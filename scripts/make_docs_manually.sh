#!/bin/bash

# This script is used to debug the doc build process. It is not used by the CI/CD.

set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

$SCRIPT_DIR_RELATIVE/make_cql_grammar_outputs.sh
$SCRIPT_DIR_RELATIVE/make_json_grammar_outputs.sh
$SCRIPT_DIR_RELATIVE/make_query_plan_grammar_outputs.sh

cp $SCRIPT_DIR_RELATIVE/out/json_grammar.md $SCRIPT_DIR_RELATIVE/../docs/user_guide/appendices/02_grammar.md
cp $SCRIPT_DIR_RELATIVE/out/cql_grammar.md $SCRIPT_DIR_RELATIVE/../docs/user_guide/appendices/05_json_schema_grammar.md

# Build regardless of whether the chapters are stubs or not
FORCE_BUILD="true" $SCRIPT_DIR_RELATIVE/make_guide.sh all

git restore $SCRIPT_DIR_RELATIVE/../docs/user_guide/appendices/02_grammar.md
git restore $SCRIPT_DIR_RELATIVE/../docs/user_guide/appendices/05_json_schema_grammar.md