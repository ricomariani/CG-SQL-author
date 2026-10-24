#!/usr/bin/env python3

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import pathlib
import subprocess
import sys


# This driver checks whether the compiler accepts a literal and, on failure,
# which phase rejects it. It does not execute SQL or check computed values;
# integer_literal_bit_patterns in run_test.sql covers those runtime semantics.
#
# Decimal magnitudes normally stop at INT64_MAX. The sole exception is 2^63,
# which must survive scanning so semantic analysis can accept it under unary
# minus as INT64_MIN. Hexadecimal literals instead describe all 64 bits, so
# patterns above INT64_MAX are valid and represent negative signed values.
def main():
    # test.sh supplies the selected compiler (regular or amalgam) and its output
    # directory. Reuse one scratch input so every invocation sees an isolated
    # case, and keep generated inputs out of the checked-in test directory.
    compiler = sys.argv[1]
    source = pathlib.Path(sys.argv[2]) / "integer_literals.sql"
    accepted = [
        # Zero is the smallest magnitude and the accumulator's initial value.
        # Rejection means the ordinary zero token or an empty-looking value broke.
        "0",
        # INT32_MAX is the last positive value eligible for an unsuffixed INT.
        # Rejection means the 32-bit upper endpoint is incorrectly excluded.
        "2147483647",
        # INT32_MAX+1 must remain legal by becoming a LONG, not overflowing INT.
        # Rejection means crossing the 32-bit boundary rejects a valid long.
        "2147483648",
        # INT64_MAX is the largest ordinary decimal magnitude.
        # Rejection means the signed 64-bit upper endpoint is excluded.
        "9223372036854775807",
        # -2^63 is INT64_MIN: its positive magnitude is exceptional, but the
        # direct unary minus makes it valid. Rejection loses the signed minimum.
        "-9223372036854775808",
        # This is the same INT64_MIN with a leading zero in its magnitude.
        # Rejection means recognizing the minimum depends on its raw spelling
        # rather than normalizing the exceptional magnitude.
        "-09223372036854775808",
        # Hex INT32_MAX exercises the last unsuffixed INT-sized hex value.
        # Rejection means the hexadecimal 32-bit endpoint is excluded.
        "0x7fffffff",
        # Hex 2^31 is a positive LONG, not a negative 32-bit INT.
        # Rejection means hex values cannot cross the INT-to-LONG boundary.
        "0x80000000",
        # Hex INT64_MAX is the last pattern without its 64-bit sign bit set.
        # Rejection means the hexadecimal signed-positive endpoint is excluded.
        "0x7fffffffffffffff",
        # The pattern with only bit 63 set represents INT64_MIN, without unary
        # minus. Rejection confuses a valid hex bit pattern with decimal overflow.
        "0x8000000000000000",
        # UINT64_MAX has every bit set and represents signed -1 in hex.
        # Rejection means the scanner incorrectly applies a signed magnitude
        # limit to hex, excluding the top half of the valid 64-bit patterns.
        "0xffffffffffffffff",
        # 0XABCDEF is a small, valid pattern using an uppercase prefix and A..F.
        # Rejection means case-insensitive hex spelling or letter digits broke.
        "0XABCDEF",
    ]
    rejected = [
        # INT64_MAX+2 is the first decimal magnitude beyond the one exceptional
        # INT64_MIN magnitude. Acceptance makes the exception too permissive;
        # a semantic-only error means the scanner did not enforce its limit.
        "9223372036854775809",
        # UINT64_MAX fits the scanner's unsigned accumulator, but is not a valid
        # decimal magnitude. Acceptance conflates decimal and hex range rules.
        "18446744073709551615",
        # UINT64_MAX+1 cannot fit even the unsigned accumulator. Acceptance can
        # indicate that accumulation wrapped to zero before the range check.
        "18446744073709551616",
        # Hex 2^64 requires a 65th bit, unlike the accepted all-ones 64-bit case.
        # Acceptance means overflowing hex accumulation was allowed to wrap.
        "0x10000000000000000",
        # INT64_MIN-1 cannot be rescued by unary minus: its magnitude is already
        # too large. Acceptance admits a value below the signed minimum; a
        # semantic-only error means an oversized magnitude escaped the scanner.
        "-9223372036854775809",
    ]
    invalid_context = [
        # Bare 2^63 must survive lexing but cannot be a positive signed LONG.
        # Semantic acceptance means the INT64_MIN exception escaped its required
        # unary-minus context; rejection in echo/expansion means checking moved
        # back into an inappropriate parser-wide validation pass.
        "9223372036854775808",
        # The inner minus forms INT64_MIN, but the outer minus would form +2^63.
        # Semantic acceptance permits an unrepresentable negated minimum.
        # The space is intentional: "--" would start a SQL comment instead.
        "- -9223372036854775808",
    ]
    cases = []
    # No suffix exercises inferred width. Uppercase L forces LONG even for zero
    # and other small values; lowercase l checks the scanner's case-insensitive
    # suffix rule. Different outcomes imply that suffix handling bypasses a range
    # check or incorrectly changes which magnitudes are legal.
    for suffix in ("", "L", "l"):
        cases.extend((f"select {value}{suffix};", None) for value in accepted)
        cases.extend((f"select {value}{suffix};", "lexical") for value in rejected)
        cases.extend(
            (f"select {value}{suffix};", "semantic") for value in invalid_context
        )
    cases.extend([
        # Empty user input is valid, including with the implicit builtins.
        # Failure means the literal changes disturbed empty-input processing.
        ("", None),
        # The macro supplies the complete -2^63 expression. Failure means a
        # valid minimum is rejected when its unary-minus parent is macro-created.
        ("@macro(expr) minimum!() begin -9223372036854775808 end;"
         "select minimum!();", None),
        # Expansion places another minus around the macro's INT64_MIN. Semantic
        # acceptance means validation missed the expanded parent relationships;
        # echo/expansion alone must still accept this syntactically valid tree.
        ("@macro(expr) minimum!() begin -9223372036854775808 end;"
         "select -minimum!();", "semantic"),
        # The argument is bare 2^63 until the macro supplies its unary minus.
        # Rejection means validation ran before expansion could make it valid,
        # or semantic analysis failed to recognize the resulting minimum.
        ("@macro(expr) negate!(x! expr) begin -x! end;"
         "select negate!(9223372036854775808);", None),
        # An enum initializer cannot use positive 2^63. Acceptance means enum
        # processing bypasses the normal numeric-literal context check.
        ("declare enum bad long (v = 9223372036854775808);", "semantic"),
        # An enum initializer must reject negated INT64_MIN before evaluating it.
        # Acceptance, a crash, or the wrong failure phase means an erroneous enum
        # expression was evaluated or its semantic error was not propagated.
        ("declare enum bad long (v = - -9223372036854775808);", "semantic"),
        # Named constant evaluation must not turn bare 2^63 into a valid value.
        # Acceptance means the constant-group path missed the semantic guard.
        ("const group bad (v = 9223372036854775808);", "semantic"),
        # A LONG column does not make positive 2^63 a valid default.
        # Acceptance means default-value analysis bypasses literal validation.
        ("create table bad(x long default 9223372036854775808);", "semantic"),
        # Arbitrary attribute values also need the 2^63 context check, even though
        # they are metadata rather than ordinary SQL expressions. Acceptance
        # means the existing attribute traversal did not validate numeric leaves.
        ("@attribute(v=9223372036854775808) create table bad(x int);", "semantic"),
        # The first list element is valid INT64_MIN; the second is invalid +2^63.
        # Acceptance means traversal stopped after the good element, skipped
        # nested values, or failed to propagate an invalid child's error.
        ("@attribute(v=(-9223372036854775808,9223372036854775808))"
         "create table bad(x int);", "semantic"),
        # A metadata attribute may legitimately hold -2^63. Rejection means
        # attribute validation forbids the exceptional magnitude indiscriminately
        # instead of respecting its valid unary-minus parent.
        ("@attribute(v=-9223372036854775808) create table good(x int);", None),
    ])

    for sql, error_stage in cases:
        source.write_text(sql, encoding="utf-8")
        # Echo parses only; expansion adds macro rewriting; semantics also checks
        # value contexts after expansion. Lexical errors must fail in all three.
        # Context errors must fail only with --sem, not in syntax-only modes.
        for mode in ("--echo", "--sem", "--exp"):
            result = subprocess.run(
                [compiler, mode, "--in", str(source)],
                capture_output=True, text=True, check=False,
            )
            # Zero is normal compiler success, including syntax-only processing
            # of a literal whose context would be invalid during semantics.
            status = 0
            if error_stage == "lexical":
                # Exit 2 specifically means a scanner/parser error. Merely
                # checking nonzero would let a crash masquerade as safe rejection.
                status = 2
            elif error_stage == "semantic" and mode == "--sem":
                # Exit 1 is the compiler's semantic-error status. Requiring it
                # distinguishes the intended context diagnostic from a parse
                # failure or an abort while evaluating an invalid constant.
                status = 1
            # The status alone is insufficient: require the range diagnostic so
            # an unrelated syntax/name/type error cannot satisfy a negative case.
            if result.returncode != status or (
                status and "integer literal out of range" not in result.stderr
            ):
                raise AssertionError(
                    f"{mode} {sql!r}: expected status {status}, "
                    f"got {result.returncode}\n{result.stdout}\n{result.stderr}"
                )


if __name__ == "__main__":
    main()
