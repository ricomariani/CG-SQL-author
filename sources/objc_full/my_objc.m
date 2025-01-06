/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "Sample_objc.h"

void dumpResults(CGSDemoRS *rs);

void Expect(Boolean b, char *str) {
  if (!b) {
    NSLog(@"expecation failed %s\n", str);
  }
}

void VerifyMultiOut(sqlite3 *db) {
  // a procedure with multiple out-ish arguments

  // RT is the "return type"  and RS is the "result set"
  // These were abbreviated to keep the names from getting ridiculously long

  CGSOutArgThingRT *rt = CGSCreateOutArgThingRT(@"_input", @5, @2);
  Expect([rt.y intValue] == 3, "in out argument not incremented");
  Expect([rt.z intValue] == 7, "sum not computed");
  Expect([rt.t isEqualToString: @"prefix__input"], "string not assigned");
}

void VerifyArgConversions(sqlite3 *db) {
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
  NSData *b1 = CGSCreateBlobFromTextRT(db, @"a blob from text").test_blob;
  NSData *b2 = CGSCreateBlobFromTextRT(db, @"a blob from text").test_blob;
  CGSCheckBlob(b1, b2);
  CGSCheckBlob(nil, nil);
}

void VerifyAllNumericCombos(sqlite3 *db) {
    // Out notnull numeric types
  Expect(true == CGSCreateOutBooleanRT(true).test, "mismatched out bool");
  Expect(123 == CGSCreateOutIntegerRT(123).test, "mismatched out int");
  Expect(456L == CGSCreateOutLongRT(456L).test, "mismatched out long");
  Expect(8.5 == CGSCreateOutRealRT(8.5).test, "mismatched out real");

  // Out nullable numeric types
  Expect(false == [CGSCreateOutNullableBooleanRT(false).test intValue], "mismatched nullable out bool");
  Expect(1234 == [CGSCreateOutNullableIntegerRT(@1234).test intValue], "mismatched nullable out int");
  Expect(4567L == [CGSCreateOutNullableLongRT(@4567L).test longLongValue], "mismatched nullable out long");
  Expect(8.25 == [CGSCreateOutNullableRealRT(@8.25).test doubleValue], "mismatched nullable out real");

  // Out nullable numeric types with nil
  Expect(CGSCreateOutNullableBooleanRT(nil).test == nil, "mismatched nil out bool");
  Expect(CGSCreateOutNullableIntegerRT(nil).test == nil, "mismatched nil out int");
  Expect(CGSCreateOutNullableLongRT(nil).test == nil, "mismatched nil out long");
  Expect(CGSCreateOutNullableRealRT(nil).test == nil, "mismatched nil out real");

  // Inout notnull numeric types
  Expect(true == CGSCreateInOutBooleanRT(false).test, "mismatched inout bool");
  Expect(124 == CGSCreateInOutIntegerRT(123).test, "mismatched inout int");
  Expect(457L == CGSCreateInOutLongRT(456L).test, "mismatched inout long");
  Expect(9.5 == CGSCreateInOutRealRT(8.5).test, "mismatched inout real");

  // Inout nullable numeric types
  Expect(true == [CGSCreateInOutNullableBooleanRT(@false).test intValue], "mismatched nullable inout bool");
  Expect(1235 == [CGSCreateInOutNullableIntegerRT(@1234).test intValue], "mismatched nullable inout int");
  Expect(4568L == [CGSCreateInOutNullableLongRT(@4567L).test longLongValue], "mismatched nullable inout long");
  Expect(9.25 == [CGSCreateInOutNullableRealRT(@8.25).test doubleValue], "mismatched nullable inout real");

  // Inout nullable numeric types with nil
  Expect(CGSCreateInOutNullableBooleanRT(nil).test == nil, "mismatched nil inout bool");
  Expect(CGSCreateInOutNullableIntegerRT(nil).test == nil, "mismatched nil inout int");
  Expect(CGSCreateInOutNullableLongRT(nil).test == nil, "mismatched nil inout long");
  Expect(CGSCreateInOutNullableRealRT(nil).test == nil, "mismatched nil inout real");
}

void VerifyOutandOutUnionResultSets() {
  CGSOutStatementRT *rtOut = CGSCreateOutStatementRT(314);
  CGSOutStatementRS *rsOut = rtOut.resultSet;

  Expect(1 == rsOut.count, "expected row count is 1");
  Expect(314 == rsOut.x, "value not echoed with OutStatement");

  CGSOutUnionStatementRT *rtOutU = CGSCreateOutUnionStatementRT(300);
  CGSOutUnionStatementRS *rsOutU = rtOutU.resultSet;

  Expect(2 == rsOutU.count, "expected row count is 2");
  Expect(301 == [rsOutU x:0], "value+1 not echoed with OutUnionStatement");
  Expect(302 == [rsOutU x:1], "value+2 not echoed with OutUnionStatement");
}


int main(int argc, char **argv) {
  // make an empty database (this can be replaced)
  sqlite3 *db;
  int rc = sqlite3_open(":memory:", &db);

  VerifyMultiOut(db);
  VerifyArgConversions(db);
  VerifyAllNumericCombos(db);

  // try a recursive procedure
  CGSFibRT *rtFib = CGSCreateFibRT(10);
  Expect(55 == rtFib.result, "Fibnacci value did not compute correctly");

  VerifyOutandOutUnionResultSets();

  // get call result code and rowset
  CGSDemoRT *rtDemo = CGSCreateDemoRT(db);

  Expect(rtDemo.resultCode == 0, "rc == SQLITE_OK");

  // use the results
  dumpResults(rtDemo.resultSet);

  // release the connection
  sqlite3_close(db);

  return 0;
}

void dumpResults(CGSDemoRS *rs)
{
  int count = rs.count;
  printf("dumping result set: count = %d\n", count);

  Expect(count == 5, "count == 5");

  for (int i = 0; i < count; i++) {
    NSData *bytes = [rs bytes:i];
    NSString *s = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];

    NSLog(
      @"Row %d: name:%@ blob:%@ age:%@ thing:%@ key1:%@ key2:%@",
      i,
      [rs name:i],
      s,
      [rs age:i],
      [rs thing:i],
      [rs key1:i],
      [rs key2:i]
    );

    CGSChildRS *child = [rs my_child_result:i];
    for (int j = 0; j < child.count; j++) {
      int irow = [child irow:j];
      NSString *t = [child t:j];

      NSLog(@"    Child Row %d: irow:%d t:%@", j, irow, t);
      Expect(j + 1 == irow, "index should correspond to value");
    }
  }
}

