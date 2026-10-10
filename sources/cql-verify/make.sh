#!/bin/bash

set -euo pipefail

./regen.sh
make -C .. cql-verify
