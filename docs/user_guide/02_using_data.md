---
title: "Chapter 2: Using Data"
weight: 2
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

The point of using CQL is to facilitate access to a SQLite database, so we'll
switch gears to a slightly more complicated setup.  We'll still keep things
fairly simple, but let's start to use some database features.

> NOTE: It is not the intent of this tutorial to also be a primer for the SQLite
> programming language, which is ably documented on [sqlite.org](https://sqlite.org/). Please
> refer to that site for details on the meaning of the SQL statements used here
> if you are new to SQL.

### A Sample Program

Suppose we have the following program:

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

create table my_data(t text!);

create proc hello()
begin
  insert into my_data(t) values("Hello, world\n");
  var t text!;
  set t := (select * from my_data);
  call printf('%s', t);
end;
```

The above is an interesting little baby program, and it appears as though it
would once again print that most famous of salutations, "Hello, world".

Well, it doesn't.  At least, not yet.  Let's walk through the various things
that are going to go wrong as this will teach us everything we need to know
about activating CQL from some environment of your choice.

### Providing a Suitable Database

CQL is just a compiler; it doesn't know how the code it creates will be
provisioned any more than, say, clang does. It creates functions with predictable
signatures so that they can be called from C just as easily as the SQLite API
itself, and using the same currency.  Our new version of `hello` now requires a
database handle because it performs database operations. Also, there are now
opportunities for the database operations to fail, and so `hello` now provides a
return code.

A new minimal `main` program might look something like this:

```c
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
  rc = hello(db);
  if (rc != SQLITE_OK) {
    exit(2);
  }

  sqlite3_close(db);
  return 0;
}
```

If we re-run CQL and look in the `hello.h` output file we'll see that the
declaration of the `hello` function is now:

```c
...
extern CQL_WARN_UNUSED cql_code hello(sqlite3 *_Nonnull _db_);
...
```

This indicates that the database is used and a SQLite return code is provided.
We're nearly there. If you attempt to build the program as before, there will be
several link-time errors due to missing functions.  Typically, these are resolved
by providing the SQLite library to the command line and also adding the CQL
runtime. The new command line looks something like this:

```bash
$ cc -o hello main.c hello.c cqlrt.c -lsqlite3
$ ./hello
Hello, world
```

The CQL runtime can be placed anywhere you want it to be, and of course the usual C
separate compilation methods can be applied. More on that later.

But actually, that program doesn't quite work yet.  If you run it, you'll get an
error result code, not the message "Hello, world".

Let's talk about the final missing bit.

### Declaring Schema

In CQL, a loose piece of Data Definition Language (henceforth DDL) does not
actually create or drop anything. In most CQL programs, the normal situation is
that "something" has already created the database and put some data in it.  You
need to tell the CQL compiler about the schema so that it knows what the tables
are and what to expect to find in those tables.  This is because typically
you're reconnecting to some sort of existing database. So, in CQL, loose DDL
simply *declares* schema, it does not create it.  To create schema you have to
put the DDL into a procedure you can run.  If you do that, then the DDL still
serves a declaration, but also the schema will be created when the procedure is
executed.

We need to change our program a tiny bit.

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

create proc hello()
begin
  create table my_data(t text!);
  insert into my_data(t) values("Hello, world\n");

  var t text!;
  set t := (select * from my_data);
  call printf('%s', t);
  drop table my_data;
end;
```

If we rebuild the program, it will now behave as expected.

### Explaining The New Hello World

Let's go over every important line of the new program, starting from main:

```c
int rc = sqlite3_open(":memory:", &db);
```

This statement gives us an empty, private, in-memory only database to work with.
This is the simplest case and it's still very useful.  The `sqlite_open` and
`sqlite_open_v2` functions can be used to create a variety of databases per the
SQLite documentation.

We'll need such a database to use our procedure, and we use it in the call here:

```c
rc = hello(db);
```

This provides a valid database handle to our procedure.  Note that the procedure
doesn't know what database it is supposed to operate on; it expects to be handed
a suitable database on a silver platter.  In fact, any given procedure could be used
with various databases at various times.  Just like SQLite, CQL does not enforce
any particular database setup; it just uses the provided database.

When `hello` runs, we begin with:

```sql
create table my_data(t text!);
```

This will create the `my_data` table with a single column `t`, of type `text not
null`.  That will work because we know we're going to call this with a
fresh/empty database.  More typically you might do `create table if not exists...`
or otherwise have a general attach/create phase or something to that
effect.  We'll dispense with that here.

Next, we'll run the insert statement:

```sql
insert into my_data(t) values("Hello, world\n");
```

This will add a single row to the table.  Note that we have again used double
quotes, meaning that this is a C string literal.  This is highly convenient
given the escape sequences.  Normally SQLite text has the newlines directly
embedded in it; that practice isn't very compiler friendly, hence the
alternative.

Next, we declare a local variable to hold our data:

```sql
var t text!;
```

Then, we can read back our data:

```sql
set t := (select * from my_data);
```

This form of database reading has very limited usability but it does work for
this case and it is illustrative. The presence of `(select ...)` indicates to
the CQL compiler that the parenthesized expression should be given to SQLite for
evaluation according to the SQLite rules. The expression is statically checked
at compile time to ensure that it has exactly one result column. In this case
the `*` is just column `t`, and actually it would have been clearer to use `t`
directly here but then there wouldn't be a reason to talk about `*` and multiple
columns. At run time, the `select` query must return exactly one row or an error
code will be returned. It's not uncommon to see `(select ... limit 1)` to force
the issue. But that still leaves the possibility of zero rows, which would be an
error. We'll talk about more flexible ways to read from the database later.

> You can declare a variable and assign it in one step with the `LET` keyword, e.g.
> ```sql
> let t := (select * from my_data);
> ```
>
> The code would normally be written in this way but for discussion purposes, these examples continue to avoid `LET`.

At this point it seems wise to bring up the unusual expression evaluation
properties of CQL. CQL is by necessity a two-headed beast. On the one side there
is a rich expression evaluation language for working with local variables. Those
expressions are compiled into C (or Lua) logic that emulates the behavior of
SQLite on the data. It provides complex expression constructs such as `IN` and
`CASE` but it is ultimately evaluated by C execution. Alternately, anything that
is inside of a piece of SQL is necessarily evaluated by SQLite itself. To make
this clearer let's change the example a little bit before we move on.

```sql
set t := (select "__"||t||' '||1.234 from my_data);
```

This is a somewhat silly example but it illustrates some important things:

* even though SQLite doesn't use double quotes for string literals, that's no
  problem because CQL will convert the string into a single quoted version with
  the correct escape values as a matter of course during compilation
* the `||` concatenation operator is evaluated by SQLite
* you can mix and match both kinds of string literals, they will all be the
  single quote variety by the time SQLite sees them
* the `||` operator has lots of complex formatting conversions (such as
  converting real values to strings) * in fact the conversions are so subtle as
  to be impossible to emulate in loose C code with any economy, so, like a few
  other operators, `||` is only supported in the SQLite context

Returning now to our code as written, we see something very familiar:

```sql
call printf('%s', t);
```

Note that we've used the single quote syntax here for no particular reason other
than illustration. There are no escape sequences here, so either form would
suffice. Importantly, the string literal will not create a string object as
before, but the text variable `t` is, of course, a string reference. Before it
can be used in a call to an undeclared function, it must be converted into a
temporary C string. This might require allocation in general; that allocation is
automatically managed.

Also, note that CQL assumes that calls to "no check" functions should be emitted
as written. In this way, you can use `printf` even though CQL knows nothing
about it.

Lastly, we have:

```sql
drop table my_data;
```

This is not strictly necessary because the database is in memory anyway and the
program is about to exit but there it is for illustration.

Now Data Manipulation Language (i.e. insert and select here; and henceforth
DML) and DDL might fail for various reasons. If that happens the procedure will
`goto` a cleanup handler and return the failed return code instead of running
the rest of the code. Any temporary memory allocations will be freed and any
pending SQLite statements will be finalized. More on that later when we discuss
error handling.

With that we have a much more complicated program that prints "Hello, world"

### Introducing Cursors

In order to read data with reasonable flexibility, we need a more powerful
construction. Let's change our example again and start using some database
features.

```sql
declare procedure printf no check;

-- for previty the `create` in `create proc` can be elided
proc hello()
begin
  -- this time we use the ! short hand for not null
  create table my_data(
    pos int! primary key,
    txt text!
  );

  -- you can supply more than one set of values in a single insert
  -- but we didn't here.
  insert into my_data values(2, 'World');
  insert into my_data values(0, 'Hello');
  insert into my_data values(1, 'There');

  cursor C for select * from my_data order by pos;

  loop fetch C
  begin
    -- we elided the 'call' here to show the briefer syntax
    printf("%d: %s\n", C.pos, C.txt);
  end;

  close C;

  drop table my_data;
end;
```

Reviewing the essential parts of the above.

```sql
create table my_data(
  pos int! primary key,
  txt text!
);
```

The table now includes a position column to give us some ordering.  That is the
primary key.

```sql
insert into my_data values(2, 'World');
```

The insert statements provide both columns, not in the printed order. The insert
form where the columns are not specified indicates that all the columns will be
present, in order; this is more economical to type. CQL will generate errors at
compile time if there are any missing columns or if any of the values are not
type compatible with the indicated column.

The most important change is here:

```sql
cursor C for select * from my_data order by pos;
```

We've created a non-scalar variable `C`, a cursor over the indicated result set.
The results will be ordered by `pos`.

```sql
loop fetch C
begin
  ...
end;
```

This loop will run until there are no results left (it might not run at all if
there are zero rows, that is not an error).  The `FETCH` construct allows you to
specify target variables, but if you do not do so, then a synthetic structure is
automatically created to capture the projection of the `select`. In this case
the columns are `pos` and `txt`.  The automatically created storage exactly
matches the type of the columns in the select list (which could itself be a
tricky calculation). In this case the `select` is quite simple and the columns
of the result directly match the schema for `my_data`.  An integer and a string
reference.  Both not null.


```sql
printf("%d: %s\n", C.pos, C.txt);
```

The storage for the cursor is given the same names as the columns of the
projection of the select, in this case the columns were not renamed in the
select clause so `pos` and `txt` are the fields in the cursor.  Double quotes
were used in the format string to get the newline in there easily.

```sql
close C;
```

The cursor is automatically released at the end of the procedure, but in this
case, we'd like to release it before the `drop table` operation occurs.
Therefore, an explicit `close` statement is included. However, this sort of
`close` is frequently omitted since automatic cleanup takes care of it.

If you compile and run this program, you'll get this output:

```bash
$ cc -x c -E hello.sql | cql --cg hello.h hello.c
$ cc -o hello main.c hello.c cqlrt.c -lsqlite3
$ ./hello
0: Hello
1: There
2: World
```

So the data was inserted and then sorted.

### Going Crazy

We've only scratched the surface of what SQLite can do, and almost all DML constructs
are supported by CQL. This includes common table expressions, and even recursive
versions of the same. But remember, when it comes to DML, the CQL compiler only
has to validate the types and figure out what the result shape will be -- SQLite
always does all the heavy lifting of evaluation. All of this means with
remarkably little additional code, the example below from the SQLite
documentation can be turned into a CQL stored proc using the constructs we have
defined above.


```sql
-- needed to allow vararg calls to C functions
declare proc printf no check;

-- proc and procedure can be used interchangeably
procedure mandelbrot()
begin
  -- this is basically one giant select statement
  cursor C for
    with recursive
      -- x from -2.0 to +1.2
      xaxis(x) as (select -2.0 union all select x + 0.05 from xaxis where x < 1.2),

      -- y from -1.0 to +1.0
      yaxis(y) as (select -1.0 union all select y + 0.1 from yaxis where y < 1.0),

      m(iter, cx, cy, x, y) as (
        -- initial seed iteration count 0, at each of the points in the above grid
        select 0 iter, x cx, y cy, 0.0 x, 0.0 y from xaxis, yaxis
        union all
        -- the next point is always iter +1, same (x,y) and the next iteration of z^2 + c
        select iter+1 iter, cx, cy, x*x-y*y + cx x, 2.0*x*y + cy y from m
        -- stop condition, the point has escaped OR iteration count > 28
        where (m.x*m.x + m.y*m.y) < 4.0 and m.iter < 28
      ),
      m2(iter, cx, cy) as (
       -- find the last iteration for any given point to get that count
       select max(iter), cx, cy from m group by cx, cy
      ),
      a(t) as (
        -- convert the iteration count to a printable character, grouping by line
        select group_concat(substr(" .+*#", 1 + min(iter/7,4), 1), '')
        from m2 group by cy
      )
    -- group all the lines together
    select rtrim(t) line from a;

  -- slurp out the data
  loop fetch C
  begin
    call printf("%s\n", C.line);
  end;
end;
```

The above code uses various SQLite features to generate this text:

```bash
$
                                     ....#
                                    ..#*..
                                  ..+####+.
                             .......+####....   +
                            ..##+*##########+.++++
                           .+.##################+.
               .............+###################+.+
               ..++..#.....*#####################+.
              ...+#######++#######################.
           ....+*################################.
  #############################################...
           ....+*################################.
              ...+#######++#######################.
               ..++..#.....*#####################+.
               .............+###################+.+
                           .+.##################+.
                            ..##+*##########+.++++
                             .......+####....   +
                                  ..+####+.
                                    ..#*..
                                     ....#
                                      +.
```

The above won't come up very often, but it does illustrate several things:

 * `WITH RECURSIVE` actually provides a full lambda calculus so arbitrary
   computation is possible
 * You can use `WITH RECURSIVE` to create table expressions that are sequences
   of numbers easily, with no reference to any real data

A working version of this code can be found in the `sources/demo` directory of
the CG/SQL project. Additional demo code is available in
[Appendix 10](./appendices/10_working_example.md)
