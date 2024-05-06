/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import com.acme.cgsql.CQLDb;
import java.nio.charset.StandardCharsets;
import sample.*;

public class MyJava {
  public static void main(String[] args) throws Exception {
    // make an empty database (this can be replaced)
    CQLDb.open();

    // get result set handle
    long db = CQLDb.get();

    var outargs = sample.SampleJNI.OutArgThing("_input", 5, 2);
    Expect(outargs.get_y() == 3, "in out argument not incremented");
    Expect(outargs.get_z() == 7, "sum not computed");
    Expect(outargs.get_t().equals("prefix__input"), "string not assigned");

    // Test passing of all not nullable primitive types
    sample.SampleJNI.CheckBoolean(true, true);
    sample.SampleJNI.CheckInteger(1234, 1234);
    sample.SampleJNI.CheckLong(12345L, 12345L);
    sample.SampleJNI.CheckReal(2.5, 2.5);

    // Same test using nullable versions (passed boxed)
    sample.SampleJNI.CheckNullableBoolean(true, true);
    sample.SampleJNI.CheckNullableInteger(1234, 1234);
    sample.SampleJNI.CheckNullableLong(12345L, 12345L);
    sample.SampleJNI.CheckNullableReal(2.5, 2.5);

    // And again, this time using null
    sample.SampleJNI.CheckNullableBoolean(null, null);
    sample.SampleJNI.CheckNullableInteger(null, null);
    sample.SampleJNI.CheckNullableLong(null, null);
    sample.SampleJNI.CheckNullableReal(null, null);

    // And again for text
    sample.SampleJNI.CheckText("foo", "foo");
    sample.SampleJNI.CheckText(null, null);

    // Finally creatge some test blobs and test them
    var b1 = sample.SampleJNI.CreateBlobFromText(db, "a blob from text").get_test_blob();
    var b2 = sample.SampleJNI.CreateBlobFromText(db, "a blob from text").get_test_blob();
    sample.SampleJNI.CheckBlob(b1, b2);
    sample.SampleJNI.CheckBlob(null, null);

    Expect(true == sample.SampleJNI.OutBoolean(true).get_test(), "mismatched out bool");
    Expect(123 == sample.SampleJNI.OutInteger(123).get_test(), "mismatched out int");
    Expect(456L == sample.SampleJNI.OutLong(456L).get_test(), "mismatched out long");
    Expect(8.5 == sample.SampleJNI.OutReal(8.5).get_test(), "mismatched out real");
    Expect(false == sample.SampleJNI.OutNullableBoolean(false).get_test(), "mismatched nullable out bool");
    Expect(1234 == sample.SampleJNI.OutNullableInteger(1234).get_test(), "mismatched nullable out int");
    Expect(4567L == sample.SampleJNI.OutNullableLong(4567L).get_test(), "mismatched nullable out long");
    Expect(8.25 == sample.SampleJNI.OutNullableReal(8.25).get_test(), "mismatched nullable out real");
    Expect(sample.SampleJNI.OutNullableBoolean(null).get_test() == null, "mismatched null out bool");
    Expect(sample.SampleJNI.OutNullableInteger(null).get_test() == null, "mismatched null out int");
    Expect(sample.SampleJNI.OutNullableLong(null).get_test() == null, "mismatched null out long");
    Expect(sample.SampleJNI.OutNullableReal(null).get_test() == null, "mismatched null out real");

    Expect(true == sample.SampleJNI.InOutBoolean(false).get_test(), "mismatched inout bool");
    Expect(124 == sample.SampleJNI.InOutInteger(123).get_test(), "mismatched inout int");
    Expect(457L == sample.SampleJNI.InOutLong(456L).get_test(), "mismatched inout long");
    Expect(9.5 == sample.SampleJNI.InOutReal(8.5).get_test(), "mismatched inout real");
    Expect(true == sample.SampleJNI.InOutNullableBoolean(false).get_test(), "mismatched nullable inout bool");
    Expect(1235 == sample.SampleJNI.InOutNullableInteger(1234).get_test(), "mismatched nullable inout int");
    Expect(4568L == sample.SampleJNI.InOutNullableLong(4567L).get_test(), "mismatched nullable inout long");
    Expect(9.25 == sample.SampleJNI.InOutNullableReal(8.25).get_test(), "mismatched nullable inout real");
    Expect(sample.SampleJNI.InOutNullableBoolean(null).get_test() == null, "mismatched null inout bool");
    Expect(sample.SampleJNI.InOutNullableInteger(null).get_test() == null, "mismatched null inout int");
    Expect(sample.SampleJNI.InOutNullableLong(null).get_test() == null, "mismatched null inout long");
    Expect(sample.SampleJNI.InOutNullableReal(null).get_test() == null, "mismatched null inout real");

    // try a recursive procedure
    var fib = sample.SampleJNI.Fib(10);
    Expect(55 == fib.get_result(), "Fibnacci value did not compute correctly");

    var outS = sample.SampleJNI.OutStatement(314);
    var outSResult = outS.get_result_set();
    Expect(1 == outSResult.getCount(), "expected row count is 1");
    Expect(314 == outSResult.get_x(), "value not echoed with OutStatement");

    var outU = sample.SampleJNI.OutUnionStatement(300);
    var outUResult = outU.get_result_set();
    Expect(2 == outUResult.getCount(), "expected row count is 2");
    Expect(301 == outUResult.get_x(0), "value+1 not echoed with OutUnionStatement");
    Expect(302 == outUResult.get_x(1), "value+2 not echoed with OutUnionStatement");

    // get call result code and rowset
    var results = sample.SampleJNI.JavaDemo(db);

    Expect(results.get_result_code() == 0, "rc == SQLITE_OK");

    var data = results.get_result_set();

    // use the results
    dumpResults(data);

    // release the connection
    CQLDb.close();
  }

  public static void dumpResults(SampleJNI.JavaDemoViewModel data) throws Exception {
    int count = data.getCount();
    System.out.println(String.format("dumping result set: count = %d", count));

    Expect(count == 5, "count == 5");

    for (int i = 0; i < count; i++) {
      byte[] bytes = data.get_bytes(i);
      String s = new String(bytes, StandardCharsets.UTF_8);
      System.out.println(
          String.format(
              "Row %d: name:%s blob:%s age:%-7d(%s) thing:%f key1:%s key2:%s(%s)",
              i,
              data.get_name(i),
              s,
              data.get_age(i),
              data.get_age_IsEncoded() ? "encoded" : "clear",
              data.get_thing(i),
              data.get_key1(i),
              data.get_key2(i),
              data.get_key2_IsEncoded() ? "encoded" : "clear"
         )
     );

      // this could be done automatically in the helper, it just isn't yet
      // var child = data.get_my_child_result(i) should do the job
      var child = new SampleJNI.ChildViewModel(data.get_my_child_result(i));
      for (int j = 0; j < child.getCount(); j++) {
	var irow = child.get_irow(j);
	var t = child.get_t(j);

        System.out.println(String.format("    Child Row %d: irow:%d t:%s", j, irow, t));
	Expect(j + 1 == irow, "index should correspond to value");

	var formatted = String.format("'%s'", irow);
	Expect(formatted.equals(t), "invalid format transform through the CQL");
      }
    }
  }

  public static void Expect(boolean b, String str) throws Exception {
     if (!b) throw new Exception(str);
  }
}
