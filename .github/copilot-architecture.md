# CG/SQL Architecture Deep Dive

## Compilation Flow

```
Input (.sql file)
    ↓
[Lexer - cql.l]
    ↓ tokens
[Parser - cql.y]
    ↓ AST
[Semantic Analysis - sem.c]
    ↓ Decorated AST (with type info)
[Code Generators - cg_*.c]
    ↓
Output (C/Lua/JSON/etc.)
```

## AST Structure

### Node Design Philosophy
- **String-based types** not enum-based
- Enables easy pattern matching and printing
- Uniform tree structure (binary tree)
- No separate node class per construct

### AST Node (`ast.h`)
```c
typedef struct ast_node {
  const char *type;          // "if_stmt", "select_stmt", etc.
  struct ast_node *left;     // Left child
  struct ast_node *right;    // Right child
  struct sem_node *sem;      // Semantic info (added later)
  const char *filename;      // Source location
  int32_t lineno;           // Line number
} ast_node;
```

### Common Patterns
- Binary operations: `left = operand1, right = operand2`
- Statements: `left = condition, right = body`
- Lists: `left = item, right = rest_of_list`
- Leaves: `left = NULL, right = NULL`

## Semantic Analysis

### Two-Phase Process

**Phase 1: Symbol Resolution**
- Build symbol tables
- Resolve names to declarations
- Detect redefinitions

**Phase 2: Type Checking**
- Bottom-up type propagation
- Compatibility checking
- Implicit conversions where allowed

### Type System (`sem.h`)

**Base Types** (stored in `sem_t` - 64-bit flags):
```
SEM_TYPE_INTEGER      - 32-bit integer
SEM_TYPE_LONG_INTEGER - 64-bit integer
SEM_TYPE_REAL         - double
SEM_TYPE_BOOL         - boolean
SEM_TYPE_TEXT         - string
SEM_TYPE_BLOB         - binary data
SEM_TYPE_OBJECT       - opaque object reference
```

**Type Qualifiers** (additional flags):
```
SEM_TYPE_NOT_NULL     - Non-nullable
SEM_TYPE_VARIABLE     - Is a variable
SEM_TYPE_SENSITIVE    - Contains sensitive data
SEM_TYPE_HAS_DEFAULT  - Has default value
```

**Complex Types**:
- `STRUCT` → `sem_struct` (tables, result sets)
- `JOIN` → `sem_join` (FROM clause scopes)

### Sem Node Structure
```c
typedef struct sem_node {
  sem_t sem_type;              // Type flags
  CSTR name;                   // Name if applicable
  CSTR kind;                   // Object kind (e.g., "UIImage")
  struct sem_struct *sptr;     // Struct info
  struct sem_join *jptr;       // Join scope info
  int32_t create_version;      // Schema version
  int32_t delete_version;      // Schema version
  CSTR region;                 // Schema region
  // ... more fields
} sem_node;
```

### Symbol Tables

**Scoping:**
- Global: procedures, tables, views
- Procedure: parameters, local variables
- Block: compound statement locals
- Query: SELECT list aliases

**Operations:**
- `symtab_new()` - Create new table
- `symtab_add()` - Add symbol
- `symtab_find()` - Lookup symbol
- Stack managed manually via push/pop

## Code Generation

### C Code Generator (`cg_c.c`)

**Output Buffers:**
- `cg_header_output` - .h file (declarations)
- `cg_main_output` - .c file (implementations)
- `cg_scratch` - Temporary buffer

**Key Functions:**
```c
cg_stmt(ast_node *stmt)      // Generate statement code
cg_expr(ast_node *expr)      // Generate expression code
cg_proc(ast_node *proc)      // Generate procedure
```

**Pattern:**
1. Walk AST recursively
2. Emit C code to buffers via `bprintf()`
3. Handle SQLite API calls with error checking
4. Generate cleanup code for error paths

### Lua Code Generator (`cg_lua.c`)

**Differences from C:**
- No manual memory management
- Dynamic typing (runtime type checks)
- Different boolean semantics
- Table-based data structures

### JSON Schema Generator (`cg_json_schema.c`)

**Outputs:**
- Table/view schemas
- Procedure signatures
- Query result shapes
- Dependencies graph

**Use Cases:**
- Documentation generation
- Client code generation (Java, ObjC)
- Change tracking
- Diagram generation

### Schema Generator (`cg_schema.c`)

**Processes:**
- Parse `@create(n)` and `@delete(n)` annotations
- Compute schema versions
- Generate upgrade procedures
- Handle dependencies (FK, views, triggers)

**Output:**
```c
// Per-version upgrade procedures
void cql_schema_upgrade_v3() { ... }
void cql_schema_upgrade_v4() { ... }
```

## Runtime System

### Reference Counting

**Types with RC:**
- `cql_string_ref` - Strings
- `cql_blob_ref` - Blobs
- `cql_object_ref` - Objects

**Macros:**
- `cql_string_retain()` - Increment ref count
- `cql_string_release()` - Decrement (free at 0)
- `cql_set_string_ref()` - Smart pointer assignment

### Result Sets

**Structure:**
```c
typedef struct cql_result_set {
  cql_result_set_meta meta;    // Type metadata
  cql_int32 count;             // Row count
  void *data;                  // Row data
} cql_result_set;
```

**Generated Accessors:**
```c
// For each column in result:
cql_int32 result_get_id(cql_result_set *rs, cql_int32 row);
cql_string_ref result_get_name(cql_result_set *rs, cql_int32 row);
```

## Memory Management

### AST Allocation
- All AST nodes allocated from pools (`minipool.c`)
- No individual free operations
- Entire pool freed at end of compilation
- Fast allocation, no fragmentation

### String Handling
- Interned strings via symbol table
- Single canonical copy per unique string
- Pointer comparison for equality

### Charbuf (`charbuf.c`)
- Growable string buffers
- Used for code generation
- Efficient append operations

## Error Handling

### Compile-Time Errors
- Errors reported via `report_error()`
- Continue compilation to find more errors
- Error nodes marked in AST (SEM_TYPE_ERROR)
- Prevent cascading errors

### Runtime Errors (Generated Code)
- SQLite result codes checked
- `try/catch/throw` mapped to C
- Cleanup via `cql_cleanup_and_exit()`
- RAII-style resource management in C

## Pre-Processing

### Directives
- `@macro` - Define text substitution macros
- `@include` - Include other .sql files
- `@ifdef/@ifndef/@endif` - Conditional compilation
- `@text/@id` - Token manipulation

### Implementation
- Handled during parsing (`cql.y`)
- Simple text substitution
- State tracked via stack (`cql_ifdef_state`)

## Testing Infrastructure

### Test Organization
```
test/
  test.sql           - Parser tests
  sem_test.sql       - Semantic tests  
  cg_test.sql        - C codegen tests
  run_test.sql       - Runtime tests
  query_plan_test.sql - Query plan tests
  *.ref              - Reference outputs
```

### Test Execution (`test.sh`)
1. Compile CQL compiler
2. Run compiler on test files
3. Compare output to `.ref` files
4. Report differences
5. Optionally accept new outputs

### Coverage (`cov.sh`)
- Uses gcov
- Requires GCC (not Clang)
- Generates HTML report
- Must achieve 100% line coverage

## Build System

### Makefile Structure
- Source files auto-discovered
- Dependencies via GCC `-MMD`
- Multiple targets (cql, amalgam, tests)
- Platform detection (Darwin vs Linux)

### Amalgam Generation (`make_amalgam.sh`)
- Combines all C files into one
- Removes duplicate headers
- Easier integration into other projects
- Must be tested separately

## Extensions and Customization

### Custom Runtime
- Implement alternative `cqlrt.h`
- Provide own ref-counting
- Custom string/blob/object types
- Use `--rt c` flag

### Custom Code Generators
- Create `cg_myformat.c`
- Register in command-line parser
- Walk AST, emit to buffers
- Add to build system

### SQLite Extensions
- `sqlite3_cql_extension/` - SQLite loadable module
- Exposes CQL functions to SQLite
- Can call CQL procs from SQL

## Performance Characteristics

### Compile Time
- Single-pass architecture
- Linear in source size
- Hash-based symbol tables
- Pool-based allocation

### Generated Code
- Minimal abstraction overhead
- Direct SQLite C API calls
- C compiler does optimization
- Result sets are arrays (cache-friendly)

## Common Patterns

### Walking the AST
```c
void process_ast(ast_node *node) {
  if (!node) return;
  
  // Pre-order processing
  handle_node(node);
  
  // Recurse
  process_ast(node->left);
  process_ast(node->right);
  
  // Post-order processing
  finalize_node(node);
}
```

### Error Propagation
```c
static void sem_my_expr(ast_node *ast) {
  sem_expr(ast->left);
  sem_expr(ast->right);
  
  if (is_error(ast->left) || is_error(ast->right)) {
    record_error(ast);
    return;
  }
  
  // Actual semantic check...
  ast->sem = new_sem(result_type);
}
```

### Code Emission
```c
static void cg_my_stmt(ast_node *ast) {
  bprintf(cg_main_output, "  // My statement\n");
  bprintf(cg_main_output, "  {\n");
  
  CG_PUSH_INDENT();
  cg_stmt_list(ast->left);
  CG_POP_INDENT();
  
  bprintf(cg_main_output, "  }\n");
}
```

## Future Directions

### Compiler as Library
- Currently has `main()` in `cql.y`
- Goal: Extract to separate driver
- Enable embedding in other tools
- Better error handling API

### Additional Backends
- Go code generation
- Rust code generation
- Other dynamic languages

### Optimization Passes
- Currently minimal optimization
- Potential for CSE, constant folding
- Dead code elimination
- Query optimization hints
