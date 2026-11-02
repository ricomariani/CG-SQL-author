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
appendix picks up on May 15, 2026. Essentially all the new findings from
that point came from AI-assisted analysis. Some were security problems, some
were ordinary bugs, and some were improvements to the tests themselves.
There were also a few proposals I declined. I'll get to those.

The earlier article describes a compiler getting regular daily use from
hundreds of developers at Meta. CQL still gets that use, but not through this
open-source version. In particular, quoted identifiers are a feature of my
fork, and both public blob serialization facilities have been lightly used.
The internal backed-blob implementation was different and hardened separately.
Those differences in use explain quite a bit of what follows.

### How I put this together

I used an AI coding agent to review the history and individual fixes and help
write this appendix. I checked the results and supplied the context about how
we built and used CQL.

The window starts **on May 15**, including that day's first blob and extension
findings. The last preceding mainline commit is
[`8793b00f`](https://github.com/ricomariani/CG-SQL-author/commit/8793b00f), dated
January 28. There were no intervening mainline commits. The comparison is
therefore reproducible as:

```text
git log --first-parent 8793b00f..837956ba
git show <commit> -- <affected files>
```

The range has 73 first-parent commits, including documentation, releases,
tooling, and follow-ups to earlier fixes.

We split the large correctness proposal, #205, into smaller changes. Those
landed in PRs #207 through #253, along with additional security follow-ups.
I've used the final fixes for this account; several changed considerably
during review.

---

## How much did we find?

I count **68 finding groups** in this work: **52 bugs in the compiler,
runtimes, and samples; 8 test/tooling problems; and 8 preventive changes**.
A group can affect several entry points or backends. I count the shared
canonical-name mistake once, for example, rather than once per emitter.

These are reviewed groups, not a count of commits or failing assertions.
The UTF-8 work also completed earlier human-reported problems. Including
those repairs here doesn't give AI credit for the original reports.
The .NET fixture's ASan load failure was a regression introduced during this
work; I keep that follow-up separate from the 68 original findings.

### Priority and security are separate questions

These are my retrospective **fix priorities**. They aren't exploit-severity
scores. **Critical** covers hostile-data memory failures, urgent and broadly
disruptive failures in ordinary supported use, and demonstrated major security
impacts. **Important** covers serious wrong-code, wrong-result, or storage
failures. **Medium** covers more limited features,
inputs, and configurations. **Low** covers small test gaps and preventive
work with no known failing ordinary caller.

| Priority | Security bugs | Other correctness bugs | Test/tooling | Preventive | Total |
|---|---:|---:|---:|---:|---:|
| Critical | 6 | 0 | 0 | 0 | 6 |
| Important | 0 | 16 | 0 | 0 | 16 |
| Medium | 1 | 29 | 4 | 2 | 36 |
| Low | 0 | 0 | 4 | 6 | 10 |
| **Total** | **7** | **45** | **8** | **8** | **68** |

The security column is limited to the hostile-blob reader/update boundary
described below. Compiler crashes, bad generated text, and missing internal
contracts haven't been promoted into that column on the strength of their
failure mechanism.

### Bugs per KLOC

For density, I use a matching source surface: the root `sources/*.c` and
`*.h` files except `unit_tests.c`, plus the grammar, lexer, and Lua runtime.
This excludes tests, generated distributions, vendored SQLite, Python
bindings, and the extension bridge. Counts are physical lines, including
comments and blanks, consistent with the earlier appendix's measurements.

| Measure | Count |
|---|---:|
| Core source before the audit, `8793b00f` | 89,419 lines |
| Core source after the fixes, `837956ba` | 90,377 lines |
| Bug groups within that source surface | 45 |
| Of those, security groups | 7 |
| Of those, other correctness groups | 38 |
| Additional preventive groups within that surface | 6 |
| Core bugs found per pre-audit KLOC | **0.50** |
| Core security bugs per pre-audit KLOC | **0.08** |
| Core other correctness bugs per pre-audit KLOC | **0.42** |

The other seven correctness groups belong to samples and tools outside that
denominator. Dividing all 68 findings by the compiler's size would mix
different code populations and count preventive work as bugs.

I think the code held up pretty well. This was a concentrated examination
of a mature implementation, including features with very little use.
The repairs were generally local, and many of the failures required inputs
or combinations that the existing tests had never tried. The findings below
show where the tests were too narrow.

### Compared with the human-found era

My recollection of the heavily used Meta version is roughly **12 operational
bugs per year**. Using the same 89.419 KLOC merely as a scale reference gives
about **0.13 bugs/KLOC/year**. The earlier appendix's narrower C/header
denominator, 82.575 KLOC, gives about **0.15**.

| Human-era observation | AI-assisted audit |
|---|---|
| Roughly 12 operational bugs per year, from maintainer recollection | 52 compiler/runtime/sample bug groups over this review |
| Daily use by hundreds of developers at Meta | Targeted examination of the OSS fork, including lightly used features |
| About 0.13 operational bugs/KLOC/year at the reference size | 0.50 core bug groups/KLOC in a concentrated pass |

We don't have a comparable census of every human-found development-time bug.
The annual field rate and the audit yield have different units and different
inputs. I wouldn't turn them into a claim that one method found bugs some
multiple faster. The useful comparison is the additional cases this
examination reached after years of development, testing, and operational use.

The counting notes near the end explain the grouping decisions.

---

## Summary

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
5. **Wrong assumptions.** The C hex-escape rules surprised me. Lua's truthiness
   and numeric conversions supplied a few more examples.
6. **Basic error handling in test drivers.** We were ignoring some errors
   that could make a test result misleading.
7. **Checking the result.** JSON can parse and still contain the wrong string.
   SQL can execute and create a table with the wrong name.

### Fresh eyes

The AI analysis was ruthless and tireless. It was fresh eyes on code I had
been looking at for years, and it kept reconsidering assumptions. Does this
count really fit? Is this name already encoded? Who checked this argument?
What did the test actually verify?

Most of the findings were worth fixing. Only a few proposals were unwise,
beyond what I expect the system to do, or truly uneconomical. I spent a fair
amount of the review working out the smallest sensible fix. A repeated graph
traversal, for instance, wasn't worth extra state given the schema graphs
we actually see.

---

## Security findings

### Which findings belong here?

A security finding needs an attacker, something they control, and a trust
boundary they can cross. A buffer overrun or broken quoting can be a horrible
correctness bug. Calling the mechanism "memory corruption" or "injection"
doesn't establish the security case.

That was a recurring problem with the AI's security reports. It could find
a real bug and attach a dumb security argument. Giving the supposed attacker
control of trusted program text or internal call arguments doesn't establish
an attack. I still wanted many of those correctness fixes.

The compiler processes application code. Its source author already controls
what program they are asking it to generate. We need to establish what the
compiler is expected to protect from that author before calling a failure
a vulnerability. Inventing a build service that accepts contributed source
doesn't answer that question.

### Serialized data: validate the whole representation

The blob readers have an explicit requirement to handle hostile bytes.
An attacker who can supply a blob controls its counts, offsets, types, and
payload. The reader has to reject malformed input without out-of-bounds reads
or writes. That is the trust boundary for the bounds failures below. The
security claim applies where an application accepts blobs from less-trusted
sources.

The backed-table UDF sequence began on May 15 with
[`2ed3ac9e`](https://github.com/ricomariani/CG-SQL-author/commit/2ed3ac9e).
It checked computed blob shapes and selected payload ranges and corrected
inconsistent type-code handling between creation passes. July's
[`1432fa66`](https://github.com/ricomariani/CG-SQL-author/commit/1432fa66)
then validated **retained** variable fields before updates copied them.
An update has to check the fields it preserves as well as the replacement.

The old reader made the assumption explicit:

```c
// we know enough to make the shape and get the offsets; the variable size is
// not computed but that is of no import since we are not yet validating all
// the internal offsets (blobs are assumed to be well formed for now)
```

That comment came from code which had started as a test implementation.
The cursor serializer had expected hostile input from the beginning; the
public backed-table UDFs acquired that requirement as they became useful
outside the original tests. Both facilities were lightly used.

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
payload fits. Updating one field adds another obligation: every preserved
variable field will also be read and copied. July's correction checked those
fields, including their string terminators.

Almost always, I'd intended to do these checks at another level and then
forgot to check at all. The missing branch cannot show up as an uncovered
line. The review question has to be: which function actually establishes
this precondition?

[`3b2b0228`](https://github.com/ricomariani/CG-SQL-author/commit/3b2b0228)
rejected unknown serialized type codes.
[`2c3b89d0`](https://github.com/ricomariani/CG-SQL-author/commit/2c3b89d0)
completed an important error-policy change: malformed arguments or storage
produce `SQLITE_ERROR`, not a successful SQL `NULL`. A valid sparse value blob
with an absent nullable field can still return `NULL`.

Returning NULL for corruption let a query continue as though the value were
merely absent. This error-reporting fix also matters for ordinary corrupt data,
with no attacker involved.

#### Overlapping fields

The later overlap repair, [#211](https://github.com/ricomariani/CG-SQL-author/pull/211),
found another assumption. Two serialized fields could each describe a
valid range while sharing some or all of their bytes. Starting from the
physical input length and adjusting changed fields underestimated the output
when the updater copied each logical field separately.

For example, two strings sharing one payload need that payload twice when
rewritten into separate storage. Every source read can be in bounds while
the destination is too small.

I chose to keep accepting overlapping fields. We size the output from the
sum of validated logical field lengths in both key and value updates,
including deletions. The regression inputs were only 47 bytes for a key blob
and 71 bytes for a value blob.

The allocation mistake can be seen without a large binary dump. Suppose
two string descriptors share `"abc"` and its terminator. The stored string
length is three; each output copy needs four bytes:

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

Both source ranges pass a bounds check. Copying them needs eight payload
bytes. Starting from the four physical input bytes underallocates the
destination even when no field is being replaced.

The validator therefore also computes the sum of logical field lengths.
The updater starts with that sum and adjusts for replacements and deletions.
Rejecting overlap would have been a larger compatibility change than fixing
the allocation.

This case added a test dimension that ordinary round trips could never
produce: the normal writer emits separate payloads. A reader of hostile
data has to handle representations outside its own writer's output.

#### A four-byte header was enough to defeat the old stream arithmetic

The May 15 stream fix,
[`c5eddda7`](https://github.com/ricomariani/CG-SQL-author/commit/c5eddda7),
corrected a check that proved only the start of an offset word was present.
The October follow-up,
[#214](https://github.com/ricomariani/CG-SQL-author/pull/214), found that the
new `(index + 2) * 4` expression could itself overflow.

The repair first proves that the count and complete offset table fit, using
division before multiplication. It then validates:

```text
table_end <= selected_start <= selected_end <= blob_length
```

Count and offset loads use `memcpy`, avoiding alignment and aliasing
assumptions. Rejection also clears an existing cursor row and its references.

A four-byte blob declaring a huge count was enough to reach the bad arithmetic.

The old guard was:

```c
if (index < 0 || index >= count || (index + 2) * 4 > len) {
  goto error;
}
```

For `index = 536870910`, `(index + 2) * 4` exceeds signed 32-bit range.
Checking the length after doing that arithmetic is too late.

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

Those byte spellings describe the little-endian test environment. None
contains enough bytes for its declared offset table. Each must fail before
an offset is read.

The rejection test also starts with an existing cursor row containing a
string reference. After each failed decode it checks:

```sql
EXPECT_EQ!(hit, true);  -- The call raised SQLITE_ERROR.
EXPECT_EQ!(C, false);   -- The old row is no longer present.
EXPECT_EQ!(C.z, null);  -- Its string reference has been cleared.
```

The useful test categories are visible here: truncated shape, arithmetic
overflow, an offset inside the table, invalid indices, and rejection while
the destination already owns data. Random byte corruption alone would be
unlikely to cover all of them.

#### Counter width was a separate representation limit

[#219](https://github.com/ricomariani/CG-SQL-author/pull/219) rejected type
headers beyond 65,535 fields **before** 16-bit counters wrapped and extra fields
could be checked against metadata beyond the destination. A roughly 64 KiB
hostile header makes that boundary realistic.

We kept the existing format limit.
Compiler-side narrowing is protected by a contract; malformed wire input
returns an error. Bit indices were widened separately because a nullable
Boolean can contribute both a presence bit and a value bit. C and Lua use the
same field-count policy.

---

## Coverage left input dimensions untested

The compiler's 100% line coverage was useful throughout this work. It forces
reachable syntax and AST shapes through fail-fast handlers. It doesn't tell
us which values, sizes, configurations, or combinations have passed through
an executed line.

The most useful failures here exposed dimensions missing from the tests.
A serializer had seen every field type without seeing a moving allocation.
A string helper had seen comment markers without seeing an empty buffer.
JSON tests had exercised an encoder without comparing the decoded Unicode
text on both signed- and unsigned-char hosts.

### A moving allocation changes the meaning of a saved pointer

The cursor serializer writes type information, a bit vector, then field
payloads. The bit vector records nullable-field presence and Boolean values.
The old code retained its address:

```c
uint8_t *bits = cql_bytebuf_alloc(b, bitvector_bytes_needed);
memset(bits, 0, bitvector_bytes_needed);
```

Later, a string or blob append could grow `b`, freeing the allocation that
contained `bits`. The next nullable or Boolean field still did:

```c
cql_setbit(bits, nullable_index);
```

Every read of that code is plausible if the rows stay small. A single long
first field makes the pointer stale before the next bit write.

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

The later field-count repair widened that last index to 32 bits. The lifetime
repair itself was to stop carrying an interior pointer across appends.

Here is the first half of the runtime regression. The declared field order
is important:

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

The 1,025-byte string exceeds the initial 1,024-byte buffer. The longer
string and blob force further growth, with bit writes after each. The
second half of the actual test repeats growth with absent nullable fields;
their presence bits must remain clear while the later nonnull Boolean
still writes to the current allocation.

This is a test-design improvement we can reuse. Small/large is a weak size
classification for a growable buffer. Before growth, across one growth,
and across several growths with later writes are distinct cases.

### Empty after filtering is still empty

The comment-marker scanner had a much smaller version of the same coverage
problem. Its buffer length includes the terminating zero. An empty buffer
therefore has `used == 1`:

```diff
-for (uint32_t i = 0; i < b->used - 2; i++) {
+for (uint32_t i = 0; i + 2 < b->used; i++) {
```

Unsigned subtraction made the old empty-input bound enormous.
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

ASan reproduced the old out-of-bounds scan. The test also checks that changing
comment markers preserves the logical length.

Filtering supplied another empty case in
[#222](https://github.com/ricomariani/CG-SQL-author/pull/222). An enum could
have declarations but no public members after hidden members were excluded.
The deduplication bound `enum_count - 1` then underflowed. A test of an empty
declaration wouldn't cover that route to an empty working set. We needed an
all-hidden declaration and the ordinary diagnostic for the resulting switch.

### A heavily used format still had untested paths

JSON schema was heavily used. The full-string encoder had learned to
preserve valid UTF-8, but the pretty-quoted SQL path still encoded individual
bytes. For the UTF-8 sequence `E2 80 A2`, representing U+2022, it emitted:

```json
"\u00e2\u0080\u00a2"
```

That JSON parses. Its value has three characters in place of the intended
one. A syntax validator could approve every output while missing the damage.

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

Users had been reporting JSON problems for years. I hadn't followed through
with enough test diversity. The final tests compare decoded attribute and
SQL strings, exercise both encoders, and run unsigned-char configurations.
They retain the established malformed-byte policy, including escaping a
sequence followed by an extra continuation byte.

This is where usage and coverage both ran out of variety. Ordinary JSON
consumers supplied lots of use without supplying these combinations of
encoding path, input bytes, and host signedness. Schema upgrade needed a
long period of additional diversity after reaching 100% coverage too.

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
size disagreement: an amalgam destination used 255 bytes while `_fullpath`
was allowed `_MAX_PATH`. The diagnostic printer had yet another size
dimension: a 2,100-`NOT` AST could exhaust its indentation buffer. Its
[#215](https://github.com/ricomariani/CG-SQL-author/pull/215) repair truncates
diagnostic descent with a marker while leaving accepted SQL nesting alone.

These are memory-safety bugs. Their security classification still requires
an attacker-controlled input and a protection the compiler is expected to
provide. The cases establish why the bounds were wrong.

---

## A changed invariant has consumers I forgot

Quoted identifiers are lightly used and exist in my fork, not in the internal
version whose use at Meta supplied so much of CQL's earlier feedback.

I developed QIDs test-first, with a burndown list of every major identifier
usage I could think of. I tested the crap out of them, and on the whole I
think we did well. But even I can't remember all the places identifiers can
creep in. It's a major invariant change.

Many emitters used to print a stored name directly. With QIDs, each one has
to turn that name into the right form for its output.

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

A feature can be correct in the ordinary `CREATE TABLE` path and still be
wrong in virtual tables, constraint metadata, generated drops, query-plan
programs, or one language wrapper.

The important failure mode was an incomplete inventory. Each ordinary
table test could pass while a forgotten consumer kept the old rule. More
examples through the already-correct emitter would do nothing for that
consumer.

### Successful execution can use the wrong name

[#240](https://github.com/ricomariani/CG-SQL-author/pull/240) fixed virtual-table
creation that printed the stored string directly. For `doc store`, SQLite
successfully created `X_docX20store`; subsequent correctly quoted inserts into
`doc store` failed.

The repaired test checks the actual catalog name, inserts and reads data,
and drops the intended table.

Here is a complete CQL declaration of the kind that failed:

```sql
create virtual table if not exists `doc store`
  using fts4(content) as (content text);
```

The old SQLite output used the internal name:

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS X_docX20store USING fts4(content);
```

That statement succeeds. The next operation, correctly rendered for the
same source name, fails:

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

The single-case integration check can be written as this complete function.
Its argument is the compiler's emitted SQLite schema:

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
classes across three module-argument forms. Those are different consumers
of the same source declaration. SQLite's catalog supplies the independent
answer about the object we actually created.

[#230](https://github.com/ricomariani/CG-SQL-author/pull/230) found the same
representation mistake in deleted or unsubscribed recreate-table drops.
An encoded-name lookalike control proved that the intended table was removed
without deleting an unrelated table with the internal-looking spelling.

### A name can be encoded correctly in the wrong language

[#242](https://github.com/ricomariani/CG-SQL-author/pull/242) decoded
`no_table_scan` names but then put them between raw CQL quotes. A literal
backslash followed by `t` became a tab. The generated program could compile
yet stop matching the actual plan text, silently losing its alert.

The same PR fixed runtime graph and alert strings inserted into JSON without
JSON escaping. We had escaped statement text and missed these other fields.

For a name containing a literal backslash followed by `t`, the relevant
generated CQL strings are:

```sql
"backslash\t"   -- Wrong: CQL decodes a tab.
"backslash\\t"  -- Correct: CQL decodes a backslash and the letter t.
```

Both strings are legal source. Only one can match the literal name in
SQLite's plan text. A test that stops at successful generation or compilation
misses the loss of the scan alert.

The runtime helper is ordinary C/Lua string encoding. It does not depend on
SQLite JSON support or database access.

[#241](https://github.com/ricomariani/CG-SQL-author/pull/241) normalized
constraint names so foreign-key and primary-key metadata referred to the same
decoded names as the table and column declarations. It separately JSON-encoded
index and predicate expressions, where raw quote wrapping could produce
invalid JSON or silently reinterpret backslashes.

The metadata identity problem is just as concrete:

```text
Table declaration's JSON name:       parent table
Foreign key's referenceTable:        X_parentX20table
```

Neither JSON parsing nor testing each field's string type can establish
that these refer to the same table. The regression resolves each foreign-key
reference against the emitted table and column declarations.

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

The targeted table-helper test separately covers both quote classes:

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
this procedure, and restores the previous dictionary. Setup is important:
otherwise a test could fail before reaching the identifier operation.

These are correctness examples. Reading a name from the catalog doesn't
establish attacker control or a gain in SQL authority. We fixed the quoting
without treating every unusual name as a demonstrated security attack.

### Identity and output spelling are different

[#232](https://github.com/ricomariani/CG-SQL-author/pull/232) repaired C and Lua
emitters that used a reference's source spelling instead of its resolved
canonical name. CQL resolves names without case sensitivity; C and Lua do not.
The same cursor field referred to with different case could therefore produce
an undeclared C name or the wrong Lua field/global.

This one needs only a case change in an ordinary name. At the target-language
level the mistake is equivalent to:

```c
struct row {
  int Total;
};

void update(struct row *r) {
  r->total = 1;  /* C has no such member. */
}
```

CQL accepted the reference because its semantic lookup had resolved it.
Printing the reference's original spelling threw that work away. Tests
need declaration/reference case variation even when every character is an
ordinary letter.

[#245](https://github.com/ricomariani/CG-SQL-author/pull/245) brought projection
accessors into agreement across Java, C#, and the two Objective-C generators.
Legal-name encoding, collisions, reserved wrapper members, and matching
declarations/implementations are each the wrapper's responsibility. The repair
kept that policy local to the customizable samples rather than adding a new
compiler JSON naming contract.

The burndown list and TDD helped a great deal. I still missed places that
assumed the old rule. I'd use an AI pass to check the next burndown list
against the actual consumers in the code. That could find omitted paths
before their first real use.

---

## Sometimes I was wrong about the language

Some of the missing cases came from a wrong model of the implementation
language. Once you believe an encoder or conversion has the right rule,
it's easy to make the golden output agree with it. An independent execution
check has a better chance of challenging that belief.

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

The test has to inspect the bytes used by generated C code.

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

The review had to include non-executable output as well as ordinary strings.
These are generated-program correctness cases; the source author already
controls the program.

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
fractions becoming zero, and NULL preservation. Both C and Lua can run the
same CQL cases. A collection of positive fractions adds little after the
first; crossing zero tests the rule we had actually missed.

### CQL Boolean rules don't come from Lua

In Lua, `true == 1` is false and numeric zero is truthy. CQL permits Boolean
and numeric comparisons and uses SQL-style numeric conditions. The
translation has to implement those rules explicitly.

The runtime test in
[#233](https://github.com/ricomariani/CG-SQL-author/pull/233) includes:

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
Boolean would make true equal to 2 or 0.5. CASE needs Boolean-to-number
normalization. A fragment's IF predicate needs number-to-Boolean
normalization so zero selects the false branch.

The normal harness checked generated Lua text without executing its runtime
suite. Running these cases in Lua exposed results the goldens had approved.
For backend work, generation and execution have to be separate checks.

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

Both produce `a:b:c`. The resulting partition contains children from two
different parents. Doubling the separator also leaves an ambiguity over
which field owns a boundary colon.

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
context where they no longer held. This family was familiar from the
human-found era. The missing tests combined conditions, exits, aliases, and
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

The first branch reaches the call with `a` still NULL. The compiler must
reject it. The ELSE IF and ELSE branches both know `a` is nonnull because
the first condition was false, but the ELSE IF returns.

The implementation removed that returning branch from the count of
continuing branches while leaving its inherited nonnull contribution in
the accumulated history. The stale contribution made the nonnull fact
appear to cover both remaining branches.

The repair delays inherited-history accumulation until a branch is known
to continue. Simply discarding all inherited history would reject this
valid counterpart:

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
nonnull value. We needed both tests, plus local overwrites, empty branches,
and other jumping statements. Executing the merge code had never established
that these combinations gave it the right accounting model.

### Identity and scope need to survive the shortcut paths

The same review question applies to aliases: what storage does this argument
actually name? Comparing source spellings or AST pointers misses case
variants, dotted fields, and argument-bundle aliases. The
[#224](https://github.com/ricomariani/CG-SQL-author/pull/224) checks use
resolved mutable storage instead. An evaluated IN expression can share its
source spelling with an OUT target without being a second mutable alias;
that distinction needs its own control cases.

Rowid and JSON-function repairs exposed another carried property.
An unmatched row from the right side of an outer join has a NULL rowid,
even though a real row's rowid is nonnull. Some sources have no implicit
rowid at all. The tests in
[#225](https://github.com/ricomariani/CG-SQL-author/pull/225) cover source
eligibility and the join transformation. Likewise,
[#226](https://github.com/ricomariani/CG-SQL-author/pull/226) makes JSON
scalar functions preserve the appropriate nullability and sensitivity
flags, including nullable results from missing paths.

The direct blob-call checks in
[#227](https://github.com/ricomariani/CG-SQL-author/pull/227) show why testing
only the usual higher-level route is insufficient. Rewritten DML supplies
assignment and layout checks. A direct call must also establish consistent
partitions, unique columns, and complete primary-key order. The first field
selects the storage operation, so accepting an inconsistent later field
can send the operation down the wrong storage path.

This is compile-time validation of the requested operation. The binary
reader's malformed-data checks cannot supply it later.

### Numeric spelling also carries a type

[#220](https://github.com/ricomariani/CG-SQL-author/pull/220) checked integer
literal ranges rather than accepting silent conversion saturation. It retained
the exceptional magnitude needed to spell `INT64_MIN` under unary minus and
preserved high-bit hexadecimal patterns through folding, JSON, and generated C.
Emitting a high-bit pattern as an unsigned C expression can change comparison
and division behavior even when its bits look right.

[#221](https://github.com/ricomariani/CG-SQL-author/pull/221) replaced unchecked
numeric conversion for `--min_schema_version` and line directives. It rejected
empty, negative, junk-suffixed, and out-of-range values and reserved line-number
headroom before installing a source mapping.

I declined the broader arithmetic and shift proposals discussed below.

For example, the C expressions below have the same low 64 bits for the
hexadecimal operand but different comparison behavior:

```c
0xffffffffffffffffLL < 0  /* false: the literal has unsigned type */
(-1LL) < 0              /* true: the intended signed value */
```

CQL's high-bit hex pattern is signed. Preserving its bits while emitting an
unsigned C expression loses that semantic fact. The test therefore compares
raw, folded, and generated results, rather than only the printed digits.

---

## The tests need an independent answer

Several failures survived because the check established something weaker
than the property the application needed. Generated text could be stable,
JSON could parse, and a helper could return success while the requested
object, value, or physical change was wrong.

The virtual-table test above illustrates this well: SQLite's catalog and
an insert into the intended name tell us more than CREATE's return code.
The schema and reporting cases supplied two further examples.

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

Changing I can leave the group checksum unchanged. Creating a fresh database
works, but upgrading an existing one can omit the new uniqueness constraint.

The old loop included:

```c
table_crc ^= crc_charbuf(&make_table);
table_crc ^= crc_charbuf(&delete_tables);
table_crc ^= crc_charbuf(&update_indices);
```

Only the first line belongs to each table. The repair moved the cumulative
drop/index hashes to the end of the group.

The regression checks physical state. The upgrade fixture defines
`g1(id integer primary key, name text)` in a two-table recreate group. Version
1 adds `g1_name`, an index on its first table. Before each upgrade, the test
inserts a probe:

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

Compatibility mattered: corrected group hashes can cause a one-time maintenance
recreate after a later schema change opens the outer complete-schema gate.
The bundled runtime recreates a called group, discarding its data. It does not
compare actual SQL and automatically decide that nothing needs doing.
Single-table hashes were preserved, and recompiling an identical complete
schema does not alone open the outer gate.

### Query-local numbers aren't global identities

The query-plan statistics in
[#243](https://github.com/ricomariani/CG-SQL-author/pull/243) had correct
graphs and query text, which made a visual inspection reassuring. The search
count could still be wrong.

Plan node IDs are local to a statement. A simplified pair of stored plan rows
shows the problem:

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

The regression needs multiple statements with reused node IDs, including
different kinds of search. Running each statement in isolation cannot
expose this contamination.

### Parseable output can still describe a different program

The UTF-8 case already showed why parsing output is too weak a check.
SQL expression grouping supplied an independent version of the problem.
[#239](https://github.com/ricomariani/CG-SQL-author/pull/239) fixed another
way we could change the meaning of emitted SQL. It preserved
right-nested grouping among `||`, `->`, and `->>`. They share left-associative
precedence, but mixed pairs are not associative.

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

This tests the meaning at each end. Producer/consumer agreement alone can
also be misleading if both share the same bad convention, as the older
C/Lua serialization mismatch showed. SQLite execution, the actual CQL parser,
and cross-backend checks supply useful independent answers.

---

## Lightly used integrations need complete use-cases

Some failures were spectacular enough to say something about use. The
nullable-binary failures discussed in the human-era appendix could hardly
survive an application that actually stored and retrieved nullable values.
The .NET sample supplied an equally direct example in this review.

### The binary argument was never sent

[#246](https://github.com/ricomariani/CG-SQL-author/pull/246) completed .NET
blob marshalling. This is the old generator template expanded for a parameter
named `value`:

```c
void *bytes_value = "xx";
int len_value = 2;
blob_ref_value = cql_blob_ref_new(bytes_value, (cql_uint32)len_value);
```

Every supplied blob became the same two bytes. A generator golden could
approve that output forever. Any actual binary use-case would expose it.

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
and projected result sets. NULL and empty remain distinct in both directions.
It reads returned data twice and releases the owning result set, respecting
the borrowed handle in a projection. Copying bytes back and freeing native
storage are part of a complete binding example too.

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
cleanup. A one-call test has nothing to overwrite. The regression exercises
nested calls, checks application globals, and verifies input/INOUT forwarding.

Scanner ownership needed repeated calls too.

[#217](https://github.com/ricomariani/CG-SQL-author/pull/217) repaired ownership
of main/include files and current/suspended Flex buffers. A compiler-owned
input must be released; a borrowed caller stream or buffer must remain the
caller's to release, including after an error.

The repair closed include files at EOF, released remaining owned handles
during cleanup, and deleted saved parent buffers exactly once while leaving
the current scanner state to Flex's destruction path. A separate regression
ran repeated compilations under a small descriptor limit, including nested
includes, failures, recovery, and borrowed inputs.

The ordinary command-line process exits after one compilation. The repeated
compilation tests made these leaks visible. Repeated compiler invocations
and SQLite's cursor lifecycle need tests that outlive one successful call.

---

## The test infrastructure had bugs and blind spots too

Ignoring a failed transaction or building stale generated code can undermine
the checks that follow. These drivers often got very basic error treatment.
The fixes here were ordinary error checking and better assertions.

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
ties the build to successful regeneration. A useful negative test makes
regeneration fail while leaving old generated files in place. Otherwise
we're only retesting the successful route.

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

This defines the private C test generator's wraparound. It doesn't establish
a new arithmetic policy for CQL programs.

### A permissive or disconnected checker leaves a hole

The schema JSON validator used a case-insensitive scanner. That let
wrong-case field names satisfy a supposedly canonical schema contract.
[#253](https://github.com/ricomariani/CG-SQL-author/pull/253) removed the
global option:

```diff
-%option noyywrap nodefault yylineno case-insensitive
+%option noyywrap nodefault yylineno
```

Canonical uppercase `CRC` remains uppercase. JSON numbers still accept
either exponent letter through an explicit `[Ee]` rule. This was a hole in
the validator; it wasn't evidence that the compiler was emitting wrong-case
JSON keys.

The default harness also omitted an existing extension-encoding check.
[#252](https://github.com/ricomariani/CG-SQL-author/pull/252) wired it in.
That test already ran in the extension suite and CI, so calling it a new
test would overstate the change.

There was a more subtle configuration gap in global-procedure tracing.
The emitter used a function name where `_PROC_` needed a C string. The normal
no-op tracing macro never consumed that argument.
[#231](https://github.com/ricomariani/CG-SQL-author/pull/231) tests a tracing
configuration that actually uses it. Exercising the emitter with the default
macro had given us no check of the emitted value's type.

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

The test deliberately constructs the precondition:

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

The seed forces growth when duplicated; the final append tests an interior
slice. This locks down a useful invariant for future callers.

For formatted text, I chose a smaller contract. Supporting a format string
inside the destination buffer would complicate a two-pass formatter. The
[#208](https://github.com/ricomariani/CG-SQL-author/pull/208) check prohibits
that alias:

```c
uintptr_t source = (uintptr_t)format;
uintptr_t start = (uintptr_t)b->ptr;
Contract(source < start || source - start >= b->max);
```

String arguments retain a documented non-aliasing precondition too. This
doesn't offer arbitrary self-formatting. We had no known caller needing it.

### A contract must survive the configuration that relies on it

Before this work the compiler macros were:

```c
#define Invariant assert
#define Contract assert
```

Compiling with `NDEBUG` removed them. The runtime had the same dependency.
The small always-on compiler replacement is:

```c
#define Invariant(condition) do { if (!(condition)) abort(); } while (0)
#define Contract(condition) do { if (!(condition)) abort(); } while (0)
```

The runtime change landed in
[#204](https://github.com/ricomariani/CG-SQL-author/pull/204), with the
compiler completed in #208. This keeps fail-fast checks meaningful in release
builds. It doesn't establish that every caller formerly reached a bad
unchecked access.

Other preventive checks make the intended contracts explicit: runtime
result-set/list bounds in #204, matching row sizes before result-set equality
in [#213](https://github.com/ricomariani/CG-SQL-author/pull/213), and extension
callback/ownership conditions in
[`11e277c2`](https://github.com/ricomariani/CG-SQL-author/commit/11e277c2).
None supplied a demonstrated ordinary-use failure in this review.

The SHA-256 code in
[#209](https://github.com/ricomariani/CG-SQL-author/pull/209) had a
portability assumption: it allocated a byte array and read it through an
`int64_t *`. The fix allocates integer storage and gives the digest writer a
byte view, preserving the bytes while guaranteeing alignment and the right
object type. A convenient stack address on the machines we happened to use
had hidden that requirement.

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

We simplified several proposals during review: size blob output by logical
length, use a depth guard for macros, length-prefix Lua keys, and share a
runtime cast helper. The first proposals for these had considerably more
machinery.

### Proposals we did not adopt

I declined these proposals.

| Proposal | Why it was declined |
|---|---|
| Checked constant arithmetic and enum increments (original item 13) | A new overflow, division/remainder, and floating-point policy would need matching runtime/backend semantics. I didn't think the benefit justified that language change. |
| Defined shifts and numeric conversions (14) | A defined CQL shift/conversion policy would need consistent folding and emitted operations across backends. Applying checks only during folding wouldn't give us that. |
| SQLite-style loose `IN`/`NOT IN` semantics (19) | CQL deliberately differs from SQLite on RHS NULLs. The documented behavior makes loose `1 NOT IN (NULL, 5)` true. I didn't want to change it. |
| Deduplicated recreate dependency traversal (22) | The DFS detects cycles correctly. Duplicate edges and shared descendants repeat work, but we had no failing case or practical workload that made the extra visited-set state worthwhile. [#228](https://github.com/ricomariani/CG-SQL-author/pull/228) documents that decision. |
| A generated-C symbol registry and reserved-name rejection (25) | The C compiler already diagnoses symbol conflicts. Tracking every generated symbol and scope was too much machinery. Banning only `_rc_` would miss other collisions; broad underscore bans would reject legitimate conventions. |
| Lua keyword/name mangling (remainder of 27) | I didn't approve a new mangling scheme or naming restrictions. [#232](https://github.com/ricomariani/CG-SQL-author/pull/232) fixes canonical spelling only. |

I also left numeric/Boolean validation of edited JSON out of #244. The sample
normally consumes compiler JSON, and the attribute fix was about preserving
those values. It doesn't provide comprehensive validation of hostile JSON.
Diagram modes were outside that fix too.

---

## Counting notes

The counts describe the fixes reviewed here, including completed repairs to
human-reported problems. They don't measure how many independent discoveries
an AI made without help. I used these grouping rules:

| Source of findings | Groups |
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

The seven #204 groups are runtime collection bounds, non-elidable contracts,
Windows destination sizing, provenance line-comment encoding, Lua long-comment
delimiters, sample SQL encoding, and extension SQL/C encoding. The compiler
contract completion in #208 stays with the runtime contract group; the
format-alias contract is separate.

There are 47 PRs from #207 through #253. Excluding #228's comment-only declined
optimization and #247's newly introduced fixture regression leaves 45.
#238, #241, and #242 each repair two distinct failures; #251 repairs three.
That gives 45 + 3 + 2 = 50 groups. The four binding generators in #245 count
as one naming family, and the canonical C/Lua emitter error in #232 counts
once.

Routine release, documentation, build-maintenance, and signature-alignment
changes are excluded, as are declined proposals and ancillary renamings.
The three #251 groups remain test/tooling findings. The eight preventive
groups have no demonstrated ordinary-use failure in this review: extension
contracts, verifier heap storage, collection bounds, always-on contracts,
byte-buffer self-append, the format-alias contract, digest storage, and the
result-set row-size contract.

The seven security groups are the initial backed-blob shape/range checks,
the initial stream-word bound, retained-field validation, unknown-type
rejection, overlapping-field output sizing, complete stream-table validation,
and field-counter limits. The unknown-type abort is Medium priority; the
six hostile-data memory failures are Critical. These classifications apply
to the less-trusted blob boundary described earlier.

For the other bugs, Important includes stale serialization pointers,
incorrect numeric interpretation, flow/alias/type-property failures,
cancelled schema checksums, Lua results and wrapper state, generated C escapes,
SQL grouping, .NET marshalling, and the include/Windows memory bounds.
More limited encoding, metadata, source-validation, diagnostic, and lifecycle
failures are Medium. These are engineering judgments about fix priority,
not observed incident frequencies or exploit scores.

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
The density uses the pre-audit 89.419 KLOC:
45 / 89.419 = 0.50, split into 7 / 89.419 = 0.08 security and
38 / 89.419 = 0.42 other correctness groups per KLOC.
The human-era scale comparison uses 12 / 89.419 = 0.13 per year.
The operational estimate remains my recollection; the public history isn't
a complete incident ledger.

---

## What we learned about testing

We found bounds and allocation errors in readers of hostile data, basic
first-use failures in lightly used code, and missed consumers of the QID
invariant. Heavily used features still had gaps in encoding and test diversity.
Checks I'd intended for another layer never got implemented, and some test
drivers could hide failures.

That suggests several useful additions to the tests. Lightly used serializers
and bindings need complete use-cases that move real data, including NULL,
empty, and nonempty values. Malformed-data tests should vary counts, offsets,
types, and overlapping fields independently. QIDs show why even a careful
consumer inventory needs another pass against the code.

In established features, I'd expand along the dimensions we missed here:
allocation growth, negative values, numeric representation, quoting and
encoding combinations, repeated calls, and feature interactions. Checks
should compare decoded values and actual execution results. SQLite and the
other backend give us independent references for some of those checks. The
drivers have to propagate errors for the results to be reliable.

An AI pass could help trace the consumers of the next invariant change and
compare them with the test inventory. I'd also use it to look for
counterexamples to specific assumptions, then turn the useful examples into
regression tests.
