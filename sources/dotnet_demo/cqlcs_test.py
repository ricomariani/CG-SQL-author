#!/usr/bin/env python3

# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import contextlib
import io
import re

import cqlcs


def capture(func, *args):
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        func(*args)
    return output.getvalue()


def main():
    hostile = 'x(int row) { return 0; } static void boom() {} //'
    projection = [
        {"name": "safe", "type": "integer", "isNotNull": True},
        {"name": "Count", "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
    ]
    proc = {
        "name": "sample",
        "projection": projection,
        "hasOutResult": True,
    }
    generated = capture(cqlcs.emit_result_set_projection, proc, {})

    names = re.findall(
        r"public int (get_[A-Za-z_][A-Za-z0-9_]*)\(\)", generated)
    assert len(names) == len(projection)
    assert len(set(names)) == len(projection)
    assert "get_Count()" not in generated
    assert hostile not in generated
    for col in range(len(projection)):
        assert f"mResultSet.getInteger(0, {col})" in generated

    blob_proc = {
        "name": "CheckBlob",
        "usesDatabase": False,
        "args": [
            {
                "name": "x",
                "type": "blob",
                "isNotNull": True,
                "binding": "in",
            },
            {
                "name": "y",
                "type": "blob",
                "isNotNull": False,
                "binding": "in",
            },
        ],
    }

    c_output = capture(cqlcs.emit_proc_c_interop, blob_proc, {})
    assert '"xx"' not in c_output
    assert "const void * x,\n  cql_int32 x_len,\n  cql_int32 x_has_value" in c_output
    assert "const void * y,\n  cql_int32 y_len,\n  cql_int32 y_has_value" in c_output
    assert "const void *bytes_x = x_len ? x : &empty_blob_x;" in c_output
    assert "cql_blob_ref_new(bytes_x, (cql_uint32)x_len)" in c_output
    assert "const void *bytes_y = y_len ? y : &empty_blob_y;" in c_output
    assert "cql_blob_ref_new(bytes_y, (cql_uint32)y_len)" in c_output

    cs_output = capture(cqlcs.emit_proc_csharp_interop, blob_proc, {})
    assert "x, x == null ? 0 : x.Length, x == null ? 0 : 1" in cs_output
    assert "y, y == null ? 0 : y.Length, y == null ? 0 : 1" in cs_output
    assert "SizeParamIndex = 1" in cs_output
    assert "SizeParamIndex = 4" in cs_output


if __name__ == "__main__":
    main()
