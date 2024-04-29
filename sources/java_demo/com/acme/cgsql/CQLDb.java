/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.acme.cgsql;

/**
 * CQLDb holds the abstract database pointer from cql and provides it to whomever needs it
 */
public class CQLDb {
  static private long cqlDb;

  static {
    System.loadLibrary("CQLDb");
  }

  public static void open() {
    cqlDb = openDb();
  }

  public static void close() {
    closeDb(cqlDb);   
  }

  public static long get() {
    return cqlDb;
  }

  public static native long openDb();
  public static native void closeDb(long db);
}
