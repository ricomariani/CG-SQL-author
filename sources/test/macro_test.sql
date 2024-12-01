/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- note to readers
--
-- This file contains test cases for the macro expansion only
-- as such there are many things here that can be parsed legally
-- but are semantically invalid or meaningless.
--
-- The purpose of these test cases is to exercise all the legal
-- macro paths only so don't worry about that business.

-- do not insert tests before this one the line numbers matter in the first test

-- TEST: macro definition that uses the current file and line number
-- we will verify the line numbers.  Don't move this code or the test
-- will fail for no good reason.

-- + @MACRO(STMT_LIST) file_line!()
-- + BEGIN
-- + LET line := @MACRO_LINE;
-- + LET file := @MACRO_FILE;
-- + LET mline := 34;
-- + LET mfile := 'test/macro_test.sql';
-- + END
@macro(stmt_list) file_line!()
begin
  let line := @MACRO_LINE;
  let file := @MACRO_FILE;
  let mline := @LINE;
  let mfile := @FILE("");
end;

-- TEST: macro expansion file and line
-- + LET line := 43;
-- + LET file := 'test/macro_test.sql';
-- + LET mline := 34;
-- + LET mfile := 'test/macro_test.sql';
file_line!();

-- TEST: assert macro
-- + @MACRO(STMT_LIST) assert!(e! EXPR)
-- + BEGIN
-- +   IF NOT e! THEN
-- +     CALL printf("assert '%s' failed at line %s:%d\n", @TEXT(e!), @MACRO_FILE, @MACRO_LINE);
-- +   END;
-- + END;
@macro(stmt_list) assert!(e! expr)
begin
  if (not e!) then
     call printf("assert '%s' failed at line %s:%d\n", @text(e!), @macro_file, @macro_line);
  end if;
end;

-- an assertion... but converted to a string
-- + LET zzz := "begin\nIF NOT 7 THEN\n  CALL printf(\"assert '%%s' failed at line %%s:%d\\n\", \"7\", 'test/macro_test.sql', 61);\nEND;\n\nfoo";
let zzz := @TEXT("begin\n", assert!(7), "\nfoo");

-- TEST: expression macro
-- + @MACRO(EXPR) expr_macro_def_test!(x! EXPR, z! EXPR)
-- + x! + z!
@macro (expr) expr_macro_def_test!(x! expr, z! expr)
begin
  x! + z!
end;

-- TEST: statment macro
-- + @MACRO(STMT_LIST) stmt_macro_def_test!(x! EXPR, y! STMT_LIST)
-- + IF x! THEN
-- +   y!;
-- + END;
@macro(stmt_list) stmt_macro_def_test!(x! expr, y! stmt_list)
begin
  if x! then y!; end if;
end;

-- TEST:  int! still works even though it isn't a macro
-- + DECLARE x_int INT!;
var x_int int!;


-- TEST: expand statement list macro
-- + IF 1 THEN
-- + CALL printf("hi\n");
-- + END;
create proc foo()
begin
  stmt_macro_def_test!(1, begin call printf("hi\n"); end);
end;

create table first_table(
  x int!
);

create table second_table(
  y int!
);

-- TEST: query parts macro
-- + @MACRO(QUERY_PARTS) qp!()
-- + BEGIN
-- +   first_table AS T1
-- +   INNER JOIN second_table AS T2 ON T1.x = T2.y
-- + END;
@macro(query_parts) qp!()
begin
  first_table as T1 inner join second_table as T2 on T1.x == T2.y
end;

-- TEST: make a select statement...
-- use macro in a join clause
-- + SELECT *
-- +   FROM (
-- +     first_table AS T1
-- +     INNER JOIN second_table AS T2 ON T1.x = T2.y)
-- +   INNER JOIN second_table;
select * from qp!() inner join second_table;

-- TEST: use macro as a table
-- + SELECT *
-- +   FROM (
-- +     first_table AS T1
-- +     INNER JOIN second_table AS T2 ON T1.x = T2.y) AS T1;
select * from qp!() as T1;

-- TEST: statement macro that assembles query parts
-- + @MACRO(STMT_LIST) sel!(e! EXPR, q! QUERY_PARTS)
-- + BEGIN
-- +   SELECT e!
-- +   FROM q! AS Q;
-- + END;
@macro(stmt_list) sel!(e! expr, q! query_parts)
begin
  select e! from q! as Q;
end;

-- TEST: expand a full select statement with nested macros as args
-- + SELECT x
-- +   FROM (
-- +     first_table AS T1
-- +     INNER JOIN second_table AS T2 ON T1.x = T2.y) AS Q;
sel!(x, from( qp!() ));

-- TEST: expand a full select statement with nested macros as args
-- arg typing is optional for variables, it can be inferred
-- + SELECT x
-- +   FROM (
-- +     first_table AS T1
-- +     INNER JOIN second_table AS T2 ON T1.x = T2.y) AS Q;
sel!(x, qp!());

-- TEST: cte tables macro
-- + @MACRO(CTE_TABLES) cte!()
-- + BEGIN
-- +   foo (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   ),
-- +   bar (*) AS (
-- +     SELECT 3 AS u, 4 AS v
-- +   )
-- + END;
@macro(cte_tables) cte!()
begin
  foo(*) as (select 1 x, 2 y),
  bar(*) as (select 3 u, 4 v)
end;

-- TEST use cte tables
-- + WITH
-- +   vv (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   ),
-- +   foo (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   ),
-- +   bar (*) AS (
-- +     SELECT 3 AS u, 4 AS v
-- +   ),
-- +   uu (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   )
-- + SELECT *
-- +   FROM foo;
with
vv(*) as (select 1 x, 2 y),
cte!(),
uu(*) as (select 1 x, 2 y)
select * from foo;

-- TEST: cte tables at the front of the list
-- + WITH
-- +   foo (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   ),
-- +   bar (*) AS (
-- +     SELECT 3 AS u, 4 AS v
-- +   ),
-- +   uu (*) AS (
-- +     SELECT 1 AS x, 2 AS y
-- +   )
-- + SELECT *
-- +   FROM foo;
with
cte!(),
uu(*) as (select 1 x, 2 y)
select * from foo;

-- TEST: cte tables macro as the only element
-- + WITH
-- +  foo (*) AS (
-- +    SELECT 1 AS x, 2 AS y
-- +  ),
-- +  bar (*) AS (
-- +    SELECT 3 AS u, 4 AS v
-- +  )
-- + SELECT *
-- +   FROM foo;
with
cte!()
select * from foo;

-- TEST: cte tables macro at the end of the list
-- + WITH
-- +  vv (*) AS (
-- +    SELECT 1 AS x, 2 AS y
-- +  ),
-- +  foo (*) AS (
-- +    SELECT 1 AS x, 2 AS y
-- +  ),
-- +  bar (*) AS (
-- +    SELECT 3 AS u, 4 AS v
-- +  )
-- +SELECT *
-- +  FROM foo;
with
vv(*) as (select 1 x, 2 y),
cte!()
select * from foo;

-- TEST: amacro that accepts CTE tables
-- + @MACRO(STMT_LIST) query!(u! CTE_TABLES)
-- + BEGIN
-- +   WITH
-- +   u!
-- +   SELECT *
-- +     FROM foo;
-- + END;
@macro(stmt_list) query!(u! cte_tables)
begin
  with u! select * from foo;
end;

-- TEST: use cte tables as a macro arg
-- + WITH
-- + foo (*) AS (
-- +   SELECT 100 AS x, 200 AS y
-- + )
-- + SELECT *
-- +   FROM foo;
query!(with( foo(*) as (select 100 x, 200 y)));

-- TEST: macro that produces a select core list
-- + @MACRO(SELECT_CORE) selcor!(x! EXPR)
-- + BEGIN
-- +   SELECT x! + 1 AS x
-- +   UNION ALL
-- +   SELECT x! + 2 AS x
-- + END;
@macro(select_core) selcor!(x! expr)
begin
  select x! + 1 x
  union all
  select x! + 2 x
end;

-- TEST: macro that accepts select core lists
-- + @MACRO(SELECT_CORE) selcor2!(x! SELECT_CORE, y! SELECT_CORE)
-- + BEGIN
-- + x!
-- + UNION ALL
-- + y!
-- + END;
@macro(select_core) selcor2!(x! select_core, y! select_core)
begin
   ROWS(x!) union all ROWS(y!)
end;

-- TEST: use macro that consumes select core list
-- + SELECT 5 + 1 AS x
-- + UNION ALL
-- + SELECT 5 + 2 AS x
-- + UNION ALL
-- + SELECT 50 + 1 AS x
-- + UNION ALL
-- + SELECT 50 + 2 AS x;
ROWS(selcor2!(selcor!(5), selcor!(50)));


-- TEST: a select expression with args
-- + @MACRO(SELECT_EXPR) se!(x! SELECT_EXPR)
-- + BEGIN
-- +   x!, x!
-- + END;
@macro(select_expr) se!(x! select_expr)
begin
  x!, x!
end;

-- TEST: a select expression with nested macro
-- + @MACRO(SELECT_EXPR) se2!(x! SELECT_EXPR)
-- + BEGIN
-- +   se!(SELECT(x!))
-- + END;
@macro(select_expr) se2!(x! select_expr)
begin
  se!(select(x!))
end;

-- TEST: use se2 to build a select list, with args
-- + SELECT x + 2 AS z, x + 2 AS z;
select se2!(select(x+2 z));

-- TEST: expression macro
-- + @MACRO(EXPR) macro1!(u! EXPR)
-- + BEGIN
-- +   u! + u! + 1
-- + END;
@macro(expr) macro1!(u! expr)
begin
  u! + u! + 1
end;

-- TEST: expression macro with args
-- + @MACRO(EXPR) macro2!(u! EXPR, v! EXPR)
-- + BEGIN
-- +   u! * macro1!(v! + 5)
-- + END;
@macro(expr) macro2!(u! expr, v! expr)
begin
  u! * macro1!(v! + 5)
end;

-- TEST: expression macro accepting query parts to make text
-- + @MACRO(EXPR) macro3!(q! QUERY_PARTS)
-- + BEGIN
-- +   @TEXT(q!)
-- + END;
@macro(expr) macro3!(q! query_parts)
begin
  @TEXT(q!)
end;

-- TEST: expression macro accepting using tables to make text
-- + @MACRO(EXPR) macro4!(q! CTE_TABLES)
-- + BEGIN
-- +   @TEXT(q!)
-- + END;
@macro(expr) macro4!(q! cte_tables)
begin
  @TEXT(q!)
end;

-- TEST: expression macro accepting select core to make text
-- + @MACRO(EXPR) macro5!(q! SELECT_CORE)
-- + BEGIN
-- +   @TEXT(q!)
-- + END;
@macro(expr) macro5!(q! select_core)
begin
  @TEXT(q!)
end;

-- TEST: expression macro accepting expression to make text
-- + @MACRO(EXPR) macro6!(q! EXPR)
-- + BEGIN
-- +   @TEXT(q!)
-- + END;
@macro(expr) macro6!(q! expr)
begin
  @TEXT(q!)
end;

-- TEST: expression macro accepting select expression to make text
-- + @MACRO(EXPR) macro7!(q! SELECT_EXPR)
-- + BEGIN
-- +   @TEXT(q!)
-- + END;
@macro(expr) macro7!(q! select_expr)
begin
  @TEXT(q!)
end;

let x := 1;
let y := 2;

-- TEST: nested expressions
-- + LET z := x * (y + 5 + (y + 5) + 1);
let z := macro2!(x, y);

-- TEST: query parts as text (table factor)
-- + LET zz := "(SELECT 1 AS x, 2 AS y) AS T";
let zz := macro3!(from( (select 1 x, 2 y) as T));

-- TEST: query parts as text (join)
-- + SET zz := "T1\nINNER JOIN T2 ON T1.id = T2.id";
set zz := macro3!(from( T1 join T2 on T1.id = T2.id));

-- TEST: cte tables as text
-- + SET zz := "x (*) AS (\n  SELECT 1 AS x, 2 AS y\n)\n";
set zz := macro4!(WITH( x(*) as (select 1 x, 2 y) ));

-- TEST: select core list as text
-- + SET zz := "SELECT 1 AS x\n  FROM foo";
set zz := macro5!(ROWS(select 1 x from foo));

-- TEST: expression as text
-- + SET zz := "1 + 2";
set zz := macro6!(1+2);

-- TEST: select expressions as text
-- + SET zz := "1 AS x, 2 AS y";
set zz := macro7!(select(1 x, 2 y));

-- TEST: ID to make a string into an identifier
-- + SET x := 5;
set @ID("x") := 5;

-- TEST: ID to make a name out of parts
-- + LET uv := 5;
let @ID(@TEXT("u", "v")) := 5;

-- TEST: macro with all the arg types and forwarded with the simple syntax (convert to text)
-- + @MACRO(STMT_LIST) mondo1!(a! EXPR, b! QUERY_PARTS, c! SELECT_CORE, d! SELECT_EXPR, e! CTE_TABLES, f! STMT_LIST)
-- + BEGIN
-- +   SET zz := @TEXT(a!, "___", b!, "___", c!, "___", d!, "___", e!, "___", f!);
-- + END;
@macro(stmt_list) mondo1!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  set zz := @text(a!, "___", b!, "___", c!, "___", d!, "___", e!, "___", f!);
end;

-- TEST: macro with all the arg types and forwarded with the simple syntax
-- + @MACRO(STMT_LIST) mondo2!(a! EXPR, b! QUERY_PARTS, c! SELECT_CORE, d! SELECT_EXPR, e! CTE_TABLES, f! STMT_LIST)
-- + BEGIN
-- +   mondo1!(a!, b!, c!, d!, e!, f!);
-- + END;
@macro(stmt_list) mondo2!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  mondo1!(a!, b!, c!, d!, e!, f!);
end;

-- TEST: make a big chunk of text
-- SET zz := "1 + 2___x\nINNER JOIN y___SELECT 1\n  FROM foo\nUNION\nSELECT 2\n  FROM bar___20 AS first_table___f (*) AS (\n  SELECT 99\n    FROM second_table\n)\n___LET qq := 201;\n";
mondo2!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 first_table),
  with(f(*) as (select 99 from second_table)),
  begin let qq := 201; end
);

-- TEST: tricky case to make sure that the selection is properly wrapped as an expression
-- + @MACRO(EXPR) a_selection!()
-- + BEGIN
-- +   ( SELECT 1 + 5 )
-- + END;
@macro(expr) a_selection!()
begin
  (select 1+5)
end;

-- TEST: make sure that the selection is properly wrapped as an expression (as text)
-- the parens are the important part, it has to be an expression not a statement
-- even though it's quoted
--
-- + LET x := "( SELECT 1 + 5 )";
let x := @TEXT(a_selection!());

-- TEST: expression macro in pipeline
-- + LET y := 5 + 5 + 1;
let y := 5:macro1!;

-- TEST: pipeline macro with no args
-- + LET z := 6 + 6 + 1;
let z := 6:macro1!();

-- TEST: pipeline macro with args
-- + LET w := 7 * (11 + 5 + (11 + 5) + 1);
let w := 7:macro2!(11);

-- TEST: use proc in various forms, ensuring it resolves very late
-- These tests verify that we can use @proc inside of other constructs
-- to build identifiers and strings that are more complicated.  The
-- trick here is that unlike literally everything else @proc must be
-- evaluated very late, the invoking context may not even be a proc
-- but it may ultimately generate one. run_test.sql is full of this
-- kind of thing.
--
-- + LET zz := 'various_proc_forms':fmt();
-- + LET uu := "various_proc_forms_x";
-- + LET uu := "foo_x";
-- + LET various_proc_forms_foo := 1;
proc various_proc_forms()
begin
 let zz := @proc:fmt;
 let uu := @text(@proc, "_x");
 let uu := @text('foo', "_x");
 let @ID(@proc, "_foo") := 1;
end;

@macro(stmt_list) proc_macro!(x! stmt_list)
begin
 create proc macro_test_proc()
 begin
   x!;
 end;
end;

-- TEST: make sure that proc is not evaluated inside of macro args
-- indeed @text and @id must not do their job until after they are
-- out of any macro arg. They can only evaluate their arguments
-- and never @proc.  The code below doen't appear in the context 
-- of the proc.  The macros have to unwind first, hence the test.
--
-- + LET x := 'macro_test_proc';
-- + LET y := "macro_test_proc";
-- + LET macro_test_proc_bar_baz := 1;
-- + LET tmp_%_extension := 7;
-- + tmp_%_extension := 7;
proc_macro!(
begin
  let x := @proc;
  let y := @text(@proc);
  let @id(@proc,"_bar_baz") := 1;
  let @tmp("_extension") := 7;
  @tmp(_extension) := 7;
end
);

