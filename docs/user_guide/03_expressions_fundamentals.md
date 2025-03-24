---
title: "Chapter 3: Expression Fundamentals"
weight: 3
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

Until this point we've only discussed simple kinds of expressions as well as
variables and table columns marked with `NOT NULL`. These are indeed the easiest
types for CQL to work with as they tend to correspond most directly to the types
known to C. However, SQL provides for many more types of expressions as well as
nullable types, and these require handling in any language that purports to be
like SQL.

### Expression Examples

The usual arithmetic operators apply in CQL:

Example expressions (these are all true)

```
(1 + 2) * 3 == 9
1 + 2 * 3 == 7
6 / 3 == 2
7 - 5 == 2
6 % 5 == 1
5 / 2.5 == 2
7 & 3 == 2 | 1
1 << 2 == 4
```
However, before going any further, it's important to note that CQL is inherently
a two-headed beast. Expressions are either evaluated by transpiling to C (like
the predicate of an IF statement or a variable assignment) or by sending them
to SQLite for evaluation (like expressions inside a `SELECT` statement or the
`WHERE` part of a `DELETE`).

CQL evaluation rules are designed to be as similar as possible, but some variance
is inevitable because evaluation is done in two fundamentally different ways.

### Operator Precedence

The operator precedence rules in CQL are as follows; the top-most rule binds the
most loosely, and the bottom-most rule binds the most tightly:

```
ASSIGNMENT:     := += -= /= *= %= &= |= <<= >>=
LOGICAL_OR:     OR
LOGICAL_AND:    AND
LOGICAL_NOT:    NOT
EQUALITY:       = == != <>  IS [NOT], [NOT] IN, [NOT] LIKE,
                [NOT] MATCH, [NOT] GLOB, [NOT] BETWEEN
INEQUALITY:     <  <=  >  >=
BINARY:         << >> & |
ADDITION:       + -
MULTIPLICATION: * / %
CONCAT:         || -> ->>
COLLATE:        COLLATE
UNARY:          ~  -
SPECIAL:        x[] x:y x::y x:::y x.y f(y) CAST CASE ~type~
```

The above rules are **not** the same as C's operator precedence rules! Instead,
CQL follows SQLite's rules. Parentheses are emitted in the C output as needed to
force that order.

>NOTE: CQL emits minimal parentheses in all outputs. Different parentheses are
>often needed for SQL output as opposed to C output.

### Order of Evaluation

In contrast to C, CQL guarantees a left-to-right order of evaluation for
arguments. This applies both to arguments provided to the operators mentioned in
the previous section as well as arguments provided to procedures.

### Variables, Columns, Basic Types, and Nullability

CQL needs type information for both variables in the code and columns in the
database. Like SQL, CQL allows variables to hold a NULL value, and just as in SQL,
the absence of `NOT NULL` implies that `NULL` is a legal value. Consider these
examples:

```sql
-- real code should use better names than this :)
create table all_the_nullables(
  i1 integer,
  b1 bool,
  l1 long,
  r1 real,
  t1 text,
  bl1 blob
);

declare i2 integer;
declare b2 bool;
declare l2 long;
declare r2 real;
declare t2 text;
declare bl2 blob;
```

All of `i1`, `i2`, `b1`, `b2`, `l1`, `l2`, `r1`, `r2`, `t1`, `t2`, and `bl1`,
`bl2` are nullable. In some sense, variables and columns declared nullable (by
virtue of the missing `NOT NULL`) are the root sources of nullability in the SQL
language. That and the `NULL` literal. Though there are other sources as we
will see.

`NOT NULL` could be added to any of these, e.g.

```sql
-- real code should use better names than this :)
declare i_nn int!;
```

In fact, `NOT NULL` is so common in CQL code that it can be abbreviated with a
single `!` character. Some languages use `?` to make a type nullable, but since
nullable is the default in SQL, CQL opts for the reverse. Hence, the following
code is equivalent to the above:

```sql
-- "int" is equivalent to "integer" and "!" is equivalent to "not null"
declare i_nn int!;
```

In the context of computing the types of expressions, CQL is statically typed,
and so it must make a decision about the type of any expression based on the
type information at hand at compile time. As a result, it handles the static
type of an expression conservatively. If the result might be null, then the
expression is of a nullable type, and the compiled code will include an
affordance for the possibility of a null value at runtime.

The generated code for nullable types is considerably less efficient, and so it
should be avoided if that is reasonably possible.

#### Quoted Identifiers

In places where a SQL name is allowed, such as a table name, column name, index
name, trigger name, or constraint name, a back-quoted identifier may be used.
This allows for the more flexible names supported by SQLite to appear anywhere
they might be needed.

Example:

```sql

  create table `my table` (
    `a column` integer
  );
```

Since SQL names "leak" into the language via cursors, other places a SQL name
might appear have similar flexibility. For instance, names of variables, and
columns in cursors can have exotic names.

When rendered to SQL, the name will be emitted like so:

```sql
  [my table]
```

If the name goes to C or Lua, it has to be escaped and rendered like so:

```C
  X_aX20table
```

In this form, non-identifier characters are escaped into hex. This is invisible to
users of CQL, but the C or Lua interface to such columns necessarily uses the
escaped names. While this is less than perfect, it is the only way to allow
access to any legal SQL name.

#### LET Statement

You can declare and initialize a variable in one step using the `LET` form, e.g.

```sql
LET x := 1;
```

The named variable is declared to be the exact type of the expression on the
right. More on expressions in the coming sections. The right side is often a
constant in these cases but does not need to be.

```sql
LET i := 1;       -- integer not null
LET l := 1L;      -- long not null
LET t := "x";     -- text not null
LET b := x IS y;  -- bool not null
LET b := x = y;   -- bool (maybe not null depending on x/y)
```

The pseudo-function "nullable" removes `not null` from the type of
its argument but otherwise does no computation. This can be useful to
initialize nullable types.

```sql
LET n_i := nullable(1);   -- nullable integer variable initialized to 1
LET n_l := nullable(1L);  -- nullable long variable initialized to 1
```

The pseudo-function "sensitive" adds `@sensitive` to the type of its
argument but otherwise does no computation. This also can be useful to
initialize nullable types.

```sql
LET s_i := sensitive(1);   -- sensitive nullable integer variable initialized to 1
LET s_l := sensitive(1L);  -- sensitive nullable long variable initialized to 1
```

#### The `@RC` special variable

CQL also has the special built-in variable `@RC`, which refers to the most recent
error code returned by a SQLite operation, e.g., 0 == `SQLITE_OK`, 1 ==
`SQLITE_ERROR`. `@RC` is of type `integer not null`. Specifically:

* Each catch block captures the error code when it is entered into its own local
  variable.
* The hidden variable is created lazily, so it only exists if it is used.
  * The variable is called `_rc_thrown_n` where n is the catch block number in
    the procedure.
* Any reference to `@RC` refers to the above error variable of the innermost
  catch block the `@RC` reference is in.
* If the `@RC` reference happens outside of any catch block, its value is
  `SQLITE_OK` (i.e., zero).

### Types of Literals

There are a number of literal objects that may be expressed in CQL.
These are as follows:

#### String Literals

* A double quoted string is a C style string literal.
  * The usual simple C escape sequences are supported.
  * The \xNN form for embedded hex characters is supported, however.
  * The \0NNN octal form is not supported, and.
  * Embedded nulls in string literals (\0 or \0x00) are not supported (you must
    use blobs in such cases).
* A single quoted string is a SQL style string literal.
  * No escape sequences are supported other than `''` to indicate a single quote
    character (this is just like normal SQLite).
* A sequence of single or double quoted strings separated by whitespace such as
  "xx" 'yy' "zz" which are concatenated to make one literal.
* The sequence @FILE("some_string") is a special string literal.
  * The value of this literal is the path of the current compiland starting at
    the letters in `some_string`, or, the entire path of the current compiland
    if `some_string` does not occur in the path.
  * The purpose of the `@FILE` construct is to provide a partial path to a file
    for diagnostics that is consistent even if the file is built in various
    different root paths on different build machines.

#### Blob Literals

* SQLite Blob literals are supported in SQL contexts (i.e., where they will be
  processed by SQLite). CQL produces an error if you attempt to use a blob
  literal in a loose expression.

#### Numeric Literals

* All numeric literals are considered to be positive; negative numbers are
  actually a positive literal combined with unary minus (the negation operator).
* Base 10 and hexadecimal literals are supported.
* Literals with a decimal point are of type `REAL` and stored as the C type
  `double`.
* Literals that can fit in a signed integer without loss and do not end in the
  letter `L` are integer literals.
* Larger literals, or those ending with the letter `L`, are long integer
  literals.
* Literals that begin with 0x are interpreted as hex.

Examples:

```sql
  1.3            -- real
  2L             -- long
  123456789123   -- long
  123            -- integer
  0x10           -- hex integer
  0x10L          -- hex long integer
```

#### The NULL literal

The use of `NULL` always results in a nullable result; however, this literal is
special in that it has no storage class. `NULL` is neither a numeric nor a string
itself but rather mutates into whatever it is first combined with. For instance,
`NULL + 1` results in a nullable integer. Because `NULL` has no primitive type,
in some cases where type knowledge is required, you might have to use the
`CAST()` function to cast `NULL` to a specific type, such as `CAST(NULL as TEXT)`.
This construct guarantees type consistency in cases like `SELECT` from
different sources combined with `UNION ALL`.

> NOTE: Constructs like `CAST(NULL as TEXT)` are always rewritten to just `NULL`
> before going to SQLite as the cast is uninteresting except for the type
> information, which SQLite doesn't need/use anyway.

> NOTE: The trailing cast notation is often helpful for economy here, e.g.
> `NULL ~TEXT~` is a lot shorter than `CAST(NULL AS TEXT)` and is identical.
> SQLite will never see the shorthand version, it is converted immediately.

#### Boolean Literals

The boolean literals `TRUE` and `FALSE` (case insensitive) may be used freely.
These are the same as the normal literals `0` and `1` except they have type
`BOOL`. They mix with numbers in the usual ways with the usual promotion rules.

> NOTE: Even if the target language is Lua, you can mix and match bools and
> integers in CQL. The compiler will emit casts if needed.

#### Other Considerations

The C pre-processor can still be combined with CQL, in which case the `__FILE__`
and `__LINE__` directives of the pre-processor may be used to create literals;
they will be preprocessed into normal literals.

The use of `__FILE__` can give surprising results in the presence of build
systems; hence, the existence of `@FILE(...)`.

Use of the C-pre-processor is _deprecated_.

### Const and Enumerations

It's possible to use named constants in CQL with nothing more than the
pre-processor features that have already appeared; however, the use of macros in
such a way is not entirely satisfactory. For one thing, macros are expanded
before semantic analysis, which means CQL can't provide macro constant values for
you in the JSON output, for instance.

To help with this problem, CQL includes specific support for constants. They can
be in the form of enumerations of a fixed type or general-purpose ad hoc constants.
We'll see both in the sections to follow.

```sql
enum business_type int (
  restaurant,
  laundromat,
  corner_store = 11 + 3  /* math added for demo purposes only */
);
```

After this enum is declared, this:

```sql
select business_type.corner_store;
```

is the same as this:

```sql
select 14;
```

And that is exactly what SQLite will see: the literal `14`.

You can also use an enum type to define columns whose type is more specific than
just `integer`, like so:

```sql
CREATE TABLE businesses (
  name TEXT,
  type business_type
);
```

CQL will then enforce that you use the correct enum to access those columns. For
example, this is valid:

```sql
SELECT * FROM businesses WHERE type = business_type.laundromat;
```

While this does not type check, even if state.delaware is a numeric code for the state:

```sql
SELECT * FROM businesses WHERE type = state.delaware;
```

Enumerations follow these rules:

* The enumeration can be any numeric type (bool, integer, long integer, real).
* The values of the enumeration start at 1 (i.e., if there is no `= expression`,
  the first item will be `1`, not `0`).
* If you don't specify a value, the next value is the previous value plus one.
* If you do specify a value, it can be any constant expression, and it will be
  cast to the type of the enumeration (even if that is lossy).
* The enumeration can refer to previous values in itself with no qualification
  `(big = 100.0, medium = big/2, small = medium/2)`.
* The enumeration can refer to previously defined enumerations as usual `(code =
  business_type.restaurant)`.
* Once the enumeration is defined, you refer to its members in a fully qualified
  fashion `enum_name.member_name` elsewhere.

With these forms, you get some additional useful output:
* The JSON includes the enumerations and their values in their own section.
* You can use the `@emit_enums` directive to put declarations like this into the
  `.h` file that corresponds to the current compiland.

```c
enum business_type {
  business_type__restaurant = 1,
  business_type__laundromat = 2,
  business_type__corner_store = 14
};
```

Note that C does not allow for floating-point enumerations, so in case of
floating-point values such as:

```sql
enum floating real (
  one = 1.0,
  two = 2.0,
  e = 2.71828,
  pi = 3.14159
);
```

you get:

```c
// enum floating (floating point values)
#define floating__one 1.000000e+00
#define floating__two 2.000000e+00
#define floating__e 2.718280e+00
#define floating__pi 3.141590e+00
```
In Lua output the compiler creates a call to `cql_emit_constants` like so:

```lua
  cql_emit_constants("enum", "business_type", {
    restaurant = 1,
    laundromat = 2,
    corner_store = 14
  })
```

By default this function adds the indicated constants to the global dictionary
`_cql` but you can override this to do whatever you like with the constants.

#### Constant Folding

In order to get useful expressions in enumeration values, constant folding and
general evaluation were added to the compiler; these expressions work on any
numeric type and the literal `NULL`. The supported operations include:

`+`, `-`, `*`, `/`, `%`, `|`, `&`, `<<`, `>>`, `~`, `and`, `or`, `not`,
`==`, `<=`, `>=`, `!=`, `<`, `>`, the `CAST` operator, and the `CASE` forms
(including the `IIF` function). These operations are enough to make a lot of
very interesting expressions, all of which are evaluated at compile time.

Constant folding was added to allow for rich `enum` expressions, but there is
also the `const()` primitive in the language which can appear anywhere a literal
could appear. This allows you to do things like:

```sql
create table something(
  x int default const((1<<16)|0xf) /* again the math is just for illustration */
);
```

The `const` form is also very useful in macros to force arguments to be
constants and so forth.

This `const` form ensures that the constant will be evaluated at compile time. The
`const` pseudo-function can also nest so you can build these kinds of macros
from other macros or you can build enum values this way. Anywhere you might need
literals, you can use `const`.

### Constant Groups

Constant groups are more general than enumerations but very similar.  This statement
declares named global constants of any type.

```sql
declare const group some_constants (
  my_x = cast(5 as int<job_id>),
  my_y = 12.0,
  my_z = 'foo'
);
```

As with enums, referring to `my_x`, `my_y`, or `my_z` after this will cause the
appropriate constant value to be inlined into the code.  The output code carries
no symbolic reference to the constant.  However, similarly to enums, if you wish
the constant to be consumable by external code you can use:


```sql
@emit_const_groups some_constant;
```

This causes

```C
#ifndef const_group_some_constants_defined
#define const_group_some_constants_defined

#define my_x 5
#define my_y 1.200000e+01
#define my_z "foo"

#endif
```

To go into the header file for C.  For Lua you instead get this call:

```lua
  cql_emit_constants("const", "some_constants", {
    my_x = 5,
    my_y = 1.200000e+01,
    my_z = "foo"
  })
```

You can use this call to create whatever constant dictionary or dictionaries you want
by overriding `cql_emit_constants`.  By default they are added to a global dictionary
named `_cql`

### Named Types

A common source of errors in stored procedures is incorrect typing in variables
and arguments. For instance, a particular key for an entity might need to be
`LONG`, `LONG NOT NULL` or even `LONG NOT NULL @SENSITIVE`. This requires you to
diligently get the type right in all the places it appears, and should it ever
change, you have to revisit all the places.

To help with this situation, and to make the code a little more self-describing,
we added named types to the language. This is a lot like `typedef` in the C
language. These definitions do not create different incompatible types, but they
do let you name types for reuse.

You can now write these sorts of forms:

```sql
type foo_id long!;

create table foo(
  id foo_id primary key autoincrement,
  name text
);

create proc inserter(name_ text, out id foo_id)
begin
  insert into foo(id, name) values(NULL, name_);
  set id := last_insert_rowid();
end;

func func_return_foo_id() foo_id;

var v foo_id;
```

Additionally any enumerated type can be used as a type name.  e.g.

```sql
enum thing int (
  thing1,
  thing2
);

type thing_type thing;
```

Enumerations always include "not null" in addition to their base type. Enumerations
also have a unique "kind" associated; specifically, the above enum has the type
`integer<thing> not null`. The rules for type kinds are described below.

### Type Kinds

Any CQL type can be tagged with a "kind"; for instance, `real` can become
`real<meters>`, `integer` can become `integer<job_id>`. The idea here is that
the additional tag, the "kind", can help prevent type mistakes in arguments, in
columns, and in procedure calls. For instance:

```sql
create table things(
  size real<meters>,
  duration real<seconds>
);

create proc do_something(size_ real<meters>, duration_ real<seconds>)
begin
  insert into things(size, duration) values(size_, duration_);
end;
```

In this situation, you couldn't accidentally switch the columns in `do_something`
even though both are `real`, and indeed SQLite will only see the type `real` for
both. If you have your own variables typed `real<size>` and `real<duration>`,
you can't accidentally do:

```sql
  call do_something(duration, size);
```

even though both are real. The type kind won't match.

Importantly, an expression with no type kind is compatible with any type kind
(or none). Hence all of the below are legal.

```sql
var generic real;
set generic := size;        -- no kind may accept <meters>
set generic := duration;    -- no kind may accept <seconds>
set duration := generic;    -- no kind may be stored in <seconds>
```

Only mixing types where both have a kind, and the kind is different, generates
errors. This choice allows you to write procedures that (for instance) log any
`integer` or any `real`, or that return an `integer` out of a collection.

These rules are applied to comparisons, assignments, column updates, anywhere
and everywhere types are checked for compatibility.

To get the most value out of these constructs, the authors recommend that type
kinds be used universally except when the extra compatibility described above is
needed (like low-level helper functions).

Importantly, type kind can be applied to object types as well, allowing
`object<dict>` to be distinct from `object<list>`.

At runtime, the kind information is lost. But it does find its way into the
JSON output so external tools also get to see the kinds.

### Nullability

#### Nullability Rules

Nullability is tracked via CQL's type system. To understand whether or not an
expression will be assigned a nullable type, you can follow these rules; they
will hopefully be intuitive if you are familiar with SQL:

The literal `NULL` is, of course, always assigned a nullable type. All other
literals are non-null.

In general, the type of an expression involving an operator (e.g., `+`, `==`,
`!=`, `~`, `LIKE`, et cetera) is nullable if any of its arguments are
nullable. For example, `1 + NULL` is assigned the type `INTEGER`, implying
nullability. `1 + 2`, however, is assigned the type `INTEGER NOT NULL`.

`IN` and `NOT IN` expressions are assigned a nullable type if and only if
their left argument is nullable: The nullability of the right side is
irrelevant. For example, `"foo" IN (a, b)` will always have the type `BOOL NOT
NULL`, whereas `some_nullable IN (a, b)` will have the type `BOOL`.

> NOTE: In CQL, the `IN` operator behaves like a series of equality tests (i.e.,
> `==` tests, not `IS` tests), and `NOT IN` behaves symmetrically. SQLite has
> slightly different nullability rules for `IN` and `NOT IN`. *This is the one
> place where CQL has different evaluation rules from SQLite, by design.*

The result of `IS` and `IS NOT` is always of type `BOOL NOT NULL`, regardless
of the nullability of either argument.

For `CASE` expressions, the result is always of a nullable type if no `ELSE`
clause is given. If an `ELSE` is given, the result is nullable if any of the
`THEN` or `ELSE` expressions are nullable.

> NOTE: The SQL `CASE` construct is quite powerful: Unlike the C `switch`
> statement, it is actually an expression. In this sense, it is rather more like
> a highly generalized ternary `a ? b : c` operator than a C switch statement.
> There can be arbitrarily many conditions specified, each with their own result,
> and the conditions need not be constants; typically, they are not.

`IFNULL` and `COALESCE` are assigned a `NOT NULL` type if one or more of their
arguments are of a `NOT NULL` type.

In most join operations, the nullability of each column participating in the
join is preserved. However, in a `LEFT OUTER` join, the columns on the right
side of the join are always considered nullable; in a `RIGHT OUTER` join, the
columns on the left side of the join are considered nullable.

As in most other languages, CQL does not perform evaluation of value-level
expressions during type checking. There is one exception to this rule: An
expression within a `const` is evaluated at compilation time, and if its
result is then known to be non-null, it will be given a `NOT NULL` type. For
example, `const(NULL or 1)` is given the type `BOOL NOT NULL`, whereas merely
`NULL or 1` has the type `BOOL`.


#### Nullability Improvements

CQL is able to "improve" the type of some expressions from a nullable type to a
`NOT NULL` type via occurrence typing, also known as flow typing. There are
three kinds of improvements that are possible:

Positive improvements, i.e., improvements resulting from the knowledge that
some condition containing one or more `AND`-linked `IS NOT NULL` checks must
have been _true_:

##### `IF` statements:

```sql
IF a IS NOT NULL AND c.x IS NOT NULL THEN
  -- `a` and `c.x` are not null here
ELSE IF b IS NOT NULL THEN
  -- `b` is not null here
END IF;
```

##### `CASE` expressions:

```sql
CASE
  WHEN a IS NOT NULL AND c.x IS NOT NULL THEN
    -- `a` and `c.x` are not null here
  WHEN b IS NOT NULL THEN
    -- `b` is not null here
  ELSE
    ...
END;
```

##### `IIF` expressions:

```sql
IIF(a IS NOT NULL AND c.x IS NOT NULL,
  ..., -- `a` and `c.x` are not null here
  ...
)
```

##### `SELECT` expressions:

```sql
SELECT
  -- `t.x` and `t.y` are not null here
FROM t
WHERE x IS NOT NULL AND y IS NOT NULL
```

Negative improvements, i.e., improvements resulting from the knowledge that
some condition containing one or more `OR`-linked `IS NULL` checks must have
been _false_:

##### `IF` statements:

```sql
IF a IS NULL THEN
  ...
ELSE IF c.x IS NULL THEN
  -- `a` is not null here
ELSE
  -- `a` and `c.x` are not null here
END IF;
```

##### `IF` statements, guard pattern:

```sql
IF a IS NULL RETURN;
-- `a` is not null here

IF c.x IS NULL THEN
  ...
  THROW;
END IF;
-- `a` and `c.x` are not null here
```

##### `CASE` expressions:

```sql
CASE
  WHEN a IS NULL THEN
    ...
  WHEN c.x IS NULL THEN
    -- `a` is not null here
  ELSE
    -- `a` and `c.x` are not null here
END;
```

##### `IIF` expressions:

```sql
IIF(a IS NULL OR c.x IS NULL,
  ...,
  ... -- `a` and `c.x` are not null here
)
```

Assignment improvements, i.e., improvements resulting from the knowledge that
the right side of a statement (or a portion therein) cannot be `NULL`:

##### `SET` statements:

```sql
SET a := 42;
-- `a` is not null here
```

>NOTE: Assignment improvements from `FETCH` statements are not currently
>supported. This may change in a future version of CQL.

There are several ways in which improvements can cease to be in effect:

The scope of the improved variable or cursor field has ended:

```sql
IF a IS NOT NULL AND c.x IS NOT NULL THEN
  -- `a` and `c.x` are not null here
END IF;
-- `a` and `c.x` are nullable here
```

An improved variable was `SET` to a nullable value:

```sql
IF a IS NOT NULL THEN
  -- `a` is not null here
  SET a := some_nullable;
  -- `a` is nullable here
END IF;
```

An improved variable was used as an `OUT` (or `INOUT`) argument:

```sql
IF a IS NOT NULL THEN
  -- `a` is not null here
  CALL some_procedure_that_requires_an_out_argument(a);
  -- `a` is nullable here
END IF;
```

An improved variable was used as a target for a `FETCH` statement:

```sql
IF a IS NOT NULL THEN
  -- `a` is not null here
  FETCH c INTO a;
  -- `a` is nullable here
END IF;
```

An improved cursor field was re-fetched:

```sql
IF c.x IS NOT NULL THEN
  -- `c.x` is not null here
  FETCH c;
  -- `c.x` is nullable here
END IF;
```

A procedure call was made (which removes improvements from _all globals_
because the procedure may have mutated any of them; locals are unaffected):

```sql
IF a IS NOT NULL AND some_global IS NOT NULL THEN
  -- `a` and `some_global` are not null here
  CALL some_procedure();
  -- `a` is still not null here
  -- `some_global` is nullable here
END IF;
```

CQL is generally smart enough to understand the control flow of your program and
infer nullability appropriately; here are a handful of examples:

```sql
IF some_condition THEN
  SET a := 42;
ELSE
  THROW;
END IF;
-- `a` is not null here because it must have been set to 42
-- if we've made it this far
```

```sql
IF some_condition THEN
  SET a := 42;
ELSE
  SET a := 100;
END IF;
-- `a` is not null here because it was set to a value of a
-- `NOT NULL` type in all branches and the branches cover
-- all of the possible cases
```

```sql
IF a IS NOT NULL THEN
  IF some_condition THEN
    SET a := NULL;
  ELSE
    -- `a` is not null here despite the above `SET` because
    -- CQL understands that, if we're here, the previous
    -- branch must not have been taken
  END IF;
END IF;
```

```sql
IF a IS NOT NULL THEN
  WHILE some_condition
  BEGIN
    -- `x` is nullable here despite `a IS NOT NULL` because
    -- `a` was set to `NULL` later in the loop and thus `x`
    -- will be `NULL` when the loop repeats
    LET x := a;
    SET a := NULL;
    ...
  END;
END IF;
```

##### Regarding Conditions

For positive improvements, the check must be exactly of the form `IS NOT NULL`;
other checks that imply a variable or cursor field must not be null when true
have no effect:

```sql
IF a > 42 THEN
  -- `a` is nullable here
END IF;
```

>NOTE: This may change in a future version of CQL.

For multiple positive improvements to be applied from a single condition, they
must be linked by `AND` expressions along the outer spine of the condition;
uses of `IS NOT NULL` checks that occur as subexpressions within anything
other than `AND` have no effect:

```sql
IF
  (a IS NOT NULL AND b IS NOT NULL)
  OR c IS NOT NULL
THEN
  -- `a`, `b`, and `c` are all nullable here
END IF;
```

For negative improvements, the check must be exactly of the form `IS NULL`;
other checks that imply a variable or cursor field must not be null when false
have no effect:

```sql
DECLARE equal_to_null INT;
IF a IS equal_to_null THEN
  ...
ELSE
  -- `a` is nullable here
END IF;
```

For multiple negative improvements to be applied from a single condition, they
must be linked by `OR` expressions along the outer spine of the condition;
uses of `IS NULL` checks that occur as subexpressions within anything other
than `OR` have no effect:

```sql
IF
  (a IS NULL OR b IS NULL)
  AND c IS NULL
THEN
  ...
ELSE
  -- `a`, `b`, and `c` are all nullable here
END IF;
```

#### Forcing Nonnull Types

If possible, it is best to use the techniques described in "Nullability
Improvements" to verify that the value of a nullable type is nonnull before
using it as such.

Sometimes, however, you may know that a value with a nullable type cannot be
null and simply wish to use it as though it were nonnull. The `ifnull_crash`
and `ifnull_throw` "attesting" functions convert the type of an expression to be
nonnull and ensure that the value is nonnull with a runtime check. They cannot
be used in SQLite contexts because the functions are not known to SQLite, but
they can be used in loose expressions. For example:

```sql
CREATE PROC square_if_odd(a INT!, OUT result INT)
BEGIN
  IF a % 2 = 0 THEN
    SET result := NULL;
  ELSE
    SET result := a * a;
  END IF;
END;

-- `x` has type `INT`, but we know it can't be `NULL`
let x := square_if_odd(3);

-- `y` has type `INT NOT NULL`
let y := ifnull_crash(x);
```

Above, the `ifnull_crash` attesting function is used to coerce the expression
`x` to be of type `INT NOT NULL`. If our assumptions were somehow wrong,
however—and `x` were, in fact, `NULL`—our program would crash.

As an alternative to crashing, you can use `ifnull_throw`. The following two
pieces of code are equivalent:

```sql
CREATE PROC y_is_not_null(x INT)
BEGIN
  let y := ifnull_throw(x);
END;
```

```sql
CREATE PROC y_is_not_null(x INT)
BEGIN
  VAR y INT!;
  IF x IS NOT NULL THEN
    SET y := x;
  ELSE
    THROW;
  END IF;
END;
```

### Expression Types

CQL supports a variety of expressions, nearly everything from the SQLite world.
The following are the various supported operators; they are presented in order
from the weakest binding strength to the strongest. Note that the binding order
is NOT the same as C, and in some cases, it is radically different (e.g., boolean
math)

#### UNION and UNION ALL

These appear only in the context of `SELECT` statements. The arms of a
compound select may include `FROM`, `WHERE`, `GROUP BY`, `HAVING`, and
`WINDOW`. If `ORDER BY` or `LIMIT ... OFFSET` are present, these apply
to the entire UNION.

Example:

```sql
select A.x x from A inner join B using(z)
union all
select C.x x from C
where x = 1;
```
The `WHERE` applies only to the second select in the union.  And each
`SELECT` is evaluated before the the `UNION ALL`

```sql
select A.x x from A inner join B using(z)
where x = 3
union all
select C.x x from C
where x = 1
order by x;
```

The `ORDER BY` applies to the result of the union, so any results from the 2nd
branch will sort before any results from the first branch (because `x` is
constrained in both).

#### Assignment

Assignment occurs in the `UPDATE` statement, in the `SET` and `LET` statements, and
in various implied cases like the `+=` operator. In these cases, the left side is a simple target and the right side is a general expression. The expression is evaluated before the assignment.

>NOTE: In cases where the left-hand side is an array or property, the assignment is actually
>rewritten to call a suitable setter function, so it isn't actually an assignment at all.

Example:

```sql
SET x := 1 + 3 AND 4;  -- + before AND then :=
```

#### Logical OR

The logical `OR` operator performs shortcut evaluation, much like the C `||`
operator (not to be confused with SQL's concatenation operator with the same
lexeme).  If the left side is true, the result is true, and the right side is not
evaluated.

The truth table for logical `OR` is as follows:

| A    | B     | A OR B  |
|:----:|:-----:|:-------:|
| 0    |  0    |  0      |
| 0    |  1    |  1      |
| 0    |  NULL |  NULL   |
| 1    |  0    |  1      |
| 1    |  1    |  1      |
| 1    |  NULL |  1      |
| NULL |  0    |  NULL   |
| NULL |  1    |  1      |
| NULL |  NULL |  NULL   |


#### Logical AND

The logical `AND` operator performs shortcut evaluation, much like the C `&&`
operator. If the left side is false, the result is false, and the right side is not
evaluated.

The truth table for logical `AND` is as follows:

| A    | B     | A AND B |
|:----:|:-----:|:-------:|
| 0    |  0    |  0      |
| 0    |  1    |  0      |
| 0    |  NULL |  0      |
| 1    |  0    |  0      |
| 1    |  1    |  1      |
| 1    |  NULL |  NULL   |
| NULL |  0    |  0      |
| NULL |  1    |  NULL   |
| NULL |  NULL |  NULL   |


#### BETWEEN and NOT BETWEEN

These are ternary operators.  The general forms are:

```sql
  expr1 BETWEEN expr2 AND expr3
  expr1 NOT BETWEEN expr2 AND expr3
```

Importantly, there is an inherent ambiguity in the language because `expr2` or
`expr3` above could be logical expressions that include `AND`. CQL resolves this
ambiguity by insisting that `expr2` and `expr3` be "math expressions" as defined
in the CQL grammar. These expressions may not have ungrouped `AND` or `OR`
operators.

Examples:

```sql
-- oh hell no (syntax error)
a between 1 and 2 and 3;

-- all ok
a between (1 and 2) and 3;
a between 1 and (2 and 3);
a between 1 and b between c and d; -- binds left to right
a between 1 + 2 and 12 / 2;
```

#### Logical NOT

The one operand of logical `NOT` must be a numeric.  `NOT 'x'` is illegal.

#### Non-ordering tests `!=`, `<>`, `=`, `==`, `LIKE`, `GLOB`, `MATCH`, `REGEXP`, `IN`, `IS`, `IS NOT`

These operations do some non-ordered comparison of their two operands:
* `IS` and `IS NOT` never return `NULL`,  So for instance `X IS NOT NULL` gives
  the natural answer.  `x IS y` is true if and only if: 1. both `x` and `y` are
  `NULL` or 2. if they are equal.
* The other operators return `NULL` if either operand is `NULL` and otherwise
  perform their usual test to produce a boolean.
* `!=` and `<>` are equivalent as are `=` and `==`.
* Strings and blobs compare equal based on their value, not their identity (i.e.,
  not the string/blob pointer).
* Objects compare equal based on their address, not their content (i.e.,
  reference equality).
* `MATCH`, `GLOB`, and `REGEXP` are only valid in SQL contexts, `LIKE` can be
  used in any context (a helper method to do `LIKE` in C is provided by SQLite,
  but not the others).
* `MATCH`, `GLOB`, `REGEXP`, `LIKE`, and `IN` may be prefixed with `NOT` which
  reverses their value.

```sql
 NULL IS NULL  -- this is true
(NULL == NULL) IS NULL  -- this is also true because NULL == NULL is not 1, it's NULL.
(NULL != NULL) IS NULL  -- this is also true because NULL != NULL is not 0, it's also NULL.
'xy' NOT LIKE 'z%'` -- this is true
```

#### Ordering comparisons `<`, `>`, `<=`, `>=`

These operators perform the usual order comparison of their two operands:

* If either operand is `NULL`, the result is `NULL`.
* Objects and blobs may not be compared with these operands.
* Strings are compared based on their value (as with other comparisons), not
  their address.
* Numerics are compared as usual with the usual promotion rules.

> NOTE: CQL uses `strcmp` for string comparison. In SQL expressions, the
> comparison happens in whatever way SQLite has been configured. Typically,
> general-purpose string comparison should be done with helper functions that
> deal with collation and other considerations. This is a very complex topic and
> CQL is largely silent on it.

#### Bitwise operators `<<`, `>>`, `&`, `|`

These are the bit-manipulation operations. Their binding strength is **very**
different from C, so beware. Notably, the `&` operator has the same binding
strength as the `|` operator, so they bind left to right, which is utterly
unlike most systems. Many parentheses are likely to be needed to correctly
codify the usual "or of ands" patterns.

Likewise, the shift operators `<<` and `>>` have the same strength as `&` and `|`,
which is very atypical. Consider:

```sql
x & 1 << 7;    -- not ambiguous but unusual meaning, not like C or Lua
(x & 1) << 7;  -- means the same as the above
x & (1 << 7)   -- probably what you intended
```

Note that these operators only work on integer and long integer data. If any
operand is `NULL`, the result is `NULL`.

#### Addition and Subtraction `+`, `-`

These operators perform the typical arithmetic operations. Note that there are no
unsigned numeric types, so it's always signed arithmetic that is performed.

* Operands are promoted to the "biggest" type involved as previously described
  (bool -> int -> long -> real).
* Only numeric operands are legal (no adding strings).
* If any operand is `NULL`, the result is `NULL`.

#### Multiplication, Division, Modulus `*`, `/`, `%`

These operators also perform typical arithmetic operations. Note that there are no
unsigned numeric types, so it's always signed arithmetic that is performed.

* Operands are promoted to the "biggest" type as previously described (bool ->
  int -> long -> real).
* Only numeric operands are legal (no multiplying strings).
* If any operand is `NULL`, the result is `NULL`.
* In a native context, division by zero will product a fault.

> EXCEPTION: The `%` operator doesn't make sense on real values, so real values
> produce an error.

#### Concatenation `||`

This operator is only valid in a SQL context, it concatenates the text
representation of its left and right arguments into text.  The arguments
can be of any type.

#### JSON Operators `->` and `->>`

The JSON extraction operator `->` accepts a JSON text value or JSON blob value
as its left argument and a valid JSON path as its right argument.  The indicated
path is extracted and the result is a new, smaller, piece of JSON text.

The extended extraction operator `->>` will return the selected item as a value
rather than as JSON.  The SQLite documentation can be helpful here:

> Both the `->` and `->>` operators select the same subcomponent of the JSON to
> their left. The difference is that `->` always returns a JSON representation of
> that subcomponent and the `->>` operator always returns an SQL representation of
> that subcomponent.

Importantly, the resulting type of the `->>` operator cannot be known at compile
time because it will depend on the path value which could be, and often is, a
non-constant expression. Dynamic typing is not a concept available in CQL, as a
consequence, in CQL, you must declare the extraction type when using the `->>`
operator with syntax:

```
  json_arg ->> ~type_spec~ path_arg
```

The type_spec can be any valid type like `int`, `int<foo>`, or a type alias. All
the normal type expressions are valid.

> NOTE: this form is not a CAST operation, it's a declaration. The type of the
> expression will be _assumed_ to be the indicated type. SQLite will not see the
> `~type~` notation when the expression is evaluated.  If a cast is desired
> simply write one as usual, the trailing cast syntax can be specially convenient
> when working with JSON.

#### Unary operators `-`, `~`

Unary negation (`-`) and bitwise invert (`~`) are the strongest binding
operators.

* The `~` operator only works on integer types (not text, not real).
* The usual promotion rules otherwise apply.
* If the operand is `NULL`, the result is `NULL`.

### CAST Expressions

The `CAST` expression can be written in two ways, the standard form:

```sql
  CAST( expr AS type)
```

And equivalently using pipeline notation

```sql
  expr ~type~
```

The trailing `~type~` notation has very strong binding,  As shown in
the order of operations table, it is even stronger than the unary `~`
operator. It is intended to be used in function pipelines in combination
with other pipeline operations (the `:` family) rather than as part of arithmetic
and so forth, hence it has a fairly strong binding (equal to `:`).

The `~type~` form is immediately converted to the standard `CAST` form
and so SQLite will never see this alternate notation.  This form is purely
syntactic sugar.

Compare:

```sql
-- pipeline notation
select x:substr(5) ~int~ :ifnull(0) x from X;

-- equivalent
SELECT ifnull(CAST(substr(x, 5) AS INT), 0) AS x FROM X;
```

### CASE Expressions

The `CASE` expression has two major forms and provides a great deal of
flexibility in an expression. You can think of it as an enhanced version of the
C `?:` operator.

```sql
let x := 'y';
let y := case x
  when 'y' then 1
  when 'z' then 2
  else 3
end;
```

In this form, the `CASE` expression (`x` here) is evaluated exactly once and
then compared against each `WHEN` clause. Every `WHEN` clause must be
type-compatible with the `CASE` expression. The `THEN` expression corresponding
to the matching `WHEN` is evaluated and becomes the result. If no `WHEN`
matches, then the `ELSE` expression is used. If there is no `ELSE` and no
matching `WHEN`, then the result is `NULL`.

If that's not general enough, there is an alternate form:


```sql
let y := 'yy';
let z := 'z';
let x := case
  when y = 'y' then 1
  when z = 'z' then 2
  else 3
end;
```

In the second form, where there is no value before the first `WHEN` keyword, each
`WHEN` expression is a separate independent boolean expression. The first one
that evaluates to true causes the corresponding `THEN` to be evaluated, and that
becomes the result. As before, if there is no matching `WHEN` clause, then the
result is the `ELSE` expression if present, or `NULL` if there is no `ELSE`.

The result types must be compatible, and the best type to hold the answer is
selected with the usual promotion rules.

#### SELECT Expressions

Single values can be extracted from SQLite using an inline `SELECT` expression.
For instance:

```sql
set x_ := (select x from somewhere where id = 1);
```

The `SELECT` statement in question must extract exactly one column, and the type
of the expression becomes the type of the column. This form can appear anywhere
an expression can appear, though it is most commonly used in assignments.
Something like this would also be valid:

```sql
if (select x from somewhere where id = 1) == 3 then
  ...
end if;
```

The `SELECT` statement can, of course, be arbitrarily complex.

Importantly, if the `SELECT` statement returns no rows, this will result in the
normal error flow. In that case, the error code will be `SQLITE_DONE`, which is
treated like an error because in this context `SQLITE_ROW` is expected as a
result of the `SELECT`. This is not a typical error code and can be quite
surprising to callers. If you're seeing this failure mode, it usually means the
code had no affordance for the case where there were no rows, and probably that
situation should have been handled. This is an easy mistake to make, so to avoid
it, CQL also supports these more tolerant forms:

```sql
set x_ := (select x from somewhere where id = 1 if nothing then -1);
```

And even more generally, if the schema allows for null values and those are not
desired:

```sql
set x_ := (select x from somewhere where id = 1 if nothing or null then -1);
```

Both of these are much safer to use, as only genuine errors (e.g., the table was
dropped and no longer exists) will result in the error control flow.

Again, note that:

```sql
set x_ := (select ifnull(x, -1) from somewhere where id = 1);
```

Would not avoid the `SQLITE_DONE` error code because "no rows returned" is not at
all the same as "null value returned."

The `if nothing or null` form above is equivalent to the following, but it is
more economical and probably clearer:

```sql
set x_ := (select ifnull(x, -1) from somewhere where id = 1 if nothing then -1);
```

To compute the type of the overall expression, the rules are almost the same as
normal binary operators. In particular:

* If the default expression is present, it must be type compatible with the
  select result. The result type is the smallest type that holds both the select
  value and the default expression (see normal promotion rules above).
* Object types are not allowed (SQLite cannot return an object).
* In `(select ...)`, the result type is not null if and only if the select
  result type is not null (see select statement, many cases).
* In `(select ... if nothing)`, the result type is not null if and only if both
  the select result and the default expression types are not null (normal binary
  rules).
* In `(select ... if nothing or null)`, the result type is not null if and only
  if the default expression type is not null.

Finally, the form `(select ... if nothing then throw)` is allowed; this form is
exactly the same as normal `(select ...)`, but it makes explicit that the error
control flow will happen if there is no row. Consequently, this form is allowed
even if `@enforce_strict select if nothing` is in force.

### Marking Data as Sensitive

CQL supports the notion of 'sensitive' data in a first-class way. You can think
of it as very much like nullability; it largely begins by tagging data columns
with `@sensitive`.

Rather than go through the whole calculus, it's easier to understand by a series
of examples. So let's start with a table with some sensitive data.

```sql
create table with_sensitive(
  id int,
  name text @sensitive,
  sens int @sensitive
);
```

The most obvious thing you might do at this point is create a stored procedure
that would read data out of that table. Maybe something like this:

```sql
create proc get_sensitive()
begin
  select id as not_sensitive_1,
        sens + 1 sensitive_1,
        name as sensitive_2,
        'x' as not_sensitive_2,
        -sens as sensitive_3,
        sens between 1 and 3 as sensitive_4
  from with_sensitive;
end;
```

So looking at that procedure, we can see that it's reading sensitive data, so the result will have some sensitive columns in it.

* `id` is not sensitive (at least not in this example)
* `sens + 1` is sensitive, math on a sensitive field leaves it sensitive
* `name` is sensitive, it began that way and is unchanged
* `x` is just a string literal, it's not sensitive
* `-sens` is sensitive, that's more math
* and the `between` expression is also sensitive

Generally, sensitivity is "radioactive" - anything it touches becomes sensitive.
This is very important because even a simple-looking expression like `sens IS
NOT NULL` must lead to a sensitive result or the whole process would be largely
useless. It has to be basically impossible to wash away sensitivity.

These rules apply to normal expressions as well as expressions in the context of
SQL. Accordingly:

Sensitive variables can be declared:

```sql
var sens int @sensitive;
```

Simple operations on the variables are sensitive:

```sql
-- this is sensitive (and the same would be true for any other math)
sens + 1;
```

The `IN` expression gives a sensitive result if anything about it is sensitive:

```sql
-- all of these are sensitive
sens in (1, 2);
1 in (1, sens);
(select id in (select sens from with_sensitive));
```

Similarly, sensitive constructs in `CASE` expressions result in a sensitive
output:

```sql
-- not sensitive
case 0 when 1 then 2 else 3 end;

-- all of these are sensitive
case sens when 1 then 2 else 3 end;
case 0 when sens then 2 else 3 end;
case 0 when 1 then sens else 3 end;
case 0 when 1 then 2 else sens end;
```

Cast operations preserve sensitivity:

```sql
-- sensitive result
select cast(sens as INT);
```

Aggregate functions likewise preserve sensitivity:

```sql
-- all of these are sensitive
select AVG(T1.sens) from with_sensitive T1;
select MIN(T1.sens) from with_sensitive T1;
select MAX(T1.sens) from with_sensitive T1;
select SUM(T1.sens) from with_sensitive T1;
select COUNT(T1.sens) from with_sensitive T1;
```

There are many operators that get similar treatment such as `COALESCE`,
`IFNULL`, `IS` and `IS NOT`.

Things get more interesting when we come to the `EXISTS` operator:

```sql
-- sensitive if and only if any selected column is sensitive
exists(select * from with_sensitive)

-- sensitive because "info" is sensitive
exists(select info from with_sensitive)

-- not sensitive because "id" is not sensitive
exists(select id from with_sensitive)
```

If this is making you nervous, it probably should. We need a little more
protection because of the way `EXISTS` is typically used. The predicates matter.
Consider the following:

```sql
-- id is now sensitive because the predicate of the where clause was sensitive
select id from with_sensitive where sens = 1;

-- this expression is now sensitive because id is sensitive in this context
exists(select id from with_sensitive where sens = 1)
```

In general, if the predicate of a WHERE or HAVING clause is sensitive, then all
columns in the result become sensitive.

Similarly, when performing joins, if the column specified in the USING clause is
sensitive or the predicate of the ON clause is sensitive, then the result of the
join is considered to be all sensitive columns, even if the columns were not
sensitive in the schema.

Likewise, a sensitive expression in LIMIT or OFFSET will result in 100%
sensitive columns, as these can be used in a WHERE-ish way.

```sql
-- join with ON
select T1.id from with_sensitive T1 inner join with_sensitive T2 on T1.sens = T2.sens

-- join with USING
select T1.id from with_sensitive T1 inner join with_sensitive T2 using(sens);
```

All of these expressions and join propagations are designed to make it
impossible to simply wash away sensitivity with a little bit of math.

Now we come to enforcement, which boils down to what assignments or
"assignment-like" operations we allow.

If we have these:

```sql
var sens int @sensitive;
declare not_sens integer;
```

We can use those as stand-ins for lots of expressions, but the essential
calculus goes like this:

```sql
-- assigning a sensitive to a sensitive is ok
set sens := sens + 1;

-- assigning not sensitive data to a sensitive is ok
-- this is needed so you can (e.g.) initialize to zero
set sens := not_sens;

-- not ok
set not_sens := sens;
```

Now these "assignments" can happen in a variety of ways:

* you can set an out parameter of your procedure
* when calling a function or procedure, we require:
  * any `IN` parameters of the target be "assignable" from the value of the
    argument expression
  * any `OUT` parameters of the target be "assignable" from the procedures type
    to the argument variable
  * any `INOUT` parameters require both the above

Now it's possible to write a procedure that accepts sensitive things and returns
non-sensitive things.  This is fundamentally necessary because the proc must be
able return (e.g.) a success code, or encrypted data, that is not sensitive.
However, if you write the procedure in CQL it, too, will have to follow the
assignment rules and so cheating will be quite hard.  The idea here is to make
it easy to handle sensitive data well and make typical mistakes trigger errors.

With these rules  it's possible to compute the the type of procedure result sets
and also to enforce IN/OUT parameters.  Since the signature of procedures is
conveniently generated with --generate_exports good practices are fairly easy to
follow and sensitivity checks flow well into your programs.

This is a brief summary of CQL semantics for reference types -- those types that
are ref counted by the runtime.

The three reference types are:

* `TEXT`
* `BLOB`
* `OBJECT`

Each of these has their own macro for `retain` and `release` though all three
actually turn into the exact same code in all the current CQL runtime
implementations.  In all cases the object is expected to be promptly freed when
the reference count falls to zero.

### Reference Semantics

#### Stored Procedure Arguments

* `in` and `inout` arguments are not retained on entry to a stored proc
* `out` arguments are assumed to contain garbage and are nulled without
  retaining on entry
* if your `out` argument doesn't have garbage in it, then it is up to you to
  `release` it before you make a call
* When calling a proc with an `out` argument, CQL will `release` the argument
  variable before the call site, obeying its own contract

#### Local Variables

* assigning to a local variable `retains` the object, and then does a `release`
  on the previous object
* this order is important; all assignments are done in this way in case of
  aliasing (`release` first might accidentally free too soon)
* CQL calls `release` on all local variables when the method exits

#### Assigning to an `out` parameter or a global variable

* `out`, `inout` parameters, and global variables work just like local variables
  except that CQL does not call `release` at the end of the procedure

### Function Return Values

Stored procedures do not return values, they only have `out` arguments and those
are well defined as above.  Functions however are also supported and they can
have either `get` or `create` semantics

#### Get Semantics

If you declare a function like so:

```sql
func Getter() object;
```

Then CQL assumes that the returned object should follow the normal rules above,
retain/release will balance by the end of the procedure for locals and globals
or `out` arguments could retain the object.

#### Create Semantics

If you declare a function like so:

```sql
func Getter() create text;
```

then CQL assumes that the function created a new result which it is now
responsible for releasing. In short, the returned object is assumed to arrive
with a retain count of 1 already on it. When CQL stores this return value it
will:

* release the object that was present at the storage location (if any)
* copy the returned pointer without further retaining it this one time

As a result, if you store the returned value in a local variable it will be
released when the procedure exits (as usual) or if you instead store the result
in a global or an out parameter the result will survive to be used later.

### Comparison

CQL tries to adhere to normal SQL comparison rules but with a C twist.

#### `OBJECT`

The object type has no value-based comparison, so there is no `<`, `>` and so
forth.

The following table is useful.  Let's suppose there are exactly two distinct objects 'X' and 'Y':

|result|`examples     `|`             `|`                `|`            `|`               `|`            `|
|:----:|:-------------:|:-------------:|:----------------:|:------------:|:---------------:|:------------:|
|true  |`X = X`        |`X <> Y`       |`Y = Y`           |`Y <> X`      |`X IN (X, Y)`    |`X NOT IN (Y)`|
|false |`X = Y  `      |`X <> X`       |`Y = X`           |`Y <> Y`      |`X NOT IN (X, Y)`|              |
|null  |`null = null`  |`X <> null`    |`x = null`        |`null <> null`|`Y <> null`      |`y = null`    |
|true  |`X is not null`|`Y is not null`|`null is null`    |              |                 |              |
|false |`X is null`    |`Y is null`    |`null is not null`|              |                 |              |

`null = null` resulting in `NULL` is particularly surprising but consistent with
the usual SQL rules. And again, as in SQL, the `IS` operator returns true for
`X IS Y` even if both are `NULL`.

> NOTE: null-valued variables evaluate as above; however, the `NULL` literal
> generally yields errors if it is used strangely. For example, in `if x == NULL`,
> you get an error. The result is always going to be `NULL`, hence falsey. This was
> almost certainly intended to be `if x IS NULL`. Likewise, comparing expressions
> that are known to be `NOT NULL` against `NULL` yields errors. This is also true
> where an expression has been inferred to be `NOT NULL` by control flow analysis.

#### `TEXT`

Text has value comparison semantics, but normal string comparison is done only
with `strcmp`, which is of limited value. Typically, you'll want to either
delegate the comparison to SQLite (with `(select x < y)`) or else use a helper
function with a suitable comparison mechanism.

For text comparisons, including equality:

|result|`                                      cases                                      `|
|:-----|:----------------------------------------------------------------------------------|
|true  |if and only if both operands are not null and the comparison matches (using strcmp)|
|false |if and only if  both operands are not null and the comparison does not match (using strcmp)|
|null  |if and only if at least one operand is null|

Example:

```
'x' < 'y' == true -- because strcmp("x", "y") < 0
```

As with type `object`, the `IS` and `IS NOT` operators behave similarly to
equality and inequality, but never produce a `NULL` result. Strings have the
same null semantics as `object`. In fact strings have all the same semantics as
object except that they get a value comparison with `strcmp` rather than an
identity comparison. With object `x == y` implies that `x` and `y` point to the
very same object. With strings, it only means `x` and `y` hold the same text.

The `IN` and `NOT IN` operators also work for text using the same value
comparisons as above.

Additionally there are special text comparison operators such as `LIKE`, `MATCH`
and `GLOB`. These comparisons are defined by SQLite.

#### `BLOB`

Blobs are compared by value (equivalent to `memcmp`) but have no well-defined
ordering. The `memcmp` order is deemed not helpful as blobs usually have
internal structure hence the valid comparisons are only equality and inequality.

You can use user defined functions to do better comparisons of your particular
blobs if needed.

The net comparison behavior is otherwise just like strings.

### Sample Code

#### Out Argument Semantics

```sql
DECLARE FUNCTION foo() OBJECT;

CREATE PROC foo_user (OUT baz OBJECT)
BEGIN
  SET baz := foo();
END;
```

```c
void foo_user(cql_object_ref _Nullable *_Nonnull baz) {
  *(void **)baz = NULL; // set out arg to non-garbage
  cql_set_object_ref(baz, foo());
}
```

#### Function with Create Semantics

```sql
DECLARE FUNCTION foo() CREATE OBJECT;

CREATE PROCEDURE foo_user (INOUT baz OBJECT)
BEGIN
  DECLARE x OBJECT;
  SET x := foo();
  SET baz := foo();
END;
```

```c
void foo_user(cql_object_ref _Nullable *_Nonnull baz) {
  cql_object_ref x = NULL;

  cql_object_release(x);
  x = foo();
  cql_object_release(*baz);
  *baz = foo();

cql_cleanup:
  cql_object_release(x);
}
```

#### Function with Get Semantics

```sql
DECLARE FUNCTION foo() OBJECT;

CREATE PROCEDURE foo_user (INOUT baz OBJECT)
BEGIN
  DECLARE x OBJECT;
  SET x := foo();
  SET baz := foo();
END;
```

```c
void foo_user(cql_object_ref _Nullable *_Nonnull baz) {
  cql_object_ref x = NULL;

  cql_set_object_ref(&x, foo());
  cql_set_object_ref(baz, foo());

cql_cleanup:
  cql_object_release(x);
}
```

### Pipeline Function Notation

Function calls can be made using a pipeline notation to chain function results together
in a way that is clearer.  The general syntax is:

```sql
   expr : func(...args...)
```

Which is exactly equivalent to

```sql
   func(expr, ...args...)
```

This can be generalized with the `@op` statement, which in general might change the function
name to something more specific.  For instance.

```sql
@op real : call foo as foo_real;
@op real<joules> : call foo as foo_real_joules;
```

Now has more specific mappings

```sql
var x real<joules>;

-- These are the functions that you might call with pipeline notation

func foo(x text) real;
func foo_real(x real) real;
func foo_real_joules(x real) real;
```

The mappings and declarations are both required now allow this:

```sql
"test":foo()  -->  foo("test")

5.0:foo()     --> foo_real(5.0)

x:foo()       --> foo_real_joules(x)
```

Note that in each case `foo` could have included additional arguments which are placed normally.

```
x:foo(1,2)    --> foo_real_joules(x, 1, 2) (this function is not declared)
```

If there are no additional arguments the `()` can be elided.  This is a good way to end a pipeline.

```sql
x:dump        --> dump(x)
```

The old `::` and `:::` operators are no longer supported.  The combination of naming conventions
proved impossible to remember.  With `@op` you can decide how to resolve the naming yourself.

#### Pipeline Polymorphic Overloads

This is a functor like form and it can be enabled using `@op` like the other cases.  For instance

```sql
@op object<list_builder> : functor all as list_builder_add;
```

The invocation syntax is like the `:` operator but with no function name, so it looks kind of like
the left argument has become a functor (something you can call like a function). In reality the
call is converted using the base name in the `@op` directive and the base types of the arguments.

```sql
expr:(arg1, arg2, ...)
```

To enable:

  * the left argument (here `expr`) must have a type kind (e.g. `object<container>`)
  * the type kind must match an `@op` directive specifying `functor` and `all`
  * the rewritten function name is the `@op` name plus the types of all the arguments (if any)

for instance, with these declarations:

```sql
func new_builder() create object<list_builder>;
func list_builder_add_int(arg1 object<list_builder>, arg2 int!) object<list_builder>;
func list_builder_add_int_int(arg1 object<list_builder>, arg2 int!, arg3 int!)
  object<list_builder>;
func list_builder_add_real(arg1 object<list_builder>, arg2 real!) object<list_builder>;
func list_builder_to_list(arg1 object<list_builder>) create object<list>;

@op object<list_builder> : functor all as list_builder_add;
@op object<list_builder> : call to_list as list_builder_to_list;
```

You could write:

```sql
let list := new_builder():(5):(7.0):(1,2):to_list();
```

This expands to the much less readable:

```sql
LET list :=
  list_builder_to_list(
   list_builder_add_int_int(
      list_builder_add_real(
        list_builder_add_int(
          new_builder(), 5), 7.0), 1, 2));
```
You can use this form to build helper functions that assemble text, arrays, JSON and many other uses.
Anywhere the "fluent" coding pattern is helpful this syntax gives you a very flexible pattern.  In
the end it's just rewritten function calls.

The appended type names look like this:

| core type    | short name |
|:-------------|-----------:|
| NULL +       | null       |
| BOOL         | bool       |
| INTEGER      | int        |
| LONG INTEGER | long       |
| REAL         | real       |
| TEXT         | text       |
| BLOB         | blob       |
| OBJECT       | object     |
| CURSOR ++    | cursor     |

+ _the null type applies only to the null literal, other instances are typed such as a nullable int that is null_

++ _the CURSOR type applies to functions with a CURSOR argument, these are the so called dynamic-cursor arguments_

#### Pipeline Cast Operations

Cast operations also have a pipeline notation:

```sql
-- This is the same as let i := cast(foo(x) as int);
let i := x :foo() ~int~ ;
```

These operations are particularly useful when working with json data.  For instance:

```sql
select foo.json : json_extract('x') ~int~ :ifnull(0) as X from foo;
```

This is much easier to read than the equivalent:

```sql
select ifnull(cast(json_extract(foo.json 'x') as int), 0) as X from foo;
```

In all the cases the expression is rewritten into the normal form so SQLite will never see
the pipeline form.  No special SQLite support is needed.

This form of the `~` operator has the same binding strength as the `:` operator family.

### Other operators useful in construction: `->` `<<` `>>` `||`

The `@op` form allows the definition of many possible overload combos.  For instance the `->`
is now mappable to a function call of your choice, this is very useful in pipeline forms.

```sql
@op text<xml> : arrow text<xml_path> as extract_xml_path;
```

Allows this mapping

```sql
  xml -> path   --->   extract_xml_path(xml, path)
```

The type forms for `arrow` should use types in their simplest form, like so:

| core type    | short name |
|:-------------|-----------:|
| BOOL         | bool       |
| INTEGER      | int        |
| LONG INTEGER | long       |
| REAL         | real       |
| TEXT         | text       |
| BLOB         | blob       |
| OBJECT       | object     |

These are the same forms that are used when adding argument types for the polymorpic pipeline form.

`@op` can be used with `lshift` `rshift` and `concat` to remap the `<<`, `>>`, and `||` operators
respectively.

### Properties and Arrays

CQL offers structured types in the form of cursors, but applications often need
other structured types. In the interest of not encumbering the language and
runtime with whatever types given application might need, CQL offers a generic
solution for properties and arrays where it will rewrite property and array
syntax into function calls.

#### Specific Properties on objects

The rewrite depends on the object type, and in particular the "kind"
designation. So for instance consider:

```sql
func create_container() create object<container>!;
let cont := create_container();
cont.x := cont.x + 1;
```

For this to work we need a function that makes the container:

```sql
func create_container() create object<container>;
```

Now `cont.x` *might* mean field access in a cursor or table access in a `select`
expression. So, when it is seen, `cont.x` will be resolved in the usual ways. If
these fail then CQL will look for a suitable mapping using the `@op` directive,
like so:

```
@op object<container> : get x as container_get_x;
@op object<container> : set x as container_set_x;
```

`container_set_x` to do setting and `container_get_x` to do getting.

Like these maybe:

```sql
func container_get_x(self object<container> not null) int!;
declare proc container_set_x(self object<container> not null, value int!);
```

With those in place `cont.x := cont.x + 1` will be converted into this:

```sql
CALL set_object_container_x(cont, get_object_container_x(cont) + 1);
```

Importantly with this pattern you can control exactly which properties are
available.  Missing properties will always give errors.  For instance `cont.y := 1;`
results in `name not found 'y'`.

This example uses `object` as the base type but it can be any type. For
instance, if you have a type `integer<handle>` that identifies some storage
based on the handle value, you can use the property pattern on this. CQL does
not care what the types are, so if property access is meaningful on your type
then it can be supported.

Additionally, the rewrite can happen in a SQL context or a native context. The
only difference is that in a SQL context you would need to create the
appropriate SQLite UDF and declare it with `select function` rather than
`function`.

#### Open Ended Properties

There is a second choice for properties, where the properties are open-ended.
That is where the property name can be anything. If instead of the property
specific functions above, we had created these more general functions:

```sql
func container_get(self object<container>! , field text!) int!;
declare proc container_set(self object<container>!, field text!, value int!);
```

These functions have the desired property name as a parameter (`field`) and so
they can work with any field.

```sql
@op object<container> : get all as container_get;
@op object<container> : set all as container_set;
```

With these in place, `cont.y` is no longer an error. We get these transforms:

```sql
cont.x += 1;
cont.y += 1;
-- specific functions for 'x'
CALL container_set_x(cont, container_get_x(cont) + 1);

-- generic functions for 'y'
CALL container_set(cont, 'y', container_get(cont, 'y') + 1);
```

Nearly the same, but more generic. This is great if the properties are
open-ended. Perhaps for a dictionary or something representing JSON. Anything
like that.

In fact, the property doesn't have to be a compile-time constant. Let's look
at array syntax next.

#### Using Arrays in CQL

Array access is just like the open-ended property form with two differences:

* the type of the index can be anything you want it to be, not just a property name
* there can be as many indices as you like

```sql
cont['x'] += 1;
```

You get exactly the same transform if you set up the array mapping:

```sql
@op object<container> : array get container_get;
@op object<container> : array set container_set;

To yield:

CALL container_set(cont, 'x', container_get(cont, 'x') + 1);
```

The index type is not contrained so you can make several mappings with different
signatures.  For instance:

```sql
cont[1,2] := cont[3,4] + cont[5,6];
```

Could be supported by these functions:

```sql
func cont_get_ij(self object<container>!, i int!, j int!) int!;
declare proc cont_set_ij(self object<container>!, i int!, j int!, value int!);

@op object<container> : array get as cont_get_ij;
@op object<container> : array set as cont_set_ij;
```

This results in:

```sql
CALL cont_set_ij(cont, 1, 2, cont_get_ij(cont, 3, 4) + cont_get_ij(cont, 5, 6));
```

This is a very simple transform that allows for the creation of any array-like
behavior you might want.

#### Notes On Implementation

In addition to the function pattern shown above, you can use the "proc as func"
form to get values, like so:

```sql
create proc container(self object<container>!, field text!, out value int!)
begin
  value := something_using_container_and_field;
end;
```

And with this form, you could write all of the property management or array
management in CQL directly.

However, it's often the case that you want to use native data structures to hold
your things-with-properties or your arrays. If that's the case, you can write
them in C as usual, using the normal interface types to CQL that are defined in
`cqlrt.h`. The exact functions you need to implement will be emitted into the
header file output for C. For Lua, things are even easier; just write matching
Lua functions in Lua. It's all primitives or dictionaries in Lua.

In C, you could also implement some or all of the property reading functions as
macros. You could add these macros to your copy of `cqlrt.h` (it's designed to
be changed) or you could emit them with `@echo c, "#define stuff\n";`

Finally, the `no check` version of the functions or procedures can also be used.
This will let you use a var-arg list, for instance, in your arrays, which might be
interesting. Variable indices can be used in very flexible array builder forms.

Another interesting aspect of the `no check` version of the APIs is that the
calling convention for such functions is a little different in C (in Lua it's
the same). In C, the `no check` forms most common target is the `printf`
function. But `printf` accepts C strings not CQL text objects. This means any
text argument must be converted to a normal C string before making the call.
But it also means that string literals pass through unchanged into the C!

For instance:

```sql
  call printf("Hello world\n");
```

becomes:

```C
  printf("Hello world\n");
```

So likewise, if your array or property getters are `no check`, then `cont.x := 1;`
becomes maybe `container_set(cont, "x", 1)`. Importantly, the C string
literal `"x"` will fold across any number of uses in your whole program, so
there will only be one copy of the literal. This gives great economy for the
flexible type case and it is actually why `no check` _functions_ were added to the
language, rounding out all the `no check` flavors.

So, if targeting C, consider using `no check` functions and procedures for your
getters and setters for maximum economy. If you also implement the functions on
the C side as macros, or inline functions in your `cqlrt.h` path, then array and
property access can be very economical. There need not be any actual function
calls by the time the code runs.
