/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_GEN_SQL)

// stubs to avoid link errors,

cql_noexport void gen_init(CS) {}
cql_export void gen_cleanup(CS) {}
cql_noexport void gen_misc_attrs_to_stdout(CS, ast_node *ast) {}
cql_noexport void gen_to_stdout(CS, ast_node *ast, gen_func fn) {}
cql_noexport void gen_one_stmt_to_stdout(CS, ast_node *ast) {}
cql_noexport void gen_stmt_list_to_stdout(CS, ast_node *ast) {}

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
#include "cql_state.h"

// for dispatching expression types
typedef struct gen_expr_dispatch {
  void (*func)(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new);
  CSTR str;
  int32_t pri_new;
} gen_expr_dispatch;

//static symtab *gen_stmts;
//static symtab *gen_exprs;
//static charbuf *gen_output;
//static gen_sql_callbacks *gen_callbacks = NULL;
#define gen_callbacks_lv CS->gen_callbacks
#define gen_callbacks_rv ((gen_sql_callbacks*)gen_callbacks_lv)

//static symtab *used_alias_syms = NULL;

// forward references for things that appear out of order or mutually call each other
static void gen_select_core_list(CqlState* CS, ast_node *ast);
static void gen_groupby_list(CqlState* CS, ast_node *_Nonnull ast);
static void gen_orderby_list(CqlState* CS, ast_node *_Nonnull ast);
static void gen_stmt_list(CqlState* CS, ast_node *_Nullable ast);
static void gen_expr(CqlState* CS, ast_node *_Nonnull ast, int32_t pri);
static void gen_version_attrs(CqlState* CS, ast_node *_Nullable ast);
static void gen_col_def(CqlState* CS, ast_node *_Nonnull ast);
static void gen_query_parts(CqlState* CS, ast_node *ast);
static void gen_select_stmt(CqlState* CS, ast_node *_Nonnull ast);
static void gen_opt_where(CqlState* CS, ast_node *ast);
static void gen_opt_orderby(CqlState* CS, ast_node *ast);
static void gen_shape_arg(CqlState* CS, ast_node *ast);
static void gen_insert_list(CqlState* CS, ast_node *_Nullable ast);
static void gen_column_spec(CqlState* CS, ast_node *ast);
static void gen_from_shape(CqlState* CS, ast_node *ast);
static void gen_opt_filter_clause(CqlState* CS, ast_node *ast);
static void gen_if_not_exists(CqlState* CS, ast_node *ast, bool_t if_not_exist);
static void gen_shape_def(CqlState* CS, ast_node *ast);
static void gen_expr_names(CqlState* CS, ast_node *ast);
static void gen_conflict_clause(CqlState* CS, ast_node *ast);
static void gen_call_stmt(CqlState* CS, ast_node *ast);
static void gen_shared_cte(CqlState* CS, ast_node *ast);
static bool_t gen_found_set_kind(CqlState* CS, ast_node *ast, void *context, charbuf *buffer);
static void gen_cte_tables(CqlState* CS, ast_node *ast, CSTR prefix);
static void gen_select_expr_list(CqlState* CS, ast_node *ast);
static void gen_select_expr_macro_ref(CqlState* CS, ast_node *ast);
static void gen_select_expr_macro_arg_ref(CqlState* CS, ast_node *ast);
static void gen_expr_at_id(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new);
static void gen_select_expr(CqlState* CS, ast_node *ast);

//static int32_t gen_indent = 0;
//static int32_t pending_indent = 0;

#define GEN_BEGIN_INDENT(name, level) \
  int32_t name##_level = CS->gen_indent; \
  CS->gen_indent += level; \
  CS->pending_indent = CS->gen_indent;

#define GEN_END_INDENT(name) \
  CS->gen_indent = name##_level; \
  if (CS->pending_indent > CS->gen_indent) CS->pending_indent = CS->gen_indent;

cql_noexport void gen_printf(CqlState* CS, const char *format, ...) {
 CHARBUF_OPEN(tmp);
 va_list args;
 va_start(args, format);
 vbprintf(&tmp, format, args);
 va_end(args);

 for (CSTR p = tmp.ptr; *p; p++) {
    if (*p != '\n') {
      for (int32_t i = 0; i < CS->pending_indent; i++) bputc(CS->gen_output, ' ');
      CS->pending_indent = 0;
    }
    bputc(CS->gen_output, *p);
    if (*p == '\n') {
      CS->pending_indent = CS->gen_indent;
    }
 }
 CHARBUF_CLOSE(tmp);
}

static void gen_literal(CqlState* CS, CSTR literal) {
  for (int32_t i = 0; i < CS->pending_indent; i++) bputc(CS->gen_output, ' ');
  CS->pending_indent = 0;
  bprintf(CS->gen_output, "%s", literal);
}

cql_noexport void gen_to_stdout(CqlState* CS, ast_node *ast, gen_func fn) {
  gen_callbacks_lv = NULL;
  charbuf *gen_saved = CS->gen_output;
  CHARBUF_OPEN(sql_out);
  gen_set_output_buffer(CS, &sql_out);
  (*fn)(CS, ast);
  cql_output(CS, "%s", sql_out.ptr);
  CHARBUF_CLOSE(sql_out);
  CS->gen_output = gen_saved;
}

static bool_t suppress_attributes(CqlState* CS) {
  return gen_callbacks_lv && (gen_callbacks_rv->mode == gen_mode_sql || gen_callbacks_rv->mode == gen_mode_no_annotations);
}

static bool_t for_sqlite(CqlState* CS) {
  return gen_callbacks_lv && gen_callbacks_rv->mode == gen_mode_sql;
}

cql_noexport void gen_stmt_list_to_stdout(CqlState* CS, ast_node *ast) {
  gen_to_stdout(CS, ast, gen_stmt_list);
}

cql_noexport void gen_one_stmt_to_stdout(CqlState* CS, ast_node *ast) {
  gen_to_stdout(CS, ast, gen_one_stmt);
  cql_output(CS, ";\n");
}

cql_noexport void gen_misc_attrs_to_stdout(CqlState* CS, ast_node *ast) {
  gen_to_stdout(CS, ast, gen_misc_attrs);
}

cql_noexport void gen_with_callbacks(CqlState* CS, ast_node *ast, gen_func fn, gen_sql_callbacks *_callbacks) {
  gen_callbacks_lv = _callbacks;
  (*fn)(CS, ast);
  gen_callbacks_lv = NULL;
}

cql_noexport void gen_col_def_with_callbacks(CqlState* CS, ast_node *ast, gen_sql_callbacks *_callbacks) {
  gen_with_callbacks(CS, ast, gen_col_def, _callbacks);
}

cql_noexport void gen_statement_with_callbacks(CqlState* CS, ast_node *ast, gen_sql_callbacks *_callbacks) {
  // works for statements or statement lists
  if (is_ast_stmt_list(ast)) {
    CS->gen_stmt_level = -1;  // the first statement list does not indent
    gen_with_callbacks(CS, ast, gen_stmt_list, _callbacks);
  }
  else {
    CS->gen_stmt_level = 0;  // nested statement lists will indent
    gen_with_callbacks(CS, ast, gen_one_stmt, _callbacks);
  }
}

cql_noexport void gen_statement_and_attributes_with_callbacks(CqlState* CS, ast_node *ast, gen_sql_callbacks *_callbacks) {
  CS->gen_stmt_level = 0;  // nested statement lists will indent
  gen_with_callbacks(CS, ast, gen_one_stmt_and_misc_attrs, _callbacks);
}

cql_noexport void gen_set_output_buffer(CqlState* CS, struct charbuf *buffer) {
  CS->gen_output = buffer;
}

static void gen_name_ex(CqlState*CS, CSTR name, bool_t is_qid) {
  CHARBUF_OPEN(tmp);
  if (is_qid) {
    if (!for_sqlite(CS)) {
      cg_decode_qstr(CS, &tmp, name);
      gen_printf(CS, "%s", tmp.ptr);
    }
    else {
      cg_unquote_encoded_qstr(CS, &tmp, name);
      gen_printf(CS, "[%s]", tmp.ptr);
    }
  }
  else {
    gen_printf(CS, "%s", name);
  }
  CHARBUF_CLOSE(tmp);
}

static void gen_name(CqlState* CS, ast_node *ast) {
  if (is_ast_at_id(ast)) {
    gen_expr_at_id(CS, ast, "", 0, 0);
    return;
  }

  EXTRACT_STRING(name, ast);
  gen_name_ex(CS, name, is_qid(ast));
}

static void gen_sptr_name(CqlState* CS, sem_struct *sptr, uint32_t i) {
  gen_name_ex(CS, sptr->names[i], !!(sptr->semtypes[i] & SEM_TYPE_QID));
}

static void gen_constraint_name(CqlState* CS, ast_node *ast) {
  EXTRACT_NAME_AST(name_ast, ast);
  gen_printf(CS, "CONSTRAINT ");
  gen_name(CS, name_ast);
  gen_printf(CS, " ");
}

static void gen_name_list(CqlState* CS, ast_node *list) {
  Contract(is_ast_name_list(list));

  for (ast_node *item = list; item; item = item->right) {
    gen_name(CS, item->left);
    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

cql_noexport void gen_misc_attr_value_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_misc_attr_value_list(ast));
  for (ast_node *item = ast; item; item = item->right) {
    gen_misc_attr_value(CS, item->left);
    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

cql_noexport void gen_misc_attr_value(CqlState* CS, ast_node *ast) {
  if (is_ast_misc_attr_value_list(ast)) {
    gen_printf(CS, "(");
    gen_misc_attr_value_list(CS, ast);
    gen_printf(CS, ")");
  }
  else {
    gen_root_expr(CS, ast);
  }
}

static void gen_misc_attr(CqlState* CS, ast_node *ast) {
  Contract(is_ast_misc_attr(ast));

  gen_printf(CS, "@ATTRIBUTE(");
  if (is_ast_dot(ast->left)) {
    gen_name(CS, ast->left->left);
    gen_printf(CS, ":");
    gen_name(CS, ast->left->right);
  }
  else {
    gen_name(CS, ast->left);
  }
  if (ast->right) {
    gen_printf(CS, "=");
    gen_misc_attr_value(CS, ast->right);
  }
  gen_printf(CS, ")\n");
}

cql_noexport void gen_misc_attrs(CqlState* CS, ast_node *list) {
  Contract(is_ast_misc_attrs(list));

  // misc attributes don't go into the output if we are writing for Sqlite
  if (suppress_attributes(CS)) {
    return;
  }

  for (ast_node *item = list; item; item = item->right) {
    gen_misc_attr(CS, item->left);
  }
}

static void gen_type_kind(CqlState* CS, CSTR name) {
  // we don't always have an ast node for this, we make a fake one for the callback
  str_ast_node sast = {
    .type = k_ast_str,
    .value = name,
    .filename = "none"
  };

  ast_node *ast = (ast_node *)&sast;

  bool_t suppress = false;
  if (gen_callbacks_lv) {
    gen_sql_callback callback = gen_callbacks_rv->set_kind_callback;
    if (callback && ends_in_set(name)) {
      CHARBUF_OPEN(buf);
      suppress = callback(CS, ast, gen_callbacks_rv->set_kind_context, &buf);
      gen_printf(CS, "%s", buf.ptr);
      CHARBUF_CLOSE(buf);
    }
  }

  if (!suppress) {
    gen_printf(CS, "<%s>", name);
  }
}

static void gen_not_null(CqlState* CS) {
  if (for_sqlite(CS)) {
    gen_printf(CS, " NOT NULL");
  }
  else {
    gen_printf(CS, "!");
  }
}

void gen_data_type(CqlState* CS, ast_node *ast) {
  if (is_ast_create_data_type(ast)) {
    gen_printf(CS, "CREATE ");
    gen_data_type(CS, ast->left);
    return;
  }
  else if (is_ast_notnull(ast)) {
    gen_data_type(CS, ast->left);
    gen_not_null(CS);
    return;
  }
  else if (is_ast_sensitive_attr(ast)) {
    gen_data_type(CS, ast->left);
    if (!for_sqlite(CS)) {
      gen_printf(CS, " @SENSITIVE");
    }
    return;
  }
  else if (is_ast_type_int(ast)) {
    if (for_sqlite(CS)) {
      // we could use INT here but there is schema out
      // there that won't match if we do, seems risky
      // to change the canonical SQL output
      gen_printf(CS, "INTEGER");
    }
    else {
      gen_printf(CS, "INT");
    }
  } else if (is_ast_type_text(ast)) {
    gen_printf(CS, "TEXT");
  } else if (is_ast_type_blob(ast)) {
    gen_printf(CS, "BLOB");
  } else if (is_ast_type_object(ast)) {
    gen_printf(CS, "OBJECT");
  } else if (is_ast_type_long(ast)) {
    if (for_sqlite(CS)) {
      // we could use INT here but there is schema out
      // there that won't match if we do, seems risky
      // to change the canonical SQL output
      gen_printf(CS, "LONG_INT");
    }
    else {
      gen_printf(CS, "LONG");
    }
  } else if (is_ast_type_real(ast)) {
    gen_printf(CS, "REAL");
  } else if (is_ast_type_bool(ast)) {
    gen_printf(CS, "BOOL");
  } else if (is_ast_type_cursor(ast)) {
    gen_printf(CS, "CURSOR");
  } else {
    bool_t suppress = false;
    if (gen_callbacks_lv) {
      gen_sql_callback callback = gen_callbacks_rv->named_type_callback;
      if (callback) {
        CHARBUF_OPEN(buf);
        suppress = callback(CS, ast, gen_callbacks_rv->named_type_context, &buf);
        gen_printf(CS, "%s", buf.ptr);
        CHARBUF_CLOSE(buf);
        return;
      }
    }
    if (!suppress) {
      EXTRACT_NAME_AST(name_ast, ast);
      gen_name(CS, name_ast);
    }
    return;
  }

  if (!for_sqlite(CS)) {
    if (ast->left) {
      EXTRACT_STRING(name, ast->left);
      gen_type_kind(CS, name);
    }
  }
}

static void gen_indexed_column(CqlState* CS, ast_node *ast) {
  Contract(is_ast_indexed_column(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);

  gen_root_expr(CS, expr);
  if (is_ast_asc(ast->right)) {
    gen_printf(CS, " ASC");
  }
  else if (is_ast_desc(ast->right)) {
    gen_printf(CS, " DESC");
  }
}

static void gen_indexed_columns(CqlState* CS, ast_node *ast) {
  Contract(is_ast_indexed_columns(ast));
  for (ast_node *item = ast; item; item = item->right) {
    gen_indexed_column(CS, item->left);
    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_create_index_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "CREATE ");
  if (flags & INDEX_UNIQUE) {
    gen_printf(CS, "UNIQUE ");
  }
  gen_printf(CS, "INDEX ");
  gen_if_not_exists(CS, ast, !!(flags & INDEX_IFNE));
  gen_name(CS, index_name_ast);
  gen_printf(CS, " ON ");
  gen_name(CS, table_name_ast);
  gen_printf(CS, " (");
  gen_indexed_columns(CS, indexed_columns);
  gen_printf(CS, ")");
  if (opt_where) {
    gen_printf(CS, "\n");
    gen_opt_where(CS, opt_where);
  }
  gen_version_attrs(CS, attrs);
}

static void gen_unq_def(CqlState* CS, ast_node *def) {
  Contract(is_ast_unq_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);
  EXTRACT_ANY(conflict_clause, indexed_columns_conflict_clause->right);

  if (def->left) {
    gen_constraint_name(CS, def->left);
  }

  gen_printf(CS, "UNIQUE (");
  gen_indexed_columns(CS, indexed_columns);
  gen_printf(CS, ")");
  if (conflict_clause) {
    gen_conflict_clause(CS, conflict_clause);
  }
}

static void gen_check_def(CqlState* CS, ast_node *def) {
  Contract(is_ast_check_def(def));
  if (def->left) {
    gen_constraint_name(CS, def->left);
  }

  EXTRACT_ANY_NOTNULL(expr, def->right);
  gen_printf(CS, "CHECK (");
  gen_root_expr(CS, expr);
  gen_printf(CS, ")");
}

cql_noexport void gen_fk_action(CqlState* CS, int32_t action) {
  switch (action) {
    case FK_SET_NULL:
      gen_printf(CS, "SET NULL");
      break;
    case FK_SET_DEFAULT:
      gen_printf(CS, "SET DEFAULT");
      break;
    case FK_CASCADE:
      gen_printf(CS, "CASCADE");
      break;
    case FK_RESTRICT:
      gen_printf(CS, "RESTRICT");
      break;
    default:
      // this is all that's left, it better be this...
      Contract(action == FK_NO_ACTION);
      gen_printf(CS, "NO ACTION");
      break;
  }
}

static void gen_fk_flags(CqlState* CS, int32_t flags) {
  if (flags) {
    gen_printf(CS, " ");
  }

  int32_t action = (flags & FK_ON_UPDATE) >> 4;

  if (action) {
    gen_printf(CS, "ON UPDATE ");
    gen_fk_action(CS, action);
    if (flags & (FK_ON_DELETE|FK_DEFERRABLES)) {
      gen_printf(CS, " ");
    }
  }

  action = (flags & FK_ON_DELETE);
  if (action) {
    gen_printf(CS, "ON DELETE ");
    gen_fk_action(CS, action);
    if (flags & FK_DEFERRABLES) {
      gen_printf(CS, " ");
    }
  }

  if (flags & FK_DEFERRABLES) {
    Contract(flags & (FK_DEFERRABLE|FK_NOT_DEFERRABLE));
    if (flags & FK_DEFERRABLE) {
      Contract(!(flags & FK_NOT_DEFERRABLE));
      gen_printf(CS, "DEFERRABLE");
    }
    else {
      gen_printf(CS, "NOT DEFERRABLE");
    }
    if (flags & FK_INITIALLY_IMMEDIATE) {
      Contract(!(flags & FK_INITIALLY_DEFERRED));
      gen_printf(CS, " INITIALLY IMMEDIATE");
    }
    else if (flags & FK_INITIALLY_DEFERRED) {
      gen_printf(CS, " INITIALLY DEFERRED");
    }
  }
}

static void gen_fk_target_options(CqlState* CS, ast_node *ast) {
  Contract(is_ast_fk_target_options(ast));
  EXTRACT_NOTNULL(fk_target, ast->left);
  EXTRACT_OPTION(flags, ast->right);
  EXTRACT_NAME_AST(table_name_ast, fk_target->left);
  EXTRACT_NAMED_NOTNULL(ref_list, name_list, fk_target->right);

  gen_printf(CS, "REFERENCES ");
  gen_name(CS, table_name_ast);
  gen_printf(CS, " (");
  gen_name_list(CS, ref_list);
  gen_printf(CS, ")");
  gen_fk_flags(CS, flags);
}

static void gen_fk_def(CqlState* CS, ast_node *def) {
  Contract(is_ast_fk_def(def));
  EXTRACT(fk_info, def->right);
  EXTRACT_NAMED_NOTNULL(src_list, name_list, fk_info->left);
  EXTRACT_NOTNULL(fk_target_options, fk_info->right);

  if (def->left) {
    gen_constraint_name(CS, def->left);
  }

  gen_printf(CS, "FOREIGN KEY (");
  gen_name_list(CS, src_list);
  gen_printf(CS, ") ");
  gen_fk_target_options(CS, fk_target_options);
}

static void gen_conflict_clause(CqlState* CS, ast_node *ast) {
  Contract(is_ast_int(ast));
  EXTRACT_OPTION(conflict_clause_opt, ast);

  gen_printf(CS, " ON CONFLICT ");
  switch (conflict_clause_opt) {
    case ON_CONFLICT_ROLLBACK:
      gen_printf(CS, "ROLLBACK");
      break;
    case ON_CONFLICT_ABORT:
      gen_printf(CS, "ABORT");
      break;
    case ON_CONFLICT_FAIL:
      gen_printf(CS, "FAIL");
      break;
    case ON_CONFLICT_IGNORE:
      gen_printf(CS, "IGNORE");
      break;
    case ON_CONFLICT_REPLACE:
      gen_printf(CS, "REPLACE");
      break;
  }
}

static void gen_pk_def(CqlState* CS, ast_node *def) {
  Contract(is_ast_pk_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);
  EXTRACT_ANY(conflict_clause, indexed_columns_conflict_clause->right);

  if (def->left) {
    gen_constraint_name(CS, def->left);
  }

  gen_printf(CS, "PRIMARY KEY (");
  gen_indexed_columns(CS, indexed_columns);
  gen_printf(CS, ")");
  if (conflict_clause) {
    gen_conflict_clause(CS, conflict_clause);
  }
}

static void gen_version_and_proc(CqlState* CS, ast_node *ast)
{
  Contract(is_ast_version_annotation(ast));
  EXTRACT_OPTION(vers, ast->left);
  gen_printf(CS, "%d", vers);
  if (ast->right) {
    if (is_ast_dot(ast->right)) {
      EXTRACT_NOTNULL(dot, ast->right);
      EXTRACT_STRING(lhs, dot->left);
      EXTRACT_STRING(rhs, dot->right);

      gen_printf(CS, ", %s:%s", lhs, rhs);
    }
    else
    {
      EXTRACT_STRING(name, ast->right);
      gen_printf(CS, ", %s", name);
    }
  }
}

static void gen_recreate_attr(CqlState* CS, ast_node *attr) {
  Contract (is_ast_recreate_attr(attr));
  if (!suppress_attributes(CS)) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(CS, " @RECREATE");
    if (attr->left) {
      EXTRACT_STRING(group_name, attr->left);
      gen_printf(CS, "(%s)", group_name);
    }
  }
}

static void gen_create_attr(CqlState* CS, ast_node *attr) {
  Contract (is_ast_create_attr(attr));
  if (!suppress_attributes(CS)) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(CS, " @CREATE(");
    gen_version_and_proc(CS, attr->left);
    gen_printf(CS, ")");
  }
}

static void gen_delete_attr(CqlState* CS, ast_node *attr) {
  Contract (is_ast_delete_attr(attr));

  // attributes do not appear when writing out commands for Sqlite
  if (!suppress_attributes(CS)) {
    gen_printf(CS, " @DELETE");
    if (attr->left) {
      gen_printf(CS, "(");
      gen_version_and_proc(CS, attr->left);
      gen_printf(CS, ")");
    }
  }
}

static void gen_sensitive_attr(CqlState* CS, ast_node *attr) {
  Contract (is_ast_sensitive_attr(attr));
  if (!for_sqlite(CS)) {
    // attributes do not appear when writing out commands for Sqlite
    gen_printf(CS, " @SENSITIVE");
  }
}

static void gen_col_attrs(CqlState* CS, ast_node *_Nullable attrs) {
  for (ast_node *attr = attrs; attr; attr = attr->right) {
    if (is_ast_create_attr(attr)) {
      gen_create_attr(CS, attr);
    } else if (is_ast_sensitive_attr(attr)) {
      gen_sensitive_attr(CS, attr);
    } else if (is_ast_delete_attr(attr)) {
      gen_delete_attr(CS, attr);
    } else if (is_ast_col_attrs_not_null(attr)) {
      gen_not_null(CS);
      EXTRACT_ANY(conflict_clause, attr->left);
      if (conflict_clause) {
        gen_conflict_clause(CS, conflict_clause);
      }
    } else if (is_ast_col_attrs_pk(attr)) {
      EXTRACT_NOTNULL(autoinc_and_conflict_clause, attr->left);
      EXTRACT(col_attrs_autoinc, autoinc_and_conflict_clause->left);
      EXTRACT_ANY(conflict_clause, autoinc_and_conflict_clause->right);

      gen_printf(CS, " PRIMARY KEY");
      if (conflict_clause) {
        gen_conflict_clause(CS, conflict_clause);
      }
      if (col_attrs_autoinc) {
        gen_printf(CS, " AUTOINCREMENT");
      }
    } else if (is_ast_col_attrs_unique(attr)) {
      gen_printf(CS, " UNIQUE");
      if (attr->left) {
        gen_conflict_clause(CS, attr->left);
      }
    } else if (is_ast_col_attrs_hidden(attr)) {
      gen_printf(CS, " HIDDEN");
    } else if (is_ast_col_attrs_fk(attr)) {
      gen_printf(CS, " ");
      gen_fk_target_options(CS, attr->left);
    } else if (is_ast_col_attrs_check(attr)) {
      gen_printf(CS, " CHECK(");
      gen_root_expr(CS, attr->left);
      gen_printf(CS, ") ");
    } else if (is_ast_col_attrs_collate(attr)) {
      gen_printf(CS, " COLLATE ");
      gen_root_expr(CS, attr->left);
    } else {
      Contract(is_ast_col_attrs_default(attr));
      gen_printf(CS, " DEFAULT ");
      gen_root_expr(CS, attr->left);
    }
  }
}

static void gen_col_def(CqlState* CS, ast_node *def) {
  Contract(is_ast_col_def(def));
  EXTRACT_NOTNULL(col_def_type_attrs, def->left);
  EXTRACT(misc_attrs, def->right);
  EXTRACT_ANY(attrs, col_def_type_attrs->right);
  EXTRACT_NOTNULL(col_def_name_type, col_def_type_attrs->left);
  EXTRACT_NAME_AST(name_ast, col_def_name_type->left);
  EXTRACT_ANY_NOTNULL(data_type, col_def_name_type->right);

  if (misc_attrs) {
    gen_misc_attrs(CS, misc_attrs);
  }

  gen_name(CS, name_ast);
  gen_printf(CS, " ");

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // with no SEM we can't do this conversion, we're just doing vanilla echos
  gen_data_type(CS, data_type);
#else
  if (gen_callbacks_lv && gen_callbacks_rv->long_to_int_conv && def->sem && (def->sem->sem_type & SEM_TYPE_AUTOINCREMENT)) {
    // semantic checking must have already validated that this is either an integer or long_integer
    sem_t core_type = core_type_of(def->sem->sem_type);
    Contract(core_type == SEM_TYPE_INTEGER || core_type == SEM_TYPE_LONG_INTEGER);
    gen_printf(CS, "INTEGER");
  }
  else {
    gen_data_type(CS, data_type);
  }
#endif
  gen_col_attrs(CS, attrs);
}

cql_export bool_t eval_star_callback(CqlState* CS, ast_node *ast) {
  Contract(is_ast_star(ast) || is_ast_table_star(ast));
  bool_t suppress = 0;

  if (gen_callbacks_lv && gen_callbacks_rv->star_callback && ast->sem) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks_rv->star_callback(CS, ast, gen_callbacks_rv->star_context, &buf);
    gen_printf(CS, "%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }

  return suppress;
}

cql_noexport bool_t eval_column_callback(CqlState* CS, ast_node *ast) {
  Contract(is_ast_col_def(ast));
  bool_t suppress = 0;

  if (gen_callbacks_lv && gen_callbacks_rv->col_def_callback && ast->sem) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks_rv->col_def_callback(CS, ast, gen_callbacks_rv->col_def_context, &buf);
    gen_printf(CS, "%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }

  return suppress;
}

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)

// if SEM isn't in the picture there are no "variables"
bool_t eval_variables_callback(CS, ast_node *ast) {
  return false;
}

#else

bool_t eval_variables_callback(CqlState* CS, ast_node *ast) {
  bool_t suppress = 0;
  if (gen_callbacks_lv && gen_callbacks_rv->variables_callback && ast->sem && is_variable(ast->sem->sem_type)) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks_rv->variables_callback(CS, ast, gen_callbacks_rv->variables_context, &buf);
    gen_printf(CS, "%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }
  return suppress;
}
#endif

cql_noexport void gen_col_or_key(CqlState* CS, ast_node *def) {
  if (is_ast_col_def(def)) {
    gen_col_def(CS, def);
  } else if (is_ast_pk_def(def)) {
    gen_pk_def(CS, def);
  } else if (is_ast_fk_def(def)) {
    gen_fk_def(CS, def);
  } else if (is_ast_shape_def(def)) {
    gen_shape_def(CS, def);
  } else if (is_ast_check_def(def)) {
    gen_check_def(CS, def);
  } else {
    Contract(is_ast_unq_def(def));
    gen_unq_def(CS, def);
  }
}

cql_noexport void gen_col_key_list(CqlState* CS, ast_node *list) {
  Contract(is_ast_col_key_list(list));
  bool_t need_comma = 0;

  GEN_BEGIN_INDENT(coldefs, 2);

  for (ast_node *item = list; item; item = item->right) {
    EXTRACT_ANY_NOTNULL(def, item->left);

    // give the callback system a chance to suppress columns that are not in this version
    if (is_ast_col_def(def) && eval_column_callback(CS, def)) {
      continue;
    }

    if (need_comma) {
      gen_printf(CS, ",\n");
    }
    need_comma = 1;

    gen_col_or_key(CS, def);
  }
  GEN_END_INDENT(coldefs);
}

static void gen_select_opts(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_opts(ast));
  EXTRACT_ANY_NOTNULL(opt, ast->left);

  if (is_ast_all(opt)) {
    gen_printf(CS, " ALL");
  }
  else if (is_ast_distinct(opt)) {
    gen_printf(CS, " DISTINCT");
  }
  else {
    Contract(is_ast_distinctrow(opt));
    gen_printf(CS, " DISTINCTROW");
  }
}

static void gen_binary_no_spaces(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, "%s", op);
  gen_expr(CS, ast->right, pri_new + 1);
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_binary(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {

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

  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " %s ", op);
  gen_expr(CS, ast->right, pri_new + 1);
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_unary(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf(CS, "(");
  gen_printf(CS, "%s", op);
  gen_expr(CS, ast->left, pri_new);
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_postfix(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " %s", op);
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_expr_const(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  gen_printf(CS, "CONST(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, ")");
}

static void gen_uminus(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  if (pri_new < pri) gen_printf(CS, "(");
  gen_printf(CS, "%s", op);

  // we don't ever want -- in the output because that's a comment
  CHARBUF_OPEN(tmp);
  charbuf *saved = CS->gen_output;
  CS->gen_output = &tmp;
  gen_expr(CS, ast->left, pri_new);
  CS->gen_output = saved;

  if (tmp.ptr[0] == '-') {
    gen_printf(CS, " ");
  }

  gen_printf(CS, "%s", tmp.ptr);
  CHARBUF_CLOSE(tmp);

  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_concat(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_concat(ast));

  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " %s ", op);
  gen_expr(CS, ast->right, pri_new);
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_arg_expr(CqlState* CS, ast_node *ast) {
  if (is_ast_star(ast)) {
    gen_printf(CS, "*");
  }
  else if (is_ast_from_shape(ast)) {
    gen_shape_arg(CS, ast);
  }
  else {
    gen_root_expr(CS, ast);
  }
}

static void gen_expr_exists(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_exists_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);

  gen_printf(CS, "EXISTS (");
  GEN_BEGIN_INDENT(sel, 2);
    CS->pending_indent = 0;
    gen_select_stmt(CS, select_stmt);
  GEN_END_INDENT(sel);
  gen_printf(CS, ")");
}

static void gen_arg_list(CqlState* CS, ast_node *ast) {
  while (ast) {
    gen_arg_expr(CS, ast->left);
    if (ast->right) {
      gen_printf(CS, ", ");
    }
    ast = ast->right;
  }
}

static void gen_expr_list(CqlState* CS, ast_node *ast) {
  while (ast) {
    gen_root_expr(CS, ast->left);
    if (ast->right) {
      gen_printf(CS, ", ");
    }
    ast = ast->right;
  }
}

static void gen_shape_arg(CqlState* CS, ast_node *ast) {
  Contract(is_ast_from_shape(ast));
  EXTRACT_STRING(shape, ast->left);
  gen_printf(CS, "FROM %s", shape);
  if (ast->right) {
    gen_printf(CS, " ");
    gen_shape_def(CS, ast->right);
  }
}

static void gen_case_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_case_list(ast));

  while (ast) {
    EXTRACT_NOTNULL(when, ast->left);
    EXTRACT_ANY_NOTNULL(case_expr, when->left);
    EXTRACT_ANY_NOTNULL(then_expr, when->right);

    // additional parens never needed because WHEN/THEN act like parens
    gen_printf(CS, "WHEN ");
    gen_root_expr(CS, case_expr);
    gen_printf(CS, " THEN ");
    gen_root_expr(CS, then_expr);
    gen_printf(CS, "\n");

    ast = ast->right;
  }
}

static void gen_expr_table_star(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_table_star(ast));
  gen_name(CS, ast->left);
  gen_printf(CS, ".*");
}

static void gen_expr_star(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_star(ast));
  gen_printf(CS, "*");
}

static void gen_expr_num(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_num(ast));
  EXTRACT_NUM_VALUE(val, ast);
  EXTRACT_NUM_TYPE(num_type, ast);
  Contract(val);

  if (has_hex_prefix(val) && gen_callbacks_lv && gen_callbacks_rv->convert_hex) {
    int64_t v = strtol(val, NULL, 16);
    gen_printf(CS, "%lld", (llint_t)v);
  }
  else {
    if (for_sqlite(CS) || num_type != NUM_BOOL) {
      gen_printf(CS, "%s", val);
    }
    else {
      if (!strcmp(val, "0")) {
        gen_printf(CS, "FALSE");
      }
      else {
        gen_printf(CS, "TRUE");
      }
    }
  }

  if (for_sqlite(CS)) {
    return;
  }

  if (num_type == NUM_LONG) {
    gen_printf(CS, "L");
  }
}

static void gen_expr_blob(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_blob(ast));
  EXTRACT_BLOBTEXT(str, ast);

  // blob literals are easy, we just emit them, there's no conversion or anything like that
  gen_printf(CS, "%s", str);
}

static void gen_macro_args(CqlState* CS, ast_node *ast) {
  for ( ; ast; ast = ast->right) {
    EXTRACT_ANY_NOTNULL(arg, ast->left);
    if (is_ast_expr_macro_arg(arg)) {
      gen_root_expr(CS, arg->left);
    }
    else if (is_ast_query_parts_macro_arg(arg)) {
      gen_printf(CS, "FROM(");
      gen_query_parts(CS, arg->left);
      gen_printf(CS, ")");
    }
    else if (is_ast_select_core_macro_arg(arg)) {
      gen_printf(CS, "ALL(");
      gen_select_core_list(CS, arg->left);
      gen_printf(CS, ")");
    }
    else if (is_ast_select_expr_macro_arg(arg)) {
      gen_printf(CS, "SELECT(");
      gen_select_expr_list(CS, arg->left);
      gen_printf(CS, ")");
    }
    else if (is_ast_cte_tables_macro_arg(arg)) {
      gen_printf(CS, "WITH(\n");
      GEN_BEGIN_INDENT(tables, 2);
        gen_cte_tables(CS, arg->left, "");
      GEN_END_INDENT(tables);
      gen_printf(CS, ")");
    }
    else {
      Contract(is_ast_stmt_list_macro_arg(arg));
      gen_printf(CS, "\nBEGIN\n");
      gen_stmt_list(CS, arg->left);
      gen_printf(CS, "END");
    }
    if (ast->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_text_args(CqlState* CS, ast_node *ast) {
  for (; ast; ast = ast->right) {
    Contract(is_ast_text_args(ast));
    EXTRACT_ANY_NOTNULL(txt, ast->left);

    if (is_any_macro_ref(txt)) {
      EXTRACT_STRING(name, txt->left);
      gen_printf(CS, "%s(", name);
      gen_macro_args(CS, txt->right);
      gen_printf(CS, ")");
    }
    else if (is_any_macro_arg_ref(txt)) {
      EXTRACT_STRING(name, txt->left);
      gen_printf(CS, "%s", name);
    }
    else {
      gen_root_expr(CS, txt);
    }
    if (ast->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_expr_macro_text(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  gen_printf(CS, "@TEXT(");
  gen_text_args(CS, ast->left);
  gen_printf(CS, ")");
}

cql_noexport void gen_any_text_arg(CqlState* CS, ast_node *ast) {
  if (is_ast_cte_tables(ast)) {
    gen_cte_tables(CS, ast, "");
  }
  else if (is_ast_table_or_subquery_list(ast) || is_ast_join_clause(ast)) {
    gen_query_parts(CS, ast);
  }
  else if (is_ast_stmt_list(ast)) {
    gen_stmt_list(CS, ast);
  }
  else if (is_ast_select_core_list(ast)) {
    gen_select_core_list(CS, ast);
  }
  else if (is_ast_select_expr_list(ast)) {
    gen_select_expr_list(CS, ast);
  }
  else {
    gen_root_expr(CS, ast);
  }
}

// note that the final expression might end up with parens or not
// but in this form no parens are needed, the replacement will
// naturally cause parens around a lower binding macro or macro arg
// hence we ignore pri and pri new just like for say identifiers
static void gen_expr_macro_ref(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_expr_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

// note that the final expression might end up with parens or not
// but in this form no parens are needed, the replacement will
// naturally cause parens around a lower binding macro or macro arg
// hence we ignore pri and pri new just like for say identifiers
static void gen_expr_macro_arg_ref(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_expr_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

static void gen_expr_at_id(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_at_id(ast));
  gen_printf(CS, "@ID(");
  gen_text_args(CS, ast->left);
  gen_printf(CS, ")");
}

static void gen_expr_str(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_str(ast));
  EXTRACT_STRING(str, ast);

  if (is_strlit(ast)) {
    str_ast_node *asts = (str_ast_node *)ast;
    if (asts->str_type != STRING_TYPE_C || for_sqlite(CS)) {
      // Note: str is the lexeme, so it is either still quoted and escaped
      // or if it was a c string literal it was already normalized to SQL form.
      // In both cases we can just print.
      gen_literal(CS, str);
    }
    else {
      // If was originally a c string literal re-encode it for echo output
      // so that it looks the way it was given to us.  This is so that when we
      // echo the SQL back for say test output C string literal forms come out
      // just as they were given to us.
      CHARBUF_OPEN(decoded);
      CHARBUF_OPEN(encoded);
      cg_decode_string_literal(str, &decoded);
      cg_encode_c_string_literal(CS, decoded.ptr, &encoded);

      gen_literal(CS, encoded.ptr);
      CHARBUF_CLOSE(encoded);
      CHARBUF_CLOSE(decoded);
    }
  }
  else {
    if (!eval_variables_callback(CS, ast)) {
      // an identifier
      gen_name(CS, ast);
    }
  }
}

static void gen_expr_null(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_null(ast));
  gen_printf(CS, "NULL");
}

static void gen_expr_dot(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_dot(ast));

  // the general case is not variables tables etc. the notifications do not fire
  // these are rewritten away so they won't survive in the tree for later codegen
  // to use these callbacks anyway.
  if (!is_id(ast->left) || !is_id(ast->right)) {
    gen_binary_no_spaces(CS, ast, op, pri, pri_new);
    return;
  }

  EXTRACT_ANY_NOTNULL(left, ast->left);
  EXTRACT_ANY_NOTNULL(right, ast->right);

  if (eval_variables_callback(CS, ast)) {
    return;
  }

  bool_t has_table_rename_callback = gen_callbacks_lv && gen_callbacks_rv->table_rename_callback;
  bool_t handled = false;

  if (has_table_rename_callback) {
    handled = gen_callbacks_rv->table_rename_callback(CS, left, gen_callbacks_rv->table_rename_context, CS->gen_output);
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
     gen_name(CS, left);
  }
  gen_printf(CS, ".");
  gen_name(CS, right);
#else
  bool_t is_arguments = false;

  if (is_id(left)) {
    EXTRACT_STRING(lname, left);
    is_arguments = !strcmp("ARGUMENTS", lname) && ast->sem && ast->sem->name;
  }

  if (is_arguments) {
    // special case for rewritten arguments, hide the "ARGUMENTS." stuff
    gen_printf(CS, "%s", ast->sem->name);
  }
  else if (CS->sem.keep_table_name_in_aliases && get_inserted_table_alias_string_override(ast)) {
    gen_printf(CS, "%s.", get_inserted_table_alias_string_override(ast));
    gen_name(CS, right);
  }
  else {
    if (left) {
      gen_name(CS, left);
    }
    gen_printf(CS, ".");
    gen_name(CS, right);
  }
#endif
}

static void gen_expr_in_pred(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_in_pred(ast));
  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " IN (");
  if (ast->right == NULL) {
    /* nothing */
  }
  else if (is_ast_expr_list(ast->right)) {
    EXTRACT_NOTNULL(expr_list, ast->right);
    gen_expr_list(CS, expr_list);
  }
  else {
    EXTRACT_ANY_NOTNULL(select_stmt, ast->right);
    gen_select_stmt(CS, select_stmt);
  }
  gen_printf(CS, ")");

  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_expr_not_in(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_not_in(ast));
  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " NOT IN (");
  if (ast->right == NULL) {
    /* nothing */
  }
  else if (is_ast_expr_list(ast->right)) {
    EXTRACT_NOTNULL(expr_list, ast->right);
    gen_expr_list(CS, expr_list);
  }
  else {
    EXTRACT_ANY_NOTNULL(select_stmt, ast->right);
    gen_select_stmt(CS, select_stmt);
  }
  gen_printf(CS, ")");

  if (pri_new < pri) gen_printf(CS, ")");
}

// Append field name and type to the buffer.  Canonicalize column name to camel case.
// Many languages use camel case property names and we want to make it easy
// for them to bind to fields and generate hashes.  We have to pick some
// canonical thing so we canonicalize to camelCase.  It's not perfect but it seems
// like the best trade-off. Lots of languages wrap SQLite columns.
static void gen_append_field_desc(CqlState* CS, charbuf *tmp, CSTR cname, sem_t sem_type) {
  cg_sym_name(CS, cg_symbol_case_camel, tmp, "", cname, NULL); // no prefix camel
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
cql_noexport CSTR get_field_hash(CqlState* CS, CSTR name, sem_t sem_type) {
  CHARBUF_OPEN(tmp);
  gen_append_field_desc(CS, &tmp, name, sem_type);
  int64_t hash = sha256_charbuf(&tmp);
  CSTR result = dup_printf(CS, "%lld", (llint_t)hash);
  CHARBUF_CLOSE(tmp);
  return result;
}

// This is only called when doing for_sqlite output which
// presumes that semantic analysis has already happened. Its
// otherwise meaningless.  There must also be live blob mappings
// again all this would be screen out much earlier if it was otherwise.
static void gen_field_hash(CqlState* CS, ast_node *ast) {
  Contract(is_ast_dot(ast));
  Contract(CS->cg_blob_mappings);
  Contract(ast->sem);
  EXTRACT_STRING(cname, ast->right);

  CHARBUF_OPEN(tmp);
  gen_append_field_desc(CS, &tmp, cname, ast->sem->sem_type);
  int64_t hash = sha256_charbuf(&tmp);
  gen_printf(CS, "%lld", (llint_t)hash);
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
cql_noexport CSTR gen_type_hash(CqlState* CS, ast_node *ast) {
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
  cg_sym_name(CS, cg_symbol_case_pascal, &tmp, "", sptr->struct_name, NULL); // no prefix pascal

  // we need an array of the field descriptions, first we need the count of mandatory fields
  uint32_t count = (uint32_t)table_info->notnull_count;

  // there must be a pk and it is not null so count is > 0
  Invariant(count > 0);

  // make our temporary array
  CSTR *ptrs = calloc(count, sizeof(CSTR));

  // now compute the fields we need
  for (uint32_t i = 0; i < count; i++) {
    int16_t icol = table_info->notnull_cols[i];
    CSTR cname = sptr->names[icol];
    sem_t sem_type = sptr->semtypes[icol];

    CHARBUF_OPEN(field);
      gen_append_field_desc(CS, &field, cname, sem_type);
      ptrs[i] = Strdup(CS, field.ptr);
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

  return dup_printf(CS, "%lld", (llint_t)hash);
}

static void gen_cql_blob_get_type(CqlState* CS, ast_node *ast) {
  Contract(is_ast_call(ast));
  Contract(CS->cg_blob_mappings);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  CSTR func = CS->cg_blob_mappings->blob_get_key_type;

  gen_printf(CS, "%s(", func);
  gen_root_expr(CS, first_arg(arg_list));
  gen_printf(CS, ")");
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

    if (!Strcasecmp(name, sptr->names[icol])) {
      return i;
    }
  }

  return -1;
}

static void gen_cql_blob_get(CqlState* CS, ast_node *ast) {
  Contract(is_ast_call(ast));
  Contract(CS->cg_blob_mappings);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  ast_node *table_expr = second_arg(arg_list);

  EXTRACT_STRING(tname, table_expr->left);
  EXTRACT_STRING(cname, table_expr->right);

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(CS, tname);
  Invariant(table_ast);

  int32_t pk_col_offset = get_table_col_offset(table_ast, cname, CQL_SEARCH_COL_KEYS);

  CSTR func = pk_col_offset >= 0 ?
    CS->cg_blob_mappings->blob_get_key : CS->cg_blob_mappings->blob_get_val;

  bool_t offsets = pk_col_offset >= 0 ?
    CS->cg_blob_mappings->blob_get_key_use_offsets : CS->cg_blob_mappings->blob_get_val_use_offsets;

  gen_printf(CS, "%s(", func);
  gen_root_expr(CS, first_arg(arg_list));

  if (offsets) {
    int32_t offset = pk_col_offset;
    if (offset < 0) {
      // if column not part of the key then we need to index the value, not the key
      offset = get_table_col_offset(table_ast, cname, CQL_SEARCH_COL_VALUES);
      // we know it's a valid column so it's either a key or it isn't
      // since it isn't a key it must be a value
      Invariant(offset >= 0);
      Invariant(offset < table_ast->sem->table_info->value_count);
    }
    else {
      Invariant(offset < table_ast->sem->table_info->key_count);
    }
    gen_printf(CS, ", %d)", offset);
  }
  else {
    gen_printf(CS, ", ");
    gen_field_hash(CS, table_expr);
    gen_printf(CS, ")");
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
static const int32_t sem_type_to_blob_type[] = {
   -1, // NULL
  CQL_BLOB_TYPE_BOOL,
  CQL_BLOB_TYPE_INT32,
  CQL_BLOB_TYPE_INT64,
  CQL_BLOB_TYPE_FLOAT,
  CQL_BLOB_TYPE_STRING,
  CQL_BLOB_TYPE_BLOB,
  CQL_BLOB_TYPE_ENTITY
};

static void gen_cql_blob_create(CqlState* CS, ast_node *ast) {
  Contract(is_ast_call(ast));
  Contract(CS->cg_blob_mappings);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  ast_node *table_name_ast = first_arg(arg_list);

  EXTRACT_STRING(t_name, table_name_ast);

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

  CSTR func = is_pk ?
      CS->cg_blob_mappings->blob_create_key :
      CS->cg_blob_mappings->blob_create_val;

  bool_t use_offsets = is_pk ?
      CS->cg_blob_mappings->blob_create_key_use_offsets :
      CS->cg_blob_mappings->blob_create_val_use_offsets;

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(CS, t_name);
  Invariant(table_ast);

  gen_printf(CS, "%s(%s", func, gen_type_hash(CS, table_ast));

  // 2n+1 args already confirmed, safe to do this
  for (ast_node *args = arg_list->right; args; args = args->right->right) {
     ast_node *val = first_arg(args);
     ast_node *col = second_arg(args);
     if (use_offsets) {
       // when creating a key blob all columns are present in order, so no need to
       // emit the offsets, they are assumed.  However, value blobs can have
       // some or all of the values and might skip some
       if (!is_pk) {
         EXTRACT_STRING(cname, col->right);
         int32_t offset = get_table_col_offset(table_ast, cname, CQL_SEARCH_COL_VALUES);
         gen_printf(CS, ", %d", offset);
       }
     }
     else {
       gen_printf(CS, ", ");
       gen_field_hash(CS, col);
     }

     gen_printf(CS, ", ");
     gen_root_expr(CS, val);

     gen_printf(CS, ", %d", sem_type_to_blob_type[core_type_of(col->sem->sem_type)]);
  }

  gen_printf(CS, ")");
}

static void gen_cql_blob_update(CqlState* CS, ast_node *ast) {
  Contract(is_ast_call(ast));
  Contract(CS->cg_blob_mappings);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT(arg_list, call_arg_list->right);

  // known to be dot operator and known to have a table
  EXTRACT_NOTNULL(dot, third_arg(arg_list));
  EXTRACT_STRING(t_name, dot->left);

  sem_t sem_type_dot = dot->sem->sem_type;
  bool_t is_pk = is_primary_key(sem_type_dot) || is_partial_pk(sem_type_dot);

  CSTR func = is_pk ?
      CS->cg_blob_mappings->blob_update_key :
      CS->cg_blob_mappings->blob_update_val;

  bool_t use_offsets = is_pk ?
      CS->cg_blob_mappings->blob_update_key_use_offsets :
      CS->cg_blob_mappings->blob_update_val_use_offsets;

  // table known to exist (and not deleted) already
  ast_node *table_ast = find_table_or_view_even_deleted(CS, t_name);
  Invariant(table_ast);

  gen_printf(CS, "%s(", func);
  gen_root_expr(CS, first_arg(arg_list));

  // 2n+1 args already confirmed, safe to do this
  for (ast_node *args = arg_list->right; args; args = args->right->right) {
     ast_node *val = first_arg(args);
     ast_node *col = second_arg(args);
     EXTRACT_STRING(cname, col->right);
     if (use_offsets) {
      // we know it's a valid column
      int32_t offset = get_table_col_offset(table_ast, cname,
         is_pk ? CQL_SEARCH_COL_KEYS : CQL_SEARCH_COL_VALUES);
      Invariant(offset >= 0);
      gen_printf(CS, ", %d", offset);
     }
     else {
       gen_printf(CS, ", ");
       gen_field_hash(CS, col);
     }
     gen_printf(CS, ", ");
     gen_root_expr(CS, val);
     if (!is_pk) {
       // you never need the item types for the key blob becasue it always has all the fields
       gen_printf(CS, ", %d", sem_type_to_blob_type[core_type_of(col->sem->sem_type)]);
     }
  }

  gen_printf(CS, ")");
}

static void gen_array(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_array(ast));
  EXTRACT_ANY_NOTNULL(array, ast->left);
  EXTRACT_NOTNULL(arg_list, ast->right);

  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, array, pri_new);
  if (pri_new < pri) gen_printf(CS, ")");
  gen_printf(CS, "[");
  gen_arg_list(CS, arg_list);
  gen_printf(CS, "]");
}

static void gen_expr_call(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_call(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_STRING(name, name_ast);
  EXTRACT_NOTNULL(call_arg_list, ast->right);
  EXTRACT_NOTNULL(call_filter_clause, call_arg_list->left);
  EXTRACT(distinct, call_filter_clause->left);
  EXTRACT(opt_filter_clause, call_filter_clause->right);
  EXTRACT(arg_list, call_arg_list->right);

  // We never want this to appear. Calls to `cql_inferred_notnull` exist only as
  // the product of a rewrite rule and should not be visible to users.
  if (!Strcasecmp("cql_inferred_notnull", name)) {
    gen_arg_list(CS, arg_list);
    return;
  }

  if (for_sqlite(CS) && CS->cg_blob_mappings) {
    if (!Strcasecmp("cql_blob_get", name)) {
      gen_cql_blob_get(CS, ast);
      return;
    }
    else if (!Strcasecmp("cql_blob_get_type", name)) {
      gen_cql_blob_get_type(CS, ast);
      return;
    }
    else if (!Strcasecmp("cql_blob_create", name)) {
      gen_cql_blob_create(CS, ast);
      return;
    }
    else if (!Strcasecmp("cql_blob_update", name)) {
      gen_cql_blob_update(CS, ast);
      return;
    }
  }

  if (for_sqlite(CS)) {
    // These functions are all no-ops in SQL and must not be emitted if we're
    // doing codegen: They're only present within queries in source programs for
    // the purpose of manipulating types.

    if (!Strcasecmp("nullable", name)) {
      gen_arg_list(CS, arg_list);
      return;
    }

    if (!Strcasecmp("ptr", name)) {
      gen_arg_list(CS, arg_list);
      return;
    }

    if (!Strcasecmp("sensitive", name)) {
      gen_arg_list(CS, arg_list);
      return;
    }
  }

  bool_t has_func_callback = gen_callbacks_lv && gen_callbacks_rv->func_callback;

  if (has_func_callback) {
    bool_t handled = gen_callbacks_rv->func_callback(CS, ast, gen_callbacks_rv->func_context, CS->gen_output);

    if (handled) {
      return;
    }
  }

  gen_printf(CS, "%s(", name);
  if (distinct) {
    gen_printf(CS, "DISTINCT ");
  }
  gen_arg_list(CS, arg_list);
  gen_printf(CS, ")");

  if (opt_filter_clause) {
    gen_opt_filter_clause(CS, opt_filter_clause);
  }
}

static void gen_opt_filter_clause(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_filter_clause(ast));
  EXTRACT_NOTNULL(opt_where, ast->left);

  gen_printf(CS, " FILTER (");
  gen_opt_where(CS, opt_where);
  gen_printf(CS, ")");
}

static void gen_opt_partition_by(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_partition_by(ast));
  EXTRACT_NOTNULL(expr_list, ast->left);

  gen_printf(CS, "PARTITION BY ");
  gen_expr_list(CS, expr_list);
}

static void gen_frame_spec_flags(CqlState* CS, int32_t flags) {
  if (flags & FRAME_TYPE_RANGE) {
    gen_printf(CS, "RANGE");
  }
  if (flags & FRAME_TYPE_ROWS) {
    gen_printf(CS, "ROWS");
  }
  if (flags & FRAME_TYPE_GROUPS) {
    gen_printf(CS, "GROUPS");
  }
  if (flags & FRAME_BOUNDARY_UNBOUNDED || flags & FRAME_BOUNDARY_START_UNBOUNDED) {
    gen_printf(CS, "UNBOUNDED PRECEDING");
  }
  if (flags & FRAME_BOUNDARY_PRECEDING ||
      flags & FRAME_BOUNDARY_START_PRECEDING ||
      flags & FRAME_BOUNDARY_END_PRECEDING) {
    gen_printf(CS, "PRECEDING");
  }
  if (flags & FRAME_BOUNDARY_CURRENT_ROW ||
      flags & FRAME_BOUNDARY_START_CURRENT_ROW ||
      flags & FRAME_BOUNDARY_END_CURRENT_ROW) {
    gen_printf(CS, "CURRENT ROW");
  }
  if (flags & FRAME_BOUNDARY_START_FOLLOWING ||
      flags & FRAME_BOUNDARY_END_FOLLOWING) {
    gen_printf(CS, "FOLLOWING");
  }
  if (flags & FRAME_BOUNDARY_END_UNBOUNDED) {
    gen_printf(CS, "UNBOUNDED FOLLOWING");
  }
  if (flags & FRAME_EXCLUDE_NO_OTHERS) {
    gen_printf(CS, "EXCLUDE NO OTHERS");
  }
  if (flags & FRAME_EXCLUDE_CURRENT_ROW) {
    gen_printf(CS, "EXCLUDE CURRENT ROW");
  }
  if (flags & FRAME_EXCLUDE_GROUP) {
    gen_printf(CS, "EXCLUDE GROUP");
  }
  if (flags & FRAME_EXCLUDE_TIES) {
    gen_printf(CS, "EXCLUDE TIES");
  }
}

static void gen_frame_type(CqlState* CS, int32_t flags) {
  Invariant(flags == (flags & FRAME_TYPE_FLAGS));
  gen_frame_spec_flags(CS, flags);
  gen_printf(CS, " ");
}

static void gen_frame_exclude(CqlState* CS, int32_t flags) {
  Invariant(flags == (flags & FRAME_EXCLUDE_FLAGS));
  if (flags != FRAME_EXCLUDE_NONE) {
    gen_printf(CS, " ");
  }
  gen_frame_spec_flags(CS, flags);
}

static void gen_frame_boundary(CqlState* CS, ast_node *ast, int32_t flags) {
  EXTRACT_ANY(expr, ast->left);
  Invariant(flags == (flags & FRAME_BOUNDARY_FLAGS));

  if (expr) {
    gen_root_expr(CS, expr);
    gen_printf(CS, " ");
  }
  gen_frame_spec_flags(CS, flags);
}

static void gen_frame_boundary_start(CqlState* CS, ast_node *ast, int32_t flags) {
  Contract(is_ast_expr_list(ast));
  EXTRACT_ANY(expr, ast->left);
  Invariant(flags == (flags & FRAME_BOUNDARY_START_FLAGS));

  gen_printf(CS, "BETWEEN ");
  if (expr) {
    gen_root_expr(CS, expr);
    gen_printf(CS, " ");
  }
  gen_frame_spec_flags(CS, flags);
}

static void gen_frame_boundary_end(CqlState* CS, ast_node *ast, int32_t flags) {
  Contract(is_ast_expr_list(ast));
  EXTRACT_ANY(expr, ast->right);
  Invariant(flags == (flags & FRAME_BOUNDARY_END_FLAGS));

  gen_printf(CS, " AND ");
  if (expr) {
    gen_root_expr(CS, expr);
    gen_printf(CS, " ");
  }
  gen_frame_spec_flags(CS, flags);
}

static void gen_opt_frame_spec(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_frame_spec(ast));
  EXTRACT_OPTION(flags, ast->left);
  EXTRACT_NOTNULL(expr_list, ast->right);

  int32_t frame_type_flags = flags & FRAME_TYPE_FLAGS;
  int32_t frame_boundary_flags = flags & FRAME_BOUNDARY_FLAGS;
  int32_t frame_boundary_start_flags = flags & FRAME_BOUNDARY_START_FLAGS;
  int32_t frame_boundary_end_flags = flags & FRAME_BOUNDARY_END_FLAGS;
  int32_t frame_exclude_flags = flags & FRAME_EXCLUDE_FLAGS;

  if (frame_type_flags) {
    gen_frame_type(CS, frame_type_flags);
  }
  if (frame_boundary_flags) {
    gen_frame_boundary(CS, expr_list, frame_boundary_flags);
  }
  if (frame_boundary_start_flags) {
    gen_frame_boundary_start(CS, expr_list, frame_boundary_start_flags);
  }
  if (frame_boundary_end_flags) {
    gen_frame_boundary_end(CS, expr_list, frame_boundary_end_flags);
  }
  if (frame_exclude_flags) {
    gen_frame_exclude(CS, frame_exclude_flags);
  }
}

static void gen_window_defn(CqlState* CS, ast_node *ast) {
  Contract(is_ast_window_defn(ast));
  EXTRACT(opt_partition_by, ast->left);
  EXTRACT_NOTNULL(window_defn_orderby, ast->right);
  EXTRACT(opt_orderby, window_defn_orderby->left);
  EXTRACT(opt_frame_spec, window_defn_orderby->right);

  // the first optional element never needs a space
  bool need_space = 0;

  gen_printf(CS, " (");
  if (opt_partition_by) {
    Invariant(!need_space);
    gen_opt_partition_by(CS, opt_partition_by);
    need_space = 1;
  }

  if (opt_orderby) {
    if (need_space) gen_printf(CS, " ");
    gen_opt_orderby(CS, opt_orderby);
    need_space = 1;
  }

  if (opt_frame_spec) {
    if (need_space) gen_printf(CS, " ");
    gen_opt_frame_spec(CS, opt_frame_spec);
  }
  gen_printf(CS, ")");
}

static void gen_name_or_window_defn(CqlState* CS, ast_node *ast) {
  if (is_ast_str(ast)) {
    EXTRACT_STRING(window_name, ast);
    gen_printf(CS, " %s", window_name);
  }
  else {
    Contract(is_ast_window_defn(ast));
    gen_window_defn(CS, ast);
  }
}

static void gen_expr_window_func_inv(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_window_func_inv(ast));
  EXTRACT_NOTNULL(call, ast->left);
  EXTRACT_ANY_NOTNULL(name_or_window_defn, ast->right);

  gen_printf(CS, "\n  ");
  gen_expr_call(CS, call, op, pri, pri_new);
  gen_printf(CS, " OVER");
  gen_name_or_window_defn(CS, name_or_window_defn);
}

static void gen_expr_raise(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_raise(ast));
  EXTRACT_OPTION(flags, ast->left);
  EXTRACT_ANY(expr, ast->right);

  Contract(flags >= RAISE_IGNORE && flags <= RAISE_FAIL);

  gen_printf(CS, "RAISE(");
  switch (flags) {
    case RAISE_IGNORE: gen_printf(CS, "IGNORE"); break;
    case RAISE_ROLLBACK: gen_printf(CS, "ROLLBACK"); break;
    case RAISE_ABORT: gen_printf(CS, "ABORT"); break;
    case RAISE_FAIL: gen_printf(CS, "FAIL"); break;
  }
  if (expr) {
    gen_printf(CS, ", ");
    gen_root_expr(CS, expr);
  }
  gen_printf(CS, ")");
}

static void gen_expr_between(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_between(ast));
  EXTRACT_NOTNULL(range, ast->right);

  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " BETWEEN ");
  gen_expr(CS, range->left, pri_new);
  gen_printf(CS, " AND ");
  gen_expr(CS, range->right, pri_new + 1); // the usual rules for the right operand (see gen_binary)
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_expr_not_between(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_not_between(ast));
  EXTRACT_NOTNULL(range, ast->right);

  if (pri_new < pri) gen_printf(CS, "(");
  gen_expr(CS, ast->left, pri_new);
  gen_printf(CS, " NOT BETWEEN ");
  gen_expr(CS, range->left, pri_new);
  gen_printf(CS, " AND ");
  gen_expr(CS, range->right, pri_new + 1); // the usual rules for the right operand (see gen_binary)
  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_expr_between_rewrite(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_between_rewrite(ast));
  EXTRACT_NOTNULL(range, ast->right);

  // even though we did a rewrwite on the AST to make codegen easier we want to
  // echo this back the way it was originally written.  This is important to allow
  // the echoed codegen to reparse in tests -- this isn't a case of sugar, we've
  // added a codegen temporary into the AST and it really doesn't belong in the output

  if (pri_new < pri) gen_printf(CS, "(");

  gen_expr(CS, ast->left, pri_new);
  if (is_ast_or(range->right)) {
    gen_printf(CS, " NOT BETWEEN ");
  }
  else {
    gen_printf(CS, " BETWEEN ");
  }
  gen_expr(CS, range->right->left->right, pri_new);
  gen_printf(CS, " AND ");
  gen_expr(CS, range->right->right->right, pri_new);

  if (pri_new < pri) gen_printf(CS, ")");
}

static void gen_expr_case(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_case_expr(ast));
  EXTRACT_ANY(expr, ast->left);
  EXTRACT_NOTNULL(connector, ast->right);
  EXTRACT_NOTNULL(case_list, connector->left);
  EXTRACT_ANY(else_expr, connector->right);

  // case is like parens already, you never need more parens
  gen_printf(CS, "CASE");
  if (expr) {
    gen_printf(CS, " ");
    // case can have expression or just when clauses
    gen_root_expr(CS, expr);
  }
  gen_printf(CS, "\n");
  GEN_BEGIN_INDENT(case_list, 2);
  gen_case_list(CS, case_list);
  if (else_expr) {
    gen_printf(CS, "ELSE ");
    gen_root_expr(CS, else_expr);
    gen_printf(CS, "\n");
  }
  GEN_END_INDENT(case_list);
  gen_printf(CS, "END");
}

static void gen_expr_select(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_select_stmt(ast));
  gen_printf(CS, "( ");
  gen_select_stmt(CS, ast);
  gen_printf(CS, " )");
}

static void gen_expr_select_if_nothing_throw(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_select_if_nothing_throw_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);
  gen_printf(CS, "( ");
  gen_select_stmt(CS, select_stmt);
  gen_printf(CS, " IF NOTHING THROW )");
}

static void gen_expr_select_if_nothing(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_select_if_nothing_expr(ast) || is_ast_select_if_nothing_or_null_expr(ast));
  EXTRACT_ANY_NOTNULL(select_stmt, ast->left);
  EXTRACT_ANY_NOTNULL(else_expr, ast->right);

  gen_printf(CS, "( ");
  gen_select_stmt(CS, select_stmt);
  gen_printf(CS, " %s ", op);
  gen_root_expr(CS, else_expr);
  gen_printf(CS, " )");
}

static void gen_expr_type_check(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_type_check_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(type, ast->right);

  // In SQLite context we only emit the actual expression since type checking already happened during
  // semantic analysis step. Here we're emitting the final sql statement that goes to sqlite
  if (for_sqlite(CS)) {
    gen_expr(CS, expr, EXPR_PRI_ROOT);
  }
  else {
    // note that this will be rewritten to nothing during semantic analysis, it only exists
    // to force an manual compile time type check (useful in macros and such)
    gen_printf(CS, "TYPE_CHECK(");
    gen_expr(CS, expr, EXPR_PRI_ROOT);
    gen_printf(CS, " AS ");
    gen_data_type(CS, type);
    gen_printf(CS, ")");
  }
}

static void gen_expr_cast(CqlState* CS, ast_node *ast, CSTR op, int32_t pri, int32_t pri_new) {
  Contract(is_ast_cast_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  if (gen_callbacks_lv && gen_callbacks_rv->minify_casts) {
    if (is_ast_null(expr)) {
      // when generating the actual SQL for Sqlite, we don't need to include cast expressions on NULL
      // we only need those for type checking.
      gen_printf(CS, "NULL");
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
        gen_printf(CS, "(");
        gen_expr(CS, expr, EXPR_PRI_ROOT);
        gen_printf(CS, ")");
        return;
      }
    }
#endif
  }

  gen_printf(CS, "CAST(");
  gen_expr(CS, expr, EXPR_PRI_ROOT);
  gen_printf(CS, " AS ");
  gen_data_type(CS, data_type);
  gen_printf(CS, ")");
}

static void gen_expr(CqlState* CS, ast_node *ast, int32_t pri) {
  // These are all the expressions there are, we have to find it in this table
  // or else someone added a new expression type and it isn't supported yet.
  symtab_entry *entry = symtab_find(CS->gen_exprs, ast->type);
  Invariant(entry);
  gen_expr_dispatch *disp = (gen_expr_dispatch*)entry->val;
  disp->func(CS, ast, disp->str, pri, disp->pri_new);
}

cql_noexport void gen_root_expr(CqlState* CS, ast_node *ast) {
  gen_expr(CS, ast, EXPR_PRI_ROOT);
}

static void gen_as_alias(CqlState* CS, ast_node *ast) {
  EXTRACT_NAME_AST(name_ast, ast->left);

  gen_printf(CS, " AS ");
  gen_name(CS, name_ast);
}

static void gen_as_alias_with_override(CqlState* CS, ast_node *ast) {
  Contract(CS->sem.keep_table_name_in_aliases);

  CSTR name = get_inserted_table_alias_string_override(ast);
  Invariant(name);

  gen_printf(CS, " AS %s", name);
}

static void gen_select_expr(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_expr(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT(opt_as_alias, ast->right);

  gen_root_expr(CS, expr);

  if (opt_as_alias) {
    EXTRACT_STRING(name, opt_as_alias->left);

    if (CS->used_alias_syms && !symtab_find(CS->used_alias_syms, name)) {
      return;
    }

    gen_as_alias(CS, opt_as_alias);
  }
}

static void gen_col_calc(CqlState* CS, ast_node *ast) {
  Contract(is_ast_col_calc(ast));
  if (ast->left) {
    EXTRACT_NAME_AND_SCOPE(ast->left);
    if (scope) {
      gen_printf(CS, "%s.%s", scope, name);
    } else {
      gen_printf(CS, "%s", name);
    }
    if (ast->right) {
      gen_printf(CS, " ");
    }
  }

  if (ast->right) {
    gen_shape_def(CS, ast->right);
  }
}

static void gen_col_calcs(CqlState* CS, ast_node *ast) {
  Contract(is_ast_col_calcs(ast));
  ast_node *item = ast;
  while (item) {
    gen_col_calc(CS, item->left);
    if (item->right) {
      gen_printf(CS, ", ");
    }
    item = item->right;
  }
}

static void gen_column_calculation(CqlState* CS, ast_node *ast) {
  Contract(is_ast_column_calculation(ast));
  gen_printf(CS, "@COLUMNS(");
  if (ast->right) {
    gen_printf(CS, "DISTINCT ");
  }
  gen_col_calcs(CS, ast->left);
  gen_printf(CS, ")");
}

static void gen_select_expr_list(CqlState* CS, ast_node *ast) {
  symtab *temp = CS->used_alias_syms;
  CS->used_alias_syms = NULL;

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // if there is no SEM then we can't do this minificiation
#else
  if (ast->sem && gen_callbacks_lv && gen_callbacks_rv->minify_aliases) {
    CS->used_alias_syms = ast->sem->used_symbols;
  }
#endif
  int32_t count = 0;
  for (ast_node *item = ast; item && count < 4; item = item->right) {
     count++;
  }
  int32_t indent = count == 4 ? 4 : 0;

  if (indent) {
    gen_printf(CS, "\n");
  }

  int32_t pending_indent_saved = CS->pending_indent;
  GEN_BEGIN_INDENT(sel_list, indent);

  if (!indent) { CS->pending_indent = pending_indent_saved; }

  for (ast_node *item = ast; item; item = item->right) {
    ast_node *expr = item->left;

    if (is_ast_select_expr_macro_ref(expr)) {
      gen_select_expr_macro_ref(CS, expr);
    }
    else if (is_ast_select_expr_macro_arg_ref(expr)) {
      gen_select_expr_macro_arg_ref(CS, expr);
    }
    else if (is_ast_star(expr)) {
      if (!eval_star_callback(CS, expr)) {
        gen_printf(CS, "*");
      }
    }
    else if (is_ast_table_star(expr)) {
      if (!eval_star_callback(CS, expr)) {
        EXTRACT_NOTNULL(table_star, expr);
        gen_name(CS, table_star->left);
        gen_printf(CS, ".*");
      }
    }
    else if (is_ast_column_calculation(expr)) {
      gen_column_calculation(CS, expr);
    }
    else {
      EXTRACT_NOTNULL(select_expr, expr);
      gen_select_expr(CS, select_expr);
    }
    if (item->right) {
      if (indent) {
         gen_printf(CS, ",\n");
      }
      else {
         gen_printf(CS, ", ");
      }
    }
  }
  GEN_END_INDENT(sel_list);
  CS->used_alias_syms = temp;
}

static void gen_table_or_subquery(CqlState* CS, ast_node *ast) {
  Contract(is_ast_table_or_subquery(ast));

  EXTRACT_ANY_NOTNULL(factor, ast->left);

  if (is_ast_str(factor)) {
    EXTRACT_STRING(name, factor);

    bool_t has_table_rename_callback = gen_callbacks_lv && gen_callbacks_rv->table_rename_callback;
    bool_t handled = false;

    if (has_table_rename_callback) {
      handled = gen_callbacks_rv->table_rename_callback(CS, factor, gen_callbacks_rv->table_rename_context, CS->gen_output);
    }

    if (!handled) {
      gen_name(CS, factor);
    }
  }
  else if (is_ast_select_stmt(factor) || is_ast_with_select_stmt(factor)) {
    gen_printf(CS, "(");
    GEN_BEGIN_INDENT(sel, 2);
    CS->pending_indent = 0;
    gen_select_stmt(CS, factor);
    GEN_END_INDENT(sel);
    gen_printf(CS, ")");
  }
  else if (is_ast_shared_cte(factor)) {
    gen_printf(CS, "(");
    gen_shared_cte(CS, factor);
    gen_printf(CS, ")");
  }
  else if (is_ast_table_function(factor)) {
    bool_t has_table_function_callback = gen_callbacks_lv && gen_callbacks_rv->table_function_callback;
    bool_t handled_table_function = false;
    if (has_table_function_callback) {
      handled_table_function = gen_callbacks_rv->table_function_callback(CS, factor, gen_callbacks_rv->table_function_context, CS->gen_output);
    }

    if (!handled_table_function) {
      EXTRACT_STRING(name, factor->left);
      EXTRACT(arg_list, factor->right);
      gen_printf(CS, "%s(", name);
      gen_arg_list(CS, arg_list);
      gen_printf(CS, ")");
    }
  }
  else {
    // this is all that's left
    if (is_ast_query_parts_macro_ref(factor) || is_ast_query_parts_macro_arg_ref(factor)) {
      gen_query_parts(CS, factor);
    }
    else {
      gen_printf(CS, "(\n");
      GEN_BEGIN_INDENT(qp, 2);
      gen_query_parts(CS, factor);
      GEN_END_INDENT(qp);
      gen_printf(CS, ")");
    }
  }

  EXTRACT(opt_as_alias, ast->right);
  if (opt_as_alias) {
    if (get_inserted_table_alias_string_override(opt_as_alias)) {
      gen_as_alias_with_override(CS, opt_as_alias);
    } else {
      gen_as_alias(CS, opt_as_alias);
    }
  }
}

static void gen_join_cond(CqlState* CS, ast_node *ast) {
  Contract(is_ast_join_cond(ast));
  EXTRACT_ANY_NOTNULL(cond_type, ast->left);

  if (is_ast_on(cond_type)) {
    gen_printf(CS, " ON ");
    gen_root_expr(CS, ast->right);
  }
  else {
    // only other ast type that is allowed
    Contract(is_ast_using(cond_type));
    gen_printf(CS, " USING (");
    gen_name_list(CS, ast->right);
    gen_printf(CS, ")");
  }
}

static void gen_join_target(CqlState* CS, ast_node *ast) {
  Contract(is_ast_join_target(ast));
  EXTRACT_OPTION(join_type, ast->left);

  switch (join_type) {
    case JOIN_INNER: gen_printf(CS, "\nINNER JOIN "); break;
    case JOIN_CROSS: gen_printf(CS, "\nCROSS JOIN "); break;
    case JOIN_LEFT_OUTER: gen_printf(CS, "\nLEFT OUTER JOIN "); break;
    case JOIN_RIGHT_OUTER: gen_printf(CS, "\nRIGHT OUTER JOIN "); break;
    case JOIN_LEFT: gen_printf(CS, "\nLEFT JOIN "); break;
    case JOIN_RIGHT: gen_printf(CS, "\nRIGHT JOIN "); break;
  }

  EXTRACT_NOTNULL(table_join, ast->right);
  EXTRACT_NOTNULL(table_or_subquery, table_join->left);
  gen_table_or_subquery(CS, table_or_subquery);

  EXTRACT(join_cond, table_join->right);
  if (join_cond) {
    gen_join_cond(CS, join_cond);
  }
}

static void gen_join_target_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_join_target_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT(join_target, item->left);
    gen_join_target(CS, join_target);
  }
}

static void gen_join_clause(CqlState* CS, ast_node *ast) {
  Contract(is_ast_join_clause(ast));
  EXTRACT_NOTNULL(table_or_subquery, ast->left);
  EXTRACT_NOTNULL(join_target_list, ast->right);

  gen_table_or_subquery(CS, table_or_subquery);
  gen_join_target_list(CS, join_target_list);
}

static void gen_table_or_subquery_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_table_or_subquery_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    gen_table_or_subquery(CS, item->left);
    if (item->right) {
      gen_printf(CS, ",\n");
    }
  }
}

static void gen_select_core_macro_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_core_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

static void gen_select_core_macro_arg_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_core_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

static void gen_select_expr_macro_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_expr_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

static void gen_select_expr_macro_arg_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_expr_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

static void gen_cte_tables_macro_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_cte_tables_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

static void gen_cte_tables_macro_arg_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_cte_tables_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

static void gen_query_parts_macro_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_query_parts_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

static void gen_query_parts_macro_arg_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_query_parts_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

static void gen_query_parts(CqlState* CS, ast_node *ast) {
  if (is_ast_table_or_subquery_list(ast)) {
    gen_table_or_subquery_list(CS, ast);
  }
  else if (is_ast_query_parts_macro_ref(ast)) {
    gen_query_parts_macro_ref(CS, ast);
  }
  else if (is_ast_query_parts_macro_arg_ref(ast)) {
    gen_query_parts_macro_arg_ref(CS, ast);
  }
  else {
    Contract(is_ast_join_clause(ast)); // this is the only other choice
    gen_join_clause(CS, ast);
  }
}

static void gen_asc_desc(CqlState* CS, ast_node *ast) {
  if (is_ast_asc(ast)) {
    gen_printf(CS, " ASC");
    if (ast->left && is_ast_nullslast(ast->left)) {
      gen_printf(CS, " NULLS LAST");
    }
  }
  else if (is_ast_desc(ast)) {
    gen_printf(CS, " DESC");
    if (ast->left && is_ast_nullsfirst(ast->left)) {
      gen_printf(CS, " NULLS FIRST");
    }
  }
  else {
    Contract(!ast);
  }
}

static void gen_groupby_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_groupby_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_groupby_list(item));
    EXTRACT_NOTNULL(groupby_item, item->left);
    EXTRACT_ANY_NOTNULL(expr, groupby_item->left);

    gen_root_expr(CS, expr);

    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_orderby_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_orderby_list(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_orderby_list(item));
    EXTRACT_NOTNULL(orderby_item, item->left);
    EXTRACT_ANY_NOTNULL(expr, orderby_item->left);
    EXTRACT_ANY(opt_asc_desc, orderby_item->right);

    gen_root_expr(CS, expr);
    gen_asc_desc(CS, opt_asc_desc);

    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_opt_where(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_where(ast));

  gen_printf(CS, "WHERE ");
  gen_root_expr(CS, ast->left);
}

static void gen_opt_groupby(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_groupby(ast));
  EXTRACT_NOTNULL(groupby_list, ast->left);

  gen_printf(CS, "\n  GROUP BY ");
  gen_groupby_list(CS, groupby_list);
}

static void gen_opt_orderby(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_orderby(ast));
  EXTRACT_NOTNULL(orderby_list, ast->left);

  gen_printf(CS, "ORDER BY ");
  gen_orderby_list(CS, orderby_list);
}

static void gen_opt_limit(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_limit(ast));

  gen_printf(CS, "\n  LIMIT ");
  gen_root_expr(CS, ast->left);
}

static void gen_opt_offset(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_offset(ast));

  gen_printf(CS, "\n  OFFSET ");
  gen_root_expr(CS, ast->left);
}

static void gen_window_name_defn(CqlState* CS, ast_node *ast) {
  Contract(is_ast_window_name_defn(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(window_defn, ast->right);

  gen_printf(CS, "\n    %s AS", name);
  gen_window_defn(CS, window_defn);
}

static void gen_window_name_defn_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_window_name_defn_list(ast));
  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT_NOTNULL(window_name_defn, item->left);
    gen_window_name_defn(CS, window_name_defn);
    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_window_clause(CqlState* CS, ast_node *ast) {
  Contract(is_ast_window_clause(ast));
  EXTRACT_NOTNULL(window_name_defn_list, ast->left);

  gen_window_name_defn_list(CS, window_name_defn_list);
}

static void gen_opt_select_window(CqlState* CS, ast_node *ast) {
  Contract(is_ast_opt_select_window(ast));
  EXTRACT_NOTNULL(window_clause, ast->left);

  gen_printf(CS, "\n  WINDOW ");
  gen_window_clause(CS, window_clause);
}

static void gen_select_from_etc(CqlState* CS, ast_node *ast) {
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
    gen_printf(CS, "\n  FROM ");
    GEN_BEGIN_INDENT(from, 4);
      CS->pending_indent = 0;
      gen_query_parts(CS, query_parts);
    GEN_END_INDENT(from);
  }
  if (opt_where) {
    gen_printf(CS, "\n  ");
    gen_opt_where(CS, opt_where);
  }
  if (opt_groupby) {
    gen_opt_groupby(CS, opt_groupby);
  }
  if (opt_having) {
    gen_printf(CS, "\n  HAVING ");
    gen_root_expr(CS, opt_having->left);
  }
  if (opt_select_window) {
    gen_opt_select_window(CS, opt_select_window);
  }
}

static void gen_select_orderby(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_orderby(ast));
  EXTRACT(opt_orderby, ast->left);
  EXTRACT_NOTNULL(select_limit, ast->right);
  EXTRACT(opt_limit, select_limit->left);
  EXTRACT_NOTNULL(select_offset, select_limit->right);
  EXTRACT(opt_offset, select_offset->left);

  if (opt_orderby) {
    gen_printf(CS, "\n  ");
    gen_opt_orderby(CS, opt_orderby);
  }
  if (opt_limit) {
    gen_opt_limit(CS, opt_limit);
  }
  if (opt_offset) {
    gen_opt_offset(CS, opt_offset);
  }
}

static void gen_select_expr_list_con(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_expr_list_con(ast));
  EXTRACT(select_expr_list, ast->left);
  EXTRACT(select_from_etc, ast->right);

  gen_select_expr_list(CS, select_expr_list);
  if (select_from_etc) {
    gen_select_from_etc(CS, select_from_etc);
  }
}

cql_noexport void init_gen_sql_callbacks(gen_sql_callbacks *cb)
{
  memset((void *)cb, 0, sizeof(gen_sql_callbacks));
  // with callbacks is for SQLite be default, the normal raw output
  // case is done with callbacks == NULL
  cb->mode = gen_mode_sql;
}

static void gen_select_statement_type(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_core(ast));
  EXTRACT_ANY(select_opts, ast->left);

  if (select_opts && is_ast_select_values(select_opts)) {
    gen_printf(CS, "VALUES");
  } else {
    gen_printf(CS, "SELECT");
    if (select_opts) {
      Contract(is_ast_select_opts(select_opts));
      gen_select_opts(CS, select_opts);
    }
  }
}

static void gen_values(CqlState* CS, ast_node *ast) {
  Contract(is_ast_values(ast));
  for (ast_node *item = ast; item; item = item->right) {
    EXTRACT(insert_list, item->left);
    gen_printf(CS, "(");
    if (insert_list) {
      gen_insert_list(CS, insert_list);
    }
    gen_printf(CS, ")");
    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

cql_noexport void gen_select_core(CqlState* CS, ast_node *ast) {

  if (is_ast_select_core_macro_ref(ast)) {
    gen_select_core_macro_ref(CS, ast);
  }
  else if (is_ast_select_core_macro_arg_ref(ast)) {
    gen_select_core_macro_arg_ref(CS, ast);
  }
  else {
    Contract(is_ast_select_core(ast));
    EXTRACT_ANY(select_core_left, ast->left);

    gen_select_statement_type(CS, ast);

    // select_core subtree can be a SELECT or VALUES statement
    if (is_ast_select_values(select_core_left)) {
      // VALUES [values]
      EXTRACT(values, ast->right);
      gen_values(CS, values);
    } else {
      // SELECT [select_expr_list_con]
      // We're making sure that we're in the SELECT clause of the select stmt
      Contract(select_core_left == NULL || is_ast_select_opts(select_core_left));
      CS->pending_indent = 1; // this gives us a single space before the select list if needed
      EXTRACT_NOTNULL(select_expr_list_con, ast->right);
      gen_select_expr_list_con(CS, select_expr_list_con);
    }
  }
}

static void gen_select_no_with(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_stmt(ast));
  EXTRACT_NOTNULL(select_core_list, ast->left);
  EXTRACT_NOTNULL(select_orderby, ast->right);

  gen_select_core_list(CS, select_core_list);
  gen_select_orderby(CS, select_orderby);
}

static void gen_cte_decl(CqlState* CS, ast_node *ast)  {
  Contract(is_ast_cte_decl(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s (", name);
  if (is_ast_star(ast->right)) {
    gen_printf(CS, "*");
  }
  else {
    gen_name_list(CS, ast->right);
  }
  gen_printf(CS, ")");
}

static void gen_cte_binding_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_cte_binding_list(ast));

  while (ast) {
     EXTRACT_NOTNULL(cte_binding, ast->left);
     EXTRACT_STRING(actual, cte_binding->left);
     EXTRACT_STRING(formal, cte_binding->right);
     gen_printf(CS, "%s AS %s", actual, formal);

     if (ast->right) {
       gen_printf(CS, ", ");
     }
     ast = ast->right;
  }
}

static void gen_shared_cte(CqlState* CS, ast_node *ast) {
  Contract(is_ast_shared_cte(ast));
  bool_t has_cte_procs_callback = gen_callbacks_lv && gen_callbacks_rv->cte_proc_callback;
  bool_t handled = false;

  if (has_cte_procs_callback) {
    handled = gen_callbacks_rv->cte_proc_callback(CS, ast, gen_callbacks_rv->cte_proc_context, CS->gen_output);
  }

  if (!handled) {
    EXTRACT_NOTNULL(call_stmt, ast->left);
    EXTRACT(cte_binding_list, ast->right);
    gen_call_stmt(CS, call_stmt);
    if (cte_binding_list) {
      gen_printf(CS, " USING ");
      gen_cte_binding_list(CS, cte_binding_list);
    }
  }
}

static void gen_cte_table(CqlState* CS, ast_node *ast)  {
  Contract(is_ast_cte_table(ast));
  EXTRACT(cte_decl, ast->left);
  EXTRACT_ANY_NOTNULL(cte_body, ast->right);

  gen_cte_decl(CS, cte_decl);

  if (is_ast_like(cte_body)) {
    gen_printf(CS, " LIKE ");
    if (is_ast_str(cte_body->left)) {
      gen_name(CS, cte_body->left);
    }
   else {
     gen_printf(CS, "(\n");
     GEN_BEGIN_INDENT(cte_indent, 2);
       gen_select_stmt(CS, cte_body->left);
     GEN_END_INDENT(cte_indent);
     gen_printf(CS, "\n)");
   }
   return;
  }

  gen_printf(CS, " AS (");

  if (is_ast_shared_cte(cte_body)) {
    gen_shared_cte(CS, cte_body);
    gen_printf(CS, ")");
  }
  else {
    gen_printf(CS, "\n");
    GEN_BEGIN_INDENT(cte_indent, 2);
      // the only other alternative is the select statement form
      gen_select_stmt(CS, cte_body);
    GEN_END_INDENT(cte_indent);
    gen_printf(CS, "\n)");
  }
}

static void gen_cte_tables(CqlState* CS, ast_node *ast, CSTR prefix) {
  bool_t first = true;

  while (ast) {
    Contract(is_ast_cte_tables(ast));
    EXTRACT_ANY_NOTNULL(cte_table, ast->left);

    bool_t handled = false;

    if (is_ast_cte_table(cte_table)) {
      Contract(is_ast_cte_table(cte_table));

      // callbacks can suppress some CTE for use in shared_fragments
      bool_t has_cte_suppress_callback = gen_callbacks_lv && gen_callbacks_rv->cte_suppress_callback;

      if (has_cte_suppress_callback) {
        handled = gen_callbacks_rv->cte_suppress_callback(CS, cte_table, gen_callbacks_rv->cte_suppress_context, CS->gen_output);
      }
    }

    if (!handled) {
      if (first) {
        gen_printf(CS, "%s", prefix);
        first = false;
      }
      else {
        gen_printf(CS, ",\n");
      }

      if (is_ast_cte_tables_macro_ref(cte_table)) {
        gen_cte_tables_macro_ref(CS, cte_table);
      }
      else if (is_ast_cte_tables_macro_arg_ref(cte_table)) {
        gen_cte_tables_macro_arg_ref(CS, cte_table);
      }
      else {
        gen_cte_table(CS, cte_table);
      }
    }

    ast = ast->right;
  }

  if (!first) {
    gen_printf(CS, "\n");
  }
}

static void gen_with_prefix(CqlState* CS, ast_node *ast) {
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
    CS->pending_indent -= 2;
    gen_cte_tables(CS, cte_tables, prefix);
  GEN_END_INDENT(cte_indent);
}

static void gen_with_select_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_with_select_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_ANY_NOTNULL(select_stmt, ast->right);

  gen_with_prefix(CS, with_prefix);
  gen_select_stmt(CS, select_stmt);
}

static void gen_select_core_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_core_list(ast));

  EXTRACT_ANY_NOTNULL(select_core, ast->left);

  gen_select_core(CS, select_core);

  EXTRACT(select_core_compound, ast->right);
  if (!select_core_compound) {
    return;
  }
  EXTRACT_OPTION(compound_operator, select_core_compound->left);
  EXTRACT_NOTNULL(select_core_list, select_core_compound->right);

  gen_printf(CS, "\n%s\n", get_compound_operator_name(compound_operator));
  gen_select_core_list(CS, select_core_list);
}


// This form is expanded late like select *
// since it only appears in shared fragments (actually only
// in conditional fragments) it will never be seen
// in the course of normal codegen, only in SQL expansion
// hence none of the code generators need to even know
// this is happening (again, just like select *).
// This approach gives us optimal sql for very little cost.
static void gen_select_nothing_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_nothing_stmt(ast));

  if (!for_sqlite(CS) || !ast->sem || !ast->sem->sptr) {
    gen_printf(CS, "SELECT NOTHING");
    return;
  }

  // we just generate the right number of dummy columns for Sqlite
  // type doesn't matter because it's going to be "WHERE 0"

  gen_printf(CS, "SELECT ");
  sem_struct *sptr = ast->sem->sptr;
  for (uint32_t i = 0; i < sptr->count; i++) {
    if (i) {
      gen_printf(CS, ",");
    }

    if (gen_callbacks_lv && gen_callbacks_rv->minify_aliases) {
      gen_printf(CS, "0");
    } else {
      gen_printf(CS, "0 ");
      gen_sptr_name(CS, sptr, i);
    }
  }
  gen_printf(CS, " WHERE 0");
}

static void gen_select_stmt(CqlState* CS, ast_node *ast) {
  if (is_ast_with_select_stmt(ast)) {
    gen_with_select_stmt(CS, ast);
  }
  else {
    Contract(is_ast_select_stmt(ast));
    gen_select_no_with(CS, ast);
  }
}

static void gen_version_attrs(CqlState* CS, ast_node *_Nullable ast) {
  for (ast_node *attr = ast; attr; attr = attr->right) {
    if (is_ast_recreate_attr(attr)) {
      gen_recreate_attr(CS, attr);
    }
    else if (is_ast_create_attr(attr)) {
      gen_create_attr(CS, attr);
    } else {
      Contract(is_ast_delete_attr(attr)); // the only other kind
      gen_delete_attr(CS, attr);
    }
  }
}

// If there is a handler, the handler will decide what to do.  If there is no handler
// or the handler returns false, then we honor the flag bit.  This lets you override
// the if_not_exists flag forcing it to be either ignored or enabled.  Both are potentially
// needed.  When emitting schema creation scripts for instance we always use IF NOT EXISTS
// even if the schema declaration didn't have it (which it usually doesn't).
static void gen_if_not_exists(CqlState* CS, ast_node *ast, bool_t if_not_exist) {
  bool_t if_not_exists_callback = gen_callbacks_lv && gen_callbacks_rv->if_not_exists_callback;
  bool_t handled = false;

  if (if_not_exists_callback) {
    handled = gen_callbacks_rv->if_not_exists_callback(CS, ast, gen_callbacks_rv->if_not_exists_context, CS->gen_output);
  }

  if (if_not_exist && !handled) {
    gen_printf(CS, "IF NOT EXISTS ");
  }
}

static void gen_eponymous(CqlState* CS, ast_node *ast, bool_t is_eponymous) {
  if (!for_sqlite(CS) && is_eponymous) {
    gen_printf(CS, "@EPONYMOUS ");
  }
}

static void gen_create_view_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "CREATE ");
  if (flags & VIEW_IS_TEMP) {
    gen_printf(CS, "TEMP ");
  }
  gen_printf(CS, "VIEW ");
  gen_if_not_exists(CS, ast, if_not_exist);
  gen_name(CS, name_ast);
  if (name_list) {
    gen_printf(CS, "(");
    gen_name_list(CS, name_list);
    gen_printf(CS, ")");
  }
  gen_printf(CS, " AS\n");
  GEN_BEGIN_INDENT(sel, 2);
  gen_select_stmt(CS, select_stmt);
  gen_version_attrs(CS, attrs);
  GEN_END_INDENT(sel);
}

static void gen_create_trigger_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "CREATE ");
  if (flags & TRIGGER_IS_TEMP) {
    gen_printf(CS, "TEMP ");
  }
  gen_printf(CS, "TRIGGER ");
  gen_if_not_exists(CS, ast, !!(flags & TRIGGER_IF_NOT_EXISTS));

  gen_name(CS, trigger_name_ast);
  gen_printf(CS, "\n  ");

  if (flags & TRIGGER_BEFORE) {
    gen_printf(CS, "BEFORE ");
  }
  else if (flags & TRIGGER_AFTER) {
    gen_printf(CS, "AFTER ");
  }
  else if (flags & TRIGGER_INSTEAD_OF) {
    gen_printf(CS, "INSTEAD OF ");
  }

  if (flags & TRIGGER_DELETE) {
    gen_printf(CS, "DELETE ");
  }
  else if (flags & TRIGGER_INSERT) {
    gen_printf(CS, "INSERT ");
  }
  else {
    gen_printf(CS, "UPDATE ");
    if (name_list) {
      gen_printf(CS, "OF ");
      gen_name_list(CS, name_list);
      gen_printf(CS, " ");
    }
  }
  gen_printf(CS, "ON ");
  gen_name(CS, table_name_ast);

  if (flags & TRIGGER_FOR_EACH_ROW) {
    gen_printf(CS, "\n  FOR EACH ROW");
  }

  if (when_expr) {
    gen_printf(CS, "\n  WHEN ");
    gen_root_expr(CS, when_expr);
  }

  gen_printf(CS, "\nBEGIN\n");
  gen_stmt_list(CS, stmt_list);
  gen_printf(CS, "END");
  gen_version_attrs(CS, trigger_attrs);
}

static void gen_create_table_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "CREATE ");
  if (temp) {
    gen_printf(CS, "TEMP ");
  }

  gen_printf(CS, "TABLE ");
  gen_if_not_exists(CS, ast, if_not_exist);

  gen_name(CS, table_name_ast);
  gen_printf(CS, "(\n");
  gen_col_key_list(CS, col_key_list);
  gen_printf(CS, "\n)");
  if (no_rowid) {
    gen_printf(CS, " WITHOUT ROWID");
  }
  gen_version_attrs(CS, table_attrs);
}

static void gen_create_virtual_table_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "CREATE VIRTUAL TABLE ");
  gen_if_not_exists(CS, ast, if_not_exist);
  gen_eponymous(CS, ast, is_eponymous);
  gen_printf(CS, "%s USING %s", name, module_name);

  if (!for_sqlite(CS)) {
    if (is_ast_following(module_args)) {
      gen_printf(CS, " (ARGUMENTS FOLLOWING) ");
    }
    else if (module_args) {
      gen_printf(CS, " ");
      gen_misc_attr_value(CS, module_args);
      gen_printf(CS, " ");
    }
    else {
      gen_printf(CS, " ");
    }

    // When emitting to SQLite we do not include the column declaration part
    // just whatever the args were because SQLite doesn't parse that part of the CQL syntax.
    // Note that CQL does not support general args because that's not parseable with this parser
    // tech but this is pretty general.  The declaration part is present here so that
    // CQL knows the type info of the net table we are creating.
    // Note also that virtual tables are always on the recreate plan, it isn't an option
    // and this will mean that you can't make a foreign key to a virtual table which is probably
    // a wise thing.

    gen_printf(CS, "AS (\n");
    gen_col_key_list(CS, col_key_list);
    gen_printf(CS, "\n)");

    // delete attribute is the only option (recreate by default)
    if (!is_ast_recreate_attr(table_attrs)) {
      Invariant(is_ast_delete_attr(table_attrs));
      gen_delete_attr(CS, table_attrs);
    }
  }
  else {
    if (is_ast_following(module_args)) {
      gen_printf(CS, " (\n");
      gen_col_key_list(CS, col_key_list);
      gen_printf(CS, ")");
    } else if (module_args) {
      gen_printf(CS, " ");
      gen_misc_attr_value(CS, module_args);
    }
  }
}

static void gen_drop_view_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_drop_view_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf(CS, "DROP VIEW ");
  if (if_exists) {
    gen_printf(CS, "IF EXISTS ");
  }
  gen_name(CS, name_ast);
}

static void gen_drop_table_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_drop_table_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf(CS, "DROP TABLE ");
  if (if_exists) {
    gen_printf(CS, "IF EXISTS ");
  }
  gen_name(CS, name_ast);
}

static void gen_drop_index_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_drop_index_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf(CS, "DROP INDEX ");
  if (if_exists) {
    gen_printf(CS, "IF EXISTS ");
  }
  gen_name(CS, name_ast);
}

static void gen_drop_trigger_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_drop_trigger_stmt(ast));
  EXTRACT_ANY(if_exists, ast->left);
  EXTRACT_NAME_AST(name_ast, ast->right);

  gen_printf(CS, "DROP TRIGGER ");
  if (if_exists) {
    gen_printf(CS, "IF EXISTS ");
  }
  gen_name(CS, name_ast);
}

static void gen_alter_table_add_column_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_alter_table_add_column_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(col_def, ast->right);

  gen_printf(CS, "ALTER TABLE ");
  gen_name(CS, name_ast);
  gen_printf(CS, " ADD COLUMN ");
  gen_col_def(CS, col_def);
}

bool_t eval_if_stmt_callback(CqlState* CS, ast_node *ast) {
  Contract(is_ast_if_stmt(ast));

  bool_t suppress = 0;
  if (gen_callbacks_lv && gen_callbacks_rv->if_stmt_callback) {
    CHARBUF_OPEN(buf);
    suppress = gen_callbacks_rv->if_stmt_callback(CS, ast, gen_callbacks_rv->if_stmt_context, &buf);
    gen_printf(CS, "%s", buf.ptr);
    CHARBUF_CLOSE(buf);
  }
  return suppress;
}

static void gen_cond_action(CqlState* CS, ast_node *ast) {
  Contract(is_ast_cond_action(ast));
  EXTRACT(stmt_list, ast->right);

  gen_root_expr(CS, ast->left);
  gen_printf(CS, " THEN\n");
  gen_stmt_list(CS, stmt_list);
}

static void gen_elseif_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_elseif(ast));

  while (ast) {
    Contract(is_ast_elseif(ast));
    EXTRACT(cond_action, ast->left);
    gen_printf(CS, "ELSE IF ");
    gen_cond_action(CS, cond_action);
    ast = ast->right;
  }
}

static void gen_if_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_if_stmt(ast));
  EXTRACT_NOTNULL(cond_action, ast->left);
  EXTRACT_NOTNULL(if_alt, ast->right);
  EXTRACT(elseif, if_alt->left);
  EXTRACT_NAMED(elsenode, else, if_alt->right);

  if (eval_if_stmt_callback(CS, ast)) {
    return;
  }

  gen_printf(CS, "IF ");
  gen_cond_action(CS, cond_action);

  if (elseif) {
    gen_elseif_list(CS, elseif);
  }

  if (elsenode) {
    gen_printf(CS, "ELSE\n");
    EXTRACT(stmt_list, elsenode->left);
    gen_stmt_list(CS, stmt_list);
  }

  gen_printf(CS, "END");
}

static void gen_guard_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_guard_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf(CS, "IF ");
  gen_expr(CS, expr, EXPR_PRI_ROOT);
  gen_printf(CS, " ");
  gen_one_stmt(CS, stmt);
}

static void gen_expr_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_expr_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  gen_expr(CS, expr, EXPR_PRI_ROOT);
}

static void gen_delete_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_delete_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(opt_where, ast->right);

  gen_printf(CS, "DELETE FROM ");
  gen_name(CS, name_ast);
  if (opt_where) {
    gen_printf(CS, " WHERE ");
    gen_root_expr(CS, opt_where->left);
  }
}

static void gen_with_delete_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_with_delete_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(delete_stmt, ast->right);

  gen_with_prefix(CS, with_prefix);
  gen_delete_stmt(CS, delete_stmt);
}

static void gen_update_entry(CqlState* CS, ast_node *ast) {
  Contract(is_ast_update_entry(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->right)
  EXTRACT_NAME_AST(name_ast, ast->left);
  gen_name(CS, name_ast);
  gen_printf(CS, " = ");
  gen_root_expr(CS, expr);
}

static void gen_update_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_update_list(ast));

  int32_t count = 0;
  for (ast_node *item = ast; item; item = item->right) {
    count++;
  }

  if (count <= 4) {
    gen_printf(CS, " ");
    for (ast_node *item = ast; item; item = item->right) {
      Contract(is_ast_update_list(item));
      EXTRACT_NOTNULL(update_entry, item->left);

      gen_update_entry(CS, update_entry);
      if (item->right) {
        gen_printf(CS, ", ");
      }
    }
  }
  else {
    GEN_BEGIN_INDENT(set_indent, 2);
    gen_printf(CS, "\n");
    for (ast_node *item = ast; item; item = item->right) {
      Contract(is_ast_update_list(item));
      EXTRACT_NOTNULL(update_entry, item->left);
  
      gen_update_entry(CS, update_entry);
      if (item->right) {
        gen_printf(CS, ",\n");
      }
    }
    GEN_END_INDENT(set_indent);
  }
}

static void gen_from_shape(CqlState* CS, ast_node *ast) {
  Contract(is_ast_from_shape(ast));
  EXTRACT_STRING(shape_name, ast->right);
  EXTRACT_ANY(column_spec, ast->left);
  gen_printf(CS, "FROM %s", shape_name);
  gen_column_spec(CS, column_spec);
}

static void gen_update_cursor_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_update_cursor_stmt(ast));
  EXTRACT_ANY(cursor, ast->left);
  EXTRACT_STRING(name, cursor);
  EXTRACT_ANY_NOTNULL(columns_values, ast->right);

  gen_printf(CS, "UPDATE CURSOR %s", name);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(CS, " USING ");
    gen_expr_names(CS, columns_values);
  }
  else {
    EXTRACT_ANY(column_spec, columns_values->left);
    EXTRACT_ANY(insert_list, columns_values->right);

    gen_column_spec(CS, column_spec);
    gen_printf(CS, " ");
    if (is_ast_from_shape(insert_list)) {
      gen_from_shape(CS, insert_list);
    }
    else {
      gen_printf(CS, "FROM VALUES(");
      gen_insert_list(CS, insert_list);
      gen_printf(CS, ")");
    }
  }
}

static void gen_update_stmt(CqlState* CS, ast_node *ast) {
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

  gen_printf(CS, "UPDATE");
  if (ast->left) {
    EXTRACT_NAME_AST(name_ast, ast->left);
    gen_printf(CS, " ");
    gen_name(CS, name_ast);
  }
  GEN_BEGIN_INDENT(up, 2);

  gen_printf(CS, "\nSET");
  if (is_ast_columns_values(update_list)) {
    // UPDATE table_name SET ([opt_column_spec]) = ([from_shape])
    EXTRACT(column_spec, update_list->left);
    EXTRACT_ANY_NOTNULL(from_shape_or_insert_list, update_list->right);

    gen_printf(CS, " ");
    gen_column_spec(CS, column_spec);
    gen_printf(CS, " = ");

    gen_printf(CS, "(");
    gen_insert_list(CS, from_shape_or_insert_list);
    gen_printf(CS, ")");
  } else {
    // UPDATE table_name SET [update_list] FROM [query_parts]
    gen_update_list(CS, update_list);
  }

  if (query_parts) {
    gen_printf(CS, "\nFROM ");
    gen_query_parts(CS, query_parts);
  }
  if (opt_where) {
    gen_printf(CS, "\n");
    gen_opt_where(CS, opt_where);
  }
  if (opt_orderby) {
    gen_printf(CS, "\n");
    gen_opt_orderby(CS, opt_orderby);
  }
  if (opt_limit) {
    gen_opt_limit(CS, opt_limit);
  }
  GEN_END_INDENT(up);
}

static void gen_with_update_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_with_update_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(update_stmt, ast->right);

  gen_with_prefix(CS, with_prefix);
  gen_update_stmt(CS, update_stmt);
}

static void gen_insert_list(CqlState* CS, ast_node *_Nullable ast) {
  Contract(!ast || is_ast_insert_list(ast));

  while (ast) {
    Contract(is_ast_insert_list(ast));

    if (is_ast_from_shape(ast->left)) {
      gen_shape_arg(CS, ast->left);
    }
    else {
      gen_root_expr(CS, ast->left);
    }

    if (ast->right) {
      gen_printf(CS, ", ");
    }
    ast = ast->right;
  }
}

cql_noexport void gen_insert_type(CqlState* CS, ast_node *ast) {
  if (is_ast_insert_or_ignore(ast)) {
    gen_printf(CS, "INSERT OR IGNORE");
  }
  else if (is_ast_insert_or_replace(ast)) {
    gen_printf(CS, "INSERT OR REPLACE");
  }
  else if (is_ast_insert_replace(ast)) {
    gen_printf(CS, "REPLACE");
  }
  else if (is_ast_insert_or_abort(ast)) {
    gen_printf(CS, "INSERT OR ABORT");
  }
  else if (is_ast_insert_or_fail(ast)) {
    gen_printf(CS, "INSERT OR FAIL");
  }
  else if (is_ast_insert_or_rollback(ast)) {
     gen_printf(CS, "INSERT OR ROLLBACK");
  }
  else {
    Contract(is_ast_insert_normal(ast));
    gen_printf(CS, "INSERT");
  }
}

static void gen_insert_dummy_spec(CqlState* CS, ast_node *ast) {
  Contract(is_ast_insert_dummy_spec(ast) || is_ast_seed_stub(ast));
  EXTRACT_ANY_NOTNULL(seed_expr, ast->left);
  EXTRACT_OPTION(flags, ast->right);

  if (suppress_attributes(CS)) {
    return;
  }

  gen_printf(CS, " @DUMMY_SEED(");
  gen_root_expr(CS, seed_expr);
  gen_printf(CS, ")");

  if (flags & INSERT_DUMMY_DEFAULTS) {
    gen_printf(CS, " @DUMMY_DEFAULTS");
  }

  if (flags & INSERT_DUMMY_NULLABLES) {
    gen_printf(CS, " @DUMMY_NULLABLES");
  }
}

static void gen_shape_def_base(CqlState* CS, ast_node *ast) {
  Contract(is_ast_like(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY(from_args, ast->right);

  gen_printf(CS, "LIKE ");
  gen_name(CS, name_ast);
  if (from_args) {
    gen_printf(CS, " ARGUMENTS");
  }
}

static void gen_shape_expr(CqlState* CS, ast_node *ast) {
  Contract(is_ast_shape_expr(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);

  if (!ast->right) {
    gen_printf(CS, "-");
  }
  gen_name(CS, name_ast);
}

static void gen_shape_exprs(CqlState* CS, ast_node *ast) {
 Contract(is_ast_shape_exprs(ast));

  while (ast) {
    Contract(is_ast_shape_exprs(ast));
    gen_shape_expr(CS, ast->left);
    if (ast->right) {
      gen_printf(CS, ", ");
    }
    ast = ast->right;
  }
}

static void gen_shape_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_shape_def(ast));
  EXTRACT_NOTNULL(like, ast->left);
  gen_shape_def_base(CS, like);

  if (ast->right) {
    gen_printf(CS, "(");
    gen_shape_exprs(CS, ast->right);
    gen_printf(CS, ")");
  }
}

static void gen_column_spec(CqlState* CS, ast_node *ast) {
  // allow null column_spec here so we don't have to test it everywhere
  if (ast) {
    gen_printf(CS, "(");
    if (is_ast_shape_def(ast->left)) {
      gen_shape_def(CS, ast->left);
    }
    else {
      EXTRACT(name_list, ast->left);
      if (name_list) {
        gen_name_list(CS, name_list);
      }
    }
    gen_printf(CS, ")");
  }
}

static void gen_insert_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_insert_stmt(ast));
  EXTRACT_ANY_NOTNULL(insert_type, ast->left);
  EXTRACT_NOTNULL(name_columns_values, ast->right);
  EXTRACT_NAME_AST(name_ast, name_columns_values->left);
  EXTRACT_ANY_NOTNULL(columns_values, name_columns_values->right);
  EXTRACT_ANY(insert_dummy_spec, insert_type->left);

  gen_insert_type(CS, insert_type);
  gen_printf(CS, " INTO ");
  gen_name(CS, name_ast);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(CS, " USING ");
    gen_expr_names(CS, columns_values);
  }
  else if (is_select_stmt(columns_values)) {
    gen_printf(CS, " USING ");
    gen_select_stmt(CS, columns_values);
  }
  else if (is_ast_columns_values(columns_values)) {
    EXTRACT(column_spec, columns_values->left);
    EXTRACT_ANY(insert_list, columns_values->right);
    gen_column_spec(CS, column_spec);

    if (is_select_stmt(insert_list)) {
      gen_printf(CS, "\n");
      GEN_BEGIN_INDENT(sel, 2);
        gen_select_stmt(CS, insert_list);
      GEN_END_INDENT(sel);
    }
    else if (is_ast_from_shape(insert_list)) {
      gen_printf(CS, " ");
      gen_from_shape(CS, insert_list);
    }
    else {
      gen_printf(CS, " VALUES(");
      gen_insert_list(CS, insert_list);
      gen_printf(CS, ")");
    }

    if (insert_dummy_spec) {
      gen_insert_dummy_spec(CS, insert_dummy_spec);
    }
  }
  else {
    // INSERT [conflict resolution] INTO name DEFAULT VALUES
    Contract(is_ast_default_columns_values(columns_values));
    gen_printf(CS, " DEFAULT VALUES");
  }
}

static void gen_with_insert_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_with_insert_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(insert_stmt, ast->right);

  gen_with_prefix(CS, with_prefix);
  gen_insert_stmt(CS, insert_stmt);
}

static void gen_expr_names(CqlState* CS, ast_node *ast) {
  Contract(is_ast_expr_names(ast));

  for (ast_node *list = ast; list; list = list->right) {
    EXTRACT(expr_name, list->left);
    EXTRACT_ANY(expr, expr_name->left);
    EXTRACT_NOTNULL(opt_as_alias, expr_name->right);

    gen_expr(CS, expr, EXPR_PRI_ROOT);
    gen_as_alias(CS, opt_as_alias);

    if (list->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_fetch_cursor_from_blob_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_fetch_cursor_from_blob_stmt(ast));
  EXTRACT_ANY_NOTNULL(cursor, ast->left);
  EXTRACT_ANY_NOTNULL(blob, ast->right);

  gen_printf(CS, "FETCH ");
  gen_expr(CS, cursor, EXPR_PRI_ROOT);
  gen_printf(CS, " FROM BLOB ");
  gen_expr(CS, blob, EXPR_PRI_ROOT);
}

static void gen_set_blob_from_cursor_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_set_blob_from_cursor_stmt(ast));
  EXTRACT_ANY_NOTNULL(blob, ast->left);
  EXTRACT_ANY_NOTNULL(cursor, ast->right);

  gen_printf(CS, "SET ");
  gen_expr(CS, blob, EXPR_PRI_ROOT);
  gen_printf(CS, " FROM CURSOR ");
  gen_expr(CS, cursor, EXPR_PRI_ROOT);
}

static void gen_fetch_values_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_fetch_values_stmt(ast));

  EXTRACT(insert_dummy_spec, ast->left);
  EXTRACT_NOTNULL(name_columns_values, ast->right);
  EXTRACT_STRING(name, name_columns_values->left);
  EXTRACT_ANY_NOTNULL(columns_values, name_columns_values->right);

  gen_printf(CS, "FETCH %s", name);

  if (is_ast_expr_names(columns_values)) {
    gen_printf(CS, " USING ");
    gen_expr_names(CS, columns_values);
  } else {
    EXTRACT(column_spec, columns_values->left);
    gen_column_spec(CS, column_spec);
    gen_printf(CS, " ");

    if (is_ast_from_shape(columns_values->right)) {
      gen_from_shape(CS, columns_values->right);
    }
    else {
      EXTRACT(insert_list, columns_values->right);
      gen_printf(CS, "FROM VALUES(");
      gen_insert_list(CS, insert_list);
      gen_printf(CS, ")");
    }
  }

  if (insert_dummy_spec) {
    gen_insert_dummy_spec(CS, insert_dummy_spec);
  }
}

static void gen_assign(CqlState* CS, ast_node *ast) {
  Contract(is_ast_assign(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf(CS, "SET ");
  gen_name(CS, name_ast);
  gen_printf(CS, " := ");
  gen_root_expr(CS, expr);
}

static void gen_let_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_let_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf(CS, "LET ");
  gen_name(CS, name_ast);
  gen_printf(CS, " := ");
  gen_root_expr(CS, expr);
}

static void gen_const_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_const_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(expr, ast->right);

  gen_printf(CS, "CONST ");
  gen_name(CS, name_ast);
  gen_printf(CS, " := ");
  gen_root_expr(CS, expr);
}

static void gen_opt_inout(CqlState* CS, ast_node *ast) {
  if (is_ast_in(ast)) {
    gen_printf(CS, "IN ");
  }
  else if (is_ast_out(ast)) {
    gen_printf(CS, "OUT ");
  }
  else if (is_ast_inout(ast)) {
    gen_printf(CS, "INOUT ");
  }
  else {
    Contract(!ast);
  }
}

static void gen_normal_param(CqlState* CS, ast_node *ast) {
  Contract(is_ast_param(ast));
  EXTRACT_ANY(opt_inout, ast->left);
  EXTRACT_NOTNULL(param_detail, ast->right);
  EXTRACT_NAME_AST(name_ast, param_detail->left);
  EXTRACT_ANY_NOTNULL(data_type, param_detail->right);

  gen_opt_inout(CS, opt_inout);
  gen_name(CS, name_ast);
  gen_printf(CS, " ");
  gen_data_type(CS, data_type);
}

static void gen_like_param(CqlState* CS, ast_node *ast) {
  Contract(is_ast_param(ast));
  EXTRACT_NOTNULL(param_detail, ast->right);
  EXTRACT_NOTNULL(shape_def, param_detail->right);

  if (param_detail->left) {
    EXTRACT_STRING(name, param_detail->left);
    gen_printf(CS, "%s ", name);
  }

  gen_shape_def(CS, shape_def);
}

static void gen_param(CqlState* CS, ast_node *ast) {
  Contract(is_ast_param(ast));

  EXTRACT_NOTNULL(param_detail, ast->right);
  if (is_ast_shape_def(param_detail->right)) {
    gen_like_param(CS, ast);
  }
  else {
    gen_normal_param(CS, ast);
  }
}

cql_noexport void gen_params(CqlState* CS, ast_node *ast) {
  Contract(is_ast_params(ast));

  for (ast_node *cur = ast; cur; cur = cur->right) {
    Contract(is_ast_params(cur));
    EXTRACT_NOTNULL(param, cur->left);

    gen_param(CS, param);

    if (cur->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_create_proc_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT(stmt_list, proc_params_stmts->right);

  gen_printf(CS, "PROC ");
  gen_name(CS, name_ast);
  gen_printf(CS, " (");
  if (params) {
    gen_params(CS, params);
  }
  gen_printf(CS, ")\nBEGIN\n");
  gen_stmt_list(CS, stmt_list);
  gen_printf(CS, "END");
}

static void gen_declare_proc_from_create_proc(CqlState* CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  Contract(!for_sqlite(CS));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);

  gen_printf(CS, "DECLARE PROC %s (", name);
  if (params) {
    gen_params(CS, params);
  }
  gen_printf(CS, ")");

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
  // if no SEM then we can't do the full declaration, do the best we can with just AST
#else
  if (ast->sem) {
    if (has_out_stmt_result(ast)) {
      gen_printf(CS, " OUT");
    }

    if (has_out_union_stmt_result(ast)) {
      gen_printf(CS, " OUT UNION");
    }

    if (is_struct(ast->sem->sem_type)) {
      sem_struct *sptr = ast->sem->sptr;

      gen_printf(CS, " (");
      for (uint32_t i = 0; i < sptr->count; i++) {
        gen_sptr_name(CS, sptr, i);
        gen_printf(CS, " ");

        sem_t sem_type = sptr->semtypes[i];
        gen_printf(CS, "%s", coretype_string(sem_type));

        CSTR kind = sptr->kinds[i];
        if (kind) {
          gen_type_kind(CS, kind);
        }

        if (is_not_nullable(sem_type)) {
          gen_not_null(CS);
        }

        if (sensitive_flag(sem_type)) {
          gen_printf(CS, " @SENSITIVE");
        }

        if (i + 1 < sptr->count) {
          gen_printf(CS, ", ");
        }
      }
      gen_printf(CS, ")");

      if ((has_out_stmt_result(ast) || has_out_union_stmt_result(ast)) && is_dml_proc(ast->sem->sem_type)) {
        // out [union] can be DML or not, so we have to specify
        gen_printf(CS, " USING TRANSACTION");
      }
    }
    else if (is_dml_proc(ast->sem->sem_type)) {
      gen_printf(CS, " USING TRANSACTION");
    }
  }
#endif
}

// the current primary output buffer for the closure of declares
//static charbuf *closure_output;

// The declares we have already emitted, if NULL we are emitting
// everything every time -- useful for --test output but otherwise
// just redundant at best.  Note cycles are not possible.
// even with no checking because declares form a partial order.
//static symtab *closure_emitted;

static bool_t gen_found_set_kind(CqlState* CS, ast_node *ast, void *context, charbuf *buffer) {
  EXTRACT_STRING(name, ast);
  ast_node *proc = NULL;

  CHARBUF_OPEN(proc_name);
    for (int32_t i = 0; name[i] && name[i] != ' '; i++) {
      bputc(&proc_name, name[i]);
    }
    proc = find_proc(CS, proc_name.ptr);
  CHARBUF_CLOSE(proc_name);

  if (proc) {
    // get canonical name
    EXTRACT_STRING(pname, get_proc_name(CS, proc));

    // we interrupt the current decl to emit a decl for this new name
    if (!CS->closure_emitted || symtab_add(CS, CS->closure_emitted, pname, NULL)) {
      CHARBUF_OPEN(current);
      charbuf *gen_output_saved = CS->gen_output;

      CS->gen_output = &current;
      gen_declare_proc_from_create_or_decl(CS, proc);

      CS->gen_output = CS->closure_output;
      gen_printf(CS, "%s;\n", current.ptr);

      CS->gen_output = gen_output_saved;
      CHARBUF_CLOSE(current);
    }
  }

  return false;
}

cql_noexport void gen_declare_proc_closure(CqlState* CS, ast_node *ast, symtab *emitted) {
  gen_sql_callbacks callbacks = {
     .set_kind_callback = gen_found_set_kind,
     .set_kind_context = emitted
  };
  gen_callbacks_lv = &callbacks;

  EXTRACT_STRING(name, ast->left);
  if (emitted) {
    // if specified then we use this to track what we have already emitted
    symtab_add(CS, emitted, name, NULL);
  }

  CS->closure_output = CS->gen_output;
  CS->closure_emitted = emitted;

  CHARBUF_OPEN(current);
    CS->gen_output = &current;
    gen_declare_proc_from_create_proc(CS, ast);

    CS->gen_output = CS->closure_output;
    gen_printf(CS, "%s;\n", current.ptr);
  CHARBUF_CLOSE(current);

  // Make sure we're clean on exit -- mainly so that ASAN leak detection
  // doesn't think there are roots when we are actually done with the
  // stuff.  We want to see the leaks if there are any.
  gen_callbacks_lv = NULL;
  CS->closure_output = NULL;
  CS->closure_emitted = NULL;
}

static void gen_typed_name(CqlState* CS, ast_node *ast) {
  EXTRACT(typed_name, ast);
  EXTRACT_ANY(name, typed_name->left);
  EXTRACT_ANY_NOTNULL(type, typed_name->right);

  if (name) {
    gen_name(CS, name);
    gen_printf(CS, " ");
  }

  if (is_ast_shape_def(type)) {
    gen_shape_def(CS, type);
  }
  else {
    gen_data_type(CS, type);
  }
}

void gen_typed_names(CqlState* CS, ast_node *ast) {
  Contract(is_ast_typed_names(ast));

  for (ast_node *item = ast; item; item = item->right) {
    Contract(is_ast_typed_names(item));
    gen_typed_name(CS, item->left);

    if (item->right) {
      gen_printf(CS, ", ");
    }
  }
}

static void gen_declare_proc_no_check_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_proc_no_check_stmt(ast));
  EXTRACT_ANY_NOTNULL(proc_name, ast->left);
  EXTRACT_STRING(name, proc_name);
  gen_printf(CS, "DECLARE PROC %s NO CHECK", name);
}

cql_noexport void gen_declare_interface_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_interface_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT_NOTNULL(typed_names, proc_params_stmts->right);

  gen_printf(CS, "DECLARE INTERFACE %s", name);

  gen_printf(CS, " (");
  gen_typed_names(CS, typed_names);
  gen_printf(CS, ")");
}

static void gen_declare_proc_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_proc_stmt(ast));
  EXTRACT_NOTNULL(proc_name_type, ast->left);
  EXTRACT_STRING(name, proc_name_type->left);
  EXTRACT_OPTION(type, proc_name_type->right);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT(typed_names, proc_params_stmts->right);

  gen_printf(CS, "DECLARE PROC %s (", name);
  if (params) {
    gen_params(CS, params);
  }
  gen_printf(CS, ")");

  if (type & PROC_FLAG_USES_OUT) {
    gen_printf(CS, " OUT");
  }

  if (type & PROC_FLAG_USES_OUT_UNION) {
    gen_printf(CS, " OUT UNION");
  }

  if (typed_names) {
    Contract(type & PROC_FLAG_STRUCT_TYPE);
    gen_printf(CS, " (");
    gen_typed_names(CS, typed_names);
    gen_printf(CS, ")");
  }

  // we don't emit USING TRANSACTION unless it's needed

  // if it doesnt use DML it's not needed
  if (!(type & PROC_FLAG_USES_DML)) {
    return;
  }

  // out can be either, so emit it if needed
  if (type & (PROC_FLAG_USES_OUT | PROC_FLAG_USES_OUT_UNION)) {
    gen_printf(CS, " USING TRANSACTION");
    return;
  }

  // if the proc returns a struct not via out then it uses SELECT and so it's implictly DML
  if (type & PROC_FLAG_STRUCT_TYPE) {
    return;
  }

  // it's not an OUT and it doesn't have a result but it does use DML
  // the only flag combo left is a basic dml proc.
  Contract(type == PROC_FLAG_USES_DML);
  gen_printf(CS, " USING TRANSACTION");
}

cql_noexport void gen_declare_proc_from_create_or_decl(CqlState* CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast) || is_ast_declare_proc_stmt(ast));
  if (is_ast_create_proc_stmt(ast)) {
    gen_declare_proc_from_create_proc(CS, ast);
  }
  else {
    gen_declare_proc_stmt(CS, ast);
  }
}

static void gen_declare_select_func_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_select_func_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf(CS, "DECLARE SELECT FUNC %s (", name);
  if (params) {
    gen_params(CS, params);
  }
  gen_printf(CS, ") ");

  if (is_ast_typed_names(ret_data_type)) {
    // table valued function
    gen_printf(CS, "(");
    gen_typed_names(CS, ret_data_type);
    gen_printf(CS, ")");
  }
  else {
    // standard function
    gen_data_type(CS, ret_data_type);
  }
}

static void gen_declare_select_func_no_check_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_select_func_no_check_stmt(ast));
  EXTRACT_STRING(name, ast-> left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf(CS, "DECLARE SELECT FUNC %s NO CHECK ", name);

  if (is_ast_typed_names(ret_data_type)) {
    // table valued function
    gen_printf(CS, "(");
    gen_typed_names(CS, ret_data_type);
    gen_printf(CS, ")");
  }
  else {
    // standard function
    gen_data_type(CS, ret_data_type);
  }
}

static void gen_declare_func_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_func_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf(CS, "DECLARE FUNC %s (", name);
  if (params) {
    gen_params(CS, params);
  }
  gen_printf(CS, ") ");

  gen_data_type(CS, ret_data_type);
}

static void gen_declare_func_no_check_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_func_no_check_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT_ANY_NOTNULL(ret_data_type, func_params_return->right);

  gen_printf(CS, "DECLARE FUNC %s NO CHECK ", name);

  gen_data_type(CS, ret_data_type);
}

static void gen_declare_vars_type(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_vars_type(ast));
  EXTRACT_NOTNULL(name_list, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  gen_printf(CS, "DECLARE ");
  gen_name_list(CS, name_list);
  gen_printf(CS, " ");
  gen_data_type(CS, data_type);
}

static void gen_declare_cursor(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_cursor(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_ANY_NOTNULL(source, ast->right);

  gen_printf(CS, "CURSOR %s FOR", name);

  if (is_select_stmt(source) || is_ast_call_stmt(source)) {
    // The two statement cases are unified
    gen_printf(CS, "\n");
    GEN_BEGIN_INDENT(cursor, 2);
      gen_one_stmt(CS, source);
    GEN_END_INDENT(cursor);
  }
  else {
    gen_printf(CS, " ");
    gen_root_expr(CS, source);
  }
}

static void gen_declare_cursor_like_name(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_cursor_like_name(ast));
  EXTRACT_STRING(new_cursor_name, ast->left);
  EXTRACT_NOTNULL(shape_def, ast->right);

  gen_printf(CS, "CURSOR %s ", new_cursor_name);
  gen_shape_def(CS, shape_def);
}

static void gen_declare_cursor_like_select(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_cursor_like_select(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf(CS, "CURSOR %s LIKE ", name);
  gen_one_stmt(CS, stmt);
}

static void gen_declare_cursor_like_typed_names(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_cursor_like_typed_names(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_ANY_NOTNULL(typed_names, ast->right);

  gen_printf(CS, "CURSOR %s LIKE (", name);
  gen_typed_names(CS, typed_names);
  gen_printf(CS, ")");
}

static void gen_declare_named_type(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_named_type(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  gen_printf(CS, "TYPE ");
  gen_name(CS, name_ast);
  gen_printf(CS, " ");
  gen_data_type(CS, data_type);
}

static void gen_declare_value_cursor(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_value_cursor(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_ANY_NOTNULL(stmt, ast->right);

  gen_printf(CS, "CURSOR %s FETCH FROM ", name);
  gen_one_stmt(CS, stmt);
}

static void gen_declare_enum_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_enum_stmt(ast));
  EXTRACT_NOTNULL(typed_name, ast->left);
  EXTRACT_NOTNULL(enum_values, ast->right);
  gen_printf(CS, "DECLARE ENUM ");
  gen_typed_name(CS, typed_name);
  gen_printf(CS, " (");

  while (enum_values) {
     EXTRACT_NOTNULL(enum_value, enum_values->left);
     EXTRACT_STRING(enum_name, enum_value->left);
     EXTRACT_ANY(expr, enum_value->right);

     gen_printf(CS, "\n  %s", enum_name);
     if (expr) {
       gen_printf(CS, " = ");
       gen_root_expr(CS, expr);
     }

     if (enum_values->right) {
       gen_printf(CS, ",");
     }

     enum_values = enum_values->right;
  }
  gen_printf(CS, "\n)");
}

static void gen_declare_group_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_group_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(stmt_list, ast->right);
  gen_printf(CS, "DECLARE GROUP %s\nBEGIN\n", name);

  while (stmt_list) {
     EXTRACT_ANY_NOTNULL(stmt, stmt_list->left);
     gen_printf(CS, "  ");
     gen_one_stmt(CS, stmt);
     gen_printf(CS, ";\n");
     stmt_list = stmt_list->right;
  }
  gen_printf(CS, "END");
}

static void gen_declare_const_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_const_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(const_values, ast->right);
  gen_printf(CS, "DECLARE CONST GROUP %s (", name);

  while (const_values) {
     EXTRACT_NOTNULL(const_value, const_values->left);
     EXTRACT_STRING(const_name, const_value->left);
     EXTRACT_ANY(expr, const_value->right);

     gen_printf(CS, "\n  %s", const_name);
     if (expr) {
       gen_printf(CS, " = ");
       gen_root_expr(CS, expr);
     }

     if (const_values->right) {
       gen_printf(CS, ",");
     }

     const_values = const_values->right;
  }
  gen_printf(CS, "\n)");
}

static void gen_set_from_cursor(CqlState* CS, ast_node *ast) {
  Contract(is_ast_set_from_cursor(ast));
  EXTRACT_NAME_AST(var_name_ast, ast->left);
  EXTRACT_STRING(cursor_name, ast->right);

  gen_printf(CS, "SET ");
  gen_name(CS, var_name_ast);
  gen_printf(CS, " FROM CURSOR %s", cursor_name);
}

static void gen_fetch_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_fetch_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT(name_list, ast->right);

  gen_printf(CS, "FETCH %s", name);
  if (name_list) {
    gen_printf(CS, " INTO ");
    gen_name_list(CS, name_list);
  }
}

static void gen_switch_cases(CqlState* CS, ast_node *ast) {
  Contract(is_ast_switch_case(ast));

  while (ast) {
     EXTRACT_NOTNULL(connector, ast->left);
     if (connector->left) {
        EXTRACT_NOTNULL(expr_list, connector->left);
        EXTRACT(stmt_list, connector->right);

        gen_printf(CS, "  WHEN ");
        gen_expr_list(CS, expr_list);
        if (stmt_list) {
            gen_printf(CS, " THEN\n");
            GEN_BEGIN_INDENT(statement, 2);
              gen_stmt_list(CS, stmt_list);
            GEN_END_INDENT(statement);
        }
        else {
          gen_printf(CS, " THEN NOTHING\n");
        }
     }
     else {
        EXTRACT_NOTNULL(stmt_list, connector->right);

        gen_printf(CS, "  ELSE\n");
        GEN_BEGIN_INDENT(statement, 2);
          gen_stmt_list(CS, stmt_list);
        GEN_END_INDENT(statement);
     }
     ast = ast->right;
  }
  gen_printf(CS, "END");
}

static void gen_switch_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_switch_stmt(ast));
  EXTRACT_OPTION(all_values, ast->left);
  EXTRACT_NOTNULL(switch_body, ast->right);
  EXTRACT_ANY_NOTNULL(expr, switch_body->left);
  EXTRACT_NOTNULL(switch_case, switch_body->right);

  // SWITCH [expr] [switch_body] END
  // SWITCH [expr] ALL VALUES [switch_body] END

  gen_printf(CS, "SWITCH ");
  gen_root_expr(CS, expr);

  if (all_values) {
    gen_printf(CS, " ALL VALUES");
  }
  gen_printf(CS, "\n");

  gen_switch_cases(CS, switch_case);
}

static void gen_while_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_while_stmt(ast));
  EXTRACT_ANY_NOTNULL(expr, ast->left);
  EXTRACT(stmt_list, ast->right);

  // WHILE [expr] BEGIN [stmt_list] END

  gen_printf(CS, "WHILE ");
  gen_root_expr(CS, expr);

  gen_printf(CS, "\nBEGIN\n");
  gen_stmt_list(CS, stmt_list);
  gen_printf(CS, "END");
}

static void gen_loop_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_loop_stmt(ast));
  EXTRACT_NOTNULL(fetch_stmt, ast->left);
  EXTRACT(stmt_list, ast->right);

  // LOOP [fetch_stmt] BEGIN [stmt_list] END

  gen_printf(CS, "LOOP ");
  gen_fetch_stmt(CS, fetch_stmt);
  gen_printf(CS, "\nBEGIN\n");
  gen_stmt_list(CS, stmt_list);
  gen_printf(CS, "END");
}

static void gen_call_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_call_stmt(ast));
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT(arg_list, ast->right);

  gen_printf(CS, "CALL ");
  gen_name(CS, name_ast);
  gen_printf(CS, "(");
  if (arg_list) {
    gen_arg_list(CS, arg_list);
  }

  gen_printf(CS, ")");
}

static void gen_declare_out_call_stmt(CqlState* CS, ast_node *ast) {
  EXTRACT_NOTNULL(call_stmt, ast->left);
  gen_printf(CS, "DECLARE OUT ");
  gen_call_stmt(CS, call_stmt);
}

static void gen_fetch_call_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_fetch_call_stmt(ast));
  Contract(is_ast_call_stmt(ast->right));
  EXTRACT_STRING(cursor_name, ast->left);
  EXTRACT_NOTNULL(call_stmt, ast->right);

  gen_printf(CS, "FETCH %s FROM ", cursor_name);
  gen_call_stmt(CS, call_stmt);
}

static void gen_continue_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_continue_stmt(ast));

  gen_printf(CS, "CONTINUE");
}

static void gen_leave_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_leave_stmt(ast));

  gen_printf(CS, "LEAVE");
}

static void gen_return_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_return_stmt(ast));

  gen_printf(CS, "RETURN");
}

static void gen_rollback_return_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_rollback_return_stmt(ast));

  gen_printf(CS, "ROLLBACK RETURN");
}

static void gen_commit_return_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_commit_return_stmt(ast));

  gen_printf(CS, "COMMIT RETURN");
}

static void gen_proc_savepoint_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_proc_savepoint_stmt(ast));
  EXTRACT(stmt_list, ast->left);

  gen_printf(CS, "PROC SAVEPOINT");
  gen_printf(CS, "\nBEGIN\n");
  gen_stmt_list(CS, stmt_list);
  gen_printf(CS, "END");
}

static void gen_throw_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_throw_stmt(ast));

  gen_printf(CS, "THROW");
}

static void gen_begin_trans_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_begin_trans_stmt(ast));
  EXTRACT_OPTION(mode, ast->left);

  gen_printf(CS, "BEGIN");

  if (mode == TRANS_IMMEDIATE) {
    gen_printf(CS, " IMMEDIATE");
  }
  else if (mode == TRANS_EXCLUSIVE) {
    gen_printf(CS, " EXCLUSIVE");
  }
  else {
    // this is the default, and only remaining case, no additional output needed
    Contract(mode == TRANS_DEFERRED);
  }
}

static void gen_commit_trans_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_commit_trans_stmt(ast));

  gen_printf(CS, "COMMIT");
}

static void gen_rollback_trans_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_rollback_trans_stmt(ast));

  gen_printf(CS, "ROLLBACK");

  if (ast->left) {
    EXTRACT_STRING(name, ast->left);
    gen_printf(CS, " TO %s", name);
  }
}

static void gen_savepoint_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_savepoint_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "SAVEPOINT %s", name);
}

static void gen_release_savepoint_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_release_savepoint_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "RELEASE %s", name);
}

static void gen_trycatch_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_trycatch_stmt(ast));
  EXTRACT_NAMED(try_list, stmt_list, ast->left);
  EXTRACT_NAMED(catch_list, stmt_list, ast->right);

  gen_printf(CS, "TRY\n");
  gen_stmt_list(CS, try_list);
  gen_printf(CS, "CATCH\n");
  gen_stmt_list(CS, catch_list);
  gen_printf(CS, "END");
}

static void gen_close_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_close_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "CLOSE %s", name);
}

static void gen_out_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_out_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "OUT %s", name);
}

static void gen_out_union_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_out_union_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "OUT UNION %s", name);
}

static void gen_child_results(CqlState* CS, ast_node *ast) {
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

    gen_printf(CS, "\n  ");
    gen_call_stmt(CS, call_stmt);
    gen_printf(CS, " USING (");
    gen_name_list(CS, name_list);
    gen_printf(CS, ")");

    if (child_column_name) {
      gen_printf(CS, " AS %s", child_column_name);
    }

    if (item->right) {
      gen_printf(CS, " AND");
    }

    item = item->right;
  }
}

static void gen_out_union_parent_child_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_out_union_parent_child_stmt(ast));
  EXTRACT_NOTNULL(call_stmt, ast->left);
  EXTRACT_NOTNULL(child_results, ast->right);

  gen_printf(CS, "OUT UNION ");
  gen_call_stmt(CS, call_stmt);
  gen_printf(CS, " JOIN ");
  gen_child_results(CS, child_results);
}

static void gen_echo_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_echo_stmt(ast));
  EXTRACT_STRING(rt_name, ast->left);

  gen_printf(CS, "@ECHO %s, ", rt_name);
  gen_root_expr(CS, ast->right);  // emit the quoted literal
}

static void gen_schema_upgrade_script_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_schema_upgrade_script_stmt(ast));

  gen_printf(CS, "@SCHEMA_UPGRADE_SCRIPT");
}

static void gen_schema_upgrade_version_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_schema_upgrade_version_stmt(ast));
  EXTRACT_OPTION(vers, ast->left);

  gen_printf(CS, "@SCHEMA_UPGRADE_VERSION (%d)", vers);
}

static void gen_previous_schema_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_previous_schema_stmt(ast));

  gen_printf(CS, "@PREVIOUS_SCHEMA");
}

static void gen_enforcement_options(CqlState* CS, ast_node *ast) {
  EXTRACT_OPTION(option, ast);

  switch (option) {
    case ENFORCE_CAST:
      gen_printf(CS, "CAST");
      break;

    case ENFORCE_STRICT_JOIN:
      gen_printf(CS, "JOIN");
      break;

    case ENFORCE_FK_ON_UPDATE:
      gen_printf(CS, "FOREIGN KEY ON UPDATE");
      break;

    case ENFORCE_UPSERT_STMT:
      gen_printf(CS, "UPSERT STATEMENT");
      break;

    case ENFORCE_WINDOW_FUNC:
      gen_printf(CS, "WINDOW FUNCTION");
      break;

    case ENFORCE_WITHOUT_ROWID:
      gen_printf(CS, "WITHOUT ROWID");
      break;

    case ENFORCE_TRANSACTION:
      gen_printf(CS, "TRANSACTION");
      break;

    case ENFORCE_SELECT_IF_NOTHING:
      gen_printf(CS, "SELECT IF NOTHING");
      break;

    case ENFORCE_INSERT_SELECT:
      gen_printf(CS, "INSERT SELECT");
      break;

    case ENFORCE_TABLE_FUNCTION:
      gen_printf(CS, "TABLE FUNCTION");
      break;

    case ENFORCE_ENCODE_CONTEXT_COLUMN:
      gen_printf(CS, "ENCODE CONTEXT COLUMN");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_INTEGER:
      gen_printf(CS, "ENCODE CONTEXT TYPE INTEGER");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_LONG_INTEGER:
      gen_printf(CS, "ENCODE CONTEXT TYPE LONG_INTEGER");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_REAL:
      gen_printf(CS, "ENCODE CONTEXT TYPE REAL");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_BOOL:
      gen_printf(CS, "ENCODE CONTEXT TYPE BOOL");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_TEXT:
      gen_printf(CS, "ENCODE CONTEXT TYPE TEXT");
      break;

    case ENFORCE_ENCODE_CONTEXT_TYPE_BLOB:
      gen_printf(CS, "ENCODE CONTEXT TYPE BLOB");
      break;

    case ENFORCE_IS_TRUE:
      gen_printf(CS, "IS TRUE");
      break;

    case ENFORCE_SIGN_FUNCTION:
      gen_printf(CS, "SIGN FUNCTION");
      break;

    case ENFORCE_CURSOR_HAS_ROW:
      gen_printf(CS, "CURSOR HAS ROW");
      break;

    case ENFORCE_UPDATE_FROM:
      gen_printf(CS, "UPDATE FROM");
      break;

    case ENFORCE_AND_OR_NOT_NULL_CHECK:
      gen_printf(CS, "AND OR NOT NULL CHECK");
      break;

    default:
      // this is all that's left
      Contract(option == ENFORCE_FK_ON_DELETE);
      gen_printf(CS, "FOREIGN KEY ON DELETE");
      break;
  }
}

static void gen_enforce_strict_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_enforce_strict_stmt(ast));
  gen_printf(CS, "@ENFORCE_STRICT ");
  gen_enforcement_options(CS, ast->left);
}

static void gen_enforce_normal_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_enforce_normal_stmt(ast));
  gen_printf(CS, "@ENFORCE_NORMAL ");
  gen_enforcement_options(CS, ast->left);
}

static void gen_enforce_reset_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_enforce_reset_stmt(ast));
  gen_printf(CS, "@ENFORCE_RESET");
}

static void gen_enforce_push_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_enforce_push_stmt(ast));
  gen_printf(CS, "@ENFORCE_PUSH");
}

static void gen_enforce_pop_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_enforce_pop_stmt(ast));
  gen_printf(CS, "@ENFORCE_POP");
}

static void gen_region_spec(CqlState* CS, ast_node *ast) {
  Contract(is_ast_region_spec(ast));
  EXTRACT_OPTION(type, ast->right);
  bool_t is_private = (type == PRIVATE_REGION);

  gen_name(CS, ast->left);
  if (is_private) {
    gen_printf(CS, " PRIVATE");
  }
}

static void gen_region_list(CqlState* CS, ast_node *ast) {
  Contract(is_ast_region_list(ast));
  while (ast) {
    gen_region_spec(CS, ast->left);
    if (ast->right) {
      gen_printf(CS, ", ");
    }
    ast = ast->right;
  }
}

static void gen_declare_deployable_region_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_deployable_region_stmt(ast));
  gen_printf(CS, "@DECLARE_DEPLOYABLE_REGION ");
  gen_name(CS, ast->left);
  if (ast->right) {
    gen_printf(CS, " USING ");
    gen_region_list(CS, ast->right);
  }
}

static void gen_declare_schema_region_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_declare_schema_region_stmt(ast));
  gen_printf(CS, "@DECLARE_SCHEMA_REGION ");
  gen_name(CS, ast->left);
  if (ast->right) {
    gen_printf(CS, " USING ");
    gen_region_list(CS, ast->right);
  }
}

static void gen_begin_schema_region_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_begin_schema_region_stmt(ast));
  gen_printf(CS, "@BEGIN_SCHEMA_REGION ");
  gen_name(CS, ast->left);
}

static void gen_end_schema_region_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_end_schema_region_stmt(ast));
  gen_printf(CS, "@END_SCHEMA_REGION");
}

static void gen_schema_unsub_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_schema_unsub_stmt(ast));
  EXTRACT_NOTNULL(version_annotation, ast->left);
  EXTRACT_NAME_AST(name_ast, version_annotation->right);

  gen_printf(CS, "@UNSUB(");
  gen_name(CS, name_ast);
  gen_printf(CS, ")");
}

static void gen_schema_ad_hoc_migration_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_schema_ad_hoc_migration_stmt(ast));
  EXTRACT_ANY_NOTNULL(l, ast->left);
  EXTRACT_ANY(r, ast->right);

  // two arg version is a recreate upgrade instruction
  if (r) {
    EXTRACT_STRING(group, l);
    EXTRACT_STRING(proc, r);
    gen_printf(CS, "@SCHEMA_AD_HOC_MIGRATION FOR @RECREATE(");
    gen_printf(CS, "%s, %s)", group, proc);
  }
  else {
    gen_printf(CS, "@SCHEMA_AD_HOC_MIGRATION(");
    gen_version_and_proc(CS, l);
    gen_printf(CS, ")");
  }
}

static void gen_emit_group_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_emit_group_stmt(ast));
  EXTRACT(name_list, ast->left);

  gen_printf(CS, "@EMIT_GROUP");
  if (name_list) {
    gen_printf(CS, " ");
    gen_name_list(CS, name_list);
  }
}


static void gen_emit_enums_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_emit_enums_stmt(ast));
  EXTRACT(name_list, ast->left);

  gen_printf(CS, "@EMIT_ENUMS");
  if (name_list) {
    gen_printf(CS, " ");
    gen_name_list(CS, name_list);
  }
}

static void gen_emit_constants_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_emit_constants_stmt(ast));
  EXTRACT_NOTNULL(name_list, ast->left);

  gen_printf(CS, "@EMIT_CONSTANTS ");
  gen_name_list(CS, name_list);
}

static void gen_conflict_target(CqlState* CS, ast_node *ast) {
  Contract(is_ast_conflict_target(ast));
  EXTRACT(indexed_columns, ast->left);
  EXTRACT(opt_where, ast->right);

  gen_printf(CS, "\nON CONFLICT ");
  if (indexed_columns) {
    gen_printf(CS, "(");
    gen_indexed_columns(CS, indexed_columns);
    gen_printf(CS, ") ");
  }
  if (opt_where) {
    gen_printf(CS, "\n");
    gen_opt_where(CS, opt_where);
    gen_printf(CS, " ");
  }
}

static void gen_upsert_update(CqlState* CS, ast_node *ast) {
  Contract(is_ast_upsert_update(ast));
  EXTRACT_NOTNULL(conflict_target, ast->left);
  EXTRACT(update_stmt, ast->right);

  gen_conflict_target(CS, conflict_target);
  gen_printf(CS, "DO ");
  if (update_stmt) {
    gen_update_stmt(CS, update_stmt);
  } else {
    gen_printf(CS, "NOTHING");
  }
}

static void gen_upsert_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_upsert_stmt(ast));

  EXTRACT_NOTNULL(insert_stmt, ast->left);
  EXTRACT_NOTNULL(upsert_update, ast->right);

  gen_insert_stmt(CS, insert_stmt);
  gen_upsert_update(CS, upsert_update);
}

static void gen_with_upsert_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_with_upsert_stmt(ast));
  EXTRACT_ANY_NOTNULL(with_prefix, ast->left)
  EXTRACT_NOTNULL(upsert_stmt, ast->right);

  gen_with_prefix(CS, with_prefix);
  gen_upsert_stmt(CS, upsert_stmt);
}

static void gen_blob_get_key_type_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_get_key_type_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "@BLOB_GET_KEY_TYPE %s", name);
}

static void gen_blob_get_val_type_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_get_val_type_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  gen_printf(CS, "@BLOB_GET_VAL_TYPE %s", name);
}

static void gen_blob_get_key_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_get_key_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_GET_KEY %s%s", name, offset ? " OFFSET" : "");
}

static void gen_blob_get_val_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_get_val_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_GET_VAL %s%s", name, offset ? " OFFSET" : "");
}

static void gen_blob_create_key_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_create_key_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_CREATE_KEY %s%s", name, offset ? " OFFSET" : "");
}

static void gen_blob_create_val_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_create_val_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_CREATE_VAL %s%s", name, offset ? " OFFSET" : "");
}

static void gen_blob_update_key_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_update_key_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_UPDATE_KEY %s%s", name, offset ? " OFFSET" : "");
}

static void gen_blob_update_val_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_blob_update_val_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_OPTION(offset, ast->right);

  gen_printf(CS, "@BLOB_UPDATE_VAL %s%s", name, offset ? " OFFSET" : "");
}

static void gen_keep_table_name_in_aliases_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_keep_table_name_in_aliases_stmt(ast));
  gen_printf(CS, "@KEEP_TABLE_NAME_IN_ALIASES");
}

static void gen_explain_stmt(CqlState* CS, ast_node *ast) {
  Contract(is_ast_explain_stmt(ast));
  EXTRACT_OPTION(query_plan, ast->left);
  EXTRACT_ANY_NOTNULL(stmt_target, ast->right);

  gen_printf(CS, "EXPLAIN");
  if (query_plan == EXPLAIN_QUERY_PLAN) {
    gen_printf(CS, " QUERY PLAN");
  }
  gen_printf(CS, "\n");
  gen_one_stmt(CS, stmt_target);
}

static void gen_macro_formal(CqlState* CS, ast_node *macro_formal) {
  Contract(is_ast_macro_formal(macro_formal));
  EXTRACT_STRING(l, macro_formal->left);
  EXTRACT_STRING(r, macro_formal->right);
  gen_printf(CS, "%s! %s", l, r);
}

static void gen_macro_formals(CqlState* CS, ast_node *macro_formals) {
  for ( ; macro_formals; macro_formals = macro_formals->right) {
     Contract(is_ast_macro_formals(macro_formals));
     gen_macro_formal(CS, macro_formals->left);
     if (macro_formals->right) {
       gen_printf(CS, ", ");
     }
  }
}

static void gen_expr_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_expr_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(EXPR) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_root_expr(CS, body);
  GEN_END_INDENT(body_indent);
  gen_printf(CS, "\nEND");
}

static void gen_stmt_list_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_stmt_list_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(STMT_LIST) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  gen_stmt_list(CS, body);
  gen_printf(CS, "END");
}

static void gen_select_core_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_core_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(SELECT_CORE) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_select_core_list(CS, body);
  GEN_END_INDENT(body_indent);
  gen_printf(CS, "\nEND");
}

static void gen_select_expr_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_select_expr_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(SELECT_EXPR) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_select_expr_list(CS, body);
  GEN_END_INDENT(body_indent);
  gen_printf(CS, "\nEND");
}

static void gen_query_parts_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_query_parts_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(QUERY_PARTS) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_query_parts(CS, body);
  GEN_END_INDENT(body_indent);
  gen_printf(CS, "\nEND");
}

static void gen_cte_tables_macro_def(CqlState* CS, ast_node *ast) {
  Contract(is_ast_cte_tables_macro_def(ast));
  EXTRACT_NOTNULL(macro_name_formals, ast->left);
  EXTRACT_ANY_NOTNULL(body, ast->right);
  EXTRACT_STRING(name, macro_name_formals->left);

  gen_printf(CS, "@MACRO(CTE_TABLES) %s!(", name);
  gen_macro_formals(CS, macro_name_formals->right);
  gen_printf(CS, ")\nBEGIN\n");
  GEN_BEGIN_INDENT(body_indent, 2);
    gen_cte_tables(CS, body, "");
  GEN_END_INDENT(body_indent);
  gen_printf(CS, "END");
}

static void gen_stmt_list_macro_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_stmt_list_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s(", name);
  gen_macro_args(CS, ast->right);
  gen_printf(CS, ")");
}

static void gen_stmt_list_macro_arg_ref(CqlState* CS, ast_node *ast) {
  Contract(is_ast_stmt_list_macro_arg_ref(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf(CS, "%s", name);
}

//cql_data_defn( int32_t gen_stmt_level );

static void gen_stmt_list(CqlState* CS, ast_node *root) {
  if (!root) {
    return;
  }

  CS->gen_stmt_level++;

  int32_t indent_level = (CS->gen_stmt_level > 1) ? 2 : 0;

  GEN_BEGIN_INDENT(statement, indent_level);

  bool first_stmt = true;

  for (ast_node *semi = root; semi; semi = semi->right) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, semi);
    if (misc_attrs) {
      // do not echo declarations that came from the builtin stream
      if (exists_attribute_str(CS, misc_attrs, "builtin")) {
        continue;
      }
    }

    if (CS->gen_stmt_level == 1 && !first_stmt) {
      gen_printf(CS, "\n");
    }

    first_stmt = false;

    if (misc_attrs) {
      gen_misc_attrs(CS, misc_attrs);
    }
    gen_one_stmt(CS, stmt);

    if (CS->gen_stmt_level == 0 && semi->right == NULL) {
      gen_printf(CS, ";");
    }
    else {
      gen_printf(CS, ";\n");
    }
  }

  GEN_END_INDENT(statement);
  CS->gen_stmt_level--;
}

cql_noexport void gen_one_stmt(CqlState* CS, ast_node *stmt)  {
  symtab_entry *entry = symtab_find(CS->gen_stmts, stmt->type);

  // These are all the statements there are, we have to find it in this table
  // or else someone added a new statement and it isn't supported yet.
  Invariant(entry);
  ((AstGenOneStmt)entry->val)(CS, stmt);
}

cql_noexport void gen_one_stmt_and_misc_attrs(CqlState* CS, ast_node *stmt)  {
  EXTRACT_MISC_ATTRS(stmt, misc_attrs);
  if (misc_attrs) {
    gen_misc_attrs(CS, misc_attrs);
  }
  gen_one_stmt(CS, stmt);
}

// so the name doesn't otherwise conflict in the amalgam
#undef output

static bool_t symtab_add_sql_expr_dispatch_func(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull sym_new, gen_expr_dispatch _Nullable *val_new)
{
    return symtab_add(CS, syms, sym_new, val_new);
}

#undef STMT_INIT
#define STMT_INIT(x) symtab_add_GenOneStmt(CS, CS->gen_stmts, k_ast_ ## x, gen_ ## x)

#undef EXPR_INIT
#define EXPR_INIT(x, func, str, pri_new) \
  static gen_expr_dispatch expr_disp_ ## x = { func, str, pri_new }; \
  symtab_add_sql_expr_dispatch_func(CS, CS->gen_exprs, k_ast_ ## x, &expr_disp_ ## x);

cql_noexport void gen_init(CqlState* CS) {
  CS->gen_stmts = symtab_new();
  CS->gen_exprs = symtab_new();

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
  STMT_INIT(fetch_cursor_from_blob_stmt);
  STMT_INIT(fetch_stmt);
  STMT_INIT(fetch_values_stmt);
  STMT_INIT(guard_stmt);
  STMT_INIT(if_stmt);
  STMT_INIT(insert_stmt);
  STMT_INIT(leave_stmt);
  STMT_INIT(let_stmt);
  STMT_INIT(loop_stmt);
  STMT_INIT(stmt_list_macro_def);
  STMT_INIT(expr_macro_def);
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
  STMT_INIT(set_blob_from_cursor_stmt);
  STMT_INIT(set_from_cursor);
  STMT_INIT(stmt_list_macro_arg_ref);
  STMT_INIT(stmt_list_macro_ref);
  STMT_INIT(switch_stmt);
  STMT_INIT(throw_stmt);
  STMT_INIT(trycatch_stmt);
  STMT_INIT(update_cursor_stmt);
  STMT_INIT(update_stmt);
  STMT_INIT(upsert_stmt);
  STMT_INIT(upsert_update);
  STMT_INIT(while_stmt);
  STMT_INIT(with_delete_stmt);
  STMT_INIT(with_insert_stmt);
  STMT_INIT(with_select_stmt);
  STMT_INIT(with_update_stmt);
  STMT_INIT(with_upsert_stmt);

  STMT_INIT(blob_get_key_type_stmt);
  STMT_INIT(blob_get_val_type_stmt);
  STMT_INIT(blob_get_key_stmt);
  STMT_INIT(blob_get_val_stmt);
  STMT_INIT(blob_create_key_stmt);
  STMT_INIT(blob_create_val_stmt);
  STMT_INIT(blob_update_key_stmt);
  STMT_INIT(blob_update_val_stmt);

  STMT_INIT(keep_table_name_in_aliases_stmt);

  EXPR_INIT(table_star, gen_expr_table_star, "T.*", EXPR_PRI_ROOT);
  EXPR_INIT(at_id, gen_expr_at_id, "@ID", EXPR_PRI_ROOT);
  EXPR_INIT(star, gen_expr_star, "*", EXPR_PRI_ROOT);
  EXPR_INIT(num, gen_expr_num, "NUM", EXPR_PRI_ROOT);
  EXPR_INIT(str, gen_expr_str, "STR", EXPR_PRI_ROOT);
  EXPR_INIT(blob, gen_expr_blob, "BLB", EXPR_PRI_ROOT);
  EXPR_INIT(null, gen_expr_null, "NULL", EXPR_PRI_ROOT);
  EXPR_INIT(dot, gen_expr_dot, ".", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(expr_macro_arg_ref, gen_expr_macro_arg_ref, "!", EXPR_PRI_ROOT);
  EXPR_INIT(expr_macro_ref, gen_expr_macro_ref, "!", EXPR_PRI_ROOT);
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
  EXPR_INIT(select_if_nothing_throw_expr, gen_expr_select_if_nothing_throw, "IF NOTHING THROW", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_expr, gen_expr_select_if_nothing, "IF NOTHING", EXPR_PRI_ROOT);
  EXPR_INIT(select_if_nothing_or_null_expr, gen_expr_select_if_nothing, "IF NOTHING OR NULL", EXPR_PRI_ROOT);
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
  EXPR_INIT(reverse_apply, gen_binary_no_spaces, ":", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(reverse_apply_typed, gen_binary_no_spaces, "::", EXPR_PRI_REVERSE_APPLY);
  EXPR_INIT(reverse_apply_poly, gen_binary_no_spaces, ":::", EXPR_PRI_REVERSE_APPLY);
}

cql_export void gen_cleanup(CqlState* CS) {
  SYMTAB_CLEANUP(CS->gen_stmts);
  SYMTAB_CLEANUP(CS->gen_exprs);
  CS->gen_output = NULL;
  gen_callbacks_lv = NULL;
  CS->used_alias_syms = NULL;
}

#endif
