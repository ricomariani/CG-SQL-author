#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import pathlib
import sqlite3
import subprocess
import sys
import tempfile


def quote_identifier(name):
    return '"' + name.replace('"', '""') + '"'


def main():
    out = pathlib.Path(sys.argv[1])
    with tempfile.TemporaryDirectory(dir=out) as directory:
        database = pathlib.Path(directory) / "identifiers.db"
        subprocess.run([str(out / "upgrade0"), str(database)], check=True)
        names = ["bracket]name", 'double"quote', "single'quote", 'mixed ] " ; -- name']
        objects = []
        with sqlite3.connect(database) as db:
            db.executescript(
                "CREATE TABLE identifier_host(value);"
                "CREATE TABLE identifier_guard(value);"
                "INSERT INTO identifier_guard VALUES (42);"
            )
            for i, suffix in enumerate(names):
                for kind in ("VIEW", "TRIGGER", "INDEX"):
                    name = f"{kind.lower()}_{i}_{suffix}"
                    identifier = quote_identifier(name)
                    if kind == "VIEW":
                        sql = f"CREATE VIEW {identifier} AS SELECT * FROM identifier_host"
                    elif kind == "TRIGGER":
                        sql = (
                            f"CREATE TRIGGER {identifier} AFTER INSERT ON identifier_host "
                            "BEGIN SELECT 1; END"
                        )
                    else:
                        sql = f"CREATE INDEX {identifier} ON identifier_host(value)"
                    db.execute(sql)
                    objects.append(name)

        # The exclusive upgrader must drop database-derived names literally,
        # including names containing either quoting delimiter and SQL punctuation.
        subprocess.run([str(out / "upgrade4"), str(database)], check=True)
        with sqlite3.connect(database) as db:
            remaining = {row[0] for row in db.execute("SELECT name FROM sqlite_master")}
            for name in objects:
                if name in remaining:
                    raise AssertionError(f"upgrade did not drop {name!r}")
            if db.execute("SELECT value FROM identifier_guard").fetchall() != [(42,)]:
                raise AssertionError("upgrade modified the unrelated guard table")


if __name__ == "__main__":
    main()
