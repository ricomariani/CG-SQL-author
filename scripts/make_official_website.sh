#!/bin/bash

set -o errexit -o nounset -o pipefail

# Usage in dev: ./make_official_website.sh server

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

git submodule update --init --recursive

hugo \
  --source $SCRIPT_DIR_RELATIVE/official_website \
  --destination ../out/official_website \
  $@
