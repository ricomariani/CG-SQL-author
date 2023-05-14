# CG/SQL Playground

## CQL Playground
While we do not offer an interactive REPL environment, we have bootstrapped an environment to run simple CQL programs in the `repl` folder of our repository. You can run it by doing this from the CQL repository:

```bash
$ cd sources/repl
$ ./go.sh
```

By default, you'll get this output:
```
../out/cql ready
CQL Mini App Thingy
Hello from CQL.
Edit as you please
```

`go.sh` runs the `go()` stored procedure defined in `go.sql`. You can experiment with the CQL language by editing the `go.sql` file, as you please.

The contents of `go.sh` also offers a basic demonstration of how CQL should be typically used to transpile files into a C executable.

## Query Plan Playground
Within the same `repl` directory, we have a script that demonstrates [CQL's query plan generation feature](../CQL_Guide/generated/guide.md#chapter-15-query-plan-generation) with `go.sql`.

Run this script in the `/repl` directory of the CQL repository:
```bash
$ cd repl
$ ./go_query_plan.sh
```

The script will generate the output of `EXPLAIN QUERY PLAN` of the SQL statements used in `go.sql`.

```json
["Query", "Stat", "Graph"],
[
  "INSERT INTO my_table(str) VALUES(\"Hello from CQL.\"), (\"Edit as you please.\")",
  [
    [],
    [{"value": "SCAN", "style": {"fontSize": 14, "color": "red", "fontWeight": "bold"}}, {"value": 1, "style": {"fontSize": 14, "color": "red", "fontWeight": "bold"}}],
    []
  ],
  "\n?\n|...SCAN 2 CONSTANT ROWS"
],
[
  "SELECT *\n  FROM my_table",
  [
    [],
    [{"value": "SCAN", "style": {"fontSize": 14, "color": "red", "fontWeight": "bold"}}, {"value": 1, "style": {"fontSize": 14, "color": "red", "fontWeight": "bold"}}],
    []
  ],
  "\n?\n|...SCAN TABLE my_table"
],
```

You might notice the above output has a lot of extraneous stuff, like what seems to be CSS styling in JSON format. This is something that will be addressed in the future. In the meantime, you can use
something like [`jq`](https://stedolan.github.io/jq/) to filter stuff out. For example:

```bash
$ ./go_query_plan.sh | jq '.[0][0][1:-1][] | {"query": .[0], "explain": .[2]}'
```

## Fully Online Playground
Contributor [mingodad](https://github.com/mingodad) created this wonder, all online using the CQL Amalgam, plus WASM and LUA to create a 100% [in-your-browser playground](https://mingodad.github.io/CG-SQL-Lua-playground/).
