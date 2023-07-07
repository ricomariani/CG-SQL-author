/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"
#include "cg_common.h"
#include "cg_c.h"
#include "cg_json_schema.h"
#include "cg_lua.h"
#include "cg_objc.h"
#include "cg_query_plan.h"
#include "cg_schema.h"
#include "cg_stats.h"
#include "cg_test_helpers.h"
#include "rt.h"

// These are the various result types we can produce
// they include useful string fragments for the code generator

// patternlint-disable prefer-sized-ints-in-msys
// patternlint-disable windows-comptability-prefer-sized-longs-in-msys
// disabled due to many instances of "int" and "long" in a string or a comment

static rtdata rt_c = {
  .name = "c",
  .code_generator = &cg_c_main,
  .required_file_names_count = -1,
  .header_prefix =
    RT_IP_NOTICE("//")
    RT_AUTOGEN("//")
    "#pragma once\n\n",
  .cqlrt_template = "#include \"%s\"\n\n",
  .cqlrt = "cqlrt.h",
  .header_wrapper_begin = "",
  .header_wrapper_end = "",
  .source_prefix =
    RT_IP_NOTICE("//")
    RT_AUTOGEN("//") "\n",
  .source_wrapper_begin = "",
  .source_wrapper_end = "",
  .exports_prefix =
    RT_IP_NOTICE("--")
    RT_AUTOGEN("--") "\n",
  .symbol_case = cg_symbol_case_snake,
  .generate_type_getters = 0,
  .generate_equality_macros = 1,
  .symbol_prefix = "",
  .symbol_visibility = "extern ",
  .cql_contract = "cql_contract",
  .cql_log_database_error = "cql_log_database_error",
  .cql_bool = "cql_bool",
  .cql_int32 = "cql_int32",
  .cql_int64 = "cql_int64",
  .cql_double = "cql_double",
  .cql_code = "cql_code",
  .cql_blob_ref = "cql_blob_ref",
  .cql_blob_retain = "cql_blob_retain",
  .cql_blob_release = "cql_blob_release",
  .cql_blob_equal = "cql_blob_equal",
  .cql_object_ref = "cql_object_ref",
  .cql_object_retain = "cql_object_retain",
  .cql_object_release = "cql_object_release",
  .cql_string_ref = "cql_string_ref",
  .cql_string_ref_new = "cql_string_ref_new",
  .cql_get_blob_size = "cql_get_blob_size",
  .cql_string_literal = "cql_string_literal",
  .cql_string_proc_name = "cql_string_proc_name",
  .cql_string_retain = "cql_string_retain",
  .cql_string_release = "cql_string_release",
  .cql_string_hash = "cql_string_hash",
  .cql_blob_hash = "cql_blob_hash",
  .cql_string_compare = "cql_string_compare",
  .cql_string_equal = "cql_string_equal",
  .cql_string_like = "cql_string_like",
  .cql_alloc_cstr = "cql_alloc_cstr",
  .cql_free_cstr = "cql_free_cstr",
  .cql_result_set_ref = "cql_result_set_ref",
  .cql_result_set_ref_new = "cql_result_set_create",
  .cql_result_set_meta_struct = "cql_result_set_meta",
  .cql_result_set_get_meta = "cql_result_set_get_meta",
  .cql_result_set_retain = "cql_result_set_retain",
  .cql_result_set_release = "cql_result_set_release",
  .cql_result_set_get_count = "cql_result_set_get_count",
  .cql_result_set_get_data = "cql_result_set_get_data",
  .cql_result_set_get_bool = "cql_result_set_get_bool_col",
  .cql_result_set_get_double = "cql_result_set_get_double_col",
  .cql_result_set_get_int32 = "cql_result_set_get_int32_col",
  .cql_result_set_get_int64 = "cql_result_set_get_int64_col",
  .cql_result_set_get_string = "cql_result_set_get_string_col",
  .cql_result_set_get_object = "cql_result_set_get_object_col",
  .cql_result_set_get_blob = "cql_result_set_get_blob_col",
  .cql_result_set_get_is_null = "cql_result_set_get_is_null_col",
  .cql_result_set_get_is_encoded = "cql_result_set_get_is_encoded_col",
  .cql_result_set_set_bool = "cql_result_set_set_bool_col",
  .cql_result_set_set_double = "cql_result_set_set_double_col",
  .cql_result_set_set_int32 = "cql_result_set_set_int32_col",
  .cql_result_set_set_int64 = "cql_result_set_set_int64_col",
  .cql_result_set_set_string = "cql_result_set_set_string_col",
  .cql_result_set_set_object = "cql_result_set_set_object_col",
  .cql_result_set_set_blob = "cql_result_set_set_blob_col",
  .cql_target_null = "NULL",
};

static rtdata rt_lua = {
  .name = "lua",
  .code_generator = &cg_lua_main,
  .required_file_names_count = 1,
  .header_prefix = "",
  .cqlrt_template = "require(\"%s\")\n\n",
  .cqlrt = "cqlrt",
  .header_wrapper_begin = "",
  .header_wrapper_end = "",
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_AUTOGEN("--") "\n",
  .source_wrapper_begin = "",
  .source_wrapper_end = "",
  .exports_prefix = "",
  .symbol_case = cg_symbol_case_snake,
  .generate_type_getters = 0,
  .generate_equality_macros = 1,
  .symbol_prefix = ""
};

static rtdata rt_objc = {
  .name = "objc",
  .code_generator = &cg_objc_main,
  .required_file_names_count = 1,
  // note the @ is split from the generated so that tools don't think this is a generated file
  .header_prefix =
    RT_IP_NOTICE("//")
    RT_SIGNSRC("//")
    "#pragma once\n\n"
    "#import <Foundation/Foundation.h>\n",
  .header_wrapper_begin = "\nNS_ASSUME_NONNULL_BEGIN\n",
  .header_wrapper_end = "\nNS_ASSUME_NONNULL_END\n",
  .symbol_case = RT_OBJC_CASE,
  .generate_type_getters = 1,
  .generate_equality_macros = 1,
  .symbol_prefix = RT_SYM_PREFIX,
  .impl_symbol_prefix = RT_IMPL_SYMBOL_PREFIX,
  .cql_bool = "BOOL",
  .cql_int32 = "int32_t",
  .cql_int64 = "int64_t",
  .cql_double = "double",
  .cql_code = "int",
  .cql_blob_ref = "NSData *",
  .cql_object_ref = "NSObject *",
  .cql_string_ref = "NSString *",
  .cql_string_ref_encode = RT_STRING_ENCODE,
  .cql_string_ref_encode_include = "",
  .cql_result_set_note_ownership_transferred = "cql_result_set_note_ownership_transferred",
};

// this lets us test the OSS version of the objc gen even if the build is configured differently by default
static rtdata rt_objc_mit = {
  .name = "objc_mit",
  .code_generator = &cg_objc_main,
  .required_file_names_count = 1,
  // note the @ is split from the generated so that tools don't think this is a generated file
  .header_prefix =
    "#pragma once\n\n"
    "#import <Foundation/Foundation.h>\n",
  .header_wrapper_begin = "\nNS_ASSUME_NONNULL_BEGIN\n",
  .header_wrapper_end = "\nNS_ASSUME_NONNULL_END\n",
  .symbol_case = cg_symbol_case_snake,
  .generate_type_getters = 1,
  .generate_equality_macros = 1,
  .symbol_prefix = "CGS_",
  .impl_symbol_prefix = "",
  .cql_bool = "BOOL",
  .cql_int32 = "int32_t",
  .cql_int64 = "int64_t",
  .cql_double = "double",
  .cql_code = "int",
  .cql_blob_ref = "NSData *",
  .cql_object_ref = "NSObject *",
  .cql_string_ref = "NSString *",
  .cql_string_ref_encode = "cql_string_ref_encode",
  .cql_string_ref_encode_include = "",
  .cql_result_set_note_ownership_transferred = "cql_result_set_note_ownership_transferred",
};

static rtdata rt_schema_upgrade = {
  .name = "schema_upgrade",
  .code_generator = &cg_schema_upgrade_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_SIGNSRC("--") "\n",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_schema_sqlite = {
  .name = "schema_sqlite",
  .code_generator = &cg_schema_sqlite_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_SIGNSRC("--") "\n",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_schema = {
  .name = "schema",
  .code_generator = &cg_schema_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_SIGNSRC("--") "\n",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_json_schema = {
  .name = "json_schema",
  .code_generator = &cg_json_schema_main,
  .required_file_names_count = 1,
  .source_prefix = "",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_test_helpers = {
  .name = "test_helpers",
  .code_generator = &cg_test_helpers_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_SIGNSRC("--") "\n",
};

static rtdata rt_query_plan = {
  .name = "query_plan",
  .code_generator = &cg_query_plan_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_IP_NOTICE("--")
    RT_SIGNSRC("--") "\n",
};

static rtdata rt_stats = {
  .name = "stats",
  .code_generator = &cg_stats_main,
  .required_file_names_count = 1,
};

static rtdata *(rt_all[]) = {
  &rt_c,
  &rt_objc,
  &rt_objc_mit,
  &rt_lua,
  &rt_schema_upgrade,
  &rt_schema_sqlite,
  &rt_schema,
  &rt_json_schema,
  &rt_test_helpers,
  &rt_query_plan,
  &rt_stats,
  RT_EXTRAS
  NULL,
};

cql_noexport rtdata *find_rtdata(CSTR name) {
  rt_cleanup();

  int32_t i = 0;
  rtdata *rt_ = NULL;
  while ((rt_ = rt_all[i])) {
    if (!strcmp(rt_->name, name)) {
       break;
    }
    i++;
  }

  // the result type can override this, we don't want to check both places so normalize to the option.
  if (rt_) {
    options.generate_type_getters |= rt_->generate_type_getters;
  }

  return rt_;
}

cql_noexport void rt_cleanup() {
  RT_EXTRA_CLEANUP
}
