Major releases will include a pre-built version of the amalgam at that point in time and the necessary runtime libraries that went with it.

You can make your own amalgam using the `make_amalgam.sh` script in the sources directory, the result goes in `sources/out/cql_amalgam.c`

This one-file version of the compiler can be stripped to just the parts you want using various defines (see `test_amalgam.sh` for examples)
and it is easily consumed.
