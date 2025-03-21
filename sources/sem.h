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

cql_noexport void sem_main(ast_node *node);
cql_noexport void sem_cleanup(void);
cql_noexport void print_sem_type(struct sem_node *sem);

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
  list_item *index_list;            // the list of indices that use this table (so we can recreate them together if needed)
  int16_t key_count;                // number of key columns
  int16_t *key_cols;                // the key column indices (ast allocated)
  int16_t notnull_count;            // number of notnull columns
  int16_t *notnull_cols;            // the notnull column indices (ast allocated)
  int16_t value_count  ;            // number of value (non-key) columns
  int16_t *value_cols;              // the non-key column indices (ast allocated)
} table_node;

typedef struct sem_node {
  sem_t sem_type;                   // core type plus flags
  CSTR name;                        // for named expressions in select columns etc.
  CSTR kind;                        // the Foo in object<Foo>, not a variable or column name
  CSTR error;                       // error text for test output, not used otherwise
  CSTR backed_table;                // if this is a column in a backed table, the name of that table
  struct sem_struct *sptr;          // encoded struct if any
  struct sem_join *jptr;            // encoded join if any
  int32_t create_version;           // create version if any (really only for tables and columns)
  int32_t delete_version;           // delete version if any (really only for tables and columns)
  bool_t unsubscribed;              // true if unsubscribed (applies only to tables or views)
  bool_t recreate;                  // for tables only, true if marked @recreate
  CSTR recreate_group_name;         // for tables only, the name of the recreate group if they are in one
  CSTR region;                      // the schema region, if applicable; null means unscoped (default)
  symtab *used_symbols;             // for select statements, we need to know which of the ids in the select list was used, if any
  struct eval_node *value;          // for enum values we have to store the evaluated constant value of each member of the enum
  table_node *table_info;           // extra info unique to tables (above)
} sem_node;

// for tables and views and the result of a select

typedef struct sem_struct {
  CSTR struct_name;               // struct name
  uint32_t count;                 // count of fields
  CSTR *names;                    // field names
  CSTR *kinds;                    // the "kind" text of each column, if any, e.g. integer<foo> foo is the kind
  sem_t *semtypes;                // typecode for each field
  bool_t is_backed;               // original backed table source
} sem_struct;

// for the data type of (parts of) the FROM clause
// sometimes I refer to as a "joinscope"

typedef struct sem_join {
  uint32_t count;                 // count of table/views in the join
  CSTR *names;                    // names of the table/view
  struct sem_struct **tables;     // struct type of each table/view
} sem_join;

typedef struct recreate_annotation {
  CSTR target_name;               // the name of the target
  CSTR group_name;                // group name or "" if no group (not null, safe to sort)
  ast_node *target_ast;           // top level target (table, view, or index)
  ast_node *annotation_ast;       // the actual annotation
  int32_t ordinal;                // when sorting we want to use the original order (reversed actually) within a group
  int32_t group_ordinal;          // when sorting we want to use the group ordinal that we will obtain from a topological sort on recreate group dependency tree
} recreate_annotation;

typedef struct schema_annotation {
  int32_t ordinal;                // this will be the original annotation order
  int32_t version;                // the version number (always > 0)
  ast_node *target_ast;           // top level target (table, view, or index)
  CSTR target_name;               // the name of the target
  uint32_t annotation_type;       // one of the codes below for the type of annotation
  ast_node *annotation_ast;       // the actual annotation
  int32_t column_ordinal;         // -1 if not a column
  ast_node *column_ast;           // a particular column if column annotation
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

// All `sem_try_resolve_*` functions return either `SEM_RESOLVE_CONTINUE` to
// indicate that another resolver should be tried, or `SEM_RESOLVE_STOP` to
// indicate that the correct resolver was found. Continuing implies that no
// failure has (yet) occurred, but stopping implies neither success nor failure.
typedef enum {
  SEM_RESOLVE_CONTINUE = 0,
  SEM_RESOLVE_STOP = 1
} sem_resolve;

cql_noexport sem_t core_type_of(sem_t sem_type);
cql_noexport sem_t sensitive_flag(sem_t sem_type);
cql_noexport CSTR coretype_string(sem_t sem_type);

cql_noexport bool_t is_virtual_ast(ast_node *ast);
cql_noexport bool_t is_deleted(ast_node *ast);
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
cql_noexport bool_t is_numeric_expr(ast_node *expr);
cql_noexport bool_t is_unitary(sem_t sem_type);
cql_noexport bool_t is_struct(sem_t sem_type);
cql_noexport bool_t is_cursor(sem_t sem_type);
cql_noexport bool_t is_auto_cursor(sem_t sem_type);
cql_noexport bool_t is_primary_key(sem_t sem_type);
cql_noexport bool_t is_partial_pk(sem_t sem_type);
cql_noexport bool_t is_foreign_key(sem_t sem_type);
cql_noexport bool_t is_sem_error(sem_node *sem);
cql_noexport bool_t is_error(ast_node *ast);
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
cql_noexport bool_t has_result_set(ast_node *ast);
cql_noexport bool_t has_out_stmt_result(ast_node *ast);
cql_noexport bool_t has_out_union_call(ast_node *ast);
cql_noexport bool_t has_out_union_stmt_result(ast_node *ast);
cql_noexport bool_t is_autotest_dummy_table(CSTR name);
cql_noexport bool_t is_autotest_dummy_insert(CSTR name);
cql_noexport bool_t is_autotest_dummy_select(CSTR name);
cql_noexport bool_t is_autotest_dummy_result_set(CSTR name);
cql_noexport bool_t is_autotest_dummy_test(CSTR name);
cql_noexport bool_t is_referenceable_by_foreign_key(ast_node *ref_table, CSTR column_name);
cql_noexport bool_t is_inline_func_call(ast_node *call_ast);
cql_noexport bool_t is_proc_private(ast_node *proc_stmt);
cql_noexport bool_t is_proc_suppress_result_set(ast_node *proc_stmt);
cql_noexport bool_t is_proc_suppress_getters(ast_node *proc_stmt);
cql_noexport bool_t is_proc_emit_setters(ast_node *proc_stmt);
cql_noexport bool_t is_proc_shared_fragment(ast_node *ast);
cql_noexport bool_t is_alias_ast(ast_node *ast);
cql_noexport CSTR get_inserted_table_alias_string_override(ast_node *ast);

cql_noexport ast_node *new_maybe_qstr(CSTR name);
cql_noexport ast_node* new_str_or_qstr(CSTR name, sem_t sem_type);
cql_noexport CSTR sem_get_name(ast_node *ast);
cql_noexport ast_node *sem_get_name_ast(ast_node *ast);
cql_noexport CSTR create_group_id(CSTR group_name, CSTR table_name);

// Exit if schema validation directive was seen
cql_noexport void exit_on_validating_schema(void);

cql_noexport void sem_main(ast_node *node);
cql_noexport void sem_cleanup(void);
cql_noexport void print_sem_type(struct sem_node *sem);
cql_noexport int32_t sem_column_index(sem_struct *sptr, CSTR name);

cql_noexport ast_node *find_proc(CSTR name);
cql_noexport bytebuf *find_proc_arg_info(CSTR name);
cql_noexport ast_node *find_local_or_global_variable(CSTR name);
cql_noexport ast_node *find_region(CSTR name);
cql_noexport struct cg_blob_mappings_struct *find_backing_info(CSTR name);
cql_noexport CSTR find_op(CSTR op_key);
cql_noexport ast_node *find_func(CSTR name);
cql_noexport ast_node *find_unchecked_func(CSTR name);
cql_noexport ast_node *find_table_or_view_even_deleted(CSTR name);
cql_noexport ast_node *find_usable_and_not_deleted_table_or_view(CSTR name, ast_node *err_target, CSTR msg);
cql_noexport symtab *find_default_values(CSTR name);
cql_noexport bool_t add_default_values(symtab *def_values, CSTR name);
cql_noexport void sem_resolve_id(ast_node *ast, CSTR name, CSTR scope);
cql_noexport ast_node *find_enum(CSTR name);
cql_noexport ast_node *find_recreate_migrator(CSTR name);
cql_noexport ast_node *find_constant_group(CSTR name);
cql_noexport ast_node *find_variable_group(CSTR name);
cql_noexport ast_node *find_constant(CSTR name);
cql_noexport int32_t find_col_in_sptr(sem_struct *sptr, CSTR name);
cql_noexport ast_node *sem_get_col_default_value(ast_node *attrs);
cql_noexport void sem_accumulate_full_region_image(symtab *regions, CSTR name);
cql_noexport void sem_accumulate_public_region_image(symtab *regions, CSTR name);
cql_noexport sem_t find_column_type(CSTR table_name, CSTR column_name);

#define LIKEABLE_FOR_ARGS   1
#define LIKEABLE_FOR_VALUES 2

cql_noexport ast_node *sem_find_shape_def(ast_node *shape_def, int32_t likeable_for);
cql_noexport ast_node *sem_find_shape_def_base(ast_node *like_ast, int32_t likeable_for);
cql_noexport ast_node *sem_find_likeable_from_expr_type(ast_node *var);
cql_noexport ast_node *find_named_type(CSTR name);

cql_noexport void record_error(ast_node *ast);
cql_noexport void record_ok(ast_node *ast);
cql_noexport void report_error(ast_node *ast, CSTR msg, CSTR subject);
cql_noexport void sem_one_stmt(ast_node *ast);
cql_noexport void sem_root_expr(ast_node *node, uint32_t expr_context);
cql_noexport void sem_expr(ast_node *node);
cql_noexport void sem_cursor(ast_node *ast);
cql_noexport ast_node *find_arg_bundle(CSTR name);
cql_noexport bool_t add_arg_bundle(ast_node *ast, CSTR name);
cql_noexport void sem_add_flags(ast_node *ast, sem_t flags);
cql_noexport ast_node *first_arg(ast_node *arg_list);
cql_noexport ast_node *second_arg(ast_node *arg_list);
cql_noexport ast_node *third_arg(ast_node *arg_list);
cql_noexport void sem_verify_no_anon_no_null_columns(ast_node *ast);
cql_noexport void sem_verify_identical_columns(ast_node *expected, ast_node *actual, CSTR target);
cql_noexport void sem_validate_cursor_blob_compat(ast_node *ast_error, ast_node *cursor, ast_node *blob, ast_node *dest, ast_node *src);
cql_noexport void sem_any_shape(ast_node *ast);
cql_noexport sem_node *new_sem(sem_t sem_type);
cql_noexport bool_t sem_verify_assignment(ast_node *ast, sem_t sem_type_needed, sem_t sem_type_found, CSTR var_name);
cql_noexport void sem_any_row_source(ast_node *node);
cql_noexport ast_node *sem_recover_with_stmt(ast_node *ast);
cql_noexport ast_node *sem_skip_with(ast_node *ast);
cql_noexport bool_t is_table_not_physical(ast_node *table_ast);

#endif

// the current chain of common table expressions (for WITH clauses)
typedef struct cte_state {
  struct cte_state *prev;
  symtab *ctes;
} cte_state;

cql_data_decl( bytebuf *schema_annotations );
cql_data_decl( bytebuf *recreate_annotations );

cql_data_decl( struct list_item *all_tables_list );
cql_data_decl( struct list_item *all_subscriptions_list );
cql_data_decl( struct list_item *all_functions_list );
cql_data_decl( struct list_item *all_views_list );
cql_data_decl( struct list_item *all_indices_list );
cql_data_decl( struct list_item *all_triggers_list );
cql_data_decl( struct list_item *all_regions_list );
cql_data_decl( struct list_item *all_ad_hoc_list );
cql_data_decl( struct list_item *all_select_functions_list );
cql_data_decl( struct list_item *all_enums_list );
cql_data_decl( struct list_item *all_constant_groups_list );
cql_data_decl( symtab *schema_regions );
cql_data_decl( ast_node *current_proc );
cql_data_decl( charbuf *error_capture );
cql_data_decl( cte_state *cte_cur );
cql_data_decl( symtab *ref_sources_for_target_table );
cql_data_decl( symtab *ref_targets_for_source_table );

// These are the symbol tables with the accumulated included/excluded regions
cql_data_decl( symtab *included_regions );
cql_data_decl( symtab *excluded_regions );
cql_data_decl( sem_t global_proc_flags );

// This is the table for all the migration procs for any recreate procs or groups
// that might need them, these are the second form of ad hoc schema migration
cql_data_decl( symtab *ad_hoc_recreate_actions );

// If the current context is a upsert statement
cql_data_decl( bool_t in_upsert );
cql_data_decl( bool_t in_upsert_rewrite );

// hold the table ast query in the current upsert statement.
cql_data_decl ( ast_node *current_upsert_table_ast );
// This is the symbol table with the recreate group dependencies where an edge B -> A means A FKs to B
cql_data_decl( symtab *recreate_group_deps );

// Truthy when the @keep_table_name_in_aliases_stmt directive is used.
cql_data_decl( bool_t keep_table_name_in_aliases );
