/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Assorted definitions for the CQL abstract syntax tree

#pragma once

#include "cql.h"
#include "minipool.h"
#include "symtab.h"

#define GENERIC_IS_TEMP       0x1
#define GENERIC_IF_NOT_EXISTS 0x2

#define VTAB_IS_EPONYMOUS     0x4

#define TABLE_IS_TEMP         GENERIC_IS_TEMP
#define TABLE_IF_NOT_EXISTS   GENERIC_IF_NOT_EXISTS
#define TABLE_IS_NO_ROWID     0x0004

#define VIEW_IS_TEMP          GENERIC_IS_TEMP
#define VIEW_IF_NOT_EXISTS    GENERIC_IF_NOT_EXISTS

#define TRIGGER_IS_TEMP       GENERIC_IS_TEMP
#define TRIGGER_IF_NOT_EXISTS GENERIC_IF_NOT_EXISTS
#define TRIGGER_BEFORE        0x0004
#define TRIGGER_AFTER         0x0008
#define TRIGGER_INSTEAD_OF    0x0010
#define TRIGGER_UPDATE        0x0020
#define TRIGGER_DELETE        0x0040
#define TRIGGER_INSERT        0x0080
#define TRIGGER_FOR_EACH_ROW  0x0100

#define PROC_FLAG_BASIC          0
#define PROC_FLAG_STRUCT_TYPE    1
#define PROC_FLAG_USES_DML       2
#define PROC_FLAG_USES_OUT       4
#define PROC_FLAG_USES_OUT_UNION 8

#define INDEX_UNIQUE        1
#define INDEX_IFNE          2

#define RAISE_IGNORE        0
#define RAISE_ROLLBACK      1
#define RAISE_ABORT         2
#define RAISE_FAIL          3

#define ON_CONFLICT_ROLLBACK   0
#define ON_CONFLICT_ABORT      1
#define ON_CONFLICT_FAIL       2
#define ON_CONFLICT_IGNORE     3
#define ON_CONFLICT_REPLACE    4

#define FK_ON_UPDATE   0xF0
#define FK_ON_DELETE   0x0F

#define FK_SET_NULL    0x01
#define FK_SET_DEFAULT 0x02
#define FK_CASCADE     0x03
#define FK_RESTRICT    0x04
#define FK_NO_ACTION   0x05

#define FK_DEFERRABLES         0xF00
#define FK_NOT_DEFERRABLE      0x800
#define FK_DEFERRABLE          0x400
#define FK_INITIALLY_DEFERRED  0x200
#define FK_INITIALLY_IMMEDIATE 0x100

#define TRANS_DEFERRED 1
#define TRANS_IMMEDIATE 2
#define TRANS_EXCLUSIVE 3

#define ENFORCE_FK_ON_UPDATE 1
#define ENFORCE_FK_ON_DELETE 2
#define ENFORCE_STRICT_JOIN 3
#define ENFORCE_UPSERT_STMT 4
#define ENFORCE_WINDOW_FUNC 5
#define ENFORCE_CAST 6
#define ENFORCE_WITHOUT_ROWID 7
#define ENFORCE_TRANSACTION 8
#define ENFORCE_SELECT_IF_NOTHING 9
#define ENFORCE_INSERT_SELECT 10
#define ENFORCE_TABLE_FUNCTION 11
#define ENFORCE_SIGN_FUNCTION 12
#define ENFORCE_IS_TRUE 13
#define ENFORCE_CURSOR_HAS_ROW 14
#define ENFORCE_UPDATE_FROM 15
#define ENFORCE_AND_OR_NOT_NULL_CHECK 16

#define COMPOUND_OP_UNION 1
#define COMPOUND_OP_UNION_ALL 2
#define COMPOUND_OP_INTERSECT 3
#define COMPOUND_OP_EXCEPT 4

#define PUBLIC_REGION 0
#define PRIVATE_REGION 1

#define EXPLAIN_NONE 1
#define EXPLAIN_QUERY_PLAN 2

#define FRAME_TYPE_RANGE                 0x00001
#define FRAME_TYPE_ROWS                  0x00002
#define FRAME_TYPE_GROUPS                0x00004
#define FRAME_TYPE_FLAGS                 0x00007 // bit mask for the frame spec type

#define FRAME_BOUNDARY_UNBOUNDED         0x00008
#define FRAME_BOUNDARY_PRECEDING         0x00010
#define FRAME_BOUNDARY_CURRENT_ROW       0x00020
#define FRAME_BOUNDARY_FLAGS             0x00038 // bit mask for the frame spec boundary

#define FRAME_BOUNDARY_START_UNBOUNDED   0x00040
#define FRAME_BOUNDARY_START_PRECEDING   0x00080
#define FRAME_BOUNDARY_START_CURRENT_ROW 0x00100
#define FRAME_BOUNDARY_START_FOLLOWING   0x00200
#define FRAME_BOUNDARY_START_FLAGS       0x003C0 // bit mask for the frame spec boundary start

#define FRAME_BOUNDARY_END_PRECEDING     0x00400
#define FRAME_BOUNDARY_END_CURRENT_ROW   0x00800
#define FRAME_BOUNDARY_END_FOLLOWING     0x01000
#define FRAME_BOUNDARY_END_UNBOUNDED     0x02000
#define FRAME_BOUNDARY_END_FLAGS         0x03C00 // bit mask for the frame spec boundary end

#define FRAME_EXCLUDE_NO_OTHERS          0x04000
#define FRAME_EXCLUDE_CURRENT_ROW        0x08000
#define FRAME_EXCLUDE_GROUP              0x10000
#define FRAME_EXCLUDE_TIES               0x20000
#define FRAME_EXCLUDE_NONE               0x40000
#define FRAME_EXCLUDE_FLAGS              0x7C000 // bit mask for the frame spec boundary end

#define NUM_INT 0
#define NUM_LONG 1
#define NUM_REAL 2
#define NUM_BOOL 3

typedef struct ast_node {
  const char *_Nonnull type;
  struct sem_node *_Nullable sem;
  struct ast_node *_Nullable parent;
  int32_t lineno;
  CSTR _Nonnull filename;
  struct ast_node *_Nullable left;
  struct ast_node *_Nullable right;
} ast_node;

typedef struct int_ast_node {
  const char *_Nonnull type;
  struct sem_node *_Nullable sem;
  struct ast_node *_Nullable parent;
  int32_t lineno;
  CSTR _Nonnull filename;
  int64_t value;
} int_ast_node;

#define STRING_TYPE_SQL 0
#define STRING_TYPE_C 1
#define STRING_TYPE_QUOTED_ID 2

typedef struct str_ast_node {
  const char *_Nonnull type;
  struct sem_node *_Nullable sem;
  struct ast_node *_Nullable parent;
  int32_t lineno;
  CSTR _Nonnull filename;
  const char *_Nullable value;
  uint8_t str_type;
} str_ast_node;

typedef struct num_ast_node {
  const char *_Nonnull type;
  struct sem_node *_Nullable sem;
  struct ast_node *_Nullable parent;
  int32_t lineno;
  CSTR _Nonnull filename;
  int32_t num_type;
  const char *_Nullable value;
} num_ast_node;

typedef struct {
  ast_node *_Nonnull def;
  int32_t type;
  int32_t count_context;
} macro_info;

cql_noexport CSTR _Nullable install_macro_args(ast_node *_Nonnull ast);
cql_noexport void new_macro_formals(void);
cql_noexport void delete_macro_formals(void);
cql_noexport bool_t set_macro_info(CSTR _Nonnull name, int32_t macro_type, ast_node *_Nonnull ast);
cql_noexport bool_t set_macro_arg_info(CSTR _Nonnull name, int32_t macro_type, ast_node *_Nonnull ast);
cql_noexport macro_info *_Nullable get_macro_arg_info(CSTR _Nonnull name);
cql_noexport macro_info *_Nullable get_macro_info(CSTR _Nonnull name);
cql_noexport void expand_macros(ast_node *_Nonnull root);
cql_noexport int32_t macro_arg_type(ast_node *_Nonnull macro_arg);
cql_noexport int32_t resolve_macro_name(CSTR _Nonnull name);
cql_noexport ast_node *_Nonnull new_macro_arg_node(ast_node *_Nonnull arg);
cql_noexport ast_node *_Nonnull new_macro_arg_ref_node(CSTR _Nonnull name);
cql_noexport ast_node *_Nonnull new_macro_ref_node(CSTR _Nonnull name, ast_node *_Nullable args);
cql_noexport CSTR _Nonnull macro_type_from_name(CSTR _Nonnull name);

// from the lexer
extern int yylineno;
cql_data_decl( char *_Nullable current_file );

cql_data_decl ( CSTR _Nullable base_fragment_name );

cql_data_decl( bool_t macro_expansion_errors );

cql_data_decl( minipool *_Nullable ast_pool );

#define _ast_pool_new(x) _pool_new(ast_pool, x)
#define _ast_pool_new_array(x, c) _pool_new_array(ast_pool, x, c)

// reset location to make sure it's not used by the next new nodes. If any
// new node is created without setting location then the app will crash.
#define AST_REWRITE_INFO_START() \
  ast_reset_rewrite_info()

// end reset location session and make sure SET and RESET were used in synced
#define AST_REWRITE_INFO_END() \
  Contract(!current_file && yylineno == -1)

// any new nodes will be charged to this location
#define AST_REWRITE_INFO_SET(lineno, filename) \
  Contract(!current_file && yylineno == -1); \
  ast_set_rewrite_info(lineno, filename)

// reset the location to make sure it's not used by the next new nodes
#define AST_REWRITE_INFO_RESET() \
  Contract(current_file && yylineno > 0); \
  ast_reset_rewrite_info()

// any new nodes will be charged to this location
#define AST_REWRITE_INFO_SAVE() \
  int32_t lineno_saved = yylineno; \
  CSTR current_file_saved = current_file; \
  ast_reset_rewrite_info()

// reset the location to make sure it's not used by the next new nodes
#define AST_REWRITE_INFO_RESTORE() \
  ast_set_rewrite_info(lineno_saved, current_file_saved);


cql_noexport void ast_set_rewrite_info(int32_t lineno, CSTR _Nonnull filename);
cql_noexport void ast_reset_rewrite_info(void);

cql_noexport void ast_init(void);
cql_noexport void ast_cleanup(void);

cql_noexport ast_node *_Nonnull new_ast(const char *_Nonnull type, ast_node *_Nullable l, ast_node *_Nullable r);
cql_noexport ast_node *_Nonnull new_ast_num(int32_t type, const char *_Nonnull value);
cql_noexport ast_node *_Nonnull new_ast_option(int32_t value);
cql_noexport ast_node *_Nonnull new_ast_str(CSTR _Nonnull value);
cql_noexport ast_node *_Nonnull new_ast_cstr(CSTR _Nonnull value);
cql_noexport ast_node *_Nonnull new_ast_qstr_escaped(CSTR _Nonnull value);
cql_noexport ast_node *_Nonnull new_ast_qstr_quoted(CSTR _Nonnull value);
cql_noexport ast_node *_Nonnull new_ast_blob(CSTR _Nonnull value);

cql_noexport bool_t is_ast_int(ast_node *_Nullable node);
cql_noexport bool_t is_ast_str(ast_node *_Nullable node);
cql_noexport bool_t is_ast_num(ast_node *_Nullable node);
cql_noexport bool_t is_ast_blob(ast_node *_Nullable node);

cql_noexport bool_t is_any_macro_ref(ast_node *_Nullable ast);
cql_noexport bool_t is_macro_def(ast_node *_Nonnull ast);
cql_noexport bool_t is_macro_ref(ast_node *_Nullable ast);
cql_noexport bool_t is_macro_arg_ref(ast_node *_Nullable ast);

cql_noexport bool_t is_select_variant(ast_node *_Nullable ast);
cql_noexport bool_t is_row_source(ast_node *_Nullable ast);
cql_noexport bool_t is_delete_stmt(ast_node *_Nullable ast);
cql_noexport bool_t is_insert_stmt(ast_node *_Nullable ast);
cql_noexport bool_t is_update_stmt(ast_node *_Nullable ast);
cql_noexport bool_t is_upsert_stmt(ast_node *_Nullable ast);

cql_noexport bool_t is_select_func(ast_node *_Nonnull ast);
cql_noexport bool_t is_non_select_func(ast_node *_Nonnull ast);

cql_noexport bool_t is_strlit(ast_node *_Nullable node);
cql_noexport bool_t is_id(ast_node *_Nullable node);
cql_noexport bool_t is_qname(CSTR _Nonnull subject);
cql_noexport bool_t is_qid(ast_node *_Nullable node);
cql_noexport bool_t is_id_or_dot(ast_node *_Nullable node);
cql_noexport bool_t is_primitive(ast_node *_Nullable  node);
cql_noexport bool_t is_proc(ast_node *_Nullable node);
cql_noexport bool_t is_region(ast_node *_Nonnull ast);

cql_noexport ast_node *_Nullable get_proc_params(ast_node *_Nonnull ast);
cql_noexport ast_node *_Nonnull get_proc_name(ast_node *_Nonnull ast);
cql_noexport ast_node *_Nullable get_func_params(ast_node *_Nonnull func_stmt);

cql_noexport bool_t ast_has_left(ast_node *_Nullable node);
cql_noexport bool_t ast_has_right(ast_node *_Nullable enode);

cql_noexport void ast_set_right(ast_node *_Nonnull parent, ast_node *_Nullable right);
cql_noexport void ast_set_left(ast_node *_Nonnull parent, ast_node *_Nullable left);

cql_noexport bool_t print_ast_value(struct ast_node *_Nonnull node);
cql_noexport void print_ast_type(ast_node *_Nonnull node);
cql_noexport void print_ast(ast_node *_Nullable node, ast_node *_Nullable parent, int32_t pad, bool_t flip);
cql_noexport void print_root_ast(ast_node *_Nullable node);

cql_noexport void ast_reset_rewrite_info(void);
cql_noexport ast_node *_Nullable ast_clone_tree(ast_node *_Nullable ast);
cql_noexport CSTR _Nonnull convert_cstrlit(CSTR _Nonnull cstr);

cql_noexport CSTR _Nonnull get_compound_operator_name(int32_t compound_operator);

#define INSERT_DUMMY_DEFAULTS 1
#define INSERT_DUMMY_NULLABLES 2

/*
  SQLite understands the following binary operators, in order from LOWEST to HIGHEST precedence:
  NOTE: this is NOT the C binding order (!!!)
  NOTE: this MUST match the tokens in cql.y
  PRI_OR
  PRI_AND
  PRI_EQUALITY =    ==   !=   <>   IS   IS NOT   IN   LIKE   GLOB   MATCH   REGEXP
  PRI_INEQUALITY <    <=   >    >=
  PRI_BINARY <<   >>   &    |
  PRI_ADD     +    -
  PRI_MUL     *    /    %
  PRI_CONCAT  ||
  PRI_TILDE ~
  PRI_REVERSE_APPLY : []
*/

#define has_hex_prefix(s) (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))

#define EXPR_PRI_ROOT -999
#define EXPR_PRI_ASSIGN 0
#define EXPR_PRI_OR 1
#define EXPR_PRI_AND 2
#define EXPR_PRI_NOT 3
#define EXPR_PRI_BETWEEN 5  // between is the same as equality, left to right
#define EXPR_PRI_EQUALITY 5
#define EXPR_PRI_INEQUALITY 6
#define EXPR_PRI_BINARY 7
#define EXPR_PRI_ADD 8
#define EXPR_PRI_MUL 9
#define EXPR_PRI_CONCAT 10
#define EXPR_PRI_COLLATE 11
#define EXPR_PRI_TILDE 12
#define EXPR_PRI_REVERSE_APPLY 13

/* from the SQLite grammar

%left OR.
%left AND.
%right NOT.
%left IS MATCH LIKE_KW BETWEEN IN ISNULL NOTNULL NE EQ.
%left GT LE LT GE.
%right ESCAPE.    NYI in CQL
%left BITAND BITOR LSHIFT RSHIFT.
%left PLUS MINUS.
%left STAR SLASH REM.
%left CONCAT.
%left COLLATE.
%right BITNOT.

*/

// relevant C binding order
#define C_EXPR_PRI_ROOT -999
#define C_EXPR_PRI_ASSIGN 0
#define C_EXPR_PRI_LOR 1
#define C_EXPR_PRI_LAND 2
#define C_EXPR_PRI_BOR  3
#define C_EXPR_PRI_BAND 4
#define C_EXPR_PRI_EQ_NE 5
#define C_EXPR_PRI_LT_GT 6
#define C_EXPR_PRI_SHIFT 7
#define C_EXPR_PRI_ADD 8
#define C_EXPR_PRI_MUL 9
#define C_EXPR_PRI_UNARY 10
#define C_EXPR_PRI_HIGHEST 999

#define JOIN_INNER 1
#define JOIN_CROSS 2
#define JOIN_LEFT_OUTER 3
#define JOIN_RIGHT_OUTER 4
#define JOIN_LEFT 5
#define JOIN_RIGHT 6

#define EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, stmt_list) \
  Contract(is_ast_stmt_list(stmt_list)); \
  ast_node *stmt = stmt_list->left; \
  ast_node *misc_attrs = NULL; \
  if (is_ast_stmt_and_attr(stmt)) { \
    misc_attrs = stmt->left; \
    stmt = stmt->right; \
    Contract(is_ast_misc_attrs(misc_attrs)); \
  }

#define EXTRACT_STMT(stmt, stmt_list) \
  Contract(is_ast_stmt_list(stmt_list)); \
  ast_node *stmt = stmt_list->left; \
  if (is_ast_stmt_and_attr(stmt)) { \
    stmt = stmt->right; \
  }

// Use this macro from within a single node processor to reach out and get the attributes that apply to that
// node, which would be hanging off the parent ast node, if present.
#define EXTRACT_MISC_ATTRS(ast, misc_attrs) \
  ast_node *misc_attrs = NULL; \
  if (is_ast_stmt_and_attr(ast->parent)) { \
    misc_attrs = ast->parent->left; \
    Contract(is_ast_misc_attrs(misc_attrs)); \
  }

#define EXTRACT_ANY(name, node) \
  ast_node *name = node;

#define EXTRACT_ANY_NOTNULL(name, node) \
  ast_node *name = node; \
  Contract(node);

#define EXTRACT_NAMED(name, type, node) \
  ast_node *name = node; \
  Contract(!name || is_ast_##type(name));

#define EXTRACT_NAMED_NOTNULL(name, type, node) \
  ast_node *name = node; \
  Contract(name && is_ast_##type(name));

#define EXTRACT(type, node) EXTRACT_NAMED(type, type, node)

#define EXTRACT_NOTNULL(type, node) EXTRACT_NAMED_NOTNULL(type, type, node)

#define EXTRACT_STRING(name, node) \
  Contract(is_ast_str(node)); \
  const char *name = ((str_ast_node *)(node))->value; \
  Contract(name);

#define EXTRACT_NAME_AST(name_ast, node) \
  Contract(is_id(node) || is_ast_at_id(node)); \
  ast_node *name_ast = (node);

#define EXTRACT_BLOBTEXT(name, node) \
  Contract(is_ast_blob(node)); \
  const char *name = ((str_ast_node *)(node))->value; \
  Contract(name);

#define EXTRACT_NUM_TYPE(num_type, node) \
  Contract(is_ast_num(node)); \
  int32_t num_type = ((num_ast_node *)(node))->num_type;

#define EXTRACT_NUM_VALUE(val, node) \
  Contract(is_ast_num(node)); \
  CSTR val = ((num_ast_node *)(node))->value; \
  Contract(val);

#define EXTRACT_OPTION(name, node) \
  Contract(is_ast_int(node)); \
  int32_t name = (int32_t)((int_ast_node *)(node))->value;

#define EXTRACT_NAMED_NAME_AND_SCOPE(name, scope, node) \
  Contract(is_id_or_dot(node)); \
  CSTR name, scope; \
  if (is_id(node)) { \
    name = ((str_ast_node *)(node))->value; \
    scope = NULL; \
  } \
   else { \
    name = ((str_ast_node *)(node->right))->value; \
    scope = ((str_ast_node *)(node->left))->value; \
  }

#define EXTRACT_NAME_AND_SCOPE(node) \
  EXTRACT_NAMED_NAME_AND_SCOPE(name, scope, node)

// For searching proc dependencies/attributes
typedef void (*find_ast_str_node_callback)(CSTR _Nonnull found_name, ast_node *_Nonnull str_ast, void *_Nullable context);
typedef void (*find_ast_num_node_callback)(CSTR _Nonnull found_name, ast_node *_Nonnull num_ast, void *_Nullable context);

typedef struct table_callbacks {
  bool_t notify_table_or_view_drops;
  bool_t notify_fk;
  bool_t notify_triggers;
  bool_t do_not_recurse_views;
  symtab *_Nullable visited_any_table;
  symtab *_Nullable visited_insert;
  symtab *_Nullable visited_update;
  symtab *_Nullable visited_delete;
  symtab *_Nullable visited_from;
  symtab *_Nullable visited_proc;
  find_ast_str_node_callback _Nullable callback_any_table;
  find_ast_str_node_callback _Nullable callback_any_view;
  find_ast_str_node_callback _Nullable callback_inserts;
  find_ast_str_node_callback _Nullable callback_updates;
  find_ast_str_node_callback _Nullable callback_deletes;
  find_ast_str_node_callback _Nullable callback_from;
  find_ast_str_node_callback _Nullable callback_proc;
  void (*_Nullable callback_final_processing)(void *_Nullable callback_context);
  void *_Nullable callback_context;
} table_callbacks;

cql_noexport void find_table_refs(table_callbacks *_Nonnull data, ast_node *_Nonnull node);
cql_noexport void continue_find_table_node(table_callbacks *_Nonnull callbacks, ast_node *_Nonnull node);


// Signature of function finding annotation values
typedef uint32_t (*find_annotation_values)(
    ast_node *_Nullable misc_attr_list,
    find_ast_str_node_callback _Nonnull callback,
    void *_Nullable callback_context);

cql_noexport uint32_t find_ok_table_scan(
   ast_node *_Nonnull list,
   find_ast_str_node_callback _Nonnull callback,
   void *_Nullable context);

cql_noexport uint32_t find_autodrops(
   ast_node *_Nonnull list,
   find_ast_str_node_callback _Nonnull callback,
   void *_Nullable context);

cql_noexport uint32_t find_identity_columns(
  ast_node *_Nullable misc_attr_list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable callback_context);

cql_noexport uint32_t find_cql_alias_of(
  ast_node *_Nonnull misc_attr_list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable context
);

cql_noexport uint32_t find_attribute_str(
  ast_node *_Nonnull misc_attr_list,
  find_ast_str_node_callback _Nullable callback,
  void *_Nullable context,
  const char *_Nonnull attribute_name);

cql_noexport uint32_t exists_attribute_str(
  ast_node *_Nullable misc_attr_list,
  const char *_Nonnull attribute_name);

cql_noexport uint32_t find_backed_table_attr(ast_node *_Nonnull misc_attr_list);
cql_noexport uint32_t find_backing_table_attr(ast_node *_Nonnull misc_attr_list);

cql_noexport CSTR _Nullable get_named_string_attribute_value(ast_node *_Nonnull misc_attr_list, CSTR _Nonnull name);
cql_noexport bool_t find_named_attr(ast_node *_Nonnull misc_attr_list, CSTR _Nonnull name);

cql_noexport uint32_t find_query_plan_branch(
  ast_node *_Nonnull list,
  find_ast_num_node_callback _Nonnull callback,
  void *_Nullable context
);

cql_noexport bool_t is_table_blob_storage(ast_node *_Nonnull ast);
cql_noexport bool_t is_table_backing(ast_node *_Nonnull ast);
cql_noexport bool_t is_table_backed(ast_node *_Nonnull ast);

// Callback whenever a misc_attr node is found in find_misc_attrs().
typedef void (*find_ast_misc_attr_callback)(
  CSTR _Nullable misc_attr_prefix,
  CSTR _Nonnull misc_attr_name,
  ast_node *_Nullable ast_misc_attr_value_list,
  void *_Nullable context);

cql_noexport void find_misc_attrs(
  ast_node *_Nullable misc_attr_list,
  find_ast_misc_attr_callback _Nonnull misc_attr_callback,
  void *_Nullable context);

cql_noexport size_t ends_in_cursor(CSTR _Nonnull str);
cql_noexport size_t ends_in_set(CSTR _Nonnull str);

cql_noexport void replace_node(ast_node *_Nonnull old, ast_node *_Nonnull new);

#ifdef CQL_AMALGAM

  // In the amalgam build we see this file only once, we emit the definitions as statics
  // AST_EMIT_DEFS is irrelevant in this mode.  This is the easy case.

  #define AST_VIS static
  #define AST_DATA_DECL(x)
  #define AST_DATA_DEFN(x) AST_VIS x
  #define AST_DEF(x) x

#else

  // In the non amalgam build we need the ".h" version that declares things
  // except one time the ".c" version that defines things.  This is the hard case.

  #ifdef AST_EMIT_DEFS
    #define AST_DEF(x) x
  #else
    #define AST_DEF(x)
  #endif

  #define AST_VIS extern
  #define AST_DATA_DECL(x) AST_VIS x
  #define AST_DATA_DEFN(x) AST_DEF(x)

#endif

AST_DATA_DECL( CSTR _Nonnull k_ast_int );
AST_DATA_DECL( CSTR _Nonnull k_ast_num );
AST_DATA_DECL( CSTR _Nonnull k_ast_str );
AST_DATA_DECL( CSTR _Nonnull k_ast_blob );

AST_DATA_DEFN( CSTR _Nonnull k_ast_int = "int" );
AST_DATA_DEFN( CSTR _Nonnull k_ast_num = "num" );
AST_DATA_DEFN( CSTR _Nonnull k_ast_str = "str" );
AST_DATA_DEFN( CSTR _Nonnull k_ast_blob = "blb" );

#define AST_DECL_CHECK(x) \
  AST_DATA_DECL(const char *_Nonnull k_ast_ ## x;) \
  AST_DATA_DEFN(const char *_Nonnull k_ast_ ## x = #x;) \
  AST_VIS bool_t is_ast_ ## x(ast_node *_Nullable n); \
  AST_DEF(AST_VIS  bool_t is_ast_ ## x(ast_node *_Nullable n) {return n && (n->type == k_ast_ ## x);  })

#define AST(x) \
  AST_DECL_CHECK(x) \
  AST_VIS ast_node *_Nonnull new_ast_ ## x(ast_node *_Nullable l, ast_node *_Nullable r); \
  AST_DEF(AST_VIS ast_node *_Nonnull new_ast_ ## x(ast_node *_Nullable l, ast_node *_Nullable r) { return new_ast(k_ast_ ## x, l, r); })

#define AST1(x) \
  AST_DECL_CHECK(x) \
  AST_VIS ast_node *_Nonnull new_ast_ ## x(ast_node *_Nullable l); \
  AST_DEF(AST_VIS ast_node *_Nonnull new_ast_ ## x(ast_node *_Nullable l) { return new_ast(k_ast_ ## x, l, NULL); })

#define AST0(x) \
  AST_DECL_CHECK(x) \
  AST_VIS ast_node *_Nonnull new_ast_ ## x(void); \
  AST_DEF(AST_VIS ast_node *_Nonnull new_ast_ ## x() { return new_ast(k_ast_ ## x, NULL, NULL); })

#ifndef _MSC_VER

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

#endif

AST(add)
AST(add_eq)
AST(alter_table_add_column_stmt)
AST(and)
AST(and_eq)
AST(arg_list)
AST(array)
AST(assign)
AST(autoinc_and_conflict_clause)
AST(between)
AST(between_rewrite)
AST(bin_and)
AST(bin_or)
AST(call)
AST(call_arg_list)
AST(call_filter_clause)
AST(call_stmt)
AST(case_expr)
AST(case_list)
AST(cast_expr)
AST(check_def)
AST(child_result)
AST(child_results)
AST(col_attrs_check)
AST(col_attrs_collate)
AST(col_attrs_default)
AST(col_attrs_fk)
AST(col_attrs_hidden)
AST(col_attrs_not_null)
AST(col_attrs_pk)
AST(col_attrs_unique)
AST(col_calc)
AST(col_calcs)
AST(col_def)
AST(col_def_name_type)
AST(col_def_type_attrs)
AST(col_key_list)
AST(collate)
AST(column_calculation)
AST(columns_values);
AST(concat);
AST(cond_action)
AST(conflict_target)
AST(connector)
AST(const_stmt)
AST(const_value)
AST(const_values)
AST(create_attr)
AST(create_index_on_list)
AST(create_index_stmt)
AST(create_proc_stmt)
AST(create_table_name_flags)
AST(create_table_stmt)
AST(create_trigger_stmt)
AST(create_view_stmt)
AST(create_virtual_table_stmt)
AST(cte_binding)
AST(cte_binding_list)
AST(cte_decl)
AST(cte_table)
AST(cte_tables)
AST(cte_tables_macro_def)
AST(cte_tables_macro_ref)
AST(declare_const_stmt)
AST(declare_cursor)
AST(declare_cursor_like_name)
AST(declare_cursor_like_select)
AST(declare_cursor_like_typed_names)
AST(declare_deployable_region_stmt);
AST(declare_enum_stmt)
AST(declare_func_no_check_stmt)
AST(declare_func_stmt)
AST(declare_group_stmt)
AST(declare_interface_stmt)
AST(declare_named_type)
AST(declare_proc_stmt)
AST(declare_schema_region_stmt);
AST(declare_select_func_no_check_stmt)
AST(declare_select_func_stmt)
AST(declare_value_cursor)
AST(declare_vars_type)
AST(delete_attr)
AST(delete_returning_stmt)
AST(delete_stmt)
AST(div)
AST(div_eq)
AST(dot)
AST(drop_index_stmt)
AST(drop_table_stmt)
AST(drop_trigger_stmt)
AST(drop_view_stmt)
AST(echo_stmt)
AST(elseif)
AST(enum_value)
AST(enum_values)
AST(eq)
AST(explain_stmt)
AST(expr_assign)
AST(expr_list)
AST(expr_macro_def)
AST(expr_macro_ref)
AST(expr_name)
AST(expr_names)
AST(fetch_call_stmt)
AST(fetch_stmt)
AST(fetch_values_stmt)
AST(fk_def)
AST(fk_info)
AST(fk_target)
AST(fk_target_options)
AST(flags_names_attrs)
AST(for_stmt)
AST(for_info)
AST(frame_boundary)
AST(frame_boundary_end)
AST(frame_boundary_opts)
AST(frame_boundary_start)
AST(from_shape);
AST(func_params_return)
AST(ge)
AST(glob)
AST(groupby_list)
AST(gt)
AST(guard_stmt)
AST(if_alt)
AST(if_stmt)
AST(ifdef_stmt)
AST(ifndef_stmt)
AST(in_pred)
AST(index_names_and_attrs)
AST(indexed_column)
AST(indexed_columns)
AST(indexed_columns_conflict_clause)
AST(insert_dummy_spec);
AST(insert_list)
AST(insert_returning_stmt)
AST(insert_stmt)
AST(is)
AST(is_not)
AST(jex1)
AST(jex2)
AST(join_clause)
AST(join_cond)
AST(join_target)
AST(join_target_list)
AST(le)
AST(let_stmt)
AST(like)
AST(loop_stmt)
AST(ls_eq)
AST(lshift)
AST(lt)
AST(macro_args)
AST(macro_formal)
AST(macro_formals)
AST(macro_name_formals)
AST(match)
AST(misc_attr)
AST(misc_attr_value_list)
AST(misc_attrs)
AST(mod)
AST(mod_eq)
AST(module_info)
AST(mul)
AST(mul_eq)
AST(name_columns_values);
AST(name_list)
AST(named_result)
AST(ne)
AST(not_between)
AST(not_glob)
AST(not_in)
AST(not_like)
AST(not_match)
AST(not_regexp)
AST(op_stmt)
AST(op_vals)
AST(opt_frame_spec)
AST(or)
AST(or_eq)
AST(orderby_item)
AST(orderby_list)
AST(out_union_parent_child_stmt)
AST(param)
AST(param_detail)
AST(params)
AST(pk_def)
AST(pre)
AST(proc_name_type)
AST(proc_params_stmts)
AST(query_parts_macro_def)
AST(query_parts_macro_ref)
AST(raise);
AST(range)
AST(recreate_attr)
AST(regexp)
AST(region_list);
AST(region_spec);
AST(reverse_apply)
AST(reverse_apply_poly_args)
AST(rs_eq)
AST(rshift)
AST(schema_ad_hoc_migration_stmt);
AST(seed_stub)
AST(select_core)
AST(select_core_compound)
AST(select_core_list)
AST(select_core_macro_def)
AST(select_core_macro_ref)
AST(select_expr)
AST(select_expr_list)
AST(select_expr_list_con)
AST(select_expr_macro_def)
AST(select_expr_macro_ref)
AST(select_from_etc)
AST(select_groupby)
AST(select_having)
AST(select_if_nothing_expr)
AST(select_if_nothing_or_null_expr)
AST(select_limit)
AST(select_offset)
AST(select_orderby)
AST(select_stmt)
AST(select_where)
AST(sensitive_attr);
AST(set_from_cursor)
AST(shape_def)
AST(shape_expr)
AST(shape_exprs)
AST(shared_cte)
AST(stmt_and_attr)
AST(stmt_list)
AST(stmt_list_macro_def)
AST(stmt_list_macro_ref);
AST(str_chain)
AST(sub)
AST(sub_eq)
AST(switch_body);
AST(switch_case);
AST(switch_stmt);
AST(table_flags_attrs);
AST(table_function);
AST(table_join);
AST(table_or_subquery);
AST(table_or_subquery_list);
AST(text_args);
AST(trigger_action);
AST(trigger_body_vers);
AST(trigger_condition);
AST(trigger_def);
AST(trigger_op_target);
AST(trigger_operation);
AST(trigger_target_action);
AST(trigger_when_stmts);
AST(trycatch_stmt)
AST(type_check_expr)
AST(typed_name)
AST(typed_names)
AST(unknown_macro_arg)
AST(unknown_macro_ref)
AST(unknown_macro_def)
AST(unq_def)
AST(update_cursor_stmt)
AST(update_entry)
AST(update_from)
AST(update_list)
AST(update_orderby)
AST(update_set)
AST(update_returning_stmt)
AST(update_stmt)
AST(update_where)
AST(upsert_returning_stmt)
AST(upsert_stmt)
AST(upsert_update)
AST(values)
AST(version_annotation)
AST(view_and_attrs)
AST(view_details)
AST(view_details_select)
AST(when)
AST(while_stmt)
AST(window_defn)
AST(window_defn_orderby)
AST(window_func_inv)
AST(window_name_defn)
AST(window_name_defn_list)
AST(with_delete_stmt)
AST(with_insert_stmt)
AST(with_select_stmt)
AST(with_update_stmt)
AST(with_upsert_stmt)
AST0(all)
AST0(col_attrs_autoinc)
AST0(commit_return_stmt);
AST0(commit_trans_stmt);
AST0(continue_stmt)
AST0(default_columns_values);
AST0(distinct)
AST0(distinctrow)
AST0(end_schema_region_stmt);
AST0(enforce_pop_stmt);
AST0(enforce_push_stmt);
AST0(enforce_reset_stmt);
AST0(following)
AST0(in)
AST0(inout)
AST0(insert_normal);
AST0(insert_or_abort);
AST0(insert_or_fail);
AST0(insert_or_ignore);
AST0(insert_or_replace);
AST0(insert_or_rollback);
AST0(insert_replace);
AST0(keep_table_name_in_aliases_stmt)
AST0(leave_stmt)
AST0(null)
AST0(nullsfirst)
AST0(nullslast)
AST0(on)
AST0(out)
AST0(previous_schema_stmt);
AST0(return_stmt)
AST0(rollback_return_stmt);
AST0(schema_upgrade_script_stmt);
AST0(select_nothing_stmt)
AST0(select_values)
AST0(star)
AST0(throw_stmt)
AST0(type_cursor)
AST0(using)
AST1(asc)
AST1(at_id);
AST1(begin_schema_region_stmt);
AST1(begin_trans_stmt);
AST1(close_stmt)
AST1(column_spec);
AST1(const)
AST1(create_data_type);
AST1(cte_tables_macro_arg);
AST1(cte_tables_macro_arg_ref)
AST1(declare_out_call_stmt)
AST1(declare_proc_no_check_stmt)
AST1(desc)
AST1(else)
AST1(emit_constants_stmt)
AST1(emit_enums_stmt)
AST1(emit_group_stmt)
AST1(enforce_normal_stmt);
AST1(enforce_strict_stmt);
AST1(exists_expr)
AST1(expr_macro_arg)
AST1(expr_macro_arg_ref)
AST1(expr_stmt)
AST1(groupby_item)
AST1(is_false)
AST1(is_not_false)
AST1(is_not_true)
AST1(is_true)
AST1(macro_text)
AST1(not)
AST1(notnull);
AST1(opt_as_alias)
AST1(opt_filter_clause)
AST1(opt_groupby)
AST1(opt_having)
AST1(opt_limit)
AST1(opt_offset)
AST1(opt_orderby)
AST1(opt_partition_by)
AST1(opt_select_window)
AST1(opt_where)
AST1(out_stmt)
AST1(out_union_stmt)
AST1(proc_savepoint_stmt);
AST1(query_parts_macro_arg);
AST1(query_parts_macro_arg_ref)
AST1(release_savepoint_stmt);
AST1(rollback_trans_stmt);
AST1(savepoint_stmt);
AST1(schema_unsub_stmt);
AST1(schema_upgrade_version_stmt);
AST1(select_core_macro_arg);
AST1(select_core_macro_arg_ref)
AST1(select_expr_macro_arg);
AST1(select_expr_macro_arg_ref)
AST1(select_if_nothing_throw_expr)
AST1(select_if_nothing_or_null_throw_expr)
AST1(select_opts)
AST1(stmt_list_macro_arg);
AST1(stmt_list_macro_arg_ref);
AST1(table_star)
AST1(tilde)
AST1(type_blob)
AST1(type_bool)
AST1(type_int)
AST1(type_long)
AST1(type_object)
AST1(type_real)
AST1(type_text)
AST1(uminus)
AST1(unknown_macro_arg_ref)
AST1(window_clause)
AST1(with)
AST1(with_recursive)

#ifndef _MSC_VER
#pragma clang diagnostic pop
#endif