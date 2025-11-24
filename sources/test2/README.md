# Test2 Directory Notes

This second test directory exists to help with testing the @include directive.
It's important to verify that we are able to pull from paths relative to the
directory the including file is in so we need some other directory that we
can be "relative to" when an include happens

`test2_include_file.sql` will try to pull in `test2_second_include_file.sql`
and it does so with no include path to help it.  It should be able to do so
with this one directive.

```
test2_include_file.sql:@include "test2_second_include_file.sql"
```

If these were not in a different directory than test it would be not helpful
as a test case because the test directory has to be in the include path.
