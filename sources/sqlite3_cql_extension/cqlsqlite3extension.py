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
    print(f"#ifndef NO_SQLITE_EXT")
    print(f"#include <sqlite3ext.h>")
    print(f"SQLITE_EXTENSION_INIT1")
    print(f"#endif")
    print(f"#include \"cqlrt.h\"")
    print(f"#include \"cql_sqlite_extension.h\"")
    print(f"#include \"{cmd_args['cql_header']}\"")
    print(f"")

def emit_extension_initializer(data, cmd_args):

    print("""
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi) {
#ifndef NO_SQLITE_EXT
  SQLITE_EXTENSION_INIT2(pApi);
#endif

  int rc = SQLITE_OK;
  cql_rowset_aux_init *aux = NULL;""")
    for proc in data['queries'] + data['deletes'] + data['inserts'] + data['generalInserts'] + data['updates'] + data['general']:
        proc_name = proc['canonicalName']
        has_projection = 'projection' in proc

        if has_projection:
            # Create a new array with the required changes
            args = [{'name': f"arg_{a['name']}", 'type': f"{a['type']} hidden"} for a in proc['args']]
            col = [{'name': p['name'], 'type' : p['type'] } for p in proc['projection']]
            cols = ", ".join(f"{p['name']} {p['type']}" for p in (col + args))
            table_decl = f"CREATE TABLE {proc_name}({cols})"
            print(f"""
  aux = cql_rowset_create_aux_init(call_{proc_name}, "{table_decl}");
  rc = register_cql_rowset_tvf(db, aux, "{proc_name}");
""")
        else:
            print(f"""
  rc = sqlite3_create_function(db, "{proc_name}", {len([arg for arg in proc['args'] if arg['binding'] in ['in', 'inout']])}, SQLITE_UTF8, NULL, call_{proc_name}, NULL, NULL);
""")
        print("  if (rc != SQLITE_OK) return rc;")

    print("")
    print("  return rc;")
    print("}")

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

    # select in style arguments preserving order of original arguments, i.e. only skip pure out
    innie_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'in' or arg['binding'] == 'inout')]

    # again preserve original order, skip only 'in' arguments
    outtie_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'out' or arg['binding'] == 'inout')]

    out_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'out')]
    in_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'in')]

    first_outtie = None
    for arg in outtie_arguments:
        skip = False

        if is_ref_type[arg['type']]:
            if arg['type'] == "object":
                __v(f"/* {arg['type']} not implemented yet, skipping outtie arg {arg['name']} */")
                skip = True

        if not skip:
            first_outtie = arg
            break

    proc_name = proc['canonicalName']
    has_projection = 'projection' in proc

    sql_in_args = ', '.join(f"{a['name']} {a['type']}{'!' if a['isNotNull'] else ''}" for a in innie_arguments)

    if has_projection:
        sql_result =  ', '.join(f"{p['name']} {p['type']}{'!' if p['isNotNull'] else ''}" for p in proc['projection'])
        sql_result = "(" + sql_result + ")"
    elif first_outtie:
        sql_result = f"{first_outtie['type']}{'!' if first_outtie['isNotNull'] else ''}"
    else:
        # function must return something but it's a void proc, so it will return null in a nullable int
        sql_result = "/*void*/ int"

    ___(f"// DECLARE SELECT FUNCTION {proc_name}({sql_in_args}) {sql_result};")

    if has_projection:
        ___(f"void call_{proc_name}(sqlite3 *_Nonnull db, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv, cql_result_set_ref *result)")
    else:
        ___(f"void call_{proc_name}(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv)")
    ___("{")

    indent()

    if has_projection:
        _vv(f"// Ensure output result set is cleared in case of early out")
        ___(f"*result = NULL;")
        ___(f"")

    _vv(f"// 1. Ensure Sqlite function argument count matches count of the proc_namedure in and inout arguments")
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


    # note that project procs always get the database via the module interface even if they don't need it
    # and they don't get the context arg
    _vv(f"// 4. Initialize proc_namedure dependencies")
    if proc['usesDatabase']:
        ___(f"cql_code rc = SQLITE_OK;")
        if 'projection' not in proc:
            ___(f"sqlite3* db = sqlite3_context_db_handle(context);")
        ___(f"")

    if has_projection:
        ___(f"{proc['name']}_result_set_ref _data_result_set_ = NULL;")
        ___(f"")


    _vv("// 5. Call the proc_namedure")
    ___(f"{'rc = ' if proc['usesDatabase'] else ''}{proc['name']}{'_fetch_results' if has_projection else ''}(", end="")
    for index, computed_arg in enumerate(
        (["db"] if proc['usesDatabase'] else []) +
        (["&_data_result_set_"] if has_projection else []) +
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


    _vv("// 7. Ensure the proc_namedure executed successfully")
    if proc['usesDatabase']:
        ___("if (rc != SQLITE_OK) {")
        if 'projection' not in proc:
            ___("  sqlite3_result_null(context);")
        ___("  goto cleanup;")
        ___("}")
    ___()

    _vv("// 8. Resolve the result base on:")
    vvv("//   (A) The rows of the result_set, if any")
    vvv("//   (B) The first outtie argument (in or inout) value, if any")
    vvv("//   (C) Fallback to: null")
    vvv("//")
    if has_projection:
        vvv("// Current strategy: (A) Table valued function that exposes the result set")

        ___("*result = (cql_result_set_ref)_data_result_set_;")
        ___("goto cleanup;")
        ___()
    else:
        if first_outtie:
            vvv("// Current strategy: (B) Using Outtie arguments")
            vvv("// Set Sqlite result")
            arg = first_outtie
            if is_ref_type[arg['type']]:
                ___(f"{sqlite3_result_setter[IS_NULLABLE][arg['type']]}(context, {arg['name']});")
            else:
                ___(f"{sqlite3_result_setter[arg['isNotNull']][arg['type']]}(context, {arg['name']});")
        else:
            vvv("// Current strategy: (C) Fallback to null")
            ___("sqlite3_result_null(context);")

        ___("goto cleanup;")
        ___()

    ___("invalid_arguments:")
    if 'projection' not in proc:
        ___("sqlite3_result_error(context, \"CQL extension: Invalid proc_namedure arguments\", -1);")
    ___("return;")
    ___()

    ___("cleanup:")
    _vv("// 10. Cleanup Outtie arguments")
    for arg in [arg for arg in outtie_arguments if is_ref_type[arg['type']]]:
        ___(f"if ({arg['name']}) {cql_ref_release[arg['type']]}({arg['name']});")
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
