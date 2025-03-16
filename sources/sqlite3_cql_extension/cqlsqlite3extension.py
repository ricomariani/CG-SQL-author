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

IS_NOT_NULL = 1
IS_NULLABLE = 0

is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True

cql_row_types = {}
cql_row_types["bool"] = "CQL_DATA_TYPE_BOOL"
cql_row_types["integer"] = "CQL_DATA_TYPE_INT32"
cql_row_types["long"] = "CQL_DATA_TYPE_INT64"
cql_row_types["real"] = "CQL_DATA_TYPE_DOUBLE"
cql_row_types["object"] = "CQL_DATA_TYPE_OBJECT"
cql_row_types["blob"] = "CQL_DATA_TYPE_BLOB"
cql_row_types["text"] = "CQL_DATA_TYPE_STRING"

cql_ref_release = {}
cql_ref_release["text"] = "cql_string_release"
cql_ref_release["blob"] = "cql_blob_release"
cql_ref_release["object"] = "cql_object_release"

cql_types = {IS_NULLABLE: {}, IS_NOT_NULL: {}}
cql_types[IS_NOT_NULL]["bool"] = "cql_bool"
cql_types[IS_NOT_NULL]["integer"] = "cql_int32"
cql_types[IS_NOT_NULL]["long"] = "cql_int64"
cql_types[IS_NOT_NULL]["real"] = "cql_double"
cql_types[IS_NOT_NULL]["object"] = "cql_object_ref"
cql_types[IS_NOT_NULL]["blob"] = "cql_blob_ref"
cql_types[IS_NOT_NULL]["text"] = "cql_string_ref"
cql_types[IS_NULLABLE]["bool"] = "cql_nullable_bool"
cql_types[IS_NULLABLE]["integer"] = "cql_nullable_int32"
cql_types[IS_NULLABLE]["long"] = "cql_nullable_int64"
cql_types[IS_NULLABLE]["real"] = "cql_nullable_double"
cql_types[IS_NULLABLE]["object"] = "cql_object_ref"
cql_types[IS_NULLABLE]["blob"] = "cql_blob_ref"
cql_types[IS_NULLABLE]["text"] = "cql_string_ref"

sqlite3_value_getter = {IS_NULLABLE: {}, IS_NOT_NULL: {}}
sqlite3_value_getter[IS_NOT_NULL]["bool"] = "resolve_not_null_bool_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["integer"] = "resolve_not_null_integer_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["long"] = "resolve_not_null_long_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["real"] = "resolve_not_null_real_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["object"] = "resolve_object_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["blob"] = "resolve_blob_from_sqlite3_value"
sqlite3_value_getter[IS_NOT_NULL]["text"] = "resolve_text_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["bool"] = "resolve_nullable_bool_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["integer"] = "resolve_nullable_integer_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["long"] = "resolve_nullable_long_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["real"] = "resolve_nullable_real_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["object"] = "resolve_object_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["blob"] = "resolve_blob_from_sqlite3_value"
sqlite3_value_getter[IS_NULLABLE]["text"] = "resolve_text_from_sqlite3_value"

sqlite3_result_setter = {IS_NULLABLE: {}, IS_NOT_NULL: {}}
sqlite3_result_setter[IS_NOT_NULL]["bool"] = "sqlite3_result_int"
sqlite3_result_setter[IS_NOT_NULL]["integer"] = "sqlite3_result_int"
sqlite3_result_setter[IS_NOT_NULL]["long"] = "sqlite3_result_int64"
sqlite3_result_setter[IS_NOT_NULL]["real"] = "sqlite3_result_double"
sqlite3_result_setter[IS_NOT_NULL]["object"] = "sqlite3_result_pointer"
sqlite3_result_setter[IS_NOT_NULL]["blob"] = "sqlite3_result_blob"
sqlite3_result_setter[IS_NOT_NULL]["text"] = "sqlite3_result_text"
sqlite3_result_setter[IS_NULLABLE]["bool"] = "sqlite3_result_cql_nullable_bool"
sqlite3_result_setter[IS_NULLABLE]["integer"] = "sqlite3_result_cql_nullable_int"
sqlite3_result_setter[IS_NULLABLE]["long"] = "sqlite3_result_cql_nullable_int64"
sqlite3_result_setter[IS_NULLABLE]["real"] = "sqlite3_result_cql_nullable_double"
sqlite3_result_setter[IS_NULLABLE]["object"] = "sqlite3_result_cql_pointer"
sqlite3_result_setter[IS_NULLABLE]["blob"] = "sqlite3_result_cql_blob"
sqlite3_result_setter[IS_NULLABLE]["text"] = "sqlite3_result_cql_text"

# Indentation-aware utils to emit code
indentation_state = {'value': 0, 'pending_line': False}

def codegen_utils(cmd_args):
    verbosity = {
        'quiet': 0,
        'normal': 1,
        'verbose': 2,
        'very_verbose': 3,
        'debug': 4
    }.get(cmd_args.get('verbosity', 'normal'), 3)

    def indent(indentation=1):
        if not indentation_state['pending_line']:
            indentation_state["value"] += indentation

    def dedent(indentation=1):
        if not indentation_state['pending_line']:
            indentation_state["value"] = max(0, indentation_state["value"] - indentation)

    def indetented_print(*args, **kwargs):
        text = kwargs.get("sep", " ").join(map(str, args))
        lines = text.split("\n")

        for i, line in enumerate(lines):
            if i > 0 or not indentation_state['pending_line']:
                print("  " * indentation_state['value'], end="")
            print(line, end="" if i < len(lines) - 1 else kwargs.get("end", "\n"))

        indentation_state['pending_line'] = kwargs.get("end", "\n") != "\n" and not text.endswith("\n")

    noop = lambda *args, **kwargs: None
    code = lambda *args, **kwargs: indetented_print(*args, **kwargs)
    v = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 1 else noop(*args, **kwargs)
    vv = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 2 else noop(*args, **kwargs)
    vvv = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 3 else noop(*args, **kwargs)

    return code, v, vv, vvv, indent, dedent

# Not actually written by Meta
def emit_original_licence():
    print("/*")
    print("* Copyright (c) Meta Platforms, Inc. and affiliates.")
    print("*")
    print("* This source code is licensed under the MIT license found in the")
    print("* LICENSE file in the root directory of this source tree.")
    print("*/")
    print("")

def emit_headers(cmd_args):
    print(f"#include <sqlite3ext.h>")
    print(f"SQLITE_EXTENSION_INIT1")
    print(f"#include \"cqlrt.h\"")
    print(f"#include \"cql_sqlite_extension.h\"")
    print(f"#include \"{cmd_args['cql_header']}\"")
    print(f"")

def emit_extension_initializer(data, cmd_args):

    print("""
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi) {
  SQLITE_EXTENSION_INIT2(pApi);

  int rc = SQLITE_OK;
""")
    for proc in data['queries'] + data['deletes'] + data['inserts'] + data['generalInserts'] + data['updates'] + data['general']:
        if proc['projection']:
             print(f"""
  rc = register_rowset_tvf(db, call_{proc['canonicalName']}, "{proc['canonicalName']}");
""")
        else:
            print(f"""
  rc = sqlite3_create_function(db, "{proc['canonicalName']}", {len([arg for arg in proc['args'] if arg['binding'] in ['in', 'inout']])}, SQLITE_UTF8, NULL, call_{proc['canonicalName']}, NULL, NULL);
""")  
        print("""
        if (rc != SQLITE_OK) return rc;
        """)

    print("""
  return rc;
}

""")

def emit_all_procs(data, cmd_args):
    for proc in sorted(
        data["queries"] +
        data["deletes"] +
        data["inserts"] +
        data["generalInserts"] +
        data["updates"] +
        data["general"],
        key=lambda proc: proc['canonicalName']
    ):
        if "cql:private" in proc['attributes']: return

        emit_proc_c_func_body(proc, cmd_args)

# This emits the main body of the C Interop function, this includes
# * the Interop entry point for the procedure
# * the call to the procedure
# * the marshalling of the results
# * the return of the results
# * the cleanup of the results
def emit_proc_c_func_body(proc, cmd_args):
    ___, __v, _vv, vvv, indent, dedent = codegen_utils(cmd_args)

    in_arguments = [arg for arg in proc['args'] if arg['binding'] == 'in']
    inout_arguments = [arg for arg in proc['args'] if arg['binding'] == 'inout']
    out_arguments = [arg for arg in proc['args'] if arg['binding'] == 'out']

    innie_arguments = in_arguments + inout_arguments
    outtie_arguments = inout_arguments + out_arguments

    if proc['projection']:
        out_cursor = ", cql_rowset_cursor *result"
    else:
        out_cursor = ""

    ___(f"void call_{proc['canonicalName']}(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv{out_cursor})")
    ___("{")
    indent()

    _vv(f"// 1. Ensure Sqlite function argument count matches count of the procedure in and inout arguments")
    ___(f"if (argc != {len(innie_arguments)}) goto invalid_arguments;")
    ___(f"")


    _vv("// 2. Ensure sqlite3 value type is compatible with cql type")
    for index, arg in enumerate(innie_arguments):
        ___(
            f"if (!is_sqlite3_type_compatible_with_cql_core_type("
                f"sqlite3_value_type(argv[{index}]), "
                f"{cql_row_types[arg['type']]}, "
                f"{'cql_false' if arg['isNotNull'] else 'cql_true'}"
            f")) goto invalid_arguments; // {arg['name']}"
        )
    ___()


    _vv("// 3. Marshalled argument initialization")
    for index, arg in enumerate(innie_arguments):
        ___(f"{cql_types[arg['isNotNull']][arg['type']].ljust(20)} {arg['name'].ljust(25)} = {sqlite3_value_getter[arg['isNotNull']][arg['type']]}(argv[{index}]);")
    for arg in out_arguments:
        ___(f"{cql_types[arg['isNotNull']][arg['type']].ljust(20)} {arg['name'].ljust(25)}", end="")

        if arg['type'] in ("text", "blob", "object"):
            ___(f" = NULL;")
        elif arg['isNotNull']:
            ___(f" = 0;")
        else:
            ___(f" ; cql_set_null({arg['name']});")
    ___()


    _vv(f"// 4. Initialize procedure dependencies")
    if proc['usesDatabase']:
        ___(f"cql_code rc = SQLITE_OK;")
        ___(f"sqlite3* db = sqlite3_context_db_handle(context);")
        ___(f"")
    if proc['projection']:
        ___(f"{proc['name']}_result_set_ref _data_result_set_ = NULL;")
        ___(f"")


    _vv("// 5. Call the procedure")
    ___(f"{'rc = ' if proc['usesDatabase'] else ''}{proc['name']}{'_fetch_results' if proc['projection'] else ''}(", end="")
    for index, computed_arg in enumerate(
        (["db"] if proc['usesDatabase'] else []) +
        (["&_data_result_set_"] if proc['projection'] else []) +
        [
            f"&{arg['name']}" if arg['binding'] != "in"
                else "/* unsupported arg type object*/" if arg['type'] == "object"
                else arg['name']
            for arg in proc['args']
        ]
    ):
        print(f"{',' if index > 0 else ''}\n    {computed_arg}", end="")
    ___()
    ___(");")
    ___()


    _vv("// 6. Cleanup In arguments since they are no longer needed")
    for arg in [arg for arg in in_arguments if is_ref_type[arg['type']]]:
        ___(f"{cql_ref_release[arg['type']]}({arg['name']});")
    ___()


    _vv("// 7. Ensure the procedure executed successfully")
    if proc['usesDatabase']:
        ___("if (rc != SQLITE_OK) {")
        ___("  sqlite3_result_null(context);")
        ___("  goto cleanup;")
        ___("}")
    ___()


    _vv("// 8. Resolve the result base on:")
    vvv("//   (A) The first column of first row of the result_set, if any")
    vvv("//   (B) The first outtie argument (in or inout) value, if any")
    vvv("//   (C) Fallback to: null")
    vvv("//")
    if proc['projection']:
        vvv("// Current strategy: (A) Using the result set")

        ___("result->result_set = (cql_result_set_ref)_data_result_set_;")
        ___("goto cleanup;")
        ___()
    else:
        vvv("// Current strategy: (B) Using Outtie arguments")
        vvv("// Set Sqlite result")
        vvv("// NB: If the procedure generates a cql result set, the first column of the first row would be used as the result")
        for arg in [arg for arg in proc['args'] if arg['binding'] in ("inout", "out")]:
            skip = False

            if is_ref_type[arg['type']]:
                if arg['type'] == "object":
                    __v(f"/* {arg['type']} not implemented yet */")
                    skip = True
                else:
                    ___(f"{sqlite3_result_setter[IS_NULLABLE][arg['type']]}(context, {arg['name']}); goto cleanup;")
            else:
                ___(f"{sqlite3_result_setter[arg['isNotNull']][arg['type']]}(context, {arg['name']}); goto cleanup;")

            if not skip: break
        ___()
        ___("goto cleanup;")
        ___()


    ___("invalid_arguments:")
    ___("sqlite3_result_error(context, \"CQL extension: Invalid procedure arguments\", -1);")
    ___("return;")
    ___()

    ___("cleanup:")
    _vv("// 10. Cleanup Outtie arguments")
    for arg in [arg for arg in outtie_arguments if is_ref_type[arg['type']]]:
        ___(f"if({arg['name']}) {cql_ref_release[arg['type']]}({arg['name']});")
    __v("/* Avoid empty block warning */ ;")

    dedent()
    ___("}")
    ___()

def normalize_json_output(data, cmd_args):
    for proc in (
        data["queries"] +
        data["deletes"] +
        data["inserts"] +
        data["generalInserts"] +
        data["updates"] +
        data["general"]
    ):
        proc['usesDatabase'] = proc.get("usesDatabase", True)
        proc['projection'] = "projection" in proc
        proc['canonicalName'] = cmd_args['namespace'] + proc['name']
        proc['attributes'] = {attr['name']: attr['value'] for attr in proc.get("attributes", [])}
        for arg in proc['args']:
            arg['binding'] = arg.get('binding', 'in')

    return data

def main():
    cmd_args = {
        "cql_header": "cqlrt.h",
        "namespace": "",
        "verbosity": "very_verbose"
    }

    jfile = sys.argv[1]

    i = 2
    while i + 2 <= len(sys.argv):
        if sys.argv[i] == "--cql_header":
            cmd_args["cql_header"] = sys.argv[i + 1]
        elif sys.argv[i] == "--namespace":
            cmd_args["namespace"] = sys.argv[i + 1] + '_'
        elif sys.argv[i] == "--verbosity":
            cmd_args["verbosity"] = sys.argv[i + 1]
        else:
            usage()
        i += 2

    with open(jfile) as json_file:
        data = normalize_json_output(json.load(json_file), cmd_args)

        emit_original_licence()
        emit_headers(cmd_args)
        emit_all_procs(data, cmd_args)
        emit_extension_initializer(data, cmd_args)

if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
