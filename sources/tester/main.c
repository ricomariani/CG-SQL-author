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
 fprintf(stderr, "sqlite3_errmsg: %s\n", sqlite3_errmsg(db)); \
 errors = -1; \
 goto error; \
}

extern int32_t errors;

int main(int argc, char **argv) {
  cql_object_ref args = create_arglist(argc, argv);
  
  sqlite3 *db = NULL;
  E(sqlite3_open(":memory:", &db));
  E(dbhelp_main(db, args));

error:
  if (db) sqlite3_close(db);
  cql_object_release(args);
  exit(errors);
}
