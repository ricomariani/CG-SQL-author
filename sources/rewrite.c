/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)

// stubs to avoid link errors (none needed)

#else

// Most of the functions that rewrite the AST have been hoisted out of sem.c and are here
// Rewrites always happen during semantic analysis so this is really part of that phase.

#include <stdint.h>
#include <stdio.h>
#include <limits.h>
#include "cg_common.h"
#include "compat.h"
#include "cql.h"
#include "ast.h"
#include "cql.y.h"
#include "sem.h"
#include "charbuf.h"
#include "bytebuf.h"
#include "list.h"
#include "gen_sql.h"
#include "symtab.h"
#include "eval.h"
#include "rewrite.h"
#include "printf.h"
#include "encoders.h"

static ast_node *rewrite_gen_iif_case_expr(ast_node *expr, ast_node *val1, ast_node *val2);
static bool_t rewrite_one_def(ast_node *head);
static void rewrite_one_typed_name(ast_node *typed_name, symtab *used_names);
static void rewrite_from_shape_args(ast_node *head);

// This function transforms FROM shape syntax into explicit value expressions by creating
// dot-notation column references from the shape object. It converts shape-based data
// access into standard column access patterns that can be processed by semantic analysis.
//
// Transforms: INSERT INTO table (col1, col2) FROM shape_cursor
// Into: INSERT INTO table (col1, col2) VALUES (shape_cursor.col1, shape_cursor.col2)
//
// The function validates that the shape has sufficient fields to satisfy the column
// requirements, then builds a chain of member access expressions (shape.column) for
// each requested column from the shape's field list.
//
// The function constructs AST nodes using these patterns from cql.y:
// - insert_list: insert_list ',' expr | expr
// - dot: expr '.' IDENTIFIER (member access for shape.column)
// - maybe_qstr: IDENTIFIER (for shape and column names)
//
// This enables automatic data extraction from cursors and other shaped objects.
//
// To do this rewrite we only need to check a few things:
//  * is the given name really a shape
//  * does the shape have storage (i.e. SEM_TYPE_HAS_SHAPE_STORAGE is set)
//  * were enough fields specified?
//  * were any fields requested?  [e.g. FETCH C() FROM CURSOR is meaningless]
//
// If the above conditions are met then we're basically good to go. For each column specified
// e.g. FETCH C(a,b) has two; we will take the next shape columns and add it an automatically
// created values list.  At the end the AST will be transformed into
//   FETCH C(a,b, etc.) FROM VALUES(D.col1, D.col2, etc.)
// and it can then be type checked as usual.
//
cql_noexport void rewrite_insert_list_from_shape(
  ast_node *ast,
  ast_node *from_shape,
  uint32_t count)
{
  Contract(is_ast_columns_values(ast));
  Contract(is_ast_from_shape(from_shape));
  Contract(count > 0);
  EXTRACT_ANY_NOTNULL(shape, from_shape->right); // Shape object (cursor, record, etc.)

  // from_shape must have the columns

  // Validate that the shape object has accessible fields
  // Only objects with storage (cursors, result sets) can be used as data sources
  if (!(shape->sem->sem_type & SEM_TYPE_HAS_SHAPE_STORAGE)) {
    report_error(shape, "CQL0298: cannot read from a cursor without fields", shape->sem->name);
    record_error(shape);
    record_error(ast);
    return;
  }

  // Extract the column specification from the FROM shape clause
  // This tells us which columns from the shape should be used
  EXTRACT_ANY_NOTNULL(column_spec, from_shape->left);
  EXTRACT_ANY(name_list, column_spec->left); // List of column names to extract

  // Count available columns in the shape to ensure sufficient data
  uint32_t provided_count = 0;
  for (ast_node *item = name_list; item; item = item->right) {
    provided_count++;
  }

  // Validate that shape provides enough columns for the request
  if (provided_count < count) {
    report_error(ast, "CQL0299: [shape] has too few fields", shape->sem->name);
    record_error(ast);
    return;
  }

  AST_REWRITE_INFO_SET(shape->lineno, shape->filename);

  // Build a chain of value expressions for the INSERT list
  // Each expression will be shape_name.column_name for the corresponding column
  ast_node *insert_list = NULL;
  ast_node *insert_list_tail = NULL;

  ast_node *item = name_list;

  // Generate member access expressions for each requested column
  for (uint32_t i = 0; i < count; i++, item = item->right) {
    EXTRACT_STRING(item_name, item->left); // Column name from shape

    // Build member access expression: shape_name.column_name
    // Following cql.y dot: expr '.' IDENTIFIER pattern
    ast_node *cname = new_maybe_qstr(shape->sem->name); // Shape object name
    ast_node *col = new_maybe_qstr(item_name); // Column name within shape
    ast_node *dot = new_ast_dot(cname, col); // Member access: shape.column

    // Create insert list entry containing the member access expression
    // Following cql.y insert_list: insert_list ',' expr | expr pattern
    ast_node *new_tail = new_ast_insert_list(dot, NULL);

    // Link the new expression into the growing insert list chain
    if (insert_list) {
      ast_set_right(insert_list_tail, new_tail); // Link to previous item
    }
    else {
      insert_list = new_tail; // First item in list
    }

    insert_list_tail = new_tail; // Track current tail for next iteration
  }

  AST_REWRITE_INFO_RESET();

  // Replace the FROM shape clause with the generated insert list
  // Result: columns_values now contains explicit value expressions instead of shape reference
  ast_set_right(ast, insert_list);

  // Mark AST as temporarily valid - further semantic analysis will validate column types and compatibility
  record_ok(ast);
}

//
// This function transforms LIKE shape_definition syntax into explicit column name lists
// by expanding shape references into their constituent column names. It provides syntactic
// sugar for specifying column lists based on existing table or cursor structures.
//
// Transforms: INSERT INTO table (LIKE other_table) VALUES (...)
// Into: INSERT INTO table (col1, col2, col3, ...) VALUES (...)
//
// Transforms: FETCH cursor (LIKE some_cursor) FROM VALUES (...)
// Into: FETCH cursor (field1, field2, field3, ...) FROM VALUES (...)
//
// This enables automatic column list generation from existing schema definitions,
// reducing duplication and maintaining consistency when table structures change.
// The LIKE syntax can reference tables, views, cursors, or any other "likeable" object.
//
// The function constructs AST nodes using these patterns from cql.y:
// - name_list: name_list ',' name | name
// - name: IDENTIFIER (column names)
// - column_spec: '(' name_list ')'
//
// This enables schema-driven column list generation for various SQL operations.
//
// The form "LIKE x" can appear in most name lists instead of a list of names
// the idea here is that if you want to use the columns of a shape
// for the data you don't want to specify the columns manually, you'd like
// to get them from the type information.  So for instance:
// INSERT INTO T(like C) values(C.x, C.y) is better than
// INSERT INTO T(x,y) values(C.x, C.y), but better still
// INSERT INTO T(like C) from C;
//
// This is sugar, so the code gen system never sees the like form.
// The rewrite is semantically checked as usual so you get normal errors
// if the column types are not compatible.
//
// There are good helpers for creating the name list and for finding
// the likeable object.  So we just use those for all the heavy lifting.
cql_noexport void rewrite_like_column_spec_if_needed(ast_node *columns_values) {
  Contract(is_ast_columns_values(columns_values) || is_ast_from_shape(columns_values));
  EXTRACT_NOTNULL(column_spec, columns_values->left); // Column specification part
  EXTRACT_ANY(shape_def, column_spec->left); // Potential LIKE shape definition

  // Check if this is a LIKE shape definition that needs expansion
  if (is_ast_shape_def(shape_def)) {
     // Resolve the shape reference to find the actual table/cursor/view being referenced
     // LIKEABLE_FOR_VALUES indicates this shape will be used for generating value lists
     ast_node *found_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
     if (!found_shape) {
       record_error(columns_values);
       return;
     }

     AST_REWRITE_INFO_SET(shape_def->lineno, shape_def->filename);

     // Extract the schema structure from the resolved shape
     // This contains all column names, types, and metadata
     sem_struct *sptr = found_shape->sem->sptr;

     // Generate a complete name list containing all columns from the shape
     // Following cql.y name_list: name_list ',' name | name pattern
     // This creates: name1, name2, name3, ... for all columns in the shape
     ast_node *name_list = rewrite_gen_full_column_list(sptr);

     // Replace the LIKE shape_def with the explicit column name list
     // Following cql.y column_spec: '(' name_list ')' pattern
     // Result: (LIKE table) becomes (col1, col2, col3, ...)
     ast_set_left(column_spec, name_list);

     AST_REWRITE_INFO_RESET();
  }

  // Mark the columns_values as processed and ready for further semantic analysis
  record_ok(columns_values);
}

// This function orchestrates the transformation of FROM shape syntax into explicit value
// expressions, coordinating multiple rewriting phases to convert shape-based data access
// into standard SQL VALUE lists. It serves as the main entry point for shape expansion.
//
// Transforms: INSERT INTO table (col1, col2) FROM cursor_name
// Into: INSERT INTO table (col1, col2) VALUES (cursor_name.col1, cursor_name.col2)
//
// Transforms: FETCH target_cursor (LIKE source_cursor) FROM source_cursor
// Into: FETCH target_cursor (field1, field2, ...) VALUES (source_cursor.field1, source_cursor.field2, ...)
//
// The transformation process involves multiple coordinated steps:
// 1. Validate that FROM shape syntax is present and meaningful
// 2. Perform semantic analysis on the shape object to extract schema information
// 3. Expand any LIKE clauses in the FROM shape's column specification
// 4. Generate explicit member access expressions (shape.column) for each target column
//
// This enables automatic data copying between compatible cursors and reduces boilerplate
// code when transferring data from cursors to tables or between cursors with similar schemas.
//
// The function coordinates calls to other rewriting functions that handle specific AST
// transformations, ensuring that all shape references are resolved to explicit column access.
//
// FROM [shape] is a sugar feature, this is the place where we trigger rewriting of the AST
// to replace FROM [shape] with normal values from the shape
//  * Note: By this point column_spec has already  been rewritten so that it is for sure not
//    null if it was absent.  It will be an empty name list.
// All we're doing here is setting up the call to the worker using the appropriate AST args
cql_noexport void rewrite_from_shape_if_needed(ast_node *ast_stmt, ast_node *columns_values)
{
  Contract(ast_stmt); // we can record the error on any statement
  Contract(is_ast_columns_values(columns_values));
  EXTRACT_NOTNULL(column_spec, columns_values->left); // Target column specification

  // Check if this statement uses FROM shape syntax
  // If not, this is a regular VALUES clause that doesn't need shape expansion
  if (!is_ast_from_shape(columns_values->right)) {
    record_ok(ast_stmt);
    return;
  }

  // Count the number of target columns that need to be filled from the shape
  // This determines how many shape fields we need to extract
  uint32_t count = 0;
  for (ast_node *item = column_spec->left; item; item = item->right) {
    count++;
  }

  // Validate that FROM shape is meaningful - empty column list makes it redundant
  if (count == 0) {
    report_error(columns_values->right, "CQL0297: FROM [shape] is redundant if column list is empty", NULL);
    record_error(ast_stmt);
    return;
  }

  // Extract the FROM shape clause and the shape object being referenced
  EXTRACT_NOTNULL(from_shape, columns_values->right); // FROM shape clause
  EXTRACT_ANY_NOTNULL(shape, from_shape->right); // The actual shape object (cursor, etc.)

  // Perform semantic analysis on the shape object to validate it can be used as data source
  // This resolves the shape reference and validates it has the required structure
  sem_any_shape(shape);
  if (is_error(shape)) {
    record_error(ast_stmt);
    return;
  }

  // Phase 1: Handle empty column lists in the FROM shape clause
  // If the FROM shape has no explicit column list, generate a full list from the shape schema
  // This ensures we have explicit column names to work with in later phases
  sem_struct *sptr = shape->sem->sptr;
  rewrite_empty_column_list(from_shape, sptr);

  // Phase 2: Expand any LIKE clauses in the FROM shape's column specification
  // The FROM shape itself might contain LIKE syntax that needs expansion
  // For example: FROM cursor (LIKE other_cursor) becomes FROM cursor (field1, field2, ...)
  rewrite_like_column_spec_if_needed(from_shape);
  if (is_error(from_shape)) {
    record_error(ast_stmt);
    return;
  }

  // Phase 3: Transform the FROM shape into explicit member access expressions
  // This is the core transformation that converts FROM shape to VALUES (shape.col1, shape.col2, ...)
  // The count parameter limits how many columns are extracted to match the target column list
  rewrite_insert_list_from_shape(columns_values, from_shape, count);
  if (is_error(columns_values)) {
    record_error(ast_stmt);
    return;
  }

  // Mark the statement as successfully rewritten
  // Further semantic analysis will validate type compatibility between source and target columns
  record_ok(ast_stmt);
}

// This function transforms FROM shape arguments into explicit member access expressions
// within function argument lists, procedure calls, and other expression contexts. It expands
// shape references into individual field accesses for automatic data passing.
//
// Transforms: CALL proc(FROM cursor_name)
// Into: CALL proc(cursor_name.field1, cursor_name.field2, cursor_name.field3, ...)
//
// Transforms: INSERT INTO table VALUES (FROM shape_obj LIKE target_shape)
// Into: INSERT INTO table VALUES (shape_obj.col1, shape_obj.col2, ...)
//
// This enables automatic argument expansion from cursors and other shaped objects,
// allowing procedures to accept data from cursors without explicitly naming each field.
// The expansion can be filtered through LIKE clauses to select specific subsets of fields.
//
// The function constructs AST nodes using these patterns from cql.y:
// - expr_list: expr_list ',' expr | expr
// - arg_list: arg_list ',' expr | expr
// - insert_list: insert_list ',' expr | expr
// - dot: expr '.' IDENTIFIER (member access for shape.field)
//
// This supports polymorphic argument lists that adapt to cursor schemas automatically.
//
// Here we will rewrite the arguments in a call statement expanding any
// FROM [shape] [LIKE type ] entries we encounter.  We don't validate
// the types here.  That happens after expansion.  It's possible that the
// types don't match at all, but we don't care yet.
static void rewrite_from_shape_args(ast_node *head) {
  Contract(is_ast_expr_list(head) || is_ast_arg_list(head) || is_ast_insert_list(head));

  // Preserve the original list node type (expr_list, arg_list, or insert_list)
  // All three types have identical structure but different semantic contexts
  // We need to maintain the correct type when creating new list nodes
  CSTR node_type = head->type;

  // Process each item in the list, looking for FROM shape expressions to expand
  for (ast_node *item = head ; item ; item = item->right) {
    EXTRACT_ANY_NOTNULL(arg, item->left); // Current argument expression

    // Check if this argument is a FROM shape expression that needs expansion
    if (is_ast_from_shape(arg)) {
      EXTRACT_ANY_NOTNULL(shape, arg->left); // Shape object (cursor, result set, etc.)

      // Perform semantic analysis on the shape to validate it and extract schema information
      // Note: If this shape has no storage (e.g. non-automatic cursor) then we will fail later
      // when we try to resolve the '.' expression. That error message tells the story well enough
      // so we don't need an extra check here.
      sem_any_shape(shape);
      if (is_error(shape)) {
        record_error(head);
        return;
      }

      // Check if there's a LIKE clause that filters which fields to include
      ast_node *shape_def = arg->right; // Optional LIKE shape_definition
      ast_node *likeable_shape = NULL;

      if (shape_def) {
          // Resolve the LIKE reference to find the filtering shape
          likeable_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
          if (!likeable_shape) {
            record_error(head);
            return;
          }
      }

      AST_REWRITE_INFO_SET(shape->lineno, shape->filename);

      // Determine which fields to expand: LIKE clause fields if present, otherwise all shape fields
      // Use the names from the LIKE clause if there is one, otherwise use all the names in the shape
      sem_struct *sptr = likeable_shape ? likeable_shape->sem->sptr : shape->sem->sptr;
      uint32_t count = sptr->count;

      // Generate member access expressions for each field: shape_name.field_name
      for (uint32_t i = 0; i < count; i++) {
        // Build member access expression: shape_name.field_name
        // Following cql.y dot: expr '.' IDENTIFIER pattern
        ast_node *cname = new_maybe_qstr(shape->sem->name); // Shape object name
        ast_node *col = new_str_or_qstr(sptr->names[i], sptr->semtypes[i]); // Field name with type info
        ast_node *dot = new_ast_dot(cname, col); // Member access: shape.field

        if (i == 0) {
          // Replace the FROM shape expression with the first field access
          // This preserves the original list structure while substituting the content
          ast_set_left(item, dot);
        }
        else {
          // Insert additional field accesses after the current position
          // Following the appropriate list pattern (expr_list, arg_list, or insert_list)
          ast_node *right = item->right; // Save remaining list items
          ast_node *new_item = new_ast_expr_list(dot, right); // Create new list node
          new_item->type = node_type; // Set correct node type
          ast_set_right(item, new_item); // Link into list
          item = new_item; // Advance to new position
        }
      }

      AST_REWRITE_INFO_RESET();
    }
  }

  // Mark the list as successfully processed
  // Type checking will occur later during semantic analysis of the expanded expressions
  record_ok(head);
}

// This function processes column definition lists in table creation statements,
// looking for LIKE shape_definition clauses and expanding them into explicit column
// definitions. It enables schema inheritance and reuse by allowing tables to inherit
// column structures from existing tables, views, or procedures.
//
// Transforms: CREATE TABLE new_table (id INT, LIKE existing_table, name TEXT)
// Into: CREATE TABLE new_table (id INT, col1 TYPE1, col2 TYPE2, ..., name TEXT)
//
// This is part of CQL's schema composition system that allows building tables by
// combining column definitions from multiple sources. Each LIKE clause gets expanded
// into the complete set of column definitions from the referenced shape.
//
// The function coordinates the expansion process by delegating to rewrite_one_def()
// for each LIKE clause found, ensuring that all shape references are resolved into
// concrete column definitions before semantic analysis proceeds.
//
// Walk the list of column definitions looking for any of the
// "LIKE table/proc/view". If any are found, replace that parameter with
// the table/prov/view columns
cql_noexport bool_t rewrite_col_key_list(ast_node *head) {
  // Traverse the column definition list, processing each entry
  for (ast_node *ast = head; ast; ast = ast->right) {
    Contract(is_ast_col_key_list(ast));

    // Check if this entry is a LIKE shape_definition that needs expansion
    if (is_ast_shape_def(ast->left)) {
      // Expand the LIKE clause into explicit column definitions
      // This transforms one LIKE entry into multiple column definition entries
      bool_t success = rewrite_one_def(ast);
      if (!success) {
        return false; // Expansion failed (e.g., invalid shape reference)
      }
    }
  }

  return true; // All LIKE clauses successfully expanded
}

// This function performs the core transformation of a single LIKE shape_definition
// into explicit column definitions within table creation statements. It handles the
// detailed AST reconstruction required to replace shape references with concrete columns.
//
// Transforms: LIKE existing_table  [within CREATE TABLE column list]
// Into: col1 TYPE1 [NOT NULL] [SENSITIVE], col2 TYPE2 [NOT NULL] [SENSITIVE], ...
//
// The transformation preserves all column attributes including data types, nullability
// constraints, and sensitivity markers. This ensures that inherited columns maintain
// their original semantic properties in the new table definition.
//
// The function constructs complex AST nodes using these patterns from cql.y:
// - col_def: col_def_type_attrs opt_col_def_val
// - col_def_type_attrs: col_def_name_type opt_col_attrs
// - col_def_name_type: name data_type
// - col_attrs: col_attrs col_attr | col_attr
// - col_attr: NOT NULL | SENSITIVE | DEFAULT value | CHECK expr | COLLATE name
//
// This enables precise schema inheritance with full attribute preservation.
//
// There is a LIKE [table/view/proc] used to create a table so we
// - Look up the parameters to the table/view/proc
// - Create a col_def node for each field of the table/view/proc
// - Reconstruct the ast
cql_noexport bool_t rewrite_one_def(ast_node *head) {
  Contract(is_ast_col_key_list(head));
  EXTRACT_NOTNULL(shape_def, head->left); // LIKE shape_definition to expand

  // Resolve the shape reference to find the source table/view/procedure
  // it's ok to use the LIKE construct on old tables
  ast_node *likeable_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
  if (!likeable_shape) {
    record_error(head);
    return false;
  }

  AST_REWRITE_INFO_SET(shape_def->lineno, shape_def->filename);

  // Store the remaining column definitions that come after this LIKE clause
  // We'll need to reattach them after expanding the LIKE into multiple columns
  EXTRACT_ANY(right_ast, head->right);

  // Extract schema information from the resolved shape
  sem_struct *sptr = likeable_shape->sem->sptr;
  uint32_t count = sptr->count;

  // Generate a column definition for each field in the referenced shape
  for (uint32_t i = 0; i < count; i++) {
    sem_t sem_type = sptr->semtypes[i]; // Column's semantic type with flags
    CSTR col_name = sptr->names[i]; // Column name

    // Build the core column definition: name and data type
    // Following cql.y col_def_name_type: name data_type pattern
    ast_node *data_type = rewrite_gen_data_type(core_type_of(sem_type), NULL);
    ast_node *name_ast = new_str_or_qstr(col_name, sem_type);
    ast_node *name_type = new_ast_col_def_name_type(name_ast, data_type);

    // Build column attributes based on the semantic type flags
    // Following cql.y col_attrs: col_attrs col_attr | col_attr pattern
    ast_node *attrs = NULL;

    // Add NOT NULL constraint if the original column was not nullable
    if (is_not_nullable(sem_type)) {
      attrs = new_ast_col_attrs_not_null(NULL, NULL);
    }

    // Add SENSITIVE attribute if the original column was marked sensitive
    if (sensitive_flag(sem_type)) {
      // Chain with any existing attributes (like NOT NULL)
      attrs = new_ast_sensitive_attr(NULL, attrs);
    }

    // Build complete column definition with attributes
    // Following cql.y col_def_type_attrs: col_def_name_type opt_col_attrs pattern
    ast_node *col_def_type_attrs = new_ast_col_def_type_attrs(name_type, attrs);

    // Following cql.y col_def: col_def_type_attrs opt_col_def_val pattern
    ast_node *col_def = new_ast_col_def(col_def_type_attrs, NULL);

    // Link the new column definition into the column list chain
    if (i) {
      // For subsequent columns, create new list nodes and chain them
      // Following cql.y col_key_list: col_key_list ',' col_key | col_key pattern
      ast_node *new_head = new_ast_col_key_list(col_def, NULL);
      ast_set_right(head, new_head);
      head = new_head;
    }
    else {
      // For the first column, replace the LIKE shape_def with the column definition
      Invariant(is_ast_col_key_list(head));
      Invariant(is_ast_shape_def(head->left));

      // Replace the shape def entry with the first col_def
      // Subsequent iterations will insert additional columns to the right
      ast_set_right(head, NULL);
      ast_set_left(head, col_def);
    }
  }

  AST_REWRITE_INFO_RESET();

  // Reattach any column definitions that came after the LIKE clause
  // This preserves the original column ordering: columns before LIKE, expanded columns, columns after LIKE
  ast_set_right(head, right_ast);
  return true;
}

// This utility function determines the most appropriate name to use when referencing
// a shape type in generated code or error messages. It implements a priority system
// for choosing between different available names based on their specificity and usefulness.
//
// The function handles several naming scenarios:
// 1. Named structures from tables/views: Uses the actual table/view name
// 2. Anonymous SELECT structures: Falls back to object name or generic "_select_"
// 3. Cursor-based shapes: Prefers structure name over cursor name when available
//
// This enables consistent and meaningful naming in code generation and diagnostics,
// helping users understand which shapes are being referenced in complex expressions.
//
// The naming priority is:
// - struct_name (if not generic "_select_") - highest priority
// - obj_name (cursor/variable name) - medium priority
// - "_select_" (anonymous shape indicator) - lowest priority
//
// This supports clear identification of shape types across various CQL contexts.
//
// Give the best name for the shape type given then AST
// there are many casese, the best data is on the struct type unless
// it's anonymous, in which case the item name is the best choice.
CSTR static best_shape_type_name(ast_node *shape) {
  Contract(shape->sem);
  Contract(shape->sem->sptr);

  // Extract both potential names: the structure type name and the object instance name
  CSTR struct_name = shape->sem->sptr->struct_name; // Name from the shape's structure type
  CSTR obj_name = shape->sem->name; // Name of the shape object/cursor

  // Prefer the structure name if it's meaningful and not a generic placeholder
  // "_select_" is the generic name used for structs that are otherwise unnamed.
  // e.g.  "cursor C like select 1 x, 2 y" gets struct_name="_select_" but obj_name="C"
  if (struct_name && strcmp("_select_", struct_name)) {
    // Use the specific structure name (table name, view name, etc.)
    // This provides the most precise type identification
    return struct_name;
  }
  else {
    // Fall back to object name when structure name is generic or missing
    // Use "_select_" only as a last recourse, it means some anonymous shape
    // Priority: object_name > "_select_" (anonymous indicator)
    return obj_name ? obj_name : "_select_";
  }
}

// This function performs the core transformation of a single LIKE shape_definition parameter
// into explicit parameter definitions within procedure parameter lists. It handles the
// detailed AST reconstruction required to replace shape references with concrete parameters.
//
// Transforms: LIKE table_name AS shape_prefix  [within procedure parameter list]
// Into: table_col1 TYPE1 [IN|OUT|INOUT], table_col2 TYPE2 [IN|OUT|INOUT], ...
//
// Transforms: LIKE procedure_name  [within procedure parameter list]
// Into: param1 TYPE1 [IN|OUT|INOUT], param2 TYPE2 [IN|OUT|INOUT], ...
//
// The transformation creates a complete parameter expansion that preserves all parameter
// attributes including data types, parameter direction (IN/OUT/INOUT), and naming conventions.
// This enables automatic parameter list generation from existing schema definitions.
//
// The function handles several complex naming scenarios:
// - Named shape expansion with prefixes (shape_name_column for disambiguation)
// - Qualified identifier handling (X_prefix_column for special QID parameters)
// - Conflict avoidance with automatic _ suffixes for non-procedure parameters
// - Duplicate elimination when multiple LIKE clauses reference overlapping schemas
//
// The function constructs complex AST nodes using these patterns from cql.y:
// - params: params ',' param | param
// - param: [IN | OUT | INOUT] param_detail
// - param_detail: name data_type_any
// - data_type_any: data_type | name (for custom types)
//
// This supports flexible procedure interfaces that adapt to schema changes automatically.
//
// Here we have found a "like T" name that needs to be rewritten with
// the various columns of T.  We do this by:
// * looking up "T" (this is the only thing that can go wrong)
// * replace the "like T" slug with a param node for the first column of T
// * for each additional column create a param node and link it in.
// * emit any given name only once, (so you can do like T1, like T1 even if both have the same pk)
// * arg names get a _ suffix so they don't conflict with column names
static ast_node *rewrite_one_param(ast_node *param, symtab *param_names, bytebuf *args_info) {
  Contract(is_ast_param(param));
  EXTRACT_NOTNULL(param_detail, param->right);
  EXTRACT_ANY(shape_name_ast, param_detail->left);
  EXTRACT_NOTNULL(shape_def, param_detail->right);

  ast_node *likeable_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_ARGS);
  if (!likeable_shape) {
    record_error(param);
    return param;
  }

  AST_REWRITE_INFO_SET(shape_def->lineno, shape_def->filename);

  // Nothing can go wrong from here on - shape reference has been validated
  record_ok(param);

  // Extract schema information from the resolved shape
  // This contains all field definitions with their types, names, and attributes
  sem_struct *sptr = likeable_shape->sem->sptr;
  uint32_t count = sptr->count; // Number of fields to expand
  bool_t first_rewrite = true; // Track first parameter replacement
  CSTR shape_name = ""; // Optional prefix for parameter names
  CSTR shape_type = best_shape_type_name(likeable_shape); // Type name for metadata

  // Handle optional shape name prefix for parameter disambiguation
  // Form: LIKE table_name AS shape_prefix creates parameters like shape_prefix_column
  if (shape_name_ast) {
    EXTRACT_STRING(sname, shape_name_ast);
    shape_name = sname;

    // Create a shape AST node for the argument bundle system
    // This enables passing the entire shape as a single structured argument
    ast_node *shape_ast = new_maybe_qstr(shape_name);
    shape_ast->sem = likeable_shape->sem;
    sem_add_flags(shape_ast, SEM_TYPE_HAS_SHAPE_STORAGE); // Mark as having storage for data access
    shape_ast->sem->name = shape_name;
    add_arg_bundle(shape_ast, shape_name); // Register for bundle argument handling
  }

  // Generate individual parameter definitions for each field in the shape
  // Each field becomes a separate parameter with appropriate type and direction attributes
  for (uint32_t i = 0; i < count; i++) {
    sem_t param_type = sptr->semtypes[i]; // Semantic type with flags (nullable, sensitive, etc.)
    CSTR param_name = sptr->names[i]; // Original field name from shape
    CSTR param_kind = sptr->kinds[i]; // Custom type name if applicable
    CSTR original_name = param_name; // Preserve original for metadata

    // Apply naming rules based on whether shape prefix was specified
    if (shape_name[0]) {
      // Named shape form: create compound parameter names for disambiguation
      // This prevents conflicts when multiple shapes have similarly named fields

      if ((param_type & SEM_TYPE_QID) && param_name[0] == 'X' && param_name[1] == '_') {
        // Special handling for qualified identifiers with X_ prefix
        // QID parameters need the X_ moved to the front: X_shape_column instead of shape_X_column
        param_name = dup_printf("X_%s_%s", shape_name, param_name + 2);
      }
      else {
        // Standard compound naming: shape_name_field_name
        // Creates predictable parameter names based on the shape prefix
        param_name = dup_printf("%s_%s", shape_name, param_name);
      }

      // note we skip none of these, if the names conflict that is an error:

      // For named shapes, all parameters are included - conflicts are reported as errors
      // This ensures that LIKE shape AS name always produces the complete parameter set
      // e.g. if you have conflicting names like x_y (manual) and x (shape) with field y, error
      symtab_add(param_names, param_name, NULL);
    }
    else {
      // If the shape came from a procedure we keep the args unchanged
      // If the shape came from a data type or cursor then we add _
      // The idea here is that if it came from a procedure we want to keep the same signature
      // exactly and if any _ needed to be added to avoid conflict with a column name then it already was.

      // Unnamed shape form: apply naming conventions based on parameter origin

      // Procedure parameters maintain their original names to preserve exact signatures
      // Non-procedure parameters get _ suffix to avoid column name conflicts
      // This distinction ensures procedures can be called with exact parameter matching
      if (!(param_type & (SEM_TYPE_IN_PARAMETER | SEM_TYPE_OUT_PARAMETER))) {
        param_name = dup_printf("%s_", param_name); // Add trailing _ for table/cursor fields
      }

      // Skip duplicate parameter names - allows multiple LIKE clauses with overlapping schemas
      // This enables flexible parameter composition without errors for common fields
      if (!symtab_add(param_names, param_name, NULL)) {
        continue; // Skip already processed parameters
      }
    }

    // Record parameter metadata for code generation and tooling support
    // This enables external tools to understand the parameter expansion mapping
    if (args_info) {
      // args info uses the cleanest version of the name, no trailing _

      // Store metadata using clean names without disambiguation suffixes
      // Format: original_name, shape_prefix, shape_type for each expanded parameter
      bytebuf_append_var(args_info, original_name); // Clean field name from shape
      bytebuf_append_var(args_info, shape_name); // Shape prefix (empty if unnamed)
      bytebuf_append_var(args_info, shape_type); // Shape type name for diagnostics
    }

    // Build the complete parameter definition with proper type information
    // Following cql.y param_detail: name data_type_any pattern
    ast_node *type = rewrite_gen_data_type(param_type, param_kind); // Generate AST for data type
    ast_node *name_ast = new_str_or_qstr(param_name, param_type); // Parameter name with semantic info
    ast_node *param_detail_new = new_ast_param_detail(name_ast, type); // Complete parameter definition

    // Determine parameter direction based on semantic type flags
    // Following cql.y param: [IN | OUT | INOUT] param_detail pattern
    ast_node *inout = NULL; // Default to IN parameter
    if (param_type & SEM_TYPE_OUT_PARAMETER) {
      if (param_type & SEM_TYPE_IN_PARAMETER) {
        inout = new_ast_inout(); // Bidirectional parameter
      }
      else {
        inout = new_ast_out(); // Output-only parameter
      }
    }
    // IN parameters need no explicit marker (NULL inout = IN by default)

    // Link the parameter definition into the parameter list chain
    // Different handling for first parameter (replaces LIKE node) vs. subsequent parameters (inserted)
    if (!first_rewrite) {
      // For second and subsequent parameters, create new parameter nodes and insert them
      // Following cql.y params: params ',' param pattern
      ast_node *params = param->parent; // Get the params list container
      ast_node *new_param = new_ast_param(inout, param_detail_new); // Create complete parameter node

      // Insert the new parameter into the parameter list chain
      // This extends the list: existing_params -> new_parameter -> remaining_params
      ast_set_right(params, new_ast_params(new_param, params->right));
      param = new_param; // Update position for next iteration
    }
    else {
      // For the first parameter, replace the LIKE shape_def node directly
      // This transforms the existing parameter node from LIKE syntax to concrete parameter
      Invariant(is_ast_param(param));

      // Replace the LIKE shape_def with the actual parameter definition
      // Following cql.y param: [IN | OUT | INOUT] param_detail pattern
      ast_set_right(param, param_detail_new); // Set the parameter details
      ast_set_left(param, inout); // Set the parameter direction
      first_rewrite = false; // Mark first replacement complete
    }

    // Mark the parameter as successfully processed
    record_ok(param);
  }

  // Handle the edge case where no parameters were actually added due to complete duplication
  // This can occur when multiple LIKE clauses reference the same fields that were already present
  if (first_rewrite) {
    // All parameters were duplicates, so we need to remove the LIKE node entirely
    // This can only happen if there's at least one previous parameter (otherwise we'd have expanded something)
    EXTRACT_NOTNULL(params, param->parent); // Get the params list containing this LIKE node
    EXTRACT_NAMED_NOTNULL(tail, params, params->parent); // Get the previous params node in the chain

    // Remove the LIKE parameter node by bypassing it in the parameter list chain
    // This connects: previous_params -> remaining_params (skipping the LIKE node)
    ast_set_right(tail, params->right);
  }

  AST_REWRITE_INFO_RESET();

  // this is the last param that we modified
  return param;
}

// This utility function generates complete AST data type nodes from semantic type information,
// providing the essential bridge between CQL's internal type system and the concrete AST
// representation used for code generation and SQL output.
//
// Transforms semantic types into AST nodes using these patterns from cql.y:
// - data_type: INT | TEXT | REAL | LONG | BOOL | BLOB | OBJECT
// - data_type_any: data_type | name (for custom/kind types)
// - notnull_attr: data_type NOT NULL
// - sensitive_attr: SENSITIVE data_type | data_type SENSITIVE
//
// The function handles all CQL core types and their combinations:
// - Basic types: INTEGER, TEXT, REAL, LONG_INTEGER, BOOL, BLOB, OBJECT
// - Nullability: Wraps with NOT NULL constraint when SEM_TYPE_NOT_NULL flag is set
// - Sensitivity: Wraps with SENSITIVE attribute when SEM_TYPE_SENSITIVE flag is set
// - Custom types: Uses kind parameter for user-defined type names and enums
//
// This enables automatic AST construction during rewriting operations where semantic
// analysis has determined types but concrete AST nodes are needed for further processing.
//
// The generated AST nodes are fully compatible with semantic analysis and code generation,
// ensuring consistent type representation throughout the compilation pipeline.
//
// Examples of generated structures:
// - INTEGER -> type_int(NULL)
// - INTEGER NOT NULL -> notnull(type_int(NULL))
// - SENSITIVE TEXT -> sensitive_attr(type_text(NULL), NULL)
// - my_enum_type -> type_int(str("my_enum_type"))
//
// generates an AST node for a data_type_any based on the semantic type
// we need this any time we need to make a tree for a semantic type out
// of thin air.
cql_noexport ast_node *rewrite_gen_data_type(sem_t sem_type, CSTR kind) {
  ast_node *ast = NULL;

  // Handle custom type kinds (enums, named types) by creating a string node
  // Following cql.y data_type_any: data_type | name pattern
  // The kind parameter contains the custom type name for user-defined types
  ast_node *kind_ast = kind ? new_ast_str(kind) : NULL;

  // Generate the core data type AST node based on the semantic type
  // Following cql.y data_type patterns for each fundamental type
  // Each core type maps to its corresponding AST constructor with optional kind annotation
  switch (core_type_of(sem_type)) {
    case SEM_TYPE_INTEGER:      ast = new_ast_type_int(kind_ast); break; // INT [kind]
    case SEM_TYPE_TEXT:         ast = new_ast_type_text(kind_ast); break; // TEXT [kind]
    case SEM_TYPE_LONG_INTEGER: ast = new_ast_type_long(kind_ast); break; // LONG [kind]
    case SEM_TYPE_REAL:         ast = new_ast_type_real(kind_ast); break; // REAL [kind]
    case SEM_TYPE_BOOL:         ast = new_ast_type_bool(kind_ast); break; // BOOL [kind]
    case SEM_TYPE_BLOB:         ast = new_ast_type_blob(kind_ast); break; // BLOB [kind]
    case SEM_TYPE_OBJECT:       ast = new_ast_type_object(kind_ast); break; // OBJECT [kind]
  }

  // All semantic types must map to a valid AST node
  Invariant(ast);

  // Apply nullability constraint if the semantic type indicates NOT NULL
  // Following cql.y notnull_attr: data_type NOT NULL pattern
  // This wraps the base type in a NOT NULL constraint node
  if (is_not_nullable(sem_type)) {
    ast = new_ast_notnull(ast); // data_type -> NOT NULL(data_type)
  }

  // Apply sensitivity attribute if the semantic type indicates SENSITIVE data
  // Following cql.y sensitive_attr: SENSITIVE data_type | data_type SENSITIVE pattern
  // This wraps the type (possibly already wrapped with NOT NULL) in a SENSITIVE attribute
  if (sensitive_flag(sem_type)) {
    ast = new_ast_sensitive_attr(ast, NULL); // data_type -> SENSITIVE(data_type)
  }

  return ast;
}

// This utility function generates a complete column name list from a semantic structure,
// creating explicit AST name nodes for all visible columns in a table, view, cursor, or
// procedure result set. It provides the foundation for automatic column list expansion.
//
// Transforms: sem_struct containing (col1, col2, col3, ...)
// Into: name_list AST containing (name(col1), name(col2), name(col3), ...)
//
// The function filters out hidden columns (marked with SEM_TYPE_HIDDEN_COL) that should
// not appear in user-visible column lists, such as internal implementation columns or
// system-generated metadata fields.
//
// This is used extensively throughout the rewriting system whenever explicit column
// names are needed but only schema information is available. Common use cases include:
// - Expanding LIKE clauses into concrete column names
// - Converting FROM shape syntax into column references
// - Generating default column lists when none are specified
// - Supporting wildcard operations like SELECT * transformations
//
// The function constructs AST nodes using this pattern from cql.y:
// - name_list: name_list ',' name | name
// - name: IDENTIFIER (column names with semantic type information)
//
// This enables automatic schema-driven code generation that adapts to table changes.
//
// If no name list then fake a name list so that both paths are the same
// no name list is the same as all the names
cql_noexport ast_node *rewrite_gen_full_column_list(sem_struct *sptr) {
  Contract(sptr);
  ast_node *name_list = NULL; // Head of the name list chain
  ast_node *name_list_tail = NULL; // Tail pointer for efficient appending

  // Iterate through all columns in the semantic structure
  // Generate name nodes for each visible column in the schema
  for (uint32_t i = 0; i < sptr->count; i++) {
    // Skip hidden columns that should not appear in user-visible lists
    // Hidden columns include internal implementation details and system metadata
    if (sptr->semtypes[i] & SEM_TYPE_HIDDEN_COL) {
      continue; // Skip to next column
    }

    // Create a name AST node with semantic type information
    // new_str_or_qstr handles proper quoting based on the column name and type
    ast_node *ast_col = new_str_or_qstr(sptr->names[i], sptr->semtypes[i]);

    // Build the name list chain using cql.y name_list: name_list ',' name | name pattern
    // Each column becomes a separate name_list node in the chain
    ast_node *new_tail = new_ast_name_list(ast_col, NULL);

    // Link the new name into the growing name list chain
    if (name_list) {
      // Append to existing list: previous_tail -> new_tail
      ast_set_right(name_list_tail, new_tail);
    }
    else {
      // First column: initialize the list head
      name_list = new_tail;
    }

    // Update tail pointer for next iteration's efficient appending
    name_list_tail = new_tail;
  }

  return  name_list;
}

// This function transforms the USING syntax for cursor fetching into standard columns_values
// format by separating the expression list from the alias names. It converts the compact
// USING form into explicit column specifications and value lists.
//
// Transforms: FETCH cursor USING expr1 alias1, expr2 alias2, expr3 alias3
// Into: FETCH cursor (alias1, alias2, alias3) VALUES (expr1, expr2, expr3)
//
// The USING syntax provides a convenient way to specify both the source expressions and
// the target column names in a single compact form. This rewrite separates them into
// the standard columns_values structure expected by the rest of the compilation system.
//
// The transformation involves complex AST reconstruction that reverses the order of
// processing - the USING form is parsed left-to-right but needs to be split into
// two separate lists that are processed in reverse order for proper list construction.
//
// The function constructs AST nodes using these patterns from cql.y:
// - columns_values: column_spec insert_list | column_spec select_stmt
// - column_spec: '(' name_list ')'
// - name_list: name_list ',' name | name
// - insert_list: insert_list ',' expr | expr
//
// This enables the USING syntax to be processed by standard semantic analysis.
//
// This helper function rewrites the expr_names ast to the columns_values ast.
// e.g: fetch C using 1 a, 2 b, 3 c; ==> fetch C (a,b,c) values (1, 2, 3);
cql_noexport void rewrite_expr_names_to_columns_values(ast_node *columns_values) {
  Contract(is_ast_expr_names(columns_values));

  AST_REWRITE_INFO_SET(columns_values->lineno, columns_values->filename);

  // Extract the expr_names structure that contains the USING expression/alias pairs
  EXTRACT(expr_names, columns_values);
  ast_node *name_list = NULL; // Will hold column names (aliases)
  ast_node *insert_list = NULL; // Will hold value expressions

  // Navigate to the end of the expr_names chain for reverse processing
  // The USING syntax is parsed left-to-right but we need to build lists in reverse
  // to maintain proper ordering in the final columns_values structure
  for ( ; expr_names->right ; expr_names = expr_names->right) ;

  // Process each expr_name pair in reverse order to build the separated lists
  // This reversal is necessary because we're building lists by prepending
  do {
    EXTRACT(expr_name, expr_names->left); // Current expression/alias pair
    EXTRACT_ANY(expr, expr_name->left); // The value expression
    EXTRACT_ANY(as_alias, expr_name->right); // The alias specification
    EXTRACT_ANY_NOTNULL(name, as_alias->left); // The column name (alias)

    // Build the column name list by prepending each alias
    // Following cql.y name_list: name_list ',' name | name pattern
    // Result: (alias3, alias2, alias1) for "expr1 alias1, expr2 alias2, expr3 alias3"
    name_list = new_ast_name_list(name, name_list);

    // Build the value expression list by prepending each expression
    // Following cql.y insert_list: insert_list ',' expr | expr pattern
    // Result: (expr3, expr2, expr1) for "expr1 alias1, expr2 alias2, expr3 alias3"
    insert_list = new_ast_insert_list(expr, insert_list);

    // Move to the previous expr_name in the chain
    expr_names = expr_names->parent;
  } while (is_ast_expr_names(expr_names));

  // Construct the final columns_values structure from the separated lists
  // Following cql.y columns_values: column_spec insert_list pattern

  // Create the column specification containing the alias names
  // Following cql.y column_spec: '(' name_list ')' pattern
  ast_node *opt_column_spec = new_ast_column_spec(name_list);

  // Create the complete columns_values node
  // This combines the column names with their corresponding value expressions
  ast_node *new_columns_values = new_ast_columns_values(opt_column_spec, insert_list);

  // Transform the original expr_names node into a columns_values node
  // This preserves the original AST position while changing its structure and semantics
  columns_values->type = new_columns_values->type;
  ast_set_left(columns_values, new_columns_values->left);
  ast_set_right(columns_values, new_columns_values->right);

  AST_REWRITE_INFO_RESET();
}

// This function transforms INSERT/FETCH statements that use SELECT subqueries directly
// into the standard columns_values format by extracting column names from the SELECT's
// result structure and creating explicit column specifications.
//
// Transforms: INSERT INTO table USING SELECT expr1 AS col1, expr2 AS col2, expr3 AS col3
// Into: INSERT INTO table (col1, col2, col3) SELECT expr1 AS col1, expr2 AS col2, expr3 AS col3
//
// Transforms: FETCH cursor USING SELECT field1, field2, field3 FROM other_table
// Into: FETCH cursor (field1, field2, field3) SELECT field1, field2, field3 FROM other_table
//
// The USING SELECT syntax allows direct use of SELECT statements as data sources without
// explicitly specifying the target column names. This rewrite extracts the column names
// from the SELECT's semantic analysis results and creates an explicit column specification.
//
// This transformation is essential because the rest of the compilation system expects
// the standard columns_values format with explicit column lists, but users want the
// convenience of automatic column name inference from SELECT statements.
//
// The function constructs AST nodes using these patterns from cql.y:
// - columns_values: column_spec select_stmt
// - column_spec: '(' name_list ')'
// - name_list: name_list ',' name | name
// - select_stmt: SELECT select_core opt_orderby opt_limit
//
// This enables seamless integration of SELECT-based data sources with standard processing.
//
// This helper function rewrites the select statement ast to the columns_values ast.
// e.g: insert into X using select 1 a, 2 b, 3 c; ==> insert into X (a,b,c) values (1, 2, 3);
cql_noexport void rewrite_select_stmt_to_columns_values(ast_node *columns_values) {
  // Extract the SELECT statement that's currently masquerading as columns_values
  EXTRACT_ANY_NOTNULL(select_stmt, columns_values);
  Contract(is_select_variant(select_stmt));

  AST_REWRITE_INFO_SET(columns_values->lineno, columns_values->filename);

  ast_node *name_list = NULL; // Will hold the extracted column names

  // Validate that the SELECT statement has been semantically analyzed
  // We need the semantic structure to extract column names and types
  Invariant(select_stmt->sem);
  Invariant(select_stmt->sem->sptr);

  // Extract the result structure from the SELECT statement's semantic analysis
  // This contains all column names, types, and metadata from the SELECT list
  sem_struct *sptr = select_stmt->sem->sptr;

  // Build the column name list in reverse order for efficient list construction
  // Starting from the last column and prepending creates the list in correct order
  int32_t i = (int32_t)sptr->count;

  while (--i >= 0) {
    CSTR name = sptr->names[i]; // Column name from SELECT list

    // Create a name AST node with full semantic type information
    // This preserves nullability, sensitivity, and other type flags
    ast_node *name_ast = new_str_or_qstr(name, sptr->semtypes[i]);

    // Build the name list by prepending each column name
    // Following cql.y name_list: name_list ',' name | name pattern
    // Reverse iteration with prepending creates correct final order
    name_list = new_ast_name_list(name_ast, name_list);
  }

  // Create a new SELECT statement node to avoid mutating the original
  // We need to preserve the original SELECT while changing the containing structure
  ast_node *new_select_stmt = new_ast_select_stmt(select_stmt->left, select_stmt->right);
  new_select_stmt->type = select_stmt->type; // Preserve specific SELECT variant type

  // Construct the final columns_values structure
  // Following cql.y columns_values: column_spec select_stmt pattern

  // Create the column specification from the extracted names
  // Following cql.y column_spec: '(' name_list ')' pattern
  ast_node *opt_column_spec = new_ast_column_spec(name_list);

  // Create the complete columns_values node combining column spec with SELECT
  // This creates: (col1, col2, col3) SELECT expr1 AS col1, expr2 AS col2, expr3 AS col3
  ast_node *new_columns_values = new_ast_columns_values(opt_column_spec, new_select_stmt);

  // Transform the original SELECT node into a columns_values node
  // This preserves the AST position while completely changing the node's structure
  // The original SELECT is now nested within the new columns_values structure
  columns_values->type = new_columns_values->type;
  ast_set_left(columns_values, new_columns_values->left);
  ast_set_right(columns_values, new_columns_values->right);

  AST_REWRITE_INFO_RESET();
}

//
// This utility function handles the automatic generation of complete column lists when
// none are explicitly specified in cursor operations. It provides default behavior for
// operations that can work with either explicit or implicit column specifications.
//
// Transforms: FETCH cursor FROM VALUES(...) [no column list specified]
// Into: FETCH cursor (col1, col2, col3, ...) FROM VALUES(...)
//
// Transforms: INSERT INTO table FROM shape [no column list specified]
// Into: INSERT INTO table (col1, col2, col3, ...) FROM shape
//
// The function implements the principle that "no column list means all columns" for
// operations that support both explicit and implicit column specifications. This
// enables convenient shorthand syntax while ensuring the rest of the compilation
// system always has explicit column lists to work with.
//
// This is essential for operations involving:
// - Automatic cursor fetching with all available columns
// - Bulk data operations where column lists would be redundant
// - Integration with dummy data generation systems
// - Argument-based data sources where column mapping is implicit
//
// The function constructs AST nodes using this pattern from cql.y:
// - column_spec: '(' name_list ')'
// - name_list: name_list ',' name | name (generated from schema)
//
// This enables consistent column list handling across various CQL operations.
//
// There are two reasons the columns might be missing. A form like this:
//    INSERT C FROM VALUES(...);
// or
//    INSERT C() FROM VALUES() @dummy_seed(...)
//
// The first form is shorthand for specifying that all of the columns are present.
// It will be expanded into something like FETCH C(x,y,z) FROM VALUES(....)
//
// The second form indicates that there are NO values specified at all.  This might
// be ok if all the columns have some default value.  Or if dummy data is used.
// When dummy data is present, any necessary but missing columns are provided
// using the seed variable.  The same rules apply to the FETCH statement.
//
// So these kinds of cases:
//   FETCH C FROM VALUES(...) // all values are specified
//   FETCH C() FROM VALUES() @dummy_seed(...) -- NO values are specified, all dummy
//
// If you add FROM ARGUMENTS to this situation, the arguments take the place of the
// values. Each specified column will cause an argument to be used as a value, in
// the declared order.  The usual type checking will be done.
//
// So we have these kinds of cases:
//  FETCH C FROM ARGUMENTS  -- args are covering everything (dummy data not applicable as usual)
//  FETCH C() FROM ARGUMENTS @dummy_seed(...)  -- error, args can't possibly be used, no columns specified
//  FETCH C() FROM VALUES() @dummy_seed(...)  -- all values are dummy
//  FETCH C(x,y) FROM VALUES(1,2) @dummy_seed(...)  -- x, y from values, the rest are dummy
//  FETCH C(x,y) FROM ARGUMENTS @dummy_seed(...) -- x,y from args, the rest are dummy
//
// This is harder to explain than it is to code.
cql_noexport void rewrite_empty_column_list(ast_node *columns_values, sem_struct *sptr)
{
  Invariant(is_ast_columns_values(columns_values) || is_ast_from_shape(columns_values));
  EXTRACT(column_spec, columns_values->left); // Extract existing column specification

  AST_REWRITE_INFO_SET(columns_values->lineno, columns_values->filename);

  // Check if no explicit column list was provided
  // This is the case for shorthand syntax like FETCH cursor FROM VALUES(...)
  if (!column_spec) {
    // Generate a complete column list from the schema structure
    // This creates explicit column names for all visible columns in the target
    ast_node *name_list = rewrite_gen_full_column_list(sptr);

    // Create a column specification node to hold the generated name list
    // Following cql.y column_spec: '(' name_list ')' pattern
    // This transforms implicit "all columns" into explicit (col1, col2, col3, ...)
    column_spec = new_ast_column_spec(name_list);

    // Install the generated column specification into the columns_values structure
    // This ensures the rest of the system always sees explicit column lists
    ast_set_left(columns_values, column_spec);
  }

  AST_REWRITE_INFO_RESET();
}

// This wrapper function provides safe handling of FROM shape expansion in argument lists
// by checking for null arguments and managing error propagation. It serves as a defensive
// interface to the core shape argument expansion functionality.
//
// Transforms: function_call(FROM cursor_name, other_args) [if arg_list exists]
// Into: function_call(cursor_name.field1, cursor_name.field2, ..., other_args)
//
// Transforms: function_call() [if arg_list is null]
// Into: function_call() [no change, returns success]
//
// The function handles the edge case where argument lists might be null (for functions
// with no arguments) while still providing shape expansion capabilities when needed.
// This is essential because the error handling model expects boolean returns rather
// than error nodes when dealing with potentially null AST structures.
//
// This defensive pattern is necessary because:
// - Some functions have no arguments (arg_list is null)
// - Shape expansion errors need to be propagated as boolean failures
// - The caller needs to know whether to proceed with further processing
// - Error state in AST nodes isn't sufficient for null pointer cases
//
// The function coordinates with rewrite_from_shape_args() to handle the actual
// expansion while providing safe null pointer handling and consistent error reporting.
//
// We can't just return the error in the tree like we usually do because
// arg_list might be null and we're trying to do all the helper logic here.
cql_noexport bool_t rewrite_shape_forms_in_list_if_needed(ast_node *arg_list) {
  // Only process non-null argument lists - null means no arguments to expand
  if (arg_list) {
    // Delegate to the core shape argument expansion function
    // This handles FROM cursor_name syntax within argument lists
    // and expands them into individual field access expressions
    rewrite_from_shape_args(arg_list);

    // Check if the expansion process encountered any errors
    // Shape expansion can fail due to invalid cursor references, type mismatches, etc.
    if (is_error(arg_list)) {
      return false; // Signal failure to caller
    }
  }

  // Success: either no arguments to process or all expansions completed successfully
  return true;
}

// This function transforms the IIF (Immediate IF) function call into an equivalent
// CASE expression, providing a convenient ternary operator-like functionality in CQL.
// The transformation converts function call syntax into standard SQL CASE syntax.
//
// Transforms: IIF(condition_expr, true_value, false_value)
// Into: CASE WHEN condition_expr THEN true_value ELSE false_value END
//
// The IIF function provides a more compact and familiar syntax for simple conditional
// expressions, similar to ternary operators in other languages (condition ? true : false).
// This rewrite converts the function call into standard SQL CASE syntax that can be
// processed by the rest of the compilation system and generated into efficient SQL.
//
// The transformation is purely syntactic - no semantic validation is performed at this
// stage because the resulting CASE expression may still have semantic errors that will
// be caught during normal semantic analysis. This allows the rewrite to focus purely
// on AST structure transformation.
//
// The function constructs AST nodes using these patterns from cql.y:
// - case_expr: CASE opt_expr case_list opt_else END
// - case_list: case_list when_clause | when_clause
// - when_clause: WHEN expr THEN expr
// - opt_else: ELSE expr | [empty]
//
// This enables natural conditional expression syntax within CQL expressions.
//
// This helper function rewrites an iif ast to a case_expr ast, e.g.:
//
//   iif(X, Y, Z) => CASE WHEN X THEN Y ELSE Z END;
//
// The caller is responsible for validating that we have the three arguments
// required. In fact, we don't do any form of semantic analysis here at all:
// Unlike in other rewrite functions that call `sem_expr` to validate the
// rewrite, it's very much the case that the rewritten expression may not be
// semantically valid due to an error in the input program, so we simply let the
// caller deal with it.
cql_noexport void rewrite_iif(ast_node *ast) {
  Contract(is_ast_call(ast)); // Ensure we're transforming a function call
  EXTRACT_NAME_AST(name_ast, ast->left); // Extract function name AST node
  EXTRACT_STRING(name, name_ast); // Get function name string (should be "iif")
  EXTRACT_NOTNULL(call_arg_list, ast->right); // Extract the call argument list structure
  EXTRACT(arg_list, call_arg_list->right); // Extract the actual arguments

  // Extract the three IIF arguments: condition, true_value, false_value
  // The caller is responsible for ensuring exactly three arguments are present
  ast_node *arg1 = first_arg(arg_list); // Condition expression
  ast_node *arg2 = second_arg(arg_list); // Value when condition is true
  ast_node *arg3 = third_arg(arg_list); // Value when condition is false

  AST_REWRITE_INFO_SET(name_ast->lineno, name_ast->filename);

  // Generate the equivalent CASE expression structure
  // This creates: CASE WHEN arg1 THEN arg2 ELSE arg3 END
  // The helper function handles all the detailed AST construction
  ast_node *case_expr = rewrite_gen_iif_case_expr(arg1, arg2, arg3);

  AST_REWRITE_INFO_RESET();

  // Transform the original function call node into a CASE expression node
  // This preserves the original AST position while completely changing the node type and structure
  // The function call becomes: CASE WHEN condition THEN true_value ELSE false_value END
  ast->type = case_expr->type; // Change from k_ast_call to k_ast_case_expr
  ast_set_left(ast, case_expr->left); // Set the CASE expression components
  ast_set_right(ast, case_expr->right); // Set the WHEN/ELSE clause structure
}

// This function implements automatic column name inference for Common Table Expressions (CTEs)
// that use the wildcard (*) syntax. It extracts column names from the CTE's SELECT statement
// and generates an explicit column list, eliminating redundant column name specifications.
//
// Transforms: WITH cte_name(*) AS (SELECT expr1 AS col1, expr2 AS col2, expr3 AS col3)
// Into: WITH cte_name(col1, col2, col3) AS (SELECT expr1 AS col1, expr2 AS col2, expr3 AS col3)
//
// The CTE(*) syntax provides a convenient way to automatically infer CTE column names from
// the SELECT statement's column list, avoiding the need to duplicate column names in both
// the CTE declaration and the SELECT statement. This is especially valuable for CTEs with
// many columns where manual duplication is error-prone and maintenance-intensive.
//
// The transformation ensures that:
// - All columns in the SELECT have explicit names (no anonymous columns)
// - Column names are extracted in the correct order
// - The resulting CTE has a standard explicit column list
// - UNION operations within the CTE will enforce consistent column naming
//
// This functionality is essential for complex queries with large result sets where
// maintaining synchronized column lists between CTE declarations and SELECT statements
// would be impractical and error-prone.
//
// The function constructs AST nodes using this pattern from cql.y:
// - cte_decl: name opt_cte_proc_name_list
// - opt_cte_proc_name_list: '(' name_list ')' | [empty]
// - name_list: name_list ',' name | name
//
// This enables automatic CTE column management that adapts to SELECT statement changes.
//
// The form we're trying to rewrite here is
// with cte(*) as (select 1 a, 2 b) select * from cte;
// The idea is that if you named all the columns in the projection of the select
// in this case "a, b" you don't want to rename all again in the cte definiton.
// That is with cte(a,b) as (select 1 a, 2 b) is redundant.
// There are many cases with dozens of names and it becomes a real problem to make sure
// the names all match and are in the right order.  This avoids all that.  Even if you
// select the columns you need in the wrong order it won't matter because you get them
// by name from the CTE anyway.  If you're using a union, the additional enforcement
// that the names match on each branch locks you in to correct columns.
// All we have to do is:
//   * make sure all the columns have a name and a reasonable type
//   * make a name list for the column names
//   * swap it in
cql_noexport void rewrite_cte_name_list_from_columns(
  ast_node *ast,
  ast_node *select_core)
{
  Contract(is_ast_cte_decl(ast)); // Ensure we're processing a CTE declaration
  EXTRACT_NOTNULL(star, ast->right) // Extract the "*" placeholder for column list

  // Validate that the SELECT statement has proper column names and types
  // This ensures all columns are explicitly named (no anonymous expressions)
  // and that all columns have valid types for CTE usage
  sem_verify_no_anon_no_null_columns(select_core);
  if (is_error(select_core)) {
    record_error(ast);
    return;
  }

  AST_REWRITE_INFO_SET(star->lineno, star->filename);

  // Extract the column schema information from the SELECT statement's semantic analysis
  // This contains all column names, types, and metadata from the SELECT's result set
  sem_struct *sptr = select_core->sem->sptr;

  // Generate an explicit column name list from the SELECT statement's columns
  // This creates: (col1, col2, col3, ...) from the SELECT's column definitions
  // Following cql.y name_list: name_list ',' name | name pattern
  ast_node *name_list = rewrite_gen_full_column_list(sptr);

  // Replace the "*" placeholder with the explicit column name list
  // This transforms: cte_name(*) into: cte_name(col1, col2, col3, ...)
  // The right side of the CTE declaration now contains concrete column names
  ast_set_right(ast, name_list);

  AST_REWRITE_INFO_RESET();

  // Mark the CTE declaration as successfully processed
  // The CTE now has explicit column names that match its SELECT statement
  record_ok(ast);
}

// This function performs the core transformation of a single LIKE shape_definition
// into explicit typed name definitions within procedure return type declarations. It handles
// the detailed AST reconstruction required to replace shape references with concrete typed names.
//
// Transforms: LIKE table_name AS shape_prefix  [within procedure return type list]
// Into: shape_prefix_col1 TYPE1, shape_prefix_col2 TYPE2, shape_prefix_col3 TYPE3, ...
//
// Transforms: LIKE procedure_name  [within procedure return type list]
// Into: field1 TYPE1, field2 TYPE2, field3 TYPE3, ...
//
// The transformation creates explicit typed name entries for procedure return value
// declarations, enabling automatic return type generation from existing schema definitions.
// This is used when procedures need to return data structures that match existing
// tables, views, or other procedures.
//
// The function handles several naming scenarios:
// - Named shape expansion with prefixes for disambiguation (shape_name_column)
// - Duplicate elimination when multiple LIKE clauses reference overlapping schemas
// - Proper type preservation including nullability, sensitivity, and custom types
//
// Unlike parameter expansion, typed names are used in procedure declarations and don't
// participate in the argument bundle system since they describe return values rather
// than input parameters.
//
// The function constructs AST nodes using these patterns from cql.y:
// - typed_names: typed_names ',' typed_name | typed_name
// - typed_name: name data_type_any
// - data_type_any: data_type | name (for custom types)
//
// This enables automatic return type generation that adapts to schema changes.
//
// Here we have found a "like T" name that needs to be rewritten with
// the various columns of T.  We do this by:
// * looking up "T" (this is the only thing that can go wrong)
// * replace the "like T" slug with the first column of T
// * for each additional column create a typed name node and link it in.
// * emit any given name only once, (so you can do like T1, like T1 even if both have the same pk)
static void rewrite_one_typed_name(ast_node *typed_name, symtab *used_names) {
  Contract(is_ast_typed_name(typed_name));
  EXTRACT_ANY(shape_name_ast, typed_name->left); // Optional shape prefix name
  EXTRACT_NOTNULL(shape_def, typed_name->right); // LIKE shape_definition to expand

  // Resolve the shape reference to find the source table/view/procedure
  // This validates that the referenced shape exists and can be used for typed names
  ast_node *found_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
  if (!found_shape) {
    record_error(typed_name);
    return;
  }

  AST_REWRITE_INFO_SET(shape_def->lineno, shape_def->filename);

  // Nothing can go wrong from here on - shape reference has been validated
  record_ok(typed_name);

  // Extract schema information from the resolved shape
  // This contains all field definitions with their types, names, and attributes
  sem_struct *sptr = found_shape->sem->sptr;
  uint32_t count = sptr->count; // Number of fields to expand
  bool_t first_rewrite = true; // Track first typed name replacement
  CSTR shape_name = ""; // Optional prefix for field names

  ast_node *insertion = typed_name; // Current insertion point in list

  // Handle optional shape name prefix for field disambiguation
  // Form: LIKE table_name AS shape_prefix creates typed names like shape_prefix_field
  if (shape_name_ast) {
    EXTRACT_STRING(sname, shape_name_ast);
    shape_name = sname;

    // Note: typed names are part of procedure return type declarations
    // They don't create procedure bodies and don't participate in arg_bundles
    // since they describe return values rather than input parameters
  }

  // Iterate through all fields in the shape definition
  // Each field becomes a typed name with appropriate type information
  for (uint32_t i = 0; i < count; i++) {
    sem_t sem_type = sptr->semtypes[i]; // Semantic type with nullability/attributes
    CSTR name = sptr->names[i]; // Original field name from shape
    CSTR kind = sptr->kinds[i]; // Additional type kind information
    CSTR combined_name = name; // Final name for the typed parameter

    // Apply optional shape prefix for field disambiguation
    // Creates names like "prefix_field" to avoid naming conflicts
    if (shape_name[0]) {
      combined_name = dup_printf("%s_%s", shape_name, name);
    }

    // Skip any fields that we have already added or that are manually present
    // This prevents duplicate typed names when multiple LIKE clauses reference overlapping shapes
    if (!symtab_add(used_names, combined_name, NULL)) {
      continue;
    }

    // Build the typed name AST: combined_name : type
    // Follows cql.y typed_name grammar rule construction
    ast_node *name_ast = new_ast_str(combined_name);
    ast_node *type = rewrite_gen_data_type(sem_type, kind);
    ast_node *new_typed_name = new_ast_typed_name(name_ast, type);
    ast_node *typed_names = insertion->parent; // Parent typed_names list node

    if (!first_rewrite) {
      // Add subsequent typed names after the current insertion point
      // Creates new typed_names list node linking the new field to remaining list
      ast_set_right(typed_names, new_ast_typed_names(new_typed_name, typed_names->right));
    }
    else {
      // Replace the original LIKE typed_name node with the first expanded field
      // This preserves list structure while substituting content
      ast_set_left(typed_names, new_typed_name);
      first_rewrite = false;
    }

    insertion = new_typed_name; // Update insertion point for next field
  }

  // Handle edge case where no fields were expanded (all duplicates or hidden)
  // The original LIKE typed_name node must still be removed from the list
  if (first_rewrite) {
    // Since this can only happen with 100% duplication, there must be a previous typed name
    // If this were the first node, we would have expanded at least something
    EXTRACT_NOTNULL(typed_names, typed_name->parent); // Current typed_names list node
    EXTRACT_NAMED_NOTNULL(tail, typed_names, typed_names->parent); // Previous list node
    ast_set_right(tail, typed_names->right); // Skip current node, linking to next
  }

  AST_REWRITE_INFO_RESET();
}

// Walk the typed name list looking for any LIKE shape_definition forms
// Orchestrates the expansion of all LIKE references in a typed name list
// Each LIKE reference is replaced with the complete field set from the referenced shape
cql_noexport void rewrite_typed_names(ast_node *head) {
  // Global symbol table to track all expanded field names across all LIKE clauses
  // This prevents duplicate names when multiple LIKE clauses reference overlapping shapes
  symtab *used_names = symtab_new();

  // Traverse the typed_names list looking for LIKE expansion opportunities
  // The list may grow during traversal as LIKE nodes are replaced with multiple fields
  for (ast_node *ast = head; ast; ast = ast->right) {
    Contract(is_ast_typed_names(ast)); // Validate list structure
    EXTRACT_NOTNULL(typed_name, ast->left); // Extract individual typed name

    // Check if this typed name is a LIKE shape_definition that needs expansion
    // These are placeholder nodes that represent multiple fields from a referenced shape
    if (is_ast_shape_def(typed_name->right)) {
      rewrite_one_typed_name(typed_name, used_names); // Expand LIKE into actual fields
      if (is_error(typed_name)) { // Propagate expansion errors
        record_error(head); // Mark entire list as failed
        goto cleanup; // Exit on first expansion error
      }
    }
    else {
      // Handle regular typed names (not LIKE references) - no expansion needed
      // Just record the name to prevent future duplicate field expansion
      EXTRACT_STRING(name, typed_name->left); // Get the explicit field name
      symtab_add(used_names, name, NULL); // Mark name as used
    }
  }
  record_ok(head); // All expansions successful

cleanup:
  symtab_delete(used_names); // Clean up name tracking table
}

// These are the canonical short names for types.  They are used in the @op
// directive and in  places where a type name becomes part of a function name.
cql_noexport CSTR _Nonnull rewrite_type_suffix(sem_t sem_type) {
   CSTR result = "";
    switch (core_type_of(sem_type)) {
     case SEM_TYPE_NULL: result = "null"; break;
     case SEM_TYPE_BOOL: result = "bool"; break;
     case SEM_TYPE_INTEGER:  result = "int"; break;
     case SEM_TYPE_LONG_INTEGER: result = "long"; break;
     case SEM_TYPE_REAL:  result = "real"; break;
     case SEM_TYPE_TEXT:  result = "text"; break;
     case SEM_TYPE_BLOB:  result = "blob"; break;
     case SEM_TYPE_OBJECT: result = "object"; break;
     case SEM_TYPE_STRUCT: result = "cursor"; break;
  };
  // Only the above are possible
  Contract(result[0]);
  return result;
}

// Transform reverse apply operator expressions: argument:function(args) → function(argument, args)
// This implements operator overloading for method-call syntax by rewriting to function calls
// Supports both type-specific operators and fallback to the original function name
cql_noexport void rewrite_reverse_apply(ast_node *_Nonnull head) {
  Contract(is_ast_reverse_apply(head));
  EXTRACT_ANY_NOTNULL(argument, head->left); // Left operand (becomes first argument)
  EXTRACT_NOTNULL(call, head->right); // Right side function call
  EXTRACT_ANY_NOTNULL(function_name, call->left); // Function name to potentially rewrite
  EXTRACT_NOTNULL(call_arg_list, call->right); // Original argument list
  // This may be NULL if the function only has one argument (the reverse apply operand)
  EXTRACT(arg_list, call_arg_list->right); // Additional arguments after the operand

  AST_REWRITE_INFO_SET(head->lineno, head->filename);

  EXTRACT_STRING(func, function_name); // Original function name string

  // Extract type information from the left operand for operator resolution
  sem_t sem_type = argument->sem->sem_type; // Base semantic type (int, text, etc.)
  CSTR kind = argument->sem->kind; // Additional type kind (object subtype)
  CSTR new_name = NULL; // Resolved operator function name

  CHARBUF_OPEN(key); // Buffer for building operator lookup keys

  // First attempt: Look for kind-specific operator override
  // Format: "type<kind>:call:function" (e.g., "object<MyClass>:call:to_string")
  if (kind) {
    bprintf(&key, "%s<%s>:call:%s", rewrite_type_suffix(sem_type), kind, func);
    new_name = find_op(key.ptr); // Check @op directive registrations
  }

  // Second attempt: Look for general type-specific operator
  // Format: "type:call:function" (e.g., "text:call:format")
  if (!new_name) {
    bclear(&key);
    bprintf(&key, "%s:call:%s", rewrite_type_suffix(sem_type), func);
    new_name = find_op(key.ptr); // Check for base type operator
  }

  // Fallback: Use original function name if no operator override found
  // This allows reverse apply syntax even for functions without @op directives
  if (!new_name) {
    new_name = func;
  }

  CHARBUF_CLOSE(key);

  // Create durable function name AST node
  // new_name is guaranteed durable (either from symbol table or AST string)
  function_name = new_maybe_qstr(new_name);

  // Build the rewritten function call: new_function(argument, original_args...)
  // The reverse apply operand becomes the first argument in the function call
  ast_node *new_arg_list =
    new_ast_call_arg_list(
      new_ast_call_filter_clause(NULL, NULL), // No filter clause for operator calls
      new_ast_arg_list(argument, arg_list) // Operand first, then original args
    );
  ast_node *new_call = new_ast_call(function_name, new_arg_list);

  AST_REWRITE_INFO_RESET();

  // Replace the reverse_apply node with the rewritten function call
  // This transforms argument:func(args) into func(argument, args) in-place
  ast_set_right(head, new_call->right);
  ast_set_left(head, new_call->left);
  head->type = new_call->type;
}

// Transform polymorphic reverse apply operators: argument:(args...) → function_type1_type2_...
// This implements advanced operator overloading where the function name is determined by
// the types of all arguments. The base function name comes from @op functor:all directives.
// Final function name format: base_name_arg1type_arg2type_... (e.g., "transform_int_text_bool")
//
// Walk through the ast and grab the arg list as well as the function name.
// Create a new call node using these two and the argument passed in
// prior to the ':' symbol.  This is the "overloaded" version of the function
// where the target name is appended with the types of the arguments.  So
// for instance if the function name is "foo" and the arguments are "int, text"
// the new name will be "foo_int_text".
cql_noexport void rewrite_reverse_apply_polymorphic(ast_node *_Nonnull head) {
  Contract(is_ast_reverse_apply_poly_args(head));
  EXTRACT_ANY_NOTNULL(argument, head->left); // Left operand (becomes first argument)
  EXTRACT(arg_list, head->right); // Argument list with type-based naming
  Contract(argument->sem); // Must have semantic analysis

  // Extract type information from the primary operand for base function lookup
  sem_t sem_type = argument->sem->sem_type; // Base semantic type
  CSTR kind = argument->sem->kind; // Additional type kind information

  CHARBUF_OPEN(new_name); // Buffer for building final function name
  CHARBUF_OPEN(key); // Buffer for operator lookup key

  // Look up the base function name using functor:all operator directive
  // This provides the root name that will be extended with argument types
  if (!kind) {
    bprintf(&key, "%s:functor:all", rewrite_type_suffix(sem_type));
  }
  else {
    // Include kind specification for object subtypes
    bprintf(&key, "%s<%s>:functor:all", rewrite_type_suffix(sem_type), kind);
  }

  CSTR base_name = find_op(key.ptr); // Lookup registered functor operator

  if (!base_name) {
    // No functor operator found - this will fail at semantic analysis
    // Use the lookup key as the base name to provide a clear error message
    bprintf(&new_name, "%s", key.ptr);
  }
  else {
    // Start building function name with the resolved base name
    bprintf(&new_name, "%s", base_name);
  }

  CHARBUF_CLOSE(key);

  AST_REWRITE_INFO_SET(head->lineno, head->filename);

  // Append type suffixes for all arguments to create polymorphic function name
  // This creates names like "base_int_text_bool" for type-specific dispatch
  ast_node *item = arg_list;
  while (item) {
    EXTRACT_ANY_NOTNULL(arg, item->left); // Extract each argument expression

    // Append type suffix to function name (e.g., "_int", "_text", "_bool")
    bprintf(&new_name, "_%s", rewrite_type_suffix(arg->sem->sem_type));
    item = item->right; // Move to next argument
  }

  // Create durable string for the AST - must allocate since new_name is temporary
  ast_node *function_name = new_maybe_qstr(Strdup(new_name.ptr));

  CHARBUF_CLOSE(new_name);

  // Build the polymorphic function call AST with type-derived name
  // Format: polymorphic_function_type1_type2(argument, arg1, arg2, ...)
  ast_node *new_arg_list =
    new_ast_call_arg_list(
      new_ast_call_filter_clause(NULL, NULL), // No filter clause needed
      new_ast_arg_list(argument, arg_list) // Primary operand + remaining args
    );
  ast_node *new_call = new_ast_call(function_name, new_arg_list);

  AST_REWRITE_INFO_RESET();

  // Replace the reverse_apply_poly_args node with the polymorphic function call
  // This transforms argument:(args...) into base_type1_type2_...(argument, args...)
  ast_set_right(head, new_call->right);
  ast_set_left(head, new_call->left);
  head->type = new_call->type;
}

// Orchestrates the expansion of all LIKE shape_definition references in procedure parameter lists
// This function manages the complete parameter expansion process, handling both LIKE references
// that need expansion and regular parameters that should be preserved as-is.
//
// Transforms: CREATE PROC p(id INT, LIKE table_name, name TEXT)
// Into: CREATE PROC p(id INT, table_col1 TYPE1, table_col2 TYPE2, ..., name TEXT)
//
// The function coordinates parameter expansion while maintaining a global namespace to prevent
// duplicate parameter names when multiple LIKE clauses reference overlapping schemas. It also
// manages the args_info bytebuf that tracks parameter metadata for code generation.
//
// This enables procedures to automatically adapt their parameter lists to schema changes,
// making them more maintainable and less prone to errors when table definitions evolve.
//
// The function delegates actual expansion work to rewrite_one_param() while providing
// the infrastructure for name tracking, error handling, and metadata collection.
//
// Walk the param list looking for any of the "like T" forms
// if any is found, replace that parameter with the table/shape columns
cql_noexport void rewrite_params(ast_node *head, bytebuf *args_info) {
  // Global symbol table to track all parameter names across the entire list
  // This prevents duplicate parameter names when multiple LIKE clauses overlap
  symtab *param_names = symtab_new();

  // Traverse the parameter list looking for LIKE expansion opportunities
  // The list may grow during traversal as LIKE nodes are replaced with multiple parameters
  for (ast_node *ast = head; ast; ast = ast->right) {
    Contract(is_ast_params(ast)); // Validate list structure
    EXTRACT_NOTNULL(param, ast->left) // Extract individual parameter
    EXTRACT_NOTNULL(param_detail, param->right) // Extract parameter details

    // Check if this parameter is a LIKE shape_definition that needs expansion
    // These are placeholder nodes that represent multiple parameters from a referenced shape
    if (is_ast_shape_def(param_detail->right)) {
      param = rewrite_one_param(param, param_names, args_info);
      if (is_error(param)) { // Propagate expansion errors
        record_error(head);
        goto cleanup;
      }
      ast = param->parent; // Update traversal pointer after expansion
      Invariant(is_ast_params(ast)); // Ensure list structure is preserved
    }
    else {
      // Handle regular parameters (not LIKE references) - no expansion needed
      // Just record the parameter name and metadata for tracking and code generation
      EXTRACT_STRING(param_name, param_detail->left); // Get the explicit parameter name
      CSTR shape_type = ""; // No shape type for regular parameters
      CSTR shape_name = ""; // No shape name for regular parameters

      // Record parameter metadata in the args_info buffer for code generation
      // This maintains consistent parameter tracking across expanded and regular parameters
      if (args_info) {
        bytebuf_append_var(args_info, param_name); // Parameter name
        bytebuf_append_var(args_info, shape_name); // Shape name (empty for regular params)
        bytebuf_append_var(args_info, shape_type); // Shape type (empty for regular params)
      }

      symtab_add(param_names, param_name, NULL); // Mark parameter name as used
    }
  }

  record_ok(head); // All parameter processing successful

cleanup:
  symtab_delete(param_names); // Clean up name tracking table
}

// Generates a CASE expression AST structure for IIF function transformation
// This utility constructs the complex nested AST nodes required to represent a CASE expression
// that implements the ternary conditional logic of the IIF function.
//
// Transforms: IIF(condition, true_value, false_value) logic
// Into: CASE WHEN condition THEN true_value ELSE false_value END AST structure
//
// The function builds the proper hierarchical AST structure following cql.y grammar patterns:
// - case_expr: CASE opt_expr case_list opt_else END
// - case_list: case_list when_clause | when_clause
// - when_clause: WHEN expr THEN expr
// - opt_else: ELSE expr
//
// This creates a complete CASE expression that can be processed by semantic analysis
// and code generation, providing the same conditional evaluation semantics as IIF
// but using standard SQL CASE syntax that's universally supported.
static ast_node *rewrite_gen_iif_case_expr(
  ast_node *expr, // Condition expression to evaluate
  ast_node *val1, // Value to return when condition is true
  ast_node *val2) // Value to return when condition is false (ELSE clause)
{
  // Create the WHEN clause: WHEN expr THEN val1
  // This represents the true branch of the conditional expression
  ast_node *when = new_ast_when(expr, val1);

  // Create the case list containing the single WHEN clause
  // Following cql.y case_list: when_clause pattern (no additional WHEN clauses)
  ast_node *case_list = new_ast_case_list(when, NULL);

  // Create the connector that links the WHEN clause with the ELSE clause
  // This represents: case_list ELSE val2 structure
  ast_node *connector = new_ast_connector(case_list, val2);

  // Create the complete CASE expression: CASE WHEN expr THEN val1 ELSE val2 END
  // First parameter is NULL because this is "CASE WHEN" form, not "CASE expr WHEN" form
  ast_node *case_expr = new_ast_case_expr(NULL, connector);
  return case_expr;
}

// Applies inherited type attributes from named types to column definitions in CREATE TABLE statements
// This function ensures that when columns use custom named types (enums, declared types), they
// automatically inherit the nullability and sensitivity attributes defined in the type declaration.
//
// Transforms: CREATE TABLE t (col my_enum_type, other_col TEXT)
// Where my_enum_type was declared as: DECLARE my_enum_type INTEGER NOT NULL SENSITIVE
// Into: CREATE TABLE t (col my_enum_type NOT NULL SENSITIVE, other_col TEXT)
//
// This automatic attribute inheritance prevents inconsistencies between type declarations and
// their usage in table definitions. Without this rewrite, columns using named types would
// not automatically inherit the nullability and sensitivity constraints, leading to potential
// type safety violations and security issues.
//
// The function only processes column definitions that use string-based type names (custom types)
// rather than built-in type keywords. It looks up the named type definition and applies any
// NOT NULL or SENSITIVE attributes to the column's attribute list.
//
// The function constructs AST nodes using these patterns from cql.y:
// - col_attrs: col_attrs col_attr | col_attr
// - col_attr: NOT NULL | SENSITIVE | DEFAULT expr | CHECK expr
//
// This ensures consistent type semantics across type declarations and table definitions.
//
// This helper rewrites col_def_type_attrs->right nodes to include notnull and sensitive
// flag from the data type of a column in create table statement. This is only applicable
// if column data type of the column is the name of an emum type or a declared named type.
cql_noexport void rewrite_right_col_def_type_attrs_if_needed(ast_node *ast) {
  Contract(is_ast_col_def_type_attrs(ast));
  EXTRACT_NOTNULL(col_def_name_type, ast->left); // Extract column name and type info
  EXTRACT_ANY_NOTNULL(data_type, col_def_name_type->right); // Extract the data type specification
  EXTRACT_ANY(col_attrs, ast->right); // Extract existing column attributes

  // Only process columns that use named types (represented as string nodes)
  // Built-in types like INTEGER, TEXT are represented as specific AST node types
  if (is_ast_str(data_type)) {
    EXTRACT_STRING(name, data_type); // Get the named type identifier
    ast_node *named_type = find_named_type(name); // Look up the type declaration
    if (!named_type) {
      report_error(ast, "CQL0360: unknown type", name);
      record_error(ast);
      return;
    }

    AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

    // Extract semantic type information from the named type declaration
    // This contains the nullability and sensitivity flags defined in the type
    sem_t found_sem_type = named_type->sem->sem_type;

    // Apply NOT NULL attribute if the named type was declared as NOT NULL
    // This creates a col_attrs chain with NOT NULL prepended to existing attributes
    if (!is_nullable(found_sem_type)) {
      col_attrs = new_ast_col_attrs_not_null(NULL, col_attrs);
    }

    // Apply SENSITIVE attribute if the named type was declared as SENSITIVE
    // This creates a sensitive_attr node that wraps the existing attributes
    if (sensitive_flag(found_sem_type)) {
      col_attrs = new_ast_sensitive_attr(NULL, col_attrs);
    }

    // Update the column definition with the inherited attributes
    // The column now has explicit NOT NULL and/or SENSITIVE attributes from its type
    ast_set_right(ast, col_attrs);

    AST_REWRITE_INFO_RESET();
  }

  record_ok(ast); // Mark column definition as processed
}

// Transforms named type references into their underlying concrete type definitions
// This function resolves custom type names (enums, declared types) into their actual
// data type representations, enabling proper type checking and code generation.
//
// Transforms: CAST(expr AS my_enum_type) or my_custom_type in variable declarations
// Where my_enum_type was declared as: DECLARE my_enum_type INTEGER NOT NULL
// Into: The appropriate INTEGER type AST node with proper semantic information
//
// This resolution is essential because the rest of the compilation system needs to work
// with concrete types rather than symbolic type names. The function handles different
// contexts where named types appear and applies appropriate attribute preservation rules.
//
// The function handles two main contexts:
// 1. Cast expressions: Preserve nullability/sensitivity from the cast operand
// 2. Column definitions: Generate base type only (attributes handled separately)
// 3. Variable declarations: Include full type attributes from the named type
//
// This enables a consistent type system where custom types are expanded to their
// underlying representations while maintaining proper semantic information.
//
// Rewrite a data type represented as a string node to the
// actual type if the string name is a declared type.
cql_noexport void rewrite_data_type_if_needed(ast_node *ast) {
  // Handle both direct data type nodes and create_data_type wrapper nodes
  // The create_data_type wrapper is used in some contexts for additional processing
  ast_node *data_type = NULL;
  if (is_ast_create_data_type(ast)) {
    data_type = ast->left; // Extract wrapped data type
  }
  else {
    data_type = ast; // Direct data type node
  }

  // Only process named types represented as string nodes
  // Built-in types like INTEGER, TEXT are already concrete AST nodes
  if (is_ast_str(data_type)) {
    EXTRACT_STRING(name, data_type); // Get the type name identifier
    ast_node *named_type = find_named_type(name); // Look up the type declaration
    if (!named_type) {
      report_error(ast, "CQL0360: unknown type", name);
      record_error(ast);
      return;
    }

    // Extract the semantic type from the named type declaration
    // This contains the underlying type and all associated attributes
    sem_t sem_type = named_type->sem->sem_type;

    // * The cast_expr node doesn't need attributes, it only casts to the
    //   target type.  When casting, both nullability and sensitivity are
    //   preserved. So in that case we remove the extra attributes.  They
    //   are not expected/required in the rewrite.
    //
    // * Columns are a little different; nullability and sensitivity are
    //   encoded differently in columns than in variables.
    //   So in that case we again only produce the base type here.
    //   The caller will do the rest. This work is done in
    //   rewrite_right_col_def_type_attrs_if_needed(ast_node)
    bool_t only_core_type = ast->parent &&
        (is_ast_col_def_name_type(ast->parent) || is_ast_cast_expr(ast->parent));

    if (only_core_type) {
      // Strip attributes and use only the base type (INTEGER, TEXT, etc.)
      // This prevents double-application of nullability/sensitivity attributes
      sem_type = core_type_of(sem_type);
    }

    AST_REWRITE_INFO_SET(data_type->lineno, data_type->filename);

    // Generate the concrete data type AST from the semantic type information
    // This creates the appropriate type node (INTEGER, TEXT, etc.) with proper attributes
    ast_node *node = rewrite_gen_data_type(sem_type, named_type->sem->kind);

    AST_REWRITE_INFO_RESET();

    // Replace the string-based type reference with the concrete type AST
    // This transforms symbolic type names into actual type structures
    ast_set_left(data_type, node->left);
    ast_set_right(data_type, node->right);
    data_type->sem = node->sem; // Transfer semantic information
    data_type->type = node->type; // Transfer AST type (not semantic type)
  }

  record_ok(ast); // Mark type resolution as successful
}

// Transforms nullable variable references into non-null assertions using compiler intrinsics
// This function implements null-safety transformations by wrapping potentially nullable
// expressions in calls to the cql_inferred_notnull() compiler intrinsic function.
//
// Transforms: variable_name or object.field_name (when nullable)
// Into: cql_inferred_notnull(variable_name) or cql_inferred_notnull(object.field_name)
//
// This rewrite is used by CQL's null-safety analysis system when it can prove that a
// nullable variable or field is actually non-null in a specific context, but the type
// system still considers it nullable. The cql_inferred_notnull() intrinsic provides
// a bridge between static analysis and the type system.
//
// The transformation handles both simple identifiers and dot-notation field access,
// preserving the original expression structure while changing the nullability semantics.
// This enables more precise type information in contexts where null-safety can be proven.
//
// The function constructs a function call AST using this pattern from cql.y:
// - call: name '(' opt_arg_list ')'
// - arg_list: arg_list ',' expr | expr
//
// The resulting call is semantically analyzed to ensure the transformation is valid.
cql_noexport void rewrite_nullable_to_notnull(ast_node *_Nonnull ast) {
  Contract(is_id_or_dot(ast)); // Must be identifier or field access

  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Reconstruct the original expression as an argument to the intrinsic function
  // This preserves the exact structure while changing the containing context
  ast_node *id_or_dot;
  if (is_id(ast)) {
    // Handle simple identifier case: variable_name
    EXTRACT_STRING(name, ast);
    id_or_dot = new_maybe_qstr(name); // Create new identifier node
  }
  else {
    // Handle dot notation case: object.field_name
    Invariant(is_ast_dot(ast));
    EXTRACT_NAME_AND_SCOPE(ast); // Extract scope and field name
    id_or_dot = new_ast_dot(new_maybe_qstr(scope), new_maybe_qstr(name));
  }

  // Create the cql_inferred_notnull function call structure
  // This intrinsic function tells the type system to treat the argument as non-null
  ast_node *cql_inferred_notnull = new_ast_str("cql_inferred_notnull");

  // Build the argument list for the function call
  // Following cql.y call_arg_list: call_filter_clause opt_arg_list pattern
  ast_node *call_arg_list =
    new_ast_call_arg_list(
      new_ast_call_filter_clause(NULL, NULL), // No filter clause needed
      new_ast_arg_list(id_or_dot, NULL) // Single argument: original expression
    );

  // Transform the original node into a function call node
  // This changes: variable -> cql_inferred_notnull(variable)
  ast->type = k_ast_call; // Change AST node type to function call
  ast_set_left(ast, cql_inferred_notnull); // Set function name
  ast_set_right(ast, call_arg_list); // Set argument list

  AST_REWRITE_INFO_RESET();

  // Validate the transformation by performing semantic analysis
  // This ensures the rewritten expression is semantically valid and properly typed
  sem_expr(ast);

  // The null-safety rewrite should never introduce semantic errors
  // If this fails, there's a bug in the null-safety analysis system
  Invariant(!is_error(ast));
}

// Transforms compact guard statement syntax into standard IF-THEN-END IF structure
// This function provides syntactic sugar for simple conditional statements by allowing
// a more compact form that gets expanded into the full IF statement syntax.
//
// Transforms: IF condition single_statement
// Into: IF condition THEN single_statement END IF
//
// The guard statement syntax provides a convenient shorthand for simple conditional
// execution without requiring the full THEN...END IF block structure. This is especially
// useful for single-line conditional statements and error handling patterns.
//
// The transformation creates the proper nested AST structure that matches the standard
// IF statement pattern expected by semantic analysis and code generation. The rewritten
// statement is immediately analyzed to ensure semantic validity.
//
// The function constructs AST nodes using these patterns from cql.y:
// - if_stmt: IF expr THEN stmt_list opt_elseif_list opt_else END IF
// - cond_action: expr THEN stmt_list (condition with statement block)
// - stmt_list: stmt_list stmt | stmt
// - if_alt: ELSEIF cond_action opt_elseif_list opt_else | ELSE stmt_list | [empty]
//
// This enables more concise conditional syntax while maintaining full semantic compatibility.
cql_noexport void rewrite_guard_stmt_to_if_stmt(ast_node *_Nonnull ast) {
  Contract(is_ast_guard_stmt(ast));

  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  EXTRACT_ANY_NOTNULL(expr, ast->left); // Extract the condition expression
  EXTRACT_ANY_NOTNULL(stmt, ast->right); // Extract the statement to execute

  // Transform the guard statement into a full IF statement structure
  // This changes the AST node type from guard_stmt to if_stmt
  ast->type = k_ast_if_stmt;

  // Create the condition-action pair for the IF clause
  // Following cql.y cond_action: expr THEN stmt_list pattern
  // The statement is wrapped in a stmt_list for consistency with IF syntax
  ast_set_left(ast, new_ast_cond_action(expr, new_ast_stmt_list(stmt, NULL)));

  // Create an empty alternative clause (no ELSE or ELSEIF)
  // Following cql.y if_alt: [empty] pattern for simple IF statements
  ast_set_right(ast, new_ast_if_alt(NULL, NULL));

  AST_REWRITE_INFO_RESET();

  // Immediately analyze the rewritten IF statement to ensure semantic validity
  // This validates that the transformation is correct and the statement is well-formed
  sem_one_stmt(ast);
}

// Inserts automatic type casts and literal replacements in printf-style function calls
// This function bridges CQL's flexible type system with the strict type requirements of
// C printf functions, particularly sqlite3_mprintf used in generated code.
//
// The function analyzes printf format strings and automatically adjusts arguments whose
// types don't exactly match format specifier requirements. It handles two main cases:
// 1. NULL values: Replaced with appropriate zero-valued literals for numeric types
// 2. Type mismatches: Wrapped with cast expressions to match expected types
//
// Example transformations:
// - printf("value: %d", NULL) → printf("value: %d", 0)
// - printf("long: %ld", NULL) → printf("long: %ld", 0L)
// - printf("real: %g", integer_val) → printf("real: %g", CAST(integer_val AS REAL))
// - printf("int: %d", long_val) → printf("int: %d", CAST(long_val AS INTEGER))
//
// This is essential because sqlite3_mprintf and other C printf functions require exact
// type matching for format specifiers, while CQL allows more flexible type conversions.
// The automatic adjustments preserve CQL's ergonomic type system while generating
// correct C code that doesn't rely on undefined behavior.
//
// The function constructs cast expressions and literals using patterns from cql.y:
// - cast_expr: CAST '(' expr AS data_type_any ')'
// - num: INTEGER_LITERAL | LONG_LITERAL | REAL_LITERAL
//
// This enables transparent printf compatibility without requiring manual type adjustments.
cql_noexport void rewrite_printf_inserting_casts_as_needed(ast_node *ast, CSTR format_string) {
  Contract(is_ast_call(ast)); // Must be a function call
  Contract(!is_error(ast)); // Must be semantically valid
  EXTRACT_NOTNULL(call_arg_list, ast->right); // Extract the argument list structure
  EXTRACT_NOTNULL(arg_list, call_arg_list->right); // Extract the actual arguments

  // Initialize format string parser to analyze printf format specifiers
  // This iterator tracks expected types for each format placeholder
  printf_iterator *iterator = minipool_alloc(ast_pool, (uint32_t)sizeof_printf_iterator);
  printf_iterator_init(iterator, NULL, format_string);

  // Skip the format string argument itself and process the format arguments
  // The first argument is the format string, subsequent arguments are the values
  ast_node *args_for_format = arg_list->right;
  for (ast_node *arg_item = args_for_format; arg_item; arg_item = arg_item->right) {
    // Get the expected type for the current format specifier
    sem_t sem_type = printf_iterator_next(iterator);
    // We know the format string cannot have an error.
    Contract(sem_type != SEM_TYPE_ERROR);
    // We know that we do not have too many arguments.
    Contract(sem_type != SEM_TYPE_OK);

    ast_node *arg = arg_item->left; // Current argument expression
    AST_REWRITE_INFO_SET(arg->lineno, arg->filename);

    if (core_type_of(arg->sem->sem_type) == SEM_TYPE_NULL) {
      // NULL values cannot be cast in non-SQL contexts, so replace with zero literals
      // This provides safe default values that match the expected format types
      switch (sem_type) {
        case SEM_TYPE_INTEGER:
          ast_set_left(arg_item, new_ast_num(NUM_INT, "0")); // Replace with integer 0
          break;
        case SEM_TYPE_LONG_INTEGER:
          ast_set_left(arg_item, new_ast_num(NUM_LONG, "0")); // Replace with long 0L
          break;
        case SEM_TYPE_REAL:
          ast_set_left(arg_item, new_ast_num(NUM_REAL, "0.0")); // Replace with real 0.0
          break;
        default:
          // Reference types (TEXT, BLOB, OBJECT) can remain NULL
          // These are handled properly by printf implementations
          break;
      }
    }
    else if (core_type_of(arg->sem->sem_type) != sem_type) {
      Invariant(is_numeric(sem_type)); // Only numeric types need casting
      // Type mismatch detected - insert cast to match format specifier requirements
      // This handles cases like passing INTEGER to %g (REAL) or LONG to %d (INTEGER)
      ast_node *type_ast;
      switch (sem_type) {
        case SEM_TYPE_INTEGER:
          type_ast = new_ast_type_int(NULL); // Create INTEGER type node
          break;
        case SEM_TYPE_LONG_INTEGER:
          type_ast = new_ast_type_long(NULL); // Create LONG_INTEGER type node
          break;
        default:
          Invariant(sem_type == SEM_TYPE_REAL); // Must be REAL type
          type_ast = new_ast_type_real(NULL); // Create REAL type node
          break;
      }
      // Create cast expression and replace the original argument
      ast_set_left(arg_item, new_ast_cast_expr(arg, type_ast));
    }
    AST_REWRITE_INFO_RESET();
  }

  // Verify that all format specifiers have corresponding arguments
  // This ensures the format string and argument count are properly balanced
  Contract(printf_iterator_next(iterator) == SEM_TYPE_OK);

  // Re-analyze the entire call expression to validate all transformations
  // This ensures the rewritten function call is semantically correct
  sem_expr(ast);
}

// Efficient utility for appending nodes to linked list structures with head/tail tracking
// This function maintains both head and tail pointers while adding nodes to the end of
// a linked list, enabling O(1) append operations for list construction.
//
// The function handles two cases:
// 1. Empty list: Sets both head and tail to the new node
// 2. Non-empty list: Links the new node after the current tail and updates tail pointer
//
// This pattern is commonly used throughout AST construction where lists need to be built
// incrementally, such as building select_expr_list, stmt_list, or arg_list structures.
// The ->right pointer convention follows standard CQL AST linking patterns.
//
// The head/tail tracking approach avoids O(n²) complexity that would result from
// repeatedly traversing to the end of the list for each append operation.
//
// This enables efficient construction of large AST lists during rewriting operations.
static void add_tail(ast_node **head, ast_node **tail, ast_node *node) {
  if (*head) {
    // List already has elements - link new node after current tail
    ast_set_right(*tail, node);
  }
  else {
    // Empty list - new node becomes the head
    *head = node;
  }
  // Update tail pointer to the newly added node
  *tail = node;
}

// Constructs and appends scoped column references to SELECT expression lists
// This utility function creates properly structured SELECT expression nodes for column
// references, handling both scoped (table.column) and unscoped (column) forms.
//
// Creates: scope.name (if scope is provided) or name (if scope is NULL)
// Then wraps in: SELECT expression list structure for use in SELECT statements
//
// The function handles two naming patterns:
// 1. Scoped references: table_name.column_name (dot notation for disambiguation)
// 2. Unscoped references: column_name (simple identifier)
//
// This is commonly used in @COLUMNS expansion where column references need to be
// generated programmatically and added to SELECT lists. The proper AST wrapping
// ensures compatibility with semantic analysis and code generation.
//
// The function constructs AST nodes using these patterns from cql.y:
// - select_expr: expr opt_as_alias (column expression without alias)
// - select_expr_list: select_expr_list ',' select_expr | select_expr
// - dot: expr '.' IDENTIFIER (for scoped column access)
// - name: IDENTIFIER (for simple column names)
//
// This enables automatic generation of properly structured column references.
static void append_scoped_name(
  ast_node **head, // Head pointer for the select expression list
  ast_node **tail, // Tail pointer for efficient appending
  CSTR scope, // Optional table/scope name (NULL for unscoped)
  CSTR name) // Column name
{
  ast_node *expr = NULL;
  if (scope) {
    // Create scoped reference: scope.name using dot notation
    // Following cql.y dot: expr '.' IDENTIFIER pattern
    expr = new_ast_dot(new_maybe_qstr(scope), new_maybe_qstr(name));
  }
  else {
    // Create simple column reference: name
    // Following cql.y name: IDENTIFIER pattern
    expr = new_maybe_qstr(name);
  }

  // Wrap the column expression in a SELECT expression node (no alias)
  // Following cql.y select_expr: expr pattern (opt_as_alias is NULL)
  ast_node *select_expr = new_ast_select_expr(expr, NULL);

  // Wrap in a select expression list node for proper list structure
  // Following cql.y select_expr_list: select_expr pattern
  ast_node *select_expr_list = new_ast_select_expr_list(select_expr, NULL);

  // Append to the growing list using efficient tail tracking
  add_tail(head, tail, select_expr_list);
}

// This is our helper struct with the computed symbol tables for disambiguation
// we flow this around when we need to do the searches.
typedef struct jfind_t {
  sem_join *jptr;
  symtab *location;
  symtab *dups;
  symtab *tables;
} jfind_t;

// This just gives us easy access to the sem_struct or NULL
static sem_struct *jfind_table(jfind_t *jfind, CSTR name) {
  symtab_entry *entry = symtab_find(jfind->tables, name);
  return entry ? (sem_struct *)(entry->val) : NULL;
}

// Initializes fast lookup tables for column name resolution and disambiguation
// This function creates optimized symbol tables that enable O(1) lookups during column
// expansion operations, avoiding O(n³) algorithmic complexity that would result from
// repeatedly searching through JOIN structures for each column reference.
//
// The function builds three critical lookup tables:
// 1. location: Maps column names to the first table that contains them
// 2. dups: Tracks column names that appear in multiple tables (need disambiguation)
// 3. tables: Maps table names to their semantic structures for fast access
//
// This preprocessing is essential for @COLUMNS expansion where hundreds of column
// references might need to be resolved. Without these lookup tables, each column
// would require scanning all tables in the FROM clause, leading to cubic complexity.
//
// The disambiguation detection works by attempting to add each column name to the
// location table - if the add fails (name already exists), the column is marked
// as requiring scope qualification in the dups table.
//
// This enables efficient column expansion with proper scope resolution for complex JOINs.
static void jfind_init(jfind_t *jfind, sem_join *jptr) {
  jfind->jptr = jptr; // Store reference to JOIN structure

  // Initialize the three core lookup tables for fast column resolution
  // These tables convert O(n) searches into O(1) lookups during expansion

  // Maps column name → first table name that contains this column
  // Used to determine the default scope for unambiguous column references
  jfind->location = symtab_new();

  // Tracks column names that appear in multiple tables
  // These columns require explicit table qualification to avoid ambiguity
  jfind->dups = symtab_new();

  // Maps table name → sem_struct pointer for fast table metadata access
  // Enables quick lookup of table schemas without linear search
  jfind->tables = symtab_new();

  // Build the lookup tables by scanning all tables and columns in the FROM clause
  // This preprocessing step enables efficient column resolution during expansion
  for (uint32_t i = 0; i < jptr->count; i++) {
    CSTR name = jptr->names[i]; // Current table name
    sem_struct *sptr = jptr->tables[i]; // Current table structure

    // Map table name to its semantic structure for fast metadata access
    symtab_add(jfind->tables, name, (void *)sptr);

    // Process all columns in the current table to build column resolution maps
    for (uint32_t j = 0; j < sptr->count; j++) {
      CSTR col = sptr->names[j]; // Current column name

      // Attempt to register this column with its first table location
      // If the add fails, the column already exists in another table (duplicate)
      if (!symtab_add(jfind->location, col, (void*)name)) {
        // Column name collision detected - mark as requiring disambiguation
        // Columns in the dups table must be qualified with table names
        symtab_add(jfind->dups, col, NULL);
      }
    }
  }
}

// Cleans up the fast lookup tables used for column name resolution and disambiguation
// This function properly deallocates all symbol tables created by jfind_init() to prevent
// memory leaks in the amalgamated compilation environment. It safely handles partial
// initialization scenarios where some tables might not have been created.
//
// The function performs defensive cleanup by checking each table pointer before deletion,
// ensuring safe operation even if initialization was incomplete due to errors or early
// termination during the column expansion process.
//
// This cleanup is essential because:
// 1. The jfind_t structure contains dynamically allocated symbol tables
// 2. Memory leaks in the amalgam affect the entire compilation process
// 3. Error conditions might leave the structure in partially initialized states
// 4. The tables can contain hundreds of entries for complex JOIN operations
//
// The function ensures complete cleanup of all three core lookup tables:
// - location: Column name to table name mapping
// - dups: Duplicate column name tracking
// - tables: Table name to semantic structure mapping
//
// This enables safe resource management during @COLUMNS expansion operations.
static void jfind_cleanup(jfind_t *jfind) {
  // Safely delete the column location lookup table
  // This table maps column names to their first occurring table
  if (jfind->location) {
    symtab_delete(jfind->location);
  }

  // Safely delete the duplicate column tracking table
  // This table tracks columns that appear in multiple tables and need disambiguation
  if (jfind->dups) {
    symtab_delete(jfind->dups);
  }

  // Safely delete the table metadata lookup table
  // This table maps table names to their semantic structure pointers
  if (jfind->tables) {
    symtab_delete(jfind->tables);
  }
}

// Validates type compatibility between required and actual columns in @COLUMNS LIKE operations
// This function ensures that when using @COLUMNS(table LIKE shape), the columns from the table
// have compatible types with the corresponding columns in the shape definition.
//
// The type checking is essential for @COLUMNS LIKE operations because:
// - LIKE clauses specify which columns should be included based on a template shape
// - The actual table must have compatible columns for each required column
// - Type mismatches would cause runtime errors or data corruption
// - Column positions may differ between required and actual structures
//
// Example validation: @COLUMNS(employee LIKE person) requires that employee table
// has columns compatible with person shape (same names, assignable types).
//
// The function performs comprehensive validation including:
// - Column name existence checking in the target table
// - Type compatibility verification using semantic type system
// - Proper error reporting with scoped column names for diagnostics
// - Fast-path optimization when structures are identical (no LIKE clause)
//
// This ensures type safety in dynamic column selection operations.
//
// Here we check if the indicated column of the required sptr is a type match
// for the same column name (maybe different index) in the actual column.  We
// have to do this because we want to make sure that when you say @COLUMNS(X like foo)
// that the foo columns of X are the same type as those in foo.
static bool_t verify_matched_column(
  ast_node *ast, // AST node for error reporting (has correct line/column info)
  sem_struct *sptr_reqd, // Required structure from LIKE clause (template)
  uint32_t i_reqd, // Index of column in required structure
  sem_struct *sptr_actual, // Actual table structure being validated
  CSTR scope) // Table name for error reporting
{
  CHARBUF_OPEN(err); // Buffer for error message construction
  bool_t ok = false; // Return value: validation success
  CSTR col = sptr_reqd->names[i_reqd]; // Column name from required structure

  // Fast path optimization: if structures are identical, no validation needed
  // This occurs when emitting from the same structure without LIKE filtering
  if (sptr_reqd == sptr_actual) {
    ok = true;
    goto cleanup;
  }

  // Build scoped column name for better error diagnostics
  // Format: "table_name.column_name" to clearly identify the problematic column
  bprintf(&err, "%s.%s", scope, col);

  // Look up the required column in the actual table structure
  // Column positions may differ between required and actual structures
  int32_t i_actual = find_col_in_sptr(sptr_actual, col);
  if (i_actual < 0) {
    // Column not found in target table - report missing column error
    report_error(ast, "CQL0069: name not found", err.ptr);
    goto cleanup;
  }

  // Verify type compatibility between required and actual column types
  // This uses the standard CQL type assignment verification system
  // The AST node provides exact line/column information for the @COLUMNS directive
  if (!sem_verify_assignment(ast, sptr_reqd->semtypes[i_reqd], sptr_actual->semtypes[i_actual], err.ptr)) {
    // Type mismatch detected - error already reported by sem_verify_assignment
    goto cleanup;
  }

  // All validations passed - column exists and has compatible type
  ok = true;

cleanup:
  CHARBUF_CLOSE(err); // Clean up error message buffer
  return ok; // Return validation result
}

// Here we've found one column_calculation node, this corresponds to a single
// instance of @COLUMNS(...) in the select list.  When we process this, we
// will replace it with its expansion.  Note that each one is independent
// so often you really only need one (distinct is less powerful if you have two or more).

// Expands a single @COLUMNS(...) directive into explicit column references
// This function processes one @COLUMNS calculation node and replaces it with a list of
// concrete SELECT expressions. It handles all @COLUMNS syntax variants and generates
// the appropriate scoped column references for the final SELECT statement.
//
// Supported @COLUMNS syntax patterns:
// - @COLUMNS(table.column) - Explicit scoped column reference
// - @COLUMNS(table) - All columns from specified table
// - @COLUMNS(table LIKE shape) - Table columns filtered by shape compatibility
// - @COLUMNS(LIKE shape) - Columns from any table matching the shape
// - @COLUMNS(DISTINCT ...) - Eliminate duplicate column names in expansion
//
// The function generates properly scoped column references to avoid ambiguity in JOINs
// and performs type validation for LIKE clauses to ensure schema compatibility.
// Each @COLUMNS directive operates independently, enabling precise control over
// column selection in complex queries.
//
// The expansion transforms high-level column selection into concrete SQL that can be
// processed by standard semantic analysis and code generation systems.
static void rewrite_column_calculation(ast_node *column_calculation, jfind_t *jfind) {
  Contract(is_ast_column_calculation(column_calculation));

  // Check if DISTINCT modifier is specified to eliminate duplicate column names
  // This is essential for JOINs where multiple tables may have columns with the same name
  bool_t distinct = !!column_calculation->right;

  // Create name tracking table only if DISTINCT is specified
  // This table prevents duplicate columns when expanding multiple table references
  symtab *used_names = distinct ? symtab_new() : NULL;

  // Initialize linked list for building the expanded column expression list
  // These pointers enable O(1) append operations during column expansion
  ast_node *tail = NULL;
  ast_node *head = NULL;

  // Process each column calculation item in the @COLUMNS directive
  // Each item represents a different column selection pattern (explicit, table, LIKE, etc.)
  for (ast_node *item = column_calculation->left; item; item = item->right) {
    Contract(is_ast_col_calcs(item)); // Validate list structure
    EXTRACT(col_calc, item->left); // Extract individual calculation

    if (is_ast_dot(col_calc->left)) {
      // Handle explicit scoped column references: @COLUMNS(table.column)
      // These are literal column specifications that bypass expansion logic
      // They are emitted directly without type checking or filtering

      EXTRACT_NOTNULL(dot, col_calc->left); // Extract dot expression
      EXTRACT_STRING(left, dot->left); // Table/scope name
      EXTRACT_STRING(right, dot->right); // Column name

      // Emit the explicit column reference without modification
      // No type checking needed since this is a direct user specification
      append_scoped_name(&head, &tail, left, right);

      // Track the column name if DISTINCT mode is enabled
      // This prevents later expansion from duplicating explicitly mentioned columns
      if (used_names) {
        symtab_add(used_names, right, NULL);
      }
    }
    else if (col_calc->left) {
      // Handle table-specific column selection: @COLUMNS(table) or @COLUMNS(table LIKE shape)
      // This expands to all columns from the specified table, optionally filtered by shape

      EXTRACT_STRING(scope, col_calc->left); // Extract table name

      // Look up the table in the FROM clause using fast lookup table
      sem_struct *sptr_table = jfind_table(jfind, scope);

      if (!sptr_table) {
        // Table not found in FROM clause - report error with table name
        report_error(col_calc->left, "CQL0054: table not found", scope);
        record_error(column_calculation);
        goto cleanup;
      }

      // Check for optional LIKE shape filter clause
      EXTRACT(shape_def, col_calc->right);

      sem_struct *sptr; // Structure defining which columns to include

      if (shape_def) {
        // LIKE clause specified: @COLUMNS(table LIKE shape)
        // Find the shape definition and use it to filter table columns
        ast_node *found_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
        if (!found_shape) {
          record_error(column_calculation);
          goto cleanup;
        }
        // Use the shape structure to determine which columns to include
        // Only columns that exist in both the table and shape will be emitted
        sptr = found_shape->sem->sptr;
      }
      else {
        // No LIKE clause: @COLUMNS(table)
        // Include all columns from the specified table
        sptr = sptr_table;
      }

      // Iterate through all columns in the source structure (table or shape)
      // Generate scoped column references for each eligible column
      for (uint32_t j = 0; j < sptr->count; j++) {
        CSTR col = sptr->names[j]; // Current column name

        // Filter out special columns that should not appear in SELECT lists
        // This implements SQLite's behavior where certain columns are implicit
        if (!strcmp(col, "rowid") || (sptr->semtypes[j] & SEM_TYPE_HIDDEN_COL)) {
          // `rowid` is a special case, it's not a real column it's a virtual
          // column from the base table. we don't want to emit it in the select
          // list unless it is explictly mentioned

          // This business is much more important that it might look. When
          // considering backed table the backed table does not mention rowid
          // but it is known to be there.  The CTE for the backed table include
          // rowid from the underlying table, it's important for doing say
          // delete and stuff like that.  However we do not want rowid to appear
          // in results unless it is explicitly mentioned. The way we do that is
          // to make * not include rowid.  This is exactly what SQLite itself
          // does.  Rowid is "there" but it doesn't count.
          //
          // we might want to alias the rowid column in backed tables to make
          // this less likely to conflict with a user named table... but that's
          // a different issue. As it is, you'll get an error if you name a
          // backed column rowid and that's fine I guess.  It seems like a
          // terrible terrible idea to name your own column rowid.
          continue;
        }

        // Check for duplicate columns when DISTINCT mode is enabled
        // Skip columns that have already been included in the expansion
        if (used_names && !symtab_add(used_names, col, NULL)) {
          continue; // Column already processed
        }

        // Generate the scoped column reference: scope.column
        append_scoped_name(&head, &tail, scope, col);

        // Validate type compatibility for LIKE-filtered columns
        // Ensures that table columns match the required shape types
        if (!verify_matched_column(tail, sptr, j, sptr_table, scope)) {
          record_error(column_calculation);
          goto cleanup;
        }
      }
    }
    else {
      // Handle shape-based column selection: @COLUMNS(LIKE shape)
      // This finds columns in any table that match the specified shape definition

      EXTRACT_NOTNULL(shape_def, col_calc->right); // Extract the LIKE shape clause

      // Resolve the shape definition to get column requirements
      ast_node *found_shape = sem_find_shape_def(shape_def, LIKEABLE_FOR_VALUES);
      if (!found_shape) {
        record_error(column_calculation);
        goto cleanup;
      }

      // Extract the shape structure defining required columns and their types
      sem_struct *sptr = found_shape->sem->sptr;

      // Process each column required by the shape definition
      // Find the table containing each column and generate appropriate references
      for (uint32_t i = 0; i < sptr->count; i++) {
        CSTR col = sptr->names[i]; // Required column name

        // Check for duplicates if DISTINCT mode is enabled
        // Skip columns that have already been processed
        if (!used_names || symtab_add(used_names, col, NULL)) {

          // Look up which table contains this column name
          // This uses the fast lookup table built during initialization
          symtab_entry *entry = symtab_find(jfind->location, col);

          if (!entry) {
            // Required column not found in any table in FROM clause
            report_error(shape_def, "CQL0069: name not found", col);
            record_error(column_calculation);
            goto cleanup;
          }

          CSTR scope = (CSTR)entry->val; // Table name containing the column

          // Get the table structure for type validation
          sem_struct *sptr_table = jfind_table(jfind, scope);
          Invariant(sptr_table); // Must exist (came from our own lookup)

          // Determine whether to include table scope in the output
          // Only add scope qualification if column is ambiguous AND DISTINCT is specified
          // Without DISTINCT, ambiguous columns will cause semantic analysis errors later
          CSTR used_scope = (used_names && symtab_find(jfind->dups, col)) ? scope : NULL;

          // Generate the column reference with appropriate scoping
          append_scoped_name(&head, &tail, used_scope, col);

          // Validate type compatibility between shape requirement and actual table column
          // This ensures the found column has compatible type with the shape definition
          if (!verify_matched_column(tail, sptr, i, sptr_table, scope)) {
            record_error(column_calculation);
            goto cleanup;
          }
        }
      }
    }
  }

  // Replace the @COLUMNS calculation node with the expanded column list
  // This splices the generated column expressions into the SELECT expression list
  ast_node *splice = column_calculation->parent; // Parent select_expr_list node

  // Perform the AST splice operation to replace @COLUMNS with expanded columns
  // This complex linking preserves the list structure while substituting content

  // This logic works even if head is an alias for tail

  ast_set_left(splice, head->left); // Replace calc with first expanded column
  ast_set_right(tail, splice->right); // Link last expanded column to remaining list
  ast_set_right(splice, head->right); // Link first column to rest of expansion

  // Mark the column calculation as successfully expanded
  record_ok(column_calculation);

cleanup:
  // Clean up the name tracking table if DISTINCT mode was used
  // This prevents memory leaks in complex queries with multiple @COLUMNS directives
  if (used_names) {
    symtab_delete(used_names);
  }
}

// This function orchestrates the expansion of advanced column selection syntax in SELECT
// statements, transforming wildcards and @COLUMNS directives into explicit column lists.
// It handles the complete column expansion process from high-level syntax to concrete columns.
//
// Transforms: SELECT *, T.*, @COLUMNS(scope LIKE shape), @COLUMNS(T), @COLUMNS(DISTINCT T, U)
// Into: SELECT table1.col1, table1.col2, table2.col3, table2.col4, ...
//
// The function supports several advanced column selection features:
// - Wildcard expansion (* and T.*) converted to @COLUMNS directives
// - Table-specific column selection with @COLUMNS(table_name)
// - Shape-based column filtering with LIKE clauses for schema compatibility
// - DISTINCT column selection to eliminate duplicate column names in complex joins
// - Scoped column access with automatic disambiguation for ambiguous column names
//
// This is a powerful code generation feature that makes working with complex schemas
// much more manageable by eliminating the need to manually list dozens of columns.
//
// The function constructs explicit column references using patterns from cql.y:
// - select_expr_list: select_expr_list ',' select_expr | select_expr
// - select_expr: expr opt_as_alias
// - dot: expr '.' IDENTIFIER (for scoped column access)
//
// This enables automatic schema evolution where column lists adapt to table changes.
//
// At this point we're going to walk the select expression list looking for
// the construct @COLUMNS(...) with its various forms.  This is a generalization
// of the T.* syntax that allows you to pull slices of the tables and to
// get distinct columns where there are duplicates due to joins.  Ultimately
// this is just sugar but the point is that there could be dozens of such columns
// and if you have to type it all yourself it is very easy to get it wrong. So
// here we're going to expand out the @COLUMNS(...) operator into the actual
// tables/columns you requested.  SQLite, has no support for this sort of thing
// so it, and indeed the rest of the compilation chain, will just see the result
// of the expansion.
cql_noexport void rewrite_select_expr_list(ast_node *select_expr_list, sem_join *jptr_from) {

  // Normalize wildcard syntax by converting * and T.* to @COLUMNS directives
  // This creates a uniform processing path where all column expansion goes through @COLUMNS
  rewrite_star_and_table_star_as_columns_calc(select_expr_list, jptr_from);

  // Initialize the join finder helper structure for fast column disambiguation
  // This provides efficient lookup tables for resolving column names and detecting conflicts
  jfind_t jfind = {0};

  // Phase 2: Process each expression in the SELECT list, expanding @COLUMNS directives
  for (ast_node *item = select_expr_list; item; item = item->right) {
    Contract(is_ast_select_expr_list(item));

    // Validate that column expansion operations have a FROM clause to work with
    // all star and table star will be rewritten to @columns(...) by now so any left will indicate
    // jptr_from is null like a select with no from clause.
    if (is_ast_column_calculation(item->left) || is_ast_star(item->left) || is_ast_table_star(item->left)) {
      if (!jptr_from) {
        report_error(select_expr_list, "CQL0052: select *, T.*, or @columns(...) cannot be used with no FROM clause", NULL);
        record_error(item->left);
        record_error(select_expr_list);
        return;
      }
    }

    // Process @COLUMNS(...) directives by expanding them into explicit column references
    if (is_ast_column_calculation(item->left)) {
      EXTRACT_NOTNULL(column_calculation, item->left);
      Invariant(jptr_from);

      // Lazy initialization of the join finder helper tables
      // We only create these expensive lookup structures when actually needed
      if (!jfind.jptr) {
        jfind_init(&jfind, jptr_from);
      }

      AST_REWRITE_INFO_SET(column_calculation->lineno, column_calculation->filename);

      // Perform the core column expansion transformation
      // This replaces the @COLUMNS directive with explicit scoped column references
      // Following cql.y select_expr_list: select_expr_list ',' select_expr pattern
      // Results in: table1.col1, table1.col2, table2.col3, ...
      rewrite_column_calculation(column_calculation, &jfind);

      AST_REWRITE_INFO_RESET();

      // Propagate any expansion errors to the parent select expression list
      if (is_error(column_calculation)) {
        record_error(select_expr_list);
        goto cleanup;
      }
    }
  }

  // Mark the select expression list as successfully processed
  record_ok(select_expr_list);

cleanup:
  // Clean up the join finder helper structures to prevent memory leaks
  jfind_cleanup(&jfind);
}

static int32_t cursor_base;

// This utility function transforms a name_list into a shape_exprs structure by recursively
// converting each name into a shape expression. It's used in cursor shape definitions to
// specify which columns should be included when creating cursors based on procedure shapes.
//
// Transforms: name_list of (col1, col2, col3)
// Into: shape_exprs containing (col1 col1), (col2 col2), (col3 col3)
//
// The transformation creates additive shape expressions where each column name appears
// twice - once as the source and once as the target. This follows the pattern used in
// CQL's shape system where "column_name column_name" means "include column_name as column_name".
//
// This is commonly used when creating cursors that should have the same shape as a subset
// of columns from a procedure or table, particularly in parent-child JOIN rewriting where
// key columns need to be extracted from child procedures.
//
// The function constructs AST nodes using these patterns from cql.y:
// - shape_exprs: shape_exprs ',' shape_expr | shape_expr
// - shape_expr: expr opt_as_alias (where both expr and alias are the same column name)
//
// Returns NULL for empty name lists, enabling proper termination of recursive processing.
static ast_node *shape_exprs_from_name_list(ast_node *ast) {
  if (!ast) {
    return NULL; // Base case: empty name list results in no shape expressions
  }

  Contract(is_ast_name_list(ast));

  // Create a shape expression for the current name using the additive form
  // Following cql.y shape_expr: expr opt_as_alias pattern
  // Both the source and target are the same column name: "column_name column_name"
  ast_node *shape_expr = new_ast_shape_expr(ast->left, ast->left);

  // Recursively process the remaining names in the list and chain them together
  // Following cql.y shape_exprs: shape_exprs ',' shape_expr | shape_expr pattern
  // This builds: (name1 name1), (name2 name2), (name3 name3), ...
  return new_ast_shape_exprs(shape_expr, shape_exprs_from_name_list(ast->right));
}

// This function recursively generates the complex statement sequences needed to create
// and populate partitions for each child result set in parent-child JOIN operations.
// It transforms high-level parent-child JOIN syntax into procedural partition management code.
//
// For each child result, it generates this pattern:
// DECLARE __key__N CURSOR LIKE child_proc(selected_columns);
// LET __partition__N := cql_partition_create();
// DECLARE __child_cursor__N CURSOR FOR CALL child_proc(args);
// LOOP FETCH __child_cursor__N BEGIN
//   FETCH __key__N FROM __child_cursor__N(LIKE __key__N);
//   SET __result__N := cql_partition_cursor(__partition__N, __key__N, __child_cursor__N);
// END;
//
// This implements a hash-table-like data structure where child rows are grouped by
// their key columns, enabling efficient lookups when joining with parent rows.
// The partition system allows CQL to implement complex parent-child relationships
// without requiring nested loops or expensive JOIN operations.
//
// The function constructs complex nested AST structures using patterns from cql.y:
// - stmt_list: stmt_list stmt | stmt
// - declare_cursor_like_name: DECLARE name CURSOR LIKE name '(' shape_def ')'
// - let_stmt: LET name ASSIGN expr
// - loop_stmt: LOOP fetch_stmt stmt_list
// - fetch_values_stmt: FETCH name FROM shape
// - assign: SET name ASSIGN expr
//
// Each child result gets its own numbered set of variables and cursors for isolation.
//
// This creates the statements for each child partition creation
static ast_node *rewrite_child_partition_creation(
  ast_node *child_results,
  int32_t cursor_num,
  ast_node *tail)
{
  if (!child_results) {
    return tail; // Base case: no more child results to process
  }

  // note that I have not included the numbers that get appended to the names
  //
  // let __partition__ := cql_partition_create();
  // declare __child_cursor__ cursor for call child_proc();  -- args as needed
  // loop fetch __child_cursor__
  // begin
  //   fetch __key__ from __child_cursor__(like __key__);
  //   set result_ := cql_partition_cursor(__partition__, __key__, __child_cursor__));
  // end;
  //

  // Extract components from the current child result specification
  EXTRACT_NOTNULL(child_result, child_results->left);
  EXTRACT_NOTNULL(call_stmt, child_result->left); // CALL child_proc(args)
  EXTRACT_NOTNULL(named_result, child_result->right);
  EXTRACT_NOTNULL(name_list, named_result->right); // JOIN key columns
  EXTRACT_STRING(proc_name, call_stmt->left); // Child procedure name

  // Generate unique names for this child's partition infrastructure
  // Each child gets numbered variables to avoid conflicts with other children
  CSTR key_name = dup_printf("__key__%d", cursor_num);
  CSTR cursor_name = dup_printf("__child_cursor__%d", cursor_num);
  CSTR partition_name = dup_printf("__partition__%d", cursor_num);
  CSTR result_name = dup_printf("__result__%d", cursor_base);

  // Build the complete statement sequence for this child partition
  return new_ast_stmt_list(
      // AST for: DECLARE __key__N CURSOR LIKE child_proc(selected_columns);
      // Following cql.y declare_cursor_like_name: DECLARE name CURSOR LIKE name '(' shape_def ')' pattern
      // This creates a cursor with the same shape as the specified columns from the child procedure
      // The key cursor will hold the JOIN key values for partitioning
      new_ast_declare_cursor_like_name(
        new_maybe_qstr(key_name), // cursor name: __key__N
        new_ast_shape_def( // shape definition
          new_ast_like( // LIKE clause
            new_ast_str(proc_name), // procedure name to get shape from
            NULL
          ),
          shape_exprs_from_name_list(name_list) // specific columns from name_list
        )
      ),
    new_ast_stmt_list(
      // AST for: LET __partition__N := cql_partition_create();
      // Following cql.y let_stmt: LET name ASSIGN expr pattern
      // This creates a new partition object for grouping child results by their key values
      new_ast_let_stmt(
        new_maybe_qstr(partition_name), // variable name: __partition__N
        new_ast_call( // function call
          new_ast_str("cql_partition_create"), // function name
          new_ast_call_arg_list( // empty argument list
            new_ast_call_filter_clause(NULL, NULL),
            NULL
          )
        )
      ),
    new_ast_stmt_list(
      // AST for: DECLARE __child_cursor__N CURSOR FOR CALL child_proc(args);
      // Following cql.y declare_cursor: DECLARE name CURSOR FOR row_source pattern
      // This declares a cursor that will iterate over the child procedure results
      new_ast_declare_cursor(
        new_ast_str(cursor_name), // cursor name: __child_cursor__N
        call_stmt // the CALL statement with procedure and args
      ),
    // AST for: LOOP FETCH __child_cursor__N BEGIN ... END;
    // Following cql.y loop_stmt: LOOP fetch_stmt stmt_list pattern
    // This creates the main loop that processes each row from the child cursor
    new_ast_stmt_list(
      new_ast_loop_stmt(
        // The FETCH statement that controls the loop
        // Following cql.y fetch_stmt: FETCH name pattern
        new_ast_fetch_stmt(
          new_maybe_qstr(cursor_name), // cursor to fetch from: __child_cursor__N
          NULL // no INTO clause (standard fetch)
        ),
        // Loop body - nested statement list containing fetch and assignment operations
        new_ast_stmt_list(
          // AST for: FETCH __key__N FROM __child_cursor__N(LIKE __key__N);
          // Following cql.y fetch_values_stmt: FETCH name FROM name_columns_values pattern
          // This extracts the key columns from the current cursor row into the key cursor
          new_ast_fetch_values_stmt(
            NULL, // no dummy values (opt_insert_dummy_spec)
            new_ast_name_columns_values( // name and column specification
              new_maybe_qstr(key_name), // target cursor: __key__N
              new_ast_columns_values( // columns and values specification
                NULL, // no explicit column list
                new_ast_from_shape( // FROM shape clause
                  new_ast_column_spec( // column specification
                    new_ast_shape_def( // shape definition
                      new_ast_like( // LIKE clause
                        new_maybe_qstr(key_name), // reference cursor: __key__N
                        NULL
                      ),
                      NULL // no additional shape expressions
                    )
                  ),
                  new_ast_str(cursor_name) // source cursor: __child_cursor__N
                )
              )
            )
          ),
          // AST for: SET __result__N := cql_partition_cursor(__partition__N, __key__N, __child_cursor__N);
          // Following cql.y assign: SET name ASSIGN expr pattern
          // This adds the current cursor row to the partition, grouped by the key
          new_ast_stmt_list(
            new_ast_assign( // SET statement
              new_maybe_qstr(result_name), // target variable: __result__N
              new_ast_call( // function call
                new_ast_str("cql_partition_cursor"), // function name
                new_ast_call_arg_list( // argument list structure
                  new_ast_call_filter_clause(NULL, NULL), // no filter clause
                  new_ast_arg_list( // first argument: partition
                    new_maybe_qstr(partition_name),
                    new_ast_arg_list( // second argument: key cursor
                      new_maybe_qstr(key_name),
                      new_ast_arg_list( // third argument: data cursor
                        new_ast_str(cursor_name),
                        NULL // end of argument list
                      )
                    )
                  )
                )
              )
            ),
            NULL // end of statement list
          )
        )
      ),
      // Recursively process the next child result, building the statement chain
      // This creates the complete sequence for all child results in the parent-child JOIN
      rewrite_child_partition_creation(child_results->right, cursor_num + 1, tail)
  ))));
}

// Builds typed name lists for child result columns in parent-child JOIN cursor declarations
// This function recursively constructs typed_names AST structures that define the schema
// for child result columns in the output cursor of parent-child JOIN operations.
//
// For each child result, it creates: child_name OBJECT<child_proc SET> NOT NULL
// Where child_name is either explicitly specified or auto-generated as "child0", "child1", etc.
//
// The function generates proper type declarations for child result columns that will be
// populated with result set objects from child procedure calls. These columns enable
// access to the partitioned child data that corresponds to each parent row.
//
// Example transformation for two child results:
// child_results: [CALL proc1(...) AS child1, CALL proc2(...) AS child2]
// Into: child1 OBJECT<proc1 SET> NOT NULL, child2 OBJECT<proc2 SET> NOT NULL
//
// The OBJECT<proc_name SET> type represents a result set from the specified procedure,
// enabling type-safe access to child data through the partition extraction system.
// The NOT NULL constraint ensures that child result columns always contain valid
// result set objects (though the result sets themselves may be empty).
//
// The function constructs AST nodes using these patterns from cql.y:
// - typed_names: typed_names ',' typed_name | typed_name
// - typed_name: name data_type_with_options
// - data_type_with_options: data_type col_attrs
// - object_type: OBJECT '<' name SET '>'
//
// This enables automatic cursor schema generation that adapts to child procedure changes.
static ast_node *build_child_typed_names(
  ast_node *child_results,
  int32_t child_index)
{
  if (!child_results) {
    return NULL;
  }

  // named_type  child[n] object<child_proc set>, ...

  Contract(is_ast_child_results(child_results));
  EXTRACT_NOTNULL(child_result, child_results->left);
  EXTRACT_NOTNULL(call_stmt, child_result->left);
  EXTRACT_NOTNULL(named_result, child_result->right);
  EXTRACT_NOTNULL(name_list, named_result->right);
  EXTRACT_STRING(proc_name, call_stmt->left);

  // optional child result name
  CSTR child_column_name = NULL;
  if (named_result->left) {
    EXTRACT_STRING(name, named_result->left);
    child_column_name = name;
  }

  if (!child_column_name) {
    child_column_name = dup_printf("child%d", child_index);
  }

  // AST for: child_name OBJECT<proc_name SET> NOT NULL, ...
  // This builds a typed_names list representing child result columns in cursor declarations
  // Each entry corresponds to: typed_name ',' typed_names in cql.y grammar
  return new_ast_typed_names(
    // AST for: child_name OBJECT<proc_name SET> NOT NULL
    // This creates a typed_name entry corresponding to: sql_name data_type_with_options in cql.y
    new_ast_typed_name(
      new_maybe_qstr(child_column_name), // column name (child1, child2, etc. or explicit name)
      new_ast_notnull( // NOT NULL wrapper for the type
        // AST for: OBJECT<proc_name SET>
        // This creates an object type representing a result set from the child procedure
        // Corresponds to: OBJECT '<' name SET '>' in cql.y grammar
        new_ast_type_object(
          new_ast_str(dup_printf("%s SET", proc_name)) // "child_proc SET" - result set type
        )
      )
    ),
    // Recursively build the rest of the typed_names list for remaining child results
    build_child_typed_names(child_results->right, child_index + 1)
  );
}

// Creates output cursor declarations that combine parent and child shapes in parent-child JOINs
// This function generates DECLARE CURSOR LIKE statements that define output cursors with
// a composite schema containing both parent procedure columns and child result set columns.
//
// Transforms: Parent-child JOIN specification
// Into: DECLARE __out_cursor__ CURSOR LIKE (LIKE parent_proc, child1 OBJECT<child_proc1 SET>, child2 OBJECT<child_proc2 SET>, ...)
//
// The output cursor schema is constructed by combining:
// 1. All columns from the parent procedure (via LIKE parent_proc)
// 2. Child result columns with OBJECT<proc_name SET> types for each child procedure
//
// This composite cursor enables the parent-child JOIN system to produce result rows that
// contain both the parent data and associated child result sets. Each row includes the
// parent columns plus typed columns containing partitioned child data accessible through
// the result set object interface.
//
// Example for a parent procedure "get_orders" with child procedures "get_items" and "get_payments":
// DECLARE __out_cursor__ CURSOR LIKE (
//   LIKE get_orders,                           -- parent columns: order_id, customer, date, etc.
//   child1 OBJECT<get_items SET> NOT NULL,    -- child items result set
//   child2 OBJECT<get_payments SET> NOT NULL  -- child payments result set
// );
//
// The cursor declaration uses the typed_names system to specify the exact schema required
// for the combined parent-child result structure. This enables type-safe access to both
// parent fields and child result sets through a single cursor interface.
//
// The function constructs AST nodes using these patterns from cql.y:
// - declare_cursor_like_typed_names: DECLARE name CURSOR LIKE '(' typed_names ')'
// - typed_names: typed_names ',' typed_name | typed_name
// - shape_def: LIKE name (for parent procedure shape inclusion)
//
// This enables automatic cursor schema generation that reflects parent-child relationships.
static ast_node *rewrite_out_cursor_declare(
  CSTR parent_proc_name,
  CSTR out_cursor_name,
  ast_node *child_results,
  ast_node *tail)
{
  // AST for: DECLARE __out_cursor__ CURSOR LIKE (LIKE parent_proc, child1 OBJECT<child_proc1 SET>, ...)
  // This creates an output cursor that combines the parent procedure's shape with child result columns
  return new_ast_stmt_list(
    // AST for: DECLARE cursor_name CURSOR LIKE (typed_names)
    // Corresponds to: DECLARE name CURSOR LIKE '(' typed_names ')' in cql.y grammar
    new_ast_declare_cursor_like_typed_names(
      new_ast_str(out_cursor_name), // cursor name: __out_cursor__
      // AST for the typed_names list: (LIKE parent_proc, child1 OBJECT<...>, child2 OBJECT<...>, ...)
      // This builds the comma-separated list of type specifications for the cursor
      new_ast_typed_names(
        // First entry: LIKE parent_proc (inherits all columns from parent procedure)
        // AST for: shape_def entry in typed_names (corresponds to: shape_def in typed_name rule)
        new_ast_typed_name(
          NULL, // no explicit name for LIKE clause
          // AST for: LIKE parent_proc
          // This creates a shape definition that inherits the parent procedure's result shape
          new_ast_shape_def(
            new_ast_like( // LIKE clause
              new_ast_str(parent_proc_name), // procedure name to inherit shape from
              NULL // no arguments to LIKE
            ),
            NULL // no additional shape expressions
          )
        ),
        // Remaining entries: child result columns built by build_child_typed_names
        // Each child becomes: childN OBJECT<child_proc SET> NOT NULL
        build_child_typed_names(child_results, 1)
      )
    ),
    tail // append to statement list chain
  );
}

// Generates FETCH statements to extract JOIN key columns from parent cursor into child key cursors
// This function recursively creates FETCH statements that populate each child's key cursor
// with the appropriate key column values from the current parent row, enabling efficient
// partition lookup during parent-child JOIN processing.
//
// For each child result, it generates: FETCH __key__N FROM parent_cursor(LIKE __key__N);
// This extracts only the columns that are needed for the JOIN operation between parent and child.
//
// The key extraction is essential for the partition-based JOIN algorithm because:
// 1. Child data is pre-partitioned by key columns during the setup phase
// 2. For each parent row, we need to extract the key values that correspond to JOIN conditions
// 3. These key values are used to look up the relevant child partition using hash-table lookup
// 4. The partition system enables O(1) lookup instead of O(n) nested loop joins
//
// Example transformation for two child results with different JOIN keys:
// Child 1 JOINs on (order_id), Child 2 JOINs on (customer_id, region)
// Generates:
//   FETCH __key__0 FROM __parent__(LIKE __key__0);  -- extracts order_id
//   FETCH __key__1 FROM __parent__(LIKE __key__1);  -- extracts customer_id, region
//
// The LIKE clause ensures that only the specific key columns are extracted, maintaining
// efficient cursor operations and avoiding unnecessary data copying. Each key cursor
// has been previously declared with the exact shape needed for its child's JOIN operation.
//
// This is a critical component of the parent-child JOIN rewrite that enables scalable
// processing of hierarchical data relationships without expensive nested loops.
//
// The function constructs AST nodes using these patterns from cql.y:
// - fetch_values_stmt: FETCH name FROM name '(' shape_def ')'
// - shape_def: LIKE name (for extracting specific columns matching a cursor shape)
// - stmt_list: stmt_list stmt | stmt
//
// This enables efficient key-based partition lookup in complex parent-child relationships.
static ast_node *rewrite_load_child_keys_from_parent(
  ast_node *child_results,
  CSTR parent_cursor_name,
  int32_t cursor_num,
  ast_node *tail)
{
  if (!child_results) {
    return tail;
  }

  // generates this pattern for each child
  // fetch __key__ from __parent__0(like __key__);

  CSTR key_name = dup_printf("__key__%d", cursor_num);

  return new_ast_stmt_list(
    // AST for: FETCH __key__N FROM parent_cursor(LIKE __key__N);
    // This extracts key columns from the parent cursor into the child's key cursor
    // Each child needs its key populated from the current parent row before partitioning
    new_ast_fetch_values_stmt(
      NULL, // no dummy values (opt_insert_dummy_spec)
      // AST for the FETCH target and source specification
      new_ast_name_columns_values( // name and column specification
        new_maybe_qstr(key_name), // target cursor: __key__N
        new_ast_columns_values( // columns and values specification
          NULL, // no explicit column list (use shape)
          // AST for: FROM parent_cursor(LIKE __key__N)
          // This creates a FROM shape clause that extracts columns matching the key shape
          new_ast_from_shape( // FROM shape clause
            new_ast_column_spec( // column specification
              // AST for: LIKE __key__N
              // This specifies which columns to extract (those matching key cursor shape)
              new_ast_shape_def( // shape definition
                new_ast_like( // LIKE clause
                  new_maybe_qstr(key_name), // reference cursor: __key__N
                  NULL // no arguments to LIKE
                ),
                NULL // no additional shape expressions
              )
            ),
            new_ast_str(parent_cursor_name) // source cursor: parent cursor name
          )
        )
      )
    ),
    // Recursively generate FETCH statements for remaining child results
    rewrite_load_child_keys_from_parent(child_results->right, parent_cursor_name, cursor_num + 1, tail)
  );
}

static ast_node *rewrite_insert_children_partitions(
  ast_node *child_results,
  int32_t cursor_num)
{
  if (!child_results) {
    return NULL;
  }

  //  cql_partition_extract(__partition__, __key__)
  CSTR partition_name = dup_printf("__partition__%d", cursor_num);
  CSTR key_name = dup_printf("__key__%d", cursor_num);

  // AST for: cql_extract_partition(__partition__N, __key__N), ...
  // This builds a comma-separated list of function calls for extracting child partitions
  // Used in INSERT or VALUES contexts to populate child result columns
  return new_ast_insert_list(
    // AST for: cql_extract_partition(__partition__N, __key__N)
    // This function call extracts the partitioned child results for the current key
    new_ast_call(
      new_ast_str("cql_extract_partition"), // function name
      // AST for the function argument list: (__partition__N, __key__N)
      new_ast_call_arg_list( // argument list structure
        new_ast_call_filter_clause(NULL, NULL), // no filter clause
        new_ast_arg_list( // first argument: partition object
          new_maybe_qstr(partition_name), // __partition__N variable
          new_ast_arg_list( // second argument: key cursor
            new_maybe_qstr(key_name), // __key__N cursor
            NULL // end of argument list
          )
        )
      )
    ),
    // Recursively build the insert_list for remaining child results
    // This creates the comma-separated chain: expr1, expr2, expr3, ...
    // Corresponds to: insert_list_item ',' insert_list in cql.y grammar
    rewrite_insert_children_partitions(child_results->right, cursor_num + 1)
  );
}

static ast_node *rewrite_declare_parent_cursor(
  CSTR parent_cursor_name,
  ast_node *parent_call_stmt,
  ast_node *tail)
{
  Contract(is_ast_call_stmt(parent_call_stmt));

  // AST for: DECLARE parent_cursor CURSOR FOR CALL parent_proc(args);
  // This creates a cursor that will iterate over the parent procedure results

  return new_ast_stmt_list(
    // AST for: DECLARE cursor_name CURSOR FOR row_source
    // Corresponds to: DECLARE name CURSOR FOR row_source in cql.y grammar
    // The row_source in this case is the CALL statement for the parent procedure
    new_ast_declare_cursor(
      new_ast_str(parent_cursor_name), // cursor name: parent cursor name
      parent_call_stmt // row source: CALL parent_proc(args)
    ),
    tail // append to statement list chain
  );
}

// Generates FETCH statements that combine parent data with extracted child partitions
// This function creates the core data combination logic for parent-child JOINs by generating
// FETCH statements that populate the output cursor with both parent columns and child result sets.
//
// Generates: FETCH __out_cursor__ FROM VALUES(from parent_cursor, cql_extract_partition(...), ...);
// This creates a single result row containing parent data plus all associated child result sets.
//
// The FETCH FROM VALUES pattern enables the combination of heterogeneous data sources:
// 1. Parent columns: Copied directly from the parent cursor using "from parent_cursor" syntax
// 2. Child partitions: Extracted from pre-built partitions using cql_extract_partition() calls
// 3. Output cursor: Receives the combined data in a unified schema
//
// This is the critical data fusion step in parent-child JOINs where individual parent rows
// are augmented with their corresponding child data. The partition extraction functions
// use the key values (populated by rewrite_load_child_keys_from_parent) to perform O(1)
// lookups in the hash-table-based partition structures.
//
// Example transformation for parent "orders" with children "items" and "payments":
// FETCH __out_cursor__ FROM VALUES(
//   from __parent__,                                    -- order_id, customer, date, total
//   cql_extract_partition(__partition__0, __key__0),   -- items result set
//   cql_extract_partition(__partition__1, __key__1)    -- payments result set
// );
//
// The resulting output cursor contains:
// - All parent columns (order_id, customer, date, total)
// - Child result sets as typed columns (items OBJECT<get_items SET>, payments OBJECT<get_payments SET>)
//
// This enables efficient hierarchical data processing where each parent row includes
// complete access to all associated child data through result set objects, avoiding
// the need for separate queries or expensive JOIN operations.
//
// The function constructs AST nodes using these patterns from cql.y:
// - fetch_values_stmt: FETCH name FROM VALUES '(' insert_list ')'
// - insert_list: insert_list ',' expr | expr
// - from_shape: FROM name (for copying all columns from a source cursor)
//
// This enables scalable parent-child data relationships with O(1) child data access.
static ast_node *rewrite_fetch_results(
  CSTR out_cursor_name,
  CSTR parent_cursor_name,
  ast_node *child_results)
{
  Contract(is_ast_child_results(child_results));

  //   -- load up the wider cursor
  //   fetch __out_cursor__ from values(
  //     from __parent__,
  //     cql_partition_extract(__partition__1, __key__1),
  //     cql_partition_extract(__partition__2, __key__2)
  //   );

  return new_ast_stmt_list(
    // AST for: FETCH __out_cursor__ FROM VALUES(from parent_cursor, partition_extract1, partition_extract2, ...);
    // This populates the output cursor by combining parent columns with extracted child partitions
    new_ast_fetch_values_stmt(
      NULL, // no dummy values (opt_insert_dummy_spec)
      // AST for the FETCH target and source specification
      new_ast_name_columns_values( // name and column specification
        new_ast_str(out_cursor_name), // target cursor: output cursor name
        new_ast_columns_values( // columns and values specification
          NULL, // no explicit column list
          // AST for: VALUES(from parent_cursor, cql_extract_partition(...), ...)
          // This creates the value list combining parent data with child partition extracts
          new_ast_insert_list( // value list (corresponds to insert_list in cql.y)
            // AST for: FROM parent_cursor
            // This includes all columns from the parent cursor in the result
            new_ast_from_shape( // FROM shape clause
              new_ast_str(parent_cursor_name), // source cursor: parent cursor
              NULL // no specific shape specification
            ),
            // AST for: cql_extract_partition(__partition__1, __key__1), cql_extract_partition(__partition__2, __key__2), ...
            // This builds the comma-separated list of partition extraction calls for each child
            rewrite_insert_children_partitions(child_results, cursor_base)
          )
        )
      )
    ),
    new_ast_stmt_list(
      // AST for: OUT UNION __out_cursor__;
      // This outputs the combined row to the result set
      // Corresponds to: OUT UNION name in cql.y grammar
      new_ast_out_union_stmt(
        new_ast_str(out_cursor_name) // cursor to output: output cursor name
      ),
      NULL // end of statement list
    )
  );
}

// Generates the main processing loop for parent-child JOIN operations
// This function creates the core loop structure that iterates over parent rows and combines
// each parent row with its corresponding child data through efficient partition-based lookups.
//
// Generates: LOOP FETCH parent_cursor BEGIN ... key extraction ... data fusion ... output ... END
// This creates the complete parent-row processing logic that drives the parent-child JOIN system.
//
// The generated loop implements a sophisticated data joining algorithm:
// 1. Iteration: LOOP FETCH parent_cursor traverses each parent row
// 2. Key Extraction: Extract JOIN key values for each child using rewrite_load_child_keys_from_parent
// 3. Data Fusion: Combine parent data with child partitions using rewrite_fetch_results
// 4. Output Generation: Emit the combined row through OUT UNION statements
//
// This loop structure replaces expensive nested-loop JOINs with an efficient hash-table-based
// approach where child data is pre-partitioned by key values during setup, enabling O(1)
// lookups for each parent row rather than O(n) scans through child data.
//
// Example transformation for parent "orders" with children "items" and "payments":
// LOOP FETCH __parent__ BEGIN
//   FETCH __key__0 FROM __parent__(LIKE __key__0);                    -- extract order_id
//   FETCH __key__1 FROM __parent__(LIKE __key__1);                    -- extract customer_id
//   FETCH __out_cursor__ FROM VALUES(
//     from __parent__,                                                -- parent: order_id, customer, date, total
//     cql_extract_partition(__partition__0, __key__0),               -- items for this order
//     cql_extract_partition(__partition__1, __key__1)                -- payments for this customer
//   );
//   OUT UNION __out_cursor__;                                         -- emit combined result
// END;
//
// This approach enables scalable hierarchical data processing where:
// - Parent rows drive the iteration (no Cartesian products)
// - Child data is accessed through efficient hash-table lookups
// - Each output row contains complete parent + children information
// - Complex parent-child relationships are handled transparently
//
// The function orchestrates calls to other rewrite functions:
// - rewrite_load_child_keys_from_parent: Extracts JOIN keys from current parent row
// - rewrite_fetch_results: Combines parent data with extracted child partitions
//
// The function constructs AST nodes using these patterns from cql.y:
// - loop_stmt: LOOP fetch_stmt stmt_list END
// - fetch_stmt: FETCH name (for parent cursor iteration)
// - stmt_list: stmt_list stmt | stmt (for the loop body)
//
// This enables efficient parent-child data relationships with O(1) child data access per parent row.
static ast_node *rewrite_loop_fetch_parent_cursor(
  CSTR parent_cursor_name,
  CSTR out_cursor_name,
  ast_node *child_results)
{
  // generate code to read rows from parent and attach the matching rows from each partition above via hash lookup
  //
  // declare __parent__ cursor for call parent();  -- args as needed
  // loop fetch __parent__
  // begin
  //   -- look up key columns using the matching column names
  //   fetch __key__1 from __parent__(like __key__1);
  //   fetch __key__2 from __parent__(like __key__2);
  //
  //   -- load up the wider cursor
  //   fetch __out_cursor__ from values(
  //     from __parent__,
  //     cql_partition_extract(__partition__1, __key__1),
  //     cql_partition_extract(__partition__2, __key__2)
  //   );
  //   out union __out_cursor__;
  // end;

  return new_ast_stmt_list(
    // AST for: LOOP FETCH parent_cursor BEGIN ... END
    // This creates the main processing loop that iterates over each parent row
    // and combines it with matching child partition data
    new_ast_loop_stmt(
      // AST for: FETCH parent_cursor
      // This is the loop control statement - fetches next row from parent cursor
      // Corresponds to: LOOP fetch_stmt BEGIN_ opt_stmt_list END in cql.y grammar
      new_ast_fetch_stmt(
        new_ast_str(parent_cursor_name), // cursor to fetch from: parent cursor
        NULL // no INTO clause (standard fetch)
      ),
      // Loop body: chain of statements to execute for each parent row
      // 1. Extract key columns from parent into child key cursors
      // 2. Combine parent data with child partition extracts and output the result
      rewrite_load_child_keys_from_parent(child_results, parent_cursor_name, cursor_base,
        rewrite_fetch_results(out_cursor_name, parent_cursor_name, child_results)
      )
    ),
    NULL // end of statement list
  );
}

// The general rewrite looks like this:
//
// create proc test_parent_child()
// begin
//   out union call parent(2) join call child(1) using (x);
// end;
//
// becomes:
//
// CREATE PROC test_parent_child ()
// BEGIN
//   DECLARE __result__0 BOOL NOT NULL;
//   DECLARE __key__0 CURSOR LIKE test_child(x);
//   LET __partition__0 := cql_partition_create();
//   DECLARE __child_cursor__0 CURSOR FOR CALL test_child(1);
//   LOOP FETCH __child_cursor__0
//   BEGIN
//     FETCH __key__0(x) FROM VALUES(__child_cursor__0.x);
//     SET __result__0 := cql_partition_cursor(__partition__0, __key__0, __child_cursor__0);
//   END;
//
//   The above repeats once for each child result set
//
//   DECLARE __out_cursor__0 CURSOR LIKE (x INTEGER, child1 OBJECT<test_child SET> NOT NULL);
//   DECLARE __parent__0 CURSOR FOR CALL test_parent(2);
//   LOOP FETCH __parent__0
//   BEGIN
//     FETCH __key__0(x) FROM VALUES(__parent__0.x);
//     FETCH __out_cursor__0(x, child1) FROM VALUES(__parent__0.x, cql_extract_partition(__partition__0, __key__0));
//     OUT UNION __out_cursor__0;
//   END;
// END;
//
cql_noexport void rewrite_out_union_parent_child_stmt(ast_node *ast) {
  Contract(is_ast_out_union_parent_child_stmt(ast));

  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  CSTR result_name = dup_printf("__result__%d", cursor_base);
  CSTR out_cursor_name = dup_printf("__out_cursor__%d", cursor_base);
  CSTR parent_cursor_name = dup_printf("__parent__%d", cursor_base);

  // AST for: DECLARE __result__N BOOL NOT NULL;
  // This creates a boolean result variable (required by the rewrite but not used in the generated code)
  // Corresponds to: DECLARE sql_name_list data_type_with_options in cql.y grammar
  ast_node *result_var =
    new_ast_declare_vars_type(
      new_ast_name_list( // variable name list
        new_maybe_qstr(result_name), NULL), // __result__N variable name
      new_ast_notnull(new_ast_type_bool(NULL)) // BOOL NOT NULL type
    );

  EXTRACT_NOTNULL(child_results, ast->right);
  EXTRACT_NOTNULL(call_stmt, ast->left);
  EXTRACT_STRING(parent_proc_name, call_stmt->left);

  // Find the statement list context where we need to insert the generated code
  // We traverse up the AST to find the containing statement list
  ast_node *stmt_tail = ast;
  while (!is_ast_stmt_list(stmt_tail)) {
    stmt_tail = stmt_tail->parent;
  }

  // Generate the complete rewritten code by chaining together all the rewrite functions
  // This creates the full sequence of statements needed to implement parent-child joins:
  // 1. Child partition creation (cursors and partitioning)
  // 2. Output cursor declaration (combined parent+child shape)
  // 3. Parent cursor declaration (for the parent procedure call)
  // 4. Main processing loop (fetch parent rows and join with child partitions)
  ast_node *result = rewrite_child_partition_creation(child_results, cursor_base,
    rewrite_out_cursor_declare(parent_proc_name, out_cursor_name, child_results,
      rewrite_declare_parent_cursor(parent_cursor_name, call_stmt,
        rewrite_loop_fetch_parent_cursor(parent_cursor_name, out_cursor_name, child_results)
      )
    )
  );

  // Find the end of the generated statement chain so we can link it into the existing AST
  ast_node *end = result;
  Invariant(is_ast_stmt_list(end));

  while (end->right) {
    end = end->right;
    Invariant(is_ast_stmt_list(end));
  }

  Invariant(is_ast_stmt_list(end));

  // Splice the generated code into the AST:
  // - Link the end of our generated code to what follows the original statement
  // - Link the statement list to our generated code, replacing the original
  ast_set_right(end, stmt_tail->right);
  ast_set_right(stmt_tail, result);

  AST_REWRITE_INFO_RESET();

  // Transform the original OUT UNION parent() JOIN child() statement into a simple variable declaration
  // This effectively replaces the complex parent-child join with the generated implementation code
  // The original AST node is reused as the result variable declaration
  ast_set_left(ast, result_var->left);
  ast_set_right(ast, result_var->right);
  ast->type = result_var->type;

  // Update cursor_base to account for the cursors we created for each child result
  int32_t child_count = 0;
  while (child_results) {
    child_count++;
    child_results = child_results->right;
  }
  cursor_base += child_count;
}

typedef struct {
  ast_node *backed_table;
  CSTR key;
  sem_t sem_type_key;
  CSTR val;
  sem_t sem_type_val;
} backed_expr_list_info;

// Each column in the backed table needs an entry in the select list for the generated
// create proc.  It will fetch from either the key blob or the value blob.  This can be
// generalized in the future but for now we support only the "two blob" backing store
// shape.  We peel off the first item and then recurse to add the nested item.  Not
// especially economical but fine for any normal sized table.  This can be made non-recursive
// if it ever matters.
static ast_node *rewrite_backed_expr_list(backed_expr_list_info *info, uint32_t index) {
  sem_struct *sptr = info->backed_table->sem->sptr;
  if (index >= sptr->count) {
    return NULL;
  }

  sem_t sem_type = sptr->semtypes[index];
  bool_t is_key_column = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Determine which blob column to extract from based on whether this is a key or value column
  ast_node *col_name_ast;
  if (is_key_column) {
     col_name_ast = new_str_or_qstr(info->key, info->sem_type_key);
  }
  else {
     col_name_ast = new_str_or_qstr(info->val, info->sem_type_val);
  }

  // AST for: cql_blob_get(T.key_or_val_column, table_name.column_name) AS column_name, ...
  // This builds a SELECT expression list where each backed table column is extracted from blob storage
  // Corresponds to: select_expr ',' select_expr_list in cql.y grammar
  ast_node *result = new_ast_select_expr_list(
    // AST for: cql_blob_get(T.blob_column, table.column_name) AS column_name
    // This creates a single SELECT expression that extracts a column value from a blob
    new_ast_select_expr(
      // AST for: cql_blob_get(T.blob_column, table.column_name)
      // This function call extracts the column value from the appropriate blob (key or value)
      new_ast_call(
        new_ast_str("cql_blob_get"), // function name
        new_ast_call_arg_list( // argument list structure
          new_ast_call_filter_clause(NULL, NULL), // no filter clause
          new_ast_arg_list( // first argument: T.blob_column
            // AST for: T.key_or_val_column
            // This references the blob column containing the serialized data
            new_ast_dot(
              new_maybe_qstr("T"), // table alias "T"
              col_name_ast // key or value blob column name
            ),
            new_ast_arg_list( // second argument: table.column_name
              // AST for: table_name.column_name
              // This specifies which column to extract from the blob
              new_ast_dot(
                new_maybe_qstr(sptr->struct_name), // table/struct name
                new_str_or_qstr(sptr->names[index], sem_type) // column name
              ),
              NULL // end of argument list
            )
          )
        )
      ),
      // AST for: AS column_name
      // This provides the alias for the extracted column value
      new_ast_opt_as_alias(
        new_str_or_qstr(sptr->names[index], sem_type) // column name as alias
      )
    ),
    // Recursively build the rest of the SELECT expression list for remaining columns
    // This creates the comma-separated chain: expr1, expr2, expr3, ...
    rewrite_backed_expr_list(info, index + 1)
  );

  return result;
}

// Once we have a valid backed table we need to create a shared fragment that access it
// so that we can use it when rewriting select statements.  To do this we make the create
// proc statement out of thin air and then parse it, adding it to the set of shared fragments.
// The generated procedure looks like this:
//
// [[shared_fragment]]
// CREATE PROC _backed ()
// BEGIN
//   SELECT
//     cql_blob_get(T.k, backed.id) AS id,
//     cql_blob_get(T.v, backed.t) AS t,
//     cql_blob_get(T.v, backed.v) AS v
//   FROM backing AS T;
// END;
//
// This is a fixed shape with just names plugged in except for the expression list
// which is generated by a helper above.
// Here the table "backing" has two blob columns "k" and "v" for the key and value storage.
cql_noexport void rewrite_shared_fragment_from_backed_table(ast_node *_Nonnull backed_table) {
  EXTRACT_MISC_ATTRS(backed_table, misc_attrs);

  AST_REWRITE_INFO_SET(backed_table->lineno, backed_table->filename);

  Contract(is_ast_create_table_stmt(backed_table));
  EXTRACT_NOTNULL(create_table_name_flags, backed_table->left);
  EXTRACT_STRING(backed_table_name, create_table_name_flags->right);
  CSTR proc_name = dup_printf("_%s", backed_table_name);

  CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
  Invariant(backing_table_name); // already validated
  ast_node *backing_table = find_table_or_view_even_deleted(backing_table_name);
  Invariant(backing_table); // already validated
  sem_struct *sptr_backing = backing_table->sem->sptr;
  Invariant(sptr_backing); // table must have a sem_struct

  // figure out the column order of the key and value columns in the backing store
  // the options are "key, value" or "value, key"
  sem_t sem_type = sptr_backing->semtypes[0];
  bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Set up the information structure for generating blob extraction expressions
  // This determines which backing table columns contain the key vs value blobs
  backed_expr_list_info info = {
    .backed_table = backed_table,
    .key = sptr_backing->names[!is_key_first], // if the order is kv then the key is column 0, else 1
    .sem_type_key = sptr_backing->semtypes[!is_key_first],
    .val = sptr_backing->names[is_key_first], // if the order is kv then the key is column 0, else 1
    .sem_type_val = sptr_backing->semtypes[is_key_first], // if the order is kv then the value is colume 1, else 0
  };

  // Generate the SELECT expression list that extracts all backed table columns from blobs
  // This creates: cql_blob_get(...) AS col1, cql_blob_get(...) AS col2, ...
  ast_node *select_expr_list = rewrite_backed_expr_list(&info, 0);

  // AST for: SELECT rowid, cql_blob_get(...) AS col1, ... FROM backing_table T WHERE cql_blob_get_type(...) = type_hash;
  // This creates a complete SELECT statement that reads from the blob backing store and reconstructs the backed table rows
  ast_node *select_stmt =
    new_ast_select_stmt(
      new_ast_select_core_list(
        new_ast_select_core(
          NULL, // no select options (DISTINCT, etc.)
          new_ast_select_expr_list_con(
            // AST for: SELECT rowid, col1, col2, ...
            // This builds the complete SELECT list starting with rowid, followed by extracted columns
            new_ast_select_expr_list(
              // AST for: rowid (first column in result set)
              new_ast_select_expr(
                new_ast_str("rowid"), // rowid expression
                NULL // no alias needed
              ),
              select_expr_list // followed by the blob-extracted columns
            ),
            // AST for: FROM backing_table T WHERE ... GROUP BY ... HAVING ...
            // This specifies the data source and filtering for the backed table reconstruction
            new_ast_select_from_etc(
              // AST for: FROM backing_table T
              // This creates the FROM clause referencing the blob backing store with alias T
              new_ast_table_or_subquery_list(
                new_ast_table_or_subquery(
                  new_maybe_qstr(backing_table_name), // backing table name
                  new_ast_opt_as_alias(new_ast_str("T")) // alias "T" for shorter references
                ),
                NULL // no additional tables
              ),
              // AST for: WHERE cql_blob_get_type(backed_table_name, T.key_column) = type_hash
              // This filters to only rows that match the backed table's type signature
              new_ast_select_where(
                new_ast_opt_where(
                  // AST for: cql_blob_get_type(...) = type_hash
                  // This equality comparison ensures we only get rows for this specific backed table type
                  new_ast_eq(
                    // AST for: cql_blob_get_type(table_name, T.key_column)
                    // This function call extracts the type identifier from the key blob
                    new_ast_call(
                      new_ast_str("cql_blob_get_type"), // function name
                      new_ast_call_arg_list( // argument list
                        new_ast_call_filter_clause(NULL, NULL), // no filter clause
                        new_ast_arg_list( // first argument: table name
                          new_maybe_qstr(backed_table_name),
                          new_ast_arg_list( // second argument: T.key_column
                            new_ast_dot(
                              new_ast_str("T"), // table alias
                              new_str_or_qstr(info.key, info.sem_type_key) // key column name
                            ),
                            NULL // end of argument list
                          )
                        )
                      )
                    ),
                    // AST for: type_hash (the expected type hash for this backed table)
                    new_ast_num(NUM_LONG, gen_type_hash(backed_table))
                  )
                ),
                // AST for: GROUP BY ... HAVING ... (empty in this case)
                new_ast_select_groupby(
                  NULL, // no GROUP BY clause
                  new_ast_select_having(
                    NULL, // no HAVING clause
                    NULL
                  )
                )
              )
            )
          )
        ),
        NULL // no additional SELECT cores (no UNION, etc.)
      ),
      // AST for: ORDER BY ... LIMIT ... OFFSET ... (all empty)
      new_ast_select_orderby(
        NULL, // no ORDER BY clause
        new_ast_select_limit(
          NULL, // no LIMIT clause
          new_ast_select_offset(
            NULL, // no OFFSET clause
            NULL
          )
        )
      )
    );

  // AST for: [[cql:shared_fragment]] CREATE PROC _table_name() BEGIN SELECT ... END;
  // This creates a complete procedure declaration with the shared_fragment attribute
  // The procedure will be used as a CTE in queries that reference the backed table
  ast_node *stmt_and_attr =
    new_ast_stmt_and_attr(
      // AST for: [[cql:shared_fragment]]
      // This attribute marks the procedure as a shared fragment that can be used in CTEs
      new_ast_misc_attrs(
        new_ast_misc_attr(
          new_ast_dot( // cql.shared_fragment attribute
            new_ast_str("cql"),
            new_ast_str("shared_fragment")
          ),
          NULL // no attribute value
        ),
        NULL // no additional attributes
      ),
      // AST for: CREATE PROC _table_name() BEGIN SELECT ... END
      // This creates the procedure that implements the backed table access
      // Corresponds to: CREATE PROCEDURE name '(' params ')' BEGIN_ opt_stmt_list END in cql.y
      new_ast_create_proc_stmt(
        new_ast_str(proc_name), // procedure name: _table_name (with leading underscore)
        new_ast_proc_params_stmts(
          NULL, // no parameters
          new_ast_stmt_list( // procedure body
            select_stmt, // the SELECT statement we built above
            NULL // no additional statements
          )
        )
      )
    );

  // stdout the rewrite for debugging if needed
  // gen_stmt_list_to_stdout(new_ast_stmt_list(stmt_and_attr, NULL));

  AST_REWRITE_INFO_RESET();

  // analysis can't fail, there's nothing to go wrong, all names already checked
  // note that semantic analysis expects to start at the statement not the attributes
  // so we skip into the statement.
  sem_one_stmt(stmt_and_attr->right);
  Invariant(!is_error(stmt_and_attr->right));
}

// Here we find all of the backed tables that have been mentioned in this statement
// from the backed tables list and produce a chain of CTEs that define them.  This
// can then be linked into some other statement (see below)
//
// Note that walking the list in this way effectively reverses the order the items
// will appear in the  CTE list.
//
// If you're thinking, just a hold it, what if there's a reference to the base
// table for say an insert statement or something, won't the CTE we add for
// that table be hiding the table we are trying to insert into?  But no, for
// the main table if it is backed is necessarily renamed to be the backing table
// so by the time SQLite sees it there will be possibly many CTEs for backed
// tables that were mentioned, including the main table, but the main table
// is gone, replaced by the backing table. This leaves the main table name
// free to be used in the statement by a CTE like usual.
static void rewrite_backed_table_ctes(
  list_item *backed_tables_list,
  ast_node **pcte_tables,
  ast_node **pcte_tail)
{
  // Use a symbol table to track which backed tables we've already processed
  // This prevents creating duplicate CTEs for the same backed table
  symtab *backed = symtab_new();

  ast_node *backed_cte_tables = NULL;
  ast_node *cte_tail = NULL;

  // Process each backed table reference in the list
  for (list_item *item = backed_tables_list; item; item = item->next) {
    // Track whether we added a CTE for this item
    bool_t added = false;

    if (is_ast_cte_table(item->ast)) {
      // If it's already a CTE table, just add it directly to the list
      // AST for: cte_table, cte_table, ...
      // This builds the comma-separated CTE table list
      // Corresponds to: cte_table ',' cte_tables in cql.y grammar
      backed_cte_tables = new_ast_cte_tables(item->ast, backed_cte_tables);
      added = true;
    }
    else {
      // Extract the backed table name from table_or_subquery reference
      EXTRACT_NOTNULL(table_or_subquery, item->ast);
      EXTRACT_NAME_AST(backed_table_name_ast, table_or_subquery->left);
      EXTRACT_STRING(backed_table_name, backed_table_name_ast);
      CSTR backed_proc_name = dup_printf("_%s", backed_table_name);

      // Only create a CTE if we haven't seen this backed table before
      if (symtab_add(backed, backed_table_name, NULL)) {
        added = true;
        // AST for: table_name(*) AS (CALL _table_name()), ...
        // This creates a CTE that calls the generated shared fragment procedure
        // Corresponds to: cte_table ',' cte_tables in cql.y grammar
        backed_cte_tables = new_ast_cte_tables(
          // AST for: table_name(*) AS (CALL _table_name())
          // This creates a single CTE table entry
          // Corresponds to: cte_decl AS '(' shared_cte ')' in cql.y grammar
          new_ast_cte_table(
            // AST for: table_name(*)
            // This declares the CTE with the backed table name and all columns
            new_ast_cte_decl(
              new_maybe_qstr(backed_table_name), // CTE name (same as backed table name)
              new_ast_star() // all columns (*)
            ),
            // AST for: CALL _table_name()
            // This creates the shared CTE that calls the generated procedure
            // Corresponds to: call_stmt in shared_cte rule
            new_ast_shared_cte(
              new_ast_call_stmt(
                new_ast_str(backed_proc_name), // procedure name: _table_name
                NULL // no arguments
              ),
              NULL // no USING clause
            )
          ),
          backed_cte_tables // link to previous CTEs in the list
        );
      }
    }

    // Keep track of the tail of the CTE list for linking purposes
    if (added && cte_tail == NULL) {
      cte_tail = backed_cte_tables;
    }
  }

  // Return the built CTE tables list and tail pointer
  *pcte_tail = cte_tail;
  *pcte_tables = backed_cte_tables;

  symtab_delete(backed);
}

// Transforms SQL statements to include Common Table Expressions (CTEs) for backed table access
// This function wraps statements with WITH clauses that define backed table CTEs, enabling
// transparent access to blob-stored data through generated shared fragment procedures.
//
// The transformation enables statements like:
// SELECT * FROM backed_table WHERE pk = 1
// To be processed as:
// WITH backed_table AS (SELECT ... FROM _backed_table()) SELECT * FROM backed_table WHERE pk = 1
//
// This is the core mechanism that makes backed tables work transparently. The CTEs effectively
// replace backed table references with calls to their generated shared fragment procedures,
// which handle the complex blob extraction and reconstruction logic automatically.
//
// The function handles multiple statement types by detecting existing WITH clauses:
// 1. If statement already has WITH: Prepends backed table CTEs to existing CTE list
// 2. If no WITH clause: Creates new WITH clause and converts statement type
//
// Statement type conversions performed:
// - select_stmt → with_select_stmt
// - insert_stmt → with_insert_stmt
// - update_stmt → with_update_stmt
// - delete_stmt → with_delete_stmt
// - upsert_stmt → with_upsert_stmt
//
// The function constructs AST nodes using these patterns from cql.y:
// - with_select_stmt: WITH cte_tables select_stmt
// - with_insert_stmt: WITH cte_tables insert_stmt
// - cte_tables: cte_tables ',' cte_table | cte_table
// - cte_table: ID '(' opt_name_list ')' AS '(' select_stmt ')'
//
// This enables seamless backed table integration across all SQL statement types.
//
// This is the magic, we have tracked the backed tables so now we can insert calls to
// the generated shared fragments (see above) for each such table.  Once we've done that,
// the select will "just work." because the backed table has been aliased by a correct CTE.
cql_noexport void rewrite_statement_backed_table_ctes(
  ast_node *_Nonnull stmt,
  list_item *_Nonnull backed_tables_list)
{
  Contract(stmt);
  Contract(backed_tables_list);

  ast_node *backed_cte_tables = NULL;
  ast_node *cte_tail = NULL;

  rewrite_backed_table_ctes(backed_tables_list, &backed_cte_tables, &cte_tail);

  Invariant(cte_tail);
  Invariant(backed_cte_tables);

  if (is_ast_with(stmt->left)) {
    // add the backed table CTEs to the front of the list
    EXTRACT(with, stmt->left);
    EXTRACT(cte_tables, with->left);
    ast_set_right(cte_tail, cte_tables);
    ast_set_left(with, backed_cte_tables);
  }
  else {
    // preserve the old (left, right) in a nested node and swap in the "with" node
    ast_set_right(stmt, new_ast(stmt->type, stmt->left, stmt->right));
    ast_set_left(stmt, new_ast_with(backed_cte_tables));

    // map the node type to the with form
    if (stmt->type == k_ast_select_stmt) {
      stmt->type = k_ast_with_select_stmt;
    }
    else if (stmt->type == k_ast_upsert_stmt) {
      stmt->type = k_ast_with_upsert_stmt;
    }
    else if (stmt->type == k_ast_update_stmt) {
      stmt->type = k_ast_with_update_stmt;
    }
    else if (stmt->type == k_ast_delete_stmt) {
      stmt->type = k_ast_with_delete_stmt;
    }
    else {
      // this is all that's left
      Invariant(stmt->type == k_ast_insert_stmt);
      stmt->type = k_ast_with_insert_stmt;
    }
  }

  // stdout the rewrite for debugging if needed
  // printf("------------\n");
  // gen_stmt_list_to_stdout(new_ast_stmt_list(stmt, NULL));
  // printf("------------\n\n\n\n");
}

// Transforms SELECT statements to enable transparent backed table access through CTEs
// This function handles the complete rewrite process for SELECT statements that reference
// backed tables, converting them into WITH statements that include the necessary CTEs
// for blob-based data access.
//
// Transforms: SELECT col1, col2 FROM backed_table WHERE condition
// Into: WITH backed_table AS (SELECT ... FROM _backed_table())
//       SELECT col1, col2 FROM backed_table WHERE condition
//
// The rewrite process involves two main phases:
// 1. CTE Integration: Add Common Table Expressions for all referenced backed tables
// 2. Semantic Analysis: Re-analyze the transformed statement to validate correctness
//
// This is the simplest backed table rewrite case because SELECT statements don't modify
// data - they only need to read from the blob storage through the generated shared
// fragment procedures. The complexity is handled by rewrite_statement_backed_table_ctes()
// which manages WITH clause construction and statement type conversion.
//
// The backed table CTEs replace table references with procedure calls that:
// - Extract data from key/value blob columns in the backing table
// - Reconstruct the original table structure using cql_blob_get() calls
// - Filter results using proper type hash validation
// - Present a transparent interface matching the original table schema
//
// After CTE integration, the statement undergoes semantic analysis to ensure:
// - Column references resolve correctly through the CTE definitions
// - Type checking works with the reconstructed column types
// - JOIN operations function properly with backed table CTEs
// - WHERE clauses can reference backed table columns normally
//
// This enables backed tables to work seamlessly in complex queries without requiring
// users to understand the underlying blob storage implementation.
cql_noexport void rewrite_select_for_backed_tables(
  ast_node *_Nonnull stmt,
  list_item *_Nonnull backed_tables_list)
{
  Contract(is_ast_select_stmt(stmt) || is_ast_with_select_stmt(stmt));
  Contract(backed_tables_list);

  AST_REWRITE_INFO_SET(stmt->lineno, stmt->filename);

  rewrite_statement_backed_table_ctes(stmt, backed_tables_list);

  AST_REWRITE_INFO_RESET();

  sem_any_row_source(stmt);
}

// As we do our recursion creating the fields for blob creation we flow this state
typedef struct create_blob_args_info {
  // inputs to recursion (same at every level)
  ast_node *backed_table;
  bool_t for_key;
  ast_node *name_list;

} create_blob_args_info;

// This walks the name list and generates either the args for the key or the args for the value
// both are just going to be V.col_name from the _vals alias and the backed table.column.
// The info we need to flows in the info variable.
static ast_node *rewrite_create_blob_args(create_blob_args_info *info) {
  Invariant(info->backed_table->sem);
  Invariant(info->backed_table->sem->table_info);
  Invariant(info->backed_table->sem->sptr);

  ast_node *name_list = info->name_list;
  table_node *table_info = info->backed_table->sem->table_info;
  sem_struct *sptr = info->backed_table->sem->sptr;
  CSTR backed_table_name = sptr->struct_name;
  symtab *seen_names = symtab_new();
  sem_t backed_table_sem_type = info->backed_table->sem->sem_type;

  // Get default values for columns that may not be explicitly provided
  symtab *def_values = find_default_values(sptr->struct_name);
  Invariant(def_values); // table name known to be good

  int16_t col_count;
  int16_t *cols;

  // Determine which columns we need based on whether we're building key or value blob args
  // Key blobs contain primary key columns, value blobs contain non-key columns
  if (info->for_key) {
    col_count = table_info->key_count;
    cols = table_info->key_cols;
  }
  else {
    col_count = table_info->value_count;
    cols = table_info->value_cols;
  }

  // Build a symbol table of explicitly provided column names
  // This lets us distinguish between columns with explicit values vs. those needing defaults
  for (ast_node *item = name_list; item ; item = item->right) {
    EXTRACT_STRING(name, item->left);
    symtab_add(seen_names, name, NULL);
  }

  // Create a dummy root node to simplify list construction (avoids null tail handling)
  ast_node *root = new_ast_arg_list(NULL, NULL);
  ast_node *tail = root;

  // Generate blob creation arguments in the correct column order
  // Key columns must be in exact order since their position determines the blob structure
  // Value columns also need consistent ordering for proper blob reconstruction
  for (int16_t i = 0; i < col_count; i++) {
    // Get the column index from the pre-computed column order array
    int16_t icol = cols[i];
    Invariant(icol >= 0);
    Invariant((uint32_t)icol < sptr->count);
    CSTR name = sptr->names[icol];
    sem_t sem_type = sptr->semtypes[icol];
    ast_node *name_ast = new_str_or_qstr(name, sem_type);

    ast_node *new_item = NULL;
    symtab_entry *entry = NULL;

    // Handle explicitly provided columns - these come from the INSERT values
    if (symtab_find(seen_names, name)) {
      // AST for: V.column_name, table_name.column_name
      // This creates a pair of arguments for cql_blob_create:
      // - V.column_name: the actual value from the VALUES clause (aliased as V)
      // - table_name.column_name: the column specification for type/metadata
      new_item =
        new_ast_arg_list(
          // AST for: V.column_name (the value to store in the blob)
          new_ast_dot(new_ast_str("V"), ast_clone_tree(name_ast)),
          new_ast_arg_list(
            // AST for: table_name.column_name (the column specification)
            new_ast_dot(new_str_or_qstr(backed_table_name, backed_table_sem_type), name_ast),
            NULL // end of this argument pair
          )
        );
    }
    // Handle columns with default values - these weren't explicitly provided in INSERT
    else if ((entry = symtab_find(def_values, name))) {
      // there is a default value, copy it!
      // when we copy the tree we will use the file and line numbers from the original
      // so we temporarily discard whatever file and line number we are using right now

      // this can happen inside of other rewrites so we nest it
      AST_REWRITE_INFO_SAVE();
        ast_node *_Nonnull node = entry->val;
        ast_node *def_value;

        Contract(is_ast_num(node) || is_ast_str(node));

        // Create a new AST node for the default value with proper source location info
        AST_REWRITE_INFO_SET(node->lineno, node->filename);
        if (is_ast_num(node)) {
          // AST for: numeric_literal (default numeric value)
          EXTRACT_NUM_TYPE(num_type, node);
          EXTRACT_NUM_VALUE(val, node);
          def_value = new_ast_num(num_type, val);
        }
        else {
          // AST for: string_literal (default string value)
          EXTRACT_STRING(value, node);
          def_value = new_maybe_qstr(value);
        }
        AST_REWRITE_INFO_RESET();

        Invariant(def_value);

      AST_REWRITE_INFO_RESTORE();

      // AST for: default_value, table_name.column_name
      // This creates a pair of arguments for cql_blob_create using the default value
      // - default_value: the literal default value (number or string)
      // - table_name.column_name: the column specification for type/metadata
      new_item = new_ast_arg_list(
        def_value, // the default value literal
        new_ast_arg_list(
          // AST for: table_name.column_name (the column specification)
          new_ast_dot(new_maybe_qstr(backed_table_name), name_ast),
          NULL // end of this argument pair
        )
      );
    }

    // Add the argument pair to the list if we created one
    // Some columns might be missing (especially in value blobs where not all columns are required)
    // The dummy root node eliminates null pointer handling in the list construction
    if (new_item) {
      // Link the new argument pair to the end of the current list
      ast_set_right(tail, new_item);

      // Advance the tail pointer to the end of the newly added arguments
      // Each new_item contains a pair of arguments, so we need to find the true end
      while (tail->right) {
        tail = tail->right;
      }
    }
  }

  symtab_delete(seen_names);

  // Return the argument list, skipping the dummy root node we used for construction
  // The result is: value1, spec1, value2, spec2, ... valueN, specN
  // Where each value is either V.column or a default literal
  // And each spec is table_name.column for type/metadata information
  return root->right;
}

// This walks the name list and generates either the key create call or the
// value create call. This is the fixed part of the call.
static ast_node *rewrite_blob_create(
  bool_t for_key,
  ast_node *backed_table,
  ast_node *name_list)
{
  // Set up the context information for generating blob creation arguments
  // The rewrite_create_blob_args function will use this to determine which columns
  // to include and how to generate the value/specification argument pairs
  create_blob_args_info info = {
    .for_key = for_key, // true = key blob, false = value blob
    .backed_table = backed_table, // the backed table schema
    .name_list = name_list // columns explicitly provided in INSERT
  };

  // Clone the table name AST for use in the function call
  // This preserves any qualification (schema.table) that might be present
  ast_node *table_name_ast = ast_clone_tree(sem_get_name_ast(backed_table));

  // AST for: cql_blob_create(table_name, value1, spec1, value2, spec2, ...)
  // This generates the function call that creates a blob from column values
  // The blob will contain either key columns (for key blob) or value columns (for value blob)
  return new_ast_call(
    new_ast_str("cql_blob_create"), // function name
    new_ast_call_arg_list( // argument list structure
      new_ast_call_filter_clause(NULL, NULL), // no filter clause
      new_ast_arg_list(
        table_name_ast, // first argument: table name for type information
        // Generate the remaining arguments: value/spec pairs for each column
        // This creates: value1, spec1, value2, spec2, ... for all relevant columns
        rewrite_create_blob_args(&info)
      )
    )
  );
}

// create the wrapper for a cql_blob_get call for the given blob, backed table
// name and column name
static ast_node *cql_blob_get_call (
  CSTR blob_field,
  sem_t sem_type_blob,
  CSTR backed_table,
  CSTR col,
  sem_t sem_type_col)
{
  // AST for: cql_blob_get(blob_field, backed_table.column)
  // This creates a function call that extracts a specific column value from a blob
  // Used when reading from backed tables to reconstruct individual column values
  return new_ast_call(
    new_ast_str("cql_blob_get"), // function name
    new_ast_call_arg_list( // argument list structure
      new_ast_call_filter_clause(NULL, NULL), // no filter clause
      new_ast_arg_list(
        // First argument: the blob field containing the serialized data
        // This is either a key blob column or value blob column from the backing table
        new_str_or_qstr(blob_field, sem_type_blob),
        new_ast_arg_list(
          // Second argument: backed_table.column specification
          // This tells cql_blob_get which column to extract from the blob
          // The table.column format provides type and metadata information
          new_ast_dot(
            new_maybe_qstr(backed_table), // backed table name
            new_str_or_qstr(col, sem_type_col) // column name to extract
          ),
          NULL // end of argument list
        )
      )
    )
  );
}


// create the wrapper for a cql_blob_get call for the given blob, backed table
// name and column name, this is almost the same as the above but we use
// the excluded name prefix to get the key or value field.  So it looks like
// cql_blob_get(excluded.key, backed_table.col)
static ast_node *cql_blob_get_call_with_excluded (
  CSTR blob_field,
  sem_t sem_type_blob,
  CSTR backed_table,
  CSTR col,
  sem_t sem_type_col)
{
  // AST for: cql_blob_get(excluded.blob_field, backed_table.column)
  // This creates a function call that extracts column values from EXCLUDED row blobs
  // Used in ON CONFLICT clauses where 'excluded' refers to the row that would have been inserted
  // The EXCLUDED pseudo-table contains the blob data from the failed INSERT attempt
  return new_ast_call(
    new_ast_str("cql_blob_get"), // function name
    new_ast_call_arg_list( // argument list structure
      new_ast_call_filter_clause(NULL, NULL), // no filter clause
      new_ast_arg_list(
        // First argument: excluded.blob_field
        // This references the blob column from the EXCLUDED pseudo-table
        // EXCLUDED contains the row data that caused the conflict in INSERT OR REPLACE/UPSERT
        new_ast_dot(
          new_ast_str("excluded"), // EXCLUDED pseudo-table reference
          new_str_or_qstr(blob_field, sem_type_blob) // key or value blob field name
        ),
        new_ast_arg_list(
          // Second argument: backed_table.column specification
          // This tells cql_blob_get which column to extract from the excluded blob
          // Same format as regular blob_get but operates on conflict resolution data
          new_ast_dot(
            new_maybe_qstr(backed_table), // backed table name
            new_str_or_qstr(col, sem_type_col) // column name to extract
          ),
          NULL // end of argument list
        )
      )
    )
  );
}


// Several args need to flow during the recursion so we bundle them into a struct
// so that we can flow the pointer instead of all these arguments
typedef struct update_rewrite_info {
  CSTR backing_key;
  sem_t sem_type_key;
  CSTR backing_val;
  sem_t sem_type_val;
  bool_t for_key;
  ast_node *backed_table;
} update_rewrite_info;

// Recursively traverses AST nodes to find and rewrite backed table column references
// Converts column references like "backed_table.column" into blob extraction calls
// like "cql_blob_get(blob_field, backed_table.column)"
static void rewrite_blob_column_references(
  update_rewrite_info *info,
  ast_node *ast)
{
  // Process leaf nodes that represent column names or qualified column references
  // These are the actual column references that need to be converted to blob extraction calls
  if (is_ast_str(ast) || is_ast_dot(ast)) {
    // Check if this node represents a backed table column reference
    // The semantic analysis phase marks backed table columns with backed_table info
    if (ast->sem && ast->sem->backed_table) {
      // Get the backed table schema to determine column properties (key vs value)
      // Primary key info doesn't flow through expression trees, so we look it up directly
      sem_struct *sptr_backed = info->backed_table->sem->sptr;
      Invariant(ast->sem);
      Invariant(ast->sem->name);

      bool excluded = false;

      // Handle the special case of EXCLUDED pseudo-table references in UPSERT statements
      // EXCLUDED.column references need to extract from excluded blob data, not current table data
      if (is_ast_dot(ast) && is_ast_str(ast->left)) {
        // Check if this is an "excluded.column" reference for conflict resolution
        // In UPSERT statements, "excluded" refers to the row that would have been inserted
        // This requires using excluded.blob_field instead of regular blob_field
        EXTRACT_STRING(sc, ast->left);
        if (!strcmp(sc, "excluded")) {
          excluded = true;
        }
      }

      // Look up the column in the backed table schema to get its semantic type
      // We need this to determine if it's a key column (primary key) or value column
      int32_t i = find_col_in_sptr(sptr_backed, ast->sem->name);
      Invariant(i >= 0); // the column for sure exists, it's already been checked
      sem_t sem_type = sptr_backed->semtypes[i];

      // Determine which blob column contains this data (key blob or value blob)
      // Key columns are stored in the key blob, other columns in the value blob
      bool_t is_key_column = is_primary_key(sem_type) || is_partial_pk(sem_type);
      CSTR blob_field = is_key_column ? info->backing_key : info->backing_val;
      sem_t blob_type = is_key_column ? info->sem_type_key : info->sem_type_val;

      // Generate the appropriate cql_blob_get() call based on context
      // Normal case: cql_blob_get(blob_field, backed_table.column)
      // EXCLUDED case: cql_blob_get(excluded.blob_field, backed_table.column)
      ast_node *new = !excluded ?
        cql_blob_get_call(
          blob_field,
          blob_type,
          ast->sem->backed_table, // this is a direct reference to the backed table
          ast->sem->name,
          ast->sem->sem_type) :
        cql_blob_get_call_with_excluded( // use excluded.(k/v) for the blob
          blob_field,
          blob_type,
          sptr_backed->struct_name, // get the backed table directly from struct name
          ast->sem->name,
          ast->sem->sem_type);

      // Replace the original column reference with the blob extraction call
      // This transforms the AST in-place, converting column refs to function calls
      ast->type = new->type;
      ast_set_left(ast, new->left);
      ast_set_right(ast, new->right);
    }
    return;
  }

  // Recursively process child nodes to find all column references in the expression tree
  // This ensures we rewrite all backed table column references, no matter how deeply nested
  if (ast_has_left(ast)) {
    rewrite_blob_column_references(info, ast->left);
  }
  if (ast_has_right(ast)) {
    rewrite_blob_column_references(info, ast->right);
  }
}

// Public interface for rewriting backed table column references in any AST subtree
// This function sets up the context and calls the recursive rewriter to convert
// all backed table column references into blob extraction calls
cql_noexport void rewrite_backed_column_references_in_ast(
  ast_node *_Nonnull root,
  ast_node *_Nonnull backed_table)
{
  // Extract the backing table information from the backed table's attributes
  // The @attribute(cql:backed_by="backing_table") tells us which physical table stores the blobs
  EXTRACT_MISC_ATTRS(backed_table, misc_attrs);

  CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
  Invariant(backing_table_name); // already validated
  ast_node *backing_table = find_table_or_view_even_deleted(backing_table_name);
  Invariant(backing_table); // already validated
  sem_struct *sptr_backing = backing_table->sem->sptr;
  Invariant(sptr_backing); // table must have a sem_struct

  // Determine the column layout of the backing table (key-first or value-first)
  // Backing tables have exactly two columns: one for key blob, one for value blob
  // The order can be either (key, value) or (value, key) depending on table definition
  sem_t sem_type = sptr_backing->semtypes[0];
  bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Set up the rewrite context with backing table column information
  // This tells the rewriter which blob columns to use for key vs value data
  update_rewrite_info info = {
   .backing_key = sptr_backing->names[!is_key_first], // if the order is kv then the key is column 0, else 1
   .sem_type_key = sptr_backing->semtypes[!is_key_first],
   .backing_val = sptr_backing->names[is_key_first], // if the order is vk then the value is column 0, else 1
   .sem_type_val = sptr_backing->semtypes[is_key_first],
   .backed_table = backed_table, // the logical backed table schema
   .for_key = false, // this field is ignored in this context (used only for update operations)
  };

  // Handle nested rewrite contexts safely - this can be called during other rewrites
  // The AST_REWRITE_INFO stack allows us to nest rewrite operations without losing context
  // This is particularly important for UPSERT operations which involve multiple rewrite phases
  AST_REWRITE_INFO_SAVE();
  AST_REWRITE_INFO_SET(root->lineno, root->filename);
    // Recursively traverse the AST and rewrite all backed table column references
    // This converts expressions like "backed_table.column" into "cql_blob_get(blob_field, backed_table.column)"
    rewrite_blob_column_references(&info, root);
  AST_REWRITE_INFO_RESET();
  AST_REWRITE_INFO_RESTORE();
}

// This walks the update list and generates either the args for the key or the
// args for the value the values come from the assignment in the update entry list
// This function recursively processes UPDATE SET clauses for backed tables, filtering
// and transforming column assignments into blob update arguments. It builds AST
// structures for cql_blob_update() calls by separating key and value columns.
//
// For backed tables like: CREATE TABLE backed(pk INT PRIMARY KEY, x TEXT, y REAL) USING blob_storage
// An UPDATE like: UPDATE backed SET x='new', y=42.0 WHERE pk=1
// Gets transformed into separate key and value blob updates.
//
// The function constructs AST nodes using these patterns from cql.y:
// - arg_list: expr_list  (for function call arguments)
// - expr_list: expr_list ',' expr | expr
// - member_access: expr '.' IDENTIFIER
//
// Returns arg_list AST containing:
//   [new_value_expr, backed_table.column_name, ...recursive_args...]
static ast_node *rewrite_update_blob_args(
  update_rewrite_info *info,
  ast_node *update_list)
{
  if (!update_list) {
    return NULL;
  }

  Contract(is_ast_update_list(update_list));

  // Extract column assignment: column_name = new_value_expr
  EXTRACT_NOTNULL(update_entry, update_list->left);
  EXTRACT_STRING(name, update_entry->left); // Column being updated
  EXTRACT_ANY_NOTNULL(expr, update_entry->right); // New value expression

  // Look up column metadata in backed table schema
  sem_struct *sptr = info->backed_table->sem->sptr;
  int32_t icol = sem_column_index(sptr, name);
  Invariant(icol >= 0); // must be valid name, already checked!
  sem_t sem_type = sptr->semtypes[icol];
  bool_t is_key = is_primary_key(sem_type) || is_partial_pk(sem_type);
  CSTR backed_table_name = sptr->struct_name;

  // Only include this column if it matches the current blob type (key vs value)
  if (is_key == info->for_key) {
    // Rewrite any column references within the new value expression
    rewrite_blob_column_references(info, expr);

    // Build nested arg_list AST: new_ast_arg_list(expr, new_ast_arg_list(table.col, rest))
    // This creates: expr, backed_table.column_name, [additional pairs...]
    // Following cql.y arg_list: arg_list ',' expr pattern
    return new_ast_arg_list(
      expr, // New value expression
      new_ast_arg_list(
        new_ast_dot(new_maybe_qstr(backed_table_name), new_str_or_qstr(name, sem_type)), // table.column reference
        rewrite_update_blob_args(info, update_list->right) // Process remaining columns recursively
      )
    );
  }
  else {
    // Skip this column (wrong type for current blob), process rest of list
    return rewrite_update_blob_args(info, update_list->right);
  }
}

// This function generates cql_blob_update() function call AST nodes for backed table
// UPDATE operations. It constructs either key blob updates or value blob updates
// depending on the for_key parameter.
//
// For a backed table like: CREATE TABLE backed(pk INT PRIMARY KEY, x TEXT, y REAL) USING blob_storage
// With backing table: CREATE TABLE backing(k BLOB, v BLOB)
// An UPDATE backed SET x='new', y=42.0 WHERE pk=1 becomes:
//   UPDATE backing SET v = cql_blob_update(v, 'new', backed.x, 42.0, backed.y) WHERE k = cql_blob_update(k, 1, backed.pk)
//
// The function constructs AST nodes using these patterns from cql.y:
// - call: name '(' arg_list ')'  (function call)
// - call_arg_list: call_filter_clause arg_list
// - arg_list: arg_list ',' expr | expr
//
// Returns call AST: cql_blob_update(blob_column, value1, column1, value2, column2, ...)
static ast_node *rewrite_blob_update(
  bool_t for_key,
  sem_struct *sptr_backing,
  ast_node *backed_table,
  ast_node *update_list)
{
  // Determine backing table column layout (key-value or value-key order)
  sem_t sem_type = sptr_backing->semtypes[0];
  bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Set up rewrite context with backing table schema information
  update_rewrite_info info = {
   .backing_key = sptr_backing->names[!is_key_first], // if the order is kv then the key is column 0, else 1
   .sem_type_key = sptr_backing->semtypes[!is_key_first],
   .backing_val = sptr_backing->names[is_key_first],
   .sem_type_val = sptr_backing->semtypes[is_key_first],
   .for_key = for_key,
   .backed_table = backed_table,
  };

  // Build argument list containing alternating new_values and column_references
  // Only includes columns matching the requested blob type (key vs value)
  ast_node *arg_list = rewrite_update_blob_args(&info, update_list);
  if (!arg_list) {
    // No columns of this type are being updated
    return NULL;
  }

  // Select appropriate blob column (key or value) from backing table
  CSTR blob_name = for_key ? info.backing_key : info.backing_val;
  sem_t blob_type = for_key ? info.sem_type_key : info.sem_type_val;
  ast_node *blob_val = new_str_or_qstr(blob_name, blob_type);

  Contract(is_ast_update_list(update_list));

  // Construct function call AST: cql_blob_update(blob_column, value_pairs...)
  // Following cql.y call: name '(' arg_list ')' pattern
  return new_ast_call(
    new_ast_str("cql_blob_update"), // Function name
    new_ast_call_arg_list(
      new_ast_call_filter_clause(NULL, NULL), // No FILTER clause
      new_ast_arg_list(
        blob_val, // First arg: blob column to update
        arg_list // Remaining args: value, column pairs
      )
    )
  );
}

// This function transforms an INSERT VALUES list into a SELECT VALUES statement
// for backed table processing. It wraps raw value tuples in a complete SELECT
// statement that can be used in CTEs and JOIN operations.
//
// Transforms: VALUES (1, 'text', 3.14), (2, 'more', 2.71)
// Into: SELECT * FROM (VALUES (1, 'text', 3.14), (2, 'more', 2.71))
//
// This enables backed table INSERT rewriting where we need to:
// 1. Extract values from INSERT statement
// 2. Process them through blob creation functions
// 3. Insert results into backing table
//
// The function constructs AST nodes using these patterns from cql.y:
// - select_stmt: select_core_list select_orderby
// - select_core_list: select_core_list compound_operator select_core | select_core
// - select_core: SELECT select_expr_list table_or_subquery_list where_clause group_by having select_window
//              | SELECT VALUES '(' values_list ')'
// - values: '(' insert_list ')' values | '(' insert_list ')'
//
// Returns complete SELECT statement AST with embedded VALUES claus
//
// This helper creates the select list we will need to get the values out from
// the statement that was the insert list (it could be values or a select
// statement)
static ast_node *rewrite_insert_list_as_select_values(
  ast_node *insert_list)
{
  // Build complete SELECT VALUES statement structure
  // Following cql.y select_stmt: select_core_list select_orderby pattern
  return new_ast_select_stmt(
    new_ast_select_core_list(
      new_ast_select_core(
        new_ast_select_values(), // SELECT VALUES keyword
        new_ast_values(
            insert_list, // The actual value tuples: (1,2,3), (4,5,6)
            NULL // No additional VALUES clauses
        )
      ),
      NULL // No compound operators (UNION, etc.)
    ),
    new_ast_select_orderby(
      NULL, // No ORDER BY clause
      new_ast_select_limit(
        NULL, // No LIMIT clause
        new_ast_select_offset(
          NULL, // No OFFSET clause
          NULL // End of statement
        )
      )
    )
  );
}

// This is the main entry point for rewriting INSERT statements that target backed tables.
// It performs a complete transformation from user-friendly INSERT syntax into the complex
// CTE-based blob storage operations required by the backing table system.
//
// Transforms: INSERT INTO backed_table (pk, x, y) VALUES (1, 'text', 3.14), (2, 'more', 2.71)
// Into: WITH _vals (pk, x, y) AS (VALUES (1, 'text', 3.14), (2, 'more', 2.71))
//       INSERT INTO backing_table (k, v)
//         SELECT cql_blob_create_key(...), cql_blob_create_val(...) FROM _vals V
//
// The function builds complex AST structures using patterns from cql.y:
// - insert_stmt: INSERT insert_type name_columns_values
// - with_stmt: WITH cte_tables insert_stmt
// - cte_tables: cte_tables ',' cte_table | cte_table
// - select_stmt: select_core_list select_orderby
//
// This enables transparent backed table usage while storing data efficiently in blob format.
//
// The general insert pattern converts something like this:
//
// insert into backed values(1,2,3), (4,5,6), (7,8,9);
//
// into:
//
// WITH
// _vals (pk, x, y) AS (VALUES(1, "2", 3.14), (4, "5", 6), (7, "8", 9.7))
// INSERT INTO backing(k, v)
//   SELECT bcreatekey(9032558069325805135L, V.pk, 1),
//          bcreateval(9032558069325805135L, V.x, 7953209610392031882L, 4, V.y, 4501343740738089802L, 3)
//   FROM _vals V;
//
// To do this we need to:
//  * make the _vals CTE out of the values clause
//  * add a select clause that maps the values
//
// This code uses cql_blob_create(...) to which ultimately expands into whatever the blob create
// functions will be when sql code gen happens.
//
// cql_blob_create calls look like
//
// cql_blob_create(backed_type, val1, backed_type.col1, val2, backed_type.col2, ...)
//
// Those calls expand to include the hash codes if needed and field types.
cql_noexport void rewrite_insert_statement_for_backed_table(
  ast_node *ast,
  list_item *backed_tables_list)
{
  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Navigate to core INSERT statement, handling WITH clauses
  ast_node *stmt = sem_skip_with(ast);
  Invariant(is_ast_insert_stmt(stmt));
  EXTRACT_NOTNULL(name_columns_values, stmt->right);
  EXTRACT_STRING(backed_table_name, name_columns_values->left); // Target table name
  EXTRACT_ANY_NOTNULL(columns_values, name_columns_values->right); // Column spec and values

  // Validate that target table exists and determine if backing transformation needed
  ast_node *backed_table = find_table_or_view_even_deleted(backed_table_name);
  Contract(is_ast_create_table_stmt(backed_table));
  if (!is_backed(backed_table->sem->sem_type)) {
    // Table is not backed - skip blob transformation, just handle nested backed table CTEs
    goto replace_backed_tables_only;
  }

  // Extract backing table metadata from the backed table's attributes
  EXTRACT_MISC_ATTRS(backed_table, misc_attrs);

  CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
  Invariant(backing_table_name); // already validated
  ast_node *backing_table = find_table_or_view_even_deleted(backing_table_name);
  Invariant(backing_table); // already validated
  sem_struct *sptr_backing = backing_table->sem->sptr;
  Invariant(sptr_backing); // table must have a sem_struct

  // Validate INSERT statement form - only standard column/values syntax supported for backed tables

  // INSERT...USING form must be resolved to standard form before rewriting
  Contract(!is_ast_expr_names(columns_values));

  // DEFAULT VALUES not supported for backed tables (should error earlier)
  Contract(!is_ast_default_columns_values(columns_values));

  // Standard INSERT INTO table (cols) VALUES/SELECT form expected
  Contract(is_ast_columns_values(columns_values));

  EXTRACT(column_spec, columns_values->left); // Column specification: (col1, col2, ...)
  EXTRACT_ANY(insert_list, columns_values->right); // Data source: VALUES(...) or SELECT

  // Normalize INSERT data to SELECT form for consistent processing
  // Multiple INSERT forms (cursor, args, raw values) all get converted to SELECT VALUES
  // This creates a single rewrite path and simplifies blob generation logic

  // Most insert types are rewritten into select form including the standard
  // values clause but the insert forms that came from a cursor, args, or some
  // other shape are still written using an insert list, these are just vanilla
  // values.  Dummy default and all that sort of business likewise applies to
  // simple insert lists and all of that processing is done. If we find an
  // insert list form the first step is to normalize the insert list into a
  // select...values. We do this so thatwe have just one rewrite path after this
  // point, and because it's stupid simple

  if (is_ast_insert_list(insert_list)) {
    // Convert VALUES (1,2,3), (4,5,6) -> SELECT * FROM (VALUES (1,2,3), (4,5,6))
    ast_node *select_stmt = rewrite_insert_list_as_select_values(insert_list);
    // debug output if needed
    // gen_stmt_list_to_stdout(new_ast_stmt_list(select_stmt, NULL));
    insert_list = select_stmt;
  }

  // At this point we must have a SELECT statement (including SELECT VALUES form)
  // All other insert forms should have been normalized above
  Contract(is_select_variant(insert_list));

  EXTRACT_NOTNULL(name_list, column_spec->left);

  // Create CTE "_vals" that holds the user data with proper column names
  // This follows cql.y cte_table: cte_decl AS '(' select_stmt ')' pattern
  // Enables referencing user data as "V.column_name" in blob creation calls
  ast_node *cte_table_vals = new_ast_cte_table(
    new_ast_cte_decl(
      new_ast_str("_vals"), // CTE table name
      name_list // Column name list from INSERT
    ),
    insert_list // SELECT statement containing user data (could include WHERE clause)
  );

  // Generate blob creation expressions for key and value columns
  // These create cql_blob_create_key() and cql_blob_create_val() function calls
  ast_node *key_expr = rewrite_blob_create(true, backed_table, name_list);
  ast_node *val_expr = rewrite_blob_create(false, backed_table, name_list);

  // Build SELECT expression list for the final INSERT...SELECT
  // Following cql.y select_expr_list: select_expr_list ',' select_expr | select_expr pattern
  // Creates: SELECT key_blob_expr, val_blob_expr FROM _vals V
  ast_node *select_expr_list = new_ast_select_expr_list(
    new_ast_select_expr(key_expr, NULL), // First expression: key blob
    new_ast_select_expr_list(
      new_ast_select_expr(val_expr, NULL), // Second expression: value blob
      NULL // End of expression list
    )
  );

  // Construct complete SELECT statement that generates blob data from CTE
  // Following cql.y select_stmt: select_core_list select_orderby pattern
  // Creates: SELECT blob_key_expr, blob_val_expr FROM _vals V [WHERE 1]
  ast_node *select_stmt =
    new_ast_select_stmt(
      new_ast_select_core_list(
        new_ast_select_core(
          NULL, // No SELECT modifier (DISTINCT, etc.)
          new_ast_select_expr_list_con(
            // Computed select list containing blob creation expressions
            select_expr_list,
            // FROM clause references the _vals CTE with alias "V"
            new_ast_select_from_etc(
              new_ast_table_or_subquery_list(
                new_ast_table_or_subquery(
                  new_ast_str("_vals"), // Reference to _vals CTE
                  new_ast_opt_as_alias(new_ast_str("V")) // Short alias for column references
                ),
                NULL // No additional tables
              ),
              // WHERE clause handling for UPSERT compatibility
              // UPSERT conflict clauses require WHERE to avoid ambiguity
              // Any original WHERE from user SELECT is already in the _vals CTE
              //
              // we only need this where 1 business to avoid ambiguity
              // in the conflict clause of an upsert, it's the documented "use a where" business
              // we actually check for this in user generated code but there are no laws for us
              // Note that if there was an existing where clause associated with say a select that
              // contributed to the values, it would be hoisted into the _vals CTE and would be
              // part of the where clause of that select statement.  Which means for sure
              // there is no user-created where clause left here for us to handle.

              new_ast_select_where(
                  in_upsert ? new_ast_opt_where( new_ast_num(NUM_INT, "1")) : NULL, // WHERE 1 for UPSERT
                new_ast_select_groupby(
                  NULL, // No GROUP BY
                  new_ast_select_having(
                    NULL, // No HAVING
                    NULL // End of clause chain
                  )
                )
              )
            )
          )
        ),
        NULL // No compound operators (UNION, etc.)
      ),
      // Empty ORDER BY, LIMIT, OFFSET clauses
      new_ast_select_orderby(
        NULL, // No ORDER BY
        new_ast_select_limit(
          NULL, // No LIMIT
          new_ast_select_offset(
            NULL, // No OFFSET
            NULL // End of statement
          )
        )
      )
    );

  // for debugging dump the generated select statement
  // gen_stmt_list_to_stdout(new_ast_stmt_list(select_stmt, NULL));

  // Determine backing table column layout (key/value order can vary)
  // Backing tables can be either (key_col, val_col) or (val_col, key_col)
  // We detect this by checking if first column is a primary key
  sem_t sem_type = sptr_backing->semtypes[0];
  bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Map to actual column names based on detected layout
  CSTR backing_key = sptr_backing->names[!is_key_first]; // if order is kv then key is column 0, else 1
  CSTR backing_val = sptr_backing->names[is_key_first]; // if order is kv then val is column 1, else 0
  sem_t sem_type_key = sptr_backing->semtypes[!is_key_first];
  sem_t sem_type_val = sptr_backing->semtypes[is_key_first];

  // Construct final INSERT statement targeting the backing table
  // Following cql.y name_columns_values: name columns_values pattern
  // Creates: INSERT INTO backing_table (key_col, val_col) SELECT ...
  ast_node *new_name_columns_values = new_ast_name_columns_values(
    new_maybe_qstr(backing_table_name), // Target backing table name
    new_ast_columns_values(
      new_ast_column_spec(
        new_ast_name_list(
          new_str_or_qstr(backing_key, sem_type_key), // First column: key blob
          new_ast_name_list(
            new_str_or_qstr(backing_val, sem_type_val), // Second column: value blob
            NULL // End of column list
          )
        )
      ),
      select_stmt // SELECT statement generating blob data
    )
  );

  ast_set_right(stmt, new_name_columns_values);
  // for debugging dump the generated insert statement
  // gen_stmt_list_to_stdout(new_ast_stmt_list(ast, NULL));

  ast_node *with_node = NULL;
  ast_node *main_node = NULL;

  // recover the main statement, we need to add our CTE there
  if (in_upsert) {
    main_node = sem_recover_with_stmt(ast->parent);
    Invariant(is_ast_upsert_stmt(main_node) || is_ast_with_upsert_stmt(main_node));
  }
  else {
    main_node = ast;
    Invariant(is_ast_insert_stmt(main_node) || is_ast_with_insert_stmt(main_node));
  }

  if (is_ast_with(main_node->left)) {
    with_node = main_node->left;
  }

  // the _vals node has to go after everything else
  if (with_node) {
    EXTRACT_NOTNULL(cte_tables, with_node->left);

    // find the end and append
    while (cte_tables->right) {
      Contract(is_ast_cte_tables(cte_tables));
      cte_tables = cte_tables->right;
    }

    Contract(is_ast_cte_tables(cte_tables));
    ast_set_right(cte_tables, new_ast_cte_tables(cte_table_vals, NULL));
  }
  else {
    // there is nothing else, so we can go first, leverage our other converter
    list_item *vals_cte_list = NULL;
    add_item_to_list(&vals_cte_list, cte_table_vals);
    rewrite_statement_backed_table_ctes(main_node, vals_cte_list);
  }

replace_backed_tables_only:

  if (backed_tables_list) {
    if (!in_upsert) {
      rewrite_statement_backed_table_ctes(ast, backed_tables_list);
    }
  }

  // for debugging, dump the generated ast without trying to validate it at all
  // print_root_ast(ast);
  //
  // for debugging dump the generated insert statement
  // gen_stmt_list_to_stdout(new_ast_stmt_list(ast, NULL));

  AST_REWRITE_INFO_RESET();

  // if in upsert the overall statement will be analyzed, don't do it yet
  if (!in_upsert) {
    // the insert statement is top level, when it re-enters it expects the cte state to be nil
    cte_state *saved = cte_cur;
    cte_cur = NULL;
      sem_one_stmt(ast);
    cte_cur = saved;
  }
}

// This function creates a SELECT statement that retrieves rowid values from a backed table.
// It's used internally by DELETE and UPDATE operations that need to identify specific rows
// in the backing table for blob operations.
//
// For a backed table, this generates: SELECT rowid FROM backed_table [WHERE ...] [ORDER BY ...] [LIMIT ...]
// The backed table reference will later be replaced with appropriate CTE joins during full rewriting.
//
// The function constructs AST nodes using these patterns from cql.y:
// - select_stmt: select_core_list select_orderby
// - select_core: SELECT select_expr_list table_or_subquery_list where_clause group_by having select_window
// - select_expr_list: select_expr_list ',' select_expr | select_expr
// - table_or_subquery_list: table_or_subquery_list ',' table_or_subquery | table_or_subquery
//
// Returns complete SELECT statement AST for rowid retrieval
static ast_node *rewrite_select_rowid(
  CSTR backed_table_name,
  ast_node *opt_where,
  ast_node *opt_orderby,
  ast_node *opt_limit)
{
  // Build complete SELECT rowid statement structure
  // Following cql.y select_stmt: select_core_list select_orderby pattern
  return
    new_ast_select_stmt(
      new_ast_select_core_list(
        new_ast_select_core(
          NULL, // No SELECT modifier (DISTINCT, etc.)
          new_ast_select_expr_list_con(
            // Select list contains only "rowid" column
            // Following select_expr_list: select_expr pattern
            new_ast_select_expr_list(
              new_ast_select_expr(
                new_ast_str("rowid"), // Column name: rowid
                NULL // No column alias
              ),
              NULL // End of select list
            ),
            // FROM clause references the backed table (will be CTE-rewritten later)
            new_ast_select_from_etc(
              new_ast_table_or_subquery_list(
                new_ast_table_or_subquery(
                  new_maybe_qstr(backed_table_name), // Table name (possibly quoted)
                  NULL // No table alias
                ),
                NULL // No additional tables
              ),
              // WHERE clause from caller (DELETE/UPDATE conditions)
              new_ast_select_where(
                opt_where, // Optional WHERE conditions
                new_ast_select_groupby(
                  NULL, // No GROUP BY
                  new_ast_select_having(
                    NULL, // No HAVING
                    NULL // End of clause chain
                  )
                )
              )
            )
          )
        ),
        NULL // No compound operators (UNION, etc.)
      ),
      // ORDER BY, LIMIT, OFFSET from caller
      new_ast_select_orderby(
        opt_orderby, // Optional ORDER BY clause
        new_ast_select_limit(
          opt_limit, // Optional LIMIT clause
          new_ast_select_offset(
            NULL, // No OFFSET clause
            NULL // End of statement
          )
        )
      )
    );
}

// This function rewrites DELETE statements for backed tables, transforming them into
// DELETE operations on the underlying backing table using rowid-based selection.
//
// Transforms: DELETE FROM backed_table WHERE condition
// Into: WITH backed_table AS (...blob extraction CTE...)
//       DELETE FROM backing_table WHERE rowid IN (SELECT rowid FROM backed_table WHERE condition)
//
// The key insight is that we can't directly apply user conditions to blob data,
// so we first SELECT the rowids of matching rows using the original condition
// against the backed table CTE, then DELETE those specific rowids from the backing table.
//
// This function constructs AST nodes using patterns from cql.y:
// - delete_stmt: DELETE FROM name opt_where
// - opt_where: WHERE expr | ε
// - in_pred: expr IN '(' select_stmt ')'
//
// The backing table stores the actual blob data that needs to be deleted.
cql_noexport void rewrite_delete_statement_for_backed_table(
  ast_node *ast,
  list_item *backed_tables_list)
{
  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Navigate to core DELETE statement, handling WITH clauses
  ast_node *stmt = sem_skip_with(ast);
  Invariant(is_ast_delete_stmt(stmt));

  EXTRACT_STRING(backed_table_name, stmt->left); // Table to delete from
  EXTRACT(opt_where, stmt->right); // User's WHERE conditions

  // Validate target table and determine if backing transformation needed
  ast_node *backed_table = find_table_or_view_even_deleted(backed_table_name);
  Contract(is_ast_create_table_stmt(backed_table));
  if (!is_backed(backed_table->sem->sem_type)) {
    // Table is not backed - skip blob transformation, just handle nested backed table CTEs
    goto replace_backed_tables_only;
  }

  // Register backed table for CTE generation (needed for blob data extraction)
  add_item_to_list(
    &backed_tables_list,
    new_ast_table_or_subquery(new_maybe_qstr(backed_table_name), NULL)
  );

  // Extract backing table metadata from backed table attributes
  EXTRACT_MISC_ATTRS(backed_table, misc_attrs);

  CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
  Invariant(backing_table_name); // already validated

  // Create SELECT statement to identify rowids of rows matching user conditions
  // This uses the backed table (which will become a CTE with blob extraction)
  // and applies the original WHERE clause to find matching rows
  // Result: SELECT rowid FROM backed_table WHERE original_condition
  ast_node *select_stmt = rewrite_select_rowid(backed_table_name, opt_where, NULL, NULL);

  // for debugging print just the select statement
  // gen_stmt_list_to_stdout(new_ast_stmt_list(select_stmt, NULL));

  // Construct new WHERE clause using IN predicate with rowid subquery
  // Following cql.y in_pred: expr IN '(' select_stmt ')' pattern
  // Creates: WHERE rowid IN (SELECT rowid FROM backed_table WHERE original_condition)
  ast_node *new_opt_where =
    new_ast_opt_where(
     new_ast_in_pred(
       new_ast_str("rowid"), // Column: rowid
       select_stmt // Subquery selecting matching rowids
     )
  );

  // Transform DELETE statement: backed_table -> backing_table, original_where -> rowid IN (...)
  // Result: DELETE FROM backing_table WHERE rowid IN (SELECT rowid FROM backed_table WHERE original_condition)
  ast_set_left(stmt, new_maybe_qstr(backing_table_name)); // Change target to backing table
  ast_set_right(stmt, new_opt_where); // Replace WHERE clause

replace_backed_tables_only:

  // now add the backed tables and convert the node to a with delete if necessary
  rewrite_statement_backed_table_ctes(ast, backed_tables_list);

  AST_REWRITE_INFO_RESET();

  // the delete statement is top level, when it re-enters it expects the cte state to be nil
  cte_state *saved = cte_cur;
  cte_cur = NULL;
    sem_one_stmt(ast);
  cte_cur = saved;
}

// This function rewrites UPDATE statements for backed tables, transforming column
// assignments into blob update operations on the underlying backing table.
//
// Transforms: UPDATE backed_table SET x='new', y=42.0 WHERE condition
// Into: WITH backed_table AS (...blob extraction CTE...)
//       UPDATE backing_table SET
//         key_col = cql_blob_update(key_col, 'new', backed_table.x, ...),
//         val_col = cql_blob_update(val_col, 42.0, backed_table.y, ...)
//       WHERE rowid IN (SELECT rowid FROM backed_table WHERE condition)
//
// The function handles two contexts:
// 1. Standalone UPDATE: Uses rowid selection to identify target rows
// 2. UPSERT UPDATE: Operates on rows already selected by SQLite's conflict resolution
//
// This constructs AST nodes using patterns from cql.y:
// - update_stmt: UPDATE name SET update_list update_from update_where update_orderby
// - update_list: update_list ',' update_entry | update_entry
// - update_entry: name '=' expr
//
// Key and value blobs are updated separately using cql_blob_update() calls.
cql_noexport void rewrite_update_statement_for_backed_table(
  ast_node *ast,
  list_item *backed_tables_list)
{
  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Navigate to core UPDATE statement, handling WITH clauses
  ast_node *stmt = sem_skip_with(ast);

  Invariant(is_ast_update_stmt(stmt));
  // Extract all components of UPDATE statement structure
  EXTRACT_NOTNULL(update_set, stmt->right);
  EXTRACT_NOTNULL(update_list, update_set->left); // SET column=value assignments
  EXTRACT_NOTNULL(update_from, update_set->right);
  EXTRACT_NOTNULL(update_where, update_from->right);
  EXTRACT(opt_where, update_where->left); // WHERE conditions
  EXTRACT_NOTNULL(update_orderby, update_where->right);
  EXTRACT(opt_orderby, update_orderby->left); // ORDER BY clause
  EXTRACT(opt_limit, update_orderby->right); // LIMIT clause

  // Determine target table name (different handling for standalone vs UPSERT context)
  CSTR backed_table_name = NULL;

  if (stmt->left) {
    // Standalone UPDATE case - table name is directly available
    EXTRACT_STRING(t_name, stmt->left);
    backed_table_name = t_name;
  }
  else {
    // UPSERT context - table name comes from current upsert context
    Contract(is_ast_create_table_stmt(current_upsert_table_ast));
    EXTRACT_NOTNULL(create_table_name_flags, current_upsert_table_ast->left);
    EXTRACT_STRING(t_name, create_table_name_flags->right);
    backed_table_name = t_name;
  }


  // Validate target table and determine if backing transformation needed
  ast_node *backed_table = find_table_or_view_even_deleted(backed_table_name);
  Contract(is_ast_create_table_stmt(backed_table));
  if (!is_backed(backed_table->sem->sem_type)) {
    // Table is not backed - skip blob transformation, just handle nested backed table CTEs
    goto replace_backed_tables_only;
  }

  // Register backed table for CTE generation (needed for blob data extraction and rowid selection)
  add_item_to_list(
    &backed_tables_list,
    new_ast_table_or_subquery(new_maybe_qstr(backed_table_name), NULL)
  );

  // Extract backing table metadata and schema information
  EXTRACT_MISC_ATTRS(backed_table, misc_attrs);

  CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
  Invariant(backing_table_name); // already validated
  ast_node *backing_table = find_table_or_view_even_deleted(backing_table_name);
  Invariant(backing_table); // already validated
  sem_struct *sptr_backing = backing_table->sem->sptr;
  Invariant(sptr_backing); // table must have a sem_struct

  // Determine backing table column layout (key/value order can vary)
  // Backing tables can be either (key_col, val_col) or (val_col, key_col)
  // We detect this by checking if first column is a primary key
  sem_t sem_type = sptr_backing->semtypes[0];
  bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

  // Map to actual column names and types based on detected layout
  CSTR backing_key = sptr_backing->names[!is_key_first]; // if order is kv then key is column 0, else 1
  sem_t sem_type_key = sptr_backing->semtypes[!is_key_first];
  CSTR backing_val = sptr_backing->names[is_key_first]; // if order is kv then val is column 1, else 0
  sem_t sem_type_val = sptr_backing->semtypes[is_key_first];

  // Create rowid selection query for identifying target rows (standalone UPDATE only)
  // UPSERT context doesn't need this since SQLite handles row selection via conflict resolution

  // the new where clause has at its core a select statement that generates the
  // rowids of the rows to be updated.  This is using the existing where clause
  // against a from clause that is just the backed table.

  ast_node *select_stmt;

  if (!in_upsert) {
    // Standalone UPDATE: Create SELECT to identify rowids matching user conditions
    // Incorporates original WHERE, ORDER BY, and LIMIT clauses
    // Result: SELECT rowid FROM backed_table WHERE condition ORDER BY ... LIMIT ...
    select_stmt = rewrite_select_rowid(
      backed_table_name,
      opt_where,
      opt_orderby,
      opt_limit);

    // for debugging print just the select statement
    // gen_stmt_list_to_stdout(new_ast_stmt_list(select_stmt, NULL));
    // the new where clause for the update statement is going to be something like
    // rowid IN (select rowid from selected rows)

  }
  else {
    // UPSERT context: SQLite has already identified conflicting rows
    // No need for explicit rowid selection - UPSERT mechanism handles targeting

    // in the upsert case, the rows in question are already selected by SQLite
    // itself. We don't need to do the rowid selection, we just need to rewrite
    // the update list to use the backing table columns directly and we'll
    // select the rowid out of excluded.rowid
    select_stmt = NULL;
  }

  // Generate blob update expressions for key and value columns
  // These create cql_blob_update() calls that modify specific fields within the blobs
  // Returns NULL if no columns of that type (key/value) are being updated
  ast_node *key_expr = rewrite_blob_update(true, sptr_backing, backed_table, update_list);
  ast_node *val_expr = rewrite_blob_update(false, sptr_backing, backed_table, update_list);

  // Build new UPDATE assignment list targeting backing table blob columns
  // Following cql.y update_list: update_list ',' update_entry | update_entry pattern
  // Creates: SET key_col = cql_blob_update(...), val_col = cql_blob_update(...)
  ast_node *new_update_list = new_ast_update_list(NULL, NULL); // fake list head for building
  ast_node *up_tail = new_update_list;

  // Add key blob update assignment if any key columns are being updated
  if (key_expr) {
    ast_node *new = new_ast_update_list(
      new_ast_update_entry(new_str_or_qstr(backing_key, sem_type_key), key_expr), // key_col = cql_blob_update(...)
      NULL
    );
    ast_set_right(up_tail, new);
    up_tail =  new;
  }

  // Add value blob update assignment if any value columns are being updated
  if (val_expr) {
    ast_node *new = new_ast_update_list(
      new_ast_update_entry(new_str_or_qstr(backing_val, sem_type_val), val_expr), // val_col = cql_blob_update(...)
      NULL
    );
    ast_set_right(up_tail, new);
  }

  // Construct appropriate WHERE clause based on context
  ast_node *new_opt_where = NULL;

  if (!in_upsert) {
    // Standalone UPDATE: Use rowid IN (subquery) to target specific rows
    // Following cql.y in_pred: expr IN '(' select_stmt ')' pattern
    new_opt_where = new_ast_opt_where(
     new_ast_in_pred(
       new_ast_str("rowid"), // Column: rowid
       select_stmt // Subquery selecting target rowids
     )
    );
  }
  else {
    // UPSERT context: Preserve original WHERE clause but rewrite column references to blob extractions
    new_opt_where = opt_where;

    if (opt_where) {
      // Transform backed table column references to blob extraction calls
      AST_REWRITE_INFO_SAVE();
      AST_REWRITE_INFO_SET(opt_where->lineno, opt_where->filename);
      rewrite_backed_column_references_in_ast(opt_where, backed_table);
      AST_REWRITE_INFO_RESET();
      AST_REWRITE_INFO_RESTORE();
    }
  }

  // Transform UPDATE statement components to target backing table with blob operations
  // Result: UPDATE backing_table SET blob_assignments WHERE rowid_condition

  // Update target table (standalone only - UPSERT keeps NULL for context-based resolution)
  ast_set_left(stmt, in_upsert ? NULL : new_maybe_qstr(backing_table_name));

  // Replace column assignments with blob update expressions
  ast_set_left(update_set, new_update_list->right);

  // Update WHERE clause (rowid IN subquery for standalone, rewritten conditions for UPSERT)
  ast_set_left(update_where, new_opt_where);

  // Clear ORDER BY and LIMIT (already incorporated into rowid selection subquery for standalone)
  ast_set_left(update_orderby, NULL); // opt orderby handled in the select
  ast_set_right(update_orderby, NULL); // opt limit handled in the select

replace_backed_tables_only:

  if (!in_upsert) {
    // now add the backed tables and convert the node to a with update if necessary
    rewrite_statement_backed_table_ctes(ast, backed_tables_list);
  }

  AST_REWRITE_INFO_RESET();

  // if in upsert the overall statement will be analyzed
  if (!in_upsert) {
    // the update statement is top level, when it re-enters it expects the cte state to be nil
    cte_state *saved = cte_cur;
    cte_cur = NULL;
      sem_one_stmt(ast);
    cte_cur = saved;
  }
}

// This function orchestrates the rewriting of UPSERT statements for backed tables,
// coordinating the transformation of both INSERT and UPDATE components along with
// conflict resolution targeting.
//
// Transforms: INSERT INTO backed_table (...) VALUES (...) ON CONFLICT (pk) DO UPDATE SET ...
// Into: WITH backed_table AS (...blob extraction CTE...)
//       INSERT INTO backing_table (k, v) SELECT blob_key, blob_val FROM _vals
//       ON CONFLICT (key_col) DO UPDATE SET key_col = cql_blob_update(...), val_col = cql_blob_update(...)
//
// The function handles three key transformations:
// 1. INSERT component -> blob creation and backing table insertion
// 2. UPDATE component -> blob update operations on conflict
// 3. Conflict target -> backing table key column targeting
//
// This constructs AST nodes using patterns from cql.y:
// - upsert_stmt: insert_stmt ON CONFLICT conflict_target DO update_stmt
// - conflict_target: '(' indexed_columns ')' opt_where
// - indexed_columns: indexed_columns ',' indexed_column | indexed_column
//
// The backing table's key column becomes the conflict resolution target.
cql_noexport void rewrite_upsert_statement_for_backed_table(
  ast_node *ast,
  list_item *backed_tables_list)
{
  Contract(is_ast_upsert_stmt(ast) || is_ast_with_upsert_stmt(ast));

  // Navigate to core UPSERT statement, handling WITH clauses
  ast_node *stmt = sem_skip_with(ast);

  Invariant(is_ast_upsert_stmt(stmt));
  // Extract UPSERT statement components
  EXTRACT_NOTNULL(insert_stmt, stmt->left); // INSERT portion
  EXTRACT_NOTNULL(upsert_update, stmt->right); // ON CONFLICT ... DO UPDATE portion
  EXTRACT(conflict_target, upsert_update->left); // Conflict resolution target columns
  EXTRACT(update_stmt, upsert_update->right); // UPDATE statement for conflicts
  EXTRACT(indexed_columns, conflict_target->left); // Columns used for conflict detection

  // Determine if target table is backed and get table metadata
  Invariant(current_upsert_table_ast);
  ast_node *table_ast = current_upsert_table_ast;
  bool_t backed = is_backed(table_ast->sem->sem_type);

  // Transform INSERT component using blob creation and backing table targeting
  rewrite_insert_statement_for_backed_table(insert_stmt, backed_tables_list);

  // Transform UPDATE component (if present) using blob update operations
  if (update_stmt) {
    rewrite_update_statement_for_backed_table(update_stmt, backed_tables_list);
  }

  // Transform any backed table column references in conflict target to blob extractions
  // This handles cases where conflict detection references backed table columns
  if (backed) {
    rewrite_backed_column_references_in_ast(conflict_target, table_ast);
  }

  AST_REWRITE_INFO_SET(stmt->lineno, stmt->filename);

  // Add backed table CTEs to provide blob extraction functionality
  if (backed_tables_list) {
    rewrite_statement_backed_table_ctes(ast, backed_tables_list);
  }

  // For backed tables, redirect conflict target to use backing table's key column
  // This ensures UPSERT conflict detection works on the actual stored key blob
  if (backed) {
    // Extract backed table and backing table metadata
    EXTRACT_NOTNULL(create_table_name_flags, table_ast->left);
    EXTRACT_STRING(backed_table_name, create_table_name_flags->right);
    EXTRACT_MISC_ATTRS(table_ast, misc_attrs);
    CSTR backing_table_name = get_named_string_attribute_value(misc_attrs, "backed_by");
    Invariant(backing_table_name); // already validated
    ast_node *backing_table = find_table_or_view_even_deleted(backing_table_name);
    Invariant(backing_table); // already validated
    sem_struct *sptr_backing = backing_table->sem->sptr;
    Invariant(sptr_backing); // table must have a sem_struct

    // Determine backing table column layout to identify key column
    // Backing tables can be either (key_col, val_col) or (val_col, key_col)
    sem_t sem_type = sptr_backing->semtypes[0];
    bool_t is_key_first = is_primary_key(sem_type) || is_partial_pk(sem_type);

    CSTR backing_key = sptr_backing->names[!is_key_first]; // if order is kv then key is column 0, else 1

    // Create new conflict target that references the backing table's key column
    // Following cql.y indexed_columns: indexed_column pattern
    // Result: ON CONFLICT (backing_key_column) DO UPDATE ...
    ast_node *new_indexed_columns =
      new_ast_indexed_columns(
        new_ast_indexed_column(new_maybe_qstr(backing_key), NULL), // Key column for conflict resolution
        NULL // End of column list
      );

    // Replace original conflict target with backing table key column
    ast_set_left(conflict_target, new_indexed_columns);
  }

  AST_REWRITE_INFO_RESET();

  // the insert statement is top level, when it re-enters it expects the cte state to be nil
  cte_state *saved = cte_cur;
  cte_cur = NULL;
  in_upsert = false;
  in_upsert_rewrite = true;
  current_upsert_table_ast = NULL;
    sem_one_stmt(ast);
  in_upsert_rewrite = false;
  cte_cur = saved;
}

// This function transforms function call syntax into procedure call syntax when
// semantic analysis determines that a function call is actually referencing a procedure.
// This disambiguation happens after name resolution identifies the target as a procedure.
//
// Transforms: proc_name(arg1, arg2, ...)  [in expression statement context]
// Into: CALL proc_name(arg1, arg2, ...)   [proper procedure call statement]
//
// The key insight is that CQL allows procedures to be called using function syntax
// in expression statement contexts, but internally they need to be represented as
// proper CALL statements for correct code generation and analysis.
//
// This function constructs AST nodes using patterns from cql.y:
// - call_stmt: CALL name '(' arg_list ')'
// - expr_stmt: expr ';'
//
// The transformation preserves the procedure name and argument list while changing
// the statement type from expression to procedure call.
cql_noexport void rewrite_func_call_as_proc_call(
  ast_node *_Nonnull ast)
{
  Contract(is_ast_expr_stmt(ast));
  EXTRACT_NOTNULL(call, ast->left); // Original function call expression
  EXTRACT_NAME_AST(name_ast, call->left); // Procedure name

  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Extract argument list from function call structure
  EXTRACT_NOTNULL(call_arg_list, call->right);
  EXTRACT_ANY(arg_list, call_arg_list->right); // Arguments (may be NULL for no args)

  // Create proper CALL statement AST node
  // Following cql.y call_stmt: CALL name '(' arg_list ')' pattern
  ast_node *new = new_ast_call_stmt(name_ast, arg_list);

  AST_REWRITE_INFO_RESET();

  // Transform the expression statement into a call statement in-place
  // This preserves the original AST node while changing its type and structure
  ast->type = new->type; // Change from expr_stmt to call_stmt
  ast_set_left(ast, new->left); // Set procedure name
  ast_set_right(ast, new->right); // Set argument list
}

// This function handles the special '*' syntax in procedure argument lists,
// transforming it into a "FROM LOCALS LIKE procedure_name" shape expression.
// The '*' operator provides a convenient way to pass all local variables that
// match the target procedure's parameter signature.
//
// Transforms: CALL proc_name(*)
// Into: CALL proc_name(FROM LOCALS LIKE proc_name)
//
// This enables automatic argument passing where local variables with names
// matching the procedure's parameters are automatically bound as arguments.
// For example, if proc_name expects (x INT, y TEXT) and you have local variables
// x and y with compatible types, using '*' will pass them automatically.
//
// The function constructs AST nodes using patterns from cql.y:
// - from_shape: FROM name shape_def
// - shape_def: LIKE name
// - like: LIKE name name
//
// Returns false if '*' is mixed with other arguments (which is not allowed).
cql_noexport bool_t rewrite_ast_star_if_needed(
  ast_node *_Nullable arg_list,
  ast_node *_Nonnull proc_name_ast)
{
  if (!arg_list) {
    return true;
  }

  // Check if the first argument is the special '*' operator
  if (is_ast_star(arg_list->left)) {
    // Validate that '*' is used alone - it cannot be mixed with other arguments
    Contract(is_ast_arg_list(arg_list));
    if (arg_list->right) {
      report_error(arg_list, "CQL0474: when '*' appears in an expression list there can be nothing else in the list", NULL);
      record_error(arg_list);
      return false;
    }

    AST_REWRITE_INFO_SET(arg_list->lineno, arg_list->filename);

    // Build the shape expression: FROM LOCALS LIKE proc_name
    // Following cql.y like: LIKE name name pattern (both names are the same procedure)
    ast_node *like = new_ast_like(proc_name_ast, proc_name_ast);

    // Following cql.y shape_def: LIKE name pattern
    ast_node *shape_def = new_ast_shape_def(like, NULL);

    // Following cql.y from_shape: FROM name shape_def pattern
    // Creates: FROM LOCALS LIKE proc_name
    ast_node *call_expr = new_ast_from_shape(new_maybe_qstr("LOCALS"), shape_def);

    // Replace the '*' with the expanded shape expression
    ast_set_left(arg_list, call_expr);
    AST_REWRITE_INFO_RESET();
  }

  return true;
}

// This function transforms compound assignment operators (+=, -=, *=, etc.) into
// equivalent expanded assignment expressions. It provides syntactic sugar for
// common update patterns by expanding them into their explicit binary operation form.
//
// Transforms: variable += expression
// Into: variable := variable + expression
//
// Similarly handles: -=, *=, /=, %=, &=, |=, <<=, >>=
//
// The key insight is that compound assignments like "x += 5" are semantically
// equivalent to "x := x + 5", but the compound form is more concise and less
// error-prone (avoids repeating the variable name).
//
// This function constructs AST nodes using patterns from cql.y:
// - expr_assign: expr ASSIGN expr
// - binary operators: add, sub, mul, div, mod, bin_and, bin_or, lshift, rshift
//
// The transformation creates a cloned copy of the LHS for use in the binary operation,
// ensuring that complex LHS expressions (like array access) are properly duplicated.
cql_noexport void rewrite_op_equals_assignment_if_needed(
  ast_node *_Nonnull expr,
  CSTR _Nonnull op)
{
  Contract(expr);
  Contract(op);

  // Check if this is a compound assignment operator (must end with '=')
  size_t len = strlen(op);
  Contract(len);
  if (op[len-1] != '=') {
    return;
  }

  // Map compound assignment operators to their corresponding binary operators
  CSTR node_type = NULL;

  if (len == 2) {
    // Two-character operators: +=, -=, *=, /=, %=, &=, |=
    switch (op[0]) {
      case '+':  node_type = k_ast_add; break; // += becomes +
      case '-':  node_type = k_ast_sub; break; // -= becomes -
      case '*':  node_type = k_ast_mul; break; // *= becomes *
      case '/':  node_type = k_ast_div; break; // /= becomes /
      case '%':  node_type = k_ast_mod; break; // %= becomes %
      case '&':  node_type = k_ast_bin_and; break; // &= becomes &
      case '|':  node_type = k_ast_bin_or; break; // |= becomes |
    }
  }
  else if (len == 3) {
    // Three-character operators: <<=, >>=
    if (op[0] == op[1]) {
      switch (op[0]) {
        case '<':  node_type = k_ast_lshift; break; // <<= becomes <<
        case '>':  node_type = k_ast_rshift; break; // >>= becomes >>
      }
    }
  }

  // If no mapping found, this isn't a compound assignment - nothing to do
  if (!node_type) {
     return;
  }

  EXTRACT_ANY_NOTNULL(lval, expr->left); // Left-hand side (target variable)

  AST_REWRITE_INFO_SET(expr->lineno, expr->filename);

  // Clone the LHS for use as the first operand in the binary operation
  // This is crucial for complex LHS expressions like array[index] or object.field
  ast_node *rval = ast_clone_tree(lval);

  // Transform the compound assignment into a regular assignment
  expr->type = k_ast_expr_assign;

  // Create the binary operation: LHS_copy operator RHS
  // Start with addition as a template, then change to the correct operator
  ast_node *oper = new_ast_add(rval, expr->right);

  // Set the correct binary operator type (mapped from compound assignment)
  oper->type = node_type;

  // Install the binary operation as the RHS of the assignment
  // Result: LHS := (LHS_copy operator RHS)
  // This will be further rewritten into a SET statement by later processing
  ast_set_right(expr, oper);

  AST_REWRITE_INFO_RESET();
}

// This function transforms array access syntax into function call syntax by mapping
// array operations to user-defined operator functions. It enables custom array-like
// behavior for objects by converting array access into method calls.
//
// Transforms: array_obj[index1, index2, ...]  [in getter context]
// Into: type<kind>:array:get(array_obj, index1, index2, ...)
//
// Transforms: array_obj[index1, index2, ...] = value  [in setter context - handled by later rewrite]
// Into: type<kind>:array:set(array_obj, index1, index2, ..., value)
//
// The function constructs operator function names using a standardized pattern:
// "type_suffix<object_kind>:array:operation" where operation is "get" or "set".
// This enables polymorphic array access across different object types.
//
// This function constructs AST nodes using patterns from cql.y:
// - call: name '(' arg_list ')'
// - arg_list: arg_list ',' expr | expr
//
// The transformation preserves all array indices while adding the array object as the first argument.
cql_noexport void rewrite_array_as_call(
  ast_node *_Nonnull expr,
  CSTR _Nonnull op)
{
  Contract(is_ast_array(expr));
  EXTRACT_ANY_NOTNULL(array, expr->left); // Array object being accessed
  EXTRACT_NOTNULL(arg_list, expr->right); // Index arguments: [a, b, c]
  sem_t sem_type = array->sem->sem_type; // Object's semantic type
  CSTR kind = array->sem->kind; // Object's kind (class name, etc.)

  // Build the operator function name using type and kind information
  // Pattern: "type_suffix<object_kind>:array:operation"
  // Examples: "object<MyClass>:array:get", "text<>:array:set"
  CHARBUF_OPEN(tmp);
  bprintf(&tmp, "%s<%s>:array:%s", rewrite_type_suffix(sem_type), kind, op);
  CSTR new_name = find_op(tmp.ptr); // Look up registered operator function

  if (!new_name) {
    // No operator function registered - preserve the constructed name for error reporting
    new_name = Strdup(tmp.ptr); // this is for sure going to be an error
  }

  CHARBUF_CLOSE(tmp);

  AST_REWRITE_INFO_SET(expr->lineno, expr->filename);

  // Construct function call: operator_func(array_object, index1, index2, ...)
  // The array object becomes the first argument, followed by all index expressions
  ast_node *new_arg_list = new_ast_arg_list(array, arg_list);
  ast_node *name_ast = new_maybe_qstr(new_name);
  ast_node *call_arg_list = new_ast_call_arg_list(new_ast_call_filter_clause(NULL, NULL), new_arg_list);
  ast_node *new_call = new_ast_call(name_ast, call_arg_list);

  // Transform the array access into a function call in-place
  // This preserves the original AST node while changing its type and structure
  expr->type = new_call->type; // Change from array to call
  ast_set_left(expr, new_call->left); // Set function name
  ast_set_right(expr, new_call->right); // Set argument list

  AST_REWRITE_INFO_RESET();
}

// This utility function appends a new argument to the end of an existing function
// call's argument list. It's commonly used during rewriting to add additional
// parameters to transformed function calls (e.g., adding assigned values to setter calls).
//
// Transforms: func(arg1, arg2, arg3) + new_arg
// Into: func(arg1, arg2, arg3, new_arg)
//
// This is particularly useful in array setter rewriting where the assigned value
// needs to be added as the final argument to the setter function call.
//
// The function constructs AST nodes using patterns from cql.y:
// - arg_list: arg_list ',' expr | expr
//
// It traverses the existing argument list to find the tail, then appends the new argument.
cql_noexport void rewrite_append_arg(
  ast_node *_Nonnull call,
  ast_node *_Nonnull arg)
{
  Contract(is_ast_call(call));
  EXTRACT_NOTNULL(call_arg_list, call->right); // Extract call argument structure
  EXTRACT_NOTNULL(arg_list, call_arg_list->right); // Extract the actual argument list

  // Traverse to the end of the argument list
  // The argument list is a right-recursive structure: arg_list → (expr, arg_list | NULL)
  while (arg_list->right) {
    arg_list = arg_list->right;
  }

  // At this point, arg_list->right is NULL, so we're at the tail of the list
  AST_REWRITE_INFO_SET(arg->lineno, arg->filename);

  // Create new argument list node containing the new argument
  // Following cql.y arg_list: arg_list ',' expr pattern
  ast_node *new_arg_list = new_ast_arg_list(arg, NULL);

  // Link the new argument as the next item in the list
  // This extends: func(existing_args) → func(existing_args, new_arg)
  ast_set_right(arg_list, new_arg_list);
  AST_REWRITE_INFO_RESET();
}

// This function attempts to rewrite binary operators as function calls when user-defined
// operator overloads are available. It enables custom behavior for operators like
// →, <<, >>, || (concat) on object types by mapping them to registered operator functions.
//
// Transforms: left_operand → right_operand  [if → operator is overloaded]
// Into: type<kind>:arrow:type<kind>(left_operand, right_operand)
//
// The function implements a fallback strategy for operator function lookup:
// 1. Try specific left_type<left_kind>:op:right_type<right_kind>
// 2. Try left_type<left_kind>:op:right_type (ignoring right kind)
// 3. Try left_type<left_kind>:op:all (universal right operand)
//
// This enables flexible operator overloading where objects can define operators
// for specific types or provide generic operators for any right operand.
//
// This function constructs AST nodes using patterns from cql.y:
// - call: name '(' arg_list ')'
// - arg_list: arg_list ',' expr | expr
//
// Returns true if an operator mapping was found and applied, false otherwise.
cql_noexport bool_t try_rewrite_op_as_call(ast_node *_Nonnull ast, CSTR op) {
  EXTRACT_ANY_NOTNULL(left, ast->left); // Left operand
  EXTRACT_ANY_NOTNULL(right, ast->right); // Right operand

  sem_t sem_type_left = left->sem->sem_type; // Left operand's semantic type
  CSTR kind_left = left->sem->kind; // Left operand's kind (class name, etc.)
  sem_t sem_type_right = right->sem->sem_type; // Right operand's semantic type

  if (!kind_left) {
    // No kind means no custom operators possible - use built-in operator
    return false;
  }

  // Build operator function name using fallback strategy
  CHARBUF_OPEN(key);

  // Start with base pattern: "left_type<left_kind>:operator:"
  bprintf(&key, "%s<%s>:%s:", rewrite_type_suffix(sem_type_left), kind_left, op);
  uint32_t used = key.used; // Save position for backtracking during fallback

  CSTR new_name = NULL;

  // Strategy 1: Try specific right operand type with kind
  // Pattern: "left_type<left_kind>:op:right_type<right_kind>"
  CSTR kind_right = right->sem->kind;
  if (kind_right) {
     bprintf(&key, "%s<%s>", rewrite_type_suffix(sem_type_right), kind_right);
     new_name = find_op(key.ptr);
  }

  // Strategy 2: Try right operand type without kind
  // Pattern: "left_type<left_kind>:op:right_type"
  if (!new_name) {
     key.used = used; // Backtrack to base pattern
     key.ptr[used] = 0;
     bprintf(&key, "%s", rewrite_type_suffix(sem_type_right));
     new_name = find_op(key.ptr);
  }

  // Strategy 3: Try universal right operand
  // Pattern: "left_type<left_kind>:op:all"
  if (!new_name) {
     key.used = used; // Backtrack to base pattern
     key.ptr[used] = 0;
     bprintf(&key, "all");
     new_name = find_op(key.ptr);
  }

  CHARBUF_CLOSE(key);

  if (!new_name) {
    // No operator overload found - use built-in operator behavior
    return false;
  }

  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  // Transform binary operation into function call: operator_func(left, right)
  // Following cql.y call: name '(' arg_list ')' pattern
  ast_node *new_arg_list = new_ast_arg_list(left, new_ast_arg_list(right, NULL));
  ast_node *function_name = new_maybe_qstr(new_name);
  ast_node *call_arg_list = new_ast_call_arg_list(new_ast_call_filter_clause(NULL, NULL), new_arg_list);
  ast_node *new_call = new_ast_call(function_name, call_arg_list);

  // Replace the binary operator with the function call in-place
  ast->type = new_call->type; // Change from binary op to call
  ast_set_left(ast, new_call->left); // Set function name
  ast_set_right(ast, new_call->right); // Set argument list

  AST_REWRITE_INFO_RESET();

  return true; // Successfully rewrote operator as function call
}

// This function transforms member access syntax (dot operator) into function call syntax
// by mapping property access to user-defined getter/setter functions. It enables custom
// property access behavior for objects by converting property access into method calls.
//
// Transforms: object.property  [in getter context]
// Into: type<kind>:get:property(object) OR type<kind>:get:all(object, 'property')
//
// Transforms: object.property = value  [in setter context - handled by assignment rewrite]
// Into: type<kind>:set:property(object, value) OR type<kind>:set:all(object, 'property', value)
//
// The function implements a two-tier fallback strategy for property function lookup:
// 1. Try specific property: "type<kind>:operation:property_name"
// 2. Try universal property: "type<kind>:operation:all" (adds property name as string argument)
//
// This enables flexible property access where objects can define specific property handlers
// or provide generic property access through a universal handler that receives the property name.
//
// The function constructs AST nodes using these patterns from cql.y:
// - call: name '(' arg_list ')'
// - arg_list: arg_list ',' expr | expr
// - str: STRING_LITERAL (for property name in universal handler case)
//
// The transformation preserves the object expression while replacing property access with function calls.
cql_noexport void rewrite_dot_as_call(
  ast_node *_Nonnull dot,
  CSTR _Nonnull op)
{
  Contract(is_ast_dot(dot));
  EXTRACT_ANY_NOTNULL(expr, dot->left); // Object being accessed
  EXTRACT_STRING(func, dot->right); // Property name being accessed

  // Build operator function name using fallback strategy
  CHARBUF_OPEN(k1);
  CHARBUF_OPEN(k2);

  sem_t sem_type = expr->sem->sem_type; // Object's semantic type
  CSTR kind = expr->sem->kind; // Object's kind (class name, etc.)

  // Strategy 1: Try specific property handler
  // Pattern: "type<kind>:operation:property_name"
  // Example: "object<MyClass>:get:name" for object.name getter
  bprintf(&k1, "%s<%s>:%s:%s", rewrite_type_suffix(sem_type), kind, op, func);
  CSTR new_name = find_op(k1.ptr);
  bool_t add_arg = false;

  // Strategy 2: Try universal property handler
  // Pattern: "type<kind>:operation:all"
  // Example: "object<MyClass>:get:all" for any property getter
  if (!new_name) {
    bprintf(&k2, "%s<%s>:%s:all", rewrite_type_suffix(sem_type), kind, op);
    new_name = find_op(k2.ptr);
    add_arg = !!new_name; // Universal handler needs property name as string argument
  }

  if (!new_name) {
    // No property handler found - preserve the constructed name for error reporting
    new_name = Strdup(k1.ptr); // this is for sure going to be an error
  }

  CHARBUF_CLOSE(k2);
  CHARBUF_CLOSE(k1);

  AST_REWRITE_INFO_SET(dot->lineno, dot->filename);

  // For universal property handlers, add the property name as a string literal argument
  // This allows the handler to determine which property is being accessed at runtime
  ast_node *base_list = NULL;
  if (add_arg) {
    EXTRACT_STRING(name, dot->right);
    // AST for: 'property_name' (string literal containing the property name)
    // Following cql.y str: STRING_LITERAL pattern
    ast_node *new_str = new_ast_str(dup_printf("'%s'", name));
    base_list = new_ast_arg_list(new_str, NULL);
  }

  // Construct function call: property_func(object [, 'property_name'])
  // Following cql.y call: name '(' arg_list ')' pattern
  // The object becomes the first argument, optionally followed by property name for universal handlers
  ast_node *new_arg_list = new_ast_arg_list(expr, base_list);
  ast_node *function_name = new_maybe_qstr(new_name);
  ast_node *call_arg_list = new_ast_call_arg_list(new_ast_call_filter_clause(NULL, NULL), new_arg_list);
  ast_node *new_call = new_ast_call(function_name, call_arg_list);

  // Transform the dot access into a function call in-place
  // This preserves the original AST node while changing its type and structure
  dot->type = new_call->type; // Change from dot to call
  ast_set_left(dot, new_call->left); // Set function name
  ast_set_right(dot, new_call->right); // Set argument list

  AST_REWRITE_INFO_RESET();
}

// This function transforms INSERT column/value pairs into UPDATE assignment lists,
// converting from INSERT syntax to UPDATE syntax for use in UPSERT operations and
// other contexts where INSERT data needs to be represented as assignments.
//
// Transforms: INSERT INTO table (col1, col2, col3) VALUES (val1, val2, val3)
// Into equivalent: UPDATE table SET col1 = val1, col2 = val2, col3 = val3
//
// This transformation is crucial for UPSERT statement processing where the INSERT
// portion needs to be converted into UPDATE assignments for the conflict resolution
// "DO UPDATE SET" clause. It enables code reuse between INSERT and UPDATE handling.
//
// The function pairs up corresponding elements from the column name list and value list,
// creating UPDATE entry nodes that represent "column = value" assignments.
//
// The function constructs AST nodes using these patterns from cql.y:
// - update_list: update_list ',' update_entry | update_entry
// - update_entry: name '=' expr
// - name: IDENTIFIER (column names)
//
// The result is a linked list of update entries that can be used in UPDATE statements.
cql_noexport ast_node *_Nonnull rewrite_column_values_as_update_list(
  ast_node *_Nonnull columns_values)
{
  // Extract the column specification and value lists from INSERT column/value structure
  EXTRACT_NOTNULL(column_spec, columns_values->left); // Column specification: (col1, col2, ...)
  EXTRACT_ANY_NOTNULL(name_list, column_spec->left); // Column name list
  EXTRACT_ANY_NOTNULL(insert_list, columns_values->right); // Value list: (val1, val2, ...)

  AST_REWRITE_INFO_SET(columns_values->lineno, columns_values->filename);

  // Create a dummy head node for building the update list chain
  // This simplifies the list construction logic by providing a stable starting point
  // The actual result will skip this dummy head node
  ast_node *new_update_list_head = new_ast_update_list(NULL, NULL); // fake list head
  ast_node *curr_update_list = new_update_list_head;

  // Traverse both lists in parallel, pairing columns with their corresponding values
  // Both lists should have the same length (validated elsewhere in semantic analysis)
  ast_node *name_item = NULL;
  ast_node *insert_item = NULL;
  for (
    name_item = name_list, insert_item = insert_list;
    name_item && insert_item;
    name_item = name_item->right, insert_item = insert_item->right
  ) {
    // Extract column name and corresponding value expression
    EXTRACT_STRING(name, name_item->left); // Column name: "column_name"
    EXTRACT_ANY_NOTNULL(expr, insert_item->left); // Value expression: value

    // Create UPDATE entry: column_name = value_expression
    // Following cql.y update_entry: name '=' expr pattern
    // This represents a single assignment in an UPDATE statement
    ast_node *new_update_list = new_ast_update_list(
      new_ast_update_entry(new_maybe_qstr(name), expr), // Single assignment: name = expr
      NULL // Next entry (to be linked)
    );

    // Link the new entry into the growing update list chain
    // Following cql.y update_list: update_list ',' update_entry pattern
    // This builds: SET col1 = val1, col2 = val2, col3 = val3, ...
    ast_set_right(curr_update_list, new_update_list);
    curr_update_list = curr_update_list->right; // Advance to new tail
  }

  AST_REWRITE_INFO_RESET();

  // Return the actual update list, skipping the dummy head node we used for construction
  // The result is a complete update_list chain ready for use in UPDATE statements
  return new_update_list_head->right;
}

// This function transforms SQL-only function calls into SELECT expressions that can be
// evaluated in contexts where direct function calls are not permitted. It wraps function
// calls in a SELECT statement with "IF NOTHING THROW" semantics to ensure they execute
// in a proper SQL evaluation context.
//
// Transforms: sql_function(arg1, arg2, ...)  [in expression context]
// Into: (SELECT sql_function(arg1, arg2, ...) IF NOTHING THROW)
//
// This is necessary for SQL functions that can only be evaluated within a SQL statement
// context (like aggregate functions, window functions, or database-specific functions)
// but need to be used in procedural expression contexts. The SELECT wrapper provides
// the required SQL execution environment.
//
// The "IF NOTHING THROW" clause ensures that if the SELECT returns no rows (which
// shouldn't happen for scalar functions), an exception is thrown rather than returning NULL.
// This maintains the expected behavior of scalar function calls.
//
// The function constructs a complete SELECT statement using these patterns from cql.y:
// - select_if_nothing_throw_expr: '(' select_stmt IF NOTHING THROW ')'
// - select_stmt: select_core_list select_orderby
// - select_core: SELECT select_expr_list_con
// - select_expr_list: select_expr_list ',' select_expr | select_expr
// - select_expr: expr opt_as_alias
//
// This enables SQL functions to be used transparently in procedural code contexts.
void rewrite_as_select_expr(ast_node *ast) {
  AST_REWRITE_INFO_SET(ast->lineno, ast->filename);

  Contract(is_ast_call(ast));

  // Transform the function call node into a SELECT IF NOTHING THROW expression
  // This changes the node type while preserving the original function call as part of the SELECT
  ast->type = k_ast_select_if_nothing_throw_expr;

  // Clone the original function call for embedding in the SELECT statement
  // This preserves the function name and arguments while allowing the original node to be transformed
  ast_node *new_call = new_ast_call(ast->left, ast->right);

  // Construct the complete SELECT statement structure
  // Following cql.y select_if_nothing_throw_expr: '(' select_stmt IF NOTHING THROW ')' pattern
  // Result: (SELECT function_call IF NOTHING THROW)
  ast_set_left(
    ast,
    // AST for: SELECT function_call [ORDER BY] [LIMIT] [OFFSET]
    // Following cql.y select_stmt: select_core_list select_orderby pattern
    new_ast_select_stmt(
      // AST for: SELECT function_call (no compound operators like UNION)
      // Following cql.y select_core_list: select_core pattern
      new_ast_select_core_list(
        // AST for: SELECT function_call [FROM] [WHERE] [GROUP BY] [HAVING] [WINDOW]
        // Following cql.y select_core: SELECT select_expr_list_con pattern
        new_ast_select_core(
          NULL, // No SELECT modifiers (DISTINCT, etc.)
          // AST for: function_call [FROM table_list] [WHERE] [GROUP BY] [HAVING]
          // Following cql.y select_expr_list_con: select_expr_list select_from_etc pattern
          new_ast_select_expr_list_con(
            // AST for: function_call (single expression in SELECT list)
            // Following cql.y select_expr_list: select_expr pattern
            new_ast_select_expr_list(
              // AST for: function_call [AS alias]
              // Following cql.y select_expr: expr opt_as_alias pattern
              new_ast_select_expr(new_call, NULL), // Function call with no alias
              NULL // No additional expressions
            ),
            // AST for: [FROM] [WHERE] [GROUP BY] [HAVING]
            // All clauses are NULL since we're just evaluating a scalar function
            new_ast_select_from_etc(
              NULL, // No FROM clause (scalar function evaluation)
              // AST for: [WHERE expr] [GROUP BY] [HAVING]
              new_ast_select_where(
                NULL, // No WHERE clause
                // AST for: [GROUP BY expr_list] [HAVING expr]
                new_ast_select_groupby(
                  NULL, // No GROUP BY clause
                  new_ast_select_having(NULL, NULL) // No HAVING clause
                )
              )
            )
          )
        ),
        NULL // No compound operators (UNION, INTERSECT, etc.)
      ),
      // AST for: [ORDER BY] [LIMIT] [OFFSET]
      // All clauses are NULL since we're evaluating a single scalar expression
      new_ast_select_orderby(
        NULL, // No ORDER BY clause
        // AST for: [LIMIT expr] [OFFSET expr]
        new_ast_select_limit(
          NULL, // No LIMIT clause
          new_ast_select_offset(NULL, NULL) // No OFFSET clause
        )
      )
    )
  );

  // Clear the right child since SELECT IF NOTHING THROW expressions only have a left child (the SELECT)
  ast_set_right(ast, NULL);

  // for debugging, dump the generated ast without trying to validate it at all
  // print_root_ast(ast->parent);
  // for debugging dump the tree
  // gen_stmt_list_to_stdout(new_ast_stmt_list(ast, NULL));

  AST_REWRITE_INFO_RESET();
}

// This function transforms wildcard column selection syntax (*) and table-qualified wildcards
// (table.*) into explicit column calculation expressions that can be properly processed during
// semantic analysis and code generation. It handles both global wildcards and table-specific wildcards.
//
// Transforms: SELECT * FROM table1, table2
// Into: SELECT @COLUMNS(table1), @COLUMNS(table2)
//
// Transforms: SELECT table1.* FROM table1, table2
// Into: SELECT @COLUMNS(table1)
//
// This transformation is crucial for several reasons:
// 1. Backed tables require early column expansion since their column structure is virtual
// 2. It enables consistent column handling across different table types
// 3. It provides a uniform interface for column enumeration during semantic analysis
//
// The function implements a special optimization for EXISTS expressions where column
// expansion is unnecessary - it simply replaces wildcards with literal "1" since
// EXISTS only cares about row existence, not specific column values.
//
// The function constructs AST nodes using these patterns from cql.y:
// - column_calculation: '@' COLUMNS '(' col_calcs ')'
// - col_calcs: col_calcs ',' col_calc | col_calc
// - col_calc: name opt_column_calculation_type
// - select_expr: expr opt_as_alias
//
// This enables deferred column expansion through the @COLUMNS directive system.
cql_noexport void rewrite_star_and_table_star_as_columns_calc(
  ast_node *select_expr_list,
  sem_join *jptr)
{
  // Validate that join scope information is available for column expansion
  // Without join scope, we cannot determine which tables/columns are available
  if (!jptr) {
    return; // no expansion is possible, errors will be emitted later
  }

  // Special optimization for EXISTS expressions: replace wildcards with literal "1"
  // Since EXISTS only tests for row existence, the actual column values are irrelevant
  // This avoids unnecessary column expansion and improves performance
  if (is_ast_select_expr_list_con(select_expr_list->parent)) {
    // Navigate up the AST hierarchy to determine if we're in an EXISTS context
    // The structure is: select_expr_list → select_expr_list_con → select_core → ... → select_stmt → exists_expr
    EXTRACT(select_expr_list_con, select_expr_list->parent);
    EXTRACT(select_core, select_expr_list_con->parent);
    EXTRACT_ANY(any_select_core, select_core->parent);

    // Traverse up to find the containing SELECT statement
    while (!is_ast_select_stmt(any_select_core)) {
      any_select_core = any_select_core->parent;
    }
    EXTRACT_ANY_NOTNULL(select_context, any_select_core->parent);

    // If this SELECT is part of an EXISTS expression, optimize by using literal "1"
    if (is_ast_exists_expr(select_context)) {
      // Clear any additional expressions and replace with a single literal "1"
      // Following cql.y select_expr: expr opt_as_alias pattern
      select_expr_list->right = NULL;
      AST_REWRITE_INFO_SET(select_expr_list->lineno, select_expr_list->filename);
      ast_set_left(select_expr_list, new_ast_select_expr(new_ast_num(NUM_INT, "1"), NULL));
      AST_REWRITE_INFO_RESET();

      return;
    }
  }

  // Process each expression in the SELECT list, looking for wildcard patterns
  for (ast_node *item = select_expr_list; item; item = item->right) {
    EXTRACT_ANY_NOTNULL(select_expr, item->left);

    // Handle global wildcard: SELECT * FROM ...
    // This expands to all columns from all tables in the FROM clause
    if (is_ast_star(select_expr)) {
      // Transform * into @COLUMNS directive for all tables in scope
      // The @COLUMNS directive will be processed later to expand into actual column lists
      // This approach is necessary because backed tables require early expansion
      // but normal tables can defer expansion until code generation

      AST_REWRITE_INFO_SET(select_expr->lineno, select_expr->filename);

      // Build a chain of column calculation nodes for each table in the join scope
      // Each table gets its own @COLUMNS(table_name) entry
      ast_node *prev = NULL;
      ast_node *first = NULL;

      for (int i = 0; i < jptr->count; i++) {
        CSTR tname = jptr->names[i];

        // AST for: @COLUMNS(table_name)
        // Following cql.y col_calcs: col_calc pattern and col_calc: name opt_column_calculation_type pattern
        // This creates a column calculation directive that will expand all columns from the specified table
        ast_node *calcs = new_ast_col_calcs(
          new_ast_col_calc(new_maybe_qstr(tname), NULL), // Table name with no type filter
          NULL // Next calculation (to be linked)
        );

        // Build the chain of column calculations: @COLUMNS(table1), @COLUMNS(table2), ...
        if (i == 0) {
          first = calcs; // First calculation in the chain
        }
        else {
          ast_set_right(prev, calcs); // Link to previous calculation
        }

        prev = calcs; // Track current node for next iteration
      }

      // Transform the * expression into a column calculation expression
      // Following cql.y column_calculation: '@' COLUMNS '(' col_calcs ')' pattern
      // Result: SELECT @COLUMNS(table1), @COLUMNS(table2), ... FROM ...
      select_expr->type = k_ast_column_calculation;
      ast_set_left(select_expr, first);
      AST_REWRITE_INFO_RESET();
    }
    // Handle table-qualified wildcard: SELECT table_name.* FROM ...
    // This expands to all columns from the specified table only
    else if (is_ast_table_star(select_expr)) {
      AST_REWRITE_INFO_SET(select_expr->lineno, select_expr->filename);

      // Extract the table name from the table.* expression
      // The table name might be invalid, but error handling occurs during semantic analysis
      EXTRACT_STRING(tname, select_expr->left);

      // Transform table.* into @COLUMNS(table_name)
      // Following cql.y column_calculation: '@' COLUMNS '(' col_calcs ')' pattern
      // Result: SELECT @COLUMNS(specific_table) FROM ...
      select_expr->type = k_ast_column_calculation;
      ast_set_left(select_expr,
        // AST for: @COLUMNS(table_name)
        // Following cql.y col_calcs: col_calc pattern
        new_ast_col_calcs(
          // AST for: table_name (column calculation for specific table)
          // Following cql.y col_calc: name opt_column_calculation_type pattern
          new_ast_col_calc(
            new_maybe_qstr(tname), // Specified table name
            NULL // No type filter - include all columns
          ),
          NULL // No additional calculations
        )
      );
      AST_REWRITE_INFO_RESET();
    }
  }
}

#endif
