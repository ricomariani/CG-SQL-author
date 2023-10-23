#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly OUT=$SCRIPT_DIR_RELATIVE/out
readonly CQL_ROOT_DIR=$SCRIPT_DIR_RELATIVE/../sources
readonly CQL_OUT_DIR=$CQL_ROOT_DIR/out

if [ ! -f "$CQL_OUT_DIR/json_replacements" ]; then
  (mkdir -p $CQL_OUT_DIR; cd "$CQL_ROOT_DIR" ; make --quiet out/json_replacements) >&2
fi
mkdir -p $OUT
debug() { echo $@ >&2; }


debug "Cleanup remaining artifacts"
rm -f $OUT/json_grammar.*


debug "Building JSON Grammar"

cat $CQL_ROOT_DIR/json_test/json_test.y \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/remove_c_code_from_yacc_output.awk \
  | sed -e "/^  *$/d" \
  | $CQL_OUT_DIR/json_replacements \
  | sed -e "s/  *$//" \
  > $OUT/json_grammar.txt
ls $OUT/json_grammar.txt


debug "Building JSON Grammar Railroad diagram"

cat $OUT/json_grammar.txt \
  | awk 'BEGIN { FS="\n"; RS="" } { gsub("\n","",$0); print }' \
  | sed \
      -e 's/:/ ::= /' \
      -e 's/;$//' \
      -e 's/  */ /g' \
      -e 's/  *$//' \
  | grep -v '^BOOL_LITERAL' \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/compile_bottlecaps_railroad_diagram.sh \
  > $OUT/json_grammar.railroad.html
ls $OUT/json_grammar.railroad.html


debug "Building JSON Grammar Markdown article"

function rules_section() {
  cat $OUT/json_grammar.txt
}

cat <<EOF > $OUT/json_grammar.md
---
title: "Appendix 5: JSON Schema Grammar"
weight: 5
---
$(cat $SCRIPT_DIR_RELATIVE/grammar_utils/meta_licence_header.template.html)

What follows is taken from the JSON validation grammar with the tree building rules removed.

### Rules

\`\`\`
$(rules_section)
\`\`\`
EOF

ls $OUT/json_grammar.md

debug ""
