/*
 * Copyright (c) Rico Mariani
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

DECLARE PROC printf NO CHECK;

@macro(stmt_list) DUMP!(exp! expr)
begin
  exp!;
  printf("%-30s -> x is now %d\n", @TEXT(exp!), x);
end;

create proc entrypoint()
begin
  declare x integer not null;

  DUMP!(x);
  DUMP!(x := 100);
  DUMP!(x *= 2);
  DUMP!(x += 25);
  DUMP!(x -= 15);
  DUMP!(x /= 3);
  DUMP!(x %= 8);
  DUMP!(x |= 11);
  DUMP!(x &= 7);
  DUMP!(x <<= 3);
  DUMP!(x >>= 1);
end;
