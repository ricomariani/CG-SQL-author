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

Pre-processing features are a recent introduction to the CQL language; previously
any pre-processing functionality was provided by running the C Pre-Processor
over the input file before processing. Indeed the practice of using
`cpp` or `cc -E` is still in many examples.  However it is less than ideal.

 * It creates an unnatural dependence in the compile chain
 * The lexical rules for CQL and C are not fully compatible so `cc -E` often gives specious warnings
 * It's not possible to create automatic code formatting tools with text based macro replacement
 * Macros are easily abused, creating statement fragments in weird places that are hard to understand
 * The usual problems with text replacement and order of operations means that macro arguments frequently have to be wrapped to avoid non-obvious errors
 * Debugging problems in the macros is very difficult with line information being unhelpful and pre-processed output being nearly unreadable

To address these problems CQL introduces pre-processing features including
structured macros. That is, macros that describe the sort of thing they intends
to produce and the kinds of things they consume.  This allows for reasonable
syntax and type checking and much better error reporting.  This in addition to
the usual pre-processing features.

### Conditional Compilation

Users can "define" conditional compilation switches using `--defines x y z`
on the command line.  Additionally, if `--rt foo` is specified then
`__rt__foo` will be defined.

>NOTE: that if `-cg` is specified but no `--rt` is specified then
>the default is `--rt c` and so `__rt__c` will be
>defined.  

The syntax is the familiar:

```
@ifdef name
 ... this code will be processed if "name" is defined
@else
... this code will be processed if "name" is not defined
@endif
```

The `@else` is optional and the construct nests as one would expect.  `@ifndef` is also available and simply reverses the sense of the condition.

This construct can appear anywhere in the token stream.

### Text Includes

Pulling in common headers is also supported.  The syntax is

```
@include "any/path/foo.sql"
```

In addition to the current directory any paths specified with `--include_paths x y z` will be checked.


>NOTE: For now, this construct can appear anywhere in the token stream. However, inline uses (like in the middle of an expression) are astonishingly "rude" and limitations that force more sensible locations are likely to appear in the future.  It is recommended that `@include` happen at the statement level. If any expression inclusion is needed a combination of `@include` and macros (see below) is recommended.

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

### Types of Macros and Macro Arguments

The example in the introduction is a macro that produces a statement list.
It can be used anywhere a statement list would be valid.
The full list of macro types is as follows:

|Type|Notes                                                  |
|---:|:------------------------------------------------------|
|cte_tables|part of the contents of a `WITH` expression      |
|expr|any expression                                         |
|query_parts|something that goes in a `FROM` clause          |
|select_core|one or more select statement that can be unioned|
|select_expr|one or more select named expressions            |
|stmt_list|one more statements                               |

Here are examples that illustrate the various macro types, in
alphabetical order with examples.

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

Macro arguments can have the same types as macros themselves
and expressions are a common choice as we saw in the assert macro.

```sql
@macro(expr) max!(a! expr, b! expr)
begin
  case when a! > b! then a! else b! end
end;

max!(not 3, 1==2);

-- this generates

CASE WHEN (NOT 3) > (1 = 2) THEN NOT 3
ELSE 1 = 2
END;
```

Notice that order of operations isn't a problem, since the macro drops directly into the
AST even though `NOT` is lower precedence than `>` the correct expression is generated.
If the AST is rendered as text like in the above, any necessary parentheses are added.

*query_parts*

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

Of course semantic errors are still possible, so for instance maybe the tables
don't exist or they don't have those columns.  But the macro expanion is certain
to be well formed.

*select_core*

A select core macro generates "something you could union".  It's
the parts of a select statement that comes before `order by`.  If
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
|select_core|all(select * from U union all select * from V)  |
|select_expr|select(1 x, 2 y)                                |
|stmt_list|begin statement1; statement2; end                 |

With these forms the type of macro argument is unambiguous and
can be immediately checked against the macro requirements.

#### Stringification

It's often helpful to render a macro argument as text.  Let's
generalize our assert macro a little bit to illustrate.

```sql
@MACRO(STMT_LIST) assert!(exp! expr)
begin
  if not exp! then
    call printf("assertion failed: %s\n", @TEXT(exp!));
  end if;
end;

assert!(1 == 1);

-- this generates

IF NOT 1 = 1 THEN
  CALL printf("assertion failed: %s\n", "1 = 1");
END IF;
```

#### Meta Variables

|Variable|Notes|
|--------|-----|
|`@LINE` | The current line number |
|`@MACRO_LINE`|The line number macro expansion began|
|`@MACRO_FILE`|The file where macro expansion began|

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

You can create new tokens with a two step process:

  * `@TEXT` will create a string from one or more parts.
  * `@ID` will make a new identifier from one or more parts
    * If the parts do not concatenate into a valid identifier an error is generated.


This can be used to create very powerful code-helpers.  Consider this code,
which is very similar to the actual test helpers in the compiler's test
cases.

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
    begin try
      body!;
    end try;
    begin catch
      call printf("Test failed %s\n", @TEXT(name!));
      throw;
    end catch;
  end;
end;

TEST!(try_something,
BEGIN
  EXPECT!(1 == 1);
END);

--- This generates:

CREATE PROC test_try_something ()
BEGIN
  BEGIN TRY
    IF NOT 1 = 1 THEN
      THROW;
    END IF;
  END TRY;
  BEGIN CATCH
    CALL printf("Test failed %s\n", "try_something");
    THROW;
  END CATCH;
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
or identifiers.

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

Since @id(...) can go anywhere an identifier can go, it is totally
suitable for use for type names but also for procedure names, table
names, any identifer.  As mentioned above `@id` will generate an
error if the expression does not make a legal normal identifier.