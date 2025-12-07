# Summary

`cqljson.py` is used to read the JSON schema output of the CQL compiler
and create various artifacts that visualize it.  For instand it can produce
an ERD.

# Usage

```
--table_diagram input.json [universe] > tables.dot
   creates a .dot file for a table diagram

--region_diagram input.json > regions.dot
   creates a .dot file for a region diagram

--erd input.json [universe] > erd.dot
   creates a .dot file for an ER diagram

--sql input.json > inputdb.sql
   creates a .sql file for a database with the schema info
```

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
