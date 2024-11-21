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

// note the @ is split from the generated so that tools don't think this is a generated file
#define RT_AUTOGEN(x) x " @" "generated S" "ignedSource<<deadbeef8badf00ddefec8edfacefeed>>\n"

// These are the various result types we can produce
// they include useful string fragments for the code generator

static rtdata rt_c = {
  .name = "c",
  .code_generator = &cg_c_main,
  .required_file_names_count = -1,
  .header_prefix =
    RT_AUTOGEN("//")
    "#pragma once\n\n",
  .cqlrt_template = "#include \"%s\"\n\n",
  .cqlrt = "cqlrt.h",
  .header_wrapper_begin = "",
  .header_wrapper_end = "",
  .source_prefix =
    RT_AUTOGEN("//") "\n",
  .source_wrapper_begin = "",
  .source_wrapper_end = "",
  .exports_prefix =
    RT_AUTOGEN("--") "\n",
  .symbol_case = cg_symbol_case_snake,
  .generate_equality_macros = 1,
  .symbol_prefix = "",
  .symbol_visibility = "extern ",
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
    RT_AUTOGEN("--") "\n",
  .source_wrapper_begin = "",
  .source_wrapper_end = "",
  .exports_prefix = "",
  .symbol_case = cg_symbol_case_snake,
  .generate_equality_macros = 1,
  .symbol_prefix = ""
};

static rtdata rt_objc = {
  .name = "objc",
  .code_generator = &cg_objc_main,
  .required_file_names_count = 1,
  // note the @ is split from the generated so that tools don't think this is a generated file
  .header_prefix =
    RT_AUTOGEN("//")
    "#pragma once\n\n"
    "#import <Foundation/Foundation.h>\n",
  .header_wrapper_begin = "\nNS_ASSUME_NONNULL_BEGIN\n",
  .header_wrapper_end = "\nNS_ASSUME_NONNULL_END\n",
  .symbol_case = cg_symbol_case_snake,
  .generate_equality_macros = 1,
  .symbol_prefix = "CGS_",
  .impl_symbol_prefix = "",  
  .cql_string_ref_encode_include = "",
};

static rtdata rt_schema_upgrade = {
  .name = "schema_upgrade",
  .code_generator = &cg_schema_upgrade_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_AUTOGEN("--") "\n",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_schema_sqlite = {
  .name = "schema_sqlite",
  .code_generator = &cg_schema_sqlite_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_AUTOGEN("--") "\n",
  .symbol_case = cg_symbol_case_camel,
};

static rtdata rt_schema = {
  .name = "schema",
  .code_generator = &cg_schema_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_AUTOGEN("--") "\n",
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
    RT_AUTOGEN("--") "\n",
};

static rtdata rt_query_plan = {
  .name = "query_plan",
  .code_generator = &cg_query_plan_main,
  .required_file_names_count = 1,
  .source_prefix =
    RT_AUTOGEN("--") "\n",
};

static rtdata rt_stats = {
  .name = "stats",
  .code_generator = &cg_stats_main,
  .required_file_names_count = 1,
};

static rtdata *(rt_all[]) = {
  &rt_c,
  &rt_objc,
  &rt_lua,
  &rt_schema_upgrade,
  &rt_schema_sqlite,
  &rt_schema,
  &rt_json_schema,
  &rt_test_helpers,
  &rt_query_plan,
  &rt_stats,
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

  return rt_;
}

cql_noexport void rt_cleanup() {
}
