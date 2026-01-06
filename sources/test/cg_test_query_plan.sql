/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- TEST: query plan
-- + SELECT FUNC is_declare_func_enabled () BOOL!;
-- + SELECT FUNC is_declare_func_wall (id LONG) BOOL!;
-- + SELECT FUNC array_num_at (array_object_ptr LONG!, idx INT!) LONG;
-- + SELECT FUNC select_virtual_table (b TEXT) (id LONG, t TEXT, b BLOB, r REAL);
-- + [[deterministic]]
-- + SELECT FUNC bgetkey_type (x BLOB!) LONG!;
-- + [[deterministic]]
-- + SELECT FUNC bgetval_type (x BLOB!) LONG!;
-- + [[deterministic]]
-- + SELECT FUNC bgetkey NO CHECK BLOB;
-- + [[deterministic]]
-- + SELECT FUNC bgetval NO CHECK BLOB;
-- + [[deterministic]]
-- + SELECT FUNC bcreatekey NO CHECK BLOB;
-- + [[deterministic]]
-- + SELECT FUNC bcreateval NO CHECK BLOB;
-- + [[deterministic]]
-- + SELECT FUNC bupdatekey NO CHECK BLOB;
-- + [[deterministic]]
-- + SELECT FUNC bupdateval NO CHECK BLOB;
-- + SELECT FUNC stuff () INT!;
-- + PROC create_schema()
-- + BEGIN
-- +   call cql_create_udf_stub("is_declare_func_enabled");
-- +   call cql_create_udf_stub("is_declare_func_wall");
-- +   call cql_create_udf_stub("array_num_at");
-- +   call cql_create_udf_stub("select_virtual_table");
-- +   call cql_create_udf_stub("bgetkey_type");
-- +   call cql_create_udf_stub("bgetval_type");
-- +   call cql_create_udf_stub("bgetkey");
-- +   call cql_create_udf_stub("bgetval");
-- +   call cql_create_udf_stub("bcreatekey");
-- +   call cql_create_udf_stub("bcreateval");
-- +   call cql_create_udf_stub("bupdatekey");
-- +   call cql_create_udf_stub("bupdateval");
-- +   call cql_create_udf_stub("stuff");
-- +   CREATE TABLE `table one`(
-- +     id INT PRIMARY KEY,
-- +     name TEXT
-- +   );
-- +   CREATE TABLE t2(
-- +     id INT PRIMARY KEY,
-- +     name TEXT
-- +   );
-- +   CREATE TABLE t3(
-- +     id INT PRIMARY KEY,
-- +     name TEXT
-- +   );
-- +   CREATE TABLE t4(
-- +     id LONG PRIMARY KEY AUTOINCREMENT,
-- +     data BLOB
-- +   );
-- +   CREATE TABLE t5(
-- +     id LONG,
-- +     FOREIGN KEY (id) REFERENCES t4 (id) ON UPDATE CASCADE ON DELETE CASCADE
-- +   );
-- +   CREATE TABLE scan_ok(
-- +     id INT
-- +   );
-- +   CREATE TABLE foo(
-- +     id INT
-- +   );
-- +   CREATE TABLE _foo(
-- +     id INT
-- +   );
-- +   CREATE TABLE foo_(
-- +     id INT
-- +   );
-- +   CREATE INDEX `table one index` ON `table one` (name, id);
-- +   CREATE INDEX it4 ON t4 (data, id);
-- +   CREATE VIEW my_view AS
-- +   SELECT
-- +       `table one`.id,
-- +       `table one`.name,
-- +       t2.id,
-- +       t2.name
-- +     FROM `table one`
-- +       INNER JOIN t2 USING (id);
-- +   CREATE VIEW my_view_using_table_alias AS
-- +   SELECT
-- +       foo.id,
-- +       foo.name,
-- +       bar.id AS id2,
-- +       bar.rowid AS rowid
-- +     FROM `table one` AS foo
-- +       INNER JOIN t2 AS bar USING (id);
-- +   CREATE TRIGGER my_trigger
-- +     AFTER INSERT ON `table one`
-- +     WHEN is_declare_func_enabled() AND is_declare_func_wall(new.id) = 1
-- +   BEGIN
-- +   DELETE FROM t2 WHERE id > new.id;
-- +   END;
-- +   CREATE TABLE virtual_table(
-- +     id INT,
-- +     t TEXT,
-- +     b BLOB,
-- +     r REAL
-- +   );
-- +   CREATE TABLE C(
-- +     id INT!,
-- +     name TEXT
-- +   );
-- +   CREATE TABLE select_virtual_table (
-- +     id INT,
-- +     t TEXT,
-- +     b BLOB,
-- +     r REAL
-- +   );
-- +   [[backing_table]]
-- +   CREATE TABLE backing(
-- +     k BLOB PRIMARY KEY,
-- +     v BLOB!
-- +   );
-- +   CREATE INDEX backing_index ON backing (bgetkey_type(k));
-- +   CREATE TABLE sql_temp(
-- +     id INT! PRIMARY KEY,
-- +     sql TEXT!
-- +   ) WITHOUT ROWID;
-- +   CREATE TABLE plan_temp(
-- +     iselectid INT!,
-- +     iorder INT!,
-- +     ifrom INT!,
-- +     zdetail TEXT!,
-- +     sql_id INT!,
-- +     FOREIGN KEY (sql_id) REFERENCES sql_temp(id)
-- +   );
-- +   CREATE TABLE no_table_scan(
-- +     table_name TEXT! PRIMARY KEY
-- +   );
-- +   CREATE TABLE table_scan_alert(
-- +     info TEXT!
-- +   );
-- +   CREATE TABLE b_tree_alert(
-- +     info TEXT!
-- +   );
-- +   CREATE TABLE ok_table_scan(
-- +     sql_id INT! PRIMARY KEY,
-- +     proc_name TEXT!,
-- +     table_names TEXT!
-- +   ) WITHOUT ROWID;
-- + END;
--
-- + [[backed_by=backing]]
-- + CREATE TABLE backed(
-- +   id INT PRIMARY KEY,
-- +   name TEXT
-- + );
-- + PROC populate_no_table_scan()
-- + BEGIN
-- +   INSERT OR IGNORE INTO no_table_scan(table_name) VALUES
-- +     ("table one"),
-- +     ("t2"),
-- +     ("scan_ok"),
-- +     ("foo");
-- + END;
--
-- + PROC populate_query_plan_1()
-- + BEGIN
-- +   LET query_plan_trivial_object := trivial_object();
-- +   LET query_plan_trivial_blob := trivial_blob();
--
-- +   LET stmt := "SELECT %\\n  FROM `table one`\\n  WHERE name = 'Nelly' AND id IN (SELECT id\\n  FROM t2\\n  WHERE id = 1\\nUNION\\nSELECT id\\n  FROM t3)\\n  ORDER BY name ASC";
-- +   INSERT INTO sql_temp(id, sql) VALUES(1, stmt);
-- +   CURSOR C FOR EXPLAIN QUERY PLAN
-- +   SELECT %
-- +     FROM `table one`
-- +     WHERE name = 'Nelly' AND id IN (SELECT id
-- +     FROM t2
-- +     WHERE id = 1
-- +   UNION
-- +   SELECT id
-- +     FROM t3)
-- +     ORDER BY name ASC;
-- +   LOOP FETCH C
-- +   BEGIN
-- +     INSERT INTO plan_temp(sql_id, iselectid, iorder, ifrom, zdetail) VALUES(1, C.iselectid, C.iorder, C.ifrom, C.zdetail);
-- +   END;
-- + END;
--
-- + PROC populate_query_plan_2()
-- + PROC populate_query_plan_20()
--
-- + [[shared_fragment]]
-- + PROC split_commas (str TEXT)
-- + BEGIN
-- + WITH
-- +   splitter (tok, rest) AS (
-- +     SELECT "", IFNULL(str || ",", "")
-- +     UNION ALL
-- +     SELECT substr(rest, 1, instr(rest, ",") - 1), substr(rest, instr(rest, ",") + 1)
-- +       FROM splitter
-- +       WHERE rest <> ""
-- +   )
-- + SELECT tok
-- +   FROM splitter
-- +   WHERE tok <> "";
-- + END;
--
-- + [[shared_fragment]]
-- + PROC ids_from_string (str TEXT)
-- + BEGIN
-- + WITH
-- +   toks (tok) AS (CALL split_commas(str))
-- + SELECT CAST(tok AS LONG) AS id
-- +   FROM toks;
-- + END;
--
-- + PROC populate_query_plan_21()
-- + BEGIN
-- +   LET query_plan_trivial_object := trivial_object();
-- +   LET query_plan_trivial_blob := trivial_blob();
--
-- +   LET stmt := "WITH\\n  I (id) AS (CALL ids_from_string('1')),\\n  E (id) AS (CALL ids_from_string('1'))\\nSELECT %\\n  FROM C\\n  WHERE C.id IN (SELECT %\\n  FROM I) AND C.id NOT IN (SELECT %\\n  FROM E)";
-- +   INSERT INTO sql_temp(id, sql) VALUES(21, stmt);
-- +   CURSOR C FOR EXPLAIN QUERY PLAN
-- +   WITH
-- +     I (id) AS (CALL ids_from_string('1')),
-- +     E (id) AS (CALL ids_from_string('1'))
-- +   SELECT %
-- +     FROM C
-- +     WHERE C.id IN (SELECT %
-- +     FROM I) AND C.id NOT IN (SELECT %
-- +     FROM E);
-- +   LOOP FETCH C
-- +   BEGIN
-- +     INSERT INTO plan_temp(sql_id, iselectid, iorder, ifrom, zdetail) VALUES(21, C.iselectid, C.iorder, C.ifrom, C.zdetail);
-- +   END;
-- + END;
--
-- + [[shared_fragment]]
-- + [[query_plan_branch=11]]
-- + PROC frag1 (x INT)
-- + BEGIN
-- + SELECT 2 AS a;
-- + END;
--
-- + [[shared_fragment]]
-- + [[query_plan_branch=4]]
-- + PROC frag2 (y INT)
-- + BEGIN
-- + SELECT 40 AS b;
-- + END;
--
-- + [[shared_fragment]]
-- + PROC frag3 (z INT)
-- + BEGIN
-- + SELECT 100 AS c;
-- + END;
--
-- + [[shared_fragment]]
-- + PROC frag_with_select ()
-- + BEGIN
-- + WITH
-- +   cte (a) AS (
-- +     SELECT 1 AS a
-- +   )
-- + SELECT cte.a
-- +   FROM cte;
-- + END;
--
-- + [[shared_fragment]]
-- + [[query_plan_branch=2]]
-- + PROC frag_with_select_nothing ()
-- + BEGIN
-- + SELECT 1 AS a;
-- + END;
--
-- + [[shared_fragment]]
-- + PROC frag (v INT!)
-- + BEGIN
-- + SELECT v AS val;
-- + END;
--
-- + PROC populate_query_plan_40()
--
-- + PROC populate_table_scan_alert_table(table_ text!)
-- + BEGIN
-- +   INSERT OR IGNORE INTO table_scan_alert
-- +     SELECT upper(table_) || '(' || count(*) || ')' as info FROM plan_temp
-- +     WHERE ( zdetail GLOB ('*[Ss][Cc][Aa][Nn]* ' || table_) OR
-- +             zdetail GLOB ('*[Ss][Cc][Aa][Nn]* ' || table_ || ' *')
-- +           )
-- +     AND sql_id NOT IN (
-- +       SELECT sql_id from ok_table_scan
-- +         WHERE table_names GLOB ('*#' || table_ || '#*')
-- +     ) GROUP BY table_;
-- + END;
--
-- + PROC populate_b_tree_alert_table()
-- + END;
--
-- + PROC print_query_plan_graph(id_ int!)
-- + BEGIN
-- +   DECLARE C CURSOR FOR
-- +   WITH RECURSIVE
-- +     plan_chain(iselectid,  zdetail, level) AS (
-- +      SELECT 0 as  iselectid, 'QUERY PLAN' as  zdetail, 0 as level
-- +      UNION ALL
-- +      SELECT plan_temp.iselectid, plan_temp.zdetail, plan_chain.level+1 as level
-- +       FROM plan_temp JOIN plan_chain ON plan_temp.iorder=plan_chain.iselectid WHERE plan_temp.sql_id = id_
-- +      ORDER BY 3 DESC
-- +     )
-- +     SELECT
-- +      level,
-- +      substr('                              ', 1, max(level - 1, 0)*3) ||
-- +      substr('|.............................', 1, min(level, 1)*3) ||
-- +      zdetail as graph_line FROM plan_chain;
--
-- +   CALL printf("   \"plan\" : \"");
-- +   LOOP FETCH C
-- +   BEGIN
-- +     CALL printf("%s%s", IIF(C.level, "\\n", ""), C.graph_line);
-- +   END;
-- +   CALL printf("\"\n");
-- + END;
--
-- + PROC print_query_plan(sql_id int!)
-- + BEGIN
-- +   CALL printf("  {\n");
-- +   CALL printf("   \"id\" : %d,\n", sql_id);
-- +   CALL print_sql_statement(sql_id);
-- +   CALL print_query_plan_stat(sql_id);
-- +   CALL print_query_plan_graph(sql_id);
-- +   CALL printf("  }");
-- + END;
--
-- + PROC query_plan()
-- + BEGIN
-- +   CALL create_schema();
-- +   TRY
-- +     CALL populate_no_table_scan();
-- +   CATCH
-- +     CALL printf("failed populating no_table_scan table\n");
-- +     THROW;
-- +   END;
-- +   CALL printf("{\n");
-- +   CALL print_query_violation();
-- +   CALL printf("\"plans\" : [\n");
-- +   LET q := 1;
-- +   WHILE q <=
-- +   BEGIN
-- +     CALL printf("%s", IIF(q == 1, "", ",\n"));
-- +     CALL print_query_plan(q);
-- +     SET q := q + 1;
-- +   END;
-- +   CALL printf("\n]\n");
-- +   CALL printf("}");
-- + END;
[[no_table_scan]]
create table `table one`(id int primary key, name text);

-- duplicate, no problem!  only one will be emitted for SQLite
[[no_table_scan]]
create table `table one`(id int primary key, name text);

[[no_table_scan]]
create table t2(id int primary key, name text);
create table t3(id int primary key, name text);
create table t4(id long int primary key autoincrement, data blob);
create table t5(id long int, foreign key (id) references t4(id) on update cascade on delete cascade);
create table t6(id int primary key, name text) @delete(1);
[[no_table_scan]]
create table scan_ok(id int);
[[no_table_scan]]
create table foo(id int);
create table _foo(id int);
create table foo_(id int);
create index `table one index` ON `table one`(name, id);
create index `table one index` ON `table one`(name, id);
create index it4 ON t4(data, id);
create index it4 ON t4(data, id);
create index it5 ON t4(data) @delete(1);
create view my_view as select * from `table one` inner join t2 using(id);
create view my_view as select * from `table one` inner join t2 using(id);
create view my_view_using_table_alias as select foo.*, bar.id id2, bar.rowid rowid from `table one` as foo inner join t2 as bar using(id);
func any_func() bool not null;
select function is_declare_func_enabled() bool not null;
select function is_declare_func_wall(id long integer) bool not null;
select function array_num_at(array_object_ptr LONG!, idx int!) long;
func blob_from_string(str text) create blob not null;
declare timer_var int;
declare label_var text;
declare data_var blob;
set timer_var := 1;
set label_var := 'Eric';
set data_var := blob_from_string('1');
create trigger my_trigger
  after insert on `table one` when is_declare_func_enabled() and (is_declare_func_wall(new.id) = 1)
begin
  delete from t2 where id > new.id;
end;
create trigger my_trigger
  after insert on `table one` when is_declare_func_enabled() and (is_declare_func_wall(new.id) = 1)
begin
  delete from t2 where id > new.id;
end;

create trigger my_trigger_deleted
  after insert on `table one` when is_declare_func_enabled() and (is_declare_func_wall(new.id) = 1)
begin
  delete from t2 where id > new.id;
end @delete(1);

create virtual table virtual_table using module_name(this, that, the_other) as (
  id integer,
  t text,
  b blob,
  r real
);

select function select_virtual_table(b text) (id long int, t text, b blob, r real);

-- Proc with SELECT stmt
proc sample()
begin
  select * from `table one`
    where name = 'Nelly' and
    id IN (
      select id from t2
        where id = timer_var
      union
      select id from t3
    )
    order by name asc;
end;

-- SELECT stmt
select is_declare_func_wall(id) from t4 where data = data_var;

-- UPDATE stmt
update `table one` set id = 1, name = label_var where name in (select T.NAME from t3 as T);

-- [WITH ... UPDATE] stmt
with
  some_cte(id, name) as (select T.* from t2 as T)
update `table one` set id = 1, name = label_var where name in (select name from some_cte);

-- UPDATE FROM stmt
-- This does not work on SQLite 3.31 which is still the default on Ubuntu
-- disabling this for now.  Maybe we can do this conditionally somehow...
-- update `table one` set id = other_table.id, name = other_table.name from (select foo.* from t2 as foo limit 1) as other_table;

-- DELETE stmt
delete from `table one`
  where name in (
    select foo.name
      from t2 as foo inner join t3 using(name)
  );

-- [WITH ... DELETE] stmt
with
  some_cte(name) as (
    select foo.name from t2 as foo inner join t3 using(id)
  )
  delete from `table one` where name not in (select * from some_cte);

-- INSERT stmt
insert into `table one` select foo.* from t2 as foo union all select bar.* from t3 as bar;

-- [WITH... INSERT] stmt
with some_cte(id, name) as (select T.* from t2 as T)
insert into `table one` select * from some_cte;

-- BEGIN stmt
begin transaction;

-- UPSERT stmt
insert into `table one`(id, name) values(1, 'Irene') on conflict(id) do update set name = excluded.name || 'replace' || ' • ' || '\x01\x02\xA1\x1b\x00\xg' || 'it''s high noon\r\n\f\b\t\v' || "it's" || name;

-- [WITH...UPSERT] stmt
with some_cte(id, name) as (select 1, 'Irene')
insert into `table one`(id, name) select * from some_cte where id = 1 on conflict(id) do update set name = excluded.name || 'replace' || ' • ' || ' 😀 ' || ' é ' || '\x01\x02\xA1\x1b\x00\xg' || 'it''s high noon\r\n\f\b\t\v' || "it's" || name;

-- COMMIT stmt
commit transaction;

-- DROP TABLE stmt
drop table if exists `table one`;

-- DROP VIEW stmt
drop view my_view;

-- DROP INDEX stmt
drop index `table one index`;

-- DROP TRIGGER stmt
drop trigger if exists my_trigger;

-- [WITH ... SELECT] stmt
with
  some_cte(name) as (
    select t2.name from t2 inner join t3 using(id)
  )
  select * from some_cte;

-- Object type in stmt
-- + SELECT array_num_at(ptr(query_plan_trivial_object), id) AS idx
proc read_object(sync_group_ids_ object not null)
begin
  select array_num_at(ptr(sync_group_ids_), id) as idx from `table one`;
end;

-- ok_table_scan attr
[[ok_table_scan=(scan_ok, t3)]]
proc use_ok_table_scan_attr()
begin
  select * from scan_ok;
end;

-- test no table scan on "foo_", "_foo" but should be on "foo"
proc table_name_like_t1()
begin
  select 1 as n from foo_, _foo;
end;

proc nullable_variables_remain_nullable(a int)
begin
  -- analysis of this would fail if `a` were replaced with a value of a nonnull
  -- type when generating the query plan
  select ifnull(a, 42) as nullable_result;
end;

create table C(
 id int!,
 name text);

[[shared_fragment]]
PROC split_commas(str text)
BEGIN
  WITH splitter(tok, rest) AS (
    SELECT "", IFNULL(str || ",", "")
    UNION ALL
    SELECT
      substr(rest, 1, instr(rest, ",") - 1),
      substr(rest, instr(rest, ",") + 1)
    FROM splitter
    WHERE rest <> "")
  SELECT tok FROM splitter WHERE tok <> "";
END;

[[shared_fragment]]
PROC ids_from_string(str text)
BEGIN
  WITH toks(tok) AS (CALL split_commas(str))
  SELECT CAST(tok AS LONG) AS id FROM toks;
END;

PROC use_shared(inc_ text!, exc_ text!)
begin
  WITH
  I(id) as (call ids_from_string(inc_)),
  E(id) as (call ids_from_string(exc_))
  select C.* from C
  where C.id in (select * from I)
  and C.id not in (select * from E);
end;

[[shared_fragment]]
[[query_plan_branch=011]]
PROC frag1(x int)
BEGIN
  IF x == 2 THEN
    SELECT 1 a;
  ELSE
    SELECT 2 a;
  END IF;
END;

[[shared_fragment]]
[[query_plan_branch=4]]
PROC frag2(y int)
BEGIN
  IF y == 2 THEN
    SELECT 10 b;
  ELSE IF y == -1 THEN
    SELECT 20 b;
  ELSE IF y == 0 THEN
    SELECT 30 b;
  ELSE IF y == 3 THEN
    SELECT 40 b;
  ELSE
    SELECT 50 b;
  END IF;
END;

[[shared_fragment]]
[[query_plan_branch=1]]
PROC frag3(z int)
BEGIN
  IF z == 2 THEN
    SELECT 100 c;
  ELSE
    SELECT 200 c;
  END IF;
END;

[[shared_fragment]]
[[query_plan_branch=1]]
PROC frag_with_select() BEGIN
  IF TRUE THEN
    WITH cte(a) AS (SELECT 1 a)
    SELECT * FROM cte;
  ELSE
    SELECT 2 a;
  END IF;
END;

[[shared_fragment]]
[[query_plan_branch=2]]
PROC frag_with_select_nothing() BEGIN
  IF TRUE THEN
    SELECT 1 a;
  ELSE
    SELECT NOTHING;
  END IF;
END;

[[shared_fragment]]
PROC frag(v int!) BEGIN
  select v val;
END;

PROC use_frag_locals() BEGIN
  let v := nullable(1);
  if v is not null then
    with
      (call frag(from locals))
    select * from frag;
  end if;
END;

PROC use_frag_arguments(v integer) BEGIN
  if v is not null then
    with
      (call frag(from arguments))
    select * from frag;
  end if;
END;

-- proc call a virtual table
PROC call_virtual_table()
BEGIN
  select
    one.id,
    one.t,
    one.b,
    one.r,
    two.id as id_,
    two.t as t_,
    two.b as b_,
    two.r as r_
  from
    select_virtual_table("abc") one,
    select_virtual_table("dec") two;
END;

[[backing_table]]
create table backing(
  k blob primary key,
  v blob not null
);

[[backed_by=backing]]
create table backed(
  id integer primary key,
  name text
);

-- blob access stubs, it doesn't matter what they return, they aren't
-- semantically checked, but we do want them in the UDF output

[[deterministic]]
select function bgetkey_type(x blob not null) long not null;

[[deterministic]]
select function bgetval_type(x blob not null) long not null;

[[deterministic]]
select function bgetkey no check blob;

[[deterministic]]
select function bgetval no check blob;

[[deterministic]]
select function bcreatekey no check blob;

[[deterministic]]
select function bcreateval no check blob;

[[deterministic]]
select function bupdatekey no check blob;

[[deterministic]]
select function bupdateval no check blob;

create index backing_index on backing(bgetkey_type(k));

-- proc to read from a backed table
proc read_from_backed_table()
begin
  select * from backed where name = 'x';
end;

-- proc to test various constant types and ensure they convert correctly
proc constant_types()
begin
  let l1 := 1L;
  let long_to_int_cast := (select cast(l1 as int));
  let r1 := 1.0;
  let real_to_int_cast := (select cast(r1 as int));
  let i1 := 1;
  let int_to_real_cast := (select cast(i1 as real));
  let b1 := true;
  let bool_to_int_cast := (select cast(b1 as int));
end;

[[shared_fragment]]
proc notnull_int_frag(v int!) BEGIN
  select v val;
end;

proc use_inferred_notnull()
begin
  declare v integer;
  set v := 1; -- v is now not null, inferred
  select * from (call notnull_int_frag(v));
end;

func foo() int not null;
select function stuff() int not null;

proc a_proc(out v int not null)
begin
  set v := foo();
end;

proc use_frag_with_native_args()
begin
  select stuff() x, notnull_int_frag(1) y, T1.* from (call notnull_int_frag(foo() + a_proc())) T1;
end;

func external_blob_func() blob;

[[shared_fragment]]
proc simple_blob_fragment(x blob)
begin
  select 1 xx;
end;

-- + LET query_plan_trivial_object := trivial_object();
-- + LET query_plan_trivial_blob := trivial_blob();
-- + LET stmt := "SELECT %\\n  FROM (CALL simple_blob_fragment(nullable(trivial_blob())))";
proc blob_frag_user()
BEGIN
  select * from (call simple_blob_fragment(external_blob_func()));
END;

func external_object_func() object;

[[shared_fragment]]
proc simple_object_fragment(x object)
begin
  select 1 xx;
end;

-- + LET stmt := "SELECT %\\n  FROM (CALL simple_object_fragment(nullable(trivial_object())))";
proc object_frag_user()
BEGIN
  select * from (call simple_object_fragment(external_object_func()));
END;

-- + select foo as inner_a
[[shared_fragment]]
proc qp_take_inner_blob(foo blob) begin
  select foo inner_a;
end;

-- + (CALL qp_take_inner_blob(LOCALS.foo))
[[shared_fragment]]
proc qp_take_blob(foo blob) begin
  with (call qp_take_inner_blob(*))
  select * from qp_take_inner_blob;
end;

proc qp_use_frag(foo blob) begin
  with (call qp_take_blob(*))
  select * from qp_take_blob;
end;

proc qp_use_frag2(foo blob) begin
  with (call qp_take_inner_blob(*))
  select * from qp_take_inner_blob;
end;

proc qp_use_no_frag(foo blob) begin
  select foo foo;
end;

func my_object_func() object;

[[shared_fragment]]
proc object_frag(o object)
begin
  select 1 x;
end;

[[shared_fragment]]
proc outer_frag()
begin
  select * from (call object_frag(my_object_func()));
end;

proc do_something()
begin
  select * from (call outer_frag());
end;

-- Use this special syntax to test edge case in --format_table_alias_for_eqp
proc use_table_star_in_query()
begin
  select alias.* from `table one` as alias;
end;

-- Use this special syntax to test edge case in --format_table_alias_for_eqp
proc use_rowid_column_in_query()
begin
  select alias.rowid from `table one` as alias;
end;

proc use_view_with_table_alias_in_query()
begin
  select view.* from my_view_using_table_alias as view;
end;
