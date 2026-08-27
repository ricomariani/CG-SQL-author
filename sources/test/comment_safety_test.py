#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import subprocess
import sys


def main():
    c_source = open(sys.argv[1], encoding="utf-8").read()
    c_header = open(sys.argv[2], encoding="utf-8").read()
    lua_source = open(sys.argv[3], encoding="utf-8").read()

    marker = "Generated from safe\\n#error provenance_injection:"
    if marker not in c_source + c_header:
        raise AssertionError("C provenance control character was not encoded")
    if "\n#error provenance_injection" in c_source + c_header:
        raise AssertionError("C provenance escaped its line comment")

    if marker not in lua_source:
        raise AssertionError("Lua provenance control character was not encoded")
    if "--[=[" not in lua_source:
        raise AssertionError("Lua long comment delimiter was not strengthened")

    subprocess.run(
        ["lua", "-e", f"assert(loadfile({sys.argv[3]!r}))"],
        check=True,
    )


if __name__ == "__main__":
    main()
