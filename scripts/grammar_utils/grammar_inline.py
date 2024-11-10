#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import sys
import re

# All of these are actually redundant productions where we need
# the action in the grammar at the point that we have shifted far
# enough.  We don't actually want to document this business it
# just makes the grammar harder to understand so we inline these
# productions into the rules directly.
words = [
    "create_table_prefix_opt_temp",
    "cte_tables_macro_def",
    "elsedef",
    "endif",
    "expr_macro_def",
    "ifdef",
    "ifndef",
    "query_parts_macro_def",
    "select_core_macro_def",
    "select_expr_macro_def",
    "stmt_list_macro_def",
]

# Create a regex pattern to match whole words with case sensitivity
any_word_pattern = r'\b(' + '|'.join(re.escape(word)
                                     for word in words) + r')\b'

# this is a pattern for each word individually, we will use these to
# make replacements once we find any match.
word_patterns = {}

for word in words:
    word_patterns[word] = r'\b' + re.escape(word) + r'\b'

# this will hold all the lines keyed by rule
rules = {}

# Read all lines from stdin into a list
lines = [line.strip() for line in sys.stdin]

# make the rule mapping
for line in lines:
    # Strip whitespace (including newline) and split on '::='
    parts = line.split("::=", 1)

    # Check if there are exactly two parts (left and right)
    if len(parts) != 2:
        continue

    # record the key and value in the rules table
    key, value = parts[0].strip(), parts[1].strip()
    rules[key] = value

# Now find all the replacements, we have to do this in two passes
# because the replacement values might come after the replacement
# locations in the grammar.

for line in lines:
    # Strip whitespace (including newline) and split on '::='
    parts = line.split("::=", 1)

    # Check if there are exactly two parts (left and right)
    if len(parts) != 2:
        continue

    # same split as before
    key, value = parts[0].strip(), parts[1].strip()

    # this is being inlined, we don't want it
    if key in words:
        continue

    # if we found any pattern apply all replacements
    if re.search(any_word_pattern, value):
        for word in words:
            line = re.sub(word_patterns[word], rules[word], line)

    print(line)
