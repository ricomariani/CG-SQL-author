---
title: "Chapter 11: Previous Schema Validation"
weight: 11
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

As we saw in the previous chapter, CQL includes powerful schema management
tools for creating automatic upgrade scripts for your databases.
However, not all schema alterations are possible after-the-fact and so
CQL also includes schema comparison tools to help you avoid problems as
you version your schema over time.

You can compare the previous version of a schema with the current version
to do additional checks such as:

* the data type of a column may not change
* the attributes of a column (e.g. nullable, default value) may not change
* columns can't be renamed
* columns can't be removed, only marked delete
* new columns must be at the end of the table and marked with create
* created columns have to be created in a schema version >= any that previously
  existed (no creating columns in the past)
* nothing other than new columns at the end may be added to a table (e.g. new
  PK/UK is right out)
* new tables must be marked create, deleted tables must be marked delete
* new views must be marked create, deleted views must be marked delete
* new indices must be marked create, deleted indices must be marked delete
* an item that was previously a table/view cannot turn into the other one
* version numbers in the annotations may not ever change
* if any annotation has a migration proc associated with it, it cannot change to
  a different proc later
* created tables, views, indices have to be created in a schema version >= any
  that previously existed (no creating tables in the past)
* there may be other checks not mentioned here

When checking `@recreate` tables against the previous schema version
for errors, these checks are done:

* suppress checking of any table facet changes in previous schema on recreate tables; you can do anything you want
* allow new `@recreate` tables to appear with no `@create` needed
* allow a table to go from "original schema" (no annotation) to `@recreate` but not back
* allow a table to go from `@recreate` to `@create` at the current schema version
* allow a table to go from recreate directly to `@delete` at the current schema version
* do not allow a table to go from `@create` or `@delete` state to `@recreate`

All of these are statically checked.

To use these tools, you must run CQL in a mode where it has both the
proposed and existing schema in its input stream,
then it can provide suitable errors if any unsupported change is about to happen.

### Basic Usage

The normal way that you do previous schema validation is to create an
input file that provides both schema.

This file may look something like this:

```sql
-- prev_check.sql
create table foo(
  id int,
  new_field text @create(1)
);

@previous_schema;

create table foo(
  id int
);
```

So, here the old version of `foo` will be validated against the new
version and all is well.  A new nullable text field was added at the end.

In practice these comparisons are likely to be done in a somewhat more
maintainable way, like so:

```sql
-- prev_check.sql
@include "table1.sql"
@include "table2.sql"
@include "table3.sql"

@previous_schema;

@include "previous.sql"
```

Now importantly, in this configuration, everything that follows the
`@previous_schema` directive does not actually contribute to the declared
schema.  This means the `--rt schema` result type will not see it. Because of
this, you can do your checking operation like so:

```bash
cc -E -x c prev_check.sql | cql --cg new_previous_schema.sql --rt schema
```

The above command will generate the schema in new_previous_schema and, if this
command succeeds, it's safe to replace the existing `previous.sql` with
`new_previous_schema`.

>NOTE: you can bootstrap the above by leaving off the `@previous_schema` and
>what follows to get your first previous schema from the command above.

Now, as you can imagine, comparing against the previous schema allows many more
kinds of errors to be discovered.  What follows is a large chunk of the CQL
tests for this area taken from the test files themselves. For easy visibility I
have brought each fragment of current and previous schema close to each other
and I show the errors that are reported. We start with a valid fragment and go
from there.


#### Case 1 : No problemo

```sql
create table foo(
  id int!,
  rate long @delete(5, deletor),
  rate_2 long @delete(4),
  id2 integer @create(4),
  name text @create(5),
  name_2 text @create(6)
);
-------
create table foo(
  id int!,
  rate long @delete(5, deletor),
  rate_2 long @delete(4),
  id2 integer @create(4),
  name text @create(5),
  name_2 text @create(6)
);
```
The table `foo` is the same!  It doesn't get any easier than that.

#### Case 2 : table create version changed

```sql
create table t_create_version_changed(id int) @create(1);
-------
create table t_create_version_changed(id int) @create(2);

Error at sem_test_prev.sql:15 : in str : current create version not equal to
previous create version for 't_create_version_changed'
```
You can't change the version a table was created in.  Here the new schema
says it appeared in version 1.  The old schema says 2.

#### Case 3 : table delete version changed

```sql
create table t_delete_version_changed(id int) @delete(1);
-------
create table t_delete_version_changed(id int) @delete(2);

Error at sem_test_prev.sql:18 : in str : current delete version not equal to
previous delete version for 't_delete_version_changed'
```
You can't change the version a table was deleted in.  Here the new schema
says it was gone in version 1.  The old schema says 2.

#### Case 4 : table not present in new schema

```sql
-- t_not_present_in_new_schema is gone
-------
create table t_not_present_in_new_schema(id int);

Error at sem_test_prev.sql:176 : in create_table_stmt : table was present but now it
does not exist (use @delete instead) 't_not_present_in_new_schema'
```
So here `t_not_present_in_new_schema` was removed, it should have been
marked with `@delete`.  You don't remove tables.

#### Case 5 : table is now a view

```sql
create view t_became_a_view as select 1 id @create(6);
-------
create table t_became_a_view(id int);

Error at sem_test_prev.sql:24 : in create_view_stmt : object was a table but is now a
view 't_became_a_view'
```
Tables can't become views...

#### Case 6 : table was in base schema, now created

```sql
create table t_created_in_wrong_version(id int) @create(1);
-------
create table t_created_in_wrong_version(id int);

Error at sem_test_prev.sql:27 : in str : current create version not equal to previous
create version for 't_created_in_wrong_version'
```
Here a version annotation is added after the fact.  This item was already in the base schema.

#### Case 7: table was in base schema, now deleted (ok)

```sql
create table t_was_correctly_deleted(id int) @delete(1);
-------
create table t_was_correctly_deleted(id int);
```
No errors here, just a regular delete.

#### Case 8: column name changed

```sql
create table t_column_name_changed(id_ integer);
-------
create table t_column_name_changed(id int);

Error at sem_test_prev.sql:33 : in str : column name is different between previous
and current schema 'id_'
```

You can't rename columns. We could support this but it's a bit of a maintenance
nightmare. On the other hand logical renames of columns in procedure results are
trivial without doing physical renames.

#### Case 9 : column type changed

```sql
create table t_column_type_changed(id real);
-------
create table t_column_type_changed(id int);

Error at sem_test_prev.sql:36 : in str : column type is different between previous
and current schema 'id'
```
You can't change the type of a column.

#### Case 10 : column attribute changed

```sql
create table t_column_attribute_changed(id int!);
-------
create table t_column_attribute_changed(id int);

Error at sem_test_prev.sql:39 : in str : column type is different between previous
and current schema 'id'
```
Change of column attributes counts as a change of type.

#### Case 11: column version changed for delete

```sql
create table t_column_delete_version_changed(id int, id2 integer @delete(1));
-------
create table t_column_delete_version_changed(id int, id2 integer @delete(2));

Error at sem_test_prev.sql:42 : in str : column current delete version not equal
to previous delete version 'id2'
```

You can't change the delete version after it has been set.

#### Case 12 : column version changed for create
```sql
create table t_column_create_version_changed(id int, id2 integer @create(1));
-------
create table t_column_create_version_changed(id int, id2 integer @create(2));

Error at sem_test_prev.sql:45 : in str : column current create version not equal
to previous create version 'id2'
```

You can't change the create version after it has been set.

#### Case 13 : column default value changed

```sql
create table t_column_default_value_changed(id int, id2 int! default 2);
-------
create table t_column_default_value_changed(id int, id2 int! default 1);

Error at sem_test_prev.sql:48 : in str : column current default value not equal
to previous default value 'id2'
```

You can't change the default value after the fact.  There's no alter
statement that would allow this even though it does make some logical
sense.

#### Case 14 : column default value did not change (ok)

```sql
create table t_column_default_value_ok(id int, id2 int! default 1);
-------
create table t_column_default_value_ok(id int, id2 int! default 1);
```

No change. No error here.

#### Case 15 : create table with additional attribute present and matching (ok)

```sql
create table t_additional_attribute_present(a int!, b int, primary key (a,b));
-------
create table t_additional_attribute_present(a int!, b int, primary key (a,b));
```

No change. No error here.

#### Case 16 : create table with additional attribute (doesn't match)

```sql
create table t_additional_attribute_mismatch(a int!, primary key (a));
-------
create table t_additional_attribute_mismatch(a int!, b int, primary key (a,b));

Error at sem_test_prev.sql:57 : in pk_def : a table facet is different in the previous
and current schema
```

This is an error because the additional attribute does not match the previous schema.

#### Case 17 : column removed

```sql
create table t_columns_removed(id int);
-------
create table t_columns_removed(id int, id2 integer);

Error at sem_test_prev.sql:255 : in col_def : items have been removed from the table
rather than marked with @delete 't_columns_removed'
```

You can't remove columns from tables.  You have to mark them with `@delete` instead.

#### Case 18 : create table with added facet not present in the previous
```sql
create table t_attribute_added(a int!, primary key (a));
-------
create table t_attribute_added(a int!);

Error at sem_test_prev.sql:63 : in pk_def : table has a facet that is different in the
previous and current schema 't_attribute_added'
```

Table facets like primary keys cannot be added after the fact. There is no way to do this in sqlite.

#### Case 19 : create table with additional column and no `@create`

```sql
create table t_additional_column(a int!, b int);
-------
create table t_additional_column(a int!);

Error at sem_test_prev.sql:66 : in col_def : table has columns added without marking
them @create 't_additional_column'
```

If you add a new column like `b` above you have to mark it with `@create` in a suitable version.

#### Case 20 : create table with additional column and ``@create` (ok)

```sql
create table t_additional_column_ok(a int!, b int @create(2), c int @create(6));
-------
create table t_additional_column_ok(a int!, b int @create(2));
```

Column properly created.  No errors here.

#### Case 21 : create table with different flags (like TEMP)

```sql
create TEMP table t_becomes_temp_table(a int!, b int);
-------
create table t_becomes_temp_table(a int!, b int);

Error at sem_test_prev.sql:72 : in create_table_stmt : table create statement attributes
different than previous version 't_becomes_temp_table'
```

Table became a TEMP table, there is no way to generate an alter statement for
that.  Not allowed.

#### Case 22 : create table and apply annotation (ok)

```sql
create table t_new_table_ok(a int!, b int) @create(6);
-------
-- no previous version
```
No errors here; this is a properly created new table.

#### Case 23 : create new table without annotation (error)

```sql
create table t_new_table_no_annotation(a int!, b int);
-------
-- no previous version

Error at sem_test_prev.sql:85 : in create_table_stmt : new table must be added with
@create(6) or later 't_new_table_no_annotation'
```
This table was added with no annotation.  It has to have an @create and be at
least version 6, the current largest.

#### Case 24 : create new table stale annotation (error)

```sql
create table t_new_table_stale_annotation(a int!, b int) @create(2);
-------
-- no previous version

Error at sem_test_prev.sql:91 : in create_table_stmt : new table must be added with
@create(6) or later 't_new_table_stale_annotation'
```
The schema is already up to version 6.  You can't then add a table in the past
at version 2.

#### Case 25 : add columns to table, marked `@create` and `@delete`

```sql
create table t_new_table_create_and_delete(a int!, b int @create(6) @delete(7));
-------
create table t_new_table_create_and_delete(a int!);

Error at sem_test_prev.sql:96 : in col_def : table has newly added columns that are
marked both @create and @delete 't_new_table_create_and_delete'
```
Adding a column in the new version and marking it both create and delete is ...
weird... don't do that.  Technically you can do it (sigh) but it must be done
one step at a time.

#### Case 26 : add columns to table, marked `@create` correctly

```sql
create table t_new_legit_column(a int!, b int @create(6));
-------
create table t_new_legit_column(a int!);
```
No errors here; new column added in legit version.

#### Case 27 : create table with a create migration proc where there was none

```sql
create table with_create_migrator(id int) @create(1, ACreateMigrator);
-------
create table with_create_migrator(id int) @create(1);

Error at sem_test_prev.sql:104 : in str : @create procedure changed in object
'with_create_migrator'
```

You can't add a create migration proc after the fact.

#### Case 28 : create table with a different create migration proc

```sql
create table with_create_migrator(id int) @create(1, ACreateMigrator);
-------
create table with_create_migrator(id int) @create(1, ADifferentCreateMigrator);

Error at sem_test_prev.sql:104 : in str : @create procedure changed in object
'with_create_migrator'
```

You can't change a create migration proc after the fact.

#### Case 29 : create table with a delete migration proc where there was none

```sql
create table with_delete_migrator(id int) @delete(1, ADeleteMigrator);
-------
create table with_delete_migrator(id int) @delete(1);

Error at sem_test_prev.sql:107 : in str : @delete procedure changed in object
'with_delete_migrator'
```

You can't add a delete migration proc after the fact.

#### Case 30 : create table with a different delete migration proc

```sql
create table with_delete_migrator(id int) @delete(1, ADeleteMigrator);
-------
create table with_delete_migrator(id int) @delete(1, ADifferentDeleteMigrator);

Error at sem_test_prev.sql:107 : in str : @delete procedure changed in object
'with_delete_migrator'
```

You can't change a delete migration proc after the fact.

#### Case 31 : create a table which was a view in the previous schema

```sql
create table view_becomes_a_table(id int);
-------
create view view_becomes_a_table as select 1 X;

Error at sem_test_prev.sql:110 : in create_table_stmt : object was a view but is now a
table 'view_becomes_a_table'
```
Converting views to tables is not allowed.

#### Case 32 : delete a view without marking it deleted

```sql
--- no matching view in current schema
-------
create view view_was_zomg_deleted as select 1 X;

Error at sem_test_prev.sql:333 : in create_view_stmt : view was present but now it does
not exist (use @delete instead) 'view_was_zomg_deleted'
```
Here the view was deleted rather than marking it with `@delete`, resulting in an error.

#### Case 33 : create a new version of this view that is not temp

```sql
create view view_was_temp_but_now_it_is_not as select 1 X;
-------
create temp view view_was_temp_but_now_it_is_not as select 1 X;

Error at sem_test_prev.sql:339 : in create_view_stmt : TEMP property changed in new
schema for view 'view_was_temp_but_now_it_is_not'
```

A temp view became a view.  This flag is not allowed to change.  Side note: temp views are weird.

#### Case 34 : create a new version of this view that was created in a different version

```sql
create view view_with_different_create_version as select 1 X @create(3);
-------
create view view_with_different_create_version as select 1 X @create(2);

Error at sem_test_prev.sql:116 : in str : current create version not equal to previous
create version for 'view_with_different_create_version'
```
You can't change the create version of a view after the fact.


#### Case 35 : create an index that is now totally gone in the new schema

```sql
--- no matching index in current schema
-------
create index this_index_was_deleted_with_no_annotation on foo(id);

Error at sem_test_prev.sql:349 : in create_index_stmt : index was present but now it
does not exist (use @delete instead) 'this_index_was_deleted_with_no_annotation'
```
You have to use `@delete` on indices to remove them correctly.

#### Case 36 : create a view with no annotation that is not in the previous schema

```sql
create view view_created_with_no_annotation as select 1 X;
-------
--- there is no previous version

Error at sem_test_prev.sql:122 : in create_view_stmt : new view must be added with
@create(6) or later 'view_created_with_no_annotation'
```
You have to use `@create` on views to create them correctly.

#### Case 37 : index created in different version

```sql
create index this_index_has_a_changed_attribute on foo(id) @create(2);
-------
create index this_index_has_a_changed_attribute on foo(id) @create(1);

Error at sem_test_prev.sql:125 : in str : current create version not equal to previous
create version for 'this_index_has_a_changed_attribute'
```
You can't change the `@create` version of an index.

#### Case 38 : create a new index but with no `@create` annotation

```sql
create index this_index_was_created_with_no_annotation on foo(id);
-------
--- there is no previous version

Error at sem_test_prev.sql:130 : in create_index_stmt : new index must be added with
@create(6) or later 'this_index_was_created_with_no_annotation'
```

You have to use `@create` on indices to make new ones.

#### Case 39 : create a table with a column def that has a different create migrator proc

```sql
create table create_column_migrate_test(
 id int,
 id2 int @create(2, ChangedColumnCreateMigrator)
);
-------
create table create_column_migrate_test(
 id int,
 id2 int @create(2, PreviousColumnCreateMigrator)
);

Error at sem_test_prev.sql:136 : in str : column @create procedure changed 'id2'
```
You can't change the `@create` migration stored proc on columns.


#### Case 40 : create a table with a column def that has a different delete migrator proc

```sql
create table delete_column_migrate_test(
 id int,
 id2 int @delete(2, ChangedColumnDeleteMigrator)
);
-------
create table delete_column_migrate_test(
 id int,
 id2 int @delete(2, PreviousColumnDeleteMigrator)
);

Error at sem_test_prev.sql:142 : in str : column @delete procedure changed 'id2'
```

You can't change the `@delete` migration stored proc on columns.

>NOTE: in addition to these errors, there are many more that do not require the
>previous schema which are also checked (not shown here). These comprise things
>like making sure the delete version is greater than the create version on any
>item.  There is a lot of "sensibility checking" that can happen without
>reference to the previous schema.
