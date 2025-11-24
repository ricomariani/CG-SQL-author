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

-- [[private]] bug if this is is private we fail to emit a needed result set type
proc children_by_name(u_ text)
begin
  select T1.id, T2.seq, T2.a, T2.b
  from parent_table T1
  join child_table T2 on T1.id = T2.id
  where u = u_;
end;

-- join together parent and child using 'id'
-- example x_, y_ arguments for illustration only
[[private]]
proc parent_child_join(u_ text)
begin
  out union call parent(u_) join call children_by_name(u_) using (id);
end;

proc child_id(id_ integer not null)
begin
  select * from child_table where id = id_;
end;

[[private]]
proc parent_child_iter(u_ text)
begin
  declare C cursor for call parent(u_);
  loop fetch C
  begin
    declare result cursor like(like parent, ch1 object<child_id set>);
    fetch result from values(from C, child_id(C.id));
    out union result;
  end;
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
proc print_two_selects_method()
begin
  printf("compute nested result via two selects\n");
  printf("  this has the fewest sql queries and does an in-memory join\n");

  declare C cursor for call parent_child_join('foo');
  loop fetch C
  begin
    printf("id: %d, u:%s, v:%s\n", C.id, C.u, C.v);
    declare D cursor for C.child1;
    loop fetch D
    begin
      printf("    id:%d seq:%d    a:%d b:%d\n", D.id, D.seq, D.a, D.b);
    end;
  end;
end;

[[private]]
proc print_iteration_method()
begin
  printf("\ncompute nested result via iteration\n");
  printf("  this can be better if the number of rows is small or the join is expensive\n");

  declare C cursor for call parent_child_iter('foo');
  loop fetch C
  begin
    printf("id: %d, u:%s, v:%s\n", C.id, C.u, C.v);
    declare D cursor for C.ch1;
    loop fetch D
    begin
      printf("    id:%d seq:%d    a:%d b:%d\n", D.id, D.seq, D.a, D.b);
    end;
  end;
end;

proc entrypoint()
begin
  create_tables();
  insert_data();
  print_two_selects_method();
  print_iteration_method();
end;
