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

# Accessor naming

Projection accessors use the shared customizable sample policy in
`sources/common/projection_names.py`: ordinary names are preserved, exotic names
use CQL-style `X_`/`Xhh` UTF-8 encoding, and collisions receive ordinal suffixes.
Bodies call the compiler-generated column-specific public getters, including
their NULL/value helpers for boxed scalars. Wrapper-name collision suffixes do
not change the native getter names.

Run `./test.sh --test binding_accessors_test --non_interactive` from `sources`.
With Clang and GNUstep, the regression compiles both Objective-C wrappers against
actual generated C headers and executes them using ordinal API test doubles.
This Linux check does not replace Apple ARC/CoreFoundation integration testing.
Without those tools, the additional native checks are explicitly skipped.

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
