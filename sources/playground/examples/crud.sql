/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

DECLARE PROC printf NO CHECK;

CREATE PROC make_mixed ()
BEGIN
  CREATE TABLE mixed(
    id INTEGER NOT NULL,
    name TEXT,
    code LONG_INT,
    flag BOOL,
    rate REAL
  );
END;

CREATE PROC load_mixed ()
BEGIN
  DELETE FROM mixed;
  INSERT INTO mixed VALUES(1, 'a name', 12, 1, 5.0);
  INSERT INTO mixed VALUES(2, 'some name', 14, 3, 7.0);
  INSERT INTO mixed VALUES(3, 'yet another name', 15, 3, 17.4);
  INSERT INTO mixed VALUES(4, 'some name', 19, 4, 9.1);
  INSERT INTO mixed VALUES(5, 'what name', 21, 8, 12.3);
END;

CREATE PROC update_mixed (id_ INTEGER NOT NULL, rate_ REAL NOT NULL)
BEGIN
  UPDATE mixed
  SET rate = rate_
    WHERE id = id_;
END;

@ATTRIBUTE(cql:identity=(id, code))
@ATTRIBUTE(cql:generate_copy)
CREATE PROC get_mixed (lim INTEGER NOT NULL)
BEGIN
  SELECT *
    FROM mixed
  ORDER BY id
  LIMIT lim;
END;

create proc print_mixed()
begin
  declare C cursor for call get_mixed(50);
  loop fetch C
  begin
     call printf("%d %s %lld %d %f\n", C.id, C.name, C.code, C.flag, C.rate);
  end;
end;

create proc entrypoint()
begin
  call make_mixed();
  call load_mixed();
  call print_mixed();
  call printf("\nupdating mixed values 3 and 4\n");
  call update_mixed(3, 999.99);
  call update_mixed(4, 199.99);
  call print_mixed();
end;
