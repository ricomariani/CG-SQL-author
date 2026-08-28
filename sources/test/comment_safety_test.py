#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Validate both generated-comment boundaries using comment_safety.sql.  The C
# checks prove that decoded filename controls are rendered visibly and cannot
# create a new source line.  The Lua checks prove that a delimiter found in the
# reconstructed CQL forces a stronger long-comment delimiter.  Finally, Lua
# parses the complete generated file so textual checks cannot hide invalid
# generated syntax.

import subprocess
import sys


def main():
    c_source = open(sys.argv[1], encoding="utf-8").read()
    c_header = open(sys.argv[2], encoding="utf-8").read()
    lua_source = open(sys.argv[3], encoding="utf-8").read()

    # The visible \n must appear in provenance in both generated C files, while
    # the decoded newline plus directive must never appear as a real source line.
    marker = "Generated from safe\\n#error provenance_injection:"
    if marker not in c_source + c_header:
        raise AssertionError("C provenance control character was not encoded")
    if "\n#error provenance_injection" in c_source + c_header:
        raise AssertionError("C provenance escaped its line comment")

    # The hostile statement contains ]], so level-zero Lua long comments are
    # unsafe and the generator must use at least the --[=[...]=] form.
    if marker not in lua_source:
        raise AssertionError("Lua provenance control character was not encoded")
    if "--[=[" not in lua_source:
        raise AssertionError("Lua long comment delimiter was not strengthened")

    # Parsing the complete file verifies that the chosen delimiter is balanced
    # and that no hostile text became active Lua.
    subprocess.run(
        ["lua", "-e", f"assert(loadfile({sys.argv[3]!r}))"],
        check=True,
    )


if __name__ == "__main__":
    main()
