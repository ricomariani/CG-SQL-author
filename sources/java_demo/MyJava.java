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

    var outargs = sample.SampleJNI.OutArgThing(5, 2);
    Expect(outargs.get_y() == 3, "in out argument not incremented");
    Expect(outargs.get_z() == 7, "sum not computed");
    Expect(outargs.get_t().equals("xxx"), "string not assigned");

    // try a no-result procedure
    sample.SampleJNI.NoResult(1234);

    // try a recursive procedure
    var fib = sample.SampleJNI.Fib(10);
    System.out.println("Fibonacci Result is: " + fib.get_result());
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

    System.out.println("Result code is: " +  results.get_result_code());
    Expect(results.get_result_code() == 0, "rc == SQLITE_OK");

    var data = results.get_result_set();

    // use the results
    dumpResults(data);

    // release the connection
    CQLDb.close();
  }

  public static void dumpResults(SampleJNI.JavaDemoViewModel data) throws Exception {
    System.out.println("Dumping Results");
    int count = data.getCount();
    System.out.println(String.format("count = %d", count));

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
	var x = child.get_x(j);
	var y = child.get_y(j);

        System.out.println(String.format("--> Child Row %d: x:%d y:%s", j, x, y));
	Expect(j + 1 == x, "index should correspond to value");

	var x_formatted = String.format("<< %s >>", x);
	Expect(x_formatted.equals(y), "invalid format transform through the CQL");
      }
    }
  }

  public static void Expect(boolean b, String str) throws Exception {
     if (!b) throw new Exception(str);
  }
}
