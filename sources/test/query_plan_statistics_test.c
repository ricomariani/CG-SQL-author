/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <stdio.h>
#include <assert.h>
#include "cqlrt.h"

extern cql_code query_plan_statistics_test(sqlite3 *_Nonnull _db_);

int main(int argc, char **argv) {
  sqlite3 *db = NULL;
  cql_code rc = sqlite3_open(":memory:", &db);

  if (rc == SQLITE_OK) {
    rc = query_plan_statistics_test(db);
  }
  if (rc) {
    fprintf(stderr, "sqlite error: code = %d, msg = %s\n", rc, sqlite3_errmsg(db));
  }

  sqlite3_close(db);
  assert(cql_outstanding_refs == 0);
  return rc;
}
