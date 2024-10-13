/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare proc printf no check;

proc make_mixed ()
begin
  create table mixed(
    id int!,
    name text,
    code long,
    flag bool,
    rate real
  );
end;

proc ins(like mixed)
begin
  insert into mixed from arguments;
end;

proc up(id_ int!, rate_ real!)
begin
  update mixed set rate = rate_ WHERE id = id_;
end;

proc get_mixed (lim int!)
begin
  select * from mixed order by id limit lim;
end;

proc load_mixed ()
begin
  delete from mixed;

  -- using pipeline form
  1:ins('a name', 12, 1, 5.0);
  2:ins('some name', 14, 3, 7.0);
  3:ins('yet another name', 15, 3, 17.4);
  4:ins('some name', 19, 4, 9.1);
  5:ins('what name', 21, 8, 12.3);
end;

proc print_mixed()
begin
  cursor C for call get_mixed(50);
  loop fetch C
  begin
    printf("%d %-20s %10lld %3d %10.2f\n", C.id, C.name, C.code, C.flag, C.rate);
  end;
end;

create proc entrypoint()
begin
  make_mixed();
  load_mixed();
  print_mixed();

  printf("\nupdating mixed values 3 and 4\n\n");

  -- using pipeline form
  3:up(999.99);
  4:up(199.99);

  print_mixed();
end;
