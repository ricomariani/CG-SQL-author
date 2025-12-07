# Summary

A CQL runtime designed for use with Apple CF. This code defines the CQLRT implementation using
CF notions to retain/release etc.  CQL strings map to `CFStringRef`.  CQL blobs map to `CFDataRef`.
The necessary comparisons and so forth are included such the `cqlrt_common` can do the rest.

* `clean.sh` -- cleans all build artifacts
* `cqlholder.m` -- a simple ObjC wrapper that retains a CQL reference
* `cqlobjc.py` -- converts CQL JSON format into interop functions for Objective-C
* `cqlrt_cf.c` -- the C helpers needed to do the linkage to CF
* `cqlrt_cf.h` -- the cqlrt.h equivalent
* `demo_main.m` -- an objective C file that uses `demo_todo.sql` using ObjC interface
* `demo_todo.sql` -- the procedures we are going to invoke
* `make.sh` -- builds the system and runs it
* `min.sh` -- minimal build-only, use where CF is missing (e.g. on Linux) but you want to to try to catch build errors

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
