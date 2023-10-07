# Testing CG/SQL


<style>
table {
  border-collapse: collapse;
  width: 100%;
}

th, td {
  text-align: left;
  padding: 8px;
  border-bottom: 1px solid #ddd;
}

th {
  background-color: #f2f2f2;
}
</style>

Basic testing commands you should know

|Command|Details|
|:-----|:------|
|`./test.sh` | Build the compiler and run the suite.  This is the bread an butter of the dev cycle.|
|`--use_amalgam`| Builds the compiler from the amalgam and then tests it as above.|
|`--use_asan`| Enable address sanitizer.  Great and finding memory issues.|
|`--use_clang`| Clang finds more warnings than GCC in general, recommened before any PR.|
|`cov.sh` | See [Code Coverage](code-coverage.md) |


> See details in our [CQL Internals documentation](../CQL_Guide/generated/internal.md#part-4-testing)
