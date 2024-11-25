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

These can be extracted from `cql.y` to get an always current list and are largely self explanatory.
Each `@op` directive defines some pipeline shortcuts. These are discussed in [Chapter 8](../08_functions.md)

### Boxing and Unboxing

Boxing operator for each primitive type, example:
  * `expr:box`

Details:
```
@op bool : call box as cql_box_bool;
@op int  : call box as cql_box_int;
@op long : call box as cql_box_long;
@op real : call box as cql_box_real;
@op text : call box as cql_box_text;
@op blob : call box as cql_box_blob;
@op object : call box as cql_box_object;
```

Unboxing operator for each primitive type, example:
* `my_box:to_bool`


Details:
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

Reading values out of a cursor, most these are really only useful in the context of a macro
because that is the only way you could polymorphically pass a cursor around but here they are.

Examples:
* `C:count` -- returns count of items
* `C:type(n)` -- returns type code of column n
* `C:get_int(n)` -- returns the int at column n or null if not an int (or null)


Details:
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

Converts to or from a blob, examples:

* `let my_blob := C:to_blob`
* `C:to_blob(my_blob)`
* `C:from_blob(my_blob)`


Details:
```
@op cursor : call to_blob as cql_cursor_to_blob;
@op cursor : call from_blob as cql_cursor_from_blob;
```

#### Cursor Formatting

Creates a string representation of the cursor with field names and values, useful for debugging, example:
* `printf("C is: %s\n", C:format);`

```
@op cursor : call format as cql_cursor_format;
```

#### Cursor Difference

Reports the first difference between two cursors, or null if none.  The first
provides the column name and the second provides the differing column and values
all in text form.  Blob values are not emitted, only the length.


Details:
```
@op cursor : call diff_col as cql_cursor_diff_col;
@op cursor : call diff_val as cql_cursor_diff_val;
```

#### Cursor Hash

Hashes all fields of the cursor regardless of what they may be, example:
* `let hash := C:hash;`


Details:
```
@op cursor : call hash as cql_cursor_hash;
```

#### Cursor Equality

Compares two cursors for equality, example:
* `if not C:equals(D) throw;`

Details:
```
@op cursor : call equals as cql_cursors_equal;
```

### List operations

List operations for each primitive type, examples:
* `list[index] := value` (will not grow the list)
* `value := list[index]`
* `list:add(value)`
* `list:count`

Details:
```
@op cql_string_list : array set as cql_string_list_set_at;
@op cql_string_list : array get as cql_string_list_get_at;
@op cql_string_list : call add as cql_string_list_add;
@op cql_string_list : get count as cql_string_list_count;

@op cql_blob_list : array set as cql_blob_list_set_at;
@op cql_blob_list : array get as cql_blob_list_get_at;
@op cql_blob_list : call add as cql_blob_list_add;
@op cql_blob_list : get count as cql_blob_list_count;

@op cql_long_list : array set as cql_long_list_set_at;
@op cql_long_list : array get as cql_long_list_get_at;
@op cql_long_list : call add as cql_long_list_add;
@op cql_long_list : get count as cql_long_list_count;

@op cql_real_list : array set as cql_real_list_set_at;
@op cql_real_list : array get as cql_real_list_get_at;
@op cql_real_list : call add as cql_real_list_add;
@op cql_real_list : get count as cql_real_list_count;
```

### Dictionary Operations

Dicitonary operations for each primitive type, examples:
* `dict:find(x)`
* `dict:add(x)`
* `dict[x] := val`
* `val := dict[x]`


Details:
```
-- string dictionary 'add', 'find' and [] get and set
--
@op object<cql_string_dictionary> : call add as cql_string_dictionary_add;
@op object<cql_string_dictionary> : call find as cql_string_dictionary_find;
@op object<cql_string_dictionary> : array set as cql_string_dictionary_add;
@op object<cql_string_dictionary> : array get as cql_string_dictionary_find;

-- long dictionary 'add', 'find' and [] get and set
--
@op object<cql_long_dictionary> : call add as cql_long_dictionary_add;
@op object<cql_long_dictionary> : call find as cql_long_dictionary_find;
@op object<cql_long_dictionary> : array set as cql_long_dictionary_add;
@op object<cql_long_dictionary> : array get as cql_long_dictionary_find;

-- real dictionary 'add', 'find' and [] get and set
--
@op object<cql_real_dictionary> : call add as cql_real_dictionary_add;
@op object<cql_real_dictionary> : call find as cql_real_dictionary_find;
@op object<cql_real_dictionary> : array set as cql_real_dictionary_add;
@op object<cql_real_dictionary> : array get as cql_real_dictionary_find;

-- object dictionary 'add', 'find' and [] get and set
--
@op object<cql_object_dictionary> : call add as cql_object_dictionary_add;
@op object<cql_object_dictionary> : call find as cql_object_dictionary_find;
@op object<cql_object_dictionary> : array set as cql_object_dictionary_add;
@op object<cql_object_dictionary> : array get as cql_object_dictionary_find;

-- blob dictionary 'add', 'find' and [] get and set
--
@op object<cql_blob_dictionary> : call add as cql_blob_dictionary_add;
@op object<cql_blob_dictionary> : call find as cql_blob_dictionary_find;
@op object<cql_blob_dictionary> : array set as cql_blob_dictionary_add;
@op object<cql_blob_dictionary> : array get as cql_blob_dictionary_find;
```

