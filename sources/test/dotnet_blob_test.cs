/*
 * Copyright (c) Rico Mariani
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

using System;
using System.Linq;
using System.Reflection;
using CGSQL;

class BlobChecks {
  static void Check(byte[]? expected, byte[]? actual, string label) {
    if (expected == null ? actual != null :
        actual == null || !expected.SequenceEqual(actual)) {
      throw new Exception(label + ": blob bytes or NULL presence changed");
    }
  }

  static void Release(CQLViewModel model) {
    // The sample ViewModels do not expose close; release their real result sets.
    var field = typeof(CQLViewModel).GetField("mResultSet",
        BindingFlags.NonPublic | BindingFlags.Instance)!;
    ((CQLResultSet)field.GetValue(model)!).close();
  }

  static void Echo(byte[]? value) {
    var result = BlobInterop.echo_nullable(value);
    try {
      Check(value, result.echoed, "nullable echo");
      Check(value, result.echoed, "repeated read");
    } finally {
      Release(result);
    }
  }

  static void RejectNull(Action call) {
    try {
      call();
    } catch (ArgumentNullException) {
      return;
    }
    throw new Exception("nonnull blob accepted null");
  }

  static void Main() {
    byte[] binary = {0, 255, 1, 128, 0, 42};
    byte[] large = Enumerable.Range(0, 4097).Select(i => (byte)(i % 256)).ToArray();
    byte[]?[] values = {binary, new byte[] {1}, Array.Empty<byte>(),
                       new byte[] {120, 120}, large, null};
    foreach (byte[]? value in values) {
      Echo(value);
      if (value != null) {
        BlobInterop.consume_nonnull(value);
        var result = BlobInterop.echo_nonnull(value);
        try {
          Check(value, result.echoed, "nonnull echo");
        } finally {
          Release(result);
        }
        var nonnullOuter = BlobInterop.projected_nonnull(value);
        try {
          Check(value, nonnullOuter.result_set.get_value(), "nonnull projected blob");
        } finally {
          Release(nonnullOuter);
        }
      }

      var outer = BlobInterop.projected(value);
      var projection = outer.result_set;
      try {
        if (projection.Count != 1) throw new Exception("projection count");
        Check(value, projection.get_value(), "projected blob");
      } finally {
        // result_set borrows its handle from the owning return row.
        Release(outer);
      }

      foreach (byte[]? replacement in values) {
        var result = BlobInterop.replace_nullable(value, replacement);
        try {
          Check(replacement, result.payload, "nullable inout");
        } finally {
          Release(result);
        }
        if (value != null && replacement != null) {
          var nonnull = BlobInterop.replace_nonnull(value, replacement);
          try {
            Check(replacement, nonnull.payload, "nonnull inout");
          } finally {
            Release(nonnull);
          }
        }
        var comparison = BlobInterop.same_bytes(73, value, replacement);
        try {
          bool expected = value == null ? replacement == null :
              replacement != null && value.SequenceEqual(replacement);
          if (comparison.same != expected) {
            throw new Exception("native blob comparison lost bytes or NULL presence");
          }
        } finally {
          Release(comparison);
        }
      }
    }

    RejectNull(() => BlobInterop.echo_nonnull(null!));
    RejectNull(() => BlobInterop.consume_nonnull(null!));
    RejectNull(() => BlobInterop.replace_nonnull(null!, binary));
    RejectNull(() => BlobInterop.replace_nonnull(binary, null!));
    Check(new byte[] {0, 255, 1, 128, 0, 42}, binary, "input array unchanged");
    Console.WriteLine(".NET/native blob bytes, lengths, NULL, empty, and inout round trips passed.");
  }
}
