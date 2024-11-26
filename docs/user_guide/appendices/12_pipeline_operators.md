---
title: "Appendix 12: Pipeline Overloads"
weight: 12
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

Each of the pipeline shortcuts below can be extracted from `cql.y` to get an
always current list (`grep @op cql.y`). They are largely self explanatory as
they always map some simple shortcut to a standard cql function with each `@op`
directive defining one such pipeline shortcut. The form of these is discussed
more generally in [Chapter 8](../08_functions.md). Below are the particulars of
the builtin `@op` directives.

>Note: `@op` directives can be overridden and therefore customized to whatever
>is locally helpful. The function calls resulting from rewrites directed by
>`@op` are still semantically checked so there are no additional type-safety
>issues for doing so.

### Boxing and Unboxing

There is a shortcut for the boxing operation for each primitive type

**Examples:**
  * `let obj := expr:box;`

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

There is a shortcut to (try to) unbox for each primitive type.

**Examples:**
* `nullable_bool := my_box:to_bool;`
* `notnull_long := my_box:to_long:ifnull_throw;`

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

These are for reading values out of a cursor, most these are really only useful
in the context of a macro because that is the only way you could polymorphically
pass a cursor around.

**Examples:**
* `let column_count := C:count;`
* `let column_type := C:type(n);`
* `let an_integer := C:get_int(n);` (could be null)


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

These two shortcuts convert cursor contents to a blob or the reverse, extracting
the blob into the cursor.  Both have failure modes.

**Examples:**
* `let my_blob := C:to_blob`
* `C:to_blob(my_blob)`
* `C:from_blob(my_blob)`

**Details:**
```
@op cursor : call to_blob as cql_cursor_to_blob;
@op cursor : call from_blob as cql_cursor_from_blob;
```

#### Cursor Formatting

Creates a string representation of the cursor with field names and values, useful for debugging.

**Examples:**
* `printf("C is: %s\n", C:format);`

**Details:**
```
@op cursor : call format as cql_cursor_format;
```

#### Cursor Difference

Reports the first difference between two cursors, or null if none.  The first
provides the column name and the second provides the differing column and values
all in text form.  Blob values are not emitted, only the length.

**Examples:**
* `printf("first difference: %s", C1:diff_val(C2));`

**Details:**
```
@op cursor : call diff_col as cql_cursor_diff_col;
@op cursor : call diff_val as cql_cursor_diff_val;
```

#### Cursor Hash

Hashes all fields of the cursor to give one overall hash.

**Examples:**
* `let hash := C:hash;`

**Details:**
```
@op cursor : call hash as cql_cursor_hash;
```

#### Cursor Equality

Compares two cursors for equality.

**Examples:**
* `if not C:equals(D) throw;`

**Details:**
```
@op cursor : call equals as cql_cursors_equal;
```

### List operations

List operations for each primitive type, examples:
* `list[index] := value;` (will not grow the list)
* `value := list[index];`
* `list:add(value);`
* `n_items := list:count;`

**Details:**

The details are totally symmetric for each list type offering `add`, `count`,
and array get/set.

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

There are dictionaries for each primitive type with simple dictionary shortcuts.

**Examples:**
* `dict:find(x)`
* `dict:add(x)`
* `dict[x] := val`
* `val := dict[x]`


**Details:** 

The details are totally symmetric for each dictionary type offering
`add`, `find` and array get/set.

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
