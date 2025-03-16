declare proc printf no check;

@echo C,'
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
';

DECLARE SELECT FUNCTION hello_world() (result text);
DECLARE SELECT FUNCTION result_from_result_set__no_args() (result text);
DECLARE SELECT FUNCTION in__bool__not_null(x bool!) (in__x bool!);
DECLARE SELECT FUNCTION in__bool__nullable(x bool) (in__x bool);
DECLARE SELECT FUNCTION in__real__not_null(x real!) (in__x real!);
DECLARE SELECT FUNCTION in__real__nullable(x real) (in__x real);
DECLARE SELECT FUNCTION in__integer__not_null(x int!) (in__x integer!);
DECLARE SELECT FUNCTION in__integer__nullable(x int) (in__x integer);
DECLARE SELECT FUNCTION in__long__not_null(x long!) (in__x long!);
DECLARE SELECT FUNCTION in__long__nullable(x long) (in__x long);
DECLARE SELECT FUNCTION in__text__not_null(x text!) (in__x text!);
DECLARE SELECT FUNCTION in__text__nullable(x text) (in__x text);
DECLARE SELECT FUNCTION in__blob__not_null(x blob!) (in__x blob!);
DECLARE SELECT FUNCTION in__blob__nullable(x blob) (in__x blob);
DECLARE SELECT FUNCTION three_int_test(x int, y int, z int) (x int, y int, z int);
DECLARE SELECT FUNCTION many_rows(n int) (x int!, y int!, z text!);
DECLARE SELECT FUNCTION result_from_first_inout_or_out_argument__inout(t1 text!, t2 text!, t3 text!) text;
DECLARE SELECT FUNCTION result_from_first_inout_or_out_argument__out(t1 text!, t2 text!, t3 text!) text;
DECLARE SELECT FUNCTION result_from_inout(t text) text;
DECLARE SELECT FUNCTION result_from_out() text;
DECLARE SELECT FUNCTION result_from_void__null__with_in(t text) int;
DECLARE SELECT FUNCTION result_from_void__null__no_args() int;

DECLARE SELECT FUNCTION inout__bool__not_null(b bool!) bool;
DECLARE SELECT FUNCTION inout__bool__nullable(b bool) bool;
DECLARE SELECT FUNCTION inout__real__not_null(r real!) real;
DECLARE SELECT FUNCTION inout__real__nullable(r real) real;
DECLARE SELECT FUNCTION inout__integer__not_null(i int!) int;
DECLARE SELECT FUNCTION inout__integer__nullable(i int) int;
DECLARE SELECT FUNCTION inout__long__not_null(ll long!) long;
DECLARE SELECT FUNCTION inout__long__nullable(l long) long;
DECLARE SELECT FUNCTION inout__text__not_null(t text!) text;
DECLARE SELECT FUNCTION inout__text__nullable(t text) text;
DECLARE SELECT FUNCTION inout__blob__not_null(b blob!) blob;
DECLARE SELECT FUNCTION inout__blob__nullable(b blob) blob;

/* Pending test cases

DECLARE SELECT FUNCTION out__bool__not_null()
DECLARE SELECT FUNCTION out__bool__nullable()
DECLARE SELECT FUNCTION out__real__not_null()
DECLARE SELECT FUNCTION out__real__nullable()
DECLARE SELECT FUNCTION out__integer__not_null()
DECLARE SELECT FUNCTION out__integer__nullable()
DECLARE SELECT FUNCTION out__long__not_null()
DECLARE SELECT FUNCTION out__long__nullable()
DECLARE SELECT FUNCTION out__text__not_null()
DECLARE SELECT FUNCTION out__text__nullable()
DECLARE SELECT FUNCTION out__blob__not_null()
DECLARE SELECT FUNCTION out__blob__nullable()
DECLARE SELECT FUNCTION comprehensive_test() (result text);
DECLARE SELECT FUNCTION result_from_result_set__with_in_out_inout() (result text);
*/

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

@macro(stmt_list) E!(x! expr, y! expr)
begin
  let @tmp(x) := x!;
  let @tmp(y) := y!;
  if @tmp(x) is not @tmp(y) then
     printf("line %d error %s is not %s\n", @MACRO_LINE, @tmp(x):fmt, @tmp(y):fmt);
     printf("expressions:%s is not %s\n", @text(x!), @text(y!));
     throw;
  end if;
end;

proc demo()
begin
  printf("Starting demo.\n");
  let hello := (select result from hello_world());
  printf("%s\n", hello:ifnull("<null>"));

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

  t := (select result_from_first_inout_or_out_argument__inout("foo", "bar", "baz"));
  E!(t, "inout_argument");

  t := (select result_from_first_inout_or_out_argument__out("foo", "bar", "baz"));
  E!(t, "out_argument");

  t := (select result_from_inout("foo"));
  E!(t, "inout_argument");

  t := (select result_from_out());
  E!(t, "out_argument");

  let nil := (select result_from_void__null__with_in("foo"));
  E!(nil, null);

  nil := (select result_from_void__null__no_args());
  E!(nil, null);

  -- all these bind to nothing so we're really just testing
  -- the call sequence for errors

  b := (select inout__bool__not_null(false));
  E!(b, false);
  b := (select inout__bool__nullable(null));
  E!(b, null);
  r := (select inout__real__not_null(3.25));
  E!(r, 3.25);
  r := (select inout__real__nullable(null));
  E!(r, null);
  i := (select inout__integer__not_null(7));
  E!(i, 7);
  i := (select inout__integer__nullable(null));
  E!(i, null);
  l := (select inout__long__not_null(5L));
  E!(l, 5);
  l := (select inout__long__nullable(null));
  E!(l, null);
  t := (select inout__text__not_null('foo'));
  E!(t, 'foo');
  t := (select inout__text__nullable(null));
  E!(t, null);
  bl := (select inout__blob__not_null(x'1234'));
  b := (select bl == x'1234');
  E!(b, true);
  bl := (select inout__blob__nullable(null));
  E!(bl, null);
  
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
   rc = sqlite3_cqlextension_init(db, NULL, NULL);
   if (rc) exit(rc);
   explicit_test(db);
   rc = demo(db);
   exit(rc);
}
';

