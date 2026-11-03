---
title: "Appendix 4: The AI-Found Bugs of CQL"
weight: 4
---
<!---
-- Copyright (c) Rico Mariani
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## A different way of looking for bugs

**Study date:** November 2, 2026

**Discovery-era window:** May 15 through November 2, 2026

**Analyzed endpoint:** [`837956ba`](https://github.com/ricomariani/CG-SQL-author/commit/837956ba)

**Repository:** `ricomariani/CG-SQL-author`

[The Bugs of CQL](./02_bugs_of_cql.md) describes the human-found era. This
appendix picks up on May 15, 2026, when essentially all the new findings
started coming from AI-assisted analysis. Some were security problems, some
were ordinary bugs, and some were improvements to the tests themselves.
There were also a few proposals I declined, and I'll get to those.

The earlier article describes a compiler getting regular daily use from
hundreds of developers at Meta. CQL still gets that use, but not through this
open-source version. In particular, quoted identifiers are a feature of my
fork, and both public blob serialization facilities have been lightly used.
The internal backed-blob implementation was different and hardened separately.
Those differences in use explain quite a bit of what follows.

### How I put this together

An AI coding agent helped me review the history and individual fixes and
write this appendix. I checked its account against the code and supplied
the context about how we built and used CQL.

The window includes May 15's first blob and extension findings. The last
preceding mainline commit is
[`8793b00f`](https://github.com/ricomariani/CG-SQL-author/commit/8793b00f), dated
January 28, with no intervening mainline commits, so the comparison is
reproducible as:

```text
git log --first-parent 8793b00f..837956ba
git show <commit> -- <affected files>
```

The range has 73 first-parent commits, including documentation, releases,
tooling, and follow-ups to earlier fixes.

We split the large correctness proposal, #205, into smaller changes that
landed in PRs #207 through #253, along with additional security follow-ups.
I've used the final fixes for this account because several changed
considerably during review.

---

## How much did we find?

I count **68 findings** in this work: **52 compiler, runtime, build,
and sample bugs; 8 test/tooling problems; and 8 preventive changes**.
The shared canonical-name mistake counts once, for example, even though
it needed repairs in both emitters.

The UTF-8 work completed some earlier human-reported problems, so including
those repairs here doesn't give AI credit for the original reports.
I also keep the .NET fixture's ASan load failure separate from the 68
findings because it was a regression introduced during this work.

### Priority and security are separate questions

These are my retrospective **fix priorities**, rather than exploit-severity
scores. **Critical** covers hostile-data memory failures, urgent and broadly
disruptive failures in ordinary supported use, and demonstrated major security
impacts. **Important** covers serious wrong-code, wrong-result, or storage
failures. **Medium** covers more limited features, inputs, and configurations.
**Low** covers small test gaps and preventive work with no known failing
ordinary caller.

| Priority | Security bugs | Other correctness bugs | Test/tooling | Preventive | Total |
|---|---:|---:|---:|---:|---:|
| Critical | 6 | 0 | 0 | 0 | 6 |
| Important | 0 | 16 | 0 | 0 | 16 |
| Medium | 1 | 29 | 4 | 2 | 36 |
| Low | 0 | 0 | 4 | 6 | 10 |
| **Total** | **7** | **45** | **8** | **8** | **68** |

The security column is limited to the hostile-blob reader/update boundary
described below. I haven't put compiler crashes, bad generated text, or
missing internal contracts in that column without establishing a security
case.

### Bugs per KLOC

**Raw KLOC** counts all source lines, including comments, blank lines,
`#define`s, and other non-executable text. **Executable KLOC** counts source
lines with generated machine code associated with them, as reported by
coverage for a particular build.

For raw-line density, I count bugs and lines in the same set of files:
the root `sources/*.c` and `*.h` files except `unit_tests.c`, plus the grammar,
lexer, and Lua runtime. This excludes tests, generated distributions,
vendored SQLite, Python bindings, and the extension bridge.

| Measure | Count |
|---|---:|
| Core source before the audit, `8793b00f` | 89,419 lines |
| Core source after the fixes, `837956ba` | 90,377 lines |
| Bug findings within that source surface | 45 |
| Of those, security findings | 7 |
| Of those, other correctness findings | 38 |
| Additional preventive findings within that surface | 6 |
| Core bugs found per pre-audit raw KLOC | **0.50** |
| Core security bugs per pre-audit raw KLOC | **0.08** |
| Core other correctness bugs per pre-audit raw KLOC | **0.42** |

The other seven correctness findings belong to build support, samples, and
tools outside that denominator. Dividing all 68 findings by the compiler's
size would mix different sets of code and count preventive work as bugs.

The November 2 coverage report gives us the executable-line count:

| Coverage-report measure | Lines |
|---|---:|
| All executable lines | 39,789 |
| Of those, `unit_tests.c` | 291 |
| Production executable C lines, including grammar/lexer actions and code in headers | **39,498** |
| Production executable lines covered | **39,498 (100%)** |

Two of the 45 core bug findings were confined to the Lua runtime: negative
integer casts and partition-key encoding. The remaining **43 native
compiler/runtime findings** give approximately **1.09 bugs per executable
C KLOC**, split into **0.18 security** and **0.91 other correctness**.
This is a rough normalisation using the post-fix coverage build as a size
reference. It depends on that platform and build configuration, doesn't
include Lua runtime lines, and isn't a reconstructed pre-audit
executable-line count.

I think the code held up pretty well. This was a concentrated examination
of a mature implementation, including features with very little use.
The repairs were generally local, and many of the failures required inputs
or combinations that the existing tests had never tried.

### Where the findings clustered

The aggregate density hides quite a bit. In this file-level heatmap,
**each `*` represents a finding affecting that file**; preventive work
doesn't get a star. All paths are relative to `sources/`.

The size columns use the measures above: **raw KLOC** is the file size
at `8793b00f`, and **executable KLOC** comes from the post-fix November 2
coverage report. A dash means the file isn't represented in that report.

The core table includes every root C implementation file except `unit_tests.c`,
plus the lexer, grammar, and Lua runtime. Headers contribute to the aggregate
denominator above but have no separate bug sites in this inventory.

| Core implementation file | Raw KLOC | Executable KLOC | Findings | Theme |
|---|---:|---:|---|---|
| `cqlrt_common.c` | 7.228 | 3.406 | `**********` | Blob validation, arithmetic, update sizing, serializer growth |
| `sem.c` | 27.347 | 13.533 | `******` | Numeric ranges, empty sets, aliasing, rowid and scalar properties |
| `cg_lua.c` | 5.892 | 2.902 | `*****` | Comment boundaries, canonical names, conversions, wrapper locals |
| `encoders.c` | 0.545 | 0.352 | `*****` | Scan bounds, C escapes, UTF-8/JSON bytes, canonical names |
| `cg_c.c` | 9.027 | 4.375 | `****` | Provenance comments, signed hex, trace strings, canonical names |
| `cg_query_plan.c` | 1.040 | 0.423 | `***` | CQL/JSON name encoding, statistics scope |
| `cg_schema.c` | 2.263 | 1.316 | `***` | Dynamic/static DROP names, recreate checksums |
| `cql.l` | 0.709 | 0.514 | `***` | Include-path bounds, scanner ownership, integer literals |
| `gen_sql.c` | 6.704 | 3.843 | `***` | Signed hex, expression grouping, virtual-table names |
| `ast.c` | 2.577 | 1.058 | `**` | Indentation bounds, recursive macro expansion |
| `cg_json_schema.c` | 2.944 | 1.777 | `**` | Constraint identity, expression string encoding |
| `cql.y` | 4.170 | 1.573 | `**` | Scanner ownership, CLI and line-directive numbers |
| `cqlrt.lua` | 1.965 | - | `**` | Negative integer casts, partition-key collisions |
| `eval.c` | 1.226 | 0.529 | `*` | Signed hexadecimal interpretation |
| `flow.c` | 0.724 | 0.224 | `*` | Jumping branches and inherited facts |
| `bytebuf.c` | 0.066 | 0.036 | 0 | Preventive self-append contract only |
| `cg_common.c` | 0.236 | 0.099 | 0 | No counted bug |
| `cg_stats.c` | 0.188 | 0.076 | 0 | No counted bug |
| `cg_test_helpers.c` | 1.302 | 0.625 | 0 | No counted bug |
| `charbuf.c` | 0.200 | 0.096 | 0 | Preventive format-alias contract only |
| `compat.c` | 0.101 | 0.043 | 0 | No counted bug |
| `cqlrt.c` | 0.310 | 0.140 | 0 | No counted bug |
| `crc64xz.c` | 0.110 | 0.007 | 0 | No counted bug |
| `list.c` | 0.035 | 0.017 | 0 | No counted bug |
| `minipool.c` | 0.113 | 0.044 | 0 | No counted bug |
| `printf.c` | 0.490 | 0.242 | 0 | No counted bug |
| `result_set_extension.c` | 0.142 | - | 0 | No counted bug |
| `rewrite.c` | 6.309 | 1.591 | 0 | No counted bug |
| `rt.c` | 0.167 | 0.011 | 0 | No counted bug |
| `sha256.c` | 0.183 | 0.089 | 0 | Preventive digest-storage change only |
| `symtab.c` | 0.323 | 0.149 | 0 | No counted bug |

The other affected production/build files cover eight findings, seven
additional to the core. The binding-name finding also appears in the core
encoder, but these files' lines aren't in the core denominator.

| Other production/build file | Raw KLOC | Findings | Theme |
|---|---:|---|---|
| `cqljson/cqljson.py` | 0.694 | `**` | SQL encoding, reconstructed attribute values |
| `dotnet_demo/cqlcs.py` | 1.013 | `**` | Projection names, actual blob marshalling |
| `sqlite3_cql_extension/cql_sqlite_extension.c` | 0.501 | `**` | Unsupported OBJECTs, repeated-filter ownership |
| `cqlrt_cf/cqlobjc.py` | 0.314 | `*` | Projection names, wrapper-member collisions |
| `dotnet_demo/CQLInterop.cs` | 0.227 | `*` | NULL/empty blob results and native-buffer cleanup |
| `dotnet_demo/cql_interop.c` | 0.129 | `*` | NULL/empty blob ABI and native copying |
| `java_demo/cqljava.py` | 1.031 | `*` | Projection identifier encoding and member collisions |
| `make_amalgam.sh` | 0.240 | `*` | Windows amalgam's `PATH_MAX`/`_MAX_PATH` mismatch |
| `objc_full/cql_objc_full.py` | 0.921 | `*` | Projection names, matching declarations and definitions |
| `sqlite3_cql_extension/cqlsqlite3extension.py` | 0.710 | `*` | SQL/C name and literal encoding |

For test/tooling findings, both size columns count raw lines, and a
dash means the file didn't exist before the audit. Two drivers and some
checks were added during this work, so these aren't all defects in the
pre-audit checkout.

| Test/tooling file | Raw KLOC (pre-audit) | Raw KLOC (post-fix) | Findings | Theme |
|---|---:|---:|---|---|
| `test/run_test_client.c` | 1.228 | 1.248 | `***` | Incomplete results, physical schema checks, PRNG overflow |
| `cql-verify/make.sh` | 0.002 | 0.003 | `*` | Regeneration errors ignored |
| `json_test/json_test.l` | 0.175 | 0.175 | `*` | Over-permissive key casing |
| `test.sh` | 1.208 | 1.519 | `*` | Encoding check omitted from default run |
| `test/cqltest.c` | 0.041 | 0.054 | `*` | Close errors ignored |
| `test/query_plan_encoding_test.c` | - | 0.047 | `*` | Close errors ignored |
| `test/query_plan_statistics_test.c` | - | 0.034 | `*` | Close errors ignored |
| `test/query_plan_test.c` | 0.030 | 0.036 | `*` | Close errors ignored |
| `test/test_helpers_test.c` | 0.086 | 0.092 | `*` | Close errors ignored |
| `upgrade/upgrade_test.c` | 0.214 | 0.255 | `*` | Transaction errors lost or ignored |

A single finding can require changes in several files, as the integer literal
repair did across the lexer, semantic analysis, constant evaluation, C
emission, and SQL emission. I count it once in the 52, but once in each
affected file here.
The production/build tables therefore contain
**65 stars for 52 unique findings**; the test/tooling table has **12 for 8**.
I haven't assigned stars to new helpers, regression files, or mechanical
caller adaptations merely because the patch touched them. The C hex-escape
repair, for example, belongs to `encoders.c`, not every generator that uses
its helpers.

Attribution also explains two less obvious placements. The Windows
`PATH_MAX`/`_MAX_PATH` mismatch came from the definition emitted by
`make_amalgam.sh`, outside the core source denominator. Conversely, #245's
binding-name finding includes
the core `encoders.c` correction for ordinary capital-X identifiers. That
finding belongs in the core count as well as in the sample rows.

The small encoder has five findings; the semantic analyzer has six in
27 raw KLOC. The rewrite implementation has none in 6 raw KLOC. The blob
runtime alone has ten, including all seven security findings. Much of the
concentration is at representation boundaries: stored bytes, target-language
text, and names crossing between systems.

I find that distribution more informative than a uniform 0.50 bugs per raw KLOC.
We didn't measure equal review effort or equal exposure in use, and a zero
only means we found no bug there in this review. The table can't tell us
each file's remaining defect rate.

### Compared with the human-found era

My recollection of the heavily used Meta version is roughly **12 operational
bugs per year**. Using the same 89.419 raw KLOC merely as a scale reference
gives about **0.13 bugs per raw KLOC per year**. The earlier appendix's
narrower C/header denominator, 82.575 raw KLOC, gives about **0.15**.

| Human-era observation | AI-assisted audit |
|---|---|
| Roughly 12 operational bugs per year, from maintainer recollection | 52 compiler/runtime/build/sample bug findings over this review |
| Daily use by hundreds of developers at Meta | Targeted examination of the OSS fork, including lightly used features |
| About 0.13 operational bugs per raw KLOC/year at the reference size | 0.50 core bug findings per raw KLOC in a concentrated pass |

We don't have a comparable census of every human-found development-time bug,
and an annual field rate has different units and inputs from an audit yield.
I wouldn't turn these numbers into a speed multiplier. What interests me is
the additional cases this examination reached after years of development,
testing, and operational use.

The counting notes near the end explain the grouping decisions.

### Fewer maintainers, fewer users

As the public fork lost active maintainers and users, it also lost independent
review and ad hoc testing. Fewer people were questioning changes, and fewer
applications were exercising combinations I hadn't thought to put in the
test suite.

The primary-author counts for first-parent, non-merge commits through the
studied endpoint show how concentrated maintenance became:

| Period, by author date | All commits | Mine | My share |
|---|---:|---:|---:|
| Entire public history | 2,251 | 1,746 | 77.6% |
| November 2, 2022 onward | 1,211 | 1,108 | 91.5% |
| January 1, 2024 onward | 733 | 722 | 98.5% |

The two largest other primary-author totals are Winnie Quinn's 126 and Raoul
Foaleng's 104. Their last mainline commits were
[July 28, 2022](https://github.com/ricomariani/CG-SQL-author/commit/4bb2e0f03b9f)
and [March 15, 2023](https://github.com/ricomariani/CG-SQL-author/commit/790e6f7b7738),
respectively.

There were important later contributions too. Joris Garonian introduced the
[SQLite extension generator in 2024](https://github.com/ricomariani/CG-SQL-author/commit/fad49eeef3d5),
and `amyworrall` contributed
[UTF-8 encoding work in 2025](https://github.com/ricomariani/CG-SQL-author/commit/8818eb4520ee).

These are authorship counts, not counts of reviewers, users, or internal
Meta work. AI-assisted changes also remain under my author name.

Keeping the compiler at 100% line coverage didn't replace that lost feedback.
The AI supplied another detailed examination of code that was increasingly
being written, tested, and reviewed by the same person.

---

## The recurring themes

Several things kept coming up:

1. **Light use.** Some failures were so basic that an actual use-case would
   have exposed them immediately. The .NET blob sample returned placeholder
   bytes.
2. **Test diversity.** We had covered the lines, but missed negative fractions,
   long payloads, unusual names, or another combination of features.
3. **QIDs.** Quoted identifiers changed a major compiler invariant. I had
   tested them extensively, but missed some places identifiers could appear.
4. **Missing validation.** I'd meant to check at another level, then ended
   up forgetting to check at all.
5. **Wrong assumptions.** The C hex-escape rules surprised me.
6. **Basic error handling in test drivers.** We were ignoring some errors
   that could make a test result misleading.
7. **Checking the result.** JSON can parse and still contain the wrong string.
   SQL can execute and create a table with the wrong name.

### Fresh eyes

The AI analysis was ruthless and tireless, bringing fresh eyes to code I
had been looking at for years and reconsidering assumptions along the way.
Does this count really fit? Is this name already encoded? Who checked this
argument? What did the test actually verify?

Most of the findings were worth fixing, though a few proposals were unwise,
beyond what I expect the system to do, or truly uneconomical. I spent a fair
amount of the review working out the smallest sensible fix.

---

## Security findings

### Which findings belong here?

A security finding needs an attacker, something they control, and a trust
boundary they can cross. A buffer overrun or broken quoting can be a horrible
correctness bug without giving anyone new authority, so calling the mechanism
"memory corruption" or "injection" doesn't establish the security case.

The AI sometimes found a real bug but hadn't established that a trust boundary
was crossed, or hadn't correctly identified the boundary. I still wanted
those correctness fixes; I just needed a reason to call them security
findings.

For example, the compiler's source author already controls the program they
are asking it to generate. Giving that author control of trusted program
text or internal call arguments doesn't establish an attack. What is the
compiler expected to protect from them? Inventing a build service that
accepts contributed source doesn't answer that question.

### Serialized data: validate the whole representation

The blob readers do have an explicit requirement to handle hostile bytes.
An attacker who can supply a blob controls its counts, offsets, types, and
payload, and the reader has to reject malformed input without out-of-bounds
reads or writes. That is the trust boundary in applications that accept
blobs from less-trusted sources.

The backed-table UDF sequence began on May 15 with
[`2ed3ac9e`](https://github.com/ricomariani/CG-SQL-author/commit/2ed3ac9e).
It checked computed blob shapes and selected payload ranges and corrected
inconsistent type-code handling between creation passes. July's
[`1432fa66`](https://github.com/ricomariani/CG-SQL-author/commit/1432fa66)
then extended validation to **retained** variable fields before updates
copied them.

The old reader made the assumption explicit:

```c
// we know enough to make the shape and get the offsets; the variable size is
// not computed but that is of no import since we are not yet validating all
// the internal offsets (blobs are assumed to be well formed for now)
```

The backed-table UDFs had started as a test implementation and acquired the
hostile-input requirement as they became useful outside those tests. The
cursor serializer had expected hostile input from the beginning, but both
facilities were lightly used.

Here is the May correction at the shape check:

```diff
 cql_key_blob_shape shape;
 cql_compute_key_blob_shape(&shape, header.column_count, 0);
+if (shape.variable_offset > original_bytes) {
+  goto cql_error;
+}
```

And at the point where a stored string's range was about to become a SQLite
result:

```diff
 uint64_t val = cql_read_big_endian_u64(b + storage_offset);
 uint32_t len = val & 0xffffffff;
 uint32_t offset = val >> 32;
+if ((uint64_t)offset + len > original_bytes) goto cql_error;
 const char *text = (const char *)b + offset;
 sqlite3_result_text(context, text, (int)len, SQLITE_TRANSIENT);
```

`header.column_count`, `offset`, and `len` come from the supplied blob.
Checking the fixed header alone cannot establish that the computed table or
payload fits. An update also reads and copies every preserved variable
field, so July's correction checked those fields and their string terminators
as well as the replacement.

Almost always, I'd intended to do these checks at another level and then
forgot to check at all. A missing branch can't show up as an uncovered line,
so I had to go back and ask which function actually established the
precondition.

[`3b2b0228`](https://github.com/ricomariani/CG-SQL-author/commit/3b2b0228)
rejected unknown serialized type codes, and
[`2c3b89d0`](https://github.com/ricomariani/CG-SQL-author/commit/2c3b89d0)
completed an important error-policy change: malformed arguments or storage
produce `SQLITE_ERROR`, rather than letting a query continue as though the
value were merely absent. A valid sparse value blob with an absent nullable
field can still return `NULL`. That distinction matters for ordinary corrupt
data too, with no attacker involved.

#### Overlapping fields

The later overlap repair, [#211](https://github.com/ricomariani/CG-SQL-author/pull/211),
found another assumption: two serialized fields could each describe a
valid range while sharing some or all of their bytes. The updater copied
each logical field separately, but sized the output by starting from the
physical input length and adjusting changed fields.

Suppose two string descriptors share `"abc"` and its terminator. The stored
string length is three, but each output copy needs four bytes:

```text
Input:
  field 0 -> payload offset P, string length 3
  field 1 -> payload offset P, string length 3
  bytes at P: 61 62 63 00                 "abc\0"

Rewritten output, with separate copies:
  field 0 -> first copy,  4 bytes including terminator
  field 1 -> second copy, 4 bytes including terminator
  payload: 61 62 63 00 61 62 63 00
```

Both source ranges pass a bounds check, but copying them needs eight payload
bytes. Starting from the four physical input bytes underallocates the
destination even when no field is being replaced.

I chose to keep accepting overlap rather than make a larger compatibility
change. The validator now computes the sum of validated logical field
lengths, and both key and value updates start with that sum before adjusting
for replacements and deletions. The regression inputs were only 47 bytes
for a key blob and 71 bytes for a value blob.

The normal writer emits separate payloads, so ordinary round-trip tests
could never produce this case. A reader of hostile data has to handle
representations outside its own writer's output.

#### A four-byte header was enough to defeat the old stream arithmetic

The May 15 stream fix,
[`c5eddda7`](https://github.com/ricomariani/CG-SQL-author/commit/c5eddda7),
corrected a check that proved only the start of an offset word was present.
The October follow-up,
[#214](https://github.com/ricomariani/CG-SQL-author/pull/214), found that the
new `(index + 2) * 4` expression could itself overflow. A four-byte blob
declaring a huge count was enough to reach the bad arithmetic.

We needed to prove that the complete offset table fit before reading from
it, then validate the selected range:

```text
table_end <= selected_start <= selected_end <= blob_length
```

The old guard tried to check the length after doing the arithmetic:

```c
if (index < 0 || index >= count || (index + 2) * 4 > len) {
  goto error;
}
```

For `index = 536870910`, `(index + 2) * 4` exceeds signed 32-bit range before
the length comparison can protect us.

Here is the corrected read path from
[`957db34a`](https://github.com/ricomariani/CG-SQL-author/commit/957db34a).
`b` is the input blob; `dyn_cursor` describes the destination row:

```c
cql_code cql_cursor_from_blob_stream(
  sqlite3 *_Nonnull db,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_blob_ref _Nonnull b,
  cql_int32 index)
{
  cql_contract(b);
  cql_bool *has_row = dyn_cursor->cursor_has_row;
  const uint8_t *bytes = (const uint8_t *)cql_get_blob_bytes(b);
  const uint32_t len = (uint32_t)cql_get_blob_size(b);

  if (len < 4) {
    goto error;
  }

  uint32_t count;
  memcpy(&count, bytes, sizeof(count));
  if (count > len / sizeof(uint32_t) - 1) {
    goto error;
  }
  if (index < 0 || (uint32_t)index >= count) {
    goto error;
  }

  uint32_t end;
  memcpy(&end, bytes + ((uint32_t)index + 1) * sizeof(end), sizeof(end));
  if (end > len) {
    goto error;
  }

  uint32_t table_end = (count + 1) * sizeof(uint32_t);
  uint32_t start = table_end;
  if (index > 0) {
    memcpy(&start, bytes + (uint32_t)index * sizeof(start), sizeof(start));
  }
  if (start < table_end || start > end) {
    goto error;
  }

  return cql_cursor_from_bytes(dyn_cursor, bytes + start, end - start);

error:
  *has_row = false;
  cql_clear_references_before_deserialization(dyn_cursor);
  return SQLITE_ERROR;
}
```

The division check establishes that `(count + 1) * sizeof(uint32_t)` will
fit before the code computes it. It also bounds the selected offset-word
read. `memcpy` loads the native-format words without requiring the blob's
address to have integer alignment. The existing byte order is unchanged.

These are three of the regression inputs:

```sql
cursor cases for
  -- Four bytes containing count INT32_MAX; no offset table follows.
  select x'FFFFFF7F' as b, 2147483646 as idx
  union all
  -- Count 536,870,912; the selected index overflowed the old guard.
  select x'00000020' as b, 536870910 as idx
  union all
  -- Count UINT32_MAX; count + 1 used to wrap.
  select x'FFFFFFFF' as b, 0 as idx;
```

Those byte spellings describe the little-endian test environment, and none
contains enough bytes for its declared offset table. Each must fail before
an offset is read.

The rejection test also starts with an existing cursor row containing a
string reference. After each failed decode it checks:

```sql
EXPECT_EQ!(hit, true);  -- The call raised SQLITE_ERROR.
EXPECT_EQ!(C, false);   -- The old row is no longer present.
EXPECT_EQ!(C.z, null);  -- Its string reference has been cleared.
```

Between them, the regressions exercise truncated shapes, arithmetic overflow,
offsets inside the table, invalid indices, and rejection while the destination
already owns data. Random byte corruption alone would be unlikely to cover
all of those cases.

#### Counter width was a separate representation limit

[#219](https://github.com/ricomariani/CG-SQL-author/pull/219) rejected type
headers beyond 65,535 fields **before** 16-bit counters wrapped and extra fields
could be checked against metadata beyond the destination. A roughly 64 KiB
hostile header makes that boundary realistic.

We kept the existing format limit, with a contract protecting compiler-side
narrowing and an error for malformed wire input. Bit indices needed a
separate widening because a nullable Boolean can contribute both a presence
bit and a value bit. C and Lua use the same field-count policy.

---

## Coverage left input dimensions untested

The compiler's 100% line coverage was useful throughout this work because it
forces reachable syntax and AST shapes through fail-fast handlers. But an
executed line doesn't tell us which values, sizes, configurations, or
combinations have passed through it.

The failures exposed some very different gaps: a serializer had seen every
field type without seeing a moving allocation, a string helper had seen
comment markers without seeing an empty buffer, and JSON tests had exercised
an encoder without comparing decoded Unicode text on both signed- and
unsigned-char hosts.

### A moving allocation changes the meaning of a saved pointer

The cursor serializer writes type information, a bit vector recording
nullable-field presence and Boolean values, and then the field payloads.
The old code retained the bit vector's address:

```c
uint8_t *bits = cql_bytebuf_alloc(b, bitvector_bytes_needed);
memset(bits, 0, bitvector_bytes_needed);
```

Small rows didn't grow the buffer, but a long string or blob append could
grow `b` and free the allocation containing `bits`. The next nullable or
Boolean field still did:

```c
cql_setbit(bits, nullable_index);
```

The repair in [#218](https://github.com/ricomariani/CG-SQL-author/pull/218)
retained the offset and resolved the address at each write:

```c
uint32_t bits_offset = b->used;
memset(cql_bytebuf_alloc(b, bitvector_bytes_needed), 0, bitvector_bytes_needed);
```

```c
static void cql_setbit(
  cql_bytebuf *_Nonnull b,
  uint32_t bits_offset,
  uint16_t index)
{
  uint8_t *bytes = (uint8_t *)b->ptr + bits_offset;
  bytes[index / 8] |= (1 << (index % 8));
}
```

The later field-count repair widened that last index to 32 bits; this repair
addressed the lifetime of the interior pointer across appends.

The declared field order matters in this first half of the runtime
regression:

```sql
[[blob_storage]]
create table serialization_growth_blob(
  large_text text!, required_flag bool!, nullable_int int,
  nullable_long long, nullable_real real, nullable_flag bool,
  nullable_text text, final_flag bool!, nullable_blob blob,
  final_nullable_flag bool
);

TEST!(blob_serialization_survives_buffer_growth,
begin
  declare C cursor like serialization_growth_blob;
  fetch C from values(
    printf("%1025s", "x"), true, 22, 33L, 3.14, true,
    printf("%4097s", "y"), false, blob_from_string(printf("%8193s", "z")), true
  );
  let encoded := C:to_blob;
  declare D cursor like serialization_growth_blob;
  D:from_blob(encoded);

  EXPECT!(D);
  EXPECT_EQ!(D.large_text, C.large_text);
  EXPECT_EQ!(D.required_flag, C.required_flag);
  EXPECT_EQ!(D.nullable_int, C.nullable_int);
  EXPECT_EQ!(D.nullable_long, C.nullable_long);
  EXPECT_EQ!(D.nullable_real, C.nullable_real);
  EXPECT_EQ!(D.nullable_flag, C.nullable_flag);
  EXPECT_EQ!(D.nullable_text, C.nullable_text);
  EXPECT_EQ!(D.final_flag, C.final_flag);
  EXPECT_EQ!(D.nullable_blob, C.nullable_blob);
  EXPECT_EQ!(D.final_nullable_flag, C.final_nullable_flag);
end);
```

The 1,025-byte string exceeds the initial 1,024-byte buffer, and the longer
string and blob force further growth with bit writes after each. The
second half of the test repeats that growth with absent nullable fields:
their presence bits must remain clear while the later nonnull Boolean
still writes to the current allocation.

Calling a row "small" or "large" misses what matters here. We needed writes
before growth, after one growth, and after several growths.

### Empty after filtering is still empty

The comment-marker scanner had a much smaller version of the same coverage
problem. Its buffer length includes the terminating zero, so an empty buffer
has `used == 1`:

```diff
-for (uint32_t i = 0; i < b->used - 2; i++) {
+for (uint32_t i = 0; i + 2 < b->used; i++) {
```

Unsigned subtraction made the old empty-input bound enormous, which ASan
reproduced as an out-of-bounds scan.
[#210](https://github.com/ricomariani/CG-SQL-author/pull/210) added this
complete helper test:

```c
static bool test_comment_marker_scan() {
  CHARBUF_OPEN(temp);

  cg_remove_slash_star_and_star_slash(&temp);
  bool result = temp.used == 1 && !strcmp(temp.ptr, "");

  const char *inputs[] = { "/", "*", "/*", "*/", "/* */", "text/*", "text*/" };
  const char *outputs[] = { "/", "*", "/+", "+/", "/+ +/", "text/+", "text+/" };
  for (uint32_t i = 0; i < sizeof(inputs) / sizeof(inputs[0]); i++) {
    bclear(&temp);
    bprintf(&temp, "%s", inputs[i]);
    uint32_t used = temp.used;
    cg_remove_slash_star_and_star_slash(&temp);
    result &= temp.used == used && !strcmp(temp.ptr, outputs[i]);
  }

  CHARBUF_CLOSE(temp);
  return result;
}
```

Along with the empty case, the test checks that changing comment markers
preserves the logical length.

Filtering supplied another empty case in
[#222](https://github.com/ricomariani/CG-SQL-author/pull/222). An enum could
have declarations but no public members after hidden members were excluded.
The deduplication bound `enum_count - 1` then underflowed. A test of an empty
declaration wouldn't cover that route to an empty working set. We needed an
all-hidden declaration and the ordinary diagnostic for the resulting switch.

### A heavily used format still had untested paths

JSON schema had heavy use, and its full-string encoder had learned to
preserve valid UTF-8, but the pretty-quoted SQL path still encoded individual
bytes. For the UTF-8 sequence `E2 80 A2`, representing U+2022, it emitted:

```json
"\u00e2\u0080\u00a2"
```

A syntax validator accepts that JSON even though its value has three
characters in place of the intended one.

There was a separate host-configuration assumption in the byte fallback.
Here is the reduced change to that logic:

```diff
-if (c < 32) {
-  uint32_t ch = (uint32_t)c;
-  ch &= 0xff;
+uint32_t ch = (uint32_t)(unsigned char)c;
+if (ch < 32 || ch >= 0x80) {
   bprintf(output, "\\u00");
   emit_hex_digit(ch >> 4, output);
   emit_hex_digit(ch & 0xf, output);
```

On a signed-char host, high bytes happened to satisfy the old condition.
On an unsigned-char host, an isolated invalid high byte could pass through
raw. The UTF-8 repair and the signedness repair are separate entries in the
count even though they landed together in
[#238](https://github.com/ricomariani/CG-SQL-author/pull/238).

Users had been reporting JSON problems for years, and I hadn't followed
through with enough test diversity. The final tests compare decoded
attribute and SQL strings through both encoders and run unsigned-char
configurations. They retain the established malformed-byte policy, including
escaping a sequence followed by an extra continuation byte.

Ordinary JSON consumers supplied lots of use without supplying these
combinations of encoding path, input bytes, and host signedness. I had
much the same experience with schema upgrade: reaching 100% coverage was
followed by a long period of discovering more input combinations.

### Bounds belong to the representation actually used

The include-path overflow,
[`4867d6a4`](https://github.com/ricomariani/CG-SQL-author/commit/4867d6a4),
survived a check that looked relevant. `realpath` bounded the resolved name,
but the subsequent `strcpy(ambient_path, path.ptr)` copied the original
spelling into `char ambient_path[PATH_MAX]`. Enough redundant `./` segments
can make the spelling arbitrarily long while resolving to an existing short
path. Pool-backed storage removed the fixed destination.

The Windows/amalgam path in
[#204](https://github.com/ricomariani/CG-SQL-author/pull/204) had a related
size disagreement between two macros. `make_amalgam.sh` emitted
`#define PATH_MAX 255`, and the lexer allocated `char resolved_path[PATH_MAX]`.
The Windows `Realpath` wrapper passed that buffer to `_fullpath` with
`_MAX_PATH` as the size limit, allowing it to write more bytes than the
destination could hold. The fix was `#define PATH_MAX _MAX_PATH`, so the
allocation matches the limit passed to `_fullpath`.

The faulty line was a `#define`, so it wasn't even an executable line for
coverage to count. The size mismatch could survive complete coverage of the
code that used it.

The diagnostic printer had yet another size dimension: a 2,100-`NOT` AST
could exhaust its indentation buffer. Its
[#215](https://github.com/ricomariani/CG-SQL-author/pull/215) repair truncates
diagnostic descent with a marker while leaving accepted SQL nesting alone.

---

## The QID invariant changed, and I missed some consumers

I developed QIDs test-first, with a burndown list of every major identifier
usage I could think of, and made dozens of passes over the work. I tested
the crap out of them, and on the whole I think we did well. But even I can't
remember all the places identifiers can creep in.

This was a major invariant change. Many emitters used to print a stored
name directly; with QIDs, each one has to turn that name into the right form
for its output.

There are several representations to keep straight:

| Representation | Example or obligation |
|---|---|
| Source spelling | A CQL backtick-quoted name, possibly containing spaces or punctuation |
| Internal name | An encoded identifier such as `X_docX20store`, plus the AST's quoted status |
| Semantic identity | Case-insensitive resolution with a canonical declared spelling |
| SQL identifier | Decode and quote for the target SQL syntax |
| CQL string containing a name | Decode the name, then encode it as string data |
| JSON metadata | Use the decoded name consistently with declarations |
| Host-language accessor | Apply that sample binding's legal-name and collision policy |

An ordinary `CREATE TABLE` test could pass while virtual tables, constraint
metadata, generated drops, query-plan programs, or a language wrapper still
used the old rule. Adding more examples through the already-correct emitter
would do nothing for those forgotten consumers.

### Successful execution can use the wrong name

Virtual-table creation was one such consumer.
[#240](https://github.com/ricomariani/CG-SQL-author/pull/240) fixed a path that
printed the stored string directly. Here is a complete CQL declaration of
the kind that failed:

```sql
create virtual table if not exists `doc store`
  using fts4(content) as (content text);
```

The old SQLite output used the internal name:

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS X_docX20store USING fts4(content);
```

SQLite happily creates `X_docX20store`, so the correctly rendered insert for
the same source name fails:

```sql
INSERT INTO [doc store](content) VALUES ('hello');
-- no such table: doc store
```

The compiler had retained the wrong thing for printing:

```diff
-EXTRACT_STRING(name, create_table_name_flags->right);
+EXTRACT_NAME_AST(table_name_ast, create_table_name_flags->right);
@@
-gen_printf("%s USING %s", name, module_name);
+gen_name(table_name_ast);
+gen_printf(" USING %s", module_name);
```

`gen_name` has the identifier AST, including quoted status, and selects the
spelling for CQL or SQLite output. A quoted ordinary name or keyword also
needs that status even when its stored bytes don't contain a hex encoding.

This integration check takes the compiler's emitted SQLite schema and
verifies the catalog name, data operations, and removal:

```python
import sqlite3

def check_virtual_table(sql):
    with sqlite3.connect(":memory:") as database:
        database.executescript(sql)
        database.executescript(sql)  # IF NOT EXISTS must remain harmless.
        actual = database.execute(
            "SELECT name FROM sqlite_master "
            "WHERE sql LIKE 'CREATE VIRTUAL TABLE%'"
        ).fetchall()
        assert actual == [("doc store",)]
        database.execute(
            "INSERT INTO [doc store](content) VALUES (?)", ("hello",)
        )
        assert database.execute(
            "SELECT content FROM [doc store]"
        ).fetchall() == [("hello",)]
        database.execute("DROP TABLE [doc store]")
        assert database.execute(
            "SELECT name FROM sqlite_master "
            "WHERE sql LIKE 'CREATE VIRTUAL TABLE%'"
        ).fetchall() == []
```

The actual regression also reparses emitted CQL and varies seven name
classes across three module-argument forms, exercising other consumers of
the same source declaration.

[#230](https://github.com/ricomariani/CG-SQL-author/pull/230) found the same
representation mistake in deleted or unsubscribed recreate-table drops.
An encoded-name lookalike control proved that the intended table was removed
without deleting an unrelated table with the internal-looking spelling.

### A name can be encoded correctly in the wrong language

The query-plan code fixed in
[#242](https://github.com/ricomariani/CG-SQL-author/pull/242) decoded
`no_table_scan` names but then put them between raw CQL quotes. A literal
backslash followed by `t` became a tab, so the generated program could compile
yet stop matching the actual plan text and silently lose its alert.

The same PR fixed runtime graph and alert strings inserted into JSON without
JSON escaping. We had escaped statement text and missed these other fields.

For a name containing a literal backslash followed by `t`, the relevant
generated CQL strings are:

```sql
"backslash\t"   -- Wrong: CQL decodes a tab.
"backslash\\t"  -- Correct: CQL decodes a backslash and the letter t.
```

Both strings are legal source, but only one can match the literal name in
SQLite's plan text. Successful generation or compilation wouldn't catch
the missing scan alert.

The runtime helper is ordinary C/Lua string encoding. It does not depend on
SQLite JSON support or database access.

Constraint metadata had another name mismatch, fixed in
[#241](https://github.com/ricomariani/CG-SQL-author/pull/241):

```text
Table declaration's JSON name:       parent table
Foreign key's referenceTable:        X_parentX20table
```

The repair normalized foreign-key and primary-key metadata to use the same
decoded names as the table and column declarations. The regression resolves
each foreign-key reference against those declarations, because parsing JSON
or checking a field's string type can't establish that identity.

The same PR separately JSON-encoded index and predicate expressions, where
raw quote wrapping could produce invalid JSON or silently reinterpret
backslashes.

### Names also reach dynamic SQL

Dynamic schema-drop code obtained names from `sqlite_master` and put them
inside square brackets. The source name `identifier_table]bracket` therefore
became an invalid identifier in the generated statement.

The correction in
[#212](https://github.com/ricomariani/CG-SQL-author/pull/212) covered the table,
trigger, view, and index paths. These are excerpts of the C generator;
`%%s` leaves a `%s` placeholder for the generated CQL procedure:

```diff
-bprintf(decls, "  CALL cql_exec_internal(printf('DROP TABLE IF EXISTS [%%s]', table_name));\n");
+bprintf(decls, "  CALL cql_exec_internal(printf('DROP TABLE IF EXISTS \"%%s\"', replace(table_name, '\"', '\"\"')));\n");
@@
-bprintf(output, "    CALL cql_exec_internal(printf('DROP TRIGGER [%%s];', C.name));\n");
+bprintf(output, "    CALL cql_exec_internal(printf('DROP TRIGGER \"%%s\";', replace(C.name, '\"', '\"\"')));\n");
@@
-bprintf(output, "    CALL cql_exec_internal(printf('DROP VIEW [%%s];', C.name));\n");
+bprintf(output, "    CALL cql_exec_internal(printf('DROP VIEW \"%%s\";', replace(C.name, '\"', '\"\"')));\n");
@@
-bprintf(output, "    CALL cql_exec_internal(printf('DROP INDEX [%%s];', C.name));\n");
+bprintf(output, "    CALL cql_exec_internal(printf('DROP INDEX \"%%s\";', replace(C.name, '\"', '\"\"')));\n");
```

The executable regression establishes the objects, invokes the generated
drop paths, and checks both removal and unrelated data. Here is the
schema-object portion, with its setup and verification:

```sql
create proc prepare_quoted_schema_objects()
begin
  create table identifier_host (value int);
  insert into identifier_host values (42);
  declare names cursor for select ']bracket' suffix
    union all select '"quote' suffix;
  loop fetch names
  begin
    let view_name := printf('identifier_view%s', names.suffix);
    let trigger_name := printf('identifier_trigger%s', names.suffix);
    let index_name := printf('identifier_index%s', names.suffix);
    call cql_exec_internal(printf(
      'CREATE VIEW "%s" AS SELECT * FROM identifier_host',
      replace(view_name, '"', '""')));
    call cql_exec_internal(printf(
      'CREATE TRIGGER "%s" AFTER INSERT ON identifier_host BEGIN SELECT 1; END',
      replace(trigger_name, '"', '""')));
    call cql_exec_internal(printf(
      'CREATE INDEX "%s" ON identifier_host(value)',
      replace(index_name, '"', '""')));
  end;
end;

create proc verify_quoted_schema_drops()
begin
  if (select exists(select 1 from sqlite_master
    where name in ('identifier_view]bracket', 'identifier_view"quote',
      'identifier_trigger]bracket', 'identifier_trigger"quote',
      'identifier_index]bracket', 'identifier_index"quote'))) then
    printf_stderr("ERROR! quoted schema objects were not dropped\n");
    throw;
  end if;
  if (select count(*) from identifier_host) != 1 or
     (select value from identifier_host) != 42 then
    printf_stderr("ERROR! schema drops modified unrelated data\n");
    throw;
  end if;
  drop table identifier_host;
end;
```

`cql_exec_internal` executes the constructed SQL; `printf_stderr` reports
test failures. The harness calls setup immediately before the exclusive
upgrade at the relevant version boundary and verification immediately after.
The host table remains subscribed, so its row must survive while the
unmanaged objects disappear.

The targeted table-helper test separately covers brackets and double quotes:

```sql
create proc verify_quoted_table_drops()
begin
  declare names cursor for select 'identifier_table]bracket' name
    union all select 'identifier_table"quote' name;
  loop fetch names
  begin
    call cql_exec_internal(printf('CREATE TABLE "%s"(value)',
      replace(names.name, '"', '""')));
    call test_drop_table_helper(names.name);
    if (select exists(select 1 from sqlite_master where name = names.name)) then
      printf_stderr("ERROR! quoted table %s was not dropped\n", names.name);
      throw;
    end if;
  end;
end;
```

`test_drop_table_helper` is the generated table-drop helper under the test
prefix. Its C harness temporarily installs the helper's dictionary, runs
this procedure, and restores the previous dictionary. Without that setup,
the test could fail before reaching the identifier operation.

These tests demonstrate that valid catalog names broke the generated
statements; they don't establish attacker control or a gain in SQL authority.

### Identity and output spelling are different

[#232](https://github.com/ricomariani/CG-SQL-author/pull/232) repaired C and Lua
emitters that used a reference's source spelling instead of its resolved
canonical name. CQL resolves names without case sensitivity; C and Lua do not.
The same cursor field referred to with different case could therefore produce
an undeclared C name or the wrong Lua field/global.

At the target-language level, the mistake is equivalent to:

```c
struct row {
  int Total;
};

void update(struct row *r) {
  r->total = 1;  /* C has no such member. */
}
```

The fix uses the canonical spelling already established by semantic lookup.
The tests vary declaration and reference case even when every character is
an ordinary letter; no exotic QID is needed to expose this one.

[#245](https://github.com/ricomariani/CG-SQL-author/pull/245) brought projection
accessors into agreement across Java, C#, and the two Objective-C generators.
Legal-name encoding, collisions, reserved wrapper members, and matching
declarations/implementations are each the wrapper's responsibility. The repair
kept that policy local to the customizable samples rather than adding a new
compiler JSON naming contract.

That review also found a compiler inconsistency: the quoted-name encoder
escaped an ordinary capital `X` even when the name needed no encoding.
Quoted `XName` and unquoted `XName` could therefore acquire different
canonical spellings. The repair decides whether encoding is needed first;
only encoded names need to escape literal `X` bytes.

---

## Target-language rules and missed conversions

The compiler already handles many differences between CQL, C, and Lua.
Some failures came from a missed conversion in one path; others came from
a rule I had wrong. Golden output can preserve either mistake unless the
test checks what the generated program does.

### C escape syntax surprised the C programmer

I am a veteran C programmer, and I was surprised by this one.

In C, a hexadecimal escape consumes all following hexadecimal digits:

```c
"\x01f"       /* One escape: 0x1f, not byte 0x01 followed by 'f'. */
"\x01" "f"    /* Two bytes, followed by the terminating zero. */
```

Likewise, `"\x41f"` does **not** mean `"Af"`; it describes one hex escape with
value `0x41f`, with the additional representability problem that creates.
`"\x41" "f"` expresses the intended characters.

CQL's corresponding byte escape consumes two digits. An encoder that shared
the same spelling across CQL echo, Lua, and generated C could therefore look
perfectly reasonable while changing the executable C bytes.

[#237](https://github.com/ricomariani/CG-SQL-author/pull/237) used adjacent C
string tokens when a hex digit followed a hex escape. We separated the target
encoders so CQL and Lua kept their existing behavior.

Ordinary constants, quoted SQL, and compressed SQL dictionary pieces all
needed the C rule. `#line` filenames are not an ordinary adjacent-string
context and were not treated as one.

The regression compiles the generated C and checks the resulting bytes.
Sometimes you're just wrong.

### Comments are generated text too

The same context question applies to text intended to be ignored.
[#204](https://github.com/ricomariani/CG-SQL-author/pull/204) fixed provenance
comments that inserted a decoded `#line` filename directly. A filename
containing a newline could end the C or Lua line comment. For a decoded
filename consisting of `first`, a newline, and `#error unexpected`, the C
output had this shape:

```c
// Generated from first
#error unexpected:17
```

The filename now goes through a comment-text encoder before either backend
inserts it.

Lua source comments had a related delimiter problem. This old rendering ends
the Lua comment inside a CQL string:

```lua
--[[
SELECT "]]";
--]]
```

Lua doesn't parse the enclosed CQL string before recognizing `]]`.
The generator now chooses a long-comment delimiter whose closing form isn't
in the enclosed source. For this example it can emit:

```lua
--[=[
SELECT "]]";
--]=]
```

### A plausible conversion can be wrong for half the number line

Lua's integer conversion helper used `math.floor`. Positive fractions
made that look right:

```text
value       old floor result      CQL/SQLite cast
 1.9                1                    1
-1.9               -2                   -1
-0.5               -1                    0
```

The complete helper correction in
[#234](https://github.com/ricomariani/CG-SQL-author/pull/234) was:

```diff
 function cql_to_integer(num)
   if num == true then return 1 end
   if num == false then return 0 end
   if num == nil then return nil end
-  return math.floor(num);
+  return num < 0 and math.ceil(num) or math.floor(num);
 end;
```

The new runtime cases cover negative nonnull INT/LONG conversions, nullable
fractions becoming zero, and NULL preservation, and can run in both C and Lua.
More positive fractions wouldn't have exposed the problem; crossing zero
tests the rule we had actually missed.

### Existing Lua conversions still had missing callers

Lua's truthiness is well known, and the backend is full of conversions between
CQL's numeric and Boolean values. Assignments, arithmetic, comparisons,
`IN`, ordinary `IF`, and loops already use `cg_lua_to_bool` and
`cg_lua_to_num`, but it's easy to miss one place that needs them.

For example, the ordinary IF emitter already did this:

```c
cg_lua_to_bool(sem_type_expr, &expr_value);
bprintf(cg_main_output, "if %s then\n", expr_value.ptr);
```

The fixes in [#233](https://github.com/ricomariani/CG-SQL-author/pull/233)
covered two separate emitters.

#### Simple CASE had its own comparison emitter

The ordinary comparison path normalized Boolean operands to numbers, but
simple CASE emitted equality directly. Lua's `true == 1` is false, whereas
CQL's `CASE true WHEN 1` must match.

The CASE-list emitter now receives the selector's semantic type and converts
both operands before printing the comparison. Here is the relevant change,
with the source comment omitted and the long output line wrapped:

```diff
-bprintf(cg_main_output, "if %s == %s then\n", expr, case_expr_value.ptr);
+CHARBUF_OPEN(expr_comparable);
+bprintf(&expr_comparable, "%s", expr);
+cg_lua_to_num(sem_type_expr, &expr_comparable);
+cg_lua_to_num(sem_type_case_expr, &case_expr_value);
+bprintf(cg_main_output, "if %s == %s then\n",
+  expr_comparable.ptr, case_expr_value.ptr);
+CHARBUF_CLOSE(expr_comparable);
```

For a Boolean selector, the emitted comparison changes from
`if selector == 1 then` to `if cql_to_num(selector) == 1 then`.
The helper leaves numeric operands alone, and the surrounding CASE code
retains its NULL guard.

The runtime regression includes:

```sql
TEST!(bool_numeric_case,
begin
  let t := nullable(true);
  let f := nullable(false);
  declare unknown bool;
  set unknown := null;

  EXPECT_SQL_TOO!((case t when 1 then 10 else 20 end) = 10);
  EXPECT_SQL_TOO!((case f when 0 then 10 else 20 end) = 10);
  EXPECT_SQL_TOO!((case 1 when t then 10 else 20 end) = 10);
  EXPECT_SQL_TOO!((case 0.0 when f then 10 else 20 end) = 10);

  EXPECT_SQL_TOO!((case t when 2 then 10 else 20 end) = 20);
  EXPECT_SQL_TOO!((case 0.5 when t then 10 else 20 end) = 20);

  EXPECT_SQL_TOO!((case unknown when unknown then 10 else 20 end) = 20);
  EXPECT_SQL_TOO!((case 1 when unknown then 10 else 20 end) = 20);
end);
```

`EXPECT_SQL_TOO!` checks the CQL expression and its SQLite evaluation.
The middle cases prevent an overcorrection: converting every operand to a
Boolean would make true equal to 2 or 0.5.

#### Fragment selection had its own IF emitter

A conditional shared fragment chooses which SQL text to include.
Its IF emitter was separate from the ordinary statement emitter and had
missed the same normalization step:

```diff
 CG_LUA_PUSH_EVAL(expr, LUA_EXPR_PRI_ROOT);

+cg_lua_to_bool(expr->sem->sem_type, &expr_value);
 bprintf(cg_main_output, "if %s then\n", expr_value.ptr);
```

This regression fragment makes the effect visible:

```sql
[[shared_fragment]]
proc numeric_fragment(x int!, y real, flag bool)
begin
  if x then
    select 10 as value;
  else if y then
    select 20 as value;
  else if flag then
    select 30 as value;
  else
    select 40 as value;
  end if;
end;
```

With `(x, y, flag) = (0, 0.0, false)`, the old Lua selected 10 because zero
is truthy, while CQL requires 40. The existing helper converts numeric zero
to false, preserves NULL, and leaves Boolean predicates alone. Negative
integers and nonzero fractions must still select their branches, so the
tests include those controls too.

The normal harness checked generated Lua text without executing its runtime
suite, so running these cases in Lua exposed wrong results the goldens had
approved.

### A readable tuple isn't necessarily an unambiguous key

The Lua partition helper used a string representation to collect children
under a parent key. A two-field version of the old encoding is enough to
show the collision:

```lua
local function old_key(a, b)
  return tostring(a) .. ":" .. tostring(b)
end

assert(old_key("a:b", "c") == old_key("a", "b:c"))
```

Both produce `a:b:c`, putting children from two different parents in the same
partition. Doubling the separator still leaves an ambiguity over which
field owns a boundary colon.

Length prefixes in
[#236](https://github.com/ricomariani/CG-SQL-author/pull/236) distinguish them:

```text
("a:b", "c")  -> 3:a:b1:c
("a", "b:c")  -> 1:a3:b:c

NULL         -> N
text "nil"   -> 3:nil
empty text   -> 0:
```

The lengths are byte lengths, so embedded zero bytes in blobs remain data.
Numeric identity added more cases: adjacent doubles can stringify alike,
and converting full-width integers through double loses distinctions above
2^53. The helper now preserves integers exactly, uses enough digits for
nonintegral doubles, and gives integer and floating representations of the
same number the same key.

The 16-row regression fixture deliberately puts each collision pair in
otherwise identical keys. It then extracts every partition and requires
exactly the one expected child. That tests key identity through the operation
which relies on it, including NULL, binary, and numeric cases.

---

## A local fact can be lost when paths meet

Some failures came from correctly established facts being carried into a
context where they no longer held. I'd seen this family of bugs in the
human-found era too. The missing tests combined conditions, exits, aliases, and
rewrites in ways our earlier examples hadn't.

### A returning branch cannot prove a fact about a continuing path

This is the failing semantic test from
[#223](https://github.com/ricomariani/CG-SQL-author/pull/223):

```sql
declare proc requires_int_notnull(a int!);

proc jumping_branch_does_not_contribute_inherited_improvements(a int, b bool!)
begin
  if a is null then
    set b := true;
  else if b then
    return;
  else
    set b := false;
  end if;

  call requires_int_notnull(a);
end;
```

The first branch reaches the call with `a` still NULL, so the compiler must
reject it. The ELSE IF and ELSE branches both know `a` is nonnull because
the first condition was false, but the ELSE IF returns.

The implementation removed that returning branch from the count of
continuing branches while leaving its inherited nonnull contribution in
the accumulated history. The stale contribution made the nonnull fact
appear to cover both remaining branches.

The old branch-entry code had already recorded that contribution. Here are
the three operations, with long lines wrapped:

```c
flow_history branch_group_history =
  clone_history(current_context->parent->history);
append_history(&branch_group_history,
  current_context->parent->branch_group.branch_histories);
current_context->parent->branch_group.branch_histories = branch_group_history;
```

The repair removes those operations from branch entry. At branch exit,
after rolling back branch-local changes, it records inherited facts only
for a continuing branch. With the source comments omitted, that part becomes:

```c
if (current_context->branch.always_jumps) {
  current_context->parent->branch_group.branch_count--;
}
else {
  append_history(&current_context->history,
    clone_history(current_context->parent->history));
  append_history(&current_context->history,
    current_context->parent->branch_group.branch_histories);
  current_context->parent->branch_group.branch_histories = current_context->history;
}
```

The branch count and its contributions now exclude the same returning path.
Simply discarding all inherited history would reject this valid counterpart:

```sql
proc continuing_branches_retain_inherited_improvements(a int, b bool!)
begin
  if a is null then
    set a := 1;
  else if b then
    return;
  else
    set b := false;
  end if;

  let x := a;
  call requires_int_notnull(a);
end;
```

Now the first branch repairs `a`, and every path reaching the call has a
nonnull value. The regressions include both tests along with local
overwrites, empty branches, and other jumping statements, checking the
accounting across combinations that hadn't been exercised before.

### Identity and scope need to survive the shortcut paths

The same review question applies to aliases: what storage does this argument
actually name? Comparing source spellings or AST pointers misses case
variants, dotted fields, and argument-bundle aliases. The
[#224](https://github.com/ricomariani/CG-SQL-author/pull/224) checks use
resolved mutable storage instead. An evaluated IN expression can share its
source spelling with an OUT target without being a second mutable alias;
that distinction needs its own control cases.

Nullability also has to survive transformations. An unmatched row from the
right side of an outer join has a NULL rowid, even though a real row's rowid
is nonnull. Some sources have no implicit rowid at all. The tests in
[#225](https://github.com/ricomariani/CG-SQL-author/pull/225) cover source
eligibility and the join transformation.

Likewise, [#226](https://github.com/ricomariani/CG-SQL-author/pull/226) makes JSON
scalar functions preserve the appropriate nullability and sensitivity
flags, including nullable results from missing paths.

The direct blob-call checks in
[#227](https://github.com/ricomariani/CG-SQL-author/pull/227) show why testing
only the usual higher-level route is insufficient. Rewritten DML supplies
assignment and layout checks. A direct call must also establish consistent
partitions, unique columns, and complete primary-key order. The first field
selects the storage operation, so accepting an inconsistent later field
can send the operation down the wrong storage path. Those are compile-time
checks of the requested operation; the binary reader's malformed-data checks
cannot supply them later.

### Numeric spelling also carries a type

[#220](https://github.com/ricomariani/CG-SQL-author/pull/220) checked integer
literal ranges rather than accepting silent conversion saturation. It retained
the exceptional magnitude needed to spell `INT64_MIN` under unary minus and
preserved high-bit hexadecimal patterns through folding, JSON, and generated C.
The C expressions below show why preserving the bits alone wasn't enough:

```c
0xffffffffffffffffLL < 0  /* false: the literal has unsigned type */
(-1LL) < 0              /* true: the intended signed value */
```

CQL's high-bit hex pattern is signed, so emitting an unsigned C expression
can change comparison and division behavior. The test compares raw, folded,
and generated results to catch that loss of meaning.

[#221](https://github.com/ricomariani/CG-SQL-author/pull/221) addressed unchecked
numeric conversion for `--min_schema_version` and line directives, rejecting
empty, negative, junk-suffixed, and out-of-range values. It also reserved
line-number headroom before installing a source mapping. I declined the
broader arithmetic and shift proposals discussed below.

---

## The tests need an independent answer

Several tests established something weaker than what the application needed.
Generated text could be stable, JSON could parse, and a helper could return
success while the requested object, value, or physical change was wrong.
We saw this with virtual tables, and it showed up in schema checksums and
reporting too.

### A checksum test needs a physical schema change

[#229](https://github.com/ricomariani/CG-SQL-author/pull/229) found cumulative
index/drop buffers being hashed once per table in a recreate group. XORing the
same accumulated text twice could cancel its contribution. An index-only
change in a two-table group could therefore leave the group checksum unchanged
and suppress required work.

Consider a group with two tables, A and B. A has index I; B has no index.
The index buffer is cumulative:

```text
after A: index buffer contains I; hash H(I) into the group
after B: index buffer still contains I; hash H(I) into the group again

index contribution = H(I) XOR H(I) = 0
```

Creating a fresh database works, but upgrading an existing one can omit the
new uniqueness constraint.

The old loop included:

```c
table_crc ^= crc_charbuf(&make_table);
table_crc ^= crc_charbuf(&delete_tables);
table_crc ^= crc_charbuf(&update_indices);
```

Only the first line belongs to each table. The repair moved the cumulative
drop/index hashes to the end of the group.

The upgrade fixture checks physical state using
`g1(id integer primary key, name text)` in a two-table recreate group.
Version 1 adds `g1_name`, an index on its first table, and before each
upgrade the test inserts a probe:

```sql
create proc prepare_recreate_crc_test(old_version long!)
begin
  if old_version >= 0 then
    insert into g1 values (1, 'recreate checksum probe');
  end if;
end;
```

Afterward it checks both the index and the data. Here is the verification
body, omitting only the explanatory source comments:

```sql
create proc verify_recreate_crc_test(old_version long!, new_version long!)
begin
  let has_index := (select exists(
    select 1 from sqlite_master where name = 'g1_name'
  ));
  if has_index != (new_version >= 1) then
    printf_stderr("ERROR! recreate-group index missing or unexpected in v%lld\n",
      new_version);
    throw;
  end if;

  if old_version >= 0 then
    let unchanged := old_version == new_version or
      (old_version >= 1 and new_version <= 3);
    let has_probe := (select exists(select 1 from g1 where id = 1));
    if has_probe != unchanged then
      printf_stderr("ERROR! unexpected recreate-group data preservation from v%lld to v%lld\n",
        old_version, new_version);
      throw;
    end if;
    delete from g1 where id = 1;
  end if;
end;
```

Versions 1 through 3 leave this group unchanged; version 4 adds a group
member. Unchanged and repeated upgrades must preserve the probe. An
index-only change or new member must really recreate the group, removing
the probe with the bundled runtime. A return-code check wouldn't establish
either behavior.

Compatibility mattered because corrected group hashes can cause a one-time
maintenance recreate after a later schema change opens the outer
complete-schema gate. The bundled runtime recreates a called group and
discards its data; it doesn't compare actual SQL to decide that nothing
needs doing. We preserved single-table hashes, and recompiling an identical
complete schema doesn't by itself open the outer gate.

### Query-local numbers aren't global identities

The statistics bug in
[#243](https://github.com/ricomariani/CG-SQL-author/pull/243) was easy to miss
in a visual inspection because the graphs and query text were correct.
Plan node IDs are local to a statement, but the search-count query treated
them as global. A simplified pair of stored plan rows shows the problem:

| sql_id | iselectid | zdetail |
|---:|---:|---|
| 1 | 3 | SEARCH t USING INDEX t_x |
| 2 | 3 | SEARCH u USING COVERING INDEX u_x |

When counting ordinary index searches for statement 1, the reporting query
excludes covering searches. Its exclusion subquery selected every covering
node ID, including statement 2's node 3. That also excluded statement 1's
ordinary search.

The fix scopes the subquery to the statement being counted:

```diff
-WHERE zdetail LIKE '%search%using%covering%'
+WHERE zdetail LIKE '%search%using%covering%' AND sql_id = id_
```

The regression puts different kinds of search in statements with reused
node IDs, because running each statement in isolation can't expose this
contamination.

### Parseable output can still describe a different program

SQL expression grouping gave us another way to emit a valid but different
program. [#239](https://github.com/ricomariani/CG-SQL-author/pull/239)
preserved right-nested grouping among `||`, `->`, and `->>`, which share
left-associative precedence but aren't associative in mixed pairs.

With the CQL cast removed, SQLite can show the difference directly:

```sql
select '{"ab":7}' ->> ('a' || 'b');  -- 7
select '{"ab":7}' ->> 'a' || 'b';    -- NULL
```

Other combinations raised a JSON error instead of returning the intended text.
The existing stronger-right-child rule already used by ordinary binary
emission was enough. A matrix of all nine operator pairs checked emitted
grouping and actual results separately.

[#244](https://github.com/ricomariani/CG-SQL-author/pull/244) exposed another
nested format boundary in `cqljson.py`. The outer SQL literal was correctly
escaped, but the inner reconstructed CQL attribute value was not.

These distinct values could collapse into identical stored text:

```text
two strings:  ("a", "b")
one string:   ("a\", \"b")
```

Literal backslashes could also become CQL escapes, and scalar or nested NULLs
were printed as Python `None`. The repair encoded CQL values first, then SQL
literals, and tested the complete route:

```text
CQL -> compiler JSON -> sample SQL -> SQLite
    -> reconstructed CQL -> compiler JSON -> original values
```

SQLite execution and the actual CQL parser give us independent checks along
that route. Producer/consumer agreement alone can be misleading if both
share the same bad convention, as the older C/Lua serialization mismatch
showed; cross-backend checks help with that too.

---

## Lightly used integrations need complete use-cases

Some failures were spectacular enough to say something about use. The
nullable-binary failures in the human-era appendix could hardly survive an
application that actually stored and retrieved nullable values, and the .NET
sample supplied an equally direct example in this review.

### The binary argument was never sent

[#246](https://github.com/ricomariani/CG-SQL-author/pull/246) completed .NET
blob marshalling. This is the old generator template expanded for a parameter
named `value`:

```c
void *bytes_value = "xx";
int len_value = 2;
blob_ref_value = cql_blob_ref_new(bytes_value, (cql_uint32)len_value);
```

Every supplied blob became the same two bytes, something a generator golden
could approve forever but an actual binary use-case would expose immediately.

The replacement passes the data pointer, size, and NULL presence separately.
An empty managed array can marshal as a NULL pointer, so pointer presence
cannot distinguish an empty blob from SQL NULL. The generated nullable
conversion now has this shape:

```c
cql_contract(value_size >= 0);
if (value_has_value) {
  cql_contract(!value_size || value);
  blob_ref_value = cql_blob_ref_new(
    value_size ? value : "", (cql_uint32)value_size);
}
```

The new fixture's inputs include:

```csharp
byte[] binary = {0, 255, 1, 128, 0, 42};
byte[] large = Enumerable.Range(0, 4097).Select(i => (byte)(i % 256)).ToArray();
byte[]?[] values = {binary, new byte[] {1}, Array.Empty<byte>(),
                   new byte[] {120, 120}, large, null};
```

The `"xx"` input is intentional: it belongs alongside values that the old
placeholder could never return correctly. The fixture checks actual payloads
through nullable and nonnull calls, INOUT replacement, native comparison,
and projected result sets, with NULL and empty distinct in both directions.
It reads returned data twice using the borrowed projection handle, then
releases the owning result set. The interop code also has to free each native
buffer after copying it back.

That work also produced a real follow-up failure:
[#247](https://github.com/ricomariani/CG-SQL-author/pull/247). The fixture
inherited ASan instrumentation, but the .NET host did not supply the ASan
runtime, so it failed to load with `DllNotFoundException`. We changed the
foreign-hosted fixture's flags; the compiler and ordinary native tests stayed
instrumented.

### One call doesn't exercise an integration's lifecycle

The first May 15 extension changes tell a similar first-use story.
[`82925067`](https://github.com/ricomariani/CG-SQL-author/commit/82925067)
stopped retaining an OBJECT and exposing its address as an integer SQL value;
the generic bridge now returns NULL for that unsupported column type.
[`b7ac09a6`](https://github.com/ricomariani/CG-SQL-author/commit/b7ac09a6)
released the previous rowset when SQLite called `xFilter` again on the same
cursor, as an ordinary nested-loop join can do.

[#235](https://github.com/ricomariani/CG-SQL-author/pull/235) found a related
problem in generated Lua fetch-results wrappers. Tuple assignments lacked
`local`, so nested calls could overwrite the outer statement and lose its
cleanup. The core emitter correction is one keyword:

```diff
-bprintf(d, "  %s = %s(%s)\n", returns.ptr, proc_sym.ptr, args.ptr);
+bprintf(d, "  local %s = %s(%s)\n", returns.ptr, proc_sym.ptr, args.ptr);
```

The returned tuple now belongs to this invocation, and Lua evaluates
forwarded arguments before the newly declared locals can shadow parameter
names. Since a one-call test has nothing to overwrite, the regression
exercises nested calls, checks application globals, and verifies input/INOUT
forwarding.

Repeated invocations also exposed scanner ownership problems, repaired in
[#217](https://github.com/ricomariani/CG-SQL-author/pull/217). A compiler-owned
main/include file or Flex buffer must be released, while a borrowed caller
stream or buffer must remain the caller's to release, including after an
error. The ordinary command-line process exits after one compilation, making
leaks easy to miss.

The repair closes include files at EOF, releases remaining owned handles
and buffers exactly once during cleanup, and resets Flex's scanner state
without destroying borrowed input. The regression runs repeated
compilations under a small descriptor limit, including nested includes,
failures, recovery, and borrowed inputs.

---

## The test infrastructure had bugs and blind spots too

The test drivers often got very basic error treatment, and ignoring a failed
transaction or building stale generated code can undermine all the checks
that follow.

### A printed error isn't a failed test

The schema-upgrade driver printed a failed BEGIN but continued into the
upgrade. It also ignored COMMIT's result. The important part of
[#248](https://github.com/ricomariani/CG-SQL-author/pull/248) was propagation:

```diff
-if (begin_transaction(db)) {
-  fprintf(stderr, "failed to begin transaction\n");
+rv = begin_transaction(db);
+if (rv != SQLITE_OK) {
+  fprintf(stderr, "failed to begin transaction: %s (%d)\n",
+    sqlite3_errmsg(db), rv);
+  return rv;
 }
```

The commit path now assigns and returns the transaction's result too.
Similarly, [#249](https://github.com/ricomariani/CG-SQL-author/pull/249)
reports a failed SQLite close instead of concealing outstanding resources
behind a successful process exit.

The driver fixes stayed small. If `main` is going to report an error and
immediately exit, there's no need to add rollback and cleanup machinery.

The verifier wrapper had the same problem one level higher:

```diff
-./regen.sh
-(cd ..; make cql-verify)
+#!/bin/bash
+
+./regen.sh && make -C .. cql-verify
```

If regeneration failed, the old wrapper could build stale files and finish
successfully. [#250](https://github.com/ricomariani/CG-SQL-author/pull/250)
ties the build to successful regeneration. To check that failure path, old
generated files need to remain in place when regeneration fails; otherwise
a build might fail simply because its inputs are missing.

### The assertion has to describe the complete result

The parent/child fixture expected two parents and three children:

| Parent ID | Name | Child task IDs |
|---:|---|---|
| 2 | bar | 200 |
| 1 | foo | 100, 101 |

The old checks could accept incomplete results. The child query also had no
`ORDER BY`, so a position-dependent expected-value formula was unjustified.
[#251](https://github.com/ricomariani/CG-SQL-author/pull/251) checks the exact
parent count, IDs and names, each child count, and unique membership in the
expected child set. A subset, duplicate, or unrelated child now fails without
requiring an ordering the query never promised.

That change also strengthened the runtime recreate-helper test. It seeds a
probe row, calls the helper, then verifies from CQL that the probe is gone
but all five tables and the expected index exist. Losing data alone could
mean the helper dropped the tables without restoring them.

The corruption-test PRNG had a separate problem: it relied on signed
multiplication overflow to wrap. Its state is now unsigned, with the intended
arithmetic:

```c
rand_state = (rand_state * UINT32_C(1302475243) + UINT32_C(21493))
  & UINT32_C(0x7fffffff);
```

### A permissive or disconnected checker leaves a hole

The schema JSON validator used a case-insensitive scanner. That let
wrong-case field names satisfy a supposedly canonical schema contract.
[#253](https://github.com/ricomariani/CG-SQL-author/pull/253) removed the
global option:

```diff
-%option noyywrap nodefault yylineno case-insensitive
+%option noyywrap nodefault yylineno
```

Canonical uppercase `CRC` remains uppercase, and JSON numbers still accept
either exponent letter through an explicit `[Ee]` rule. This was a validator
bug; we hadn't found wrong-case JSON keys in the compiler's output.

The extension-encoding check already ran in the extension suite and CI, but
the default harness had left it out.
[#252](https://github.com/ricomariani/CG-SQL-author/pull/252) added it to
that path.

Global-procedure tracing had a subtler configuration gap: the emitter used
a function name where `_PROC_` needed a C string, and the normal no-op tracing
macro never consumed the argument.
[#231](https://github.com/ricomariani/CG-SQL-author/pull/231) tests a tracing
configuration that actually uses it and exposes the wrong type.

---

## Future-proofing has a budget

Some findings identified a dangerous helper precondition without finding a
caller that violated it. Others proposed behavior the language had never
promised. Those deserve different treatment from a reproduced failure.

### Supporting self-append or prohibiting it are both possible contracts

The compiler's byte-buffer append helper originally allocated destination
space and then copied from the caller's pointer. If the caller passed part
of the same buffer, growth invalidated the source. This has the same lifetime
mechanism as the serializer's bit pointer, but we had no known failing
production caller.

[#207](https://github.com/ricomariani/CG-SQL-author/pull/207) made self-append
supported behavior. The helper records a source offset before allocation
and rederives the pointer afterward:

```diff
+uint32_t offset = 0;
+bool_t aliases_buffer = false;
+
+if (buf->ptr) {
+  uintptr_t source = (uintptr_t)bytes;
+  uintptr_t start = (uintptr_t)buf->ptr;
+  if (source >= start && source - start < buf->used) {
+    offset = (uint32_t)(source - start);
+    aliases_buffer = true;
+  }
+}
+
 void *mem = bytebuf_alloc(buf, count);
-memcpy(mem, bytes, count);
+if (aliases_buffer) {
+  bytes = buf->ptr + offset;
+}
+memmove(mem, bytes, count);
```

The regression checks full self-append and an interior slice:

```c
static bool test_bytebuf_self_append() {
  bytebuf buffer;
  bytebuf_open(&buffer);

  char seed[BYTEBUF_GROWTH_SIZE + 1];
  for (uint32_t i = 0; i < sizeof(seed); i++) {
    seed[i] = (char)(i & 0x7f);
  }
  bytebuf_append(&buffer, seed, sizeof(seed));
  bytebuf_append(&buffer, buffer.ptr, buffer.used);

  bool result =
    buffer.used == 2 * sizeof(seed) &&
    !memcmp(buffer.ptr, seed, sizeof(seed)) &&
    !memcmp(buffer.ptr + sizeof(seed), seed, sizeof(seed));

  bytebuf_append(&buffer, buffer.ptr + 17, 31);
  result &= buffer.used == 2 * sizeof(seed) + 31;
  result &= !memcmp(buffer.ptr + 2 * sizeof(seed), seed + 17, 31);

  bytebuf_close(&buffer);
  return result;
}
```

The seed is large enough to force growth when duplicated, so the test
actually exercises pointer relocation.

For formatted text, I chose a smaller contract. Supporting a format string
inside the destination buffer would complicate a two-pass formatter. The
[#208](https://github.com/ricomariani/CG-SQL-author/pull/208) check prohibits
that alias:

```c
uintptr_t source = (uintptr_t)format;
uintptr_t start = (uintptr_t)b->ptr;
Contract(source < start || source - start >= b->max);
```

String arguments retain a documented non-aliasing precondition too, giving
us a deliberately limited contract for a helper that had no known need for
self-formatting.

### A contract must survive the configuration that relies on it

Before this work the compiler macros were:

```c
#define Invariant assert
#define Contract assert
```

Both the compiler and runtime lost those checks when compiled with `NDEBUG`.
The small always-on compiler replacement is:

```c
#define Invariant(condition) do { if (!(condition)) abort(); } while (0)
#define Contract(condition) do { if (!(condition)) abort(); } while (0)
```

The runtime change landed in
[#204](https://github.com/ricomariani/CG-SQL-author/pull/204), with the
compiler completed in #208, keeping fail-fast checks meaningful in release
builds.

Other preventive checks make the intended contracts explicit: runtime
result-set/list bounds in #204, matching row sizes before result-set equality
in [#213](https://github.com/ricomariani/CG-SQL-author/pull/213), and extension
callback/ownership conditions in
[`11e277c2`](https://github.com/ricomariani/CG-SQL-author/commit/11e277c2).

The SHA-256 code in
[#209](https://github.com/ricomariani/CG-SQL-author/pull/209) had a
portability assumption: it allocated a byte array and read it through an
`int64_t *`. Convenient stack addresses on the machines we happened to use
had hidden the alignment requirement, and the object type was wrong too:

```diff
-SHA256_BYTE hash_bytes[64];
-sha256_final(&ctx, hash_bytes);
-int64_t *h = (int64_t *)hash_bytes;
-int64_t hash = h[0] ^ h[1] ^h[2] ^ h[3];
+int64_t words[SHA256_BLOCK_SIZE / sizeof(int64_t)];
+sha256_final(&ctx, (SHA256_BYTE *)words);
+int64_t hash = words[0] ^ words[1] ^ words[2] ^ words[3];
```

The digest writer is allowed a byte view of the integer objects; the integer
reads now have the required alignment and object type without changing the
bytes.

### Bound the actual operation without building a new subsystem

Recursive macro expansion needed a limit because both the expansion walker
and AST cloning recurse. The
[#216](https://github.com/ricomariani/CG-SQL-author/pull/216) fix uses a depth
guard at 256 and the normal source diagnostic. I declined an initial plan
with node budgets and extra traversal machinery. A very large flat macro
isn't the same operation as a deep expansion chain.

The verifier's
[`bdf53add`](https://github.com/ricomariani/CG-SQL-author/commit/bdf53add)
change likewise moved line-sized scratch storage from `alloca` to the heap.
This is a robustness improvement in a test utility.

Several of the first proposals had considerably more machinery than we
needed. Working through the designs was as much a part of the review as
checking the diagnoses.

### Proposals we did not adopt

| Proposal | Why it was declined |
|---|---|
| Checked constant arithmetic and enum increments (original item 13) | A new overflow, division/remainder, and floating-point policy would need matching runtime/backend semantics. I didn't think the benefit justified that language change. |
| Defined shifts and numeric conversions (14) | A defined CQL shift/conversion policy would need consistent folding and emitted operations across backends. Applying checks only during folding wouldn't give us that. |
| SQLite-style loose `IN`/`NOT IN` semantics (19) | CQL deliberately differs from SQLite on RHS NULLs. The documented behavior makes loose `1 NOT IN (NULL, 5)` true. I didn't want to change it. |
| Deduplicated recreate dependency traversal (22) | The DFS detects cycles correctly. Duplicate edges and shared descendants repeat work, but we had no failing case or practical workload that made the extra visited-set state worthwhile. [#228](https://github.com/ricomariani/CG-SQL-author/pull/228) documents that decision. |
| A generated-C symbol registry and reserved-name rejection (25) | The C compiler already diagnoses symbol conflicts. Tracking every generated symbol and scope was too much machinery. Banning only `_rc_` would miss other collisions; broad underscore bans would reject legitimate conventions. |
| Lua keyword/name mangling (remainder of 27) | I didn't approve a new mangling scheme or naming restrictions. [#232](https://github.com/ricomariani/CG-SQL-author/pull/232) fixes canonical spelling only. |

I also left numeric/Boolean validation of edited JSON out of #244 because
the sample normally consumes compiler JSON and the attribute fix was about
preserving those values. It doesn't comprehensively validate hostile JSON,
and diagram modes were outside the fix too.

---

## Counting notes

The 68 findings come from three batches:

| Source of findings | Findings |
|---|---:|
| May/July fixes before the October batch | 11 |
| The grouped changes in #204 | 7 |
| Extractions and follow-ups, #207 through #253 | 50 |
| **Total** | **68** |

The first 11 cover backed-blob shape/range validation, constructor type-code
consistency, the stream offset-word bound, unsupported extension OBJECTs,
repeated `xFilter`, extension contracts, verifier stack allocation, include
paths, retained-field validation, unknown stored types, and malformed-data
error reporting. The two constructor/reader issues in `2ed3ac9e` are separate
because one concerns constructing a consistent value and the other concerns
accepting hostile stored bytes.

The seven #204 findings are runtime collection bounds, non-elidable contracts,
Windows `PATH_MAX` sizing, provenance line-comment encoding, Lua long-comment
delimiters, sample SQL encoding, and extension SQL/C encoding. The compiler
contract completion in #208 stays with the runtime contract finding; the
format-alias contract is separate.

There are 47 PRs from #207 through #253. Excluding #228's comment-only declined
optimization and #247's newly introduced fixture regression leaves 45.
#238, #241, and #242 each repair two distinct failures; #251 repairs three.
That gives 45 + 3 + 2 = 50 findings. The four binding generators and core
identifier-encoding correction in #245 count as one finding, and the
canonical C/Lua emitter error in #232 counts once.

Routine release, documentation, build-maintenance, and signature-alignment
changes are excluded, as are declined proposals and ancillary renamings.
#251 contributes three test/tooling findings. The eight preventive findings
have no demonstrated ordinary-use failure in this review: extension
contracts, verifier heap storage, collection bounds, always-on contracts,
byte-buffer self-append, the format-alias contract, digest storage, and the
result-set row-size contract.

The seven security findings are the initial backed-blob shape/range checks,
the initial stream-word bound, retained-field validation, unknown-type
rejection, overlapping-field output sizing, complete stream-table validation,
and field-counter limits. The unknown-type abort is Medium priority; the
six hostile-data memory failures are Critical.

For the other bugs, Important includes stale serialization pointers,
incorrect numeric interpretation, flow/alias/type-property failures,
cancelled schema checksums, Lua results and wrapper state, generated C escapes,
SQL grouping, .NET marshalling, and the include/Windows memory bounds.
More limited encoding, metadata, source-validation, diagnostic, and lifecycle
failures are Medium.

### Reproducing the source denominator

This script measures only tracked historical source, so generated working
files and the current checkout don't affect it:

```python
import re
import subprocess

def git(*args):
    return subprocess.check_output(["git", *args])

for revision in ("8793b00f", "837956ba"):
    paths = git("ls-tree", "-r", "--name-only", revision).decode().splitlines()
    core = [
        path for path in paths
        if re.fullmatch(r"sources/[^/]+\.[ch]", path)
        and path != "sources/unit_tests.c"
    ]
    other = ["sources/cql.y", "sources/cql.l", "sources/cqlrt.lua"]
    lines = sum(len(git("show", f"{revision}:{path}").splitlines())
                for path in core + other)
    print(revision, lines)
```

It prints 89,419 and 90,377, counting a final unterminated line as a line.
For each heatmap file, the same
`len(git("show", f"{revision}:{path}").splitlines()) / 1000` calculation gives
raw KLOC, rounded to three decimal places. Pre-audit sizes use
`8793b00f`; post-fix sizes use `837956ba`. Executable sizes use the matching
file's `Lines` column in the November 2 coverage report, divided by 1,000.

The raw-line density uses the pre-audit 89.419 raw KLOC:
45 / 89.419 = 0.50, split into 7 / 89.419 = 0.08 security and
38 / 89.419 = 0.42 other correctness findings per raw KLOC.
The human-era scale comparison uses 12 / 89.419 = 0.13 per raw KLOC per year.

The executable-line count comes from the November 2 `sources/cov.sh` report:
39,789 executable lines minus 291 in `unit_tests.c` gives 39,498 production
lines. Using that post-fix size reference, 43 / 39.498 = 1.09 native bug
findings per executable KLOC; 7 / 39.498 = 0.18 security and
36 / 39.498 = 0.91 other correctness.

The authorship table comes from:

```text
git log --first-parent --no-merges --format='%aN%x09%as' 837956ba
```

I grouped by the primary author name and filtered on the printed author
calendar date. Merge commits and coauthor trailers aren't additional rows.
The initial public import already contained a mature implementation, so
these commit shares don't measure who originally wrote every line.

---

## What we learned about testing

So was I making a systematic mistake, or had I run out of useful passes
over code I knew too well?

Some weaknesses were systematic. I'd intended validation to happen at
another layer without making sure the check actually existed, test drivers
didn't always propagate errors, and some tests checked generated text or
successful parsing without checking the resulting value.

The regressions prove that the missed cases were testable, but how do you
get inspired to write the tests you haven't thought of? A list of cases
is easy to produce after seeing the failures. QIDs had already had that
kind of disciplined attention, and I don't think another pass by me was
likely to supply the missing examples.

I can't turn that into a general limit on what one human can accomplish,
but I can see the diminishing returns from my own repeated reviews.
More contributors could have supplied different experience and independent
scrutiny, but could I recruit someone to learn the whole compiler and
meticulously work through this many findings? That might take years, and
it wasn't help I could simply assume would arrive.

More usage would plainly have helped with the first-use failures in lightly
used features. Under our usual process, many of these bugs were waiting for
a user to stumble into the right combination. The hostile-data cases also
needed deliberate examination: overlapping payloads aren't produced by the
normal writer.

The AI gave us a practical way to ask for independent scrutiny across the
whole implementation. It could keep looking, help reproduce the useful
counterexamples, and work through the repairs with me. My part was still
substantial, including reviewing the diagnoses, rejecting unsupported
security claims, and declining uneconomical changes. We could turn the
accepted counterexamples into fixes and regression tests before a user had
to find them.
