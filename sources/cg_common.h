/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include "ast.h"
#include "charbuf.h"
#include "cql.h"
#include "sem.h"
#include "symtab.h"
#include "crc64xz.h"
#include "sha256.h"
#include "gen_sql.h"

// When emitting code for a sql statement you might need to prepare it expecting
// to use the sql statement yourself, or you may just want to run the SQL.
// CG_PREPARE indicates a result is expected.
#define CG_PREPARE 0            // so we can be explicit about not 1
#define CG_EXEC 1
#define CG_MINIFY_ALIASES 2
#define CG_NO_MINIFY_ALIASES 0  // so we can be explicit about not 2

// currently used only in DASM but of interest to all the code generators in the future
#define CG_EMIT_ONLY_BINDING 4  // assume the statement is ready to be bound, emit only the bindings
#define CG_EMIT_ONLY_PREPARE 8  // emit only the prepare, omitting the bindings which will be done later using the above

// To understand the PUSH/POP eval macros, and generally all the expression state
// macros you have to understand the overall theory of operation of the expression
// code generation.  In a traditional evaluation you could walk the tree and assemble
// the net expression just like we do when we produce SQL in the gen_* walk.  However,
// this doesn't work for SQL->C transpilation because of nullable types and compound
// expressions.
//   * Nullable types
//     The problem here is that the nullable has an is_null and an value field
//     in order to represent the possibily null state of something like a bool.
//     There is no one expression type that can hold all of that and we can't do
//     things like multiply a struct or otherwise accumulate expression state.
//     To solve this problem we keep a stack of local variables with intermediate
//     nullable results.  The result of evaluation is then TWO strings, one of which
//     is a string to get the value of the current expression and one of which is
//     a similar string to find out if that expression is null.  When a temporary is used
//     code generation will emit the necessary code to load the temporary variable
//     and then produce "variable.is_null" and "variable.value" as the pieces.
//   * Compound expressions
//     Many expressions cannot be evaluated without control flow logic.  The simplest
//     example is logical AND with short-circuit.  Knowing that the AND, and even its
//     fragements might need logic emitted you have to take the same approach --
//     you allocate a scratch variable to hold the answer, then compute it.  The same
//     approach lets you resole CASE/WHEN, IN, and BETWEEN, among others.  All of
//     these might require temporary variables and control flow.
// With the above general approach in mind, it becomes possible to keep building up
// subexpressions as long as nothing forces you to spill to locals.  So you can do
// 1+2*3 and so forth all you like and keep getting a nice simple string.  This gives
// you the best combination of simple, readable output with correct SQL semantics.
//
// The upshot of all this is that everything in sight gets an is_null and value
// buffer to write into.  Those pieces are then used to assemble any necessary evaluation.
//
// The pri argument tells the callee the context you intend to use the result.
// For instance if the result of this expression evaluation is going to be used
// as the left size of == you would pass in EXPR_PRI_COMP.  This tells the evaluator
// if the left side has binding strength weaker then == it must add parens because
// it will be used in the context of == by its caller.

#define CG_PUSH_MAIN_INDENT(tag, indent) \
CHARBUF_OPEN(tag##_buf); \
charbuf *tag##_main_saved = cg_main_output; \
int32_t tag##_indent = indent; \
cg_main_output = &tag##_buf; \

#define CG_PUSH_MAIN_INDENT2(tag) \
CG_PUSH_MAIN_INDENT(tag, 2)

#define CG_POP_MAIN_INDENT(tag) \
cg_main_output = tag##_main_saved; \
bindent(cg_main_output, &tag##_buf, tag##_indent); \
CHARBUF_CLOSE(tag##_buf);

#define CG_TEMP_STMT_BASE_NAME(index, output) \
  if (index == 0) { bprintf(output, "_temp"); } else { bprintf(output, "_temp%d", index);  }

#define CG_TEMP_STMT_NAME(index, output) \
  { CG_TEMP_STMT_BASE_NAME(index, output); bprintf(output, "_stmt"); }

// Several code generators track the nesting level of their blocks for
// various purposes, mostly indenting and diagnostic output.
cql_data_decl( int32_t stmt_nesting_level );

// This is the first of two major outputs, this one holds the .h file output
// it will get the prototypes of all the functions we generate.
cql_data_decl( charbuf *_Nullable cg_header_output );

// This is current place where statements should be going.  It begins
// as a buffer that holds the original.c file but it is normal for this
// to get temporarily redirected into other places, such as the body of
// a stored proc.
cql_data_decl( charbuf *_Nullable cg_main_output );

// This will spill into the main buffer at the end.  String literals go here.
cql_data_decl( charbuf *_Nullable cg_constants_output );

// This will spill into the main buffer at the end.  Extern declarations go here
cql_data_decl( charbuf *_Nullable cg_fwd_ref_output );

// All local variable declarations are hoisted to the front of the resulting C.
// This prevents C lexical scoping from affecting SQL scoping rules.
cql_data_decl( charbuf *_Nullable cg_declarations_output );

// Scratch variables go into their own section and will go out adjacent to
// local variable declarations.
cql_data_decl( charbuf *_Nullable cg_scratch_vars_output );

// Any on-exit cleanup goes here. This is going to be the code to finalize
// any sql statements that were generated and also to release any strings
// we were holding on to.
cql_data_decl( charbuf *_Nullable cg_cleanup_output );

// The definitions of all of the statement pieces go into this section
cql_data_decl( charbuf *_Nullable cg_pieces_output );

// Prints a symbol name, along with any configured prefix, to the specified buffer.
// Multiple CSTRs may be supplied to build the name, which will be concatenated
// together.  The configured symbol case will be applied to the full symbol name.
// The prefix will be included as specified.
//
// All input names are assumed to be in snake case already.
cql_noexport void cg_sym_name(cg_symbol_case symbol_case, charbuf *_Nonnull output, CSTR _Nonnull symbol_prefix, CSTR _Nonnull name, ...);

// Initializes all of the common buffers and sym tables.
cql_noexport void cg_common_init(void);

// cleanup the global state
cql_noexport void cg_common_cleanup(void);

// Exit if any semantic errors
cql_noexport void cql_exit_on_semantic_errors(ast_node *_Nullable head);

// Exit if no global proc name specified
cql_noexport void exit_on_no_global_proc(void);

// For the common case of "semantic-only" nodes
cql_noexport void cg_no_op(ast_node *_Nonnull ast);

// For expanding select *
cql_noexport bool_t cg_expand_star(ast_node *_Nonnull ast, void *_Nullable context, charbuf *_Nonnull buffer);

cql_noexport int32_t cg_find_first_line(ast_node *_Nonnull ast);

typedef struct cg_blob_mappings_struct {
  CSTR _Nullable get_key_type;
  CSTR _Nullable get_val_type;  // unused
  CSTR _Nullable get_key;
  CSTR _Nullable get_val;
  CSTR _Nullable create_key;
  CSTR _Nullable create_val;
  CSTR _Nullable update_key;
  CSTR _Nullable update_val;
  bool_t key_use_offsets;
  bool_t val_use_offsets;
  bool_t use_json;
  bool_t use_jsonb;
} cg_blob_mappings_t;

// Hashing helpers

cql_noexport crc_t crc_charbuf(charbuf *_Nonnull input);
cql_noexport int64_t sha256_charbuf(charbuf *_Nonnull input);

// name foratting helpers

cql_noexport void cg_emit_name(charbuf *_Nonnull output, CSTR _Nonnull name, bool_t qid);
cql_noexport void cg_emit_name_ast(charbuf *_Nonnull output, ast_node *_Nonnull name_ast);
cql_noexport void cg_emit_sptr_index(charbuf *_Nonnull output, sem_struct *_Nonnull sptr, uint32_t i);

#define CG_CHARBUF_OPEN_SYM_WITH_PREFIX(name, symbol_prefix, ...) \
CHARBUF_OPEN(name); \
cg_sym_name(rt->symbol_case, &name, symbol_prefix, ##__VA_ARGS__, NULL)

#define CG_CHARBUF_OPEN_SYM(name, ...) \
CG_CHARBUF_OPEN_SYM_WITH_PREFIX(name, rt->symbol_prefix, ##__VA_ARGS__)

// These are pre-loaded with pointers to functions for handling the
// root statements and functions.
cql_data_decl( symtab *_Nullable cg_stmts );
cql_data_decl( symtab *_Nullable cg_funcs );
cql_data_decl( symtab *_Nullable cg_exprs );

// Used by the cte_proc_context attribute in gen_sql_callbacks
typedef struct {
  gen_sql_callbacks *_Nonnull callbacks;
  bool_t minify_aliases;
} cte_proc_call_info;
