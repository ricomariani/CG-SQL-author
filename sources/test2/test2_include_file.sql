/*
 * Copyright (c) Rico Mariani
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- this test file has to be in a different directory to exercise the include paths directives

@include "test2_second_include_file.sql"

proc any_proc(out z integer)
begin
  z := 1;
end;
