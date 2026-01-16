---
title: "Appendix 7: Antipatterns"
weight: 7
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

These are a few of the antipatterns I've seen while travelling through various
CQL source files.  They are in various categories.

Refer also to Appendix 8: Best Practices.

### Common Schema

For these examples let's create a couple of tables we might need for examples

```sql
CREATE TABLE foo (
    id int primary key,
    name text
);

CREATE TABLE bar (
    id int primary key,
    rate real
);
```

### Declarations

```sql
DECLARE v LONG NOT NULL;
SET v := 1;
```

better:

```sql
LET v := 1L;  -- long literals have the L suffix like in C
```

Similarly:

```sql
VAR v REAL NOT NULL;
SET v := 1;
```

better:

```sql
LET v := 1.0; -- use scientific notation or add .0 to make a real literal
```

### Casts

Redundant casts fatten the code and don't really add anything to readability.
Sometimes it's necessary to cast NULL to a particular type so that you can be
sure that generated result set has the right data type, but most of the casts
below are not necessary.

```sql
  SELECT
    CAST(foo.id as INT) as id,  -- generates an error, it's already an int
    CAST(foo.name as TEXT) as name, -- generates an error, it's already text
    CAST(NULL as REAL) as rate
  FROM foo
UNION ALL
  SELECT
    CAST(bar.id as INT) as id, -- generates an error, it's already an int
    CAST(NULL as TEXT) as name, -- generates an error, it's already an int
    CAST(bar.rate as REAL) as rate
  FROM bar
```

Redundant casts actually generate errors now, so you'll end up with this much
better code:

```sql
  SELECT
    foo.id,
    foo.name,
    CAST(NULL as REAL) as rate
  FROM foo
UNION ALL
  SELECT
    bar.id,
    CAST(NULL as TEXT) as name,
    bar.rate
  FROM bar
```

Alternatively, suffix casting is much less verbose and generates the same SQL.

```sql
  SELECT
    foo.id,
    foo.name,
    null ~real~ as rate
  FROM foo
UNION ALL
  SELECT
    bar.id,
    null ~text~ as name,
    bar.rate
  FROM bar
```


#### Booleans

TRUE and FALSE can be used as boolean literals.

SQLite doesn't care about the type but CQL will get the type information it
needs to make the columns of type BOOL

```sql
  SELECT
    foo.id,
    foo.name,
    NULL_REAL as rate,
    TRUE as has_name,  -- this is a bit artificial but you get the idea
    FALSE as has_rate
  FROM foo
UNION ALL
  SELECT
    bar.id,
    NULL_TEXT as name,
    bar.rate,
    FALSE as has_name,
    TRUE as has_rate
  FROM bar
```

### Boolean expressions and CASE/WHEN

It's easy to get carried away with the power of `CASE` expressions, I've seen
this kind of thing:

```sql
CAST(CASE WHEN foo.name IS NULL THEN 0 ELSE 1 END AS BOOL)
```

But this is simply

```sql
foo.name IS NOT NULL
```

In general, if your case alternates are booleans a direct boolean expression
would have served you better.

### CASE and CAST and NULL

Sometimes there's clamping or filtering going on in a case statement

```sql
CAST(CASE WHEN foo.name > 'm' THEN foo.name ELSE NULL END AS TEXT)
```

Here the `CAST` is not needed at all so we could go to

```sql
CASE WHEN foo.name > 'm' THEN foo.name ELSE NULL END
```

`NULL` is already the default value for the `ELSE` clause so you never need
`ELSE NULL`

So better:

```sql
CASE WHEN foo.name > 'm' THEN foo.name END
```

### Filtering out NULLs

Consider

```sql
SELECT *
    FROM foo
    WHERE foo.name IS NOT NULL AND foo.name > 'm';
```

There's no need to test for `NOT NULL` here, the boolean will result in `NULL`
if `foo.name` is null which is not true so the `WHERE` test will fail.

Better:

```sql
SELECT *
    FROM foo
    WHERE foo.name > 'm';
```

### Not null boolean expressions

In this statement we do not want to have a null result for the boolean
expression

```sql
SELECT
    id,
    name,
    CAST(IFNULL(name > 'm', 0) AS BOOL) AS name_bigger_than_m
    FROM FOO;
```

So now we've made several mistakes.  We could have used the usual `FALSE`
definition to avoid the cast. But even that would have left us with an IFNULL
that's harder to read.  Here's a much simpler formulation:

```sql
SELECT
    id,
    name,
    name > 'm' IS TRUE AS name_bigger_than_m
    FROM FOO;
```
Even without the `TRUE` macro you could do `IS 1` above and still get a result

of type `BOOL NOT NULL`

### Using `IS` when it makes sense to do so

This kind of boolean expression is also verbose for no reason

```sql
    rate IS NOT NULL AND rate = 20
```

In a `WHERE` clause probably `rate = 20` suffices but even if you really need a
`BOOL NOT NULL` result the expression above is exactly what the `IS` operator is
for.  e.g.

```sql
    rate IS 20
```

The `IS` operator is frequently avoided except for `IS NULL` and `IS NOT NULL`
but it's a general equality operator with the added semantic that it never
returns `NULL`.   `NULL IS NULL` is true.  `NULL IS [anything not null]` is
false.

### Left joins that are not left joins

Consider

```sql
  SELECT foo.id,
         foo.name,
         bar.rate
  FROM foo
  LEFT JOIN bar ON foo.id = bar.id
  WHERE bar.rate > 5;
```

This is no longer a left join because the `WHERE` clause demands a value for at
least one column from `bar`.

Better:

```sql
  SELECT foo.id,
         foo.name,
         bar.rate
  FROM foo
  INNER JOIN bar ON foo.id = bar.id
  WHERE bar.rate > 5;
```
