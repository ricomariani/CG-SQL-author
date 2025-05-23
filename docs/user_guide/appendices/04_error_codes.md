---
title: "Appendix 4: Error Codes"
weight: 4
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### CQL0001: operands must be an integer type, not real

integer math operators like << >> & and | are not compatible with real-valued
arguments

-----

### CQL0002: left operand cannot be an object in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on objects.  Basically
comparison is all you can do.

-----

### CQL0003: left operand cannot be an object in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on objects.  Basically
comparison is all you can do.

-----

### CQL0004: left operand cannot be a blob in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on blobs.  Basically
comparison is all you can do.

-----

### CQL0005: right operand cannot be a blob in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on blobs.  Basically
comparison is all you can do.

-----

### CQL0007: left operand cannot be a string in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on strings.  Basically
comparison is all you can do.

-----

### CQL0008: right operand cannot be a string in 'operator'

Most arithmetic operators (e.g. +, -, *) do not work on strings.  Basically
comparison is all you can do.

-----

### CQL0009: required 'needed' not compatible with found 'actual' context 'subject'

The indicated subject required the type 'needed' and instead found type
'actual'.  For instance in this expression `1 == 'foo'` the left operand is of
type integer and so the right operator must be compatible with that.  Instead
there is a string, so needed would be 'INT' and found would be 'TEXT'.  Now
actually any numeric type would do.  So the needed type in the error is the type
that would be an exact match.  Usually it's the type of one of the operands.
The subject could be an operator, or it could be a field name, or any other kind
of situation where compatability has to be checked.

-----

### CQL0010 available for reuse


-----

### CQL0011 available for reuse

-----

### CQL0012 available for reuse

-----

### CQL0013: cannot assign/copy possibly null expression to not null target 'target'

Here assign/copy can be the simplest case of assigning to a local variable or an
OUT parameter but this error also appears when calling functions.  You should
think of the IN arguments as requiring that the actual argument be assignable to
the formal variable and OUT arguments requiring that the formal be assignable to
the actual argument variable.

------

### CQL0014: cannot assign/copy sensitive expression to not null target 'target'

Here assign/copy can be the simplest case of assigning to a local variable or an
OUT parameter but this error also appears when calling functions.  You should
think of the IN arguments as requiring that the actual argument be assignable to
the formal variable and OUT arguments requiring that the formal be assignable to
the actual argument variable.

------

### CQL0015: expected numeric expression 'context'

Many SQL clauses require a numeric expression such as WHERE/HAVING/LIMIT/OFFSET.
This expression indicates the expression in the given context is not a numeric.

------

### CQL0016: duplicate table name in join 'table'

When this error is produced it means the result of the join would have the same
table twice with no disambiguation between the two places.  The conflicting name
is provided.  To fix this, make an alias both tables. e.g.

```sql
SELECT T1.id AS parent_id, T2.id AS child_id
  FROM foo AS T1
  INNER JOIN foo AS T2 ON T1.id = T2.parent_id;
```
-----

### CQL0017: index was present but now it does not exist (use `@delete` instead) 'index'

The named index is in the previous schema bit it is not in the current schema.
All entities need some kind of tombstone in the  schema so that they can be
correctly deleted if they are still present.

-----

### CQL0018: duplicate index name 'index'

An index with the indicated name already exists.

-----

### CQL0019: create index table name not found 'table_name'

The table part of a CREATE INDEX statement was not a valid table name.

------

### CQL0020: duplicate constraint name in table 'constraint_name'

A table contains two constraints with the same name.

------

### CQL0021: foreign key refers to non-existent table 'table_name'

The table in a foreign key REFERENCES clause is not a valid table.

------

### CQL0022: exact type of both sides of a foreign key must match (expected expected_type; found actual_type) 'key_name'

The indicated foreign key has at least one column with a different type than
corresponding column in the table it references. This usually means that you
have picked the wrong table or column in the foreign key declaration.

-----

### CQL0023: number of columns on both sides of a foreign key must match

The number of column in the foreign key must be the same as the number of
columns specified in the foreign table. This usually means a column is missing
in the REFERENCES part of the declaration.

-----

### CQL0024: cursor not declared with 'LIKE table_name', blob type can't be inferred

When using the `cql_cursor_to_blob` function or its equivalent shorthand
`C:to_blob` the cursor must be declared like so `cursor C like table_name` where
`table_name` is the name of a table marked for blob storage  (`[[blob storage]]`).

If this is not the case then the type of the resulting blob cannot be inferred.
If you do not want/need the type to be inferred you can use the form
`cql_cursor_to_blob(a_cursor, a_blob)` or equivalently
`a_cursor:to_blob(a_blob)` in which case no inferred type is required.

-----

### CQL0025: version number in annotation must be positive

In an `@create` or `@delete` annotation, the version number must be > 0. This
error usually means there is a typo in the version number.

-----

### CQL0026: duplicate version annotation

There can only be one `@create`, `@delete`, or `@recreate` annotation for any
given table/column.  More than one `@create` is redundant. This error usually
means the `@create` was cut/paste to make an `@delete` and then not edited or
something like that.

-----

### CQL0027: a procedure can appear in only one annotation 'procedure_name'

The indicated migration procedure e.g. the foo in `@create(5, foo)` appears in
another annotation.  Migration steps should happen exactly once. This probably
means the annotation was cut/paste and the migration proc was not removed.

-----

### CQL0028: FK reference must be exactly one column with the correct type 'column_name'

When a foreign key is specified in the column definition it is the entire
foreign key.  That means the references part of the declaration can only be for
that one column. If you need more columns, you have to declare the foreign key
independently.

-----

### CQL0029: autoincrement column must be [LONG_]INTEGER PRIMARY KEY 'column name'

SQLite is very fussy about autoincrement columns.  The column in question must
be either a LONG INTEGER or an INTEGER and it must be PRIMARY KEY. In fact, CQL
will rewrite LONG INTEGER into INTEGER because only that exact form is
supported, but SQLite INTEGERs can hold LONG values so that's ok. Any other
autoincrement form results in this error.

----

### CQL0030: a column attribute was specified twice on the same column 'column_name'

This error indicates a pattern like "id text not null not null" was found. The
same attribute shouldn't appear twice.

-----

### CQL0031: column can't be primary key and also unique key 'column'

In a column definition, the column can only be marked with at most one of
PRIMARY KEY or UNIQUE

-----

### CQL0032: created columns must be at the end and must be in version order", 'column'

The SQLite ALTER TABLE ADD COLUMN statement is used to add new columns to the
schema.  This statement puts the columns at the end of the table. In order to
make the CQL schema align as closely as possible to the actual sqlite schema you
will get you are required to add columns where SQLite will put them.  This will
help a lot if you ever connect to such a database and start doing `select * from
<somewhere with creates>`

-----

### CQL0033: columns in a table marked @recreate cannot have @create or `@delete`, 'column'

If the table is using the `@recreate` plan then you can add and remove columns
(and other things freely)  you don't need to mark columns with `@create` or
`@delete` just add/remove them. This error prevents the build up of useless
annotations.

-----

### CQL0034: create/delete version numbers can only be applied to columns that are nullable or have a default value 'column'

Any new column added to a schema must have a default value or be nullable so
that its initial state is clear and so that all existing insert statements do
not have to be updated to include it.  Either make the column nullable or give
it a default value.

Similarly, any column being deleted must be nullable or have a default value.
The column can't actually be deleted (not all versions of SQLite support this)
so it will only be "deprecated".  But if the column is not null and has no
default then it would be impossible to write a correct insert statement for the
table with the deleted column.

As a consequence you can neither add nor remove columns that are not null and
have no default.

-----

### CQL0035: column delete version can't be <= column create version", 'column'

You can't `@delete` a column in a version before it was even created.  Probably
there is a typo in one or both of the versions.

-----

### CQL0036: column delete version can't be <= the table create version 'column'

The indicated column is being deleted in a version that is before the table it
is found in was even created.  Probably there is a typo in the delete version.

-----

### CQL0037: column delete version can't be >= the table delete version

The indicated column is being deleted in a version that is after the table has
already been deleted.  This would be redundant.  Probably one or both have a
typo in their delete version.

-----

### CQL0038: column create version can't be `<=` the table create version 'column'

The indicated column is being created in a version that is before the table it
is found in was even created.  Probably there is a typo in the delete version.

-----

### CQL0039: column create version can't be `>=` the table delete version 'column'

The indicated column is being created in a version that that is after it has
already been supposedly deleted.  Probably there is a typo in one or both of the
version numbers.

-----

### CQL0040: table can only have one autoinc column 'column'

The indicated column is the second column to be marked with AUTOINCREMENT in its
table.  There can only be one such column.

-----

### CQL0041: tables cannot have object columns 'column'

The OBJECT data type is only for use in parameters and local variables.  SQLite
has no storage for object references. The valid data types include `INTEGER`,
`LONG INTEGER`, `REAL`, `BOOL`, `TEXT`, `BLOB`

-----

### CQL0042: left operand must be a string in 'LIKE/MATCH/GLOB'

The indicated operator can only be used to compare two strings.

-----

### CQL0043: right operand must be a string in 'LIKE/MATCH/GLOB'

The indicated operator can only be used to compare two strings.

-----

### CQL0044: operator may only appear in the context of a SQL statement 'MATCH'

The MATCH operator is a complex sqlite primitive.  It can only appear within SQL
expressions. See the CQL documentation about it being a two-headed-beast when it
comes to expression evaluation.

-----

### CQL0045: blob operand not allowed in 'operator'

None of the unary math operators e.g. '-' and '~' allow blobs as an operand.

-----

### CQL0046: object operand not allowed in 'operator'

None of the unary math operators e.g. '-' and '~' allow objects as an operand.

-----

### CQL0047: string operand not allowed in 'operator'

None of the unary math operators e.g. '-' and '~' allow strings as an operand.

-----

### CQL0051: argument can only be used in count(*) '*'

The '*' special operator can only appear in the COUNT function. e.g.:

```sql
select count(*) from some_table
```

It is not a valid function argument in any other context.

-----

### CQL0052: select *, T.*, or columns(...) cannot be used with no FROM clause

Select statements of the form `select 1, 'foo';` are `valid but select '*';` is
not. The `*` shortcut for columns only makes sense if there is something to
select from. e.g. `select * from some_table;` is valid.  Similarly `T.*` makes
no sense without a from clause and the @columns(...) construction requires columns.

-----

### CQL0053 available for re-use

-----

### CQL0054: table not found 'table'

The indicated table was used in a select statement like `select T.* from ...`
but no such table was present in the `FROM` clause.

-----

### CQL0055: all columns in the select must have a name

Referring to the select statement on the failing line, that select statement was
used in a context where all the columns must have a name. Examples include
defining a view, a cursor, or creating a result set from a procedure.  The
failing code might look something like this. `select 1, 2 B;`  it needs to look
like this `select 1 A, 2 B`;

-----

### CQL0056: NULL expression has no type to imply a needed type 'variable'

In some contexts the type of a constant is used to imply the type of the
expression.  The NULL literal cannot be used in such contexts because it has no
specific type.

In a SELECT statement the NULL literal has no type.  If the type of the column
cannot be inferred then it must be declared specifically.

In a  LET statement, the same situation arises  `LET x := NULL;`  doesn't
specify what type 'x' is to be.

You can fix this error by changing the `NULL` to something like `CAST(NULL as
TEXT)`.

A common place this problem happens is in defining a view or returning a result
set from a stored procedure.  In those cases all the columns must have a name
and a type.

-----

### CQL0057: if multiple selects, all must have the same column count

If a stored procedure might return one of several result sets, each of the
select statements it might return must have the same number of columns.
Likewise, if several select results are being combined with `UNION` or `UNION
ALL` they must all have the same number of columns.

------

### CQL0058: if multiple selects, all column names must be identical so they have unambiguous names; error in column N: 'X' vs. 'Y'


If a stored procedure might return one of several result sets, each of the
select statements must have the same column names for its result. Likewise, if
several select results are being combined with `UNION` or `UNION ALL` they must
all have the same column names.

This is important so that there can be one unambiguous column name for every
column for group of select statements.

e.g.
```sql
select 1 A, 2 B
union
select 3 A, 4 C;
```
Would provoke this error.  In this case the error would report that the problem
was in column 2 and that error was 'B' vs. 'C'

-----

### CQL0059: a variable name might be ambiguous with a column name, this is an anti-pattern 'name'

The referenced name is the name of a local or a global in the same scope as the
name of a column.  This can lead to surprising results as it is not clear which
name takes priority (previously the variable did rather than the column, now
it's an error).

Example:

```sql
create proc foo(id integer)
begin
  -- this is now an error, in all cases the argument would have been selected
  select id from bar T1 where T1.id != id;
end;
```

To correct this, rename the local/global.  Or else pick a more distinctive
column name, but usually the local is the problem.

-----

### CQL0060: referenced table can be independently recreated so it cannot be used in a foreign key, 'referenced_table'

The referenced table is marked recreate so it must be in the same recreate group
as the current table or in a recreate group that does not introduce a cyclic
foreign key dependency among recreate groups. Otherwise, the referenced table
might be recreated away leaving all the foreign key references in current table
as orphans.

So we check the following: If the referenced table is marked recreate then any
of the following result in CQL0060

 * the containing table is not recreate at all (non-recreate table can't
   reference recreate tables at all), OR
 * the new foreign key dependency between the referenced table and the current
   table introduces a cycle

The referenced table is a recreate table and one of the 4 above conditions was
not met.  Either don't reference it or else put the current table and the
referenced table into the same recreate group.

----

### CQL0061: if multiple selects, all columns must be an exact type match (expected expected_type; found actual_type) 'column'

In a stored proc with multiple possible selects providing the result, all of the
columns of all the selects must be an exact type match.

e.g.

```sql
if x then
  select 1 A, 2 B
else
  select 3 A, 4.0 B;
end if;
```

Would provoke this error.  In this case 'B' would be regarded as the offending
column and the error is reported on the second B.

----

### CQL0062: if multiple selects, all columns must be an exact type match (including nullability) (expected expected_type; found actual_type) 'column'

In a stored proc with multiple possible selects providing the result, all of the
columns of all the selects must be an exact type match. This error indicates
that the specified column differs by nullability.

-----

### CQL0063: can't mix and match out statement with select/call for return values 'procedure_name'

If the procedure is using SELECT to create a result set it cannot also use the
OUT keyword to create a one-row result set.

-----

### CQL0064: object variables may not appear in the context of a SQL statement

SQLite doesn't understand object references, so that means you cannot try to use
a variable or parameter of type object inside of a SQL statement.

e.g.
```sql
create proc foo(X object)
begin
  select X is null;
end;
```

In this example X is an object parameter, but even to use X for an `is null`
check in a select statement would require binding an object which is not
possible.

On the other hand this compiles fine.

```sql
create proc foo(X object, out is_null bool!)
begin
  set is_null := X is null;
end;
```

This is another example of XQL being a two-headed beast.

-----

### CQL0065: identifier is ambiguous 'name'

There is more than one variable/column with indicated name in equally near
scopes.  The most common reason for this is that there are two column in a join
with the same name and that name has not been qualified elsewhere.

e.g.
```sql
SELECT A
  FROM (SELECT 1 AS A, 2 AS B) AS T1
  INNER JOIN (SELECT 1 AS A, 2 AS B) AS T2;
```
There are two possible columns named `A`.  Fix this by using `T1.A` or `T2.A`.

----

### CQL0066: if a table is marked `@recreate`, its indices must be in its schema region 'index_name'

If a table is marked `@recreate` that means that when it changes it is dropped
and created during schema maintenance.  Of course when it is dropped its indices
are also dropped.  So the indices must also be recreated when the table changes.
So with such a table it makes no sense to have indices that are in a different
schema region.  This can only work if they are all always visible together.

Tables on the `@create` plan are not dropped so their indices can be maintained
separately.  So they get a little extra flexibility.

To fix this error move the offending index into the same schema region as the
table.  And probably put them physically close for maintenance sanity.

----

### CQL0067: cursor was not used with 'fetch [cursor]'  'cursor_name'

The code is trying to access fields in the named cursor but the automatic field
generation form was not used so there are no such fields.

e.g.

```sql
var a int;
var b int;
cursor C for select 1 A, 2 B;
fetch C into a, b; -- C.A and C.B not created (!)
if (C.A) then -- error
  ...
end if;
```

Correct usage looks like this:

```sql
cursor C for select 1 A, 2 B;
fetch C;  -- automatically creates C.A and C.B
if (C.A) then
  ...
end if;
```

-----

### CQL0068: field not found in cursor 'field'

The indicated field is not a valid field in a cursor expression.

e.g.

```sql
cursor C for select 1 A, 2 B;
fetch C;  -- automatically creates C.A and C.B
if (C.X) then -- C has A and B, but no X
  ...
end if;
```

----

### CQL0069: name not found 'name'

The indicated name could not be resolved in the scope in which it appears.
Probably there is a typo.  But maybe the name you need isn't available in the
scope you are trying to use it in.

----

### CQL0070: incompatible object type 'incompatible_type'

Two expressions of type object are holding a different object type e.g.

```sql
declare x object<Foo>;
declare y object<Bar>;
set x := y;
```

Here the message would report that 'Bar' is incompatible. The message generally
refers to the 2nd object type as the first one was ok by default then the second
one caused the problem.

-----

### CQL0071: first operand cannot be a blob in 'BETWEEN/NOT BETWEEN'

The BETWEEN operator works on numerics and strings only.

-----

### CQL0072: first operand cannot be a blob in 'BETWEEN/NOT BETWEEN'

The BETWEEN operator works on numerics and strings only.

-----

### CQL0073: CAST may only appear in the context of SQL statement

The CAST function does highly complex and subtle conversions, including
date/time functions and other things.  It's not possibly to emulate this
accurately and there is no sqlite helper to do the job directly from a C call.
Consequently it's only supported in the context of CQL statements.  It can be
used in normal expressions by using the nested `SELECT` form `(select ...)`

-----

### CQL0074: too few arguments provided 'coalesce'

There must be at least two arguments in a call to `coalesce`.

-----

### CQL0075: incorrect number of arguments 'ifnull'

The  `ifnull` function requires exactly two arguments.

-----

### CQL0076: NULL literal is useless in function 'ifnull/coalesce'

Adding a NULL literal to `IFNULL` or `COALESCE` is a no-op.  It's most likely an
error.

-----

### CQL0077: encountered arg known to be not null before the end of the list, rendering the rest useless 'expression'

In an `IFNULL` or `COALESCE` call, only the last argument may be known to be not
null.  If a not null argument comes earlier in the list, then none of the others
could ever be used.  That is almost certainly an error.  The most egregious form
of this error is if the first argument is known to be not null in which case the
entire `IFNULL` or `COALESCE` can be removed.

-----

### CQL0078: [not] in (select ...) is only allowed inside of select lists, where, on, and having clauses

The (select...) option for `IN` or `NOT IN` only makes sense in certain
expression contexts.    Other uses are most likely errors.  It cannot appear in
a loose expression because it fundamentally requires sqlite to process it.

-----

### CQL0079: function got incorrect number of arguments 'name'

The indicated function was called with the wrong number of arguments.  There are
various functions supported each with different rules.  See the SQLite
documentation for more information about the specified function.

-----

### CQL0080: function may not appear in this context 'name'

Many functions can only appear in certain contexts.  For instance most aggregate
functions are limited to the select list or the HAVING clause.  They cannot
appear in, for instance, a WHERE, or ON clause.  The particulars vary by
function.

-----

### CQL0081: aggregates only make sense if there is a FROM clause 'name'

The indicated aggregate function was used in a select statement with no tables.
For instance

```sql
select MAX(7);
```

Doesn't make any sense.

-----

### CQL0082: macro or argument used where it is not allowed 'name'

The indicated macro appeared in a context in which that type of macro is not
allowed. For instance attempting to use a statement list macro where an
expression belongs results in this error.

Macro errors include a detailed trace of the path to the macro with the problem.
The problem could be nested quite deeply.

-----

### CQL0083: macro reference is not a valid macro, 'name'

The indicated macro reference does not refer to an actual macro or macro
argument. There is probably a typo in the name of the macro.

Macro errors include a detailed trace of the path to the macro with the problem.
The problem could be nested quite deeply.

-----

### CQL0084: argument [n] has an invalid type; valid types are: 'type1' 'type2' in 'function'

The argument at the named position is requried to be one of the named types in
the named function.

This message is used for a variety of argument type mismatches in function
invocation.

-----

### CQL0085: @ID expansion is not a valid identifier, 'invalid string'

The result of the concatenation of an `@ID` construct is not a valid identifier.
To be a valid identifier:

* the identifier is a least one character
* the first character must be an alphabetic upper or lower case or underscore
* all other characters must be alphanumeric or underscore

The result of the invalid concatenation is included in the message.

Macro errors include a detailed trace of the path to the macro with the problem.
The problem could be nested quite deeply.

-----

### CQL0086: macro type mismatch in argument, 'formal_name'

A macro invocation tried to satisfy the indicated formal name with an argument
that was the wrong type.  For instance attempting to provide a statement list as
an argument to a macro that expected an expression.

Macro errors include a detailed trace of the path to the macro with the problem.
The problem could be nested quite deeply.

-----

### CQL0087: (not enough/too many) arguments to macro, 'macro_name'

The indicated macro was used with not enough or too many arguments as indicated
by the message (it will be one or the other).

Sometimes this message looks surprising because there are actually mismatched
making more arguments look like fewer.  Check the parens and the total count.

Macro errors include a detailed trace of the path to the macro with the problem.
The problem could be nested quite deeply.

-----

### CQL0088: user function may not appear in the context of a SQL statement 'function_name'

External C functions declared with `function ...` are not for use in
sqlite.  They may not appear inside statements.

-----

### CQL0089: user function may only appear in the context of a SQL statement 'function_name'

SQLite user defined functions (or builtins) declared with  `declare select
function` may only appear inside of sql statements.  In the case of user defined
functions they must be added to sqlite by the appropriate C APIs before they can
be used in CQL stored procs (or any other context really).   See the sqlite
documentation on how to add user defined functions. [Create Or Redefine SQL
Functions](http://www.sqlite.org/c3ref/create_function.html)

-----

### CQL0090: `object<T SET>` has a T that is not a procedure with a result set, 'name'

The data type `object<T SET>` refers to the shape of a result set of a
particular procedure.  In this case the indicated name is not such a procedure.

The most likely source of this problem is that there is a typo in the indicated
name.  Alternatively the name might be a valid shape like a cursor name or some
other shape name but it's a shape that isn't coming from a procedure.

-----

### CQL0091: `object<T SET>` has a T that is not a public procedure with a result set, 'name'

The data type `object<T SET>` refers to the shape of a result set of a
particular procedure.  In this case the indicated procedure name was tagged with
either the `cql:private` attribute or the `cql:suppress_result_set` attribute.

Either of these attributes will make it impossible to actually use this result
set type.  They must be removed.

-----

### CQL0092: RAISE may only be used in a trigger statement

SQLite only supports this kind of control flow in the context of triggers,
certain trigger predicates might need to unconditionally fail and complex logic
can be implemented in this way.  However this sort of thing is not really
recommended.  In any case this is not a general purpose construct.

-----

### CQL0093: RAISE 2nd argument must be a string

Only forms with a string as the second argument are supported by SQLite.

-----

### CQL0094: function not yet implemented 'function'

The indicated function is not implemented in CQL.  Possibly you intended to
declare it with `function` as an external function or `select function` as a
sqlite builtin.  Note not all sqlite builtins are automatically declared.

-----

### CQL0095: table/view not defined 'name'

The indicated name is neither a table nor a view.  It is possible that the
table/view is now deprecated with `@delete` and therefore will appear to not
exist in the current context.

-----

### CQL0096: join using column not found on the left side of the join 'column_name'

In the `JOIN ... USING(x,y,z)` form, all the columns in the using clause must
appear on both sides of the join.  Here the indicated name is not present on the
left side of the join.

-----

### CQL0097: join using column not found on the right side of the join 'column_name'

In the `JOIN ... USING(x,y,z)` form, all the columns in the using clause must
appear on both sides of the join.  Here the indicated name is not present on the
right side of the join.

-----

### CQL0098: left/right column types in join USING(...) do not match exactly 'column_name'

In the `JOIN ... USING(x,y,z)` form, all the columns in the using clause must
appear on both sides of the join and have the same data type.  Here the data
types differ in the named column.

-----

### CQL0099: HAVING clause requires GROUP BY clause

The `HAVING` clause makes no sense unless there is also a `GROUP BY` clause.
SQLite enforces this as does CQL.

-----

### CQL0100: duplicate common table name 'name'

In a `WITH` clause, the indicated common table name was defined more than once.

-----

### CQL0101: too few column names specified in common table expression 'name'

In a `WITH` clause the indicated common table expression doesn't include enough
column names to capture the result of the `select` statement it is associated
with.

e.g.

```sql
WITH foo(a) as (SELECT 1 A, 2 B) ...`
```

The select statement produces two columns the `foo` declaration specifies one.

-----

### CQL0102: too many column names specified in common table expression 'name'


In a `WITH` clause the indicated common table expression has more  column names
than the `select` expression it is associated with.

e.g.

```sql
WITH foo(a, b) as (SELECT 1) ... `
```

The select statement produces one column the `foo` declaration specifies two.

-----

### CQL0103: duplicate table/view name 'name'

The indicated table or view must be unique in its context.  The version at the
indicated line number is a duplicate of a previous declaration.

-----

### CQL0104: view was present but now it does not exist (use `@delete` instead) 'name'

During schema validation, CQL found a view that used to exist but is now totally
gone.  The correct procedure is to mark the view with `@delete` (you can also
make it stub with the same name to save a little space).  This is necessary so
that CQL can know what views should be deleted on client devices during an
upgrade.  If the view is eradicated totally there would be no way to know that
the view should be deleted if it exists.

-----

### CQL0105: object was a view but is now a table 'name'

Converting a view into a table, or otherwise creating a table with the same name
as a view is not legal.

-----

### CQL0106: trigger was present but now it does not exist (use `@delete` instead) 'name'

During schema validation, CQL found a trigger that used to exist but is now
totally gone.  The correct procedure is to mark the trigger with `@delete` (you
can also make it stub with the same name to save a little space).  This is
necessary so that CQL can know what triggers should be deleted on client devices
during an upgrade.  If the trigger is eradicated totally there would be no way
to know that the trigger should be deleted if it exists.  That would be bad.

-----

### CQL0107: delete version can't be <= create version 'name'

Attempting to declare that an object has been deleted before it was created is
an error.  Probably there is a typo in one or both of the version numbers of the
named object.

-----

### CQL0108: table in drop statement does not exist 'table_name'

The indicated table was not declared anywhere.  Note that CQL requires that you
declare all tables you will work with, even if all you intend to do with the
table is drop it.  When you put a `CREATE TABLE` statement in global scope this
only declares a table, it doesn't actually create the table. See the
documentation on DDL for more information.

-----

### CQL0109: cannot drop a view with drop table 'view_name'

The object named in a `DROP TABLE` statement must be a table, not a view.

-----

### CQL0110: view in drop statement does not exist 'view_name'

The indicated view was not declared anywhere.  Note that CQL requires that you
declare all views you will work with, even if all you intend to do with the view
is drop it.  When you put a `CREATE VIEW` statement in global scope this only
declares a view, it doesn't actually create the view.  See the documentation on
DDL for more information.

-----

### CQL0111: cannot drop a table with drop view 'name'

The object named in a `DROP VIEW` statement must be a view, not a table.

-----

### CQL0112: index in drop statement was not declared 'index_name'

The indicated index was not declared anywhere.  Note that CQL requires that you
declare all indices you will work with, even if all you intend to do with the
index is drop it.  When you put a `CREATE INDEX` statement in global scope this
only declares an index, it doesn't actually create the index.  See the
documentation on DDL for more information.

-----

### CQL0113: trigger in drop statement was not declared 'name'

The indicated trigger was not declared anywhere.  Note that CQL requires that
you declare all triggers you will work with, even if all you intend to do with
the trigger is drop it.  When you put a `CREATE TRIGGER` statement in global
scope this only declares a trigger, it doesn't actually create the trigger.  See
the documentation on DDL for more information.

-----

### CQL0114: current schema can't go back to recreate semantics for 'table_name'

The indicated table was previously marked with `@create` indicating it has
precious content and should be upgraded carefully.  The current schema marks the
same table with `@recreate` meaning it has discardable content and should be
upgraded by dropping it and recreating it.  This transition is not allowed.  If
the table really is non-precious now you can mark it with `@delete` and then
make a new similar table with `@recreate`.  This really shouldn't happen very
often if at all.  Probably the error is due to a typo or wishful thinking.

-----

### CQL0115: current create version not equal to previous create version for 'table'

The indicated table was previously marked with `@create` at some version (x) and
now it is being created at some different version (y !=x ).  This not allowed
(if it were then objects might be created in the wrong/different order during
upgrade which would cause all kinds of problems).

-----

### CQL0116: current delete version not equal to previous delete version for 'table'

The indicated table was previously marked with `@delete` at some version (x) and
now it is being deleted at some different version (y != x).  This not allowed
(if it were then objects might be deleted in the wrong/different order during
upgrade which would cause all kinds of problems).

-----

### CQL0117: `@delete` procedure changed in object 'table_name'

The `@delete` attribute can optional include a "migration proc" that is run when
the upgrade happens.  Once set, this proc can never be changed.

-----

### CQL0118: `@create` procedure changed in object 'table_name'

The `@create` attribute can optional include a "migration proc" that is run when
the upgrade happens.  Once set, this proc can never be changed.

-----

### CQL0119: column name is different between previous and current schema 'name'

Since there is no sqlite operation that allows for columns to be renamed,
attempting to rename a column is not allowed.

>NOTE: you can also get this error if you remove a column entirely, or add a
>column in the middle of the list somewhere.

Since columns (also) cannot be reordered during upgrade, CQL expects to find all
the columns in exactly the same order in the previous and new schema.  Any
reordering, or deletion could easily look like an erroneous rename.  New columns
must appear at the end of any existing columns.

-----

### CQL0120: column type is different between previous and current schema 'name'

It is not possible to change the data type of a column during an upgrade, SQLite
provides no such options.  Attempting to do so results in an error.  This
includes nullability.

-----

### CQL0121: column current create version not equal to previous create version 'name'

The indicated column was previously marked with `@create` at some version (x)
and now it is being created at some different version (y !=x ).  This not
allowed (if it were then objects might be created in the wrong/different order
during upgrade which would cause all kinds of problems).


### CQL0122: column current delete version not equal to previous delete version 'name'

The indicated column was previously marked with `@delete` at some version (x)
and now it is being deleted at some different version (y != x).  This not
allowed (if it were then objects might be deleted in the wrong/different order
during upgrade which would cause all kinds of problems).

-----

### CQL0123: column `@delete` procedure changed 'name'

The `@delete` attribute can optional include a "migration proc" that is run when
the upgrade happens.  Once set, this proc can never be changed.

-----

### CQL0124: column `@create` procedure changed 'name'

The `@create` attribute can optional include a "migration proc" that is run when
the upgrade happens.  Once set, this proc can never be changed.

-----

### CQL0125: column current default value not equal to previous default value 'column'

The default value of a column may not be changed in later versions of the
schema.  There is no SQLite operation that would allow this.

-----

### CQL0126: table was present but now it does not exist (use `@delete` instead) 'table'

During schema validation, CQL found a table that used to exist but is now
totally gone.  The correct procedure is to mark the table with `@delete`.  This
is necessary so that CQL can know what tables should be deleted on client
devices during an upgrade.  If the table is eradicated totally there would be no
way to know that the table should be deleted if it exists.  That would be bad.

-----

### CQL0127: object was a table but is now a view 'name'

The indicated object was a table in the previous schema but is now a view in the
current schema.  This transformation is not allowed.

-----

### CQL0128: table has a column that is different in the previous and current schema 'column'

The indicated column changed in one of its more exotic attributes, examples:

* its `FOREIGN KEY` rules changed in some way
* its `PRIMARY KEY` status changed
* its `UNIQUE` status changed

Basically the long form description of the column is now different and it isn't
different in one of the usual way like type or default value.  This error is the
catch all for all the other ways a column could change such as "the FK rule for
what happens when an update fk violation occurs is now different" -- there are
dozens of such errors and they aren't very helpful anyway.

-----

### CQL0129: a column was removed from the table rather than marked with `@delete` 'column_name'

During schema validation, CQL found a column that used to exist but is now
totally gone.  The correct procedure is to mark the column with `@delete`.  This
is necessary so that CQL can know what columns existed during any version of the
schema, thereby allowing them to be used in migration scripts during an upgrade.
If the column is eradicated totally there would be no way to know that the
exists, and should no longer be used.  That would be bad.

Of course `@recreate` tables will never get this error because they can be
altered at whim.

-----

### CQL0130: table has columns added without marking them `@create` 'column_name'

The indicated column was added but it was not marked with `@create`.  The table
in question is not on the `@recreate` plan so this is an error.  Add a suitable
`@create` annotation to the column declaration.

-----

### CQL0131: table has newly added columns that are marked both `@create` and `@delete` 'column_name'

The indicated column was simultaneously marked `@create` and `@delete`.  That's
surely some kind of typo.  Creating a column and deleting it in the same version
is weird.

-----

### CQL0132: table has a facet that is different in the previous and current schema 'table_name'

The indicated table has changes in one of its non-column features.  These
changes might be:

* a primary key declaration
* a unique key declaration
* a foreign key declaration

None of these are allowed to change.  Of course `@recreate` tables will never
get this error because they can be altered at whim.

-----

### CQL0133: non-column facets have been removed from the table 'name'

The error indicates that the table has had some stuff removed from it.  The
"stuff" might be:

* a primary key declaration
* a unique key declaration
* a foreign key declaration

Since there is no way to change any of the constraints after the fact, they may
not be changed at all if the table is on the `@create` plan.  Of course
`@recreate` tables will never get this error because they can be altered at
whim.

-----

### CQL0134: table has a new non-column facet in the current schema 'table_name'

The error indicates that the table has had some stuff added to it.  The "stuff"
might be:

* a primary key declaration
* a unique key declaration
* a foreign key declaration

Since there is no way to change any of the constraints after the fact, they may
not be changed at all if the table is on the `@create` plan.  Of course
`@recreate` tables will never get this error because they can be altered at
whim.

-----

### CQL0135: table create statement attributes different than previous version 'table_name'

The 'flags' on the `CREATE TABLE` statement changed between versions.  These
flags capture the options like the`TEMP` in `CREATE TEMP TABLE` and the `IF NOT
EXISTS`.   Changing these is not allowed.

-----

### CQL0136: trigger already exists 'trigger_name'

Trigger names may not be duplicated.  Probably there is copy/pasta going on
here.

-----

### CQL0137: table/view not found 'name'

In a `CREATE TRIGGER` statement, the indicated name is neither a table or a
view.  Either a table or a view was expected in this context.

-----

### CQL0138: a trigger on a view must be the INSTEAD OF form 'name'

In a `CREATE TRIGGER` statement, the named target of the trigger was a view but
the trigger type is not `INSTEAD OF`.  Only `INSTEAD OF` can be applied to views
because views are not directly mutable so none of the other types make sense.
e.g. there can be no delete operations, on a view, so `BEFORE DELETE` or `AFTER
DELETE` are not really a thing.

-----

### CQL0139: temp objects may not have versioning annotations 'object_name'

The indicated object is a temporary.  Since temporary  do not survive sessions
it makes no sense to try to version them for schema upgrade. They are always
recreated on demand.  If you need to remove one, simply delete it entirely, it
requires no tombstone.

-----

### CQL0140: columns in a temp table may not have versioning attributes 'column_name'

The indicated column is part of a temporary table.  Since temp tables do not
survive sessions it makes no sense to try to version their columns for schema
upgrade.  They are always recreated on demand.

-----

### CQL0141: table has an AUTOINCREMENT column; it cannot also be WITHOUT ROWID 'table_name'

SQLite uses its `ROWID` internally for `AUTOINCREMENT` columns.  Therefore
`WITHOUT ROWID` is not a possibility if `AUTOINCREMENT` is in use.

-----

### CQL0142: duplicate column name 'column_name'

In a `CREATE TABLE` statement, the indicated column was defined twice.  This is
probably a copy/pasta issue.

-----

### CQL0143: more than one primary key in table 'table_name'

The indicated table has more than one column with the `PRIMARY KEY` attribute or
multiple `PRIMARY KEY` constraints, or a combination of these things.  You'll
have to decide which one is really intended to be primary.

-----

### CQL0144: cannot alter a view 'view_name'

In an `ALTER TABLE` statement, the table to be altered is actually a view.  This
is not allowed.

-----

### CQL0144: table in alter statement does not exist 'table_name'

In an `ALTER TABLE` statement, the table to be altered was not defined, or
perhaps was marked with `@delete` and is no longer usable in the current schema
version.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0145: version annotations not valid in alter statement 'column_name'

In an `ALTER TABLE` statement, the attributes on the column may not include
`@create` or `@delete`.  Those annotations go on the columns declaration in the
corresponding `CREATE TABLE` statement.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0146: adding an auto increment column is not allowed 'column_name'

In an `ALTER TABLE` statement, the attributes on the column may not include
`AUTOINCREMENT`.  SQLite does not support the addition of new `AUTOINCREMENT`
columns.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0147: adding a not nullable column with no default value is not allowed 'column_name'

In an `ALTER TABLE` statement the attributes on the named column must include a
default value or else the column must be nullable.  This is so that SQLite knows
what value to put on existing rows when the column is added and also so that any
existing insert statements will not suddenly all become invalid.  If the column
is nullable or has a default value then the existing insert statements that
don't specify the column will continue to work, using either NULL or the
default.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0148: added column must already be reflected in declared schema, with `@create`, exact name match required 'column_name'

In CQL loose schema is a declaration, it does not actually create anything
unless placed inside of a procedure.  A column that is added with `ALTER TABLE`
is not actually declared as part of the schema by the `ALTER`.  Rather the
schema declaration is expected to include any columns you plan to add.  Normally
the way this all happens is that you put `@create` notations on a column in the
schema and the automatic schema upgrader then creates suitable `ALTER TABLE`
statements to arrange for that column to be added.  If you manually write an
`ALTER TABLE` statement it isn't allowed to add columns at whim; in some sense
it must be creating the reality already described in the declaration.  This is
exactly what the automated schema upgrader does -- it declares the end state and
then alters the world to get to that state.

It's important to remember that from CQL's perspective the schema is fixed for
any given compilation, so runtime alterations to it are not really part of the
type system.  They can't be.  Even `DROP TABLE` does not remove the table from
type system -- it can't -- the most likely situation is that you are about to
recreate that same table again for another iteration with the proc that creates
it.

This particular error is saying that the column you are trying to add does not
exist in the declared schema.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0149: added column must be an exact match for the column type declared in the table 'column_name'

In CQL loose schema is a declaration, it does not actually create anything
unless placed inside of a procedure.  A column that is added with `ALTER TABLE`
is not actually declared as part of the schema by the `ALTER`.  Rather the
schema declaration is expected to include any columns you plan to add.  Normally
the way this all happens is that you put `@create` notations on a column in the
schema and the automatic schema upgrader then creates suitable `ALTER TABLE`
statements to arrange for that column to be added.  If you manually write an
`ALTER TABLE` statement it isn't allowed to add columns at whim; in some sense
it must be creating the reality already described in the declaration.  This is
exactly what the automated schema upgrader does -- it declares the end state and
then alters the world to get to that state.

It's important to remember that from CQL's perspective the schema is fixed for
any given compilation, so runtime alterations to it are not really part of the
type system.  They can't be.  Even `DROP TABLE` does not remove the table from
type system -- it can't -- the most likely situation is that you are about to
recreate that same table again for another iteration with the proc that creates
it.

This particular error is saying that the column you are trying to add exists in
the declared schema, but its definition is different than you have specified in
the `ALTER TABLE` statement.

>NOTE: `ALTER TABLE` is typically not used directly; the automated schema
>upgrade script generation system uses it.

-----

### CQL0150: expected numeric expression in IF predicate

In an `IF` statement the condition (predicate) must be a numeric.  The body of
the `IF` runs if the value is not null and not zero.

-----

### CQL0151: table in delete statement does not exist 'table_name'

In a `DELETE` statement, the indicated table does not exist. Probably it's a
spelling mistake, or else the table has been marked with `@delete` and may no
longer be used in `DELETE` statements.

-----

### CQL0152: cannot delete from a view 'view_name'

In a `DELETE` statement, the target of the delete must be a table, but the
indicated name is a view.

-----

### CQL0153: duplicate target column name in update statement 'column_name'

In an `UPDATE` statement, you can only specify any particular column to update
once.

e.g. `UPDATE coordinates set x = 1, x = 3;`  will produce this error. `UPDATE
coordinates set x = 1, y = 3;` might be correct.

This error is most likely caused by a typo or a copy/pasta of the column names,
especially if they were written one per line.

-----

### CQL0154: table in update statement does not exist 'table_name'

In an `UPDATE` statement, the target table does not exist.  Probably it's a
spelling mistake, or else the table has been marked with `@delete` and may no
longer be used in `UPDATE` statements.

-----

### CQL0155: cannot update a view 'view_name'

In an `UPDATE` statement, the target of the update must be a table but the name
of a view was provided.

-----

### CQL0156: seed expression must be a non-nullable integer

The `INSERT` statement statement supports the notion of synthetically generated
values for dummy data purposes.  A 'seed' integer is used to derive the values.
That seed (in the `@seed()` position) must be a non-null integer.

The most common reason for this error is that the seed is an input parameter and
it was not declared `NOT NULL`.

-----

### CQL0157: count of columns differs from count of values

In an `INSERT` statement of the form `INSERT INTO foo(a, b, c) VALUES(x, y, z)`
the number of values (x, y, z) must be the same as the number of columns (a, b,
c).  Note that there are many reasons you might not have to specify all the
columns of the table but whichever columns you do specify should have values.

-----

### CQL0158: required column missing in INSERT statement 'column_name'

In an `INSERT` statement such as `INSERT INTO foo(a,b,c) VALUES(x,yz)` this
error is indicating that there is a column in `foo` (the one indicated in the
error) which was not in the list (i.e. not one of a, b, c) and that column is
neither nullable, nor does it have a default value.  In order to insert a row a
value must be provided.  To fix this include the indicated column in your insert
statement.

-----

### CQL0159: cannot add an index to a virtual table 'table_name'

Adding an index to a virtual table isn't possible, the virtual table includes
whatever indexing its module provides, no further indexing is possible.

From the SQLite documentation: "One cannot create additional indices on a
virtual table. (Virtual tables can have indices but that must be built into the
virtual table implementation. Indices cannot be added separately using CREATE
INDEX statements.)"

-----

### CQL0160: table in insert statement does not exist 'table_name'

In an `INSERT` statement attempting to insert into the indicated table name is
not possible because there is no such table. This error might happen because of
a typo, or it might happen because the indicated table has been marked with
`@delete` and is logically hidden.

-----

### CQL0161: cannot insert into a view 'view_name'

In an `INSERT` statement attempting to insert into the indicated name is not
possible because that name is a view not a table.  Inserting into views is not
supported.

-----

### CQL0162: cannot add a trigger to a virtual table 'table_name'

Adding a trigger to a virtual table isn't possible.

From the SQLite documentation: "One cannot create a trigger on a virtual table."

-----

### CQL0163: FROM ARGUMENTS construct is only valid inside a procedure

Several statements support the `FROM ARGUMENTS` sugar format like `INSERT INTO
foo(a,b,c) FROM ARGUMENTS` which causes the arguments of the current procedure
to be used as the values.  This error is complaining that you have used this
form but the statement does not occur inside of a procedure so there can be no
arguments.  This form does not make sense outside of any procedure.

-----

### CQL0164: cannot use ALTER TABLE on a virtual table 'table_name'

This is not supported by SQLite.

From the SQLite documentation: "One cannot run ALTER TABLE ... ADD COLUMN
commands against a virtual table."

-----

### CQL0165: fetch values is only for value cursors, not for sqlite cursors 'cursor_name'

Cursors come in two flavors.  There are "statement cursors" which are built from
something like this:

```sql
cursor C for select * from foo;
fetch C;
-- or --
fetch C into a, b, c;
```

That is, they come from a SQLite statement and you can fetch values from that
statement.  The second type comes from procedural values like this.

```sql
cursor C like my_table;
fetch C from values(1, 2, 3);
```

In the second example `C`'s data type will be the same as the columns in
`my_table` and we will fetch its values from `1,2,3` -- this version has no
database backing at all, it's just data.

This error says that you declared the cursor in the first form (with a SQL
statement) but then you tried to fetch it using the second form, the one for
data. These forms don't mix.   If you need a value cursor for a row you can copy
data from one cursor into another.

-----

### CQL0166: count of columns differs from count of values

In a value cursor, declared something like this:
```sql
cursor C like my_table;
fetch C from values(1, 2, 3);
```
The type of the cursor ( in this case from `my_table`) requires a certain number
of columns, but that doesn't match the number that were provided in the values.

To fix this you'll need to add/remove values so that the type match.

-----

### CQL0167: required column missing in FETCH statement 'column_name'

In a value cursor, declared something like this:
```sql
cursor C like my_table;
fetch C(a,b,c) from values(1, 2, 3);
```

This error is saying that there is some other field in the table 'd' and it was
not specified in the values.  Nor was there a usable dummy data for that column
that could be used.  You need to provide a value for the missing column.

-----

### CQL0168: statement requires a RETURNING clause to be used as a source of rows

An insert/delete/update statement lacking the RETURNING clause does not produce any result
therefore it is not suitable for use to fill a cursor or other such things
that need results.  With the RETURNING clause the same statement is, in
very real way, behaving like a special SELECT.  It can therefore be used in a cursor.

-----

### CQL0169: enum not found 'enum_name'

The indicated name was used in a context where an enumerated type name was
expected but there is no such type.

Perhaps the enum was not included (missing an @include?) or else there is a typo.

-----

### CQL0170: cast is redundant, remove to reduce code size 'expression'

The operand of the `CAST` expression is already the type that it is being cast
to.  The cast will do nothing but waste space in the binary and make the code
less clear.  Remove it.

-----

### CQL0171: name not found 'name'

In a scoped name list, like the columns of a cursor (for a fetch), or the
columns of a particular table (for an index) a name appeared that did not belong
to the universe of legal names.  Trying to make a table index using a column
that is not in the table would produce this error.  There are many instances
where a list of names belongs to some limited scope.

-----

### CQL0172: name list has duplicate name 'name'

In a scoped name list, like the columns of a cursor (for a fetch), or the
columns of a particular table (for an index) a name appeared twice in the list
where the names must be unique.  Trying to make a table index using the same
column twice would produce this error.

-----

### CQL0173: variable not found 'variable_name'

In a `SET` statement, the target of the assignment is not a valid variable name
in that scope.

-----

### CQL0174: cannot set a cursor 'cursor_name'

In a `SET` statement, the target of the assignment is a cursor variable, you
cannot assign to a cursor variable.

-----

### CQL0175: duplicate parameter name 'parameter_name'

In a parameter list for a function or a procedure, the named parameter appears
more than once.  The formal names for function arguments must be unique.

-----

### CQL0176: indicated procedure or group already has a recreate action 'name'

There can only be one migration rule for a table or group, the indicated item
already has such an action.  If you need more than one migration action you can
create a containing procedure that dispatches to other migrators.

-----

### CQL0177: global constants must be either constant numeric expressions or string literals 'constant_definition'

Global constants must be either a combination other constants for numeric
expressions or else string literals.  The indicated expression was not one of
those.

This can happen if the expression uses variables, or has other problems that
prevent it from evaluating, or if a function is used that is not supported.

-----

### CQL0178: proc has no result 'like_name'

In an argument list, the `LIKE` construct was used to create arguments that are
the same as the return type of the named procedure.  However the named procedure
does not produce a result set and therefore has no columns to mimic.  Probably
the name is wrong.

-----

### CQL0179: shared fragments must consist of exactly one top level statement 'procedure_name'

Any shared fragment can have only one statement.  There are three valid forms --
IF/ELSE, WITH ... SELECT, and SELECT.

This error indicates the named procedure, which is a shared fragment, has more
than one statement.

-----

### CQL0180: duplicate column name in result not allowed 'column_name'

In a procedure that returns a result either with a loose `SELECT` statement or
in a place where the result of a `SELECT` is captured with a `FETCH` statement
the named column appears twice in the projection of the `SELECT` in question.
The column names must be unique in order to have consistent cursor field names
or consistent access functions for the result set of the procedure.  One
instance of the named column must be renamed with something like `select T1.foo
first_foo, T2.foo second_foo`.

-----

### CQL0181: autodrop temp table does not exist 'name'

In a `cql:autodrop` annotation, the given name is unknown entirely.

-----

### CQL0182: autodrop target is not a table 'name'

In a `cql:autodrop` annotation, the given name is not a table (it's probably a
view).

-----

### CQL0183: autodrop target must be a temporary table 'name'

In a `cql:autodrop` annotation, the given name is a table but it is not a temp
table.  The annotation is only valid on temp tables, it's not for "durable"
tables.

-----

### CQL0184: stored procedures cannot be nested 'name'

The `CREATE PROCEDURE` statement may not appear inside of another stored
procedure.  The named procedure appears in a nested context.

-----

### CQL0185: proc name conflicts with func name 'name'

In a `CREATE PROCEDURE` statement, the given name conflicts with an already
declared function (`DECLARE FUNCTION` or `DECLARE SELECT FUNCTION`).  You'll
have to choose a different name.

-----

### CQL0186: duplicate stored proc name 'name'

In a `CREATE PROCEDURE` statement, the indicated name already corresponds to a
created (not just declared) stored procedure.  You'll have to choose a different
name.

-----

### CQL0187: @schema_upgrade_version not declared or doesn't match upgrade version `N` for proc 'name'

The named procedure was declared as a schema migration procedure in an `@create`
or `@delete` annotation for schema version `N`.  In order to correctly type
check such a procedure it must be compiled in the context of schema version `N`.
This restriction is required so that the tables and columns the procedure sees
are the ones that existed in version `N` not the ones that exist in the most
recent version as usual.

To create this condition, the procedure must appear in a file that begins with
the line:

```sql
@schema_upgrade_version <N>;
```

And this declaration must come before any `CREATE TABLE` statements.  If there
is no such declaration, or if it is for the wrong version, then this error will
be generated.

-----

### CQL0188: procedure is supposed to do schema migration but it doesn't have any DML 'name'

The named procedure was declared as a schema migration procedure in an `@create`
or `@delete` annotation, however the procedure does not have any DML in it.
That can't be right.  Some kind of data reading and writing is necessary.

-----

### CQL0189: procedure declarations/definitions do not match 'name'

The named procedure was previously declared with a `DECLARE PROCEDURE` statement
but when the `CREATE PROCEDURE` was encountered, it did not match the previous
declaration.

-----

### CQL0190: duplicate column name 'name'

In a context with a typed name list (e.g. `id integer, t text`) the named column
occurs twice.  Typed name lists happen in many contexts, but a common one is the
type of the result in a declared procedure statement or declared function
statement.

-----

### CQL0191: declared functions must be top level 'function_name'

A `DECLARE FUNCTION` statement for the named function is happening inside of a
procedure.  This is not legal.  To correct this move the declaration outside of
the procedure.

-----

### CQL0192: func name conflicts with proc name 'name'

The named function in a `DECLARE FUNCTION` statement conflicts with an existing
declared or created procedure.  One or the other must be renamed to resolve this
issue.

-----

### CQL0193: duplicate function name 'name'

The named function in a `DECLARE FUNCTION` statement conflicts with an existing
declared function, or it was declared twice.  One or the other declaration must
be renamed or removed to resolve this issue.

-----

### CQL0194: declared procedures must be top level 'name'

A `DECLARE PROCEDURE` statement for the named procedure is itself happening
inside of a procedure.  This is not legal.  To correct this move the declaration
outside of the procedure.

-----

### CQL0195: proc name conflicts with func name 'name'

The named procedure in a `DECLARE PROCEDURE` statement conflicts with an
existing declared function.  One or the other declaration must be renamed or
removed to resolve this issue.

-----

### CQL0196: procedure declarations/definitions do not match 'name'

The named procedure was previously declared with a `DECLARE PROCEDURE`
statement.  Now there is another declaration and it does not match the previous
declaration

-----

### CQL0197: duplicate variable name in the same scope 'name'

In a `DECLARE` statement, a variable of the same name already exists in that
scope.  Note that CQL does not have block level scope, all variables are
procedure level, so they are in scope until the end of the procedure.  To
resolve this problem, either re-use the old variable if appropriate or rename
the new variable.

-----

### CQL0198: global variable hides table/view name 'name'

In a `DECLARE` statement, the named variable is a global (declared outside of
any procedure) and has the same name as a table or view.  This creates a lot of
confusion and is therefore disallowed.  To correct the problem, rename the
variable.  Global variables generally are problematic, but sometimes necessary.

-----

### CQL0199: cursor requires a procedure that returns a result set via select 'procedure_name'

In a `DECLARE` statement that declares a `CURSOR FOR CALL` the procedure that is
being called does not produce a result set with the `SELECT` statement.  As it
has no row results it is meaningless to try to put a cursor on it.  Probably the
error is due to a copy/pasta of the procedure name.

-----

### CQL0200: variable is not a cursor 'another_cursor'

In a `DECLARE` statement that declares a `CURSOR LIKE` another cursor, the
indicated name is a variable but it is not a cursor, so we cannot make another
cursor like it.  Probably the error is due to a typo in the 'like_name'.

-----

### CQL0201: expanding FROM ARGUMENTS, there is no argument matching 'required_arg'

In an `INSERT` or `FETCH` statement using the form `FROM ARGUMENTS(LIKE [name])`
The shape `[name]` had columns that did not appear in as arguments to the
current procedure. Maybe arguments are missing or maybe the name in the `like`
part is the wrong name.

-----

### CQL0202: must be a cursor, proc, table, or view 'like_name'

In a `DECLARE` statement that declares a `CURSOR LIKE` some other name, the
indicated name is not the name of any of the things that might have a valid
shape to copy, like other cursors, procedures, tables, or views.  Probably there
is a typo in the name.

-----

### CQL0203: cursor requires a procedure that returns a cursor with OUT 'cursor_name'

In the `DECLARE [cursor_name] CURSOR FETCH FROM CALL <something>` form, the code
is trying to create the named cursor by calling a procedure that doesn't
actually produce a single row result set with the `OUT` statement.  The
procedure is valid (that would be a different error) so it's likely that the
wrong procedure is being called rather than being an outright typo.  Or perhaps
the procedure was changed such that it no longer produces a single row result
set.

This form is equivalent to:

```sql
DECLARE [cursor_name] LIKE procedure;
FETCH [cursor_name] FROM CALL procedure(args);
```

It's the declaration that's failing here, not the call.

-----

### CQL0204 available for re-use

-----

### CQL0205: not a cursor 'name'

The indicated name appeared in a context where the name of a cursor was
expected, but the name does not refer to a cursor.

-----

### CQL0206: duplicate name in list 'name'

There are many contexts where a list of names appears in the CQL grammar and the
list must not contain duplicate names.  Some examples are:

* the column names in a `JOIN ... USING(x,y,z,...)` clause
* the fetched variables in a `FETCH [cursor] INTO x,y,z...` statement
* the column names listed in a common table expression `CTE(x,y,z,...) as
  (SELECT ...)`
* the antecedent schema region names in `@declare_schema_region <name> USING
  x,y,z,...`

The indicated name was duplicated in such a context.

-----

### CQL0207: expected a variable name for OUT or INOUT argument 'param_name'

In a procedure call, the indicated parameter of the procedure is an OUT or INOUT
parameter but the call site doesn't have a variable in that position in the
argument list.

Example:

```sql
declare proc foo(out x int);

-- the constant 1 cannot be used in the out position when calling foo
call foo(1); '
```
-----

### CQL0208: shared fragments cannot have any out or in/out parameters 'param_name'

A shared fragment will be expanded into the body of a SQL select statement, as
such it can have no side-effects such as out arguments.

-----

### CQL0209: proc out parameter: arg must be an exact type match (expected expected_type; found actual_type) 'param_name'

In a procedure call, the indicated parameter is in an 'out' position, it is a
viable local variable but it is not an exact type match for the parameter.  The
type of variable used to capture out parameters must be an exact match.

```sql
declare proc foo(out x int);

create proc bar(out y real)
begin
  call foo(y); -- y is a real variable, not an integer.
end;
```

The above produces:
```sql
CQL0209: proc out parameter: arg must be an exact type match
(expected integer; found real) 'y'
```

-----

### CQL0210: proc out parameter: arg must be an exact type match (even nullability)
(expected expected_type; found actual_type) 'variable_name'

In a procedure call, the indicated parameter is in an 'out' position, it is a
viable local variable of the correct type but the nullability does not match.
The type of variable used to capture out parameters must be an exact match.

```sql
declare proc foo(out x int!);

create proc bar(out y integer)
begin
  call foo(y); -- y is nullable but foo is expecting not null.
end;
```

The above produces:
```sql
CQL0210: proc out parameter: arg must be an exact type match (even nullability)
(expected integer notnull; found integer) 'y'
```

-----

### CQL0211: procedure without trailing OUT parameter used as function 'procedure_name'

In a function call, the target of the function call was a procedure, procedures
can be used like functions but their last parameter must be marked `out`. That
will be the return value.  In this case the last argument was not marked as
`out` and so the call is invalid.

Example:

```sql
declare proc foo(x integer);

create proc bar(out y integer)
begin
  set y := foo(); -- foo does not have an out argument at the end
end;
```

-----

### CQL0212: too few arguments provided to procedure 'name'

In a procedure call to the named procedure, not enough arguments were provided
to make the call.  One or more arguments may have been omitted or perhaps the
called procedure has changed such that it now requires more arguments.

-----

### CQL0213: procedure had errors, can't call. 'procedure_name'

In a procedure call to the named procedure, the target of the call had
compilation errors.  As a consequence this call cannot be checked and therefore
must be marked in error, too.  Fix the errors in the named procedure.

-----

### CQL0214: procedures with results can only be called using a cursor in global context 'name'

The named procedure results a result set, either with the `SELECT` statement or
the `OUT` statement.  However it is being called from outside of any procedure.
Because of this, its result cannot then be returned anywhere.  As a result, at
the global level the result must be capture with a cursor.

Example:
```sql
create proc foo()
begin
  select * from bar;
end;

call foo();  -- this is not valid
declare cursor C for call foo();  -- C captures the result of foo, this is ok.
```
-----

### CQL0215: value cursors are not used with FETCH C, or FETCH C INTO 'cursor_name'

In a `FETCH` statement of the form `FETCH [cursor]` or `FETCH [cursor] INTO` the
named cursor is a value cursor.  These forms of the `FETCH` statement apply only
to statement cursors.

Example:good

```sql
-- value cursor shaped like a table
cursor C for select * from bar;
--ok, C is fetched from the select results
fetch C;
```
Example: bad
```sql
-- value cursor shaped like a table
cursor C like bar;
-- invalid, there is no source for fetching a value cursor
fetch C;
-- ok assuming bar is made up of 3 integers
fetch C from values(1,2,3);
```

* statement cursors come from SQL statements and can be fetched
* value cursors are of a prescribed shape and can only be loaded from value
  sources

-----

### CQL0216: FETCH variable not found 'cursor_name'

In a `FETCH` statement,  the indicated name, which is supposed to be a cursor,
is not in fact a valid name at all.

Probably there is a typo in the name.  Or else the declaration is entirely
missing.

-----

### CQL0217: number of variables did not match count of columns in cursor 'cursor_name'

In a `FETCH [cursor] INTO [variables]` the number of variables specified did not
match the number of columns in the named cursor.  Perhaps the source of the
cursor (a select statement or some such) has changed.

-----

### CQL0218: continue must be inside of a 'loop' or 'while' statement

The `CONTINUE` statement may only appear inside of looping constructs.  CQL only
has two `LOOP FETCH ...` and `WHILE`

-----

### CQL0219: leave must be inside of a 'loop', 'while', or 'switch' statement

The `LEAVE` statement may only appear inside of looping constructs or the switch
statement.

CQL has two loop types: `LOOP FETCH ...` and `WHILE` and of course the `SWITCH`
statement.

The errant `LEAVE` statement is not in any of those.

-----

### CQL0220: savepoint has not been mentioned yet, probably wrong 'name'

In a `ROLLBACK` statement that is rolling back to a named savepoint, the
indicated savepoint was never mentioned before.  It should have appeared
previously in a `SAVEPOINT` statement.  This probably means there is a typo in
the name.

-----

### CQL0221: savepoint has not been mentioned yet, probably wrong 'name'

In a `RELEASE SAVEPOINT` statement that is rolling back to a named savepoint,
the indicated savepoint was never mentioned before.  It should have appeared
previously in a `SAVEPOINT` statement.  This probably means there is a typo in
the name.

-----

### CQL0222: out cursor statement only makes sense inside of a procedure

The statement form `OUT [cursor_name]` makes a procedure that returns a single
row result set.  It doesn't make any sense to do this outside of any procedure
because there is no procedure to return that result.  Perhaps the `OUT`
statement was mis-placed.

-----

### CQL0223: cursor was not fetched with the auto-fetch syntax 'fetch [cursor]' 'cursor_name'

The statement form `OUT [cursor_name]` makes a procedure that returns a single
row result set that corresponds to the current value of the cursor.  If the
cursor never held values directly then there is nothing to return.

Example:

```sql
cursor C for select * from bar;
out C;  -- error C was never fetched

cursor C for select * from bar;
fetch C into x, y, z;
-- error C was used to load x, y, z so it's not holding any data
out C;

cursor C for select * from bar;
-- create storage in C to hold bar columns (e.g. C.x, C,y, C.z)
fetch C;
-- ok, C holds data
out C;
```

-----

### CQL0224: a CALL statement inside SQL may call only a shared fragment i.e. [[shared_fragment]]

Inside of a WITH clause you can create a CTE by calling a shared fragment like
so:

```
WITH
  my_shared_something(*) AS (CALL shared_proc(5))
SELECT * from my shared_something;
```

or you can use a nested select expression like

```
 SELECT * FROM (CALL shared_proc(5)) as T;
```

However `shared_proc` must define a shareable fragment, like so:

```
[[shared_fragment]]
create proc shared_proc(lim_ integer)
begin
   select * from somewhere limit lim_;
end;
```

Here the target of the CALL is not a shared fragment.

-----

### CQL0225: switching to previous schema validation mode must be outside of any proc

The `@previous_schema` directive says that any schema that follows should be
compared against what was declared before this point.  This gives CQL the
opportunity to detect changes in schema that are not supportable.

The previous schema directive must be outside of any stored procedure.

Example:
```sql
@previous_schema;  -- ok here

create proc foo()
begin
  @previous schema; -- nope
end;
```
-----

### CQL0226: schema upgrade declaration must be outside of any proc

The `@schema_upgrade_script` directive tells CQL that the code that follows is
intended to upgrade schema from one version to another.  This kind of script is
normally generated by the `--rt schema_upgrade` option discussed elsewhere.
When processing such a script, a different set of rules are used for DDL
analysis.  In particular, it's normal to declare the final versions of tables
but have DDL that creates the original version and more DDL to upgrade them from
wherever they are to the final version (as declared).  Ordinarily these
duplicate definitions would produce errors.  This directive allows those
duplications.

This error is reporting that the directive happened inside of a stored
procedure, this is not allowed.

Example:
```sql
@schema_upgrade_script;  -- ok here

create proc foo()
begin
  @schema_upgrade_script; -- nope
end;
```
-----

### CQL0227: schema upgrade declaration must come before any tables are declared

The `@schema_upgrade_script` directive tells CQL that the code that follows is
intended to upgrade schema from one version to another.  This kind of script is
normally generated by the `--rt schema_upgrade` option discussed elsewhere.
When processing such a script, a different set of rules are used for DDL
analysis.  In particular, it's normal to declare the final versions of tables
but have DDL that creates the original version and more DDL to upgrade them from
wherever they are to the final version (as declared).  Ordinarily these
duplicate definitions would produce errors.  This directive allows those
duplications.

In order to do its job properly the directive must come before any tables are
created with DDL.  This error tells you that the directive came too late in the
stream. Or perhaps there were two such directives and one is late in the stream.

-----

### CQL0228: schema upgrade version must be a positive integer

When authoring a schema migration procedure that was previously declared in an
`@create` or `@delete` directive, the code in that procedure expects to see the
schema as it existed at the version it is to migrate.  The
`@schema_upgrade_version` directive allows you to set the visible schema version
to something other than the latest. There can only be one such directive.

This error says that the version you are trying to view is not a positive
integer version (e.g version -2)

-----

### CQL0229: schema upgrade version declaration may only appear once

When authoring a schema migration procedure that was previously declared in an
`@create` or `@delete` directive, the code in that procedure expects to see the
schema as it existed at the version it is to migrate.  The
`@schema_upgrade_version` directive allows you to set the visible schema version
to something other than the latest.  There can only be one such directive.

This error says that a second `@schema_upgrade_version` directive has been
found.

-----

### CQL0230: schema upgrade version declaration must be outside of any proc

When authoring a schema migration procedure that was previously declared in an
`@create` or `@delete` directive, the code in that procedure expects to see the
schema as it existed at the version it is to migrate.  The
`@schema_upgrade_version` directive allows you to set the visible schema version
to something other than the latest.  There can only be one such directive.

This error says that the `@schema_upgrade_version` directive was found inside of
a stored procedure.  This is not allowed.

-----

### CQL0231: schema upgrade version declaration must come before any tables are declared

When authoring a schema migration procedure that was previously declared in an
`@create` or `@delete` directive, the code in that procedure expects to see the
schema as it existed at the version it is to migrate.  The
`@schema_upgrade_version` directive allows you to set the visible schema version
to something other than the latest.  There can only be one such directive.

This error says that the `@schema_upgrade_version` directive came after tables
were already declared.  This is not allowed, the directive must come before any
DDL.

-----

### CQL0232: nested select expression must return exactly one column

In a `SELECT` expression like `set x := (select id from bar)` the select
statement must return exactly one column as in the example provided.  Note that
a runtime error will ensue if the statement returns zero rows, or more than one
row,  so this form is very limited.  To fix this error change your select
statement to return exactly one column.  Consider how many rows you will get
very carefully also, that cannot be checked at compile time.

-----

### CQL0233: procedure previously declared as schema upgrade proc, it can have no args 'procedure_name'

When authoring a schema migration procedure that was previously declared in an
`@create` or `@delete` directive that procedure will be called during schema
migration with no context available.  Therefore, the schema migration proc is
not allowed to have any arguments.

-----

### CQL0234: autodrop annotation can only go on a procedure that returns a result set 'procedure_name'

The named procedure has the `autodrop` annotation (to automatically drop a
temporary table) but the procedure in question doesn't return a result set so it
has no need of the autodrop feature.  The purpose that that feature is to drop
the indicated temporary tables once all the select results have been fetched.

-----

### CQL0235: too many arguments provided to procedure 'procedure_name'

In a `CALL` statement, or a function call, the named procedure takes fewer
arguments than were provided. This error might be due to some copy/pasta going
on or perhaps the argument list of the procedure/function changed to fewer
items. To fix this, consult the argument list and adjust the call accordingly.

-----

### CQL0236: autodrop annotation can only go on a procedure that uses the database 'name'

The named procedure has the `autodrop` annotation (to automatically drop a
temporary table) but the procedure in question doesn't even use the database at
all, much less the named table.  This annotation is therefore redundant.

-----

### CQL0237: strict FK validation requires that some ON UPDATE option be selected for every foreign key

`@enforce_strict` has been use to enable strict foreign key enforcement.  When
enabled every foreign key must have an action for the `ON UPDATE` rule.  You can
specify `NO ACTION` but you can't simply leave the action blank.

-----

### CQL0238: strict FK validation requires that some ON DELETE option be selected for every foreign key

`@enforce_strict` has been use to enable strict foreign key enforcement.  When
enabled every foreign key must have an action for the `ON DELETE` rule.  You can
specify `NO ACTION` but you can't simply leave the action blank.

-----

### CQL0239: 'annotation' column does not exist in result set 'column_name'

The `[[identity=(col1, col2, ...)]]` form has been used to list the identity
columns of a stored procedures result set.  These columns must exist in the
result set and they must be unique.  The indicated column name is not part of
the result of the procedure that is being annotated.

The `[[vault_sensitive=(col1, col2, ...]]` form has been used to list the
columns of a stored procedures result set. These columns must exist in the
result set. The indicated column name will be encoded if they are sensitive and
the cursor that produced the result_set is a DML.

-----

### CQL0240: identity annotation can only go on a procedure that returns a result set 'procedure_name'

The `[[identity=(col1, col2,...)]]` form has been used to list the identity
columns of a stored procedures result set.  These columns must exist in the
result set and they must be unique.  In this case, the named procedure doesn't
even return a result set.  Probably there is a copy/pasta going on.  The
identity attribute can likely be removed.

-----

### CQL0241: CONCAT may only appear in the context of SQL statement

The SQLite `||` operator has complex string conversion rules making it
impossible to faithfully emulate.  Since there is no helper function for doing
concatenations, CQL choses to support this operator only in contexts where it
will be evaluated by SQLite.  That is, inside of some SQL statement.

Examples:
```sql
var X text;

set X := 'foo' || 'bar';   -- error

set X := (select 'foo' || 'bar');  -- ok
```

If concatenation is required in some non-sql context, use the `(select ..)` expression form to let SQLite do the evaluation.

-----

### CQL0242: lossy conversion from type 'type'

There is an explicit (`set x := y`) or implicit assignment (e.g. conversion of a
parameter) where the storage for the target is a smaller numeric type than the
expression that is being stored.   This usually means a variable that should
have been declared `LONG` is instead declared `INTEGER` or that you are typing
to pass a LONG to a procedure that expects an `INTEGER`

-----

### CQL0243: blob operand must be converted to string first in '||'

We explicitly do not wish to support string concatenation for blobs that holds
non-string data. If the blob contains string data, make your intent clear by
converting it to string first using `CAST` before doing the concatenation.

-----

### CQL0244: unknown schema region 'region'

In a `@declare_schema_region` statement one of the USING regions is not a valid
region name.  Or in `@begin_schema_region` the region name is not valid.  This
probably means there is a typo in your code.

-----

### CQL0245: schema region already defined 'region'

The indicated region was previously defined, it cannot be redefined.

-----

### CQL0246: schema regions do not nest; end the current region before starting a new one

Another `@begin_schema_region` directive was encountered before the previous
`@end_schema_region` was found.

-----

### CQL0247: you must begin a schema region before you can end one

An `@end_schema_region` directive was encountered but there was no corresponding
`@begin_schema_region` directive.

-----

### CQL0248: schema region directives may not appear inside of a procedure

All of the `*_schema_region` directives must be used at the top level of your
program, where tables are typically declared.  They do not belong inside of
procedures.  If you get this error, move the directive out of the procedure near
the DDL that it affects.

-----

### CQL0249: function is not a table-valued-function 'function_name'

The indicated identifier appears in the context of a table, it is a function,
but it is not a table-valued function.  Either the declaration is wrong (use
something like `select function foo(arg text) (id int, t text)`) or
the name is wrong.  Or both.

-----

### CQL0250: table-valued function not declared 'function_name'

In a select statement, there is a reference to the indicated
table-valued-function.  For instance:

```sql
-- the above error happens if my_function has not been declared
-- as a table valued function
select * from my_function(1,2,3);
```

However , `my_function` has not been declared as a function at all.  A correct
declaration might look like this:

```sql
select function my_function(a int, b int, c int)
  (x int, y text);
```

Either there is a typo in the name or the declaration is missing, or both...

-----

### CQL0251 available for re-use

-----

### CQL0252: @PROC literal can only appear inside of procedures

An @PROC literal was used outside of any procedure.  It cannot be resolved if it isn't inside a procedure.

-----

### CQL0253 available for re-use

-----

### CQL0254: switching to previous schema validation mode not allowed if `@schema_upgrade_version` was used

When authoring a schema migration script (a stored proc named in an `@create` or
`@delete` annotation) you must create that procedure in a file that is marked
with `@schema_upgrade_verison` specifying the schema version it is upgrading.
If you do this, then the proc (correctly) only sees the schema as it existed at
that version.  However that makes the schema unsuitable for analysis using
`@previous_schema` because it could be arbitrarily far in the past.  This error
prevents you from combining those features.  Previous schema validation should
only happen against the current schema.

-----

### CQL0255 available for re-use

-----

### CQL0256 available for re-use

-----

### CQL0257: argument must be a string or numeric in 'function'

The indicated function (usually min or max) only works on strings and numerics.
`NULL` literals, blobs, or objects are not allowed in this context.

-----

### CQL0258 available for re-us

-----

### CQL0259 available for re-use

-----

### CQL0260 available for re-use

-----

### CQL0261: cursor did not originate from a SQLite statement, it only has values 'cursor_name'

The form:

```sql
  SET [name] FROM CURSOR [cursor_name]
```

Is used to wrap a cursor in an object so that it can be returned for forwarded.
This is the so-called "boxing" operation on the cursor.  The object can then be
"unboxed" later to make a cursor again.  However the point of this is to keep
reading forward on the cursor perhaps in another procedure.  You can only read
forward on a cursor that has an associated SQLite statement.  That is the cursor
was created with something like this

```sql
  DECLARE [name] CURSOR FOR SELECT ... | CALL ...
```

If the cursor isn't of this form it's just values, you can't move it forward and
so "boxing" it is of no value.  Hence not allowed. You can return the cursor
values with `OUT` instead.

----

### CQL0262: LIKE ... ARGUMENTS used on a procedure with no arguments 'procedure_name'

The `LIKE [procedure]` ARGUMENTS` form creates a shape for use in a cursor or
procedure arguments.

The indicated name is a procedure with no arguments so it cannot be used to make
a shape.

-----

### CQL0263: non-ANSI joins are forbidden if strict join mode is enabled.

You can enable strict enforcement of joins to avoid the form

```sql
select * from A, B;
```

which sometimes confuses people (the above is exactly the same as

```sql
select * from A inner join B on 1;
```
Usually there are constraints on the join also in the WHERE clause but there
don't have to be.

`@enforce_strict join` turns on this mode.

-----

### CQL0264 available for re-use

-----

### CQL0265 available for re-use

-----

### CQL0266 available for re-use

-----

### CQL0267 available for re-use

-----

### CQL0268 available for re-use

-----

### CQL0269: at least part of this unique key is redundant with previous unique keys

The new unique key must have at least one column that is not in a previous key
AND it must not have all the columns from any previous key.

e.g:
```sql
create table t1 (
  a int,
  b long,
  c text,
  d real,
  UNIQUE (a, b),
  UNIQUE (a, b, c), -- INVALID  (a, b) is already unique key
  UNIQUE (b, a), -- INVALID (b, a) is the same as (a, b)
  UNIQUE (c, d, b, a), -- INVALID subset (b, a) is already unique key
  UNIQUE (a), -- INVALID a is part of (a, b) key
  UNIQUE (a, c), -- VALID
  UNIQUE (d), -- VALID
  UNIQUE (b, d) -- VALID
);
```

-----

### CQL0270: use FETCH FROM for procedures that returns a cursor with OUT 'cursor'

If you are calling a procedure that returns a value cursor (using `OUT`) then
you accept that cursor using the pattern

```sql
CURSOR C FETCH FROM CALL foo(...);
```

The pattern

```sql
CURSOR C FOR CALL foo(...);
```

Is used for procedures that provide a full `select` statement.

Note that in the former cause you don't then use `fetch` on the cursor.  There
is at most one row anyway and it's fetched for you so a fetch would be useless.
In the second case you fetch as many rows as there are and/or you want.

-----

### CQL0271: OFFSET clause may only be used if LIMIT is also present

```sql
select * from foo offset 1;
```

Is not supported by SQLite.  `OFFSET` may only be used if `LIMIT` is also
present.  Also, both should be small because offset is not cheap.  There is no
way to do offset other than to read and ignore the indicated number of rows.  So
something like `offset 1000` is always horrible.

-----

### CQL0272: columns referenced in the foreign key statement should match exactly a unique key in parent table

If you're creating a table t2 with foreign keys on table t1, then the set of
t1's columns reference in the foreign key statement for table t2 should be:

- A primary key in `t1`

```sql
e.g:
create table t1(a text primary key);
create table t2(a text primary key, foreign key(a) references t1(a));
```

- A unique key in `t1`

```sql
e.g:
create table t1(a text unique);
create table t2(a text primary key, foreign key(a) references t1(a));
```

- A group of unique key in `t1`

```sql
e.g:
create table t1(a text, b int, unique(a, b));
create table t2(a text, b int, foreign key(a, b) references t1(a, b));
```

- A group of primary key in `t1`

```sql
e.g:
create table t1(a text, b int, primary key(a, b));
create table t2(a text, b int, foreign key(a, b) references t1(a, b));
```

- A unique index in `t1`

```sql
e.g:
create table t1(a text, b int);
create unique index unq on t1(a, b);
create table t2(a text, b int, foreign key(a, b) references t1(a, b));
```

-----

### CQL0273: autotest attribute has incorrect format (...) in 'dummy_test'

In a `cql:autotest` annotation, the given **dummy_test** info (table name,
column name, column value) has incorrect format.

-----

### CQL0274: autotest attribute 'dummy_test' has non existent table

In a `cql:autotest` annotation, the given table name for **dummy_test**
attribute does not exist.

-----

### CQL0275: autotest attribute 'dummy_test' has non existent column

In a `cql:autotest` annotation, the given column name for **dummy_test**
attribute does not exist.

-----

### CQL0276: autotest attribute 'dummy_test' has invalid value type in

In a `cql:autotest` annotation, the given column value's type for **dummy_test**
attribute does not match the column type.

-----

### CQL0277: autotest has incorrect format

In a `cql:autotest` annotation, the format is incorrect.

-----

### CQL0278: autotest attribute name is not valid

In a `cql:autotest` annotation, the given attribute name is not valid.

-----

### CQL0279: columns referenced in an UPSERT conflict target must exactly match a unique key the target table

If you're doing an UPSERT on table `T`, the columns listed in the conflict
target should be:
- A primary key in `T`
- A unique key in `T`
- A group of unique key in `T`
- A group of primary key in `T`
- A unique index in `T`

-----

### CQL0280: upsert statement requires a where clause if the insert clause uses select

When the `INSERT` statement to which the UPSERT is attached takes its values
from a `SELECT` statement, there is a potential parsing ambiguity. The SQLite
parser might not be able to tell if the `ON` keyword is introducing the UPSERT
or if it is the `ON` clause of a join. To work around this, the `SELECT`
statement should always include a `WHERE` clause, even if that `WHERE` clause is
just `WHERE 1` (always true).

>NOTE: The CQL parser doesn't have this ambiguity because it treats "ON
>CONFLICT" as a single token so this is CQL reporting that SQLite might have
>trouble with the query as written.  e.g:

```sql
insert into foo select id from bar where 1 on conflict(id) do nothing;
```

-----

### CQL0281: upsert statement does not include table name in the update statement

The UPDATE statement of and UPSERT should not include the table name because the
name is already known from the INSERT statement part of the UPSERT.  e.g:

```sql
insert into foo select id from bar where 1 on conflict(id) do update set id=10;
```

-----

### CQL0282: update statement requires a table name

The UPDATE statement should always include a table name except if the UPDATE
statement is part of an UPSERT statement. e.g:

```sql
update foo set id=10;
insert into foo(id) values(1) do update set id=10;
```

-----

### CQL0283: upsert syntax only support INSERT INTO

The INSERT statement part of an UPSERT statement can only uses `INSERT INTO ...`
e.g:

```sql
insert into foo(id) values(1) on conflict do nothing;
insert into foo(id) values(1) on conflict do update set id=10;
```

-----

### CQL0284: ad hoc schema migration directive must provide a procedure to run

`@schema_ad_hoc_migration` must provide both a version number and a migrate
procedure name. This is unlike the other version directives like `@create` where
the version number is optional.  This is because the whole point of this
migrator is to invoke a procedure of your choice.

-----

### CQL0285: ad hoc schema migration directive version number changed 'procedure_name'

In `@schema_ad_hoc_migration` you cannot change the version number of the
directive once it has been added to the schema because this could cause
inconsistencies when upgrading.

You can change the body of the method if you need to but this is also not
recommended because again there could be inconsistencies.  However careful
replacement and compensation is possible.  This is like going to 110% on the
reactor... possible, but not recommended.

-----

### CQL0286: ad hoc schema migration directive was removed; this is not allowed 'procedure_name'

An `@schema_ad_hoc_migration` cannot be removed because it could cause
inconsistencies on upgrade.

You can change the body of the method if you need to but this is also not
recommended because again there could be inconsistencies.  However careful
replacement and compensation is possible.  This is like going to 110% on the
reactor... possible, but not recommended.

-----

### CQL0287 available for re-use

-----

### CQL0288 available for re-use

-----

### CQL0289: upsert statement are forbidden if strict upsert statement mode is enabled

`@enforce_strict` has been use to enable strict upsert statement enforcement.
When enabled all sql statement should not use the upsert statement. This is
because sqlite version running in some iOS and Android version is old. Upsert
statement was added to sqlite in the version **3.24.0 (2018-06-04)**.

-----

### CQL0290 available for re-use

-----

### CQL0291: region links into the middle of a deployable region; you must point to the root of `<deployable_region>` not into the middle: `<error_region>`

Deployable regions have an "inside" that is in some sense "private".  In order
to keep the consistent (and independently deployable) you can't peek into the
middle of such a region, you have to depend on the root (i.e.
`<deployable_region>` itself).  This allows the region to remain independently
deployable and for its internal logical regions to be reorganized in whatever
manner makes sense.

To fix this error probably you should change `error_region` so that it depends
directly on `deployable_region`

-----

### CQL0292: explain statement is only available in `--dev` mode because its result set may vary between sqlite versions

The EXPLAIN statement is intended for debugging and analysis only. It helps
engineer understand how Sqlite will execute their query and the cost attached to
it. SQLite can and does change the shape of the results of the explain statement and
so it should not be used in production code. This is why this statement is only available
in `--dev` mode in CQL indicating "not for production" output.

-----

### CQL0293: only [EXPLAIN QUERY PLAN ...] statement is supported

CQL only support [EXPLAIN QUERY PLAN stmt] sql statement.

------

### CQL0294: window function invocations can only appear in the select list of a select statement

Not all SQLite builtin function can be used as a window function.

------

### CQL0295: window name is not defined

Window name referenced in the select list should be defined in the Window clause
of the same select statement.

------

### CQL0296: window name definition is not used

Window name defined in the window clause of a select statement should always be
used within that statement.

------

### CQL0297: FROM [shape] is redundant if column list is empty

In this form:

`insert into YourTable() FROM your_cursor;`

The `()` means no columns are being specified, the cursor will never be used.
The only source of columns is maybe dummy data (if it was specified) or the
default values or null.  In no case will the cursor be used.  If you really want
this use `FROM VALUES()` and don't implicate a cursor or an argument bundle.

------

### CQL0298: cannot read from a cursor without fields 'cursor_name'

The cursor in question has no storage associated with it.  It was loaded with
something like:

`fetch C into x, y, z;`

You can only use a cursor as a source of data if it was fetched with its own
storage like

`fetch C`

This results in a structure for the cursor.  This gives you `C.x`, `C.y`, `C.z` etc.

If you fetched the cursor into variables then you have to use the variables for
any inserting.

------

### CQL0299: [cursor] has too few fields, 'shape_name'

The named shape was used in a fetch statement but the number of columns fetched
is smaller than the number required by the statement we are processing.

If you need to use the cursor plus some other data then you can't use this form,
you'll have to use each field individually like 

```sql
from values(C.x, C.y, C.z, other_stuff)
```

The shape with too few fields might be the source or the target of the statement.

------

### CQL0300: argument must be an integer (between 1 and max integer) in function 'function_name'

The argument of the function should be an integer.

------

### CQL0301: second argument must be an integer (between 0 and max integer) in function 'function_name'

The second argument of the function should be an integer between 0 and
INTEGER_MAX.

------

### CQL0302: first and third arguments must be compatible in function 'function_name'

The first and third arguments of the function have to be of the same type
because the third argument provide a default value in cause the first argument
is NULL.

------

### CQL0303: second argument must be an integer between 1 and max integer in function 'function_name'

The second argument of the function must be and integer between 1 and INTEGER_MAX.

------

### CQL0304: DISTINCT may only be used with one explicit argument in an aggregate function

The keyword DISTINCT can only be used with one argument in an aggregate function.

------

### CQL0305: DISTINCT may only be used in function that are aggregated or user defined

Only aggregated functions and user defined functions can use the keyword
DISTINCT. Others type of functions are not allowed to use it.

------

### CQL0306: FILTER clause may only be used in function that are aggregated or user defined

------

### CQL0307: return statement should be in a procedure and not at the top level

There are basically two checks here both of which have to do with the "nesting
level" at which the `return` occurs.

A loose `return` statement (not in a procedure) is meaningless so that produce
an error.  There is nothing to return from.

If the return statement is not inside of an "if" or something like that then it
will run unconditionally.  Nothing should follow the return (see CQL0308) so if
we didn't fall afoul of CQL0308 and we're at the top level then the return is
the last thing in the proc, in which case it is totally redundant.

Both these situations produce an error.

------

### CQL0308: statement should be the last thing in a statement list

Control flow will exit the containing procedure after a `return` statement, so
any statements that follow in its statement list will certainly not run.  So the
return statement must be the last statement, otherwise there are
dead/unreachable statements which is most likely done by accident.

To fix this probably the things that came after the return should be deleted.
Or alternately there was a condition on the return that should have been added
but wasn't, so the return should have been inside a nested statement list (like
the body of an `if` maybe).

------

### CQL0309: new table must be added with @create([number]) or later 'table_name'

The indicated table was newly added -- it is not present in the previous schema.
However the version number it was added at is in the past.  The new table must
appear at the current schema version or later.  That version is provided in the
error message.

To fix this, change the `@create` annotation on the table to be at the indicated
version or later.

------

### CQL0310: new column must be added with @create([number]) or later" 'column_name'

The indicated column was newly added -- it is not present in the previous
schema.  However the version number it was added at is in the past.  The new
column must appear at the current schema version or later.  That version is
provided in the error message.

To fix this, change the `@create` annotation on the table to be at the indicated
version or later.

------

### CQL0311: object's deployment region changed from '<previous_region>' to '<current_region>' 'object_name'

An object may not move between deployment regions, because users of the schema
will depend on its contents.  New objects can be added to a deployment region
but nothing can move from one region to another.  The indicated object appears
to be moving.

------

### CQL0312: window function invocation are forbidden if strict window function mode is enabled

`@enforce_strict` has been use to enable strict window function enforcement.
When enabled all sql statement should not invoke window function. This is
because sqlite version running in some iOS version is old. Window function was
added to SQLite in the version **3.25.0 (2018-09-15)**.

------

### CQL0313: blob literals may only appear in the context of a SQL statement

CQL (currently)  limits use of blob literals to inside of SQL fragments.
There's no easy way to get a blob constant variable into the data section so any
implementation would be poor.  These don't come up very often in any case so
this is a punt basically.  You can fake it with (select x'1234') which makes it
clear that you are doing something expensive.  This is not recommended.  Better
to pass the blob you need into CQL rather than cons it from a literal.  Within
SQL it's just text and SQLite does the work as usual so that poses no problems.
And of course non-literal blobs (as args) work find and are bound as usual.

------

### CQL0314: select function does not require a declaration, it is a CQL built-in

CQL built-in function does not require a select function declaration. You can
used it directly in your SQL statement.

------

### CQL0315: mandatory column with no default value in INSERT INTO name DEFAULT VALUES statement.

Columns on a table must have default value or be nullable in order to use INSERT
INTO `<table>` DEFAULT VALUES statement.

------

### CQL0316: upsert-clause is not compatible with DEFAULT VALUES

`INSERT` statement with `DEFAULT VALUES` can not be used in a upsert statement.
This form is not supported by SQLite.

-----

### CQL0317 available for re-use

-----

### CQL0318 available for re-use

-----

### CQL0319 available for re-use

-----

### CQL0320 available for re-use

-----

### CQL0321: migration proc not allowed on object 'object_name'

The indicated name is an index or a trigger. These objects may not have a
migration script associated with them when they are deleted.

The reason for this is that both these types of objects are attached to a table
and the table itself might be deleted.  If the table is deleted it becomes
impossible to express even a tombstone for the deleted trigger or index without
getting errors.  As a consequence the index/trigger must be completely removed.
But if there had been a migration procedure on it then some upgrade sequences
would have run it, but others would not (anyone who upgraded after the table was
deleted would not get the migration procedure).  To avoid this problem,
migration procedures are not allowed on indices and triggers.

-----

### CQL0322 available for re-use

-----

### CQL0323: calls to undeclared procedures are forbidden; declaration missing or typo 'procedure'

If you get this error it means that there is a typo in the name of the procedure
you are trying to call, or else the declaration for the procedure is totally
missing.  Maybe a necessary `@include` needs to be added to the compiland.

Previously if you attempted to call an unknown CQL would produce a generic
function call. If you need to do this, especially a function with varargs, then
you must declare the function  with something like:

`DECLARE PROCEDURE printf NO CHECK;`

This option only works for void functions.  For more complex signatures check
`DECLARE FUNCTION` and `DECLARE SELECT FUNCTION`.  Usually these will require a
simple wrapper to call from CQL.

In all cases there must be some kind of declaration,to avoid mysterious linker
failures or argument signature mismatches.

-----

### CQL0324: referenced table was created in a later version so it cannot be used in a foreign key 'referenced_table'

In a foreign key, we enforce the following rules:

* `@recreate` tables can see any version they like, if the name is in scope
  that's good enough
* other tables may only "see" the same version or an earlier version.

Normal processing can't actually get into this state because if you tried to
create the referencing table with the smaller version number first you would get
errors because the name of the referenced table doesn't yet exist.  But if you
created them at the same time and you made a typo in the version number of the
referenced table such that it was accidentally bigger you'd create a weirdness.
So we check for that situation here and reject it to prevent that sort of typo.

If you see this error there is almost certainly a typo in the version number of
the referenced table; it should be fixed.

-----

### CQL0325: ok_table_scan attribute must be a name

The values for the attribute `ok_table_scan` can only be names.

CQL attributes can have a variety of values but in this case the attribute
refers to the names of tables so no other type of attribute is reasonable.

-----

### CQL0326: table name in ok_table_scan does not exist 'table_name'

The names provided to `ok_table_scan` attribute should be names of existing
tables.

The attribute indicates tables that are ok to scan in this procedure even though
they are typically not ok to scan due to 'no_table_scan'.  Therefore the
attribute must refer to an existing table.  There is likely a typo in the the
table name that needs to be corrected.

-----

### CQL0327: a value should not be assigned to 'attribute_name' attribute

The attribute `attribute_name` doesn't take a value.

When marking a statement with `[[<attribute_name>]]` there is no need for an
attribute value.

-----

### CQL0328: 'attribute_name' attribute may only be added to a 'statement_name'

The `attribute_name` attribute can only be assigned to specific statements.

The marking `[[<attribute_name>]]` only makes sense on specific statement. It's
likely been put somewhere strange, If it isn't obviously on the wrong thing,
look into possibly how the source is after macro expansion.

-----

### CQL0329: ok_table_scan attribute can only be used in a create procedure statement

The `ok_table_scan` can only be placed on a create procedure statement.

The marking `[[ok_table_scan=...]]` indicates that the procedure may scan the
indicated tables. This marking doesn't make sense on other kinds of statements.

-----

### CQL0330 available for re-use

-----

### CQL0331 available for re-use

-----

### CQL0332 available for re-use

-----

### CQL0333 available for re-use

-----

### CQL0334: @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row

Dummy insert feature makes only sense when it's used in a VALUES clause that is
not part of a compound select statement.

### CQL0336: select statement with VALUES clause requires a non empty list of values

VALUES clause requires at least a value for each of the values list. Empty
values list are not supported.

-----

### CQL0337: number of columns values for each row should be identical in VALUES clause

The number of values for each values list in VALUES clause should always be the
same.

-----

### CQL0338: name of a migration procedure may not end in '_crc' 'procedure_name'

To avoid name conflicts in the upgrade script, migration procedures are not
allowed to end in '_crc' this suffix is reserved for internal use.

-----

### CQL0339: WITHOUT ROWID tables are forbidden if strict without rowid mode is enabled

`@enforce_strict` has been used to enable strict `WITHOUT ROWID` enforcement.
When enabled no CREATE TABLE statement can have WITHOUT ROWID clause.

-----

### CQL0340: FROM ARGUMENTS used in a procedure with no arguments 'procedure_name'

The named procedure has a call that uses the FROM ARGUMENTS pattern but it
doesn't have any arguments. This is almost certainly a cut/paste from a
different location that needs to be adjusted.

-----

### CQL0341 available for re-use

-----

### CQL0342 available for re-use

-----

### CQL0343: all arguments must be blob 'cql_get_blob_size'

The argument for the CQL builtin function cql_get_blob_size should always be of
type blob

-----

### CQL0344: argument must be a nullable type (but not constant NULL) in 'function'

Functions like `ifnull_crash` only make sense if the argument is nullable.  If
it's already not null the operation is uninteresting/redundant.

The most likely cause is that the function call in question is vestigial and you
can simply remove it.

-----

### CQL0345 available for re-use

-----

### CQL0346: expression must be of type `object<T cursor>` where T is a valid shape name 'variable'

It's possible to take the statement associated with a statement cursor and store
it in an object variable. Using the form:

```sql
cursor C for X;
```

The object variable 'X' must be declared as follows:

```sql
declare X object<T cursor>;
```

Where `T` refers to a named object with a shape, like a table, a view, or a
stored procedure that returns a result set. This type `T` must match the shape
of the cursor exactly i.e. having the column names and types.

The reverse operation, storing a statement cursor in a variable is also possible
with this form:

```sql
set X from cursor C;
```

This has similar constraints on the variable `X`.

This error indicates that the variable in question (`X` in this example) is not
a typed object variable so it can't be the source of a cursor, or accept a
cursor.

See Chapter 5 of the CQL Programming Language.

-----

### CQL0347: select function may not return type OBJECT 'function_name'

The indicated function was declared with `DECLARE SELECT FUNCTION` meaning it is
to be used in the context of SQLite statements. However, SQLite doesn't
understand functions that return type object at all.  Therefore declaration is
illegal.

When working with pointer type through SQLite it is often possibly to encode the
object as an long integer assuming it can pass through unchanged with no
retain/release semantics or any such thing.  If that is practical you can move
objects around by returning long integers.

----

### CQL0348: collate applied to a non-text column 'column_name'

Collation order really only makes sense on text fields.  Possibly blob fields
but we're taking a stand on blob for now.  This can be relaxed later if that
proves to be a mistake.  For now, only text

----

### CQL0349: column definitions may not come after constraints 'column_name'

In a CREATE TABLE statement, the indicated column name came after a constraint.  SQLite expects all the column definitions
to come before any constraint definitions.  You must move the offending column definition above the constraints.

----

### CQL0350: statement must appear inside of a PROC SAVEPOINT block

The `ROLLBACK RETURN` and `COMMIT RETURN` forms are only usable inside of a
`PROC SAVEPOINT` block because they rollback or commit the savepoint that was
created at the top level.

----

### CQL0351: statement should be in a procedure and at the top level

The indicated statement may only appear inside procedure and not nested.  The
classic example of this is the `PROC SAVEPOINT` form which can only be used at
the top level of procedures.

----

### CQL0352: use COMMIT RETURN or ROLLBACK RETURN in within a proc savepoint block

The normal `RETURN` statement cannot be used inside of `PROC SAVEPOINT` block,
you have to indicate if you want to commit or rollback the savepoint when you
return.  This makes it impossible to forget to do so which is in some sense the
whole point of `PROC SAVEPOINT`.

----

### CQL0353: evaluation of constant failed

The constant expression could not be evaluated.  This is most likely because it
includes an operator that is not supported or a function call which is not
support.  Very few functions can be used in constant expressions The supported
functions include `iif`, which is rewritten; `abs`; `ifnull`, `nullif`, and
`coalesce`.

----

### CQL0354: duplicate enum member 'enum_name'

While processing a `enum` statement the indicated member of the enum
appeared twice.

This is almost certainly a copy/paste of the same enum member twice.

----

### CQL0355: evaluation failed 'enum_name'

While processing a `enum` statement the indicated member of the enum
could not be evaluated as a constant expression.

There could be a non-constant in the expression or there could be a
divide-by-zero error.

----

### CQL0356: enum definitions do not match 'name'

The two described `enum` statements have the same name but they are not
identical.

The error output contains the full text of both declarations to compare.

----

### CQL0357: enum does not contain 'enum_name'

The indicated member is not part of the enumeration.

----

### CQL0358: declared enums must be top level 'enum'

An `ENUM` statement for the named enum is happening inside of a
procedure.  This is not legal.

To correct this move the declaration outside of the procedure.

----

### CQL0359: conflicting type declaration 'type_name'

If a type name is used twice then the two or more declarations must be
identical.  The conflicting types will be included in the output and printed in
full.

----

### CQL0360: unknown type 'type_name'

The indicated name is not a valid type name.

----

### CQL0361: return data type in a create function declaration can only be Text, Blob or Object

Return data type in a create function definition can only be TEXT, BLOB or
OBJECT.

These are the only reference types and so CREATE makes sense only with those
types.  An integer, for instance, can't start with a +1 reference count.

----

### CQL0362: HIDDEN column attribute must be the first attribute if present

In order to ensure that SQLite will parse HIDDEN as part of the type it has to
come before any other attributes like NOT NULL.

This limitation is due to the fact that CQL and SQLite use slightly different
parsing approaches for attributes and in SQLite HIDDEN isn't actually an
attribute.  The safest place to put the attribute is right after the type name
and before any other attributes as it is totally unambiguous there so CQL
enforces this.

----

### CQL0363 available for re-use

----

### CQL0364 available for re-use

----

### CQL0365: @enforce_pop used but there is nothing to pop

Each `@enforce_pop` should match an `@enforce_push`, but there is nothing to pop
on the stack now.

----

### CQL0366: transaction operations disallowed while STRICT TRANSACTION enforcement is on

`@enforce_strict transaction` has been used, while active no transaction
operations are allowed.  Savepoints may be used.  This is typically done to
prevent transactions from being used in any ad hoc way because they don't nest
and typically need to be used with some "master plan" in mind.

----

### CQL0367: an attribute was specified twice 'attribute_name'

In the indicated type declaration, the indicated attribute was specified twice.
This is almost certainly happening because the line in question looks like this
`type x_name not null;` but `type_name` is already `not null`.

----

### CQL0368: strict select if nothing requires that all (select ...) expressions include 'if nothing'

`@enforce_strict select if nothing` has been enabled.  This means that select
expressions must include `if nothing then throw` (the old default) `if nothing
then [value]` or `if nothing or null then [value]`. This options exists because
commonly the case where a row does not exist is not handled correctly when
`(select ...)` is used without the `if nothing` options.

If your select expression uses a [built-in aggregate
function](https://www.sqlite.org/lang_aggfunc.html), this check may not be
enforced because they can always return a row. But there are exceptions. The
check is still enforced when one of the following is in the expression:
- a `GROUP BY` clause
- a `LIMIT` that evaluates to less than 1, or is a variable
- an `OFFSET` clause
- You have a `min` or `max` function with more than 1 argument. Those are
  [scalar functions](https://sqlite.org/lang_corefunc.html#max_scalar).

----

### CQL0369: (SELECT ... IF NOTHING) construct is for use in top level expressions, not inside of other DML

This form allows for error control of (select...) expressions.  But SQLite does
not understand the form at all, so it can only appear at the top level of
expressions where CQL can strip it out. Here are some examples:

good:

```sql
  set x := (select foo from bar where baz if nothing then 0);
  if (select foo from bar where baz if nothing then 1) then ... end if;
```

bad:

```sql
  select foo from bar where (select something from somewhere if nothing then null);
  delete from foo where (select something from somewhere if nothing then 1);
```

Basically if you are already in a SQL context, the form isn't usable because
SQLite simply doesn't understand if nothing at all. This error makes it so that
you'll get a build time failure from CQL rather than a run time failure from
SQLite.

----

### CQL0370: due to a memory leak bug in old SQLite versions, the select part of an insert must not have a top level join or compound operator. Use WITH and a CTE, or a nested select to work around this.

There is an unfortunate memory leak in older versions of SQLite (research pending on particular versions,
but 3.28.0 has it).  It causes this pattern to leak:

```sql
-- must be autoinc table
create table x (
  pk integer primary key autoincrement
);

-- any join will do (this is a minimal repro)
insert into x
  select NULL pk from
  (select 1) t1 inner join (select 1) t2;
```

You can workaround this with a couple of fairly simple rewrites.  This form is probably the cleanest.

```sql
with
cte (pk) as (select .. anything you need)
insert into x
  select * from cte;
```

Simply wrapping your desired select in a nested select also suffices.  So long as the top level is simple.

```sql
insert into x
  select * from (
    select anything you need....
  );
```

----

### CQL0371: table valued function used in a left/right/cross context; this would hit a SQLite bug.  Wrap it in a CTE instead.

This error is generated by `@enforce_strict table function`. It is there to
allow safe use of Table Valued Functions (TVFs) even though there was a bug in
SQLite prior to v 3.31.0 when joining against them.  The bug appears when the
TVF is on the right of a left join. For example:

```sql
select * from foo left join some_tvf(1);
```

In this case the join becomes an INNER join even though you wrote a left join.  Likewise

```sql
select * from some_tvf(1) right join foo;
```

Becomes an inner join even though you wrote a right join.  The same occurs when a TVF is on either side of a cross join.

The workaround is very simple.  You don't want the TVF to be the target of the join directly.  Instead:

```sql
with tvf_(*) as (select * from some_tvf(1))
select * from foo left join tvf_;
```

OR

```sql
select * from foo left join (select * from some_tvf(1));
```

----

### CQL0372: SELECT ... IF NOTHING OR NULL THEN NULL is redundant; use SELECT ... IF NOTHING THEN NULL instead.

It is always the case that
`SELECT ... IF NOTHING OR NULL THEN NULL` is equivalent to
`SELECT ... IF NOTHING THEN NULL`. As such, do not do this:

```sql
select foo from bar where baz if nothing or null then null
```

Do this instead:

```sql
select foo from bar where baz if nothing then null
```

----

### CQL0373: comparing against NULL always yields NULL; use IS and IS NOT instead.

Attempting to check if some value `x` is NULL via `x = NULL` or `x == NULL`, or
isn't NULL via `x <> NULL` or `x != NULL`, will always produce NULL regardless
of the value of `x`. Instead, use `x IS NULL` or `x IS NOT NULL` to get the
expected boolean result.

----

### CQL0374: SELECT expression is equivalent to NULL.

CQL found a redundant select operation (e.g., `set x := (select NULL);`).

There is no need to write a select expression that always evaluates to NULL. Simply use NULL instead (e.g., `set x := NULL;`).

----

### CQL0375 available for re-use

----

### CQL0376 available for re-use

----

### CQL0377: table transitioning from `@recreate` to `@create` must use `@create(nn,cql:from_recreate)` 'table name'

The indicated table is moving from `@recreate` to `@create` meaning it will now
be schema managed in an upgradable fashion.  When this happens end-user
databases might have some stale version of the table from a previous
installation.  This stale version must get a one-time cleanup in order to ensure
that the now current schema is correctly applied.  The `cql:from_recreate`
annotation does this.  It is required because otherwise there would be no record
that this table "used to be recreate" and therefore might have an old version
still in the database.

A correct table might look something like this:

```sql
create table correct_migration_to_create(
 id integer primary key,
 t text
) @create(7, cql:from_recreate);
```

----

### CQL0378: built-in migration procedure not valid in this context 'name'

The indicated name is a valid built-in migration procedure but it is not valid
on this kind of item.  For instance `cql:from_recreate` can only be applied to
tables.

----

### CQL0379: unknown built-in migration procedure 'name'

Certain schema migration steps are built-in.  Currently the only one is
`cql:from_recreate` for moving to `@create` from `@recreate`.  Others may be
added in the future.  The `cql:` prefix ensures that this name cannot conflict
with a valid user migration procedure.

----

### CQL0380: WHEN expression cannot be evaluated to a constant

In a `SWITCH` statement each expression each expression in a `WHEN` clause must
be made up of constants and simple numeric math operations.  See the reference
on the `const(..)` expression for the valid set.

It's most likely that a variable or function call appears in the errant
expression.

----

### CQL0381: case expression must be a not-null integral type

The `SWITCH` statement can only switch over integers or long integers.  It will
be translated directly to the C switch statement form.  `TEXT`, `REAL`, `BLOB`,
`BOOL`, and `OBJECT` cannot be used in this way.

----

### CQL0382: type of a WHEN expression is bigger than the type of the SWITCH expression

The `WHEN` expression evaluates to a `LONG INTEGER` but the expression in the
`SWITCH` is `INTEGER`.

----

### CQL0383: switch ... ALL VALUES is useless with an ELSE clause

The `ALL VALUES` form of switch means that:
 * the `SWITCH` expression is an enumerated type
 * the `WHEN` cases will completely cover the values of the enum

If you allow the `ELSE` form then `ALL VALUES` becomes meaningless because of
course they are all covered.  So with `ALL VALUES` there can be no `ELSE`.

You can list items that have no action with this form:

```sql
   WHEN 10, 15 THEN NOTHING -- explicitly do nothing in these cases so they are still covered
```

No code is generated for such cases.

----

### CQL0384: switch statement did not have any actual statements in it

Either there were no `WHEN` clauses at all, or they were all `WHEN ... THEN
NOTHING` so there is no actual code to execute.  You need to add some cases that
do work.

----

### CQL0385: WHEN clauses contain duplicate values 'value'

In a `SWITCH` statement all of the values in the `WHEN` clauses must be unique.
The indicated errant entry is a duplicate.

----

### CQL0386: SWITCH ... ALL VALUES is used but the switch expression is not an enum type

In a `SWITCH` statement with `ALL VALUES` specified the switch expression was
not an enumerated type. `ALL VALUES` is used to ensure that there is a case for
every value of an enumerated type so this switch cannot be so checked.  Either
correct the expression, or remove `ALL VALUES`.

----

### CQL0387: a value exists in the enum that is not present in the switch 'enum_member'

In a `SWITCH` statement with `ALL VALUES` specified the errant enum member did
not appear in any `WHEN` clause.  All members must be specified when `ALL
VALUES` is used.

----

### CQL0388: a value exists in the switch that is not present in the enum 'numeric_value'

In a `SWITCH` statement with `ALL VALUES` specified the errant integer value
appeared in in a `WHEN` clause.  This value is not part of the members of the
enum.  Note that enum members that begin with '_' are ignored as they are, by
convention, considered to be pseudo-members. e.g. in `declare enum v integer (v0
= 0, v1 =1, v2 =2, _count = 3)` `_count` is a pseudo-member.

The errant entry should probably be removed. Alternatively, `ALL VALUES` isn't
appropriate as the domain of the switch is actually bigger than the domain of
the enumeration.  One of these changes must happen.

----

### CQL0389: DECLARE OUT requires that the procedure be already declared

The purpose of the `DECLARE OUT` form is to automatically declare the out
parameters for that procedure.

This cannot be done if the type of the procedure is not yet known.

----

### CQL0390: DECLARE OUT CALL used on a procedure with no missing OUT arguments

The `DECLARE OUT CALL` form was used, but the procedure has no `OUT` arguments
that need any implicit declaration.  Either they have already all been declared
or else there are no `OUT` arguments at all, or even no arguments of any kind.

----

### CQL0391: CLOSE cannot be used on a boxed cursor

When a cursor is boxed—i.e., wrapped in an object—the lifetime of the box and
underlying statement are automatically managed via reference counting.
Accordingly, it does not make sense to manually call CLOSE on such a cursor as
it may be retained elsewhere. Instead, to allow the box to be freed and the
underlying statement to be finalized, set all references to the cursor to NULL.

Note: As with all other objects, boxed cursors are automatically released when
they fall out of scope. You only have to set a reference to NULL if you want to
release the cursor sooner, for some reason.

----

### CQL0392: when deleting a virtual table you must specify @delete(nn, cql:module_must_not_be_deleted_see_docs_for_CQL0392) as a reminder not to delete the module for this virtual table

When the schema upgrader runs, if the virtual table is deleted it will attempt
to do `DROP TABLE IF EXISTS` on the indicated table.  This table is a virtual
table.  SQLite will attempt to initialize the table even when you simply try to
drop it.  For that to work the module must still be present.  This means modules
can never be deleted!  This attribute is here to remind you of this fact so that
you are not tempted to delete the module for the virtual table when you delete
the table.  You may, however, replace it with a shared do-nothing stub.

The attribute itself does nothing other than hopefully cause you to read this
documentation.

----

### CQL0393: not deterministic user function cannot appear in a constraint expression 'function_name'

`CHECK` expressions and partial indexes (`CREATE INDEX` with a `WHERE` clause)
require that the expressions be deterministic.  User defined functions may or
may not be deterministic.

Use [[deterministic) on a UDF declaration (select function...]] to mark
it deterministic and allow its use in an index.

----

### CQL0394: nested select expressions may not appear inside of a constraint expression

SQLite does not allow the use of correlated subqueries or other embedded select
statements inside of a CHECK expression or the WHERE clauses of a partial index.
This would require additional joins on every such operation which would be far
too expensive.

----

### CQL0395: table valued functions may not be used in an expression context 'function_name'

A table valued function should be used like a table e.g.

```sql
-- this is right
select * from table_valued_func(5);
```

Not like a value e.g.

```sql
-- this is wrong
select table_valued_func(5);

-- this is also wrong
select 1 where table_valued_func(5) = 3;
```

----

### CQL0396: versioning attributes may not be used on DDL inside a procedure

If you are putting DDL inside of a procedure then that is going to run
regardless of any `@create`, `@delete`, or `@recreate` attributes;

DDL in entires do not get versioning attributes, attributes are reserved for
schema declarations outside of any procedure.

----

### CQL0397: object is an orphan because its table is deleted. Remove rather than @delete 'object_name'

This error is about either a trigger or an index. In both cases you are trying
to use `@delete` on the index/trigger but the table that the named  object is
based on is itself deleted, so the object is an orphan. Because of this, the
orphaned object doesn't need, or no longer needs, an `@delete` tombstone because
when the table is dropped, all of its orphaned indices and triggers will also be
dropped.

To fix this error, remove the named object entirely rather than marking it
`@delete`.

Note: if the index/trigger was previously deleted and now the table is also
deleted, it is now safe to remove the index/trigger `@delete` tombstone and this
error reminds you to do so.

----

### CQL0398: a compound select cannot be ordered by the result of an expression

When specifying an `ORDER BY` for a compound select, you may only order by
indices (e.g., `3`) or names (e.g., `foo`) that correspond to an output column,
not by the result of an arbitrary expression (e.g., `foo + bar`).

For example, this is allowed:

```sql
SELECT x, y FROM t0 UNION ALL select x, y FROM t1 ORDER BY y
```

The equivalent using an index is also allowed:

```sql
SELECT x, y FROM t0 UNION ALL select x, y FROM t1 ORDER BY 2
```

This seemingly equivalent version containing an arbitrary expression, however,
is not:

```sql
SELECT x, y FROM t0 UNION ALL select x, y FROM t1 ORDER BY 1 + 1;
```

----

### CQL0399: table must leave @recreate management with @create(nn) or later 'table_name'

The indicated table changed from `@recreate` to `@create` but it did so in a
past schema version.  The change must happen in the current schema version.
That version is indicated by the value of nn.

To fix this you can change the `@create` annotation so that it matches the
number in this error message

----

### CQL0400 available for re-use

----

### CQL0401 available for re-use

----

### CQL0402 available for re-use

----

### CQL0403: operator may not be used because it is not supported on old versions of SQLite, 'operator'

The indicated operator has been suppressed with `@enforce_strict is true`
because it is not available on older versions of sqlite.

----

### CQL0404: procedure cannot be both a normal procedure and an unchecked procedure, 'procedure_name'

The construct:

```sql
DECLARE PROCEDURE printf NO CHECK;
```

Is used to tell CQL about an external procedure that might take any combination
of arguments.  The canonical example is `printf`. All the arguments are
converted from CQL types to basic C types when making the call (e.g. TEXT
variables become temporary C strings).  Once a procedure has been declared in
this way it can't then also be declared as a normal CQL procedure via `CREATE`
or `DECLARE PROCEDURE`.  Likewise a normal procedure can't be redeclared with
the `NO CHECK` pattern.

----

### CQL0405: procedure of an unknown type used in an expression 'procedure_name'

If a procedure has no known type—that is, it was originally declared with `NO
CHECK`, and has not been subsequently re-declared with `DECLARE FUNCTION` or
`DECLARE SELECT FUNCTION`—it is not possible to use it in an expression. You
must either declare the type before using it or call the procedure outside of an
expression via a `CALL` statement:

```sql
DECLARE PROCEDURE some_external_proc NO CHECK;

-- This works even though `some_external_proc` has no known type
-- because we're using a CALL statement.
CALL some_external_proc("Hello!");

DECLARE FUNCTION some_external_proc(t TEXT!) INT!;

-- Now that we've declared the type, we can use it in an expression.
let result := some_external_proc("Hello!");
```

----

### CQL0406: substr uses 1 based indices, the 2nd argument of substr may not be zero"

A common mistake with substr is to assume it uses zero based indices like C
does.  It does not.  In fact the result when using 0 as the second argument is
not well defined.  If you want the first `n` characters of a string you use
`substr(haystack, 1, n)`.

----

CQL 0407 available for re-use

----

### CQL0408 available for re-use

----

### CQL0409: cannot use IS NULL or IS NOT NULL on a value of a NOT NULL type 'nonnull_expr'

If the left side of an `IS NULL` or `IS NOT NULL` expression is of a `NOT NULL`
type, the answer will always be the same (`FALSE` or `TRUE`, respectively). Such
a check often indicates confusion that may lead to unexpected behavior (e.g.,
checking, incorrectly, if a cursor has a row via `cursor IS NOT NULL`).

>NOTE: Cursor fields of cursors without a row and uninitialized variables of a
>NOT NULL reference type are exceptions to the above rule: Something may be NULL
>even if it is of a NOT NULL type in those cases. CQL will eventually eliminate
>these exceptions. In the cursor case, one can check whether or not a cursor has
>a row by using the cursor-as-boolean-expression syntax (e.g., `IF cursor THEN
>... END IF;`, `IF NOT cursor ROLLBACK RETURN;`, et cetera). In the
>uninitialized variables case, writing code that checks for initialization is
>not recommended (and, indeed, use before initialization will soon be impossible
>anyway): One should simply always initialize the variable.

----

### CQL0410 available for re-use

----

### CQL0411: duplicate flag in substitution 'flag'

The same flag cannot be used more than once per substitution within a format
string.

----

### CQL0412: cannot combine '+' flag with space flag

It is not sensible to use both the `+` flag and the space flag within the same
substitution (e.g., `%+ d`) as it is equivalent to just using the `+` flag
(e.g., `%+d`).


----

### CQL0413: width required when using flag in substitution 'flag'

The flag used (`-` or `0`) for a substitution within a format string does not
make sense unless accompanied by a width (e.g., `%-10d`).

----

### CQL0414: 'l' length specifier has no effect; consider 'll' instead

The use of the `l` length specifier within a format string, e.g. `%ld`, has no
effect in SQLite. If the argument is to be a `LONG`, use `ll` instead (e.g.,
`%lld`). If the argument is to be an `INTEGER`, simply omit the length specifier
entirely (e.g., `%d`).

----

### CQL0415: length specifier cannot be combined with '!' flag

Length specifiers are only for use with integer type specifiers (e.g. `%lld`)
and the `!` flag is only for use with non-integer type specifiers (e.g. `%!10s`
and `%!f`). It therefore makes no sense to use both within the same
substitution.

----

### CQL0416: type specifier not allowed in CQL 'type_specifier'

The type specifier used is accepted by SQLite, but it would be either useless or
unsafe if used within the context of CQL.

----

### CQL0417: unrecognized type specifier 'type_specifier'

The type specifier used within the format string is not known to SQLite.

----

### CQL0418: type specifier combined with inappropriate flags 'type_specifier'

The type specifier provided does not make sense given one or more flags that
appear within the same substitution. For example, it makes no sense to have a
substitution like `%+u`: the `+` indicates the sign of the number will be shown,
while the `u` indicates the number will be shown as an unsigned integer.

----

### CQL0419: type specifier cannot be combined with length specifier 'type_specifier'

The type specifier provided cannot be used with a length specifier. For example,
`%lls` makes no sense because `ll` only makes sense with integer types and `s`
is a type specifier for strings.

----

### CQL0420: incomplete substitution in format string

The format string ends with a substitution that is incomplete. This can be the
case if a format string ends with a `%` (e.g., `"%d %s %"`). If the intent is to
have a literal `%` printed, use `%%` instead (e.g., "%d %s %%"`).

----

### CQL0421: first argument must be a string literal 'function'

The first argument to the function must be a string literal.

----

### CQL0422: more arguments provided than expected by format string 'function'

More arguments were provided to the function than its format string indicates
are necessary. The most likely cause for this problem is that the format string
is missing a substitution.

----

### CQL0423: fewer arguments provided than expected by format string 'function'

Fewer arguments were provided to the function than its format string indicates
are necessary. The most likely cause for this problem is that an argument was
accidentally omitted.

-----

### CQL0424: procedure with INOUT parameter used as function 'procedure_name'

If a procedure has an `INOUT` parameter, it cannot be used as a function: It may
only be called via a `CALL` statement.

-----

### CQL0425: procedure with non-trailing OUT parameter used as function 'procedure_name'

For a procedure to be used as a function, it must have exactly one `OUT`
parameter, and that parameter must be the last parameter of the procedure. In
all other cases, procedures with one or more `OUT` parameters may only be called
via a `CALL` statement.

----

### CQL0426: OUT or INOUT argument cannot be used again in same call 'variable'

When a variable is passed as an `OUT` or `INOUT` argument, it may not be used as
another argument within the same procedure call. It can, however, be used within
a _subexpression_ of another argument. For example:

```sql
CREATE PROC some_proc(IN a TEXT, OUT b TEXT)
BEGIN
  ...
END

VAR t TEXT;

-- This is NOT legal.
CALL some_proc(t, t);

-- This, however, is perfectly fine.
CALL some_proc(some_other_proc(t), t);
```

----

### CQL0427: LIKE CTE form may only be used inside a shared fragment at the top level i.e. [[shared_fragment]] 'procedure_name'

When creating a shared fragment you can specify "table parameters" by defining
their shape like so:

```
[[shared_fragment]]
create proc shared_proc(lim_ integer)
begin
   with source(*) LIKE any_shape
   select * from source limit lim_;
end;
```

However this LIKE form only makes sense withing a shared fragment, and only as a
top level CTE in such a fragment.  So either:

* the LIKE appeared outside of any procedure
* the LIKE appeared in a procedure, but that procedure is not a shared fragment
* the LIKE appeared in a nested WITH clause

----

### CQL0428: duplicate binding of table in CALL/USING clause 'table_name'

In a CALL clause to access a shared fragment there is a duplicate table name in
the USING portion.

Example:

```
my_cte(*) AS (call my_fragment(1) USING something as param1, something_else as param1),
```

Here `param1` is supposed to take on the value of both `something` and
`something_else`.  Each parameter may appear only once in the `USING` clause.

### CQL0429: called procedure has no table arguments but a USING clause is present 'procedure_name'

In a CALL clause to access a shared fragment there are table bindings but the
shared fragment that is being called does not have any table bindings. e.g.:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 select * from a_location limit lim;
end;

-- here we try to use my_fragment with table parameter but it has none
with
  my_cte(*) AS (call my_fragment(1) USING something as param)
  select * from my_cte;
```

----

### CQL0430: no actual table was provided for the table parameter 'table_name'

In a CALL clause to access a shared fragment the table bindings are missing a table parameter.

Example:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 with source LIKE source_shape
 select * from source limit lim;
end;

-- here we try to use my_fragment but no table was specified to play the role of "source"
with
  my_cte(*) AS (call my_fragment(1))
  select * from my_cte;
```

----

### CQL0431: an actual table was provided for a table parameter that does not exist 'table_name'

In a CALL clause to access a shared fragment the table bindings refer to a table
parameter that does not exist.

Example:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 with source LIKE source_shape
 select * from source limit lim;
end;

-- here we try to use my_fragment but there is a table name "soruce" that doesn't match source
with
  my_cte(*) AS (call my_fragment(1) USING something as soruce)
  select * from my_cte;
```

----

### CQL0432: table provided must have the same number of columns as the table parameter 'table_name'

In a CALL clause to access a shared fragment the table bindings are trying to
use a table that has the wrong number of columns.  The column count, names, and
types must be compatible. Extra columns for instance are not allowed because
they might create ambiguities that were not present in the shared fragment. e.g.:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 with source LIKE (select 1 x, 2 y)
 select * from source limit lim;
end;

-- here we try to use my_fragment but we provided 3 columns not 2
with
  my_source(*) AS (select 1 x, 2 y, 3 z),
  my_cte(*) AS (call my_fragment(1) USING my_source as source)
  select * from my_cte;
```

Here `my_fragment` wants a `source` table with 2 columns (x, y).  But 3 were
provided.

----

### CQL0433: table argument 'formal_name' requires column 'column_name' but it is missing in provided table 'actual_name'

In a CALL clause to access a shared fragment the table bindings are trying to
use a table that is missing a required column. e.g.:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 with source LIKE (select 1 x, 2 y)
 select * from source limit lim;
end;

-- here we try to use my_fragment but we passed in a table with (w,x) not (x,y)
with
  my_source(*) AS (select 1 w, 2 x),
  my_cte(*) AS (call my_fragment(1) USING my_source as source)
  select * from my_cte;
```

----

### CQL0434: shared fragments may not be called outside of a SQL statement 'procedure_name'

The indicated name is the name of a shared fragment, these fragments may be used inside
of SQL code (e.g. select statements) but they have no meaning in a normal call outside
of a SQL statement. e.g.:

```sql
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
 select * from somewhere limit lim;
end;

call my_fragment();
```

Here `my_fragment` is being used like a normal procedure. This is not valid.  A correct
use of a fragment might look something like this:

```sql
with
  (call my_fragment())
  select * from my_fragment;
```

----

### CQL0435: must use qualified form to avoid ambiguity with alias 'column'

In a SQLite `SELECT` expression, `WHERE`, `GROUP BY`, `HAVING`, and `WINDOW`
clauses see the columns of the `FROM` clause before they see any aliases in the
expression list. For example, assuming some table `t` has columns `x` and `y`,
the following two expressions are equivalent:

```sql
SELECT x AS y FROM t WHERE y > 100
SELECT x AS y FROM t WHERE t.y > 100
```

In the first expression, the use of `y > 100` makes it seem as though the `y`
referred to could be the `y` resulting from `x as y` in the expression list, but
that is not the case. To avoid such confusion, CQL requires the use of the
qualified form `t.y > 100` instead.

----

### CQL0436: alias referenced from WHERE, GROUP BY, HAVING, or WINDOW clause

Unlike many databases (e.g., PostgreSQL and SQL Server), SQLite allows the
aliases of a `SELECT` expression list to be referenced from clauses that are
evaluated _before_ the expression list. It does this by replacing all such alias
references with the expressions to which they are equivalent. For example,
assuming `t` does _not_ have a column `x`, the following two expressions are
equivalent:

```
SELECT a + b AS x FROM t WHERE x > 100
SELECT a + b AS x FROM t WHERE a + b > 100
```

This can be convenient, but it is also error-prone. As mentioned above, the
above equivalency only holds if `x` is _not_ a column in `t`: If `x` _is_ a
column in `t`, the `WHERE` clause would be equivalent to `t.x > 100` instead,
and there would be no syntactically obvious way to know this without first
manually determining all of the columns present in `t`.

To avoid such confusion, CQL disallows referencing expression list aliases from
`WHERE`, `GROUP BY`, `HAVING`, and `WINDOW` clauses altogether. Instead, one
should simply use the expression to which the alias is equivalent (as is done in
the second example above).

----

### CQL0437: common table name shadows previously declared table or view 'name'

The name of a common table expression may not shadow a previously declared table
or view. To rectify the problem, simply use a different name.

----

### CQL0438: variable possibly used before initialization 'name'

The variable indicated must be initialized before it is used because it is of
a reference type (`BLOB`, `OBJECT`, or `TEXT`) that is also `NOT NULL`.

CQL is usually smart enough to issue this error only in cases where
initialization is truly lacking. Be sure to verify that the variable will be
initialized before it is used for all possible code paths.

----

### CQL0439: nonnull reference OUT parameter possibly not always initialized 'name'

The parameter indicated must be initialized before the procedure returns because
it is of a reference type (`BLOB`, `OBJECT`, or `TEXT`) that is also `NOT NULL`.

CQL is usually smart enough to issue this error only in cases where
initialization is truly lacking. Be sure to verify that the parameter will be
initialized both before the end of the procedure and before all cases of
`RETURN` and `ROLLBACK RETURN`. (Initialization before `THROW` is not required.)

----

### CQL0440: fragments may not have an empty body 'procedure_name'

The indicated procedure is one of the fragment types but has an empty body. This
is not valid for any fragment type.

Example:

```
[[shared_fragment]]
create proc my_fragment(lim int!)
begin
  /* something has to go here */
end;
```

----

### CQL0441: shared fragments may only have IF, SELECT, or  WITH...SELECT at the top level 'procedure_name'

A shared fragment may consist of just one SELECT statement (including
WITH...SELECT) or it can be an IF/ELSE statement that has a series of compatible
select statements. There are no other valid options.

-----

### CQL0443: shared fragments with conditionals must have exactly one SELECT or WITH...SELECT in each statement list 'procedure_name'

In a shared fragment with conditionals the top level statement is an "IF".  All
of the statement lists in the IF must have exactly one valid select statement.
This error indicates that a statement list has the wrong number or type of
statement.

-----

### CQL0444: this use of the named shared fragment is not legal because of name conflict 'procedure_name'

This error will be followed by additional diagnostic information about the call
chain that is problematic.  For instance:

```
Procedure innermost has a different CTE that is also named foo
The above originated from CALL inner USING foo AS source
The above originated from CALL middle USING foo AS source
The above originated from CALL outer USING foo AS source
```

This indicates that you are trying to call `outer` which in turn calls `middle`
which in turn called `inner`.  The conflict happened when the `foo` parameter
was passed in to `inner` because it already has a CTE named `foo` that means
something else.

The way to fix this problem is to rename the CTE in probably the outermost call
as that is likely the one you control. Renaming it in the innermost procedure
might also be wise if that procedure is using a common name likely to conflict.

It is wise to name the CTEs in shared fragments such that they are unlikely to
eclipse outer CTEs that will be needed as table parameters.

-----

### CQL0445: [[try_is_proc_body]] accepts no values

The attribute `cql:try_is_proc_body` cannot be used with any values (e.g.,
`cql:try_is_proc_body=(...)`).

-----

### CQL0446: [[try_is_proc_body]] cannot be used more than once per procedure

The purpose of `cql:try_is_proc_body` is to indicate that a particular `TRY`
block contains what should be considered to be the true body of the procedure.
As it makes no sense for a procedure to have multiple bodies,
`cql:try_is_proc_body` must appear only once within any given procedure.

-----

### CQL0447: virtual table 'table' claims to be eponymous but its module name 'module' differs from its table name

By definition, an eponymous virtual table has the same name as its module.  If
you use the @eponymous notation on a virtual table, you must also make the
module and table name match.

-----

### CQL0448: table was marked @delete but it needs to be marked @recreate @delete 'table'

The indicated table was on the recreate plan and was then deleted by adding an `@delete(version)` attribute.

However, the previous `@recreate` annotation was removed.  This would make the
table look like it was a baseline table that had been deleted, and it isn't.  To
correctly drop a table on the `@recreate` you leave the recreate directive as it
was and simply add `@delete`.  No version information is required because the
table is on the recreate plan anyway.

Example:

```
create table dropping_this
(
  f1 integer,
  f2 text
) @recreate(optional_group) @delete;
```

This error indicates that the `@recreate(optional_group)` annotation was
removed.  You should put it back.

-----

### CQL0449: unsubscribe does not make sense on non-physical tables 'table_name'

The indicated table was marked for blob storage or is a backed table.  In both
cases there is no physical schema associated with it so unsubscribe does not
make any sense there. If it's a backed table perhaps the intent was to remove
the backing table?

### CQL0450: a shared fragment used like a function must be a simple SELECT with no FROM clause

When using a shared fragment like an expression, the shared fragment must
consist of a simple SELECT without a FROM clause. That SELECT, however, may
contain a nested SELECT expression which, itself, may have a FROM clause.

Additional constraints:

* the target of the call is a shared fragment
  * the target therefore a single select statement
  * the target therefore has no out-arguments
* the target has no select clauses other than the select list, e.g. no FROM,
  WHERE, LIMIT etc.
* the target returns exactly one column, i.e. it's just one SQL expression

-----

### CQL0451: procedure as function call is not compatible with DISTINCT or filter clauses

Certain built-in functions like `COUNT` can be used with `DISTINCT` or `FILTER` options like so:

```sql
select count(distinct ...);

select sum(...) filter(where ...) over (...)
```

These options are not valid when calling a procedure as a function and so they
generate errors if used.

-----

### CQL0452: function may not be used in SQL because it is not supported on old versions of SQLite 'function'

Due to an enabled enforcement (e.g., `@enforce_strict sign function;`), the
indicated function may not be used within SQL because it is not supported on old
versions of SQLite.

-----

### CQL0453: blob type is not a valid table 'table_name'

The CQL forms `SET [blob] FROM CURSOR [cursor]` and `FETCH [cursor] FROM [blob]`
require that the blob variable be declared with a type kind and the type of the
blob matches a suitable table.

In this case the blob was declared like so:

```
DECLARE blob_var blob<table_name>
```

But the named table `table_name` is not a table.

-----

### CQL0454 available for re-use

-----

### CQL0455: blob variable must have a type kind for type safety, 'blob_name'

The CQL forms `SET [blob] FROM CURSOR [cursor]` and `FETCH [cursor] FROM [blob]`
require that the blob variable be declared with a type kind and the type of the
blob matches a suitable table.

In this case the blob was declared like so:

```
DECLARE blob_name blob;
```

But it must be:

```
DECLARE blob_name blob<table_name>;
```

Where `table_name` is a suitable table.

-----

### CQL0456: blob type is a view, not a table 'view_name'

The CQL forms `SET [blob] FROM CURSOR [cursor]` and `FETCH [cursor] FROM [blob]`
require that the blob variable be declared with a type kind and the type of the
blob matches a suitable table.

In this case the blob was declared like:

```
DECLARE blob_var blob<view_name>
```

Where the named type `view_name` is a view, not a table.

-----

### CQL0457: the indicated table is not marked with [[blob_storage]] 'table_name'

The CQL forms `SET [blob] FROM CURSOR [cursor]` and `FETCH [cursor] FROM [blob]`
require that the blob variable be declared with a type kind and the type of the
blob matches a suitable table.

In this case the blob was declared like:

```
DECLARE blob_var blob<table_name>
```

but the indicated table is missing the necessary attribute `[[blob_storage]]`.

This attribute is necessary so that CQL can enforce additional rules on the
table to ensure that it is viable for blob storage.  For instance, the table can
have no primary key, no foreign keys, and may not be used in normal SQL
statements.

-----

### CQL0458: the indicated table may only be used for blob storage 'table_name'

The indicated table has been marked with `[[blob_storage]]`.  This means that it
isn't a real table -- it will have no SQL schema.  Since it's only a storage
shape, it cannot be used in normal operations that use tables such as `DROP
TABLE`, `CREATE INDEX`, or inside of `SELECT` statements.

The `CREATE TABLE` construct is used to declare a blob storage type because it's
the natural way to define a structure in SQL and also because the usual
versioning rules are helpful for such tables.  But otherwise, blob storage isn't
really a table at all.

-----

### CQL0459: table is not suitable for use as blob storage: [reason] 'table_name'

The indicated table was marked with `[[blob_storage]]`.  This indicates that the
table is going to be used to define the shape of blobs that could be stored in
the database. It isn't going to be a "real" table.

There are a number of reasons why a table might not be a valid as blob storage.

For instance:

* it has a primary key
* it has foreign keys
* it has constraints
* it is a virtual table

This error indicates that one of these items is present. The specific cause is
included in the text of the message.

-----

### CQL0460: field of a nonnull reference type accessed before verifying that the cursor has a row 'cursor.field'

If a cursor has a field of a nonnull reference type (e.g., `TEXT!`), it
is necessary to verify that the cursor has a row before accessing the field
(unless the cursor has been fetched in such a way that it *must* have a row,
e.g., via `FETCH ... FROM VALUES` or `LOOP FETCH`). The reason for this is that,
should the cursor _not_ have a row, the field will be `NULL` despite the nonnull
type.

Assume we have the following:

```sql
create table t (x text!);
declare proc requires_text_notnull(x text!);
```

The following code is **illegal**:

```sql
cursor c for select * from t;
fetch c;
-- ILLEGAL because `c` may not have a row and thus
-- `c.x` may be `NULL`
call requires_text_notnull(c.x);
```

To fix it, the cursor must be verified to have a row before the field is
accessed:

```sql
cursor c for select * from t;
fetch c;
if c then
  -- legal due to the above check
  call requires_text_notnull(c.x);
end if;
```

Alternatively, one can perform a "negative" check by returning (or using another
control flow statement) when the cursor does not have a row:

```sql
cursor c for select * from t;
fetch c;
if not c then
  call some_logging_function("no rows in t");
  return;
end if;
-- legal as we would have returned if `c` did not
-- have a row
call requires_text_notnull(c.x);
```

If you are sure that a row *must* be present, you can throw to make that
explicit:

```sql
cursor c for select * from t;
fetch c;
if not c throw;
-- legal as we would have thrown if `c` did not
-- have a row
call requires_text_notnull(c.x);
```

-----

### CQL0461 available for re-use

-----

### CQL0462: group declared variables must be top level 'name'

A `GROUP` statement for the named enum is happening inside of a
procedure.  This is not legal.

To correct this, move the declaration outside of the procedure.

-----

#### CQL0463: variable definitions do not match in group 'name'

The two described `GROUP` statements have the same name but they are not
identical.

The error output contains the full text of both declarations to compare.

-----

### CQL0464: group not found 'group_name'

The indicated name was used in a context where a variable group name was
expected but there is no such group.

Perhaps the group was not included (missing an @include) or else there is a
typo.

-----

### CQL0465: left operand of `:=` must be a name

The assignment syntax may be generalized at some point to support things like
arrays but for now only simple names may appear on the left of the `:=`
operator.

-----

### CQL0466: the table/view named in an @unsub directive does not exist 'name'

The indicated name is not a valid table or view.

-----

### CQL0467: a shared fragment used like a function cannot nest fragments that use arguments

When using a shared fragment like an expression, the shared fragment may contain
a nested select with a WITH statement that calls other fragments, like this:

```sql
[[shared_fragment]]
create proc expression_frag()
begin
  select (
    with
      (call frag())
    select frag.col from frag
    ...
  ) val
end;
```

However the nested fragment(s) cannot take any arguments. The inner fragment
must be moved outside to allow the fragment be used like a sql function.

-----

### CQL0468: [[shared_fragment]] may only be placed on a CREATE PROC statement 'proc_name'

In order to use a shared fragment the compiler must see the full body of the
fragment, this is because the fragment will be inlined into the SQL in which it
appears.  As a consequence it makes no sense to try to apply the attribute to a
procedure declaration. e.g.:

```sql
-- incorrect, the compiler needs to see the whole body of the shared fragment
[[shared_fragment]]
declare proc x() (x integer);

create proc y()
begin
  with (call x())
  select * from x;
end;
```

Instead provide the whole body of the fragment. e.g.:

```sql
[[shared_fragment]]
create proc x()
begin
  select 1 x; -- the procedure body must be present
end;
```

-----

### CQL0469: table/view is already deleted 'name'

In an @unsub directive, the indicated table/view has already been deleted. It
can no longer be managed via subscriptions.

-----

### CQL0470: operation is only available for types with a declared type kind like `object<something>` 'operator'

Array operations from a type like `object<foo>` generate calls to

`get_from_object_foo(index)` or `set_in_object_foo(index, value)`

>NOTE: There can be more than one index if desired e.g., `foo[a, b]`.

In order to do this and create sensible unique names the thing that has
array-like behavior has to have a type kind.

>NOTE: This works even for things that are primitive types.  For instance you
could use array notation to get optional fields from a task id even if the task
id is an integer.  `int<task_id> not null` can have an helper function
`get_from_int_task_id(index integer);` and it "just works".

>NOTE: Arrays can work in a SQL context if the appropriate `select functions`
>are defined.  Array syntax is only sugar.

Using the dot (.) operator can also map to `set_object_foo` or `get_object_foo`
and likewise requires a type kind.

-----

### CQL0471: a top level equality is almost certainly an error,  ':=' is assignment

Expressions can be top level statements and a statement like `x = 5;` is
technically legal but this is almost certainly supposed to be `x := 5`.  To
avoid that problem we make the former an error.  Note that in SQLite and CQL `=`
and `==` are the same thing.  `:=` is assignment.

-----

### CQL0472: table/view is already unsubscribed 'name'

In an @unsub directive, the indicated table/view has already been unsubscribed.
It doesn't need another unsubscription.

-----

### CQL0473: @unsub is invalid because the table/view is still used by 'name'

This error indicates that you are attempting to @unsub a table/view while there
are still other tables/views that refer to it (e.g. by FK).  You must @unsub all
of those as well in order to safely @unsub the present table/view.  All such
dependencies  will be listed.  Note that some of those might, in turn, have the
same issue.  In short, a whole subtree has to be removed in order to do this
operation safely.

-----

### CQL0474: when '*' appears in an expression list there can be nothing else in the list

For generality `*` can appear in many expression contexts but when it is used it must appear by itself.

For instance, `select *, * from foo` is not supported.

-----

### CQL0475: select functions cannot have out parameters 'param_name'

A function declared with `select function` will be called by SQLite --
it has no possibilty of having a call-by-reference out argument.  Therefore
these are disallowed.  Both `out` and `in out` forms generate this error and may
not be used.

-----

### CQL0476 available for re-use

-----

### CQL0477: interface name conflicts with func name 'name'

In a `DECLARE INTERFACE` statement, the given name conflicts with an already
declared function (`DECLARE FUNCTION` or `DECLARE SELECT FUNCTION`).  You'll
have to choose a different name.

-----

### CQL0478: interface name conflicts with procedure name 'name'

In a `DECLARE INTERFACE` statement, the indicated name already corresponds to a
created or declared stored procedure.  You'll have to choose a different name.

-----

### CQL0479: interface declarations do not match 'name'

The interface was previously declared with a `DECLARE INTERFACE` statement but
when subsequent `DECLARE INTERFACE` was encountered, it did not match the
previous declaration.

-----

### CQL0480: declared interface must be top level 'name'

A `DECLARE INTERFACE` statement is happening inside of a procedure.  This is not
legal.  To correct this move the declaration outside of the procedure.

-----

### CQL0481: proc name conflicts with interface name 'name'

In a `CREATE PROCEDURE` / `DECLARE PROCEDURE` statement, the given name
conflicts with an already declared interface (`DECLARE INTERFACE`).  You'll have
to choose a different name.

-----

### CQL0482: interface not found 'name'

Interface with the name provided in `cql:implements` attribute does not exist

-----

### CQL0483: table is not suitable for use as backing storage: [reason] 'table_name'

The indicated table was marked with `[[backing_table]]`.  This indicates that
the table is going to be used to as a generic storage location stored in the
database.

There are a number of reasons why a table might not be a valid as backing
storage.

For instance:

* it has foreign keys
* it has constraints
* it is a virtual table
* it has schema versioning

This error indicates that one of these items is present. The specific cause is
included in the text of the message.

-----

### CQL0484: procedure '%s' is missing column '%s' of interface '%s'

Procedure should return all columns defined by the interface (and possibly
others).  The columns may be returned in any order.

-----

### CQL0485: column types returned by proc need to be the same as defined on the interface

Procedure should return at least all columns defined by the interface and column
type should be the same.

-----

### CQL0486: function cannot be both a normal function and an unchecked function, 'function_name'

The same function cannot be declared as a function with unchecked parameters
with the `NO CHECK` clause and then redeclared with typed parameters, or vice
versa.

```sql
--- Declaration of an external function foo with unchecked parameters.
DECLARE SELECT FUNCTION foo NO CHECK t text;

...

--- A redeclaration of foo with typed paramters. This would be invalid if the previous declaration exists.
DECLARE SELECT FUNCTION foo() t text;
```

Make sure the redeclaration of the function is consistent with the original
declaration, or remove the redeclaration.

-----

### CQL0487: table is not suitable as backed storage: [reason] 'table_name'

The indicated table was marked with `[[backing_table]]`.  This indicates that
the table is going to be used to as a generic storage location stored in the
database.

There are a number of reasons why a table might not be a valid as backing
storage. For instance:

* it has foreign keys
* it has constraints
* it is a virtual table
* it has schema versioning

This error indicates that one of these items is present. The specific cause is
included in the text of the message.

-----

### CQL0488: the indicated table is not declared for backed storage 'table_name'

When declaring a backed table, you must specify the physical table that will
hold its data.  The backed table is marked with `[[backed_by=table_name)`.  The
backing table is marked with `@attribute(cql:backing]]`. The backing and
backed_by attributes applies extra checks to tables to ensure they are suitable
candidates.

This error indicates that the named table is not marked as a backed table.

-----

### CQL0489: the indicated column is not present in the named backed storage 'table_name.column_name'

The named table is a backed table, but it does not have the indicated column.

-----

### CQL0490: argument must be table.column where table is a backed table 'function"

The database blob access functions `cql_blob_get`, `cql_blob_create`,
`cql_blob_update` all allow you to specify the backed table name and column you
are trying to read/create/update.  The named function was called with a
table.column combination where the table is not a backed table, hence the call
is invalid.  Note that normally this error doesn't happen because these
functions are typically called by CQL itself as part of the rewriting process
for backed tables.  However it is possible to use them manually, hence they are
error checked.

-----

### CQL0491: argument 1 must be a table name that is a backed table 'cql_blob_create'

When using the `cql_blob_create` helper function, the first argument must be a
valid backed table (i.e. one that was marked with
`[[backed_by=some_backing_table)]]`.  The type signature of this table is used
to create a hash valid for the type of the blob that is created.  This error
indicates that the first argument is not even an identifier, much less a table
name that is backed.  There are more specific errors if the table is not found
or the table is not backed.  Note that normally this error doesn't happen
because this functions is typically called by CQL itself as part of the
rewriting process for backed tables.  However it is possible to
`cql_blob_create` manually, hence it is error checked.

-----

### CQL0492:  operator found in an invalid position 'operator'

There are several cases here:

Assigment expressions are only allowed so as to make the SET keyword optional
for readability.

Why this limitation?

First, control flow in expressions with side effects is weird and SQL has a lot
of this:

```sql
case when something then x := 5 else z := 2 end;
```

Would wreak havoc with the logic for testing for un-initialized variables.  This
is solvable with work.

Second, the normal way chained assignment works alters the type as you go along
so this form:

```sql
a := b := 1;
```

Would give an error if `b` is nullable and `a` is not nullable which is very
bizaree indeed.

For these reasons, at least for now, `:=` in expressions is just a convenience
feature to let you skip the `SET` keyword which makes code a bit more readable.

The other cases involve '*' and 'T.*' which are only allowed where column or
argument replacement is implied by them.  A loose '*'  like '* := 5;' is just
wrong.

-----

### CQL0493: backed storage tables may not be used in indexes/triggers/drop 'table_name'

The indicated table name was marked as backed storage.  Therefore it does not
have a physical manifestation, and therefore it cannot be used in an index or in
a trigger.  You may be able to get the index or trigger you want by creating an
index on the backing storage and then using the blob access functions to index a
column or check colulmns in a trigger.  For instance this index is pretty
normal:

```
[[backing_table]]
create table backing (
  k blob primary key,
  v blob not null
);

create index backing_type_index on backing(cql_blob_get_type(k));
```

This gives you a useful index on the type field of the blob for all backed
tables that use `backing_table`.

But generally, physical operations like indices, triggers, and drop are not
applicable to backed tables.

-----

### CQL0494: mixing adding and removing columns from a shape 'name'

When selecting columns from a shape you can use this form

```sql
LIKE some_shape(name1, name2)
```

to extract the named columns or this form

```sql
LIKE some_shape(-name1, -name2)
```

to extract everything but the named columns.  You can't mix the positive and
negative forms

-----

### CQL0495: no columns were selected in the LIKE expression

An expression that is supposed to select some columns from a shape such as

```sql
LIKE some_shape(-name1, -name2)
```

ended up removing all the columns from `some_shape`.

-----

### CQL0496: SELECT NOTHING may only appear in the else clause of a shared fragment

A common case for conditional shared fragments is that there are rows that
should be optionally included.  The normal way this is handled is to have a
condition like this

```sql
IF something THEN
  SELECT your_data;
ELSE
  SELECT dummy data WHERE 0;
END IF;
```

The problem here is that dummy_data could be complex and involve a lot of typing
to get nothing. To make this less tedious CQL allows:

```sql
IF something THEN
  SELECT your_data;
ELSE
  SELECT NOTHING;
END IF;
```

However this is the only place SELECT NOTHING is allowed.  It must be:

* in a procedure
* which is a conditional shared fragment
* in the else clause

Any violation results in the present error.

-----

### CQL0497: FROM clause not supported when updating backed table, 'table_name'

SQLite supports an extended format of the update statement with a FROM clause.
At this time backed tables cannot be updated using this form.  This is likely to
change fairly soon.

-----

### CQL0498: strict UPDATE ... FROM validation requires that the UPDATE statement not include a FROM clause

`@enforce_strict` has been use to enable strict update enforcement.  When
enabled update statements may not include a FROM clause. This is done if the
code expects to target SQLite version 3.33 or lower.

-----

### CQL0499: alias_of attribute may only be added to a function statement

`cql:alias_of` attributes may only be used in [`DECLARE FUNC`
statements](../08_functions.md#ordinary-scalar-functions) or [`DECLARE PROC`
statements](../06_importing_and_exporting_procedures.md#declaring-procedures-defined-elsewhere).

-----

### CQL0500: alias_of attribute must be a non-empty string argument

`cql:alias_of` must have a string argument to indicate the underlying function
name that the aliased function references. For example:

```sql
[[alias_of=foo]]
func bar() int;
```

All subsequent calls to `bar()` in CQL will call the `foo()` function.

-----

### CQL0501: WHEN expression must not be a constant NULL but can be of a nullable type

In a `CASE` statement each `WHEN` expression must not be a constant NULL. For example:
```sql
  var hex text;
  set hex := case color
    when NULL    then "#FFFFFF" -- error
    when "red"   then "#FF0000"
    when "green" then "#00FF00"
    when "blue"  then "#0000FF"
    else "#000000"
  end;
```
-----

### CQL0501: WHEN expression must not be a constant NULL but can be of a nullable type

When the case expression `color` evaluates to NULL, it does not match with an
expression that evaluates to NULL. Consequently, the CASE statement will default
to the ELSE clause, provided it is defined.

-----

### CQL0502: Cannot re-assign value to constant variable.

When you declare variables with the `const` syntax, they cannot be re-assigned a
new value (e.g. with a `set` statement, are being passed to an out argument).

Declare these variables with a `let` statement instead if you would like to mutate them.

----

### CQL0503: left operand must be json text or json blob 'context'

The indicated argument or operand is expected to be JSON in the form of either
text or a blob. will indicate which argument number or operand that is
incorrect.

----

### CQL0504: right operand must be json text path or integer 'context'

The indicated argument or operand is expected to be a json path in text form.
The error will indicate which argument number or operand that is incorrect.

----

### CQL0505 available for re-use

----

### CQL0506: left argument must have a type kind

When using the pipeline syntax with no function name e.g.

```sql
foo:(1):(2):(3);
```

The left argument of the pipeline, `foo` in this example, must have a type
"kind" because the pipeline uses the "kind" to generate the name of the function
it will call.

```sql
var foo object<builder>;
foo := new_builder();
let u := foo:(1);

-- becomes

let u := object_builder_int(foo, 1);
```

Without the:(2):(3); `builder` the name isn't unique enough to be useful.

Note that if object_builder_int returns the first argument (`foo`) then it can
be chained as in the first example `foo:(1):(2):(3)`.
