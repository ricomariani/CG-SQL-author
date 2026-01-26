# CG/SQL AST Coding Conventions

This document describes the macros and conventions for working with the AST in CG/SQL. Understanding these patterns is essential for compiler development.

## Core AST Macros

### EXTRACT Family - Unpacking AST Nodes

The EXTRACT macros are the primary way to destructure AST nodes. They validate types and create local variables.

#### EXTRACT(type, node)
Extracts a child node using the type name as the variable name.
```c
// Creates variable 'select_stmt' from ast->left
EXTRACT(select_stmt, ast->left);
// Now you can use: select_stmt (may be NULL)
```

#### EXTRACT_NOTNULL(type, node)
Same as EXTRACT but asserts the node is not NULL.
```c
// Creates variable 'expr' which must not be NULL
EXTRACT_NOTNULL(expr, ast->left);
```

#### EXTRACT_NAMED(name, type, node)
Extracts with a custom variable name instead of using the type name.
```c
// Creates variable 'my_expr' of type 'expr'
EXTRACT_NAMED(my_expr, expr, ast->left);
```

#### EXTRACT_NAMED_NOTNULL(name, type, node)
Custom name variant that requires non-NULL.
```c
EXTRACT_NAMED_NOTNULL(my_select, select_stmt, ast->right);
```

#### EXTRACT_ANY(name, node)
Extracts without type checking (can be any node type).
```c
// Creates 'child' which may be NULL, no type validation
EXTRACT_ANY(child, ast->left);
```

#### EXTRACT_ANY_NOTNULL(name, node)
Extracts without type checking but requires non-NULL.
```c
// Creates 'expr' which must not be NULL
EXTRACT_ANY_NOTNULL(expr, ast->left);
```

### EXTRACT String and Numeric Values

#### EXTRACT_STRING(name, node)
Extracts a string value from a str_ast_node.
```c
// Given an identifier or string literal node
EXTRACT_STRING(table_name, name_ast);
// Creates: const char *table_name = ...
```

#### EXTRACT_NAME_AST(name_ast, node)
Extracts an identifier node (preserves the AST node itself).
```c
// Useful when you need both name and node for error reporting
EXTRACT_NAME_AST(name_ast, ast->left);
// name_ast is the full node, call EXTRACT_STRING on it to get the name
```

#### EXTRACT_BLOBTEXT(name, node)
Extracts the text value from a blob literal.
```c
EXTRACT_BLOBTEXT(blob_text, blob_node);
// Creates: const char *blob_text = ...
```

#### EXTRACT_NUM_TYPE(num_type, node)
Extracts the numeric type (NUM_INT, NUM_LONG, NUM_REAL, NUM_BOOL).
```c
EXTRACT_NUM_TYPE(num_type, num_node);
// Creates: int32_t num_type = ...
```

#### EXTRACT_NUM_VALUE(val, node)
Extracts the string representation of a numeric value.
```c
EXTRACT_NUM_VALUE(value_str, num_node);
// Creates: CSTR value_str = "42" (or whatever)
```

#### EXTRACT_DETAIL(name, node)
Extracts an integer value from a detail node (used for flags and options).
```c
EXTRACT_DETAIL(flags, ast->left);
// Creates: int32_t flags = ...
// Use to extract: TABLE_IF_NOT_EXISTS, INDEX_UNIQUE, etc.
```

### EXTRACT for Scoped Names

#### EXTRACT_NAME_AND_SCOPE(node)
Handles potentially scoped names like "schema.table".
```c
// For either "table" or "schema.table"
EXTRACT_NAME_AND_SCOPE(node);
// Creates: CSTR name, scope
// For "schema.table": name="table", scope="schema"
// For "table": name="table", scope=NULL
```

#### EXTRACT_NAMED_NAME_AND_SCOPE(name, scope, node)
Custom variable names for scoped extraction.
```c
EXTRACT_NAMED_NAME_AND_SCOPE(tbl_name, schema_name, node);
// Creates: CSTR tbl_name, schema_name
```

### EXTRACT for Statements

#### EXTRACT_STMT(stmt, stmt_list)
Extracts a statement from a statement list, unwrapping attributes if present.
```c
// stmt_list is a linked list of statements
EXTRACT_STMT(stmt, stmt_list);
// Creates: ast_node *stmt (unwrapped from stmt_and_attr if needed)
```

#### EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, stmt_list)
Extracts both statement and its attributes.
```c
EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, stmt_list);
// Creates: ast_node *stmt, *misc_attrs
// misc_attrs will be NULL if no attributes present
```

#### EXTRACT_MISC_ATTRS(ast, misc_attrs)
From within a node processor, reach up to parent to get attributes.
```c
// When processing a node that might have attributes
EXTRACT_MISC_ATTRS(ast, misc_attrs);
// Creates: ast_node *misc_attrs (from parent if available)
```

## Type Checking Macros

### is_ast_* Functions

Every AST node type has a corresponding type checker:
```c
if (is_ast_select_stmt(node)) { ... }
if (is_ast_create_table_stmt(node)) { ... }
if (is_ast_if_stmt(node)) { ... }
```

These are generated from the grammar and check the `node->type` string.

### Special Type Checkers

#### is_id(node)
Checks if node is an identifier.
```c
if (is_id(node)) {
  EXTRACT_STRING(name, node);
}
```

#### is_ast_str(node)
Checks if node is a string literal.

#### is_ast_num(node)
Checks if node is a numeric literal.

#### is_ast_blob(node)
Checks if node is a blob literal.

#### is_ast_detail(node)
Checks if node is a detail/flags node.

#### is_id_or_dot(node)
Checks if node is an identifier or qualified name (dot).
```c
if (is_id_or_dot(node)) {
  EXTRACT_NAME_AND_SCOPE(node);
}
```

## Common Coding Patterns

### Pattern 1: Binary Expression Processing
```c
static void sem_add(ast_node *ast, CSTR op) {
  Contract(is_ast_add(ast));
  EXTRACT_ANY_NOTNULL(left, ast->left);
  EXTRACT_ANY_NOTNULL(right, ast->right);
  
  // Process children first
  sem_expr(left);
  sem_expr(right);
  
  // Check for errors
  if (is_error(left) || is_error(right)) {
    record_error(ast);
    return;
  }
  
  // Type checking and result assignment
  // ...
  ast->sem = new_sem(result_type);
}
```

### Pattern 2: Statement with Attributes
```c
static void gen_create_table(ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast));
  EXTRACT_NOTNULL(create_table_name_flags, ast->left);
  EXTRACT_NOTNULL(col_key_list, ast->right);
  EXTRACT_DETAIL(flags, create_table_name_flags->left);
  EXTRACT_NAME_AST(name_ast, create_table_name_flags->right);
  
  // Extract table attributes if present
  EXTRACT_MISC_ATTRS(ast, misc_attrs);
  
  // Generate code...
}
```

### Pattern 3: Processing Lists
```c
static void gen_column_list(ast_node *ast) {
  Contract(is_ast_col_key_list(ast));
  
  // Lists are right-recursive
  for (ast_node *item = ast; item; item = item->right) {
    ast_node *col = item->left;
    gen_column(col);
    
    if (item->right) {
      gen_printf(", ");
    }
  }
}
```

### Pattern 4: Extracting Flags and Options
```c
static void process_create_index(ast_node *ast) {
  EXTRACT_NOTNULL(index_flags_names_attrs, ast->right);
  EXTRACT_DETAIL(flags, index_flags_names_attrs->left);
  
  if (flags & INDEX_UNIQUE) {
    gen_printf("UNIQUE ");
  }
  if (flags & INDEX_IFNE) {
    gen_printf("IF NOT EXISTS ");
  }
}
```

### Pattern 5: Handling Optional Nodes
```c
static void gen_select_stmt(ast_node *ast) {
  EXTRACT_NOTNULL(select_core_list, ast->left);
  EXTRACT(select_orderby, ast->right);  // May be NULL
  
  gen_select_core_list(select_core_list);
  
  if (select_orderby) {
    gen_orderby(select_orderby);
  }
}
```

### Pattern 6: Name Resolution with Scope
```c
static void sem_table_reference(ast_node *ast) {
  EXTRACT_NAME_AND_SCOPE(ast);
  // name = "MyTable", scope = NULL or "MySchema"
  
  if (scope) {
    // Handle qualified name
    report_error(ast, "CQL0123: qualified table names not supported here", name);
    record_error(ast);
    return;
  }
  
  ast_node *table = find_table(name);
  // ...
}
```

## Contract Assertions

Always use `Contract()` to validate assumptions:

```c
Contract(is_ast_select_stmt(ast));  // Type must be correct
Contract(ast->left);                // Must have left child
Contract(name);                     // String must not be NULL
```

These are debug assertions that help catch bugs during development. They compile to nothing in release builds.

## Invariant Checks

Use `Invariant()` for runtime checks that should always be true:

```c
Invariant(is_unitary(core_type));
Invariant(count > 0);
```

Unlike `Contract`, `Invariant` checks remain in release builds.

## Error Handling Pattern

Standard error propagation:

```c
static void sem_my_operation(ast_node *ast) {
  // 1. Extract and process children
  EXTRACT_NOTNULL(left, ast->left);
  sem_expr(left);
  
  // 2. Early exit on error
  if (is_error(left)) {
    record_error(ast);
    return;
  }
  
  // 3. Validation and reporting
  if (!is_valid(left->sem->sem_type)) {
    report_error(left, "CQL0123: error message", "context");
    record_error(ast);
    return;
  }
  
  // 4. Success - set semantic info
  ast->sem = new_sem(result_type);
}
```

## AST Rewrite Macros

When creating new AST nodes outside of parsing (e.g., for rewriting):

```c
AST_REWRITE_INFO_SET(ast->lineno, ast->filename);
ast_node *new_node = new_ast(...);
AST_REWRITE_INFO_RESET();
```

Or use the SAVE/RESTORE pattern:
```c
AST_REWRITE_INFO_SAVE();
// Create nodes here
ast_node *new_node = new_ast(...);
AST_REWRITE_INFO_RESTORE();
```

## Semantic Node Access

Access semantic information through `ast->sem`:

```c
sem_t type = ast->sem->sem_type;
CSTR name = ast->sem->name;
CSTR kind = ast->sem->kind;
sem_struct *sptr = ast->sem->sptr;
```

### Common Type Checks on sem_t

```c
is_error(ast)              // SEM_TYPE_ERROR set
is_nullable(type)          // NOT SEM_TYPE_NOT_NULL
is_not_nullable(type)      // SEM_TYPE_NOT_NULL set
is_text(type)              // Core type is TEXT
is_blob(type)              // Core type is BLOB
is_object(type)            // Core type is OBJECT
is_numeric(type)           // INT, LONG, REAL, or BOOL
is_any_int(type)           // INT or LONG
core_type_of(type)         // Extract base type without flags
sensitive_flag(type)       // Extract SEM_TYPE_SENSITIVE flag
combine_flags(t1, t2)      // Merge nullability and sensitivity
```

## Code Generation Patterns

### Using charbuf (gen_printf)

```c
gen_printf("SELECT ");
gen_expr(expr_node);
gen_printf(" FROM ");
gen_name(table_name_ast);
gen_printf(";\n");
```

### Indentation

```c
GEN_BEGIN_INDENT(save, 2);  // Indent by 2 spaces
gen_printf("BEGIN\n");
gen_stmt_list(stmts);
gen_printf("END\n");
GEN_END_INDENT(save);
```

### Dispatching to Specific Handlers

Many files use symbol table dispatch:

```c
// In gen_sql.c initialization:
symtab_add(gen_stmts, "select_stmt", (void *)gen_select_stmt);

// Later:
symtab_entry *entry = symtab_find(gen_stmts, ast->type);
if (entry) {
  gen_func fn = (gen_func)entry->val;
  fn(ast);
}
```

## Typical Function Signatures

### Semantic Analysis
```c
static void sem_<construct>(ast_node *ast);
static void sem_<construct>(ast_node *ast, CSTR op);
```

### Code Generation
```c
static void gen_<construct>(ast_node *ast);
static void cg_<construct>(ast_node *ast);
```

### Helpers
```c
static bool_t <check_something>(ast_node *ast);
static ast_node *find_<entity>(CSTR name);
```

## Node Creation

Creating new AST nodes:

```c
ast_node *node = new_ast("node_type", left_child, right_child);
ast_node *str_node = new_ast_str("identifier_name");
ast_node *num_node = new_ast_num(NUM_INT, "42");
ast_node *detail = new_ast_detail(flags_value);
```

## Best Practices

1. **Always use EXTRACT macros** - Don't manually access `ast->left` or cast nodes
2. **Check types with is_ast_* first** - Validate before extraction
3. **Use Contract liberally** - Catch bugs early in debug builds
4. **Propagate errors immediately** - Check `is_error()` after processing children
5. **Follow existing patterns** - Look at similar functions as templates
6. **Use descriptive variable names** - Even though EXTRACT creates them for you
7. **Document complex tree structures** - Add comments showing the AST shape

## Example: Complete Statement Handler

```c
// {create_index_stmt}
//   | {create_index_on_list}
//     | {name index_name}
//     | {name table_name}
//   | {index_flags_names_attrs}
//     | {detail flags}
//     | {connector}
//       | {indexed_columns}
//       | {opt_where}?
static void sem_create_index_stmt(ast_node *ast) {
  Contract(is_ast_create_index_stmt(ast));
  
  // Extract the tree structure
  EXTRACT_NOTNULL(create_index_on_list, ast->left);
  EXTRACT_NOTNULL(index_flags_names_attrs, ast->right);
  EXTRACT_NAME_AST(index_name_ast, create_index_on_list->left);
  EXTRACT_NAME_AST(table_name_ast, create_index_on_list->right);
  EXTRACT_DETAIL(flags, index_flags_names_attrs->left);
  EXTRACT_NOTNULL(connector, index_flags_names_attrs->right);
  EXTRACT_NOTNULL(indexed_columns, connector->left);
  EXTRACT(opt_where, connector->right);  // Optional
  
  // Get the actual names
  EXTRACT_STRING(index_name, index_name_ast);
  EXTRACT_STRING(table_name, table_name_ast);
  
  // Semantic validation
  ast_node *table = find_table(table_name);
  if (!table) {
    report_error(ast, "CQL0123: table not found", table_name);
    record_error(ast);
    return;
  }
  
  // Process columns
  sem_indexed_columns(indexed_columns, table);
  if (is_error(indexed_columns)) {
    record_error(ast);
    return;
  }
  
  // Process optional WHERE clause
  if (opt_where) {
    sem_opt_where(opt_where);
    if (is_error(opt_where)) {
      record_error(ast);
      return;
    }
  }
  
  // Success - mark as valid
  ast->sem = new_sem(SEM_TYPE_OK);
}
```

## Summary

The EXTRACT macros and conventions in CG/SQL provide:
- **Type safety** - Validate node types at extraction
- **Null safety** - Explicit about nullable vs non-null
- **Clarity** - Self-documenting code
- **Consistency** - Uniform patterns across the codebase
- **Error catching** - Contract assertions catch bugs early

Master these patterns and you'll be able to navigate and modify the CG/SQL compiler effectively.
