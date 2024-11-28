#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# cqlcs.py -> converts CQL JSON format into a C Sqlite extension
#
# The CQL JSON format is documented here: https://cgsql.dev/cql-guide/ch13
# and here: https://cgsql.dev/json-diagram
#
# NB: This code should be considered SAMPLE code, not production code.
# Feel free to fork it and modify it to suit your needs.
import json
import sys

def usage():
    print(
        """
Usage: input.json [options] >result.c

--cql_header header_file
    specifies the CQL generated header file to include in the generated C code
"""
    )
    sys.exit(0)

# Reference type check
is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True

# Sqlite3 null value getter for the given types
sqlite3_value_getter_nullable = {}
sqlite3_value_getter_nullable["bool"] = "resolve_nullable_bool_from_sqlite3_value"
sqlite3_value_getter_nullable["integer"] = "resolve_nullable_integer_from_sqlite3_value"
sqlite3_value_getter_nullable["long"] = "resolve_nullable_long_from_sqlite3_value"
sqlite3_value_getter_nullable["real"] = "resolve_nullable_real_from_sqlite3_value"
sqlite3_value_getter_nullable["object"] = "resolve_object_from_sqlite3_value"
sqlite3_value_getter_nullable["blob"] = "resolve_blob_from_sqlite3_value"
sqlite3_value_getter_nullable["text"] = "resolve_text_from_sqlite3_value"

# Sqlite3 null value getter for the given types
sqlite3_value_getter_notnull = {}
sqlite3_value_getter_notnull["bool"] = "RESOLVE_NOTNULL_BOOL_FROM_SQLITE3_VALUE"
sqlite3_value_getter_notnull["integer"] = "RESOLVE_NOTNULL_INTEGER_FROM_SQLITE3_VALUE"
sqlite3_value_getter_notnull["long"] = "RESOLVE_NOTNULL_LONG_FROM_SQLITE3_VALUE"
sqlite3_value_getter_notnull["real"] = "RESOLVE_NOTNULL_REAL_FROM_SQLITE3_VALUE"
sqlite3_value_getter_notnull["object"] = "resolve_object_from_sqlite3_value"
sqlite3_value_getter_notnull["blob"] = "resolve_blob_from_sqlite3_value"
sqlite3_value_getter_notnull["text"] = "resolve_text_from_sqlite3_value"

# Sqlite3 result setter for the given types
sqlite3_result_setter_notnull = {}
sqlite3_result_setter_notnull["bool"] = "sqlite3_result_int"
sqlite3_result_setter_notnull["integer"] = "sqlite3_result_int"
sqlite3_result_setter_notnull["long"] = "sqlite3_result_int64"
sqlite3_result_setter_notnull["real"] = "sqlite3_result_double"
sqlite3_result_setter_notnull["object"] = "sqlite3_result_pointer"
sqlite3_result_setter_notnull["blob"] = "sqlite3_result_blob"
sqlite3_result_setter_notnull["text"] = "sqlite3_result_text"

# Sqlite3 result setter for nullable CQL types implemented with macros
sqlite3_result_setter_nullable = {}
sqlite3_result_setter_nullable["bool"] = "SQLITE3_RESULT_CQL_NULLABLE_INT"
sqlite3_result_setter_nullable["integer"] = "SQLITE3_RESULT_CQL_NULLABLE_INT"
sqlite3_result_setter_nullable["long"] = "SQLITE3_RESULT_CQL_NULLABLE_INT64"
sqlite3_result_setter_nullable["real"] = "SQLITE3_RESULT_CQL_NULLABLE_DOUBLE"
sqlite3_result_setter_nullable["object"] = "SQLITE3_RESULT_CQL_POINTER"
sqlite3_result_setter_nullable["blob"] = "SQLITE3_RESULT_CQL_BLOB"
sqlite3_result_setter_nullable["text"] = "SQLITE3_RESULT_CQL_TEXT"

# CQL row type codes for the given kinds of fields
row_types = {}
row_types["bool"] = "CQL_DATA_TYPE_BOOL"
row_types["integer"] = "CQL_DATA_TYPE_INT32"
row_types["long"] = "CQL_DATA_TYPE_INT64"
row_types["real"] = "CQL_DATA_TYPE_DOUBLE"
row_types["object"] = "CQL_DATA_TYPE_OBJECT"
row_types["blob"] = "CQL_DATA_TYPE_BLOB"
row_types["text"] = "CQL_DATA_TYPE_STRING"

# Notnull CQL C types for the given type of fields
cql_notnull_types = {}
cql_notnull_types["bool"] = "cql_bool"
cql_notnull_types["integer"] = "cql_int32"
cql_notnull_types["long"] = "cql_int64"
cql_notnull_types["real"] = "cql_double"
cql_notnull_types["object"] = "cql_object_ref"
cql_notnull_types["blob"] = "cql_blob_ref"
cql_notnull_types["text"] = "cql_string_ref"

# Nullable CQL C types for the given type of fields
cql_nullable_types = {}
cql_nullable_types["bool"] = "cql_nullable_bool"
cql_nullable_types["integer"] = "cql_nullable_int32"
cql_nullable_types["long"] = "cql_nullable_int64"
cql_nullable_types["real"] = "cql_nullable_double"
cql_nullable_types["object"] = "cql_object_ref"
cql_nullable_types["blob"] = "cql_blob_ref"
cql_nullable_types["text"] = "cql_string_ref"

# Storage for the various command line arguments
cmd_args = {}
cmd_args["cql_header"] = "something.h"
cmd_args["namespace"] = ""


def emit_licence():
    # Include original license — Not actually written by Meta
    print("""
/*
* Copyright (c) Meta Platforms, Inc. and affiliates.
*
* This source code is licensed under the MIT license found in the
* LICENSE file in the root directory of this source tree.
*/

""")

def emit_headers():
    print("#include <sqlite3ext.h>")
    print("SQLITE_EXTENSION_INIT1")
    print("#include \"cqlrt.h\"")
    print("#include \"cql_sqlite_extension.h\"")
    print(f"#include \"{cmd_args['cql_header']}\"")
    print("")


def emit_extension_initializer(data):

    print("""
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi) {
  SQLITE_EXTENSION_INIT2(pApi);

  int rc = SQLITE_OK;
""")
    for proc in data['queries'] + data['deletes'] + data['inserts'] + data['generalInserts'] + data['updates'] + data['general']:
        print(f"""
  rc = sqlite3_create_function(db, "{cmd_args['namespace']}{proc['name']}", {len([arg for arg in proc['args'] if arg.get('binding', 'in') in ['in', 'inout']])}, SQLITE_UTF8, NULL, call_{cmd_args['namespace']}{proc['name']}, NULL, NULL);
  if (rc != SQLITE_OK) return rc;
""")

    print("""
  return rc;
}

""")

def emit_all_procs(data):
    for proc in (
        data["queries"] +
        data["deletes"] +
        data["inserts"] +
        data["generalInserts"] +
        data["updates"] +
        data["general"]
    ):
        proc['usesDatabase'] = proc["usesDatabase"] if "usesDatabase" in proc else True
        proc['projection'] = "projection" in proc
        proc['canonicalName'] = f"call_{cmd_args['namespace']}{proc['name']}"

        attributes = {}
        for attr in proc.get("attributes", []):
            attributes[attr['name']] = attr['value']

        # no codegen for private methods
        if "cql:private" in attributes: return

        emit_proc_c_func_body(proc, attributes)

# This emits the main body of the C Interop function, this includes
# * the Interop entry point for the procedure
# * the call to the procedure
# * the marshalling of the results
# * the return of the results
# * the cleanup of the results
def emit_proc_c_func_body(proc, attributes):
    in_arguments = [arg for arg in proc['args'] if arg.get('binding', 'in') == ('in')]
    inout_arguments = [arg for arg in proc['args'] if arg.get('binding', 'in') == ('inout')]
    out_arguments = [arg for arg in proc['args'] if arg.get('binding', 'in') == ('out')]

    innie_arguments = in_arguments + inout_arguments
    outtie_arguments = inout_arguments + out_arguments


    print(f"void {proc['canonicalName']}(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv)", end="")
    print("{")

    print(f"  // 1. Ensure Sqlite function argument count matches count of the procedure in and inout arguments")
    print(f"  if (argc != {len(innie_arguments)}) goto invalid_arguments;")
    print(f"")


    print("  // 2. Ensure sqlite3 value type is compatible with cql type")
    for index, arg in enumerate(innie_arguments):
        print(
            f"  if (!is_sqlite3_type_compatible_with_cql_core_type("
                f"sqlite3_value_type(argv[{index}]), "
                f"{row_types[arg['type']]}, "
                f"{'cql_false' if arg['isNotNull'] else 'cql_true'}"
            f")) goto invalid_arguments; // {arg['name']}"
        )
    print("")


    print("  // 3. Marshalled argument initialization")
    for index, arg in enumerate(innie_arguments):
        if arg['type'] in ("text", "blob", "object"):
            print(f"  {cql_nullable_types[arg['type']].ljust(20)} {arg['name'].ljust(25)} = {sqlite3_value_getter_nullable[arg['type']]}(argv[{index}]);")
        elif arg['isNotNull']:
            print(f"  {cql_notnull_types[arg['type']].ljust(20)} {arg['name'].ljust(25)} = {sqlite3_value_getter_notnull[arg['type']]}(argv[{index}]);")
        else:
            print(f"  {cql_nullable_types[arg['type']].ljust(20)} {arg['name'].ljust(25)} = {sqlite3_value_getter_nullable[arg['type']]}(argv[{index}]);")
    for arg in out_arguments:
        if arg['type'] in ("text", "blob", "object"):
            print(f"  {cql_nullable_types[arg['type']].ljust(20)} {arg['name'].ljust(25)} = NULL;")
        elif arg['isNotNull']:
            print(f"  {cql_notnull_types[arg['type']].ljust(20)} {arg['name'].ljust(25)} = 0;")
        else:
            print(f"  {cql_nullable_types[arg['type']].ljust(20)} {(arg['name'] + ';').ljust(25)}   cql_set_null({arg['name']});")
    print("")


    print("  // 4. Initialize procedure dependencies")
    if proc['projection']:   print(f"  {proc['name']}_result_set_ref _data_result_set_ = NULL;")
    if proc['usesDatabase']: print(f"  sqlite3* db = sqlite3_context_db_handle(context);")
    if proc['usesDatabase']: print(f"  cql_code rc = SQLITE_OK;")
    print("") if proc['usesDatabase'] or proc['projection'] else None


    print("  // 5. Call the procedure")
    print(f"  {'rc = ' if proc['usesDatabase'] else ''}{proc['name']}{'_fetch_results' if proc['projection'] else ''}(", end="")
    for index, computed_arg in enumerate(
        (["db"] if proc['usesDatabase'] else []) +
        (["&_data_result_set_"] if proc['projection'] else []) +
        [
            f"&{arg['name']}" if arg.get('binding', 'in') != "in"
                else arg['name'] if arg['type'] != "object"
                else "/* unsupported arg type object*/"
            for arg in proc['args']
        ]
    ):
        print(f"{',' if index > 0 else ''}\n    {computed_arg}", end="")
    print("")
    print("  );")
    print("")


    print("  // 6. Cleanup In arguments since they are no longer needed")
    for arg in [arg for arg in in_arguments if is_ref_type[arg['type']]]:
        if   arg['type'] == "text":   print(f"  cql_string_release({arg['name']});")
        elif arg['type'] == "blob":   print(f"  cql_blob_release({  arg['name']});")
        elif arg['type'] == "object": print(f"  cql_object_release({arg['name']});")
    print("")


    print("  // 7. Ensure the procedure executed successfully")
    if proc['usesDatabase']:
        print("  if (rc != SQLITE_OK) {")
        print("    sqlite3_result_null(context);")
        print("    goto cleanup;")
        print("  }")
    print("")


    print("  // 8. Resolve the result base on:")
    print("  //   (A) The first column of first row of the result_set, if any")
    print("  //   (B) The first outtie argument (in or inout) value, if any")
    print("  //   (C) Fallback to: null")
    print("  //")
    if proc['projection']:
        print("  // Current strategy: (A) Using the result set")

        print("  set_sqlite3_result_from_result_set(context, (cql_result_set_ref)_data_result_set_);")
        print("  goto cleanup;")
        print("")
    else:
        print("  // Current strategy: (B) Using Outtie arguments")
        print("  // Set Sqlite result")
        print("  // NB: If the procedure generates a cql result set, the first column of the first row would be used as the result")
        for arg in [arg for arg in proc['args'] if arg.get('binding', 'in') in ("inout", "out")]:
            skip = False

            if arg['type'] == "text":
                print(f"  SQLITE3_RESULT_CQL_TEXT(context, {arg['name']}); goto cleanup;")
            elif arg['type'] == "blob":
                print(f"  SQLITE3_RESULT_CQL_BLOB(context, {arg['name']}); goto cleanup;")
            elif is_ref_type[arg['type']]:
                # Object
                print(f"  /* {arg['type']} not implemented yet */")
                skip = True
            elif arg['isNotNull']:
                print(f"  {sqlite3_result_setter_notnull[arg['type']]}(context, {arg['name']}); goto cleanup;")
            elif not arg['isNotNull']:
                print(f"  {sqlite3_result_setter_nullable[arg['type']]}(context, {arg['name']}); goto cleanup;")
            else:
                print(f"  /* Unsupported type {arg['type']} */")
                skip = True

            if not skip:
                break
        print("")
        print("  goto cleanup;")


    print("invalid_arguments:")
    print("  sqlite3_result_error(context, \"CQL extension: Invalid procedure arguments\", -1);")
    print("  return;")


    print("")
    print("cleanup:")
    print("  // 10. Cleanup Outtie arguments")
    for arg in [arg for arg in outtie_arguments if is_ref_type[arg['type']]]:
        if   arg['type'] == "text":   print(f"  if({arg['name']}) cql_string_release({arg['name']});")
        elif arg['type'] == "blob":   print(f"  if({arg['name']}) cql_blob_release({  arg['name']});")
        elif arg['type'] == "object": print(f"  if({arg['name']}) cql_object_release({arg['name']});")
    print("  /* Avoid empty block warning */ ;")

    print("}")
    print("")

def main():
    jfile = sys.argv[1]
    with open(jfile) as json_file:
        data = json.load(json_file)
        i = 2

        while i + 2 <= len(sys.argv):
            if sys.argv[i] == "--cql_header":
                cmd_args["cql_header"] = sys.argv[i + 1]
            elif sys.argv[i] == "--namespace":
                cmd_args["namespace"] = sys.argv[i + 1] + '_'
            else:
                usage()
            i += 2

        emit_licence()
        emit_headers()
        emit_all_procs(data)
        emit_extension_initializer(data)

if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
