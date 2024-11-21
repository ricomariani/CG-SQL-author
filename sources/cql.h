/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// cql - pronounced "see-queue-el" is a basic tool for enabling stored
//       procedures for SQLite. The tool does this by parsing a language
//       not unlike typical SQL stored procedure forms available in
//       MySql and SQL Server.
//
//       Broadly speaking compilation is as follows:
//         * SQL statements such as SELECT/INSERT/UPDATE/DELETE
//           are converted into calls to SQLite to do the work.
//           Any variables in those statements are converted into
//           the appropriate binding and and results are read out
//           with the usual SQLite column reading.
//         * Stored procedure control flow is converted into the equivalent
//           C directly.  So for instance an 'IF' in the SQL becomes
//           a correlated 'if' in the generated code.
//
//       The result of this is that CQL produces, "The C you could have
//       written yourself using the SQLite API to do that database operation."
//       CQL does this in a less brittle and type-safe way that is far
//       more maintainable.
//
// Design principles:
//
//  1. Keep each pass in one file (simple, focused, and easy refactor)
//  2. Use simple printable AST parse nodes (no separate #define per AST node type)
//  3. 100% coverage of all logic, no exceptions.

#pragma once

#include "diags.h"

#include <assert.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#ifndef CQL_AMALGAM

// as well as the integration points.
#define cql_noexport extern
#define cql_export extern
#define cql_data_decl(x) extern x
#define cql_data_defn(x) x

#endif

typedef uint8_t bool_t;
typedef long long int llint_t;

#include "compat.h"

#define u32_not(x) ((uint32_t)(~(x)))
#define u64_not(x) ((uint64_t)(~(x)))

#if LONG_MAX > 0x7fffffff
#define _64(x) x##L
#else
#define _64(x) x##LL
#endif

// patternlint-disable-next-line prefer-sized-ints-in-msys
int main(int argc, char **argv);

// we need this for some callbacks
struct charbuf;

typedef struct cmd_options {
  bool_t test;
  bool_t echo_input;
  bool_t hide_builtins;
  bool_t print_ast;
  bool_t ast_no_echo;
  bool_t print_dot;
  bool_t expand;
  bool_t semantic;
  bool_t codegen;
  bool_t compress;
  bool_t generate_exports;
  bool_t run_unit_tests;
  bool_t nolines;
  bool_t schema_exclusive;
  char *rt;
  char **file_names;
  uint32_t file_names_count;
  char **include_paths;
  uint32_t include_paths_count;
  char **defines;
  uint32_t defines_count;
  char **include_regions;
  uint32_t include_regions_count;
  char **exclude_regions;
  uint32_t exclude_regions_count;
  int32_t min_schema_version;
  char *c_include_path;
  char *objc_c_include_path;
  char *c_include_namespace;
  char *cqlrt;
  bool_t dev;                           // option use to activate features in development or dev features
} cmd_options;

cql_data_decl( cmd_options options );

#define Invariant assert
#define Contract assert

#define _new(x) ((x*)malloc(sizeof(x)))
#define _new_array(x,c) ((x*)malloc(c*sizeof(x)))

#define CQL_NICE_LITERAL_NAME_LIMIT 32

// note this is not easily changed, storage for used strach variables is in an unsigned long long
#define CQL_MAX_STACK 128

typedef const char *CSTR;

typedef enum cg_symbol_case {
  cg_symbol_case_snake,
  cg_symbol_case_pascal,
  cg_symbol_case_camel,
} cg_symbol_case;

cql_data_decl( const char *global_proc_name );

typedef struct ast_node *ast_ptr;

typedef struct rtdata {
  // the command line name of this result type
  const char *name;

  // The main code generator function that will be executed.
  void (*code_generator)(ast_ptr root);

  // The number of file names required by the rt. Use -1 for a variable number
  // of file names that will be verified by the code generator itself based on
  // the arguments passed t it
  int32_t required_file_names_count;

  // A string to add before any header contents (include copyright, autogen comments, runtime include, etc).
  const char *header_prefix;

  // The default "cqlrt.h" for this code type
  const char *cqlrt;

  // the formatting string into which the filename above is placed
  const char *cqlrt_template;

  // A begin string to wrap the contents of the header file.
  const char *header_wrapper_begin;

  // A end string to wrap the contents of the header file.
  const char *header_wrapper_end;

  // A string to add before any source contents (include copyright, autogen comments, etc).
  const char *source_prefix;

  // A begin string to wrap the contents of the source file.
  const char *source_wrapper_begin;

  // A end string to wrap the contents of the source file.
  const char *source_wrapper_end;

  // A string to add before any import file contents (include copyright, autgen comments, etc).
  const char *exports_prefix;

  // The case to use for symbols.
  cg_symbol_case symbol_case;

  // If enabled, macros will be generated to test equality between 2 list/index pairs.
  bool_t generate_equality_macros;

  // Called for each proc name that is processed.
  void (*register_proc_name)(const char *proc_name);

  // Predicate function to determine whether to implicitly generate the copy function for a result set.
  // The cql:generate_copy attribute overrides the value, if specified.
  bool_t (*proc_should_generate_copy)(const char *proc_name);

  // Provides a chance to add some extra definitions to the result set type, specify if extra stuff needed.
  void (*result_set_type_decl_extra)(struct charbuf *output, CSTR sym, CSTR ref);

  // Prefix for public symbol.
  const char *symbol_prefix;

  // Prefix for private implementation symbol.
  const char *impl_symbol_prefix;

  // Visibility attribute for generated functions.
  const char *symbol_visibility;

  // The type for a sqlite3 result code.
  const char *cql_code;

  // The include library for the encode type for a string object.
  const char *cql_string_ref_encode_include;

  // Generic is_encoded value getter on base result set object.
  // NOTE: This function should call through to the
  // inline type getters that are passed into the ctor for the result set.
  // @param result_set The cql result_set object.
  // @param col The column to fetch the value for.
  // @return cql_true if the value is sensitive, otherwise cql_false.
  // cql_bool cql_result_set_get_is_encoded(cql_result_set_ref result_set, int32_t col)
  const char *cql_result_set_get_is_encoded;

  // Generic bool value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new boolean value to be set.
  // void cql_result_set_set_bool(cql_result_set_ref result_set, int32_t row, int32_t col, cql_bool new_value)
  const char *cql_result_set_set_bool;

  // Generic double value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new boolean value to be set.
  // void cql_result_set_set_double(cql_result_set_ref result_set, int32_t row, int32_t col, double new_value)
  const char *cql_result_set_set_double;

  // Generic cql_int32 value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new cql_int32 value to be set.
  // void cql_result_set_set_int32(cql_result_set_ref result_set, int32_t row, int32_t col, cql_int32 new_value)
  const char *cql_result_set_set_int32;

  // Generic int64 value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new int64 value to be set.
  // void cql_result_set_set_int64(cql_result_set_ref result_set, int32_t row, int32_t col, cql_int64 new_value)
  const char *cql_result_set_set_int64;

  // Generic string value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new string value to be set.
  // void cql_result_set_set_string(cql_result_set_ref result_set, int32_t row, int32_t col, cql_string new_value)
  const char *cql_result_set_set_string;

  // Generic object value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new object value to be set.
  // void cql_result_set_set_object(cql_result_set_ref result_set, int32_t row, int32_t col, cql_object new_value)
  const char *cql_result_set_set_object;

  // Generic blob value setter on base result set object.
  // @param result_set The cql result_set object.
  // @param row The row number to set the value for.
  // @param col The column to set the value for.
  // @param new_value the new blob value to be set.
  // void cql_result_set_set_blob(cql_result_set_ref result_set, int32_t row, int32_t col, cql_blob new_value)
  const char *cql_result_set_set_blob;

  // The target type for NULL object value.
  const char *cql_target_null;

  void (*cql_post_common_init)(void);
} rtdata;

cql_data_decl( rtdata *rt );

cql_noexport void cql_cleanup_and_exit(int32_t code);

// output to "stderr"
cql_noexport void cql_error(const char *format, ...) __attribute__ (( format( printf, 1, 2 ) ));

// output to "stdout"
cql_noexport void cql_output(const char *format, ...) __attribute__ (( format( printf, 1, 2 ) ));

// Creates a file in write mode. Aborts if there's any error.
cql_export FILE *cql_open_file_for_write(CSTR file_name);

// Create file, write the data to it, and close the file
cql_export void cql_write_file(const char *file_name, const char *data);

cql_noexport void line_directive(const char *directive);

cql_export void cql_emit_error(const char *err);

cql_export void cql_emit_output(const char *out);

cql_data_decl( char *current_file );

cql_noexport CSTR get_last_doc_comment();

cql_noexport CSTR cql_builtin_text();

cql_noexport void cql_setup_for_builtins(void);

cql_noexport int32_t macro_type_from_str(CSTR type);
cql_noexport int32_t macro_arg_type(struct ast_node *ast);

cql_noexport void cql_cleanup_open_includes(void);
cql_noexport void cql_reset_open_includes(void);

cql_noexport bool_t cql_is_defined(CSTR name);
