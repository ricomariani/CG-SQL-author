---
title: "Chapter 6: Importing and Exporting Procedures"
weight: 6
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL generally doesn't see the whole world in one compilation.
In this way it's more like the C compiler than Java or C#.
This has some useful consequences:

* You don't have to tell CQL about all schema across all files;
  particular stored procedures can be encapsulated.
* You can mount different databases in different places; you provide the
  database connection when calling stored procedures, and that database is
  assumed to have the tables declared in this translation unit.
* Multiple independent schema can be maintained by CQL—even in the same
  database—and they won't need to know about each other.

To make this possible there are a few interesting features

### Importing Procedures (Declaring Procedures Defined Elsewhere)

Declare stored procedures defined in another file so you can call them.
Use forms appropriate to the procedure's behavior.

### Simple Procedures (Database-free)

```sql
declare proc foo(id int, out name text!);
```

This introduces the symbol name without providing the body.
Variations below add database usage and result types.

### Procedures that Use the Database

```sql
declare proc foo(id int, out name text!) USING TRANSACTION;
```

Most procedures use SQLite—e.g., a `SELECT`. The `USING TRANSACTION` annotation
indicates the procedure uses the database, so the generated code includes a
database connection argument and returns a SQLite error code.

### Procedures that Create a Result Set

If the procedure in question is going to use `select` or `call` to create a result set,
the type of that result set has to be declared.  An example might look like this:

```sql
declare proc with_result_set ()
  (id int!,  name text, rate long, type int, size real);
```

This declares a procedure with no arguments (other than the implicit database
connection) that produces a result set with the indicated columns: `id`, `name`,
`rate`, `type`, and `size`. This form implies `USING TRANSACTION`.

### Procedures that Return a Single Row (Value Cursor)

If the procedure emits a cursor with the `OUT` statement to produce a single
row then it can be declared as follows:

```sql
declare proc with_result_set ()
  OUT (id int!, name text, rate long, type int, size real);
```

This form may or may not include `USING TRANSACTION`; it's possible
to emit a row with a value cursor without using the database. See the previous
chapter for details on the `OUT` statement.

### Procedures that Return a Full Result Set

If the procedure emits many rows with the `OUT UNION` statement to produce a
full result set then it can be declared as follows:

```sql
declare proc with_result_set ()
  OUT UNION (id int!, name text, rate long, type int, size real);
```

This form may or may not include `USING TRANSACTION`; it's possible
to emit rows with a value cursor without using the database. See the previous
chapter for details on the `OUT UNION` statement.

### Exporting Declarations Automatically

To avoid errors, the declarations for any given file can be automatically
created by adding `--generate_exports` to the command line. This will require an
additional file name to be passed in the `--cg` portion to capture the exports.

Reference that file with `@include` to add the declarations to the input
stream. These can be combined into useful units so that you
don't have to name each include file individually every time.  Note that any
given `@include` is processed exactly once, a second attempt to include the same
file is disregarded.

Naming hint: You use `--generate_exports` to export stored procedure declarations
from a translation unit. Those exported symbols are what you import elsewhere.
Some teams name the output file `foo_imports.sql` (exports for importing `foo`).
Use any convention you prefer. Example:

```
cql --in foo.sql --cg foo.h foo.c foo_imports.sql --generate_exports
```

Use the pre-processor to include declarations from elsewhere:

```
@include "foo_imports.sql"
```

### Declaration Examples

Here are some more examples directly from the CQL test cases; these are all
auto-generated with `--generate_exports`.

```sql
DECLARE PROC test (i INT!);

DECLARE PROC out_test (OUT i INT!, OUT ii INT);

DECLARE PROC outparm_test (OUT foo INT!) USING TRANSACTION;

DECLARE PROC select_from_view () (id INT!, type INT);

DECLARE PROC make_view () USING TRANSACTION;

DECLARE PROC copy_int (a INT, OUT b INT);

DECLARE PROC complex_return ()
  (_bool BOOL!,
   _integer INT!,
   _longint LONG!,
   _real REAL NOT NULL,
   _text TEXT!,
   _nullable_bool BOOL);

DECLARE PROC outint_nullable (
  OUT output INT,
  OUT result BOOL!)
USING TRANSACTION;

DECLARE PROC outint_notnull (
  OUT output INT!,
  OUT result BOOL!)
USING TRANSACTION;

DECLARE PROC obj_proc (OUT an_object OBJECT);

DECLARE PROC insert_values (
  id_ INT!,
  type_ INTEGER)
  USING TRANSACTION;
```

Mapping to generated C: these declarations correspond directly to C signatures.
Conversion is straightforward.

```c
void test(cql_int32 i);

void out_test(
  cql_int32 *_Nonnull i,
  cql_nullable_int32 *_Nonnull ii);

cql_code outparm_test(
  sqlite3 *_Nonnull _db_,
  cql_int32 *_Nonnull foo);

cql_code select_from_view_fetch_results(
  sqlite3 *_Nonnull _db_,
  select_from_view_result_set_ref _Nullable *_Nonnull result_set);

cql_code make_view(sqlite3 *_Nonnull _db_);

void copy_int(cql_nullable_int32 a, cql_nullable_int32 *_Nonnull b);

cql_code complex_return_fetch_results(
  sqlite3 *_Nonnull _db_,
  complex_return_result_set_ref _Nullable *_Nonnull result_set);

cql_code outint_nullable(
  sqlite3 *_Nonnull _db_,
  cql_nullable_int32 *_Nonnull output,
  cql_bool *_Nonnull result);

cql_code outint_notnull(
  sqlite3 *_Nonnull _db_,
  cql_int32 *_Nonnull output,
  cql_bool *_Nonnull result);

void obj_proc(
  cql_object_ref _Nullable *_Nonnull an_object);

cql_code insert_values(
  sqlite3 *_Nonnull _db_,
  cql_int32 id_,
  cql_nullable_int32 type_);
```

These declarations use normal SQLite types, so it is easy to declare a procedure
in CQL and implement it in C by conforming to the contract.

Important: SQLite does not know anything about CQL stored procedures, so stored
procedure names cannot be used in SQL statements. CQL control flow (e.g., `call`)
invokes procedures; results can be captured with `OUT` plus `DECLARE CURSOR`.
SQLite is not involved in these operations.

Procedures with structured result types (`SELECT`, `OUT`, `OUT UNION`) can be
used with a suitable cursor.

```sql
proc get_stuff()
begin
  select * from stuff;
end;
```

Two usage patterns:

```sql
proc meta_stuff(meta bool)
begin
  if meta then
    call get_stuff();
  else
    call get_other_stuff();
  end if;
end;
```
If `get_stuff` and `get_other_stuff` have the same shape, this procedure
passes one or the other's result set through as its own return value.

Or process results directly:

```sql
proc meta_stuff(meta bool)
begin
  cursor C for call get_stuff();  -- or get_meta_stuff(...)
  loop fetch C
  begin
     -- do stuff with C
     -- may be out union some of the rows after adjustment even
  end;
end;
```

This procedure fetches rows and processes them directly.

Likewise, the result of an `OUT` can be processed using a value cursor.

These combinations allow general composition of stored procedures, independent
of SQLite statements.
