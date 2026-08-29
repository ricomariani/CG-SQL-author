@macro(expr) minimum_long!()
begin
  -9223372036854775808
end;

select -minimum_long!();
