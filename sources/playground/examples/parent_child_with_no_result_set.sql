/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare proc printf no check;

[[private]]
proc create_tables()
begin
  create table parent_table(
    id integer primary key,
    u text not null,
    v text not null
  );

  create table child_table(
    id integer not null references parent_table(id),
    seq integer not null,
    a integer not null,
    b integer not null,
    primary key (id, seq)
  );
end;

[[private]]
proc parent(u_ text)
begin
  select * from parent_table where u = u_;
end;

[[private]]
proc child_id(id_ integer not null)
begin
  select * from child_table where id = id_;
end;

[[private]]
proc insert_data()
begin
  insert into parent_table values
    (1, 'foo', 'goo'),
    (2, 'foo', 'stew'),
    (3, 'you', 'new'),
    (4, 'who', 'moo');

  insert into child_table values
    (1, 1, 100, 10),
    (1, 2, 200, 20),
    (2, 1, 300, 30),
    (2, 2, 400, 40),
    (3, 1, 500, 50),
    (4, 1, 600, 60),
    (4, 2, 700, 70);
end;

[[private]]
proc print_no_rowset_iteration_method()
begin
  call printf("compute no rowsets method\n");
  call printf("  this can be better if you don't need to materialize rowsets at all\n");

  -- gets a statement from the parent proc
  declare C cursor for call parent('foo');
  loop fetch C
  begin
    call printf("id: %d, u:%s, v:%s\n", C.id, C.u, C.v);
    declare D cursor for call child_id(C.id);
    loop fetch D
    begin
      call printf("    id:%d seq:%d    a:%d b:%d\n", D.id, D.seq, D.a, D.b);
    end;
  end;
end;

proc entrypoint()
begin
  call create_tables();
  call insert_data();

  call print_no_rowset_iteration_method();
end;
