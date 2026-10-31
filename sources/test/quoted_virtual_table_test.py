#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import contextlib
import pathlib
import sqlite3
import subprocess
import sys


def main():
    compiler = sys.argv[1]
    output_dir = pathlib.Path(sys.argv[2])
    source = output_dir / "quoted_virtual_table.sql"
    schema = output_dir / "quoted_virtual_table_schema.sql"
    sqlite_schema = output_dir / "quoted_virtual_table_sqlite.sql"
    roundtrip = output_dir / "quoted_virtual_table_roundtrip.sql"
    names = [
        # An unquoted control and a quoted ordinary name distinguish identifier
        # spelling from simply deciding whether a name contains special bytes.
        ("plain_virtual", False),
        ("quoted_virtual", True),
        ("doc store", True),
        ("virtual-table.punct", True),
        ("select", True),
        ('virtual"quote', True),
        ("virtual`tick", True),
    ]

    for name, quoted in names:
        cql_name = "`" + name.replace("`", "``") + "`" if quoted else name
        sql_name = f"[{name}]" if quoted else name
        # FTS4 accepts a default content column, explicit column arguments, and
        # declaration-derived column/type arguments. This exercises all three
        # emitter paths against a real module, not just a placeholder module name.
        for arguments in ("", "(content)", "(arguments following)"):
            print(f"Checking virtual table identity: {cql_name} {arguments}",
                  flush=True)
            source.write_text(
                f"create virtual table if not exists {cql_name} "
                f"using fts4{arguments} as (content text);\n",
                encoding="ascii",
            )
            for input_file, output_file, runtime in [
                (source, schema, "schema"),
                (source, sqlite_schema, "schema_sqlite"),
                (schema, roundtrip, "schema"),
            ]:
                subprocess.run(
                    [compiler, "--in", str(input_file), "--cg", str(output_file),
                     "--rt", runtime],
                    check=True,
                )

            # CQL schema must retain quoted names and remain stable on reparse.
            assert f"CREATE VIRTUAL TABLE IF NOT EXISTS {cql_name} USING fts4" in (
                schema.read_text()
            ), (name, arguments, schema.read_text())
            assert schema.read_text() == roundtrip.read_text(), (name, arguments)
            sql = sqlite_schema.read_text()
            assert f"CREATE VIRTUAL TABLE IF NOT EXISTS {sql_name} USING fts4" in (
                sql
            ), (name, arguments, sql)

            with contextlib.closing(sqlite3.connect(":memory:")) as database:
                database.executescript(sql)
                database.executescript(sql)
                # Successful CREATE is insufficient: the broken emitter creates
                # an encoded table name, while subsequent SQL uses the real name.
                actual = database.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE sql LIKE 'CREATE VIRTUAL TABLE%'"
                ).fetchall()
                assert actual == [(name,)], (name, arguments, actual)
                database.execute(
                    f"INSERT INTO [{name}](content) VALUES (?)", ("hello",)
                )
                assert database.execute(
                    f"SELECT content FROM [{name}]"
                ).fetchall() == [("hello",)], (name, arguments)
                database.execute(f"DROP TABLE [{name}]")
                assert database.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE sql LIKE 'CREATE VIRTUAL TABLE%'"
                ).fetchall() == [], (name, arguments)


if __name__ == "__main__":
    main()
