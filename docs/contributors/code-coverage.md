# Code Coverage CG/SQL

Run this command in the `/sources` directory:

```
./cov.sh
```
This will run the test scripts with the coverage flag, which causes the coverage build.  If the tests pass a coverage report is created.

The same build options are available as `cov.sh` uses `test.sh` to do the heavy lifting.

Note that not all the test options are compatible with the `cov.sh` build but this might be something we could improve over time.

>NOTE: `gcovr` is used in the reporting and has been notoriously unpredictable on MacOS and so it's used in a very simple way in concert
>with `gcov` to workaround the various failures we have seen.  If you are wondering why the `gcov` dance is in the script that's why.
>There was a time it was simpler.  It's still pretty simple though.

See [Testing](testing.md)
