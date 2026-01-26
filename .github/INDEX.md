# CG/SQL Copilot Documentation Index

**Total Documentation: 91 KB across 8 files**

Quick access to all documentation:

## Core Documentation (4 files)

### 📘 [copilot-instructions.md](copilot-instructions.md) - 7.2 KB
**Daily reference for working with CG/SQL**
- Build system and workflows
- Code style and conventions  
- File organization
- Platform notes
- Quick commands

### 🏗️ [copilot-architecture.md](copilot-architecture.md) - 9.2 KB
**Deep dive into compiler internals**
- Compilation pipeline
- AST structure
- Semantic analysis
- Code generators
- Memory management
- Runtime system

### 🔧 [copilot-ast-conventions.md](copilot-ast-conventions.md) - 13.8 KB
**Essential AST manipulation guide**
- EXTRACT macro reference
- Type checking macros
- Coding patterns
- Error handling
- Working examples

### 🚀 [copilot-extending.md](copilot-extending.md) - 19.8 KB
**Adding new backends and targets**
- JSON schema approach
- Direct codegen approach
- Case studies (C, Lua, JSON, Query Plan)
- Type mapping strategies
- Step-by-step guides

## Testing & Debugging (2 files)

### 🧪 [copilot-testing.md](copilot-testing.md) - 11.7 KB
**Testing the compiler**
- Running tests (./test.sh)
- Coverage analysis (./cov.sh)
- Adding tests
- Test patterns
- Common mistakes

### 🐛 [copilot-debugging.md](copilot-debugging.md) - 14.4 KB
**Debugging with lldb**
- Crash debugging workflow
- lldb commands (bt, f, p, call)
- AST inspection helpers
- Breakpoints and watchpoints
- Debug print statements
- WSL-specific tips

## Meta Documentation (2 files)

### 📋 [README.md](README.md) - 6.5 KB
**Overview and navigation**
- How to use the documentation
- File descriptions
- Quick start examples
- Key principles

### 📊 [SUMMARY.md](SUMMARY.md) - 8.0 KB
**Complete project summary**
- What was created
- Key insights
- Common tasks
- Anti-patterns
- Future directions

---

## Quick Navigation by Task

### I want to...

**...understand the codebase**
→ Start with [README.md](README.md), then [copilot-architecture.md](copilot-architecture.md)

**...build and test**
→ [copilot-instructions.md](copilot-instructions.md) + [copilot-testing.md](copilot-testing.md)

**...write code that touches the AST**
→ [copilot-ast-conventions.md](copilot-ast-conventions.md) (keep it open!)

**...debug a crash**
→ [copilot-debugging.md](copilot-debugging.md)

**...add a feature**
→ [copilot-architecture.md](copilot-architecture.md) → [copilot-ast-conventions.md](copilot-ast-conventions.md) → [copilot-testing.md](copilot-testing.md)

**...add a new language target**
→ [copilot-extending.md](copilot-extending.md)

**...ensure code quality**
→ [copilot-testing.md](copilot-testing.md) (100% coverage required!)

---

## Quick Reference Card

### Essential Commands
```bash
# Build
cd sources && make

# Test
./test.sh
./test.sh --use_clang
./test.sh --use_asan

# Coverage (must be 100%)
./cov.sh

# Debug
lldb out/cql
(lldb) run --in test.sql --cg out.c
(lldb) bt
(lldb) call print_ast(ast, NULL, 0, 0)
```

### Essential Macros
```c
EXTRACT(type, node)
EXTRACT_NOTNULL(type, node)
EXTRACT_STRING(name, node)
EXTRACT_NAME_AND_SCOPE(node)
```

### Essential Invariants
- ✅ Use EXTRACT macros, never manual AST access
- ✅ 100% test coverage required
- ✅ Contract/Invariant assertions everywhere
- ✅ Check is_error() after processing children
- ✅ Test with both GCC and Clang
- ✅ Clean build before important tests

---

## Documentation Statistics

| File | Size | Lines | Purpose |
|------|------|-------|---------|
| copilot-instructions.md | 7.2 KB | ~200 | Daily workflows |
| copilot-architecture.md | 9.2 KB | ~250 | Internals deep dive |
| copilot-ast-conventions.md | 13.8 KB | ~400 | AST patterns |
| copilot-extending.md | 19.8 KB | ~600 | Adding backends |
| copilot-testing.md | 11.7 KB | ~350 | Testing guide |
| copilot-debugging.md | 14.4 KB | ~450 | Debugging guide |
| README.md | 6.5 KB | ~180 | Navigation |
| SUMMARY.md | 8.0 KB | ~230 | Project summary |
| **Total** | **91 KB** | **~2,660** | **Complete reference** |

---

## Contributing to These Docs

Found an error? Missing information? Have suggestions?

**Please update the relevant file!**

These docs are meant to be living documentation that evolves with the codebase. Keep them accurate and helpful for future developers and Copilot sessions.

---

## Original Source Documentation

These files complement (but don't replace) the official documentation:

- `README.md` - Project overview
- `DEVELOPER_FAQ.md` - Q&A for developers
- `CONTRIBUTING.md` - Contribution guidelines
- `docs/developer_guide/` - Complete developer guide
- `docs/user_guide/` - Language reference

Online: https://ricomariani.github.io/CG-SQL-author/

---

**Created:** January 26, 2026  
**Purpose:** Enable effective development and understanding of CG/SQL  
**Maintained by:** Contributors to the CG/SQL project
