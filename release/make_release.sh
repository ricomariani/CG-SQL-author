#!/bin/bash

set -euo pipefail

echo gathering the release pieces from the build locations

(cd ../sources; make clean; make; ./make_amalgam.sh)

cp ../sources/out/cql_amalgam.c .
cp ../sources/cqlrt*.c ../sources/cqlrt*.h ../sources/cqlrt*.lua .

./test_amalgam.sh
