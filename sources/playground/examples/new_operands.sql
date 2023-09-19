/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

DECLARE PROC printf NO CHECK;

#define DUMP(stmt) stmt; printf("%-30s -> x is now %d\n", #stmt, x)

create proc entrypoint()
begin
  DUMP(declare x integer not null);
  DUMP(x := 100);
  DUMP(x *= 2);
  DUMP(x += 25);
  DUMP(x -= 15);
  DUMP(x /= 3);
  DUMP(x %= 8);
end;
