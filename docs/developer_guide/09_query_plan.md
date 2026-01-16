---
title: "Part 9: Query Plan Generation"
weight: 9
---
<!---
-- Copyright (c) Rico Mariani
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Preface

Part 9 continues with a discussion of the query plan generation system.
As in the previous sections, the goal here is not to go over every detail but rather to give
a sense of how query plan generation works in general -- the core strategies and implementation choices --
so that when reading the source you will have an idea how it all hangs together. To accomplish
this, we'll illustrate the key strategies used to transform the AST and generate executable
query plan code.

## Query Plan Overview

The query plan system is described in [Chapter 15](../user_guide/15_query_plan_generation.md) of the Guide.
The goal of this system is to enable developers to see the query plans that SQLite will use for all
the SQL statements in their CQL code. This is valuable for performance analysis and optimization.

The challenge is that query plans can only be obtained by actually running `EXPLAIN QUERY PLAN` on
a statement in a live database. But the original CQL code might:
* Have variables whose values aren't available at compile time
* Use user-defined functions that require native implementations
* Reference many tables across multiple procedures
* Include conditionals in shared fragments
* Use virtual tables or table-valued functions

The query plan generator solves these problems by transforming the original CQL code into a completely
new CQL program that:
1. Creates all the necessary schema
2. Replaces problematic constructs with simpler alternatives
3. Runs `EXPLAIN QUERY PLAN` on every eligible SQL statement
4. Collects the results into a JSON report

This is a "meta-compilation" approach: we compile CQL to generate new CQL that will produce query plans.

### Entry Point and Initialization

The main entry point is `cg_query_plan_main` in [cg_query_plan.c](../../sources/cg_query_plan.c#L945). 

```c
cql_noexport void cg_query_plan_main(ast_node *head) {
  sql_stmt_count = 0; // reset statics

  Contract(options.file_names_count == 1);
  cql_exit_on_semantic_errors(head);
  exit_on_validating_schema();

  cg_stmts = symtab_new();
  virtual_tables = symtab_new();
```

The function begins by resetting state (since CQL can be invoked multiple times in a process), then
sets up symbol tables to track:
* Statement types we care about (`cg_stmts`)
* Virtual tables we've encountered (`virtual_tables`)

The code then registers callbacks for different statement types using macros like `STMT_INIT`:

```c
STMT_INIT(create_proc_stmt);
STMT_INIT(create_virtual_table_stmt);

// schema statements
STMT_INIT_DDL(create_table_stmt);
STMT_INIT_DDL(create_index_stmt);
STMT_INIT_DDL(create_view_stmt);
STMT_INIT_DDL(create_trigger_stmt);

// DML statements that we want to explain
STMT_INIT_EXPL(select_stmt);
STMT_INIT_EXPL(insert_stmt);
STMT_INIT_EXPL(update_stmt);
STMT_INIT_EXPL(delete_stmt);
// ... and many more
```

This creates a dispatch table so that as we walk the AST, different node types are handled appropriately.

### The Fundamental Problem: Variables

One of the core challenges is that SQL statements often contain variables:

```sql
SELECT * FROM users WHERE id = user_id;
```

When we run `EXPLAIN QUERY PLAN`, SQLite needs actual values, not variable references. The solution
is to replace all variables with type-appropriate constants. The function `qp_variables_callback` 
handles this:

```c
static bool_t qp_variables_callback(
  struct ast_node *_Nonnull ast,
  void *_Nullable context,
  charbuf *_Nonnull output)
{
  qp_emit_constant_one(false, ast->sem->sem_type, output);
  return true;
}
```

This delegates to `qp_emit_constant_one` which generates a suitable constant based on the type:

```c
static void qp_emit_constant_one(bool_t native_context, sem_t sem_type, charbuf *output)
{
  bool_t nullable = is_nullable(sem_type) && !is_inferred_notnull(sem_type);

  if (nullable) {
    gen_printf("nullable(");
  }

  if (is_bool(sem_type)) {
    gen_printf("true");
  }
  else if (is_long(sem_type)) {
    gen_printf("1L");
  }
  else if (is_real(sem_type)) {
    gen_printf("1.0");
  }
  else if (is_numeric(sem_type)) {
    gen_printf("1");
  }
  else if (is_text(sem_type)) {
    gen_printf("'1'");
  }
  else if (is_object(sem_type)) {
    if (native_context) {
       gen_printf("trivial_object()");
    }
    else {
       gen_printf("query_plan_trivial_object");
    }
  }
  else {
    Contract(is_blob(sem_type));
    if (native_context) {
       gen_printf("trivial_blob()");
    }
    else {
      gen_printf("query_plan_trivial_blob");
    }
  }

  if (nullable) {
    gen_printf(")");
  }
}
```

Note the special handling for objects and blobs: in native context (outside SQL), we call helper
functions that return appropriate dummy values. Inside SQL context, we reference pre-computed
variables (`query_plan_trivial_object` and `query_plan_trivial_blob`) that were set up earlier.
This avoids function call overhead in the generated SQL.

The choice of "1" as the constant is deliberate: it's a valid value for most types and won't trigger
NULL-handling paths in the query planner, giving us the most representative plan.

### Handling Native Functions

Similar to variables, native functions pose a problem: we can't actually call them when generating
query plans. The `qp_func_callback` handles this:

```c
static bool_t qp_func_callback(
  struct ast_node *_Nonnull ast,
  void *_Nullable context,
  charbuf *_Nonnull output)
{
  Contract(is_ast_call(ast));
  EXTRACT_STRING(name, ast->left);

  // shared expression fragment will be inline expanded
  // we don't have to replace it
  if (is_inline_func_call(ast)) {
    return false;
  }

  ast_node *func = find_func(name);

  // note: ast_declare_select_func_stmt does NOT match, they stay
  if (func && is_ast_declare_func_stmt(func)) {
    qp_emit_constant_one(true, ast->sem->sem_type, output);
    return true;
  }

  // similar handling for proc-as-func...
```

The key points:
* Inline shared fragments are left alone - they'll be expanded normally
* Native functions (`declare func`) are replaced with constants
* Select functions (`declare select function`) are kept - we'll generate stubs for them later
* The distinction is important: select functions are UDFs that SQLite knows about, while native
  functions exist only in the C/C++ host language

### Virtual Tables and Table-Valued Functions

Virtual tables are particularly tricky because they require complex native setup. The query plan
generator takes a pragmatic approach: it replaces them with regular tables that have the same
column structure.

The `qp_table_function_callback` handles this:

```c
static bool_t qp_table_function_callback(
  struct ast_node *_Nonnull ast,
  void *_Nullable context,
  charbuf *_Nonnull output)
{
  Contract(is_ast_table_function(ast));
  EXTRACT_STRING(name, ast->left);
  gen_printf("%s", name);

  if (!symtab_add(virtual_tables, name, NULL)) {
    // This virtual table is already created
    return true;
  }

  bprintf(schema_stmts, "CREATE TABLE %s (\n", name);

  sem_join *jptr = ast->sem->jptr;
  uint32_t size = jptr->tables[0]->count;
  for (uint32_t i = 0; i < size; i++) {
    if (i > 0) {
      bprintf(schema_stmts, ",\n");
    }

    CSTR type;
    sem_t core_type = core_type_of(jptr->tables[0]->semtypes[i]);
    switch (core_type) {
      case SEM_TYPE_OBJECT:
      case SEM_TYPE_BOOL:
      case SEM_TYPE_INTEGER:
      case SEM_TYPE_LONG_INTEGER:
        type = "INT";
        break;
      case SEM_TYPE_TEXT:
        type = "TEXT";
        break;
      case SEM_TYPE_BLOB:
        type = "BLOB";
        break;
      default :
        Contract(core_type == SEM_TYPE_REAL);
        type = "REAL";
    }
    bprintf(schema_stmts, "  %s %s", jptr->tables[0]->names[i], type);
  }

  bprintf(schema_stmts, "\n);\n");
  return true;
}
```

This extracts the column information from the semantic analysis result and creates a regular
table with matching columns. This won't give perfect query plans (since virtual table internals
can be complex), but it allows the query plan generator to work without requiring all the native
virtual table implementations.

### Shared Fragments with Conditionals

Shared fragments can contain conditional logic:

```sql
[[shared_fragment]]
CREATE PROC my_fragment(x INT)
BEGIN
  IF x > 10 THEN
    SELECT * FROM big_table;
  ELSE
    SELECT * FROM small_table;
  END IF;
END;
```

We can't evaluate the condition at query plan time, so we need to pick one branch. The
`if_stmt_callback` handles this:

```c
static bool_t if_stmt_callback(
  struct ast_node *_Nonnull ast,
  void *_Nullable context,
  charbuf *_Nonnull output)
{
  Contract(is_ast_if_stmt(ast));
  EXTRACT_NOTNULL(if_alt, ast->right);
  EXTRACT(elseif, if_alt->left);
  EXTRACT_NAMED_NOTNULL(elsenode, else, if_alt->right);

  int64_t branch_to_keep_index = context ? *(int64_t*) context : 1;
  ast_node *stmt_list;

  if (branch_to_keep_index <= 1) {
    EXTRACT_NOTNULL(cond_action, ast->left);
    stmt_list = cond_action->right;
  }
  else {
    int64_t curr_index = 2;
    while (elseif && curr_index < branch_to_keep_index) {
      Contract(is_ast_elseif(elseif));
      elseif = elseif->right;
      curr_index++;
    }

    if (elseif) {
      EXTRACT(cond_action, elseif->left);
      stmt_list = cond_action->right;
    }
    else {
      stmt_list = elsenode->left;
    }
  }
```

The function navigates through the IF/ELSEIF/ELSE chain to find the desired branch. The branch
number comes from the `[[query_plan_branch=n]]` attribute on the shared fragment declaration.
If not specified, it defaults to 1 (the first branch).

Importantly, if the selected branch is `SELECT NOTHING`, we fall back to branch 1:

```c
  if (is_ast_select_nothing_stmt(stmt)) {
    // If the selected branch contains SELECT NOTHING,
    // select a different branch instead for query plan generation.
    Contract(branch_to_keep_index > 1);
    branch_to_keep_index = 1;
    return if_stmt_callback(ast, (void *) &branch_to_keep_index, output);
  }
```

This ensures we always get a real query to analyze.

### Generating EXPLAIN QUERY PLAN Statements

The core work happens in `cg_qp_explain_query_stmt`, which wraps each SQL statement with
the machinery needed to capture its query plan:

```c
static void cg_qp_explain_query_stmt(ast_node *stmt) {
  sql_stmt_count++;
  CHARBUF_OPEN(proc);
  CHARBUF_OPEN(body);
  CHARBUF_OPEN(sql);
  CHARBUF_OPEN(json_str);
  CHARBUF_OPEN(c_str);

  gen_set_output_buffer(&sql);
  gen_statement_with_callbacks(stmt, cg_qp_callbacks);
```

First, it generates the transformed SQL statement using the callbacks we've registered (replacing
variables, handling functions, etc.). Then it does some complex string encoding:

```c
  // the generated statement has to be encoded in different ways, it will go out directly
  // as an explain statement starting from the basic string computed above.  However,
  // we also want to store the text of the statement as a string.  So we have to quote
  // the statement.  That's all fine and well but actually the text we want is for the
  // JSON output we will create.  So we have to JSON encode the sql and then quote
  // the JSON as a C string.
  cg_encode_json_string_literal(sql.ptr, &json_str);

  // Now that we have the JSON string we need all of that in a C string, including the
  // quotes. So we use the single character helper to build a buffer with new quotes.  Note
  // that C string encoding is slightly different than JSON, there are small escape differences.
  // So we're going to be quite careful to C-encode the JSON encoding.  It's double-encoded.
  bprintf(&c_str, "\"");
  for (uint32_t i = 1; i < json_str.used - 2; i++) {
    // json_str can have no control characters, but it might have quotes and backslashes
    cg_encode_char_as_c_string_literal(json_str.ptr[i], &c_str);
  }
  bprintf(&c_str, "\"");
```

This double-encoding is necessary because:
1. The final output will be JSON
2. The JSON contains the SQL text as a string
3. But we're generating CQL code that will print the JSON
4. So we need the SQL text encoded as a JSON string (escaping quotes, backslashes, etc.)
5. And then we need that JSON string encoded as a CQL string literal

Then it generates a procedure to capture the plan:

```c
  bprintf(&body, "LET query_plan_trivial_object := trivial_object();\n");
  bprintf(&body, "LET query_plan_trivial_blob := trivial_blob();\n\n");

  bprintf(&body, "LET stmt := %s;\n", c_str.ptr);

  bprintf(&body, "INSERT INTO sql_temp(id, sql) VALUES(%d, stmt);\n", sql_stmt_count);
  if (current_procedure_name && current_ok_table_scan && current_ok_table_scan->used > 1) {
    bprintf(
      &body,
      "INSERT INTO ok_table_scan(sql_id, proc_name, table_names) VALUES(%d, \"%s\", \"%s\");\n",
      sql_stmt_count,
      current_procedure_name,
      current_ok_table_scan->ptr
    );
  }
  bprintf(&body, "CURSOR C FOR EXPLAIN QUERY PLAN\n");
  bprintf(&body, "%s;\n", sql.ptr);
  bprintf(&body, "LOOP FETCH C\n");
  bprintf(&body, "BEGIN\n");
  bprintf(&body, "  INSERT INTO plan_temp(sql_id, iselectid, iorder, ifrom, zdetail) VALUES(%d, C.iselectid, C.iorder, C.ifrom, C.zdetail);\n", sql_stmt_count);
  bprintf(&body, "END;\n");

  bprintf(&proc, "PROC populate_query_plan_%d()\n", sql_stmt_count);
  bprintf(&proc, "BEGIN\n");
  bindent(&proc, &body, 2);
  bprintf(&proc, "END;\n\n");
```

Each SQL statement gets its own `populate_query_plan_N()` procedure that:
1. Sets up the trivial object/blob variables (for any object/blob references in the SQL)
2. Stores the SQL text in a `sql_temp` table
3. Records any "ok table scan" annotations (see below)
4. Runs `EXPLAIN QUERY PLAN` on the transformed SQL
5. Fetches all rows from the result and stores them in `plan_temp`

### The "ok_table_scan" Feature

Some table scans are expected and acceptable. The `[[ok_table_scan=...]]` attribute lets developers
mark specific tables where scanning is allowed. This information is captured during procedure processing:

```c
static void cg_qp_ok_table_scan_callback(
    CSTR _Nonnull name,
    ast_node* _Nonnull misc_attr_value,
    void* _Nullable context) {
  Contract(context && is_ast_str(misc_attr_value));

  charbuf *ok_table_scan_buf = (charbuf *)context;
  EXTRACT_STRING(table_name, misc_attr_value);
  if (ok_table_scan_buf->used > 1) {
    bprintf(ok_table_scan_buf, ",");
  }
  // The "#" around the name make it easier to do a whole-word
  // match on the table name later
  bprintf(ok_table_scan_buf, "#%s#", table_name);
}
```

The `#` delimiters allow for easy pattern matching later when checking if a scan is permitted.
This gets stored in the `ok_table_scan` table with the procedure name and SQL ID, so the final
report can filter out expected scans.

### Schema Generation

The query plan generator needs to create all the tables, views, indices, and triggers that the
original code references. This is handled by `cg_qp_sql_stmt`:

```c
static void cg_qp_sql_stmt(ast_node *ast) {
  // we only run if the item is not deleted (i.e. delete version == -1) and
  // it is not an aliased item.  That is if there are two copies of create table T1(...)
  // the 2nd identical copy should not be emitted. Same for indices, triggers, and views.
  if (ast->sem->delete_version <= 0 && !is_alias_ast(ast)) {
    charbuf *out = schema_stmts;
    if (is_backing(ast->sem->sem_type)) {
      bprintf(out, "[[backing_table]]\n");
    }
    if (is_backed(ast->sem->sem_type)) {
      out = backed_tables;

      EXTRACT_MISC_ATTRS(ast, misc_attrs);
      CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
      bprintf(out, "[[backed_by=%s]]\n", backing_table_name);
    }
    gen_set_output_buffer(out);
    gen_statement_with_callbacks(ast, cg_qp_callbacks);
    bprintf(out, ";\n");
  }
}
```

This carefully handles:
* Schema versioning (skipping deleted items)
* Aliased declarations (avoiding duplicates)
* Backing tables (which need special attributes)
* Backed tables (which go in a separate buffer and are declared outside the create_schema proc)

### UDF Stubs

For UDFs (user-defined functions declared with `DECLARE SELECT FUNCTION`), the generator creates
no-op stubs:

```c
static void cg_qp_emit_udf_stubs(charbuf *output) {
  for (list_item *item = all_functions_list; item; item = item->next) {
    EXTRACT_ANY_NOTNULL(any_func, item->ast);
    bool_t is_select_func =
      is_ast_declare_select_func_stmt(any_func) ||
      is_ast_declare_select_func_no_check_stmt(any_func);

    Contract(is_select_func  || is_ast_declare_func_stmt(any_func));

    if (is_select_func) {
      EXTRACT_STRING(name, any_func->left);
      bprintf(output, "  call cql_create_udf_stub(\"%s\");\n", name);
    }
  }
}
```

These stubs don't need to do anything real; they just need to exist so SQLite doesn't complain
about undefined functions. The actual `cql_create_udf_stub` implementation is provided by the
runtime (in test/query_plan_test.c).

### Output Generation

The final output is structured as a single CQL file that contains:

1. Helper procedures (`trivial_object`, `trivial_blob`)
2. UDF declarations
3. A `create_schema()` procedure that sets up all tables, views, indices, etc.
4. A `populate_no_table_scan()` procedure
5. Individual `populate_query_plan_N()` procedures for each SQL statement
6. Helper procedures for formatting the JSON output
7. A main `query_plan()` procedure that orchestrates everything

The main procedure looks like this:

```c
  bprintf(&output_buf, "PROC query_plan()\n");
  bprintf(&output_buf, "BEGIN\n");
  bprintf(&output_buf, "  CALL create_schema();\n");
  bprintf(&output_buf, "  TRY\n");
  bprintf(&output_buf, "    CALL populate_no_table_scan();\n");
  bprintf(&output_buf, "  CATCH\n");
  bprintf(&output_buf, "    CALL printf(\"failed populating no_table_scan table\\n\");\n");
  bprintf(&output_buf, "    THROW;\n");
  bprintf(&output_buf, "  END;\n");

  for (uint32_t i = 1; i <= sql_stmt_count; i++) {
    bprintf(&output_buf, "  TRY\n");
    bprintf(&output_buf, "    CALL populate_query_plan_%d();\n", i);
    bprintf(&output_buf, "  CATCH\n");
    bprintf(&output_buf, "    CALL printf(\"failed populating query %d\\n\");\n", i);
    bprintf(&output_buf, "    THROW;\n");
    bprintf(&output_buf, "  END;\n");
  }

  bprintf(&output_buf, "  CALL printf(\"{\\n\");\n");
  bprintf(&output_buf, "  CALL print_query_violation();\n");
  bprintf(&output_buf, "  CALL printf(\"\\\"plans\\\" : [\\n\");\n");
  bprintf(&output_buf, "  LET q := 1;\n");
  bprintf(&output_buf, "  WHILE q <= %d\n", sql_stmt_count);
  bprintf(&output_buf, "  BEGIN\n");
  bprintf(&output_buf, "    CALL printf(\"%%s\", IIF(q == 1, \"\", \",\\n\"));\n");
  bprintf(&output_buf, "    CALL print_query_plan(q);\n");
  bprintf(&output_buf, "    SET q := q + 1;\n");
  bprintf(&output_buf, "  END;\n");
  bprintf(&output_buf, "  CALL printf(\"\\n]\\n\");\n");
  bprintf(&output_buf, "  CALL printf(\"}\");\n");
  bprintf(&output_buf, "END;\n");
```

Each `populate_query_plan_N()` call is wrapped in a TRY/CATCH so that if one statement fails,
we get a clear error message about which one.

### JSON Report Structure

The final output is JSON with this structure:

```json
{
  "alerts": {
    "tableScanViolation": "...",
    "tempBTreeViolation": "..."
  },
  "plans": [
    {
      "id": 1,
      "query": "SELECT * FROM users WHERE id = 1",
      "stats": {
        "search": 1
      },
      "plan": "QUERY PLAN\n|...SEARCH users USING PRIMARY KEY"
    },
    ...
  ]
}
```

The alerts section warns about:
* Table scans on tables marked with `[[no_table_scan]]` (unless in the ok_table_scan list)
* Temporary B-trees (which can indicate inefficient queries)

The stats section counts different query plan operations (scans, searches, temp B-trees, etc.).
The plan section shows the hierarchical query plan structure.

### Why This Design?

This meta-compilation approach might seem complex, but it solves several problems elegantly:

1. **No runtime dependency**: The query plan generator doesn't need access to your application's
   runtime environment, native functions, or virtual table implementations.

2. **Standalone analysis**: You can analyze query plans without building your entire application.

3. **Repeatable**: The same input always produces the same output, making it useful for CI/CD
   to detect query plan regressions.

4. **Comprehensive**: Every SQL statement is analyzed, including those deep inside procedures
   and shared fragments.

5. **Informative**: The JSON output can be processed by other tools for visualization, alerting,
   or integration into development workflows.

The tradeoff is that the query plans aren't 100% accurate for virtual tables and the constant
substitution for variables means we don't see different plans for different parameter values.
But for the vast majority of use cases, this provides excellent visibility into how SQLite
will execute your queries.

### Design Patterns

The code exhibits several interesting patterns:

**Callback-based AST walking**: Rather than hardcoding transformations in the AST walker, the
code uses callbacks registered in `gen_sql_callbacks`. This makes the transformations composable
and testable.

**Contextual transformation**: Some callbacks behave differently inside shared fragments vs.
regular procedures (e.g., variables aren't replaced in shared fragments). Context is passed
through callback parameters.

**Progressive encoding**: The multi-stage string encoding (SQL -> JSON string -> CQL string literal)
might seem odd, but it ensures correctness at each layer without requiring complex escaping logic.

**Separation of concerns**: Schema generation, query plan collection, and report formatting are
all separate procedures in the output. This makes the generated code easier to debug.

**Error handling**: Each query plan collection is wrapped in TRY/CATCH with specific error messages,
making it easy to identify which statement caused a problem.

This query plan generator is one of the more sophisticated parts of the CQL compiler, but its
modular design and clear separation of concerns make it maintainable and extensible.
