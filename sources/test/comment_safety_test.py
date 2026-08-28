#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Validate both generated-comment boundaries using comment_safety.sql.  The C
# checks prove that decoded filename controls are rendered visibly and cannot
# create a new source line.  The Lua checks prove that a delimiter found in the
# reconstructed CQL forces a stronger long-comment delimiter and that the
# hostile text remains between the matching opener and closer.  The test
# intentionally uses only Python because Lua is not a test-suite dependency.

import sys


def main():
    c_source = open(sys.argv[1], encoding="utf-8").read()
    c_header = open(sys.argv[2], encoding="utf-8").read()
    lua_source = open(sys.argv[3], encoding="utf-8").read()

    # The visible \n must appear in provenance in both generated C files, while
    # the decoded newline plus directive must never appear as a real source line.
    marker = "Generated from safe\\n#error provenance_injection:"
    if marker not in c_source or marker not in c_header:
        raise AssertionError("C provenance control character was not encoded")
    if "\n#error provenance_injection" in c_source + c_header:
        raise AssertionError("C provenance escaped its line comment")

    # The hostile statement contains ]], so level-zero Lua long comments are
    # unsafe and the generator must use at least the --[=[...]=] form.
    if marker not in lua_source:
        raise AssertionError("Lua provenance control character was not encoded")
    if "--[=[" not in lua_source:
        raise AssertionError("Lua long comment delimiter was not strengthened")

    # Locate the reconstructed CQL comment and verify that its hostile ]] text
    # occurs before the matching level-one closer.  Since ]] cannot close a
    # --[=[ comment, these ordered markers prove the source stays commented
    # without requiring a Lua interpreter.
    open_index = lua_source.find("--[=[\nPROC comment_safety")
    hostile_index = lua_source.find("error('lua_comment_injection')", open_index)
    close_index = lua_source.find("--]=]", hostile_index)
    if not 0 <= open_index < hostile_index < close_index:
        raise AssertionError("CQL source escaped its strengthened Lua comment")


if __name__ == "__main__":
    main()
