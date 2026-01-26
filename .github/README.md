# CG/SQL GitHub Copilot Documentation

This directory contains specialized documentation for GitHub Copilot to understand the CG/SQL codebase.

## Files

### [copilot-instructions.md](copilot-instructions.md)
**Main reference for day-to-day work with CG/SQL**

Covers:
- Project overview and architecture summary
- Build and test workflows
- Code style conventions
- File organization
- Development constraints
- Platform-specific notes (WSL, macOS, Linux)
- Quick reference commands

**Use this for:** Getting started, understanding the workflow, knowing what constraints to follow.

### [copilot-architecture.md](copilot-architecture.md)
**Deep dive into compiler internals**

Covers:
- Compilation flow details
- AST structure and design philosophy
- Semantic analysis process (two-phase, type system)
- Code generation patterns (C, Lua, JSON, Schema)
- Runtime system (reference counting, result sets)
- Memory management (pools, string interning)
- Error handling strategies
- Pre-processing system
- Testing infrastructure
- Build system details
- Performance characteristics

**Use this for:** Understanding how the compiler works internally, adding features, debugging complex issues.

### [copilot-testing.md](copilot-testing.md)
**Practical skills for testing the CG/SQL compiler**

Covers:
- Running tests (./test.sh with various options)
- Code coverage analysis (./cov.sh)
- Adding new tests to appropriate files
- Test patterns and directives
- Debugging test failures
- Performance and memory testing
- Continuous testing workflows
- Common testing mistakes to avoid

**Use this for:** Running tests, adding test cases, ensuring coverage, validating changes.

### [copilot-debugging.md](copilot-debugging.md)
**Comprehensive debugging guide using lldb in WSL**

Covers:
- Step-by-step crash debugging workflow
- Using lldb commands (bt, f, p, call)
- AST helper functions for inspection
- Debugging specific problems (Contract failures, memory corruption, wrong codegen)
- Setting breakpoints and watchpoints
- Adding debug print statements
- WSL-specific tips
- Common debugging patterns and checklists

**Use this for:** Investigating crashes, finding Contract violations, tracing execution, understanding AST structure.

### [copilot-extending.md](copilot-extending.md)
**Complete guide to adding new code generation targets**

Covers:
- JSON schema as universal intermediate representation
- Direct code generator approach vs. JSON-based approach
- Case studies: C, Lua, JSON Schema, Query Plan generators
- Step-by-step guide for adding new backends
- Type system mapping strategies
- Memory management considerations
- Hybrid approaches (JSON + codegen)
- Future evolution (compiler as library, plugins)
- Practical recommendations and checklists

**Use this for:** Adding support for new languages (Rust, Go, C#, etc.), creating custom code generators, understanding the extensibility model.

### [copilot-ast-conventions.md](copilot-ast-conventions.md)
**Essential guide to working with the AST**

Covers:
- Complete EXTRACT macro reference
  - `EXTRACT`, `EXTRACT_NOTNULL`, `EXTRACT_NAMED`, etc.
  - `EXTRACT_STRING`, `EXTRACT_NUM_TYPE`, `EXTRACT_DETAIL`
  - `EXTRACT_NAME_AND_SCOPE` for qualified names
  - `EXTRACT_STMT` and attribute handling
- Type checking macros (`is_ast_*` family)
- Common coding patterns (binary expressions, lists, flags)
- Contract and Invariant assertions
- Error handling patterns
- AST rewrite macros
- Semantic node access
- Complete working examples

**Use this for:** Writing or modifying any code that touches the AST (which is most of the compiler).

## How to Use These Docs

### For New Features

1. Read **copilot-instructions.md** to understand the workflow
2. Study **copilot-architecture.md** for the relevant pipeline stage
3. Reference **copilot-ast-conventions.md** for coding patterns
4. Look at similar existing code in the source files
5. Add tests following the patterns in test files

### For Bug Fixes

1. Use **copilot-instructions.md** to understand testing
2. Check **copilot-architecture.md** for the relevant subsystem
3. Use **copilot-ast-conventions.md** for correct AST manipulation
4. Run `./test.sh` and `./cov.sh` to validate

### For Code Understanding

1. Start with **copilot-instructions.md** for overview
2. Dive into **copilot-architecture.md** for specific areas
3. Keep **copilot-ast-conventions.md** handy as a reference

## Key Principles

From these docs, the most important things to remember:

1. **Use EXTRACT macros** - Never manually access AST nodes
2. **100% coverage required** - All code must be tested
3. **Minimal changes** - Surgical modifications only
4. **Follow patterns** - Look at existing code
5. **Contract liberally** - Catch bugs in debug builds
6. **Error propagation** - Check `is_error()` after processing children
7. **Classic C style** - 2-space indent, descriptive names, ANSI C

## Additional Resources

Official documentation (in the main repo):
- `README.md` - Getting started
- `DEVELOPER_FAQ.md` - Q&A for developers
- `CONTRIBUTING.md` - Contribution guidelines
- `docs/developer_guide/` - Complete developer guide
- `docs/user_guide/` - Language reference

Online: https://ricomariani.github.io/CG-SQL-author/

## Contributing to These Docs

These instruction files are meant to help Copilot understand the codebase. If you find:
- Missing information
- Incorrect patterns
- Areas needing clarification

Please update these files to keep them accurate and helpful.

## Quick Start Example

Here's a complete example of adding a new semantic analysis function:

```c
// In sem.c
static void sem_my_new_stmt(ast_node *ast) {
  Contract(is_ast_my_new_stmt(ast));
  
  // Extract the tree structure (see AST conventions doc)
  EXTRACT_NOTNULL(name_ast, ast->left);
  EXTRACT(optional_clause, ast->right);
  EXTRACT_STRING(name, name_ast);
  
  // Validate
  if (!valid_name(name)) {
    report_error(ast, "CQL9999: invalid name", name);
    record_error(ast);
    return;
  }
  
  // Process optional parts
  if (optional_clause) {
    sem_optional_clause(optional_clause);
    if (is_error(optional_clause)) {
      record_error(ast);
      return;
    }
  }
  
  // Success
  ast->sem = new_sem(SEM_TYPE_OK);
}
```

Then add tests in `sources/test/sem_test.sql` and verify with:
```bash
cd sources
./test.sh
./cov.sh
```

That's it! These docs should help you navigate the entire CG/SQL codebase effectively.
