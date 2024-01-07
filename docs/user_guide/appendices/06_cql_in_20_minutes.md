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

/**********************************************************
 * 1. Primitive Datatypes and Operators
 *********************************************************/

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

-- Bitwise operators bind left to right like in SQLite
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

/**********************************************************
 * 2. Simple Variables
 *********************************************************/

-- CQL can call simple libc methods with a no-check declaration
-- we'll need this for later examples so we can do something
-- with our expressions (i.e. print them)
declare procedure printf no check;

call printf("I'm CQL. Nice to meet you!\n");

-- Variables are declared with DECLARE.
-- Keywords and identifiers are not case sensitive.
declare x integer not null;

-- You can call it X, it is the same thing.
set X := 0;

-- All variables begin with a null value if allowed, else a zero value.
declare y integer not null;
if y == 0 then
  call printf("Yes, this will run.\n");
end if;

-- A nullable variable (i.e. not marked with not null) is initialized to null
declare z real;
if z is null then
  call printf("Yes, this will run.\n");
end if;

-- The various types
declare a_blob blob;
declare a_string text;
declare a_real real;
declare an_int integer;
declare a_long long;
declare an_object object;

-- There are some typical SQL synonyms
declare an_int int;
declare a_long long integer;
declare a_long long int;
declare a_long long_int;

-- The basic types can be tagged to make them less miscible
declare m real<meters>;
declare kg real<kilos>;

set m := kg;  -- error!

-- Object variables can also be tagged so that they are not mixed-up easily
declare dict object<dict> not null;
declare list object<list> not null;
set dict := create_dict();  -- an external function that creates a dict
set dict := create_list();  -- error
set list := create_list();  -- ok
set list := dict;           -- error

-- Implied type initialization
LET i := 1;      -- integer not null
LET l := 1L;     -- long not null
LET t := "x";    -- text not null
LET b := x IS y; -- bool not null
LET b := x = y;  -- bool (maybe not null depending on x/y)

-- The psuedo function "nullable" converts the type of its arg to the nullable
-- version of the same thing.

LET n_i := nullable(1);   -- nullable integer variable initialized to 1
LET l_i := nullable(1L);  -- nullable long variable initialized to 1

/**********************************************************
 * 3. Control Flow
 *********************************************************/

-- Just make a variable
declare some_var integer not null;
set some_var := 5

-- Here is an IF statement
if some_var > 10 then
    call printf("some_var is totally bigger than 10.\n")
else if some_var < 10 then  -- else if is optional
    call printf("some_var is smaller than 10.\n")
else -- else is optional
    call printf("some_var is indeed 10.\n")
end if;


-- WHILE loops iterate as usual
declare i integer not null;
set i := 0;
while i < 5
begin
   call printf("%d\n", i);
   set i := i + 1;
end;

-- Use LEAVE to end a loop early
declare i integer not null;
set i := 0;
while i < 500
begin
   if i >= 5 then
     -- we are not going to get anywhere near 500
     leave;
   end if;

   call printf("%d\n", i);
   set i := i + 1;
end;

-- Use CONTINUE to go back to the loop test
declare i integer not null;
set i := 0;
while i < 500
begin
   set i := i + 1;
   if i % 2 then
     -- Note: we to do this after "i" is incremented!
     -- to avoid an infinite loop
     continue;
   end if;

   -- odd numbers will not be printed because of continue above
   call printf("%d\n", i);
end;

 /**********************************************************
 * 4. Complex Expression Forms
 *********************************************************/

 -- Case is an expression, so it is more like the C "?:" operator
 -- than a switch statement.  It is like "?:" on steroids.

 case i              -- a switch expression is optional
   when 1 then "one" -- one or more cases
   when 2 then "two"
   else "other"      -- else is optional
 end;

-- Case with no common expression is a series of independent tests
case
   when i == 1 then "i = one"   -- booleans could be completely unrelated
   when j == 2 then "j = two"   -- first match wins
   else "other"
end;

-- If nothing matches the cases, the result is null.
-- The following expression yields null because 7 is not 1.
case 7 when 1 then "one" end


-- Case is just an expression, so it can nest
case X
  when 1
    case y when 1 "x:1 y:1"
           else "x:1 y:other"
    end
  else
    case when z == 1 "x:other z:1"
         else "x:other z:other"
    end
end;

-- IN is used to test for membership
5 IN (1, 2, 3, 4, 5)  --> true
7 IN (1, 2)           --> false
null in (1, 2, 3)     --> null
null in (1, null, 3)  --> null  (null == null is not true)
7 NOT IN (1, 2)       --> true
null not in (null, 3) --> null

/**********************************************************
 * 4. Working with and "getting rid of" null
 *********************************************************/

-- Null can be annoying, you might need a not null value.
-- In most operations null is radioactive:
null + x     --> null
null * x     --> null
null == null --> null

-- IS and IS NOT always return 0 or 1
null is 1     -> 0
1 is not null -> 1

-- COALESCE returns the first non null arg, or the last arg if all were null.
-- If the last arg is not null, you get a non null result for sure.
-- The following is never null, but it's false if either x or y is null
COALESCE(x==y, false) -> thought excercise: how is this different than x IS y?

-- IFNULL is coalesce with 2 args only (COALESCE is more general)
IFNULL(x, -1) --> use -1 if x is null

-- The reverse, NULLIF, converts a sentinel value to unknown, more exotic
NULLIF(x, -1) --> if x is -1 then use null

-- the else part of a case can get rid of nulls
CASE when x == y then 1 else 0 end;  --> true iff x = y and neither is null

-- CASE can be used to give you a default value after various tests
-- The following expression is never null; "other" is returned if x is null.
CASE when x > 0 then "pos" when x < 0 then "neg" else "other" end;

-- You can "throw" out of the current procedure (see exceptions below)
declare x integer not null;
set x := ifnull_throw(nullable_int_expr); -- returns non null, throws if null

-- If you have already tested the expression then control flow analysis
-- improves its type to "not null".  Many common check patterns are recognized.
if nullable_int_expr is not null then
  -- nullable_int_expression is known to be not null in this context
  set x := nullable_int_expr;
end if;

/**********************************************************
 * 5. Tables, Views, Indices, Triggers
 *********************************************************/

-- Most forms of data definition language DDL are supported.
-- "Loose" DDL (outside of any procedure) simply declares
-- schema, it does not actually create it; the schema is assumed to
-- exist as you specified.

create table T1(
  id integer primary key,
  t text,
  r real
);

create table T2(
  id integer primary key references T1(id),
  l long,
  b blob
);

-- CQL can take a series of schema declarations (DDL) and
-- automatically create a procedure that will materialize
-- that schema and even upgrade previous versions of the schema.
-- This system is discussed in Chapter 10 of The Guide.
-- To actually create tables and other schema you need
-- procedures that look like the below:

create proc make_tables()
begin
  create table T1 if not exists (
    id integer primary key,
    t text,
    r real
  );
end;

-- Views are supported
create view V1 as (select * from T1);

-- Triggers are supported
create trigger if not exists trigger1
  before delete on T1
begin
  delete from T2 where id = old.id;
end;

-- Indices are supported
create index I1 on T1(t);
create index I2 on T1(r);

-- The various drop forms are supported
drop index I1;
drop index I2;
drop view V1;
drop table T2;
drop table T1;

-- A complete discussion of DDL is out of scope, refer to sqlite.org

/**********************************************************
 * 6. Selecting Data
 *********************************************************/

-- We will use this scratch variable in the following examples
declare rr real;

-- First observe CQL is a two-headed language
set rr := 1+1;           -- this is evaluated in generated C code
set rr := (select 1+1);  -- this expresion goes to SQLite; SQLite does the addition

-- CQL tries to do most things the same as SQLite in the C context
-- but some things are exceedingly hard to emulate correctly.
-- Even simple looking things such as:
set rr := (select cast("1.23" as real));   -->  rr := 1.23
set rr := cast("1.23" as real);            -->  error (not safe to emulate SQLite)

-- In general, numeric/text conversions have to happen in SQLite context
-- because the specific library that does the conversion could be and usually
-- is different than the one CQL would use.  It would not do to give different answers
-- in one context or another so those conversions are simply not supported.

-- Loose concatenation is not supported because of the implied conversions.
-- Loose means "not in the context of a SQL statement".
set r := 1.23;
set r := (select cast("100"||r as real));  --> 1001.23 (a number)
set r := cast("100"||r as real);  --> error, concat not supported in loose expr

-- A simple insertion
insert into T1 values (1, "foo", 3.14);

-- Finally, reading from the database
set r := (select r from T1 where id = 1);  --> r = 3.14

-- The (select ...) form requires the result to have at least one row.
-- You can use IF NOTHING forms to handle other cases such as:
set r := (select r from T1
          where id = 2
          if nothing -1);  --> r = -1

-- If the SELECT statement might return a null result you can handle that as well
set r := (select r from T1
          where id = 2
          if nothing or null -1);  --> r = -1

-- With no IF NOTHING clause, lack of a row will cause the SELECT expression to throw
-- an exception.  IF NOTHING THROW merely makes this explicit.
set r := (select r from T1 where id = 2 if nothing throw);  --> will throw

/**********************************************************
 * 6. Procedures, Results, Exceptions
 *********************************************************/

-- Procedures are a list of statements that can be executed, with arguments.
create proc hello()
begin
  call printf("Hello, world\n");
end;

-- IN, OUT, and INOUT parameters are possible
create proc swizzle(x integer, inout y integer, out z real not null)
begin
  set y := x + y;  -- any computation you like

  -- bizarre way to compute an id but this is just an illustration
  set z := (select r from T1 where id = x if nothing or null -1);
end;

-- Procedures like "hello" (above) have a void signature -- they return nothing
-- as nothing can go wrong. Procedures that use the database like "swizzle" (above)
-- can return an error code if there is a problem.
-- "will_fail" (below)  will always return SQLITE_CONSTRAINT, the second insert
-- is said to "throw".  In CQL exceptions are just result codes.
create proc will_fail()
begin
   insert into T1 values (1, "x", 1);
   insert into T1 values (1, "x", 1);  --> duplicate key
end;

-- DML that fails generates an exception and
-- exceptions can be caught. Here is a example:
create proc upsert_t1(
  id_ integer primary key,
  t_ text,
  r_ real
)
begin
  try
    -- try to insert
    insert into T1(id, t, r) values (id_, t_, r_);
  catch
    -- if the insert fails, try to update
    update T1 set t = t_, r = r_ where id = id_;
  end;
end;

-- Shapes can be very useful in avoiding boilerplate code
-- the following is equivalent to the above.
-- More on shapes later.
create proc upsert_t1(LIKE t1) -- my args are the same as the columns of T1
begin
  try
    insert into T1 from arguments
  catch
    update T1 set t = t_, r = r_ where id = id_;
  end;
end;

-- You can (re)throw an error explicitly.
-- If there is no current error you get SQLITE_ERROR
create proc upsert_wrapper(LIKE t1) -- my args are the same as the columns of T1
begin
  if r_ > 10 then throw end if; -- throw if r_ is too big
  call upsert_t1(from arguments);
end;

-- Procedures can also produce a result set.
-- The compiler generates the code to create this result set
-- and helper functions to read rows out of it.
create proc get_low_r(r_ real)
begin
   -- optionally insert some rows or do other things
   select * from T1 where T1.r <= r_;
end;

-- A procedure can choose between various results, the choices must be compatible.
-- The last "select" to run controls the ultimate result.
create proc get_hi_or_low(r_ real, hi_not_low bool not null)
begin
  -- trying to do this with one query would result in a poor plan, so
  -- instead we use two economical queries.
  if hi_not_low then
    select * from T1 where T1.r >= r_;
  else
    select * from T1 where T1.r <= r_;
  end if;
end;

-- Using IF to create to nice selects above is a powerful thing.
-- SQLite has no IF, if we tried to create a shared query we get
-- something that does not use indices at all.  As in the below.
-- The two-headed CQL beast has its advantages!
select * from T1 where case hi_not_low then T1.r >= r_ else T1.r <= r_ end;

-- You can get the current return code and use it in your CATCH logic.
-- This upsert is a bit better than the first:
create proc upsert_t1(LIKE t1) -- my args are the same as the columns of T1
begin
  try
    insert into T1 from arguments
  catch
    if @rc == 19 /* SQLITE_CONSTRAINT */ then
      update T1 set t = t_, r = r_ where id = id_;
    else
      throw;  -- rethrow, something bad happened.
    end if;
  end;
end;

-- By convention, you can call a procedure that has an OUT argument
-- as its last argument using function notation.  The out argument
-- is used as the return value.   If the called procedure uses the
-- database then it could throw which causes the caller to throw
-- as usual.
create proc fib(n integer not null, out result integer not null)
begin
   set result := case n <= 2 then 1 else fib(n-1) + fib(n-2) end;
end;

/**********************************************************
 * 7. Statement Cursors
 *********************************************************/

-- Statement cursors let you iterate over a select result.
-- Here we introduce cursors, LOOP and FETCH.
create proc count_t1(r_ real, out rows_ integer not null)
begin
  declare rows integer not null;  -- starts at zero guaranteed
  declare C cursor for select * from T1 where r < r_;
  loop fetch C -- iterate until fetch returns no row
  begin
    -- goofy code to illustrate you can process the cursor
    -- in whatever way you deem appropriate
    if C.r < 5 then
      rows := rows + 1; -- count rows with C.r < 5
    end if;
  end;
  set rows_ := rows;
end;

-- Cursors can be tested for presence of a row
-- and they can be closed before the enumeration is finished.
-- As before the below is somewhat goofy example code.
create proc peek_t1(r_ real, out rows_ integer not null)
begin
   /* rows_ is set to zero for sure! */
   declare C cursor for select * from T1 where r < r_ limit 2;
   open C;  -- this is no-op, present because other systems have it
   fetch C;  -- fetch might find a row or not
   if C then  -- cursor name as bool indicates presence of a row
     set rows_ = rows_ + (C.r < 5);
     fetch C;
     set rows_ = rows_ + (C and C.r < 5);
   end if;
   close C;  -- cursors auto-closed at end of method but early close possible
end;

-- The FETCH...INTO form can be used to fetch directly into variables
fetch C into id_, t_, r_;  --> loads named locals instead of C.id, C.t, C.r

-- A procedure can be the source of a cursor
declare C cursor for call get_low_r(3.2);  -- valid cursor source

-- OUT can be used to create a result set that is just one row
create proc one_t1(r_ real)
begin
   declare C cursor for select * from T1 where r < r_ limit 1;
   fetch C;
   out C;  -- emits a row if we have one, no row is ok too, empty result set.
end;

/**********************************************************
 * 8. Value Cursors, Out, and Out Union
 *********************************************************/

-- To consume a procedure that uses "out" you can declare a value cursor.
-- By itself such as cursor does not imply use of the database, but often
-- the source of the cursor uses the database.  In this example
-- consume_one_t1 uses the database because of the call to one_t1.
create proc consume_one_t1()
begin
  -- a cursor whose shape matches the one_t1 "out" statement
  declare C cursor like one_t1;

  -- load it from the call
  fetch C from call one_t1(7);
  if C.r > 10 then
    -- use values as you see fit
    call printf("woohoo");
  end if;
end;

-- You can do the above in one step with the compound form:
declare C cursor fetch from call one_t1(7); -- declare and fetch

-- Value cursors can come from anywhere and can be a procedure result
create proc use_t1_a_lot()
begin
  -- T1 is the same shape as one_t1, this will work, too
  declare C cursor like T1;
  fetch C from call one_t1(7);  -- load it from the call

  -- some arbitrary logic might be here

  -- load C again with different args
  fetch C from call one_t1(12);   -- load it again

  -- some arbitrary logic might be here

  -- now load C yet again with explicit args
  fetch C using
     1 id,
     "foo" t,
     8.2 r;

  -- now return it
  out C;
end;

-- Make a complex result set one row at a time
create proc out_union_example()
begin
  -- T1 is the same shape as one_t1, this will work, too
  declare C cursor like T1;

  -- load it from the call
  fetch C from call one_t1(7);

  -- note out UNION rather than just out, indicating potentially many rows
  out union C;

  -- load it again with different args
  fetch C from call one_t1(12);
  out union C;

  -- do something, then maybe load it again with explicit args
  fetch C using
     1 id,
     "foo" t,
     8.2 r;
  out union C;

  -- we have generated a 3 row result set
end;

-- Consume the above
create proc consume_result()
begin
  declare C cursor for call out_union_example();
  loop fetch C
  begin
    -- use builtin cql_cursor_format to make the cursor into a string
    call printf("%s\n", cql_cursor_format(C)); --> prints every column and value
  end;
end;

/**********************************************************
 * 9. Named Types and Enumerations
 *********************************************************/

-- Create a simple named types
declare my_type type integer not null;   -- make an alias for integer not null
declare i my_type;  -- use it, "i" is an integer

-- Mixing in type kinds is helpful
declare distance type real<meters>;  -- e.g., distances to be measured in meters
declare time type real<seconds>;     -- e.g., time to be measured in seconds
declare job_id type long<job_id>;
declare person_id type long<person_id>;

-- With the above done
--  * vars/cols of type "distance" are incompatible with those of type "time"
--  * vars/cols of types job_id are incompatible with person_id
-- This is true even though the underlying type is the same for both!

-- ENUM declarations can have any numeric type as their base type
declare enum implement integer (
   pencil,       -- values start at 1 unless you use = to choose something
   pen,          -- the next enum gets previous + 1 as its value (2)
   brush = 7     -- with = expression you get the indicated value
);

-- The above also implicitly does this
declare implement type integer<implement> not null;

-- Using the enum -- simply use dot notation
declare impl implement;
set impl := implement.pen;  -- value "2"

-- You can emit an emum into the current .h file we are going to generate.
-- Do not put this directive in an include file, you want it to go to one place.
-- Instead, pick one compiland that will "own" the emission of the enum.
-- C code can then #include that one .h file.
@emit_enums implement;

/**********************************************************
 * 10. Shapes and Their Uses
 *********************************************************/

-- Shapes first appeared to help define value cursors like so:

-- A table or view name defines a shape
declare C cursor like T1;

-- The result of a proc defines a shape
declare D cursor like one_t1;

-- A dummy select statement defines a shape (the select does not run)
-- this one is the same as (x integer not null, y text not null)
declare E cursor like select 1 x, "2" y;

-- Another cursor defines a shape
declare F cursor like C;

-- The arguments of a procedure define a shape. If you have
-- create proc count_t1(r_ real, out rows_ integer not null) ...
-- the shape will be:
--  (r_ real, rows_ integer not null)
declare G cursor like count_t1 arguments;

-- A loaded cursor can be used to make a call
call count_t1(from G);  -- the args become G.r_, G.rows_

-- A shape can be used to define a procedures args, or some of the args
-- In the following "p" will have arguments:s id_, t_, and r_ with types
-- matching table T1.
-- Note: To avoid ambiguity, an _ was added to each name!
create proc p(like T1)
begin
  -- do whatever you like
end;

-- The arguments of the current procedure are a synthetic shape
-- called "arguments" and can used where other shapes can appear.
-- For instance, you can have "q" shim to "p" using this form:
create proc q(like T1, print bool not null)
begin
  -- maybe pre-process, silly example
  set id_ := id_ + 1;

  -- shim to p
  call p(from arguments); -- pass my args through, whatever they are

  -- maybe post-process, silly example
  set r_ := r_ - 1;

  if print then
    -- convert args to cursor
    declare C like q arguments;
    fetch C from arguments;
    call printf("%s\n", cql_cursor_format(C)); --> prints every column and value
  end if;

  -- insert a row based on the args
  insert into T1 from arguments;
end;

-- You an use a given shape more than once if you name each use.
-- This would be more exciting if T1 was like a "person" or something.
create proc r(a like T1, b like T1)
begin
  call p(from a);
  call p(from b);
  -- you can refer to a.id, b.id etc.
  declare C like a;
  fetch C from a;
  call printf("%s\n", cql_cursor_format(C));
  fetch C from b;
  call printf("%s\n", cql_cursor_format(C));
end;

-- Shapes can be subsetted, for instance in the following example
-- only the arguments that match C are used in the FETCH.
fetch C from arguments(like C);

-- Fetch the columns of D into C using the cursor D for the data source.
-- Other columns get default values.
fetch C(like D) from D;

-- Use the D shape to load C, dummy values for the others.
-- In this example, dummy_seed means use the provided value, 11, for
-- any numerics that are not specified (not in D) and and use
-- "col_name_11" for any strings/blobs.  This pattern is useful in test code
-- to create dummy data, hence the name.
fetch C(like D) from D @dummy_seed(11);

-- Use the Z shape to control which fields are copied.
-- Use the dummy value even if the field is nullable and null would have be ok.
fetch C(like Z) from D(like Z) @dummy_seed(11) @dummy_nullables;

-- The above patterns also work for insert statements
-- The shape constraints are generally useful.  The dummy data
-- sources are useful for inserting test data.
insert into T1(like Z) from D(like Z) @dummy_seed(11) @dummy_nullables;

-- We'll need this dummy procedure some_shape so we can use its return
-- value in the examples that follow.  We will never actual create this
-- proc, we only declare it to define the shape, so this is kind of like
-- a typedef.
declare proc some_shape() (x integer not null, y integer not null, z integer not null);

-- You can make a helper procedure to create test args that are mostly constant
-- or computable.
create get_foo_args(X like some_shape, seed_ integer not null)
begin
  declare C cursor like foo arguments;
  -- any way of loading C could work this is one
  fetch C(like X) from X @dummy_seed(seed_);
  out C;
end;

-- Now we can use the "get_foo_args" to get full set of arguments for "foo" and then
-- call "foo" with those arguments.  In this example we're providing
-- some of the arguments explicitly, "some_shape" is the part of the args that
-- needs to manually vary in each test iteration, the rest of the arguments will
-- be dummy values.  There could be zillions of args in either category.
-- In the below "some_shape" is going to get the manual values 1, 2, 3 while 100
-- will be the seed for the dummy args.
declare foo_args cursor fetch from call get_foo_args(1,2,3, 100);
call foo(from foo_args);

/**********************************************************
 * 11. INSERT USING and FETCH USING
 *********************************************************/

 -- This kind of thing is a pain
 insert into foo(a, b, c, d, e, f, g)
    values(1, 2, 3, null, null, 5, null);

-- Instead, write this form:
insert into foo USING
    1 a, 2 b, 3 c, null d, null e, 5 f, null g;

-- The FETCH statement can also be "fetch using"
declare C cursor like foo;
fetch C USING
    1 a, 2 b, 3 c, null d, null e, 5 f, null g;
```

If you've read this far you know more than most now.  :)
