# CG/SQL Version History

A chronological record of CG/SQL's evolution from inception to present.

## 2020

### October 2020
**Initial Release** - CG/SQL open-sourced by Meta Platforms
- First public commit
- Facebook Engineering blog announcement
- Basic CQL language and compiler functionality
- C code generation from SQL stored procedures
- SQLite integration
- MIT License

### November 2020
**Feature expansion and early improvements**
- `check` and `collate` column attributes
- `@attribute(cql:suppress_result_set)` for procedures
- Cursor comparison methods: `cql_cursor_diff_col`, `cql_cursor_diff_val`
- `cql_cursor_format` for debug output
- `cql_get_blob_size` API
- String manipulation: `trim`, `rtrim`, `ltrim` builtins
- `ifnull_crash` builtin for NULL contract enforcement
- `cast` operator support outside SQL context
- Railroad syntax diagrams
- Cursor shapes from procedure arguments
- `LIKE` forms for arguments
- `FETCH ... USING` syntax
- Cursor differencing capabilities
- Cursor boxing/unboxing for flexible passing
- General error tracing with `cql_error_trace()`
- Error tracing helper macros
- `LIKE` forms comprehensive tutorial

### December 2020
**Constants and argument bundles**
- `declare enum` for named constants
- `const()` primitive for compile-time constant evaluation
- Named argument bundles for procedures
- `argOrigin` tracking in JSON output
- Virtual table support with specialized syntax

## 2021

### January 2021
**Type system enhancements**
- `declare type` for type aliases
- Type "kinds" for enhanced type safety
- Discriminated types with `<kind>` syntax (e.g., `long<job_id>`)

### February 2021
**Semantic improvements**
- Empty result set semantics change for early returns
- `SELECT ... IF NOTHING` syntax
- `SELECT ... IF NOTHING OR NULL` for NULL handling
- `@RC` builtin variable for SQLite result codes

### March 2021
**Language enhancements and strictness**
- `LET` statement for declare-and-assign in one step
- `SWITCH` statement with `ALL VALUES` support
- `ifnull_throw()` builtin (peer to `attest_notnull`)
- `ifnull_crash` as synonym for `attest_notnull`
- `OUT DECLARE` form to auto-declare out args
- `INSERT USING SELECT` form
- `@RC` semantics changed to refer to error in scope
- Disallow comparing against NULL with `=` and `<>`
- Disallow SELECT expressions of null type
- Kind info preserved on cursors and arg bundles
- Boxed cursor improvements

### April 2021
**Schema and indexing features**
- Partial indices and index expressions
- `conflict_clause` grammar support
- Indexed columns in PK/UK constraints
- Virtual table deletion with `cql:module_must_not_be_deleted` annotation
- `cql:from_recreate` migration builtin
- Enhanced schema upgrade testing
- Table-valued functions context enforcement
- Object type support in cursors
- `sensitive` pseudo-function like `nullable(..)`
- Blob type support in dummy_test

### May 2021
**JSON schema enhancements**
- Attributes emission for views in JSON schema
- Attributes emission for indices in JSON schema
- Attributes emission for triggers in JSON schema
- Attributes emission for ad-hoc migration sprocs
- Query plan improvements with temp b-tree counts
- Setter support additions

### June 2021
**Nullability and validation improvements**
- Occurrence typing for nullability
- Nullability improvements in CASE statements
- SET statement can improve nullability
- Context-based nullability improvements
- Tripwires for nullability contracts
- `cql:generate_copy` attribute
- Extension fragment improvements
- VSCode hover support for CQL files
- Schema upgrade caching for performance

### July 2021
**Operators and type safety**
- `TRUE` and `FALSE` constants added
- `IS TRUE` and `IS FALSE` operators
- `IS NOT TRUE` and `IS NOT FALSE` operators
- `ISNULL` and `NOTNULL` operators
- `NOT MATCH`, `NOT GLOB`, `NOT REGEXP` operators
- Guard statements with nullability improvements
- IIF support for nonnull improvements
- Strict procedure names enforcement
- Order of operations fixes
- Java interface codegen alternative
- Left recursion for statement lists (avoid stack overflow)

### August 2021
**Code generation and documentation**
- Nullability improvements fully enabled
- Branch-independent nullability for CASE
- `round` builtin function
- Comprehensive CQL internals documentation started
- Internals Part 1: Building the AST
- Internals Part 2: Semantic Analysis  
- Internals Part 3: C Code Generation
- Testing documentation
- `replace` built-in function
- `cql:emit_setters` attribute and codegen
- CRC emission for schema items in JSON
- Amalgam documentation and options
- `--rt schema_sqlite` output mode

### September 2021
**Flow analysis and optimization**
- Nullability improvements for globals
- SET and OUT arg flow analysis
- Strict CAST mode (redundant casts cause errors)
- Query plan nullability maintenance
- Static constant strings for string literals
- `SELECT table.*` nullability support
- Coalesce/ifnull errors for known not-null args
- Sensitive function elision in codegen
- Schema management runtime improvements

### October 2021
**Test infrastructure and enforcement**
- Test helpers comprehensive implementation
- Test helpers documentation
- `NULL CHECK ON NOT NULL` enforcement option
- `cql_func_sign` and `cql_func_sign` helpers
- Ad hoc migration support for recreate tables/groups
- `PROC AS FUNC ARGUMENTS` enforcement mandatory
- OUT/INOUT argument uniqueness requirements
- Error format compatibility with modern IDEs
- Global constant groups support
- Exclusive mode schema support

### November 2021
**Shared fragments foundation**
- Shared fragments initial implementation and wiring
- Simple syntax for matching fragment names
- Simple syntax for forwarding arguments to procedures
- JSON dependency analysis for shared fragments
- Error handling for bad window definitions
- Leak fixes in fragment analysis
- Meta copyright transition (Facebook â†’ Meta Platforms)

### December 2021
**Major code reuse features**
- Shared fragments for query reuse
- Generic fragments with conditional logic
- Comprehensive fragment validation
- Control flow analysis improvements
- Nullability inference
- Initialization-before-use enforcement

## 2022

### January 2022
**Swift interop and tooling**
- Optional `@interface` for Objective-C output for Swift interop
- Swift-friendly runtime declarations in `cqlrt_cf.h`
- Eponymous virtual table annotations
- AST statistics generation option for code analysis
- Exec tracing option
- Migration procedures auto-declared with correct signatures
- `@delete` support for tables on `@recreate` plan
- Schema version info in `--sql` output
- Upgrader strategy improvements for dropped tables
- CQL Guide comprehensive edits (chapters 1-14)
- Error message consistency improvements

### February 2022
**Bulk operations and expression reuse**
- `COLUMNS()` construct in SELECT statements
- `COLUMNS(like Shape)` for column extraction
- Shared expression fragments
- Expression-level code sharing
- Extended `FROM` construct usage
- `FROM` in more contexts with mixed value sources

### March 2022
**Binary serialization**
- Blob storage feature
- `@attribute(cql:blob_storage)` for tables
- Binary serialization format
- Cursor-to-blob and blob-to-cursor conversion

### April 2022
**Cursor enhancements and unsubscription**
- Cursor parameters and dynamic cursor calls
- General purpose cursor hashing and comparison
- `likely` function support
- Unsubscription/resubscription region management
- JSON schema shows unsubscribed tables as deleted
- `--c_include_path` for header specification
- CQL Guide Chapter 13 (JSON) rewritten
- LIKE arguments error handling improvements

### May 2022
**Interfaces and parent/child result sets**
- `DECLARE INTERFACE` statement
- `cql:implements` attribute support
- Interfaces in LIKE expressions and JSON schema
- Parent/child result set partitioning functions
- Simple sugar form for parent/child queries
- View unsubscription support
- Variadic select procedures (like `json_extract`)
- Shape narrowing by column specification
- Virtual table schema deployment
- Result set variables in `declare cursor for`

### June 2022
**Type system and optimization**
- `NULLS FIRST` and `NULLS LAST` support
- Partition function builtin support
- Child result set fetching
- `object<procname SET>` result types
- Strict IF NOTHING enforcement improvements
- Long enum support with #define generation
- Constant folding for min long values
- Query plan conditional fragment handling
- `definedOnLine` in JSON output
- Algolia Docsearch integration

### July 2022
**Lua code generation foundation**
- Initial Lua codegen implementation (experimental)
- Lua runtime skeleton (`cqlrt.lua`)
- Lua upgrader additions
- Lua integer division emulation
- Dynamic cursor structure with field names
- `DECLARE INTERFACE` statement support
- Compressed string optimizations
- Test helpers enqueue triggers
- Query plan script improvements

### August 2022
**Code generation refinements**
- Interface attributes in JSON schema
- Compressed strings for recreate group inputs
- Virtual table support in query plans
- Multiple interfaces per procedure
- Flexible interface column ordering
- Boolean normalization for int/long args
- Named child result sets
- Global nullable variable initialization

### September 2022
**Backed tables implementation**
- Backing store and backed table detection
- `@attribute(cql:backed_by)` for virtual storage
- SHA256 helper for type hashing
- Blob access function declarations (`cql_blob_get`, `cql_blob_update`)
- Automatic query rewriting for backed tables
- SELECT/INSERT/UPDATE/DELETE transformations
- Rowid support in backed tables
- Backing table shared fragment generation
- Runtime helpers for blob operations
- Reverse application operator (`|>`)
- Previous schema validation for backed tables

### October 2022
**Virtual storage and nested results**
- Backed tables with `@attribute(cql:backed_by)`
- Key-value backing store support
- Type hashing for schema evolution
- Parent/child result sets
- Nested result set capabilities
- `out union ... join` syntax
- Partitioning functions for result sets

### November 2022
**Schema system improvements**
- Schema upgrade system enhancements
- Immutable schema versions replaced
- Zombie table handling fixes
- Unsubscription/resubscription improvements
- Performance optimizations (7% and 13-15% gains)
- Reduced CRC-based checks

## 2023

**CG/SQL Author's Cut established** 
- Following Meta's November 2022 layoffs and decision to stop publishing OSS updates, Rico Mariani established the "Author's Cut" fork to continue maintaining CG/SQL. The Meta internal version diverged significantly (adopting C-like brace syntax), leaving the OSS project without a maintainer.

### January 2023
**Internal refactoring**
- Facet diff logic refactoring
- API for fetching rebuilt facets
- Documentation updates

### February 2023
**Schema migration enhancements**
- `cql:alias_of` attribute introduced
- Migration proc skipping for rebuilt recreate groups
- `@delete` table drop order fixes
- Rollback logic corrections
- Docusaurus security patches

### March 2023
**JSON schema enhancements**
- Schema string added to CQL table JSON output
- Object type handling in `cql_multinull`
- Return type enforcement for functions simplified
- Schema attributes excluding CQL annotations

### April 2023
*No commits this month*

### May 2023
- **Repository created May 10, 2023** 
- CG-SQL-author repository established on GitHub
**JNI support**
- General purpose Java/JNI adapter
- Automatic `.java` and `.c` file generation
- `cqljava.py` code generator tool

### June 2023
**Documentation and tooling**
- Documentation improvements
- Internal link fixes
- Query plan output corrections

### July 2023
**Query plan evolution**
- Removed `--rt udf` in favor of `--rt query_plan`
- Lua UDF stub support
- `cql_create_udf_stub` runtime helper

### August 2023
**Runtime enhancements**
- Backing table helper methods in standard runtime
- Null value support in blob serialization

### September 2023
**Documentation and testing improvements**
- Markdown formatting and consistency fixes
- Documentation line-wrapping standardization
- Testing options expansion
- Link corrections throughout documentation
- Example formatting consistency
- User's Guide and Developer's Guide naming standardization
- Boolean literals section added

### October 2023
**Quoted identifiers and website launch**
- Quoted identifier support in SQL contexts
- Quoted names in backed table columns
- Quoted names in test helpers (triggers, views, indices)
- Quoted names in schema upgrader
- Named shape expansion with quoted identifiers
- Conditional shared fragments without ELSE clause
- Query plan output includes actual table/view names with aliases
- New official website launched
- AST node sorting for clarity
- CICD improvements for website deployment
- SQL prepare/exec tracing to stderr
- `UPDATE..FROM` compatibility fixes for SQLite 3.31

### November 2023
**Pre-processor and CI/CD**
- Built-in pre-processing features
- `@include`, `@ifdef`, `@ifndef`, `@macro` directives
- Quoted identifier support
- C pre-processor officially deprecated
- GitHub Actions CI/CD pipeline
- Code coverage builds

### December 2023
**Syntax sugar and @include refinements**
- `CONST` statement introduced
- `IF ... END` syntax (optional `IF` in `END IF`)
- Briefer try/catch syntax support
- `FROM` shape syntax sugar in UPDATE statements
- Parent/child result set C API fixes
- `@include` restrictions (top-level only, no duplicates)
- Test output echo parsing verification
- UPDATE statement echo formatting improvements
- Sugar syntax documentation for INSERT and UPDATE
- Type getters optimization fixes

## 2024

### January 2024
**Syntax modernization**
- Preferred `PROC` over `CREATE PROC`
- `!` abbreviation for `NOT NULL` in echo output
- `INTEGER` â†’ `INT`, `LONG_INT` â†’ `LONG` in echoed output
- `DECLARE CURSOR` and `DECLARE TYPE` short form echoing
- BETWEEN expression echo improvements (round-trip parsing)
- Try/catch syntax removal from test suite
- `--rt objc_mit` removed (merged with `--rt objc`)
- `rt_common.c` folded into `rt.c`
- Modern syntax adoption in run_test

### February 2024
**First Official Release**
- Syntax modernization continued from January
- **v1.0.0 released (February 25, 2024)** 
- First numbered version release with stable API commitment and production-ready milestone

### March 2024
**Hugo actions and documentation**
- Hugo action configuration updates
- AI-assisted editing pass on documentation
- Title block corrections
- Triple quote fixes

### April 2024
**JNI and documentation improvements**
- Automatic JNI generation for java_demo
- JNI boilerplate reduction
- Helper generation for JNI calls
- Row number elision from out statement results
- Developer guide chapter renaming and link updates
- Getting started package updates
- AI-assisted text corrections
- CPP removal from Java demo compilation

### May 2024
**Java/JNI refinements**
- Test cases for all primitive types
- Nullable type test coverage
- Null blob and text test cases
- INOUT parameter support for primitives
- Private procedure suppression from JNI
- `CQLEncodedString` documentation improvements
- Null string and blob argument handling
- C codegen refactoring into smaller functions
- Python comment enhancements
- Validation improvements
- Standard runtime helpers organization
- `CQL_NO_GETTERS` removal (always set, never used)
- README tweaks and formatting

### June 2024
**Syntax improvements and C# foundation**
- `SELECT ... IF NOTHING THEN NULL` syntax support
- CTE implied column names: `WITH foo AS (SELECT 1 x)`
- Rowid lookup in full join stack
- Empty/blocked join scope handling
- Canonical `IF NOTHING THEN` form standardization
- Printf-like format string corrections throughout
- `__attribute((format(printf,...)))` enforcement
- Missing AST argument fixes
- C# interop initial implementation (mostly working)
- Property usage in C# where allowed
- Blob display corrections
- Java reference cleanup

### July 2024
**Java codegen improvements**
- Float formatting for clarity
- Comments added to `CQLEncodedString`
- Java output formatting enhancements

### August 2024
*No commits this month*

### September 2024
**JSON support foundation**
- JSON and JSONB function support (`json_array`, `jsonb_array`)
- `json_extract` and `jsonb_extract` with semantic checks
- `json_insert`, `json_replace`, `json_set` functions
- `json_remove`, `jsonb_remove` support
- `json_object`, `jsonb_object` functions
- `json_patch`, `jsonb_patch` added
- `json_type`, `json_pretty` support
- `json_valid`, `json_quote` functions
- `json_group_array`, `json_group_object` aggregates
- `json_error_position`, `json_array_length` functions
- Pipeline operators `->` and `->>` initial support
- Cast notation with `:type:` suffix
- Platform-agnostic format specifiers
- SQLite version logging

### October 2024
**Advanced JSON and operator overloading**
- Additional JSON methods (`typeof`, `unicode`, `unlikely`)
- `randomblob`, `zeroblob`, `hex`, `unhex` functions
- `quote`, `octet_length`, `total_changes` support
- `sqlite_version`, `sqlite_source_id`, `sqlite_offset` functions
- `load_extension`, `soundex`, `likelihood` functions
- SQLite compile option inspection functions
- `@op` directive for operator overloading
- Pipeline operator customization with `@op`
- Type-based operator overloading (`~type~` cast notation)
- Polymorphic pipeline invocation
- Boxing/unboxing primitives (`cql_box_*`, `cql_unbox_*`)
- Object dictionary for boxed objects
- Dynamic cursor access from CQL
- `@op` support for cursors and null literals
- Expression macros in pipeline syntax
- Loose name function parsing for keyword reuse
- Pattern argument checking for JSON functions
- `COLUMNS()` construct improvements
- Function argument validation helpers
- `format`, `concat`, `concat_ws` builtins
- Blob conversion helpers
- `like`, `glob`, `substring` builtins
- Many more SQLite functions callable directly
- CAST from null to any type without SQL

### November 2024
**v1.1.0 Release**
- JSON and operator overloading work from September-October matured
- **v1.1.0 released (November 10, 2024)**
- Enhanced JSON support, pipeline operator customization, general purpose boxing/unboxing, and .NET support

### December 2024
**RETURNING clause and backing improvements**
- `INSERT ... RETURNING` support
- `DELETE ... RETURNING` support
- `UPDATE ... RETURNING` support
- `UPSERT ... RETURNING` support
- JSON-backed tables with `@attribute(cql:backed_table_format="json")`
- Attribute-driven backing tables (replacing string-based system)
- `[[autodrop]]` attribute handling in Lua
- `@columns` for `SELECT *` and `SELECT T.*`
- Modern test infrastructure with checked-in SQLite amalgam
- `excluded` virtual table support in upsert for backed tables
- CTE handling improvements for multiple backed tables
- Backed table array path syntax corrections
- `json_pretty` second argument support
- `VALUES` formatting standardization
- Shorter echo syntax for shared fragments
- Error message improvements for CTEs and fragments
- Blob field validation for JSON backed tables
- Statement reading DML helper generalization
- Lua codegen `DELETE RETURNING` support
- Query plan `RETURNING` clause handling
- Modern syntax adoption in samples
- Additional identifier tokens allowed as names
- Python script for `--rt objc` replacement (`cqlobjc.py`)
- `SELECT ... IF NOTHING OR NULL THEN THROW` combo
- Vault_sensitive removal from documentation

## 2025

### January 2025
**v1.2.0 Release**
- RETURNING clause support from December 2024
- **v1.2.0 released (January 7, 2025)**
- Additional JSON methods support, `->>` operator with type hints, `@op` pipeline operator customization

### February 2025
**Grammar and documentation refinements**
- Grammar simplification with `$$` for result types
- Named terminals/non-terminals consistency
- CQL in 20 minutes guide updates
- `@op` directive documentation expansion
- Chapter 5 formatting and clarity improvements
- MSC compilation fixes for amalgam
- Beta release snapshot

### March 2025
**v1.3.0 & v1.3.1 Releases**
- **v1.3.0 released (March 23, 2025)** 
- Syntax shortcuts (PROC, FUNC keywords), SQLite extension improvements
- **v1.3.1 released (March 24, 2025)**
- MacOS build fixes, cosmetic syntax updates

### April 2025
**Code organization and validation**
- Private method visibility enforcement
- Shared fragment CTE reference validation
- Parent/child join column null checks enforced
- Amalgam visibility improvements
- Window function analysis comments
- Argument pattern matcher documentation
- sem.c comment enhancements
- C preprocessor to `@include` migration in docs
- `--rt objc` reference removal

### May 2025
*No commits this month*

### June 2025
**Test infrastructure refactoring**
- Test.sh macro-based refactoring for consistency
- Test output standardization

### July 2025
**Code organization**
- Test file reorganization
- `cql_not_like` Lua runtime fix

### August 2025
**Minor fixes**
- SQLite extension private procedure filtering
- Macro shape argument handling fix
- CICD improvements

### September 2025
*No material changes this month*

### October 2025
**v1.3.2 Release**
- Code organization and validation work from April-September
- **v1.3.2 released (October 4, 2025)**
- UTF-8 support in JSON strings, `@strict` control directives, attribute support for enums and const groups

### November 2025
**Documentation improvements**
- Shared fragments and appendices reformatted
- `#define` references updated to `@macro`
- README files added throughout project

### December 2025
**UTF-8 and attribute features**
- UTF-8 support in JSON strings
- `@strict` control directives documented
- Enum and const group attributes support in JSON
- AST output decoding improvements (human-readable flags)

### January 2026
**Developer documentation and infrastructure**
- Security reporting via GitHub (SECURITY.md)
- AST flag decoding enforcement and improvements
- Detail node renaming (was `new_ast_option`) for clarity
- Comprehensive developer guide updates (all 11 chapters)
- Query plan documentation added
- Lua codegen comparison documentation
- Python JSON utilities documentation
- FAQ documentation (USER_FAQ.md, DEVELOPER_FAQ.md)
- HISTORY.md comprehensive version history
- **v1.3.3 released (January 14, 2026)**
- Documentation and infrastructure release with comprehensive developer guides, improved AST debugging, and security reporting

---

## Notes

**Meta's Involvement**: CG/SQL was originally developed and open-sourced by Meta Platforms (Facebook) in October 2020. It is no longer maintained by Meta as of 2024.

**Author's Cut**: The project is now maintained by Rico Mariani as the "CG/SQL Author's Cut," ensuring continued development and community support.

**Release Cadence**: After the initial 1.0.0 release in February 2024, the project has followed a regular release schedule with minor versions every few months.

**Documentation**: Extensive documentation has been maintained throughout, including user guides, developer guides, and railroad diagram visualizations.

**Major Themes**:
- **2020-2021**: Foundation, type safety, basic features
- **2022**: Advanced features (fragments, serialization, nested results)
- **2023**: Language bindings, tooling, CI/CD
- **2024-2025**: Stability, .NET support, JSON enhancements, syntactic improvements
