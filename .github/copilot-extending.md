# Extending CG/SQL: Adding New Code Generation Targets

This document provides a complete guide to extending CG/SQL with new backends, based on analysis of the existing code generators and documentation.

## Table of Contents

1. [Overview of Code Generation Architecture](#overview)
2. [The JSON Schema as Universal Intermediate](#json-schema)
3. [Direct Code Generator Approach](#direct-codegen)
4. [Hybrid Approaches](#hybrid-approaches)
5. [Case Studies: Existing Generators](#case-studies)
6. [Step-by-Step: Adding a New Target](#step-by-step)
7. [Design Considerations](#design-considerations)
8. [Future Evolution](#future-evolution)

## Overview of Code Generation Architecture {#overview}

CG/SQL supports **two distinct approaches** for code generation:

### 1. Direct Code Generation (C-style)
Compile-time code generation that walks the AST and emits code directly:
- C backend (`cg_c.c`) - Full native compilation
- Lua backend (`cg_lua.c`) - Interpreted language target
- Query Plan (`cg_query_plan.c`) - Analysis output
- Test Helpers (`cg_test_helpers.c`) - Testing infrastructure
- Schema Upgrader (`cg_schema.c`) - Migration code
- Stats (`cg_stats.c`) - Statistics tracking

### 2. JSON Schema + External Tools
Two-stage approach using JSON as intermediate representation:
- CQL compiler emits JSON schema (`cg_json_schema.c`)
- External tools (Python, Go, etc.) process JSON
- Examples: Java JNI bindings, Objective-C bindings, diagrams

Both approaches have their place depending on requirements.

## The JSON Schema as Universal Intermediate {#json-schema}

### What is the JSON Schema?

The JSON output is a **complete, stable representation** of:
- All DDL (tables, views, indices, triggers)
- All procedures with signatures and dependencies
- Type information for all entities
- Schema versioning and regions
- Attributes and metadata

**Key Insight:** The JSON schema is the **stable contract**. While code generators can change, the JSON format evolves in a backward-compatible way.

### JSON Structure

```json
{
  "tables": [...],
  "virtualTables": [...],
  "views": [...],
  "indices": [...],
  "triggers": [...],
  "queries": [...],        // SELECT procedures (single statement)
  "inserts": [...],        // INSERT procedures (single statement)
  "generalInserts": [...], // Complex INSERT (multi-row, INSERT...SELECT)
  "updates": [...],        // UPDATE procedures
  "deletes": [...],        // DELETE procedures
  "general": [...],        // All other procedures
  "regions": [...],
  "enums": [...],
  "constantGroups": [...]
}
```

### Procedure Categorization

The compiler automatically categorizes procedures for easier binding:

| Category | Criteria | Use Case |
|----------|----------|----------|
| `queries` | Single SELECT, no OUT params, no fragments | Result set queries |
| `inserts` | Single INSERT VALUES, no OUT params | Simple inserts |
| `generalInserts` | Complex INSERT, no OUT params | Batch inserts, UPSERT |
| `updates` | Single UPDATE, no OUT params | Simple updates |
| `deletes` | Single DELETE, no OUT params | Simple deletes |
| `general` | Everything else | Complex procedures |

**Why this matters:** Simple procedures get richer metadata and easier bindings. Complex procedures get basic signatures.

### When to Use JSON Approach

✅ **Use JSON when:**
- Target language has good JSON parsing
- You want to decouple from CQL compiler internals
- You're generating bindings (Java, C#, Swift, Go, etc.)
- External tool authors might want to customize
- You need multiple tools consuming same schema
- You want to version the schema separately

❌ **Don't use JSON when:**
- You need complete access to AST details
- Performance of code generation is critical
- You're generating runtime code (not bindings)
- JSON overhead is unacceptable

## Direct Code Generator Approach {#direct-codegen}

### Architecture

All direct code generators follow this pattern:

```c
// Main entry point
cql_noexport void cg_<target>_main(ast_node *head) {
  // 1. Initialize state
  //2. Set up dispatch tables
  // 3. Walk AST
  // 4. Write output files
}
```

### Core Requirements

Every direct code generator needs:

1. **State Management**
   - Output buffers (charbuf)
   - Symbol tables for tracking
   - Context stack (for nested scopes)

2. **AST Dispatch**
   - Statement handlers
   - Expression handlers
   - Type conversions

3. **Output Management**
   - Header file (.h)
   - Implementation file (.c, .lua, etc.)
   - Potentially multiple sections

### Example: Minimal Generator Structure

```c
// In cg_myformat.c

// State
static charbuf *cg_header_output;
static charbuf *cg_main_output;
static symtab *cg_stmts;

// Main entry
cql_noexport void cg_myformat_main(ast_node *head) {
  cql_exit_on_semantic_errors(head);
  
  // Initialize buffers
  CHARBUF_OPEN(header);
  CHARBUF_OPEN(main);
  cg_header_output = &header;
  cg_main_output = &main;
  
  // Set up dispatch
  cg_stmts = symtab_new();
  symtab_add(cg_stmts, "create_proc_stmt", (void *)cg_create_proc_stmt);
  symtab_add(cg_stmts, "create_table_stmt", (void *)cg_create_table_stmt);
  // ... more handlers
  
  // Process AST
  cg_stmt_list(head);
  
  // Write outputs
  cql_write_file("output.h", header.ptr);
  cql_write_file("output.c", main.ptr);
  
  // Cleanup
  CHARBUF_CLOSE(main);
  CHARBUF_CLOSE(header);
  SYMTAB_CLEANUP(cg_stmts);
}
```

### Key Challenges for Direct Generators

1. **Type System Mapping**
   - Map CQL types to target language types
   - Handle nullable vs non-nullable
   - Reference types vs value types

2. **Memory Management**
   - Reference counting for strings/blobs
   - Cleanup on errors
   - RAII patterns if target supports

3. **SQLite Integration**
   - Binding variables
   - Error checking
   - Result set extraction

4. **Expression Translation**
   - SQL semantics vs target language semantics
   - NULL handling (3-valued logic)
   - Operator precedence

## Case Studies: Existing Generators {#case-studies}

### Case Study 1: C Generator (`cg_c.c`)

**Target:** C language with SQLite C API

**Key Features:**
- Full native compilation
- Explicit memory management
- Static typing with nullable structs
- Direct SQLite API calls

**Type Mapping:**
```c
INTEGER NOT NULL     -> cql_int32
INTEGER (nullable)   -> cql_nullable_int32  // struct with is_null flag
TEXT                 -> cql_string_ref      // ref-counted string
BLOB                 -> cql_blob_ref        // ref-counted blob
OBJECT<T>            -> cql_object_ref      // generic object
```

**Memory Strategy:**
- Pool allocation for temporaries
- Reference counting for strings/blobs/objects
- Cleanup via RAII-style macros

**Strengths:**
- Maximum performance
- Complete control
- No runtime overhead

**Complexity:**
- ~30,000 lines of code
- Handles all edge cases
- Complex null handling

### Case Study 2: Lua Generator (`cg_lua.c`)

**Target:** Lua language with SQLite bindings

**Key Features:**
- Dynamic typing
- Garbage collection
- Native nil handling
- Table-based result sets

**Type Mapping:**
```lua
-- All types -> Lua value or nil
INTEGER  -> number or nil
REAL     -> number or nil
TEXT     -> string or nil
BLOB     -> string (binary) or nil
OBJECT   -> userdata or nil
```

**Memory Strategy:**
- Lua GC handles everything
- No explicit reference counting needed
- Much simpler than C

**Truthiness Gotcha:**
```lua
-- Lua: 0 is truthy!
if 0 then print("yes") end  -- prints "yes"

-- C: 0 is falsey
if (0) { printf("no"); }    -- doesn't execute

-- Solution: Explicit comparisons
if (x ~= 0) and (x ~= nil) then ... end
```

**Strengths:**
- Simple generated code
- Easy to read/debug
- Rapid prototyping

**Tradeoffs:**
- Different semantics from SQL
- No compile-time type checking
- Slower than C

### Case Study 3: JSON Schema (`cg_json_schema.c`)

**Target:** JSON metadata

**Key Features:**
- Complete schema representation
- Dependency analysis
- Procedure categorization
- Stable format for external tools

**Output Sections:**
```json
{
  "tables": [...],
  "queries": [...],
  "general": [...]
}
```

**Dependency Analysis:**
- Uses `find_table_refs` to walk AST
- Tracks: tables used, views used, procedures called
- Transitive closure for views
- Direct deps only for procedures

**Strengths:**
- Stable contract
- Language-agnostic
- Supports external tooling
- Easy to extend

**Use Cases:**
- Java JNI bindings (cqljava.py)
- Objective-C bindings
- Documentation generation
- Schema visualization
- Change tracking

### Case Study 4: Query Plan Generator (`cg_query_plan.c`)

**Target:** Query analysis procedures

**Key Features:**
- Wraps queries with EXPLAIN QUERY PLAN
- Generates C procedures to extract plans
- Handles shared fragments
- Transforms CQL to executable SQL

**Output Example:**
```c
// Generated procedure that explains a query
void get_plan_for_my_query(sqlite3 *db, cql_string_ref *plan_out) {
  sqlite3_stmt *stmt = NULL;
  cql_code rc = sqlite3_prepare_v2(db, 
    "EXPLAIN QUERY PLAN SELECT ...", -1, &stmt, NULL);
  // ... extract plan into string
}
```

**Strengths:**
- Debugging aid
- Performance analysis
- No runtime overhead (separate tool)

## Step-by-Step: Adding a New Target {#step-by-step}

### Option A: JSON-Based Generator (Recommended)

**Best for:** Most new language bindings

**Steps:**

1. **Understand the JSON output**
   ```bash
   cql --in sample.sql --rt json_schema --cg output.json
   cat output.json | jq .
   ```

2. **Study existing tools**
   - Look at `sources/java_demo/cqljava.py` for JNI bindings
   - Look at `sources/cqljson/cqljson.py` for visualization

3. **Design type mappings**
   ```python
   # Example for Go
   cql_to_go = {
       "integer": "int32",
       "long": "int64",
       "real": "float64",
       "bool": "bool",
       "text": "*string",  # Nullable
       "blob": "[]byte",
       "object": "interface{}"
   }
   ```

4. **Write procedure wrappers**
   ```python
   def emit_procedure(proc):
       # Generate function signature
       # Marshal parameters
       # Call C procedure
       # Unmarshal results
   ```

5. **Handle result sets**
   ```python
   def emit_result_set_accessors(projection):
       # Generate getters for each column
       # Handle nullable types
   ```

6. **Test incrementally**
   - Start with simple queries
   - Add inserts/updates/deletes
   - Then general procedures

### Option B: Direct AST Generator

**Best for:** Runtime code generation, new SQLite-like backends

**Steps:**

1. **Create `cg_myformat.c` and `cg_myformat.h`**

2. **Implement main entry point:**
   ```c
   cql_noexport void cg_myformat_main(ast_node *head);
   ```

3. **Set up dispatch tables:**
   ```c
   static void cg_myformat_init() {
     cg_stmts = symtab_new();
     
     // Statements
     symtab_add(cg_stmts, "create_proc_stmt", (void *)cg_proc);
     symtab_add(cg_stmts, "if_stmt", (void *)cg_if_stmt);
     symtab_add(cg_stmts, "while_stmt", (void *)cg_while_stmt);
     
     // Expressions
     symtab_add(cg_exprs, "add", (void *)cg_binary);
     symtab_add(cg_exprs, "mul", (void *)cg_binary);
   }
   ```

4. **Implement core handlers:**
   ```c
   static void cg_proc(ast_node *ast) {
     EXTRACT_STRING(name, ast->left);
     EXTRACT_NOTNULL(params, get_proc_params(ast));
     
     // Emit procedure header
     bprintf(cg_header_output, "extern void %s(...);\n", name);
     
     // Emit procedure body
     bprintf(cg_main_output, "void %s(...) {\n", name);
     cg_stmt_list(get_proc_body(ast));
     bprintf(cg_main_output, "}\n");
   }
   ```

5. **Handle expressions:**
   ```c
   static void cg_binary(ast_node *ast, CSTR op) {
     EXTRACT_ANY_NOTNULL(left, ast->left);
     EXTRACT_ANY_NOTNULL(right, ast->right);
     
     cg_expr(left);
     bprintf(output, " %s ", op);
     cg_expr(right);
   }
   ```

6. **Add command-line option** in `cql.y`:
   ```c
   else if (!strcmp(argv[cur], "--cg")) {
     // ... existing options
   }
   else if (!strcmp(argv[cur], "--rt")) {
     if (!strcmp(argv[cur + 1], "myformat")) {
       rt = &myformat_target;
     }
   }
   ```

7. **Define runtime table** in `rt.c`:
   ```c
   static cql_data_defn( rt_common ) myformat_target = {
     .cql_emit_main = cg_myformat_main,
     .rt_cleanup = myformat_cleanup,
     .header_prefix = "// Generated by CQL\n",
     .source_prefix = "#include \"myformat.h\"\n"
   };
   ```

8. **Update Makefile:**
   ```makefile
   SOURCES += cg_myformat.c
   ```

9. **Add tests** in `sources/test/`:
   ```sql
   -- TEST: myformat basic
   -- + (expected output pattern)
   CREATE PROC test_proc()
   BEGIN
     SELECT 1 AS x;
   END;
   ```

10. **Ensure coverage:**
    ```bash
    cd sources
    ./test.sh
    ./cov.sh
    ```

## Design Considerations {#design-considerations}

### Type System Questions

**Q: How do I handle NULL?**

Options:
1. **Native nil/null/None** (Lua, Python, Swift, Kotlin)
   - Map nullable types to `value | nil`
   - Simple and natural

2. **Optional/Maybe types** (Rust, Haskell, OCaml)
   - Map to `Option<T>`, `Maybe T`
   - Type-safe but verbose

3. **Nullable wrapper** (C, Java primitives)
   - Struct with `is_null` flag
   - Required for primitives

4. **Nullable reference types** (C#, Kotlin, TypeScript)
   - Use language's nullability annotations
   - Compiler-checked

**Q: How do I map CQL types?**

Consider:
- Integer sizes (32-bit vs 64-bit)
- Float precision (64-bit default)
- String encoding (UTF-8)
- Blob representation (byte arrays)
- Object types (generic vs typed)

**Q: Should I use boxing?**

Boxing (Int -> Integer in Java) adds:
- ✅ Uniform null handling
- ✅ Simpler code generation
- ❌ Performance overhead
- ❌ Extra allocations

### Memory Management Questions

**Q: Who owns result set data?**

Options:
1. **Caller owns** - Caller must free
2. **Generator owns** - Internal cache, read-only
3. **Shared ownership** - Reference counting
4. **Garbage collected** - Language runtime handles

**Q: How long do strings live?**

Consider:
- Are strings copied or referenced?
- When are strings freed?
- Thread safety requirements

### SQL Integration Questions

**Q: Do I generate runtime code or bindings?**

**Runtime code** (C, Lua):
- Generate actual SQLite calls
- Full control over execution
- More complex generator

**Bindings** (Java, C#, Swift):
- Call C procedures from generated code
- Simpler generator
- Requires FFI/JNI/interop layer

**Q: How do I handle errors?**

Options:
1. **Exceptions** - Throw on SQLite errors
2. **Result types** - Return `Result<T, Error>`
3. **Error codes** - Return int, pass output via pointers
4. **Callbacks** - Error handler callback

### Code Organization Questions

**Q: One file or many?**

**One file:**
- ✅ Simple deployment
- ❌ Large file size
- ❌ Slow compilation

**Many files:**
- ✅ Better organization
- ✅ Parallel compilation
- ❌ Complex packaging

**Q: Generate comments?**

Consider:
- Original SQL as comments
- Type information
- Null handling notes
- Performance hints

## Hybrid Approaches {#hybrid-approaches}

### JSON + Code Generation

Use JSON for **what** to generate, direct codegen for **how**:

```python
# Read JSON schema
schema = json.load(open("schema.json"))

# Generate via template or direct emission
for table in schema["tables"]:
    emit_table_class(table)

for proc in schema["queries"]:
    emit_query_method(proc)
```

**Advantages:**
- Stable input (JSON contract)
- Flexible output (any template system)
- Easy to customize

**Examples:**
- cqljava.py - Reads JSON, emits Java + C
- Custom ORMs and frameworks

### Extending JSON Schema

Add custom metadata via attributes:

```sql
@attribute(myformat:special_handling)
CREATE TABLE users(
  id INTEGER PRIMARY KEY,
  @attribute(myformat:indexed)
  name TEXT
);
```

JSON output includes attributes:
```json
{
  "name": "users",
  "attributes": [
    {"name": "myformat:special_handling", "value": true}
  ],
  "columns": [
    {
      "name": "name",
      "attributes": [
        {"name": "myformat:indexed", "value": true}
      ]
    }
  ]
}
```

Your tool processes attributes:
```python
def should_index(column):
    for attr in column.get("attributes", []):
        if attr["name"] == "myformat:indexed":
            return True
    return False
```

## Future Evolution {#future-evolution}

### Compiler as Library

**Current:** Compiler is an executable
**Future:** Compiler is a library with API

Benefits:
- In-process code generation
- Custom error handling
- Incremental compilation
- IDE integration

### Plugin Architecture

**Concept:** Loadable code generators

```c
// Plugin API
typedef struct cg_plugin {
  void (*init)(void);
  void (*emit_proc)(ast_node *ast);
  void (*emit_table)(ast_node *ast);
  void (*cleanup)(void);
} cg_plugin;

// Load dynamically
cg_plugin *p = dlopen("cg_rust.so");
```

Benefits:
- No recompilation needed
- Community contributions
- Rapid experimentation

### Enhanced JSON Schema

Future additions might include:
- **Control flow graphs** - For optimization
- **Data flow analysis** - For safety checking
- **Cost estimates** - For query planning
- **Change sets** - For migration tools

### Multi-Stage Compilation

**Concept:** Multiple backend passes

```
CQL -> IR1 (high-level) -> IR2 (low-level) -> Target
```

Benefits:
- Shared optimization passes
- Easier to add targets
- Better code quality

## Summary and Recommendations

### When to Use Each Approach

| Approach | Best For | Complexity | Flexibility |
|----------|----------|------------|-------------|
| **JSON + Python** | Language bindings, tools | Low | High |
| **JSON + Custom Tool** | Domain-specific needs | Low-Med | Highest |
| **Direct AST (C)** | Runtime code, backends | High | Medium |
| **Direct AST (plugin)** | Advanced features | Highest | Medium |

### Getting Started Checklist

- [ ] Study existing code generator (C or Lua)
- [ ] Generate JSON from sample schema
- [ ] Map CQL types to target language
- [ ] Handle simple SELECT query
- [ ] Handle INSERT/UPDATE/DELETE
- [ ] Handle nullable types
- [ ] Handle result sets
- [ ] Handle OUT parameters
- [ ] Add error handling
- [ ] Write tests
- [ ] Document usage

### Resources

**Code to study:**
- `sources/cg_c.c` - Complete C generator
- `sources/cg_lua.c` - Simpler Lua generator
- `sources/cg_json_schema.c` - JSON emitter
- `sources/java_demo/cqljava.py` - JSON consumer

**Documentation:**
- Part 3: C Code Generation (`docs/developer_guide/03_c_code_generation.md`)
- Part 7: JSON Generation (`docs/developer_guide/07_json_generation.md`)
- Part 10: Lua Notes (`docs/developer_guide/10_lua_notes.md`)
- Part 11: JSON Python Tools (`docs/developer_guide/11_json_python_tools.md`)
- Chapter 13: JSON Output (`docs/user_guide/13_json_output.md`)

**Testing:**
- `sources/test/cg_test.sql` - C codegen tests
- `sources/test/query_plan_test.sql` - Query plan tests

### Final Thoughts

CG/SQL's architecture makes it **surprisingly easy** to add new targets:

1. **JSON approach** gets you 80% there in a few hundred lines of Python
2. **Direct approach** gives you complete control but requires deep understanding
3. **Hybrid approach** often best: use JSON for structure, generate code for performance

The key insight: **CQL's semantic analysis does the hard work**. Your generator just needs to map validated, typed AST to your target language.

Start simple, iterate, and don't be afraid to study the existing generators. They contain years of accumulated wisdom about code generation for database-backed applications.
