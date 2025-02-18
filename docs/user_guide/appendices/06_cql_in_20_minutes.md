---
title: "Appendix 6: CQL In 20 Minutes"
weight: 6
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

What follows is a series of examples intended to illustrate the most important features of
the CQL language. This appendix was significantly influenced by a similar article on Python
at https://learnxinyminutes.com/docs/python/

Also of interest:
* http://sqlite.org
* https://learnxinyminutes.com/docs/sql

And with no further delay, CQL in 20 minutes...

```
-- Single line comments start with two dashes

/* C style comments also work
 *
 * C pre-processor features like #include and #define are generally available
 * CQL is typically run through the C pre-processor before it is compile.
 */
```

### 1. Primitive Datatypes and Operators


```
-- You have numbers
3     -- an integer
3L    -- a long integer
3.5   -- a real literal
0x10  -- 16 in hex

-- Math is what you would expect
1 + 1     --> 2
8 - 1     --> 7
10 * 2    --> 20
35.0 / 5  --> 7.0

-- Modulo operation, same as C and SQLite
7 % 3    --> 1
-7 % 3   --> -1
7 % -3   --> 1
-7 % 3   --> -1

-- Bitwise operators bind left to right like in SQLite not like in C
1 | 4 & 3  -->  1  (not 0)

-- Enforce precedence with parentheses
1 + 3 * 2    --> 7
(1 + 3) * 2  --> 8

-- Use true and false for bools, nullable bool is possible
true    --> how to true
false   --> how to false
null    --> null means "unknown" in CQL like SQLite

-- Negate with not
not true   --> false
not false  --> true
not null   --> null (not unknown is unknown)

-- Logical Operators
1 and 0 --> 0
0 or 1  --> 1
0 and x --> 0 and x not evaluated
1 or x  --> 1 and x not evaluated

-- Remember null is "unknown"
null or false  --> null
null or true   --> true
null and false --> false
null and true  --> null

-- Non-zero values are truthy
0        --> false
4        --> true
-6       --> true
0 and 2  --> 0 (false)
-5 or 0  --> 1 (true)

-- Equality is == or =
1 == 1       --> true
1 = 1        --> true  (= and == are the same thing)
2 == 1       --> false

-- Note that null is not equal to anything (like SQL)
null == 1    --> null (hence not true)
null == null --> null (hence not true)
"x" == "x"   --> true

-- IS lets you compare against null
1 IS 1       --> true
2 IS 1       --> false
null IS 1    --> false
null IS null --> true  (Unknown is Unknown?  Yes it is!)
"x" IS "x"   --> true

-- x IS NOT y is the same as NOT (x IS y)
1 IS NOT 1       --> false
2 IS NOT 1       --> true
null IS NOT 1    --> true
null IS NOT null --> false
"x" IS NOT "x"   --> false

-- Inequality is != or <>
1 != 1       --> false
2 <> 1       --> true
null != 1    --> null
null <> null --> null

-- More comparisons
1 < 10    --> true
1 > 10    --> false
2 <= 2    --> true
2 >= 2    --> true
10 < null --> null

-- To test if a value is in a range
1 < 2 and 2 < 3  --> true
2 < 3 and 3 < 2  --> false

-- BETWEEN makes this look nicer
2 between 1 and 3 --> true
3 between 2 and 2 --> false

-- Strings are created with "x" or 'x'
"This is a string.\n"           -- can have C style escapes (no embedded nulls)
"Th\x69s is a string.\n"        -- even hex literals
'This isn''t a C style string'  -- use '' to escape single quote ONLY
```


### 2. Simple Variables

CQL can call simple libc methods with a no-check declaration
we'll need this for later examples so we can do something
with our expressions (i.e. print them)

```
declare procedure printf no check;  -- any args

call printf("I'm CQL. Nice to meet you!\n");

-- or simply

printf("I'm CQL. Nice to meet you!\n");
```

Variables are declared with VAR. Keywords and identifiers are not case sensitive.

```
var x int!;  -- ! means 'not null'

-- You can call it X, it is the same thing.
X := 0;
```

All variables begin with a null value if allowed, else a zero value.

```
var y int!;
if y == 0 then
  printf("Yes, this will run.\n");
end if;
```

A nullable variable (i.e. not marked with not null) is initialized to null

```
var z real;
if z is null then
  printf("Yes, this will run.\n");
end if;
```

The various types are:

```
var a_blob blob;
var a_string text;
var a_real real;
var an_int integer;
var a_long long;
var an_object object;
```

There are some typical SQL synonyms
```
var an_int int;
var a_long long integer;
var a_long long int;
var a_long long_int;
```

The basic types can be tagged to make them less miscible

```
var m real<meters>;
var kg real<kilos>;

m := kg;  -- error!
```

Object variables can also be tagged so that they are not mixed-up easily

```
var dict object<dict> not null;
var list object<list> not null;

dict := create_dict();  -- an external function that creates a dict
dict := create_list();  -- error
list := create_list();  -- ok
list := dict;           -- error
```

Use LET for implied declaration and initialization

```
let i := 1;      -- int!
let l := 1L;     -- long!
let t := "x";    -- text!
let b := x IS y; -- bool!
let b := x = y;  -- bool (maybe not null depending on x/y)
```

The psuedo function "nullable" converts the type of its arg to the nullable
 version of the same thing.

```
let n_i := nullable(1);   -- nullable integer variable initialized to 1
let l_i := nullable(1L);  -- nullable long variable initialized to 1
```

Most operators have a side-effect assignment version

```
i += 1;
i *= 2;
```


### 3. Control Flow

Here is an IF statement
```
let some_var := 5
if some_var > 10 then
    printf("some_var is totally bigger than 10.\n")
else if some_var < 10 then  -- else if is optional
    printf("some_var is smaller than 10.\n")
else -- else is optional
    printf("some_var is indeed 10.\n")
end if;
```

WHILE loops iterate as usual.

```
let i := 0;
while i < 5
begin
   printf("%d\n", i);
   i += 1;
end;
```

Use LEAVE to end a loop early

```
let i := 0;
while i < 500
begin
   if i >= 5 then
     -- we are not going to get anywhere near 500
     leave;
   end if;

   printf("%d\n", i);
   i += 1;
end;
```

Use CONTINUE to go back to the loop test
```
let i := 0;
while i < 500
begin
   i += 1;
   if i % 2 then
     -- Note: we to do this after "i" is incremented!
     -- to avoid an infinite loop
     continue;
   end if;

   -- odd numbers will not be printed because of continue above
   printf("%d\n", i);
end;
```

Use FOR to do normal iteration, any number of update statements
may come after the condition.  They need not be +=, they can be anything

```
let i := 0;
let j := 0;
for i < 500; i += 1; j += 2;
begin
  printf("%d %d\n", i, j);
end;
```


### 4. Complex Expression Forms

Case is an expression, so it is more like the C "?:" operator
than a switch statement.  It is like "?:" on steroids.

```
 case i              -- a switch expression is optional
   when 1 then "one" -- one or more cases
   when 2 then "two"
   else "other"      -- else is optional
 end;
```

Case with no common expression is a series of independent tests

```
case
   when i == 1 then "i = one"   -- booleans could be completely unrelated
   when j == 2 then "j = two"   -- first match wins
   else "other"
end;
```

If nothing matches the cases, the result is null.
The following expression yields null because 7 is not 1.

```
case 7 when 1 then "one" end
```

Case is just an expression, so it can nest:

```
case X
  when 1
    case y
      when 1 "x:1 y:1"
      else "x:1 y:other"
    end
  else
    case
      when z == 1 "x:other z:1"
      else "x:other z:other"
    end
end;
```

IN is used to test for membership

```
5 IN (1, 2, 3, 4, 5)  --> true
7 IN (1, 2)           --> false
null in (1, 2, 3)     --> null
null in (1, null, 3)  --> null  (null == null is not true)
7 NOT IN (1, 2)       --> true
null not in (null, 3) --> null
```


### 5. Working with and "getting rid of" null


Null can be annoying, you might need a not null value.
In most operations null is "radioactive":

```
null + x     --> null
null * x     --> null
null == null --> null
```

IS and IS NOT always return 0 or 1

```
null is 1     -> 0
1 is not null -> 1
```

COALESCE returns the first non null arg, or the last arg if all were null.
If the last arg is not null, you get a non null result for sure.
The following is never null, but it's false if either x or y is null

```
coalesce(x==y, false) -> thought excercise: how is this different than x IS y?
```

IFNULL is coalesce with 2 args only (COALESCE is more general)

```
ifnull(x, -1) --> use -1 if x is null
```

The reverse, NULLIF, converts a sentinel value to unknown, this is more exotic

```
nullif(x, -1) --> if x is -1 then use null
```

the ELSE part of a CASE can get rid of nulls

```
case when x == y then 1 else 0 end;  --> true iff x = y and neither is null

-- equivalent to the above
ifnull(x == y, 0)
```

CASE can be used to give you a default value after various tests
The following expression is never null; "other" is returned if x is null.f

```
case when x > 0 then "pos" when x < 0 then "neg" else "other" end;
```

You can "throw" out of the current procedure (see exceptions below)

```
var x int!;
x := ifnull_throw(nullable_int_expr); -- returns non null, throws if null
```

If you have already tested the expression then control flow analysis
improves its type to "not null".  Many common check patterns are recognized.

```
if nullable_int_expr is not null then
  -- nullable_int_expression is known to be not null in this context
  x := nullable_int_expr;
end if;
```


### 6. Tables, Views, Indices, Triggers

Most forms of data definition language DDL are supported.
"Loose" DDL (outside of any procedure) simply declares
schema, it does not actually create it; the schema is assumed to
exist as you specified.

```
create table sample_table(
  id integer primary key,
  t text,
  r real
);

create table other_table(
  id integer primary key references sample_table(id),
  l long,
  b blob
);
```

CQL can take a series of schema declarations (DDL) and
automatically create a procedure that will materialize
that schema and even upgrade previous versions of the schema.
This system is discussed in Chapter 10 of The Guide.
To actually create tables and other schema you need
procedures that look like the below:

```
proc make_tables()
begin
  -- this is not just a declaration, it will actually create the table
  create table sample_table if not exists (
    id integer primary key,
    t text,
    r real
  );
end;
```

Views are supported

```
create view V1 as (select * from sample_table);
```

Triggers are supported

```
create trigger if not exists trigger1
  before delete on sample_table
begin
  delete from other_table where id = old.id;
end;
```

Indices are supported

```
create index I1 on sample_table(t);
create index I2 on sample_table(r);
```

The various drop forms are supported

```
drop index I1;
drop index I2;
drop view V1;
drop table other_table;
drop table sample_table;
drop trigger trigger1;
```

A complete discussion of DDL is out of scope, refer to sqlite.org

### 7. Selecting Data

 We will use this scratch variable in the following examples

```
var rr real;
```

First observe CQL is a two-headed language

```
rr := 1+1;           -- this is evaluated in generated C or Lua code
rr := (select 1+1);  -- this expresion goes to SQLite; SQLite does the addition
```

CQL tries to do most things the same as SQLite in the C context
but some things are exceedingly hard to emulate correctly.
Even simple looking things such as:

```
rr := (select cast("1.23" as real));   -->  rr := 1.23
rr := cast("1.23" as real);            -->  error (not safe to emulate SQLite)
```

In general, numeric/text conversions have to happen in SQLite context because
the specific library that does the conversion could be and usually is different
than the one CQL would use.  It would not do to give different answers in one
context or another so those conversions are simply not supported.

Loose concatenation is not supported because of the implied conversions. Loose
means "not in the context of a SQL statement".

```
r := 1.23;
r := (select cast("100"||r as real));  --> 1001.23 (a number)
r := cast("100"||r as real);  --> error, concat not supported in loose expr
```

A simple insertion
```
insert into sample_table values (1, "foo", 3.14);
```
Finally, reading from the database

```
r := (select r from sample_table where id = 1);  --> r = 3.14
```

The (select ...) form requires the result to have at least one row. You can use
IF NOTHING forms to handle other cases such as:
```
r := (select r from sample_table
        where id = 2
        if nothing -1);  --> r = -1
```

If the SELECT statement might return a null result you can handle that as well

```
r := (select r from sample_table
      where id = 2
      if nothing or null -1);  --> r = -1
```

With no IF NOTHING clause, lack of a row will cause the SELECT expression to
throw an exception.  IF NOTHING THROW merely makes this explicit.

```
r := (select r from sample_table where id = 2 if nothing throw);  --> will throw
```

### 8. Procedures, Results, Exceptions

Procedures are a list of statements that can be executed, with arguments.

```
proc hello()
begin
  printf("Hello, world\n");
end;
```

IN, OUT, and INOUT parameters are possible

```
proc swizzle(x integer, inout y integer, out z real not null)
begin
  set y := x + y;  -- any computation you like

  -- bizarre way to compute an id but this is just an illustration
  set z := (select r from sample_table where id = x if nothing or null -1);
end;
```

Procedures like "hello" (above) have a void signature -- they return nothing as
nothing can go wrong. Procedures that use the database like "swizzle" (above)
can return an error code if there is a problem. "will_fail" (below)  will always
return SQLITE_CONSTRAINT, the second insert is said to "throw".  In CQL
exceptions are just result codes that flow back up the stack.

```
proc will_fail()
begin
   insert into sample_table values (1, "x", 1);
   insert into sample_table values (1, "x", 1);  --> duplicate key
end;
```

DML that fails generates an exception and
exceptions can be caught. Here is a example:

```
proc upsert_sample_table(
  id_ integer primary key,
  t_ text,
  r_ real)
begin
  try
    -- try to insert
    insert into sample_table(id, t, r) values (id_, t_, r_);
  catch
    -- if the insert fails, try to update
    update sample_table set t = t_, r = r_ where id = id_;
  end;
end;
```

Shapes can be very useful in avoiding boilerplate code the following is
equivalent to the above. More on shapes later.

```
-- my args are the same as the columns of sample_table
-- with a trailing _ in the name
proc upsert_sample_table(LIKE sample_table)
begin
  try
    insert into sample_table from arguments
  catch
    update sample_table set t = t_, r = r_ where id = id_;
  end;
end;
```

You can (re)throw an error explicitly. If there is no current error you get
SQLITE_ERROR THROW, CONTINUE, LEAVE, and RETURN may be used without begin/end in
an IF

```
-- my args are the same as the columns of sample_table
proc upsert_wrapper(LIKE sample_table)
begin
  if r_ > 10 throw; -- throw if r_ is too big
  upsert_sample_table(from arguments);
end;
```

Procedures can also produce a result set. The compiler generates the code to
create this result set and helper functions to read rows out of it.

```
-- get anything less than r_ from sample_table
proc get_low_r(r_ real)
begin
   -- optionally insert some rows or do other things
   select * from sample_table where sample_table.r <= r_;
end;
```

A procedure can choose between various results, the choices must be compatible.
The last "select" to run controls the ultimate result.

```
proc get_hi_or_low(r_ real, hi_not_low bool!)
begin
  -- trying to do this with one query would result in a poor plan, so
  -- instead we use two economical queries.
  if hi_not_low then
    select * from sample_table where sample_table.r >= r_;
  else
    select * from sample_table where sample_table.r <= r_;
  end if;
end;
```

Using IF to create to nice selects above is a powerful thing.
SQLite has no IF, if we tried to create a shared query we get
something that does not use indices at all.  As in the below.
The two-headed CQL beast has its advantages!

```
select * from sample_table
  where
    case hi_not_low then sample_table.r >= r_
    else sample_table.r <= r_
  end;
```

You can get the current return code and use it in your CATCH logic.
This upsert is a bit better than the first:

```
-- my args are the same as the columns of sample_table
proc upsert_sample_table(LIKE sample_table)
begin
  try
    insert into sample_table from arguments
  catch
    if @rc == 19 /* SQLITE_CONSTRAINT */ then
      update sample_table set t = t_, r = r_ where id = id_;
    else
      throw;  -- rethrow, something bad happened.
    end if;
  end;
end;
```

By convention, you can call a procedure that has an OUT argument
as its last argument using function notation.  The out argument
is used as the return value.   If the called procedure uses the
database then it could throw which causes the caller to throw
as usual.

```
proc fib(n int!, out result int!)
begin
  result := case n <= 2 then 1 else fib(n-1) + fib(n-2) end;
end;
```

### 9. Statement Cursors

Statement cursors let you iterate over a select result.
Here we introduce cursors, LOOP and FETCH.

```
proc count_sample_table(r_ real, out rows_ int!)
begin
  rows_ := 0; -- this is redundant, rows_ is set to zero for sure
  cursor C for select * from sample_table where r < r_;
  loop fetch C -- iterate until fetch returns no row
  begin
    -- goofy code to illustrate you can process the cursor
    -- in whatever way you deem appropriate
    if C.r < 5 then
      _rows += 1; -- count rows with C.r < 5
    end if;
  end;
end;
```

Cursors can be tested for presence of a row
and they can be closed before the enumeration is finished.
As before the below is somewhat goofy example code.

```
proc peek_sample_table(r_ real, out rows_ int!)
begin
   /* rows_ is set to zero for sure! */
   cursor C for select * from sample_table where r < r_ limit 2;
   fetch C;  -- fetch might find a row or not
   if C then  -- cursor name as bool indicates presence of a row
     rows_ += C.r < 5;
     fetch C;
     rows_ += (C and C.r < 5);
   end if;
   close C;  -- cursors auto-closed at end of method but early close possible
end;
```

The FETCH...INTO form can be used to fetch directly into variables
```
fetch C into id_, t_, r_;  --> loads named locals instead of C.id, C.t, C.r
```

A procedure can be the source of a cursor, the cursor has the shape of the
whatever result set the procedure returns.

```
cursor C for call get_low_r(3.2);  -- valid cursor source
```

OUT can be used to create a result set that is just one row

```
proc one_sample_table(r_ real)
begin
   cursor C for select * from sample_table where r < r_ limit 1;
   fetch C;
   out C;  -- emits a row if we have one, no row is ok too, empty result set.
end;
```

### 10. Value Cursors, Out, and Out Union

To consume a procedure that uses "out" you can declare a value cursor.
By itself such as cursor does not imply use of the database, but often
the source of the cursor uses the database.  In this example
consume_one_sample_table uses the database because of the call to one_sample_table.

```
proc consume_one_sample_table()
begin
  -- a cursor whose shape matches the one_sample_table "out" statement
  cursor C like one_sample_table;

  -- load it from the call
  fetch C from call one_sample_table(7);
  if C.r > 10 then
    -- use values as you see fit
    printf("woohoo");
  end if;
end;
```

You can do the above in one step with the compound form:
```
cursor C fetch from call one_sample_table(7); -- declare and fetch
```

Value cursors can come from anywhere and can be a procedure result

```
proc use_sample_table_a_lot()
begin
  -- sample_table is the same shape as one_sample_table, this will work, too
  cursor C like sample_table;
  fetch C from call one_sample_table(7);  -- load it from the call

  -- some arbitrary logic might be here

  -- load C again with different args
  fetch C from call one_sample_table(12); -- load it again

  -- some arbitrary logic might be here

  -- now load C yet again with explicit args
  fetch C using
     1 id,
     "foo" t,
     8.2 r;

  -- now return it
  out C;
end;
```

Here we make a complex result set one row at a time

```
proc out_union_example()
begin
  -- sample_table is the same shape as one_sample_table, this will work, too
  cursor C like sample_table;

  -- load it from the call
  fetch C from call one_sample_table(7);

  -- note out UNION rather than just out, indicating potentially many rows
  out union C;

  -- load it again with different args
  fetch C from call one_sample_table(12);
  out union C;

  -- do something, then maybe load it again with explicit args
  fetch C using
     1 id,
     "foo" t,
     8.2 r;
  out union C;

  -- we have generated a 3 row result set
end;
```

And here we consume the above

```
proc consume_result()
begin
  cursor C for call out_union_example();
  loop fetch C
  begin
    -- use builtin cql_cursor_format to make the cursor into a string
    printf("%s\n", cql_cursor_format(C)); --> prints every column and value
  end;
end;
```


### 11. Named Types and Enumerations

Create a simple named types using `type`

```
type my_type int!;   -- make an alias for int!
var i my_type;  -- use it, "i" is an integer
```

Mixing in type kinds can be helpful

```
type distance real<meters>;  -- e.g., distances to be measured in meters
type time real<seconds>;     -- e.g., time to be measured in seconds
tppe job_id long<job_id>;
type person_id long<person_id>;
```

With the above done
  * vars/cols of type "distance" are incompatible with those of type "time"
  * vars/cols of types job_id are incompatible with person_id

This is true even though the underlying type is the same for both!

ENUM declarations can have any numeric type as their base type

```
declare enum implement integer (
   pencil,       -- values start at 1 unless you use = to choose something
   pen,          -- the next enum gets previous + 1 as its value (2)
   brush = 7     -- with = expression you get the indicated value
);
```

The above also implicitly does this

```
type implement integer<implement>!;  -- not needed
```

Using the enum -- simply use dot notation

```
let impl := implement.pen;  -- value 2
```

You can emit an emum into the current .h file we are going to generate (or .lua).
Do not put this directive in an include file, you want it to go to one place.
Instead, pick one compiland that will "own" the emission of the enum.
C code can then #include the one .h file.  Lua code gets to use the constansts
to initialize a dictionary.

```
@emit_enums implement;
```

### 12. Shapes and Their Uses

Shapes first appeared to help define value cursors like so:

A table or view name defines a shape

```
cursor C like sample_table;
```

The result of a proc defines a shape
```
cursor D like one_sample_table;
```

A dummy select statement defines a shape (the select does not run)
this one is the same as (x int!, y text!)

```
cursor E like select 1 x, "2" y;
cursor E like (x int!, y text!) -- equivalent
```

Another cursor defines a shape

```
declare F cursor like C;
```

The arguments of a procedure define a shape. If you have
`proc count_sample_table(r_ real, out rows_ int!) ...`
the shape will be `(r_ real, rows_ int!)`

```
cursor G like count_sample_table arguments;
```

A loaded cursor can be used to make a call

```
count_sample_table(from G);  -- the args become G.r_, G.rows_
```

A shape can be used to define a procedures args, or some of the args
In the following "p" will have arguments:s id_, t_, and r_ with types
matching table sample_table.
Note: To avoid ambiguity, an _ was added to each name!

```
proc p(like sample_table)
begin
  -- do whatever you like
end;
```

The arguments of the current procedure are a synthetic shape
called "arguments" and can used where other shapes can appear.
For instance, you can have "q" shim to "p" using this form:

```
proc q(like sample_table, print bool not null)
begin
  -- maybe pre-process, silly example
  id_ += 1;

  -- shim to p
  p(from arguments); -- pass my args through, whatever they are

  -- maybe post-process, silly example
  r_ -= 1;

  if print then
    -- convert args to cursor
    cursor C like q arguments;
    fetch C from arguments;
    printf("%s\n", cql_cursor_format(C)); --> prints every column and value
  end if;

  -- insert a row based on the args
  insert into sample_table from arguments;
end;
```

You an use a given shape more than once if you name each use.
This would be more exciting if sample_table was like a "person" or something.

```
proc r(a like sample_table, b like sample_table)
begin
  call p(from a);
  call p(from b);
  -- you can refer to a.id, b.id etc.
  cursor C like a;
  fetch C from a;
  printf("%s\n", cql_cursor_format(C));
  fetch C from b;
  printf("%s\n", cql_cursor_format(C));
end;
```

Shapes can be subsetted, for instance in the following example
only the arguments that match C are used in the FETCH.

```
fetch C from arguments(like C);
```

Fetch the columns of D into C using the cursor D for the data source.
Other columns get default values.

```
fetch C(like D) from D;
```

Use the D shape to load C, dummy values for the others.
In this example, dummy_seed means use the provided value, 11, for
any numerics that are not specified (not in D) and and use
"col_name_11" for any strings/blobs.  This pattern is useful in test code
to create dummy data, hence the name.

```
fetch C(like D) from D @dummy_seed(11);
```

Use the Z shape to control which fields are copied.
Use the dummy value even if the field is nullable and null would have be ok.

```
fetch C(like Z) from D(like Z) @dummy_seed(11) @dummy_nullables;
```

The above patterns also work for insert statements
The shape constraints are generally useful.  The dummy data
sources are useful for inserting test data.

```
insert into sample_table(like Z) from D(like Z) @dummy_seed(11) @dummy_nullables;
```

We can make a named shape with `interface`.

```
interface some_shape (x int!, y int!, z int!);
```

You can make a helper procedure to create test args that are mostly constant
or computable.f

```
create get_foo_args(X like some_shape, seed_ int!)
begin
  cursor C like foo arguments;
  -- any way of loading C could work this is one
  fetch C(like X) from X @dummy_seed(seed_);
  out C;
end;
```

Now we can use the "get_foo_args" to get full set of arguments for "foo" and
then call "foo" with those arguments.  In this example we're providing some of
the arguments explicitly, "some_shape" is the part of the args that needs to
manually vary in each test iteration, the rest of the arguments will be dummy
values.  There could be zillions of args in either category. In the below
"some_shape" is going to get the manual values 1, 2, 3 while 100 will be the
seed for the dummy args.

```
-- provide some foo args and let the rest be computed by get_foo_args
cursor foo_args fetch from call get_foo_args(1, 2, 3, 100);

-- now use the args, very useful for generating test variations
call foo(from foo_args);
```


### 13. The USING clause for INSERT and FETCH

This kind of thing is error prone:

```
-- which variable is getting '5', are you sure it's 'f', you have to read
-- carefully... it gets worse if there are more columns with longer names

insert into foo(a, b, c, d, e, f, g)
  values(1, 2, 3, null, null, 5, null);
```

Instead, write with the USING form:

```
-- this is sugar, it generates the above but you can't get the fields wrong
insert into foo using
  1 a, 2 b, 3 c, null d, null e, 5 f, null g;
```

The FETCH statement can also be "fetch using"
```
cursor C like foo;
fetch C using
    1 a, 2 b, 3 c, null d, null e, 5 f, null g;
```


### 14. Pipeline Forms

Borrowing from Lua, it is possible to invoke functions using a postfix notation.

```
select x:ifnull(0) x;
```

The above is exactly the same as:

```
select ifnull(x, 0) x;
```

The postfix form is often much more convenient and clear to write and
it chains more naturally to create fluent forms.

The CAST operator may also be written in a postfix form using `~type~`.  Special
syntax is required for type casts because types can be tricky.  `~real<meters> not null~`
is a valid type for instance.  A simple example might look like this.

```
select x:substr(2)~int~:ifnull(0) x;
```

Which is much clearer than:

```
select ifnull(cast(substr(x, 2) as int), 0) x;
```

Shorter function alaises may also be used, the `@op` directive defines aliases,
this is common to allow overloaded names.

```
@op real<meters> call dist as metric_distance;

x:dist -- becomes  metric_distance(x) if x is of type real<meters>
```

This notation can be quite useful, for instance the builtin `fmt` is defined for
all types such that `x:fmt` renders x into some debug string regardless of what `x`
is by calling a suitable format function (different functions for different types).
`@op` may be used to redefine/override the expansion as many times as desired.

Fluent syntax is easily achieved like this:

```
-- makes an object<cql_long_list> with 3 items in it
let l := cql_long_list_create():add(5):add(3):add(2);
```

### 15. Pre-procesing

The below includes the text from the incidated path, these directives must come
before any other statements. Any given path is included only once. Use
`--include_paths` to specify prefixes to use with the `@include` directive.

```
@include "path"
```

Conditional processing can be done at the statement level
use `--defines` to define symbols for use with `@ifdef` and `@ifndef`
`@ifndef` includes the code if the symbol is not defined. The `@else`
directive is optional.

```
@ifdef foo
  -- some code
@else
  -- other code
@endif
```

### 16. Macros

Macros have a form of typing, in that we know what kind of macro we're talking
about and likewise we know the type of any macro argument.  These types are a
piece of syntax which can be understood from the grammar.  The most common type
by far is an expression macro.  Importantly, we know that the macro is an
expression and we know the types of its arguments so we can parse it without
using it thereby finding errors sooner and more clearly.  Syntax errors are not
possible when a macro is invoked, but other errors such as argument mismatch are
possible.  Macro names and arguments alway end in `!`.  Such as `a!`, `b!`, and
`min!`.

```
-- this macro may be used anywhere an expression is valid
@macro(expr) min!(a! expr, b! expr)
begin
  case when a! < b! then a! else b! end
end;

let m := min!(1+2, 3+4);
```

Importantly there is no need to add extra parens like we do in C.  The Macros
are expanded by copying in the AST into the indicated location, not by inserting
text. The AST shape remains as defined so in the above we certainly get (1+2) < (3+4)
no matter what operators were in the macro.

The next most common type of macro is the statement list

```
-- this macro may be used anywhere a statement list is valid
@macro(stmt_list) expect_eq!(x! expr, y! expr)
begin
  let @tmp(x) := x!;
  let @tmp(y) := y!;
  if @tmp(x) != @tmp(y) then
    printf("Assertion failed: %s != %s at %s:%d",
      @TEXT(x!),
      @TEXT(y!),
      @MACRO_FILE,
      @MACRO_LINE);

    printf("left: %s, right %s\n", @tmp(x!):fmt, @tmp(y!):fmt);
    throw;
  end if;
end;
```

Lots is going on here:

* @tmp(x) is a unique name for the macro expansion it turns into something like
  x_12345
* the values were captured into locals so that they are evaluated exactly one
  time
* if the assertion fails we use @TEXT to get a text representation of the
  expressions x and y for the diagnostic
* we use @MACRO_FILE and @MACRO_LINE to get the file and line number of macro
  invocation, the current file and line would be useless
* we use :fmt to get a string represenation of the values of the variables so
  we can show what values we got
* in the event of a failure we use throw to escape from the current procedure
  (other techniques could be used)

This is a big bag of tricks to get a cool macro which is known to accept expressions
and can be used anywhere a statement list could appear.

The other macro types are for important pieces of a select statement.  Something
you can join, something you can union, a piece of a select list.  These are also
useful but come up less often.


### 17. Properties, Arrays, and Custom Operators

Property syntax and array syntax can be converted to function calls using the `@op`
directive.

For instance, these directives are builtin:

```
@op cql_long_list : array set as cql_long_list_set_at;
@op cql_long_list : array get as cql_long_list_get_at;
```

As a result, if `a` and `b` are of type `cql_long_list` (created with `cql_long_list_create`)
Then you can write:

```
a[x] := b[y];

-- equivalent to the following:
cql_long_list_set_at(a, x, cql_long_list_get_at(b, y));
```

Properties can be defined like so:

```
@op cql_long_list : get count as cql_long_list_count;
```

allowing:

```
let c := a.count;

--- equivalent to:
let c := cql_long_list_count(a);
```

Here `count` is a read only property but

```
@op cql_long_list : set length as cql_set_length;
```

Could have been added (it isn't) to set the maximum length like so:

```
a.length := a.count + 5;

--- equivalent
cql_set_length(a, cql_long_list_count(a) + 5);
```

In short, properties and arrays mean whatever you want them to mean.

Finally  "arrow", "lshift", "rshift", "concat" can be used to remap
the `->` `<<` `>>` and `||` operators into functions like so:

```
@op object<storage> lshift int as store_int;

var s object<storage>;
s := get_storage_from_somewhere();
s << 5 << 8 << 12

-- becomes
store_int(store_int(store_int(s, 5), 8), 12);
```

Just as `lshift` remaps `<<`, `rshift` remaps `>>`, `arrow` remaps `->`, and
`concat` remaps `||`. These operators then mean whatever you want them to mean.
They are used whenver the operands match and can generate type mismatch errors
as usual.

If you've read this far you know more than most now.  :)
