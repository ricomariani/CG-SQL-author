# CG/SQL Documentation Summary

Created: 2026-01-26

This is a comprehensive set of documentation files created to help GitHub Copilot (and developers) understand and work with the CG/SQL codebase effectively.

## What Was Created

### Five Documentation Files (55KB total)

1. **README.md** (5.4 KB) - You are here
   - Overview and navigation guide
   - Quick start examples
   - Key principles

2. **copilot-instructions.md** (7.2 KB) - Daily workflow reference
   - Build/test procedures
   - Code style conventions
   - File organization
   - Platform-specific notes
   - Quick reference commands

3. **copilot-architecture.md** (9.2 KB) - Compiler internals
   - Compilation pipeline details
   - AST structure and philosophy
   - Semantic analysis (2-phase, type system)
   - All code generators explained
   - Memory management strategies
   - Error handling patterns

4. **copilot-ast-conventions.md** (13.8 KB) - Working with the AST
   - Complete EXTRACT macro reference
   - Type checking macros
   - Common coding patterns
   - Error handling
   - Complete working examples

5. **copilot-extending.md** (19.8 KB) - Adding new backends
   - JSON schema as universal IR
   - Direct vs. JSON-based approaches
   - Case studies of all existing generators
   - Step-by-step guides
   - Design considerations
   - Future directions

## How to Use This Documentation

### For Understanding the Codebase

**Start here:**
1. Read `README.md` (this file) for overview
2. Scan `copilot-instructions.md` for basics
3. Deep dive into `copilot-architecture.md` for specific areas
4. Keep `copilot-ast-conventions.md` open as reference

### For Making Changes

**Bug fixes:**
1. `copilot-instructions.md` → workflow and testing
2. `copilot-architecture.md` → find relevant subsystem
3. `copilot-ast-conventions.md` → correct AST manipulation
4. Run `./test.sh` and `./cov.sh`

**New features:**
1. `copilot-architecture.md` → understand pipeline stage
2. `copilot-ast-conventions.md` → implement with patterns
3. `copilot-instructions.md` → follow constraints
4. Add tests, ensure 100% coverage

**New code generator:**
1. `copilot-extending.md` → complete guide
2. `copilot-architecture.md` → case studies
3. `copilot-ast-conventions.md` → AST walking
4. Study existing generators in `sources/cg_*.c`

## Key Insights About CG/SQL

### The Design Philosophy

**Classic Compiler Architecture:**
```
CQL Source → [Lexer] → Tokens
          → [Parser] → AST
          → [Semantic Analysis] → Typed AST
          → [Code Generator] → C/Lua/JSON/etc.
```

**String-Based AST:**
- Node types are strings, not enums
- Enables flexible pattern matching
- Simpler tree structure
- Easy to add new node types

**Pool-Based Allocation:**
- All AST nodes from memory pools
- No individual frees
- Entire pool freed at end
- Fast allocation, zero fragmentation

**100% Test Coverage:**
- Every line of code must be tested
- Reference-based test validation
- Pattern matching for flexibility
- Coverage enforced by `cov.sh`

### The EXTRACT Patterns

These macros are **essential** to CG/SQL development:

```c
// Basic extraction
EXTRACT(select_stmt, ast->left);           // Creates 'select_stmt'
EXTRACT_NOTNULL(expr, ast->right);         // Must not be NULL

// Strings and values
EXTRACT_STRING(table_name, name_ast);      // Get identifier
EXTRACT_NUM_TYPE(num_type, num_node);      // Get numeric type
EXTRACT_DETAIL(flags, flags_node);         // Get integer flags

// Scoped names
EXTRACT_NAME_AND_SCOPE(node);              // Creates 'name' and 'scope'

// Statements with attributes
EXTRACT_STMT_AND_MISC_ATTRS(stmt, attrs, list);
```

**Why they matter:**
- Type-safe AST traversal
- Self-documenting code
- Catches errors early (via Contract)
- Consistent patterns across codebase

### Extensibility Model

**Two Paths to New Backends:**

1. **JSON-Based (Recommended for most cases)**
   - CQL → JSON schema (stable contract)
   - External tool (Python/Go/etc.) → Target code
   - Examples: Java bindings, diagrams, documentation
   - Pros: Simple, decoupled, language-agnostic
   - Cons: No AST access, extra step

2. **Direct AST Generator**
   - Walk AST directly in C
   - Generate code on the fly
   - Examples: C, Lua, Query Plan, Schema Upgrader
   - Pros: Complete control, single pass, fast
   - Cons: Complex, coupled to compiler, harder to maintain

**Key Insight:** The semantic analyzer does the hard work (type checking, validation). Your generator just transforms validated AST to target language.

## Common Tasks Reference

### Building and Testing

```bash
# Build
cd sources && make clean && make

# Test everything
cd sources && ./test.sh

# Test with Clang
cd sources && ./test.sh --use_clang

# Check coverage (must be 100%)
cd sources && ./cov.sh

# Test amalgam build
cd sources && ./test.sh --use_amalgam
```

### Code Generation Examples

```bash
# Generate C code
cql --in input.sql --cg output.c --rt c

# Generate Lua code
cql --in input.sql --cg output.lua --rt lua

# Generate JSON schema
cql --in input.sql --rt json_schema --cg output.json

# Generate query plans
cql --in input.sql --rt query_plan --cg plans.c
```

### Working with JSON

```bash
# Generate and view JSON
cql --in schema.sql --rt json_schema --cg schema.json
cat schema.json | jq .

# Create diagram from JSON
python sources/cqljson/cqljson.py --erd schema.json > diagram.dot
dot diagram.dot -Tpdf -o diagram.pdf

# Generate Java bindings
python sources/java_demo/cqljava.py schema.json \
  --package com.example \
  --class Database > Database.java
```

## Project Statistics

**Lines of Code (approximate):**
- `cg_c.c` - ~30,000 lines (C code generator)
- `sem.c` - ~40,000 lines (semantic analysis)
- `cg_lua.c` - ~15,000 lines (Lua code generator)
- `cg_json_schema.c` - ~2,500 lines (JSON output)
- `ast.c` - ~8,000 lines (AST construction)

**Total:** ~200,000 lines of C code + tests

**Test Files:**
- `test.sql` - Parser tests
- `sem_test.sql` - Semantic tests
- `cg_test.sql` - C codegen tests
- `run_test.sql` - Runtime tests
- `query_plan_test.sql` - Query plan tests

## Anti-Patterns to Avoid

Based on analysis of the codebase and documentation:

❌ **Don't:**
- Manually access `ast->left` or `ast->right` - use EXTRACT macros
- Add features without 100% test coverage
- Make sweeping changes - be surgical
- Use C++ features - this is ANSI C
- Call `exit()` from library code
- Assume SQLite version-specific behavior
- Break backwards compatibility without discussion
- Submit without running `./test.sh` and `./cov.sh`
- Modify `.ref` files manually - regenerate via test.sh
- Create temporary markdown files in repo for planning

✅ **Do:**
- Use EXTRACT macros for type-safe AST access
- Follow existing patterns in similar code
- Add Contract/Invariant assertions liberally
- Check `is_error()` after processing children
- Use 2-space indentation, snake_case names
- Study existing code before adding similar features
- Ask clarifying questions if requirements unclear
- Test incrementally as you develop

## Contributing

The documentation is meant to be living. If you find:
- Missing information
- Incorrect patterns
- Areas needing clarification
- New insights about the codebase

Please update these files to keep them accurate and helpful.

## License

All CG/SQL code and documentation is MIT licensed.

---

**Created:** January 26, 2026
**Based on:** CG/SQL codebase analysis and existing documentation
**Purpose:** Enable GitHub Copilot and developers to understand and extend CG/SQL effectively

**Files in this directory:**
- `README.md` - This overview
- `copilot-instructions.md` - Daily workflow reference
- `copilot-architecture.md` - Compiler internals
- `copilot-ast-conventions.md` - AST manipulation guide
- `copilot-extending.md` - Adding new backends

**Total:** 55 KB of curated technical documentation
