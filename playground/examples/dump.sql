@include "utils/dump.sql"

-- Check the implementation in utils/dump.sql

proc entrypoint()
begin
  1::dump();
  DUMP!(1+1);
  if 2::dump() then
    "hi there"::dump();
  end if;

  -- standard casting syntax)
  ERROR!(cast("1.23" as real), "-- not safe to emulate SQLite");

  -- Alternate casting syntax
  EXAMPLE!( (select ("100"||1.23) ~real~ ));
  _!("Hello");
end;
