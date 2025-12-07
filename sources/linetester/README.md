# Summary

`linetest` is a test tool.  It processes the output .c code of a compilation
looking for the `#line` directives and compares them against the expected.

Since new tests are always added all of the line numbers in the test collateral
are relative to the procedure they are found in.  The generated output is normalized
to reflect this, so in short, each procedure looks like it wqas compiled in its
own file.

# Usage

```bash
linetest expected_lines output_file.c
```

# Contents

* `linetest.c` -- checked in compiled version of linetest.sql
* `linetest.h` -- checked in compiled version of linetest.sql
* `linetest.sql` -- the line tester (uses cqlhelp.c for args and setup stuff)
* `regen.sh` -- rebuilds linetest.c and linetest.h

Importantly, we do not always regenerate `linetest.c` because we expect that the compiler
might be slightly broken during development.  So we regenerate a working comparator
from time to time to keep the output relatively fresh viz code gen norms but not
instantly up to date.  It is wise not to depend on a compilers latest features in
the test cases immediatly.

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.

# Test Case Markup

Line numbers are relative to the line the #define _PROC_

Anything outside the #define and #undef for _PROC is IGNORED, it's just comments.

The test cases are echoed here but again, that will be ignored, it's just here
for your viewing pleasure.  The source of truth is in "test/linetest.sql"
annotated source code from there included.

```
TEST: simple statements
----------------
10: CREATE PROC based_statements ()
11: BEGIN
12:   DECLARE x INTEGER NOT NULL;      THIS IS FOR DISPLAY ONLY.
13:   SET x := 1;                      THIS TEXT IS PROOF THAT THIS IS NOT PARSED.
14:   SET x := 2;
15:   SET x := 3;
16:   @ECHO c, "/* hello ";
17:   @ECHO c, "world \n";
18:   SET x := 4;
19:   SET x := 5;
20: END;
----------------

Note that the proc started at line 10.  That's because there was a comment
but the starting line is not relevant, everything will be normalized to
a proc that starts at line 1 anyway.

#define _PROC_ "based_statements"
# 1
void based_statements(void) {
# 1
  cql_int32 x = 0;
# 1

# 3 "test/linetest.sql"
# 4 "test/linetest.sql"
  x = 1;
# 5 "test/linetest.sql"
  x = 2;
# 6 "test/linetest.sql"
  x = 3;
# 6
  /* hello world 
# 9 "test/linetest.sql"
  x = 4;
# 10 "test/linetest.sql"
  x = 5;
# 11 "test/linetest.sql"

# 11
}
#undef _PROC_
```

The test cases cover every statement type that needs line handling.  Simple statements
are best so as to avoid spurious errors due to codegen changes.