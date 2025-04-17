/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_CG_COMMON)

// minimal stubs to avoid link errors

cql_noexport void cg_common_cleanup() {}
void cql_exit_on_semantic_errors(ast_node *head) {}

#else

#include "cg_common.h"
#include "ast.h"
#include "sem.h"
#include "symtab.h"
#include "encoders.h"

// Storage declarations
cql_data_defn( symtab *_Nullable cg_stmts );
cql_data_defn( symtab *_Nullable cg_funcs );
cql_data_defn( symtab *_Nullable cg_exprs );
cql_data_defn( charbuf *_Nullable cg_header_output );
cql_data_defn( charbuf *_Nullable cg_main_output );
cql_data_defn( charbuf *_Nullable cg_fwd_ref_output );
cql_data_defn( charbuf *_Nullable cg_constants_output );
cql_data_defn( charbuf *_Nullable cg_declarations_output );
cql_data_defn( charbuf *_Nullable cg_scratch_vars_output );
cql_data_defn( charbuf *_Nullable cg_cleanup_output );
cql_data_defn( charbuf *_Nullable cg_pieces_output );

// Prints a symbol name, along with any configured prefix, to the specified buffer.
// Multiple CSTRs may be supplied to build the name, which will be concatenated
// together.  The configured symbol case will be applied to the full symbol name.
// The prefix will be included as specified.
//
// All input names are assumed to be in snake case already.
cql_noexport void cg_sym_name(cg_symbol_case symbol_case, charbuf *_Nonnull output, CSTR _Nonnull symbol_prefix, CSTR _Nonnull name, ...)
{
  // Print the prefix first
  bprintf(output, "%s", symbol_prefix);

  // Setup the arg list
  va_list args;
  va_start(args, name);

  CSTR name_component = name;

  // Check the case configuration
  switch (symbol_case) {
    case cg_symbol_case_snake:{
      // No need to modify it, everything in here is already snake case.
      do {
        bprintf(output, "%s", name_component);
      } while ((name_component = va_arg(args, CSTR)));
      break;
    }
    case cg_symbol_case_camel:
    case cg_symbol_case_pascal:{
      // Remove all underscores and uppercase each next character, along with the first if pascal case.
      bool should_upper = (symbol_case != cg_symbol_case_camel);
      do {
        const size_t len = strlen(name_component);
        for (size_t i = 0; i != len; ++i) {
          if (name_component[i] == '_') {
            should_upper = true;
          }
          else if (should_upper) {
            bputc(output, ToUpper(name_component[i]));
            should_upper = false;
          }
          else {
            bputc(output, name_component[i]);
          }
        }
      } while ((name_component = va_arg(args, CSTR)));
      break;
    }
  }
  va_end(args);
}

// normal charbuf allocation and open goes on the stack
// this macro is for the case where we want a durable buffer
// that will be used across multiple functions
#define ALLOC_AND_OPEN_CHARBUF_REF(x) \
  (x) = (charbuf *)calloc(1, sizeof(charbuf)); \
  bopen(x);

// and here's the cleanup for the durable buffer
#define CLEANUP_CHARBUF_REF(x) if (x) { bclose(x); free(x);  x = NULL; }

cql_noexport void cg_common_init(void)
{
  // All of these will leak, but we don't care.  The tool will shut down after running cg, so it is pointless to clean
  // up after ourselves here.
  cg_stmts = symtab_new();
  cg_funcs = symtab_new();
  cg_exprs = symtab_new();

  ALLOC_AND_OPEN_CHARBUF_REF(cg_header_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_main_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_fwd_ref_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_constants_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_declarations_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_scratch_vars_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_cleanup_output);
  ALLOC_AND_OPEN_CHARBUF_REF(cg_pieces_output);

  if (rt->cql_post_common_init) rt->cql_post_common_init();
}

// lots of AST nodes require no action -- this guy is very good at that.
cql_noexport void cg_no_op(ast_node * ast) {
}

// If there is a semantic error, we should not proceed with code generation.
// We find such an error at the root of the AST.  Note its important
// to be pristine in memory usage because the amalgam version of the compiler
// does not necessarily exit when it's done. It might be used in a long running
// process, like VSCode, and we don't want to leak memory.
cql_noexport void cql_exit_on_semantic_errors(ast_node *head) {
  if (head && is_error(head)) {
    cql_error("semantic errors present; no code gen.\n");
    cql_cleanup_and_exit(1);
  }
}

// If we are here then we've already determined that there is global code to emit.
// This is code that is outside of any procedure.  This is actually pretty common
// for instance the CQL unit test pattern relies on global code to make the tests run.
// If there is no procedure name for the global code then we have a problem.  We
// can't proceed.
cql_noexport void exit_on_no_global_proc() {
  if (!global_proc_name) {
    cql_error("There are global statements but no global proc name was specified (use --global_proc)\n");
    cql_cleanup_and_exit(1);
  }
}

// Produce a crc of a given charbuf using the CRC helpers.
cql_noexport crc_t crc_charbuf(charbuf *input) {
  crc_t crc = crc_init();
  crc = crc_update(crc, (const unsigned char *)input->ptr, input->used);
  return crc_finalize(crc);
}

// Produce a sha256 reduced to 64 bits using the SHA256 helpers
cql_noexport int64_t sha256_charbuf(charbuf *input) {
  SHA256_CTX ctx;
  sha256_init(&ctx);
  sha256_update(&ctx, (const SHA256_BYTE *)input->ptr, input->used - 1);
  SHA256_BYTE hash_bytes[64];
  sha256_final(&ctx, hash_bytes);
  int64_t *h = (int64_t *)hash_bytes;
  int64_t hash = h[0] ^ h[1] ^h[2] ^ h[3];
  return hash;
}

// See cg_find_first_line for more details on why this is what it is.
// All that's going on here is we recursively visit the tree and find the smallest
// line number that matches the given file in that branch.
static int32_t cg_find_first_line_recursive(ast_node *ast, CSTR filename) {
  int32_t line = INT32_MAX;
  int32_t lleft = INT32_MAX;
  int32_t lright = INT32_MAX;

  // file name is usually the same actual string but not always
  if (ast->filename == filename || !strcmp(filename, ast->filename)) {
   line = ast->lineno;
  }

  if (ast_has_left(ast)) {
   lleft = cg_find_first_line_recursive(ast->left, filename);
   if (lleft < line) line = lleft;
  }

  if (ast_has_right(ast)) {
   lright = cg_find_first_line_recursive(ast->right, filename);
   if (lright < line) line = lright;
  }

  return line;
}

// What's going on here is that the AST is generated on REDUCE operations.
// that means the line number at the time any AST node was generated is
// the largest line number anywhere in that AST.  But if we're looking for
// the line number for a statement we want the line number where it started.
// The way to get that is to recurse through the tree and choose the smallest
// line number anywhere in the tree.  But, we must only use line numbers
// from the same file as the one we ended on.  If (e.g.) a procedure spans files
// this will cause jumping around but that's not really avoidable.
cql_noexport int32_t cg_find_first_line(ast_node *ast) {
  return cg_find_first_line_recursive(ast, ast->filename);
}

cql_noexport void cg_emit_name(charbuf *output, CSTR name, bool_t qid) {
  if (qid) {
    cg_decode_qstr(output, name);
  }
  else {
    bprintf(output, "%s", name);
  }
}

// emit a name or a quoted name as needed
cql_noexport void cg_emit_name_ast(charbuf *output, ast_node *name_ast) {
  EXTRACT_STRING(name, name_ast);
  cg_emit_name(output, name, is_qid(name_ast));
}

cql_noexport void cg_emit_sptr_index(charbuf *output, sem_struct *sptr, uint32_t i) {
  cg_emit_name(output, sptr->names[i], !!(sptr->semtypes[i] & SEM_TYPE_QID));
}

cql_noexport void cg_common_cleanup() {
  SYMTAB_CLEANUP(cg_stmts);
  SYMTAB_CLEANUP(cg_funcs);
  SYMTAB_CLEANUP(cg_exprs);

  CLEANUP_CHARBUF_REF(cg_header_output);
  CLEANUP_CHARBUF_REF(cg_main_output);
  CLEANUP_CHARBUF_REF(cg_fwd_ref_output);
  CLEANUP_CHARBUF_REF(cg_constants_output);
  CLEANUP_CHARBUF_REF(cg_declarations_output);
  CLEANUP_CHARBUF_REF(cg_scratch_vars_output);
  CLEANUP_CHARBUF_REF(cg_cleanup_output);
  CLEANUP_CHARBUF_REF(cg_pieces_output)
}

#endif
