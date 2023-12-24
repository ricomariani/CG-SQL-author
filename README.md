# CG/SQL

CG/SQL is a code generation system for the popular SQLite library that allows
developers to write stored procedures in a variant of Transact-SQL (T-SQL) and
compile them into C or Lua code that uses SQLite’s C API to do the coded
operations.  CG/SQL enables engineers to create highly complex stored
procedures with very large queries, without the manual code checking that
existing methods require.

CG/SQL system also includes features for managing and upgrading schema,
creating test code for stored procedures, getting query plans for procedures,
as well as interfacing with stored procedures from other languages, such as
Java and Objective-C.

CG/SQL's JSON output allows for the creation of even more analysis or
interfacing code. The package includes extensive documentation on the language
and system.

## Getting Started

### Essential Documentation

- [Introduction](https://ricomariani.github.io/CG-SQL-author/docs/quick_start/introduction/)
- [CG/SQL User Guide](https://ricomariani.github.io/CG-SQL-author/docs/user_guide/) [(HTML version)](https://ricomariani.github.io/CG-SQL-author/user_guide.html)
- [CG/SQL Developer Guide](https://ricomariani.github.io/CG-SQL-author/docs/developer_guide/) [(HTML version)](https://ricomariani.github.io/CG-SQL-author/developer_guide.html)
- [Getting Started with CG/SQL](https://ricomariani.github.io/CG-SQL-author/docs/quick_start/getting-started/)
- [Writing a Hello World Program](https://ricomariani.github.io/CG-SQL-author/docs/user_guide/01_introduction/#getting-started)
- [Playground](https://ricomariani.github.io/CG-SQL-author/docs/quick_start/playground/)
- [Examples](https://github.com/ricomariani/CG-SQL-author/wiki/Examples)

### Grammar Diagrams
- [Language Railroad Diagrams](https://ricomariani.github.io/CG-SQL-author/cql_grammar.railroad.html)
- [JSON Output Diagrams](https://ricomariani.github.io/CG-SQL-author/json_grammar.railroad.html)
- [Query Plan Output Diagram](https://ricomariani.github.io/CG-SQL-author/query_plan_grammar.railroad.html)

### Wiki
- [Wiki Home](https://github.com/ricomariani/CG-SQL-author/wiki/Home)

### For Contributors
- [Contributing](https://github.com/ricomariani/CG-SQL-author/blob/main/CONTRIBUTING.md)
- [Typical Dev Cycle](https://ricomariani.github.io/CG-SQL-author/docs/contributors/dev_notes/)
- [Testing CG/SQL](https://ricomariani.github.io/CG-SQL-author/docs/contributors/testing/)
- [Code Coverage](https://ricomariani.github.io/CG-SQL-author/docs/contributors/code-coverage/)

### Notes and Archived Resources
- [Latest Updates Blog](https://github.com/ricomariani/CG-SQL-author/wiki/CG-SQL-Blog)
- [Why an Author's Cut](https://github.com/ricomariani/CG-SQL-author/wiki/CG-SQL-Author's-Cut)
- [All the old Blogs](https://github.com/ricomariani/CG-SQL-author/wiki/CG-SQL-Blog-Archive)

## Licensing

CG/SQL is [MIT-licensed](./LICENSE).
