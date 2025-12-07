# Summary

This is a snapshot of the key runtime files plus the compiler in amalgam form.  The `beta` drop
is updated more frequently than the release drop but the mechanism is the same.

The idea is that you can readily consume the beta without needing to meet the requirements of
a build.  i.e. you don't need `bison` or `flex` for instance.

This directory also serves as an LKG of sorts and compiler output can be readily compared against
a baseline if that is needed.  In fact even creating a local `beta` that you have no intent to
publish can be useful.

# Contents

* `cqlrt.c` -- the primary C runtime
* `cqlrt.h` -- headers for the same
* `cqlrt.lua` -- the lua version of the runtime
* `cqlrt_cf.c` -- the CF version of the runtime
* `cqlrt_cf.h` -- headers for the same
* `cqlrt_common.c` -- the common parts of the runtime (uses `cqlrt` or `cqlrt_cf`)
* `cqlrt_common.h` -- headers for the same
* `cql_amalgam.c` -- the compiler in amalgam form
* `make_beta.sh` -- script to create the above and do basic testing on it