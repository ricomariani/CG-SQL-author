#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# cqlobjc.py -> converts CQL JSON format into objc classes for interop
#
# The CQL JSON format is documented here: https://cgsql.dev/cql-guide/ch13 and
#   here: https://cgsql.dev/json-diagram
#
# NB: This code should be considered SAMPLE code, not production code. Which is
# to say you can reasonably expect that the specifics of the diagrams and the
# database produced here are likely to change at whim.  If you need a particular
# output, you are enouraged to FORK this sample into something stable.  The JSON
# format itself is the contract and it evolves in a backwards compatible way.
# This script is likely to change to make different pretty pictures at various
# times.
#
# This approach is just one way to generate objective C, there are other ways
# you can create wrapper classes;  The naming conventions used here are the
# simplest with the least transform from the original CQL but you could
# reasonably want to camelCase or PascalCase names as needed to create something
# cleaner looking.  All these things are possible with not much python at all.

import json
import sys


def usage():
    print(
        "Usage: input.json [options] >result.h or >result.m\n"
        "\n"
        "--legacy\n"
        "    emit extra instance variable definitions in the header (legacy objc)\n"
        "--emit_impl\n"
        "    activates the code pass to make the .m file, run the tool once with this flag once without\n"
        "--header header_file\n"
        "    specifies the CQL generated header file to include in the generated C code\n"
    )
    sys.exit(0)


dashes = "// ----------------------------------------------------------------"

# Reference type check
is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True

# Objc types for not null cql types
objc_notnull_types = {}
objc_notnull_types["bool"] = "cql_bool"
objc_notnull_types["integer"] = "cql_int32"
objc_notnull_types["long"] = "cql_int64"
objc_notnull_types["real"] = "cql_double"
objc_notnull_types["object"] = "NSObject *_Nonnull"
objc_notnull_types["blob"] = "NSData *_Nonnull"
objc_notnull_types["text"] = "NSString *_Nonnull"

# Objc types for nullable cql types
objc_nullable_types = {}
objc_nullable_types["bool"] = "NSNumber *_Nullable"
objc_nullable_types["integer"] = "NSNumber *_Nullable"
objc_nullable_types["long"] = "NSNumber *_Nullable"
objc_nullable_types["real"] = "NSNumber *_Nullable"
objc_nullable_types["object"] = "NSObject *_Nullable"
objc_nullable_types["blob"] = "NSData *_Nullable"
objc_nullable_types["text"] = "NSString *_Nullable"

objc_types = {}
objc_types[False] = objc_nullable_types
objc_types[True] = objc_notnull_types

cf_types = {}
cf_types["object"] = "CFTypeRef"
cf_types["blob"] = "CFDataRef"
cf_types["text"] = "CFStringRef"

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

# encoding for the types of conversions that might be necessary
notnull_conv = {}
notnull_conv["bool"] = ""
notnull_conv["integer"] = ""
notnull_conv["long"] = ""
notnull_conv["real"] = ""
notnull_conv["object"] = "bridge"
notnull_conv["blob"] = "bridge"
notnull_conv["text"] = "bridge"

nullable_conv = {}
nullable_conv["bool"] = "@"
nullable_conv["integer"] = "@"
nullable_conv["long"] = "@"
nullable_conv["real"] = "@"
nullable_conv["object"] = "bridge"
nullable_conv["blob"] = "bridge"
nullable_conv["text"] = "bridge"

c_types = {}
c_types[False] = c_nullable_types
c_types[True] = c_notnull_types

# methods to extract the indicated type out of an NSNumber
box_vals = {}
box_vals["bool"] = "intValue"
box_vals["integer"] = "intValue"
box_vals["long"] = "longLongValue"
box_vals["real"] = "doubleValue"

# Storage for the various command line arguments
cmd_args = {}
cmd_args["emit_impllass"] = False
cmd_args["header"] = "something.h"
cmd_args["legacy"] = False
cmd_args["emit_impl"] = False

# The prefix for all the generated classes and procedures.
# Change as you see fit.
CGS = "CGS"

# The procedure might have any number of out arguments plus its normal returns
# We emit them all here.  We make a synthetic result set type to hold all those
# out results as well as the SQLite return code if it's needed and the returned
# result set if it's needed.  We don't make a return type if the procedure is
# void or returns just returns the status code.  Out arguments or a result set
# are the triggers for the return type.
def emit_proc_objc_return_impl(proc):
    p_name = proc["name"]
    args = proc["args"]

    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    # this is the result type for the procedure out arguments and returns
    print("")
    print(dashes)

    legacy = cmd_args["legacy"]
   
    if legacy:
      print(f"@implementation {CGS}{p_name}RT : NSObject", end="")
    else:
      print(f"@implementation {CGS}{p_name}RT", end="")

    print(" {")

    for p in args:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isNotNull = p["isNotNull"]
        binding = p["binding"] if "binding" in p else ""

        if binding == "out" or binding == "inout":
            objc_type = objc_type_for_arg(c_type, kind, isNotNull)
            print(f"  {objc_type} _{c_name};")

    if usesDatabase:
        print("  int _resultCode;")

    if projection:
        print(f"  {CGS}{p_name}RS *_Nullable _resultSet;")

    print("}")
    print("")

    for p in args:
        c_name = p["name"]
        binding = p["binding"] if "binding" in p else ""
        if binding == "out" or binding == "inout":
            print(f"@synthesize {c_name} = _{c_name};")

    if usesDatabase:
        print("@synthesize resultCode = _resultCode;")

    if projection:
        print(f"@synthesize resultSet = _resultSet;")

    print("")
    print("@end")
    print(dashes)


# This creates the body of the result set class.  This is the class that
# holds the result set from a procedure that returns a result set.  The
# result set is a collection of rows, each row is a collection of columns.
# The columns are the projected columns of the procedure.  This class
# is a wrapper around the CQL result set, it knows how to fetch the
# columns from the result set and how to convert them into Objc types.
def emit_proc_objc_projection_impl(proc, attributes):
    p_name = proc["name"]

    # emit the projection type if it needs one
    if "projection" not in proc:
        return

    projection = proc["projection"]

    print("")
    print(dashes)
    legacy = cmd_args["legacy"]
   
    if legacy:
      print(f"@implementation {CGS}{p_name}RS : NSObject", end="")
    else:
      print(f"@implementation {CGS}{p_name}RS", end="")

    print(" {")
    print(f"  {p_name}_result_set_ref _resultSet;")
    print("}")

    for p in projection:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isSensitive = p.get("isSensitive", 0)
        isNotNull = p["isNotNull"]
        hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]

        objc_type = objc_type_for_arg(c_type, kind, isNotNull)

        print("")

        if hasOutResult:
            print(f"- ({objc_type}){c_name}", end="")
        else:
            print(f"- ({objc_type}){c_name}:(NSUInteger)row", end="")

        conv = notnull_conv[c_type] if isNotNull else nullable_conv[c_type]
        bool_fix = "" if objc_type != "cql_bool" else " ? YES : NO"
        row_arg = "" if hasOutResult else ", row"
        row_param = "" if hasOutResult else ", cql_int32 row"

        # the getter body is one of three forms
        # 1. For reference types we convert the value to NSString, NSData etc.
        # 2. For nullable types value types we convert the value to NSNumber
        # 3. For non-nullable value types we just return the value

        print(" {")

        if conv == "@":
            print(
                f"  return {p_name}_get_{c_name}_is_null(_resultSet{row_arg}) ? nil : @({p_name}_get_{c_name}_value(_resultSet{row_arg}));"
            )
        elif conv == "bridge":
            print(
                f"  return (__bridge {objc_type}){p_name}_get_{c_name}(_resultSet{row_arg}){bool_fix};"
            )
        else:
            print(
                f"  return {p_name}_get_{c_name}(_resultSet{row_arg}){bool_fix};"
            )

        print("}")

    identityResult = "YES" if "cql:identity" in attributes else "NO"

    print("")
    print("- (cql_bool)hasIdentityColumns {")
    print(f"  return {identityResult};")
    print("}")

    # expose the count of the result set, note that even result set
    # that was made with OUT (i.e. a one row result) might be empty
    # so the count is the only way to know if there is a row or not.

    print("")
    print("-(int)count {")
    print(f"  return {p_name}_result_count(_resultSet);")
    print("}")

    # we own the handle so we release it in dealloc


    print("")
    print("-(void)dealloc {")
    print("  cql_release((cql_type_ref)self.resultSet);")
    if legacy:
      print("  [super dealloc];")
  
    print("}")

    print("")
    print("@synthesize resultSet = _resultSet;")
    print("")
    print("@end")
    print(dashes)


# This emits the main body of the implementation function, this includes
# * the OBJC entry point for the procedure
# * the call to the CQL procedure
# * the appropriate bridge of the results
# * the return of the results
def emit_proc_objc_impl(proc, attributes):
    p_name = proc["name"]
    args = proc["args"]

    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc
    outArgs = hasOutArgs(args)

    needs_return_type = outArgs or projection
    needs_only_result_code = usesDatabase and not needs_return_type

    if needs_return_type:
        emit_proc_objc_return_impl(proc)

    emit_proc_objc_projection_impl(proc, attributes)

    print("")
    print(f"// procedure entry point {p_name}")

    # emit a suitable entry point, use int or void return if possible
    # otherwise we have to create the result set type, and return that
    if needs_return_type:
        print(f"{CGS}{p_name}RT *_Nonnull {CGS}Create{p_name}RT(")
    elif needs_only_result_code:
        print(f"int {CGS}{p_name}(")
    else:
        print(f"void {CGS}{p_name}(")

    needs_comma = False
    # if we use the database then we need the db argument, because database
    if usesDatabase:
        print("  sqlite3 *_Nonnull __db", end="")
        needs_comma = True

    # now we emit the arguments for the procedure, which is all the args
    # in the proc signature except for the out args.  The out args are
    # only returned in the result structure.  The inout args arrive
    # as normal in arguments and are also returned in the result structure.
    for arg in args:
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        a_type = arg["type"]

        # for in or inout arguments we use the nullable or not nullable type as appropriate
        binding = arg["binding"] if "binding" in arg else "in"
        if binding == "inout" or binding == "in":
            objc_type = objc_types[isNotNull][a_type]
            if needs_comma:
                print(",")

            print(f"  {objc_type} {a_name}", end="")
            needs_comma = True

    print(")")
    print("{")

    # Now we emit the standard locals if needed, one to capture the result code
    # and another to capture the result set if there is one.  The result set

    if usesDatabase:
        print("  cql_code rc = SQLITE_OK;")

    # if the procedure creates a result set then it is captured in "data_result_set"
    # this is typically the result of a query or something like that
    if projection:
        print(f"  {p_name}_result_set_ref _result_set_ref = NULL;")

    # if the procedure has outputs, like a return code or a result set, or out arguments
    # then we need a row to capture those outputs. This row is allocated and filled
    # like a normal result set but it represents the procedures ABI. It is a single
    # row result set just like the result of a CQL "out" statement.  Such a row is
    # never empty, it has at least the result code.
    if needs_return_type:
        print(f"  {CGS}{p_name}RT *_result = [{CGS}{p_name}RT new];")

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

    # the call is the name of the procedure, it won't have the JNI suffix
    # if it has a projection we called the "_fetch_results" version of the
    # procedure.  This is the version that materializes and returns a result set.
    call += p_name
    if projection:
        call += "_fetch_results"

    call += "(\n    "

    needsComma = False

    # if we use the database we need to pass the db, this is the first argument
    # by convention
    if usesDatabase:
        call += "__db"
        needsComma = True

    # if the procedure returns a result set that will be the second argument
    # and it is by reference.  We own this reference after the call.
    if projection:
        if needsComma:
            call += ",\n    "
        call += "&_result_set_ref"
        needsComma = True

    # Now we walk the arguments and emit the call to the procedure.  There
    # as important things to do at this point:
    #   * "out" arguments did not exist in the Objc call, we use the storage in
    #     the procedure result row to capture them
    #
    #   * "inout" arguments are passed by value in the Objc world and then
    #     returned in the procedure result row.  So we store the provided value
    #     in a temporary and then pass that temporary by reference to the
    #     procedure.  The procedure will fill in the value and we will copy it
    #     back to the output row.
    #
    #   * "in" arguments are passed by value in the Objc world and are passed by
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
            call += ",\n    "

        needsComma = True
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        a_type = arg["type"]
        isRef = is_ref_type[a_type]
        binding = arg["binding"] if "binding" in arg else "in"
        inout = (binding == "inout")
        out = (binding == "out")
        kind = arg["kind"] if "kind" in arg else ""
        call += f"/*{binding}*/ "

        # for inout we will by passing either in input argument or the
        # converted temporary by reference.  We will also be copying the
        # result back to the output row.  This starts the inout-ness
        if inout or out:
            call += "&"

        c_type = c_types[isNotNull][a_type]

        if out or not isNotNull or isRef:
            # Out arguments are not passed in the call, they are returned in the result row.
            # Nullable arguments come in as NSNumber or NSData or NSString and need to be converted
            # Reference types come in as NSObject or NSData or NSString and need to be converted
            # We emit a temporary variable to hold the converted value.
            if isRef:
                if out:
                    preamble += f"  {c_type} tmp_{a_name} = NULL;\n"
                else:
                    ref_type = cf_types[a_type]
                    preamble += f"  {c_type} tmp_{a_name} = (__bridge {ref_type}){a_name};\n"

            else:
                preamble += f"  {c_type} tmp_{a_name};\n"

        transfer = "_transfer" if out else ""

        if isNotNull and not isRef:
            # Not null and not reference type means we can pass the argument
            # directly.  We never need to unbox it because it's passed as
            # a native type.  We don't need to convert it because it's not
            # a blob or string.  So just go.
            arg = f"tmp_{a_name}" if out else a_name
            call += arg
            cleanup += f"  _result.{a_name} = {arg};\n" if inout or out else ""
        elif a_type == "text":
            # Text is a string in Objc.  We need to "unbox" it into a
            # cql_string_ref.  We need to release the string ref after the call.
            # So we emit a temporary string ref, we initialize it from the Objc
            # string and then use it in the call.  For "inout" args, after the
            # call copy the string reference to the output row.
            cleanup += f"  _result.{a_name} = (__bridge{transfer} NSString *)tmp_{a_name};\n" if inout or out else ""
            call += f"tmp_{a_name}"
        elif a_type == "blob":
            cleanup += f"  _result.{a_name} = (__bridge{transfer} NSData *)tmp_{a_name};\n" if inout or out else ""
            call += f"tmp_{a_name}"
        elif a_type == "bool" or a_type == "integer" or a_type == "long" or a_type == "real":
            # The boolean type comes as a Boolean from Objc which needs to be
            # unboxed. once it's unboxed we can pass it as a cql_nullable_bool.
            # For "inout" arguments we copy out the value from the temporary
            # after the call into the row object.
            val = box_vals[a_type]
            notnull_type = c_notnull_types[a_type]
            bool_norm = "!!" if a_type == "bool" else ""
            preamble += f"  cql_set_nullable(tmp_{a_name}, !{a_name}, ({notnull_type}){bool_norm}[{a_name} {val}]);\n" if not out else ""
            cleanup += f"  _result.{a_name} = tmp_{a_name}.is_null ? NULL : @(tmp_{a_name}.value);" if inout or out else ""
            call += f"tmp_{a_name}"
        else:
            # object types are not supported in this sample
            call += f" /* unsupported arg type:'{a_type}' isNotNull:{isNotNull} kind:'{kind}' */  error_unsupported_arg_type_{a_name}"

    call += ");\n"

    # we're ready, we emit the preamble, the call, and the cleanup
    if preamble != "":
        print(preamble)
    print(call)
    if cleanup != "":
        print(cleanup)

    # if have result fields we fill them in and return the result row
    if needs_return_type:
        # if we have a result code we need to return that
        if usesDatabase:
            print("  _result.resultCode = rc;")

        # if we have a result set we need to return that
        if projection:
            print(
                f"  // {CGS}{p_name}RS takes over result_set_ref, it knows to clean it up"
            )
            print(f" {CGS}{p_name}RS *rs = [{CGS}{p_name}RS new];")
            print("  rs.resultSet = _result_set_ref;")
            print("  _result.resultSet = rs;")

        print("  return _result;")

    print("}")


# convert the CQL column json type into the objc type
def objc_type_for_arg(a_type, kind, isNotNull):
    if a_type == "object" and kind.endswith(" SET"):
        set_type = kind[:-4]
        c_type = f"{CGS}{set_type}RS *"
        if isNotNull:
            c_type = f"{c_type}_Nonnull"
        else:
            c_type = f"{c_type}_Nullable"
    else:
        c_type = objc_types[isNotNull][a_type]

    return c_type


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
def emit_result_set_projection_header(proc, attributes):
    # the procedure is already known to have a projection or we wouldn't be here
    p_name = proc["name"]
    projection = proc["projection"]
    for p in projection:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isSensitive = p.get("isSensitive", 0)
        isNotNull = p["isNotNull"]
        hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]

        c_type = objc_type_for_arg(c_type, kind, isNotNull)

        if hasOutResult:
            print(f"@property (nonatomic, readonly) {c_type} {c_name};")
        else:
            print(f"- ({c_type}){c_name}:(NSUInteger)row;")


def hasOutArgs(args):
    for p in args:
        # For the out args, all we need to know at this point is
        # that there are some, we'll handle them in the return type.
        binding = p["binding"] if "binding" in p else ""
        if binding == "inout" or binding == "out":
            return True
    return False


# The procedure might have any number of out arguments plus its normal returns
# We emit them all here.  We make a synthetic result set type to hold all those
# out results as well as the SQLite return code if it's needed and the returned
# result set if it's needed.
def emit_proc_objc_return_type(proc):
    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    outArgs = hasOutArgs(args)

    # we don't need the result type if either "void" or "int" will do
    if not projection and not outArgs:
        return

    # this is the result type for the procedure out arguments and returns
    print("")
    print(dashes)
    print(f"@interface {CGS}{p_name}RT : NSObject", end="")

    legacy = cmd_args["legacy"]

    if legacy:
        print(" {")

        for p in args:
            c_name = p["name"]
            c_type = p["type"]
            kind = p.get("kind", "")
            isNotNull = p["isNotNull"]
            binding = p["binding"] if "binding" in p else ""

            if binding == "out" or binding == "inout":
                objc_type = objc_type_for_arg(c_type, kind, isNotNull)
                print(f"  {objc_type} _{c_name};")

            if usesDatabase:
                print("  int _resultCode;")

            if projection:
                print(f"  {CGS}{p_name}RS *_Nullable _resultSet;")

        print("}")

    first = True
    for p in args:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isNotNull = p["isNotNull"]
        binding = p["binding"] if "binding" in p else ""

        isRef = is_ref_type[c_type]
        objc_type = objc_type_for_arg(c_type, kind, isNotNull)
        retain = "retain" if isRef or not isNotNull else "assign"

        if binding == "out" or binding == "inout":
            if first:
                print("")
                first = False
            print(f"@property (nonatomic, {retain}) {objc_type} {c_name};")

    if usesDatabase:
        print("")
        print("@property (nonatomic, assign) int resultCode;")

    if projection:
        print("")
        print(
            f"@property (nonatomic, retain) {CGS}{p_name}RS *_Nullable resultSet;"
        )

    print("")
    print("@end")
    print(dashes)


def emit_proc_objc_projection_header(proc, attributes):
    p_name = proc["name"]

    # emit the projection type if it needs one
    if "projection" not in proc:
        return

    print("")
    print(dashes)
    print(f"@interface {CGS}{p_name}RS : NSObject", end="")

    legacy = cmd_args["legacy"]

    if legacy:
        print(" {")
        print(f"  {p_name}_result_set_ref _resultSet;")
        print("}")

    print("")

    p_name = proc["name"]
    projection = proc["projection"]
    for p in projection:
        c_name = p["name"]
        c_type = p["type"]
        kind = p.get("kind", "")
        isSensitive = p.get("isSensitive", 0)
        isNotNull = p["isNotNull"]
        hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]

        c_type = objc_type_for_arg(c_type, kind, isNotNull)

        if hasOutResult:
            print(f"@property (nonatomic, readonly) {c_type} {c_name};")
        else:
            print(f"- ({c_type}){c_name}:(NSUInteger)row;")

    identityResult = "true" if "cql:identity" in attributes else "false"

    print("")
    print(f"@property (nonatomic, assign) {p_name}_result_set_ref resultSet;")
    print("@property (nonatomic, readonly) cql_bool hasIdentityColumns;")
    print("@property (nonatomic, readonly) int count;")
    print("")
    print("@end")
    print(dashes)


def emit_proc_objc_header(proc, attributes):
    emit_proc_objc_projection_header(proc, attributes)

    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    emit_proc_objc_return_type(proc)

    commaNeeded = False
    params = ""
    param_names = ""

    # if usesDatabase then we need the db argument, in Objc it goes in __db
    if usesDatabase:
        params += "sqlite3 *_Nonnull __db"
        param_names += "__db"
        commaNeeded = True

    # Now we walk the arguments and emit the objc types for all of the
    # in and inout arguments.  Note that the objc ABI does not use
    # out arguments, they are returned as part procedures result.  So
    # there are no "by ref" arguments in the objc world. This is just
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
            type = objc_types[isNotNull][type]

            if commaNeeded:
                params += ", "
                param_names += ", "

            params += f"{type} {a_name}"
            param_names += a_name
            commaNeeded = True

        # For the out args, all we need to know at this point is
        # that there are some, we'll handle them in the return type.
        if binding == "inout" or binding == "out":
            outArgs = True

    # Out args or a projection demand a return type.
    # If those are missing we need only the result code, or nothing.
    needs_return_type = outArgs or projection
    needs_only_result_code = usesDatabase and not needs_return_type

    print("")
    print(f"// procedure entry point {p_name}")

    # emit a suitable entry point, use int or void return if possible
    # otherwise we have to create the result set type, and return that
    if needs_return_type:
        print(f"{CGS}{p_name}RT *_Nonnull {CGS}Create{p_name}RT({params});")
    elif needs_only_result_code:
        print(f"int {CGS}{p_name}({params});")
    else:
        print(f"void {CGS}{p_name}({params});")
    print("")


# emit all the procedures in a section, the most interesting are those
# that have a projection, those are the ones that return a result set.
def emit_proc_section(section, s_name):
    emit_impl = cmd_args["emit_impl"]
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

        # no codegen for private methods
        if not suppressed:
            if emit_impl:
                emit_proc_objc_impl(proc, attributes)
            else:
                emit_proc_objc_header(proc, attributes)


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

        # pull the flags, starting with whether we will be emitting C or objc
        i = 2

        while i < len(sys.argv):
            if sys.argv[i] == "--header" and i + 1 < len(sys.argv):
                cmd_args["header"] = sys.argv[i + 1]
                i += 2
            elif sys.argv[i] == "--legacy":
                cmd_args["legacy"] = True
                i += 1
            elif sys.argv[i] == "--emit_impl":
                cmd_args["emit_impl"] = True
                i += 1
            else:
                usage()

        # Each generated file gets the standard header.
        # It still uses the Meta header because that was required
        # by the original license even though none of this is actually
        # written by Meta at this point.  The header is in pieces
        # so that a code scanner won't think it's signed
        ss1 = "Signed"
        ss2 = "Source"
        hash = "deadbeef8badf00ddefec8edfacefeed"
        gen = "generated"
        print(f"// @{gen} {ss1}{ss2}<<{hash}>>")

        header = cmd_args["header"]

        if cmd_args["emit_impl"]:
            # The objc implementation
            print(f"#import \"{header}\"")
            print("")
            emit_procs(data)
        else:
            # The objc headers
            print("#pragma once")
            print("")
            print("#import <Foundation/Foundation.h>")
            print("")
            print(f"#import <{header}>")
            print("")
            print("NS_ASSUME_NONNULL_BEGIN")
            print("")
            emit_procs(data)
            print("")
            print("NS_ASSUME_NONNULL_END")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
