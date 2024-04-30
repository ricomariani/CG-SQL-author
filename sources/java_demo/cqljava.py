#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# cqljava.py -> converts CQL JSON format into java classes for interop
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
# This approach is just one way to generate java, there are other ways you can
# create wrapper classes;  The nested class approach with one class per
# procedure works but it isn't the best for everyone.  The naming conventions
# used here are the simplest with the least transform from the original CQL
# but you could reasonably want to camelCase or PascalCase names as needed
# to create something cleaner looking.  All these things are possible with
# not much python at all.  It's also possible to create the JNI code to
# invoke the procedures but this sample has not done so at this time.

import json
import sys


def usage():
    print(("Usage: input.json [options] >result.java\n"
           "\n"
           "--package package_name\n"
           "   specifies the output package name for the java\n"
           "--class outer_class_name\n"
           "   specifies the output class name for the wrapping java class\n"))


# Reference type check
is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True

# Java types for not null cql types
notnull_types = {}
notnull_types["bool"] = "bool"
notnull_types["integer"] = "int"
notnull_types["long"] = "long"
notnull_types["real"] = "double"
notnull_types["object"] = "Object"
notnull_types["blob"] = "byte[]"
notnull_types["text"] = "String"

# Java types for nullable cql types
nullable_types = {}
nullable_types["bool"] = "Boolean"
nullable_types["integer"] = "Integer"
nullable_types["long"] = "Long"
nullable_types["real"] = "Double"
nullable_types["object"] = "Object"
nullable_types["blob"] = "byte[]"
nullable_types["text"] = "String"

# JNI types for not null cql types
jni_notnull_types = {}
jni_notnull_types["bool"] = "jbool"
jni_notnull_types["integer"] = "jint"
jni_notnull_types["long"] = "jlong"
jni_notnull_types["real"] = "jdouble"
jni_notnull_types["object"] = "jobject"
jni_notnull_types["blob"] = "jbyteArray"
jni_notnull_types["text"] = "jstring"

jni_nullable_types = {}
jni_nullable_types["bool"] = "jobject"
jni_nullable_types["integer"] = "jobject"
jni_nullable_types["long"] = "jobject"
jni_nullable_types["real"] = "jobject"
jni_nullable_types["object"] = "jobject"
jni_nullable_types["blob"] = "jbyteArray"
jni_nullable_types["text"] = "jstring"

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
cmd_args["jni_header"] = "something_somethingJNI.h"
cmd_args["cql_header"] = "something.h"


def emit_c_helpers():
    print("""
static jboolean UnboxBoolean(JNIEnv *env, jobject boxedBoolean)
{
    // Get the class of Boolean
    jclass booleanClass = (*env)->GetObjectClass(env, boxedBoolean);

    // Get the method ID for booleanValue() method
    jmethodID booleanValueMethodID = (*env)->GetMethodID(env, booleanClass, "booleanValue", "()Z");

    // Call the booleanValue() method to get the boolean value
    return (*env)->CallBooleanMethod(env, boxedBoolean, booleanValueMethodID);
}

static jint UnboxInteger(JNIEnv *env, jobject boxedInteger)
{
    // Get the class of Integer
    jclass integerClass = (*env)->GetObjectClass(env, boxedInteger);

    // Get the method ID for intValue() method
    jmethodID intValueMethodID = (*env)->GetMethodID(env, integerClass, "intValue", "()I");

    // Call the intValue() method to get the int value
    return (*env)->CallIntMethod(env, boxedInteger, intValueMethodID);
}

static jlong UnboxLong(JNIEnv *env, jobject boxedLong)
{
    // Get the class of Long
    jclass longClass = (*env)->GetObjectClass(env, boxedLong);

    // Get the method ID for longValue() method
    jmethodID longValueMethodID = (*env)->GetMethodID(env, longClass, "longValue", "()J");

    // Call the longValue() method to get the long value
    return (*env)->CallLongMethod(env, boxedLong, longValueMethodID);
}

static jdouble UnboxDouble(JNIEnv *env, jobject boxedDouble)
{
    // Get the class of Double
    jclass doubleClass = (*env)->GetObjectClass(env, boxedDouble);

    // Get the method ID for doubleValue() method
    jmethodID doubleValueMethodID = (*env)->GetMethodID(env, doubleClass, "doubleValue", "()D");

    // Call the doubleValue() method to get the double value
    return (*env)->CallDoubleMethod(env, boxedDouble, doubleValueMethodID);
}
    """)


def emit_proc_c_jni(proc):
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

    if usesDatabase:
        row_meta += "  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL,\n"
        val_fields += "  cql_int32 __rc;\n"
        row_offsets += f"  cql_offsetof({proc_row_type}, __rc),\n"
        field_count += 1

    if projection:
        # the long version of the result set is so that we can have an opaque
        # handle that we can easily fetch and get into the java world
        # the object version is so that ref counting is done correctly
        # the long version won't participate in ref counting which is fine/correct
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

        if ref_field_count > 0:
            print(f"#define {proc_row_type}_refs_count {ref_field_count}")
            print(
                f"#define {proc_row_type}_refs_offset cql_offsetof({proc_row_type}, {first_ref})"
            )
            print("")

        print(f"static cql_uint16 {p_name}_offsets[] = {{ {field_count},")
        print(row_offsets, end="")
        print("};")
        print("")

    package_name = cmd_args["package_name"]
    class_name = cmd_args["class_name"]
    return_type = "jlong" if field_count else "void"
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc
    suffix = "" if field_count == 0 else "JNI"

    print(f"JNIEXPORT {return_type} JNICALL Java_", end="")
    print(f"{package_name}_{class_name}_{p_name}{suffix}(")
    print("  JNIEnv *env,")
    print("  jclass thiz", end="")

    if usesDatabase:
        print(",\n  jlong __db", end="")

    for arg in args:
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        type = arg["type"]

        binding = arg["binding"] if "binding" in arg else "in"
        if binding == "inout" or binding == "in":
            type = jni_notnull_types[
                type] if isNotNull else jni_nullable_types[type]

            print(f",\n  {type} {a_name}", end="")

    print(")")
    print("{")

    if usesDatabase:
        print("  cql_code rc = SQLITE_OK;")

    if projection:
        print(f"  {p_name}_result_set_ref _result_set_ = NULL;")

    if field_count:
        print("  cql_result_set_ref result_set = NULL;")
        print(
            f"  {proc_row_type} *row = ({proc_row_type} *)calloc(1, sizeof({proc_row_type}));"
        )

    # now it's time to make the call
    preamble = ""
    cleanup = ""
    call = "  "

    if usesDatabase:
        call += "rc = "

    call += p_name
    if projection:
        call += "_fetch_results"

    call += "("

    needsComma = False

    if usesDatabase:
        call += "(sqlite3*)__db"
        needsComma = True

    if projection:
        if needsComma:
            call += ", "
        call += "&_result_set_"
        needsComma = True

    print("  // inout bindings not supported yet")

    for arg in args:
        if needsComma:
            call += ","

        needsComma = True
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        a_type = arg["type"]
        isRef = is_ref_type[a_type]

        binding = arg["binding"] if "binding" in arg else "in"
        call += f"/* {binding} */"

        if binding == "inout":
            call += "&"

        if binding == "out":
            # this arg was not mentioned in the list, it is only part of the result
            c_type = c_notnull_types[
                a_type] if isNotNull else c_nullable_types[a_type]
            call += f"&row->{a_name}"
        elif isNotNull and not isRef:
            call += a_name
        elif a_type == "text":
            preamble += f"const char *cString_{a_name} = (*env)->GetStringUTFChars(env, {a_name}, NULL);\n"
            preamble += f"cql_string_ref str_ref_{a_name} = cql_string_ref_new(cString_{a_name});\n"
            preamble += f"(*env)->ReleaseStringUTFChars(env, {a_name}, cString_{a_name});\n"
            cleanup += f"cql_string_release(str_ref_{a_name});\n"
            call += f"str_ref_{a_name}"
        elif a_type == "blob":
            preamble += f"jbyte *bytes_{a_name} = (*env)->GetByteArrayElements(env, {a_name}, NULL);"
            preamble += f"jsize len_{a_name} = (*env)->GetByteArrayLength(env, {a_name}, NULL);"
            preamble += f"cql_blob_ref blob_ref_{a_name} = cql_blob_ref_new(bytes_{a_name}, len_{a_name});\n"
            preamble += f"(*env)->ReleaseByteArrayElements(env, {a_name}, bytes_{a_name});\n"
            cleanup += f"cql_blob_release(blob_ref{a_name});\n"
            call += f"blob_ref_{a_name}"
        elif a_type == "bool":
            preamble += f"  cql_nullable_bool n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !!{a_name}, UnboxBool(env, {a_name}));\n"
            call += f"n_{a_name}"
        elif a_type == "integer":
            preamble += f"  cql_nullable_int32 n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !!{a_name}, UnboxInteger(env, {a_name}));\n"
            call += f"n_{a_name}"
        elif a_type == "long":
            preamble += f"  cql_nullable_int64 n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !!{a_name}, UnboxLong(env, {a_name}));\n"
            call += f"n_{a_name}"
        elif a_type == "real":
            preamble += f"  cql_nullable_double n_{a_name};\n"
            preamble += f"  cql_set_nullable(n_{a_name}, !!{a_name}, UnboxDouble(env, {a_name}));\n"
            call += f"n_{a_name}"
        else:
            call += f" /* unsupported arg type {a_type} isnotnull:{isNotNull} */"

    call += ");"

    if preamble != "":
        print(preamble)
    print(call)
    if cleanup != "":
        print(cleanup)

    if field_count:
        if usesDatabase:
            print("  row->__rc = rc;")

        if projection:
            print(
                "  // let the row take over the reference, we don't release it"
            )
            print("  row->__result = (cql_result_set_ref)_result_set_;")
            print("  row->__result_long = (int64_t)_result_set_;")

        print("")
        print("  cql_fetch_info info = {")
        if usesDatabase:
            print("    .rc = SQLITE_OK,")
        print(f"    .col_offsets = {p_name}_offsets,")
        print(f"    .data_types = {p_name}_return_meta,")

        if ref_field_count:
            print(f"    .refs_count = {proc_row_type}_refs_count,")
            print(f"    .refs_offset = {proc_row_type}_refs_offset,")
        print("    .encode_context_index = -1,")
        print(f"    .rowsize = sizeof({proc_row_type}),")
        print("  };")

        print("  cql_one_row_result(&info, (char *)row, 1, &result_set);")
        print("  return (jlong)result_set;")

    print("}")


# The procedure might have any number of projected columns if it has a result
# We emit them all here
# projected_column
#  name : STRING
#  type : STRING
#  kind : STRING [optional]
#  isSensitive : BOOL [optional]
#  isNotNull" : BOOL
def emit_projection(p_name, projection, attributes):
    col = 0
    for p in projection:
        c_name = p["name"]
        type = p["type"]
        kind = p.get("kind", "")
        isSensitive = p.get("isSensitive", 0)
        isNotNull = p["isNotNull"]

        vaulted_columns = attributes.get("cql:vault_sensitive", None)
        vault_all = vaulted_columns == 1

        getter = getters[type]
        type = notnull_types[type]

        if isNotNull:
            nullable = ""
        else:
            if getter == "String" or getter == "Blob" or getter == "ChildResultSet":
                nullable = ""
            else:
                nullable = "Nullable"

        if getter == "ChildResultSet":
            type = "CQLResultSet"

        isEncoded = False

        if (isSensitive and vaulted_columns is not None
                and (vault_all or c_name in vaulted_columns)):
            isEncoded = True
            # use custom encoded string type for encoded strings
            if type == "String":
                type = "Encoded" + type
                getter = "Encoded" + getter

        print(f"    public {type} get_{c_name}(int row)", end="")
        print(" {")
        print(f"      return mResultSet.get{nullable}{getter}(row, {col});")
        print("    }\n")

        if isEncoded:
            print(f"    public boolean get_{c_name}_IsEncoded()", end="")
            print(" {")
            print(f"      return mResultSet.getIsEncoded({col});")
            print("    }\n")

        col += 1


# The procedure might have any number of out arguments plus its normal returns
# We emit them all here
def emit_proc_return_type(proc):
    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    print(f"  static public final class {p_name}Results extends CQLViewModel {{")
    print(f"    public {p_name}Results(CQLResultSet resultSet)", end="")
    print("    {")
    print(f"       super(resultSet);")
    print("    }\n")

    col = 0
    for p in args:
        c_name = p["name"]
        type = p["type"]
        isNotNull = p["isNotNull"]

        binding = p["binding"] if "binding" in p else ""

        if binding == "out" or binding == "inout":
            getter = getters[type]
            type = notnull_types[type]

            if isNotNull:
                nullable = ""
            else:
                if getter == "String" or getter == "Blob" or getter == "ChildResultSet":
                    nullable = ""
                else:
                    nullable = "Nullable"

            if getter == "ChildResultSet":
                type = "CQLResultSet"

            print(f"    public {type} get_{c_name}()", end="")
            print(" {")
            print(f"      return mResultSet.get{nullable}{getter}(0, {col});")
            print("    }\n")

            col += 1

    if usesDatabase:
        print(f"    public int get_result_code() {{")
        print(f"      return mResultSet.getInteger(0, {col});")
        print("    }\n")
        col += 1

    if projection:
        print(f"    public {p_name}ViewModel get_result_set() {{")
        print(f"      return new {p_name}ViewModel(new CQLResultSet(mResultSet.getLong(0, {col})));")
        print("    }\n")
        col += 1

    print("    public int getCount() {")
    print(f"      return 1;")
    print("    }\n")
    print("    @Override")
    print("    protected boolean hasIdentityColumns() {")
    print(f"      return false;")
    print("    }")
    print("  }\n")


def emit_proc_java_jni(proc):
    p_name = proc["name"]
    args = proc["args"]
    # if usesDatabase is missing it's a query type and they all use the db
    usesDatabase = proc["usesDatabase"] if "usesDatabase" in proc else True
    projection = "projection" in proc

    emit_proc_return_type(proc)

    # Generate Java JNI method declaration

    commaNeeded = False
    params = ""
    param_names = ""

    if usesDatabase:
        params += "long __db"
        param_names += "__db"
        commaNeeded = True

    outArgs = False
    for arg in args:
        a_name = arg["name"]
        isNotNull = arg["isNotNull"]
        type = arg["type"]

        binding = arg["binding"] if "binding" in arg else "in"
        if binding == "inout" or binding == "in":
            type = notnull_types[type] if isNotNull else nullable_types[type]

            if commaNeeded:
                params += ", "
                param_names += ", "

            params += f"{type} {a_name}"
            param_names += a_name
            commaNeeded = True

        if binding == "inout" or binding == "out":
            outArgs = True

    needs_result = usesDatabase or outArgs or projection

    print(f"  // procedure entry point {p_name}")
    suffix = ""
    return_type = "void"

    if needs_result:
        suffix = "JNI"
        return_type = "long"
        print(f"  public static {p_name}Results {p_name}({params}) {{")
        print(f"     return new {p_name}Results(new CQLResultSet({p_name}JNI({param_names})));")
        print("  }\n")

    print(f"  public static native {return_type} {p_name}{suffix}(", end="")
    print(params, end="")
    print(");\n")


# Here we emit all the information for the procedures that are known
# this is basic info about the name and arguments as well as dependencies.
# For any chunk of JSON that has the "dependencies" sub-block
# (see CQL JSON docs) we emit the table dependency info
# by following the "usesTables" data.  Note that per docs
# this entry is not optional!
def emit_procinfo(section, s_name):
    emit_c = cmd_args["emit_c"]
    for src in section:
        p_name = src["name"]

        # for now only procs with a result type, like before
        # we'd like to emit JNI helpers for other procs too, but not now

        if "projection" in src and not emit_c:
            print(f"  static public final class {p_name}ViewModel extends CQLViewModel {{")
            print(f"    public {p_name}ViewModel(CQLResultSet resultSet) {{")
            print(f"       super(resultSet);")
            print("    }\n")

            alist = src.get("attributes", [])
            attributes = {}
            for attr in alist:
                k = attr["name"]
                v = attr["value"]
                attributes[k] = v

            emit_projection(p_name, src["projection"], attributes)

            identityResult = "true" if "cql:identity" in attributes else "false"

            print("    @Override")
            print("    protected boolean hasIdentityColumns() {")
            print(f"      return {identityResult};")
            print("    }\n")

            print("    public int getCount() {")
            print(f"      return mResultSet.getCount();")
            print("    }")
            print("  }\n")

        if emit_c:
            emit_proc_c_jni(src)
        else:
            emit_proc_java_jni(src)


# This walks the various JSON chunks and emits them into the equivalent table:
# * first we walk the tables, this populates:
#  * we use emit_procinfo for each chunk of procedures that has dependencies
#     * this is "queries", "inserts", "updates", "deletes", "general", and "generalInserts"
#     * see the CQL JSON docs for the meaning of each of these sections
#       * these all have the "dependencies" block in their JSON
def emit_procs(data):
    emit_procinfo(data["queries"], "queries")
    emit_procinfo(data["deletes"], "deletes")
    emit_procinfo(data["inserts"], "inserts")
    emit_procinfo(data["generalInserts"], "generalInserts")
    emit_procinfo(data["updates"], "updates")
    emit_procinfo(data["general"], "general")


def main():
    jfile = sys.argv[1]
    with open(jfile) as json_file:
        data = json.load(json_file)

        i = 2
        if sys.argv[i] == "--emit_c":
            cmd_args["emit_c"] = True
            i += 1

        while i + 2 <= len(sys.argv):
            if sys.argv[i] == "--class":
                cmd_args["class_name"] = sys.argv[i + 1]
            elif sys.argv[i] == "--package":
                cmd_args["package_name"] = sys.argv[i + 1]
            elif sys.argv[i] == "--jni_header":
                cmd_args["jni_header"] = sys.argv[i + 1]
            elif sys.argv[i] == "--cql_header":
                cmd_args["cql_header"] = sys.argv[i + 1]
            else:
                usage()
            i += 2

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
        jni_header = cmd_args["jni_header"]
        cql_header = cmd_args["cql_header"]

        if cmd_args["emit_c"]:
            print("")
            print("#include \"cqlrt.h\"")
            print(f"#include \"{jni_header}\"")
            print(f"#include \"{cql_header}\"")
            print("")
            emit_c_helpers()
            emit_procs(data)
        else:

            print(f"package {package_name};\n\n")

            print("import com.acme.cgsql.CQLResultSet;\n")
            print("import com.acme.cgsql.CQLViewModel;\n")
            print("import com.acme.cgsql.EncodedString;\n")

            print(f"public class {class_name}")
            print("{")
            print("  static {")
            print("    System.loadLibrary(\"", end="")
            print(class_name, end="")
            print("\");")
            print("  }")
            print("")

            emit_procs(data)
            print("}")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        usage()
    else:
        main()
