# CG/SQL Debugging Skills

This document provides practical skills for debugging the CG/SQL compiler using lldb in WSL.

## Quick Start: Debugging a Crash

### The Typical Debugging Workflow

When the compiler crashes, follow this progression:

1. **Reproduce the crash** - Get the exact command that fails
2. **Run under lldb** - Get the stack trace
3. **Examine the stack** - Find the failed invariant
4. **Inspect variables** - Look at values in frames
5. **Dump AST nodes** - Use helper functions to understand tree structure
6. **Add print statements** - If still unclear, trace execution flow

### Step 1: Reproduce the Crash

```bash
cd sources

# Find the failing test
./test.sh 2>&1 | grep -B 5 "FAILED\|Segmentation fault\|Aborted"

# Note the test case that crashed
# Look in the test output for the command that was run
```

**Example output:**
```
Running: out/cql --in test/sem_test.sql --cg out/sem_test.out
Segmentation fault (core dumped)
FAILED: sem_test
```

### Step 2: Run Under lldb

```bash
# Start lldb with the compiler
lldb out/cql

# In lldb, run with the same arguments
(lldb) run --in test/sem_test.sql --cg out/sem_test.out

# Crash will occur, showing:
Process 1234 stopped
* thread #1, name = 'cql', stop reason = signal SIGSEGV: invalid address
```

### Step 3: Get the Stack Trace

```lldb
# Get backtrace (also: backtrace, where)
(lldb) bt

# Output shows the call stack:
* thread #1:
  frame #0: 0x00007f... cql`sem_validate_compatable_table_columns
  frame #1: 0x00007f... cql`sem_create_table_stmt
  frame #2: 0x00007f... cql`sem_stmt_list
  frame #3: 0x00007f... cql`sem_main
  frame #4: 0x00007f... cql`main
```

**Reading the backtrace:**
- Frame #0 is where the crash occurred
- Subsequent frames show how we got there
- Usually the invariant is in frame #0 or #1

### Step 4: Examine the Crash Frame

```lldb
# Frame 0 is already selected, or select it explicitly
(lldb) frame select 0
(lldb) f 0  # Short form

# See the source code and crash location
(lldb) list

# Output:
   1234    Contract(ast);
   1235    Contract(is_ast_create_table_stmt(ast));
-> 1236    Contract(ast->sem);  // ← Crash here!
   1237    
   1238    EXTRACT_NOTNULL(table_flags, ast->left);
```

### Step 5: Inspect Variables

```lldb
# Print variable values
(lldb) p ast
(ast_node *) $0 = 0x00007fff...

(lldb) p *ast
(ast_node) $1 = {
  type = 0x00007fff... "create_table_stmt"
  left = 0x00007fff...
  right = 0x00007fff...
  sem = 0x0000000000000000  # ← NULL! This is the problem!
  parent = 0x00007fff...
  lineno = 42
  filename = 0x00007fff... "test/sem_test.sql"
}

# The invariant expects ast->sem to be non-NULL
# But it's NULL, so Contract fails
```

### Step 6: Examine Other Frames

```lldb
# Move up the stack to see context
(lldb) frame select 1
(lldb) f 1  # Short form

# See caller's code
(lldb) list

# Print variables from this frame
(lldb) p table_name
(const char *) $2 = 0x00007fff... "my_table"

# Move back down
(lldb) f 0
```

## Advanced Debugging Techniques

### Using AST Helper Functions

The compiler provides several helper functions in `ast.c` for debugging:

```lldb
# Print the entire AST tree
(lldb) call print_root_ast(ast)

# Print a specific AST node
(lldb) call print_ast(ast, NULL, 0, 0)

# Print AST with parent context
(lldb) call print_ast(ast, ast->parent, 2, 0)
```

**Example output:**
```
{create_table_stmt}
  | {table_flags}
  |   | {detail}: 0x3  (TABLE_IF_NOT_EXISTS | TABLE_IS_TEMP)
  | {table_and_columns}
      | {str}: "my_table"
      | {col_key_list}
          | {col_def}
          ...
```

### Dumping Semantic Information

```lldb
# Print semantic node
(lldb) call print_sem_type(ast->sem)

# Output:
# integer notnull variable

# Print full semantic node structure
(lldb) p *ast->sem
(sem_node) $3 = {
  sem_type = 0x0000000000000005  # Flags: INTEGER | NOT_NULL
  name = 0x00007fff... "x"
  kind = NULL
  error = NULL
  sptr = NULL
  jptr = NULL
  create_version = 0
  delete_version = 0
  ...
}
```

### Examining Symbol Tables

```lldb
# Print symbol table contents
(lldb) p *current_variables
(symtab) $4 = {
  count = 3
  capacity = 16
  payload = 0x00007fff...
}

# Find symbol in table
(lldb) call symtab_find(current_variables, "my_var")
(symtab_entry *) $5 = 0x00007fff...

# Print symbol value
(lldb) p ((symtab_entry *)$5)->val
(void *) $6 = 0x00007fff...  # Points to ast_node
```

### Setting Breakpoints

```lldb
# Break on function
(lldb) breakpoint set --name sem_create_table_stmt
(lldb) b sem_create_table_stmt  # Short form

# Break on file:line
(lldb) breakpoint set --file sem.c --line 1234
(lldb) b sem.c:1234  # Short form

# Break on condition
(lldb) b sem_expr -c 'ast->type == "add"'

# List breakpoints
(lldb) breakpoint list
(lldb) br list  # Short form

# Delete breakpoint
(lldb) breakpoint delete 1
(lldb) br del 1  # Short form

# Disable/enable
(lldb) breakpoint disable 1
(lldb) breakpoint enable 1
```

### Stepping Through Code

```lldb
# Step into (follow calls)
(lldb) step
(lldb) s  # Short form

# Step over (don't follow calls)
(lldb) next
(lldb) n  # Short form

# Step out (return from current function)
(lldb) finish
(lldb) f  # Short form (careful: also means frame!)

# Continue execution
(lldb) continue
(lldb) c  # Short form
```

### Watchpoints (Watch Variable Changes)

```lldb
# Watch when a variable changes
(lldb) watchpoint set variable ast->sem
(lldb) w s v ast->sem  # Short form

# Watch memory location
(lldb) watchpoint set expression -- &ast->sem

# List watchpoints
(lldb) watchpoint list

# Delete watchpoint
(lldb) watchpoint delete 1
```

## Debugging Specific Problems

### Problem: Contract/Invariant Failure

**Symptoms:** Assertion failure, "Contract failed" message

```lldb
# Run under lldb
(lldb) run --in test.sql --cg out.c

# When it crashes:
(lldb) bt

# Look for Contract or Invariant in the backtrace
# frame #0: sem.c:1234 Contract(ast->sem)

# Examine the condition
(lldb) p ast->sem
# (sem_node *) $0 = NULL  ← This is why it failed

# Move up the stack to see why sem is NULL
(lldb) f 1
(lldb) list

# Look for where ast->sem should have been set
```

**Common causes:**
- Forgot to call `sem_something()` to analyze a node
- Error occurred but not properly propagated
- Wrong AST structure (missing expected child)

### Problem: Memory Corruption

**Symptoms:** Random crashes, invalid pointers, strange values

```lldb
# Use address sanitizer first!
# Rebuild with ASAN:
make clean
./test.sh --use_asan

# If ASAN doesn't catch it, use watchpoints
(lldb) run --in test.sql --cg out.c
(lldb) watchpoint set variable suspicious_ptr
(lldb) c

# When watchpoint triggers:
(lldb) bt  # See who modified it
(lldb) frame info  # See the exact line
```

### Problem: Wrong Generated Code

**Symptoms:** Generated C code is incorrect

```lldb
# Break in the code generator
(lldb) b cg_expr

# Run until breakpoint
(lldb) run --in test.sql --cg out.c

# When it breaks:
(lldb) p ast->type
# (const char *) $0 = "add"

# Print the AST
(lldb) call print_ast(ast, NULL, 0, 0)

# Step through to see what gets generated
(lldb) n
(lldb) n

# Check output buffer
(lldb) p cg_main_output->ptr
# (const char *) $1 = "...generated code so far..."
```

### Problem: Parser Creates Wrong AST

**Symptoms:** Semantic analysis fails unexpectedly

```lldb
# Set breakpoint after parsing
(lldb) b sem_main
(lldb) run --in test.sql --cg out.c

# When it breaks, dump the AST
(lldb) call print_root_ast(ast)

# Compare to expected structure
# Look for:
# - Wrong node types
# - Missing children
# - Unexpected NULL pointers
```

### Problem: Infinite Loop

**Symptoms:** Compiler hangs

```bash
# Run under lldb
lldb out/cql
(lldb) run --in test.sql --cg out.c

# Wait a bit, then Ctrl+C to interrupt
^C

# Get backtrace to see where it's spinning
(lldb) bt

# Look at the code
(lldb) list

# Check loop variables
(lldb) p item
(lldb) p item->next

# Set breakpoint inside loop to see iterations
(lldb) b sem.c:1234
(lldb) c
(lldb) c  # Each continue shows another iteration

# Watch for changing values
(lldb) p depth
```

## Adding Print Statement Debugging

Sometimes lldb isn't enough and you need to trace execution flow.

### Adding Debug Prints

```c
// In sem.c or cg_c.c

static void sem_my_function(ast_node *ast) {
  // Add debug output
  printf("DEBUG: sem_my_function called\n");
  printf("DEBUG: ast->type = %s\n", ast->type);
  printf("DEBUG: ast->lineno = %d\n", ast->lineno);
  
  EXTRACT_NOTNULL(child, ast->left);
  printf("DEBUG: child->type = %s\n", child->type);
  
  // Your normal code
  sem_expr(child);
  
  printf("DEBUG: sem_my_function done\n");
}
```

### Conditional Debug Output

```c
// Add a debug flag
static bool debug_mode = false;

#define DEBUG_PRINT(...) if (debug_mode) printf(__VA_ARGS__)

static void sem_expr(ast_node *ast) {
  DEBUG_PRINT("DEBUG: sem_expr: %s at line %d\n", ast->type, ast->lineno);
  
  // Normal code...
}

// Enable with environment variable or flag
int main(int argc, char **argv) {
  debug_mode = getenv("CQL_DEBUG") != NULL;
  // ...
}
```

### Using Debug Output

```bash
# Rebuild with your debug prints
make clean && make

# Run with debug output
CQL_DEBUG=1 out/cql --in test.sql --cg out.c 2>&1 | less

# Filter output
CQL_DEBUG=1 out/cql --in test.sql --cg out.c 2>&1 | grep "sem_expr"

# Save to file
CQL_DEBUG=1 out/cql --in test.sql --cg out.c 2>&1 > debug.log
```

## WSL-Specific Tips

### Running lldb in WSL

```bash
# Install lldb if not present
sudo apt-get update
sudo apt-get install lldb

# Check version
lldb --version

# Run lldb
lldb out/cql
```

### WSL Paths

```lldb
# Use Linux-style paths in lldb
(lldb) run --in /home/user/test.sql --cg /tmp/out.c

# Not Windows-style paths
(lldb) run --in C:\Users\...  # Won't work!
```

### Viewing Source Files

```bash
# If lldb can't find source files, set the path
(lldb) settings set target.source-map /old/path /new/path

# Or use absolute paths
(lldb) settings set target.source-map /sources /mnt/v/home/ricomariani/CG-SQL/sources
```

### Editor Integration

```bash
# In WSL, you can use VS Code to view files
code sem.c:1234  # Opens file at line 1234

# Or use vim/emacs in separate terminal
vim +1234 sem.c
```

## Common Debugging Patterns

### Pattern: Find Where Variable Gets Set

```lldb
# Set watchpoint on variable
(lldb) run --in test.sql --cg out.c
(lldb) b sem_main
(lldb) c

# Now watch the variable
(lldb) watchpoint set variable current_proc
(lldb) c

# Watchpoint will trigger when variable changes
# Examine the stack to see why
(lldb) bt
(lldb) f 0
(lldb) list
```

### Pattern: Find Who Calls a Function

```lldb
# Set breakpoint on function
(lldb) b rare_function
(lldb) run --in test.sql --cg out.c

# When it breaks, check the caller
(lldb) bt

# frame #0: rare_function
# frame #1: some_caller  ← This is who called it
# frame #2: some_caller's_caller

# Examine caller's state
(lldb) f 1
(lldb) list
(lldb) p local_var
```

### Pattern: Trace Execution Path

```lldb
# Break at start of interesting code
(lldb) b sem_select_stmt
(lldb) run --in test.sql --cg out.c

# Step through and print state
(lldb) n
(lldb) p ast->type
(lldb) n
(lldb) p ast->left->type
(lldb) n

# Or use breakpoints at key points
(lldb) b sem_from_clause
(lldb) b sem_where_clause
(lldb) b sem_select_expr_list
(lldb) c  # Continue to next breakpoint
```

### Pattern: Compare Expected vs Actual

```lldb
# Break at point where AST should be formed
(lldb) b sem_create_proc_stmt
(lldb) run --in test.sql --cg out.c

# Dump the AST
(lldb) call print_ast(ast, NULL, 0, 0)

# Compare to what you expected
# Look for differences in:
# - Node types
# - Tree structure
# - Child relationships
```

## Debugging Checklist

When investigating a bug:

- [ ] Reproduce the crash reliably
- [ ] Note the exact command line that fails
- [ ] Run under lldb
- [ ] Get backtrace with `bt`
- [ ] Examine frame 0 with `f 0` and `list`
- [ ] Check variable values with `p var`
- [ ] Look at AST with `call print_ast(ast, NULL, 0, 0)`
- [ ] Check semantic node with `call print_sem_type(ast->sem)`
- [ ] Move up stack with `f 1`, `f 2`, etc.
- [ ] Set breakpoints at suspicious functions
- [ ] Use watchpoints for variable changes
- [ ] Add debug prints if still unclear
- [ ] Compare AST to expected structure
- [ ] Check symbol tables if name resolution involved
- [ ] Verify Contract/Invariant assumptions

## Cheat Sheet

```lldb
# Start debugging
lldb out/cql
(lldb) run --in test.sql --cg out.c

# Navigation
bt              # Backtrace
f 0             # Select frame 0
f 1             # Select frame 1
list            # Show source code

# Inspection
p var           # Print variable
p *var          # Dereference pointer
call func(arg)  # Call function

# AST helpers
call print_ast(ast, NULL, 0, 0)       # Print AST node
call print_root_ast(ast)              # Print entire tree
call print_sem_type(ast->sem)         # Print semantic type

# Breakpoints
b function_name                  # Break on function
b file.c:123                     # Break on line
b function -c 'var == value'     # Conditional break
br list                          # List breakpoints
br del 1                         # Delete breakpoint

# Stepping
n               # Next (step over)
s               # Step (step into)
finish          # Step out
c               # Continue

# Watchpoints
w s v var       # Watch variable
w list          # List watchpoints
w del 1         # Delete watchpoint
```

## Summary

**The debugging progression:**
1. `bt` - Get the stack trace
2. `f 0` - Look at crash site
3. `p var` - Check variable values
4. `call print_ast(ast, NULL, 0, 0)` - Dump AST
5. `f 1`, `f 2` - Check callers
6. Add debug prints if needed

**Most bugs are:**
- Failed invariants (NULL where shouldn't be)
- Wrong AST structure
- Missing semantic analysis
- Type mismatches
- Symbol table issues

**Remember:**
- Use `--use_asan` for memory bugs
- Use coverage to find untested code
- Isolate to minimal test case
- Compare AST to expected structure
- Check both the code and the test
