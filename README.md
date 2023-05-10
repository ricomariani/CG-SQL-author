# CG/SQL

CG/SQL is a code generation system for the popular SQLite library that allows developers to write stored procedures in a variant of Transact-SQL (T-SQL) and compile them into C code that uses SQLite’s C API to do the coded operations. CG/SQL enables engineers to create highly complex stored procedures with very large queries, without the manual code checking that existing methods require.

The full system also includes features for managing and upgrading schema, creating test code for stored procedures, getting query plans for procedures, as well as interfacing with stored procedures from other languages, such as Java and Objective-C. The JSON output allows for the creation of even more analysis or interfacing code. The package includes extensive documentation on the language and system.

## Getting Started

Please refer to our documentation to start using CG/SQL:
  [Introduction](https://github.com/ricomariani/CG-SQL-author/blob/main/docs/introduction.md)
- [CG/SQL Language Guide](https://github.com/ricomariani/CG-SQL-author/blob/main/CQL_Guide/generated/guide.md)
- [CG/SQL Internals](https://github.com/ricomariani/CG-SQL-author/blob/main/CQL_Guide/generated/internal.md)
- [Getting Started with CG/SQL](https://github.com/ricomariani/CG-SQL-author/blob/main/docs/getting-started.md)
- [Writing a Hello World Program](https://github.com/ricomariani/CG-SQL-author/blob/main/CQL_Guide/generated/guide.md#getting-started)
- [Playground](https://github.com/ricomariani/CG-SQL-author/blob/main/docs/playground.md)

For Contributors:
- [Contributing](https://github.com/ricomariani/CG-SQL-author/blob/main/CONTRIBUTING.md)
- [Typical Dev Cycle](https://github.com/ricomariani/CG-SQL-author/blob/main/docs/dev_notes.md)
- [Testing CG/SQL](https://github.com/ricomariani/CG-SQL-author/blob/main/docs/testing.md)
- [Code Coverage](https://cgsql.dev/docs/code-coverag://github.com/ricomariani/CG-SQL-author/blob/main/docs/code-coverage.md)

## Licensing

CG/SQL is [MIT-licensed](./LICENSE).
