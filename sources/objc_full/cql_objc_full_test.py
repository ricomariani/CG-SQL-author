#!/usr/bin/env python3

# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import contextlib
import io
import re

import cql_objc_full


def capture(func, *args):
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        func(*args)
    return output.getvalue()


def main():
    hostile = 'x:(NSUInteger)row { return 0; } @end @interface Boom'
    projection = [
        {"name": "safe", "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
    ]
    proc = {"name": "sample", "projection": projection}

    header = capture(
        cql_objc_full.emit_proc_objc_projection_header, proc, {})
    implementation = capture(
        cql_objc_full.emit_proc_objc_projection_impl, proc, {})

    header_names = re.findall(
        r"- \(cql_int32\)([A-Za-z_][A-Za-z0-9_]*):\(NSUInteger\)row;",
        header,
    )
    implementation_names = re.findall(
        r"- \(cql_int32\)([A-Za-z_][A-Za-z0-9_]*):\(NSUInteger\)row",
        implementation,
    )
    assert len(header_names) == len(projection)
    assert len(set(header_names)) == len(projection)
    assert header_names == implementation_names
    assert header_names[0] == "safe"
    assert hostile not in header
    assert hostile not in implementation
    for col in range(len(projection)):
        assert (
            "cql_result_set_get_int32_col("
            f"(cql_result_set_ref)_result_set_ref, row, {col})"
        ) in implementation


if __name__ == "__main__":
    main()
