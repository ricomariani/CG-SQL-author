#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# This driver verifies that runtime contracts remain active when the companion
# C binary is compiled with NDEBUG.  It first runs the binary without arguments
# as a control case: all valid operations must complete successfully.  It then
# launches one child process for each named contract violation because a
# successful contract check terminates the process and therefore cannot share a
# process with later cases.  Each child must terminate specifically with
# SIGABRT; accepting any nonzero status would let an unrelated crash such as
# SIGSEGV masquerade as a successful contract check.

import subprocess
import signal
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
        "rows_equal_row_size_mismatch",
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
        if result.returncode != -signal.SIGABRT:
            raise AssertionError(
                f"contract test did not terminate with SIGABRT: "
                f"{test_case} returned {result.returncode}"
            )


if __name__ == "__main__":
    main()
