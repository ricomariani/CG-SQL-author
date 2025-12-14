---
title: "Chapter 14: Shared Fragments"
weight: 14
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

Shared fragments allows you to reuse and compose SQL queires in a safe
(type checked) and efficient manner. They are based on [Common Table
Expressions (CTEs)](https://www.sqlite.org/lang_with.html), so some
basic knowledge of that is recommended before using Shared Fragments.

You can think of shared fragments as being somewhat like a parameterized
view, but the parameters are both value parameters and type parameters. In
Java or C#, a shared fragments might have had an invocation that looked
something like this:  `my_fragment(1,2)<table1, table2>`.

It's helpful to consider a real example:

```sql
split_text(tok) AS (
  WITH RECURSIVE
    splitter(tok,rest) AS (
      SELECT
        '' tok,
        IFNULL( some_variable_ || ',', '') rest
      UNION ALL
      SELECT
        substr(rest, 1, instr(rest, ',') - 1) tok,
        substr(rest, instr(rest, ',') + 1) rest
        FROM splitter
        WHERE rest != ''
  )
  SELECT tok from splitter where tok != '';
)
```

This text might appear in dozens of places where a comma separated list
needs to be split into pieces and there is no good way to share the code
between these locations.  CQL can also do fragments with macros but this
loses some benefits so there is a trade off, for instance, if use `@macro`
to build fragments:

* any errors in the macro do not appear until the macro is used
* the compiler does not then know that the origin of the text really is the same
  * thus it has no clue that sharing the text of the string might be a good idea
* if you try to compose such macros it only gets worse; it's more code duplication and harder error cases

None of this is any good but the desire to create helpers like this is
real both for correctness and for performance.

To make these things possible, we introduce the notion of shared
fragments.  We need to give them parameters and the natural way to
create a select statement that is bindable in CQL is the procedure. So
the shape we choose looks like this:

```sql
[[shared_fragment]]
PROC split_text(value TEXT)
BEGIN
  WITH RECURSIVE
    splitter(tok,rest) AS (
      SELECT
        '' tok,
        IFNULL( value || ',', '') rest
      UNION ALL
      SELECT
        substr(rest, 1, instr(rest, ',') - 1) tok,
        substr(rest, instr(rest, ',') + 1) rest
        FROM tokens
        WHERE rest != ''
  )
  SELECT tok from splitter where tok != '';
END;
```

The introductory attribute `[[shared_fragment]]` indicates that the
procedure is to produce no code, but rather will be inlined as a CTE in
other locations.  To use it, we introduce the ability to call a procedure
as part of a CTE declaration.  Like so:

```sql
WITH
  result(v) as (call split_text('x,y,z'))
  select * from result;
```

Once the fragment has been defined, the statement above could appear
anywhere, and of course the text `'x,y,z'` need not be constant.
For instance:

```sql
PROC print_parts(value TEXT)
BEGIN
  CURSOR C FOR
    WITH
      result(v) as (CALL split_text('x,y,z'))
      SELECT * from result;

  LOOP FETCH C
  BEGIN
     CALL printf("%s\n", C.v);
  END;
END;
```

Fragments are also composable, so for instance, we might also want some
shared code that extracts comma separated numbers.  We could do this:

```sql
[[shared_fragment]]
PROC ids_from_string(value TEXT)
BEGIN
  WITH
    result(v) as (CALL split_text(value))
  SELECT CAST(v as LONG) as id from result;
END;
```

Now we could write:

```sql
PROC print_ids(value TEXT)
BEGIN
  CURSOR C FOR
    WITH
      result(id) as (CALL ids_from_string('1,2,3'))
      SELECT * from result;

  LOOP FETCH C
  BEGIN
     CALL printf("%ld\n", C.id);
  END;
END;
```

Of course these are very simple examples but in principle you can use
the generated tables in whatever way is necessary.  For instance, here's
a silly but illustrative example:

```sql
/* This is a bit silly */
PROC print_common_ids(value TEXT)
BEGIN
  CURSOR C FOR
    WITH
      v1(id) as (CALL ids_from_string('1,2,3')),
      v2(id) as (CALL ids_from_string('2,4,6'))
      SELECT * from v1
      INTERSECT
      SELECT * from v2;

  LOOP FETCH C
  BEGIN
     CALL printf("%ld\n", C.id);
  END;
END;
```

With a small amount of dynamism in the generation of the SQL for the
above, it's possible to share the body of v1 and v2.  SQL will of course
see the full expansion but your program only needs one copy no matter
how many times you use the fragment anywhere in the code.

So far we have illustrated the "parameter" part of the flexibility.
Now let's look at the "generics" part; even though it's overkill for
this example, it should still be illustrative.  You could imagine that
the procedure we wrote above `ids_from_string` might do something more
complicated, maybe filtering out negative ids, ids that are too big, or
that don't match some pattern, whatever the case might be.  You might
want these features in a variety of contexts, maybe not just starting
from a string to split.

We can rewrite the fragment in a "generic" way like so:

```sql
[[shared_fragment]]
PROC ids_from_string_table()
BEGIN
  WITH
    source(v) LIKE (select "x" v)
  SELECT CAST(v as LONG) as id from source;
END;
```

Note the new construct for a CTE definition: inside a fragment we can
use "LIKE" to define a plug-able CTE.  In this case we used a `select`
statement to describe the shape the fragment requires.  We could also
have used a name `source(*) LIKE shape_name` just like we use shape
names when describing cursors.  The name can be any existing view, table,
a procedure with a result, etc.  Any name that describes a shape.

Now when the fragment is invoked, you provide the actual data source
(some table, view, or CTE) and that parameter takes the role of "values".
Here's a full example:

```sql
PROC print_ids(value TEXT)
BEGIN
  CURSOR C FOR
    WITH
      my_data(*) as (CALL split_text(value)),
      my_numbers(id) as (CALL ids_from_string_table() USING my_data AS source)
      SELECT id from my_numbers;

  LOOP FETCH C
  BEGIN
     CALL printf("%ld\n", C.id);
  END;
END;
```

We could actually rewrite the previous simple id fragment as follows:

```sql
[[shared_fragment]]
PROC ids_from_string(value TEXT)
BEGIN
  WITH
    tokens(v) as (CALL split_text(value))
    ids(id) as (CALL ids_from_string_table() USING tokens as source)
  SELECT * from ids;
END;
```

And actually we have a convenient name we could use for the shape we need
so we could have used the shape syntax to define `ids_from_string_table`.

```sql
[[shared_fragment]]
PROC ids_from_string_table()
BEGIN
  WITH
    source(*) LIKE split_text
  SELECT CAST(tok as LONG) as id from source;
END;
```

These examples have made very little use of the database but of course
normal data is readily available, so shared fragments can make a great
way to provide access to complex data with shareable, correct code.
For instance, you could write a fragment that provides the ids of all
open businesses matching a name from a combination of tables.  This is
similar to what you could do with a `VIEW` plus a `WHERE` clause but:

* such a system can give you well controlled combinations known to work well
* there is no schema required, so your database load time can still be fast
* parameterization is not limited to filtering VIEWs after the fact
* "generic" patterns are available, allowing arbitrary data sources to be filtered, validated, augmented
* each fragment can be tested separately with its own suite rather than only in the context of some larger thing
* code generation can be more economical because the compiler is aware of what is being shared

In short, shared fragments can help with the composition of any complicated kinds of queries.
If you're producing an SDK to access a data set, they are indispensible.

#### Creating and Using Valid Shared Fragments

When creating a fragment the following rules are enforced:

* the fragment many not have any out arguments
* it must consist of exactly one valid select statement (but see future forms below)
* it may use the LIKE construct in CTE definitions to create placeholder shapes
  * this form is illegal outside of shared fragments (otherwise how would you bind it)
* the LIKE form may only appear in top level CTE expressions in the fragment
* the fragment is free to use other fragments, but it may not call itself
  * calling itself would result in infinite inlining

Usage of a fragment is always introduced by a "call" to the fragment name in a CTE body.
When using a fragment the following rules are enforced.

* the provided parameters must create a valid procedure call just like normal procedure calls
  * i.e. the correct number and type of arguments
* the provided parameters may not use nested `(SELECT ...)` expressions
  * this could easily create fragment building within fragment building which seems not worth the complexity
  * if database access is required in the parameters simply wrap it in a helper procedure
* the optional USING clause must specify each required table parameter exactly once and no other tables
  * a fragment that requires table parameters be invoked without a USING clause
* every actual table provided must match the column names of the corresponding table parameter
  * i.e. in `USING my_data AS values` the actual columns in `my_data` must be the same as in the `values` parameter
  * the columns need not be in the same order
* each column in any actual table must be "assignment compatible" with its corresponding column in the parameters
  * i.e. the actual type could be converted to the formal type using the same rules as the := operator
  * these are the same rules used for procedure calls, for instance, where the call is kind of like assigning the actual parameter values to the formal parameter variables
* the provided table values must not conflict with top level CTEs in the shared fragment
  * exception: the top level CTEs that were parameters do not create conflicts
  * e.g. it's common to do `values(*) as (CALL something() using source as source)` - here the caller's "source" takes the value of the fragment's "source", which is not a true conflict
  * however, the caller's source might itself have been a parameter in which case the value provided could create an inner conflict
    * all these problems are easily avoided with a simple naming convention for parameters so that real arguments never look like parameter names and parameter forwarding is apparent
    * e.g. `USING _source AS _source` makes it clear that a parameter is being forwarded and `_source` is not likely to conflict with real table or view names

Note that when shared fragments are used, the generated SQL has the text
split into parts, with each fragment and its surroundings separated,
therefore the text of shared fragments is shared(!) between usages if
normal linker optimizations for text folding are enabled (common in
production code.)

### Shared Fragments with Conditionals

Shared fragments use dynamic assembly of the text to do the sharing
but it is also possible to create alternative texts.  There are many
instances where it is desirable to not just replace parameters but use,
for instance, an entirely different join sequence.  Without shared
fragments, the only way to accomplish this is to fork the desired query
at the topmost level (because SQLite has no internal possibility of "IF"
conditions.)  This is expensive in terms of code size and also cognitive
load because the entire alternative sequences have to be kept carefully
in sync.  Macros can help with this but then you get the usual macro
maintenance problems, including poor diagnostics.  And of course there
is no possibility to share the common parts of the text of the code if
it is forked.

However, conditional shared fragments allow forms like this:

```sql
[[shared_fragment]]
PROC ids_from_string(val TEXT)
BEGIN
  IF val IS NULL OR val IS '' THEN
    SELECT 0 id WHERE 0; -- empty result
  ELSE
    WITH
      tokens(v) as (CALL split_text(val))
      ids(id) as (CALL ids_from_string_table() USING tokens as source)
    SELECT * from ids;
  END IF;
END;
```

Now we can do something like:

```sql
  ids(*) AS (CALL ids_from_string(str))
```

In this case, if the string `val` is empty then SQLite will not see the
complex comma splitting code, and instead will see the trivial case
`select 0 id where 0`.  The code in a conditional fragment might be
entirely different between the branches removing unnecessary code,
or swapping in a new experimental cache in your test environment, or
anything like that.

#### Conditionals without ELSE clauses
When a condiitional is specified without an else clause, the fragment would return a result with no rows if none of the specified conditionals are truthy.

For example:
```sql
[[shared_fragment]]
PROC maybe_empty(cond BOOL!)
BEGIN
  IF cond THEN
    SELECT 1 a, 2 b, 3 c;
  END IF;
END;
```

Internally, this is actually equivalent to the following:
```sql
[[shared_fragment]]
PROC maybe_empty(cond BOOL!)
BEGIN
  IF cond THEN
    SELECT 1 a, 2 b, 3 c;
  ELSE
    SELECT NOTHING;
  END IF;
END;
```

The `SELECT NOTHING` expands to the a query that returns no rows, like this:
```sql
SELECT 0,0,0 WHERE 0; -- number of columns match the query returned by the main conditional.
```

#### Summary

The generalization is simply this:

* instead of just one select statement there is one top level "IF" statement
* each statement list of the IF must be exactly one select statement
* the select statements must be type compatible, just like in a normal procedure
* any table parameters with the same name in different branches must have the same type
  * otherwise it would be impossible to provide a single actual table for those table parameters

With this additional flexibility a wide variety of SQL statements can be
constructed economically and maintainability.  Importantly, consumers of
the fragments need not deal with all these various alternate possibilities
but they can readily create their own useful combinations out of building
blocks.

Ultimately, from SQLite's perspective, all of these shared fragment
forms result in nothing more complicated than a chain of CTE expressions.

See Appendix 8 for an extensive section on best practices around fragments
and common table expressions in general.

>TIP: If you use CQL's query planner on shared fragments with conditionals, the
>query planner will only analyze the first branch by default. You need to use
>`[[query_plan_branch={an_integer}]]` to modify the behavior. Read [Query Plan
>Generation](./15_query_plan_generation.md) for details.

### Shared Fragments as Expressions

The shared fragment system also has the ability to create re-usable
expression-style fragments giving you something like SQL inline functions. These
do come with some performance cost so they should be used for larger fragments.
In many systems a simple shared expression fragment would not compete well with
an equivalent `@macro(expr)`.  Expression fragments shine when:

* the fragment is quite large
* its used frequently (hence providing significant space savings)
* the arguments are complex, potentially used many times in the expression

From a raw performance perspective, the best you can hope for with
any of the fragment approaches is a "tie" on speed compared do directly
inlining equivalent SQL or using a macro to do the same.  However, from a
correctness and space perspective it is very possible to come out ahead.
It's fair to say that expression fragments have the greatest overhead
compared to the other types and so they are best used in cases where
the size benefits are going to be important.

#### Syntax

An expression fragment is basically a normal shared fragment with no
top-level `FROM` clause that generates a single column.  A typical one
might look like this:

```sql
-- this isn't very exciting because regular max would do the job
[[shared_fragment]]
proc max_func(x int, y int)
begin
  select case when x >= y then x else y end;
end;
```

The above can be used in the context of a SQL statement like so:

```sql
select max_func(T1.column1, T1.column2) the_max from foo T1;
```

#### Discussion

The consequence of the above is that the body of `max_func` is inlined
into the generated SQL.  However, like the other shared fragments, this is
done in such a way that the text can be shared between instances so you
only pay for the cost of the text of the SQL in your program one time,
no matter how many time you use it.

In particular, for the above, the compiler will generate the following SQL:

```sql
select (
  select case when x >= y then x else y end
    from (select T1.column1 x, column2 y))
```

But each line will be its own string literal, so, more accurately,
it will concatenate the following three strings:

```c
"select (",                                      // string1
" select case when x >= y then x else y end",    // string2
" from (select T1.column1 x, column2 y))"        // string3
```

Importantly, `string2` is fixed for any given fragment.  The only
thing that changes is `string3`, i.e., the arguments.  In any modern C
compilation system, the linker will unify the `string2` literal across
all translation units so you only pay for the cost of that text one time.
It also means that the text of the arguments appears exactly one time,
no matter how complex they are.  For these benefits, we pay the cost of
the select wrapper on the arguments.  If the arguments are complex that
"cost" is negative.  Consider the following:

```sql
select max_func((select max(T.m) from T), (select max(U.m) from U))
```

A direct expansion of the above would result in something like this:

```sql
case when (select max(T.m) from T) >= (select max(U.m) from U)
   then (select max(T.m) from T)
   else (select max(U.m) from U)
end;
```

The above could be accomplished with a simple `@macro(expr)`
construct. However, the expression fragment generates the following code:

```sql
select (
  select case when x >= y then x else y end
    from select (select max(T.m) from T) x, (select max(U.m) from U) y))
```

Meaning that the values arguments evaluated exactly once.

Expression fragments can nest, so you could write:

```sql
[[shared_fragment]]
proc max3_func(x int, y int, z int)
begin
  select max_func(x, max_func(y, z));
end;
```

Again, this particular example is a waste because regular `max` would
already do the job better.

To give another example, common mappings from one kind of code to another
using case/when can be written and shared this way:

```sql
-- this sort of thing happens all the time
[[shared_fragment]]
proc remap(x int!)
begin
   select case x
     when 1 then 1001
     when 2 then 1057
     when 3 then 2010
     when 4 then 2011
     else 9999
   end;
end;
```

In the following:

```sql
select remap(T1.c), remap(T2.d), remap(T3.e) from T1, T2, T3... etc.
```

The text for `remap` will appear three times in the generated SQL query but only one time in your binary.

#### Restrictions

* the fragment must consist of exactly one simple select statement
  * no `FROM`, `WHERE`, `HAVING`, etc. -- the result is an expression
* the select list must have exactly one value
  * Note the expression can be a nested `SELECT` which could then have all the usual `SELECT` elements
* the usual shared fragment rules apply, e.g. no out-parameters, exactly one statement, etc.


#### Additional Notes

A simpler syntax might have been possible but expression fragments
are only interesting in SQL contexts where (among other things) normal
procedure and function calls are not available. So the `select` keyword
makes it clear to the coder and the compiler that the expression will
be evaluated by SQLite and the rules for what is allowed to go in the
expression are the SQLite rules.

The fragment has no `FROM` clause because we're trying to produce
an expression, not a table-value with one column.  If you want a
table-value with one column, the original shared fragments solution
already do exactly that.  Expression fragments give you a solution for
sharing code in, say, the `WHERE` clause of a larger select statement.

Commpared to something like

```sql
@macro(expr) max_func!(x! expr, y! expr)
begin
  case when x! >= y! then x! else y! end
end;
```

The macro does give you a ton of flexibility, but it has many problems:

* the compiler doesn't know that the sharing is going on so it won't be able to share text between call sites
* the arguments can be evaluated many times each which could be expensive, bloaty, or wrong
* there is no type-checking of arguments to the macro so you may or may not get compilation errors after expansion

In general, macros _can_ be used as an alternative to expression fragments,
especially for small fragments.  But, this gets to be a worse idea as such
macros grow.  For larger cases, C and C++ provide inline functions -- CQL
provides expression fragments.


### Macros vs. Shared Fragments Example

This bit of sample code illustrates the different flexibilities of macros vs. shared fragments.

```sql
declare proc printf no check;

create proc setup()
begin
    /*
       This view is sort of the most basic form of a shared fragment. It can
       have no parameters and cannot customized beyond the one statement.
    */
    create view v1 as
        with cte as (
            select 1 as N
            union all
            select n + 1 N from cte where cte.n < 100
        )
        select N from cte;
end;

/*
    This shared fragment produces a CTE that counts from 1 to lim. The value of
    this form is that:
    * lim is strongly typed * it can be independently error checked
    * the exact text will be the same except for variables hence it can be
      shared in the code
    * it can be invoked with call where a CTE could go and composes in the usual
      SQL ways
    * it has a consistent known signature for its inputs and outputs so strong
      error checking is possible
    * Note that conditional fragments allow you to get different SQL depending
      on the input arguments but they always result in the same shape
*/
[[shared_fragment]]
proc counter(lim int)
begin
    with cte as (
        select 1 as N
        union all
        select n + 1 N from cte where cte.n < lim
    )
    select N from cte;
end;

/* This macro definition acts very much like a shared fragment. The value of
   this form is that:
    * the end expression can be anything that is valid SQL, and it will be
       evaluated in the context of the statement not in the context of the
       caller
    * it could include other macro parameters to for instance rename the cte
    * it could include other macro arguments to otherwise alter the shape of the
      query, like a predicate
    * The downside is that it cannot be checked until it is used (still at
      compile time) hence errors will be weirder
    * It could generate wildly different SQL depending on the arguments passed
      to it, hence the text cannot be shared.
    * Certainly this form can do anything that a shared fragment can do, but
      with less control.
*/
@macro(cte_tables) counter!(lim! expr)
begin
    cte as (
        select 1 as N
        union all
        select n + 1 N from cte where cte.n < lim!
    )
end;

/* The various forms can be used similarly.  The shared fragment is kind of like
   an inline function compared to the macro being, well, a macro. It's more
   flexible and composes more generally but the usual macro issues.  One issue
   we don't have is text based replacement causing weird order of operations. In
   CQL all macro arguments flow in as AST fragments and remain atomic.  You do
   not have to add extra parens to keep the evaluation consistent like in C.
   Also macros arguments have a certain type so you can't put a statement where
   an expression is expected.
   */

proc test()
begin
    setup();

    -- loop over the shared fragment
    cursor C for with (call counter(5))
    select * from counter;

    loop fetch C
    begin
        printf("C: %d\n", C.N);
    end;

    -- loop over the macro
    cursor D for with counter!(5)
    select N from cte;

    loop fetch D
    begin
        printf("D: %d\n", D.N);
    end;

    -- loop over the view
    cursor E for select * from V1 where N <= 5;
    loop fetch E
    begin
        printf("E: %d\n", E.N);
    end;

end;


@ECHO lua, '
os.exit(test(sqlite3.open(":memory:")))
';

```