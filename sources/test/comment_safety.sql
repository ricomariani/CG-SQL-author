/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#line 7 "safe\n#error provenance_injection"

proc comment_safety()
begin
  let hostile := "]]; error('lua_comment_injection') --";
end;
