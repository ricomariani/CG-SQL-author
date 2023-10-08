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
  > $OUT/cql_grammar.txt
ls $OUT/cql_grammar.txt


debug "Building CQL Grammar Railroad diagram"

  # | sed -f $SCRIPT_DIR_RELATIVE/grammar_utils/diagram_tweaks.txt \
cat $OUT/cql_grammar.txt \
  | $SCRIPT_DIR_RELATIVE/grammar_utils/compile_bottlecaps_railroad_diagram.sh \
  > $OUT/cql_grammar.railroad.html
ls $OUT/cql_grammar.railroad.html


debug "Building CQL Grammar Javascript Tree Sitter"

$SCRIPT_DIR_RELATIVE/grammar_utils/tree_sitter.py $OUT/cql_grammar.txt \
  > $OUT/cql_grammar.tree_sitter.js
ls $OUT/cql_grammar.tree_sitter.js


debug "Building CQL Grammar Markdown article"

function operators_and_literals_section() {
  # use whole word match on these small replacements LS, RS, GE, LE, NE, EQEQ
  cat $CQL_ROOT_DIR/cql.y \
    | egrep "^%left|^%right|^%nonassoc" \
    | sed -e 's/%left //' -e 's/%right //' -e 's/%nonassoc //' -e 's/  *$//' \
    | $CQL_OUT_DIR/replacements
}

function statement_type_keywords_section() {
  cat $CQL_ROOT_DIR/cql.y |
  grep '%token [^<]' |        # Get only the lines starting with %token
  sed 's/%token //g' |        # Remove '%token ' from the start of each line
  tr ' ' '\n' |               # Put each token on a new line
  $CQL_OUT_DIR/replacements | # Apply our usual replacements
  sort |                      # Sort the tokens
  uniq |                      # Remove duplicates resulting from explicit string
                              # declarations (e.g., `%token NULL_ "NULL"`)
  grep '^"[A-Z@]' |           # Filter out operators present due to explicit
                              # string declarations (e.g., `%token EQEQ "=="`)
  tr '\n' ' ' |               # Group all tokens into a single line
  grep '' |                   # Restore the trailing newline
  fold -w 60 -s |             # Rewrap to a 60-column width
  sed 's/  *$//'              # Remove trailing spaces left by fold
}

function rules_section() {
  cat $OUT/cql_grammar_for_markdown.txt
}

cat <<EOF \
  | cat $SCRIPT_DIR_RELATIVE/grammar_utils/meta_licence_header.template.html - \
  > $OUT/cql_grammar.md
## Appendix 2: CQL Grammar

What follows is taken from a grammar snapshot with the tree building rules removed.
It should give a fair sense of the syntax of CQL (but not semantic validation).


### Operators and Literals

These are in order of priority lowest to highest

\`\`\`
$(operators_and_literals_section)
\`\`\`

NOTE: The above varies considerably from the C binding order!!!

Literals:
\`\`\`
ID        /* a name */
STRLIT    /* a string literal in SQL format e.g. 'it''s sql' */
CSTRLIT   /* a string literal in C format e.g. "hello, world\n" */
BLOBLIT   /* a blob literal in SQL format e.g. x'12ab' */
INTLIT    /* integer literal */
LONGLIT   /* long integer literal */
REALLIT   /* floating point literal */
\`\`\`

### Statement/Type Keywords

\`\`\`
$(statement_type_keywords_section)
\`\`\`

### Rules

Note that in many cases the grammar is more generous than the overall language
and errors have to be checked on top of this, often this is done on purpose because
even when it's possible it might be very inconvenient to do checks with syntax.
For example the grammar cannot enforce non-duplicate ids in id lists,
but it could enforce non-duplicate attributes in attribute lists.
It chooses to do neither as they are easily done with semantic validation. 
Thus the grammar is not the final authority on what constitutes a valid program but it's a good start.

\`\`\`
$(rules_section)
\`\`\`
EOF

rm -f $OUT/cql_grammar_for_markdown.txt >&2

ls $OUT/cql_grammar.md

debug ""
