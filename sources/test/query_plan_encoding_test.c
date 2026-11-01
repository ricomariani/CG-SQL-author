/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "cqlrt.h"

extern cql_code query_plan_encoding_test(sqlite3 *_Nonnull _db_);

static int reject_json(void *context, int action, const char *arg1,
                       const char *arg2, const char *database, const char *trigger) {
  if (action == SQLITE_FUNCTION && !strncmp(arg2, "json", 4)) {
    return SQLITE_DENY;
  }
  return SQLITE_OK;
}

int main(int argc, char **argv) {
  sqlite3 *db = NULL;
  cql_code rc = sqlite3_open(":memory:", &db);

  if (rc == SQLITE_OK) {
    rc = sqlite3_set_authorizer(db, reject_json, NULL);
  }
  if (rc == SQLITE_OK) {
    rc = query_plan_encoding_test(db);
  }

  if (rc) {
    fprintf(stderr, "sqlite error: code = %d, msg = %s\n", rc, sqlite3_errmsg(db));
  }

  sqlite3_close(db);
  assert(cql_outstanding_refs == 0);
  return rc;
}
