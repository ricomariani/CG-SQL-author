declare proc printf no check;

@echo C,'
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
';

DECLARE SELECT FUNCTION hello_world() (result text);
DECLARE SELECT FUNCTION result_from_result_set__no_args() (result text);
DECLARE SELECT FUNCTION in__bool__not_null() (in__x bool);
DECLARE SELECT FUNCTION in__bool__nullable() (in__x bool);
DECLARE SELECT FUNCTION in__real__not_null() (in__x real);
DECLARE SELECT FUNCTION in__real__nullable() (in__x real);
DECLARE SELECT FUNCTION in__integer__not_null() (in__x integer);
DECLARE SELECT FUNCTION in__integer__nullable() (in__x integer);
DECLARE SELECT FUNCTION in__long__not_null() (in__x long);
DECLARE SELECT FUNCTION in__long__nullable() (in__x long);
DECLARE SELECT FUNCTION in__text__not_null() (in__x text);
DECLARE SELECT FUNCTION in__text__nullable() (in__x text);
DECLARE SELECT FUNCTION in__blob__not_null() (in__x blob);
DECLARE SELECT FUNCTION in__blob__nullable() (in__x blob);
DECLARE SELECT FUNCTION comprehensive_test() (result text);
DECLARE SELECT FUNCTION result_from_result_set__with_in_out_inout() (result text);

proc demo()
begin
  cursor C for select 1 x;
  fetch C;
  printf("Starting demo.\n");
  let r := (select result from hello_world());
  printf("%s\n", r:ifnull("<null>"));
  printf("Successful exit\n");
end;


@echo C, '
int sqlite3_cqlextension_init(sqlite3 *_Nonnull db, char *_Nonnull *_Nonnull pzErrMsg, const sqlite3_api_routines *_Nonnull pApi);
int main(int argc, char **argv) {
   sqlite3 *db = NULL;
   int rc = sqlite3_open(":memory:", &db);
   if (rc) exit(rc);
   rc = sqlite3_cqlextension_init(db, NULL, NULL);
   if (rc) exit(rc);
   rc = demo(db);
   exit(rc);
}
';
