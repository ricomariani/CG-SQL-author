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
In this way it's a lot more like, say, the C compiler than it is like, say, Java
or C# or something like that.  This means several things:

* You don't have to tell CQL about all your schema in all your files,
so particular stored procs can be more encapsulated
* You can have different databases mounted in different places and CQL
won't care; you provide the database connection to the stored procedures when you call them, and that database is assumed to have the tables declared in this translation unit
* Several different schema can be maintained by CQL,
even in the same database, and they won't know about each other

To make this possible there are a few interesting features

### Declaring Procedures Defined Elsewhere

Stored procedures defined in another file can be declared to CQL in various
ways for each major type of stored procedure.  These are covered in
the sections below.

### Simple Procedures (database free):

```sql
declare proc foo(id int, out name text!);
```

This introduces the symbol name without providing the body.
This has important variations.

### Procedures that use the database

```sql
declare proc foo(id int, out name text!) USING TRANSACTION;
```

Most procedures you write will use SQLite in some fashion,
maybe a `select` or something.  The `USING TRANSACTION` annotation indicates that
the proc in question uses the database and therefore the generated code
will need a database connection in-argument and it will return a SQLite error code.

### Procedures that create a result set

If the procedure in question is going to use `select` or `call` to create a result set,
the type of that result set has to be declared.  An example might look like this:

```sql
declare proc with_result_set () (id int!,
                                 name text,
                                 rate long,
                                 type int,
                                 size real);
```

This says that the procedure takes no arguments (other than the implicit database
connection) and it has an implicit out-argument that can be read to get a result
set with the indicated columns: id, name, rate, type, and size.
This form implies `USING TRANSACTION`.

### Procedures that return a single row with a value cursor

If the procedure emits a cursor with the `OUT` statement to produce a single
row then it can be declared as follows:

```sql
declare proc with_result_set () OUT (id int!,
                                     name text,
                                     rate long,
                                     type int,
                                     size real);
```

This form can have `USING TRANSACTION`  or not, since it is possible
to emit a row with a value cursor and never use the database.  See the
previous chapter for details on the `OUT` statement.

### Procedures that return a full result set

If the procedure emits many rows with the `OUT UNION` statement to produce a full result set
then it can be declared as follows:

```sql
declare proc with_result_set () OUT UNION (id int!,
                                     name text,
                                     rate long,
                                     type int,
                                     size real);
```

This form can have `USING TRANSACTION`  or not, since it is possible
to emit a rows with a value cursor and never use the database.  See the
previous chapter for details on the `OUT UNION` statement.

### Exporting Declared Symbols Automatically

To avoid errors, the declarations for any given file can be automatically
created by adding something like `--generate_exports` to the command
line. This will require an additional file name to be passed in the `--cg`
portion to capture the exports.

That file can then be referenced `@include` to add the declarations to the input
stream. And of course these could be combined into useful units so that you
don't have to name each include file individually every time.  Note that any
given `@include` is processed exactly once, a second attempt to include the same
file is disregarded.

Nomenclature is perhaps a bit weird here.  You use `--generate_exports` to export
the stored procedure declarations from a translation unit.  Of course those
exported symbols are what you then import in some other module.  Sometimes this
output file is called `foo_imports.sql` because those exports are of course exactly
what you need to import `foo`.  You can use whatever convention you like of course,
CQL doesn't care.  The full command line might look something like this:

```
cql --in foo.sql --cg foo.h foo.c foo_imports.sql --generate_exports
```

Using the pre-processor you can get declarations from elsewhere with
a directive like this:

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

So far we've avoided discussing the generated C code in any details but here
it seems helpful to show exactly what these declarations correspond to in the
generated C to demystify all this.  There is a very straightforward conversion.

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

As you can see, these declarations use exactly the normal SQLite
types and so it is very easy to declare a procedure in CQL and then implement it
yourself in straight C, simply by conforming to the contract.

Importantly, SQLite does not know anything about CQL stored procedures, or anything at all about CQL
really so CQL stored procedure names cannot be used in any way in SQL statements.  CQL
control flow like the `call` statement can be used to invoke other procedures and
results can be captured by combing the `OUT` statement and a `DECLARE CURSOR` construct
but SQLite is not involved in those things.  This is another place where the inherent
two-headed nature of CQL leaks out.

Finally, this is a good place to reinforce that procedures with any of the structured
result types (`select`, `out`, `out union`) can be used with a suitable cursor.

```sql
proc get_stuff()
begin
  select * from stuff;
end;
```

Can be used in two interesting ways:

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
Assuming that `get_stuff` and `get_other_stuff` have the same shape, then
this procedure simply passes on one or the other's result set unmodified
as its own return value.

But you could do more than simply pass on the result.

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

Here we can see that we used the procedure to get the results and then
process them directly somehow.

And of course the result of an `OUT` can similarly be processed using
a value cursor, as previously seen.

These combinations allow for pretty general composition of stored procedures
so long as they are not recombined with SQLite statements.
