---
title: "Chapter 7: Result Sets"
weight: 7
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

Most of this tutorial is about the CQL language itself but here we must diverge a bit.  The purpose of the
result set feature of CQL is to create a C interface to SQLite data.  Because of this
there are a lot of essential details that require looking carefully at the generated C code.  Appendix 2
covers this code in even more detail but here it makes sense to at least talk about the interface.

Let's say we have this simple stored procedure:

```sql
create table foo(id int!, b bool, t text);

proc read_foo(id_ int!)
begin
  select * from foo where id = id_;
end;
```

We've created a simple data reader: this CQL code will cause the compiler to
generate helper functions to read the data and materialize a result set.

Let's look at the public interface of that result set now considering the most essential pieces.

```c
/* this is almost everything in the generated header file */
#define read_foo_data_types_count 3
cql_result_set_type_decl(
  read_foo_result_set, \
  read_foo_result_set_ref);

extern cql_int32 read_foo_get_id(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_bool read_foo_get_b_is_null(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_bool read_foo_get_b_value(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_string_ref _Nullable read_foo_get_t(
   read_foo_result_set_ref  _Nonnull result_set,
   cql_int32 row);
extern cql_int32 read_foo_result_count(read_foo_result_set_ref
  _Nonnull result_set);
extern cql_code read_foo_fetch_results(sqlite3 *_Nonnull _db_,
  read_foo_result_set_ref _Nullable *_Nonnull result_set,
  cql_int32 id_);
#define read_foo_row_hash(result_set, row) \
  cql_result_set_get_meta((cql_result_set_ref)(result_set))->\
  rowHash((cql_result_set_ref)(result_set), row)
#define read_foo_row_equal(rs1, row1, rs2, row2) \
cql_result_set_get_meta((cql_result_set_ref)(rs1)) \
 ->rowsEqual( \
   (cql_result_set_ref)(rs1),  row1,  \
   (cql_result_set_ref)(rs2),  row2)
```

Let's consider some of these individually now
```c
cql_result_set_type_decl(
  read_foo_result_set,
  read_foo_result_set_ref);
```
This declares the data type for `read_foo_result_set` and the associated object reference `read_foo_result_set_ref`.
As it turns out, the underlying data type for all result sets is the same, and only the shape of the data varies.


```c
extern cql_code read_foo_fetch_results(sqlite3 *_Nonnull _db_,
  read_foo_result_set_ref _Nullable *_Nonnull result_set,
  cql_int32 id_);
```
The result set fetcher method gives you a `read_foo_result_set_ref` if
it succeeds.  It accepts the `id_` argument which it will internally pass
along to `read_foo(...)`.  The latter function provides a `sqlite3_stmt*`
which can then be iterated in the fetcher.  This method is the main
public entry point for result sets.

Once you have a result set, you can read values out of it.

```c
extern cql_int32 read_foo_result_count(read_foo_result_set_ref
  _Nonnull result_set);
```
That function tells you how many rows are in the result set.

For each row you can use any of the row readers:

```c
extern cql_int32 read_foo_get_id(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_bool read_foo_get_b_is_null(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_bool read_foo_get_b_value(read_foo_result_set_ref
  _Nonnull result_set, cql_int32 row);
extern cql_string_ref _Nullable read_foo_get_t(
   read_foo_result_set_ref  _Nonnull result_set,
   cql_int32 row);
```

These let you read the `id` of a particular row, and get a `cql_int32` or you can read the nullable boolean,
using the `read_foo_get_b_is_null` function first to see if the boolean is null and then `read_foo_get_b_value`
to get the value.  Finally the string can be accessed with `read_foo_get_t`.  As you can see, there is a
simple naming convention for each of the field readers.

>NOTE: The compiler has runtime arrays that control naming conventions as well as using CamelCasing.
>Additional customizations may be created by adding new runtime arrays into the CQL compiler.

Finally, also part of the public interface, are these macros:

```c
#define read_foo_row_hash(result_set, row)
#define read_foo_row_equal(rs1, row1, rs2, row2)
```

These use the CQL runtime to hash a row or compare two rows from identical result
set types.  Metadata included in the result set allows general purpose code to work for
every result set.  Based on configuration, result set copying methods can also
be generated.   When you're done with a result set you can use the `cql_release(...)`
method to free the memory.

Importantly, all of the rows from the query in the stored procedure are materialized
immediately and become part of the result set.  Potentially large amounts of memory can
be used if a lot of rows are generated.

The code that actually creates the result set starting from the prepared statement is always the same.
The essential parts are:


First, a constant array that holds the data types for each column.

```C
uint8_t read_foo_data_types[read_foo_data_types_count] = {
  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL, // id
  CQL_DATA_TYPE_BOOL, // b
  CQL_DATA_TYPE_STRING, // t
};
```

All references are stored together at the end of the row, so we only need the count
of references and the offset of the first one to do operations like `cql_retain` or `cql_release`
on the row.

```
#define read_foo_refs_offset cql_offsetof(read_foo_row, t) // count = 1
```

Lastly we need metadata to tell us count of columns and the offset of each column within the row.

```C
static cql_uint16 read_foo_col_offsets[] = { 3,
  cql_offsetof(read_foo_row, id),
  cql_offsetof(read_foo_row, b),
  cql_offsetof(read_foo_row, t)
};
```

Using the above we can now write this fetcher
```
CQL_WARN_UNUSED cql_code
read_foo_fetch_results(
  sqlite3 *_Nonnull _db_,
  read_foo_result_set_ref _Nullable *_Nonnull result_set,
  cql_int32 id_)
{
  sqlite3_stmt *stmt = NULL;
  cql_profile_start(CRC_read_foo, &read_foo_perf_index);

  // we call the original procedure, it gives us a prepared statement
  cql_code rc = read_foo(_db_, &stmt, id_);

  // this is everything you need to know to fetch the result
  cql_fetch_info info = {
    .rc = rc,
    .db = _db_,
    .stmt = stmt,
    .data_types = read_foo_data_types,
    .col_offsets = read_foo_col_offsets,
    .refs_count = 1,
    .refs_offset = read_foo_refs_offset,
    .rowsize = sizeof(read_foo_row),
    .crc = CRC_read_foo,
    .perf_index = &read_foo_perf_index,
  };

  // this function does all the work, it cleans up if .rc is an error code.
  return cql_fetch_all_results(&info, (cql_result_set_ref *)result_set);
}
```

### Results Sets From `OUT UNION`

The `out` keyword was added for writing procedures that produce a
single row result set.  With that, it became possible to make any single
row result you wanted, assembling it from whatever sources you needed.
That is an important case as single row results happen frequently and they
are comparatively easy to create and pass around using C structures for
the backing store.  However, it's not everything; there are also cases
where full flexibility is needed while producing a standard many-row
result set.  For this we have `out union` which was discussed fully in
Chapter 5.  Here we'll discuss the code generation behind that.


Here’s an example from the CQL tests:
```sql
proc some_integers(start int!, stop int!)
begin
  cursor C like select 1 v, 2 v_squared, "xx" some_text;
  var i int!;
  set i := start;
  while (i < stop)
  begin
   fetch C(v, v_squared, junk) from values (i, i*i, printf("%d", i));
   out union C;
   set i := i + 1;
 end;
end;
```

In this example the entire result set is made up out of thin air.
Of course any combination of this computation or data-access is possible,
so you can ultimately make any rows you want in any order using SQLite
to help you as much or as little as you need.

Virtually all the code pieces to do this already exist for normal
result sets.  The important parts of the output code look like this in
your generated C.

We need a buffer to hold the rows we are going to accumulate;  We use
`cql_bytebuf` just like the normal fetcher above.

```c
// This bit creates a growable buffer to hold the rows
// This is how we do all the other result sets, too
cql_bytebuf _rows_;
cql_bytebuf_open(&_rows_);
```

We need to be able to copy the cursor into the buffer and retain any internal references

```
// This bit is what you get when you "out union" a cursor "C"
// first we +1 any references in the cursor then we copy its bits
cql_retain_row(C_);   // a no-op if there is no row in the cursor
if (C_._has_row_) cql_bytebuf_append(&_rows_, (const void *)&C_, sizeof(C_));
```

Finally, we make the rowset when the procedure exits. If the procedure
is returning with no errors the result set is created, otherwise the
buffer is released.  The global `some_integers_info` has constants that
describe the shape produced by this procedure just like the other cases
that produce a result set.

```
cql_results_from_data(_rc_,
                      &_rows_,
                      &some_integers_info,
                      (cql_result_set_ref *)_result_set_);
```
The operations here are basically the same ones that will happen inside of
the standard helper `cql_fetch_all_results`, the difference, of course,
is that you write the loop manually and therefore have full control of
the rows as they go in to the result set.

In short, the overhead is pretty low.  What you’re left with is pretty
much the base cost of your algorithm.  The cost here is very similar to
what it would be for any other thing that make rows.

Of course, if you make a million rows, well, that would burn a lot
of memory.

### A Working Example

Here's a fairly simple example illustrating some of these concepts
including the reading of rowsets.

```sql
-- hello.sql:

proc hello()
begin

  create table my_data(
    pos int! primary key,
    txt text!
  );

  insert into my_data values(2, 'World');
  insert into my_data values(0, 'Hello');
  insert into my_data values(1, 'There');

  select * from my_data order by pos;
end;
```

And this main code to open the database and access the procedure:

```c
// main.c

#include <stdlib.h>
#include <sqlite3.h>

#include "hello.h"

int main(int argc, char **argv)
{
  sqlite3 *db;
  int rc = sqlite3_open(":memory:", &db);
  if (rc != SQLITE_OK) {
    exit(1); /* not exactly world class error handling but that isn't the point */
  }
  hello_result_set_ref result_set;
  rc = hello_fetch_results(db, &result_set);
  if (rc != SQLITE_OK) {
    printf("error: %d\n", rc);
    exit(2);
  }

  cql_int32 result_count = hello_result_count(result_set);

  for(cql_int32 row = 0; row < result_count; row++) {
    cql_string_ref text = hello_get_txt(result_set, row);
    cql_alloc_cstr(ctext, text);
    printf("%d: %s\n", row, ctext);
    cql_free_cstr(ctext, text);
  }
  cql_result_set_release(result_set);

  sqlite3_close(db);
}
```

From these pieces you can make a working example like so:

```sh
# ${cgsql} refers to the root directory of the CG-SQL sources
#
cql --in hello.sql --cg hello.h hello.c
cc -o hello -I ${cgsql}/sources main.c hello.c ${cgsql}/sources/cqlrt.c -lsqlite3
./hello
```

Additional demo code is available in [Appendix 10](./appendices/10_working_example.md)

### Nested Result Sets (Parent/Child)

There are many cases where you might want to nest one result set inside of another one.  In order to
do this ecomomically you must be able to run a parent query and a child query and
then link the child rows to the parent rows.  One way to do this is of course to run one query for
each "child" but then you end up with `O(n)` child queries and if there are sub-children it would be
`O(n*m)` and so forth. What you really want to do here is something more like a join, only without
the cross-product part of the join.  Many systems have such features, sometimes they are called
"chaptered rowsets" but in any case there is a general need for such a thing.

To reasonably support nested results sets the CQL language has to be extended a variety of ways,
as discussed below.

Here are some things that happened along the way that are interesting.

#### Cursor Types and Result Types

One of the first problems we run into thinking about how a CQL program might express pieces of a rowset
and turn them into child results is that a program must be able to hash a row, append row data, and
extract a result set from a key.  These are the essential operations required. In order to do anything
at all with a child rowset, a program must be able to describe its type. Result sets must appear
in the type system as well as in the runtime.

To address this we use an object type with a special "kind", similar to how boxed statements are handled.
A result set has a type that looks like this: `object <proc_name set>`.  Here `proc_name` must the the name of a
procedure that returns a result set and the object will represent a result set with the corresponding columns in it.

#### Creating New Cursor Types From Existing Cursor Types

In addition to creating result set types, the language must be able to express cursors that capture the necessary
parent/child column. These are rows with all of the parent columns plus additional columns for the child rows
(note that you can have more than one child result set per parent).  So for instance you might have a list of
people, and one child result might be the details of the schools they attended and another could be the details
of the jobs they worked.

To accomplish this kind of shape, the language must be able to describe a new output row is that is the
same as the parent but includes columns for the the child results, too. This is done using a cursor
declaration that comes from a typed name list.  An example might be:

```sql
cursor C like (id int, name text);
```

Importantly, such constructs include the ability to reference existing shapes by name. So we might create
a cursor we need like so:

```sql
cursor result like (like parent_proc, child_result object<child_proc set>);
```

Where the above indicates all the parent columns plus a child result set.  Or more than one child result set if needed.

In addition, the language needs a way to conveniently cursor a that is only some of the columns of an existing cursor.
In particular, nested result sets require us to extract the columns that link the parent and child result sets.  The columns
we will "join" on.  To accomplish this the language extends the familiar notion:

```sql
cursor D like C;
```

To the more general form:

```sql
cursor pks like C(pk1, pk2);
```

Which chooses just the named fields from `C` and makes a cursor with only those. In this case
this primary key fields, `pk1` and `pk2`.  Additionally, for completeness, we add this form:

```sql
cursor vals like C(-pk1, -pk2);
```

To mean the cursor vals should have all the columns of `C` except `pk1` and `pk2` i.e. all the "values".

Using any number of intermediate construction steps, and maybe some `type X ...` statements,
any type can be formed from existing shapes by adding and removing columns.

Having done the above we can load a cursor that has just the primary keys with the usual form

```sql
fetch pks from C(like pks);
```

Which says we want to load `pks` from the fields of `C`, but using only the columns of `pks`.  That operation
is of course going to be an exact type match by construction.

#### Cursor Arguments

In order to express the requisite parent/child join, the language must be able to express operations like
"hash a cursor" (any cursor) or "store this row into the appropriate partition". The language provides no way
to write functions that can take any cursor and dynamically do things to it based on type information, but:

* we don't need very many of them,
* it's pretty easy to do that job in C (or lua if lua codegen is being used)

The minimum requirement is that the language must be able to declare a functions that takes a generic cursor argument
and to call such functions a generic cursor construct that has the necessary shape info.  This form does the job:

```sql
func cursor_hash(C cursor) long!;
```

And it can be used like so:

```sql
let hash := cursor_hash(C); -- C is any cursor
```

When such a call is made the C function `cursor_hash` is passed a so-called "dynamic cursor" pointer which includes:

* a pointer to the data for the cursor
* the count of fields
* the names of the fields
* the type/offset of every field in the cursor

With this information you can (e.g.) generically do the hash by applying a hash to each field and then combining
all of those hashes. This kind of function works on any cursor and all the extra data about the shape that's needed
to make the call is static, so really the cost of the call stays modest.  Details of the dynamic cursor type are in
`cqlrt_common.h` and there are many example functions now in the `cqlrt_common.c` file.

#### The Specific Parent/Child Functions

Three helper functions are used to do the parent/child join, they are:

```sql
DECLARE FUNC cql_partition_create ()
   CREATE OBJECT<partitioning> NOT NULL;

DECLARE FUNC cql_partition_cursor (
  part OBJECT<partitioning> NOT NULL,
  key CURSOR,
  value CURSOR)
    BOOL!;

DECLARE FUNC cql_extract_partition (
  part OBJECT<partitioning> NOT NULL,
  key CURSOR)
    CREATE OBJECT NOT NULL;
```

The first function makes a new partitioning.

The second function hashes the key columns of a cursor (specified by the key argument) and appends
the values provided in the second argument into a bucket for that key.  By making a pass over the
child rows a procedure can easily create a partitioning with each unique key combo having a buffer of all
the matching rows.

The third function is used once the partitioning is done.  Given a key again, this time from the parent rows,
a procedure can get the buffer it had accumulated and then make a result set out of it and return that.

Note that the third function returns a vanilla object type because it could be returning a result set of
any shape so a cast is required for correctness.

#### Result Set Sugar

Using the features mentioned above a developer could now join together any kind of complex parent and
child combo as needed, but the result would be a lot of error-prone code, To avoid this CQL adds
language sugar to do such partitionings automatically and type-safely, like so:


```sql
-- parent and child defined elsewhere
declare proc parent(x int!) (id int!, a int, b integer);
declare proc child(y int!) (id int!, u text, v text);

-- join together parent and child using 'id'
-- example x_, y_ arguments for illustration only
proc parent_child(x_ int!, y_ int!)
begin
  out union call parent(x_) join call child(y_) using (id);
end;
```

The generated code is simple enough, even though there's a good bit of it.
But it's a useful exercise to look at it once.  Comments added for clarity.

```sql
PROC parent_child (x_ INT!, y_ INT!)
BEGIN
  DECLARE __result__0 BOOL!;

  -- we need a cursor to hold just the key of the child row
  CURSOR __key__0 LIKE child(id);

  -- we need our partitioning object (there could be more than one per function
  -- so it gets a number, likewise everything else gets a number
  LET __partition__0 := cql_partition_create();

  -- we invoke the child and then iterate its rows
  CURSOR __child_cursor__0 FOR CALL child(y_);
  LOOP FETCH __child_cursor__0
  BEGIN
    -- we extract just the key fields (id in this case)
    FETCH __key__0(id) FROM VALUES(__child_cursor__0.id);

    -- we add this child to the partition using its key
    __result__0 := cql_partition_cursor(__partition__0, __key__0, __child_cursor__0);
  END;

  -- we need a shape for our result, the columns of the parent plus the child rowset
  CURSOR __out_cursor__0 LIKE (
    id INT!, a INT, b INT,
    child1 OBJECT<child SET> NOT NULL);

  -- now we call the parent and iterate it
  CURSOR __parent__0 FOR CALL parent(x_);
  LOOP FETCH __parent__0
  BEGIN
    -- we load the key values out of the parent this time, same key fields
    FETCH __key__0(id) FROM VALUES(__parent__0.id);

    -- now we create a result row using the parent columns and the child result set
    FETCH __out_cursor__0(id, a, b, child1) FROM
       VALUES(
         __parent__0.id, __parent__0.a, __parent__0.b,
         cql_extract_partition(__partition__0, __key__0));

    -- and then we emit that row
    OUT UNION __out_cursor__0;
  END;
END;
```

This code iterates the child once and the parent once and only has two database calls,
one for the child and one for the parent.  And this is enough to create parent/child result
sets for the most common examples.

#### Result Set Values

While the above is probably the most common case,  a developer might also want to make a procedure call
for each parent row to compute the child.  And, more generally, to work with result sets from procedure calls
other than iterating them with a cursor.

The iteration pattern:

```sql
cursor C for call foo(args);
```

is very good if the data is coming from (e.g.) a select statement and we don't want to materialize all
of the results if we can stream instead.  However, when working with result sets the whole point is to
create materialized results for use elsewhere.

Since we can express a result set type with `object<proc_name set>` the language also includes the ability
to call a procedure that returns a result set and capture that result.  This yields these forms:

```sql
declare child_result object<child set>;
set child_result := child(args);
```

or better still:

```sql
let child_result := child(args);
```

And more generally, this examples shows a manual iteration:

```sql
declare proc parent(x int!) (id int!, a int, b int);
declare proc child(id int!) (id int!, u text, v text);

proc parent_child(x_ int!, y_ int!)
begin
  -- the result is like the parent with an extra column for the child
  cursor result like (like parent, child object<child set>);

  -- call the parent and loop over the results
  cursor P for call parent(x_);
  loop fetch P
  begin
     -- compute the child for each P and then emit it
     fetch result from values(from P, child(P.id));
     out union result;
  end;
end;
```

After the sugar is applied to expand the types out, the net program is the following:

```sql
DECLARE PROC parent (x INT!) (id INT!, a INT, b INT);
DECLARE PROC child (id INT!) (id INT!, u TEXT, v TEXT);

PROC parent_child (x_ INT!, y_ INT!)
BEGIN
  CURSOR result LIKE (id INT!, a INT, b INT,
                              child OBJECT<child SET>);

  CURSOR P FOR CALL parent(x_);
  LOOP FETCH P
  BEGIN
    FETCH result(id, a, b, child) FROM VALUES(P.id, P.a, P.b, child(P.id));
    OUT UNION result;
  END;
END;
```

Note the `LIKE` and `FROM` forms are make it a lot easier to express this notion
of just adding one more column to the result. The code for emitting the `parent_child`
result doesn't need to specify the columns of the parent or the columns of the child,
only that the parent has at least the `id` column. Even that could have been removed.

This call could have been used instead:

```sql
fetch result from values(from P, child(from P like child arguments));
```

That syntax would result in using the columns of P that match the arguments of `child` -- just
`P.id` in this case.  But if there were many such columns the sugar would be easier to understand
and much less error prone.

#### Generated Code Details

Normally all result sets that have an object type in them use a generic object `cql_object_ref`
as their C data type. This isn't wrong exactly but it would mean that a cast would be required
in every use case on the native side, and it's easy to get the cast wrong.  So the result type
of column getters is adjusted to be a `child_result_set_ref` instead of just `cql_object_ref`
where `child` is the name of the child procedure.
