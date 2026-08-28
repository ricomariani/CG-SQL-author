#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Exercise SQL generation with apostrophes in every major metadata category.
# The generated script is executed in an in-memory SQLite database, which tests
# syntax and round-trip values together.  One table name also contains a
# complete SQL-looking suffix; the final sqlite_master query proves that suffix
# remained data rather than becoming another statement.

import contextlib
import io
import sqlite3

import cqljson


def main():
    # Populate tables, columns, keys, regions, procedures, views, triggers,
    # dependencies, attributes, and optional fields so no SQL-emission path can
    # bypass the common literal encoder unnoticed.
    table_name = "tab'); create table pwned(x); --"
    data = {
        "tables": [{
            "name": table_name,
            "region": "reg'ion",
            "isDeleted": False,
            "isRecreated": True,
            "addedVersion": 2,
            "deletedVersion": 3,
            "recreateGroupName": "gro'up",
            "attributes": [{"name": "att'r", "value": ["v'al", 7]}],
            "columns": [{
                "name": "co'l",
                "type": "te'xt",
                "kind": "ki'nd",
                "isNotNull": True,
            }],
            "primaryKey": ["co'l"],
            "foreignKeys": [{
                "columns": ["co'l"],
                "referenceTable": "ref'table",
                "referenceColumns": ["ref'col"],
            }],
        }],
        "regions": [
            {"name": "reg'ion", "using": ["par'ent"]},
            {"name": "par'ent", "using": []},
        ],
        "queries": [{
            "name": "pr'oc",
            "projection": [{
                "name": "p'col",
                "type": "te'xt",
                "kind": "p'kind",
                "isSensitive": True,
                "isNotNull": False,
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
        }],
        "triggers": [{
            "name": "tr'igger",
            "target": table_name,
            "region": "reg'ion",
            "isDeleted": False,
            "usesTables": ["dep'table"],
        }],
    }

    # emit_schema creates the metadata tables and emit_sql populates them.
    # Capturing stdout mirrors the command-line generator's output contract.
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cqljson.emit_schema()
        cqljson.emit_sql(data)

    # Executing the whole script catches malformed quoting.  The queries below
    # additionally prove that escaping preserved the original values exactly.
    db = sqlite3.connect(":memory:")
    db.executescript(output.getvalue())

    assert db.execute("select t_name, region, recreate_group from tables").fetchone() == (
        table_name,
        "reg'ion",
        "gro'up",
    )
    assert db.execute("select c_name, c_type, c_kind from columns").fetchone() == (
        "co'l",
        "te'xt",
        "ki'nd",
    )
    assert db.execute("select a_name, value from table_attributes").fetchone() == (
        "att'r",
        '("v\'al", 7)',
    )
    assert db.execute("select p_name, c_name, kind from proc_projections").fetchone() == (
        "pr'oc",
        "p'col",
        "p'kind",
    )
    assert db.execute("select v_name from proc_view_deps").fetchone() == ("vi'ew",)
    assert db.execute("select tr_name, t_name from triggers").fetchone() == (
        "tr'igger",
        table_name,
    )
    assert db.execute("select t_name from trigger_deps").fetchone() == ("dep'table",)

    # If the hostile-looking table name escaped its literal, this injected table
    # would exist.  Zero rows proves the entire name remained inert data.
    assert db.execute(
        "select count(*) from sqlite_master where name = 'pwned'"
    ).fetchone() == (0,)


if __name__ == "__main__":
    main()
