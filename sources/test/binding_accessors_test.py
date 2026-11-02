#!/usr/bin/env python3

# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

SOURCES = pathlib.Path(__file__).resolve().parents[1]

FIELDS = [
    ("safe", "safe"),
    ("Xname", "Xname"),
    ("class", "class"),
    ("a b", "X_aX20b"),
    ("foo\\bar", "X_fooX5cbar"),
    ("a-b", "X_aX2db"),
    ("caf\u00e9", "X_cafXc3Xa9"),
    ("face\U0001f600", "X_faceXf0X9fX98X80"),
    ("aX b", "X_aX58X20b"),
    ('q"uote', "X_qX22uote"),
    ("a`b", "X_aX60b"),
    ("a\u200cb", "X_aXe2X80X8cb"),
    ("ab", "ab"),
    ("Count", "Count"),
    ("other", "other"),
    ("hasIdentityColumns", "hasIdentityColumns"),
    ("result_set_ref", "result_set_ref"),
    ("dealloc", "dealloc"),
    ("1field", "X_1field"),
    ("switch", "switch"),
    ("setResult_set_ref", "setResult_set_ref"),
    ("X_prefix", "X_X58_prefix"),
]


def prepare_metadata(compiler, output_dir):
    select = "select " + ", ".join(
        f"{col} as `{name.replace('`', '``')}`" if name not in
        ("safe", ) else f"{col} as {name}"
        for col, (name, _) in enumerate(FIELDS)) + ";"
    source = output_dir / "java_projection.sql"
    metadata = output_dir / "java_projection.json"
    source.write_text(
        "proc row_results()\nbegin\n" + select + "\nend;\n"
        "proc single_row()\nbegin\n"
        "declare C cursor for " + select + "\nfetch C;\nout C;\nend;\n"
        # C# Count's ordinal suffix is already another column name.
        "proc collisions()\nbegin\n"
        "select 0 as Count_2, 1 as spare, 2 as Count;\nend;\n"
        "proc single_count()\nbegin\n"
        "declare C cursor for select 0 as count;\nfetch C;\nout C;\nend;\n"
        "proc nullable_types()\nbegin\n"
        "declare C cursor like (n_b bool, i_n integer, l_l long int,"
        " r_r real, t_t text, b_b blob, o_o object);\n"
        "fetch C from values (null, null, null, null, null, null, null);\n"
        "out C;\nend;\n"
        "proc nonnull_types()\nbegin\n"
        "declare C cursor like (n_b bool not null, l_l long int not null,"
        " r_r real not null, t_t text not null);\n"
        "fetch C from values (1, 2L, 3.5, 'text');\nout C;\nend;\n",
        encoding="utf-8",
    )
    subprocess.run(
        [
            compiler, "--in",
            str(source), "--rt", "json_schema", "--cg",
            str(metadata)
        ],
        check=True,
    )
    document = json.loads(metadata.read_text(encoding="utf-8"))
    procs = {
        proc["name"]: proc
        for category in ("queries", "deletes", "inserts", "generalInserts",
                         "updates", "general")
        for proc in document[category]
    }
    for name in ("row_results", "single_row"):
        assert [col["name"] for col in procs[name]["projection"]
                ] == [field for field, _ in FIELDS], procs[name]
    assert procs["single_row"]["hasOutResult"] == 1, procs["single_row"]
    assert [col["name"] for col in procs["collisions"]["projection"]
            ] == ["Count_2", "spare", "Count"], procs["collisions"]
    assert [col["name"] for col in procs["nullable_types"]["projection"]
            ] == ["n_b", "i_n", "l_l", "r_r", "t_t", "b_b", "o_o"]
    duplicate = output_dir / "quoted_duplicate.sql"
    duplicate.write_text(
        "proc duplicate_names()\nbegin\n"
        "select 1 as XName, 2 as `XName`;\nend;\n",
        encoding="ascii")
    rejected = subprocess.run(
        [compiler, "--in", str(duplicate), "--sem"],
        stderr=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True)
    assert rejected.returncode != 0 and "CQL0180" in rejected.stderr, rejected
    return metadata


def check_generated_java(generated):
    expected = {}
    for proc, suffixes, row_arg, row_value in [
        ("row_results", [suffix for _, suffix in FIELDS], "int row", "row"),
        ("single_row", [suffix for _, suffix in FIELDS], "", "0"),
        ("collisions", ["Count_2", "spare", "Count"], "int row", "row"),
        ("single_count", ["count"], "", "0"),
    ]:
        block = generated.split(f"static public final class {proc}ViewModel",
                                1)[1].split("static public final class", 1)[0]
        methods = re.findall(
            r"public int (get_\S+)\((int row)?\) \{\s*"
            r"return mResultSet.getInteger\((row|0), (\d+)\);\s*\}",
            block,
        )
        wanted = [("get_" + suffix, row_arg, row_value, str(col))
                  for col, suffix in enumerate(suffixes)]
        assert methods == wanted, (proc, wanted, methods)
        expected[proc] = [method[0] for method in wanted]
    return expected


def check_java_execution(generated_source, output_dir, expected):
    javac = shutil.which("javac")
    java = shutil.which("java")
    if javac is None or java is None:
        print(
            "SKIP: Java compilation/execution requires a JDK; "
            "CQL metadata and exact generated getter checks passed.",
            file=sys.stderr,
        )
        return

    demo = SOURCES / "java_demo"
    # Compile against the real runtime API first; a test double must not hide
    # signature errors in the complete generated Java wrapper.
    subprocess.run(
        [
            javac, "-d",
            str(output_dir / "java_projection_api"), "-sourcepath",
            str(demo),
            str(generated_source)
        ],
        check=True,
    )
    stub = output_dir / "CQLResultSet.java"
    stub.write_text(
        """package com.acme.cgsql;
public final class CQLResultSet {
  public CQLResultSet(long ref) {}
  public int getInteger(int row, int column) { return row * 1000 + column; }
  public int getCount() { return 10; }
  public long getLong(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public boolean getBoolean(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public double getDouble(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public Boolean getNullableBoolean(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public Integer getNullableInteger(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public Long getNullableLong(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public Double getNullableDouble(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public String getString(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public byte[] getBlob(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public CQLResultSet getChildResultSet(int row, int column) {
    throw new UnsupportedOperationException();
  }
  public long rowHashCode(int row) {
    throw new UnsupportedOperationException();
  }
  public boolean rowsEqual(int row, CQLResultSet other, int otherRow) {
    throw new UnsupportedOperationException();
  }
  public boolean rowsSame(int row, CQLResultSet other, int otherRow) {
    throw new UnsupportedOperationException();
  }
}
""",
        encoding="ascii",
    )
    harness = output_dir / "GetterChecks.java"
    # The double records row and ordinal in the returned value. Access only
    # nested ViewModels so no outer JNI library initializer is invoked.
    calls = "".join('    check("' + proc + '", GetterForm.' +
                    ("SINGLE_ROW" if proc.startswith("single_") else "ROWS") +
                    ", new String[]{" + ", ".join('"' + name + '"'
                                                  for name in names) + "});\n"
                    for proc, names in expected.items())
    harness.write_text(
        """import com.acme.cgsql.CQLResultSet;
import java.lang.reflect.Method;
public class GetterChecks {
  enum GetterForm { ROWS, SINGLE_ROW }
  static void check(String proc, GetterForm form, String[] getters) throws Exception {
    Class<?> modelClass = Class.forName("sample.Bindings$" + proc + "ViewModel");
    Object model = modelClass.getConstructor(CQLResultSet.class)
        .newInstance(new CQLResultSet(0));
    int row = form == GetterForm.ROWS ? 7 : 0;
    for (int col = 0; col < getters.length; col++) {
      Method getter = form == GetterForm.ROWS
          ? modelClass.getMethod(getters[col], int.class)
          : modelClass.getMethod(getters[col]);
      Object actual = form == GetterForm.ROWS
          ? getter.invoke(model, row) : getter.invoke(model);
      int expected = row * 1000 + col;
      if (!Integer.valueOf(expected).equals(actual)) {
        throw new AssertionError(proc + "." + getters[col] + ": " + actual);
      }
    }
  }
  public static void main(String[] args) throws Exception {
""" + calls + """  }
}
""",
        encoding="ascii",
    )
    classes = output_dir / "java_projection_execution"
    subprocess.run(
        [
            javac, "-d",
            str(classes),
            str(stub),
            str(demo / "com/acme/cgsql/CQLViewModel.java"),
            str(generated_source),
            str(harness)
        ],
        check=True,
    )
    subprocess.run([java, "-cp", str(classes), "GetterChecks"], check=True)
    print("Java API compilation and getter row/ordinal execution passed.")


def generate(generator, metadata, *args):
    return subprocess.run(
        [sys.executable,
         str(SOURCES / generator),
         str(metadata), *args],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.decode("utf-8")


def expected_names(language):
    names = {
        "row_results": [suffix for _, suffix in FIELDS],
        "single_row": [suffix for _, suffix in FIELDS],
        "collisions": ["Count_2", "spare", "Count"],
        "single_count": ["count"],
    }
    if language == "cs":
        names["collisions"] = ["Count_2", "spare", "Count_2_"]
        for proc in ("row_results", "single_row"):
            names[proc][13] = "Count_13"
    if language == "objc":
        names["single_row"][15:18] = [
            "hasIdentityColumns_15", "result_set_ref_16", "dealloc_17"
        ]
        names["single_count"] = ["count_0"]
        names["single_row"][19] = "X_switch"
        names["row_results"][20] = "setResult_set_ref_20"
    return names


def check_csharp(generated, output_dir):
    expected = expected_names("cs")
    for proc, names in expected.items():
        block = generated.split(f"sealed class {proc}ViewModel",
                                1)[1].split("sealed class", 1)[0]
        row_arg, row = ("", "0") if proc.startswith("single_") else ("int row",
                                                                     "row")
        methods = re.findall(
            r"public int (get_\S+)\((int row)?\) \{\s*"
            r"return mResultSet.getInteger\((row|0), (\d+)\);\s*\}", block)
        assert methods == [("get_" + name, row_arg, row, str(col))
                           for col, name in enumerate(names)], (proc, methods)

    dotnet = shutil.which("dotnet")
    if dotnet is None:
        print("SKIP: C# compilation/execution requires a .NET SDK.",
              file=sys.stderr)
        return
    sdks = subprocess.check_output([dotnet, "--list-sdks"], text=True)
    majors = [
        int(major) for major in re.findall(r"^(\d+)\.\d+\.\S+ ", sdks, re.M)
    ]
    if not majors:
        print("SKIP: C# compilation/execution requires a .NET SDK.",
              file=sys.stderr)
        return
    target = f"net{max(majors)}.0"
    runtime = (SOURCES / "dotnet_demo/CQLInterop.cs").read_text()
    env = dict(os.environ,
               DOTNET_CLI_TELEMETRY_OPTOUT="1",
               DOTNET_NOLOGO="1",
               DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1",
               DOTNET_GENERATE_ASPNET_CERTIFICATE="false",
               MSBUILDDISABLENODEREUSE="1")
    for name, code, executable in [
        ("api", runtime, False),
        ("execution", """using System;
namespace CGSQL {
public sealed class CQLResultSet {
  public CQLResultSet(long value) {}
  public int getInteger(int row, int col) => row * 1000 + col;
  public int getCount() => 10;
  public long getLong(int row, int col) => throw new NotSupportedException();
  public bool getBoolean(int row, int col) => throw new NotSupportedException();
  public double getDouble(int row, int col) => throw new NotSupportedException();
  public bool? getNullableBoolean(int row, int col) => throw new NotSupportedException();
  public int? getNullableInteger(int row, int col) => throw new NotSupportedException();
  public long? getNullableLong(int row, int col) => throw new NotSupportedException();
  public double? getNullableDouble(int row, int col) => throw new NotSupportedException();
  public string getString(int row, int col) => throw new NotSupportedException();
  public byte[] getBlob(int row, int col) => throw new NotSupportedException();
  public CQLResultSet getChildResultSet(int row, int col) => throw new NotSupportedException();
  public long rowHashCode(int row) => throw new NotSupportedException();
  public bool rowsEqual(int row, CQLResultSet other, int otherRow) => throw new NotSupportedException();
  public bool rowsSame(int row, CQLResultSet other, int otherRow) => throw new NotSupportedException();
}
public abstract class CQLViewModel""" +
         runtime.split("public abstract class CQLViewModel", 1)[1], True),
    ]:
        directory = output_dir / ("csharp_projection_" + name)
        directory.mkdir(exist_ok=True)
        (directory / "Bindings.cs").write_text(generated, encoding="utf-8")
        (directory / "Runtime.cs").write_text(code, encoding="utf-8")
        (directory / "GetterChecks.csproj").write_text(
            '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
            f'<TargetFramework>{target}</TargetFramework>'
            f'<OutputType>{"Exe" if executable else "Library"}</OutputType>'
            '</PropertyGroup></Project>',
            encoding="ascii")
        (directory / "NuGet.Config").write_text(
            '<configuration><packageSources><clear /></packageSources></configuration>',
            encoding="ascii")
        if executable:
            calls = "".join('    Check("' + proc + '", ' +
                            ("GetterForm.SingleRow" if proc.
                             startswith("single_") else "GetterForm.Rows") +
                            ', new string[] {' +
                            ", ".join('"get_' + method + '"'
                                      for method in names) + '});\n'
                            for proc, names in expected.items())
            (directory / "GetterChecks.cs").write_text("""using System;
using CGSQL;
class GetterChecks {
  enum GetterForm { Rows, SingleRow }
  static void Check(string proc, GetterForm form, string[] names) {
    bool singleRow = form == GetterForm.SingleRow;
    Type type = typeof(Bindings).GetNestedType(proc + "ViewModel");
    object model = Activator.CreateInstance(type, new CQLResultSet(0));
    int row = singleRow ? 0 : 7;
    for (int col = 0; col < names.Length; col++) {
      object actual = type.GetMethod(names[col]).Invoke(model,
          singleRow ? new object[0] : new object[] {row});
      if (!Equals(actual, row * 1000 + col)) throw new Exception(names[col]);
    }
    if (!Equals(type.GetProperty("Count").GetValue(model), 10))
      throw new Exception("Count property");
  }
  static void Main() {
""" + calls + """  }
}
""",
                                                       encoding="ascii")
        subprocess.run([
            dotnet, "build",
            str(directory / "GetterChecks.csproj"), "--nologo", "--verbosity",
            "quiet", "-p:UseSharedCompilation=false"
        ],
                       check=True,
                       env=env)
        if executable:
            subprocess.run([
                dotnet,
                str(directory / f"bin/Debug/{target}/GetterChecks.dll")
            ],
                           check=True,
                           env=env)
    print("C# API compilation and getter row/ordinal execution passed.")


def check_objc(cf, header, impl, compiler, output_dir):
    for language, generated in [("cf", cf), ("objc", impl)]:
        for proc, names in expected_names(language).items():
            row_arg = "" if proc.startswith("single_") else ", row"
            result = "cResultSet" if language == "cf" else "_result_set_ref"
            for col, name in enumerate(names):
                native_name = expected_names("cf")[proc][col]
                getter = f"{proc}_get_{native_name}({result}{row_arg})"
                if language == "cf":
                    signature = f"CGS_{proc}_get_{name}"
                    block = generated.split(signature + "(",
                                            1)[1].split("}", 1)[0]
                else:
                    suffix = "" if proc.startswith(
                        "single_") else ":(NSUInteger)row"
                    signature = f"- (cql_int32){name}{suffix}"
                    block = generated.split(f"@implementation CGS{proc}RS",
                                            1)[1]
                    block = block.split(signature, 1)[1].split("}", 1)[0]
                    declaration = (f"cql_int32 {name};" if
                                   proc.startswith("single_") else signature +
                                   ";")
                    interface = header.split(f"@interface CGS{proc}RS",
                                             1)[1].split("@end", 1)[0]
                    assert declaration in interface, (proc, declaration)
                assert f"return {getter};" in block, (signature, block)
        for proc, columns in [
            ("nullable_types",
             ["n_b", "i_n", "l_l", "r_r", "t_t", "b_b", "o_o"]),
            ("nonnull_types", ["n_b", "l_l", "r_r", "t_t"]),
        ]:
            block = generated.split(
                f"CGS_{proc}_get_"
                if language == "cf" else f"@implementation CGS{proc}RS", 1)[1]
            block = block.split(
                f"CGS_{proc}_result_count" if language == "cf" else "@end",
                1)[0]
            for col, native_name in enumerate(columns):
                getter = f"{proc}_get_{native_name}"
                if proc == "nullable_types" and col < 4:
                    guard = (f"{getter}_is_null({result}) ? nil : "
                             f"@({getter}_value({result}))")
                    assert guard in block, guard
                else:
                    assert f"{getter}({result})" in block, (proc, getter)
            if proc == "nonnull_types":
                assert ") ? YES : NO" in block, block

    native = output_dir / "binding_projection.h"
    subprocess.run([
        compiler, "--in",
        str(output_dir / "java_projection.sql"), "--cg",
        str(native),
        str(output_dir / "binding_projection.c"), "--cqlrt", "cqlrt_cf.h"
    ],
                   check=True)
    native_header = native.read_text(encoding="utf-8")
    assert "row_results_get_Xname(" in native_header
    assert "row_results_get_X_X58name(" not in native_header
    assert "row_results_get_X_X58_prefix(" in native_header
    assert "row_results_get_X_1field(" in native_header
    (output_dir / "binding_cf.h").write_text(cf, encoding="utf-8")
    (output_dir / "binding_objc.h").write_text(header, encoding="utf-8")
    implementation = output_dir / "binding_objc.m"
    implementation.write_text(impl, encoding="utf-8")
    clang = shutil.which("clang")
    config = shutil.which("gnustep-config")
    if clang is None or config is None:
        print(
            "SKIP: Objective-C compilation requires Clang and GNUstep "
            "for the existing Linux minimum-compile mode.",
            file=sys.stderr)
        return
    import shlex
    flags = [
        flag for flag in shlex.split(
            subprocess.check_output([config, "--objc-flags"], text=True))
        if flag not in ("-MMD", "-MP")
    ]
    # Follow the repository's Linux minimum-compile scripts, without rebuilding
    # the demos in place or modifying their checked-in generated files.
    flags += [
        "-DCQL_OBJC_MIN_COMPILE",
        "-Werror=implicit-function-declaration",
        "-Werror=incomplete-implementation",
        "-Werror=objc-property-implementation",
        "-Wno-arc-bridge-casts-disallowed-in-nonarc",
        "-I/usr/lib/gcc/x86_64-linux-gnu/11/include",
        "-I" + str(SOURCES),
        "-I" + str(SOURCES / "cqlrt_cf"),
        "-I" + str(output_dir),
    ]
    consumer = output_dir / "binding_cf.m"
    consumer.write_text('#import "binding_cf.h"\n', encoding="ascii")
    for source in (consumer, implementation):
        subprocess.run([clang, *flags, "-fsyntax-only",
                        str(source)],
                       check=True)
    print(
        "Both Objective-C wrappers compile against actual generated C headers."
    )
    check_objc_execution(clang, config, flags, implementation, output_dir)


def check_objc_execution(clang, config, flags, implementation, output_dir):
    import shlex
    calls = []
    for proc, names in expected_names("objc").items():
        calls += [
            f"  CGS{proc}RS *{proc} = [CGS{proc}RS new];",
            f"  {proc}.result_set_ref = (cql_result_set_ref)&result;",
        ]
        row = 0 if proc.startswith("single_") else 7
        for col, name in enumerate(names):
            calls.append(
                f"  assert([{proc} {name}{'' if row == 0 else ':7'}] == {row * 1000 + col});"
            )
        calls += [f"  assert({proc}.count == 10);", f"  [{proc} release];"]
    for proc, names in expected_names("cf").items():
        row = 0 if proc.startswith("single_") else 7
        for col, name in enumerate(names):
            calls.append(
                f"  assert(CGS_{proc}_get_{name}((CGS_{proc} *)&result"
                f"{'' if row == 0 else ', 7'}) == {row * 1000 + col});")
    nullable_names = [
        "n_b",
        "i_n",
        "l_l",
        "r_r",
        "t_t",
        "b_b",
        "o_o",
    ]
    calls += [
        "  CGSnullable_typesRS *nullable = [CGSnullable_typesRS new];",
        "  nullable.result_set_ref = (cql_result_set_ref)&result;",
        "  null_values = 1;",
    ]
    for name in nullable_names:
        calls += [
            f"  assert([nullable {name}] == nil);",
            f"  assert(CGS_nullable_types_get_{name}((CGS_nullable_types *)&result) == nil);",
        ]
    calls += [
        "  null_values = 0;",
        "  assert([[nullable i_n] intValue] == 1);",
        "  assert([CGS_nullable_types_get_l_l((CGS_nullable_types *)&result) longLongValue] == 2);",
        "  assert([[nullable r_r] doubleValue] == 3.5);",
        "  [nullable release];",
        "  CGSnonnull_typesRS *nonnull = [CGSnonnull_typesRS new];",
        "  nonnull.result_set_ref = (cql_result_set_ref)&result;",
        "  assert([nonnull n_b] == YES);",
        "  assert(CGS_nonnull_types_get_n_b((CGS_nonnull_types *)&result) == YES);",
        "  assert([nonnull l_l] == 1);",
        "  assert(CGS_nonnull_types_get_r_r((CGS_nonnull_types *)&result) == 2.5);",
        "  assert([[nonnull t_t] isEqualToString:@\"text\"]);",
        "  [nonnull release];",
    ]
    harness = output_dir / "binding_objc_checks.m"
    counts = "".join(
        f"cql_int32 {proc}_result_count({proc}_result_set_ref ref) {{\n"
        "  return cql_result_set_get_count(ref);\n}\n"
        for proc in (*expected_names("cf"), "nullable_types", "nonnull_types"))
    harness.write_text(f"#define MAX_COLS {len(FIELDS)}\n" +
                       """#import "binding_cf.h"
#import "binding_objc.h"
static cql_result_set result;
static int null_values;
static void check(cql_result_set_ref ref, int row, int col) {
  assert(ref == (cql_result_set_ref)&result && row >= 0 && row < 10);
  assert(col >= 0 && col < MAX_COLS);
}
cql_result_set *cql_get_result_set_from_ref(cql_result_set_ref ref) {
  assert(ref == (cql_result_set_ref)&result);
  return &result;
}
void cql_release(cql_type_ref ref) { assert(ref == (cql_type_ref)&result); }
void cql_retain(cql_type_ref ref) { assert(ref == (cql_type_ref)&result); }
cql_bool cql_result_set_get_is_null_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); return null_values;
}
cql_int32 cql_result_set_get_int32_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(!null_values); return row * 1000 + col;
}
cql_int64 cql_result_set_get_int64_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(!null_values); return row * 1000 + col;
}
cql_double cql_result_set_get_double_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(!null_values); return row * 1000 + col + 0.5;
}
cql_bool cql_result_set_get_bool_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(!null_values); return 2;
}
cql_string_ref cql_result_set_get_string_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); return null_values ? NULL : (cql_string_ref)@"text";
}
cql_blob_ref cql_result_set_get_blob_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(null_values); return NULL;
}
cql_object_ref cql_result_set_get_object_col(cql_result_set_ref ref, int row, int col) {
  check(ref, row, col); assert(null_values); return NULL;
}
""" + counts + """int main() {
  @autoreleasepool {
  result.count = 10;
""" + "\n".join(calls) + """
  }
  return 0;
}
""",
                       encoding="ascii")
    libs = [
        flag for flag in shlex.split(
            subprocess.check_output([config, "--base-libs"], text=True))
        if flag != "-rdynamic"
    ]
    binary = output_dir / "binding_objc_checks"
    # Drop unused procedure entry points; this exercises projection wrappers,
    # not SQLite execution or a replacement CoreFoundation runtime.
    subprocess.run([
        clang, *flags, "-ffunction-sections", "-Wl,--gc-sections",
        str(harness),
        str(implementation), "-o",
        str(binary), *libs
    ],
                   check=True)
    subprocess.run([str(binary.resolve())], check=True)
    print(
        "Both Objective-C wrappers passed row/ordinal, NULL, and boxing execution."
    )


def main():
    compiler = sys.argv[1]
    output_dir = pathlib.Path(sys.argv[2])
    metadata = prepare_metadata(compiler, output_dir)
    generator = SOURCES / "java_demo/cqljava.py"
    result = subprocess.run(
        [
            sys.executable,
            str(generator),
            str(metadata), "--package", "sample", "--class", "Bindings"
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    source = output_dir / "Bindings.java"
    source.write_bytes(result.stdout)
    expected = check_generated_java(result.stdout.decode("utf-8"))
    check_java_execution(source, output_dir, expected)
    csharp = generate("dotnet_demo/cqlcs.py", metadata, "--class", "Bindings")
    check_csharp(csharp, output_dir)
    cf = generate("cqlrt_cf/cqlobjc.py", metadata, "--objc_c_include_path",
                  "binding_projection.h")
    header = generate("objc_full/cql_objc_full.py", metadata, "--header",
                      "binding_projection.h", "--legacy")
    impl = generate("objc_full/cql_objc_full.py", metadata, "--emit_impl",
                    "--header", "binding_objc.h", "--legacy")
    check_objc(cf, header, impl, compiler, output_dir)


if __name__ == "__main__":
    main()
