/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#undef FMT
#ifdef FMT_DEBUG
#define FMT(x) "(_o%d_)" x, __LINE__
#else
#define FMT(x) x
#endif

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_OBJC)

// stubs to avoid link errors
cql_noexport void cg_objc_main(CS, ast_node *head) {}

#else

// Perform codegen of the various nodes to "Obj-C".

#include "cg_objc.h"

#include "ast.h"
#include "cg_common.h"
#include "charbuf.h"
#include "cql.h"
#include "gen_sql.h"
#include "list.h"
#include "sem.h"
#include "symtab.h"
#include "cql_state.h"

// Whether a text column in the result set of a proc is encoded
//static bool_t is_string_column_encoded = 0;

static void cg_objc_proc_result_set_c_getter(CqlState* _Nonnull CS,
  bool_t fetch_proc,
  charbuf *buffer,
  CSTR name,
  CSTR col_name,
  CSTR sym_suffix)
{
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(
    col_getter_sym,
    CS->rt->impl_symbol_prefix,
    name,
    "_get_",
    col_name,
    sym_suffix);

  bprintf(buffer, FMT("%s(cResultSet%s)"), col_getter_sym.ptr, fetch_proc ? "" : ", row");
  CHARBUF_CLOSE(col_getter_sym);
}

static void cg_objc_proc_result_set_getter(
  CqlState* _Nonnull CS,
  bool_t fetch_proc,
  CSTR name,
  CSTR col_name,
  CSTR objc_name,
  CSTR c_result_set_ref,
  CSTR c_convert,
  uint32_t col,
  sem_t sem_type,
  charbuf *output,
  bool_t encode,
  bool_t custom_type_for_encoded_column)
{
  Contract(is_unitary(sem_type));
  sem_t core_type = core_type_of(sem_type);
  Contract(core_type != SEM_TYPE_NULL);
  Contract(CS->cg_main_output);

  bool_t nullable = is_nullable(sem_type);
  CHARBUF_OPEN(return_type);
  CSTR return_type_separator = "";

  CHARBUF_OPEN(value_convert_begin);
  CSTR value_convert_end = "";
  CSTR c_getter_suffix = "";

  CHARBUF_OPEN(value);

  if (nullable) {
    switch (core_type) {
      case SEM_TYPE_INTEGER:
      case SEM_TYPE_LONG_INTEGER:
      case SEM_TYPE_REAL:
      case SEM_TYPE_BOOL:
        bprintf(&return_type, FMT("%s"), "NSNumber *_Nullable");
        return_type_separator = " ";
         bprintf(&value_convert_begin, FMT("%s"), "@(");
        value_convert_end = ")";
        c_getter_suffix = "_value";
        cg_objc_proc_result_set_c_getter(CS, fetch_proc, &value, name, col_name, "_is_null");
        bprintf(&value, FMT(" ? nil : "));
        break;
      case SEM_TYPE_BLOB:
        bprintf(&return_type, FMT("%s_Nullable"), CS->rt->cql_blob_ref);
        return_type_separator = " ";
        bprintf(&value_convert_begin, FMT("(__bridge %s)"), CS->rt->cql_blob_ref);
        break;
      case SEM_TYPE_TEXT:
        if (encode && custom_type_for_encoded_column) {
          CS->is_string_column_encoded = 1;
          bprintf(&return_type, FMT("%s *_Nullable"), CS->rt->cql_string_ref_encode);
          bprintf(&value_convert_begin, FMT("(__bridge %s *)"), CS->rt->cql_string_ref_encode);
        } else {
          bprintf(&return_type, FMT("%s_Nullable"), CS->rt->cql_string_ref);
          bprintf(&value_convert_begin, FMT("(__bridge %s)"), CS->rt->cql_string_ref);
        }
        return_type_separator = " ";
        break;
      case SEM_TYPE_OBJECT:
        bprintf(&return_type, FMT("%s_Nullable"), CS->rt->cql_object_ref);
        return_type_separator = " ";
        bprintf(&value_convert_begin, FMT("(__bridge %s)"), CS->rt->cql_object_ref);
        break;
    }
  } else {
    switch (core_type) {
      case SEM_TYPE_INTEGER:
        return_type_separator = " ";
        bprintf(&return_type, FMT("%s"), CS->rt->cql_int32);
        break;
      case SEM_TYPE_LONG_INTEGER:
        return_type_separator = " ";
        bprintf(&return_type, FMT("%s"), CS->rt->cql_int64);
        break;
      case SEM_TYPE_REAL:
        return_type_separator = " ";
        bprintf(&return_type, FMT("%s"), CS->rt->cql_double);
        break;
      case SEM_TYPE_BOOL:
        return_type_separator = " ";
        bprintf(&return_type, FMT("%s"), CS->rt->cql_bool);
        value_convert_end = " ? YES : NO";
        break;
      case SEM_TYPE_TEXT:
        if (encode && custom_type_for_encoded_column) {
          CS->is_string_column_encoded = 1;
          bprintf(&return_type, FMT("%s"), CS->rt->cql_string_ref_encode);
          bprintf(&value_convert_begin, "(__bridge %s *)", CS->rt->cql_string_ref_encode);
        } else {
          bprintf(&return_type, FMT("%s"), CS->rt->cql_string_ref);
          bprintf(&value_convert_begin, "(__bridge %s)", CS->rt->cql_string_ref);
        }
        break;
      case SEM_TYPE_BLOB:
        bprintf(&return_type, FMT("%s"), CS->rt->cql_blob_ref);
        bprintf(&value_convert_begin, FMT("(__bridge %s)"), CS->rt->cql_blob_ref);
        break;
      case SEM_TYPE_OBJECT:
        bprintf(&return_type, FMT("%s"), CS->rt->cql_object_ref);
        return_type_separator = " ";
        bprintf(&value_convert_begin, FMT("(__bridge %s)"), CS->rt->cql_object_ref);
        break;
    }
  }

  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(
    objc_getter,
    CS->rt->symbol_prefix,
    name,
    "_get_",
    col_name);

  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(c_getter,
                                  CS->rt->impl_symbol_prefix,
                                  name,
                                  "_get_",
                                  col_name,
                                  c_getter_suffix);

  if (fetch_proc) {
    bprintf(&value, FMT("%s%s(cResultSet)%s"),
            value_convert_begin.ptr,
            c_getter.ptr,
            value_convert_end);
  }
  else {
    bprintf(&value, FMT("%s%s(cResultSet, row)%s"),
            value_convert_begin.ptr,
            c_getter.ptr,
            value_convert_end);
  }

  if (fetch_proc) {
    bprintf(output,
            FMT("\nstatic inline %s%s%s(%s *resultSet)\n"),
            return_type.ptr,
            return_type_separator,
            objc_getter.ptr,
            objc_name);
  }
  else {
    bprintf(output,
            FMT("\nstatic inline %s%s%s(%s *resultSet, %s row)\n"),
            return_type.ptr,
            return_type_separator,
            objc_getter.ptr,
            objc_name,
            CS->rt->cql_int32);
  }

  bprintf(output, FMT("{\n"));

  bprintf(output, FMT("  %s cResultSet = %s(resultSet);\n"), c_result_set_ref, c_convert);
  bprintf(output, FMT("  return %s;\n"), value.ptr);
  bprintf(output, FMT("}\n"));

  CHARBUF_CLOSE(c_getter);
  CHARBUF_CLOSE(objc_getter);
  CHARBUF_CLOSE(value);
  CHARBUF_CLOSE(value_convert_begin);
  CHARBUF_CLOSE(return_type);
}

static void cg_objc_proc_result_set(CqlState* _Nonnull CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  Contract(is_struct(ast->sem->sem_type));
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  EXTRACT_STRING(name, ast->left);
  EXTRACT_MISC_ATTRS(ast, misc_attrs);

  // if getters are suppressed the entire class is moot
  // if result set is suppressed the entire class is moot
  // private implies result set suppressed so also moot
  bool_t suppressed = is_proc_suppress_getters(CS, ast) || is_proc_suppress_result_set(CS, ast) || is_proc_private(CS, ast);

  if (suppressed) {
    return;
  }

  Invariant(!CS->sem.use_encode);
  Invariant(!CS->sem.encode_context_column);
  Invariant(!CS->sem.encode_columns);
  CS->sem.encode_columns = symtab_new();
  init_encode_info(CS, misc_attrs, &CS->sem.use_encode, &CS->sem.encode_context_column, CS->sem.encode_columns);

  bool_t custom_type_for_encoded_column = !!exists_attribute_str(CS, misc_attrs, "custom_type_for_encoded_column");
  CSTR c_result_set_name = name;
  charbuf *h = CS->cg_header_output;

  CG_CHARBUF_OPEN_SYM(objc_name, name);
  CG_CHARBUF_OPEN_SYM(objc_result_set_name, c_result_set_name);
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(c_name, CS->rt->impl_symbol_prefix, name);

  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(c_result_set, CS->rt->impl_symbol_prefix, c_result_set_name, "_result_set");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(
    c_result_set_ref, CS->rt->impl_symbol_prefix, c_result_set_name, "_result_set_ref");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(c_convert, "", c_name.ptr, "_from_", objc_name.ptr);

  CSTR classname = objc_name.ptr;

  bprintf(h, FMT("\n@class %s;\n"), classname);
  bprintf(h, FMT("\n#ifdef CQL_EMIT_OBJC_INTERFACES\n"));
  bprintf(h, FMT("@interface %s\n"), classname);
  bprintf(h, FMT("@end\n"));
  bprintf(h, FMT("#endif\n"));

  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(objc_convert, "", objc_name.ptr, "_from_", c_name.ptr);

  bprintf(h, FMT("\nstatic inline %s *%s(%s resultSet)\n"), objc_name.ptr, objc_convert.ptr, c_result_set_ref.ptr);
  bprintf(h, FMT("{\n"));
  bprintf(h, FMT("  return (__bridge %s *)resultSet;\n"), objc_name.ptr);
  bprintf(h, FMT("}\n"));

  CHARBUF_CLOSE(objc_convert);

  bprintf(
    h,
    FMT("\nstatic inline %s %s(%s *resultSet)\n"),
    c_result_set_ref.ptr,
    c_convert.ptr,
    objc_name.ptr);

  bprintf(h, FMT("{\n"));
  bprintf(h, FMT("  return (__bridge %s)resultSet;\n"), c_result_set_ref.ptr);
  bprintf(h, FMT("}\n"));

  bool_t out_stmt_proc = has_out_stmt_result(ast);
  // extension fragments use SELECT and are incompatible with the single row result set form using OUT

  sem_struct *sptr = ast->sem->sptr;
  uint32_t count = sptr->count;
  for (uint32_t i = 0; i < count; i++) {
    sem_t sem_type = sptr->semtypes[i];
    CSTR col = sptr->names[i];
    cg_objc_proc_result_set_getter(CS,
      out_stmt_proc,
      name,
      col,
      objc_name.ptr,
      c_result_set_ref.ptr,
      c_convert.ptr,
      i,
      sem_type,
      h,
      should_encode_col(col, sem_type, CS->sem.use_encode, CS->sem.encode_columns),
      custom_type_for_encoded_column);
  }

  if (CS->sem.use_encode) {
    for (uint32_t i = 0; i < count; i++) {
      CSTR col = sptr->names[i];
      sem_t sem_type = sptr->semtypes[i];
      bool_t encode = should_encode_col(col, sem_type, CS->sem.use_encode, CS->sem.encode_columns);
      if (encode) {
        CG_CHARBUF_OPEN_SYM_WITH_PREFIX(
            objc_getter, objc_name.ptr, "_get_", col, "_is_encoded");
        CG_CHARBUF_OPEN_SYM_WITH_PREFIX(
            c_getter, c_name.ptr, "_get_", col, "_is_encoded");

        bprintf(h,
            FMT("\nstatic inline %s %s(%s *resultSet)\n"),
            CS->rt->cql_bool,
            objc_getter.ptr,
            objc_result_set_name.ptr);
        bprintf(h, FMT("{\n"));
        bprintf(h, FMT("  return %s(%s(resultSet));\n"), c_getter.ptr, c_convert.ptr);
        bprintf(h, FMT("}\n"));

        CHARBUF_CLOSE(c_getter);
        CHARBUF_CLOSE(objc_getter);
      }
    }

    // Add a helper function that overrides CQL_DATA_TYPE_ENCODED bit of a resultset.
    // It's a debugging function that allow you to turn ON/OFF encoding/decoding when
    // your app is running.
    bprintf(h,
            FMT("\nstatic inline void %sSetEncoding(%s col, %s encode)\n"),
            objc_name.ptr,
            CS->rt->cql_int32,
            CS->rt->cql_bool);
    bprintf(h, FMT("{\n"));
    bprintf(h, FMT("  return %sSetEncoding(col, encode);\n"), c_name.ptr);
    bprintf(h, FMT("}\n"));
  }

  CG_CHARBUF_OPEN_SYM(cgs_result_count, name, "_result_count");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(result_count, CS->rt->impl_symbol_prefix, name, "_result_count");

  bprintf(h,
          FMT("\nstatic inline %s %s(%s *resultSet)\n"),
          CS->rt->cql_int32,
          cgs_result_count.ptr,
          objc_result_set_name.ptr);


  bprintf(h, FMT("{\n"));
  bprintf(h, FMT("  return %s(%s(resultSet));\n"), result_count.ptr, c_convert.ptr);
  bprintf(h, FMT("}\n"));

  CHARBUF_CLOSE(result_count);
  CHARBUF_CLOSE(cgs_result_count);

  CG_CHARBUF_OPEN_SYM(cgs_copy_func_name, name, "_copy");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(copy_func_name, CS->rt->impl_symbol_prefix, name, "_copy");

  bool_t generate_copy = misc_attrs && exists_attribute_str(CS, misc_attrs, "generate_copy");
  if (generate_copy) {
    bprintf(h,
            FMT("\nstatic inline %s *%s(%s *resultSet"),
            objc_result_set_name.ptr,
            cgs_copy_func_name.ptr,
            objc_result_set_name.ptr);
    if (!out_stmt_proc) {
      bprintf(h,
              FMT(", %s from, %s count"),
              CS->rt->cql_int32,
              CS->rt->cql_int32);
    }
    bprintf(h, FMT(")\n"));
    bprintf(h, FMT("{\n"));
    bprintf(h, FMT("  %s copy;\n"), c_result_set_ref.ptr);
    bprintf(h,
            FMT("  %s(%s(resultSet), &copy%s);\n"),
            copy_func_name.ptr,
            c_convert.ptr,
            out_stmt_proc ? "" : ", from, count");
    bprintf(h, FMT("  %s(copy);\n"), CS->rt->cql_result_set_note_ownership_transferred);
    bprintf(h, FMT("  return (__bridge_transfer %s *)copy;\n"), objc_name.ptr);
    bprintf(h, FMT("}\n"));
  }

  CHARBUF_CLOSE(copy_func_name);
  CHARBUF_CLOSE(cgs_copy_func_name);

  CSTR opt_row = out_stmt_proc ? "" : "_row";
  CG_CHARBUF_OPEN_SYM(cgs_hash_func_name, name, opt_row, "_hash");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(hash_func_name, CS->rt->impl_symbol_prefix, name, opt_row, "_hash");
  CG_CHARBUF_OPEN_SYM(cgs_eq_func_name, name, opt_row, "_equal");
  CG_CHARBUF_OPEN_SYM_WITH_PREFIX(eq_func_name, CS->rt->impl_symbol_prefix, name, opt_row, "_equal");

  bprintf(h,
          FMT("\nstatic inline NSUInteger %s(%s *resultSet"),
          cgs_hash_func_name.ptr,
          objc_name.ptr);
  if (!out_stmt_proc) {
    bprintf(h, FMT(", %s row"), CS->rt->cql_int32);
  }
  bprintf(h, FMT(")\n"));
  bprintf(h, FMT("{\n"));
  bprintf(h,
          FMT("  return %s(%s(resultSet)%s);\n"),
          hash_func_name.ptr,
          c_convert.ptr,
          out_stmt_proc ? "" : ", row");
  bprintf(h, FMT("}\n"));

  bprintf(h,
          FMT("\nstatic inline BOOL %s(%s *resultSet1"),
          cgs_eq_func_name.ptr,
          objc_name.ptr);
  if (!out_stmt_proc) {
    bprintf(h, FMT(", %s row1"), CS->rt->cql_int32);
  }
  bprintf(h, FMT(", %s *resultSet2"), objc_name.ptr);
  if (!out_stmt_proc) {
    bprintf(h, FMT(", %s row2"), CS->rt->cql_int32);
  }
  bprintf(h, FMT(")\n"));
  bprintf(h, FMT("{\n"));
  bprintf(h,
          FMT("  return %s(%s(resultSet1)%s, %s(resultSet2)%s);\n"),
          eq_func_name.ptr,
          c_convert.ptr,
          out_stmt_proc ? "" : ", row1",
          c_convert.ptr,
          out_stmt_proc ? "" : ", row2");
  bprintf(h, FMT("}\n"));

  CHARBUF_CLOSE(eq_func_name);
  CHARBUF_CLOSE(cgs_eq_func_name);
  CHARBUF_CLOSE(hash_func_name);
  CHARBUF_CLOSE(cgs_hash_func_name);
  CHARBUF_CLOSE(c_convert);
  CHARBUF_CLOSE(c_result_set_ref);
  CHARBUF_CLOSE(c_result_set);
  CHARBUF_CLOSE(c_name);
  CHARBUF_CLOSE(objc_result_set_name);
  CHARBUF_CLOSE(objc_name);

  CS->sem.use_encode = 0;
  symtab_delete(CS, CS->sem.encode_columns);
  CS->sem.encode_columns = NULL;
  CS->sem.encode_context_column = NULL;
}

static void cg_objc_create_proc_stmt(CqlState* _Nonnull CS, ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast));
  EXTRACT_STRING(name, ast->left);
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  bool_t result_set_proc = has_result_set(ast);
  bool_t out_stmt_proc = has_out_stmt_result(ast);
  bool_t out_union_proc = has_out_union_stmt_result(ast);

  if (result_set_proc || out_stmt_proc || out_union_proc) {
    cg_objc_proc_result_set(CS, ast);
  }
}

static void cg_objc_one_stmt(CqlState* _Nonnull CS, ast_node *stmt) {
  // DDL operations not in a procedure are ignored
  // but they can declare schema during the semantic pass
  if (is_ast_create_proc_stmt(stmt)) {
    cg_objc_create_proc_stmt(CS, stmt);
  }
}

static void cg_objc_stmt_list(CqlState* _Nonnull CS, ast_node *head) {
  for (ast_node *ast = head; ast; ast = ast->right) {
    EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, ast);
    if (is_ast_create_proc_stmt(stmt) && is_proc_shared_fragment(CS, stmt)) {
      // shared fragments never create any code
      continue;
    }

    cg_objc_one_stmt(CS, stmt);
  }
}


static void cg_objc_init(CqlState* _Nonnull CS) {
  cg_common_init(CS);
}

// Main entry point for code-gen.
cql_noexport void cg_objc_main(CqlState* _Nonnull CS, ast_node *head) {
  Invariant(CS->options.file_names_count == 1);
  Invariant(CS->is_string_column_encoded == 0);
  if (!CS->options.objc_c_include_path) {
    cql_error(CS, "The C header path must be provided as argument (use --objc_c_include_path)\n");
    cql_cleanup_and_exit(CS, 1);
  }
  cql_exit_on_semantic_errors(CS, head);
  exit_on_validating_schema(CS);

  cg_objc_init(CS);

  CHARBUF_OPEN(header_file);
  CHARBUF_OPEN(imports);

  bprintf(&header_file, FMT("%s"), CS->rt->header_prefix);
  bprintf(&header_file, FMT("\n#import <%s>\n"), CS->options.objc_c_include_path);

  // gen objc code ....
  cg_objc_stmt_list(CS, head);

  bprintf(&header_file, FMT("%s"), CS->rt->header_wrapper_begin);

  if (CS->is_string_column_encoded) {
    bprintf(&header_file, FMT("\n@class %s;\n"), CS->rt->cql_string_ref_encode);
  }

  bprintf(&header_file, FMT("%s"), CS->cg_header_output->ptr);
  bprintf(&header_file, FMT("%s"), CS->rt->header_wrapper_end);

  CSTR header_file_name = CS->options.file_names[0];
  cql_write_file(CS, header_file_name, header_file.ptr);

  CHARBUF_CLOSE(imports);
  CHARBUF_CLOSE(header_file);

  // reset globals so they don't interfere with leaksan
  CS->is_string_column_encoded = 0;
}

#endif
