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
    (3, 1, 500, 50),
    (4, 1, 600, 60),
    (4, 2, 700, 70);
end;

[[private]]
proc parent(u_ text)
begin
  select * from parent_table where u = u_;
end;

proc a_and_b_row(id_ integer not null)
begin
  declare C cursor for select a, b from child_table where id = id_ limit 1;
  fetch C;
  out C;
end;

proc x_and_y_row(id integer not null, x real, y real)
begin
   -- a cursor can be loaded from values with no DB access required
   declare C cursor like x_and_y_row arguments;
   fetch C from arguments;

   -- a loaded cursor can be updated
   -- this is a silly update but this is only a demno
   update cursor C using x + id - 1 as x;
   out C;
end;

proc parent_child_record(u_ text)
begin
  declare C cursor for call parent(u_);
  loop fetch C
  begin
    declare result cursor like(like parent, a_and_b object<a_and_b_row set>, x_and_y object<x_and_y_row set>);
    fetch result from values(from C, a_and_b_row(C.id), x_and_y_row(C.id, 3.14, 2.718));
    out union result;
  end;
end;

[[private]]
proc print_results(results object<parent_child_record set>)
begin
  call printf("Compute nested result via out cursor\n");
  call printf("  this can be used to emulate records in a column with type safety\n");

  declare C cursor for results;
  loop fetch C
  begin
    call printf("id: %d, u:%s, v:%s\n", C.id, C.u, C.v);

    declare D cursor for C.a_and_b;
    fetch D; -- check for a row
    if D then
      call printf("    a:%d b:%d\n", D.a, D.b);
    end if;

    declare E cursor for C.x_and_y;
    fetch E;
    if E then -- check for a row
      call printf("    x:%f y:%f\n", E.x, E.y);
    end if;
   end;
end;

proc entrypoint()
begin
  call create_tables();
  call insert_data();
  let results := parent_child_record('foo');
  call print_results(results);
end;
