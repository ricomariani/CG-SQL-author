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

## Summary

Several things kept coming up:

1. **Light use.** Some failures were so basic that an actual use-case would
   have exposed them immediately. The .NET blob sample returned placeholder
   bytes.
2. **Test diversity.** We had covered the lines, but missed negative fractions,
   long payloads, unusual names, or another combination of features.
3. **QIDs.** Quoted identifiers changed a major compiler invariant. I had
   tested them extensively, but missed some places identifiers could appear.
4. **Missing validation.** Sometimes I hadn't thought of a check. Sometimes
   code assumed another layer had done the checking.
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

I grouped the findings this way:

| Class | Examples |
|---|---|
| Memory safety or injection | Buffer overruns, use-after-free, text escaping its intended SQL or generated-code context |
| Defensive hardening | Missing contracts, resource limits, unsafe helper preconditions with no known failing caller |
| Correctness and testing | Wrong results, rejected valid programs, incomplete samples, misleading test results |

Exposure depends on how CQL is used. A build service accepting contributed
source has different risks from a developer compiling their own application.
The runtime also reads stored bytes, which can be corrupt or attacker-controlled.
I've described the failures and the inputs that reach them; I haven't tried
to assign exploit severity.

### 1. Serialized data: validate the whole representation

The binary readers had some of the clearest security bugs. They have to deal
with corrupt, old, or deliberately malformed data.

The backed-table UDF sequence began on May 15 with
[`2ed3ac9e`](https://github.com/ricomariani/CG-SQL-author/commit/2ed3ac9e).
It checked computed blob shapes and selected payload ranges and corrected
inconsistent type-code handling between creation passes. July's
[`1432fa66`](https://github.com/ricomariani/CG-SQL-author/commit/1432fa66)
then validated **retained** variable fields before updates copied them.
An update has to check the fields it preserves as well as the replacement.

[`3b2b0228`](https://github.com/ricomariani/CG-SQL-author/commit/3b2b0228)
rejected unknown serialized type codes.
[`2c3b89d0`](https://github.com/ricomariani/CG-SQL-author/commit/2c3b89d0)
completed an important error-policy change: malformed arguments or storage
produce `SQLITE_ERROR`, not a successful SQL `NULL`. A valid sparse value blob
with an absent nullable field can still return `NULL`.

Returning NULL for corruption let a query continue as though the value were
merely absent.

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

### 2. Memory safety in the compiler and serializer

| Fix | Mechanism | Repair or test |
|---|---|---|
| [`4867d6a4`](https://github.com/ricomariani/CG-SQL-author/commit/4867d6a4), July 9 | An unbounded include-path spelling was copied into a fixed `PATH_MAX` buffer. | Crafted source could supply a long path that still resolved to an existing short path. Pool-backed storage removed the fixed destination. |
| [#204](https://github.com/ricomariani/CG-SQL-author/pull/204), Windows path handling | `_fullpath`'s permitted output size and the actual destination disagreed, including in the amalgam. | Platform-specific buffer sizing; resolved-path limits must match allocated storage. |
| [#210](https://github.com/ricomariani/CG-SQL-author/pull/210) | `used - 2` underflowed in an unsigned comment-marker loop for empty input. | ASan caught the out-of-bounds scan. We changed the loop bound and added short-input cases. |
| [#215](https://github.com/ricomariani/CG-SQL-author/pull/215) | Deep AST diagnostic printing could overrun its fixed indentation buffer. | The printer stops descent with an explicit marker. The compiler still accepts the same SQL nesting. |
| [#218](https://github.com/ricomariani/CG-SQL-author/pull/218) | Payload appends could reallocate a cursor serialization buffer while presence/Boolean writes retained an interior pointer. | A valid sufficiently large row could cause use-after-free writes. Retaining an offset and resolving it against the current buffer fixes the lifetime. |
| [#222](https://github.com/ricomariani/CG-SQL-author/pull/222) | Filtering hidden enum members could leave an empty buffer; `enum_count - 1` underflowed in deduplication. | Source could trigger an out-of-bounds empty-set access. The ordinary enum diagnostic must not assume a nonempty working set. |

The include-path bug was sneaky. `realpath` bounded the resolved
path, but the code copied the original spelling. Many redundant path segments
can collapse to a short result.

The serialization growth bug needed only an ordinary row with long strings
or blobs. The small test rows never moved the buffer.

### 3. Generated text is an execution boundary

[#204](https://github.com/ricomariani/CG-SQL-author/pull/204) repaired several
places where text crossed into another language without the right encoding:

- Decoded `#line` filenames were inserted into C and Lua line comments.
  Newlines could end the comment and expose following text as code.
- A fixed Lua long-comment delimiter could occur in echoed CQL source.
  The generator now chooses a closing delimiter absent from that source.
- `cqljson.py --sql` interpolated metadata strings into SQL without consistently
  quoting them as SQL literals.
- The SQLite-extension generator needed **SQL identifier quoting first**, then
  **C string encoding** for the completed SQL declaration.

With untrusted input, these mistakes can inject code or SQL. With trusted
input, a quote or newline in a name can still break the generated program.

The dynamic schema-drop repair,
[#212](https://github.com/ricomariani/CG-SQL-author/pull/212), belongs here too.
Names read from `sqlite_master` were inserted between square brackets. A `]`
could terminate the intended identifier. All four dynamic drop paths now use
double-quoted identifiers with embedded double quotes doubled.

The later [#230](https://github.com/ricomariani/CG-SQL-author/pull/230) fixed
static recreate-table names during code generation. I'll cover it with the
other QID cases below.

These are places where value parameterization doesn't help: identifiers,
comments, and text inside another generated program still need their own
encoding.

### 4. Contracts must exist in the build that needs them

The runtime headers said contracts and invariants should remain in release
builds, but defined them with `assert`. `NDEBUG` therefore removed them.
[#204](https://github.com/ricomariani/CG-SQL-author/pull/204) made standard and
CoreFoundation runtime contracts non-elidable, filled missing public
result-set/list bounds checks, and used overflow-safe range checks.

We made the compiler's `Contract` and `Invariant` definitions non-elidable
in [#208](https://github.com/ricomariani/CG-SQL-author/pull/208) as well.

[#213](https://github.com/ricomariani/CG-SQL-author/pull/213) added the missing
matching-row-size precondition to `cql_rows_equal`. Using the first result set's
row size to address both buffers is safe only when the physical sizes agree.

Contracts check caller and implementation obligations. Malformed stored blobs
need recoverable errors so the application can deal with bad data.

### 5. Limits and defensive checks

[#216](https://github.com/ricomariani/CG-SQL-author/pull/216) bounded macro
expansion at 256 active frames. Direct and indirect recursion receive an
ordinary diagnostic instead of consuming the stack indefinitely. A
constant-time depth guard was enough.

[#207](https://github.com/ricomariani/CG-SQL-author/pull/207) made the compiler's
byte-buffer self-append safe across allocation growth. We knew of no
production caller doing this, but it was easy to demonstrate the failure
with a deliberate overlapping append.

For formatting, [#208](https://github.com/ricomariani/CG-SQL-author/pull/208)
added a contract prohibiting a format string inside the destination allocation.
String arguments also have a documented non-aliasing precondition.

[#209](https://github.com/ricomariani/CG-SQL-author/pull/209) allocated hash digest
storage as aligned integer words and wrote it through a byte view. That removed
alignment/strict-aliasing assumptions while preserving the hash.

The May 15 removal of `alloca` from verifier helpers,
[`bdf53add`](https://github.com/ricomariani/CG-SQL-author/commit/bdf53add),
was another precaution in a test tool.

---

## Ordinary correctness findings

### 1. QIDs were a major invariant change

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

#### Successful execution can use the wrong name

[#240](https://github.com/ricomariani/CG-SQL-author/pull/240) fixed virtual-table
creation that printed the stored string directly. For `doc store`, SQLite
successfully created `X_docX20store`; subsequent correctly quoted inserts into
`doc store` failed.

The repaired test checks the actual catalog name, inserts and reads data,
and drops the intended table.

[#230](https://github.com/ricomariani/CG-SQL-author/pull/230) found the same
representation mistake in deleted or unsubscribed recreate-table drops.
An encoded-name lookalike control proved that the intended table was removed
without deleting an unrelated table with the internal-looking spelling.

#### A name can be encoded correctly in the wrong language

[#242](https://github.com/ricomariani/CG-SQL-author/pull/242) decoded
`no_table_scan` names but then put them between raw CQL quotes. A literal
backslash followed by `t` became a tab. The generated program could compile
yet stop matching the actual plan text, silently losing its alert.

The same PR fixed runtime graph and alert strings inserted into JSON without
JSON escaping. We had escaped statement text and missed these other fields.

The runtime helper is ordinary C/Lua string encoding. It does not depend on
SQLite JSON support or database access.

[#241](https://github.com/ricomariani/CG-SQL-author/pull/241) normalized
constraint names so foreign-key and primary-key metadata referred to the same
decoded names as the table and column declarations. It separately JSON-encoded
index and predicate expressions, where raw quote wrapping could produce
invalid JSON or silently reinterpret backslashes.

#### Identity and output spelling are different

[#232](https://github.com/ricomariani/CG-SQL-author/pull/232) repaired C and Lua
emitters that used a reference's source spelling instead of its resolved
canonical name. CQL resolves names without case sensitivity; C and Lua do not.
The same cursor field referred to with different case could therefore produce
an undeclared C name or the wrong Lua field/global.

This one needs only a case change in an ordinary name.

[#245](https://github.com/ricomariani/CG-SQL-author/pull/245) brought projection
accessors into agreement across Java, C#, and the two Objective-C generators.
Legal-name encoding, collisions, reserved wrapper members, and matching
declarations/implementations are each the wrapper's responsibility. The repair
kept that policy local to the customizable samples rather than adding a new
compiler JSON naming contract.

The burndown list and TDD helped a great deal. I still missed places that
assumed the old rule.

### 2. C escape syntax surprised the C programmer

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

### 3. Lua conversions, comparisons, and locals

| Fix | Failure | The missing test dimension |
|---|---|---|
| [#233](https://github.com/ricomariani/CG-SQL-author/pull/233) | Simple `CASE` compared Lua `true` with numeric `1`; conditional fragments treated numeric zero as Lua truthy. | Mixed BOOL/numeric values and zero-valued fragment predicates |
| [#234](https://github.com/ricomariani/CG-SQL-author/pull/234) | `math.floor(-1.9)` produced `-2` instead of C/SQLite's in-range integer cast result `-1`. | Negative fractions, including fractions between -1 and 0 |
| [#235](https://github.com/ricomariani/CG-SQL-author/pull/235) | Fetch-results temporaries were globals; nested calls could overwrite outer statement state and lose cleanup. | Reentry, application globals, and input/INOUT forwarding |
| [#236](https://github.com/ricomariani/CG-SQL-author/pull/236) | Stringified partition tuples collided, mixing children belonging to different keys. | Delimiter boundaries, NULL/text distinctions, binary bytes, and numeric precision |

The partition-key example is easy to see. Concatenating values
with colons does not distinguish `("a:b", "c")` from `("a", "b:c")`.
Text `"nil"` is not SQL `NULL`, and default numeric string conversion is not
an exact identity function for all doubles or full-width integers.

The repair used length-prefixed non-NULL fields and a distinct NULL
marker. It preserved byte-exact strings/blobs, full-width integers, and
integer/float equality for the same numeric value.

The ordinary harness generated Lua but did not execute its runtime suite.
The fixes needed execution tests in Lua.

### 4. Semantic facts were lost on less ordinary paths

| Fix | What the accepted program got wrong |
|---|---|
| [#223](https://github.com/ricomariani/CG-SQL-author/pull/223) | Flow facts inherited by a jumping branch contaminated the merge for continuing branches, permitting an unsafe nonnull assumption. |
| [#224](https://github.com/ricomariani/CG-SQL-author/pull/224) | OUT/INOUT alias checks compared spellings or AST identity instead of resolved mutable storage, missing case variants and dotted/bundle aliases. |
| [#225](https://github.com/ricomariani/CG-SQL-author/pull/225) | Implicit rowids were fabricated for ineligible sources or kept NOT NULL across outer joins; unmatched rows could lose their SQL NULL. |
| [#226](https://github.com/ricomariani/CG-SQL-author/pull/226) | JSON scalar functions dropped input nullability/sensitivity; missing-path forms still required nullable results. |
| [#227](https://github.com/ricomariani/CG-SQL-author/pull/227) | Direct backed-blob calls bypassed assignment, domain, duplicate-column, partition, and complete ordered-key checks normally supplied by higher-level usage. |

[#227](https://github.com/ricomariani/CG-SQL-author/pull/227) shows how a
validation check can get lost between layers. The storage operation is
selected from the first field, and key creation assumes complete primary-key
order. Direct calls need the same checks that the normal rewritten-DML path
provides.

[#222](https://github.com/ricomariani/CG-SQL-author/pull/222) covered another
kind of absence: an `ALL VALUES` enum containing only hidden members has no
public values. Filtering a nonempty declaration does not guarantee a nonempty
working set. The fix guarded sorting/deduplication and reused the ordinary
diagnostic without changing access to hidden values in normal switches.
The unsigned empty-set bound caused an out-of-bounds access, which is why
this case also appears in the memory-safety table.

### 5. Small numeric inputs exposed host assumptions

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

### 6. Schema checksums and query-plan statistics

[#229](https://github.com/ricomariani/CG-SQL-author/pull/229) found cumulative
index/drop buffers being hashed once per table in a recreate group. XORing the
same accumulated text twice could cancel its contribution. An index-only
change in a two-table group could therefore leave the group checksum unchanged
and suppress required work.

The fix moved those hashes to the group boundary.

Compatibility mattered: corrected group hashes can cause a one-time maintenance
recreate after a later schema change opens the outer complete-schema gate.
The bundled runtime recreates a called group, discarding its data. It does not
compare actual SQL and automatically decide that nothing needs doing.
Single-table hashes were preserved, and recompiling an identical complete
schema does not alone open the outer gate.

[#243](https://github.com/ricomariani/CG-SQL-author/pull/243) fixed an unrelated
scope error in query-plan statistics. Plan node IDs are local to a statement,
but a covering-index lookup searched all statements. A covering search in
query 2 could erase an ordinary search count in query 1.

The graphs and query texts were correct, but the JSON statistics could be
wrong. We added the missing `sql_id` predicate.

### 7. JSON, UTF-8, and reconstructed SQL

[#238](https://github.com/ricomariani/CG-SQL-author/pull/238) fixed two JSON
encoding paths that did not agree. The full-string encoder preserved valid
UTF-8; pretty-quoted SQL still escaped individual bytes. The UTF-8 bytes
`E2 80 A2` for U+2022 could become:

```text
\u00e2\u0080\u00a2
```

That is valid JSON, but it describes three different characters. A separate
plain-`char` signedness assumption made malformed-byte handling fail on
unsigned-char builds.

Users had been reporting JSON problems for years. I hadn't followed through
with enough test diversity. The October repair credits those reports; AI
analysis helped finish the job. We kept the compatibility rules from the
earlier UTF-8 and malformed-sequence repairs.

[#239](https://github.com/ricomariani/CG-SQL-author/pull/239) fixed another
way we could change the meaning of emitted SQL. It preserved
right-nested grouping among `||`, `->`, and `->>`. They share left-associative
precedence, but mixed pairs are not associative. Dropping parentheses from
`'{"ab":7}' ->> ~int~ ('a' || 'b')` changed its SQLite result from 7 to NULL.
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

### 8. Incomplete samples

[#246](https://github.com/ricomariani/CG-SQL-author/pull/246) completed .NET
blob marshalling. Passing placeholder `"xx"` bytes is spectacularly wrong for
an actual binary use-case. The replacement carries real bytes, length, and
independent NULL presence; empty and NULL cannot be inferred from the same
pointer value. Returned storage also needs an explicit ownership/freeing rule.

The new fixture called real managed/native code and compared actual payloads.
An actual use-case would have exposed this immediately.

That work also produced a real follow-up failure:
[#247](https://github.com/ricomariani/CG-SQL-author/pull/247). The fixture
inherited ASan instrumentation, but the .NET host did not supply the ASan
runtime, so it failed to load with `DllNotFoundException`. We changed the
foreign-hosted fixture's flags; the compiler and ordinary native tests stayed
instrumented.

The first May 15 extension changes tell a similar first-use story.
[`82925067`](https://github.com/ricomariani/CG-SQL-author/commit/82925067)
stopped retaining an OBJECT and exposing its address as an integer SQL value;
the generic bridge now returns NULL for that unsupported column type.
[`b7ac09a6`](https://github.com/ricomariani/CG-SQL-author/commit/b7ac09a6)
released the previous rowset when SQLite called `xFilter` again on the same
cursor, as an ordinary nested-loop join can do.

### 9. Repeated invocation exposed scanner ownership

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
compilation tests made these leaks visible.

---

## The test infrastructure had bugs and blind spots too

Test drivers often get the simplest error treatment in a project. That was
visible here:

| Fix | What could be hidden | Repair |
|---|---|---|
| [#231](https://github.com/ricomariani/CG-SQL-author/pull/231) | A global `_PROC_` tracing definition was a function name rather than a C string; the default no-op tracing configuration did not consume it. | Fix the emitter and run the fixture with tracing that consumes the string. |
| [#248](https://github.com/ricomariani/CG-SQL-author/pull/248) | Failed BEGIN/COMMIT operations in the upgrade driver could be ignored. | Report and propagate the failure. |
| [#249](https://github.com/ricomariani/CG-SQL-author/pull/249) | A failed SQLite close could conceal outstanding resources while the driver reported success. | Report the failure. |
| [#250](https://github.com/ricomariani/CG-SQL-author/pull/250) | Failed verifier regeneration could be followed by a successful build of stale generated files. | Chain regeneration and build so failure stops the wrapper. |
| [#251](https://github.com/ricomariani/CG-SQL-author/pull/251) | Parent/child checks accepted incomplete results; recreate checks established status but not the physical effect; the corruption PRNG used signed-overflow arithmetic. | Check complete observable results, query the database in CQL, and use unsigned arithmetic only in the private C PRNG. |
| [#252](https://github.com/ricomariani/CG-SQL-author/pull/252) | The normal harness omitted an existing extension-encoding check. | Wire it into that harness; it already ran in the extension suite and CI. |
| [#253](https://github.com/ricomariani/CG-SQL-author/pull/253) | A case-insensitive schema validator accepted wrong-case field names. | Require canonical key spelling, retain uppercase `CRC`, and explicitly accept either exponent letter. |

The parent/child test had no `ORDER BY` in its child query. We replaced a
position-dependent formula with exact counts and unique expected-set
membership.

Likewise, testing recreate means checking that a probe row disappeared and
the expected tables/index remained. A successful return code alone cannot
distinguish a real recreate from a successful no-op.

The driver fixes stayed small. If `main` is going to report an error and
immediately exit, there's no need to add rollback and cleanup machinery.

The history also includes routine maintenance: release/beta refreshes, the
gcovr compatibility pin, grammar-comment extraction, CI/runtime updates,
executable modes, and the verifier's regenerated warning pragma. Two small
May 15 changes aligned the blob-constructor signed/unsigned signatures,
[`e86fbdc7`](https://github.com/ricomariani/CG-SQL-author/commit/e86fbdc7),
and made extension contracts more explicit,
[`11e277c2`](https://github.com/ricomariani/CG-SQL-author/commit/11e277c2).

---

## What the findings say about usage and testing

### Light use

QIDs and both blob serialization features are lightly used. QIDs also had
extensive tests. Those tests still left some things for first use to find.

The public cursor serializer and the backed-table binary UDFs had different
origins. The cursor serializer expected hostile input and version skew from
the beginning. The backed UDFs grew from a public test stub; Meta used a
separate internal implementation.

Failures in nullable-value binary serialization are especially telling. A
basic nullable-value use-case would expose them quickly. The older nullable
Boolean cursor-format problem in the human-era appendix is a particularly
clear example.

My experience has usually been that CQL's initial implementation is fairly
good, but initial use boils out assumptions and missing cases. AI analysis
reached some surfaces that had not received enough of that feedback. The
placeholder blob binding, negative Lua casts, and quoted virtual-table names
are consistent with that pattern.

Ordinary names, nonnegative fractions, small rows, and non-NULL data can all
work while the neighboring case fails. People using valid blobs are also
unlikely to stumble over the hostile-input cases.

There is a separate fringe of escaping and encoding failures in **heavily
used** features. JSON schema output is the obvious example: unusual Unicode,
escape-looking text, or a particular expression/name context can still expose
a missed boundary. The broader feature can be heavily used without every
representation combination being common.

Schema upgrade took a long time to get enough test diversity too, well after
we had reached 100% coverage.

### Coverage and diversity

The compiler's 100% line coverage remains valuable. It forces reachable syntax
and AST shapes through fail-fast handlers. It does not enumerate every input
to an executed handler, every target-language rule, or every external helper.

| Covered code can still miss | Concrete example |
|---|---|
| An omitted validation | The line rejecting an oversized wire header did not exist before #219. |
| Growth rather than ordinary size | Serialization bit writes were covered without a moving allocation. |
| Another representation of the same identity | Case variants and dotted OUT aliases; QIDs versus decoded names |
| A neighboring value class | Negative fractions, NULL versus `"nil"`, adjacent doubles, full-width integers |
| Another host configuration | Plain-`char` signedness, `NDEBUG`, Windows path sizes, a non-ASan managed host |
| Another path through the same format | Full-string JSON versus pretty-quoted SQL |
| Meaning after successful parsing | Mojibake, altered backslashes, wrong-name CREATE, contaminated statistics |

You cannot cover a check you did not think to write. Nor does covering the
normal higher-level caller establish that a lower-level direct API enforces
the same preconditions.

I saw both sorts of missing validation here. Some checks were overlooked;
other code assumed its caller had already checked. The public backed-blob
comments explicitly assumed well-formed storage. Direct blob calls bypassed
checks normally supplied by the rewritten DML path.

### Checking what happened

Some of the most useful test changes were straightforward:

- execute emitted schema, inspect the real object name, then use the object;
- parse JSON and compare decoded strings and relationships;
- compare Lua results with C/SQLite for the relevant defined cases;
- force several buffer growths before writing later bits;
- round-trip metadata through the actual CQL parser, not a similar JSON parser;
- inspect the physical post-upgrade schema and data from CQL;
- invoke the real managed/native binding and compare real bytes.

Even a round trip needs care. If producer and consumer share a mistaken
convention, they can agree with each other. Comparing the C and Lua cursor
formats caught just such a mistake in the human-era article.

### The fixes themselves need review

We simplified several proposals during review: size blob output by logical
length, use a depth guard for macros, length-prefix Lua keys, and share a
runtime cast helper. The first proposals for these had considerably more
machinery.

We also had to fix the .NET fixture after it broke the ASan run. And the
UTF-8 history has several rounds of incomplete fixes, including my own.

---

## Proposals we did not adopt

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

## What I would carry forward

I'm keeping the covered, fail-fast architecture. It has served CQL well.
The work here gives me more cases to add: unusual names and strings, moving
allocations, negative values, NULLs, repeated calls, and interactions between
features. QIDs in particular need an inventory that includes metadata,
strings containing names, and host-language wrappers as well as SQL.

The binary readers need to validate the complete input before arithmetic or
copying, and size the output for the copies they actually make. Generated
text needs the right encoder at each layer. The test drivers need ordinary
error checks and tests of the result.

On the whole, I think we did well with CQL. Hundreds of developers using it
every day found a lot of the rough spots. But that use didn't reach everything,
especially in this fork. The AI kept looking, including in places I'd already
tested thoroughly. It found enough to make this a very worthwhile exercise.
