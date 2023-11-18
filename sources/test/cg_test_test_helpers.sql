/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- test helpers generation tests
create table `table a`
(
  `a pk` real not null primary key
);

create table Baa
(
  id int not null,
  `id 2` long int,
  `id 3` text
);

create unique index `Baa id index` on Baa(id, `id 2`);

create unique index baa_id_deleted on Baa(id, `id 2`) @delete(1);

create table dbl_table (
  num real,
  label text,
  tag text,
  constraint unq unique (num, label)
);

create table `table C`
(
  id int not null,
  `a pk` real not null,
  uid real,
  name text,
  name2 text,
  num long int,
  FOREIGN KEY (id, num) REFERENCES Baa(id, `id 2`) ON UPDATE NO ACTION,
  FOREIGN KEY (`a pk`) REFERENCES `table a`(`a pk`) ON UPDATE NO ACTION,
  FOREIGN KEY (uid, name) REFERENCES dbl_table(num, label) ON UPDATE NO ACTION
);

create table primary_as_column
(
  id_ text not null,
  seat text,
  lable text,
  primary key (id_, seat)
);

create table self_ref_table
(
  id integer primary key,
  `id 2` integer @sensitive, -- @sensitive forces attrs to be examined
  name text,
  foreign key (`id 2`) references self_ref_table(id)
);

create table self_ref_table2
(
  id integer primary key,
  `id 2` integer references self_ref_table2(id),
  name text
);

create view `Foo View` AS select * from `table C`;

create view Complex_view AS select * from `table C` where name in (select id_ from primary_as_column);

declare proc decl1(id integer) ( A integer not null, B bool );

create index p_id on primary_as_column(id_);

create index p_id_delete on primary_as_column(id_) @delete(1);

@attribute(cql:deterministic)
declare select function is_declare_func_enabled() bool not null;

create trigger `trigger on table a`
  before delete on `table a` when is_declare_func_enabled()
begin
  delete from dbl_table where num = OLD.`a pk`;
end;

create trigger trigger_deleted
  before delete on `table a` when is_declare_func_enabled()
begin
  delete from dbl_table where num = OLD.`a pk`;
end @delete(2);

create table experiment_value
(
  config text not null,
  param text not null,
  @attribute(non_privacy_sensitive)
  value text,
  type long int not null,
  @attribute(non_privacy_sensitive)
  logging_id text,
  primary key (config, param)
);

create table T4
(
  id int primary key
);

create table T1
(
  id int
);

create table T2
(
  id int
);

create table T3
(
  id int,
  foreign key (id) references T4(id) on update no action
);

create table t5(
  id long int primary key autoincrement,
  data text
);

create table t6(
  id long int primary key,
  foreign key (id) references t5 (id) on update cascade on delete cascade
);

create trigger `Trigger 1`
    before delete on T1
begin
  delete from T2 where id = OLD.id;
end;

create trigger R1_deleted
    before delete on T1
begin
  delete from T2 where id = OLD.id;
end @delete(3);

create trigger R2
    before delete on T2
begin
  delete from T3 where id = OLD.id;
end;

create trigger R2_deleted
    before delete on T2
begin
  delete from T3 where id = OLD.id;
end @delete(1);

create virtual table basic_virtual using module_name(this, that, the_other) as (
  id integer,
  t text
);

create table blob_primary_key (
  id blob primary key,
  name text
);

create table child_blob_primary_key (
  id blob primary key,
  name text,
  foreign key (id) references blob_primary_key(id) on update no action
);

-- TEST: dummy_table only
-- + DECLARE PROC sample_proc1 () (id INTEGER NOT NULL, `a pk` REAL NOT NULL, uid REAL, name TEXT, name2 TEXT, num LONG_INT);
-- + CREATE TEMP TABLE test_sample_proc1(LIKE sample_proc1);
-- + DROP TABLE test_sample_proc1;
@attribute(cql:autotest=(dummy_table))
create proc sample_proc1()
begin
  select * from `Foo View`;
end;

-- TEST: dummy_insert only
-- + DECLARE PROC sample_proc2 () (id INTEGER NOT NULL, `a pk` REAL NOT NULL, uid REAL, name TEXT, name2 TEXT, num LONG_INT);
-- + INSERT INTO test_sample_proc2 FROM ARGUMENTS;
@attribute(cql:autotest=(dummy_table, dummy_insert))
create proc sample_proc2()
begin
  select * from `Foo View`;
end;

-- TEST: dummy_select only
-- + DECLARE PROC sample_proc3 () (id INTEGER NOT NULL, `a pk` REAL NOT NULL, uid REAL, name TEXT, name2 TEXT, num LONG_INT);
-- + SELECT * FROM test_sample_proc3;
@attribute(cql:autotest=(dummy_table, dummy_select))
create proc sample_proc3()
begin
  select * from `Foo View`;
end;

-- TEST: dummy_table and dummy_insert only
-- + DECLARE PROC sample_proc4 () (id INTEGER NOT NULL);
-- + CREATE TEMP TABLE test_sample_proc4(LIKE sample_proc4);
-- + DROP TABLE test_sample_proc4;
-- + INSERT INTO test_sample_proc4 FROM ARGUMENTS;
@attribute(cql:autotest=(dummy_table, dummy_insert))
create proc sample_proc4()
begin
  select id from `Foo View`;
end;

-- TEST: dummy_table and dummy_insert only
-- + DECLARE PROC sample_proc5 () (id INTEGER NOT NULL);
-- + CREATE TEMP TABLE test_sample_proc5(LIKE sample_proc5);
-- + DROP TABLE test_sample_proc5;
-- + SELECT * FROM test_sample_proc5;
@attribute(cql:autotest=(dummy_table, dummy_select))
create proc sample_proc5()
begin
  select id from `Foo View`;
end;

-- TEST: dummy_select and dummy_insert only
-- + DECLARE PROC sample_proc6 () (id INTEGER NOT NULL);
-- + SELECT * FROM test_sample_proc6;
-- + INSERT INTO test_sample_proc6 FROM ARGUMENTS;
@attribute(cql:autotest=(dummy_table, dummy_select, dummy_insert))
create proc sample_proc6()
begin
  select id from `Foo View`;
end;

-- TEST: dummy_table, dummy_select, dummy_insert, dummy_test
-- + DECLARE PROC sample_proc7 () (id INTEGER NOT NULL);
-- + CREATE TEMP TABLE test_sample_proc7(LIKE sample_proc7);
-- + DROP TABLE test_sample_proc7;
-- + INSERT INTO test_sample_proc7 FROM ARGUMENTS;
-- + SELECT * FROM test_sample_proc7;
-- + CREATE PROC test_sample_proc7_create_tables()
-- + CREATE PROC test_sample_proc7_populate_tables()
-- + CREATE PROC test_sample_proc7_drop_tables()
-- + CREATE PROC test_sample_proc7_read_Baa()
-- + CREATE PROC test_sample_proc7_read_X_tableX20C()
-- + CREATE PROC test_sample_proc7_read_X_FooX20View()
-- + CREATE PROC test_sample_proc7_drop_indexes()
@attribute(cql:autotest=(dummy_table, dummy_insert, dummy_select, dummy_test))
create proc sample_proc7()
begin
  select id from `Foo View`;
end;

-- TEST: Proc has fetch_result instead of result_set
-- + SELECT * FROM test_sample_proc11;
@attribute(cql:autotest=(dummy_table, dummy_select))
create proc sample_proc11()
begin
  DECLARE curs CURSOR FOR SELECT id FROM `FOO VIEW`;
  FETCH curs;
  OUT curs;
end;

-- TEST: Proc has dummy_result_set attribute
-- + DECLARE PROC sample_proc12 () OUT (id INTEGER NOT NULL) USING TRANSACTION;
-- + CREATE PROC generate_sample_proc12_row(LIKE sample_proc12)
-- + DECLARE curs CURSOR LIKE sample_proc12
@attribute(cql:autotest=(dummy_result_set))
create proc sample_proc12()
begin
  DECLARE curs CURSOR FOR SELECT id FROM `FOO VIEW`;
  FETCH curs;
  OUT curs;
end;

-- TEST: Proc that generates table/insert/select/result_set/dummy_test
-- + DECLARE PROC sample_proc13 () OUT (id INTEGER NOT NULL) USING TRANSACTION;
-- + DECLARE SELECT FUNC is_declare_func_enabled () BOOL NOT NULL;
-- + CREATE PROC test_sample_proc13_create_tables()
-- + CREATE PROC test_sample_proc13_populate_tables()
-- + CREATE PROC test_sample_proc13_drop_tables()
--
-- + CREATE PROC test_sample_proc13_read_Baa()
-- + CREATE PROC test_sample_proc13_read_X_tableX20a()
-- + CREATE PROC test_sample_proc13_read_dbl_table()
-- + CREATE PROC test_sample_proc13_read_X_tableX20C()
-- + CREATE PROC test_sample_proc13_read_X_FooX20View()
--
-- + CREATE PROC test_sample_proc13_drop_indexes()
--
-- + CREATE PROC open_sample_proc13()
-- + CREATE TEMP TABLE test_sample_proc13(LIKE sample_proc13);
--
-- + CREATE PROC close_sample_proc13()
-- + DROP TABLE test_sample_proc13;
--
-- + CREATE PROC insert_sample_proc13(LIKE sample_proc13)
-- + INSERT INTO test_sample_proc13 FROM ARGUMENTS;
--
-- + CREATE PROC select_sample_proc13()
-- + SELECT * FROM test_sample_proc13;
--
-- + CREATE PROC generate_sample_proc13_row(LIKE sample_proc13)
-- + DECLARE curs CURSOR LIKE sample_proc13
@attribute(cql:autotest=(dummy_test, dummy_table, dummy_insert, dummy_select, dummy_result_set))
create proc sample_proc13()
begin
  DECLARE curs CURSOR FOR SELECT id FROM `FOO VIEW`;
  FETCH curs;
  OUT curs;
end;

-- TEST: dummy_test only
-- + CREATE PROC test_sample_proc14_create_tables()
-- + CREATE PROC test_sample_proc14_populate_tables()
-- + CREATE PROC test_sample_proc14_read_Baa()
-- + CREATE PROC test_sample_proc14_read_X_tableX20C()
-- + CREATE PROC test_sample_proc14_read_X_FooX20View()
-- + CREATE PROC test_sample_proc14_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc14()
begin
  select * from `Foo View`;
end;

-- TEST: test dummy_test with primary key as column in the table "primary_as_column"
-- + CREATE PROC test_sample_proc15_create_tables()
-- + CREATE PROC test_sample_proc15_populate_tables()
-- + CREATE PROC test_sample_proc15_read_primary_as_column()
-- + CREATE PROC test_sample_proc15_read_X_FooX20View()
-- + CREATE PROC test_sample_proc15_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc15()
begin
  select * from primary_as_column left join `foo view`;
end;

-- TEST: test dummy_test with insert statement
-- + CREATE PROC test_sample_proc16_create_tables()
-- + CREATE PROC test_sample_proc16_populate_tables()
-- + CREATE PROC test_sample_proc16_read_Baa()
-- + CREATE PROC test_sample_proc16_read_dbl_table()
-- + CREATE PROC test_sample_proc16_read_X_tableX20C()
-- + CREATE PROC test_sample_proc16_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc16()
begin
  insert into `table C`(id, `a pk`, name) values (1, 1.1, 'val');
end;

-- TEST: test dummy_test with drop,delete table statement
-- + CREATE PROC test_sample_proc17_create_tables()
-- + CREATE PROC test_sample_proc17_populate_tables()
-- + CREATE PROC test_sample_proc17_read_Baa()
-- + CREATE PROC test_sample_proc17_read_X_tableX20C()
-- + CREATE PROC test_sample_proc17_read_primary_as_column()
-- + CREATE PROC test_sample_proc17_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc17()
begin
  drop table `table C`;
  drop view `Foo View`;
  delete from primary_as_column where id_ = '1';
end;

-- TEST: test dummy_test with create view statement
-- + CREATE PROC test_sample_proc18_create_tables()
-- + CREATE PROC test_sample_proc18_populate_tables()
-- + CREATE PROC test_sample_proc18_drop_tables()
-- + CREATE PROC test_sample_proc18_read_Baa()
-- + CREATE PROC test_sample_proc18_read_X_tableX20C()
-- + CREATE PROC test_sample_proc18_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc18()
begin
  create view zaa AS select * from `table C`;
end;

-- TEST: test dummy_test with create table statement with the foreign key table (Baa) to generate
-- + CREATE PROC test_sample_proc19_create_tables()
-- + CREATE PROC test_sample_proc19_populate_tables()
-- + CREATE PROC test_sample_proc19_read_Baa()
-- + CREATE PROC test_sample_proc19_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc19()
begin
create table t (
  id int not null primary key,
  num long int,
  FOREIGN KEY (id, num) REFERENCES Baa(id, `id 2`) ON UPDATE NO ACTION
);
end;

-- TEST: test dummy_test with update statement
-- + CREATE PROC test_sample_proc20_create_tables()
-- + CREATE PROC test_sample_proc20_populate_tables()
-- + CREATE PROC test_sample_proc20_read_Baa()
-- + CREATE PROC test_sample_proc20_read_X_tableX20a()
-- + CREATE PROC test_sample_proc20_read_dbl_table()
-- + CREATE PROC test_sample_proc20_read_X_tableX20C()
-- + CREATE PROC test_sample_proc20_drop_indexes()
@attribute(cql:autotest=(dummy_test))
create proc sample_proc20()
begin
  update `table C` set id = 1;
end;

-- TEST: test dummy_test with create view statement contains multiple tables
-- + CREATE PROC test_sample_proc21_create_tables()
-- + CREATE TABLE IF NOT EXISTS Baa
-- + CREATE UNIQUE INDEX IF NOT EXISTS `Baa id index` ON Baa (id, `id 2`);
-- + CREATE TABLE IF NOT EXISTS `table a`(
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE TABLE IF NOT EXISTS `table C`
-- + CREATE TABLE IF NOT EXISTS primary_as_column
-- + CREATE INDEX IF NOT EXISTS p_id ON primary_as_column (id_);
-- + CREATE VIEW IF NOT EXISTS Complex_view
-- + 
-- + CREATE PROC test_sample_proc21_populate_tables()
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(111, 1)
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(333, 2)
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(444, 3)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(1)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(2)
-- + INSERT OR IGNORE INTO dbl_table(label, num) VALUES('Nelly', 1)
-- + INSERT OR IGNORE INTO dbl_table(label, num) VALUES('Babeth', 2)
-- + INSERT OR IGNORE INTO `table C`(id, name, `a pk`, uid, num) VALUES(333, 'Nelly', 1, 1, 1)
-- + INSERT OR IGNORE INTO `table C`(id, name, `a pk`, uid, num) VALUES(444, 'Babeth', 2, 2, 2)
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('1', '1')
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('2', '2')
--
-- + CREATE PROC test_sample_proc21_drop_tables()
-- + DROP VIEW IF EXISTS Complex_view;
-- + DROP TABLE IF EXISTS primary_as_column;
-- + DROP TABLE IF EXISTS `table C`;
-- + DROP TABLE IF EXISTS dbl_table;
-- + DROP TABLE IF EXISTS `table a`;
-- + DROP TABLE IF EXISTS Baa;
--
-- + CREATE PROC test_sample_proc21_read_Baa()
-- + CREATE PROC test_sample_proc21_read_X_tableX20a()
-- + CREATE PROC test_sample_proc21_read_dbl_table()
-- + CREATE PROC test_sample_proc21_read_X_tableX20C()
-- + SELECT * FROM `table C`;
-- + CREATE PROC test_sample_proc21_read_primary_as_column()
-- + CREATE PROC test_sample_proc21_read_Complex_view()
--
-- + CREATE PROC test_sample_proc21_drop_indexes()
-- + DROP INDEX IF EXISTS `Baa id index`;
-- + DROP INDEX IF EXISTS p_id;
@attribute(cql:autotest=((dummy_test, (Baa, (id), (111), (333)), (`table C`, (name, id), ('Nelly', 333), ('Babeth', 444))), dummy_table))
create proc sample_proc21()
begin
  select * from Complex_view;
end;

-- TEST: test dummy_test with fk column value populated to fk table
-- + CREATE PROC test_sample_proc22_create_tables()
-- + CREATE TABLE IF NOT EXISTS Baa
-- + CREATE UNIQUE INDEX IF NOT EXISTS `Baa id index` ON Baa (id, `id 2`);
-- + CREATE TABLE IF NOT EXISTS `table a`(
-- + CREATE TABLE IF NOT EXISTS dbl_table(
-- + CREATE TABLE IF NOT EXISTS `table C`
-- + CREATE TABLE IF NOT EXISTS primary_as_column
-- + CREATE INDEX IF NOT EXISTS p_id ON primary_as_column (id_);
-- + CREATE VIEW IF NOT EXISTS Complex_view
-- + CREATE PROC test_sample_proc22_populate_tables()
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(111, 1)
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(222, 2)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(1)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(2)
-- + INSERT OR IGNORE INTO dbl_table(label, num) VALUES('Nelly', 1)
-- + INSERT OR IGNORE INTO dbl_table(label, num) VALUES('Babeth', 2)
-- + INSERT OR IGNORE INTO `table C`(id, name, `a pk`, uid, num) VALUES(111, 'Nelly', 1, 1, 1)
-- + INSERT OR IGNORE INTO `table C`(id, name, `a pk`, uid, num) VALUES(222, 'Babeth', 2, 2, 2)
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('1', '1')
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('2', '2')
-- + CREATE PROC test_sample_proc22_drop_tables()
-- + DROP VIEW IF EXISTS Complex_view;
-- + DROP TABLE IF EXISTS primary_as_column;
-- + DROP TABLE IF EXISTS `table C`;
-- + DROP TABLE IF EXISTS dbl_table;
-- + DROP TABLE IF EXISTS `table a`;
-- + DROP TABLE IF EXISTS Baa;
-- + CREATE PROC test_sample_proc22_read_Baa()
-- + CREATE PROC test_sample_proc22_read_X_tableX20a()
-- + SELECT * FROM `table a`;
-- + CREATE PROC test_sample_proc22_read_dbl_table()
-- + CREATE PROC test_sample_proc22_read_X_tableX20C()
-- + SELECT * FROM `table C`;
-- + CREATE PROC test_sample_proc22_read_primary_as_column()
-- + CREATE PROC test_sample_proc22_read_Complex_view()
-- + CREATE PROC test_sample_proc22_drop_indexes()
-- + DROP INDEX IF EXISTS `Baa id index`;
-- + DROP INDEX IF EXISTS p_id;
@attribute(cql:autotest=((dummy_test, (`table C`, (name, id), ('Nelly', 111), ('Babeth', 222))), dummy_table))
create proc sample_proc22()
begin
  select * from Complex_view;
end;

-- TEST: test dummy_test with no explicit value on a complex view
-- + CREATE PROC test_sample_proc23_create_tables()
-- + CREATE TABLE IF NOT EXISTS Baa
-- + CREATE UNIQUE INDEX IF NOT EXISTS `Baa id index` ON Baa (id, `id 2`);
-- + CREATE TABLE IF NOT EXISTS `table a`(
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE TABLE IF NOT EXISTS `table C`
-- + CREATE TABLE IF NOT EXISTS primary_as_column
-- + CREATE INDEX IF NOT EXISTS p_id ON primary_as_column (id_);
-- + CREATE VIEW IF NOT EXISTS Complex_view
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(1, 1)
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(2, 2)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(1)
-- + INSERT OR IGNORE INTO `table a`(`a pk`) VALUES(2)
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(1, '1')
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(2, '2')
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(1, 1, 1, '1', 1)
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(2, 2, 2, '2', 2)
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('1', '1')
-- + INSERT OR IGNORE INTO primary_as_column(id_, seat) VALUES('2', '2')
-- + CREATE PROC test_sample_proc23_drop_indexes()
-- + DROP INDEX IF EXISTS `Baa id index`;
-- + DROP INDEX IF EXISTS p_id;
@attribute(cql:autotest=(dummy_test))
create proc sample_proc23()
begin
  select * from Complex_view;
end;

-- TEST: test dummy_test with fk column value populated to fk table
-- + CREATE PROC test_sample_proc24_create_tables()
-- + CREATE TABLE IF NOT EXISTS Baa
-- + CREATE UNIQUE INDEX IF NOT EXISTS `Baa id index` ON Baa (id, `id 2`);
-- + CREATE TABLE IF NOT EXISTS `table a`
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE TABLE IF NOT EXISTS `table C`
-- + CREATE PROC test_sample_proc24_populate_tables()
-- + INSERT OR IGNORE INTO dbl_table(label, num) VALUES('Chris', 777.0)
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(2, '2')
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(1, 1, 777.0, 'Chris', 1)
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(2, 2, 777.0, 'Chris', 2)
-- + CREATE PROC test_sample_proc24_drop_tables()
-- + CREATE PROC test_sample_proc24_drop_indexes()
-- + DROP INDEX IF EXISTS `Baa id index`;
@attribute(cql:autotest=((dummy_test, (dbl_table, (num, label), (777.0, 'Chris'))), dummy_table))
create proc sample_proc24()
begin
  select * from `table C`;
end;

-- TEST: test dummy_test with fk column value populated to fk table that already has the value
-- + CREATE UNIQUE INDEX IF NOT EXISTS `Baa id index` ON Baa (id, `id 2`);
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(777.0, '1')
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(2, '2')
-- + INSERT OR IGNORE INTO `table C`(uid, id, `a pk`, name, num) VALUES(777.0, 1, 1, '1', 1)
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(2, 2, 777.0, '2', 2)
-- + CREATE PROC test_sample_proc25_drop_indexes()
-- + DROP INDEX IF EXISTS `Baa id index`;
@attribute(cql:autotest=((dummy_test, (dbl_table, (num), (777.0)), (`table C`, (uid), (777.0))), dummy_table))
create proc sample_proc25()
begin
  select * from `table C`;
end;

-- TEST: test dummy_test with unique column
-- + CREATE PROC test_sample_proc26_create_tables()
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE PROC test_sample_proc26_populate_tables()
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(-0.1, '1')
-- + INSERT OR IGNORE INTO dbl_table(num, label) VALUES(2, '2')
-- + CREATE PROC test_sample_proc26_drop_tables()
-- + DROP TABLE IF EXISTS dbl_table;
-- + CREATE PROC test_sample_proc26_read_dbl_table()
-- + SELECT * FROM dbl_table
@attribute(cql:autotest=((dummy_test, (dbl_table, (num), (-0.1)))))
create proc sample_proc26()
begin
  select * from dbl_table;
end;

-- TEST: test dummy_test info duplicated
-- + CREATE PROC test_sample_proc27_create_tables()
-- + CREATE TABLE IF NOT EXISTS experiment_value
-- + CREATE PROC test_sample_proc27_populate_tables()
-- + INSERT OR IGNORE INTO experiment_value(config, logging_id, type, param, value) VALUES('rtc_overlayconfig_exampleconfig', '1234', 9223372036854775807, 'enabled', '0')
-- + INSERT OR IGNORE INTO experiment_value(config, logging_id, type, param, value) VALUES('rtc_overlayconfig_exampleconfig', '5678', 9223372036854775807, 'some_integer', '42')
-- + CREATE PROC test_sample_proc27_drop_tables()
-- + DROP TABLE IF EXISTS experiment_value;
-- + CREATE PROC test_sample_proc27_read_experiment_value()
-- + SELECT * FROM experiment_value
@attribute(cql:autotest=((dummy_test, (experiment_value, (config, param, value, type, logging_id), ('rtc_overlayconfig_exampleconfig', 'enabled', '0', 9223372036854775807, '1234'), ('rtc_overlayconfig_exampleconfig', 'some_integer', '42', 9223372036854775807, '5678')))))
CREATE PROCEDURE sample_proc27()
BEGIN
  @enforce_normal join;
  SELECT * FROM experiment_value;
END;

-- TEST: test dbl_table is processed in dummy_test because of `trigger on table a` on `table a`
-- + DECLARE SELECT FUNC is_declare_func_enabled () BOOL NOT NULL;
-- + CREATE PROC test_sample_proc28_create_tables()
-- + CREATE TABLE IF NOT EXISTS `table a`
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE PROC test_sample_proc28_create_triggers()
-- + CREATE TRIGGER IF NOT EXISTS `trigger on table a`
-- + CREATE PROC test_sample_proc28_populate_tables()
-- +2 INSERT OR IGNORE INTO `table a`
-- +2 INSERT OR IGNORE INTO dbl_table
-- + CREATE PROC test_sample_proc28_drop_tables()
-- + DROP TABLE IF EXISTS dbl_table;
-- + DROP TABLE IF EXISTS `table a`;
-- + CREATE PROC test_sample_proc28_drop_triggers()
-- + DROP TRIGGER IF EXISTS `trigger on table a`
-- + CREATE PROC test_sample_proc28_read_X_tableX20a()
-- + CREATE PROC test_sample_proc28_read_dbl_table()
@attribute(cql:autotest=(dummy_test))
CREATE PROCEDURE sample_proc28()
BEGIN
  select * from `table a`;
END;

-- TEST: test `table a` is not processed in dummy_test because the trigger`table a` is on `table a`
-- + CREATE PROC test_sample_proc29_create_tables()
-- - CREATE TABLE IF NOT EXISTS `table a`
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- _ CREATE PROC test_sample_proc29_create_triggers()
-- - CREATE TRIGGER `trigger on table a`
-- + CREATE PROC test_sample_proc29_populate_tables()
-- - INSERT OR IGNORE INTO `table a`
-- +2 INSERT OR IGNORE INTO dbl_table
-- + CREATE PROC test_sample_proc29_drop_tables()
-- - DROP TABLE IF EXISTS `table a`;
-- + DROP TABLE IF EXISTS dbl_table;
-- + CREATE PROC test_sample_proc29_drop_triggers()
-- - DROP TRIGGER IF EXISTS `trigger on table a`
-- + CREATE PROC test_sample_proc29_read_dbl_table()
@attribute(cql:autotest=(dummy_test))
CREATE PROCEDURE sample_proc29()
BEGIN
  select * from dbl_table;
END;

-- TEST: test dbl_table is processed in dummy_test because of trigger`table a` on `table a`
-- + DECLARE SELECT FUNC is_declare_func_enabled () BOOL NOT NULL;
-- + CREATE PROC test_sample_proc30_create_tables()
-- + CREATE TABLE IF NOT EXISTS `table a`
-- + CREATE TABLE IF NOT EXISTS dbl_table
-- + CREATE PROC test_sample_proc30_create_triggers()
-- + CREATE TRIGGER IF NOT EXISTS `trigger on table a`
-- + CREATE PROC test_sample_proc30_populate_tables()
-- +2 INSERT OR IGNORE INTO `table a`
-- +2 INSERT OR IGNORE INTO dbl_table
-- + CREATE PROC test_sample_proc30_drop_tables()
-- + DROP TABLE IF EXISTS dbl_table;
-- + DROP TABLE IF EXISTS `table a`;
-- + CREATE PROC test_sample_proc30_drop_triggers()
-- + DROP TRIGGER IF EXISTS `trigger on table a`
-- + CREATE PROC test_sample_proc30_read_X_tableX20a
-- + CREATE PROC test_sample_proc30_read_dbl_table()
@attribute(cql:autotest=(dummy_test))
CREATE PROCEDURE sample_proc30()
BEGIN
  create trigger `also on table a`
      before delete on `table a`
    begin
      delete from dbl_table where num = OLD.`a pk`;
    end;
END;

-- TEST: test T1, T2, T3 relationship base on triggers and T3, T4 base on foreign key
-- + CREATE PROC test_sample_proc31_create_tables()
-- + CREATE TABLE IF NOT EXISTS T1
-- + CREATE TABLE IF NOT EXISTS T2
-- + CREATE TABLE IF NOT EXISTS T4
-- + CREATE TABLE IF NOT EXISTS T3
-- + CREATE PROC test_sample_proc31_create_triggers()
-- + CREATE TRIGGER IF NOT EXISTS `Trigger 1`
-- + CREATE TRIGGER IF NOT EXISTS R2
-- + CREATE PROC test_sample_proc31_populate_tables()
-- +2 INSERT OR IGNORE INTO T1
-- +2 INSERT OR IGNORE INTO T2
-- +2 INSERT OR IGNORE INTO T3
-- +2 INSERT OR IGNORE INTO T4
-- + CREATE PROC test_sample_proc31_drop_tables()
-- + DROP TABLE IF EXISTS T3;
-- + DROP TABLE IF EXISTS T4;
-- + DROP TABLE IF EXISTS T2;
-- + DROP TABLE IF EXISTS T1;
-- + CREATE PROC test_sample_proc31_drop_triggers()
-- + DROP TRIGGER IF EXISTS `Trigger 1`
-- + DROP TRIGGER IF EXISTS R2
-- + CREATE PROC test_sample_proc31_read_T1()
-- + CREATE PROC test_sample_proc31_read_T2()
-- + CREATE PROC test_sample_proc31_read_T4()
-- + CREATE PROC test_sample_proc31_read_T3()
@attribute(cql:autotest=(dummy_test))
CREATE PROCEDURE sample_proc31()
BEGIN
  insert into T1 (id) values(1);
END;

-- TEST:
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(-99, 1)
-- + INSERT OR IGNORE INTO Baa(id, `id 2`) VALUES(-444, 2)
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(-444, 1, 1, '1', 1)
-- + INSERT OR IGNORE INTO `table C`(id, `a pk`, uid, name, num) VALUES(-444, 2, 2, '2', 2)
@attribute(cql:autotest=((dummy_test, (Baa, (id), (-99)), (`table C`, (id), (-444)))))
create proc sample_proc311()
begin
  select * from `table C`;
end;

-- TEST: test that column type of id in t5, t6 tables is not converted to integer.
-- +2 id LONG_INT PRIMARY KEY
@attribute(cql:autotest=(dummy_test))
create proc no_long_to_conversion()
begin
  select * from t6;
end;

-- TEST: test dummy_test with like statement, do no generate dummy_test because cursor dont query the table foo but just use its schema
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_test))
create proc sample_proc32()
begin
  declare curs cursor like `foo view`;
end;

-- TEST: test dummy_test with cursor like a proc, do not generate dummy_test because decl1 is not a table.
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_test))
create proc sample_proc33()
begin
  declare curs cursor like decl1;
end;

-- TEST: test dummy_test with create table statement, do not generate dummy_test because the proc already create the table in quest
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_test))
create proc sample_proc34()
begin
  create table tt (
    id int not null
  );
end;

-- TEST: Proc does query a Common Table Expressions (not a table), do not generate dummy_test
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_test))
create proc sample_proc35()
begin
  with cte(a,b) as (select 1,2)
  select * from cte;
end;

-- TEST: Proc does not query a table, do not generate dummy_test
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_test))
create proc sample_proc36()
begin
  select 1 as A, 2 as B;
end;

-- TEST: Unknown attribute "auto", do not generate dummy_test
-- - CREATE
-- - DECLARE
@attribute(cql:auto=(dummy_test))
create proc sample_proc37()
begin
  select 1 as A, 2 as B;
end;

-- TEST: Proc has no attributes, do not generate anything
-- - CREATE
-- - DECLARE
create proc sample_proc8()
begin
  select id from `Foo View`;
end;

-- TEST: Proc does not return a result set, do not generate anything
-- - CREATE
-- - DECLARE
@attribute(cql:autotest=(dummy_table))
create proc sample_proc9()
begin
  insert into `table C` values (1, 1.1, 10, "asdf", "Antonia", 0);
end;

-- TEST: self referencing table -- ensure null binds correctly
-- + INSERT OR IGNORE INTO self_ref_table(id, `id 2`) VALUES(1, NULL) @dummy_seed(123);
-- + INSERT OR IGNORE INTO self_ref_table(id, `id 2`) VALUES(2, 1) @dummy_seed(124) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=((dummy_test, (self_ref_table, (id, `id 2`), (1, null), (2, 1)))))
create proc self_ref_proc()
begin
  select * from self_ref_table;
end;

-- TEST: self referencing table -- no data specified
-- + INSERT OR IGNORE INTO self_ref_table(id, `id 2`) VALUES(1, 1) @dummy_seed(123);
-- + INSERT OR IGNORE INTO self_ref_table(id, `id 2`) VALUES(2, 2) @dummy_seed(124) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=((dummy_test)))
create proc self_ref_proc_no_data()
begin
  select * from self_ref_table;
end;

-- TEST: self referencing table -- using attribute -- ensure null binds correctly
-- + INSERT OR IGNORE INTO self_ref_table2(id, `id 2`) VALUES(1, NULL) @dummy_seed(123);
-- + INSERT OR IGNORE INTO self_ref_table2(id, `id 2`) VALUES(2, 1) @dummy_seed(124) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=((dummy_test, (self_ref_table2, (id, `id 2`), (1, null), (2, 1)))))
create proc self_ref_proc2()
begin
  select * from self_ref_table2;
end;

-- TEST: self referencing table -- using attribute --  no data specified
-- + INSERT OR IGNORE INTO self_ref_table2(id, `id 2`) VALUES(1, 1) @dummy_seed(123);
-- + INSERT OR IGNORE INTO self_ref_table2(id, `id 2`) VALUES(2, 2) @dummy_seed(124) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=((dummy_test)))
create proc self_ref_proc2_no_data()
begin
  select * from self_ref_table2;
end;

-- TEST:
create table test1(
  id int primary key
);
create table test2(
  name text,
  id int,
  foreign key (id) references test1(id)
);

-- TEST: test too many row in the child table compare to the parent table.
-- + INSERT OR IGNORE INTO test1(id) VALUES(1) @dummy_seed(123);
-- + INSERT OR IGNORE INTO test1(id) VALUES(2) @dummy_seed(124) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO test2(name, id) VALUES('name_1', 1) @dummy_seed(125);
-- + INSERT OR IGNORE INTO test2(name, id) VALUES('name_2', 2) @dummy_seed(126) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO test2(name, id) VALUES('name_3', 2) @dummy_seed(127);
-- + INSERT OR IGNORE INTO test2(name, id) VALUES('name_4', 1) @dummy_seed(128) @dummy_nullables @dummy_defaults;
@attribute(
  cql:autotest=(
    (dummy_test,
      (test2,
        (name),
        ('name_1'),
        ('name_2'),
        ('name_3'),
        ('name_4')
      )
    )
  )
)
create proc test_too_many_row_in_child_table()
begin
  select * from test2;
end;

-- TEST: test too many row in the child table compare to the parent table with foreign key defined.
-- + INSERT OR IGNORE INTO test1(id) VALUES(90) @dummy_seed(123);
-- + INSERT OR IGNORE INTO test1(id) VALUES(91) @dummy_seed(124) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO test1(id) VALUES(92) @dummy_seed(125);
-- + INSERT OR IGNORE INTO test1(id) VALUES(93) @dummy_seed(126) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO test2(id) VALUES(90) @dummy_seed(127);
-- + INSERT OR IGNORE INTO test2(id) VALUES(91) @dummy_seed(128) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO test2(id) VALUES(92) @dummy_seed(129);
-- + INSERT OR IGNORE INTO test2(id) VALUES(93) @dummy_seed(130) @dummy_nullables @dummy_defaults;
@attribute(
  cql:autotest=(
    (dummy_test,
      (test2,
        (id),
        (90),
        (91),
        (92),
        (93)
      )
    )
  )
)
create proc test_too_many_row_in_child_table_2()
begin
  select * from test2;
end;

-- TEST: test virtual table in dummy_test helper
-- + CREATE VIRTUAL TABLE IF NOT EXISTS basic_virtual USING module_name (this, that, the_other) AS (
-- +   id INTEGER,
-- +   t TEXT
-- + );
-- + CREATE PROC test_test_virtual_table_proc_drop_tables()
-- +   DROP TABLE IF EXISTS basic_virtual;
-- + CREATE PROC test_test_virtual_table_proc_read_basic_virtual()
-- +   SELECT * FROM basic_virtual;
@attribute(cql:autotest=(dummy_test))
create proc test_virtual_table_proc()
begin
  select * from basic_virtual;
end;

-- TEST: test blob primary key is emitted as blob
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(CAST('1' as blob)) @dummy_seed(123);
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(CAST('2' as blob)) @dummy_seed(124) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=(dummy_test))
create proc test_blob_primary_key()
begin
  select * from blob_primary_key;
end;

-- TEST: test parent and child blob primary key are emitted as blob
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(CAST('1' as blob)) @dummy_seed(123);
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(CAST('2' as blob)) @dummy_seed(124) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO child_blob_primary_key(id) VALUES(CAST('1' as blob)) @dummy_seed(125);
-- + INSERT OR IGNORE INTO child_blob_primary_key(id) VALUES(CAST('2' as blob)) @dummy_seed(126) @dummy_nullables @dummy_defaults;
@attribute(cql:autotest=(dummy_test))
create proc test_child_blob_primary_key()
begin
  select * from child_blob_primary_key;
end;

-- TEST: test blob value in dummy_test attribution
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(X'90') @dummy_seed(123);
-- + INSERT OR IGNORE INTO blob_primary_key(id) VALUES(X'91') @dummy_seed(124) @dummy_nullables @dummy_defaults;
-- + INSERT OR IGNORE INTO child_blob_primary_key(id) VALUES(X'90') @dummy_seed(125);
-- + INSERT OR IGNORE INTO child_blob_primary_key(id) VALUES(X'91') @dummy_seed(126) @dummy_nullables @dummy_defaults;
@attribute(
  cql:autotest=(
    (dummy_test,
      (blob_primary_key,
        (id),
        (X'90'),
        (X'91')
      )
    )
  )
)
create proc test_blob_literal_in_dummy_test()
begin
  select * from child_blob_primary_key;
end;


@attribute(cql:shared_fragment)
create proc simple_frag()
begin
  with source(*) like child_blob_primary_key
  select * from source;
end;

-- TEST: we need to make sure we recurse into the shared fragment
-- and consider the tables it contains
-- + CREATE TABLE IF NOT EXISTS blob_primary_key(
-- + CREATE TABLE IF NOT EXISTS child_blob_primary_key(
-- - dbl_table
@attribute(cql:autotest=((dummy_test)))
create proc test_frags()
begin
  declare C cursor like select * from dbl_table;
  with (call simple_frag() using child_blob_primary_key as source)
  select * from simple_frag;
end;

CREATE TABLE trig_test_t1(
  pk LONG_INT PRIMARY KEY
);

CREATE TABLE trig_test_t2(
  pk LONG_INT PRIMARY KEY,
  ak LONG_INT REFERENCES trig_test_t1 (pk)
);

CREATE TABLE trig_test_t3(
  pk LONG_INT PRIMARY KEY,
  ak LONG_INT REFERENCES trig_test_t2 (pk)
);

CREATE TABLE trig_test_t4(
  pk LONG_INT PRIMARY KEY,
  ak LONG_INT REFERENCES trig_test_t2 (pk)
);

CREATE TABLE IF NOT EXISTS trig_test_tx(
  ak LONG_INT PRIMARY KEY
);

CREATE TRIGGER IF NOT EXISTS trig
  AFTER INSERT ON trig_test_t1
BEGIN
  INSERT OR IGNORE INTO trig_test_tx(ak) SELECT pk
    FROM trig_test_t3;
END;

-- TEST: we verify that the trigger is not going to mess things up order-wise
-- it should be walked after all else so even though it gives a shorter path
-- to trig_test_t3 it is still ok, we will generate trig_test_t3 after _t2
-- note that validation here only checks for well formed output.  The real
-- validation comes from the fact that we compile the generated code so
-- any invalid order will cause the compilation to fail in the test.  That is
-- providing real order validation here.
-- + CREATE PROC test_MyProc_create_tables()
-- + BEGIN
-- + CREATE TABLE IF NOT EXISTS trig_test_t1
-- + CREATE TABLE IF NOT EXISTS trig_test_t2
-- + CREATE TABLE IF NOT EXISTS trig_test_t4
-- + CREATE TABLE IF NOT EXISTS trig_test_tx
-- + CREATE TABLE IF NOT EXISTS trig_test_t3
-- + END
-- + CREATE PROC test_MyProc_create_triggers()
-- + BEGIN
-- + CREATE TRIGGER IF NOT EXISTS trig
-- + END
@ATTRIBUTE(cql:autotest=(dummy_test))
CREATE PROC MyProc ()
BEGIN
  SELECT 1 AS dummy
    FROM trig_test_t4;
END;

@attribute(cql:backing_table)
create table backing(
  k blob primary key,
  v blob
);

create index backing_type_index on backing(cql_blob_get_type(k));

@attribute(cql:backed_by=backing)
create table backed(
  pk int primary key,
  x text,
  y real
);

-- TEST: backed tables
-- backed tables are not created, only declared
-- backing tables do not get inserts, we insert into backed tables
-- backed/backing tables should have attributes
--
-- + @attribute(cql:backing_table)
-- + CREATE TABLE IF NOT EXISTS backing(
-- + CREATE INDEX IF NOT EXISTS backing_type_index ON backing (cql_blob_get_type(k));
--
-- + @attribute(cql:backed_by=backing)
-- + CREATE TABLE IF NOT EXISTS backed(
-- + INSERT OR IGNORE INTO backed(pk) VALUES(1) @dummy_seed(123);
-- + INSERT OR IGNORE INTO backed(pk) VALUES(2) @dummy_seed(124) @dummy_nullables @dummy_defaults;
-- + DROP TABLE IF EXISTS backing;
-- + DROP INDEX IF EXISTS backing_type_index;
--
-- - DROP TABLE IF EXISTS backed;
-- - INSERT OR IGNORE INTO backing
@attribute(cql:autotest=(dummy_test))
create proc uses_backed_table()
begin
  select * from backed;
end;

