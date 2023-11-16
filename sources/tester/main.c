/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <inttypes.h>

#include "cqlrt.h"
#include "dbhelp.h"
#include "cqlhelp.h"

// super cheesy error handling
#define E(x) \
if (SQLITE_OK != (x)) { \
 fprintf(stderr, "error encountered at: %s (%s:%d)\n", #x, __FILE__, __LINE__); \
 fprintf(stderr, "args: %s, %s\n", sql_name, result_name); \
 fprintf(stderr, "sqlite3_errmsg: %s\n", sqlite3_errmsg(db)); \
 goto error; \
}

const char *prefix = "The statement ending at line ";

// just some counts for tests, errors, attempts
int32_t tests = 0;
int32_t errors = 0;
int32_t attempts = 0;

// the database connection (global)
sqlite3 *db = NULL;

// the input test file with encoding for what to match
const char *sql_name;

// the result file with the prefix marks to associate against the input
// and the data we will match
const char *result_name;

// if anything goes wrong matching, we use this to print the error
static void print_error_message(char *buffer, int32_t line, int32_t expected) {
  printf("error: at line %d, expected '%s' %spresent", line, buffer, expected ? "" : "not ");

  // this indicates we expected a certain exact number of matches
  if (expected) {
    printf(" %s%d times\n", expected == -1 ? "at least " : "", expected == -1 ? 1 : expected);
  }
  printf("\n");
}

void do_match(char *buffer, int32_t line) {
  int32_t search_line;
  int32_t count;
  int32_t expected;

  // the comments encode the matches
  if (buffer[0] == '-' && buffer[1] == ' ') {
    // -- - foo
    // negation, none expected
    buffer++;
    expected = 0;
  }
  else if (buffer[0] == '+' && buffer[1] == ' ') {
    // -- + foo
    // at least one is expected, any number will do
    buffer++;
    expected = -1;
  }
  else if (buffer[0] == '+' && buffer[1] >= '0' && buffer[1] <= '9' && buffer[2] == ' ') {
    // -- +7 foo
    // an exact match (single digit matches)
    expected = buffer[1] - '0';
    buffer += 2;
  }
  else {
    // any other line is just a normal comment, ignore it
    return;
  }

  attempts++;

  // change the pattern to %foo%, we'll be using LIKE matching
  int32_t len = strlen(buffer);
  buffer[len-1] = '%';
  buffer[0] = '%';
  cql_string_ref ref = cql_string_ref_new(buffer);

  // search among all the matching lines
  E(dbhelp_find(db, line, ref, &search_line, &count));
  cql_string_release(ref);
  if (expected == count || (expected == -1 && count > 0)) {
    return;
  }

  // print error corresponding to the pattern
  errors++;
  print_error_message(buffer, line, expected);
  printf("found:\n");

  // dump all the text associated with this line (this could be many lines)
  // it's all the output associated with this test case
  E(dbhelp_dump_output(db, search_line));

  // find the line that ended the previous test block
  int32_t prev;
  E(dbhelp_prev_line(db, search_line, &prev));

  // dump everything from there to here, that's the test case
  printf("\nThe corresponding test case is:\n");
  E(dbhelp_dump_source(db, prev, search_line));

  // repeat the error so it's at the end also
  print_error_message(buffer, line, expected);
  printf("test file: %s\n", sql_name);
  printf("result file: %s\n", result_name);
  printf("\n");
  return;

error:
  printf("unexpected sqlite error\n");
  exit(1);
}

int main(int argc, char **argv) {
  cql_object_ref args = create_arglist(argc, argv);
  
  E(sqlite3_open(":memory:", &db));

  E(dbhelp_main(db, args));

  cql_object_release(args);

  // this procedure gets us all of the lines and the data on those lines in order
  dbhelp_source_result_set_ref result_set;
  E(dbhelp_source_fetch_results(db, &result_set));

  // get the count of rows (lines) and start looping
  cql_int32 count = dbhelp_source_result_count(result_set);
  for (cql_int32 i = 0; i < count; i++) {
    cql_string_ref ref;
    cql_int32 line = dbhelp_source_get_line(result_set, i);
    ref = dbhelp_source_get_data(result_set, i);

    // this is a single line of text from the test file
    char *text = (char*)ref->ptr;

    // the standard test prefix it just counts tests, this doesn't mean anything
    // but it's a useful statistic
    if (strstr(text, "-- TEST:")) {
      tests++;
    }

    // if it looks like a test directive then do the match and report errors
    if (!strncmp(text, "-- +", 4) || !strncmp(text, "-- -", 4)) {
      do_match(text + 3, line);
    }
  }
  cql_result_set_release(result_set);

  printf("Verification results: %d tests matched %d patterns of which %d were errors.\n", tests, attempts, errors);

  exit(errors);

error:
  exit(1);
}
