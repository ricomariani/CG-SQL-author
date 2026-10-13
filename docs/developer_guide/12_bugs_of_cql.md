---
title: "Part 12: The Bugs of CQL"
weight: 12
---
<!---
-- Copyright (c) Rico Mariani
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## A point-in-time study of defects in the public history of CG/SQL

**Study date:** October 13, 2026

**Public-history window:** October 7, 2020 through October 10, 2026

**Analyzed endpoint:** [`957db34adb4337afb4498d9feabea7cdb4f9036a`](https://github.com/ricomariani/CG-SQL-author/commit/957db34adb4337afb4498d9feabea7cdb4f9036a)

**Repository:** `ricomariani/CG-SQL-author`

### How to read this chapter

Read this as a historical snapshot. It is not a live quality dashboard. The
counts, file sizes, examples, and conclusions describe the public repository
at the analyzed endpoint on October 10, 2026. I did not read later fixes or
architectural changes back into the results.

The public history also begins with an already mature compiler. It does not
contain CQL's earlier internal development, when the architecture and defect
profile would have been substantially different. This chapter is about the
maintenance history of the mature, open-source codebase.

### How I made this chapter

I used an AI coding agent to mine the complete public Git history, screen
candidate fix commits, measure the source and test corpus, retrieve historical
patches, compare them with current code, and produce the first draft. It did a
lot of the raw work, so I did not personally research and write every sentence
from scratch.

I deliberately left the agent room to read the history and reach its own
conclusions because the independent reading was useful. Then I heavily curated
it. I added my own domain knowledge, supplied operational and architectural
context that Git cannot provide, checked the examples against the source and
historical patches, and corrected bad assumptions.

That changed several conclusions:

- I corrected the interpretation of CQL's fail-fast AST and tree-shape
  development model;
- I separated observed operational bugs from development-time failures,
  CI-prevented pushes, and prophylactic audit hardening;
- I added what I remember from sustained production use: roughly 12 real bugs
  per year;
- I corrected an overbroad interpretation of compiler global state and
  reentrancy;
- I distinguished incomplete first fixes from additional field failures;
- I audited every code sample and expanded examples that did not show enough
  setup, operation, or test evidence.

So the agent did a lot of the research and drafting. I checked and rewrote the
result, and I own it. The chapter is in my voice and these are my conclusions.

Use this as an engineering study. There is no authoritative incident ledger
behind these numbers, so read them with the limits stated below.

---

## Summary

The short version: CG/SQL's public history looks like a mature compiler with a
very specific defect shape. The bugs cluster at **boundaries between otherwise
well-structured subsystems**.

Here is the pattern that matters most:

> The code usually gets each local operation right. Bugs recur when one fact
> must remain true across several compiler phases, representations, backends, or
> ownership conventions.

I came away with five ideas that organize the history:

1. **Cross-phase semantic invariants** - nullability, sensitivity, error state,
   identifier spelling, and ownership must survive semantic analysis, rewriting,
   SQL generation, and multiple backends. Novel AST kinds are a special case:
   the normal path is deliberately fail-fast, so missing handlers are forced
   out during development.
2. **Schema evolution and dependency ordering** - create order, drop order,
   dependency order, declaration order, key order, and quoted-name handling are
   related but not interchangeable.
3. **Global compiler state and C ownership** - the intentionally stateful
   implementation is concise and effective, but nested compilation work,
   repeated invocation, aliasing, and `+1` reference ownership require explicit
   protocols.
4. **Representation boundaries** - growable buffers, serialized blobs, offset
   tables, platform integer widths, and C aliasing/alignment rules produce a
   disproportionate share of low-level fixes.
5. **Coverage-driven fail-fast development plus independent tests** - 100%
   coverage and always-on contracts force new tree shapes through every stage
   that can see them. Golden output is still only a consistency oracle, so the
   hardest remaining bugs survived when the compiler and its expected outputs
   shared the same mistaken assumption.

CQL is also a useful counterexample to a fair amount of conventional C advice.
It has a 27,000-line semantic-analysis file, hundreds of file-static variables,
large macros, and several very long functions. At the same time, the median
function is only 14 lines, naming is exceptionally regular, contracts are dense
and always on, arenas simplify allocation lifetimes, and the test suite compiles
and executes generated code through several independent paths.

The apparent contradiction is the interesting part:

> CQL succeeds because its departures from conventional structural advice are
> consistent, and because the compensating mechanisms fit the compiler it
> actually is.

---

## Scope and method

I examined only the public Git history. The root commit is:

| Item | Value |
|---|---|
| Commit | [`f7f1af408fc335a542de735388709c53a9e4461a`](https://github.com/ricomariani/CG-SQL-author/commit/f7f1af408fc335a542de735388709c53a9e4461a) |
| Date | October 7, 2020 |
| Subject | `Initial commit` |
| Initial import | 249 files, 184,612 inserted lines |

At the analyzed mainline tip, I found:

| Measure | Count |
|---|---:|
| Mainline commits | 2,238 |
| Mainline non-merge commits | 2,233 |
| Mainline merge commits | 5 |
| Unique commits across local public refs | 2,266 |
| Mainline activity span | 2020-10-07 to 2026-10-10 |

I screened commit messages conservatively:

- 809 commits contained some possible defect language.
- 284 subjects used stronger defect language.
- 88 commits remained after requiring production-code changes and excluding
  obvious documentation, formatting, build-only, and coverage-only work.

The number **88 is not a bug count**. Commit subjects overcount and undercount
in equal-opportunity fashion. Some commits called "fix" are cleanup. Some real
fixes are titled "Handle", "Require", "Validate", "Coverage", or simply state a
new invariant. A large audit commit can also contain several independent
corrections. Recent audit work also includes theoretical invariant hardening
that had no known failing caller. Rapid revert/reapply chains can record one
real bug plus a bad attempted fix that CI prevented from progressing. I use the
screen for trends and candidate selection, not as an exact defect ledger.

I then inspected representative commits by patch, affected production files,
tests, and generated-reference changes. The safety boundary is deliberate:
I did **not** search for new defects, try to trigger unknown failures, or assess
exploitability.

---

## The public defect profile

### Activity by year

| Year | Mainline commits | Conservative production-fix candidates | Approximate share |
|---|---:|---:|---:|
| 2020 | 131 | 4 | 3.1% |
| 2021 | 541 | 23 | 4.3% |
| 2022 | 416 | 13 | 3.1% |
| 2023 | 461 | 22 | 4.8% |
| 2024 | 410 | 14 | 3.4% |
| 2025 | 182 | 2 | 1.1% |
| 2026 through October 10 | 97 | 10 | 10.3% |

The 2025 number shows why message-based classification needs some humility. An
important reentrancy fix was hidden in a commit whose subject began with
coverage work. The 2026 screen likewise misses plainly corrective commits
titled "Validate", "Require", "Handle", and "Size". What I can say is that 2026
contains a concentrated correctness-audit spike. Much of that spike came from
AI-assisted review, and several findings are prophylactic rather than observed
failures. Calling these "exactly ten bugs" would give the heuristic precision
it does not have.

### Observed bugs versus audit hardening

The late-2026 changes need their own bucket.

For most older fixes, the history and my recollection are consistent with a
reported failure, something I personally observed, or a failure found while
developing a feature. I treated the recent AI-assisted audit work differently.
I let the agent ask, "What assumption here is not enforced?" That is a useful
question, and it produces a different kind of change.

Representative late-audit changes added buffer-aliasing contracts and
whole-shape representation checks. These are prophylactic hardening, not
evidence of field failures; detailed examples appear below.

### CI-caught changes are bugs prevented

Git history records what was pushed, not what survived the delivery process.
Those are not the same thing.

The `cql_multinull` object-handling chain is the cleanest example:

1. [`f97fb8be74dc`](https://github.com/ricomariani/CG-SQL-author/commit/f97fb8be74dc)
   attempted to fix a real missing runtime case.
2. [`5b70a230f899`](https://github.com/ricomariani/CG-SQL-author/commit/5b70a230f899)
   reverted that attempt 14 minutes later.
3. [`64d4305c205e`](https://github.com/ricomariani/CG-SQL-author/commit/64d4305c205e)
   applied the properly constrained fix the next day.

What happened is simple: I pushed the first fix too aggressively without
running the full suite. CI caught it immediately and forced the correction.
The original missing object case was a real bug. The bad attempted fix was not
a second operational bug; it was a bug prevented by the test and delivery
system.

This distinction matters to the statistics. A raw fix-commit count can assign
two fixes, a revert, and a reapplication to one escaped defect. Rapid CI-driven
follow-ups should be collapsed into the originating issue and credited to the
prevention machinery, not counted as additional field failures.

### Where fixes occurred

The following counts overlap because a commit can affect several phases:

| Phase or file family | Candidates in the conservative 88-commit screen |
|---|---:|
| Code generation | 25 |
| Runtime | 24 |
| Semantic analysis | 22 |
| Other production tools and bindings | 16 |
| Core AST, buffer, and symbol utilities | 9 |
| Parser | 9 |
| Lexer | 7 |
| SQL echo and rewriting | 6 |

This distribution looks right for a compiler, with one CQL-specific twist.
Traditional optimizing compilers often find many wrong-code bugs in
optimization passes. CQL has extensive rewrites and code generation, without a
GCC/LLVM-style tower of aggressive machine-level optimization passes. CQL's
specific concentration is in semantics-preserving rewrites, schema migration,
backend/runtime agreement, generated ownership, and SQLite-facing output--not
machine-level optimization.

---

## Does it work?

Yes.

My recollection from the years of constant use at Meta is about **12 real bugs
per year**. The public history lines up with that number.

The conservative screen found 88 production-fix candidates over roughly six
public years, or about 14.6 candidate commits per year. Using the five complete
years from 2021 through 2025 gives 14.8 per year. Candidate commits mix
hardening, pre-check-in failures, CI-rejected attempts, cleanup, multi-commit
fixes, and bugs hidden by neutral or bundled commit subjects, so the screen
cannot establish an incident count.

Given those effects, roughly 12 real bugs per year is entirely plausible. Git
cannot prove the exact number; that would require a complete issue and incident
ledger. Still, the number is supportable and fits the public evidence.

Even if I set my recollection aside, I judge that rate to be exceptionally
low. The system is roughly 83,000 lines of current core C and headers, with a
grammar, multiple generators, a runtime, schema migration, several
representation formats, and years of sustained production use. About one
observed bug a month across that surface is a very strong result.

I do not have a statistically calibrated comparison population, so I cannot
attach a percentile to "exceptionally low." It is my engineering judgment, not
a measured statistic.

So yes, the compiler works. The low operational bug rate, fail-fast covered
tree walking, layered execution tests, and long production use all point in the
same direction.

---

## Ranked findings

### 1. Fail-fast tree walking works; cross-phase semantics are harder

The largest defect family cuts across labels such as "parser bug", "semantic
bug", and "code-generator bug." The common ingredient is **a fact represented
in more than one place**.

I would separate AST kind dispatch from the rest because CQL is deliberately
designed to blow up on a novel tree shape. The semantic expression dispatcher
does this:

```c
cql_noexport void sem_expr(ast_node *ast) {
  // These are all the expressions there are, we have to find it in this table
  // or else someone added a new expression type and it isn't supported yet.
  symtab_entry *entry = symtab_find(exprs, ast->type);
  Invariant(entry);
  sem_expr_dispatch *disp = (sem_expr_dispatch*)entry->val;
  disp->func(ast, disp->str);
}
```

The C expression generator does the same thing after semantic analysis:

```c
// These are all the expressions there are, we have to find it in this table
// or else someone added a new expression type and it isn't supported yet.
symtab_entry *entry = symtab_find(cg_exprs, expr->type);
Invariant(entry);
cg_expr_dispatch *disp = (cg_expr_dispatch*)entry->val;
disp->func(expr, disp->str, is_null, value, pri, disp->pri_new);
```

The extraction macros then check the detailed child shape at each step. A
grammar change that adds or changes a reachable tree shape should therefore
produce an immediate assertion at the first phase that has not been updated.

The 100% coverage norm is what makes this useful rather than aspirational. A
new parser production is exercised, semantic analysis fails until the new shape
is handled, and any shape that survives semantic analysis fails again in
codegen until that stage handles it. Development becomes a sequence of
concrete failures. You do not have to forecast every registration in advance
because the compiler tells you where the next one is.

That works extremely well. In the normal covered path, a missing handler cannot
quietly persist.

The persistent examples are the facts that can be handled locally and still be
wrong globally:

- a semantic error reported but not recorded in the enclosing node;
- nullability or sensitivity copied from only one operand;
- a quoted identifier handled by static SQL but not dynamic upgrade SQL;
- a rewritten expression preserving its value but not its ownership or type
  wrapper;
- a logical table name renamed in ordinary SQL expressions but not dot
  expressions.

#### The missing registrations were mostly deliberate no-op cases

In May 2022, `declare_interface_stmt` was a valid AST kind, but the C backend
had no no-op registration for it:

```diff
   NO_OP_STMT_INIT(declare_const_stmt);
   NO_OP_STMT_INIT(declare_named_type);
   NO_OP_STMT_INIT(declare_proc_no_check_stmt);
   NO_OP_STMT_INIT(declare_select_func_no_check_stmt);
+  NO_OP_STMT_INIT(declare_interface_stmt);
```

Commit:
[`3a9f41f21a266ab5377d23d9df3594c9a2a2f9c7`](https://github.com/ricomariani/CG-SQL-author/commit/3a9f41f21a266ab5377d23d9df3594c9a2a2f9c7)

At that point, statement code generation immediately required a registered
handler:

```c
symtab_entry *entry = symtab_find(cg_stmts, stmt->type);
Contract(entry);
```

That commit changed only the registration line; it added no focused regression
test. What supports the interpretation is the fail-fast lookup, the
crash-specific commit subject, and the missing no-op registration itself.

The same narrow family reappeared in December 2024, when two macro-definition
AST kinds needed no-op registration in both C and Lua backends:

```diff
diff --git a/sources/cg_c.c b/sources/cg_c.c
@@
   NO_OP_STMT_INIT(expr_macro_def);
   NO_OP_STMT_INIT(stmt_list_macro_def);
   NO_OP_STMT_INIT(query_parts_macro_def);
   NO_OP_STMT_INIT(cte_tables_macro_def);
+  NO_OP_STMT_INIT(select_expr_macro_def);
+  NO_OP_STMT_INIT(select_core_macro_def);

diff --git a/sources/cg_lua.c b/sources/cg_lua.c
@@
   LUA_NO_OP_STMT_INIT(expr_macro_def);
   LUA_NO_OP_STMT_INIT(stmt_list_macro_def);
   LUA_NO_OP_STMT_INIT(query_parts_macro_def);
   LUA_NO_OP_STMT_INIT(cte_tables_macro_def);
+  LUA_NO_OP_STMT_INIT(select_expr_macro_def);
+  LUA_NO_OP_STMT_INIT(select_core_macro_def);
```

Commit:
[`868ec5b7`](https://github.com/ricomariani/CG-SQL-author/commit/868ec5b7)

This commit likewise added no dedicated regression test. These definitions had
already served their semantic purpose, so the correct backend evidence was the
explicit no-op classification rather than generated output.

The details matter here. These nodes were deliberately ignored by codegen.
They are the awkward edge of the fail-fast scheme: the correct handler is
`NO_OP`, so there may be no ordinary generated output to make the omission
obvious except the assertion itself.

I would not mechanically require every parser AST kind in every backend.
Semantic analysis rewrites the tree, some parser shapes disappear, and some
semantic-only declarations should never reach code generation as active work.
Each phase intentionally sees a different set of shapes.

So I read the history more narrowly than "distributed dispatch tables drift."
Normal reachable shapes fail fast and coverage forces them out. The residual
registration misses are mainly intentional no-op classifications or other
cases where a phase is supposed to ignore a shape.

#### Error reporting and error state were separate obligations

In July 2021, assignment compatibility correctly detected a lossy conversion,
but the error was attached to the wrong expression and the enclosing update
node did not receive error state:

```diff
-  if (!sem_verify_assignment(ast, sem_type_left, sem_type_right, left->sem->name)) {
+  if (!sem_verify_assignment(right, sem_type_left, sem_type_right, left->sem->name)) {
+    record_error(ast);
     return;
   }
```

The focused test checks both the diagnostic and propagation through the update
subtree:

```sql
-- TEST: update with loss of precision
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- + Error % lossy conversion from type 'LONG_INT' in 1L
-- +1 Error
update foo set id = 1L where id = 2;
```

Commit:
[`5084c83c1f751dcfd436253c88bad3fbf1bb85f7`](https://github.com/ricomariani/CG-SQL-author/commit/5084c83c1f751dcfd436253c88bad3fbf1bb85f7)

The same distinction surfaced again in December 2023:

```diff
   // check if length of columns to update and provided values match
   for ( ; name_list && insert_list; name_list = name_list->right, insert_list = insert_list->right) {}
   if (name_list || insert_list) {
     report_error(ast, "CQL0157: count of columns differs from count of values", NULL);
+    record_error(ast);
+    return;
   }
```

Commit:
[`7933769f72b4a7d18e73895eac150fa200378c76`](https://github.com/ricomariani/CG-SQL-author/commit/7933769f72b4a7d18e73895eac150fa200378c76)

The second bug hid inside batched negative tests. Before the repair, four
invalid constructs lived in one procedure and the aggregate `+4 error:` count
could not prove that each construct produced its own error:

```diff
-proc test_update_from_shape_errors(like update_test_1)
-begin
-  -- Swapped ordering of columns lead to incompatible types.
-  update update_test_1
-  set (name, id) = (from arguments);
-
-  -- Use of non existent shape in values
-  update update_test_1 set (id, name) = (from cursor_not_exist);
-
-  -- Use of non existent shape in column spec
-  update update_test_1 set (like cursor_not_exist) = (from arguments);
-
-  -- Count of columns differ from count of values
-  update update_test_1 set (id) = (from arguments);
-end;
```

The repaired tests isolate all four operations and check each exact count:

```sql
-- TEST: update from_shape sugar error handling, type mismatch
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- + {dot}: err
-- + {name ARGUMENTS}
-- + {name id}
-- * error: % incompatible types in expression 'name'
-- +1 error:
proc test_update_from_shape_errors0(like update_test_1)
begin
  update update_test_1
  set (name, id) = (from arguments);
end;

-- TEST: update from_shape sugar error handling, FROM invalid
-- + {update_stmt}: err
-- + {insert_list}: err
-- + {name cursor_not_exist}: err
-- * error: % name not found 'cursor_not_exist'
-- +1 error:
proc test_update_from_shape_errors1(like update_test_1)
begin
  update update_test_1 set (id, name) = (from cursor_not_exist);
end;

-- TEST: update from_shape sugar error handling invalid like shape
-- + {update_stmt}: err
-- + {columns_values}: err
-- + {shape_def}: err
-- + {name cursor_not_exist}: err
-- * error: % must be a cursor, proc, table, or view 'cursor_not_exist'
-- +1 error:
proc test_update_from_shape_errors2(like update_test_1)
begin
  update update_test_1 set (like cursor_not_exist) = (from arguments);
end;

-- TEST: update from_shape sugar error handling, missing count
-- + SET (id, name) = (ARGUMENTS.id);
-- + {update_stmt}: err
-- * error: % count of columns differs from count of values
-- +1 error:
proc test_update_from_shape_errors3(id int!)
begin
  update update_test_1 set (id, name) = (from arguments);
end;
```

The details matter here. This repeated defect says more about the abstraction
than the care of the person writing the code. The architecture had two distinct
operations, `report_error` and `record_error`, and convention was responsible
for keeping them paired.

#### Semantic flags are a lattice, not a single property

The 2021 `substr` fix combined nullability and sensitivity from all arguments
instead of copying flags from only the text operand:

```diff
-  // This will give us the same type nullability and sensitivity as the original string
-  sem_t flags = sem_type & (SEM_TYPE_NOTNULL | SEM_TYPE_SENSITIVE);
+  // The result is nonnull if all arguments are nonnull, and sensitive if any
+  // arguments are sensitive.
+  sem_t flags = combine_flags(arg1->sem->sem_type, arg2->sem->sem_type);
+  if (arg3) {
+    flags = combine_flags(flags, arg3->sem->sem_type);
+  }
```

Commit:
[`2020413560de1f84369d15dd5f793bde8258e02b`](https://github.com/ricomariani/CG-SQL-author/commit/2020413560de1f84369d15dd5f793bde8258e02b)

The six focused cases prove that nullable and sensitive flags can originate in
the string, start, or count argument:

```sql
-- + {name substr}: text
create proc substr_test_nullable_string(t text)
begin
  select substr(t, 1, 2) as t;
end;

-- + {name substr}: text
create proc substr_test_nullable_start(t text not null)
begin
  select substr(t, nullable(1), 2) as t;
end;

-- + {name substr}: text
create proc substr_test_nullable_count(t text not null)
begin
  select substr(t, 1, nullable(2)) as t;
end;

-- + {name substr}: text sensitive
create proc substr_test_sensitive_string(t text @sensitive)
begin
  select substr(t, 1, 2) as t;
end;

-- + {name substr}: text sensitive
create proc substr_test_sensitive_start(t text)
begin
  select substr(t, sensitive(1), 2) as t;
end;

-- + {name substr}: text sensitive
create proc substr_test_sensitive_count(t text)
begin
  select substr(t, 1, sensitive(2)) as t;
end;
```

Nullability, sensitivity, object kind, shape, and error state all decorate
expressions. Every builtin and every rewrite has to preserve or recompute the
right subset. That is why semantic bugs can recur in a well-tested compiler:
each special case is effectively a tiny compiler pass.

#### Flow analysis failed on the branch that contained nothing

In December 2021, empty `IF` branches were not counted as branches. That made an
improvement performed by every *non-empty* branch appear to be performed by
every branch:

```c
// Records the presence of an empty branch within the branch group. This is
// equivalent to calling `_flow_push_context_branch` immediately followed by
// `_flow_pop_context_branch`.
cql_noexport void flow_context_branch_group_add_empty_branch() {
  Contract(current_context);
  Contract(current_context->kind == FLOW_CONTEXT_KIND_BRANCH_GROUP);

  current_context->branch_group.branch_count++;
}
```

Commit:
[`d17a350684151871d4ed78b1126f8d6e1a86cbf9`](https://github.com/ricomariani/CG-SQL-author/commit/d17a350684151871d4ed78b1126f8d6e1a86cbf9)

The semantic callers now record an absent body as a real branch:

```diff
   if (stmt_list) {
     FLOW_PUSH_CONTEXT_BRANCH();
     sem_set_notnull_improvements_for_true_condition(expr);
     sem_stmt_list_in_current_flow_context(stmt_list);
     FLOW_POP_CONTEXT_BRANCH();
     if (is_error(stmt_list)) {
       record_error(ast);
       return;
     }
+  } else {
+    flow_context_branch_group_add_empty_branch();
   }

@@
     if (stmt_list) {
       FLOW_PUSH_CONTEXT_BRANCH();
       sem_stmt_list_in_current_flow_context(stmt_list);
       FLOW_POP_CONTEXT_BRANCH();
       if (is_error(stmt_list)) {
         record_error(elsenode);
         record_error(if_alt);
         goto error;
       }
+    } else {
+      flow_context_branch_group_add_empty_branch();
     }
```

The regression puts the empty branch in each significant position and verifies
that all six post-branch variables remain nullable:

```sql
-- TEST: An empty branch in an IF or SWITCH prevents the IF or SWITCH from
-- persisting any improvements.
-- + {name x0}: x0: integer variable
-- + {name x1}: x1: integer variable
-- + {name x2}: x2: integer variable
-- + {name x3}: x3: integer variable
-- + {name x4}: x4: integer variable
-- + {name x5}: x5: integer variable
-- - error:
create proc empty_branches_prevent_persisting_improvements()
begin
  declare a int;

  if 0 then
    -- empty
  else if 0 then
    set a := 1;
  else
    set a := 1;
  end if;
  let x0 := a;

  if 0 then
    set a := 1;
  else if 0 then
    -- empty
  else
    set a := 1;
  end if;
  let x1 := a;

  if 0 then
    set a := 1;
  else if 0 then
    set a := 1;
  else
    -- empty
  end if;
  let x2 := a;

  switch 0
  when 1 then
    -- empty
    leave;
  when 2 then
    set a := 1;
  else
    set a := 1;
  end;
  let x3 := a;

  switch 0
  when 1 then
    set a := 1;
  when 2 then
    set a := 1;
  else
    -- empty
    leave;
  end;
  let x4 := a;

  switch three_things.zero all values
  when three_things.zero then
    -- empty
    leave;
  when three_things.one then
    set a := 1;
  when three_things.two then
    set a := 1;
  end;
  let x5 := a;
end;
```

The empty branch had no data structure, but it was still a semantic case. I
like the eventual abstraction because "empty branch" now has an explicit place
in the flow protocol.

---

### 2. Schema migration and ordering form the hardest persistent subsystem

Schema evolution repeatedly produced fixes around order, dependency, and name
handling. This is the clearest long-running cluster in the public history.

The question is which order applies. Schema work has several perfectly
legitimate answers:

- declaration order;
- dependency order;
- reverse dependency order;
- drop order;
- create order;
- recreate-group order;
- primary-key column order;
- physical serialized-field order.

Each one is locally reasonable. Trouble starts when code reuses one where
another is required.

#### Drop order was not create order

In December 2021, recreate groups were sorted in the order needed to drop
tables, and that same order was reused for creation. Foreign keys can require
the reverse:

```diff
   CHARBUF_OPEN(recreate);
   CHARBUF_OPEN(update_tables);
+  CHARBUF_OPEN(pending_table_creates);

@@
     table_crc ^= crc_charbuf(&make_table);
-    bindent(&update_tables, &make_table, 4);

+    // Now we have to remember that the tables in the recreate annotations have been
+    // sorted by reverse ordinal, meaning they are in the correct order to DROP
+    // we emit the DROP statements first as normal but the creates have to be
+    // stashed in a pending buffer that accumulates in the reverse order.  When we're
+    // done with the group, then we emit the whole batch of creates in the natural order.
+    CHARBUF_OPEN(temp);
+    bindent(&temp, &make_table, 4);
+    bprintf(&temp, "%s", pending_table_creates.ptr);
+    bclear(&pending_table_creates);
+    bprintf(&pending_table_creates, "%s", temp.ptr);
+    CHARBUF_CLOSE(temp);

@@
     if (i + 1 < count && gname[0] && !Strcasecmp(gname, (note+1)->group_name)) {
       continue;
     }
+    bprintf(&update_tables, "%s", pending_table_creates.ptr);
+    bclear(&pending_table_creates);

@@
+  CHARBUF_CLOSE(pending_table_creates);
   CHARBUF_CLOSE(update_tables);
   CHARBUF_CLOSE(recreate);
```

Commit:
[`39551d179f77ce34c0a6678fa9e1a89ae14db156`](https://github.com/ricomariani/CG-SQL-author/commit/39551d179f77ce34c0a6678fa9e1a89ae14db156)

The group-boundary flush is important: it emits the accumulated creates only
after all members of that recreate group have been seen. This commit updated
generated golden references, but added no executed foreign-key regression.

In October 2022, recreate-group comparator direction required another fix:

```diff
 // Sort the @recreate annotations in place: the order is:
-//  * group name
+//  * group ordinal
 //  * ordinal reversed
 //
+//  We use create order for groups so that we do the CRC check for the
+//  strongest tables first - wherein we recursively drop children in
+//  drop order and also drop any tables in the correct drop order via
+//  the call to cql_rebuild_recreate_group. We also dirty the CRC for
+//  any children we end up dropping, so we want the children (weak tables) to
+//  follow after the parent (strong table) so that we recreate them.
@@
-  // reverse ordinal order
+  // We need group ordinal to be in create order so that we blow away
+  // strongest groups (groups that other groups depend on) first
   if (a1->group_ordinal != a2->group_ordinal) {
-    return (a1->group_ordinal < a2->group_ordinal) ? 1 : -1;
+    return (a1->group_ordinal < a2->group_ordinal) ? -1 : 1;
   }

   // It can't be a tie! ordinal is unique!
   Invariant(a1->ordinal != a2->ordinal);

+  // reverse ordinal
   return (a1->ordinal < a2->ordinal) ? 1 : -1;
```

Commit:
[`ddd4335d0cad57742814498d1ed5ebbb00e63627`](https://github.com/ricomariani/CG-SQL-author/commit/ddd4335d0cad57742814498d1ed5ebbb00e63627)

In February 2023, `@delete` table processing similarly needed reverse order:

```diff
   cql_object_ref deleteList =
     _cql_create_upgrader_input_statement_list(deletes, "DROP ");

   cql_code rc = SQLITE_OK;
   // Execute all delete table drops
-  for (cql_int32 i = 0;
-       i < cql_string_list_get_count(deleteList); i++) {
+  // Note deleteList provides table drops in create order, so we must execute them in reverse.
+  for (cql_int32 i = cql_string_list_get_count(deleteList); --i >= 0; ) {
     cql_string_ref delete = cql_string_list_get_string(deleteList, i);
     rc = cql_exec_internal(db, delete);
     if (rc != SQLITE_OK) goto cleanup;
   }
```

Commit:
[`3b597671509042abf95c568848efd05fbb0659be`](https://github.com/ricomariani/CG-SQL-author/commit/3b597671509042abf95c568848efd05fbb0659be)

The expanded C test fixture supplied parent/child tables and a create-ordered
delete list:

```diff
 cql_string_ref tables =
   cql_string_ref_new(
     " CREATE TABLE g1( id INTEGER PRIMARY KEY, name TEXT ); "
     "CREATE TABLE use_g1( id INTEGER PRIMARY KEY REFERENCES g1 (id), name2 TEXT); "
-    "CREATE TABLE foo(y text DEFAULT 'it''s, ('); ");
+    "CREATE TABLE foo(y text DEFAULT 'it''s, ('); "
+    "CREATE TABLE g2( id INTEGER PRIMARY KEY ); "
+    "CREATE TABLE use_g2( id INTEGER PRIMARY KEY REFERENCES g2 (id)); ");
 cql_string_ref indices =
   cql_string_ref_new("CREATE INDEX extra_index ON g1 (id); ");
-cql_string_ref deletes = cql_string_ref_new("DROP TABLE IF EXISTS g2; ");
+cql_string_ref deletes = cql_string_ref_new("DROP TABLE IF EXISTS g2; DROP TABLE IF EXISTS use_g2; ");
@@
 rc = cql_rebuild_recreate_group(db, tables, indices, deletes, &result);
 E(rc == SQLITE_OK, "expected succesful recreate group upgrade\n");
```

The commit did **not** complete the correction in Lua. It changed the Lua loop
to this:

```diff
-  for i = 1, #deleteList do
+  for i = 1, #deleteList, -1 do
```

Because the start is below the positive-length end while the step is negative,
that loop executes zero iterations. Commit
[`6f2c9498`](https://github.com/ricomariani/CG-SQL-author/commit/6f2c9498)
completed the backend correction:

```diff
-  for i = 1, #deleteList, -1 do
+  -- these are deleted or unsubscribed tables
+  -- note that tables in the list are in create order, so we reverse to get drop order
+  for i = #deleteList, 1, -1 do
     rc = cql_exec(db, deleteList[i])
     if rc ~= sqlite3.OK then return rc end
   end
```

So `3b597671` fixed C drop order and expanded the C fixture, while
introducing a zero-iteration Lua loop; `6f2c9498` completed the correction. The
fixture checks successful execution, but it does not independently prove the
drop order because the referenced tables are empty. This is a multi-backend
correction sequence: the drop-order failure is the operational bug, and the
Lua loop is an incomplete first fix in its correction chain, not a separately
reported field defect.

These are different bugs, but they point to the same weak spot. "Order" lived
implicitly in loops, comparators, and buffer accumulation instead of in named
order domains.

#### Identifier correctness was distributed

Quoted identifiers recur in schema and SQL-generation fixes. The October 2026
schema-drop correction touched all four dynamic emitters:

```diff
-  bprintf(decls, "  CALL cql_exec_internal(printf('DROP TABLE IF EXISTS [%%s]', table_name));\n");
+  // SQLite identifiers escape embedded double quotes by doubling them.
+  bprintf(decls, "  CALL cql_exec_internal(printf('DROP TABLE IF EXISTS \"%%s\"', replace(table_name, '\"', '\"\"')));\n");

@@
-    bprintf(output, "    CALL cql_exec_internal(printf('DROP TRIGGER [%%s];', C.name));\n");
+    bprintf(output, "    CALL cql_exec_internal(printf('DROP TRIGGER \"%%s\";', replace(C.name, '\"', '\"\"')));\n");

@@
-    bprintf(output, "    CALL cql_exec_internal(printf('DROP VIEW [%%s];', C.name));\n");
+    bprintf(output, "    CALL cql_exec_internal(printf('DROP VIEW \"%%s\";', replace(C.name, '\"', '\"\"')));\n");

@@
-    bprintf(output, "    CALL cql_exec_internal(printf('DROP INDEX [%%s];', C.name));\n");
+    bprintf(output, "    CALL cql_exec_internal(printf('DROP INDEX \"%%s\";', replace(C.name, '\"', '\"\"')));\n");
```

Commit:
[`8500516b9efa7f35e9406210600adb8efce4fb9a`](https://github.com/ricomariani/CG-SQL-author/commit/8500516b9efa7f35e9406210600adb8efce4fb9a)

The executable upgrade tests create names containing both `]` and `"`. They
exercise a targeted table-drop helper plus an unmanaged view, trigger, and
index discovered during exclusive upgrade, then verify the targeted objects
are gone and unrelated table data survived:

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
    call cql_exec_internal(printf('CREATE VIEW "%s" AS SELECT * FROM identifier_host',
      replace(view_name, '"', '""')));
    call cql_exec_internal(printf(
      'CREATE TRIGGER "%s" AFTER INSERT ON identifier_host BEGIN SELECT 1; END',
      replace(trigger_name, '"', '""')));
    call cql_exec_internal(printf('CREATE INDEX "%s" ON identifier_host(value)',
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

The table-drop helper is packaged in the C harness:

```c
static cql_code test_drop_quoted_tables(sqlite3 *db) {
  cql_object_ref saved_dictionary = test_tables_dict_;
  cql_object_retain(saved_dictionary);
  cql_set_created_object_ref(&test_tables_dict_, cql_string_dictionary_create());
  cql_code rc = verify_quoted_table_drops(db);

  cql_set_object_ref(&test_tables_dict_, saved_dictionary);
  cql_object_release(saved_dictionary);
  if (rc != SQLITE_OK) {
    fprintf(stderr, "Quoted table-drop helper regression failed: %s\n", sqlite3_errmsg(db));
  }
  return rc;
}
```

In `main`, only the unmanaged schema-object setup and verification are gated to
the relevant upgrade boundary:

```c
bool check_identifiers = proposed_version == 4 && current_version != 4;
if (check_identifiers && prepare_quoted_schema_objects(db) != SQLITE_OK) {
  fprintf(stderr, "Unable to prepare quoted schema objects.\n");
  return SQLITE_ERROR;
}

if (upgrade(db, should_use_virtual_tables)) {
  fprintf(stderr, "Unable to upgrade DB.\n");
  return SQLITE_ERROR;
}

if (check_identifiers && verify_quoted_schema_drops(db) != SQLITE_OK) {
  fprintf(stderr, "Quoted schema-drop regression failed.\n");
  return SQLITE_ERROR;
}
```

After the ordinary post-upgrade version and content checks, the same harness
invokes the table helper unconditionally:

```c
if (test_drop_quoted_tables(db) != SQLITE_OK) {
  return SQLITE_ERROR;
}
```

The lesson is simple:

> Static SQL generation and dynamic SQL construction must share one identifier
> model or one escaping primitive.

Subsystem tests can stop the exact bug from coming back while the same family
continues in another emitter.

#### Rewrites compose badly unless state and syntax are explicit

The December 2024 work on backed tables, upsert, and `RETURNING` found several
issues together:

- rowid reselection where it was not appropriate;
- a lost upsert `WHERE`;
- a missing ambiguity-avoiding `WHERE 1`;
- confusion between generated names and quoted user identifiers;
- nested rewrite state not restored correctly.

Commit:
[`cf546d7ed13edb2642abb75addcd6d5b48479c53`](https://github.com/ricomariani/CG-SQL-author/commit/cf546d7ed13edb2642abb75addcd6d5b48479c53)

Each rewrite makes sense on its own. Once combined, the tree carries the
obligations of all of them, and that cross-product is where the failure lived.

The correction was spread across the composing rewrites. The generated insert
adds SQLite's documented ambiguity breaker only for upsert:

```diff
              new_ast_select_where(
-                NULL,
+                  in_upsert ? new_ast_opt_where( new_ast_num(NUM_INT, "1")) : NULL,
                new_ast_select_groupby(
                  NULL,
                  new_ast_select_having(
                    NULL,
                    NULL
                  )
                )
              )
```

The backed-table update stops synthesizing rowid reselection during upsert and
preserves the upsert's own `WHERE`, rewriting its backed-column references:

```diff
-  ast_node *select_stmt = rewrite_select_rowid(
-     backed_table_name,
-     opt_where,
-     opt_orderby,
-     opt_limit);
+  ast_node *select_stmt;
+
+  if (!in_upsert) {
+
+    // this generates the normal where clause for the update statement
+    // WHERE rowid in (SELECT rowid FROM backed) which is what you want
+    // for the pdate case
+
+    select_stmt = rewrite_select_rowid(
+      backed_table_name,
+      opt_where,
+      opt_orderby,
+      opt_limit);
+
+    // for debugging print just the select statement
+    // gen_stmt_list_to_stdout(new_ast_stmt_list(select_stmt, NULL));
+
+    // the new where clause for the update statement is going to be something like
+    // rowid IN (select rowid from selected rows)
+  }
+  else {
+    // in the upsert case, the rows in question are already selected by SQLite itself.
+    // We don't need to do the rowid selection, we just need to rewrite the
+    // update list to use the backing table columns directly and we'll select
+    // the rowid out of excluded.rowid
+    select_stmt = NULL;
+  }
@@
-  ast_node *new_opt_where =
-    new_ast_opt_where(
-     new_ast_in_pred(
-       new_ast_str("rowid"),
-       select_stmt
-     )
-  );
+  ast_node *new_opt_where = NULL;
+
+  if (!in_upsert) {
+    new_opt_where = new_ast_opt_where(
+     new_ast_in_pred(
+       new_ast_str("rowid"),
+       select_stmt
+     )
+    );
+  }
+  else {
+    // the upsert case can have a WHERE clause of its own, it stays as is
+    new_opt_where = opt_where;
+
+    if (opt_where) {
+      AST_REWRITE_INFO_SAVE();
+      AST_REWRITE_INFO_SET(opt_where->lineno, opt_where->filename);
+      rewrite_backed_column_references_in_ast(opt_where, backed_table);
+      AST_REWRITE_INFO_RESET();
+      AST_REWRITE_INFO_RESTORE();
+    }
+  }
```

The nested rewrite now preserves any already-active rewrite context, and CTE
names use the normal quoted-name generator:

```diff
+  // this can be called from an existing rewrite in the upsert case, handle both cases
+  AST_REWRITE_INFO_SAVE();
   AST_REWRITE_INFO_SET(root->lineno, root->filename);
-
-  rewrite_blob_column_references(&info, root);
-
+    rewrite_blob_column_references(&info, root);
   AST_REWRITE_INFO_RESET();
+  AST_REWRITE_INFO_RESTORE();
```

```diff
-  EXTRACT_STRING(name, ast->left);
-  if (is_ast_star(ast->right)) {
-    // use the shorter syntax for (*) which is just the name
-    gen_printf("%s", name);
-  }
-  else {
-    gen_printf("%s (", name);
+  EXTRACT_ANY_NOTNULL(name_ast, ast->left);
+  gen_name(name_ast);
+  if (!is_ast_star(ast->right)) {
+    // skip this for foo(*), the shorter syntax is just the name
+    gen_printf(" (");
     gen_name_list(ast->right);
     gen_printf(")");
   }
```

The expanded runtime test proves that quoted backed-table names, insert/select,
delete, update, upsert, `WHERE`, and `RETURNING` compose into an executable
statement, then checks returned values and exhaustion:

```sql
proc make_jsonb_backed_schema()
begin
  [[backing_table]]
  [[jsonb]]
  create table `a backing table`(
    `the key` blob primary key,
    `the value` blob
  );
end;

[[backed_by=`a backing table`]]
create table `a table`(
  `col 1` int primary key,
  `col 2` int
);

TEST_MODERN_ONLY!(verify_returning,
begin
  make_jsonb_backed_schema();
    cursor C for
    with data(a, b) as (values
      (1, 1),
      (2, 4),
      (3, 9),
      (4, 16)
    )
    insert into `a table`(`col 1`, `col 2`)
      select * from data
      returning *;

    let i := 0;
    loop fetch C
    begin
      i += 1;
      EXPECT_EQ!(C.`col 1` * C.`col 1`, C.`col 2`);
    end;
    EXPECT_EQ!(i, 4);

    cursor D for
      delete from `a table` where `col 1` in (2, 3)
      returning *;

    fetch D;
    EXPECT_EQ!(D.`col 1`, 2);
    EXPECT_EQ!(D.`col 2`, 4);
    fetch D;
    EXPECT_EQ!(D.`col 1`, 3);
    EXPECT_EQ!(D.`col 2`, 9);
    fetch D;
    EXPECT!(not D);

    cursor E for select * from `a table`;
    i := 0;
    loop fetch E
    begin
      i += 1;
      EXPECT_EQ!(E.`col 1` * E.`col 1`, E.`col 2`);
    end;
    EXPECT_EQ!(i, 2);

    cursor F for
      update `a table` set `col 2` = `col 1` * 1000
      where `col 1` = 4
      returning *;

    fetch F;
    EXPECT_EQ!(F.`col 1`, 4);
    EXPECT_EQ!(F.`col 2`, 4000);
    fetch F;
    EXPECT!(not F);

    cursor G for
      insert into `a table`(`col 1`, `col 2`) values (1, 1), (5, 25)
      on conflict(`col 1`)
      do update set `col 2` = 1000 where `col 1` <= 4
      returning *;

    fetch G;
    EXPECT_EQ!(G.`col 1`, 1);
    EXPECT_EQ!(G.`col 2`, 1000);

    fetch G;
    EXPECT_EQ!(G.`col 1`, 5);
    EXPECT_EQ!(G.`col 2`, 25);
    fetch G;
    EXPECT!(not G);
end);
```

The production diff shows that the upsert `WHERE` is preserved and its
backed-column references are rewritten. This runtime case does not independently
exercise the predicate's false branch: the only conflicting key satisfies the
predicate, while key 5 is a non-conflicting insert.

#### How to think about the subsystem

From my chair, schema migration is a compiler inside the compiler. It has its
own:

- dependency graph;
- ordering semantics;
- identifier language;
- generated program;
- runtime execution behavior;
- compatibility rules across versions.

That is why the end-to-end upgrade tests matter more than the large golden
outputs. They execute the generated migration as a program instead of checking
only its text.

---

### 3. Global state works better than normal advice predicts

Conventional advice says to avoid global mutable state and pass explicit
contexts. CQL mostly keeps each compiler phase's state in globals.

My approximate current scan found:

- about 214 file-static state declarations;
- about 80 in `sem.c`;
- about 38 in `cg_c.c`;
- about 36 in `cg_lua.c`.

There are real advantages:

- recursive visitors have small signatures;
- current procedure, scope, callbacks, and output buffers are immediately
  available;
- code for one compiler phase stays together;
- the implementation avoids passing a very large context through thousands of
  calls.

The details matter: recursion almost never needs all of that state. Most nested
contexts save one or two symbol tables, a join scope, or a callback and output
buffer. For example:

```c
symtab *saved_locals = locals;
symtab *saved_globals = globals;

locals = globals = NULL;
PUSH_JOIN(expr_scope, jptr);
sem_root_expr(expr, SEM_EXPR_CONTEXT_CONSTRAINT);
POP_JOIN();

locals = saved_locals;
globals = saved_globals;
```

The generic SQL generator state is a complete three-pointer abstraction with
paired save and restore operations:

```c
typedef struct gen_sql_state {
  charbuf *_Nullable gen_output;
  gen_sql_callbacks *_Nullable gen_callbacks;
  symtab *_Nullable used_alias_syms;
} gen_sql_state;

cql_noexport void gen_get_state(gen_sql_state *state) {
  state->gen_output = gen_output;
  state->gen_callbacks = gen_callbacks;
  state->used_alias_syms = used_alias_syms;
}

cql_noexport void gen_set_state(gen_sql_state *state) {
  gen_output = state->gen_output;
  gen_callbacks = state->gen_callbacks;
  used_alias_syms = state->used_alias_syms;
}
```

That is the normal shape. The shared-fragment case below is exceptional: it
re-enters SQL generation while fragment predicates, variable numbering, and
fragment buffers are all in flight.

#### Nested code generation exposed the cost

In March 2025, evaluating a shared-fragment argument containing a nested
`SELECT` re-entered SQL generation and clobbered outer generator state.

The code had already documented exactly what remained to be done:

```c
// todo: if the evaluation has a nested select statement then we will have
// to re-enter all of this.  We can either ban that (which isn't insane
// really) or else we can save the codegen state like callbacks and such so
// that it can re-enter.  That's the desired path.
```

The save/restore work in the comment had not been implemented. The fix did
exactly that:

```c
gen_sql_state state;
gen_get_state(&state);

bytebuf sfs_saved;
memcpy(&sfs_saved, &shared_fragment_strings, sizeof(bytebuf));
memset(&shared_fragment_strings, 0, sizeof(bytebuf));

int cur_fragment_predicate_saved = cur_fragment_predicate;
int max_fragment_predicate_saved = max_fragment_predicate;
int prev_variable_count_saved = prev_variable_count;
int cur_variable_count_saved = cur_variable_count;
bool_t has_conditional_fragments_saved = has_conditional_fragments;
bool_t has_shared_fragments_saved = has_shared_fragments;
bool_t has_variables_saved = has_variables;

CG_PUSH_EVAL(expr, C_EXPR_PRI_ASSIGN);
cg_store(cg_main_output, alias_name, sem_type_var, sem_type_expr, expr_is_null.ptr, expr_value.ptr);
CG_POP_EVAL(expr);

gen_set_state(&state);
memcpy(&shared_fragment_strings, &sfs_saved, sizeof(bytebuf));
cur_fragment_predicate = cur_fragment_predicate_saved;
max_fragment_predicate = max_fragment_predicate_saved;
prev_variable_count = prev_variable_count_saved;
cur_variable_count = cur_variable_count_saved;
has_conditional_fragments = has_conditional_fragments_saved;
has_shared_fragments = has_shared_fragments_saved;
has_variables = has_variables_saved;
```

Commit:
[`7dadf83af8d84f3d5d7450769e5520b80efb65cf`](https://github.com/ricomariani/CG-SQL-author/commit/7dadf83af8d84f3d5d7450769e5520b80efb65cf)

The Lua backend received the corresponding state boundary around its actual
nested evaluation:

```c
gen_sql_state state;
gen_get_state(&state);
bytebuf sfs_saved;
memcpy(&sfs_saved, &lua_shared_fragment_strings, sizeof(bytebuf));
memset(&lua_shared_fragment_strings, 0, sizeof(bytebuf));

int cur_fragment_predicate_saved = lua_cur_fragment_predicate;
int max_fragment_predicate_saved = lua_max_fragment_predicate;
int prev_variable_count_saved = lua_prev_variable_count;
int cur_variable_count_saved = lua_cur_variable_count;
bool_t has_conditional_fragments_saved = lua_has_conditional_fragments;
bool_t has_shared_fragments_saved = lua_has_shared_fragments;
bool_t has_variables_saved = lua_has_variables;

CG_LUA_PUSH_EVAL(expr, LUA_EXPR_PRI_ASSIGN);
cg_lua_store(cg_main_output, alias_name, sem_type_var, sem_type_expr, expr_value.ptr);
CG_LUA_POP_EVAL(expr);

lua_cur_variable_count = cur_variable_count_saved;
lua_prev_variable_count = prev_variable_count_saved;
lua_cur_fragment_predicate = cur_fragment_predicate_saved;
lua_max_fragment_predicate = max_fragment_predicate_saved;
lua_has_conditional_fragments = has_conditional_fragments_saved;
lua_has_shared_fragments = has_shared_fragments_saved;
lua_has_variables = has_variables_saved;

gen_set_state(&state);
memcpy(&lua_shared_fragment_strings, &sfs_saved, sizeof(bytebuf));
```

The list is longer here because nested shared-fragment arguments can themselves
contain shared fragments. This path has more live recursive context than the
usual one or two symbol tables.

A helper dedicated to pushing and popping this shared-fragment generation
context would be cleaner, and the manual C/Lua copies are maintenance debt. I
never got around to making that helper. Still, this commit is better read as an
unfinished, already-documented re-entry requirement than as evidence that all
compiler global state needs to be snapshotted. The commit added unrelated
`Dirname` coverage, but no focused regression source for nested shared-fragment
argument evaluation.

#### Repeated compiler invocation has an unusually strong regression test

The amalgam test calls `cql_main` several times in one process:

```c
const char *cql_success_file = (char *) argv[1];
const char *cql_semantic_error_file = (char *) argv[2];
const char *cql_syntax_error_file = (char *) argv[3];

const char *args_1[5] = {"cql", "--in", cql_success_file, "--sem", "--echo"};
if (cql_main(5, (char **)args_1) != 0) {
  fprintf(stderr, "%s reported an error: this is unexpected\n", cql_success_file);
  exit(1);
}

const char *args_2[5] = {"cql", "--in", cql_semantic_error_file, "--sem", "--echo"};
if (cql_main(5, (char **)args_2) == 0) {
  fprintf(stderr, "%s did not reported an error: this is unexpected\n", cql_semantic_error_file);
  exit(1);
}

const char *args_3[5] = {"cql", "--in", cql_syntax_error_file, "--sem", "--echo"};
if (cql_main(5, (char **)args_3) == 0) {
  fprintf(stderr, "%s did not reported an error: this is unexpected\n", cql_syntax_error_file);
  exit(1);
}

if (cql_main(5, (char **)args_1) != 0) {
  fprintf(stderr, "%s reported an error: this is unexpected\n", cql_success_file);
  exit(1);
}
```

Source: `sources/test/amalgam_test.c`

I like this better than a cleanup unit test. It verifies observable reentrancy
after both semantic and syntax failure, which directly exercises the risk
created by phase globals.

#### The global-state design is deliberate

Phase globals come with explicit cleanup entry points. For example, C generator
initialization calls cleanup before rebuilding dispatch and state, and compiler
orchestration cleans every phase before returning.

```c
cql_noexport void cg_c_init(void) {
  cg_c_cleanup(); // reset globals/statics
  cg_common_init();

  Contract(!error_target_used);

  // one table for the whole translation unit
  Contract(!string_literals);
  string_literals = symtab_new_case_sens();
```

```c
cg_c_cleanup();
sem_cleanup();
ast_cleanup();
gen_cleanup();
rt_cleanup();
parse_cleanup();
cql_cleanup_open_includes();
cql_cleanup_defines();

#ifdef CQL_AMALGAM
  // the variables need to be set back to zero so we can
  // be called again as though we were just loaded
  cql_reset_globals();
#endif
```

I read the history this way: top-level reset works, ordinary recursion saves
little context, and shared-fragment generation is the exceptional wide
re-entry case that still wants a focused helper.

---

### 4. Ownership helpers and bulk lifetimes are CQL's strongest C-level design

C usually gives you leaks, use-after-free, double-free, dangling pointers,
aliasing errors, buffer overruns, integer overflow, and undefined behavior from
alignment or effective-type violations.

CQL removes much of the ordinary ownership burden by dividing memory into a few
strong lifetime classes.

#### AST and durable compiler data use arenas

The minipool is intentionally simple. The exact excerpts below omit the
remainder of the introductory commentary and `minipool_open`, which eagerly
initializes the first block:

```c
// This is the stupidest pool allocator ever, it's only useful for cases where
// everything lives until the end.  Currently it's used to hold ast nodes and
// duplicated strings.

cql_noexport void minipool_close(minipool **head) {
  minipool *pool = *head;
  while (pool) {
    minipool *next = pool->next;
    free(pool->bytes);
    free(pool);
    pool = next;
  }
  *head = NULL;
}

// Get needed memory; if the memory is not available then we allocate a new
// block and thread it into the list.  Note that this is different than the
// other CQL helper bytebuf. This allocation never moves bytes or copies bytes.
// Once you get memory it is valid until you close the buffer. Bytebuf cannot
// hold pointers because the structure moves when it grows and it is one
// continuous allocation so it's only for byte streams. Minipool doesn't move
// objects around so pointers remain valid.
cql_noexport void *minipool_alloc(minipool *pool, uint32_t needed) {
  void *result;

  // for alignment, all allocs will be on a 8 byte boundary
  needed += 7;
  needed &= u32_not(7);

  if (needed > pool->available) {
    // Make a copy of the most recent head node and link to it we have to do
    // this because the head of the pool never changes once it's created.  Note
    // that none of the byte buffers are copied, only the minipool struct.  Once
    // we've copied it, we re-initialize the minipool to a size that is at least
    // big enough for the next allocation.
    minipool *old = malloc(sizeof(minipool));
    *old = *pool;
    uint32_t blocksize = MAX(needed, MINIBLOCK);
    pool->bytes = malloc(blocksize);
    pool->current = pool->bytes;
    pool->available = blocksize;
    pool->next = old;
  }

  result = pool->current;
  pool->current += needed;
  pool->available -= needed;
  return result;
}
```

The key property is in the comment: allocations never move and remain valid
until the whole pool closes. Compiler ASTs naturally live for the compilation,
so individual `free` calls would add risk with very little useful memory
recovery.

That runs directly against generic "free each allocation promptly" advice. For
this workload, I think the bulk lifetime is the better engineering choice.

#### Reference ownership needed type-specific operations

In November 2024, generated code released a destination reference before
evaluating a create call. That was wrong when the old destination value was
also an argument to the call:

```c
static void cg_copy_for_create(charbuf *output, CSTR var, sem_t sem_type_var, CSTR value) {
   if (is_text(sem_type_var)) {
     bprintf(cg_main_output, "%s(%s);\n", rt->cql_string_release, var);
   }
   else if (is_blob(sem_type_var)) {
     bprintf(output, "%s(%s);\n", rt->cql_blob_release, var);
   }
   else if (is_object(sem_type_var)) {
     bprintf(output, "%s(%s);\n", rt->cql_object_release, var);
   }
   bprintf(output, "%s = %s;\n", var, value);
}
```

The fix introduced explicit setters for incoming `+1` references:

```c
void cql_set_created_object_ref(
  cql_object_ref _Nullable *_Nonnull target,
  cql_object_ref _Nullable source)
{
  // no upcount, we were given an upcounted ref. We just release what we had and store
  cql_object_release(*target);
  *target = source;
}
```

The executable aliasing case removed its temporary workaround and passes the
destination directly as an argument to the create function:

```diff
-let b_temp := my_blob; -- avoid bug in cg_copy_for_create
-my_blob := corrupt_blob_with_invalid_shenanigans(b_temp);
+my_blob := corrupt_blob_with_invalid_shenanigans(my_blob);
```

The generator now emits the type-specific created-reference operations:

```c
if (is_text(sem_type_var)) {
  bprintf(output, "cql_set_created_string_ref(%s%s, %s);\n", prefix, var, value);
}
else if (is_blob(sem_type_var)) {
  bprintf(output, "cql_set_created_blob_ref(%s%s, %s);\n", prefix, var, value);
}
else if (is_object(sem_type_var)) {
  bprintf(output, "cql_set_created_object_ref(%s%s, %s);\n", prefix, var, value);
}
```

Selected exact cases from separate locations in `cg_test.sql` cover object,
blob, string, and boxing paths:

```sql
-- + cql_set_created_object_ref(&obj_var, obj_func_create());
set obj_var := obj_func_create();

-- + cql_set_created_blob_ref(&blob_var, blob_func_create());
set blob_var := blob_func_create();

-- + cql_set_created_string_ref(&s, cql_cursor_format(&C_dyn));
PROC BigFormat ()
BEGIN
  DECLARE C CURSOR FOR SELECT * FROM big_data;
  LOOP FETCH C
  BEGIN
    LET s := cql_cursor_format(C);
  END;
END;

-- + cql_set_created_object_ref(&C_object_, cql_box_stmt(C_stmt));
-- + cql_set_object_ref(&box, C_object_);
proc call_in_loop_boxed()
begin
  declare i int;
  set i := 0;
  while i < 5
  begin
    set i := i + 1;
    declare C cursor for call simple_select();
    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;
    fetch D;
  end;
end;
```

Commit:
[`0001945b26ad1b50b80f439ce57f2b9fbe89f523`](https://github.com/ricomariani/CG-SQL-author/commit/0001945b26ad1b50b80f439ce57f2b9fbe89f523)

I much prefer this to merely reordering the release. The helper name encodes
the ownership contract and reduces the legal spellings of a subtle operation.

#### Net reference balancing is checked for every runtime test

The runtime `TEST!` macro records outstanding references around each test:

```sql
start_refs := get_outstanding_refs();
@id("test_", name!)();
end_refs := get_outstanding_refs();

if start_refs != end_refs then
  printf("Test %s unbalanced refs.", @text(name!));
  printf("  Starting refs %d, ending refs %d.\n", start_refs, end_refs);
  fails := fails + 1;
end if;
```

Source: `sources/test/run_test.sql`

This is a powerful general invariant. It catches net leaks regardless of the
feature a test was written to exercise. FWIW, the limit is just as clear:
balanced counts cannot prove correct ordering, absence of temporary
use-after-release, or correct ownership transfer. The created-reference bug
survived until the abstraction itself got stronger.

#### Why this design holds up

CQL's best C mitigations reduce the number of lifetimes a programmer has to
reason about:

- AST objects: compilation arena lifetime.
- Interned strings: durable shared lifetime.
- output buffers: lexical open/close lifetime.
- generated runtime references: retain/release helper protocol.
- created runtime references: distinct `set_created` protocol.

The remaining ownership bugs tend to appear at a crossing between lifetime
classes, or when code spells out the protocol by hand.

---

### 5. Late audit hardening exposed hidden representation assumptions

I weight this section differently from the older history. It is
disproportionately made up of late-2026 AI-assisted audit work. Several changes
strengthened an invariant that no known production caller violated.

These changes make the code better. They expose low-level preconditions that
had been implicit. They do not show that buffers were routinely failing in
operation.

#### `bytebuf` self-append was a prophylactic invariant change

In October 2026, `bytebuf_append` was changed to support a source range inside
the same buffer even when growth moves the allocation:

```diff
+ uint32_t offset = 0;
+ bool_t aliases_buffer = false;
+
+ if (buf->ptr) {
+   uintptr_t source = (uintptr_t)bytes;
+   uintptr_t start = (uintptr_t)buf->ptr;
+   if (source >= start && source - start < buf->used) {
+     offset = (uint32_t)(source - start);
+     aliases_buffer = true;
+   }
+ }
+
  void *mem = bytebuf_alloc(buf, count);
- memcpy(mem, bytes, count);
+ if (aliases_buffer) {
+   bytes = buf->ptr + offset;
+ }
+ memmove(mem, bytes, count);
```

Commit:
[`25f48ef5985a15b805f2dda66347c7c33bb71ef9`](https://github.com/ricomariani/CG-SQL-author/commit/25f48ef5985a15b805f2dda66347c7c33bb71ef9)

The regression test forces growth and then tests both whole-buffer and
interior-slice aliasing:

```c
static bool test_bytebuf_self_append() {
bytebuf buffer;
bytebuf_open(&buffer);

// Duplicating this seed forces growth while the source aliases the buffer.
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

It is registered in `run_unit_tests` with the literal assertion
`TEST_ASSERT(test_bytebuf_self_append());`.

I searched the repository and checked what I know about the call sites. I found
no known caller appending an overlapping range. The shown code does not
establish that negative-history claim; the test constructs the case
deliberately. I would call this an invariant test rather than a regression for
an observed compiler failure.

The old helper had an unenforced assumption: source storage would not be
invalidated by destination growth. The new helper removes that assumption and
defines self-append as supported behavior. That is good prophylactic work.

#### `bprintf` format aliasing was prohibited explicitly

The same audit added an always-on contract to `vbprintf`:

```c
uintptr_t source = (uintptr_t)format;
uintptr_t start = (uintptr_t)b->ptr;
Contract(source < start || source - start >= b->max);
```

Commit:
[`14b0eaa75cba729abe3e16bacbbca417990a6c13`](https://github.com/ricomariani/CG-SQL-author/commit/14b0eaa75cba729abe3e16bacbbca417990a6c13)

I found no call where the dynamic format string lives inside the destination
allocation. The snippet itself proves only the new precondition. The contract
prevents a future caller from depending on storage that can move during
formatting. The commit added no test. Righteous fix, hidden assumption, no
observed bug.

#### Unsigned loop bounds make empty input special

Another audit fix changed:

```diff
- for (uint32_t i = 0; i < b->used - 2; i++) {
+ for (uint32_t i = 0; i + 2 < b->used; i++) {
```

Commit:
[`89f2879b74b3dff61fd40afccad8f9ccc6a11fd3`](https://github.com/ricomariani/CG-SQL-author/commit/89f2879b74b3dff61fd40afccad8f9ccc6a11fd3)

The original arithmetic looks natural when read locally, but it underflows for
short buffers. The repaired form says what the code actually needs: three
positions must fit. This was boundary hardening found by inspection, not
evidence that empty comment buffers had caused field failures.

The complete table-driven test starts with a truly empty buffer, then covers
one-character, two-character, and ordinary inputs while checking that the
logical buffer length is unchanged:

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

It is registered in `run_unit_tests` with
`TEST_ASSERT(test_comment_marker_scan());`.

#### Serialized blobs need whole-shape validation

The backed-blob and blob-stream fixes form a recognizable family:

- canonical field ordering;
- offset-table off-by-one errors;
- incomplete stored-field validation;
- confusion between physical trailing bytes and logical field lengths;
- arithmetic performed before validating the entire offset table.

The October 2026 blob-stream audit moved toward a better pattern. The complete
read path proves the table shape, validates both ends of the selected range,
and clears any existing cursor row on rejection:

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

  // the first 4 bytes are the count of blobs
  // note that we're assuming little endian here, this could be generalized
  uint32_t count;
  memcpy(&count, bytes, sizeof(count));

  // Prove the entire count/offset table fits before any count or index arithmetic.
  if (count > len / sizeof(uint32_t) - 1) {
    goto error;
  }

  if (index < 0 || (uint32_t)index >= count) {
    goto error;
  }

  // note that we're assuming little endian here, this could be generalized
  uint32_t end;
  memcpy(&end, bytes + ((uint32_t)index + 1) * sizeof(end), sizeof(end));
  if (end > len) {
    goto error;
  }

  // the first blob starts after the offsets and count
  uint32_t table_end = (count + 1) * sizeof(uint32_t);
  uint32_t start = table_end;

  if (index > 0) {
    // Subsequent blobs start at the preceding exclusive end.
    // note that we're assuming little endian here, this could be generalized
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

Commit:
[`957db34adb4337afb4498d9feabea7cdb4f9036a`](https://github.com/ricomariani/CG-SQL-author/commit/957db34adb4337afb4498d9feabea7cdb4f9036a)

The regression table covers huge counts, arithmetic-overflow indices, zero
count, an offset inside the table, and negative and high indices. Before every
attempt it seeds a row containing a string reference; every rejection must
clear both the cursor and `C.z`:

```sql
TEST!(blob_stream_table_bounds__,
begin
  let control := control_blob();
  cursor cases for
    -- Four-byte little-endian count INT32_MAX (2,147,483,647), with no
    -- offsets or payload. Index INT32_MAX-1 overflowed the old index+2.
    select x'FFFFFF7F' as b, 2147483646 as idx
    union all
    -- Four-byte count 536,870,912, no offsets or payload. Index 536,870,910
    -- made the old (index+2)*4 overflow signed INT32 despite this tiny input.
    select x'00000020' as b, 536870910 as idx
    union all
    -- Four-byte unsigned count UINT32_MAX, no offsets or payload.
    -- The old (count+1)*4 wrapped to zero; the full table cannot fit.
    select x'FFFFFFFF' as b, 0 as idx
    union all
    -- Four-byte count zero: a complete empty stream, with no row 0.
    select x'00000000' as b, 0 as idx
    union all
    -- 23-byte stream: count 2 at 0..3, ends 8 and 23 at 4..11.
    -- Bytes 12..22 encode my_blob (0,0,"z_0"): "iis\0", presence bits 07,
    -- zigzag integers 00,00, then "z_0\0". For index 1, start 8 is inside
    -- the 12-byte table; it must not be treated as serialized row data.
    select x'020000000800000017000000696973000700007A5F3000' as b, 1 as idx
    union all
    -- Complete valid five-row control stream; only the indices are invalid.
    select control as b, -1 as idx
    union all
    select control as b, 5 as idx;

  cursor C like my_blob;
  loop fetch cases
  begin
    fetch C() from values () @dummy_seed(42) @dummy_nullables;
    let hit := false;
    try
      cql_cursor_from_blob_stream(C, cases.b, cases.idx);
    catch
      EXPECT_EQ!(@rc, 1); -- SQLITE_ERROR
      hit := true;
    end;
    EXPECT_EQ!(hit, true);
    EXPECT_EQ!(C, false);
    EXPECT_EQ!(C.z, null);
  end;
end);
```

Two things improve at once:

1. `memcpy` avoids alignment and aliasing assumptions.
2. The complete table shape is established before offsets are trusted.

The validation got better here: early checks made the next read safe; later
checks prove the whole shape before trusting offsets. These malformed-input
checks are defensive hardening unless there is a corrupt persisted blob or an
external caller supplying one; they should not be counted automatically as
observed compiler failures.

#### Platform width assumptions appeared at the lexer boundary

The earliest public-history example is a November 2020 fix for systems where
`long` is 32 bits:

```diff
-0x[0-9a-fA-F]+               { char *s = Strdup(yytext); yylval.sval = s; return strtol(s+2, NULL, 16) <= 0x7fffffff ? INTLIT: LONGLIT; }
+0x[0-9a-fA-F]+               { char *s = Strdup(yytext); yylval.sval = s; return strtoll(s+2, NULL, 16) <= 0x7fffffff ? INTLIT: LONGLIT; }
 0x[0-9a-fA-F]+L              { char *s = Strdup(yytext); s[strlen(s)-1] = 0; /* remove the L */ yylval.sval = s; return LONGLIT; }
-[0-9]+                       { char *s = Strdup(yytext); yylval.sval = s; return atol(s) <= 0x7fffffff ? INTLIT: LONGLIT; }
+[0-9]+                       { char *s = Strdup(yytext); yylval.sval = s; return atoll(s) <= 0x7fffffff ? INTLIT: LONGLIT; }
 [0-9]+L                      { char *s = Strdup(yytext); s[strlen(s)-1] = 0; /* remove the L */ yylval.sval = s; return LONGLIT; }
```

Commit:
[`36e3e3a7880407509205158c1a632a21f9840dac`](https://github.com/ricomariani/CG-SQL-author/commit/36e3e3a7880407509205158c1a632a21f9840dac)

This is ordinary C portability trouble in a compiler-specific location:
literal classification. A host-width assumption changed the accepted source
language. The commit added no regression test, so the portability effect is
supported by the lexer threshold logic and commit intent rather than an
executed cross-platform case.

---

### 6. Lexer and parser bugs were fewer, but boundary-sensitive

The lexer and parser account for fewer conservative candidates than semantics,
runtime, or code generation. The fixes that do show up usually involve:

- token adjacency;
- escape handling;
- host integer width;
- recursion direction and parser stack use;
- the difference between language errors and internal contracts.

#### Keyword recognition consumed an identifier prefix

In January 2021:

```diff
- ELSE[ \t\n]IF
+ ELSE[ \t]+IF/[^A-Z_0-9]
```

Commit:
[`fa6522e3ada6be01612f527315fe62b63c7d9050`](https://github.com/ricomariani/CG-SQL-author/commit/fa6522e3ada6be01612f527315fe62b63c7d9050)

The old rule could tokenize `ELSE IFNULL(...)` as `ELSE_IF`. The regression test
is admirably small:

```sql
-- TEST: ensure that ifnull parses properly after else, it's not "else if"
-- + ELSE ifnull(x, y)
select case when 1 then 2 else ifnull(x, y) end;
```

This is where lexical bugs like to hide: at the boundary between a keyword
phrase and a longer identifier.

#### Grammar direction was a resource-use property

In July 2021, statement lists changed from right recursion to left recursion to
avoid exhausting the Bison stack on very large procedures:

```diff
-  stmt ';'  { $result = new_ast_stmt_list($stmt, NULL); $result->lineno = $stmt->lineno;}
-  | stmt ';' stmt_list[slist]  { $result = new_ast_stmt_list($stmt, $slist); $result->lineno = $stmt->lineno; }
+  stmt ';'  {
+     // We're going to do this cheesy thing with the stmt_list structures so that we can
+     // code the stmt_list rules using left recursion.  We're doing this because it's
+     // possible that there could be a LOT of statements and this minimizes the use
+     // of the bison stack because reductions happen sooner with this pattern.  It does
+     // mean we have to do some weird stuff because we need to build the list so that the
+     // tail is on the right.  To accomplish this we take advantage of the fact that the
+     // parent pointer of the statement list is meaningless while it is unrooted.  It
+     // would always be null.  We store the tail of the statement list there so we know
+     // where to add new nodes on the right.  When the statement list is put into the tree
+     // the parent node is set as usual so nobody will know we did this and we don't
+     // have to add anything to the node for this one case.
+     //
+     // With this done we can handle several thousand statements without using much stack space.
+     $result = new_ast_stmt_list($stmt, NULL);
+     $result->lineno = $stmt->lineno;
+
+     // set up the tail pointer invariant to use later
+     $result->parent = $result;
+     }
+  | stmt_list[slist] stmt ';'  {
+     ast_node *new_stmt = new_ast_stmt_list($stmt, NULL);
+     new_stmt->lineno = $stmt->lineno;
+
+     // use our tail pointer invariant so we can add at the tail without searching
+     ast_node *tail = $slist->parent;
+     ast_set_right(tail, new_stmt);
+
+     // re-establish the tail invariant per the above
+     $slist->parent = new_stmt;
+     $result = $slist;
+     }
```

Commit:
[`1c95bbdb8e20dbf6a02e479245dce03dbde95fd9`](https://github.com/ricomariani/CG-SQL-author/commit/1c95bbdb8e20dbf6a02e479245dce03dbde95fd9)

A conventional representation review might object because the field
temporarily changes meaning. Here the invariant is local to parser
construction, documented in detail, and erased when the list is rooted. Given
the existing AST shape, I think that is a sound engineering trade. The commit
updated grammar documentation but added no checked-in large-procedure stress
regression; the stack-use claim rests on the recursion direction and commit
rationale.

#### Parentheses require associativity, not only precedence

In November 2020, C generation checked only whether a child operator had weaker
precedence. Equal-precedence right children of left-associative operators also
needed parentheses:

```c
// This tells us if a subtree should be wrapped in ()
// Basically we know the binding strength of the context (pri) and the current element (pri_new)
// Weaker contexts get parens.  Equal contexts get parens on the right side because all ops
// are left to right associtive in SQL. Stronger child contexts never need parens because
// the operator already binds tighter than its parent in the tree.
static bool_t needs_paren(ast_node *ast, int32_t pri_new, int32_t pri) {
  if (pri_new != pri) {
    return pri_new < pri;
  }

  return ast->parent->right == ast;
}
```

Commit:
[`47e78dd5e6a56c501b694030e0a15e92027be2fe`](https://github.com/ricomariani/CG-SQL-author/commit/47e78dd5e6a56c501b694030e0a15e92027be2fe)

The helper replaced precedence-only checks at the actual emission point:

```diff
-if (pri_new < pri) {
+if (needs_paren(ast, pri_new, pri)) {
   bprintf(value, "(%s)", result.ptr);
 }
 else {
   bprintf(value, "%s", result.ptr);
 }
```

Paired tests distinguish equal-precedence left trees from right trees:

```sql
-- + x = 1 * (2 / 3);
SET x := 1 * (2 / 3);

-- + x = 1 * 2 / 3;
SET x := 1 * 2 / 3;

-- + x = 1 - 2 - (2 - 3);
SET x := 1 - 2 - (2 - 3);

-- + x = 1 / 2 / 3;
SET x := 1 / 2 / 3;

-- + x = 1 / (2 / 3);
SET x := 1 / (2 / 3);
```

This is a standard tree-to-text failure. The operator set survives, but the
original tree does not, because precedence alone is an incomplete printing
rule.

---

### 7. The tests are unusually layered; independence matters more than volume

The current corpus is large:

| Measure | Current count |
|---|---:|
| Files under `sources/test` | 151 |
| SQL test files | 57 |
| Golden `.ref` files | 82 |
| SQL test lines | 48,465 |
| Golden-output lines | 227,046 |
| `-- TEST:` labels | 4,191 |
| Positive `-- +...` directives | 15,415 |
| Negative `-- -...` directives | 1,702 |
| Named shell test cases | 132 |
| Golden diff operations in `test.sh` | 81 |

I also found that production fixes usually get tests:

- 1,089 of 2,266 public-ref commits touched test assets.
- 975 touched both production and test code.
- 106 bug-like commits touched both.
- 101 of those 106 added test lines.

The count is useful context. What matters more is that CQL uses several
different kinds of oracle.

#### Layer 1: directive-level semantic expectations

`cql-verify` supports ordered positive matches, negative matches, exact counts,
exactly-one checks, and same-line checks:

```text
-- match and advance the current match pointer
-- + foo       --> match foo, searching forward from the last match with +

-- these forms do not change the current search position
-- +[0-9] foo  --> match foo anywhere, but demand exactly n matches
-- - foo       --> shorthand for +0 foo (demand no matches)
-- * foo       --> shorthand for +1 foo (demand 1 match, anywhere)
-- = foo       --> match foo on the same line as the last match with +
```

This fits semantic analysis well because one compiler invocation can continue
after errors and validate thousands of decorated AST fragments.

#### Layer 2: whole-output goldens

Golden files detect broad collateral changes. The harness normalizes unstable
line numbers. In non-interactive runs it fails rather than blessing a diff; in
an interactive run it copies output only after explicit confirmation:

```sh
if [ "${NON_INTERACTIVE:-0}" == 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "When running: diff $*"
  echo "The above differences were detected. If these are expected copy the test output to the reference."
  echo "You can also re-run the tests without specifying --non_interactive to affirm the updates."
  echo "Don't just accept the changes to make the error go away; you have to really understand the diff first!"
  echo " "
  failed
else
  read -rp "When running: diff $*
The above differences were detected. Is this expected?
Don't just accept to make the error go away; you have to really understand the diff first! (y/N) " ANS
  case $ANS in
  [Yy]*) cp "$2" "$1" 2>/dev/null ;;
  *)
    echo " "
    failed
    ;;
  esac
fi
```

Source: `sources/common/test_helpers.sh`

That social safeguard matters. Golden tests make it very easy to bless a
self-consistent but incorrect new world.

#### Layer 3: generated-code compilation

The suite also compiles and runs the generated C code. Generated test-helper
CQL is semantically analyzed, converted to C, compiled, and executed. That
compositional path is one of the suite's strongest features.
The exact command/run pairs below omit only each case's `TEST_NAME` and
`TEST_DESC` metadata:

```sh
TEST_CMD="${CQL} --sem --ast --in \"$O/cg_test_test_helpers.out\""
run_test_expect_success

TEST_CMD="${CQL} --test --dev --cg \"$O/test_helpers.h\" \"$O/test_helpers.c\" --in \"$O/cg_test_test_helpers.out\""
run_test_expect_success

TEST_CMD="do_make test_helpers_test"
run_test_expect_success

TEST_CMD="./$O/test_helpers_test"
run_test_expect_success
```

#### Layer 4: runtime execution

The runtime framework evaluates operands once, reports both sides on failure,
and checks reference balance:

```sql
let @tmp(a) := a!;
let @tmp(b) := b!;
expected := @tmp(a) IS @tmp(b);
error_check(expected, @text(a!, " == ", b!), @MACRO_LINE);
if not expected then
  printf("left: %s\n", @tmp(a):fmt);
  printf("right: %s\n", @tmp(b):fmt);
end if;
```

#### Layer 5: differential or external oracles

`EXPECT_SQL_TOO!` evaluates the same expression in generated CQL code and
inside SQLite:

```sql
@MACRO(stmt_list) EXPECT_SQL_TOO!(pred! expr)
begin
  pred!:EXPECT!;
  (select pred!):EXPECT!;
end;
```

This is stronger than another expected-output file because SQLite independently
evaluates the same expression.

The same `run_test.sql` serialization case runs through both backends and
compares its bytes with one fixed hexadecimal result:

```sql
let b := ext_cursor:to_blob;

let actual_hex := hex(b);
let expected_hex :=
   "66696C64736266696C64736246494C44534266696C64736200C00F090280D0AC"
   "F30E0000000000000A406120737472696E670014666972737420626C6F62E807"
   "8080A2A9EAE801000000000080234061207365636F6E6420737472696E670016"
   "7365636F6E6420626C6F62616E20756E7573656420737472696E6700";

-- this is true on all platforms!
EXPECT_EQ!(actual_hex, expected_hex);
```

The Lua harness compiles and executes that same source:

```sh
out/cql --in test/run_test.sql --cg out/run_test_core.lua --rt lua --global_proc go
cat lua_demo/test_helpers.lua out/run_test_core.lua >out/run_test.lua
echo "go(sqlite3.open_memory())" >>out/run_test.lua
lua out/run_test.lua | tee out/run_test_lua.out
```

The C harness separately builds and runs against the system SQLite link and a
checked-in modern SQLite:

```sh
do_make run_test
MAKE_ARGS_SAVED=${MAKE_ARGS}
MAKE_ARGS=$(echo SQLITE_PATH=./sqlite ${MAKE_ARGS})
do_make sqlite
do_make run_test_modern
MAKE_ARGS=${MAKE_ARGS_SAVED}

TEST_CMD="./$O/run_test"
run_test_expect_success

TEST_CMD="./$O/run_test_modern"
run_test_expect_success
```

#### The canonical self-consistent failure

In December 2024, CQL consistently emitted invalid SQLite
`RETURNING (x,y,z)` syntax. Parser, semantic, C, Lua, JSON, and golden outputs
all agreed with one another because they shared the same mistaken model.
Execution against SQLite exposed it.

Commit:
[`3163e93e7f01`](https://github.com/ricomariani/CG-SQL-author/commit/3163e93e7f01)

The grammar and all four DML emitters removed the invented parentheses:

```diff
-returning_suffix: RETURNING '(' select_expr_list ')' { $$ = $select_expr_list; }
+returning_suffix: RETURNING select_expr_list { $$ = $select_expr_list; }

@@ -3652,35 +3652,34 @@ static void gen_delete_returning_stmt(ast_node *ast) {
-  gen_printf("\n  RETURNING (");
+  gen_printf("\n  RETURNING ");
   gen_select_expr_list(ast->right);
-  gen_printf(")");

@@ -3814,35 +3813,34 @@ static void gen_update_returning_stmt(ast_node *ast) {
-  gen_printf("\n  RETURNING (");
+  gen_printf("\n  RETURNING ");
   gen_select_expr_list(ast->right);
-  gen_printf(")");

@@ -4020,35 +4018,34 @@ static void gen_insert_returning_stmt(ast_node *ast) {
-  gen_printf("\n  RETURNING (");
+  gen_printf("\n  RETURNING ");
   gen_select_expr_list(ast->right);
-  gen_printf(")");

@@ -5351,35 +5348,34 @@ static void gen_upsert_returning_stmt(ast_node *ast) {
-  gen_printf("\n  RETURNING (");
+  gen_printf("\n  RETURNING ");
   gen_select_expr_list(ast->right);
-  gen_printf(")");
```

The resulting test executes the insert through SQLite, consumes every returned
row, checks its values, and checks the final row count:

```sql
TEST_MODERN_ONLY!(verify_insert_returning,
begin
  make_jsonb_backed_schema();
  cursor C for
    with data(a, b) as (values
      (1, 1),
      (2, 4),
      (3, 9),
      (4, 16)
    )
    insert into `a table`(`col 1`, `col 2`)
      select * from data
      returning(*);

  let i := 0;
  loop fetch C
  begin
    i += 1;
    EXPECT_EQ!(C.`col 1` * C.`col 1`, C.`col 2`);
  end;
  EXPECT_EQ!(i, 4);
end);
```

The key testing point is:

> More checks derived from the same implementation increase sensitivity to
> change, but not necessarily correctness. Independent oracles increase
> correctness.

#### Coverage is part of the compiler design

Project documentation says line coverage is maintained at 100%, with any dip
to 99.9% treated as temporary. In this codebase, 100% coverage turns the
fail-fast tree walkers into a development method.

Adding a grammar production creates a new tree shape. Covered parser and
semantic tests force that shape into semantic dispatch, where a missing entry
hits `Invariant(entry)`. Once semantic analysis is updated, covered codegen
tests force every surviving shape into the relevant backend, which fails the
same way if it is not handled. `EXTRACT` contracts catch changes below the node
kind, such as a child moving or becoming optional.

This is why missing ordinary AST kinds cannot persist in the normal covered
path. The code does not silently take a default path. It stops exactly where
the new shape first becomes someone's responsibility.

Not every parser shape should be registered in every backend. Semantic analysis
rewrites and removes shapes, and some declarations intentionally become no-ops
after they have served their semantic purpose. Coverage plus fail-fast dispatch
checks the shape set that actually reaches each phase, which is the useful set.

The current coverage script always runs the tests and produces reports, though
it does not pass a numeric `--fail-under-line 100` threshold to `gcovr`. The
project convention is doing the enforcement work in practice.

---

## CQL compared with conventional C guidance

Common C guidance emphasizes small functions, small modules, limited global
state, restrained macro use, explicit ownership, portable integer and string
handling, and tests that exercise failure paths. Sources used for comparison
are listed at the end of this chapter.

That advice is useful, but the details matter here. A compiler can violate the
surface rule while still preserving the property the rule was trying to buy.

### File size: CQL violates the letter, but often not the purpose

Current core inventory:

| Category | Files | Lines |
|---|---:|---:|
| Core compiler/runtime C and headers, excluding unit tests | 57 | 82,838 |
| Core `.c` files | 28 | 78,049 |
| Core headers | 29 | 4,789 |
| Grammar `cql.y` | 1 | 4,170 |
| Lexer `cql.l` | 1 | 716 |

Largest core files:

| Lines | File |
|---:|---|
| 27,347 | `sources/sem.c` |
| 9,034 | `sources/cg_c.c` |
| 7,384 | `sources/cqlrt_common.c` |
| 6,704 | `sources/gen_sql.c` |
| 6,309 | `sources/rewrite.c` |
| 5,933 | `sources/cg_lua.c` |

Large files draw criticism because they often mix unrelated responsibilities,
hide dependencies, and become hard to navigate. CQL's large files mostly map to
compiler phases. `sem.c` is enormous because the language has many semantic
rules; it is not a grab bag of UI, networking, persistence, and unrelated
utilities.

There are still real costs:

- merge conflicts concentrate;
- phase-local global state is easy to add;
- review requires understanding distant helper conventions;
- deliberate no-op registrations can still be missed;
- a rule may be difficult to locate without naming familiarity.

There are also real benefits:

- the full semantic vocabulary is searchable in one place;
- shared phase state does not cross arbitrary module boundaries;
- similarly shaped handlers sit near one another;
- dispatch initialization gives a broad inventory of supported statements.

The history says:

> File length has been less predictive of CQL defects than protocol
> completeness across files and phases.

### Function size: the code mostly follows the advice

Approximate current function distribution:

| Function length | Count | Share |
|---|---:|---:|
| 1-20 lines | 1,492 | 63.9% |
| 21-50 | 528 | 22.6% |
| 51-100 | 211 | 9.0% |
| 101-200 | 83 | 3.6% |
| 201-500 | 21 | 0.9% |
| 501+ | 1 | less than 0.1% |

- Median: **14 lines**
- Mean: **26.7 lines**
- 90th percentile: **64 lines**
- Maximum: **about 549 lines**

The Linux kernel's coding-style guidance says functions should usually fit on
one or two screenfuls, while allowing longer simple switch-like functions.
NASA/JPL's "Power of Ten" is stricter and uses roughly one printed page, often
interpreted as about 60 lines.

CQL's median and broad distribution compare well. The exceptional functions
need a little sorting:

- some are long, low-branch orchestration or registration sequences;
- some combine length and high branching and are genuine cognitive hotspots.

Examples in the second category include schema-mode generation, table semantic
analysis, result-set generation, and serialization update logic. Historical
fixes do cluster around schema and serialization. That tells us more than the
mere existence of a few long initialization functions.

### Naming: a major success

Approximately 99.5% of functions use lowercase snake case. Prefixes reliably
identify subsystem ownership:

- `sem_`
- `cg_`
- `gen_`
- `cql_`
- `rewrite_`
- `eval_`
- `ast_`
- `flow_`

The portability wrappers such as `Strdup`, `StrCaseCmp`, `IsAlpha`, and
`ToLower` are conspicuous exceptions, and their exceptional spelling is useful:
it marks them as replacements for platform or C runtime behavior.

Regular naming buys back some of the navigability lost to file size. A
27,000-line file is much less hostile when symbol names form a searchable
taxonomy.

### Macros: CQL created a small language inside C

CQL uses macros for facilities that C does not express conveniently:

- AST destructuring;
- generated node predicates and constructors;
- scoped output buffers;
- statement and expression dispatch registration;
- cleanup patterns;
- type-specific generated-code templates.

For example:

```c
#define EXTRACT_NAMED_NOTNULL(name, type, node) \
  ast_node *name = node; \
  Contract(name && is_ast_##type(name));

#define EXTRACT_NOTNULL(type, node) \
  EXTRACT_NAMED_NOTNULL(type, type, node)

#define EXTRACT_STRING(name, node) \
  Contract(is_ast_str(node)); \
  const char *name = ((str_ast_node *)(node))->value; \
  Contract(name);
```

And scoped buffers:

```c
#define CHARBUF_OPEN(x) \
  int32_t __saved_charbuf_count##x = charbuf_open_count; \
  charbuf x; \
  pending_charbuf pending_charbuf_##x; \
  pending_charbuf_##x.prev = __charbufs_in_flight; \
  pending_charbuf_##x.buf = &x; \
  __charbufs_in_flight = &pending_charbuf_##x; \
  bopen(&x)

#define CHARBUF_CLOSE(x) \
  bclose(&x); \
  Invariant(__saved_charbuf_count##x == charbuf_open_count); \
  __charbufs_in_flight = __charbufs_in_flight->prev
```

These macros form a standardized, pervasive, documented implementation
language. Their consistency is what makes the approach viable.

The costs are:

- declarations are implicit;
- token-pasted local names complicate debugging;
- control and lifetime are not visible to ordinary C tooling;
- deliberate no-op AST cases still require an explicit phase classification.

I did not find macro misuse as a dominant defect class. For normal reachable
tree shapes, the macros plus coverage make missing cases fail immediately. The
residual risk is mainly the set of shapes a phase is supposed to ignore, or
shapes transformed away before that phase runs.

### Contracts compensate for an intentionally weak static representation

Current core files contain approximately:

- 1,702 `Contract` calls;
- 496 `Invariant` calls;
- about 26.5 always-on checks per thousand lines of core code.

They are not disabled by `NDEBUG`:

```c
#define Invariant(condition) \
  do { if (!(condition)) abort(); } while (0)

#define Contract(condition) \
  do { if (!(condition)) abort(); } while (0)
```

CQL's AST uses several structs with a common initial layout:

```c
typedef struct ast_node {
  const char *type;
  struct sem_node *sem;
  struct ast_node *parent;
  int32_t lineno;
  CSTR filename;
  struct ast_node *left;
  struct ast_node *right;
} ast_node;

typedef struct str_ast_node {
  const char *type;
  struct sem_node *sem;
  struct ast_node *parent;
  int32_t lineno;
  CSTR filename;
  const char *value;
  uint8_t str_type;
} str_ast_node;
```

This pseudo-object model gives up some static safety compared with a tagged
union and distinct typed visitors. It also removes a great deal of verbosity
from a large grammar. Generated `is_ast_*` predicates, extraction macros,
canonical type strings, and always-on contracts make the trade workable.

The question is what a failed condition represents:

- an internal compiler invariant, where aborting is appropriate; or
- malformed user input, where a diagnostic is required.

The June 2021 fragment fix, which converted a `Contract` into a semantic error,
shows the boundary clearly:

```diff
 // check for the single named CTE
 EXTRACT_NOTNULL(cte_tables, with_select_stmt->left->left);
-Contract(cte_tables->right == NULL);
+if (cte_tables->right) {
+  report_error(cte_tables, "CQL0253: base fragment must have only a single CTE named the same as the fragment", base_frag_name);
+  goto error;
+}
```

Commit:
[`a440adedac03`](https://github.com/ricomariani/CG-SQL-author/commit/a440adedac03)

The regression supplies the malformed two-CTE fragment and requires exactly one
user-facing diagnostic:

```sql
-- TEST: make sure that using two CTEs in a base fragment causes an error
-- You can run into this error if you mark your extension fragment as a base fragment on accident.
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- + Error % base fragment must have only a single CTE named the same as the fragment 'err_assembly_name'
-- +1 Error
@attribute(cql:base_fragment=err_assembly_name)
create proc ext1()
begin
  with err_assembly_name(id) as (select * from foo),
  ext1(*) as (
    select * from err_assembly_name
    union all
    select 1 id
  )
  select * from ext1;
end;
```

---

## Bug classes that stayed rare

### Aggressive optimizer bugs

Compiler bug literature often emphasizes misoptimization: a legal input is
accepted and silently transformed into wrong machine code. CQL has rewrites and
code generation, without the deep, target-dependent optimization pipeline of
GCC or LLVM. Without a deep machine-optimization pipeline, CQL's public history
clusters around SQL rewrites, semantic propagation, generated ownership,
schema ordering, and backend text generation rather than instruction selection
or value-range optimization.

The closest CQL analogue is a rewrite or pretty-printer that emits a different
semantic tree, such as missing right-side parentheses.

### Fine-grained AST lifetime failures

The arena model removes most per-node deallocation from ordinary compiler work.
There are ownership bugs around rewrites and displaced primitive nodes, but no
broad history of arbitrary AST use-after-free failures. Bulk lifetime is doing
useful work.

### Naming-driven confusion

Naming defects do not form a strong historical family. Subsystem prefixes and
snake case make the large phase files navigable, and the usual long-lived-C
drift in abbreviations and styles is largely absent.

### Concurrency races

CQL is a single-threaded batch compiler. Its global-state architecture would
need isolation for concurrent use, but concurrency is outside the normal
execution model, so data races do not dominate the public history.

### Unbounded parser complexity

The generated lexer/parser and explicit grammar keep syntax handling relatively
regular. Parser defects exist. The long-term difficulty shows up more often in
semantics, rewrites, migration, and generated runtime behavior.

---

## Repeated defect families and prevention signals

Repeated bugs usually mean the abstraction is missing part of the protocol.
Rapid CI corrections mean the delivery system caught the mistake.

| Family | Prevention signal |
|---|---|
| Deliberate no-op and non-tree switches | Keep intentional no-ops explicit and covered; do not apply AST-dispatch assumptions to runtime type switches. |
| Identifier rendering | Centralize quoting and escaping across emitters. |
| Ownership and context cleanup | Replace manual sequences with named ownership, lifetime, and context helpers. |
| Schema order | Name each order domain and test dependency behavior as a graph. |
| Serialization | Validate the whole representation before arithmetic, copying, or mutation; classify audit hardening separately from observed failures. |

---

## Which mitigations worked

### 1. 100% coverage plus fail-fast tree walking

I think this is one of the strongest mechanisms in the codebase. Every covered
parser shape is forced into semantic analysis, every surviving covered shape is
forced into code generation, and missing dispatch entries or changed child
layouts abort at the exact boundary that needs work.

It turns compiler development into a sequence of concrete failures instead of
a checklist somebody has to remember.

### 2. Bulk allocation

Arena allocation reduces ordinary AST lifetime risk and makes pointer stability
a design property.

### 3. Always-on contracts

Contracts catch violations close to their source. They are especially valuable
with the intentionally weakly typed AST representation.

### 4. Generated and table-driven regularity

AST predicates, constructors, dispatch initialization, and test directives
keep a large language surface regular.

### 5. Layered and independent tests

Pattern assertions, goldens, generated-code compilation, runtime execution,
differential checks, reference balancing, sanitizer/compiler diversity, and
repeated invocation cover different failure modes. SQLite execution is
especially valuable because it can reject semantics on which parsing, semantic
analysis, code generation, and goldens all agree.

### 6. Helper functions that encode ownership

`cql_set_*_ref` and `cql_set_created_*_ref` put the retain/release contract in
one place instead of relying on memory at every call site.

### 7. Exact regression and invariant tests

The best test forces the failed or newly enforced invariant rather than merely
executing the affected code.

---

## What those mitigations do not prove

### 1. Coverage and goldens are not semantic oracles

Coverage forces reachable shapes through fail-fast machinery, and goldens
detect textual changes. Neither independently proves handler semantics, feature
combinations, or the correctness of expected output.

### 2. Net leak checks

Reference balancing catches leaks, with no claim to catch every ordering or
aliasing mistake.

### 3. Top-level cleanup

Cleanup makes repeated whole-compilation invocation reliable. Nested reentrancy
needs a targeted save of the context that is actually changing because
destruction would throw away the outer work. In most places that context is one
or two symbol tables or scopes.

### 4. Conventions around paired operations

`report_error` plus `record_error`, a type case plus pointer consumption, or
creation plus matching cleanup remain vulnerable while the pairing is spread
across multiple operations.

---

## A compact historical catalogue

These examples cover the range; they are not ranked by severity.

| Date | Commit | Area | Defect pattern | Durable lesson |
|---|---|---|---|---|
| 2020-10-26 | [`c2a205b6`](https://github.com/ricomariani/CG-SQL-author/commit/c2a205b6e28b1083e7cd862bb5064f6000bca24c) | Schema semantics | Applied delete-procedure immutability before deletion existed | Versioned rules need explicit applicability conditions |
| 2020-11-18 | [`36e3e3a7`](https://github.com/ricomariani/CG-SQL-author/commit/36e3e3a7880407509205158c1a632a21f9840dac) | Lexer | Assumed `long` was 64-bit | Host types can alter source-language behavior |
| 2020-11-18 | [`47e78dd5`](https://github.com/ricomariani/CG-SQL-author/commit/47e78dd5e6a56c501b694030e0a15e92027be2fe) | C codegen | Precedence without associativity lost tree structure | Pretty-printing rules must encode the full grammar |
| 2021-01-08 | [`64e138ac`](https://github.com/ricomariani/CG-SQL-author/commit/64e138ac3ac9293429932f4f48097e05ae6e7001) | Lexer | Escape alternatives admitted the wrong characters | Regex alternatives deserve adjacency and escape tests |
| 2021-01-27 | [`fa6522e3`](https://github.com/ricomariani/CG-SQL-author/commit/fa6522e3ada6be01612f527315fe62b63c7d9050) | Lexer | `ELSE IFNULL` became `ELSE_IF` | Keyword rules must prove token boundaries |
| 2021-03-20 | [`6a686760`](https://github.com/ricomariani/CG-SQL-author/commit/6a6867609f672616106e8fff690dbcd78ea39100) | Generators | Symbol tables were nulled without delete | Reset and destruction are different operations |
| 2021-07-20 | [`1c95bbdb`](https://github.com/ricomariani/CG-SQL-author/commit/1c95bbdb8e20dbf6a02e479245dce03dbde95fd9) | Parser | Right recursion exhausted parser stack | Grammar shape is a resource-use decision |
| 2021-07-20 | [`5084c83c`](https://github.com/ricomariani/CG-SQL-author/commit/5084c83c1f751dcfd436253c88bad3fbf1bb85f7) | Semantics | Diagnostic target and propagated error state diverged | Reporting and state mutation should be one protocol |
| 2021-12-10 | [`39551d17`](https://github.com/ricomariani/CG-SQL-author/commit/39551d179f77ce34c0a6678fa9e1a89ae14db156) | Schema codegen | Reused drop order as create order | Name distinct order domains |
| 2021-12-22 | [`d17a3506`](https://github.com/ricomariani/CG-SQL-author/commit/d17a350684151871d4ed78b1126f8d6e1a86cbf9) | Flow | Empty branch had no representation | Semantic absence is still a semantic case |
| 2022-05-25 | [`3a9f41f2`](https://github.com/ricomariani/CG-SQL-author/commit/3a9f41f21a266ab5377d23d9df3594c9a2a2f9c7) | C codegen | Semantic-only AST kind missing its backend no-op | Fail-fast catches the miss; deliberate no-op cases still need explicit registration |
| 2022-08-02 | [`673ec88c`](https://github.com/ricomariani/CG-SQL-author/commit/673ec88c56ce44c44204b31f77b81db6202cbcb3) | Runtime parser | Used `sizeof(pointer)` as string length | C array/pointer decay remains a routine hazard |
| 2022-10-27 | [`0ad05ef6`](https://github.com/ricomariani/CG-SQL-author/commit/0ad05ef61eb964ba4ee2aa94f487ede020e0f145) | Semantics | Primary-key column ordinal was not incremented | Index bookkeeping needs direct shape assertions |
| 2022-12-05 | [`315a202c`](https://github.com/ricomariani/CG-SQL-author/commit/315a202c89ee4634416e1a7eb66a63b10b8a082b) | Rewrite | Overwrote an AST node and displaced owned primitive data | Transparent wrappers preserve ownership better than shape copying |
| 2023-08-11 | [`9e9a4e09`](https://github.com/ricomariani/CG-SQL-author/commit/9e9a4e099897cbeb0bb45cccb447b542e7b9f22e) | Serialization | Emitted variable fields in update order, not canonical order | Equivalent logical keys need canonical bytes |
| 2023-08-22 | [`67b29643`](https://github.com/ricomariani/CG-SQL-author/commit/67b2964335bdda089ce9733be9a3aec6dca22907) | SQL generation | Dot expressions bypassed shared-fragment rename callback | Every syntax form must pass through the same name-resolution hook |
| 2023-12-21 | [`7933769f`](https://github.com/ricomariani/CG-SQL-author/commit/7933769f72b4a7d18e73895eac150fa200378c76) | Semantics/tests | Missing error record hidden by batched tests | Exact per-case diagnostics beat aggregate counts |
| 2024-11-20 | [`0001945b`](https://github.com/ricomariani/CG-SQL-author/commit/0001945b26ad1b50b80f439ce57f2b9fbe89f523) | Generated ownership | Released destination before evaluating aliasing call | Encode ownership variants in helper APIs |
| 2024-12-24 | [`3163e93e`](https://github.com/ricomariani/CG-SQL-author/commit/3163e93e7f01) | SQLite syntax | All internal goldens agreed on invalid `RETURNING` syntax | Independent execution is stronger than consistent output |
| 2024-12-25 | [`cf546d7e`](https://github.com/ricomariani/CG-SQL-author/commit/cf546d7ed13edb2642abb75addcd6d5b48479c53) | Rewrites | Backed-table/upsert/returning features composed incorrectly | Cross-product tests matter for interacting rewrites |
| 2025-03-28 | [`7dadf83a`](https://github.com/ricomariani/CG-SQL-author/commit/7dadf83af8d84f3d5d7450769e5520b80efb65cf) | Reentrant codegen | Nested `SELECT` clobbered shared-fragment generator state | Finish documented re-entry protocols; use a focused helper for the exceptional wider context |
| 2026-08 to 2026-10 | [`eaa48be3`](https://github.com/ricomariani/CG-SQL-author/commit/eaa48be31c4a44b37a0a80c2abead5f58aeec70b), [`25f48ef5`](https://github.com/ricomariani/CG-SQL-author/commit/25f48ef5985a15b805f2dda66347c7c33bb71ef9), [`14b0eaa7`](https://github.com/ricomariani/CG-SQL-author/commit/14b0eaa75cba729abe3e16bacbbca417990a6c13), and related audit commits | AI-assisted correctness audit | Mix of latent functional issues, defensive validation, and theoretical invariant hardening | Classify separately from reported or observed operational bugs |

---

## Likely future bug shapes

I am extrapolating from the history here. None of these entries asserts that a
current bug exists.

### Most likely

1. **A rewrite that preserves value but drops one decoration.**
   Nullability, sensitivity, kind, shape, source location, parent linkage, and
   ownership do not all travel automatically.

2. **An exceptional reentrant path with an unfinished save/restore
   requirement.**
   Most recursive contexts are tiny. The shared-fragment case was wider, was
   already called out in a TODO, and would be cleaner with one focused helper.

3. **An identifier edge case in a less-used generated SQL path.**
   Static SQL, dynamic SQL, migration helpers, and backend strings have
   historically used separate spellings.

4. **A schema dependency edge case involving several individually correct
   orders.**
   Recreate groups, deletes, foreign keys, triggers, views, and version filters
   create a large ordering cross-product.

5. **A serialized-data edge case at zero length, maximum count, or aliased
   storage.**
   These are the repeated boundaries in the low-level history.

6. **A deliberate no-op or rewritten-away shape missing its phase
   classification.**
   Ordinary reachable AST kinds fail immediately under covered dispatch. The
   narrower residual risk is a shape that a phase intentionally ignores, or a
   shape whose lifetime ends during semantic rewriting.

---

## Recommendations suggested by the history

These recommendations follow from the history.
Nothing in this section reports a new bug.

### 1. Keep fail-fast shape coverage and the 100% norm non-negotiable

The existing design is the right one: dispatch has no permissive default,
`EXTRACT` checks every tree edge, and 100% coverage forces new shapes through
the phases that can actually see them.

Do not try to generate every backend registration from the parser's AST
inventory. Semantic analysis rewrites the tree, some shapes disappear, and
some declarations deliberately become no-ops. The required shape set is
phase-specific.

The useful improvement is narrower: keep deliberate `NO_OP` classifications
obvious and covered, because those are the places where "handling" means doing
nothing and the normal output path provides less evidence.

A numeric CI threshold could make the convention explicit, but the essential
rule is that new syntax and rewrites must exercise every reachable shape
through the phases that can see it.

### 2. Give order domains explicit names and types

Use vocabulary such as:

- declaration order;
- dependency order;
- reverse dependency order;
- create order;
- drop order;
- canonical field order.

Avoid a generic "ordinal" or a comparator whose direction has to be
rediscovered from context.

### 3. Add a focused shared-fragment context helper

Most recursion already saves exactly what it needs: often one or two symbol
tables, a join scope, or the three-pointer `gen_sql_state`.

The shared-fragment argument path is the exception. It should have one helper
that pushes and pops its fragment buffers, counters, predicates, and generator
callbacks for both C and Lua. That removes the duplicated manual list without
pretending the entire compiler phase needs to become one giant context object.

### 4. Centralize identifier rendering

Static SQL, dynamic SQL, schema migration, and backend-specific output should
share identifier-quoting primitives, with explicit rules for already-quoted
names and generated names.

### 5. Prefer protocol helpers over paired calls

The ownership history makes a strong case for this. Beyond ownership setters,
the clearest remaining opportunities are report-and-record semantic error
helpers and validated serialized-table readers.

### 6. Continue increasing oracle independence

Keep adding tests whose oracle comes from outside the path under test--especially
SQLite execution, C/Lua comparison, independent serialization, post-failure
reinvocation, multiple C compilers, and ASAN. More goldens improve change
detection, not semantic independence.

### 7. Preserve a defect taxonomy in commit or issue metadata

Knuth's *The Errors of TeX* gained much of its value from a maintained error
log and classification. CQL's future history would be easier to analyze if
fixes recorded a small set of labels such as:

- parser/lexer;
- semantic propagation;
- rewrite composition;
- schema ordering;
- ownership/lifetime;
- fail-fast tree-shape handling;
- representation/bounds;
- backend divergence;
- test oracle.

That would make repeat families visible sooner.

---

## Sources and reproducibility

### Repository sources

Primary evidence comes from:

- the full Git history of `ricomariani/CG-SQL-author`;
- production patches linked throughout this chapter;
- `sources/test.sh`;
- `sources/common/test_helpers.sh`;
- `sources/cql-verify/README.md`;
- `sources/test/run_test.sql`;
- `sources/test/amalgam_test.c`;
- `sources/unit_tests.c`;
- `sources/lua_demo/prepare_run_test.sh` and `sources/lua_demo/run_test.sh`;
- `sources/upgrade/upgrade_validate.sql` and `sources/upgrade/upgrade_test.c`;
- `sources/cql.h`;
- `sources/ast.h` and `sources/ast.c`;
- `sources/flow.c`;
- `sources/sem.c`;
- `sources/cg_c.c`;
- `sources/cg_lua.c`;
- `sources/cg_schema.c`;
- `sources/gen_sql.c`;
- `sources/rewrite.c`;
- `sources/cqlrt_common.c`;
- `sources/cqlrt.lua`;
- `sources/minipool.c`;
- `sources/charbuf.h` and `sources/charbuf.c`;
- `sources/bytebuf.c`;
- `sources/encoders.c`;
- `docs/developer_guide/01_building_the_ast.md`;
- `docs/developer_guide/04_testing.md`.

### External comparison sources

- Donald E. Knuth, ["The Errors of TeX"](https://doi.org/10.1002/spe.4380190702),
  *Software: Practice and Experience*, 1989. Knuth classified more than 850
  logged changes over ten years and used the history as a study of program
  evolution.
- [Linux kernel coding style, section 6: Functions](https://www.kernel.org/doc/html/latest/process/coding-style.html#functions),
  for common guidance on short, single-purpose functions and limited local
  state.
- [SEI CERT C Coding Standard](https://wiki.sei.cmu.edu/confluence/display/c),
  for the standard categories of C risk: integers, arrays, strings, memory,
  I/O, error handling, and undefined behavior.
- Gerard J. Holzmann,
  ["The Power of Ten: Rules for Developing Safety-Critical Code"](https://spinroot.com/gerard/pdf/P10.pdf),
  for the stricter one-page function guideline, assertion use, and constrained
  control flow.
- Xuejun Yang, Yang Chen, Eric Eide, and John Regehr,
  ["Finding and Understanding Bugs in C Compilers"](https://web.stanford.edu/class/cs343/resources/finding-bugs-compilers.pdf),
  for compiler wrong-code testing, independent comparison, and the limits of
  testing only proved components.
- [LLVM Testing Infrastructure Guide](https://llvm.org/docs/TestingGuide.html),
  for the distinction between unit, regression, and broader test-suite
  coverage.
- [GCC Coding Conventions and testsuite conventions](https://gcc.gnu.org/codingconventions.html),
  for explicit regression-test identification and compiler test maintenance.

### Measurement notes

- File counts use tracked files. Generated release/beta distributions and
  vendored SQLite are excluded unless explicitly stated.
- Function counts and lengths come from a lightweight C lexical scan. It
  removes comments, strings, and preprocessor directives before identifying
  top-level brace-delimited functions. Macro-generated and conditionally
  compiled functions make the values approximate.
- The branch proxy counts control-flow tokens; it is not full McCabe
  complexity.
- Commit-screen counts are deliberately labeled conservative candidates. They
  should not be read as exact bug counts.
- Those candidates mix observed failures, development-time omissions,
  prophylactic audit hardening, and sometimes multiple commits for one issue.
- Rapid CI-driven revert/reapply chains are prevention successes and should be
  collapsed into the originating issue rather than counted as extra bugs.
- I checked my recollection of roughly 12 real bugs per year against the Git
  history; I am not presenting it as a count derived from Git alone.
- Generated-reference churn can greatly inflate changed-file and changed-line
  counts for a small production correction.
- I make no conclusion about defect severity or exploitability.
