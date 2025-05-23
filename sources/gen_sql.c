/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_GEN_SQL)

// stubs to avoid link errors,

cql_noexport void gen_init() {}
cql_export void gen_cleanup() {}
cql_noexport void gen_misc_attrs_to_stdout(ast_node *ast) {}
cql_noexport void gen_to_stdout(ast_node *ast, gen_func fn) {}
cql_noexport void gen_one_stmt_to_stdout(ast_node *ast) {}
cql_noexport void gen_stmt_list_to_stdout(ast_node *ast) {}

#else

// (re)generate equivalent SQL to what we parsed
// validate the tree shape in painful detail as we go

#include "cql.h"
#include "cg_common.h"
#include "ast.h"
#include "gen_sql.h"
#include "sem.h"
#include "charbuf.h"
#include "symtab.h"
#include "encoders.h"
#include <string.h>
#include <stdlib.h>

// for dispatching expression types
typedef struct gen_expr_dispatch {
  void (*func)(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new);
  CSTR str;
  int32_t pri_new;
} gen_expr_dispatch;

static symtab *gen_stmts;
static symtab *gen_exprs;
static symtab *gen_macros;
static charbuf *gen_output;
static gen_sql_callbacks *gen_callbacks = NULL;
static symtab *used_alias_syms = NULL;

// forward references for things that appear out of order or mutually call each other
static void gen_select_core_list(ast_node *ast);
static void gen_groupby_list(ast_node *_Nonnull ast);
static void gen_orderby_list(ast_node *_Nonnull ast);
static void gen_stmt_list(ast_node *_Nullable ast);
static void gen_expr(ast_node *_Nonnull ast, int32_t pri);
static void gen_version_attrs(ast_node *_Nullable ast);
static void gen_col_def(ast_node *_Nonnull ast);
static void gen_query_parts(ast_node *ast);
static void gen_select_stmt(ast_node *_Nonnull ast);
static void gen_opt_where(ast_node *ast);
static void gen_opt_orderby(ast_node *ast);
static void gen_shape_arg(ast_node *ast);
static void gen_insert_list(ast_node *_Nullable ast);
static void gen_column_spec(ast_node *ast);
static void gen_from_shape(ast_node *ast);
static void gen_opt_filter_clause(ast_node *ast);
static void gen_if_not_exists(ast_node *ast, bool_t if_not_exist);
static void gen_shape_def(ast_node *ast);
static void gen_expr_names(ast_node *ast);
static void gen_conflict_clause(ast_node *ast);
static void gen_call_stmt(ast_node *ast);
static void gen_shared_cte(ast_node *ast);
static bool_t gen_found_set_kind(ast_node *ast, void *context, charbuf *buffer);
static void gen_cte_table(ast_node *ast);
static void gen_cte_tables(ast_node *ast, CSTR prefix);
static void gen_select_expr_list(ast_node *ast);
static void gen_expr_at_id(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new);
static void gen_select_expr(ast_node *ast);
static void gen_arg_list(ast_node *ast);
static void gen_any_macro_ref(ast_node *ast);
static void gen_stmt_list_flat(ast_node *root);

static int32_t gen_indent = 0;
static int32_t pending_indent = 0;

#define GEN_BEGIN_INDENT(name, level) \
  int32_t name##_level = gen_indent; \
  gen_indent += level; \
  pending_indent = gen_indent;

#define GEN_END_INDENT(name) \
  gen_indent = name##_level; \
  if (pending_indent > gen_indent) pending_indent = gen_indent;

cql_noexport void gen_printf(const char *format, ...) {
 CHARBUF_OPEN(tmp);
 va_list args;
 va_start(args, format);
 vbprintf(&tmp, format, args);
 va_end(args);

 for (CSTR p = tmp.ptr; *p; p++) {
    if (*p != '\n') {
      for (int32_t i = 0; i < pending_indent; i++) bputc(gen_output, ' ');
      pending_indent = 0;
    }
    bputc(gen_output, *p);
    if (*p == '\n') {
      pending_indent = gen_indent;
    }
 }
 CHARBUF_CLOSE(tmp);
}

void bprint_maybe_qname(charbuf *output, CSTR subject) {
  if (is_qname(subject)) {
    cg_decode_qstr(output, subject);
  }
  else {
    bprintf(output, "%s", subject);
  }
}

static void gen_literal(CSTR literal) {
  for (int32_t i = 0; i < pending_indent; i++) bputc(gen_output, ' ');
  pending_indent = 0;
  bprintf(gen_output, "%s", literal);
}

cql_noexport void gen_to_stdout(ast_node *ast, gen_func fn) {
  gen_callbacks = NULL;
  charbuf *gen_saved = gen_output;
  CHARBUF_OPEN(sql_out);
  gen_set_output_buffer(&sql_out);
  (*fn)(ast);
  cql_output("%s", sql_out.ptr);
  CHARBUF_CLOSE(sql_out);
  gen_output = gen_saved;
}

static bool_t suppress_attributes() {
  return gen_callbacks && (gen_callbacks->mode == gen_mode_sql || gen_callbacks->mode == gen_mode_no_annotations);
}

static bool_t for_sqlite() {
  return gen_callbacks && gen_callbacks->mode == gen_mode_sql;
}

cql_noexport void gen_stmt_list_to_stdout(ast_node *ast) {
  gen_to_stdout(ast, gen_stmt_list);
}

cql_noexport void gen_one_stmt_to_stdout(ast_node *ast) {
  gen_to_stdout(ast, gen_one_stmt);
  bool_t prep = is_ast_ifdef_stmt(ast) || is_ast_ifndef_stmt(ast);
  if (prep) cql_output("\n"); else cql_output(";\n");
}

cql_noexport void gen_misc_attrs_to_stdout(ast_node *ast) {
  gen_to_stdout(ast, gen_misc_attrs);
}

cql_noexport void gen_with_callbacks(ast_node *ast, gen_func fn, gen_sql_callbacks *_callbacks) {
  gen_callbacks = _callbacks;
  (*fn)(ast);
  gen_callbacks = NULL;
}

cql_noexport void gen_col_def_with_callbacks(ast_node *ast, gen_sql_callbacks *_callbacks) {
  gen_with_callbacks(ast, gen_col_def, _callbacks);
}

cql_noexport void gen_statement_with_callbacks(ast_node *ast, gen_sql_callbacks *_callbacks) {
  // works for statements or statement lists
  if (is_ast_stmt_list(ast)) {
    gen_stmt_level = -1;  // the first statement list does not indent
    gen_with_callbacks(ast, gen_stmt_list, _callbacks);
  }
  else {
    gen_stmt_level = 0;  // nested statement lists will indent
    gen_with_callbacks(ast, gen_one_stmt, _callbacks);
  }
}

cql_noexport void gen_statement_and_attributes_with_callbacks(ast_node *ast, gen_sql_callbacks *_callbacks) {
  gen_stmt_level = 0;  // nested statement lists will indent
  gen_with_callbacks(ast, gen_one_stmt_and_misc_attrs, _callbacks);
}

cql_noexport void gen_set_output_buffer(struct charbuf *buffer) {
  gen_output = buffer;
}

cql_noexport void gen_get_state(gen_sql_state *state) {
  state->gen_output = gen_output;
  state->gen_callbacks = gen_callbacks;
  state->used_alias_syms = used_alias_syms;
}

cql_noexport void gen_set_state(gen_sql_state *state) {
  gen_output = state->gen_output;
  gen_callbacks = state->gen_callbacks;
  used_alias_syms = state->used_alias_syms;
}

static void gen_name_ex(CSTR name, bool_t is_qid) {
  CHARBUF_OPEN(tmp);
  if (is_qid) {
    if (!for_sqlite()) {
      cg_decode_qstr(&tmp, name);
      gen_printf("%s", tmp.ptr);
    }
    else {
      cg_unquote_encoded_qstr(&tmp, name);
      gen_printf("[%s]", tmp.ptr);
    }
  }
  else {
    gen_printf("%s", name);
  }
  CHARBUF_CLOSE(tmp);
}

static void gen_name(ast_node *ast) {
  if (is_ast_at_id(ast)) {
    gen_expr_at_id(ast, "", 0, 0);
    return;
  }

  EXTRACT_STRING(name, ast);
  gen_name_ex(name, is_qid(ast));
}

cql_noexport void gen_name_for_msg(ast_node *name_ast, charbuf *output) {
  charbuf *saved = gen_output;
  gen_output = output;
  gen_name(name_ast);
  gen_output = saved;
}

static void gen_sptr_name(sem_struct *sptr, uint32_t i) {
  gen_name_ex(sptr->names[i], !!(sptr->semtypes[i] & SEM_TYPE_QID));
}

static void gen_constraint_name(ast_node *ast) {
  EXTRACT_NAME_AST(name_ast, ast);
  gen_printf("CONSTRAINT ");
  gen_name(name_ast);
  gen_printf(" ");
}

static void gen_name_list(ast_node *list) {
  Contract(is_ast_name_list(list));

  for (ast_node *item = list; item; item = item->right) {
    gen_name(item->left);
    if (item->right) {
      gen_printf(", ");
    }
  }
}

cql_noexport void gen_misc_attr_value_list(ast_node *ast) {
  Contract(is_ast_misc_attr_value_list(ast));
  for (ast_node *item = ast; item; item = item->right) {
    gen_misc_attr_value(item->left);
    if (item->right) {
      gen_printf(", ");
    }
  }
}

cql_noexport void gen_misc_attr_value(ast_node *ast) {
  if (is_ast_misc_attr_value_list(ast)) {
    gen_printf("(");
    gen_misc_attr_value_list(ast);
    gen_printf(")");
  }
  else {
    gen_root_expr(ast);
  }
}

static void gen_misc_attr(ast_node *ast) {
  Contract(is_ast_misc_attr(ast));

  bool_t is_cql =
    is_ast_dot(ast->left) &&
    is_ast_str(ast->left->left) &&
    !StrCaseCmp("cql", ((str_ast_node *)(ast->left->left))->value);

  CSTR attr_open = "[[";
  CSTR attr_close = "]]";

  if (gen_callbacks && gen_callbacks->escape_attributes_for_lua) {
    // in Lua comments ]] ends a comment, so we need the attribute to not match that
    // fortunately "[ [ builtin ] ]" is also valid syntax but in any case it's
    // just a comment
    attr_open = "[ [ ";
    attr_close = " ] ]";
  }

  if (is_cql) {
    gen_printf("%s", attr_open);
    gen_name(ast->left->right);
  }
  else {
    gen_printf("@ATTRIBUTE(");
    if (is_ast_dot(ast->left)) {
      gen_name(ast->left->left);
      gen_printf(":");
      gen_name(ast->left->right);
    }
    else {
      gen_name(ast->left);
    }
  }
  if (ast->right) {
    gen_printf("=");
    gen_misc_attr_value(ast->right);
  }
  if (is_cql) {
    gen_printf("%s\n", attr_close);
  }
  else {
    gen_printf(")\n");
  }
}

cql_noexport void gen_misc_attrs(ast_node *list) {
  Contract(is_ast_misc_attrs(list));

  // misc attributes don't go into the output if we are writing for Sqlite
  if (suppress_attributes()) {
    return;
  }

  for (ast_node *item = list; item; item = item->right) {
    gen_misc_attr(item->left);
  }
}

static void gen_type_kind(CSTR name) {
  // we don't always have an ast node for this, we make a fake one for the callback
  str_ast_node sast = {
    .type = k_ast_str,
    .value = name,
    .filename = "none"
  };

  ast_node *ast = (ast_node *)&sast;

  bool_t suppress = false;
  if (gen_callbacks) {
    gen_sql_callback callback = gen_callbacks->set_kind_callback;
    if (callback && ends_in_set(name)) {
      CHARBUF_OPEN(buf);
      suppress = callback(ast, gen_callbacks->set_kind_context, &buf);
      gen_printf("%s", buf.ptr);
      CHARBUF_CLOSE(buf);
    }
  }

  if (!suppress) {
    gen_printf("<%s>", name);
  }
}

static void gen_not_null() {
  if (for_sqlite()) {
    gen_printf(" NOT NULL");
  }
  else {
    gen_printf("!");
  }
}

void gen_data_type(ast_node *ast) {
  if (is_ast_create_data_type(ast)) {
    gen_printf("CREATE ");
    gen_data_type(ast->left);
    return;
  }
  else if (is_ast_notnull(ast)) {
    gen_data_type(ast->left);
    gen_not_null();
    return;
  }
  else if (is_ast_sensitive_attr(ast)) {
    gen_data_type(ast->left);
    if (!for_sqlite()) {
      gen_printf(" @SENSITIVE");
    }
    return;
  }
  else if (is_ast_type_int(ast)) {
    if (for_sqlite()) {
      // we could use INT here but there is schema out
      // there that won't match if we do, seems risky
      // to change the canonical SQL output
      gen_printf("INTEGER");
    }
    else {
      gen_printf("INT");
    }
  }
  else if (is_ast_type_text(ast)) {
    gen_printf("TEXT");
  }
  else if (is_ast_type_blob(ast)) {
    gen_printf("BLOB");
  }
  else if (is_ast_type_object(ast)) {
    gen_printf("OBJECT");
  }
  else if (is_ast_type_long(ast)) {
    if (for_sqlite()) {
      // we could use INT here but there is schema out
      // there that won't match if we do, seems risky
      // to change the canonical SQL output
      gen_printf("LONG_INT");
    }
    else {
      gen_printf("LONG");
    }
  }
  else if (is_ast_type_real(ast)) {
    gen_printf("REAL");
  }
  else if (is_ast_type_bool(ast)) {
    gen_printf("BOOL");
  }
  else if (is_ast_type_cursor(ast)) {
    gen_printf("CURSOR");
  }
  else {
    bool_t suppress = false;
    if (gen_callbacks) {
      gen_sql_callback callback = gen_callbacks->named_type_callback;
      if (callback) {
        CHARBUF_OPEN(buf);
        suppress = callback(ast, gen_callbacks->named_type_context, &buf);
        gen_printf("%s", buf.ptr);
        CHARBUF_CLOSE(buf);
        return;
      }
    }
    if (!suppress) {
      EXTRACT_NAME_AST(name_ast, ast);
      gen_name(name_ast);
    }
    return;
  }

  if (!for_sqlite()) {
    if (ast->left) {
      EXTRACT_STRING(name, ast->left);
      gen_type_kind(name);
    }
  }
}

static void gen_indexed_column(ast_node *ast) {
  Contract(is_ast_indexed_column(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);

  gen_root_expr(expr);
  if (is_ast_asc(ast->right)) {
    gen_printf(" ASC");
  }
  else if (is_ast_desc(ast->right)) {
    gen_printf(" DESC");
  }
}

static void gen_indexed_columns(ast_node *ast) {
  Contract(is_ast_indexed_columns(ast));
  for (ast_node *item = ast; item; item = item->right) {
    gen_indexed_column(item->left);
    if (item->right) {
      gen_printf(", ");
    }
  }
}

static void gen_create_index_stmt(ast_node *ast) {
  Contract(is_ast_create_index_stmt(ast));
  EXTRACT_NOTNULL(create_index_on_list, ast->left);
  EXTRACT_NOTNULL(flags_names_attrs, ast->right);
  EXTRACT_NOTNULL(connector, flags_names_attrs->right);
  EXTRACT_NOTNULL(index_names_and_attrs, connector->left);
  EXTRACT_OPTION(flags, flags_names_attrs->left);
  EXTRACT_NOTNULL(indexed_columns, index_names_and_attrs->left);
  EXTRACT(opt_where, index_names_and_attrs->right);
  EXTRACT_ANY(attrs, connector->right);
  EXTRACT_NAME_AST(index_name_ast, create_index_on_list->left);
  EXTRACT_NAME_AST(table_name_ast, create_index_on_list->right);

  gen_printf("CREATE ");
  if (flags & INDEX_UNIQUE) {
    gen_printf("UNIQUE ");
  }
  gen_printf("INDEX ");
  gen_if_not_exists(ast, !!(flags & INDEX_IFNE));
  gen_name(index_name_ast);
  gen_printf(" ON ");
  gen_name(table_name_ast);
  gen_printf(" (");
  gen_indexed_columns(indexed_columns);
  gen_printf(")");
  if (opt_where) {
    gen_printf("\n");
    gen_opt_where(opt_where);
  }
  gen_version_attrs(attrs);
}

static void gen_unq_def(ast_node *def) {
  Contract(is_ast_unq_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);
  EXTRACT_ANY(conflict_clause, indexed_columns_conflict_clause->right);

  if (def->left) {
    gen_constraint_name(def->left);
  }

  gen_printf("UNIQUE (");
  gen_indexed_columns(indexed_columns);
  gen_printf(")");
  if (conflict_clause) {
    gen_conflict_clause(conflict_clause);
  }
}

static void gen_check_def(ast_node *def) {
  Contract(is_ast_check_def(def));
  if (def->left) {
    gen_constraint_name(def->left);
  }

  EXTRACT_ANY_NOTNULL(expr, def->right);
  gen_printf("CHECK (");
  gen_root_expr(expr);
  gen_printf(")");
}

cql_noexport void gen_fk_action(int32_t action) {
  switch (action) {
    case FK_SET_NULL:
      gen_printf("SET NULL");
      break;
    case FK_SET_DEFAULT:
      gen_printf("SET DEFAULT");
      break;
    case FK_CASCADE:
      gen_printf("CASCADE");
      break;
    case FK_RESTRICT:
      gen_printf("RESTRICT");
      break;
    default:
      // this is all that's left, it better be this...
      Contract(action == FK_NO_ACTION);
      gen_printf("NO ACTION");
      break;
  }
}

static void gen_fk_flags(int32_t flags) {
  if (flags) {
    gen_printf(" ");
  }

  int32_t action = (flags & FK_ON_UPDATE) >> 4;

  if (action) {
    gen_printf("ON UPDATE ");
    gen_fk_action(action);
    if (flags & (FK_ON_DELETE|FK_DEFERRABLES)) {
      gen_printf(" ");
    }
  }

  action = (flags & FK_ON_DELETE);
  if (action) {
    gen_printf("ON DELETE ");
    gen_fk_action(action);
    if (flags & FK_DEFERRABLES) {
      gen_printf(" ");
    }
  }

  if (flags & FK_DEFERRABLES) {
    Contract(flags & (FK_DEFERRABLE|FK_NOT_DEFERRABLE));
    if (flags & FK_DEFERRABLE) {
      Contract(!(flags & FK_NOT_DEFERRABLE));
      gen_printf("DEFERRABLE");
    }
    else {
      gen_printf("NOT DEFERRABLE");
    }
    if (flags & FK_INITIALLY_IMMEDIATE) {
      Contract(!(flags & FK_INITIALLY_DEFERRED));
      gen_printf(" INITIALLY IMMEDIATE");
    }
    else if (flags & FK_INITIALLY_DEFERRED) {
      gen_printf(" INITIALLY DEFERRED");
    }
  }
}

static void gen_fk_target_options(ast_node *ast) {
  Contract(is_ast_fk_target_options(ast));
  EXTRACT_NOTNULL(fk_target, ast->left);
  EXTRACT_OPTION(flags, ast->right);
  EXTRACT_NAME_AST(table_name_ast, fk_target->left);
  EXTRACT_NAMED_NOTNULL(ref_list, name_list, fk_target->right);

  gen_printf("REFERENCES ");
  gen_name(table_name_ast);
  gen_printf(" (");
  gen_name_list(ref_list);
  gen_printf(")");
  gen_fk_flags(flags);
}

static void gen_fk_def(ast_node *def) {
  Contract(is_ast_fk_def(def));
  EXTRACT(fk_info, def->right);
  EXTRACT_NAMED_NOTNULL(src_list, name_list, fk_info->left);
  EXTRACT_NOTNULL(fk_target_options, fk_info->right);

  if (def->left) {
    gen_constraint_name(def->left);
  }

  gen_printf("FOREIGN KEY (");
  gen_name_list(src_list);
  gen_printf(") ");
  gen_fk_target_options(fk_target_options);
}

static void gen_conflict_clause(ast_node *ast) {
  Contract(is_ast_int(ast));
  EXTRACT_OPTION(conflict_clause_opt, ast);

  gen_printf(" ON CONFLICT ");
  switch (conflict_clause_opt) {
    case ON_CONFLICT_ROLLBACK:
      gen_printf("ROLLBACK");
      break;
    case ON_CONFLICT_ABORT:
      gen_printf("ABORT");
      break;
    case ON_CONFLICT_FAIL:
      gen_printf("FAIL");
      break;
    case ON_CONFLICT_IGNORE:
      gen_printf("IGNORE");
      break;
    case ON_CONFLICT_REPLACE:
      gen_printf("REPLACE");
      break;
  }
}

static void gen_pk_def(ast_node *def) {
  Contract(is_ast_pk_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);
  EXTRACT_ANY(conflict_clause, indexed_columns_conflict_clause->right);

  if (def->left) {
    gen_constraint_name(def->left);
  }

  gen_printf("PRIMARY KEY (");
  gen_indexed_columns(indexed_columns);
  gen_printf(")");
  if (conflict_clause) {
    gen_conflict_clause(conflict_clause);
  }
}

static void gen_version_and_proc(ast_node *ast)
{
  Contract(is_ast_version_annotation(ast));
  EXTRACT_OPTION(vers, ast->left);
  gen_printf("%d", vers);
  if (ast->right) {
    if (is_ast_dot(ast->right)) {
      EXTRACT_NOTNULL(dot, ast->right);
      EXTRACT_STRING(lhs, dot->left);
      EXTRACT_STRING(rhs, dot->right);

      gen_printf(", %s:%s", lhs, rhs);
    }
    else
    {
      EXTRACT_STRING(name, ast->right);
      gen_printf(", %s", name);
    }
  }
}

static void gen_recreate_attr(ast_node *attr) {
  Contract (is_ast_recreate_attr(attr));
  if (!suppress_attributes()) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(" @RECREATE");
    if (attr->left) {
      EXTRACT_STRING(group_name, attr->left);
      gen_printf("(%s)", group_name);
    }
  }
}

static void gen_create_attr(ast_node *attr) {
  Contract (is_ast_create_attr(attr));
  if (!suppress_attributes()) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(" @CREATE(");
    gen_version_and_proc(attr->left);
    gen_printf(")");
  }
}

static void gen_delete_attr(ast_node *attr) {
  Contract (is_ast_delete_attr(attr));

  // attributes do not appear when writing out commands for Sqlite
  if (!suppress_attributes()) {
    gen_printf(" @DELETE");
    if (attr->left) {
      gen_printf("(");
      gen_version_and_proc(attr->left);
      gen_printf(")");
    }
  }
}

static void gen_sensitive_attr(ast_node *attr) {
  Contract (is_ast_sensitive_attr(attr));
  if (!for_sqlite()) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(" @SENSITIVE");
  }
}

static void gen_col_attrs(ast_node *_Nullable attrs) {
  for (ast_node *attr = attrs; attr; attr = attr->right) {
    if (is_ast_create_attr(attr)) {
      gen_create_attr(attr);
    }
    else if (is_ast_sensitive_attr(attr)) {
      gen_sensitive_attr(attr);
    }
    else if (is_ast_delete_attr(attr)) {
      gen_delete_attr(attr);
    }
    else if (is_ast_col_attrs_not_null(attr)) {
      gen_not_null();
      EXTRACT_ANY(conflict_clause, attr->left);
      if (conflict_clause) {
        gen_conflict_clause(conflict_clause);
      }
    }
    else if (is_ast_col_attrs_pk(attr)) {
      EXTRACT_NOTNULL(autoinc_and_conflict_clause, attr->left);
      EXTRACT(col_attrs_autoinc, autoinc_and_conflict_clause->left);
      EXTRACT_ANY(conflict_clause, autoinc_and_conflict_clause->right);

      gen_printf(" PRIMARY KEY");
      if (conflict_clause) {
        gen_conflict_clause(conflict_clause);
      }
      if (col_attrs_autoinc) {
        gen_printf(" AUTOINCREMENT");
      }
    }
    else if (is_ast_col_attrs_unique(attr)) {
      gen_printf(" UNIQUE");
      if (attr->left) {
        gen_conflict_clause(attr->left);
      }
    }
    else if (is_ast_col_attrs_hidden(attr)) {
      gen_printf(" HIDDEN");
    }
    else if (is_ast_col_attrs_fk(attr)) {
      gen_printf(" ");
      gen_fk_target_options(attr->left);
    }
    else if (is_ast_col_attrs_check(attr)) {
      gen_printf(" CHECK(");
      gen_root_expr(attr->left);
      gen_printf(") ");
    }
    else if (is_ast_col_attrs_collate(attr)) {
      gen_printf(" COLLATE ");
      gen_root_expr(attr->left);
    }
    else {
      Contract(is_ast_col_attrs_default(attr));
      gen_printf(" DEFAULT ");
      gen_root_expr(attr->left);
    }
  }
}

static void gen_col_def(ast_node *def) {
  Contract(is_ast_col_def(def));
  EXTRACT_NOTNULL(col_def_type_attrs, def->left);
  EXTRACT(misc_attrs, def->right);
  EXTRACT_ANY(attrs, col_def_type_attrs->right);
  EXTRACT_NOTNULL(col_def_name_type, col_def_type_attrs->left);
  EXTRACT_NAME_AST(name_ast, col_def_name_type->left);
  EXTRACT_ANY_NOTNULL(data_type, col_def_name_type->right);

  if (misc_attrs) {
    gen_misc_attrs(misc_attrs);
  }

  gen_name(name_ast);
  gen_printf(" ");

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // with no SEM we can't do this conversion, we're just doing vanilla echos
  gen_data_type(data_type);
#else
  if (gen_callbacks && gen_callbacks->long_to_int_conv && def->sem && (def->sem->sem_type & SEM_TYPE_AUTOINCREMENT)) {
    // semantic checking must have already validated that this is either an integer or long_integer
    sem_t core_type = core_type_of(def->sem->sem_type);
    Contract(core_type == SEM_TYPE_INTEGER || core_type == SEM_TYPE_LONG_INTEGER);
    gen_printf("INTEGER");
  }
  else {
    gen_data_type(data_type);
  }
#endif
  gen_col_attrs(attrs);
}

cql_noexport bool_t eval_column_callback(ast_node *ast) {
  Contract(is_ast_col_def(ast));
  bool_t suppress = 0;

  if (gen_callbacks && gen_callbacks->col_def_callback && ast->sem) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks->col_def_callback(ast, gen_callbacks->col_def_context, &buf);
    gen_printf("%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }

  return suppress;
}

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)

// if SEM isn't in the picture there are no "variables"
bool_t eval_variables_callback(ast_node *ast) {
  return false;
}

#else

bool_t eval_variables_callback(ast_node *ast) {
  bool_t suppress = 0;
  if (gen_callbacks && gen_callbacks->variables_callback && ast->sem && is_variable(ast->sem->sem_type)) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks->variables_callback(ast, gen_callbacks->variables_context, &buf);
    gen_printf("%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }
  return suppress;
}
#endif

cql_noexport void gen_col_or_key(ast_node *def) {
  if (is_ast_col_def(def)) {
    gen_col_def(def);
  }
  else if (is_ast_pk_def(def)) {
    gen_pk_def(def);
  }
  else if (is_ast_fk_def(def)) {
    gen_fk_def(def);
  }
  else if (is_ast_shape_def(def)) {
    gen_shape_def(def);
  }
  else if (is_ast_check_def(def)) {
    gen_check_def(def);
  }
  else {
    Contract(is_ast_unq_def(def));
    gen_unq_def(def);
  }
}

cql_noexport void gen_col_key_list(ast_node *list) {
  Contract(is_ast_col_key_list(list));
  bool_t need_comma = 0;

  GEN_BEGIN_INDENT(coldefs, 2);

  for (ast_node *item = list; item; item = item->right) {
    EXTRACT_ANY_NOTNULL(def, item->left);

    // give the callback system a chance to suppress columns that are not in this version
    if (is_ast_col_def(def) && eval_column_callback(def)) {
      continue;
    }

    if (need_comma) {
      gen_printf(",\n");
    }
    need_comma = 1;

    gen_col_or_key(def);
  }
  GEN_END_INDENT(coldefs);
}

static void gen_select_opts(ast_node *ast) {
  Contract(is_ast_select_opts(ast));
  EXTRACT_ANY_NOTNULL(opt, ast->left);

  if (is_ast_all(opt)) {
    gen_printf(" ALL");
  }
  else if (is_ast_distinct(opt)) {
    gen_printf(" DISTINCT");
  }
  else {
    Contract(is_ast_distinctrow(opt));
    gen_printf(" DISTINCTROW");
  }
}

static void gen_binary_no_spaces(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf("%s", op);
  if (is_ast_reverse_apply_poly_args(ast)) {
    gen_printf("(");
    gen_arg_list(ast->right);
    gen_printf(")");
  }
  else {
    gen_expr(ast->right, pri_new + 1);
  }
  if (pri_new < pri) gen_printf(")");
}

static void gen_binary(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {

  // We add parens if our priority is less than the parent priority
  // meaning something like this:
  // * we're a + node, our parent is a * node
  // * we need parens because the tree specifies that the + happens before the *
  //
  // Also, grouping of equal operators is left to right
  // so for so if our right child is the same precedence as us
  // that means there were parens there in the original expression
  // e.g.  3+(4+7);
  // effectively it's like we're one binding strength higher for our right child
  // so we call it with pri_new + 1.  If it's equal to us it must emit parens

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" %s ", op);
  gen_expr(ast->right, pri_new + 1);
  if (pri_new < pri) gen_printf(")");
}

static void gen_unary(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf("(");
  gen_printf("%s", op);
  gen_expr(ast->left, pri_new);
  if (pri_new < pri) gen_printf(")");
}

static void gen_postfix(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" %s", op);
  if (pri_new < pri) gen_printf(")");
}

static void gen_expr_const(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  gen_printf("CONST(");
  gen_expr(ast->left, pri_new);
  gen_printf(")");
}

static void gen_uminus(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf("(");
  gen_printf("%s", op);

  // we don't ever want -- in the output because that's a comment
  CHARBUF_OPEN(tmp);
  charbuf *saved = gen_output;
  gen_output = &tmp;
  gen_expr(ast->left, pri_new);
  gen_output = saved;

  if (tmp.ptr[0] == '-') {
    gen_printf(" ");
  }

  gen_printf("%s", tmp.ptr);
  CHARBUF_CLOSE(tmp);

  if (pri_new < pri) gen_printf(")");
}

static void gen_concat(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_concat(ast));

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" %s ", op);
  gen_expr(ast->right, pri_new);
  if (pri_new < pri) gen_printf(")");
}

static void gen_jex1(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_jex1(ast));

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" %s ", op);
  gen_expr(ast->right, pri_new);
  if (pri_new < pri) gen_printf(")");
}

static void gen_jex2(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_jex2(ast));

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" %s ", op);
  if (!for_sqlite()) {
    gen_printf("~");
    gen_data_type(ast->right->left);
    gen_printf("~ ");
  }
  gen_expr(ast->right->right, pri_new);
  if (pri_new < pri) gen_printf(")");
}

static void gen_arg_expr(ast_node *ast) {
  if (is_ast_star(ast)) {
    gen_printf("*");
  }
  else if (is_ast_from_shape(ast)) {
    gen_shape_arg(ast);
  }
  else {
    gen_root_expr(ast);
  }
}

static void gen_expr_exists(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_exists_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);

  gen_printf("EXISTS (");
  GEN_BEGIN_INDENT(sel, 2);
    pending_indent = 0;
    gen_select_stmt(select_stmt);
  GEN_END_INDENT(sel);
  gen_printf(")");
}

static void gen_arg_list(ast_node *ast) {
  while (ast) {
    gen_arg_expr(ast->left);
    if (ast->right) {
      gen_printf(", ");
    }
    ast = ast->right;
  }
}

static void gen_expr_list(ast_node *ast) {
  while (ast) {
    gen_root_expr(ast->left);
    if (ast->right) {
      gen_printf(", ");
    }
    ast = ast->right;
  }
}

static void gen_shape_arg(ast_node *ast) {
  Contract(is_ast_from_shape(ast));
  EXTRACT_STRING(shape, ast->left);
  gen_printf("FROM %s", shape);
  if (ast->right) {
    gen_printf(" ");
    gen_shape_def(ast->right);
  }
}

static void gen_case_list(ast_node *ast) {
  Contract(is_ast_case_list(ast));

  while (ast) {
    EXTRACT_NOTNULL(when, ast->left);
    EXTRACT_ANY_NOTNULL(case_expr, when->left);
    EXTRACT_ANY_NOTNULL(then_expr, when->right);

    // additional parens never needed because WHEN/THEN act like parens
    gen_printf("WHEN ");
    gen_root_expr(case_expr);
    gen_printf(" THEN ");
    gen_root_expr(then_expr);
    gen_printf("\n");

    ast = ast->right;
  }
}

static void gen_expr_table_star(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_table_star(ast));
  gen_name(ast->left);
  gen_printf(".*");
}

static void gen_expr_star(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_star(ast));
  gen_printf("*");
}

static void gen_expr_num(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_num(ast));
  EXTRACT_NUM_VALUE(val, ast);
  EXTRACT_NUM_TYPE(num_type, ast);
  Contract(val);

  if (has_hex_prefix(val) && gen_callbacks && gen_callbacks->convert_hex) {
    int64_t v = strtol(val, NULL, 16);
    gen_printf("%lld", (llint_t)v);
  }
  else {
    if (for_sqlite() || num_type != NUM_BOOL) {
      gen_printf("%s", val);
    }
    else {
      if (!strcmp(val, "0")) {
        gen_printf("FALSE");
      }
      else {
        gen_printf("TRUE");
      }
    }
  }

  if (for_sqlite()) {
    return;
  }

  if (num_type == NUM_LONG) {
    gen_printf("L");
  }
}

static void gen_expr_blob(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_blob(ast));
  EXTRACT_BLOBTEXT(str, ast);

  // blob literals are easy, we just emit them, there's no conversion or anything like that
  gen_printf("%s", str);
}

static void gen_macro_args(ast_node *ast) {
  for ( ; ast; ast = ast->right) {
    EXTRACT_ANY_NOTNULL(arg, ast->left);
    if (is_any_macro_ref(arg->left)) {
      gen_any_macro_ref(arg->left);
    }
    else if (is_ast_expr_macro_arg(arg)) {
      gen_root_expr(arg->left);
    }
    else if (is_ast_query_parts_macro_arg(arg)) {
      gen_printf("FROM(");
      gen_query_parts(arg->left);
      gen_printf(")");
    }
    else if (is_ast_select_core_macro_arg(arg)) {
      gen_printf("ROWS(");
      gen_select_core_list(arg->left);
      gen_printf(")");
    }
    else if (is_ast_select_expr_macro_arg(arg)) {
      gen_printf("SELECT(");
      gen_select_expr_list(arg->left);
      gen_printf(")");
    }
    else if (is_ast_cte_tables_macro_arg(arg)) {
      gen_printf("WITH(\n");
      GEN_BEGIN_INDENT(tables, 2);
        gen_cte_tables(arg->left, "");
      GEN_END_INDENT(tables);
      gen_printf(")");
    }
    else {
      Contract(is_ast_stmt_list_macro_arg(arg));
      gen_printf("\nBEGIN\n");
      gen_stmt_list(arg->left);
      gen_printf("END");
    }
    if (ast->right) {
      gen_printf(", ");
    }
  }
}

static void gen_text_args(ast_node *ast) {
  for (; ast; ast = ast->right) {
    Contract(is_ast_text_args(ast));
    EXTRACT_ANY_NOTNULL(txt, ast->left);

    if (is_any_macro_ref(txt)) {
      gen_any_macro_ref(txt);
    }
    else {
      gen_root_expr(txt);
    }
    if (ast->right) {
      gen_printf(", ");
    }
  }
}

static void gen_expr_macro_text(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(ast->left);

  gen_printf("@TEXT(");
  gen_text_args(ast->left);
  gen_printf(")");
}

cql_noexport void gen_any_text_arg(ast_node *ast) {
  if (is_ast_cte_tables(ast)) {
    gen_cte_tables(ast, "");
  }
  else if (is_ast_table_or_subquery_list(ast) || is_ast_join_clause(ast)) {
    gen_query_parts(ast);
  }
  else if (is_ast_stmt_list(ast)) {
    gen_stmt_list(ast);
  }
  else if (is_ast_select_core_list(ast)) {
    gen_select_core_list(ast);
  }
  else if (is_ast_select_expr_list(ast)) {
    gen_select_expr_list(ast);
  }
  else {
    gen_root_expr(ast);
  }
}

// this is used to token paste an identifier
static void gen_expr_at_id(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_at_id(ast));
  EXTRACT_NOTNULL(text_args, ast->left);

  if (is_ast_str(text_args->left)) {
    EXTRACT_STRING(arg1, text_args->left);
    if (!strcmp("@TMP", arg1)) {
       gen_printf("@TMP(");
       gen_text_args(text_args->right);
       gen_printf(")");
       return;
    }
  }

  gen_printf("@ID(");
  gen_text_args(ast->left);
  gen_printf(")");
}

static void gen_expr_str(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_str(ast));
  EXTRACT_STRING(str, ast);

  if (is_strlit(ast)) {
    str_ast_node *asts = (str_ast_node *)ast;
    if (asts->str_type != STRING_TYPE_C || for_sqlite()) {
      // Note: str is the lexeme, so it is either still quoted and escaped
      // or if it was a c string literal it was already normalized to SQL form.
      // In both cases we can just print.
      gen_literal(str);
    }
    else {
      // If was originally a c string literal re-encode it for echo output
      // so that it looks the way it was given to us.  This is so that when we
      // echo the SQL back for say test output C string literal forms come out
      // just as they were given to us.
      CHARBUF_OPEN(decoded);
      CHARBUF_OPEN(encoded);
      cg_decode_string_literal(str, &decoded);
      cg_encode_c_string_literal(decoded.ptr, &encoded);

      gen_literal(encoded.ptr);
      CHARBUF_CLOSE(encoded);
      CHARBUF_CLOSE(decoded);
    }
  }
  else {
    if (!eval_variables_callback(ast)) {
      // an identifier
      gen_name(ast);
    }
  }
}

static void gen_expr_null(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_null(ast));
  gen_printf("NULL");
}

static void gen_expr_dot(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_dot(ast));

  // the general case is not variables tables etc. the notifications do not fire
  // these are rewritten away so they won't survive in the tree for later codegen
  // to use these callbacks anyway.
  if (!is_id(ast->left) || !is_id(ast->right)) {
    gen_binary_no_spaces(ast, op, pri, pri_new);
    return;
  }

  // the "_select_" scope is special name of a nested select table
  // expression that was not aliased.  This name is useless. Either
  // the columns will be unambiguous without it or it's an error
  // in any case. No point in emitting it.  It's included in the semantic
  // expansion to disambiguate any column name that matches from the same
  // local name, but it's not needed in the SQLite output.
  EXTRACT_STRING(left_name, ast->left);
  if (!strcmp("_select_", left_name) && for_sqlite()) {
    gen_name(ast->right);
    return;
  }

  EXTRACT_ANY_NOTNULL(left, ast->left);
  EXTRACT_ANY_NOTNULL(right, ast->right);

  if (eval_variables_callback(ast)) {
    return;
  }

  bool_t has_table_rename_callback = gen_callbacks && gen_callbacks->table_rename_callback;
  bool_t handled = false;

  if (has_table_rename_callback) {
    handled = gen_callbacks->table_rename_callback(left, gen_callbacks->table_rename_context, gen_output);
  }

  if (handled) {
    // the scope name has already been written by table_rename_callback
    // this is a case like:
    //
    // [[shared_fragment]]
    // proc transformer()
    // begin
    //   with
    //   source(*) like xy
    //   select source.x + 1 x, source.y + 20 y from source;
    // end;
    //
    // with T(x,y) as (call transformer() using xy as source) select T.* from T;
    //
    // In the above source.x must become xy.x and source.y must become xy.y
    //
    // At this point the correct table name is already in the stream, so left is
    // now useless. So we just throw it away.

    left = NULL;
  }

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // simple case if SEM is not available
  if (left) {
     gen_name(left);
  }
  gen_printf(".");
  gen_name(right);
#else
  bool_t is_arguments = false;

  if (is_id(left)) {
    EXTRACT_STRING(lname, left);
    is_arguments = !strcmp("ARGUMENTS", lname) && ast->sem && ast->sem->name;
  }

  if (is_arguments) {
    // special case for rewritten arguments, hide the "ARGUMENTS." stuff
    gen_printf("%s", ast->sem->name);
  }
  else if (keep_table_name_in_aliases && get_inserted_table_alias_string_override(ast)) {
    gen_printf("%s.", get_inserted_table_alias_string_override(ast));
    gen_name(right);
  }
  else {
    if (left) {
      gen_name(left);
    }
    gen_printf(".");
    gen_name(right);
  }
#endif
}

static void gen_expr_in_pred(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_in_pred(ast));
  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" IN (");
  if (ast->right == NULL) {
    /* nothing */
  }
  else if (is_ast_expr_list(ast->right)) {
    EXTRACT_NOTNULL(expr_list, ast->right);
    gen_expr_list(expr_list);
  }
  else {
    EXTRACT_ANY_NOTNULL(select_stmt, ast->right);
    gen_select_stmt(select_stmt);
  }
  gen_printf(")");

  if (pri_new < pri) gen_printf(")");
}

static void gen_expr_not_in(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_not_in(ast));
  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" NOT IN (");
  if (ast->right == NULL) {
    /* nothing */
  }
  else if (is_ast_expr_list(ast->right)) {
    EXTRACT_NOTNULL(expr_list, ast->right);
    gen_expr_list(expr_list);
  }
  else {
    EXTRACT_ANY_NOTNULL(select_stmt, ast->right);
    gen_select_stmt(select_stmt);
  }
  gen_printf(")");

  if (pri_new < pri) gen_printf(")");
}

// Append field name and type to the buffer.  Canonicalize column name to camel case.
// Many languages use camel case property names and we want to make it easy
// for them to bind to fields and generate hashes.  We have to pick some
// canonical thing so we canonicalize to camelCase.  It's not perfect but it seems
// like the best trade-off. Lots of languages wrap SQLite columns.
static void gen_append_field_desc(charbuf *tmp, CSTR c_name, sem_t sem_type) {
  cg_sym_name(cg_symbol_case_camel, tmp, "", c_name, NULL); // no prefix camel
  bputc(tmp, ':');

  if (is_nullable(sem_type)) {
    bputc(tmp, '?');
  }

  switch (core_type_of(sem_type)) {
    case SEM_TYPE_BOOL:
      bprintf(tmp, "Bool");
      break;
    case SEM_TYPE_INTEGER:
      bprintf(tmp, "Int32");
      break;
    case SEM_TYPE_LONG_INTEGER:
      bprintf(tmp, "Int64");
      break;
    case SEM_TYPE_TEXT:
      bprintf(tmp, "String");
      break;
    case SEM_TYPE_REAL:
      bprintf(tmp, "Float64");
      break;
    case SEM_TYPE_BLOB:
      bprintf(tmp, "Blob");
      break;
  }
}

// This is the same as the standard field hash but it doesn't emit it
// to an output stream and it takes ad hoc parameters, suitable for external
// callers but otherwise the same.  They could be folded but there's nothing
// to fold really other than the sha256 stuff which is already folded...
cql_noexport CSTR get_field_hash(CSTR name, sem_t sem_type) {
  CHARBUF_OPEN(tmp);
  gen_append_field_desc(&tmp, name, sem_type);
  int64_t hash = sha256_charbuf(&tmp);
  CSTR result = dup_printf("%lld", (llint_t)hash);
  CHARBUF_CLOSE(tmp);
  return result;
}

// This is only called when doing for_sqlite output which
// presumes that semantic analysis has already happened. Its
// otherwise meaningless.  There must also be live blob mappings
// again all this would be screen out much earlier if it was otherwise.
static void gen_field_hash(ast_node *ast) {
  Contract(is_ast_dot(ast));
  Contract(ast->sem);
  EXTRACT_STRING(c_name, ast->right);

  CHARBUF_OPEN(tmp);
  gen_append_field_desc(&tmp, c_name, ast->sem->sem_type);
  int64_t hash = sha256_charbuf(&tmp);
  gen_printf("%lld", (llint_t)hash);
  CHARBUF_CLOSE(tmp);
}


// patternlint-disable-next-line prefer-sized-ints-in-msys
// get CSTR out of the array and compare case insensitively
static int case_cmp(void *p1, void *p2) {
  CSTR c1 = *(CSTR*)p1;
  CSTR c2 = *(CSTR*)p2;
  // case sensitive compare for the hash canonicalization
  return strcmp(c1, c2);
}

// The type hash considers all of the not null fields plus the type name
// as the core identity of the type.
cql_noexport CSTR gen_type_hash(ast_node *ast) {
  Contract(ast);
  Contract(ast->sem);
  Contract(ast->sem->sptr);
  Contract(ast->sem->table_info);

  table_node *table_info = ast->sem->table_info;

  int64_t hash = 0;

  if (table_info->type_hash != 0) {
    // if we are so unlucky that the hash is zero, nothing bad happens
    // we just compute it every time
    hash = table_info->type_hash;
    goto cache_hit;
  }

  sem_struct *sptr = ast->sem->sptr;

  CHARBUF_OPEN(tmp);

  // Canonicalize to pascal
  cg_sym_name(cg_symbol_case_pascal, &tmp, "", sptr->struct_name, NULL); // no prefix pascal

  // we need an array of the field descriptions, first we need the count of mandatory fields
  uint32_t count = (uint32_t)table_info->notnull_count;

  // there must be a pk and it is not null so count is > 0
  Invariant(count > 0);

  // make our temporary array
  CSTR *ptrs = calloc(count, sizeof(CSTR));

  // now compute the fields we need
  for (uint32_t i = 0; i < count; i++) {
    int16_t icol = table_info->notnull_cols[i];
    CSTR c_name = sptr->names[icol];
    sem_t sem_type = sptr->semtypes[icol];

    CHARBUF_OPEN(field);
      gen_append_field_desc(&field, c_name, sem_type);
      ptrs[i] = Strdup(field.ptr);
    CHARBUF_CLOSE(field);
  }

  qsort(ptrs, count, sizeof(CSTR), (void*)case_cmp);

  // assemble the fields into one big string to hash
  bool_t first = true;
  for (uint32_t i = 0; i < count; i++) {
     bputc(&tmp, first ? ':' : ',');
     bprintf(&tmp, "%s", ptrs[i]);
     first = false;
  }

  free(ptrs);

  // printf("hashing: %s\n", tmp.ptr); -- for debugging
  hash = sha256_charbuf(&tmp);
  CHARBUF_CLOSE(tmp);

  ast->sem->table_info->type_hash = hash;

cache_hit:

  return dup_printf("%lld", (llint_t)hash);
}

static void gen_cql_blob_get_type(ast_node *ast) {
  Contract(is_ast_call(ast));
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);
  EXTRACT_STRING(t_name, first_arg(arg_list));

  cg_blob_mappings_t *map = find_backing_info(t_name);
  Contract(map);

  // special case json and jsonb, we use the extraction operator
  if (map->use_json || map->use_jsonb) {
    gen_printf("((");
    gen_root_expr(second_arg(arg_list));
    gen_printf(")->>0)");
    return;
  }

  CSTR func = map->get_key_type;
  gen_printf("%s(", func);
  gen_root_expr(second_arg(arg_list));
  gen_printf(")");
}

#define CQL_SEARCH_COL_KEYS true
#define CQL_SEARCH_COL_VALUES false

static int32_t get_table_col_offset(ast_node *create_table_stmt, CSTR name, bool_t search_for_keys) {
  // this can only be used after semantic analysis
  Contract(is_ast_create_table_stmt(create_table_stmt));
  Contract(create_table_stmt->sem);
  Contract(create_table_stmt->sem->sptr);
  Contract(create_table_stmt->sem->table_info);

  table_node *table_info = create_table_stmt->sem->table_info;
  sem_struct *sptr = create_table_stmt->sem->sptr;

  int16_t count;
  int16_t *columns;

  if (search_for_keys) {
    count = table_info->key_count;
    columns = table_info->key_cols;
  }
  else {
    count = table_info->value_count;
    columns = table_info->value_cols;
  }

  Invariant(count > 0);
  Invariant(columns);

  for (int16_t i = 0; i < count; i++) {
    int16_t icol = columns[i];
    Invariant(icol >= 0);
    Invariant((uint32_t)icol < sptr->count);

    if (!StrCaseCmp(name, sptr->names[icol])) {
      return i;
    }
  }

  return -1;
}

static void gen_cql_blob_get(ast_node *ast) {
  Contract(is_ast_call(ast));
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  ast_node *table_expr = second_arg(arg_list);

  EXTRACT_STRING(t_name, table_expr->left);
  EXTRACT_STRING(c_name, table_expr->right);

  cg_blob_mappings_t *map = find_backing_info(t_name);

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(t_name);
  Invariant(table_ast);

  int32_t pk_col_offset = get_table_col_offset(table_ast, c_name, CQL_SEARCH_COL_KEYS);

  // special case json and jsonb
  if (map->use_json || map->use_jsonb) {
    if (pk_col_offset >= 0) {
      gen_printf("((");
      gen_root_expr(first_arg(arg_list));
      gen_printf(")->>%d)", pk_col_offset+1);
    }
    else {
      gen_printf("((");
      gen_root_expr(first_arg(arg_list));
      gen_printf(")->>'$.%s')", c_name);
    }
    return;
  }

  CSTR func = pk_col_offset >= 0 ? map->get_key : map->get_val;

  bool_t offsets = pk_col_offset >= 0 ? map->key_use_offsets : map->val_use_offsets;

  gen_printf("%s(", func);
  gen_root_expr(first_arg(arg_list));

  if (offsets) {
    int32_t offset = pk_col_offset;
    if (offset < 0) {
      // if column not part of the key then we need to index the value, not the key
      offset = get_table_col_offset(table_ast, c_name, CQL_SEARCH_COL_VALUES);
      // we know it's a valid column so it's either a key or it isn't
      // since it isn't a key it must be a value
      Invariant(offset >= 0);
      Invariant(offset < table_ast->sem->table_info->value_count);
    }
    else {
      Invariant(offset < table_ast->sem->table_info->key_count);
    }
    gen_printf(", %d)", offset);
  }
  else {
    gen_printf(", ");
    gen_field_hash(table_expr);
    gen_printf(")");
  }
}

// These align directly with the sem types but they are offset by 1
// Note that these should never change because we expect there are
// backing tables with these values in them.
#define CQL_BLOB_TYPE_BOOL   0
#define CQL_BLOB_TYPE_INT32  1
#define CQL_BLOB_TYPE_INT64  2
#define CQL_BLOB_TYPE_FLOAT  3
#define CQL_BLOB_TYPE_STRING 4
#define CQL_BLOB_TYPE_BLOB   5
#define CQL_BLOB_TYPE_ENTITY 6  // this is reserved for future use

// This effectively subtracts one but it makes it clear there is a mapping
// The output values of this mapping should never change, we have to assume
// there are blobs "out there" that have these values hard coded in them
// for column type info.  That is allowed and even expected.
// In contrast, the sem_type values could be reordered, and have been.
// If they are, then this mapping must "fix" that so that the new sem_type ordering
// (which is not fixed forever) matches the blob column types (which is fixed).
static int32_t sem_type_to_blob_type[] = {
   -1, // NULL
  CQL_BLOB_TYPE_BOOL,
  CQL_BLOB_TYPE_INT32,
  CQL_BLOB_TYPE_INT64,
  CQL_BLOB_TYPE_FLOAT,
  CQL_BLOB_TYPE_STRING,
  CQL_BLOB_TYPE_BLOB,
  CQL_BLOB_TYPE_ENTITY
};

static void gen_cql_blob_create(ast_node *ast) {
  Contract(is_ast_call(ast));
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  ast_node *table_name_ast = first_arg(arg_list);

  EXTRACT_STRING(t_name, table_name_ast);
  cg_blob_mappings_t *map = find_backing_info(t_name);

  bool_t is_pk = false;

  // If there is no third arg then this is a create for a value column for sure
  // only the value blob can be devoid of data, the key column has at least
  // one not null column.  The degenerate form insert backed(id) values(1)
  // leads to only one arg so is_pk will stay false.
  if (arg_list->right && arg_list->right->right) {
    ast_node *arg3 = third_arg(arg_list);
    sem_t sem_type3 = arg3->sem->sem_type;
    is_pk = is_primary_key(sem_type3) || is_partial_pk(sem_type3);
  }

  CSTR func = is_pk ? map->create_key : map->create_val;

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(t_name);
  Invariant(table_ast);

  if (map->use_json || map->use_jsonb) {
    if (is_pk) {
      gen_printf("json%s_array(%s", map->use_jsonb ? "b" : "", gen_type_hash(table_ast));
      for (ast_node *args = arg_list->right; args; args = args->right->right) {
        ast_node *val = first_arg(args);
        gen_printf(", ");
        gen_root_expr(val);
      }
      gen_printf(")");
    }
    else {
      gen_printf("json%s_object(", map->use_jsonb ? "b" : "");
      for (ast_node *args = arg_list->right; args; args = args->right->right) {
        ast_node *val = first_arg(args);
        ast_node *col = second_arg(args);
        EXTRACT_STRING(c_name, col->right);
        gen_printf("'%s', ", c_name);
        gen_root_expr(val);
        if (args->right->right) {
          gen_printf(",  ");
        }
      }
      gen_printf(")");
    }
    return;
  }

  bool_t use_offsets = is_pk ? map->key_use_offsets : map->val_use_offsets;
  gen_printf("%s(%s", func, gen_type_hash(table_ast));

  // 2n+1 args already confirmed, safe to do this
  for (ast_node *args = arg_list->right; args; args = args->right->right) {
     ast_node *val = first_arg(args);
     ast_node *col = second_arg(args);
     if (use_offsets) {
       // when creating a key blob all columns are present in order, so no need to
       // emit the offsets, they are assumed.  However, value blobs can have
       // some or all of the values and might skip some
       if (!is_pk) {
         EXTRACT_STRING(c_name, col->right);
         int32_t offset = get_table_col_offset(table_ast, c_name, CQL_SEARCH_COL_VALUES);
         gen_printf(", %d", offset);
       }
     }
     else {
       gen_printf(", ");
       gen_field_hash(col);
     }

     gen_printf(", ");
     gen_root_expr(val);

     gen_printf(", %d", sem_type_to_blob_type[core_type_of(col->sem->sem_type)]);
  }

  gen_printf(")");
}

static void gen_cql_blob_update(ast_node *ast) {
  Contract(is_ast_call(ast));
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  // known to be dot operator and known to have a table
  EXTRACT_NOTNULL(dot, third_arg(arg_list));
  EXTRACT_STRING(t_name, dot->left);
  cg_blob_mappings_t *map = find_backing_info(t_name);

  sem_t sem_type_dot = dot->sem->sem_type;
  bool_t is_pk = is_primary_key(sem_type_dot) || is_partial_pk(sem_type_dot);

  CSTR func = is_pk ? map->update_key : map->update_val;

  bool_t use_offsets = is_pk ? map->key_use_offsets : map->val_use_offsets;

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(t_name);
  Invariant(table_ast);

  if (map->use_json || map->use_jsonb) {
    gen_printf("json%s_set(", map->use_jsonb ? "b" : "");
    gen_root_expr(first_arg(arg_list));
    for (ast_node *args = arg_list->right; args; args = args->right->right) {
      ast_node *val = first_arg(args);
      ast_node *col = second_arg(args);
      EXTRACT_STRING(c_name, col->right);
      if (is_pk) {
        int32_t offset = get_table_col_offset(table_ast, c_name, CQL_SEARCH_COL_KEYS);
        Invariant(offset >= 0);
        gen_printf(",  '$[%d]', ", offset + 1);  // the type is offset 0
      }
      else {
        gen_printf(",  '$.%s', ", c_name);
      }
      gen_root_expr(val);
    }
    gen_printf(")");
    return;
  }

  gen_printf("%s(", func);
  gen_root_expr(first_arg(arg_list));

  // 2n+1 args already confirmed, safe to do this
  for (ast_node *args = arg_list->right; args; args = args->right->right) {
     ast_node *val = first_arg(args);
     ast_node *col = second_arg(args);
     EXTRACT_STRING(c_name, col->right);
     if (use_offsets) {
      // we know it's a valid column
      int32_t offset = get_table_col_offset(table_ast, c_name,
         is_pk ? CQL_SEARCH_COL_KEYS : CQL_SEARCH_COL_VALUES);
      Invariant(offset >= 0);
      gen_printf(", %d", offset);
     }
     else {
       gen_printf(", ");
       gen_field_hash(col);
     }
     gen_printf(", ");
     gen_root_expr(val);
     if (!is_pk) {
       // you never need the item types for the key blob becasue it always has all the fields
       gen_printf(", %d", sem_type_to_blob_type[core_type_of(col->sem->sem_type)]);
     }
  }

  gen_printf(")");
}

static void gen_array(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_array(ast));
  EXTRACT_ANY_NOTNULL(array, ast->left);
  EXTRACT_NOTNULL(arg_list, ast->right);

  if (pri_new < pri) gen_printf("(");
  gen_expr(array, pri_new);
  if (pri_new < pri) gen_printf(")");
  gen_printf("[");
  gen_arg_list(arg_list);
  gen_printf("]");
}

static void gen_expr_call(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_call(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT_NOTNULL(call_filter_clause, call_arg_list->left);
  EXTRACT(distinct, call_filter_clause->left);
  EXTRACT(opt_filter_clause, call_filter_clause->right);
  EXTRACT(arg_list, call_arg_list->right);

  if (is_ast_str(name_ast)) {
    EXTRACT_STRING(name, name_ast);

    // We never want this to appear. Calls to `cql_inferred_notnull` exist only as
    // the product of a rewrite rule and should not be visible to users.
    if (!StrCaseCmp("cql_inferred_notnull", name)) {
      gen_arg_list(arg_list);
      return;
    }

    if (for_sqlite()) {
      if (!StrCaseCmp("cql_blob_get", name)) {
        gen_cql_blob_get(ast);
        return;
      }
      else if (!StrCaseCmp("cql_blob_get_type", name)) {
        gen_cql_blob_get_type(ast);
        return;
      }
      else if (!StrCaseCmp("cql_blob_create", name)) {
        gen_cql_blob_create(ast);
        return;
      }
      else if (!StrCaseCmp("cql_blob_update", name)) {
        gen_cql_blob_update(ast);
        return;
      }
    }

    if (for_sqlite()) {
      // These functions are all no-ops in SQL and must not be emitted if we're
      // doing codegen: They're only present within queries in source programs for
      // the purpose of manipulating types.

      if (!StrCaseCmp("nullable", name)) {
        gen_arg_list(arg_list);
        return;
      }

      if (!StrCaseCmp("ptr", name)) {
        gen_arg_list(arg_list);
        return;
      }

    if (!StrCaseCmp("sensitive", name)) {
        gen_arg_list(arg_list);
        return;
      }
    }
  }

  bool_t has_func_callback = gen_callbacks && gen_callbacks->func_callback;

  if (has_func_callback) {
    bool_t handled = gen_callbacks->func_callback(ast, gen_callbacks->func_context, gen_output);

    if (handled) {
      return;
    }
  }

  gen_name(name_ast);
  gen_printf("(");
  if (distinct) {
    gen_printf("DISTINCT ");
  }
  gen_arg_list(arg_list);
  gen_printf(")");

  if (opt_filter_clause) {
    gen_opt_filter_clause(opt_filter_clause);
  }
}

static void gen_opt_filter_clause(ast_node *ast) {
  Contract(is_ast_opt_filter_clause(ast));
  EXTRACT_NOTNULL(opt_where, ast->left);

  gen_printf(" FILTER (");
  gen_opt_where(opt_where);
  gen_printf(")");
}

static void gen_opt_partition_by(ast_node *ast) {
  Contract(is_ast_opt_partition_by(ast));
  EXTRACT_NOTNULL(expr_list, ast->left);

  gen_printf("PARTITION BY ");
  gen_expr_list(expr_list);
}

static void gen_frame_spec_flags(int32_t flags) {
  if (flags & FRAME_TYPE_RANGE) {
    gen_printf("RANGE");
  }
  if (flags & FRAME_TYPE_ROWS) {
    gen_printf("ROWS");
  }
  if (flags & FRAME_TYPE_GROUPS) {
    gen_printf("GROUPS");
  }
  if (flags & FRAME_BOUNDARY_UNBOUNDED || flags & FRAME_BOUNDARY_START_UNBOUNDED) {
    gen_printf("UNBOUNDED PRECEDING");
  }
  if (flags & FRAME_BOUNDARY_PRECEDING ||
      flags & FRAME_BOUNDARY_START_PRECEDING ||
      flags & FRAME_BOUNDARY_END_PRECEDING) {
    gen_printf("PRECEDING");
  }
  if (flags & FRAME_BOUNDARY_CURRENT_ROW ||
      flags & FRAME_BOUNDARY_START_CURRENT_ROW ||
      flags & FRAME_BOUNDARY_END_CURRENT_ROW) {
    gen_printf("CURRENT ROW");
  }
  if (flags & FRAME_BOUNDARY_START_FOLLOWING ||
      flags & FRAME_BOUNDARY_END_FOLLOWING) {
    gen_printf("FOLLOWING");
  }
  if (flags & FRAME_BOUNDARY_END_UNBOUNDED) {
    gen_printf("UNBOUNDED FOLLOWING");
  }
  if (flags & FRAME_EXCLUDE_NO_OTHERS) {
    gen_printf("EXCLUDE NO OTHERS");
  }
  if (flags & FRAME_EXCLUDE_CURRENT_ROW) {
    gen_printf("EXCLUDE CURRENT ROW");
  }
  if (flags & FRAME_EXCLUDE_GROUP) {
    gen_printf("EXCLUDE GROUP");
  }
  if (flags & FRAME_EXCLUDE_TIES) {
    gen_printf("EXCLUDE TIES");
  }
}

static void gen_frame_type(int32_t flags) {
  Invariant(flags == (flags & FRAME_TYPE_FLAGS));
  gen_frame_spec_flags(flags);
  gen_printf(" ");
}

static void gen_frame_exclude(int32_t flags) {
  Invariant(flags == (flags & FRAME_EXCLUDE_FLAGS));
  if (flags != FRAME_EXCLUDE_NONE) {
    gen_printf(" ");
  }
  gen_frame_spec_flags(flags);
}

static void gen_frame_boundary(ast_node *ast, int32_t flags) {
  EXTRACT_ANY(expr, ast->left);
  Invariant(flags == (flags & FRAME_BOUNDARY_FLAGS));

  if (expr) {
    gen_root_expr(expr);
    gen_printf(" ");
  }
  gen_frame_spec_flags(flags);
}

static void gen_frame_boundary_start(ast_node *ast, int32_t flags) {
  Contract(is_ast_expr_list(ast));
  EXTRACT_ANY(expr, ast->left);
  Invariant(flags == (flags & FRAME_BOUNDARY_START_FLAGS));

  gen_printf("BETWEEN ");
  if (expr) {
    gen_root_expr(expr);
    gen_printf(" ");
  }
  gen_frame_spec_flags(flags);
}

static void gen_frame_boundary_end(ast_node *ast, int32_t flags) {
  Contract(is_ast_expr_list(ast));
  EXTRACT_ANY(expr, ast->right);
  Invariant(flags == (flags & FRAME_BOUNDARY_END_FLAGS));

  gen_printf(" AND ");
  if (expr) {
    gen_root_expr(expr);
    gen_printf(" ");
  }
  gen_frame_spec_flags(flags);
}

static void gen_opt_frame_spec(ast_node *ast) {
  Contract(is_ast_opt_frame_spec(ast));
  EXTRACT_OPTION(flags, ast->left);
  EXTRACT_NOTNULL(expr_list, ast->right);

  int32_t frame_type_flags = flags & FRAME_TYPE_FLAGS;
  int32_t frame_boundary_flags = flags & FRAME_BOUNDARY_FLAGS;
  int32_t frame_boundary_start_flags = flags & FRAME_BOUNDARY_START_FLAGS;
  int32_t frame_boundary_end_flags = flags & FRAME_BOUNDARY_END_FLAGS;
  int32_t frame_exclude_flags = flags & FRAME_EXCLUDE_FLAGS;

  if (frame_type_flags) {
    gen_frame_type(frame_type_flags);
  }
  if (frame_boundary_flags) {
    gen_frame_boundary(expr_list, frame_boundary_flags);
  }
  if (frame_boundary_start_flags) {
    gen_frame_boundary_start(expr_list, frame_boundary_start_flags);
  }
  if (frame_boundary_end_flags) {
    gen_frame_boundary_end(expr_list, frame_boundary_end_flags);
  }
  if (frame_exclude_flags) {
    gen_frame_exclude(frame_exclude_flags);
  }
}

static void gen_window_defn(ast_node *ast) {
  Contract(is_ast_window_defn(ast));
  EXTRACT(opt_partition_by, ast->left);
  EXTRACT_NOTNULL(window_defn_orderby, ast->right);
  EXTRACT(opt_orderby, window_defn_orderby->left);
  EXTRACT(opt_frame_spec, window_defn_orderby->right);

  // the first optional element never needs a space
  bool need_space = 0;

  gen_printf(" (");
  if (opt_partition_by) {
    Invariant(!need_space);
    gen_opt_partition_by(opt_partition_by);
    need_space = 1;
  }

  if (opt_orderby) {
    if (need_space) gen_printf(" ");
    gen_opt_orderby(opt_orderby);
    need_space = 1;
  }

  if (opt_frame_spec) {
    if (need_space) gen_printf(" ");
    gen_opt_frame_spec(opt_frame_spec);
  }
  gen_printf(")");
}

static void gen_name_or_window_defn(ast_node *ast) {
  if (is_ast_str(ast)) {
    EXTRACT_STRING(window_name, ast);
    gen_printf(" %s", window_name);
  }
  else {
    Contract(is_ast_window_defn(ast));
    gen_window_defn(ast);
  }
}

static void gen_expr_window_func_inv(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_window_func_inv(ast));
  EXTRACT_NOTNULL(call, ast->left);
  EXTRACT_ANY_NOTNULL(name_or_window_defn, ast->right);

  gen_printf("\n  ");
  gen_expr_call(call, op, pri, pri_new);
  gen_printf(" OVER");
  gen_name_or_window_defn(name_or_window_defn);
}

static void gen_expr_raise(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_raise(ast));
  EXTRACT_OPTION(flags, ast->left);
  EXTRACT_ANY(expr, ast->right);

  Contract(flags >= RAISE_IGNORE && flags <= RAISE_FAIL);

  gen_printf("RAISE(");
  switch (flags) {
    case RAISE_IGNORE: gen_printf("IGNORE"); break;
    case RAISE_ROLLBACK: gen_printf("ROLLBACK"); break;
    case RAISE_ABORT: gen_printf("ABORT"); break;
    case RAISE_FAIL: gen_printf("FAIL"); break;
  }
  if (expr) {
    gen_printf(", ");
    gen_root_expr(expr);
  }
  gen_printf(")");
}

static void gen_expr_between(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_between(ast));
  EXTRACT_NOTNULL(range, ast->right);

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" BETWEEN ");
  gen_expr(range->left, pri_new);
  gen_printf(" AND ");
  gen_expr(range->right, pri_new + 1); // the usual rules for the right operand (see gen_binary)
  if (pri_new < pri) gen_printf(")");
}

static void gen_expr_not_between(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_not_between(ast));
  EXTRACT_NOTNULL(range, ast->right);

  if (pri_new < pri) gen_printf("(");
  gen_expr(ast->left, pri_new);
  gen_printf(" NOT BETWEEN ");
  gen_expr(range->left, pri_new);
  gen_printf(" AND ");
  gen_expr(range->right, pri_new + 1); // the usual rules for the right operand (see gen_binary)
  if (pri_new < pri) gen_printf(")");
}

static void gen_expr_between_rewrite(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_between_rewrite(ast));
  EXTRACT_NOTNULL(range, ast->right);

  // even though we did a rewrwite on the AST to make codegen easier we want to
  // echo this back the way it was originally written.  This is important to allow
  // the echoed codegen to reparse in tests -- this isn't a case of sugar, we've
  // added a codegen temporary into the AST and it really doesn't belong in the output

  if (pri_new < pri) gen_printf("(");

  gen_expr(ast->left, pri_new);
  if (is_ast_or(range->right)) {
    gen_printf(" NOT BETWEEN ");
  }
  else {
    gen_printf(" BETWEEN ");
  }
  gen_expr(range->right->left->right, pri_new);
  gen_printf(" AND ");
  gen_expr(range->right->right->right, pri_new);

  if (pri_new < pri) gen_printf(")");
}

static void gen_expr_case(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_case_expr(ast));
  EXTRACT_ANY(expr, ast->left);
  EXTRACT_NOTNULL(connector, ast->right);
  EXTRACT_NOTNULL(case_list, connector->left);
  EXTRACT_ANY(else_expr, connector->right);

  // case is like parens already, you never need more parens
  gen_printf("CASE");
  if (expr) {
    gen_printf(" ");
    // case can have expression or just when clauses
    gen_root_expr(expr);
  }
  gen_printf("\n");
  GEN_BEGIN_INDENT(case_list, 2);
  gen_case_list(case_list);
  if (else_expr) {
    gen_printf("ELSE ");
    gen_root_expr(else_expr);
    gen_printf("\n");
  }
  GEN_END_INDENT(case_list);
  gen_printf("END");
}

static void gen_expr_select(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_select_variant(ast));
  gen_printf("( ");
  gen_select_stmt(ast);
  gen_printf(" )");
}

static void gen_expr_select_if_nothing_throw(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_select_if_nothing_throw_expr(ast) || is_ast_select_if_nothing_or_null_throw_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);
  gen_printf("( ");
  gen_select_stmt(select_stmt);
  gen_printf(" %s )", op);
}

static void gen_expr_select_if_nothing(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_select_if_nothing_expr(ast) || is_ast_select_if_nothing_or_null_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);
  EXTRACT_ANY_NOTNULL(else_expr, ast->right);

  gen_printf("( ");
  gen_select_stmt(select_stmt);
  gen_printf(" %s ", op);
  gen_root_expr(else_expr);
  gen_printf(" )");
}

static void gen_expr_type_check(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_type_check_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(type, ast->right);

  // In SQLite context we only emit the actual expression since type checking already happened during
  // semantic analysis step. Here we're emitting the final sql statement that goes to sqlite
  if (for_sqlite()) {
    gen_expr(expr, EXPR_PRI_ROOT);
  }
  else {
    // note that this will be rewritten to nothing during semantic analysis, it only exists
    // to force an manual compile time type check (useful in macros and such)
    gen_printf("TYPE_CHECK(");
    gen_expr(expr, EXPR_PRI_ROOT);
    gen_printf(" AS ");
    gen_data_type(type);
    gen_printf(")");
  }
}

static void gen_expr_cast(ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_cast_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  if (gen_callbacks && gen_callbacks->minify_casts) {
    if (is_ast_null(expr)) {
      // when generating the actual SQL for Sqlite, we don't need to include cast expressions on NULL
      // we only need those for type checking.
      gen_printf("NULL");
      return;
    }

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // with no SEM we can't do optimization, nor is there any need
#else
    if (expr->sem && ast->sem) {
      // If the expression is already of the correct type (less nullability), we don't need the cast at all.
      sem_t core_type_expr = core_type_of(expr->sem->sem_type);
      sem_t core_type_ast = core_type_of(ast->sem->sem_type);
      if (core_type_expr == core_type_ast) {
        gen_printf("(");
        gen_expr(expr, EXPR_PRI_ROOT);
        gen_printf(")");
        return;
      }
    }
#endif
  }

  gen_printf("CAST(");
  gen_expr(expr, EXPR_PRI_ROOT);
  gen_printf(" AS ");
  gen_data_type(data_type);
  gen_printf(")");
}

static void gen_expr(ast_node *ast, int32_t pri) {
  if (is_any_macro_ref(ast)) {
    gen_any_macro_ref(ast);
    return;
  }

  // These are all the expressions there are, we have to find it in this table
  // or else someone added a new expression type and it isn't supported yet.
  symtab_entry *entry = symtab_find(gen_exprs, ast->type);
  Invariant(entry);
  gen_expr_dispatch *disp = (gen_expr_dispatch*)entry->val;
  disp->func(ast, disp->str, pri, disp->pri_new);
}

cql_noexport void gen_root_expr(ast_node *ast) {
  gen_expr(ast, EXPR_PRI_ROOT);
}

static void gen_as_alias(ast_node *ast) {
  EXTRACT_NAME_AST(name_ast, ast->left);

  gen_printf(" AS ");
  gen_name(name_ast);
}

static void gen_as_alias_with_override(ast_node *ast) {
  Contract(keep_table_name_in_aliases);

  CSTR name = get_inserted_table_alias_string_override(ast);
  Invariant(name);

  gen_printf(" AS %s", name);
}

static void gen_select_expr(ast_node *ast) {
  Contract(is_ast_select_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT(opt_as_alias, ast->right);

  gen_root_expr(expr);

  if (opt_as_alias && is_id(opt_as_alias->left)) {
    EXTRACT_STRING(name, opt_as_alias->left);

    if (used_alias_syms && !symtab_find(used_alias_syms, name)) {
      return;
    }

    gen_as_alias(opt_as_alias);
  }
}

static void gen_col_calc(ast_node *ast) {
  Contract(is_ast_col_calc(ast));
  if (ast->left) {
    ast_node *val = ast->left;

    if (is_ast_dot(val)) {
      gen_name(val->left);
      gen_printf(".");
      gen_name(val->right);
    }
    else {
      gen_name(val);
    }

    if (ast->right) {
      gen_printf(" ");
    }
  }

  if (ast->right) {
    gen_shape_def(ast->right);
  }
}

static void gen_col_calcs(ast_node *ast) {
  Contract(is_ast_col_calcs(ast));
  ast_node *item = ast;
  while (item) {
    gen_col_calc(item->left);
    if (item->right) {
      gen_printf(", ");
    }
    item = item->right;
  }
}

static void gen_column_calculation(ast_node *ast) {
  Contract(is_ast_column_calculation(ast));
  gen_printf("@COLUMNS(");
  if (ast->right) {
    gen_printf("DISTINCT ");
  }
  gen_col_calcs(ast->left);
  gen_printf(")");
}

static void gen_select_expr_list(ast_node *ast) {
  symtab *temp = used_alias_syms;
  used_alias_syms = NULL;

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // if there is no SEM then we can't do this minificiation
#else
  if (ast->sem && gen_callbacks && gen_callbacks->minify_aliases) {
    used_alias_syms = ast->sem->used_symbols;
  }
#endif
  int32_t count = 0;
  for (ast_node *item = ast; item && count < 4; item = item->right) {
     count++;
  }
  int32_t indent = count == 4 ? 4 : 0;

  if (indent) {
    gen_printf("\n");
  }

  int32_t pending_indent_saved = pending_indent;
  GEN_BEGIN_INDENT(sel_list, indent);

  if (!indent) { pending_indent = pending_indent_saved; }

  for (ast_node *item = ast; item; item = item->right) {
    ast_node *expr = item->left;

    if (is_any_macro_ref(expr)) {
      gen_any_macro_ref(expr);
    }
    else if (is_ast_star(expr)) {
      gen_printf("*");
    }
    else if (is_ast_table_star(expr)) {
      EXTRACT_NOTNULL(table_star, expr);
      gen_name(table_star->left);
      gen_printf(".*");
    }
    else if (is_ast_column_calculation(expr)) {
      gen_column_calculation(expr);
    }
    else {
      EXTRACT_NOTNULL(select_expr, expr);
      gen_select_expr(select_expr);
    }
    if (item->right) {
      if (indent) {
         gen_printf(",\n");
      }
      else {
         gen_printf(", ");
      }
    }
  }
  GEN_END_INDENT(sel_list);
  used_alias_syms = temp;
}

static void gen_table_or_subquery(ast_node *ast) {
  Contract(is_ast_table_or_subquery(ast));

  EXTRACT_ANY_NOTNULL(factor, ast->left);

  if (is_any_macro_ref(factor)) {
    gen_any_macro_ref(factor);
  }
  else if (is_ast_str(factor) || is_ast_at_id(factor)) {
    bool_t has_table_rename_callback = gen_callbacks && gen_callbacks->table_rename_callback;
    bool_t handled = false;

    if (has_table_rename_callback) {
      handled = gen_callbacks->table_rename_callback(factor, gen_callbacks->table_rename_context, gen_output);
    }

    if (!handled) {
      gen_name(factor);
    }
  }
  else if (is_ast_select_stmt(factor) || is_ast_with_select_stmt(factor)) {
    gen_printf("(");
    GEN_BEGIN_INDENT(sel, 2);
    pending_indent = 0;
    gen_select_stmt(factor);
    GEN_END_INDENT(sel);
    gen_printf(")");
  }
  else if (is_ast_shared_cte(factor)) {
    gen_printf("(");
    gen_shared_cte(factor);
    gen_printf(")");
  }
  else if (is_ast_table_function(factor)) {
    bool_t has_table_function_callback = gen_callbacks && gen_callbacks->table_function_callback;
    bool_t handled_table_function = false;
    if (has_table_function_callback) {
      handled_table_function = gen_callbacks->table_function_callback(factor, gen_callbacks->table_function_context, gen_output);
    }

    if (!handled_table_function) {
      EXTRACT_STRING(name, factor->left);
      EXTRACT(arg_list, factor->right);
      gen_printf("%s(", name);
      gen_arg_list(arg_list);
      gen_printf(")");
    }
  }
  else {
    // this is all that's left
    gen_printf("(\n");
    GEN_BEGIN_INDENT(qp, 2);
    gen_query_parts(factor);
    GEN_END_INDENT(qp);
    gen_printf(")");
  }

  EXTRACT(opt_as_alias, ast->right);
  if (opt_as_alias) {
    if (get_inserted_table_alias_string_override(opt_as_alias)) {
      gen_as_alias_with_override(opt_as_alias);
    }
    else {
      gen_as_alias(opt_as_alias);
    }
  }
}

static void gen_join_cond(ast_node *ast) {
  Contract(is_ast_join_cond(ast));
  EXTRACT_ANY_NOTNULL(cond_type, ast->left);

  if (is_ast_on(cond_type)) {
    gen_printf(" ON ");
    gen_root_expr(ast->right);
  }
  else {
    // only other ast type that is allowed
    Contract(is_ast_using(cond_type));
    gen_printf(" USING (");
    gen_name_list(ast->right);
    gen_printf(")");
  }
}

static void gen_join_target(ast_node *ast) {
  Contract(is_ast_join_target(ast));
  EXTRACT_OPTION(join_type, ast->left);

  switch (join_type) {
    case JOIN_INNER: gen_printf("\nINNER JOIN "); break;
    case JOIN_CROSS: gen_printf("\nCROSS JOIN "); break;
    case JOIN_LEFT_OUTER: gen_printf("\nLEFT OUTER JOIN "); break;
    case JOIN_RIGHT_OUTER: gen_printf("\nRIGHT OUTER JOIN "); break;
    case JOIN_LEFT: gen_printf("\nLEFT JOIN "); break;
    case JOIN_RIGHT: gen_printf("\nRIGHT JOIN "); break;
  }

  EXTRACT_NOTNULL(table_join, ast->right);
  EXTRACT_NOTNULL(table_or_subquery, table_join->left);
  gen_table_or_subquery(table_or_subquery);

  EXTRACT(join_cond, table_join->right);
  if (join_cond) {
    gen_join_cond(join_cond);
  }
}

static void gen_join_target_list(ast_node *ast) {
  Contract(is_ast_join_target_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT(join_target, item->left);
    gen_join_target(join_target);
  }
}

static void gen_join_clause(ast_node *ast) {
  Contract(is_ast_join_clause(ast));
  EXTRACT_NOTNULL(table_or_subquery, ast->left);
  EXTRACT_NOTNULL(join_target_list, ast->right);

  gen_table_or_subquery(table_or_subquery);
  gen_join_target_list(join_target_list);
}

static void gen_table_or_subquery_list(ast_node *ast) {
  Contract(is_ast_table_or_subquery_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    gen_table_or_subquery(item->left);
    if (item->right) {
      gen_printf(",\n");
    }
  }
}

static void gen_macro_arg_ref(ast_node *ast) {
  EXTRACT_STRING(name, ast->left);
  gen_printf("%s!", name);
}

static void gen_macro_ref(ast_node *ast) {
  EXTRACT_STRING(name, ast->left);
  gen_printf("%s!", name);
  gen_printf("(");
  if (ast->right) {
    gen_macro_args(ast->right);
  }
  gen_printf(")");
}

static void gen_any_macro_ref(ast_node *ast) {
  symtab_entry *entry = symtab_find(gen_macros, ast->type);
  Contract(entry);
  ((void (*)(ast_node*))entry->val)(ast);
}

static void gen_query_parts(ast_node *ast) {
  if (is_ast_table_or_subquery_list(ast)) {
    gen_table_or_subquery_list(ast);
  }
  else {
    Contract(is_ast_join_clause(ast)); // this is the only other choice
    gen_join_clause(ast);
  }
}

static void gen_asc_desc(ast_node *ast) {
  if (is_ast_asc(ast)) {
    gen_printf(" ASC");
    if (ast->left && is_ast_nullslast(ast->left)) {
      gen_printf(" NULLS LAST");
    }
  }
  else if (is_ast_desc(ast)) {
    gen_printf(" DESC");
    if (ast->left && is_ast_nullsfirst(ast->left)) {
      gen_printf(" NULLS FIRST");
    }
  }
  else {
    Contract(!ast);
  }
}

static void gen_groupby_list(ast_node *ast) {
  Contract(is_ast_groupby_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_groupby_list(item));
    EXTRACT_NOTNULL(groupby_item, item->left);
    EXTRACT_ANY_NOTNULL(expr, groupby_item->left);

    gen_root_expr(expr);

    if (item->right) {
      gen_printf(", ");
    }
  }
}

static void gen_orderby_list(ast_node *ast) {
  Contract(is_ast_orderby_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_orderby_list(item));
    EXTRACT_NOTNULL(orderby_item, item->left);
    EXTRACT_ANY_NOTNULL(expr, orderby_item->left);
    EXTRACT_ANY(opt_asc_desc, orderby_item->right);

    gen_root_expr(expr);
    gen_asc_desc(opt_asc_desc);

    if (item->right) {
      gen_printf(", ");
    }
  }
}

static void gen_opt_where(ast_node *ast) {
  Contract(is_ast_opt_where(ast));

  gen_printf("WHERE ");
  gen_root_expr(ast->left);
}

static void gen_opt_groupby(ast_node *ast) {
  Contract(is_ast_opt_groupby(ast));
  EXTRACT_NOTNULL(groupby_list, ast->left);

  gen_printf("\n  GROUP BY ");
  gen_groupby_list(groupby_list);
}

static void gen_opt_orderby(ast_node *ast) {
  Contract(is_ast_opt_orderby(ast));
  EXTRACT_NOTNULL(orderby_list, ast->left);

  gen_printf("ORDER BY ");
  gen_orderby_list(orderby_list);
}

static void gen_opt_limit(ast_node *ast) {
  Contract(is_ast_opt_limit(ast));

  gen_printf("\n  LIMIT ");
  gen_root_expr(ast->left);
}

static void gen_opt_offset(ast_node *ast) {
  Contract(is_ast_opt_offset(ast));

  gen_printf("\n  OFFSET ");
  gen_root_expr(ast->left);
}

static void gen_window_name_defn(ast_node *ast) {
  Contract(is_ast_window_name_defn(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(window_defn, ast->right);

  gen_printf("\n    %s AS", name);
  gen_window_defn(window_defn);
}

static void gen_window_name_defn_list(ast_node *ast) {
  Contract(is_ast_window_name_defn_list(ast));
  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT_NOTNULL(window_name_defn, item->left);
    gen_window_name_defn(window_name_defn);
    if (item->right) {
      gen_printf(", ");
    }
  }
}

static void gen_window_clause(ast_node *ast) {
  Contract(is_ast_window_clause(ast));
  EXTRACT_NOTNULL(window_name_defn_list, ast->left);

  gen_window_name_defn_list(window_name_defn_list);
}

static void gen_opt_select_window(ast_node *ast) {
  Contract(is_ast_opt_select_window(ast));
  EXTRACT_NOTNULL(window_clause, ast->left);

  gen_printf("\n  WINDOW ");
  gen_window_clause(window_clause);
}

static void gen_select_from_etc(ast_node *ast) {
  Contract(is_ast_select_from_etc(ast));

  EXTRACT_ANY(query_parts, ast->left);
  EXTRACT_NOTNULL(select_where, ast->right);
  EXTRACT(opt_where, select_where->left);
  EXTRACT_NOTNULL(select_groupby, select_where->right);
  EXTRACT(opt_groupby, select_groupby->left);
  EXTRACT_NOTNULL(select_having, select_groupby->right);
  EXTRACT(opt_having, select_having->left);
  EXTRACT(opt_select_window, select_having->right);

  if (query_parts) {
    gen_printf("\n  FROM ");
    GEN_BEGIN_INDENT(from, 4);
      pending_indent = 0;
      gen_query_parts(query_parts);
    GEN_END_INDENT(from);
  }
  if (opt_where) {
    gen_printf("\n  ");
    gen_opt_where(opt_where);
  }
  if (opt_groupby) {
    gen_opt_groupby(opt_groupby);
  }
  if (opt_having) {
    gen_printf("\n  HAVING ");
    gen_root_expr(opt_having->left);
  }
  if (opt_select_window) {
    gen_opt_select_window(opt_select_window);
  }
}

static void gen_select_orderby(ast_node *ast) {
  Contract(is_ast_select_orderby(ast));
  EXTRACT(opt_orderby, ast->left);
  EXTRACT_NOTNULL(select_limit, ast->right);
  EXTRACT(opt_limit, select_limit->left);
  EXTRACT_NOTNULL(select_offset, select_limit->right);
  EXTRACT(opt_offset, select_offset->left);

  if (opt_orderby) {
    gen_printf("\n  ");
    gen_opt_orderby(opt_orderby);
  }
  if (opt_limit) {
    gen_opt_limit(opt_limit);
  }
  if (opt_offset) {
    gen_opt_offset(opt_offset);
  }
}

static void gen_select_expr_list_con(ast_node *ast) {
  Contract(is_ast_select_expr_list_con(ast));
  EXTRACT(select_expr_list, ast->left);
  EXTRACT(select_from_etc, ast->right);

  gen_select_expr_list(select_expr_list);
  if (select_from_etc) {
    gen_select_from_etc(select_from_etc);
  }
}

cql_noexport void init_gen_sql_callbacks(gen_sql_callbacks *cb)
{
  memset((void *)cb, 0, sizeof(*gen_callbacks));
  // with callbacks is for SQLite be default, the normal raw output
  // case is done with callbacks == NULL
  cb->mode = gen_mode_sql;
}

static void gen_select_statement_type(ast_node *ast) {
  Contract(is_ast_select_core(ast));
  EXTRACT_ANY(select_opts, ast->left);

  if (select_opts && is_ast_select_values(select_opts)) {
    gen_printf("VALUES");
  }
  else {
    gen_printf("SELECT");
    if (select_opts) {
      Contract(is_ast_select_opts(select_opts));
      gen_select_opts(select_opts);
    }
  }
}

static void gen_values(ast_node *ast) {
  Contract(is_ast_values(ast));
  bool_t many_items = ast && ast->right;
  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT(insert_list, item->left);
    if (many_items) {
      gen_printf("\n  ");
    }
    else {
      gen_printf(" ");
    }
    gen_printf("(");
    if (insert_list) {
      gen_insert_list(insert_list);
    }
    gen_printf(")");
    if (item->right) {
      gen_printf(",");
    }
  }
}

cql_noexport void gen_select_core(ast_node *ast) {

  if (is_any_macro_ref(ast)) {
    gen_printf("ROWS(");
    gen_any_macro_ref(ast);
    gen_printf(")");
  }
  else {
    Contract(is_ast_select_core(ast));
    EXTRACT_ANY(select_core_left, ast->left);

    gen_select_statement_type(ast);

    if (is_ast_select_values(select_core_left)) {
      // VALUES [values]
      EXTRACT(values, ast->right);
      gen_values(values);
    }
    else {
      // SELECT [select_expr_list_con]
      // We're making sure that we're in the SELECT clause of the select stmt
      Contract(select_core_left == NULL || is_ast_select_opts(select_core_left));
      pending_indent = 1; // this gives us a single space before the select list if needed
      EXTRACT_NOTNULL(select_expr_list_con, ast->right);
      gen_select_expr_list_con(select_expr_list_con);
    }
  }
}

static void gen_select_no_with(ast_node *ast) {
  Contract(is_ast_select_stmt(ast));
  EXTRACT_NOTNULL(select_core_list, ast->left);
  EXTRACT_NOTNULL(select_orderby, ast->right);

  gen_select_core_list(select_core_list);
  gen_select_orderby(select_orderby);
}

static void gen_cte_decl(ast_node *ast)  {
  Contract(is_ast_cte_decl(ast));
  EXTRACT_ANY_NOTNULL(name_ast, ast->left);
  gen_name(name_ast);
  if (!is_ast_star(ast->right)) {
    // skip this for foo(*), the shorter syntax is just the name
    gen_printf(" (");
    gen_name_list(ast->right);
    gen_printf(")");
  }
}

static void gen_cte_binding_list(ast_node *ast) {
  Contract(is_ast_cte_binding_list(ast));

  while (ast) {
     EXTRACT_NOTNULL(cte_binding, ast->left);
     EXTRACT_STRING(actual, cte_binding->left);
     EXTRACT_STRING(formal, cte_binding->right);
     gen_printf("%s AS %s", actual, formal);

     if (ast->right) {
       gen_printf(", ");
     }
     ast = ast->right;
  }
}

static void gen_shared_cte(ast_node *ast) {
  Contract(is_ast_shared_cte(ast));
  bool_t has_cte_procs_callback = gen_callbacks && gen_callbacks->cte_proc_callback;
  bool_t handled = false;

  if (has_cte_procs_callback) {
    handled = gen_callbacks->cte_proc_callback(ast, gen_callbacks->cte_proc_context, gen_output);
  }

  if (!handled) {
    EXTRACT_NOTNULL(call_stmt, ast->left);
    EXTRACT(cte_binding_list, ast->right);
    gen_call_stmt(call_stmt);
    if (cte_binding_list) {
      gen_printf(" USING ");
      gen_cte_binding_list(cte_binding_list);
    }
  }
}

static void gen_cte_table(ast_node *ast)  {
  Contract(is_ast_cte_table(ast));
  EXTRACT(cte_decl, ast->left);
  EXTRACT_ANY_NOTNULL(cte_body, ast->right);

  bool_t suppress_decl = false;
  if (is_ast_shared_cte(cte_body) && is_ast_star(cte_decl->right)) {
    // special case for foo(*) as (call foo(...))
    // we want to emit the abbreviated form in that case

    EXTRACT_STRING(cte_name, cte_decl->left);
    EXTRACT_NOTNULL(call_stmt, cte_body->left);
    EXTRACT_STRING(call_name, call_stmt->left);

    // skip the redunant cte decl if the names are the same
    // this is much cleaner looking and avoids the "is it the same?" question
    // when reading the source
    suppress_decl = !StrCaseCmp(cte_name, call_name);
  }

  if (!suppress_decl) {
    gen_cte_decl(cte_decl);
  }

  if (is_ast_like(cte_body)) {
    gen_printf(" LIKE ");
    if (is_ast_str(cte_body->left)) {
      gen_name(cte_body->left);
    }
    else {
      gen_printf("(\n");
      GEN_BEGIN_INDENT(cte_indent, 2);
        gen_select_stmt(cte_body->left);
      GEN_END_INDENT(cte_indent);
      gen_printf("\n)");
    }
    return;
  }

  if (!suppress_decl) {
    gen_printf(" AS ");
  }

  gen_printf("(");

  if (is_ast_shared_cte(cte_body)) {
    gen_shared_cte(cte_body);
    gen_printf(")");
  }
  else {
    gen_printf("\n");
    GEN_BEGIN_INDENT(cte_indent, 2);
      // the only other alternative is the select statement form
      gen_select_stmt(cte_body);
    GEN_END_INDENT(cte_indent);
    gen_printf("\n)");
  }
}

static void gen_cte_tables(ast_node *ast, CSTR prefix) {
  bool_t first = true;

  while (ast) {
    Contract(is_ast_cte_tables(ast));
    EXTRACT_ANY_NOTNULL(cte_table, ast->left);

    bool_t handled = false;

    if (is_ast_cte_table(cte_table)) {
      Contract(is_ast_cte_table(cte_table));

      // callbacks can suppress some CTE for use in shared_fragments
      bool_t has_cte_suppress_callback = gen_callbacks && gen_callbacks->cte_suppress_callback;

      if (has_cte_suppress_callback) {
        handled = gen_callbacks->cte_suppress_callback(cte_table, gen_callbacks->cte_suppress_context, gen_output);
      }
    }

    if (!handled) {
      if (first) {
        gen_printf("%s", prefix);
        first = false;
      }
      else {
        gen_printf(",\n");
      }

      if (is_ast_cte_tables_macro_ref(cte_table)) {
        gen_any_macro_ref(cte_table);
      }
      else if (is_ast_cte_tables_macro_arg_ref(cte_table)) {
        gen_any_macro_ref(cte_table);
      }
      else {
        gen_cte_table(cte_table);
      }
    }

    ast = ast->right;
  }

  if (!first) {
    gen_printf("\n");
  }
}

static void gen_with_prefix(ast_node *ast) {
  EXTRACT(cte_tables, ast->left);
  CSTR prefix;

  // for us there is no difference between WITH and WITH RECURSIVE
  // except we have to remember which one it was so that we can
  // emit the same thing we saw.  Sqlite lets you do recursion
  // even if don't use WITH RECURSIVE
  if (is_ast_with(ast)) {
    prefix = "WITH\n";
  }
  else {
    Contract(is_ast_with_recursive(ast));
    prefix = "WITH RECURSIVE\n";
  }
  GEN_BEGIN_INDENT(cte_indent, 2);
    pending_indent -= 2;
    gen_cte_tables(cte_tables, prefix);
  GEN_END_INDENT(cte_indent);
}

static void gen_with_select_stmt(ast_node *ast) {
  Contract(is_ast_with_select_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_ANY_NOTNULL(select_stmt, ast->right);

  gen_with_prefix(with_prefix);
  gen_select_stmt(select_stmt);
}

static void gen_select_core_list(ast_node *ast) {
  Contract(is_ast_select_core_list(ast));

  EXTRACT_ANY_NOTNULL(select_core, ast->left);

  gen_select_core(select_core);

  EXTRACT(select_core_compound, ast->right);
  if (!select_core_compound) {
    return;
  }
  EXTRACT_OPTION(compound_operator, select_core_compound->left);
  EXTRACT_NOTNULL(select_core_list, select_core_compound->right);

  gen_printf("\n%s\n", get_compound_operator_name(compound_operator));
  gen_select_core_list(select_core_list);
}


// This form is expanded late like select *
// since it only appears in shared fragments (actually only
// in conditional fragments) it will never be seen
// in the course of normal codegen, only in SQL expansion
// hence none of the code generators need to even know
// this is happening (again, just like select *).
// This approach gives us optimal sql for very little cost.
static void gen_select_nothing_stmt(ast_node *ast) {
  Contract(is_ast_select_nothing_stmt(ast));

  if (!for_sqlite() || !ast->sem || !ast->sem->sptr) {
    gen_printf("SELECT NOTHING");
    return;
  }

  // we just generate the right number of dummy columns for Sqlite
  // type doesn't matter because it's going to be "WHERE 0"

  gen_printf("SELECT ");
  sem_struct *sptr = ast->sem->sptr;
  for (uint32_t i = 0; i < sptr->count; i++) {
    if (i) {
      gen_printf(",");
    }

    if (gen_callbacks && gen_callbacks->minify_aliases) {
      gen_printf("0");
    }
    else {
      gen_printf("0 ");
      gen_sptr_name(sptr, i);
    }
  }
  gen_printf(" WHERE 0");
}

static void gen_select_stmt(ast_node *ast) {
  if (is_ast_with_select_stmt(ast)) {
    gen_with_select_stmt(ast);
  }
  else {
    Contract(is_ast_select_stmt(ast));
    gen_select_no_with(ast);
  }
}

static void gen_version_attrs(ast_node *_Nullable ast) {
  for (ast_node *attr = ast; attr; attr = attr->right) {
    if (is_ast_recreate_attr(attr)) {
      gen_recreate_attr(attr);
    }
    else if (is_ast_create_attr(attr)) {
      gen_create_attr(attr);
    }
    else {
      Contract(is_ast_delete_attr(attr)); // the only other kind
      gen_delete_attr(attr);
    }
  }
}

// If there is a handler, the handler will decide what to do.  If there is no handler
// or the handler returns false, then we honor the flag bit.  This lets you override
// the if_not_exists flag forcing it to be either ignored or enabled.  Both are potentially
// needed.  When emitting schema creation scripts for instance we always use IF NOT EXISTS
// even if the schema declaration didn't have it (which it usually doesn't).
static void gen_if_not_exists(ast_node *ast, bool_t if_not_exist) {
  bool_t if_not_exists_callback = gen_callbacks && gen_callbacks->if_not_exists_callback;
  bool_t handled = false;

  if (if_not_exists_callback) {
    handled = gen_callbacks->if_not_exists_callback(ast, gen_callbacks->if_not_exists_context, gen_output);
  }

  if (if_not_exist && !handled) {
    gen_printf("IF NOT EXISTS ");
  }
}

static void gen_eponymous(ast_node *ast, bool_t is_eponymous) {
  if (!for_sqlite() && is_eponymous) {
    gen_printf("@EPONYMOUS ");
  }
}

static void gen_create_view_stmt(ast_node *ast) {
  Contract(is_ast_create_view_stmt(ast));
  EXTRACT_OPTION(flags, ast->left);
  EXTRACT(view_and_attrs, ast->right);
  EXTRACT_NOTNULL(view_details_select, view_and_attrs->left);
  EXTRACT_NOTNULL(view_details, view_details_select->left);
  EXTRACT(name_list, view_details->right);
  EXTRACT_ANY(attrs, view_and_attrs->right);
  EXTRACT_ANY_NOTNULL(select_stmt, view_details_select->right);
  EXTRACT_NAME_AST(name_ast, view_details->left);

  bool_t if_not_exist = !!(flags & VIEW_IF_NOT_EXISTS);

  gen_printf("CREATE ");
  if (flags & VIEW_IS_TEMP) {
    gen_printf("TEMP ");
  }
  gen_printf("VIEW ");
  gen_if_not_exists(ast, if_not_exist);
  gen_name(name_ast);
  if (name_list) {
    gen_printf("(");
    gen_name_list(name_list);
    gen_printf(")");
  }
  gen_printf(" AS\n");
  GEN_BEGIN_INDENT(sel, 2);
  gen_select_stmt(select_stmt);
  gen_version_attrs(attrs);
  GEN_END_INDENT(sel);
}

static void gen_create_trigger_stmt(ast_node *ast) {
  Contract(is_ast_create_trigger_stmt(ast));

  EXTRACT_OPTION(flags, ast->left);
  EXTRACT_NOTNULL(trigger_body_vers, ast->right);
  EXTRACT_ANY(trigger_attrs, trigger_body_vers->right);
  EXTRACT_NOTNULL(trigger_def, trigger_body_vers->left);
  EXTRACT_NAME_AST(trigger_name_ast, trigger_def->left);
  EXTRACT_NOTNULL(trigger_condition, trigger_def->right);
  EXTRACT_OPTION(cond_flags, trigger_condition->left);
  flags |= cond_flags;
  EXTRACT_NOTNULL(trigger_op_target, trigger_condition->right);
  EXTRACT_NOTNULL(trigger_operation, trigger_op_target->left);
  EXTRACT_OPTION(op_flags,  trigger_operation->left);
  EXTRACT(name_list, trigger_operation->right);
  flags |= op_flags;
  EXTRACT_NOTNULL(trigger_target_action, trigger_op_target->right);
  EXTRACT_NAME_AST(table_name_ast, trigger_target_action->left);
  EXTRACT_NOTNULL(trigger_action, trigger_target_action->right);
  EXTRACT_OPTION(action_flags, trigger_action->left);
  flags |= action_flags;
  EXTRACT_NOTNULL(trigger_when_stmts, trigger_action->right);
  EXTRACT_ANY(when_expr, trigger_when_stmts->left);
  EXTRACT_NOTNULL(stmt_list, trigger_when_stmts->right);

  gen_printf("CREATE ");
  if (flags & TRIGGER_IS_TEMP) {
    gen_printf("TEMP ");
  }
  gen_printf("TRIGGER ");
  gen_if_not_exists(ast, !!(flags & TRIGGER_IF_NOT_EXISTS));

  gen_name(trigger_name_ast);
  gen_printf("\n  ");

  if (flags & TRIGGER_BEFORE) {
    gen_printf("BEFORE ");
  }
  else if (flags & TRIGGER_AFTER) {
    gen_printf("AFTER ");
  }
  else if (flags & TRIGGER_INSTEAD_OF) {
    gen_printf("INSTEAD OF ");
  }

  if (flags & TRIGGER_DELETE) {
    gen_printf("DELETE ");
  }
  else if (flags & TRIGGER_INSERT) {
    gen_printf("INSERT ");
  }
  else {
    gen_printf("UPDATE ");
    if (name_list) {
      gen_printf("OF ");
      gen_name_list(name_list);
      gen_printf(" ");
    }
  }
  gen_printf("ON ");
  gen_name(table_name_ast);

  if (flags & TRIGGER_FOR_EACH_ROW) {
    gen_printf("\n  FOR EACH ROW");
  }

  if (when_expr) {
    gen_printf("\n  WHEN ");
    gen_root_expr(when_expr);
  }

  gen_printf("\nBEGIN\n");
  gen_stmt_list(stmt_list);
  gen_printf("END");
  gen_version_attrs(trigger_attrs);
}

static void gen_create_table_stmt(ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast));
  EXTRACT_NOTNULL(create_table_name_flags, ast->left);
  EXTRACT_NOTNULL(table_flags_attrs, create_table_name_flags->left);
  EXTRACT_OPTION(flags, table_flags_attrs->left);
  EXTRACT_ANY(table_attrs, table_flags_attrs->right);
  EXTRACT_NAME_AST(table_name_ast, create_table_name_flags->right);
  EXTRACT_NOTNULL(col_key_list, ast->right);

  bool_t temp = !!(flags & TABLE_IS_TEMP);
  bool_t if_not_exist = !!(flags & TABLE_IF_NOT_EXISTS);
  bool_t no_rowid = !!(flags & TABLE_IS_NO_ROWID);

  gen_printf("CREATE ");
  if (temp) {
    gen_printf("TEMP ");
  }

  gen_printf("TABLE ");
  gen_if_not_exists(ast, if_not_exist);

  gen_name(table_name_ast);
  gen_printf("(\n");
  gen_col_key_list(col_key_list);
  gen_printf("\n)");
  if (no_rowid) {
    gen_printf(" WITHOUT ROWID");
  }
  gen_version_attrs(table_attrs);
}

static void gen_create_virtual_table_stmt(ast_node *ast) {
  Contract(is_ast_create_virtual_table_stmt(ast));
  EXTRACT_NOTNULL(module_info, ast->left);
  EXTRACT_NOTNULL(create_table_stmt, ast->right);
  EXTRACT_NOTNULL(create_table_name_flags, create_table_stmt->left);
  EXTRACT_NOTNULL(table_flags_attrs, create_table_name_flags->left);
  EXTRACT_OPTION(flags, table_flags_attrs->left);
  EXTRACT_ANY(table_attrs, table_flags_attrs->right);
  EXTRACT_STRING(name, create_table_name_flags->right);
  EXTRACT_NOTNULL(col_key_list, create_table_stmt->right);
  EXTRACT_STRING(module_name, module_info->left);
  EXTRACT_ANY(module_args, module_info->right);

  bool_t if_not_exist = !!(flags & TABLE_IF_NOT_EXISTS);
  bool_t is_eponymous = !!(flags & VTAB_IS_EPONYMOUS);

  gen_printf("CREATE VIRTUAL TABLE ");
  gen_if_not_exists(ast, if_not_exist);
  gen_eponymous(ast, is_eponymous);
  gen_printf("%s USING %s", name, module_name);

  if (!for_sqlite()) {
    if (is_ast_following(module_args)) {
      gen_printf(" (ARGUMENTS FOLLOWING) ");
    }
    else if (module_args) {
      gen_printf(" ");
      gen_misc_attr_value(module_args);
      gen_printf(" ");
    }
    else {
      gen_printf(" ");
    }

    // When emitting to SQLite we do not include the column declaration part
    // just whatever the args were because SQLite doesn't parse that part of the CQL syntax.
    // Note that CQL does not support general args because that's not parseable with this parser
    // tech but this is pretty general.  The declaration part is present here so that
    // CQL knows the type info of the net table we are creating.
    // Note also that virtual tables are always on the recreate plan, it isn't an option
    // and this will mean that you can't make a foreign key to a virtual table which is probably
    // a wise thing.

    gen_printf("AS (\n");
    gen_col_key_list(col_key_list);
    gen_printf("\n)");

    // delete attribute is the only option (recreate by default)
    if (!is_ast_recreate_attr(table_attrs)) {
      Invariant(is_ast_delete_attr(table_attrs));
      gen_delete_attr(table_attrs);
    }
  }
  else {
    if (is_ast_following(module_args)) {
      gen_printf(" (\n");
      gen_col_key_list(col_key_list);
      gen_printf(")");
    }
    else if (module_args) {
      gen_printf(" ");
      gen_misc_attr_value(module_args);
    }
  }
}

static void gen_drop_view_stmt(ast_node *ast) {
  Contract(is_ast_drop_view_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf("DROP VIEW ");
  if (if_exists) {
    gen_printf("IF EXISTS ");
  }
  gen_name(name_ast);
}

static void gen_drop_table_stmt(ast_node *ast) {
  Contract(is_ast_drop_table_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf("DROP TABLE ");
  if (if_exists) {
    gen_printf("IF EXISTS ");
  }
  gen_name(name_ast);
}

static void gen_drop_index_stmt(ast_node *ast) {
  Contract(is_ast_drop_index_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf("DROP INDEX ");
  if (if_exists) {
    gen_printf("IF EXISTS ");
  }
  gen_name(name_ast);
}

static void gen_drop_trigger_stmt(ast_node *ast) {
  Contract(is_ast_drop_trigger_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf("DROP TRIGGER ");
  if (if_exists) {
    gen_printf("IF EXISTS ");
  }
  gen_name(name_ast);
}

static void gen_alter_table_add_column_stmt(ast_node *ast) {
  Contract(is_ast_alter_table_add_column_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(col_def, ast->right);

  gen_printf("ALTER TABLE ");
  gen_name(name_ast);
  gen_printf(" ADD COLUMN ");
  gen_col_def(col_def);
}

static bool_t eval_if_stmt_callback(ast_node *ast) {
  Contract(is_ast_if_stmt(ast));

  bool_t suppress = 0;
  if (gen_callbacks && gen_callbacks->if_stmt_callback) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks->if_stmt_callback(ast, gen_callbacks->if_stmt_context, &buf);
    gen_printf("%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }
  return suppress;
}

static void gen_cond_action(ast_node *ast) {
  Contract(is_ast_cond_action(ast));
  EXTRACT(stmt_list, ast->right);

  gen_root_expr(ast->left);
  gen_printf(" THEN\n");
  gen_stmt_list(stmt_list);
}

static void gen_elseif_list(ast_node *ast) {
  Contract(is_ast_elseif(ast));

  while (ast) {
    Contract(is_ast_elseif(ast));
    EXTRACT(cond_action, ast->left);
    gen_printf("ELSE IF ");
    gen_cond_action(cond_action);
    ast = ast->right;
  }
}

static void gen_ifxdef_stmt(ast_node *ast) {
  EXTRACT_ANY_NOTNULL(true_false, ast->left);
  EXTRACT_STRING(id, true_false->left);
  EXTRACT(pre, ast->right);
  EXTRACT_NAMED(left, stmt_list, pre->left);
  EXTRACT_NAMED(right, stmt_list, pre->right);
  gen_printf("%s\n", id);
  if (left) {
    gen_stmt_list(left);
  }
  if (right) {
    gen_printf("@ELSE\n");
    gen_stmt_list(right);
  }
  gen_printf("@ENDIF\n");
}

static void gen_ifdef_stmt(ast_node *ast) {
  gen_printf("@IFDEF ");
  gen_ifxdef_stmt(ast);
}

static void gen_ifndef_stmt(ast_node *ast) {
  gen_printf("@IFNDEF ");
  gen_ifxdef_stmt(ast);
}

static void gen_if_stmt(ast_node *ast) {
  Contract(is_ast_if_stmt(ast));
  EXTRACT_NOTNULL(cond_action, ast->left);
  EXTRACT_NOTNULL(if_alt, ast->right);
  EXTRACT(elseif, if_alt->left);
  EXTRACT_NAMED(elsenode, else, if_alt->right);

  if (eval_if_stmt_callback(ast)) {
    return;
  }

  gen_printf("IF ");
  gen_cond_action(cond_action);

  if (elseif) {
    gen_elseif_list(elseif);
  }

  if (elsenode) {
    gen_printf("ELSE\n");
    EXTRACT(stmt_list, elsenode->left);
    gen_stmt_list(stmt_list);
  }

  gen_printf("END");
}

static void gen_guard_stmt(ast_node *ast) {
  Contract(is_ast_guard_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf("IF ");
  gen_expr(expr, EXPR_PRI_ROOT);
  gen_printf(" ");
  gen_one_stmt(stmt);
}

static void gen_expr_stmt(ast_node *ast) {
  Contract(is_ast_expr_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  gen_expr(expr, EXPR_PRI_ROOT);
}

static void gen_delete_stmt(ast_node *ast) {
  Contract(is_ast_delete_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(opt_where, ast->right);

  gen_printf("DELETE FROM ");
  gen_name(name_ast);
  if (opt_where) {
    gen_printf(" WHERE ");
    gen_root_expr(opt_where->left);
  }
}

static void gen_with_delete_stmt(ast_node *ast) {
  Contract(is_ast_with_delete_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(delete_stmt, ast->right);

  gen_with_prefix(with_prefix);
  gen_delete_stmt(delete_stmt);
}

static void gen_delete_returning_stmt(ast_node *ast) {
  Contract(is_ast_delete_returning_stmt(ast));
  EXTRACT_ANY_NOTNULL(delete_stmt, ast->left);
  if (is_ast_with_delete_stmt(delete_stmt)) {
    gen_with_delete_stmt(delete_stmt);
  }
  else {
    gen_delete_stmt(delete_stmt);
  }
  gen_printf("\n  RETURNING ");
  gen_select_expr_list(ast->right);
}

static void gen_update_entry(ast_node *ast) {
  Contract(is_ast_update_entry(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->right)
  EXTRACT_NAME_AST(name_ast, ast->left);
  gen_name(name_ast);
  gen_printf(" = ");
  gen_root_expr(expr);
}

static void gen_update_list(ast_node *ast) {
  Contract(is_ast_update_list(ast));

  int32_t count = 0;
  for (ast_node *item = ast; item; item = item->right) {
    count++;
  }

  if (count <= 4) {
    gen_printf(" ");
    for (ast_node *item = ast; item; item = item->right) {
      Contract(is_ast_update_list(item));
      EXTRACT_NOTNULL(update_entry, item->left);

      gen_update_entry(update_entry);
      if (item->right) {
        gen_printf(", ");
      }
    }
  }
  else {
    GEN_BEGIN_INDENT(set_indent, 2);
    gen_printf("\n");
    for (ast_node *item = ast; item; item = item->right) {
      Contract(is_ast_update_list(item));
      EXTRACT_NOTNULL(update_entry, item->left);

      gen_update_entry(update_entry);
      if (item->right) {
        gen_printf(",\n");
      }
    }
    GEN_END_INDENT(set_indent);
  }
}

static void gen_from_shape(ast_node *ast) {
  Contract(is_ast_from_shape(ast));
  EXTRACT_STRING(shape_name, ast->right);
  EXTRACT_ANY(column_spec, ast->left);
  gen_printf("FROM %s", shape_name);
  gen_column_spec(column_spec);
}

static void gen_update_cursor_stmt(ast_node *ast) {
  Contract(is_ast_update_cursor_stmt(ast));
  EXTRACT_ANY(cursor, ast->left);
  EXTRACT_STRING(name, cursor);
  EXTRACT_ANY_NOTNULL(columns_values, ast->right);

  gen_printf("UPDATE CURSOR %s", name);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(" USING ");
    gen_expr_names(columns_values);
  }
  else {
    EXTRACT_ANY(column_spec, columns_values->left);
    EXTRACT_ANY(insert_list, columns_values->right);

    gen_column_spec(column_spec);
    gen_printf(" ");
    if (is_ast_from_shape(insert_list)) {
      gen_from_shape(insert_list);
    }
    else {
      gen_printf("FROM VALUES (");
      gen_insert_list(insert_list);
      gen_printf(")");
    }
  }
}

static void gen_update_stmt(ast_node *ast) {
  Contract(is_ast_update_stmt(ast));
  EXTRACT_NOTNULL(update_set, ast->right);
  EXTRACT_ANY_NOTNULL(update_list, update_set->left);
  EXTRACT_NOTNULL(update_from, update_set->right);
  EXTRACT_NOTNULL(update_where, update_from->right);
  EXTRACT_ANY(query_parts, update_from->left);
  EXTRACT(opt_where, update_where->left);
  EXTRACT_NOTNULL(update_orderby, update_where->right);
  EXTRACT(opt_orderby, update_orderby->left);
  EXTRACT(opt_limit, update_orderby->right);

  gen_printf("UPDATE");
  if (ast->left) {
    EXTRACT_NAME_AST(name_ast, ast->left);
    gen_printf(" ");
    gen_name(name_ast);
  }
  GEN_BEGIN_INDENT(up, 2);

  gen_printf("\nSET");
  if (is_ast_columns_values(update_list)) {
    // UPDATE table_name SET ([opt_column_spec]) = ([from_shape])
    EXTRACT(column_spec, update_list->left);
    EXTRACT_ANY_NOTNULL(from_shape_or_insert_list, update_list->right);

    gen_printf(" ");
    gen_column_spec(column_spec);
    gen_printf(" = ");

    gen_printf("(");
    gen_insert_list(from_shape_or_insert_list);
    gen_printf(")");
  }
  else {
    // UPDATE table_name SET [update_list] FROM [query_parts]
    gen_update_list(update_list);
  }

  if (query_parts) {
    gen_printf("\nFROM ");
    gen_query_parts(query_parts);
  }
  if (opt_where) {
    gen_printf("\n");
    gen_opt_where(opt_where);
  }
  if (opt_orderby) {
    gen_printf("\n");
    gen_opt_orderby(opt_orderby);
  }
  if (opt_limit) {
    gen_opt_limit(opt_limit);
  }
  GEN_END_INDENT(up);
}

static void gen_with_update_stmt(ast_node *ast) {
  Contract(is_ast_with_update_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(update_stmt, ast->right);

  gen_with_prefix(with_prefix);
  gen_update_stmt(update_stmt);
}

static void gen_update_returning_stmt(ast_node *ast) {
  Contract(is_ast_update_returning_stmt(ast));
  EXTRACT_ANY_NOTNULL(update_stmt, ast->left);
  if (is_ast_with_update_stmt(update_stmt)) {
    gen_with_update_stmt(update_stmt);
  }
  else {
    gen_update_stmt(update_stmt);
  }
  gen_printf("\n  RETURNING ");
  gen_select_expr_list(ast->right);
}

static void gen_insert_list(ast_node *_Nullable ast) {
  Contract(!ast || is_ast_insert_list(ast));

  while (ast) {
    Contract(is_ast_insert_list(ast));

    if (is_ast_from_shape(ast->left)) {
      gen_shape_arg(ast->left);
    }
    else {
      gen_root_expr(ast->left);
    }

    if (ast->right) {
      gen_printf(", ");
    }
    ast = ast->right;
  }
}

cql_noexport void gen_insert_type(ast_node *ast) {
  if (is_ast_insert_or_ignore(ast)) {
    gen_printf("INSERT OR IGNORE");
  }
  else if (is_ast_insert_or_replace(ast)) {
    gen_printf("INSERT OR REPLACE");
  }
  else if (is_ast_insert_replace(ast)) {
    gen_printf("REPLACE");
  }
  else if (is_ast_insert_or_abort(ast)) {
    gen_printf("INSERT OR ABORT");
  }
  else if (is_ast_insert_or_fail(ast)) {
    gen_printf("INSERT OR FAIL");
  }
  else if (is_ast_insert_or_rollback(ast)) {
     gen_printf("INSERT OR ROLLBACK");
  }
  else {
    Contract(is_ast_insert_normal(ast));
    gen_printf("INSERT");
  }
}

static void gen_insert_dummy_spec(ast_node *ast) {
  Contract(is_ast_insert_dummy_spec(ast) || is_ast_seed_stub(ast));
  EXTRACT_ANY_NOTNULL(seed_expr, ast->left);
  EXTRACT_OPTION(flags, ast->right);

  if (suppress_attributes()) {
    return;
  }

  gen_printf(" @DUMMY_SEED(");
  gen_root_expr(seed_expr);
  gen_printf(")");

  if (flags & INSERT_DUMMY_DEFAULTS) {
    gen_printf(" @DUMMY_DEFAULTS");
  }

  if (flags & INSERT_DUMMY_NULLABLES) {
    gen_printf(" @DUMMY_NULLABLES");
  }
}

static void gen_shape_def_base(ast_node *ast) {
  Contract(is_ast_like(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY(from_args, ast->right);

  gen_printf("LIKE ");
  gen_name(name_ast);
  if (from_args) {
    gen_printf(" ARGUMENTS");
  }
}

static void gen_shape_expr(ast_node *ast) {
  Contract(is_ast_shape_expr(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);

  if (!ast->right) {
    gen_printf("-");
  }
  gen_name(name_ast);
}

static void gen_shape_exprs(ast_node *ast) {
 Contract(is_ast_shape_exprs(ast));

  while (ast) {
    Contract(is_ast_shape_exprs(ast));
    gen_shape_expr(ast->left);
    if (ast->right) {
      gen_printf(", ");
    }
    ast = ast->right;
  }
}

static void gen_shape_def(ast_node *ast) {
  Contract(is_ast_shape_def(ast));
  EXTRACT_NOTNULL(like, ast->left);
  gen_shape_def_base(like);

  if (ast->right) {
    gen_printf("(");
    gen_shape_exprs(ast->right);
    gen_printf(")");
  }
}

static void gen_column_spec(ast_node *ast) {
  // allow null column_spec here so we don't have to test it everywhere
  if (ast) {
    gen_printf("(");
    if (is_ast_shape_def(ast->left)) {
      gen_shape_def(ast->left);
    }
    else {
      EXTRACT(name_list, ast->left);
      if (name_list) {
        gen_name_list(name_list);
      }
    }
    gen_printf(")");
  }
}

static void gen_insert_stmt(ast_node *ast) {
  Contract(is_ast_insert_stmt(ast));
  EXTRACT_ANY_NOTNULL(insert_type, ast->left);
  EXTRACT_NOTNULL(name_columns_values, ast->right);
  EXTRACT_NAME_AST(name_ast, name_columns_values->left);
  EXTRACT_ANY_NOTNULL(columns_values, name_columns_values->right);
  EXTRACT_ANY(insert_dummy_spec, insert_type->left);

  gen_insert_type(insert_type);
  gen_printf(" INTO ");
  gen_name(name_ast);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(" USING ");
    gen_expr_names(columns_values);
  }
  else if (is_select_variant(columns_values)) {
    gen_printf(" USING ");
    gen_select_stmt(columns_values);
  }
  else if (is_ast_columns_values(columns_values)) {
    EXTRACT(column_spec, columns_values->left);
    EXTRACT_ANY(insert_list, columns_values->right);
    gen_column_spec(column_spec);

    if (is_select_variant(insert_list)) {
      gen_printf("\n");
      GEN_BEGIN_INDENT(sel, 2);
        gen_select_stmt(insert_list);
      GEN_END_INDENT(sel);
    }
    else if (is_ast_from_shape(insert_list)) {
      gen_printf(" ");
      gen_from_shape(insert_list);
    }
    else {
      gen_printf(" VALUES (");
      gen_insert_list(insert_list);
      gen_printf(")");
    }

    if (insert_dummy_spec) {
      gen_insert_dummy_spec(insert_dummy_spec);
    }
  }
  else {
    // INSERT [conflict resolution] INTO name DEFAULT VALUES
    Contract(is_ast_default_columns_values(columns_values));
    gen_printf(" DEFAULT VALUES");
  }
}

static void gen_with_insert_stmt(ast_node *ast) {
  Contract(is_ast_with_insert_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(insert_stmt, ast->right);

  gen_with_prefix(with_prefix);
  gen_insert_stmt(insert_stmt);
}

static void gen_insert_returning_stmt(ast_node *ast) {
  Contract(is_ast_insert_returning_stmt(ast));
  EXTRACT_ANY_NOTNULL(insert_stmt, ast->left);
  if (is_ast_with_insert_stmt(insert_stmt)) {
    gen_with_insert_stmt(insert_stmt);
  }
  else {
    gen_insert_stmt(insert_stmt);
  }
  gen_printf("\n  RETURNING ");
  gen_select_expr_list(ast->right);
}

static void gen_expr_names(ast_node *ast) {
  Contract(is_ast_expr_names(ast));

  for (ast_node *list = ast; list; list = list->right) {
    EXTRACT(expr_name, list->left);
    EXTRACT_ANY(expr, expr_name->left);
    EXTRACT_NOTNULL(opt_as_alias, expr_name->right);

    gen_expr(expr, EXPR_PRI_ROOT);
    gen_as_alias(opt_as_alias);

    if (list->right) {
      gen_printf(", ");
    }
  }
}

static void gen_fetch_values_stmt(ast_node *ast) {
  Contract(is_ast_fetch_values_stmt(ast));

  EXTRACT(insert_dummy_spec, ast->left);
  EXTRACT_NOTNULL(name_columns_values, ast->right);
  EXTRACT_STRING(name, name_columns_values->left);
  EXTRACT_ANY_NOTNULL(columns_values, name_columns_values->right);

  gen_printf("FETCH %s", name);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(" USING ");
    gen_expr_names(columns_values);
  }
  else {
    EXTRACT(column_spec, columns_values->left);
    gen_column_spec(column_spec);
    gen_printf(" ");

    if (is_ast_from_shape(columns_values->right)) {
      gen_from_shape(columns_values->right);
    }
    else {
      EXTRACT(insert_list, columns_values->right);
      gen_printf("FROM VALUES (");
      gen_insert_list(insert_list);
      gen_printf(")");
    }
  }

  if (insert_dummy_spec) {
    gen_insert_dummy_spec(insert_dummy_spec);
  }
}

static void gen_assign(ast_node *ast) {
  Contract(is_ast_assign(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf("SET ");
  gen_name(name_ast);
  gen_printf(" := ");
  gen_root_expr(expr);
}

static void gen_let_stmt(ast_node *ast) {
  Contract(is_ast_let_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf("LET ");
  gen_name(name_ast);
  gen_printf(" := ");
  gen_root_expr(expr);
}

static void gen_const_stmt(ast_node *ast) {
  Contract(is_ast_const_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf("CONST ");
  gen_name(name_ast);
  gen_printf(" := ");
  gen_root_expr(expr);
}

static void gen_opt_inout(ast_node *ast) {
  if (is_ast_in(ast)) {
    gen_printf("IN ");
  }
  else if (is_ast_out(ast)) {
    gen_printf("OUT ");
  }
  else if (is_ast_inout(ast)) {
    gen_printf("INOUT ");
  }
  else {
    Contract(!ast);
  }
}

static void gen_normal_param(ast_node *ast) {
  Contract(is_ast_param(ast));
  EXTRACT_ANY(opt_inout, ast->left);
  EXTRACT_NOTNULL(param_detail, ast->right);
  EXTRACT_NAME_AST(name_ast, param_detail->left);
  EXTRACT_ANY_NOTNULL(data_type, param_detail->right);

  gen_opt_inout(opt_inout);
  gen_name(name_ast);
  gen_printf(" ");
  gen_data_type(data_type);
}

static void gen_like_param(ast_node *ast) {
  Contract(is_ast_param(ast));
  EXTRACT_NOTNULL(param_detail, ast->right);
  EXTRACT_NOTNULL(shape_def, param_detail->right);

  if (param_detail->left) {
    EXTRACT_STRING(name, param_detail->left);
    gen_printf("%s ", name);
  }

  gen_shape_def(shape_def);
}

cql_noexport void gen_param(ast_node *ast) {
  Contract(is_ast_param(ast));

  EXTRACT_NOTNULL(param_detail, ast->right);
  if (is_ast_shape_def(param_detail->right)) {
    gen_like_param(ast);
  }
  else {
    gen_normal_param(ast);
  }
}

cql_noexport void gen_params(ast_node *ast) {
  Contract(is_ast_params(ast));

  for (ast_node *cur = ast; cur; cur = cur->right) {
    Contract(is_ast_params(cur));
    EXTRACT_NOTNULL(param, cur->left);

    gen_param(param);

    if (cur->right) {
      gen_printf(", ");
    }
  }
}

static void gen_create_proc_stmt(ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT(stmt_list, proc_params_stmts->right);

  gen_printf("PROC ");
  gen_name(name_ast);
  gen_printf(" (");
  if (params) {
    gen_params(params);
  }
  gen_printf(")\nBEGIN\n");
  gen_stmt_list(stmt_list);
  gen_printf("END");
}

static void gen_declare_proc_from_create_proc(ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  Contract(!for_sqlite());
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);

  gen_printf("DECLARE PROC %s (", name);
  if (params) {
    gen_params(params);
  }
  gen_printf(")");

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // if no SEM then we can't do the full declaration, do the best we can with just AST
#else
  if (ast->sem) {
    if (has_out_stmt_result(ast)) {
      gen_printf(" OUT");
    }

    if (has_out_union_stmt_result(ast)) {
      gen_printf(" OUT UNION");
    }

    if (is_struct(ast->sem->sem_type)) {
      sem_struct *sptr = ast->sem->sptr;

      gen_printf(" (");
      for (uint32_t i = 0; i < sptr->count; i++) {
        gen_sptr_name(sptr, i);
        gen_printf(" ");

        sem_t sem_type = sptr->semtypes[i];
        gen_printf("%s", coretype_string(sem_type));

        CSTR kind = sptr->kinds[i];
        if (kind) {
          gen_type_kind(kind);
        }

        if (is_not_nullable(sem_type)) {
          gen_not_null();
        }

        if (sensitive_flag(sem_type)) {
          gen_printf(" @SENSITIVE");
        }

        if (i + 1 < sptr->count) {
          gen_printf(", ");
        }
      }
      gen_printf(")");

      if ((has_out_stmt_result(ast) || has_out_union_stmt_result(ast)) && is_dml_proc(ast->sem->sem_type)) {
        // out [union] can be DML or not, so we have to specify
        gen_printf(" USING TRANSACTION");
      }
    }
    else if (is_dml_proc(ast->sem->sem_type)) {
      gen_printf(" USING TRANSACTION");
    }
  }
#endif
}

// the current primary output buffer for the closure of declares
static charbuf *closure_output;

// The declares we have already emitted, if NULL we are emitting
// everything every time -- useful for --test output but otherwise
// just redundant at best.  Note cycles are not possible.
// even with no checking because declares form a partial order.
static symtab *closure_emitted;

static bool_t gen_found_set_kind(ast_node *ast, void *context, charbuf *buffer) {
  EXTRACT_STRING(name, ast);
  ast_node *proc = NULL;

  CHARBUF_OPEN(proc_name);
    for (int32_t i = 0; name[i] && name[i] != ' '; i++) {
      bputc(&proc_name, name[i]);
    }
    proc = find_proc(proc_name.ptr);
  CHARBUF_CLOSE(proc_name);

  if (proc) {
    // get canonical name
    EXTRACT_STRING(pname, get_proc_name(proc));

    // we interrupt the current decl to emit a decl for this new name
    if (!closure_emitted || symtab_add(closure_emitted, pname, NULL)) {
      CHARBUF_OPEN(current);
      charbuf *gen_output_saved = gen_output;

      gen_output = &current;
      gen_declare_proc_from_create_or_decl(proc);

      gen_output = closure_output;
      gen_printf("%s;\n", current.ptr);

      gen_output = gen_output_saved;
      CHARBUF_CLOSE(current);
    }
  }

  return false;
}

cql_noexport void gen_declare_proc_closure(ast_node *ast, symtab *emitted) {
  gen_sql_callbacks callbacks = {
     .set_kind_callback = gen_found_set_kind,
     .set_kind_context = emitted
  };
  gen_callbacks = &callbacks;

  EXTRACT_STRING(name, ast->left);
  if (emitted) {
    // if specified then we use this to track what we have already emitted
    symtab_add(emitted, name, NULL);
  }

  closure_output = gen_output;
  closure_emitted = emitted;

  CHARBUF_OPEN(current);
    gen_output = &current;
    gen_declare_proc_from_create_proc(ast);

    gen_output = closure_output;
    gen_printf("%s;\n", current.ptr);
  CHARBUF_CLOSE(current);

  // Make sure we're clean on exit -- mainly so that ASAN leak detection
  // doesn't think there are roots when we are actually done with the
  // stuff.  We want to see the leaks if there are any.
  gen_callbacks = NULL;
  closure_output = NULL;
  closure_emitted = NULL;
}

static void gen_typed_name(ast_node *ast) {
  EXTRACT(typed_name, ast);
  EXTRACT_ANY(name, typed_name->left);
  EXTRACT_ANY_NOTNULL(type, typed_name->right);

  if (name) {
    gen_name(name);
    gen_printf(" ");
  }

  if (is_ast_shape_def(type)) {
    gen_shape_def(type);
  }
  else {
    gen_data_type(type);
  }
}

void gen_typed_names(ast_node *ast) {
  Contract(is_ast_typed_names(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_typed_names(item));
    gen_typed_name(item->left);

    if (item->right) {
      gen_printf(", ");
    }
  }
}

static void gen_declare_proc_no_check_stmt(ast_node *ast) {
  Contract(is_ast_declare_proc_no_check_stmt(ast));
  EXTRACT_ANY_NOTNULL(proc_name, ast->left);
  EXTRACT_STRING(name, proc_name);
  gen_printf("DECLARE PROC %s NO CHECK", name);
}

cql_noexport void gen_declare_interface_stmt(ast_node *ast) {
  Contract(is_ast_declare_interface_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT_NOTNULL(typed_names, proc_params_stmts->right);

  gen_printf("INTERFACE %s", name);

  gen_printf(" (");
  gen_typed_names(typed_names);
  gen_printf(")");
}

static void gen_declare_proc_stmt(ast_node *ast) {
  Contract(is_ast_declare_proc_stmt(ast));
  EXTRACT_NOTNULL(proc_name_type, ast->left);
  EXTRACT_STRING(name, proc_name_type->left);
  EXTRACT_OPTION(type, proc_name_type->right);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT(typed_names, proc_params_stmts->right);

  gen_printf("DECLARE PROC %s (", name);
  if (params) {
    gen_params(params);
  }
  gen_printf(")");

  if (type & PROC_FLAG_USES_OUT) {
    gen_printf(" OUT");
  }

  if (type & PROC_FLAG_USES_OUT_UNION) {
    gen_printf(" OUT UNION");
  }

  if (typed_names) {
    Contract(type & PROC_FLAG_STRUCT_TYPE);
    gen_printf(" (");
    gen_typed_names(typed_names);
    gen_printf(")");
  }

  // we don't emit USING TRANSACTION unless it's needed

  // if it doesnt use DML it's not needed
  if (!(type & PROC_FLAG_USES_DML)) {
    return;
  }

  // out can be either, so emit it if needed
  if (type & (PROC_FLAG_USES_OUT | PROC_FLAG_USES_OUT_UNION)) {
    gen_printf(" USING TRANSACTION");
    return;
  }

  // if the proc returns a struct not via out then it uses SELECT and so it's implictly DML
  if (type & PROC_FLAG_STRUCT_TYPE) {
    return;
  }

  // it's not an OUT and it doesn't have a result but it does use DML
  // the only flag combo left is a basic dml proc.
  Contract(type == PROC_FLAG_USES_DML);
  gen_printf(" USING TRANSACTION");
}

cql_noexport void gen_declare_proc_from_create_or_decl(ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast) || is_ast_declare_proc_stmt(ast));
  if (is_ast_create_proc_stmt(ast)) {
    gen_declare_proc_from_create_proc(ast);
  }
  else {
    gen_declare_proc_stmt(ast);
  }
}

static void gen_declare_select_func_stmt(ast_node *ast) {
  Contract(is_ast_declare_select_func_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf("SELECT FUNC %s (", name);
  if (params) {
    gen_params(params);
  }
  gen_printf(") ");

  if (is_ast_typed_names(ret_data_type)) {
    // table valued function
    gen_printf("(");
    gen_typed_names(ret_data_type);
    gen_printf(")");
  }
  else {
    // standard function
    gen_data_type(ret_data_type);
  }
}

static void gen_declare_select_func_no_check_stmt(ast_node *ast) {
  Contract(is_ast_declare_select_func_no_check_stmt(ast));
  EXTRACT_STRING(name, ast-> left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf("SELECT FUNC %s NO CHECK ", name);

  if (is_ast_typed_names(ret_data_type)) {
    // table valued function
    gen_printf("(");
    gen_typed_names(ret_data_type);
    gen_printf(")");
  }
  else {
    // standard function
    gen_data_type(ret_data_type);
  }
}

static void gen_declare_func_stmt(ast_node *ast) {
  Contract(is_ast_declare_func_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf("FUNC %s (", name);
  if (params) {
    gen_params(params);
  }
  gen_printf(") ");

  gen_data_type(ret_data_type);
}

static void gen_declare_func_no_check_stmt(ast_node *ast) {
  Contract(is_ast_declare_func_no_check_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf("FUNC %s NO CHECK ", name);

  gen_data_type(ret_data_type);
}

static void gen_declare_vars_type(ast_node *ast) {
  Contract(is_ast_declare_vars_type(ast));
  EXTRACT_NOTNULL(name_list, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  gen_printf("DECLARE ");
  gen_name_list(name_list);
  gen_printf(" ");
  gen_data_type(data_type);
}

static void gen_declare_cursor(ast_node *ast) {
  Contract(is_ast_declare_cursor(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(source, ast->right);

  gen_printf("CURSOR ");
  gen_name(name_ast);
  gen_printf(" FOR");

  // we have to handle an insert/delete statement in the AST here which might not be a row source
  // we detect that later in semantic analysis, it's wrong but so are many other things
  // in the ast at this point, we still echo them... We could fix this in the grammar but then
  // (a) the grammar gets more complex for no good reason and (b) the error message isn't as good.
  if (is_row_source(source) ||
      is_ast_call_stmt(source) ||
      is_insert_stmt(source) ||
      is_update_stmt(source) ||
      is_upsert_stmt(source) ||
      is_delete_stmt(source)) {
    // The two statement cases are unified
    gen_printf("\n");
    GEN_BEGIN_INDENT(cursor, 2);
      gen_one_stmt(source);
    GEN_END_INDENT(cursor);
  }
  else {
    gen_printf(" ");
    gen_root_expr(source);
  }
}

static void gen_declare_cursor_like_name(ast_node *ast) {
  Contract(is_ast_declare_cursor_like_name(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_NOTNULL(shape_def, ast->right);

  gen_printf("CURSOR ");
  gen_name(name_ast);
  gen_printf(" ");
  gen_shape_def(shape_def);
}

static void gen_declare_cursor_like_select(ast_node *ast) {
  Contract(is_ast_declare_cursor_like_select(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf("CURSOR ");
  gen_name(name_ast);
  gen_printf(" LIKE ");
  gen_one_stmt(stmt);
}

static void gen_declare_cursor_like_typed_names(ast_node *ast) {
  Contract(is_ast_declare_cursor_like_typed_names(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(typed_names, ast->right);

  gen_printf("CURSOR ");
  gen_name(name_ast);
  gen_printf(" LIKE (");
  gen_typed_names(typed_names);
  gen_printf(")");
}

static void gen_declare_named_type(ast_node *ast) {
  Contract(is_ast_declare_named_type(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  gen_printf("TYPE ");
  gen_name(name_ast);
  gen_printf(" ");
  gen_data_type(data_type);
}

static void gen_declare_value_cursor(ast_node *ast) {
  Contract(is_ast_declare_value_cursor(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf("CURSOR ");
  gen_name(name_ast);
  gen_printf(" FETCH FROM ");
  gen_one_stmt(stmt);
}

static void gen_declare_enum_stmt(ast_node *ast) {
  Contract(is_ast_declare_enum_stmt(ast));
  EXTRACT_NOTNULL(typed_name, ast->left);
  EXTRACT_NOTNULL(enum_values, ast->right);
  gen_printf("ENUM ");
  gen_typed_name(typed_name);
  gen_printf(" (");

  while (enum_values) {
     EXTRACT_NOTNULL(enum_value, enum_values->left);
     EXTRACT_STRING(enum_name, enum_value->left);
     EXTRACT_ANY(expr, enum_value->right);

     gen_printf("\n  %s", enum_name);
     if (expr) {
       gen_printf(" = ");
       gen_root_expr(expr);
     }

     if (enum_values->right) {
       gen_printf(",");
     }

     enum_values = enum_values->right;
  }
  gen_printf("\n)");
}

static void gen_declare_group_stmt(ast_node *ast) {
  Contract(is_ast_declare_group_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(stmt_list, ast->right);
  gen_printf("GROUP %s\nBEGIN\n", name);

  while (stmt_list) {
     EXTRACT_ANY_NOTNULL(stmt, stmt_list->left);
     gen_printf("  ");
     gen_one_stmt(stmt);
     gen_printf(";\n");
     stmt_list = stmt_list->right;
  }
  gen_printf("END");
}

static void gen_declare_const_stmt(ast_node *ast) {
  Contract(is_ast_declare_const_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(const_values, ast->right);
  gen_printf("CONST GROUP %s (", name);

  while (const_values) {
     EXTRACT_NOTNULL(const_value, const_values->left);
     EXTRACT_STRING(const_name, const_value->left);
     EXTRACT_ANY(expr, const_value->right);

     gen_printf("\n  %s", const_name);
     if (expr) {
       gen_printf(" = ");
       gen_root_expr(expr);
     }

     if (const_values->right) {
       gen_printf(",");
     }

     const_values = const_values->right;
  }
  gen_printf("\n)");
}

static void gen_set_from_cursor(ast_node *ast) {
  Contract(is_ast_set_from_cursor(ast));
  EXTRACT_NAME_AST(var_name_ast, ast->left);
  EXTRACT_NAME_AST(cursor_name_ast, ast->right);

  gen_printf("SET ");
  gen_name(var_name_ast);
  gen_printf(" FROM CURSOR ");
  gen_name(cursor_name_ast);
}

static void gen_fetch_stmt(ast_node *ast) {
  Contract(is_ast_fetch_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(name_list, ast->right);

  gen_printf("FETCH ");
  gen_name(name_ast);
  if (name_list) {
    gen_printf(" INTO ");
    gen_name_list(name_list);
  }
}

static void gen_switch_cases(ast_node *ast) {
  Contract(is_ast_switch_case(ast));

  while (ast) {
     EXTRACT_NOTNULL(connector, ast->left);
     if (connector->left) {
        EXTRACT_NOTNULL(expr_list, connector->left);
        EXTRACT(stmt_list, connector->right);

        gen_printf("  WHEN ");
        gen_expr_list(expr_list);
        if (stmt_list) {
            gen_printf(" THEN\n");
            GEN_BEGIN_INDENT(statement, 2);
              gen_stmt_list(stmt_list);
            GEN_END_INDENT(statement);
        }
        else {
          gen_printf(" THEN NOTHING\n");
        }
     }
     else {
        EXTRACT_NOTNULL(stmt_list, connector->right);

        gen_printf("  ELSE\n");
        GEN_BEGIN_INDENT(statement, 2);
          gen_stmt_list(stmt_list);
        GEN_END_INDENT(statement);
     }
     ast = ast->right;
  }
  gen_printf("END");
}

static void gen_switch_stmt(ast_node *ast) {
  Contract(is_ast_switch_stmt(ast));
  EXTRACT_OPTION(all_values, ast->left);
  EXTRACT_NOTNULL(switch_body, ast->right);
  EXTRACT_ANY_NOTNULL(expr, switch_body->left);
  EXTRACT_NOTNULL(switch_case, switch_body->right);

  // SWITCH [expr] [switch_body] END
  // SWITCH [expr] ALL VALUES [switch_body] END

  gen_printf("SWITCH ");
  gen_root_expr(expr);

  if (all_values) {
    gen_printf(" ALL VALUES");
  }
  gen_printf("\n");

  gen_switch_cases(switch_case);
}

static void gen_for_stmt(ast_node *ast) {
  Contract(is_ast_for_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT(for_info, ast->right);

  // FOR [expr] ; stmt_list; BEGIN [stmt_list] END

  gen_printf("FOR ");
  gen_root_expr(expr);
  gen_printf("; ");
  gen_stmt_list_flat(for_info->left);

  gen_printf("\nBEGIN\n");
  gen_stmt_list(for_info->right);
  gen_printf("END");
}

static void gen_while_stmt(ast_node *ast) {
  Contract(is_ast_while_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT(stmt_list, ast->right);

  // WHILE [expr] BEGIN [stmt_list] END

  gen_printf("WHILE ");
  gen_root_expr(expr);

  gen_printf("\nBEGIN\n");
  gen_stmt_list(stmt_list);
  gen_printf("END");
}

static void gen_loop_stmt(ast_node *ast) {
  Contract(is_ast_loop_stmt(ast));
  EXTRACT_NOTNULL(fetch_stmt, ast->left);
  EXTRACT(stmt_list, ast->right);

  // LOOP [fetch_stmt] BEGIN [stmt_list] END

  gen_printf("LOOP ");
  gen_fetch_stmt(fetch_stmt);
  gen_printf("\nBEGIN\n");
  gen_stmt_list(stmt_list);
  gen_printf("END");
}

static void gen_call_stmt(ast_node *ast) {
  Contract(is_ast_call_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(arg_list, ast->right);

  gen_printf("CALL ");
  gen_name(name_ast);
  gen_printf("(");
  if (arg_list) {
    gen_arg_list(arg_list);
  }

  gen_printf(")");
}

static void gen_declare_out_call_stmt(ast_node *ast) {
  EXTRACT_NOTNULL(call_stmt, ast->left);
  gen_printf("DECLARE OUT ");
  gen_call_stmt(call_stmt);
}

static void gen_fetch_call_stmt(ast_node *ast) {
  Contract(is_ast_fetch_call_stmt(ast));
  Contract(is_ast_call_stmt(ast->right));
  EXTRACT_STRING(cursor_name, ast->left);
  EXTRACT_NOTNULL(call_stmt, ast->right);

  gen_printf("FETCH %s FROM ", cursor_name);
  gen_call_stmt(call_stmt);
}

static void gen_continue_stmt(ast_node *ast) {
  Contract(is_ast_continue_stmt(ast));

  gen_printf("CONTINUE");
}

static void gen_leave_stmt(ast_node *ast) {
  Contract(is_ast_leave_stmt(ast));

  gen_printf("LEAVE");
}

static void gen_return_stmt(ast_node *ast) {
  Contract(is_ast_return_stmt(ast));

  gen_printf("RETURN");
}

static void gen_rollback_return_stmt(ast_node *ast) {
  Contract(is_ast_rollback_return_stmt(ast));

  gen_printf("ROLLBACK RETURN");
}

static void gen_commit_return_stmt(ast_node *ast) {
  Contract(is_ast_commit_return_stmt(ast));

  gen_printf("COMMIT RETURN");
}

static void gen_proc_savepoint_stmt(ast_node *ast) {
  Contract(is_ast_proc_savepoint_stmt(ast));
  EXTRACT(stmt_list, ast->left);

  gen_printf("PROC SAVEPOINT");
  gen_printf("\nBEGIN\n");
  gen_stmt_list(stmt_list);
  gen_printf("END");
}

static void gen_throw_stmt(ast_node *ast) {
  Contract(is_ast_throw_stmt(ast));

  gen_printf("THROW");
}

static void gen_begin_trans_stmt(ast_node *ast) {
  Contract(is_ast_begin_trans_stmt(ast));
  EXTRACT_OPTION(mode, ast->left);

  gen_printf("BEGIN");

  if (mode == TRANS_IMMEDIATE) {
    gen_printf(" IMMEDIATE");
  }
  else if (mode == TRANS_EXCLUSIVE) {
    gen_printf(" EXCLUSIVE");
  }
  else {
    // this is the default, and only remaining case, no additional output needed
    Contract(mode == TRANS_DEFERRED);
  }
}

static void gen_commit_trans_stmt(ast_node *ast) {
  Contract(is_ast_commit_trans_stmt(ast));

  gen_printf("COMMIT");
}

static void gen_rollback_trans_stmt(ast_node *ast) {
  Contract(is_ast_rollback_trans_stmt(ast));

  gen_printf("ROLLBACK");

  if (ast->left) {
    EXTRACT_STRING(name, ast->left);
    gen_printf(" TO %s", name);
  }
}

static void gen_savepoint_stmt(ast_node *ast) {
  Contract(is_ast_savepoint_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf("SAVEPOINT %s", name);
}

static void gen_release_savepoint_stmt(ast_node *ast) {
  Contract(is_ast_release_savepoint_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf("RELEASE %s", name);
}

static void gen_trycatch_stmt(ast_node *ast) {
  Contract(is_ast_trycatch_stmt(ast));
  EXTRACT_NAMED(try_list, stmt_list, ast->left);
  EXTRACT_NAMED(catch_list, stmt_list, ast->right);

  gen_printf("TRY\n");
  gen_stmt_list(try_list);
  gen_printf("CATCH\n");
  gen_stmt_list(catch_list);
  gen_printf("END");
}

static void gen_close_stmt(ast_node *ast) {
  Contract(is_ast_close_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf("CLOSE %s", name);
}

static void gen_op_stmt(ast_node *ast) {
  Contract(is_ast_op_stmt(ast));
  EXTRACT_ANY_NOTNULL(data_type, ast->left);
  EXTRACT_ANY_NOTNULL(v1, ast->right);
  EXTRACT_ANY_NOTNULL(v2, v1->right);

  gen_printf("@OP ");
  gen_data_type(data_type);
  gen_printf(" : ");
  gen_name(v1->left);
  gen_printf(" ");
  gen_name(v2->left);
  gen_printf(" AS ");
  gen_name(v2->right);
}

static void gen_out_stmt(ast_node *ast) {
  Contract(is_ast_out_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf("OUT %s", name);
}

static void gen_out_union_stmt(ast_node *ast) {
  Contract(is_ast_out_union_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf("OUT UNION %s", name);
}

static void gen_child_results(ast_node *ast) {
  Contract(is_ast_child_results(ast));

  ast_node *item = ast;
  while (item) {
    Contract(is_ast_child_results(item));

    EXTRACT_NOTNULL(child_result, item->left);
    EXTRACT_NOTNULL(call_stmt, child_result->left);
    EXTRACT_NOTNULL(named_result, child_result->right);

    EXTRACT_NOTNULL(name_list, named_result->right);
    CSTR child_column_name = NULL;
    if (named_result->left) {
      EXTRACT_STRING(name, named_result->left);
      child_column_name = name;
    }

    gen_printf("\n  ");
    gen_call_stmt(call_stmt);
    gen_printf(" USING (");
    gen_name_list(name_list);
    gen_printf(")");

    if (child_column_name) {
      gen_printf(" AS %s", child_column_name);
    }

    if (item->right) {
      gen_printf(" AND");
    }

    item = item->right;
  }
}

static void gen_out_union_parent_child_stmt(ast_node *ast) {
  Contract(is_ast_out_union_parent_child_stmt(ast));
  EXTRACT_NOTNULL(call_stmt, ast->left);
  EXTRACT_NOTNULL(child_results, ast->right);

  gen_printf("OUT UNION ");
  gen_call_stmt(call_stmt);
  gen_printf(" JOIN ");
  gen_child_results(child_results);
}

static void gen_echo_stmt(ast_node *ast) {
  Contract(is_ast_echo_stmt(ast));
  EXTRACT_STRING(rt_name, ast->left);

  gen_printf("@ECHO %s, ", rt_name);
  gen_root_expr(ast->right);  // emit the quoted literal
}

static void gen_schema_upgrade_script_stmt(ast_node *ast) {
  Contract(is_ast_schema_upgrade_script_stmt(ast));

  gen_printf("@SCHEMA_UPGRADE_SCRIPT");
}

static void gen_schema_upgrade_version_stmt(ast_node *ast) {
  Contract(is_ast_schema_upgrade_version_stmt(ast));
  EXTRACT_OPTION(vers, ast->left);

  gen_printf("@SCHEMA_UPGRADE_VERSION (%d)", vers);
}

static void gen_previous_schema_stmt(ast_node *ast) {
  Contract(is_ast_previous_schema_stmt(ast));

  gen_printf("@PREVIOUS_SCHEMA");
}

static void gen_enforcement_options(ast_node *ast) {
  EXTRACT_OPTION(option, ast);

  switch (option) {
    case ENFORCE_CAST:
      gen_printf("CAST");
      break;

    case ENFORCE_STRICT_JOIN:
      gen_printf("JOIN");
      break;

    case ENFORCE_FK_ON_UPDATE:
      gen_printf("FOREIGN KEY ON UPDATE");
      break;

    case ENFORCE_UPSERT_STMT:
      gen_printf("UPSERT STATEMENT");
      break;

    case ENFORCE_WINDOW_FUNC:
      gen_printf("WINDOW FUNCTION");
      break;

    case ENFORCE_WITHOUT_ROWID:
      gen_printf("WITHOUT ROWID");
      break;

    case ENFORCE_TRANSACTION:
      gen_printf("TRANSACTION");
      break;

    case ENFORCE_SELECT_IF_NOTHING:
      gen_printf("SELECT IF NOTHING");
      break;

    case ENFORCE_INSERT_SELECT:
      gen_printf("INSERT SELECT");
      break;

    case ENFORCE_TABLE_FUNCTION:
      gen_printf("TABLE FUNCTION");
      break;

    case ENFORCE_IS_TRUE:
      gen_printf("IS TRUE");
      break;

    case ENFORCE_SIGN_FUNCTION:
      gen_printf("SIGN FUNCTION");
      break;

    case ENFORCE_CURSOR_HAS_ROW:
      gen_printf("CURSOR HAS ROW");
      break;

    case ENFORCE_UPDATE_FROM:
      gen_printf("UPDATE FROM");
      break;

    case ENFORCE_AND_OR_NOT_NULL_CHECK:
      gen_printf("AND OR NOT NULL CHECK");
      break;

    default:
      // this is all that's left
      Contract(option == ENFORCE_FK_ON_DELETE);
      gen_printf("FOREIGN KEY ON DELETE");
      break;
  }
}

static void gen_enforce_strict_stmt(ast_node *ast) {
  Contract(is_ast_enforce_strict_stmt(ast));
  gen_printf("@ENFORCE_STRICT ");
  gen_enforcement_options(ast->left);
}

static void gen_enforce_normal_stmt(ast_node *ast) {
  Contract(is_ast_enforce_normal_stmt(ast));
  gen_printf("@ENFORCE_NORMAL ");
  gen_enforcement_options(ast->left);
}

static void gen_enforce_reset_stmt(ast_node *ast) {
  Contract(is_ast_enforce_reset_stmt(ast));
  gen_printf("@ENFORCE_RESET");
}

static void gen_enforce_push_stmt(ast_node *ast) {
  Contract(is_ast_enforce_push_stmt(ast));
  gen_printf("@ENFORCE_PUSH");
}

static void gen_enforce_pop_stmt(ast_node *ast) {
  Contract(is_ast_enforce_pop_stmt(ast));
  gen_printf("@ENFORCE_POP");
}

static void gen_region_spec(ast_node *ast) {
  Contract(is_ast_region_spec(ast));
  EXTRACT_OPTION(type, ast->right);
  bool_t is_private = (type == PRIVATE_REGION);

  gen_name(ast->left);
  if (is_private) {
    gen_printf(" PRIVATE");
  }
}

static void gen_region_list(ast_node *ast) {
  Contract(is_ast_region_list(ast));
  while (ast) {
    gen_region_spec(ast->left);
    if (ast->right) {
      gen_printf(", ");
    }
    ast = ast->right;
  }
}

static void gen_declare_deployable_region_stmt(ast_node *ast) {
  Contract(is_ast_declare_deployable_region_stmt(ast));
  gen_printf("@DECLARE_DEPLOYABLE_REGION ");
  gen_name(ast->left);
  if (ast->right) {
    gen_printf(" USING ");
    gen_region_list(ast->right);
  }
}

static void gen_declare_schema_region_stmt(ast_node *ast) {
  Contract(is_ast_declare_schema_region_stmt(ast));
  gen_printf("@DECLARE_SCHEMA_REGION ");
  gen_name(ast->left);
  if (ast->right) {
    gen_printf(" USING ");
    gen_region_list(ast->right);
  }
}

static void gen_begin_schema_region_stmt(ast_node *ast) {
  Contract(is_ast_begin_schema_region_stmt(ast));
  gen_printf("@BEGIN_SCHEMA_REGION ");
  gen_name(ast->left);
}

static void gen_end_schema_region_stmt(ast_node *ast) {
  Contract(is_ast_end_schema_region_stmt(ast));
  gen_printf("@END_SCHEMA_REGION");
}

static void gen_schema_unsub_stmt(ast_node *ast) {
  Contract(is_ast_schema_unsub_stmt(ast));
  EXTRACT_NOTNULL(version_annotation, ast->left);
  EXTRACT_NAME_AST(name_ast, version_annotation->right);

  gen_printf("@UNSUB(");
  gen_name(name_ast);
  gen_printf(")");
}

static void gen_schema_ad_hoc_migration_stmt(ast_node *ast) {
  Contract(is_ast_schema_ad_hoc_migration_stmt(ast));
  EXTRACT_ANY_NOTNULL(l, ast->left);
  EXTRACT_ANY(r, ast->right);

  // two arg version is a recreate upgrade instruction
  if (r) {
    EXTRACT_STRING(group, l);
    EXTRACT_STRING(proc, r);
    gen_printf("@SCHEMA_AD_HOC_MIGRATION FOR @RECREATE(");
    gen_printf("%s, %s)", group, proc);
  }
  else {
    gen_printf("@SCHEMA_AD_HOC_MIGRATION(");
    gen_version_and_proc(l);
    gen_printf(")");
  }
}

static void gen_emit_group_stmt(ast_node *ast) {
  Contract(is_ast_emit_group_stmt(ast));
  EXTRACT(name_list, ast->left);

  gen_printf("@EMIT_GROUP");
  if (name_list) {
    gen_printf(" ");
    gen_name_list(name_list);
  }
}


static void gen_emit_enums_stmt(ast_node *ast) {
  Contract(is_ast_emit_enums_stmt(ast));
  EXTRACT(name_list, ast->left);

  gen_printf("@EMIT_ENUMS");
  if (name_list) {
    gen_printf(" ");
    gen_name_list(name_list);
  }
}

static void gen_emit_constants_stmt(ast_node *ast) {
  Contract(is_ast_emit_constants_stmt(ast));
  EXTRACT_NOTNULL(name_list, ast->left);

  gen_printf("@EMIT_CONSTANTS ");
  gen_name_list(name_list);
}

static void gen_conflict_target(ast_node *ast) {
  Contract(is_ast_conflict_target(ast));
  EXTRACT(indexed_columns, ast->left);
  EXTRACT(opt_where, ast->right);

  gen_printf("\nON CONFLICT");
  if (indexed_columns) {
    gen_printf(" (");
    gen_indexed_columns(indexed_columns);
    gen_printf(")");
  }
  if (opt_where) {
    gen_printf("\n");
    gen_opt_where(opt_where);
    gen_printf(" ");
  }
}

static void gen_upsert_update(ast_node *ast) {
  Contract(is_ast_upsert_update(ast));
  EXTRACT_NOTNULL(conflict_target, ast->left);
  EXTRACT(update_stmt, ast->right);

  gen_conflict_target(conflict_target);
  gen_printf("\nDO ");
  if (update_stmt) {
    gen_update_stmt(update_stmt);
  }
  else {
    gen_printf("NOTHING");
  }
}

static void gen_upsert_stmt(ast_node *ast) {
  Contract(is_ast_upsert_stmt(ast));

  EXTRACT_NOTNULL(insert_stmt, ast->left);
  EXTRACT_NOTNULL(upsert_update, ast->right);

  gen_insert_stmt(insert_stmt);
  gen_upsert_update(upsert_update);
}

static void gen_with_upsert_stmt(ast_node *ast) {
  Contract(is_ast_with_upsert_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(upsert_stmt, ast->right);

  gen_with_prefix(with_prefix);
  gen_upsert_stmt(upsert_stmt);
}

static void gen_upsert_returning_stmt(ast_node *ast) {
  Contract(is_ast_upsert_returning_stmt(ast));
  EXTRACT_ANY_NOTNULL(upsert_stmt, ast->left);
  if (is_ast_with_upsert_stmt(upsert_stmt)) {
    gen_with_upsert_stmt(upsert_stmt);
  }
  else {
    gen_upsert_stmt(upsert_stmt);
  }
  gen_printf("\n  RETURNING ");
  gen_select_expr_list(ast->right);
}


static void gen_keep_table_name_in_aliases_stmt(ast_node *ast) {
  Contract(is_ast_keep_table_name_in_aliases_stmt(ast));
  gen_printf("@KEEP_TABLE_NAME_IN_ALIASES");
}

static void gen_explain_stmt(ast_node *ast) {
  Contract(is_ast_explain_stmt(ast));
  EXTRACT_OPTION(query_plan, ast->left);
  EXTRACT_ANY_NOTNULL(stmt_target, ast->right);

  gen_printf("EXPLAIN");
  if (query_plan == EXPLAIN_QUERY_PLAN) {
    gen_printf(" QUERY PLAN");
  }
  gen_printf("\n");
  gen_one_stmt(stmt_target);
}

static void gen_macro_formal(ast_node *macro_formal) {
  Contract(is_ast_macro_formal(macro_formal));
  EXTRACT_STRING(l, macro_formal->left);
  EXTRACT_STRING(r, macro_formal->right);
  gen_printf("%s! %s", l, r);
}

static void gen_macro_formals(ast_node *macro_formals) {
  for ( ; macro_formals; macro_formals = macro_formals->right) {
     Contract(is_ast_macro_formals(macro_formals));
     gen_macro_formal(macro_formals->left);
     if (macro_formals->right) {
       gen_printf(", ");
     }
  }
}

static void gen_expr_macro_def(ast_node *ast) {
  Contract(is_ast_expr_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(EXPR) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_root_expr(body);
  GEN_END_INDENT(body_indent);
  gen_printf("\nEND");
}

static void gen_stmt_list_macro_def(ast_node *ast) {
  Contract(is_ast_stmt_list_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(STMT_LIST) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  gen_stmt_list(body);
  gen_printf("END");
}

static void gen_select_core_macro_def(ast_node *ast) {
  Contract(is_ast_select_core_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(SELECT_CORE) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_select_core_list(body);
  GEN_END_INDENT(body_indent);
  gen_printf("\nEND");
}

static void gen_select_expr_macro_def(ast_node *ast) {
  Contract(is_ast_select_expr_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(SELECT_EXPR) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_select_expr_list(body);
  GEN_END_INDENT(body_indent);
  gen_printf("\nEND");
}

static void gen_query_parts_macro_def(ast_node *ast) {
  Contract(is_ast_query_parts_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(QUERY_PARTS) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_query_parts(body);
  GEN_END_INDENT(body_indent);
  gen_printf("\nEND");
}

static void gen_cte_tables_macro_def(ast_node *ast) {
  Contract(is_ast_cte_tables_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf("@MACRO(CTE_TABLES) %s!(", name);
  gen_macro_formals(macro_name_formals->right);
  gen_printf(")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_cte_tables(body, "");
  GEN_END_INDENT(body_indent);
  gen_printf("END");
}

cql_data_defn( int32_t gen_stmt_level );

static void gen_stmt_list_flat(ast_node *root) {
  Contract(is_ast_stmt_list(root));

  for (ast_node *semi = root; semi; semi = semi->right) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, semi);

    if (misc_attrs) {
      gen_misc_attrs(misc_attrs);
    }

    gen_one_stmt(stmt);

    bool_t prep = is_ast_ifdef_stmt(stmt) || is_ast_ifndef_stmt(stmt);

    if (!prep) {
      gen_printf(";");
    }

    if (semi->right) {
       gen_printf(" ");
    }
  }
}

static void gen_stmt_list(ast_node *root) {
  if (!root) {
    return;
  }

  gen_stmt_level++;

  int32_t indent_level = (gen_stmt_level > 1) ? 2 : 0;

  GEN_BEGIN_INDENT(statement, indent_level);

  bool first_stmt = true;

  for (ast_node *semi = root; semi; semi = semi->right) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, semi);
    if (misc_attrs) {
      // do not echo declarations that came from the builtin stream
      if (exists_attribute_str(misc_attrs, "builtin")) {
        continue;
      }
    }

    if (gen_stmt_level == 1 && !first_stmt) {
      gen_printf("\n");
    }

    first_stmt = false;

    if (misc_attrs) {
      gen_misc_attrs(misc_attrs);
    }
    gen_one_stmt(stmt);

    bool_t prep = is_ast_ifdef_stmt(stmt) || is_ast_ifndef_stmt(stmt);

    if (!prep) {
      gen_printf(";");
    }

    if (gen_stmt_level != 0 || semi->right != NULL) {
       gen_printf("\n");
    }
  }

  GEN_END_INDENT(statement);
  gen_stmt_level--;
}

cql_noexport void gen_one_stmt(ast_node *stmt)  {
  if (is_any_macro_ref(stmt)) {
    gen_any_macro_ref(stmt);
    return;
  }

  symtab_entry *entry = symtab_find(gen_stmts, stmt->type);

  // These are all the statements there are, we have to find it in this table
  // or else someone added a new statement and it isn't supported yet.
  Invariant(entry);
  ((void (*)(ast_node*))entry->val)(stmt);
}

cql_noexport void gen_one_stmt_and_misc_attrs(ast_node *stmt)  {
  EXTRACT_MISC_ATTRS(stmt, misc_attrs);
  if (misc_attrs) {
    gen_misc_attrs(misc_attrs);
  }
  gen_one_stmt(stmt);
}

// so the name doesn't otherwise conflict in the amalgam
#undef output

#undef STMT_INIT
#define STMT_INIT(x) symtab_add(gen_stmts, k_ast_ ## x, (void *)gen_ ## x)

#undef EXPR_INIT
#define EXPR_INIT(x, func, str, pri_new) \
  static gen_expr_dispatch expr_disp_ ## x = { func, str, pri_new }; \
  symtab_add(gen_exprs, k_ast_ ## x, (void *)&expr_disp_ ## x);

#undef MACRO_INIT
#define MACRO_INIT(x) \
  symtab_add(gen_macros, k_ast_ ## x ## _macro_ref, (void *)gen_macro_ref); \
  symtab_add(gen_macros, k_ast_ ## x ## _macro_arg_ref, (void *)gen_macro_arg_ref); \

cql_noexport void gen_init() {
  gen_stmts = symtab_new();
  gen_exprs = symtab_new();
  gen_macros = symtab_new();

  MACRO_INIT(expr);
  MACRO_INIT(stmt_list);
  MACRO_INIT(query_parts);
  MACRO_INIT(cte_tables);
  MACRO_INIT(select_core);
  MACRO_INIT(select_expr);
  MACRO_INIT(unknown);

  STMT_INIT(alter_table_add_column_stmt);
  STMT_INIT(assign);
  STMT_INIT(begin_schema_region_stmt);
  STMT_INIT(begin_trans_stmt);
  STMT_INIT(call_stmt);
  STMT_INIT(close_stmt);
  STMT_INIT(commit_return_stmt);
  STMT_INIT(commit_trans_stmt);
  STMT_INIT(conflict_target);
  STMT_INIT(const_stmt);
  STMT_INIT(continue_stmt);
  STMT_INIT(create_index_stmt);
  STMT_INIT(create_proc_stmt);
  STMT_INIT(create_table_stmt);
  STMT_INIT(create_trigger_stmt);
  STMT_INIT(create_view_stmt);
  STMT_INIT(create_virtual_table_stmt);
  STMT_INIT(cte_tables_macro_def);
  STMT_INIT(declare_const_stmt);
  STMT_INIT(declare_cursor);
  STMT_INIT(declare_cursor_like_name);
  STMT_INIT(declare_cursor_like_select);
  STMT_INIT(declare_cursor_like_typed_names);
  STMT_INIT(declare_deployable_region_stmt);
  STMT_INIT(declare_enum_stmt);
  STMT_INIT(declare_func_no_check_stmt);
  STMT_INIT(declare_func_stmt);
  STMT_INIT(declare_group_stmt);
  STMT_INIT(declare_interface_stmt);
  STMT_INIT(declare_named_type);
  STMT_INIT(declare_out_call_stmt);
  STMT_INIT(declare_proc_no_check_stmt);
  STMT_INIT(declare_proc_stmt);
  STMT_INIT(declare_schema_region_stmt);
  STMT_INIT(declare_select_func_no_check_stmt);
  STMT_INIT(declare_select_func_stmt);
  STMT_INIT(declare_value_cursor);
  STMT_INIT(declare_vars_type);
  STMT_INIT(delete_returning_stmt);
  STMT_INIT(delete_stmt);
  STMT_INIT(drop_index_stmt);
  STMT_INIT(drop_table_stmt);
  STMT_INIT(drop_trigger_stmt);
  STMT_INIT(drop_view_stmt);
  STMT_INIT(echo_stmt);
  STMT_INIT(emit_constants_stmt);
  STMT_INIT(emit_enums_stmt);
  STMT_INIT(emit_group_stmt);
  STMT_INIT(end_schema_region_stmt);
  STMT_INIT(enforce_normal_stmt);
  STMT_INIT(enforce_pop_stmt);
  STMT_INIT(enforce_push_stmt);
  STMT_INIT(enforce_reset_stmt);
  STMT_INIT(enforce_strict_stmt);
  STMT_INIT(explain_stmt);
  STMT_INIT(expr_stmt);
  STMT_INIT(fetch_call_stmt);
  STMT_INIT(fetch_stmt);
  STMT_INIT(fetch_values_stmt);
  STMT_INIT(for_stmt);
  STMT_INIT(guard_stmt);
  STMT_INIT(if_stmt);
  STMT_INIT(ifdef_stmt);
  STMT_INIT(ifndef_stmt);
  STMT_INIT(insert_stmt);
  STMT_INIT(insert_returning_stmt);
  STMT_INIT(leave_stmt);
  STMT_INIT(let_stmt);
  STMT_INIT(loop_stmt);
  STMT_INIT(stmt_list_macro_def);
  STMT_INIT(expr_macro_def);
  STMT_INIT(op_stmt);
  STMT_INIT(out_stmt);
  STMT_INIT(out_union_parent_child_stmt);
  STMT_INIT(out_union_stmt);
  STMT_INIT(previous_schema_stmt);
  STMT_INIT(proc_savepoint_stmt);
  STMT_INIT(query_parts_macro_def);
  STMT_INIT(release_savepoint_stmt);
  STMT_INIT(return_stmt);
  STMT_INIT(rollback_return_stmt);
  STMT_INIT(rollback_trans_stmt);
  STMT_INIT(savepoint_stmt);
  STMT_INIT(schema_ad_hoc_migration_stmt);
  STMT_INIT(schema_unsub_stmt);
  STMT_INIT(schema_upgrade_script_stmt);
  STMT_INIT(schema_upgrade_version_stmt);
  STMT_INIT(select_core_macro_def);
  STMT_INIT(select_expr_macro_def);
  STMT_INIT(select_nothing_stmt);
  STMT_INIT(select_stmt);
  STMT_INIT(set_from_cursor);
  STMT_INIT(switch_stmt);
  STMT_INIT(throw_stmt);
  STMT_INIT(trycatch_stmt);
  STMT_INIT(update_cursor_stmt);
  STMT_INIT(update_returning_stmt);
  STMT_INIT(update_stmt);
  STMT_INIT(upsert_returning_stmt);
  STMT_INIT(upsert_stmt);
  STMT_INIT(upsert_update);
  STMT_INIT(while_stmt);
  STMT_INIT(with_delete_stmt);
  STMT_INIT(with_insert_stmt);
  STMT_INIT(with_select_stmt);
  STMT_INIT(with_update_stmt);
  STMT_INIT(with_upsert_stmt);

  STMT_INIT(keep_table_name_in_aliases_stmt);

  EXPR_INIT(table_star, gen_expr_table_star, "T.*", EXPR_PRI_ROOT);
  EXPR_INIT(at_id, gen_expr_at_id, "@ID", EXPR_PRI_ROOT);
  EXPR_INIT(star, gen_expr_star, "*", EXPR_PRI_ROOT);
  EXPR_INIT(num, gen_expr_num, "NUM", EXPR_PRI_ROOT);
  EXPR_INIT(str, gen_expr_str, "STR", EXPR_PRI_ROOT);
  EXPR_INIT(blob, gen_expr_blob, "BLB", EXPR_PRI_ROOT);
  EXPR_INIT(null, gen_expr_null, "NULL", EXPR_PRI_ROOT);
  EXPR_INIT(dot, gen_expr_dot, ".", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(macro_text, gen_expr_macro_text, "!", EXPR_PRI_ROOT);
  EXPR_INIT(const, gen_expr_const, "CONST", EXPR_PRI_ROOT);
  EXPR_INIT(bin_and, gen_binary, "&", EXPR_PRI_BINARY);
  EXPR_INIT(bin_or, gen_binary, "|", EXPR_PRI_BINARY);
  EXPR_INIT(lshift, gen_binary, "<<", EXPR_PRI_BINARY);
  EXPR_INIT(rshift, gen_binary, ">>", EXPR_PRI_BINARY);
  EXPR_INIT(mul, gen_binary, "*", EXPR_PRI_MUL);
  EXPR_INIT(div, gen_binary, "/", EXPR_PRI_MUL);
  EXPR_INIT(mod, gen_binary, "%", EXPR_PRI_MUL);
  EXPR_INIT(add, gen_binary, "+", EXPR_PRI_ADD);
  EXPR_INIT(sub, gen_binary, "-", EXPR_PRI_ADD);
  EXPR_INIT(not, gen_unary, "NOT ", EXPR_PRI_NOT);
  EXPR_INIT(tilde, gen_unary, "~", EXPR_PRI_TILDE);
  EXPR_INIT(collate, gen_binary, "COLLATE", EXPR_PRI_COLLATE);
  EXPR_INIT(uminus, gen_uminus, "-", EXPR_PRI_TILDE);
  EXPR_INIT(eq, gen_binary, "=", EXPR_PRI_EQUALITY);
  EXPR_INIT(lt, gen_binary, "<", EXPR_PRI_INEQUALITY);
  EXPR_INIT(gt, gen_binary, ">", EXPR_PRI_INEQUALITY);
  EXPR_INIT(ne, gen_binary, "<>", EXPR_PRI_INEQUALITY);
  EXPR_INIT(ge, gen_binary, ">=", EXPR_PRI_INEQUALITY);
  EXPR_INIT(le, gen_binary, "<=", EXPR_PRI_INEQUALITY);
  EXPR_INIT(expr_assign, gen_binary, ":=", EXPR_PRI_ASSIGN);
  EXPR_INIT(add_eq, gen_binary, "+=", EXPR_PRI_ASSIGN);
  EXPR_INIT(sub_eq, gen_binary, "-=", EXPR_PRI_ASSIGN);
  EXPR_INIT(mul_eq, gen_binary, "*=", EXPR_PRI_ASSIGN);
  EXPR_INIT(div_eq, gen_binary, "/=", EXPR_PRI_ASSIGN);
  EXPR_INIT(mod_eq, gen_binary, "%=", EXPR_PRI_ASSIGN);
  EXPR_INIT(or_eq, gen_binary, "|=", EXPR_PRI_ASSIGN);
  EXPR_INIT(and_eq, gen_binary, "&=", EXPR_PRI_ASSIGN);
  EXPR_INIT(rs_eq, gen_binary, ">>=", EXPR_PRI_ASSIGN);
  EXPR_INIT(ls_eq, gen_binary, "<<=", EXPR_PRI_ASSIGN);
  EXPR_INIT(array, gen_array, "[]", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(call, gen_expr_call, "CALL", EXPR_PRI_ROOT);
  EXPR_INIT(window_func_inv, gen_expr_window_func_inv, "WINDOW-FUNC-INV", EXPR_PRI_ROOT);
  EXPR_INIT(raise, gen_expr_raise, "RAISE", EXPR_PRI_ROOT);
  EXPR_INIT(between, gen_expr_between, "BETWEEN", EXPR_PRI_BETWEEN);
  EXPR_INIT(not_between, gen_expr_not_between, "NOT BETWEEN", EXPR_PRI_BETWEEN);
  EXPR_INIT(and, gen_binary, "AND", EXPR_PRI_AND);
  EXPR_INIT(between_rewrite, gen_expr_between_rewrite, "BETWEEN", EXPR_PRI_BETWEEN);
  EXPR_INIT(or, gen_binary, "OR", EXPR_PRI_OR);
  EXPR_INIT(select_stmt, gen_expr_select, "SELECT", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_throw_expr, gen_expr_select_if_nothing_throw, "IF NOTHING THEN THROW", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_expr, gen_expr_select_if_nothing, "IF NOTHING THEN", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_or_null_expr, gen_expr_select_if_nothing, "IF NOTHING OR NULL THEN", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_or_null_throw_expr, gen_expr_select_if_nothing_throw, "IF NOTHING OR NULL THEN THROW", EXPR_PRI_ROOT);
  EXPR_INIT(with_select_stmt, gen_expr_select, "WITH...SELECT", EXPR_PRI_ROOT);
  EXPR_INIT(is, gen_binary, "IS", EXPR_PRI_EQUALITY);
  EXPR_INIT(is_not, gen_binary, "IS NOT", EXPR_PRI_EQUALITY);
  EXPR_INIT(is_true, gen_postfix, "IS TRUE", EXPR_PRI_EQUALITY);
  EXPR_INIT(is_false, gen_postfix, "IS FALSE", EXPR_PRI_EQUALITY);
  EXPR_INIT(is_not_true, gen_postfix, "IS NOT TRUE", EXPR_PRI_EQUALITY);
  EXPR_INIT(is_not_false, gen_postfix, "IS NOT FALSE", EXPR_PRI_EQUALITY);
  EXPR_INIT(like, gen_binary, "LIKE", EXPR_PRI_EQUALITY);
  EXPR_INIT(not_like, gen_binary, "NOT LIKE", EXPR_PRI_EQUALITY);
  EXPR_INIT(match, gen_binary, "MATCH", EXPR_PRI_EQUALITY);
  EXPR_INIT(not_match, gen_binary, "NOT MATCH", EXPR_PRI_EQUALITY);
  EXPR_INIT(regexp, gen_binary, "REGEXP", EXPR_PRI_EQUALITY);
  EXPR_INIT(not_regexp, gen_binary, "NOT REGEXP", EXPR_PRI_EQUALITY);
  EXPR_INIT(glob, gen_binary, "GLOB", EXPR_PRI_EQUALITY);
  EXPR_INIT(not_glob, gen_binary, "NOT GLOB", EXPR_PRI_EQUALITY);
  EXPR_INIT(in_pred, gen_expr_in_pred, "IN", EXPR_PRI_EQUALITY);
  EXPR_INIT(not_in, gen_expr_not_in, "NOT IN", EXPR_PRI_EQUALITY);
  EXPR_INIT(case_expr, gen_expr_case, "CASE", EXPR_PRI_ROOT);
  EXPR_INIT(exists_expr, gen_expr_exists, "EXISTS", EXPR_PRI_ROOT);
  EXPR_INIT(cast_expr, gen_expr_cast, "CAST", EXPR_PRI_ROOT);
  EXPR_INIT(type_check_expr, gen_expr_type_check, "TYPE_CHECK", EXPR_PRI_ROOT);
  EXPR_INIT(concat, gen_concat, "||", EXPR_PRI_CONCAT);
  EXPR_INIT(jex1, gen_jex1, "->", EXPR_PRI_CONCAT);
  EXPR_INIT(jex2, gen_jex2, "->>", EXPR_PRI_CONCAT);
  EXPR_INIT(reverse_apply, gen_binary_no_spaces, ":", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(reverse_apply_poly_args, gen_binary_no_spaces, ":", EXPR_PRI_REVERSE_APPLY);
}

cql_export void gen_cleanup() {
  SYMTAB_CLEANUP(gen_stmts);
  SYMTAB_CLEANUP(gen_exprs);
  SYMTAB_CLEANUP(gen_macros);
  gen_output = NULL;
  gen_callbacks = NULL;
  used_alias_syms = NULL;
}

#endif
