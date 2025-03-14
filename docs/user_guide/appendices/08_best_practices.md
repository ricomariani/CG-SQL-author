---
title: "Appendix 8: Best Practices"
weight: 8
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

This is a brief discussion of every statement type and some general best
practices for that statement. The statements are in mostly alphabetical order
except related statements were moved up in the order to make logical groups.

Refer also to Appendix 7: Anti-patterns.

### Data Definition Language (DDL)

* `ALTER TABLE ADD COLUMN`
* `CREATE INDEX`
* `CREATE PROC`
* `CREATE TABLE`
* `CREATE TRIGGER`
* `CREATE VIEW`
* `CREATE VIRTUAL TABLE`
* `DROP INDEX`
* `DROP TABLE`
* `DROP TRIGGER`
* `DROP VIEW`

These statements almost never appear in normal procedures and generally should
be avoided.  The normal way of handling schema in CQL is to have one or more
files declare all the schema you need and then let CQL create a schema upgrader
for you.  This means you'll never manually drop tables or indices etc.  The
`create` declarations with their annotations will totally drive the schema.

Any ad hoc DDL is usually a very bad sign.  Test code is an obvious exception to
this as it often does setup and teardown of schema to set up things for the
test.

### Ad Hoc Migrations

* `@SCHEMA_AD_HOC_MIGRATION`

This is a special upgrade step that should be taken at the version indicated in
the statement.  These can be quite complex and even super important but should
not be used lightly.  Any migration procedure has to be highly tolerant of a
variety of incoming schema versions and previous partial successes. In any case
this directive should not appear in normal code.  It should be part of the
schema DDL declarations.

### Transactions

* `BEGIN TRANSACTION`
* `COMMIT TRANSACTION`
* `ROLLBACK TRANSACTION`

Transactions do not nest and most procedures do not know the context in which
they will be called, so the vast majority of procedures will not and should not
actually start transactions.  You can only do this if you know, somehow, for
sure, that the procedure in question is somehow a "top level" procedure.  So
generally, don't use these statements.

### Savepoints

* `SAVEPOINT`
* `ROLLBACK TO SAVEPOINT`
* `RELEASE SAVEPOINT`
* `PROC SAVEPOINT`
* `COMMIT RETURN`
* `ROLLBACK RETURN`

back if needed.  You can use ad hoc savepoints, just give your save point and
Savepoints are the preferred tool for having interim state that can be rolled
name then use `RELEASE SAVEPOINT` to commit it, or else `ROLLBACK TO SAVEPOINT`
followed by a `RELEASE` to abort it.  Note that you always `RELEASE` savepoints
in both the rollback and the commit case.

Managing savepoints can be tricky, especially given the various error cases.
They combine nicely with `TRY CATCH` to do this job.  However, even that is a
lot of boilerplate.  The best way to use savepoints is with `PROC SAVEPOINT
BEGIN` .. `END`;

When you use `PROC SAVEPOINT`, a savepoint is created for you with the name of
your procedure.  When the block exits the savepoint is released (committed).
However you also get an automatically generated try/catch block which will
rollback the savepoint if anything inside the block were to invoke `THROW`.
Also, you may not use a regular `RETURN` inside this block, you must use either
`ROLLBACK RETURN` or `COMMIT RETURN`.  Both of these directly indicate the fate
of the automatically generated statement when they run.  This gives you useful
options to early-out (with no error) while keeping or abandoning any work in
progress.  Of course you can use `THROW` to return an error and abandon the work
in progress.

### Compilation options

* `@ENFORCE_NORMAL`
* `@ENFORCE_POP`
* `@ENFORCE_PUSH`
* `@ENFORCE_RESET`
* `@ENFORCE_STRICT`

CQL allows you to specify a number of useful options such as "do not allow
Window Functions" or "all foreign keys must choose some update or delete
strategy". These additional enforcements are designed to prevent errors.
Because of this they should be established once, somewhere central and they
should be rarely if ever overridden.  For instance `@ENFORCE_NORMAL WINDOW
FUNCTION` would allow you to use window functions again, but this is probably a
bad idea. If strict mode is on, disallowing them, that probably means your
project is expected to target versions of SQLite that do not have window
functions.  Overriding that setting is likely to lead to runtime errors.

In general you don't want to see these options in most code.

### Previous Schema

* `@PREVIOUS_SCHEMA`

CQL can ensure that the current schema is compatible with the previous schema,
meaning that an upgrade script could reasonably be generated to go from the
previous to the current.  This directive demarks the start of the previous
schema section when that validation happens.  This directive is useless except
for creating that schema validation so it should never appear in normal
procedures.

### Schema Regions

* `@BEGIN_SCHEMA_REGION`
* `@DECLARE_DEPLOYABLE_REGION`
* `@DECLARE_SCHEMA_REGION`
* `@END_SCHEMA_REGION`

CQL allows you to declare arbitrary schema regions and limit what parts of the
schema any given region may consume.  This helps you to prevent schema from
getting entangled.  There is never a reason to use this directives inside normal
procedures;  They should appear only in your schema declaration files.

### Schema Version

* `@SCHEMA_UPGRADE_SCRIPT`
* `@SCHEMA_UPGRADE_VERSION`

The `@SCHEMA_UPGRADE_SCRIPT` directive is only used by CQL itself to declare
that the incoming file is an autogenerated schema upgrade script. These scripts
have slightly different rules for schema declaration that are not useful outside
of such scripts.  So you should never use this.

`@SCHEMA_UPGRADE_VERSION` on the other hand is used if you are creating a manual
migration script.  You need this script to run in the context of the schema
version that it affects.  Use this directive at the start of the file to do so.
Generally manual migration scripts are to be avoided so hopefully this directive
is rarely if ever used.


### C Text Echo

* `@ECHO`

This directive emits plain text directly into the compiler's output stream.  It
can be invaluable for adding new runtime features and for ensuring that (e.g.)
additional `#include` or `#define` directives are present in the output but you
can really break things by over-using this feature.  Most parts of the CQL
output are subject to change so any use of this should be super clean.  The
intended use was, as mentioned, to allow an extra `#include` in your code so
that CQL could call into some library.  Most uses of this combine with `DECLARE
FUNCTION` or `DECLARE PROCEDURE` to declare an external entity.

### Enumerations

* `ENUM`
* `@EMIT_ENUMS`

Avoid embedded constants whenever possible.  Instead declare a suitable
enumeration.   Use `@EMIT_ENUMS Some_Enum` to get the enumeration constants into
the generated .h file for C. But be sure to do this only from one compiland.
You do not want the enumerations in every .h file. Choose a single .sql file
(not included by lots of other things) to place the `@EMIT_ENUMS` directive. You
can make a file specifically for this purpose if nothing else is serviceable.

### Cursor Lifetime

* `CLOSE`

The `CLOSE` statement is normally not necessary because all cursors are closed
at the end of the procedure they are declared in (unless they are boxed, see
below).  You only need `CLOSE` if you want to close a global cursor (which has
no scope) or if you want to close a local cursor "sooner" because waiting to the
end of the procedure might be a very long time.  Using close more than once is
safe, the second and later close operations do nothing.

### Procedure Calls and Exceptions

* `CALL`
* `THROW`
* `TRY CATCH`

Remember that if you call a procedure and it uses `THROW` or else uses some SQL that failed, this return code will cause your
code to `THROW` when the procedure returns.  Normally that's exactly what you want, the error will ripple out and some top-level
`CATCH` will cause a `ROLLBACK` and the top level callers sees the error.  If you have your own rollback needs be sure to install
your own `TRY`/`CATCH` block or else use `PROC SAVEPOINT` as above to do it for you.

Inside of a `CATCH` block you can use the special variable `@RC` to see the most recent return code from SQLite.


### Control Flow with "Big Moves"

* `CONTINUE`
* `LEAVE`
* `RETURN`

These work as usual but beware, you can easily use any of these to accidentally leave a block with a savepoint or transaction
and you might skip over the `ROLLBACK` or `COMMIT` portions of the logic.  Avoid this problem by using `PROC SAVEPOINT`.


### Getting access to external code

* `DECLARE FUNCTION`
* `DECLARE SELECT FUNCTION`
* `DECLARE PROCEDURE`

The best practice is to put any declarations into a shared header file which you
can `#include` in all the places it is needed. This is especially important
should you have to forward declare a procedure.  CQL normally provides exports
for all procedures so you basically get an automatically generated and
certain-to-be-correct `#include` file.  But, if the procedures are being
compiled together then an export file won't have been generated yet at the time
you need it;  To work around this you use the ``DECLARE PROCEDURE`` form.
However, procedure declarations are tricky;  they include not just the type of
the arguments but the types of any/all of the columns in any result set the
procedure might have.  This must not be wrong or callers will get unpredictable
failures.

The easiest way to ensure it is correct is to use the same trick as you would in
C -- make sure that you `#include` the declaration the in the translation unit
with the definition.  If they don't match there will be an error.

A very useful trick: the error will include the exact text of the correct
declaration.  So if you don't know it, or are too lazy to figure it out; simply
put `ANY` declaration in the shared header file and then paste in the correct
declaration from the error.  should the definition ever change you will get a
compilation error which you can again harvest to get the correct declaration.

In this way you can be sure the declarations are correct.

Functions have no CQL equivalent, but they generally don't change very often.
Use `DECLARE FUNCTION` to allow access to some C code that returns a result of
some kind.   Be sure to add the `CREATE` option if the function returns a
reference that the caller owns.

Use `DECLARE SELECT FUNCTION` to tell CQL about any User Defined Functions you
have added to SQLite so that it knows how to call them. Note that CQL does not
register those UDFs, it couldn't make that call lacking the essential C
information required to do so.  If you find that you are getting errors when
calling a UDF the most likely reason for the failure is that the UDF was
declared but never registered with SQLite at runtime.  This happens in test code
a lot -- product code tends to have some central place to register the UDFs and
it normally runs at startup, e.g. right after the schema is upgraded.

### Regular Data Manipulation Language (DML)

* `DELETE`
* `INSERT`
* `SELECT`
* `UPDATE`
* `UPSERT`

These statements are the most essential and they'll appear in almost every
procedure. There are a few general best practices we can go over.

 * Try to do as much as you can in one batch rather than iterating;  e.g.
   * don't write a loop with a `DELETE` statement that deletes one row if you
     can avoid it, write a delete statement that deletes all you need to delete
   * don't write a loop with of `SELECT` statement that fetches one row, try to
     fetch all the rows you need with one select

 * Make sure `UPSERT` is supported on the SQLite system you are using, older
   versions do not support it

 * Don't put unnecessary casts in your `SELECT` statements, they just add fat
 * Don't use `CASE`/`WHEN` to compute a boolean, the boolean operations are more
   economical (e.g. use `IS`)
 * Don't use `COUNT` if all you need to know is whether a row exists or not, use
   `EXISTS`
 * Don't use `GROUP BY`, `ORDER BY`, or `DISTINCT` on large rowsets, the sort is
   expensive and it will make your `SELECT` statements write to disk rather than
   just read

 * Always use the `INSERT INTO FOO USING` form of the `INSERT` statement, it's
   much easier to read than the standard form and compiles to the same thing


### Variable and Cursor declarations

* `DECLARE OUT CALL`
* `DECLARE`
* `LET`
* `SET`

These are likely to appear all over as well.  If you can avoid a variable
declaration by using `LET` then do so;  The code will be more concise and you'll
get the exact variable type you need.  This is the same as `var x = foo();` in
other languages.  Once the variable is declared use `SET`.

You can save yourself a lot of declarations of `OUT` variables with `DECLARE OUT
CALL`.  That declaration form automatically declares the `OUT` variables used in
the call you are about to make with the correct type.  If the number of
arguments changes you just have to add the args you don't have to also add new
declarations.

The `LIKE` construct can be used to let you declare things whose type is the
same as another thing.  Patterns like `CURSOR ARGS LIKE FOO ARGUMENTS`
save you a lot of typing and also enhance correctness.  There's a whole chapter
dedicated to "shapes" defined by `LIKE`.

### Query Plans

* `EXPLAIN`

Explain can be used in front of other queries to generate a plan.  The way
SQLite handles this is that you fetch the rows of the plan as usual.  So
basically `EXPLAIN` is kind of like `SELECT QUERY PLAN OF`.  This hardly ever
comes up in normal coding.  CQL has an output option where it will generate code
that gives you the query plan for a procedures queries rather than the normal
body of the procedure.

### Fetching Data from a Cursor or from Loose Data

* `FETCH`
* `UPDATE CURSOR`

The `FETCH` statement has many variations, all are useful at some time or
another. There are a few helpful guidelines.

* If fetching from loose values into a cursor use the `FETCH USING` form (as you
  would with `INSERT INTO USING`) because it is less error prone
* `FETCH INTO` is generally a bad idea, you'll have to declare a lot of
  variables, instead just rely on automatic storage in the cursor e.g. `fetch
  my_cursor` rather than `fetch my_cursor into a, b, c`
* If you have data already in a cursor you can mutate some of the columns using
  `UPDATE CURSOR`, this can let you adjust values or apply defaults

### Control Flow

* `IF`
* `LOOP`
* `SWITCH`
* `WHILE`

These are your bread and butter and they will appear all over.

>TIP: Use the `ALL VALUES` variant of switch whenever possible to ensure that
>you haven't missed any cases.

### Manual Control of Results

* `OUT`
* `OUT UNION`

* If you know you are producing exactly one row `OUT` is more economical than `SELECT`
* If you need complete flexibility on what rows to produce (e.g. skip some, add
  extras, mutate some) then `OUT UNION` will give you that, use it only when
  needed, it's more expensive than just `SELECT`


### CTEs and Shared Fragments

To understand what kinds of things you can reasonably do with fragments, really you
just have to understand the things that you can do with common table expressions or
CTEs.  For those who don't know, CTEs are the things you declare
in the WITH clause of a SELECT statement.  They're kind of like local views.  Well,
actually, they are exactly like local views.

Query fragments help you to define useful CTEs so basically what you can do
economically in a CTE directly determines what you can do economically in a fragment.

To demonstrate some things that happen with CTEs we're going to use these three
boring tables.

```sql
create table A
(
   id int primary key,
   this text!
);

create table B
(
   id int primary key,
   that text!
);

create table C
(
   id int primary key,
   other text!
);
```

Let's start with a very simple example, the first few examples are like control
cases.

```sql
explain query plan
select * from A
inner join B on B.id = A.id;

QUERY PLAN
|--SCAN TABLE A
\--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
```

OK as we can see `A` is not constrained so it has to be scanned but `B` isn't
scanned, we use its primary key for the join.  This is the most common kind of
join: a search based on a key of the table you are joining to.

Let's make it a bit more realistic.

```sql
explain query plan
select * from A
inner join B on B.id = A.id
where A.id = 5;

QUERY PLAN
|--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
```

Now `A` is constrained by the `WHERE` clause so we can use its index and then
use the `B` index. So we get a nice economical join from `A` to `B` and no scans
at all.

Now suppose we try this with some CTE replacements for `A` and `B`.  Does this
make it worse?

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  BB(id, that) as (select * from B)
select * from AA
left join BB on BB.id = AA.id
where AA.id = 5;

QUERY PLAN
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
```

The answer is a resounding no.  The CTE `AA` was not materialized it was
expanded in place, as was the CTE `BB`.  We get *exactly* the same query plan.
Now this means that the inner expressions like `select * from A` could have been
fragments such as:

```sql
[[shared_fragment]]
create proc A_()
begin
  select * from A;
end;

[[shared_fragment]]
create proc B_()
begin
  select * from B;
end;

explain query plan
with
  (call A_()),    -- short for A_(*) AS (call A_())
  (call B_())     -- short for B_(*) AS (call B_())
select * from A_
left join B_ on B_.id = A_.id
where A_.id = 5;
```

>NOTE: I'll use the convention that `A_` is the fragment proc that could have
>generated the CTE `AA`, likewise with `B_` and so forth.

The above will expand into exactly what we had before and hence will have the
exactly same good query plan.  Of course this is totally goofy, why make a
fragment like that -- it's just more typing.  Well now lets generalize the
fragments just a bit.

```sql
[[shared_fragment]]
create proc A_(experiment bool not null)
begin
  -- data source might come from somewhere else due to an experiment
  if not experiment then
    select * from A;
  else
    select id, this from somewhere_else;
  end if;
end;

[[shared_fragment]]
create proc B_()
begin
  -- we don't actually refer to "B" if the filter is null
  if b_filter is not null then
    -- applies b_filter if specified
    select * from B where B.other like b_filter;
  else
    -- generates the correct shape but zero rows of it
    select null as id, null as that where false;
  end if;
end;

create proc getAB(
    id_ int!,
    experiment bool!,
    b_filter text)
begin
  with
    (call A_(experiment)),
    (call B_(b_filter))
  select * from A_
  left join B_ on B_.id = A_.id
  where A_.id = id_;
end;
```

The above now has 4 combos economically encoded and all of them have a good
plan. Importantly though, if `b_filter` is not specified then we don't actually
join to `B`. The `B_` CTE will have no reference to `B`, it just has zero rows.

Now lets look at some things you don't want to do.

Consider this form:

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  BB(id, that) as (select A.id, B.that from A left join B on B.id = A.id)
select * from AA
left join BB on BB.id = AA.id
where AA.id = 5;

QUERY PLAN
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
```

Note that here we get 3 joins.  Now a pretty cool thing happened here -- even
though the expression for `BB` does not include a `WHERE` clause SQLite has
figured out the `AA.id` being 5 forces `A.id` to be 5 which in turn gives a
constraint on `BB`. Nice job SQLite.  If it hadn't been able to figure that out
then the expansion of `BB` would have resulted in a table scan.

Still, 3 joins is bad when we only need 2 joins to do the job.  What happened?
Well, when we did the original fragments with extensions and stuff we saw this
same pattern in fragment code. Basically the fragment for `BB` isn't just doing
the `B` things it's restarting from `A` and doing its own join to get `B`. This
results in a wasted join.  And it might result in a lot of work on the `A` table
as well if the filtering was more complex and couldn't be perfectly inferred.

You might think, "oh, no problem, I can save this, I'll just refer to `AA`
instead of `A` in the second query."

This does not help (but it's going in the right direction):

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  BB(id, that) as (select AA.id, B.that from AA left join B on B.id = AA.id)
select * from AA
left join BB on BB.id = AA.id
where AA.id = 5;

QUERY PLAN
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
```

In terms of fragments the anti-pattern is this.

```sql
[[shared_fragment]]
create proc B_()
begin
  select B.* from A left join B on B.id = A.id;
end;
```

The above starts the query for `B` again from the root.  You can save this, the
trick is to not try to generate just the `B` columns and then join them later.
You can get a nice data flow going with chain of CTEs.

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  AB(id, this, that) as (select AA.*, B.that from AA left join B on B.id = AA.id)
select * from AB
where AB.id = 5;

QUERY PLAN
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
```

And we're right back to the perfect plan.  The good form creates a CTE chain
where we only need the result of the final CTE.  A straight line of CTEs each
depending on the previous one results in a excellent data flow.

In terms of fragments this is now:

```sql
[[shared_fragment]]
create proc A_()
begin
  select * from A;
end;

[[shared_fragment]]
create proc AB_()
begin
  with
  (call A_)
  select A_.*, B.that from A_ left join B on B.id = A_.id
end;

with (call AB_())
select * from AB_ where AB_.id = 5;
```

For brevity we haven't included the possibility of using conditional fragments (i.e. `IF` statements)
the same good query plan could be generated in that way.

We can generalize `AB_` so that it doesn't know where the base data is coming
from and can be used in more cases.


```sql
[[shared_fragment]]
create proc A_()
begin
  select * from A;
end;

[[shared_fragment]]
create proc AB_()
begin
  with
  source(*) like A -- you must provide some source that is the same shape as A
  select source.*, B.that from source left join B on B.id = source.id
end;

with
(call A_())
(call AB_() using A_ as source)
select * from AB_ where AB_.id = 5;
```

Again this results in a nice straight chain of CTEs and even though the where
clause is last the `A` table is constrained properly.

It's important not to fork the chain in the query plan, if that happens then
whatever came before the fork must be materialized for use in both branches.
That can be quite bad because then the filtering might come after the
materialization.  This is an example that is quite bad.

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  BB(id, that) as (select AA.id, B.that from AA left join B on B.id = AA.id),
  CC(id, other) as (select AA.id, C.other from AA left join C on C.id = AA.id)
select * from AA
left join BB on BB.id = AA.id
left join CC on CC.id = AA.id
where AA.id = 5;

QUERY PLAN
|--MATERIALIZE 2
|  |--SCAN TABLE A
|  \--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
|--MATERIALIZE 3
|  |--SCAN TABLE A
|  \--SEARCH TABLE C USING INTEGER PRIMARY KEY (rowid=?)
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
|--SCAN SUBQUERY 2
\--SEARCH SUBQUERY 3 USING AUTOMATIC COVERING INDEX (id=?)
```

Things have gone poorly here. As you can see `A` is now scanned twice. and there
are many more joins.  We could make this a lot better by moving the `A`
condition all the way up into the first CTE.  With fragments that would just
mean creating something like:

```sql
[[shared_fragment]]
create proc A_(id_)
begin
  select * from A where A.id = id_;
end;
```

At least then if we have to materialize we'll get only one row.  This could be a
good thing to do universally, but it's especially important if you know that
forking in the query shape is mandatory for some reason.

A better pattern might be this:

```sql
explain query plan
with
  AA(id, this) as (select * from A),
  AB(id, this, that) as (select AA.*, B.that from AA left join B on B.id = AA.id),
  ABC(id, this, that, other) as (select AB.*, C.other from AB left join C on C.id = AB.id)
select * from ABC
where ABC.id = 5;

QUERY PLAN
|--SEARCH TABLE A USING INTEGER PRIMARY KEY (rowid=?)
|--SEARCH TABLE B USING INTEGER PRIMARY KEY (rowid=?)
\--SEARCH TABLE C USING INTEGER PRIMARY KEY (rowid=?)
```

Here we've just extended the chain.  With shared fragments you could easily
build an `AB_` proc as before and then build an `ABC_` proc either by calling
`AB_` directly or by having a table parameter that is `LIKE AB_`.

Both cases will give you a great plan.

So the most important things are:

* Avoid forking the chain of CTEs/fragments, a straight chain works great.
* Avoid re-joining to tables, even unconstrained CTEs result in great plans if
  they don't have to be materialized.
* If you do need to fork in your CTE chain, because of your desired shape, be
  sure to move as many filters as you can further upstream so that by the time
  you materialize only a very small number of rows need to be materialiized.

These few rules will go far in helping you to create shapes.

One last thing, without shared fragments, if you wanted to create a large join
the normal way, maybe 10 tables or so, then you have to type that join into your
file and it would be very much in your face.  Shared fragments might hide that
join from you in a nice easy-to-use fragment.  Which you might then decide you
want to use the fragment 3 times... And now with a tiny amount of code you have
30 joins.

The thing is shared fragments make it easy to generate a lot of SQL.  It's not
bad that shared fragments make things easy, but with great power comes great
responsibility, so give a care as to what it is you are assembling.
Understanding your fragments, especially any big ones, will help you to create
great code.
