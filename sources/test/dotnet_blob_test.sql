-- Copyright (c) Rico Mariani
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.

proc echo_nullable(payload blob, out echoed blob)
begin
  echoed := payload;
end;

proc echo_nonnull(payload blob not null, out echoed blob not null)
begin
  echoed := payload;
end;

proc consume_nonnull(payload blob not null)
begin
  declare copied blob not null;
  copied := payload;
end;

proc replace_nullable(inout payload blob, replacement blob)
begin
  payload := replacement;
end;

proc replace_nonnull(inout payload blob not null, replacement blob not null)
begin
  payload := replacement;
end;

proc same_bytes(marker integer not null, left_value blob, right_value blob,
                out same bool not null)
begin
  same := marker == 73 and left_value is right_value;
end;

proc projected(payload blob)
begin
  declare C cursor like (value blob);
  fetch C from values (payload);
  out C;
end;

proc projected_nonnull(payload blob not null)
begin
  declare C cursor like (value blob not null);
  fetch C from values (payload);
  out C;
end;
