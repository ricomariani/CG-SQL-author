---
title: "Appendix 13: Python JSON Utilities and Language Integrations"
weight: 13
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

## Overview

CQL provides several Python utilities that process the JSON schema output to enable integration with different programming ecosystems and to generate useful visualizations. **These utilities are simple, illustrative sample code that is subject to change.** They demonstrate patterns and techniques but are not intended to be production-ready solutions without customization.

These sample tools serve two purposes:
1. **Practical utilities** - They can generate useful outputs like diagrams and language bindings
2. **Educational examples** - They demonstrate how CQL can be extended to work with additional languages and frameworks

All utilities work by consuming the JSON schema output from the CQL compiler. **The JSON format is the stable contract** and evolves in a backward-compatible way. The Python scripts themselves are intentionally kept simple and may be freely modified, forked, or replaced to suit specific needs. If you require stable output formats or specific features, you are encouraged to fork these samples into your own maintained versions.

### Generating JSON Schema

Before using any of these utilities, you must first generate a JSON schema from your CQL source:

```bash
cql --in your_file.sql --rt json_schema --cg output.json
```

The JSON format is documented in:
* [Chapter 13: JSON Output](../13_json_output)
* [JSON Diagram Documentation](https://cgsql.dev/json-diagram)

### Running Python Scripts

All the utilities are Python 3 scripts and can be invoked directly:

Most utilities read JSON from standard input and write their output to standard output, following standard Unix pipeline conventions.

## Visualization Tools

### cqljson.py - Schema Visualization and Analysis

**Location:** `sources/cqljson/cqljson.py`

This is the primary utility for creating various visualizations of your CQL schema. It can generate entity-relationship diagrams (ERDs), table diagrams, region diagrams, and SQL database files.

#### Usage Patterns

**Creating an Entity-Relationship Diagram (ERD):**
```bash
cqljson.py --erd input.json [universe] > erd.dot
dot erd.dot -Tpdf -o erd.pdf
```

**Creating a Table Diagram:**
```bash
cqljson.py --table_diagram input.json [universe] > tables.dot
dot tables.dot -Tpdf -o tables.pdf
```

**Creating a Region Diagram:**
```bash
cqljson.py --region_diagram input.json > regions.dot
dot regions.dot -Tpdf -o regions.pdf
```

**Creating a SQL Database:**
```bash
cqljson.py --sql input.json > schema.sql
sqlite3 mydb.db < schema.sql
```

#### Universe Filtering

The `[universe]` parameter allows you to filter which tables appear in the diagram. This is particularly useful for large schemas where you want to focus on specific areas.

**Universe Syntax:**
* `table_name` - include just this table
* `table_name+fks` - include the table and all tables it references via foreign keys (transitively)
* `table_name+refs` - include the table and all tables that reference it via foreign keys (transitively)
* `table_name+graph` - include the table and any table connected to it by foreign keys in either direction (transitively)
* `-table_name` - exclude this table (used to remove items from a larger set)

**Examples:**
```bash
# Show just the users table and everything it references
cqljson.py --erd schema.json users+fks > users_erd.dot

# Show posts and all related tables (both directions)
cqljson.py --erd schema.json posts+graph > posts_graph.dot

# Show all tables except system tables
cqljson.py --erd schema.json +graph -sqlite_master > app_erd.dot
```

#### Processing .dot Files

The output from diagram modes is in GraphViz .dot format. Process these with:

```bash
# PDF output
dot diagram.dot -Tpdf -o diagram.pdf

# PNG output
dot diagram.dot -Tpng -o diagram.png

# SVG output
dot diagram.dot -Tsvg -o diagram.svg
```

## Language Integration Tools

These tools generate wrapper code that allows other programming languages to call CQL-generated procedures and access CQL result sets with native type safety.

### cqljava.py - Java/JNI Integration

**Location:** `sources/java_demo/cqljava.py`

Generates Java wrapper classes and JNI C code to enable Java programs to call CQL stored procedures. This creates a complete interop layer with type-safe access to CQL procedures and result sets.

#### Usage

The tool must be run twice - once to generate Java code, once to generate C code:

**Generate Java wrapper classes:**
```bash
cqljava.py input.json \
  --package com.example.app \
  --class DatabaseWrappers \
  > DatabaseWrappers.java
```

**Generate JNI C implementation:**
```bash
cqljava.py input.json \
  --emit_c \
  --jni_header com_example_app_DatabaseWrappers.h \
  --cql_header sample.h \
  > database_wrappers_jni.c
```

#### Options

* `--emit_c` - Generate C code instead of Java code
* `--package package_name` - Specify the Java package name for generated classes
* `--class outer_class_name` - Specify the wrapper class name
* `--jni_header header_file` - JNI header file to include (generated by javac -h)
* `--cql_header header_file` - CQL generated header file to include

#### Generated Code Structure

* Creates nested Java classes - one for each CQL procedure
* Provides type-safe methods to call procedures and fetch results
* Uses the `CQLViewModel` base class pattern
* Generates JNI C code that bridges between Java and CQL
* Supports all CQL types including nullable types, blobs, and objects

See `sources/java_demo/README.md` for a complete working example with build instructions.

**Demo Script:** The complete workflow including JSON generation, wrapper generation, compilation, and execution is demonstrated in `sources/java_demo/make.sh`.

### cqlcs.py - C#/.NET Integration

**Location:** `sources/dotnet_demo/cqlcs.py`

Generates C# wrapper classes and C interop code for .NET applications. Similar architecture to the Java tool but adapted for C#/.NET interop patterns.

#### Usage

Run twice - once for C# code, once for C code:

**Generate C# wrapper classes:**
```bash
cqlcs.py input.json \
  --class DatabaseWrappers \
  > DatabaseWrappers.cs
```

**Generate C interop implementation:**
```bash
cqlcs.py input.json \
  --emit_c \
  --cql_header sample.h \
  > database_wrappers_interop.c
```

#### Options

* `--emit_c` - Generate C code instead of C# code
* `--class outer_class_name` - Specify the wrapper class name
* `--cql_header header_file` - CQL generated header file to include

#### Features

* Uses C# nullable reference types (`string?`, `int?`, etc.)
* Generates `CQLViewModel` base class implementations
* Provides `CQLResultSet` for dynamic column access with type safety
* Supports P/Invoke marshaling for all CQL types
* Handles CQL encoded types (vault support)

See `sources/dotnet_demo/README.md` for build instructions and usage examples.

**Demo Script:** The complete workflow is demonstrated in `sources/dotnet_demo/make.sh`.

### cqlobjc.py - Objective-C Integration (Core Foundation)

**Location:** `sources/cqlrt_cf/cqlobjc.py`

Generates Objective-C interop functions for use with the Core Foundation-based CQL runtime. This is designed for Apple platforms and uses CF types (`CFStringRef`, `CFDataRef`) for CQL reference types.

#### Usage

**Generate Objective-C header:**
```bash
cqlobjc.py input.json \
  --objc_c_include_path sample.h \
  > sample_objc.h
```

#### Options

* `--objc_c_include_path header_file` - **Required.** Specifies the CQL generated C header file to include

#### Type Mappings

* CQL `text` → `NSString *` / `CFStringRef`
* CQL `blob` → `NSData *` / `CFDataRef`
* CQL `object` → `NSObject *`
* Primitive types use `cql_bool`, `cql_int32`, `cql_int64`, `cql_double`
* Nullable types use `NSNumber *` for boxing

This tool is intended for use with the `cqlrt_cf` runtime implementation which provides CF-based memory management.

See `sources/cqlrt_cf/README.md` for more details on the CF runtime.

**Demo Script:** A working example is demonstrated in `sources/cqlrt_cf/make.sh`.

### cql_objc_full.py - Full Objective-C Wrapper

**Location:** `sources/objc_full/cql_objc_full.py`

Generates complete Objective-C wrapper classes (both `.h` and `.m` files) with a more traditional Objective-C interface than `cqlobjc.py`.

#### Usage

Run twice - once for header, once for implementation:

**Generate header file:**
```bash
cql_objc_full.py input.json \
  --header sample.h \
  > SampleWrappers.h
```

**Generate implementation file:**
```bash
cql_objc_full.py input.json \
  --emit_impl \
  --header sample.h \
  > SampleWrappers.m
```

#### Options

* `--legacy` - Emit extra instance variable definitions in header (for legacy Objective-C)
* `--emit_impl` - Generate `.m` implementation instead of `.h` header
* `--header header_file` - CQL generated C header file to include

#### Generated Code

* Creates Objective-C classes with properties for each result column
* Provides `+[ClassName fetch:]` class methods to execute procedures
* Uses standard Objective-C naming conventions
* Supports both modern and legacy Objective-C

**Note:** This tool has primarily been tested for compilation on Linux and may require adjustments for actual Mac deployment. Consider it a starting point for Mac-based development.

See `sources/objc_full/README.md` for additional information.

**Demo Script:** Build and compilation steps are shown in `sources/objc_full/make.sh` (note: this has not been tested on actual Mac hardware).

### cqlsqlite3extension.py - SQLite Extension Generator

**Location:** `sources/sqlite3_cql_extension/cqlsqlite3extension.py`

Generates C code to expose CQL procedures as loadable SQLite extensions, specifically as table-valued functions that can be queried directly from SQL.

#### Usage

**Generate SQLite extension C code:**
```bash
cqlsqlite3extension.py input.json \
  --cql_header sample.h \
  > sample_extension.c
```

#### Options

* `--cql_header header_file` - **Required.** Specifies the CQL generated C header file to include

#### How It Works

This tool transforms CQL procedures that return result sets into SQLite table-valued functions. These can be:

1. Compiled into a loadable extension (`.so` or `.dylib`)
2. Loaded into SQLite with `.load extension_name`
3. Queried like tables: `SELECT * FROM procedure_name(arg1, arg2)`

#### Example Workflow

```bash
# Generate JSON schema
cql --in sample.sql --rt json_schema --cg sample.json

# Generate C code for the procedures
cql --in sample.sql --cg sample.h

# Generate extension glue code
cqlsqlite3extension.py sample.json --cql_header sample.h > sample_ext.c

# Compile the extension
gcc -shared -fPIC \
  -I${SQLITE_PATH} \
  sample.c sample_ext.c cql_sqlite_extension.c \
  -o cqlextension.so

# Use in SQLite
sqlite3 ":memory:" -cmd ".load ./cqlextension" \
  "SELECT * FROM my_procedure('test');"
```

#### Use Cases

* Testing CQL procedures interactively from the SQLite shell
* Providing SQL-only interfaces to CQL logic
* Creating queryable views of complex CQL computations
* Building SQLite CLI tools that leverage CQL

See `sources/sqlite3_cql_extension/README.md` for complete build and usage instructions, including test case examples.

**Demo Script:** A complete working example with test cases is in `sources/sqlite3_cql_extension/demo.sh`. For building a loadable extension, see `make_extension.sh` in the same directory.

## Customization and Extension

All these Python utilities are **simple, illustrative sample code** designed to demonstrate patterns rather than provide complete production solutions. The JSON schema is the stable contract; the Python tools are intentionally basic and subject to change. You should expect to fork and customize them for your specific needs.

### Naming Conventions

The default output uses CQL's naming as-is, but you could:
* Convert to `camelCase` or `PascalCase`
* Add prefixes/suffixes
* Map types to platform-specific conventions

### Type Mappings

Each tool has dictionaries mapping CQL types to target language types. These can be extended for:
* Custom object types
* Platform-specific types
* Encoded types (vault support)
* Custom numeric types

### Code Generation Patterns

The tools demonstrate different patterns:
* **Nested classes** (Java, C#) - one class per procedure
* **Flat functions** (Objective-C CF) - procedural interface
* **Object wrappers** (Objective-C full) - classes with properties
* **Extension functions** (SQLite) - table-valued functions

You can mix and match these patterns or create entirely new ones.

### Adding New Languages

To add support for a new language:

1. Study the JSON schema format (Appendix 5: JSON Schema Grammar)
2. Create type mappings from CQL types to your target language
3. Decide on the code generation pattern (classes, functions, etc.)
4. Implement getters for result set columns
5. Implement procedure invocation with parameter passing
6. Handle nullable types and reference counting
7. Test with simple procedures before tackling complex ones

The existing tools provide templates for common patterns. Start with the simplest (maybe `cqlobjc.py`) and adapt as needed.

## Summary

These Python utilities demonstrate CQL's extensibility and provide ready-to-use integrations for multiple programming environments:

| Utility | Purpose | Output |
|---------|---------|--------|
| `cqljson.py` | Schema visualization and SQL generation | GraphViz .dot, SQL |
| `cqljava.py` | Java/JNI integration | Java + C |
| `cqlcs.py` | C#/.NET integration | C# + C |
| `cqlobjc.py` | Objective-C CF integration | Objective-C header |
| `cql_objc_full.py` | Full Objective-C wrappers | Objective-C .h + .m |
| `cqlsqlite3extension.py` | SQLite loadable extension | C extension code |

All tools work from the same JSON schema, ensuring consistency across different language bindings and making it straightforward to support new languages or customize existing integrations.
