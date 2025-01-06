#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# cqlcs.py -> converts CQL JSON format into C# classes for interop
#
# The CQL JSON format is documented here:
#   https://cgsql.dev/cql-guide/ch13
# and here:
#   https://cgsql.dev/json-diagram
#
# NB: This code should be considered SAMPLE code, not production code.
# Which is to say you can reasonably expect that the specifics of the diagrams
# and the database produced here are likely to change at whim.  If you need
# a particular output, you are enouraged to FORK this sample into something
# stable.  The JSON format itself is the contract and it evolves in a backwards
# compatible way.  This script is likely to change to make different pretty
# pictures at various times.
#
# This approach is just one way to generate C#, there are other ways you can
# create wrapper classes;  The nested class approach with one class per
# procedure works but it isn't the best for everyone.  The naming conventions
# used here are the simplest with the least transform from the original CQL
# but you could reasonably want to camelCase or PascalCase names as needed
# to create something cleaner looking.  All these things are possible with
# not much python at all.  It's also possible to create the Interop code to
# invoke the procedures but this sample has not done so at this time.

import json
import sys


def usage():
    print(
        "Usage: input.json [options] >result.cs or >result.c\n"
        "\n"
        "--emit_c\n"
        "    activates the  C code pass, run the tool once with this flag once without\n"
        "--class outer_class_name\n"
        "   specifies the output class name for the wrapping C# class\n"
        "--cql_header header_file\n"
        "    specifies the CQL generated header file to include in the generated C code\n"
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

# C# types for not null cql types
notnull_types = {}
notnull_types["bool"] = "bool"
notnull_types["integer"] = "int"
notnull_types["long"] = "long"
notnull_types["real"] = "double"
notnull_types["object"] = "object"
notnull_types["blob"] = "byte[]"
notnull_types["text"] = "string"

# C# types for nullable cql types
nullable_types = {}
nullable_types["bool"] = "bool?"
nullable_types["integer"] = "int?"
nullable_types["long"] = "long?"
nullable_types["real"] = "double?"
nullable_types["object"] = "object?"
nullable_types["blob"] = "byte[]?"
nullable_types["text"] = "string?"

split_types = {}
split_types["bool"] = True
split_types["integer"] = True
split_types["long"] = True
split_types["real"] = True
split_types["object"] = False
split_types["blob"] = False
split_types["text"] = False

# Interop types for not null cql types
dotnet_notnull_types = {}
dotnet_notnull_types["bool"] = "cql_bool"
dotnet_notnull_types["integer"] = "cql_int32"
dotnet_notnull_types["long"] = "cql_int64"
dotnet_notnull_types["real"] = "cql_double"
dotnet_notnull_types["object"] = "void*"
dotnet_notnull_types["blob"] = "const void *"
dotnet_notnull_types["text"] = "const char *"

# Interop types for nullable cql types
dotnet_nullable_types = {}
dotnet_nullable_types["bool"] = "split"
dotnet_nullable_types["integer"] = "split"
dotnet_nullable_types["long"] = "split"
dotnet_nullable_types["real"] = "split"
dotnet_nullable_types["object"] = "void *"
dotnet_nullable_types["blob"] = "const void *"
dotnet_nullable_types["text"] = "const char *"

# Getter name fragments
getters = {}
getters["bool"] = "Boolean"
getters["integer"] = "Integer"
getters["long"] = "Long"
getters["real"] = "Double"
getters["object"] = "ChildResultSet"
getters["blob"] = "Blob"
getters["text"] = "String"

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
c_notnull_types = {}
c_notnull_types["bool"] = "cql_bool"
c_notnull_types["integer"] = "cql_int32"
c_notnull_types["long"] = "cql_int64"
c_notnull_types["real"] = "cql_double"
c_notnull_types["object"] = "cql_object_ref"
c_notnull_types["blob"] = "cql_blob_ref"
c_notnull_types["text"] = "cql_string_ref"

# Nullable CQL C types for the given type of fields
c_nullable_types = {}
c_nullable_types["bool"] = "cql_nullable_bool"
c_nullable_types["integer"] = "cql_nullable_int32"
c_nullable_types["long"] = "cql_nullable_int64"
c_nullable_types["real"] = "cql_nullable_double"
c_nullable_types["object"] = "cql_object_ref"
c_nullable_types["blob"] = "cql_blob_ref"
c_nullable_types["text"] = "cql_string_ref"

# Storage for the various command line arguments
cmd_args = {}
cmd_args["emit_c"] = False
cmd_args["package_name"] = "default_package"
cmd_args["class_name"] = "default_class"
cmd_args["dotnet_header"] = "something_something.h"
cmd_args["cql_header"] = "something.h"


# The first thing we do is go through the arguments and build up the
# metadata for the return type.  This is a list of CQL_DATA_TYPE_XXX values
# that describe the type of each field in the return type. We also build up
# the struct definition for the return type. This is a struct with one field
# for each argument.  The fields are named the same as the arguments and
# have the appropriate type. Note that in the structure the reference types
# must go LAST we do this so that we can easily release the references in
# the cleanup code.  We only need the offset to the first reference and the
# count. This pass is looking for anything that is going to be an out or
# inout parameter. Those are the ones that participate in the return type.
# Additionally the result type includes a field for the result code if the
# procedure uses the database. As well as a field for the result set if the
# procedure has a "projection" -- that is if it returns a result set. out
# arguments can themselves by complex but for now in and out "object"
# arguments are not supported.  The exception being the result set which is
# an implicit object type.
def emit_proc_c_metadata(proc, attributes):
    p_name = proc["name"]
    args = proc["args"]

    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    field_count = 0
    row_meta = ""
    ref_field_count = 0
    ref_fields = ""
    val_fields = ""
    row_offsets = ""
    first_ref = ""
    proc_row_type = f"{p_name}_return_struct"

    for arg in args:
        c_name = arg["name"]
        c_type = arg["type"]
        isNotNull = arg["isNotNull"]

        binding = arg["binding"] if "binding" in arg else ""

        if binding == "out" or binding == "inout":
            field_count += 1
            row_meta += "  " + row_types[c_type]
            row_field = "  "

            if isNotNull:
                row_meta += " | CQL_DATA_TYPE_NOT_NULL"
                row_field += c_notnull_types[c_type]
            else:
                row_field += c_nullable_types[c_type]

            row_field += " " + c_name + ";\n"

            if is_ref_type[c_type]:
                ref_fields += row_field
                ref_field_count += 1
                if first_ref == "":
                    first_ref = c_name
            else:
                val_fields += row_field

            row_offsets += f"  cql_offsetof({proc_row_type}, {c_name}),\n"

            row_meta += f", // {c_name}\n"

    # If the procedure uses the database we need a field for the result code
    # because it calls SQLite and we need to know if that worked.  If the
    # return value is not SQLITE_OK then the caller needs to know the error code.
    if usesDatabase:
        row_meta += "  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL,\n"
        val_fields += "  cql_int32 __rc;\n"
        row_offsets += f"  cql_offsetof({proc_row_type}, __rc),\n"
        field_count += 1

    # If the procedure has a projection then we need a field for the result set
    # actually we have two fields.  One that holds the result set as a long and
    # one that holds it as an object.  The long version is so that we can easily
    # pass it back to the C# world.  The object version is so that we can
    # manage the reference count correctly.  The long version won't participate
    # in ref counting which is fine/correct.
    if projection:
        row_meta += "  CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL, // result as long\n"
        row_meta += "  CQL_DATA_TYPE_OBJECT, // result set as object\n"
        ref_fields += "  cql_int64 __result_long;\n"
        ref_fields += "  cql_result_set_ref __result;\n"
        ref_field_count += 1
        row_offsets += f"  cql_offsetof({proc_row_type}, __result_long),\n"
        row_offsets += f"  cql_offsetof({proc_row_type}, __result),\n"
        field_count += 2
        if first_ref == "":
            first_ref = "__result"

    # from this point on we can use field_count to know if we have any result type at all
    # if we have such a type then we need to emit the computed metadata and struct definition
    if field_count > 0:
        print("")
        print(f"uint8_t {p_name}_return_meta[] = {{")
        print(row_meta, end="")
        print("};")
        print("")

        print(f"typedef struct {p_name}_return_struct {{")
        print(val_fields, end="")
        print(ref_fields, end="")
        print(f"}} {p_name}_return_struct;")
        print("")

        # If there are any reference fields we emit the reference count and offset
        # recall that this suffices to free the row as all internal references are
        # at the end of the row.
        if ref_field_count > 0:
            print(f"#define {proc_row_type}_refs_count {ref_field_count}")
            print(
                f"#define {proc_row_type}_refs_offset cql_offsetof({proc_row_type}, {first_ref})"
            )
            print("")

        # If there are any fields at all we emit the row offsets
        # note that the field offsets are in LOGICAL order not physical order
        # access to the fields will be by ordinal and that ordinal is the declared
        # order not the layout order with refs last.
        print(f"static cql_uint16 {p_name}_offsets[] = {{ {field_count},")
        print(row_offsets, end="")
        print("};")
        print("")

    return {
        "field_count": field_count,
        "proc_row_type": proc_row_type,
        "ref_field_count": ref_field_count
    }


# This emits the main body of the C Interop function, this includes
# * the Interop entry point for the procedure
# * the call to the procedure
# * the marshalling of the results
# * the return of the results
# * the cleanup of the results
def emit_proc_c_func_body(proc, meta_results, attributes):
    p_name = proc["name"]
    args = proc["args"]
    field_count = meta_results["field_count"]
    proc_row_type = meta_results["proc_row_type"]
    ref_field_count = meta_results["ref_field_count"]

    # Grab the command line arguments the package name and class
    # we know the return type for the Interop entry point based on fields
    # we'll need the usesDatabase flag to know if we need to pass the db
    package_name = cmd_args["package_name"]
    class_name = cmd_args["class_name"]
    return_type = "cql_int64" if field_count else "void"
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    # Now we emit the Interop entry point for the procedure.
    # The names are canonical based on the package and class name
    # that defined the entry point.  We expect these arguments to
    # have the same value when we generate the C as when we generated
    # the C#.
    print(f"{return_type} ", end="")
    print(f"{class_name}_{p_name}(")

    needsComma = False
    # if we use the database then we need the db argument, because database
    if usesDatabase:
        print("  cql_int64 __db", end="")
        needsComma = True

    # now we emit the arguments for the procedure, which is all the args
    # in the proc signature except for the out args.  The out args are
    # only returned in the result structure.  The inout args arrive
    # as normal in arguments and are also returned in the result structure.
    # The C#/Interop ABI has no by-ref arguments!
    for arg in args:
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        type = arg["type"]

        # for in or inout arguments we use the nullable or not nullable type as appropriate
        binding = arg["binding"] if "binding" in arg else "in"
        if binding == "inout" or binding == "in":
            xtype = dotnet_notnull_types[
                type] if isNotNull else dotnet_nullable_types[type]

            comma = ""
            if needsComma:
                comma = ",\n"

            if not isNotNull and split_types[arg["type"]]:
                xtype = dotnet_notnull_types[type]
                print(f"{comma}  bool {a_name}_has_value,")
                print(f"  {xtype} {a_name}_value", end="")
            else:
                print(f"{comma}  {xtype} {a_name}", end="")

            needsComma = True

    print(")")
    print("{")

    # Now we emit the standard locals if needed, one to capture the result code
    # and another to capture the result set if there is one.  The result set

    if usesDatabase:
        print("  cql_code rc = SQLITE_OK;")

    # if the procedure creates a result set then it is captured in "data_result_set"
    # this is typically the result of a query or something like that
    if projection:
        print(f"  {p_name}_result_set_ref _data_result_set_ = NULL;")

    # if the procedure has outputs, like a return code or a result set, or out arguments
    # then we need a row to capture those outputs. This row is allocated and filled
    # like a normal result set but it represents the procedures ABI. It is a single
    # row result set just like the result of a CQL "out" statement.  Such a row is
    # never empty, it has at least the result code.
    if field_count:
        # we make the output result set and the row to capture the results for it
        print("  cql_result_set_ref outputs_result_set = NULL;")
        print(
            f"  {proc_row_type} *row = ({proc_row_type} *)calloc(1, sizeof({proc_row_type}));"
        )

    # now it's time to make the call, we have variables to hold what goes before
    # the call, the call, and what goes after the call.  Before the call go things
    # like variable declarations and unboxing.  After the call goes assignment of
    # inout arguments and cleanup of any resources that were allocated during the
    # preamble.
    preamble = ""
    cleanup = ""
    call = "  "

    # if we use the database we need to assign the rc variable with the result
    # of the call
    if usesDatabase:
        call += "rc = "

    # the call is the name of the procedure, it won't have the Interop suffix
    # if it has a projection we called the "_fetch_results" version of the
    # procedure.  This is the version that materializes and returns a result set.
    call += p_name
    if projection:
        call += "_fetch_results"

    call += "("

    needsComma = False

    # if we use the database we need to pass the db, this is the first argument
    # by convention
    if usesDatabase:
        call += "(sqlite3*)__db"
        needsComma = True

    # if the procedure returns a result set that will be the second argument
    # and it is by reference.  We own this reference after the call.
    if projection:
        if needsComma:
            call += ", "
        call += "&_data_result_set_"
        needsComma = True

    # Now we walk the arguments and emit the call to the procedure.  There
    # as important things to do at this point:
    #   * "out" arguments did not exist in the C# call, we use the storage in
    #     the procedure result row to capture them
    #
    #   * "inout" arguments are passed by value in the C# world and then
    #     returned in the procedure result row.  So we store the provided value
    #     in a temporary and then pass that temporary by reference to the
    #     procedure.  The procedure will fill in the value and we will copy it
    #     back to the output row.
    #
    #   * "in" arguments are passed by value in the C# world and are passed by
    #     value to the procedure.  They are not returned in the result.
    #
    #   * for nullable types provided arguments might be in a boxed form like
    #     boxedBoolean, boxedInteger, boxedLong, boxedDouble.  We need to unbox
    #     these into their native types before we can pass them to the
    #     procedure.  Note that they might be null.  They are stored in
    #     cql_nullable_bool, cql_nullable_int32, cql_nullable_int64,
    #     cql_nullable_double.  So nulls are not a problem.
    for arg in args:
        if needsComma:
            call += ","

        needsComma = True
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        a_type = arg["type"]
        isRef = is_ref_type[a_type]
        binding = arg["binding"] if "binding" in arg else "in"
        inout = (binding == "inout")
        kind = arg["kind"] if "kind" in arg else ""
        call += f" /*{binding}*/ "

        # for inout we will by passing either in input argument or the
        # converted temporary by reference.  We will also be copying the
        # result back to the output row.  This starts the inout-ness
        if inout:
            call += "&"

        if binding == "out":
            # If this is an out argument we will be passing the storage in the
            # result row by reference.  This fully handles the out-ness. Note,
            # out arguments are not mentioned in the list, they are only part of
            # the result row.
            c_type = c_notnull_types[
                a_type] if isNotNull else c_nullable_types[a_type]
            call += f"&row->{a_name}"
        elif isNotNull and not isRef:
            # Not null and not reference type means we can pass the argument
            # directly.  We never need to unbox it because it's passed as
            # a native type.  We don't need to convert it because it's not
            # a blob or string.  So just go.
            call += a_name
            cleanup += f"  row->{a_name} = {a_name};\n" if inout else ""
        elif a_type == "text":
            # Text is a string in C#.  We need to "unbox" it into a
            # cql_string_ref.  We need to release the string ref after the call.
            # So we emit a temporary string ref, we initialize it from the C#
            # string and then use it in the call.  For "inout" args, after the
            # call copy the string reference to the output row.
            preamble += f"  cql_string_ref str_ref_{a_name} = NULL;\n"
            preamble += f"  if ({a_name}) {{\n"
            preamble += f"    str_ref_{a_name} = cql_string_ref_new({a_name});\n"
            preamble += f"  }}\n"
            cleanup += f"  cql_set_string_ref(&row->{a_name}, str_ref_{a_name});\n" if inout else ""
            cleanup += f"  cql_string_release(str_ref_{a_name});\n"
            call += f"str_ref_{a_name}"
        elif a_type == "blob":
            # Text is a byte in C#.  We need to "unbox" it into a
            # cql_blob_ref.  We need to release the blob ref after the call. So
            # we emit a temporary blob ref, we initialize it from the C# blob
            # and then use it in the call.  For "inout" args, after the call
            # copy the blob reference to the output row.
            preamble += f"  cql_blob_ref blob_ref_{a_name} = NULL;\n"
            preamble += f"  if ({a_name}) {{\n"
            preamble += f"    void *bytes_{a_name} = \"xx\";\n"
            preamble += f"    int len_{a_name} = 2;\n"
            preamble += f"    blob_ref_{a_name} = cql_blob_ref_new(bytes_{a_name}, len_{a_name});\n"
            preamble += f"  }}\n"
            cleanup += f"  cql_set_blob_ref(&row->{a_name}, blob_ref_{a_name});\n" if inout else ""
            cleanup += f"  cql_blob_release(blob_ref_{a_name});\n"
            call += f"blob_ref_{a_name}"
        elif a_type == "bool":
            # The bool type comes as a bool from C# which needs to be
            # unboxed. once it's unboxed we can pass it as a cql_nullable_bool.
            # For "inout" arguments we copy out the value from the temporary
            # after the call into the row object.
            preamble += f"  cql_nullable_bool n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !{a_name}_has_value, {a_name}_value);\n"
            cleanup += f"  row->{a_name} = n_{a_name};" if inout else ""
            call += f"n_{a_name}"
        elif a_type == "integer":
            # The integer type comes as a Integer from C# which needs to be
            # unboxed. once it's unboxed we can pass it as a cql_nullable_int32.
            # For "inout" arguments we copy out the value from the temporary
            # after the call into the row object.
            preamble += f"  cql_nullable_int32 n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !{a_name}_has_value, {a_name}_value);\n"
            cleanup += f"  row->{a_name} = n_{a_name};\n" if inout else ""
            call += f"n_{a_name}"
        elif a_type == "long":
            # The long type comes as a Long from C# which needs to be unboxed.
            # once it's unboxed we can pass it as a cql_nullable_int64.  For
            # "inout" arguments we copy out the value from the temporary after
            # the call into the row object.
            preamble += f"  cql_nullable_int64 n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !{a_name}_has_value, {a_name}_value);\n"
            cleanup += f"  row->{a_name} = n_{a_name};\n" if inout else ""
            call += f"n_{a_name}"
        elif a_type == "real":
            # The real type comes as a Double from C# which needs to be
            # unboxed. once it's unboxed we can pass it as a
            # cql_nullable_double.  For "inout" arguments we copy out the value
            # from the temporary after the call into the row object.
            preamble += f"  cql_nullable_double n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !{a_name}_has_value, {a_name}_value);\n"
            cleanup += f"  row->{a_name} = n_{a_name};\n" if inout else ""
            call += f"n_{a_name}"
        else:
            # object types are not supported in this sample
            call += f" /* unsupported arg type:'{a_type}' isNotNull:{isNotNull} kind:'{kind}' */"

    call += ");"

    # we're ready, we emit the preamble, the call, and the cleanup
    if preamble != "":
        print(preamble)
    print(call)
    if cleanup != "":
        print(cleanup)

    # if have result fields we fill them in and return the result row
    if field_count:
        # if we have a result code we need to return that
        if usesDatabase:
            print("  row->__rc = rc;")

        # if we have a result set we need to return that
        if projection:
            # the C# world wants to access the row reference as a "long"
            # so we store a non-ref counted version of the pointer
            print("  // the row takes over the result set reference.")
            print("  row->__result = (cql_result_set_ref)_data_result_set_;")
            print("  row->__result_long = (int64_t)_data_result_set_;")

        # to return the row we need to populate a cql_Fetch_info
        # we have already emitted everything we need to fill it in
        # so here we can just populate
        print("")
        print("  cql_fetch_info info = {")

        if usesDatabase:
            print("    .rc = SQLITE_OK,")
        print(f"    .col_offsets = {p_name}_offsets,")
        print(f"    .data_types = {p_name}_return_meta,")

        if ref_field_count:
            print(f"    .refs_count = {proc_row_type}_refs_count,")
            print(f"    .refs_offset = {proc_row_type}_refs_offset,")
        print(f"    .rowsize = sizeof({proc_row_type}),")
        print("  };")

        # generate and return the one row result set that holds our procedure outputs
        print(
            "  cql_one_row_result(&info, (char *)row, 1, &outputs_result_set);"
        )
        print("  return (cql_int64)outputs_result_set;")

    print("}")


# Emit the C code for a single procedure
# this includes
# * the metadata for the return type
# * the struct definition for the return type
# * the Interop entry point for the procedure
# * the call to the procedure
# * the marshalling of the results
# * the return of the results
# * the cleanup of the results
def emit_proc_c_interop(proc, attributes):
    meta_results = emit_proc_c_metadata(proc, attributes)
    emit_proc_c_func_body(proc, meta_results, attributes)


# The procedure might have any number of projected columns if it creates
# a result set.  We emit a class for the reading such a result set here.
#
# The relevant parts of the JSON are these fragments:
# projected_column
#  name : STRING
#  type : STRING
#  kind : STRING [optional]
#  isSensitive : BOOL [optional]
#  isNotNull" : BOOL
def emit_result_set_projection(proc, attributes):
    # the procedure is already known to have a projection or we wouldn't be here
    p_name = proc["name"]
    projection = proc["projection"]
    col = 0
    for p in projection:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isSensitive = p.get("isSensitive", 0)
        isNotNull = p["isNotNull"]
        hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]

        # vaulted columns get encoding treatment, the treatment is defined
        # the primary docs discuss vaulted columns.
        vaulted_columns = attributes.get("cql:vault_sensitive", None)
        vault_all = vaulted_columns == 1

        # we compute the name of the getter based on the type of the column
        getter = getters[c_type]
        c_type = notnull_types[c_type]

        # we tweak the name for nullability if needed
        if isNotNull:
            nullable = ""
            q = ""
        else:
            if getter == "String" or getter == "Blob" or getter == "ChildResultSet":
                nullable = ""
                q = ""
            else:
                nullable = "Nullable"
                q = "?"

        # the return type for child result sets is not just Object
        if getter == "ChildResultSet":
            c_type = "CQLResultSet"

        # if there is only one row (because it was made with an out statement)
        # then we can elide all the row arguments and just pass "row 0" to the helpers.
        row_arg = "" if hasOutResult else "int row"
        row_formal = "0" if hasOutResult else "row"

        # we're done, we're ready to emit the function name and its body
        print(f"    public {c_type}{q} get_{c_name}({row_arg}) {{")
        print(
            f"      return mResultSet.get{nullable}{getter}({row_formal}, {col});"
        )
        print("    }\n")

        col += 1


# The procedure might have any number of out arguments plus its normal returns
# We emit them all here.  We make a synthetic result set type to hold all those
# out results as well as the SQLite return code if it's needed and the returned
# result set if it's needed.  So both the database result set and the procedures
# out arguments come back in the form of a result set.  This lets us use the
# same Interop for both types.
def emit_proc_csharp_return_type(proc):
    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    # this is the result type for the procedure out arguments and returns
    print(f"  public sealed class {p_name}ReturnType : CQLViewModel {{")
    print(
        f"    public {p_name}ReturnType(CQLResultSet resultSet) : base(resultSet) {{"
    )
    print("    }\n")

    col = 0
    for p in args:
        c_name = p["name"]
        type = p["type"]
        isNotNull = p["isNotNull"]

        binding = p["binding"] if "binding" in p else ""

        if binding == "out" or binding == "inout":
            getter = getters[type]

            if isNotNull:
                type = notnull_types[type]
                nullable = ""
            else:
                type = nullable_types[type]
                if getter == "String" or getter == "Blob" or getter == "ChildResultSet":
                    nullable = ""
                else:
                    nullable = "Nullable"

            if getter == "ChildResultSet":
                type = "CQLResultSet"

            print(f"    public {type} {c_name} {{")
            print("      get {")
            print(
                f"        return mResultSet.get{nullable}{getter}(0, {col});")
            print("      }")
            print("    }\n")

            col += 1

    if usesDatabase:
        print(f"    public int result_code {{")
        print(f"      get {{")
        print(f"        return mResultSet.getInteger(0, {col});")
        print(f"      }}")
        print("    }\n")
        col += 1

    if projection:
        print(f"    public {p_name}ViewModel result_set {{")
        print(f"      get {{")
        print(
            f"        return new {p_name}ViewModel(new CQLResultSet(mResultSet.getLong(0, {col})));"
        )
        print(f"      }}")
        print("    }\n")
        col += 1

    print("    public int Count {")
    print("       get {")
    print("        return 1;")
    print("       }")
    print("    }\n")
    print("    override protected bool hasIdentityColumns() {")
    print(f"      return false;")
    print("    }")
    print("  }\n")


def emit_proc_csharp_interop(proc, attributes):
    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc
    class_name = cmd_args["class_name"]

    emit_proc_csharp_return_type(proc)

    # Generate interop method declaration

    commaNeeded = False
    params = ""
    c_params = ""
    call_args = ""
    needs_wrapper = False

    # if usesDatabase then we need the db argument, in c# it goes in __db
    if usesDatabase:
        params += "long __db"
        c_params += "long __db"
        call_args += "__db"
        commaNeeded = True

    # Now we walk the arguments and emit the C# types for all of the
    # in and inout arguments.  Note that the C# ABI does not use
    # out arguments, they are returned as part procedures result.  So
    # there are no "by ref" arguments in the C# world. This is just
    # a convention, you could do it differently if you wanted to, but
    # this code makes that fairly simple ABI choice so that all results
    # can use the same access patterns. Rowsets and arguments.
    outArgs = False
    for arg in args:
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        type = arg["type"]

        binding = arg["binding"] if "binding" in arg else "in"

        # Add in and inout arguments to the method signature
        if binding == "inout" or binding == "in":
            xtype = notnull_types[type] if isNotNull else nullable_types[type]

            if commaNeeded:
                params += ", "
                c_params += ", "
                call_args += ", "

            if not isNotNull and split_types[type]:
                call_args += f"{a_name}.HasValue, {a_name}.GetValueOrDefault()"
                params += f"{xtype} {a_name}"
                xtype = notnull_types[type]
                c_params += f"bool {a_name}_has_value, {xtype} {a_name}_value"
                needs_wrapper = True
            else:
                call_args += a_name
                c_params += f"{xtype} {a_name}"
                params += f"{xtype} {a_name}"

            commaNeeded = True

        # For the out args, all we need to know at this point is
        # that there are some, we'll handle them in the return type.
        if binding == "inout" or binding == "out":
            outArgs = True

    # Any of these demand a return type, the Interop entry point will return
    # a result set thing for the return shape.  That itself might include
    # a "normal" result set.  The return type is a nested class that
    # has the result set and the out arguments.  This is a little bit
    # more complex than the C version because the C version can return
    # multiple things in the return shape.  The C# version only
    # returns one thing, so we wrap the result set and the out arguments.
    needs_return_type = usesDatabase or outArgs or projection

    print(f"  // procedure entry point {p_name}")
    return_type = "void"

    # If we need a result type, we emit the Interop entry point as a helper
    # that maps the returned long to the result type.  This makes things
    # as easy as possible for the caller.
    if needs_return_type:
        return_type = "long"
        print(f"  public static {p_name}ReturnType {p_name}({params}) {{")
        print(
            f"     return new {p_name}ReturnType(new CQLResultSet({class_name}_{p_name}({call_args})));"
        )
        print("  }\n")
    else:
        print(f"  public static {return_type} {p_name}({params}) {{")
        if return_type != "void":
            print(f"     return {class_name}_{p_name}({call_args});")
        else:
            print(f"     {class_name}_{p_name}({call_args});")
        print("  }\n")

    # Now we emit the declaration for Interop entry point itself.  This is a simple wrapper
    # to the C code that does the actual work.
    print(f"  [DllImport(@\"cql_interop.dll\")]")
    print(
        f"  public static extern {return_type} {class_name}_{p_name}({c_params});\n"
    )


def emit_proc_csharp_projection(proc, attributes):
    p_name = proc["name"]
    # for now only procs with a result type, like before
    # we'd like to emit Interop helpers for other procs too, but not now

    if "projection" in proc:
        print(f"  public sealed class {p_name}ViewModel : CQLViewModel {{")
        print(
            f"    public {p_name}ViewModel(CQLResultSet resultSet) : base(resultSet) {{"
        )
        print("    }\n")

        emit_result_set_projection(proc, attributes)

        identityResult = "true" if "cql:identity" in attributes else "false"

        print("    override protected bool hasIdentityColumns() {")
        print(f"      return {identityResult};")
        print("    }\n")

        print("    public int Count {")
        print("       get {")
        print(f"        return mResultSet.getCount();")
        print("       }")
        print("    }\n")
        print("  }\n")


# emit all the procedures in a section, the most interesting are those
# that have a projection, those are the ones that return a result set.
def emit_proc_section(section, s_name):
    emit_c = cmd_args["emit_c"]
    for proc in section:
        # we unwrap the attributes array into a map for easy access
        alist = proc.get("attributes", [])
        attributes = {}
        for attr in alist:
            k = attr["name"]
            v = attr["value"]
            attributes[k] = v

        # these are the procedures that are suppressed from the public API
        # they are used internally by other procedures but we can't call them
        suppressed = ("cql:suppress_result_set" in attributes
                      or "cql:private" in attributes
                      or "cql:suppress_getters" in attributes)

        if not suppressed:
            if emit_c:
                # emit the C code for the Interop entry points and the supporting metadata
                emit_proc_c_interop(proc, attributes)
            else:
                emit_proc_csharp_projection(proc, attributes)
                emit_proc_csharp_interop(proc, attributes)


def emit_basetypes(data):
    print("typedef struct nullable_bool {")
    print("  unsigned int hasValue;")
    print("  unsigned int value;")
    print("} nullable_bool;")
    print("typedef struct nullable_int {")
    print("  unsigned int hasValue;")
    print("  cql_int32 value;")
    print("} nullable_int;")
    print("typedef struct nullable_long {")
    print("  unsigned int hasValue;")
    print("  cql_int64 value;")
    print("} nullable_long;")
    print("typedef struct nullable_real {")
    print("  unsigned int hasValue;")
    print("  double value;")
    print("} nullable_real;")


# These are all of the procedure sources
def emit_procs(data):
    emit_proc_section(data["queries"], "queries")
    emit_proc_section(data["deletes"], "deletes")
    emit_proc_section(data["inserts"], "inserts")
    emit_proc_section(data["generalInserts"], "generalInserts")
    emit_proc_section(data["updates"], "updates")
    emit_proc_section(data["general"], "general")


def main():
    jfile = sys.argv[1]
    with open(jfile) as json_file:
        data = json.load(json_file)

        # pull the flags, starting with whether we will be emitting C or C#
        i = 2
        if sys.argv[i] == "--emit_c":
            cmd_args["emit_c"] = True
            i += 1

        # these are the various fragments we might need, we need all the parts
        # to generate the C.  The first two are enough for the C#, there are
        # defaults but they are kind of useless.
        while i + 2 <= len(sys.argv):
            if sys.argv[i] == "--class":
                cmd_args["class_name"] = sys.argv[i + 1]
            elif sys.argv[i] == "--cql_header":
                cmd_args["cql_header"] = sys.argv[i + 1]
            else:
                usage()
            i += 2

        # Each generated file gets the standard header.
        # It still uses the Meta header because that was required
        # by the original license even though none of this is actually
        # written by Meta at this point.
        print("/*")
        print("* Copyright (c) Meta Platforms, Inc. and affiliates.")
        print("*")
        print(
            "* This source code is licensed under the MIT license found in the"
        )
        print("* LICENSE file in the root directory of this source tree.")
        print("*/\n")

        package_name = cmd_args["package_name"]
        class_name = cmd_args["class_name"]
        dotnet_header = cmd_args["dotnet_header"]
        cql_header = cmd_args["cql_header"]

        if cmd_args["emit_c"]:
            # The C code gen has the standard header files per the flags
            # after which we emit the Interop helpers to unbox int, long, etc.
            # Finally we emit the actual Interop entry points to invoke the CQL.
            # These convert the C# types to CQL types and back.
            print("")
            print("#include \"cqlrt.h\"")
            print(f"#include \"{cql_header}\"")
            print("")
            emit_basetypes(data)
            emit_procs(data)
        else:
            print("using System;")
            print("using System.Runtime.InteropServices;")
            print("using System.Text;")
            print("using CGSQL;\n")

            print(f"public class {class_name}")
            print("{")
            print("")

            emit_procs(data)
            print("}")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
