---
title: "Chapter 5: Types of Cursors, Shapes, OUT and OUT UNION, and FETCH"
weight: 5
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

In the previous chapters we have used cursor variables without fully discussing
them. Most of the uses are fairly self-evident but a more exhaustive discussion
is also useful.

First there are three types of cursors, as we will see below.

### Statement Cursors

A statement cursor is based on a SQL `SELECT` statement, or some other statement
that returns a result set (like DML with `RETURNING`).  An example might look like this:

```sql
-- somewhere we declare this table
create table xy_table(x int, y int);

-- legacy syntax
cursor C for select x, y from xy_table;

-- economical syntax (same thing)
cursor C for select x, y from xy_table;
```

When compiled, this will result in creating a SQLite statement object (type
`sqlite_stmt *`) and storing it in a variable called `C_stmt`.  This statement
can then be used later in various ways.

Here's perhaps the simplest way to use the cursor above:

```sql
declare x, y int;
fetch C into x, y;
```

This will have the effect of reading one row from the results of the query into
the local variables `x` and `y`.

These variables might then be used to create some output such as:

```sql
-- somewhere we say printf is a varargs external function with any arg in any position
declare proc printf no check;

-- note use of double quotes so that \n is legal
call printf("x:%d y:%d\n", ifnull(x, 0), ifnull(y,0));
```

More generally, attempting to fetch values may or may not actually get a row,
there may be none left.  The cursor variable `C` can be used by itself as a
boolean to indicate if the fetch succeeded.  So a more complete example might be:

```sql
if C then
  call printf("x:%d y:%d\n", ifnull(x, 0), ifnull(y,0));
else
  call printf("nada\n");
end if
```

This often happens in a loop, yielding this form:

```sql
loop fetch C into x, y
begin
  call printf("x:%d y:%d\n", ifnull(x, 0), ifnull(y,0));
end;
```

The last example above reads all the rows and prints them.

Now if the table `xy_table` had instead had dozens of columns, those
declarations would be very verbose and error prone, and frankly annoying,
especially if the table definition was changing over time.

To make this a little easier, the cursor can include its own storage, sometimes
these are called 'automatic' cursors.  The storage is declared implicitly and
includes all the necessary fields to exactly match the rows of the cursor.
Using the automatic syntax for the above looks like so:

```sql
cursor C for select * from xy_table;
fetch C;
if C then
  call printf("x:%d y:%d\n", ifnull(C.x, 0), ifnull(C.y,0));
end if;
```

or the equivalent loop form:

```sql
cursor C for select * from xy_table;
loop fetch C
begin
  call printf("x:%d y:%d\n", ifnull(C.x, 0), ifnull(C.y,0));
end;
```

All the necessary local state is automatically created, hence the name
"automatic" cursor. This pattern is generally preferred, but the loose variables
pattern is in some sense more general.  For instance you could store values
directing into out variables this way.

In all the cases semantic errors are produced if the number and type of
variables do not match the select statement.

### Shapes

In the following discussion the notion of "shapes" will make its first major
appearance. Shapes are one of the key CQL features that allow
you to work with dozens of columns without having to type their names all
the time or create a maintenance disaster. They first made their
appearance in cursor features but soon found their way throughout the language,
as we will see below, we consume shapes with `LIKE` when the shape is used for
type information and `FROM` when it is being expanded into values.

SQL doesn't have the notion of structure types, but structures actually appear
pretty directly in many places.  Generally we call these things "shapes" and
there are a variety of sources for shapes including:

* the columns of a table, `like my_table`
* the projection of a sample `SELECT` statement `like select 1 x, 2 y`
* the columns of a cursor use `like my_cursor`
* the result type of a procedure with a result set `like my_proc`
* the arguments of a procedure  `like my_proc ARGUMENTS`
* the columns of an interface

The interface statement directly declares a named shape. e.g.,

```sql
interface foo (x int, y int, n text!);
```

The other shape sources similarly define a set of named fields.

The most typical ways to consume shapes are using `LIKE`, for instance:

```sql
-- all of the shape S
LIKE S

-- x and y from S
LIKE S(x, y)

-- all of S except x and y
LIKE S(-x, -y)

-- take from S, the columns of shapes A and B plus x and y
-- this of course creates an error if S does not in fact
-- have all those columns
LIKE S(like A, like B, x, y)
```

When consuming values from somewhere with a shape we use:

```sql
FROM X LIKE Y
```

The `FROM` part indicates the domain (the source of the values) and the optional
`LIKE` part indicates the subset of those values that are desired (via one of
the shape selections above). For example

```sql
FROM ARGUMENTS [like ...]
FROM LOCALS [like ...]
FROM a_cursor [like ...]
FROM an_arg_bundle [like ...]
```

The most important use of shapes is to create value cursors.

### Value Cursors

The purpose of value cursors is to make it possible for a stored procedure to
work with structures as a unit rather than only field by field.  The value cursor
need not have a SQLite equivalent, any shape source will do to define it and any
data source, computed or otherwise, can be used to load it.

Let's first start with how you declare a value cursor.  It is providing one of
the shape sources above.

So:

```sql
cursor C like xy_table;
cursor C like select 1 a, 'x' b;
cursor C like (a int!, b text!);
cursor C like a_view;
cursor C like a_cursor;
cursor C like an_interface;
cursor C like a_previously_declared_procedure;
cursor C like a_previously_declared_procedure arguments;
```

Any of those forms define a valid set of columns, i.e., a shape.  Note that the
`select` example in no way causes the query provided to run. Instead, the select
statement is analyzed and the column names and types are computed.  The cursor
gets the same field names and types.  The cursor's shape is literally `like` the
`select` clause but that `select` never runs.

The last two examples assume that there is a stored procedure defined somewhere
earlier in the same translation unit and that the procedure returns a result set
or has arguments, respectively.

In all cases the cursor declaration makes a cursor that could hold the indicated
result. That result can then be loaded with `FETCH` or emitted with `OUT` or
`OUT UNION` -- all of which is discussed below.

#### Loading a Value Cursor

Once we have declared a value cursor, we can load it with values using `FETCH` in
its value form. Here are some examples:

You can `fetch` into a cursor by providing compatible values:

```sql
fetch C from values(1,2);
```

```sql
fetch C(x,y) from values(1,2);
```

```sql
-- this form makes it clear which field is getting which value
fetch C using
    1 x,
    2 y;
```

Fetch from a call to a procedure that returns a single row:

```sql
fetch C from call my_previously_declared_stored_proc();
```

Fetch from another cursor:
```sql
fetch C from D;
```

In this last case if `D` is a statement cursor it must also be "automatic" (i.e.
it has the storage).  This form lets you copy a row and save it for later.  For
instance, in a loop you could copy the current max-value row into a value cursor
and use it after the loop, like so:

```sql
cursor C for select * from somewhere;
cursor D like C;

loop fetch C
begin
  if (not D or D.something < C.something) then
    fetch D from C;
  end if;
end;
```

After the loop, `D` is either empty because there were no rows (so `if D`
fails) or it has the row with the maximum value of `something`,
whatever that is. Note that you don't have to copy each field separately
nor change the code if new fields are added.

Value cursors always have their own storage, so you could say all value
cursors are "automatic".

And as we saw above, value cursors may or may not be holding a row.

```sql
cursor C like xy_table;
if not C then
  call printf("this will always print because C starts empty\n");
end if;
```

When you call a procedure you may or may not get a row as we'll see below.

The third type of cursor is a "result set" cursor but that won't make any sense
until we've discussed result sets which requires `OUT` and/or `OUT UNION` and so
we'll go on to those statements next.  As it happens, we are recapitulating the
history of cursor features in the CQL language by exploring the system in this
way.

#### Benefits of typed name lists for cursor shapes

This form allows any kind of declaration, for instance:

```sql
cursor C like ( id int!, val real, flag boolean );
```

This wouldn't really give us much more than the other forms, however typed name
lists can include `LIKE` in them again, as part of the list.  Which means you can
do this kind of thing:

```sql
-- make a cursor C just like D but also add the fields extra1 and extra2
cursor C like (like D, extra1 real, extra2 bool)
```

You could then load that cursor like so:

```sql
fetch C from values (from D, 2.5, false);
```

and now you have `D` plus 2 more fields which maybe you want to output.

Importantly this way of doing it means that `C` always includes `D`, even if `D`
changes over time.  As long as the `extra1` and `extra2` fields don't conflict
names it will always work.

### OUT Statement

Value cursors were initially designed to create a convenient way for a procedure
to return a single row from a complex query without having a crazy number of
`OUT` parameters.  It's easiest to illustrate this with an example.

Suppose you want to return several variables, the "classic" way to do so would
be a procedure like this:

```sql
proc get_a_row(
  id_ integer!,
  out got_row bool!,
  out w int!,
  out x int,
  out y text!,
  out z real)
begin
  cursor C for select w, x, y, z from somewhere where id = id_;
  fetch C into w, x, y, z;
  set got_row := C;
end;
```

This is already verbose, but you can imagine the situation gets very annoying if
`get_a_row` has to produce a couple dozen column values.  And of course you have
to get the types exactly right. And they might evolve over time. This is not
very friendly to maintainers.

On the receiving side you must do something just as awkward:

```sql
declare got_row bool!;
var w int!;
var x int;
var y text;
var z real;
call get_a_row(some_id, got_row, w, x, y, z);
```

Using the `out` statement we get the equivalent functionality with a much
simplified pattern. It looks like this:

```sql
proc get_a_row(id_ int!)
begin
  cursor C for select w, x, y, z from somewhere where id = id_;
  fetch C;
  out C;
end;
```

To use the new procedure you simply do this:
```sql
cursor C like get_a_row;
fetch C from call get_a_row(id);
```

In fact, originally you did the two steps above in one statement and that was
the only way to load a value cursor. Later, the calculus was generalized. The
original form still works:

```sql
cursor C fetch from call get_a_row(id);
```

The `OUT` statement lets you return a single row economically and lets you then
test if there actually was a row and if so, read the columns. It infers all the
various column names and types so it is resilient to schema change and generally
a lot less error prone than having a large number of `out` arguments to your
procedure.

Once you have the result in a value cursor you can do the usual cursor
operations to get values from it or pass pieces of it to other procedures.

The use of the `LIKE` keyword to refer to groups of columns spread to other
places in CQL as a very useful construct, but it began here with the need to
describe a cursor shape economically, by reference.

### OUT UNION Statement

The semantics of the `OUT` statement are that it always produces one row of
output (a procedure can produce no row if an `OUT` never actually rans but the
procedure does use `OUT`).

If an `OUT` statement runs more than once, the most recent row becomes the
result, and all such statements must agree on the shape of the result.  So the
`OUT` statement really does mirror having one `OUT` variable for each output
column.  This was its intent and procedures that return at most one row are very
common so it works well enough.  In most cases it's actually always exactly one row
and not zero.

However, in general, one row results do not suffice; you might want to produce a
result set from various sources, possibly with some computation as part of the
row creation process.  To make general results, you need to be able to emit
multiple rows from a computed source.  This is exactly what `OUT UNION`
provides.

Here's a (somewhat contrived) example of the kind of thing you can do with this
form:

```sql
proc foo(n int!)
begin
  cursor C like select 1 value;
  let i := 0;
  while i < n
  begin
     -- emit one row for every int
     fetch C from values(i);
     out union C;
     set i := i + 1;
  end;
end;
```

In `foo` above, we make an entire result set out of thin air.  It isn't a very
interesting result, but of course any computation would have been possible.

This pattern is very flexible as we see below in `bar` where
we merge two different data streams.

```sql
create table t1(id int, stuff text, [other things too]);
create table t2(id int, stuff text, [other things too]);

proc bar()
begin
  cursor C for select * from t1 order by id;
  cursor D for select * from t2 order by id;

  fetch C;
  fetch D;

  -- we're going to merge these two queries
  while C or D
  begin
    -- if both have a row pick the smaller id
    if C and D then
       if C.id < D.id then
         out union C;
         fetch C;
       else
         out union D;
         fetch D;
       end if;
    else if C then
      -- only C has a row, emit that
      out union C;
      fetch C;
    else
      -- only D has a row, emit that
      out union D;
      fetch D;
    end if;
  end;
end;
```

Just like `foo`, in `bar`, each time `OUT UNION` runs a new row is accumulated
creating the overall result set.

The normal way to create a result set is to make a procedure that ends with a
`SELECT` statement, or something else that returns rows. In that case CQL
automatically creates a fetcher function that does something like an `OUT UNION`
loop -- it loops over the SQLite statement for the `SELECT` and fetches each
row, materializing a result.  This "fetcher" can be called from `C` or `Lua` directly
to get a materialized result set and it is used by CQL itself as needed.

With `OUT UNION` you take manual control of that same process creating identical
result sets. This allows you to build arbitrary result sets using computations
of your choice.  Note that the data from either of `C` or `D` above could have
been modified, replaced, skipped, normalized, etc. with any kind of computation.
Even entirely synthetic rows can be computed and inserted into the output as we
saw in `foo`.  This is invaluable for mocking.

### Result Set Cursors

Now that we have `OUT UNION` it makes sense to talk about the final type of
cursor.

`OUT UNION` makes it possible to create arbitrary result sets using a mix of
sources and filtering.  Unfortunately this result type is not a simple row, nor
is it a SQLite statement.  This meant that neither of the existing types of
cursors could hold the result of a procedure that used `OUT UNION`. and then CQL
could not itself consume its own results.

To address this hole, we need an additional cursor type. The syntax is exactly
the same as the statement cursor cases described above but, instead of holding a
SQLite statement, the cursor holds a result set pointer along with the current
and maximum row numbers. Stepping through the cursor simply increments the row
number and fetches the next row out of the rowset instead of from SQLite.

Example:

```sql
-- reading the above
proc reader()
begin
  cursor C for call bar();
  loop fetch C
  begin
    call printf("%d %s\n", C.id, C.stuff);  -- or whatever fields you need
  end;
end;
```

If `bar` had been created with a `SELECT`, `UNION ALL`, and `ORDER BY` to merge
the results, the above would have worked with `C` being a standard statement
cursor, iterating over the union. Since `foo` produces a result set, CQL
transparently produces a suitable cursor implementation behind the scenes, but
otherwise the usage is the same.

Note this is a lousy way to simply iterate over rows; you have to materialize
the entire result set so that you can just step over it.  Re-consuming like this
is not recommended at all for production code, but it is ideal for testing
result sets that were made with `OUT UNION` which otherwise would require C/C++
to test.  Testing CQL with CQL is generally a lot easier.

### Reshaping Data, Cursor `LIKE` forms

There are lots of cases where you have big rows with many columns, and there are
various manipulations you might need to do.

What follows is a set of useful syntactic sugar constructs that simplify
handling complex rows.  The idea is that pretty much anywhere you can specify a
list of columns you can instead use the `LIKE x` construct to get the columns as
they appear in the shape `x` -- which is usually a table or a cursor.

It’s a lot easier to illustrate with examples, even though these are, again, a
bit contrived.

First we need some table with lots of columns -- usually the column names are
much bigger which makes it all the more important to not have to type them over
and over, but in the interest of some brevity,
here is a big table:

```sql
create table big (
  id int primary key,
  id2 integer unique,
  a int,
  b int,
  c int,
  d int,
  e int,
  f int
);
```

This example showcases several of the cursor and shape slicing features by emitting
two related rows:

```sql
proc foo(id_ int!)
begin
  -- this is the shape of the result we want -- it's some of the columns of "big"
  -- note this query doesn't run, we just use its shape to create a cursor
  -- with those columns.
  cursor result like select id, b, c, d from big;

  -- fetch the main row, specified by id_
  -- main row has all the fields, including id2
  cursor main_row for select * from big where id = id_;
  fetch main_row;

  -- now fetch the result columns out of the main row
  -- `like result` here means to use the names of the result cursor
  -- to index into the columns of the main_row cursor, and then
  -- and store them in `result`
  fetch result from cursor main_row(like result);

  -- this is our first result row
  out union result;

  -- now we want the related row, but we only need two columns
  -- from the related row, 'b' and 'c'
  cursor alt_row for select b, c from big where big.id2 = main_row.id2;
  fetch alt_row;

  -- update some of the fields in 'result' from the `alt_row`
  update cursor result(like alt_row) from cursor alt_row;

  -- and emit the modified result, so we've generated two rows
  out union result;
end;
```

Now let's briefly discuss what is above.  The two essential parts are:

`fetch result from cursor main_row(like result);`

and

`update cursor result(like alt_row) from cursor alt_row;`

In the first case what we're saying is that we want to load the columns of
`result` from `main_row` but we only want to take the columns that are actually
present in `result`.  So this is a narrowing of a wide row into a smaller row.
In this case, the smaller row, `result`, is what we want to emit. We needed the
other columns to compute `alt_row`.

The second case, what we're saying is that we want to update `result` by
replacing the columns found in `alt_row` with the values in `alt_row`. So in
this case we're writing a smaller cursor into part of a wider cursor. Note that
we used the `update cursor` form here because it preserves all other columns.
If we used `fetch` we would be rewriting the entire row contents, using `NULL`
if necessary, and that is not desired here.

Here is the rewritten version of the above procedure; this is what ultimately
gets compiled into C.

```sql
PROC foo (id_ INT!)
BEGIN
  CURSOR result LIKE SELECT id, b, c, d FROM big;
  DECLARE main_row CURSOR FOR SELECT * FROM big WHERE id = id_;
  FETCH main_row;

  FETCH result(id, b, c, d)
    FROM VALUES(main_row.id, main_row.b, main_row.c, main_row.d);
  OUT UNION result;

  DECLARE alt_row CURSOR FOR SELECT b, c FROM big WHERE big.id2 = main_row.id2;
  FETCH alt_row;

  UPDATE CURSOR result(b, c) FROM VALUES(alt_row.b, alt_row.c);
  OUT UNION result;
END;
```

Of course you could have typed the above directly but if there are 50 odd
columns it gets old fast and is very error prone.  The sugared form is going to
be 100% correct and will require much less typing and maintenance.

Finally, while I've shown both `LIKE` forms separately, they can also be used
together.  For instance:

```sql
  update cursor C(like X) from cursor D(like X);
```

The above would mean, "move the columns that are found in `X` from cursor
`D` to cursor `C`", presuming `X` has columns common to both.

### Fetch Statement Specifics

Many of the examples used the `FETCH` statement in a sort of demonstrative way
that is hopefully self-evident but the statement has many forms and so it's
worth going over them specifically.  Below we'll use the letters `C` and `D` for
the names of cursors.  Usually `C`;

#### Fetch with Statement or Result Set Cursors

A cursor declared in one of these forms:

* `cursor C for select * from foo;`
* `cursor C for call foo();`  (foo might end with a `select` or use `out union`)

is either a statement cursor or a result set cursor.  In either case the cursor
moves through the results.  You load the next row with:

* `FETCH C`, or
* `FETCH C into x, y, z;`

In the first form `C` is said to be *automatic* in that it automatically
declares the storage needed to hold all its columns.  As mentioned above,
automatic cursors have storage for their row.

Having done this fetch you can use C as a scalar variable to see if it holds a
row, e.g.

```sql
cursor C for select * from foo limit 1;
fetch C;
if C then
  -- bingo we have a row
  call printf("%s\n", C.whatever);
end if
```

You can easily iterate, e.g.

```sql
cursor C for select * from foo;
loop fetch C
begin
  -- one time for every row
  call printf("%s\n", C.whatever);
end;
```

Automatic cursors are so much easier to use than explicit storage that explicit
storage is rarely seen.  Storing to `out` parameters is one case where explicit
storage actually is the right choice, as the `out` parameters have to be
declared anyway.

#### Fetch with Value Cursors

 A value cursor is declared in one of these ways:

 * `cursor C fetch from call foo(args)`
   * `foo` must be a procedure that returns one row with `OUT`
 * `cursor C like select 1 id, "x" name;`
 * `cursor C like X;`
   * where X is the name of a table, a view, another cursor, or a procedure that
     returns a structured result

 A value cursor is *always* automatic; it's purpose is to hold a row. It doesn't
 iterate over anything but it can be re-loaded in a loop.

 * `fetch C` or `fetch C into ...` is not valid on such a cursor, because it
   doesn't have a source to step through.

 The canonical way to load such a cursor is:

 * `fetch C from call foo(args);`
   * `foo` must be a procedure that returns one row with `OUT`
 * `fetch C(a,b,c...) from values(x, y, z);`

The first form is in some sense the origin of the value cursor. Value cursors
were added to the language initially to provide a way to capture the single row
`OUT` statement results, much like result set cursors were added to capture
procedure results from `OUT UNION`.  In the first form, the cursor storage (a C
struct) is provided by reference as a hidden out parameter to the procedure and
the procedure fills it in. The procedure may or may not use the `OUT` statement
in its control flow, as the cursor might not hold a row.  You can use `if C then
...` as before to test for a row.

The second form is more interesting as it allows the cursor to be loaded from
arbitrary expressions subject to some rules:

* you should think of the cursor as a logical row: it's either fully loaded or
  it's not, therefore you must specify enough columns in the column list to
  ensure that all `NOT NULL` columns will get a value
* if not mentioned in the list, NULL will be loaded where possible
* if insufficient columns are named, an error is generated
* if the value types specified are not compatible with the column types
  mentioned, an error is generated
* later in this chapter, we'll show that columns can also be filled with dummy
  data using a seed value

With this form, any possible valid cursor values could be set, but many forms of
updates that are common would be awkward. So there are various forms of
syntactic sugar that are automatically rewritten into the canonical form.  See
the examples below:

* `fetch C from values(x, y, z)`
  * if no columns are specified this is the same as naming all the columns, in
    declared order

* `fetch C from arguments`
  * the arguments to the procedure in which this statement appears are used as
    the values, in order
  * in this case `C` was also rewritten into `C(a,b,c,..)` etc.

* `fetch C from arguments like C`
  * the arguments to the procedure in which this statement appears are used, by
    name, as the values, using the names of of the indicated shape
  * the order in which the arguments appeared no longer matters, the names that
    match the columns of C are used if present
  * the formal parameter name may have a single trailing underscore (this is
    what `like C` would generate)
  * e.g. if `C` has columns `a` and `b` then there must exist formals named `a`
    or `a_` and `b` or `b_`, in any position

* `fetch C(a,b) from cursor D(a,b)`
  * the named columns of D are used as the values
  * in this case the statement becomes: `fetch C(a,b) from values(D.a, D.b);`

That most recent form doesn't seem like it saves much, but recall the first
rewrite:

* `fetch C from cursor D`
  * both cursors are expanded into all their columns, creating a copy from one
    to the other
  * `fetch C from D` can be used if the cursors have the exact same column names
    and types; it also generates slightly better code and is a common case

 It is very normal to want to use only some of the columns of a cursor; these
 `LIKE` forms do that job.  We saw some of these forms in an earlier example.

 * `fetch C from cursor D(like C)`
   * here `D` is presumed to be "bigger" than `C`, in that it has all of the `C`
     columns and maybe more.  The `like C` expands into the names of the `C`
     columns so `C` is loaded from the `C` part of `D`
   * the expansion might be `fetch C(a, b, g) from values (D.a, D.b, D.g)`
   * `D` might have had fields `c, d, e, f` which were not used because they are
     not in `C`.

 The symmetric operation, loading some of the columns of a wider cursor can be
 expressed neatly:

 * `fetch C(like D) from cursor D`
   * the `like D` expands into the columns of `D` causing the cursor to be
     loaded with what's in `D` and `NULL` (if needed)
   * when expanded, this might look like `fetch C(x, y) from values(D.x, D.y)`

`LIKE` can be used in both places, for instance suppose `E` is a shape
that has a subset of the rows of both `C` and `D`.  You can write a form
like this:

* `fetch C(like E) from cursor D(like E)`
  * this means take the column names found in `E` and copy them from D to C.
  * the usual type checking is done

 As is mentioned above, the `fetch` form means "load an entire row into the
 cursor". This is important because "half loaded" cursors would be semantically
 problematic.  However there are many cases where you might like to amend the
 values of an already loaded cursor.  You can do this with the `update` form.

 * `update cursor C(a,b,..) from values(1,2,..);`
   * the update form is a no-op if the cursor is not already loaded with values (!!)
   * the columns and values are type checked so a valid row is ensured (or no row)
   * all the re-writes above are legal so `update cursor C(like D) from D` is
     possible; it is in fact the use-case for which this was designed.

### Calling Procedures with Argument Bundles

It's often desirable to treat bundles of arguments as a unit, or cursors as a
unit, especially when calling other procedures.  The shape patterns above are
very helpful for moving data between cursors, and the database. These can be
rounded out with similar constructs for procedure definitions and procedure
calls as follows.

First we'll define some shapes to use in the examples.  Note that we made `U`
using `T`.

```sql
-- these tables appear in the following examples
create table T(x int!, y int!,  z int!);
create table U(like T, a int!, b int!);
```

We haven't mentioned this before but the implication of the above is that you
can use the `LIKE` construct inside a table definition to add columns from a
shape.

We can also use the `LIKE` construct to create procedure arguments.  To avoid
conflicts with column names, when used this way the procedure arguments all get
a trailing underscore appended to them.  The arguments will be `x_`, `y_`, and
`z_` as we can see if the following:

```sql
proc p1(like T)
begin
  call printf("%d %d %d\n", x_, y_, z_);
end;
```

Shapes can also be used in a procedure call, as showed below. This next example
is obviously contrived, but of course it generalizes. It is exactly equivalent
to the above.

```sql
proc p2(like T)
begin
  call printf("%d %d %d\n", from arguments);
end;
```

Now we might want to chain these things together.  This next example uses a
cursor to call `p1`.

```sql
proc q1()
begin
 cursor C for select * from T;
 loop fetch C
 begin
   /* this is the same as call p(C.x, C.y, C.z) */
   call p1(from C);
 end;
end;
```

The `LIKE` construct allows you to select some of the arguments, or some of a
cursor to use as arguments.  This next procedure has more arguments than just
`T`. The arguments will be `x_`, `y_`, `z_`, `a_`, `b_`.  But the call will
still have the `T` arguments `x_`, `y_`, and `z_`.

```sql
proc q2(like U)
begin
  /* just the args that match T: so this is still call p(x_, y_, z_) */
  call p1(from arguments like T);
end;
```

Or similarly, using a cursor.

```sql
proc q3(like U)
begin
 cursor C for select * from U;
 loop fetch C
 begin
  /* just the columns that match T so this is still call p(C.x, C.y, C.z) */
  call p1(from C like T);
 end;
end;
```

Note that the `from` argument forms do not have to be all the arguments.  For
instance you can get columns from two cursors like so:

```sql
  call something(from C, from D)
```

All the varieties can be combined but of course the procedure signature must
match.  And all these forms work in function expressions as well as procedure
calls.

e.g.

```sql
  set x := a_function(from C);
```

Since these forms are simply syntatic sugar, they can also appear inside of
function calls that are in SQL statements. The variables mentioned will be
expanded and become bound variables just like any other variable that appears in
a SQL statement.

Note the form `x IN (from arguments)` is not supported at this time, though this
would be a relatively easy addition.

### Using Named Argument Bundles

There are many cases where stored procedures require complex arguments using
data shapes that come from the schema, or from other procedures.  As we have
seen the `LIKE` construct for arguments can help with this, but it has some
limitations. Let's consider a specific example to study:

```sql
create table Person (
  id text primary key,
  name text!,
  address text!,
  birthday real
);
```

To manage this table we might need something like this:

```sql
proc insert_person(like Person)
begin
  insert into Person from arguments;
end;
```

As we have seen, the above expands into:

```sql
proc insert_person(
  id_ text!,
  name_ text!,
  address_ text!,
  birthday_ real)
begin
  insert into Person(id, name, address, birthday)
    values(id_, name_, address_, birthday_);
end;
```

It's clear that the sugared version is a lot easier to reason about than the
fully expanded version, and much less prone to errors as well.

This much is already helpful, but just those forms aren't general enough to
handle the usual mix of situations.  For instance, what if we need a procedure
that works with two people? A hypothetical `insert_two_people` procedure cannot
be written with the forms we have so far.

To generalize this the language adds the notion of named argument bundles. The
idea here is to name the bundles which provides a useful scoping.  Example:

```sql
proc insert_two_people(p1 like Person, p2 like Person)
begin
  -- using a procedure that takes a Person args
  call insert_person(from p1);
  call insert_person(from p2);
end;
```

or alternatively

```sql
proc insert_two_people(p1 like Person, p2 like Person)
begin
  -- inserting a Person directly
  insert into Person from p1;
  insert into Person from p2;
end;
```

The above expands into:

```sql
proc insert_two_people(
  p1_id text!,
  p1_name text!,
  p1_address text!,
  p1_birthday real,
  p2_id text!,
  p2_name text!,
  p2_address text!,
  p2_birthday real)
begin
  insert into Person(id, name, address, birthday)
    values(p1_id, p1_name, p1_address, p1_birthday);
  insert into Person(id, name, address, birthday)
    values(p2_id, p2_name, p2_address, p2_birthday);
end;
```

Or course different named bundles can have different types -- you can create and
name shapes of your choice.  The language allows you to use an argument bundle
name in all the places that a cursor was previously a valid source.  That
includes `insert`, `fetch`, `update cursor`, and procedure calls.  You can refer
to the arguments by their expanded name such as `p1_address` or alternatively
`p1.address` -- they mean the same thing.

Here's another example showing a silly but illustrative thing you could do:

```sql
proc insert_lotsa_people(P like Person)
begin
  -- make a cursor to hold the arguments
  cursor C like P;

  -- convert arguments to a cursor
  fetch C from P;

  -- set up to patch the cursor and use it 20 times
  let i := 0;
  while i < 20
  begin
    update cursor C(id) from values(printf("id_%d", i));
    insert into Person from C;
    set i := i + 1;
  end;
end;
```

The above shows that you can use a bundle as the source of a shape, and you can
use a bundle as a source of data to load a cursor.  After which you can do all
the usual value cursor things.  Of course in this case the value cursor was
redundant, we could just as easily have done something like this:

```sql
  set P_id := printf("id_%d", i);
  insert into Person from P;
  set i := i + 1;
```

>NOTE: the CQL JSON output includes extra information about procedure arguments
>if they originated as part of a shape bundle do identify the shape source
>for tools that might need that information.

### The @COLUMNS construct in the SELECT statement

The select list of a `SELECT` statement already has complex syntax and
functionality, but it is a very interesting place to use shapes.  To make it
possible to use shape notations and not confuse that notation with standard SQL
the `@COLUMNS` construct was added to the language.  This allows for a sugared
syntax for extracting columns in bulk.

The `@COLUMNS` clause is like of a generalization of the `select T.*` with shape
slicing and type-checking.  In fact, the standard forms `*` and `T.*` are converted
to the more general `@COLUMNS` form internally. The forms are discussed below:


#### Columns from a join table or tables

This is the simplest form, it's just like `T.*`:

```sql
-- this is the same as A.*
select @columns(A) from ...;

-- this is the same as A.*, B.*
select @columns(A, B) from ...;
```

#### Columns from a particular joined table that match a shape

This allows you to choose some of the columns of one table of the FROM clause.

```sql
-- the columns of A that match the shape Foo
select @columns(A like Foo) from ...;

-- get the Foo shape from A and the Bar shape from B
select @columns(A like Foo, B like Bar) from ...;
```

#### Columns from any that match a shape, from anywhere in the FROM

Here we do not specify a particular table that contains the columns, they could
come from any of the tables in the FROM clause.

```sql
--- get the Foo shape from anywhere in the join
select @columns(like Foo) from ...;

-- get the Foo and Bar shapes, from anywhere in the join
select @columns(like Foo, like Bar) from ...;
```

#### Subsets of Columns from shapes

This pattern can be helpful for getting part of a shape.

```sql
-- get the a and b from the Foo shape only
select @columns(like Foo(a,b))
```

This pattern is great for getting almost all of a shape (e.g. all but the pk).

```sql
-- get the Foo shape except the a and b columns
select @columns(like Foo(-a, -b))
```

#### Specific columns

This form allows you to slice out a few columns without defining a shape, you
simply list the exact columns you want.

```sql
-- T1.x and T2.y plus the Foo shape
select @columns(T1.x, T2.y, like Foo) from ...;
```

#### Distinct columns

Its often the case that there are duplicate column names in the `FROM` clause.
For instance, you could join `A` to `B` with both having a column `pk`. The
final result set can only have one column named `pk`, the distinct clause helps
you to get distinct column names.  In this context `distinct` is about column
names, not values.  This is especially helpful when it is known that the
duplicate column names have the same values like in a join.

```sql
-- removes duplicate column names
-- e.g. there will be one copy of 'pk'
select @columns(distinct A, B) from A join B using(pk);

-- if both Foo and Bar have an (e.g.) 'id' field you only get one copy
select @columns(distinct like Foo, like Bar) from ...;
```

If a specific column is mentioned it is always included, but later expressions
that are not a specific column will avoid that column name.

```sql
-- if F or B has an x it won't appear again, just T.x
select @columns(distinct T.x, F like Foo, B like Bar) from F, B ..;
```

Of course this is all just sugar, so it all compiles to a column list with table
qualifications -- but the syntax is very powerful.  You can easily narrow a wide
table, or fuse joins that share common keys without creating conflicts.

```sql
-- just the Foo columns
select @columns(like Foo) from Superset_Of_Foo_From_Many_Joins_Even;

-- only one copy of 'pk'
select @columns(distinct A, B, C) from
  A join B using (pk) join C using (pk);
```

And of course you can define shapes however you like and then use them to slice
off column chucks of your choice.  There are many ways to build up shapes from
other shapes.  For instance, you can declare procedures that return the shape
you want and never actually create the procedure -- a pattern is very much like
a shape "typedef".  E.g.

```sql
interface shape1 (x int, y real, z text);
interface shape2 (like shape1, u bool, v bool);
```

With this combination you can easily define common column shapes and slice them
out of complex queries without having to type the columns names over and over.

### Missing Data Columns, Nulls and Dummy Data

What follows are the rules for columns that are missing in an `INSERT`, or
`FETCH` statement. As with many of the other things discussed here, the forms
result in automatic rewriting of the code to include the specified dummy data.
So SQLite will never see these forms.

Two things to note: First, the dummy data options described below are really
only interesting in test code, it's hard to imagine them being useful in
production code.  Second, none of what follows applies to the `update cursor`
statement because its purpose is to do partial updates on exactly the specified
columns and we're about to talk about what happens with the columns that were
not specified.

When fetching a row all the columns must come from somewhere; if the column is
mentioned or mentioned by rewrite then it must have a value mentioned, or a
value mentioned by rewrite. For columns that are not mentioned, a NULL value is
used if it is legal to do so.  For example, `fetch C(a) from values(1)` might
turn into `fetch C(a,b,c,d) from values (1, NULL, NULL, NULL)`

In addition to the automatic NULL you may add the annotation
`@dummy_seed([long integer expression])`. If this annotation is present
then:

* the expression is evaluated and stored in the hidden variable _seed_
* all integers, and long integers get _seed_ as their value (possibly truncated)
* booleans get 1 if and only if _seed_ is non-zero
* strings get the name of the string column an underscore and the value as text
  (e.g. "myText_7" if _seed_ is 7)
* blobs get the name of the blob column and the value as text (e.g. "myBlob7")

This construct is hugely powerful in a loop to create many complete rows with
very little effort, even if the schema change over time.

```sql
var i int!;
cursor C like my_table;
set i := 0;
while (i < 20)
begin
  -- the id is fully specified the rest come from the dummy
  fetch C(id) from values(i+10000) @dummy_seed(i);
  insert into my_table from cursor C;
end;
```

Now in this example we don't need to know anything about `my_table` other than
that it has a column named `id`.  This example shows several things:

 * we got the shape of the cursor from the table we were inserting into
 * you can do your own computation for some of the columns (those named) and
   leave the unnamed values to be defaulted
 * the rewrites mentioned above work for the `insert` statement as well as
   `fetch`
 * in fact `insert into my_table(id) values(i+10000) @dummy_seed(i)` would have
   worked too with no cursor at all
   * bonus, dummy blob data does work in insert statements because SQLite can do
     the string conversion easily
   * the dummy value for a blob is a blob that holds the text of the column name
     and the text of the seed just like a string column

The `@dummy_seed` form can be modified with `@dummy_nullables`, this indicates
that rather than using NULL for any nullable value that is missing, CQL should
use the seed value.  This overrides the default behavior of using NULL where
columns are needed.  Note the NULL filling works a little differently on insert
statements.  Since SQLite will provide a NULL if one is legal the column doesn't
have to be added to the list with a NULL value during rewriting, it can simply
be omitted, making the statement smaller.

Finally for `insert` statement only, SQLite will normally use the default value
of a column if it has one, so there is no need to add missing columns with
default values to the insert statement.  However if you specify
`@dummy_defaults` then columns with a default value will instead be rewritten
and they will get `_seed_` as their value.

Some examples.  Suppose columns `a`, `b`, `c` are not null;  `m`, `n` are nullable; and `x`,
`y` have defaults.

```
-- as written
insert into my_table(a) values(7) @dummy_seed(1000)

-- rewrites to
insert into my_table(a, b, c) values(7, 1000, 1000);
```

```
-- as written
insert into my_table(a) values(7) @dummy_seed(1000) @dummy_nullables

-- rewrites to
insert into my_table(a, b, c, m, n) values(7, 1000, 1000, 1000, 1000);
```

```
-- as written
insert into my_table(a) values(7) @dummy_seed(1000) @dummy_nullables @dummy_defaults

-- rewrites to
insert into my_table(a, b, c, m, n, x, y) values(7, 1000, 1000, 1000, 1000, 1000, 1000);
```

The sugar features on `fetch`, `insert`, and `update cursor` are as symmetric as
possible, but again, dummy data is generally only interesting in test code.
Dummy data will continue to give you valid test rows even if columns are added
or removed from the tables in question so it's a nice toil saver.

### Generalized Cursor Lifetimes aka Cursor "Boxing"

Generalized Cursor Lifetime refers to capturing a Statement Cursor in an object
so that it can used more flexibly.  Wrapping something in an object is often
called "boxing".  Since Generalized Cursor Lifetime is a mouthful we'll refer to
it as "boxing" from here forward. The symmetric operation "unboxing" refers to
converting the boxed object back into a cursor.

The normal cursor usage pattern is by far the most common, a cursor is created
directly with something like these forms:

```sql
cursor C for select * from shape_source;

cursor D for call proc_that_returns_a_shape();
```

At this point the cursor can be used normally as follows:

```sql
loop fetch C
begin
  -- do stuff with C
end;
```

Those are the usual patterns and they allow statement cursors to be consumed
sort of "up" the call chain from where the cursor was created. But what if you
want some worker procedures that consume a cursor? There is no way to pass your
cursor down again with these normal patterns alone.

To generalize the patterns, allowing, for instance, a cursor to be returned as
an out parameter or accepted as an in parameter you first need to declare an
object variable that can hold the cursor and has a type indicating the shape of
the cursor.

To make an object that can hold a cursor:

```sql
declare obj object<T cursor>;
```

Where `T` is the name of a shape. It can be a table name, or a view name, or it
can be the name of the canonical procedure that returns the result.  T should be
some kind of global name, something that could be accessed with `@include` in
various places.  Referring to the examples above, choices for `T` might be
`shape_source` the table or `proc_that_returns_a_shape` the procedure.

>NOTE: A key purpose of the `interface` keyword is to create shapes. e.g.

```sql
interface my_shape (id int!, name text);
```

The declared interface `my_shape` can be used to help define columns, arguments,
etc. Anywhere a shape goes.

To create the boxed cursor, first declare the object variable that will hold it
and then set the object from the cursor.  Note that in the following example the
cursor `C` must have the shape defined by `my_shape` or an error is produced.
The type of the object is crucial because, as we'll see, during unboxing that
type defines the shape of the unboxed cursor.


```sql
-- recap: declare the box that holds the cursor (T changed to my_shape for this example)
declare box_obj object<my_shape cursor>;

-- box the cursor into the object (the cursor shape must match the box shape)
set box_obj from cursor C;
```

The variable `box_obj` can now be passed around as usual.  It could be
stored in a suitable `out` variable or it could be passed to a procedure
as an `in` parameter.  Then, later, you can "unbox" `box_obj` to get a
cursor back. Like so:

```sql
-- unboxing a cursor from an object, the type of box_obj defines the type
-- of the created cursor
cursor D for box_obj;
```

These primitives allow cursors to be passed around with general purpose lifetime.

Example:

```sql
-- consumes a cursor
proc cursor_user(box_obj object<my_shape cursor>)
begin
  -- the cursors shape will be my_shape, matching box_obj
  cursor C for box_obj;
  loop fetch C
  begin
    -- do something with C
  end;
end;

-- captures a cursor and passes it on
proc cursor_boxer()
begin
  cursor C for select * from something_like_my_shape;
  declare box_obj object<my_shape cursor>
  set box from cursor C; -- produces error if shape doesn't match
  call cursor_user(box_obj);
end;
```

Importantly, once you box a cursor the underlying SQLite statement’s lifetime is
managed by the box object with normal retain/release semantics.  The box and
underlying statement can be released simply by setting all references to it to
null as usual.

With this pattern it's possible to, for instance, create a cursor, box it,
consume some of the rows in one procedure, do some other stuff, and then consume
the rest of the rows in another different procedure.

Important Notes:

* the underlying SQLite statement is shared by all references to it.  Unboxing
  does not reset the cursor's position.  It is possible, even desirable, to have
  different procedures advancing the same cursor
* there is no operation for "peeking" at a cursor without advancing it; if your
  code requires that you inspect the row and then delegate it, you can do this
  simply by passing the cursor data as a value rather than the cursor statement.
  Boxing and unboxing are for cases where you need to stream data out of the
  cursor in helper procedures
* durably storing a boxed cursor (e.g. in a global) could lead to all manner of
  problems -- it SQLite terms is *exactly* like holding on to a `sqlite3_stmt *`
  for a long time with all the same problems, because that is exactly is
  happening

Summarizing, the main reason for using the boxing patterns is to allow for
standard helper procedures that can get a cursor from a variety of places and
process it.  Boxing isn’t the usual pattern at all and returning cursors in a
box, while possible, should be avoided in favor of the simpler patterns, if only
because then then lifetime management is very simple in all those cases.

### Advanced Shape Usage

There are a number of ways that shapes can be used creatively given their
sources. A few examples should illustrate what is possible.

Let's suppose we want to write code to call a function with test arguments,
there are dozens of combos so we might do something like this.

```sql
cursor C for select * from test_args;
loop fetch C
begin
  let ok := foo(from C);
  if not x throw;
end;
```

OK that's fair enough but how did we make that table?

```sql

-- example
proc foo(x int, y int, out result int)
begin
  result := x + y;
end;

-- all of the columns of the arguments but not the out arg result
create table test_args(
  like foo arguments(-result)
);
```

In a test case we might want to use default values for many of the
arguments and vary just one or two.  We could do something like this:

```sql
proc foo_defaults()
begin
  -- here we let the result column be part of the cursor
  -- it wil hold the result when the call is made
  -- we could omit it like the previous example
  cursor C like foo arguments;
  -- @dummy_seed could also be used
  fetch C from values (... defaults ...);
  out C;
end;
```

now we could do

```sql
cursor C fetch from call foo_defaults();
call foo(from C);
-- test C.result
```

If we wanted to change some of the defaults for our test (procedures might have
many arguments) we can change it up a bit

```sql
proc foo_args_case1(x_ int)
begin
  cursor C like foo arguments;
  fetch C from call foo_defaults();

  -- change some columns
  update cursor C using x_ x;
  out C;
end;

cursor C fetch from call foo_args_case1(5);
call foo(from C);
-- test C.result
```

Many such combinations are possible and this can materially reduce the test burden.
Remember any of the columns of a value cursor can come from anywhere, they could
be computed, stored or any combination.  Result could include arguments for
more than one function as long as each unique argument has a unique shape.
For instance:

```sql
-- foo and bar share some arguments (or not)

-- pull just the arguments for foo out of C which has foo and bar args
call foo(from C like foo arguments);

-- pull just the arguments for bar out of C which has foo and bar args
call bar(from C like bar arguments);
```

All sorts of combinations like this are possible.  Forwarding your own
arguments to helper functions can be massively simplified using these
forms.

```sql
-- call bar using my arguments, pass the ones that match
call bar(from arguments like bar arguments);

-- call bar using my arguments and locals, pass the ones that match
call bar(from locals like bar arguments);
```

I can easily create a procedure that gets some input state, assembles
the arguments to call various helper procedures, and calls them all.
If the state is common I can easily flow the argument values each
helper needs from my locals without having to type them all the time.
If a helper needs one of the usual context locals it can be added
to the signature of the helper and it will be automatically populated
at the call sites without having to change code.  This sort of thing
happens all the time in test code.

The `from` form can be used for call arguments, inserted values, cursor
fetch values -- the usual places expression lists go.  The `like` form
can go anywhere column names go, like the columns of an `insert` statement,
the columns in a `create table` statement, an `interface`.  Anywhere
typed names like `(x int, y int)` could go.


