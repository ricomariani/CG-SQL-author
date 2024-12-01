# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# the common make file requires no overrides for the OSS build

ifndef NON_STD_YACC
LEX = flex
YACC = bison
endif

O=out
T=test

# SQLITE_PATH is the path to the sqlite3 source code, if it's not defined then
# we'll use the system sqlite3. This is useful for testing on systems that don't
# have sqlite3 installed.  sqlite3.c is the amalgamation of the sqlite3 source
# code, so it's a single file that can be compiled into the various test cases
# and so forth.  This is also a good way to test a specific version of sqlite3,
# e.g. the latest new release.
ifdef SQLITE_PATH
SQLITE_OBJ = $O/sqlite3.o
SQLITE_LINK = $(SQLITE_OBJ)
CFLAGS += -I$(SQLITE_PATH)
else
SQLITE_LINK = -lsqlite3
endif

SQLITE_LINK+=-pthread -ldl
CFLAGS += -I. -I$O
CFLAGS += -g
CFLAGS += -Werror

ifdef CGSQL_GCC
CFLAGS += -std=c99
endif

ifdef CGSQL_ASAN
CFLAGS += -fsanitize=address
endif

ifdef COVERAGE
CFLAGS += -O0 --coverage
endif

#note cql itself doesn't use cqlrt.o but we insist that it can be compiled
PROGRAMS = $O/cql $O/cqlrt.o $O/cqltest.o

all: ${PROGRAMS}

OBJECTS = $O/cql.y.o $O/cql.o $O/ast.o $O/gen_sql.o $O/sem.o $O/list.o $O/bytebuf.o $O/charbuf.o \
          $O/cg_common.o $O/cg_c.o $O/cg_objc.o $O/symtab.o $O/compat.o \
          $O/cg_schema.o $O/crc64xz.o $O/sha256.o $O/cg_json_schema.o $O/cg_test_helpers.o $O/encoders.o \
          $O/unit_tests.o $O/cg_query_plan.o ${O}/minipool.o $O/rt.o $O/eval.o \
          $O/rewrite.o $O/printf.o $O/flow.o $O/cg_stats.o $O/cg_lua.o

$O/%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$O/flex_tested:
	common/test_flex.sh "$(LEX)"
	touch $O/flex_tested

$O/bison_tested: $O/flex_tested
	common/test_bison.sh "$(YACC)"
	touch $O/bison_tested

$O/cql: $O/bison_tested $(OBJECTS) $(SQLITE_OBJ)
	${CC} -DSQLITE_DEBUG ${CFLAGS} -o $O/cql $(OBJECTS)

$O/cql.y.c $O/cql.y.h: cql.y encoders.h charbuf.h
	${YACC} -Werror -vd cql.y -o $O/cql.y.c

$O/cql.c: cql.l
	${LEX} -o $*.c $<

# For replacing terminals in the generated language grammar diagram
$O/replacements: ../scripts/grammar_utils/replacements.l
	${LEX} -o $O/replacements.c $<
	${CC} -o $@ $O/replacements.c

# For replacing terminals in the generated CQL JSON grammar diagram
$O/json_replacements: ../scripts/grammar_utils/json_replacements.l
	${LEX} -o $O/json_replacements.c $<
	${CC} -o $@ $O/json_replacements.c

# The dependencies are only approximately correct, you can't trust
# these in general but the full build is so fast it hardly matters

$O/cql.y.o: $O/cql.y.c $O/cql.y.h

$O/ast.o: ast.c $O/cql.y.h ast.h

$O/cql.o: $O/cql.c $O/cql.y.h cql.h ast.h

$O/cql.y.o: $O/cql.y.c $O/cql.y.h

$O/unit_tests.o: unit_tests.c unit_tests.h

$O/encoders.o: encoders.c encoders.h

$O/crc64xz.o: crc64xz.c crc64xz.h

$O/sha256.o: sha256.c sha256.h

$O/ast.o: ast.c ast.h cql.h encoders.h charbuf.h

$O/cqlrt.o: cqlrt.c cqlrt.h cqlrt_common.c cqlrt_common.h

$O/rt.o: rt.c rt.h

$O/gen_sql.o: gen_sql.c ast.h gen_sql.h charbuf.h cql.h encoders.h sem.h

$O/cg_schema.o: cg_schema.h cql.h sem.h ast.h list.h symtab.h cg_common.h crc64xz.h

$O/cg_json_schema.o: cg_json_schema.h cql.h sem.h ast.h list.h symtab.h cg_common.h crc64xz.h

$O/sem.o: sem.c sem.h ast.h list.h charbuf.h cql.h bytebuf.h rewrite.h encoders.h printf.h flow.h

$O/list.o: list.c list.h ast.h cql.h

$O/compat.o: compat.c compat.h

$O/charbuf.o: charbuf.c charbuf.h cql.h

$O/bytebuf.o: bytebuf.c bytebuf.h cql.h

$O/cg_common.o: cg_common.c cg_common.h ast.h charbuf.h cql.h symtab.h sem.h

$O/cg_c.o: cg_c.c cg_c.h cg_common.h ast.h sem.h charbuf.h list.h cql.h ast.h

$O/cg_objc.o: cg_objc.c cg_objc.h cg_common.h ast.h sem.h charbuf.h list.h cql.h ast.h

$O/cg_test_helpers.o: cg_test_helpers.c cg_test_helpers.h cg_common.h sem.h charbuf.h list.h cql.h ast.h

$O/cg_query_plan.o: cg_query_plan.c cg_query_plan.h cg_common.h ast.h sem.h charbuf.h list.h cql.h ast.h

$O/cg_stats.o: cg_stats.c cg_stats.h ast.h

$O/eval.o: eval.c eval.h

$O/rewrite.o: rewrite.h sem.h ast.h

$O/printf.o: printf.c printf.h ast.h cql.h sem.h

$O/flow.o: flow.c flow.h ast.h cql.h sem.h

$O/symtab.o: symtab.c symtab.h bytebuf.h

$O/minipool.o: minipool.c minipool.h

$O/sqlite3.o: $(SQLITE_PATH)/sqlite3.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf *.gcno *.gcda $O .pbcopy.swp
	mkdir $O

amalgam: $O/cql.c $O/cql.y.c $O/cql.y.h
	bash make_amalgam.sh
	$(CC) $(CFLAGS) -o $O/cql_amalgam.o -c $O/cql_amalgam.c
	$(CC) $(CFLAGS) -o $O/cql_amalgam $O/cql_amalgam.o

cg_test: $O/cg_test_c.c

cg_test_schema_upgrade: ${O}/cg_test_schema_upgrade.o

$O/cqltest.o: $T/cqltest.c
	$(CC) $(CFLAGS) -c -o $O/cqltest.o $T/cqltest.c

$O/run_test.o: $O/run_test.c

$O/run_test_compressed.o: $O/run_test_compressed.c

$O/cg_test_c.o: $O/cg_test_c.c

$O/cg_test_c_with_type_getters.o: $O/cg_test_c_with_type_getters.c

$O/run_test_client.o: run_test_client.c
	$(CC) $(CFLAGS) -DCQL_RUN_TEST -c -o $O/run_test_client.o run_test_client.c

$O/result_set_extension.o: result_set_extension.c

$O/query_plan_test.o: query_plan_test.c

$O/query_plan.o: $O/query_plan.c

$O/test_helpers.o: $O/test_helpers.c

$O/test_helpers_test.o: test_helpers_test.c

$O/cqlrt_mocked.o: cqlrt.c cqlrt.h cqlrt_common.c cqlrt_common.h
	$(CC) $(CFLAGS) -DCQL_RUN_TEST -c -o $O/cqlrt_mocked.o cqlrt.c

RUN_TEST_DEPS=$O/run_test.o $O/cqltest.o $O/run_test_client.o $O/cqlrt_mocked.o $O/result_set_extension.o

run_test: $(RUN_TEST_DEPS)
	$(CC) -o $O/run_test $(CFLAGS) $(RUN_TEST_DEPS) $(SQLITE_LINK)

RUN_TEST_COMPRESSED_DEPS=$(RUN_TEST_DEPS:run_test.o=run_test_compressed.o)

run_test_compressed: $(RUN_TEST_COMPRESSED_DEPS)
	$(CC) -o $O/run_test_compressed $(CFLAGS) $(RUN_TEST_COMPRESSED_DEPS) $(SQLITE_LINK)

# ensure that the same .o file is used exactly, rather than rebuilding from .c, this avoids gcov errors

$O/upgrade_test.o: upgrade/upgrade_test.c
	$(CC) -o $@ -c $(CFLAGS) $<

$O/downgrade_test.o: upgrade/downgrade_test.c
	$(CC) -o $@ -c $(CFLAGS) $<

$O/upgrade_validate.o: $O/upgrade_validate.c

$O/generated_upgrade0.o: $O/generated_upgrade0.c

$O/generated_upgrade1.o: $O/generated_upgrade1.c

$O/generated_upgrade2.o: $O/generated_upgrade2.c

$O/generated_upgrade3.o: $O/generated_upgrade3.c

$O/generated_upgrade4.o: $O/generated_upgrade4.c

UPGRADE_OBJS = $O/generated_upgrade0.o $O/generated_upgrade1.o $O/generated_upgrade2.o $O/generated_upgrade3.o $O/generated_upgrade4.o

upgrade_test: $(UPGRADE_OBJS) $O/upgrade_test.o $O/upgrade_validate.o $O/downgrade_test.o $O/cqlrt_mocked.o
	$(CC) $(CFLAGS) -o $O/upgrade0 $O/cqlrt_mocked.o $O/upgrade_validate.o $O/generated_upgrade0.o $O/upgrade_test.o $(SQLITE_LINK)
	$(CC) $(CFLAGS) -o $O/upgrade1 $O/cqlrt_mocked.o $O/upgrade_validate.o $O/generated_upgrade1.o $O/upgrade_test.o $(SQLITE_LINK)
	$(CC) $(CFLAGS) -o $O/upgrade2 $O/cqlrt_mocked.o $O/upgrade_validate.o $O/generated_upgrade2.o $O/upgrade_test.o $(SQLITE_LINK)
	$(CC) $(CFLAGS) -o $O/upgrade3 $O/cqlrt_mocked.o $O/upgrade_validate.o $O/generated_upgrade3.o $O/upgrade_test.o $(SQLITE_LINK)
	$(CC) $(CFLAGS) -o $O/upgrade4 $O/cqlrt_mocked.o $O/upgrade_validate.o $O/generated_upgrade4.o $O/upgrade_test.o $(SQLITE_LINK)
	$(CC) $(CFLAGS) -o $O/downgrade_test $O/cqlrt_mocked.o $O/generated_upgrade1.o $O/downgrade_test.o $(SQLITE_LINK)

query_plan_test: $O/query_plan_test.o $O/cqlrt.o $O/query_plan.o
	$(CC) $(CFLAGS) -o $O/query_plan_test $O/query_plan_test.o $O/cqlrt.o $O/query_plan.o $(SQLITE_LINK)

test_helpers_test: $O/test_helpers_test.o $O/cqlrt.o $O/test_helpers.o
	$(CC) $(CFLAGS) -o $O/test_helpers_test $O/test_helpers_test.o $O/cqlrt.o $O/test_helpers.o $(SQLITE_LINK)

$O/cql-verify.o: cql-verify/cql-verify.c cql-verify/cql-verify.h
	$(CC) -o $@ -c $(CFLAGS) cql-verify/cql-verify.c

$O/cqlhelp.o: cql-verify/cqlhelp.c
	$(CC) -o $@ -c $(CFLAGS) $<

cql-verify: $O/cqlrt.o $O/cql-verify.o $O/cqlhelp.o $(SQLITE_OBJ)
	$(CC) $(CFLAGS) -I. -o $O/cql-verify $O/cqlhelp.o $O/cqlrt.o $O/cql-verify.o $(SQLITE_LINK)

$O/linetest.o: linetester/linetest.c linetester/linetest.h
	$(CC) -o $@ -c $(CFLAGS) -Icql-verify linetester/linetest.c

cql-linetest: $O/cqlrt.o $O/linetest.o $(SQLITE_OBJ) $O/cqlhelp.o
	$(CC) $(CFLAGS) -I. -o $O/cql-linetest $O/cqlrt.o $O/linetest.o $O/cqlhelp.o $(SQLITE_LINK)

json-test: $O/json_test

$O/json_test: json_test/json_test.y json_test/json_test.l
	${YACC} -Werror -vd json_test/json_test.y -o $O/json_test.y.c
	${LEX} -o $O/json_test.c json_test/json_test.l
	$(CC) -c $(CFLAGS) -o $O/json_test.o $O/json_test.c
	$(CC) -c $(CFLAGS) -o $O/json_test.y.o $O/json_test.y.c
	$(CC) $(CFLAGS) -o $O/json_test $O/json_test.y.o $O/json_test.o

amalgam_test:
	bash make_amalgam.sh
	$(CC) $(CFLAGS) -o $O/amalgam_test.o -c $T/amalgam_test.c
	$(CC) $(CFLAGS) -o $O/amalgam_test $O/amalgam_test.o
