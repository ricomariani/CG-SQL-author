---
title: "Appendix 3: Control Directives"
weight: 3
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

The control directives are those statements that begin with `@` and they are distinguished from other statements because they influence the compiler rather than the program logic.  Some of these are of great importance and discussed elsewhere.

The complete list (as of this writing) is:

`@ENFORCE_STRICT`
`@ENFORCE_NORMAL`

* These enable or disable more strict semantic checking. The sub-options are:
  * `FOREIGN KEY ON UPDATE`: all foreign keys must choose some `ON UPDATE` strategy
  * `FOREIGN KEY ON DELETE`: all foreign keys must choose some `ON DELETE` strategy
  * `JOIN`: all joins must be ANSI style, the form `FROM A,B` is not allowed (replace with `A INNER JOIN B`)
  * `UPSERT STATEMENT`: the upsert form is disallowed (useful if targeting SQLite versions before 3.24.0)
  * `WINDOW FUNC`: window functions are disallowed (useful if targeting SQLite versions before 3.25.0)
  * `WITHOUT ROWID`: `WITHOUT ROWID` tables are forbidden
  * `TRANSACTION`: transaction operations (`BEGIN`, `COMMIT`, `ROLLBACK`, etc.) are disallowed
  * `SELECT IF NOTHING`: all scalar `(select ...)` expressions must include `IF NOTHING`, `IF NOTHING OR NULL`, or `IF NOTHING THROW` to handle the case when the select returns no rows
  * `INSERT SELECT`: `INSERT ... SELECT` statements may not include joins
  * `TABLE FUNCTION`: table-valued functions cannot be used on left/right joins (avoids a SQLite bug)
  * `IS TRUE`: `IS TRUE`, `IS FALSE`, `IS NOT TRUE`, `IS NOT FALSE` operators are disallowed (useful if targeting SQLite versions before 3.24.0)
  * `CAST`: no-op casts (where source and target types are the same) result in errors. **This is enabled by default.**
  * `SIGN FUNCTION`: the SQLite `sign()` function may not be used (useful if targeting SQLite versions before 3.35.0)
  * `CURSOR HAS ROW`: auto cursors require a has-row check (e.g., `IF cursor THEN`) before accessing cursor fields
  * `UPDATE FROM`: the `UPDATE ... FROM` clause is disallowed (useful if targeting SQLite versions before 3.33.0)
  * `AND OR NOT NULL CHECK`: enables stricter nullability analysis on `AND`/`OR` logical expressions

`@SENSITIVE`

 * marks a column or variable as 'sensitive' for privacy purposes, this behaves somewhat like nullability (See Chapter 3) in that it is radioactive, contaminating anything it touches
 * the intent of this annotation is to make it clear where sensitive data is being returned or consumed in your procedures
 * this information appears in the JSON output for further codegen or for analysis (See Chapter 13)

`@DECLARE_SCHEMA_REGION`
`@DECLARE_DEPLOYABLE_REGION`
`@BEGIN_SCHEMA_REGION`
`@END_SCHEMA_REGION`

 * These directives control the declaration of schema regions and allow you to place things into those regions -- see [Chapter 10](../10_schema_management.md)

`@SCHEMA_AD_HOC_MIGRATION`

 * Allows for the creation of an ad hoc migration step at a given schema version (See Chapter 10)

`@ECHO`

 * Emits text into the C output stream, useful for emitting things like function prototypes or preprocessor directives
 * e.g., `echo C, '#define foo bar'`

`@RECREATE`
`@CREATE`
`@DELETE`

  * used to mark the schema version where an object is created or deleted, or alternatively indicate that the object is always dropped and recreated when it changes (See Chapter 10)

`@SCHEMA_UPGRADE_VERSION`

 * used to indicate that the code that follows is part of a migration script for the indicated schema version
 * this has the effect of making the schema appear to be how it existed at the indicated version
 * the idea here is that migration procedures operate on previous versions of the schema where (e.g.) some columns/tables hadn't been deleted yet

`@PREVIOUS_SCHEMA`

 * indicates the start of the previous version of the schema for comparison (See Chapter 11)

`@SCHEMA_UPGRADE_SCRIPT`

 * CQL emits a schema upgrade script as part of its upgrade features, this script declares tables in their final form but also creates the same tables as they existed when they were first created
 * this directive instructs CQL to ignore the incompatible creations, the first declaration controls
 * the idea here is that the upgrade script is in the business of getting you to the finish line in an orderly fashion and some of the interim steps are just not all the way there yet
 * note that the upgrade script recapitulates the version history, it does not take you directly to the finish line, this is so that all instances get to the same place the same way (and this fleshes out any bugs in migration)

`@DUMMY_NULLABLES`
`@DUMMY_DEFAULTS`
`@DUMMY_SEED`

 * these control the creation of dummy data for `insert` and `fetch` statements (See Chapters 5 and 12)

`@FILE`

 * a string literal that corresponds to the current file name with a prefix stripped (to remove build lab junk in the path)

`@ATTRIBUTE`

  * the main purpose of `@attribute` is to appear in the JSON output so that it can control later codegen stages in whatever way you deem appropriate
  * the nested nature of attribute values is sufficiently flexible that you could encode an arbitrary LISP program in an attribute, so really anything you might need to express is possible
  * there are a number of attributes known to the compiler which are listed below (complete as of this writing)

  * `cql:autodrop=(table1, table2, ...)` when present the indicated tables, which must be temp tables, are dropped when the results of the procedure have been fetched into a rowset
  * `cql:identity=(column1, column2, ...)` the indicated columns are used to create a row comparator for the rowset corresponding to the procedure, this appears in a C macro of the form `procedure_name_row_same(rowset1, row1, rowset2, row2)`
  * `cql:suppress_getters` the annotated procedure should not emit its related column getter functions.
    * Useful if you only intend to call the procedure from CQL.
    * Saves code generation and removes the possibility of C code using the getters.
  * `cql:emit_setters` the annotated procedure should  emit setter functions so that result set columns can be mutated, this can be quite useful for business logic but it is more costly
  * `cql:suppress_result_set` the annotated procedure should not emit its related "fetch results" function.
    * Useful if you only intend to call the procedure from CQL.
    * Saves code generation and removes the possibility of C code using the result set or getters.
    * Implies `cql:suppress_getters`; since there is no result set, getters would be redundant.
    * an `OUT UNION` procedure cannot have a suppressed result set since all such a procedure does is produce a result set. This attribute is ignored for out union procedures.
  * `cql:private` the annotated procedure will be static in the generated C
    * Because the generated function is `static` it cannot be called from other modules and therefore will not go in any CQL exports file (that would be moot since you couldn't call it).
    * This attribute also implies `cql:suppress_result_set` since only CQL code in the same translation unit could possibly call it and hence the result set procedure is useless to other C code.
  * `cql:generate_copy` the code generation for the annotated procedure will produce a `[procedure_name]_copy` function that can make complete or partial copies of its result set.
  * `cql:shared_fragment` is used to create shared fragments (See [Chapter 14](../14_shared_fragments.md))
  * `cql:no_table_scan` for query plan processing, indicates that attributed table should never be table scanned in any plan (for better diagnostics)
  * `cql:ok_table_scan=([t1], [t2], ...)` indicates that the attributed procedure scans the indicated tables and that's not a problem.  This helps to suppress errors in expensive search functions that are known to scan big tables.
  * `cql:autotest=([many forms])` declares various autotest features (See [Chapter 12](../12_testability_features.md))
  * `cql:query_plan_branch=[integer]` is used by the query plan generator to determine which conditional branch to use in query plan analysis when a shared fragment that contains an `IF` statement is used. (See [Chapter 15](../15_query_plan_generation.md))
  * `cql:alias_of=[c_function_name]` are used on [function declarations](../08_functions.md#ordinary-scalar-functions) to declare a function or procedure in CQL that calls a function of a different name. This is intended to used for aliasing native (C) functions. Both the aliased function name and the original function name may be declared in CQL at the same time. Note that the compiler does not enforce any consistency in typing between the original and aliased functions.
  * `cql:backing_table` used to define a key value store table (docs need, there is only a brief wiki article)
  * `cql:backed_by=[a_backing_table]` specifies that the attributed table should have its data stored in the specified backing table, (docs needed, there is only a brief wiki article)
  * `cql:blob_storage` the attributed table isn't really a physical table, it specifies the layout of a serializable blob, see this [introductory article](https://github.com/ricomariani/CG-SQL-author/wiki/CG-SQL-Blog-Archive#introducing-blob-storage-20220317)
  * `cql:deterministic` when applied to a `select function` indicates that the function is deterministic and hence ok to use in indices.
  * `cql:implements=[interface]` interfaces may be declared with `declare interface` and are basically a normal CQL shape.  This annotation specifies that the annotated procedure has all the needed columns to encode the indicated shape.  It may be used more than once to indicate several shapes are supported.  The requirements are validated by the compiler but they do not affect code generation at all other than the JSON file (see [Chapter 13](../13_json_output.md)). The intent here is to allow downstream code generators like you might have for Java and Objective-C to incorporate the interface into the signature of result sets and define the interface as needed.  The C and Lua output do not have any such notions.  The present Objective-C output (`--rt objc`) doesn't support interfaces and is likely to be replaced by a python equivalent based on the JSON output that does.  Generally, `--rt objc` was a mistake as was `--rt java`, but the latter has been removed.  Interfaces are highly useful even without codegen just for declarative purposes.
  * `cql:java_package=[a name]` this is not used by the compiler but it can be handy to apply to various items to give Java code generators a hint where the code should go or where it comes from.  Any support for this needs to be in your Java code generator.  A sample is in the `java_demo` directory.
  * `cql:try_is_proc_body` (See [Initialization Improvements](../../developer_guide/02_semantic_analysis.md#initialization-improvements)), this indicates that the annotated try block should be considered the entire body of the procedure for initialization purposes.  In particular, it ensures that all parameters of the current procedure have been initialized by the end of the `TRY` and prevents this check from happening again at the end of the procedure. This is needed because for various reasons sometimes we need to wrap certain stored procedures in a try/catch such that custom error handling or logging can be implemented. In doing so, however, they can break our normal assumptions about things like initialization of OUT parameters in the errant case and that must be ok.
  * `cql:vault_sensitive` or `cql:vault_sensitive([columns]...)` `cql:vault_sensitive(context, [columns]...)` these forms indicate that `@sensitive` columns should get additional encoding. These columns are marked with `CQL_DATA_TYPE_ENCODED` in the result set metadata.  This causes `cql_copy_encoder` to be called to make an abstract encoder from a database instance and then functions like `cql_encode_text` to be called to encode each column.  To make sure of these attributes you will need a custom `cqlrt.c` with suitable encodings for your application.
  * `cql:from_recreate` is used to mark tables that transitioned from `@recreate` to `@create`
  * `cql:module_must_not_be_deleted_see_docs_for_CQL0392` must be added to an `@delete` attribute on a virtual table to remind the developer that the module for the virtual table must never be deleted elsewise database upgrades will fail.  See [`CQL0392`](#cql0392-when-deleting-a-virtual-table-you-must-specify-deletenn-cqlmodule_must_not_be_deleted_see_docs_for_cql0392-as-a-reminder-not-to-delete-the-module-for-this-virtual-table)

### Deprecated attributes

  * `cql:alt_prefix=prefix` this may be applied to a procedure definition or declaration to override the prefix found in `rt_common.c`, this is really only interesting if there is a prefix in the first place so the default configuration of `rt_common.c` doesn't make this very interesting.  However it is possible to change `.symbol_prefix` (Meta does) and having done so you might want to change it to something else.
  * `cql:custom_type_for_encoded_column` the Objective-C output has the option of using a different type for strings that have been encoded because they are sensitive.  This attribute is placed on a procedure and it causes all strings in result sets to be declared with `cql_string_ref_encode` from the objc result type.  The type is configured with `RT_STRING_ENCODE` which is `cql_string_ref_encode` by default.  This is deprecated because the entire `--rt objc` feature is slated for destruction to be replaced with python that processes the JSON like the Java case.
