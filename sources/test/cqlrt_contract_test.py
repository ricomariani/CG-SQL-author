#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import subprocess
import sys


def main():
    binary = sys.argv[1]
    subprocess.run([binary], check=True)

    cases = [
        "contract_failure",
        "invariant_failure",
        "row_hash_negative",
        "rows_equal_first_negative",
        "rows_equal_second_negative",
        "rows_same_first_negative",
        "rows_same_second_negative",
        "rowset_copy_count_negative",
        "rowset_copy_count_high",
        "rowset_copy_from_high",
        "result_get_row_negative",
        "result_get_row_high",
        "result_get_col_negative",
        "result_get_col_high",
        "result_set_row_negative",
        "result_set_col_high",
        "result_is_null_row_negative",
        "result_set_null_col_high",
        "string_get_negative",
        "string_set_high",
        "long_get_negative",
        "long_set_high",
        "real_get_negative",
        "real_set_high",
    ]

    for test_case in cases:
        result = subprocess.run(
            [binary, test_case],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            raise AssertionError(
                f"contract test unexpectedly succeeded: {test_case}"
            )


if __name__ == "__main__":
    main()
