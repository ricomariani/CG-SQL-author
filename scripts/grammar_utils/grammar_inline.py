#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import sys
import re

words = [
    # The presence of this node break tree-sitter. It was added to
    # 'create_table_stmt' for the sole purpose of grabbing documentation
    "create_table_prefix_opt_temp",
    "ifdef",
    "ifndef",
    "elsedef",
    "endif",
]

# Create a regex pattern to match whole words with case sensitivity
# Search for any match in the text
any_word_pattern = r'\b(' + '|'.join(re.escape(word) for word in words) + r')\b'

word_patterns = {}
rules = {}

for word in words:
   word_patterns[word] = r'\b' + re.escape(word) + r'\b'

# Read all lines from stdin into a list
lines = [line.strip() for line in sys.stdin]

# make the rule mapping
for line in lines:
    # Strip whitespace (including newline) and split on '::='
    parts = line.split("::=", 1)
    
    # Check if there are exactly two parts (left and right)
    if len(parts) != 2:
        continue

    key, value = parts[0].strip(), parts[1].strip()
    rules[key] = value


# now find all the replacements

for line in lines:
    # Strip whitespace (including newline) and split on '::='
    parts = line.split("::=", 1)
    
    # Check if there are exactly two parts (left and right)
    if len(parts) != 2:
        continue
   
    key, value = parts[0].strip(), parts[1].strip()

    # this is being inlined, we don't want it
    if key in words:
        continue

    if not re.search(any_word_pattern, value):
        print(line)
        continue

    for word in words:
        line = re.sub(word_patterns[word], rules[word], line)

    print(line)
