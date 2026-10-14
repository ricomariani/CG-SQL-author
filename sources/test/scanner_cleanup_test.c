/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <stdio.h>

#pragma clang diagnostic ignored "-Wnullability-completeness"

#define CQL_IS_NOT_MAIN
#include "out/cql_amalgam.c"

static bool_t check_scanner_compile(int32_t argc, const char **argv, int32_t expected) {
  int32_t result = cql_main(argc, (char **)argv);
  if (result != expected) {
    fprintf(stderr, "scanner cleanup compile returned %d, expected %d\n", result, expected);
    return false;
  }
  return true;
}

static bool_t check_borrowed_buffer(CSTR text, int32_t argc, const char **argv, int32_t expected) {
  YY_BUFFER_STATE buffer = yy_scan_string(text);
  bool_t success = check_scanner_compile(argc, argv, expected);
  // This is the documented embedding pattern: cql_main borrows this buffer
  // even on failure, and the caller must still be able to delete it afterward.
  yy_delete_buffer(buffer);
  return success;
}

int32_t main(int32_t argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "Usage: scanner_cleanup_test success.sql syntax.sql missing.sql\n");
    return 1;
  }

  const char *success_args[] = {"cql", "--in", argv[1], "--sem"};
  const char *syntax_args[] = {"cql", "--in", argv[2], "--sem"};
  const char *missing_args[] = {"cql", "--in", argv[3], "--sem"};
  const char *replacement_args[] = {"cql", "--in", argv[1], "--in", argv[1], "--sem"};
  const char *buffer_args[] = {"cql", "--sem"};
  const char *bad_args[] = {"cql", "--in"};

  // test.sh limits descriptors to 32; 64 rounds expose even one leaked file
  // per compile. Recovery also checks Flex's state after an interrupted include.
  for (int32_t i = 0; i < 64; i++) {
    if (!check_scanner_compile(4, success_args, 0) ||
        !check_scanner_compile(4, syntax_args, 2) ||
        !check_scanner_compile(4, missing_args, 1) ||
        !check_scanner_compile(6, replacement_args, 0)) {
      return 1;
    }

    // Test the borrowed buffer both as the current input and as a suspended
    // parent when an included file fails. Neither role transfers ownership.
    if (!check_borrowed_buffer("select 1;", 2, buffer_args, 0) ||
        !check_borrowed_buffer("select select", 2, buffer_args, 2) ||
        !check_borrowed_buffer("@include \"test/cql_amalgam_test_syntax_error.sql\"",
                              2, buffer_args, 2) ||
        !check_borrowed_buffer("@include \"test/test_include_file_not_found.sql\"",
                              2, buffer_args, 1)) {
      return 1;
    }

    // Argument errors happen before builtins setup. --in can reuse a borrowed
    // buffer, but ownership of the buffer must not follow ownership of the FILE.
    if (!check_borrowed_buffer("select 1;", 2, bad_args, 1) ||
        !check_borrowed_buffer("select select", 6, replacement_args, 0)) {
      return 1;
    }
  }

  // yyset_in lends a stream without lending a Flex buffer. The compiler owns
  // the buffer it creates, while the caller must still be able to use the FILE.
  FILE *borrowed = tmpfile();
  if (!borrowed) {
    perror("scanner cleanup tmpfile");
    return 1;
  }
  if (fputs("select 1;", borrowed) == EOF || fseek(borrowed, 0, SEEK_SET)) {
    perror("scanner cleanup input setup");
    fclose(borrowed);
    return 1;
  }
  yyset_in(borrowed);
  bool_t success = check_scanner_compile(2, buffer_args, 0);
  if (fseek(borrowed, 0, SEEK_SET)) {
    perror("scanner cleanup borrowed stream");
    success = false;
  }
  if (fclose(borrowed)) {
    perror("scanner cleanup borrowed stream close");
    success = false;
  }
  return success ? 0 : 1;
}
