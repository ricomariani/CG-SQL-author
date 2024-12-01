---
title: "Chapter 18: Pre-processing"
weight: 18
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Introduction

Pre-processing features are a recent introduction to the CQL language;
previously any pre-processing functionality was provided by running the C
Pre-Processor over the input file before processing. The practice of using
`cc -E` or the equivalent was deprecated because:

 * It creates an unnatural dependence in the compile chain
 * The lexical rules for CQL and C are not fully compatible so `cc -E` often
   gives specious warnings
 * It is not possible to create automatic code formatting tools with text based
   macro replacement
 * Macros are easily abused, creating statement fragments in weird places that
   are hard to understand
 * The usual problems with text replacement and order of operations means that
   macro arguments frequently have to be wrapped to avoid non-obvious errors
 * Debugging problems in the macros is very difficult with line information
   being unhelpful and pre-processed output being nearly unreadable

To address these problems CQL introduced pre-processing features including
structured macros. That is, macros that describe the sort of thing they intend
to produce and the kinds of things they consume.  This allows for reasonable
syntax and type checking and much better error reporting.  To this we also
add `@include` to import code and `@ifdef`/`@ifndef` for conditionals.

### Conditional Compilation

Users can "define" conditional compilation switches using `--defines x y z`
on the command line.  Additionally, if `--rt foo` is specified then
`__rt__foo` will be defined.

>NOTE: that if `-cg` is specified but no `--rt` is specified then
>the default is `--rt c` and so `__rt__c` will be
>defined.

The syntax for conditional compilation is the familiar:

```
@ifdef name
 ... this code will be processed if "name" is defined
@else
 ... this code will be processed if "name" is not defined
@endif
```

The `@else` is optional and the construct nests as one would expect.  `@ifndef`
is also available and simply reverses the sense of the condition.

In order to avoid "rude" macro patterns with `@ifdef` in the middle of SQL or
expressions, this construct is itself a _statement_ in the grammar.  In order to
create conditional expression pieces or other internal pieces you should use one
of the macro types and define it two or more ways.  These design choices were
made to avoid the weird token pasting that inevitably results if pre-processing
is allowed everywhere.  Conditional `cte_tables`, `select_core` and even just
`expr` are highly flexible and give clear composition in the code with no weird
syntax.

Note that in CQL even the code that is conditionally compiled out must at least
_parse_ correctly.  Semantic analysis does not run, and indeed often there would
be conflicts if it did, but the code must at least be correct enough to parse.

Conditionally choosing one of several macro implementations for use later in
the code is a very powerful way to get conditionality throughout your code
cleanly.  `@ifdef` can only appear inside of statement list (`stmt_list`) macros
becasue `@ifdef` is a statement so it can't appear in expressions and query
fragments.   Hence the most powerful pattern is:

```sql
@ifdef something
  @macro(...) foo! begin choice1 end;
@else
  @macro(...) foo! begin choice2 end;
@endif

-- foo! is now conditionally defined
```

### Text Includes

Pulling in common headers is also supported.  The syntax is

```
@include "any/path/foo.sql"
```

In addition to the current directory any paths specified with `--include_paths x
y z` will be checked.


Like the `@ifdef` forms, `@include` can only appear at the statement level, so
it cannot be used to do exotic token pasting like often happens with `#include`.
Furthermore, it must appear at the *top* of files, so it's a lot more like the
import features of other languages than it is like the C pre-Processor token
stream.  Once normal statements begin further includes are not possible, each
file, gets an include section and a statements section.  Note that `@ifdef` and
include _do not_ compose.  Again, `@include` is more like an import.  If you
need conditionals the included item should conditionally produce declarations
and possibly macros.  This means that file dependencies are consistent
regardless of conditionals.

### Macros

A typical macro declaration might look like this:

```sql
@MACRO(STMT_LIST) assert!(exp! expr)
begin
  if not exp! then
    call printf("assertion failed\n");
  end if;
end;

-- Usage

assert!(foo < bar);
```

This example is a macro that produces a statement list (`stmt_list`), so it can
be used in the places where a statement list can appear.  Every macro definition
specifies the nature of the thing it produces, which limits the places that it
can appear.

The nature of macros means that while you may get an error for using the wrong
macro type in the wrong location, you cannot get syntax errors due to the
replacement. Of course semantic errors are still possible, so for instance maybe
the macro references a table that doesn't exist or maybe the table doesn't have
certain necessary columns. Such errors are possible, but the macro is sure to
expand correctly.

Any errors are reported on the lines of the macro not where the macro is used.

### Types of Macros and Macro Arguments

The example in the introduction is a macro that produces a statement list. It
can be used anywhere a statement list would be valid. The full list of macro
types is as follows:

|Type|Notes                                                  |
|---:|:------------------------------------------------------|
|cte_tables|part of the contents of a `WITH` expression      |
|expr|any expression                                         |
|query_parts|something that goes in a `FROM` clause          |
|select_core|one or more select statement that can be unioned|
|select_expr|one or more select named expressions            |
|stmt_list|one more statements                               |

Here are examples that illustrate the various macro types, in alphabetical order
with examples.  The names of the macro types are the same as the same structure
in the grammar so the definition is easy to spot.

*cte_tables*

```sql
@macro(cte_tables) foo!()
begin
  x(a,b) as (select 1, 2),
  y(d,e) as (select 3, 4)
end;

-- all or part of the cte tables in the with clause
with foo!() select * from x join y;
```

*expr*

```sql
@macro(expr) pi!()
begin
   3.14159
end;
```

Macro arguments can have the same types as macros themselves and expressions are
a common choice as we saw in the assert macro.

```sql
@macro(expr) max!(a! expr, b! expr)
begin
  case when a! > b! then a! else b! end
end;

max!(not 3, 1=2);

-- this generates

CASE WHEN (NOT 3) > (1 = 2) THEN NOT 3
ELSE 1 = 2
END;
```

Order of operations isn't a problem with CQL macros, no extra parentheses are
needed for arguments and so forth since the macro drops directly into the syntax
tree.  This means that in the above even though `NOT` is lower precedence than
`>`, the correct expression is generated with no extra effort for the coder. If
the expanded syntax tree is rendered as text with `--echo` and `--exp` like in
the above, any necessary parentheses are added, but the tree is always the right
shape for the arguments.

*query_parts*

A query part macro generates "something you could put in a `from` clause". It
could be the whole `from` clause or it could be one or more of the joined tables.

```sql
@macro(query_parts) foo!(x! expr)
begin
  foo inner join bar on foo.a == bar.a and foo.x == x!
end;

select * from foo!(y);

-- this generates

SELECT *
  FROM foo
  INNER JOIN bar ON foo.a = bar.a AND foo.x = y;
```

*select_core*

A select core macro generates "something you could union".  It's
the part of a select statement that comes before `order by`.  If
you're trying to make a macro that assembles parts of a set of
results which are then unioned and ordered, this is what you need.

```sql
@macro(select_core) foo!()
begin
  select x, y from T
  union all
  select x, y from U
end;

foo!()
union all
select x, y from V
order by x;

-- this generates

SELECT x, y FROM T
UNION ALL
SELECT x, y FROM U
UNION ALL
SELECT x, y FROM V
ORDER BY x;
```

A `select_core` macro can be a useful way to specify a set of tables
and values while leaving filtering and sorting open for customization.

*select_expr*

A select expression macro can let you codify certain common columns and alises
that might might want to select.  Such as:

```sql
@macro(select_expr) foo!()
begin
  T1.x + T1.y as A, T2.u / T2.v * 100 as pct
end;

select foo!() from X as T1 join Y as T2 on T1.id = T2.id;

--- this generates

SELECT T1.x + T1.y AS A, T2.u / T2.v * 100 AS pct
  FROM X AS T1
  INNER JOIN Y AS T2 ON T1.id = T2.id;
```

If certain column extractions are common you can easily make a macro
that lets you pull out the columns you want.  This can be readily
generalized.  This becomes very useful when it's normal to extract
(e.g.) the same 20 columns from various queries.

```sql
@MACRO(SELECT_EXPR) foo!(t1! EXPR, t2! EXPR)
BEGIN
  t1!.x + t1!.y AS A, t2!.u / t2!.v * 100 AS pct
END;

select foo!(X, Y) from X join Y on X.id = Y.id;

-- this generates

SELECT X.x + X.y AS A, Y.u / Y.v * 100 AS pct
  FROM X
  INNER JOIN Y ON X.id = Y.id;
```

In this second case we have provided the table names as arguments rather than
hard coding them.

*stmt_list*

We began with a statement list macro before many of the concepts
had been introduced.  Let's revisit where we started.

```sql
@MACRO(STMT_LIST) assert!(exp! expr)
begin
  if not exp! then
    call printf("assertion failed\n");
  end if;
end;

assert!(1 == 1);

-- this generates

IF NOT 1 = 1 THEN
  CALL printf("assertion failed\n");
END IF;
```

Recall that in SQL order of operations `NOT` is very weak.  This is in contrast
to many other languages where `!` binds quite strongly. But as it happens
we don't have to care.  The expression would have been evaluated correctly
regardless of the binding strength of what surrounds the macro because
the replacement is in the AST not in the text.

This rounds out all of the macro types.

#### Passing Macro Arguments

In order to avoid language ambiguity and to allow macro fragments like
a `cte_table` in unusual locations.  The code must specify the type
of the macro argument.  Expressions are the defaul type, the others
use a function-like syntax to do the job.

|Type|Syntax                                                 |
|---:|:------------------------------------------------------|
|cte_tables|with( x(*) as (select 1 x, 2 y))                 |
|expr|no keyword required  just _foo!(x)_                    |
|query_parts|from(U join V)                                  |
|select_core|rows(select * from U union all select * from V) |
|select_expr|select(1 x, 2 y)                                |
|stmt_list|begin statement1; statement2; end                 |

With these forms the type of macro argument is unambiguous and
can be immediately checked against the macro requirements.

>Note that when using a `select_core` macro or macro argument
>in source it is necessary to do `ROWS(name!)`.  This is an
>unfortunate but unavoidable concession to the grammar tools.

>Note that none of the macro args requires qualifications when
>used in a macro argument context because they can always be
>type checked later, therefore foo!(a!, b!, c!) always works.
>The other macro types require their wrappings to have clean
>grammar.

And example with all of the types:

```sql
@macro(stmt_list) mondo1!(
  a! expr,
  b! query_parts,
  c! select_core,
  d! select_expr,
  e! cte_tables,
  f! stmt_list)
begin
  -- macros can be used without qualification in @ID and @TEXT
  set zz := @text(a!, b!, c!, d!, e!, f!);
end;

@macro(stmt_list) mondo2!(
  a! expr,
  b! query_parts,
  c! select_core,
  d! select_expr,
  e! cte_tables,
  f! stmt_list)
begin
  -- arguments can be forwarded unambigously
  mondo1!(a!, b!, c!, d!, e!, f!);
  if a! then   -- an expression (the most common)
    f!;        -- a statement list (next most common)
  else
    -- these are the parts of a query that you might
    -- want to macroize

    with e!    -- cte tables
    select d!  -- select expressions
    from b!    -- query parts
    union all
    rows(c!);  -- select core
  end if;
end;

-- and this is how you encode each type
mondo2!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );
```

#### Meta Variables

|Variable|Notes|
|--------|-----|
|`@LINE` | The current line number |
|`@MACRO_LINE`|The line where macro expansion began|
|`@MACRO_FILE`|The file where macro expansion began|

`@MACRO_LINE` and `@MACRO_FILE` are useful for providing
error information that refer to the source file that
used the macro rather than the macro itself. Like in
an `assert` macro.  `@LINE` is useful to report problems
in the macro itself, like an invariant.

We can make the assert macro better still:

```sql
@MACRO(STMT_LIST) assert!(exp! expr)
begin
  if not exp! then
    call printf("%s:%d assertion failed: %s\n",
      @MACRO_FILE, @MACRO_LINE, @TEXT(exp!));
  end if;
end;

assert!(1 == 1);

-- this generates

IF NOT 1 = 1 THEN
  CALL printf("%s:%d assertion failed: %s\n", 'myfile.sql', 9, "1 = 1");
END IF;
```

Note that here the macro was invoked on line 9 of myfile.sql.  `@LINE`
would have been much less useful, reporting the line of the `printf`.

#### Token Pasting

You can create new tokens in one of two ways:

* `@TEXT` will create a string from one or more parts.
* `@ID` will make a new identifier from one or more parts
  * If the parts do not concatenate into a valid identifier an error is
    generated.

This can be used to create very powerful code-helpers.  Consider this code,
which is very similar to the actual test helpers in the compiler's test cases.

```sql
@MACRO(stmt_list) EXPECT!(pred! expr)
begin
  if not pred! then
    throw;
  end if;
end;

@MACRO(stmt_list) TEST!(name! expr, body! stmt_list)
begin
  create procedure @ID("test_", name!)()
  begin
    try
      body!;
    catch
      call printf("Test failed %s\n", @TEXT(name!));
      throw;
    end;
  end;
end;

TEST!(try_something,
BEGIN
  EXPECT!(1 == 1);
END);

--- This generates:

CREATE PROC test_try_something ()
BEGIN
  TRY
    IF NOT 1 = 1 THEN
      THROW;
    END IF;
  CATCH
    CALL printf("Test failed %s\n", "try_something");
    THROW;
  END;
END;
```

And of course additional diagnostics can be readily added
(and they are present in the real code). For instance
all of the tricks used in the `assert!` macro would
be helpful in the `expect!` macro.

### Macros for Types

There is no macro form that can stand in for a type name.  However,
identifiers are legal types and so `@ID(...)` is an excellent
construct for creating type names from expressions like strings
or identifiers.  In general, `@ID(...)` can allow you to use
an expression macro where an expression is not legal but a name is.

For instance:

```sql
@macro(stmt_list) make_var!(x! expr, t! expr)
begin
   declare @id(t!,"_var") @id(t!);
   set @id(t!,"_var") := x!;
end;

-- declares real_var as an real and stores 1+5 in it
make_var!(1+5, "real");

--- this generates
DECLARE real_var real;
SET real_var := 1 + 5;
```

Since `@id(...)` can go anywhere an identifier can go, it is not only suitable
for use for type names but also for procedure names, table names -- any
identifer.  As mentioned above `@id` will generate an error if the expression
does not make a legal normal identifier.

### Pipeline syntax for Expression Macros

The pipeline syntax `expr:macro_name!(args...)` can be used instead of
`macro_name!(expr, args)`. This allows macros to appear in expressions written
in the fluent style.  Note that `args` may be empty in which case the form can
be written `expr:macro_name!()` or the even shorter `expr:macro_name!` both of
which become `macro_name!(expr)`

```sql
printf("%s", x:fmt!);
```