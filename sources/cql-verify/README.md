# Summary

`cql-verify` is a test tool.  It processes the input test file
looking for patterns to match in the test results.

## Usage

```bash
cql-verify test_case.sql test_results.out
```

# License

The same license applies to these files as the rest of the project.

```
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
```

# Test Case Markup

Input is typically a SQL file.  The comments in the file describe how to
match the output results.  The compiler is expected to annotate its output
with tags of the form

```
The statement ending at line 123
```

The tool searches the output for those lines and correlates them to the input.
These matching directives should appear before the input lines.  Like so:

```sql
-- TEST: basic test table with an auto inc field (implies not null)
-- + create_table_stmt% foo: % id: integer notnull primary_key autoinc
-- - error:
create table foo(
  id integer PRIMARY KEY AUTOINCREMENT
);
```

`TEST:` lines are merely counted, they mean nothing.  The other annotations have
these meanings:

```
-- match and advance the current match pointer
-- + foo       --> match foo, searching forward from the last match with +

-- these forms do not change the current search position
-- +[0-9] foo  --> match foo anywhere, but demand exactly n matches
-- - foo       --> shorthand for +0 foo (demand no matches)
-- * foo       --> shorthand for +1 foo (demand 1 match, anywhere)
-- = foo       --> match foo on the same line as the last match with +
```

This is discussed more fully in the developers guide [Chapter 4](https://ricomariani.github.io/CG-SQL-author/docs/developer_guide/04_testing/).
