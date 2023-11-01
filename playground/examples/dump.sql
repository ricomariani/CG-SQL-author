#include <utils/dump.sql>

-- Check the implementation in utils/dump.sql

proc entrypoint()
begin
  1::dump();
  DUMP(1+1);
  if 2::dump() then
    "hi there"::dump();
  end if;

  ERROR(cast("1.23" as real), "-- not safe to emulate SQLite");
  EXAMPLE(select cast("100"||1.23 as real));
  _("Hello");
end;
