#!/usr/bin/env python3

# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
import pathlib
import re
import shutil
import subprocess
import sys

SOURCES = pathlib.Path(__file__).resolve().parents[1]


def prepare(compiler, output):
    output.mkdir(exist_ok=True)
    source = SOURCES / "test/dotnet_blob_test.sql"
    subprocess.run([
        compiler, "--in",
        str(source), "--cg",
        str(output / "blobs.h"),
        str(output / "blobs.c")
    ],
                   check=True)
    metadata = output / "blobs.json"
    subprocess.run([
        compiler, "--in",
        str(source), "--rt", "json_schema", "--cg",
        str(metadata)
    ],
                   check=True)
    generator = SOURCES / "dotnet_demo/cqlcs.py"
    for name, options in [
        ("BlobInterop.cs", ["--class", "BlobInterop"]),
        ("BlobInterop.c",
         ["--emit_c", "--class", "BlobInterop", "--cql_header", "blobs.h"]),
    ]:
        result = subprocess.run(
            [sys.executable,
             str(generator),
             str(metadata), *options],
            stdout=subprocess.PIPE,
            check=True)
        (output / name).write_bytes(result.stdout)


def run(output):
    dotnet = shutil.which("dotnet")
    if dotnet is None:
        print("SKIP: .NET/native blob execution requires a .NET SDK.",
              file=sys.stderr)
        return
    sdks = subprocess.check_output([dotnet, "--list-sdks"], text=True)
    majors = [
        int(major) for major in re.findall(r"^(\d+)\.\d+\.\S+ ", sdks, re.M)
    ]
    if not majors:
        print("SKIP: .NET/native blob execution requires a .NET SDK.",
              file=sys.stderr)
        return
    target = f"net{max(majors)}.0"
    (output / "NuGet.Config").write_text(
        '<configuration><packageSources><clear /></packageSources></configuration>',
        encoding="ascii")
    project = output / "BlobChecks.csproj"
    project.write_text(
        '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
        f'<TargetFramework>{target}</TargetFramework><OutputType>Exe</OutputType>'
        '<Nullable>annotations</Nullable>'
        '</PropertyGroup><ItemGroup>'
        f'<Compile Include="{SOURCES / "dotnet_demo/CQLInterop.cs"}" />'
        f'<Compile Include="{SOURCES / "test/dotnet_blob_test.cs"}" />'
        '<None Include="cql_interop.dll" CopyToOutputDirectory="PreserveNewest" />'
        '</ItemGroup></Project>',
        encoding="utf-8")
    env = dict(os.environ,
               DOTNET_CLI_TELEMETRY_OPTOUT="1",
               DOTNET_NOLOGO="1",
               DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1",
               DOTNET_GENERATE_ASPNET_CERTIFICATE="false",
               MSBUILDDISABLENODEREUSE="1")
    subprocess.run([
        dotnet, "build",
        str(project), "--nologo", "--verbosity", "quiet",
        "-p:UseSharedCompilation=false"
    ],
                   check=True,
                   env=env)
    subprocess.run(
        [dotnet, str(output / f"bin/Debug/{target}/BlobChecks.dll")],
        check=True,
        env=env)


if __name__ == "__main__":
    if sys.argv[1] == "--prepare":
        prepare(sys.argv[2], pathlib.Path(sys.argv[3]).resolve())
    else:
        run(pathlib.Path(sys.argv[1]).resolve())
