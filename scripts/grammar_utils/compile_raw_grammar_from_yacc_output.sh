#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly CQL_ROOT_DIR=$SCRIPT_DIR_RELATIVE/../../sources
readonly CQL_OUT_DIR=$CQL_ROOT_DIR/out

(mkdir -p $CQL_OUT_DIR; cd "$CQL_ROOT_DIR" ; make --quiet out/replacements) >&2

function remove_lines_containing_only_spaces { sed -e "/^  *$/d"; }
function normalize_tokens { $CQL_OUT_DIR/replacements; }
function remove_trailing_spaces { sed -e "/^  *$/d"; }

cat - \
  | $SCRIPT_DIR_RELATIVE/remove_c_code_from_yacc_output.awk \
  | remove_lines_containing_only_spaces \
  | normalize_tokens \
  | remove_trailing_spaces
