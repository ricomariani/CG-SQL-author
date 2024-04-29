/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "TestResult.h"
#include "cqlrt.h"
#include "Sample.h"

/*
 * Class:     TestResult
 * Method:    getTestResult
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_TestResult_getTestResult(JNIEnv *env, jclass thiz, jlong db) {
  JavaDemo_result_set_ref result_set;
  cql_code rc = JavaDemo_fetch_results((sqlite3 *)db, &result_set);
  if (rc) return 0;
  return (jlong)result_set;
}
