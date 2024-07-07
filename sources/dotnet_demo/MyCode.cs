/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

using CGSQL;

public class MyCode {
  public static void Main(String[] args) {
    // make an empty database (this can be replaced)
    CQLDb.open();

    // get result set handle
    long db = CQLDb.get();

    var outargs = SampleInterop.OutArgThing("_input", 5, 2);
    Expect(outargs.y == 3, "in out argument not incremented");
    Expect(outargs.z == 7, "sum not computed");
    Expect((outargs.t ?? "null").Equals("prefix__input"), "string not assigned");

    // Test passing of all not nullable primitive types
    SampleInterop.CheckBoolean(true, true);
    SampleInterop.CheckInteger(1234, 1234);
    SampleInterop.CheckLong(12345L, 12345L);
    SampleInterop.CheckReal(2.5, 2.5);

    // Same test using nullable versions (passed boxed)
    SampleInterop.CheckNullableBoolean(true, true);
    SampleInterop.CheckNullableInteger(1234, 1234);
    SampleInterop.CheckNullableLong(12345L, 12345L);
    SampleInterop.CheckNullableReal(2.5, 2.5);

    // And again, this time using null
    SampleInterop.CheckNullableBoolean(null, null);
    SampleInterop.CheckNullableInteger(null, null);
    SampleInterop.CheckNullableLong(null, null);
    SampleInterop.CheckNullableReal(null, null);

    // And again for text
    SampleInterop.CheckText("foo", "foo");
    SampleInterop.CheckText(null, null);

    // Finally creatge some test blobs and test them
    var b1 = SampleInterop.CreateBlobFromText(db, "a blob from text").test_blob;
    var b2 = SampleInterop.CreateBlobFromText(db, "a blob from text").test_blob;
    SampleInterop.CheckBlob(b1, b2);
    SampleInterop.CheckBlob(null, null);

    Expect(true == SampleInterop.OutBoolean(true).test, "mismatched out bool");
    Expect(123 == SampleInterop.OutInteger(123).test, "mismatched out int");
    Expect(456L == SampleInterop.OutLong(456L).test, "mismatched out long");
    Expect(8.5 == SampleInterop.OutReal(8.5).test, "mismatched out real");
    Expect(false == SampleInterop.OutNullableBoolean(false).test, "mismatched nullable out bool");
    Expect(1234 == SampleInterop.OutNullableInteger(1234).test, "mismatched nullable out int");
    Expect(4567L == SampleInterop.OutNullableLong(4567L).test, "mismatched nullable out long");
    Expect(8.25 == SampleInterop.OutNullableReal(8.25).test, "mismatched nullable out real");
    Expect(SampleInterop.OutNullableBoolean(null).test == null, "mismatched null out bool");
    Expect(SampleInterop.OutNullableInteger(null).test == null, "mismatched null out int");
    Expect(SampleInterop.OutNullableLong(null).test == null, "mismatched null out long");
    Expect(SampleInterop.OutNullableReal(null).test == null, "mismatched null out real");

    Expect(true == SampleInterop.InOutBoolean(false).test, "mismatched inout bool");
    Expect(124 == SampleInterop.InOutInteger(123).test, "mismatched inout int");
    Expect(457L == SampleInterop.InOutLong(456L).test, "mismatched inout long");
    Expect(9.5 == SampleInterop.InOutReal(8.5).test, "mismatched inout real");
    Expect(true == SampleInterop.InOutNullableBoolean(false).test, "mismatched nullable inout bool");
    Expect(1235 == SampleInterop.InOutNullableInteger(1234).test, "mismatched nullable inout int");
    Expect(4568L == SampleInterop.InOutNullableLong(4567L).test, "mismatched nullable inout long");
    Expect(9.25 == SampleInterop.InOutNullableReal(8.25).test, "mismatched nullable inout real");
    Expect(SampleInterop.InOutNullableBoolean(null).test == null, "mismatched null inout bool");
    Expect(SampleInterop.InOutNullableInteger(null).test == null, "mismatched null inout int");
    Expect(SampleInterop.InOutNullableLong(null).test == null, "mismatched null inout long");
    Expect(SampleInterop.InOutNullableReal(null).test == null, "mismatched null inout real");

    // try a recursive procedure
    var fib = SampleInterop.Fib(10);
    Expect(55 == fib.result, "Fibnacci value did not compute correctly");

    var outS = SampleInterop.OutStatement(314);
    var outSResult = outS.result_set;
    Expect(1 == outSResult.Count, "expected row count is 1");
    Expect(314 == outSResult.get_x(), "value not echoed with OutStatement");

    var outU = SampleInterop.OutUnionStatement(300);
    var outUResult = outU.result_set;
    Expect(2 == outUResult.Count, "expected row count is 2");
    Expect(301 == outUResult.get_x(0), "value+1 not echoed with OutUnionStatement");
    Expect(302 == outUResult.get_x(1), "value+2 not echoed with OutUnionStatement");

    // get call result code and rowset
    var results = SampleInterop.CSharpDemo(db);

    Expect(results.result_code == 0, "rc == SQLITE_OK");

    var data = results.result_set;

    // use the results
    dumpResults(data);

    // release the connection
    CQLDb.close();
  }

  public static void dumpResults(SampleInterop.CSharpDemoViewModel data) {
    int count = data.Count;
    Console.WriteLine("dumping result set: count = {0}", count);

    Expect(count == 5, "count == 5");

    for (int i = 0; i < count; i++) {
      byte[] bytes = data.get_bytes(i);
      String? s = System.Text.Encoding.UTF8.GetString(bytes);
      Console.WriteLine(
         "Row {0}: name:{1} blob:{2} age:{3}({4}) thing:{5:F6} key1:{6} key2:{7}({8})",
         i, // 0
         data.get_name(i), // 1
         s, // 2
         data.get_age(i), // 3
         data.get_age_IsEncoded() ? "encoded" : "clear", // 4
         data.get_thing(i), // 5
         data.get_key1(i), // 6
         data.get_key2(i), // 7
         data.get_key2_IsEncoded() ? "encoded" : "clear" // 8
     );

      // this could be done automatically in the helper, it just isn't yet
      // var child = data.get_my_child_result(i) should do the job
      var child = new SampleInterop.ChildViewModel(data.get_my_child_result(i));
      for (int j = 0; j < child.Count; j++) {
	var irow = child.get_irow(j);
	var t = child.get_t(j);

        Console.WriteLine("    Child Row {0}: irow:{1} t:{2}", j, irow, t);
	Expect(j + 1 == irow, "index should correspond to value");

	var formatted = String.Format("'{0}'", irow);
	Expect(formatted.Equals(t), "invalid format transform through the CQL");
      }
    }
  }

  public static void Expect(bool b, String str) {
     if (!b) throw new Exception(str);
  }
}
