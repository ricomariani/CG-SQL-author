#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import pathlib
import subprocess
import sys


def main():
    compiler = sys.argv[1]
    source = pathlib.Path(sys.argv[2]) / "integer_literals.sql"
    accepted = [
        "0", "2147483647", "2147483648", "9223372036854775807",
        "-9223372036854775808", "-09223372036854775808",
        "0x7fffffff", "0x80000000", "0x7fffffffffffffff",
        "0x8000000000000000", "0xffffffffffffffff", "0XABCDEF",
    ]
    rejected = [
        "9223372036854775809",
        "18446744073709551615", "18446744073709551616",
        "0x10000000000000000", "-9223372036854775809",
    ]
    invalid_context = ["9223372036854775808", "- -9223372036854775808"]
    cases = []
    for suffix in ("", "L", "l"):
        cases.extend((f"select {value}{suffix};", None) for value in accepted)
        cases.extend((f"select {value}{suffix};", "lexical") for value in rejected)
        cases.extend(
            (f"select {value}{suffix};", "semantic") for value in invalid_context
        )
    cases.extend([
        ("", None),
        ("@macro(expr) minimum!() begin -9223372036854775808 end;"
         "select minimum!();", None),
        ("@macro(expr) minimum!() begin -9223372036854775808 end;"
         "select -minimum!();", "semantic"),
        ("@macro(expr) negate!(x! expr) begin -x! end;"
         "select negate!(9223372036854775808);", None),
        ("declare enum bad long (v = 9223372036854775808);", "semantic"),
        ("declare enum bad long (v = - -9223372036854775808);", "semantic"),
        ("const group bad (v = 9223372036854775808);", "semantic"),
        ("create table bad(x long default 9223372036854775808);", "semantic"),
        ("@attribute(v=9223372036854775808) create table bad(x int);", "semantic"),
        ("@attribute(v=(-9223372036854775808,9223372036854775808))"
         "create table bad(x int);", "semantic"),
        ("@attribute(v=-9223372036854775808) create table good(x int);", None),
    ])

    for sql, error_stage in cases:
        source.write_text(sql, encoding="utf-8")
        for mode in ("--echo", "--sem", "--exp"):
            result = subprocess.run(
                [compiler, mode, "--in", str(source)],
                capture_output=True, text=True, check=False,
            )
            status = 0
            if error_stage == "lexical":
                status = 2
            elif error_stage == "semantic" and mode == "--sem":
                status = 1
            if result.returncode != status or (
                status and "integer literal out of range" not in result.stderr
            ):
                raise AssertionError(
                    f"{mode} {sql!r}: expected status {status}, "
                    f"got {result.returncode}\n{result.stdout}\n{result.stderr}"
                )


if __name__ == "__main__":
    main()
