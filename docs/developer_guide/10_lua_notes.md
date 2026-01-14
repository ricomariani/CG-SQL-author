---
title: "Part 10: Lua Code Generation"
weight: 10
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Preface

Part 10 discusses the Lua code generator and compares it with the C code generator.
The CQL compiler can target multiple backends: primarily C (via `cg_c.c`)
and Lua (via cg_lua.c). While both generators share significant
infrastructure and conceptual patterns, they differ substantially in their approach to type
handling, memory management, and runtime integration. Understanding these differences is
essential for anyone working on either backend or considering adding a new target language.

This chapter covers:
* Fundamental differences between C and Lua as target languages
* Type system mapping strategies
* Memory management and reference counting
* SQLite integration patterns
* Code generation idioms and conventions
* Shared infrastructure and divergences

## Language Characteristics

### C: Static Typing and Manual Memory Management

C is a statically typed, compiled language with explicit memory management. The key characteristics
that influence code generation are:

**Static typing**: Every variable must have a declared type at compile time. This means CQL's
type system maps directly to C types, with separate types for nullable vs. non-nullable values.

**Manual memory management**: The programmer (or generated code) must explicitly allocate and
free memory. String and blob types require reference counting. Object types use a generic
reference counting interface.

**Null representation**: There's no universal "null" value. Nullable types are represented
as structs containing a boolean `is_null` field plus the value. For example:

```c
typedef struct cql_nullable_int32 {
  cql_bool is_null;
  cql_int32 value;
} cql_nullable_int32;
```

**Primitive operations**: All operations are explicit. Even comparisons require careful null
handling, often via helper macros like `cql_is_nullable_true`.

### Lua: Dynamic Typing and Automatic Garbage Collection

Lua is a dynamically typed, interpreted language with automatic memory management. Its
characteristics lead to very different code generation strategies:

**Dynamic typing**: Variables don't have declared types. A variable can hold any type of value
at runtime. This means CQL's compile-time type checking doesn't appear in the generated Lua
code at all.

**Garbage collection**: Lua automatically manages memory. When objects are no longer referenced,
they're collected. This eliminates the need for explicit reference counting in generated code.

**Native nil**: Lua has a built-in `nil` value that represents "no value" or "null". This maps
perfectly to SQL NULL and CQL's nullable types.

**Tables as universal data structure**: Lua uses tables (hash maps) for everything: arrays,
objects, result sets, even modules. This provides a flexible foundation for representing
CQL's structured data.

## Type System Mapping

### C Type Mapping

In C, each CQL type maps to a specific C type. The mapping depends on nullability:

```c
// From cg_c.c type mappings:
// INTEGER NOT NULL -> cql_int32
// INTEGER (nullable) -> cql_nullable_int32 (struct)
// LONG INTEGER NOT NULL -> cql_int64
// LONG INTEGER (nullable) -> cql_nullable_int64 (struct)
// REAL NOT NULL -> cql_double
// REAL (nullable) -> cql_nullable_double (struct)
// BOOL NOT NULL -> cql_bool
// BOOL (nullable) -> cql_nullable_bool (struct)
// TEXT -> cql_string_ref (always nullable, NULL = null)
// BLOB -> cql_blob_ref (always nullable, NULL = null)
// OBJECT -> cql_object_ref (always nullable, NULL = null)
```

Reference types (text, blob, object) are always represented as pointers. A NULL pointer
means SQL NULL. Non-reference types use the struct-with-flag approach when nullable.

### Lua Type Mapping

In Lua, the mapping is much simpler because of dynamic typing:

```lua
-- From cg_lua.c perspective:
-- INTEGER/LONG INTEGER/BOOL -> Lua number (or nil if null)
-- REAL -> Lua number (or nil if null)
-- TEXT -> Lua string (or nil if null)
-- BLOB -> Lua string (binary data) (or nil if null)
-- OBJECT -> Lua object reference (or nil if null)
-- All nullable types -> value or nil
```

Lua's `nil` serves as the universal null representation. No wrapper structs needed.

## Variable Declaration

### C Variable Declaration

C requires explicit type declarations. The `cg_var_decl` function generates these:

```c
// From cg_c.c
static void cg_var_decl(charbuf *output, sem_t sem_type, CSTR name, bool_t is_full_decl) {
  // Emits something like:
  //   cql_int32 x = 0;
  //   cql_nullable_int32 y = { .is_null = 1 };
  //   cql_string_ref str = NULL;
}
```

Non-nullable numeric types get zero-initialized. Nullable types get their `is_null` flag
set to 1. Reference types start as NULL.

### Lua Variable Declaration

Lua variables don't need type declarations, but they do need initialization in certain contexts.
The `cg_lua_var_decl` function from cg_lua.c:

```c
static void cg_lua_var_decl(charbuf *output, sem_t sem_type, CSTR name) {
  Contract(is_unitary(sem_type));
  Contract(!is_null_type(sem_type));
  Contract(cg_main_output);

  if (lua_in_var_group_emit) {
    // we only need initializers for not-null types that are not reference types
    // here we are avoiding bogus looking codegen taking advantage that
    // variables have the value nil by default which is the correct starting
    // value for nullable types and ref types.
    if (is_nullable(sem_type) || is_ref_type(sem_type)) {
      // no init needed
      return;
    }
  }
  else {
    // variable groups are global by construction so don't emit "local" for them
    // if we're here this not a variable group
    bprintf(output, "local ");
  }

  bprintf(output, "%s", name);
  cg_lua_emit_local_init(output, sem_type);
}
```

The key insight: Lua variables default to `nil`, which is perfect for nullable types and
references. We only need explicit initialization for non-nullable non-reference types:

```lua
-- Generated Lua code:
local x = 0  -- NOT NULL INTEGER
local y      -- nullable integer, defaults to nil (correct!)
local str    -- TEXT, defaults to nil (correct!)
```

This is a significant simplification over C.

## Truthiness and Type Coercion

### Lua's Unique Truthiness Model

One of the most significant differences between C and Lua is their treatment of boolean values
in conditional contexts. This difference requires careful handling throughout the Lua code generator.

**C truthiness**: In C, zero is false, non-zero is true:
```c
if (0) { }      // never executes
if (1) { }      // always executes
if (42) { }     // always executes
if (x) { }      // executes if x != 0
```

**Lua truthiness**: In Lua, only `false` and `nil` are falsey. **Everything else is truthy**,
including zero:
```lua
if 0 then print("executed") end      -- EXECUTES! Zero is truthy!
if false then print("no") end        -- does not execute
if nil then print("no") end          -- does not execute
if 1 then print("yes") end           -- executes
if "" then print("yes") end          -- executes (empty string is truthy)
```

This creates a problem for CQL because SQL and C follow the C model where `0` means false.
Consider this CQL code:

```sql
DECLARE x INTEGER NOT NULL;
SET x := 0;
IF x THEN
  -- Should this execute? In SQL/C semantics: NO
  -- In naive Lua semantics: YES (zero is truthy!)
END IF;
```

### The Solution: Explicit Conversion Functions

The Lua code generator solves this by using explicit conversion functions from cqlrt.lua:

```lua
function cql_to_bool(num)
  if num == nil then
    return nil
  end
  return num ~= 0
end

function cql_to_num(b)
  if b == nil then
    return nil
  end
  if b then
    return 1
  else
    return 0
  end
end
```

These functions bridge the gap between CQL's C-style semantics and Lua's native semantics.

### When Conversions Are Applied

The code generator carefully applies conversions at type boundaries:

**Boolean to numeric context** (`cg_lua_to_num`):
```lua
-- CQL: SET x := some_bool + 1;
-- Generated:
x = cql_to_num(some_bool) + 1

-- If some_bool is true: 1 + 1 = 2
-- If some_bool is false: 0 + 1 = 1
-- If some_bool is nil: nil (NULL propagates)
```

**Numeric to boolean context** (`cg_lua_to_bool`):
```lua
-- CQL: IF x THEN ... END IF;
-- where x is INTEGER
-- Generated:
if cql_to_bool(x) then ... end

-- If x is 0: cql_to_bool(0) = false, doesn't execute
-- If x is 42: cql_to_bool(42) = true, executes
-- If x is nil: cql_to_bool(nil) = nil, doesn't execute
```

### Optimization for Literals

The generator optimizes common cases to avoid unnecessary function calls:

```c
// From cg_lua_emit_to_bool:
if (!strcmp("1", input)) {
  bprintf(output, "true");    // Hard-coded
  return;
}
if (!strcmp("0", input)) {
  bprintf(output, "false");   // Hard-coded
  return;
}
// Otherwise: cql_to_bool(...)

// From cg_lua_emit_to_num:
if (!strcmp("true", input)) {
  bprintf(output, "1");       // Hard-coded
  return;
}
if (!strcmp("false", input)) {
  bprintf(output, "0");       // Hard-coded
  return;
}
// Otherwise: cql_to_num(...)
```

This means `IF 1 THEN` generates `if true then` (not `if cql_to_bool(1) then`), and
`SET x := true + 1` generates `x = 1 + 1` (not `x = cql_to_num(true) + 1`).

### Logical Operators: A Special Case

Logical operators (`AND`, `OR`) in CQL must use boolean semantics, but they also must
short-circuit correctly. The generated code converts both operands:

```lua
-- CQL: IF x AND y THEN
-- where x and y are integers
-- Generated:
if cql_to_bool(x) and cql_to_bool(y) then
```

This ensures:
1. `0 AND 1` evaluates to false (not true, as `0 and 1` would in raw Lua)
2. Short-circuit behavior is preserved (Lua's `and`/`or` short-circuit)
3. NULL propagation works correctly (nil values are handled)

### Why This Matters

Without these conversions, CQL code would have different semantics in Lua than in C:

```sql
-- This loop would be infinite in naive Lua (zero is truthy)
-- but correctly terminates in both C and CQL-generated Lua:
LET i := 5;
WHILE i
BEGIN
  i -= 1;
END;
-- When i reaches 0, the loop exits in both C and Lua
```

The moral: **Lua's code generator can't be naive.** Every place where a numeric expression
appears in a boolean context, or vice versa, requires careful conversion to maintain CQL's
C-like semantics in a Lua runtime.

## Short-Circuit Evaluation: Value vs. Boolean Semantics

Both C and Lua support short-circuit evaluation for logical operators (`&&`/`||` in C,
`and`/`or` in Lua), but they have fundamentally different semantics that require careful
handling in the code generator.

### C Short-Circuit Semantics

In C, logical operators return boolean (integer) values:

```c
int x = 5 && 10;      // x = 1 (true)
int y = 0 && 10;      // y = 0 (false, RHS not evaluated)
int z = 5 || 10;      // z = 1 (true, RHS not evaluated)
```

The result is always 1 (true) or 0 (false). Short-circuiting prevents evaluation of the
right-hand side when the result is already determined.

### Lua Short-Circuit Semantics

In Lua, logical operators **return values**, not necessarily booleans:

```lua
local x = 5 and 10      -- x = 10 (returns RHS if LHS is truthy)
local y = 0 and 10      -- y = 10 (zero is truthy! returns RHS)
local z = 5 or 10       -- z = 5 (returns LHS if LHS is truthy)
local w = false or 10   -- w = 10 (returns RHS since LHS is falsey)
```

The semantics are:
* `a and b` returns `a` if `a` is falsey, otherwise returns `b`
* `a or b` returns `a` if `a` is truthy, otherwise returns `b`

This creates problems for CQL because:
1. The result isn't necessarily a boolean
2. Zero is truthy, so `0 and x` would return `x` instead of `false`
3. NULL (nil) semantics require three-valued logic

### The Lua Code Generator's Solution

The Lua generator must handle multiple cases depending on whether the operands can be
evaluated inline or require statement sequences.

#### Simple Case: Direct Operators

When both operands are simple expressions (no statements needed) and the result is not
nullable, the generator can use native Lua operators **after converting to boolean**:

```lua
-- CQL: SET result := x AND y;
-- where x and y are non-nullable integers
-- Generated (simple case):
result = cql_to_bool(x) and cql_to_bool(y)
```

The conversions ensure:
* `0 and 1` becomes `cql_to_bool(0) and cql_to_bool(1)` → `false and true` → `false`
* Both operands are converted, so the native `and` operator works correctly
* Short-circuit behavior is preserved: if `x` is 0 (false after conversion), `y` isn't evaluated

#### Complex Case: Function Wrapper

When the right operand requires statements (e.g., it calls a procedure), the generator
wraps it in a function to defer evaluation:

```lua
-- CQL: SET result := x AND (SELECT something FROM table);
-- Generated:
result = cql_shortcircuit_and(x, function() return <select expression> end)
```

From cqlrt.lua:

```lua
function cql_shortcircuit_and(x, y)
  if cql_is_false(x) then
    return false  -- short-circuit: don't call y()
  else
    return cql_logical_and(x, y())  -- call y() only if needed
  end
end
```

This ensures:
* The right side is only evaluated if necessary
* The function wrapper prevents premature evaluation
* NULL semantics are handled correctly

#### Most Complex Case: Open-Coded Short-Circuit

When the right operand has complex control flow (like `goto` for error handling), wrapping
it in a function would break the control flow. The generator open-codes the short-circuit:

```lua
-- CQL: SET result := x AND <complex expression that might throw>;
-- Generated:
repeat
  local _tmp_bool_0 = x
  if cql_is_false(_tmp_bool_0) then
    result = false
    break
  end
  
  -- Complex right-hand evaluation goes here, can use goto cleanup
  local _tmp_bool_1 = <complex RHS evaluation>
  
  result = cql_logical_and(_tmp_bool_0, _tmp_bool_1)
until true
```

```c
// we need a scratch for the left to avoid evaluating it twice
CG_LUA_PUSH_TEMP(temp, SEM_TYPE_BOOL);
cg_lua_store_same_type(cg_main_output, temp.ptr, SEM_TYPE_BOOL, l_value.ptr);

// This is the open coded short circuit version
bprintf(cg_main_output, "if cql_is_%s(%s) then\n", short_circuit_value, temp.ptr);
bprintf(cg_main_output, "  ");
cg_lua_store_same_type(cg_main_output, result_var.ptr, sem_type_result, short_circuit_value);
bprintf(cg_main_output, "else\n");

  // The evaluation of the right goes here, it could include things that
  // throw (like proc as func calls) so we have to be careful to leave it
  // in a context where "goto cleanup" still works
  CG_PUSH_MAIN_INDENT(r, 2)
  bprintf(cg_main_output, "%s", right_eval.ptr);
  // ... combine with logical_and/logical_or helper
```

### NULL Propagation in Logical Operations

SQL's three-valued logic requires special handling. The truth tables for AND/OR with NULL:

```
AND:  NULL AND FALSE = FALSE (short-circuit!)
      NULL AND TRUE  = NULL
      NULL AND NULL  = NULL
      FALSE AND NULL = FALSE (short-circuit!)
      TRUE AND NULL  = NULL

OR:   NULL OR TRUE  = TRUE (short-circuit!)
      NULL OR FALSE = NULL
      NULL OR NULL  = NULL
      TRUE OR NULL  = TRUE (short-circuit!)
      FALSE OR NULL = NULL
```

The runtime helpers implement these correctly:

```lua
function cql_logical_and(x, y)
  if cql_is_false(x) or cql_is_false(y) then
    return false   -- FALSE dominates
  elseif x == nil or y == nil then
    return nil     -- NULL propagates when result not determined
  else
    return true    -- both are true
  end
end

function cql_logical_or(x, y)
  if cql_is_true(x) or cql_is_true(y) then
    return true    -- TRUE dominates
  elseif x == nil or y == nil then
    return nil     -- NULL propagates when result not determined
  else
    return false   -- both are false
  end
end
```

### C Code Generator Comparison

The C generator has similar complexity but different mechanics. From `cg_c.c`:

**Simple case** uses C's native `&&`:
```c
// Generated for: result = x AND y (non-nullable)
result.is_null = 0;
result.value = x.value && y.value;
```

**Complex case** uses explicit if-statement:
```c
// Generated for: result = x AND y (nullable or complex)
if (!cql_is_nullable_false(x.is_null, x.value)) {
  result.is_null = 0;
  result.value = 0;
}
else {
  // evaluate right side here
  if (!cql_is_nullable_false(r.is_null, r.value)) {
    result.is_null = 0;
    result.value = 0;
  }
  else {
    // both are not false, combine with three-valued logic
    ...
  }
}
```

The C version doesn't need function wrappers because C has proper short-circuit operators
at the language level that work with complex expressions.

### Why This Matters

Consider this CQL code:

```sql
DECLARE x, y INTEGER;
SET x := 0;
SET y := some_expensive_computation();

IF x AND y THEN
  -- should not execute
END IF;
```

**Incorrect Lua (naive)**: 
```lua
if x and y then  -- WRONG! Evaluates y even though x is 0 (truthy!)
```

**Correct Lua (generated)**:
```lua
if cql_to_bool(x) and cql_to_bool(y) then  -- Correct: y not evaluated
```

Even better, if `some_expensive_computation()` has side effects or could throw:

```lua
-- Generated with proper short-circuit:
if cql_shortcircuit_and(x, function() return some_expensive_computation() end) then
```

This ensures `some_expensive_computation()` is never called when `x` is 0.

The key insight: **Lua's value-returning operators combined with its unique truthiness rules
mean we can't directly translate CQL's boolean operators to Lua's operators.** We need
explicit conversion and careful short-circuit handling to maintain CQL's semantics.

## Switch Statements: No Native Support in Lua

One of the most striking differences between C and Lua code generation is how switch statements
are handled. C has native `switch/case` statements, but Lua does not. This requires the Lua
generator to simulate switch behavior using if-then chains.

### C Switch Generation

C code generation is straightforward. From `cg_c.c`:

```c
// CQL source:
SWITCH x
  WHEN 1 THEN
    do_one();
  WHEN 2, 3 THEN
    do_two_or_three();
  ELSE
    do_default();
END;

// Generated C code:
switch (x) {
  case 1:
    do_one();
    break;
    
  case 2:
  case 3:
    do_two_or_three();
    break;
    
  default:
    do_default();
    break;
}
```

The C generator uses `cg_switch_expr_list` to emit multiple `case` labels:

```c
static void cg_switch_expr_list(ast_node *ast, sem_t sem_type_switch_expr) {
  while (ast) {
    EXTRACT_ANY_NOTNULL(expr, ast->left);
    
    eval_node result = EVAL_NIL;
    eval(expr, &result);
    
    bprintf(cg_main_output, "case ");
    eval_format_number(&result, EVAL_FORMAT_FOR_C, cg_main_output);
    bprintf(cg_main_output, ":\n");
    
    ast = ast->right;
  }
}
```

This emits native C switch statements with optimal jump table performance.

### Lua Switch Generation: Emulated with If-Then-Else

Since Lua has no switch statement, the generator must create an equivalent structure
using if-then-else chains wrapped in a `repeat...until true` loop:

```lua
-- Same CQL source generates:
repeat
  local _tmp_int_0 = x
  
  if _tmp_int_0 == 1 then
    do_one()
    break
  end
  
  if _tmp_int_0 == 2 or _tmp_int_0 == 3 then
    do_two_or_three()
    break
  end
  
  -- default
  do_default()
until true
```

The key implementation details:

**1. Temporary variable to avoid re-evaluation:**
```c
// From cg_lua_switch_stmt:
CG_LUA_PUSH_TEMP(val, sem_type_expr);
CG_LUA_PUSH_EVAL(expr, LUA_EXPR_PRI_ROOT);
cg_lua_copy(cg_main_output, val.ptr, sem_type_expr, expr_value.ptr);
```

The switch expression is evaluated once and stored in a temporary. This ensures:
* Side effects only happen once
* Expensive computations aren't repeated
* Consistent semantics with C's switch (which also evaluates once)

**2. Repeat-until-true wrapper:**
```c
bprintf(cg_main_output, "repeat\n");
// ... cases ...
bprintf(cg_main_output, "until true\n");
```

This Lua idiom creates a scope that can be exited with `break`, mimicking C's switch
behavior. It's equivalent to C's `do { ... } while(0)` pattern but more idiomatic in Lua.

**3. Multiple values with OR chains:**

```c
static void cg_lua_switch_expr_list(ast_node *ast, sem_t sem_type_switch_expr, CSTR val) {
  bprintf(cg_main_output, "if ");
  
  while (ast) {
    EXTRACT_ANY_NOTNULL(expr, ast->left);
    
    eval_node result = EVAL_NIL;
    eval(expr, &result);
    
    bprintf(cg_main_output, "%s == ", val);
    eval_format_number(&result, EVAL_FORMAT_FOR_LUA, cg_main_output);
    
    if (ast->right) {
      bprintf(cg_main_output, " or ");  // Chain multiple cases with OR
    }
    
    ast = ast->right;
  }
  bprintf(cg_main_output, " then\n");
}
```

This generates: `if val == 2 or val == 3 then` for multi-value cases.

**4. Default case handling:**

The default case has no condition check - it simply executes if all other cases failed:

```c
// From cg_lua_switch_stmt:
if (connector->left) {
  // Regular case: emit condition
  cg_lua_switch_expr_list(expr_list, expr->sem->sem_type, val.ptr);
}
else {
  // Default case: just emit comment
  bprintf(cg_main_output, "-- default\n");
}
```

Since we're in a repeat-until loop, the default case naturally executes if no earlier
`break` was hit.

### Performance Implications

The C version has potential performance advantages:

**Jump table optimization**: Modern C compilers can optimize dense switch statements into
jump tables, giving O(1) lookup time regardless of the number of cases.

**Branch prediction**: Hardware branch predictors can learn switch patterns.

The Lua version must evaluate each case sequentially:

**Linear search**: Each case is checked in order until a match is found, giving O(n) time
for n cases.

**No compiler optimization**: Lua's interpreter can't build jump tables (though LuaJIT
might optimize some patterns).

However, in practice:
* Most switch statements have few cases (2-5), so the difference is negligible
* The simplicity of the generated code aids debugging
* Database operations dominate execution time anyway

### Why the Repeat-Until Pattern?

You might wonder: why not just use if-then-elseif?

```lua
-- Alternative (not used):
if x == 1 then
  do_one()
elseif x == 2 or x == 3 then
  do_two_or_three()
else
  do_default()
end
```

This would work for simple cases, but fails when WHEN clauses contain `LEAVE` or `CONTINUE`
statements that need to break out of an enclosing loop. The repeat-until wrapper provides
a consistent "break" target that matches C switch semantics.

Example:

```sql
WHILE condition
BEGIN
  SWITCH x
    WHEN 1 THEN LEAVE;  -- Should exit WHILE loop, not just switch
    WHEN 2 THEN /* ... */;
  END;
END;
```

With repeat-until:
```lua
while true do
  -- condition check
  repeat
    local _tmp_int_0 = x
    if _tmp_int_0 == 1 then
      break  -- Exits repeat-until (switch)
               -- Control returns to while loop, which then gets the LEAVE
    end
  until true
end
```

Actually, looking at the code more carefully, `LEAVE` maps to `break` which would break
out of the innermost loop. The repeat-until doesn't solve this - it's about providing
a consistent control flow structure. The real issue is that Lua's control flow is simpler
than C's, so we need the repeat-until to ensure `break` in a WHEN clause terminates
the switch, not an outer loop.

### WHEN ... THEN NOTHING Optimization

Both generators optimize away empty WHEN clauses unless there's a default case:

```sql
SWITCH x
  WHEN 1 THEN NOTHING;  -- Can be skipped
  WHEN 2 THEN do_two();
END;
```

```c
// no stmt list corresponds to WHEN ... THEN NOTHING
// we can skip the entire case set unless there is a default
// in which case we have to emit it with just break...
if (stmt_list || has_default) {
  // emit the case
}
```

If there's no statement list and no default, the entire case is omitted from the output.

### Summary

The switch statement illustrates a key code generation challenge: **translating a language
feature that exists natively in one target but not in another.** 

The C generator can use `switch/case` directly with all its performance benefits.

The Lua generator must **emulate** switch using if-then chains, which requires:
* Storing the switch expression in a temporary to avoid re-evaluation
* Wrapping everything in repeat-until for consistent `break` semantics
* Chaining multiple case values with `or` operators
* Special handling for the default case

Despite the complexity, the generated Lua code is clear, correct, and performs adequately
for typical use cases. The pattern demonstrates how higher-level constructs can be
decomposed into simpler primitives while maintaining the same semantics.

## Null Handling

### C Null Handling

In C, null checking requires different code paths for different types:

```c
// Nullable integer (struct-based):
if (x.is_null) {
  // handle null case
} else {
  // use x.value
}

// Reference type (pointer-based):
if (str == NULL) {
  // handle null case
} else {
  // use str
}
```

Comparisons must account for null. For example, `x == y` when both are nullable integers
requires comparing both the `is_null` flags and the values.

### Lua Null Handling

In Lua, null checking is uniform:

```lua
-- All types:
if x == nil then
  -- handle null case
else
  -- use x
end
```

This uniformity extends to comparisons. However, Lua's comparison semantics differ from
SQL's three-valued logic, so the generator must use helper functions:

```lua
-- From cg_lua.c - handling IS NULL:
if x == nil then ...  -- simple nil check

-- Handling equality with potential nulls:
-- Uses cql_is_null aware comparison helpers when needed
```

## Memory Management

### C Reference Counting

C requires explicit reference counting for strings, blobs, and objects. The pattern is:

```c
// Creating a reference:
cql_string_ref str = cql_string_ref_new("hello");

// Assigning:
cql_set_string_ref(&target, source);  // releases old target, retains source

// Releasing:
cql_string_release(str);
```

The code generator must track every reference type variable and emit proper cleanup code.
This happens in cleanup blocks (usually labeled `cql_cleanup:`).

### Lua Garbage Collection

Lua handles memory automatically. No reference counting needed:

```lua
-- Creating:
local str = "hello"

-- Assigning:
target = source  -- old value will be GC'd if no other references

-- No explicit release needed
```

This dramatically simplifies the generated code and eliminates a major class of potential
bugs (reference counting errors).

## SQLite Integration

Both generators interact with SQLite, but the details differ.

### C SQLite Calls

C code uses the SQLite C API directly:

```c
// Preparing a statement:
_rc_ = sqlite3_prepare_v2(_db_, "SELECT * FROM users", -1, &stmt, NULL);

// Stepping:
_rc_ = sqlite3_step(stmt);

// Getting values:
x.value = sqlite3_column_int(stmt, 0);
x.is_null = sqlite3_column_type(stmt, 0) == SQLITE_NULL;

// String (with retain):
cql_column_string_ref(stmt, 1, &str);  // macro that checks for NULL
```

Error handling is explicit via checking `_rc_`.

### Lua SQLite Calls

Lua code goes through a binding layer cqlrt.lua:

```lua
-- Preparing (via cql_prepare):
local stmt = cql_prepare(db, "SELECT * FROM users")

-- Stepping:
_rc_ = cql_step(stmt)

-- Getting values:
x = cql_get_int64(stmt, 0)  -- returns value or nil
str = cql_get_text(stmt, 1)  -- returns string or nil
```

The Lua runtime functions abstract the FFI/binding layer. They handle:
* Converting between Lua types and SQLite types
* Null checking (returning `nil` for SQL NULL)
* Error propagation

This makes the generated Lua code cleaner and more idiomatic.

## Expression Evaluation

### C Expression Evaluation

C expressions must manage both the value and null status separately. The code generator
uses a two-buffer approach:

```c
// From cg_c.c pattern:
CHARBUF_OPEN(is_null);  // holds "1" if null, "0" if not
CHARBUF_OPEN(value);    // holds the value expression
cg_expr(ast, &is_null, &value, pri);

// Example result for (x + y) where both are nullable int:
// is_null: "(x.is_null || y.is_null)"
// value: "(x.value + y.value)"
```

The caller must then combine these appropriately, often storing to a nullable struct:

```c
result.is_null = (x.is_null || y.is_null);
result.value = (x.value + y.value);  // only valid if !is_null
```

### Lua Expression Evaluation

Lua expressions evaluate to a single value (possibly `nil`). The code generator uses
helper functions to handle null propagation:

```c
// From cg_lua.c pattern:
CHARBUF_OPEN(value);  // holds the complete expression
cg_lua_expr(ast, &value, pri);

// Example result for (x + y):
// value: "cql_binary_add(x, y)"
```

The helper function `cql_binary_add` (in cqlrt.lua) handles the null propagation:

```lua
function cql_binary_add(l, r)
  if l == nil or r == nil then
    return nil
  end
  return l + r
end
```

This encapsulates the three-valued logic in the runtime library rather than generating
it inline, resulting in more readable code.

## Control Flow: Case/When Example

A concrete example illustrates the differences well. Consider this CQL:

```sql
SET result = CASE x
  WHEN 1 THEN 'one'
  WHEN 2 THEN 'two'
  ELSE 'other'
END;
```

### C Code Generation

```c
// Pseudocode based on cg_c.c patterns:
do {
  cql_nullable_int32 _tmp_n_int_0;  // temp for x
  cql_set_nullable_int32(_tmp_n_int_0, x);
  
  if (_tmp_n_int_0.is_null) {
    cql_set_string_ref_is_null(&result);
    break;
  }
  
  cql_string_ref _tmp_text_1 = NULL;  // temp for result
  
  if (_tmp_n_int_0.value == 1) {
    cql_set_string_ref(&_tmp_text_1, _literal_1_one);
    break;
  }
  
  if (_tmp_n_int_0.value == 2) {
    cql_set_string_ref(&_tmp_text_1, _literal_2_two);
    break;
  }
  
  cql_set_string_ref(&_tmp_text_1, _literal_3_other);
} while (0);

cql_set_string_ref(&result, _tmp_text_1);
cql_string_release(_tmp_text_1);
```

Note the complexity:
* Explicit null checking and propagation
* Reference counting (`cql_set_string_ref`, `cql_string_release`)
* do/while(0) wrapper to enable `break` for control flow
* Multiple temporary variables

### Lua Code Generation

```lua
-- Pseudocode based on cg_lua.c patterns:
repeat
  local _tmp_n_int_0 = x
  
  if _tmp_n_int_0 == nil then
    result = nil
    break
  end
  
  result = "one"  -- initial value (will be overwritten if needed)
  
  if _tmp_n_int_0 == 1 then
    break
  end
  
  if _tmp_n_int_0 == 2 then
    result = "two"
    break
  end
  
  result = "other"
until true
```

The Lua version is significantly simpler:
* Direct nil checking
* No reference counting
* Natural string literals
* repeat/until wrapper (Lua idiom equivalent to do/while(0))
* Fewer temporaries needed

## Scratch Variables

Both generators use "scratch variables" for intermediate results, but the approaches differ.

### C Scratch Variables

C generates typed scratch variables on demand, tracked by stack level and type:

```c
// From cg_c.c:
// _tmp_int_0, _tmp_int_1, ...        (non-nullable int)
// _tmp_n_int_0, _tmp_n_int_1, ...    (nullable int)
// _tmp_text_0, _tmp_text_1, ...      (text)
// _tmp_double_0, etc.
```

Each type requires separate tracking to avoid reusing a variable before it's safe.
Reference types require cleanup at the end of the scope.

### Lua Scratch Variables

Lua uses the same naming convention for consistency (making diffs between C and Lua
output comparable):

```lua
-- From cg_lua.c:
-- _tmp_int_0, _tmp_int_1, ...        (non-nullable number)
-- _tmp_n_int_0, _tmp_n_int_1, ...    (nullable number)
-- _tmp_text_0, _tmp_text_1, ...      (text)
```

But since Lua is dynamically typed, these are really just naming conventions. The
`_tmp_text_0` variable could hold any type at runtime; the name is for human readers
and to maintain parallel structure with the C output.

The comment in `cg_lua.c` explains:

```c
// This depth + type keying mirrors the C generator so diffs across
// backends remain comparable and stable. Deterministic naming helps
// golden-file tests and simplifies manual reasoning about temp reuse.
```

## Shared Infrastructure

Despite their differences, both generators share significant infrastructure:

### Common Code Generation Framework

Both use the same AST walking infrastructure from `cg_common.c`, plus:
* Statement dispatch tables (`cg_stmts` / `cg_lua_stmts`)
* Expression dispatch tables (`cg_exprs` / `cg_lua_exprs`)
* Function dispatch tables (`cg_funcs` / `cg_lua_funcs`)
* SQL generation via `gen_sql.c`

### Shared Patterns

Common patterns appear in both:
* `CG_PUSH_EVAL`/`CG_LUA_PUSH_EVAL` macros for evaluating expressions
* Stack level management to track temporary variable usage
* Cleanup labels and error handling via goto
* Statement numbering for prepared statements
* Fragment handling for shared CTEs

### SQL Statement Generation

Both generators use `gen_sql` to produce the SQL text. The SQL is the same; only
the binding differs:

```c
// C version:
_rc_ = sqlite3_bind_int(stmt, 1, x);

// Lua version (via runtime):
cql_bind_int64(stmt, 1, x)
```

## Why Two Generators?

The natural question: why maintain two code generators?

**Different deployment environments**: Some environments favor C (embedded systems,
performance-critical applications, static linking requirements). Others favor Lua
(scripting environments, sandboxed execution, rapid iteration).

**Runtime flexibility**: Lua's dynamic nature makes it easier to inspect and debug
at runtime. The Lua runtime can provide rich error messages and interactive debugging.

**Performance vs. simplicity**: C code is faster but more complex. Lua code is slower
but simpler and more maintainable. Different use cases have different priorities.

**Testing and validation**: Having two independent implementations of the same semantics
provides validation. If both generators produce equivalent behavior, it's strong evidence
that the semantics are correctly understood.

**Code as documentation**: The Lua generator serves as a simpler, more readable reference
implementation. When understanding what a complex CQL construct means, the Lua output
is often easier to read than the C output.

## Development Considerations

### Adding New Features

When adding a new feature to CQL:

1. **Semantic analysis** happens once, in `sem.c`
2. **SQL generation** happens once, in `gen_sql.c` (if applicable)`
3. **C code generation** must be implemented in `cg_c.c`
4. **Lua code generation** must be implemented in `cg_lua.c`

The two generators should produce equivalent behavior, but the code will look different
due to language differences.

### Testing Strategy

Tests use "golden files" - expected output for each backend. When you change code
generation:

1. Run tests: `make test`
2. If output changed intentionally: `./make_test_references.sh`
3. Review diffs carefully: `git diff sources/test/*.ref`

Having both C and Lua outputs helps catch bugs:
* If only one backend's output changed unexpectedly, it's likely a backend-specific bug
* If both changed similarly, it's likely correct (assuming the change was intended)

### Debugging Generated Code

**C debugging**: Compile with `-g`, use gdb/lldb:
```bash
$ cc -g -I. generated.c cqlrt.c test.c -lsqlite3
$ gdb ./a.out
```

**Lua debugging**: Run with lua debugger:
```bash
$ lua -l debugger generated.lua
```

The Lua version is often easier to debug interactively because you can inspect variables
at runtime without recompiling.

## Performance Characteristics

### C Performance

C code is significantly faster:
* Compiled to native code
* Static typing enables optimizations
* Direct SQLite API calls (no interpreter overhead)
* Minimal runtime library

Typical performance: microseconds per statement.

### Lua Performance

Lua code is slower but still practical:
* Interpreted (unless using LuaJIT)
* Dynamic typing prevents many optimizations
* FFI/binding layer overhead
* Runtime helper functions for null handling

Typical performance: 10-100x slower than C, but still fast enough for most applications
(milliseconds per statement).

The performance gap matters for high-throughput applications but is negligible for
typical database-driven applications where the database operations dominate.

## Conclusion

The C and Lua code generators demonstrate two different approaches to implementing the same
semantics:

**C** prioritizes performance and static safety. It maps CQL's type system directly to C
types, uses explicit null representation, and requires manual memory management. The result
is fast, type-safe code that integrates easily with existing C/C++ applications.

**Lua** prioritizes simplicity and flexibility. It leverages Lua's dynamic typing and
garbage collection to produce cleaner, more concise code. The runtime library handles
complexity that would otherwise appear in generated code.

Both generators share the same frontend (parsing, semantic analysis, SQL generation) and
use similar code generation patterns. Understanding the relationship between them helps
appreciate the design decisions in each and provides insight into how CQL's semantics
map to different runtime environments.

For developers working on CQL:
* Study both generators to understand language semantics
* Use the simpler Lua generator as a reference when the C generator is unclear
* Ensure new features work correctly in both backends
* Leverage the different strengths: C for production, Lua for debugging and prototyping
