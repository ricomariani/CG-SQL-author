#!/usr/bin/env python3

# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

#############################################################################
# cqlsqlite3extension.py - CQL JSON to SQLite Extension Code Generator
#############################################################################
#
# PURPOSE:
# This script reads the JSON schema output from CQL (produced via --rt json)
# and generates C code that exposes CQL procedures as SQLite functions or
# table-valued functions (TVFs). This allows CQL stored procedures to be
# called directly from SQL queries within SQLite.
#
# HOW IT WORKS:
# 1. Parses CQL JSON output containing procedure definitions, arguments,
#    projections (result columns), and attributes
# 2. For each non-private procedure, generates a C wrapper function that:
#    - Validates argument count and types
#    - Marshals SQLite values to CQL types
#    - Calls the underlying CQL procedure
#    - Marshals results back to SQLite
# 3. Generates an extension initializer that registers all functions with SQLite
#
# RESULT TYPES:
# - Procedures with projections become table-valued functions (TVFs)
# - Procedures with OUT parameters return the first OUT value as a scalar
# - Void procedures return NULL
#
# The CQL JSON format is documented here: https://cgsql.dev/cql-guide/ch13
# and here: https://cgsql.dev/json-diagram
#
# NB: This code should be considered SAMPLE code, not production code.
# Feel free to fork it and modify it to suit your needs.
#############################################################################

import json
import sys

# Function to display usage instructions for the script
def usage():
    print(
        """
Usage: input.json [options] >result.c

--cql_header header_file
    specifies the CQL generated header file to include in the generated C code
"""
    )
    sys.exit(0)

#############################################################################
# TYPE MAPPING TABLES
#############################################################################
# These dictionaries map between CQL's type system and SQLite/C types.
# CQL has its own type names (bool, integer, long, real, text, blob, object)
# that need to be translated for:
# - C type declarations (cql_int32, cql_string_ref, etc.)
# - SQLite type constants (CQL_DATA_TYPE_INT32, etc.)
# - Nullable vs not-null variants (cql_nullable_int32 vs cql_int32)
#############################################################################

# Constants for nullability - used as dictionary keys for type lookups
# This allows type mappings to be indexed by nullability status
IS_NOT_NULL = 1
IS_NULLABLE = 0

# Reference types require special memory management (retain/release).
# Value types (bool, integer, long, real) are passed by value.
# Reference types (text, blob, object) are passed by pointer and must be
# explicitly released after use to avoid memory leaks.
is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True

# CQL data type constants used for runtime type validation.
# These constants are checked against sqlite3_value_type() results
# to ensure the SQLite value can be safely converted to the expected CQL type.
cql_row_types = {}
cql_row_types["bool"] = "CQL_DATA_TYPE_BOOL"
cql_row_types["integer"] = "CQL_DATA_TYPE_INT32"
cql_row_types["long"] = "CQL_DATA_TYPE_INT64"
cql_row_types["real"] = "CQL_DATA_TYPE_DOUBLE"
cql_row_types["object"] = "CQL_DATA_TYPE_OBJECT"
cql_row_types["blob"] = "CQL_DATA_TYPE_BLOB"
cql_row_types["text"] = "CQL_DATA_TYPE_STRING"

# Release functions for reference types. These must be called after the
# reference is no longer needed to properly manage memory. Each reference
# type has its own release function in the CQL runtime.
cql_ref_release = {}
cql_ref_release["text"] = "cql_string_release"
cql_ref_release["blob"] = "cql_blob_release"
cql_ref_release["object"] = "cql_object_release"

# C type names for variable declarations. Nullable value types use special
# struct wrappers (e.g., cql_nullable_int32) that include an is_null flag.
# Reference types are always nullable by nature (NULL pointer = SQL NULL),
# so they use the same type regardless of the isNotNull flag.
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
cql_types[IS_NULLABLE]["object"] = "cql_object_ref"  # ref types always nullable via NULL pointer
cql_types[IS_NULLABLE]["blob"] = "cql_blob_ref"
cql_types[IS_NULLABLE]["text"] = "cql_string_ref"

# Functions to extract values from sqlite3_value* (SQLite's variant type).
# These helper functions (defined in cql_sqlite_extension.h) convert from
# SQLite's internal representation to CQL types. The "not_null" variants
# assume the value is never NULL and return a plain value. The "nullable"
# variants return a nullable struct that may contain is_null=true.
# Reference types (text, blob, object) use the same getter regardless of
# nullability since they naturally represent NULL via a NULL pointer.
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

# Functions to set the SQLite function result. These are called to return
# the procedure's output to SQLite. For not-null value types, we use the
# standard sqlite3_result_* functions. For nullable types and reference
# types, we use CQL helper functions (sqlite3_result_cql_*) that properly
# handle NULL values and memory management (e.g., setting SQLITE_TRANSIENT
# for text/blob so SQLite makes its own copy before we release the ref).
sqlite3_result_setter = {IS_NULLABLE: {}, IS_NOT_NULL: {}}
sqlite3_result_setter[IS_NOT_NULL]["bool"] = "sqlite3_result_int"       # bool stored as int in SQLite
sqlite3_result_setter[IS_NOT_NULL]["integer"] = "sqlite3_result_int"
sqlite3_result_setter[IS_NOT_NULL]["long"] = "sqlite3_result_int64"
sqlite3_result_setter[IS_NOT_NULL]["real"] = "sqlite3_result_double"
sqlite3_result_setter[IS_NOT_NULL]["object"] = "sqlite3_result_pointer"  # opaque pointer passthrough
sqlite3_result_setter[IS_NOT_NULL]["blob"] = "sqlite3_result_blob"
sqlite3_result_setter[IS_NOT_NULL]["text"] = "sqlite3_result_text"
sqlite3_result_setter[IS_NULLABLE]["bool"] = "sqlite3_result_cql_nullable_bool"    # checks is_null flag
sqlite3_result_setter[IS_NULLABLE]["integer"] = "sqlite3_result_cql_nullable_int"
sqlite3_result_setter[IS_NULLABLE]["long"] = "sqlite3_result_cql_nullable_int64"
sqlite3_result_setter[IS_NULLABLE]["real"] = "sqlite3_result_cql_nullable_double"
sqlite3_result_setter[IS_NULLABLE]["object"] = "sqlite3_result_cql_pointer"  # handles NULL pointer
sqlite3_result_setter[IS_NULLABLE]["blob"] = "sqlite3_result_cql_blob"       # handles NULL ref
sqlite3_result_setter[IS_NULLABLE]["text"] = "sqlite3_result_cql_text"       # handles NULL ref

#############################################################################
# CODE GENERATION UTILITIES
#############################################################################
# These utilities help generate properly indented C code and control the
# verbosity of comments in the output. The indentation is tracked globally
# so that nested blocks are properly formatted.
#############################################################################

# Global state for tracking current indentation level and whether we're
# in the middle of a line (pending_line=True means we used end="" on
# the previous print, so we shouldn't add indentation on the next print).
indentation_state = {'value': 0, 'pending_line': False}

def codegen_utils(cmd_args):
    """
    Returns a set of helper functions for generating indented code with
    verbosity control. The functions returned are:

    - code (___): Always prints, used for actual C code
    - v (__v): Prints at verbosity >= 1 (normal+), for basic comments
    - vv (_vv): Prints at verbosity >= 2 (verbose+), for detailed comments
    - vvv (vvv): Prints at verbosity >= 3 (very_verbose+), for debug comments
    - indent: Increases indentation level
    - dedent: Decreases indentation level

    Usage pattern in emit_proc_c_func_body:
        ___, __v, _vv, vvv, indent, dedent = codegen_utils(cmd_args)
        ___("{")
        indent()
        _vv("// Comment only shown in verbose mode")
        ___("int x = 0;")  # Always shown
        dedent()
        ___("}")
    """
    verbosity = {
        'quiet': 0,
        'normal': 1,
        'verbose': 2,
        'very_verbose': 3,
        'debug': 4
    }.get(cmd_args.get('verbosity', 'normal'), 3)

    def indent(indentation=1):
        """Increase indentation by the specified number of levels."""
        if not indentation_state['pending_line']:
            indentation_state["value"] += indentation

    def dedent(indentation=1):
        """Decrease indentation by the specified number of levels."""
        if not indentation_state['pending_line']:
            indentation_state["value"] = max(0, indentation_state["value"] - indentation)

    def indetented_print(*args, **kwargs):
        """Print with current indentation level. Handles multi-line strings."""
        text = kwargs.get("sep", " ").join(map(str, args))
        lines = text.split("\n")

        for i, line in enumerate(lines):
            if i > 0 or not indentation_state['pending_line']:
                print("  " * indentation_state['value'], end="")
            print(line, end="" if i < len(lines) - 1 else kwargs.get("end", "\n"))

        # Track if we're mid-line (used end="" without newline in text)
        indentation_state['pending_line'] = kwargs.get("end", "\n") != "\n" and not text.endswith("\n")

    noop = lambda *args, **kwargs: None
    code = lambda *args, **kwargs: indetented_print(*args, **kwargs)
    v = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 1 else noop(*args, **kwargs)
    vv = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 2 else noop(*args, **kwargs)
    vvv = lambda *args, **kwargs: indetented_print(*args, **kwargs) if verbosity >= 3 else noop(*args, **kwargs)

    return code, v, vv, vvv, indent, dedent

def emit_headers(cmd_args, json_file):
    """
    Emit the C file header with required #includes.

    The generated code can be compiled in two modes:
    1. As a loadable SQLite extension (CQL_SQLITE_EXT defined):
       - Uses sqlite3ext.h for extension APIs
       - SQLITE_EXTENSION_INIT1 declares the sqlite3_api pointer
    2. Linked directly into an application:
       - Uses standard sqlite3.h (via cqlrt.h)

    Required headers:
    - cqlrt.h: CQL runtime types and functions
    - cql_sqlite_extension.h: Helper functions for value marshalling
    - The CQL-generated header: Procedure declarations and result set types
    """
    print(f"// Generated by cqlsqlite3extension.py from {json_file.name}")
    print(f"")
    print(f"#ifdef CQL_SQLITE_EXT")
    print(f"#include <sqlite3ext.h>")  # Extension API with indirect function pointers
    print(f"SQLITE_EXTENSION_INIT1")   # Macro that declares sqlite3_api pointer
    print(f"#endif")
    print(f"#include \"cqlrt.h\"")  # CQL runtime: types, memory management
    print(f"#include \"cql_sqlite_extension.h\"")  # Value marshalling helpers
    print(f"#include \"{cmd_args['cql_header']}\"")  # CQL-generated declarations
    print(f"")

def emit_extension_initializer(data, cmd_args):
    """
    Emit the SQLite extension entry point function.

    This function is called by SQLite when the extension is loaded. It must:
    1. Initialize the extension API (for loadable extensions)
    2. Register each CQL procedure as either:
       - A scalar function (sqlite3_create_function) for procedures without projections
       - A table-valued function (register_cql_rowset_tvf) for procedures with projections

    The function name follows SQLite's naming convention:
    sqlite3_<extension_name>_init

    For TVFs, we generate a CREATE TABLE declaration that describes the virtual
    table schema. This includes the projection columns (visible) and the input
    arguments as hidden columns (used for parameter passing).
    """
    print("""
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi) {
#ifdef CQL_SQLITE_EXT
  SQLITE_EXTENSION_INIT2(pApi);  // Initialize extension API function pointers
#endif

  int rc = SQLITE_OK;
  cql_rowset_aux_init *aux = NULL;""")

    # Register each non-private procedure
    for proc in data['queries'] + data['deletes'] + data['inserts'] + data['generalInserts'] + data['updates'] + data['general']:
        if "cql:private" in proc['attributes']:
            # Private procedures are internal helpers, not exposed to SQL
            continue

        proc_name = proc['canonicalName']
        has_projection = 'projection' in proc

        if has_projection:
            # TABLE-VALUED FUNCTION REGISTRATION
            # TVFs return a result set that appears as a virtual table.
            # The schema declaration includes:
            # - Projection columns: the actual result columns, visible in queries
            # - Hidden columns: input arguments, accessed via special syntax
            #
            # Example: SELECT * FROM my_proc(arg1, arg2) WHERE col1 > 5
            args = [{'name': f"arg_{a['name']}", 'type': f"{a['type']} hidden"} for a in proc['args']]
            col = [{'name': p['name'], 'type' : p['type'] } for p in proc['projection']]
            cols = ", ".join(f"[{p['name']}] {p['type']}" for p in (col + args))
            table_decl = f"CREATE TABLE {proc_name}({cols})"
            print(f"""
  aux = cql_rowset_create_aux_init(call_{proc_name}, "{table_decl}");
  rc = register_cql_rowset_tvf(db, aux, "{proc_name}");
""")
        else:
            # SCALAR FUNCTION REGISTRATION
            # Scalar functions return a single value and are called like:
            # SELECT my_func(arg1, arg2)
            # The nArg parameter specifies how many arguments the function takes
            # (only counting IN and INOUT, not pure OUT parameters)
            in_arg_count = len([arg for arg in proc['args'] if arg['binding'] in ['in', 'inout']])
            print(f"""
  rc = sqlite3_create_function(db, "{proc_name}", {in_arg_count}, SQLITE_UTF8, NULL, call_{proc_name}, NULL, NULL);
""")
        print("  if (rc != SQLITE_OK) return rc;")

    print("")
    print("  return rc;")
    print("}")

def emit_all_procs(data, cmd_args):
    """
    Emit C wrapper functions for all eligible procedures.

    Iterates through all procedure categories in the CQL JSON output:
    - queries: SELECT statements that return result sets
    - deletes: DELETE statements
    - inserts: Simple INSERT statements
    - generalInserts: Complex INSERT statements (INSERT...SELECT, etc.)
    - updates: UPDATE statements
    - general: Other procedures (CALL, compound statements, etc.)

    Procedures are sorted alphabetically for consistent output.

    Suppressed procedures are skipped because they cannot be safely called
    from SQL or don't have the necessary runtime support.
    """
    for proc in sorted(
        data["queries"] +
        data["deletes"] +
        data["inserts"] +
        data["generalInserts"] +
        data["updates"] +
        data["general"],
        key=lambda proc: proc['canonicalName']
    ):
        # Check for attributes that suppress public API generation:
        # - cql:private: Internal procedure, not meant for external use
        # - cql:suppress_result_set: No result set accessors generated
        # - cql:suppress_getters: No column getter functions generated
        # Any of these means we can't properly marshal results to SQLite.
        attributes = proc['attributes']
        suppressed = ("cql:suppress_result_set" in attributes
                      or "cql:private" in attributes
                      or "cql:suppress_getters" in attributes)

        if not suppressed:
            emit_proc_c_func_body(proc, cmd_args)

def emit_proc_c_func_body(proc, cmd_args):
    """
    Emit the C wrapper function for a single CQL procedure.

    This is the core of the code generator. It creates a C function that:
    1. Validates that the correct number of arguments were passed
    2. Validates that each argument's SQLite type is compatible with the CQL type
    3. Marshals SQLite values (sqlite3_value*) to CQL types
    4. Calls the underlying CQL procedure
    5. Cleans up IN argument references (they're no longer needed after the call)
    6. Checks if the procedure succeeded (for database procedures)
    7. Marshals the result back to SQLite:
       - For projections: returns the result set for TVF consumption
       - For OUT params: returns the first OUT value as a scalar
       - For void procs: returns NULL
    8. Cleans up OUT argument references

    The generated function signature differs based on whether the procedure
    has a projection (TVF) or not (scalar function).
    """
    ___, __v, _vv, vvv, indent, dedent = codegen_utils(cmd_args)

    # Categorize arguments by their binding direction:
    # - IN: passed from SQLite to CQL, read-only
    # - OUT: returned from CQL to SQLite, write-only
    # - INOUT: both passed in and returned
    #
    # "innie" = appears in SQLite function call (IN, INOUT)
    # "outtie" = contains result after proc call (OUT, INOUT)
    innie_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'in' or arg['binding'] == 'inout')]
    outtie_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'out' or arg['binding'] == 'inout')]

    # Pure subsets for specific operations (cleanup, initialization)
    out_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'out')]
    in_arguments = [arg for arg in proc['args'] if (arg['binding'] == 'in')]

    # Find the first usable OUT/INOUT argument to return as the scalar result.
    # For procedures without projections, we return the first OUT value.
    # Object types are skipped because they can't be directly returned to SQLite
    # (they're opaque pointers with no standard serialization).
    first_outtie = None
    for arg in outtie_arguments:
        skip = False

        if is_ref_type[arg['type']]:
            if arg['type'] == "object":
                # Objects are opaque - can't return them as SQLite values
                __v(f"/* {arg['type']} not implemented yet, skipping outtie arg {arg['name']} */")
                skip = True

        if not skip:
            first_outtie = arg
            break

    proc_name = proc['canonicalName']
    has_projection = 'projection' in proc  # True = TVF, False = scalar function

    # Build SQL-like signature comment for documentation in generated code
    sql_in_args = ', '.join(f"`{a['name']}` {a['type']}{'!' if a['isNotNull'] else ''}" for a in innie_arguments)

    if has_projection:
        # if it has a projection we need to list all the projection columns
        sql_result =  ', '.join(f"`{p['name']}` {p['type']}{'!' if p['isNotNull'] else ''}" for p in proc['projection'])
        sql_result = "(" + sql_result + ")"
    elif first_outtie:
        # function returns first outtie argument
        sql_result = f"{first_outtie['type']}{'!' if first_outtie['isNotNull'] else ''}"
    else:
        # function must return something but it's a void proc, so it will return null in a nullable int
        sql_result = "/*void*/ int"

    # this comment can be used as the signature to declare the UDF/TVF we are making function in CQL
    ___(f"// SELECT FUNC {proc_name}({sql_in_args}) {sql_result};")


    # at this point we have all the information to make the function signature
    # for either a scalar function or a table valued function, we need the C
    # signature for a SQLite UDF or TVF

    if has_projection:
        # this will be a TVF so we need to return the result set
        ___(f"void call_{proc_name}(sqlite3 *_Nonnull db, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv, cql_result_set_ref *result)")
    else:
        # this will be a scalar function so we need to return the result via the context
        ___(f"void call_{proc_name}(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv)")
    ___("{")

    indent()

    # each section below is documented by the numbered output step

    if has_projection:
        _vv(f"// 0. Ensure output result set is cleared in case of early out")
        ___(f"*result = NULL;")
        ___(f"")

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
        # declare and initialize in and inout arguments using the right value getter
        ___(f"{cql_types[arg['isNotNull']][arg['type']].ljust(20)} {arg['name'].ljust(25)} = {sqlite3_value_getter[arg['isNotNull']][arg['type']]}(argv[{index}]);")

    for arg in out_arguments:
        ___(f"{cql_types[arg['isNotNull']][arg['type']].ljust(20)} {arg['name'].ljust(25)}", end="")

        # initialize out args to null/zero as appropriate

        if arg['type'] in ("text", "blob", "object"):
            ___(f" = NULL;")
        elif arg['isNotNull']:
            ___(f" = 0;")
        else:
            ___(f" ; cql_set_null({arg['name']});")
    ___()


    # note that TVF functions (i.e. with projection) always get the database via
    # the module interface even if they don't need it and they don't get the
    # context arg, so we have to create the right setup in both cases.

    _vv(f"// 4. Initialize procedure dependencies")
    if proc['usesDatabase']:
        ___(f"cql_code rc = SQLITE_OK;")
        if not has_projection:
            ___(f"sqlite3* db = sqlite3_context_db_handle(context);")
        ___(f"")

    # clear result set if needed

    if has_projection:
        ___(f"{proc['name']}_result_set_ref _data_result_set_ = NULL;")
        ___(f"")


    # here we decode the args and call the native procedure, we have to be
    # mindful of stuff like whether or not there is a db parameter, and whether
    # or not there is a result set to capture.

    _vv("// 5. Call the procedure")
    ___(f"{'rc = ' if proc['usesDatabase'] else ''}{proc['name']}{'_fetch_results' if has_projection else ''}(", end="")
    for index, computed_arg in enumerate(
        (["db"] if proc['usesDatabase'] else []) +
        (["&_data_result_set_"] if has_projection else []) +
        [
            # args passed by reference for out and inout, by value for in
            # arg variables already declared above
            f"&{arg['name']}" if arg['binding'] != "in"
                else "/* unsupported arg type object*/" if arg['type'] == "object"
                else arg['name']
            for arg in proc['args']
        ]
    ):
        # comma separate args based on the list generated above
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
        if not has_projection:
            ___("  sqlite3_result_null(context);")
        ___("  goto cleanup;")
        ___("}")
    ___()

    _vv("// 8. Resolve the result based on:")
    vvv("//   (A) The rows of the result_set, if any")
    vvv("//   (B) The first outtie argument (out or inout) value, if any")
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
    if not has_projection:
        ___("sqlite3_result_error(context, \"CQL extension: Invalid procedure arguments\", -1);")
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
    """
    Normalize the CQL JSON schema for easier processing.

    The CQL JSON output has some optional fields and uses arrays for
    attributes. This function:

    1. Sets defaults for optional fields:
       - usesDatabase: defaults to True (most procs need db)
       - binding: defaults to 'in' (most args are input-only)

    2. Applies namespace prefix to procedure names:
       - If --namespace foo is specified, "myproc" becomes "foo_myproc"
       - This allows multiple CQL modules in one extension

    3. Converts attributes from array to dict for O(1) lookup:
       - From: [{"name": "cql:private", "value": 1}, ...]
       - To: {"cql:private": 1, ...}

    This normalization simplifies the code generation logic.
    """
    for proc in (
        data["queries"] +
        data["deletes"] +
        data["inserts"] +
        data["generalInserts"] +
        data["updates"] +
        data["general"]
    ):
        # Default: assume procedure uses the database (safe assumption)
        proc['usesDatabase'] = proc.get("usesDatabase", True)

        # Apply namespace prefix for multi-module extensions
        proc['canonicalName'] = cmd_args['namespace'] + proc['name']

        # Convert attributes array to dict for fast lookups
        proc['attributes'] = {attr['name']: attr['value'] for attr in proc.get("attributes", [])}
        for arg in proc['args']:
            # Default binding is 'in' (input parameter)
            arg['binding'] = arg.get('binding', 'in')

    return data

def main():
    """
    Main entry point: parse arguments, load JSON, and generate C code.

    Command line usage:
        python cqlsqlite3extension.py input.json [options] > output.c

    Options:
        --cql_header <file>  Header file with CQL declarations (default: cqlrt.h)
        --namespace <name>   Prefix for all function names (e.g., "mymod" -> "mymod_func")
        --verbosity <level>  Comment verbosity: quiet, normal, verbose, very_verbose, debug

    The generated C code is written to stdout; redirect to a file as needed.

    Generation order:
    1. Headers (#includes)
    2. Wrapper functions for each procedure (sorted alphabetically)
    3. Extension initializer (registers all functions with SQLite)
    """
    # Default configuration
    cmd_args = {
        "cql_header": "cqlrt.h",   # CQL-generated header to include
        "namespace": "",            # Prefix for function names (empty = no prefix)
        "verbosity": "very_verbose" # Default to detailed comments
    }

    # First positional arg is the input JSON file
    jfile = sys.argv[1]

    # Parse optional arguments (--key value pairs)
    i = 2
    while i + 2 <= len(sys.argv):
        if sys.argv[i] == "--cql_header":
            cmd_args["cql_header"] = sys.argv[i + 1]
        elif sys.argv[i] == "--namespace":
            # Add underscore separator: "foo" -> "foo_"
            cmd_args["namespace"] = sys.argv[i + 1] + '_'
        elif sys.argv[i] == "--verbosity":
            cmd_args["verbosity"] = sys.argv[i + 1]
        else:
            usage()
        i += 2

    # Load and process the CQL JSON schema
    with open(jfile) as json_file:
        data = normalize_json_output(json.load(json_file), cmd_args)


        # Generate the C source file in order:
        emit_headers(cmd_args, json_file)          # #includes and macros
        emit_all_procs(data, cmd_args)             # Wrapper functions
        emit_extension_initializer(data, cmd_args) # sqlite3_cqlextension_init()

if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
