/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare proc printf no check;

-- Any kind of child result set will do the job for this test
-- note that with the json based code generation you can have
-- as many procs per file as you like.
create proc Child(lim int!)
begin
  cursor C like (irow int!, t text!);
  let i := 0;
  while i < lim
  begin
    i += 1;
    fetch C using
       i irow,
       printf("'%d'", i)  t;
    out union C;
  end;
end;

proc OutArgThing(inout t text, x int, inout y int, out z int)
begin
   z := x + y;
   y += 1;
   t := printf("prefix_%s", t);
end;

proc Fib(n int!, out result int!)
begin
   if n <= 2 then
     result := 1;
   else
     result := Fib(n-1) + Fib(n-2);
   end;
end;

[[private]]
proc Expect(b bool!, msg text!)
begin
   var y int;
   if b then
     y := 1;
   else
     printf("error: %s\n", msg);
   end;

  -- force a failure
  y := ifnull_crash(y);
end;

-- we have a series of check methods that accept every arg type

proc CheckBoolean(x bool!, y bool)
begin
  Expect(x is y, "boolean values should match");
end;

proc CheckInteger(x int!, y int)
begin
  Expect(x is y, "int values should match");
end;

proc CheckLong(x long!, y long)
begin
  Expect(x is y, "long values should match");
end;

proc CheckReal(x real!, y real)
begin
  Expect(x is y, "real values should match");
end;

proc CheckNullableBoolean(x bool, y bool)
begin
  Expect(x is y, "boolean values should match");
end;

proc CheckNullableInteger(x int, y int)
begin
  Expect(x is y, "int values should match");
end;

proc CheckNullableLong(x long, y long)
begin
  Expect(x is y, "long values should match");
end;

proc CheckNullableReal(x real, y real)
begin
  Expect(x is y, "real values should match");
end;

proc CheckText(x text, y text)
begin
  Expect(x is y, "text values should match");
end;

proc CheckBlob(x blob, y blob)
begin
  Expect(x is y, "blob values should match");
end;

proc CreateBlobFromText(in x text, out test_blob blob)
begin
  -- this is just a cheesy conversion to make
  -- a blob out of a string
  test_blob := (select CAST(x as blob));
end;

proc OutBoolean(in x bool!, out test bool!)
begin
  test := x;
end;

proc OutInteger(in x int!, out test int!)
begin
  test := x;
end;

proc OutLong(in x long!, out test long!)
begin
  test := x;
end;

proc OutReal(in x real!, out test real!)
begin
  test := x;
end;

proc OutNullableBoolean(in x bool, out test bool)
begin
  test := x;
end;

proc OutNullableInteger(in x int, out test int)
begin
  test := x;
end;

proc OutNullableLong(in x long, out test long)
begin
  test := x;
end;

proc OutNullableReal(in x real, out test real)
begin
  test := x;
end;

proc InOutBoolean(inout test bool!)
begin
  test |= true;
end;

proc InOutInteger(inout test int!)
begin
  test += 1;
end;

proc InOutLong(inout test long!)
begin
  test += 1;
end;

proc InOutReal(inout test real!)
begin
  test += 1;
end;

proc InOutNullableBoolean(inout test bool)
begin
  test |= true;
end;

proc InOutNullableInteger(inout test int)
begin
  test += 1;
end;

proc InOutNullableLong(inout test long)
begin
  test += 1;
end;

proc InOutNullableReal(inout test real)
begin
  test += 1;
end;

proc OutStatement(x int!)
begin
  cursor C like select x;
  fetch C using x x;
  out C;
end;

proc OutUnionStatement(x int!)
begin
  cursor C like select x;
  fetch C using x+1 x;
  out union C;
  fetch C using x+2 x;
  out union C;
end;

/* this is a demo procedure, it's rather silly... */
@attribute(cql:vault_sensitive)
@attribute(cql:custom_type_for_encoded_column)
create proc CSharpDemo()
begin
  /* add the table we will be using */
  create table my_data(
    name text,
    age int @sensitive,
    thing real,
    bytes blob,
    key1 text,
    key2 text @sensitive);

  /* insert some data */
  let i := 0;
  while i < 5
  begin
    /* avoiding @dummy_seed even though it's perfect here just so that
     * we don't take a dependency on the printf sqlite function.  If
     * your sqlite is very old you won't have that and we don't want the
     * JNI test to fail just because of a printf
     */
    insert into my_data using
      "name_"||i AS name,
      i AS age,
      i AS thing,
      cast("blob_"||i as blob) AS bytes,
      "code_1"||i AS key1,
      "code_2"||i AS key2;
    i += 1;
  end;

  set i := 0;
  /* the result will have a variety of data types to exercise the JNI helpers */
  cursor C for select * from my_data;
  loop fetch C
  begin
    cursor result like (like C, my_child_result object<Child set>);
    fetch result from values(from C, Child(i));
    out union result;
    i += 1;
  end;
end;
