---
title: "Part 11: JSON Schema and Python Code Generators"
weight: 11
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## Overview

The CQL compiler can emit a JSON schema representation of CQL code using the `--rt json_schema` option. This JSON output is a complete, stable representation of all the schema elements, procedures, and type information in the CQL source. Several Python utilities consume this JSON to generate language bindings, diagrams, and other artifacts.

This chapter explains how these Python code generators work internally, providing a foundation for understanding, modifying, or creating new generators.

## The JSON Schema Contract

The JSON schema is the **stable contract** between the CQL compiler and external tools. While the Python scripts are simple sample code subject to change, the JSON format itself evolves in a backward-compatible way.

### Key JSON Structures

The JSON schema contains several top-level arrays and objects:

**Procedure Categories:**
* `queries` - SELECT procedures that return result sets (single SELECT statement, no OUT params, no fragments)
* `inserts` - Simple INSERT procedures (single-row VALUES clause, no OUT params, no fragments)
* `generalInserts` - Complex INSERT procedures (multi-row VALUES, INSERT...SELECT, WITH, UPSERT, no OUT params, no fragments)
* `updates` - UPDATE procedures (single UPDATE statement, no OUT params, no fragments)
* `deletes` - DELETE procedures (single DELETE statement, no OUT params, no fragments)
* `general` - All other procedures (OUT parameters, multiple statements, shared fragments, or complex logic)

These categories are determined by the compiler's analysis of procedure simplicity. A procedure must have no OUT/INOUT parameters, contain exactly one statement, and not use shared fragments to qualify for the specific categories. The categorization enables richer metadata for simple cases while providing basic information for complex procedures. See the [JSON Output chapter](../user_guide/13_json_output.md#procedures) in the user guide for detailed information about procedure categorization rules and the specific fields available in each category.

**Schema Elements:**
* `tables` - All table definitions
* `views` - All view definitions
* `regions` - Schema regions for deployment management
* `adHocMigrationProcs` - Ad-hoc migration procedures

**Type Information:**
* `enums` - Enumerated types
* `declareProcs` - External procedure declarations
* `declareFuncs` - External function declarations
* `interfaces` - Interface definitions

Each procedure object contains:
* `name` - The procedure name
* `canonicalName` - The name with parameter signature (for overloads)
* `args` - Array of arguments with name, type, binding (in/out/inout), and nullable info
* `attributes` - Array of attribute strings (e.g., `cql:private`)
* `usesDatabase` - Boolean indicating if the procedure accesses SQLite
* `projection` - Result set structure (if the procedure returns rows)
* `hasSelectResult` - Boolean for whether it has a SELECT result
* `hasOutResult` - Boolean for whether it has OUT parameters
* `hasOutUnionResult` - Boolean for OUT UNION result

## Common Pattern: Type Mapping Dictionaries

All language binding generators follow a similar pattern for type mapping. They maintain dictionaries that map CQL types to target language types.

### Example from cqljava.py

```python
# Java types for not null cql types
notnull_types = {}
notnull_types["bool"] = "boolean"
notnull_types["integer"] = "int"
notnull_types["long"] = "long"
notnull_types["real"] = "double"
notnull_types["object"] = "Object"
notnull_types["blob"] = "byte[]"
notnull_types["text"] = "String"

# Java types for nullable cql types
nullable_types = {}
nullable_types["bool"] = "Boolean"
nullable_types["integer"] = "Integer"
nullable_types["long"] = "Long"
nullable_types["real"] = "Double"
nullable_types["object"] = "Object"
nullable_types["blob"] = "byte[]"
nullable_types["text"] = "String"
```

The distinction between nullable and non-nullable types is crucial because:
* Primitive types in Java/C# cannot be null
* CQL's nullable primitives must map to boxed/reference types
* Reference types (blob, text, object) are always nullable in the target language

### Reference Type Detection

Many generators need to know which types require special memory management:

```python
is_ref_type = {}
is_ref_type["bool"] = False
is_ref_type["integer"] = False
is_ref_type["long"] = False
is_ref_type["real"] = False
is_ref_type["object"] = True
is_ref_type["blob"] = True
is_ref_type["text"] = True
```

Reference types require:
* Release/retain logic in cleanup code
* Special marshaling across language boundaries
* Null checking before use

## Schema Visualization: cqljson.py

This tool processes schema information to create GraphViz diagrams and SQL files.

### Main Entry Points

The tool supports multiple output modes selected via command-line flags:
* `--erd` - Entity-relationship diagram
* `--table_diagram` - Table structure diagram
* `--region_diagram` - Schema region dependencies
* `--sql` - SQL database creation script

### Universe Filtering Algorithm

The "universe" filtering is a key feature that allows focusing on specific parts of large schemas:

```python
def compute_universe(data, tables, targets):
    universe = set()
    
    for target in targets:
        # Handle removal (prefixed with -)
        if target.startswith('-'):
            table_name = target[1:]
            universe.discard(table_name)
            continue
            
        # Parse modifiers (+fks, +refs, +graph)
        if '+fks' in target:
            add_table_with_fks(universe, tables, table_name)
        elif '+refs' in target:
            add_table_with_refs(universe, tables, table_name)
        elif '+graph' in target:
            add_table_with_graph(universe, tables, table_name)
        else:
            universe.add(table_name)
```

The algorithm:
1. Starts with an empty set
2. Processes targets in order (allowing cumulative additions)
3. Handles removal with `-` prefix
4. Recursively follows foreign keys for `+fks`
5. Recursively follows reverse references for `+refs`
6. Combines both directions for `+graph`

### ERD Generation

The ERD generator creates a GraphViz dot file with:

**Table Nodes:**
```python
def emit_erd(data, universe, tables):
    for t_name in universe:
        t = tables[t_name]
        pk = compute_pk(t)
        colinfo = compute_colinfo(t)
        
        # Emit HTML table with columns
        # Primary keys listed first
        # Then separator "---"
        # Then non-PK columns
        # Each column shows: name, type, PK/FK/UK markers
```

**Foreign Key Edges:**
```python
for fk in t["foreignKeys"]:
    reftable = fk["referenceTable"]
    portcol = fk["columns"][0]
    print(f"{t_name}:{portcol} -> {reftable}")
```

The output uses GraphViz's HTML-like labels to create table-shaped nodes with ports for each column, allowing foreign key arrows to connect to specific columns.

## Java JNI Generator: cqljava.py

This generator creates two outputs:
1. Java wrapper classes (one pass)
2. C JNI implementation code (second pass with `--emit_c`)

### Java Class Generation

For each procedure, the generator creates a nested class:

```python
def emit_proc_java_class(proc):
    p_name = proc["name"]
    args = proc["args"]
    projection = proc.get("projection", [])
    
    # Emit class declaration
    print(f"  public static class {p_name} extends CQLViewModel {{")
    
    # Emit fields for result columns
    for col in projection:
        java_type = get_java_type(col["type"], col["isNotNull"])
        print(f"    public {java_type} {col['name']};")
    
    # Emit constructor
    # Emit fetch method
    # Emit column getters
```

The fetch method signature is built from the procedure's arguments:

```python
def emit_fetch_method(proc):
    in_args = [arg for arg in proc["args"] if arg["binding"] in ["in", "inout"]]
    
    params = []
    for arg in in_args:
        java_type = get_java_type(arg["type"], arg["isNotNull"])
        params.append(f"{java_type} {arg['name']}")
    
    print(f"    public static {p_name}[] fetch(CQLDb db, {', '.join(params)}) {{")
```

**Generated Java Class (Pseudocode):**

For a CQL procedure like:
```sql
CREATE PROC get_users(min_age INTEGER NOT NULL)
BEGIN
  SELECT id, name, age FROM users WHERE age >= min_age;
END;
```

The Java generator produces:
```java
public static class get_users extends CQLViewModel {
  // Result set fields
  public Long id;
  public String name;
  public Integer age;
  
  // Fetch method
  public static get_users[] fetch(CQLDb db, int min_age) {
    // Call native JNI method
    long resultSetPtr = nativeFetch(db.getHandle(), min_age);
    
    // Read rows and populate array
    int rowCount = getRowCount(resultSetPtr);
    get_users[] results = new get_users[rowCount];
    
    for (int i = 0; i < rowCount; i++) {
      results[i] = new get_users();
      results[i].id = getColumnLong(resultSetPtr, i, 0);
      results[i].name = getColumnString(resultSetPtr, i, 1);
      results[i].age = getColumnInteger(resultSetPtr, i, 2);
    }
    
    releaseResultSet(resultSetPtr);
    return results;
  }
  
  // Column getters
  public Long getId() { return id; }
  public String getName() { return name; }
  public Integer getAge() { return age; }
  
  // Native JNI declaration
  private static native long nativeFetch(long dbHandle, int min_age);
}
```

### C JNI Implementation

The C code generation involves several steps:

**1. Unboxing Helpers:**

For nullable primitive types (Integer, Long, etc.), the generator emits unboxing functions:

```python
def emit_c_helpers():
    print("""
static jint UnboxInteger(JNIEnv *env, jobject boxedInteger) {
    jclass integerClass = (*env)->GetObjectClass(env, boxedInteger);
    jmethodID intValueMethodID = (*env)->GetMethodID(env, integerClass, "intValue", "()I");
    return (*env)->CallIntMethod(env, boxedInteger, intValueMethodID);
}
    """)
```

**2. Result Metadata:**

The generator builds metadata describing the return type structure:

```python
def emit_proc_c_metadata(proc):
    # Count fields and build structure definition
    field_count = 0
    ref_field_count = 0
    
    # Non-reference fields go first
    for arg in out_args:
        if not is_ref_type[arg["type"]]:
            field_count += 1
            # emit field in struct
    
    # Reference fields go last (for easy cleanup)
    for arg in out_args:
        if is_ref_type[arg["type"]]:
            field_count += 1
            ref_field_count += 1
            # emit field in struct
```

Reference types must be grouped together at the end of the struct because the CQL runtime's cleanup code uses `cql_finalize_row` which releases all reference types from a given offset to the end.

**Generated C JNI Code (Pseudocode):**

For the same `get_users` procedure, the C implementation looks like:
```c
// Result structure
typedef struct get_users_row {
  cql_int64 id;        // Non-reference types first
  cql_int32 age;
  cql_string_ref name; // Reference types last for cleanup
} get_users_row;

// JNI implementation
JNIEXPORT jlong JNICALL Java_get_1users_nativeFetch
  (JNIEnv *env, jclass cls, jlong dbHandle, jint min_age)
{
  sqlite3 *db = (sqlite3 *)dbHandle;
  get_users_result_set_ref result_set = NULL;
  
  // Call CQL procedure
  cql_code rc = get_users_fetch_results(db, &result_set, min_age);
  if (rc != SQLITE_OK) {
    return 0; // Error
  }
  
  // Return result set pointer to Java
  return (jlong)result_set;
}

// Column accessor example
JNIEXPORT jstring JNICALL Java_getColumnString
  (JNIEnv *env, jclass cls, jlong resultSetPtr, jint row, jint col)
{
  get_users_result_set_ref result_set = (get_users_result_set_ref)resultSetPtr;
  cql_result_set_get_data(result_set, row);
  
  get_users_row *data = get_users_get_data(result_set);
  cql_string_ref str = data[row].name;
  
  if (!str) return NULL;
  return (*env)->NewStringUTF(env, str->ptr);
}
```

**3. JNI Function Body:**

```python
def emit_jni_function(proc):
    # Extract arguments from Java objects
    for arg in in_args:
        if arg["isNotNull"]:
            # Direct access for non-null primitives
        else:
            # Check for null, then unbox if needed
    
    # Call CQL procedure
    print(f"  {proc['name']}(_db, ...args...);")
    
    # Marshal results back to Java
    for col in projection:
        # Create Java objects from C results
        # Handle null values appropriately
    
    # Cleanup
    # Release reference types
```

## C# Interop Generator: cqlcs.py

The C# generator follows a similar two-pass approach but uses P/Invoke instead of JNI.

### Key Differences from Java

**Nullable Value Types:**

C# has built-in nullable value types (`int?`, `bool?`) which simplifies the type mapping:

```python
nullable_types["bool"] = "bool?"
nullable_types["integer"] = "int?"
nullable_types["long"] = "long?"
nullable_types["real"] = "double?"
```

**Split Types for Result Sets:**

For complex result types, C# uses a split representation:

```python
split_types = {}  # Maps type to split representation
split_nullables = {}  # Tracks nullable status
```

**P/Invoke Marshaling:**

The C code uses simpler marshaling than JNI:

```python
def emit_csharp_pinvoke(proc):
    print(f"[DllImport(\"cqlinterop\")]")
    print(f"public static extern int {proc['name']}(...);")
```

Reference types are marshaled using `IntPtr` and converted with runtime helpers.

**Generated C# Class (Pseudocode):**

For the same `get_users` procedure:
```csharp
public class get_users {
  // Result set properties
  public long? id { get; set; }
  public string name { get; set; }
  public int? age { get; set; }
  
  // P/Invoke declaration
  [DllImport("cqlinterop", CallingConvention = CallingConvention.Cdecl)]
  private static extern int get_users_fetch_results(
    IntPtr db,
    out IntPtr result_set,
    int min_age);
  
  // Fetch method
  public static get_users[] Fetch(CQLDatabase db, int min_age) {
    IntPtr resultSetPtr;
    int rc = get_users_fetch_results(db.Handle, out resultSetPtr, min_age);
    
    if (rc != 0) {
      throw new CQLException($"Query failed with code {rc}");
    }
    
    // Read result set
    int rowCount = cql_result_set_get_count(resultSetPtr);
    var results = new get_users[rowCount];
    
    for (int i = 0; i < rowCount; i++) {
      results[i] = new get_users {
        id = GetNullableLong(resultSetPtr, i, 0),
        name = GetString(resultSetPtr, i, 1),
        age = GetNullableInt(resultSetPtr, i, 2)
      };
    }
    
    cql_result_set_release(resultSetPtr);
    return results;
  }
  
  // Helper methods for marshaling
  private static long? GetNullableLong(IntPtr rs, int row, int col) {
    if (cql_result_set_get_is_null(rs, row, col))
      return null;
    return cql_result_set_get_int64(rs, row, col);
  }
  
  private static string GetString(IntPtr rs, int row, int col) {
    IntPtr strPtr = cql_result_set_get_string(rs, row, col);
    if (strPtr == IntPtr.Zero)
      return null;
    return Marshal.PtrToStringAnsi(strPtr);
  }
}
```

## Objective-C Generators

There are two Objective-C generators with different approaches:

### cqlobjc.py (Core Foundation)

This generator creates Objective-C functions for the CF-based runtime:

**Type Mapping:**
```python
objc_notnull_types["text"] = "NSString *_Nonnull"
objc_nullable_types["text"] = "NSString *_Nullable"
objc_notnull_types["blob"] = "NSData *_Nonnull"
```

**Conversion Helpers:**
```python
notnull_conv["text"] = "(__bridge NSString *)"
notnull_conv["blob"] = "(__bridge NSData *)"
```

The `__bridge` casts are necessary because the CF runtime uses `CFStringRef` and `CFDataRef` internally, which need bridging to `NSString` and `NSData`.

### cql_objc_full.py (Full Wrappers)

This creates complete Objective-C classes with properties:

```python
def emit_objc_class(proc):
    # @interface with properties
    for col in projection:
        objc_type = get_objc_type(col["type"], col["isNotNull"])
        print(f"@property (nonatomic, strong) {objc_type} {col['name']};")
    
    # Class method for fetching
    print(f"+ (NSArray<{proc['name']} *> *)fetch:(sqlite3 *)db ...;")
```

The implementation file (`.m`) contains:
* The fetch method that calls the CQL procedure
* Row-by-row result set reading using CQL result set APIs
* Object creation and property setting
* Reference counting and cleanup

**Generated Objective-C Class (Pseudocode):**

For the `get_users` procedure:
```objc
// Header file (.h)
@interface get_users : NSObject

@property (nonatomic, strong) NSNumber *_Nullable id;
@property (nonatomic, strong) NSString *_Nullable name;
@property (nonatomic, strong) NSNumber *_Nullable age;

+ (NSArray<get_users *> *_Nonnull)fetch:(sqlite3 *_Nonnull)db
                                 minAge:(int)min_age;

@end

// Implementation file (.m)
@implementation get_users

+ (NSArray<get_users *> *)fetch:(sqlite3 *)db minAge:(int)min_age {
  get_users_result_set_ref result_set = NULL;
  
  // Call CQL procedure
  cql_code rc = get_users_fetch_results(db, &result_set, min_age);
  if (rc != SQLITE_OK) {
    return @[];
  }
  
  // Read rows
  cql_int32 count = get_users_result_count(result_set);
  NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
  
  for (cql_int32 i = 0; i < count; i++) {
    get_users *row = [[get_users alloc] init];
    
    // Get column values (with CF bridging)
    row.id = get_users_get_id_is_null(result_set, i) ? nil :
             @(get_users_get_id_value(result_set, i));
    
    row.name = get_users_get_name_is_null(result_set, i) ? nil :
               (__bridge NSString *)get_users_get_name_value(result_set, i);
    
    row.age = get_users_get_age_is_null(result_set, i) ? nil :
              @(get_users_get_age_value(result_set, i));
    
    [results addObject:row];
  }
  
  cql_result_set_release(result_set);
  return results;
}

@end
```

## SQLite Extension Generator: cqlsqlite3extension.py

This generator creates table-valued functions and scalar functions that can be loaded into SQLite.

### Indentation Management

The extension generator uses a sophisticated indentation system:

```python
indentation_state = {'value': 0, 'pending_line': False}

def indent(indentation=1):
    if not indentation_state['pending_line']:
        indentation_state["value"] += indentation

def indented_print(*args, **kwargs):
    text = " ".join(map(str, args))
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if i > 0 or not indentation_state['pending_line']:
            print("  " * indentation_state['value'], end="")
        print(line, ...)
```

This allows the generator to emit well-formatted C code without manually tracking indentation levels.

### Procedure Classification

The generator handles procedures differently based on whether they return results:

```python
has_projection = 'projection' in proc

if has_projection:
    # Create table-valued function (TVF)
    # Table definition includes result columns + hidden input columns
    table_decl = f"CREATE TABLE {proc_name}({cols})"
    register_cql_rowset_tvf(db, aux, proc_name)
else:
    # Create scalar function
    sqlite3_create_function(db, proc_name, arg_count, ...)
```

### Argument Marshaling

For table-valued functions, the generator emits code to extract arguments from `sqlite3_value` objects:

```python
def emit_argument_extraction(arg):
    c_type = cql_types[is_nullable][arg["type"]]
    getter = sqlite3_value_getter[is_nullable][arg["type"]]
    
    print(f"{c_type} {arg['name']};")
    print(f"{arg['name']} = {getter}(argv[{index}]);")
```

The getter functions handle:
* Type checking (ensuring SQLite value type matches expected type)
* NULL handling (for nullable parameters)
* Reference counting (for blobs, text, objects)

### Result Marshaling

Results are set using SQLite result setters:

```python
def emit_result_setting(col):
    setter = sqlite3_result_setter[is_nullable][col["type"]]
    
    if is_ref_type[col["type"]]:
        # Reference types need special handling
        print(f"{setter}(context, result.{col['name']});")
    else:
        # Primitive types are direct
        print(f"{setter}(context, result.{col['name']});")
```

### Extension Initializer

The extension entry point registers all procedures:

```python
def emit_extension_initializer(data):
    print("int sqlite3_cqlextension_init(sqlite3 *db, ...) {")
    
    for proc in all_procedures:
        if has_projection:
            print(f"  aux = cql_rowset_create_aux_init(call_{proc_name}, ...)
            print(f"  register_cql_rowset_tvf(db, aux, \"{proc_name}\");")
        else:
            print(f"  sqlite3_create_function(db, \"{proc_name}\", ...);")
    
    print("}")
```

This creates a loadable extension that can be used with `.load` in the SQLite shell.

**Generated SQLite Extension (Pseudocode):**

For the `get_users` procedure, the extension generator creates:
```c
// Table-valued function implementation
static int get_users_tvf(
  sqlite3_vtab_cursor *cursor,
  int argc, sqlite3_value **argv)
{
  // Extract argument from SQLite value
  cql_int32 min_age = sqlite3_value_int(argv[0]);
  
  // Call CQL procedure
  get_users_result_set_ref result_set = NULL;
  cql_code rc = get_users_fetch_results(
    cursor->db, &result_set, min_age);
  
  if (rc != SQLITE_OK) {
    return rc;
  }
  
  // Store result set in cursor
  cursor->result_set = result_set;
  cursor->row_index = 0;
  return SQLITE_OK;
}

// Column accessor
static int get_users_column(
  sqlite3_vtab_cursor *cursor,
  sqlite3_context *context,
  int column)
{
  get_users_result_set_ref rs = cursor->result_set;
  int row = cursor->row_index;
  
  switch (column) {
    case 0: // id column
      if (get_users_get_id_is_null(rs, row)) {
        sqlite3_result_null(context);
      } else {
        sqlite3_result_int64(context, 
          get_users_get_id_value(rs, row));
      }
      break;
      
    case 1: // name column
      if (get_users_get_name_is_null(rs, row)) {
        sqlite3_result_null(context);
      } else {
        cql_string_ref name = get_users_get_name_value(rs, row);
        sqlite3_result_text(context, name->ptr, -1, SQLITE_TRANSIENT);
      }
      break;
      
    case 2: // age column
      if (get_users_get_age_is_null(rs, row)) {
        sqlite3_result_null(context);
      } else {
        sqlite3_result_int(context,
          get_users_get_age_value(rs, row));
      }
      break;
  }
  return SQLITE_OK;
}

// Extension initializer
int sqlite3_cqlextension_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi)
{
  SQLITE_EXTENSION_INIT2(pApi);
  
  // Register table-valued function
  cql_rowset_aux *aux = cql_rowset_create_aux_init(
    get_users_tvf,
    get_users_column,
    /* ... other callbacks ... */);
  
  register_cql_rowset_tvf(db, aux, "get_users");
  
  return SQLITE_OK;
}
```

Usage in SQLite:
```sql
.load ./cqlextension
SELECT * FROM get_users(25);
-- Returns all users with age >= 25
```

## Common Implementation Patterns

### Command-Line Argument Processing

All generators parse command-line arguments consistently:

```python
cmd_args = {}
cmd_args["package"] = ""
cmd_args["class"] = ""
cmd_args["cql_header"] = ""

for i, arg in enumerate(sys.argv):
    if arg == "--package" and i + 1 < len(sys.argv):
        cmd_args["package"] = sys.argv[i + 1]
    elif arg == "--class" and i + 1 < len(sys.argv):
        cmd_args["class"] = sys.argv[i + 1]
```

### JSON Loading

All tools load JSON from the first non-option argument or stdin:

```python
if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
    with open(sys.argv[1]) as f:
        data = json.load(f)
else:
    data = json.load(sys.stdin)
```

### Attribute Filtering

Procedures can be marked with attributes that affect generation:

```python
attributes = proc["attributes"]

# Skip private procedures
if "cql:private" in attributes:
    continue

# Skip suppressed result sets
if "cql:suppress_result_set" in attributes:
    continue

# Skip procedures without getters
if "cql:suppress_getters" in attributes:
    continue
```

Common attributes:
* `cql:private` - Don't generate public interface
* `cql:suppress_result_set` - Don't create result set wrapper
* `cql:suppress_getters` - Don't create column getter functions
* `cql:vault_sensitive` - Mark as containing sensitive data

### Binding Classification

Arguments are classified by their binding:

```python
in_args = [arg for arg in proc["args"] if arg["binding"] == "in"]
out_args = [arg for arg in proc["args"] if arg["binding"] == "out"]
inout_args = [arg for arg in proc["args"] if arg["binding"] == "inout"]

# Often need all inputs (in + inout)
input_args = [arg for arg in proc["args"] 
              if arg["binding"] in ["in", "inout"]]

# And all outputs (out + inout)
output_args = [arg for arg in proc["args"] 
               if arg["binding"] in ["out", "inout"]]
```

### Error Handling Patterns

Generated code includes error checking:

```python
# Check for database errors
if rc != SQLITE_OK:
    return rc;

# Check for null arguments (when not expected)
if (arg == NULL && !is_nullable):
    return error_code;

# Check return codes from CQL procedures
rc = procedure_name(db, ...);
if (rc != SQLITE_OK) {
    cleanup();
    return rc;
}
```

## Creating a New Generator

To create a new language binding generator:

### 1. Define Type Mappings

```python
# Your language's type system
target_types_notnull = {}
target_types_nullable = {}
is_ref_type = {}

# Map each CQL type
target_types_notnull["bool"] = "YourBoolType"
target_types_notnull["integer"] = "YourIntType"
# ... etc
```

### 2. Parse JSON Schema

```python
import json
import sys

data = json.load(sys.stdin)

for proc in data["queries"]:
    generate_query_wrapper(proc)

for proc in data["general"]:
    generate_general_wrapper(proc)
```

### 3. Emit Wrapper Code

```python
def generate_wrapper(proc):
    # Extract procedure metadata
    name = proc["name"]
    args = proc["args"]
    projection = proc.get("projection", [])
    
    # Generate entry point
    emit_function_header(name, args)
    
    # Generate argument marshaling
    for arg in args:
        emit_marshal_arg(arg)
    
    # Call CQL procedure
    emit_cql_call(name, args)
    
    # Generate result marshaling
    if projection:
        emit_result_marshaling(projection)
    
    # Generate cleanup
    emit_cleanup(args)
```

### 4. Handle Nullable Types

```python
def get_type(cql_type, is_not_null):
    if is_not_null:
        return target_types_notnull[cql_type]
    else:
        return target_types_nullable[cql_type]
```

### 5. Manage Reference Counting

```python
def emit_cleanup(args):
    ref_args = [arg for arg in args if is_ref_type[arg["type"]]]
    
    for arg in ref_args:
        print(f"release_{arg['type']}({arg['name']});")
```

### 6. Test Thoroughly

Create test procedures with:
* All CQL types (bool, integer, long, real, text, blob, object)
* Nullable and non-nullable variants
* IN, OUT, and INOUT parameters
* Result sets with multiple rows
* NULL values in results
* Error conditions

## Best Practices for Generator Development

### Keep It Simple

These tools are intentionally simple. Don't add complex features that make the code hard to understand or modify. If you need sophisticated features, fork the tool and maintain your own version.

### Emit Readable Code

Generated code should be:
* Properly indented
* Include comments explaining non-obvious logic
* Use clear variable names
* Follow target language conventions

### Preserve Type Safety

Even when crossing language boundaries:
* Use the strongest possible types
* Check for nulls where required
* Validate array bounds
* Handle errors explicitly

### Test Edge Cases

* Empty result sets
* Single-row result sets
* NULL values in every position
* Very long strings
* Binary data (blobs) with embedded nulls
* Unicode text
* Large integers (long type)
* Floating point special values (NaN, Infinity)

### Document Limitations

If your generator doesn't support certain CQL features:
* Document the limitations clearly
* Skip unsupported procedures with clear error messages
* Consider emitting comments in the output noting unsupported features

## Debugging Generated Code

### Enable Verbose Output

Add verbosity flags to your generator:

```python
cmd_args["verbose"] = False

if "--verbose" in sys.argv:
    cmd_args["verbose"] = True

def debug_print(msg):
    if cmd_args["verbose"]:
        sys.stderr.write(f"DEBUG: {msg}\n")
```

### Emit Comments in Generated Code

```python
print(f"// Procedure: {proc['name']}")
print(f"// Arguments: {len(args)}")
print(f"// Result columns: {len(projection)}")
```

### Test with Simple Examples First

Start with:
```sql
CREATE PROC simple_test()
BEGIN
  SELECT 1 as one, 2 as two;
END;
```

Then progressively add:
* Arguments
* Multiple rows
* Nullable types
* Reference types
* Error handling

### Compare with Working Generators

When in doubt, check how the Java or C# generators handle a similar case. They're well-tested and demonstrate correct patterns.

## Summary

The Python JSON generators demonstrate how CQL's stable JSON schema enables language interoperability. Key takeaways:

1. **JSON is the contract** - It's stable and versioned, unlike the generators
2. **Type mapping is central** - Map CQL types correctly to target language types
3. **Handle nullability carefully** - Most bugs involve incorrect null handling
4. **Reference types need cleanup** - Don't leak memory
5. **Keep generators simple** - They're examples and starting points
6. **Test thoroughly** - Edge cases reveal bugs
7. **Fork when needed** - Customize for your specific needs

These generators show that adding a new language binding requires relatively little code (typically 200-800 lines of Python) when you understand the JSON schema structure and follow established patterns.
