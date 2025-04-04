---
title: "Chapter 12: Testability Features"
weight: 12
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL includes a number of features to make it easier to create what
you might call "Test" procedures.  These primarily are concerned with
loading up the database with dummy data, and/or validating the result of
normal procedures that query the database.  There are several interesting
language features in these dimensions.

### Dummy Data

Test code can be needlessly brittle, especially when creating dummy
data; any column changes typically cause all sorts of data insertion
code to need to be repaired.  In many cases the actual data values are
completely uninteresting to the test -- any values would do.  There are
several strategies you can use to get good dummy data into your database
in a more maintainable way.

#### Simple Inserts With Dummy Data

The simplest form uses a variant of the insert statement that fills in
any missing columns with a seed value.  An example might be something
like the below:

```sql
create proc dummy_user()
begin
  insert into users () values () @dummy_seed(123)
     @dummy_nullables @dummy_defaults;
end;
```
This statement causes all values including columns that are nullable or
have a default value to get the value `123` for any numeric type and
`'column_name_123'` for any text.

If you omit the `@dummy_nullables` then any nullable fields will be null
as usual.  And likewise if you omit `@dummy_defaults` then any fields
with a default value will use that value as usual.  You might want any
combination of these for your tests (null values are handy in your tests
and default behavior is also handy.)

The `@dummy_seed` expression provided can be anything that resolves to
a non-null integer value, so it can be pretty flexible.  You might use a
`while` loop to insert a bunch of rows with the seed value being computed
from the `while` loop variable.

The form above is sort of like `insert * into table` in that it is
giving dummy values for all columns but you can also specify some of
the columns while using the seed value for others.  Importantly, you can
specify values you particularly want to control either for purposes of
creating a more tailored test or because you need them to match existing
or created rows in a table referenced by a foreign key.

As an example:

```sql
insert into users (id) values (1234) @dummy_seed(123)
   @dummy_nullables @dummy_defaults;
```
will provide dummy values for everything but the `id` column.

#### Using `WITH RECURSIVE`


Sometimes what you want to do is create a dummy result set without
necessarily populating the database at all.  If you have code that
consumes a result set of a particular shape, it's easy enough to create
a fake result set with a pattern something like this:

```sql
create proc dummy_stuff(lim int!)
begin
  WITH RECURSIVE
  dummy(x) AS (
     SELECT 1
     UNION ALL
     SELECT x+1 FROM dummy WHERE x < lim)
  SELECT
    x id,
    printf("name_%d", x) name,
    cast(x % 2 as bool) is_cool,
    x * 1.3 as rate,
    x etc1,
    x etc2
  FROM dummy;
end;
```

The first part of the above creates a series of numbers from 1 to `lim`.
The second uses those values to create dummy columns.  Any result shape
can be generated in this fashion.

You get data like this from the above:

```text
1|name_1|1|1.3|1|1
2|name_2|0|2.6|2|2
3|name_3|1|3.9|3|3
4|name_4|0|5.2|4|4
5|name_5|1|6.5|5|5
6|name_6|0|7.8|6|6
7|name_7|1|9.1|7|7
8|name_8|0|10.4|8|8
9|name_9|1|11.7|9|9
10|name_10|0|13.0|10|10
```

The result of the select statement is itself quite flexible and if
more dummy data is what you wanted, this form can be combined with
`INSERT ... FROM SELECT...` to create dummy data in real tables.   And of
course once you have a core query you could use it in a variety of ways,
combined with cursors or any other strategy to `select` out pieces and
`insert` them into various tables.

#### Using Temporary Tables

If you need an API to create very flexible dummy data with values of your
choice you can use temporary tables and a series of helper procedures.

First, create a table to hold the results. You can of course make this
table however you need to but the `like` construct in the table creation
is especially helpful; it creates columns in the table that match
the name and type of the named object.  For instance `like my_proc` is
shorthand for the column names ands of the shape that `my_proc` returns.
This is perfect for emulating the results of `my_proc`.


```sql
create proc begin_dummy()
begin
   drop table if exists my_dummy_data;

   -- the shape of my_dummy_data matches the columns
   -- returned by proc_I_want_to_emulate
   create temp table my_dummy_data(
     like proc_I_want_to_emulate;
   );
end;
```

Next, you will need a procedure that accepts and writes a single row to
your temp table.  You can of course write this all explicitly but the
testing support features provide more support to make things easier;
In this example, arguments  of the procedure will exactly match the
output of the procedure we emulating, one argument for each column the
proc returns. The `insert` statement gets its values from the arguments.

```sql
create proc add_dummy(like proc_I_want_to_emulate)
begin
   insert into my_dummy_data from arguments;
end;
```

This allows you to create the necessary helper methods automatically
even if the procedure changes over time.

Next we need a procedure to get our result set.

```sql
create proc get_dummy()
begin
  select * from my_dummy_data;
end;
```

And finally, some cleanup.

```sql
create proc cleanup_dummy()
begin
   drop table if exists my_dummy_data;
end;
```

Again the temp table could be combined with `INSERT INTO ...FROM
SELECT...` to create dummy data in real tables.

#### Other Considerations

Wrapping your `insert` statements in `try/catch` can be very useful if
there may be dummy data conflicts.  In test code searching for a new
suitable seed is pretty easy.  Alternatively

```sql
set seed := 1 + (select max(id) from foo);
```

could be very useful.  Many alternatives are also possible.

The dummy data features are not suitable for use in production code,
only tests.  But the LIKE features are generally useful for creating
contract-like behavior in procs and there are reasonable uses for them
in production code.

#### Complex Result Set Example

Here's a more complicated example that can be easily rewritten using the
sugar features.  This method is designed to return a single-row result
set that can be used to mock a method.  I've replaced the real fields with
'f1, 'f2' etc.

```sql
PROC test_my_subject(
  f1_ LONG!,
  f2_ TEXT!,
  f3_ INT!,
  f4_ LONG!,
  f5_ TEXT,
  f6_ TEXT,
  f7_ TEXT,
  f8_ BOOL!,
  f9_ TEXT,
  f10_ TEXT
)
BEGIN
  DECLARE data_cursor CURSOR LIKE my_subject;
  FETCH data_cursor()
        FROM VALUES (f1_, f2_, f3_, f4_, f5_, f6_, f7_, f8_, f9_, f10);
  OUT data_cursor;
END;
```

This can be written much more maintainably as:

```sql
PROC test_my_subject(like my_subject)
BEGIN
  CURSOR C LIKE my_subject;
  FETCH C FROM ARGUMENTS;
  OUT C;
END;
```

Naturally, real columns have much longer names and there are often many
more than 10.

### Autotest Attributes

Some of the patterns described above are so common that CQL offers a
mechanism to automatically generate those test procedures.

#### Temporary Table Pattern

The attributes dummy_table, dummy_insert, and dummy_select can be used
together to create and populate temp tables.

Example:

To create a dummy row set for `sample_proc`, add the `[[autotest]]`
attribute with dummy_table, dummy_insert, and dummy_select values.

```sql
create table foo(
  id int!,
  name text!
);

[[autotest=(dummy_table, dummy_insert, dummy_select)]]
create proc sample_proc(foo int)
begin
  select * from Foo;
end;
```

`dummy_table` generates procedures for creating and dropping a temp table with the same shape as `sample_proc`.

```sql
CREATE PROC open_sample_proc()
BEGIN
  CREATE TEMP TABLE test_sample_proc(LIKE sample_proc);
END;

CREATE PROC close_sample_proc()
BEGIN
  DROP test_sample_proc;
END;
```

The `dummy_insert` attribute generates a procedure for inserting into the temp table.

```sql
CREATE PROC insert_sample_proc(LIKE sample_proc)
BEGIN
  INSERT INTO test_sample_proc FROM ARGUMENTS;
END;
```

The `dummy_select` attribute generates procedures for selecting from the temp table.

```sql
CREATE PROC select_sample_proc()
BEGIN
  SELECT * FROM test_sample_proc;
END;
```
It's interesting to note that the generated test code does not ever need
to mention the exact columns it is emulating because it can always use
`like`, `*`, and `from arguments` in a generic way.

When compiled, the above will create C methods that can create, drop,
insert, and select from the temp table.  They will have the following
signatures:

```
CQL_WARN_UNUSED cql_code open_sample_proc(
  sqlite3 *_Nonnull _db_);

CQL_WARN_UNUSED cql_code close_sample_proc(
  sqlite3 *_Nonnull _db_);

CQL_WARN_UNUSED cql_code insert_sample_proc(
  sqlite3 *_Nonnull _db_,
  cql_int32 id_,
  cql_string_ref _Nonnull name_);

CQL_WARN_UNUSED cql_code select_sample_proc_fetch_results(
  sqlite3 *_Nonnull _db_,
  select_sample_proc_result_set_ref _Nullable *_Nonnull result_set);
```

#### Single Row ResultSet

In some cases, using four APIs to generate fake data can be verbose.
In the case that only a single row of data needs to be faked, the
dummy_result_set attribute can be more convenient.

Example:

```sql
[[autotest=(dummy_result_set]])
create proc sample_proc()
begin
  select id from Foo;
end;
```

Will generate the following procedure

```sql
CREATE PROC generate_sample_proc_row(LIKE sample_proc)
BEGIN
  CURSOR curs LIKE sample_proc;
  FETCH curs FROM ARGUMENTS;
  OUT curs;
END;
```

Which generates this C API:

```c
void generate_sample_proc_row_fetch_results(
    generate_sample_proc_row_rowset_ref _Nullable *_Nonnull result_set,
    string_ref _Nonnull foo_,
    int64_t bar_);
```

These few test helpers are useful in a variety of scenarios and can save you a lot of typing and maintenance.  They evolve automatically as the code
changes, always matching the signature of the attributed procedure.

#### Generalized Dummy Test Pattern

The most flexible test helper is the `dummy_test` form.  This is
far more advanced than the simple helpers above.  While the choices
above were designed to help you create fake result sets pretty easily,
`dummy_test` goes much further letting you set up arbitrary schema and
data so that you can run your procedure on actual data.  The `dummy_test`
code generator uses the features above to do its job and like the other
autotest options, it works by automatically generating CQL code from your
procedure definition.  However, you get a lot more code in this mode.

It's easiest to study an example so let's begin there.

To understand `dummy_test` we'll need a more complete example, so we start
with this simple two-table schema with a trigger and some indices. To
this we add a very small procedure that we might want to test.

```
create table foo(
 id int! primary key,
 name text
);

create table bar(
 id int! primary key references foo(id),
 data text
);

create index foo_index on foo(name);

create index bar_index on bar(data);

create temp trigger if not exists trigger1
  before delete on foo
begin
  delete from foo where name = 'this is so bogus';
end;

[[autotest=(
  dummy_table,
  dummy_insert,
  dummy_select,
  dummy_result_set,
  (dummy_test, (bar, (data), ('plugh'))))
]]
create proc the_subject()
begin
  select * from bar;
end;
```

As you can see, we have two tables, `foo` and `bar`; the `foo` table
has a trigger;  both `foo` and `bar` have indices.  This schema is very
simple, but of course it could be a lot more complicated, and real cases
typically are.

The procedure we want to test is creatively called `the_subject`.  It has
lots of test attributes on it.  We've already discussed `dummy_table`,
`dummy_insert`, `dummy_select`, and `dummy_result_set` above but as you
can see they can be mixed in with `dummy_test`.  Now let's talk about
`dummy_test`.  First you'll notice that annotation has additional
sub-attributes; the attribute grammar is sufficiently flexible such
that, in principle, you could represent an arbitrary LISP program,
so the instructions can be very detailed.  In this case, the attribute
provides table and column names, as well as sample data.  We'll discuss
that when we get to the population code.

First let's dispense with the attributes we already discussed -- since
we had all the attributes, the output will include those helpers, too.
Here they are again:

```sql
-- note that the code does not actually call the test subject
-- this declaration is used so that CQL will know the shape of the result
DECLARE PROC the_subject () (id INT!, data TEXT);

CREATE PROC open_the_subject()
BEGIN
  CREATE TEMP TABLE test_the_subject(LIKE the_subject);
END;

CREATE PROC close_the_subject()
BEGIN
  DROP TABLE test_the_subject;
END;

CREATE PROC insert_the_subject(LIKE the_subject)
BEGIN
  INSERT INTO test_the_subject FROM ARGUMENTS;
END;

CREATE PROC select_the_subject()
BEGIN
  SELECT * FROM test_the_subject;
END;

CREATE PROC generate_the_subject_row(LIKE the_subject)
BEGIN
  CURSOR curs LIKE the_subject;
  FETCH curs FROM ARGUMENTS;
  OUT curs;
END;
```

That covers what we had before, so, what's new?  Actually, quite a bit.  We'll begin with the easiest:

```sql
CREATE PROC test_the_subject_create_tables()
BEGIN
  CREATE TABLE IF NOT EXISTS foo(
    id INT! PRIMARY KEY,
    name TEXT
  );
  CREATE TABLE IF NOT EXISTS bar(
    id INT! PRIMARY KEY REFERENCES foo (id),
    data TEXT
  );
END;
```

Probably the most important of all the helpers,
`test_the_subject_create_tables` will create all the tables you need to
run the procedure.  Note that in this case, even though the subject code
only references `bar`, CQL determined that `foo` is also needed because
of the foreign key.

The symmetric drop procedure is also generated:

```sql
CREATE PROC test_the_subject_drop_tables()
BEGIN
  DROP TABLE IF EXISTS bar;
  DROP TABLE IF EXISTS foo;
END;
```

Additionally, in this case there were triggers and indices.  This caused
the creation of helpers for those aspects.

```sql
CREATE PROC test_the_subject_create_indexes()
BEGIN
  CREATE INDEX bar_index ON bar (data);
  CREATE INDEX foo_index ON foo (name);
END;

CREATE PROC test_the_subject_create_triggers()
BEGIN
  CREATE TEMP TRIGGER IF NOT EXISTS trigger1
    BEFORE DELETE ON foo
  BEGIN
  DELETE FROM foo WHERE name = 'this is so bogus';
  END;
END;

CREATE PROC test_the_subject_drop_indexes()
BEGIN
  DROP INDEX IF EXISTS bar_index;
  DROP INDEX IF EXISTS foo_index;
END;

CREATE PROC test_the_subject_drop_triggers()
BEGIN
  DROP TRIGGER IF EXISTS trigger1;
END;
```

If there are no triggers or indices, the corresponding create/drop
methods will not be generated.

With these helpers available, when writing test code you can then choose
if you want to create just the tables, or the tables and indices, or
tables and indices and triggers by invoking the appropriate combination
of helper methods.  Since all the implicated triggers and indices are
automatically included, even if they change over time, maintenance is
greatly simplified.

Note that in this case the code simply reads from one of the tables, but
in general the procedure under test might make modifications as well.
Test code frequently has to read back the contents of the tables to
verify that they were modified correctly.  So these additional helper
methods are also included:

```sql
CREATE PROC test_the_subject_read_foo()
BEGIN
 SELECT * FROM foo;
END;

CREATE PROC test_the_subject_read_bar()
BEGIN
 SELECT * FROM bar;
END;
```

These procedures will allow you to easily create result sets with data
from the relevant tables which can then be verified for correctness.
Of course if more tables were implicated, those would have been included
as well.

As you can see, the naming always follows the convention
`test_[YOUR_PROCEDURE]_[helper_type]`

Finally, the most complicated helper is the one that used that large
annotation.  Recall that we provided the fragment `(dummy_test, (bar,
(data), ('plugh'))))` to the compiler.  This fragment helped to produce
this last helper function:

```sql
CREATE PROC test_the_subject_populate_tables()
BEGIN
  INSERT OR IGNORE INTO foo(id) VALUES(1) @dummy_seed(123);

  INSERT OR IGNORE INTO foo(id) VALUES(2) @dummy_seed(124)
      @dummy_nullables @dummy_defaults;

INSERT OR IGNORE INTO bar(data, id) VALUES('plugh', 1) @dummy_seed(125);

  INSERT OR IGNORE INTO bar(id) VALUES(2) @dummy_seed(126)
     @dummy_nullables @dummy_defaults;
END;
```

In general the `populate_tables` helper will fill all implicated tables
with at least two rows of data.  It uses the dummy data features discussed
earlier to generate the items using a seed.  Recall that if `@dummy_seed`
is present in an `insert` statement then any missing columns are generated
using that value, either as a string, or as an integer (or true/false
for a boolean).   Note that the second of the two rows that is generated
also specifies `@dummy_nullables` and `@dummy_defaults`.  This means
that even nullable columns, and columns with a default value will get
the non-null seed instead.  So you get a mix of null/default/explicit
values loaded into your tables.

Of course blindly inserting data doesn't quite work.  As you can see,
the insert code used the foreign key references in the schema to figure
out the necessary insert order and the primary key values for `foo` were
automatically specified so that they could then be used again in `bar`.

Lastly, the autotest attribute included explicit test values for the table
`bar`, and  in particular the `data` column has the value `'plugh'`.
So the first row of data for table `bar` did not use dummy data for the
`data` column but rather used `'plugh'`.

In general, the `dummy_test` annotation can include any number of tables,
and for each table you can specify any of the columns and you can have
any number of tuples of values for those columns.

>NOTE: if you include primary key and/or foreign key columns among
the explicit values, it's up to you to ensure that they are valid
combinations.  SQLite will complain as usual if they are not, but the
CQL compiler will simply emit the data you asked for.

Generalizing the example a little bit, we could use the following:

```
(dummy_test, (foo, (name), ('fred'), ('barney'), ('wilma'), ('betty')),
                        (bar, (id, data), (1, 'dino'), (2, 'hopparoo'))))
```

to generate this population:

```
CREATE PROC test_the_subject_populate_tables()
BEGIN
  INSERT OR IGNORE INTO foo(name, id) VALUES('fred', 1) @dummy_seed(123);

  INSERT OR IGNORE INTO foo(name, id) VALUES('barney', 2) @dummy_seed(124)
    @dummy_nullables @dummy_defaults;

  INSERT OR IGNORE INTO foo(name, id) VALUES('wilma', 3) @dummy_seed(125);

  INSERT OR IGNORE INTO foo(name, id) VALUES('betty', 4) @dummy_seed(126)
    @dummy_nullables @dummy_defaults;

  INSERT OR IGNORE INTO bar(id, data) VALUES(1, 'dino') @dummy_seed(127);

  INSERT OR IGNORE INTO bar(id, data) VALUES(2, 'hopparoo') @dummy_seed(128)
    @dummy_nullables @dummy_defaults;
END;
```

And of course if the annotation is not flexible enough, you can write
your own data population.

The CQL above results in the usual C signatures.  For instance:

```c
CQL_WARN_UNUSED cql_code test_the_subject_populate_tables(sqlite3 *_Nonnull _db_);
```

So, it's fairly easy to call from C/C++ test code or from CQL test code.

#### Cross Procedure Limitations

Generally it's not possible to compute table usages that come from called
procedures. This is because to do so you need to see the body of the
called procedure and typically that body is in a different translation --
and is therefore not available.  A common workaround for this particular
problem is to create a dummy procedure that explicitly uses all of the
desired tables.  This is significantly easier than creating all the
schema manually and still gets you triggers and indices automatically.
Something like this:

```sql
[[autotest=(dummy_test]])
create proc use_my_stuff()
begin
  let x := select 1 from t1, t2, t3, t4, t5, t6, etc..;
end;
```

The above can be be done as a macro if desired.  But in any case
`use_my_stuff` simply and directly lists the desired tables.  Using this
approach you can have one set of test helpers for an entire unit rather
than one per procedure.  This is often desirable and the maintenance is
not too bad.  You just use the `use_my_stuff` test helpers everywhere.
