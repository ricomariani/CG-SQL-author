---
title: "Appendix 3: The Evolution of CQL"
weight: 3
---
<!---
-- Copyright (c) Rico Mariani
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## A history of the language, not a history of its bugs

**Public-history window:** October 7, 2020 through October 14, 2026

**Analyzed endpoint:** [`b653ccaa`](https://github.com/ricomariani/CG-SQL-author/commit/b653ccaac184922f95bf1cd5b6ffbcf48f333287)

**Repository:** `ricomariani/CG-SQL-author`

The interesting question here is not how many features CQL acquired. It is
what people were trying to express, what made that difficult, and how the
language changed so that the next program was easier to write.

The short version is this:

> CQL started by taking responsibility for the tedious, fragile parts of
> calling SQLite from C. It gradually took responsibility for the tedious,
> fragile parts of writing a large, typed, evolving data program.

Shapes reduced repeated declarations. Flow analysis reduced repeated proofs.
Fragments reduced repeated queries. Structured storage and nested results
reduced repeated packing and joining code. Native macros reduced repeated
program structure. Later changes made those mechanisms fit together and
removed special cases that no longer earned their keep.

That is the organizing idea of this appendix. It is not a claim that all
these features were planned together at the start.

### Scope and evidence

This is a reconstruction from the public Git history, historical guides,
implementation changes, and tests. The initial public commit already contains
a substantial language and compiler. The earlier internal development is not
in this record. **October 2020 is the start of the observable history, not
the invention of CQL.**

Dates identify work in the repository, not formal language releases. Some
features arrived in stages: parsing first, semantics next, code generation
after that, then broader use. Where that distinction matters, it is called
out rather than treating the first grammar production as a finished feature.

Motivation has two different kinds of evidence:

* **Recorded intent** comes from contemporary commit descriptions or guides.
* **Interpretation** connects the change to a broader need when the record
  does not state that connection directly.

The interpretation is useful, but it is not a substitute for an author's
recorded reason. Links identify the patches on which the account rests.
Current user-guide links explain present semantics; they are not evidence
that today's syntax existed in 2020.

Likewise, **adoption here means adoption in the public repository**. A
semantic test proves that a feature is checked. A runtime test proves that
a scenario is exercised. Rewriting the test harness or the verifier to use
the feature is stronger evidence that it became an ordinary programming
tool. None of those, alone, measures production usage.

The epochs overlap. Flow analysis continued while query composition was
being built; storage work continued while the surface syntax changed.
The divisions below describe changes in emphasis, not clean architectural
boundaries.

### The epochs at a glance

| Epoch | Approximate period | The expanding responsibility |
|---|---|---|
| 0. The public starting point | October 2020 | Compile typed SQLite procedures into approachable C; manage schema and results |
| 1. Program with shapes and intent | Late 2020 to early 2021 | Stop repeating columns, argument lists, and primitive meanings |
| 2. Make the compiler follow the proof | 2021 to early 2022 | Track nullability, initialization, and cursor state through control flow |
| 3. Compose queries instead of copying them | Late 2021 to 2022 | Reuse checked query interfaces and expressions |
| 4. Go beyond physical rows | 2022 to 2023, with later completion | Serialize shapes, build nested results, abstract storage, and target Lua |
| 5. Make CQL pleasant to write in | 2023 to early 2024 | Shorter notation, native macros, imports, and substantial dogfooding |
| 6. Give libraries a vocabulary | Primarily late 2024 | Explicit operations, containers, dynamic metadata, and ordinary runtime APIs |
| 7. Complete and consolidate | Late 2024 to the endpoint | Modern SQLite, extensible backing, simpler declarations, and richer interfaces |

---

## Epoch 0: the public starting point was already a system

### October 2020: less C plumbing, not less SQLite

The [initial public commit][initial] is dated October 7, 2020. Its
introduction states the original problem plainly: SQLite has a rich C API
but no stored procedures, and changes to SQL force corresponding changes
to bindings, column indices, null handling, and error handling.

The proposed output was "The C you could have written to do that job using
the normal SQLite interfaces." That is an important aspiration. CQL was
not trying to hide SQLite behind an unrelated object model. It was trying
to let the programmer write SQL and control flow together, then generate
the necessary C machinery reliably.

The original introduction also explicitly identifies the needs of the
Messenger application as the origin of the work. The public source does
not expose that application's earlier language history, so this appendix
does not invent one.

### The baseline language

By the public import, CQL already supported:

* Procedures, declared native procedures and functions, `IN`, `OUT`, and
  `INOUT` arguments, nullable primitives, reference types, and sensitivity.
* Ordinary SQL DDL and DML, joins, CTEs, recursive CTEs, window functions,
  filters and frames, and upsert.
* Local variables, conditionals, loops, cursor iteration, and structured
  error handling with `TRY`, `CATCH`, and `THROW`.
* Statement cursors, value cursors, procedure results, shape reuse, `OUT`,
  and `OUT UNION`.
* Transactions and explicit SQLite savepoints.
* Schema versioning, previous-schema validation, migration procedures,
  schema regions, and deployable regions.
* Attributes, generated test helpers, dummy-data generation, JSON
  metadata, and several code-generation modes.
* The original base/extension/assembly query-fragment system.

These are not later discoveries. The root grammar, guide, and tests already
contain them.

This also explains why the later evolution looks less like constructing
a language from scratch and more like removing seams between things the
system already knew.

### Schema was already a longitudinal concern

The initial schema guide explains that recording schema changes seemed
essential. `@create`, `@delete`, and `@recreate` were already ways of
describing a schema over time, not merely accepting a set of `CREATE`
statements.

The language could distinguish the schema visible to ordinary code from
the schema visible to an old migration. A deleted column could remain in
the physical database while becoming inaccessible to current application
queries. Regions described dependencies and allowed portions of a schema
to be deployed separately.

That was a major part of the original reach: **a compiler that knows SQL
should help maintain the database's history as well as today's queries.**

Later additions to migration and subscription policy should be read as
extensions to this baseline, not as the introduction of schema management.

### Results were already more than a single SELECT

`OUT` and `OUT UNION` made a row shape into a procedure interface.
Procedures could compute rows procedurally instead of being restricted
to returning one SQL statement's result.

This matters later. Nested result sets, partitioning, cursor serialization,
and dynamic cursor helpers did not arrive in a language with no row model.
They reused a row model that was already central.

### Testability was part of the starting design

The initial runtime suite already exercises recursion, cursor fetches,
transactions, savepoints, generated data, and unioned procedural results.
The initial tree also contains `cg_test_test_helpers.sql`.

Dummy values and generated test helpers let the compiler use its schema
knowledge to create test environments. Rather than make every test manually
reproduce table dependencies, column lists, and suitable values, CQL could
generate some of that work.

This is the first recurring pattern in the history: once the compiler
knows something, having the programmer repeat it is an opportunity for
both inconvenience and disagreement.

**Evidence:** the [initial guide and sources][initial], particularly
`CQL_Guide/ch01.md`, `ch05.md`, `ch07.md`, `ch10.md`, and `ch14.md`;
`sources/cql.y`; and the initial runtime and test-helper suites.

---

## Epoch 1: shapes became a programming vocabulary

### Late 2020 to early 2021

The early public work repeatedly generalizes an existing idea. A shape
is not just the columns of one table. It can be a cursor, a procedure's
result, a procedure's arguments, or a named bundle of values.

The payoff is not merely shorter declarations. It is that one declaration
can become the authority for several related operations.

### Arguments should not have to be retyped

In October 2020, `FROM` argument expansion was
[generalized to function calls][from-functions]. In November,
[cursor shapes could be obtained from procedure arguments][argument-shapes],
not just procedure results.

The November commit gives two concrete needs: forwarding shims and tests
that call a procedure with many arguments. A shim should be able to take
the same arguments, add logging, and forward them. A test should be able
to modify one named input without manually reconstructing a long,
position-sensitive call.

`FETCH ... USING`, `INSERT ... USING`, and `UPDATE CURSOR ... USING`
followed in November. These forms put an expression next to its destination
name rather than requiring a parallel list of columns and values.

That is a small syntax change with a practical consequence: the unit of
maintenance becomes "this value belongs to this field," not "the seventh
value must continue to match the seventh column."

Then [named argument bundles][argument-bundles] made it possible to take
two instances of the same shape. The contemporary example is two people:
`p1 LIKE Person` and `p2 LIKE Person`. Each expands into ordinary
arguments, but the source can retain the conceptual grouping.

The December work introduces a synthetic `ARGUMENTS` shape and
[consolidates the terminology around shapes][from-shape]. An old grammar
form could disappear while its capability survived in the more general
shape mechanism. `FROM ARGUMENTS` remains meaningful in current CQL;
the consolidation was not the removal of argument forwarding.

**Usage change:** procedures with large interfaces, forwarding adapters,
and data-driven tests need less duplicated structure. The same information
can drive a call, a value cursor, and a declaration.

**Adoption evidence:** these changes add parser, semantic, and generated-code
cases to the existing test files. The recorded rationale specifically names
test code as a recurring use case. Later nested-result and blob examples
depend on this vocabulary rather than inventing a second struct language.

The same idea continued in March 2021 with
[OUT DECLARE][out-declare]: callers could ask CQL to declare a procedure's
output arguments from its signature rather than repeat their types.

### A cursor could travel as an object

Boxed cursors arrived on October 28, 2020, in
[parsing][boxed-parse], semantic, and [code-generation][boxed-codegen]
steps.

A box is not a copy of the current row. It packages the cursor's underlying
statement so another cursor can refer to it. The initial runtime tests
alternate fetches through two cursors and verify that the statement advances
while each cursor retains its own fetched field values.

That distinction is the feature's purpose. It makes a cursor something
that can be passed around without exposing the raw SQLite statement
handling to every caller.

This was an early extension of the original abstraction boundary:
procedural control over a query should remain possible without falling
back to manual C resource management.

### Transaction scope acquired procedure-sized notation

Raw savepoints were already present. November 2020 added
`PROC SAVEPOINT`, `COMMIT RETURN`, and `ROLLBACK RETURN` through separate
grammar, semantic, and [code-generation][proc-savepoint] changes.

The code-generation description gives the lowering: a procedure-named
savepoint and structured error handling; the returning forms release or
roll back that scope before returning.

**Interpretation:** the need is not a new transaction engine. It is a
common procedural pattern that deserves one consistent spelling. The
programmer specifies the intended scope, and the compiler owns its
bookkeeping.

This is the same style of economy as argument bundles: recognize a
recurring shape of code and express its intent directly.

### Names started carrying more than spelling

Several changes supplied names for things that had previously needed
repetition or convention:

| Addition | Arrival | What it made explicit |
|---|---|---|
| [`const(...)` folding][constant-folding] | November 2020 | An expression should be resolved at compile time |
| Enums | December 2020 | A named set of numeric values |
| Named types | January 2021 | A reusable type declaration |
| Primitive type kinds | January 2021 | The domain meaning of a primitive value |
| `LET` | March 2021 | A declaration whose type follows its initializer |

The [enum change][enums] added named values and was followed by C and
JSON emission. [Named types][named-types] made declarations reusable.

The [kind change][kinds] is especially revealing. Objects already had
kinds such as lists and dictionaries. The change generalized that idea
to primitive values: an integer task identifier should not accidentally
be assigned a job identifier merely because both use the same machine
representation.

The initial implementation explicitly says that table-column kinds can
be declared before all DML enforcement is implemented. Follow-up work
propagated kinds through semantic structures, enums, builtins, casts,
table operations, and JSON output.

This is a good example of staged completeness. Accepting a discriminator
in the grammar is not the same as carrying it through every operation
that can erase its meaning.

Kinds also deliberately do not make every unadorned primitive incompatible:
the original description says that values without a kind continue to mix
freely under the ordinary conversion rules. This is domain discrimination,
not a wholesale replacement of the primitive type system.

[LET][let] arrived in March 2021. It combines declaration and assignment
and derives a useful type from the expression. Unlike the later `CONST`
binding, it does not mean that the binding is immutable.

### Complete more of SQLite, without confusing that with new CQL concepts

The same period filled SQL gaps: virtual-table declarations and their schema
and JSON treatment in December 2020, table `CHECK` constraints, and
expression/partial indexes and richer conflict/indexed-column forms in
April 2021.

These changes widened the SQLite vocabulary available to a typed program.
They did not redefine the language's organizing model.

Their importance is practical completeness. A language that handles most
of an application's SQL but requires a separate escape path for one useful
index or table declaration has not removed as much bookkeeping as it
appears to have removed.

**Evidence:** [virtual tables][virtual-tables],
[expression and partial indexes][indexes], and the accompanying schema,
semantic, and metadata tests.

---

## Epoch 2: the compiler learned to follow the proof

### 2021 to early 2022

CQL was strongly typed from the start. This epoch changed what a type check
could know about the program at a particular point.

A declared nullable value is not necessarily nullable after a check.
A declared nonnull reference is not necessarily initialized.
A cursor with a nonnull column does not necessarily have a row.

The recurring need was to distinguish the declaration from the current
state.

### An empty scalar query needed an explicit policy

The February 2021 [SELECT ... IF NOTHING work][if-nothing] begins with a
recorded complaint: scalar nested selects were frequently misused, and
getting no row can be an error.

The family grew to provide fallbacks and throwing behavior, with a strict
enforcement option for requiring the policy explicitly. Later additions
distinguished no row from a row containing `NULL` and rounded out the
throwing forms.

These alternatives matter because they represent different application
contracts. "This lookup may be absent, so use a default" and "this lookup
must exist" are not interchangeable.

**Usage change:** absence becomes visible at the lookup rather than an
implicit assumption elsewhere in the procedure.

This is language-level handling of an expected data outcome. It should
not be confused with accepting invalid compiler/runtime API arguments
outside their contracts.

Error handling also gained a more explicit vocabulary. `@RC` was added in
February 2021 and [defined in terms of the error in scope][rc-scope] in
March. In [February 2024][chosen-error], `cql_throw` allowed code to choose
the exception code. These are extensions to the existing error-handling
model, useful when a procedure must expose a particular failure to its
caller.

### Occurrence typing: use the fact the program just established

[Occurrence typing for nullability][flow-initial] arrived in June 2021.
Its contemporary description explicitly connects it to similar ideas in
other programming languages.

The simplest example, in contemporary CQL notation, is:

```sql
proc present_or_empty(value text, out result text!)
begin
  if value is not null then
    result := value;
  else
    result := "";
  end;
end;
```

The assignment to the nonnull `OUT` parameter is valid because the branch
has established that `value` is nonnull, not because its declaration
promised that.

The first version was intentionally limited. Certain `AND`-separated
positive checks improved local bindings and cursor fields. Writes,
fetches, and `OUT` uses invalidated improvements. Globals and more
complicated control-flow cases required later work.

The history then broadens the proof:

* Assignment can establish useful nullability facts.
* Guards that exit can establish facts in the code that remains.
* False branches and `CASE` alternatives carry information too.
* Globals receive appropriate handling.
* Facts must be combined correctly across conditionals, loops, and
  switches.

The initial rollout required a `NOT NULL AFTER CHECK` enforcement setting.
September 2021 contains a particularly strong adoption trail:
[the existing code-generation suite was changed][flow-cg-adoption] to
use the improvements; [the analysis became unconditional][flow-always];
then the old opt-in mechanism was removed.

This is more than a new fixture. Existing tests had to restore actual
nullable states where they still wanted to verify nullable generated code.
The compiler now knew that some formerly nullable test values were not
nullable at that point.

**Usage change:** an ordinary check or assignment becomes the proof. The
programmer no longer has to restate the conclusion with an artificial cast
or a separate assertion.

### Stronger analysis brought stronger obligations

December 2021 generalized control-flow analysis and then
[required initialization of nonnull references][initialization].
Such variables must be initialized before use, and nonnull reference
`OUT` parameters must be initialized before a procedure returns.

The commit explains that the new rule could build on the existing flow
machinery. It also records a practical exception: procedures that wrap
their meaningful body in a `TRY` block sometimes need
`cql:try_is_proc_body` so the analysis understands that structure.

This is a different kind of completeness. A compiler should not merely
trust a nonnull declaration when an uninitialized reference can still be
null at runtime.

In March 2022, [CURSOR HAS ROW enforcement][cursor-row] applied the same
reasoning to cursor fields. A nonnull reference column is not safe to
access just because its schema says nonnull; the fetch may have produced
no row. Checking the cursor establishes the needed state. Refetching it
invalidates that state.

This was introduced as an enforcement option, not as evidence that every
program immediately used it. The semantic tests cover both successful
proofs and the cases where a proof has been lost.

### Exhaustiveness and policy became expressible

[SWITCH][switch] and [ALL VALUES][switch-all] arrived in March 2021.
The recorded intent includes compact C switch generation and better
checking. `ALL VALUES` lets the compiler verify coverage of an enum's
meaningful members rather than relying on a programmer to remember every
case.

Meanwhile, enforcement settings gained push/pop/reset operations in
February. This allowed policy to be scoped around code instead of depending
on a long-lived ambient setting.

The period also tightened ordinary semantics. Undeclared function calls
were no longer the norm in July 2021. Redundant-cast checks became stricter.
December [disallowed several SQLite select-alias lookup quirks][alias-policy]
that could make query meaning ambiguous and complicate flow analysis.

These are intentional restrictions, not missing implementations.
**Completeness sometimes meant making a questionable interpretation
unavailable.**

### The proof kept expanding after the epoch

In November 2023, [short-circuit AND/OR analysis][short-circuit] allowed
the right operand to use facts established by the left:

```sql
proc has_name(value text, out result bool!)
begin
  result := value is not null and length(value) > 0;
end;
```

The relevant fact is available where the second expression is evaluated.
That is the expression-level continuation of the 2021 work, not a
separate nullability model.

The overall aspiration is consistent: let ordinary program structure
carry the proof, and make the compiler responsible for following it.

---

## Epoch 3: query composition became a checked interface

### Late 2021 to 2022

SQL reuse is awkward when the unit of reuse is just text. A macro can
duplicate a query, but it does not necessarily provide a checked interface
between the author of the reusable piece and the caller.

CQL already had one answer: the original fragment system. This epoch
developed a more general answer and eventually retired the old one.

### The original aspiration: independent pieces of a large query

The initial guide describes a core query for a UI and extensions that add
rows or columns for additional features. The aim was to avoid a monster
"fetch everything" query and keep each extension's dependencies limited.

That is a real aspiration, not merely a syntax experiment. Large schemas
and feature-specific result columns can make one query difficult to own,
review, and evolve.

But the original base/extension/assembly structure accumulated machinery
for those specific roles.

### Shared fragments: a procedure-like interface for reusable SQL

[Shared-fragment semantics][shared-start] and
[code generation][shared-codegen] arrived in November 2021, followed by
documentation and metadata dependencies.

A shared fragment is checked as a reusable query interface. A caller can
use it in a CTE, pass ordinary arguments, and build a larger query from
its result. Table/CTE parameters allow a fragment to operate over a supplied
shape rather than hard-code one physical table.

A small contemporary example shows the intended separation:

```sql
[[shared_fragment]]
proc positive_ids()
begin
  select id from items where id > 0;
end;

-- items is declared elsewhere in the program.
proc count_positive_ids()
begin
  with ids(*) as (call positive_ids())
  select count(*) as count from ids;
end;
```

The example is schematic: it shows composition, not a complete schema.
The fragment can be analyzed independently, and the larger statement still
becomes SQL for SQLite.

The user-guide account contrasts this with copying query text through
macros: mistakes in reusable text can be deferred until use, while a
fragment has a checked definition and a known result shape.

That rationale should not be read as a comparison to native CQL macros in
2021. Those did not arrive until 2023. At the time, text preprocessing was
the existing alternative.

### Conditional fragments could change the query's work

[Conditional shared fragments][shared-if] arrived in December 2021.
The contemporary description uses a comma splitter: empty input can select
an empty result without handing SQLite the more elaborate recursive CTE.

The same mechanism can choose primary or backup data, omit a join when it
is unnecessary, or choose among query alternatives that return the same
shape.

This is not simply adding `IF` to SQL text. The compiler checks shape
compatibility and handles SQL pieces and binding requirements for the
selected alternative.

**Usage change:** one maintained procedure can describe several efficient
query forms without duplicating the entire query or manually assembling
SQL and bind lists.

The original form required an `ELSE`. In
[October 2023][shared-no-else], omitting it became shorthand for an empty
result of the appropriate shape. That later convenience is not projected
back into the 2021 examples.

### Reusable expressions and shape-directed columns

[Expression fragments][expression-fragments] arrived in February 2022.
They extended the composition idea to an expression rather than requiring
every reusable piece to be a full result-producing query.

The same period added shape-directed column selection and generalized
`FROM` insertion lists. `COLUMNS`, later renamed `@columns`, let a
program derive an expression list from shapes instead of spelling every
column again.

These features complement fragments. A checked query interface does not
help as much if its caller still has to duplicate every result-field name.

The naming change to `@columns` in September 2023 also has a recorded
practical reason: `columns` is a useful ordinary identifier and need not
be consumed as a language keyword.

### The older fragment architecture did not survive

The [March 2022 change][classic-takeback] explicitly calls itself a
"feature take-back." Its explanation is concrete: separately generated
extension interfaces complicated code generation, were not useful enough,
and obstructed independent assemblies sharing a base.

That first simplification was followed by a deprecation notice in November
2022 and [removal of classic fragments][classic-remove] in May 2023.
Shared fragments remained.

The important lesson is about language design, not defects:

> A feature can satisfy the original use case and still be the wrong
> long-term abstraction once a more general composition mechanism exists.

The public evidence supports the replacement and the recorded reasons.
It does not support treating every proposal in the take-back discussion
as syntax that eventually shipped.

### Separate compilation also needed declarations

[Declaration and emission groups][groups] arrived in March 2022 to help
share declarations, including globals, across modules.

This extends the same concern beyond SQL composition. Reuse requires
some way to publish an interface without defining everything again in
every translation unit.

In February 2023, [native alias declarations][native-alias] let a CQL
function or procedure use a different name from its native implementation.
This is another interface separation: a CQL-friendly name does not need
to force renaming the underlying C library entry point. The initial
implementation described this as C support; proposed uses in other
backends should not be mistaken for demonstrated support.

**Adoption evidence for the epoch:** fragment changes add semantic,
generated-C, metadata, and runtime cases; later backed-table reads are
implemented using generated fragments. That last point is significant:
query composition became infrastructure for another major language
feature, not just a user-facing convenience.

---

## Epoch 4: data programming went beyond physical rows

### 2022 to 2023, with later completion

This epoch contains several related but distinct developments:
whole-cursor serialization, generic cursor operations, nested result sets,
logical tables with alternative storage, and a second executable backend.

They all reuse the type and shape system. They do not all use the same
representation.

### Structured blobs: package the whole shape

The [March 2022 structured-blob proposal][structured-blobs] gives an
unusually clear account of the need: economically package multiple fields
using the type system CQL already has.

The chosen initial operations were whole-cursor serialization and
whole-cursor deserialization. The commit explicitly rejects a large family
of field-at-a-time operations: that would create both overhead and an
unpleasant cross-product of types and language forms.

A shape-only declaration describes the fields without creating a physical
table. A blob kind identifies the intended shape. The format includes
type information, null and boolean bits, compact integer encodings, and
inline string/blob data.

Evolution was part of the design from the beginning. Adding trailing
nullable columns can let an old reader tolerate a newer payload and a new
reader supply missing nullable fields from an older payload.

**Usage change:** a program can persist or transmit a structured value
without hand-writing a separate codec and repeating its schema in C.

The initial syntax had dedicated `SET ... FROM CURSOR` and
`FETCH ... FROM BLOB` statements. Current syntax uses ordinary runtime
calls and pipelines; that replacement belongs to Epoch 6.

The tests arrived immediately, including round trips and mutation cases.
They establish that arbitrary incoming bytes are a supported validation
boundary. They do not make malformed payloads equivalent to programmer
misuse of an internal API.

### Generic cursors: work on a shape without naming every field

[Dynamic cursor parameters][dynamic-params] arrived in April 2022.
Generic hashing, equality, and [partition/extract helpers][partition]
followed.

The need is easy to see in the later result-set construction: a reusable
helper must compare key fields whose particular names and types belong
to the caller. It should not require a separately handwritten helper for
each table.

This is runtime genericity over compiler-described shapes. It does not
mean that ordinary typed cursor operations lose their static checking.

The initial generic interface was particularly useful to C helpers.
In 2024, dynamic cursor introspection became directly available inside
CQL, which widened who could write those helpers.

### Interfaces gave shapes names independent of storage

[Interfaces][interfaces] arrived in May 2022, with semantic support,
`LIKE` reuse, implementation checks, and JSON output.

They allow a result shape to have a name without manufacturing a physical
table or an artificial procedure solely to supply that name. Multiple
interfaces and more flexible matching followed later that year.

**Interpretation:** this is the natural next step after shapes spread
through arguments, results, and storage. The useful abstraction is the
set of fields, not the incidental declaration from which it was first
obtained.

Interfaces subsequently became important for nested result contracts.
March 2025 adds recursive matching of kind-qualified interface shapes,
making checks more complete for results that contain other results.

### Nested results: represent the data the consumer actually wants

Parent/child data is awkward to return as one flat join. Parent fields
repeat, consumers have to reconstruct collections, and the query's
physical row shape becomes tangled with the application's desired shape.

May 2022 [shape narrowing][shape-narrowing] explicitly names parent/child
keys as a motivation. Generic partitioning supplied the underlying
mechanism. Then [OUT UNION CALL ... JOIN CALL ... USING][parent-child]
made the pattern a language operation:

```sql
declare proc parent(x int!) (id int!, a int, b int);
declare proc child(y int!) (id int!, u text, v text);

proc parent_child(x_ int!, y_ int!)
begin
  out union call parent(x_) join call child(y_) using (id);
end;
```

This contemporary example comes from the result-set guide. The `JOIN`
here describes partitioning procedural results into nested parent/child
data; it is not simply a textual SQLite join.

Result-set kinds and named child results followed in June and September.
The resulting interface can describe nested data instead of leaving the
consumer to infer a collection relationship from repeated flat columns.

**Usage change:** a procedure can expose a structured result tailored to
its consumer, while the compiler generates the repetitive key handling,
partitioning, and result assembly.

The tests verify construction and access, not only the declaration.
This is also why interface matching and metadata matter: a nested result
must remain intelligible to callers and generated bindings.

### Materialized results became values inside CQL

The nested-result work did not force every parent/child computation through
the partitioning form. A caller can also compute a child result for each
parent and attach it as a value.

[May 2022][result-cursors] allowed result-set variables to supply a cursor.
Then [June 2022][result-values] generalized the existing
procedure-as-function notation to capture a procedure's materialized result:

```sql
-- producer is declared or defined elsewhere.
let rows := producer();
cursor C for rows;
loop fetch C
begin
  -- Consume the captured result.
end;
```

The result has a kind such as `object<producer set>`, so its source shape
is not lost merely because it is held in an object value.

There is an important usage choice here. A cursor over a select-producing
procedure can stream its rows; capturing the result makes a materialized
result available for reuse, passing, or nesting. Those are different
requirements, and the language supports both.

The introduction patch supplies unusually concrete adoption evidence:
an existing runtime test that used a fake procedure declaration and C
`#define` aliases to call the generated fetcher is replaced by ordinary
CQL result capture and iteration.

### Shape operations continued to fill practical holes

[Shape subtraction][shape-subtraction] arrived in October 2022. The
recorded canonical example is a table shape minus its generated primary
key: an insert procedure wants all the useful input fields except the
field the database will generate.

`LIKE foo(-id)` makes that relationship explicit. Without it, a large
input signature would duplicate nearly all of the table.

This is a small extension with large leverage. It fits the existing shape
system instead of creating a special "insert argument" declaration.

### Backed tables: logical SQL, different physical storage

Backed-table work began in September 2022 and advanced through detection,
helper declarations, reads, inserts, deletes, updates, test helpers,
upsert, defaults, and schema-evolution treatment.

The [initial read rewrite][backed-read] explains the model: a logical
table is represented by fields in a generic physical key/value store.
The compiler rewrites a reference to the logical table into a CTE that
extracts those fields.

The programmer still queries a typed logical schema. The physical
representation need not be one SQLite table with one physical column per
logical column.

**Interpretation:** this extends CQL's original ambition from "keep C
bindings synchronized with SQL" to "keep SQL operations synchronized with
a storage representation." It opens space for different storage strategies
without making application procedures perform all their own packing and
unpacking.

The [September runtime-helper change][backed-initial-runtime] is explicit
that its helper implementations are deliberately simple initial test
implementations. Standard key helpers, value helpers, Lua support, and
versioning tests were developed further in 2023.

That distinction matters. The compiler rewrite and the storage library
were separate pieces with separate maturation paths.

It also matters that **backed key/value blobs are not whole-cursor
serialization**. Keys need appropriate identity and comparison behavior;
values need their own update and evolution behavior. A wire-style record
codec is not automatically the right format for either one.

**Adoption evidence:** backed tables acquire runtime DML tests and generated
test-helper support, not just read fixtures. Later per-table backing and
JSON storage tests combine logical tables with different physical helpers.

### Schema subscription policy was simplified

In spring 2022, `@unsub` and `@resub` described withdrawal and return of
schema objects, with previous-schema checks and generated operations.

The [November removal of @resub][resub-remove] records the simplification:
a table is treated as deleted or not; resubscribing is accomplished by
removing the unsubscribe declaration. The obsolete versioned unsubscribe
form was removed shortly afterward.

This is another non-additive development. The schema model acquired a
capability, then a simpler expression of that capability replaced some
of the original surface.

Additional schema work in late 2021 had already added migration procedures
for recreated tables/groups and an exclusive-schema mode. These extended
the original versioned-schema model to more deployment and recreation
policies.

### SQL itself continued to widen

June 2022 added `NULLS FIRST`/`NULLS LAST` ordering, and
[November 2022][update-from] added SQLite's `UPDATE ... FROM` form.
The latter lets a modification use joined source data instead of making
the programmer reconstruct the operation through separate lookups.

It also illustrates version-aware policy: CQL can support a newer SQLite
form while an enforcement setting rejects it for code targeting an older
SQLite runtime. Language acceptance and runtime availability are separate
questions.

### Lua tested the language's independence from C

The [initial Lua backend][lua-initial] arrived in July 2022 with unusually
explicit limits: highly experimental, provisional interfaces, runtime
assumptions, and no guarantee that the experiment would survive.

The interesting aspiration is nevertheless clear. If CQL's semantics are
really described by its type system and operations, rather than by the
accidental properties of generated C, another backend should be possible.

It was not enough to print superficially similar Lua. Integer division,
null behavior, object lifetime expectations, result sets, and storage
operations all needed appropriate treatment.

The repository progressively derives Lua upgrade tests from common
sources, enables backed-table runtime tests, and checks runtime output.
In November 2024, [Lua cursor serialization][lua-serialization] and
[exact C/Lua byte comparisons][serialization-equivalence] make the
cross-backend ambition especially concrete.

This is not a claim that every backend facility was at parity in July
2022, or that common tests establish production adoption. It is evidence
that Lua advanced from a tentative code generator toward exercising the
same language and data formats.

---

## Epoch 5: CQL became more comfortable to write in

### 2023 to early 2024

This period has two threads. One reduces ceremony. The other replaces
unstructured preprocessing with native, structured metaprogramming.

Together they make CQL more plausible for programs that do substantial
work outside a single SQL statement.

### Shorter notation without C-style expression side effects

March 2023 introduced [PROC shorthand and bracket attributes][short-proc]:
`PROC` could replace `CREATE PROC`, and `[[private]]` could replace the
long attribute notation.

September added top-level expression statements, automatic conversion
of appropriate procedure calls, optional `SET` with `:=`, and compound
assignment forms. Array and property notation followed.

The [compound-assignment description][compound-assignment] is careful
about the boundary: `x += y` is statement shorthand, not an arbitrary
expression with C-style assignment side effects.

That is worth preserving in the historical interpretation. More familiar
notation did not mean abandoning the language's preference for clear
statement structure.

`VAR` and shorter cursor/interface/type declarations had started in late
2022. September 2023 added `!` as a nonnull abbreviation. December added
`CONST` bindings and shorter `TRY/CATCH` and `END` forms.

Three concepts with similar names should remain distinct:

| Construct | Role |
|---|---|
| `const(...)` | Compile-time expression folding |
| [A const group (November 2021)][constant-groups] | A named collection of constant values |
| A `CONST` binding | A binding that cannot subsequently be reassigned |

Their introduction dates and needs differ. Treating them as one feature
would hide useful development in the language.

### Pipelines had a longer history than the ergonomic wave

The [reverse-application operator][pipeline-initial] arrived in September
2022. Its runtime tests already use single-colon chaining:

```sql
-- Schematic equivalence, with f and g declared elsewhere:
value:f(arg):g()

-- Corresponding nesting:
g(f(value, arg))
```

The value on the left becomes the leading argument to the operation on
the right. This makes a sequence of transformations read in the order
in which the values flow.

In 2023, `::` and `:::` variants explored name-convention-driven resolution
and overloading. Properties and arrays likewise used conventions before
the explicit `@op` system arrived.

Those intermediate operators are historical syntax, not current advice.
The current guide explicitly says the old `::` and `:::` operators are
no longer supported.

### Quoted names and strings mattered to real schemas

[Backtick-quoted identifiers][quoted-identifiers] arrived in October
2023, followed by propagation through schema handling, backing, metadata,
and test helpers.

A generated or external schema cannot always promise convenient identifier
names. Supporting quoting only in an ordinary select would not be enough;
the name has to survive every surface that publishes or rewrites it.

String composition had gained adjacent literal pieces in October 2022.
In November 2023, multiline single-quoted literals were accepted as well,
with the recorded observation that SQLite already supported them and they
were useful.

These are usability and interoperability improvements. They do not change
the central type model, but they remove reasons for otherwise straightforward
programs to require awkward workarounds.

### Native macros: the important part was structure

The [native-macro change][native-macros] landed in November 2023. It added
six categories:

| Macro category | The unit it supplies |
|---|---|
| `expr` | An expression |
| `stmt_list` | A sequence of statements |
| `query_parts` | Sources in a `FROM` clause |
| `cte_tables` | CTE declarations |
| `select_core` | A select core |
| `select_expr` | Select-list expressions |

The [preprocessing guide][preprocessing-guide] states why C preprocessing
was deprecated: mismatched lexical rules, an unnatural build dependency,
poor formatting prospects, token fragments, precedence hazards, and
unhelpful debugging information.

The replacement is not simply an in-process text preprocessor. The macro
declares what kind of syntax it consumes and produces. Expansion operates
on structured language forms, with `@TEXT`, `@ID`, and source-position
facilities for the cases that really require generated text or identifiers.

**Usage change:** repeated program structure can be abstracted without
allowing arbitrary token pasting to redefine the shape of a statement.

This does not give macros every guarantee of shared fragments. A macro
definition is not a separately type-checked query interface in the same
sense. Typed macro categories organize syntax; expanded code still needs
semantic analysis in its context.

The two features address different levels of reuse and can coexist.

### The runtime suite became the demonstration

The macro introduction rewrites much of `run_test.sql` and removes almost
all of its reliance on C preprocessing. The contemporary account ends
with the C preprocessor banished from the runtime tests.

That is unusually strong adoption evidence. The feature is not confined
to a test named "native macros." The suite's ordinary `TEST!` and `EXPECT!`
machinery becomes an everyday client of macro expansion.

That machinery in turn exercises generated identifiers, embedded statement
lists, procedure construction, source positions, and expression
substitution in ordinary tests of unrelated language features.

There is a useful feedback loop here: once a feature supports the test
harness, many later tests exercise it indirectly as well as directly.
That still does not replace targeted tests of its boundaries.

### Imports were deliberately less permissive than text includes

Native `@include` arrived in November 2023, followed by conditional
compilation. December changes progressively limited includes to complete
statement lists, then to the start of files, and made repeated inclusion
of the same file ineffective.

The [recorded direction][include-import] was explicit: include should
behave more like import, not like arbitrary C-preprocessor text insertion.

Conditional compilation also evolved. By late 2024, `@ifdef`/`@ifndef`
are statement forms. Inactive branches must parse, though they are not
semantically checked. Conditional expressions and query pieces are
obtained by choosing well-formed macro definitions, not by cutting
statements into token fragments.

That is a restriction in service of composition. File dependencies and
syntactic structure become less surprising.

### Dogfooding moved beyond the runtime tests

In [November 2023][verifier-cql], the verifier became substantially CQL,
with native helpers and a main entry point remaining where appropriate.

The current `sources/cql-verify/cql-verify.sql` is not a contrived database
example. It performs file/string processing, maintains test records,
and evaluates test output. It uses typed native functions, procedures,
queries, and, later, explicit operation mappings.

That is an expansion in reach. CQL is being used to build part of the
toolchain that evaluates CQL.

January 2024 then [changed canonical nonnull echo][nonnull-echo] to `!`
and [updated existing runtime code][modern-run-tests] to newer notation.
The compiler's own rendered CQL and its ordinary tests started presenting
the modern surface as the normal language.

The reason is not necessarily a new semantic capability. It is that the
new surface had become worth using consistently.

---

## Epoch 6: libraries gained an explicit vocabulary

### Primarily late 2024

The ergonomic work made expression-oriented library calls pleasant.
The next question was how a library could specify their meaning without
relying on a growing collection of naming conventions.

At the same time, CQL acquired more general-purpose runtime data
facilities and made previously native-only helpers accessible in CQL.

### From guessed names to declared operations

The [October 2024 @op change][op-declarations] replaces convention and
existence tests for pipelines, properties, and arrays with explicit
declarations.

A library can say which function implements an operation for a type or
a type kind. For example, this complete contemporary fragment is adapted
from the expression guide:

```sql
@op real : call measure as measure_real;
@op real<joules> : call measure as measure_joules;

func measure_real(value real) real;
func measure_joules(value real<joules>) real;

proc example(value real<joules>, out result real)
begin
  result := value:measure;
end;
```

The source operation can be stable while the implementation is specific.
The compiler does not have to guess the programmer's intended vocabulary
from whatever specially named functions happen to exist.

Follow-up work covers kind-specific mappings, cursors, nulls, and argument
patterns. Polymorphic pipeline/functor forms allow richer dispatch over
the types of several arguments.

**Usage change:** reusable libraries can publish operations, not just
functions plus unwritten naming rules. The same mechanism can support
container indexing, property access, formatting, and domain-specific calls.

The guide gives a candid reason for withdrawing the old `::`/`:::`
approach: its naming combinations were impossible to remember. This is
not evidence that overload resolution itself was unwanted. It is evidence
that an explicit interface was a better way to supply it.

**Adoption evidence:** the change rewrites the verifier, line tester,
runtime tests, and playground examples, not only overload fixtures.

### JSON made SQLite's dynamic data useful to a typed language

September 2024 adds broad JSON/JSONB builtin coverage: constructors,
extraction, modification, removal, objects, patches, aggregates, and
the `->`/`->>` operators.

The tension is straightforward. SQLite can return dynamically typed
JSON values, while CQL needs a static expression type.

The [extraction work][json-extract] therefore does not pretend that
one static type captures every possible JSON extraction result. Casts
and type-directed forms remain important where the program needs a
particular typed value.

JSONB is also a SQLite-version-dependent capability, not a format that
every old SQLite library will understand.

Type suffixes evolved during this work: a `:type:` spelling was replaced
by `~type~` in October to fit better with parenthesis-free pipeline calls.
That is an interaction between features, not merely aesthetic punctuation.

JSON support later becomes one possible physical backing representation.
The same SQL operations can then work with logical tables whose storage
is JSON-based rather than the standard backed-blob helpers.

### More SQLite functions became ordinary expression calls

The [October direct-call expansion][sqlite-direct-calls] has a precise
recorded reason. Many SQLite functions have no semantically identical
native entry point. Instead of requiring the programmer to wrap every
use in a scalar `SELECT`, the compiler can do that lowering.

The change includes date/time functions, string operations, random data,
SQLite version information, and other useful functions. JSON functions
were already following this route.

**Usage change:** a CQL expression can use more of SQLite's vocabulary
without manual SQL wrappers, while SQLite remains the implementation
of the operation where that is necessary.

This is not a claim that the functions become independent of a database
connection or are reimplemented identically in native C.

The runtime tests are changed from checking that certain direct calls
are rejected to checking their useful behavior.

### Boxes and containers supplied ordinary data structures

October and November add primitive boxing/unboxing, type inspection,
object dictionaries, typed numeric dictionaries, and lists/collections
for primitive and reference data.

These work with the existing kind system. A list or dictionary is not
merely an untyped `object` whose intended element type exists only in a
comment. Declared functions and operation mappings expose a useful typed
interface.

**Interpretation:** once CQL can build procedural results, manipulate
structured blobs, and implement tools like the verifier, programs need
intermediate data structures. Forcing each one into a physical SQLite
table or a custom C helper would leave a significant gap.

The runtime implementations remain backend-specific where appropriate.
For example, the typed dictionary wrappers can share machinery in C,
while Lua can use aliases over its existing representation.

That is reuse underneath a typed surface, not an attempt to make the
backend representations identical.

### Dynamic cursor introspection moved into CQL

The [October 2024 dynamic-access feature][dynamic-access] records its
motivation directly: these operations were previously possible through
external C/Lua helpers, but should also be expressible in CQL.

Code can inspect column counts, names, types, null state, and values
through a generic cursor interface. Later cursor-diff and formatting
helpers build on the same metadata.

This makes generic debugging, comparison, and conversion code possible
without generating a separate implementation for every shape.

Dynamic cursor arguments for declared native procedures were broadened
in November. That is not a claim that all CQL procedure definitions
thereby became unrestricted dynamically typed procedures.

### Structured serialization stopped needing special statements

November 2024 [moves cursor/blob operations to normal functions][blob-functions]
and then [removes the dedicated statements][blob-statements-remove].
The capability survives; its special syntax does not.

A complete contemporary example is:

```sql
[[blob_storage]]
create table message_shape(
  sender text,
  body text
);

proc encode_message(like message_shape, out result blob<message_shape>)
begin
  cursor C like message_shape;
  fetch C from arguments;
  result := C:to_blob;
end;

proc decode_message(data blob<message_shape>)
begin
  cursor C like message_shape;
  C:from_blob(data);
  out C;
end;
```

The format and shape guarantees remain. The operations now participate
in the same ordinary call and pipeline mechanisms as library code.
Special semantic checks still protect shape compatibility where needed.

This is a major design direction:

> Adding a capability does not require keeping a special grammar construct
> for it forever. Once the ordinary mechanisms are strong enough, the
> capability can move into them.

It also allows C and Lua tests to use the same programming forms.

### Macro temporaries addressed a real composition need

The runtime assertions show why [@TMP][macro-tmp] mattered in November
2024. An equality macro must evaluate each argument once, preserve the
values for a useful failure report, and avoid colliding with local names
or another expansion.

`@tmp(a)` supplies an expansion-specific temporary name. It is a targeted
hygiene facility, not a claim that every aspect of the macro system is
automatically hygienic.

Primitive `:fmt` mappings make the same assertion macro useful across
types. The contemporary runtime harness combines `LET`, `@TMP`, pipeline
formatting, source positions, and structured statement macros in the
ordinary `EXPECT_EQ!` and `EXPECT_NE!` definitions.

This is particularly good evidence of features becoming mainstream in
the tests: they work together to implement testing itself.

---

## Epoch 7: complete the useful combinations, simplify the rest

### Late 2024 through the endpoint

The later record is less about finding a new center for the language
and more about completing combinations, broadening interoperability, and
consolidating interfaces.

It would be misleading to turn every 2026 hardening change into a new
language epoch. The newer defect work belongs primarily in
[Appendix 2](./02_bugs_of_cql.md), not here.

### Backing became per-table and format-extensible

The [December 2024 backing change][backing-attributes] replaces global
mapping statements with attribute-driven choices and adds JSON backing.

This changes what can coexist in one program. A global storage convention
is awkward when different physical backing tables need different helpers.
Per-table metadata makes the relationship local to the declaration.

The tests combine compound keys and joins involving different backing
tables and helper families. That is more meaningful integration evidence
than a single isolated logical-table read.

The aspiration is a stable logical SQL vocabulary over more than one
physical representation. It is not a guarantee that every representation
has identical performance, schema restrictions, or SQLite-version needs.

### Modern SQLite needed a real runtime lane

The [December 2024 modern-runtime change][modern-sqlite] adds a runtime
lane using the checked-in SQLite amalgamation. This makes newer
capabilities testable without assuming that the host's system SQLite has
all of them.

The need was concrete: JSON backing and newer SQL forms require a modern
library. Compiler acceptance alone cannot establish that emitted SQL
runs on the relevant SQLite version.

Later `MODERN_TEST!` macros make version-dependent cases identifiable in
the common runtime suite.

That is test infrastructure rather than new syntax, but it is part of
how a language feature becomes usable and maintained.

### RETURNING completed another important SQLite surface

Between December 19 and 21, 2024, CQL adds
[INSERT RETURNING][insert-returning],
[DELETE RETURNING][delete-returning],
[UPDATE RETURNING][update-returning], and
[UPSERT RETURNING][upsert-returning].

This is not just four parser productions. A modifying statement can now
also produce a typed result. That affects cursors, generated interfaces,
C and Lua output, JSON metadata, query plans, test helpers, and backed
table rewrites.

**Usage change:** code can modify data and obtain the resulting values
without a separately maintained follow-up query that tries to reconstruct
what the modification did.

The public patches wire the feature through those surfaces and add
runtime cases for the different forms. The ordinary row/result machinery
absorbs another useful kind of statement.

This is the completeness test for an established abstraction: can the
new SQL capability participate in all the existing ways of consuming a
result, or is it a parser-only island?

### Fewer independent ways to describe columns

In [December 2024][star-columns], `SELECT *` and `T.*` are lowered through
the `@columns` machinery.

The user-facing shorthand is old. The consolidation is new.

**Interpretation:** if star expansion and shape-directed selection must
obey the same naming and type rules, making them share a mechanism reduces
the chance that the language develops two subtly different definitions
of "these columns."

Likewise, shorter inferred CTE column lists and simpler empty-result
fallback spellings reduce repetition without changing the central query
model.

### FOR made a common loop pattern explicit

[FOR][for-statement] arrived in January 2025. Unlike a C `for`, the CQL
form has a condition and a sequence of state-update statements; the
initial setup is performed before the loop.

```sql
declare proc printf no check;

proc print_numbers(limit_ int!)
begin
  let i := 0;
  for i < limit_; i += 1;
  begin
    printf("%d\n", i);
  end;
end;
```

The important behavior is the increment/update point: `CONTINUE` proceeds
there before the next condition check. A handwritten `WHILE` with updates
at its bottom can accidentally skip them.

The feature keeps the ordinary control-flow model while giving a common
pattern an explicit form. The extension examples later use it to build
multirow procedural results.

### Blob streams extended records to collections

The [March 2025 blob-array helpers][blob-streams] add an addressable stream
of blobs: a header carries the count and offsets, and each element can be
an already serialized structured value.

The original cursor codec packages one record. Blob streams compose those
records instead of inventing an unrelated serializer for every array
element type.

The change includes C and Lua runtime support, builtin declarations,
metadata, and runtime cases. This is an extension of the storage library
and its typed access, not another dedicated statement family.

### Modern notation spread to generated code and documentation

In March 2025, `DECLARE` becomes optional for enums, const groups, groups,
and function declarations. Documentation and tests are updated to prefer
the shorter forms.

[Schema generation also adopts modern syntax][modern-schema]. That is an
important adoption marker: the language is no longer presented differently
depending on whether a person or the compiler produced the CQL.

These changes should not be counted as new enums, new constants, or new
functions. They are reductions in ceremony around existing capabilities.

### The language reached back out through SQLite

CQL began by generating callers of SQLite. By
[March 2025][sqlite-extension-results], the SQLite extension generator
can expose CQL procedures that produce results as table-valued functions.

That makes the relationship bidirectional. A CQL procedure can become a
component of a query issued by an SQLite client.

The patch includes substantial SQL test cases and a multirow procedural
example. It is not merely a claim that an extension wrapper could be
written eventually.

This widens reach without making the CQL compiler itself a new database
engine. SQLite remains the host and query executor.

### Bindings used metadata instead of multiplying compiler backends

The broader interoperability history follows a related direction. By
early 2023, the Java demo no longer requires the old Java runtime-output
mode. In [April 2024][jni-generator], automatic JNI generation is built
around metadata and the generated native interfaces; C# and Objective-C
wrapper tools provide other access paths.

These are not all new language constructs, but they change who can use
the language's procedures and results. JSON metadata carries information
about types, nullability, arguments, results, attributes, and dependencies
to tools that generate host-language interfaces.

This supports a division of responsibility: the compiler owns semantic
facts, while wrapper generators choose a host-language presentation.

The retirement of vault-sensitive code, discussed below, follows that
same division.

### Metadata completeness became an interface concern

The [December 2025 enum/const-group change][enum-attributes] carries their
attributes into JSON output. It is not the introduction of enums or
const groups, and the patch does not add new enum grammar.

In [January 2026][emitted-groups], emitted-status metadata identifies
which declaration groups were actually emitted in a translation unit.

That distinction matters to downstream tools: knowing a declaration
exists is not the same as knowing its interface was emitted here.

**Interpretation:** as CQL becomes a source for more generated interfaces,
completeness means carrying semantic distinctions through the metadata
boundary, not just successfully generating native code.

### Import ordering and schema history had to fit together

The [November 2025 include-block change][include-schema-version] permits
`@schema_upgrade_version` in the initial include section and requires it
before meaningful declarations.

The recorded need is to combine schema includes with an upgrade version
that must be established before table declarations are interpreted.

That is a small but consequential interaction between two older systems:
import-like ordering and version-dependent schema visibility.

The direction remains consistent. Rather than allow arbitrary ordering
and recover from it later, the language establishes a useful invariant
at the boundary.

---

## The history also contains subtraction

Calling this an evolution history rather than a feature list requires
giving removals their proper weight.

### Privacy encoding was tried, then moved out of the compiler

Sensitivity was already part of the public baseline. The vault-sensitive
work in 2021 added result/cursor encoding and decoding, with context support
later that year.

The aspiration was a more deliberate path from sensitive stored values
to visible values, including an explicit decode step and customizable
encoding behavior.

The [retirement documentation][vault-retirement] is unusually direct:
the feature was not being used, and wrapping results through metadata-driven
API generators was judged a better place for this policy. The
[December 2024 removal][vault-remove] deleted substantial compiler,
runtime, and binding machinery.

The important distinction is that **sensitivity tracking was not removed
with vault encoding**. A type property and a specific generated encoding
policy are different things.

This episode is about scope. It is reasonable to want the application
interface to protect sensitive values without insisting that the lowest
level SQL code generator own every encoding choice.

### Other withdrawals usually preserve the underlying need

| Withdrawn or superseded surface | What remained or replaced it |
|---|---|
| Classic base/extension/assembly fragments | Shared fragments and more general checked query composition |
| Opt-in nullability improvement setting | Flow-sensitive nullability as ordinary compiler behavior |
| Separate `@resub` and versioned unsubscribe notation | Simpler subscription/deletion treatment |
| `::`/`:::` naming-convention operators | Single-colon pipelines with explicit `@op` mappings |
| Dedicated cursor/blob storage statements | Ordinary typed runtime calls and pipelines |
| Global backing-helper mappings | Per-table attribute-driven backing |
| Unrestricted text-preprocessor composition | Structured macros, statement-level conditionals, import-like includes |
| Compiler-owned vault encoding | Metadata-driven application wrappers, where desired |

These are not all the same kind of change. Some remove a capability;
others preserve it under a more general mechanism; still others deliberately
restrict how it can be expressed.

The common question is whether the special machinery remains the simplest
way to satisfy the need.

---

## When did the features become ordinary?

An isolated test named after a feature is necessary evidence, but weak
evidence of adoption. The stronger question is whether unrelated programs
start relying on it.

### Observable transitions

| Transition | Public evidence | What can reasonably be concluded |
|---|---|---|
| Flow typing leaves opt-in status | September 2021 changes to `cg_test.sql`, unconditional analysis, removal of the opt-in setting | Existing generated-code tests must account for flow facts |
| Shared fragments become infrastructure | September 2022 backed-table read rewrites generate fragments | Composition is useful to the compiler itself |
| Lua goes beyond emitted examples | Shared upgrade/runtime inputs, backed-table cases, checked runtime output, later C/Lua serialization comparisons | Important common scenarios exercise both backends |
| Native macros support the runtime suite | November 2023 conversion of `run_test.sql` | Macros become part of nearly every ordinary runtime test |
| CQL supports a compiler utility | November 2023 verifier conversion | Procedural, SQL, and native-call facilities work together in a real tool |
| Modern syntax becomes conventional | January 2024 echo/test changes; March 2025 docs/schema generation | The shorter surface becomes the repository's preferred presentation |
| `@op` becomes library vocabulary | October 2024 verifier, line tester, runtime, and playground migrations | Dispatch is used outside dedicated overload tests |
| New data features improve assertions | Late 2024 `@TMP`, formatting, and equality-macro work | Metaprogramming and runtime type facilities become harness infrastructure |
| Modern SQL enters executable coverage | December 2024 modern SQLite lane and `MODERN_TEST!` cases | Newer SQL is exercised against a suitable runtime |
| Metadata extends downstream reach | JNI/wrapper work, extension result tests, later attribute/emission metadata | Language interfaces become consumable by more than generated C callers |

Each conclusion is narrower than "widely deployed." The record supports
repository use. It does not supply a survey of applications.

### A small, reproducible adoption census

The following counts use only `sources/test/run_test.sql` at historical
snapshots. They count source lines matching the indicated construct,
not compiled tests, executions, or distinct semantic cases.

Block comments are excluded. `LET` and `FOR` counts require the keyword
at the beginning of a source line, after whitespace. Macro declarations
match `@macro(` at that position; `TEST!` counts match invocations at that
position. Matching is case-insensitive.

The counts include macro bodies and conditional branches. They do not
deduplicate expansions. In particular, a `FOR` count is not a count of
loops executed in any one backend.

| Snapshot | `LET` lines | Native macro declarations | `TEST!` invocation lines | `FOR` lines |
|---|---:|---:|---:|---:|
| [Initial import, October 2020][initial] | 0 | 0 | 0 | 0 |
| [End of 2021][snapshot-2021] | 24 | 0 | 0 | 0 |
| [End of 2022][snapshot-2022] | 88 | 0 | 0 | 0 |
| [End of 2023][snapshot-2023] | 114 | 6 | 151 | 0 |
| [End of 2024][snapshot-2024] | 280 | 15 | 190 | 0 |
| [Study endpoint][endpoint] | 307 | 16 | 200 | 46 |

The year-end snapshots are the last commits reachable from the analyzed
endpoint before January 1 of the next year, using Git's commit-time
cutoff. They are not release tags.

There are two clear signals. `LET` spreads well beyond its introduction.
Native macros become the ordinary runtime-test framework almost immediately
after introduction, then support a growing body of tests.

The zero `TEST!` count in the earlier years does **not** mean there were
no tests. Those snapshots use the older C-preprocessor framework.

The census is deliberately modest. A broad search for a colon would
confuse pipeline calls with attributes and other syntax. A raw search
for a feature name would mix examples, diagnostics, comments, and invalid
programs. The explicit migration patches are stronger evidence for
features whose textual spelling is not unambiguous.

### What this evidence cannot say

These measures do not establish popularity outside the repository,
performance benefit, or absence of defects. A feature can be used all
over the harness and still have a rarely exercised boundary.

They do establish a useful distinction:

> CQL did not merely accumulate features that appeared once in a semantic
> fixture. Several major features changed how the project wrote its own
> programs and tests.

---

## The through-line: less repetition, stronger composition

The language's evolution has several recurring moves.

### 1. Reuse a fact instead of copying it

A shape supplies columns, cursor fields, arguments, result interfaces,
and serialization layouts. A flow fact supplies a nullability or
initialization proof. Metadata supplies a binding generator's interface
knowledge.

The compiler's value increases when one fact can serve several operations.
That is more consequential than saving a few keywords.

### 2. Name a recurring pattern, then generalize it

Procedure savepoints name a transaction pattern. Parent/child result
sugar names a partitioning pattern. Shared fragments name a query-reuse
pattern. Native macros name repeated syntax.

Later generalization sometimes makes an older special form unnecessary.
Cursor serialization moves to calls; stars use `@columns`; explicit
operations replace name guessing.

This is not a contradiction. A special form can be useful on the way to
a better general mechanism.

### 3. Keep SQLite in the picture

CQL keeps adding useful SQLite surface area and delegates actual SQL
execution to SQLite. The generated code remains a caller of the database,
even when logical-table rewrites make the SQL more elaborate.

The later extension work lets SQLite call CQL-produced components in
return. It widens the relationship without changing who is the database
engine.

### 4. Make extensibility explicit

Attributes, type kinds, interfaces, JSON metadata, `@op`, and runtime
helpers make extension points visible.

They let a library or wrapper generator declare a policy without making
every policy a new compiler backend or grammar family. The vault removal
is the clearest example of deciding that an application-specific policy
belongs on the other side of such an interface.

### 5. Prove the useful combinations

Nullability has to work with calls and loops, not only `IF`. Backing has
to work with DML and multiple logical tables, not only one read.
`RETURNING` has to work with results and metadata, not only parsing.
Quoted identifiers have to survive generated helpers. A second backend
has to execute common programs, not only print them.

This is where need turns into completeness. The language becomes useful
when the features meet without forcing the programmer to rebuild the
missing connections.

### Where the aspiration reached

The initial public system was already more than a stored-procedure syntax
for SQLite. But its central promise was still easy to state: write typed
SQL and control flow; get correct native plumbing.

By the endpoint, that same system can describe reusable queries, rich
result interfaces, nested collections, schema history, structured payloads,
alternative storage layouts, runtime containers, and its own test
metaprogramming. It targets C and Lua and publishes semantic information
for other language interfaces.

The reach expanded, but the best additions did not require abandoning
the original idea. They gave the compiler more of the information it
needed to do repetitive work consistently.

That is the history worth remembering: not a steady increase in the
number of constructs, but a steady effort to make the programmer's
intent the source of the bookkeeping.

---

## Feature coverage and further reading

This is an episodic account, not a release-by-release changelog. The
following index makes the major subjects findable, including features
already present at the public baseline.

| Subject | Historical treatment | Current guide |
|---|---|---|
| Procedures, native calls, arguments, error handling, transactions | Baseline; shape forwarding and savepoints; scalar-query policies; modern syntax | [Statements and error checking](../../user_guide/09_statements_summary_and_error_checking.md) |
| SQL DDL/DML, CTEs, recursion, windows, upsert | Baseline; SQL-completeness additions; modern SQLite and `RETURNING` | [Statements](../../user_guide/09_statements_summary_and_error_checking.md) |
| Cursors, boxes, shapes, bundles, `USING`, subtraction, `@columns` | Epochs 1, 3, and 4; later consolidation | [Cursors](../../user_guide/05_cursors.md) |
| Enums, constants, named types, kinds, inference, flow analysis | Epochs 1 and 2; bindings and shorter declarations later | [Expressions](../../user_guide/03_expressions_fundamentals.md) |
| Schema versions, regions, migration, recreation, subscription | Baseline and Epochs 4 and 7 | [Schema management](../../user_guide/10_schema_management.md) |
| Classic fragments, shared queries, expression fragments | Epoch 3 and the withdrawal discussion | [Shared fragments](../../user_guide/14_shared_fragments.md) |
| Results, `OUT`, `OUT UNION`, interfaces, partitioning, nested children | Baseline and Epoch 4 | [Result sets](../../user_guide/07_result_sets.md) |
| Structured blobs, backed tables, JSON backing, blob streams | Epochs 4, 6, and 7 | [Advanced blob features](../../user_guide/16_advanced_blob_features.md) |
| Pipelines, properties, arrays, explicit operations, containers | Epochs 5 and 6 | [Expressions](../../user_guide/03_expressions_fundamentals.md) |
| Macros, imports, conditional compilation, generated identifiers, temporaries | Epochs 5 and 6; ordering consolidation in Epoch 7 | [Preprocessing](../../user_guide/18_pre_processing.md) |
| Metadata and generated host-language access | Baseline and Epoch 7 | [JSON output](../../user_guide/13_json_output.md) |
| Test generation and dummy values | Baseline, backing integration, and adoption discussion | [Testability](../../user_guide/12_testability_features.md) |
| Sensitivity and retired vault encoding | Baseline and the withdrawal discussion | [Vault retirement note][vault-retirement] |
| Lua and backend-independent behavior | Epoch 4 and subsequent runtime/library completion | [Lua code generation](../10_lua_notes.md) |

The links below are historical anchors, not a complete inventory of
every patch in each feature's implementation. Follow the surrounding
history when distinguishing its initial form from its later completion.

[initial]: https://github.com/ricomariani/CG-SQL-author/commit/f7f1af408fc335a542de735388709c53a9e4461a
[endpoint]: https://github.com/ricomariani/CG-SQL-author/commit/b653ccaac184922f95bf1cd5b6ffbcf48f333287
[from-functions]: https://github.com/ricomariani/CG-SQL-author/commit/0eb5ab73
[argument-shapes]: https://github.com/ricomariani/CG-SQL-author/commit/f761c19e
[argument-bundles]: https://github.com/ricomariani/CG-SQL-author/commit/2852c064
[out-declare]: https://github.com/ricomariani/CG-SQL-author/commit/7819ed15
[from-shape]: https://github.com/ricomariani/CG-SQL-author/commit/d170e052
[boxed-parse]: https://github.com/ricomariani/CG-SQL-author/commit/ebc4afd1
[boxed-codegen]: https://github.com/ricomariani/CG-SQL-author/commit/f8a36167
[proc-savepoint]: https://github.com/ricomariani/CG-SQL-author/commit/25ebd50b
[enums]: https://github.com/ricomariani/CG-SQL-author/commit/3aabe8ce
[named-types]: https://github.com/ricomariani/CG-SQL-author/commit/11d04e62
[kinds]: https://github.com/ricomariani/CG-SQL-author/commit/38328b42
[let]: https://github.com/ricomariani/CG-SQL-author/commit/83fafc24
[constant-folding]: https://github.com/ricomariani/CG-SQL-author/commit/56d3963a
[constant-groups]: https://github.com/ricomariani/CG-SQL-author/commit/5b6eac31
[virtual-tables]: https://github.com/ricomariani/CG-SQL-author/commit/86cf01d2
[indexes]: https://github.com/ricomariani/CG-SQL-author/commit/d8089b74
[if-nothing]: https://github.com/ricomariani/CG-SQL-author/commit/8b7a9dfe
[rc-scope]: https://github.com/ricomariani/CG-SQL-author/commit/7a50b4f2
[chosen-error]: https://github.com/ricomariani/CG-SQL-author/commit/ec73ec83
[flow-initial]: https://github.com/ricomariani/CG-SQL-author/commit/fbae41ae
[flow-cg-adoption]: https://github.com/ricomariani/CG-SQL-author/commit/7656d226
[flow-always]: https://github.com/ricomariani/CG-SQL-author/commit/728a41f9
[initialization]: https://github.com/ricomariani/CG-SQL-author/commit/c45f07c9
[cursor-row]: https://github.com/ricomariani/CG-SQL-author/commit/6f60abc7
[switch]: https://github.com/ricomariani/CG-SQL-author/commit/587e0762
[switch-all]: https://github.com/ricomariani/CG-SQL-author/commit/da49e7cc
[alias-policy]: https://github.com/ricomariani/CG-SQL-author/commit/21048917
[short-circuit]: https://github.com/ricomariani/CG-SQL-author/commit/3dd9cec6
[shared-start]: https://github.com/ricomariani/CG-SQL-author/commit/2188cbfc
[shared-codegen]: https://github.com/ricomariani/CG-SQL-author/commit/22af803c
[shared-if]: https://github.com/ricomariani/CG-SQL-author/commit/93ceba07
[shared-no-else]: https://github.com/ricomariani/CG-SQL-author/commit/5d6b13eb
[expression-fragments]: https://github.com/ricomariani/CG-SQL-author/commit/86436f4e
[classic-takeback]: https://github.com/ricomariani/CG-SQL-author/commit/83cd8daf
[classic-remove]: https://github.com/ricomariani/CG-SQL-author/commit/e99ed789
[groups]: https://github.com/ricomariani/CG-SQL-author/commit/116febb6
[native-alias]: https://github.com/ricomariani/CG-SQL-author/commit/2780fee7
[structured-blobs]: https://github.com/ricomariani/CG-SQL-author/commit/b573687a
[dynamic-params]: https://github.com/ricomariani/CG-SQL-author/commit/d03efc80
[partition]: https://github.com/ricomariani/CG-SQL-author/commit/3048113f
[interfaces]: https://github.com/ricomariani/CG-SQL-author/commit/afa2af21
[shape-narrowing]: https://github.com/ricomariani/CG-SQL-author/commit/085ba4c4
[parent-child]: https://github.com/ricomariani/CG-SQL-author/commit/ffe2c852
[result-cursors]: https://github.com/ricomariani/CG-SQL-author/commit/139f3645
[result-values]: https://github.com/ricomariani/CG-SQL-author/commit/2b92b253
[shape-subtraction]: https://github.com/ricomariani/CG-SQL-author/commit/1d03329e
[backed-read]: https://github.com/ricomariani/CG-SQL-author/commit/2238a465
[backed-initial-runtime]: https://github.com/ricomariani/CG-SQL-author/commit/83898dbf
[resub-remove]: https://github.com/ricomariani/CG-SQL-author/commit/27f0cb64
[update-from]: https://github.com/ricomariani/CG-SQL-author/commit/c830e63a
[lua-initial]: https://github.com/ricomariani/CG-SQL-author/commit/51fea1e7
[lua-serialization]: https://github.com/ricomariani/CG-SQL-author/commit/66281918
[serialization-equivalence]: https://github.com/ricomariani/CG-SQL-author/commit/d94eded9
[short-proc]: https://github.com/ricomariani/CG-SQL-author/commit/14d138fa
[compound-assignment]: https://github.com/ricomariani/CG-SQL-author/commit/2404f735
[pipeline-initial]: https://github.com/ricomariani/CG-SQL-author/commit/cbda0556
[quoted-identifiers]: https://github.com/ricomariani/CG-SQL-author/commit/ead444bf
[native-macros]: https://github.com/ricomariani/CG-SQL-author/commit/98bbd87f
[preprocessing-guide]: ../../user_guide/18_pre_processing.md
[include-import]: https://github.com/ricomariani/CG-SQL-author/commit/1532e4ce
[verifier-cql]: https://github.com/ricomariani/CG-SQL-author/commit/97bdefcc
[nonnull-echo]: https://github.com/ricomariani/CG-SQL-author/commit/f62ae2b5
[modern-run-tests]: https://github.com/ricomariani/CG-SQL-author/commit/51e7843e
[op-declarations]: https://github.com/ricomariani/CG-SQL-author/commit/3d53b5b8
[json-extract]: https://github.com/ricomariani/CG-SQL-author/commit/c8e40e91
[sqlite-direct-calls]: https://github.com/ricomariani/CG-SQL-author/commit/b5eb31f2
[dynamic-access]: https://github.com/ricomariani/CG-SQL-author/commit/5379cffe
[blob-functions]: https://github.com/ricomariani/CG-SQL-author/commit/d6ed2e23
[blob-statements-remove]: https://github.com/ricomariani/CG-SQL-author/commit/47b82609
[macro-tmp]: https://github.com/ricomariani/CG-SQL-author/commit/1e05c693
[backing-attributes]: https://github.com/ricomariani/CG-SQL-author/commit/c0bad4b6
[modern-sqlite]: https://github.com/ricomariani/CG-SQL-author/commit/0538fdc9
[insert-returning]: https://github.com/ricomariani/CG-SQL-author/commit/81c9b5ea
[delete-returning]: https://github.com/ricomariani/CG-SQL-author/commit/f5abe4e2
[update-returning]: https://github.com/ricomariani/CG-SQL-author/commit/de609d93
[upsert-returning]: https://github.com/ricomariani/CG-SQL-author/commit/80b32ee7
[star-columns]: https://github.com/ricomariani/CG-SQL-author/commit/70e93f7d
[for-statement]: https://github.com/ricomariani/CG-SQL-author/commit/f3ca247b
[blob-streams]: https://github.com/ricomariani/CG-SQL-author/commit/989d5090
[modern-schema]: https://github.com/ricomariani/CG-SQL-author/commit/f2c3f239
[sqlite-extension-results]: https://github.com/ricomariani/CG-SQL-author/commit/8215281b
[jni-generator]: https://github.com/ricomariani/CG-SQL-author/commit/9c15533d
[enum-attributes]: https://github.com/ricomariani/CG-SQL-author/commit/20f15750
[emitted-groups]: https://github.com/ricomariani/CG-SQL-author/commit/e5e91286
[include-schema-version]: https://github.com/ricomariani/CG-SQL-author/commit/6b16ac88
[vault-retirement]: ../../user_guide/17_vault_sensitive.md
[vault-remove]: https://github.com/ricomariani/CG-SQL-author/commit/95330a90
[snapshot-2021]: https://github.com/ricomariani/CG-SQL-author/commit/066f62d7f743f8a5340391bdda9cb4a994ef0115
[snapshot-2022]: https://github.com/ricomariani/CG-SQL-author/commit/f23fbf51a8831bfc0d01dfd0154a788709bbe0ad
[snapshot-2023]: https://github.com/ricomariani/CG-SQL-author/commit/52840d934af6ed5e6a9d5def13397ba7424607cc
[snapshot-2024]: https://github.com/ricomariani/CG-SQL-author/commit/d48a816dfa35454adb79d6ad903b8df48f6d485a
