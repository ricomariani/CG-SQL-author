/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CGSQL {

/**
 * CQLDb holds the abstract database pointer from cql and provides it to whomever needs it
 */
public class CQLDb {
  static private long cqlDb;

  public static void open() {
    cqlDb = openDb();
  }

  public static void close() {
    closeDb(cqlDb);
  }

  public static long get() {
    return cqlDb;
  }

  [DllImport(@"cql_interop.dll")]
  public static extern long openDb();

  [DllImport(@"cql_interop.dll")]
  public static extern void closeDb(long db);
}

/*
 * CQLEncodedString hides the string fields in the result set that were marked as vaulted.
 *
 * It has no getter so you can't directly extract the string at all.
 *
 * The way you use this class is you add helper methods to it that directly put the string
 * to where it needs to go, such as logging, or into a text view, or whatever you might need.
 *
 * The idea is that the pieces of code that flow the string to its final destination cannot see
 * its value so they can't do "the wrong thing" with it.  When you are finally ready to do
 * whatever actually needs to be done, that final code calls a helper to do the job.
 *
 * By using this pattern you can easily spot the pieces of code that actually extract the
 * string and restrict them in whatever way you want with simple tools.
 */
public class CQLEncodedString {
  public String mValue;

  public CQLEncodedString(String value) {
    mValue = value;
  }

  public override String ToString() {
    return "[secret]";
  }

  // you add your methods for dealing with encoded strings here
}

/**
 * CQLResultSet is a simple utility class that holds a native cql_result_set_ref
 *
 * <p><b>YOU CANNOT USE THIS CLASS DIRECTLY</b>
 *
 * <p>This class is only meant to be used directly by generated code, so any other code that depends
 * on this class directly is considered invalid and could break anytime without further notice.
 */
public sealed class CQLResultSet {
  private long result_set_ref;

  public CQLResultSet(long result_set_ref_) {
    result_set_ref = result_set_ref_;
  }

  public bool? getNullableBoolean(int row, int column) {
    if (isNull(row, column)) {
      return null;
    }
    return getBoolean(row, column);
  }

  public int? getNullableInteger(int row, int column) {
    if (isNull(row, column)) {
      return null;
    }
    return getInteger(row, column);
  }

  public long? getNullableLong(int row, int column) {
    if (isNull(row, column)) {
      return null;
    }
    return getLong(row, column);
  }

  public double? getNullableDouble(int row, int column) {
    if (isNull(row, column)) {
      return null;
    }
    return getDouble(row, column);
  }

  public void close() {
    if (result_set_ref != 0) {
      close(result_set_ref);
      result_set_ref = 0;
    }
  }

  public bool getBoolean(int row, int column) {
    return getBoolean(result_set_ref, row, column);
  }

  public int getInteger(int row, int column) {
    return getInteger(result_set_ref, row, column);
  }

  public long getLong(int row, int column) {
    return getLong(result_set_ref, row, column);
  }

  public String getString(int row, int column) {
    return getString(result_set_ref, row, column);
  }

  public CQLEncodedString getEncodedString(int row, int column) {
    return new CQLEncodedString(getString(row, column));
  }

  public double getDouble(int row, int column) {
    return getDouble(result_set_ref, row, column);
  }

  public byte[] getBlob(int row, int column) {
    int size;
    IntPtr ptr = CQLResultSet.getBlob(result_set_ref, row, column, out size);
    byte[] blob = new byte[size];

    // Copy the unmanaged blob to the managed byte array
    Marshal.Copy(ptr, blob, 0, size);
    CQLResultSet.freeBlob(ptr);
    return blob;
  }

  public CQLResultSet getChildResultSet(int row, int column) {
    return new CQLResultSet(copyChildResultSet(result_set_ref, row, column));
  }

  public bool isNull(int row, int column) {
    return isNull(result_set_ref, row, column);
  }

  public int getCount() {
    return getCount(result_set_ref);
  }

  public long rowHashCode(int row) {
    return rowHashCode(result_set_ref, row);
  }

  public bool rowsEqual(int row1, CQLResultSet rs2, int row2) {
    return rowsEqual(result_set_ref, row1, rs2.result_set_ref, row2);
  }

  public bool rowsSame(int row1, CQLResultSet rs2, int row2) {
    return rowsSame(result_set_ref, row1, rs2.result_set_ref, row2);
  }

  public CQLResultSet copy(int row, int count) {
    return new CQLResultSet(copy(result_set_ref, row, count));
  }

  public bool getIsEncoded(int column) {
    return getIsEncoded(result_set_ref, column);
  }

  [DllImport(@"cql_interop.dll")]
  public static extern void close(long result_set_ref);

  [DllImport(@"cql_interop.dll")]
  public static extern bool getBoolean(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern int getInteger(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern long getLong(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern String getString(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern double getDouble(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern IntPtr getBlob(long result_set_ref, int row, int column, out int size);

  [DllImport(@"cql_interop.dll")]
  public static extern void freeBlob(IntPtr blob);

  [DllImport(@"cql_interop.dll")]
  public static extern long copyChildResultSet(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern bool isNull(long result_set_ref, int row, int column);

  [DllImport(@"cql_interop.dll")]
  public static extern int getCount(long result_set_ref);

  [DllImport(@"cql_interop.dll")]
  public static extern long rowHashCode(long result_set_ref, int row);

  [DllImport(@"cql_interop.dll")]
  public static extern bool rowsEqual(long result_set_ref, int row1, long rs2, int row2);

  [DllImport(@"cql_interop.dll")]
  public static extern bool rowsSame(long result_set_ref, int row1, long rs2, int row2);

  [DllImport(@"cql_interop.dll")]
  public static extern long copy(long result_set_ref, int row, int count);

  [DllImport(@"cql_interop.dll")]
  public static extern bool getIsEncoded(long result_set_ref, int column);
}

/**
 * Super class extended by all CQL based view models.
 *
 * <p><b>YOU CANNOT USE THIS CLASS DIRECTLY</b>
 *
 * <p>This class is only meant to be used directly by generated code, so any other code that depends
 * on this class directly is considered invalid and could break anytime without further notice.
 */
public abstract class CQLViewModel {
  protected CQLResultSet mResultSet;

  public CQLViewModel(CQLResultSet resultSet) {
    mResultSet = resultSet;
  }

  public long rowHashCode(int row) {
    return mResultSet.rowHashCode(row);
  }

  public bool rowsEqual(int row1, CQLViewModel rs2, int row2) {
    return mResultSet.rowsEqual(row1, rs2.mResultSet, row2);
  }

  public bool rowsSame(int row1, CQLViewModel rs2, int row2) {
    if (!hasIdentityColumns()) {
      return false;
    }
    return mResultSet.rowsSame(row1, rs2.mResultSet, row2);
  }

  protected abstract bool hasIdentityColumns();
}

}
