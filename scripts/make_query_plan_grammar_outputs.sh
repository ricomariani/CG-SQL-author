#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly OUT=$SCRIPT_DIR_RELATIVE/out

mkdir -p $OUT
debug() { echo $@ >&2; }


debug "Cleanup remaining artifacts"
rm -f $OUT/query_plan_grammar.*


debug "Building Query Plan Grammar Railroad diagram"

cat $SCRIPT_DIR_RELATIVE/grammar_utils/query_plan_grammar.txt \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/compile_bottlecaps_railroad_diagram.sh \
  > $OUT/query_plan_grammar.railroad.html

ls $OUT/query_plan_grammar.railroad.html

debug ""