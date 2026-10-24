#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import pathlib
import subprocess
import sys


def check(command, expected_status, diagnostic=None):
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    # Require the phase-specific exit status, not merely a nonzero result:
    # a signal or contract abort must not masquerade as deliberate rejection.
    if result.returncode != expected_status or (
        diagnostic and diagnostic not in result.stderr
    ):
        raise AssertionError(
            f"{command!r}: expected status {expected_status}"
            f" and diagnostic {diagnostic!r}, got {result.returncode}\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result.stdout


def main():
    # test.sh chooses the regular or amalgam compiler. Scratch input belongs in
    # its output directory and is overwritten so cases cannot affect each other.
    compiler = sys.argv[1]
    source = pathlib.Path(sys.argv[2]) / "numeric_inputs.sql"
    source.write_text("select 1;", encoding="utf-8")
    # The SQL value 1 is just a valid, schema-independent input. These checks
    # exercise CLI parsing, not database execution or schema migration behavior.
    cli_cases = [
        # Zero is the existing default, meaning no minimum-version filtering.
        # Rejection would break explicitly requesting the default behavior.
        ("0", True),
        # One is the first positive schema version; rejection would break the
        # smallest useful non-default argument.
        ("1", True),
        # Leading zeros must still mean decimal one. Rejection means the new
        # spelling rule became stricter than the intended decimal-digit grammar.
        ("0001", True),
        # INT32_MAX is the last value that fits the signed option storage.
        # Rejection means the inclusive upper endpoint was implemented wrongly.
        ("2147483647", True),
        # Empty text used to become zero through atoi. Acceptance would silently
        # disable filtering instead of telling the caller its argument is missing.
        ("", False),
        # Negative one is outside the nonnegative version domain. Acceptance
        # means signed spelling bypassed validation.
        ("-1", False),
        # Explicit plus is not a decimal digit. Acceptance means the parser kept
        # atoi's optional-sign grammar instead of the documented digits-only one.
        ("+1", False),
        # Leading whitespace was accepted by atoi; it must not hide a malformed
        # argument now. Acceptance means digit validation was skipped.
        (" 1", False),
        # Trailing whitespace must not be silently discarded. Acceptance means
        # the whole-argument check stopped at a valid numeric prefix.
        ("1 ", False),
        # This has a valid numeric prefix but is not wholly decimal. Acceptance
        # reproduces atoi's silent truncation of malformed input.
        ("1x", False),
        # INT32_MAX+1 tests the first unrepresentable option value. Acceptance
        # means an inclusive-bound error or narrowing overflow remains.
        ("2147483648", False),
        # Forty nines exceed even unsigned 64-bit storage, not just the option's
        # 32-bit domain. Acceptance or an abort means accumulation was unchecked
        # or narrowed before the overflow decision.
        ("9999999999999999999999999999999999999999", False),
    ]
    for value, valid in cli_cases:
        # Put --in first so invalid-option cleanup also has an owned input
        # stream to release, preserving the scanner-ownership fixes.
        command = [
            compiler, "--sem", "--in", str(source), "--min_schema_version", value,
        ]
        # Zero denotes success; one is the existing CLI-error exit status.
        # The specific diagnostic rules out unrelated failures satisfying a case.
        check(
            command, 0 if valid else 1,
            None if valid else "invalid minimum schema version",
        )

    line_cases = [
        # One is the first legal source line. Rejection would exclude the lower
        # endpoint; an echoed zero would expose the directive's off-by-one bug.
        ("1", 1),
        # Leading-zero decimal one must set the same source line as bare one.
        # Failure means decimal spelling or line-counter installation changed.
        ("0001", 1),
        # INT32_MAX/2 is the inclusive directive limit, intentionally leaving
        # over a billion scanner increments before overflow. Failure means the
        # policy endpoint or the subsequent line increment is incorrect.
        ("1073741823", 1073741823),
        # Zero would install -1 before the scanner consumes the directive's
        # newline, leaving the next token on invalid line zero. Acceptance or a
        # crash means validation happened after scanner state was corrupted.
        ("0", None),
        # This is INT32_MAX/2+1, still representable but beyond the chosen
        # headroom policy. Acceptance means the directive limit was not enforced.
        ("1073741824", None),
        # INT32_MAX fits a plain int, but leaves no room for the next newline.
        # Acceptance would let a tiny following input overflow the line counter.
        ("2147483647", None),
        # Forty nines exercise rejection without any representable intermediate
        # integer. Acceptance, a signal, or a contract failure would reveal
        # unchecked conversion or a wrapped scanner line number.
        ("9999999999999999999999999999999999999999", None),
    ]
    # Both supported directive forms must obey the same range and preserve the
    # same next-line semantics. The spelling must not choose a weaker path.
    for prefix in ("#line", "#"):
        for value, expected_line in line_cases:
            # Keep real statements after the directive: an invalid installed
            # line could otherwise go unnoticed until an AST node is created.
            # The second statement proves normal increments continue afterward.
            source.write_text(
                f'{prefix} {value} "numeric_input.sql"\n'
                "select @line as source_line;\n"
                "select @line as next_line;\n",
                encoding="utf-8",
            )
            command = [compiler, "--echo", "--hide_builtins", "--in", str(source)]
            if expected_line is None:
                # Two is the scanner/parser-error status. Require the directive
                # diagnostic rather than accepting a generic SQL syntax failure.
                # The directive is on physical line one, and parser diagnostics
                # use column one. Its error must retain the original file/line,
                # not the rejected mapping to numeric_input.sql.
                check(
                    command, 2,
                    f"{source}:1:1: error: invalid #line directive line number",
                )
            else:
                # A valid directive must succeed and affect @LINE exactly, not
                # merely avoid an error. One additional line must add exactly one.
                output = check(command, 0)
                first = f"SELECT {expected_line} AS source_line;"
                following = f"SELECT {expected_line + 1} AS next_line;"
                if first not in output or following not in output:
                    raise AssertionError(
                        f"{prefix} {value}: incorrect source lines\n{output}"
                    )


if __name__ == "__main__":
    main()
