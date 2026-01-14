---
title: "Appendix 12: Builtin Pipeline Operators"
weight: 12
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## Overview

Pipeline operators provide syntactic shortcuts that make CQL code more concise and readable by transforming special syntax into standard function calls. These operators support multiple syntactic forms (`:`, `.`, `->`, `[]`, etc.) that transform in a left-to-right flow, similar to method chaining in object-oriented languages.

This appendix includes a short primer on the use of `@op` to do these transforms and the builtin operators (defined in `cql.y`).

### Syntax Variations

Pipeline operators support several equivalent syntactic forms:

```sql
-- Colon syntax - method-like operations
let count := my_list:count;
list:add("value");

-- Dot syntax - property-like access
let count := my_list.count;
EXPECT_EQ!(0, list.count);

-- Array syntax - indexed access
value := list[index];
list[index] := value;

-- Arrow syntax - custom binary operations
result := xml_data -> xpath_query;

-- Standard operators - remappable for custom types
result := value << offset;    -- lshift
result := value >> offset;    -- rshift
result := text1 || text2;     -- concat
```

The choice of syntax is largely stylistic, with each form designed to read
naturally for its use case. All forms transform to standard function calls and
undergo normal type checking.  Note that precedence of the operators is normal
and this can affect which operator you choose.  Choose one with the most
helpful/natural precedence!

### How Pipeline Operators Work

Pipeline operators are defined using `@op` directives that specify
pattern-matching rules for syntax transformations. When the CQL compiler
encounters pipeline syntax like `expr:operation` or `expr.operation`, it:

1. **Pattern Matches**: Examines the type and kind of `expr` (e.g., `cursor`, `object<cql_box>`, `cql_long_list`)
2. **Looks Up Mapping**: Finds the corresponding `@op` directive that matches the pattern
3. **Rewrites to Function Call**: Transforms the pipeline syntax into a standard function call
4. **Type Checks**: Validates the resulting function call using normal semantic analysis

**Example transformation:**
```sql
-- Pipeline syntax (concise)
let count := my_list:count;

-- Rewrites to (verbose)
let count := cql_long_list_count(my_list);
```

### The `@op` Directive Format

Each `@op` directive defines one transformation rule with this structure:

```
@op <type_pattern> : <operation> <name> as <function_name>;
```

**Components:**
* `<type_pattern>`: The type and optional kind to match (e.g., `cursor`, `int`, `object<cql_box>`, `cql_long_list`)
* `<operation>`: The operation type (`call`, `get`, `set`, `array get`, `array set`, `functor all`, `arrow`, `lshift`, `rshift`, `concat`)
* `<name>`: The operation name used in pipeline syntax (e.g., `box`, `count`, `add`)
* `<function_name>`: The target function to call (e.g., `cql_box_int`, `cql_cursor_count`)

**Examples:**
```
@op int : call box as cql_box_int;
  -- Transforms: my_int:box → cql_box_int(my_int)

@op cursor : call count as cql_cursor_column_count;
  -- Transforms: C:count → cql_cursor_column_count(C)

@op cql_long_list : array get as cql_long_list_get_at;
  -- Transforms: list[index] → cql_long_list_get_at(list, index)

@op text<xml> : arrow text<xml_path> as extract_xml_path;
  -- Transforms: xml -> path → extract_xml_path(xml, path)
```

**Binary Operator Remapping:**

The `@op` directive also supports remapping standard binary operators for custom types:

* `arrow` - Remaps the `->` operator for custom binary operations
* `lshift` - Remaps the `<<` operator (left shift)
* `rshift` - Remaps the `>>` operator (right shift)
* `concat` - Remaps the `||` operator (concatenation)

These enable domain-specific operator syntax while maintaining type safety
through the semantic checking of the resulting function calls.

### Benefits and Customization

**Benefits:**
* **Readability**: Left-to-right flow matches natural reading order
* **Discoverability**: IDE autocomplete can suggest available operations for each type
* **Chainability**: Multiple operations can be chained: `value:box:to_int:ifnull_throw`
* **Type Safety**: Transformations are validated during semantic analysis, preventing type errors

**Customization:**
`@op` directives can be overridden or extended in your code to define custom
pipeline operators for your own types. The rewritten function calls are still
semantically checked, so there are no additional type-safety concerns when
defining custom operators.

### Built-in Pipeline Operators

The following sections document all built-in pipeline operators provided by CQL. Each operator entry shows:
* The transformation performed
* The purpose and use cases
* The specific `@op` directive details

All built-in operators can be found in `cql.y` (search for `@op`). The form of
pipeline operators is discussed more generally in [Chapter 8](../08_functions.md).

### Boxing and Unboxing

#### Boxing Primitive Values

The `:box` pipeline operator converts primitive CQL values into boxed object
references. This transformation wraps primitive types (bool, int, long, real,
text, blob, object) into a uniform `object<cql_box>` type that can be stored in
generic containers or passed to functions expecting objects.

**Transformation:**
* `let obj := my_int:box;` → `let obj := cql_box_int(my_int);`
* `let obj := my_text:box;` → `let obj := cql_box_text(my_text);`

**Details:**
```
@op bool : call box as cql_box_bool;
@op int  : call box as cql_box_int;
@op long : call box as cql_box_long;
@op real : call box as cql_box_real;
@op text : call box as cql_box_text;
@op blob : call box as cql_box_blob;
@op object : call box as cql_box_object;
```

#### Unboxing Object References

The `:to_<type>` pipeline operators extract primitive values from boxed object
references. These operations convert an `object<cql_box>` back to its underlying
primitive type. The extracted value is nullable; use `:ifnull_throw` or
`:ifnull_crash` if a non-null value is required.

**Transformation:**
* `nullable_bool := my_box:to_bool;` → `nullable_bool := cql_unbox_bool(my_box);`
* `notnull_long := my_box:to_long:ifnull_throw;` → `notnull_long := cql_unbox_long(my_box):ifnull_throw;`

**Purpose:** The `:type` operator returns the runtime type code of the boxed
value, enabling type checking at runtime.

**Details:**
```
@op object<cql_box> : call to_bool as cql_unbox_bool;
@op object<cql_box> : call to_int as cql_unbox_int;
@op object<cql_box> : call to_long as cql_unbox_long;
@op object<cql_box> : call to_real as cql_unbox_real;
@op object<cql_box> : call to_text as cql_unbox_text;
@op object<cql_box> : call to_blob as cql_unbox_blob;
@op object<cql_box> : call to_object as cql_unbox_object;
@op object<cql_box> : call type as cql_box_get_type;
```

### Cursor Access

#### Reading Column Metadata and Values

These pipeline operators provide generic access to cursor columns by index
position. They are primarily useful in macro contexts where cursors are passed
polymorphically without compile-time knowledge of their structure.

**Transformation:**
* `C:count` → `cql_cursor_column_count(C)` - Returns the number of columns in cursor C
* `C:type(n)` → `cql_cursor_column_type(C, n)` - Returns the type code of column n (e.g., CQL_DATA_TYPE_INT32)
* `C:get_int(n)` → `cql_cursor_get_int(C, n)` - Returns the value of column n as a nullable integer

**Purpose:** These operators enable writing generic cursor manipulation code
that works with any cursor shape. The `get_<type>` family returns nullable
values matching the underlying column type.

**Details:**
```
@op cursor : call count as cql_cursor_column_count;
@op cursor : call type as cql_cursor_column_type;
@op cursor : call get_bool as cql_cursor_get_bool;
@op cursor : call get_int as cql_cursor_get_int;
@op cursor : call get_long as cql_cursor_get_long;
@op cursor : call get_real as cql_cursor_get_real;
@op cursor : call get_text as cql_cursor_get_text;
@op cursor : call get_blob as cql_cursor_get_blob;
@op cursor : call get_object as cql_cursor_get_object;
```

### Whole Cursor Helpers

#### Cursor Conversions

These pipeline operators serialize cursor contents to/from blob format, enabling
cursor data to be stored or transmitted as binary data.

**Serialization:**
* `let my_blob := C:to_blob;` → `let my_blob := cql_cursor_to_blob(C);`
  - Converts cursor C's current row into a blob containing all column values
  - Returns NULL if serialization fails (e.g., cursor has no valid row)

**Deserialization:**
* `C:from_blob(my_blob);` → `cql_cursor_from_blob(C, my_blob);`
  - Populates cursor C's fields from the blob's serialized data
  - Throws an exception if the blob format doesn't match cursor C's shape

**Purpose:** These operations enable cursor data persistence, inter-process communication, or network transmission.

**Details:**
```
@op cursor : call to_blob as cql_cursor_to_blob;
@op cursor : call from_blob as cql_cursor_from_blob;
```

#### Cursor Formatting

The `:format` operator creates a human-readable string representation of a
cursor's current row, showing all column names and their values.

**Transformation:**
* `printf("C is: %s\n", C:format);` → `printf("C is: %s\n", cql_cursor_format(C));`

**Output Format:** Returns a string like `{id:123, name:"Alice", age:30}` with
each column shown as `name:value`. NULL values are shown as `NULL`, and blob
values show their length rather than content (e.g., `blob[128]`).

**Purpose:** Debugging and logging cursor contents without manually accessing each field.

**Details:**
```
@op cursor : call format as cql_cursor_format;
```

#### Cursor Difference

These pipeline operators compare two cursors with the same shape and identify
the first differing column.

**Transformation:**
* `C1:diff_index(C2)` → `cql_cursor_diff_index(C1, C2)` - Returns the zero-based column index of the first difference, or -1 if cursors are equal
* `C1:diff_col(C2)` → `cql_cursor_diff_col(C1, C2)` - Returns the column name of the first difference as a string, or NULL if cursors are equal
* `C1:diff_val(C2)` → `cql_cursor_diff_val(C1, C2)` - Returns a formatted string showing both values: `"column_name: value1 vs value2"`, or NULL if cursors are equal

**Purpose:** Testing and validation code that needs to identify specific differences between expected and actual cursor contents. Blob columns show lengths (e.g., `"data: blob[128] vs blob[256]"`) rather than full contents.

**Details:
```
@op cursor : call diff_col as cql_cursor_diff_col;
@op cursor : call diff_val as cql_cursor_diff_val;
@op cursor : call diff_index as cql_cursor_diff_index;
```

#### Cursor Hash

The `:hash` operator computes a hash value incorporating all columns in the
cursor's current row.

**Transformation:**
* `let hash := C:hash;` → `let hash := cql_cursor_hash(C);`

**Purpose:** Enables using cursor rows as hash table keys or detecting changes
in cursor contents. The hash includes all column values using a deterministic
algorithm.

**Details:
```
@op cursor : call hash as cql_cursor_hash;
```

#### Cursor Equality

The `:equals` operator performs a field-by-field comparison of two cursors with
the same shape.

**Transformation:**
* `if not C:equals(D) throw;` → `if not cql_cursors_equal(C, D) throw;`

**Purpose:** Testing and validation code that needs to verify cursor contents
match expected values. Returns true if all column values are equal (considering
NULL = NULL as equal), false otherwise.

**Details:
```
@op cursor : call equals as cql_cursors_equal;
```

### List Operations

These pipeline operators provide typed list operations for each primitive type.
CQL provides built-in list types (`cql_long_list`, `cql_real_list`,
`cql_string_list`, `cql_blob_list`, `cql_object_list`) that support indexed
access and dynamic growth.

**Transformations:**
* `list[index] := value;` → `cql_<type>_list_set_at(list, index, value);` - Updates element at index (will not grow the list; index must be < count)
* `value := list[index];` → `value := cql_<type>_list_get_at(list, index);` - Retrieves element at index (returns NULL if index out of bounds)
* `list:add(value);` → `cql_<type>_list_add(list, value);` - Appends value to the end of the list, growing it by one element
* `n_items := list:count;` → `n_items := cql_<type>_list_count(list);` - Returns the current number of elements in the list

**Purpose:** Type-safe dynamic arrays for each primitive type. The
`cql_long_list` type can hold bool, int, or long values.

**Details:**

The operations are symmetric for each list type:

*Long* (can also hold int and bool)
```
@op cql_long_list : array set as cql_long_list_set_at;
@op cql_long_list : array get as cql_long_list_get_at;
@op cql_long_list : call add as cql_long_list_add;
@op cql_long_list : get count as cql_long_list_count;
```

*Real*
```
@op cql_real_list : array set as cql_real_list_set_at;
@op cql_real_list : array get as cql_real_list_get_at;
@op cql_real_list : call add as cql_real_list_add;
@op cql_real_list : get count as cql_real_list_count;
```

*String*
```
@op cql_string_list : array set as cql_string_list_set_at;
@op cql_string_list : array get as cql_string_list_get_at;
@op cql_string_list : call add as cql_string_list_add;
@op cql_string_list : get count as cql_string_list_count;
```

*Blob*
```
@op cql_blob_list : array set as cql_blob_list_set_at;
@op cql_blob_list : array get as cql_blob_list_get_at;
@op cql_blob_list : call add as cql_blob_list_add;
@op cql_blob_list : get count as cql_blob_list_count;
```
*Object*
```
@op cql_object_list : array set as cql_object_list_set_at;
@op cql_object_list : array get as cql_object_list_get_at;
@op cql_object_list : call add as cql_object_list_add;
@op cql_object_list : get count as cql_object_list_count;
```

### Dictionary Operations

These pipeline operators provide typed dictionary operations for each primitive
type. CQL provides built-in dictionary types (`object<cql_long_dictionary>`,
`object<cql_real_dictionary>`, etc.) that map string keys to typed values.

**Transformations:**
* `dict:find(key)` → `cql_<type>_dictionary_find(dict, key);` - Retrieves the value for key, returns NULL if key not found
* `dict:add(key, value)` → `cql_<type>_dictionary_add(dict, key, value);` - Inserts or updates the mapping from key to value
* `dict[key] := value;` → `cql_<type>_dictionary_add(dict, key, value);` - Indexing syntax for add operation
* `value := dict[key];` → `value := cql_<type>_dictionary_find(dict, key);` - Indexing syntax for find operation

**Purpose:** Type-safe string-keyed hash tables for each primitive type. All dictionary types use string keys and store typed values.

**Details:**

The operations are symmetric for each dictionary type:

*Long* (can also hold int and bool)
```
@op object<cql_long_dictionary> : call add as cql_long_dictionary_add;
@op object<cql_long_dictionary> : call find as cql_long_dictionary_find;
@op object<cql_long_dictionary> : array set as cql_long_dictionary_add;
@op object<cql_long_dictionary> : array get as cql_long_dictionary_find;
```

*Real*
```
@op object<cql_real_dictionary> : call add as cql_real_dictionary_add;
@op object<cql_real_dictionary> : call find as cql_real_dictionary_find;
@op object<cql_real_dictionary> : array set as cql_real_dictionary_add;
@op object<cql_real_dictionary> : array get as cql_real_dictionary_find;
```

*String*
```
@op object<cql_string_dictionary> : call add as cql_string_dictionary_add;
@op object<cql_string_dictionary> : call find as cql_string_dictionary_find;
@op object<cql_string_dictionary> : array set as cql_string_dictionary_add;
@op object<cql_string_dictionary> : array get as cql_string_dictionary_find;
```

*Blob*
```
@op object<cql_blob_dictionary> : call add as cql_blob_dictionary_add;
@op object<cql_blob_dictionary> : call find as cql_blob_dictionary_find;
@op object<cql_blob_dictionary> : array set as cql_blob_dictionary_add;
@op object<cql_blob_dictionary> : array get as cql_blob_dictionary_find;
```

*Object*
```
@op object<cql_object_dictionary> : call add as cql_object_dictionary_add;
@op object<cql_object_dictionary> : call find as cql_object_dictionary_find;
@op object<cql_object_dictionary> : array set as cql_object_dictionary_add;
@op object<cql_object_dictionary> : array get as cql_object_dictionary_find;
```
