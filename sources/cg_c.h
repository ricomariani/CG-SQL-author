/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include "cql.h"
#include "charbuf.h"
#include "ast.h"
#include "gen_sql.h"

cql_noexport void cg_c_main(struct ast_node *_Nonnull root);
cql_noexport void cg_c_cleanup(void);

// Make a temporary buffer for the evaluation results using the canonical
// naming convention.  This might exit having burned some stack slots
// for its result variables, that's normal.
#define CG_PUSH_EVAL(expr, pri) \
CHARBUF_OPEN(expr##_is_null); \
CHARBUF_OPEN(expr##_value); \
cg_expr(expr, &expr##_is_null, &expr##_value, pri);

// Close the buffers used for the above.
// The scratch stack is not restored so that any temporaries used in
// the evaluation of expr will not be re-used prematurely.  They
// can't be used again until either the expression is finished,
// or they have been captured in a less-nested result variable.
#define CG_POP_EVAL(expr) \
CHARBUF_CLOSE(expr##_value); \
CHARBUF_CLOSE(expr##_is_null);

// Create buffers for a temporary variable.  Use cg_scratch_var to fill in the buffers
// with the text needed to refer to the variable.  cg_scratch_var picks the name
// based on stack level-and type.
#define CG_PUSH_TEMP(name, sem_type) \
CHARBUF_OPEN(name); \
CHARBUF_OPEN(name##_is_null); \
CHARBUF_OPEN(name##_value); \
cg_scratch_var(NULL, sem_type, &name, &name##_is_null, &name##_value); \
stack_level++;

// Release the buffers for the temporary, restore the stack level.
#define CG_POP_TEMP(name) \
CHARBUF_CLOSE(name##_value); \
CHARBUF_CLOSE(name##_is_null); \
CHARBUF_CLOSE(name); \
stack_level--;

// Make a scratch variable to hold the final result of an evaluation.
// It may or may not be used.  It should be the first thing you put
// so that it is on the top of your stack.  This only saves the slot.
// If you use this variable you can reclaim other temporaries that come
// from deeper in the tree since they will no longer be needed.
#define CG_RESERVE_RESULT_VAR(ast, sem_type) \
int32_t stack_level_reserved = stack_level; \
sem_t sem_type_reserved = sem_type; \
ast_node *ast_reserved = ast; \
CHARBUF_OPEN(result_var); \
CHARBUF_OPEN(result_var_is_null); \
CHARBUF_OPEN(result_var_value); \
stack_level++;

// If the result variable is going to be used, this writes its name
// and .value and .is_null into the is_null and value fields.
#define CG_USE_RESULT_VAR() \
int32_t stack_level_now = stack_level; \
stack_level = stack_level_reserved; \
cg_scratch_var(ast_reserved, sem_type_reserved, &result_var, &result_var_is_null, &result_var_value); \
stack_level = stack_level_now; \
Invariant(result_var.used > 1); \
bprintf(is_null, "%s", result_var_is_null.ptr); \
bprintf(value, "%s", result_var_value.ptr)

// Release the buffer holding the name of the variable.
// If the result variable was used, we can re-use any temporaries
// with a bigger number.  They're no longer needed since they
// are captured in this result.  We know it was used if it
// has .used > 1 (there is always a trailing null so empty is 1).
#define CG_CLEANUP_RESULT_VAR() \
if (result_var.used > 1) stack_level = stack_level_reserved + 1; \
CHARBUF_CLOSE(result_var_value); \
CHARBUF_CLOSE(result_var_is_null); \
CHARBUF_CLOSE(result_var);

// This does reserve and use in one step
#define CG_SETUP_RESULT_VAR(ast, sem_type) \
CG_RESERVE_RESULT_VAR(ast, sem_type); \
CG_USE_RESULT_VAR();

#define CG_BEGIN_ADJUST_FOR_OUTARG(var, sem_type_var) \
CHARBUF_OPEN(adjusted_target); \
/* for out parameters we need to do *name */ \
if (is_out_parameter(sem_type_var)) { \
  bprintf(&adjusted_target, "*%s", var); \
  var = adjusted_target.ptr; \
}

#define CG_END_ADJUST_FOR_OUTARG() \
CHARBUF_CLOSE(adjusted_target);

// This is the symbol table for all the tokens.
// This saves us from having a giant switch for the AST types
// and for the builtin functions.
//
// Note: semantic analysis knows about more function than code-gen does
// that's because many functions are only legal in the context of SQL
// so we have no codegen for them.  But we do need to verify correctness.
#define STMT_INIT(x) symtab_add(cg_stmts, k_ast_ ## x, (void *)cg_ ## x)
#define NO_OP_STMT_INIT(x) symtab_add(cg_stmts, k_ast_ ## x, (void *)cg_no_op)
#define FUNC_INIT(x) symtab_add(cg_funcs, # x, (void *)cg_func_ ## x)
#define EXPR_INIT(x, func, str, pri_new) \
  static cg_expr_dispatch expr_disp_ ## x = { func, str, pri_new }; \
  symtab_add(cg_exprs, k_ast_ ## x, (void *)&expr_disp_ ## x);

typedef void (*cg_expr_dispatch_func)(ast_node *_Nonnull ast,
                                      CSTR _Nonnull op,
                                      charbuf *_Nonnull is_null,
                                      charbuf *_Nonnull value,
                                      int32_t pri,
                                      int32_t pri_new);

// for dispatching expression types
typedef struct cg_expr_dispatch {
  cg_expr_dispatch_func _Nonnull func;
  CSTR _Nonnull str;
  int32_t pri_new;
} cg_expr_dispatch;

#define DDL_STMT_INIT(x) symtab_add(cg_stmts, k_ast_ ## x, (void *)cg_any_ddl_stmt)
#define STD_DML_STMT_INIT(x) symtab_add(cg_stmts, k_ast_ ## x, (void *)cg_std_dml_exec_stmt)
#define STD_PREP_STMT_INIT(x) symtab_add(cg_stmts, k_ast_ ## x, (void *)cg_std_dml_prep_stmt)

