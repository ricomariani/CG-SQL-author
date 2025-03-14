/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_JSON)

// stubs to avoid link errors
cql_noexport void cg_json_schema_main(ast_node *head) {}

#else

// Perform codegen of the various nodes to json schema format

#include "cg_json_schema.h"
#include <stdio.h>

#include "ast.h"
#include "cg_common.h"
#include "charbuf.h"
#include "cql.h"
#include "gen_sql.h"
#include "list.h"
#include "sem.h"
#include "symtab.h"
#include "encoders.h"
#include "eval.h"

static void cg_fragment_with_params(charbuf *output, CSTR frag, ast_node *ast, gen_func fn);
static void cg_fragment_with_params_raw(charbuf *output, CSTR frag, ast_node *ast, gen_func fn);
static void cg_json_fk_target_options(charbuf *output, ast_node *ast);
static void cg_json_emit_region_info(charbuf *output, ast_node *ast);
static void cg_json_dependencies(charbuf *output, ast_node *ast);
static void cg_json_data_type(charbuf *output, sem_t sem_type, CSTR kind);

// These little helpers are for handling comma seperated lists where you may or may
// not need a comma in various places.  The local tracks if there is an item already
// present and you either get ",\n"  or just "\n" as needed.
#define BEGIN_LIST bool_t list_start = 1
#define CONTINUE_LIST bool_t list_start = 0
#define COMMA if (!list_start) bprintf(output, ",\n"); else list_start = 0
#define END_LIST if (!list_start) bprintf(output, "\n")

// These are the main output buffers for the various forms of statements we support
// we build these up as we encounter them, redirecting the local 'output' to one of these
static charbuf *queries;
static charbuf *deletes;
static charbuf *inserts;
static charbuf *updates;
static charbuf *general;
static charbuf *general_inserts;

// We use this to track every table we've ever seen and we remember what stored procedures use it
static symtab *tables_to_procs;

// The callback function for dependency analysis gets this structure as the anonymous context
typedef struct json_context {
  CSTR cookie;
  ast_node *proc_ast;
  charbuf *used_tables;
  charbuf *used_views;
  charbuf *insert_tables;
  charbuf *update_tables;
  charbuf *delete_tables;
  charbuf *from_tables;
  charbuf *used_procs;
} json_context;

// magic string to sanity check the context cuz we're paranoid
static char cookie_str[] = "cookie";

// compute the CRC for an arbitrary statement
static llint_t crc_stmt(ast_node *stmt) {
  CHARBUF_OPEN(temp);

  // Format the text with full annotations, this text isn't going to SQLite but it should capture
  // all aspects of the table/view/index/trigger including annotations.
  gen_sql_callbacks callbacks;
  init_gen_sql_callbacks(&callbacks);
  gen_set_output_buffer(&temp);
  gen_statement_with_callbacks(stmt, &callbacks);
  llint_t result = (llint_t)crc_charbuf(&temp);

  CHARBUF_CLOSE(temp);
  return result;
}

// emit either a normal name or quoted name into the output stream
// If the name is a qid `like so` we have to "unquote" it before we emit it
// This means converting the hex form to normal ascii including and then
// requoting it for json with the appropriate escape sequences.
static void cg_json_sql_name_ex(charbuf *output, CSTR name, bool qid) {
  if (qid) {
    CHARBUF_OPEN(sql_name);
    cg_unquote_encoded_qstr(&sql_name, name);
    cg_pretty_quote_plaintext(sql_name.ptr, output, PRETTY_QUOTE_JSON | PRETTY_QUOTE_SINGLE_LINE);
    CHARBUF_CLOSE(sql_name);
  }
  else {
    bprintf(output, "\"%s\"", name);
  }
}

// This is a helper function to emit a name into the JSON output stream.
// The origin is a structure member.
// The name is either a quoted identifier or a plain identifier.
// The quoted identifier info comes from the semantic type on the column.
static void cg_json_sptr_sql_name(charbuf *output, sem_struct *sptr, int32_t i) {
  CSTR name = sptr->names[i];
  cg_json_sql_name_ex(output, name, !!(sptr->semtypes[i] & SEM_TYPE_QID));
}

// This is a helper function to emit a name into the JSON output stream.
// The origin is an ast node
// The name is either a quoted identifier or a plain identifier.
// The quoted identifier info comes from the semantic type ast node
static void cg_json_sql_name(charbuf *output, ast_node *ast) {
  EXTRACT_STRING(name, ast);
  cg_json_sql_name_ex(output, name, is_qid(ast));
}

// This is a helper function to emit a name into the JSON output stream.
// We use the sql name helper above to emit the name and we add commas as needed
// so here we're building a list.
static void add_name_to_output(charbuf* output, ast_node *ast) {
  Contract(output);
  ast_node *name_ast = sem_get_name_ast(ast);
  if (output->used > 1) {
    bprintf(output, ", ");
  }
  cg_json_sql_name(output, name_ast);
}

// This is the callback function that tells us a view name was found in the body
// of the stored proc we are currently examining.  The void context information
// is how we remember which proc we were processing.   For each table we have
// a character buffer.  We look it up, create it if not present, and write into it.
// We also write into the buffer for the current proc which came in with the context.
static void cg_found_view(CSTR view_name, ast_node *name_ast, void* pvContext) {
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check
  Contract(context->used_views);

  add_name_to_output(context->used_views, name_ast);
}

// This is the callback function that tells us a table name was found in the body
// of the stored proc we are currently examining.  The void context information
// is how we remember which proc we were processing.   For each table we have
// a character buffer.  We look it up, create it if not present, and write into it.
// We also write into the buffer for the current proc which came in with the context.
static void cg_found_table(CSTR table_name, ast_node *table_ast, void* pvContext) {
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check
  Contract(context->used_tables);

  ast_node *proc_ast = context->proc_ast;

  if (is_ast_create_proc_stmt(proc_ast)) {
    Contract(tables_to_procs);

    charbuf* output = symtab_ensure_charbuf(tables_to_procs, table_name);

    // Get the proc name and add it to the list for this table
    add_name_to_output(output, proc_ast);
  }

  add_name_to_output(context->used_tables, table_ast);
}

// we found a table that is used in an insert context, add it to the list
// this is part of the dependency analysis
static void cg_found_insert(CSTR table_name, ast_node *table_ast, void *pvContext)
{
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check

  add_name_to_output(context->insert_tables, table_ast);
}

// we found a table that is used in an update context, add it to the list
// this is part of the dependency analysis
static void cg_found_update(CSTR table_name, ast_node *table_ast, void *pvContext)
{
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check

  add_name_to_output(context->update_tables, table_ast);
}

// we found a table that is used in an delete context, add it to the list
// this is part of the dependency analysis
static void cg_found_delete(CSTR table_name, ast_node *table_ast, void *pvContext)
{
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check

  add_name_to_output(context->delete_tables, table_ast);
}

// we found a table that is used in an "from" context, add it to the list
// this is part of the dependency analysis
static void cg_found_from(CSTR table_name, ast_node *table_ast, void *pvContext)
{
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check
  add_name_to_output(context->from_tables, table_ast);
}

// we found a procedure, add it to the list
// this is part of the dependency analysis
static void cg_found_proc(CSTR proc_name, ast_node *name_ast, void *pvContext)
{
  json_context *context = (json_context *)pvContext;
  Contract(context->cookie == cookie_str);  // sanity check
  add_name_to_output(context->used_procs, name_ast);
}

// When processing generated SQL we get a callback every time a variable appears
// in the output stream.  This method records the variable name for use later
// in the _parameters array.
static bool_t cg_json_record_var(struct ast_node *_Nonnull ast, void *_Nullable context, charbuf *_Nonnull output) {
  // If this invariant fails that means the code is using cg_fragment when
  // cg_fragment_with_params is required (because variables were used).
  Invariant(context);
  charbuf *var = (charbuf *)context;

  bprintf(output, "?");
  if (var->used > 1) {
    bprintf(var, ", ");
  }
  bprintf(var, "\"%s\"", ast->sem->name);
  return true;
}

// In test mode the JSON output is contaminated with test info so that we can
// tell where the output came from.  This allows us to use the normal verifier
// to match JSON fragments.
static void cg_json_test_details(charbuf *output, ast_node *ast, ast_node *misc_attrs) {
  if (options.test) {
    bprintf(output, "\nThe statement ending at line %d\n", ast->lineno);
    bprintf(output, "\n");

    gen_set_output_buffer(output);
    if (misc_attrs) {
      gen_with_callbacks(misc_attrs, gen_misc_attrs, NULL);
    }
    gen_with_callbacks(ast, gen_one_stmt, NULL);
    bprintf(output, "\n\n");
  }
}

// Just extract a name from the AST and emit it
static void cg_json_name(charbuf *output, ast_node *ast) {
  EXTRACT_STRING(name, ast);
  bprintf(output, "%s", name);
}

// Emit a quoted string into the JSON
static void cg_json_emit_string(charbuf *output, ast_node *ast) {
  Invariant(is_strlit(ast));
  EXTRACT_STRING(str, ast);

  // note str is the lexeme, so it is still quoted and escaped
  CHARBUF_OPEN(str1);
  CHARBUF_OPEN(str2);
  // requote it as a c style literal
  cg_decode_string_literal(str, &str1);
  cg_encode_json_string_literal(str1.ptr, &str2);
  bprintf(output, "%s", str2.ptr);
  CHARBUF_CLOSE(str2);
  CHARBUF_CLOSE(str1);
}

// Emit out a single miscellaneous attribute value into the current output stream
// We could be processing any kind of entity, we don't care.  We're just
// emitting a single value here.  The legal values are:
// * a list of nested values
// * an integer literal
// * a double literal
// * a string literal
// * a name
// * a quoted name `foo bar`
// * null
// String literals have to be unescaped from SQL format and reescaped into C format
static void cg_json_attr_value(charbuf *output, ast_node *ast) {
  if (is_ast_misc_attr_value_list(ast)) {
    bprintf(output, "[");
    for (ast_node *item = ast; item; item = item->right) {
      cg_json_attr_value(output, item->left);
      if (item->right) {
        bprintf(output, ", ");
      }
    }
    bprintf(output, "]");
  }
  else if (is_ast_str(ast)) {
    EXTRACT_STRING(str, ast);

    if (is_strlit(ast)) {
      cg_json_emit_string(output, ast);
    }
    else {
      // an identifier or QID
      cg_json_sql_name_ex(output, str, is_qid(ast));
    }
  }
  else if (is_ast_null(ast)) {
    // Null must be all in lowercase to be valid json, so we need a special case
    bprintf(output, "null");
  }
  else {
    gen_set_output_buffer(output);
    gen_sql_callbacks callbacks;
    init_gen_sql_callbacks(&callbacks);
    callbacks.mode = gen_mode_sql;
    callbacks.convert_hex = true;  // json doesn't support hex numbers
    gen_with_callbacks(ast, gen_root_expr, &callbacks);
  }
}

// Emit a single miscellaneous attribute name/value pair
// The name could be of the form foo:bar in which case we emit foo_bar
// The value is any of the legal values handled above in cg_json_attr_value.
static void cg_json_misc_attr(charbuf *output, ast_node *ast) {
  Contract(is_ast_misc_attr(ast));
  bprintf(output, "{\n");
  BEGIN_INDENT(attr, 2);
  bprintf(output, "\"name\" : \"");
  if (is_ast_dot(ast->left)) {
    cg_json_name(output, ast->left->left);
    bprintf(output, ":");
    cg_json_name(output, ast->left->right);
  }
  else {
    cg_json_name(output, ast->left);
  }
  bprintf(output, "\",\n\"value\" : ");
  if (ast->right) {
    cg_json_attr_value(output, ast->right);
  }
  else {
    bprintf(output, "1");
  }
  END_INDENT(attr);
  bprintf(output, "\n}");
}

// Emit a list of attributes for the current entity, it could be any kind of entity.
// Whatever it is we spit out the attributes here in array format.
static void cg_json_misc_attrs(charbuf *output, ast_node *_Nonnull list) {
  Contract(is_ast_misc_attrs(list));
  bprintf(output, "\"attributes\" : [\n");
  BEGIN_INDENT(attr, 2);
  BEGIN_LIST;

  for (ast_node *item = list; item; item = item->right) {
    COMMA;
    cg_json_misc_attr(output, item->left);
  }
  END_LIST;
  END_INDENT(attr);
  bprintf(output, "]");
}

// The column has its definition and attributes, output for the column goes
// into the direct output and maybe to the deferred outputs.  For instance if
// a column in an FK then is FKness is emitted into the fk buffer for later use
// in the fk section.
typedef struct col_info {
  // Inputs
  ast_node *def;
  ast_node *attrs;
  bool_t is_backed;  // true if the table we're emitting is backed

  // We write to these
  charbuf *col_pk;
  charbuf *col_uk;
  charbuf *col_fk;
} col_info;


static void cg_json_default_value(charbuf *output, ast_node *def) {
  if (is_ast_uminus(def)) {
    def = def->left;
    bprintf(output, "-");
  }
  cg_json_attr_value(output, def);
}

// Emits the JSON for all ad-hoc migration procs as a list
static void cg_json_ad_hoc_migration_procs(charbuf* output) {
  bprintf(output, "\"adHocMigrationProcs\" : [\n");
  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  for (list_item *item = all_ad_hoc_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_schema_ad_hoc_migration_stmt(ast));

    EXTRACT(version_annotation, ast->left);
    EXTRACT_OPTION(version, version_annotation->left);
    EXTRACT_STRING(name, version_annotation->right);

    ast_node *misc_attrs = NULL;
    ast_node *attr_target = ast->parent;
    if (is_ast_stmt_and_attr(attr_target)) {
      EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
      misc_attrs = misc;
    }

    cg_json_test_details(output, ast, misc_attrs);

    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(t, 2);
    bprintf(output, "\"name\" : \"%s\",\n", name);
    bprintf(output, "\"CRC\" : \"%lld\",\n", crc_stmt(ast));

    if (misc_attrs) {
      cg_json_misc_attrs(output, misc_attrs);
      bprintf(output, ",\n");
    }

    bprintf(output, "\"version\" : %d", version);
    END_INDENT(t);
    bprintf(output, "\n}");
  }

  uint32_t count = ad_hoc_recreate_actions->count;
  symtab_entry *actions = symtab_copy_sorted_payload(ad_hoc_recreate_actions, default_symtab_comparator);

  for (uint32_t i = 0; i < count; i++) {
    ast_node *ast = (ast_node *)actions[i].val;
    EXTRACT_STRING(group, ast->left);
    EXTRACT_STRING(proc, ast->right);

    ast_node *misc_attrs = NULL;
    ast_node *attr_target = ast->parent;
    if (is_ast_stmt_and_attr(attr_target)) {
      EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
      misc_attrs = misc;
    }

    cg_json_test_details(output, ast, misc_attrs);

    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(t, 2);
    bprintf(output, "\"name\" : \"%s\",\n", proc);
    bprintf(output, "\"CRC\" : \"%lld\",\n", crc_stmt(ast));

    if (misc_attrs) {
      cg_json_misc_attrs(output, misc_attrs);
      bprintf(output, ",\n");
    }

    bprintf(output, "\"onRecreateOf\" : \"%s\"", group);
    END_INDENT(t);
    bprintf(output, "\n}");
  }
  free(actions);

  END_LIST;
  END_INDENT(list);
  bprintf(output, "]");
}

// Emits the name and value for each value in the enumeration
static void cg_json_enum_values(ast_node *enum_values, charbuf *output) {
  Contract(is_ast_enum_values(enum_values));

  bprintf(output, "\"values\" : [\n");

  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  while (enum_values) {
     EXTRACT_NOTNULL(enum_value, enum_values->left);
     EXTRACT_NAME_AST(enum_name_ast, enum_value->left);
     EXTRACT_STRING(enum_name, enum_name_ast);

     COMMA;
     bprintf(output, "{\n");

     bprintf(output, "  \"name\" : \"%s\",\n", enum_name);
     bprintf(output, "  \"value\" : ");
     eval_format_number(enum_name_ast->sem->value, EVAL_FORMAT_NORMAL, output);
     bprintf(output, "\n}");

     enum_values = enum_values->right;
  }

  END_LIST;
  END_INDENT(list);

  bprintf(output, "]\n");
}

// Emits the JSON for all enumerations
static void cg_json_enums(charbuf* output) {
  bprintf(output, "\"enums\" : [\n");
  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  for (list_item *item = all_enums_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_declare_enum_stmt(ast));
    EXTRACT_NOTNULL(typed_name, ast->left);
    EXTRACT_NOTNULL(enum_values, ast->right);
    EXTRACT_ANY(name_ast, typed_name->left);
    EXTRACT_STRING(name, name_ast);
    EXTRACT_ANY_NOTNULL(type, typed_name->right);

    cg_json_test_details(output, ast, NULL);

    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(t, 2);
    bprintf(output, "\"name\" : \"%s\",\n", name);
    cg_json_data_type(output, type->sem->sem_type | SEM_TYPE_NOTNULL, NULL);
    bprintf(output, ",\n");

    cg_json_enum_values(enum_values, output);

    END_INDENT(t);
    bprintf(output, "}");
  }

  END_LIST;
  END_INDENT(list);
  bprintf(output, "]");
}

// emits the type and value for each constant in the constant group
static void cg_json_const_values(ast_node *const_values, charbuf *output) {
  Contract(is_ast_const_values(const_values));

  bprintf(output, "\"values\" : [\n");

  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  while (const_values) {
    EXTRACT_NOTNULL(const_value, const_values->left);
    EXTRACT_NAME_AST(const_name_ast, const_value->left);
    EXTRACT_STRING(const_name, const_name_ast);
    EXTRACT_ANY_NOTNULL(const_expr, const_value->right);

    COMMA;
    bprintf(output, "{\n");

    bprintf(output, "  \"name\" : \"%s\",\n", const_name);
    BEGIN_INDENT(type, 2);
      cg_json_data_type(output, const_expr->sem->sem_type, const_expr->sem->kind);
    END_INDENT(type);
    bprintf(output, ",\n");
    bprintf(output, "  \"value\" : ");

    if (is_strlit(const_expr)) {
      cg_json_emit_string(output, const_expr);
    }
    else {
      eval_format_number(const_expr->sem->value, EVAL_FORMAT_NORMAL, output);
    }

    bprintf(output, "\n}");

    const_values = const_values->right;
  }

  END_LIST;
  END_INDENT(list);

  bprintf(output, "]\n");
}

// Emits the JSON for all the global constants
// note that these are in groups for convenience but they are all global
// scope, not like enums.
static void cg_json_constant_groups(charbuf* output) {
  bprintf(output, "\"constantGroups\" : [\n");
  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  for (list_item *item = all_constant_groups_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_declare_const_stmt(ast));
    EXTRACT_NAME_AST(name_ast, ast->left);
    EXTRACT_NOTNULL(const_values, ast->right);
    EXTRACT_STRING(name, name_ast);

    cg_json_test_details(output, ast, NULL);

    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(t, 2);
    bprintf(output, "\"name\" : \"%s\",\n", name);

    cg_json_const_values(const_values, output);

    END_INDENT(t);
    bprintf(output, "}");
  }

  END_LIST;
  END_INDENT(list);
  bprintf(output, "]");
}

// Emits the JSON for all the unsubscription directives
static void cg_json_subscriptions(charbuf* output) {
  bprintf(output, "\"subscriptions\" : [\n");
  BEGIN_INDENT(list, 2);
  BEGIN_LIST;

  for (list_item *item = all_subscriptions_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_schema_unsub_stmt(ast));

    EXTRACT_NOTNULL(version_annotation, ast->left);
    EXTRACT_OPTION(vers, version_annotation->left);
    EXTRACT_STRING(name, version_annotation->right);
    CSTR region = ast->sem->region;

    cg_json_test_details(output, ast, NULL);

    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(t, 2);
    bprintf(output, "\"type\" : \"unsub\",\n");
    bprintf(output, "\"table\" : \"%s\"", name);
    if (region) {
      cg_json_emit_region_info(output, ast);
    }
    bprintf(output, ",\n\"version\" : %d\n", vers);
    END_INDENT(t);
    bprintf(output, "}");
  }

  END_LIST;
  END_INDENT(list);
  bprintf(output, "]");
}

// Emits a migration procedure name into the output
// it can be a vanilla name or it can be a dot name, i.e. foo.bar.
// The dot name is emitted into the json as "foo:bar".  These are
// "special" builting migration notes. The canonical one is
// cql:from_recreate which indicates a table transitioned
// to normal schema from recreate schema.
static void cg_migration_proc(ast_node *ast, charbuf *output) {
  if (is_ast_dot(ast)) {
    EXTRACT_NOTNULL(dot, ast);
    EXTRACT_STRING(lhs, dot->left);
    EXTRACT_STRING(rhs, dot->right);
    bprintf(output,"\"%s:%s\"", lhs, rhs);
  }
  else {
    EXTRACT_STRING(migration_proc_name, ast);
    bprintf(output,"\"%s\"", migration_proc_name);
  }
}

// Searches for an "ast_create" node from a list and emits the name of the migration
// proc associated with it, if any
static void cg_json_added_migration_proc(charbuf *output, ast_node *list) {
  for (ast_node *attr = list; attr; attr = attr->right) {
    if (is_ast_create_attr(attr)){
      EXTRACT(version_annotation, attr->left);
      if (version_annotation && version_annotation->right) {
        bprintf(output,",\n\"addedMigrationProc\" : ");
        cg_migration_proc(version_annotation->right, output);
      }
    }
  }
}

// Searches for an "ast_delete" node from a list and emits the name of the migration
// proc associated with it, if any
static void cg_json_deleted_migration_proc(charbuf *output, ast_node *list) {
  for (ast_node *attr = list; attr; attr = attr->right) {
    if (is_ast_delete_attr(attr)){
      EXTRACT(version_annotation, attr->left);
      if (version_annotation && version_annotation->right) {
        bprintf(output,",\n\"deletedMigrationProc\" : ");
        cg_migration_proc(version_annotation->right, output);
      }
    }
  }
}

// Crack the semantic info for the column and emit that into the main output
// examine the attributes and emit those as needed.
static void cg_json_col_attrs(charbuf *output, col_info *info) {
  // most of the attributes are in the semantic type, we don't have to walk the tree for them
  // we do need to check for a default value.
  // Note that there are implications associated with this flags and semantic analysis
  // makes those conclusions (e.g. pk implies not null)
  // We don't want that logic again so we use the semantic type not the raw declaration

  ast_node *col = info->def;

  sem_t sem_type = col->sem->sem_type;
  CSTR name = col->sem->name;

  bool_t is_added = col->sem->create_version > 0;
  bool_t is_deleted = col->sem->delete_version > 0;
  bprintf(output, ",\n\"isAdded\" : %d", is_added);
  if (is_added) {
    bprintf(output, ",\n\"addedVersion\" : %d", col->sem->create_version);
    cg_json_added_migration_proc(output, info->attrs);
  }
  bprintf(output, ",\n\"isDeleted\" : %d", is_deleted);
  if (is_deleted) {
    bprintf(output, ",\n\"deletedVersion\" : %d", col->sem->delete_version);
    cg_json_deleted_migration_proc(output, info->attrs);
  }

  if (sem_type & SEM_TYPE_PK) {
    cg_json_sql_name_ex(info->col_pk, name, !!(sem_type & SEM_TYPE_QID));
  }

  if (sem_type & SEM_TYPE_UK) {
    if (info->col_uk->used > 1) {
      bprintf(info->col_uk, ",\n");
    }
    CHARBUF_OPEN(tmp);
    bprintf(&tmp, "%s_uk", name);
    bool_t is_qid = !!(sem_type & SEM_TYPE_QID);

    bprintf(info->col_uk, "{\n");
    bprintf(info->col_uk, "  \"name\" : ");
    cg_json_sql_name_ex(info->col_uk, tmp.ptr, is_qid);
    bprintf(info->col_uk, ",\n");
    bprintf(info->col_uk, "  \"columns\" : [ ");
    cg_json_sql_name_ex(info->col_uk, name, is_qid);
    bprintf(info->col_uk, " ],\n");
    bprintf(info->col_uk, "  \"sortOrders\" : [ \"\" ]\n");
    bprintf(info->col_uk, "}");

    CHARBUF_CLOSE(tmp);
  }

  // There could be several foreign keys, we have to walk the list of attributes and gather them all
  for (ast_node *attr = info->attrs; attr; attr = attr->right) {
    charbuf *saved = output;
    output = info->col_fk;
    if (is_ast_col_attrs_fk(attr)) {
      if (output->used > 1) {
        bprintf(output, ",\n");
      }
      bprintf(output, "{\n");
      BEGIN_INDENT(fk, 2)
      bprintf(output, "\"columns\" : [ \"%s\" ]", name);
      cg_json_fk_target_options(output, attr->left);
      END_INDENT(fk);
      bprintf(output,"\n}");
    }
    output = saved;
  }

  if (sem_type & SEM_TYPE_HAS_DEFAULT) {
    bprintf(output, ",\n\"defaultValue\" : ");
    cg_json_default_value(output, sem_get_col_default_value(info->attrs));
  }

  if (sem_type & SEM_TYPE_HAS_COLLATE) {
    // find the collate attribute and emit it (there can only be one)
    for (ast_node *attr = info->attrs; attr; attr = attr->right) {
      if (is_ast_col_attrs_collate(attr)) {
        bprintf(output, ",\n\"collate\" : ");
        cg_json_attr_value(output, attr->left);
      }
    }
  }

  if (sem_type & SEM_TYPE_HAS_CHECK) {
    // find the check attribute and emit it (there can only be one)
    for (ast_node *attr = info->attrs; attr; attr = attr->right) {
      if (is_ast_col_attrs_check(attr)) {
        EXTRACT_ANY_NOTNULL(when_expr, attr->left);
        cg_fragment_with_params(output, "checkExpr", when_expr, gen_root_expr);
      }
    }
  }

  if (info->is_backed) {
    bprintf(output, ",\n\"typeHash\" : %s", get_field_hash(name, sem_type));
  }

  // end with mandatory columns, this makes the json validation with yacc a little easier
  bprintf(output, ",\n\"isPrimaryKey\" : %d", !!(sem_type & SEM_TYPE_PK));
  bprintf(output, ",\n\"isUniqueKey\" : %d", !!(sem_type & SEM_TYPE_UK));
  bprintf(output, ",\n\"isAutoIncrement\" : %d", !!(sem_type & SEM_TYPE_AUTOINCREMENT));
}

// Starting from a semantic type, emit the appropriate JSON type
static void cg_json_data_type(charbuf *output, sem_t sem_type, CSTR kind) {
  sem_t core_type = core_type_of(sem_type);

  BEGIN_LIST;
  COMMA;
  bprintf(output, "\"type\" : \"");

  switch (core_type) {
    case SEM_TYPE_INTEGER:      bprintf(output, "integer"); break;
    case SEM_TYPE_TEXT:         bprintf(output, "text"); break;
    case SEM_TYPE_BLOB:         bprintf(output, "blob"); break;
    case SEM_TYPE_BOOL:         bprintf(output, "bool"); break;
    case SEM_TYPE_REAL:         bprintf(output, "real"); break;
    case SEM_TYPE_LONG_INTEGER: bprintf(output, "long"); break;
    case SEM_TYPE_OBJECT:       bprintf(output, "object"); break;
  }
  bprintf(output, "\"");

  if (kind) {
    COMMA;
    bprintf(output, "\"kind\" : \"%s\"", kind);
  }

  bool_t sensitive = !!sensitive_flag(sem_type);

  if (sensitive) {
    COMMA;
    bprintf(output, "\"isSensitive\" : %d", sensitive);
  }

  COMMA;
  bprintf(output, "\"isNotNull\" : %d", !is_nullable(sem_type));
}

// Starting with a column definition, emit the name and type information
// for the column.  If there are any miscellaneous attributes emit them as well.
// Finally gather the column attributes like not null etc. and emit those using
// the helper methods above.
static void cg_json_col_def(charbuf *output, col_info *info) {
  ast_node *def = info->def;

  Contract(is_ast_col_def(def));
  EXTRACT_NOTNULL(col_def_type_attrs, def->left);
  EXTRACT(misc_attrs, def->right);
  EXTRACT_ANY(attrs, col_def_type_attrs->right);
  EXTRACT_NOTNULL(col_def_name_type, col_def_type_attrs->left);
  EXTRACT_NAME_AST(name_ast, col_def_name_type->left);

  bprintf(output, "{\n");
  BEGIN_INDENT(col, 2);

  bprintf(output, "\"name\" : ");
  cg_json_sql_name(output, name_ast);
  bprintf(output, ",\n");

  if (misc_attrs) {
    cg_json_misc_attrs(output, misc_attrs);
    bprintf(output, ",\n");
  }
  cg_json_data_type(output, def->sem->sem_type, def->sem->kind);

  info->attrs = attrs;
  cg_json_col_attrs(output, info);

  END_INDENT(col);
  bprintf(output, "\n}");
}

// Emits a list of names into a one-line array of quoted names
static void cg_json_name_list(charbuf *output, ast_node *list) {
  Contract(is_ast_name_list(list));

  for (ast_node *item = list; item; item = item->right) {
    bprintf(output, "\"");
    cg_json_name(output, item->left);
    bprintf(output, "\"");
    if (item->right) {
      bprintf(output, ", ");
    }
  }
}

// This is useful for expressions known to have no parameters (e.g. constraint expressions)
// variables are illegal in such things so there can be no binding needed
static void cg_json_vanilla_expr(charbuf *output, ast_node *expr) {
  gen_sql_callbacks callbacks;
  init_gen_sql_callbacks(&callbacks);
  callbacks.mode = gen_mode_echo; // we want all the text, unexpanded, so NOT for sqlite output (this is raw echo)
  gen_set_output_buffer(output);
  gen_with_callbacks(expr, gen_root_expr, &callbacks);
}

// Similar to the above, this is also a list of names but we emit two arrays
// one array for the names and another array for the sort orders specified if any.
// Note unspecified sort orders are emitted as "".
static void cg_json_indexed_columns(charbuf *cols, charbuf *orders, ast_node *list) {
  for (ast_node *item = list; item; item = item->right) {
    Contract(is_ast_indexed_columns(list));
    EXTRACT_NOTNULL(indexed_column, item->left);

    bprintf(cols, "\"");
    cg_json_vanilla_expr(cols, indexed_column->left);
    bprintf(cols, "\"");

    if (is_ast_asc(indexed_column->right)) {
      bprintf(orders, "\"asc\"");
    }
    else if (is_ast_desc(indexed_column->right)) {
      bprintf(orders, "\"desc\"");
    }
    else {
      bprintf(orders, "\"\"");
    }

    if (item->right) {
      bprintf(cols, ", ");
      bprintf(orders, ", ");
    }
  }
}

// The primary key def is emitted just as an ordinary name list
static void cg_json_pk_def(charbuf *output, ast_node *def) {
  Contract(is_ast_pk_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);

  CHARBUF_OPEN(cols);
  CHARBUF_OPEN(orders);

  cg_json_indexed_columns(&cols, &orders, indexed_columns);

  bprintf(output, "\"primaryKey\" : [ %s ]", cols.ptr);
  bprintf(output, ",\n\"primaryKeySortOrders\" : [ %s ],\n", orders.ptr);

  CHARBUF_CLOSE(orders);
  CHARBUF_CLOSE(cols);
}

// This is just a little wrapper to set up the buffer to get the FK
// resolution action emitted without cloning that code.  gen_fk_action
// has a different contract than the usual generators (it doesn't take an AST)
// so I can't use the usual fragment helpers.
static void cg_json_action(charbuf *output, int32_t action) {
  CHARBUF_OPEN(sql);
  gen_set_output_buffer(&sql);
  if (!action) {
    action = FK_NO_ACTION;
  }
  gen_fk_action(action);
  bprintf(output, "\"%s\"", sql.ptr);
  CHARBUF_CLOSE(sql);
}

// Here we generate the update and delete actions plus the isDeferred state
// Everything is sitting pretty in the AST.
static void cg_json_fk_flags(charbuf *output, int32_t flags) {
  int32_t action = (flags & FK_ON_UPDATE) >> 4;

  bprintf(output, ",\n\"onUpdate\" : ");
  cg_json_action(output, action);

  action = (flags & FK_ON_DELETE);
  bprintf(output, ",\n\"onDelete\" : ");
  cg_json_action(output, action);

  // in sqlite anything that is not:
  // DEFERRABLE INITIALLY DEFERRED  is immediate
  // See 4.2. Deferred Foreign Key Constraints

  bool_t deferred = (flags & FK_DEFERRABLE) && (flags & FK_INITIALLY_DEFERRED);
  bprintf(output, ",\n\"isDeferred\" : %d", deferred);
}

// Generates the properties for a foreign key's target and the options
// that means the referencedTable, the columns as well as the flags
// using the helper above.
static void cg_json_fk_target_options(charbuf *output, ast_node *ast) {
  Contract(is_ast_fk_target_options(ast));

  EXTRACT_NOTNULL(fk_target, ast->left);
  EXTRACT_OPTION(flags, ast->right);
  EXTRACT_STRING(table_name, fk_target->left);
  EXTRACT_NAMED_NOTNULL(ref_list, name_list, fk_target->right);

  bprintf(output, ",\n\"referenceTable\" : \"%s\"", table_name);

  bprintf(output, ",\n\"referenceColumns\" : [ ");
  cg_json_name_list(output, ref_list);
  bprintf(output, " ]");
  cg_json_fk_flags(output, flags);
}

// optional constraint name, very boring.
static void cg_json_opt_constraint_name(charbuf *output, ast_node *def) {
  if (def->left) {
    EXTRACT_NAME_AST(constraint_name_ast, def->left);
    bprintf(output, "\"name\" : ");
    cg_json_sql_name(output, constraint_name_ast);
    bprintf(output, ",\n");
  }
}

// A full FK definition consists of the constrained columns
// and the FK target.  This takes care of the columns and defers
// to the above for the target (the target is used in other cases too)
static void cg_json_fk_def(charbuf *output, ast_node *def) {
  Contract(is_ast_fk_def(def));
  EXTRACT_NOTNULL(fk_info, def->right);
  EXTRACT_NAMED_NOTNULL(src_list, name_list, fk_info->left);
  EXTRACT_NOTNULL(fk_target_options, fk_info->right);

  cg_json_opt_constraint_name(output, def);

  bprintf(output, "\"columns\" : [ ");
  cg_json_name_list(output, src_list);
  bprintf(output, " ]");

  cg_json_fk_target_options(output, fk_target_options);
}

// A unique key definition is just the name of the key and then
// the participating columns.
static void cg_json_unq_def(charbuf *output, ast_node *def) {
  Contract(is_ast_unq_def(def));
  EXTRACT_NOTNULL(indexed_columns_conflict_clause, def->right);
  EXTRACT_NOTNULL(indexed_columns, indexed_columns_conflict_clause->left);

  bprintf(output, "{\n");
  BEGIN_INDENT(uk, 2);
  cg_json_opt_constraint_name(output, def);

  CHARBUF_OPEN(cols);
  CHARBUF_OPEN(orders);

  cg_json_indexed_columns(&cols, &orders, indexed_columns);

  bprintf(output, "\"columns\" : [ %s ]", cols.ptr);
  bprintf(output, ",\n\"sortOrders\" : [ %s ]", orders.ptr);

  CHARBUF_CLOSE(orders);
  CHARBUF_CLOSE(cols);

  END_INDENT(uk);
  bprintf(output, "\n}");
}

// A check constraint is just an expression, possibly named
static void cg_json_check_def(charbuf *output, ast_node *def) {
  Contract(is_ast_check_def(def));
  EXTRACT_ANY_NOTNULL(expr, def->right);

  bprintf(output, "{\n");
  BEGIN_INDENT(chk, 2);
  cg_json_opt_constraint_name(output, def);
  cg_fragment_with_params_raw(output, "checkExpr", expr, gen_root_expr);
  END_INDENT(chk);
  bprintf(output, "\n}");
}

// This is the list of "columns and keys" that form a table. In order to
// organize these we make several passes on the column list. We loop once
// for the columns then again for the PKs, then the FK, and finally UK.
// Note that in each case there is a chance that columns will contribute to
// the contents with keys that are defined directly on the column.
// That's ok, those are just buffered up and emitted with each section.
// All this several passes business just results in for sure all the column direct
// stuff comes before non column related stuff in each section.
static void cg_json_col_key_list(charbuf *output, ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast));
  EXTRACT_ANY(list, ast->right);
  Contract(is_ast_col_key_list(list));

  CHARBUF_OPEN(col_pk);
  CHARBUF_OPEN(col_uk);
  CHARBUF_OPEN(col_fk);

  col_info info;
  info.col_pk = &col_pk;
  info.col_uk = &col_uk;
  info.col_fk = &col_fk;
  info.is_backed = is_backed(ast->sem->sem_type);

  {
    bprintf(output, "\"columns\" : [\n");
    BEGIN_INDENT(cols, 2);
    BEGIN_LIST;
    for (ast_node *item = list; item; item = item->right) {
      EXTRACT_ANY_NOTNULL(def, item->left);
      if (is_ast_col_def(def)) {
        COMMA;
        info.def = def;
        info.attrs = NULL;
        cg_json_col_def(output, &info);
      }
    }
    END_LIST;
    END_INDENT(cols);
    bprintf(output, "],\n");
  }

  ast_node *pk_def = NULL;

  {
    if (col_pk.used > 1) {
      bprintf(output, "\"primaryKey\" : [ %s ],\n", col_pk.ptr);
      bprintf(output, "\"primaryKeySortOrders\" : [ \"\" ],\n");
    }
    else {
      for (ast_node *item = list; item; item = item->right) {
        EXTRACT_ANY_NOTNULL(def, item->left);
        if (is_ast_pk_def(def)) {
          cg_json_pk_def(output, def);
          pk_def = def;
        }
      }
      if (!pk_def) {
        bprintf(output, "\"primaryKey\" : [  ],\n");
        bprintf(output, "\"primaryKeySortOrders\" : [  ],\n");
      }
    }
  }


  if (pk_def && pk_def->left) {
    EXTRACT_STRING(pk_name, pk_def->left);
    bprintf(output, "\"primaryKeyName\" : \"%s\",\n", pk_name);
  }

  {
    bprintf(output, "\"foreignKeys\" : [\n");
    BEGIN_INDENT(fks, 2);
    BEGIN_LIST;
    if (col_fk.used > 1) {
      COMMA;
      bprintf(output, "%s", col_fk.ptr);
    }
    for (ast_node *item = list; item; item = item->right) {
      EXTRACT_ANY_NOTNULL(def, item->left);
      if (is_ast_fk_def(def)) {
        COMMA;
        bprintf(output, "{\n");
        BEGIN_INDENT(fk, 2);
        cg_json_fk_def(output, def);
        END_INDENT(fk);
        bprintf(output, "\n}");
      }
    }
    END_LIST;
    END_INDENT(fks);
    bprintf(output, "],\n");
  }

  {
    bprintf(output, "\"uniqueKeys\" : [\n");
    BEGIN_INDENT(uk, 2);
    BEGIN_LIST;
    if (col_uk.used > 1) {
      COMMA;
      bprintf(output, "%s", col_uk.ptr);
    }
    for (ast_node *item = list; item; item = item->right) {
      EXTRACT_ANY_NOTNULL(def, item->left);
      if (is_ast_unq_def(def)) {
        COMMA;
        cg_json_unq_def(output, def);
      }
    }
    END_LIST;
    END_INDENT(uk);
    bprintf(output, "],\n");
  }

  {
    bprintf(output, "\"checkExpressions\" : [\n");
    BEGIN_INDENT(chk, 2);
    BEGIN_LIST;
    for (ast_node *item = list; item; item = item->right) {
      EXTRACT_ANY_NOTNULL(def, item->left);
      if (is_ast_check_def(def)) {
        COMMA;
        cg_json_check_def(output, def);
      }
    }
    END_LIST;
    END_INDENT(chk);
    bprintf(output, "]");
  }

  CHARBUF_CLOSE(col_fk);
  CHARBUF_CLOSE(col_uk);
  CHARBUF_CLOSE(col_pk);
}

// Here we walk all the indices, extract out the key info for each index and
// emit it.  The indices have a few flags plus columns and a sort order for
// each column.  Other entries reference this list by name.
static void cg_json_indices(charbuf *output) {
  bprintf(output, "\"indices\" : [\n");
  BEGIN_INDENT(indices, 2);
  BEGIN_LIST;

  for (list_item *item = all_indices_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_create_index_stmt(ast));

    EXTRACT_NOTNULL(create_index_on_list, ast->left);
    EXTRACT_NOTNULL(flags_names_attrs, ast->right);
    EXTRACT_NOTNULL(connector, flags_names_attrs->right);
    EXTRACT_NOTNULL(index_names_and_attrs, connector->left);
    EXTRACT_OPTION(flags, flags_names_attrs->left);
    EXTRACT_NOTNULL(indexed_columns, index_names_and_attrs->left);
    EXTRACT(opt_where, index_names_and_attrs->right);
    EXTRACT_NAME_AST(index_name_ast, create_index_on_list->left);
    EXTRACT_NAME_AST(table_name_ast, create_index_on_list->right);
    EXTRACT_STRING(table_name, table_name_ast);

    ast_node *misc_attrs = NULL;
    ast_node *attr_target = ast->parent;
    if (is_ast_stmt_and_attr(attr_target)) {
      EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
      misc_attrs = misc;
    }

    cg_json_test_details(output, ast, misc_attrs);

    COMMA;
    bprintf(output, "{\n");

    BEGIN_INDENT(index, 2);

    bool_t is_deleted = ast->sem->delete_version > 0;
    bprintf(output, "\"name\" : ");
    cg_json_sql_name(output, index_name_ast);
    bprintf(output, ",\n\"CRC\" : \"%lld\"", crc_stmt(ast));
    bprintf(output, ",\n\"table\" : ");
    cg_json_sql_name(output, table_name_ast);
    bprintf(output, ",\n\"isUnique\" : %d", !!(flags & INDEX_UNIQUE));
    bprintf(output, ",\n\"ifNotExists\" : %d", !!(flags & INDEX_IFNE));
    bprintf(output, ",\n\"isDeleted\" : %d", is_deleted);
    if (is_deleted) {
      bprintf(output, ",\n\"deletedVersion\" : %d", ast->sem->delete_version);
    }

    if (ast->sem->region) {
      cg_json_emit_region_info(output, ast);
    }

    if (opt_where) {
      bprintf(output, ",\n\"where\" : \"");
      cg_json_vanilla_expr(output, opt_where->left);
      bprintf(output, "\"");
    }

    if (misc_attrs) {
      bprintf(output, ",\n");
      cg_json_misc_attrs(output, misc_attrs);
    }

    CHARBUF_OPEN(cols);
    CHARBUF_OPEN(orders);

    cg_json_indexed_columns(&cols, &orders, indexed_columns);

    bprintf(output, ",\n\"columns\" : [ %s ]", cols.ptr);
    bprintf(output, ",\n\"sortOrders\" : [ %s ]", orders.ptr);

    CHARBUF_CLOSE(orders);
    CHARBUF_CLOSE(cols);

    END_INDENT(index);
    bprintf(output, "\n}");
  }

  END_INDENT(indices);
  END_LIST;
  bprintf(output, "]");
}

// optional bool, which is "1" if present else absent
static void cg_json_opt_bool(charbuf *output, int32_t flag, CSTR desc) {
  if (flag) {
    bprintf(output, ",\n\"%s\" : 1", desc);
  }
}

// Here we walk all the triggers, we extract the essential flags from
// the trigger statement and emit those into the metadata as well. The main
// body is emitted verbatim.
static void cg_json_triggers(charbuf *output) {
  bprintf(output, "\"triggers\" : [\n");
  BEGIN_INDENT(indices, 2);
  BEGIN_LIST;

  for (list_item *item = all_triggers_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_create_trigger_stmt(ast));

    EXTRACT_OPTION(flags, ast->left);
    EXTRACT_NOTNULL(trigger_body_vers, ast->right);
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
    EXTRACT_STRING(table_name, trigger_target_action->left);
    EXTRACT_NOTNULL(trigger_action, trigger_target_action->right);
    EXTRACT_OPTION(action_flags, trigger_action->left);
    flags |= action_flags;
    EXTRACT_NOTNULL(trigger_when_stmts, trigger_action->right);
    EXTRACT_ANY(when_expr, trigger_when_stmts->left);
    EXTRACT_NOTNULL(stmt_list, trigger_when_stmts->right);

    ast_node *misc_attrs = NULL;
    ast_node *attr_target = ast->parent;
    if (is_ast_stmt_and_attr(attr_target)) {
      EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
      misc_attrs = misc;
    }

    cg_json_test_details(output, ast, misc_attrs);

    // use the canonical name (which may be case-sensitively different)
    ast_node *canonical_ast = find_table_or_view_even_deleted(table_name);
    ast_node *target_name_ast = sem_get_name_ast(canonical_ast);

    COMMA;
    bprintf(output, "{\n");

    BEGIN_INDENT(trigger, 2);

    bool_t is_deleted = ast->sem->delete_version > 0;
    bprintf(output, "\"name\" : ");
    cg_json_sql_name(output, trigger_name_ast);
    bprintf(output, ",\n\"CRC\" : \"%lld\"", crc_stmt(ast));
    bprintf(output, ",\n\"target\" : ");
    cg_json_sql_name(output, target_name_ast);
    bprintf(output, ",\n\"isTemp\" : %d", !!(flags & TRIGGER_IS_TEMP));
    bprintf(output, ",\n\"ifNotExists\" : %d", !!(flags & TRIGGER_IF_NOT_EXISTS));
    bprintf(output, ",\n\"isDeleted\" : %d", is_deleted);
    if (is_deleted) {
      bprintf(output, ",\n\"deletedVersion\" : %d", ast->sem->delete_version);
    }

    // only one of these
    cg_json_opt_bool(output, (flags & TRIGGER_BEFORE), "isBeforeTrigger");
    cg_json_opt_bool(output, (flags & TRIGGER_AFTER), "isAfterTrigger");
    cg_json_opt_bool(output, (flags & TRIGGER_INSTEAD_OF), "isInsteadOfTrigger");

    // only one of these
    cg_json_opt_bool(output, (flags & TRIGGER_DELETE), "isDeleteTrigger");
    cg_json_opt_bool(output, (flags & TRIGGER_INSERT), "isInsertTrigger");
    cg_json_opt_bool(output, (flags & TRIGGER_UPDATE), "isUpdateTrigger");

    cg_json_opt_bool(output, (flags & TRIGGER_FOR_EACH_ROW), "forEachRow");

    if (when_expr) {
      cg_fragment_with_params(output, "whenExpr", when_expr, gen_root_expr);
    }

    cg_fragment_with_params(output, "statement", ast, gen_one_stmt);

    if (ast->sem->region) {
      cg_json_emit_region_info(output, ast);
    }

    if (misc_attrs) {
      bprintf(output, ",\n");
      cg_json_misc_attrs(output, misc_attrs);
    }

    cg_json_dependencies(output, ast);

    END_INDENT(trigger);
    bprintf(output, "\n}");
  }

  END_INDENT(indices);
  END_LIST;
  bprintf(output, "]");
}

// This creates the map of regions and how they depend on each other
// regions have a list of regions they depend on, they can use
// that region directly or privately.  This is discussed elsewhere
// but generally items in a region R can use other things in R
// anything R depends on. If R depends on things privately then
// things in R can use those things things that depend on R cannot.
// This is like private inheritance in C++.
static void cg_json_region_deps(charbuf *output, CSTR sym) {
  // Every name we encounter has already been validated!
  ast_node *region = find_region(sym);
  Invariant(region);

  bprintf(output, "\"using\" : [ ");

  EXTRACT(region_list, region->right);
  for (ast_node *item = region_list; item; item = item->right) {
    Contract(is_ast_region_list(item));
    EXTRACT_NOTNULL(region_spec, item->left);
    EXTRACT_STRING(item_name, region_spec->left);
    bprintf(output, "\"%s\"", item_name);
    if (item->right) {
      bprintf(output, ", ");
    }
  }
  bprintf(output, " ]");

  bprintf(output, ",\n\"usingPrivately\" : [ ");

  for (ast_node *item = region_list; item; item = item->right) {
    Contract(is_ast_region_list(item));
    EXTRACT_NOTNULL(region_spec, item->left);
    EXTRACT_OPTION(type, region_spec->right);
    bprintf(output, "%d", type == PRIVATE_REGION);
    if (item->right) {
      bprintf(output, ", ");
    }
  }
  bprintf(output, " ]");
}

// To compute the deployed_in_region we only need to know its definiton
// * a normal object (not a region) indicates the region it is in by filling
//   in the region of its semantic node
// * a region indicates the deployment region it is in by filling in
//   the region of its semantic node
// * therefore to go from an object to its deployed region you first
//   get the region the object is in and then get the region that region is in
// * note that deployable regions do not necessarily cover everything so
//   if the object is in a region that is not yet in an deployable region
//   it's marked as an orphan.
static CSTR get_deployed_in_region(ast_node *ast) {
  CSTR deployedInRegion = "(orphan)";
  // if we are in no region at all, we're an orphan
  if (ast->sem->region) {
    // this is the region we are in, look it up
    ast_node *reg = find_region(ast->sem->region);

    // the region of that region is our deployment region
    if (reg->sem->region) {
       deployedInRegion = reg->sem->region;
    }
  }

  return deployedInRegion;
}

// Emit the region info and the deployment region info as needed
static void cg_json_emit_region_info(charbuf *output, ast_node *ast) {
  bprintf(output, ",\n\"region\" : \"%s\"", ast->sem->region);
  bprintf(output, ",\n\"deployedInRegion\" : \"%s\"", get_deployed_in_region(ast));
}

// Here we walk all the regions, we get the dependency information for
// that region and emit it.
static void cg_json_regions(charbuf *output) {
  bprintf(output, "\"regions\" : [\n");
  BEGIN_INDENT(regout, 2);
  BEGIN_LIST;

  symtab_entry *regs = symtab_copy_sorted_payload(schema_regions, default_symtab_comparator);

  for (list_item *item = all_regions_list; item; item = item->next) {
    ast_node *ast = item->ast;
    EXTRACT_STRING(name, ast->left);

    cg_json_test_details(output, ast, NULL);

    COMMA;
    bprintf(output, "{\n\"name\" : \"%s\",\n", name);
    CSTR deployedInRegion = get_deployed_in_region(ast);
    bprintf(output, "\"isDeployableRoot\" : %d,\n", !!(ast->sem->sem_type & SEM_TYPE_DEPLOYABLE));
    bprintf(output, "\"deployedInRegion\" : \"%s\",\n", deployedInRegion);
    cg_json_region_deps(output, name);
    bprintf(output, "\n}");
  }
  END_LIST;
  END_INDENT(regout);
  bprintf(output, "]");
  free(regs);
}

// Emit the result columns in the select list -- their names and types.
// This is the projection of the select.
static void cg_json_projection(charbuf *output, ast_node *ast) {
  Contract(ast);
  Contract(ast->sem);

  sem_struct *sptr = ast->sem->sptr;

  bprintf(output, ",\n\"projection\" : [\n");
  BEGIN_INDENT(proj, 2);
  BEGIN_LIST;

  for (uint32_t i = 0; i < sptr->count; i++) {
    COMMA;
    bprintf(output, "{\n");
    BEGIN_INDENT(type, 2);
    bprintf(output, "\"name\" : ");
    cg_json_sptr_sql_name(output, sptr, (int32_t)i);
    bprintf(output, ",\n");
    cg_json_data_type(output, sptr->semtypes[i], sptr->kinds[i]);
    END_INDENT(type);
    bprintf(output, "\n}");
  }
  END_LIST;
  END_INDENT(proj);
  bprintf(output, "]");
}

// The set of views look rather like the query section in as much as
// they are in fact nothing more than named select statements.  However
// the output here is somewhat simplified.  We only emit the whole select
// statement and any binding args, we don't also emit all the pieces of the select.
static void cg_json_views(charbuf *output) {
  bprintf(output, "\"views\" : [\n");
  BEGIN_INDENT(views, 2);

  int32_t i = 0;
  for (list_item *item = all_views_list; item; item = item->next) {
    ast_node *ast = item->ast;
    Invariant(is_ast_create_view_stmt(ast));

    ast_node *misc_attrs = NULL;
    ast_node *attr_target = ast->parent;
    if (is_ast_stmt_and_attr(attr_target)) {
      EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
      misc_attrs = misc;
    }

    cg_json_test_details(output, ast, misc_attrs);

    EXTRACT_OPTION(flags, ast->left);
    EXTRACT_NOTNULL(view_and_attrs, ast->right);
    EXTRACT_NOTNULL(view_details_select, view_and_attrs->left);
    EXTRACT_NOTNULL(view_details, view_details_select->left);
    EXTRACT_ANY_NOTNULL(select_stmt, view_details_select->right);
    EXTRACT_NAME_AST(name_ast, view_details->left);

    if (i > 0) {
      bprintf(output, ",\n");
    }
    bprintf(output, "{\n");

    bool_t is_deleted = ast->sem->delete_version > 0;
    BEGIN_INDENT(view, 2);
    bprintf(output, "\"name\" : ");
    cg_json_sql_name(output, name_ast);
    bprintf(output, ",\n\"CRC\" : \"%lld\"", crc_stmt(ast));
    bprintf(output, ",\n\"isTemp\" : %d", !!(flags & VIEW_IS_TEMP));
    bprintf(output, ",\n\"isDeleted\" : %d", is_deleted);
    if (is_deleted) {
      bprintf(output, ",\n\"deletedVersion\" : %d", ast->sem->delete_version);
      cg_json_deleted_migration_proc(output, view_and_attrs);
    }

    if (ast->sem->region) {
      cg_json_emit_region_info(output, ast);
    }

    if (misc_attrs) {
      bprintf(output, ",\n");
      cg_json_misc_attrs(output, misc_attrs);
    }

    cg_json_projection(output, select_stmt);
    cg_fragment_with_params(output, "select", select_stmt, gen_one_stmt);
    cg_json_dependencies(output, ast);
    END_INDENT(view);
    bprintf(output, "\n}\n");
    i++;
  }

  END_INDENT(views);
  bprintf(output, "]");
}

// This is the list of indices that are defined a the table.
static void cg_json_table_indices(list_item *head, charbuf *output) {
  bprintf(output, "\"indices\" : [ ");

  bool_t needs_comma = 0;
  for (list_item *item = head; item; item = item->next) {
    ast_node *ast = item->ast;

    // don't include deleted indices
    if (ast->sem->delete_version > 0) {
       continue;
    }

    Invariant(is_ast_create_index_stmt(ast));
    EXTRACT_NOTNULL(create_index_on_list, ast->left);
    EXTRACT_NAME_AST(index_name_ast, create_index_on_list->left);

    if (needs_comma) {
      bprintf(output, ", ");
    }

    cg_json_sql_name(output, index_name_ast);
    needs_comma = 1;
  }
  bprintf(output, " ]");
}

// The table output is the tables name, the assorted flags, and misc attributes
// the rest of the table output is produced by walking the column and key list
// using the helper above.
static void cg_json_table(charbuf *output, ast_node *ast) {
  Invariant(is_ast_create_table_stmt(ast));

  EXTRACT_NOTNULL(create_table_name_flags, ast->left);
  EXTRACT_NOTNULL(table_flags_attrs, create_table_name_flags->left);
  EXTRACT_OPTION(flags, table_flags_attrs->left);
  EXTRACT_NAME_AST(name_ast, create_table_name_flags->right);
  EXTRACT_ANY_NOTNULL(col_key_list, ast->right);

  int32_t temp = flags & TABLE_IS_TEMP;
  int32_t if_not_exist = flags & TABLE_IF_NOT_EXISTS;
  int32_t no_rowid = flags & TABLE_IS_NO_ROWID;

  ast_node *misc_attrs = NULL;

  ast_node *attr_target = ast->parent;
  if (is_virtual_ast(ast)) {
    // for virtual tables, we have to go up past the virtual table node to get the attributes
    attr_target = attr_target->parent;
  }

  if (is_ast_stmt_and_attr(attr_target)) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc, attr_target->parent);
    misc_attrs = misc;
  }

  cg_json_test_details(output, ast, misc_attrs);

  bprintf(output, "{\n");

  BEGIN_INDENT(table, 2);

  bool_t is_added = ast->sem->create_version > 0;

  bool_t is_deleted = ast->sem->delete_version > 0;
  bool_t is_unsub = ast->sem->unsubscribed > 0;

  bprintf(output, "\"name\" : ");
  cg_json_sql_name(output, name_ast);

  CHARBUF_OPEN(table_schema);
  gen_sql_callbacks schema_callbacks;
  init_gen_sql_callbacks(&schema_callbacks);
  schema_callbacks.mode = gen_mode_sql;
  gen_set_output_buffer(&table_schema);
  gen_statement_with_callbacks(ast, &schema_callbacks);
  bprintf(output, ",\n\"schema\" : ");
  cg_encode_json_string_literal(table_schema.ptr, output);
  CHARBUF_CLOSE(table_schema);

  bprintf(output, ",\n\"CRC\" : \"%lld\"", crc_stmt(ast));
  bprintf(output, ",\n\"isTemp\" : %d", !!temp);
  bprintf(output, ",\n\"ifNotExists\" : %d", !!if_not_exist);
  bprintf(output, ",\n\"withoutRowid\" : %d", !!no_rowid);
  bprintf(output, ",\n\"isAdded\" : %d", is_added);
  if (is_added) {
    bprintf(output, ",\n\"addedVersion\" : %d", ast->sem->create_version);
    cg_json_added_migration_proc(output, table_flags_attrs);
  }
  // deleted state includes deleted or unsubscribed
    bprintf(output, ",\n\"isDeleted\" : %d", is_deleted || is_unsub);
  if (is_deleted) {
    bprintf(output, ",\n\"deletedVersion\" : %d", ast->sem->delete_version);
    cg_json_deleted_migration_proc(output, table_flags_attrs);
  }
  bprintf(output, ",\n\"isRecreated\": %d", ast->sem->recreate);

  if (ast->sem->recreate_group_name) {
    bprintf(output, ",\n\"recreateGroupName\" : \"%s\"", ast->sem->recreate_group_name);
  }

  if (is_unsub) {
     bprintf(output, ",\n\"unsubscribedVersion\" : %d", ast->sem->unsubscribed);
  }

  if (is_backing(ast->sem->sem_type)) {
    bprintf(output, ",\n\"isBacking\" : 1");
  }
  else if (is_backed(ast->sem->sem_type)) {
    bprintf(output, ",\n\"isBacked\" : 1");
    bprintf(output, ",\n\"typeHash\" : %s", gen_type_hash(ast));
  }

  if (ast->sem->region) {
    cg_json_emit_region_info(output, ast);
  }

  if (is_virtual_ast(ast)) {
    bprintf(output, ",\n\"isVirtual\" : 1");
    bprintf(output, ",\n\"isEponymous\" : %d", !!(flags & VTAB_IS_EPONYMOUS));
    EXTRACT_NOTNULL(create_virtual_table_stmt, ast->parent);
    EXTRACT_NOTNULL(module_info, create_virtual_table_stmt->left);
    EXTRACT_STRING(module_name, module_info->left);
    EXTRACT_ANY(module_args, module_info->right);
    bprintf(output, ",\n\"module\" : \"%s\"", module_name);
    if (module_args) {
      bprintf(output, ",\n\"moduleArgs\" : ");
      if (is_ast_following(module_args)) {
        CHARBUF_OPEN(sql);
          gen_set_output_buffer(&sql);
          gen_sql_callbacks callbacks;
          init_gen_sql_callbacks(&callbacks);
          gen_with_callbacks(col_key_list, gen_col_key_list, &callbacks);
          cg_encode_json_string_literal(sql.ptr, output);
        CHARBUF_CLOSE(sql);
      }
      else {
        CHARBUF_OPEN(sql);
          gen_set_output_buffer(&sql);
          gen_sql_callbacks callbacks;
          init_gen_sql_callbacks(&callbacks);
          gen_with_callbacks(module_args, gen_misc_attr_value_list, &callbacks);
          cg_encode_json_string_literal(sql.ptr, output);
        CHARBUF_CLOSE(sql);
      }
    }
  }

  CONTINUE_LIST;

  if (ast->sem->table_info->index_list) {
    COMMA;
    cg_json_table_indices(ast->sem->table_info->index_list, output);
  }

  if (misc_attrs) {
    COMMA;
    cg_json_misc_attrs(output, misc_attrs);
  }

  COMMA;
  cg_json_col_key_list(output, ast);

  END_INDENT(table);
  END_LIST;
  bprintf(output, "}");
}

// The tables section is simply an array of table entries under the tables key
static void cg_json_tables(charbuf *output) {
  bprintf(output, "\"tables\" : [\n");
  BEGIN_INDENT(tables, 2);
  BEGIN_LIST;

  for (list_item *item = all_tables_list; item; item = item->next) {
    ast_node *ast = item->ast;
    if (is_virtual_ast(ast)) {
      continue;
    }
    COMMA;
    cg_json_table(output, ast);
  }

  END_INDENT(tables);
  END_LIST;
  bprintf(output, "]");
}

// The tables section is simply an array of table entries under the tables key
static void cg_json_virtual_tables(charbuf *output) {
  bprintf(output, "\"virtualTables\" : [\n");
  BEGIN_INDENT(tables, 2);
  BEGIN_LIST;

  for (list_item *item = all_tables_list; item; item = item->next) {
    ast_node *ast = item->ast;
    if (!is_virtual_ast(ast)) {
      continue;
    }
    COMMA;
    cg_json_table(output, ast);
  }

  END_INDENT(tables);
  END_LIST;
  bprintf(output, "]");
}

// This helper emits one parameter for a single stored proc.  Each will be
// used as the legal arguments to the statement we are binding.  If any of
// the parameters are of the 'out' flavor then this proc is "complex"
// so we simply return false and let it fall into the general bucket.
static bool_t cg_json_param(charbuf *output, ast_node *ast, CSTR *infos) {
  Contract(is_ast_param(ast));
  EXTRACT_ANY(opt_inout, ast->left);
  EXTRACT_NOTNULL(param_detail, ast->right);
  EXTRACT_STRING(name, param_detail->left);

  bool_t simple = 1;

  bprintf(output, "{\n");
  BEGIN_INDENT(type, 2);

  if (is_ast_inout(opt_inout)) {
    bprintf(output, "\"binding\" : \"inout\",\n");
    simple = 0;
  }
  else if (is_ast_out(opt_inout)) {
    bprintf(output, "\"binding\" : \"out\",\n");
    simple = 0;
  }

  bprintf(output, "\"name\" : \"%s\",\n", name);

  if (infos) {
    CSTR base_name = infos[0];
    CSTR shape_name = infos[1];
    CSTR shape_type = infos[2];

    if (shape_name[0]) {
      // this is an expansion of the form shape_name LIKE shape_type
      // the formal arg will have a name like "shape_name_base_name" (underscore between the parts)
      bprintf(output, "\"argOrigin\" : \"%s %s %s\",\n", shape_name, shape_type, base_name);
    }
    else if (shape_type[0]) {
      // this is an expansion of the form LIKE shape_type
      // the formal arg will have a name like "base_name_" (trailing underscore)
      bprintf(output, "\"argOrigin\" : \"%s %s\",\n", shape_type, base_name);
    }
    else {
      // this is a normal arg, it was not auto-expanded from anything
      // the formal arg will have the name "base_name"
      bprintf(output, "\"argOrigin\" : \"%s\",\n", base_name);
    }
  }

  cg_json_data_type(output, ast->sem->sem_type, ast->sem->kind);

  END_INDENT(type);

  bprintf(output, "\n}");
  return simple;
}

// Here we walk all the parameters of a stored proc and process each in turn.
// If any parameter is not valid, the entire proc becomes not valid.
static bool_t cg_json_params(charbuf *output, ast_node *ast, CSTR *infos) {
  bool_t simple = 1;

  BEGIN_LIST;
  while (ast) {
    Contract(is_ast_params(ast));
    EXTRACT_NOTNULL(param, ast->left);

    COMMA;

    simple &= cg_json_param(output, param, infos);

    ast = ast->right;

    // There are 3 strings per arg, one each for the shape name, shape type, and base name
    // these desribe how automatically generated arguments were created.
    if (infos) {
      infos += 3;
    }
  }
  END_LIST;

  return simple;
}

static bool_t found_shared_fragment;

// simply record the factthat we found a shared fragment
static bool_t cg_json_call_in_cte(ast_node *cte_body, void *context, charbuf *buffer) {
  found_shared_fragment = true;
  return false;
}

// Use the indicated generation function to create a SQL fragment.  The fragment
// may have parameters.  They are captured and emitted as an array.
static void cg_fragment_with_params_raw(charbuf *output, CSTR frag, ast_node *ast, gen_func fn) {
  CHARBUF_OPEN(sql);
  CHARBUF_OPEN(vars);
  gen_set_output_buffer(&sql);
  gen_sql_callbacks callbacks;
  init_gen_sql_callbacks(&callbacks);
  callbacks.variables_callback = cg_json_record_var;
  callbacks.variables_context = &vars;
  callbacks.cte_proc_callback = cg_json_call_in_cte;

  found_shared_fragment = false;

  bprintf(output, "\"%s\" : ", frag);
  gen_with_callbacks(ast, fn, &callbacks);
  cg_pretty_quote_plaintext(sql.ptr, output, PRETTY_QUOTE_JSON | PRETTY_QUOTE_SINGLE_LINE);
  bprintf(output, ",\n\"%sArgs\" : [ %s ]", frag, vars.ptr);

  CHARBUF_CLOSE(vars);
  CHARBUF_CLOSE(sql);
}

// Same as the above, but the most common case requires continuing a list
// so this helper does that.
static void cg_fragment_with_params(charbuf *output, CSTR frag, ast_node *ast, gen_func fn)
{
  bprintf(output, ",\n");
  cg_fragment_with_params_raw(output, frag, ast, fn);
}

// Use the indicated generation function to create a SQL fragment.  The fragment
// may not have parameters.  This is not suitable for use where expressions
// will be present.
static void cg_fragment(charbuf *output, CSTR frag, ast_node *ast, gen_func fn) {
  CHARBUF_OPEN(sql);
  gen_set_output_buffer(&sql);
  gen_sql_callbacks callbacks;
  init_gen_sql_callbacks(&callbacks);
  callbacks.variables_callback = cg_json_record_var;
  callbacks.variables_context = NULL;  // forces invariant violation if any variables

  bprintf(output, ",\n\"%s\" : ", frag);
  gen_with_callbacks(ast, fn, &callbacks);
  cg_pretty_quote_plaintext(sql.ptr, output, PRETTY_QUOTE_JSON | PRETTY_QUOTE_SINGLE_LINE);

  CHARBUF_CLOSE(sql);
}

// The row sources (select, insert returns, explain query plan) are emitted
// along with their projection and the full statement with bindings.  That
// here we handle the statement and bindings.  Once upon a time we also emitted
// fragments of the select statement but that was removed because such pieces
// proved of little use.
static void cg_json_any_row_source(charbuf *output, ast_node *ast) {
  Contract(is_row_source(ast));

  cg_fragment_with_params(output, "statement", ast, gen_one_stmt);
}

// Here we emit the following bits of information
// * the table we are inserting into
// * the insert type (INSERT, INSERT OR REPLACE etc)
// * the insert columns (the ones we are specifying)
// * a fragment for the entire statement with all the args
// * [optional] a fragment for each inserted value with its args
static void cg_json_insert_stmt(charbuf *output, ast_node *ast, bool_t emit_values) {
  // Both insert types have been unified in the AST
  Contract(is_insert_stmt(ast));
  Contract(!is_ast_insert_returning_stmt(ast));  // this is handled as a query

  ast_node *insert_stmt = ast;

  // extract the insert part it may be behind the WITH clause and it may be the insert part of an upsert
  if (is_ast_with_insert_stmt(ast)) {
    insert_stmt = ast->right;
  }
  else if (is_ast_upsert_stmt(ast)) {
    insert_stmt = ast->left;
  }
  else if (is_ast_with_upsert_stmt(ast)) {
    insert_stmt = ast->right->left;
  }

  Contract(is_ast_insert_stmt(insert_stmt));

  EXTRACT_ANY_NOTNULL(insert_type, insert_stmt->left);
  EXTRACT_NOTNULL(name_columns_values, insert_stmt->right);
  EXTRACT_NAME_AST(name_ast, name_columns_values->left)
  EXTRACT_NOTNULL(columns_values, name_columns_values->right);
  EXTRACT_NOTNULL(column_spec, columns_values->left);
  EXTRACT_ANY(columns_values_right, columns_values->right);
  EXTRACT(name_list, column_spec->left);

  // use the canonical name (which may be case-sensitively different)
  CSTR name = name_ast->sem->sptr->struct_name;

  bprintf(output, ",\n\"table\" : \"%s\"", name);
  cg_fragment_with_params(output, "statement", ast, gen_one_stmt);

  cg_fragment(output, "statementType", insert_type, gen_insert_type);

  bprintf(output, ",\n\"columns\" : [ ");
  if (name_list) {
    cg_json_name_list(output, name_list);
  }
  bprintf(output, " ]");

  if (emit_values) {
    // We only try to emit values if we know there is one row of them
    // So the select statement can only be a values clause with only one list of values.
    // This is guaranteed because of is_simple_insert(...) already checked this.
    // The general insert form might have arguments in all sorts of places and
    // so it can't be readily analyzed by downstream tools.  This very simple
    // insert form can be manipulated in interesting ways.  A downstream tool might
    // want to convert it into an upsert or some such.  In any case, we pull
    // out the very simple inserts to allow them to be more deeply analyzed.

    bprintf(output, ",\n\"values\" : [\n");
    BEGIN_LIST;
    BEGIN_INDENT(v1, 2);
    if (is_ast_select_stmt(columns_values_right)) {
      EXTRACT(select_stmt, columns_values_right);
      EXTRACT_NOTNULL(select_core_list, select_stmt->left);
      EXTRACT(select_core_compound, select_core_list->right);
      EXTRACT_NOTNULL(select_core, select_core_list->left);
      EXTRACT_NOTNULL(values, select_core->right);
      columns_values_right = values->left;
    }
    Invariant(columns_values_right == NULL || is_ast_insert_list(columns_values_right));
    EXTRACT(insert_list, columns_values_right);
    for (ast_node *item = insert_list; item; item = item->right) {
      COMMA;
      bprintf(output, "{\n");
      BEGIN_INDENT(v2, 2);
      cg_fragment_with_params_raw(output, "value", item->left, gen_root_expr);
      END_INDENT(v2);
      bprintf(output, "\n}");
    }
    END_INDENT(v1);
    END_LIST;
    bprintf(output, "]");
  }
}

// Delete statement gets the table name and the full statement and args
// as one fragment.
static void cg_json_delete_stmt(charbuf *output, ast_node * ast) {
  Contract(is_delete_stmt(ast));
  ast_node *delete_stmt = is_ast_with_delete_stmt(ast) ? ast->right : ast;
  EXTRACT_NAME_AST(name_ast, delete_stmt->left);

  // use the canonical name (which may be case-sensitively different)
  CSTR name = name_ast->sem->sptr->struct_name;

  bprintf(output, ",\n\"table\" : \"%s\"", name);
  cg_fragment_with_params(output, "statement", ast, gen_one_stmt);
}

// Update statement gets the table name and the full statement and args
// as one fragment.
static void cg_json_update_stmt(charbuf *output, ast_node *ast) {
  Contract(is_update_stmt(ast));
  ast_node *update_stmt = is_ast_with_update_stmt(ast) ? ast->right : ast;

  EXTRACT_NAME_AST(name_ast, update_stmt->left);

  // use the canonical name (which may be case-sensitively different)
  CSTR name = name_ast->sem->sptr->struct_name;

  bprintf(output, ",\n\"table\" : \"%s\"", name);
  cg_fragment_with_params(output, "statement", ast, gen_one_stmt);
}

// Start a new section for any kind of thing, if testing we spew the test info here
// This lets us attribute the output to a particular line number in the test file.
// This code also adds the pesky comma that goes before any new items in the same
// section.
static void cg_begin_item_attrs(charbuf *output, ast_node *ast, ast_node *misc_attrs) {
  Contract(ast);

  if (output->used > 1) bprintf(output, ",\n");
  cg_json_test_details(output, ast, misc_attrs);
  bprintf(output, "{\n");
}

// For symetry we have this lame end function
static void cg_end_proc(charbuf *output, ast_node *ast) {
  bprintf(output, "\n}");
}

// Emit the arguments to the proc, track if they are valid (i.e. no OUT args)
// If not valid, the proc will be "general"
static bool_t cg_parameters(charbuf *output, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  bool_t simple = 1;

  bytebuf *arg_info = find_proc_arg_info(name);
  CSTR *infos = arg_info ? (CSTR *)arg_info->ptr : NULL;

  bprintf(output, ",\n\"args\" : [\n");
  BEGIN_INDENT(parms, 2);
  simple = cg_json_params(output, params, infos);
  END_INDENT(parms);
  bprintf(output, "]");

  return simple;
}

// The purpose of the "simple" versions is to enable code-rewriters to replace
// the proc with the DML directly and bind it.  The code gen can some idea of what's
// going on in the simple cases -- it's a single row insert.  In those cases it's
// possible to skip the C codegen entirely.  You can just bind and run the DML.
bool_t static is_simple_insert(ast_node *ast) {
  if (!is_ast_insert_stmt(ast)) {
    return false;
  }

  EXTRACT_NOTNULL(name_columns_values, ast->right);
  EXTRACT_NOTNULL(columns_values, name_columns_values->right);
  if (!is_select_variant(columns_values->right)) {
    // the insert statement does not have a select statement
    return true;
  }

  EXTRACT(select_stmt, columns_values->right);
  EXTRACT_NOTNULL(select_core_list, select_stmt->left);
  EXTRACT(select_core_compound, select_core_list->right);
  if (select_core_compound != NULL) {
    // The select statement is a compound select therefore it's not simple insert
    return false;
  }

  EXTRACT_NOTNULL(select_core, select_core_list->left);
  if (!is_ast_values(select_core->right)) {
    // The select statement does not have VALUES clause then it's not simple insert
    return false;
  }

  EXTRACT_NOTNULL(values, select_core->right);
  if (values->right) {
    // The values clause has multiple list of value therefore it's not a simple insert
    return false;
  }

  // The insert statement contains a select statement that only has a VALUES clause
  // and the VALUES clause has only one list of values.
  return true;
}

static void cg_json_general_proc(ast_node *ast, ast_node *misc_attrs, CSTR params) {
  charbuf *output = general;
  cg_begin_item_attrs(output, ast, misc_attrs);
  sem_t sem_type = ast->sem->sem_type;
  BEGIN_INDENT(proc, 2)
  bprintf(output, "%s", params);
  bool_t has_any_result_set = !!ast->sem->sptr;
  bool_t uses_out_union = !!(sem_type & SEM_TYPE_USES_OUT_UNION);
  bool_t uses_out = !!(sem_type & SEM_TYPE_USES_OUT);
  bool_t select_result = !uses_out && !uses_out_union && has_any_result_set;

  if (has_any_result_set) {
    cg_json_projection(output, ast);
  }

  // clearer coding of the result types including out union called out seperately
  if (uses_out) {
    Invariant(has_any_result_set);
    bprintf(output, ",\n\"hasOutResult\" : 1");
  }
  else if (uses_out_union) {
    Invariant(has_any_result_set);
    bprintf(output, ",\n\"hasOutUnionResult\" : 1");
  }
  else if (select_result) {
    Invariant(has_any_result_set);
    bprintf(output, ",\n\"hasSelectResult\" : 1");
  }
  else {
    Invariant(!has_any_result_set);
  }

  bprintf(output, ",\n\"usesDatabase\" : %d", !!(sem_type & SEM_TYPE_DML_PROC));
  END_INDENT(proc);
}

// For procedures and triggers we want to walk the statement list and emit a set
// of dependency entries that show what the code in question is using and how.
// We track tables that are used and if they appear in say the FROM clause
// (or some other read-context) or if they are the subject of an insert, update,
// or delete.  We also track the use of nested procedures and produce a list of
// procs the subject might call.  Of course no proc calls ever appear in triggers.
static void cg_json_dependencies(charbuf *output, ast_node *ast) {
  json_context context;
  CHARBUF_OPEN(used_tables);
  CHARBUF_OPEN(used_views);
  CHARBUF_OPEN(insert_tables);
  CHARBUF_OPEN(update_tables);
  CHARBUF_OPEN(delete_tables);
  CHARBUF_OPEN(from_tables);
  CHARBUF_OPEN(used_procs);

  context.cookie = cookie_str;
  context.proc_ast = ast;
  context.used_tables = &used_tables;
  context.used_views = &used_views;
  context.insert_tables = &insert_tables;
  context.delete_tables = &delete_tables;
  context.update_tables = &update_tables;
  context.from_tables = &from_tables;
  context.used_procs = &used_procs;

  table_callbacks callbacks = {
      .notify_table_or_view_drops = false,
      .notify_fk = false,
      .notify_triggers = false,
      .callback_any_table = cg_found_table,
      .callback_any_view = cg_found_view,
      .callback_inserts = cg_found_insert,
      .callback_updates = cg_found_update,
      .callback_deletes = cg_found_delete,
      .callback_from = cg_found_from,
      .callback_proc = cg_found_proc,
      .callback_context = &context,
  };
  find_table_refs(&callbacks, ast);

  if (insert_tables.used > 1) {
    bprintf(output, ",\n\"insertTables\" : [ %s ]", insert_tables.ptr);
  }
  if (update_tables.used > 1) {
    bprintf(output, ",\n\"updateTables\" : [ %s ]", update_tables.ptr);
  }
  if (delete_tables.used > 1) {
    bprintf(output, ",\n\"deleteTables\" : [ %s ]", delete_tables.ptr);
  }
  if (from_tables.used > 1) {
    bprintf(output, ",\n\"fromTables\" : [ %s ]", from_tables.ptr);
  }
  if (used_procs.used > 1) {
    bprintf(output, ",\n\"usesProcedures\" : [ %s ]", used_procs.ptr);
  }
  if (used_views.used > 1) {
    bprintf(output, ",\n\"usesViews\" : [ %s ]", used_views.ptr);
  }

  bprintf(output, ",\n\"usesTables\" : [ %s ]", used_tables.ptr);

  CHARBUF_CLOSE(used_procs);
  CHARBUF_CLOSE(from_tables);
  CHARBUF_CLOSE(delete_tables);
  CHARBUF_CLOSE(update_tables);
  CHARBUF_CLOSE(insert_tables);
  CHARBUF_CLOSE(used_views);
  CHARBUF_CLOSE(used_tables);
}


static void cg_defined_in_file(charbuf *output, ast_node *ast) {
  CHARBUF_OPEN(tmp);
    // quote the file as a json style literaj
    CSTR filename = ast->filename;
    #ifdef _WIN32
    CSTR slash = strrchr(filename, '\\');
    #else
    CSTR slash = strrchr(filename, '/');
    #endif
    if (slash) {
      filename = slash + 1;
    }
    cg_encode_json_string_literal(filename, &tmp);
    bprintf(output, ",\n\"definedInFile\" : %s",  tmp.ptr);
  CHARBUF_CLOSE(tmp);
}

static void cg_defined_on_line(charbuf *output, ast_node *ast) {
  int32_t lineno = cg_find_first_line(ast);
  bprintf(output, ",\n\"definedOnLine\" : %d", lineno);
}

static void cg_json_declare_interface(charbuf *output, ast_node *ast, ast_node *misc_attrs) {
  Contract(is_ast_declare_interface_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT_NOTNULL(typed_names, proc_params_stmts->right);

  cg_begin_item_attrs(output, ast, NULL);

  BEGIN_INDENT(interface, 2);
  bprintf(output, "\"name\" : \"%s\"", name);
  cg_defined_in_file(output, ast);
  cg_defined_on_line(output, ast);

  if (misc_attrs) {
    bprintf(output, ",\n");
    cg_json_misc_attrs(output, misc_attrs);
  }

  cg_json_projection(output, ast);
  END_INDENT(interface);

  cg_end_proc(output, ast);
}

static void cg_json_declare_func(charbuf *stmt_out, ast_node *ast, ast_node *misc_attrs) {
  bool_t select_func = is_ast_declare_select_func_no_check_stmt(ast) || is_ast_declare_select_func_stmt(ast);
  bool_t non_select_func = is_ast_declare_func_no_check_stmt(ast) || is_ast_declare_func_stmt(ast);
  bool_t no_check_func = is_ast_declare_func_no_check_stmt(ast) || is_ast_declare_select_func_no_check_stmt(ast);
  Contract(select_func || non_select_func);

  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_STRING(name, name_ast);
  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);

  CHARBUF_OPEN(declare_func_buffer);
  charbuf *output = &declare_func_buffer;

  bprintf(output, "\"name\" : \"%s\"", name);

  if (!no_check_func) {
    // emit parameters.
    bprintf(output, ",\n\"args\" : [\n");
    BEGIN_INDENT(parms, 2);
    cg_json_params(output, params, NULL);
    END_INDENT(parms);
    bprintf(output, "]");
  }

  // emit attributes.
  if (misc_attrs) {
    bprintf(output, ",\n");
    cg_json_misc_attrs(output, misc_attrs);
  }

  // emit return type.
  EXTRACT_ANY_NOTNULL(data_type, func_params_return->right);

  bool_t creates_object = false;
  if (is_ast_typed_names(data_type)) {
    // table valued function
    cg_json_projection(output, data_type);
  }
  else {
    if (is_ast_create_data_type(data_type)) {
      creates_object = true;
      data_type = data_type->left;
    }

    bprintf(output, ",\n\"returnType\" : {\n");
    BEGIN_INDENT(type, 2);
    cg_json_data_type(output, data_type->sem->sem_type, data_type->sem->kind);
    END_INDENT(type);
    bprintf(output, "\n}");
  }

  if (!select_func) {
    // emit whether this function is a "create" function or not.
    // (this means its return value begins with a +1 ref that the caller now owns)
    // always false for table valued functions
    bprintf(output, ",\n\"createsObject\" : %d", (int)creates_object);
  }

  // add this function to the list.
  output = stmt_out;
  cg_begin_item_attrs(output, ast, misc_attrs);
  BEGIN_INDENT(func, 2);
  bprintf(output, "%s", declare_func_buffer.ptr);
  END_INDENT(func);

  // clean up
  CHARBUF_CLOSE(declare_func_buffer);
  cg_end_proc(output, ast);
}


// the no check version has no args, and it is never DML, and never has a shape
static void cg_json_declare_proc_no_check(charbuf *stmt_out, ast_node *ast, ast_node *misc_attrs) {
  Contract(is_ast_declare_proc_no_check_stmt(ast));
  EXTRACT_ANY_NOTNULL(proc_name, ast->left);
  EXTRACT_STRING(name, proc_name);

  CHARBUF_OPEN(declare_proc_buffer);
  charbuf *output = &declare_proc_buffer;

  // emit function name.
  bprintf(output, "\"name\" : \"%s\"", name);

  // emit attributes.
  if (misc_attrs) {
    bprintf(output, ",\n");
    cg_json_misc_attrs(output, misc_attrs);
  }

  // add this proc to the list.
  output = stmt_out;
  cg_begin_item_attrs(output, ast, misc_attrs);
  BEGIN_INDENT(proc, 2);
  bprintf(output, "%s", declare_proc_buffer.ptr);
  END_INDENT(proc);

  // cleanup
  CHARBUF_CLOSE(declare_proc_buffer);
  cg_end_proc(output, ast);
}

static void cg_json_declare_proc(charbuf *stmt_out, ast_node *ast, ast_node *misc_attrs) {
  Contract(is_ast_declare_proc_stmt(ast));
  EXTRACT_NOTNULL(proc_name_type, ast->left);
  EXTRACT_NAME_AST(name_ast, proc_name_type->left);
  EXTRACT_STRING(name, name_ast);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);

  CHARBUF_OPEN(declare_proc_buffer);
  charbuf *output = &declare_proc_buffer;

  // emit function name.
  bprintf(output, "\"name\" : \"%s\"", name);

  // emit parameters.
  bprintf(output, ",\n\"args\" : [\n");
  BEGIN_INDENT(parms, 2);
  cg_json_params(output, params, NULL);
  END_INDENT(parms);
  bprintf(output, "]");

  // emit attributes.
  if (misc_attrs) {
    bprintf(output, ",\n");
    cg_json_misc_attrs(output, misc_attrs);
  }

  // emit projections.
  sem_t sem_type = ast->sem->sem_type;
  bool_t has_any_result_set = !!ast->sem->sptr;
  if (has_any_result_set) {
    cg_json_projection(output, ast);
  }

  // emit use db or not.
  bprintf(output, ",\n\"usesDatabase\" : %d", !!(sem_type & SEM_TYPE_DML_PROC));

  // add this proc to the list.
  output = stmt_out;
  cg_begin_item_attrs(output, ast, misc_attrs);
  BEGIN_INDENT(proc, 2);
  bprintf(output, "%s", declare_proc_buffer.ptr);
  END_INDENT(proc);

  // cleanup
  CHARBUF_CLOSE(declare_proc_buffer);
  cg_end_proc(output, ast);
}

// If we find a procedure definition we crack its arguments and first statement
// If it matches one of the known types we generate the details for it.  Otherwise
// it goes into the general bucket.  The output is redirected to the appropriate
// output stream for the type of statement and then a suitable helper is dispatched.
// Additionally, each procedure includes an array of tables that it uses regardless
// of the type of procedure.
static void cg_json_create_proc(charbuf *unused, ast_node *ast, ast_node *misc_attrs) {
  Contract(is_ast_create_proc_stmt(ast));
  Contract(unused == NULL);  // proc output is complicated, this code knows what to do
  EXTRACT_NAME_AST(name_ast, ast->left);
  EXTRACT_STRING(name, name_ast);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT(stmt_list, proc_params_stmts->right);

  // shared fragments are invisible to the JSON or anything else, they have
  // no external interface.
  if (is_proc_shared_fragment(ast)) {
    return;
  }

  CHARBUF_OPEN(param_buffer);
  charbuf *output = &param_buffer;

  bprintf(output, "\"name\" : \"%s\"", name);
  cg_defined_in_file(output, name_ast);
  cg_defined_on_line(output, ast);

  bool_t simple = cg_parameters(output, ast);

  cg_json_dependencies(output, ast);

  if (ast->sem->region) {
    cg_json_emit_region_info(output, ast);
  }

  if (misc_attrs) {
    bprintf(output, ",\n");
    cg_json_misc_attrs(output, misc_attrs);
  }

  if (!stmt_list) {
    output = general;
    cg_json_general_proc(ast, misc_attrs, param_buffer.ptr);
    goto cleanup;
  }

  EXTRACT_STMT_AND_MISC_ATTRS(stmt, nested_misc_attrs, stmt_list);

  // if more than one statement it isn't simple
  if (stmt_list->right) {
    simple = 0;
  }

  // we have to see if it uses shared fragments, this can't be "simple"
  // because the parameters can be synthetic and require assignments and such
  if (simple && is_row_source(stmt)) {
    found_shared_fragment = false;
    CHARBUF_OPEN(scratch);
    cg_json_any_row_source(&scratch, stmt); // easy way to walk the tree
    CHARBUF_CLOSE(scratch);
    // the above sets this by side-effect in the callback
    simple = !found_shared_fragment;
  }

  if (simple && is_row_source(stmt)) {
    output = queries;
    cg_begin_item_attrs(output, ast, misc_attrs);
    BEGIN_INDENT(proc, 2);
    bprintf(output, "%s", param_buffer.ptr);
    cg_json_projection(output, stmt);
    cg_json_any_row_source(output, stmt);
    END_INDENT(proc);
  }
  else if (simple && is_insert_stmt(stmt)) {
    bool_t simple_insert = is_simple_insert(stmt);

    output = simple_insert ? inserts : general_inserts;
    cg_begin_item_attrs(output, ast, misc_attrs);
    BEGIN_INDENT(proc, 2);
    bprintf(output, "%s", param_buffer.ptr);
    cg_json_insert_stmt(output, stmt, simple_insert);
    END_INDENT(proc);
  }
  else if (simple && is_delete_stmt(stmt)) {
    output = deletes;
    cg_begin_item_attrs(output, ast, misc_attrs);
    BEGIN_INDENT(proc, 2);
    bprintf(output, "%s", param_buffer.ptr);
    cg_json_delete_stmt(output, stmt);
    END_INDENT(proc);
  }
  else if (simple && is_update_stmt(stmt)) {
    output = updates;
    cg_begin_item_attrs(output, ast, misc_attrs);
    BEGIN_INDENT(proc, 2);
    bprintf(output, "%s", param_buffer.ptr);
    cg_json_update_stmt(output, stmt);
    END_INDENT(proc);
  }
  else {
    output = general;
    cg_json_general_proc(ast, misc_attrs, param_buffer.ptr);
  }

cleanup:
  CHARBUF_CLOSE(param_buffer);
  cg_end_proc(output, ast);
}

// This lets us have top level attributes that go into the main output stream
// this is stuff like the name of the database and so forth.  By convention these
// are placed as an attribution on the statements "declare database object".
// Attributes for any object variables named *database are unified so that
// different schema fragments can contribute easily.
static void cg_json_database_var(charbuf *output, ast_node *ast, ast_node *misc_attrs) {
  Contract(is_ast_declare_vars_type(ast));
  EXTRACT_NOTNULL(name_list, ast->left);
  EXTRACT_ANY_NOTNULL(data_type, ast->right);

  bool_t first_attr = output->used == 1;

  // we're looking for "declare *database object"  and nothing else. Note the '*',
  // which indicates that we will match any variable ending with "database".
  if (misc_attrs && !name_list->right && is_object(data_type->sem->sem_type)) {
    EXTRACT_STRING(name, name_list->left);
    if (StrEndsWith(name, "database")) {

      if (first_attr) {
        bprintf(output, "\n");
      }

      cg_json_test_details(output, ast, misc_attrs);

      BEGIN_INDENT(attr, 2);

      // The attributes from all the various sources are unified, they will
      // go into one attributes block.  Note there can be duplicates but that's
      // not a problem for the schema and may even be desired.  Note also
      // that even if we had only one such object there could still be duplicates
      // because again, attributes on a single object are not unique.  They mean
      // whatever you want them to mean.  So we just spit them out and let
      // the consumer sort it out.  In practice this isn't really a problem.
      // Whatever tool is downstream will complain if the attributes are badly formed.
      for (ast_node *item = misc_attrs; item; item = item->right) {
        if (!first_attr) {
          bprintf(output, ",\n");
        }
        first_attr = false;
        cg_json_misc_attr(output, item->left);
      }

      END_INDENT(attr);
    }
  }
}


// all the generic statement handlers look like this
// this is a custom functor to call them
typedef struct {
  void (*func)(charbuf *out, ast_node *ast, ast_node *misc_attrs);
  charbuf *out;
} json_dispatch;

#undef STMT_INIT
#define STMT_INIT(x, func, out) \
  json_dispatch json_disp_ ## x = { func,  out }; \
  symtab_add(stmts, k_ast_ ## x, (void *)&json_disp_ ##x)

// Here we create several buffers for the various statement types and then redirect
// output into the appropriate buffer as we walk the statements.  Finally each buffer
// is emitted in order.
static void cg_json_stmt_list(charbuf *output, ast_node *head) {
  CHARBUF_OPEN(query_buf);
  CHARBUF_OPEN(insert_buf);
  CHARBUF_OPEN(update_buf);
  CHARBUF_OPEN(delete_buf);
  CHARBUF_OPEN(general_buf);
  CHARBUF_OPEN(general_inserts_buf);
  CHARBUF_OPEN(attributes_buf);
  CHARBUF_OPEN(declare_procs_buf);
  CHARBUF_OPEN(declare_no_check_procs_buf);
  CHARBUF_OPEN(declare_funcs_buf);
  CHARBUF_OPEN(declare_no_check_funcs_buf);
  CHARBUF_OPEN(declare_select_funcs_buf);
  CHARBUF_OPEN(declare_no_check_select_funcs_buf);
  CHARBUF_OPEN(declare_interfaces_buf);

  queries = &query_buf;
  inserts = &insert_buf;
  updates = &update_buf;
  deletes = &delete_buf;
  general = &general_buf;
  general_inserts = &general_inserts_buf;

  symtab *stmts = symtab_new();

  STMT_INIT(create_proc_stmt, cg_json_create_proc, NULL);
  STMT_INIT(declare_vars_type, cg_json_database_var, &attributes_buf);
  STMT_INIT(declare_interface_stmt, cg_json_declare_interface, &declare_interfaces_buf);
  STMT_INIT(declare_proc_stmt, cg_json_declare_proc, &declare_procs_buf);
  STMT_INIT(declare_proc_no_check_stmt, cg_json_declare_proc_no_check, &declare_no_check_procs_buf);
  STMT_INIT(declare_func_stmt, cg_json_declare_func, &declare_funcs_buf);
  STMT_INIT(declare_func_no_check_stmt, cg_json_declare_func, &declare_no_check_funcs_buf);
  STMT_INIT(declare_select_func_stmt, cg_json_declare_func, &declare_select_funcs_buf);
  STMT_INIT(declare_select_func_no_check_stmt, cg_json_declare_func, &declare_no_check_select_funcs_buf);


  for (ast_node *ast = head; ast; ast = ast->right) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, ast);

    // declares can be duplicated, we don't want to emit more than one into the JSON
    // e.g. you can declare the same proc twice
    if (is_alias_ast(stmt)) {
      continue;
    }

    // Search for the functions we declared above and dispatch
    symtab_entry *entry = symtab_find(stmts, stmt->type);
    if (!entry) {
      continue;
    }

    json_dispatch *disp = (json_dispatch *)entry->val;
    disp->func(disp->out, stmt, misc_attrs);
  }

  symtab_delete(stmts);

  bprintf(output, "\"attributes\" : [");
  bprintf(output, "%s", attributes_buf.ptr);
  bprintf(output, "\n],\n");

  bprintf(output, "\"queries\" : [\n");
  bindent(output, queries, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"inserts\" : [\n");
  bindent(output, inserts, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"generalInserts\" : [\n");
  bindent(output, general_inserts, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"updates\" : [\n");
  bindent(output, updates, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"deletes\" : [\n");
  bindent(output, deletes, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"general\" : [\n");
  bindent(output, general, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareProcs\" : [\n");
  bindent(output, &declare_procs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareNoCheckProcs\" : [\n");
  bindent(output, &declare_no_check_procs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareFuncs\" : [\n");
  bindent(output, &declare_funcs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareNoCheckFuncs\" : [\n");
  bindent(output, &declare_no_check_funcs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareSelectFuncs\" : [\n");
  bindent(output, &declare_select_funcs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"declareNoCheckSelectFuncs\" : [\n");
  bindent(output, &declare_no_check_select_funcs_buf, 2);
  bprintf(output, "\n],\n");

  bprintf(output, "\"interfaces\" : [\n");
  bindent(output, &declare_interfaces_buf, 2);
  bprintf(output, "\n]");

  CHARBUF_CLOSE(declare_interfaces_buf);
  CHARBUF_CLOSE(declare_no_check_select_funcs_buf);
  CHARBUF_CLOSE(declare_select_funcs_buf);
  CHARBUF_CLOSE(declare_no_check_funcs_buf);
  CHARBUF_CLOSE(declare_funcs_buf);
  CHARBUF_CLOSE(declare_no_check_procs_buf);
  CHARBUF_CLOSE(declare_procs_buf);
  CHARBUF_CLOSE(attributes_buf);
  CHARBUF_CLOSE(general_inserts_buf);
  CHARBUF_CLOSE(general_buf);
  CHARBUF_CLOSE(delete_buf);
  CHARBUF_CLOSE(update_buf);
  CHARBUF_CLOSE(insert_buf);
  CHARBUF_CLOSE(query_buf);

  // Ensure the globals do not hold any pointers so that leaksan will find any leaks
  // All of these have already been freed (above)
  queries = NULL;
  deletes = NULL;
  inserts = NULL;
  updates = NULL;
  general = NULL;
  general_inserts = NULL;
}

// Here we emit a top level fragment that has all the tables and
// all the procedures that use that table.  This is the reverse mapping
// from the proc section where each proc defines which tables it uses.
// i.e. we can use this map to go from a dirty table name to a list of
// affected queries/updates etc.
static void cg_json_table_users(charbuf *output) {
  uint32_t count = tables_to_procs->count;
  symtab_entry *deps = symtab_copy_sorted_payload(tables_to_procs, default_symtab_comparator);

  bprintf(output, "\"tableUsers\" : {\n");
  BEGIN_INDENT(users, 2);
  BEGIN_LIST;
  for (uint32_t i = 0; i < count; i++) {
    CSTR sym = deps[i].sym;
    charbuf *buf = (charbuf*)deps[i].val;

    COMMA;
    bprintf(output, "\"%s\" : [ %s ]", sym, buf->ptr);
  }
  END_LIST;
  END_INDENT(users);
  bprintf(output, "}");
  free(deps);
}

// Main entry point for json schema format
cql_noexport void cg_json_schema_main(ast_node *head) {
  Contract(options.file_names_count == 1);

  cql_exit_on_semantic_errors(head);

  tables_to_procs = symtab_new();

  CHARBUF_OPEN(main);
  charbuf *output = &main;

  bprintf(output, "%s", rt->source_prefix);

  // master dictionary begins
  bprintf(output, "\n{\n");
  BEGIN_INDENT(defs, 2);
  cg_json_tables(output);
  bprintf(output, ",\n");
  cg_json_virtual_tables(output);
  bprintf(output, ",\n");
  cg_json_views(output);
  bprintf(output, ",\n");
  cg_json_indices(output);
  bprintf(output, ",\n");
  cg_json_triggers(output);
  bprintf(output, ",\n");
  cg_json_stmt_list(output, head);
  bprintf(output, ",\n");
  cg_json_regions(output);
  bprintf(output, ",\n");
  cg_json_ad_hoc_migration_procs(output);
  bprintf(output, ",\n");
  cg_json_enums(output);
  bprintf(output, ",\n");
  cg_json_constant_groups( output);
  bprintf(output, ",\n");
  cg_json_subscriptions( output);

  if (options.test) {
    bprintf(output, ",\n");
    cg_json_table_users(output);
  }

  END_INDENT(defs);
  bprintf(output, "\n}\n");

  cql_write_file(options.file_names[0], output->ptr);
  CHARBUF_CLOSE(main);

  SYMTAB_CLEANUP(tables_to_procs);
}
#endif
