#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# cqlobjc.py -> converts CQL JSON format into interop functions for Objective-C
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

import json
import sys

def usage():
    print(
        "Usage: input.json [options] >result.h\n"
        "\n"
        "--cql_header header_file  (this is mandatory)\n"
        "    specifies the CQL generated header file to include in the generated C code\n"
    )
    sys.exit(0)

# Java types for not null cql types
notnull_types = {}
notnull_types["bool"] = "cql_bool"
notnull_types["integer"] = "cql_int32"
notnull_types["long"] = "cql_int64"
notnull_types["real"] = "double"
notnull_types["object"] = "NSObject *"
notnull_types["blob"] = "NSData *"
notnull_types["text"] = "NSString *"

# Java types for nullable cql types
nullable_types = {}
nullable_types["bool"] = "NSNumber *_Nullable"
nullable_types["integer"] = "NSNumber *_Nullable"
nullable_types["long"] = "NSNumber *_Nullable"
nullable_types["real"] = "NSNumber *_Nullable"
nullable_types["object"] = "NSObject *_Nullable"
nullable_types["blob"] = "NSData *_Nullable"
nullable_types["text"] = "NSString *_Nullable"

notnull_conv = {}
notnull_conv["bool"] = ""
notnull_conv["integer"] = ""
notnull_conv["long"] = ""
notnull_conv["real"] = ""
notnull_conv["object"] = "(__bridge NSObject *)"
notnull_conv["blob"] = "(__bridge NSData *)"
notnull_conv["text"] = "(__bridge NSString *)"

nullable_conv = {}
nullable_conv["bool"] = "@"
nullable_conv["integer"] = "@"
nullable_conv["long"] = "@"
nullable_conv["real"] = "@"
nullable_conv["object"] = "(__bridge NSObject *)"
nullable_conv["blob"] = "(__bridge NSData *)"
nullable_conv["text"] = "(__bridge NSString *)"

# Storage for the various command line arguments
cmd_args = {}
cmd_args["cql_header"] = ""

# The procedure might have any number of projected columns if it creates
# a result set.  We emit a class for the reading such a result set here.
#
# The relevant parts of the JSON are these fragments:
# projected_column
#  name : STRING
#  type : STRING
#  kind : STRING [optional]
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
        isNotNull = p["isNotNull"]
        hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]

        objc_type = notnull_types[c_type] if isNotNull else nullable_types[c_type]
        conv = notnull_conv[c_type] if isNotNull else nullable_conv[c_type]

        bool_fix = "" if objc_type != "cql_bool" else " ? YES : NO"

        row_arg = "" if hasOutResult else ", row"
        row_param = "" if hasOutResult else ", cql_int32 row"

        print(f"static inline {objc_type} {CGS}{p_name}_get_{c_name}({CGS}{p_name} *resultSet{row_param})")
        print("{")
        print(f"  {p_name}_result_set_ref cResultSet = {p_name}_from_{CGS}{p_name}(resultSet);")
        print(f"  return {conv}{p_name}_get_{c_name}(cResultSet{row_arg}){bool_fix};")
        print("}")
        print("")

CGS = "CGS_"

def emit_proc_c_objc(proc, attributes):
    p_name = proc["name"]
    # for now only procs with a result type, like before
    # we'd like to emit JNI helpers for other procs too, but not now

    if "projection" not in proc:
        return

    print(f"@class {CGS}{p_name};")
    print("")
    # we don't actually emit the interfaces anywhere at this time, this was done at Meta
    # and there is no open source version of this yet.  The idea is that the ObjC classes
    # with common shape can implement an interface to be exchangeable.  This could also
    # be done in the dotnet and java output but it isn't... yet.
    print("#ifdef CQL_EMIT_OBJC_INTERFACES")
    print(f"@interface {CGS}{p_name}")
    print("@end")
    print("#endif")
    print("")

    # conversion methods to go from the result set reference to the Arc friendly type
    print(f"static inline {CGS}{p_name} *{CGS}{p_name}_from_{p_name}({p_name}_result_set_ref resultSet)")
    print("{")
    print(f"  return (__bridge {CGS}{p_name} *)resultSet;")
    print("}")
    print("")
    print(f"static inline {p_name}_result_set_ref {p_name}_from_{CGS}{p_name}({CGS}{p_name} *resultSet)")
    print("{")
    print(f"  return (__bridge {p_name}_result_set_ref)resultSet;")
    print("}")
    print("")

    emit_result_set_projection(proc, attributes)

    hasOutResult = "hasOutResult" in proc and proc["hasOutResult"]
    row_arg = "" if hasOutResult else ", row"
    row_param = "" if hasOutResult else ", cql_int32 row"

    print(f"static inline cql_int32 {CGS}{p_name}_result_count({CGS}{p_name} *resultSet)")
    print("{")
    print(f"  return {p_name}_result_count({p_name}_from_{CGS}{p_name}(resultSet));")
    print("}")

    # the copy method isn't cheap so it's often elided
    if "cql:generate_copy"  in attributes:
        print(f"static inline {CGS}{p_name} *{CGS}{p_name}_copy({CGS}{p_name} *resultSet, cql_int32 from, cql_int32 count)")
        print("{")
        print(f"  {p_name}_result_set_ref copy;")
        print(f"  {p_name}_copy({p_name}_from_{CGS}{p_name}(resultSet), &copy, from, count);")
        print(f"  cql_result_set_note_ownership_transferred(copy);")
        print(f"  return (__bridge_transfer {CGS}{p_name} *)copy;")
        print("}")

    print(f"static inline NSUInteger {CGS}{p_name}_row_hash({CGS}{p_name} *resultSet{row_param})")
    print("{")
    print(f"  return {p_name}_row_hash({p_name}_from_{CGS}{p_name}(resultSet){row_arg});")
    print("}")

    r1_arg = "" if hasOutResult else ", row1"
    r2_arg = "" if hasOutResult else ", row2"
    r1_param = "" if hasOutResult else ", cql_int32 row1"
    r2_param = "" if hasOutResult else ", cql_int32 row2"

    print(f"static inline BOOL {CGS}{p_name}_row_equal({CGS}{p_name} *resultSet1{r1_param}, {CGS}{p_name} *resultSet2{r2_param})")
    print("{")
    print(f"  return {p_name}_row_equal({p_name}_from_{CGS}{p_name}(resultSet1){r1_arg}, {p_name}_from_{CGS}{p_name}(resultSet2){r2_arg});")
    print("}")

# emit all the procedures in a section, any of the sections might have projections
# typically it's just "queries" but there's no need to assume that, we can just look
def emit_proc_section(section, s_name):
    for proc in section:
        # we unwrap the attributes array into a map for easy access
        alist = proc.get("attributes", [])
        attributes = {}
        for attr in alist:
            k = attr["name"]
            v = attr["value"]
            attributes[k] = v

        # no codegen for private methods
        if "cql:private" not in attributes:
            # emit the C code for the JNI entry points and the supporting metadata
            emit_proc_c_objc(proc, attributes)

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

        # pull the flags, starting with whether we will be emitting C or java
        i = 2
        if sys.argv[i] == "--emit_c":
            cmd_args["emit_c"] = True
            i += 1

        # these are the various fragments we might need, we need all the parts
        # to generate the C.  The first two are enough for the java, there are
        # defaults but they are kind of useless.
        while i + 2 <= len(sys.argv):
            if sys.argv[i] == "--cql_header":
                cmd_args["cql_header"] = sys.argv[i + 1]
            else:
                usage()
            i += 2

        if cmd_args["cql_header"] == "":
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

        cql_header = cmd_args["cql_header"]

        # The C code gen has the standard header files per the flags
        # after which we emit the JNI helpers to unbox int, long, etc.
        # Finally we emit the actual JNI entry points to invoke the CQL.
        # These convert the java types to CQL types and back.
        print("#pragma once")
        print("")
        print("#import <Foundation/Foundation.h>")
        print("")
        print(f"#import <{cql_header}>")
        print("")
        print("NS_ASSUME_NONNULL_BEGIN")
        emit_procs(data)
        print("")
        print("NS_ASSUME_NONNULL_END")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
