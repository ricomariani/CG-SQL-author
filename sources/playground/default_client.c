/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


// Extensive use of macros to tailor for the playground's adaptability providing users with a flexible testing environment.
// In standard applications, such dynamism may not be necessary.
// See `./play.sh` for more details about how the values of these macros are resolved and how they are injected.


// The compiled procedure's header file path is resolved by `./play.sh` based the example procedure chosen to embed
#include HEADER_FILE_FOR_SPECIFIC_EXAMPLE

// Header file for the CQL Runtime (cqlrt) dynamically included using the CQL compiler --cqlrt flag. Defaults to:
// #include "cqlrt.h"

#ifndef SQLITE_FILE_PATH_ABSOLUTE
  #define SQLITE_FILE_PATH_ABSOLUTE ":memory:"
#endif

#ifdef ENABLE_SQLITE_ERROR_TRACING
  #define cql_error_trace() \
    fprintf(stderr, "[SQLite] Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
#else
  #define cql_error_trace()
#endif

#ifdef ENABLE_SQLITE_STATEMENT_TRACING
static int sqlite_trace_callback(unsigned type, void* ctx, void* p, void* x) {
  switch (type) {
    case SQLITE_TRACE_PROFILE:
      fprintf(stderr, "[SQLite] Statement: %s, Execution Time: %lld ns\n", sqlite3_sql((sqlite3_stmt*)p), *((sqlite3_int64*)x));
      break;
  }
  return 0;
}
#endif

// Super cheesy error handling
#define _E(c, x, ...) if (!(c)) { \
  printf("!" #x "%s:%d\n" __VA_ARGS__ "\n", __FILE__, __LINE__); \
  goto error; \
}
#define E(x, ...) _E(x, x, ##__VA_ARGS__)
#define SQL_E(x, ...) _E(SQLITE_OK == (x), x, ##__VA_ARGS__)

// The following macro is used to adapt to the procedure signature.
// The entrypoint() procedure's signature varies based on the requirement for a database connection.
// For the convenience of users playing with CQL who might inadvertently remove the last
// or add the first sqlite statement – thus altering the connection requirement –
// we resolve the requirement for a connection in `./play.sh` and conditionally define how to call the procedure below.
#ifdef NO_DB_CONNECTION_REQUIRED_FOR_ENTRYPOINT
  // Omits the first parameter (the db connection) and avoids warnings about unused variables
  // Override void return tpe with SQLITE_OK to match the standard return signature
  #define __CALL_ENTRYPOINT__(db, ...) (0 ? (void)(db) : 0, entrypoint(__VA_ARGS__), SQLITE_OK)
#else
  // Omits no parameters
  #define __CALL_ENTRYPOINT__(db, ...) entrypoint(db, ##__VA_ARGS__)
#endif

// patternlint-disable-next-line prefer-sized-ints-in-msys
int main(int argc, char **argv) {
  sqlite3 *db = NULL;

  char *filepath = SQLITE_FILE_PATH_ABSOLUTE;

  printf("Database: %s\n", filepath);

  SQL_E(sqlite3_open(filepath, &db), "SQLite failed to open the database")
  #ifdef ENABLE_SQLITE_STATEMENT_TRACING
    SQL_E(sqlite3_trace_v2(db, SQLITE_TRACE_PROFILE, sqlite_trace_callback, NULL), "SQLite failed to register the trace callback");
  #endif

  SQL_E(__CALL_ENTRYPOINT__(db), "The call to the main entrypoint() procedure failed");

  SQL_E(sqlite3_close_v2(db));

  return 0;
error:
  if (db) {
    sqlite3_close_v2(db);
  }

  return 1;
}
