/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "Sample_objc.h"

void dumpResults(CGSDemoResultSet *data);

void Expect(Boolean b, char *str) {
  if (!b) {
    NSLog(@"expecation failed %s\n", str);
  }
}

int main(int argc, char **argv) {
  // make an empty database (this can be replaced)
  sqlite3 *db;
  int rc = sqlite3_open(":memory:", &db);

  CGSOutArgThingReturnType *outargs = CGSCreateOutArgThingReturnType(@"_input", @5, @2);
  Expect([outargs.y intValue] == 3, "in out argument not incremented");
  Expect([outargs.z intValue] == 7, "sum not computed");
  Expect([outargs.t isEqualToString: @"prefix__input"], "string not assigned");

  // Test passing of all not nullable primitive types
  CGSCheckBoolean(true, @true);
  CGSCheckInteger(1234, @1234);
  CGSCheckLong(12345L, @12345L);
  CGSCheckReal(2.5, @2.5);

  // Same test using nullable versions (passed boxed)
  CGSCheckNullableBoolean(@true, @true);
  CGSCheckNullableInteger(@1234, @1234);
  CGSCheckNullableLong(@12345L, @12345L);
  CGSCheckNullableReal(@2.5, @2.5);

  // And again, this time using nil
  CGSCheckNullableBoolean(nil, nil);
  CGSCheckNullableInteger(nil, nil);
  CGSCheckNullableLong(nil, nil);
  CGSCheckNullableReal(nil, nil);

  // And again for text
  CGSCheckText(@"foo", @"foo");
  CGSCheckText(nil, nil);

  // Finally creatge some test blobs and test them
  NSData *b1 = CGSCreateBlobFromTextReturnType(db, @"a blob from text").test_blob;
  NSData *b2 = CGSCreateBlobFromTextReturnType(db, @"a blob from text").test_blob;
  CGSCheckBlob(b1, b2);
  CGSCheckBlob(nil, nil);

  Expect(true == CGSCreateOutBooleanReturnType(true).test, "mismatched out bool");
  Expect(123 == CGSCreateOutIntegerReturnType(123).test, "mismatched out int");
  Expect(456L == CGSCreateOutLongReturnType(456L).test, "mismatched out long");
  Expect(8.5 == CGSCreateOutRealReturnType(8.5).test, "mismatched out real");
  Expect(false == [CGSCreateOutNullableBooleanReturnType(false).test intValue], "mismatched nullable out bool");
  Expect(1234 == [CGSCreateOutNullableIntegerReturnType(@1234).test intValue], "mismatched nullable out int");
  Expect(4567L == [CGSCreateOutNullableLongReturnType(@4567L).test longLongValue], "mismatched nullable out long");
  Expect(8.25 == [CGSCreateOutNullableRealReturnType(@8.25).test doubleValue], "mismatched nullable out real");
  Expect(CGSCreateOutNullableBooleanReturnType(nil).test == nil, "mismatched nil out bool");
  Expect(CGSCreateOutNullableIntegerReturnType(nil).test == nil, "mismatched nil out int");
  Expect(CGSCreateOutNullableLongReturnType(nil).test == nil, "mismatched nil out long");
  Expect(CGSCreateOutNullableRealReturnType(nil).test == nil, "mismatched nil out real");

  Expect(true == CGSCreateInOutBooleanReturnType(false).test, "mismatched inout bool");
  Expect(124 == CGSCreateInOutIntegerReturnType(123).test, "mismatched inout int");
  Expect(457L == CGSCreateInOutLongReturnType(456L).test, "mismatched inout long");
  Expect(9.5 == CGSCreateInOutRealReturnType(8.5).test, "mismatched inout real");
  Expect(true == [CGSCreateInOutNullableBooleanReturnType(@false).test intValue], "mismatched nullable inout bool");
  Expect(1235 == [CGSCreateInOutNullableIntegerReturnType(@1234).test intValue], "mismatched nullable inout int");
  Expect(4568L == [CGSCreateInOutNullableLongReturnType(@4567L).test longLongValue], "mismatched nullable inout long");
  Expect(9.25 == [CGSCreateInOutNullableRealReturnType(@8.25).test doubleValue], "mismatched nullable inout real");
  Expect(CGSCreateInOutNullableBooleanReturnType(nil).test == nil, "mismatched nil inout bool");
  Expect(CGSCreateInOutNullableIntegerReturnType(nil).test == nil, "mismatched nil inout int");
  Expect(CGSCreateInOutNullableLongReturnType(nil).test == nil, "mismatched nil inout long");
  Expect(CGSCreateInOutNullableRealReturnType(nil).test == nil, "mismatched nil inout real");

  // try a recursive procedure
  CGSFibReturnType *fib = CGSCreateFibReturnType(10);
  Expect(55 == fib.result, "Fibnacci value did not compute correctly");

  CGSOutStatementReturnType *outS = CGSCreateOutStatementReturnType(314);
  CGSOutStatementResultSet *outSResult = outS.resultSet;

  Expect(1 == outSResult.count, "expected row count is 1");
  Expect(314 == outSResult.x, "value not echoed with OutStatement");

  CGSOutUnionStatementReturnType *outU = CGSCreateOutUnionStatementReturnType(300);
  CGSOutUnionStatementResultSet *outUResult = outU.resultSet;

  Expect(2 == outUResult.count, "expected row count is 2");
  Expect(301 == [outUResult x:0], "value+1 not echoed with OutUnionStatement");
  Expect(302 == [outUResult x:1], "value+2 not echoed with OutUnionStatement");

  // get call result code and rowset
  CGSDemoReturnType *results = CGSCreateDemoReturnType(db);

  Expect(results.resultCode == 0, "rc == SQLITE_OK");

  // use the results
  dumpResults(results.resultSet);

  // release the connection
  sqlite3_close(db);

  return 0;
}

void dumpResults(CGSDemoResultSet *data)
{
  int count = data.count;
  printf("dumping result set: count = %d\n", count);

  Expect(count == 5, "count == 5");

  for (int i = 0; i < count; i++) {
    NSData *bytes = [data bytes:i];
    NSString *s = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];

    NSLog(
      @"Row %d: name:%@ blob:%@ age:%@ thing:%@ key1:%@ key2:%@",
      i,
      [data name:i],
      s,
      [data age:i],
      [data thing:i],
      [data key1:i],
      [data key2:i]
    );

    CGSChildResultSet *child = [data my_child_result:i];
    for (int j = 0; j < child.count; j++) {
      int irow = [child irow:j];
      NSString *t = [child t:j];

      NSLog(@"    Child Row %d: irow:%d t:%@", j, irow, t);
      Expect(j + 1 == irow, "index should correspond to value");
    }
  }
}

