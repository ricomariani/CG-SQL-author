#!/bin/bash
set -o errexit -o nounset -o pipefail

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

$SCRIPT_DIR_RELATIVE/make_cql_grammar_outputs.sh
$SCRIPT_DIR_RELATIVE/make_json_grammar_outputs.sh
$SCRIPT_DIR_RELATIVE/make_query_plan_grammar_outputs.sh

$SCRIPT_DIR_RELATIVE/make_guide.sh all
