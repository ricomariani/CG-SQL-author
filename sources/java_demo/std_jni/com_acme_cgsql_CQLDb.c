/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// !!! THIS FILE IS NOT AUTO GENERATED, only the .h file is !!!

#include "cqlrt.h"
#include "com_acme_cgsql_CQLDb.h"

/*
 * Class:     com_acme_cgsql_CQLDb
 * Method:    openDb
 * Signature: ()J
 */
JNIEXPORT jlong JNICALL Java_com_acme_cgsql_CQLDb_openDb(JNIEnv *env, jclass thiz) {
  sqlite3 *db;
  if (sqlite3_open(":memory:", &db) == SQLITE_OK) {
    return (jlong)db;
  }
  return 0;
}

/*
 * Class:     com_acme_cgsql_CQLDb
 * Method:    closeDb
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_acme_cgsql_CQLDb_closeDb(JNIEnv *env, jclass thiz, jlong db) {
  sqlite3_close((sqlite3 *)db);
}
  