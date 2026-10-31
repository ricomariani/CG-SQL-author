#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import pathlib
import subprocess
import sys


def main():
    compiler = sys.argv[1]
    output_dir = pathlib.Path(sys.argv[2])
    source = output_dir / "json_utf8.sql"
    output = output_dir / "json_utf8.json"
    cases = [
        # Mixing all UTF-8 widths catches byte-by-byte Latin-1 conversion and
        # incorrect advancement between complete sequences.
        ("valid Unicode", b"caf\xc3\xa9 \xe2\x80\xa2 \xf0\x9f\x98\x80",
         "caf\u00e9 \u2022 \U0001f600"),
        # ASCII, SQL quote doubling, and JSON control escaping are unchanged.
        ("ASCII and controls", b"' \" \\ \n \t \x07", "' \" \\ \n \t \x07"),
        # An isolated high byte must become valid JSON on unsigned-char builds
        # too. The fallback represents that byte as U+0081, not U+FFFD.
        ("isolated continuation", b"a\x81z", "a\u0081z"),
        # The January 2026 policy rejects the entire extra-continuation run,
        # rather than preserving its otherwise-valid three-byte prefix.
        ("extra continuation", b"\xe2\x80\xa2\xa2",
         "\u00e2\u0080\u00a2\u00a2"),
        # Malformed sequences must retain the established byte-wise fallback.
        ("truncated sequence", b"\xf0\x9f\x98", "\u00f0\u009f\u0098"),
        ("overlong sequence", b"\xc0\xaf", "\u00c0\u00af"),
        ("surrogate codepoint", b"\xed\xa0\x80", "\u00ed\u00a0\u0080"),
        ("above Unicode maximum", b"\xf4\x90\x80\x80",
         "\u00f4\u0090\u0080\u0080"),
    ]

    for name, payload, expected in cases:
        # ASCII CQL hex escapes supply exact input bytes without depending on
        # this driver's source encoding. The attribute uses full-string JSON
        # encoding; the SELECT statement uses the previously missed pretty path.
        literal = "".join(f"\\x{byte:02x}" for byte in payload)
        source.write_text(
            f'@attribute(utf8_payload="{literal}")\n'
            'proc json_utf8_case()\nbegin\n'
            f'  select "{literal}" as payload;\nend;\n',
            encoding="ascii",
        )
        print(f"Checking JSON string fidelity: {name}", flush=True)
        subprocess.run(
            [compiler, "--in", str(source), "--cg", str(output),
             "--rt", "json_schema"],
            check=True,
        )
        # Strict UTF-8 decoding and a real JSON parser reject raw malformed
        # bytes. Comparing decoded strings catches valid JSON with wrong text.
        document = json.loads(output.read_text(encoding="utf-8"))
        query, = document["queries"]
        attribute, = query["attributes"]
        assert attribute["name"] == "utf8_payload", (name, attribute)
        assert attribute["value"] == expected, (
            name, "attribute", repr(expected), repr(attribute["value"])
        )
        expected_sql = "SELECT '" + expected.replace("'", "''") + "' AS payload"
        assert query["statement"] == expected_sql, (
            name, "statement", repr(expected_sql), repr(query["statement"])
        )
        # Parameter binding would bypass SQL literal quoting and hide its bug.
        assert query["statementArgs"] == [], (name, query["statementArgs"])


if __name__ == "__main__":
    main()
