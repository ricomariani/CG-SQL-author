#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import contextlib
import io
import re

import cqlobjc


def main():
    hostile = 'x) { return 0; } static void boom(void) {'
    projection = [
        {"name": "safe", "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
        {"name": hostile, "type": "integer", "isNotNull": True},
    ]
    proc = {"name": "sample", "projection": projection}

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cqlobjc.emit_result_set_projection(proc, {})
    generated = output.getvalue()

    names = re.findall(
        r"CGS_sample_get_([A-Za-z_][A-Za-z0-9_]*)"
        r"\(CGS_sample \*resultSet, cql_int32 row\)",
        generated,
    )
    assert len(names) == len(projection)
    assert len(set(names)) == len(projection)
    assert hostile not in generated
    for col in range(len(projection)):
        assert (
            "cql_result_set_get_int32_col("
            f"(cql_result_set_ref)cResultSet, row, {col})"
        ) in generated


if __name__ == "__main__":
    main()
