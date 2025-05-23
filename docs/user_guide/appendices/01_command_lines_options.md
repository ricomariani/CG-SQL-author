---
title: "Appendix 1: Command Line Options"
weight: 1
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL has a variety of command line (CLI) options but many of them are only interesting for cql development.  Nonetheless this is a comprehensive list:

>NOTE: CQL is often used after the c pre-processor is run so this kind of invocation is typical:

```
cc -E -x c foo.sql | cql [args]
```

### With No Options
* emits a usage message

### --in file

* reads the given file for the input instead of stdin
* the input should probably have already been run through the C pre-processor as above
* returns non-zero if the file fails to parse

Example:
```
cql --in test.sql
```

### --sem
* performs semantic analysis on the input file ONLY
* the return code is zero if there are no errors

Example:
```
cql --in sem_test.sql --sem
```

### --ast
* walks the AST and prints it to stdout in human readable text form
* may be combined with --sem (semantic info will be included)
Example
```
cql --in sem_test.sql --sem --ast >sem_ast.out
```

### --echo
* walks the AST and emits the text of a program that would create it
* this has the effect of "beautifying" badly formatted input or "canonicalizing" it
  * some sensible indenting is added but it might not be the original indenting
  * extraneous whitespace, parens, etc. are removed
* may be combined with --sem (in which case you see the source after any rewrites for sugar)
* this also validates that the input can be parsed

Example
```
cql --in test.sql --echo >test.out  # test.out is "equivalent" to test.sql
```

### --dot
* prints the internal AST to stdout in DOT format for graph visualization
* this is really only interesting for small graphs for discussion as it rapidly gets insane

Example:
```
cql --dot --in dottest.sql
```
### --cg output1 output2 ...

* any number of output files may be needed for a particular result type, two is common
* the return code is zero if there are no errors
* any --cg option implies --sem

Example:

```
cql --in foo.sql --cg foo.h foo.c
```

### --nolines

* Suppress the # directives for lines.  Useful if you need to debug the C code.

Example:

```
cql --in test.sql --nolines --cg foo.h foo.c
```

### --global_proc name
* any loose SQL statements not in a stored proc are gathered and put into a procedure of the given name
* when generating a schema migrate script the global proc name is used as a prefix on all of the artifacts so that there can be several independent migrations linked into a single executable

### --compress
* for use with the C result type, (or any similar types added to the runtime array in your compiler)
* string literals for the SQL are broken into "fragments" the DML is then represented by an array of fragments
* since DML is often very similar there is a lot of token sharing possible
* the original string is recreated at runtime from the fragments and then executed
* comments show the original string inline for easier debugging and searching

>NOTE: different result types require a different number of output files with different meanings

### --test
* some of the output types can include extra diagnostics if `--test` is included
* the test output often makes the outputs badly formed so this is generally good for humans only

### --dev
* some codegen features only make sense during development, this enables dev mode to turn those one
** example: [explain query plan](../15_query_plan_generation.md)

### --exp
* runs macro expansion without semantic analysis
* combined with `--echo` this is kind of like `cc -E` it can give you a view of what happened after the pre-processing
* combined with `--ast` it is a useful test tool (its primary function)

### --c_include_namespace
* for the C codegen runtimes, it determines the header namespace (as in #include "namespace/file.h") that goes into the output C file
* if this option is used, it is prefixed to the first argment to --cg to form the include path in the C file
* if absent there is no "namespace/" prefix

### --c_include_path
* for the C codegen runtimes, it determines the full header path (as in #include "your_arg") that goes into the output C file
* if this option is used, the first argment to --cg controls only the output path and does not appear in include path at all
* this form overrides --c_include_namespace if both are specified

### Result Types (--rt *)

These are the various outputs the compiler can produce.

#### --rt c
* requires two output files (foo.h and foo.c)
* this is the standard C compilation of the sql file

##### --cqlrt foo.h
* emits `#include "foo.h"` into the C output instead of `#include "cqlrt.h"`

##### --generate_type_getters
* changes C output for CQL result sets so that the field readers used shared functions to get fields of a certain type
* this style of codegen makes result-sets more interoperable with each other if they have similar shape so it can be useful

##### --generate_exports
* adds an additional output file
 * example:  `--in foo.sql --generate_exports --rt c --cg foo.h foo.c foo_exports.sql
* the output file `foo_exports.sql` includes procedure declarations for the contents of `foo.sql`
* basically automatically generates the CQL header file you need to access the procedures in the input from some other file
 * if it were C it would be like auto-generating `foo.h` from `foo.c`

#### --rt lua
* requires one output file (foo.lua)
* this is the standard Lua compilation of the sql file

#### --rt schema
* produces the canonical schema for the given input files
* stored procedures etc. are removed
* whitespace etc. is removed
* suitable for use to create the next or first "previous" schema for schema validation
* requires one output file

#### --rt schema_upgrade
* produces a CQL schema upgrade script which can then be compiled with CQL itself
* see the chapter on schema upgrade/migration: [Chapter 10](../10_schema_management.md)
* requires one output file (foo.sql)

##### --include_regions a b c
* the indicated regions will be declared
* used with `--rt schema_upgrade` or `--rt schema`
* in the upgrade case excluded regions will not be themselves upgraded, but may be referred, to by things that are being upgraded

##### --exclude_regions x y z
* the indicated regions will still be declared but the upgrade code will be suppressed, the presumption being that a different script already upgrades x y z
* used with `--rt schema_upgrade`

##### --min_schema_version n
* the schema upgrade script will not include upgrade steps for schema older than the version specified

##### --schema_exclusive
* the schema upgrade script assumes it owns all the schema in the database, it aggressively removes other things

#### --rt json_schema
* produces JSON output suitable for consumption by downstream codegen
* the JSON includes a definition of the various entities in the input
* see the section on JSON output for details

#### --rt query_plan
* produces CQL output which can be re-compiled by CQL as normal input
* the output consists of a set of procedures that will emit all query plans for the DML that was in the input
* see [Chapter 15](../15_query_plan_generation.md)

#### --rt stats
* produces  a simple .csv file with node count information for AST nodes per procedure in the input
* requires one output file (foo.csv)
