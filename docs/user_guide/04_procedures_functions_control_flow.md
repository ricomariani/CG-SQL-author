---
title: "Chapter 4: Procedures, Functions, and Control Flow"
weight: 4
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

All kinds of control flow happens in the context of some procedure. Though we've already introduced examples of procedures let's
now go over some of the additional aspects we have not yet illustrated.

### Out Parameters

Consider this procedure:

```sql
create procedure echo_integer(in arg1 integer not null, out arg2 integer not null)
begin
  set arg2 := arg1;
end;
```

`arg1` has been declared `in`. This is the default: `in arg1 integer not null`
and `arg1 integer not null` mean the exact same thing.

`arg2`, however, has been declared `out`. When a parameter is declared using
`out`, arguments for it are passed by reference. This is similar to by-reference
arguments in other languages; indeed, they compile into a simple pointer
reference in the generated C code.

Given that `arg2` is passed by reference, the statement `set arg2 := arg1;`
actually updates a variable in the caller. For example:

```sql
declare x int not null;
call echo_integer(42, x);
-- `x` is now 42
```

It is important to note that values cannot be passed *into* a procedure via an
`out` parameter. In fact, `out` parameters are immediately assigned a new value
as soon as the procedure is called:

- All nullable `out` parameters are set to `null`.

- Nonnull `out` parameters of a non-reference type (e.g., `integer`, `long`,
  `bool`, et cetera) are set to their default values (`0`, `0.0`, `false`, et
  cetera).

- Nonnull `out` parameters of a reference type (e.g., `blob`, `object`, and
  `text`) are set to `null` as there are no default values for reference types.
  They must, therefore, be assigned a value within the procedure so that they
  will not be `null` when the procedure returns. CQL enforces this.

In addition to `in` and `out` parameters, there are also `inout` parameters.
`inout` parameters are, as one might expect, a combination of `in` and `out`
parameters: The caller passes in a value as with `in` parameters, but the value
is passed by reference as with `out` parameters.

`inout` parameters allow for code such as the following:

```sql
create procedure times_two(inout arg integer not null)
begin
  -- note that a variable in the caller is both
  -- read from and written to
  set arg := arg + arg;
end;

let x := 2;
call times_two(x);
-- `x` is now 4
```

### Procedure Calls

The usual `call` syntax is used to invoke a procedure.  It returns no value but it can have any number of `out` arguments.

```
  declare scratch integer not null;
  call echo_integer(12, scratch);
  scratch == 12; -- true
```

Let's go over the most essential bits of control flow.

### The IF statement

The CQL `IF` statement has no syntatic ambiguities at the expense of being somewhat more verbose than many other languages.
In CQL the `ELSE IF` portion is baked into the `IF` statement, so what you see below is logically a single statement.

```sql
create proc checker(foo integer, out result integer not null)
begin
  if foo = 1 then
   set result := 1;
  else if foo = 2 then
   set result := 3;
  else
   set result := 5;
  end if;
end;
```

### The WHILE statement

What follows is a simple procedure that counts down its input argument.

```sql
declare procedure printf no check;

create proc looper(x integer not null)
begin
  while x > 0
  begin
   call printf('%d\n', x);
   set x := x - 1;
  end;
end;
```

The `WHILE` loop has additional keywords that can be used within it to better control the loop.  A more general
loop might look like this:

```sql
declare procedure printf no check;

create proc looper(x integer not null)
begin
  while 1
  begin
   set x := x - 1;
   if x < 0 then
     leave;
   else if x % 100 = 0 then
     continue;
   else if x % 10 = 0 then
     call printf('%d\n', x);
   end if;
  end;
end;
```

Let's go over this peculiar loop:

```sql
  while 1
  begin
    ...
  end;
```

This is an immediate sign that there will be an unusual exit condition.
The loop will never end without one because `1` will never be false.

```sql
   if x < 0 then
     leave;
```
Now here we've encoded our exit condition a bit strangely: we might have
done the equivalent job with a normal condition in the predicate part of
the `while` statement but for illustration anyway, when x becomes negative
`leave` will cause us to exit the loop.  This is like `break` in C.

```sql
   else if x % 100 = 0 then
     continue;
```

This bit says that on every 100th iteration we go back to the start of
the loop.  So the next bit will not run, which is the printing.

```sql
   else if x % 10 = 0 then
     call printf('%d\n', x);
   end if;
```

Finishing up the control flow, on every 10th iteration we print the value of the loop variable.

### The SWITCH Statement

The  CQL `SWITCH` is designed to map to the C `switch` statement for
better codegen and also to give us the opportunity to do better error
checking.  `SWITCH` is a *statement* like `IF` not an *expression* like
`CASE..WHEN..END` so it combines with other statements. The general form
looks like this:

```SQL
SWITCH switch-expression [optional ALL VALUES]
WHEN expr1, expr2, ... THEN
  [statement_list]
WHEN expr3, ... THEN
  [statement_list]
WHEN expr4 THEN
  NOTHING
ELSE
  [statement_list]
END;
```
* the switch-expression must be a not-null integral type (`integer not null` or `long integer not null`)
* the `WHEN` expressions [expr1, expr2, etc.] are made from constant integer expressions (e.g. `5`, `1+7`, `1<<2`, or `my_enum.thing`)
* the `WHEN` expressions must be compatible with the switch expression (long constants cannot be used if the switch expression is an integer)
* the values in the `WHEN` clauses must be unique (after evaluation)
* within one of the interior statement lists the `LEAVE` keyword exits the `SWITCH` prematurely, just like `break` in C
   * a `LEAVE` is not required before the next `WHEN`
   * there are no fall-through semantics as you can find in `C`, if fall-through ever comes to `SWITCH` it will be explicit
* if the keyword `NOTHING` is used after `THEN` it means there is no code for that case, which is useful with `ALL VALUES` (see below)
* the `ELSE` clause is optional and works just like `default` in `C`, covering any cases not otherwise explicitly listed
* if you add `ALL VALUES` then:
   * the expression must be an from an enum type
   * the `WHEN` values must cover every value of the enum
      * enum members that start with a leading `_` are by convention considered pseudo values and do not need to be covered
   * there can be no extra `WHEN` values not in the enum
   * there can be no `ELSE` clause (it would defeat the point of listing `ALL VALUES` which is to get an error if new values come along)

Some more complete examples:

```sql
let x := get_something();
switch x
  when 1,1+1 then -- constant expressions ok
    set y := 'small';
    -- other stuff
  when 3,4,5 then
    set y := 'medium';
    -- other stuff
  when 6,7,8 then
    set y := 'large';
    -- other stuff
  else
    set y := 'zomg enormous';
end;

declare enum item integer (
  pen = 0, pencil, brush,
  paper, canvas,
  _count
);

let x := get_item(); -- returns one of the above

switch x all values
  when item.pen, item.pencil then
     call write_something();
  when item.brush then nothing
     -- itemize brush but it needs no code
  when item.paper, item.canvas then
    call setup_writing();
end;
```

Using `THEN NOTHING` allows the compiler to avoid emitting a useless
`break` in the C code.  Hence that choice is better/clearer than `when
brush then leave;`

Note that the presence of `_count` in the enum will not cause an error
in the above because it starts with `_`.

The `C` output for this statement will be a direct mapping to a `C`
switch statement.

### The TRY, CATCH, and THROW Statements

This example illustrates catching an error from some DML, and recovering
rather than letting the error cascade up.  This is the common "upsert"
pattern (insert or update)

```sql
declare procedure printf no check;

create procedure upsert_foo(id_ integer, t_ text)
begin
  try
    insert into foo(id, t) values(id_, t_)
  catch
    try
      update foo set t = t_ where id = id_;   
    catch
      call printf("Error code %d!\n", @rc);
      throw;
    end;
  end;
end;
```

Once again, let's go over this section by section:

```sql
  try
    insert into foo(id, t) values(id_, t_)
  catch
```

Normally if the `insert` statement fails, the procedure will exit with a failure result code.  Here, instead,
we prepare to catch that error.

```sql
  catch
    try
      update foo set t = t_ where id = id_;
    catch
```

Now, having failed to insert, presumably because a row with the provided
`id` already exists, we try to update that row instead.  However that
might also fail, so we  wrap it in another try.  If the update fails,
then there is a final catch block:

```sql
    catch
      call printf("Error code %d!\n", @rc);
      throw;
    end;
```

Here we see a usage of the `@rc` variable to observe the failed error
code.  In this case we simply print a diagnostic message and then use the
`throw` keyword to rethrow the previous failure (exactly what is stored
in `@rc`).  In general, `throw` will create a failure in the current
block using the most recent failed result code from SQLite (`@rc`)
if it is an error, or else the general `SQLITE_ERROR` result code if
there is no such error.  In this case the failure code for the `update`
statement will become the result code of the current procedure.

This leaves only the closing markers:

```sql
  end;
end;
```

If control flow reaches the normal end of the procedure it will return `SQLITE_OK`.

### Procedures as Functions: Motivation and Example


The calling convention for CQL stored procedures often (usually) requires
that the procedure returns a result code from SQLite.  This makes it
impossible to write a procedure that returns a result like a function,
as the result position is already used for the error code.  You can
get around this problem by using `out` arguments as your return codes.
So for instance, this version of the Fibonacci function is possible.


```sql
-- this works, but it is awkward
create procedure fib (in arg integer not null, out result integer not null)
begin
  if (arg <= 2) then
    set result := 1;
  else
    declare t integer not null;
    call fib(arg - 1, result);
    call fib(arg - 2, t);
    set result := t + result;
  end if;
end;
```

The above works, but the notation is very awkward.


CQL has a "procedures as functions" feature that tries to make this
more pleasant by making it possible to use function call notation on a
procedure whose last argument is an `out` variable.  You simply call
the procedure like it was a function and omit the last argument in
the call.  A temporary variable is automatically created to hold the
result and that temporary becomes the logical return of the function.
For semantic analysis, the result type of the function becomes the type
of the `out` argument.

```sql
-- rewritten with function call syntax
create procedure fib (in arg integer not null, out result integer not null)
begin
  if (arg <= 2) then
    set result := 1;
  else
    set result := fib(arg - 1) + fib(arg - 2);
  end if;
end;
```

This form is allowed when:

* all but the last argument of the procedure was specified
* the formal parameter for that last argument was marked with `out` (neither `in` nor `inout` are acceptable)
* the procedure does not return a result set using a `select` statement or `out` statement (more on these later)

If the procedure in question uses SQLite, or calls something that
uses SQLite, then it might fail.  If that happens the result code
will propagate just like it would have with the usual `call` form.
Any failures can be caught with `try/catch` as usual.  This feature is
really only syntatic sugar for the "awkward" form above, but it does
allow for slightly better generated C code.
