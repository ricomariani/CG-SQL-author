#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

hugo server \
  --source $SCRIPT_DIR_RELATIVE/official_website \
  --destination ../out/official_website \
  $@
