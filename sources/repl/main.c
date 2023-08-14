/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt.h"
#include "go.h"

// super cheesy error handling
#define _E(c, x) if (!(c)) { \
  printf("!" #x "%s:%d\n", __FILE__, __LINE__); \
  goto error; \
}

#define E(x) _E(x, x)
#define SQL_E(x) _E(SQLITE_OK == (x), x)

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
  printf("CQL Mini App Thingy\n");

  sqlite3 *db = NULL;
  SQL_E(sqlite3_open(":memory:", &db));

  if (argc >= 2 && strcmp(argv[1], "-vvv") == 0) {
    sqlite3_trace_v2(db, SQLITE_TRACE_PROFILE, sqlite_trace_callback, NULL);
  }

  SQL_E(go(db));
  return 0;

error:
  return 1;
}
