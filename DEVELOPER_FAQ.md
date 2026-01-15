---
title: Developer FAQ
weight: 6
---

# CG/SQL Developer FAQ

Frequently asked questions for CG/SQL contributors and developers. For user questions, see the [User FAQ](USER_FAQ.md).

## Getting Started with Development

### How do I build CG/SQL from source?

```bash
cd sources
make clean
make
```

The compiler binary will be at `out/cql`.

**Platform-specific requirements:**
- **macOS**: Install newer bison and flex via Homebrew
- **Linux**: Install build tools (gcc, make, flex, bison, sqlite3-dev)

**Complete guide:**
- [Getting Started](docs/quick_start/getting-started.md)
- [Requirements](docs/quick_start/getting-started.md#requirements)

### What's the typical development workflow?

1. Make your changes to source files (`.y`, `.l`, `.c`, `.h`)
2. Add test cases to appropriate test files
3. Run `./test.sh` to compile and test
4. Accept diffs when output is correct
5. Ensure 100% code coverage with `./cov.sh`
6. Test with both GCC and Clang

**Step-by-step:**
- [Developer Notes](docs/contributors/dev_notes.md)
- [Testing Guide](docs/contributors/testing.md)

**Example workflow:**
```bash
# Edit sources/sem.c to add feature
vim sources/sem.c

# Add test case
vim sources/test/sem_test.sql

# Run tests
./test.sh

# Check coverage
./cov.sh

# Test with clang
./test.sh --use_clang
```

### What test scripts are available?

| Command | Purpose |
|---------|---------|
| `./test.sh` | Build and run full test suite |
| `./test.sh --use_amalgam` | Test amalgam build |
| `./test.sh --use_asan` | Enable address sanitizer |
| `./test.sh --use_clang` | Build with Clang |
| `./test.sh --use_gcc` | Build with GCC |
| `./cov.sh` | Generate code coverage report |

**Documentation:**
- [Testing](docs/contributors/testing.md)
- [Code Coverage](docs/contributors/code-coverage.md)
- [Test Details](docs/developer_guide/04_testing.md)

## Architecture and Code Organization

### What's the overall architecture of CG/SQL?

CG/SQL follows a classic compiler pipeline:

1. **Lexing/Parsing** (`cql.l`, `cql.y`) → AST
2. **Semantic Analysis** (`sem.c`) → Decorated AST
3. **Code Generation** (`cg_*.c`) → Output (C/Lua/JSON/etc.)

**Deep dive:**
- [Building the AST](docs/developer_guide/01_building_the_ast.md)
- [Semantic Analysis](docs/developer_guide/02_semantic_analysis.md)
- [C Code Generation](docs/developer_guide/03_c_code_generation.md)

### What are the main source files and their purposes?

| File | Purpose |
|------|---------|
| `cql.y` | Yacc grammar (parser) |
| `cql.l` | Lex scanner (lexer) |
| `ast.h` | AST node definitions |
| `ast.c` | AST construction |
| `sem.c` | Semantic analysis (type checking, validation) |
| `cg_c.c` | C code generation |
| `cg_lua.c` | Lua code generation |
| `cg_json_schema.c` | JSON schema output |
| `cg_schema.c` | Schema upgrade generation |
| `gen_sql.c` | SQL echo (pretty printing) |
| `charbuf.c` | String buffer utilities |
| `symtab.c` | Symbol table |
| `list.c` | List data structure |

**Learn more:**
- [Developer Guide Overview](docs/developer_guide/_index.md)

### How do I add a new AST node type?

1. Define the node structure in `ast.h`
2. Add grammar rule in `cql.y`
3. Add semantic analysis in `sem.c`
4. Add code generation in appropriate `cg_*.c` file
5. Add tests in `test/sem_test.sql` and `test/cg_test.sql`

**Example from docs:**
```c
// In ast.h
typedef struct my_new_node {
  ast_node *left;
  ast_node *right;
  int32_t flags;
} my_new_node;
```

**Complete guide:**
- [Building the AST](docs/developer_guide/01_building_the_ast.md)
- [Dev Workflow](docs/contributors/dev_notes.md)

## Semantic Analysis

### How does semantic analysis work?

Semantic analysis decorates the AST with type information stored in `sem_node`:

```c
struct sem_node {
  sem_t sem_type;        // Core type (integer, text, etc.)
  CSTR name;             // Name if applicable
  CSTR kind;             // Additional classification
  // ... more fields
};
```

Each AST node gets a `sem` pointer during analysis.

**Deep dive:**
- [Semantic Analysis Chapter](docs/developer_guide/02_semantic_analysis.md)

### How does type checking work?

CG/SQL uses a bottom-up approach:
1. Leaf nodes get types from literals/variables
2. Operators combine child types with compatibility rules
3. Type errors reported immediately

**Key function pattern:**
```c
static void sem_my_operation(ast_node *ast) {
  // Analyze children first
  sem_expr(ast->left);
  sem_expr(ast->right);
  
  // Check for previous errors
  if (is_error(ast->left) || is_error(ast->right)) {
    record_error(ast);
    return;
  }
  
  // Type compatibility check
  if (!compatible_types(ast->left->sem->sem_type, 
                        ast->right->sem->sem_type)) {
    report_error(...);
    record_error(ast);
    return;
  }
  
  // Set result type
  ast->sem = new_sem(result_type);
}
```

**Learn more:**
- [Semantic Analysis](docs/developer_guide/02_semantic_analysis.md)

### How are symbols resolved?

Symbol resolution uses a symbol table stack:
- Global scope for tables, procedures
- Local scope for variables, parameters
- Scope pushes on procedure entry, pops on exit

**Documentation:**
- [Name Resolution](docs/developer_guide/02_semantic_analysis.md)
- [Symbol Table](docs/developer_guide/02_semantic_analysis.md)

## Code Generation

### How does C code generation work?

The `cg_c.c` file walks the semantically analyzed AST and emits C code to a character buffer:

**Key patterns:**
```c
// Emit a statement
static void cg_my_statement(ast_node *ast) {
  bprintf(cg_main_output, "  // My statement\n");
  cg_expr(ast->left);
  bprintf(cg_main_output, ";\n");
}

// Emit an expression
static void cg_my_expr(ast_node *ast, charbuf *output) {
  bprintf(output, "(");
  cg_expr(ast->left, output);
  bprintf(output, " + ");
  cg_expr(ast->right, output);
  bprintf(output, ")");
}
```

**Complete guide:**
- [C Code Generation](docs/developer_guide/03_c_code_generation.md)

### How does the Lua code generator differ from C?

Key differences:
- **No manual memory management**: Lua is garbage collected
- **Dynamic typing**: Runtime conversions instead of compile-time
- **Different boolean semantics**: `nil` and `false` are falsy; everything else is truthy
- **No pointers**: Use tables and references

**Documentation:**
- [Lua Code Generation](docs/developer_guide/10_lua_notes.md)

### How do I add a new code generator output?

1. Create new file `cg_myformat.c`
2. Implement main entry point: `cql_emit_myformat(ast_node *root)`
3. Walk AST and emit to output buffers
4. Add command-line option in `cql.y` (main function)
5. Add tests in `test/` directory

**Reference existing generators:**
- [JSON Generation](docs/developer_guide/07_json_generation.md)
- [Query Plan Generation](docs/developer_guide/09_query_plan.md)

## Testing

### What are the main test files?

| Test File | Purpose |
|-----------|---------|
| `test/test.sql` | Parser/syntax tests |
| `test/sem_test.sql` | Semantic analysis tests |
| `test/cg_test.sql` | C code generation tests |
| `test/run_test.sql` | Runtime execution tests |
| `test/query_plan_test.sql` | Query plan tests |
| `unit_tests.c` | C unit tests |

**Learn more:**
- [Testing Chapter](docs/developer_guide/04_testing.md)

### How do I add a new test case?

1. Add test SQL to appropriate file (e.g., `sem_test.sql`)
2. Add expected output pattern using `@EXPECT_*` directives
3. Run `./test.sh`
4. Review diff output
5. Accept diff if correct: `./test.sh` will prompt

**Example:**
```sql
-- Add to sem_test.sql
-- TEST: my_feature
-- Test description
create proc test_my_feature()
begin
  -- test code
end;
-- @EXPECT_ERROR MY_ERROR_CODE

-- Result: 1
```

**Documentation:**
- [Testing](docs/developer_guide/04_testing.md)
- [Test Patterns](docs/contributors/testing.md)

### How does test output validation work?

Two mechanisms:

1. **Reference comparison**: Generated output compared to `.ref` files
2. **Pattern matching**: `@EXPECT_*` directives in test files

Pattern matching catches regressions even if reference changes.

**Learn more:**
- [Testing Strategy](docs/developer_guide/04_testing.md)

### What code coverage is expected?

**100% line coverage** is required. Run `./cov.sh` to generate report.

The report shows:
- Coverage by file
- Uncovered lines

**Guide:**
- [Code Coverage](docs/contributors/code-coverage.md)

## Runtime System

### What's in the CQL runtime?

The runtime (`cqlrt.h`, `cqlrt.c`) provides:

- Reference counting for strings/blobs/objects
- Result set infrastructure
- Type definitions
- Error handling helpers

**Two flavors:**
- `cqlrt.c`: Basic/default runtime
- `cqlrt_cf.c`: CoreFoundation runtime (Apple platforms)
- `cqlrt_common.c`: Shared helpers that use the above to provide the rest of the runtime

**Documentation:**
- [CQL Runtime](docs/developer_guide/05_cql_runtime.md)

### Can I customize the runtime?

Yes! You can:
- Implement your own reference counting
- Use different string/blob/numeric types
- Override error handling
- Provide custom allocators

Use `--rt c` and provide your own runtime implementation.

**Learn more:**
- [Runtime Customization](docs/developer_guide/05_cql_runtime.md)

## Schema Management

### How does schema upgrade generation work?

CG/SQL analyzes `@create` and `@delete` annotations:

1. Computes schema versions
2. Generates upgrade procedures for each version
3. Handles dependencies between tables/views/triggers
4. Emits DDL in correct order

**Generated code example:**
```c
void cql_schema_upgrade_v5() {
  // Generated migration code
}
```

**Complete guide:**
- [Schema Management](docs/developer_guide/06_schema_management.md)

### How are schema regions handled?

Regions create logical groupings:
- Dependencies tracked between regions
- Can generate separate upgrade procedures per region
- Supports partial schema deployment

**Learn more:**
- [Schema Management](docs/developer_guide/06_schema_management.md)

## Contributing

### What's the code style?

- classic ANSI C
- 2-space indentation
- Descriptive variable names
- Comments for complex logic, focus on the why not the what
- Follow existing patterns

### How do I submit changes?

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Ensure `./test.sh` and `./cov.sh` pass
5. Test with `--use_clang` and `--use_gcc`
6. Submit pull request

**Guidelines:**
- [Contributing](CONTRIBUTING.md)
- [Developer Notes](docs/contributors/dev_notes.md)

### What should I know about the amalgam?

The amalgam (`cql_amalgam.c`) is a single-file distribution:
- Generated by `make_amalgam.sh`
- Easier to integrate in other projects
- Must be tested: `./test.sh --use_amalgam`

**Documentation:**
- [Using the Amalgam](docs/user_guide/appendices/09_using_the_cql_amalgam.md)

## Advanced Topics

### How does the pre-processor work?

CG/SQL has a built-in pre-processor (not C preprocessor):

- `@macro`: Define macros
- `@include`: Include files
- `@ifdef`/`@ifndef`: Conditional compilation
- `@text`/`@id`: Token pasting

**Details:**
- [Pre-processing](docs/user_guide/18_pre_processing/)

### How does shared fragment inlining work?

Shared fragments are inlined at semantic analysis time:
1. Fragment proc analyzed separately
2. At call site, fragment's SELECT is substituted
3. Variables remapped to calling context
4. Type checking ensures compatibility

**Learn more:**
- [Shared Fragments](docs/user_guide/14_shared_fragments.md)

### How does JSON output work?

The JSON generator (`cg_json_schema.c`) emits structured metadata:

- Table schemas
- Procedure signatures
- Query shapes
- Dependencies

Describes what the CQL compiler saw; can be used for diagrams,
change tracking, even interoperability.

**Documentation:**
- [JSON Output](docs/developer_guide/07_json_generation.md)
- [JSON Python Tools](docs/developer_guide/11_json_python_tools.md)

### How are query plans generated?

Query plan generation (`cg_query_plan.c`):
1. Transforms CQL to executable SQL
2. Wraps queries in `EXPLAIN QUERY PLAN`
3. Generates procedures that extract plans
4. Handles CQL-specific features (shared fragments, etc.)

**Complete guide:**
- [Query Plan Generation](docs/developer_guide/09_query_plan.md)

## Debugging

### How do I debug the compiler itself?

**Techniques:**
1. Add `printf` debugging in compiler code
2. Use `--dev` flag for verbose output
3. Run under debugger: `gdb out/cql`
4. Examine generated AST (use echo modes)
5. Add temporary test cases

**Tips:**
- Print AST nodes: Look at `gen_sql.c` for tree walking patterns
- Check `sem_node` contents during semantic analysis
- Examine symbol tables

### How do I visualize the AST?

Use the dotpdf script:
```bash
./dotpdf.sh myfile.sql
```

This generates a PDF visualization of the AST.

**Learn more:**
- [AST Visualization](docs/developer_guide/01_building_the_ast.md)

### What if tests are failing?

1. Check error output carefully
2. Review generated `.out` files vs `.ref` files
3. Look for pattern matching failures
4. Ensure you rebuilt after source changes
5. Check for platform-specific issues (SQLite version)

**Common issues:**
- SQLite version differences (especially query plans)
- Line ending differences (Windows vs Unix)
- Bison/flex version differences

## Performance

### How can I optimize CQL code generation?

The compiler focuses on correctness over micro-optimization. Generated C code is:
- Readable and debuggable
- Relies on C compiler optimization
- Minimal abstraction overhead

**Best practices:**
- Trust the C compiler's optimizer
- Profile generated code as needed
- Focus on query optimization (use EXPLAIN QUERY PLAN)

### How does the compiler handle large schemas?

- Symbol tables use hash maps (efficient lookup)
- AST nodes allocated from pools
- Single-pass compilation
- No global optimization passes

Large schemas (1000+ tables) compile efficiently.

## Getting Help

### Where can I get help with development?

- [GitHub Issues](https://github.com/ricomariani/CG-SQL-author/issues)
- [GitHub Discussions](https://github.com/ricomariani/CG-SQL-author/discussions)
- Read the [Developer Guide](docs/developer_guide/_index.md)
- Review existing code patterns

### How can I propose new features?

1. Open a GitHub issue with your proposal
2. Discuss design approach
3. Consider backwards compatibility
4. Prototype if helpful
5. Submit PR with tests and documentation

### Where can I learn more?

- [Developer Guide](docs/developer_guide/_index.md) - Complete internals documentation
- [User Guide](docs/user_guide/_index.md) - Language reference
- [CG/SQL Blog](https://github.com/ricomariani/CG-SQL-author/wiki/CG-SQL-Blog) - Updates and articles
- Source code - Well-commented and readable
