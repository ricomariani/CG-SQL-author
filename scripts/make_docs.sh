#!/bin/bash

readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")

$SCRIPT_DIR_RELATIVE/make_guide.sh "user_guide" "CQL User's Guide" $SCRIPT_DIR_RELATIVE/../docs/user_guide/*.md $SCRIPT_DIR_RELATIVE/../docs/user_guide/**/*.md
$SCRIPT_DIR_RELATIVE/make_guide.sh "developer_guide" "CQL Developer's Guide" $SCRIPT_DIR_RELATIVE/../docs/developer_guide/*.md

