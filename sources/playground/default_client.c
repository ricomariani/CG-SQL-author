/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt.h"
#include EXAMPLE_HEADER_NAME

static int sqlite_trace_callback(unsigned type, void* ctx, void* p, void* x) {
  switch (type) {
    case SQLITE_TRACE_PROFILE:
      fprintf(stderr, "[SQLite] Statement: %s, Execution Time: %lld ns\n", sqlite3_sql((sqlite3_stmt*)p), *((sqlite3_int64*)x));
      break;
  }
  return 0;
}

// patternlint-disable-next-line prefer-sized-ints-in-msys
int main(int argc, char **argv) {
  sqlite3 *db = NULL;
  sqlite3_open(":memory:", &db);
  
  if (argc >= 2 && strcmp(argv[1], "-vvv") == 0) {
    sqlite3_trace_v2(db, SQLITE_TRACE_PROFILE, sqlite_trace_callback, NULL);
  }

  if (!(SQLITE_OK == entrypoint(db))) {
    printf("The call to the entrypoint procedure failed %s:%d\n", __FILE__, __LINE__);
    return 1;
  }

  return 0;
}
