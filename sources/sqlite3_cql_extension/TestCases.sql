declare proc printf no check;

@echo C,'
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
';

-- auto  generateed by the python, simply `grep "DECLARE SELECT" out/SampleInterop.c | sed s/...//`
-- the prototype is emitted in a comment so you just strip it out
-- see out/SampleInterop.c if this is unclear at all
DECLARE SELECT FUNCTION comprehensive_test1(in__bool__not_null bool!, in__bool__nullable bool, in__real__not_null real!, in__real__nullable real, in__integer__not_null integer!, in__integer__nullable integer, in__long__not_null long!, in__long__nullable long, in__text__not_null text!, in__text__nullable text, in__blob__not_null blob!, in__blob__nullable blob) (result text!);
DECLARE SELECT FUNCTION comprehensive_test2(inout__bool__not_null bool!, inout__bool__nullable bool, inout__real__not_null real!, inout__real__nullable real, inout__integer__not_null integer!, inout__integer__nullable integer, inout__long__not_null long!, inout__long__nullable long, inout__text__not_null text!, inout__text__nullable text, inout__blob__not_null blob!, inout__blob__nullable blob) (result text!);
DECLARE SELECT FUNCTION comprehensive_test3() (result text!);
DECLARE SELECT FUNCTION hello_world() (result text!);
DECLARE SELECT FUNCTION in__blob__not_null(in__x blob!) (in__x blob!);
DECLARE SELECT FUNCTION in__blob__nullable(in__x blob) (in__x blob);
DECLARE SELECT FUNCTION in__bool__not_null(in__x bool!) (in__x bool!);
DECLARE SELECT FUNCTION in__bool__nullable(in__x bool) (in__x bool);
DECLARE SELECT FUNCTION in__integer__not_null(in__x integer!) (in__x integer!);
DECLARE SELECT FUNCTION in__integer__nullable(in__x integer) (in__x integer);
DECLARE SELECT FUNCTION in__long__not_null(in__x long!) (in__x long!);
DECLARE SELECT FUNCTION in__long__nullable(in__x long) (in__x long);
DECLARE SELECT FUNCTION in__real__not_null(in__x real!) (in__x real!);
DECLARE SELECT FUNCTION in__real__nullable(in__x real) (in__x real);
DECLARE SELECT FUNCTION in__text__not_null(in__x text!) (in__x text!);
DECLARE SELECT FUNCTION in__text__nullable(in__x text) (in__x text);
DECLARE SELECT FUNCTION inout__blob__not_null(inout__x blob!) blob!;
DECLARE SELECT FUNCTION inout__blob__nullable(inout__x blob) blob;
DECLARE SELECT FUNCTION inout__bool__not_null(inout__x bool!) bool!;
DECLARE SELECT FUNCTION inout__bool__nullable(inout__x bool) bool;
DECLARE SELECT FUNCTION inout__integer__not_null(inout__x integer!) integer!;
DECLARE SELECT FUNCTION inout__integer__nullable(inout__x integer) integer;
DECLARE SELECT FUNCTION inout__long__not_null(inout__x long!) long!;
DECLARE SELECT FUNCTION inout__long__nullable(inout__x long) long;
DECLARE SELECT FUNCTION inout__real__not_null(inout__x real!) real!;
DECLARE SELECT FUNCTION inout__real__nullable(inout__x real) real;
DECLARE SELECT FUNCTION inout__text__not_null(inout__x text!) text!;
DECLARE SELECT FUNCTION inout__text__nullable(inout__x text) text;
DECLARE SELECT FUNCTION many_rows(x integer) (x integer!, y integer!, z text!);
DECLARE SELECT FUNCTION out__blob__not_null() blob!;
DECLARE SELECT FUNCTION out__blob__nullable() blob;
DECLARE SELECT FUNCTION out__bool__not_null() bool!;
DECLARE SELECT FUNCTION out__bool__nullable() bool;
DECLARE SELECT FUNCTION out__integer__not_null() integer!;
DECLARE SELECT FUNCTION out__integer__nullable() integer;
DECLARE SELECT FUNCTION out__long__not_null() long!;
DECLARE SELECT FUNCTION out__long__nullable() long;
DECLARE SELECT FUNCTION out__real__not_null() real!;
DECLARE SELECT FUNCTION out__real__nullable() real;
DECLARE SELECT FUNCTION out__text__not_null() text!;
DECLARE SELECT FUNCTION out__text__nullable() text;
DECLARE SELECT FUNCTION result_from_first_inout_or_out_argument__inout(in__text__not_null text!, inout__text__not_null text!, inout__text__not_null_bis text!) text!;
DECLARE SELECT FUNCTION result_from_first_inout_or_out_argument__out(in__text__not_null text!, inout__text__not_null text!, inout__text__not_null_bis text!) text!;
DECLARE SELECT FUNCTION result_from_inout(inout__x text!) text!;
DECLARE SELECT FUNCTION result_from_out() text!;
DECLARE SELECT FUNCTION result_from_result_set__no_args() (result text!);
DECLARE SELECT FUNCTION result_from_result_set__with_in_out_inout(in__text__not_null text!, inout__text__not_null text!) (result text!);
DECLARE SELECT FUNCTION result_from_void__null__no_args() /*void*/ int;
DECLARE SELECT FUNCTION result_from_void__null__with_in(in__x text!) /*void*/ int;
DECLARE SELECT FUNCTION three_int_test(x integer, y integer, z integer) (x integer, y integer, z integer);

@macro(stmt_list) sel!(f! expr, v! expr)
begin
  let @tmp(r) := (select in__x from @id(f!)(v!));
  if @tmp(r) is not v! then
     printf("%s: error %s is not %s\n", @text(f!), @text(v!), @tmp(r):fmt);
     throw;
  else
     printf("%s: passed with %s\n", @text(f!), @text(v!));
  end if;
end;

@macro(stmt_list) EXPECT_EQ!(x! expr, y! expr)
begin
  let @tmp(x) := x!;
  let @tmp(y) := y!;
  if @tmp(x) is not @tmp(y) then
     printf("line %d error %s is not %s\n", @MACRO_LINE, @tmp(x):fmt, @tmp(y):fmt);
     printf("expressions:%s is not %s\n", @text(x!), @text(y!));
     throw;
  end if;
end;

proc test_cases()
begin
  printf("Starting demo.\n");
  let hello := (select result from hello_world());
  printf("%s\n", hello);

  printf("three int test");

  cursor C for select * from three_int_test(1, 2, 3);
  fetch C;
  printf("%d %d %d\n", C.x, C.y, C.z);
  if C.x != 1 or C.y != 2 or C.z != 3 throw;

  cursor D for select * from three_int_test(4, 5, 6);
  fetch D;
  printf("%d %d %d\n", D.x, D.y, D.z);
  if D.x != 4 or D.y != 5 or D.z != 6 throw;

  sel!(in__bool__not_null, true);
  sel!(in__bool__not_null, false);
  sel!(in__bool__nullable, true);
  sel!(in__bool__nullable, false);
  sel!(in__bool__nullable, null);
  sel!(in__integer__not_null, 1);
  sel!(in__integer__not_null, 100);
  sel!(in__integer__nullable, null);
  sel!(in__integer__nullable, 2);
  sel!(in__integer__nullable, 200);
  sel!(in__real__not_null, 1.5);
  sel!(in__real__not_null, 100.5);
  sel!(in__real__nullable, null);
  sel!(in__real__nullable, 2.5);
  sel!(in__real__nullable, 200.5);
  sel!(in__text__not_null, "foo_text");
  sel!(in__text__nullable, null);
  sel!(in__text__nullable, "bar_text");

  let a_blob := (select "blob stuff" ~blob~);

  sel!(in__blob__not_null, a_blob);
  sel!(in__blob__nullable, null);
  sel!(in__blob__nullable, a_blob);

  let wanted := 10;
  declare LL cursor for select * from many_rows(wanted);

  let got := 0;
  loop fetch LL
  begin
    printf("%d %d %s\n", LL.x, LL.y, LL.z);
    if LL.x != got throw;
    if LL.y != got*100 throw;
    if LL.z != printf("text_%d", got) throw;
    got += 1;
  end;

  var i int;
  var l long;
  var r real;
  var t text;
  var bl blob;
  var b bool;

  t := (select result from result_from_result_set__with_in_out_inout("foo", "bar"));
  EXPECT_EQ!(t, "result_set");

  t := (select result_from_first_inout_or_out_argument__inout("foo", "bar", "baz"));
  EXPECT_EQ!(t, "inout_argument");

  t := (select result_from_first_inout_or_out_argument__out("foo", "bar", "baz"));
  EXPECT_EQ!(t, "out_argument");

  t := (select result_from_inout("foo"));
  EXPECT_EQ!(t, "inout_argument");

  t := (select result_from_out());
  EXPECT_EQ!(t, "out_argument");

  let nil := (select result_from_void__null__with_in("foo"));
  EXPECT_EQ!(nil, null);

  nil := (select result_from_void__null__no_args());
  EXPECT_EQ!(nil, null);

  -- all these bind to nothing so we're really just testing
  -- the call sequence for errors

  b := (select inout__bool__not_null(false));
  EXPECT_EQ!(b, false);
  b := (select inout__bool__nullable(true));
  EXPECT_EQ!(b, true);
  b := (select inout__bool__nullable(null));
  EXPECT_EQ!(b, null);
  r := (select inout__real__not_null(3.25));
  EXPECT_EQ!(r, 3.25);
  r := (select inout__real__nullable(6.5));
  EXPECT_EQ!(r, 6.5);
  r := (select inout__real__nullable(null));
  EXPECT_EQ!(r, null);
  i := (select inout__integer__not_null(7));
  EXPECT_EQ!(i, 7);
  i := (select inout__integer__nullable(11));
  EXPECT_EQ!(i, 11);
  i := (select inout__integer__nullable(null));
  EXPECT_EQ!(i, null);
  l := (select inout__long__not_null(5L));
  EXPECT_EQ!(l, 5);
  l := (select inout__long__nullable(0x123456789a));
  EXPECT_EQ!(l, 0x123456789a);
  l := (select inout__long__nullable(null));
  EXPECT_EQ!(l, null);
  t := (select inout__text__not_null('foo'));
  EXPECT_EQ!(t, 'foo');
  t := (select inout__text__nullable('bar'));
  EXPECT_EQ!(t, 'bar');
  t := (select inout__text__nullable(null));
  EXPECT_EQ!(t, null);
  bl := (select inout__blob__not_null(x'1234'));
  b := (select bl == x'1234');
  EXPECT_EQ!(b, true);
  bl := (select inout__blob__nullable(x'4567'));
  b := (select bl == x'4567');
  EXPECT_EQ!(b, true);
  bl := (select inout__blob__nullable(null));
  EXPECT_EQ!(bl, null);

  b := (select out__bool__not_null());
  EXPECT_EQ!(b, true);
  b := (select out__bool__nullable());
  EXPECT_EQ!(b, null);
  r := (select out__real__not_null());
  EXPECT_EQ!(r, 3.14);
  r := (select out__real__nullable());
  EXPECT_EQ!(r, null);
  i := (select out__integer__not_null());
  EXPECT_EQ!(i, 1234);
  i := (select out__integer__nullable());
  EXPECT_EQ!(i, null);
  l := (select out__long__not_null());
  EXPECT_EQ!(l, 1234567890123456789);
  l := (select out__long__nullable());
  EXPECT_EQ!(l, null);
  t := (select out__text__not_null());
  EXPECT_EQ!(t, 'HW');
  t := (select out__text__nullable());
  EXPECT_EQ!(t, null);
  bl := (select out__blob__not_null());
  b := (select bl ~text~ == 'blob');
  EXPECT_EQ!(b, true);
  bl := (select out__blob__nullable());
  EXPECT_EQ!(bl, null);

  let b_nn := true;
  let i_nn := 1;
  let l_nn := 123456789012345L;
  let r_nn := 1.5;
  let t_nn := 'foo';
  let bl_nn := (select x'1234');

  t := (select result from comprehensive_test1(
    false, null, 1.5, null, 1, null, 12345679012345L, null, 'foo', null,  (select x'1234'), null));
  EXPECT_EQ!(t, 'hello1');

  t := (select result from comprehensive_test2(
    b_nn, b, r_nn, r, i_nn, i, l_nn, l, t_nn, t, bl_nn, bl));

  EXPECT_EQ!(t, 'hello2');

  t := (select result from comprehensive_test3());
  EXPECT_EQ!(t, 'hello3');

  printf("Successful exit\n");
end;


@echo C, '
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi);

#define trace_printf(x,...)

void explicit_test(sqlite3 *db) {
    printf("explicit test\n");

    /* Query with filtering via hidden columns */
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(db, "SELECT * FROM three_int_test WHERE arg_x = 100 AND arg_y = 200 and arg_z = 300", -1, &stmt, NULL);
    trace_printf("explicit rc = %d\n", rc);

    for (;;) {
      trace_printf("stepping\n");
      rc = sqlite3_step(stmt);
      trace_printf("--> step rc = %d\n", rc);
      if (rc != SQLITE_ROW) break;

      int x = sqlite3_column_int(stmt, 0);
      int y = sqlite3_column_int(stmt, 1);
      int z = sqlite3_column_int(stmt, 2);

      printf("Row: %d, %d, %d\n", x, y, z);
      if (x != 100 || y != 200 || z != 300) exit(1);
    }

    /* Cleanup */
    sqlite3_finalize(stmt);
    printf("done explicit test\n");
}

int main(int argc, char **argv) {
   sqlite3 *db = NULL;
   int rc = sqlite3_open(":memory:", &db);
   if (rc) exit(rc);

   // this is the thing that registers all of the UDFs and TVFs
   rc = sqlite3_cqlextension_init(db, NULL, NULL);
   if (rc) exit(rc);

   // this is a hand written test case
   explicit_test(db);

   // this is CQL exercising its own generated procs via the interop interface
   rc = test_cases(db);
   exit(rc);
}
';
