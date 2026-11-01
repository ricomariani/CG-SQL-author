#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Exercise SQL metadata values and reconstructed CQL attributes. SQLite checks
# the emitted rows; the compiler checks that attribute text retains its meaning.

import contextlib
import io
import json
import pathlib
import sqlite3
import subprocess
import sys

import cqljson


def render_sql(data):
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cqljson.emit_schema()
        cqljson.emit_sql(data)
    return output.getvalue()


def check_sql_metadata():
    # Populate tables, columns, keys, regions, procedures, views, triggers,
    # dependencies, attributes, and optional fields so no SQL-emission path can
    # bypass the common literal encoder unnoticed.
    table_name = "tab'); create table pwned(x); --"
    data = {
        "tables": [{
            "name":
            table_name,
            "region":
            "reg'ion",
            "isDeleted":
            False,
            "isRecreated":
            True,
            "addedVersion":
            2,
            "deletedVersion":
            3,
            "recreateGroupName":
            "gro'up",
            "attributes": [{
                "name": "att'r",
                "value": ["v'al", 7]
            }],
            "columns": [{
                "name": "co'l",
                "type": "te'xt",
                "kind": "ki'nd",
                "isNotNull": True,
            }, {
                "name": "co\\l",
                "type": "text",
                "isNotNull": 0,
            }],
            "primaryKey": ["co'l", "co\\l"],
            "foreignKeys": [{
                "columns": ["co'l", "co\\l"],
                "referenceTable": "ref'table",
                "referenceColumns": ["ref'col", "ref\\col"],
            }],
        }, {
            "name": "plain\\table",
            "isDeleted": 1,
            "isRecreated": 0,
            "columns": [],
            "primaryKey": [],
            "foreignKeys": [],
        }],
        "regions": [
            {
                "name": "reg'ion",
                "using": ["par'ent"]
            },
            {
                "name": "par'ent",
                "using": []
            },
        ],
        "queries": [{
            "name":
            "pr'oc",
            "projection": [{
                "name": "p'col",
                "type": "te'xt",
                "kind": "p'kind",
                "isSensitive": True,
                "isNotNull": False,
            }, {
                "name": "plain\\projection",
                "type": "integer",
                "isNotNull": 1,
            }],
            "usesTables": [table_name],
            "usesViews": ["vi'ew"],
        }],
        "deletes": [],
        "inserts": [],
        "generalInserts": [],
        "updates": [],
        "general": [],
        "views": [{
            "name": "vi'ew",
            "region": "reg'ion",
            "isDeleted": False,
            "addedVersion": 4,
            "deletedVersion": 5,
        }, {
            "name": "plain\\view",
            "isDeleted": 1,
        }],
        "triggers": [{
            "name": "tr'igger",
            "target": table_name,
            "region": "reg'ion",
            "isDeleted": False,
            "usesTables": ["dep'table"],
        }, {
            "name": "plain\\trigger",
            "target": "plain\\table",
            "isDeleted": 1,
            "usesTables": [],
        }],
    }

    # Nonempty entries in every procedure category exercise all dispatch paths.
    # Deletion has no dependencies; the others retain their exact quoted names.
    for category in ("deletes", "inserts", "generalInserts", "updates",
                     "general"):
        data[category] = [{
            "name":
            category + "'proc",
            "usesTables": [] if category == "deletes" else [table_name],
        }]

    expected = {
        "tables": [
            (table_name, "reg'ion", 0, 2, 3, 1, "gro'up"),
            ("plain\\table", "None", 1, 0, -1, 0, ""),
        ],
        "columns": [
            (table_name, "co'l", "te'xt", "ki'nd", 1),
            (table_name, "co\\l", "text", "", 0),
        ],
        "pks": [(table_name, "co'l"), (table_name, "co\\l")],
        "fks": [
            ("fk1", table_name, "ref'table", "co'l", "ref'col"),
            ("fk1", table_name, "ref'table", "co\\l", "ref\\col"),
        ],
        "table_attributes": [(table_name, "att'r", '("v\'al", 7)')],
        "regions": [("reg'ion", ), ("par'ent", )],
        "region_deps": [("reg'ion", "par'ent")],
        "procs": [("pr'oc", "queries")],
        "proc_projections": [
            ("pr'oc", 0, "p'col", "te'xt", "p'kind", 1, 0),
            ("pr'oc", 1, "plain\\projection", "integer", None, 0, 1),
        ],
        "proc_deps": [("pr'oc", table_name)],
        "proc_view_deps": [("pr'oc", "vi'ew")],
        "views": [
            ("vi'ew", "reg'ion", 0, 4, 5),
            ("plain\\view", "None", 1, 0, -1),
        ],
        "triggers": [
            ("tr'igger", table_name, "reg'ion", 0),
            ("plain\\trigger", "plain\\table", "None", 1),
        ],
        "trigger_deps": [("tr'igger", "dep'table")],
    }
    for category in ("deletes", "inserts", "generalInserts", "updates",
                     "general"):
        name = category + "'proc"
        expected["procs"].append((name, category))
        if category != "deletes":
            expected["proc_deps"].append((name, table_name))

    with contextlib.closing(sqlite3.connect(":memory:")) as db:
        db.executescript(render_sql(data))
        # Check every emitted field and row, not just selected columns or the
        # first row. Exact schema membership also detects injected statements.
        tables = {
            row[0]
            for row in db.execute(
                "select name from sqlite_master where type = 'table'")
        }
        assert tables == set(expected), tables
        for table, rows in expected.items():
            actual = sorted(db.execute(f"select * from {table}").fetchall())
            assert actual == sorted(rows), (table, rows, actual)


def source_attribute(value):
    if value is None:
        return "null"
    if isinstance(value, list):
        return "(" + ", ".join(source_attribute(item) for item in value) + ")"
    if isinstance(value, str):
        # Independent source spelling: encode every UTF-8 byte as a two-digit
        # CQL hex escape rather than reproducing the demo's escaping algorithm.
        return '"' + "".join(f"\\x{byte:02x}"
                             for byte in value.encode("utf-8")) + '"'
    return str(value)


def compile_metadata(compiler, output_dir, stem, source_text):
    source = output_dir / (stem + ".sql")
    output = output_dir / (stem + ".json")
    source.write_text(source_text, encoding="utf-8")
    subprocess.run(
        [
            compiler, "--in",
            str(source), "--rt", "json_schema", "--cg",
            str(output)
        ],
        check=True,
    )
    return json.loads(output.read_text(encoding="utf-8"))


def check_attribute_round_trip(compiler, output_dir):
    cases = {
        "empty": "",
        "null_value": None,
        "apostrophe": "it's",
        "quotes": 'a"b',
        "backslash": "a\\b",
        "literal_escapes": r"\n\x07\u0007",
        "two_strings": ["a", "b"],
        "one_string": ['a", "b'],
        "nested": ["plain", ['q"uote', "slash\\text", None], -7, 2.5],
        "controls": "".join(chr(code) for code in range(1, 32)) + "\x7f",
        "hex_follower": "\x01f",
        "unicode": "caf\u00e9 \u2022 \U0001f600",
    }
    table_name = "foo\\bar' caf\u00e9"
    source_text = "".join(f"@attribute({name} = {source_attribute(value)})\n"
                          for name, value in cases.items()
                          ) + f"create table `{table_name}`(id integer);\n"
    document = compile_metadata(compiler, output_dir, "cqljson_original",
                                source_text)
    table, = document["tables"]
    original = {attr["name"]: attr["value"] for attr in table["attributes"]}
    assert table["name"] == table_name, table
    assert original == cases, (cases, original)

    with contextlib.closing(sqlite3.connect(":memory:")) as db:
        db.executescript(render_sql(document))
        assert db.execute("select t_name from tables").fetchone() == (
            table_name, )
        rows = db.execute(
            "select a_name, value from table_attributes").fetchall()
        stored = dict(rows)
        assert len(rows) == len(cases) and set(stored) == set(cases), rows

    expected_text = {
        "empty": '""',
        "null_value": "NULL",
        "apostrophe": '"it\'s"',
        "quotes": r'"a\"b"',
        "backslash": r'"a\\b"',
        "literal_escapes": r'"\\n\\x07\\u0007"',
        "two_strings": '("a", "b")',
        "one_string": r'("a\", \"b")',
        "nested": r'("plain", ("q\"uote", "slash\\text", NULL), -7, 2.5)',
        "hex_follower": r'"\x01f"',
        "unicode": '"caf\u00e9 \u2022 \U0001f600"',
    }
    differences = [(name, expected, stored[name])
                   for name, expected in expected_text.items()
                   if stored[name] != expected]
    assert not differences, differences

    # SQL execution alone misses lossy representations. Parse the stored text
    # as actual CQL attributes; JSON decoding is not a CQL escape oracle.
    reconstructed = "".join(f"@attribute({name} = {value})\n"
                            for name, value in stored.items()
                            ) + "create table reconstructed(id integer);\n"
    round_trip = compile_metadata(compiler, output_dir,
                                  "cqljson_reconstructed", reconstructed)
    round_trip_table, = round_trip["tables"]
    actual = {
        attr["name"]: attr["value"]
        for attr in round_trip_table["attributes"]
    }
    assert actual == cases, (cases, actual)


def main():
    check_sql_metadata()
    check_attribute_round_trip(sys.argv[1], pathlib.Path(sys.argv[2]))
    # CQL cannot represent an embedded NUL; emitting \x00 would silently drop
    # it when parsed, rather than fixing the lossy reconstruction.
    try:
        cqljson.format_attr_value(["before", "\0", "after"])
    except ValueError as error:
        assert "NUL" in str(error), error
    else:
        raise AssertionError("An unrepresentable NUL attribute was accepted")


if __name__ == "__main__":
    main()
