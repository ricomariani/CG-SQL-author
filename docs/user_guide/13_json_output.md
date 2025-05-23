---
title: "Chapter 13: JSON Output"
weight: 13
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

To help facilitate additional tools that might want to depend on CQL
input files further down the toolchain, CQL includes a JSON output format
for SQL DDL as well as stored procedure information, including special
information for a single-statement DML.  "Single-statement DML" refers
to those stored procedures that consist of a single `insert`, `select`,
`update`, or `delete`.   Even though such procedures comprise just one
statement, good argument binding can create very powerful DML fragments
that are re-usable.  Many CQL stored procedures are of this form (in
practice maybe 95% are just one statement.)

To use CQL in this fashion, the sequence will be something like the
below.  See [Appendix 1](./appendices/01_command_lines_options.md) for command
line details.

```bash
cql --in input.sql --rt json_schema --cg out.json
```

The output contains many different sections for the various
types of entities that CQL can process.  There is a full
description of the possible outputs available in [diagram
form](https://ricomariani.github.io/CG-SQL-author/json_grammar.railroad.html)

In the balance of this chapter we'll deal with the contents of the
sections and their meaning rather than the specifics of the format,
which are better described with the grammar above.

### Tables

The "tables" section has zero or more tables, each table is comprised of these fields:

* **name** : the table name
* **crc** : the schema CRC for the entire table definition, including columns and constraints
* **isTemp** : true if this is a temporary table
* **ifNotExists** : true if the table was created with "if not exists"
* **withoutRowid** : true if the table was created using "without rowid"
* **isAdded** : true if the table has an @create directive
  * **addedVersion** : optional, the schema version number in the @create directive
* **isDeleted** : true if the table was marked with @delete or is currently _unsubscribed_
  * **deletedVersion** : optional, the schema version number in the @delete directive
* **isRecreated** : true if the table is marked with @recreate
  * **recreateGroupName** : optional, if the @recreate attribute specifies a group name, it is present here
* **unsubscribedVersion** : optional, if the table was last unsubscribed, the version number when this happened
* **resubscribedVersion** : optional, if the table was last resubscribed, the version number when this happened
* **_region information_** : optional, see the section on Region Info
* **indices** : optional, a list of the names of the indices on this table, see the [indices section](#indices)
* **_attributes_** : optional, see the section on attributes, they appear in many places
* **_columns_** : an array of column definitions, see the section on columns
* **primaryKey** : a list of column names, possibly empty if no primary key
* **primaryKeySortOrders** : a list of corresponding sort orders, possibly empty, for each column of the primary key if specified
* **primaryKeyName** : optional, the name of the primary key, if it has one
* **_foreignKeys_** : a list of foreign keys for this table, possibly empty, see the [foreign keys section](#foreign-keys)
* **_uniqueKeys_** : a list of unique keys for this table, possibly empty, see the [unique keys section](#unique-keys)
* **_checkExpressions_** : a list of check expressions for this table, possibly empty, see the [check expression section](#check-expressions)

Example:

```sql
@attribute(an_attribute=(1,('foo', 'bar')))
CREATE TABLE foo(
  id INTEGER,
  name TEXT
);
```

generates:

```json
    {
      "name" : "foo",
      "CRC" : "-1869326768060696459",
      "isTemp" : 0,
      "ifNotExists" : 0,
      "withoutRowid" : 0,
      "isAdded" : 0,
      "isDeleted" : 0,
      "isRecreated": 0,
      "indices" : [ "foo_name" ],
      "attributes" : [
        {
          "name" : "an_attribute",
          "value" : [1, ["foo", "bar"]]
        }
      ],
      "columns" : [
        {
          "name" : "id",
          "type" : "integer",
          "isNotNull" : 0,
          "isAdded" : 0,
          "isDeleted" : 0,
          "isPrimaryKey" : 0,
          "isUniqueKey" : 0,
          "isAutoIncrement" : 0
        },
        {
          "name" : "name",
          "type" : "text",
          "isNotNull" : 0,
          "isAdded" : 0,
          "isDeleted" : 0,
          "isPrimaryKey" : 0,
          "isUniqueKey" : 0,
          "isAutoIncrement" : 0
        }
      ],
      "primaryKey" : [  ],
      "primaryKeySortOrders" : [  ],
      "foreignKeys" : [
      ],
      "uniqueKeys" : [
      ],
      "checkExpressions" : [
      ]
    }
```

### Region Information

Region Information can appear on many entities, it consists of two
optional elements:

* **region** : optional, the name of the region in which the entity was defined
* **deployedInRegion** : optional, the deployment region in which that region is located

### Attributes

Miscellaneous attributes can be present on virtual every kind of entity.
They are optional.  The root node introduces the attributes:

* **attributes** : a list at least one attribute

Each attribute is a name and value pair:

* **name** : any string
  * attribute names are often compound like "cql:shared_fragment"
  * they are otherwise simple identifiers
  * if the ``[[attribute]]`` form is used, it is expanded into the normal `cql:attribute` form in the output
* **value** : any _attribute value_

Each _attribute value_ can be:

* any literal
* an array of _attribute values_

Since the _attribute values_ can nest it's possible to represent
arbitrarily complex data types in an attribute.

### Global attributes

While the most common use case for attributes is to be attached to
other entities (e.g., tables, columns), CQL also lets you define
"global" attributes, which are included in the top level `attributes`
section of the JSON output. To specify global attributes you declare a
variable of type `object` ending with the suffix `database` and attach
attributes to it. CQL will merge together all the attributes from all
the variables ending with `database` and place them in the `attributes`
section of the JSON output.

Global attributes give you a way to add global configuration information
into the CQL JSON output. You can, for instance, include these attributes
in some root file that you `@include` in the rest of your CQL code,
and by doing this, these attributes will be visible in any generated
JSON for those files.

Example:

```sql
@attribute(attribute_1 = "value_1")
@attribute(attribute_2 = "value_2")
declare database object;

@attribute(attribute_3 = "value_3")
declare some_other_database object;
```

Generates:

```json
    {
      "attributes": [
        {
          "name": "attribute_1",
          "value": "value_1"
        },
        {
          "name": "attribute_2",
          "value": "value_2"
        },
        {
          "name": "attribute_3",
          "value": "value_3"
        }
      ]
    }
```

### Foreign Keys

Foreign keys appear only in tables, the list of keys contains zero or
more entries of this form:

* **name** : optional, the name of the foreign key if specified
* **columns** : the names of the constrained columns in the current table (the "child" table)
* **referenceTable** : the name of the table that came after REFERENCES in the foreign key
* **referenceColumns** : the constraining columns in the referenced table
* **onUpdate** : the ON UPDATE action (e.g. "CASCADE", "NO ACTION", etc.)
* **onDelete** : the ON DELETE action (e.g. "CASCADE", "NO ACTION", etc.)
* **isDeferred** : boolean, indicating the deferred or not deferred setting for this foreign key

### Unique Keys

Unique keys appear only in tables, the list of keys contains zero or
more entries of this form:

* **name**: optional, the name of the unique key if specified
* **columns**: a list of 1 or more constrained column names
* **sortOrders**: a list of corresponding sort orders for the columns


### Check Expressions

Check Expressions appear only in tables, the list of keys contains zero
or more entries of this form:

* **name** : optional, the name of the unique key if specified
* **checkExpr** : the check expression in plain text
* **checkExprArgs**: an array of zero or more local variables that should be bound to the `?` items in the check expression

The checkExprArgs will almost certainly be the empty list `[]`.  In the exceedingly rare situation that the table
in question was defined in a procedure and some of parts of the check expression were arguments to that procedure
then the check expression is not fully known until that procedure runs and some of its literals will be decided
at run time.  This is an extraordinary choice but technically possible.


### Columns

Columns are themselves rather complex, there are 1 or more of them in
each table.  The table will have
a list of records of this form:

* **name** : the name of the columns
* **_attributes_** : optional, see the [section on attributes](#attributes), they appear in many places
* **type** : the column type (e.g. bool, real, text, etc.)
* **kind** : optional, if the type is qualified by a discriminator such as int<task_id> it appears here
* **isSensitive** : optional, indicates a column that holds sensitive information such as PII
* **isNotNull** : true if the column is not null
* **isAdded** : true if the column has an @create directive
  * **addedVersion** : optional, the schema version number in the @create directive
* **isDeleted** : true if the column was marked with @delete
  * **deletedVersion** : optional, the schema version number in the @delete directive
* **defaultValue** : optional, can be any literal, the default value of the column
* **collate** : optional, the collation string (e.g. nocase)
* **checkExpr** : optional, the _check expression_ for this column (see the related section)
* **isPrimaryKey** : true if the column was marked with PRIMARY KEY
* **isUniqueKey** : true if the column was marked with UNIQUE
* **isAutoIncrement** : true if the column was marked with AUTOINCREMENT


### Virtual Tables

The "virtualTables" section is very similar to the "tables" section with
zero or more virtual table entries.

Virtual table entries are the same as table entries with the following additions:

* **module** : the name of the module that manages this virtual table
* **isEponymous** : true if the virtual table was declared eponymous
* **isVirtual** : always true for virtual tables

The JSON schema for these items was designed to be as similar as possible
so that typically the same code can handle both with possibly a few
extra tests of the isVirtual field.


### Views

The views section contains the list of all views in the schema, it is
zero or more view entires of this form.

* **name** : the view name
* **crc** : the schema CRC for the entire view definition
* **isTemp** : true if this is a temporary view
* **isDeleted** : true if the view was marked with @delete
  * **deletedVersion** : optional, the schema version number in the @delete directive
* **_region information_** : optional, see the section on Region Info
* **_attributes_** : optional, see the section on attributes, they appear in many places
* **_projection_** : an array of projected columns from the view, the view result if you will, see the section on projections
* **select** : the text of the select statement that defined the view
* **selectArgs** : the names of arguments any unbound expressions ("?") in the view
* **_dependencies_** : several lists of tables and how they are used in the view, see the [section on dependencies](#dependencies)

>NOTE: The use of unbound expressions in a view would be truly extraordinary
>so selectArgs is essentially always going to be an empty list.

Example:

```sql
CREATE VIEW MyView AS
SELECT *
  FROM foo
```

Generates:

```json
    {
      "name" : "MyView",
      "CRC" : "5545408966671198580",
      "isTemp" : 0,
      "isDeleted" : 0,
      "projection" : [
        {
          "name" : "id",
          "type" : "integer",
          "isNotNull" : 0
        },
        {
          "name" : "name",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "select" : "SELECT id, name FROM foo",
      "selectArgs" : [  ],
      "fromTables" : [ "foo" ],
      "usesTables" : [ "foo" ]
    }
```

### Projections

A projection defines the output shape of something that can return a
table-like value such as a view or a procedure.

The projection consists of a list of one or more _projected columns_,
each of which is:

* **name** : the name of the result column  (e.g. in select 2 as foo) the name is "foo"
* **type** : the type of the column (e.g. text, real, etc.)
* **kind** : optional, the discriminator of the type if it has one (e.g. if the result is an `int<job_id>` the kind is "job_id")
* **isSensitive** : optional, true if the result is sensitive (e.g. PII or something like that)
* **isNotNull** : true if the result is known to be not null

### Dependencies

The dependencies section appears in many entities, it indicates things
that were used by the object and how they were used.  Most of the fields
are optional, some fields are impossible in some contexts (e.g. inserts
can happen inside of views).

* **insertTables** : optional, a list of tables into which values were inserted
* **updateTables** : optional, a list of tables whose values were updated
* **deleteTables** : optional, a list of tables which had rows deleted
* **fromTables** : optional, a list of tables that appeared in a FROM clause (maybe indirectly inside a VIEW or CTE)
* **usesProcedures** : optional, a list of procedures that were accessed via CALL (not shared fragments, those are inlined)
* **usesViews** : optional, a list of views which were accessed (these are recursively visited to get to tables)
* **usesTables** : the list of tables that were used in any way at all by the current entity (i.e. the union of the previous table sections)

### Indices

The indices section contains the list of all indices in the schema,
it is zero or more view entires of this form:

* **name** : the index name
* **crc** : the schema CRC for the entire index definition
* **table** : the name of the table with this index
* **isUnique** : true if this is a unique index
* **ifNotExists** : true if this index was created with IF NOT EXISTS
* **isDeleted** : true if the view was marked with @delete
  * **deletedVersion** : optional, the schema version number in the @delete directive
* **_region information_** : optional, see the section on Region Info
* **where** : optional, if this is partial index then this has the partial index where expression
* **_attributes_** : optional, see the section on attributes, they appear in many places
* **columns** : the list of column names in the index
* **sortOrders** : the list of corresponding sort orders

Example:

```sql
create index foo_name on foo(name);
```

Generates:

```json
    {
      "name" : "foo_name",
      "CRC" : "6055860615770061843",
      "table" : "foo",
      "isUnique" : 0,
      "ifNotExists" : 0,
      "isDeleted" : 0,
      "columns" : [ "name" ],
      "sortOrders" : [ "" ]
    }

```

### Procedures

The next several sections:

* Queries
* Inserts
* General Inserts
* Updates
* Deletes
* General

All provide information about various types of procedures.  Some "simple"
procedures that consist only of the type of statement correspond to
their section (and some other rules) present additional information
about their contents.  This can sometimes be useful.  All the sections
define certain common things about procedures so that basic information
is available about all procedures.  This is is basically the contents
of the "general" section which deals with procedures that have a complex
body of which little can be said.


#### Queries

The queries section corresponds to the stored procedures that are a
single SELECT statement with no fragments.

The fields of a query record are:

* **name** : the name of the procedure
* **definedInFile** : the file that contains the procedure (the path is as it was specified to CQL so it might be relative or absolute)
* **definedOnLine** : the line number of the file where the procedure is declared
* **args** : _procedure arguments_ see the relevant section
* **_dependencies_** : several lists of tables and how they are used in the view, see the section on dependencies
* **_region information_** : optional, see the section on Region Info
* **_attributes_** : optional, see the section on attributes, they appear in many places
* **_projection_** : an array of projected columns from the procedure, the view if you will, see [the section on projections](#projections)
* **statement** : the text of the select statement that is the body of the procedure
* **statementArgs** : a list of procedure arguments (possibly empty) that should be used to replace the corresponding "?" parameters in the statement

Example:

```sql
create proc p(name_ text)
begin
  select * from foo where name = name_;
end;
```

Generates:

```json
    {
      "name" : "p",
      "definedInFile" : "x",
      "definedOnLine" : 3,
      "args" : [
        {
          "name" : "name_",
          "argOrigin" : "name_",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "fromTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "projection" : [
        {
          "name" : "id",
          "type" : "integer",
          "isNotNull" : 0
        },
        {
          "name" : "name",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "statement" : "SELECT id, name FROM foo WHERE name = ?",
      "statementArgs" : [ "name_" ]
    }
```

#### Procedure Arguments

Procedure arguments have several generalities that don't come up very
often but are important to describe.  The argument list of a procedure
is 0 or more arguments of the form:

* **name** : the argument name, any valid identifier
* **argOrigin** : either the name repeated if it's just a name or a 3 part string if it came from a bundle, see below
* **type** : the type of the argument (e.g. text, real, etc.)
* **kind** : optional, the discriminated type if any e.g. in `int<job_id>` it's "job_id"
* **isSensitive** : optional, true if the argument is marked with @sensitive (e.g. it has PII etc.)
* **isNotNull** : true if the argument is declared not null

An example of a simple argument was shown above, if we change the example
a little bit to use the argument bundle syntax (even though it's overkill)
we can see the general form of argOrigin.

Example:

```sql
create proc p(a_foo like foo)
begin
  select * from foo where name = a_foo.name or id = a_foo.id;
end;
```

Generates:

```json
    {
      "name" : "p",
      "definedInFile" : "x",
      "definedOnLine" : 3,
      "args" : [
        {
          "name" : "a_foo_id",
          "argOrigin" : "a_foo foo id",
          "type" : "integer",
          "isNotNull" : 0
        },
        {
          "name" : "a_foo_name",
          "argOrigin" : "a_foo foo name",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "fromTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "projection" : [
        {
          "name" : "id",
          "type" : "integer",
          "isNotNull" : 0
        },
        {
          "name" : "name",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "statement" : "SELECT id, name FROM foo WHERE name = ? OR id = ?",
      "statementArgs" : [ "a_foo_name", "a_foo_id" ]
    }
```

Note the synthetic names `a_foo_id` and `a_foo_name` the argOrigin
indicates that the bundle name is `a_foo` which could have been anything,
the shape was `foo` and the column in `foo` was `id` or `name` as
appropriate.

The JSON is often used to generate glue code to call procedures from
different languages.  The argOrigin can be useful if you want to codegen
something other normal arguments in your code.


#### General Inserts

The general insert section corresponds to the stored procedures that are a single INSERT statement with no fragments.
The fields of a general insert record are:

* **name** : the name of the procedure
* **definedInFile** : the file that contains the procedure (the path is as it was specified to CQL so it might be relative or absolute)
* **definedOnLine** : the line number of the file where the procedure is declared
* **args** : _procedure arguments_ see [the relevant section](#procedure-arguments)
* **_dependencies_** : several lists of tables and how they are used in the view, see the [section on dependencies](#dependencies)
* **_region information_** : optional, see the [section on Region Info](#region-information)
* **_attributes_** : optional, see the [section on attributes](#attributes), they appear in many places
* **table** : the name of the table the procedure inserts into
* **statement** : the text of the select statement that is the body of the procedure
* **statementArgs** : a list of procedure arguments (possibly empty) that should be used to replace the corresponding "?" parameters in the statement
* **statementType** : there are several insert forms such as "INSERT", "INSERT OR REPLACE", "REPLACE", etc. the type is encoded here

General inserts does not include the inserted values because they are
not directly extractable in general.  This form is used if one of these
is true:

 * insert from multiple value rows
 * insert from a select statement
 * insert using a `WITH` clause
 * insert using the upsert clause

If fragments are in use then even "generalInsert" cannot capture everything and "general" must be used (see below).

Example:

```sql
create proc p()
begin
  insert into foo values (1, "foo"), (2, "bar");
end;
```

Generates:

```json
    {
      "name" : "p",
      "definedInFile" : "x",
      "args" : [
      ],
      "insertTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "table" : "foo",
      "statement" : "INSERT INTO foo(id, name) VALUES(1, 'foo'), (2, 'bar')",
      "statementArgs" : [  ],
      "statementType" : "INSERT",
      "columns" : [ "id", "name" ]
    }
```

#### Simple Inserts

The vanilla inserts section can be used for procedures that just
insert a single row.  This is a very common case and if the JSON is
being used to drive custom code generation it is useful to provide the
extra information.  The data in this section is exactly the same as
the General Inserts section except that includes the inserted values.
The "values" property has this extra information.

Each value in the values list corresponds 1:1 with a column and has
this form:

* **value** : the expression for this value
* **valueArgs**: the array of procedure arguments that should replace the "?" entries in the value

Example:

```sql
create proc p(like foo)
begin
  insert into foo from arguments;
end;
```

Generates:

```json
    {
      "name" : "p",
      "definedInFile" : "x",
      "definedOnLine" : 3,
      "args" : [
        {
          "name" : "name_",
          "argOrigin" : "foo name",
          "type" : "text",
          "isNotNull" : 0
        },
        {
          "name" : "id_",
          "argOrigin" : "foo id",
          "type" : "integer",
          "isNotNull" : 0
        }
      ],
      "insertTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "table" : "foo",
      "statement" : "INSERT INTO foo(id, name) VALUES(?, ?)",
      "statementArgs" : [ "id_", "name_" ],
      "statementType" : "INSERT",
      "columns" : [ "id", "name" ],
      "values" : [
        {
          "value" : "?",
          "valueArgs" : [ "id_" ]
        },
        {
          "value" : "?",
          "valueArgs" : [ "name_" ]
        }
      ]
    }
```

#### Updates

The updates section corresponds to the stored procedures that are a
single UPDATE statement with no fragments. The
fields of an update record are:

* **name** : the name of the procedure
* **definedInFile** : the file that contains the procedure (the path is as it was specified to CQL so it might be relative or absolute)
* **definedOnLine** : the line number of the file where the procedure is declared
* **args** : _procedure arguments_ see [the relevant section](#procedure-arguments)
* **_dependencies_** : several lists of tables and how they are used in the view, see the section on dependencies
* **_region information_** : optional, see [the section on Region Info](#region-information)
* **_attributes_** : optional, see [the section on attributes](#attributes), they appear in many places
* **table** : the name of the table the procedure inserts into
* **statement** : the text of the update statement that is the body of the procedure
* **statementArgs** : a list of procedure arguments (possibly empty) that should be used to replace the corresponding "?" parameters in the statement


Example:

```sql
create proc p(like foo)
begin
  update foo set name = name_ where id = id_;
end;
```

Generates:

```json
    {
      "name" : "p",
      "definedInFile" : "x",
      "definedOnLine" : 3,
      "args" : [
        {
          "name" : "name_",
          "argOrigin" : "foo name",
          "type" : "text",
          "isNotNull" : 0
        },
        {
          "name" : "id_",
          "argOrigin" : "foo id",
          "type" : "integer",
          "isNotNull" : 0
        }
      ],
      "updateTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "table" : "foo",
      "statement" : "UPDATE foo SET name = ? WHERE id = ?",
      "statementArgs" : [ "name_", "id_" ]
    }
```


#### Deletes

The deletes section corresponds to the stored procedures that are a single
DELETE statement with no fragments. The fields of a delete record are
exactly the same as those of update.  Those are the basic fields needed
to bind any statement.

Example:

```sql
create proc delete_proc (name_ text)
begin
  delete from foo where name like name_;
end;
```

Generates:

```json
    {
      "name" : "delete_proc",
      "definedInFile" : "x",
      "definedOnLine" : 3,
      "args" : [
        {
          "name" : "name_",
          "argOrigin" : "name_",
          "type" : "text",
          "isNotNull" : 0
        }
      ],
      "deleteTables" : [ "foo" ],
      "usesTables" : [ "foo" ],
      "table" : "foo",
      "statement" : "DELETE FROM foo WHERE name LIKE ?",
      "statementArgs" : [ "name_" ]
    }
```

#### General

And finally the section for procedures that were encountered that are
not one of the simple prepared statement forms.  The principle reasons
for being in this category are:

* the procedure has out arguments
* the procedure uses something other than a single DML statement
* the procedure has no projection (no result of any type)
* the procedure uses shared fragments and hence has complex argument binding

The fields of a general procedure are something like a union of update
and delete and query but with no statement info.  The are as follows:

* **name** : the name of the procedure
* **definedInFile** : the file that contains the procedure (the path is as it was specified to CQL so it might be relative or absolute)
* **definedOnLine** : the line number of the file where the procedure is declared
* **args** : _complex procedure arguments_ see the relevant section
* **_dependencies_** : several lists of tables and how they are used in the view, see the section on dependencies
* **_region information_** : optional, see the section on Region Info
* **_attributes_** : optional, see the section on attributes, they appear in many places
* **_projection_** : optional, an array of projected columns from the procedure, the view if you will, see the section on projections
* **_result_contract_** : optional,
* **table** : the name of the table the procedure inserts into
* **statement** : the text of the update statement that is the body of the procedure
* **statementArgs** : a list of procedure arguments (possibly empty) that should be used to replace the corresponding "?" parameters in the statement
* **usesDatabase** : true if the procedure requires you to pass in a sqlite connection to call it

The result contract is at most one of these:

* **hasSelectResult** : true if the procedure generates its projection using SELECT
* **hasOutResult**: true if the procedure generates its projection using OUT
* **hasOutUnionResult**: true if the procedure generates its projection using OUT UNION

A procedure that does not produce a result set in any way will set none
of these and have no projection entry.

Example:

```sql
create proc with_complex_args (inout arg real)
begin
  set arg := (select arg+1 as a);
  select "foo" bar;
end;
```

Generates:

```json
    {
      "name" : "with_complex_args",
      "definedInFile" : "x",
      "definedOnLine" : 1,
      "args" : [
        {
          "binding" : "inout",
          "name" : "arg",
          "argOrigin" : "arg",
          "type" : "real",
          "isNotNull" : 0
        }
      ],
      "usesTables" : [  ],
      "projection" : [
        {
          "name" : "bar",
          "type" : "text",
          "isNotNull" : 1
        }
      ],
      "hasSelectResult" : 1,
      "usesDatabase" : 1
    }
```

#### Complex Procedure Arguments

The complex form of the arguments allows for an optional "binding"

* **binding** : optional, if present it can take the value "out" or "inout"
  * if absent then binding is the usual "in"

Note that atypical binding forces procedures into the "general" section.

### Interfaces

* **name** : the name of the procedure
* **definedInFile** : the file that contains the procedure (the path is as it was specified to CQL so it might be relative or absolute)
* **definedOnLine** : the line number of the file where the procedure is declared
* **attributes** : optional, see the section on attributes, they appear in many places
* **projection**: An array of projections. See [the section on projections](#projections)

Example

```sql
interface interface1 (id int);
```

Generates:
```json
    {
      "name" : "interface1",
      "definedInFile" : "x.sql",
      "definedOnLine" : 1,
      "projection" : [
        {
          "name" : "id",
          "type" : "integer",
          "isNotNull" : 0
        }
      ]
    }
```

### Procedure Declarations

The `declareProcs` section contains a list of procedure
declarations. Each declaration is of the form:

* **name** : the name of the procedure
* **args** : _procedure arguments_ see the relevant section
* **attributes** : optional, see the section on attributes, they appear in many places
* **projection** : An array of projections. See [the section on projections](#projections)
* **usesDatabase** : true if the procedure requires you to pass in a sqlite connection to call it

The `declareNoCheckProcs` describes procedures declared like so:

```
DECLARE PROC Foo NO CHECK
```

Such procedures carry on the name and attributes

* **name** : the name of the procedure
* **attributes** : optional, see the section on attributes, they appear in many places

### Function Declarations

The `declareFuncs` section contains a list of function declarations, Each declaration is of the form:

* **name** : the name of the function
* **args** : see [the relevant section](#procedure-arguments)
* **attributes** : optional, see the section on attributes, they appear in many places
* **returnType** : see the relevant section below.
* **createsObject** : true if the function will create a new object (e.g. `function dict_create() create object;`)

There are also sections for `declareNoCheckFuncs`, `declareSelectFuncs`, and `declareNoCheckSelectFuncs`.

* No check function do not have the `args` tag
* Select functions do not have the `createsObject` tag (they can't create objects)
* Select functions may have a `projection` instead of a `returnType` if they are table-valued

### Return Type

* **type** : base type of the return value (e.g. INT, LONG)
* **kind** : optional, if the type is qualified by a discriminator such as int<task_id> it appears here
* **isSensitive** : optional, true if the result is sensitive (e.g. PII)
* **isNotNull** : true if the result is known to be not null

### Regions

The regions section contains a list of all the region definitions.  Each region is of the form:

* **name** : the name of the region
* **isDeployableRoot** : is this region itself a deployment region (declared with @declare_deployable_region)
* **deployedInRegion** : name, the deployment region that contains this region or "(orphan)" if none
   * note that deploymentRegions form a forest
* **using** : a list of zero or more parent regions
* **usingPrivately**: a list of zero more more booleans, one corresponding to each region
  * the boolean is true if the inheritance is private, meaning that sub-regions cannot see the contents of the inherited region

There are more details on regions and the meaning of these terms in Chapter 10.

### Ad Hoc Migrations

This section lists all of the declared ad hoc migrations.  Each entry is of the form:

* **name** : the name of the procedure to be called for the migration step
* **crc** : the CRC of this migration step, a hash of the call
* **_attributes_** : optional, see the section on attributes, they appear in many places

Exactly one of:

* **version**: optional, any positive integer, the version at which the migration runs, OR
* **onRecreateOf**: optional, if present indicates that the migration runs when the indicated group is recreated

There are more details on ad hoc migrations in Chapter 10.

### Enums

This section list all the enumeration types and values.  Each entry is of the form:

* **name** : the name of the enumeration
* **type** : the base type of the enumeration (e.g. INT, LONG)
* **isNotNull**: always true, all enum values are not null (here for symmetry with other uses of "type")
* **values**: a list of legal enumeration values

Each enumeration value is of the form:

* **name** : the name of the value
* **value** : a numeric literal

Example:

```sql
enum an_enumeration integer ( x = 5, y = 12 );
```

Generates:

````json
    {
      "name" : "an_enumeration",
      "type" : "integer",
      "isNotNull" : 1,
      "values" : [
        {
          "name" : "x",
          "value" : 5
        },
        {
          "name" : "y",
          "value" : 12
        }
      ]
    }
````

### Constant Groups

This section list all the constant groups and values.  Each entry is of
the form:

* **name** : the name of the constant group
* **values**: a list of declared constant values, this can be of mixed type

Each constant value is of the form:

* **name** : the name of the constant
* **type** : the base type of the constant (e.g. LONG, REAL, etc.)
* **kind** : optional, the type kind of the constant (this can be set with a CAST on a literal, e.g. CAST(1 as int<job_id>))
* **isNotNull** : true if the constant type is not null (which is anything but the NULL literal)
* **value** : the numeric or string literal value of the constant


Example:

```sql
declare const group some_constants (
  x = cast(5 as int<job_id>),
  y = 12.0,
  z = 'foo'
);
```

Generates:

```json
    {
      "name" : "some_constants",
      "values" : [
        {
          "name" : "x",
          "type" : "integer",
          "kind" : "job_id",
          "isNotNull" : 1,
          "value" : 5
        },
        {
          "name" : "y",
          "type" : "real",
          "isNotNull" : 1,
          "value" : 1.200000e+01
        },
        {
          "name" : "z",
          "type" : "text",
          "isNotNull" : 1,
          "value" : "foo"
        }
      ]
    }
```

### Subscriptions

This section list all the schema subscriptions in order of appearance.
Each entry is of the form:

* **type** : always "unsub" at this time
* **table** : the target of the subscription directive
* **version** : the version at which this operation is to happen (always 1 at this time)

This section is a little more complicated than it needs to be becasue
of the legacy/deprecated `@resub` directive.  At this point only the table
name is relevant.  The version is always 1 and the type is always "unsub".

Example:

```sql
@unsub(foo);
```

Generates:

```json
    {
      "type" : "unsub",
      "table" : "foo",
      "version" : 1
    }
```

### Summary

These sections general provide all the information about everything that
was declared in a translation unit.  Typically not the full body of what
was declared but its interface.  The schema information provide the core
type and context while the procedure information illuminates the code
that was generated and how you might call it.
