#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import pathlib
import subprocess
import sys


CASES = [
    (b"", ""),
    (b"ordinary", "ordinary"),
    (b"space name", "space name"),
    (b"quote\"and'", "quote\"and'"),
    (b"slash\\t\\u0041\\q", "slash\\t\\u0041\\q"),
    (b"back`tick", "back`tick"),
    (b"tab\tname", "tab\tname"),
    (bytes(range(1, 32)), "".join(chr(i) for i in range(1, 32))),
    (b"\x7f", "\x7f"),
    (b"\xc2\x80\xdf\xbf", "\u0080\u07ff"),
    (b"\xe0\xa0\x80\xef\xbf\xbf", "\u0800\uffff"),
    (b"\xf0\x90\x80\x80\xf4\x8f\xbf\xbf", "\U00010000\U0010ffff"),
    ("caf\u00e9_\u2022_\U0001f642".encode(), "caf\u00e9_\u2022_\U0001f642"),
    (b"\x81", "\u0081"),
    (b"\xff", "\u00ff"),
    (b"\xc0\xaf", "\u00c0\u00af"),
    (b"\xe0\x80\xaf", "\u00e0\u0080\u00af"),
    (b"\xf0\x80\x80\xaf", "\u00f0\u0080\u0080\u00af"),
    (b"\xed\xa0\x80", "\u00ed\u00a0\u0080"),
    (b"\xf4\x90\x80\x80", "\u00f4\u0090\u0080\u0080"),
    (b"\xf8\x80\x80\x80\x80", "\u00f8\u0080\u0080\u0080\u0080"),
    (b"\xc2", "\u00c2"),
    (b"\xe2\x80", "\u00e2\u0080"),
    (b"\xf0\x9f\x99", "\u00f0\u009f\u0099"),
    (b"\xe2A\x80", "\u00e2A\u0080"),
    (b"\xe2\x80\xa2\xa2", "\u00e2\u0080\u00a2\u00a2"),
    (b"\xc3\xa9_\x81_\xf0\x9f\x99\x82", "\u00e9_\u0081_\U0001f642"),
]

# The lexer does not accept multiline quoted identifiers; dynamic text can
# still contain every non-NUL control byte.
NAME_CASES = [(raw, expected) for raw, expected in CASES if b"\n" not in raw and b"\r" not in raw]


def qid(value):
    return b"`" + value.replace(b"`", b"``") + b"`"


def text_literal(value):
    return f"CAST(x'{value.hex()}' AS TEXT)"


def prepare(compiler, directory):
    source = directory / "query_plan_encoding.sql"
    generated = directory / "query_plan_encoding.cql"
    sql = bytearray()
    for i, (raw, _) in enumerate(NAME_CASES):
        table = qid(f"t{i}_".encode() + raw)
        index = qid(f"idx{i}_".encode() + raw)
        sql.extend(b"[[no_table_scan]]\ncreate table " + table + b"(id int, value text);\n")
        sql.extend(b"create index " + index + b" on " + table + b"(id);\n")
        sql.extend(b"select * from " + table + b";\n")
        sql.extend(b"select * from " + table + b" where id = 7;\n")
    source.write_bytes(sql)
    subprocess.run(
        [compiler, "--in", str(source), "--cg", str(generated), "--rt", "query_plan"],
        check=True,
    )

    # Exercise dynamic printer inputs independently of SQLite's plan wording,
    # including truncated sequences at the actual end of each value.
    adapter = [
        "PROC query_plan_encoding_test() BEGIN",
        "CALL query_plan();",
        "DELETE FROM no_table_scan;",
        "DELETE FROM plan_temp;",
        "DELETE FROM table_scan_alert;",
        "DELETE FROM b_tree_alert;",
    ]
    for i, (raw, _) in enumerate(CASES, 1):
        adapter.append(
            "INSERT INTO plan_temp(iselectid, iorder, ifrom, zdetail, sql_id) "
            f"VALUES ({i}, {i - 1}, 0, {text_literal(b'detail_' + raw)}, 1);"
        )
        for table, prefix in [("table_scan_alert", b"scan_"), ("b_tree_alert", b"btree_")]:
            adapter.append(f"INSERT INTO {table}(info) VALUES ({text_literal(prefix + raw)});")
    adapter.extend([
        'CALL printf("\\n{\\n");',
        "CALL print_query_violation();",
        'CALL printf("\\"empty\\" : \\"");',
        'CALL printf("%s", cql_create_json_escaped_str(\'\'));',
        'CALL printf("\\",\\n");',
        "CALL print_query_plan_graph(1);",
        'CALL printf("}\\n");',
        "END;",
    ])
    generated.write_bytes(generated.read_bytes() + "\n".join(adapter).encode() + b"\n")
    print(f"Prepared {len(NAME_CASES)} identifier and {len(CASES)} dynamic-string cases")


def check(report_file):
    text = report_file.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    report, end = decoder.raw_decode(text)
    dynamic, end_dynamic = decoder.raw_decode(text[end:].lstrip())
    assert not text[end:].lstrip()[end_dynamic:].strip()
    assert len(report["plans"]) == 2 * len(NAME_CASES)
    uppercase_ascii = str.maketrans("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    expected_alerts = set()
    for i, (_, expected) in enumerate(NAME_CASES):
        table = f"t{i}_" + expected
        index = f"idx{i}_" + expected
        scan, search = report["plans"][2*i:2*i + 2]
        for plan in (scan, search):
            assert "`" + table.replace("`", "``") + "`" in plan["query"], plan
            assert table in plan["plan"], plan
        assert index in search["plan"], search
        expected_alerts.add(table.translate(uppercase_ascii) + "(1)")
    assert set(report["alerts"]["tableScanViolation"].split(", ")) == expected_alerts
    expected_graph = "QUERY PLAN"
    for i, (_, expected) in enumerate(CASES):
        expected_graph += "\n" + " " * min(30, 3*i) + "|..detail_" + expected
    assert dynamic["empty"] == ""
    assert dynamic["plan"] == expected_graph, dynamic["plan"]
    for key, prefix in [("tableScanViolation", "scan_"), ("tempBTreeViolation", "btree_")]:
        assert dynamic["alerts"][key] == ", ".join(prefix + expected for _, expected in CASES)
    print(f"Decoded {len(NAME_CASES)} identifier and {len(CASES)} dynamic-string cases")


if __name__ == "__main__":
    if sys.argv[1] == "prepare":
        prepare(sys.argv[2], pathlib.Path(sys.argv[3]))
    elif sys.argv[1] == "check":
        check(pathlib.Path(sys.argv[2]))
    else:
        raise ValueError("Expected prepare or check")
