# CG/SQL Testing Skills

This document provides practical skills for testing the CG/SQL compiler effectively.

## Running Tests

### Basic Test Execution

```bash
# Run full test suite
cd sources
./test.sh

# The script will:
# 1. Build the compiler
# 2. Run all test files (test.sql, sem_test.sql, cg_test.sql, etc.)
# 3. Compare outputs to .ref files
# 4. Report differences
```

### Test with Different Compilers

```bash
# Test with GCC (default)
./test.sh --use_gcc

# Test with Clang
./test.sh --use_clang

# Test amalgam build
./test.sh --use_amalgam

# Test with address sanitizer (finds memory errors)
./test.sh --use_asan

# Combine options
./test.sh --use_clang --use_asan
```

### Running Specific Tests

```bash
# Run just one test file
./test.sh --test sem_test

# Run a specific test case by filtering
# (Look for "TEST: test_name" comments in .sql files)
./test.sh 2>&1 | grep -A 20 "TEST: my_test_name"
```

### Understanding Test Output

When tests fail, you'll see:

```
FAILED: sem_test
Expected output in: sem_test.out.ref
Actual output in:   sem_test.out
Diff saved to:      sem_test.out.diff
```

**Workflow:**
1. Examine the diff: `cat out/sem_test.out.diff`
2. If changes are correct: Accept them (test.sh will prompt)
3. If changes are wrong: Fix the bug and rerun

### Test File Structure

```sql
-- TEST: descriptive_test_name
-- This comment describes what we're testing
-- + expected output pattern
-- - pattern that should NOT appear
-- Expected error on next line
CREATE PROC bad_proc()
BEGIN
  -- Invalid SQL that should error
END;
```

**Test directives:**
- `-- TEST: name` - Marks start of a test
- `-- + pattern` - Output must contain this pattern
- `-- - pattern` - Output must NOT contain this pattern
- `-- Error at line N` - Expect error at specific line

## Code Coverage

### Running Coverage Analysis

```bash
cd sources

# Generate coverage report
./cov.sh

# This will:
# 1. Clean previous coverage data
# 2. Rebuild with coverage flags (GCC only)
# 3. Run all tests
# 4. Generate HTML report in out/coverage/
```

### Viewing Coverage Results

```bash
# Open coverage report in browser
# On WSL:
explorer.exe out/coverage/index.html

# On Linux:
firefox out/coverage/index.html

# On macOS:
open out/coverage/index.html
```

### Understanding Coverage Output

The report shows:
- **Line coverage** - Which lines were executed
- **Function coverage** - Which functions were called
- **Branch coverage** - Which branches were taken

**Required:** 100% line coverage for all code

### Coverage Tips

**Finding uncovered code:**
1. Open `out/coverage/index.html`
2. Sort by "Lines" column (ascending)
3. Click files with < 100% coverage
4. Red/pink lines were not executed

**Adding coverage:**
1. Write test case that exercises uncovered lines
2. Add to appropriate test file (sem_test.sql, cg_test.sql, etc.)
3. Run `./cov.sh` to verify
4. Repeat until 100%

**Common uncovered areas:**
- Error paths (need tests that trigger errors)
- Edge cases (empty lists, NULL values, etc.)
- Platform-specific code (may need conditional tests)

### Coverage Gotchas

**Coverage requires GCC:**
```bash
# This works
./cov.sh

# This doesn't produce coverage
./test.sh --use_clang
```

**Coverage data from previous runs:**
```bash
# Always clean before coverage run
make clean
./cov.sh
```

**Amalgam doesn't show detailed coverage:**
```bash
# Don't use amalgam for coverage analysis
./test.sh --use_amalgam  # Wrong for coverage
./cov.sh                 # Right for coverage
```

## Adding New Tests

### Step 1: Choose the Right Test File

| File | Purpose |
|------|---------|
| `test/test.sql` | Parser/syntax tests |
| `test/sem_test.sql` | Semantic analysis (type checking, validation) |
| `test/cg_test.sql` | C code generation |
| `test/run_test.sql` | Runtime execution (actually runs generated code) |
| `test/query_plan_test.sql` | Query plan generation |

### Step 2: Write the Test

```sql
-- TEST: test_nullable_comparison
-- Testing that nullable integer comparison works correctly
-- + cql_nullable_int32
-- + cql_combine_nullables

CREATE PROC test_nullable_comp(x INTEGER, y INTEGER)
BEGIN
  DECLARE result BOOL NOT NULL;
  SET result := (x == y);
END;
```

### Step 3: Run and Accept

```bash
# Run tests
./test.sh

# You'll see:
# NEW OUTPUT for test_nullable_comparison
# 
# Accept changes? (y/n)

# If output looks correct, type: y

# Test script updates .ref file
```

### Step 4: Verify Coverage

```bash
# Check that new test increased coverage
./cov.sh

# Look for the file you modified
# Should now show higher coverage %
```

## Test Patterns

### Testing Errors

```sql
-- TEST: error_duplicate_column
-- Attempting to create table with duplicate column names
-- Should produce error CQL0123

CREATE TABLE bad_table(
  id INTEGER,
  id INTEGER  -- Duplicate!
);
```

**Expected output:**
```
Error at line 7: CQL0123: duplicate column name 'id'
```

### Testing Code Generation

```sql
-- TEST: codegen_cursor_fetch
-- Verify cursor fetch generates correct C code
-- + sqlite3_step
-- + SQLITE_ROW
-- + cql_multifetch

CREATE PROC fetch_example()
BEGIN
  DECLARE C CURSOR FOR SELECT 1 AS x;
  FETCH C;
END;
```

**Checks:**
- Generated C contains `sqlite3_step`
- Generated C contains `SQLITE_ROW`
- Generated C contains `cql_multifetch`

### Testing Runtime Behavior

```sql
-- In run_test.sql
-- TEST: runtime_arithmetic
-- Verify basic arithmetic works at runtime

CREATE PROC test_math()
BEGIN
  DECLARE x INTEGER NOT NULL;
  SET x := 2 + 3;
  -- Result should be 5
  CALL printf("%d\n", x);
END;

-- Expected output: 5
```

## Debugging Test Failures

### Understanding Test Failure Messages

```
FAILED: sem_test
--- sem_test.out.ref
+++ sem_test.out
@@ -1234,7 +1234,7 @@
-expected line
+actual line
```

**Interpretation:**
- Lines with `-` are what was expected (from .ref)
- Lines with `+` are what was actually generated
- `@@ -1234,7 +1234,7 @@` shows line numbers

### Isolating Test Cases

**Extract failing test:**
```bash
# 1. Find the test in the .sql file
grep -n "TEST: failing_test" test/sem_test.sql

# 2. Copy just that test to a new file
cat > /tmp/isolated.sql << 'EOF'
-- TEST: failing_test
CREATE PROC test()
BEGIN
  -- ... test code ...
END;
EOF

# 3. Run compiler directly
out/cql --in /tmp/isolated.sql --cg /tmp/out.c 2>&1
```

### Comparing Outputs

```bash
# View the diff
cat out/sem_test.out.diff | less

# Side-by-side comparison
diff -y out/sem_test.out.ref out/sem_test.out | less

# Just show differences
diff --suppress-common-lines out/sem_test.out.ref out/sem_test.out
```

### Regenerating Reference Files

**When output is correct but different:**
```bash
# Option 1: Accept during test run
./test.sh
# Answer 'y' when prompted

# Option 2: Manual copy (if you're sure)
cp out/sem_test.out out/sem_test.out.ref

# Option 3: Regenerate all (dangerous!)
rm out/*.ref
./test.sh  # Will create new .ref files
```

**⚠️ Warning:** Only accept changes when you're certain the new output is correct!

## Performance Testing

### Timing Tests

```bash
# Time the test suite
time ./test.sh

# Time specific test
time out/cql --in test/sem_test.sql --cg /dev/null 2>&1
```

### Memory Testing

```bash
# Use address sanitizer
./test.sh --use_asan

# Use valgrind (if available)
valgrind --leak-check=full out/cql --in test.sql --cg /dev/null
```

### Large Input Testing

```bash
# Generate large test file
for i in {1..1000}; do
  echo "CREATE PROC test_$i() BEGIN SELECT 1; END;"
done > /tmp/large.sql

# Test compilation
out/cql --in /tmp/large.sql --cg /tmp/large.c
```

## Continuous Testing During Development

### Watch Mode (Manual)

```bash
# In one terminal, watch for changes
while true; do
  inotifywait -e modify sources/*.c sources/*.h
  clear
  make && ./test.sh --test sem_test
  sleep 1
done
```

### Incremental Testing

```bash
# After modifying semantic analyzer:
make && ./test.sh --test sem_test

# After modifying C codegen:
make && ./test.sh --test cg_test

# After modifying parser:
make && ./test.sh --test test
```

### Quick Sanity Check

```bash
# Minimal test to verify compiler builds and works
make && echo "SELECT 1;" | out/cql --in - --cg /dev/null
```

## Test Organization Tips

### Grouping Related Tests

```sql
-- In sem_test.sql

-- ========================================
-- SECTION: Nullable type checking
-- ========================================

-- TEST: nullable_int_comparison
-- ...

-- TEST: nullable_text_concatenation
-- ...

-- TEST: nullable_in_if_condition
-- ...

-- ========================================
-- SECTION: Cursor operations
-- ========================================
```

### Using Attributes for Test Control

```sql
-- TEST: test_private_proc
-- Verify @attribute(cql:private) works
-- + static void

@attribute(cql:private)
CREATE PROC private_helper()
BEGIN
  SELECT 1;
END;
```

### Documenting Complex Tests

```sql
-- TEST: complex_shared_fragment
-- Testing shared fragments with:
-- 1. Multiple parameters
-- 2. Nested CTEs
-- 3. Conditional logic
--
-- This reproduces bug #1234 where fragment inlining
-- would fail with complex CTEs.
--
-- Expected: Should inline correctly and generate valid SQL
```

## Common Testing Mistakes

### ❌ Don't: Test without cleaning first

```bash
# Bad - might have stale build artifacts
./test.sh
```

```bash
# Good - clean build
make clean && ./test.sh
```

### ❌ Don't: Accept changes without reviewing

```bash
# Bad - blindly accepting
./test.sh  # Answer 'y' without looking
```

```bash
# Good - review first
./test.sh
cat out/sem_test.out.diff  # Review changes
# Then decide whether to accept
```

### ❌ Don't: Test only with one compiler

```bash
# Bad - only GCC
./test.sh
```

```bash
# Good - test both
./test.sh --use_gcc && ./test.sh --use_clang
```

### ❌ Don't: Forget coverage

```bash
# Bad - add feature without coverage
# (Write code, run tests, commit)
```

```bash
# Good - verify coverage
# (Write code, run tests, run coverage, commit)
./test.sh && ./cov.sh
```

## Cheat Sheet

```bash
# Quick reference for common tasks

# Build and test
make && ./test.sh

# Test specific file
./test.sh --test sem_test

# Coverage check
./cov.sh

# Test with sanitizer
./test.sh --use_asan

# Test with both compilers
./test.sh --use_gcc && ./test.sh --use_clang

# Run compiler directly
out/cql --in myfile.sql --cg out.c

# Isolate test case
grep -A 20 "TEST: mytest" test/sem_test.sql > /tmp/test.sql
out/cql --in /tmp/test.sql --cg /tmp/out.c 2>&1

# View coverage report
./cov.sh && explorer.exe out/coverage/index.html

# Clean everything
make clean
```

## Summary

**Golden Rules:**
1. ✅ Always run `./test.sh` before committing
2. ✅ Always check `./cov.sh` shows 100% coverage
3. ✅ Test with both GCC and Clang
4. ✅ Review diffs before accepting changes
5. ✅ Add tests for every bug fix
6. ✅ Add tests for every new feature
7. ✅ Clean build before important tests
8. ✅ Use address sanitizer for memory issues

**Test File Selection:**
- Parser issues → `test/test.sql`
- Type checking → `test/sem_test.sql`
- Code generation → `test/cg_test.sql`
- Runtime behavior → `test/run_test.sql`
- Query plans → `test/query_plan_test.sql`

**When in doubt:**
- Look at similar existing tests
- Run coverage to find untested code
- Isolate the problem to a minimal test case
- Debug with lldb (see copilot-debugging.md)
