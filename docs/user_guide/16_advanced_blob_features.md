---
title: "Chapter 16: Advanced Blob Features"
weight: 16
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

There are two large features that involve complex uses of blobs that
are supported in the default runtime.  These are Blob Storage and Backed
Tables, the latter of which uses key and value blobs for generic schema.

### Blob Storage

The general idea here is that you might want to take arbitrary data that
is in a cursor, which is to say any database shape at all, and convert
it into a single blob.  You could use this blob to store composite data
in a single column in the database or to send your data over some kind
of wire transport in a generic fashion.  The idea of blob storage is
to provide a reslient way to do this that is platform neutral (i.e. you
can store the blob on one system and recover it on another system with
different endian order).  Blob storage allows limited extension of the
blob shape over time, allowing you to add new nullable columns at the
end of your shape and still recover your data from older blobs.

#### Defining a shape for Blob Storage

In SQL/CQL, the main way you define structures, especially those that you
want to maintain, is with tables.  Hence we introduce notation like this:

```sql
[[blob_storage]]
create table news_info(
  who text,
  what text,
  `when` long -- timestamp of some kind
);
```

The `blob_storage attribute` indicates that the table we're about
to define here is not really going to be a materialized table.  As a
result, you will not be able to (e.g.) `DROP` the table or `select`
from it, and there will be no schema upgrade for it should you request
one. However, the usual schema maintenance rules still apply (See
[Chapter 10](./10_schema_management.md) and
[Chapter 11](./11_previous_schema_validation.md)) which help you to
create compatible versions of this structure.  For instance, new columns
can be added only at the end, and only if they are nullable. Here we add
`source` to the schema in a hypothetical "version 6".

```sql
[[blob_storage]]
create table news_info(
  who text,
  what text,
  `when` long -- timestamp of some kind
  source text @create(6)
);
```
>NOTE: schema versions move forward globally in the schema, not locally
>in one table; this implies there are versions 1-5 elsewhere, not shown.

Additionally, since the storage is not backed by SQLite and therefore
lacks its constraint system, default values and constraints are
not allowed in a table marked with `cql:blob_storage`; it's just
data. Similarly, triggers, views, and indices may not use the table
marked as blob storage. It isn't really a table.

#### Declaring Blob Storage

Blob storage goes in a blob field, but recall CQL has discriminated
types so we can use a form like this:

```sql
create table info(
  id long primary key,
  news_info blob<news_info>
);
```

From a SQL perspective `news_info` is just a blob, you can only apply
blob operations to it in the context of a query.  This means `where`
clauses that partially constraint the blob contents are not generally
possible (though you could do it if you write suitable UDFs and
[Backed Tables](#backed-tables) actually generalize this if generic schema support
is what is desired).  Blob storage is really about moving the whole blob
around so it's apprpropriate when you want to crack the blob in code,
and not so much in database operations.

#### Creating Blobs with Blob Storage

You can use the `to_blob` pipeline function on a cursor to get a blob.
In the below `C:to_blob` becomes simply `cql_cursor_to_blob(C)`.

```sql
proc make_blob(like news_info, out result blob<news_info>)
begin
  -- declare the cursor
  cursor C like news_info;
  -- load it from loose arguments
  fetch c from arguments;
  -- set the blob variable
  set result := C:to_blob;
end;
```

The above declares a cursor, loads it from argument values, and converts it
to a blob.  Of course any of the usual cursor building forms can be used
to power your blob creation, you just do one serialization at the end.
The above is assembling a blob from arguments but you could equally make
the blob from data.

```sql
proc get_news_info(id_ long not null, out result blob<news_info>)
begin
   -- use our @columns sugar syntax for getting just news_info columns from
   -- a table with potentially lots of stuff (or an error if it's missing columns)
   cursor C for
     select @columns(like news_info) from some_source_of_info where info.id = id_;
   fetch c;
   set result := C:to_blob;
end;
```

There are *many* cursor fetch forms, including dummy data forms and other
interesting bits of sugar.  You can fetch a cursor from arguments, from
other cursors, and even combinations.  Because cursors are the source of
new blobs,  any of these data acquistion forms are viable and convenient
sources of data with which to make blobs.

#### Unpacking Blob Storage

Again, the normal way that you work with records in CQL is by creating
suitable cursors. Such cursors can be economically accessed on a
field-by-field basis. What we need is a way to easily recreate a cursor
from a blob so we can read the data values. To do this use this form:

```sql
-- get the blob from somewhere (b will be of type blob<news_info>)
let b := (select news_info from info where id = id_ if nothing null);

-- create a suitable cursor with the same shape
cursor C like b;

-- load the cursor (note that this can throw an exception if the blob is corrupt)
C:from_blob(b);

-- now use C.who, C.what, etc.
```

Once the data is loaded in a cursor it is very economical to access on a
field-by-field basis, and, since the deserialization of the blob happened
all at once, that can also be economical.

>NOTE: The runtime cannot assume that the blob is well formed, it could be
>coming from anywhere.  If only for security reasons it must assume the blob is
>"hostile".  Hence the decoding validates the shape, internal lengths, and so
>forth.  Therefore there are many ways conversion might fail.

Once you have the cursor you can do any of the usual data operations; you could
even make new blobs with different combinations by slicing the cursor fields
using the `LIKE` operator.  You can return the cursor with `OUT`, or `OUT UNION`,
or pass the blob fields as arguments to functions using the `FROM`
forms. The cracked blob is fully usable for all the usual CQL things you might
need to do.  Importantly, blob storage can contain other blobs so you can nest
shapes as needed.

#### Blob Storage Representation

The blob data must be able to evolve over time, so each blob has to
be self-describing.  We must also be able to throw an exception if an
incorrect or invalid blob is used when loading a cursor, so the blob
has to contain the following:

* the number of columns in the blob data type when it was created, the count is
  inferred from the field types which are null terminated
* the type of each field (this is encoded as a single plain-text character)
  * the types are bool, int, long, (double) real, (string) text, blob;
  * we use 'f' (flag) for bools, hence the codes are "fildsb"
  * these are encoded with one letter each, upper case meaning 'not null' so the
    storage might be "LFss"
  * the blob begins with a null terminated string that serves for both the count
    and the types
* Each nullable field may be present or null; 1 bit is used to store this fact.
  The bits are in an array of bytes that comes immediately after the type info
  (the type info implicitly tells us the size of this array)
* Boolean values are likewise encoded as bits within the same array, so the
  total number of bits stored is nullables plus booleans (nullable booleans use
  2 bits, even if null both bits are stored)
* When reading a newer version of a record from an older piece of data that is
  missing a column then the column is assumed to be NULL
* Any columns added after the initial version (using @create) must be nullable;
  this is normal for adding columns to existing schema
* Integers and longs are stored in a
  [`varint`/`VLQ`](https://en.wikipedia.org/wiki/Variable-length_quantity)
  format after `zigzag` encoding (same article)
* Text is stored inline in null terminated strings (embedded nulls are not
  allowed in CQL text)
* Nested blobs are stored inline, with a length prefix encoded like any other
  int (varint zigzag)
* Floating point is stored in IEEE 754 format which is already highly portable
* None of these encodings have endian issues, they are fully specified byte orders


#### Blob Storage Customization

As with many other features, it's possible to replace the
(de)serialization with code of your choice by supplying your own runtime
methods.

Storage types that are going to be persisted in the database or go
over a wire-protocol should be managed like schema with the usual
validation rules.  On the other hand, formats that will be used only
transiently in memory can be changed at whim from version to version.
As mentioned above, the design specifically considers cases where a new
client discovers an old-format blob (with fewer columns) and, the reverse,
cases where an old client recieves a datagram from a new client with
too many columns.  Any customizations should consider these same cases.

#### Blob Storage Example

The code samples below illustrate some of the more common blob operations
that are likely to come up.

```sql
[[blob_storage]]
create table news_info(
  who text,
  what text,
  `when` long -- timestamp of some kind
);

-- a place where the blob appears in storage
create table some_table(
  x int,
  y int,
  news_blob blob<news_info>
);

-- a procedure that creates a news_info blob from loose args
proc make_blob(like news_info, out result blob<news_info>)
begin
  cursor C like news_info;
  fetch C from arguments;
  result := C:to_blob;
end;

-- a procedure that cracks the blob, creating a cursor
proc crack_blob(data blob<news_info>)
begin
  cursor C like news_info;
  C:from_blob(data);
  out C;
end;

-- A procedure that cracks the blob into loose args if needed
-- the OUT statement was created specifically to allow you to
-- avoid this sort mass OUT awfulness consider that the blob
-- might have dozens of columns, this quickly gets unweildy.
-- But, as an illustration, here is explicit extraction.
proc crack_blob_to_vars(
  data blob<news_info>,
  out who text,
  out what text,
  out `when` long) -- when is a keyword, `when` is not.
begin
  cursor C like news_info;
  C:from_blob(data);
  who := C.who;
  what := C.what;
  `when` := C.`when`;
end;

-- we're going to have a result with x/y columns in it
-- this shape lets us select those out easily using LIKE
interface my_basic_columns (
  x int,
  y int
);

-- this defines a shape for the result we want
-- we're never actually defining this procedure
interface my_result_shape (
  like my_basic_columns,
  like news_info
);

proc select_and_crack(whatever bool!)
begin
  cursor C for select * from some_table where whatever;
  loop fetch c
  begin
    -- crack the blob in c into a new cursor 'news'
    cursor news like news_info;
    fetch news from blob c.news_blob;

    -- assemble the result we want from the parts we have
    cursor result like my_result_shape;
    fetch result from values (from c like my_basic_columns, from news);

    -- emit one row, some came from the original data some cracked
    -- callers will never know that some data was encoded in a blob
    out union result;
  end;
end;
```

#### Deprecated Syntax

These forms are no longer supported:

```sql
-- loading a blob from a cursor
set a_blob from cursor C;

-- new supported forms, these are all the same thing
let b := C:to_blob;
C:to_blob(b);
let b := cql_cursor_to_blob(C);
cql_cursor_to_blob(C, b);

-- loading a cursor from a blob
fetch C from blob b;

  -- new supported forms, these are all the same thing
  C:from_blob(b);
  cql_cursor_from_blob(C, b);
```

### Blob Streams

Blob storage provides for a general mechanism to create blobs and either store
them or transmit them as a byte stream. The byte stream thus created is intended
to be resilient to versioning, provided that the rules for versioning blob
storage are followed, and also to be cross platform.

Normal blob storage provides for general storage for a a single row of arbitrary
data.  Something you might call a struct.  There is no provision for arrays of
things, or mixed storage of various types, however, the storage allows for blobs
nested within blobs. This gives us exactly the flexibility we need to generalize.

A blob stream is an addressble array of nested blobs stored in one blob.  The
header of the blob indicates the number of embeded blobs and their offsets.

To make a blob stream, use the following steps:

* create a `cql_blob_list` using `cql_blob_list_create`
* create or select blobs that were made using `cql_cursor_to_blob`
* put the blobs into a `cql_blob_list` using `cql_blob_list_add`
* convert the list of blobs into blob stream (a single blob) using `cql_make_blob_stream`

Most of the above actions have pipeline shortcuts (see above), e.g. `a_blob :=C:to_blob`,
`list:add(a_blob)`.

To use the blob stream:

* get the count of embedded blobs with `cql_blob_stream_count`
* load one of the blobs into a cursor with `cql_cursor_from_blob_stream`

```sql
[[blob_storage]]
create table my_storage(
  x int,
  y text
  -- etc.
);


  let a_blob := select T.my_stream from some_table;

  let num := cql_blob_stream_count(a_blob);
  let i := 0;
  for i < num; i += 1;
  begin
    cursor C like my_storage;
    cql_cursor_from_blob_stream(C, a_blob, i);
    -- use C.x, C.y etc.
  end;
```

Like all blobs, blob streams are immutable.

>NOTE: there is no helper currently for extracting the blob from the storage
>without decoding it. This seems like an obvious extension that would be
>useful to split and recreate a blob stream without decoding everything.

This blob shape can contain a nested blob which might be an array.
Note that it is not required that all the blobs in the stream be the
same shape.  However, if they are not, then some other rules will have
to inform the decoding code as to what the types are.  The decoding
logic for blob storage is designed to handle blobs that are "hostile"
so attempting to decode the wrong type might generate errors but it
is designed not to crash.

```sql
[[blob_storage]]
create table bigger_storage(
  id int,
  -- other columns as needed
  my_stream blob;
);
```

### Backed Tables

Most production databases include some tables that are fairly generic,
they use maybe a simple key-value combination to store some simple
settings or something like that.  In the course of feature development
this kind of thing comes up pretty often and in large client applications
there are many small features that need a little bit of state.

It's easy enough to model whatever state you need with a table or two but
this soon results in an explosion of tiny tables.  In some cases there
are only a few rows of configuration data and indeed the situation can be
so bad that the text of the schema for the little state table is larger
than the sum of all the data you will ever store there.  This situation
is a bit tragic because SQLite has initialization cost associated with
each table.  So these "baby tables" are really not paying for themselves
at all.

What we'd like to do is use some kind of generic table as the backing
store for many of these small tables while preserving type safety. The
cost of access might be a bit higher but since data volumes are expected
to be low anyway this would be a good trade-off.  And we can have as many
as we like.  In some cases the state doesn't even need to be persisted,
so we're talking about tables in an in-memory database.  Here low cost of
initialization is especially important. And lastly, if your project has
dozens or even hundreds of small features like this, the likelihood that
all of them are even used in any one session is quite low and so again,
having a low fixed cost for the schema is a good thing.  No need to create
a few hundred in-memory tables on the off chance that they are needed.

#### Defining Backed Tables

First you need a place to store the data.  We using "backing" tables
to store the data for "backed" tables.  And we define a backing table
in the usual way.  A simple backing table is just a key/value store and
looks like this:

```sql
[[backing_table]]
CREATE TABLE backing(
  k BLOB PRIMARY KEY,
  v BLOB NOT NULL
);
```

The `backing_table` attribute indicates that the table we're about to
define is to be used for backing storage.  At present it is signficantly
restricted. It has to have exactly two columns, both of which are blobs,
one is the key and one is the value.  It should be either "baseline"
schema (no @create annotation) or annotated with `@create` as it is
expected to be precious data.  `@recreate` is an error.  If it's an
in-memory table then versioning is somewhat moot but really the backing
store schema is not supposed to change over time, that's the point.

As showwn below there are additional attributes that can be put on the backing
table to define the functions that will be used to store data there.

In future versions we expect to allow some number of additional physical
columns which can be used by the backed tables (discussed below) but for
now only the simple key/value pattern is allowed.  The columns can have
any names but as they will be frequently used short names like "k" and
"v" are recommended.

Backed tables look like this:

```sql
[[backed_by=backing]]
CREATE TABLE backed(
  id INT PRIMARY KEY,
  name TEXT!,
  bias REAL
);

[[backed_by=backing]]
CREATE TABLE backed2(
  id INT PRIMARY KEY,
  name TEXT!
);
```

The `backed_by` attribute indicates that the table we're about to define
is not really going to be its own table.  As a result, you will not be
able to (e.g.) `DROP` the table or `CREATE INDEX` or `CREATE TRIGGER`
on it, and there will be no schema upgrade for it should you request one
with `--rt schema_upgrade`.  The table may not contain constraints as
there would be no way to enforce them, but they may have default values.
As compensation for these restrictions, backed tables can be changed
freely and have no associated physical schema cost.

>NOTE: Adding new not null columns creatives effectively a new backed
>table, any previous data will seem "lost".  See below.

#### Reading Data From Backed Tables

To understand how reading works, imagine that we had a VIEW for
each backed table which simply reads the blobs out of the backing
store and then extracts the backed columns using some blob extraction
functions. This would work, but then we'd be trading view schema for
table schema so the schema savings we're trying to achieve would be lost.

We can't use an actual VIEW but CQL already has something very "view
like" -- the shared fragment structure.  So what CQL does instead of views
is to automatically create a shared fragment just like the view we could
have made.  The shared fragment looks like this:

```sql
[[shared_fragment]]
proc _backed ()
begin
  select
   rowid,
   cql_blob_get(T.k, backed.id) as id,
   cql_blob_get(T.v, backed.name) as name,
   cql_blob_get(T.v, backed.bias) as bias
    from backing as T
    where cql_blob_get_type(backed, T.k) = 2105552408096159860L;
end;
```

Two things to note:

First, this fragment has the right shape, but the shared fragment
doesn't directly call blob extraction UDFs.  Rather it uses indirect
functions like `cql_blob_get`. The point of these helpers is to make
the actual blob functions configurable.  The default runtime includes
an implementation of extration functions with the default names, but
you can create whatever blob format you want by defining suitable functions.
You can even have different encodings in different backed tables.

Second, there is a type code embedded in the procedure.  The type
code is a hash of the _type name_ and the _names_ and _types_ of all
the _not-null_ fields in the backed table.  The hash is arbitrary but
repeatable, any system can compute the same hash and find the records
they want without having to share headers. The actual hash function is
included in the open source but it's just a SHA256 reduced to 64 bits with
some name canonicalization. The [JSON output](./13_json_output.md)
also includes the relevant hashes so you can easily consume them without
even having to know the hash function.

As a second example, the expanded code for `backed2` is shown below:

```sql
[[shared_fragment]]
proc _backed2 ()
begin
  select
    rowid,
    cql_blob_get(T.k, backed2.id) as id,
    cql_blob_get(T.v, backed2.name) as name
    from backing as T
    where cql_blob_get_type(backed, T.k) = -1844763880292276559L;
end;
```
As you can see it's very similar -- the type hash is different and of
course it has different columns but the pattern should be clear.

#### Computation of the Type Hash

The type hash, which is also sometimes called the record type, is designed to
stay fixed over time even if you add new optional fields. Contrariwise, if you
change the name of the type or if you add new not null fields the type identity
is considered to be changed and any data you have in the backing table will
basically be ignored because the type hash will not match.  This is lossy but
safe.  More complicated migrations from one type shape to another are possible
by introducing a new backed type and moving data.

####  `cql_blob_get` and `cql_blob_get_type`

By default `cql_blob_get` turns into either `bgetkey` or `bgetval` depending on
if you are reading from the key blob or the value blob.  This is controlled by
attributes on the backing table.  All users of that table will apply the same
functions.

```sql
[[get_key = bgetkey]]
[[get_val = bgetval]]
[[get_type = bgetkey_type]]
```

The key can no optional fields, it is formed from the primary key of the backing
table. As a result it's possible to index the fields by number and infer their types.
Values, on the other hand, are expected to have nullable fields so some might be
missing. They are indexed using a hash of the field name and the type, similar
to the type code that identifies the backed table in the storage.

These attributes control offsets vs. codes:

```sql
[[use_key_codes]]    -- omit and keys use offsets by default
[[use_val_offsets]]  -- omit and values use codes by default
```

Here the offset means the zero based ordinal of the column in the key or the value.
The order is the order that they appear in the table definition, there might be gaps
because keys and values could interleave, each gets its own ordinals.

```sql
[[backed_by=something]]
create table foo(
  x int,    -- ordinal 0 for keys
  a int,    -- ordinal 0 for values
  b int     -- ordinal 1 for values
  y int,    -- ordinal 1 for keys
  c int     -- ordinal 2 for values
  primary key (x,y)
);
```

>NOTE: The blob format for _keys_ must be canonical in the sense that the same
>values always produce the same blob, even after replacements, so if you use a
>field id based blob it will be important to always store the fields in the same
>order. Contrariwise use of offsets for the value blob indicates that your
>particular value blob will have fixed storage that is addressable by offset.
>This may be suitable for your needs, for instance maybe you only ever need to
>store 0-3 integers in the value.

#### JSON options

The attributes `[[json]]` and `[[jsonb]]` cause the compiler to ignore the other
backing attributes and use a JSON array for the keys (with the leading column
being the type) and a JSON.  This requires that the SQLite you are using
supports the JSON functions, in particular `json_array`, `json_object`,
`json_set`, and the `->>` extraction operator.  Some stock versions of Linux do
not have them but any recent SQLite amalgamation will have these features.

#### Selecting from a Backed Table

Armed with these basic transforms we can already do a simple transform
to make select statement work.  Suppose CQL sees:

```sql
cursor C for select * from backed;
```

The compiler can make this select statement work with a simple transform:

```sql
 cursor C FOR with
  backed (*) as (CALL _backed())
  select *
    from backed;
```

Now remember `_backed` was the automatically created shared fragment.
Basically, when the compiler encounters a select statement that mentions
any backed table it adds a call to the corresponding shared fragment in
the `with` clause, creating a `with` clause if needed.  This effectively
creates necessary "view".  And, because we're using the shared fragment
form, all users of this fragment will share the text of the view.
So there is no schema and the "view" text of the backed table appears
only once in the binary.  More precisely we get this after full expansion:

```sql
with
backed (rowid, id, name, bias) as (
  select
    rowid,
    bgetkey(T.k, 0),                      -- 0 is offset of backed.id in key blob
    bgetval(T.v, -6639502068221071091L),  -- note hash of backed.name
    bgetval(T.v, -3826945563932272602L)   -- note hash of backed.bias
  from backing as T
  where bgetkey_type(T.k) = 2105552408096159860L)
select rowid, id, name, bias
  from backed;
```

Now with this in mind we can see that it would be very beneficial to
also add this:

```sql
[[deterministic]]
declare select function bgetkey_type(b blob) long;

create index backing_index on backing(bgetkey_type(k));
```

or more cleanly:

```sql
create index backing_index on backing(cql_blob_get_type(backing, k));
```

Either of these results in a computed index on the row type stored in
the blob.  Other physical indices might be helpful too and these can
potentially be shared by many backed tables, or used in partial indicies.

>NOTE: Your type function can be named something other than the default
>`bgetkey_type`.

Now consider a slightly more complex example:

```
select T1.* from backed T1 join backed2 T2 where T1.id = T2.id;
```

This becomes:

```
with
  backed (rowid, id, name, bias) as (call _backed()),
  backed2 (rowid, id, name) as (call _backed2())
  select T1.*
    from backed as T1
    inner join backed2 as T2
    where T1.id = T2.id;
```
Now even though two different backed tables will be using the backing
store, the original select "just works" once the CTE's have been added.
All the compiler had to do was add both backed table fragments.  Even if
`backed` was joined against itself, that would also just work.

#### Inserting Into a Backed Table

It will be useful to consider a simple example such as:

```sql
insert into backed values (1, "n001", 1.2), (2, "n002", 3.7);
```

This statement has to insert into the backing storage, converting the
various values into key and value blobs.  The compiler uses a simple
transform to do this job as well.  The above becomes:

```sql
 with
  _vals (id, name, bias) as (
    VALUES(1, "n001", 1.2), (2, "n002", 3.7)
  )
  INSERT INTO backing(k, v) select
    cql_blob_create(backed, V.id, backed.id),
    cql_blob_create(backed,
      V.name, backed.name,
      V.bias, backed.bias)
    from _vals as V;
```

Again the compiler is opting for a transform that is universal and here
the issue is that the data to be inserted can be arbitrarily complicated.
It might include nested select expressions, value computations, or any
similar thing. In this particular case the data is literal values but
in general the values could be anything.

To accompodate this possiblity the compiler's transform takes the original
values and puts them in its own CTE `_vals`. It then generates a new
insert statement targetting the backing store by converting _vals into
two blobs -- one for the key and one for the value.  There is only the one
place it needs to do this for any given `insert` statement no matter now
many items are inserted or how complex the insertion computation might be.

The compiler uses `cql_blob_create` as a wrapper to that can expand
to a user configured function with optional hash codes and mandatory
field types.  The default configuration that corresponds to this:

```sql
[[create_key = bcreatekey]]
[[create_val = bcreateval]]
```

The final SQL for an insert operation looks like this:

```sql
with
_vals (id, name, bias) as (
  VALUES(1, "n001", 1.2), (2, "n002", 3.7)
)
INSERT INTO backing(k, v) select
  bcreatekey(2105552408096159860, V.id, 1), -- type 1 is integer, offset implied
  bcreateval(2105552408096159860,
    -6639502068221071091, V.name, 4,  -- hash as before, type 4 is text,
    -3826945563932272602, V.bias, 3)  -- hash as before, type 3 is real,
  from _vals as V
```

As can be seen, both blobs have the same overall type code
(2105552408096159860) as in the select case.  The key blob is configured
for to use offsets and the argument positions give the implied offset.
In contrast the value blob is using hash codes (`offset` was not
specified).  This configuration is typical.

A more complex insert works just as well:

```sql
insert into backed
  select id+10, name||'x', bias+3 from backed where id < 3;
```

The above insert statement is a bit of a mess.  It's taking some of
the backed data and using that data to create new backed data.  But the
simple transform above works just as before.  We add the needed `backed`
CTE for the select and create `_vals` like before.

```sql
with
  backed (*) as (CALL _backed()),
  _vals (id, name, bias) as (
    select id + 10, name || 'x', bias + 3
    from backed
    where id < 3
  )
  INSERT INTO backing(k, v)
   select
     cql_blob_create(backed, V.id, backed.id),
     cql_blob_create(backed, V.name, backed.name, V.bias, backed.bias)
   from _vals as V;
```

Looking closely at the above we see a few things:

* `cql_blob_create` will expand as before (not shown)
* we added `backed(*)` as usual
* `_vals` once again just has the exact unchanged insert clause
* the `insert into backing(k, v)` part is identical, the same recipe always works

#### Deleting From a Backed Table

Again, we begin with a simple example:

```sql
delete from backed where id = 7;
```

The compiler requires a transformation that is quite general and while
this case is simple the where condition could be very complicated.
Fortunately there is such a simple transform:

```sql
with
  backed (*) as (CALL _backed())
DELETE from backing
  where rowid IN (
    select rowid
    from backed
    where id = 7
  );
```

All the compiler has to do here is:

* add the usual `_backed` CTE
* move the original `where` clause into a subordinate `select` that gives us the rowids to delete.

With the backed table in scope, any `where` clause works. If other backed
tables are mentioned, the compiler simply adds those as usual.

Below is a more complicated delete, it's a bit crazy but illustrative:

```sql
delete from backed where
  id in (select id from backed2 where name like '%x%');
```

So this is using rows in `backed2` to decide which rows to deleted in
`backed`.  The same simple transform works directly.

```sql
with
  backed2 (*) as (CALL _backed2()),
  backed (*) as (CALL _backed())
DELETE from backing
  where rowid IN (
    select rowid
    from backed
    where id IN (
      select id from backed2 where name LIKE '%x%'
    )
  );
```

What happened:

* the `where` clause went directly into the body of the rowid select
* `backed` was used as before but now we also need `backed2`

The delete pattern does not need any additional cql helpers beyond what we've
already seen.

#### Updating Backed Tables

The `update` statement is the most complicated of all the DML forms, it requires
all the transforms from the previous statements plus one additional transform.

First, the compiler requires two more blob helpers that are configurable. By
default they look like this:

```sql
[[update_key = bupdatekey]]
[[update_val = bupdateval]];
```

These are used to replace particular columns in a stored blob.  Now let's start
with a very simple update to see now it all works:

```sql
update backed set name = 'foo' where id = 5;
```

Fundamentally we need to do these things:

* the target of the update has to end up being the backing table
* we need the backed table CTE so we can do the filtering
* we want to use the rowid trick to figure out which rows to update which
  handles our `where` clause
* we need to modify the existing key and/or value blobs rather than create them
  from scratch

Applying all of the above, we get a transform like the following:

```sql
with
  backed (*) as (CALL _backed())
UPDATE backing
  SET v = cql_blob_update(v, 'foo', backed.name)
    where rowid IN (select rowid
    from backed
    where id = 5);
```

Looking into the details:

* we needed the normal CTE so that we can use `backed` rows
* the `where` clause moved into a `where rowid` sub-select just like in the
  `DELETE` case
* they compiler changed the SET targets to be `k` and `v` very much like the
  `INSERT` case, except we used an update helper that takes the current blob and
  creates a new blob to store
  * the helper is varargs so as we'll see it can mutate many columns in one call

The above gives a update statement that is almost working.  The remaining
problem is that it is possible to use the existing column values in the update
expressions and there is no way to use our `backed` CTE to get those values in
that context since the final update has to be all relative to the backing table.

Let's look at another example to illustrate this last wrinkle:

```sql
update backed set name = name || 'y' where bias < 5;
```

This update basically adds the letter 'y' to the name of some rows. This is a
silly example but this kind of thing happens in many contexts that are
definitely not silly.  To make these cases work the reference to `name` inside
of the set expression has to change. We end up with something like this:

```sql
with
  backed (*) as (CALL _backed())
UPDATE backing
  SET v = cql_blob_update(v,
    cql_blob_get(v, backed.name) || 'y',
    backed.name)
  where rowid IN (select rowid
    from backed
    where bias < 5);
```

Importantly the reference to `name` in the set expression was changed to
`cql_blob_get(v, backed.name)` -- extracting the name from the value blob. After
which it is appended with 'y' as usual.

The rest of the pattern is just as it was after the first attempt above, in fact
literally everything else is unchanged.  It's easy to see that the `where`
clause could be arbitrarily complex with no difficulty.

>NOTE: Since the `UPDATE` statement has no `from` clause only the fields in the
>target table might need to be rewritten, so in this case `name`, `id`, and
>`bias` were possible but only `name` was mentioned.

After the `cql_blob_get` and `cql_blob_update` are expanded the result looks
like this:

```sql
with
backed (rowid, id, name, bias) as (
  select
    rowid,
    bgetkey(T.k, 0),
    bgetval(T.v, -6639502068221071091L),
    bgetval(T.v, -3826945563932272602L)
  from backing as T
  where bgetkey_type(T.k) = 2105552408096159860L
)
UPDATE backing
SET v =
  bupdateval(
    v,
    -6639502068221071091L, bgetval(v, -6639502068221071091L) || 'y', 4
  )
  where rowid IN (select rowid
  from backed
  where bias < 5);
```

>NOTE: The blob update function for the value blob requires the original
>blob, the hash or offset to update, the new value, and the type of the
>new value. The blob update function for the key blob is the nearly same
>(blob, hash/offset, value) but the type is not required since the key
>blob necessarily has all the fields present because they are necessarily
>not null.  Therefore the type codes are already all present and so the
>type of every column is known. The value blob might be missing nullable
>values hence their type might not be stored/known.

Normally backed tables are used without having to know the details of
the transforms and the particulars of how each of the helper UDFs is
invoked but for illustration purposes we can make another small example
that shows a few more variations that might be created. In this examples
keys and values need to be mutated.

```sql
[[backed_by=backing]]
create table sample(
 name text,
 state long,
 prev_state long,
 primary key(name, state)
);
```

This update mixes all kinds of values around...

```sql
update sample
 set state = state + 1, prev_state = state
 where name = 'foo';
```

And the final output will be:

```sql
with
sample (rowid, name, state, prev_state) as (
  select
    rowid,
    bgetkey(T.k, 0),
    bgetkey(T.k, 1),
    bgetval(T.v, -4464241499905806900)
  from backing as T
  where bgetkey_type(T.k) = 3397981749045545394
)
SET
  k = bupdatekey(k, bgetkey(k, 1) + 1, 1),
  v = bupdateval(v, -4464241499905806900, bgetkey(k, 1),  2)
  where rowid IN (select rowid
  from sample
  where name = 'foo');
```

As expected the `bupdatekey` call gets the column offset (1) but not
the type code (2).  `bupdateval` gets a hash code and a type.

#### Normal Helper Declarations

If you want to refer to your blob functions in your own code, such as
for indices you'll also need to do something like this:

```sql
[[deterministic]] declare select function bgetkey_type(b blob) long;
[[deterministic]] declare select function bgetval_type(b blob) long;
[[deterministic]] declare select function bgetkey(b blob, iarg int) long; -- polymorphic
[[deterministic]] declare select function bgetval(b blob, iarg int) long; -- polymorphic
[[deterministic]] declare select function bcreateval no check blob;
[[deterministic]] declare select function bcreatekey no check blob;
[[deterministic]] declare select function bupdateval no check blob;
[[deterministic]] declare select function bupdatekey no check blob;
```

`bgetval` and `bgetkey` are not readily declarable generally because their
result is polymorphic so it's preferable to use `cql_blob_get` like the compiler
does (see examples above) which then does the rewrite for you. But it is helpful
to have a UDF declaration for each of the above, especially if you want the
`--rt query_plan` output to work seamlessly. Typically `bgetval` or `bgetval`
would only be needed in the context of a `create index` statement and
`cql_blob_get` can be used instead in that case.

>NOTE: it's possible to rewrite `CREATE INDEX` on a backed table into and index
>on the backing table but this has not yet been implemented.

#### Backed Table Attributes Summary

This example has the whole set.

```sql
[[backing_table]]             -- this makes it a backing table
[[get_type = bgetkey_type]]   -- the function to get the type out of the key blob
[[get_key = bgetkey]]         -- the function to get a column out of the key blob
[[get_val = bgetval]]         -- the function to get a column out of the value blob
[[create_key = bcreatekey]]   -- the function to create a key blob
[[create_val = bcreateval]]   -- the function to create a value blob
[[update_key = bupdatekey]]   -- the function to update a key blob
[[update_val = bupdateval]]   -- the function to update a value blob
[[use_key_codes]]             -- if present key functions use a column code, by default key funcs use column offsets
[[use_val_offsets]]           -- if present value functions use a column offset, by default value funcs use column codes
[[json]]                      -- ignores the above and targets json_* instead (don't combine it)
[[jsonb]]                     -- ignores the above and targets jsonb_* instead (don't combine it)
create table foo(
  k blob primary key,
  v blob
);
```