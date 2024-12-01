---
title: "Chapter 8: Functions"
weight: 8
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL stored procs have a very simple contract so it is easy to declare
procedures and then implement them in regular C; the C functions just
have to conform to the contract.  However, CQL procedures have their own
calling conventions and this makes it very inconvenient to use external
code that is not doing database things and wants to return values.
Even a random number generator or something would be difficult to
use because it could not be called in the context of an expression.
To allow for this CQL adds declared functions

In another example of the two-headed nature of CQL, there are two ways to declare functions.  As we have already
seen you can make function-like procedures and call them like functions
simply by making a procedure with an `out` parameter. However, there
are also cases where it is reasonable to make function calls to external
functions of other kinds.  There are three major types of functions you
might wish to call.

### Function Types

#### Ordinary Scalar Functions

These functions are written in regular C and provide for the ability to do operations on in-memory objects.  For instance,
you could create functions that allow you to read and write from a dictionary.  You can declare these functions like so:

```sql
declare function dict_get_value(dict object, key_ text not null) text;
```

Such a function is not known to SQLite and therefore cannot appear in SQL statements.  CQL will enforce this.

The above function returns a text reference, and, importantly, this is a borrowed reference.  The dictionary
is presumably holding on to the reference and as long as it is not mutated the reference is valid.  CQL will
retain this reference as soon as it is stored and release it automatically when it is out of scope.  So, in
this case, the dictionary continues to own the object.

It is also possible to declare functions that create objects.  Such as this example:

```sql
declare function dict_create() create object;
```

This declaration tells CQL that the function will create a new object for our use.  CQL does not retain the
provided object, rather assuming ownership of the presumably one reference count the object already has.
When the object goes out of scope it is released as usual.

If we also declare this procedure:

```sql
declare procedure dict_add(
    dict object not null,
    key_ text not null,
    value text not null);
```

then with this family of declarations we could write something like this:

```sql
create proc create_and_init(out dict object not null)
begin
  set dict := dict_create();
  call dict_add(dict, "k1", "v1");
  call dict_add(dict, "k2", "v2");
  if (dict_get_value(dict, "k1") == dict__get_value(dict, "k2")) then
    call printf("insanity has ensued\n");
  end if;
end;
```

>NOTE: Ordinary scalar functions may not use the database in any way. When they are invoked they will not
>be provided with the database pointer and so they will be unable to do any database operations.  To do
>database operations, use regular procedures.  You can create a function-like-procedure using the `out` convention
>discussed previously.

#### SQL Scalar Functions

SQLite includes the ability to add new functions to its expressions using `sqlite3_create_function`.  In
order to use this function in CQL, you must also provide its prototype definition to the compiler.  You
can do so following this example:

```sql
declare select function strencode(t text not null) text not null;
```

This introduces the function `strencode` to the compiler for use in SQL constructs.  With this done you
could write a procedure something like this:

```sql
create table foo(id integer, t text);

create procedure bar(id_ integer)
begin
   select strencode(T1.t) from foo T1 where T1.id = id_;
end;
```

This presumably returns the "encoded" text, whatever that might be.
Note that if `sqlite3_create_function` is not called before this code
runs, a run-time error will ensue.  Just as CQL must assume that declared
tables really are created, it also assumes that declared function really
are created.  This is another case of telling the compiler in advance
what the situation will be at runtime.

SQLite allows for many flexible kinds of user defined functions.
CQL doesn't concern itself with the details of the implementation of
the function, it only needs the signature so that it can validate calls.

Note that SQL Scalar Functions cannot contain `object` parameters. To
pass an `object`, you should instead pass the memory address of this
object using a `LONG INT` parameter. To access the address of an `object`
at runtime, you should use the `ptr()` function. See [the notes section
below](#notes-on-builtin-functions) for more information.

See also: [Create Or Redefine SQL Functions](https://www.sqlite.org/c3ref/create_function.html).

#### SQL Table Valued Functions

More recent versions of SQLite also include the ability to add
table-valued functions to statements in place of actual tables. These
functions can use their arguments to create a "virtual table" value for
use in place of a table.  For this to work, again SQLite must be told of
the existence of the table.  There are a series of steps to make this
happen beginning with `sqlite3_create_module` which are described in
the SQLite documents under "The Virtual Table Mechanism Of SQLite."

Once that has been done, a table-valued function can be defined for
most object types.  For instance it is possible to create a table-valued
function like so:

```sql
declare select function dict_contents(dict object not null)
   (k text not null, v text not null);
```

This is just like the previous type of select function but the return
type is a table shape.  Once the above has been done you can legally
write something like this:

```sql
create proc read_dict(dict object not null, pattern text)
begin
  if pattern is not null then
    select k, v from dict_contents(dict) T1 where T1.k LIKE pattern;
  else
    select k, v from dict_contents(dict);
  end if;
end;
```

This construct is very general indeed but the runtime set up for it is much more complicated than scalar functions
and only more modern versions of SQLite even support it.

### SQL Functions with Unchecked Parameter Types

Certain SQL functions like
[`json_extract`](https://www.sqlite.org/json1.html#jex) are variadic (they
accept variable number of arguments). To use such functions within CQL,
you can declare a SQL function to have untyped parameters by including
the `NO CHECK` clause instead of parameter types.

For example:
```sql
declare select function json_extract no check text;
```

This is also supported for SQL table-valued functions:

```sql
declare select function table_valued_function no check (t text, i int);
```

>NOTE: currently the `NO CHECK` clause is not supported for non SQL
>[Ordinary Scalar Functions](#Ordinary-Scalar-Functions).

### Notes on Builtin Functions

Some of the SQLite builtin functions are hard-coded; these are the
functions that have semantics that are not readily captured with a
simple prototype.  Other SQLite functions can be declared with `declare
select function ...` and then used.

CQL's hard-coded builtin list includes:

##### Aggregate Functions

 * `count`
 * `max`
 * `min`
 * `sum`
 * `total`
 * `avg`
 * `group_concat`

##### Scalar Functions

* `abs`
* `changes`
* `char`
* `coalesce`
* `concat`
* `concat_ws`
* `format`
* `glob`
* `hex`
* `ifnull`
* `iif`
* `instr`
* `last_insert_rowid`
* `length`
* `like`
* `likelihood`
* `likely`
* `load_extension`
* `lower`
* `ltrim`
* `max`
* `min`
* `nullif`
* `octet_length`
* `printf`
* `quote`
* `random`
* `randomblob`
* `replace`
* `round`
* `rtrim`
* `sign`
* `soundex`
* `sqlite_compileoption_get`
* `sqlite_compileoption_used`
* `sqlite_offset`
* `sqlite_source_id`
* `sqlite_version`
* `substr`
* `substring`
* `total_changes`
* `trim`
* `typeof`
* `unhex`
* `unicode`
* `unlikely`
* `upper`
* `zeroblob`

##### Window Functions

 * `row_number`
 * `rank`
 * `dense_rank`
 * `percent_rank`
 * `cume_dist`
 * `ntile`
 * `lag`
 * `lead`
 * `first_value`
 * `last_value`
 * `nth_value`

##### JSON Functions

 * `json`
 * `jsonb`
 * `json_array`
 * `jsonb_array`
 * `json_array_length`
 * `json_error_position`
 * `json_extract`
 * `jsonb_extract`
 * `json_insert`
 * `json_replace`
 * `json_set`
 * `jsonb_insert`
 * `jsonb_replace`
 * `jsonb_set`
 * `json_remove`
 * `jsonb_remove`
 * `json_object`
 * `jsonb_object`
 * `json_patch`
 * `jsonb_patch`
 * `json_pretty`
 * `json_type`
 * `json_valid`
 * `json_quote`

`json_extract` and `jsonb_extract` are peculiar because they do not always return the same type.
Since CQL has to assume something it assumes that `json_extract` will return `TEXT` and `jsonb_extract`
will return a `BLOB`.  Importantly, CQL does not add any casting operations into the SQL unless
they are explicitly added which means in some sense SQLite does not "know" that CQL has made a
bad assumption, or any assumption.  In many cases, even most cases, a specific type is expected,
this is a great time to use the pipeline cast notation to "force" the conversion.

```sql
  select json_extract('{ "x" : 0 }', '$.x') ~int~ as X;
```

This is exactly the same as

```sql
  select CAST(json_extract('{ "x" : 0 }', '$.x') as int) as X;
```

##### JSON Aggregations

 * `json_group_array`
 * `jsonb_group_array`
 * `json_group_object`
 * `jsonb_group_object`

##### JSON Table Functions

The two table functions are readily declared if they are needed like so:

```sql
DECLARE SELECT FUNC json_each NO CHECK
   (key BLOB, value BLOB, type TEXT, atom BLOB, id INT, parent INT, fullkey TEXT, path TEXT);

DECLARE SELECT FUNC json_tree NO CHECK
   (key BLOB, value BLOB, type TEXT, atom BLOB, id INT, parent INT, fullkey TEXT, path TEXT);
```

> NOTE: key, value, and atom can be any type and will require a cast operation similar to
> `json_extract`, see the notes above.

##### Boxing and Unboxing

These can be used to create an `object<cql_box>` from the various primitives.  This can
then be stored generically in something that holds objects. The unbox methods can be used
to extract the original value.

* `cql_box_blob`
* `cql_box_bool`
* `cql_box_get_type`
* `cql_box_int`
* `cql_box_long`
* `cql_box_object`
* `cql_box_real`
* `cql_box_text`
* `cql_unbox_blob`
* `cql_unbox_bool`
* `cql_unbox_int`
* `cql_unbox_long`
* `cql_unbox_object`
* `cql_unbox_real`
* `cql_unbox_text`

These functions have pipeline aliases  `:box`, `:type` and `:to_int`,
`:to_bool`,  etc.

*Dyanmic Cursor Functions*

These functions all work with an unspecified cursor format.  These accept a
so-called *dynamic* cursor.

* `cql_cursor_format` returns a string with the names and values of every field
  in the cursor, useful for debugging
* `cql_cursor_column_count` return the number of columns in the cursor
* `cql_cursor_column_type` returns the type of the column using
  `CQL_DATA_TYPE_*` constants
* `cql_cursor_get_*` returns a column of the indicated type at the indicated
  index, the type can be bool, int, long, real, text, blob, or object

Pipeline syntax is availabe for these, you can use `C:format`, `C:count`,
`C:type(i)`, `C:to_bool(i)`, `C:to_int(i)` etc.

##### Dictionaries

Each of the following returns an `object<cql_TYPE_dictionary` where `TYPE` is
the indicated type.

* `cql_string_dictionary_create`  -- values are strings (`text`)
* `cql_blob_dictionary_create`  -- values are blobs
* `cql_object_dictionary_create`  -- values are any `object` esp. boxed values
* `cql_long_dictionary_create` -- values are `long`
* `cql_real_dictionary_create` -- values are `real`

The `add` functions return `true` if an object was added, `false` if it was replaced.

* `cql_string_dictionary_add` -- add a string (`text`)
* `cql_blob_dictionary_add` -- add a `blob`
* `cql_object_dictionary_add` -- add an `object`
* `cql_long_dictionary_add` -- add a `long`
* `cql_real_dictionary_add` -- add a `real`

The `find` functions return `null` if there is no such value or else the stored value.
Each function requires the dictionary and the key to find.  The key is always a string
(i.e. `text`).

* `cql_string_dictionary_find`
* `cql_blob_dictionary_find`
* `cql_object_dictionary_find`
* `cql_long_dictionary_find` -- returns nullable long
* `cql_real_dictionary_find` -- returns nullable real

The pipeline syntax `dict:add(key, value)` works for all of the above.  Similarly,
`dict:find(key)` works.  Array forms `dict[key] := value` and `x := dict[value]`
also work and result in the same calls.  The long form name is really only needed
to create a dictionary.

##### Lists

As with dictionaries there are some simple built in lists.  These have limited
functionality but they are very handy for short term storage.

Each of the following returns an `object<cql_TYPE_list` where `TYPE` is the
indicated type.

* `cql_string_list_create`  -- values are strings (`text`)
* `cql_blob_list_create`  -- values are `blob`
* `cql_long_list_create` -- values are `long`
* `cql_real_list_create` -- values are `real`

The list functions are limited to `add` `get_at` `set_at` and `count`

These functions append the indicated value to the end of the list.

* `cql_string_list_add` -- append a string (`text`)
* `cql_blob_list_add` -- append a `blob`
* `cql_long_list_add` -- append a `long`
* `cql_real_list_add` -- append a `real`

Getters accept the list and an index, the index must be within bounds.

* `cql_string_list_get_at` -- gets the string (`text`) at the indicated index
* `cql_blob_list_get_at` -- gets the `blob` at the indicated index
* `cql_long_list_get_at` -- gets the `long` at the indicated index
* `cql_real_list_get_at` -- gets the `real` at the indicated index

Setters accept the list, the index and a value, the index must be within bounds.

* `cql_string_list_set_at` -- sets the string (`text`) at the indicated index
* `cql_blob_list_set_at` -- sets the `blob` at the indicated index
* `cql_long_list_set_at` -- sets the `long` at the indicated index
* `cql_real_list_set_at` -- sets the `real` at the indicated index

And, finally, the item count functions, in each case this just gives the count
of items in the list.

* `cql_string_list_count`
* `cql_blob_list_count`
* `cql_long_list_count`
* `cql_real_list_count`

Lists can use pipeline notation such as:

```sql
  let list := cql_string_list_create():add("hello"):add("goodbye");
  EXPECT!(2 == list.count);
  EXPECT!("hello" == list[0]);
  EXPECT!("goodbye" == list[1]);
  list[0] := "salut";
  EXPECT!("salut" == list[0]);
```

>Note: Lists use property notation for their `count`. This could have been a
>`:count` function also generating the same count but by convention we only use
>`:foo` when the operation is more complicated than a simple property fetch.
> `@op cql_long_list : call count as cql_long_list_count;` would add `:count`.
> The default is `@op cql_long_list : get count as cql_long_list_count;` which
> allows `.count`.  The `@op` directive is discussed below.

##### Special Functions

These are not real functions but rather notations to the compiler.

 * `nullable`
 * `sensitive`
 * `ptr`

`Nullable` casts an operand to the nullable version of its type and
otherwise does nothing.  This cast might be useful if you need an exact
type match in a situation.  It is stripped from any generated SQL and
generated C so it has no runtime effect at all other than the indirect
consequences of changing the storage class of its operand.

`Sensitive` casts an operand to the sensitive version of its type and
otherwise does nothing.  This cast might be useful if you need an exact
type match in a situation.  It is stripped from any generated SQL and
generated C so it has no runtime effect at all other than the indirect
consequences of changing the storage class of its operand.

`Ptr` is used to cause a reference type variable to be bound as a long
integer to SQLite. This is a way of giving object pointers to SQLite
UDFs. Not all versions of Sqlite support binding object variables,
so passing memory addresses is the best we can do on all versions.

### Operators That Become Functions

As we saw in [Chapter 3](./expressions_fundamentals.md) certain operators become
function calls after transformation.  In particular the `:`, `[]`, `.`, and `->`
operators can be mapped into functions.  To enable this transform you declare
the function you want to invoke normally and then you provide an `@op` directive
that redirects the operator to the function.  There are examples in the section
on [Pipeline Notation](./03_expressions_fundamentals/#pipeline-function-notation).

Here we will review the various forms so that all the `@op` patterns are easily
visible together:

|#|`@op` directive|expression|replacement|
|-|---------------|---------|-------|
|1|no declaration required | `expr:func(...)` |  `func(expr, ...)` |
|2|`@op T : call func as your_func;` | `expr:func(...)` | `your_func(expr, ...)`|
|3|`@op T<kind> : call func as func_kind;` | `expr:func(...)` | `func_kind(expr, ...)`|
|4|`@op T<kind> : get foo as get_foo;` | `expr.foo` | `get_foo(expr)`|
|5|`@op T<kind> : set foo as set_foo;` | `expr.foo := x` | `set_foo(expr, x)`|
|6|`@op T<kind> : get all as getter;` | `expr.foo` | `getter(expr, 'foo')`|
|7|`@op T<kind> : set all as setter;` | `expr.foo := x` | `setter(expr, 'foo', x)`|
|8|`@op T<kind> : array get as a_get;` | `expr[x,y]` | `a_get(expr, x, y')`|
|9|`@op T<kind> : array set as a_set;` | `expr[x,y] := z` | `a_set(expr, x, y, z)`|
|10|`@op T<kind> : functor all as f;` | `expr:(1, 2.0)` | `f_int_real(expr, 1, 2.0)`|
|11|`@op T<kind> : arrow all as arr1;` | `left->right` | `arr1(left, right)`|
|12|`@op T1<kind> : arrow T2 as arr2;` | `left->right` | `arr2(left, right)`|
|13|`@op T1<kind> : arrow T2<kind> as arr3;` | `left->right` | `arr3(left, right)`|
|14|`@op cursor : call foo as foo_bar;` | `C:foo(...)` | `foo_bar(C, ...)`|
|15|`@op null : call foo as foo_null;' | `null:foo(...)` | `foo_null(null, ...)`|

Now let's briefly go over each of these forms.  In all cases the transform is
only applied if `expr` is of type `T`.  No type conversion is applied at this
point, however only the base type must match so the transformation will be
applied regardless of the nullability or sensitivity of `expr`.  If `expr` is of
a suitable type the transform is applied and the call is then checked for errors
as usual.  Based on the type of replacement function an implicit conversion
might then be required.  Note that the types of any additional arguments are not
considered when deciding to do the transform but they can cause errors after the
transform has been applied. After the transform replacement expression,
including all arguments, are type checked as usual and errors could result from
arguments not being compatible with the transform.  This is no different than if
you had written `func(expr1, expr2, etc..)` with some of the arguments being not
appropriate for `func`.

1. With no declaration `expr:func()` is always replaced with `func(expr)`.  If
   there are no arguments `expr:func` may be used for brevity it is no different
   than `expr:func()`.

2. Here a call pipelined call to `func` with `expr` matching `T` becomes a
   normal call to `your_func`.

3. This form is a special case of (2).  CQL first looks for a match with the
   "kind", if there is one that is used preferrably. There are examples in
   [Pipeline
   Notation](./03_expressions_fundamentals/#pipeline-function-notation).  This
   lets you have a generic conversion and more specific conversions if needed.
   e.g. you might have formatting for any `int` but you have special formatting
   for `int<task_id>`.

4. This form defines a specific property getter.  Only types with a kind can
   have such getters so declaring a transform with a `T` that has no kind is
   useless and likely will produce errors at some point. The getter is type
   checked as usual after the replacement.

5. This form defines a specific property setter.  Only types with a kind can
   have such setters so declaring a transform with a `T` that has no kind is
   useless and likely will produce errors at some point. The setter is type
   checked as usual after the replacement.

6. This form declares a generic "getter", the property being fetched becomes a
   string argument.  This is useful if you have a bag of propreties of the same
   type and a generic "get" function.  Note that specific properties are
   consulted first (i.e. rule 4).

7. This form declares a generic "setter", the property being set becomes a
   string argument.  This is useful if you have a bag of propreties of the same
   type and a generic "set" function. Note that specific properties are
   consulted first (i.e. rule 5).

8. This form defines a transform for array-like read semantics.  A matching
   array operation is turned into a function call and all the array indices
   become function arguments.  Only the type of the expression being indexed is
   considered when deciding to do the transform. As usual, the replacement is
   checked and errors could result if the function is not suitable.

9. This form defines a transform for array-like write semantics.  A matching
   array operation is turned into a function call and all the array indices
   become function arguments, including the value to set. Only the type of the
   expression being indexed is considered when deciding to do the transform. As
   usual, the replacement is checked and errors could result if the function is
   not suitable.

10. This form allows for a "functor-like" syntax where there is no function name
    provided.  The name in the `@op` directive becomes the base name of the
    replacement function.  The base type names of all the arguments (but not
    `expr`) are included in the replacement.  As always the type of `expr` must
    match the directive.  The replacement could generate errors if a function is
    missing (e.g. you have no `f_int_real` variant) or if the arguments are not
    type compatible (e.g. if the signature or the `f_int_real` variant isn't
    actually `int` and `real`).

11. The replacement system is flexible enough to allow arbitary operators to be
    replaced.  At this point only `->` is supported and it is specified by
    "arrow".  The replacement happens if the left argument is exactly `T`.  In
    this form the right argumentcan be any thing.  The result of the replacement
    is type checked as usual.

12. This is just like (11) except that the type of the right argument has been
    partially specified, it must have the indicated base type T2, such as `int`,
    `real`, etc.  If this form matches the replacement takes precedence over
    (11). The result of the replacement is type checked as usual.

13. This is just like (12) except that the type and kind of the right argument
    has been specified, it must have the indicated base type T2 and the
    indicated kind.  If this form matches the replacement takes precedence over
    (12).  The result of the replacement is type checked as usual.

14. This form allows you to create pipeline functions on cursor types.  The
    replacement function will be declared with a dynamic cursor as the first
    argument. The result of the replacement is type checked as usual.

15. This form allows you to create pipeline functions on the null literal.  The
    replacement function will get null as its first argument and this can be
    accepted by any nullable type. This form is of limited use as it only is
    triggered by null literals and these are only likely to appear in a pipeline
    in the context of a macro. The result of the replacement is type checked as
    usual.

In addition to "arrow" the identifiers "lshift", "rshift" and "concat" maybe
used to similarly remap `<<`, `>>`, and `||` respectively.  The same rules
otherwise apply.  Note that the fact that these operators have different binding
strengths can be very useful in building fluent-style pipelines.

Other operators may be added in the future, they would follow the patterns for
rules 11, 12, and 13 with only the "arrow" keyword varying.  You could imagine
"add", "sub", "mult" etc. for other operators.

#### Example Transforms

These are discussed in greater detail in the [Pipeline Notation](./03_expressions_fundamentals/#pipeline-function-notation) section.
However, by way of motivational examples here are some possible transforms in table form.

|Original|Replacement|
|-|-|
|`"test":foo()`  | `foo("test")`|
|`5.0:foo()`     | `foo_real(5.0)`|
|`joules:foo()`  | `foo_real_joules(joules)`|
|`x:dump`        | `dump(x)` |
|`new_builder():(5):(7):to_list` | `tolist(add_int(add_int(b(), 5), 7))` |
|`x:ifnull(0)`   | `ifnull(x, 0)` |
|`x:nullable`    | `nullable(x)` |
|`x:n`           | `nullable(x)` |
|`xml -> path`   | `extract_xml_path(xml, path)` |
|`cont.y += 1`   | `set_y(cont, get_y(cont) + 1)` |
|`cont.z += 1`   | `set(cont, "z", get(cont, "z") + 1)` |
|`a[u,v] += 1`   | `set_uv(a, u, v, get_uv(a, u, v) + 1)` |
```
