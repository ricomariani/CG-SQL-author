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

Though we've already introduced examples of procedures, let's now go over some
of the additional aspects we have not yet illustrated, like arguments and
control-flow.

### Out Parameters

Consider this procedure:


```sql
proc copy_integer(in arg1 int!, out arg2 int!)
begin
  set arg2 := arg1;
end;
```

`arg1` has been declared as `in`. This is the default: `in arg1 int!`,
and `arg1 int!` mean the exact same thing.

`arg2`, however, has been declared as `out`. When a parameter is declared using
`out`, arguments for it are passed by reference. This is similar to by-reference
arguments in other languages; indeed, they compile into a simple pointer
reference in the generated C code.

Given that `arg2` is passed by reference, the statement `set arg2 := arg1;`
actually updates a variable in the caller. For example:

```sql
var x int!;
call copy_integer(42, x);
-- `x` is now 42
```

It is important to note that values cannot be passed *into* a procedure via an
`out` parameter. In fact, `out` parameters are immediately assigned a new value
as soon as the procedure is called:

* All nullable `out` parameters are set to `null`.
* Nonnull `out` parameters of a non-reference type (e.g., `integer`, `long`,
  `bool`, etc.) are set to their default values (`0`, `0.0`, `false`, etc.).
* Nonnull `out` parameters of a reference type (e.g., `blob`, `object`, and
  `text`) are set to `null` as there are no default values for reference types.
  They must, therefore, be assigned a value within the procedure so that they
  will not be `null` when the procedure returns. CQL enforces this.

In addition to `in` and `out` parameters, there are also `inout` parameters.
`inout` parameters are, as one might expect, a combination of `in` and `out`
parameters: The caller passes in a value as with `in` parameters, but the value
is passed by reference as with `out` parameters.

`inout` parameters allow for code such as the following:

```sql
proc times_two(inout arg int!)
begin
  -- note that a variable in the caller is both read from and written to

  arg += arg; -- this is the same as set arg := arg + arg;
end;

let x := 2;
times_two(x); -- this is the same as call times_two(x)
-- `x` is now 4
```

### Procedure Calls

The usual `call` syntax is used to invoke a procedure. It returns no value, but
it can have any number of `out` arguments.

```sql
  var scratch int!;
  call copy_integer(12, scratch);
  scratch == 12; -- true
```

Let's go over the most essential bits of control flow.

### The IF statement

The CQL `IF` statement has no syntactic ambiguities at the expense of being
somewhat more verbose than many other languages. In CQL, the `ELSE IF` portion
is baked into the `IF` statement, so what you see below is logically a single
statement.

```sql
create proc checker(foo int, out result int!)
begin
  if foo = 1 then
    result := 1;
  else if foo = 2 then
    result := 3;
  else
    result := 5;
  end if;
end;
```

### The WHILE statement

What follows is a simple procedure that counts down its input argument.

```sql
declare procedure printf no check;

create proc looper(x int!)
begin
  while x > 0
  begin
   call printf('%d\n', x);
   x -= 1;
  end;
end;
```

The `WHILE` loop has additional keywords that can be used within it to better
control the loop. A more general loop might look like this:

```sql
declare procedure printf no check;

create proc looper(x int!)
begin
  while 1
  begin
   x -= 1;
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

This is an immediate sign that there will be an unusual exit condition. The loop
will never end without one because `1` will never be false.

```sql
   if x < 0 then
     leave;
```

Now here we've encoded our exit condition a bit strangely: we might have done
the equivalent job with a normal condition in the predicate part of the `while`
statement but for illustration anyway, when x becomes negative `leave` will
cause us to exit the loop. This is like `break` in C.

```sql
   else if x % 100 = 0 then
     continue;
```

This bit says that on every 100th iteration, we go back to the start of the
loop. So the next bit will not run, which is the printing.

```sql
   else if x % 10 = 0 then
     call printf('%d\n', x);
   end if;
```

Finishing up the control flow, on every 10th iteration we print the value of the
loop variable.


### The FOR Statement

The `FOR` statement provides a bit more convenience over `WHILE` and that's pretty much it.
The usual thing that goes wrong with a simple `WHILE` loop is that you end up forgetting
to add the iteration increment and then you debug an infinite loop.  To help avoid this
`FOR` lets you specify the loop end action in the same place as the condition.  Looking
at the previous example, with `FOR` it looks like this:

```sql
declare procedure printf no check;

create proc looper(x int!)
begin
  for x > 0; x -= 1;
  begin
    printf('%d\n', x);
  end;
end;
```

Here we've also used some of the more modern forms, eliding the `call`.

`FOR` very general, any number of statements can follow the condition so for instance

```
for x < 5 and y < 5; x += 1; y += 1;
begin
   ...
end;
```

Any statements may appear in the list, even things that don't seem very loop-like.  You could fetch a cursor
or something.

The `FOR` construct is similar to while, you might think of it as:

```sql
--- for <condition> ; <loop update statements; ... ;> ; begin  <main body> end;
while <condition>
begin
  <main body>

continue_will_go_here:
  <loop update statements; ... ;>
end;
```

Essentially it's the same as putting all those statements at the end except that `continue` will
go to those statements instead of the top of the loop.

There is no difference in code quality.  The only advantage is that the all the loop info is together.

This is possible:

```
let x := 5; for x < 10; x += 1;
begin
  ...
end;
```
It would be very simple to macroize `FOR` to do some simple loop cases like:

```sql
@macro(stmt_list) _for!(id! expr, c1! expr, c2! expr, s! stmt_list)
begin
   id! := c1!;
   for id! <= c2! ; id! += 1;
   begin
      s!;
   end;
end;

proc foo()
begin
  var x int;

  _for!(x, 1, 5,
  begin
    printf("%d\n", x);
  end);
end;
```

For is useful for this because all the loop pieces are together so it's a little easier to macroize.


### The SWITCH Statement

 The CQL `SWITCH` is designed to map to the C `switch` statement for better code
 generation and also to give us the opportunity to do better error checking.
 `SWITCH` is a *statement* like `IF`, not an *expression* like
 `CASE..WHEN..END`, so it combines with other statements. The general form looks
 like this:

```sql
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

* the switch-expression must be a not-null integral type (`int!` or `long!`)
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

enum item int (
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

Using `THEN NOTHING` allows the compiler to avoid emitting a useless `break` in
the C code. Hence, that choice is better/clearer than `when brush then leave;`.

Note that the presence of `_count` in the enum will not cause an error in the
above because it starts with `_`.

The `C` output for this statement will be a `C` switch statement.

### The TRY, CATCH, and THROW Statements

This example illustrates catching an error from some DML, and recovering
rather than letting the error cascade up.  This is the common "upsert"
pattern (insert or update)

```sql
declare procedure printf no check;

proc upsert_foo(id_ integer, t_ text)
begin
  try
    insert into foo(id, t) values(id_, t_);
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
    insert into foo(id, t) values(id_, t_);
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

Here we see a usage of the `@rc` variable to observe the failed error code. In
this case, we simply print a diagnostic message and then use the `throw` keyword
to rethrow the previous failure (exactly what is stored in `@rc`). In general,
`throw` will create a failure in the current block using the most recent failed
result code from SQLite (`@rc`) if it is an error, or else the general
`SQLITE_ERROR` result code if there is no such error. In this case, the failure
code for the `update` statement will become the result code of the current
procedure.

This leaves only the closing markers:

```sql
  end;
end;
```

If control flow reaches the normal end of the procedure it will return `SQLITE_OK`.

### Advanced: The `cql:try_is_proc_body` Attribute

When writing procedures with `OUT` parameters, CQL enforces that all nonnull
`OUT` parameters must be initialized before the procedure returns. This is
normally checked at the end of the procedure. However, this can create a problem
when wrapping an entire procedure in a `TRY`/`CATCH` block for custom error
handling or logging.

Consider a common pattern where you want to add error logging to all procedures
using a macro that wraps the procedure body:

```sql
@macro(stmt_list) LOGGING_PROC!(body! stmt_list)
begin
  let error_in_try := false;
  [[cql:try_is_proc_body]]
  try
    body!;
  catch
    error_in_try := true;
  end;
  if error_in_try then
    call log_error_and_rethrow(@MACRO_FILE, @MACRO_LINE);
  end if;
end;

create proc some_proc(out x text not null)
begin
  LOGGING_PROC!(
  begin
    if some_condition then
      set x := some_value;
    else
      set x := get_another_value_or_throw();
    end if;
  end);
end;
```

Without the `[[cql:try_is_proc_body]]` attribute, this would fail CQL's
initialization checking. Even though `x` is always initialized in the `TRY`
block (or an exception is thrown), the flow analysis sees that the `CATCH` block
doesn't initialize `x`, so it appears uninitialized at the end of the procedure.

The `[[cql:try_is_proc_body]]` attribute solves this by telling CQL to:
1. Check that all `OUT` parameters are initialized by the end of the annotated
   `TRY` block (treating it as the conceptual body of the procedure)
2. Skip the normal initialization check at the end of the procedure

This allows the error-handling wrapper pattern to work correctly: if the `TRY`
block completes normally, all parameters are guaranteed initialized; if an
exception occurs, the `CATCH` block handles it (in this example by logging and
rethrowing).

**Important:** This attribute should only be used when you have a specific
error-handling pattern that ensures exceptions are properly handled. Misuse of
`[[cql:try_is_proc_body]]` can disable useful initialization checking.  The
rethrow is essential.

### Procedures as Functions: Motivation and Example

The calling convention for CQL stored procedures often requires that the
procedure return a result code from SQLite. This makes it impossible to write a
procedure that returns a result like a C function, as the result position is
already used for the error code. You can get around this problem by using `out`
arguments as your return results. So, for instance, this version of the Fibonacci
function is possible.


```sql
-- this works, but it is awkward
proc fib (in arg int!, out result int!)
begin
  if (arg <= 2) then
    set result := 1;
  else
    var t int!;
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
proc fib (in arg int!, out result int!)
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

If the procedure in question uses SQLite, or calls something that uses SQLite,
then it might fail. If that happens the result code will propagate just like it
would have with the usual `call` form. Any failures can be caught with
`try/catch` as usual. The "procedure as function" feature is really only
syntatic sugar for the "awkward" form above, but it does allow for slightly
better generated C code.
