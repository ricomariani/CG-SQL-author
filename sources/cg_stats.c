/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_STATS)

// stubs to avoid link errors
cql_noexport void cg_stats_main(CS, struct ast_node *root) {}

#else

#include <stdint.h>
#include "cql.h"
#include "ast.h"
#include "cg_stats.h"
#include "cg_common.h"
#include "charbuf.h"
#include "symtab.h"
#include "cql_state.h"

//static CSTR cg_stats_current_proc;
//static symtab *stats_table;
//static charbuf *stats_output;
//static symtab *stats_stoplist;

// Recursively walk the AST and accumulate stats The stats are accumulated in a
// symtab where the key is the type of the node and the value is the count of
// that type of node. The stoplist is used to avoid accumulating stats for nodes
// that are present in large numbers.
static void cg_stats_accumulate(CqlState* _Nonnull CS, ast_node *node) {

  CSTR type = node->type;

  if (!symtab_find(CS->stats_stoplist, type)) {
    symtab_entry *entry = symtab_find(CS->stats_table, type);

    if (!entry) {
      symtab_add(CS, CS->stats_table, type, (void *)(intptr_t)1);
    }
    else {
      // swizzle an int out of the generic storage
      intptr_t val = (intptr_t)entry->val;
      val++;
      entry->val = (void *)val;
    }
  }

  // Check the left and right nodes.
  if (ast_has_left(node)) {
    cg_stats_accumulate(CS, node->left);
  }

  if (ast_has_right(node)) {
    cg_stats_accumulate(CS, node->right);
  }
}

// Create a CSV chunk with the stats for each procedure. The CSV chunk has the
// following format: "procedure_name","node_type",count. The CSV chunk is
// appended to the stats_output charbuf.  The rows are sorted by node type.
// The stats are accumulated in a symtab where the key is the type of the node
// and the value is the count of that type of node. 
static void cg_stats_create_proc_stmt(CqlState* _Nonnull CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  // This is only interesting for debugging, in case of crash the name is useful
  // and can be dumped to the console.
  CS->cg_stats_current_proc = name;

  CS->stats_table = symtab_new();

  cg_stats_accumulate(CS, ast);

  // we can get the size of the symtab without walking it, then we get the
  // sorted payload using the helper.  This makes a copy of the payload
  uint32_t count = CS->stats_table->count;
  symtab_entry *stats = symtab_copy_sorted_payload(CS->stats_table, default_symtab_comparator);

  for (uint32_t i = 0; i < count; i++) {
  // At this point we just walk the payload entries and write them out
    symtab_entry *entry = &stats[i];
    bprintf(CS->stats_output, "\"%s\",\"%s\",%lld\n", name, entry->sym, (llint_t)entry->val);
  }

  // cleanup
  free(stats);
  symtab_delete(CS, CS->stats_table);

  // clear the current symbol table so that we don't accidentally use it
  // and so we detect any data that leaks from it in ASAN mode.
  CS->stats_table = NULL;
}

// walk the main statement list looking for create proc statements, enter those
// and accumulate stats.
static void cg_stats_stmt_list(CqlState* _Nonnull CS, ast_node *head) {
  for (ast_node *ast = head; ast; ast = ast->right) {
    EXTRACT_STMT(stmt, ast);

    if (is_ast_create_proc_stmt(stmt)) {
      cg_stats_create_proc_stmt(CS, stmt);
    }
  }
}

// Create a stoplist of nodes that are not interesting for stats. The stoplist
// is a symtab where the key is the type of the node and the value is NULL.
// The stoplist is used to avoid accumulating stats for nodes that are present
// in large numbers and also for nodes that always come as part of a set of
// related nodes, e.g. "select_having" is always present when "select" is.
static void cg_stoplist(CqlState* _Nonnull CS) {
  CS->stats_stoplist = symtab_new();

  symtab *s = CS->stats_stoplist;

  // These are optional containers that are always present
  // their child is the interesting node, e.g. "opt_having" might be present
  // "select_having" is always present
  symtab_add(CS, s, "select_having", NULL);
  symtab_add(CS, s, "select_where", NULL);
  symtab_add(CS, s, "select_offset", NULL);
  symtab_add(CS, s, "select_groupby", NULL);
  symtab_add(CS, s, "select_orderby", NULL);
  symtab_add(CS, s, "select_limit", NULL);
  symtab_add(CS, s, "select_from_etc", NULL);
  symtab_add(CS, s, "table_or_subquery_list", NULL);
  symtab_add(CS, s, "groupby_list", NULL);
  symtab_add(CS, s, "name_list", NULL);
  symtab_add(CS, s, "arg_list", NULL);
  symtab_add(CS, s, "call_arg_list", NULL);
  symtab_add(CS, s, "join_target_list", NULL);
  symtab_add(CS, s, "insert_list", NULL);
  symtab_add(CS, s, "case_list", NULL);
  symtab_add(CS, s, "update_list", NULL);
  symtab_add(CS, s, "col_key_list", NULL);
  symtab_add(CS, s, "cte_binding_list", NULL);

  // These are list holders, the list isn't interesting, the items are
  symtab_add(CS, s, "select_core_list", NULL);
  symtab_add(CS, s, "select_expr_list_con", NULL);
  symtab_add(CS, s, "select_expr_list", NULL);
  symtab_add(CS, s, "expr_list", NULL);

  // These are just wrappers
  symtab_add(CS, s, "proc_params_stmts", NULL);
}

// The main entry point for the stats code generation. This function is called
// from the main entry point of the compiler. The function first checks for
// semantic errors and then calls cg_stats_stmt_list to walk the AST and
// accumulate stats. The stats are then written to a file.
// * The file name is the first file name in the options struct.
// * The file is written in CSV format with the following columns:
//   * "procedure_name","node_type",count
// * The procedures are emitted in declaration order.
// * The nodes are sorted by node type for each procedure.
//
// Note that the global variables are reset after execution to ensure that leaks
// are reported accurately by ASAN.  Also, so that if this code runs more than
// once in a single process, we don't accidentally accumulate stats from the
// previous run.  This is possible in the alamgam case, the amlagamated code is
// linked into some harness and might run multiple times in the same process.
cql_noexport void cg_stats_main(CqlState* _Nonnull CS, struct ast_node *root) {
  Contract(CS->options.file_names_count == 1);
  cql_exit_on_semantic_errors(CS, root);
  exit_on_validating_schema(CS);

  cg_stoplist(CS);

  CHARBUF_OPEN(output);

  CS->stats_output = &output;

  cg_stats_stmt_list(CS, root);

  cql_write_file(CS, CS->options.file_names[0], output.ptr);

  CHARBUF_CLOSE(output);
  CS->stats_output = NULL;

  symtab_delete(CS, CS->stats_stoplist);
  CS->stats_stoplist = NULL;
}

#endif
