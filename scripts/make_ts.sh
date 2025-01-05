#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly OUT=$SCRIPT_DIR_RELATIVE/out
readonly CQL_ROOT_DIR=$SCRIPT_DIR_RELATIVE/../sources
readonly CQL_OUT_DIR=$CQL_ROOT_DIR/out
readonly CQL_DOC_DIR=$SCRIPT_DIR_RELATIVE/../docs

if [ ! -f "$CQL_OUT_DIR/replacements" ]; then
  (mkdir -p $CQL_OUT_DIR; cd "$CQL_ROOT_DIR" ; make --quiet out/replacements) >&2
fi
mkdir -p $OUT
debug() { echo $@ >&2; }


debug "Cleanup remaining artifacts"
rm -f $OUT/cql_grammar.*


debug "Building CQL Grammar"

cat $CQL_ROOT_DIR/cql.y \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/remove_c_code_from_yacc_output.awk >x

cat $CQL_ROOT_DIR/cql.y \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/remove_c_code_from_yacc_output.awk \
  | sed -e "/^  *$/d" \
  | $CQL_OUT_DIR/replacements \
  | sed -e "s/  *$//" \
  | tee $OUT/cql_grammar_for_markdown.txt \
  | cat <(echo "// @nolint") - \
  | awk 'BEGIN { FS="\n"; RS="" } { gsub("\n","",$0); print }' \
  | sed \
      -e 's/:/ ::= /' \
      -e 's/;$//' \
      -e 's/  */ /g' \
      -e 's/  *$//' \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/grammar_inline.py \
  > $OUT/cql_grammar.txt
ls $OUT/cql_grammar.txt


debug "Building CQL Grammar Javascript Tree Sitter"

$SCRIPT_DIR_RELATIVE/grammar_utils/tree_sitter.py $OUT/cql_grammar.txt \
  > $OUT/cql_grammar.tree_sitter.js
ls $OUT/cql_grammar.tree_sitter.js
