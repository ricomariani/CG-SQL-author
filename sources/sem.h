/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

typedef uint64_t sem_t;

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)

// minimal stuff goes here

cql_noexport void sem_main(CS, ast_node *node);
cql_noexport void sem_cleanup(CS);
cql_noexport void print_sem_type(CS, struct sem_node *sem);

#else

#include "cql.h"
#include "ast.h"
#include "bytebuf.h"
#include "symtab.h"
#include "charbuf.h"
#include "list.h"

//
// The key semantic type information
//
// The rules:
//   * if sem_type is STRUCT then sptr is not null
//   * if sem_type is JOIN then jptr is not null
//   * if node is on a table or a view element, which is a STRUCT
//     then jptr is also not null as an optimization
//   * in all other cases neither is populated
//
// Tables and Views have both their sptr and jptr filled out
// because the first thing you're going to do with a table/view is
// join it to something and so the base case of a 1 table join happens
// all the time.  To make this easier that jptr is pre-populated as
// an optimization.
//

// @lint-ignore-every LINEWRAP

#define sem_not(x) u64_not(x)

typedef struct table_node {
  int64_t type_hash;                // if the type has hash code, this will be it
  list_item *_Nullable index_list;            // the list of indices that use this table (so we can recreate them together if needed)
  int16_t key_count;                // number of key columns
  int16_t *_Nullable key_cols;                // the key column indices (ast allocated)
  int16_t notnull_count;            // number of notnull columns
  int16_t *_Nullable notnull_cols;            // the notnull column indices (ast allocated)
  int16_t value_count  ;            // number of value (non-key) columns
  int16_t *_Nullable value_cols;              // the non-key column indices (ast allocated)
} table_node;

typedef struct sem_node {
  sem_t sem_type;                   // core type plus flags
  CSTR _Nonnull name;                        // for named expressions in select columns etc.
  CSTR _Nonnull kind;                        // the Foo in object<Foo>, not a variable or column name
  CSTR _Nullable error;                       // error text for test output, not used otherwise
  CSTR _Nullable backed_table;                // if this is a column in a backed table, the name of that table
  struct sem_struct *_Nullable sptr;          // encoded struct if any
  struct sem_join *_Nullable jptr;            // encoded join if any
  int32_t create_version;           // create version if any (really only for tables and columns)
  int32_t delete_version;           // delete version if any (really only for tables and columns)
  bool_t unsubscribed;              // true if unsubscribed (applies only to tables or views)
  bool_t recreate;                  // for tables only, true if marked @recreate
  CSTR _Nullable recreate_group_name;         // for tables only, the name of the recreate group if they are in one
  CSTR _Nullable region;                      // the schema region, if applicable; null means unscoped (default)
  symtab *_Nullable used_symbols;             // for select statements, we need to know which of the ids in the select list was used, if any
  struct eval_node *_Nullable value;          // for enum values we have to store the evaluated constant value of each member of the enum
  table_node *_Nullable table_info;           // extra info unique to tables (above)
} sem_node;

// for tables and views and the result of a select

typedef struct sem_struct {
  CSTR _Nonnull struct_name;               // struct name
  uint32_t count;                 // count of fields
  CSTR _Nonnull*_Nonnull names;                    // field names
  CSTR _Nonnull*_Nonnull kinds;                    // the "kind" text of each column, if any, e.g. integer<foo> foo is the kind
  sem_t *_Nonnull semtypes;                // typecode for each field
  bool_t is_backed;               // original backed table source
} sem_struct;

// for the data type of (parts of) the FROM clause
// sometimes I refer to as a "joinscope"

typedef struct sem_join {
  uint32_t count;                 // count of table/views in the join
  CSTR _Nonnull*_Nonnull names;                    // names of the table/view
  struct sem_struct *_Nonnull*_Nonnull tables;     // struct type of each table/view
} sem_join;

typedef struct recreate_annotation {
  CSTR _Nonnull target_name;               // the name of the target
  CSTR _Nonnull group_name;                // group name or "" if no group (not null, safe to sort)
  ast_node *_Nonnull target_ast;           // top level target (table, view, or index)
  ast_node *_Nonnull annotation_ast;       // the actual annotation
  int32_t ordinal;                // when sorting we want to use the original order (reversed actually) within a group
  int32_t group_ordinal;          // when sorting we want to use the group ordinal that we will obtain from a topological sort on recreate group dependency tree
} recreate_annotation;

typedef struct schema_annotation {
  int32_t ordinal;                // this will be the original annotation order
  int32_t version;                // the version number (always > 0)
  ast_node *_Nonnull target_ast;           // top level target (table, view, or index)
  CSTR _Nonnull target_name;               // the name of the target
  uint32_t annotation_type;       // one of the codes below for the type of annotation
  ast_node *_Nonnull annotation_ast;       // the actual annotation
  int32_t column_ordinal;         // -1 if not a column
  ast_node *_Nullable column_ast;           // a particular column if column annotation
} schema_annotation;

// Note: schema annotations are processed in the indicated order: the numbers matter!
#define SCHEMA_ANNOTATION_INVALID 0
#define SCHEMA_ANNOTATION_FIRST 1
#define SCHEMA_ANNOTATION_UNSUB 1
#define SCHEMA_ANNOTATION_CREATE_TABLE 2
#define SCHEMA_ANNOTATION_CREATE_COLUMN 3
#define SCHEMA_ANNOTATION_DELETE_TRIGGER 4
#define SCHEMA_ANNOTATION_DELETE_VIEW 5
#define SCHEMA_ANNOTATION_DELETE_INDEX 6
#define SCHEMA_ANNOTATION_DELETE_COLUMN 7
#define SCHEMA_ANNOTATION_DELETE_TABLE 8
#define SCHEMA_ANNOTATION_AD_HOC 9
#define SCHEMA_ANNOTATION_LAST 9

#define SEM_TYPE_NULL 0         // the subtree is a null literal (not just nullable)
#define SEM_TYPE_BOOL 1         // the subtree is a bool
#define SEM_TYPE_INTEGER 2      // the subtree is an integer
#define SEM_TYPE_LONG_INTEGER 3 // the subtree is a long_integer
#define SEM_TYPE_REAL 4         // the subtree is a real
#define SEM_TYPE_TEXT 5         // the subtree is a text type
#define SEM_TYPE_BLOB 6         // the subtree is a blob type
#define SEM_TYPE_OBJECT 7       // the subtree is any object type
#define SEM_TYPE_STRUCT 8       // the subtree is a table/view
#define SEM_TYPE_JOIN 9         // the subtree is a join
#define SEM_TYPE_ERROR 10       // marks the subtree as having a problem
#define SEM_TYPE_OK 11          // sentinel for ok but no type info
#define SEM_TYPE_PENDING 12     // sentinel for type calculation in flight
#define SEM_TYPE_REGION 13      // the ast is a schema region
#define SEM_TYPE_CURSOR_FORMAL 14 // this is used for the cursor parameter type uniquely
#define SEM_TYPE_CORE 0xff      // bit mask for the core types

#define SEM_TYPE_MAX_UNITARY (SEM_TYPE_OBJECT+1) // the last unitary type

#define SEM_TYPE_NOTNULL               _64(0x0100) // set if and only if null is not possible
#define SEM_TYPE_HAS_DEFAULT           _64(0x0200) // set for table columns with a default
#define SEM_TYPE_AUTOINCREMENT         _64(0x0400) // set for table columns with autoinc
#define SEM_TYPE_VARIABLE              _64(0x0800) // set for variables and parameters
#define SEM_TYPE_IN_PARAMETER          _64(0x1000) // set for in parameters (can mix with below)
#define SEM_TYPE_OUT_PARAMETER         _64(0x2000) // set for out parameters (can mix with above)
#define SEM_TYPE_DML_PROC              _64(0x4000) // set for stored procs that have DML/DDL
#define SEM_TYPE_HAS_SHAPE_STORAGE     _64(0x8000) // set for a cursor with simplified fetch syntax
#define SEM_TYPE_CREATE_FUNC          _64(0x10000) // set for a function that returns a created object +1 ref
#define SEM_TYPE_SELECT_FUNC          _64(0x20000) // set for a sqlite UDF function declaration
#define SEM_TYPE_DELETED              _64(0x40000) // set for columns that are not visible in the current schema version
#define SEM_TYPE_VALIDATED            _64(0x80000) // set if item has already been validated against previous schema
#define SEM_TYPE_USES_OUT            _64(0x100000) // set if proc has a one rowresult using the OUT statement
#define SEM_TYPE_USES_OUT_UNION      _64(0x200000) // set if proc uses the OUT UNION form for multi row result
#define SEM_TYPE_PK                  _64(0x400000) // set if column is a primary key
#define SEM_TYPE_FK                  _64(0x800000) // set if column is a foreign key
#define SEM_TYPE_UK                 _64(0x1000000) // set if column is a unique key
#define SEM_TYPE_VALUE_CURSOR       _64(0x2000000) // set only if SEM_TYPE_HAS_SHAPE_STORAGE is set and the cursor has no statement
#define SEM_TYPE_SENSITIVE          _64(0x4000000) // set if the object is privacy sensitive
#define SEM_TYPE_DEPLOYABLE         _64(0x8000000) // set if the object is a deployable region
#define SEM_TYPE_BOXED             _64(0x10000000) // set if a cursor's lifetime is managed by a box object
#define SEM_TYPE_HAS_CHECK         _64(0x20000000) // set for table column with a "check" clause
#define SEM_TYPE_HAS_COLLATE       _64(0x40000000) // set for table column with a "collate" clause
#define SEM_TYPE_INFERRED_NOTNULL  _64(0x80000000) // set if inferred to not be nonnull (but was originally nullable)
#define SEM_TYPE_VIRTUAL          _64(0x100000000) // set if and only if this is a virtual table
#define SEM_TYPE_HIDDEN_COL       _64(0x200000000) // set if and only if hidden column on a virtual table
#define SEM_TYPE_TVF              _64(0x400000000) // set if and only table node is a table valued function
#define SEM_TYPE_IMPLICIT         _64(0x800000000) // set if and only the variable was declare implicitly (via declare out)
#define SEM_TYPE_CALLS_OUT_UNION _64(0x1000000000) // set if proc calls an out union proc for a result
#define SEM_TYPE_ALIAS           _64(0x2000000000) // set only for aliases of a select when analyzing its where clause
#define SEM_TYPE_INIT_REQUIRED   _64(0x4000000000) // set for variables that require initialization before use
#define SEM_TYPE_INIT_COMPLETE   _64(0x8000000000) // set when SEM_TYPE_INIT_REQUIRED is present to indicate initialization
#define SEM_TYPE_INLINE_CALL    _64(0x10000000000) // set when a proc_as_func call in SQL can be executed safely by inlining the SQL
#define SEM_TYPE_SERIALIZE      _64(0x20000000000) // set when a cursor will need serialization features
#define SEM_TYPE_HAS_ROW        _64(0x40000000000) // set on auto cursors to indicate that they are known to have a row
#define SEM_TYPE_FETCH_INTO     _64(0x80000000000) // set if the cursor is used with fetch into
#define SEM_TYPE_WAS_SET       _64(0x100000000000) // set on in args if they are set (hence we own the value)
#define SEM_TYPE_BACKING       _64(0x200000000000) // set on tables that are used for backing store
#define SEM_TYPE_BACKED        _64(0x400000000000) // set on tables/exprs that have a backing store
#define SEM_TYPE_PARTIAL_PK    _64(0x800000000000) // set if column is a primary key
#define SEM_TYPE_QID          _64(0x1000000000000) // set if column has a `quoted` name
#define SEM_TYPE_CONSTANT     _64(0x2000000000000) // set for variables marked immutable and cannot be reassigned
#define SEM_TYPE_FLAGS        _64(0x3FFFFFFFFFF00) // all the flag bits we have so far

#define SEM_EXPR_CONTEXT_NONE           0x0001
#define SEM_EXPR_CONTEXT_SELECT_LIST    0x0002
#define SEM_EXPR_CONTEXT_WHERE          0x0004
#define SEM_EXPR_CONTEXT_ON             0x0008
#define SEM_EXPR_CONTEXT_HAVING         0x0010
#define SEM_EXPR_CONTEXT_ORDER_BY       0x0020
#define SEM_EXPR_CONTEXT_GROUP_BY       0x0040
#define SEM_EXPR_CONTEXT_LIMIT          0x0080
#define SEM_EXPR_CONTEXT_OFFSET         0x0100
#define SEM_EXPR_CONTEXT_UDF            0x0200
#define SEM_EXPR_CONTEXT_WINDOW         0x0400
#define SEM_EXPR_CONTEXT_WINDOW_FILTER  0x0800
#define SEM_EXPR_CONTEXT_CONSTRAINT     0x1000
#define SEM_EXPR_CONTEXT_FLAGS          0x1FFF // all the flag bits

#define CURRENT_EXPR_CONTEXT_IS(x)  (!!(CS->sem.current_expr_context & (x)))
#define CURRENT_EXPR_CONTEXT_IS_NOT(x)  (!(CS->sem.current_expr_context & (x)))

cql_noexport sem_t core_type_of(sem_t sem_type);
cql_noexport sem_t sensitive_flag(sem_t sem_type);
cql_noexport CSTR _Nullable coretype_string(sem_t sem_type);

cql_noexport bool_t is_virtual_ast(ast_node *_Nonnull ast);
cql_noexport bool_t is_deleted(ast_node *_Nonnull ast);
cql_noexport bool_t is_single_flag(sem_t sem_type);
cql_noexport bool_t is_bool(sem_t sem_type);
cql_noexport bool_t is_real(sem_t sem_type);
cql_noexport bool_t is_string_compat(sem_t sem_type);
cql_noexport bool_t is_blob_compat(sem_t sem_type);
cql_noexport bool_t is_object_compat(sem_t sem_type);
cql_noexport bool_t is_create_func(sem_t sem_type);
cql_noexport bool_t is_long(sem_t sem_type);
cql_noexport bool_t is_any_int(sem_t sem_type);
cql_noexport bool_t is_numeric(sem_t sem_type);
cql_noexport bool_t is_numeric_compat(sem_t sem_type);
cql_noexport bool_t is_numeric_expr(ast_node *_Nonnull expr);
cql_noexport bool_t is_unitary(sem_t sem_type);
cql_noexport bool_t is_struct(sem_t sem_type);
cql_noexport bool_t is_cursor(sem_t sem_type);
cql_noexport bool_t is_auto_cursor(sem_t sem_type);
cql_noexport bool_t is_primary_key(sem_t sem_type);
cql_noexport bool_t is_partial_pk(sem_t sem_type);
cql_noexport bool_t is_foreign_key(sem_t sem_type);
cql_noexport bool_t is_sem_error(sem_node *_Nonnull sem);
cql_noexport bool_t is_error(ast_node *_Nonnull ast);
cql_noexport bool_t is_not_nullable(sem_t sem_type);
cql_noexport bool_t is_variable(sem_t sem_type);
cql_noexport bool_t is_in_parameter(sem_t sem_type);
cql_noexport bool_t is_out_parameter(sem_t sem_type);
cql_noexport bool_t is_cursor_formal(sem_t sem_type);
cql_noexport bool_t was_set_variable(sem_t sem_type);
cql_noexport bool_t is_backing(sem_t sem_type);
cql_noexport bool_t is_backed(sem_t sem_type);
cql_noexport bool_t is_inout_parameter(sem_t sem_type);
cql_noexport bool_t is_dml_proc(sem_t sem_type);
cql_noexport bool_t is_text(sem_t sem_type);
cql_noexport bool_t is_blob(sem_t sem_type);
cql_noexport bool_t is_object(sem_t sem_type);
cql_noexport bool_t is_ref_type(sem_t sem_type);
cql_noexport bool_t is_inferred_notnull(sem_t sem_type);
cql_noexport bool_t is_nullable(sem_t sem_type);
cql_noexport bool_t is_null_type(sem_t sem_type);
cql_noexport bool_t is_constant(sem_t sem_type);
cql_noexport bool_t has_result_set(ast_node *_Nonnull ast);
cql_noexport bool_t has_out_stmt_result(ast_node *_Nonnull ast);
cql_noexport bool_t has_out_union_call(ast_node *_Nonnull ast);
cql_noexport bool_t has_out_union_stmt_result(ast_node *_Nonnull ast);
cql_noexport bool_t is_autotest_dummy_table(CSTR _Nonnull name);
cql_noexport bool_t is_autotest_dummy_insert(CSTR _Nonnull name);
cql_noexport bool_t is_autotest_dummy_select(CSTR _Nonnull name);
cql_noexport bool_t is_autotest_dummy_result_set(CSTR _Nonnull name);
cql_noexport bool_t is_autotest_dummy_test(CSTR _Nonnull name);
cql_noexport bool_t is_referenceable_by_foreign_key(CqlState* _Nonnull CS, ast_node *_Nonnull ref_table, CSTR _Nonnull column_name);
cql_noexport bool_t is_inline_func_call(ast_node *_Nonnull call_ast);
cql_noexport bool_t is_proc_private(CqlState* _Nonnull CS, ast_node *_Nonnull proc_stmt);
cql_noexport bool_t is_proc_suppress_result_set(CqlState* _Nonnull CS, ast_node *_Nonnull proc_stmt);
cql_noexport bool_t is_proc_suppress_getters(CqlState* _Nonnull CS, ast_node *_Nonnull proc_stmt);
cql_noexport bool_t is_proc_emit_setters(CqlState* _Nonnull CS, ast_node *_Nonnull proc_stmt);
cql_noexport bool_t is_proc_shared_fragment(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport bool_t is_alias_ast(ast_node *_Nonnull ast);
cql_noexport CSTR _Nullable get_inserted_table_alias_string_override(ast_node *_Nonnull ast);

cql_noexport ast_node*_Nonnull new_str_or_qstr(CqlState* _Nonnull CS, CSTR _Nonnull name, sem_t sem_type);
cql_noexport CSTR _Nonnull sem_get_name(ast_node *_Nonnull ast);
cql_noexport ast_node *_Nonnull sem_get_name_ast(ast_node *_Nonnull ast);
cql_noexport CSTR _Nonnull create_group_id(CqlState* _Nonnull CS, CSTR _Nonnull group_name, CSTR _Nonnull table_name);

// Exit if schema validation directive was seen
cql_noexport void exit_on_validating_schema(CqlState* _Nonnull CS);

cql_noexport void sem_main(CqlState* _Nonnull CS, ast_node *_Nonnull node);
cql_noexport void sem_cleanup(CqlState* _Nonnull CS);
cql_noexport void print_sem_type(CqlState* _Nonnull CS, struct sem_node *_Nonnull sem);
cql_noexport int32_t sem_column_index(sem_struct *_Nonnull sptr, CSTR _Nonnull name);

cql_noexport ast_node *_Nullable find_proc(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport bytebuf *_Nullable find_proc_arg_info(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_local_or_global_variable(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_region(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_func(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_unchecked_func(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_table_or_view_even_deleted(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_usable_and_not_deleted_table_or_view(CqlState* _Nonnull CS, CSTR _Nonnull name, ast_node *_Nullable err_target, CSTR _Nullable msg);
cql_noexport symtab *_Nullable find_default_values(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport bool_t add_default_values(CqlState* _Nonnull CS, symtab *_Nonnull def_values, CSTR _Nonnull name);
cql_noexport void sem_resolve_id(CqlState* _Nonnull CS, ast_node *_Nonnull ast, CSTR _Nonnull name, CSTR _Nullable scope);
cql_noexport ast_node *_Nullable find_enum(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_recreate_migrator(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_constant_group(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_variable_group(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable find_constant(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport int32_t find_col_in_sptr(sem_struct *_Nonnull sptr, CSTR _Nonnull name);
cql_noexport ast_node *_Nullable sem_get_col_default_value(ast_node *_Nonnull attrs);
cql_noexport void sem_accumulate_full_region_image(CqlState* _Nonnull CS, symtab *_Nonnull regions, CSTR _Nonnull name);
cql_noexport void sem_accumulate_public_region_image(CqlState* _Nonnull CS, symtab *_Nonnull regions, CSTR _Nonnull name);
cql_noexport sem_t find_column_type(CqlState* _Nonnull CS, CSTR _Nonnull table_name, CSTR _Nonnull column_name);
cql_noexport void init_encode_info(CqlState* _Nonnull CS, ast_node *_Nonnull misc_attrs, bool_t *_Nonnull use_encode_arg, CSTR _Nonnull*_Nonnull encode_context_column_arg, symtab *_Nonnull encode_columns_arg);
cql_noexport bool_t should_encode_col(CSTR _Nonnull col, sem_t sem_type, bool_t use_encode_arg, symtab *_Nonnull encode_columns_arg);

#define LIKEABLE_FOR_ARGS   1
#define LIKEABLE_FOR_VALUES 2

cql_noexport ast_node *_Nullable sem_find_shape_def(CqlState* _Nonnull CS, ast_node *_Nonnull shape_def, int32_t likeable_for);
cql_noexport ast_node *_Nullable sem_find_shape_def_base(CqlState* _Nonnull CS, ast_node *_Nonnull like_ast, int32_t likeable_for);
cql_noexport ast_node *_Nullable sem_find_likeable_from_expr_type(CqlState* _Nonnull CS, ast_node *_Nonnull var);
cql_noexport ast_node *_Nullable find_named_type(CqlState* _Nonnull CS, CSTR _Nonnull name);

cql_noexport void record_error(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport void record_ok(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport void report_error(CqlState* _Nonnull CS, ast_node *_Nonnull ast, CSTR _Nonnull msg, CSTR _Nullable subject);
cql_noexport void sem_one_stmt(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport void sem_root_expr(CqlState* _Nonnull CS, ast_node *_Nonnull node, uint32_t expr_context);
cql_noexport void sem_expr(CqlState* _Nonnull CS, ast_node *_Nonnull node);
cql_noexport void sem_cursor(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport ast_node *_Nullable find_arg_bundle(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport bool_t add_arg_bundle(CqlState* _Nonnull CS, ast_node *_Nonnull ast, CSTR _Nonnull name);
cql_noexport void sem_add_flags(CqlState* _Nonnull CS, ast_node *_Nonnull ast, sem_t flags);
cql_noexport ast_node *_Nullable first_arg(ast_node *_Nonnull arg_list);
cql_noexport ast_node *_Nullable second_arg(ast_node *_Nonnull arg_list);
cql_noexport ast_node *_Nullable third_arg(ast_node *_Nonnull arg_list);
cql_noexport void sem_verify_no_anon_no_null_columns(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport void sem_verify_identical_columns(CqlState* _Nonnull CS, ast_node *_Nonnull expected, ast_node *_Nonnull actual, CSTR _Nonnull target);
cql_noexport void sem_validate_cursor_blob_compat(CqlState* _Nonnull CS, ast_node *_Nonnull ast_error, ast_node *_Nonnull cursor, ast_node *_Nonnull blob, ast_node *_Nonnull dest, ast_node *_Nonnull src);
cql_noexport void sem_any_shape(CqlState* _Nonnull CS, ast_node *_Nonnull ast);
cql_noexport sem_node *_Nonnull new_sem(CqlState* _Nonnull CS, sem_t sem_type);
cql_noexport bool_t sem_verify_assignment(CqlState* _Nonnull CS, ast_node *_Nonnull ast, sem_t sem_type_needed, sem_t sem_type_found, CSTR _Nonnull var_name);
cql_noexport void sem_select(CqlState* _Nonnull CS, ast_node *_Nonnull node);
cql_noexport ast_node *_Nonnull sem_recover_with_stmt(ast_node *_Nonnull ast);
cql_noexport ast_node *_Nonnull sem_skip_with(ast_node *_Nonnull ast);
cql_noexport bool_t is_table_not_physical(CqlState* _Nonnull CS, ast_node *_Nonnull table_ast);

#endif

// the current chain of common table expressions (for WITH clauses)
typedef struct cte_state {
  struct cte_state *_Nullable prev;
  symtab *_Nonnull ctes;
} cte_state;

//cql_data_decl( bytebuf *CS->sem.schema_annotations );
//cql_data_decl( bytebuf *CS->sem.recreate_annotations );

//cql_data_decl( struct list_item *CS->sem.all_tables_list );
//cql_data_decl( struct list_item *CS->sem.all_subscriptions_list );
//cql_data_decl( struct list_item *CS->sem.all_functions_list );
//cql_data_decl( struct list_item *CS->sem.all_views_list );
//cql_data_decl( struct list_item *CS->sem.all_indices_list );
//cql_data_decl( struct list_item *CS->sem.all_triggers_list );
//cql_data_decl( struct list_item *CS->sem.all_regions_list );
//cql_data_decl( struct list_item *CS->sem.all_ad_hoc_list );
//cql_data_decl( struct list_item *CS->sem.all_select_functions_list );
//cql_data_decl( struct list_item *CS->sem.all_enums_list );
//cql_data_decl( struct list_item *CS->sem.all_constant_groups_list );
//cql_data_decl( symtab *CS->sem.schema_regions );
//cql_data_decl( ast_node *CS->sem.current_proc );
//cql_data_decl( charbuf *CS->sem.error_capture );
//cql_data_decl( cte_state *CS->sem.cte_cur );
//cql_data_decl( symtab *CS->sem.ref_sources_for_target_table );
//cql_data_decl( symtab *CS->sem.ref_targets_for_source_table );

// True if we are presently emitting a vault stored proc.
// A stored proc with attribution vault_sensitive is a vault stored proc
//cql_data_decl( bool_t CS->sem.use_encode );
//cql_data_decl( CSTR CS->sem.encode_context_column );

// List of column names reference in a stored proc that we should vault
//cql_data_decl( symtab *CS->sem.encode_columns );

// These are the symbol tables with the accumulated included/excluded regions
//cql_data_decl( symtab *CS->sem.included_regions );
//cql_data_decl( symtab *CS->sem.excluded_regions );
//cql_data_decl( sem_t CS->sem.global_proc_flags );

// This is the table for all the migration procs for any recreate procs or groups
// that might need them, these are the second form of ad hoc schema migration
//cql_data_decl( symtab *CS->sem.ad_hoc_recreate_actions );

// If the current context is a upsert statement
//cql_data_decl( bool_t CS->sem.in_upsert );
//cql_data_decl( bool_t CS->sem.in_upsert_rewrite );

// hold the table ast query in the current upsert statement.
//cql_data_decl ( ast_node *CS->sem.current_upsert_table_ast );
// This is the symbol table with the recreate group dependencies where an edge B -> A means A FKs to B
//cql_data_decl( symtab *CS->sem.recreate_group_deps );

// Truthy when the @keep_table_name_in_aliases_stmt directive is used.
//cql_data_decl( bool_t CS->sem.keep_table_name_in_aliases );
