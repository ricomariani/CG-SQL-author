# Security Review Findings

Review target: `sources` at
`eaa48be31c4a44b37a0a80c2abead5f58aeec70b`, excluding checked-in release,
beta, and SQLite amalgamation files.

Threat model:

- Compiler source input is normally trusted.
- Runtime and generated-code defects have priority.
- Public runtime API arguments and persisted database contents can be
  attacker-controlled.

## Findings

| # | Severity | File | Lines | Vulnerability | Confidence |
|---|---|---|---|---|---|
| 1 | HIGH | `sources/cqlrt_common.c` | 5539-5584, 5906-6193, 6671-7005 | Overlapping serialized fields can under-size blob-update buffers and cause heap-buffer overflows | 9/10 |
| 2 | MEDIUM | `sources/cg_schema.c` | 956-974, 1051-1069, 1197-1220 | Database-derived schema identifiers are inserted into executable upgrade SQL without identifier escaping | 9/10 |
| 3 | MEDIUM | `sources/cqlrt_common.c` | 1485-1508 | Heterogeneous result sets can cause out-of-bounds reads in `cql_rows_equal` | 9/10 |
| 4 | MEDIUM | `sources/cqlrt_common.c` | 3388-3427 | Signed blob-stream index arithmetic can overflow and bypass bounds validation | 9/10 |

### Overlapping serialized fields

Variable-length backed-blob fields are validated independently but are not
required to occupy disjoint ranges. Update operations calculate allocation
sizes from the physical variable section and logical field lengths, then copy
each field separately. Aliased ranges can make the required output larger than
the allocation.

Reject overlapping or noncanonical variable-field ranges and use checked
arithmetic for output-size calculations.

### Schema identifier injection

Exclusive schema upgrade code reads trigger, view, and index names from
`sqlite_master`, places them inside bracket-quoted `DROP` statements without
escaping, and executes the resulting SQL. A database-controlled identifier can
terminate that quoting context.

Use SQLite identifier escaping, preferably `%w` inside double-quoted
identifiers.

### Heterogeneous result-set comparison

`cql_rows_equal` verifies only reference count and reference offset
compatibility, then uses the first result set's row size to locate and compare
both rows. A smaller or incompatible second layout can be read out of bounds.

Require compatible row sizes and complete column layouts before comparing
rows.

### Blob-stream arithmetic overflow

`cql_cursor_from_blob_stream` calculates offset-table locations using signed
32-bit expressions involving caller- and blob-controlled values. Overflow can
invalidate the guard and lead to reads outside the offset table.

Validate the complete table with checked wide arithmetic, require monotonic
offsets within the blob, and avoid unaligned integer loads.
