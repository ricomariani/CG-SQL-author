/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// In case there is any doubt, 'cql.y' is included in the license as well as
// the code bison generates from it.

// cql - pronounced "see-cue-el" is a basic tool for enabling stored
//      procedures for SQLite. The tool does this by parsing specialized
//      .sql files:
//
//      - loose DDL (not in a proc) in the .sql is used to declare tables and views
//        has no other effect
//      - SQL DML and DDL logic is converted to the equivalent sqlite calls to do the work
//      - loose DML and loose control flow is consolidated into a global proc you can name
//        with the --global_proc command line switch
//      - control flow is converted to C control flow
//      - stored procs map into C functions directly, stored procs with a result set
//        become a series of procs for creating, accessing, and destroying the result set
//      - all sqlite code gen has full error checking and participates in SQL try/catch
//        and throw patterns
//      - strings and result sets can be mapped into assorted native objects by
//        defining the items in cqlrt.h
//      - everything is strongly typed, and type checked, using the primitive types:
//        bool, int, long int, real, and text
//
// Design principles:
//
//  1. Keep each pass in one file (simple, focused, and easy refactor).
//  2. Use simple printable AST parse nodes (no separate #define per AST node type).
//  3. 100% unit test coverage on all passes including output validation.

%{

#include <inttypes.h>
#include <setjmp.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include "cql.h"
#include "charbuf.h"

#include "ast.h"
#include "cg_common.h"
#include "cg_c.h"
#include "cg_schema.h"
#include "cg_json_schema.h"
#include "cg_test_helpers.h"
#include "cg_query_plan.h"
#include "gen_sql.h"
#include "sem.h"
#include "encoders.h"
#include "unit_tests.h"
#include "symtab.h"
#include "rt.h"

// In order for leak sanitizer to run, main must exit normally
// and yet there are cases we need to bail out like we would in exit
// to do that we use cql_cleanup_and_exit below which triggers this longjmp
// here in main.  CQL aspires to be a library in the future and so
// it cannot exit in those cases either it has to clean up, clean.

static jmp_buf cql_for_exit;
static int32_t cql_exit_code;

// this is the state we need to pre-process @ifdef and @ifndef
typedef struct cql_ifdef_state_t {
  bool_t process_else;
  bool_t processing;
  struct cql_ifdef_state_t *prev;
} cql_ifdef_state_t;

static cql_ifdef_state_t *cql_ifdef_state;

static ast_node *do_ifdef(ast_node *ast);
static ast_node *do_ifndef(ast_node *ast);
static void do_endif(void);
static void do_else(void);
static bool_t is_processing(void);

// The stack needed is modest (32k) and this prevents leaks in error cases because
// it's just a stack alloc.
#define YYSTACK_USE_ALLOCA 1

// Bison defines this only if __GNUC__ is defined, but Clang defines _MSC_VER
// and not __GNUC__ on Windows.
#ifdef __clang__
  #define YY_ATTRIBUTE_UNUSED __attribute__((unused))
#endif

static void parse_cmd(int argc, char **argv);
static void print_dot(struct ast_node* node);
static ast_node *file_literal(ast_node *);
static void cql_exit_on_parse_errors();
static void parse_cleanup();
static void cql_usage();
static ast_node *make_statement_node(ast_node *misc_attrs, ast_node *any_stmt);
static ast_node *make_coldef_node(ast_node *col_def_tye_attrs, ast_node *misc_attrs);
static ast_node *reduce_str_chain(ast_node *str_chain);
static ast_node *new_simple_call_from_name(ast_node *name);

// Set to true upon a call to `yyerror`.
static bool_t parse_error_occurred;
static CSTR table_comment_saved;

static void cql_setup_defines(void);
static void cql_cleanup_defines(void);
static void cql_add_define(CSTR name);

int yylex();
void yyerror(const char *s, ...);
void yyset_in(FILE *);
void yyset_lineno(int);
void yyrestart(FILE *);

#ifndef _MSC_VER
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsign-conversion"
#pragma clang diagnostic ignored "-Wimplicit-int-conversion"
#pragma clang diagnostic ignored "-Wconversion"
#endif

// In two places in the grammar we have to include an optional name list
// even though the name list isn't actually allowed.  We do this to avoid
// a shift reduce conflict.  We can't avoid the conflict case without a lot
// of very ugly grammar duplication. So this is the lesser of two evils
// and definitely more maintainable.
#define YY_ERROR_ON_COLUMNS(x) \
  if (x) yyerror("Cursor columns not allowed in this form.")

// In window_func_inv the 'distinct' keyword may not be part of the call
// e.g. count(distinct x) is not a valid form for window functions.  We
// unify these trees to avoid shift reduce conflicts and to clean up the grammar.
// so there is one call form.  However it means an explicit error check
#define YY_ERROR_ON_DISTINCT(x) \
  if (x) yyerror("DISTINCT not valid in this context.")

// if macro arg found that's an error, it should be a macro
#define YY_ERROR_ON_MACRO_ARG(x) \
  if (get_macro_arg_info(x) && !get_macro_info(x)) yyerror("expected a defined macro not a macro formal.");

// if macro arg not found that's an error, it shouldn't be a macro, it should be an arg
#define YY_ERROR_ON_MACRO(x) \
  if (!get_macro_arg_info(x) && get_macro_info(x)) yyerror("expected a defined macro formal not a macro.");

#define YY_ERROR_ON_FAILED_ADD_MACRO(success, name) \
  if (!success) { yyerror(dup_printf("macro already exists '%s'.", name)); }

#define YY_ERROR_ON_FAILED_MACRO_ARG(name) \
  if (name) { yyerror(dup_printf("macro argument already exists '%s'.", name)); }

// We insert calls to `cql_inferred_notnull` as part of a rewrite so we expect
// to see it during semantic analysis, but it cannot be allowed to appear in a
// program. It would be unsafe if it could: It coerces a value from a nullable
// type to a nonnull type without any runtime check.
#define YY_ERROR_ON_CQL_INFERRED_NOTNULL(x) \
  if (is_ast_str(x)) { \
    EXTRACT_STRING(proc_name, x); \
    if (!strcmp(proc_name, "cql_inferred_notnull")) { \
      yyerror("Call to internal function is not allowed 'cql_inferred_notnull'"); \
    } \
  }

// If a column alias is present for * or T.* that's an error
// We now parse ast_star as an expression to avoid ambiguities in the grammar
// but that means we have to manually filter out some of this bad syntax
#define YY_ERROR_ON_ALIAS_PRESENT(x) \
   if (x) yyerror("* and T.* cannot have a column alias");

#ifdef CQL_AMALGAM
static void cql_reset_globals(void);
#endif

#define AST_STR(node) (((str_ast_node *)node)->value)

%}

%define parse.error verbose

%union {
  struct ast_node *aval;
  int ival;
  char *sval;
}

%token <sval> ID QID TRUE_ "TRUE" FALSE_ "FALSE"
%token <sval> STRLIT CSTRLIT BLOBLIT
%token <sval> INTLIT
%token <ival> BOOL_ "BOOL"
%token <ival> AT_DUMMY_NULLABLES
%token <ival> AT_DUMMY_DEFAULTS
%token <sval> LONGLIT
%token <sval> REALLIT
%token <sval> STMT_LIST_MACRO EXPR_MACRO QUERY_PARTS_MACRO CTE_TABLES_MACRO SELECT_CORE_MACRO SELECT_EXPR_MACRO

/*
 SQLite understands the following binary operators, in order from LOWEST to HIGHEST precedence:

 OR
 AND
 =    ==   !=   <>   IS   IS NOT   IN   NOT IN   LIKE   NOT LIKE   GLOB   MATCH   REGEXP
 <    <=   >    >=
 <<   >>   &    |
 +    -
 *    /    %
 ||
*/


// NOTE the precedence declared here in the grammar MUST agree with the precedence
// declared in ast.h EXPR_PRI_XXX or else badness ensues.  It must also agree
// with the SQLite precedence shown below or badness ensues...

// Don't try to remove the NOT_IN, IS_NOT, NOT_BETWEEN, or NOT_LIKE tokens
// you can match the language with those but the precedence of NOT is wrong
// so order of operations will be subtlely off.  There are now tests for this.

// Since ~ is used for type casting it has to be declared in its binary operator
// location.The normal ~foo operator gets %prec UMINUS like the others.

%left UNION_ALL UNION INTERSECT EXCEPT
%right ASSIGN ADD_EQ SUB_EQ MUL_EQ DIV_EQ MOD_EQ OR_EQ AND_EQ LS_EQ RS_EQ
%left OR
%left AND
%left NOT
%left BETWEEN NOT_BETWEEN NE NE_ '=' EQEQ LIKE NOT_LIKE GLOB NOT_GLOB MATCH NOT_MATCH REGEXP NOT_REGEXP IN NOT_IN IS_NOT IS IS_TRUE IS_FALSE IS_NOT_TRUE IS_NOT_FALSE
%left ISNULL NOTNULL
%left '<' '>' GE LE
%left LS RS '&' '|'
%left '+' '-'
%left '*' '/' '%'
%left CONCAT JEX1 JEX2 ':' '.' '[' '~'
%left COLLATE
%right UMINUS

/* from the SQLite grammar  for comparison

 left OR.
 left AND.
 right NOT.
 left IS MATCH LIKE_KW BETWEEN IN ISNULL NOTNULL NE EQ.
 left GT LE LT GE.
 right ESCAPE.    (NYI in CQL)
 left BITAND BITOR LSHIFT RSHIFT.
 left PLUS MINUS.
 left STAR SLASH REM.
 left CONCAT.
 left COLLATE.
 right BITNOT.
*/

// String representations for operators mentioned above. (These cannot be given
// in the precedence declarations themselves.)
%token ASSIGN ":="
%token CONCAT "||"
%token EQEQ "=="
%token GE ">="
%token LE "<="
%token LS "<<"
%token NE "<>"
%token NE_ "!="
%token RS ">>"

%token EXCLUDE_GROUP EXCLUDE_CURRENT_ROW EXCLUDE_TIES EXCLUDE_NO_OTHERS CURRENT_ROW UNBOUNDED PRECEDING FOLLOWING
%token CREATE DROP TABLE WITHOUT ROWID PRIMARY KEY NULL_ "NULL" DEFAULT CHECK AT_DUMMY_SEED VIRTUAL AT_EMIT_GROUP AT_EMIT_ENUMS AT_EMIT_CONSTANTS
%token OBJECT TEXT BLOB LONG_ INT_ INTEGER LONG_INT LONG_INTEGER REAL ON UPDATE CASCADE ON_CONFLICT DO NOTHING
%token DELETE INDEX FOREIGN REFERENCES CONSTRAINT UPSERT STATEMENT CONST
%token INSERT INTO VALUES VIEW SELECT QUERY_PLAN EXPLAIN OVER WINDOW FILTER PARTITION RANGE ROWS GROUPS
%token AS CASE WHEN FROM THEN ELSE END LEFT SWITCH
%token OUTER JOIN WHERE GROUP BY ORDER ASC NULLS FIRST LAST
%token DESC INNER AUTOINCREMENT DISTINCT
%token LIMIT OFFSET TEMP TRIGGER IF ALL CROSS USING RIGHT AT_EPONYMOUS
%token HIDDEN UNIQUE HAVING SET LET TO DISTINCTROW ENUM
%token FUNC FUNCTION PROC PROCEDURE INTERFACE OUT INOUT CURSOR DECLARE VAR TYPE FETCH LOOP LEAVE CONTINUE ENCODE CONTEXT_COLUMN CONTEXT_TYPE
%token OPEN CLOSE ELSE_IF WHILE CALL TRY CATCH THROW RETURN
%token SAVEPOINT ROLLBACK COMMIT TRANSACTION RELEASE ARGUMENTS
%token TYPE_CHECK CAST WITH RECURSIVE REPLACE IGNORE ADD COLUMN AT_COLUMNS RENAME ALTER
%token AT_ECHO AT_CREATE AT_RECREATE AT_DELETE AT_SCHEMA_UPGRADE_VERSION AT_PREVIOUS_SCHEMA AT_SCHEMA_UPGRADE_SCRIPT
%token AT_ID AT_RC AT_PROC AT_FILE AT_LINE AT_MACRO_LINE AT_MACRO_FILE AT_TEXT AT_ATTRIBUTE AT_SENSITIVE DEFERRED AT_TMP
%token NOT_DEFERRABLE DEFERRABLE IMMEDIATE EXCLUSIVE RESTRICT ACTION INITIALLY NO
%token BEFORE AFTER INSTEAD OF FOR_EACH_ROW EXISTS RAISE FAIL ABORT
%token AT_ENFORCE_STRICT AT_ENFORCE_NORMAL AT_ENFORCE_RESET AT_ENFORCE_PUSH AT_ENFORCE_POP
%token AT_BEGIN_SCHEMA_REGION AT_END_SCHEMA_REGION AT_OP
%token AT_DECLARE_SCHEMA_REGION AT_DECLARE_DEPLOYABLE_REGION AT_SCHEMA_AD_HOC_MIGRATION PRIVATE
%token AT_KEEP_TABLE_NAME_IN_ALIASES AT_MACRO EXPR STMT_LIST QUERY_PARTS CTE_TABLES SELECT_CORE SELECT_EXPR
%token SIGN_FUNCTION CURSOR_HAS_ROW AT_UNSUB
%left BEGIN_INCLUDE END_INCLUDE
%token AT_IFDEF AT_IFNDEF AT_ELSE AT_ENDIF RETURNING
%right BEGIN_
%right FOR

/* ddl stuff */
%type <ival> opt_temp opt_if_not_exists opt_unique opt_no_rowid dummy_modifier compound_operator opt_query_plan
%type <ival> opt_fk_options fk_options fk_on_options fk_action fk_initial_state fk_deferred_options transaction_mode conflict_clause
%type <ival> frame_type frame_exclude join_type
%type <ival> opt_vtab_flags

%type <aval> col_key_list col_key_def col_def sql_name loose_name loose_name_or_type
%type <aval> version_attrs opt_version_attrs version_attrs_opt_recreate opt_delete_version_attr opt_delete_plain_attr
%type <aval> misc_attr_key cql_attr_key misc_attr misc_attrs misc_attr_value misc_attr_value_list
%type <aval> col_attrs str_literal num_literal any_literal const_expr str_chain str_leaf
%type <aval> pk_def fk_def unq_def check_def fk_target_options opt_module_args opt_conflict_clause
%type <aval> col_calc col_calcs column_calculation text_arg text_args

%type <aval> alter_table_add_column_stmt
%type <aval> create_index_stmt create_table_stmt create_view_stmt create_virtual_table_stmt
%type <aval> indexed_column indexed_columns
%type <aval> drop_index_stmt drop_table_stmt drop_view_stmt drop_trigger_stmt
%type <ival> create_table_prefix_opt_temp

%type <aval> trigger_update_stmt trigger_delete_stmt trigger_insert_stmt trigger_select_stmt select_nothing_stmt
%type <aval> trigger_stmt trigger_stmts opt_when_expr trigger_action opt_of
%type <aval> trigger_def trigger_operation create_trigger_stmt raise_expr
%type <ival> trigger_condition opt_foreachrow

/* dml stuff */
%type <aval> delete_stmt delete_stmt_plain
%type <aval> insert_stmt insert_list_item insert_list insert_stmt_type returning_suffix insert_stmt_plain
%type <aval> column_spec opt_column_spec opt_insert_dummy_spec expr_names expr_name
%type <aval> with_prefix with_select_stmt cte_table cte_tables cte_binding_list cte_binding cte_decl shared_cte
%type <aval> select_expr select_expr_list select_opts select_stmt select_core values explain_stmt explain_target row_source
%type <aval> select_stmt_no_with select_core_list
%type <aval> window_func_inv opt_filter_clause window_name_or_defn window_defn opt_select_window
%type <aval> opt_partition_by opt_frame_spec frame_boundary_opts frame_boundary_start frame_boundary_end frame_boundary
%type <aval> opt_where opt_groupby opt_having opt_orderby opt_limit opt_offset opt_as_alias as_alias window_clause
%type <aval> groupby_item groupby_list orderby_item orderby_list opt_asc_desc opt_nullsfirst_nullslast window_name_defn window_name_defn_list
%type <aval> table_or_subquery table_or_subquery_list query_parts table_function opt_from_query_parts
%type <aval> opt_join_cond join_cond join_clause join_target join_target_list
%type <aval> basic_update_stmt update_stmt_plain update_stmt update_cursor_stmt update_entry update_list upsert_stmt conflict_target
%type <aval> declare_schema_region_stmt declare_deployable_region_stmt call opt_distinct simple_call upsert_stmt_plain
%type <aval> begin_schema_region_stmt end_schema_region_stmt schema_ad_hoc_migration_stmt region_list region_spec
%type <aval> schema_unsub_stmt

/* expressions and types */
%type <aval> expr basic_expr math_expr opt_expr_list expr_list typed_name typed_names case_list shape_arguments
%type <aval> name name_list sql_name_list opt_sql_name_list opt_name_list opt_sql_name
%type <aval> data_type_any data_type_numeric data_type_with_options opt_kind

/* proc stuff */
%type <aval> create_proc_stmt declare_func_stmt declare_select_func_stmt declare_proc_stmt declare_interface_stmt declare_proc_no_check_stmt declare_out_call_stmt
%type <aval> arg_expr arg_list arg_exprs inout param params func_params func_param
%type <aval> macro_def_stmt opt_macro_args macro_args macro_arg op_stmt
%type <aval> opt_macro_formals macro_formals macro_formal macro_type
%type <aval> top_level_stmts include_stmts include_section
%type <aval> stmt_list_macro_def expr_macro_def query_parts_macro_def cte_tables_macro_def select_core_macro_def select_expr_macro_def
%type <aval> macro_ref


/* statements */
%type <aval> stmt
%type <aval> stmt_list opt_stmt_list
%type <aval> any_stmt expr_stmt
%type <aval> begin_trans_stmt
%type <aval> call_stmt
%type <aval> close_stmt
%type <aval> commit_trans_stmt commit_return_stmt
%type <aval> continue_stmt
%type <aval> control_stmt
%type <aval> declare_vars_stmt declare_value_cursor declare_forward_read_cursor_stmt declare_type_stmt declare_fetched_value_cursor_stmt
%type <aval> declare_enum_stmt enum_values enum_value emit_enums_stmt emit_group_stmt
%type <aval> declare_const_stmt const_values const_value emit_constants_stmt declare_group_stmt simple_variable_decls
%type <aval> echo_stmt
%type <aval> fetch_stmt fetch_values_stmt fetch_call_stmt from_shape
%type <aval> guard_stmt
%type <aval> ifdef_stmt ifndef_stmt ifdef ifndef
%type <sval> elsedef endif
%type <aval> if_stmt elseif_item elseif_list opt_else opt_elseif_list proc_savepoint_stmt
%type <aval> leave_stmt return_stmt
%type <aval> loop_stmt
%type <aval> out_stmt out_union_stmt out_union_parent_child_stmt child_results child_result
%type <aval> previous_schema_stmt
%type <aval> release_savepoint_stmt
%type <aval> rollback_trans_stmt rollback_return_stmt savepoint_name
%type <aval> savepoint_stmt
%type <aval> schema_upgrade_script_stmt
%type <aval> schema_upgrade_version_stmt
%type <aval> set_stmt let_stmt const_stmt
%type <aval> switch_stmt switch_cases switch_case
%type <aval> throw_stmt
%type <aval> trycatch_stmt
%type <aval> version_annotation
%type <aval> while_stmt for_stmt
%type <aval> enforce_strict_stmt enforce_normal_stmt enforce_reset_stmt enforce_push_stmt enforce_pop_stmt
%type <aval> enforcement_options shape_def shape_def_base shape_expr shape_exprs
%type <aval> keep_table_name_in_aliases_stmt

%start program

/* beware adding comments into this section causes the auto-gen grammar to fail */

%%

program: top_level_stmts[stmts] {
    if (!parse_error_occurred) {
      gen_init();
      if (options.expand) {
        expand_macros($stmts);
        if (macro_expansion_errors) {
          cql_cleanup_and_exit(3);
        }
      }
      if (options.semantic) {
        sem_main($stmts);
      }
      if (options.codegen) {
        rt->code_generator($stmts);
      }
      else if (options.print_ast) {
        print_root_ast($stmts);
        cql_output("\n");
      }
      else if (options.print_dot) {
        cql_output("\ndigraph parse {");
        print_dot($stmts);
        cql_output("\n}\n");
      }
      else if (options.echo_input) {
        gen_stmt_list_to_stdout($stmts);
      }
      if (options.semantic) {
        cql_exit_on_semantic_errors($stmts);
      }
    }
  }
  ;

  top_level_stmts:
    /* nil */  { $$ = NULL; }
    | include_stmts { $$ = $include_stmts; }
    | stmt_list { $$ = $stmt_list; }
    | include_stmts[s1] stmt_list[s2] {
       $$ = $s2;
       if ($s1) {
         // use our tail pointer invariant so we can add at the tail without searching
         // the re-stablish the invariant
         ast_node *tail = $s1->parent;
         $s1->parent = $s2->parent;
         ast_set_right(tail, $s2);
         $$ = $s1;
      }
   }
   ;

include_section: BEGIN_INCLUDE top_level_stmts END_INCLUDE { $$ = $top_level_stmts; }
   ;

include_stmts:
    include_section[s1] { $$ = $s1; }
    | include_section[s1] include_stmts[s2] {
       if (!$s1) {
         $$ = $s2;
       }
       else {
         $$ = $s1;
         if ($s2) {
           // use our tail pointer invariant so we can add at the tail without searching
           // the re-establish the invariant
           ast_node *tail = $s1->parent;
           $s1->parent = $s2->parent;
           ast_set_right(tail, $s2);
        }
      }
    }
    ;

opt_stmt_list:
  /* nil */  { $$ = NULL; }
  | stmt_list  { $$ = $stmt_list; }
  ;

macro_ref:
  ID '!' {
     YY_ERROR_ON_MACRO($ID);
     $$ = new_macro_arg_ref_node($ID); }
  | ID '!' '(' opt_macro_args ')' {
     YY_ERROR_ON_MACRO_ARG($ID);
     $$ = new_macro_ref_node($ID, $opt_macro_args); }
  ;

stmt_list:
  stmt {
     // We're going to do this cheesy thing with the stmt_list structures so that we can
     // code the stmt_list rules using left recursion.  We're doing this because it's
     // possible that there could be a LOT of statements and this minimizes the use
     // of the bison stack because reductions happen sooner with this pattern.  It does
     // mean we have to do some weird stuff because we need to build the list so that the
     // tail is on the right.  To accomplish this we take advantage of the fact that the
     // parent pointer of the statement list is meaningless while it is unrooted.  It
     // would always be null.  We store the tail of the statement list there so we know
     // where to add new nodes on the right.  When the statement list is put into the tree
     // the parent node is set as usual so nobody will know we did this and we don't
     // have to add anything to the node for this one case.

     // With this done we can handle several thousand statements without using much stack space.

     $$ = new_ast_stmt_list($stmt, NULL);
     $$->lineno = $stmt->lineno;

     // set up the tail pointer invariant to use later
     $$->parent = $$;
     }
  | stmt_list[slist] stmt {
     ast_node *new_stmt = new_ast_stmt_list($stmt, NULL);
     new_stmt->lineno = $stmt->lineno;

     // use our tail pointer invariant so we can add at the tail without searching
     ast_node *tail = $slist->parent;
     ast_set_right(tail, new_stmt);

     // re-establish the tail invariant per the above
     $slist->parent = new_stmt;
     $$ = $slist;
     }
  ;

stmt:
  misc_attrs any_stmt ';' { $$ = make_statement_node($misc_attrs, $any_stmt); }
  | ifdef_stmt { $$ = make_statement_node(NULL, $ifdef_stmt); }
  | ifndef_stmt { $$ = make_statement_node(NULL, $ifndef_stmt); }
  ;

expr_stmt: expr {
     if (is_ast_stmt_list_macro_ref($expr) || is_ast_stmt_list_macro_arg_ref($expr)) {
        $$ = $expr;
     }
     else {
       $$ = new_ast_expr_stmt($expr);
     }
   }
  ;

any_stmt:
    alter_table_add_column_stmt
  | expr_stmt
  | begin_schema_region_stmt
  | begin_trans_stmt
  | call_stmt
  | close_stmt
  | commit_return_stmt
  | commit_trans_stmt
  | const_stmt
  | continue_stmt
  | create_index_stmt
  | create_proc_stmt
  | create_table_stmt
  | create_trigger_stmt
  | create_view_stmt
  | create_virtual_table_stmt
  | declare_deployable_region_stmt
  | declare_enum_stmt
  | declare_const_stmt
  | declare_group_stmt
  | declare_func_stmt
  | declare_select_func_stmt
  | declare_out_call_stmt
  | declare_proc_no_check_stmt
  | declare_proc_stmt
  | declare_interface_stmt
  | declare_schema_region_stmt
  | declare_vars_stmt
  | declare_forward_read_cursor_stmt
  | declare_fetched_value_cursor_stmt
  | declare_type_stmt
  | delete_stmt
  | drop_index_stmt
  | drop_table_stmt
  | drop_trigger_stmt
  | drop_view_stmt
  | echo_stmt
  | emit_enums_stmt
  | emit_group_stmt
  | emit_constants_stmt
  | end_schema_region_stmt
  | enforce_normal_stmt
  | enforce_pop_stmt
  | enforce_push_stmt
  | enforce_reset_stmt
  | enforce_strict_stmt
  | explain_stmt
  | select_nothing_stmt
  | fetch_call_stmt
  | fetch_stmt
  | fetch_values_stmt
  | guard_stmt
  | if_stmt
  | insert_stmt
  | leave_stmt
  | let_stmt
  | loop_stmt
  | macro_def_stmt
  | op_stmt
  | out_stmt
  | out_union_stmt
  | out_union_parent_child_stmt
  | previous_schema_stmt
  | proc_savepoint_stmt
  | release_savepoint_stmt
  | return_stmt
  | rollback_return_stmt
  | rollback_trans_stmt
  | savepoint_stmt
  | select_stmt
  | schema_ad_hoc_migration_stmt
  | schema_unsub_stmt
  | schema_upgrade_script_stmt
  | schema_upgrade_version_stmt
  | set_stmt
  | switch_stmt
  | throw_stmt
  | trycatch_stmt
  | update_cursor_stmt
  | update_stmt
  | upsert_stmt
  | while_stmt
  | for_stmt
  | keep_table_name_in_aliases_stmt
  ;

explain_stmt:
  EXPLAIN opt_query_plan explain_target  { $$ = new_ast_explain_stmt(new_ast_option($opt_query_plan), $explain_target); }
  ;

opt_query_plan:
  /* nil */  { $$ = EXPLAIN_NONE; }
  | QUERY_PLAN  { $$ = EXPLAIN_QUERY_PLAN; }
  ;

explain_target: select_stmt
  | begin_trans_stmt
  | commit_trans_stmt
  | delete_stmt
  | drop_index_stmt
  | drop_table_stmt
  | drop_trigger_stmt
  | drop_view_stmt
  | insert_stmt
  | update_stmt
  | upsert_stmt
  ;

previous_schema_stmt:
  AT_PREVIOUS_SCHEMA  { $$ = new_ast_previous_schema_stmt(); }
  ;

schema_upgrade_script_stmt:
  AT_SCHEMA_UPGRADE_SCRIPT  { $$ = new_ast_schema_upgrade_script_stmt(); }
  ;

schema_upgrade_version_stmt:
  AT_SCHEMA_UPGRADE_VERSION '(' INTLIT ')'  {
    $$ = new_ast_schema_upgrade_version_stmt(new_ast_option(atoi($INTLIT))); }
  ;

set_stmt:
  SET sql_name ASSIGN expr  { $$ = new_ast_assign($sql_name, $expr); }
  | SET sql_name[id] FROM CURSOR name[cursor] { $$ = new_ast_set_from_cursor($id, $cursor); }
  | SET sql_name '[' arg_list ']' ASSIGN expr  { $$ = new_ast_expr_stmt(new_ast_expr_assign(new_ast_array($sql_name, $arg_list), $expr)); }
  ;

let_stmt:
  LET sql_name ASSIGN expr  { $$ = new_ast_let_stmt($sql_name, $expr); }
  ;

const_stmt:
  CONST sql_name ASSIGN expr  { $$ = new_ast_const_stmt($sql_name, $expr); }
  ;

version_attrs_opt_recreate:
  /* nil */  { $$ = NULL; }
  | AT_RECREATE  opt_delete_plain_attr { $$ = new_ast_recreate_attr(NULL, $opt_delete_plain_attr); }
  | AT_RECREATE '(' name ')'  opt_delete_plain_attr { $$ = new_ast_recreate_attr($name, $opt_delete_plain_attr); }
  | version_attrs  { $$ = $version_attrs; }
  ;

opt_delete_plain_attr:
  /* nil */  {$$ = NULL; }
  | AT_DELETE { $$ = new_ast_delete_attr(NULL, NULL); }
  ;

opt_version_attrs:
  /* nil */  { $$ = NULL; }
  | version_attrs  { $$ = $version_attrs; }
  ;

version_attrs:
  AT_CREATE version_annotation opt_version_attrs  { $$ = new_ast_create_attr($version_annotation, $opt_version_attrs); }
  | AT_DELETE version_annotation opt_version_attrs  { $$ = new_ast_delete_attr($version_annotation, $opt_version_attrs); }
  ;

opt_delete_version_attr:
  /* nil */  {$$ = NULL; }
  | AT_DELETE version_annotation  { $$ = new_ast_delete_attr($version_annotation, NULL); }
  ;

drop_table_stmt:
  DROP TABLE IF EXISTS sql_name  { $$ = new_ast_drop_table_stmt(new_ast_option(1), $sql_name);  }
  | DROP TABLE sql_name  { $$ = new_ast_drop_table_stmt(NULL, $sql_name);  }
  ;

drop_view_stmt:
  DROP VIEW IF EXISTS sql_name  { $$ = new_ast_drop_view_stmt(new_ast_option(1), $sql_name);  }
  | DROP VIEW sql_name  { $$ = new_ast_drop_view_stmt(NULL, $sql_name);  }
  ;

drop_index_stmt:
  DROP INDEX IF EXISTS sql_name  { $$ = new_ast_drop_index_stmt(new_ast_option(1), $sql_name);  }
  | DROP INDEX sql_name  { $$ = new_ast_drop_index_stmt(NULL, $sql_name);  }
  ;

drop_trigger_stmt:
  DROP TRIGGER IF EXISTS sql_name  { $$ = new_ast_drop_trigger_stmt(new_ast_option(1), $sql_name);  }
  | DROP TRIGGER sql_name  { $$ = new_ast_drop_trigger_stmt(NULL, $sql_name);  }
  ;

create_virtual_table_stmt: CREATE VIRTUAL TABLE opt_vtab_flags sql_name[table_name]
                           USING name[module_name] opt_module_args
                           AS '(' col_key_list ')' opt_delete_version_attr {
    int flags = $opt_vtab_flags;
    struct ast_node *flags_node = new_ast_option(flags);
    struct ast_node *name = $table_name;
    struct ast_node *col_key_list = $col_key_list;
    struct ast_node *version_info = $opt_delete_version_attr ? $opt_delete_version_attr : new_ast_recreate_attr(NULL, NULL);
    struct ast_node *table_flags_attrs = new_ast_table_flags_attrs(flags_node, version_info);
    struct ast_node *table_name_flags = new_ast_create_table_name_flags(table_flags_attrs, name);
    struct ast_node *create_table_stmt =  new_ast_create_table_stmt(table_name_flags, col_key_list);
    struct ast_node *module_info = new_ast_module_info($module_name, $opt_module_args);
    $$ = new_ast_create_virtual_table_stmt(module_info, create_table_stmt);
  };

opt_module_args: /* nil */ { $$ = NULL; }
  | '(' misc_attr_value_list ')' { $$ = $misc_attr_value_list; }
  | '(' ARGUMENTS FOLLOWING ')' { $$ = new_ast_following(); }
  ;

create_table_prefix_opt_temp:
  CREATE opt_temp TABLE {
    /* This node only exists so that we can get an early reduce in the table flow to grab the doc comment */
   $$ = $opt_temp; table_comment_saved = get_last_doc_comment();
  };

create_table_stmt:
  create_table_prefix_opt_temp opt_if_not_exists sql_name '(' col_key_list ')' opt_no_rowid version_attrs_opt_recreate  {
    int flags = $create_table_prefix_opt_temp | $opt_if_not_exists | $opt_no_rowid;
    struct ast_node *flags_node = new_ast_option(flags);
    struct ast_node *name = $sql_name;
    struct ast_node *col_key_list = $col_key_list;
    struct ast_node *table_flags_attrs = new_ast_table_flags_attrs(flags_node, $version_attrs_opt_recreate);
    struct ast_node *table_name_flags = new_ast_create_table_name_flags(table_flags_attrs, name);
    $$ =  new_ast_create_table_stmt(table_name_flags, col_key_list);
  }
  ;

opt_temp:
  /* nil */  { $$ = 0; }
  | TEMP  { $$ = GENERIC_IS_TEMP; }
  ;

opt_if_not_exists:
  /* nil */  { $$ = 0;  }
  | IF NOT EXISTS  { $$ = GENERIC_IF_NOT_EXISTS; }
  ;

opt_no_rowid:
  /* nil */  { $$ = 0; }
  | WITHOUT ROWID  { $$ = TABLE_IS_NO_ROWID; }
  ;

opt_vtab_flags:
  /* nil */ { $$ = 0; }
  | IF NOT EXISTS  { $$ = GENERIC_IF_NOT_EXISTS; }
  | AT_EPONYMOUS { $$ = VTAB_IS_EPONYMOUS; }
  | AT_EPONYMOUS IF NOT EXISTS  { $$ = VTAB_IS_EPONYMOUS | GENERIC_IF_NOT_EXISTS; }
  | IF NOT EXISTS AT_EPONYMOUS { $$ = VTAB_IS_EPONYMOUS | GENERIC_IF_NOT_EXISTS; }
  ;

col_key_list:
  col_key_def  { $$ = new_ast_col_key_list($col_key_def, NULL); }
  | col_key_def ',' col_key_list[ckl]  { $$ = new_ast_col_key_list($col_key_def, $ckl); }
  ;

col_key_def:
  col_def
  | pk_def
  | fk_def
  | unq_def
  | check_def
  | shape_def
  ;

check_def:
  CONSTRAINT name CHECK '(' expr ')' { $$ = new_ast_check_def($name, $expr); }
  | CHECK '(' expr ')'  { $$ = new_ast_check_def(NULL, $expr); }
  ;

shape_exprs:
  shape_expr ',' shape_exprs[next] { $$ = new_ast_shape_exprs($shape_expr, $next); }
  | shape_expr { $$ = new_ast_shape_exprs($shape_expr, NULL); }
  ;

shape_expr:
  sql_name  { $$ = new_ast_shape_expr($sql_name, $sql_name); }
  | '-' sql_name  { $$ = new_ast_shape_expr($sql_name, NULL); }
  ;

shape_def:
    shape_def_base  { $$ = new_ast_shape_def($shape_def_base, NULL); }
  | shape_def_base '(' shape_exprs ')' { $$ = new_ast_shape_def($shape_def_base, $shape_exprs); }
  ;

shape_def_base:
    LIKE sql_name { $$ = new_ast_like($sql_name, NULL); }
  | LIKE name ARGUMENTS { $$ = new_ast_like($name, $name); }
  ;

sql_name:
  name  { $$ = $name; }
  | QID { $$ = new_ast_qstr_quoted($QID); }
  ;

misc_attr_key:
  name  { $$ = $name; }
  | name[lhs] ':' name[rhs]  { $$ = new_ast_dot($lhs, $rhs); }
  ;

cql_attr_key:
  name { $$ = new_ast_dot(new_ast_str("cql"), $name); }
  | name[lhs] ':' name[rhs]  { $$ = new_ast_dot($lhs, $rhs); }
  ;

misc_attr_value_list:
  misc_attr_value  { $$ = new_ast_misc_attr_value_list($misc_attr_value, NULL); }
  | misc_attr_value ',' misc_attr_value_list[mav]  { $$ = new_ast_misc_attr_value_list($misc_attr_value, $mav); }
  ;

misc_attr_value:
  sql_name  { $$ = $sql_name; }
  | any_literal  { $$ = $any_literal; }
  | const_expr  { $$ = $const_expr; }
  | '(' misc_attr_value_list ')'  { $$ = $misc_attr_value_list; }
  | '-' num_literal  { $$ = new_ast_uminus($num_literal);}
  | '+' num_literal  { $$ = $num_literal;}
  ;

misc_attr:
  AT_ATTRIBUTE '(' misc_attr_key ')'  { $$ = new_ast_misc_attr($misc_attr_key, NULL); }
  | AT_ATTRIBUTE '(' misc_attr_key '=' misc_attr_value ')' { $$ = new_ast_misc_attr($misc_attr_key, $misc_attr_value); }
  | '[' '[' cql_attr_key ']' ']' { $$ = new_ast_misc_attr($cql_attr_key, NULL); }
  | '[' '[' cql_attr_key  '=' misc_attr_value ']' ']' { $$ = new_ast_misc_attr($cql_attr_key, $misc_attr_value); }
  ;

misc_attrs:
  /* nil */ %prec BEGIN_ { $$ = NULL; }
  | misc_attr misc_attrs[ma] %prec BEGIN_ { $$ = new_ast_misc_attrs($misc_attr, $ma); }
  ;

col_def:
  misc_attrs sql_name data_type_any col_attrs  {
  struct ast_node *name_type = new_ast_col_def_name_type($sql_name, $data_type_any);
  struct ast_node *col_def_type_attrs = new_ast_col_def_type_attrs(name_type, $col_attrs);
  $$ = make_coldef_node(col_def_type_attrs, $misc_attrs);
  }
  ;

pk_def:
  CONSTRAINT sql_name PRIMARY KEY '(' indexed_columns ')' opt_conflict_clause {
    ast_node *indexed_columns_conflict_clause = new_ast_indexed_columns_conflict_clause($indexed_columns, $opt_conflict_clause);
    $$ = new_ast_pk_def($sql_name, indexed_columns_conflict_clause);
  }
  | PRIMARY KEY '(' indexed_columns ')' opt_conflict_clause {
    ast_node *indexed_columns_conflict_clause = new_ast_indexed_columns_conflict_clause($indexed_columns, $opt_conflict_clause);
    $$ = new_ast_pk_def(NULL, indexed_columns_conflict_clause);
  }
  ;

opt_conflict_clause:
  /* nil */ { $$ = NULL; }
  | conflict_clause { $$ = new_ast_option($conflict_clause); }
  ;

conflict_clause:
  ON_CONFLICT ROLLBACK { $$ = ON_CONFLICT_ROLLBACK; }
  | ON_CONFLICT ABORT { $$ = ON_CONFLICT_ABORT; }
  | ON_CONFLICT FAIL { $$ = ON_CONFLICT_FAIL; }
  | ON_CONFLICT IGNORE { $$ = ON_CONFLICT_IGNORE; }
  | ON_CONFLICT REPLACE { $$ = ON_CONFLICT_REPLACE; }
  ;

opt_fk_options:
  /* nil */  { $$ = 0; }
  | fk_options  { $$ = $fk_options; }
  ;

fk_options:
  fk_on_options  { $$ = $fk_on_options; }
  | fk_deferred_options  { $$ = $fk_deferred_options; }
  | fk_on_options fk_deferred_options  { $$ = $fk_on_options | $fk_deferred_options; }
  ;

fk_on_options:
  ON DELETE fk_action  { $$ = $fk_action; }
  | ON UPDATE fk_action  { $$ = ($fk_action << 4); }
  | ON UPDATE fk_action[lhs] ON DELETE fk_action[rhs]  { $$ = ($lhs << 4) | $rhs; }
  | ON DELETE fk_action[lhs] ON UPDATE fk_action[rhs]  { $$ = ($rhs << 4) | $lhs; }
  ;

fk_action:
  SET NULL_  { $$ = FK_SET_NULL; }
  | SET DEFAULT  { $$ = FK_SET_DEFAULT; }
  | CASCADE  { $$ = FK_CASCADE; }
  | RESTRICT  { $$ = FK_RESTRICT; }
  | NO ACTION  { $$ = FK_NO_ACTION; }
  ;

fk_deferred_options:
  DEFERRABLE fk_initial_state  { $$ = FK_DEFERRABLE | $fk_initial_state; }
  | NOT_DEFERRABLE fk_initial_state  { $$ = FK_NOT_DEFERRABLE | $fk_initial_state; }
  ;

fk_initial_state:
  /* nil */  { $$ = 0; }
  | INITIALLY DEFERRED  { $$ = FK_INITIALLY_DEFERRED; }
  | INITIALLY IMMEDIATE  { $$ = FK_INITIALLY_IMMEDIATE; }
  ;

fk_def:
  CONSTRAINT sql_name FOREIGN KEY '(' sql_name_list ')' fk_target_options  {
    ast_node *fk_info = new_ast_fk_info($sql_name_list, $fk_target_options);
    $$ = new_ast_fk_def($sql_name, fk_info); }
  | FOREIGN KEY '(' sql_name_list ')' fk_target_options  {
    ast_node *fk_info = new_ast_fk_info($sql_name_list, $fk_target_options);
    $$ = new_ast_fk_def(NULL, fk_info); }
  ;

fk_target_options:
  REFERENCES sql_name '(' sql_name_list ')' opt_fk_options  {
    $$ = new_ast_fk_target_options(new_ast_fk_target($sql_name, $sql_name_list), new_ast_option($opt_fk_options)); }
  ;

unq_def:
  CONSTRAINT sql_name UNIQUE '(' indexed_columns ')' opt_conflict_clause {
    ast_node *indexed_columns_conflict_clause = new_ast_indexed_columns_conflict_clause($indexed_columns, $opt_conflict_clause);
    $$ = new_ast_unq_def($sql_name, indexed_columns_conflict_clause);
  }
  | UNIQUE '(' indexed_columns ')' opt_conflict_clause {
    ast_node *indexed_columns_conflict_clause = new_ast_indexed_columns_conflict_clause($indexed_columns, $opt_conflict_clause);
    $$ = new_ast_unq_def(NULL, indexed_columns_conflict_clause);
  }
  ;

opt_unique:
  /* nil */  { $$ = 0; }
  | UNIQUE  { $$ = 1; }
  ;

indexed_column:
  expr opt_asc_desc  {
    $$ = new_ast_indexed_column($expr, $opt_asc_desc); }
  ;

indexed_columns:
  indexed_column  { $$ = new_ast_indexed_columns($indexed_column, NULL); }
  | indexed_column ',' indexed_columns[ic]  { $$ = new_ast_indexed_columns($indexed_column, $ic); }
  ;

create_index_stmt:
  CREATE opt_unique INDEX opt_if_not_exists sql_name[tbl_name] ON sql_name[idx_name] '(' indexed_columns ')' opt_where opt_delete_version_attr  {
    int flags = 0;
    if ($opt_unique) flags |= INDEX_UNIQUE;
    if ($opt_if_not_exists) flags |= INDEX_IFNE;

    ast_node *create_index_on_list = new_ast_create_index_on_list($tbl_name, $idx_name);
    ast_node *index_names_and_attrs = new_ast_index_names_and_attrs($indexed_columns, $opt_where);
    ast_node *connector = new_ast_connector(index_names_and_attrs, $opt_delete_version_attr);
    ast_node *flags_names_attrs = new_ast_flags_names_attrs(new_ast_option(flags), connector);
    $$ = new_ast_create_index_stmt(create_index_on_list, flags_names_attrs);
  }
  ;

name:
  ID  { $$ = new_ast_str($ID); }
  | ABORT { $$ = new_ast_str("abort"); }
  | ACTION { $$ = new_ast_str("action"); }
  | ADD { $$ = new_ast_str("add"); }
  | AFTER { $$ = new_ast_str("after"); }
  | ALTER { $$ = new_ast_str("alter"); }
  | ASC { $$ = new_ast_str("asc"); }
  | AT_ID '(' text_args ')' { $$ = new_ast_at_id($text_args); }
  | AT_TMP '(' text_args ')' { $$ = new_ast_at_id(new_ast_text_args(new_ast_str("@TMP"), $text_args)); }
  | AUTOINCREMENT { $$ = new_ast_str("autoincrement"); }
  | BEFORE { $$ = new_ast_str("before"); }
  | CASCADE { $$ = new_ast_str("cascade"); }
  | COLUMN { $$ = new_ast_str("column"); }
  | CREATE { $$ = new_ast_str("create"); }
  | CTE_TABLES { $$ = new_ast_str("cte_tables"); }
  | DEFAULT { $$ = new_ast_str("default"); }
  | DEFERRABLE { $$ = new_ast_str("deferrable"); }
  | DEFERRED { $$ = new_ast_str("deferred"); }
  | DELETE { $$ = new_ast_str("delete"); }
  | DESC { $$ = new_ast_str("desc"); }
  | DROP { $$ = new_ast_str("drop"); }
  | ENCODE { $$ = new_ast_str("encode"); }
  | EXCLUSIVE { $$ = new_ast_str("exclusive"); }
  | EXPLAIN { $$ = new_ast_str("explain"); }
  | EXPR { $$ = new_ast_str("expr"); }
  | FAIL { $$ = new_ast_str("fail"); }
  | FETCH { $$ = new_ast_str("fetch"); }
  | FIRST { $$ = new_ast_str("first"); }
  | FOLLOWING { $$ = new_ast_str("following"); }
  | GROUPS { $$ = new_ast_str("groups"); }
  | HIDDEN { $$ = new_ast_str("hidden"); }
  | IGNORE { $$ = new_ast_str("ignore"); }
  | IMMEDIATE { $$ = new_ast_str("immediate"); }
  | INDEX { $$ = new_ast_str("index"); }
  | INITIALLY { $$ = new_ast_str("initially"); }
  | INSTEAD { $$ = new_ast_str("instead"); }
  | INTO { $$ = new_ast_str("into"); }
  | KEY  { $$ = new_ast_str("key"); }
  | LAST { $$ = new_ast_str("last"); }
  | NULLS { $$ = new_ast_str("nulls"); }
  | OUTER { $$ = new_ast_str("outer"); }
  | PARTITION { $$ = new_ast_str("partition"); }
  | PRECEDING { $$ = new_ast_str("preceding"); }
  | PRIVATE { $$ = new_ast_str("private"); }
  | QUERY_PARTS { $$ = new_ast_str("query_parts"); }
  | RANGE { $$ = new_ast_str("range"); }
  | REFERENCES { $$ = new_ast_str("references"); }
  | RELEASE { $$ = new_ast_str("release"); }
  | RENAME { $$ = new_ast_str("rename"); }
  | REPLACE  { $$ = new_ast_str("replace"); }
  | RESTRICT { $$ = new_ast_str("restrict"); }
  | ROWID  { $$ = new_ast_str("rowid"); }
  | SAVEPOINT { $$ = new_ast_str("savepoint"); }
  | SELECT_CORE { $$ = new_ast_str("select_core"); }
  | SELECT_EXPR { $$ = new_ast_str("select_expr"); }
  | STATEMENT { $$ = new_ast_str("statement"); }
  | STMT_LIST { $$ = new_ast_str("stmt_list"); }
  | TABLE { $$ = new_ast_str("table"); }
  | TEMP { $$ = new_ast_str("temp"); }
  | TEXT  { $$ = new_ast_str("text"); }
  | TRANSACTION { $$ = new_ast_str("transaction"); }
  | TRIGGER  { $$ = new_ast_str("trigger"); }
  | TYPE { $$ = new_ast_str("type"); }
  | VIEW { $$ = new_ast_str("view"); }
  | VIRTUAL { $$ = new_ast_str("virtual"); }
  | WITHOUT { $$ = new_ast_str("without"); }
  ;

loose_name:
  name { $$ = $name; }
  | CALL { $$ = new_ast_str("call"); }
  | SET { $$ = new_ast_str("set"); }
  | BOOL_ { $$ = new_ast_str("bool"); }
  | INT_ { $$ = new_ast_str("int"); }
  | LONG_ { $$ = new_ast_str("long"); }
  | REAL { $$ = new_ast_str("real"); }
  | BLOB { $$ = new_ast_str("blob"); }
  | OBJECT { $$ = new_ast_str("object"); }
  | RIGHT { $$ = new_ast_str("right"); }
  | LEFT { $$ = new_ast_str("left"); }
  ;

loose_name_or_type[r]:
  loose_name[l] { $$ = $l; }
  | ALL { $$ = new_ast_str("all"); }
  | loose_name[l1] '<' loose_name[l2] '>' {
     EXTRACT_STRING(n1, $l1);
     EXTRACT_STRING(n2, $l2);
     $$ = new_ast_str(dup_printf("%s<%s>", n1, n2)); }
  ;


opt_sql_name:
  /* nil */  { $$ = NULL; }
  | sql_name  { $$ = $sql_name; }
  ;

name_list:
  name  { $$ = new_ast_name_list($name, NULL); }
  |  name ',' name_list[nl]  { $$ = new_ast_name_list($name, $nl); }
  ;

sql_name_list:
  sql_name  { $$ = new_ast_name_list($sql_name, NULL); }
  |  sql_name ',' sql_name_list[nl]  { $$ = new_ast_name_list($sql_name, $nl); }
  ;

opt_name_list:
  /* nil */  { $$ = NULL; }
  | name_list  { $$ = $name_list; }
  ;

opt_sql_name_list:
  /* nil */  { $$ = NULL; }
  | sql_name_list  { $$ = $sql_name_list; }
  ;

cte_binding_list:
  cte_binding { $$ = new_ast_cte_binding_list($cte_binding, NULL); }
  | cte_binding ',' cte_binding_list[nl]  { $$ = new_ast_cte_binding_list($cte_binding, $nl); }
  ;

cte_binding: name[formal] name[actual] { $$ = new_ast_cte_binding($formal, $actual); }
  | name[formal] AS name[actual] { $$ = new_ast_cte_binding($formal, $actual); }
  ;

col_attrs:
  /* nil */  { $$ = NULL; }
  | not_null opt_conflict_clause col_attrs[ca]  { $$ = new_ast_col_attrs_not_null($opt_conflict_clause, $ca); }
  | PRIMARY KEY opt_conflict_clause col_attrs[ca]  {
    ast_node *autoinc_and_conflict_clause = new_ast_autoinc_and_conflict_clause(NULL, $opt_conflict_clause);
    $$ = new_ast_col_attrs_pk(autoinc_and_conflict_clause, $ca);
  }
  | PRIMARY KEY opt_conflict_clause AUTOINCREMENT col_attrs[ca]  {
    ast_node *autoinc_and_conflict_clause = new_ast_autoinc_and_conflict_clause(new_ast_col_attrs_autoinc(), $opt_conflict_clause);
    $$ = new_ast_col_attrs_pk(autoinc_and_conflict_clause, $ca);
  }
  | DEFAULT '-' num_literal col_attrs[ca]  { $$ = new_ast_col_attrs_default(new_ast_uminus($num_literal), $ca);}
  | DEFAULT '+' num_literal col_attrs[ca]  { $$ = new_ast_col_attrs_default($num_literal, $ca);}
  | DEFAULT num_literal col_attrs[ca]  { $$ = new_ast_col_attrs_default($num_literal, $ca);}
  | DEFAULT const_expr col_attrs[ca]  { $$ = new_ast_col_attrs_default($const_expr, $ca);}
  | DEFAULT str_literal col_attrs[ca]  { $$ = new_ast_col_attrs_default($str_literal, $ca);}
  | COLLATE name col_attrs[ca]  { $$ = new_ast_col_attrs_collate($name, $ca);}
  | CHECK '(' expr ')' col_attrs[ca]  { $$ = new_ast_col_attrs_check($expr, $ca);}
  | UNIQUE opt_conflict_clause col_attrs[ca]  { $$ = new_ast_col_attrs_unique($opt_conflict_clause, $ca);}
  | HIDDEN col_attrs[ca]  { $$ = new_ast_col_attrs_hidden(NULL, $ca);}
  | AT_SENSITIVE col_attrs[ca]  { $$ = new_ast_sensitive_attr(NULL, $ca); }
  | AT_CREATE version_annotation col_attrs[ca]  { $$ = new_ast_create_attr($version_annotation, $ca);}
  | AT_DELETE version_annotation col_attrs[ca]  { $$ = new_ast_delete_attr($version_annotation, $ca);}
  | fk_target_options col_attrs[ca]  { $$ = new_ast_col_attrs_fk($fk_target_options, $ca); }
  ;

version_annotation:
  '(' INTLIT ',' name ')'  {
    $$ = new_ast_version_annotation(new_ast_option(atoi($INTLIT)), $name); }
  | '(' INTLIT ',' name[lhs] ':' name[rhs] ')'  {
    ast_node *dot = new_ast_dot($lhs, $rhs);
    $$ = new_ast_version_annotation(new_ast_option(atoi($INTLIT)), dot); }
  | '(' INTLIT ')'  {
    $$ = new_ast_version_annotation(new_ast_option(atoi($INTLIT)), NULL); }
  ;

opt_kind:
  /* nil */ { $$ = NULL; }
  | '<' name '>' { $$ = $name; }
  ;

data_type_numeric:
  INT_ opt_kind { $$ = new_ast_type_int($opt_kind); }
  | INTEGER opt_kind { $$ = new_ast_type_int($opt_kind); }
  | REAL opt_kind { $$ = new_ast_type_real($opt_kind); }
  | LONG_ opt_kind { $$ = new_ast_type_long($opt_kind); }
  | BOOL_ opt_kind { $$ = new_ast_type_bool($opt_kind); }
  | LONG_ INTEGER opt_kind { $$ = new_ast_type_long($opt_kind); }
  | LONG_ INT_ opt_kind { $$ = new_ast_type_long($opt_kind); }
  | LONG_INT opt_kind { $$ = new_ast_type_long($opt_kind); }
  | LONG_INTEGER opt_kind { $$ = new_ast_type_long($opt_kind); }
  ;

data_type_any:
  data_type_numeric { $$ = $data_type_numeric; }
  | TEXT  opt_kind { $$ = new_ast_type_text($opt_kind);  }
  | BLOB  opt_kind { $$ = new_ast_type_blob($opt_kind); }
  | OBJECT opt_kind { $$ = new_ast_type_object($opt_kind); }
  | OBJECT '<' name CURSOR '>' { /* special case for boxed cursor */
    CSTR type = dup_printf("%s CURSOR", AST_STR($name));
    $$ = new_ast_type_object(new_ast_str(type)); }
  | OBJECT '<' name SET '>' { /* special case for result sets */
    CSTR type = dup_printf("%s SET", AST_STR($name));
    $$ = new_ast_type_object(new_ast_str(type)); }
  | ID { $$ = new_ast_str($ID); }
  | AT_ID '(' text_args ')' { $$ = new_ast_at_id($text_args); }
  ;

not_null: NOT NULL_ | '!'
  ;

data_type_with_options:
  data_type_any { $$ = $data_type_any; }
  | data_type_any not_null { $$ = new_ast_notnull($data_type_any); }
  | data_type_any AT_SENSITIVE { $$ = new_ast_sensitive_attr($data_type_any, NULL); }
  | data_type_any AT_SENSITIVE not_null { $$ = new_ast_sensitive_attr(new_ast_notnull($data_type_any), NULL); }
  | data_type_any not_null AT_SENSITIVE { $$ = new_ast_sensitive_attr(new_ast_notnull($data_type_any), NULL); }
  ;

str_literal:
  str_chain { $$ = reduce_str_chain($str_chain); }
  ;

str_chain:
  str_leaf { $$ = new_ast_str_chain($str_leaf, NULL); }
  | str_leaf str_chain[next] { $$ = new_ast_str_chain($str_leaf, $next); }
  ;

str_leaf:
  STRLIT  { $$ = new_ast_str($STRLIT);}
  | CSTRLIT  { $$ = new_ast_cstr($CSTRLIT); }
  ;

num_literal:
  INTLIT  { $$ = new_ast_num(NUM_INT, $INTLIT); }
  | LONGLIT  { $$ = new_ast_num(NUM_LONG, $LONGLIT); }
  | REALLIT  { $$ = new_ast_num(NUM_REAL, $REALLIT); }
  | TRUE_ { $$ = new_ast_num(NUM_BOOL, "1"); }
  | FALSE_ { $$ = new_ast_num(NUM_BOOL, "0"); }
  ;

const_expr:
  CONST '(' expr ')' { $$ = new_ast_const($expr); }
  ;

any_literal:
  str_literal  { $$ = $str_literal; }
  | num_literal  { $$ = $num_literal; }
  | NULL_  { $$ = new_ast_null(); }
  | AT_FILE '(' str_literal ')'  { $$ = file_literal($str_literal); }
  | AT_LINE  { $$ = new_ast_num(NUM_INT, dup_printf("%d", yylineno)); }
  | AT_MACRO_LINE { $$ = new_ast_str("@MACRO_LINE"); }
  | AT_MACRO_FILE { $$ = new_ast_str("@MACRO_FILE"); }
  | AT_PROC  { $$ = new_ast_str("@PROC"); }
  | AT_TEXT '(' text_args ')' { $$ = new_ast_macro_text($text_args); }
  | BLOBLIT  { $$ = new_ast_blob($BLOBLIT); }
  ;

text_args:
   text_arg { $$ = new_ast_text_args($text_arg, NULL); }
   | text_arg ',' text_args[ta] { $$ = new_ast_text_args($text_arg, $ta); }
   ;

text_arg : expr ;

raise_expr:
  RAISE '(' IGNORE ')'  { $$ = new_ast_raise(new_ast_option(RAISE_IGNORE), NULL); }
  | RAISE '(' ROLLBACK ','  expr ')'  { $$ = new_ast_raise(new_ast_option(RAISE_ROLLBACK), $expr); }
  | RAISE '(' ABORT ','  expr ')'  { $$ = new_ast_raise(new_ast_option(RAISE_ABORT), $expr); }
  | RAISE '(' FAIL ','  expr ')'  { $$ = new_ast_raise(new_ast_option(RAISE_FAIL), $expr); }
  ;

opt_distinct:
  /* nil */ { $$ = NULL; }
  | DISTINCT { $$ = new_ast_distinct(); }
  ;

simple_call:
  loose_name[name] '(' opt_distinct arg_list ')' opt_filter_clause  {
      YY_ERROR_ON_CQL_INFERRED_NOTNULL($name);
      struct ast_node *call_filter_clause = new_ast_call_filter_clause($opt_distinct, $opt_filter_clause);
      struct ast_node *call_arg_list = new_ast_call_arg_list(call_filter_clause, $arg_list);
      $$ = new_ast_call($name, call_arg_list); }
  | GLOB '(' opt_distinct arg_list ')' opt_filter_clause  {
      ast_node *name = new_ast_str("glob");
      struct ast_node *call_filter_clause = new_ast_call_filter_clause($opt_distinct, $opt_filter_clause);
      struct ast_node *call_arg_list = new_ast_call_arg_list(call_filter_clause, $arg_list);
      $$ = new_ast_call(name, call_arg_list); }
  | LIKE '(' opt_distinct arg_list ')' opt_filter_clause  {
      ast_node *name = new_ast_str("like");
      struct ast_node *call_filter_clause = new_ast_call_filter_clause($opt_distinct, $opt_filter_clause);
      struct ast_node *call_arg_list = new_ast_call_arg_list(call_filter_clause, $arg_list);
      $$ = new_ast_call(name, call_arg_list); }
  ;

call:
  simple_call { $$ = $simple_call; }
  | basic_expr ':' simple_call { $$ = new_ast_reverse_apply($basic_expr, $simple_call); }
  | basic_expr ':' loose_name[name] { $$ = new_ast_reverse_apply($basic_expr, new_simple_call_from_name($name)); }
  | basic_expr ':' '(' arg_list ')' { $$ = new_ast_reverse_apply_poly_args($basic_expr, $arg_list); }
  | basic_expr ':' ID '!' {
     YY_ERROR_ON_MACRO_ARG($ID);
     $$ = new_macro_ref_node($ID, new_ast_macro_args(new_ast_expr_macro_arg($basic_expr), NULL)); }
  | basic_expr ':' ID '!' '(' opt_macro_args ')' {
     YY_ERROR_ON_MACRO_ARG($ID);
     $$ = new_macro_ref_node($ID, new_ast_macro_args(new_ast_expr_macro_arg($basic_expr), $opt_macro_args)); }
  ;

basic_expr:
  name  { $$ = $name; }
  | QID { $$ = new_ast_qstr_quoted($QID); }
  | macro_ref { $$ = $macro_ref; }
  | '*' { $$ = new_ast_star(); }
  | AT_RC { $$ = new_ast_str("@RC"); }
  | basic_expr[lhs] '.' sql_name[rhs] { $$ = new_ast_dot($lhs, $rhs); }
  | basic_expr[lhs] '.' '*' { $$ = new_ast_table_star($lhs); }
  | any_literal  { $$ = $any_literal; }
  | const_expr { $$ = $const_expr; }
  | '(' expr ')'  { $$ = $expr; }
  | call  { $$ = $call; }
  | window_func_inv  { $$ = $window_func_inv; }
  | raise_expr  { $$ = $raise_expr; }
  | '(' select_stmt ')'  { $$ = $select_stmt; }
  | '(' select_stmt IF NOTHING expr ')'  { $$ = new_ast_select_if_nothing_expr($select_stmt, $expr); }
  | '(' select_stmt IF NOTHING OR NULL_ expr ')'  { $$ = new_ast_select_if_nothing_or_null_expr($select_stmt, $expr); }
  | '(' select_stmt IF NOTHING OR NULL_ THEN expr ')'  { $$ = new_ast_select_if_nothing_or_null_expr($select_stmt, $expr); }
  | '(' select_stmt IF NOTHING OR NULL_ THEN THROW ')'  { $$ = new_ast_select_if_nothing_or_null_throw_expr($select_stmt); }
  | '(' select_stmt IF NOTHING OR NULL_ THROW ')'  { $$ = new_ast_select_if_nothing_or_null_throw_expr($select_stmt); }
  | '(' select_stmt IF NOTHING THEN expr ')'  { $$ = new_ast_select_if_nothing_expr($select_stmt, $expr); }
  | '(' select_stmt IF NOTHING THEN THROW')'  { $$ = new_ast_select_if_nothing_throw_expr($select_stmt); }
  | '(' select_stmt IF NOTHING THROW')'  { $$ = new_ast_select_if_nothing_throw_expr($select_stmt); }
  | EXISTS '(' select_stmt ')'  { $$ = new_ast_exists_expr($select_stmt); }
  | CASE expr[cond] case_list END  { $$ = new_ast_case_expr($cond, new_ast_connector($case_list, NULL)); }
  | CASE expr[cond1] case_list ELSE expr[cond2] END  { $$ = new_ast_case_expr($cond1, new_ast_connector($case_list, $cond2));}
  | CASE case_list END  { $$ = new_ast_case_expr(NULL, new_ast_connector($case_list, NULL));}
  | CASE case_list ELSE expr[cond] END  { $$ = new_ast_case_expr(NULL, new_ast_connector($case_list, $cond));}
  | CAST '(' expr[sexp] AS data_type_any ')'  { $$ = new_ast_cast_expr($sexp, $data_type_any); }
  | TYPE_CHECK '(' expr[sexp] AS data_type_with_options[type] ')' { $$ = new_ast_type_check_expr($sexp, $type); }
  | basic_expr[array] '[' arg_list ']' { $$ = new_ast_array($array, $arg_list); }
  | basic_expr[lhs] '~' data_type_any '~' { $$ = new_ast_cast_expr($lhs, $data_type_any); }
  | basic_expr[lhs] JEX1 basic_expr[rhs]  { $$ = new_ast_jex1($lhs, $rhs); }
  | basic_expr[lhs] JEX2 '~' data_type_any '~' basic_expr[rhs] { $$ = new_ast_jex2($lhs, new_ast_jex2($data_type_any,$rhs)); }
  ;

math_expr:
  basic_expr  { $$ = $basic_expr; }
  | math_expr[lhs] '&' math_expr[rhs]  { $$ = new_ast_bin_and($lhs, $rhs); }
  | math_expr[lhs] '|' math_expr[rhs]  { $$ = new_ast_bin_or($lhs, $rhs); }
  | math_expr[lhs] LS math_expr[rhs]  { $$ = new_ast_lshift($lhs, $rhs); }
  | math_expr[lhs] RS  math_expr[rhs]  { $$ = new_ast_rshift($lhs, $rhs); }
  | math_expr[lhs] '+' math_expr[rhs]  { $$ = new_ast_add($lhs, $rhs); }
  | math_expr[lhs] '-' math_expr[rhs]  { $$ = new_ast_sub($lhs, $rhs); }
  | math_expr[lhs] '*' math_expr[rhs]  { $$ = new_ast_mul($lhs, $rhs); }
  | math_expr[lhs] '/' math_expr[rhs]  { $$ = new_ast_div($lhs, $rhs); }
  | math_expr[lhs] '%' math_expr[rhs]  { $$ = new_ast_mod($lhs, $rhs); }
  | math_expr[lhs] IS_NOT_TRUE  { $$ = new_ast_is_not_true($lhs); }
  | math_expr[lhs] IS_NOT_FALSE  { $$ = new_ast_is_not_false($lhs); }
  | math_expr[lhs] ISNULL  { $$ = new_ast_is($lhs, new_ast_null()); }
  | math_expr[lhs] NOTNULL  { $$ = new_ast_is_not($lhs, new_ast_null()); }
  | math_expr[lhs] IS_TRUE  { $$ = new_ast_is_true($lhs); }
  | math_expr[lhs] IS_FALSE  { $$ = new_ast_is_false($lhs); }
  | '-' math_expr[rhs] %prec UMINUS { $$ = new_ast_uminus($rhs); }
  | '+' math_expr[rhs] %prec UMINUS { $$ = $rhs; }
  | '~' math_expr[rhs] %prec UMINUS { $$ = new_ast_tilde($rhs); }
  | NOT math_expr[rhs]  { $$ = new_ast_not($rhs); }
  | math_expr[lhs] '=' math_expr[rhs]  { $$ = new_ast_eq($lhs, $rhs); }
  | math_expr[lhs] EQEQ math_expr[rhs]  { $$ = new_ast_eq($lhs, $rhs); }
  | math_expr[lhs] '<' math_expr[rhs]  { $$ = new_ast_lt($lhs, $rhs); }
  | math_expr[lhs] '>' math_expr[rhs]  { $$ = new_ast_gt($lhs, $rhs); }
  | math_expr[lhs] NE math_expr[rhs]  { $$ = new_ast_ne($lhs, $rhs); }
  | math_expr[lhs] NE_ math_expr[rhs]  { $$ = new_ast_ne($lhs, $rhs); }
  | math_expr[lhs] GE math_expr[rhs]  { $$ = new_ast_ge($lhs, $rhs); }
  | math_expr[lhs] LE math_expr[rhs]  { $$ = new_ast_le($lhs, $rhs); }
  | math_expr[lhs] NOT_IN '(' opt_expr_list ')'  { $$ = new_ast_not_in($lhs, $opt_expr_list); }
  | math_expr[lhs] NOT_IN '(' select_stmt ')'  { $$ = new_ast_not_in($lhs, $select_stmt); }
  | math_expr[lhs] IN '(' opt_expr_list ')'  { $$ = new_ast_in_pred($lhs, $opt_expr_list); }
  | math_expr[lhs] IN '(' select_stmt ')'  { $$ = new_ast_in_pred($lhs, $select_stmt); }
  | math_expr[lhs] LIKE math_expr[rhs]  { $$ = new_ast_like($lhs, $rhs); }
  | math_expr[lhs] NOT_LIKE math_expr[rhs] { $$ = new_ast_not_like($lhs, $rhs); }
  | math_expr[lhs] MATCH math_expr[rhs]  { $$ = new_ast_match($lhs, $rhs); }
  | math_expr[lhs] NOT_MATCH math_expr[rhs] { $$ = new_ast_not_match($lhs, $rhs); }
  | math_expr[lhs] REGEXP math_expr[rhs]  { $$ = new_ast_regexp($lhs, $rhs); }
  | math_expr[lhs] NOT_REGEXP math_expr[rhs] { $$ = new_ast_not_regexp($lhs, $rhs); }
  | math_expr[lhs] GLOB math_expr[rhs]  { $$ = new_ast_glob($lhs, $rhs); }
  | math_expr[lhs] NOT_GLOB math_expr[rhs] { $$ = new_ast_not_glob($lhs, $rhs); }
  | math_expr[lhs] BETWEEN math_expr[me1] %prec BETWEEN AND math_expr[me2]  { $$ = new_ast_between($lhs, new_ast_range($me1,$me2)); }
  | math_expr[lhs] NOT_BETWEEN math_expr[me1] %prec BETWEEN AND math_expr[me2]  { $$ = new_ast_not_between($lhs, new_ast_range($me1,$me2)); }
  | math_expr[lhs] IS_NOT math_expr[rhs]  { $$ = new_ast_is_not($lhs, $rhs); }
  | math_expr[lhs] IS math_expr[rhs]  { $$ = new_ast_is($lhs, $rhs); }
  | math_expr[lhs] CONCAT math_expr[rhs]  { $$ = new_ast_concat($lhs, $rhs); }
  | math_expr[lhs] COLLATE name { $$ = new_ast_collate($lhs, $name); }
  ;

expr:
  math_expr { $$ = $math_expr; }
  | expr[lhs] AND expr[rhs]  { $$ = new_ast_and($lhs, $rhs); }
  | expr[lhs] OR expr[rhs]  { $$ = new_ast_or($lhs, $rhs); }
  | expr[lhs] ASSIGN expr[rhs] { $$ = new_ast_expr_assign($lhs, $rhs); }
  | expr[lhs] ADD_EQ expr[rhs] { $$ = new_ast_add_eq($lhs, $rhs); }
  | expr[lhs] SUB_EQ expr[rhs] { $$ = new_ast_sub_eq($lhs, $rhs); }
  | expr[lhs] DIV_EQ expr[rhs] { $$ = new_ast_div_eq($lhs, $rhs); }
  | expr[lhs] MUL_EQ expr[rhs] { $$ = new_ast_mul_eq($lhs, $rhs); }
  | expr[lhs] MOD_EQ expr[rhs] { $$ = new_ast_mod_eq($lhs, $rhs); }
  | expr[lhs] AND_EQ expr[rhs] { $$ = new_ast_and_eq($lhs, $rhs); }
  | expr[lhs] OR_EQ expr[rhs] { $$ = new_ast_or_eq($lhs, $rhs); }
  | expr[lhs] LS_EQ expr[rhs] { $$ = new_ast_ls_eq($lhs, $rhs); }
  | expr[lhs] RS_EQ expr[rhs] { $$ = new_ast_rs_eq($lhs, $rhs); }
  ;

case_list:
  WHEN expr[e1] THEN expr[e2]  { $$ = new_ast_case_list(new_ast_when($e1, $e2), NULL); }
  | WHEN expr[e1] THEN expr[e2] case_list[cl]  { $$ = new_ast_case_list(new_ast_when($e1, $e2), $cl);}
  ;

arg_expr: expr { $$ = $expr; }
  | shape_arguments { $$ = $shape_arguments; }
  ;

arg_exprs:
  arg_expr  { $$ = new_ast_arg_list($arg_expr, NULL); }
  | arg_expr ',' arg_exprs[al]  { $$ = new_ast_arg_list($arg_expr, $al); }
  ;

arg_list:
  /* nil */  { $$ = NULL; }
  | arg_exprs { $$ = $arg_exprs; }
  ;

opt_expr_list:
  /* nil */ { $$ = NULL; }
  | expr_list { $$ = $expr_list; }
  ;

expr_list:
  expr  { $$ = new_ast_expr_list($expr, NULL); }
  | expr ',' expr_list[el]  { $$ = new_ast_expr_list($expr, $el); }
  ;

shape_arguments:
  FROM name  { $$ = new_ast_from_shape($name, NULL); }
  | FROM name shape_def  { $$ = new_ast_from_shape($name, $shape_def); }
  | FROM ARGUMENTS  { $$ = new_ast_from_shape(new_ast_str("ARGUMENTS"), NULL); }
  | FROM ARGUMENTS shape_def  { $$ = new_ast_from_shape(new_ast_str("ARGUMENTS"), $shape_def); }
  ;

column_calculation:
  AT_COLUMNS '(' col_calcs ')' {
    $$ = new_ast_column_calculation($col_calcs, NULL); }
  | AT_COLUMNS '(' DISTINCT col_calcs ')' {
    $$ = new_ast_column_calculation($col_calcs, new_ast_distinct()); }
  ;

col_calcs:
  col_calc  { $$ = new_ast_col_calcs($col_calc, NULL); }
  | col_calc ',' col_calcs[list] { $$ = new_ast_col_calcs($col_calc, $list); }
  ;

col_calc:
  sql_name { $$ = new_ast_col_calc($sql_name, NULL); }
  | shape_def { $$ = new_ast_col_calc(NULL, $shape_def); }
  | sql_name shape_def { $$ = new_ast_col_calc($sql_name, $shape_def); }
  | sql_name[n1] '.' sql_name[n2] { $$ = new_ast_col_calc(new_ast_dot($n1, $n2), NULL); }
  ;

cte_tables:
  cte_table  { $$ = new_ast_cte_tables($cte_table, NULL); }
  | cte_table ',' cte_tables[ct]  { $$ = new_ast_cte_tables($cte_table, $ct); }
  ;

cte_decl:
  name '(' sql_name_list ')'  { $$ = new_ast_cte_decl($name, $sql_name_list); }
  | name '(' '*' ')'  { $$ = new_ast_cte_decl($name, new_ast_star()); }
  | name { $$ = new_ast_cte_decl($name, new_ast_star()); }
  ;

shared_cte:
  call_stmt { $$ = new_ast_shared_cte($call_stmt, NULL); }
  | call_stmt USING cte_binding_list { $$ = new_ast_shared_cte($call_stmt, $cte_binding_list); }
  ;

cte_table:
  cte_decl AS '(' select_stmt ')'  { $$ = new_ast_cte_table($cte_decl, $select_stmt); }
  | cte_decl AS '(' shared_cte')' { $$ = new_ast_cte_table($cte_decl, $shared_cte); }
  | '(' call_stmt ')' {
      ast_node *name = ast_clone_tree($call_stmt->left);
      ast_node *cte_decl =  new_ast_cte_decl(name, new_ast_star());
      ast_node *shared_cte = new_ast_shared_cte($call_stmt, NULL);
      $$ = new_ast_cte_table(cte_decl, shared_cte); }
  | '(' call_stmt USING cte_binding_list ')' {
      ast_node *name = ast_clone_tree($call_stmt->left);
      ast_node *cte_decl =  new_ast_cte_decl(name, new_ast_star());
      ast_node *shared_cte = new_ast_shared_cte($call_stmt, $cte_binding_list);
      $$ = new_ast_cte_table(cte_decl, shared_cte); }
  | cte_decl LIKE '(' select_stmt ')'  {
      $$ = new_ast_cte_table($cte_decl, new_ast_like($select_stmt, NULL)); }
  | cte_decl LIKE sql_name  {
      $$ = new_ast_cte_table($cte_decl, new_ast_like($sql_name, NULL)); }
  | macro_ref[ref] { $$ = $ref; }
  ;

with_prefix:
  WITH cte_tables  { $$ = new_ast_with($cte_tables); }
  | WITH RECURSIVE cte_tables  { $$ = new_ast_with_recursive($cte_tables); }
  ;

with_select_stmt:
  with_prefix select_stmt_no_with  { $$ = new_ast_with_select_stmt($with_prefix, $select_stmt_no_with); }
  ;

select_nothing_stmt:
  SELECT NOTHING { $$ = new_ast_select_nothing_stmt(); }
  ;

select_stmt:
  with_select_stmt  { $$ = $with_select_stmt; }
  | select_stmt_no_with  { $$ = $select_stmt_no_with; }
  ;

select_stmt_no_with:
  select_core_list opt_orderby opt_limit opt_offset  {
      struct ast_node *select_offset = new_ast_select_offset($opt_offset, NULL);
      struct ast_node *select_limit = new_ast_select_limit($opt_limit, select_offset);
      struct ast_node *select_orderby = new_ast_select_orderby($opt_orderby, select_limit);
       $$ = new_ast_select_stmt($select_core_list, select_orderby);
  }
  ;

select_core_list:
  select_core { $$ = new_ast_select_core_list($select_core, NULL); }
  | select_core compound_operator select_core_list[list] {
     ast_node *select_core_compound = new_ast_select_core_compound(new_ast_option($compound_operator), $list);
     $$ = new_ast_select_core_list($select_core, select_core_compound); }
  ;

values:
  '(' insert_list ')'  {
    $$ = new_ast_values($insert_list, NULL);
  }
  | '(' insert_list ')' ',' values[ov]  {
    $$ = new_ast_values($insert_list, $ov);
  }
  ;

select_core:
  SELECT select_opts select_expr_list opt_from_query_parts opt_where opt_groupby opt_having opt_select_window  {
    struct ast_node *select_having = new_ast_select_having($opt_having, $opt_select_window);
    struct ast_node *select_groupby = new_ast_select_groupby($opt_groupby, select_having);
    struct ast_node *select_where = new_ast_select_where($opt_where, select_groupby);
    struct ast_node *select_from_etc = new_ast_select_from_etc($opt_from_query_parts, select_where);
    struct ast_node *select_expr_list_con = new_ast_select_expr_list_con($select_expr_list, select_from_etc);
     $$ = new_ast_select_core($select_opts, select_expr_list_con);
  }
  | ROWS '(' macro_ref ')' { $$ = $macro_ref; }
  | VALUES values  {
    $$ = new_ast_select_core(new_ast_select_values(), $values);
  }
  ;

compound_operator:
  UNION  { $$ = COMPOUND_OP_UNION; }
  | UNION_ALL  { $$ = COMPOUND_OP_UNION_ALL; }
  | INTERSECT  { $$ = COMPOUND_OP_INTERSECT; }
  | EXCEPT  { $$ = COMPOUND_OP_EXCEPT; }
  ;

window_func_inv:
  simple_call OVER window_name_or_defn  {
    EXTRACT(call, $simple_call);
    EXTRACT_NOTNULL(call_arg_list, call->right);
    EXTRACT_NOTNULL(call_filter_clause, call_arg_list->left);
    EXTRACT(distinct, call_filter_clause->left);
    YY_ERROR_ON_DISTINCT(distinct);
    $$ = new_ast_window_func_inv($simple_call, $window_name_or_defn);
  }
  ;

opt_filter_clause:
  /* nil */  { $$ = NULL; }
  | FILTER '(' opt_where ')'  { $$ = new_ast_opt_filter_clause($opt_where); }
  ;

window_name_or_defn: window_defn
  | name
  ;

window_defn:
  '(' opt_partition_by opt_orderby opt_frame_spec ')'  {
    ast_node *window_defn_orderby = new_ast_window_defn_orderby($opt_orderby, $opt_frame_spec);
    $$ = new_ast_window_defn($opt_partition_by, window_defn_orderby);
  }
  ;

opt_frame_spec:
  /* nil */  { $$ = NULL; }
  | frame_type frame_boundary_opts frame_exclude  {
    int32_t frame_boundary_opts_flags = (int32_t)((int_ast_node *)($frame_boundary_opts)->left)->value;
    int32_t flags = $frame_type | frame_boundary_opts_flags | $frame_exclude;
    ast_node *expr_list = $frame_boundary_opts->right;
    $$ = new_ast_opt_frame_spec(new_ast_option(flags), expr_list);
  }
  ;

frame_type:
  RANGE  { $$ = FRAME_TYPE_RANGE; }
  | ROWS  { $$ = FRAME_TYPE_ROWS; }
  | GROUPS  { $$ = FRAME_TYPE_GROUPS; }
  ;

frame_exclude:
  /* nil */  { $$ = FRAME_EXCLUDE_NONE; }
  | EXCLUDE_NO_OTHERS  { $$ = FRAME_EXCLUDE_NO_OTHERS; }
  | EXCLUDE_CURRENT_ROW  { $$ = FRAME_EXCLUDE_CURRENT_ROW; }
  | EXCLUDE_GROUP  { $$ = FRAME_EXCLUDE_GROUP; }
  | EXCLUDE_TIES  { $$ = FRAME_EXCLUDE_TIES; }
  ;

frame_boundary_opts:
  frame_boundary  {
    ast_node *ast_flags = $frame_boundary->left;
    ast_node *expr_list = new_ast_expr_list($frame_boundary->right, NULL);
    $$ = new_ast_frame_boundary_opts(ast_flags, expr_list);
  }
  | BETWEEN frame_boundary_start AND frame_boundary_end  {
    int32_t flags = (int32_t)(((int_ast_node *)$frame_boundary_start->left)->value | ((int_ast_node *)$frame_boundary_end->left)->value);
    ast_node *expr_list = new_ast_expr_list($frame_boundary_start->right, $frame_boundary_end->right);
    $$ = new_ast_frame_boundary_opts(new_ast_option(flags), expr_list);
  }
  ;

frame_boundary_start:
  UNBOUNDED PRECEDING  { $$ = new_ast_frame_boundary_start(new_ast_option(FRAME_BOUNDARY_START_UNBOUNDED), NULL); }
  | expr PRECEDING  { $$ = new_ast_frame_boundary_start(new_ast_option(FRAME_BOUNDARY_START_PRECEDING), $expr); }
  | CURRENT_ROW  { $$ = new_ast_frame_boundary_start(new_ast_option(FRAME_BOUNDARY_START_CURRENT_ROW), NULL); }
  | expr FOLLOWING  { $$ = new_ast_frame_boundary_start(new_ast_option(FRAME_BOUNDARY_START_FOLLOWING), $expr); }
  ;

frame_boundary_end:
  expr PRECEDING  { $$ = new_ast_frame_boundary_end(new_ast_option(FRAME_BOUNDARY_END_PRECEDING), $expr); }
  | CURRENT_ROW  { $$ = new_ast_frame_boundary_end(new_ast_option(FRAME_BOUNDARY_END_CURRENT_ROW), NULL); }
  | expr FOLLOWING  { $$ = new_ast_frame_boundary_end(new_ast_option(FRAME_BOUNDARY_END_FOLLOWING), $expr); }
  | UNBOUNDED FOLLOWING  { $$ = new_ast_frame_boundary_end(new_ast_option(FRAME_BOUNDARY_END_UNBOUNDED), NULL); }
  ;

frame_boundary:
  UNBOUNDED PRECEDING  { $$ = new_ast_frame_boundary(new_ast_option(FRAME_BOUNDARY_UNBOUNDED), NULL); }
  | expr PRECEDING  { $$ = new_ast_frame_boundary(new_ast_option(FRAME_BOUNDARY_PRECEDING), $expr); }
  | CURRENT_ROW  { $$ = new_ast_frame_boundary(new_ast_option(FRAME_BOUNDARY_CURRENT_ROW), NULL); }
  ;

opt_partition_by:
  /* nil */  { $$ = NULL; }
  | PARTITION BY expr_list  { $$ = new_ast_opt_partition_by($expr_list); }
  ;

opt_select_window:
  /* nil */  { $$ = NULL; }
  | window_clause  { $$ = new_ast_opt_select_window($window_clause); }
  ;

window_clause:
  WINDOW window_name_defn_list  { $$ = new_ast_window_clause($window_name_defn_list); }
  ;

window_name_defn_list:
  window_name_defn  { $$ = new_ast_window_name_defn_list($window_name_defn, NULL); }
  | window_name_defn ',' window_name_defn_list[wndl]  { $$ = new_ast_window_name_defn_list($window_name_defn, $wndl); }
  ;

window_name_defn:
  name AS window_defn  { $$ = new_ast_window_name_defn($name, $window_defn); }
  ;

region_spec:
    name  { $$ = new_ast_region_spec($name, new_ast_option(PUBLIC_REGION)); }
  | name PRIVATE  { $$ = new_ast_region_spec($name, new_ast_option(PRIVATE_REGION)); }
  ;

region_list:
  region_spec ',' region_list[rl]  { $$ = new_ast_region_list($region_spec, $rl); }
  | region_spec  { $$ = new_ast_region_list($region_spec, NULL); }
  ;

declare_schema_region_stmt:
  AT_DECLARE_SCHEMA_REGION name  { $$ = new_ast_declare_schema_region_stmt($name, NULL); }
  | AT_DECLARE_SCHEMA_REGION name USING region_list  { $$ = new_ast_declare_schema_region_stmt($name, $region_list); }
  ;

declare_deployable_region_stmt:
  AT_DECLARE_DEPLOYABLE_REGION  name  { $$ = new_ast_declare_deployable_region_stmt($name, NULL); }
  | AT_DECLARE_DEPLOYABLE_REGION name USING region_list  { $$ = new_ast_declare_deployable_region_stmt($name, $region_list); }
  ;

begin_schema_region_stmt:
  AT_BEGIN_SCHEMA_REGION name  {$$ = new_ast_begin_schema_region_stmt($name); }
  ;

end_schema_region_stmt:
  AT_END_SCHEMA_REGION  {$$ = new_ast_end_schema_region_stmt(); }
  ;

schema_unsub_stmt:
  AT_UNSUB  '(' sql_name ')' { $$ = new_ast_schema_unsub_stmt(new_ast_version_annotation(new_ast_option(1), $sql_name)); }
  ;

schema_ad_hoc_migration_stmt:
  AT_SCHEMA_AD_HOC_MIGRATION version_annotation
    { $$ = new_ast_schema_ad_hoc_migration_stmt($version_annotation, NULL); }
  | AT_SCHEMA_AD_HOC_MIGRATION FOR AT_RECREATE '(' name[group] ',' name[proc] ')'
    { $$ = new_ast_schema_ad_hoc_migration_stmt($group, $proc); }
  ;

emit_enums_stmt:
  AT_EMIT_ENUMS opt_name_list { $$ = new_ast_emit_enums_stmt($opt_name_list); }
  ;

emit_group_stmt:
  AT_EMIT_GROUP opt_name_list { $$ = new_ast_emit_group_stmt($opt_name_list); }
  ;

emit_constants_stmt:
  AT_EMIT_CONSTANTS name_list { $$ = new_ast_emit_constants_stmt($name_list); }
  ;

opt_from_query_parts:
  /* nil */  { $$ = NULL; }
  | FROM query_parts  { $$ = $query_parts; }
  ;

opt_where:
  /* nil */  { $$ = NULL; }
  | WHERE expr  { $$ = new_ast_opt_where($expr); }
  ;

opt_groupby:
  /* nil */  { $$ = NULL; }
  | GROUP BY groupby_list  { $$ = new_ast_opt_groupby($groupby_list); }
  ;

groupby_list:
  groupby_item  { $$ = new_ast_groupby_list($groupby_item, NULL); }
  | groupby_item ',' groupby_list[gl]  { $$ = new_ast_groupby_list($groupby_item, $gl); }
  ;

groupby_item:
  expr  { $$ = new_ast_groupby_item($expr); }
  ;

opt_asc_desc:
  /* nil */  { $$ = NULL; }
  | ASC  opt_nullsfirst_nullslast { $$ = new_ast_asc($opt_nullsfirst_nullslast); }
  | DESC  opt_nullsfirst_nullslast { $$ = new_ast_desc($opt_nullsfirst_nullslast); }
  ;

opt_nullsfirst_nullslast:
  /* nil */  { $$ = NULL; }
  | NULLS FIRST  { $$ = new_ast_nullsfirst(); }
  | NULLS LAST  { $$ = new_ast_nullslast(); }
  ;

opt_having:
  /* nil */  { $$ = NULL; }
  | HAVING expr  { $$ = new_ast_opt_having($expr); }
  ;

opt_orderby:
  /* nil */  { $$ = NULL; }
  | ORDER BY orderby_list  { $$ = new_ast_opt_orderby($orderby_list); }
  ;

orderby_list:
  orderby_item  { $$ = new_ast_orderby_list($orderby_item, NULL); }
  | orderby_item ',' orderby_list[gl]  { $$ = new_ast_orderby_list($orderby_item, $gl); }
  ;

orderby_item:
  expr opt_asc_desc  { $$ = new_ast_orderby_item($expr, $opt_asc_desc); }
  ;

opt_limit:
  /* nil */  { $$ = NULL; }
  | LIMIT expr  { $$ = new_ast_opt_limit($expr); }
  ;

opt_offset:
  /* nil */  { $$ = NULL; }
  | OFFSET expr  { $$ = new_ast_opt_offset($expr); }
  ;

select_opts:
  /* nil */  { $$ = NULL; }
  | ALL  { $$ = new_ast_select_opts(new_ast_all()); }
  | DISTINCT  { $$ = new_ast_select_opts(new_ast_distinct()); }
  | DISTINCTROW  { $$ = new_ast_select_opts(new_ast_distinctrow()); }
  ;

select_expr_list:
  select_expr  { $$ = new_ast_select_expr_list($select_expr, NULL); }
  | select_expr ',' select_expr_list[sel]  { $$ = new_ast_select_expr_list($select_expr, $sel); }
  ;

select_expr:
  expr opt_as_alias  {
    if (is_ast_select_expr_macro_ref($expr) || is_ast_select_expr_macro_arg_ref($expr)) {
       $$ = $expr;
    }
    else if (is_ast_table_star($expr) || is_ast_star($expr)) {
      YY_ERROR_ON_ALIAS_PRESENT($opt_as_alias);
      $$ = $expr;
    }
    else {
      $$ = new_ast_select_expr($expr, $opt_as_alias);
    }
  }
  | column_calculation  { $$ = $column_calculation; }
  ;

opt_as_alias:
  /* nil */  { $$ = NULL;  }
  | as_alias
  ;

as_alias:
  AS sql_name  { $$ = new_ast_opt_as_alias($sql_name); }
  | sql_name  { $$ = new_ast_opt_as_alias($sql_name); }
  ;

query_parts:
  table_or_subquery_list  { $$ = $table_or_subquery_list; }
  | join_clause  { $$ = $join_clause; }
  ;

table_or_subquery_list:
  table_or_subquery  { $$ = new_ast_table_or_subquery_list($table_or_subquery, NULL); }
  | table_or_subquery ',' table_or_subquery_list[tsl]  { $$ = new_ast_table_or_subquery_list($table_or_subquery, $tsl); }
  ;

join_clause:
  table_or_subquery join_target_list  { $$ = new_ast_join_clause($table_or_subquery, $join_target_list); }
  ;

join_target_list:
  join_target  { $$ = new_ast_join_target_list($join_target, NULL); }
  | join_target join_target_list[jtl]  { $$ = new_ast_join_target_list($join_target, $jtl); }
  ;

table_or_subquery:
  sql_name opt_as_alias  { $$ = new_ast_table_or_subquery($sql_name, $opt_as_alias); }
  | '(' select_stmt ')' opt_as_alias  { $$ = new_ast_table_or_subquery($select_stmt, $opt_as_alias); }
  | '(' shared_cte ')' opt_as_alias  { $$ = new_ast_table_or_subquery($shared_cte, $opt_as_alias); }
  | table_function opt_as_alias  { $$ = new_ast_table_or_subquery($table_function, $opt_as_alias); }
  | '(' query_parts ')'  { $$ = new_ast_table_or_subquery($query_parts, NULL); }
  |  macro_ref[qp] opt_as_alias { $$ = new_ast_table_or_subquery($qp, $opt_as_alias); }
  ;

join_type:
  /* nil */      { $$ = JOIN_INNER; }
  | LEFT         { $$ = JOIN_LEFT; }
  | RIGHT        { $$ = JOIN_RIGHT; }
  | LEFT OUTER   { $$ = JOIN_LEFT_OUTER; }
  | RIGHT OUTER  { $$ = JOIN_RIGHT_OUTER; }
  | INNER        { $$ = JOIN_INNER; }
  | CROSS        { $$ = JOIN_CROSS; }
  ;

join_target: join_type JOIN table_or_subquery opt_join_cond  {
      struct ast_node *asti_join_type = new_ast_option($join_type);
      struct ast_node *table_join = new_ast_table_join($table_or_subquery, $opt_join_cond);
      $$ = new_ast_join_target(asti_join_type, table_join); }
  ;

opt_join_cond:
  /* nil */  { $$ = NULL; }
  | join_cond
  ;

join_cond:
  ON expr  { $$ = new_ast_join_cond(new_ast_on(), $expr); }
  | USING '(' name_list ')'  { $$ = new_ast_join_cond(new_ast_using(), $name_list); }
  ;

table_function:
  name '(' arg_list ')'  { $$ = new_ast_table_function($name, $arg_list); }
  ;

create_view_stmt:
  CREATE opt_temp VIEW opt_if_not_exists sql_name AS select_stmt opt_delete_version_attr  {
    ast_node *flags = new_ast_option($opt_temp | $opt_if_not_exists);
    ast_node *view_details = new_ast_view_details($sql_name, NULL);
    ast_node *view_details_select = new_ast_view_details_select(view_details, $select_stmt);
    ast_node *view_and_attrs = new_ast_view_and_attrs(view_details_select, $opt_delete_version_attr);
  $$ = new_ast_create_view_stmt(flags, view_and_attrs); }
  | CREATE opt_temp VIEW opt_if_not_exists sql_name '(' name_list ')' AS select_stmt opt_delete_version_attr  {
    ast_node *flags = new_ast_option($opt_temp | $opt_if_not_exists);
    ast_node *view_details = new_ast_view_details($sql_name, $name_list);
    ast_node *view_details_select = new_ast_view_details_select(view_details, $select_stmt);
    ast_node *view_and_attrs = new_ast_view_and_attrs(view_details_select, $opt_delete_version_attr);
    $$ = new_ast_create_view_stmt(flags, view_and_attrs); }
  ;

delete_stmt:
     delete_stmt_plain { $$ = $delete_stmt_plain; }
   | delete_stmt_plain returning_suffix {
     $$ = new_ast_delete_returning_stmt($delete_stmt_plain, $returning_suffix); }
   | with_prefix delete_stmt_plain {
     $$ = new_ast_with_delete_stmt($with_prefix, $delete_stmt_plain); }
   | with_prefix delete_stmt_plain returning_suffix {
     ast_node *tmp = new_ast_with_delete_stmt($with_prefix, $delete_stmt_plain); 
     $$ = new_ast_delete_returning_stmt(tmp, $returning_suffix); }
   ;

delete_stmt_plain:
  DELETE FROM sql_name opt_where  {
   $$ = new_ast_delete_stmt($sql_name, $opt_where); }
  ;

opt_insert_dummy_spec:
  /* nil */  { $$ = NULL; }
  | AT_DUMMY_SEED '(' expr ')' dummy_modifier  {
    $$ = new_ast_insert_dummy_spec($expr, new_ast_option($dummy_modifier)); }
  ;

dummy_modifier:
  /* nil */  { $$ = 0; }
  | AT_DUMMY_NULLABLES  { $$ = INSERT_DUMMY_NULLABLES; }
  | AT_DUMMY_DEFAULTS  { $$ = INSERT_DUMMY_DEFAULTS; }
  | AT_DUMMY_NULLABLES AT_DUMMY_DEFAULTS  { $$ = INSERT_DUMMY_NULLABLES | INSERT_DUMMY_DEFAULTS; }
  | AT_DUMMY_DEFAULTS AT_DUMMY_NULLABLES  { $$ = INSERT_DUMMY_NULLABLES | INSERT_DUMMY_DEFAULTS; }
  ;

insert_stmt_type:
  INSERT INTO  { $$ = new_ast_insert_normal();  }
  | INSERT OR REPLACE INTO  { $$ = new_ast_insert_or_replace(); }
  | INSERT OR IGNORE INTO  { $$ = new_ast_insert_or_ignore(); }
  | INSERT OR ROLLBACK INTO  { $$ = new_ast_insert_or_rollback(); }
  | INSERT OR ABORT INTO  { $$ = new_ast_insert_or_abort(); }
  | INSERT OR FAIL INTO  { $$ = new_ast_insert_or_fail(); }
  | REPLACE INTO  { $$ = new_ast_insert_replace(); }
  ;

opt_column_spec:
  /* nil */  { $$ = NULL; }
  | '(' opt_sql_name_list ')'  { $$ = new_ast_column_spec($opt_sql_name_list); }
  | '(' shape_def ')'  { $$ = new_ast_column_spec($shape_def); }
  ;

column_spec:
  '(' sql_name_list ')'  { $$ = new_ast_column_spec($sql_name_list); }
  | '(' shape_def ')'  { $$ = new_ast_column_spec($shape_def); }
  ;

from_shape:
  FROM CURSOR name opt_column_spec  { $$ = new_ast_from_shape($opt_column_spec, $name); }
  | FROM name opt_column_spec  { $$ = new_ast_from_shape($opt_column_spec, $name); }
  | FROM ARGUMENTS opt_column_spec  { $$ = new_ast_from_shape($opt_column_spec, new_ast_str("ARGUMENTS")); }
  ;

insert_stmt_plain:
  insert_stmt_type sql_name opt_column_spec select_stmt opt_insert_dummy_spec  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $select_stmt);
    struct ast_node *name_columns_values = new_ast_name_columns_values($sql_name, columns_values);
    ast_set_left($insert_stmt_type, $opt_insert_dummy_spec);
    $$ = new_ast_insert_stmt($insert_stmt_type, name_columns_values);  }
  | insert_stmt_type sql_name opt_column_spec from_shape opt_insert_dummy_spec  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $from_shape);
    struct ast_node *name_columns_values = new_ast_name_columns_values($sql_name, columns_values);
    ast_set_left($insert_stmt_type, $opt_insert_dummy_spec);
    $$ = new_ast_insert_stmt($insert_stmt_type, name_columns_values);  }
  | insert_stmt_type sql_name DEFAULT VALUES  {
    struct ast_node *default_columns_values = new_ast_default_columns_values();
    struct ast_node *name_columns_values = new_ast_name_columns_values($sql_name, default_columns_values);
    $$ = new_ast_insert_stmt($insert_stmt_type, name_columns_values); }
  | insert_stmt_type sql_name USING select_stmt {
    struct ast_node *name_columns_values = new_ast_name_columns_values($sql_name, $select_stmt);
    ast_set_left($insert_stmt_type, NULL); // dummy spec not allowed in this form
    $$ = new_ast_insert_stmt($insert_stmt_type, name_columns_values); }
  | insert_stmt_type sql_name USING expr_names opt_insert_dummy_spec {
    struct ast_node *name_columns_values = new_ast_name_columns_values($sql_name, $expr_names);
    ast_set_left($insert_stmt_type, $opt_insert_dummy_spec);
    $$ = new_ast_insert_stmt($insert_stmt_type, name_columns_values); }
  ;

returning_suffix: RETURNING select_expr_list { $$ = $select_expr_list; }

insert_stmt:
     insert_stmt_plain { $$ = $insert_stmt_plain; }
   | insert_stmt_plain returning_suffix {
     $$ = new_ast_insert_returning_stmt($insert_stmt_plain, $returning_suffix); }
   | with_prefix insert_stmt_plain {
     $$ = new_ast_with_insert_stmt($with_prefix, $insert_stmt_plain); }
   | with_prefix insert_stmt_plain returning_suffix {
     ast_node *tmp = new_ast_with_insert_stmt($with_prefix, $insert_stmt_plain); 
     $$ = new_ast_insert_returning_stmt(tmp, $returning_suffix); }
   ;

insert_list_item:
  expr { $$ = $expr; }
  | shape_arguments  {$$ = $shape_arguments; }
  ;

insert_list:
  /* nil */  { $$ = NULL; }
  | insert_list_item { $$ = new_ast_insert_list($insert_list_item, NULL); }
  | insert_list_item ',' insert_list[il]  { $$ = new_ast_insert_list($insert_list_item, $il); }
  ;

basic_update_stmt:
  UPDATE opt_sql_name SET update_list opt_from_query_parts opt_where  {
    struct ast_node *orderby = new_ast_update_orderby(NULL, NULL);
    struct ast_node *where = new_ast_update_where($opt_where, orderby);
    struct ast_node *from = new_ast_update_from($opt_from_query_parts, where);
    struct ast_node *list = new_ast_update_set($update_list, from);
    $$ = new_ast_update_stmt($opt_sql_name, list); }
  ;

update_stmt:
     update_stmt_plain { $$ = $update_stmt_plain; }
   | update_stmt_plain returning_suffix {
     $$ = new_ast_update_returning_stmt($update_stmt_plain, $returning_suffix); }
   | with_prefix update_stmt_plain {
     $$ = new_ast_with_update_stmt($with_prefix, $update_stmt_plain); }
   | with_prefix update_stmt_plain returning_suffix {
     ast_node *tmp = new_ast_with_update_stmt($with_prefix, $update_stmt_plain); 
     $$ = new_ast_update_returning_stmt(tmp, $returning_suffix); }
   ;

update_stmt_plain:
  UPDATE sql_name SET update_list opt_from_query_parts opt_where opt_orderby opt_limit  {
    struct ast_node *limit = $opt_limit;
    struct ast_node *orderby = new_ast_update_orderby($opt_orderby, limit);
    struct ast_node *where = new_ast_update_where($opt_where, orderby);
    struct ast_node *from = new_ast_update_from($opt_from_query_parts, where);
    struct ast_node *list = new_ast_update_set($update_list, from);
    $$ = new_ast_update_stmt($sql_name, list); }
  | UPDATE sql_name SET column_spec '=' '(' insert_list ')' opt_from_query_parts opt_where opt_orderby opt_limit  {
    struct ast_node *limit = $opt_limit;
    struct ast_node *orderby = new_ast_update_orderby($opt_orderby, limit);
    struct ast_node *where = new_ast_update_where($opt_where, orderby);
    struct ast_node *from = new_ast_update_from($opt_from_query_parts, where);
    struct ast_node *columns_values = new_ast_columns_values($column_spec, $insert_list);
    struct ast_node *list = new_ast_update_set(columns_values, from);
    $$ = new_ast_update_stmt($sql_name, list); }
  ;

update_entry:
  sql_name '=' expr  { $$ = new_ast_update_entry($sql_name, $expr); }
  ;

update_list:
  update_entry  { $$ = new_ast_update_list($update_entry, NULL); }
  | update_entry ',' update_list[ul]  { $$ = new_ast_update_list($update_entry, $ul); }
  ;

upsert_stmt:
     upsert_stmt_plain { $$ = $upsert_stmt_plain; }
   | upsert_stmt_plain returning_suffix {
     $$ = new_ast_upsert_returning_stmt($upsert_stmt_plain, $returning_suffix); }
   | with_prefix upsert_stmt_plain {
     $$ = new_ast_with_upsert_stmt($with_prefix, $upsert_stmt_plain); }
   | with_prefix upsert_stmt_plain returning_suffix {
     ast_node *tmp = new_ast_with_upsert_stmt($with_prefix, $upsert_stmt_plain); 
     $$ = new_ast_upsert_returning_stmt(tmp, $returning_suffix); }

upsert_stmt_plain:
  insert_stmt_plain[insert] ON_CONFLICT conflict_target DO NOTHING  {
    struct ast_node *upsert_update = new_ast_upsert_update($conflict_target, NULL);
    $$ = new_ast_upsert_stmt($insert, upsert_update); }
  | insert_stmt_plain[insert] ON_CONFLICT conflict_target DO basic_update_stmt  {
    struct ast_node *upsert_update = new_ast_upsert_update($conflict_target, $basic_update_stmt);
    $$ = new_ast_upsert_stmt($insert, upsert_update); }
  ;

update_cursor_stmt:
  UPDATE CURSOR name opt_column_spec FROM VALUES '(' insert_list ')'  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $insert_list);
    $$ = new_ast_update_cursor_stmt($name, columns_values); }
  | UPDATE CURSOR name opt_column_spec from_shape  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $from_shape);
    $$ = new_ast_update_cursor_stmt($name, columns_values); }
  | UPDATE CURSOR name USING expr_names {
    $$ = new_ast_update_cursor_stmt($name, $expr_names); }
  ;

conflict_target:
  /* nil */  { $$ = new_ast_conflict_target(NULL, NULL); }
  | '(' indexed_columns ')' opt_where  {
    $$ = new_ast_conflict_target($indexed_columns, $opt_where);
  }
  ;

function: FUNC | FUNCTION
  ;

declare_out_call_stmt:
  DECLARE OUT call_stmt { $$ = new_ast_declare_out_call_stmt($call_stmt); }
  ;

declare_enum_stmt:
  DECLARE ENUM name data_type_numeric '(' enum_values ')' {
     ast_node *typed_name = new_ast_typed_name($name, $data_type_numeric);
     $$ = new_ast_declare_enum_stmt(typed_name, $enum_values); }
  ;

enum_values:
    enum_value { $$ = new_ast_enum_values($enum_value, NULL); }
  | enum_value ',' enum_values[next] { $$ = new_ast_enum_values($enum_value, $next); }
  ;

enum_value:
    name { $$ = new_ast_enum_value($name, NULL); }
  | name '=' expr { $$ = new_ast_enum_value($name, $expr); }
  ;

declare_const_stmt:
  DECLARE CONST GROUP name '(' const_values ')' {
    $$ = new_ast_declare_const_stmt($name, $const_values); }
  ;

declare_group_stmt:
  DECLARE GROUP name BEGIN_ simple_variable_decls END {
    $$ = new_ast_declare_group_stmt($name, $simple_variable_decls); }
  ;

simple_variable_decls:
  declare_vars_stmt[cur] ';' { $$ = new_ast_stmt_list($cur, NULL); }
  | declare_vars_stmt[cur] ';' simple_variable_decls[next] { $$ = new_ast_stmt_list($cur, $next); }
  ;

const_values:
   const_value { $$ = new_ast_const_values($const_value, NULL);  }
  | const_value ',' const_values[next] { $$ = new_ast_const_values($const_value, $next); }
  ;

const_value:  name '=' expr { $$ = new_ast_const_value($name, $expr); }
  ;

declare_select_func_stmt:
   DECLARE SELECT function name '(' params ')' data_type_with_options  {
      $$ = new_ast_declare_select_func_stmt($name, new_ast_func_params_return($params, $data_type_with_options)); }
  | DECLARE SELECT function name '(' params ')' '(' typed_names ')'  {
      $$ = new_ast_declare_select_func_stmt($name, new_ast_func_params_return($params, $typed_names)); }
  | DECLARE SELECT function name NO CHECK data_type_with_options {
      $$  = new_ast_declare_select_func_no_check_stmt($name, new_ast_func_params_return(NULL, $data_type_with_options)); }
  | DECLARE SELECT function name NO CHECK '(' typed_names ')' {
      $$ = new_ast_declare_select_func_no_check_stmt($name, new_ast_func_params_return(NULL, $typed_names)); }
  ;

declare_func_stmt:
  DECLARE function loose_name[name] '(' func_params ')' data_type_with_options  {
      $$ = new_ast_declare_func_stmt($name, new_ast_func_params_return($func_params, $data_type_with_options)); }
  | DECLARE function loose_name[name] '(' func_params ')' CREATE data_type_with_options  {
      ast_node *create_data_type = new_ast_create_data_type($data_type_with_options);
      $$ = new_ast_declare_func_stmt($name, new_ast_func_params_return($func_params, create_data_type)); }
  | DECLARE function loose_name[name] NO CHECK data_type_with_options  {
      $$ = new_ast_declare_func_no_check_stmt($name, new_ast_func_params_return(NULL, $data_type_with_options)); }
  | DECLARE function loose_name[name] NO CHECK CREATE data_type_with_options  {
      ast_node *create_data_type = new_ast_create_data_type($data_type_with_options);
      $$ = new_ast_declare_func_no_check_stmt($name, new_ast_func_params_return(NULL, create_data_type)); }
  ;

procedure: PROC | PROCEDURE
  ;

declare_proc_no_check_stmt:
  DECLARE procedure loose_name[name] NO CHECK {
    $$ = new_ast_declare_proc_no_check_stmt($name); }
  ;

declare_proc_stmt:
  DECLARE procedure loose_name[name] '(' func_params[params] ')'  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_BASIC));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, NULL)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' '(' typed_names ')'  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_STRUCT_TYPE | PROC_FLAG_USES_DML));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, $typed_names)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' USING TRANSACTION  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_USES_DML));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, NULL)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' OUT '(' typed_names ')'  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_STRUCT_TYPE | PROC_FLAG_USES_OUT));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, $typed_names)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' OUT '(' typed_names ')' USING TRANSACTION  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_STRUCT_TYPE | PROC_FLAG_USES_OUT | PROC_FLAG_USES_DML));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, $typed_names)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' OUT UNION '(' typed_names ')'  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_STRUCT_TYPE | PROC_FLAG_USES_OUT_UNION));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, $typed_names)); }
  | DECLARE procedure loose_name[name] '(' func_params[params] ')' OUT UNION '(' typed_names ')' USING TRANSACTION  {
      ast_node *proc_name_flags = new_ast_proc_name_type($name, new_ast_option(PROC_FLAG_STRUCT_TYPE | PROC_FLAG_USES_OUT_UNION | PROC_FLAG_USES_DML));
      $$ = new_ast_declare_proc_stmt(proc_name_flags, new_ast_proc_params_stmts($params, $typed_names)); }
  ;

declare_interface_stmt:
  DECLARE INTERFACE name '(' typed_names ')'  {
      $$ = new_ast_declare_interface_stmt($name, new_ast_proc_params_stmts(NULL, $typed_names)); }
  | INTERFACE name '(' typed_names ')'  {
      $$ = new_ast_declare_interface_stmt($name, new_ast_proc_params_stmts(NULL, $typed_names)); }
  ;

create_proc_stmt:
  CREATE procedure loose_name[name] '(' params ')' BEGIN_ opt_stmt_list END  {
    $$ = new_ast_create_proc_stmt($name, new_ast_proc_params_stmts($params, $opt_stmt_list)); }
  | procedure loose_name[name] '(' params ')' BEGIN_ opt_stmt_list END  {
    $$ = new_ast_create_proc_stmt($name, new_ast_proc_params_stmts($params, $opt_stmt_list)); }
  ;

inout:
  IN  { $$ = new_ast_in(); }
  | OUT  { $$ = new_ast_out(); }
  | INOUT  { $$ = new_ast_inout(); }
  ;

typed_name:
  sql_name data_type_with_options  { $$ = new_ast_typed_name($sql_name, $data_type_with_options); }
  | shape_def  { $$ = new_ast_typed_name(NULL, $shape_def); }
  | name shape_def  { $$ = new_ast_typed_name($name, $shape_def); }
  ;

typed_names:
  typed_name  { $$ = new_ast_typed_names($typed_name, NULL); }
  | typed_name ',' typed_names[tn]  { $$ = new_ast_typed_names($typed_name, $tn);}
  ;

func_param:
  param { $$ = $param; }
  | name CURSOR { $$ = new_ast_param(NULL, new_ast_param_detail($name, new_ast_type_cursor())); }
  ;

func_params:
  /* nil */  { $$ = NULL; }
  | func_param  { $$ = new_ast_params($func_param, NULL); }
  |  func_param ',' func_params[par]  { $$ = new_ast_params($func_param, $par); }
  ;

param:
  sql_name data_type_with_options  { $$ = new_ast_param(NULL, new_ast_param_detail($sql_name, $data_type_with_options)); }
  | inout sql_name data_type_with_options  { $$ = new_ast_param($inout, new_ast_param_detail($sql_name, $data_type_with_options)); }
  | shape_def  { $$ = new_ast_param(NULL, new_ast_param_detail(NULL, $shape_def)); }
  | name shape_def  { $$ = new_ast_param(NULL, new_ast_param_detail($name, $shape_def)); }
  ;

params:
  /* nil */  { $$ = NULL; }
  | param  { $$ = new_ast_params($param, NULL); }
  |  param ',' params[par]  { $$ = new_ast_params($param, $par); }
  ;

declare_value_cursor:
  DECLARE name CURSOR shape_def  { $$ = new_ast_declare_cursor_like_name($name, $shape_def); }
  | CURSOR name shape_def  { $$ = new_ast_declare_cursor_like_name($name, $shape_def); }
  | DECLARE name CURSOR LIKE select_stmt  { $$ = new_ast_declare_cursor_like_select($name, $select_stmt); }
  | CURSOR name LIKE select_stmt  { $$ = new_ast_declare_cursor_like_select($name, $select_stmt); }
  | DECLARE name CURSOR LIKE '(' typed_names ')' { $$ = new_ast_declare_cursor_like_typed_names($name, $typed_names); }
  | CURSOR name LIKE '(' typed_names ')' { $$ = new_ast_declare_cursor_like_typed_names($name, $typed_names); }
  ;

row_source: select_stmt | explain_stmt | insert_stmt | delete_stmt | update_stmt | upsert_stmt | call_stmt 
  ;

declare_forward_read_cursor_stmt:
  DECLARE name CURSOR FOR row_source  { $$ = new_ast_declare_cursor($name, $row_source); }
  | CURSOR name FOR row_source  { $$ = new_ast_declare_cursor($name, $row_source); }
  | DECLARE name[id] CURSOR FOR expr { $$ = new_ast_declare_cursor($id, $expr); }
  | CURSOR name[id] FOR expr { $$ = new_ast_declare_cursor($id, $expr); }
  ;

declare_fetched_value_cursor_stmt:
  DECLARE name CURSOR FETCH FROM call_stmt  { $$ = new_ast_declare_value_cursor($name, $call_stmt); }
  | CURSOR name FETCH FROM call_stmt  { $$ = new_ast_declare_value_cursor($name, $call_stmt); }
  ;

declare_type_stmt:
  DECLARE name TYPE data_type_with_options { $$ = new_ast_declare_named_type($name, $data_type_with_options); }
  | TYPE name data_type_with_options { $$ = new_ast_declare_named_type($name, $data_type_with_options); }
  ;

declare_vars_stmt:
  DECLARE sql_name_list data_type_with_options  { $$ = new_ast_declare_vars_type($sql_name_list, $data_type_with_options); }
  | VAR name_list data_type_with_options  { $$ = new_ast_declare_vars_type($name_list, $data_type_with_options); }
  | declare_value_cursor { $$ = $declare_value_cursor; }
  ;

call_stmt: CALL loose_name[name] '(' arg_list ')'  {
   YY_ERROR_ON_CQL_INFERRED_NOTNULL($name);
   $$ = new_ast_call_stmt($name, $arg_list); }
  ;

for_stmt: FOR expr ';' stmt_list[step] BEGIN_ opt_stmt_list END {
   $$ = new_ast_for_stmt($expr, new_ast_for_info($step, $opt_stmt_list)); }
  ;

while_stmt:
  WHILE expr BEGIN_ opt_stmt_list END  { $$ = new_ast_while_stmt($expr, $opt_stmt_list); }
  ;

switch_stmt:
  SWITCH expr switch_case switch_cases {
    ast_node *cases = new_ast_switch_case($switch_case, $switch_cases);
    ast_node *switch_body = new_ast_switch_body($expr, cases);
    $$ = new_ast_switch_stmt(new_ast_option(0), switch_body);  }
  | SWITCH expr ALL VALUES switch_case switch_cases {
    ast_node *cases = new_ast_switch_case($switch_case, $switch_cases);
    ast_node *switch_body = new_ast_switch_body($expr, cases);
    $$ = new_ast_switch_stmt(new_ast_option(1), switch_body);  }
  ;

switch_case:
  WHEN expr_list THEN stmt_list { $$ = new_ast_connector($expr_list, $stmt_list); }
  | WHEN expr_list THEN NOTHING { $$ = new_ast_connector($expr_list, NULL); }
  ;

switch_cases:
  switch_case switch_cases[next] {
    $$ = new_ast_switch_case($switch_case, $next); }
  | ELSE stmt_list END {
    ast_node *conn = new_ast_connector(NULL, $stmt_list);
    $$ = new_ast_switch_case(conn, NULL); }
  | END { $$ = NULL; }
  ;

loop_stmt:
  LOOP fetch_stmt BEGIN_ opt_stmt_list END  { $$ = new_ast_loop_stmt($fetch_stmt, $opt_stmt_list); }
  ;

leave_stmt:
  LEAVE  { $$ = new_ast_leave_stmt(); }
  ;

return_stmt:
  RETURN  { $$ = new_ast_return_stmt(); }
  ;

rollback_return_stmt:
  ROLLBACK RETURN { $$ = new_ast_rollback_return_stmt(); }
  ;

commit_return_stmt:
  COMMIT RETURN  { $$ = new_ast_commit_return_stmt(); }
  ;

throw_stmt:
  THROW  { $$ = new_ast_throw_stmt(); }
  ;

trycatch_stmt:
  BEGIN_ TRY opt_stmt_list[osl1] END TRY ';' BEGIN_ CATCH opt_stmt_list[osl2] END CATCH  { $$ = new_ast_trycatch_stmt($osl1, $osl2); }
  | TRY opt_stmt_list[osl1] CATCH opt_stmt_list[osl2] END { $$ = new_ast_trycatch_stmt($osl1, $osl2); }
  ;

continue_stmt:
  CONTINUE  { $$ = new_ast_continue_stmt(); }
  ;

fetch_stmt:
  FETCH name INTO name_list  { $$ = new_ast_fetch_stmt($name, $name_list); }
  | FETCH name  { $$ = new_ast_fetch_stmt($name, NULL); }
  ;

fetch_values_stmt:
  FETCH name opt_column_spec FROM VALUES '(' insert_list ')' opt_insert_dummy_spec  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $insert_list);
    struct ast_node *name_columns_values = new_ast_name_columns_values($name, columns_values);
    $$ = new_ast_fetch_values_stmt($opt_insert_dummy_spec, name_columns_values); }
  | FETCH name opt_column_spec from_shape opt_insert_dummy_spec  {
    struct ast_node *columns_values = new_ast_columns_values($opt_column_spec, $from_shape);
    struct ast_node *name_columns_values = new_ast_name_columns_values($name, columns_values);
    $$ = new_ast_fetch_values_stmt($opt_insert_dummy_spec, name_columns_values); }
  | FETCH name USING expr_names opt_insert_dummy_spec {
    struct ast_node *name_columns_values = new_ast_name_columns_values($name, $expr_names);
    $$ = new_ast_fetch_values_stmt($opt_insert_dummy_spec, name_columns_values); }
  ;

expr_names:
  expr_name  { $$ = new_ast_expr_names($expr_name, NULL); }
  |  expr_name ',' expr_names[sel]  { $$ = new_ast_expr_names($expr_name, $sel); }
  ;

expr_name: expr as_alias { $$ = new_ast_expr_name($expr, $as_alias); }
  ;

fetch_call_stmt:
  FETCH name opt_column_spec FROM call_stmt  {
    YY_ERROR_ON_COLUMNS($opt_column_spec);  // not really allowed, see macro for details.
    $$ = new_ast_fetch_call_stmt($name, $call_stmt); }
  ;

close_stmt:
  CLOSE name  { $$ = new_ast_close_stmt($name); }
  ;

out_stmt:
  OUT name  { $$ = new_ast_out_stmt($name); }
  ;

out_union_stmt:
  OUT UNION name  { $$ = new_ast_out_union_stmt($name); }
  ;

out_union_parent_child_stmt:
  OUT UNION call_stmt JOIN child_results { $$ = new_ast_out_union_parent_child_stmt($call_stmt, $child_results); }
  ;

child_results:
   child_result { $$ = new_ast_child_results($child_result, NULL); }
   | child_result AND child_results[next] { $$ = new_ast_child_results($child_result, $next); }
   ;

child_result:
  call_stmt USING '(' name_list ')' { $$ = new_ast_child_result($call_stmt, new_ast_named_result(NULL, $name_list)); }
  | call_stmt USING '(' name_list ')' AS name { $$ = new_ast_child_result($call_stmt, new_ast_named_result($name, $name_list)); }
  ;

if_ending: END IF | END ;

if_stmt:
  IF expr THEN opt_stmt_list opt_elseif_list opt_else if_ending {
    struct ast_node *if_alt = new_ast_if_alt($opt_elseif_list, $opt_else);
    struct ast_node *cond_action = new_ast_cond_action($expr, $opt_stmt_list);
    $$ = new_ast_if_stmt(cond_action, if_alt); }
  ;

opt_else:
  /* nil */  { $$ = NULL; }
  | ELSE opt_stmt_list  { $$ = new_ast_else($opt_stmt_list); }
  ;

elseif_item:
  ELSE_IF expr THEN opt_stmt_list  {
    struct ast_node *cond_action = new_ast_cond_action($expr, $opt_stmt_list);
    $$ = new_ast_elseif(cond_action, NULL); }
  ;

elseif_list:
  elseif_item  { $$ = $elseif_item; }
  | elseif_item elseif_list[el2]  { ast_set_right($elseif_item, $el2); $$ = $elseif_item; }
  ;

opt_elseif_list:
  /* nil */  { $$ = NULL; }
  | elseif_list  { $$ = $elseif_list; }
  ;

control_stmt:
  commit_return_stmt  { $$ = $commit_return_stmt; }
  | continue_stmt  { $$ = $continue_stmt; }
  | leave_stmt  { $$ = $leave_stmt; }
  | return_stmt  { $$ = $return_stmt; }
  | rollback_return_stmt  { $$ = $rollback_return_stmt; }
  | throw_stmt  { $$ = $throw_stmt; }

guard_stmt:
  IF expr control_stmt  { $$ = new_ast_guard_stmt($expr, $control_stmt); }
  ;

transaction_mode:
  /* nil */ { $$ = TRANS_DEFERRED; }
  | DEFERRED { $$ = TRANS_DEFERRED; }
  | IMMEDIATE { $$ = TRANS_IMMEDIATE; }
  | EXCLUSIVE { $$ = TRANS_EXCLUSIVE; }
  ;

begin_trans_stmt:
  BEGIN_ transaction_mode TRANSACTION { $$ = new_ast_begin_trans_stmt(new_ast_option($transaction_mode)); }
  | BEGIN_ transaction_mode { $$ = new_ast_begin_trans_stmt(new_ast_option($transaction_mode)); }
  ;

rollback_trans_stmt:
  ROLLBACK  {
      $$ = new_ast_rollback_trans_stmt(NULL); }
  | ROLLBACK TRANSACTION  {
      $$ = new_ast_rollback_trans_stmt(NULL); }
  | ROLLBACK TO savepoint_name  {
      $$ = new_ast_rollback_trans_stmt($savepoint_name); }
  | ROLLBACK TRANSACTION TO savepoint_name  {
      $$ = new_ast_rollback_trans_stmt($savepoint_name); }
  | ROLLBACK TO SAVEPOINT savepoint_name  {
      $$ = new_ast_rollback_trans_stmt($savepoint_name); }
  | ROLLBACK TRANSACTION TO SAVEPOINT savepoint_name  {
      $$ = new_ast_rollback_trans_stmt($savepoint_name); }
  ;

commit_trans_stmt:
  COMMIT TRANSACTION  { $$ = new_ast_commit_trans_stmt(); }
  | COMMIT { $$ = new_ast_commit_trans_stmt(); }
  ;

proc_savepoint_stmt:  procedure SAVEPOINT BEGIN_ opt_stmt_list END {
    $$ = new_ast_proc_savepoint_stmt($opt_stmt_list);
  }
  ;

savepoint_name:
  AT_PROC { $$ = new_ast_str("@PROC"); }
  | name { $$ = $name; }
  ;

savepoint_stmt:
  SAVEPOINT savepoint_name  {
    $$ = new_ast_savepoint_stmt($savepoint_name); }
  ;

release_savepoint_stmt:
  RELEASE savepoint_name  {
    $$ = new_ast_release_savepoint_stmt($savepoint_name); }
  | RELEASE SAVEPOINT savepoint_name  {
    $$ = new_ast_release_savepoint_stmt($savepoint_name); }
  ;

echo_stmt:
  AT_ECHO name ',' str_literal  { $$ = new_ast_echo_stmt($name, $str_literal); }
  | AT_ECHO name ',' AT_TEXT '(' text_args ')' { $$ = new_ast_echo_stmt($name, new_ast_macro_text($text_args)); }
  ;

alter_table_add_column_stmt:
  ALTER TABLE sql_name ADD COLUMN col_def  {
    $$ = new_ast_alter_table_add_column_stmt($sql_name, $col_def); }
  ;

create_trigger_stmt:
  CREATE opt_temp TRIGGER opt_if_not_exists trigger_def opt_delete_version_attr  {
    int flags = $opt_temp | $opt_if_not_exists;
    $$ = new_ast_create_trigger_stmt(
        new_ast_option(flags),
        new_ast_trigger_body_vers($trigger_def, $opt_delete_version_attr)); }
  ;

trigger_def:
  sql_name[n1] trigger_condition trigger_operation ON sql_name[n2] trigger_action  {
  $$ = new_ast_trigger_def(
        $n1,
        new_ast_trigger_condition(
          new_ast_option($trigger_condition),
          new_ast_trigger_op_target(
            $trigger_operation,
            new_ast_trigger_target_action(
              $n2,
              $trigger_action)))); }
  ;

trigger_condition:
  /* nil */  { $$ = TRIGGER_BEFORE; /* before is the default per https://sqlite.org/lang_createtrigger.html */ }
  | BEFORE  { $$ = TRIGGER_BEFORE; }
  | AFTER  { $$ = TRIGGER_AFTER; }
  | INSTEAD OF  { $$ = TRIGGER_INSTEAD_OF; }
 ;

trigger_operation:
  DELETE  { $$ = new_ast_trigger_operation(new_ast_option(TRIGGER_DELETE), NULL); }
  | INSERT  { $$ = new_ast_trigger_operation(new_ast_option(TRIGGER_INSERT), NULL); }
  | UPDATE opt_of  { $$ = new_ast_trigger_operation(new_ast_option(TRIGGER_UPDATE), $opt_of); }
  ;

opt_of:
  /* nil */  { $$ = NULL; }
  | OF name_list  { $$ = $name_list; }
  ;

trigger_action:
  opt_foreachrow opt_when_expr BEGIN_ trigger_stmts END  {
  $$ = new_ast_trigger_action(
        new_ast_option($opt_foreachrow),
        new_ast_trigger_when_stmts($opt_when_expr, $trigger_stmts)); }
  ;

opt_foreachrow:
  /* nil */  { $$ = 0; }
  | FOR_EACH_ROW  { $$ = TRIGGER_FOR_EACH_ROW; }
  ;

opt_when_expr:
  /* nil */  { $$ = NULL; }
  | WHEN expr  { $$ = $expr; }
  ;

trigger_stmts:
  trigger_stmt  { $$ = new_ast_stmt_list($trigger_stmt, NULL); }
  | trigger_stmt  trigger_stmts[ts]  { $$ = new_ast_stmt_list($trigger_stmt, $ts); }
  ;

trigger_stmt:
  trigger_update_stmt ';'  { $$ = $trigger_update_stmt; }
  | trigger_insert_stmt ';'  { $$ = $trigger_insert_stmt; }
  | trigger_delete_stmt ';'  { $$ = $trigger_delete_stmt; }
  | trigger_select_stmt ';'  { $$ = $trigger_select_stmt; }
  ;

trigger_select_stmt:
  select_stmt_no_with  { $$ = $select_stmt_no_with; }
  ;

trigger_insert_stmt:
  insert_stmt  { $$ = $insert_stmt; }
  ;

trigger_delete_stmt:
  delete_stmt  { $$ = $delete_stmt; }
  ;

trigger_update_stmt:
  basic_update_stmt  { $$ = $basic_update_stmt; }
  ;

enforcement_options:
  FOREIGN KEY ON UPDATE  { $$ = new_ast_option(ENFORCE_FK_ON_UPDATE); }
  | FOREIGN KEY ON DELETE  { $$ = new_ast_option(ENFORCE_FK_ON_DELETE); }
  | JOIN  { $$ = new_ast_option(ENFORCE_STRICT_JOIN); }
  | UPSERT STATEMENT  { $$ = new_ast_option(ENFORCE_UPSERT_STMT); }
  | WINDOW function  { $$ = new_ast_option(ENFORCE_WINDOW_FUNC); }
  | WITHOUT ROWID  { $$ = new_ast_option(ENFORCE_WITHOUT_ROWID); }
  | TRANSACTION { $$ = new_ast_option(ENFORCE_TRANSACTION); }
  | SELECT IF NOTHING { $$ = new_ast_option(ENFORCE_SELECT_IF_NOTHING); }
  | INSERT SELECT { $$ = new_ast_option(ENFORCE_INSERT_SELECT); }
  | TABLE FUNCTION { $$ = new_ast_option(ENFORCE_TABLE_FUNCTION); }
  | IS_TRUE { $$ = new_ast_option(ENFORCE_IS_TRUE); }
  | CAST { $$ = new_ast_option(ENFORCE_CAST); }
  | SIGN_FUNCTION { $$ = new_ast_option(ENFORCE_SIGN_FUNCTION); }
  | CURSOR_HAS_ROW { $$ = new_ast_option(ENFORCE_CURSOR_HAS_ROW); }
  | UPDATE FROM { $$ = new_ast_option(ENFORCE_UPDATE_FROM); }
  | AND OR NOT NULL_ CHECK { $$ = new_ast_option(ENFORCE_AND_OR_NOT_NULL_CHECK); }
  ;

enforce_strict_stmt:
  AT_ENFORCE_STRICT enforcement_options  { $$ = new_ast_enforce_strict_stmt($enforcement_options); }
  ;

enforce_normal_stmt:
  AT_ENFORCE_NORMAL enforcement_options  { $$ = new_ast_enforce_normal_stmt($enforcement_options); }
  ;

enforce_reset_stmt:
  AT_ENFORCE_RESET { $$ = new_ast_enforce_reset_stmt(); }
  ;

enforce_push_stmt:
  AT_ENFORCE_PUSH { $$ = new_ast_enforce_push_stmt(); }
  ;

enforce_pop_stmt:
  AT_ENFORCE_POP { $$ = new_ast_enforce_pop_stmt(); }
  ;

keep_table_name_in_aliases_stmt:
  AT_KEEP_TABLE_NAME_IN_ALIASES { $$ = new_ast_keep_table_name_in_aliases_stmt(); }

expr_macro_def:
  AT_MACRO '(' EXPR ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_expr_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, EXPR_MACRO, $expr_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }

stmt_list_macro_def:
  AT_MACRO '(' STMT_LIST ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_stmt_list_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, STMT_LIST_MACRO, $stmt_list_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }
  ;

query_parts_macro_def:
  AT_MACRO '(' QUERY_PARTS ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_query_parts_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, QUERY_PARTS_MACRO, $query_parts_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }
  ;

cte_tables_macro_def:
  AT_MACRO '(' CTE_TABLES ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_cte_tables_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, CTE_TABLES_MACRO, $cte_tables_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }
  ;

select_core_macro_def:
  AT_MACRO '(' SELECT_CORE ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_select_core_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, SELECT_CORE_MACRO, $select_core_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }
  ;

select_expr_macro_def:
  AT_MACRO '(' SELECT_EXPR ')' name '!' '(' opt_macro_formals ')' {
    CSTR bad_name = install_macro_args($opt_macro_formals);
    YY_ERROR_ON_FAILED_MACRO_ARG(bad_name);
    $$ = new_ast_select_expr_macro_def(new_ast_macro_name_formals($name, $opt_macro_formals), NULL);
    if (is_processing()) {
      EXTRACT_STRING(name, $name);
      bool_t success = set_macro_info(name, SELECT_EXPR_MACRO, $select_expr_macro_def);
      YY_ERROR_ON_FAILED_ADD_MACRO(success, name);
    } }
  ;

op_stmt: AT_OP data_type_any ':' loose_name[op] loose_name_or_type[func] AS loose_name[targ] {
    $$ = new_ast_op_stmt($data_type_any, new_ast_op_vals($op, new_ast_op_vals($func, $targ))); }
  | AT_OP CURSOR ':' loose_name[op] loose_name_or_type[func] AS loose_name[targ] {
    $$ = new_ast_op_stmt(new_ast_str("CURSOR"), new_ast_op_vals($op, new_ast_op_vals($func, $targ))); }
  | AT_OP NULL_ ':' loose_name[op] loose_name_or_type[func] AS loose_name[targ] {
    $$ = new_ast_op_stmt(new_ast_str("NULL"), new_ast_op_vals($op, new_ast_op_vals($func, $targ))); }
  ;

ifdef: AT_IFDEF name { $$ = do_ifdef($name); }
  ;

ifndef: AT_IFNDEF name { $$ = do_ifndef($name); }
  ;

elsedef: AT_ELSE { $$ = "else"; do_else(); }
  ;

endif: AT_ENDIF { $$ = "endif"; do_endif(); }
  ;

ifdef_stmt:
   ifdef opt_stmt_list[left] elsedef opt_stmt_list[right] endif {
      $$ = new_ast_ifdef_stmt($ifdef, new_ast_pre($left, $right)); }
  | ifdef opt_stmt_list[left] endif {
      $$ = new_ast_ifdef_stmt($ifdef, new_ast_pre($left, NULL)); }
  ;

ifndef_stmt:
   ifndef opt_stmt_list[left] elsedef opt_stmt_list[right] endif {
      $$ = new_ast_ifndef_stmt($ifndef, new_ast_pre($left, $right)); }
  | ifndef opt_stmt_list[left] endif {
      $$ = new_ast_ifndef_stmt($ifndef, new_ast_pre($left, NULL)); }
  ;

macro_def_stmt:
  expr_macro_def BEGIN_ expr END {
     $$ = $expr_macro_def;
     ast_set_right($macro_def_stmt, $expr);
     delete_macro_formals(); }
  | stmt_list_macro_def BEGIN_ stmt_list END {
     $$ = $stmt_list_macro_def;
     ast_set_right($macro_def_stmt, $stmt_list);
     delete_macro_formals(); }
  | query_parts_macro_def BEGIN_ query_parts END {
     $$ = $query_parts_macro_def;
     ast_set_right($macro_def_stmt, $query_parts);
     delete_macro_formals(); }
  | cte_tables_macro_def BEGIN_ cte_tables END {
     $$ = $cte_tables_macro_def;
     ast_set_right($macro_def_stmt, $cte_tables);
     delete_macro_formals(); }
  | select_core_macro_def BEGIN_ select_core_list END {
     $$ = $select_core_macro_def;
     ast_set_right($macro_def_stmt, $select_core_list);
     delete_macro_formals(); }
  | select_expr_macro_def BEGIN_ select_expr_list END {
     $$ = $select_expr_macro_def;
     ast_set_right($macro_def_stmt, $select_expr_list);
     delete_macro_formals(); }
  ;

opt_macro_args:
   /* nil */  { $$ = NULL; }
   | macro_args { $$ = $macro_args; }
   ;

macro_arg:
 expr[arg] { $$ = new_macro_arg_node($arg); }
 | BEGIN_ stmt_list[arg] END { $$ = new_ast_stmt_list_macro_arg($arg); }
 | FROM '(' query_parts[arg] ')' { $$ = new_ast_query_parts_macro_arg($arg); }
 | WITH '(' cte_tables[arg] ')' { $$ = new_ast_cte_tables_macro_arg($arg); }
 | ROWS '(' select_core_list[arg] ')' { $$ = new_ast_select_core_macro_arg($arg); }
 | SELECT '(' select_expr_list[arg] ')' { $$ = new_ast_select_expr_macro_arg($arg); }
 ;

macro_args:
   macro_arg { $$ = new_ast_macro_args($macro_arg, NULL); }
  | macro_arg ',' macro_args[next] { $$ = new_ast_macro_args($macro_arg, $next); }
  ;

opt_macro_formals:
   /* nil */  { $$ = NULL; }
   | macro_formals { $$ = $macro_formals; }
   ;

macro_formals:
   macro_formal { $$ = new_ast_macro_formals($macro_formal, NULL); }
  | macro_formal ',' macro_formals[next] { $$ = new_ast_macro_formals($macro_formal, $next); }
  ;

macro_formal: name '!' macro_type { $$ = new_ast_macro_formal($name, $macro_type); }
  ;

macro_type:
   EXPR { $$ = new_ast_str("EXPR"); }
  | STMT_LIST { $$ = new_ast_str("STMT_LIST"); }
  | QUERY_PARTS { $$ = new_ast_str("QUERY_PARTS"); }
  | CTE_TABLES { $$ = new_ast_str("CTE_TABLES"); }
  | SELECT_CORE { $$ = new_ast_str("SELECT_CORE"); }
  | SELECT_EXPR { $$ = new_ast_str("SELECT_EXPR"); }
  ;

%%

#ifndef _MSC_VER
#pragma clang diagnostic pop
#endif

void yyerror(const char *format, ...) {
  extern int yylineno;
  va_list args;
  va_start(args, format);

  CHARBUF_OPEN(err);
  bprintf(&err, "%s:%d:1: error: ", current_file, yylineno);
  vbprintf(&err, format, args);
  bputc(&err, '\n');
  cql_emit_error(err.ptr);
  CHARBUF_CLOSE(err);
  va_end(args);

  parse_error_occurred = true;
  cql_exit_code = 2;
}

static int next_id = 0;

static void print_dot(struct ast_node *node) {
  assert(node);
  int id = next_id++;

  // we used to hard code the UTF8 for u23DA but that seems to not render consistently
  // so I switched to the codepoint 2307 "earth ground" which doesn't look as nice
  // but doesn't come out as hex-in-a-box on all my machines...
  static CSTR ground_symbol = "&#x2307;";

  // skip the builtin statements
  while (options.hide_builtins && is_ast_stmt_list(node)) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, node);

    if (!misc_attrs || !find_named_attr(misc_attrs, "builtin")) {
      break;
    }
    node = node->right;
  }

  bool_t primitive = true;

  if (is_ast_num(node)) {
    cql_output("\n    %s%u [label = \"%s\" shape=plaintext]", node->type, id, ((struct num_ast_node*)node)->value);
  }
  else if (is_ast_str(node)) {
    EXTRACT_STRING(str, node);
    if (is_id(node)) {
      // unescaped name, clean to emit
      cql_output("\n    %s%u [label = \"%s\" shape=plaintext]", node->type, id, str);
    }
    else {
      // we have to do this dance to from the encoded in SQL format string literal
      // to an escaped in C-style literal.  The dot output for \n should be the characters
      // \ and n not a newline so we need "\n" to become \"\\n\", hence double encode.
      CHARBUF_OPEN(plaintext);
      CHARBUF_OPEN(encoding);
      CHARBUF_OPEN(double_encoding);
      // the at rest format is SQL format, decode that first
      cg_decode_string_literal(str, &plaintext);
      // then double encode it
      cg_encode_c_string_literal(plaintext.ptr, &encoding);
      cg_encode_c_string_literal(encoding.ptr, &double_encoding);
      // ready to use!
      cql_output("\n    %s%u [label = %s shape=plaintext]", node->type, id, double_encoding.ptr);
      CHARBUF_CLOSE(double_encoding);
      CHARBUF_CLOSE(encoding);
      CHARBUF_CLOSE(plaintext);
    }
  }
  else {
    cql_output("\n    %s%u [label = \"%s\" shape=plaintext]", node->type, id, node->type);
    primitive = false;
  }

  if (primitive) {
    return;
  }

  if (!ast_has_left(node) && !ast_has_right(node)) {
    return;
  }

  if (ast_has_left(node)) {
    cql_output("\n    %s%u -> %s%u;", node->type, id, node->left->type, next_id);
    print_dot(node->left);
  }
  else {
    cql_output("\n    _%u [label = \"%s\" shape=plaintext]", id, ground_symbol);
    cql_output("\n    %s%u -> _%u;", node->type, id, id);
  }

  if (ast_has_right(node)) {
    cql_output("\n %s%u -> %s%u;", node->type, id, node->right->type, next_id);
    print_dot(node->right);
  }
  else {
    cql_output("\n    _%u [label = \"%s\" shape=plaintext]", id, ground_symbol);
    cql_output("\n    %s%u -> _%u;", node->type, id, id);
  }
}

cql_data_defn( cmd_options options );

cql_data_defn( const char *global_proc_name );

cql_data_defn( rtdata *rt );

static int32_t gather_arg_params(int32_t a, int32_t argc, char **argv, uint32_t *out_count, char ***out_args);

static int32_t gather_arg_param(int32_t a, int32_t argc, char **argv, char **out_arg, const char *errmsg);

static void parse_cmd(int argc, char **argv) {

  if (argc == 1) {
    cql_usage();
    cql_cleanup_and_exit(0);
  }

  // default result type
  options.rt = "c";
  rt = find_rtdata(options.rt);
  Invariant(rt);

  current_file = "<stdin>";

  // This code is generally not something you want on but it can be useful
  // if you are trying to diagnose a complex failure in a larger build and
  // you need to see what the executions were.  It can also be helpful if
  // you are using CQL in its amalgam form. Though, in that case, the
  // fprintf probably needs to be modified.

  // #define CQL_EXEC_TRACING 1
  #ifdef CQL_EXEC_TRACING

  CHARBUF_OPEN(args);
  bprintf(&args, "cql ");
  for (int32_t i = 1; i < argc; i++) {
    bprintf(&args, "%s%s", argv[i], i == argc - 1 ? "\n" : " ");
  }
  FILE *tr = fopen("/tmp/cqltrace.log", "a+");
  fprintf(tr, "%s", args.ptr);
  fclose(tr);
  CHARBUF_CLOSE(args);

  #endif

  for (int32_t a = 1; a < argc; a++) {
    char *arg = argv[a];
    if (strcmp(arg, "--echo") == 0) {
      options.echo_input = 1;
    }
    else if (strcmp(arg, "--ast") == 0) {
      options.print_ast = 1;
    }
    else if (strcmp(arg, "--ast_no_echo") == 0) {
      options.print_ast = 1;
      options.ast_no_echo = 1;
    }
    else if (strcmp(arg, "--nolines") == 0) {
      options.nolines = 1;
    }
    else if (strcmp(arg, "--hide_builtins") == 0) {
      options.hide_builtins = 1;
    }
    else if (strcmp(arg, "--schema_exclusive") == 0) {
      options.schema_exclusive = 1;
    }
    else if (strcmp(arg, "--dot") == 0) {
      options.print_dot = 1;
    }
    else if (strcmp(arg, "--exp") == 0) {
      options.expand = 1;
    }
    else if (strcmp(arg, "--sem") == 0) {
      options.expand = 1;
      options.semantic = 1;
    }
    else if (strcmp(arg, "--compress") == 0) {
      options.compress = 1;
    }
    else if (strcmp(arg, "--run_unit_tests") == 0) {
      options.run_unit_tests = 1;
    }
    else if (strcmp(arg, "--generate_exports") == 0) {
      options.generate_exports = 1;
    }
    else if (strcmp(arg, "--cg") == 0) {
      a = gather_arg_params(a, argc, argv, &options.file_names_count, &options.file_names);
      options.codegen = 1;
      options.semantic = 1;
      options.expand = 1;
    }
    else if (strcmp(arg, "--include_paths") == 0) {
      a = gather_arg_params(a, argc, argv, &options.include_paths_count, &options.include_paths);
    }
    else if (strcmp(arg, "--defines") == 0) {
      a = gather_arg_params(a, argc, argv, &options.defines_count, &options.defines);
    }
    else if (strcmp(arg, "--include_regions") == 0) {
      a = gather_arg_params(a, argc, argv, &options.include_regions_count, &options.include_regions);
    }
    else if (strcmp(arg, "--exclude_regions") == 0) {
      a = gather_arg_params(a, argc, argv, &options.exclude_regions_count, &options.exclude_regions);
    }
    else if (strcmp(arg, "--cqlrt") == 0) {
      a = gather_arg_param(a, argc, argv, &options.cqlrt, "for the name of the runtime header");
    }
    else if (strcmp(arg, "--rt") == 0) {
      a = gather_arg_param(a, argc, argv, &options.rt, "(e.g., c, lua, json_schema)");
      rt = find_rtdata(options.rt);
      if (!rt) {
        cql_error("unknown cg runtime '%s'\n", options.rt);
        cql_cleanup_and_exit(1);
      }
    }
    else if (strcmp(arg, "--test") == 0) {
      options.test = 1;
    }
    else if (strcmp(arg, "--dev") == 0) {
      options.dev = 1;
    }
    else if (strcmp(arg, "--in") == 0) {
      a = gather_arg_param(a, argc, argv, NULL, "for the file name");
      FILE *f = fopen(argv[a], "r");
      if (!f) {
        cql_error("unable to open '%s' for read\n", argv[a]);
        cql_cleanup_and_exit(1);
      }
      yyset_in(f);
      // reset the scanner to point to the newly input file (yyset_in(f)). Otherwise the scanner
      // might continue to point to the input file from the previous run in case there are still
      // a stream to read.
      // Usually when the parser encouter a syntax error, it stops reading the input file.
      // On the next run the scanner will want to continue and finish from where it stops
      // before moving to the file of the current run.
      // Therefore it's important to always do this because we're in a new run and should ignore
      // previous run because a result were already produced for that prevous run.
      yyrestart(f);

      current_file = argv[a];
    }
    else if (strcmp(arg, "--min_schema_version") == 0) {
      a = gather_arg_param(a, argc, argv, NULL, "for the minimum schema version");
      options.min_schema_version = atoi(argv[a]);
    }
    else if (strcmp(arg, "--global_proc") == 0) {
      a = gather_arg_param(a, argc, argv, NULL,  "for the global proc name");
      global_proc_name = argv[a];
    }
    else if (strcmp(arg, "--c_include_path") == 0) {
      a = gather_arg_param(a, argc, argv, &options.c_include_path, "for the include path of a C header");
    }
    else if (strcmp(arg, "--c_include_namespace") == 0) {
      a = gather_arg_param(a, argc, argv, &options.c_include_namespace, "for the C include namespace");
    }
    else {
      cql_error("unknown arg '%s'\n", argv[a]);
      cql_cleanup_and_exit(1);
    }
  }

  if (options.codegen && options.rt && (rt->required_file_names_count != options.file_names_count && rt->required_file_names_count != -1)) {
    fprintf(stderr,
            "--rt %s requires %" PRId32 " files for --cg, but received %" PRId32 "\n",
            options.rt,
            rt->required_file_names_count,
            options.file_names_count);
    cql_cleanup_and_exit(1);
  }

  if (options.cqlrt) {
    rt->cqlrt = options.cqlrt;
  }
}

#ifndef CQL_IS_NOT_MAIN
  // Normally CQL is the main entry point.  If you are using CQL in an embedded fashion
  // then you want to invoke its main at some other time. If you define CQL_IS_NOT_MAIN
  // then cql_main is not renamed to main.  You call cql_main when you want.
  #define cql_main main
#endif

cql_noexport CSTR cql_builtin_text() {
  return
    "@@begin_include@@"
    "[[builtin]]"
    "declare func cql_partition_create () CREATE OBJECT<partitioning>!;"
    "[[builtin]]"
    "declare func cql_partition_cursor (p OBJECT<partitioning>!, key CURSOR, value CURSOR) BOOL!;"
    "[[builtin]]"
    "declare func cql_extract_partition (p OBJECT<partitioning>!, key CURSOR) CREATE OBJECT!;"

    "[[builtin]]"
    "declare func cql_string_dictionary_create() CREATE OBJECT<cql_string_dictionary>!;"
    "[[builtin]]"
    "declare func cql_string_dictionary_add(dict OBJECT<cql_string_dictionary>!, key text!, value text!) BOOL!;"
    "[[builtin]]"
    "declare func cql_string_dictionary_find(dict OBJECT<cql_string_dictionary>!, key text) text;"

    "[[builtin]]"
    "@op object<cql_string_dictionary> : call add as cql_string_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_string_dictionary> : call find as cql_string_dictionary_find;"
    "[[builtin]]"
    "@op object<cql_string_dictionary> : array set as cql_string_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_string_dictionary> : array get as cql_string_dictionary_find;"

    "[[builtin]]"
    "declare func cql_long_dictionary_create() CREATE OBJECT<cql_long_dictionary>!;"
    "[[builtin]]"
    "declare func cql_long_dictionary_add(dict OBJECT<cql_long_dictionary>!, key text!, value long!) BOOL!;"
    "[[builtin]]"
    "declare func cql_long_dictionary_find(dict OBJECT<cql_long_dictionary>!, key text) long;"

    "[[builtin]]"
    "@op object<cql_long_dictionary> : call add as cql_long_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_long_dictionary> : call find as cql_long_dictionary_find;"
    "[[builtin]]"
    "@op object<cql_long_dictionary> : array set as cql_long_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_long_dictionary> : array get as cql_long_dictionary_find;"


    "[[builtin]]"
    "declare func cql_real_dictionary_create() CREATE OBJECT<cql_real_dictionary>!;"
    "[[builtin]]"
    "declare func cql_real_dictionary_add(dict OBJECT<cql_real_dictionary>!, key text!, value real!) BOOL!;"
    "[[builtin]]"
    "declare func cql_real_dictionary_find(dict OBJECT<cql_real_dictionary>!, key text) real;"

    "[[builtin]]"
    "@op object<cql_real_dictionary> : call add as cql_real_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_real_dictionary> : call find as cql_real_dictionary_find;"
    "[[builtin]]"
    "@op object<cql_real_dictionary> : array set as cql_real_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_real_dictionary> : array get as cql_real_dictionary_find;"

    "[[builtin]]"
    "declare func cql_object_dictionary_create() CREATE OBJECT<cql_object_dictionary>!;"
    "[[builtin]]"
    "declare func cql_object_dictionary_add(dict OBJECT<cql_object_dictionary>!, key text!, value OBJECT!) BOOL!;"
    "[[builtin]]"
    "declare func cql_object_dictionary_find(dict OBJECT<cql_object_dictionary>!, key text) OBJECT;"

    "[[builtin]]"
    "@op object<cql_object_dictionary> : call add as cql_object_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_object_dictionary> : call find as cql_object_dictionary_find;"
    "[[builtin]]"
    "@op object<cql_object_dictionary> : array set as cql_object_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_object_dictionary> : array get as cql_object_dictionary_find;"

    "[[builtin]]"
    "declare func cql_blob_dictionary_create() CREATE OBJECT<cql_blob_dictionary>!;"
    "[[builtin]]"
    "declare func cql_blob_dictionary_add(dict OBJECT<cql_blob_dictionary>!, key text!, value blob!) BOOL!;"
    "[[builtin]]"
    "declare func cql_blob_dictionary_find(dict OBJECT<cql_blob_dictionary>!, key text) blob;"

    "[[builtin]]"
    "@op object<cql_blob_dictionary> : call add as cql_blob_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_blob_dictionary> : call find as cql_blob_dictionary_find;"
    "[[builtin]]"
    "@op object<cql_blob_dictionary> : array set as cql_blob_dictionary_add;"
    "[[builtin]]"
    "@op object<cql_blob_dictionary> : array get as cql_blob_dictionary_find;"

    "[[builtin]]"
    "declare func cql_cursor_format(C cursor) create text!;"
    "[[builtin]]"
    "declare func cql_cursor_hash(C cursor) long!;"
    "[[builtin]]"
    "declare func cql_cursors_equal(l cursor, r cursor) bool!;"
    "[[builtin]]"
    "declare func cql_cursor_diff_index(l cursor, r cursor) int!;"
    "[[builtin]]"
    "declare func cql_cursor_diff_col(l cursor, r cursor) create text;"
    "[[builtin]]"
    "declare func cql_cursor_diff_val(l cursor, r cursor) create text;"

    "[[builtin]]"
    "declare func cql_box_int(x int) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_int(box object<cql_box>) int;"
    "[[builtin]]"
    "declare func cql_box_real(x real) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_real(box object<cql_box>) real;"
    "[[builtin]]"
    "declare func cql_box_bool(x bool) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_bool(box object<cql_box>) bool;"
    "[[builtin]]"
    "declare func cql_box_long(x long) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_long(box object<cql_box>) long;"
    "[[builtin]]"
    "declare func cql_box_text(x text) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_text(box object<cql_box>) text;"
    "[[builtin]]"
    "declare func cql_box_blob(x blob) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_blob(box object<cql_box>) blob;"
    "[[builtin]]"
    "declare func cql_box_object(x object) create object<cql_box>!;"
    "[[builtin]]"
    "declare func cql_unbox_object(box object<cql_box>) object;"
    "[[builtin]]"
    "declare func cql_box_get_type(box object<cql_box>) int!;"

    "[[builtin]]"
    "@op bool : call box as cql_box_bool;"
    "[[builtin]]"
    "@op int : call box as cql_box_int;"
    "[[builtin]]"
    "@op long : call box as cql_box_long;"
    "[[builtin]]"
    "@op real : call box as cql_box_real;"
    "[[builtin]]"
    "@op text : call box as cql_box_text;"
    "[[builtin]]"
    "@op blob : call box as cql_box_blob;"
    "[[builtin]]"
    "@op object : call box as cql_box_object;"
    "[[builtin]]"
    "@op object<cql_box> : call to_bool as cql_unbox_bool;"
    "[[builtin]]"
    "@op object<cql_box> : call to_int as cql_unbox_int;"
    "[[builtin]]"
    "@op object<cql_box> : call to_long as cql_unbox_long;"
    "[[builtin]]"
    "@op object<cql_box> : call to_real as cql_unbox_real;"
    "[[builtin]]"
    "@op object<cql_box> : call to_text as cql_unbox_text;"
    "[[builtin]]"
    "@op object<cql_box> : call to_blob as cql_unbox_blob;"
    "[[builtin]]"
    "@op object<cql_box> : call to_object as cql_unbox_object;"
    "[[builtin]]"
    "@op object<cql_box> : call type as cql_box_get_type;"

    "[[builtin]]"
    "TYPE cql_string_list object<cql_string_list>;"
    "[[builtin]]"
    "declare func cql_string_list_create() create cql_string_list!;"
    "[[builtin]]"
    "declare func cql_string_list_set_at(list cql_string_list!, index_ int!, value_ text!) cql_string_list!;"
    "[[builtin]]"
    "declare func cql_string_list_get_at(list cql_string_list!, index_ int!) text;"
    "[[builtin]]"
    "declare func cql_string_list_count(list cql_string_list!) int!;"
    "[[builtin]]"
    "declare func cql_string_list_add(list cql_string_list!, string text!) cql_string_list!;"

    "[[builtin]]"
    "@op cql_string_list : array set as cql_string_list_set_at;"
    "[[builtin]]"
    "@op cql_string_list : array get as cql_string_list_get_at;"
    "[[builtin]]"
    "@op cql_string_list : call add as cql_string_list_add;"
    "[[builtin]]"
    "@op cql_string_list : get count as cql_string_list_count;"

    "[[builtin]]"
    "TYPE cql_blob_list object<cql_blob_list>;"
    "[[builtin]]"
    "declare func cql_blob_list_create() create cql_blob_list!;"
    "[[builtin]]"
    "declare func cql_blob_list_set_at(list cql_blob_list!, index_ int!, value_ blob!) cql_blob_list!;"
    "[[builtin]]"
    "declare func cql_blob_list_get_at(list cql_blob_list!, index_ int!) blob;"
    "[[builtin]]"
    "declare func cql_blob_list_count(list cql_blob_list!) int!;"
    "[[builtin]]"
    "declare func cql_blob_list_add(list cql_blob_list!, value blob!) cql_blob_list!;"

    "[[builtin]]"
    "@op cql_blob_list : array set as cql_blob_list_set_at;"
    "[[builtin]]"
    "@op cql_blob_list : array get as cql_blob_list_get_at;"
    "[[builtin]]"
    "@op cql_blob_list : call add as cql_blob_list_add;"
    "[[builtin]]"
    "@op cql_blob_list : get count as cql_blob_list_count;"

    "[[builtin]]"
    "TYPE cql_object_list object<cql_object_list>;"
    "[[builtin]]"
    "declare func cql_object_list_create() create cql_object_list!;"
    "[[builtin]]"
    "declare func cql_object_list_set_at(list cql_object_list!, index_ int!, value_ object!) cql_object_list!;"
    "[[builtin]]"
    "declare func cql_object_list_get_at(list cql_object_list!, index_ int!) object;"
    "[[builtin]]"
    "declare func cql_object_list_count(list cql_object_list!) int!;"
    "[[builtin]]"
    "declare func cql_object_list_add(list cql_object_list!, value object!) cql_object_list!;"

    "[[builtin]]"
    "@op cql_object_list : array set as cql_object_list_set_at;"
    "[[builtin]]"
    "@op cql_object_list : array get as cql_object_list_get_at;"
    "[[builtin]]"
    "@op cql_object_list : call add as cql_object_list_add;"
    "[[builtin]]"
    "@op cql_object_list : get count as cql_object_list_count;"

    "[[builtin]]"
    "TYPE cql_long_list object<cql_long_list>;"
    "[[builtin]]"
    "declare func cql_long_list_create() create cql_long_list!;"
    "[[builtin]]"
    "declare func cql_long_list_set_at(list cql_long_list!, index_ int!, value_ long!) cql_long_list!;"
    "[[builtin]]"
    "declare func cql_long_list_get_at(list cql_long_list!, index_ int!) long!;"
    "[[builtin]]"
    "declare func cql_long_list_count(list cql_long_list!) int!;"
    "[[builtin]]"
    "declare func cql_long_list_add(list cql_long_list!, value_ long!) cql_long_list!;"

    "[[builtin]]"
    "@op cql_long_list : array set as cql_long_list_set_at;"
    "[[builtin]]"
    "@op cql_long_list : array get as cql_long_list_get_at;"
    "[[builtin]]"
    "@op cql_long_list : call add as cql_long_list_add;"
    "[[builtin]]"
    "@op cql_long_list : get count as cql_long_list_count;"


     "[[builtin]]"
    "TYPE cql_real_list object<cql_real_list>;"
    "[[builtin]]"
    "declare func cql_real_list_create() create cql_real_list!;"
    "[[builtin]]"
    "declare func cql_real_list_set_at(list cql_real_list!, index_ int!, value_ real!) cql_real_list!;"
    "[[builtin]]"
    "declare func cql_real_list_get_at(list cql_real_list!, index_ int!) real!;"
    "[[builtin]]"
    "declare func cql_real_list_count(list cql_real_list!) int!;"
    "[[builtin]]"
    "declare func cql_real_list_add(list cql_real_list!, value_ real!) cql_real_list!;"

    "[[builtin]]"
    "@op cql_real_list : array set as cql_real_list_set_at;"
    "[[builtin]]"
    "@op cql_real_list : array get as cql_real_list_get_at;"
    "[[builtin]]"
    "@op cql_real_list : call add as cql_real_list_add;"
    "[[builtin]]"
    "@op cql_real_list : get count as cql_real_list_count;"

    "[[builtin]]"
    "declare func cql_cursor_column_count(C cursor) int!;"
    "[[builtin]]"
    "declare func cql_cursor_column_type(C cursor, icol int!) int!;"
    "[[builtin]]"
    "declare func cql_cursor_column_name(C cursor, icol int!) create text;"
    "[[builtin]]"
    "declare func cql_cursor_get_bool(C cursor, icol int!) bool;"
    "[[builtin]]"
    "declare func cql_cursor_get_int(C cursor, icol int!) int;"
    "[[builtin]]"
    "declare func cql_cursor_get_long(C cursor, icol int!) long;"
    "[[builtin]]"
    "declare func cql_cursor_get_real(C cursor, icol int!) real;"
    "[[builtin]]"
    "declare func cql_cursor_get_text(C cursor, icol int!) text;"
    "[[builtin]]"
    "declare func cql_cursor_get_blob(C cursor, icol int!) blob;"
    "[[builtin]]"
    "declare func cql_cursor_get_object(C cursor, icol int!) object;"
    "[[builtin]]"
    "declare func cql_cursor_format_column(C cursor, icol int!) create text!;"
    "[[builtin]]"
    "@op cursor : call format as cql_cursor_format;"
    "[[builtin]]"
    "@op cursor : call hash as cql_cursor_hash;"
    "[[builtin]]"
    "@op cursor : call diff_index as cql_cursor_diff_index;"
    "[[builtin]]"
    "@op cursor : call diff_col as cql_cursor_diff_col;"
    "[[builtin]]"
    "@op cursor : call diff_val as cql_cursor_diff_val;"
    "[[builtin]]"
    "@op cursor : call equals as cql_cursors_equal;"
    "[[builtin]]"
    "@op cursor : call count as cql_cursor_column_count;"
    "[[builtin]]"
    "@op cursor : call type as cql_cursor_column_type;"
    "[[builtin]]"
    "@op cursor : call name as cql_cursor_column_name;"
    "[[builtin]]"
    "@op cursor : call get_bool as cql_cursor_get_bool;"
    "[[builtin]]"
    "@op cursor : call get_int as cql_cursor_get_int;"
    "[[builtin]]"
    "@op cursor : call get_long as cql_cursor_get_long;"
    "[[builtin]]"
    "@op cursor : call get_real as cql_cursor_get_real;"
    "[[builtin]]"
    "@op cursor : call get_text as cql_cursor_get_text;"
    "[[builtin]]"
    "@op cursor : call get_blob as cql_cursor_get_blob;"
    "[[builtin]]"
    "@op cursor : call get_object as cql_cursor_get_object;"
    "[[builtin]]"
    "@op cursor : call format_col as cql_cursor_format_column;"

    "[[builtin]]"
    "declare proc cql_throw(code int!) using transaction;"

    "[[builtin]]"
    "type @ID('bool') bool;"
    "[[builtin]]"
    "type @ID('int') int;"
    "[[builtin]]"
    "type @ID('integer') int;"
    "[[builtin]]"
    "type @ID('long') long;"
    "[[builtin]]"
    "type @ID('real') real;"
    "[[builtin]]"
    "type @ID('text') text;"
    "[[builtin]]"
    "type @ID('object') object;"
    "[[builtin]]"
    "type @ID('blob') blob;"
    "[[builtin]]"
    "type @ID('long_int') long;"

    "[[builtin]]"
    "declare const group cql_data_types("
    "  CQL_DATA_TYPE_NULL      = 0,"
    "  CQL_DATA_TYPE_INT32     = 1,"
    "  CQL_DATA_TYPE_INT64     = 2,"
    "  CQL_DATA_TYPE_DOUBLE    = 3,"
    "  CQL_DATA_TYPE_BOOL      = 4,"
    "  CQL_DATA_TYPE_STRING    = 5,"
    "  CQL_DATA_TYPE_BLOB      = 6,"
    "  CQL_DATA_TYPE_OBJECT    = 7,"
    "  CQL_DATA_TYPE_CORE      = 0x3f,"
    "  CQL_DATA_TYPE_ENCODED   = 0x40,"
    "  CQL_DATA_TYPE_NOT_NULL  = 0x80"
    ");"

    "[[builtin]]"
    "declare proc cql_cursor_to_blob(C cursor, out result blob!) using transaction;"
    "[[builtin]]"
    "@op cursor: call to_blob as cql_cursor_to_blob;"

    "[[builtin]]"
    "declare proc cql_cursor_from_blob(C cursor, b blob) using transaction;"
    "[[builtin]]"
    "@op cursor: call from_blob as cql_cursor_from_blob;"

    "[[builtin]]"
    "declare function cql_blob_from_int(prefix text, val int!) create blob!;"

    "[[builtin]]"
    "declare function cql_format_bool(val bool @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_int(val int @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_long(val long @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_double(val real @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_string(val text @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_blob(val blob @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_object(val object @sensitive) create text!;"
    "[[builtin]]"
    "declare function cql_format_null(ignored bool @sensitive) create text!;"

    "[[builtin]]"
    "@op bool : call fmt as cql_format_bool;"
    "[[builtin]]"
    "@op int : call fmt as cql_format_int;"
    "[[builtin]]"
    "@op long : call fmt as cql_format_long;"
    "[[builtin]]"
    "@op real : call fmt as cql_format_double;"
    "[[builtin]]"
    "@op text : call fmt as cql_format_string;"
    "[[builtin]]"
    "@op blob : call fmt as cql_format_blob;"
    "[[builtin]]"
    "@op object : call fmt as cql_format_object;"
    "[[builtin]]"
    "@op null : call fmt as cql_format_null;"

    "[[builtin]]"
    "declare function cql_make_blob_stream(list cql_blob_list!) create blob!;"
    "[[builtin]]"
    "declare proc cql_cursor_from_blob_stream(C cursor, b blob, i int!) using transaction;"
    "[[builtin]]"
    "declare function cql_blob_stream_count(b blob!) int!;"

    "@@end_include@@"
    ;
}

int cql_main(int argc, char **argv) {
  cql_exit_code = 0;
  yylineno = 1;
  parse_error_occurred = false;
  cql_ifdef_state = NULL;

  if (!setjmp(cql_for_exit)) {
    parse_cmd(argc, argv);
    ast_init();

    // add the builtin declares before we process the real input
    cql_setup_defines();
    cql_reset_open_includes();
    cql_setup_for_builtins();

    if (options.run_unit_tests) {
      run_unit_tests();
    }
    else {
      if (yyparse() || parse_error_occurred) {
        cql_exit_on_parse_errors();
      }
    }
  }

  cg_c_cleanup();
  sem_cleanup();
  ast_cleanup();
  gen_cleanup();
  rt_cleanup();
  parse_cleanup();
  cql_cleanup_open_includes();
  cql_cleanup_defines();

#ifdef CQL_AMALGAM
  // the variables need to be set back to zero so we can
  // be called again as though we were just loaded
  cql_reset_globals();
#endif

  return cql_exit_code;
}

#undef cql_main

// Use the longjmp buffer with the indicated code, see the comments above
// for why this has to be this way.  Note we do this in one line so that
// we don't get bogus code coverage errors for not covering the trialing brace
_Noreturn void cql_cleanup_and_exit(int32_t code)
{ release_open_charbufs(); cql_exit_code = code;  longjmp(cql_for_exit, 1); }

static void cql_exit_on_parse_errors() {
  cql_error("Parse errors found, no further passes will run.\n");
  cql_cleanup_and_exit(2);
}

static void parse_cleanup() {
  parse_error_occurred = false;
}

static int32_t gather_arg_params(int32_t a, int32_t argc, char **argv, uint32_t *out_count, char ***out_args) {
  if (a + 1 < argc) {
    a++;
    *out_args = &argv[a];
    *out_count = 1;
    while ((a + 1 < argc) && (strncmp("--", argv[a + 1], 2) != 0)) {
      a++;
      (*out_count)++;
    }
  }
  else {
    cql_error("%s requires additional arguments.\n", argv[a]);
    cql_cleanup_and_exit(1);
  }

  return a;
}

static int32_t gather_arg_param(int32_t a, int32_t argc, char **argv, char **out_arg, const char *errmsg) {
  if (a + 1 < argc) {
    a++;
    if (out_arg) {
      *out_arg = argv[a];
    }
  }
  else {
    cql_error("%s requires an additional param%s%s.\n", argv[a], errmsg ? " " : "", errmsg);
    cql_cleanup_and_exit(1);
  }

  return a;
}

extern int yylineno;

void line_directive(const char *directive) {
  char *directive_start = strchr(directive, '#');
  Invariant(directive_start != NULL);
  char *line_start = strchr(directive_start + 1, ' ');
  Invariant(line_start != NULL);
  int line = atoi(line_start + 1);
  yyset_lineno(line -1);  // we are about to process the linefeed

  char *q1 = strchr(directive_start +1, '"');
  if (!q1) return;
  char *q2 = strchr(q1+1, '"');
  if (!q2) return;

  CHARBUF_OPEN(temp);
  cg_decode_c_string_literal(q1, &temp);
  current_file = Strdup(temp.ptr);
  CHARBUF_CLOSE(temp);

  // we don't free the current file because it is used in the trees alongside lineno
  // free(current_file);  Don't do this.
}

// Make a string literal node based on the current file
// the node includes a search term, the literal begins at the pattern
// that is present.  So if the current dir is /var/foo/bar/baz/YourProjectRoot
// you can start at YourProjectRoot easily.
static ast_node *file_literal(ast_node *ast) {
  CHARBUF_OPEN(filter);
  EXTRACT_STRING(str, ast);
  cg_decode_string_literal(str, &filter);

  const char *p = strstr(current_file, filter.ptr);
  if (!p) {
    p = current_file;
  }

  CHARBUF_OPEN(literal);
  cg_encode_string_literal(p, &literal);
  ast_node *ret = new_ast_str(Strdup(literal.ptr));
  CHARBUF_CLOSE(literal);

  CHARBUF_CLOSE(filter);
  return ret;
}

#ifndef cql_emit_error

// CQL "stderr" outputs are emitted with this API
// You can define it to be a method of your choice with
// "#define cql_emit_error your_method" and then your method will get
// the data instead. This will be whatever output the
// compiler would have emitted to to stderr.  This includes semantic
// errors or invalid argument combinations.  Note that CQL never
// emits error fragments with this API, you always get all the text of
// one error.  This is important if you are filtering or looking for
// particular errors in a test harness or some such.
// You must copy the memory if you intend to keep it. "data" will be freed.

// Note: you may use cql_cleanup_and_exit to force a failure from within
// this API but doing so might result in unexpected cleanup paths that have
// not been tested.

void cql_emit_error(const char *err) {
  fprintf(stderr, "%s", err);
  if (error_capture) {
    bprintf(error_capture, "%s", err);
  }
}

#endif

#ifndef cql_emit_output

// CQL "stdout" outputs are emitted (in arbitrarily small pieces) with this API
// You can define it to be a method of your choice with
// "#define cql_emit_output your_method" and then your method will get
// the data instead. This will be whatever output the
// compiler would have emitted to to stdout.  This is usually
// reformated CQL or semantic trees and such -- not the normal compiler output.
// You must copy the memory if you intend to keep it. "data" will be freed.

// Note: you may use cql_cleanup_and_exit to force a failure from within
// this API but doing so might result in unexpected cleanup paths that have
// not been tested.

void cql_emit_output(const char *msg) {
  printf("%s", msg);
}

#endif

// Perform the formatting and then call cql_emit_error (which may be replaced)
// The point of all this is so that cql can have a printf-like error API but
// if you are trying to integrate with CQL you only have to handle the much
// simpler cql_emit_error API.

void cql_error(const char *format, ...)  {
  va_list args;
  va_start(args, format);
  CHARBUF_OPEN(err);
  vbprintf(&err, format, args);
  cql_emit_error(err.ptr);
  CHARBUF_CLOSE(err);
  va_end(args);
}

// Perform the formatting and the call cql_emit_output (which may be replaced)
// The point of all this is so that cql can have a printf-like output API but
// if you are trying to integrate with CQL you only have to handle the much
// simple cql_emit_output API.

void cql_output(const char *format, ...)  {
  va_list args;
  va_start(args, format);
  CHARBUF_OPEN(err);
  vbprintf(&err, format, args);
  cql_emit_output(err.ptr);
  CHARBUF_CLOSE(err);
  va_end(args);
}

#ifndef cql_open_file_for_write

// Not a normal integration point, the normal thing to do is replace cql_write_file
// but if all you need to do is adjust the path or something like that you could replace
// this method instead.  This presumes that a FILE * is still ok for your scenario.

FILE *_Nonnull cql_open_file_for_write(const char *_Nonnull file_name) {
  FILE *file;
  if (!(file = fopen(file_name, "w"))) {
    cql_error("unable to open %s for write\n", file_name);
    cql_cleanup_and_exit(1);
  }
  return file;
}

#endif

#ifndef cql_write_file

// CQL code generation outputs are emitted in one "gulp" with this API
// You can refine it to be a method of your choice with
// "#define cql_write_file your_method" and then your method will get
// the filename and the data. This will be whatever output the
// compiler would have emitted to one of it's --cg arguments. You can
// then write it to a location of your choice.
// You must copy the memory if you intend to keep it. "data" will be freed.

// Note: you *may* use cql_cleanup_and_exit to force a failure from within
// this API.  That's a normal failure mode that is well-tested.

void cql_write_file(const char *_Nonnull file_name, const char *_Nonnull data) {
  FILE *file = cql_open_file_for_write(file_name);
  fprintf(file, "%s", data);
  fclose(file);
}

#endif

static void cql_usage() {
  cql_emit_output(
    "Usage:\n"
    "--in file\n"
    "  reads the given file for the input instead of stdin\n"
    "--sem\n"
    "  performs semantic analysis on the input file ONLY\n"
    "--ast\n"
    "  prints the internal AST to stdout\n"
    "--ast_no_echo\n"
    "  prints the internal AST to stdout with no source inline (useful to debug)\n"
    "--echo\n"
    "  echoes the input in normalized form from the AST\n"
    "--dot\n"
    "  prints the internal AST to stdout in DOT format for graph visualization\n"
    "--cg output1 output2 ...\n"
    "  codegen into the named outputs\n"
    "  any number of output files may be needed for a particular result type, two is common\n"
    "--defines\n"
    "  define symbols for use with @ifdef and @ifndef\n"
    "--include_paths\n"
    "  specify prefixes to use with the @include directive\n"
    "--nolines\n"
    "  suppress the #line directives for lines; useful if you need to debug the C code\n"
    "--global_proc name\n"
    "  any loose SQL statements not in a stored proc are gathered and put into a procedure of the given name\n"
    "--compress\n"
    "  compresses SQL text into fragements that can be assembled into queries to save space\n"
    "--test\n"
    "  some of the output types can include extra diagnostics if --test is included\n"
    "--dev\n"
    "  some codegen features only make sense during development, this enables dev mode\n"
    "  example: explain query plans\n"
    "\n"
    "Result Types (--rt *) These are the various outputs the compiler can produce.\n"
    "\n"
    "--rt c\n"
    "  this is the standard C compilation of the sql file\n"
    "  requires two output files (foo.h and foo.c)\n"
    "--rt lua\n"
    "  this is the lua compilation of the sql file\n"
    "  requires one output files (foo.lua)\n"
    "--rt json_schema\n"
    "  produces JSON output suitable for consumption by downstream codegen tools\n"
    "  requires one output file (foo.json)\n"
    "--rt schema\n"
    "  produces the canonical schema for the given input files; stored procedures etc. are removed\n"
    "  requires one output file\n"
    "--rt schema_upgrade\n"
    "  produces a CQL schema upgrade script which can then be compiled with CQL itself\n"
    "  requires one output file (foo.sql)\n"
    "--rt query_plan\n"
    "  produces a set of helper procedures that create a query plan for every DML statement in the input\n"
    "  requires one output file (foo_queryplans.sql)\n"
    "--rt stats\n"
    "  produces a simple .csv file with node count information for AST nodes per procedure in the input\n"
    "  requires one output file (foo.csv)\n"
    "\n"
    "--include_regions a b c\n"
    "  the indicated regions will be declared;\n"
    "  used with --rt schema_upgrade or --rt schema\n"
    "--exclude_regions x y z\n"
    "  the indicated regions will still be declared but the upgrade code will be suppressed\n"
    "  used with --rt schema_upgrade\n"
    "--min_schema_version n\n"
    "  the schema upgrade script will not include upgrade steps for schema older than the version specified\n"
    "  used with --rt schema_upgrade\n"
    "--schema_exclusive\n"
    "  the schema upgrade script assumes it owns all the schema in the database, it aggressively removes other things\n"
    "  used with --rt schema_upgrade\n"
    "--c_include_namespace\n"
    "  for the C codegen runtimes, headers will be referenced as #include <namespace/file.h>\n"
    "--c_include_path\n"
    "  for C codegen runtimes this will be used to create the #include directive at the start of the C\n"
    "--cqlrt foo.h\n"
    "  emits foo.h into the C output instead of cqlrt.h\n"
    "--generate_exports\n"
    "  requires another output file to --cg; it contains the procedure declarations for the input\n"
    "  used with --rt c\n"
    );
}

// the reduction for a statement is pretty complicated compared to others:
//
// * procedures, views, and tables can get a doc comment add to their misc attributes
//   * if the node is one of those, we look for a recent saved comment and make an
//     attribute node eqivalent to [[doc_comment="your comment"]]
// * once this is done, if there are attributes, we wrap the statement with the attributes
//   using new_ast_stmt_and_attr
// * otherwise we just return the statement as no wrapper is needed
static ast_node *make_statement_node(
  ast_node *misc_attrs,
  ast_node *any_stmt)
{
  if (is_ast_create_proc_stmt(any_stmt) ||
      is_ast_create_view_stmt(any_stmt) ||
      is_ast_create_table_stmt(any_stmt)) {
    // Add the most recent doc comment (if any) to any table/view/proc
    CSTR comment = table_comment_saved ? table_comment_saved : get_last_doc_comment();
    if (comment) {
       ast_node *misc_attr_key = new_ast_dot(new_ast_str("cql"), new_ast_str("doc_comment"));
       ast_node *misc_attr = new_ast_misc_attr(misc_attr_key, new_ast_cstr(comment));
       misc_attrs = new_ast_misc_attrs(misc_attr, misc_attrs);
    }
  }

  // in any case, we get one chance to use this
  table_comment_saved = NULL;

  if (misc_attrs) {
     return new_ast_stmt_and_attr(misc_attrs, any_stmt);
  }
  else {
     return any_stmt;
  }
}

// creates a column definition node with a doc comment if needed
static ast_node *make_coldef_node(
  ast_node *col_def_type_attrs,
  ast_node *misc_attrs)
{
  // This is the equivalent of:
  //
  // $$ = new_ast_col_def(col_def_type_attrs, $misc_attrs);
  //
  // (with optional comment node)

  CSTR comment = get_last_doc_comment();
  if (comment) {
     ast_node *misc_attr_key = new_ast_dot(new_ast_str("cql"), new_ast_str("doc_comment"));
     ast_node *misc_attr = new_ast_misc_attr(misc_attr_key, new_ast_cstr(comment));
     misc_attrs = new_ast_misc_attrs(misc_attr, misc_attrs);
  }

  return new_ast_col_def(col_def_type_attrs, misc_attrs);
}

// When a chain of strings appears like this "xxx" "yyy" we reduce it to a single
// string literal by concatenating all the pieces.
static ast_node *reduce_str_chain(ast_node *str_chain) {
  Contract(is_ast_str_chain(str_chain));

  // trivial case, length one chain
  if (!str_chain->right) {
    return str_chain->left;
  }

  CHARBUF_OPEN(tmp);
  CHARBUF_OPEN(result);

  for (ast_node *item = str_chain; item; item = item->right) {
    Invariant(is_ast_str_chain(item));
    Invariant(is_ast_str(item->left));

    str_ast_node *str_node = (str_ast_node *)item->left;
    cg_decode_string_literal(str_node->value, &tmp);
  }

  cg_encode_string_literal(tmp.ptr, &result);
  ast_node *lit = new_ast_str(Strdup(result.ptr));

  // this just forces the literal to be echoed as a C literal
  // so that it is prettier in the echoed output, otherwise no difference
  // all literals are stored in SQL format.
  ((str_ast_node *)lit)->str_type = STRING_TYPE_C;

  CHARBUF_CLOSE(result);
  CHARBUF_CLOSE(tmp);

  return lit;
}

// This will hold the defined symbols -- the ones that came in
// via the --defines command line.  Currently there is no @define
// so you only get what came in on the command line
static symtab *defines;

// Add the defined symbol from the command line to the symbol table
static void cql_setup_defines() {
  Contract(!defines);
  defines = symtab_new();

  cql_add_define(dup_printf("__rt__%s", options.rt));

  for (int32_t i = 0; i < options.defines_count; i++) {
    cql_add_define(options.defines[i]);
  }
}

// free the defines table if it exists
static void cql_cleanup_defines() {
  SYMTAB_CLEANUP(defines);
}

// adds the given symbol to the set of defined symbols
static void cql_add_define(CSTR name) {
  Contract(defines);
  symtab_add(defines, name, (void*)1);
}

// tests if the conditional named is defined
cql_noexport bool_t cql_is_defined(CSTR name) {
  Contract(defines);
  symtab_entry *entry = symtab_find(defines, name);
  return entry && entry->val;
}

// this creates a simple call with no arguments
static ast_node *new_simple_call_from_name(ast_node *name) {
  ast_node *call_filter_clause = new_ast_call_filter_clause(NULL, NULL);
  ast_node *call_arg_list = new_ast_call_arg_list(call_filter_clause, NULL);
  return new_ast_call(name, call_arg_list);
}

// if there is no ifdef block or if the ifdef proc indicates
// we are current processing then we are processing.
static bool_t is_processing() {
  return !cql_ifdef_state || cql_ifdef_state->processing;
}

// In case of ifndef we test the symbol we process now if
// 1. we are already processing, and
// 2. the symbol is defined.
//
// Condition 1 might be false if we are for instance already
// in an @ifdef body and the body was not selected. In that
// case neither the main body or the else body will be processed.
static ast_node *do_ifdef(ast_node *ast) {
  EXTRACT_STRING(name, ast);
  cql_ifdef_state_t *new_state = _ast_pool_new(cql_ifdef_state_t);
  new_state->prev = cql_ifdef_state;
  bool_t processing = is_processing();
  new_state->processing = processing && cql_is_defined(name);
  new_state->process_else = processing && !new_state->processing;
  ast = new_state->processing ? new_ast_is_true(ast) : new_ast_is_false(ast);
  cql_ifdef_state = new_state;
  return ast;
}

// In case of ifndef we test the symbol we process now if
// 1. we are already processing, and
// 2. the symbol is not defined.
//
// Condition 1 might be false if we are for instance already
// in an @ifdef body and the body was not selected. In that
// case neither the main body or the else body will be processed.
static ast_node *do_ifndef(ast_node *ast) {
  EXTRACT_STRING(name, ast);
  cql_ifdef_state_t *new_state = _ast_pool_new(cql_ifdef_state_t);
  new_state->prev = cql_ifdef_state;
  bool_t processing = is_processing();
  new_state->processing = processing && !cql_is_defined(name);
  new_state->process_else = processing && !new_state->processing;
  ast = new_state->processing ? new_ast_is_true(ast) : new_ast_is_false(ast);
  cql_ifdef_state = new_state;
  return ast;
}

// having encountered an else
static void do_else() {
  // an else block cannot happen unless we are in an ifdef/ifndef
  // hence there must be state.
  Contract(cql_ifdef_state);

  // follow the instruction that was computed when we hit the ifdef
  cql_ifdef_state->processing = cql_ifdef_state->process_else;
}

// pops the pending ifdef state off the stack
static void do_endif() {
  Contract(cql_ifdef_state);

  cql_ifdef_state_t *prev = cql_ifdef_state->prev;
  cql_ifdef_state = prev;
}

// creates a macro argument reference node for the indicated macro type
// this is the use of a macro in any context (could be a macro body or not)
cql_noexport ast_node *new_macro_ref_node(CSTR name, ast_node *args) {
  int32_t macro_type = resolve_macro_name(name);
  ast_node *id = new_ast_str(name);
  switch (macro_type) {
    case EXPR_MACRO:         return new_ast_expr_macro_ref(id, args);
    case STMT_LIST_MACRO:    return new_ast_stmt_list_macro_ref(id, args);
    case QUERY_PARTS_MACRO:  return new_ast_query_parts_macro_ref(id, args);
    case CTE_TABLES_MACRO:   return new_ast_cte_tables_macro_ref(id, args);
    case SELECT_CORE_MACRO:  return new_ast_select_core_macro_ref(id, args);
    case SELECT_EXPR_MACRO:  return new_ast_select_expr_macro_ref(id, args);
  }
  return new_ast_unknown_macro_ref(id, args);
}

// creates a macro argument reference node for the indicated macro type
// this is the use of an argument inside the body of a macro.  Macro arguments
// obviously can only appear inside of macros bodies.
cql_noexport ast_node *new_macro_arg_ref_node(CSTR name) {
  int32_t macro_type = resolve_macro_name(name);
  ast_node *id = new_ast_str(name);
  switch (macro_type) {
    case EXPR_MACRO:         return new_ast_expr_macro_arg_ref(id);
    case STMT_LIST_MACRO:    return new_ast_stmt_list_macro_arg_ref(id);
    case QUERY_PARTS_MACRO:  return new_ast_query_parts_macro_arg_ref(id);
    case CTE_TABLES_MACRO:   return new_ast_cte_tables_macro_arg_ref(id);
    case SELECT_CORE_MACRO:  return new_ast_select_core_macro_arg_ref(id);
    case SELECT_EXPR_MACRO:  return new_ast_select_expr_macro_arg_ref(id);
  }
  return new_ast_unknown_macro_arg_ref(id);
}

// converts from the token to the friendly name of the macro
cql_noexport CSTR macro_type_from_name(CSTR name) {
  int32_t macro_type = resolve_macro_name(name);
  switch (macro_type) {
    case EXPR_MACRO:         return "expr";
    case STMT_LIST_MACRO:    return "stmt_list";
    case QUERY_PARTS_MACRO:  return "query_parts";
    case CTE_TABLES_MACRO:   return "cte_tables";
    case SELECT_CORE_MACRO:  return "select_core";
    case SELECT_EXPR_MACRO:  return "select_expr";
  }
  return "unknown";
}

// Converts from the ast node type to the token identifier
// So ast_expr_macro_arg becomes EXPR MACRO.
cql_noexport int32_t macro_arg_type(ast_node *macro_arg) {
  if (is_ast_expr_macro_arg(macro_arg)) return EXPR_MACRO;
  if (is_ast_stmt_list_macro_arg(macro_arg)) return STMT_LIST_MACRO;
  if (is_ast_query_parts_macro_arg(macro_arg)) return QUERY_PARTS_MACRO;
  if (is_ast_cte_tables_macro_arg(macro_arg)) return CTE_TABLES_MACRO;
  if (is_ast_select_core_macro_arg(macro_arg)) return SELECT_CORE_MACRO;
  if (is_ast_select_expr_macro_arg(macro_arg)) return SELECT_EXPR_MACRO;
  return EOF;
}

// Converts from the macro string like "STMT_LIST" to the constant
// like STMT_LIST_MACRO.  These tokens are only visible in this file
// so this code has to be here.

cql_noexport int32_t macro_type_from_str(CSTR type) {
  int32_t macro_type = EOF;
  if (!strcmp("EXPR", type)) {
    macro_type = EXPR_MACRO;
  }
  else if (!strcmp("STMT_LIST", type)) {
    macro_type = STMT_LIST_MACRO;
  }
  else if (!strcmp("QUERY_PARTS", type)) {
    macro_type = QUERY_PARTS_MACRO;
  }
  else if (!strcmp("CTE_TABLES", type)) {
    macro_type = CTE_TABLES_MACRO;
  }
  else if (!strcmp("SELECT_CORE", type)) {
    macro_type = SELECT_CORE_MACRO;
  }
  else if (!strcmp("SELECT_EXPR", type)) {
    macro_type = SELECT_EXPR_MACRO;
  }
  Contract(macro_type != EOF);
  return macro_type;
}

