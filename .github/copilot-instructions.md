# CG/SQL Copilot Instructions

## Quick Reference

**See also:**
- [Architecture Deep Dive](copilot-architecture.md) - Detailed compiler internals
- [AST Coding Conventions](copilot-ast-conventions.md) - EXTRACT macros and patterns

## Project Overview

CG/SQL is a **code generation system** for SQLite that compiles stored procedures written in a T-SQL variant into C or Lua code. It's a classic compiler with lexing, parsing, semantic analysis, and multiple code generation backends.

**Key Facts:**
- Language: C (ANSI C style, 2-space indentation)
- Primary output: C code that uses SQLite's C API
- Secondary outputs: Lua, JSON schema, query plans, test helpers
- Build system: GNU Make
- Testing: Comprehensive test suite with 100% coverage requirement
- Platform: Linux/macOS primary, WSL supported

## Architecture

### Compiler Pipeline

1. **Lexing/Parsing** → AST
   - `cql.l` (Lex scanner)
   - `cql.y` (Yacc parser)
   - `ast.h/ast.c` (AST construction)

2. **Semantic Analysis** → Decorated AST
   - `sem.c/sem.h` (type checking, validation)
   - Bottom-up type analysis
   - Symbol table management

3. **Code Generation** → Output files
   - `cg_c.c` - C code generation
   - `cg_lua.c` - Lua code generation
   - `cg_json_schema.c` - JSON metadata
   - `cg_schema.c` - Schema upgrade procedures
   - `cg_query_plan.c` - Query plan extraction
   - `gen_sql.c` - SQL echo/pretty printing

### Key Source Files

| File | Purpose |
|------|---------|
| `cql.y` | Parser grammar (Yacc/Bison) |
| `cql.l` | Lexer rules (Lex/Flex) |
| `ast.h` | AST node type definitions |
| `sem.c` | Semantic analysis engine |
| `cg_c.c` | C code generator |
| `charbuf.c` | String buffer utilities |
| `symtab.c` | Symbol table |
| `cqlrt.h/c` | Runtime library |

### Data Structures

**AST Node** (`ast_node` in `ast.h`):
- Simple string-based node types (not enums)
- Left/right child pointers
- `sem_node` pointer added during analysis

**Semantic Node** (`sem_node` in `sem.h`):
- Type information (`sem_t` - 64-bit flags)
- Name, kind (for objects)
- Struct/join pointers for complex types
- Version and region metadata

**Symbol Table** (`symtab.h/c`):
- Hash-based lookup
- Scoped (stack of tables)
- Used for procedures, tables, variables

## Development Workflow

### Building
```bash
cd sources
make clean
make
```
Binary output: `sources/out/cql`

### Testing
```bash
cd sources
./test.sh                    # Full test suite
./test.sh --use_clang        # Test with Clang
./test.sh --use_amalgam      # Test amalgam build
./cov.sh                     # Code coverage (must be 100%)
```

### Test Files Location
- `sources/test/test.sql` - Parser tests
- `sources/test/sem_test.sql` - Semantic analysis tests
- `sources/test/cg_test.sql` - Code generation tests
- `sources/test/run_test.sql` - Runtime execution tests
- `sources/unit_tests.c` - C unit tests

### Adding Tests
1. Add test code to appropriate `.sql` file
2. Use `@EXPECT_*` directives for validation
3. Run `./test.sh`
4. Review and accept diffs when correct
5. Ensure coverage with `./cov.sh`

## Code Style

- **Language**: Classic ANSI C
- **Indentation**: 2 spaces (no tabs)
- **Naming**: Descriptive, snake_case
- **Comments**: Focus on WHY, not WHAT; comment complex logic only
- **Pattern**: Follow existing code patterns
- **Headers**: Include copyright notice (MIT license)

## Common Tasks

### Adding a New Language Feature

1. **Grammar** (`cql.y`): Add production rule
2. **AST** (`ast.h`): Define node structure if needed
3. **Semantic Analysis** (`sem.c`): Add validation/type checking
4. **Code Generation** (`cg_*.c`): Implement output generation
5. **Tests**: Add to `sem_test.sql` and `cg_test.sql`
6. **Coverage**: Ensure 100% with `./cov.sh`

### Adding a New Code Generator

1. Create `cg_myformat.c` and `cg_myformat.h`
2. Implement `cql_emit_myformat(ast_node *root)`
3. Add command-line option in `cql.y` main function
4. Add tests in `test/` directory
5. Update documentation

### Debugging

**Compiler debugging:**
- Add `printf` in compiler code
- Use `--dev` flag for verbose output
- Run under `gdb out/cql`
- Use `./dotpdf.sh file.sql` for AST visualization

**Generated code debugging:**
- Check `.c` output files
- Compile with `-g` for debugging symbols
- Use test cases to isolate issues

## Important Constraints

### Code Changes
- Make **minimal** changes only
- Don't fix unrelated bugs
- Follow existing patterns strictly
- Validate changes don't break existing behavior

### Testing Requirements
- 100% line coverage is mandatory
- Test with both GCC and Clang
- Test amalgam build
- All existing tests must pass

### File Organization
- Runtime: `cqlrt.h`, `cqlrt.c`, `cqlrt_common.c`
- Utilities: `charbuf.c`, `symtab.c`, `list.c`, `bytebuf.c`
- Tests: All in `sources/test/` directory
- Output: Generated files go to `sources/out/`

## Build System Details

**Makefile targets:**
- `make` - Build compiler
- `make clean` - Clean build artifacts
- `make test` - Run tests (via test.sh)

**Amalgam:**
- Single-file distribution: `cql_amalgam.c`
- Generated by `make_amalgam.sh`
- Must be tested separately

## Platform Notes

### WSL (Current Environment)
- Repository at: `\\wsl$\Ubuntu\home\ricomariani\CG-SQL`
- Use Windows-style paths (backslashes) in tools
- PowerShell commands work with WSL filesystem
- Git operations are cross-platform compatible

### macOS Requirements
- Install newer bison/flex via Homebrew
- May need to set PATH for correct versions

### Linux Requirements
- gcc, make, flex, bison
- sqlite3-dev package

## Schema Management

CG/SQL includes sophisticated schema versioning:
- `@create(n)` and `@delete(n)` annotations
- Schema regions for modular deployment
- Automatic upgrade procedure generation
- Dependency tracking

See `cg_schema.c` for implementation.

## Runtime System

Two flavors:
- `cqlrt.c` - Default/basic runtime
- `cqlrt_cf.c` - CoreFoundation (Apple platforms)
- `cqlrt_common.c` - Shared helpers

Provides:
- Reference counting (strings, blobs, objects)
- Result set infrastructure
- Type definitions
- Error handling

Runtime is customizable via `--rt` flag.

## Documentation

Essential docs (already in repo):
- `README.md` - Overview and links
- `DEVELOPER_FAQ.md` - Developer Q&A
- `USER_FAQ.md` - User Q&A
- `CONTRIBUTING.md` - Contribution guidelines
- `docs/` - Full documentation (Hugo-based site)

Online docs: https://ricomariani.github.io/CG-SQL-author/

## Quick Reference Commands

```bash
# Build and test
cd sources && make && ./test.sh

# Coverage check
cd sources && ./cov.sh

# Test specific file
cd sources && ./cql --in test.sql --cg out.c

# Visualize AST
cd sources && ./dotpdf.sh test.sql

# Run with address sanitizer
cd sources && ./test.sh --use_asan
```

## Anti-Patterns to Avoid

❌ Don't use C++ features
❌ Don't exit() from library code
❌ Don't assume SQLite version-specific behavior
❌ Don't break backwards compatibility without discussion
❌ Don't add dependencies without justification
❌ Don't submit without 100% coverage
❌ Don't modify generated reference files manually
