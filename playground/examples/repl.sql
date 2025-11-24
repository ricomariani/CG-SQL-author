/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

DECLARE PROC printf NO CHECK;

CREATE PROC entrypoint ()
BEGIN
  call printf("put your code here\n");
END;
