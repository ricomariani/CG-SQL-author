---
title: "Appendix 1: AST Structure Reference"
weight: 1
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Preface

This appendix provides a comprehensive reference to the Abstract Syntax Tree (AST) node structures
used in the CQL compiler. Each diagram shows the tree structure with child nodes and their relationships.

The AST is the internal data structure that represents a CQL program after
parsing but before semantic analysis and code generation. Understanding the AST
structure is essential for compiler developers who need to work with the parser,
semantic analyzer, or any of the code generators. However, it's important to
note that **the AST structure is an implementation detail, not a contractual
interface**. The specific node types, their relationships, and even their
existence are all subject to change as the compiler evolves.

This documentation reflects the current state of the AST as implemented in the
source code. For the most up-to-date and authoritative information, always refer
to the actual implementation in `sources/ast.h` and `sources/ast.c`. The code
itself contains extensive comments and is the definitive source of truth for how
any particular node type is structured and used.

The goal here is to provide a helpful overview and reference for compiler
developers, not to create a frozen specification. As new language features are
added or existing ones are refactored, the AST will continue to evolve
accordingly.

## Notation

In the diagrams below:
- `{node_name}` - an AST node type
- `|` - introduces a child node (indentation shows nesting level)
- `?` - optional node (may be NULL)
- `+` - one or more occurrences (linked list)
- `{detail flags}` - a detail field containing bit flags
- `{name identifier}` - a name node with specific semantic meaning

## Table of Contents

- [DDL Statements](#ddl-statements)
- [DML Statements](#dml-statements)
- [Query Statements](#query-statements)
- [Query Rewrite Operations](#query-rewrite-operations)
- [Control Flow Statements](#control-flow-statements)
- [Procedure Calls](#procedure-calls)
- [Cursor Management](#cursor-management)
- [Declarations](#declarations)
- [OUT Statements](#out-statements)
- [Transaction Control](#transaction-control)
- [Schema Management](#schema-management)
- [Enforcement Control](#enforcement-control)
- [Code Generation Control](#code-generation-control)
- [Preprocessor Directives](#preprocessor-directives)
- [Debug Output](#debug-output)
- [Pipeline Operations](#pipeline-operations)
- [Query Plan Output](#query-plan-output)
- [Macro Processing](#macro-processing)
- [Expression Nodes](#expression-nodes)
- [Supporting Structures](#supporting-structures)

---

## DDL Statements

### CREATE TABLE

```
{create_table_stmt}
  | {create_table_name_flags}
    | {table_flags_attrs}
      | {detail flags}          -- TABLE_IS_TEMP, TABLE_IF_NOT_EXISTS, TABLE_IS_NO_ROWID
      | {version_attrs}?        -- optional @create/@delete annotations
    | {name table_name}
  | {col_key_list}
    | {col_def} | {pk_def} | {fk_def} | {unq_def} | {check_def} | {shape_def}
    | {col_key_list}?           -- more definitions

{col_def}
  | {col_def_type_attrs}
    | {col_def_name_type}
      | {name column_name}
      | {data_type}             -- see Data Types section
    | {col_attrs}?              -- linked list of column attributes (see below)
  | {misc_attrs}?               -- optional @attribute annotations

{col_attrs}                     -- column attribute list (linked via ->right)
  | {col_attrs_not_null}        -- NOT NULL [conflict_clause]
    | {conflict_clause}?
  | {col_attrs_pk}              -- PRIMARY KEY [conflict_clause] [AUTOINCREMENT]
    | {autoinc_and_conflict_clause}
      | {col_attrs_autoinc}?    -- AUTOINCREMENT flag
      | {conflict_clause}?      -- ON CONFLICT clause
  | {col_attrs_unique}          -- UNIQUE [conflict_clause]
    | {conflict_clause}?
  | {col_attrs_hidden}          -- HIDDEN (zero children)
  | {col_attrs_fk}              -- REFERENCES table(cols)
    | {fk_target_options}       -- see fk_target_options above
  | {col_attrs_check}           -- CHECK(expr)
    | {expr}                    -- check expression
  | {col_attrs_collate}         -- COLLATE name
    | {name collation}
  | {col_attrs_default}         -- DEFAULT expr
    | {expr}                    -- default value
  | {create_attr} | {delete_attr} | {sensitive_attr}  -- version/sensitivity attrs

{pk_def}
  | {name constraint_name}?     -- optional constraint name
  | {indexed_columns_conflict_clause}
    | {indexed_columns}
      | {indexed_column}+
    | {conflict_clause}?        -- optional ON CONFLICT clause

{fk_def}
  | {name constraint_name}?
  | {fk_info}
    | {name_list}               -- source columns
    | {fk_target_options}
      | {fk_target}
        | {name referenced_table}
        | {name_list}           -- referenced columns
      | {detail flags}          -- ON DELETE/UPDATE actions, DEFERRABLE

{unq_def}
  | {name constraint_name}?
  | {indexed_columns_conflict_clause}
    | {indexed_columns}
    | {conflict_clause}?

{check_def}
  | {name constraint_name}?
  | {expr}                      -- check expression
```

### CREATE INDEX

```
{create_index_stmt}
  | {create_index_on_list}
    | {name index_name}
    | {name table_name}
  | {index_flags_names_attrs}
    | {detail flags}            -- INDEX_UNIQUE, INDEX_IFNE
    | {connector}
      | {index_names_and_attrs}
        | {indexed_columns}
          | {indexed_column}+
            | {expr}            -- column expression
            | {asc} | {desc}?   -- optional ordering
        | {opt_where}?          -- optional partial index
      | {version_attrs}?        -- optional version annotations
```

### CREATE VIEW

```
{create_view_stmt}
  | {detail flags}              -- VIEW_IF_NOT_EXISTS, VIEW_IS_TEMP
  | {view_and_attrs}
    | {view_details_select}
      | {view_details}
        | {name view_name}
        | {name_list}?          -- optional column names
      | {select_stmt}
    | {version_attrs}?
```

### CREATE TRIGGER

```
{create_trigger_stmt}
  | {detail flags}              -- TRIGGER_IS_TEMP, TRIGGER_IF_NOT_EXISTS
  | {trigger_body_vers}
    | {trigger_def}
      | {name trigger_name}
      | {trigger_condition}
        | {detail cond_flags}   -- BEFORE, AFTER, INSTEAD_OF
        | {trigger_op_target}
          | {trigger_operation}
            | {detail op_flags} -- DELETE, INSERT, UPDATE
            | {name_list}?      -- UPDATE OF columns
          | {trigger_target_action}
            | {name table_name}
            | {trigger_action}
              | {detail action_flags} -- FOR_EACH_ROW
              | {trigger_when_stmts}
                | {expr when}?  -- optional WHEN condition
                | {stmt_list}   -- trigger body
    | {version_attrs}?
```

### CREATE VIRTUAL TABLE

```
{create_virtual_table_stmt}
  | {module_info}
    | {name module_name}
    | {misc_attr_value_list}?   -- optional module arguments
  | {create_table_stmt}         -- embedded table definition
```

### ALTER TABLE

```
{alter_table_add_column_stmt}
  | {name table_name}
  | {col_def}                   -- column to add
```

### DROP Statements

```
{drop_table_stmt}
  | {name table_name}

{drop_view_stmt}
  | {detail if_exists}?         -- optional IF EXISTS flag
  | {name view_name}

{drop_index_stmt}
  | {name index_name}

{drop_trigger_stmt}
  | {name trigger_name}
```

---

## DML Statements

### INSERT

```
{insert_stmt}
  | {detail insert_type}        -- INSERT, INSERT OR REPLACE, etc.
  | {name_columns_values}
    | {name table_name}
    | {columns_values} | {default_columns_values} | {expr_names}
      | {column_spec}?          -- optional column list
        | {name_list} | {shape_def}
      | {insert_list} | {select_stmt} | {from_shape}

{insert_list}
  | {expr} | {from_shape}       -- value or FROM cursor
  | {insert_list}?              -- more values

{insert_returning_stmt}
  | {insert_stmt} | {with_insert_stmt}
  | {select_expr_list}          -- RETURNING columns
```

#### Insert Type Flags

The `{detail insert_type}` field contains one of these zero-child nodes indicating the insert variant:

```
{insert_normal}              -- INSERT
{insert_or_abort}            -- INSERT OR ABORT
{insert_or_fail}             -- INSERT OR FAIL
{insert_or_ignore}           -- INSERT OR IGNORE
{insert_or_replace}          -- INSERT OR REPLACE
{insert_or_rollback}         -- INSERT OR ROLLBACK
{insert_replace}             -- REPLACE (shorthand for INSERT OR REPLACE)
```

#### Dummy Data Generation

CQL supports automatic generation of test data for INSERT and FETCH statements using `@DUMMY_SEED`.
This is particularly useful for testing when you want to provide some values explicitly while having
the system generate the rest.

```
{insert_dummy_spec}          -- @DUMMY_SEED(...) [options]
  | {expr seed_value}        -- seed expression for random generation
  | {detail flags}           -- INSERT_DUMMY_DEFAULTS, INSERT_DUMMY_NULLABLES

{seed_stub}                  -- placeholder after dummy spec is processed
  | {expr seed_value}        -- (same structure as insert_dummy_spec)
  | {detail flags}           -- (same flags)
                             -- Replaces insert_dummy_spec after semantic analysis
                             -- to prevent reprocessing during AST rewrites
```

### UPDATE

```
{update_stmt}
  | {name table_name}?          -- optional (for correlated updates)
  | {update_set}
    | {update_list} | {columns_values}
      | {update_entry}+
        | {name column}
        | {expr value}
    | {update_from}
      | {query_parts}?          -- optional FROM clause
      | {update_where}
        | {opt_where}?
        | {update_orderby}
          | {opt_orderby}?
          | {opt_limit}?

{update_cursor_stmt}
  | {name cursor}
  | {expr_names} | {columns_values}  -- SET using expressions or values

{update_returning_stmt}
  | {update_stmt} | {with_update_stmt}
  | {select_expr_list}          -- RETURNING columns
```

### DELETE

```
{delete_stmt}
  | {name table_name}
  | {opt_where}?                -- optional WHERE clause

{delete_returning_stmt}
  | {delete_stmt} | {with_delete_stmt}
  | {select_expr_list}          -- RETURNING columns
```

### UPSERT

```
{upsert_stmt}
  | {insert_stmt}               -- INSERT portion
  | {upsert_update}
    | {conflict_target}
      | {indexed_columns}?      -- ON CONFLICT columns
      | {opt_where}?            -- optional conflict WHERE
    | {update_stmt}?            -- DO UPDATE (NULL = DO NOTHING)

{upsert_returning_stmt}
  | {upsert_stmt} | {with_upsert_stmt}
  | {select_expr_list}          -- RETURNING columns
```

---

## Query Statements

### SELECT

```
{select_stmt}
  | {select_core_list}
    | {select_core}
      | {select_opts}?          -- ALL, DISTINCT, DISTINCTROW
      | {select_expr_list_con}
        | {select_expr_list}
          | {select_expr}+
            | {expr}
            | {opt_as_alias}?
        | {select_from_etc}?    -- FROM, WHERE, GROUP BY, HAVING, WINDOW
          | {query_parts}?      -- FROM clause
          | {select_where}
            | {opt_where}?
            | {select_groupby}
              | {opt_groupby}?
              | {select_having}
                | {opt_having}?
                | {opt_select_window}?
    | {select_core_compound}?   -- UNION, INTERSECT, EXCEPT + more cores
  | {select_orderby}
    | {opt_orderby}?
    | {select_limit}
      | {opt_limit}?
      | {select_offset}?
        | {opt_offset}?

{select_expr}
  | {expr}                      -- column expression
  | {opt_as_alias}?             -- optional AS alias

{select_values}                 -- VALUES (row1), (row2), ...
  | {values}+
    | {insert_list}             -- value expressions
    | {values}?                 -- more rows

{select_nothing_stmt}           -- SELECT NOTHING (no children)
                                -- special statement for empty result set

{with_select_stmt}
  | {with} | {with_recursive}
    | {cte_tables}+             -- one or more CTEs
  | {select_stmt}
```

### Common Table Expressions (CTEs)

```
{cte_table}
  | {cte_decl}
    | {name cte_name}
    | {name_list} | {star}?     -- optional column names
  | {select_stmt} | {shared_cte} | {like}

{cte_tables}
  | {cte_table} | {cte_tables_macro_ref}
  | {cte_tables}?               -- more CTEs (comma separated)

{shared_cte}
  | {call_stmt}                 -- procedure call
  | {cte_binding_list}?         -- optional USING bindings
    | {cte_binding}+
      | {name actual}
      | {name formal}
```

### JOIN Clauses

```
{join_clause}
  | {table_or_subquery}         -- first table
  | {join_target_list}
    | {join_target}+
      | {detail join_type}      -- INNER, CROSS, LEFT, RIGHT, etc.
      | {table_join}
        | {table_or_subquery}
        | {join_cond}?          -- ON or USING clause
          | {on} | {using}
          | {expr} | {name_list}

{table_or_subquery}
  | {name} | {select_stmt} | {table_function} | {shared_cte} | {join_clause}
  | {opt_as_alias}?             -- optional alias

{table_or_subquery_list}
  | {table_or_subquery}+        -- comma-separated list
```

### Window Functions

```
{window_func_inv}
  | {call}                      -- function call
  | {window_defn} | {name}      -- OVER clause (inline or named)

{window_defn}
  | {opt_partition_by}?
    | {expr_list}               -- PARTITION BY expressions
  | {window_defn_orderby}
    | {opt_orderby}?
    | {opt_frame_spec}?
      | {detail flags}          -- frame type, boundary, exclude flags
      | {expr_list}             -- boundary expressions

{window_clause}
  | {window_name_defn_list}
    | {window_name_defn}+
      | {name window_name}
      | {window_defn}
```

#### Window Frame Boundary Nodes

These internal nodes represent different parts of window frame specifications (ROWS/RANGE/GROUPS BETWEEN...):

```
{frame_boundary}             -- single boundary (expr PRECEDING/FOLLOWING/etc.)
  | {expr}?                  -- optional boundary expression
  -- flags indicate: UNBOUNDED, PRECEDING, CURRENT ROW

{frame_boundary_start}       -- BETWEEN start boundary
  | {expr_list}              -- contains start expression in left
  -- flags indicate: START_UNBOUNDED, START_PRECEDING, START_CURRENT_ROW, START_FOLLOWING

{frame_boundary_end}         -- AND end boundary
  | {expr_list}              -- contains end expression in right
  -- flags indicate: END_PRECEDING, END_CURRENT_ROW, END_FOLLOWING, END_UNBOUNDED

{frame_boundary_opts}        -- frame boundary options wrapper
  -- flags for frame type (ROWS/RANGE/GROUPS) and EXCLUDE clauses

{following}                  -- FOLLOWING keyword node (used in frame specs)
```

### Table-Valued Functions

```
{table_function}
  | {name function_name}
  | {arg_list}                  -- function arguments
                                -- Must be a declared function returning struct type
                                -- Used in FROM clause: SELECT * FROM my_func(args)
```

---

## Query Rewrite Operations

These internal AST nodes are created during the rewrite phase, which occurs before semantic analysis.
They represent transformations of the original SQL syntax into optimized or expanded forms.

### Column Calculation (@COLUMNS expansion)

The `column_calculation` node represents the `@COLUMNS(...)` directive, which is expanded during AST
rewriting to generate explicit column lists. This is a pre-semantic-analysis transformation.

```
{column_calculation}
  | {expr}                      -- the @COLUMNS(...) expression
                                -- Replaced during rewrite with expanded column list
```

**Supported Forms:**
- `@COLUMNS(table)` - expands to all columns from the named table
- `@COLUMNS(table.column)` - expands to table.column (useful with wildcards)
- `@COLUMNS(LIKE shape)` - expands to columns matching a shape
- `@COLUMNS(DISTINCT ...)` - expands with duplicate column removal

**Example:**
```sql
SELECT @COLUMNS(T1), @COLUMNS(T2) FROM T1 JOIN T2;
-- Expands to:
SELECT T1.col1, T1.col2, T2.col1, T2.col2 FROM T1 JOIN T2;
```

The node is completely replaced during the rewriting phase, so it never reaches semantic analysis.
This allows compile-time generation of column lists based on table/cursor shapes.

### USING Expression Syntax (expr_names)

The `expr_names` and `expr_name` nodes represent the sugar syntax for USING clauses in INSERT,
FETCH, and UPDATE statements. This syntax is rewritten during semantic analysis into the standard
`columns_values` structure.

```
{expr_names}
  | {expr_name}
    | {expr value}
    | {opt_as_alias}            -- alias (becomes column name)
  | {expr_names}?               -- more expression/alias pairs

{expr_name}                     -- single expression/alias pair
  | {expr value}
  | {opt_as_alias}              -- alias (becomes column name)
```

**Example Transformation:**
```sql
FETCH C USING 1 a, 2 b, 3 c;
-- Rewritten to:
FETCH C(a, b, c) VALUES(1, 2, 3);

INSERT INTO T USING x+1 col1, y*2 col2;
-- Rewritten to:
INSERT INTO T(col1, col2) VALUES(x+1, y*2);
```

The rewrite process:
1. Extracts each `expr_name` pair (value expression + alias)
2. Builds a `name_list` from the aliases (column names)
3. Builds an `insert_list` from the value expressions
4. Transforms the original `expr_names` node into a `columns_values` node
5. The result uses standard SQL syntax for the rest of semantic analysis

This allows users to write more concise code while maintaining compatibility with standard SQL semantics.

### String Chain Concatenation (str_chain)

The `str_chain` node represents intermediate parsing of adjacent string literals that are
automatically concatenated during parsing. This is a temporary AST structure that gets
reduced to a single string literal.

```
{str_chain}
  | {str} | {cstr}               -- string literal (STRLIT or CSTRLIT)
  | {str_chain}?                -- more string literals (right-linked)
                                -- Reduced to single string by reduce_str_chain()
```

**Example Transformation:**
```sql
"Hello " "world" "!"  -- Three adjacent string literals
-- Automatically becomes:
"Hello world!"        -- Single concatenated string literal
```

The parser processes adjacent string literals by:
1. Creating a `str_chain` with linked string nodes
2. Calling `reduce_str_chain()` to concatenate all pieces
3. Replacing the chain with a single `str` node containing the merged content
4. The result behaves exactly like a single string literal

This enables convenient string literal concatenation at parse time without runtime overhead,
similar to C string literal concatenation.

### BETWEEN Rewrite

The `between_rewrite` node is an internal optimization created during semantic analysis. It represents
the canonical form of BETWEEN expressions for code generation, while preserving the original syntax
for output.

```
{between_rewrite}
  | {expr value}                -- value to test
  | {range}
    | {low_expr}                -- lower bound
    | {high_expr}               -- upper bound
```

When the user writes `expr BETWEEN low AND high`, the semantic analyzer:
1. Creates a `between_rewrite` node for internal processing
2. Transforms it to equivalent comparison: `expr >= low AND expr <= high`
3. Uses `gen_sql.c` to echo back the original BETWEEN syntax in generated output

This allows optimization and analysis on the canonical form while maintaining readable output.
The NOT BETWEEN variant follows the same pattern with inverted logic.

---

## Control Flow Statements

### IF Statement

```
{if_stmt}
  | {cond_action}
    | {expr}                    -- IF condition
    | {stmt_list}               -- THEN body
  | {if_alt}
    | {elseif}?                 -- ELSE IF clauses (linked list)
      | {cond_action}
      | {elseif}?
    | {else}?
      | {stmt_list}             -- ELSE body
```

### SWITCH Statement

```
{switch_stmt}
  | {detail all_values}         -- optional ALL VALUES flag
  | {switch_body}
    | {expr}                    -- switch expression
    | {switch_case}+
      | {connector}
        | {expr_list} | NULL    -- WHEN values (NULL = ELSE)
        | {stmt_list}           -- case body
      | {switch_case}?          -- more cases
```

### WHILE Loop

```
{while_stmt}
  | {expr}                      -- loop condition
  | {stmt_list}                 -- loop body
```

### LOOP Statement

```
{loop_stmt}
  | {fetch_stmt}                -- cursor fetch
  | {stmt_list}                 -- loop body
```

### FOR Statement (with step)

```
{for_stmt}
  | {expr}                      -- iterator expression
  | {for_info}
    | {stmt_list step}          -- step statement(s)
    | {stmt_list body}          -- loop body
```

### Guard Statement

```
{guard_stmt}
  | {expr}                      -- guard condition
  | {stmt}                      -- guarded statement (typically RETURN)
```

### Exception Handling

```
{trycatch_stmt}
  | {stmt_list}                 -- TRY block
  | {stmt_list}                 -- CATCH block
```

### Flow Control

```
{continue_stmt}                 -- CONTINUE (no children)
{leave_stmt}                    -- LEAVE (no children)
{return_stmt}                   -- RETURN (no children)
{throw_stmt}                    -- THROW (no children)
{commit_return_stmt}            -- COMMIT RETURN (no children)
{rollback_return_stmt}          -- ROLLBACK RETURN (no children)
```

---

## Procedure Calls

```
{call_stmt}
  | {name proc_name}
  | {arg_list}?

{declare_out_call_stmt}
  | {call_stmt}                 -- DECLARE OUT CALL proc(...)
                                -- Convenience statement: auto-declares OUT parameters
                                -- that don't already exist, then calls the procedure

{fetch_call_stmt}
  | {name cursor_name}
  | {call_stmt}                 -- FETCH cursor FROM CALL proc(...)
```

---

## Cursor Management

### Cursor Declarations

```
{declare_cursor_like_select}
  | {name cursor_name}
  | {select_stmt}               -- CURSOR name LIKE SELECT ...

{declare_cursor_like_name}
  | {name cursor_name}
  | {shape_def}                 -- CURSOR name LIKE shape

{declare_value_cursor}
  | {name cursor_name}
  | {stmt}                      -- CURSOR name FETCH FROM stmt

{declare_cursor_like_typed_names}
  | {name cursor_name}
  | {typed_names}               -- CURSOR name LIKE (col1 type, col2 type, ...)

{declare_cursor}              -- generic cursor declaration (internal)
                              -- used during semantic analysis
```

### Cursor Operations

```
{fetch_stmt}
  | {name cursor_name}
  | {name_list}?                -- optional INTO variables

{fetch_values_stmt}
  | {insert_dummy_spec}?        -- optional @DUMMY_SEED
  | {name_columns_values}
    | {name cursor_name}
    | {columns_values} | {expr_names}

{fetch_call_stmt}
  | {name cursor_name}
  | {call_stmt}                 -- FETCH cursor FROM CALL proc(...)

{close_stmt}
  | {name cursor}

{set_from_cursor}
  | {name variable}             -- object<T cursor> variable
  | {name cursor}               -- SET var FROM CURSOR cursor
                                -- "Boxes" a statement cursor into an object variable
                                -- Variable must be of type object<T cursor> where
                                -- T matches the cursor's shape
```

---

## Declarations

### Procedures

```
{create_proc_stmt}
  | {name proc_name}
  | {proc_params_stmts}
    | {params}?
      | {param}+
        | {in} | {out} | {inout}?
        | {param_detail}
          | {name param_name}
          | {data_type} | {shape_def}
    | {stmt_list}               -- procedure body

{declare_proc_stmt}
  | {proc_name_type}
    | {name proc_name}
    | {detail type}             -- USES_OUT, USES_OUT_UNION, USES_DML, etc.
  | {proc_params_stmts}
    | {params}?
    | {typed_names}?            -- result shape (OUT/SELECT)

{declare_interface_stmt}
  | {name interface_name}
  | {proc_params_stmts}
    | NULL                      -- no params for interface
    | {typed_names}             -- result columns

{declare_proc_no_check_stmt}
  | {name proc_name}          -- DECLARE PROC name NO CHECK
                              -- declares procedure without type checking
```

### Functions

```
{declare_func_stmt}
  | {name func_name}
  | {func_params_return}
    | {params}?
    | {data_type}               -- return type

{declare_select_func_stmt}
  | {name func_name}
  | {func_params_return}
    | {params}?
    | {data_type} | {typed_names}  -- scalar or table function
```

### Variables

```
{declare_vars_type}
  | {name_list}                 -- variable names
  | {data_type}

{declare_named_type}
  | {name type_name}
  | {data_type}                 -- TYPE name = data_type
```

### Enums & Constants

```
{declare_enum_stmt}
  | {typed_name}
    | {name enum_name}
    | {data_type}
  | {enum_values}
    | {enum_value}+
      | {name}
      | {expr}

{declare_const_stmt}
  | {name group_name}
  | {const_values}              -- list of name = expr pairs
    | {const_value}+
      | {name constant_name}
      | {expr value}            -- constant expression
    | {const_values}?           -- more constants

{const_value}                   -- individual constant name/value pair
  | {name constant_name}
  | {expr value}                -- must be compile-time constant expression

{declare_group_stmt}
  | {name group_name}           -- DECLARE GROUP name
  | {stmt_list}                 -- declarations in the group
                                -- groups related declarations together
```

---

## OUT Statements

OUT statements are used to return result sets from procedures.

```
{out_stmt}
  | {name cursor}               -- OUT cursor_name

{out_union_stmt}
  | {name cursor}               -- OUT UNION cursor_name

{out_union_parent_child_stmt}
  | {call_stmt}                 -- parent procedure
  | {child_results}             -- child procedures joined
    | {child_result}+
      | {call_stmt}             -- child procedure call
      | {named_result}
        | {name alias}?         -- optional AS name
        | {name_list columns}   -- USING columns
    | {child_results}?          -- more children (AND)
```

---

## Transaction Control

```
{begin_trans_stmt}
  | {detail mode}               -- TRANS_DEFERRED, TRANS_IMMEDIATE, TRANS_EXCLUSIVE

{commit_trans_stmt}             -- COMMIT (no children)

{rollback_trans_stmt}
  | {name savepoint_name}?      -- optional TO SAVEPOINT

{savepoint_stmt}
  | {name savepoint_name}

{release_savepoint_stmt}
  | {name savepoint_name}

{proc_savepoint_stmt}
  | {stmt_list}                 -- PROC SAVEPOINT BEGIN ... END
```

---

## Schema Management

CQL provides directives for managing schema regions and upgrade scripts.

### Region Management

```
{declare_schema_region_stmt}
  | {name region_name}
  | {region_list}?              -- optional USING regions

{declare_deployable_region_stmt}
  | {name region_name}
  | {region_list}?              -- optional USING regions

{begin_schema_region_stmt}
  | {name region_name}

{end_schema_region_stmt}        -- @END_SCHEMA_REGION (no children)

{region_list}
  | {region_spec}+              -- one or more regions (comma separated)

{region_spec}
  | {name region_name}
  | {detail type}               -- PRIVATE_REGION or 0
```

### Schema Upgrade Directives

```
{schema_upgrade_script_stmt}    -- @SCHEMA_UPGRADE_SCRIPT (no children)

{schema_upgrade_version_stmt}
  | {detail version}            -- @SCHEMA_UPGRADE_VERSION(n)

{previous_schema_stmt}          -- @PREVIOUS_SCHEMA (no children)

{schema_ad_hoc_migration_stmt}
  | {version_annotation} | {name group}  -- version/proc or recreate group
  | {name proc}?                -- optional migration proc

{schema_unsub_stmt}
  | {version_annotation}
    | {detail version}
    | {name migration_proc}     -- @UNSUB(proc)
```

---

## Enforcement Control

CQL provides directives to control strict enforcement of various language features and patterns.

```
{enforce_strict_stmt}
  | {detail option}             -- @ENFORCE_STRICT option
                                -- options: CAST, JOIN, FK ON UPDATE, UPSERT STATEMENT,
                                -- WINDOW FUNCTION, WITHOUT ROWID, TRANSACTION,
                                -- SELECT IF NOTHING, INSERT SELECT, TABLE FUNCTION,
                                -- IS TRUE, SIGN FUNCTION, CURSOR HAS ROW,
                                -- UPDATE FROM, AND OR NOT NULL CHECK, FK ON DELETE

{enforce_normal_stmt}
  | {detail option}             -- @ENFORCE_NORMAL option (same options as strict)

{enforce_reset_stmt}            -- @ENFORCE_RESET (no children)

{enforce_push_stmt}             -- @ENFORCE_PUSH (no children)

{enforce_pop_stmt}              -- @ENFORCE_POP (no children)
```

---

## Code Generation Control

These directives control what gets emitted during code generation.

```
{emit_enums_stmt}
  | {name_list}?                -- @EMIT_ENUMS [enum_list]
                                -- optional list of enums to emit

{emit_constants_stmt}
  | {name_list}                 -- @EMIT_CONSTANTS group_list
                                -- list of constant groups to emit

{emit_group_stmt}
  | {name_list}?                -- @EMIT_GROUP [group_list]
                                -- optional list of groups to emit
```

---

## Preprocessor Directives

CQL supports compile-time conditional compilation directives that are evaluated during parsing.
These allow code to be included or excluded based on preprocessor definitions.

### Conditional Compilation

```
{ifdef_stmt}
  | {is_true} | {is_false}       -- evaluation result (based on preprocessor state)
  | {pre}                       -- conditional body wrapper
    | {stmt_list then_body}     -- statements to include if condition is true
    | {stmt_list else_body}?    -- optional @ELSE statements

{ifndef_stmt}
  | {is_true} | {is_false}       -- evaluation result (inverted from ifdef)
  | {pre}                       -- conditional body wrapper
    | {stmt_list then_body}     -- statements to include if condition is false
    | {stmt_list else_body}?    -- optional @ELSE statements

{pre}                           -- preprocessor conditional body wrapper
  | {stmt_list then_body}       -- statements for true condition
  | {stmt_list else_body}?      -- optional statements for false condition (@ELSE)
```

**Usage:**
```sql
@IFDEF FEATURE_X
  -- This code only included if FEATURE_X is defined
  CREATE TABLE feature_table(id INTEGER);
@ELSE
  -- This code included if FEATURE_X is not defined
  CREATE TABLE fallback_table(id INTEGER);
@ENDIF

@IFNDEF DEBUG_MODE
  -- This code excluded in debug builds
  PRAGMA optimize;
@ENDIF
```

The preprocessor evaluates these directives during parsing:
1. `@IFDEF name` checks if `name` is defined in the preprocessor symbol table
2. `@IFNDEF name` checks if `name` is NOT defined
3. The result becomes either `{is_true}` or `{is_false}` in the AST
4. During semantic analysis, only the appropriate branch is processed
5. The unused branch is completely ignored

This allows conditional compilation for different build configurations, feature flags,
and platform-specific code without runtime overhead.

---

## Debug Output

The echo statement provides manual debug output during compilation.

```
{echo_stmt}
  | {name runtime_name}         -- @ECHO target, "message"
  | {str message}               -- string literal to echo
```

---

## Pipeline Operations

Custom pipeline operators can be declared for use in query pipelines.

```
{op_stmt}
  | {data_type}                 -- @OP type : operand1 operand2 AS result
  | {op_vals}
    | {name operand1}
    | {op_vals}
      | {name operand2}
      | {name result}
```

---

## Query Plan Output

Statements for generating and controlling query plan output.

```
{explain_stmt}
  | {detail query_plan_flag}    -- EXPLAIN or EXPLAIN QUERY PLAN
  | {stmt}                      -- statement to explain

{keep_table_name_in_aliases_stmt}  -- @KEEP_TABLE_NAME_IN_ALIASES (no children)
                                   -- preserves table names in column aliases

---

## Macro Processing

CQL supports compile-time macros for code reuse and generation. Macros can capture expressions,
statement lists, query parts, SELECT cores, SELECT expressions, and CTE tables.

### Macro Components

#### Macro Formals

```
{macro_formal}
  | {name type}                -- formal type (EXPR!, STMT!, etc.)
  | {name param_name}          -- parameter name

{macro_formals}
  | {macro_formal}             -- type! name
  | {macro_formals}?           -- more formals

{macro_name_formals}
  | {name macro_name}
  | {macro_formals}?           -- formal parameters
```

### Macro Definitions

#### Expression Macros

```
{expr_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {expr body}                -- macro body expression

{expr_macro_arg}             -- argument in expr macro definition
{expr_macro_arg_ref}         -- reference to expr macro argument
```

#### Statement List Macros

```
{stmt_list_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {stmt_list body}           -- macro body statements

{stmt_list_macro_arg}        -- argument in stmt list macro definition
{stmt_list_macro_arg_ref}    -- reference to stmt list macro argument
```

#### SELECT Core Macros

```
{select_core_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {select_core_list body}    -- macro body

{select_core_macro_arg}      -- argument in select core macro definition
{select_core_macro_arg_ref}  -- reference to select core macro argument
```

#### SELECT Expression Macros

```
{select_expr_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {select_expr_list body}    -- macro body

{select_expr_macro_arg}      -- argument in select expr macro definition
{select_expr_macro_arg_ref}  -- reference to select expr macro argument
```

#### Query Parts Macros

```
{query_parts_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {query_parts body}         -- macro body (FROM clause)

{query_parts_macro_arg}      -- argument in query parts macro definition
{query_parts_macro_arg_ref}  -- reference to query parts macro argument
```

#### CTE Tables Macros

```
{cte_tables_macro_def}
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?         -- formal parameters
  | {cte_tables body}          -- macro body (CTE list)

{cte_tables_macro_arg}       -- argument in cte tables macro definition
{cte_tables_macro_arg_ref}   -- reference to cte tables macro argument
```

### Macro References

Macro references are used to invoke macros in code. All macro reference types share the same structure:

```
{expr_macro_ref}             -- invocation of expression macro
{stmt_list_macro_ref}        -- invocation of statement list macro
{select_core_macro_ref}      -- invocation of select core macro
{select_expr_macro_ref}      -- invocation of select expr macro
{query_parts_macro_ref}      -- invocation of query parts macro
{cte_tables_macro_ref}       -- invocation of cte tables macro
{unknown_macro_ref}          -- invocation of unknown macro type

-- All macro references have the same structure:
  | {name macro_name}
  | {macro_args}?              -- optional arguments
    | {macro_arg}+             -- argument list
      | {expr} |               -- expression argument
        {query_parts_macro_arg} |  -- FROM(query_parts)
        {select_core_macro_arg} |  -- ROWS(select_core_list)
        {select_expr_macro_arg} |  -- SELECT(select_expr_list)
        {cte_tables_macro_arg} |   -- WITH(cte_tables)
        {stmt_list_macro_arg} |    -- BEGIN...END(stmt_list)
        {*_macro_ref}          -- nested macro reference
    | {macro_args}?            -- more arguments
```

### Macro Argument and Parameter References

All macro argument types share a common structure - they wrap the actual content being passed:

```
{expr_macro_arg}             -- wraps expression argument
  | {expr}                   -- the expression content

{query_parts_macro_arg}      -- wraps query parts (FROM clause)
  | {query_parts}            -- table_or_subquery_list or join_clause

{select_core_macro_arg}      -- wraps SELECT core
  | {select_core_list}       -- SELECT statement body

{select_expr_macro_arg}      -- wraps SELECT expression list
  | {select_expr_list}       -- column expressions

{cte_tables_macro_arg}       -- wraps CTE tables
  | {cte_tables}             -- CTE definitions

{stmt_list_macro_arg}        -- wraps statement list
  | {stmt_list}              -- statements

{unknown_macro_arg}          -- wraps unknown argument type
  | {content}                -- content determined at semantic analysis
```

Macro parameter references (used within macro bodies to reference formal parameters):

```
{expr_macro_arg_ref}         -- reference to expression parameter
{query_parts_macro_arg_ref}  -- reference to query parts parameter
{select_core_macro_arg_ref}  -- reference to select core parameter
{select_expr_macro_arg_ref}  -- reference to select expr parameter
{cte_tables_macro_arg_ref}   -- reference to cte tables parameter
{stmt_list_macro_arg_ref}    -- reference to statement list parameter
{unknown_macro_arg_ref}      -- reference to unknown parameter

-- All macro argument references have the same structure:
  | {name param_name}        -- name of the formal parameter
```

### Unknown/Generic Macros

These nodes handle macros where the type cannot be determined during parsing. This occurs when:
- A macro is referenced but hasn't been defined yet
- The macro name cannot be resolved in the symbol table

**Important**: Unknown macro nodes are allowed during parsing to enable error-tolerant parsing, but they
**will cause compilation errors** during macro expansion. When an unknown macro is encountered during the
macro expansion phase, error **CQL0083** is reported: "macro reference is not a valid macro".

The parser creates these nodes when `resolve_macro_name()` returns `EOF`, meaning the macro name is not
found in either the macro definition table or the macro argument table.

```
Unknown_macro_def can't happen but it existgs for completeness.  A unit test
forces creation of this node which otherwise would be unused.  This allows
the unknown types to mirror the others.  The others can happen if the macro name
lookup fails.

{unknown_macro_def}          -- macro definition of unknown/unresolved type
  | {macro_name_formals}
    | {name macro_name}
    | {macro_formals}?
  | {content}                -- body type cannot be determined

{unknown_macro_ref}          -- macro invocation when type is unknown
  | {name macro_name}        -- the unresolved macro name
  | {macro_args}?            -- optional arguments (same structure as other refs)

{unknown_macro_arg}          -- macro argument wrapper of unknown type
  | {content}                -- argument content of unknown type

{unknown_macro_arg_ref}      -- reference to parameter of unknown type
  | {name param_name}        -- name of the unresolved formal parameter
```

---

## Expression Nodes

### Expression Statement

The `expr_stmt` node wraps an expression for use as a standalone statement.

```
{expr_stmt}
  | {expr}                     -- standalone expression statement
```

### Literals

```
{num}                           -- numeric literal (value:type in sem_node)
{str}                           -- string literal or identifier
{blob}                          -- blob literal X'...' or @FILE('...')
{null}                          -- NULL literal
```

### Identifiers

```
{name}                          -- simple identifier
{dot}                           -- qualified name
  | {name scope}                -- scope.name
  | {name ident}

{at_id}                         -- @ID(...) token paste
  | {text_args}
```

### Unary Operators

```
{uminus}                        -- unary minus
  | {expr}

{not}                           -- logical NOT
  | {expr}

{tilde}                         -- bitwise NOT
  | {expr}

{const}                         -- CONST(expr)
  | {expr}
```

### Binary Operators

#### Arithmetic

```
{add} | {sub} | {mul} | {div} | {mod}
  | {left_expr}
  | {right_expr}
```

#### Assignment Operators

```
{assign}                        -- := (also used as statement)
  | {name variable}
  | {expr value}

{expr_assign}                   -- := in expression context
  | {expr left}
  | {expr right}
                                -- Created during rewrite of compound assignments
                                -- (e.g., x += 5 becomes x := x + 5)

{add_eq} | {sub_eq} | {mul_eq} | {div_eq} | {mod_eq}  -- +=, -=, *=, /=, %=
  | {left_expr}
  | {right_expr}

{and_eq} | {or_eq}              -- &=, |= (bitwise)
  | {left_expr}
  | {right_expr}

{ls_eq} | {rs_eq}               -- <<=, >>= (shift)
  | {left_expr}
  | {right_expr}
```

#### Comparison

```
{eq} | {ne} | {lt} | {gt} | {le} | {ge}
  | {left_expr}
  | {right_expr}

{is} | {is_not}
  | {left_expr}
  | {right_expr}

{is_true} | {is_false} | {is_not_true} | {is_not_false}
  | {expr}

```

#### Logical

```
{and} | {or}
  | {left_expr}
  | {right_expr}
```

#### Bitwise

```
{bin_and} | {bin_or} | {lshift} | {rshift}
  | {left_expr}
  | {right_expr}
```

#### String & Pattern Matching

```
{concat}                        -- string concatenation ||
  | {left_expr}
  | {right_expr}

{like} | {not_like} | {glob} | {not_glob} | {match} | {not_match} | {regexp} | {not_regexp}
  | {left_expr}
  | {right_expr}

{collate}
  | {left_expr}
  | {right_expr}                -- collation name
```

#### JSON Operators

```
{jex1}                          -- JSON extract ->
  | {expr json}
  | {expr path}

{jex2}                          -- JSON extract ->>
  | {expr json}
  | {jex2_right}
    | {data_type}               -- type annotation
    | {expr path}
```

### Special Predicates

```
{between}
  | {expr}                      -- value to test
  | {range}
    | {low_expr}
    | {high_expr}

{not_between}
  | {expr}
  | {range}
    | {low_expr}
    | {high_expr}

{in_pred}
  | {expr}                      -- value to test
  | {expr_list} | {select_stmt} | NULL

{not_in}
  | {expr}
  | {expr_list} | {select_stmt}?
```

### Function Calls

```
{call}
  | {name function_name}
  | {call_arg_list}
    | {call_filter_clause}
      | {distinct}?             -- optional DISTINCT
      | {opt_filter_clause}?
        | {opt_where}           -- FILTER (WHERE expr)
    | {arg_list}
      | {expr}+ | {star} | {from_shape}

{exists_expr}
  | {select_stmt}

{raise}
  | {detail flags}              -- RAISE_IGNORE, RAISE_ROLLBACK, etc.
  | {expr}?                     -- optional error message
```

### CASE Expression

```
{case_expr}
  | {expr}?                     -- optional base expression (CASE x WHEN...)
  | {connector}
    | {case_list}
      | {when}+
        | {expr when_cond}
        | {expr then_value}
      | {case_list}?
    | {expr else_value}?        -- optional ELSE
```

### Type Operations

```
{cast_expr}
  | {expr}                      -- expression to cast
  | {data_type}                 -- target type

{type_check_expr}
  | {expr}                      -- expression to type check
  | {data_type}                 -- expected type
```

### SELECT Expressions

```
{select_if_nothing_throw_expr} | {select_if_nothing_or_null_throw_expr}
  | {select_stmt}               -- (SELECT ... IF NOTHING THROW)

{select_if_nothing_expr} | {select_if_nothing_or_null_expr}
  | {select_stmt}
  | {expr else_value}           -- (SELECT ... IF NOTHING default)
```

### Arrays & Special Operators

```
{array}                         -- array subscript
  | {expr array}
  | {arg_list}                  -- index arguments

{reverse_apply}                 -- foo:bar() operator
  | {left_expr}
  | {right_expr}

{reverse_apply_poly_args}       -- :():() no-name polymorphic form
  | {left_expr}
  | {arg_list}
```

---

## Supporting Structures

### Lists

```
{name_list}
  | {name}
  | {name_list}?                -- more names (linked list)

{expr_list}
  | {expr}
  | {expr_list}?                -- more expressions

{arg_list}
  | {expr} | {star} | {from_shape}
  | {arg_list}?                 -- more arguments

{stmt_list}
  | {stmt} | {stmt_and_attr}     -- statement or statement with attributes
  | {stmt_list}?                -- more statements

{stmt_and_attr}                -- statement wrapper with attributes
  | {misc_attrs}                -- attribute list (@ATTRIBUTE(...))
  | {stmt}                      -- the wrapped statement
                                -- Used to associate metadata with statements
                                -- for validation and code generation control

{typed_names}
  | {typed_name}
    | {name}?                   -- optional parameter name
    | {data_type} | {shape_def}
  | {typed_names}?
```

### Shapes

```
{shape_def}
  | {like}
    | {name}                    -- source table/cursor
    | {name_list}?              -- optional column filter
  | {shape_exprs}?              -- optional column expressions
    | {shape_expr}+
      | {name column}
      | {expr value}            -- column := expr

{from_shape}
  | {column_spec}?              -- optional column list
  | {name shape_name}           -- FROM cursor/arguments

{column_spec}
  | {name_list} | {shape_def}   -- column names or LIKE shape
```

### Data Types

```
{data_type}                     -- nested structure with modifiers
  | {create_data_type}?         -- optional CREATE
    | {sensitive_attr}?         -- optional @SENSITIVE
      | {notnull}?              -- optional NOT NULL
        | {type_int} | {type_long} | {type_real} | {type_bool} |
          {type_text} | {type_blob} | {type_object} | {type_cursor} |
          {name custom_type}
          | {name kind}?        -- optional for type_object
```

### Attributes & Annotations

```
{misc_attrs}
  | {misc_attr}+
    | {dot} | {name}            -- @attribute or [[cql:attr]]
    | {misc_attr_value}?        -- optional value
      | {misc_attr_value_list}?

{version_attrs}                 -- @create/@delete/@recreate chain
  | {create_attr} | {delete_attr} | {recreate_attr}
    | {version_annotation}
      | {detail version}
      | {dot} | {name}?         -- optional migration proc
```

### Query Parts

```
{opt_where}
  | {expr}                      -- WHERE condition

{opt_groupby}
  | {groupby_list}
    | {groupby_item}+
      | {expr}

{opt_orderby}
  | {orderby_list}
    | {orderby_item}+
      | {expr}
      | {asc} | {desc}?         -- with optional NULLS FIRST/LAST

{opt_limit}
  | {expr}

{opt_offset}
  | {expr}

{opt_as_alias}
  | {name alias}
```

### Assignment Statements

```
{assign}
  | {name variable}
  | {expr value}                -- SET var := expr

{let_stmt}
  | {name variable}
  | {expr value}                -- LET var := expr

{const_stmt}
  | {name variable}
  | {expr value}                -- CONST var := expr
```

---

## Notes

- Nodes marked with `?` are optional and may be NULL
- Nodes marked with `+` appear one or more times in a linked list (using `->right`)
- Most lists use the pattern: `{item} | {list}?` where right child is the rest of the list
- The `{detail flags}` field stores bit flags for various options
- Semantic information is stored in parallel `sem_node` structures (not shown here)
- The actual implementation is in [sources/ast.h](../../sources/ast.h) and [sources/ast.c](../../sources/ast.c)




