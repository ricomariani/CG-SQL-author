#!/usr/bin/env python3

# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import contextlib
import io
import re

import cqljava


def main():
    hostile = 'x(int row) { return 0; } static { boom(); } //'
    projection = [
        {"name": "safe", "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
    ]
    proc = {"name": "sample", "projection": projection}

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cqljava.emit_result_set_projection(proc, {})
    generated = output.getvalue()

    names = re.findall(
        r"public int (get_[A-Za-z_][A-Za-z0-9_]*)\(int row\)", generated)
    assert len(names) == len(projection)
    assert len(set(names)) == len(projection)
    assert hostile not in generated
    for col in range(len(projection)):
        assert f"mResultSet.getInteger(row, {col})" in generated


if __name__ == "__main__":
    main()
