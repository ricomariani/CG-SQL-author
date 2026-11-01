#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import pathlib
import subprocess
import sys


def compile_metadata(compiler, source, output, sql):
    source.write_bytes(sql)
    subprocess.run(
        [compiler, "--in", str(source), "--cg", str(output), "--rt", "json_schema"],
        check=True,
    )
    return json.loads(output.read_text(encoding="utf-8"))


def check_names(compiler, source, output):
    # Plain and quoted ordinary names are controls; each special-character case
    # must work in all constraint roles, not only table/column declarations.
    for suffix, quoted in [
        ("plain", False),
        ("ordinary", True),
        ("a b", True),
        ('a"b', True),
        ("a\\b", True),
        ("a`b", True),
        ("caf\u00e9", True),
    ]:
        def name(value):
            return "`" + value.replace("`", "``") + "`" if quoted else value

        parent = "parent_" + suffix
        child = "child_" + suffix
        key = "id_" + suffix
        pk = "pk_" + suffix
        inline = "inline_" + suffix
        table = "table_" + suffix
        inline_unique = "inline_unique_" + suffix
        table_unique = "table_unique_" + suffix
        expr = "expr_" + suffix
        fk = "fk_" + suffix
        uk = "uk_" + suffix
        index_name = "index_" + suffix
        print(f"Checking JSON constraint names: {suffix!r}", flush=True)
        sql = (
            f"create table {name(parent)} ({name(key)} int!, "
            f"constraint {name(pk)} primary key ({name(key)} desc));\n"
            f"create table {name(child)} (\n"
            f"  {name(inline)} int references {name(parent)}({name(key)}),\n"
            f"  {name(table)} int,\n"
            f"  {name(inline_unique)} int unique,\n"
            f"  {name(table_unique)} text, {name(expr)} text,\n"
            f"  constraint {name(fk)} foreign key ({name(table)}) "
            f"references {name(parent)}({name(key)}),\n"
            f"  constraint {name(uk)} unique "
            f"({name(table_unique)} desc, length({name(expr)}) asc));\n"
            f"create index {name(index_name)} on {name(child)} "
            f"({name(table_unique)} desc, length({name(expr)}) asc) "
            f"where length({name(expr)}) > 0;\n"
        ).encode("utf-8")
        document = compile_metadata(compiler, source, output, sql)
        tables = {item["name"]: item for item in document["tables"]}
        assert tables[parent]["primaryKey"] == [key], (suffix, tables[parent])
        assert tables[parent]["primaryKeySortOrders"] == ["desc"], suffix
        assert tables[parent]["primaryKeyName"] == pk, (suffix, tables[parent])
        child_table = tables[child]
        columns = {column["name"] for column in child_table["columns"]}
        foreign_keys = child_table["foreignKeys"]
        assert len(foreign_keys) == 2, (suffix, foreign_keys)
        assert foreign_keys[0]["columns"] == [inline], (suffix, foreign_keys)
        assert foreign_keys[1]["columns"] == [table], (suffix, foreign_keys)
        assert foreign_keys[1]["name"] == fk, (suffix, foreign_keys)
        for foreign_key in foreign_keys:
            assert foreign_key["referenceTable"] == parent, (suffix, foreign_key)
            assert foreign_key["referenceColumns"] == [key], (suffix, foreign_key)
            # These are metadata identifiers, not SQL spellings or internal
            # compiler encodings: they must resolve to declared tables/columns.
            assert set(foreign_key["columns"]) <= columns, (suffix, foreign_key)
            referenced = tables[foreign_key["referenceTable"]]
            assert set(foreign_key["referenceColumns"]) <= {
                column["name"] for column in referenced["columns"]
            }, (suffix, foreign_key)
        unique_keys = {item["name"]: item for item in child_table["uniqueKeys"]}
        assert unique_keys[inline_unique + "_uk"]["columns"] == [inline_unique], suffix
        expression = f"length({name(expr)})"
        assert unique_keys[uk]["columns"] == [table_unique, expression], (
            suffix, unique_keys
        )
        assert unique_keys[uk]["sortOrders"] == ["desc", "asc"], suffix
        index, = document["indices"]
        # Index columns are expression strings. Preserve their existing CQL
        # quoting, unlike the bare identifiers in constraint-name metadata.
        assert index["columns"] == [name(table_unique), expression], (suffix, index)
        assert index["sortOrders"] == ["desc", "asc"], suffix
        assert index["where"] == expression + " > 0", (suffix, index)


def check_expressions(compiler, source, output):
    for label, payload, expected in [
        ("plain", b"plain", "plain"),
        ("double quote", b'"', '"'),
        ("SQL quote", b"it's", "it''s"),
        ("escape-looking tab", b"\\t", "\\t"),
        ("escape-looking Unicode", b"\\u0041", "\\u0041"),
        ("non-JSON escape", b"\\q", "\\q"),
        ("controls", b"\r\n\t\x07\x0b\x01\x7f", "\r\n\t\x07\x0b\x01\x7f"),
        ("Unicode", b"caf\xc3\xa9 \xe2\x80\xa2 \xf0\x9f\x98\x80",
         "caf\u00e9 \u2022 \U0001f600"),
        # Retain the established malformed-byte fallback in these newly escaped
        # expression paths, including rejection of an extra-continuation run.
        ("invalid byte", b"\x81", "\u0081"),
        ("extra continuation", b"\xe2\x80\xa2\xa2", "\u00e2\u0080\u00a2\u00a2"),
    ]:
        print(f"Checking JSON expression fidelity: {label}", flush=True)
        literal = b"'" + payload.replace(b"'", b"''") + b"'"
        expression = b"payload || " + literal
        sql = (
            b"create table expr_test (payload text, "
            b"constraint expr_uk unique (" + expression + b"));\n"
            b"create index expr_index on expr_test (" + expression + b") "
            b"where payload = " + literal + b";\n"
        )
        document = compile_metadata(compiler, source, output, sql)
        table, = document["tables"]
        index, = document["indices"]
        expected_literal = "'" + expected + "'"
        expected_expression = "payload || " + expected_literal
        assert table["uniqueKeys"][0]["columns"] == [expected_expression], (
            label, table["uniqueKeys"]
        )
        assert index["columns"] == [expected_expression], (label, index)
        assert index["where"] == "payload = " + expected_literal, (label, index)


def main():
    compiler = sys.argv[1]
    output_dir = pathlib.Path(sys.argv[2])
    source = output_dir / "json_schema_metadata.sql"
    output = output_dir / "json_schema_metadata.json"
    check_names(compiler, source, output)
    check_expressions(compiler, source, output)


if __name__ == "__main__":
    main()
