---
title: "Chapter 10: Schema Management"
weight: 10
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL has a lot of schema knowledge already and so it's well positioned to think about schema upgrades and versioning.

It seemed essential to be able to record changes to the schema over time
so CQL got an understanding of versioning.  This lets you do things like:

* ensure columns are only added where they should be
* generate compiler errors if you try to access columns that are deprecated
* move from one version to another tracking schema facets that have to be added

To use cql in this fashion, the sequence will be something like the below.  See Appendix 1 for command line details.

```
cql --in input.sql --rt schema_upgrade --cg schema_upgrader.sql \
                   --global_proc desired_upgrade_proc_name
```

### Annotations

There are three basic flavors of annotation

* `@create(version [, migration proc])`
* `@delete(version [, migration proc])`
* `@recreate`

They have various constraints:

* `@create` and `@delete` can only be applied to tables and columns
* `@recreate` can only be applied to tables (nothing else needs it anyway)
* `@recreate` cannot mix with `@create` or `@delete`
* `@recreate` can include a group name as in `@recreate(musketeers)`; if a group name is specified then all the tables in that group are recreated if any of them change

Indices, Views, and Triggers are always "recreated" (just like tables
can be) and so neither the `@recreate` nor the `@create` annotations are
needed (or allowed).  However when an Index, View, or Trigger is retired
it must be marked with `@delete` so that it isn't totally forgotten but
can be deleted anywhere it might still exist.  Note that when one of
these items is deleted, the definition is not used as it will only be
dropped anyway. The simplest creation of the object with the correct
name will do the job as a tombstone.

e.g. `create view used_to_be_fabulous as select 1 x @delete(12);`
suffices to drop the `used_to_be_fabulous` view in version 12 no matter
how complicated it used to be.  Its `CREATE VIEW` will not be emitted
into the upgrade procedure in any case.  Similarly, trivial indices and
triggers of the correct name can be used for the tombstone.

In addition, if there is some data migration that needs to happen at a
particular schema version that isn't associated with any particular change
in schema, you can run an *ad hoc* migrator at any time.  The syntax
for that is `@schema_ad_hoc_migration(version, migration proc);`.
Ad hoc migrations are the last to run in any given schema version;
they happen after table drop migrations.

### Semantics

`@create` declares that the annotated object first appeared in the
indicated version, and at that time the migration proc needs to be
executed to fill in default values, denormalize values, or whatever the
case may be.

`@delete` declares that the annotated object disappeared in the indicated
version, and at that time the migration proc needs to be executed to
clean up the contents, or potentially move them elsewhere.

`@recreate` declares that the annotated object can be dropped and
recreated when it changes because there is no need to preserve its
contents during an upgrade. Such objects may be changed arbitrarily from
version to version.


* no columns in a `@recreate` table may have `@create` or `@delete` (these aren't needed anyway)
   * therefore tables with `@recreate` never have deprecated columns (since `@delete` isn't allowed on their columns)

>NOTE: all annotations are suppressed from generated SQL.  SQLite never sees them.

>NOTE: looking at the annotations it is possible to compute the logical
>schema at any version, especially the original schema -- it's what you
>get if you disregard all ```@delete``` entirely (don't delete) and then
>remove anything marked with ```@create``` directives.

### Allowable changes

Not all migrations are possible in a sensible fashion, therefore CQL
enforces certain limitations:

* the "original" schema has no annotations or just delete annotations
* new tables may be added (with ```@create```)
* tables may be deleted (with ```@delete```)
* columns may be added to a table, but only at the end of the table
* added columns must be nullable or have a default value (otherwise all existing insert statements would break for sure)
* columns may not be renamed
* columns may be deleted but this is only a logical delete, SQLite has no primitive to remove columns; once deleted you may no longer refer to that column in queries
* deleted columns must be nullable or have a default value (otherwise all existing and future insert statements would break for sure, the column isn't really gone)
* views, indices, and triggers may be added (no annotation required) and removed (with `@delete`) like tables
* views, indices, and triggers may be altered completely from version to version
* no normal code is allowed to refer to deleted columns, tables, etc.  This includes views, indices, and triggers
* schema migration stored procs see the schema as it existed in their annotation (so an older version). They are also forbidden from using views (see below)
* recreated objects (tables marked with @recreate, views, tables, and indices) have no change restrictions


### Prosecution

Moving from one schema version to another is done in an orderly fashion
with the migration proc taking these essential steps in this order:

* the `cql_schema_facets` table is created if needed -- this records the current state of the schema
* the last known schema hash is read from the `cql_schema_facets` tables (it is zero by default)
* if the overall schema hash code matches what is stored, processing stops; otherwise an upgrade ensues
* all known views are dropped (hence migration procs won't see them!)
* any index that needs to change is dropped (this includes items marked ```@delete``` or indices that are different than before)
  * change is detected by hash (crc64) of the previous index definition vs. the current
* all known triggers are dropped (hence they will not fire during migration!)
* the current schema version is extracted from ```cql_schema_facets``` (it is zero by default)
* if the current schema version is zero, then the original versions of all the tables are created

* if the current schema version is <= 1 then
  * any tables that need to be created at schema version 1 are created as they exist at schema version 1
  * any columns that need to be created at schema version 1 are created as they exist at schema version 1
  * migration procedures schema version 1 are run in this order:
    * create table migration
    * create column migration
    * delete trigger migration (these are super rare and supported for uniformity)
    * delete index migration (these are super rare and supported for uniformity)
    * delete view migration  (these are super rare and supported for uniformity)
    * delete column migration
    * delete table migration
    * ad hoc migration
    * each proc is run exactly one time
  * any tables that need to be dropped at schema version 1 are dropped
  * the schema version is marked as 1 in ```cql_schema_facets```
  * each sub-step in the above is recorded in ```cql_schema_facets``` as it happens so it is not repeated
    * all that checking not shown for brevity

* the above process is repeated for all schema versions up to the current version
* all tables that are marked with `@recreate` are re-created if necessary
  * i.e. if the checksum of the table definition has changed for any  table (or group) then `drop` it and create the new version.
* all indices that changed and were not marked with `@delete` are re-created
* all views not marked with `@delete` are re-created
* all triggers not marked with `@delete` are re-installed
* the current schema hash is written to the ```cql_schema_facets``` table

### Example Migration

Here's an example of a schema directly from the test cases:

```
-- crazy amount of versioning here
create table foo(
  id int!,
  rate long @delete(5),
  rate_2 long @delete(4, DeleteRate2Proc),
  id2 integer default 12345 @create(4, CreateId2Proc),
  name text @create(5),
  name_2 text @create(6)
);

-- much simpler table, lots of stuff added in v2.
-- note v1 is the first new version and v0 is base version
create table table2(
  id int!,
  name1 text @create(2, CreateName1Proc),
  name2 text @create(2, CreateName2Proc),
  name3 text @create(2), -- no proc
  name4 text @create(2) -- no proc
);

create table added_table(
  id int!,
  name1 text,
  name2 text @create(4)
) @create(3) @delete(5);

-- this view is present in the output
create view live_view as select * from foo;

-- this view is also present in the output
create view another_live_view as select * from foo;

-- this view is not present in the output
create view dead_view as select * from foo @delete(2);

-- this index is present
create index index_still_present on table2(name1, name2);

-- this index is going away
create index index_going_away on table2(name3) @delete(3);

-- this is a simple trigger, and it's a bit silly but that doesn't matter
create trigger trigger_one
  after insert on foo
begin
  delete from table2 where table2.id = new.id;
end;
```

This schema has a LOT of versioning... you can see tables and columns
appearing in versions 2 through 6.  There is a lot of error checking
happening.

* things with no create annotation were present in the base schema
* only things with no delete annotation are visible to normal code
* created columns have to be at the end of their table (required by SQLite)
* they have to be in ascending schema version order (but you can add several columns in one version)
* there may or may not be a proc to run to populate data in that column when it's added or to remove data when it's deleted
   * proc names must be unique
* you can't delete a table or column in a version before it was created
* you can't delete a column in a table in a version before the table was created
* you can't create a column in a table in a version after the table was deleted
* there may be additional checks not listed here

### Sample Upgrade Script
With just those annotations you can automatically create the following
upgrade script which is itself CQL (and hence has to be compiled). Notice
that this code is totally readable!

The script has been split into logical pieces to make it easier to
explain what's going on.

#### Preamble

```sql
-- ...copyright notice... possibly generated source tag... elided to avoid confusion

-- no columns will be considered hidden in this script
-- DDL in procs will not count as declarations
@SCHEMA_UPGRADE_SCRIPT;
```

Schema upgrade scripts need to see all the columns even the ones that
would be logically deleted in normal mode.  This is so that things like
`alter table add column` can refer to real columns and `drop table` can
refer to a table that shouldn't even be visible.  Remember in CQL the
declarations tell you the logical state of the universe and DLL mutations
are expected to create that condition, so you should be dropping tables
that are marked with `@delete` CQL stores the current state of the
universe in this table.

```sql
-- schema crc -7714030317354747478
```
The schema crc is computed by hashing all the schema declarations in
canonical form.  That's everything in this next section.

#### Facet Helpers

CQL uses a set of four functions to manage a dictionary.  The
implementation is in `cqlrt_common.c` but it's really just a simple hash
table that maps from a string key to a number.  This functionality was
added because over time the facets table can get pretty big and running
a SQL query every time to read a single integer is not economical.

```sql
-- declare facet helpers--
DECLARE facet_data TYPE LONG<facet_data> not null;
DECLARE test_facets facet_data;
DECLARE FUNCTION cql_facets_new() facet_data;
DECLARE PROCEDURE cql_facets_delete(facets facet_data);
DECLARE FUNCTION cql_facet_add(facets facet_data, facet TEXT!, crc LONG NOT NULL) BOOL!;
DECLARE FUNCTION cql_facet_find(facets facet_data, facet TEXT!) LONG NOT NULL;
```

#### Declaration Section
Wherein all the necessary objects are declared...

```sql
-- declare sqlite_master --
CREATE TABLE sqlite_master (
  type TEXT!,
  name TEXT!,
  tbl_name TEXT!,
  rootpage INT!,
  sql TEXT!
);
```
The `sqlite_master` table is built-in but it has to be introduced to CQL
so that we can query it. Like all the other loose DDL declarations here
there is no code generated for this.  We are simply declaring tables.
To create code you have to put the DDL in a proc.  Normally DDL in
procs also declares the table but since we may need the original
version of a table created and the final version declared we have
`@schema_upgrade_script` to help avoid name conflicts.

```sql
-- declare full schema of tables and views to be upgraded --
CREATE TABLE foo(
  id INT!,
  rate LONG @DELETE(5),
  rate_2 LONG @DELETE(4, DeleteRate2Proc),
  id2 INTEGER DEFAULT 12345 @CREATE(4, CreateId2Proc),
  name TEXT @CREATE(5),
  name_2 TEXT @CREATE(6)
);

CREATE TABLE table2(
  id INT!,
  name1 TEXT @CREATE(2, CreateName1Proc),
  name2 TEXT @CREATE(2, CreateName2Proc),
  name3 TEXT @CREATE(2),
  name4 TEXT @CREATE(2)
);

CREATE TABLE added_table(
  id INT!,
  name1 TEXT,
  name2 TEXT @CREATE(4)
) @CREATE(3) @DELETE(5);
```

>NOTE: all the tables are emitted including all the annotations.
>This lets us do the maximum validation when we compile this script.

```sql
CREATE VIEW live_view AS
SELECT *
  FROM foo;

CREATE VIEW another_live_view AS
SELECT *
  FROM foo;

CREATE VIEW dead_view AS
SELECT *
  FROM foo @DELETE(2);
```
These view declarations do very little.  We only need the view names so
we can legally drop the views.  We create the views elsewhere.

```sql
CREATE INDEX index_still_present ON table2 (name1, name2);
CREATE INDEX index_going_away ON table2 (name3) @DELETE(3);
```
Just like views, these declarations introduce the index names and nothing else.

```sql
CREATE TRIGGER trigger_one
  AFTER INSERT ON foo
BEGIN
DELETE FROM table2 WHERE table2.id = new.id;
END;
```
We have only the one trigger; we declare it here.

```sql
-- facets table declaration --
CREATE TABLE IF NOT EXISTS test_cql_schema_facets(
  facet TEXT! PRIMARY KEY,
  version LONG!
);
```
This is where we will store everything we know about the current state of
the schema.  Below we define a few helper procs for reading and writing
that table and reading `sqlite_master`

```sql
-- saved facets table declaration --
CREATE TEMP TABLE test_cql_schema_facets_saved(
  facet TEXT! PRIMARY KEY,
  version LONG!
);
```
We will snapshot the facets table at the start of the run so that we can
produce a summary of the changes at the end of the run.  This table will
hold that snapshot.

>NOTE: the prefix "test" was specified when this file was built so all the methods and tables begin with `test_`.

#### Helper Procedures
```sql
-- helper proc for testing for the presence of a column/type
PROC test_check_column_exists(table_name TEXT!,
                                          decl TEXT!,
                                          OUT present BOOL!)
BEGIN
  SET present := (SELECT EXISTS(SELECT * FROM sqlite_master
                  WHERE tbl_name = table_name AND sql GLOB decl));
END;
```
`check_column_exists` inspects `sqlite_master` and returns true if a column matching `decl` exists.


```sql
-- helper proc for creating the schema version table
PROC test_create_cql_schema_facets_if_needed()
BEGIN
  CREATE TABLE IF NOT EXISTS test_cql_schema_facets(
    facet TEXT! PRIMARY KEY,
    version LONG!
  );
END;
```
Here we actually create the `cql_schema_facets` table with DDL inside
a proc.  In a non-schema-upgrade script the above would give a name
conflict.

```sql
-- helper proc for saving the schema version table
PROC test_save_cql_schema_facets()
BEGIN
  DROP TABLE IF EXISTS test_cql_schema_facets_saved;
  CREATE TEMP TABLE test_cql_schema_facets_saved(
    facet TEXT! PRIMARY KEY,
    version LONG!
  );
  INSERT INTO test_cql_schema_facets_saved
    SELECT * FROM test_cql_schema_facets;
END;
```

The `save_sql_schema_facets` procedure simply makes a snapshot of
the current facets table.  Later we use this snapshot to report the
differences by joining these tables.

```sql
-- helper proc for setting the schema version of a facet
PROC test_cql_set_facet_version(_facet TEXT!, _version LONG!)
BEGIN
  INSERT OR REPLACE INTO test_cql_schema_facets (facet, version)
       VALUES(_facet, _version);
END;

-- helper proc for getting the schema version of a facet
PROC test_cql_get_facet_version(_facet TEXT!, out _version LONG!)
BEGIN
  TRY
    SET _version := (SELECT version FROM test_cql_schema_facets
                       WHERE facet = _facet LIMIT 1 IF NOTHING -1);
  CATCH
    SET _version := -1;
  END;
END;
```
The two procedures `cql_get_facet_version` and `cql_set_facet_version`
do just what you would expect.  Note the use of `try` and `catch` to
return a default value if the select fails.

There are two additional helper procedures that do essentially the same
thing using a schema version index.  These two methods exist only to avoid
unnecessary repeated string literals in the output file which cause bloat.

```sql
-- helper proc for getting the schema version CRC for a version index
PROC test_cql_get_version_crc(_v INT!, out _crc LONG!)
BEGIN
  SET _crc := cql_facet_find(test_facets, printf('cql_schema_v%d', _v));
END;

-- helper proc for setting the schema version CRC for a version index
PROC test_cql_set_version_crc(_v INT!, crc LONG!)
BEGIN
  INSERT OR REPLACE INTO test_cql_schema_facets (facet, version)
       VALUES('cql_schema_v'||_v, _crc);
END;
```
As you can see, these procedures are effectively specializations of
`cql_get_facet_version` and `cql_set_facet_version` where the facet name
is computed from the int.

Triggers require some special processing.  There are so-called "legacy"
triggers that crept into the system.  These begin with `tr__` and they
do not have proper tombstones.  In fact some are from early versions
of CQL before they were properly tracked.  To fix any old databases
that have these in them, we delete all triggers that start with `tr__`.

>NOTE: we have to use the `GLOB` operator to do this, because `_` is the
>`LIKE` wildcard.

```sql
-- helper proc to reset any triggers that are on the old plan --
DECLARE PROCEDURE cql_exec_internal(sql TEXT!) USING TRANSACTION;

PROC test_cql_drop_legacy_triggers()
BEGIN
  CURSOR C FOR SELECT name from sqlite_master
     WHERE type = 'trigger' AND name GLOB 'tr__*';
  LOOP FETCH C
  BEGIN
    call cql_exec_internal(printf('DROP TRIGGER %s;', C.name));
  END;
END;
```

#### Baseline Schema

The 'baseline' or 'v0' schema is unannotated (no `@create` or
`@recreate`).    The first real schema management procedures are for
creating and dropping these tables.

```sql
PROC test_cql_install_baseline_schema()
BEGIN
  CREATE TABLE foo(
    id INT!,
    rate LONG_INT,
    rate_2 LONG_INT
  );

  CREATE TABLE table2(
    id INT!
  );

END;
```

```sql
-- helper proc for dropping baseline tables before installing the baseline schema
PROC test_cql_drop_baseline_tables()
BEGIN
  DROP TABLE IF EXISTS foo;
  DROP TABLE IF EXISTS table2;
END;
```

#### Migration Procedures

The next section declares the migration procedures that were in the
schema.  These are expected to be defined elsewhere.

```sql
-- declared upgrade procedures if any
DECLARE proc CreateName1Proc() USING TRANSACTION;
DECLARE proc CreateName2Proc() USING TRANSACTION;
DECLARE proc CreateId2Proc() USING TRANSACTION;
DECLARE proc DeleteRate2Proc() USING TRANSACTION;
```
The code below will refer to these migration procedures.  We emit a
declaration so that we can use the names in context.

>NOTE: `USING TRANSACTION` when applied to a proc declaration simply
>means the proc will access the database so it needs to be provided with a
>`sqlite3 *db` parameter.


#### Views
```sql
-- drop all the views we know
PROC test_cql_drop_all_views()
BEGIN
  DROP VIEW IF EXISTS live_view;
  DROP VIEW IF EXISTS another_live_view;
  DROP VIEW IF EXISTS dead_view;
END;

-- create all the views we know
PROC test_cql_create_all_views()
BEGIN
  CREATE VIEW live_view AS
  SELECT *
    FROM foo;
  CREATE VIEW another_live_view AS
  SELECT *
    FROM foo;
END;
```
View migration is done by dropping all views and putting all views back.

>NOTE: `dead_view` was not created, but we did try to drop it if it existed.

#### Indices

```sql
-- drop all the indices that are deleted or changing
PROC test_cql_drop_all_indices()
BEGIN
  IF cql_facet_find(test_facets, 'index_still_present_index_crc') != -6823087563145941851 THEN
    DROP INDEX IF EXISTS index_still_present;
  END IF;
  DROP INDEX IF EXISTS index_going_away;
END;

-- create all the indices we need
PROC test_cql_create_indices()
BEGIN
  IF cql_facet_find(test_facets, 'index_still_present_index_crc') != -6823087563145941851 THEN
    CREATE INDEX index_still_present ON table2 (name1, name2);
    CALL test_cql_set_facet_version('index_still_present_index_crc', -6823087563145941851);
  END IF;
END;

```
Indices are processed similarly to views, however we do not want to drop indices that are not changing.  Therefore we compute the CRC of the index definition.  At the start of the script any indices that are condemned (e.g. `index_going_away`) are dropped as well as any that have a new CRC. At the end of migration, changed or new indices are (re)created using `cql_create_indices`.

#### Triggers

```sql
- drop all the triggers we know
PROC test_cql_drop_all_triggers()
BEGIN
  CALL test_cql_drop_legacy_triggers();
  DROP TRIGGER IF EXISTS trigger_one;
END;

-- create all the triggers we know
PROC test_cql_create_all_triggers()
BEGIN
  CREATE TRIGGER trigger_one
    AFTER INSERT ON foo
  BEGIN
  DELETE FROM table2 WHERE table2.id = new.id;
  END;
END;
```

Triggers are always dropped before migration begins and are re-instated quite late in the processing
as we will see below.

#### Caching the state of the facets

To avoid selecting single rows out of the facets table repeatedly we introduce this procedure
whose job is to harvest the facets table and store it in a dictionary.  The helpers that do this
were declared above.  You've already seen usage of the facets in the
code above.

```sql
PROC test_setup_facets()
BEGIN
  TRY
    SET test_facets := cql_facets_new();
    CURSOR C FOR SELECT * from test_cql_schema_facets;
    LOOP FETCH C
    BEGIN
      LET added := cql_facet_add(test_facets, C.facet, C.version);
    END;
  CATCH
    -- if table doesn't exist we just have empty facets, that's ok
  END;
END;
```

#### Main Migration Script

The main script orchestrates everything.  There are inline comments for
all of it.  The general order of events is:

* create schema facets table if needed
* check main schema crc; if it matches we're done here, otherwise continue...

These operations are done in `test_perform_needed_upgrades`
* drop all views
* drop condemned indices
* fetch the current schema version
* if version 0 then install the baseline schema (see below)
* for each schema version with changes do the following:
  * create any tables that need to be created in this version
  * add any columns that need to be added in this version
  * run migration procs in this order:
    * create table
    * create column
    * delete trigger
    * delete view
    * delete index
    * delete column
    * delete table
  * drop any tables that need to be dropped in this version
  * mark schema upgraded to the current version so far, and proceed to the next version
  * each partial step is also marked as completed so that it can be skipped if the script is run again
* create all the views
* (re)create any indices that changed and are not dead
* set the schema CRC to the current CRC

That's it... the details are below.

```sql
PROC test_perform_upgrade_steps()
BEGIN
  DECLARE column_exists BOOL!;
  VAR schema_version LONG!;
    -- dropping all views --
    CALL test_cql_drop_all_views();

    -- dropping condemned or changing indices --
    CALL test_cql_drop_all_indices();

    -- dropping condemned or changing triggers --
    CALL test_cql_drop_all_triggers();

    ---- install baseline schema if needed ----

    CALL test_cql_get_version_crc(0, schema_version);
    IF schema_version != -9177754326374570163 THEN
      CALL test_cql_install_baseline_schema();
      CALL test_cql_set_version_crc(0, -9177754326374570163);
    END IF;

    ---- upgrade to schema version 2 ----

    CALL test_cql_get_version_crc(2, schema_version);
    IF schema_version != -6840158498294659234 THEN
      -- altering table table2 to add column name1 TEXT;

      CALL test_check_column_exists('table2', '*[( ]name1 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE table2 ADD COLUMN name1 TEXT;
      END IF;

      -- altering table table2 to add column name2 TEXT;

      CALL test_check_column_exists('table2', '*[( ]name2 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE table2 ADD COLUMN name2 TEXT;
      END IF;

      -- altering table table2 to add column name3 TEXT;

      CALL test_check_column_exists('table2', '*[( ]name3 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE table2 ADD COLUMN name3 TEXT;
      END IF;

      -- altering table table2 to add column name4 TEXT;

      CALL test_check_column_exists('table2', '*[( ]name4 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE table2 ADD COLUMN name4 TEXT;
      END IF;

      -- data migration procedures
      IF cql_facet_find(test_facets, 'CreateName1Proc') = -1 THEN
        CALL CreateName1Proc();
        CALL test_cql_set_facet_version('CreateName1Proc', 2);
      END IF;
      IF cql_facet_find(test_facets, 'CreateName2Proc') = -1 THEN
        CALL CreateName2Proc();
        CALL test_cql_set_facet_version('CreateName2Proc', 2);
      END IF;

      CALL test_cql_set_version_crc(2, -6840158498294659234);
    END IF;

    ---- upgrade to schema version 3 ----

    CALL test_cql_get_version_crc(3, schema_version);
    IF schema_version != -4851321700834943637 THEN
      -- creating table added_table

      CREATE TABLE IF NOT EXISTS added_table(
        id INT!,
        name1 TEXT
      );

      CALL test_cql_set_version_crc(3, -4851321700834943637);
    END IF;

    ---- upgrade to schema version 4 ----

    CALL test_cql_get_version_crc(4, schema_version);
    IF schema_version != -6096284368832554520 THEN
      -- altering table added_table to add column name2 TEXT;

      CALL test_check_column_exists('added_table', '*[( ]name2 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE added_table ADD COLUMN name2 TEXT;
      END IF;

      -- altering table foo to add column id2 INTEGER;

      CALL test_check_column_exists('foo', '*[( ]id2 INTEGER*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE foo ADD COLUMN id2 INTEGER DEFAULT 12345;
      END IF;

      -- logical delete of column rate_2 from foo; -- no ddl

      -- data migration procedures
      IF cql_facet_find(test_facets, 'CreateId2Proc') = -1 THEN
        CALL CreateId2Proc();
        CALL test_cql_set_facet_version('CreateId2Proc', 4);
      END IF;
      IF cql_facet_find(test_facets, 'DeleteRate2Proc') = -1 THEN
        CALL DeleteRate2Proc();
        CALL test_cql_set_facet_version('DeleteRate2Proc', 4);
      END IF;

      CALL test_cql_set_version_crc(4, -6096284368832554520);
    END IF;

    ---- upgrade to schema version 5 ----

    CALL test_cql_get_version_crc(5, schema_version);
    IF schema_version != 5720357430811880771 THEN
      -- altering table foo to add column name TEXT;

      CALL test_check_column_exists('foo', '*[( ]name TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE foo ADD COLUMN name TEXT;
      END IF;

      -- logical delete of column rate from foo; -- no ddl

      -- dropping table added_table

      DROP TABLE IF EXISTS added_table;

      CALL test_cql_set_version_crc(5, 5720357430811880771);
    END IF;

    ---- upgrade to schema version 6 ----

    CALL test_cql_get_version_crc(6, schema_version);
    IF schema_version != 3572608284749506390 THEN
      -- altering table foo to add column name_2 TEXT;

      CALL test_check_column_exists('foo', '*[( ]name_2 TEXT*', column_exists);
      IF NOT column_exists THEN
        ALTER TABLE foo ADD COLUMN name_2 TEXT;
      END IF;

      CALL test_cql_set_version_crc(6, 3572608284749506390);
    END IF;

    CALL test_cql_create_all_views();
    CALL test_cql_create_all_indices();
    CALL test_cql_create_all_triggers();
    CALL test_cql_set_facet_version('cql_schema_version', 6);
    CALL test_cql_set_facet_version('cql_schema_crc', -7714030317354747478);
END;
```

We have one more helper that will look for evidence that we're trying
to move backwards to a previous schema version.  This is not supported.
This procedure also arranges for the original facet versions to be saved
and it proceduces a difference in facets after the upgrade is done.

```sql
PROC test_perform_needed_upgrades()
BEGIN
  -- check for downgrade --
  IF cql_facet_find(test_facets, 'cql_schema_version') > 6 THEN
    SELECT 'downgrade detected' facet;
  ELSE
    -- save the current facets so we can diff them later --
    CALL test_save_cql_schema_facets();
    CALL test_perform_upgrade_steps();

    -- finally produce the list of differences
    SELECT T1.facet FROM
      test_cql_schema_facets T1
      LEFT OUTER JOIN test_cql_schema_facets_saved T2
        ON T1.facet = T2.facet
      WHERE T1.version is not T2.version;
  END IF;
END;
```

This is the main function for upgrades, it checks only the master schema version.
This function is separate so that the normal startup path doesn't have to have
the code for the full upgrade case in it.  This lets linker order files do a superior job
(since full upgrade is the rare case).

```sql
PROC test()
BEGIN
  DECLARE schema_crc LONG!;

  -- create schema facets information table --
  CALL test_create_cql_schema_facets_if_needed();

  -- fetch the last known schema crc, if it's different do the upgrade --
  CALL test_cql_get_facet_version('cql_schema_crc', schema_crc);

  IF schema_crc <> -7714030317354747478 THEN
    TRY
      CALL test_setup_facets();
      CALL test_perform_needed_upgrades();
    CATCH
      CALL cql_facets_delete(test_facets);
      SET test_facets := 0;
      THROW;
    END;
    CALL cql_facets_delete(test_facets);
    SET test_facets := 0;
  ELSE
    -- some canonical result for no differences --
    SELECT 'no differences' facet;
  END IF;
END;
```

#### Temp Tables
We had no temporary tables in this schema, but if there were some they get added
to the schema after the upgrade check.

A procedure like this one is generated:

```sql
PROC test_cql_install_temp_schema()
BEGIN
  CREATE TEMP TABLE tempy(
    id INT
  );
END;
```

This entry point can be used any time you need the temp tables.  But normally it is
automatically invoked.

```sql
  ---- install temp schema after upgrade is complete ----
  CALL test_cql_install_temp_schema();
```

That logic is emitted at the end of the test procedure.

### Schema Regions

Schema Regions are designed to let you declare your schema in logical
regions whose dependencies are specified.  It enforces the dependencies
you specify creating errors if you attempt to break the declared rules.
Schema regions allow you to generate upgrade scripts for parts of your
schema that can compose and be guaranteed to remain self-consistent.

#### Details

In many cases schema can be factored into logical and independent islands.
This is desireable for a number of reasons:

* so that the schema can go into different databases
* so that the schema can be upgraded on a different schedule
* so that "not relevant" schema can be omitted from distributions
* so that parts of your schema that have no business knowing about each other can be prevented from taking dependencies on each other

These all have very real applications:

##### E.g. Your Application has an on-disk and an in-memory database

This creates basically three schema regions:

1. on disk: which cannot refer to the in-memory at all
2. in-memory: which cannot refer to the on-disk schema at all
3. cross-db: which refers to both, also in memory (optional)

##### Your Application Needs To Upgrade Each of the Above

There must be a separate upgrade script for both the island databases
and yet a different one for the "cross-db" database

##### Your Customer Doesn't Want The Kitchen Sink of Schema

If you're making a library with database support, your customers likely
want to be able to create databases that have only features they want;
you will want logical parts within your schema that can be separated
for cleanliness and distribution.

#### Declaring Regions and Dependencies

Schema Regions let you create logical groupings, you simply declare
the regions you want and then start putting things into those regions.
The regions form a directed acyclic graph -- just like C++ base classes.
You create regions like this:

```sql
@declare_schema_region root;

@declare_schema_region extra using root;
```

The above simply declares the regions -- it doesn't put anything into
them.  In this case we now have a `root` region and an `extra` region.
The `root` schema items will not be allowed to refer to anything in
`extra`.

Without regions, you could also ensure that the above is true by putting
all the `extra` items afer the `root` in the input file but things
can get more complicated than that in general, and the schema might
also be in several files, complicating ordering as the option.  Also,
relying on order could be problematic as it is quite easy to put things
in the wrong place (e.g. add a new `root` item after the `extra` items).
Making this a bit more complicated, we could have:


```sql
@declare_schema_region feature1 using extra;
@declare_schema_region feature2 using extra;
@declare_schema_region everything using feature1, feature2;
```

And now there are many paths to `root` from the `everything` region;
that's ok but certainly it will be tricky to do all that with ordering.

#### Using Regions

An illustrative example, using the regions defined above:

```sql
@begin_schema_region root;

create table main(
  id int,
  name text
);

create view names as select name from main order by name;

@end_schema_region;

@begin_schema_region extra;

create table details(
   id int references main(id),
   details text
);

create proc get_detail(id_ integer)
begin
  select T1.id, T1.details, T2.name from details T1
  inner join main T2 on T1.id = T2.id
  where T1.id = id_;
end;

@end_schema_region;

@begin_schema_region feature1;

create table f1(
   id int references details(id),
   f1_info text
);

create proc get_detail(id_ integer)
begin
  select T1.id, T1.details, T2.name, f1_info from details T1
  inner join f T2 on T1.id = T2.id
  inner join f1 on f1.id = T1.id
  where T1.id = id_;
end;

@end_schema_region;

@begin_schema_region feature2;
  -- you can use details, and main but not f1
@end_schema_region;
```

With the structure above specified, even if a new contribution to the
`root` schema appears later, the rules enforce that this region cannot
refer to anything other than things in `root`.  This can be very important
if schema is being included via `@include` and might get pulled into
the compilation in various orders.  A feature area might also have a
named public region that others things can depend on (e.g. some views)
and private regions (e.g. some tables, or whatever).

#### Region Visibility

Schema regions do not provide additional name spaces -- the names of
objects should be unique across all regions. In other words, regions do
not hide or scope entity names; rather they create errors if inappropriate
names are used.

Case 1: The second line will fail semantic validation because table `A` already exists

```sql
-- obvious standard name conflict
create table A (id int);
create table A (id int, name text);
```

Case 2: This fails for the same reason as case #1. Table `A` already exists

```sql
@declare_region root;
-- table A is in no region
create table A (id int);
@begin_region root:
-- this table A is in the root region, still an error
create table A (id int, name text);
@end_region;
```

Case 3: Again fails for the same reason as case #1. Table `A` already
exist in region `extra`, and you cannot define another table with the
same name in another region.

```sql
@declare_region root;
@declare_region extra;

@begin_region extra;
-- so far so good
create table A (id int);
@end_region;

@begin_region root;
-- no joy, this A conflicts with the previous A
create table A (id int, name text);
@end_region;
```

Really the visibility rules couldn't be anything other than the above, as SQLite has
no knowledge of regions at all and so any exotic name resolution would just doom SQLite
statements to fail when they finally run.

##### Exception for `"... LIKE <table>"` statement

The rules above are enforced for all constructs except for where the
syntactic sugar `... LIKE <table>` forms, which can happen in a variety of
statements. This form doesn't create a dependence on the table (but does
create a dependence on its shape). When CQL generates output, the `LIKE`
construct is replaced with the actual names of the columns it refers to.
But these are independent columns, so this is simply a keystroke saver.
The table (or view, cursor, etc.) reference will be gone in any output SQL
so this isn't a real dependency on the existence of the mentioned table or
shape at run time.

The cases below will succeed.

```sql
@declare_region root;

create table A (...);
create view B (....);
create procedure C {...}

@begin_region root;
create table AA(LIKE A);
create table BB(LIKE B);
create table CC(LIKE C);
@end_region;
```
>NOTE: this exception may end up causing maintenance problems and so it might be revisited in the future.

#### Maintaining Schema in Pieces

When creating upgrade scripts, using the `--rt schema_upgrade` flags you
can add region options `--include_regions a b c` and `--exclude_regions d e f`
per the following:

Included regions:

* must be valid region names -- the base types are walked to compute all the regions that are "in"
* declarations are emitted in the upgrade for all of the "in" objects -- "exclude" does not affect the declarations

Excluded regions:

* must be valid region names and indicate parts of schema that are upgraded elsewhere, perhaps with a seperate CQL run, a different automatic upgrade, or even a manual mechanism
* upgrade code will be generated for all the included schema, but not for the excluded regions and their contents

Example: Referring to the regions above you might do something like this

```bash

# All of these also need a --global_proc param for the entry point but that's not relevant here
cql --in schema.sql --cg shared.sql --rt schema_upgrade  --include_regions extra
cql --in schema.sql --cg f1.cql --rt schema_upgrade --include_regions feature1 --exclude_regions extra
cql --in schema.sql --cg f2.cql --rt schema_upgrade --include_regions feature2 --exclude_regions extra
```

The first command generates all the shared schema for regions `root`
and `extra` because `extra` contains `root`

The second command declares all of `root` and `extra` so that the
`feature1` things can refer to them, however the upgrade code for these
shared regions is not emitted.  Only the upgrade for schema in `feature1`
is emitted.  `feature2` is completely absent.  This will be ok because
we know `feature1` cannot depend on `feature2` and `extra` is assumed
to be upgraded elsewhere (such as in the previous line).

The third command declares all of `root` and `extra` so that the
`feature2` things can refer to them, however the upgrade code for these
shared regions is not emitted.  Only the upgrade for schema in `feature2`
is emitted.  `feature1` is completely absent.

>NOTE: in the above examples, CQL is generating more CQL to be compiled
>again (a common pattern).  The CQL upgrade scripts need to be compiled as
>usual to produce executable code.  Thus the output of this form includes
>the schema declarations and executable DDL.


##### Schema Not In Any Region

For schema that is not in any region you might imagine that it is a
special region `<none>` that depends on everything.  So basically you
can put anything there.  Schema that is in any region cannot ever refer
to schema that is in `<none>`.

When upgrading, if any include regions are specified then `<none>` will
not be emitted at all.  If you want an upgrader for just `<none>` this
is possible with an assortment of exclusions.  You can always create
arbitrary grouping regions to make this easier. A region named `any`
that uses all other regions would make this simple.

In general, best practice is that there is no schema in `<none>`, but
since most SQL code has no regions some sensible meaning has to be given
to DDL before it gets region encodings.

#### Deployable Regions

Given the above we note that some schema regions correspond to the way
that we will deploy the schema.  We want those bundles to be safe to
deploy but to in order to be so we need a new notion -- a deployable
region.  To make this possible CQL includes the following:

* You can declare a region as deployable using `@declare_deployable_region`
* CQL computes the covering of a deployable region: its transitive closure up to but not including any deployable regions it references
* No region is allowed to depend on a region that is within the interior of a different deployable region, but you can depend on the deployable region itself

Because of the above, each deployable region is in fact a well defined
root for the regions it contains.  The deployable region becomes the
canonical way in which a bundle of regions (and their content) is deployed
and any given schema item can be in only one deployable region.

##### Motivation and Examples

As we saw above, regions are logical groupings of tables/views/etc such
that if an entity is in some region `R` then it is allowed to only refer
to the things that `R` declared as dependencies `D1`, `D2`, etc. and their
transitive closures.  You can make as many logical regions as you like and
you can make them as razor thin as you like; they have no physical reality
but they let you make as many logical groups of things as you might want.

Additionally, when we’re deploying schema you generally need to do
it in several pieces. E.g. if we have tables that go in an in-memory
database then defining a region that holds all the in-memory tables
makes it easy to, say, put all those in-memory tables into a particular
deployment script.

Now we come to the reason for deployable regions. From CQL’s
perspective, all regions are simply logical groups; some grouping
is then meaningful to programmers but has no physical reality. This
means you’re free to reorganize tables etc. as you see fit into new
or different regions when things should move. Only, that’s not quite
true. The fact that we deploy our schema in certain ways means while most
logical moves are totally fine, if you were to move a table from, say,
the main database region to the in-memory region you would be causing
a major problem.  Some installations may already have the table in the
main area and there would be nothing left in the schema to tell CQL to
drop the table from the main database -- the best you can hope for is
the new location gets a copy of the table the old location keeps it and
now there are name conflicts forever.

So, the crux of the problem is this: We want to let you move schema freely
between logical regions in whatever way makes sense to you, but once
you pick the region you are going to deploy in, you cannot change that.

To accomplish this, CQL needs to know that some of the regions are
deployable regions and there have to be rules to make it all makes sense.
Importantly, every region has to be contained in at most one deployable
region.

Since the regions form a DAG we must create an error if any region could
ever roll up to two different deployable regions. The easiest way to
describe this rule is “no peeking” – the contents of a deployable
region are “private” they can refer to each other in any DAG shape
but outside of the deployable region you can only refer to its root. So
you can still compose them but each deployable region owns a well-defined
covering. Note that you can make as many fine-grained deployable regions
as you want; you don’t actually have to deploy them separately, but
you get stronger rules about the sharing when you do.

Here’s an example:

```
Master Deployment 1
  Feature 1 (Deployable)
    logical regions for feature 1
    Core (Deployable)
      logical regions for core
  Feature 2 (Deployable)
    logical regions for feature 2
    Core
      ...

Master Deployment 2
  Feature 1 (Deployable)
    ...

  Feature 3 (Deployable)
    logical regions for feature 3
```

In the above:

* none of the logical regions for feature 1, 2, 3 are allowed to refer to logical regions in any other feature, though any of them could refer to Core (but not directly to what is inside Core)
* within those regions you can make any set of groupings that makes sense and you can change them over time as you see fit, with some restrictions
* any such regions are not allowed to move to a different Feature group (because those are deployment regions)
* the Master Deployment regions just group features in ways we’d like to deploy them; in this case there are two deployments: one that includes Feature 1 & 2 and another that includes Feature 1 & 3
* the deployable region boundaries are preventing Feature 1 regions from using Feature 2 regions in an ad hoc way (i.e. you can't cheat by taking a direct dependency on something inside a different feature), but both Features can use Core
* Feature 3 doesn’t use Core but Core will still be in Master Deployment 2 due to Feature 1

>NOTE: deployable regions for Feature 1, 2, and 3 aren't actually
>deployed alone, but they are adding enforcement that makes the features
>cleaner

Because of how upgrades work, “Core” could have its own upgrader. Then
when you create the upgrader for Master Deployment 1 and 2, you can
specify “exclude Core” in which case those tables are assumed to be
updated independently. You could create as many or as few independently
upgrade-able things with this pattern. Because regions are not allowed to
"peek" inside of a deployable region, you can reorganize your logical
regions without breaking other parts of the schema.

#### Private Regions

The above constructs create a good basis for creating and composing
regions, but a key missing aspect is the ability to hide internal details
in the logical groups.  This becomes increasingly important as your
desire to modularize schema grows; you will want to have certain parts
that can change without worrying about breaking others and without fear
that there are foreign keys and so forth referring to them.

To accomplish this, CQL provides the ability to compose schema regions
with the optional `private` keyword.  In the following example there
will be three regions creatively named `r1`, `r2`, and `r3`.  Region `r2`
consumes `r1` privately and therefore `r3` is not allowed to use things in
`r1` even though it consumes `r2`.  When creating an upgrade script for
`r3` you will still need (and will get) all of `r2` and `r1`, but from
a visibility perspective `r3` can only directly depend on `r2`.

```sql
@declare_schema_region r1;
@declare_schema_region r2 using r1 private;
@declare_schema_region r3 using r2;

@begin_schema_region r1;
create table r1_table(id int primary key);
@end_schema_region;

@begin_schema_region r2;
create table r2_table(id int primary key references r1_table(id));
@end_schema_region;

@begin_schema_region r3;

-- this is OK
create table r3_table_2(id int primary key references r2_table(id));

-- this is an error, no peeking into r1
create table r3_table_1(id int primary key references r1_table(id));

@end_schema_region;
```

As expected `r2` is still allowed to use `r1` because your private
regions are not private from yourself.  So you may think it’s easy to
work around this privacy by simply declaring a direct dependency on r1
wherever you need it.

```
@declare_schema_region my_sneaky_region using r1, other_stuff_I_need;
```

That would seem to make it all moot.  However, this is where deployable
regions come in.  Once you bundle your logical regions in a deployable
region there’s no more peeking inside the the deployable region.
So we could strengthen the above to:

```
@declare_deployable_region r2 using r1 private;
```

Once this is done it becomes an error to try to make new regions that
peek into `r2`; you have to take all of `r2` or none of it -- and you
can’t see the private parts.  Of course you can do region wrapping
at any level so you can have as many subgroups as you like, whatever
is useful. You can even add additional deployable regions that aren’t
actually deployed to get the "hardened" grouping at no cost.

So, in summary, to get true privacy, first make whatever logical
regions you like that are helpful.  Put privacy where you need/want it.
Import logical regions as much as you want in your own bundle of regions.
Then wrap that bundle up in a deployable region (they nest) and then
your private regions are safe from unwanted usage.


### Unsubscription and Resubscription Features

Any significant library that is centered around a database is likely to
accrue significant amounts of schema to support its features.  Often users
of the library don’t want all its features and therefore don’t want
all of its schema.  CQL’s primary strategy is to allow the library
author to divide the schema into regions and then the consumer of the
library  may generate a suitable schema deployer that deploys only the
desired regions.  You simply subscribe to the regions you want.

The `@unsub` construct deals with the unfortunate situation of
over-subscription.  In the event that a customer has subscribed to
regions that it turns out they don’t need, or if indeed the regions
are not fine-grained enough, they may wish to (possibly much later)
unsubscribe from particular tables or entire regions that they previously
had included.

Unfortunately it’s not so trivial as to simply remove the regions
after the fact. The problem is that there might be billions of devices
that already have the undesired tables and are paying the initialization
costs for them.  Affirmatively removing the tables is highly desirable
and that means a forward-looking annotation is necessary to tell the
upgrader to generate `DROP` statements at some point.  Furthermore,
a customer  might decide at some point later that now is the time they
need the schema in question, so resubcription also has to be possible.

#### Unsubscription and Resubscription

To accomplish this we add the following construct:

```sql
@unsub(table_name);
```

The effects of a valid `@unsub` are as follows:

* The table is no longer accessible by statements
* If the table is marked `@create`, then “DROP IF EXISTS table_name” is emitted into the upgrade steps for _version_number_
* If the table is `@recreate` the table is unconditionally dropped as though it had been deleted
* The JSON includes the unsub details in a new subscriptions section

The compiler ensures that the directives are valid and stay valid.

#### Validations for @unsub(_table_):

* _table_ must be a valid table name
* _table_ must not be already unsubscribed
* If _table_ must not be marked with `@delete`
  * unsubscribing from a table after it’s been outright deleted is clearly a mistake
* For every child table -- those that mention this table using `REFERENCES`
  * The child must be already deleted or unsubscribed
  * The deletion or unsubscription must have happened at a version <= _version_
* _table_ is marked unsubscribed for purposes of further analysis

>CAUTION: The legacy `@resub` directive is now an error;  Resubscription
>is accomplished by simply removing the relevant `@unsub` directive(s).

#### Previous Schema validations for @unsub

Unsubscriptions may be removed when they are no longer desired in order
to resubscribe as long as this results in a valid chain of foreign keys.

These validations are sufficient to guarantee a constistent logical
history for unsubscriptions.
