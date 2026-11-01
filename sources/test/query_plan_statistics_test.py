#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import pathlib
import subprocess
import sys


ORDINARY = "SEARCH t USING INDEX ia (a=?)"
COVERING = "SEARCH t USING COVERING INDEX ia (a=?)"
CASES = [
    ("ordinary-only", [(1, 3, ORDINARY)], {1: {"search": 1}, 2: {}}),
    ("covering-only", [(1, 3, COVERING)], {1: {"searchUsingCovering": 1}, 2: {}}),
    ("same-query-mixed", [(1, 3, ORDINARY), (1, 4, COVERING)],
     {1: {"search": 1, "searchUsingCovering": 1}, 2: {}}),
    ("collision", [(1, 3, ORDINARY), (2, 3, COVERING)],
     {1: {"search": 1}, 2: {"searchUsingCovering": 1}}),
    ("reverse-collision", [(1, 3, COVERING), (2, 3, ORDINARY)],
     {1: {"searchUsingCovering": 1}, 2: {"search": 1}}),
    ("non-collision", [(1, 3, ORDINARY), (2, 4, COVERING)],
     {1: {"search": 1}, 2: {"searchUsingCovering": 1}}),
    ("multiple-collisions", [(1, 3, ORDINARY), (1, 5, ORDINARY),
                             (2, 3, COVERING), (2, 5, COVERING)],
     {1: {"search": 2}, 2: {"searchUsingCovering": 2}}),
]
REAL_STATS = [
    {"search": 1},
    {"searchUsingCovering": 1},
    {"searchUsingCovering": 1},
    {"search": 1},
    {"search": 1, "searchUsingCovering": 1},
]


def prepare(compiler, directory):
    source = directory / "query_plan_statistics.sql"
    generated = directory / "query_plan_statistics.cql"
    source.write_text(
        "create table t(a int, b text);\n"
        "create index ia on t(a);\n"
        "select b from t where a = 7;\n"
        "select a from t where a = 7 order by a;\n"
        "select a from t where a = 7 order by a;\n"
        "select b from t where a = 7;\n"
        "select t.b, u.a from t join t as u on t.a = u.a where t.a = 7;\n"
    )
    subprocess.run(
        [compiler, "--in", str(source), "--cg", str(generated), "--rt", "query_plan"],
        check=True,
    )

    # Controlled plan rows check statement-local IDs without depending on
    # SQLite's choice of node numbers or join order.
    adapter = [
        "PROC query_plan_statistics_test() BEGIN",
        "CALL query_plan();",
        'CALL printf("\\n{\\"cases\\":[\\n");',
    ]
    first = True
    for name, rows, _ in CASES:
        adapter.append("DELETE FROM plan_temp;")
        for sql_id, node_id, detail in rows:
            adapter.append(
                "INSERT INTO plan_temp(iselectid, iorder, ifrom, zdetail, sql_id) "
                f"VALUES ({node_id}, 0, 0, '{detail}', {sql_id});"
            )
        for sql_id in (1, 2):
            separator = "" if first else ","
            adapter.append(f'CALL printf("{separator}{{\\"case\\":\\"{name}\\",");')
            adapter.append(f"CALL print_query_plan_stat({sql_id});")
            adapter.append(f'CALL printf("\\"sql_id\\":{sql_id}}}");')
            first = False
    adapter.extend(['CALL printf("\\n]}\\n");', "END;"])
    generated.write_text(generated.read_text() + "\n".join(adapter) + "\n")


def check(report_file):
    text = report_file.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    real, end = decoder.raw_decode(text)
    remaining = text[end:].lstrip()
    controlled, end = decoder.raw_decode(remaining)
    assert not remaining[end:].strip()
    assert len(real["plans"]) == len(REAL_STATS)
    for plan, expected in zip(real["plans"], REAL_STATS):
        assert plan["stats"] == expected, (plan, expected)
        assert plan["plan"].count("USING INDEX ia") == expected.get("search", 0), plan
        assert plan["plan"].count("USING COVERING INDEX ia") == expected.get("searchUsingCovering", 0), plan
    expected_cases = [
        {"case": name, "sql_id": sql_id, "stats": expected[sql_id]}
        for name, _, expected in CASES
        for sql_id in (1, 2)
    ]
    assert controlled["cases"] == expected_cases, controlled["cases"]
    print(f"Checked {len(REAL_STATS)} actual SQLite plans and {len(CASES)} controlled ID cases")


if __name__ == "__main__":
    if sys.argv[1] == "prepare":
        prepare(sys.argv[2], pathlib.Path(sys.argv[3]))
    elif sys.argv[1] == "check":
        check(pathlib.Path(sys.argv[2]))
    else:
        raise ValueError("Expected prepare or check")
