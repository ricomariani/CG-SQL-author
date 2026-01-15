# CG/SQL User FAQ

Frequently asked questions for CG/SQL users. For developer/contributor questions, see the [Developer FAQ](DEVELOPER_FAQ.md).

## Getting Started

### What is CG/SQL?

CG/SQL is a code generation system that compiles stored procedures written in a SQL variant into C or Lua code that uses SQLite's API. It provides strong typing, compile-time error checking, and automated code generation to make working with SQLite safer and more maintainable.

**Learn more:**
- [Introduction](docs/quick_start/introduction.md)
- [User Guide Chapter 1](docs/user_guide/01_introduction.md)

### How do I install and build CG/SQL?

Build from source by running `make` in the `sources` directory. You'll need standard build tools (gcc/clang, flex, bison).

**Step-by-step guide:**
- [Getting Started with CG/SQL](docs/quick_start/getting-started.md)

**Example:**
```bash
cd sources
make clean
make
# Binary available at: out/cql
```

### How do I write my first CG/SQL program?

Start with a simple "Hello World" procedure:

```sql
declare procedure printf no check;

create proc hello()
begin
  call printf("Hello, world\n");
end;
```

Compile it with:
```bash
cql --in hello.sql --cg hello.h hello.c
```

**Complete tutorial:**
- [Writing Your First Program](docs/user_guide/01_introduction.md#getting-started)
- [A Sample Program with Database](docs/user_guide/02_using_data.md#a-sample-program)

## Data Types and Variables

### What data types does CG/SQL support?

CG/SQL supports these basic types:
- `integer` (int) - 32-bit integer
- `long` (long integer) - 64-bit integer  
- `real` - C double
- `bool` (boolean) - normalized 0/1
- `text` - immutable string reference
- `blob` - immutable blob reference
- `object` - object reference

All types can be marked `NOT NULL` (or `!` shorthand).

**Details:**
- [Data Types](docs/user_guide/01_introduction.md#variables-and-arithmetic)
- [Type System](docs/user_guide/03_expressions_fundamentals.md)

**Example:**
```sql
declare x integer not null;  -- or: more briefly var x int!
var name text;               -- nullable by default
let count := 0;              -- type inferred as int!
```

### How do I declare and use variables?

Variables must be declared before use. Use `VAR` with explicit types or `LET` for type inference:

```sql
-- Explicit declaration
var temperature int!;
set temperature := 72;

-- Type inference with LET
let count := 0;        -- inferred as int!
let name := "Alice";   -- inferred as text!

-- Shorthand assignment (without SET)
temperature := 75;
count += 1;
```

**Learn more:**
- [Variables](docs/user_guide/01_introduction.md#variables-and-arithmetic)
- [Assignment](docs/user_guide/04_procedures_functions_control_flow.md)

## Working with Databases

### How do I create and query tables?

Define schema with standard SQL DDL, then query with CQL procedures:

```sql
-- Define schema
create table users(
  id integer primary key,
  name text not null,  -- ! works here too
  age integer
);

-- Insert data
proc add_user(id_ int!, name_ text!, age_ int)
begin
  insert into users(id, name, age) values(id_, name_, age_);
end;

-- Query data
proc get_users()
begin
  select * from users order by name;
end;
```

**Documentation:**
- [Using Data](docs/user_guide/02_using_data.md)
- [Schema Management](docs/user_guide/10_schema_management.md)

### How do I work with cursors and result sets?

Cursors let you iterate over query results. CG/SQL generates helper functions for result set access:

```sql
create proc get_active_users()
begin
  -- This proc returns a result set
  select id, name from users where age >= 18;
end;

create proc process_users()
begin
  cursor C for call get_active_users();
  loop fetch C
  begin
    call printf("User: %s\n", C.name);
  end;
end;
```

**Complete guide:**
- [Cursors](docs/user_guide/05_cursors.md)
- [Result Sets](docs/user_guide/07_result_sets.md)

### How do I handle NULL values?

CG/SQL enforces NULL safety at compile time. You must declare if a variable can be NULL:

```sql
declare x integer;        -- nullable
declare y integer not null;  -- not null (or use int!)

-- This is an error:
set y := x;  -- ERROR: cannot assign nullable to not null

-- Use coalesce or check first:
set y := coalesce(x, 0);

-- Or use IF to check:
if x is not null then
  set y := x;
end if;
```

**Learn more:**
- [Null Safety](docs/user_guide/03_expressions_fundamentals.md)
- [Nullable Types](docs/user_guide/01_introduction.md)

## Procedures and Functions

### How do I pass parameters to procedures?

Parameters can be IN (default), OUT, or INOUT:

```sql
create proc get_user_info(
  id_ integer not null,           -- IN parameter
  out name_ text,                 -- OUT parameter
  inout status_ integer not null  -- INOUT parameter
)
begin
  name_ := (select name from users where id = id_);
  set status_ := status_ + 1;
end;
```

**Learn more:**
- [Parameters](docs/user_guide/04_procedures_functions_control_flow.md)
- [OUT Parameters](docs/user_guide/05_cursors.md)

## Schema Management

### How do I handle schema upgrades?

CG/SQL provides schema versioning with `@create` and `@delete` annotations:

```sql
-- Version 1
create table users(
  id integer primary key,
  name text not null
) @create(1);

-- Version 2: add column
create table users(
  id integer primary key,
  name text not null,
  email text @create(2)
) @create(1);

-- Version 3: delete column (logical deletion)
create table users(
  id integer primary key,
  name text not null,
  email text @create(2) @delete(3)
) @create(1);
```

CG/SQL generates upgrade procedures automatically.

**Complete guide:**
- [Schema Management](docs/user_guide/10_schema_management.md)
- [Schema Upgrades](docs/user_guide/11_previous_schema_validation.md)

### How do I organize schema into regions?

Use `@declare_schema_region` to group related schema:

```sql
@declare_schema_region user_management;
@declare_schema_region reporting;

@begin_schema_region user_management;

create table users(...) @create(1);
create table roles(...) @create(1);

@end_schema_region;
```

**Learn more:**
- [Schema Regions](docs/user_guide/10_schema_management.md)

## Testing

### How do I test my CG/SQL procedures?

Use `@dummy_test` and `@dummy_table` attributes to create test scaffolding:

```sql
-- Procedure to test
proc get_expensive_items(min_price real!)
begin
  select * from products where price > min_price;
end;

-- Generate test harness
[[autotest=get_expensive_items]]
create proc dummy_test()
begin
end;
```

This generates test code with mock data insertion.

**Complete guide:**
- [Testability Features](docs/user_guide/12_testability_features.md)
- [Test Helpers](docs/user_guide/08_test_helpers.md)

## Common Patterns

### How do I insert a row with all columns from arguments?

Use the `FROM ARGUMENTS` shorthand:

```sql
create proc insert_user(like users)
begin
  insert into users from arguments;
end;
```

This automatically matches procedure arguments to table columns.

**Learn more:**
- [Statement Forms](docs/user_guide/09_statements_summary_and_error_checking.md)

### How do I create a procedure that returns a result set shaped like a table?

-- Select the results directly

```sql
create proc get_all_users()
begin
  select * from users;
end;

-- Or load a cursor and filter as you see fit (this example is silly)
create proc get_users()
begin
  cursor U for select id, name from users;
  loop fetch U
     if U.id < 500 then
        out union U;
     end;
  end;
end;
```

**Documentation:**
- [Result Sets](docs/user_guide/07_result_sets.md)

### How do I reuse query fragments?

Use shared fragments with CTEs:

```sql

-- this is like a view with parameters
[[shared_fragment]]
proc active_users_fragment(is_active bool!)
begin
  select * from users where active = is_active;
end;

proc get_active_admins()
begin
  with
    active_users(*) as (call active_users_fragment(true))
  select * from active_users where is_admin = 1;
end;
```

**Complete guide:**
- [Shared Fragments](docs/user_guide/14_shared_fragments.md)

## Advanced Features

### Can I use CG/SQL with other languages?

Yes! CG/SQL generates JSON output that can be used to create bindings:

- **Java**: Result set wrappers
- **Objective-C**: Class definitions  
- **Lua**: Direct Lua code generation (alternative to C)
- **Python**: Via JSON processing

**Learn more:**
- [JSON Output](docs/user_guide/13_json_output.md)
- [Lua Code Generation](docs/developer_guide/10_lua_notes.md)

### How do I generate query plans?

Use the `--rt query_plan` option:

```bash
cql --in myfile.sql --rt query_plan --cg plan.sql
```

This generates SQL that extracts query plans using `EXPLAIN QUERY PLAN`.

**Learn more:**
- [Query Plan Generation](docs/user_guide/15_query_plan_generation.md)
- [Query Plan Details](docs/developer_guide/09_query_plan.md)

## Troubleshooting

### Where can I find error codes and their meanings?

All error messages are documented with explanations:

**Reference:**
- [Error Codes Appendix](docs/user_guide/appendices/04_error_codes.md)

### How do I debug generated C code?

The generated C code is readable and maps closely to your CQL. Use these tips:

1. Look at the `.h` file for procedure signatures
2. The `.c` file shows the implementation
3. Use `--dev` flag for extra debugging output
4. Enable SQLite tracing in your test harness

**Learn more:**
- [Understanding C Code Generation](docs/developer_guide/03_c_code_generation.md)
- [Runtime Configuration](docs/developer_guide/05_cql_runtime.md)

### Why am I getting "name not found" errors?

Common causes:
- Variable not declared in scope
- Table/column doesn't exist in schema
- Typo in identifier name
- Schema not included in compilation

CG/SQL is case-insensitive but the canonical case from declaration is used.

**Learn more:**
- [Name Resolution](docs/developer_guide/02_semantic_analysis.md)

## Quick Reference

### Where can I find a syntax cheatsheet?

- [CQL in 20 Minutes](docs/user_guide/appendices/06_cql_in_20_minutes.md)
- [Command Line Options](docs/user_guide/appendices/01_command_lines_options.md)
- [Grammar Railroad Diagrams](https://ricomariani.github.io/CG-SQL-author/cql_grammar.railroad.html)

### What are the most useful command line options?

```bash
# Generate C code
cql --in input.sql --cg output.h output.c

# Generate with runtime type (default is C)
cql --in input.sql --rt lua --cg output.lua

# Include schema files
cql --in myproc.sql --include_paths schema/ --cg out.c out.h

# Generate JSON output
cql --in input.sql --cg output.json

# Generate test helpers
cql --in input.sql --rt c --cg output.h output.c --generate_test_helpers
```

**Full reference:**
- [Command Line Options](docs/user_guide/appendices/01_command_lines_options.md)

## Getting Help

### Where can I ask questions?

- [GitHub Issues](https://github.com/ricomariani/CG-SQL-author/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/ricomariani/CG-SQL-author/discussions) - Questions and discussions
- [CG/SQL Wiki](https://github.com/ricomariani/CG-SQL-author/wiki) - Examples and community resources

### How can I contribute?

See the [Developer FAQ](DEVELOPER_FAQ.md) and:
- [Contributing Guide](CONTRIBUTING.md)
- [Developer Notes](docs/contributors/dev_notes.md)
- [Testing Guide](docs/contributors/testing.md)
