# Test Directory Notes

Here is, in short, all the primary test collateral expect for those things
(such as what is in `test2`) must be in some other directory by necessity.

Interop subsystems are not considered part of the main runtime -- they are
"sample code" and they are therefore tested seperately.

All language features are tested here.  The most important files are:

* `test.sql` -- for parsing tests
* `macro_test.sql` -- for parsing with macros
* `sem_test.sql` -- for semantic analysis
* `cg_test.sql` -- for C code gen
* `run_test.sql` -- code that will actually run and self-verify

Many tests can appear in one file because in most cases error generation
does not terminate compilation.  But there are exceptions and therefore
there are some test cases that test one thing in one file.  The compiler
will exit after that failure.

The test cases are largely self-documenting.  e.g. `sem_test.sql` is
teeming with comments.