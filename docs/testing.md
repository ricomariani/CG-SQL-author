# Testing CG/SQL

Basic testing commands you should know.

While standing in the `/sources` directory you may use test.sh and with these important options.

|Command|Details|
|:-----|:------|
|`./test.sh` | Build the compiler and run the suite.  This is the bread an butter of the dev cycle.|
|`--use_amalgam`| Builds the compiler from the amalgam and then tests it as above.|
|`--use_asan`| Enable address sanitizer.  Great and finding memory issues.|
|`--use_clang`| Clang finds more warnings than GCC in general, recommened before any PR.|
|`cov.sh` | See [Code Coverage](code-coverage.md) |


See details in our [CQL Internals documentation](../CQL_Guide/generated/internal.md#part-4-testing)

>NOTE: For productivty it's not uncommon to tweak `test.sh` so that the test you care about runs first.
>But don't submit a PR with the tests reordered.  Not that the author has ever made that mistake or
>anything.  But it could happen -- you know -- to other people...
