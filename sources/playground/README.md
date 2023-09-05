# CQL Playground

Use the [`./play.sh`](play.sh) cli command to run examples or your own small experiments.

Get some general help:

```sh
./play.sh --help
```

## For first-timers

The playground only requires a working cql compiler but some cool
optional features might require optional dependencies.

Check your setup and get a quick feedback on how to get ready:
```sh
./play.sh hello
```

Your pick:
```sh
./play.sh run examples/hello_world.sql
./play.sh run examples/mandelbrot.sql
```

## Common usage

### Build

```sh
# Build all outputs for every examples
./play.sh build-everything
# or its canonical version:
./play.sh build all_outputs examples/*

# Build every outputs for given example(s):
./play.sh build all_outputs examples/hello_world.sql

# Builds given output(s) for given example(s)
./play.sh build c lua examples/hello_world.sql examples/mandelbrot.sql
```
To rebuild on file change use `--watch` (Requires extra dependencies)

### Run

If the output does not exist, it will automatically try to rebuild it.

```sh
# Runs the given example (defaults to the output)
./play.sh run examples/hello_world.sql
./play.sh run lua examples/hello_world.sql

# Runs given output(s) for given example(s)
./play.sh run c lua examples/hello_world.sql examples/mandelbrot.sql

# Runs every outputs for given example(s):
./play.sh run all_outputs examples/hello_world.sql
```

To force the rebuild use `--rebuild`
To rebuild on file change use `--watch`

## Resources

### Examples
Examples have been crafted to quickly get you running and gain a deeper understanding of CQL.
Practice is the best way to learn. Edit them and create new ones!

  - **examples/hello_world.sql** — A welcoming "Hello World" example
  - **examples/crud.sql** — Showcasing the most common operations
  - **examples/cql_in_20_minutes.sql** — Learn CQL in 20 minutes
  - **examples/mandelbrot.sql** — Showcasing the seamless integration of sophisticated SQLite instructions into a CQL procedure
  - **examples/repl.sql** — An empty canvas for your own experiments
  - **examples/parent_child_result_set.sql** — Parent/Child result set
  - **examples/parent_child_with_no_result_set.sql** — Parent/Child with no result set
  - **examples/rowset_with_embedded_objets.sql** — Rowset with embedded objects

### Outputs
Multiple outputs are available. They all serve a wide range of different purposes.

- **c** (includes binary) [DEFAULT] — The compilation of the default C client embedding the C standard compilation (.c and .h) of the sql file
- **lua** — The compilation of the default Lua client embedding the Lua compilation of the sql file (.lua)
- **objc** — The Objective-C wrappers
- **java** — The Java wrappers
- **schema** — The canonical schema
- **schema_upgrade** — A CQL schema upgrade script
- **query_plan** — The query plan for every DML statement
- **stats** — A simple .csv file with AST node count information per procedure
- **ast** — The internal AST
- **ast_dot** — The internal AST using dot format
- **ast_dot_pdf** — The internal AST using dot format as PDF file
- **preprocessed** — The preprocessed version of the sql file
- **cql_json_schema** — A JSON output for codegen tools
- **cql_sql_schema** - A normalized version of the cql_json_schema (.sql)
- **table_diagram_dot** — Table Diagram
- **table_diagram_dot_pdf** — Table Diagram as PDF file
- **region_diagram_dot** — Region Diagram
- **region_diagram_dot_pdf** — Region Diagram as PDF file
- **erd_dot** - Entity Relationship Diagram
- **erd_dot_pdf** - Entity Relationship Diagram as PDF file
- **all_outputs** — All outputs

### Clients
Small applications showcasing how to use the CQL compiled code

#### Default Clients
They all call the conventional `entryproint()` procedure implemented in all examples

  - default_client.c — A minimal C application wrapping the main procedure call
  - default_client.lua — A minimal Lua application wrapping the main procedure call

#### Adhoc Clients
Some demonstrations are atypical and requires different runtimes to cater for specific purposes.

  - adhoc_client_crud_data_access.c — An Adhoc C client for the `crud.sql` example which
  demonstrates 2-way communication between C and the stored procedure using
  auto-generated helper functions.
