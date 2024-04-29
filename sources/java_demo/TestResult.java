/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import com.acme.cgsql.CQLResultSet;

public final class TestResult {
  static {
    System.loadLibrary("TestResult");
  }

  public static CQLResultSet JavaDemoFetchResults(long db) {
    // make the sample result set
    return new CQLResultSet(getTestResult(db));
  }

  public static native long getTestResult(long db);
}
