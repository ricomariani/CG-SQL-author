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

*Aggregate Functions*

 * count
 * max
 * min
 * sum
 * total
 * avg
 * group_concat

*Scalar Functions*

 * ifnull
 * nullif
 * upper
 * char
 * abs
 * instr
 * coalesce
 * last_insert_rowid
 * printf
 * strftime
 * date
 * time
 * datetime
 * julianday
 * substr
 * replace
 * round
 * trim
 * ltrim
 * rtrim

*Window Functions*

 * row_number
 * rank
 * dense_rank
 * percent_rank
 * cume_dist
 * ntile
 * lag
 * lead
 * first_value
 * last_value
 * nth_value

*JSON Functions*

 * json
 * jsonb
 * json_array
 * jsonb_array
 * json_array_length
 * json_error_position
 * json_extract
 * jsonb_extract
 * json_insert
 * json_replace
 * json_set
 * jsonb_insert
 * jsonb_replace
 * jsonb_set
 * json_remove
 * jsonb_remove
 * json_object
 * jsonb_object
 * json_patch
 * jsonb_patch
 * json_pretty
 * json_type
 * json_valid
 * json_quote

`json_extract` and `jsonb_extract` are peculiar because they do not always return the same type.
Since CQL has to assume something it assumes that `json_extract` will return `TEXT` and `jsonb_extract`
will return a `BLOB`.  Importantly, CQL does not add any casting operations into the SQL unless
they are explicitly added which means in some sense SQLite does not "know" that CQL has made a
bad assumption, or any assumption.  In many cases, even most cases, a specific type is expected,
this is a great time to use the pipeline cast notation to "force" the conversion. 

```sql
  select json_extract('{ "x" : 0 }', '$.x') :int: as X;
```

This is exactly the same as

```sql
  select CAST(json_extract('{ "x" : 0 }', '$.x') as int) as X;
```

*JSON Aggregations*

 * json_group_array
 * jsonb_group_array
 * json_group_object
 * jsonb_group_object

*JSON Table Functions*

The two table functions are readily declared if they are needed like so:

```sql
DECLARE SELECT FUNC json_each NO CHECK
   (key BLOB, value BLOB, type TEXT, atom BLOB, id INT, parent INT, fullkey TEXT, path TEXT);

DECLARE SELECT FUNC json_tree NO CHECK
   (key BLOB, value BLOB, type TEXT, atom BLOB, id INT, parent INT, fullkey TEXT, path TEXT);
```

> NOTE: key, value, and atom can be any type and will require a cast operation similar to
> `json_extract`, see the notes above.


Special Functions
 * nullable
 * sensitive
 * ptr

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
