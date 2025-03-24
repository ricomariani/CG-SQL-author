/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt.h"

extern cql_code cql_startup(sqlite3 *db);
extern cql_code run_client(sqlite3 *db);

// This is some basic "main" code to run the two run test sources
// there are some manual tests from the C world which are in
// run_client.  These basically exercise the CQL ABI from the C
// perspective. There was once a time when a lot of things had
// to be done this way because CQL could not consume itself.
// The primary tests are the cql self-authoered ones from run_test.sql.
// those start at cql_startup.
int main(int argc, char **argv) {
  // Setup database
  sqlite3 *db = NULL;
  cql_code rc;

  // first access the database using the C interface
  rc = sqlite3_open(":memory:", &db);
  if (rc == SQLITE_OK) {
    rc = run_client(db);
  }
  sqlite3_close(db);
  if (rc) exit(rc);

  // now try again using the stored procs and a clean db
  rc = sqlite3_open(":memory:", &db);
  if (rc == SQLITE_OK) {
    rc = cql_startup(db);
  }

  sqlite3_close(db);
  exit(rc);
}
