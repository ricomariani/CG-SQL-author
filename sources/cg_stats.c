/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_STATS)

// stubs to avoid link errors
cql_noexport void cg_stats_main(struct ast_node *root) {}

#else

#include <stdint.h>
#include "cql.h"
#include "ast.h"
#include "cg_stats.h"
#include "cg_common.h"
#include "charbuf.h"
#include "symtab.h"

static CSTR cg_stats_current_proc;
static symtab *stats_table;
static charbuf *stats_output;
static symtab *stats_stoplist;

// Recursively walk the AST and accumulate stats The stats are accumulated in a
// symtab where the key is the type of the node and the value is the count of
// that type of node. The stoplist is used to avoid accumulating stats for nodes
// that are present in large numbers.
static void cg_stats_accumulate(ast_node *node) {

  CSTR type = node->type;

  if (!symtab_find(stats_stoplist, type)) {
    symtab_entry *entry = symtab_find(stats_table, type);

    if (!entry) {
      symtab_add(stats_table, type, (void *)(intptr_t)1);
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
    cg_stats_accumulate(node->left);
  }

  if (ast_has_right(node)) {
    cg_stats_accumulate(node->right);
  }
}

// Create a CSV chunk with the stats for each procedure. The CSV chunk has the
// following format: "procedure_name","node_type",count. The CSV chunk is
// appended to the stats_output charbuf.  The rows are sorted by node type.
// The stats are accumulated in a symtab where the key is the type of the node
// and the value is the count of that type of node. 
static void cg_stats_create_proc_stmt(ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_STRING(name, ast->left);

  // This is only interesting for debugging, in case of crash the name is useful
  // and can be dumped to the console.
  cg_stats_current_proc = name;

  stats_table = symtab_new();

  cg_stats_accumulate(ast);

  // we can get the size of the symtab without walking it, then we get the
  // sorted payload using the helper.  This makes a copy of the payload
  uint32_t count = stats_table->count;
  symtab_entry *stats = symtab_copy_sorted_payload(stats_table, default_symtab_comparator);

  for (uint32_t i = 0; i < count; i++) {
  // At this point we just walk the payload entries and write them out
    symtab_entry *entry = &stats[i];
    bprintf(stats_output, "\"%s\",\"%s\",%lld\n", name, entry->sym, (llint_t)entry->val);
  }

  // cleanup
  free(stats);
  symtab_delete(stats_table);

  // clear the current symbol table so that we don't accidentally use it
  // and so we detect any data that leaks from it in ASAN mode.
  stats_table = NULL;
}

// walk the main statement list looking for create proc statements, enter those
// and accumulate stats.
static void cg_stats_stmt_list(ast_node *head) {
  for (ast_node *ast = head; ast; ast = ast->right) {
    EXTRACT_STMT(stmt, ast);

    if (is_ast_create_proc_stmt(stmt)) {
      cg_stats_create_proc_stmt(stmt);
    }
  }
}

// Create a stoplist of nodes that are not interesting for stats. The stoplist
// is a symtab where the key is the type of the node and the value is NULL.
// The stoplist is used to avoid accumulating stats for nodes that are present
// in large numbers and also for nodes that always come as part of a set of
// related nodes, e.g. "select_having" is always present when "select" is.
static void cg_stoplist() {
  stats_stoplist = symtab_new();

  symtab *s = stats_stoplist;

  // These are optional containers that are always present
  // their child is the interesting node, e.g. "opt_having" might be present
  // "select_having" is always present
  symtab_add(s, "select_having", NULL);
  symtab_add(s, "select_where", NULL);
  symtab_add(s, "select_offset", NULL);
  symtab_add(s, "select_groupby", NULL);
  symtab_add(s, "select_orderby", NULL);
  symtab_add(s, "select_limit", NULL);
  symtab_add(s, "select_from_etc", NULL);
  symtab_add(s, "table_or_subquery_list", NULL);
  symtab_add(s, "groupby_list", NULL);
  symtab_add(s, "name_list", NULL);
  symtab_add(s, "arg_list", NULL);
  symtab_add(s, "call_arg_list", NULL);
  symtab_add(s, "join_target_list", NULL);
  symtab_add(s, "insert_list", NULL);
  symtab_add(s, "case_list", NULL);
  symtab_add(s, "update_list", NULL);
  symtab_add(s, "col_key_list", NULL);
  symtab_add(s, "cte_binding_list", NULL);

  // These are list holders, the list isn't interesting, the items are
  symtab_add(s, "select_core_list", NULL);
  symtab_add(s, "select_expr_list_con", NULL);
  symtab_add(s, "select_expr_list", NULL);
  symtab_add(s, "expr_list", NULL);

  // These are just wrappers
  symtab_add(s, "proc_params_stmts", NULL);
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
cql_noexport void cg_stats_main(struct ast_node *root) {
  Contract(options.file_names_count == 1);
  cql_exit_on_semantic_errors(root);
  exit_on_validating_schema();

  cg_stoplist();

  CHARBUF_OPEN(output);

  stats_output = &output;

  cg_stats_stmt_list(root);

  cql_write_file(options.file_names[0], output.ptr);

  CHARBUF_CLOSE(output);
  stats_output = NULL;

  symtab_delete(stats_stoplist);
  stats_stoplist = NULL;
}

#endif
