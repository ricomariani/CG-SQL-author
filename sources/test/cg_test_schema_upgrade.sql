/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- schema migration generation tests

@declare_schema_region shared;
@declare_schema_region extra using shared;
@declare_schema_region other;

@begin_schema_region shared;

create table `quoted foo`(
  `an id` integer primary key,
  rate long integer @delete(5),
  `rate 2` long integer @delete(4, DeleteRate2Proc),
  `id 2` integer default 12345 @create(4, CreateId2Proc),
  name text @create(5),
  name_2 text @create(6)
);

create table added_table(
  `an id` integer not null,
  name1 text,
  name2 text @create(4)
) @create(3) @delete(5);

-- this view will be declared in extra schema but not upgraded
create view shared_view as select * from `quoted foo`;

-- this index will be declared in extra schema but not upgraded
create index shared_index on `quoted foo`(name, name_2);

-- this trigger will be declared in extra schema but not upgraded
create trigger shared_trigger
  before insert on `quoted foo`
begin
  select 1;
end;

-- this view is present in the output
create view live_view as select * from `quoted foo`;

-- this view is not present in the output
create view dead_view as select * from `quoted foo` @delete(2, DeadViewMigration);

-- make a recreate-group with an FK dependency (legal)
create table g1(
  `an id` integer primary key,
  name text
) @recreate(gr1);

create table `use g1`(
  `an id` integer primary key references g1(`an id`),
  name2 text
) @recreate(gr1);

[[deterministic]]
select func my_func(x text) text;

create index gr1_index on g1(name);
create index gr1_index2 on g1(name, `an id`);
create index gr1_index3 on g1(my_func(name), `an id`) @delete(5);

@end_schema_region;

@begin_schema_region extra;

-- this table will be declared in the extra schema upgrade and upgraded
create table table2(
  `an id` integer not null references `quoted foo`(`an id`),
  name1 text @create(2, CreateName1Proc),
  name2 text @create(2, CreateName2Proc),
  name3 text @create(2), -- no proc
  name4 text @create(2) -- no proc
);

-- this view will be declared and upgraded in extra schema
create view another_live_view as select * from table2;

-- this index will be declared and upgraded in extra schema
create index not_shared_present_index on table2(name1, name2);

-- this index is going away
create index index_going_away on table2(name3) @delete(3);

-- this trigger will be declared and upgraded in extra schema
create trigger not_shared_trigger
  before insert on `quoted foo`
begin
  select new.`an id`;
end;

@end_schema_region;

@begin_schema_region other;

create table other_table(`an id` integer);

@end_schema_region;

-- this table is on the recreate plan
create table table_to_recreate(
  `an id` integer not null,
  name text
) @recreate;

-- these tables are in a recreate group
create table grouped_table_1( `an id` integer not null, name text ) @recreate(my_group);
create table grouped_table_2( `an id` integer not null, name text ) @recreate(my_group);
create table grouped_table_3( `an id` integer not null, name text ) @recreate(my_group);

-- temp tables go into the temp table section
create temp table this_table_appears_in_temp_section(
 temp_section_integer integer
);

-- temp views go into the temp section
create temp view temp_view_in_temp_section as select * from `quoted foo`;

@begin_schema_region shared;

-- temp triggers go into the temp section
create temp trigger temp_trigger_in_temp_section
  before delete on `quoted foo`
  for each row
  when old.`an id` > 7
begin
  select old.`an id`;
end;

-- an actual trigger, this will be managed using recreate rules
create trigger insert_trigger
  before insert on `quoted foo`
  for each row
  when new.`an id` > 7
begin
  select new.`an id`;
end;

-- this trigger was retired
create trigger old_trigger_was_deleted
  before insert on `quoted foo`
begin
  select new.`an id`;
end @delete(3);

-- do an ad hoc migration at version 5 (inside the region)
@schema_ad_hoc_migration(5, MyAdHocMigrationScript);

-- do an ad hoc migration for recreation
@schema_ad_hoc_migration for @recreate(gr1, RecreateGroup1Migration);

@end_schema_region;

-- declare a select function that we will use
select func filter_(id integer) integer not null;

-- now use that function in a trigger
create trigger trig_with_filter
  before insert on `quoted foo`
  when filter_(new.`an id`) = 3
begin
  delete from `quoted foo` where `an id` = 77;
end;

-- test that column type of `an id` in t5, t6 tables is not converted to integer.
create table t5(
  `an id` long int primary key autoincrement,
  data text
);

create table t6(
  `an id` long int primary key,
  foreign key (`an id`) references t5 (`an id`) on update cascade on delete cascade
);

create virtual table a_virtual_table using a_module ( this, that, the_other )
as (
  `an id` integer @sensitive,
  t text
);

create virtual table @eponymous epon using epon
as (
  `an id` integer @sensitive,
  t text
);

create virtual table complex_virtual_table using a_module(arguments following)
as (
  `an id` integer @sensitive,
  t text
);

create virtual table deleted_virtual_table using a_module(arguments following)
as (
  `an id` integer @sensitive,
  t text
) @delete(4, cql:module_must_not_be_deleted_see_docs_for_CQL0392);

create table `migrated from recreate`(
  `an id` integer primary key,
  t text
) @create(4, cql:from_recreate);

create index recreate_index_needs_deleting on `migrated from recreate`(t);
create index recreate_index_needs_deleting2 on `migrated from recreate`(t);

create table migrated_from_recreate2(
  `an id` integer primary key references `migrated from recreate`(`an id`),
  t text
) @create(4, cql:from_recreate);

create index recreate_index_needs_deleting3 on migrated_from_recreate2(t);

create table conflict_clause_t(`an id` int not null on conflict fail);

create table conflict_clause_pk(
  `an id` int not null,
  constraint `pk 1` primary key (`an id`) on conflict rollback
);

create table expression_pk(
  `an id` int not null,
  constraint `pk 1` primary key (`an id`/2, `an id`%2)
);

create table expression_uk(
  `an id` int not null,
  constraint uk1 unique (`an id`/2, `an id`%2)
);

-- This table has to be deleted after delete_first
-- even though it sorts in the other order by name
-- the old algorithm would have got this wrong
create table delete__second
(
 `an id` integer primary key
) @delete(7);

create table delete_first
(
  `an id` integer references delete__second(`an id`)
) @delete(7);

-- This table has to be created before create_second
-- even though it sorts in the other order by name.
-- the old algorithm would have got this wrong
create table `create first`
(
 `an id` integer primary key
) @create(7);

create table create_second
(
  `an id` integer references `create first`(`an id`)
) @create(7);


[[blob_storage]]
create table blob_storage_at_create_table(
  x integer,
  y text
) @create(5);

[[blob_storage]]
create table blob_storage_baseline_table(
  x integer,
  y text
);

create table unsub_recreated(
 anything text
) @recreate;

create index unsub_recreated_index on unsub_recreated(anything);

create trigger unsub_recreated_trigger
  before insert on unsub_recreated
begin
  select 1;
end;

[[backing_table]]
create table backing(
 k blob primary key,
 v blob not null
);

[[backed_by=backing]]
create table backed(
  x integer primary key,
  y integer
);

[[backing_table]]
create table recreate_backing(
 k blob primary key,
 v blob not null
) @recreate(foo);

[[backed_by=recreate_backing]]
create table recreate_backed(
  x integer primary key,
  y integer
) @recreate(foo);

create table after_backed_table(
  x integer primary key
) @recreate(foo);

@unsub(unsub_recreated);

@begin_schema_region other;

create table unsub_voyage(
 v1 integer,
 v3 text @create(3),
 v5 text @create(5),
 v7 text @create(7)
);

create index unsub_voyage_index on unsub_voyage(v1);

create trigger unsub_voyage_trigger
  before insert on unsub_voyage
begin
  select 1;
end;

create table unsub_inner(
 `an id` integer primary key,
 name_inner text
);

create index us1 on unsub_inner(name_inner);

create table unsub_outer(
 `an id` integer primary key references unsub_inner(`an id`),
 name_outer text
);

create index us2 on unsub_outer(name_outer);


@unsub(unsub_voyage);
@unsub(unsub_outer);
@unsub(unsub_inner);

create table some_table(`an id` integer);

create view `foo view unsubscribed` as select * from some_table;
create view `foo view normal` as select * from some_table;

@unsub(`foo view unsubscribed`);

@end_schema_region;
