/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- The decoded filename contains a newline followed by text that would be a C
-- preprocessor directive if it escaped the generated provenance line comment.
#line 7 "safe\n#error provenance_injection"

proc comment_safety()
begin
  -- A fixed Lua long comment would close at the two right brackets and expose
  -- the remaining text as Lua.  The generator must select a stronger
  -- delimiter that does not occur anywhere in this statement.
  let hostile := "]]; error('lua_comment_injection') --";
end;
