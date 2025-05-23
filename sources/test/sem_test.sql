/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- TEST: we'll be using printf in lots of places in the tests as an external proc
-- + {declare_proc_no_check_stmt}: ok
-- - error:
declare procedure printf no check;

-- TEST: try to declare printf as a normal proc too
-- + error: % procedure cannot be both a normal procedure and an unchecked procedure 'printf'
-- + {declare_proc_stmt}: err
-- +1 error:
declare proc printf();

-- TEST: basic test table with an auto inc field (implies not null)
-- + create_table_stmt% foo: % id: integer notnull primary_key autoinc
-- - error:
create table foo(
  id integer PRIMARY KEY AUTOINCREMENT
);

-- TEST: exact duplicate table is ok
-- + {create_table_stmt}: foo: { id: integer notnull primary_key autoinc } alias
-- - error:
create table foo(
  id integer PRIMARY KEY AUTOINCREMENT
);

-- TEST: create a table using type discrimation: kinds
-- + {create_table_stmt}: with_kind: { id: integer<some_key>, cost: real<dollars>, value: real<dollars> }
-- + {col_def}: id: integer<some_key>
-- + {col_def}: cost: real<dollars>
-- + {col_def}: value: real<dollars>
-- - error:
create table with_kind(
  id integer<some_key>,
  cost real<dollars>,
  value real<dollars>
);

-- useful in later tests
declare price_d real<dollars>;
declare price_e real<euros>;

-- TEST: second test table with combination of fields
-- + {create_table_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- - error:
create table bar(
  id int!,
  name text @create(2),
  rate LONG INT @create(2)
);

-- TEST: duplicate table name, creates error, will be ignored -- types will not be resolved due to early out
-- + error: % duplicate table/view
-- + {create_table_stmt}: err
create table foo(
  id integer
);

-- TEST: duplicate column names, creates error will be ignored
-- + error: % duplicate column name 'id'
-- + {create_table_stmt}: err
-- +1 error:
create table baz(
  id integer,
  id integer
);

-- TEST: ok to get ID from foo, unique
-- + _select_: { id: integer notnull }
-- - error:
select ID from foo;

-- TEST: make sure the type includes the kinds
-- + {select_stmt}: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars> }
-- - error:
select * from with_kind;

-- TEST: classic join
-- + _select_: { id: integer notnull, name: text }
-- + JOIN { T1: foo, T2: bar }
-- - error:
select T1.id, name
from foo AS T1
inner join bar AS T2 ON T1.id = T2.id
where rate > 0;

-- TEST: left join still creates new nullable columns with no join condition
-- this is necessary because "T2" might be empty
-- + {select_stmt}: _select_: { id: integer notnull, id: integer }
-- - error:
select * from foo T1 left join foo T2;

-- TEST: cross join does not create new nullable columns with join condition
-- cross is the same as inner in SQLite, only reordering optimization is suppressed
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- - error:
select * from foo T1 cross join foo T2 on T1.id = T2.id;

-- TEST: alternate join syntax
-- + _select_: { name: text }
-- + {select_from_etc}: JOIN { foo: foo, bar: bar }
-- - error:
select name from foo, bar;

-- TEST: duplicate table alias in the join, error
-- + error: % duplicate table name in join 'T1'
-- + {select_stmt}: err
-- +1 error:
select name from foo T1, bar T1, bar T1;

-- TEST: ambiguous id in foo and bar
-- + error: % identifier is ambiguous 'id'
-- +1 error:
select id from foo, bar;

-- TEST: column not present
-- + error: % name not found 'not_found'
-- +1 error:
select not_found from foo, bar;

-- TEST: simple string select, string literals
-- + _select_: { _anon: text notnull }
-- - error:
select 'foo';

-- TEST: string add not valid, further adding 3 does not create new errors
-- + error: % left operand cannot be a string in '+'
-- + {select_stmt}: err
-- +1 error:
select 'foo' + 'bar' + 3;

-- TEST: correct like expression
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {like}: bool notnull
-- - error:
select 'foo' like 'baz';

-- TEST: correct not like expression
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {not_like}: bool notnull
-- - error:
select 'foo' not like 'baz';

-- TEST: 1 is not a string
-- + error: % left operand must be a string in 'LIKE'
-- + {select_stmt}: err
-- +1 error:
select 1 like 'baz';

-- TEST: 1 is not a string in a "NOT LIKE" expr
-- + error: % left operand must be a string in 'NOT LIKE'
-- + {select_stmt}: err
-- +1 error:
select 1 not like 'baz';

-- TEST: 2 is not a string
-- + error: % right operand must be a string in 'LIKE'
-- + {select_stmt}: err
-- +1 error:
select 'foo' like 2;

-- TEST: correct concat strings
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {concat}: text notnull
-- - error:
select 'foo' || 'baz';

-- TEST: correct concat string or number case one
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {concat}: text notnull
-- - error:
select 'foo' || 1;

-- TEST: correct concat string or number case two
-- + select_stmt}: _select_: { _anon: text notnull }
-- + {concat}: text notnull
-- - error:
select 1.0 || 'baz';

-- TEST: converts to REAL
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {add}: real notnull
-- + {int 1}: integer notnull
-- + {dbl 2.0%}: real notnull
-- - error:
select 1 + 2.0;

-- TEST: stays integer
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {add}: integer notnull
-- + {int 3}: integer notnull
-- + {int 4}: integer notnull
-- - error:
select 3 + 4;

-- TEST: invalid addition of string to id
-- + error: % right operand cannot be a string in '+'
-- + {select_stmt}: err
-- +1 error:
select T1.id + 'foo' from foo T1;

-- TEST: invalid addition of id to string
-- + error: % left operand cannot be a string in '+'
-- + {select_stmt}: err
-- +1 error:
select 'foo' + T1.id from foo T1;

-- TEST: boolean is flexible with numerics
-- + {and}: bool notnull
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- - error:
select 1 AND 2;

-- TEST: logical operators can include null, creates nullable bool
-- + {or}: bool
-- + {null}: null
-- + {int 1}: integer notnull
-- - error:
select null or 1;

-- TEST: logical operators can include null, creates nullable bool
-- + {and}: bool
-- + {null}: null
-- + {int 1}: integer notnull
-- - error:
select null and 1;

-- TEST: ok to add to a boolean
-- + {add}: integer notnull
-- + {eq}: bool notnull
-- - error:
select (1 == 2) + 1;

-- TEST: can't do a logical AND with a string
-- + error: % left operand cannot be a string in 'AND'
-- + {select_stmt}: err
-- +1 error:
select 'foo' and 1;

-- TEST: error prop handled correctly after invalid boolean
-- + error: % right operand cannot be a string in 'AND'
-- + {or}: err
-- + {and}: err
-- + {strlit 'foo'}
-- + {int 1}: integer notnull
-- +1 error:
select 1 and 'foo' or 1;

-- TEST: can't compare string and number
-- + error: % required 'TEXT' not compatible with found 'INT' context '<'
-- + {lt}: err
-- +1 error:
select 'foo' < 1;

-- TEST: can't compare string and number
-- + error: % required 'INT' not compatible with found 'TEXT' context '>'
-- + {gt}: err
-- +1 error:
select 1 > 'foo';

-- TEST: string comparison is ok
-- + {ne}: bool notnull
-- + {strlit 'baz'}: text notnull
-- + {strlit 'foo'}: text notnull
-- - error:
select 'baz' != 'foo';

-- TEST: can't compare string and number, error prop ok.
-- + error: % required 'INT' not compatible with found 'TEXT' context '>'
-- + {select_stmt}: err
-- + {gt}: err
-- +1 error:
select 1 > 'foo' > 2;

-- TEST: foo unknown gives error, error doesn't prop through like
-- + error: % name not found 'foo'
-- - error: % LIKE
select foo like 'bar';

-- TEST: selecting negative ordinal (this has to be unary minus and 1)
-- + {uminus}: integer notnull
-- + {int 1}: integer notnull
-- not negative one
-- - {int -1}
-- - error:
select -1;

-- TEST: can't do unary minus on string
-- + error: % string operand not allowed in '-'
-- + {uminus}: err
select - 'x';

-- TEST: can't do NOT on strings
-- + error: % string operand not allowed in 'NOT'
-- + {not}: err
-- +1 error:
select NOT 'x';

-- TEST: real is ok as a boolean, it's truthy
-- + {not}: bool notnull
-- + {dbl 1.2}: real notnull
-- - error:
select NOT 1.2;

-- TEST: non-null bool result even with null input
-- + {is}: bool notnull
-- + {null}: null
-- - error:
select null is null;

-- TEST: incompatible types: is
-- + error: % required 'TEXT' not compatible with found 'REAL' context 'IS'
-- + {is}: err
-- +1 error:
select 'x' is 1.2;

-- TEST: non-null bool result even with null input
-- + {is_not}: bool notnull
-- + {null}: null
-- - error:
select null is not null;

-- TEST: unary math does not double report errors
-- + error: % string operand not allowed in 'NOT'
-- + {uminus}: err
-- +1 error:
select  - NOT 'x';

-- TEST: unary logical does not double report errors
-- + error: % string operand not allowed in '-'
-- + {not}: err
-- +1 error:
select NOT - 'x';

declare real_result2 real;

-- TEST: function for ':' test
-- + {declare_func_stmt}: real notnull
-- + {name simple_func2}: real notnull
-- + {func_params_return}
-- - error:
func simple_func2(arg1 int!, arg2 int!, arg3 int!) real!;

-- TEST: colon operator used with the right number of args does not report errors
-- + {name simple_func2}
-- + {arg_list}: ok
-- + {int 2}: integer notnull
-- + {arg_list}
-- + {int 3}: integer notnull
-- + {arg_list}
-- + {int 4}: integer notnull
-- - error:
SET real_result2 := 2:simple_func2(3, 4);

declare int_result int;
func simple_func3(arg1 int!) int!;

-- TEST: colon operator when only one arg exists
-- + {name simple_func3}
-- + {arg_list}: ok
-- + {int 2}: integer notnull
-- - error:
SET int_result := 2:simple_func3();

declare real_result4 real;

-- TEST: colon operator is actually left-associative
-- + {name simple_func2}
-- + {arg_list}: ok
-- + {call}: integer notnull
-- + {name simple_func3}
-- + {arg_list}: ok
-- + {int 1}: integer notnull
-- + {arg_list}
-- + {int 2}: integer notnull
-- + {arg_list}
-- + {int 3}: integer notnull
-- - error:
SET real_result4 := 1:simple_func3():simple_func2(2,3);

-- TEST: failure when the wrong number of arguments for a function are provided
-- + error: in call : CQL0212: too few arguments provided to procedure 'simple_func2'
-- + {call}: err
-- +1 error:
SET real_result4 := 1:simple_func2(2);

-- TEST: unary is null or is not null does not double report errors
-- + error: % string operand not allowed in '-'
-- + {is}: err
-- exactly one error
-- +1 error:
select (- 'x') is null;

-- TEST: negative boolean is ok
-- + {uminus}: integer notnull
-- + {not}: bool notnull
-- + {int 1}: integer notnull
-- - error:
select - NOT 1;

-- TEST: negative float is ok
-- + {uminus}: real notnull
-- + {dbl 1.2%}: real notnull
-- - error:
select - 1.2;

-- TEST: int*int -> int
-- + {mul}: integer notnull
-- - error:
select 1 * 2;

-- TEST: int-int -> int
-- + {sub}: integer notnull
-- - error:
select 3 - 4;

-- TEST: int / int -> int
-- + {div}: integer notnull
-- - error:
select 6 / 3;

-- TEST: int % int -> int
-- + {mod}: integer notnull
-- - error:
select 6 % 3;

-- TEST: int >= int -> bool
-- + {ge}: bool notnull
-- - error:
select 2 >= 1;

-- TEST: int <= int -> bool
-- + {le}: bool notnull
-- - error:
select 1 <= 2;

-- TEST: int == int -> bool
-- + {eq}: bool notnull
-- - error:
select 2 = 2;

-- TEST: select * produces correct tables joining foo and bar
-- - error:
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, name: text, rate: longint }
-- + {select_from_etc}: JOIN { foo: foo, bar: bar }
select * from foo, bar;

-- TEST: select expression alias to one, two works
-- - error:
-- + {select_stmt}: _select_: { one: integer notnull, two: integer notnull }
select 1 as one, 2 as two;

-- TEST: select * with no from is an error
-- + error: % select *, T.*, or @columns(...) cannot be used with no FROM clause
-- +1 error:
-- + {select_stmt}: err
-- + {star}: err
select *;

-- TEST: select where statement
-- + {select_stmt}: _select_: { T: integer notnull }
-- + {select_core}: _select_: { T: integer notnull }
-- + {select_expr_list_con}: _select_: { T: integer notnull }
-- + {select_expr_list}: _select_: { T: integer notnull }
-- + {select_from_etc}: ok
-- + {select_where}
-- - error:
select 10 as T where 1;

-- TEST: select where with a column specified
-- + error: % name not found 'c'
-- + {select_stmt}: err
-- + {name c}: err
-- + {select_from_etc}: ok
-- +1 error:
select c where 1;

-- TEST: a WHERE clause can refer to the FROM
-- + {select_stmt}: _select_: { id: integer notnull }
-- + {opt_where}: bool notnull
-- - error:
select * from foo where id > 1000;

-- TEST: a WHERE clause cannot refer to the SELECT list
-- + error: % alias referenced from WHERE, GROUP BY, HAVING, or WINDOW clause 'x'
-- + {select_stmt}: err
-- + {opt_where}: err
-- +1 error:
select id as x from foo where x > 1000;

-- TEST: a GROUP BY clause cannot refer to the SELECT list
-- + error: % alias referenced from WHERE, GROUP BY, HAVING, or WINDOW clause 'y'
-- + {select_stmt}: err
-- + {opt_groupby}: err
-- +1 error:
select id, name as y from bar group by y having count(name) > 10;

-- TEST: a HAVING clause cannot refer to the SELECT list
-- + error: % alias referenced from WHERE, GROUP BY, HAVING, or WINDOW clause 'y'
-- + {select_stmt}: err
-- + {opt_having}: err
-- +1 error:
select id, name as y from bar group by name having count(y) > 10;

-- TEST: a WINDOW clause cannot refer to the SELECT list
-- + error: % alias referenced from WHERE, GROUP BY, HAVING, or WINDOW clause 'y'
-- + {select_stmt}: err
-- + {opt_select_window}: err
-- +1 error:
select id, name as y, row_number() over w
from bar
window w as (order by y);

-- TEST: GROUP BY should not be able to have aggregate functions
-- + error: % function may not appear in this context 'count'
-- + {select_stmt}: err
-- + {opt_groupby}: err
-- + {groupby_list}: err
-- +1 error:
select * from foo group by count(id);

-- TEST: ORDER BY should be able to have aggregate functions
-- + {select_stmt}: _select_: { id: integer notnull }
-- + {opt_orderby}: ok
-- + {orderby_list}: ok
-- - error:
select * from foo order by count(id);

-- TEST: a WHERE clause cannot refer to the FROM if what it refers to in the
-- FROM shadows an alias in the SELECT list
-- + error: % must use qualified form to avoid ambiguity with alias 'name'
-- + {select_stmt}: err
-- + {opt_where}: err
-- +1 error:
select id as name from bar where name like "%foo%";

-- TEST: using a qualified reference avoids the error above
-- + {select_stmt}: _select_: { name: integer notnull }
-- + {opt_where}: bool
-- - error:
select id as name from bar where bar.name like "%foo%";

-- TEST: a WHERE clause cannot refer to the FROM if what it refers to in the
-- FROM shadows an alias in any enclosing SELECT list
-- + error: % must use qualified form to avoid ambiguity with alias 'name'
-- + {select_stmt}: err
-- + {opt_where}: err
-- +1 error:
select id as name
from bar
where id > (select count(rate) from bar where name like "%foo%");

-- TEST: again, using a qualified reference avoids the error above
-- + {select_stmt}: _select_: { name: integer notnull }
-- + {opt_where}: bool
-- - error:
select id as name
from bar
where id > (select count(rate) from bar where bar.name like "%foo%");

-- TEST: a GROUP BY clause cannot refer to the FROM if what it refers to in the
-- FROM shadows an alias in any enclosing SELECT list
-- + {select_stmt}: err
-- + {opt_groupby}: err
-- +2 error: % must use qualified form to avoid ambiguity with alias 'name'
-- +2 error:
select id as name, name from bar group by name having count(name) > 10;

-- TEST: a HAVING clause cannot refer to the FROM if what it refers to in the
-- FROM shadows an alias in any enclosing SELECT list
-- + {select_stmt}: err
-- + {opt_having}: err
-- +2 error: % must use qualified form to avoid ambiguity with alias 'name'
-- both instances are flagged
-- +2 error:
select id as name, name from bar group by name having count(name) > 10;

-- TEST: a WINDOW clause cannot refer to the FROM if what it refers to in the
-- FROM shadows an alias in any enclosing SELECT list
-- + error: % must use qualified form to avoid ambiguity with alias 'name'
-- + {select_stmt}: err
-- + {opt_select_window}: err
-- +1 error:
select id as name, name, row_number() over w
from bar
window w as (order by name);

-- TEST: select * from bogus table doesn't give more errors
-- + error: % table/view not defined 'goo'
-- + {select_stmt}: err
-- + {table_or_subquery}: err
-- +1 error:
select * from goo;

-- TEST: add a table with some big stuff
-- + {col_def}: l: longint
-- + {col_def}: r: real
-- - error:
create table big (
  l LONG integer,
  r REAL
);

-- TEST: create a long int
-- + {select_stmt}: _select_: { l: longint }
-- - error:
select l from big;

-- TEST: long * int -> long
-- + {select_stmt}: _select_: { _anon: longint }
-- + {select_from_etc}: TABLE { big: big }
-- - error:
select l * 1 from big;

-- TEST: long * bool -> long (nullables)
-- + {select_stmt}: _select_: { _anon: longint }
-- + {select_from_etc}: TABLE { big: big }
-- - error:
select l * (1==1) from big;

-- TEST: long * real -> real (nullables)
-- + {select_stmt}: _select_: { _anon: real }
-- + {select_from_etc}: TABLE { big: big }
-- - error:
select l * 2.0 from big;

-- TEST: not x is an error, no cascade error reported just one error
-- + error: % required 'TEXT' not compatible with found 'INT' context '='
-- + {select_stmt}: err
-- + {not}: err
-- + {eq}: err
-- +1 error:
select not 'x' == 1;

-- TEST: `when` expression must be valid
-- + error: % right operand must be a string in 'LIKE'
-- +1 error:
select case
  when 'x' like 42 then 'foo'
end;

-- TEST: ok to have two different strings
-- note there was no else case, so nullable result
-- + {select_stmt}: _select_: { _anon: text }
-- + {case_list}: text
-- + {when}: text notnull
-- + {when}: text notnull
-- - error:
select case
  when 1 = 2 then 'foo'
  when 3 = 4 then 'bar'
end;

-- TEST: can't combine a string and a number
-- + error: % required 'TEXT' not compatible with found 'INT' context 'then'
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {case_list}: err
-- +1 error:
select case
  when 1 = 2 then 'foo'
  when 3 = 4 then 2
end;

-- TEST: when expression should be a boolean
-- + error: % required 'BOOL' not compatible with found 'TEXT' context 'when'
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {strlit 'x'}: err
-- +1 error:
select case
  when 'x' then 'foo'
end;

-- TEST: when expression cannot be a constant null — Not to be confused with else
-- + error: % WHEN expression must not be a constant NULL but can be of a nullable type
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {null}: null
-- +1 error:
select case "x"
  when null then 'foo'
  when "x" then 'foo'
  when "y" then 'bar'
end;

-- TEST: when expression cannot be a constant null — Not to be confused with else
-- + error: % WHEN expression must not be a constant NULL but can be of a nullable type
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {null}: null
-- +1 error:
select case
  when null then 'foo'
  when "x" then 'foo'
  when "y" then 'bar'
end;

-- TEST: ok to compare strings to each other
-- note the result type is nullable, there was no else case!
-- + {select_stmt}: _select_: { _anon: integer }
-- + {case_expr}: integer
-- - error:
select case 'x'
  when 'y' then 1
  when 'z' then 2
end;

-- TEST: ok to compare a real to an int
-- note the result type is nullable, there was no else case!
-- + {select_stmt}: _select_: { _anon: integer }
-- + {case_expr}: integer
-- - error:
select case 2
  when 1.0 then 1
  when 3 then 2
end;

-- TEST: can't compare a string and a number
-- + error: % required 'INT' not compatible with found 'TEXT' context 'when'
-- + {select_stmt}: err
-- + case_expr}: err
-- + {strlit 'x'}: err
-- +1 error:
select case 3
  when 'x' then 1
end;

-- TEST: int combines with real to give real
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {case_expr}: real notnull
-- - error:
select case 4
  when 1 then 1
  else 2.0
end;

-- TEST: null combines with int to give nullable int
-- + {select_stmt}: _select_: { _anon: integer }
-- + {case_expr}: integer
-- - {case_expr}: integer notnull
-- - error:
select case 5
  when 0 then null
  when 1 then 1
end;

-- TEST: real combines with real to give real
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {case_expr}: real notnull
-- - error:
select case 6
  when 0 then 1.0
  else 2.0
end;


-- TEST: bool combines with null to give nullable bool
-- + {select_stmt}: _select_: { _anon: bool }
-- + {case_expr}: bool
-- - {case_expr}: bool notnull
-- - error:
select case 7
  when 0 then (1==2)
  else null
end;

-- TEST: else statement not compatible type with when
-- + error: % required 'INT' not compatible with found 'TEXT' context 'else'
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {strlit 'bar'}: err
-- +1 error:
select case 8
  when 0 then 1
  else 'bar'
end;

-- TEST: case statement has expression type error
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {case_expr}: err
-- + {not}: err
-- +1 error:
select case NOT 'x'
when 1 then 0
end;

-- TEST: ranges ok as integer
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {between}: bool notnull
-- - error:
select 1 between 0 and 2;

-- TEST: ranges ok as string
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {between}: bool notnull
-- - error:
select 'x' between 'a' and 'z';

-- TEST: string cannot be compared to integers
-- + error: % required 'TEXT' not compatible with found 'INT' context 'BETWEEN'
-- + {select_stmt}: err
-- + {between}: err
-- +1 error:
select 'x' between 2 and 3;

-- TEST: string cannot be compared to integers -- second item
-- + error: % required 'TEXT' not compatible with found 'INT' context 'BETWEEN'
-- + {select_stmt}: err
-- + {between}: err
-- +1 error:
select 'x' between null and 3;

-- TEST: null can be compared to anything
-- note nullable result
-- + {select_stmt}: _select_: { _anon: bool }
-- + {between}: bool
-- - error:
select null between 1 and 2;

-- TEST: range items must be comparable to each other
-- + error: % required 'INT' not compatible with found 'TEXT' context 'BETWEEN/AND'
-- + {select_stmt}: err
-- + {between}: err
-- +1 error:
select null between 1 and 'x';

-- TEST: don't re-report errors if there is already a failure in the expression
-- Note: here we also verify that NOT is weaker than between hence requires the parens stay
-- + SELECT (NOT 'x') BETWEEN 1122 AND 3344;
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {between}: err
-- +1 error:
select (NOT 'x') between 1122 and 3344;

-- TEST: ranges ok as integer (NOT BETWEEN)
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {not_between}: bool notnull
-- - error:
select 1 not between 0 and 2;

-- TEST: ranges ok as string
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {not_between}: bool notnull
-- - error:
select 'x' not between 'a' and 'z';

-- TEST: string cannot be compared to integers
-- + error: % required 'TEXT' not compatible with found 'INT' context 'NOT BETWEEN'
-- + {select_stmt}: err
-- + {not_between}: err
-- +1 error:
select 'x' not between 2 and 3;

-- TEST: string cannot be compared to integers -- second item
-- + error: % required 'TEXT' not compatible with found 'INT' context 'NOT BETWEEN'
-- + {select_stmt}: err
-- + {not_between}: err
-- +1 error:
select 'x' not between null and 3;

-- TEST: null can be compared to anything
-- note nullable result
-- + {select_stmt}: _select_: { _anon: bool }
-- + {not_between}: bool
-- - error:
select null not between 1 and 2;

-- TEST: range items must be comparable to each other
-- + error: % required 'INT' not compatible with found 'TEXT' context 'NOT BETWEEN/AND'
-- + {select_stmt}: err
-- + {not_between}: err
-- +1 error:
select null not between 1 and 'x';

-- TEST: don't re-report errors if there is already a failure in the expression
-- Note: here we also verify that NOT is weaker than not between hence requires the parens stay
-- + SELECT (NOT 'x') NOT BETWEEN 1122 AND 3344;
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {not_between}: err
-- +1 error:
select (NOT 'x') not between 1122 and 3344;

-- TEST: nested select statement in the from clause
-- + {select_stmt}: _select_: { id: integer notnull, name: text notnull }
-- + {select_from_etc}: TABLE { Item: _select_ }
-- + {select_stmt}: _select_: { id: integer notnull, name: text notnull }
-- - error:
select * from ( select 1 as id, 'x' as name ) as Item;

-- TEST: nested select statement with join
-- + {select_stmt}: _select_: { id1: integer notnull, name: text notnull, id2: integer notnull, brand: text notnull }
-- + {select_stmt}: _select_: { id1: integer notnull, name: text notnull }
-- + {select_stmt}: _select_: { id2: integer notnull, brand: text notnull }
-- + {join_cond}: JOIN { Item: _select_, ItemBrand: _select_ }
-- - error:
select * from
( select 1 as id1, 'x' as name ) as Item
inner join (select 1 as id2, 'b' as brand) as ItemBrand
on ItemBrand.id2 = Item.id1;

-- TEST: nested select expression
-- + {select_stmt}: _select_: { result: integer notnull }
-- + {select_expr}: result: integer notnull
-- + {select_stmt}: unused: integer notnull
-- - error:
select (select 1 as unused) as result;

-- TEST: nested select expression with wrong # of items
-- + error: % nested select expression must return exactly one column
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {select_expr_list_con}: _select_: { _anon: integer notnull, _anon: integer notnull }
-- +1 error:
select (select 1, 2);

-- TEST: nested select used for simple math
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {select_expr}: integer notnull
-- - error:
select 1 * (select 1);

-- TEST: nested select used for string concat
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {select_expr}: integer notnull
-- - error:
select (select 1) || (select 2);

-- TEST: multiple table refs
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, name: text, rate: longint }
-- + {select_from_etc}: JOIN { foo: foo, bar: bar }
-- - error:
select * from (foo, bar);

-- TEST: duplicate table refs
-- + error: % duplicate table name in join 'foo'
-- + {select_stmt}: err
-- + {select_from_etc}: err
-- + {table_or_subquery}: TABLE { foo: foo }
-- + {table_or_subquery}: TABLE { foo: foo }
-- +1 error:
select * from (foo, foo);

-- TEST: full join with all expression options (except offset which was added later)
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, name: text, rate: longint }
-- + {opt_where}: bool notnull
-- + {opt_groupby}: ok
-- + {opt_having}: bool
-- + {opt_orderby}: ok
-- + {opt_limit}: integer notnull
-- - error:
select * from foo as T1
inner join bar as T2 on T1.id = T2.id
where T2.id > 5
group by T2.name
having T2.name = 'x'
order by T2.rate
limit 5;

-- TEST: join with bogus ON expression type
-- + error: % expected numeric expression 'ON'
-- + {select_stmt}: err
-- + {on}: err
-- +1 error:
select * from foo
inner join bar as T2 on 'v'
where 'w'
having 'x'
limit 'y';

-- TEST: join with bogus other expression types
--       one of few cases where error processing continues
-- + error: % expected numeric expression 'WHERE'
-- + error: % HAVING clause requires GROUP BY clause
-- + error: % expected numeric expression 'HAVING'
-- + {select_stmt}: err
-- +3 error:
select * from foo
where 'w'
having 'x'
limit 'y';

-- TEST: select with bogus order by x limit x
-- + error: % name not found 'bogus'
-- + error: % expected numeric expression 'LIMIT'
-- + {select_stmt}: err
-- +2 error:
select * from foo
order by bogus limit 'y';

-- TEST: force the case where a nested select has an error
--       the top level select should be marked with an error
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {select_stmt}: err
-- + {not}: err
-- +1 error:
select (select not 'x');

-- TEST: basic IN statement -- null is ok anywhere
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {in_pred}: bool notnull
-- +2 {int 1}: integer notnull
-- +1 {int 2}: integer notnull
-- + {null}: null
-- - error:
select 1 in (1, 2, null);

-- TEST: can't match strings against a number
-- + error: % required 'INT' not compatible with found 'TEXT' context 'IN'
-- + {select_stmt}: err
-- + {in_pred}: err
-- +1 error:
select 1 in ('x', 2);

-- TEST: simple string works
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- note null in the list changes nothing
-- + {in_pred}: bool notnull
-- +2 {strlit 'x'}: text notnull
-- +1 {strlit 'y'}: text notnull
-- +1 {null}: null
-- - error:
select 'x' in ('x', 'y', null);

-- TEST: string can't be matched against number
-- + error: % required 'TEXT' not compatible with found 'INT' context 'IN'
-- + {select_stmt}: err
-- + {in_pred}: err
-- +1 error:
select 'x' in ('x', 1);

-- TEST: null can match against numbers
-- nullable result! CG will make the answer null
-- + {select_stmt}: _select_: { _anon: bool }
-- + {expr_list}: integer notnull
-- - error:
select null in (1, 2);

-- TEST: null can match against strings
-- nullable result! CG will make the answer null
-- + {select_stmt}: _select_: { _anon: bool }
-- + {expr_list}: text notnull
-- - error:
select null in ('x', 'y', null);

-- TEST: numbers are ok and so are strings, but you can't mix and match
-- + error: % required 'INT' not compatible with found 'TEXT' context 'IN'
-- + {select_stmt}: err
-- + {in_pred}: err
-- +1 error:
select null in (1, 'x');

-- TEST: no casade errors if the left arg of in has an error
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {in_pred}: err
-- + {not}: err
-- +1 error:
select (not 'x') in (1, 'x');

-- TEST: no casade errors if the predicate has an error
-- "select distinct" used here just to force that option to run
-- semantic analysis does not care about it (so verify successfully ignored?)
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {in_pred}: err
-- + {not}: err
-- +1 error:
select distinct 1 in (1, not 'x', 'y');

-- TEST: basic NOT IN statement -- null is ok anywhere
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {not_in}: bool notnull
-- + {int 1}: integer notnull
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {null}: null
-- - error:
select 1 not in (1, 2, null);

-- TEST: can't match strings against a number
-- + error: % required 'INT' not compatible with found 'TEXT' context 'NOT IN'
-- + {select_stmt}: err
-- + {not_in}: err
-- +1 error:
select 1 not in ('x', 2);

-- TEST: simple string works
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- note null in the list changes nothing
-- + {not_in}: bool notnull
-- + {strlit 'x'}: text notnull
-- + {strlit 'x'}: text notnull
-- + {strlit 'y'}: text notnull
-- + {null}: null
-- - error:
select 'x' not in ('x', 'y', null);

-- TEST: string can't be matched against number
-- + error: % required 'TEXT' not compatible with found 'INT' context 'NOT IN'
-- + {select_stmt}: err
-- + {not_in}: err
-- +1 error:
select 'x' not in ('x', 1);

-- TEST: null can match against numbers
-- nullable result! CG will make the answer null
-- + {select_stmt}: _select_: { _anon: bool }
-- + {expr_list}: integer notnull
-- - error:
select null not in (1, 2);

-- TEST: null can match against strings
-- nullable result! CG will make the answer null
-- + {select_stmt}: _select_: { _anon: bool }
-- + {expr_list}: text notnull
-- - error:
select null not in ('x', 'y', null);

-- TEST: numbers are ok and so are strings, but you can't mix and match
-- + error: % required 'INT' not compatible with found 'TEXT' context 'NOT IN'
-- + {select_stmt}: err
-- + {not_in}: err
-- +1 error:
select null not in (1, 'x');

-- TEST: create a view
-- + {create_view_stmt}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- + {name MyView}
-- + {select_stmt}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- - error:
create view MyView as select 1 as f1, 2 as f2, 3 as f3;

-- TEST: create a view with column list
-- + {create_view_stmt}: AViewWithColSpec: { x: integer notnull, y: integer notnull }
-- - error:
create view AViewWithColSpec(x, y) as select 1, 2;

-- TEST: create a view with column list (too few columns)
-- + error: % too few column names specified in view 'AViewWithColSpec2'
-- + {create_view_stmt}: err
-- +1 error:
create view AViewWithColSpec2(x) as select 1, 2;

-- TEST: create a view with column list (too many columns)
-- + error: % too many column names specified in view 'AViewWithColSpec3'
-- + {create_view_stmt}: err
-- +1 error:
create view AViewWithColSpec3(x,y,z) as select 1, 2;

-- TEST: create a view with column list (duplicate columns)
-- + error: % duplicate name in list 'x'
-- + {create_view_stmt}: err
-- +1 error:
create view AViewWithColSpec3(x,x) as select 1, 2;

-- TEST: create a view with null columns
-- + error: % NULL expression has no type to imply the type of the select result '_anon'
-- + {create_view_stmt}: err
-- +1 error:
create view AViewWithColSpec3(x) as select NULL;

-- TEST: create a view -- exact duplicate is allowed
-- + {create_view_stmt}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- + {name MyView}
-- + {select_stmt}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- - error:
create view MyView as select 1 as f1, 2 as f2, 3 as f3;

-- TEST: try to use the view
-- + {select_stmt}: _select_: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- + select_from_etc}: TABLE { ViewAlias: MyView }
-- - error:
select f1, f2, ViewAlias.f3 from MyView as ViewAlias;

-- TEST: try to make a duplicate view (re-use a view)
-- + Incompatible declarations found
-- + CREATE VIEW MyView AS
-- + SELECT 1 AS f1, 2 AS f2, 3 AS f3
-- + CREATE VIEW MyView AS
-- + SELECT 1 AS y
-- + The above must be identical.
-- + error: % duplicate table/view name 'MyView'
--
-- + {create_view_stmt}: err
-- + {name MyView}: err
-- includes diagnostics
-- +3 error:
create view MyView as select 1 y;

-- TEST: try to make a duplicate view (re-use a table)
-- + Incompatible declarations found
-- + CREATE TABLE foo(
-- + id INT PRIMARY KEY AUTOINCREMENT
-- + )
-- + CREATE VIEW foo AS
-- + SELECT 2 AS x
-- + The above must be identical.
--
-- + error: % duplicate table/view name 'foo'
-- + {create_view_stmt}: err
-- +3 error:
create view foo as select 2 x;

-- TEST: no error cascade (one error, just the internal error)
-- + error: % string operand not allowed in 'NOT'
-- + {create_view_stmt}: err
-- - error: % duplicate
-- +1 error:
create view MyView as select NOT 'x';

-- TEST: this view create will fail with one error
-- + error: % string operand not allowed in 'NOT'
-- + {create_view_stmt}: err
-- + {not}: err
-- +1 error:
create view V as select NOT 'x';

-- TEST: can't select from V, it failed.
-- + error: % table/view not defined 'V'
-- + {select_stmt}: err
-- + {select_from_etc}: err
-- + {table_or_subquery}: err
-- +1 error:
select * from V;

-- TEST: create an index
-- + {create_index_stmt}: ok
-- + {name id}: id: integer notnull
-- - error:
create index index_1 on foo(id);

-- TEST: exact duplicate index is ok
-- + {create_index_stmt}: ok alias
-- + {name id}: id: integer notnull
-- - error:
create index index_1 on foo(id);

-- TEST: exact duplicate index is ok
-- + error: % migration proc not allowed on object 'index_4'
-- + {create_index_stmt}: err
-- +1 error:
create index index_4 on foo(id) @delete(1, AMigrateProc);

-- TEST: try to create a duplicate index
-- + error: % duplicate index name 'index_1'
-- + {create_index_stmt}: err
create index index_1 on bar(id);

-- TEST: try to create an index on a table that doesn't exist
-- + error: % create index table name not found 'doesNotExist'
-- + {create_index_stmt}: err
-- +1 error:
create index index_2 on doesNotExist(id);

-- TEST: try to create an index on columns that do not exist
-- + error: % name not found 'doesNotExist'
-- + {create_index_stmt}: err
-- + {name doesNotExist}: err
-- +1 error:
create index index_3 on foo(doesNotExist);

-- TEST: index on a basic expression
-- + CREATE INDEX index_4 ON foo (id + id);
-- + {create_index_stmt}: ok
-- - error:
create index index_4 on foo(id+id);

-- TEST: index on a bogus expression
-- + error: % string operand not allowed in 'NOT'
-- + {create_index_stmt}: err
-- +1 error:
create index index_5 on foo(not 'x');

-- TEST: duplicate expressions still give an error
-- + CREATE INDEX index_6 ON foo (id + id, id + id);
-- + error: % name list has duplicate name 'id + id'
-- + {create_index_stmt}: err
-- +1 error:
create index index_6 on foo(id+id, id+id);

-- TEST: partial index with valid expression
-- + CREATE INDEX index_7 ON foo (id + id)
-- + WHERE id < 100;
-- + {create_index_stmt}: ok
-- + {opt_where}: bool notnull
-- - error:
create index index_7 on foo(id+id) where id < 100;

-- TEST: partial index with invalid expression (semantic error)
-- + error: % string operand not allowed in 'NOT'
-- + {create_index_stmt}: err
-- + {opt_where}: err
-- +1 error:
create index index_8 on foo(id) where not 'x';

-- TEST: partial index with invalid expression (x not in scope)
-- + error: % name not found 'x'
-- + {create_index_stmt}: err
-- + {opt_where}: err
-- +1 error:
create index index_9 on foo(id) where x = 5;

-- TEST: partial index with invalid expression (not numeric)
-- + error: % expected numeric expression 'WHERE'
-- + {create_index_stmt}: err
-- + {opt_where}: err
-- +1 error:
create index index_10 on foo(id) where 'hi';

-- TEST: validate primary key columns, ok
-- + {create_table_stmt}: simple_pk_table: { id: integer notnull partial_pk }
-- - error:
create table simple_pk_table(
  id int!,
  PRIMARY KEY (id)
);

-- TEST: validate primary key columns, bogus name
-- + error: % name not found 'pk_col_not_exist'
-- + {create_table_stmt}: err
-- + {name pk_col_not_exist}: err
-- +1 error:
create table baz(
  id int!,
  PRIMARY KEY (pk_col_not_exist)
);

-- TEST: validate PK not duplicated
-- + error: % more than one primary key in table 'baz'
-- + {create_table_stmt}: err
-- +1 error:
create table baz(
  id int!,
  PRIMARY KEY (id),
  PRIMARY KEY (id)
);

-- TEST: validate simple unique key
-- + {create_table_stmt}: simple_ak_table: { id: integer notnull }
-- + {name ak1}
-- - error:
create table simple_ak_table (
  id int!,
  CONSTRAINT ak1 UNIQUE (id)
);

-- TEST: validate simple in group of unique key overlapping each others
-- + {create_table_stmt}: simple_ak_table_2: { a: integer notnull, b: text, c: real, d: longint }
-- - error:
create table simple_ak_table_2 (
  a int!,
  b text,
  c real,
  d long int,
  UNIQUE (a, b),
  UNIQUE (a, c),
  UNIQUE (d)
);

-- TEST: validate simple in group of unique key containing one column in common
-- + {create_table_stmt}: simple_ak_table_3: { a: integer notnull, b: text, c: real, d: longint }
-- - error:
create table simple_ak_table_3 (
  a int!,
  b text,
  c real,
  d long int,
  UNIQUE (a, b),
  UNIQUE (b, d)
);

-- TEST: invalidate unique key that is the subset (in order) of another, (a, b, c) is invalid because (a, b) is already unique key
-- + error: % at least part of this unique key is redundant with previous unique keys
-- + {create_table_stmt}: err
-- +1 error:
create table simple_ak_table_4 (
  a int!,
  b text,
  c real,
  UNIQUE (a, b),
  UNIQUE (a, b, c)
);

-- TEST: invalidate same column in two unique key, (b, a) is invalid because (a, b) is already unique key
-- + error: % at least part of this unique key is redundant with previous unique keys
-- + {create_table_stmt}: err
-- +1 error:
create table simple_ak_table_5 (
  a int!,
  b text,
  c real,
  d long int,
  UNIQUE (a, b),
  UNIQUE (b, a)
);

-- TEST: invalidate unique key that is the subset (at end) of another, (c, d, b, a) is invalid because subset (a, b) is already unique key
-- + error: % at least part of this unique key is redundant with previous unique keys
-- + {create_table_stmt}: err
-- +1 error:
create table simple_ak_table_6 (
  a int!,
  b text,
  c real,
  d long int,
  UNIQUE (a, b),
  UNIQUE (c, d, b, a)
);

-- TEST: invalidate unique key that is the subset (at start) of another, (a, b) is invalid because (a) is unique key
-- + error: % at least part of this unique key is redundant with previous unique keys
-- + {create_table_stmt}: err
-- +1 error:
create table simple_ak_table_7 (
  a int!,
  b text,
  c real,
  d long int,
  UNIQUE (a, b),
  UNIQUE (a)
);

-- TEST: validate unique key expression
-- + CONSTRAINT ak1 UNIQUE (id / 2)
-- + {create_table_stmt}: baz_expr_uk: { id: integer notnull primary_key autoinc }
-- - error:
create table baz_expr_uk (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  CONSTRAINT ak1 UNIQUE (id/2)
);

-- TEST: unique key expression is bogus
-- + CONSTRAINT ak1 UNIQUE (random())
-- + error: % function may not appear in this context 'random'
-- + {create_table_stmt}: err
-- +1 error:
create table baz_expr_uk_bogus (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  CONSTRAINT ak1 UNIQUE (random())
);

-- TEST: validate primary key expression
-- + CONSTRAINT pk1 PRIMARY KEY (id / 2)
-- note id was not converted to 'not null' because constraint id+1 does not match column id
-- + {create_table_stmt}: baz_expr_pk: { id: integer }
-- - error:
create table baz_expr_pk (
  id integer,
  CONSTRAINT pk1 PRIMARY KEY (id/2)
);

-- TEST: primary key expression is bogus
-- + CONSTRAINT pk1 PRIMARY KEY (random())
-- + error: % function may not appear in this context 'random'
-- + {create_table_stmt}: err
-- +1 error:
create table baz_expr_uk_bogus (
  id integer,
  CONSTRAINT pk1 PRIMARY KEY (random())
);

-- TEST: validate duplicate unique key
-- + error: % duplicate constraint name in table 'ak1'
-- + {create_table_stmt}: err
-- +1 error:
create table baz_dup_uk (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  CONSTRAINT ak1 UNIQUE (id),
  CONSTRAINT ak1 UNIQUE (id)
);

-- TEST: validate duplicate primary unique key
-- + error: % duplicate constraint name in table 'pk1'
-- + {create_table_stmt}: err
-- +1 error:
create table baz_dup_pk (
  id int!,
  CONSTRAINT pk1 PRIMARY KEY (id),
  CONSTRAINT pk1 PRIMARY KEY (id)
);

-- TEST: validate duplicate in group of unique key
-- + error: % at least part of this unique key is redundant with previous unique keys
-- + {create_table_stmt}: err
-- +1 error:
create table baz_2 (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  name text,
  UNIQUE (id, name),
  UNIQUE (name, id)
);

-- TEST: validate unique key columns
-- + error: % name not found 'ak_col_not_exist'
-- + {create_table_stmt}: err
-- + {name ak_col_not_exist}: err
-- +1 error:
create table baz (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  CONSTRAINT ak1 UNIQUE (ak_col_not_exist)
);

-- TEST: validate group of unique key columns
-- + error: % name not found 'ak_col_not_exist'
-- + {create_table_stmt}: err
-- + {name ak_col_not_exist}: err
-- +1 error:
create table baz_3 (
  id integer PRIMARY KEY AUTOINCREMENT not null,
  UNIQUE (ak_col_not_exist)
);

-- TEST: make a valid FK
-- + {create_table_stmt}: fk_table: { id: integer foreign_key }
-- + {name_list}
-- + {name id}: id: integer
-- + {name_list}
-- + {name id}: id: integer
-- - error:
create table fk_table (
  id integer,
  FOREIGN KEY (id) REFERENCES foo(id)
);

-- TEST: make a valid FK
-- + error: % duplicate constraint name in table 'x'
-- + {create_table_stmt}: err
-- + {fk_def}: ok
-- + {name x}
-- + {fk_def}
-- + {name x}
-- +1 error:
create table fk_table_dup (
  id integer,
  constraint x foreign key (id) references foo(id),
  constraint x foreign key (id) references foo(id)
);

-- TEST: make an FK that refers to a bogus column in the current table
-- + error: % name not found 'bogus'
-- + {create_table_stmt}: err
-- +1 error:
create table baz (
  id integer,
  FOREIGN KEY (bogus) REFERENCES foo(id)
);

-- TEST: make an FK that refers to a bogus column in the reference table
-- + error: % name not found 'bogus'
-- + {create_table_stmt}: err
-- +1 error:
create table baz (
  id integer,
  FOREIGN KEY (id) REFERENCES foo(bogus)
);

-- TEST: make an FK that refers to a bogus table
-- + error: % foreign key refers to non-existent table 'bogus'
-- + {create_table_stmt}: err
-- +1 error:
create table baz (
  id integer,
  FOREIGN KEY (id) REFERENCES bogus(id)
);

-- TEST: well formed if statement
-- + {if_stmt}: integer notnull
-- + {cond_action}: integer notnull
-- + {stmt_list}: ok
-- + {if_alt}: ok
-- + {else}: ok
-- + {stmt_list}: ok
-- - error:
if 1 then
  select 1;
else
  select 2;
end if;

-- TEST: if with bad predicate
-- + error: % expected numeric expression in IF predicate
-- + {if_stmt}: err
-- + {cond_action}: err
-- - {stmt_list}: err
-- +1 error:
if 'x' then
  select 1;
end if;

-- TEST: if with error predicate, no double error reporting
-- + error: % string operand not allowed in 'NOT'
-- + {if_stmt}: err
-- + {cond_action}: err
-- - {stmt_list}: err
-- +1 error:
if not 'x' then
  select 1;
end if;

-- TEST: if with bogus statement list, no double error reporting
-- + error: % string operand not allowed in 'NOT'
-- + {if_stmt}: err
-- + {cond_action}: err
-- + {stmt_list}: err
-- +1 error:
if 1 then
  select not 'x';
end if;

-- TEST: if with bogus statement list in else block, no double error reporting
-- + error: % string operand not allowed in 'NOT'
-- + {if_stmt}: err
-- + {cond_action}: integer notnull
-- + {if_alt}: err
-- + {else}: err
-- +1 error:
if 1 then
  select 1;
else
  select not 'x';
end if;

-- TEST: if with else if clause
-- + {if_stmt}: integer notnull
-- + {cond_action}: integer notnull
-- + {if_alt}: ok
-- + {elseif}: integer notnull
-- + {cond_action}: integer notnull
-- + {else}: ok
-- - error:
if 1 then
 select 1;
else if 2 then
 select 2;
else
 select 3;
end if;

-- TEST: if with else if clause bogus expression type
-- + error: % expected numeric expression in IF predicate
-- + {if_stmt}: err
-- + {cond_action}: integer notnull
-- + {if_alt}: err
-- + {cond_action}: err
-- +1 error:
if 1 then
 select 1;
else if '2' then
 select 2;
else
 select 3;
end if;

-- TEST: create an error down the else if list and make sure it props to the front of the list
--       that causes the whole statement to be correctly reported as having an error
-- + error: % expected numeric expression in IF predicate
-- +1 {if_stmt}: err
-- +1 {if_alt}: err
-- +3 {cond_action}: integer notnull
-- +1 {cond_action}: err
-- +1 error:
if 1 then
  select 1;
else if 2 then
  select 2;
else if 3
  then select 3;
else if '4'
  then select 4;
end if;

-- TEST: force an error in the group by clause, this error must spoil the whole statement
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {opt_groupby}: err
-- +1 error:
select id from foo group by id, not 'x';

-- TEST: force an error in the order by clause, this error must spoil the whole statement
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {opt_orderby}: err
-- +1 error:
select id from foo order by id, not 'x';

-- TEST: smallish table to cover some missing cases, bool field and an int with default
-- + {create_table_stmt}: booly: { id: integer has_default, flag: bool }
-- - error:
create table booly (
  id integer DEFAULT 8675309,
  flag BOOL
);

enum ints integer (
 negative_one = -1,
 postive_one = 1
);

-- TEST: use const expr where normally literals go in default value
-- + x INT DEFAULT -1,
-- + y INT DEFAULT CONST(1 / 0)
-- + error: % evaluation of constant failed
-- + {col_attrs_default}: err
-- + {const}: err
-- +1 error:
create table bad_constants_table(
  x integer default const(ints.negative_one),
  y integer default const(1/0)
);

-- TEST: this should be of type bool not type int
-- rewritten as "TRUE"
-- this proves that we can correctly produce the semantic type bool from the bool literal
-- + LET bool_x := TRUE;
-- + {let_stmt}: bool_x: bool notnull variable
-- - error:
let bool_x := const(1==1);

@enforce_strict is true;

-- TEST: strict mode for is true disables is true
-- + error: % Operator may not be used because it is not supported on old versions of SQLite 'IS TRUE'
-- + {assign}: err
-- +1 error:
set bool_x := 1 is true;

-- TEST: strict mode for is true disables is false
-- + error: % Operator may not be used because it is not supported on old versions of SQLite 'IS FALSE'
-- + {assign}: err
-- +1 error:
set bool_x := 1 is false;

-- TEST: strict mode for is true disables is not true
-- + error: % Operator may not be used because it is not supported on old versions of SQLite 'IS NOT TRUE'
-- + {assign}: err
-- +1 error:
set bool_x := 1 is not true;

-- TEST: strict mode for is true disables is not false
-- + error: % Operator may not be used because it is not supported on old versions of SQLite 'IS NOT FALSE'
-- + {assign}: err
-- +1 error:
set bool_x := 1 is not false;

@enforce_normal is true;

-- TEST: 2 is true
-- rewritten as "TRUE"
-- + SET bool_x := TRUE;
-- - error:
set bool_x := const(2 is true);

-- TEST: 2 is true
-- rewritten as "FALSE"
-- + SET bool_x := FALSE;
-- - error:
set bool_x := const(2 is not true);

-- TEST: eval error bubbles up
-- + SET bool_x := CONST(1 / 0 IS TRUE);
-- + error: % evaluation of constant failed
-- + {assign}: err
set bool_x := const(1/0 is true);

-- TEST: true is not 2 --> this is true is an operator
-- rewritten as "FALSE"
-- + SET bool_x := FALSE;
-- - error:
set bool_x := const(true is 2);

-- TEST: null is not true
-- rewritten as "FALSE"
-- + SET bool_x := FALSE;
-- - error:
set bool_x := const(null is true);

-- TEST: null is not true
-- rewritten as "TRUE"
-- + SET bool_x := TRUE;
-- - error:
set bool_x := const(null is not true);

-- TEST: 0 is false
-- rewritten as "TRUE"
-- + SET bool_x := TRUE;
-- - error:
set bool_x := const(0 is false);

-- TEST: 0 is not false
-- rewritten as "FALSE"
-- + SET bool_x := FALSE;
-- - error:
set bool_x := const(0 is not false);

-- TEST: null is not false
-- rewritten as "TRUE"
-- + SET bool_x := TRUE;
-- - error:
set bool_x := const(null is not false);

-- TEST: 1/0 is not false -> error
-- not rewritten due to error
-- + SET bool_x := CONST(1 / 0 IS NOT FALSE);
-- + error: % evaluation of constant failed
-- + {assign}: err
-- +1 error:
set bool_x := const(1/0 is not false);

-- TEST: 1/0 is not false -> error
-- not rewritten due to error
-- + SET bool_x := CONST(1 / 0 IS NOT TRUE);
-- + error: % evaluation of constant failed
-- + {assign}: err
-- +1 error:
set bool_x := const(1/0 is not true);

-- TEST: null is not false
-- rewritten as FALSE
-- + SET bool_x := FALSE;
-- - error:
set bool_x := const(null is false);

-- TEST: eval error bubbles up
-- + SET bool_x := CONST(1 / 0 IS FALSE);
-- + error: % evaluation of constant failed
-- + {assign}: err
-- +1 error:
set bool_x := const(1/0 is false);

-- TEST: internal const expression
-- the internal const(1==1) is evaluated to a literal which then is used by the outer const
-- the result must still be bool, this proves that we can correctly eval the type of
-- an internal bool literal
-- + LET bool_x2 := TRUE;
-- + {let_stmt}: bool_x2: bool notnull variable
-- - error:
let bool_x2 := const(const(1==1));

-- TEST: use const expr where literals go in attribute
-- + @ATTRIBUTE(whatever=-1)
-- + @ATTRIBUTE(whatever=CONST(1 / 0))
-- + error: % evaluation of constant failed
-- + {const}: err
@attribute(whatever=const(ints.negative_one))
@attribute(whatever=const(1/0))
declare proc bad_constants_proc();

-- TEST: use bad constant expr in nested context
-- + @ATTRIBUTE(whatever=(1, CONST(1 / 0), 1))
-- + error: % evaluation of constant failed
-- + {const}: err
@attribute(whatever=(1, const(1/0), 1))
declare proc bad_constants_nested_proc();

-- TEST: try to use a NULL default value on a non nullable column
-- + error: % cannot assign/copy possibly null expression to not null target 'default value'
-- + {create_table_stmt}: err
-- + {col_def}: err
-- +1 error:
create table bad_conversions(
  data int! default const(NULL)
);

-- TEST: try to use a lossy conversion in a const expr default value
-- + error: % lossy conversion from type 'REAL' in 2.200000e+00
-- + {create_table_stmt}: err
-- + {col_def}: err
-- +1 error:
create table bad_conversions(
  data int! default const(1 + 1.2)
);

-- TEST: allowable conversion, the constant becomes real
-- + data REAL! DEFAULT 1
-- - error:
create table good_conversions(
  data real! default const(1)
);

-- TEST: TRUE constant
-- + {let_stmt}: tru: bool notnull variable
-- - error:
LET tru := true;

-- TEST: FALSE constant
-- + {let_stmt}: fal: bool notnull variable
-- - error:
LET fal := false;

-- TEST: Use TRUE and FALSE in a const expr
-- + {assign}: fal: bool notnull variable
-- - error:
SET fal := const(FALSE AND TRUE);

-- TEST: verify the correct types are extracted, also cover the final select option
-- + {select_stmt}: _select_: { id: integer, flag: bool }
-- + {select_opts}
-- + {distinctrow}
-- - error:
select distinctrow id, flag from booly;

-- TEST: make variables (X/Y are nullable)
-- + {declare_vars_type}: integer
-- + {name X}: X: integer variable
-- + {name Y}: Y: integer variable
-- - error:
declare X, Y integer;

-- TEST: make variables (X/Y are not null)
-- - error:
declare X_not_null int!;

-- TEST: try to declare X again
-- + error: % duplicate variable name in the same scope 'X'
-- +1 error:
-- + {declare_vars_type}: err
-- + {name X}: err
declare X integer;

-- TEST: use the result code helper
-- + SET X := @RC;
-- + {assign}: X: integer variable
-- + {name @RC}: @rc: integer notnull variable
-- - error:
set X := @RC;

-- TEST: try to declare a variable that hides a table
-- + error: % global variable hides table/view name 'foo'
-- + {declare_vars_type}: err
-- + {name foo}: err
-- +1 error:
declare foo integer;

-- TEST: try to access a variable
-- + {select_stmt}: _select_: { Y: integer variable }
-- + {name Y}: Y: integer variable
-- - error:
select Y;

-- TEST: create a cursor with select statement
-- + {declare_cursor}: my_cursor: _select_: { one: integer notnull, two: integer notnull } variable
-- - error:
cursor my_cursor for select 1 as one, 2 as two;

-- TEST: create a cursor with primitive kinds
-- + {declare_cursor}: kind_cursor: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars> } variable
-- - error:
cursor kind_cursor for select * from with_kind;

-- TEST: make a value cursor of the same shape
-- + {declare_cursor_like_name}: kind_value_cursor: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars> } variable shape_storage value_cursor
-- - error:
cursor kind_value_cursor like kind_cursor;

-- TEST: make a value cursor extending the above using typed names syntax
-- verify the rewrite also
-- + CURSOR extended_cursor LIKE (id INT<some_key>, cost REAL<dollars>, value REAL<dollars>, xx REAL, yy TEXT);
-- + {declare_cursor_like_typed_names}: extended_cursor: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars>, xx: real, yy: text } variable shape_storage value_cursor
-- + {name extended_cursor}: extended_cursor: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars>, xx: real, yy: text } variable shape_storage value_cursor
-- + {typed_names}: _select_: { id: integer<some_key>, cost: real<dollars>, value: real<dollars>, xx: real, yy: text }
-- - error:
cursor extended_cursor like ( like kind_value_cursor, xx real, yy text);

-- TEST: restriction syntax with duplicate name
-- + error: % duplicate name in list 'id'
-- + {declare_cursor_like_name}: err
-- +1 error:
cursor reduced_cursor like extended_cursor(id, id);

-- TEST: restriction syntax with bogus name
-- + error: % name not found 'not_a_valid_name'
-- + {declare_cursor_like_name}: err
-- +1 error:
cursor reduced_cursor like extended_cursor(id, not_a_valid_name);

-- TEST: now use the restriction syntax to get a smaller cursor
-- + {declare_cursor_like_name}: reduced_cursor: _select_: { id: integer<some_key>, cost: real<dollars> } variable shape_storage value_cursor
-- + {name reduced_cursor}: reduced_cursor: _select_: { id: integer<some_key>, cost: real<dollars> } variable shape_storage value_cursor
-- + {shape_def}: _select_: { id: integer<some_key>, cost: real<dollars> }
-- - error:
cursor reduced_cursor like extended_cursor(id, cost);

-- TEST: try to make a shape with both additive and subtractive form
-- + error: % mixing adding and removing columns from a shape 'cost'
-- + {declare_cursor_like_name}: err
-- + {shape_def}: err
-- +1 error:
cursor reduced_cursor2 like extended_cursor(-id, cost);

-- TEST: try to make a cursor by removing columns
-- + {shape_def}: _select_: { cost: real<dollars>, value: real<dollars>, xx: real, yy: text }
-- - error:
cursor reduced_cursor3 like extended_cursor(-id);

-- TEST: try to make a cursor by removing columns but remove everything
-- + error: % no columns were selected in the LIKE expression
-- + {declare_cursor_like_name}: err
-- +1 error:
cursor reduced_cursor4 like extended_cursor(-id, -xx, -yy, -value, -cost);

-- TEST: try to create a duplicate cursor
-- + error: % duplicate variable name in the same scope 'my_cursor'
-- + {declare_cursor}: err
-- + {name my_cursor}: err
-- +1 error:
cursor my_cursor for select 1;

-- TEST: try to create a duplicate cursor using like syntax
-- + error: % duplicate variable name in the same scope 'extended_cursor'
-- + {declare_cursor_like_typed_names}: err
-- +1 error
cursor extended_cursor like ( x integer );

-- TEST: the select statement is bogus, error cascade halted so the duplicate name is not reported
-- - duplicate
-- + error: % string operand not allowed in 'NOT'
-- + {declare_cursor}: err
-- + {select_stmt}: err
-- + {not}: err
-- +1 error:
cursor my_cursor for select not 'x';

-- TEST: the type list is bogus, this fails before the duplicate name detection
-- + error: % duplicate column name 'x'
-- + {declare_cursor_like_typed_names}: err
-- +1 error
cursor extended_cursor like ( x integer, x integer );

-- TEST: standard loop with leave
-- + {loop_stmt}: ok
-- + {leave_stmt}: ok
-- - error:
loop fetch my_cursor into X, Y begin
  leave;
end;

-- TEST: loop with leave, leave not the last statement
-- + error: in leave_stmt % statement should be the last thing in a statement list
-- + {leave_stmt}: err
-- + {leave_stmt}: ok
-- +1 error:
while 1
begin
  leave;
  leave;
end;

-- TEST: loop with continue, continue not the last statement
-- + error: in continue_stmt % statement should be the last thing in a statement list
-- + {continue_stmt}: err
-- + {leave_stmt}: ok
-- +1 error:
while 1
begin
  continue;
  leave;
end;

-- TEST: standard loop with continue
-- + {loop_stmt}: ok
-- + {continue_stmt}: ok
-- - error:
loop fetch my_cursor into X, Y begin
  continue;
end;

-- TEST: try to loop over a scalar
-- + error: % not a cursor 'X'
-- + {loop_stmt}: err
-- + {fetch_stmt}: err
-- + {name X}: err
-- +1 error:
loop fetch X into y begin
  leave;
end;

-- TEST: try to loop over something that isn't present
-- + error: % name not found 'not_a_variable'
-- + {loop_stmt}: err
-- + {fetch_stmt}: err
-- + {name not_a_variable}: err
-- +1 error:
loop fetch not_a_variable into x
begin
  leave;
end;

-- TEST: try to leave outside of a loop
-- + error: % leave must be inside of a 'loop', 'while', or 'switch' statement
-- + {leave_stmt}: err
-- +1 error:
leave;

-- TEST: try to continue outside of a loop
-- + error: % continue must be inside of a 'loop' or 'while' statement
-- + {continue_stmt}: err
-- +1 error:
continue;

-- TEST: legal return out of a procedure
-- we have to check the next statement and that is tricky if there was
-- attribute;  this tests that case.
-- + {return_stmt}: ok
-- - error:
proc return_with_attr()
begin
  if 1 then
    @attribute(goo)
    return;
  end if;
end;

-- TEST: proc uses @rc and becomes a dml proc
-- note this is now a dml_proc (!)
-- + {create_proc_stmt}: ok dml_proc
-- + {assign}: result_code: integer notnull variable out
-- + {name @RC}: @rc: integer notnull variable
-- - error:
proc using_rc(out result_code int!)
begin
  set result_code := @rc;
end;

-- TEST: legal return, no attribute on the return this time
-- + {return_stmt}: ok
-- - error:
proc return_no_attr()
begin
  if 1 then
    return;
  end if;
end;

-- TEST: return must be the last statement (attr form)
-- + error: in return_stmt % statement should be the last thing in a statement list
-- + {create_proc_stmt}: err
-- + {return_stmt}: err
-- + {return_stmt}: ok
-- +1 error:
proc return_not_last_with_attr()
begin
  if 1 then
    @attribute(goo)
    return;
    return;
  end if;
end;

-- TEST: return must be the last statement (no attr form)
-- + error: in return_stmt % statement should be the last thing in a statement list
-- + {create_proc_stmt}: err
-- + {return_stmt}: err
-- + {return_stmt}: ok
-- +1 error:
proc return_not_last_no_attr()
begin
  if 1 then
    return;
    return;
  end if;
end;

-- TEST: return outside of any proc
-- + error: % return statement should be in a procedure and not at the top level
-- + {return_stmt}: err
-- +1 error:
return;

-- TEST: return at top level, that's just goofy
-- + error: % return statement should be in a procedure and not at the top level
-- + {create_proc_stmt}: err
-- + {return_stmt}: err
-- +1 error:
proc return_at_top_level()
begin
  return;
end;

-- TEST: loop must prop errors inside it up so the overall loop is a semantic failure
-- + error: % string operand not allowed in 'NOT'
-- + {loop_stmt}: err
-- +1 error:
loop fetch my_cursor into X, Y
begin
 select not 'X';
end;

-- TEST: close a valid cursor
-- + {close_stmt}: my_cursor: _select_: { one: integer notnull, two: integer notnull } variable
-- - error:
close my_cursor;

-- TEST: close invalid cursor
-- + error: % not a cursor 'X'
-- + {close_stmt}: err
-- + {name X}: err
-- +1 error:
close X;

-- TEST: close boxed cursor
-- + error: % CLOSE cannot be used on a boxed cursor 'C'
-- + {close_stmt}: err
-- +1 error:
proc close_boxed_cursor(in box object<foo cursor>)
begin
  cursor C for box;
  close C;
end;

func get_boxed_cursor() object<foo cursor>;

-- TEST: use boxed cursor from an expression
-- + {declare_cursor}: C: foo: { id: integer notnull primary_key autoinc } variable boxed
-- + {call}: object<foo CURSOR>
-- - error:
proc boxed_cursor_expr()
begin
  cursor C for get_boxed_cursor();
end;

-- TEST: use boxed cursor from a bogus expression
-- + error: % expression must be of type object<T cursor> where T is a valid shape name '12'
-- + {declare_cursor}: err
-- +1 error:
proc bogus_boxed_cursor_expr()
begin
  cursor C for 12;
end;

-- TEST: a working delete
-- + {delete_stmt}: ok
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- + {opt_where}: bool notnull
-- - error:
delete from foo where id = 33;

-- TEST: delete from bogus table
-- + error: % table in delete statement does not exist 'bogus_table'
-- + {delete_stmt}: err
-- +1 error:
delete from bogus_table;

-- TEST: delete from a view
-- + error: % cannot delete from a view 'MyView'
-- + {delete_stmt}: err
-- +1 error:
delete from MyView;

-- TEST: delete with bogus expression
-- + error: % name not found 'missing_column'
-- + {delete_stmt}: err
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- + {name missing_column}: err
-- +1 error:
delete from foo where missing_column = 1;

-- TEST: regular insert
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 1}: integer notnull
-- + {strlit 'bazzle'}: text notnull
-- + {int 3}: integer notnull
-- - error:
insert into bar values (1, 'bazzle', 3);

-- TEST: replace statement
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 1}: integer notnull
-- + {strlit 'bazzle'}: text notnull
-- + {int 3}: integer notnull
-- - error:
replace into bar values (1, 'bazzle', 3);

-- TEST: insert or fail
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 1}: integer notnull
-- + {strlit 'bazzle'}: text notnull
-- + {int 3}: integer notnull
-- - error:
insert or fail into bar values (1, 'bazzle', 3);

-- TEST: insert or rollback
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 1}: integer notnull
-- + {strlit 'bazzle'}: text notnull
-- + {int 3}: integer notnull
-- - error:
insert or rollback into bar values (1, 'bazzle', 3);

-- TEST: insert or abort
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 1}: integer notnull
-- + {strlit 'bazzle'}: text notnull
-- + {int 3}: integer notnull
-- - error:
insert or abort into bar values (1, 'bazzle', 3);

-- TEST: insert default values
-- + {insert_stmt}: ok
-- + {name_columns_values}
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- + {default_columns_values}
-- - error:
insert into foo default values;

-- TEST: insert default values
-- + error: % mandatory column with no default value in INSERT INTO name DEFAULT VALUES statement 'id'
-- + {insert_stmt}: err
-- +1 error:
insert into bar default values;

-- TEST: insert into a table that isn't there
-- + error: % table in insert statement does not exist 'bogus_table'
-- + {insert_stmt}: err
-- + {name bogus_table}
-- +1 error:
insert into bogus_table values (1);

-- TEST: insert into a view
-- + error: % cannot insert into a view 'MyView'
-- + {insert_stmt}: err
-- + {name MyView}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- +1 error:
insert into MyView values (1);

-- TEST: insert with errors -- note that id is a field name of bar but it must not be found
-- + error: % name not found 'id'
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {name id}: err
-- +1 error:
insert into bar values (id, 'bazzle', 3);

-- TEST: insert into foo, one column, it is autoinc, so use NULL
-- + {insert_stmt}: ok
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- - error:
insert into foo values (NULL);

-- TEST: insert into bar, type mismatch
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {strlit 'string is wrong'}: err
-- +1 error:
insert into bar values ('string is wrong', 'string', 1);

-- TEST: insert into bar, type mismatch, 2 is wrong
-- + error: % required 'TEXT' not compatible with found 'INT' context 'name'
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {int 2}: err
-- +1 error:
insert into bar values (1, 2, 3);

-- TEST: insert too many columns
-- + error: % count of columns differs from count of values
-- + {insert_stmt}: err
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- +1 error:
insert into foo values (NULL, 2);

-- TEST: insert too few columns
-- + error: % select statement with VALUES clause requires a non empty list of values
-- + {insert_stmt}: err
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- + {select_stmt}: err
-- + {select_core}: err
-- +1 error:
insert into foo values ();

-- TEST: insert into bar, null not allowed in non-null field
-- + error: % cannot assign/copy possibly null expression to not null target 'id'
-- +1 error:
-- + {insert_stmt}: err
insert into bar values (null, 'string', 1);

-- TEST: table cannot have more than one autoinc
-- + error: % table can only have one autoinc column 'id2'
-- + {create_table_stmt}: err
-- +1 error:
create table two_autoincs_is_bad(
  id1 integer PRIMARY KEY AUTOINCREMENT not null,
  id2 integer PRIMARY KEY AUTOINCREMENT not null
);

-- TEST: valid assignment
-- + {assign}: X: integer variable
-- - error:
set X := 1;

-- TEST: bogus variable name
-- + error: % variable not found 'XX'
-- + {assign}: err
-- + {name XX}
-- +1 error:
set XX := 1;

-- TEST: try to assign a cursor
-- + error: % cannot set a cursor 'my_cursor'
-- + {assign}: err
-- + {name my_cursor}: my_cursor: _select_: { one: integer notnull, two: integer notnull } variable
-- +1 error:
set my_cursor := 1;

-- TEST: variable type mismatch
-- + error: % required 'INT' not compatible with found 'TEXT' context 'X'
-- + {assign}: err
-- + {name X}: err
-- +1 error:
set X := 'x';

-- TEST: null ok with everything
-- + {assign}: X: integer variable
-- + {null}: null
-- - error:
set X := null;

-- TEST: error propagates up, no other reported error
-- + error: % string operand not allowed in 'NOT'
-- + {assign}: err
-- + {not}: err
-- +1 error:
set X := not 'x';

-- TEST: simple cursor and fetch test
-- + {declare_cursor}: fetch_cursor: _select_: { _anon: integer notnull, _anon: text notnull, _anon: null } variable
-- - error:
cursor fetch_cursor for select 1, 'foo', null;

-- setup variables for the upcoming tests
declare an_int integer;
declare an_int2 integer;
declare a_string text;
declare a_string2 text;
declare a_nullable text;
declare an_long long integer;

-- TEST: ok to fetch_stmt
-- + {fetch_stmt}: fetch_cursor: _select_: { _anon: integer notnull, _anon: text notnull, _anon: null } variable
-- + {name an_int}: an_int: integer variable
-- + {name a_string}: a_string: text variable
-- + {name a_nullable}: a_nullable: text variable
-- - error:
fetch fetch_cursor into an_int, a_string, a_nullable;

-- TEST: fetch too few columns
-- + error: % number of variables did not match count of columns in cursor 'fetch_cursor'
-- + {fetch_stmt}: err
-- +1 error:
fetch fetch_cursor into an_int, a_string;

-- TEST: fetch too many columns
-- + error: % number of variables did not match count of columns in cursor 'fetch_cursor'
-- + {fetch_stmt}: err
-- +1 error:
fetch fetch_cursor into an_int, a_string, a_nullable, a_string2;

-- TEST: fetch an int into a string
-- + error: % required 'TEXT' not compatible with found 'INT' context 'a_string2'
-- + {fetch_stmt}: err
-- + {name a_string2}: err
-- +1 error:
fetch fetch_cursor into a_string2, a_string, a_nullable;

-- TEST: fetch a string into an int
-- + error: % required 'INT' not compatible with found 'TEXT' context 'an_int2'
-- + {fetch_stmt}: err
-- + {name an_int2}: err
-- +1 error:
fetch fetch_cursor into an_int, an_int2, a_nullable;

-- TEST: fetch using a bogus cursor
-- + error: % name not found 'not_a_cursor'
-- + {fetch_stmt}: err
-- + {name not_a_cursor}: err
-- +1 error:
fetch not_a_cursor into i;

-- TEST: fetch into a variable that doesn't exist
-- + error: % FETCH variable not found 'non_existent_variable'
-- + {fetch_stmt}: err
-- +1 error:
fetch fetch_cursor into non_existent_variable;

-- TEST: fetch into variables, duplicate in the list
-- + error: % duplicate name in list 'var_id'
-- + {fetch_stmt}: err
-- + {name fetch_cursor}
-- + {name var_id}
-- + {name var_id}
-- +1 error:
fetch fetch_cursor into var_id, var_id;

-- TEST: create an index, duplicate name in index list
-- + error: % name list has duplicate name 'id'
-- + {create_index_stmt}: err
-- + {name index_7}
-- + {name foo}
-- + {indexed_columns}: err
-- + {name id}: id: integer notnull
-- + {name id}: err
-- +1 error:
create index index_7 on foo(id, id);

-- TEST: validate no duplictes allowed in unique key
-- + error: % name list has duplicate name 'key_id'
-- + {create_table_stmt}: err
-- key_id shows up in its definition once, then 2 more times due to duplication
-- + {name key_id}
-- + {unq_def}
-- + {name key_id}: key_id: integer notnull
-- + {name key_id}: err
-- +1 error:
create table bad_table (
  key_id integer PRIMARY KEY AUTOINCREMENT not null,
  CONSTRAINT ak1 UNIQUE (key_id, key_id)
);

-- TEST: validate no duplictes allowed in group of unique key
-- + error: % name list has duplicate name 'key_id'
-- + {create_table_stmt}: err
-- key_id shows up in its definition once, then 2 more times due to duplication
-- + {name key_id}
-- + {unq_def}
-- + {name key_id}: key_id: integer notnull
-- + {name key_id}
-- +1 error:
create table bad_table_2 (
  key_id integer PRIMARY KEY AUTOINCREMENT not null,
  UNIQUE (key_id, key_id)
);

-- TEST: make an FK with duplicate id in the columns
-- + error: % name list has duplicate name 'col_id'
-- + {create_table_stmt}: err
-- col_id shows up in its definition once, then 2 more times due to duplication
-- + {name col_id}
-- + {fk_def}
-- + {name col_id}: col_id: integer
-- + {name col_id}: err
-- +1 error:
create table bad_table (
  col_id integer,
  FOREIGN KEY (col_id, col_id) REFERENCES foo(id)
);

create table ref_target (
  ref_id1 integer,
  ref_id2 integer
);

-- TEST: make an FK with duplicate id in the reference columns
-- + error: % name list has duplicate name 'ref_id1'
-- + {create_table_stmt}: err
-- + {fk_target}
-- + {name ref_id1}
-- + {name ref_id1}
-- +1 error:
create table bad_table (
  id1 integer,
  id2 integer,
  FOREIGN KEY (id1, id2) REFERENCES ref_target(ref_id1, ref_id1)
);

-- TEST: try to use a cursor as a value -- you get the "cursor has row" boolean
-- + {assign}: X: integer variable
-- + {name X}: X: integer variable
-- + {name my_cursor}: _my_cursor_has_row_: bool notnull variable
-- - error:
set X := my_cursor;

-- TEST: valid update
-- + {update_stmt}: foo: { id: integer notnull primary_key autoinc }
-- + {opt_where}: bool notnull
-- + {eq}: bool notnull
-- + {name id}: id: integer notnull
-- + {int 2}: integer notnull
-- - error:
update foo set id = 1 where id = 2;

-- TEST: update with kind matching, ok to update
-- + {update_stmt}: with_kind: { id: integer<some_key>, cost: real<dollars>, value: real<dollars> }
-- + {update_list}: ok
-- - error:
update with_kind set cost = price_d;

-- TEST: update kind does not match, error
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {update_stmt}: err
-- +1 error:
update with_kind set cost = price_e;

-- TEST: update with view
-- + error: % cannot update a view 'myView'
-- + {update_stmt}: err
-- +1 error:
update myView set id = 1;

-- TEST: update with bogus where
-- + error: % string operand not allowed in 'NOT'
-- + {update_stmt}: err
-- + {opt_where}: err
-- + {not}: err
-- +1 error:
update foo set id = 1 where not 'x';

-- TEST: update with bogus limit
-- + error: % expected numeric expression 'LIMIT'
-- + {update_stmt}: err
-- + {opt_limit}: err
-- + {strlit 'x'}: err
-- +1 error:
update foo set id = 1 limit 'x';

-- TEST: update with bogus order by
-- + error: % string operand not allowed in 'NOT'
-- + {update_stmt}: err
-- + {opt_orderby}: err
-- +1 error:
update foo set id = 1 order by not 'x' limit 2;

-- TEST: update with bogus column specified
-- + error: % name not found 'non_existent_column'
-- + {update_stmt}: err
-- + {name non_existent_column}: err
-- +1 error:
update foo set non_existent_column = 1;

-- TEST: update with type mismatch (number <- string)
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + error: % additional info: in update table 'foo' the column with the problem is 'id'
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- + {name id}: id: integer notnull
-- + {strlit 'x'}: err
-- +2 error:
update foo set id = 'x';

-- TEST: update with loss of precision
-- + error: % lossy conversion from type 'LONG' in 1L
-- + error: % additional info: in update table 'foo' the column with the problem is 'id'
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- +2 error:
update foo set id = 1L where id = 2;

-- TEST: update with string type mismatch (string <- number)
-- + error: % required 'TEXT' not compatible with found 'INT' context 'name'
-- + error: % additional info: in update table 'bar' the column with the problem is 'name'
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- + {name name}: name: text
-- + {int 2}: err
-- +2 error:
update bar set name = 2;

-- TEST: update not null column to constant null
-- + error: % cannot assign/copy possibly null expression to not null target 'id'
-- + error: % additional info: in update table 'bar' the column with the problem is 'id'
-- + {update_stmt}: err
-- + {update_list}: err
-- + {name id}: id: integer notnull
-- + {null}: null
-- +2 error:
update bar set id = null;

-- TEST: try to use a variable in an update
-- + error: % name not found 'X'
-- + {update_stmt}: err
-- + {update_entry}: err
-- + {name X}: err
-- +1 error:
update bar set X = 1;

-- TEST: update nullable column to constant null
-- + {update_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {update_list}: ok
-- + {update_entry}: rate: longint
-- + {null}: null
-- - error:
update bar set rate = null;

-- TEST: update column to error, no extra errors reported
-- + error: % string operand not allowed in 'NOT'
-- + {update_stmt}: err
-- + {not}: err
-- +1 error:
update bar set id = not 'x';

-- TEST: simple procedure
-- + {create_proc_stmt}: ok dml_proc
-- + {delete_stmt}: ok
-- - error:
procedure proc1()
begin
  delete from foo;
end;

-- TEST: duplicate proc name
-- + error: % duplicate stored proc name 'proc1'
-- + {create_proc_stmt}: err
-- + {name proc1}
-- +1 error:
procedure proc1()
begin
  delete from foo;
end;

-- TEST: procedure with arguments
-- Here we're going to check that the parens came out right in the walk
-- This is a case where precedence is equal and left to right
-- The parents force it to be right to left, we have to honor that even though
-- all priorities in sight are equal
-- + DELETE FROM foo WHERE arg1 = ('x' IN (arg2));
-- + {create_proc_stmt}: ok dml_proc
-- + {delete_stmt}: ok
-- + {eq}: bool
-- + {name arg1}: arg1: integer variable in
-- + {in_pred}: bool notnull
-- + {name arg2}: arg2: text variable in
-- - error:
procedure proc2(arg1 INT, arg2 text)
begin
 delete from foo where arg1 == ('x' in (arg2));
end;

-- TEST: try to use locals that are gone
-- + error: % name not found 'arg1'
-- + {select_stmt}: err
-- +1 error:
select arg1;

-- TEST: try to use locals that are gone
-- + error: % name not found 'arg2'
-- + {select_stmt}: err
-- +1 error:
select arg2;

-- TEST: procedure with duplicate arguments
-- + error: % duplicate parameter name 'arg1'
-- + {create_proc_stmt}: err
-- + {params}: err
-- +1 error:
procedure proc3(arg1 INT, arg1 text)
begin
  call anything(arg1, arg2);
end;

-- TEST: proc name no longer available even though there were errors
-- + error: % duplicate stored proc name 'proc3'
-- + {create_proc_stmt}: err
-- +1 error:
procedure proc3()
begin
  throw; -- whatever, anything
end;

-- TEST: throw not at the end of a block
-- + error: % statement should be the last thing in a statement list
-- + {create_proc_stmt}: err
-- +1 error:
procedure proc_throw_not_at_end()
begin
  throw;
  declare x integer;
end;

-- TEST: the out statement will force the proc type to be recomputed, it must not lose the
-- throw state when that happens.
-- + {create_proc_stmt}: C: throw_before_out: { x: integer notnull } variable dml_proc shape_storage uses_out
-- - error:
proc throw_before_out()
begin
  try
    cursor C for select 1 x;
    fetch C;
  catch
    throw;
  end;
  out C;
end;

declare proc anything no check;

-- TEST: procedure call with arguments mixing in/out legally
-- + {create_proc_stmt}: ok
-- + {params}: ok
-- + {call_stmt}: ok
-- + {name anything}: ok
-- + {name arg1}: arg1: integer variable in
-- + {name arg3}: arg3: real variable in out
-- - error:
procedure proc4(in arg1 integer, out arg2 text, inout arg3 real)
begin
  call anything(arg1, arg3);
end;

-- TEST: local name conflicts with arg
-- + error: % duplicate variable name in the same scope 'arg1'
-- + {params}: ok
-- + {declare_vars_type}: err
-- + {name arg1}: err
-- +1 error:
procedure proc5(in arg1 integer, out arg2 text, inout arg3 real)
begin
  declare arg1 int;
end;

-- TEST: try to select out a whole table by table name
-- The name is not in scope
-- + error: % name not found 'bar'
-- +1 error:
select bar from bar as T;

-- TEST: try to select a whole table by aliased table name
-- The name is not in scope
-- + error: % name not found 'T'
-- +1 error:
select T from bar as T;

-- TEST: goofy nested select to verify name reachability
-- the nested table matches the outer table
-- + {select_stmt}: _select_: { id: integer notnull, rate: longint }
-- + {select_stmt}: _select_: { id: integer notnull, rate: longint }
-- + {select_from_etc}: TABLE { bar: bar }
-- - error:
select id, rate from (select id, rate from bar);

-- TEST: slighly less goofy nested select to verify name reachability
-- + {select_stmt}: _select_: { id: integer notnull, rate: longint }
-- the nested select had more columns
-- + {select_stmt}: _select_: { id: integer notnull, name: text, rate: longint }
-- + {select_from_etc}: TABLE { bar: bar }
-- - error:
select id, rate from (select * from bar);

-- TEST: use the table name as its scope
-- + {select_stmt}: _select_: { id: integer notnull }
-- + {dot}: id: integer notnull
-- + {select_from_etc}: TABLE { foo: foo }
-- - error:
select foo.id from foo;

-- TEST: error: try to use the table name as its scope after aliasing
-- + error: in dot % name not found 'foo.id'
-- + {select_stmt}: err
-- + {dot}: err
-- + {name foo}
-- + {name id}
-- + {select_from_etc}: TABLE { T1: foo }
-- +1 error:
select foo.id from foo as T1;

-- make a not null variable for the next test
declare int_nn int!;

-- TEST: bogus assignment
-- + error: % cannot assign/copy possibly null expression to not null target 'int_nn'
-- + {assign}: err
-- +1 error:
set int_nn := NULL;

-- TEST: call external method with args
-- + {call_stmt}: ok
-- + {name printf}: ok
-- + {strlit 'Hello, world'}: text notnull
-- - error:
call printf('Hello, world');

-- TEST: call known method with correct args (zero)
-- + {call_stmt}: ok dml_proc
-- + {name proc1}: ok dml_proc
-- - error:
call proc1();

-- TEST: call known method with correct args (two)
-- + {call_stmt}: ok dml_proc
-- + {name proc2}: ok dml_proc
-- + {int 1}: integer notnull
-- + {strlit 'foo'}: text notnull
-- - error:
call proc2(1, 'foo');

-- TEST: call known method with correct bogus int (arg1 should be an int)
-- + error: % required 'INT' not compatible with found 'TEXT' context 'arg1'
-- + error: % additional info: calling 'proc2' argument #1 intended for parameter 'arg1' has the problem
-- + {call_stmt}: err
-- + {name proc2}: ok dml_proc
-- + {strlit 'bar'}: err
-- +2 error:
call proc2('bar', 'foo');

-- TEST: call known method with bogus string  (arg2 should be a string)
-- + error: % required 'TEXT' not compatible with found 'INT' context 'arg2'
-- + error: % additional info: calling 'proc2' argument #2 intended for parameter 'arg2' has the problem
-- + {call_stmt}: err
-- + {name proc2}: ok dml_proc
-- + {int 2}: err
-- +2 error:
call proc2(1, 2);

-- TEST: call known method with too many args
-- + error: % too many arguments provided to procedure 'proc2'
-- + {call_stmt}: err
-- + {name proc2}: ok dml_proc
-- +1 error:
call proc2(1, 'foo', 1);

-- TEST: call known method with too few args
-- + error: % too few arguments provided to procedure 'proc2'
-- + {call_stmt}: err
-- + {name proc2}: ok dml_proc
-- +1 error:
call proc2(1);

-- TEST: call on a method that had errors
-- + error: % procedure had errors, can't call 'proc3'
-- + {call_stmt}: err
-- + {name proc3}
-- - {name proc3}: ok
-- +1 error:
call proc3(1, 'foo');

-- test method with some out arguments, used in tests below
procedure proc_with_output(in arg1 integer, inout arg2 integer, out arg3 integer)
begin
end;

-- TEST: can't use an integer for inout arg
-- + error: % expected a variable name for OUT or INOUT argument 'arg2'
-- + error: % additional info: calling 'proc_with_output' argument #2 intended for parameter 'arg2' has the problem
-- + {call_stmt}: err
-- +2 error:
call proc_with_output(1, 2, X);

-- TEST: can't use an integer for out arg
-- + error: % expected a variable name for OUT or INOUT argument 'arg3'
-- + error: % additional info: calling 'proc_with_output' argument #3 intended for parameter 'arg3' has the problem
-- + {call_stmt}: err
-- +2 error:
call proc_with_output(1, X, 3);

-- TEST: out values satisfied
-- + {call_stmt}: ok
-- + {int 1}: integer notnull
-- + {name X}: X: integer variable
-- + {name Y}: Y: integer variable
-- - error:
call proc_with_output(1, X, Y);

-- TEST: try to use an in/out arg in an out slot -> ok
-- + {create_proc_stmt}: ok
-- + {param_detail}: arg1: integer variable in out
-- + {name proc_with_output}: ok
-- + {name arg1}: arg1: integer variable in out
-- - error:
procedure test_proc2(inout arg1 integer)
begin
  call proc_with_output(1, X, arg1);
end;

-- TEST: try to use an out arg in an out slot -> ok
-- + {create_proc_stmt}: ok
-- + {param_detail}: arg1: integer variable out
-- + {name proc_with_output}: ok
-- + {name arg1}: arg1: integer variable out
-- - error:
procedure test_proc3(out arg1 integer)
begin
  call proc_with_output(1, X, arg1);
end;

-- TEST: a variable may not be passed as both an INOUT and OUT argument
-- + error: % OUT or INOUT argument cannot be used again in same call 'X'
-- + {call_stmt}: err
-- +1 error:
call proc_with_output(1, X, X);

-- TEST: a variable may not be passed as both an IN and INOUT argument
-- + error: % OUT or INOUT argument cannot be used again in same call 'X'
-- + {call_stmt}: err
-- +1 error:
call proc_with_output(X, X, Y);

-- TEST: a variable may not be passed as both an IN and OUT argument
-- + error: % OUT or INOUT argument cannot be used again in same call 'X'
-- + {call_stmt}: err
-- +1 error:
call proc_with_output(X, Y, X);

-- TEST: a variable may be passed as an OUT or INOUT argument and used within a
-- subexpression of another argument
-- + {call_stmt}: ok
-- - error:
call proc_with_output(1 + X, Y, X);

-- TEST: cursors cannot be passed as OUT arguments.
-- + error: % expected a variable name for OUT or INOUT argument 'arg1'
-- + error: % additional info: calling 'test_proc3' argument #1 intended for parameter 'arg1' has the problem
-- +2 error:
procedure cursors_cannot_be_used_as_out_args()
begin
  cursor c for select 0 as x;
  call test_proc3(c);
end;

-- TEST: Enum cases cannot be passed as OUT arguments.
-- + error: % expected a variable name for OUT or INOUT argument 'arg1'
-- + error: % additional info: calling 'test_proc3' argument #1 intended for parameter 'arg1' has the problem
-- +2 error:
procedure enum_cases_cannot_be_used_as_out_args()
begin
  call test_proc3(ints.negative_one);
end;

-- TEST: Unbound variables cannot be passed as OUT arguments.
-- + error: % name not found 'unbound'
-- + error: % additional info: calling 'test_proc3' argument #1 intended for parameter 'arg1' has the problem
-- +2 error:
procedure unbound_variables_cannot_be_used_as_out_args()
begin
  call test_proc3(unbound);
end;

-- TEST: try count function
-- - error:
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {name count}: integer notnull
-- + {star}: integer
select count(*) from foo;

-- TEST: verify that analysis of the special function `count` can deal with
-- bogus arguments
-- + error: % name not found 'this_does_not_exist'
-- + {call}: err
-- + {name this_does_not_exist}: err
-- +1 error:
select count(this_does_not_exist) from foo;

-- TEST: try count distinct function
-- - error:
-- + {select_stmt}: _select_: { c: integer notnull }
-- + {name count}: integer notnull
-- + {distinct}
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
select count(distinct id) c from foo;

-- TEST: try count distinct function with filter clause
-- + {select_stmt}: _select_: { c: integer notnull }
-- + {name count}: integer notnull
-- + {distinct}
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- - error:
select count(distinct id) filter (where id = 0) as c from foo;

-- TEST: try count distinct function with star
-- + error: % DISTINCT may only be used with one explicit argument in an aggregate function 'count'
-- + {select_stmt}: err
-- + {call}: err
-- + {name count}
-- +1 error:
select count(distinct *) from foo;

-- TEST: try sum functions
-- + {select_stmt}: _select_: { s: integer }
-- + {name sum}: integer
-- - error:
select sum(id) s from foo;

-- TEST: try total functions
-- + {select_stmt}: _select_: { t: real notnull }
-- + {name total}: real notnull
-- - error:
select total(id) t from foo;

-- TEST: try sum functions with too many param
-- + error: % too many arguments in function 'total'
-- + {select_stmt}: err
-- +1 error:
select total(id, rate) from bar;

-- TEST: try sum functions with star -- bogus
-- + error: % argument can only be used in count(*) '*'
-- + {select_stmt}: err
-- + {name sum}
-- + {star}: err
-- +1 error:
select sum(*) from foo;

-- TEST: try average, this should give a real
-- + {select_stmt}: _select_: { a: real }
-- + {name avg}: real
-- - error:
select avg(id) a from foo;

-- TEST: try min, this should give an integer
-- + {select_stmt}: _select_: { m: integer }
-- + {name min}: integer
-- - error:
select min(id) m from foo;

-- TEST: bogus number of arguments in count
-- + error: % function got incorrect number of arguments 'count'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select count(1,2) from foo);

-- TEST: bogus number of arguments in max
-- + error: % too few arguments in function 'max'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select max() from foo);

-- TEST: bogus number of arguments in sign
-- + error: % too few arguments in function 'sign'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select sign());

-- TEST: bogus number of arguments in sign
-- + error: % too many arguments in function 'sign'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select sign(1,2));

-- TEST: argument in sign is not numeric
-- + error: % argument 1 'text' is an invalid type; valid types are: 'integer' 'long' 'real' in 'sign'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select sign('x'));

-- TEST: sign may accept a real arg
-- + {let_stmt}: rs: integer notnull variable
-- - error:
let rs := (select sign(1.0));

-- TEST: sign Nullability is preserved
-- + {let_stmt}: nl: integer variable
-- - error:
let nl := (select sign(nullable(-1.0)));

-- TEST: sign Sensitivity is preserved
-- + {let_stmt}: ssnl: integer variable sensitive
-- - error:
let ssnl := (select sign(sensitive(nullable(1))));

-- TEST: bogus number of arguments in round
-- + error: % too few arguments in function 'round'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select round());

-- TEST: round rewritten to SQL context
-- + SET X := CAST(( SELECT round(1.3) IF NOTHING THEN THROW ) AS INT);
-- + {assign}: X: integer variable was_set
-- - error:
set X := round(1.3) ~int~;

-- TEST: bogus number of arguments in round
-- + error: % too many arguments in function 'round'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select round(1.0,2,3));

-- TEST: round second arg not numeric
-- + error: % argument 2 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' in 'round'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select round(1.5, 'x'));

-- TEST: round must get a real arg in position 1
-- + error: % CQL0084: argument 1 'integer' is an invalid type; valid types are: 'real' in 'round'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select round(1,2));

-- TEST: round must get a real arg in position 1
-- + {let_stmt}: rr: real notnull variable
-- - error:
let rr := (select round(1.0,2));

-- TEST: correct round double not null convered to long not null
-- + {let_stmt}: ll: longint notnull variable
-- - error:
let ll := (select round(1.0));

-- TEST: round Nullability is preserved
-- + {let_stmt}: NLL: longint variable
-- - error:
let NLL := (select round(nullable(1.0)));

-- TEST: round Nullability is preserved
-- + {let_stmt}: NRR: real variable
-- - error:
let NRR := (select round(1.0, nullable(1)));

-- TEST: round Sensitivity is preserved
-- + {let_stmt}: SNL: longint variable sensitive
-- - error:
let SNL := (select round(sensitive(nullable(1.0))));

-- TEST: round Sensitivity is preserved
-- + {let_stmt}: SNR: real variable sensitive
-- - error:
let SNR := (select round(nullable(1.0), sensitive(1)));

-- TEST: The precision must be a numeric type but not real
-- + error: % argument 2 'real' is an invalid type; valid types are: 'bool' 'integer' 'long' in 'round'
-- + {assign}: err
-- +1 error:
set ll := (select round(1.0, 2.0));

-- TEST: bogus number of arguments in average
-- + error: % too many arguments in function 'avg'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select avg(1,2) from foo);

-- TEST: bogus string type in average
-- + error: % argument 1 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' in 'avg'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select avg('foo') from foo);

-- TEST: bogus null literal in average
-- + error: % argument 1 is a NULL literal; useless in 'avg'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := (select avg(null) from foo);

-- TEST: assign select where statement to nullable variable
-- + {assign}: X: integer variable
-- - error:
set X := (select X*10 as v where 1);

-- TEST: assign select where statement to not null variable
-- + {assign}: X_not_null: integer notnull variable
-- + {name X_not_null}: X_not_null: integer notnull variable
-- + {select_stmt}: _anon: integer notnull
-- - error:
set X_not_null := (select 1 where 0);

-- TEST: bogus function
-- + error: % function not builtin and not declared 'some_unknown_function'
-- + {select_stmt}: err
-- +1 error:
set X := (select some_unknown_function(null));

var loop_var int;

-- TEST: simple while statement
-- + {while_stmt}: ok
-- + {name loop_var}: loop_var: integer variable
-- - error:
while loop_var
begin
end;

-- TEST: not numeric while
-- + error: % expected numeric expression 'WHILE'
-- + {strlit 'X'}: err
-- +1 error:
while 'X'
begin
end;

-- TEST: error in while block should be propagated up
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
-- + {while_stmt}: err
while X
begin
  select NOT 'x';
end;

-- TEST: try to make a nested proc
-- + error: % stored procedures cannot be nested 'bar'
-- +1 error:
-- The containing proc is also in error
-- +2 {create_proc_stmt}: err
proc foo()
begin
   create proc bar()
   begin
     select 1;
   end;
end;

-- TEST: verify that a procedure that calls a DML proc is a DML proc
-- - error:
-- + {create_proc_stmt}: ok dml_proc
-- + {name proc1}: ok dml_proc
proc calls_dml()
begin
  call proc1();  -- it does a select
end;

-- TEST: not much to go wrong with try/catch
-- - error:
-- + {trycatch_stmt}: ok
-- + {throw_stmt}: ok
try
  select 1;
catch
  throw;
end;

-- TEST: error in try block should be propagated to top of tree
-- + error: % string operand not allowed in 'NOT'
-- + {trycatch_stmt}: err
-- + {stmt_list}: err
-- +1 error:
try
  select not 'x';
catch
  throw;
end;

-- TEST: error in catch block should be propagated to top of tree
-- + error: % string operand not allowed in 'NOT'
-- + {trycatch_stmt}: err
-- + {stmt_list}: ok
-- + {stmt_list}: err
-- +1 error:
try
  throw;
catch
  select not 'x';
end;

-- TEST: this procedure will have a structured semantic type
-- + {create_proc_stmt}: with_result_set: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
-- +1 {select_expr_list}: _select_: { id: integer notnull, name: text, rate: longint }
procedure with_result_set()
begin
  select * from bar;
end;

-- TEST: this procedure will have a structured semantic type
-- + {create_proc_stmt}: with_matching_result: { A: integer notnull, B: real notnull } dml_proc
-- - error:
-- +2 {select_stmt}: _select_: { A: integer notnull, B: real notnull }
procedure with_matching_result(i integer)
begin
  if i then
    select 1 as A, 2.5 as B;
  else
    select 3 as A, 4.7 as B;
  end if;
end;

-- TEST: this procedure will have have not matching arg types
-- + error: % in multiple select/out statements, all columns must be an exact type match (expected real notnull; found integer notnull) 'B'
-- + {select_expr_list}: _select_: { A: integer notnull, B: real notnull }
-- + {select_expr_list}: _select_: { A: integer notnull, B: integer notnull }
procedure with_wrong_types(i integer)
begin
  if i then
    select 1 as A, 2.5 as B;
  else
    select 3 as A, 4 as B;
  end if;
end;

-- TEST: this procedure will have have not matching arg counts
-- + error: % in multiple select/out statements, all must have the same column count
-- + {select_expr_list}: _select_: { A: integer notnull, B: real notnull }
-- + {select_expr_list}: _select_: { A: integer notnull }
procedure with_wrong_count(i integer)
begin
  if i then
    select 1 as A, 2.5 as B;
  else
    select 3 as A;
  end if;
end;

-- TEST: this procedure will have nullability mismatch
-- + error: % in multiple select/out statements, all columns must be an exact type match (including nullability) (expected integer notnull; found integer) 'A'
-- + {create_proc_stmt}: err
-- + {select_stmt}: _select_: { A: integer notnull variable in }
-- + {select_expr_list_con}: _select_: { A: integer variable was_set }
procedure with_wrong_flags(i int!)
begin
  if i then
    select i as A;
  else
    select X as A;
  end if;
end;

-- TEST: this procedure will match variables
-- + {create_proc_stmt}: with_ok_flags: { A: integer notnull }
-- use the important fragment for the match, one is a variable so the tree is slightly different
-- +2 {select_expr_list}: _select_: { A: integer notnull
-- - error:
procedure with_ok_flags(i int!)
begin
  if i then
    select i as A;
  else
    select 2 as A;
  end if;
end;

-- TEST: this procedure will not match column names
-- + error: % in multiple select/out statements, all column names must be identical so they have unambiguous names; error in column 1: 'A' vs. 'B'
-- + {create_proc_stmt}: err
-- + {select_stmt}: _select_: { A: integer notnull }
-- + {select_expr_list_con}: _select_: { B: integer notnull }
procedure with_bad_names(i int!)
begin
  if i then
    select 1 as A;
  else
    select 2 as B;
  end if;
end;

-- TEST: this procedure doesn't specify a name for the result
-- + error: % all columns in the select must have a name
-- + {create_proc_stmt}: err
-- + {stmt_list}: err
-- + {select_expr_list_con}: _select_: { _anon: integer notnull }
procedure with_no_names(i int!)
begin
  select 1;
end;

-- TEST: good cursor
-- + {declare_cursor}: curs: with_result_set: { id: integer notnull, name: text, rate: longint } variable
-- + {name with_result_set}: with_result_set: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
cursor curs for call with_result_set();

-- TEST: bad args to the function -> error path
-- + error: % too many arguments provided to procedure 'with_result_set'
-- + {declare_cursor}: err
-- +1 error:
cursor curs2 for call with_result_set(1);

-- TEST: bad invocation, needs cursor
-- + error: % procedures with results can only be called using a cursor in global context 'with_result_set'
-- + {call_stmt}: err
call with_result_set();

-- TEST: bad invocation, this method doesn't return a result set
-- + error: % cursor requires a procedure that returns a result set via select 'curs'
-- + {declare_cursor}: err
-- + {name proc1}: ok dml_proc
cursor curs for call proc1();

-- TEST: full join with all expression options, including offset
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, name: text, rate: longint }
-- + {opt_where}: bool notnull
-- + {groupby_list}: ok
-- + {opt_having}: bool
-- + {opt_orderby}: ok
-- + {opt_limit}: integer notnull
-- + {opt_offset}: integer notnull
-- - error:
select * from foo as T1
inner join bar as T2 on T1.id = T2.id
where T2.id > 5
group by T2.name, T2.id
having T2.name = 'x'
order by T2.rate
limit 5
offset 7;

-- TEST: full join with all expression options and bogus offset
-- + error: % expected numeric expression 'OFFSET'
-- + {select_stmt}: err
-- + {opt_offset}: err
-- +1 error:
select * from foo as T1
inner join bar as T2 on T1.id = T2.id
where T2.id > 5
group by T2.name
having T2.name = 'x'
order by T2.rate
limit 5
offset 'x';

-- TEST: You can't aggregate if there is no FROM clause, try that out for count
-- + error: % aggregates only make sense if there is a FROM clause 'count'
-- + {select_stmt}: err
-- +1 error:
select count(1);

-- TEST: checking use of aggregates in the wrong context (not allowed in where)
-- + error: % function may not appear in this context 'count'
-- + {select_stmt}: err
-- +1 error:
select * from foo where count(*) == 1;

-- TEST: You can't aggregate if there is no FROM clause, try that out for max
-- + error: % aggregates only make sense if there is a FROM clause 'max'
-- + {select_stmt}: err
-- +1 error:
select max(1);

-- TEST: You can't aggregate if there is no FROM clause, try that out for avg
-- + error: % aggregates only make sense if there is a FROM clause 'avg'
-- + {select_stmt}: err
-- +1 error:
select avg(1);

-- TEST: assign a not null to a nullable output, that's ok.
-- + {create_proc_stmt}: ok
-- + {param_detail}: result: integer variable out
-- + {assign}: result: integer variable out
-- + {int 5}: integer notnull
-- - error:
proc out_proc(out result integer)
begin
  set result := 5;
end;

-- TEST: Set up a not null int for the tested
-- + {name my_int}: my_int: integer notnull variable
-- - error:
declare my_int int!;

-- TEST: my_int is not nullable, must be exact match in out parameter, ordinarily this would be compatible
-- + error: % cannot assign/copy possibly null expression to not null target 'my_int'
-- + error: % additional info: calling 'out_proc' argument #1 intended for parameter 'result' has the problem
-- +2 error:
call out_proc(my_int);

-- TEST: my_real is real, must be exact match in out parameter, ordinarily this would be compatible
-- + {name my_real}: my_real: real variable
-- - error:
declare my_real real;

-- TEST: Try to make the call with a bogus out arg now
-- + error: % proc out parameter: arg must be an exact type match (expected integer; found real) 'my_real'
-- + error: % additional info: calling 'out_proc' argument #1 intended for parameter 'result' has the problem
-- + {call_stmt}: err
-- +2 error:
call out_proc(my_real);

-- TEST: try an exists clause
-- + {select_stmt}: _select_: { id: integer notnull }
-- + {exists_expr}: bool notnull
-- - error:
select * from foo where exists (select * from foo);

-- TEST: try a not exists clause
-- + {select_stmt}: _select_: { id: integer notnull }
-- + {not}: bool notnull
-- + {exists_expr}: bool notnull
-- - error:
select * from foo where not exists (select * from foo);

-- TEST: try an exists clause with an error, exists is always rewritten as select 1
-- so it doesn't matter how wrong what you put there is, it's ignored
-- + WHERE EXISTS (SELECT 1
-- - error:
select * from foo where exists (select not 'x' from foo);

-- TEST: try a not exists clause with an error, exists is always rewritten as select 1
-- so it doesn't matter how wrong what you put there is, it's ignored
-- + WHERE NOT EXISTS (SELECT 1
-- - error:
select * from foo where not exists (select not 'x' from foo);

-- TEST: try to use exists in a bogus place
-- + error: % exists_expr % function may not appear in this context 'exists'
-- + {assign}: err
-- + {exists_expr}: err
-- +1 error:
set X := exists(select * from foo);

-- TEST: try to use not exists in a bogus place
-- + error: % function may not appear in this context 'exists'
-- + {assign}: err
-- + {not}: err
-- + {exists_expr}: err
-- +1 error:
set X := not exists(select * from foo);

-- TEST: release a savepoint out of the blue
-- + error: % savepoint has not been mentioned yet, probably wrong 'garbonzo'
-- + {release_savepoint_stmt}: err
release savepoint garbonzo;

-- TEST: rollback to  a savepoint out of the blue
-- + error: % savepoint has not been mentioned yet, probably wrong 'another_garbonzo'
-- + {rollback_trans_stmt}: err
rollback transaction to savepoint another_garbonzo;

-- TEST: Test the shorthand syntax for cursors. The shape_storage flag for the
-- cursor itself comes from the following fetch statement.
-- + {declare_cursor}: shape_storage: _select_: { one: integer notnull, two: integer notnull } variable dml_proc
-- + {name shape_storage}: shape_storage: _select_: { one: integer notnull, two: integer notnull } variable dml_proc shape_storage
-- - error:
cursor shape_storage for select 1 as one, 2 as two;

-- TEST: Fetch the auto cursor
-- + {fetch_stmt}: shape_storage: _select_: { one: integer notnull, two: integer notnull } variable dml_proc
-- + {name shape_storage}: shape_storage: _select_: { one: integer notnull, two: integer notnull } variable dml_proc shape_storage
-- - error:
fetch shape_storage;

-- TEST: Now access the cursor
-- + {select_stmt}: _select_: { shape_storage.one: integer notnull variable }
-- + {dot}: shape_storage.one: integer notnull variable
-- + {name shape_storage}
-- + {name one}
-- - error:
select shape_storage.one;

-- TEST: a field that is not present
-- + error: % field not found in cursor 'three'
-- + {dot}: err
-- + {name shape_storage}
-- + {name three}
select shape_storage.three;

-- TEST: a cursor that did not use the auto-cursor feature
-- + error: % cursor was not used with 'fetch [cursor]' 'my_cursor'
-- + {dot}: err
-- + {name my_cursor}
-- + {name one}
select my_cursor.one;

-- TEST: test the join using syntax
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- + {select_from_etc}: JOIN { T1: foo, T2: foo }
-- + {using}
-- + {name id}
select * from foo as T1 inner join foo as T2 using(id);

-- TEST: duplicate column names
-- + error: % duplicate name in list 'id'
-- +1 error:
-- + {select_stmt}: err
select * from foo as T1 inner join foo as T2 using(id, id);

-- TEST: invalid column names (missing on the left)
-- + error: % join using column not found on the left side of the join 'idx'
-- +1 error:
select * from foo as T1 inner join foo as T2 using(id, idx);

-- TEST: invalid column names (missing on the right)
-- + error: % join using column not found on the right side of the join 'name'
-- +1 error:
select * from bar as T1 inner join foo as T2 using(id, name);

-- helper tables for different join types

-- + {create_table_stmt}: payload1: { id: integer notnull, data1: integer notnull }
-- - error:
create table payload1 (id int!, data1 int!);

-- + {create_table_stmt}: payload2: { id: integer notnull, data2: integer notnull }
-- - error:
create table payload2 (id int!, data2 int!);

-- TEST: all not null
-- + {select_stmt}: _select_: { id: integer notnull, data1: integer notnull, id: integer notnull, data2: integer notnull }
-- - error:
select * from payload1 inner join payload2 using (id);

-- TEST: right part nullable
-- + {select_stmt}: _select_: { id: integer notnull, data1: integer notnull, id: integer, data2: integer }
-- - error:
select * from payload1 left outer join payload2 using (id);

-- TEST: left part nullable
-- + {select_stmt}: _select_: { id: integer, data1: integer, id: integer notnull, data2: integer notnull }
-- - error:
select * from payload1 right outer join payload2 using (id);

-- TEST: both parts nullable due to cross join
-- + _select_: { id: integer notnull, data1: integer notnull, id: integer notnull, data2: integer notnull }
-- - error:
select * from payload1 cross join payload2 using (id);

-- TEST: compound select
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, id: integer notnull, id: integer notnull }
-- + {select_from_etc}: JOIN { A: foo, B: foo, C: foo, D: foo }
-- - error:
select * from (foo A, foo B) inner join (foo C, foo D);

-- TEST: select with embedded error in an interior join
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {select_from_etc}: err
-- + {join_clause}: err
-- + {table_or_subquery}: err
-- + {join_clause}: err
-- + {table_or_subquery}: TABLE { foo: foo }
-- +1 error:
select id from (foo inner join bar on not 'x') inner join foo on 1;

-- TEST: simple ifnull : note X is nullable
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {name X}: X: integer variable
-- - error:
select ifnull(X, 0);

-- TEST: simple coalesce with not null result, note X,Y are nullable
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {call}: real notnull
-- + {name coalesce}
-- + {name X}: X: integer variable
-- + {name Y}: Y: integer variable
-- + {dbl 1.5%}: real notnull
-- - error:
select coalesce(X, Y, 1.5);

-- TEST: null in a coalesce is obviously wrong
-- + error: % null literal is useless in function 'coalesce'
-- + {select_stmt}: err
-- + {call}: err
-- + {null}: err
-- +1 error:
select coalesce(X, null, 1.5);

-- TEST: not null before the end is obviously wrong
-- + error: % encountered arg known to be not null before the end of the list
-- + {call}: err
-- + {name coalesce}
-- +1 error:
select coalesce(X, 5, 1.5);

-- TEST: wrong number of args (too many)
-- + error: % incorrect number of arguments 'ifnull'
-- + {call}: err
-- + {name ifnull}
-- +1 error:
select ifnull(X, 5, 1.5);

-- TEST: wrong number of args (too few)
-- + error: % too few arguments provided 'ifnull'
-- + {call}: err
-- + {name ifnull}
-- +1 error:
select ifnull(5);

-- TEST: not compatible args in ifnull
-- + error: % required 'INT' not compatible with found 'TEXT' context 'ifnull'
-- + {call}: err
-- + {name ifnull}
-- +1 error:
select ifnull(X, 'hello');

-- TEST: error in expression in ifnull
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- + {name ifnull}
-- + {arg_list}: err
-- +1 error:
select ifnull(not 'x', not 'hello');

-- TEST: make make an FK with the column count wrong
-- + error: % number of columns on both sides of a foreign key must match
-- + {create_table_stmt}: err
-- + {fk_def}: err
-- +1 error:
create table fk_table_2 (
  id1 integer,
  id2 integer,
  FOREIGN KEY (id1, id2) REFERENCES foo(id)
);

-- TEST: make make an FK with the column types not matching
-- + error: % exact type of both sides of a foreign key must match (expected real; found integer notnull) 'id'
-- + {create_table_stmt}: err
-- + {fk_def}: err
-- +1 error:
create table fk_table_2 (
  id REAL,
  FOREIGN KEY (id) REFERENCES foo(id)
);

-- TEST: helper table for join/using test
-- + {create_table_stmt}: join_clause_1: { id: real }
create table join_clause_1 (
  id REAL
);

-- TEST: helper table for join/using test
-- + {create_table_stmt}: join_clause_2: { id: integer }
-- - error:
create table join_clause_2 (
  id integer
);

-- TEST: join using syntax with column type mismatch test
-- + error: % left/right column types in join USING(...) do not match exactly 'id'
-- + {select_stmt}: err
-- + {join_clause}: err
-- + {table_or_subquery}: TABLE { join_clause_1: join_clause_1 }
-- + {table_or_subquery}: TABLE { join_clause_2: join_clause_2 }
-- +1 error:
select * from join_clause_1 inner join join_clause_2 using(id);

-- TEST: use last insert rowid, validate it's ok
-- + {select_stmt}: _select_: { _anon: longint notnull }
-- + {name last_insert_rowid}: longint notnull
-- - error:
select last_insert_rowid();

-- TEST: last_insert_row doesn't take args
-- + error: % too many arguments in function 'last_insert_rowid'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select last_insert_rowid(1);

-- TEST: last_insert_rowid is not ok in a limit
-- + error: % function may not appear in this context 'last_insert_rowid'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select * from foo limit last_insert_rowid();

-- declare result for last_insert_rowid
declare rowid_result long int!;

-- TEST: set last_insert_rowid outside of select statement
-- + {assign}: rowid_result: longint notnull variable
-- + {name rowid_result}: rowid_result: longint notnull variable
-- + {call}: longint notnull
-- + {name last_insert_rowid}: longint notnull
-- - error:
set rowid_result := last_insert_rowid();

-- TEST: use changes, validate it's ok
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {name changes}: integer notnull
-- - error:
select changes();

-- TEST: changes doesn't take args
-- + error: % too many arguments in function 'changes'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select changes(1);

-- TEST: changes is not ok in a limit
-- + error: % function may not appear in this context 'changes'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select * from foo limit changes();

-- declare result for changes function
declare changes_result int!;

-- TEST: set changes outside of select statement
-- + {assign}: changes_result: integer notnull variable
-- + {name changes_result}: changes_result: integer notnull variable
-- + {call}: integer notnull
-- + {name changes}: integer notnull
-- - error:
set changes_result := changes();

-- TEST: printf is ok in a select
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {select_expr}: text notnull
-- + {name printf}: text notnull
-- - error:
select printf('%s %d', 'x', 5);

-- TEST: printf is ok in a loose expression
-- + {assign}: a_string: text variable
-- + {name printf}: text notnull
-- - error:
set a_string := printf('Hello');

-- TEST: printf is not ok in a limit
-- + error: % function may not appear in this context 'printf'
-- + {select_stmt}: err
-- + {opt_limit}: err
-- +1 error:
select 1 from (select 1) limit printf('%s %d', 'x', 5) == 'x';

-- TEST: update with duplicate columns
-- + error: % duplicate target column name in update statement 'id'
-- + {update_stmt}: err
-- + {name id}: err
update foo set id = 1, id = 3 where id = 2;

-- TEST: bogus number of arguments in sum
-- + error: % too many arguments in function 'sum'
-- + {assign}: err
-- + {call}: err
set X := (select sum(1,2) from foo);

-- TEST: sum used in a limit, bogus
-- + error: % function may not appear in this context 'sum'
-- + {assign}: err
-- + {call}: err
set X := (select id from foo limit sum(1));

-- TEST: sum used with text
-- + error: % argument 1 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' in 'sum'
-- + {assign}: err
-- + {call}: err
set X := (select sum('x') from foo);

-- tables for the following test
create table A1(foo int);
create table B1(foo int);
create table C1(foo int);

-- TEST: duplicate table name logic needs different left and right table counts
--       this test case with 3 tables will have one join with 2 on the left 1
--       on the right
-- - error:
-- + {select_from_etc}: JOIN { T1: A1, T2: B1, T3: C1 }
select * from A1 as T1
left outer join B1 as T2 on T1.foo = t2.foo
left outer join C1 as T3 on T2.foo = t3.foo;

-- TEST: group_concat basic correct case
-- - error:
-- + {select_stmt}: _select_: { id: integer notnull, grp: text }
-- +  {name group_concat}: text
select id, group_concat(name) grp from bar group by id;

-- TEST: group_concat with second arg
-- - error:
-- + {select_stmt}: _select_: { id: integer notnull, grp: text }
-- +  {name group_concat}: text
select id, group_concat(name, 'x') grp from bar group by id;

-- TEST: group_concat with bogus second arg
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'group_concat'
-- +1 error:
-- + {select_stmt}: err
select id, group_concat(name, 0) from bar group by id;

-- TEST: group_concat with zero args
-- + error: % too few arguments in function 'group_concat'
-- +1 error:
-- + {select_stmt}: err
select id, group_concat() from bar group by id;

-- TEST: group_concat with three args
-- + error: % too many arguments in function 'group_concat'
-- +1 error:
-- + {select_stmt}: err
select id, group_concat('x', 'y', 'z') from bar group by id;

-- TEST: group_concat outside of aggregate context
-- + error: % function may not appear in this context 'group_concat'
-- +1 error:
-- + {select_stmt}: err
select id from bar where group_concat(name) = 'foo';

-- TEST: strftime basic correct case
-- - error:
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name strftime}: text notnull
select strftime('%s', 'now');

-- TEST: strftime with a modifier
-- - error:
-- + {select_stmt}: _select_: { _anon: text }
-- + {name strftime}: text
select strftime('%YYYY-%mm-%DDT%HH:%MM:%SS.SSS', 'now', '+1 month');

-- TEST: strftime with multiple modifiers
-- - error:
-- + {select_stmt}: _select_: { _anon: text }
-- + {name strftime}: text
select strftime('%W', 'now', '+1 month', 'start of month', '-3 minutes', 'weekday 4');

-- TEST: strftime with non-string modifier
-- + error: % argument 3 'integer' is an invalid type; valid types are: 'text' in 'strftime'
-- + {select_stmt}: err
-- +1 error:
select strftime('%s', 'now', 3);

-- TEST: strftime with bogus format
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'strftime'
-- + {select_stmt}: err
-- +1 error:
select strftime(42, 'now');

-- TEST: strftime with bogus timestring
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'strftime'
-- + {select_stmt}: err
-- +1 error:
select strftime('%s', 42);

-- TEST: strftime is rewritten to SQL context
-- + SET a_string := ( SELECT strftime('%s', 'now') IF NOTHING THEN THROW );
-- + {assign}: a_string: text variable was_set
-- - error:
set a_string := strftime('%s', 'now');

-- TEST: strftime without enough arguments
-- + error: % too few arguments in function 'strftime'
-- + {select_stmt}: err
-- +1 error:
select strftime('now');

-- TEST: date basic correct case
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name date}: text notnull
-- - error:
select date('now');

-- TEST: date with a modifier
-- + {select_stmt}: _select_: { _anon: text }
-- + {name date}: text
-- - error:
select date('now', '+1 month');

-- TEST: date with multiple modifiers
-- + {select_stmt}: _select_: { _anon: text }
-- + {name date}: text
-- - error:
select date('now', '+1 month', 'start of month', '-3 minutes', 'weekday 4');

-- TEST: date with non-string modifier
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'date'
-- + {select_stmt}: err
-- +1 error:
select date('now', 3);

-- TEST: date with bogus timestring
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'date'
-- + {select_stmt}: err
-- +1 error:
select date(42);

-- TEST: date is rewritten to SQL context
-- + SET a_string := ( SELECT date('now') IF NOTHING THEN THROW );
-- + {assign}: a_string: text variable was_set
-- - error:
set a_string := date('now');

-- TEST: date without enough arguments
-- + error: % too few arguments in function 'date'
-- + {select_stmt}: err
-- +1 error:
select date();

-- TEST: time basic correct case
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name time}: text notnull
-- - error:
select time('now');

-- TEST: time with a modifier
-- + {select_stmt}: _select_: { _anon: text }
-- + {name time}: text
-- - error:
select time('now', '+1 month');

-- TEST: time with multiple modifiers
-- + {select_stmt}: _select_: { _anon: text }
-- + {name time}: text
-- - error:
select time('now', '+1 month', 'start of month', '-3 minutes', 'weekday 4');

-- TEST: time with non-string modifier
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'time'
-- + {select_stmt}: err
-- +1 error:
select time('now', 3);

-- TEST: time with bogus timestring
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'time'
-- + {select_stmt}: err
-- +1 error:
select time(42);

-- TEST: time is rewritten to sql context
-- + SET a_string := ( SELECT time('now') IF NOTHING THEN THROW );
-- + {assign}: a_string: text variable was_set
-- + {call}: text notnull
-- - error:
set a_string := time('now');

-- TEST: time without enough arguments
-- + error: % too few arguments in function 'time'
-- + {select_stmt}: err
-- +1 error:
select time();

-- TEST: datetime basic correct case
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name datetime}: text notnull
-- - error:
select datetime('now');

-- TEST: datetime with a modifier
-- + {select_stmt}: _select_: { _anon: text }
-- + {name datetime}: text
-- - error:
select datetime('now', '+1 month');

-- TEST: datetime with multiple modifiers
-- + {select_stmt}: _select_: { _anon: text }
-- + {name datetime}: text
-- - error:
select datetime('now', '+1 month', 'start of month', '-3 minutes', 'weekday 4');

-- TEST: datetime with non-string modifier
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'datetime'
-- + {select_stmt}: err
-- +1 error:
select datetime('now', 3);

-- TEST: datetime with bogus timestring
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'datetime'
-- + {select_stmt}: err
-- +1 error:
select datetime(42);

-- TEST: datetime is rewritten to sql context
-- + SET a_string := ( SELECT datetime('now') IF NOTHING THEN THROW );
-- + {assign}: a_string: text variable was_set
-- + {call}: text notnull
-- + {name datetime}: text notnull
-- - error:
set a_string := datetime('now');

-- TEST: datetime without enough arguments
-- + error: % too few arguments in function 'datetime'
-- +1 error:
-- + {select_stmt}: err
select datetime();

-- TEST: julianday basic correct case
-- - error:
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {name julianday}: real notnull
select julianday('now');

-- TEST: julianday with a modifier
-- - error:
-- + {select_stmt}: _select_: { _anon: real }
-- + {name julianday}: real
select julianday('now', '+1 month');

-- TEST: julianday with multiple modifiers
-- - error:
-- + {select_stmt}: _select_: { _anon: real }
-- + {name julianday}: real
select julianday('now', '+1 month', 'start of month', '-3 minutes', 'weekday 4');

-- TEST: julianday with non-string modifier
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'julianday'
-- +1 error:
-- + {select_stmt}: err
select julianday('now', 3);

-- TEST: julianday with bogus timestring
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'julianday'
-- +1 error:
-- + {select_stmt}: err
select julianday(42);

-- TEST: julianday is rewritten to SQL context
-- + LET dummy_julian_day := ( SELECT julianday('now') IF NOTHING THEN THROW );
-- + {let_stmt}: dummy_julian_day: real notnull variable
-- - error:
let dummy_julian_day := julianday('now');

-- TEST: julianday without enough arguments
-- + error: % too few arguments in function 'julianday'
-- +1 error:
-- + {select_stmt}: err
select julianday();

-- TEST: simple cast expression
-- - error:
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {cast_expr}: text notnull
select cast(1 as text);

-- TEST: cast expression in bogus context
-- + error: % CAST may only appear in the context of SQL statement
-- +1 error:
-- + {cast_expr}: err
set X := cast(5.0 as text);

-- TEST: correct check_type (types match) on int litteral
-- + {let_stmt}: int_lit_foo: integer notnull variable
-- + {name int_lit_foo}: int_lit_foo: integer notnull variable
-- + {type_check_expr}: integer notnull
-- + {int 1}: integer notnull
-- - error
let int_lit_foo := type_check(1 as int!);

-- TEST: correct check_type (types match) on str litteral
-- + {let_stmt}: str_foo: text notnull variabl
-- + {name str_foo}: str_foo: text notnull variable
-- + {call}: a_string: text notnull variable was_set
-- + {name a_string}: a_string: text inferred_notnull variable was_set
-- - error
let str_foo := type_check(a_string as text not null);

-- TEST: correct check_type (types match)
-- + {let_stmt}: int_foo: integer<foo> notnull variable
-- - error:
let int_foo := type_check(cast(1 as integer<foo>) as integer<foo> not null);

-- TEST: invalid type check expression
-- + error: % string operand not allowed in 'NOT'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(not "x" as goo);

-- TEST: invalid type name
-- + error: % unknown type 'goo'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(1 as goo);

-- TEST: correct check_type kind must exact match (different name)
-- + error: % expressions of different kinds can't be mixed: 'bar' vs. 'foo'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(cast(1 as integer<bar>) as integer<foo> not null);

-- TEST: correct check_type kind must exact match (nil left)
-- + error: % expressions of different kinds can't be mixed: '[none]' vs. 'foo'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(1 as integer<foo> not null);

-- TEST: correct check_type kind must exact match (nil right)
-- + error: % expressions of different kinds can't be mixed: 'bar' vs. '[none]'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(cast(1 as integer<bar>) as int!);

-- TEST: correct check_type (not null mismatch)
-- + error: % incompatible types in expression (expected integer; found integer notnull) '1'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(1 as integer);

-- TEST: correct check_type (sensitive mismatch)
-- + error: % incompatible types in expression (expected integer notnull sensitive; found integer notnull) '1'
-- + {type_check_expr}: err
-- +1 error:
set int_foo := type_check(1 as integer<foo> not null @sensitive);

-- TEST: correct check_type in sql context
-- + {let_stmt}: int_sql_val: integer notnull variable
-- + {select_stmt}: _anon: integer notnull
-- + {select_expr}: integer notnull
-- + {type_check_expr}: integer notnull
-- + {int 1}: integer notnull
-- - error:
let int_sql_val := (select type_check(1 as int!));

-- enforce strict cast and verify
@enforce_strict cast;

-- TEST: 1 is already an int
-- + error: % cast is redundant, remove to reduce code size 'CAST(1 AS INT)'
-- + {let_stmt}: err
-- + {cast_expr}: err
-- +1 error:
let idx := cast(1 as integer);

-- TEST: 1.5 is not an integer, the type doesn't match, ok cast
-- + {let_stmt}: idr: integer notnull variable
-- - error:
let idr := cast(1.5 as integer);

-- TEST: integer conversion but adding a kind, this is ok
-- + {let_stmt}: idx: integer<x> notnull variable
-- - error:
let idx := cast(1 as integer<x>);

-- TEST: changing kind, this is ok
-- + {let_stmt}: idy: integer<y> notnull variable
-- - error:
let idy := cast(idx as integer<y>);

-- TEST: type and kind match, this is a no-op therefore an error
-- + error: % cast is redundant, remove to reduce code size 'CAST(idy AS INT<y>
-- + {assign}: err
-- + {cast_expr}: err
-- +1 error:
set idy := cast(idy as integer<y>);

-- restore to normalcy
@enforce_normal cast;

-- TEST: cast expression with expression error
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
-- + {cast_expr}: err
select cast(not 'x' as int);

-- TEST: create table with PK to force not null
-- - error:
-- + {create_table_stmt}: pk_test: { id: integer notnull primary_key }
-- + {col_def}: id: integer notnull
create table pk_test(id integer primary key);

-- TEST: create table with PK out of line to force not null
-- - error:
-- semantic type and coldef must both be notnull
-- + {create_table_stmt}: pk_test_2: { id: integer notnull partial_pk }
-- + {col_def}: id: integer notnull
create table pk_test_2(
  id integer,
  PRIMARY KEY (id)
);

-- TEST: ensure that table factors are visible in order
create table AA1(id1 int!);
create table BB2(id2 int!);
create table CC3(id3 int!);

-- - error:
-- + {select_stmt}: _select_: { id1: integer notnull, id2: integer notnull, id3: integer }
SELECT *
FROM (AA1 A, BB2 B)
LEFT OUTER JOIN CC3 C ON C.id3 == A.id1;

-- TEST: declare procedure basic
-- - error:
-- + {declare_proc_stmt}: ok
-- + {name decl1}: ok
-- - decl1%dml
-- + {params}: ok
-- + {param}: id: integer variable in
declare proc decl1(id integer);

-- TEST: try to declare this as an unchecked proc also
-- + error: % procedure cannot be both a normal procedure and an unchecked procedure 'decl1'
-- +1 error:
declare proc decl1 no check;

-- TEST: declare procedure with DB params
-- + {declare_proc_stmt}: ok dml_proc
-- + {name decl2}: ok dml_proc
-- + {param}: id: integer variable in
-- - error:
declare proc decl2(id integer) using transaction;

-- TEST: declare procedure with select result set
-- + declare_proc_stmt}: decl3: { A: integer notnull, B: bool } dml_proc
-- - error:
declare proc decl3(id integer) ( A int!, B bool );

-- TEST: try an arg bundle inside of a declared proc
-- make sure the rewrite was accurate
-- + DECLARE PROC decl4 (x_A INT!, x_B BOOL);
-- - error:
declare proc decl4(x like decl3);

-- TEST: declare inside of a proc
-- + error: % declared procedures must be top level 'yy'
-- + {create_proc_stmt}: err
-- +1 error:
proc bogus_nested_declare()
begin
 declare proc yy();
end;

-- TEST: duplicate declaration, all matches
-- + DECLARE PROC decl1 (id INT);
-- + {declare_proc_stmt}: ok
-- + {param}: id: integer variable in
-- - error:
declare proc decl1(id integer);

-- TEST: duplicate declaration, mismatch
-- + error: in declare_proc_stmt % procedure declarations/definitions do not match 'decl1'
-- + {declare_proc_stmt}: err
declare proc decl1(id int!);

-- TEST: bogus parameters
-- + error: % duplicate parameter name 'id'
-- + {declare_proc_stmt}: err
-- + {params}: err
-- +1 error:
declare proc bogus_duplicate_params(id integer, id integer);

-- TEST: declare procedure with select error
-- + error: % duplicate column name 'id'
-- + {declare_proc_stmt}: err
-- + {params}: ok
-- + {typed_names}: err
-- +1 error:
declare proc bogus_select_list(id integer) (id integer, id integer);

-- TEST: subquery within in clause
-- + {in_pred}: bool notnull
-- + {select_from_etc}: TABLE { bar: bar }
-- - error:
select id from foo where id in (select id from bar);

-- TEST: subquery within in clause with multiple columns
-- + error: % nested select expression must return exactly one column
-- + {select_stmt}: err
-- +1 error:
select id from foo where id in (select id, id from bar);

-- TEST: subquery within in clause with wrong type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'IN'
-- + {select_stmt}: err
-- +1 error:
select id from foo where id in (select name from bar);

-- TEST: subquery within not in clause
-- + {not_in}: bool notnull
-- + {select_from_etc}: TABLE { bar: bar }
-- - error:
select id from foo where id not in (select id from bar);

-- TEST: subquery within not in clause with wrong type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'NOT IN'
-- + {select_stmt}: err
-- +1 error:
select id from foo where id not in (select name from bar);

-- TEST: basic union pattern
-- - error:
-- + {select_core_list}: union: { A: integer notnull, B: integer notnull }
select 1 as A, 2 as B
union
select 3 as A, 4 as B;

-- TEST: basic union all pattern
-- - error:
-- + {select_core_list}: union_all: { A: integer notnull, B: integer notnull }
select 1 as A, 2 as B
union all
select 3 as A, 4 as B;

-- TEST: union all with not matching columns
-- + error: % if multiple selects, all column names must be identical so they have unambiguous names; error in column 2: 'C' vs. 'B'
-- diagnostics also present
-- +4 error:
select 1 as A, 2 as C
union all
select 3 as A, 4 as B;

-- TEST: force the various diagnostic forms
-- + error: % if multiple selects, all must have the same column count
-- + error: % additional difference diagnostic info:
-- + error: likely end location of the 1st item
-- +   this item has 3 columns
-- + error: likely end location of the 2nd item
-- +   this item has 4 columns
-- + duplicate column in 1st: x integer notnull
-- + duplicate column in 2nd: x integer notnull
-- + only in 1st: y integer notnull
-- + only in 2nd: u integer notnull
-- + only in 2nd: z integer notnull
-- + {select_stmt}: err
-- diagnostics also present
-- +4 error:
select 1 as x, 2 as x, 3 as y
union all
select 0 as u, 1 as x, 2 as x, 3 as z;

-- TEST: union all with not matching types (but compat)
-- + {select_core_list}: union_all: { A: integer notnull, B: real notnull }
-- - error:
select 1 as A, 2 as B
union all
select 3 as A, 4.3 as B;

-- TEST: union all with error on the left
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
select not 'x' as A
union all
select 1 as A;

-- TEST: union all with error on the right
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
select 'x' as A
union all
select not 'x' as A;

-- TEST: compound operator intersect
-- - error:
-- + {select_core_list}: intersect: { A: integer notnull, B: integer notnull }
select 1 as A, 2 as B
intersect
select 3 as A, 4 as B;

-- TEST: compound operator except
-- - error:
-- + {select_core_list}: except: { A: integer notnull, B: integer notnull }
select 1 as A, 2 as B
except
select 3 as A, 4 as B;

-- TEST: use nullable in a select
-- + {select_stmt}: _select_: { x: integer }
-- - error:
select nullable(1) x;

-- TEST: use nullable in an expr
-- + {let_stmt}: nullable_one: integer variable
-- - error:
let nullable_one := nullable(1);

-- TEST: use sensitive in a select
-- + {select_stmt}: _select_: { x: integer notnull sensitive }
-- - error:
select sensitive(1) x;

-- TEST: use sensitive in an expr
-- + {let_stmt}: sens_one: integer notnull variable sensitive
-- - error:
let sens_one := sensitive(1);

-- helper variable
let sens_notnull := sensitive("some text");

-- TEST: ensure nullable() doesn't strip the sensitive bit
-- notnull is gone, sensitive stays
-- + {select_stmt}: _select_: { sens_notnull: text variable sensitive }
-- + {name sens_notnull}: sens_notnull: text notnull variable sensitive
-- - error:
select nullable(sens_notnull);

-- TEST: ensure kind is preserved in nullable
-- + {select_stmt}: _select_: { price_e: real<euros> variable }
-- + {name nullable}: price_e: real<euros> variable
-- - error:
select nullable(price_e);

-- TEST: affirmative error generated after nullable with kind
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {assign}: err
-- +1 error:
set price_d := (select nullable(price_e));

-- TEST: use nullable in a select with wrong args
-- + error: % too many arguments in function 'nullable'
-- +1 error:
select nullable(1, 2);

-- TEST: use nullable in a select with wrong args
-- + error: % function got incorrect number of arguments 'sensitive'
-- +1 error:
select sensitive(1, 2);

-- try some const cases especially those with errors

-- TEST: variables not allowed in constant expressions (duh)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x);

-- TEST: divide by zero yields error in all forms (integer)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1/0);

-- TEST: divide by zero yields error in all forms (real)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1/0.0);

-- TEST: divide by zero yields error in all forms (long)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1/0L);

-- TEST: divide by zero yields error in all forms (bool)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 / not 1);

-- TEST: divide by zero yields error in all forms (integer)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 % 0);

-- TEST: divide by zero yields error in all forms (long)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 % 0L);

-- TEST: divide by zero yields error in all forms (bool)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 % not 1);

-- TEST: not handles error prop
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(not x);

-- TEST: variables not allowed in constant expressions (duh)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(case x when 1 then 2 end);

-- TEST: variables not allowed in constant expressions (duh)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(case 1 when x then 2 end);

-- TEST: variables not allowed in constant expressions (duh)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(case 1 when 1 then x end);

-- TEST: variables not allowed in constant expressions (duh)
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(case when x then 2 end);

-- TEST: non integer arguments not allowed
-- + error: % operands must be an integer type, not real '~'
-- + {const}: err
-- +1 error:
select const(~1.3);

-- TEST: error should flow through
-- + SELECT CONST(~(1 / 0));
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(~(1/0));

-- TEST: error should flow through
-- + SELECT CONST(-(1 / 0));
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(-(1/0));

-- TEST: ~NULL
-- ~NULL is null
-- + SELECT NULL;
-- - error:
select const(~null);

-- TEST: -NULL
-- -NULL is null
-- + SELECT NULL;
-- - error:
select const(-null);

-- TEST: forcing errors in binary operators to make them prop:  comparison type
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x == x);

-- TEST: forcing errors in binary operators to make them prop:  is/is_not comparison type
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x is x);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x + 0);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(0 + x);

-- TEST: null handling for +
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null + 0);

-- TEST: null handling for +
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 + null);

-- TEST: bool handling for +
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(true + false);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x - 0);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(0 - x);

-- TEST: null handling for -
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null - 0);

-- TEST: null handling for -
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 - null);

-- TEST: bool handling for -
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(true - false);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x * 0);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(0 * x);

-- TEST: null handling for *
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null * 0);

-- TEST: null handling for *
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 * null);

-- TEST: bool handling for *
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(true * false);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x / 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 / x);

-- TEST: null handling for /
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null / 1);

-- TEST: null handling for /
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(1 / null);

-- TEST: bool handling for /
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false / true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x % 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 % x);

-- TEST: null handling for %
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null % 1);

-- TEST: null handling for %
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(1 % null);

-- TEST: bool handling for %
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false % true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x == 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 == x);

-- TEST: null handling for == (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const((not null) == 0);

-- TEST: null handling for == (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 == not null);

-- TEST: null handling for +
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 + null);

-- TEST: bool handling for ==
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false == true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x != 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 != x);

-- TEST: null handling for == (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const((not null) != 0);

-- TEST: null handling for != (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 != not null);

-- TEST: bool handling for !=
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false != true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x <= 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 <= x);

-- TEST: null handling for <= (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const((not null) <= 0);

-- TEST: null handling for <= (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 <= not null);

-- TEST: bool handling for <=
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false <= true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x >= 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 >= x);

-- TEST: null handling for >= (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const((not null) >= 0);

-- TEST: null handling for >= (don't use a literal null)
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 >= not null);

-- TEST: bool handling for >=
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false >= true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x > 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 > x);

-- TEST: null handling for >
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null > 1);

-- TEST: null handling for >
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(1 > null);

-- TEST: bool handling for >
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false > true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x < 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 < x);

-- TEST: null handling for <
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null < 1);

-- TEST: null handling for <
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(1 < null);

-- TEST: bool handling for <
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false < true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x << 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 << x);

-- TEST: null handling for <<
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null << 0);

-- TEST: null handling for <<
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 << null);

-- TEST: bool handling for <<
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false << true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x >> 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 >> x);

-- TEST: null handling for >>
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null >> 0);

-- TEST: null handling for >>
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 >> null);

-- TEST: bool handling for >>
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false >> true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x | 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 | x);

-- TEST: null handling for |
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null | 0);

-- TEST: null handling for |
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 | null);

-- TEST: bool handling for |
-- + SELECT TRUE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false | true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x & 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 & x);

-- TEST: null handling for &
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(null & 0);

-- TEST: null handling for &
-- + SELECT NULL;
-- + {select_stmt}: _select_: { _anon: null }
-- - error:
select const(0 & null);

-- TEST: bool handling for &
-- + SELECT FALSE;
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- - error:
select const(false & true);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x is 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 is x);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x is not 1);

-- TEST: forcing errors in binary operators to make them prop:  normal binary
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 is not x);

-- TEST: forcing errors in binary operators to make them prop:  and error in first arg
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x and 0);

-- TEST: forcing errors in binary operators to make them prop:  and error in second arg
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 and x);

-- TEST: forcing errors in binary operators to make them prop:  or: error in first arg
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(x or 0);

-- TEST: forcing errors in binary operators to make them prop:  or: force error in second arg
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(0 or x);

-- TEST: forcing errors in binary operators to make them prop:  and: force error in 2nd arg
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(1 and x);

-- TEST: forcing errors in cast
-- + error: % evaluation of constant failed
-- + {const}: err
-- +1 error:
select const(cast(x as real));

-- TEST: with expression, duplicate columnms
-- + error: % duplicate name in list 'a'
-- +1 error:
with some_cte(a, a) as (select 1,2)
select 1;

-- TEST: with expression, duplicate cte name
-- + error: % duplicate common table name 'some_cte'
-- +1 error:
with
 some_cte(a, b) as (select 1,2),
 some_cte(a, b) as (select 1,2)
select 1;

-- TEST: with expression, too few columns
-- + error: % too few column names specified in common table expression 'some_cte'
-- +1 error:
with some_cte(a) as (select 1,2)
select 1;

-- TEST: with expression, too few columns
-- + error: % too many column names specified in common table expression 'some_cte'
-- +1 error:
with some_cte(a, b, c) as (select 1,2)
select 1;

-- TEST: with expression, broken inner select
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
with some_cte(a) as (select not 'x')
select 1;

-- TEST: with expression, broken inner select
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
with some_cte(a) as (select 1)
select not 'x';

-- TEST: basic with expression
-- - error:
with some_cte(a, b) as (select 1,2)
select a, b from some_cte;

-- TEST: make sure that the overall result of the CTE is nullable
-- even if the first branch of the CTE (which is its provisional definition)
-- is not nullable
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- + {with_select_stmt}: _select_: { a: integer }
-- + {cte_tables}: ok
-- + {cte_table}: some_cte: { a: integer }
-- + {cte_decl}: some_cte: { a: integer }
-- + {select_stmt}: union_all: { x: integer }
-- + {select_core}: _select_: { x: integer notnull }
-- + {select_core}: _select_: { x: null }
-- - error:
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
-- WARNING easily broken do not change this test especially not nullability
with
  some_cte(a) as (select 1 x union all select null x)
  select * from some_cte;

-- TEST: nested CTE -- note scoping
-- - error:
-- +2 {cte_table}: y: { a: integer notnull, b: integer notnull }
with x(a,b) as (select 1,2)
select * from x as X
inner join ( with y(a,b) as (select 1,3) select * from y ) as Y
on X.a = Y.a
inner join ( with y(a,b) as (select 1,3) select * from y ) as Z
on X.a = Z.a;

-- TEST: with recursive
-- - error:
-- + {with_select_stmt}: _select_: { current: integer notnull }
-- + {with_recursive}
-- + {cte_decl}: cnt: { current: integer notnull }
with recursive
  cnt(current) AS (
     select 1
     union all
     select current+1 from cnt
     limit 10
  )
select current from cnt;

-- TEST: CTE body that uses with_select
-- + {with_select_stmt}: _select_: { x: real notnull, y: real notnull, u: integer notnull, v: integer notnull }
-- + {with_select_stmt}: _select_: { x: real notnull, y: real notnull }
-- - error:
with
  some_cte(*) as (select 1 u, 2 v),
  another_cte(*) as (
    with baz(*) as (
      select 2.0 x, 3.0 y
    union all
      select * from baz
    limit 5)
    select * from baz
 )
select * from another_cte join some_cte;

-- TEST: a CTE may not shadow an existing table
-- + error: % common table name shadows previously declared table or view 'foo'
-- + {with_select_stmt}: err
-- + {cte_tables}: err
-- + {cte_table}: err
-- + {cte_decl}: err
-- +1 error:
with
  foo(*) as (select 1 x)
select * from foo;

-- TEST: a CTE may not shadow an existing view
-- + error: % common table name shadows previously declared table or view 'MyView'
-- + {with_select_stmt}: err
-- + {cte_tables}: err
-- + {cte_table}: err
-- + {cte_decl}: err
-- +1 error:
with
  MyView(*) as (select 1 x)
select * from MyView;

-- TEST: a CTE within a shared fragment may not shadow an existing table or
-- view; this applies to all procs, not just those that are shared fragments
-- + error: % common table name shadows previously declared table or view 'foo'
-- + error: % common table name shadows previously declared table or view 'MyView'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +2 {with_select_stmt}: err
-- +2 {cte_tables}: err
-- +2 {cte_table}: err
-- +2 {cte_decl}: err
-- +2 error:
[[shared_fragment]]
proc shadows_an_existing_table()
begin
  with
    -- applies to the LIKE form as well
    foo(*) like (select 1 x)
  select * from foo;
  with
    MyView(*) as (select 1 x)
  select * from MyView;
end;

-- TEST: a CTE within a shared fragment may be given the name of a table or view
-- that has yet to be defined; this applies to all procs, not just those that
-- are shared fragments
-- + {stmt_and_attr}: ok
-- + {create_proc_stmt}: does_not_shadow_an_existing_table: { x: integer notnull } dml_proc
-- - error:
[[shared_fragment]]
proc does_not_shadow_an_existing_table()
begin
  with
    table_not_yet_defined(*) as (select 1 x)
  select * from table_not_yet_defined;
end;

-- used in the following test
-- - error:
create table table_not_yet_defined(y text);

-- TEST: a shared fragment containing a CTE of the same name as a now-defined
-- table is okay to use
-- + {with_select_stmt}: _select_: { x: integer notnull }
-- - error:
with
  (call does_not_shadow_an_existing_table())
select * from does_not_shadow_an_existing_table;

-- TEST: empty fragments are invalid for all fragment types
-- + error: % fragments may not have an empty body 'empty_fragment'
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc empty_fragment()
begin
end;

-- TEST: create a shared fragment we can use in the frag tests
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name shared_fragment}
-- + {create_proc_stmt}: a_shared_frag: { x: integer notnull, y: integer notnull, z: real notnull } dml_proc
-- - error:
[[shared_fragment]]
proc a_shared_frag(x int!, y int!)
begin
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: use the fragment in a nested select : easiest option
-- + {shared_cte}: a_shared_frag: { x: integer notnull, y: integer notnull, z: real notnull } dml_proc
-- - error:
select * from (call a_shared_frag(1, 2));

-- TEST: use the fragment in a nested select : easiest option but with error
-- + error: % too few arguments provided to procedure 'a_shared_frag'
-- + {shared_cte}: err
-- +1 error:
select * from (call a_shared_frag());

-- TEST: fragment in nested select cannot be referred to without explict alias
-- + error: % table not found 'a_shared_frag'
-- + {select_expr_list}: err
-- +1 error:
select a_shared_frag.* from (call a_shared_frag(1, 2));

-- TEST: a conditional shared fragment without an else clause is equivalent to
-- putting "select nothing" in an else clause.
-- + {select_nothing_stmt}: conditional_no_else: { x: integer notnull }
-- - error
[[shared_fragment]]
proc conditional_no_else()
begin
  if 1 then
    select 1 x;
  end if;
end;

-- TEST: try to use select nothing in an illegal context
-- + error: % SELECT NOTHING may only appear in the ELSE clause of a shared fragment
-- + {create_proc_stmt}: err
-- + {select_nothing_stmt}: err
-- +1 error:
proc not_valid_proc_for_select_nothing()
begin
  select nothing;
end;

-- TEST: select nothing expands to whatever is needed to give no rows
-- + {select_nothing_stmt}: _select_: { x: integer notnull }
-- - error
[[shared_fragment]]
proc conditional_else_nothing()
begin
  if 1 then
    select 1 x;
  else
    select nothing;
  end if;
end;

-- TEST: create a conditional fragment with matching like clauses in both branches
-- + {create_proc_stmt}: ok_conditional_duplicate_cte_names: { x: integer notnull, y: integer notnull, z: real notnull } dml_proc
-- - error:
[[shared_fragment]]
proc ok_conditional_duplicate_cte_names()
begin
  if 1 then
    with X(*) like a_shared_frag
    select * from X;
  else
    with X(*) like a_shared_frag
    select * from X;
  end if;
end;

-- TEST: create a conditional fragment with not matching like clauses
-- + error: % bogus_cte, all must have the same column count
-- + {create_proc_stmt}: err
-- diagnostics also present
-- +4 error:
[[shared_fragment]]
proc bogus_conditional_duplicate_cte_names()
begin
  /* note that these branches return the same type so the proc looks ok
     but it's still wrong because bogus_cte is not of the same type
     here we did his by ignoring bogus_cte but it doesn't matter how you arrange it;
     you might just select id out of bogus_cte or something.
   */
  if 1 then
    with bogus_cte(*) like a_shared_frag
    select 1 x;
  else
    with bogus_cte(*) like foo
    select 1 x;
  end if;
end;

-- TEST: create a conditional fragment with no else
-- + error: % shared fragments with conditionals must have exactly one SELECT, or WITH...SELECT in each statement list 'bogus_conditional_two_selects'
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc bogus_conditional_two_selects()
begin
  if 1 then
    select 1 x;
    select 1 x;
  else
    select 1 x;
  end if;
end;

-- TEST: create a conditional fragment with a non-select statement
-- + error: % shared fragments with conditionals must have exactly SELECT, or WITH...SELECT in each statement list 'bogus_conditional_non_select'
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc bogus_conditional_non_select()
begin
  if 1 then
    declare x integer;
  else
    select 1 x;
  end if;
end;

-- TEST: create a conditional fragment with an empty if clause
-- + error: % shared fragments with conditionals must have exactly one SELECT, or WITH...SELECT in each statement list 'bogus_conditional_empty_clause'
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc bogus_conditional_empty_clause()
begin
  if 1 then
  else
    select 1 x;
  end if;
end;

-- TEST: create a conditional fragment with an empty else clause
-- + error: % shared fragments with conditionals must have exactly one SELECT, or WITH...SELECT in each statement list 'bogus_conditional_empty_else_clause'
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc bogus_conditional_empty_else_clause()
begin
  if 1 then
    select 1 x;
  else
  end if;
end;

-- TEST: cannot call shared fragments outside of a SQL context
-- + error: % shared fragments may not be called outside of a SQL statement 'a_shared_frag'
-- + {call_stmt}: err
-- +1 error:
call a_shared_frag();

-- TEST: create a shared fragment with a parameter for later use
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name shared_fragment}
-- + {create_proc_stmt}: shared_frag2: { x: integer notnull, y: integer notnull, z: real notnull } dml_proc
-- - error:
[[shared_fragment]]
proc shared_frag2(x int!, y int!)
begin
  with source(*) LIKE a_shared_frag
  select * from source;
end;

-- TEST: try to use the shared frag without the needed USING clause
-- + error: % no actual table was provided for the table parameter 'source'
-- + {with_select_stmt}: err
-- +1 error:
with (call shared_frag2(1,2))
select * from a_shared_frag;

-- a typedef
-- - error:
declare proc frag_type() (id integer<job>, name text);

-- TEST: create a shared fragment that requires a particular type kind
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name shared_fragment}
-- + {create_proc_stmt}: shared_frag3: { id: integer<job>, name: text } dml_proc
-- + {cte_table}: source: { id: integer<job>, name: text }
-- - error:
[[shared_fragment]]
proc shared_frag3()
begin
  with source(*) LIKE frag_type
  select * from source;
end;

create table jobstuff(id integer<job>, name text);
create table bad_jobstuff(id integer<meters>, name text);

-- TEST: try to use fragment with correct type kind
-- + {with_select_stmt}: _select_: { id: integer<job>, name: text }
-- - error:
with
  data(*) as (call shared_frag3() using jobstuff as source)
  select * from data;

-- TEST: try to use fragment with incorrect type kind
-- + error: % expressions of different kinds can't be mixed: 'meters' vs. 'job'
-- + {with_select_stmt}: err
-- +1 error:
with
  data(*) as (call shared_frag3() using bad_jobstuff as source)
  select * from data;

-- TEST: create a shared fragment but use a reference to a shape that doesn't exist
-- + error: % must be a cursor, proc, table, or view 'there_is_no_such_source'
-- + {with_select_stmt}: err
-- +1 error:
[[shared_fragment]]
proc shared_frag_bad_like()
begin
  with source(*) LIKE there_is_no_such_source
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: try to use LIKE outside of a procedure
-- + error: % LIKE CTE form may only be used inside a shared fragment at the top level i.e. [[shared_fragment]]
-- + {with_select_stmt}: err
-- +1 error:
with source(*) LIKE there_is_no_such_source
select 1 x, 2 y, 3.0 z;

-- TEST: try to use LIKE in a procedure that is not a shared fragment
-- + error: % LIKE CTE form may only be used inside a shared fragment at the top level i.e. [[shared_fragment]] 'not_a_shared_fragment'
-- + {with_select_stmt}: err
-- +1 error:
proc not_a_shared_fragment()
begin
  with source(*) LIKE there_is_no_such_source
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: try to use the shared fragment with a table arg even though it has none
-- + error: % called procedure has no table arguments but a USING clause is present 'a_shared_frag'
-- + {with_select_stmt}: err
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z),
  x(*) AS (call a_shared_frag(1, 2) USING some_cte as foo)
  select * from x;

-- TEST: try to use the shared fragment with a table arg but don't provide the arg
-- + error: % no actual table was provided for the table parameter 'source'
-- + {with_select_stmt}: err
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z),
  x(*) AS (call shared_frag2(1, 2) USING some_cte as foo)
  select * from x;

-- TEST: try to use the shared fragment with a table arg but have duplicate arg names
-- + error: % duplicate binding of table in CALL/USING clause 'bar'
-- + {with_select_stmt}: err
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z),
  x(*) AS (call shared_frag2(1, 2) USING source as bar, source as bar)
  select * from x;

-- TEST: try to use the shared fragment with a table arg but have extra arguments
-- + error: % an actual table was provided for a table parameter that does not exist 'bogus'
-- + {with_select_stmt}: err
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z),
  x(*) AS (call shared_frag2(1, 2) USING some_cte as source, some_cte as bogus)
  select * from x;

-- TEST: try to use the shared fragment with a table arg that isn't actually a table
-- + error: % table/view not defined 'bogus'
-- + {with_select_stmt}: err
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z),
  x(*) AS (call shared_frag2(1, 2) USING bogus as source)
  select * from x;

-- TEST: try to use the shared fragment with a table arg that has the wrong arg count
-- + error: % table provided must have the same number of columns as the table parameter 'some_cte'
-- + {with_select_stmt}: err
-- + {name some_cte}: some_cte: { x: integer notnull, y: integer notnull, z: real notnull, u: integer notnull }
-- + {name source}: source: { x: integer notnull, y: integer notnull, z: real notnull }
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 z, 4 u),
  x(*) AS (call shared_frag2(1, 2) USING some_cte as source)
  select * from x;

-- TEST: try to use the shared fragment with a table arg that is missing a column
-- + error: % table argument 'source' requires column 'z' but it is missing in provided table 'some_cte'
-- + {with_select_stmt}: err
-- + {name some_cte}: some_cte: { x: integer notnull, y: integer notnull, w: real notnull }
-- + {name source}: source: { x: integer notnull, y: integer notnull, z: real notnull }
-- +1 error:
with
  some_cte(*) as (select 1 x, 2 y, 3.0 w),
  x(*) AS (call shared_frag2(1, 2) USING some_cte as source)
  select * from x;

-- TEST: try to use the shared fragment with a table arg that is of the wrong type
-- + error: % required 'REAL' not compatible with found 'TEXT' context 'z'
-- + error: % additional info: provided table column 'some_cte.z' is not compatible with target 'source.z'
-- + {with_select_stmt}: err
-- + {name some_cte}: err
-- + {name source}: source: { x: integer notnull, y: integer notnull, z: real notnull }
-- +2 error:
with
  some_cte(*) as (select 1 x, 2 y, '3.0' z),
  x(*) AS (call shared_frag2(1, 2) USING some_cte as source)
  select * from x;

-- TEST: try to use LIKE in a procedure that is a shared fragment but not at the top level
-- + error: % LIKE CTE form may only be used inside a shared fragment at the top level i.e. [[shared_fragment]] 'bogus_like_in_shared'
-- + {with_select_stmt}: err
-- +1 error:
[[shared_fragment]]
proc bogus_like_in_shared()
begin
  with data(*) AS (
     with source(*) LIKE there_is_no_such_source
     select * from source
  )
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: create a shared fragment with an unbound table but botch the CTE decl
-- + error: % too few column names specified in common table expression 'source'
-- + {with_select_stmt}: err
-- +1 error:
[[shared_fragment]]
proc shared_frag_bad_like_decl()
begin
  with source(u) LIKE a_shared_frag
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: create a shared fragment but use a bogus CTE declaration
-- + error: % duplicate name in list 'id'
-- + {with_select_stmt}: err
-- +1 error:
[[shared_fragment]]
proc shared_frag_bogus_cte_columns()
begin
  with source(id, id) LIKE (select 1 x, 2 y)
  select 1 x, 2 y, 3.0 z;
end;

-- TEST: use a shared fragment but with a bad CTE declaration
-- + error: % duplicate name in list 'id'
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(id, id) as (call a_shared_frag(1,2))
select * from some_cte;

-- TEST: use the general form of the with CTE but with an error
-- + error: % duplicate name in list 'goo'
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(*) as (
  with garbonzo(goo, goo) as (select 1 x, 2 y)
  select * from garbonzo)
select * from some_cte;

-- TEST: use the general form of the with CTE but with an error in the outer cte_decl
-- + error: % duplicate name in list 'goo'
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(goo, goo) as (
  with garbonzo(*) as (select 1 x, 2 y)
  select * from garbonzo)
select * from some_cte;

-- TEST: use the shared fragment, simple correct case
-- + {with_select_stmt}: _select_: { x: integer notnull, y: integer notnull, z: real notnull }
-- + {cte_tables}: ok
-- + {cte_table}: some_cte: { x: integer notnull, y: integer notnull, z: real notnull }
-- + {call_stmt}: a_shared_frag: { x: integer notnull, y: integer notnull, z: real notnull } dml_proc
-- - error:
with some_cte(*) as (call a_shared_frag(1,2))
select * from some_cte;

-- TEST: the call form must call a shared fragment
-- + error: % a CALL statement inside SQL may call only a shared fragment i.e. [[shared_fragment]] 'return_with_attr'
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(*) as (call return_with_attr())
select * from some_cte;

-- TEST: the call form must make a valid call
-- + error: % calls to undeclared procedures are forbidden; declaration missing or typo 'this_is_not_even_a_proc'
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(*) as (call this_is_not_even_a_proc())
select * from some_cte;

-- TEST: shared_fragment attribute (correct usage, has with clause)
-- + {create_proc_stmt}: test_shared_fragment_with_CTEs: { x: integer notnull, y: text, z: longint } dml_proc
-- - error:
[[shared_fragment]]
proc test_shared_fragment_with_CTEs(id_ int!)
begin
  with
    t1(id) as (select id from foo where id = id_ limit 20),
    t2(x,y,z) as (select t1.id, name, rate from bar inner join t1 on t1.id = bar.id)
  select * from t2;
end;

-- TEST: shared_fragment attribute (correct usage)
-- + {create_proc_stmt}: test_shared_fragment_without_CTEs: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[shared_fragment]]
proc test_shared_fragment_without_CTEs(id_ int!)
begin
  select id, name, rate from bar where id = id_;
end;

-- TEST: shared_fragment attribute (incorrect usage)
-- + error: % shared fragments must consist of exactly one top level statement 'test_shared_fragment_wrong_form'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc test_shared_fragment_wrong_form()
begin
  select * from bar;
  select * from bar;
end;

-- TEST: shared_fragment attribute (incorrect usage)
-- + error: % shared fragments cannot have any out or in/out parameters 'x'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc test_shared_fragment_bad_args(out x integer)
begin
  select * from bar;
end;

-- TEST: shared_fragment attribute (incorrect usage)
-- + error: % shared fragments may only have IF, SELECT, or WITH...SELECT at the top level 'test_shared_fragment_wrong_form_not_select'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[shared_fragment]]
proc test_shared_fragment_wrong_form_not_select()
begin
  declare x integer;
end;

-- TEST: with recursive with error in the definition
-- + error: % duplicate name in list 'current'
-- +1 error:
with recursive
  cnt(current, current) AS (
     select 1
     union all
     select current+1 from cnt
     limit 10
  )
select current from cnt;

-- TEST: with recursive error in the base case
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
with recursive
  cnt(current) AS (
     select not 'x'
     union all
     select current+1 from cnt
     limit 10
  )
select current from cnt;

-- TEST: with recursive error in the main case
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
with recursive
  cnt(current) AS (
     select 1
     union all
     select not 'x'
  )
select current from cnt;

-- TEST: with recursive error in the output select
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
with recursive
  cnt(current) AS (
     select 1
     union all
     select current+1 from cnt
     limit 10
  )
select not 'x';

-- TEST: verify the shape of tree with many unions
-- here we're checking to make sure Y is loose at the end of the chain
-- and the two X variables came before in the tree
-- + {name X}: X: integer variable
-- + {select_core_compound}
-- + {name X}: X: integer variable
-- + {select_core_compound}
-- + {name Y}: Y: integer variable
select X as A
union all
select X as A
union all
select Y as A;

-- TEST: verify that we can create a view that is based on a CTE
-- + {with_select_stmt}: view_with_cte: { x: integer notnull }
-- + {cte_table}: goo: { x: integer notnull }
-- - error:
create view view_with_cte as
with
goo(x) as (select 1)
select * from goo;

-- TEST: verify that we can use non-simple selects inside of an IN
-- + {select_expr}: A: bool notnull
-- + {in_pred}: bool notnull
-- + {select_stmt}: _anon: integer
-- - error:
select 1 in (select 1 union all select 2 union all select 3) as A;

-- TEST: use table.* syntax to get one table
-- verify rewrite
-- + SELECT
-- + 0 AS _first,
-- + T.A,
-- + T.B,
-- + 3 AS _last
-- + FROM
-- + {select_stmt}: _select_: { _first: integer notnull, A: integer notnull, B: integer notnull, _last: integer notnull }
-- - error:
select 0 as _first, T.*, 3 as _last from (select 1 as A, 2 as B) as T;

-- TEST: use table.* syntax to get two tablesSELECT
-- verify rewrite
-- + SELECT
-- + 0 AS _first,
-- + T.A,
-- + T.B,
-- + S.C,
-- + 3 AS _last
-- + FROM
-- + {select_stmt}: _select_: { _first: integer notnull, A: integer notnull, B: integer notnull, C: integer notnull, _last: integer notnull }
-- - error:
select 0 as _first, T.*, S.*, 3 as _last from (select 1 as A, 2 as B) as T, (select 1 as C) as S;

-- TEST: try to use T.* with no from clause
-- + error: % select *, T.*, or @columns(...) cannot be used with no FROM clause
-- + {table_star}: err
select T.*;

-- TEST: try to use T.* where T does not exist
-- + error: % table not found 'T'
-- + {column_calculation}: err
select T.* from (select 1) as U;

-- TEST: simple test for function
-- + FUNC simple_func (arg1 INT!) REAL!;
-- + name simple_func}: real notnull
-- + {params}: ok
-- + {param}: arg1: integer notnull variable in
-- - error:
func simple_func(arg1 int!) real!;

-- TEST: error duplicate function
-- + error: % FUNC simple_func (arg1 INT) REAL!
-- + error: % FUNC simple_func (arg1 INT!) REAL!
-- + error: % duplicate function name 'simple_func'
-- +3 error:
func simple_func(arg1 integer) real!;

-- TEST: error declare proc conflicts with func
-- + error: % proc name conflicts with func name 'simple_func'
-- +1 error:
declare proc simple_func(arg1 int!);

-- TEST: error declare proc conflicts with func
-- + error: % proc name conflicts with func name 'simple_func'
-- +1 error:
proc simple_func(arg1 int!)
begin
  select 1;
end;

-- TEST: error function that conflicts with a proc
-- + error: % func name conflicts with proc name 'proc1'
-- +1 error:
func proc1(i integer) integer;

-- TEST: try to declare a function inside a proc
-- + error: % declared functions must be top level 'foo'
-- +1 error:
proc nested_func_wrapper()
begin
  function foo() integer;
end;

-- TEST: duplicate function formal
-- + error: % duplicate parameter name 'a'
-- +1 error:
func dup_formal(a integer, a integer) integer;

-- result for the next test
declare real_result real;

-- TEST: simple function call simple return
-- + {assign}: real_result: real variable
-- + {name real_result}: real_result: real variable
-- + {call}: real notnull
-- + {name simple_func}
-- + {arg_list}: ok
-- + {int 1}: integer notnull
-- - error:
set real_result := simple_func(1);

-- TEST: function call with bogus arg type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'arg1'
-- + error: % additional info: calling 'simple_func' argument #1 intended for parameter 'arg1' has the problem
-- + {assign}: err
-- + {call}: err
-- +2 error:
set real_result := simple_func('xx');

-- TEST: function call with invalid args
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'simple_func' argument #1 intended for parameter 'arg1' has the problem
-- + {assign}: err
-- + {call}: err
-- +2 error:
set real_result := simple_func(not 'xx');

-- TEST: try to use user func in a sql statement
-- + error: % User function may not appear in the context of a SQL statement 'simple_func'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select simple_func(1);

-- TEST: declare an object variable
-- + {name obj_var}: obj_var: object variable
-- - error:
declare obj_var object;

-- TEST: error on ordered comparisons (left)
-- + error: % left operand cannot be an object in '<'
-- +1 error:
set X := obj_var < 1;

-- TEST: error on ordered comparisons (right)
-- + error: % right operand cannot be an object in '<'
-- +1 error:
set X := 1 < obj_var;

-- TEST: ok to compare objects to each other with equality
-- + {eq}: bool
-- - error:
set X := obj_var == obj_var;

-- TEST: ok to compare objects to each other with inequality
-- + {ne}: bool
-- - error:
set X := obj_var <> obj_var;

-- TEST: error on math with object (left)
-- + error: % left operand cannot be an object in '+'
-- +1 error:
set X := obj_var + 1;

-- TEST: error on ordered comparisons (right)
-- + error: % right operand cannot be an object in '+'
-- +1 error:
set X := 1 + obj_var;

-- TEST: error on unary not
-- + error: % object operand not allowed in 'NOT'
-- + {not}: err
-- +1 error:
set X := not obj_var;

-- TEST: error on unary negation
-- + error: % object operand not allowed in '-'
-- + {uminus}: err
-- +1 error:
set X := - obj_var;

-- TEST: assign object to string
-- + error: % required 'TEXT' not compatible with found 'OBJECT' context 'a_string'
-- + {name a_string}: err
-- +1 error:
set a_string := obj_var;

-- TEST: assign string to an object
-- + error: % required 'OBJECT' not compatible with found 'TEXT' context 'obj_var'
-- + {name obj_var}: err
-- +1 error:
set obj_var := a_string;

-- TEST: create proc with object arg
-- + {param}: an_obj: object variable out
-- - error:
proc obj_proc(out an_obj object)
begin
  set an_obj := null;
end;

-- TEST: try to create a table with an object column
-- + error: % tables cannot have object columns 'obj'
-- + {col_def}: err
-- +1 error:
create table object_table_test(
  obj object
);

-- TEST: try to use an object variable in a select statement
-- + error: % object variables may not appear in the context of a SQL statement (except table-valued functions) 'obj_var'
-- + {name obj_var}: err
-- +1 error:
select obj_var;

-- TEST: try to use an object variable in an IN statement, that's ok
-- + {in_pred}: bool
-- + {expr_list}: obj_var: object variable
-- - error:
set X := obj_var in (obj_var, null);

-- TEST: bogus in statement with object variable, combining with numeric
-- + error: % required 'OBJECT' not compatible with found 'INT' context 'IN'
-- + {in_pred}: err
-- +1 error:
set X := obj_var in (obj_var, 1);

-- TEST: bogus in statement with object variable, combining with text
-- + error: % required 'OBJECT' not compatible with found 'TEXT' context 'IN'
-- + {in_pred}: err
-- +1 error:
set X := obj_var in ('foo', obj_var);

-- TEST: bogus in statement with object variable, searching for text with object in list
-- + error: % required 'TEXT' not compatible with found 'OBJECT' context 'IN'
-- + {in_pred}: err
-- + {expr_list}: text notnull
-- +1 error:
set X := 'foo' in ('foo', obj_var);

-- TEST: case statement using objects as test condition
-- + {assign}: X: integer variable
-- + {case_expr}: integer notnull
-- + {name obj_var}: obj_var: object variable
-- - error:
set X := case obj_var when obj_var then 2 else 3 end;

-- TEST: case statement using objects as result
-- + {assign}: obj_var: object variable
-- + {name obj_var}: obj_var: object variable
-- + {case_expr}: object
-- + {case_list}: object variable
-- + {when}: obj_var: object variable
-- + {null}: null
-- - error:
set obj_var := case 1 when 1 then obj_var else null end;

-- TEST: between with objects is just not happening, first case
-- + error: % first operand cannot be an object in 'BETWEEN'
-- +1 error:
set X := obj_var between 1 and 3;

-- TEST: between with objects is just not happening, second case;
-- + error: % required 'INT' not compatible with found 'OBJECT' context 'BETWEEN'
-- +1 error:
set X := 2 between obj_var and 3;

-- TEST: between with objects is just not happening, third case;
-- + error: % required 'INT' not compatible with found 'OBJECT' context 'BETWEEN'
-- +1 error:
set X := 2 between 1 and obj_var;

-- TEST: not between with objects similarly not supported, first case
-- + error: % first operand cannot be an object in 'NOT BETWEEN'
-- +1 error:
set X := obj_var not between 1 and 3;

-- TEST: not between with objects similarly not supported, second case;
-- + error: % required 'INT' not compatible with found 'OBJECT' context 'NOT BETWEEN'
-- +1 error:
set X := 2 not between obj_var and 3;

-- TEST: not between with objects similarly not supported, third case;
-- + error: % required 'INT' not compatible with found 'OBJECT' context 'NOT BETWEEN'
-- +1 error:
set X := 2 not between 1 and obj_var;

-- TEST: make a function that creates an not null object
-- + {name creater_func}: object notnull create_func
-- - error:
func creater_func() create object not null;

-- TEST: make a function that creates an nullable
-- + declare_func_stmt}: object create_func
-- - error:
func maybe_create_func() create object;

-- Storage for these next few tests
-- - error:
declare not_null_object object not null;

-- TEST: convert object to not null
-- + {assign}: not_null_object: object notnull variable
-- + {name not_null_object}: not_null_object: object notnull variable
-- - error:
set not_null_object := ifnull_crash(obj_var);

-- TEST: convert object to not null -- ifnull_crash form
-- + {assign}: not_null_object: object notnull variable
-- + {name not_null_object}: not_null_object: object notnull variable
-- - error:
set not_null_object := ifnull_crash(obj_var);

-- TEST: convert object to not null (throw semantic) -- same code path as above
-- + {assign}: not_null_object: object notnull variable
-- + {name not_null_object}: not_null_object: object notnull variable
-- - error:
set not_null_object := ifnull_throw(obj_var);

-- TEST: attest with matching kind, ok to go
-- + {assign}: price_d: real<dollars> variable
-- + {name price_d}: price_d: real<dollars> variable
-- + {call}: price_d: real<dollars> notnull variable
set price_d := ifnull_crash(price_d);

-- TEST: attest should copy the semantic info including kind, hence can produce errors
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {assign}: err
-- +1 error:
set price_d := ifnull_crash(price_e);

-- TEST: convert to not null -- fails already not null
-- + error: % argument must be a nullable type (but not constant NULL) in 'ifnull_crash'
-- + {call}: err
-- +1 error:
set not_null_object := ifnull_crash(not_null_object);

-- TEST: convert to not null -- fails can't do this to 'null'
-- + error: % argument 1 is a NULL literal; useless in 'ifnull_crash'
-- + {call}: err
-- +1 error:
set not_null_object := ifnull_crash(null);

-- TEST: convert to not null -- fails wrong arg count
-- + error: % too many arguments in function 'ifnull_crash'
-- + {call}: err
-- +1 error:
set not_null_object := ifnull_crash(1, 7);

-- TEST: convert to not null -- fails in SQL context
-- + error: % function may not appear in this context 'ifnull_crash'
-- + {call}: err
-- +1 error:
set not_null_object := (select ifnull_crash(1));

-- TEST: echo statement is ok in any top level context
-- + {echo_stmt}: ok
-- + {name c}
-- + {strlit 'foo\n'}
-- - error:
@echo c, 'foo\n';

-- TEST: simple typed object declaration
-- + declare_vars_type}: object<Foo>
-- + {name_list}: foo_obj: object<Foo> variable
-- + {name foo_obj}: foo_obj: object<Foo> variable
-- + {type_object}: object<Foo>
-- + {name Foo}
-- - error:
declare foo_obj object<Foo>;

-- TEST: simple typed object assignment
-- + {assign}: foo_obj: object<Foo> variable
-- + {name foo_obj}: foo_obj: object<Foo> variable
-- + {name foo_obj}: foo_obj: object<Foo> variable
-- - error:
set foo_obj := foo_obj;

-- TEST: function with typed object return type
-- + {declare_func_stmt}: object<Foo>
-- - error:
func foo_func() object<Foo>;

-- TEST: function with typed object return type
-- + {assign}: foo_obj: object<Foo> variable
-- + {name foo_obj}: foo_obj: object<Foo> variable
-- + {call}: object<Foo>
-- - error:
set foo_obj := foo_func();

-- TEST: some different object type
-- + {declare_vars_type}: object<Bar>
-- + {name_list}: bar_obj: object<Bar> variable
-- - error:
declare bar_obj object<Bar>;

-- TEST: assign Bar to a Foo
-- + error: % expressions of different kinds can't be mixed: 'Bar' vs. 'Foo'
-- +1 error:
set bar_obj := foo_obj;

-- TEST: case statement must have uniform return type
-- + error: % expressions of different kinds can't be mixed: 'Bar' vs. 'Foo'
-- +1 error:
set bar_obj := case 1 when 1 then bar_obj when 2 then foo_obj end;

-- TEST: case statement errors in then expr
-- + error: % name not found 'bar_object'
-- +1 error:
set bar_obj := case 1 when 1 then bar_object when 2 then foo_obj end;

-- TEST: case statement must have uniform return type
-- + error: % expressions of different kinds can't be mixed: 'Bar' vs. 'Foo'
-- +1 error:
set bar_obj := case 1 when 1 then bar_obj else foo_obj end;

-- TEST: case statement errors in else
-- + error: % name not found 'foo_object'
-- +1 error:
set bar_obj := case 1 when 1 then bar_obj else foo_object end;

-- TEST: case statement typed object no errors
-- + {assign}: bar_obj: object<Bar> variable
-- + {name bar_obj}: bar_obj: object<Bar> variable
-- + {case_expr}: object<Bar>
-- - error:
set bar_obj := case 1 when 1 then bar_obj when 2 then bar_obj else bar_obj end;

-- TEST: non-user func with bogus arg
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'simple_func' argument #1 intended for parameter 'arg1' has the problem
-- + {call_stmt}: err
-- +2 error:
call printf('%d', simple_func(not 'x'));

-- TEST: insert with column names, types match
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- - error:
insert into bar(id, name, rate) values (1, '2', 3);

-- TEST: insert with auto increment column null ok
-- + {insert_stmt}: ok
-- + {name_columns_values}
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- - error:
insert into foo(id) values (NULL);

-- TEST: insert missing column
-- + error: % required column missing in INSERT statement 'id'
-- + {insert_stmt}: err
-- +1 error:
insert into bar(name) values ('x');

-- TEST: insert column name doesn't exist
-- + error: % name not found 'garbonzo'
-- + {insert_stmt}: err
-- +1 error:
insert into bar(garbonzo) values ('x');

-- TEST: insert duplicate column name
-- + error: % name list has duplicate name 'id'
-- + {insert_stmt}: err
-- +1 error:
insert into bar(id, id) values ('x');

-- TEST: insert column with default value
-- + {insert_stmt}: ok
-- + {name booly}: booly: { id: integer has_default, flag: bool }
-- - error:
insert into booly(id) values (1);

-- TEST: insert into a view (with columns)
-- + error: % cannot insert into a view 'MyView'
-- +1 error:
-- + {insert_stmt}: err
-- + {name MyView}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
insert into MyView(id) values (1);

-- TEST: insert into non existent table
-- + error: % table in insert statement does not exist 'garbonzo'
-- + {insert_stmt}: err
-- +1 error:
insert into garbonzo(id) values ('x');

-- TEST: declare a function with object arg type
-- + {param_detail}: goo: object<Goo> variable in
-- - error:
func goo_func(goo object<Goo>) text;

-- TEST: function with mismatched arg type
-- + error: % expressions of different kinds can't be mixed: 'Goo' vs. 'Bar'
-- + error: % additional info: calling 'goo_func' argument #1 intended for parameter 'goo' has the problem
-- + {assign}: err
-- +2 error:
set a_string := goo_func(bar_obj);

-- TEST: user function with bogus arg
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'goo_func' argument #1 intended for parameter 'goo' has the problem
-- + {assign}: err
-- +2 error:
set a_string := goo_func(not 'x');

-- TEST: insert columns with mismatched count
-- + error: % count of columns differs from count of values
-- + {insert_stmt}: err
-- +1 error:
insert into foo(id) values (NULL, NULL);

-- TEST: insert columns with error in expression
-- + error: % string operand not allowed in 'NOT'
-- + {insert_stmt}: err
-- +1 error:
insert into foo(id) values (not 'x');

-- TEST: insert auto inc column with not null value
-- + {insert_stmt}: ok
-- + {name_columns_values}
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- - error:
insert into foo(id) values (1);

-- TEST: insert with not matching column types
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + {insert_stmt}: err
-- +1 error:
insert into bar(id) values ('x');

-- TEST: create a temporary view
-- + {create_view_stmt}: temp_view: { A: integer notnull, B: integer notnull }
-- this is the temp flag
-- + {int 1}
-- + {view_details_select}
-- + {view_details}
-- + {name temp_view}
-- + {select_stmt}: temp_view: { A: integer notnull, B: integer notnull }
-- - error:
create temp view temp_view as select 1 A, 2 B;

-- TEST: alter a table, adding a nullable column
-- + {alter_table_add_column_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {col_def}: name: text
-- - error:
alter table bar add column name text;

-- TEST: alter a table, adding a nullable column
-- + error: % adding a not nullable column with no default value is not allowed 'name'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column name text not null;

-- TEST: alter a table, adding a column whose declared type does not match
-- + error: % added column must be an exact match for the column type declared in the table 'name'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column name integer;

-- TEST: alter a table, adding a column that was not declared
-- + error: % added column must already be reflected in declared schema, with @create, exact name match required 'goo'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column goo integer;

-- TEST: alter a table, adding a column that was not declared
-- + error: % added column must already be reflected in declared schema, with @create, exact name match required 'NAME'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column NAME text;

-- TEST: alter a table, adding a nullable column
-- + error: % tables cannot have object columns 'foo'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column foo object;

-- TEST: alter a table, adding an autoinc column
-- + error: % adding an auto increment column is not allowed 'id'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table bar add column id integer primary key autoincrement;

-- TEST: alter a table, table doesn't exist
-- + error: % table in alter statement does not exist 'garbonzo'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table garbonzo add column id integer primary key autoincrement;

-- TEST: alter a table, table is a view
-- + error: % cannot alter a view 'MyView'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table MyView add column id integer primary key autoincrement;

-- TEST: try to declare a schema version inside of a proc
-- + error: % schema upgrade version declaration must be outside of any proc
-- +1 error:
proc bogus_version()
begin
  @schema_upgrade_version(11);
end;

-- TEST: try to declare a schema version after tables already defined
-- + error: % schema upgrade version declaration must come before any tables are declared
-- +1 error:
@schema_upgrade_version(11);

-- TEST: try to declare a bogus version number
-- + error: % schema upgrade version must be a positive integer
-- +1 error:
@schema_upgrade_version(0);

-- TEST: try to alter a column with create version specs
-- + error: % version annotations not valid in alter statement 'name'
-- +1 error:
alter table bar add column name text @create(1, bar_upgrader);

-- TEST: try to alter a column with delete version specs
-- + error: % version annotations not valid in alter statement 'name'
-- +1 error:
alter table bar add column name text @delete(1);

-- TEST: try to alter a column with multiple version specs
-- + error: % duplicate version annotation
-- +1 error:
alter table bar add column name text @delete(1) @delete(1);

-- TEST: try to alter a column with multiple version specs
-- + error: % duplicate version annotation
-- +1 error:
alter table bar add column name text @create(1) @create(1);

-- TEST: try to alter a column with bogus version number
-- + error: % version number in annotation must be positive
-- +1 error:
alter table bar add column name text @create(0);

-- TEST: declare a table with a deleted column (should be deleted)
-- + {create_table_stmt}: hides_id_not_name: { name: text }
-- + {col_def}: id: integer deleted
-- + {col_def}: name: text
create table hides_id_not_name(
  id int @delete(2),
  name text @create(3)
);

-- TEST: try to use id from the above
-- + error: % name not found 'id'
-- + {name id}: err
-- +1 error:
select id from hides_id_not_name;

-- TEST: try to use name from the above
-- + {select_stmt}: _select_: { name: text }
-- - error:
select name from hides_id_not_name;

-- TEST: duplicate procedure annotation
-- + error: % a procedure can appear in only one annotation 'creator'
-- + {create_table_stmt}: err
-- + {col_def}: err
-- + {create_attr}: err
-- +1 error:
create table migrate_test(
  id int!,
  id2 integer @create(4, creator),
  id3 integer @create(4, creator)
);

-- TEST: try to declare 'creator' in the wrong version (it should be in 4)
-- + error: % @schema_upgrade_version not declared or doesn't match upgrade version 4 for proc 'creator'
-- + {create_proc_stmt}: err
-- +1 error:
proc creator()
begin
 select 1;
end;

-- TEST: create a table with @create annotations in a bogus order
-- + error: % created columns must be at the end and must be in version order 'col3'
-- +1 error:
create table migrate_annotions_broken(
  col1 integer,
  col2 integer @create(3),
  col3 integer
);

-- TEST: create a table with @create annotations on a not null column
-- + error: % create/delete version numbers can only be applied to columns that are nullable or have a default value 'col2'
-- +1 error:
create table migrate_annotions_broken_not_null_create(
  col1 integer,
  col2 int! @create(3)
);

-- TEST: create a table with @delete annotations on a not null column
-- + error: % create/delete version numbers can only be applied to columns that are nullable or have a default value 'col2'
-- +1 error:
create table migrate_annotions_broken_not_null_delete(
  col1 integer,
  col2 int! @delete(3)
);

-- TEST: create a table with @delete on earlier version than create
-- + error: % column delete version can't be <= column create version 'col2'
-- +1 error:
create table migrate_annotions_delete_out_of_order(
  col1 integer,
  col2 integer @delete(3) @create(4)
);

-- TEST: create a table with versioning
-- + {create_table_stmt}: versioned_table: { id: integer } deleted @create(1) @delete(3)
-- + {int 0}
-- + {create_attr}
-- + {int 1}
-- + {name table_create_proc}
-- + {delete_attr}
-- + {int 3}
-- + {name table_delete_proc}
-- - error:
create table versioned_table(
   id integer @create(2)
) @create(1, table_create_proc) @delete(3, table_delete_proc);

-- TEST: try to use a migration procedure name that ends in _crc
-- + error: % name of a migration procedure may not end in '_crc' 'x_crc'
-- +1 error:
create table bogus_migration_proc(
   id integer
) @create(1, x_crc);

-- TEST: create a table with double creates
-- +1 error: % duplicate version annotation
-- +1 error:
create table versioned_table_double_create(
   id integer
) @create(1) @create(1);

-- TEST: create a table with double delete
-- +1 error: % duplicate version annotation
-- +1 error:
create table versioned_table_double_delete(
   id integer
) @delete(1) @delete(1);

-- TEST: try to create an index on deprecated table
-- + error: % create index table name not found (hidden by @delete) 'versioned_table'
-- + {create_index_stmt}: err
-- +1 error:
create index index_broken on versioned_table(id);

-- TEST: make an FK that refers to a versioned table
-- + error: % foreign key refers to non-existent table (hidden by @delete) 'versioned_table'
-- +1 error:
-- create_table_stmt}: err
create table baz (
  id integer,
  foreign key (id) references versioned_table(id)
);

-- TEST: try to select from a deprecated table
-- + error: % table/view not defined (hidden by @delete) 'versioned_table'
-- +1 error:
select * from versioned_table;

-- TEST: try to alter a deleted table -- DDL is exempt from the existence rules
-- - error:
alter table versioned_table add column id integer;

-- TEST: try to delete from a deprecated table
-- + error: % table in delete statement does not exist (hidden by @delete) 'versioned_table'
-- +1 error:
delete from versioned_table;

-- TEST: try to insert into a deprecated table
-- + error: % table in insert statement does not exist (hidden by @delete) 'versioned_table'
-- +1 error:
insert into versioned_table values (1);

-- TEST: try to insert into a deprecated table (column syntax)
-- + error: % table in insert statement does not exist (hidden by @delete) 'versioned_table'
-- +1 error:
insert into versioned_table(id) values (1);

-- TEST: try to create a view with the same name as the versioned table
-- note: the name is found even though the table is deleted
-- + Incompatible declarations found
-- + error: % CREATE TABLE versioned_table(
-- + error: % CREATE VIEW versioned_table AS
-- + The above must be identical.
-- + error: % duplicate table/view name 'versioned_table'
-- + {create_view_stmt}: err
-- +3 error:
create view versioned_table as select 1 x;

-- TEST: try to create a global variable with the same name as the versioned table
-- note: the name is found even though the table is deleted
-- + error: % global variable hides table/view name 'versioned_table'
-- + {declare_vars_type}: err
-- +1 error:
declare versioned_table integer;

-- TEST: try to create a table with the same name as the versioned table
-- note: the name is found even though the table is deleted
-- + Incompatible declarations found
-- + error: % CREATE TABLE versioned_table(
-- + error: % CREATE TABLE versioned_table(
-- + The above must be identical.
-- + error: % duplicate table/view name 'versioned_table'
-- + {create_table_stmt}: err
-- +3 error:
create table versioned_table(id2 integer);

-- TEST: drop the table (note that DDL works on any version)
-- + {drop_table_stmt}: ok
-- + {name versioned_table}: versioned_table: { id: integer } deleted
-- - error:
drop table if exists versioned_table;

-- TEST: drop table that doesn't exist
-- + error: % table in drop statement does not exist 'garbonzo'
-- +1 error:
drop table garbonzo;

-- TEST: try to drop table on a view
-- + error: % cannot drop a view with drop table 'MyView'
-- +1 error:
drop table MyView;

-- TEST: use a proc to get the result set
-- + {create_proc_stmt}: uses_proc_for_result: { id: integer notnull, name: text, rate: longint } dml_proc
-- + {call_stmt}: with_result_set: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
procedure uses_proc_for_result()
begin
  call with_result_set();
end;

-- TEST: table with a column deleted too soon
-- + error: % column delete version can't be <= the table create version 'id'
-- +1 error:
create table t_col_early_delete (
  id integer @delete(2)
) @create(3);

-- TEST: table with a column created too soon
-- + error: % column create version can't be <= the table create version 'id'
-- +1 error:
create table t_col_early_delete (
  id integer @create(2)
) @create(3);

-- TEST: table with a column deleted too late
-- + error: % column delete version can't be >= the table delete version 'id'
-- +1 error:
create table t_col_early_delete (
  id integer @delete(2)
) @delete(1);

-- TEST: table with a column created too late
-- + error: % column create version can't be >= the table delete version 'id'
-- +1 error:
create table t_col_early_delete (
  id integer @create(2)
) @delete(1);

-- TEST: table deleted not null column with default
-- + {col_def}: id: integer notnull has_default deleted @delete(2)
-- - error:
create table t_col_delete_notnull (
  id int! DEFAULT 8675309 @delete(2)
);

-- TEST: negative default value
-- + {create_table_stmt}: neg_default: { id: integer notnull has_default }
-- + {col_def}: id: integer notnull has_default
-- + {col_attrs_default}
-- + {uminus}
-- + {int 1}
-- - error:
create table neg_default (
  id int! default -1 @create(2)
);

-- TEST: alter a table, adding a nullable column
-- + ALTER TABLE neg_default ADD COLUMN id INT! DEFAULT -1;
-- + {alter_table_add_column_stmt}: ok
-- + {name neg_default}: neg_default: { id: integer notnull has_default }
-- + {col_def}: id: integer notnull has_default
-- - error:
alter table neg_default add column id int! default -1;

-- TEST: try to validate previous schema in a proc
-- + error: % switching to previous schema validation mode must be outside of any proc
-- + {create_proc_stmt}: err
-- + {previous_schema_stmt}: err
-- +1 error:
proc bogus_validate()
begin
  @previous_schema;
end;

-- TEST: make a select * with a duplicate result column name and try to fetch the fields
-- + error: % duplicate column name in result not allowed 'id'
-- + {fetch_stmt}: err
-- + {name C}: err
-- +1 error:
proc bogus_fetch()
begin
  cursor C for select * from foo T1 join foo T2 on T1.id = T2.id;
  fetch C;
end;

-- TEST: make a select * with a duplicate result column name and use that as a proc result set
-- + error: % duplicate column name in result not allowed 'id'
-- + {create_proc_stmt}: err
-- +1 error:
proc bogus_result_duplicate_names()
begin
  select * from foo T1 join foo T2 on T1.id = T2.id;
end;

-- TEST: make table with text as a column name
-- + {create_table_stmt}: table_with_text_as_name: { text: text, text2: text }
-- - error:
create table table_with_text_as_name(
  text text,
  text2 text
);

-- TEST: use text as a column
-- + {select_stmt}: _select_: { text: text, text2: text }
-- - error:
select text, text2 from table_with_text_as_name;

-- TEST: extract a column named text -- brutal renames
-- + {select_stmt}: _select_: { text: text, other_text: text }
-- + {name text2}: text2: text
-- + {name text}: text: text
-- + {select_from_etc}: TABLE { table_with_text_as_name: table_with_text_as_name }
-- - error:
select text2 as text, text as other_text from table_with_text_as_name;

-- TEST: try to start a schema upgrade after there are tables
-- + error: % schema upgrade declaration must come before any tables are declared
-- + {schema_upgrade_script_stmt}: err
-- +1 error:
@schema_upgrade_script;

-- TEST: try to start a schema upgrade inside a proc
-- + error: % schema upgrade declaration must be outside of any proc
-- + {schema_upgrade_script_stmt}: err
-- +1 error:
proc schema_upgrade_you_wish()
begin
  @schema_upgrade_script;
end;

-- TEST: try to use the non-column insert syntax on a table with deleted columns
-- we should get a fully formed insert on the non deleted column
-- + INSERT INTO hides_id_not_name(name)
-- +   VALUES ('x');
-- + {name hides_id_not_name}: hides_id_not_name: { name: text }
insert into hides_id_not_name values ('x');

-- TEST: create a table with more mixed column stuff for use testing alter statements later
-- + {create_table_stmt}: trickier_alter_target: { id: integer notnull partial_pk, added: text }
-- - error:
create table trickier_alter_target(
  id integer,
  something_deleted text @create(1) @delete(2),
  added text @create(2),
  primary key(id)
);

-- TEST: try to add id --> doesn't work
-- + error: % added column must already be reflected in declared schema, with @create, exact name match required 'id'
-- + {alter_table_add_column_stmt}: err
-- + {name trickier_alter_target}: trickier_alter_target: { id: integer notnull partial_pk, added: text }
-- +1 error:
alter table trickier_alter_target add column id integer;

-- TEST: try to add something_deleted --> doesn't work
-- + error: % added column must already be reflected in declared schema, with @create, exact name match required 'something_deleted'
-- + {alter_table_add_column_stmt}: err
-- + {name trickier_alter_target}: trickier_alter_target: { id: integer notnull partial_pk, added: text }
-- +1 error:
alter table trickier_alter_target add column something_deleted text;

-- TEST: try to add 'added' -> works!
-- + alter_table_add_column_stmt}: ok
-- + {name trickier_alter_target}: trickier_alter_target: { id: integer notnull partial_pk, added: text }
-- + {col_def}: added: text
-- - error:
alter table trickier_alter_target add column added text;

-- TEST: select as table with error
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {table_or_subquery}: err
-- +1 error:
select * from (select not 'x' X);

-- TEST: create a view with versions
-- + FROM bar @DELETE(2);
-- + {delete_attr}
-- - error:
create view view_with_version as select * from bar @delete(2);

-- TEST: use a long literal
-- + {longint 3147483647}: longint notnull
-- - error:
set ll := 3147483647L;

-- TEST: try to drop a view that doesn't exist
-- + error: % view in drop statement does not exist 'view_not_present'
-- + {drop_view_stmt}: err
-- +1 error:
drop view view_not_present;

-- TEST: try to drop a view that is a table
-- + error: % cannot drop a table with drop view 'foo'
-- + {drop_view_stmt}: err
-- +1 error:
drop view foo;

-- TEST: drop a view that is really a view
-- + {drop_view_stmt}: ok
-- + {name MyView}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- - error:
drop view if exists MyView;

-- TEST: drop an index that exists
-- + DROP INDEX index_1;
-- + {drop_index_stmt}: ok
-- - error:
drop index index_1;

-- TEST: drop an index that exists
-- + error: % index in drop statement was not declared 'I_dont_see_no_steekin_index'
-- + {drop_index_stmt}: err
-- +1 error:
drop index if exists I_dont_see_no_steekin_index;

-- TEST: specify a column attribute twice (put something in between)
-- + error: % a column attribute was specified twice on the same column
-- + {create_table_stmt}: err
-- +1 error:
create table two_not_null(
  id int! unique not null
);

-- TEST: specify incompatible constraints
-- + error: % column can't be primary key and also unique key 'id'
-- + {create_table_stmt}: err
-- +1 error:
create table mixed_pk_uk(
  id integer primary key unique
);

-- TEST: verify unique column flag recorded
-- + {create_table_stmt}: table_with_uk: { id: integer unique_key }
-- - error:
create table table_with_uk(
  id integer unique
);

-- TEST: validate PK not duplicated (mixed metho)
-- + error: % more than one primary key in table 'baz'
-- + {create_table_stmt}: err
-- +1 error:
create table baz(
  id integer primary key AUTOINCREMENT not null,
  PRIMARY KEY (id)
);

-- TEST: seed value is a string -- error
-- + error: % seed expression must be a non-nullable integer
-- + {insert_stmt}: err
-- +1 error:
insert into bar (id, name, rate) values (1, 'bazzle', 3) @dummy_seed('x');

-- TEST: seed value is a string -- expression error
-- + error: % string operand not allowed in 'NOT'
-- + {insert_stmt}: err
-- +1 error:
insert into bar (id, name, rate) values (1, 'bazzle', 3) @dummy_seed(not 'x');

-- TEST: ok to go insert with dummy values
-- note that the insert statement has been mutated!!
-- + INSERT INTO bar(id, name, rate) VALUES (_seed_, printf('name_%d', _seed_), _seed_) @DUMMY_SEED(1 + 2) @DUMMY_DEFAULTS @DUMMY_NULLABLES;
-- + {seed_stub}
-- + {call}: text notnull
-- + {name printf}: text notnull
-- + {strlit 'name_%d'}: text notnull
-- - error:
insert into bar () values () @dummy_seed(1+2) @dummy_nullables @dummy_defaults;

-- TEST: use default value of a table
-- + {name booly}: booly: { id: integer has_default, flag: bool }
-- - error:
insert into booly(flag) values (1);

-- TEST: try to declare a blob variable
-- + {declare_vars_type}: blob
-- + {name_list}: blob_var: blob variable
-- - error:
declare blob_var blob;

-- TEST: error on ordered comparisons (left)
-- + error: % left operand cannot be a blob in '<'
-- +1 error:
set X := blob_var < 1;

-- TEST: error on ordered comparisons (right)
-- + error: % right operand cannot be a blob in '<'
-- +1 error:
set X := 1 < blob_var;

-- TEST: ok to compare blobs to each other with equality
-- + {eq}: bool
-- - error:
set X := blob_var == blob_var;

-- TEST: ok to compare blobs to each other with inequality
-- + {ne}: bool
-- - error:
set X := blob_var <> blob_var;

-- TEST: error on math with blob (left)
-- + error: % left operand cannot be a blob in '+'
-- +1 error:
set X := blob_var + 1;

-- TEST: error on ordered comparisons (right)
-- + error: % right operand cannot be a blob in '+'
-- +1 error:
set X := 1 + blob_var;

-- TEST: error on unary not
-- + error: % blob operand not allowed in 'NOT'
-- + {not}: err
-- +1 error:
set X := not blob_var;

-- TEST: error on unary negation
-- + error: % blob operand not allowed in '-'
-- + {uminus}: err
-- +1 error:
set X := - blob_var;

-- TEST: assign blob to string
-- + error: % required 'TEXT' not compatible with found 'BLOB' context 'a_string'
-- + {name a_string}: err
-- +1 error:
set a_string := blob_var;

-- TEST: assign string to a blob
-- + error: % required 'BLOB' not compatible with found 'TEXT' context 'blob_var'
-- + {name blob_var}: err
-- +1 error:
set blob_var := a_string;

-- TEST: report error to use concat outside SQL statement
-- + error: % CONCAT may only appear in the context of a SQL statement
-- +1 error:
set a_string := blob_var || 2.0;

-- TEST: report error to concat blob and number
-- + error: % blob operand must be converted to string first in '||'
-- +1 error:
select blob_var || 2.0;

-- TEST: report error to concat number and blob
-- + error: % blob operand must be converted to string first in '||'
-- +1 error:
select 1 || blob_var;

-- TEST: create proc with blob arg
-- + PROC blob_proc (OUT a_blob BLOB)
-- + {create_proc_stmt}: ok
-- + {param}: a_blob: blob variable out
-- - error:
proc blob_proc(out a_blob blob)
begin
  set a_blob := null;
end;

-- TEST: try to create a table with a blob column
-- + {create_table_stmt}: blob_table_test: { b: blob }
-- - error:
create table blob_table_test(
  b blob
);

-- TEST: try to use a blob variable in a select statement
-- + {select_stmt}: _select_: { blob_var: blob variable was_set }
-- - error:
select blob_var;

-- TEST: try to use a blob variable in an IN statement, that's ok
-- + {in_pred}: bool
-- + {expr_list}: blob_var: blob variable
-- - error:
set X := blob_var in (blob_var, null);

-- TEST: bogus in statement with blob variable, combining with numeric
-- + error: % required 'BLOB' not compatible with found 'INT' context 'IN'
-- + {in_pred}: err
-- +1 error:
set X := blob_var in (blob_var, 1);

-- TEST: bogus in statement with blob variable, combining with text
-- + error: % required 'BLOB' not compatible with found 'TEXT' context 'IN'
-- + {in_pred}: err
-- +1 error:
set X := blob_var in ('foo', blob_var);

-- TEST: bogus in statement with blob variable, searching for text with blob in list
-- + error: % required 'TEXT' not compatible with found 'BLOB' context 'IN'
-- + {in_pred}: err
-- + {expr_list}: text notnull
-- +1 error:
set X := 'foo' in ('foo', blob_var);

-- TEST: case statement using blobs as test condition
-- + {assign}: X: integer variable
-- + {case_expr}: integer notnull
-- + {name blob_var}: blob_var: blob variable
-- - error:
set X := case blob_var when blob_var then 2 else 3 end;

-- TEST: case statement using blobs as result
-- + {assign}: blob_var: blob variable
-- + {name blob_var}: blob_var: blob variable
-- + {case_expr}: blob
-- + {case_list}: blob variable
-- + {when}: blob_var: blob variable
-- + {null}: null
-- - error:
set blob_var := case 1 when 1 then blob_var else null end;

-- TEST: between with blobs is just not happening, first case
-- + error: % first operand cannot be a blob in 'BETWEEN'
-- +1 error:
set X := blob_var between 1 and 3;

-- TEST: between with blobs is just not happening, second case;
-- + error: % required 'INT' not compatible with found 'BLOB' context 'BETWEEN'
-- +1 error:
set X := 2 between blob_var and 3;

-- TEST: between with blobs is just not happening, third case;
-- + error: % required 'INT' not compatible with found 'BLOB' context 'BETWEEN'
-- +1 error:
set X := 2 between 1 and blob_var;

-- TEST: not between with blobs similarly not supported, first case
-- + error: % first operand cannot be a blob in 'NOT BETWEEN'
-- +1 error:
set X := blob_var not between 1 and 3;

-- TEST: not between with blobs similarly not supported, second case;
-- + error: % required 'INT' not compatible with found 'BLOB' context 'NOT BETWEEN'
-- +1 error:
set X := 2 not between blob_var and 3;

-- TEST: not between with blobs similarly not supported, third case;
-- + error: % required 'INT' not compatible with found 'BLOB' context 'NOT BETWEEN'
-- +1 error:
set X := 2 not between 1 and blob_var;

-- TEST: try to fetch into object variables
-- + error: % required 'OBJECT' not compatible with found 'INT' context 'o1'
-- + {fetch_stmt}: err
-- +1 error:
proc bogus_object_read()
begin
  declare o1, o2, o3 object;
  cursor C for select * from bar;
  fetch C into o1, o2, o3;
end;

-- TEST: try to use in (select...) in a bogus context
-- + error: % [not] in (select ...) is only allowed inside of select lists, where, on, and having clauses
-- +1 error:
proc fool(x integer)
begin
  set x := x in (select 1);
end;

-- TEST: try to use not in (select...) in a bogus context
-- + error: % [not] in (select ...) is only allowed inside of select lists, where, on, and having clauses
-- +1 error:
proc notfool(x integer)
begin
  set x := x not in (select 1);
end;

-- TEST: try to make a dummy blob -- not supported
-- + INSERT INTO blob_table_test(b) VALUES (CAST(printf('b_%d', _seed_) AS BLOB)) @DUMMY_SEED(1) @DUMMY_NULLABLES;
-- + {insert_stmt}: ok
-- + {cast_expr}: blob notnull
-- + {call}: text notnull
-- + {name printf}: text notnull
-- + {strlit 'b_%d'}: text notnull
-- + {name _seed_}: _seed_: integer notnull variable
-- - error:
insert into blob_table_test() values () @dummy_seed(1) @dummy_nullables;

-- TEST: simple out statement case
proc out_cursor_proc()
begin
  cursor C for select 1 A, 2 B;
  fetch C;
  out C;
end;

-- needed for the next test
cursor QQ like out_cursor_proc;

-- TEST: force an error on the out cursor path, bad args
-- + error: % too many arguments provided to procedure 'out_cursor_proc'
-- + {fetch_call_stmt}: err
-- +1 error:
fetch QQ from call out_cursor_proc(1);

-- we need this for the next test, it has the right shape but it's not an out proc
proc not_out_cursor_proc()
begin
  select 1 A, 2 B;
end;

-- TEST: force an error on the out cursor path, the proc isn't actually an out cursor proc
-- + error: % cursor requires a procedure that returns a cursor with OUT 'QQ'
-- + {fetch_call_stmt}: err
-- +1 error:
fetch QQ from call not_out_cursor_proc();

-- TEST: use non-fetched cursor for out statement
-- + error: % cursor was not fetched with the auto-fetch syntax 'fetch [cursor]' 'C'
-- + {create_proc_stmt}: err
-- + {out_stmt}: err
-- +1 error:
proc out_cursor_proc_not_shape_storage()
begin
  declare a, b int!;
  cursor C for select 1 A, 2 B;
  fetch C into a, b;
  out C;
end;

-- TEST: use non-fetched cursor for out statement
-- + error: % in multiple select/out statements, all column names must be identical so they have unambiguous names; error in column 2: 'B' vs. 'C'
-- + {create_proc_stmt}: err
-- + {out_stmt}: err
-- diagnostics also present
-- +4 error:
proc out_cursor_proc_incompat_results()
begin
  declare a, b int!;
  cursor C for select 1 A, 2 B;
  cursor D for select 1 A, 2 C;
  fetch C;
  fetch D;
  out C;
  out D;
end;

-- TEST: use mixed select and out
-- + error: % can't mix and match out, out union, or select/call for return values 'out_cursor_proc_mixed_cursor_select'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- +1 error:
proc out_cursor_proc_mixed_cursor_select()
begin
  declare a, b int!;
  cursor C for select 1 A, 2 B;
  fetch C;
  out C;
  select 1 A, 2 B;
end;

-- TEST: use mixed select and out (other order)
-- + error: % can't mix and match out, out union, or select/call for return values 'out_cursor_proc_mixed_cursor_select_select_first'
-- + {create_proc_stmt}: err
-- + {out_stmt}: err
-- +1 error:
proc out_cursor_proc_mixed_cursor_select_select_first()
begin
  declare a, b int!;
  cursor C for select 1 A, 2 B;
  fetch C;
  select 1 A, 2 B;
  out C;
end;

-- TEST: use mixed select and out union
-- + error: % can't mix and match out, out union, or select/call for return values 'out_cursor_proc_mixed_cursor_select_then_union'
-- + {create_proc_stmt}: err
-- + {out_union_stmt}: err
-- +1 error:
proc out_cursor_proc_mixed_cursor_select_then_union()
begin
  declare a, b int!;
  cursor C for select 1 A, 2 B;
  fetch C;
  select 1 A, 2 B;
  out union C;
end;

-- TEST: simple out union proc with dml
-- + {create_proc_stmt}: C: out_union_dml: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out_union
-- - error:
proc out_union_dml()
begin
  cursor C for select 1 A, 2 B;
  fetch C;
  out union C;
end;

-- TEST: simple out union proc no DML
-- + {create_proc_stmt}: C: out_union: { A: integer notnull, B: integer notnull } variable shape_storage uses_out_union
-- - error:
proc out_union()
begin
  cursor C like select 1 A, 2 B;
  fetch C using 1 A, 2 B;
  out union C;
end;

-- TEST: pass through out union is and out union proc and marked "calls" (dml version)
-- + {create_proc_stmt}: C: call_out_union_dml: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out_union calls_out_union
-- - error:
proc call_out_union_dml()
begin
  call out_union_dml();
end;

-- TEST: pass through out union is and out union proc and marked "calls" (not dml version)
-- + {create_proc_stmt}: C: call_out_union: { A: integer notnull, B: integer notnull } variable shape_storage uses_out_union calls_out_union
-- - error:
proc call_out_union()
begin
  call out_union();
end;

-- TEST: calling out union for pass through not compatible with regular out union
-- + error: % can't mix and match out, out union, or select/call for return values 'out_union_call_and_out_union'
-- + {create_proc_stmt}: err
-- + {out_union_stmt}: C: _select_: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage
-- +1 error:
proc out_union_call_and_out_union()
begin
  cursor C for select 1 A, 2 B;
  fetch C;
  out union C;
  call out_union_dml();
end;

-- TEST: calling out union for pass through not compatible with regular out union
-- + error: % can't mix and match out, out union, or select/call for return values 'out_union_call_and_out_union_other_order'
-- + {create_proc_stmt}: err
-- + {out_union_stmt}: err
-- +1 error:
proc out_union_call_and_out_union_other_order()
begin
  cursor C for select 1 A, 2 B;
  fetch C;
  call out_union_dml();
  out union C;
end;

-- TEST: use out statement with non cursor
-- + error: % not a cursor 'C'
-- + {create_proc_stmt}: err
-- + {out_stmt}: err
-- +1 error:
proc out_not_cursor()
begin
  declare C integer;
  out C;
end;

-- TEST: out cursor outside of a proc
-- + error: % out cursor statement only makes sense inside of a procedure
-- + {out_stmt}: err
-- +1 error:
out curs;

-- TEST: read the result of a proc with an out cursor
-- + {create_proc_stmt}: ok dml_proc
-- + {declare_value_cursor}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage value_cursor
-- + {call_stmt}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out
-- - error:
proc result_reader()
begin
  cursor C fetch from call out_cursor_proc();
end;

-- TEST: read the result of a proc with an out cursor
-- + error: % value cursors are not used with FETCH C, or FETCH C INTO 'C'
-- + {fetch_stmt}: err
-- +1 error:
proc fails_result_reader()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C;
end;

-- TEST: declare a fetch proc with a result set
-- + {declare_proc_stmt}: declared_proc: { t: text } uses_out
-- - error:
declare proc declared_proc(id integer) out (t text);

-- TEST: fetch call a procedure with bogus args
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'declared_proc' argument #1 intended for parameter 'id' has the problem
-- + {create_proc_stmt}: err
-- +2 error:
proc invalid_proc_fetch_bogus_call()
begin
  cursor C fetch from call declared_proc(not 'x');
end;

-- a bogus proc for use in a later test
proc xyzzy()
begin
end;

-- TEST: call a procedure that is just all wrong
-- + error: % cursor requires a procedure that returns a cursor with OUT 'C'
-- + {create_proc_stmt}: err
-- +1 error:
proc invalid_proc_fetch()
begin
  cursor C fetch from call xyzzy();
end;

-- TEST: read the result of a proc with an out cursor, use same var twice
-- + error: % duplicate variable name in the same scope 'C'
-- +1 {declare_value_cursor}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage value_cursor
-- +1 {declare_value_cursor}: err
-- +1 error:
proc fails_result_reader_double_decl()
begin
  cursor C fetch from call out_cursor_proc();
  cursor C fetch from call out_cursor_proc();
end;

-- used in the following tests
proc proc_with_single_output(a int, b int, out c int)
begin
end;

-- TEST: use proc_with_single_output like it was a function
-- + SET an_int := proc_with_single_output(1, an_int);
-- + {assign}: an_int: integer variable
-- + {call}: integer
-- + {name proc_with_single_output}
-- + {arg_list}: ok
-- - error:
set an_int := proc_with_single_output(1, an_int);

-- TEST: helper proc to test distinct in proc used as a function
procedure proc_func(in arg1 integer, out arg2 integer)
begin
  drop table foo;
end;

-- TEST: Use distinct in a procedure used as a function
-- + error: % procedure as function call is not compatible with DISTINCT or filter clauses 'proc_func'
-- + {assign}: err
-- + {call}: err
-- + {distinct}
-- + {arg_list}: ok
-- +1 error:
SET an_int := proc_func(distinct 1);

-- TEST: use proc_with_single_output like it was a function, too many args
-- + error: % too many arguments provided to procedure 'proc_with_single_output'
-- + {call}: err
-- +1 error:
set an_int := proc_with_single_output(1, an_int, an_int2);

-- TEST: capture a result set from a proc that returns a structured result
-- + {let_stmt}: out_result_set: object<out_cursor_proc SET> notnull variable
-- + {name out_result_set}: out_result_set: object<out_cursor_proc SET> notnull variable
-- + {call}: object<out_cursor_proc SET>
-- - error:
let out_result_set := out_cursor_proc();

-- TEST: this proc has no out arg that can be used as a result
-- + error: % procedure without trailing OUT parameter used as function 'proc2'
-- + {call}: err
-- +1 error:
set an_int := proc2(1);

-- TEST: user proc calls can't happen inside of SQL
-- + error: % a function call to a procedure inside SQL may call only a shared fragment i.e. [[shared_fragment]] 'proc_with_single_output'
-- + {call}: err
-- +1 error:
set an_int := (select proc_with_single_output(1, an_int, an_int));

-- a helper proc that is for sure using dml
proc dml_func(out a int!)
begin
 set a := (select 1);
end;

-- TEST: create a proc that calls a dml proc as a function, must become a dml proc itself
-- - error:
-- + {create_proc_stmt}: ok dml_proc
-- + {assign}: a: integer notnull variable out
proc should_be_dml(out a int!)
begin
  set a := dml_func();
end;

-- TEST: fetch cursor from values
-- + {name C}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage value_cursor
-- + {fetch_values_stmt}: ok
proc fetch_values()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C from values (1,2);
end;

-- TEST: fetch cursor from values with dummy values
-- + FETCH C(A, B) FROM VALUES (_seed_, _seed_) @DUMMY_SEED(123) @DUMMY_NULLABLES;
-- + {name C}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage value_cursor
-- + {fetch_values_stmt}: ok
-- +2 {name _seed_}: _seed_: integer notnull variable
proc fetch_values_dummy()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C() from values () @dummy_seed(123) @dummy_nullables;
end;

-- TEST: fetch cursor from call
-- + FETCH C FROM CALL out_cursor_proc();
-- + {fetch_call_stmt}: ok
-- + {name C}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- + {call_stmt}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out
-- + {name out_cursor_proc}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out
-- - error:
proc fetch_from_call()
begin
  cursor C like out_cursor_proc;
  fetch C from call out_cursor_proc();
  out C;
end;

-- TEST: fetch cursor from call to proc with invalid arguments
-- + error: % too many arguments provided to procedure 'out_cursor_proc'
-- + {create_proc_stmt}: err
-- + {name fetch_from_call_to_proc_with_invalid_arguments}: err
-- + {stmt_list}: err
-- + {fetch_call_stmt}: err
-- + {call_stmt}: err
-- +1 error:
proc fetch_from_call_to_proc_with_invalid_arguments()
begin
  cursor C like out_cursor_proc;
  fetch C from call out_cursor_proc(42);
  out C;
end;

-- TEST: fetch cursor from call with invalid cursor
-- + {create_proc_stmt}: err
-- + {stmt_list}: err
-- + {fetch_call_stmt}: err
-- +2 {name C}: err
-- +2 error: % not a cursor 'C'
proc fetch_from_call_to_proc_with_invalid_cursor()
begin
  declare C text;
  fetch C from call out_cursor_proc();
  out C;
end;

-- TEST: fetch cursor from call to proc with different column names
-- + error: % receiving cursor from call, all column names must be identical so they have unambiguous names; error in column 2: 'C' vs. 'B'
-- + {create_proc_stmt}: err
-- + {name fetch_from_call_to_proc_with_different_column_names}: err
-- + {stmt_list}: err
-- + {fetch_call_stmt}: err
-- + {call_stmt}: err
-- expected type is not marked as an error
-- - {name C}: err
-- diagnostics also present
-- +4 error:
proc fetch_from_call_to_proc_with_different_column_names()
begin
  cursor C like select 1 A, 2 C;
  fetch C from call out_cursor_proc();
  out C;
end;

-- TEST: fetch non cursor
-- + error: % name not found 'not_a_cursor'
-- + {fetch_values_stmt}: err
-- +1 error:
fetch not_a_cursor from values (1,2,3);

-- TEST: try to use fetch values on a statement cursor
-- + error: % fetch values is only for value cursors, not for sqlite cursors 'my_cursor'
-- + {fetch_values_stmt}: err
-- +1 error:
fetch my_cursor from values (1,2,3);

-- TEST: attempt bogus seed
-- + error: % string operand not allowed in 'NOT'
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_values_bogus_seed_value()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C() from values () @dummy_seed(not 'x');
end;

-- TEST: missing columns in fetch values
-- + error: % count of columns differs from count of values
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_values_missing_value()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C from values ();
end;

-- TEST: helper proc that returns a blob
-- + {create_proc_stmt}: C: blob_out: { B: blob } variable dml_proc shape_storage uses_out
proc blob_out()
begin
  -- cheesy nullable blob
  cursor C for select case when 1 then cast('x' as blob) else null end B;
  fetch C;
  out C;
end;

-- TEST: fetch cursor from values with dummy values but one is a blob, supported with helper
-- + {fetch_values_stmt}: ok
-- + {call}: blob notnull create_func
-- + {name cql_blob_from_int}
-- - error:
proc fetch_values_blob_dummy()
begin
  cursor C fetch from call blob_out();
  fetch C() from values () @dummy_seed(123) @dummy_nullables;
end;

-- TEST: fetch cursor from values but not all columns mentioned
-- + error: % required column missing in FETCH statement 'B'
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_values_missing_columns()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C(A) from values (1);
end;

-- TEST: fetch cursor from values bogus value expression
-- + error: % string operand not allowed in 'NOT'
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_values_bogus_value()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C(A,B) from values (1, not 'x');
end;

-- TEST: fetch cursor from values bogus value type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'B'
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_values_bogus_type()
begin
  cursor C fetch from call out_cursor_proc();
  fetch C(A,B) from values (1, 'x');
end;

-- TEST: fetch cursor from values provide null for blob (works)
-- + FETCH C(B) FROM VALUES (NULL) @DUMMY_SEED(123);
-- + fetch_values_stmt}: ok
-- - error:
proc fetch_values_blob_dummy_with_null()
begin
  cursor C fetch from call blob_out();
  fetch C() from values () @dummy_seed(123);
end;

-- TEST: fetch to a cursor from another cursor
-- + FETCH C0(A, B) FROM VALUES (1, 2);
-- + FETCH C1(A, B) FROM VALUES (C0.A, C0.B);
-- + {create_proc_stmt}: C1: fetch_to_cursor_from_cursor: { A: integer notnull, B: integer notnull } variable shape_storage uses_out
-- + {fetch_values_stmt}: ok
-- - error:
proc fetch_to_cursor_from_cursor()
begin
  cursor C0 like select 1 A, 2 B;
  cursor C1 like C0;
  fetch C0 from values (1, 2);
  fetch C1 from C0;
  out C1;
end;

-- TEST: fetch to a cursor from an invalid cursor
-- + error: % not a cursor 'C0'
-- + {create_proc_stmt}: err
-- + {name fetch_to_cursor_from_invalid_cursor}: err
-- + {stmt_list}: err
-- + {fetch_values_stmt}: err
-- + {name C0}: err
-- +1 error:
proc fetch_to_cursor_from_invalid_cursor()
begin
  declare C0 int;
  cursor C1 like select 1 A, 2 B;
  fetch C1 from C0;
  out C1;
end;

-- TEST: fetch to an invalid cursor from a cursor
-- + error: % not a cursor 'C1'
-- + {create_proc_stmt}: err
-- + {name fetch_to_invalid_cursor_from_cursor}: err
-- + {stmt_list}: err
-- + {fetch_values_stmt}: err
-- + {name C1}: err
-- +1 error:
proc fetch_to_invalid_cursor_from_cursor()
begin
  cursor C0 like select 1 A, 2 B;
  declare C1 int;
  fetch C0 from values (1, 2);
  fetch C1 from C0;
end;

-- TEST: fetch to a statement cursor from another cursor
-- + error: % fetch values is only for value cursors, not for sqlite cursors 'C1'
-- + {create_proc_stmt}: err
-- + {name fetch_to_statement_cursor_from_cursor}: err
-- + {stmt_list}: err
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_to_statement_cursor_from_cursor()
begin
  cursor C0 like select 1 A, 2 B;
  cursor C1 for select 1 A, 2 B;
  fetch C0 from values (1, 2);
  fetch C1 from C0;
end;

-- TEST: fetch to a cursor from a cursor with different columns
-- + error: % [shape] has too few fields 'C0'
-- + {create_proc_stmt}: err
-- + {name fetch_to_cursor_from_cursor_with_different_columns}: err
-- + {stmt_list}: err
-- + {fetch_values_stmt}: err
-- +1 error:
proc fetch_to_cursor_from_cursor_with_different_columns()
begin
  cursor C0 like select 1 A, 2 B;
  cursor C1 like select 1 A, 2 B, 3 C;
  fetch C0 from values (1, 2);
  fetch C1 from C0;
end;

-- TEST: fetch to a cursor from a cursor without fields
-- + error: % cannot read from a cursor without fields 'C0'
-- + {create_proc_stmt}: err
-- + {name fetch_to_cursor_from_cursor_without_fields}: err
-- + {stmt_list}: err
-- + {fetch_values_stmt}: err
-- + {name C0}: err
-- +1 error:
proc fetch_to_cursor_from_cursor_without_fields()
begin
  declare X int;
  declare Y real;
  cursor C0 for select 1 A, 2.5;
  cursor C1 like C0;
  fetch C0 into X, Y;
  fetch C1 from C0;
end;

-- TEST: cursor a like an existing cursor
-- + {create_proc_stmt}: ok dml_proc
-- + {name declare_cursor_like_cursor}: ok dml_proc
-- + {declare_cursor_like_name}: C1: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- + {name C1}: C1: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- - error:
proc declare_cursor_like_cursor()
begin
  cursor C0 fetch from call out_cursor_proc();
  cursor C1 like C0;
end;

-- TEST: cursor a like a variable that's not a cursor
-- + error: % not a cursor 'C0'
-- + {create_proc_stmt}: err
-- + {name declare_cursor_like_non_cursor_variable}: err
-- + {stmt_list}: err
-- + {declare_cursor_like_name}: err
-- + {name C0}: err
-- +1 error:
proc declare_cursor_like_non_cursor_variable()
begin
    declare C0 integer;
    cursor C1 like C0;
end;

-- TEST: cursor a with the same name as an existing variable
-- + error: % duplicate variable name in the same scope 'C0'
-- + {create_proc_stmt}: err
-- + {name declare_cursor_like_cursor_with_same_name}: err
-- + {stmt_list}: err
-- + {declare_cursor_like_name}: err
-- + {name C0}: err
-- +1 error:
proc declare_cursor_like_cursor_with_same_name()
begin
  cursor C0 fetch from call out_cursor_proc();
  cursor C0 like C0;
end;

-- TEST: cursor a like something that's not defined
-- + error: % must be a cursor, proc, table, or view 'C0'
-- + {create_proc_stmt}: err
-- + {name declare_cursor_like_undefined_variable}: err
-- + {stmt_list}: err
-- + {declare_cursor_like_name}: err
-- + {name C0}: err
-- +1 error:
proc declare_cursor_like_undefined_variable()
begin
    cursor C1 like C0;
end;

-- TEST: cursor a like a proc
-- + {create_proc_stmt}: ok
-- + {name declare_cursor_like_proc}: ok
-- + {declare_cursor_like_name}: C: decl3: { A: integer notnull, B: bool } variable shape_storage value_cursor
-- + {name C}: C: decl3: { A: integer notnull, B: bool } variable shape_storage value_cursor
-- - ok dml_proc
-- - error:
proc declare_cursor_like_proc()
begin
  cursor C like decl3;
end;

-- TEST: cursor a like a proc with no result
-- + error: % proc has no result 'decl1'
-- + {create_proc_stmt}: err
-- + {name declare_cursor_like_proc_with_no_result}: err
-- + {stmt_list}: err
-- + {declare_cursor_like_name}: err
-- + {name decl1}: err
-- +1 error:
proc declare_cursor_like_proc_with_no_result()
begin
  cursor C like decl1;
end;

-- TEST: cursor a like a table
-- + {create_proc_stmt}: ok
-- + {name declare_cursor_like_table}: ok
-- + {declare_cursor_like_name}: C: bar: { id: integer notnull, name: text, rate: longint } variable shape_storage value_cursor
-- + {name C}: C: bar: { id: integer notnull, name: text, rate: longint } variable shape_storage value_cursor
-- - dml_proc
-- - error:
proc declare_cursor_like_table()
begin
  cursor C like bar;
end;

-- TEST: cursor a like a view
-- + {create_proc_stmt}: ok
-- + {name declare_cursor_like_view}: ok
-- + {declare_cursor_like_name}: C: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull } variable shape_storage value_cursor
-- + {name C}: C: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull } variable shape_storage value_cursor
-- - dml_proc
-- - error:
proc declare_cursor_like_view()
begin
  cursor C like MyView;
end;

-- TEST: use like syntax to cursor a of the type of a select statement
-- + PROC declare_cursor_like_select ()
-- + CURSOR C LIKE SELECT 1 AS A, 2.5 AS B, 'x' AS C;
-- + FETCH C(A, B, C) FROM VALUES (_seed_, _seed_, printf('C_%d', _seed_)) @DUMMY_SEED(123);
-- + {declare_cursor_like_select}: C: _select_: { A: integer notnull, B: real notnull, C: text notnull } variable shape_storage value_cursor
-- + {fetch_values_stmt}: ok
-- - dml_proc
-- - error:
proc declare_cursor_like_select()
begin
  cursor C like select 1 A, 2.5 B, 'x' C;
  fetch C() from values () @dummy_seed(123);
  out C;
end;

-- TEST: a bogus cursor due to bogus expression in select
-- + error: % string operand not allowed in 'NOT'
-- + {declare_cursor_like_select}: err
-- +1 error:
cursor some_cursor like select 1 A, 2.5 B, not 'x' C;

-- TEST: duplicate cursor name
-- + error: % duplicate variable name in the same scope 'X'
-- + {declare_cursor_like_select}: err
-- +1 error:
cursor X like select 1 A, 2.5 B, 'x' C;

-- TEST: pull the rowid out of a table
-- + {select_stmt}: _select_: { rowid: longint notnull }
-- - error:
select rowid from foo;

-- TEST: pull a rowid from a particular table
-- + SELECT T1.rowid
-- + {select_stmt}: _select_: { rowid: longint notnull }
-- - error:
select T1.rowid from foo T1, bar T2;

-- TEST: name not unique, not found
-- + error: % name not found 'T1.rowid'
-- + {select_stmt}: err
-- +1 error:
select T1.rowid from foo T2, foo T3;

-- TEST: rowid name ambiguous
-- + error: % identifier is ambiguous 'rowid'
-- + {select_stmt}: err
-- +1 error:
select rowid from foo T1, foo T2;

-- TEST: read the result of a non-dml proc;  we must not become a dml proc for doing so
-- - dml_proc
-- + {create_proc_stmt}: ok
-- + {declare_value_cursor}: C: declare_cursor_like_select: { A: integer notnull, B: real notnull, C: text notnull } variable shape_storage value_cursor
-- + {call_stmt}: C: declare_cursor_like_select: { A: integer notnull, B: real notnull, C: text notnull } variable shape_storage uses_out value_cursor
-- - error:
proc value_result_reader()
begin
  cursor C fetch from call declare_cursor_like_select();
end;

-- TEST: create table with misc attributes
-- + @ATTRIBUTE(foo)
-- + @ATTRIBUTE(goo)
-- + @ATTRIBUTE(num=-9)
-- + CREATE TABLE misc_attr_table(
-- + @ATTRIBUTE(bar=baz)
-- + {stmt_and_attr}
-- +4 {misc_attrs}
-- +4 {misc_attr}
-- +1 {name foo}
-- +1 {name goo}
-- +1 {name bar}
-- +1 {name baz}
-- +1 {name num}
-- +1 {uminus}
-- +1 {int 9}
-- + {create_table_stmt}: misc_attr_table: { id: integer notnull }
@attribute(foo)
@attribute(goo)
@attribute(num=-9)
create table misc_attr_table
(
  @attribute(bar = baz)
  id int!
);

-- TEST: complex index (with expression)
-- + CREATE UNIQUE INDEX IF NOT EXISTS my_unique_index ON bar (id / 2 ASC, name DESC, rate);
-- + {create_index_stmt}: ok
-- - error:
create unique index if not exists my_unique_index on bar(id/2 asc, name desc, rate);

-- TEST: there is no index that covers id so this is an error, the index covers id/2
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'bar'
-- + {create_table_stmt}: err
-- +1 error:
create table ref_bar(
 id int! references bar(id) -- index is on id/2
);

-- TEST: try to update a table that does not exist
-- + error: % table in update statement does not exist 'This_Table_Does_Not_Exist'
-- + {update_stmt}: err
-- +1 error:
update This_Table_Does_Not_Exist set x = 1;

-- TEST: create a table with a valid FK on a column
-- + {create_table_stmt}: fk_on_col: { fk_src: integer foreign_key }
-- + {col_attrs_fk}: ok
-- + {name foo}
-- + {name id}: id: integer notnull
-- - error:
create table fk_on_col(
  fk_src integer references foo ( id ) on update cascade on delete set null
);

-- TEST: create a table with a bogus FK : too many cols
-- + error: % FK reference must be exactly one column with the correct type 'fk_src'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_fk_on_col_1(
  fk_src integer references bar ( id, name ) on update cascade on delete set null
);

-- TEST: create a table with a bogus FK : wrong type
-- + error: % FK reference must be exactly one column with the correct type 'fk_src'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_fk_on_col_1(
  fk_src integer references bar ( name )
);

-- TEST: create a table with a bogus FK : no such table
-- + error: % foreign key refers to non-existent table 'no_such_table'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_fk_on_col_1(
  fk_src integer references no_such_table ( name )
);

-- TEST: create a table with a bogus FK : no such column
-- + error: % name not found 'no_such_column'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_fk_on_col_1(
  fk_src integer references bar ( no_such_column )
);

-- TEST: create a table with a non-integer autoinc
-- + error: % autoincrement column must be [LONG|INT] PRIMARY KEY 'id'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_autoinc_type(id bool primary key autoincrement);

-- TEST: create a table an autoinc and without rowid
-- + error: % table has an AUTOINCREMENT column; it cannot also be WITHOUT ROWID 'bogus_without_rowid'
-- + {create_table_stmt}: err
-- +1 error:
create table bogus_without_rowid(id integer primary key autoincrement) without rowid;

-- TEST: create a table that is going to be on the recreate plan
-- + CREATE TABLE recreatable(
-- + @RECREATE;
-- + {create_table_stmt}: recreatable: { id: integer notnull primary_key, name: text } @recreate
-- + {recreate_attr}
-- - error:
create table recreatable(
  id integer primary key,
  name text
) @recreate;

-- TEST: create a table that is going to be on the recreate plan, try to version a column in it
-- + CREATE TABLE column_marked_delete_on_recreate_table(
-- + @RECREATE;
-- + error: % columns in a table marked @recreate cannot have @create or @delete 'id'
-- + {create_table_stmt}: err
-- + {recreate_attr}
-- +1 error:
create table column_marked_delete_on_recreate_table(
  id integer primary key @create(2),
  name text
) @recreate;

-- TEST: create a proc that uses the same CTE name twice, these should not conflict
-- + {create_proc_stmt}: cte_test: { a: integer notnull, b: integer notnull } dml_proc
-- +2 {cte_tables}: ok
-- +2 {cte_table}: should_not_conflict: { a: integer notnull, b: integer notnull }
-- - error:
proc cte_test()
begin
  with should_not_conflict(a,b) as (select 111,222)
  select * from should_not_conflict;
  with should_not_conflict(a,b) as (select 111,222)
  select * from should_not_conflict;
end;

-- TEST: use a CTE on a insert statement, all ok
-- - error:
-- + {with_insert_stmt}: ok
-- + {cte_table}: x: { a: integer notnull, b: text notnull, c: longint notnull }
-- + {insert_stmt}: ok
-- + {insert_normal}
-- + {name_columns_values}
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_stmt}: a: integer
-- + {select_stmt}: b: text
-- + {select_stmt}: c: longint
proc with_insert_form()
begin
  with x(a,b,c) as (select 12, 'foo', 35L)
  insert into bar values (
     ifnull((select a from x), 0),
     ifnull((select b from x), 'foo'),
     ifnull((select 1L as c where 0), 0)
  );
end;

-- TEST: use a CTE on a insert statement using columns, all ok
-- - error:
-- + {with_insert_stmt}: ok
-- + {cte_table}: x: { a: integer notnull, b: text notnull, c: longint notnull }
-- + {insert_stmt}: ok
-- + {insert_normal}
-- + {name_columns_values}
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
proc with_column_spec_form()
begin
  with x(a,b,c) as (select 12, 'foo', 35L)
  insert into bar(id,name,rate) values (
     ifnull((select a from x), 0),
     ifnull((select b from x), 'foo'),
     ifnull((select 1L as c where 0), 0)
  );
end;

-- TEST: with-insert form, CTE is bogus
-- + error: % string operand not allowed in 'NOT'
-- + {with_insert_stmt}: err
-- + {cte_tables}: err
-- +1 error:
proc with_insert_bogus_cte()
begin
  with x(a) as (select not 'x')
  insert into bar(id,name,rate) values (1, 'x', 2);
end;

-- TEST: with-insert form, insert clause is bogus
-- + error: % string operand not allowed in 'NOT'
-- + {with_insert_stmt}: err
-- + {cte_tables}: ok
-- + {insert_stmt}: err
-- +1 error:
proc with_insert_bogus_insert()
begin
  with x(a) as (select 1)
  insert into bar(id,name,rate) values (1, not 'x', 1);
end;

-- TEST: insert from select (this couldn't possibly run but it makes sense semantically)
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_stmt}: _select_: { id: integer notnull, name: text, rate: longint }
insert into bar select * from bar where id > 5;

-- TEST: insert from select, wrong number of columns
-- + error: % count of columns differs from count of values
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_stmt}: _select_: { id: integer notnull }
-- +1 error:
insert into bar select id from bar;

-- TEST: insert from select, type mismatch in args
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_stmt}: _select_: { name: text, id: integer notnull, rate: longint }
-- +1 error:
insert into bar select name, id, rate from bar;

-- TEST: insert from select, bogus select
-- + error: % string operand not allowed in 'NOT'
-- + {insert_stmt}: err
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_stmt}: err
-- +1 error:
insert into bar select not 'x';

-- TEST: declare a function for use in select statements, this is a sqlite udf
-- + {declare_select_func_stmt}: real notnull select_func
-- + {param_detail}: id: integer variable in
-- - error:
declare select func SqlUserFunc(id integer) real!;

-- TEST: now try to use the user function in a select statement
-- + SELECT SqlUserFunc(1);
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {call}: real notnull
-- + {name SqlUserFunc}
-- - error:
select SqlUserFunc(1);

-- TEST: now try to use the user function with distinct keyword
-- + SELECT SqlUserFunc(DISTINCT id)
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {call}: real notnull
-- + {name SqlUserFunc}
-- + {distinct}
-- + {arg_list}: ok
-- - error:
select SqlUserFunc(distinct id) from foo;

-- TEST: now try to use the user function with filter clause
-- + SELECT SqlUserFunc(DISTINCT id)
-- + {select_stmt}: _select_: { _anon: real notnull }
-- + {call}: real notnull
-- + {name SqlUserFunc}
-- + {call_filter_clause}
-- + {distinct}
-- + {arg_list}: ok
-- - error:
select SqlUserFunc(distinct id) filter (where 1) from foo;

-- TEST: now try to use the select user function loose
-- + error: % User function may only appear in the context of a SQL statement 'SqlUserFunc'
-- + {assign}: err
-- + {name my_real}: my_real: real variable
-- + {call}: err
-- +1 error:
set my_real := SqlUserFunc(1);

-- TEST: now try to use the select user function loose with distinct
-- + error: % User function may only appear in the context of a SQL statement 'SqlUserFunc'
-- + {assign}: err
-- + {name my_real}: my_real: real variable
-- + {call}: err
-- +1 error:
set my_real := SqlUserFunc(distinct 1);

-- TEST: now try to use the select user function loose with filter clause
-- + error: % User function may only appear in the context of a SQL statement 'SqlUserFunc'
-- + {assign}: err
-- + {name my_real}: my_real: real variable
-- + {call}: err
-- +1 error:
set my_real := SqlUserFunc(1) filter (where 0);

-- TEST: declare select func with an error in declartion
-- + error: % func name conflicts with proc name 'foo'
declare select func foo(x integer, x integer) integer;

-- TEST: create a cursor and fetch from arguments
-- AST rewritten
-- + PROC arg_fetcher (arg1 TEXT!, arg2 INT!, arg3 REAL!)
-- + FETCH curs(A, B, C) FROM VALUES (arg1, arg2, arg3);
-- + {fetch_values_stmt}: ok
-- + {name_columns_values}
-- + {name curs}: curs: _select_: { A: text notnull, B: integer notnull, C: real notnull } variable shape_storage value_cursor
-- + {columns_values}: ok
-- + {column_spec}
-- + {name_list}
-- + {name A}: A: text notnull
-- + {name_list}
-- + {name B}: B: integer notnull
-- + {name_list}
-- + {name C}: C: real notnull
-- + {insert_list}
-- + {dot}: arg1: text notnull variable in
-- + {insert_list}
-- + {dot}: arg2: integer notnull variable in
-- + {insert_list}
-- + {dot}: arg3: real notnull variable in
proc arg_fetcher(arg1 text not null, arg2 int!, arg3 real!)
begin
  cursor curs like select 'x' A, 1 B, 3.5 C;
  fetch curs from arguments;
end;

-- TEST: use the arguments like "bar" even though there are other arguments
-- AST rewritten, note "extra" does not appear
-- + PROC fetch_bar (extra INT, id_ INT!, name_ TEXT, rate_ LONG)
-- + FETCH curs(id, name, rate) FROM VALUES (id_, name_, rate_);
-- + {create_proc_stmt}: ok
-- - error:
proc fetch_bar(extra integer, like bar)
begin
  cursor curs like bar;
  fetch curs from arguments(like bar);
end;

-- TEST: scoped like arguments
-- + PROC qualified_like (x_id INT!, x_name TEXT, x_rate LONG, y_id INT!, y_name TEXT, y_rate LONG)
proc qualified_like(x like bar, y like bar)
begin
end;

-- TEST: use the arguments like "bar" even though there are other arguments
-- AST rewritten, note "extra" does not appear
-- + PROC insert_bar (extra INT, id_ INT!, name_ TEXT, rate_ LONG)
-- + INSERT INTO bar(id, name, rate) VALUES (id_, name_, rate_);
-- + {create_proc_stmt}: ok
-- - error:
proc insert_bar(extra integer, like bar)
begin
  insert into bar from arguments(like bar);
end;

-- TEST: use the arguments like "bar" some have trailing _ and some do not
-- AST rewritten, note some have _ and some do not
-- + INSERT INTO bar(id, name, rate) VALUES (id, name_, rate);
-- + {create_proc_stmt}: ok
-- - error:
proc insert_bar_explicit(extra integer, id int!, name_ text, rate long integer)
begin
  insert into bar from arguments(like bar);
end;

-- TEST: use the locals like "bar" some have trailing _ and some do not
-- AST rewritten, note some have _ and some do not
-- + INSERT INTO bar(id, name, rate) VALUES (LOCALS.id, LOCALS.name, LOCALS.rate);
-- + {create_proc_stmt}: ok
-- - error:
proc insert_bar_locals(extra integer, id int!, name_ text, rate long integer)
begin
  insert into bar from locals(like bar);
end;

-- TEST: use the arguments like "bar" but some args are missing
-- AST rewritten, note some have _ and some do not
-- + error: % expanding FROM ARGUMENTS, there is no argument matching 'name'
-- + {create_proc_stmt}: err
-- +1 error:
proc insert_bar_missing(extra integer, id int!)
begin
  insert into bar from arguments(like bar);
end;

-- TEST: bogus name in the like part of from arguments
-- + error: % must be a cursor, proc, table, or view 'bogus_name_here'
-- + {create_proc_stmt}: err
-- + {insert_stmt}: err
-- +1 error:
proc insert_bar_from_bogus(extra integer, like bar)
begin
  insert into bar from arguments(like bogus_name_here);
end;

cursor val_cursor like my_cursor;

-- TEST: try to fetch a cursor from arguments but not in a procedure
-- + error: % FROM ARGUMENTS construct is only valid inside a procedure
-- + {fetch_values_stmt}: err
-- +1 error:
fetch val_cursor from arguments;

-- TEST: try to fetch a cursor but not enough arguments
-- + error: % [shape] has too few fields 'ARGUMENTS'
-- + {fetch_values_stmt}: err
-- +1 error:
proc arg_fetcher_not_enough_args(arg1 text not null)
begin
  cursor curs like select 'x' A, 1 B, 3.5 C;
  fetch curs from arguments;
end;

-- TEST: rewrite insert statement using arguments
-- + INSERT INTO bar(id, name, rate) VALUES (id, name, rate);
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- These appear as a parameter AND in the insert list
-- +1 {name id}: id: integer notnull variable in
-- +1 {name name}: name: text variable in
-- +1 {name rate}: rate: longint variable in
-- - error:
proc bar_auto_inserter(id int!, name text, rate LONG INT)
begin
 insert into bar from arguments;
end;

-- TEST: rewrite insert statement but minimal columns
-- + INSERT INTO bar(id) VALUES (id);
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- These appear as a parameters
-- +1 {name id}: id: integer notnull variable in
-- +1 {name name}: name: text variable in
-- +1 {name rate}: rate: longint variable in
-- - error:
proc bar_auto_inserter_mininal(id int!, name text, rate LONG INT)
begin
 insert into bar(id) from arguments;
end;

-- TEST: rewrite insert statement but no columns, bogus
-- + INSERT INTO bar() FROM ARGUMENTS
-- + error: % FROM [shape] is redundant if column list is empty
-- + {insert_stmt}: err
-- +1 error:
proc bar_auto_inserter_no_columns(id int!, name text, rate LONG INT)
begin
 insert into bar() from arguments @dummy_seed(1);
end;

-- TEST: rewrite insert statement but not enough columns
-- + INSERT INTO bar(id, name, rate) FROM ARGUMENTS(id);
-- + error: % [shape] has too few fields 'ARGUMENTS'
-- + {insert_stmt}: err
-- +1 error:
proc bar_auto_inserter_missing_columns(id integer)
begin
 insert into bar from arguments;
end;

-- TEST: rewrite proc arguments using the LIKE table form
-- - error:
-- + PROC rewritten_like_args (id_ INT!, name_ TEXT, rate_ LONG)
-- + INSERT INTO bar(id, name, rate) VALUES (id_, name_, rate_);
-- + {create_proc_stmt}: ok dml_proc
-- + {param}: id_: integer notnull variable in
-- + {param}: name_: text variable in
-- + {param}: rate_: longint variable in
-- + {insert_stmt}: ok
-- + {name bar}: bar: { id: integer notnull, name: text, rate: longint }
-- these appear as a parameter and also in the insert list
-- +1 {name id_}: id_: integer notnull variable in
-- +1 {name name_}: name_: text variable in
-- +1 {name rate_}: rate_: longint variable in
-- the clean name appears in the insert list and as a column
-- +2 {name id}
-- +2 {name name}
-- +2 {name rate}
-- the ARGUMENTS dot name resolves to the correct arg name
-- +1 {dot}: id_: integer notnull variable in
-- +1 {dot}: name_: text variable in
-- +1 {dot}: rate_: longint variable in
proc rewritten_like_args(like bar)
begin
  insert into bar from arguments;
end;

-- TEST: try to rewrite args on a bogus table
-- + error: % must be a cursor, proc, table, or view 'garbonzo'
-- + {create_proc_stmt}: err
-- +1 error:
proc rewrite_args_fails(like garbonzo)
begin
  declare x integer;
end;

-- a fake table for some args
create table args1(
 id integer primary key,
 name text,
 data blob
);

-- a fake table for some more args
create table args2(
 id integer references args1(id),
 name2 text,
 rate real
);

-- TEST: this procedure uses two tables for its args, the trick here is that both tables
--       have the id_ column;  we should only emit it once
-- note that id_ was skipped the second time
-- + PROC two_arg_sources (id_ INT!, name_ TEXT, data_ BLOB, name2_ TEXT, rate_ REAL)
-- + {create_proc_stmt}: ok
-- - error:
proc two_arg_sources(like args1, like args2)
begin
end;

-- TEST: test the case where 2nd and subsequent like forms do nothing
-- + PROC two_arg_sources_fully_redundant (id_ INT!, name_ TEXT, data_ BLOB)
-- + {create_proc_stmt}: ok
-- - error:
proc two_arg_sources_fully_redundant(like args1, like args1, like args1)
begin
end;

create view ViewShape as select TRUE a, 2.5 b, 'xyz' c;

-- + PROC like_a_view (a_ BOOL!, b_ REAL!, c_ TEXT!)
-- + SELECT v.a, v.b, v.c
-- +   FROM ViewShape AS v
-- + WHERE v.a = a_ AND v.b = b_ AND v.c > c_;
-- + {create_proc_stmt}: like_a_view: { a: bool notnull, b: real notnull, c: text notnull } dml_proc
proc like_a_view(like ViewShape)
begin
  select * from ViewShape v where v.a = a_ and v.b = b_ and v.c > c_;
end;

-- TEST: try to create a cursor that is like a select statement with not all names present
-- + error: % all columns in the select must have a name
-- +1 error:
proc bogus_cursor_shape()
begin
  cursor C like select 1, 2;
end;

-- TEST: views must have a name for every column
-- + all columns in the select must have a name
-- +1 error:
create view MyBogusView as select 1, 2;

-- TEST: make this proc accept args to fake the result of another proc
-- + {create_proc_stmt}: C: like_other_proc: { A: integer notnull, B: integer notnull } variable shape_storage uses_out
-- + {declare_cursor_like_name}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- + {out_stmt}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- - error:
proc like_other_proc(like out_cursor_proc)
begin
 cursor C like out_cursor_proc;
 fetch C from arguments;
 out C;
end;

-- TEST: create a proc using another proc that doesn't have a result type
-- + error: % proc has no result 'proc1'
-- + {create_proc_stmt}: err
-- +1 error:
procedure bogus_like_proc(like proc1)
begin
  declare x int;
end;

-- TEST: create a non-temporary table using another table
-- + create_table_stmt% nontemp_table_like_table: % id: integer
-- - error:
create temp table nontemp_table_like_table(
  like foo
);

-- TEST: create a temporary table using another table
-- + create_table_stmt% table_like_table: % id: integer
-- - error:
create temp table table_like_table(
  like foo
);

-- TEST: create a temporary table using a view
-- + {create_table_stmt}: table_like_view: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- - error:
create temp table table_like_view(
  like MyView
);

-- TEST: create a temporary table using a proc
-- + {create_table_stmt}: table_like_proc: { id: integer notnull, name: text, rate: longint }
-- - error:
create temp table table_like_proc(
  like with_result_set
);

-- TEST: try to create a table with a proc with no result
-- + error: % proc has no result 'proc1'
-- + {create_table_stmt}: err
-- + {col_key_list}: err
-- +1 error:
create temp table table_like_proc_with_no_result(
  like proc1
);

-- TEST: try to create a table with non existent view/proc/view
-- + error: % must be a cursor, proc, table, or view 'this_thing_doesnt_exist'
-- + {create_table_stmt}: err
-- + {col_key_list}: err
-- +1 error:
create temp table table_like_nonexistent_view(
  like this_thing_doesnt_exist
);

-- TEST: create a temp table using two like arguments
-- + {create_table_stmt}: table_multiple_like: { f1: integer notnull, f2: integer notnull, f3: integer notnull, id: integer notnull, name: text, rate: longint }
-- - error:
create temp table table_multiple_like(
  like MyView, like with_result_set
);

-- TEST: create a temp table using mix of like and normal columns
-- + {create_table_stmt}: table_like_mixed: { garbage: text, f1: integer notnull, f2: integer notnull, f3: integer notnull, happy: integer }
-- - error:
create temp table table_like_mixed(
  garbage text, like MyView, happy integer
);

-- TEST: try to create a temp table but there is a duplicate column after expanding like
-- + error: % duplicate column name 'f1'
-- + {create_table_stmt}: err
-- +1 error:
create temp table table_with_dup_col(
  f1 text, like MyView
);

-- TEST: try to create a temp view with versioning -- not allowed
-- + error: % temp objects may not have versioning annotations 'bogus_temp_view_with_versioning'
-- + {create_view_stmt}: err
-- +1 error:
create temp view bogus_temp_view_with_versioning as select 1 x @delete(1);

-- TEST: try to create a temp trigger with versioning -- not allowed
-- + error: % temp objects may not have versioning annotations 'bogus_temp_trigger'
-- + {create_trigger_stmt}: err
-- +1 error:
create temp trigger if not exists bogus_temp_trigger
  before delete on bar
begin
  delete from bar where rate > id;
end @delete(2);

-- TEST: try to create a temp table with versioning -- not allowed
-- + error: % temp objects may not have versioning annotations 'bogus_temp_with_create_versioning'
-- + {create_table_stmt}: err
-- +1 error:
create temp table bogus_temp_with_create_versioning(
  id integer
) @create(1);

-- TEST: try to create a temp table with versioning -- not allowed
-- + error: % temp objects may not have versioning annotations 'bogus_temp_with_delete_versioning'
-- + {create_table_stmt}: err
-- +1 error:
create temp table bogus_temp_with_delete_versioning(
  id integer
) @delete(1);

-- TEST: try to create a temp table with recreate versioning -- not allowed
-- + error: % temp objects may not have versioning annotations 'bogus_temp_with_recreate_versioning'
-- + {create_table_stmt}: err
-- +1 error:
create temp table bogus_temp_with_recreate_versioning(
  id integer
) @recreate;

-- TEST: try to create a temp table with versioning in a column -- not allowed
-- + error: % columns in a temp table may not have versioning attributes 'id'
-- + {create_table_stmt}: err
-- +1 error:
create temp table bogus_temp_with_versioning_in_column(
  id integer @create(2)
);

-- TEST: try to use match in a select statement
-- + {select_expr}: bool notnull
-- + {match}: bool notnull
-- + {strlit 'x'}: text notnull
-- + {strlit 'y'}: text notnull
-- - error:
select 'x' match 'y';

-- TEST: try to use match not in a select statement
-- + error: % operator may only appear in the context of a SQL statement 'MATCH'
-- + {assign}: err
-- + {match}: err
-- +1 error:
set X := 'x' match 'y';

-- TEST: try to use glob in a select statement
-- + {select_expr}: bool notnull
-- + {glob}: bool notnull
-- + {strlit 'x'}: text notnull
-- + {strlit 'y'}: text notnull
-- - error:
select 'x' glob 'y';

-- TEST: try to use glob not in a select statement
-- + error: % operator may only appear in the context of a SQL statement 'GLOB'
-- + {assign}: err
-- + {glob}: err
-- +1 error:
set X := 'x' GLOB 'y';

-- TEST: try to use match not in a select statement
-- + error: % operator may only appear in the context of a SQL statement 'MATCH'
-- + {assign}: err
-- + {match}: err
-- +1 error:
set X := 'x' MATCH 'y';

-- TEST: try to use regexp not in a select statement
-- + error: % operator may only appear in the context of a SQL statement 'REGEXP'
-- + {assign}: err
-- + {regexp}: err
-- +1 error:
set X := 'x' REGEXP 'y';

-- TEST: REGEXP inside of SQL is ok
-- + {regexp}: bool notnull
-- - error:
set X := (select 'x' REGEXP 'y');

-- TEST: shift and bitwise operators
-- + SET X := 1 << 2 | 1 << 4 & 1 >> 8;
-- + {assign}: X: integer variable
-- + {name X}: X: integer variable
-- + {rshift}: integer notnull
-- + {bin_and}: integer notnull
-- + {lshift}: integer notnull
-- + {bin_or}: integer notnull
-- + {lshift}: integer notnull
-- - error:
set X := 1 << 2 | 1 << 4 & 1 >> 8;

-- TEST: try a integer operator with a real
-- + error: % operands must be an integer type, not real '&'
-- + {assign}: err
-- + {bin_and}: err
-- +1 error:
set X := 3.0 & 2;

-- TEST: try a integer unary operator with a real
-- + error: % operands must be an integer type, not real '~'
-- + {assign}: err
-- + {tilde}: err
-- +1 error:
set X := ~3.0;

-- TEST: use column aliases in ORDER BY statement
-- + {create_proc_stmt}: simple_alias_order_by: { bar_id: integer notnull } dml_proc
-- + {name bar_id}: bar_id: integer notnull
-- - error:
proc simple_alias_order_by()
begin
  select id as bar_id
  from bar
  order by bar_id;
end;

-- TEST: use column aliases for fabricated columns in ORDER BY statement
-- + {create_proc_stmt}: complex_alias_order_by: { sort_order_value: integer notnull, id: integer notnull } dml_proc
-- + {name sort_order_value}: sort_order_value: integer notnull
-- - error:
proc complex_alias_order_by()
begin
  select 1 as sort_order_value, id from bar
  union all
  select 2 as sort_order_value, id from bar
  order by sort_order_value, id;
end;

-- TEST: fake stories table for test case stolen from the real schema
create table stories(media_id long);

-- TEST: basic delete trigger
-- + CREATE TEMP TRIGGER IF NOT EXISTS trigger1
-- +   BEFORE DELETE ON bar
-- +   FOR EACH ROW
-- +   WHEN old.id = 3
-- + {create_trigger_stmt}: ok
-- + {eq}: bool notnull
-- + {dot}: id: integer notnull
-- +2 {delete_stmt}: ok
-- - error:
create temp trigger if not exists trigger1
  before delete on bar
  for each row
  when old.id = 3
begin
  delete from bar where rate > id;
  delete from bar where rate = old.id;
end;

-- TEST: basic delete trigger, try to use "new"
-- + CREATE TRIGGER trigger1a
-- +   BEFORE DELETE ON bar
-- +   WHEN new.id = 3
-- + error: % name not found 'new.id'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger1a
  before delete on bar
  when new.id = 3
begin
  delete from bar where rate > id;
end;

-- TEST: basic insert trigger
-- + CREATE TRIGGER trigger2
-- +   AFTER INSERT ON bar
-- + BEGIN
-- +   DELETE FROM bar WHERE rate > new.id;
-- + END;
-- +  {create_trigger_stmt}: ok
-- +1 {delete_stmt}: ok
-- - error:
create trigger trigger2
  after insert on bar
begin
  delete from bar where rate > new.id;
end;

-- TEST: basic insert trigger, try to use "old"
-- + CREATE TRIGGER trigger2a
-- +   AFTER INSERT ON bar
-- +   WHEN old.id = 3
-- + error: % name not found 'old.id'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger2a
  after insert on bar
  when old.id = 3
begin
  delete from bar where rate > id;
end;

-- TEST: use update instead of on a view
-- + {create_trigger_stmt}: ok
-- +4 {dot}: b: real notnull
-- + {name ViewShape}
-- + {update_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- + {insert_stmt}: ok
-- - error:
create trigger trigger3
  instead of update on ViewShape
  when old.b > 1 and new.b < 3
begin
  update bar set id = 7 where rate > old.b and rate < new.b;
  update bar set id = 8 where rowid = old.rowid or rowid = new.rowid;
  insert into bar values (7, 'goo', 17L);
end;

-- TEST: exact duplicate trigger is ok
-- + {create_trigger_stmt}: ok alias
-- +4 {dot}: b: real notnull
-- + {name ViewShape}
-- + {update_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- + {insert_stmt}: ok
-- - error:
create trigger trigger3
  instead of update on ViewShape
  when old.b > 1 and new.b < 3
begin
  update bar set id = 7 where rate > old.b and rate < new.b;
  update bar set id = 8 where rowid = old.rowid or rowid = new.rowid;
  insert into bar values (7, 'goo', 17L);
end;

-- TEST: duplicate trigger
-- + error: % CREATE TRIGGER trigger3
-- + error: % CREATE TRIGGER trigger3
-- + The above must be identical.
-- + error: % trigger already exists 'trigger3'
-- + {create_trigger_stmt}: err
-- + {name ViewShape}
-- +3 error:
create trigger trigger3
  instead of update on ViewShape
begin
  select 1;
end;

-- TEST: specify update columns
-- + {create_trigger_stmt}: ok
-- + {name a}: a: bool notnull
-- + {name b}: b: real notnull
-- + {name c}: c: text notnull
-- - error:
create trigger trigger4
  instead of update of a, b, c on ViewShape
begin
  select 1;
end;

-- TEST: specify update columns
-- + error: % name list has duplicate name 'a'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger4a
  instead of update of a, a, c on ViewShape
begin
  select 1;
end;

-- TEST: specify a view where one is not allowed
-- + error: % a trigger on a view must be the INSTEAD OF form 'ViewShape'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger4b
  before update on ViewShape
begin
  select 1;
end;

-- TEST: specify a bogus table name
-- + error: % table/view not found 'no_such_table_dude'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger4c
  before update on no_such_table_dude
begin
  select 1;
end;

-- TEST: specify a bogus executed statement
-- + error: % name not found 'old.id'
-- + {create_trigger_stmt}: err
-- + {stmt_list}: err
-- + {select_stmt}: err
-- +1 error:
create trigger trigger4d
  before insert on bar
begin
  select old.id;
end;

-- TEST: this proc is not a result proc even though it looks like it has a loose select...
-- the select is inside a trigger, it is NOT a return for this proc
-- - {create_proc_stmt}: make_trigger: { id: integer notnull } dml_proc
-- + {create_proc_stmt}: ok dml_proc
-- - error:
proc make_trigger()
begin
  create trigger selecting_trigger
    before delete on bar
    for each row
    when old.id > 7
  begin
    select old.id;
  end;
end;

-- TEST: try to drop a trigger (bogus)
-- + error: % trigger in drop statement was not declared 'this_trigger_does_not_exist'
-- + {drop_trigger_stmt}: err
-- +1 error:
drop trigger this_trigger_does_not_exist;

-- TEST: try to drop a trigger (bogus)
-- + {drop_trigger_stmt}: ok
-- + {int 1}
-- - error:
drop trigger if exists trigger1;

-- TEST: try to delete  a table before it was created
-- + error: % delete version can't be <= create version 'retro_deleted_table'
-- + {create_table_stmt}: err
-- +1 error:
create table retro_deleted_table( id integer) @create(3) @delete(1);

-- TEST: basic delete trigger with RAISE expression
-- + {create_trigger_stmt}: ok
-- + {raise}: null
-- - error:
create temp trigger if not exists trigger5
  before delete on bar
begin
  select RAISE(rollback, "omg roll it back!");
end;

-- TEST: try to use raise in a non trigger context
-- + error: % RAISE may only be used in a trigger statement
-- + {select_stmt}: err
-- + {raise}: err
-- +1 error:
select RAISE(ignore);

-- TEST: try to use raise with a bogus string
-- + error: % RAISE 2nd argument must be a string
-- + {create_trigger_stmt}: err
-- + {raise}: err
-- +1 error:
create temp trigger if not exists trigger6
  before delete on bar
begin
  select RAISE(rollback, 0);
end;

-- TEST: try to use raise with a bogus expression
-- + error: % string operand not allowed in 'NOT'
-- + {create_trigger_stmt}: err
-- + {raise}: err
-- +1 error:
create temp trigger if not exists trigger7
  before delete on bar
begin
  select RAISE(rollback, not 'x');
end;

-- TEST: try to create a trigger with a migrate proc
-- + error: % migration proc not allowed on object 'trigger8'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger if not exists trigger8
  before delete on bar
begin
  select 1 x;
end @delete(1, MigrateProcFoo);

-- TEST: try to select union with different number of columns
-- + error: % if multiple selects, all must have the same column count
-- + {select_core_list}: err
-- + {select_core_compound}
-- +2 {int 2}
-- diagnostics also present
-- +4 error:
select 1 as A, 2 as B, 3 as C
union all
select 3 as A, 4 as B;

-- TEST: try to select union with different incompatible types
-- + error: % required 'INT' not compatible with found 'TEXT' context 'A'
-- + {select_core_list}: err
-- + {select_core_compound}
-- +2 {int 2}
-- +1 error:
select 1 as A, 2 as B
union all
select 'x' as A, 4 as B;

-- TEST: try to select union with different compatible types (null checks)
-- + {select_core_list}: union_all: { A: integer, B: integer }
-- + {select_core}: _select_: { A: integer notnull, B: integer }
-- + {select_core_compound}
-- + {int 2}
-- + {select_core}: _select_: { A: null, B: integer notnull }
-- - error:
select 1 as A, nullable(2) as B
union all
select NULL as A, 4 as B;

-- TEST: try to select union multiple times
-- + {select_stmt}: union_all: { A: integer notnull, B: integer notnull }
-- + {select_core_compound}
-- +7 {int 2}
-- +3 {select_core_list}: union_all: { A: integer notnull, B: integer notnull }
-- +4 {select_core}: _select_: { A: integer notnull, B: integer notnull }
-- - error:
select 1 as A, 2 as B
union all
select 1 as A, 2 as B
union all
select 1 as A, 2 as B
union all
select 1 as A, 2 as B;

-- TEST: try to return untyped NULL
-- + error: % NULL expression has no type to imply the type of the select result 'n'
-- + {create_proc_stmt}: err
-- +1 error:
proc returns_bogus_null()
begin
  select null AS n;
end;

-- TEST: try to declare cursor for untyped NULL
-- + error: % NULL expression has no type to imply the type of the select result 'n'
-- + {create_proc_stmt}: err
-- +1 error:
proc fetch_null_column()
begin
  cursor C for select null AS n;
  fetch C;
end;

-- TEST: declare a column as
-- + {create_table_stmt}: with_sensitive: { id: integer, name: text sensitive, info: integer sensitive }
-- - error:
create table with_sensitive(
 id integer,
 name text @sensitive,
 info integer @sensitive
);

-- TEST: declare a table to test with with_sensitive table with non-sensitive column as
-- + {create_table_stmt}: without_sensitive: { name: text }
-- - error:
create table without_sensitive(
 name text
);

-- TEST: select out some
-- + {create_proc_stmt}: get_sensitive: % dml_proc
-- + safe: integer notnull,
-- + sensitive_1: integer sensitive,
-- + sensitive_2: text sensitive,
-- + not_sensitive_1: text notnull,
-- + sensitive_3: integer sensitive,
-- + sensitive_4: bool sensitive
proc get_sensitive()
begin
  select 1 as safe,
        info+1 sensitive_1,
        name as sensitive_2,
        'x' as not_sensitive_1,
        -info as sensitive_3,
        info between 1 and 3 as sensitive_4
  from with_sensitive;
end;

-- TEST: making a sensitive variable
-- + {declare_vars_type}: integer sensitive
-- - error:
declare _sens integer @sensitive;

-- TEST: using sensitive in the LIMIT clause
-- + {select_stmt}: _select_: { safe: integer notnull sensitive }
-- - error:
select 1 as safe
limit _sens;

-- TEST: using sensitive in the LIMIT clause (control case)
-- + {select_stmt}: _select_: { safe: integer notnull }
-- - error:
select 1 as safe
limit 1;

-- TEST: using sensitive in the OFFSET clause (control case)
-- + {select_stmt}: _select_: { safe: integer notnull sensitive }
-- - error:
select 1 as safe
limit 1
offset _sens;

-- TEST: using sensitive in the OFFSET clause (control case)
-- + {select_stmt}: _select_: { safe: integer notnull }
-- - error:
select 1 as safe
limit 1
offset 1;

-- TEST: local  arithmetic
-- + {add}: integer sensitive
-- + {name _sens}: _sens: integer variable sensitive
-- - error:
set _sens := _sens + 1;

-- TEST: in an IN expression (needle)
-- + {in_pred}: bool sensitive
-- + {name _sens}: _sens: integer variable sensitive
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- - error:
set _sens := _sens in (1, 2);

-- TEST: in an IN expression (haystack)
-- + {in_pred}: bool notnull sensitive
-- + {int 1}: integer notnull
-- + {expr_list}: _sens: integer variable sensitive
-- + {name _sens}: _sens: integer variable sensitive
-- - error:
set _sens := 1 in (1, _sens);

-- TEST: in an IN expression (select form)
-- + {select_stmt}: _anon: bool notnull sensitive
-- + {in_pred}: bool notnull sensitive
-- - error:
set _sens := (select 1 in (select info from with_sensitive));

-- TEST: in a CASE statement (control case)
-- + {case_expr}: integer notnull
-- + {int 0}: integer notnull
-- + {case_list}: integer notnull
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {int 3}: integer notnull
-- - error:
set _sens := nullable(case 0 when 1 then 2 else 3 end);

-- TEST: in a CASE statement (sensitive in the main expression)
-- + {case_expr}: integer notnull sensitive
-- + {name _sens}: _sens: integer variable sensitive
-- + {case_list}: integer notnull
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {int 3}: integer notnull
-- - error:
set _sens := nullable(case _sens when 1 then 2 else 3 end);

-- TEST: in a CASE statement (sensitive in the when part)
-- + {case_expr}: integer notnull sensitive
-- + {int 0}: integer notnull
-- + {case_list}: integer notnull
-- + {name _sens}: _sens: integer variable sensitive
-- + {int 2}: integer notnull
-- + {int 3}: integer notnull
-- - error:
set _sens := nullable(case 0 when _sens then 2 else 3 end);

-- TEST: in a CASE statement (sensitive in the then part)
-- + {case_expr}: integer sensitive
-- + {int 0}: integer notnull
-- + {case_list}: integer variable sensitive
-- + {int 1}: integer notnull
-- + {name _sens}: _sens: integer variable sensitive
-- + {int 3}: integer notnull
-- - error:
set _sens := nullable(case 0 when 1 then _sens else 3 end);

-- TEST: in a CASE statement (sensitive in the else part)
-- + {case_expr}: integer sensitive
-- + {int 0}: integer notnull
-- + {case_list}: integer notnull
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {name _sens}: _sens: integer variable sensitive
-- - error:
set _sens := nullable(case 0 when 1 then 2 else _sens end);

-- TEST: make sure that cast preserves
-- + {select_stmt}: _anon: integer sensitive
-- - error:
set _sens := (select cast(_sens as INT));

-- TEST: make sure AVG preserves
-- + {name AVG}: real sensitive
-- - error:
select AVG(T1.info) from with_sensitive T1;

-- TEST: make sure MIN preserves
-- + {name MIN}: integer sensitive
-- - error:
select MIN(T1.info) from with_sensitive T1;

-- TEST: make sure MAX preserves
-- + {name MAX}: integer sensitive
-- - error:
select MAX(T1.info) from with_sensitive T1;

-- TEST: make sure SUM preserves
-- + {name SUM}: integer sensitive
-- - error:
select SUM(T1.info) from with_sensitive T1;

-- TEST: make sure COUNT preserves
-- + {name COUNT}: integer notnull sensitive
-- - error:
select COUNT(T1.info) from with_sensitive T1;

-- TEST: control  AVG
-- - {name AVG}: id: % sensitive
-- + {name AVG}: real
-- - error:
select AVG(T1.id) from with_sensitive T1;

-- TEST: control  MAX
-- - {name MAX}: id: % sensitive
-- + {name MAX}: integer
-- - error:
select MAX(T1.id) from with_sensitive T1;

-- TEST: control  SUM
-- - {name SUM}: id: % sensitive
-- + {name SUM}: integer
-- - error:
select SUM(T1.id) as s  from with_sensitive T1;

-- TEST: control  COUNT
-- - {name COUNT}: id: % sensitive
-- + {name COUNT}: integer notnull
-- - error:
select COUNT(T1.id) c from with_sensitive T1;

-- TEST: coalesce
-- + {call}: integer notnull sensitive
-- - error:
set _sens := coalesce(_sens, 0);

-- TEST: coalesce control case ok
-- - {call}: % sensitive
-- - error:
set _sens := coalesce(nullable(1), 0);

-- TEST: coalesce control not null
-- + error: % encountered arg known to be not null before the end of the list, rendering the rest useless. '7'
-- - {call}: % sensitive
-- +1 error:
set _sens := coalesce(7, 0);

-- TEST: sensitive with IS right
-- + {is}: bool notnull sensitive
-- - error:
set _sens := 0 is _sens;

-- TEST: sensitive with IS left
-- + {is}: bool notnull sensitive
-- - error:
set _sens := _sens is 0;

-- TEST: sensitive with IS control
-- - {is}: % sensitive
-- + {is}: bool notnull
-- - error:
set _sens := 0 is 0;

-- TEST: sensitive with IS NOT right
-- + {is_not}: bool notnull sensitive
-- - error:
set _sens := 0 is not _sens;

-- TEST: sensitive with IS NOT left
-- + {is_not}: bool notnull sensitive
-- - error:
set _sens := _sens is not 0;

-- TEST: sensitive with IS NOT control
-- - {is_not}: % sensitive
-- + {is_not}: bool notnull
-- - error:
set _sens := 0 is not 0;

-- TEST: sensitive implicit due to where clause
-- + {select_stmt}: id: integer sensitive
-- + {opt_where}: bool sensitive
-- - error:
set _sens := (select id from with_sensitive where info = 1);

-- TEST: select implicit control case (where not sensitive)
-- - {select_stmt}: id: integer sensitive
-- + {select_stmt}: id: integer
-- - {opt_where}: % sensitive
-- + {opt_where}: bool
-- - error:
set _sens := (select id from with_sensitive where id = 1);

-- TEST: sensitive implicit due to having clause
-- + {select_stmt}: id: integer sensitive
-- + {opt_having}: bool sensitive
-- - error:
set _sens := (select id from with_sensitive group by info having info = 1);

-- TEST: assign sensitive column value to a non-sensitive colunm
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'name'
-- + {insert_stmt}: err
-- +1 error:
insert into without_sensitive select name from with_sensitive;

create table a (
  key_ int! primary key,
  sort_key int!
);

create table b (
  key_ int! primary key,
  a_key_ int!,
  sort_key int!
);

-- TEST: compound select ordered by name
-- + {select_stmt}: UNION: { key_: integer notnull, sort_key: integer notnull }
-- - error:
select key_, sort_key from a
union
select key_, sort_key from b
order by sort_key, key_;

-- TEST: compound select ordered by index
-- + {select_stmt}: UNION: { key_: integer notnull, sort_key: integer notnull }
-- - error:
select key_, sort_key from a
union
select key_, sort_key from b
order by 2, key_;

-- TEST: compound select ordered by an arbitrary expression
-- + error: % compound select cannot be ordered by the result of an expression
-- + {select_stmt}: err
-- + {select_orderby}: err
-- +1 error:
select key_, sort_key from a
union
select key_, sort_key from b
order by 1 + 1, key_;

-- TEST: compound select name lookup from select list (other places ambiguous, still ok)
-- + ORDER BY sort_key, key_;
-- + {select_stmt}: union_all: { key_: integer notnull, sort_key: integer notnull }
-- + {select_core_list}: union_all: { key_: integer notnull, sort_key: integer notnull }
-- + {select_core_compound}
-- + {opt_orderby}: ok
-- - error:
select a.key_, a.sort_key
  from a
union all
select b.key_, b.sort_key
  from a
  inner join b ON b.a_key_ = a.key_
order by sort_key, key_;

-- TEST: compound select name lookup using something other than the select list
-- + ORDER BY a_key_
-- + error: % name not found 'a_key_'
-- + {opt_orderby}: err
-- +1 error:
select a.key_, a.sort_key
  from a
union all
select b.key_, b.sort_key
  from a
  inner join b on b.a_key_ = a.key_
order by a_key_
limit 2
offset 3;

-- TEST: compound select name lookup using something other than the select list (explicit)
-- + ORDER BY b.a_key_;
-- + error: % name not found 'b.a_key_'
-- + {opt_orderby}: err
-- +1 error:
select a.key_, a.sort_key
  from a
union ALL
select b.key_, b.sort_key
  from a
  inner join b ON b.a_key_ = a.key_
order by b.a_key_;

-- TEST: join columns become  because ON condition is SENSITIVE
-- + {select_stmt}: _select_: { id: integer notnull sensitive }
-- - error:
select T1.id from bar T1 inner join with_sensitive T2 on T1.id = T2.id and T2.info = 1;

-- TEST: join columns  flag ON condition (control case)
-- + {select_stmt}: _select_: { id: integer notnull }
-- - {select_stmt}: _select_: { id: % sensitive }
-- - error:
select T1.id from bar T1 inner join with_sensitive T2 on T1.id = T2.id;

-- TEST: join columns become  because USING condition has SENSITIVE columns
-- + {select_stmt}: _select_: { id: integer sensitive }
-- + {name_list}: info: integer sensitive
-- - error:
select T1.id from with_sensitive T1 inner join with_sensitive T2 using(info);

-- TEST: join columns do not become  because USING condition has no SENSITIVE columns
-- + {select_stmt}: _select_: { id: integer }
-- - {select_stmt}: _select_: { id: % sensitive }
-- + {name_list}: id: integer
-- - error:
select T1.id from with_sensitive T1 inner join with_sensitive T2 using(id);

-- TEST: try to assign sensitive data to a non-sensitive variable
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'X'
-- + {assign}: err
-- + {name _sens}: _sens: integer variable sensitive
-- +1 error:
set X := _sens;

-- TEST: try to call a normal proc with a sensitive parameter
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'id'
-- + error: % additional info: calling 'decl1' argument #1 intended for parameter 'id' has the problem
-- + {call_stmt}: err
-- +2 error:
call decl1(_sens);

declare proc sens_proc(out foo integer @sensitive);
declare proc non_sens_proc(out foo integer);
declare proc non_sens_proc_nonnull(out foo int!);

-- TEST: try to call a proc with a sensitive out parameter
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'X'
-- + error: % additional info: calling 'sens_proc' argument #1 intended for parameter 'foo' has the problem
-- +2 error:
call sens_proc(X);

-- TEST: control case: ok to call a proc with a non-sensitive out parameter
-- + {name _sens}: _sens: integer variable sensitive
-- - error:
call non_sens_proc(_sens);

-- TEST: make sure we can't call a proc that takes a nullable int out with a not-null integer
-- + error: % cannot assign/copy possibly null expression to not null target 'int_nn'
-- + error: % additional info: calling 'non_sens_proc' argument #1 intended for parameter 'foo' has the problem
-- +2 error:
call non_sens_proc(int_nn);

-- TEST: make sure we can't call a proc that takes a non-nullable int out with a nullable integer
-- + error: % proc out parameter: arg must be an exact type match (even nullability) (expected integer notnull; found integer)
-- + error: % additional info: calling 'non_sens_proc_nonnull' argument #1 intended for parameter 'foo' has the problem
-- +2 error:
call non_sens_proc_nonnull(X);

declare proc ref_out_proc(out x text!);

-- TEST: it's ok to invoke a procedure that has a not null ref out parameter with a nullable ref arg
-- + {name_list}: nullable_ok: text variable was_set
-- + {name nullable_ok}: nullable_ok: text variable was_set
-- + {call_stmt}: ok
-- + {arg_list}: ok
-- + {name nullable_ok}: nullable_ok: text variable
proc ref_out_notnull()
begin
  var nullable_ok text;
  ref_out_proc(nullable_ok);
end;

-- TEST: try to insert sensitive data to a non-sensitive column
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'id'
-- +1 error:
insert into foo(id) values (coalesce(_sens,0));

-- TEST: try to update to sensitive
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'id'
-- + error: % additional info: in update table 'bar' the column with the problem is 'id'
-- +2 error:
update bar set id = coalesce(_sens,0) where name = 'x';

-- Do various validations on this func in the following tests
func sens_func(id integer @sensitive, t text) text @sensitive;
declare sens_text text @sensitive;
declare non_sens_text text;

-- TEST: ok to assign to sensitive text, ok to pass non-sensitive integer as a sensitive integer
-- + {assign}: sens_text: text variable sensitive
-- + {name sens_text}: sens_text: text variable sensitive
-- + {call}: text sensitive
-- - error:
set sens_text := sens_func(1, 'x');

-- TEST: not ok to assign to non-sensitive text
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'non_sens_text'
-- + {assign}: err
-- + {name non_sens_text}: err
-- + {call}: text sensitive
-- +1 error:
set non_sens_text := sens_func(1, 'x');

-- TEST: not ok to pass sensitive text as non-sensitive arg
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 't'
-- + error: % additional info: calling 'sens_func' argument #2 intended for parameter 't' has the problem
-- + {call}: err
-- +2 error:
set sens_text := sens_func(1, sens_text);

-- TEST: make sure that the expression in the update is evaluated in the select context
--       this allows you to use things like CAST or date operations
-- + {update_stmt}: foo: { id: integer notnull primary_key autoinc }
-- + {cast_expr}: integer notnull
-- - error:
update foo set id = cast('1' as integer);

-- TEST: basic delete stmt with CTE form
-- + {with_delete_stmt}: ok
-- + {select_from_etc}: TABLE { x: x }
-- - error:
proc with_delete_form()
begin
  with x(id) as (select 1 union all select 2)
  delete from bar where id in (select * from x);
end;

-- TEST: basic delete stmt with CTE form (CTE bogus)
-- + error: % required 'INT' not compatible with found 'TEXT' context '_anon'
-- + {create_proc_stmt}: err
-- + {with_delete_stmt}: err
-- + {cte_tables}: err
-- + {select_expr_list_con}: _select_: { _anon: integer notnull }
-- + {select_expr_list_con}: _select_: { _anon: text notnull }
-- +1 error:
proc with_delete_form_bogus_cte()
begin
  with x(id) as (select 1 union all select 'x')
  delete from bar where id in (select * from x);
end;

-- TEST: basic delete stmt with CTE form (delete bogus)
-- + error: % table in delete statement does not exist 'not_valid_table'
-- + {create_proc_stmt}: err
-- + {with_delete_stmt}: err
-- +1 error:
proc with_delete_form_bogus_delete()
begin
  with x(id) as (select 1 union all select 2)
  delete from not_valid_table where id in (select * from x);
end;

-- TEST: basic update stmt with CTE form
-- + {with_update_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- + {select_from_etc}: TABLE { x: x }
-- - error:
proc with_update_form()
begin
  with x(id) as (select 1 union all select 2)
  update bar set name = 'xyzzy' where id in (select * from x);
end;

-- TEST: basic update stmt with CTE form (CTE bogus)
-- + error: % required 'INT' not compatible with found 'TEXT' context '_anon'
-- + {create_proc_stmt}: err
-- + {with_update_stmt}: err
-- + {cte_tables}: err
-- + {select_expr_list_con}: _select_: { _anon: integer notnull }
-- + {select_expr_list_con}: _select_: { _anon: text notnull }
-- +1 error:
proc with_update_form_bogus_cte()
begin
  with x(id) as (select 1 union all select 'x')
  update bar set name = 'xyzzy' where id in (select * from x);
end;

-- TEST: basic update stmt with CTE form (update bogus)
-- + error: % table in update statement does not exist 'not_valid_table'
-- + {create_proc_stmt}: err
-- + {with_update_stmt}: err
-- +1 error:
proc with_update_form_bogus_delete()
begin
  with x(id) as (select 1 union all select 2)
  update not_valid_table set name = 'xyzzy' where id in (select * from x);
end;

-- TEST: match a proc that was previously created
-- + DECLARE PROC out_cursor_proc () OUT (A INT!, B INT!) USING TRANSACTION;
-- + {declare_proc_stmt}: out_cursor_proc: { A: integer notnull, B: integer notnull } dml_proc uses_out
-- - error:
declare proc out_cursor_proc() OUT (A int!, B int!) using transaction;

-- TEST: declare the proc first then create it
-- + PROC decl1 (id INT)
-- + {create_proc_stmt}: ok
-- - error:
proc decl1(id integer)
begin
 declare i integer;
end;

-- TEST: try to create it again, even though it matches, no dice
-- + error: % duplicate stored proc name 'decl1'
-- + {create_proc_stmt}: err
-- +1 error:
proc decl1(id integer)
begin
 declare i integer;
end;

-- TEST: try to create a proc that doesn't match the signature
-- the only difference here is that the declaration specified
-- that this was to be a proc that uses the database... we will not do so
-- + PROC decl2 (id INT)
-- + Incompatible declarations found
-- + error: % DECLARE PROC decl2 (id INT) USING TRANSACTION
-- + error: % DECLARE PROC decl2 (id INT)
-- + The above must be identical.
-- + error: % procedure declarations/definitions do not match 'decl2'
-- + {create_proc_stmt}: err
-- +3 error:
proc decl2(id integer)
begin
 declare i integer;
end;

-- TEST: autotest attribute with all attributes
-- + {stmt_and_attr}
-- + {misc_attrs}: ok
-- + {dot}
-- + {name cql}
-- + {name autotest}
-- + {misc_attr_value_list}
-- + {name dummy_test}: ok
-- + {name dummy_table}: ok
-- + {name dummy_insert}: ok
-- + {name dummy_select}: ok
-- + {name dummy_result_set}: ok
-- + {create_proc_stmt}: autotest_all_attribute: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[autotest=(dummy_test, dummy_table, dummy_insert, dummy_select, dummy_result_set)]]
proc autotest_all_attribute()
begin
  select * from bar;
end;

-- TEST: autotest attribute with dummy_test info on multiple columns
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {misc_attr}
-- + {dot}
-- + {name cql}
-- + {name autotest}
-- + {misc_attr_value_list}: ok
-- + {name dummy_table}: ok
-- + {name dummy_test}: ok
-- + {misc_attr_value_list}: ok
-- + {name bar}: ok
-- + {name id}: ok
-- + {name name}: ok
-- + {int 1}: ok
-- + {strlit 'Nelly'}: ok
-- + {uminus}: ok
-- + {int 2}: ok
-- + {strlit 'Babeth'}: ok
-- + {name foo}: ok
-- + {name id}: ok
-- + {int 777}: ok
-- + {create_proc_stmt}: autotest_dummy_test_with_others_attributes: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[autotest=(dummy_table, (dummy_test, (bar, (id, name), (1, 'Nelly'), (-2, 'Babeth')), (foo, (id), (777))))]]
proc autotest_dummy_test_with_others_attributes()
begin
  select * from bar;
end;

-- TEST: autotest attribute with dymmy_test info on a single table and column
-- + {stmt_and_attr}
-- + {misc_attrs}: ok
-- + {dot}
-- + {name cql}
-- + {name autotest}
-- + {misc_attr_value_list}
-- + {name dummy_test}: ok
-- + {name bar}: ok
-- + {name id}: ok
-- + {int 1}: ok
-- + {int 2}: ok
-- + {create_proc_stmt}: autotest_dummy_test_without_other_attributes: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[autotest=((dummy_test, (bar, (id), (1), (2))))]]
proc autotest_dummy_test_without_other_attributes()
begin
  select * from bar;
end;

-- TEST: dummy_test info with invalid column value type (value type str is incorrect)
-- + error: % autotest attribute 'dummy_test' has invalid value type in 'id'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name one}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id), (one))))]]
proc autotest_dummy_test_invalid_col_str_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with invalid column value type (value type dbl is incorrect)
-- + error: % autotest attribute 'dummy_test' has invalid value type in 'id'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {dbl 0.1}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=((dummy_test, (bar, (id), (0.1))))]]
proc autotest_dummy_test_invalid_col_dbl_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with int value for a long column
-- + {misc_attrs}: ok
-- + {create_proc_stmt}: autotest_dummy_test_long_col_with_int_value: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[autotest=((dummy_test, (bar, (rate), (1))))]]
proc autotest_dummy_test_long_col_with_int_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with int value for a negative long column
-- + {misc_attrs}: ok
-- + {uminus}
-- + {int 1}
-- + {create_proc_stmt}: autotest_dummy_test_neg_long_col_with_int_value: { id: integer notnull, name: text, rate: longint } dml_proc
-- - error:
[[autotest=((dummy_test, (bar, (rate), (-1))))]]
proc autotest_dummy_test_neg_long_col_with_int_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with invalid column value type (value type strlit is incorrect)
-- + error: % autotest attribute 'dummy_test' has invalid value type in 'id'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {strlit 'bogus'}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id) , ('bogus'))))]]
proc autotest_dummy_test_invalid_col_strlit_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with invalid column value type (value type lng is incorrect)
-- + error: % autotest attribute 'dummy_test' has invalid value type in 'id'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {longint 1}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id), (1L))))]]
proc autotest_dummy_test_invalid_col_lng_value()
begin
  select * from bar;
end;

-- TEST: dummy_test info with column name not nested
-- + error: % autotest attribute has incorrect format (column name should be nested) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, id, (1), (2))))]]
proc autotest_dummy_test_invalid_col_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info with two column value for one column name
-- + error: % autotest attribute has incorrect format (too many column values) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id), (1, 2))))]]
proc autotest_dummy_test_too_many_value_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info with one column value for 2 column name
-- + error: % autotest attribute has incorrect format (mismatch number of column and values) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id, name), (1))))]]
proc autotest_dummy_test_missing_value_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info missing column value for each column name
-- + error: % autotest attribute has incorrect format (column value should be nested) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id, name))))]]
proc autotest_dummy_test_no_value_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info with column value as column name
-- + error: % autotest attribute has incorrect format (table name should be nested) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {misc_attr_value_list}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (1, (id), (1))))]]
proc autotest_bogus_table_name_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info missing column name but has column value
-- + error: % autotest attribute has incorrect format (column name should be nested) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (1), (1))))]]
proc autotest_bogus_colum_name_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info with column value not nested
-- + error: % autotest attribute has incorrect format (column value should be nested) in 'dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (id), 1)))]]
proc autotest_colum_value_incorrect_format()
begin
  select * from bar;
end;

-- TEST: dummy_test info with bogus column name
-- + error: % autotest attribute 'dummy_test' has non existent column 'bogus_col'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bar}: ok
-- + {name bogus_col}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bar, (bogus_col), (1), (2))))]]
proc autotest_dummy_test_bogus_col_name()
begin
  select * from bar;
end;

-- TEST: dummy_test info with bogus table name
-- + error: % autotest attribute 'dummy_test' has non existent table 'bogus_table'
-- + {misc_attrs}: err
-- + {name dummy_test}: err
-- + {name bogus_table}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_test, (bogus_table, (id), (1), (2))))]]
proc autotest_dummy_test_bogus_table_name()
begin
  select * from bar;
end;

-- TEST: autotest attribute with bogus attribute name
-- + error: % autotest attribute name is not valid 'dummy_bogus'
-- + {misc_attrs}: err
-- + {name dummy_bogus}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_bogus)]]
proc autotest_dummy_bogus()
begin
  select * from bar;
end;

-- TEST: autotest attribute with bogus attribute name nested
-- + error: % autotest has incorrect format 'found nested attributes that don't start with dummy_test'
-- + {misc_attrs}: err
-- + {name dummy_table}: ok
-- + {name dummy_bogus}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_table, (dummy_bogus))]]
proc autotest_bogus_nested_attribute()
begin
  select * from bar;
end;

-- TEST: dummy_test info not nested
-- + error: % autotest has incorrect format 'found nested attributes that don't start with dummy_test'
-- + {misc_attrs}: err
-- + {name bar}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=(dummy_test, (bar, (id), (1)))]]
proc autotest_dummy_test_not_nested()
begin
  select * from bar;
end;

-- TEST: autotest attribute not nested.
-- + error: % autotest attribute name is not valid 'bar'
-- + error: % autotest has incorrect format 'found nested attributes that don't start with dummy_test'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +2 error:
[[autotest=(dummy_test, bar, ((id, name),(1, 'x')))]]
proc autotest_dummy_test_not_nested_2()
begin
  select * from bar;
end;

-- TEST: autotest attribute with column names double nested
-- + error: % autotest attribute has incorrect format (table name should be nested) in 'dummy_test'
-- + {stmt_and_attr}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=((dummy_test, ((bar, (id), (1), (2)))))]]
proc autotest_dummy_test_with_col_double_nested()
begin
  select * from bar;
end;

-- TEST: autotest attribute with dummy_table
-- + error: % autotest has incorrect format 'no test types specified'
-- + {misc_attrs}: err
-- + {name dummy_table}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autotest=dummy_table]]
proc autotest_incorrect_formatting()
begin
  select * from bar;
end;

-- some declrations for autodrop tests
create temp table table1( id integer);
create temp table table2( id integer);
create table not_a_temp_table( id integer);

-- TEST: autodrop attribute (correct usage)
-- + {stmt_and_attr}
-- + {misc_attrs}: ok
-- + {dot}
-- + {name cql}
-- + {name autodrop}
-- + {name table1}: ok
-- + {name table2}: ok
-- + {create_proc_stmt}: autodropper: { id: integer } dml_proc
-- + {name autodropper}: autodropper: { id: integer } dml_proc
[[autodrop=(table1, table2)]]
proc autodropper()
begin
  select * from table1;
end;

-- TEST: autodrop attribute: name is not an object
-- + error: % autodrop temp table does not exist 'not_an_object'
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autodrop=(not_an_object)]]
proc autodropper_not_an_objecte()
begin
  select * from table1;
end;

-- TEST: autodrop attribute: name is a view
-- + error: % autodrop target is not a table 'ViewShape'
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autodrop=(ViewShape)]]
proc autodropper_dropping_view()
begin
  select * from table1;
end;

-- TEST: autodrop attribute: name is not a temp table
-- + error: % autodrop target must be a temporary table 'not_a_temp_table'
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autodrop=(not_a_temp_table)]]
proc autodropper_not_temp_table()
begin
  select * from table1;
end;

-- TEST: autodrop attribute: proc doesn't select anything
-- + error: % autodrop annotation can only go on a procedure that returns a result set 'autodrop_not_really_a_result_set_proc'
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autodrop=(table1, table2)]]
proc autodrop_not_really_a_result_set_proc()
begin
  declare i integer;
end;

-- TEST: autodrop attribute: proc doesn't use the database
-- + error: % autodrop annotation can only go on a procedure that uses the database 'autodrop_no_db'
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[autodrop=(table1, table2)]]
procedure autodrop_no_db()
begin
  cursor C like select 1 id;
  fetch c (id) from values (1);
  out c;
end;

-- TEST: table to test referenceable (primary key, unique key) column
-- + {create_table_stmt}: referenceable: { a: integer notnull primary_key, b: real unique_key, c: text, d: text, e: longint }
-- - error:
create table referenceable (
  a int primary key,
  b real unique,
  c text,
  d text,
  e long int
);

-- TEST: table to test referenceable group of columns
-- + {create_table_stmt}: referenceable_2: { a: integer notnull partial_pk, b: real notnull partial_pk }
-- - error:
create table referenceable_2 (
  a int,
  b real,
  primary key (a, b)
);

-- TEST: index to test referenceable (unique index key) column
-- - error:
create unique index referenceable_index on referenceable(c, d);

-- TEST: test foreign key on a primary key
-- +1 {create_table_stmt}: reference_pk: { id: integer foreign_key }
-- +1 {fk_def}: ok
-- - error:
create table reference_pk(
  id int,
  foreign key (id) references referenceable(a)
);

-- TEST: test foreign key on a group of primary key
-- +1 {create_table_stmt}: reference_2_pk: { id: integer foreign_key, size: real foreign_key }
-- +1 {fk_def}: ok
-- - error:
create table reference_2_pk(
  id int,
  size real,
  foreign key (id, size) references referenceable_2(a, b)
);

-- TEST: test foreign key on a group of primary key in the wrong order
-- +1 {create_table_stmt}: reference_2_wrong_order_pk: { id: integer foreign_key, size: real foreign_key }
-- +1 {fk_def}: ok
-- - error:
create table reference_2_wrong_order_pk(
  id int,
  size real,
  foreign key (size, id) references referenceable_2(b, a)
);

-- TEST: test foreign key on a unique key
-- +1 {create_table_stmt}: reference_uk: { id: real foreign_key }
-- +1 {fk_def}: ok
-- - error:
create table reference_uk(
  id real,
  foreign key (id) references referenceable(b)
);

-- TEST: test foreign key on a mixed of primary and unique key
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'referenceable'
-- +1 error:
create table reference_pk_and_uk(
  id1 int,
  id2 real,
  foreign key (id1, id2) references referenceable(a, b)
);

-- TEST: test foreign key on a unique key
-- +1 {create_table_stmt}: referenceable_unique_index: { id: text foreign_key, label: text foreign_key }
-- +1 {fk_def}: ok
-- - error:
create table referenceable_unique_index(
  id text,
  label text,
  foreign key (id, label) references referenceable(c, d)
);

-- TEST: test foreign key on a mixed of a primary and unique index
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'referenceable'
-- +1 error:
create table reference_pk_and_unique_index(
  id1 int,
  id2 text,
  foreign key (id1, id2) references referenceable(a, c)
);

-- TEST: test foreign key on a mixed of a unique key and unique index
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'referenceable'
-- +1 error:
create table reference_uk_and_unique_index(
  id1 real,
  id2 text,
  id3 text,
  foreign key (id1, id2, id3) references referenceable(b, c, d)
);

-- TEST: test foreign key on a single non referenceable column
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'referenceable'
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error:
create table reference_not_referenceable_column(
  id long int primary key,
  foreign key (id) references referenceable(e)
);

-- TEST: test foreign key on multiple non referenceable columns
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error:
create table reference_not_referenceable_columns(
  id1 text primary key,
  id2 text,
  id3 text,
  foreign key (id1, id2, id3) references referenceable(c, d, e)
);

-- TEST: test foreign key on a subset of unique index
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table
-- +1 {create_table_stmt}: err
-- +1 {fk_def}: err
-- +1 error:
create table reference_not_referenceable_column(
  id text,
  foreign key (id) references referenceable(c)
);

-- TEST: validate enforcement parse and analysis (fk on update)
-- + @ENFORCE_STRICT FOREIGN KEY ON UPDATE
-- + {enforce_strict_stmt}: ok
-- + {int 1}
@enforce_strict foreign key on update;

-- TEST: validate enforcement parse and analysis (fk on delete)
-- + @ENFORCE_STRICT FOREIGN KEY ON DELETE;
-- + {enforce_strict_stmt}: ok
-- + {int 2}
@enforce_strict foreign key on delete;

-- TEST: validate enforcement parse and analysis (fk on update)
-- + @ENFORCE_NORMAL FOREIGN KEY ON UPDATE
-- + {enforce_normal_stmt}: ok
-- + {int 1}
@enforce_normal foreign key on update;

-- TEST: validate enforcement parse and analysis (fk on delete)
-- + @ENFORCE_NORMAL FOREIGN KEY ON DELETE;
-- + {enforce_normal_stmt}: ok
-- + {int 2}
@enforce_normal foreign key on delete;

-- switch back to strict mode for the validation tests
@enforce_strict foreign key on update;
@enforce_strict foreign key on delete;

-- TEST: strict validation ok
-- + id INT REFERENCES foo (id) ON UPDATE CASCADE ON DELETE CASCADE
-- + {create_table_stmt}: fk_strict_ok: { id: integer foreign_key }
-- + {col_attrs_fk}: ok
-- - error:
create table fk_strict_ok (
  id integer REFERENCES foo(id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- TEST: strict failure ON UPDATE missing
-- + error: % strict FK validation requires that some ON UPDATE option be selected for every foreign key
-- + {create_table_stmt}: err
-- + {col_def}: err
-- + {col_attrs_fk}: err
-- +1 error:
create table fk_strict_failure_update(
  id integer REFERENCES foo(id)
);

-- TEST: strict failure ON DELETE missing
-- + id INT REFERENCES foo (id) ON UPDATE NO ACTION
-- + error: % strict FK validation requires that some ON DELETE option be selected for every foreign key
-- + {create_table_stmt}: err
-- + {col_def}: err
-- + {col_attrs_fk}: err
-- +1 error:
CREATE TABLE fk_strict_failure_delete(
  id INT REFERENCES foo (id) ON UPDATE NO ACTION
);

-- TEST: strict failure ON DELETE missing (loose FK)
-- + error: % strict FK validation requires that some ON DELETE option be selected for every foreign key
-- + {create_table_stmt}: err
-- + {fk_def}: err
-- +1 error:
CREATE TABLE fk_strict_failure_delete_loose(
  id INT,
  FOREIGN KEY (id) REFERENCES foo(id) ON UPDATE NO ACTION
);

-- TEST: strict failure ON UPDATE missing (loose FK)
-- + error: % strict FK validation requires that some ON UPDATE option be selected for every foreign key
-- + {create_table_stmt}: err
-- + {fk_def}: err
-- +1 error:
CREATE TABLE fk_strict_failure_update_loose(
  id INT,
  FOREIGN KEY (id) REFERENCES foo(id)
);

-- TEST: strict success with loose fk
-- + {create_table_stmt}: fk_strict_success_loose: { id: integer foreign_key }
-- + {fk_def}: ok
-- - error:
CREATE TABLE fk_strict_success_loose(
  id INT,
  FOREIGN KEY (id) REFERENCES foo(id) ON DELETE NO ACTION ON UPDATE CASCADE
);

-- TEST: create proc with an invalid column name in the identity attribute
-- + error: % procedure identity column does not exist in result set 'col3'
-- +1 error:
[[identity=(col1, col3)]]
proc invalid_identity()
begin
  select 1 as col1, 2 as col2, 3 as data;
end;

-- TEST: create proc with an identity attribute but it has no result
-- + error: % identity annotation can only go on a procedure that returns a result set 'no_result_set_identity'
-- +1 error:
[[identity=(col1, col3)]]
proc no_result_set_identity()
begin
  declare x integer;  /* no op */
end;

-- TEST: declare a valid root region
-- + {declare_schema_region_stmt}: root_region: region
-- + {name root_region}
-- - error:
@declare_schema_region root_region;

-- TEST: declare a valid region with dependencies
-- + {declare_schema_region_stmt}: dep_region: region
-- + {name dep_region}
-- + {name root_region}
-- - error:
@declare_schema_region dep_region using root_region;

-- TEST: try to redefine a region
-- + error: % schema region already defined 'root_region'
-- + {declare_schema_region_stmt}: err
-- +1 error:
@declare_schema_region root_region;

-- TEST: try to use a region that doesn't exist
-- + error: % unknown schema region 'unknown_region'
-- + {declare_schema_region_stmt}: err
-- +1 error:
@declare_schema_region root_region using unknown_region;

-- TEST: try to use the same region twice
-- + error: % duplicate name in list 'root_region'
-- + {declare_schema_region_stmt}: err
-- +1 error:
@declare_schema_region root_region using root_region, root_region;

-- TEST: enter a schema region
-- + {begin_schema_region_stmt}: ok
-- + | {name root_region}
-- - error:
@begin_schema_region root_region;

-- TEST: enter a schema region while there is already one active
-- + error: % schema regions do not nest; end the current region before starting a new one
-- + {begin_schema_region_stmt}: err
-- +1 error:
@begin_schema_region root_region;

-- TEST: exit a schema region
-- + {end_schema_region_stmt}: ok
-- - error:
@end_schema_region;

-- add some more regions to create a diamond shape (two ways to get to root)
@declare_schema_region dep2_region USING root_region;
@declare_schema_region diamond_region USING dep_region, dep2_region;

-- TEST: exit a schema region when there is no region active
-- + error: % you must begin a schema region before you can end one
-- + {end_schema_region_stmt}: err
-- +1 error:
@end_schema_region;

-- TEST: try to enter a schema region that is not known
-- + error: % unknown schema region 'what_is_this_region'
-- + {begin_schema_region_stmt}: err
-- +1 error:
@begin_schema_region what_is_this_region;

-- TEST: try to use schema region declaration inside of a procedure
-- + error: % schema region directives may not appear inside of a procedure
-- + {create_proc_stmt}: err
-- + {declare_schema_region_stmt}: err
-- +1 error:
proc decl_region_in_proc()
begin
  @declare_schema_region fooey;
end;

-- TEST: try to use begin schema region inside of a procedure
-- + error: % schema region directives may not appear inside of a procedure
-- + {create_proc_stmt}: err
-- + {begin_schema_region_stmt}: err
-- +1 error:
proc begin_region_in_proc()
begin
  @begin_schema_region fooey;
end;

-- TEST: try to use end schema region inside of a procedure
-- + error: % schema region directives may not appear inside of a procedure
-- + {create_proc_stmt}: err
-- + {end_schema_region_stmt}: err
-- +1 error:
proc end_region_in_proc()
begin
  @end_schema_region;
end;

-- TEST: division of reals is ok (promotes to real)
-- + {assign}: my_real: real variable
-- + {div}: real notnull
-- - error:
set my_real := 1.3 / 2;

-- TEST: modulus of reals is NOT ok (this makes no sense)
-- + error: % operands must be an integer type, not real '%'
-- + {mod}: err
-- +1 error:
set X := 1.3 % 2;

-- TEST: make sure || aborts if one of the args is already an error
-- + error: % string operand not allowed in 'NOT'
-- + {select_stmt}: err
-- + {concat}: err
-- +1 error:
select (NOT 'x') || 'plugh';

@begin_schema_region root_region;
create table a_table_in_root_region(id integer);
create trigger a_trigger_in_root_region
  before delete on a_table_in_root_region
  begin
    delete from a_table_in_root_region where id > 3;
  end;
create index a_index_in_root_region on a_table_in_root_region(id);
@end_schema_region;

@begin_schema_region dep_region;
create table a_table_in_dep_region(id integer);

-- TEST: create a legal view using tables from two regions
-- + {create_view_stmt}: a_view_in_dep_region: { id1: integer, id2: integer }
-- - error:
create view a_view_in_dep_region as
  select T1.id as id1, T2.id as id2
  from a_table_in_root_region T1
  inner join a_table_in_dep_region T2
  using(id);

-- TEST: try to drop a non-region trigger from dep_region
-- + error: % trigger in drop statement was not declared (while in schema region 'dep_region', accessing an object that isn't in a region is invalid) 'trigger2'
-- + {drop_trigger_stmt}: err
-- + {name trigger2}
-- +1 error:
drop trigger trigger2;

-- TEST: try to drop a non-region view from dep_region
-- + error: % view in drop statement does not exist (while in schema region 'dep_region', accessing an object that isn't in a region is invalid) 'MyView'
-- + {drop_view_stmt}: err
-- +1 error:
drop view MyView;

-- TEST: try to drop a non-region table from dep_region
-- + error: % table in drop statement does not exist (while in schema region 'dep_region', accessing an object that isn't in a region is invalid) 'foo'
-- + {drop_table_stmt}: err
-- +1 error:
drop table foo;

-- TEST: try to drop a non-region index from dep_region
-- + error: % index in drop statement was not declared (while in schema region 'dep_region', accessing an object that isn't in a region is invalid) 'index_1'
-- + {drop_index_stmt}: err
-- +1 error:
drop index index_1;

-- TEST: create a table like non-region table from dep_region
-- + {create_table_stmt}: a_table_like_table_in_dep_region: { id: integer notnull }
-- - error:
create table a_table_like_table_in_dep_region (like foo);

-- TEST: create a table like view in dep_region from dep_region
-- + {create_table_stmt}: a_table_like_table_in_dep_region_2: { id1: integer, id2: integer }
-- - error:
create table a_table_like_table_in_dep_region_2 (like a_view_in_dep_region);

-- TEST: create a table like a non-region view from dep_region
-- + {create_table_stmt}: a_table_like_view_in_dep_region: { f1: integer notnull, f2: integer notnull, f3: integer notnull }
-- - error:
create table a_table_like_view_in_dep_region (like MyView);

-- TEST: create a table like a non-region proc from dep_region
-- + {create_table_stmt}: a_table_like_proc_in_dep_region: { id: integer notnull, name: text, rate: longint }
-- - error:
create table a_table_like_proc_in_dep_region (like with_result_set);

@end_schema_region;

-- entering a different region now, it partly overlaps
@begin_schema_region dep2_region;

-- TEST: create a legal view using tables from root region
-- + {create_view_stmt}: ok_view_in_dep2_region: { id: integer }
-- - error:
create view ok_view_in_dep2_region as select * from a_table_in_root_region;

-- TEST: try to access objects in dep_region
-- + error: % table/view not defined (object is in schema region 'dep_region' not accessible from region 'dep2_region') 'a_table_in_dep_region'
-- + {create_view_stmt}: err
-- +1 error:
create view bogus_view_in_dep2_region as
  select T1.id as id1, T2.id as id2
  from a_table_in_root_region T1
  inner join a_table_in_dep_region T2
  using(id);

-- TEST: try to use a non-region object while in a region
-- + error: % table/view not defined (while in schema region 'dep2_region', accessing an object that isn't in a region is invalid) 'bar'
-- + {create_view_stmt}: err
-- +1 error:
create view bogus_due_to_non_region_object as select * from bar;

@end_schema_region;

-- TEST: enter a schema region that has diamond shaped dependencies
-- + {begin_schema_region_stmt}: ok
-- + {name diamond_region}
-- - error:
@begin_schema_region diamond_region;

-- TEST: drop a dep_region table from diamond_region
-- + {drop_table_stmt}: ok
-- - error:
drop table a_table_like_proc_in_dep_region;

-- TEST: drop a root_region table from diamond_region
-- + {drop_table_stmt}: ok
-- - error:
drop table a_table_in_root_region;

-- TEST: drop a dep_region view from diamond_region
-- + {drop_view_stmt}: ok
-- - error:
drop view a_view_in_dep_region;

-- TEST: drop a root_region trigger from diamond_region
-- + {drop_trigger_stmt}: ok
-- - error:
drop trigger a_trigger_in_root_region;

-- TEST: drop a root_region index from diamond_region
-- + {drop_index_stmt}: ok
-- - error:
drop index a_index_in_root_region;

-- TEST: creating a table for use later, we'll try to create an index on the wrong group
-- - error:
create table diamond_region_table(id integer) @recreate(d_group);

@end_schema_region;

-- TEST: try to create an index on the diamond group table from not in the same region
--       it's a recreate table so that's not allowed
-- + error: % if a table is marked @recreate, its indices must be in its schema region 'invalid_wrong_group_index'
-- + {create_index_stmt}: err
-- +1 error:
create index invalid_wrong_group_index on diamond_region_table(id);

-- TEST: try to use a WITH_SELECT form in a select expression
-- + {assign}: X: integer variable
-- + {with_select_stmt}: _anon: integer notnull
-- - error:
SET x := (WITH threads2 (count) AS (SELECT 1 foo) SELECT COUNT(*) FROM threads2);

-- TEST: declare a table valued function
-- + {declare_select_func_stmt}: _select_: { foo: text } select_func
-- + {name tvf}: _select_: { foo: text }
-- - error:
declare select function tvf(id integer) (foo text);

-- TEST: table valued functions may not appear in an expression context
-- + error: % table valued functions may not be used in an expression context 'tvf'
-- + {select_stmt}: err
-- +1 error:
select 1 where tvf(5) = 1;

-- TEST: use a table valued function, test expansion of from clause too
-- + FROM tvf(LOCALS.v);
-- + {create_proc_stmt}: using_tvf: { foo: text } dml_proc
-- + {select_stmt}: _select_: { foo: text }
-- rewrite to use locals
-- - error:
proc using_tvf()
begin
  let v := 1;
  select * from tvf(from locals);
end;

-- TEST: expand using 'from' bogus source of args
-- + error: % name not found 'does_not_exist'
-- + {create_proc_stmt}: err
-- + {arg_list}: err
-- +1 error:
proc using_tvf_error()
begin
  let v := 1;
  select * from tvf(from does_not_exist);
end;

-- TEST: use a table valued function but with a arg error
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'tvf' argument #1 intended for parameter 'id' has the problem
-- + {select_stmt}: err
-- + {table_function}: err
-- +2 error:
proc using_tvf_invalid_arg()
begin
  select * from tvf(NOT 'x');
end;

-- TEST: use a table valued function but with a bogus arg type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + error: % additional info: calling 'tvf' argument #1 intended for parameter 'id' has the problem
-- + {select_stmt}: err
-- + {table_function}: err
-- +2 error:
proc using_tvf_arg_mismatch()
begin
  select * from tvf('x');
end;

-- TEST: use a table valued function
-- + {create_proc_stmt}: using_tvf_unaliased: { foo: text } dml_proc
-- + {select_stmt}: _select_: { foo: text }
-- + {dot}: foo: text
-- - error:
proc using_tvf_unaliased()
begin
  select * from tvf(1) where tvf.foo = 'x';
end;

-- TEST: use a table valued function aliased
-- + {create_proc_stmt}: using_tvf_aliased: { foo: text } dml_proc
-- + {select_stmt}: _select_: { foo: text }
-- + {dot}: foo: text
-- - error:
proc using_tvf_aliased()
begin
  select * from tvf(1) T1 where T1.foo = 'x';
end;

-- TEST: use a non-table-valued function in FROM
-- + error: % function is not a table-valued-function 'SqlUserFunc'
-- + {select_stmt}: err
-- + {table_function}: err
-- +1 error:
proc using_not_a_tvf()
begin
  select * from SqlUserFunc(1);
end;

-- TEST: use a invalid symbol in FROM
-- + error: % table-valued function not declared 'ThisDoesNotExist'
-- + {select_stmt}: err
-- + {table_function}: err
-- +1 error:
proc using_not_a_func()
begin
  select * from ThisDoesNotExist(1);
end;

-- TEST: declare table valued function that consumes an object
-- + {declare_select_func_stmt}: _select_: { id: integer } select_func
-- + {params}: ok
-- + {param}: rowset: object<rowset> variable in
-- - error:
declare select function ReadFromRowset(rowset Object<rowset>) (id integer);

-- TEST: use a table valued function that consumes an object
-- + {create_proc_stmt}: rowset_object_reader: { id: integer } dml_proc
-- + {table_function}: TABLE { ReadFromRowset: _select_ }
-- + {name ReadFromRowset}: TABLE { ReadFromRowset: _select_ }
-- + {name rowset}: rowset: object<rowset> variable in
-- - error:
proc rowset_object_reader(rowset Object<rowset>)
begin
  select * from ReadFromRowset(rowset);
end;

-- TEST: convert pointer to long for binding
-- + {assign}: ll: longint notnull variable
-- + {name ptr}: longint notnull
-- - error:
set ll := (select ptr(obj_var));

-- TEST: convert pointer to long for binding -- failure case
-- + error: % string operand not allowed in 'NOT'
-- + {assign}: err
-- + {arg_list}: err
-- +1 error:
set ll := (select ptr(not 'x'));

-- TEST: try to use 'ptr' outside of sql context
-- + error: % function may not appear in this context 'ptr'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set ll := ptr(obj_var);

-- TEST: try to use 'ptr' with wrong arg count
-- + error: % function got incorrect number of arguments 'ptr'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set ll := ptr(obj_var, 1);

-- TEST: try to alias a column with a local variable of the same name
-- + error: % a variable name might be ambiguous with a column name, this is an anti-pattern 'id'
-- + {assign}: err
-- + {select_stmt}: err
-- +1 error:
proc variable_conflict()
begin
  declare id integer;
  set id := (select id from foo);
end;

-- TEST: try to alias rowid with a local variable of the same name
-- + error: % a variable name might be ambiguous with a column name, this is an anti-pattern 'rowid'
-- + {assign}: err
-- + {select_stmt}: err
-- +1 error:
proc variable_conflict_rowid()
begin
  declare rowid integer;
  set rowid := (select rowid from foo);
end;

-- TEST: group concat has to preserve sensitivity
-- + {select_stmt}: _select_: { gc: text sensitive }
-- - error:
select group_concat(name) gc from with_sensitive;

-- TEST: group concat must always return nullable
-- + {select_stmt}: _select_: { gc: text }
-- + {strlit 'not-null'}: text notnull
-- - error:
select group_concat('not-null') gc from foo;

-- TEST: min/max (same code) only accept numerics and strings
-- + error: % argument 1 'blob' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' 'text' in 'min'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- +1 error:
proc min_gets_blob(a_blob blob)
begin
  select min(a_blob) from foo;
end;

-- TEST: non aggregate version basic test
-- this version of min is still allowed to return not null, it isn't an aggregate
-- it also doesn't need a from clause
-- + {select_expr_list_con}: _select_: { min_stuff: real notnull }
-- - error:
set my_real := (select min(1.2, 2, 3) as min_stuff);

-- TEST: create a sum using a bool
-- + {select_stmt}: _select_: { _anon: integer }
-- + {and}: bool notnull
-- - error:
select sum(1 and 1) from foo;

-- TEST: create a sum using a long integer
-- + {select_stmt}: _select_: { _anon: longint }
-- - error:
select sum(1L) from foo;

-- TEST: create a sum using a real
-- + {select_stmt}: _select_: { _anon: real }
-- - error:
select sum(1.2) from foo;

-- TEST: try to do a min with incompatible arguments (non aggregate form)
-- + error: % required 'INT' not compatible with found 'TEXT' context 'min'
-- + {select_stmt}: err
-- +1 error:
select min(1, 'x');

-- TEST: try to do a min with non-numeric arguments (first position) (non aggregate form)
-- + error: % argument 1 is a NULL literal; useless in 'min'
-- + {select_stmt}: err
-- +1 error:
select min(NULL, 'x');

-- TEST: try to do a min with non-numeric arguments (not first position) (non aggregate form)
-- + error: % argument 2 is a NULL literal; useless in 'min'
-- + {select_stmt}: err
-- +1 error:
select min('x', NULL, 'y');

-- TEST: min on strings
-- + {select_stmt}: _select_: { _anon: text notnull }
-- - error:
select min('x', 'y');

-- TEST: min on numerics (upgraded to real in this case)
-- + {select_stmt}: _select_: { _anon: real notnull }
-- - error:
select min(1, 1.2);

-- TEST: min on numerics (checks sensitivy and nullable)
-- + {select_stmt}: _select_: { _anon: longint sensitive }
-- - error:
select min(_sens, 1L);

-- TEST: create a non-recreate table that references a recreated table
-- + create_table_stmt}: err
-- + col_attrs_fk}: err
-- +1 error: % referenced table can be independently recreated so it cannot be used in a foreign key 'recreatable'
-- +1 error:
create table recreatable_reference_1(
  id integer primary key references recreatable(id),
  name text
);

-- TEST: create a recreate table that references a recreated table
-- + {create_table_stmt}: recreatable_reference_2: { id: integer notnull primary_key foreign_key, name: text } @recreate
-- - error:
create table recreatable_reference_2(
  id integer primary key references recreatable(id) on update cascade on delete cascade,
  name text
) @recreate;

-- TEST: make a recreate table, put it in a group "rtest"
-- + {create_table_stmt}: in_group_test: { id: integer notnull primary_key, name: text } @recreate(rtest)
-- + {recreate_attr}
-- + {name rtest}
-- - error:
create table in_group_test(
  id integer primary key,
  name text
) @recreate(rtest);

-- TEST: create a recreate table that references a recreated table, it's in a group, but I'm not
-- + {create_table_stmt}: recreatable_reference_3: { id: integer notnull primary_key foreign_key, name: text } @recreate
-- - error:
create table recreatable_reference_3(
  id integer primary key references in_group_test(id) on update cascade on delete cascade,
  name text
) @recreate;

-- TEST: create a recreate table that references two recreated tables in different groups than me
-- + {create_table_stmt}: recreatable_reference_4: { id: integer notnull primary_key foreign_key, id2: integer foreign_key, name: text } @recreate(rtest_other_group)
-- + {recreate_attr}
-- + {name rtest_other_group}
-- - error:
create table recreatable_reference_4(
  id integer primary key references in_group_test(id) on update cascade on delete cascade,
  id2 integer references recreatable_reference_3(id) on update cascade on delete cascade,
  name text
) @recreate(rtest_other_group);

-- TEST: create a recreate table that references a recreated table, it's in the same group so this one is ok
-- + {create_table_stmt}: recreatable_reference_5: { id: integer notnull primary_key foreign_key, name: text } @recreate(rtest)
-- + {recreate_attr}
-- + {name rtest}
-- + {col_attrs_fk}: ok
-- + {name in_group_test}
-- - error:
create table recreatable_reference_5(
  id integer primary key references in_group_test(id) on delete cascade on update cascade,
  name text
) @recreate(rtest);

-- TEST: create a recreate table that introduces a cyclic dependency between recreate groups
-- + create_table_stmt}: err
-- + col_attrs_fk}: err
-- +1 error: % referenced table can be independently recreated so it cannot be used in a foreign key 'recreatable_reference_4'
-- +1 error:
create table recreatable_reference_6(
  id integer primary key references recreatable_reference_4(id) on update cascade on delete cascade,
  name text
) @recreate(rtest);

-- TEST: once we have found one error in the constraint section it's not safe to proceed to look for more
--       errors because the semantic type of the node has already been changed to "error"
--       so we have to early out.  To prove this is happening we force an error in the PK section here
--       this error will not be reported becuase we bail before that.
-- + error: % foreign key refers to non-existent table 'table_not_found'
-- + {create_table_stmt}: err
-- + {pk_def}
-- - {pk_def}: err
-- +1 error:
CREATE TABLE early_out_on_errs(
  result_index INT!,
  query TEXT!,
  FOREIGN KEY (query) REFERENCES table_not_found(q),
  PRIMARY KEY (garbonzo)
) @RECREATE;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_table_stmt}: err
-- +1 error:
proc invalid_ddl_1()
begin
  create table inv_1(
    id integer
  ) @recreate(xyx);
end;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_table_stmt}: err
-- +1 error:
proc invalid_ddl_2()
begin
  create table inv2(
    id integer
  ) @create(1);
end;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_table_stmt}: err
-- +1 error:
proc invalid_ddl_3()
begin
  create table inv3(
    id integer
  ) @delete(2);
end;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_index_stmt}: err
-- +1 error:
proc invalid_ddl_4()
begin
  create index inv_4 on bar(x) @delete(2);
end;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_view_stmt}: err
-- +1 error:
proc invalid_ddl_5()
begin
 create view inv_5 as select 1 as f1 @delete(2);
end;

-- TEST: attributes not allowed inside of a procedure
-- + error: % versioning attributes may not be used on DDL inside a procedure
-- + {create_trigger_stmt}: err
-- +1 error:
proc invalid_ddl_6()
begin
  create trigger if not exists trigger2
    after insert on bar
  begin
    delete from bar where rate > new.id;
  end @delete(2);
end;

-- TEST: enable strict join mode
-- + {enforce_strict_stmt}: ok
-- + {int 3}
-- - error:
@enforce_strict join;

-- TEST: non-ansi join is used... error in strict mode
-- + error: % non-ANSI joins are forbidden if strict join mode is enabled
-- + {select_stmt}: err
-- +1 error:
select * from foo, bar;

-- TEST: try to use an out cursor like a statement cursor, not valid
-- + error: % use FETCH FROM for procedures that returns a cursor with OUT 'C'
-- + {create_proc_stmt}: err
-- + {declare_cursor}: err
-- +1 error:
proc bar()
begin
  cursor C for call out_cursor_proc();
end;

-- TEST: can't use offset without limit
-- + error: % OFFSET clause may only be used if LIMIT is also present
-- + {select_stmt}: err
-- + {opt_offset}: err
-- +1 error:
select * from foo offset 1;

-- TEST: upsert with insert/select and do nothing statement
-- + {create_proc_stmt}: ok dml_proc
-- + {name upsert_do_nothing}: ok dml_proc
-- + {upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {upsert_update}: ok
-- + {conflict_target}: foo: { id: integer notnull }
-- - error:
proc upsert_do_nothing()
begin
  insert into foo select id from bar where 1 on conflict(id) do nothing;
end;

-- TEST: with upsert with insert/select and do nothing statement
-- + {create_proc_stmt}: ok dml_proc
-- + {name with_upsert_do_nothing}: ok dml_proc
-- + {with_upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {upsert_update}: ok
-- + {conflict_target}: foo: { id: integer notnull }
-- - error:
proc with_upsert_do_nothing()
begin
  with data(id) as (values (1), (2), (3))
  insert into foo select id from data where 1 on conflict(id) do nothing;
end;

-- TEST: with upsert with error in the CTE
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {with_upsert_stmt}: err
-- +1 error:
proc with_upsert_cte_err()
begin
  with data(id) as (values (not 'x'))
  insert into foo select id from data where 1 on conflict(id) do nothing;
end;

-- TEST: with upsert with error in the insert
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {with_upsert_stmt}: err
-- +1 error:
proc with_upsert_insert_err()
begin
  with data(id) as (values (1))
  insert into foo select id from data where not 'x' on conflict(id) do nothing;
end;

-- TEST: upsert with insert and do nothing statement
-- + {create_proc_stmt}: ok dml_proc
-- + {name upsert_without_conflict_target}: ok dml_proc
-- + {upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {upsert_update}: ok
-- + {conflict_target}: foo: { id: integer notnull }
-- - error:
proc upsert_without_conflict_target()
begin
  insert into foo(id) values (1) on conflict do nothing;
end;

-- TEST: upsert or update statement
-- + {create_proc_stmt}: ok dml_proc
-- + {name upsert_update}: ok dml_proc
-- + {upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {upsert_update}: ok
-- + {conflict_target}: foo: { id: integer notnull }
-- + {update_stmt}: foo: { id: integer notnull primary_key autoinc }
-- + {opt_where}: bool notnull
-- - error:
proc upsert_update()
begin
  insert into foo(id) values (1) on conflict(id) where id=10 do update set id=id+1 where id=20;
end;

-- TEST: upsert with conflict on unknown column
-- + error: % name not found 'bogus'
-- + {create_proc_stmt}: err
-- + {upsert_stmt}: err
-- + {conflict_target}: err
-- +1 error:
proc upsert_conflict_on_unknown_column()
begin
  insert into foo(id) values (1) on conflict(id, bogus) do nothing;
end;

-- TEST: upsert with table name added to update statement
-- + error: % upsert statement does not include table name in the update statement 'foo'
-- + {create_proc_stmt}: err
-- + {upsert_stmt}: err
-- + {update_stmt}: err
-- +1 error:
proc upsert_invalid_update_stmt()
begin
  insert into foo(id) values (1) on conflict(id) do update foo set id = 0;
end;

-- TEST: upsert with select statement without WHERE
-- + error: % upsert statement requires a where clause if the insert clause uses select
-- + {create_proc_stmt}: err
-- + {upsert_stmt}: err
-- + {insert_stmt}: err
-- +1 error:
proc upsert_no_where_stmt()
begin
  insert into foo select id from (select * from bar) on conflict(id) do nothing;
end;

-- TEST: upsert with a not normal insert statement
-- + error: % upsert syntax only supports INSERT INTO 'foo'
-- + {create_proc_stmt}: err
-- + {name upsert_or_ignore}: err
-- + {upsert_stmt}: err
-- + {insert_stmt}: err
-- +1 error:
proc upsert_or_ignore()
begin
  insert or ignore into foo select id from bar where 1 on conflict(id) do nothing;
end;

-- TEST: upsert with bogus column where statement
-- + error: % name not found 'bogus'
-- + {create_proc_stmt}: err
-- + {name upsert_with_bogus_where_stmt}: err
-- + {upsert_stmt}: err
-- + {insert_stmt}: ok
-- + {upsert_update}: err
-- + {conflict_target}: err
-- + {name bogus}: err
-- +1 error:
proc upsert_with_bogus_where_stmt()
begin
  insert into foo(id) values (1) on conflict(id) where bogus=1 do nothing;
end;

-- TEST: update statement without table name
-- + error: % update statement requires a table name
-- + {create_proc_stmt}: err
-- + {name update_without_table_name}: err
-- + {create_trigger_stmt}: err
-- + {update_stmt}: err
-- +1 error:
proc update_without_table_name()
begin
  create temp trigger update_without_table_name_trigger
    before delete on bar
  begin
    update set id=1 where id=9;
  end;
end;

-- TEST: upsert statement. The unique column in conflict target is not a unique key
-- + error: % columns referenced in an UPSERT conflict target must exactly match a unique key the target table
-- + {create_proc_stmt}: err
-- + {name upsert_conflict_target_column_not_unique_key}: err
-- + {upsert_stmt}: err
-- + {conflict_target}: err
-- +1 error:
proc upsert_conflict_target_column_not_unique_key()
begin
  insert into bar(id) values (1) on conflict(name) do nothing;
end;

-- TEST: upsert statement. The set of columns in conflict target do match unique key
-- + {create_proc_stmt}: ok dml_proc
-- + {name upsert_conflict_target_columns_valid}: ok dml_proc
-- + {upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {upsert_update}: ok
-- + {conflict_target}: simple_ak_table_2: { a: integer notnull, b: text, c: real, d: longint }
-- - error:
proc upsert_conflict_target_columns_valid()
begin
  insert into simple_ak_table_2(a, b, c, d) values (1, "t", 1.7, 1) on conflict(a, b) do nothing;
end;

-- TEST: enforce strict upsert statement
-- + @ENFORCE_STRICT UPSERT STATEMENT;
-- + {enforce_strict_stmt}: ok
-- + {int 4}
-- - error:
@enforce_strict upsert statement;

-- TEST: upsert statement failed validation in strict mode
-- + error: % upsert statement are forbidden if strict upsert statement mode is enabled
-- + {upsert_stmt}: err
-- +1 error:
insert into bar(id) values (1) on conflict do nothing;

-- TEST: enforcement normal upsert statement
-- + @ENFORCE_NORMAL UPSERT STATEMENT;
-- + {enforce_normal_stmt}: ok
-- + {int 4}
@enforce_normal upsert statement;

-- TEST: upsert statement succeed validation in normal mode
-- + {upsert_stmt}: ok
-- - error:
insert into bar(id) values (1) on conflict do nothing;

-- TEST: enforce strict window function
-- + @ENFORCE_STRICT WINDOW FUNCTION;
-- + {enforce_strict_stmt}: ok
-- + {int 5}
-- - error:
@enforce_strict window function;

-- TEST: window function invocaction failed validation in strict mode
-- + error: % window function invocation are forbidden if strict window function mode is enabled
-- + {window_func_inv}: err
-- +1 error:
select id, rank() over () from foo;

-- TEST: enforcement normal window function
-- + @ENFORCE_NORMAL WINDOW FUNCTION;
-- + {enforce_normal_stmt}: ok
-- + {int 5}
@enforce_normal window function;

-- TEST: window function invocation succeed validation in normal mode
-- + {window_func_inv}: integer notnull
-- - error:
select id, rank() over () from foo;

-- TEST: min/max may not appear outside of a SQL statement
-- (there is no codegen support for this, though it could be added)
-- the code path for min an max is identical so one test suffices
-- + error: % function may not appear in this context 'max'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set X := max(1,2);

-- TEST: substr is rewritten to the SQL context
-- + LET substr_dummy := ( SELECT substr('x', 1, 2) IF NOTHING THEN THROW );
-- + {call}: text notnull
-- + {name substr}: text notnull
-- - error:
let substr_dummy := substr('x', 1, 2);

-- TEST: simple success -- substr not nullable string
-- + {create_proc_stmt}: substr_test_notnull: { t: text notnull } dml_proc
-- + {name substring}: text notnull
-- - error:
proc substr_test_notnull(t text not null)
begin
  select substring(t, 1, 2) as t ;
end;

-- TEST: simple success -- substr not nullable string one arg
-- + {create_proc_stmt}: substr_test_onearg: { t: text notnull } dml_proc
-- + {name substr}: text notnull
-- - error:
proc substr_test_onearg(t text not null)
begin
  select substr(t, 1) as t ;
end;

-- TEST: simple success -- substr nullable string
-- + {create_proc_stmt}: substr_test_nullable_string: { t: text } dml_proc
-- + {name substr}: text
-- - error:
proc substr_test_nullable_string(t text)
begin
  select substr(t, 1, 2) as t;
end;

-- TEST: simple success -- substr nullable start
-- + {create_proc_stmt}: substr_test_nullable_start: { t: text } dml_proc
-- + {name substr}: text
-- - error:
proc substr_test_nullable_start(t text not null)
begin
  select substr(t, nullable(1), 2) as t;
end;

-- TEST: simple success -- substr nullable count
-- + {create_proc_stmt}: substr_test_nullable_count: { t: text } dml_proc
-- + {name substr}: text
-- - error:
proc substr_test_nullable_count(t text not null)
begin
  select substr(t, 1, nullable(2)) as t;
end;

-- TEST: simple success -- substr sensitive string
-- + {create_proc_stmt}: substr_test_sensitive_string: { t: text sensitive } dml_proc
-- + {name substr}: text sensitive
-- - error:
proc substr_test_sensitive_string(t text @sensitive)
begin
  select substr(t, 1, 2) as t;
end;

-- TEST: simple success -- substr sensitive start
-- + {create_proc_stmt}: substr_test_sensitive_start: { t: text sensitive } dml_proc
-- + {name substr}: text sensitive
-- - error:
proc substr_test_sensitive_start(t text)
begin
  select substr(t, sensitive(1), 2) as t;
end;

-- TEST: simple success -- substr sensitive count
-- + {create_proc_stmt}: substr_test_sensitive_count: { t: text sensitive } dml_proc
-- + {name substr}: text sensitive
-- - error:
proc substr_test_sensitive_count(t text)
begin
  select substr(t, 1, sensitive(2)) as t;
end;

-- TEST: substr error -- arg1 is not a string
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'substr'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc substr_test_notstring()
begin
  select substr(3, 1, 2);
end;

-- TEST: substr error -- arg2 is not a number
-- + error: % argument 2 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' in 'substr'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc substr_test_arg2string()
begin
  select substr('x', '1', 2);
end;

-- TEST: substr error -- arg3 is not a number
-- + error: % argument 3 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' in 'substr'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc substr_test_arg3string()
begin
  select substr('x', 1, '2');
end;

-- TEST: substr error -- too few arguments
-- + error: % too few arguments in function 'substr'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc substr_test_toofew()
begin
  select substr('x');
end;

-- TEST: substr error -- too many arguments
-- + error: % too many arguments in function 'substr'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc substr_test_toomany()
begin
  select substr('x', 1, 2, 4);
end;

-- TEST: The replace function requires exactly three arguments, not two.
-- + error: % too few arguments in function 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 'b');

-- TEST: The replace function requires exactly three arguments, not four.
-- + error: % too many arguments in function 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 'b', 'c', 'd');

-- TEST: The replace is rewritten to sql context
-- + LET replace_dummy := ( SELECT replace('a', 'b', 'c') IF NOTHING THEN THROW );
-- + {let_stmt}: replace_dummy: text notnull variable
-- + {call}: text notnull
-- - error:
let replace_dummy := replace('a', 'b', 'c');

-- TEST: The first argument to replace must be a string.
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace(0, 'b', 'c');

-- TEST: The second argument to replace must be a string.
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 0, 'c');

-- TEST: The third argument to replace must be a string.
-- + error: % argument 3 'integer' is an invalid type; valid types are: 'text' in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 'b', 0);

-- TEST: The replace function has a TEXT! result type if ALL of its
-- arguments are nonnull.
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name replace}: text notnull
-- - error:
select replace('a', 'b', 'c');

-- TEST: The replace function has a nullable TEXT result type if its first
-- argument is nullable.
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name replace}: text
-- - error:
select replace(nullable('a'), 'b', 'c');

-- TEST: The replace function has a nullable TEXT result type if its second
-- argument is nullable.
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name replace}: text
-- - error:
select replace('a', nullable('b'), 'c');

-- TEST: The replace function has a nullable TEXT result type if its third
-- argument is nullable.
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name replace}: text
-- - error:
select replace('a', 'b', nullable('c'));

-- TEST: The first argument to replace must not be the literal NULL.
-- + error: % argument 1 'real' is an invalid type; valid types are: 'text' in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace(2.0, 'b', 'c');

-- TEST: The second argument to replace must not be the literal NULL.
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 1, 'c');

-- TEST: The third argument to replace must not be the literal NULL.
-- + error: % argument 3 is a NULL literal; useless in 'replace'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select replace('a', 'b', null);

-- TEST: The result of replace is sensitive if its first argument is sensitive.
-- + {select_stmt}: _select_: { _anon: text notnull sensitive }
-- + {call}: text notnull sensitive
-- + {name replace}: text notnull sensitive
-- - error:
select replace(sensitive('a'), 'b', 'c');

-- TEST: The result of replace is sensitive if its second argument is sensitive.
-- + {select_stmt}: _select_: { _anon: text notnull sensitive }
-- + {call}: text notnull sensitive
-- + {name replace}: text notnull sensitive
-- - error:
select replace('a', sensitive('b'), 'c');

-- TEST: The result of replace is sensitive if its third argument is sensitive.
-- + {select_stmt}: _select_: { _anon: text notnull sensitive }
-- + {call}: text notnull sensitive
-- + {name replace}: text notnull sensitive
-- - error:
select replace('a', 'b', sensitive('c'));

-- TEST: create ad hoc version migration -- success
-- + {schema_ad_hoc_migration_stmt}: ok
-- + {version_annotation}
-- + {int 5}
-- + {name MyAdHocMigration}
-- - error:
@schema_ad_hoc_migration(5, MyAdHocMigration);

-- TEST: ad hoc migration proc must conform
-- + Incompatible declarations found
-- + error: % DECLARE PROC MyAdHocMigration () USING TRANSACTION
-- + error: % DECLARE PROC MyAdHocMigration (x INT)
-- + The above must be identical.
-- + error: % procedure declarations/definitions do not match 'MyAdHocMigration'
-- + {declare_proc_stmt}: err
-- +3 error:
declare proc MyAdHocMigration(x integer);

-- TEST: this is a valid decl by itself
-- + {declare_proc_stmt}: ok
-- - error:
declare proc InvalidAdHocMigration(y integer);

-- TEST: create ad hoc version migration -- failure due to invalid proc signature
-- + Incompatible declarations found
-- + error: % DECLARE PROC InvalidAdHocMigration (y INT)
-- + error: % DECLARE PROC InvalidAdHocMigration () USING TRANSACTION
-- + The above must be identical.
-- + error: % procedure declarations/definitions do not match 'InvalidAdHocMigration'
-- + schema_ad_hoc_migration_stmt}: err
-- +3 error:
@schema_ad_hoc_migration(5, InvalidAdHocMigration);

-- TEST: ok to go, simiple recreate migration
-- + {schema_ad_hoc_migration_stmt}: ok
-- + {name group_foo}
-- + {name proc_bar}
-- - error:
@schema_ad_hoc_migration for @recreate(group_foo, proc_bar);

-- TEST: foo is not a valid migration proc
-- + Incompatible declarations found
-- + error: % DECLARE PROC foo ()
-- + error: % DECLARE PROC foo () USING TRANSACTION
-- + The above must be identical.
-- + error: % procedure declarations/definitions do not match 'foo'
-- + {schema_ad_hoc_migration_stmt}: err
-- +3 error:
@schema_ad_hoc_migration for @recreate(group_something, foo);

-- TEST: duplicate group/proc in recreate migration
-- + error: % indicated procedure or group already has a recreate action 'group_foo'
-- + {schema_ad_hoc_migration_stmt}: err
-- + {name group_foo}
-- + {name proc_bar}
-- +1 error:
@schema_ad_hoc_migration for @recreate(group_foo, proc_bar);

-- TEST: create ad hoc version migration -- bogus name
-- + error: % name of a migration procedure may not end in '_crc' 'not_allowed_crc'
-- +1 error:
@schema_ad_hoc_migration(5, not_allowed_crc);

-- TEST: create ad hoc version migration -- duplicate proc
-- + error: % a procedure can appear in only one annotation 'MyAdHocMigration'
-- + {schema_ad_hoc_migration_stmt}: err
-- +1 error:
@schema_ad_hoc_migration(5, MyAdHocMigration);

-- TEST: create ad hoc version migration -- missing proc
-- + error: % ad hoc schema migration directive must provide a procedure to run
-- + {schema_ad_hoc_migration_stmt}: err
-- +1 error:
@schema_ad_hoc_migration(2);

-- make a test table for the upsert test with a pk and some columns
create table upsert_test( id integer primary key, name text, rate real);

-- TEST: use the excluded version of the names in an upsert
-- + {upsert_stmt}: ok
-- + {insert_stmt}: ok
-- + {name upsert_test}: upsert_test: { id: integer notnull primary_key, name: text, rate: real }
-- + {conflict_target}: upsert_test: { id: integer notnull, name: text, rate: real }
-- + {update_stmt}: upsert_test: { id: integer notnull primary_key, name: text, rate: real }
-- - error:
insert into upsert_test(id, name) values (1, 'name')
on conflict(id) do update set name = excluded.name, rate = id+1;

-- TEST: upsert statement with insert default values
-- + {upsert_stmt}: err
-- + {insert_stmt}: err
-- + {name_columns_values}
-- + {name foo}: foo: { id: integer notnull primary_key autoinc }
-- + {default_columns_values}
-- + {upsert_update}
-- + {conflict_target}
-- +1 error: % upsert-clause is not compatible with DEFAULT VALUES
-- +1 error:
insert into foo default values on conflict do nothing;

-- TEST: declare a value fetcher that doesn't use DML
-- + DECLARE PROC val_fetch (seed INT!) OUT (id TEXT);
-- + {declare_proc_stmt}: val_fetch: { id: text } uses_out
-- - dml_proc
-- - USING TRANSACTION
DECLARE PROC val_fetch (seed INT!) OUT (id TEXT);

-- TEST: declare a value fetcher that does use DML
-- + DECLARE PROC val_fetch_dml (seed INT!) OUT (id TEXT) USING TRANSACTION;
-- + {declare_proc_stmt}: val_fetch_dml: { id: text } dml_proc uses_out
DECLARE PROC val_fetch_dml (seed INT!) OUT (id TEXT) USING TRANSACTION;

-- TEST: declare a valid root deployable region
-- + {declare_deployable_region_stmt}: root_deployable_region: region deployable
-- + {name root_deployable_region}
-- - error:
@declare_deployable_region root_deployable_region;

-- TEST: create an error in a deployoable region (duplicate name)
-- + error: % schema region already defined 'root_deployable_region'
-- + {declare_deployable_region_stmt}: err
-- +1 error:
@declare_deployable_region root_deployable_region;

-- TEST: a simple leaves to use
-- + {declare_schema_region_stmt}: leaf1: region
-- - error:
@declare_schema_region leaf1;

-- + {declare_schema_region_stmt}: leaf2: region
-- - error:
@declare_schema_region leaf2;

-- + {declare_schema_region_stmt}: leaf3: region
-- - error:
@declare_schema_region leaf3;

-- TEST: this looks ok but leaf region will be subsumed later... so we will create an error later
-- + {declare_schema_region_stmt}: err
-- This node won't be an error when it's created, the error is emitted later when uses_leaf_3 is declared so no error message yet
-- The node does ultimately resolve into an error
-- - error:
@declare_schema_region pending_leaf_user using leaf3;

-- TEST: leaf region is claimed, this makes pending_leaf_user in error
-- + error: % region links into the middle of a deployable region; you must point to the root of 'uses_leaf_3' not into the middle: 'pending_leaf_user'
-- + {declare_deployable_region_stmt}: err
-- +1 error:
@declare_deployable_region uses_leaf_3  using leaf3;

-- TEST: declare a valid deployable region with dependencies
-- + {declare_deployable_region_stmt}: depl1: region deployable
-- + {name depl1}
-- + {name leaf1}
-- + {name leaf2}
-- - error:
@declare_deployable_region depl1 using leaf1, leaf2;

-- TEST: make a region that links into into the middle of outer_deployable_region
-- + error: % region links into the middle of a deployable region; you must point to the root of 'depl1' not into the middle: 'error_region'
-- +1 error:
@declare_schema_region error_region using leaf1;

-- TEST: this is a procedure that emits several rows "manually"
-- + {create_proc_stmt}: C: many_row_emitter: { A: integer notnull, B: integer notnull } variable dml_proc shape_storage uses_out_union value_cursor
-- +2 {out_union_stmt}: C: out_cursor_proc: { A: integer notnull, B: integer notnull } variable shape_storage value_cursor
-- - error:
proc many_row_emitter()
begin
  cursor C like out_cursor_proc;
  fetch C from call out_cursor_proc();
  out union C;
  out union C;
end;

-- TEST: compound selects are allowed as a select expression, they can still return one row
-- + {create_proc_stmt}: ok dml_proc
-- + {assign}: x: integer variable
-- + {name x}: x: integer variable
-- + {select_stmt}: _anon: integer notnull
-- + {select_core_compound}
-- + {int 1}
-- - error:
proc compound_select_expr()
begin
  declare x integer;

  set x := (select 1 where 0 union select 2 limit 1);
end;

-- TEST: declare a region with a private interior
-- + {declare_schema_region_stmt}: region_hiding_something: region
-- + | {name region_hiding_something}
-- + | {region_list}
-- +   | {region_spec}
-- +     | {name depl1}
-- +     | {int 1}
-- - error:
@declare_schema_region region_hiding_something using depl1 private;

-- TEST: declare a region with non-private interior
-- + {declare_schema_region_stmt}: region_not_hiding_something: region
-- + | {name region_not_hiding_something}
-- + | {region_list}
-- +   | {region_spec}
-- +     | {name depl1}
-- +     | {int 0}
-- - error:
@declare_schema_region region_not_hiding_something using depl1;

-- - error:
@enforce_normal foreign key on update;
-- - error:
@enforce_normal foreign key on delete;

-- test regions the innermost one here "private_region" can't be reached from client_region
-- - error:
@declare_schema_region private_region;

-- - error:
@declare_schema_region containing_region using private_region private;

-- - error:
@declare_schema_region client_region using containing_region;

-- - error:
@begin_schema_region private_region;

-- - error:
create table private_region_table(id integer primary key);

-- - error:
@end_schema_region;

-- - error:
@begin_schema_region containing_region;

-- - error:
create table containing_region_table(id integer primary key references private_region_table(id));

-- - error:
@end_schema_region;

-- - error:
@begin_schema_region client_region;

-- TEST: not able to access private region
-- + error: % (object is in schema region 'private_region' not accessible from region 'client_region') 'private_region_table'
-- + {create_table_stmt}: err
-- +1 error:
create table client_region_table_1(id integer primary key references private_region_table(id));

-- TEST: non-private table is good to go
-- + {create_table_stmt}: client_region_table_2: { id: integer notnull primary_key foreign_key }
-- + {fk_target_options}
-- +   | {fk_target}
-- +   | | {name containing_region_table}
-- - error:
create table client_region_table_2(id integer primary key references containing_region_table(id));

-- - error:
@end_schema_region;

-- TEST: explain not supported
-- + error: % Only [EXPLAIN QUERY PLAN ...] statement is supported
-- + {explain_stmt}: err
-- + {int 1}
-- +1 error:
explain select 1;

-- TEST: explain query plan with select
-- + {explain_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {int 2}
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull, name: text, rate: longint }
-- - error:
explain query plan select * from foo inner join bar where foo.id = 1;

-- TEST: explain query plan with update
-- + {explain_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {int 2}
-- + {update_stmt}: bar: { id: integer notnull, name: text, rate: longint }
-- - error:
explain query plan update bar set id = 1 where name = 'Stella';

-- TEST: explain query plan with incorrect select stmt
-- + error: % name not found 'bogus'
-- + {explain_stmt}: err
-- + {int 2}
-- + {select_stmt}: err
-- +1 error:
explain query plan select bogus;

-- TEST: explain query plan as result set of a proc
-- + {create_proc_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull } dml_proc
-- + {name explain_query}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {explain_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {int 2}
-- - error:
proc explain_query()
begin
  explain query plan select 1;
end;

-- TEST: explain query plan cursor
-- + {declare_cursor}: c: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull } variable
-- + {name c}: c: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull } variable
-- + {explain_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {int 2}
-- - error:
cursor c for explain query plan select * from foo inner join bar;

-- TEST: explain query plan cursor in proc
-- + {create_proc_stmt}: ok dml_proc
-- + {name explain_query_with_cursor}: ok dml_proc
-- + {declare_cursor}: c: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull } variable dml_proc
-- + {name c}: c: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull } variable dml_proc shape_storage
-- + {explain_stmt}: explain_query: { iselectid: integer notnull, iorder: integer notnull, ifrom: integer notnull, zdetail: text notnull }
-- + {int 2}
-- - error:
proc explain_query_with_cursor()
begin
  cursor c for explain query plan select 1;
  fetch c;
end;

-- TEST: test nullability result on column X in a union select
-- + {select_stmt}: union_all: { X: text }
-- + {select_core_list}: union_all: { X: text }
-- + {select_core}: _select_: { X: text notnull }
-- + {select_core_list}: _select_: { X: null }
-- + {select_core}: _select_: { X: null }
select "x" as X
union all
select null as X;

-- TEST: test nullability result on column X in a union select without alias
-- + {create_proc_stmt}: mixed_union: { X: text } dml_proc
-- + {name mixed_union}: mixed_union: { X: text } dml_proc
-- + {select_stmt}: union_all: { X: text }
-- + {select_core_list}: union_all: { X: text }
-- + {select_core}: _select_: { X: text notnull }
-- + {select_core_list}: _select_: { X: null }
-- + {select_core}: _select_: { X: null }
proc mixed_union()
begin
  select "x" X
  union all
  select null X;
end;

-- TEST: test nullability result on column X in a union select without alias
-- + {create_proc_stmt}: mixed_union_cte: { X: text } dml_proc
-- + {name mixed_union_cte}: mixed_union_cte: { x: text } dml_proc
-- + {with_select_stmt}: _select_: { X: text }
-- + {select_stmt}: union_all: { X: text }
-- + {select_core_list}: union_all: { X: text }
-- + {select_core}: _select_: { X: text notnull }
-- + {select_core_list}: _select_: { X: null }
-- + {select_core}: _select_: { X: null }
-- + {select_stmt}: _select_: { x: text }
-- + {select_core_list}: _select_: { x: text }
proc mixed_union_cte()
begin
  with core(x) as (
    select "x" X
    union all
    select null X
  )
  select * from core;
end;

-- TEST: select with a basic window function invocation
-- + {select_stmt}: _select_: { id: integer notnull, row_num: integer notnull }
-- + {select_core_list}: _select_: { id: integer notnull, row_num: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {name id}: id: integer notnull
-- + {select_expr}: row_num: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name row_number}: integer notnull
-- + {call_filter_clause}
-- + {window_defn}: ok
-- + {opt_as_alias}
-- + {name row_num}
-- + {select_from_etc}: TABLE { foo: foo }
-- - error:
select id, row_number() over () as row_num from foo;

-- TEST: window function invocation like regular function
-- + error: % function may not appear in this context 'row_number'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {call}: err
-- +1 error:
select id, row_number() as row_num from foo;

-- TEST: window function invocation outside [SELECT expr] statement
-- + error: % Window function invocations can only appear in the select list of a select statement
-- + {select_stmt}: err
-- + {select_from_etc}: err
-- + {opt_where}: err
-- + {window_func_inv}: err
-- + {call}
-- +1 error:
select 1 where row_number() over ();

-- TEST: test invalid number of argument on window function row_number()
-- + error: % function got incorrect number of arguments 'row_number'
-- + {select_stmt}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name row_number}: err
-- + {select_from_etc}: TABLE { foo: foo }
-- +1 error:
select id, row_number(1) over () as row_num from foo;

-- TEST: window function invocation with a window clause
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull, _anon: integer notnull }
-- + {select_expr}: integer notnull
-- +2 {window_func_inv}: integer notnull
-- +2 {call}: integer notnull
-- +2 {name row_number}: integer notnull
-- +2 {call_filter_clause}
-- + {name win1}
-- + {name win2}
-- + {opt_select_window}: ok
-- + {window_clause}: ok
-- +2 {window_name_defn_list}
-- +2 {window_name_defn}: ok
-- + {name win1}
-- + {name win2}
-- +2 {window_defn}: ok
-- - error:
select id, row_number() over win1, row_number() over win2
  from foo
  window
    win1 as (),
    win2 as ()
order by id;

-- TEST: test invalid window name
-- + error: % Window name is not defined 'bogus'
-- + {select_stmt}: err
-- + {window_func_inv}: err
-- + {call_filter_clause}
-- + {name bogus}: err
-- +1 error:
select id, row_number() over bogus
  from foo;

-- TEST: test invalid window definition
-- + error: % name not found 'bogus'
-- + {select_stmt}: err
-- + {opt_select_window}: err
-- + {window_clause}: err
-- + {window_name_defn}: err
-- + {window_defn}: err
-- + {name bogus}: err
-- +1 error:
select id, row_number() over win
  from foo
  window
    win as (order by bogus);

-- TEST: test window name definition not used
-- + error: % Window name definition is not used 'win'
-- + {select_stmt}: err
-- + {opt_select_window}: err
-- + {window_clause}: err
-- + {window_name_defn}: err
-- + {name win}: err
-- + {window_defn}
-- +1 error:
select id
  from foo
  window
    win as ();

-- TEST: test filter clause in window function invocation
-- + {select_stmt}: _select_: { id: integer notnull, row_num: text }
-- + {select_expr}: id: integer notnull
-- + {name id}: id: integer notnull
-- + {select_expr}: row_num: text
-- + {window_func_inv}: text
-- + {call}: text
-- + {name group_concat}: text
-- + {call_arg_list}
-- + {call_filter_clause}
-- + {opt_filter_clause}: bool notnull
-- + {opt_where}: bool notnull
-- + {ge}: bool notnull
-- + {name id}: id: integer notnull
-- + {int 99}: integer notnull
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- + {arg_list}
-- + {strlit '.'}: text notnull
-- + {window_defn}: ok
-- + {window_defn_orderby}
-- + {opt_as_alias}
-- + {name row_num}
-- + { foo: foo }
-- - error:
select id, group_concat(id, '.') filter (where id >= 99) over () as row_num from foo;

-- TEST: test filter clause do not support referencing on alias column
-- + error: % name not found 'alias'
-- + {select_stmt}: err
-- + {select_expr_list}: err
-- + {select_expr}: alias: integer notnull
-- + {name id}: id: integer notnull
-- + {name alias}
-- + {window_func_inv}: err
-- + {call}: err
-- + {name avg}
-- + {call_arg_list}
-- + {opt_filter_clause}: err
-- + {opt_where}: err
-- + {eq}: err
-- + {name alias}: err
-- + {int 0}: integer notnull
-- + {arg_list}
-- + {name id}
-- + {window_defn}: ok
-- + {window_defn_orderby}
-- + {select_from_etc}: TABLE { foo: foo }
-- +1 error:
select id as alias, avg(id) filter (where alias = 0) over () from foo;

-- TEST: test FILTER clause may only be used with aggregate window functions
-- + error: % function may not appear in this context 'row_number'
-- + error: % FILTER clause may only be used in function that are aggregated or user defined 'row_number'
-- + {select_stmt}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name row_number}
-- +2 error:
select 1, row_number() filter (where 1) over ();

-- TEST: test DISTINCT clause may only be used with aggregates
-- + error: % function may not appear in this context 'row_number'
-- + error: % DISTINCT may only be used in function that are aggregated or user defined 'row_number'
-- + {select_stmt}: err
-- + {call}: err
-- + {name row_number}
-- +2 error:
select 1, row_number(distinct 1);

-- TEST: test partition by grammar
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {window_func_inv}: integer notnull
-- + {call_filter_clause}
-- + {window_defn}: ok
-- + {opt_partition_by}: ok
-- + {expr_list}
-- + {name id}: id: integer notnull
-- - error:
select id, row_number() over (partition by id) from foo;

-- TEST: test order by grammar
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {window_func_inv}: integer notnull
-- + {call_filter_clause}
-- + {window_defn}: ok
-- + {opt_orderby}: ok
-- + {orderby_list}: ok
-- + {name id}: id: integer notnull
-- - error:
select id, row_number() over (order by id asc) from foo;

-- TEST: test order by bogus value
-- + error: % name not found 'bogus'
-- + {select_stmt}: err
-- + {window_func_inv}: err
-- + {call_filter_clause}
-- + {window_defn}: err
-- + {opt_orderby}: err
-- + {orderby_list}: err
-- + {name bogus}: err
-- +1 error:
select id, row_number() over (order by bogus asc) from foo;

-- TEST: test frame spec grammar combination
-- + {select_stmt}: _select_: { id: integer notnull, avg: real, _anon: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {select_expr}: avg: real
-- + {window_func_inv}: real
-- + {opt_frame_spec}: ok
-- + {int 131084}
-- + {expr_list}
-- + {window_func_inv}: integer notnull
-- + {opt_frame_spec}: ok
-- + {int 36994}
-- - error:
select id,
       avg(id) filter (where id > 0) over (groups unbounded preceding exclude ties) as avg,
       row_number() over (rows between id = 1 preceding and id = 45 following exclude current row)
  from foo;

-- TEST: test frame spec grammar combination
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {select_expr}: integer notnull
-- + {window_func_inv}: integer notnull
-- + {opt_frame_spec}: ok
-- - error:
select id,
       row_number() over (rows between current row and unbounded following exclude group)
  from foo;

-- TEST: test frame spec grammar combination
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {select_expr}: integer notnull
-- + {window_func_inv}: integer notnull
-- + {opt_frame_spec}: ok
-- - error:
select id,
       row_number() over (rows id > 0 preceding exclude ties)
  from foo;

-- TEST: test frame spec grammar with bogus expr
-- + error: % name not found 'bogus'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {opt_frame_spec}: err
-- + {name bogus}: err
-- +1 error:
select id,
       row_number() over (rows bogus = null preceding exclude ties)
  from foo;

-- TEST: test rank() window function
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {select_expr}: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name rank}: integer notnull
-- - error:
select id, rank() over () from foo;

-- TEST: test dense_rank() window function
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {select_expr}: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name dense_rank}: integer notnull
-- - error:
select id, dense_rank() over () from foo;

-- TEST: test percent_rank() window function
-- + {select_stmt}: _select_: { id: integer notnull, _anon: real notnull }
-- + {select_expr}: real notnull
-- + {window_func_inv}: real notnull
-- + {call}: real notnull
-- + {name percent_rank}: real notnull
-- - error:
select id, percent_rank() over () from foo;

-- TEST: test cume_dist() window function
-- + {select_stmt}: _select_: { id: integer notnull, _anon: real notnull }
-- + {select_expr}: real notnull
-- + {window_func_inv}: real notnull
-- + {call}: real notnull
-- + {name cume_dist}: real notnull
-- - error:
select id, cume_dist() over () from foo;

-- TEST: test ntile() window function
-- + {select_stmt}: _select_: { id: integer notnull, _anon: integer notnull }
-- + {select_expr}: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name ntile}: integer notnull
-- + {int 7}: integer notnull
-- - error:
select id, ntile(7) over () from foo;

-- TEST: test ntile() window function with a non integer param
-- + error: % Argument must be an integer (between 1 and max integer) in function 'ntile'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name ntile}
-- + {longint 9898989889989}: longint notnull
-- +1 error:
select id, ntile(9898989889989) over () from foo;

-- TEST: test ntile() window function with invalid int param
-- + error: % Argument must be an integer (between 1 and max integer) in function 'ntile'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name ntile}
-- + {arg_list}: err
-- + {int 0}: integer notnull
-- +1 error:
select id, ntile(0) over () from foo;

-- TEST: test ntile() window function with too many params
-- + error: % function got incorrect number of arguments 'ntile'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name ntile}
-- + {arg_list}:
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- +1 error:
select id, ntile(1, 2) over () from foo;

-- TEST: test ntile() window function outside window context
-- + error: % function may not appear in this context 'ntile'
-- + {select_stmt}: err
-- + {select_where}
-- + {opt_where}: err
-- + {call}: err
-- + {name ntile}
-- + {int 7}: integer notnull
-- +1 error:
select id from foo where ntile(7);

-- TEST: test lag() window function
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {window_func_inv}: id: integer notnull
-- + {call}: id: integer notnull
-- + {name lag}: id: integer notnull
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- + {int 1}: integer notnull
-- + {int 0}: integer notnull
-- - error:
select id, lag(id, 1, 0) over () from foo;

-- TEST: kind not compatible in lag between arg3 and arg1
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'some_key'
-- + error: % first and third arguments must be compatible in function 'lag'
-- + {select_stmt}: err
-- +2 error:
select lag(cost, 1, id) over () from with_kind;

-- TEST: lag with non integer offset
-- + error: % second argument must be an integer (between 0 and max integer) in function 'lag'
-- + {select_stmt}: err
-- +1 error:
select id, lag(id, 1.3, 0) over () from foo;

-- TEST: test lag() window function with non constant index (this is ok)
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- - error:
select id, lag(id, X, 0) over () from foo;

-- TEST: test lag() window function with lag() nullable even though id is not nullable
-- + {select_stmt}: _select_: { id: integer notnull, id: integer }
-- + {select_expr}: id: integer
-- + {window_func_inv}: id: integer
-- + {call}: id: integer
-- + {name lag}: id: integer
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- + {int 1}: integer notnull
-- - error:
select id, lag(id, 1) over () from foo;

-- TEST: test lag() window function with first param sensitive
-- + {select_stmt}: _select_: { id: integer, info: integer sensitive }
-- + {select_expr}: info: integer sensitive
-- + {window_func_inv}: info: integer sensitive
-- + {call}: info: integer sensitive
-- + {name lag}: info: integer sensitive
-- + {arg_list}: ok
-- + {name info}: info: integer sensitive
-- + {int 1}: integer notnull
-- - error:
select id, lag(info, 1) over () from with_sensitive;

-- TEST: test lag() window function with third param sensitive
-- + {select_stmt}: _select_: { id: integer, _anon: integer sensitive }
-- + {select_expr}: integer
-- + {window_func_inv}: integer sensitive
-- + {call}: integer sensitive
-- + {arg_list}: ok
-- + {mul}: integer
-- + {int 1}: integer notnul
-- + {name info}: info: integer sensitive
-- - error:
select id, lag(id * 3, 1, info) over () from with_sensitive;

-- TEST: test lag() window function with negative integer param
-- + error: % Argument must be an integer (between 0 and max integer) in function 'lag'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name lag}
-- + {arg_list}: err
-- +1 error:
select id, lag(id, -1) over () from foo;

-- TEST: test lag() window function with invalid first param
-- + error: % right operand cannot be a string in '|'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name lag}
-- + {arg_list}: err
-- +1 error:
select id, lag(id | " ") over () from foo;

-- TEST: test lag() window function with first and third param are not same type
-- + error: % lossy conversion from type 'REAL' in 0.7
-- + error: % first and third arguments must be compatible in function 'lag'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name lag}
-- + {arg_list}: err
-- +2 error:
select id, lag(id, 0, 0.7) over () from foo;

-- TEST: test lag() window function with no param
-- + error: % function got incorrect number of arguments 'lag'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name lag}
-- +1 error:
select id, lag() over () from foo;

-- TEST: test lead() window function
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {window_func_inv}: id: integer notnull
-- + {call}: id: integer notnull
-- + {name lead}: id: integer notnull
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- + {int 1}: integer notnull
-- + {mul}: integer notnull
-- - error:
select id, lead(id, 1, id * 3) over () from foo;

-- TEST: test first_value() window function
-- + {select_stmt}: _select_: { id: integer notnull, first: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name first_value}: integer notnull
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- - error:
select id, first_value(id) over () as first from foo;

-- TEST: ensure the kind of the first_value is preserved
-- + {select_stmt}: _select_: { first: integer<some_key> }
-- + {window_func_inv}: integer<some_key>
-- - error:
select first_value(id) over () as first from with_kind;

-- TEST: ensure the kind of the first_value is preserved
-- + {select_stmt}: _select_: { last: integer<some_key> }
-- + {window_func_inv}: integer<some_key>
-- - error:
select last_value(id) over () as last from with_kind;

-- TEST: ensure the kind of the nth_value is preserved
-- + {select_stmt}: _select_: { nth: integer<some_key> }
-- + {window_func_inv}: integer<some_key>
-- - error:
select nth_value(id, 5) over () as nth from with_kind;

-- TEST: test first_value() window function outside window context
-- + error: % function may not appear in this context 'first_value'
-- + {select_stmt}: err
-- + {select_where}
-- + {opt_where}: err
-- + {call}: err
-- + {name first_value}
-- + {int 7}: integer notnull
-- +1 error:
select id from foo where first_value(7);

-- TEST: test last_value() window function
-- + {select_stmt}: _select_: { id: integer notnull, last: integer notnull }
-- + {select_expr}: id: integer notnull
-- + {window_func_inv}: integer notnull
-- + {call}: integer notnull
-- + {name last_value}: integer notnull
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- - error:
select id, last_value(id) over () as last from foo;

-- TEST: test nth_value() window function
-- + {select_stmt}: _select_: { id: integer notnull, nth: integer }
-- + {select_expr}: id: integer
-- + {window_func_inv}: integer
-- + {call}: integer
-- + {name nth_value}: integer
-- + {arg_list}: ok
-- + {name id}: id: integer notnull
-- - error:
select id, nth_value(id, 1) over () as nth from foo;

-- TEST: test nth_value() window function outside window context
-- + error: % function may not appear in this context 'nth_value'
-- + {select_stmt}: err
-- + {select_where}
-- + {opt_where}: err
-- + {call}: err
-- + {name nth_value}
-- + {int 7}: integer notnull
-- +1 error:
select id from foo where nth_value(7, 1);

-- TEST: test nth_value() window function with incorrect number of param
-- + error: % function got incorrect number of arguments 'nth_value'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name nth_value}
-- +1 error:
select id, nth_value(id) over () from foo;

-- TEST: test nth_value() window function with invalid value on second param
-- + error: % second argument must be an integer between 1 and max integer in function 'nth_value'
-- + {select_stmt}: err
-- + {select_expr}: err
-- + {window_func_inv}: err
-- + {call}: err
-- + {name nth_value}: ok
-- + {name id}: id: integer notnull
-- + {int 0}: integer notnull
-- +1 error:
select id, nth_value(id, 0) over () as nth from foo;

-- TEST: try total functions with sensitive param
-- + {select_stmt}: _select_: { t: real notnull sensitive }
-- + {name total}: real notnull sensitive
-- + {name info}: info: integer sensitive
-- - error:
select total(info) as t from with_sensitive;

-- TEST: combine dummy data and FROM arguments in INSERT
-- This is all sugar
-- + INSERT INTO referenceable(a, b, c, d, e) VALUES (x, y, printf('c_%d', _seed_), printf('d_%d', _seed_), _seed_) @DUMMY_SEED(1) @DUMMY_NULLABLES;
-- - error:
proc insert_using_args_with_dummy(x int!, y real!)
begin
  insert into referenceable(a, b) from arguments @dummy_seed(1) @dummy_nullables;
end;

-- TEST: combine dummy data and FROM arguments in FETCH
-- This is all sugar
-- + FETCH C(a, b, c, d, e) FROM VALUES (x, y, printf('c_%d', _seed_), printf('d_%d', _seed_), _seed_) @DUMMY_SEED(1) @DUMMY_NULLABLES;
-- - error:
proc fetch_using_args_with_dummy(x int!, y real!)
begin
  cursor C like referenceable;
  fetch C(a,b) from arguments @dummy_seed(1) @dummy_nullables;
end;

-- TEST: ensure that empty list is expanded
-- + FETCH C(a, b, c, d, e) FROM VALUES (1, 2, 'x', 'y', 5);
-- - error:
proc fetch_from_empty_col_list()
begin
  cursor C like referenceable;
  fetch C from values (1, 2, 'x', 'y', 5);
  out C;
END;

-- we'll need this cursor for the FROM cursor tests
cursor c_bar like referenceable;

-- TEST: verify that we can insert from a match cursor
-- This is a sugar feature, so we only need to check the rewrite
-- Further semantic validation of the expansion happens normally as though the fields had been typed manually
-- + INSERT INTO referenceable(a, b, c, d, e) VALUES (c_bar.a, c_bar.b, c_bar.c, c_bar.d, c_bar.e);
-- + {insert_stmt}: ok
-- + {name referenceable}: referenceable: { a: integer notnull primary_key, b: real unique_key, c: text, d: text, e: longint }
-- - error:
insert into referenceable from cursor c_bar;

-- TEST: try to use no columns from the cursor
-- + error: % FROM [shape] is redundant if column list is empty
-- + {insert_stmt}: err
-- +1 error:
insert into referenceable() from cursor c_bar;

-- TEST: try to use a cursor that has no storage (a non automatic cursor)
-- + error: % cannot read from a cursor without fields 'fetch_cursor'
-- + {insert_stmt}: err
-- +1 error:
insert into referenceable from cursor fetch_cursor;

-- we need this cursor with only one field to test the case where the cursor is too small
cursor small_cursor like select 1 x;

-- TEST: try to use a cursor that has not enough fields
-- + error: % [shape] has too few fields 'small_cursor'
-- + {insert_stmt}: err
-- +1 error:
insert into referenceable from cursor small_cursor;

-- TEST: try to use something that isn't a cursor
-- + error: % not a cursor 'X'
-- + {insert_stmt}: err
-- +1 error:
insert into referenceable from cursor X;

-- TEST: -- simple use of update cursor statement
-- + {update_cursor_stmt}: ok
-- + | {name small_cursor}: small_cursor: _select_: { x: integer notnull } variable shape_storage value_cursor
-- + | {columns_values}
-- +   | {column_spec}
-- +   | | {name_list}
-- +   |   | {name x}: x: integer notnull
-- +   | {insert_list}
-- +     | {int 2}: integer notnull
-- - error:
update cursor small_cursor(x) from values (2);

-- TEST: -- wrong type
-- + error: % required 'INT' not compatible with found 'TEXT' context 'x'
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor small_cursor(x) from values ('x');

-- TEST: -- wrong number of columns
-- + error: % count of columns differs from count of values
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor small_cursor(x) from values (1, 2);

-- TEST: -- invalid column
-- + error: % name not found 'w'
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor small_cursor(w) from values (1);

-- TEST: -- not an auto cursor
-- + error: % cursor was not used with 'fetch [cursor]' 'my_cursor'
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor my_cursor(one) from values (2);

-- TEST: -- like statement can't be resolved in an update statement
-- + error: % must be a cursor, proc, table, or view 'not_a_symbol'
-- +1 error:
update cursor small_cursor(like not_a_symbol) from values (1);

-- TEST: -- not a cursor
-- + error: % not a cursor 'X'
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor X(one) from values (2);

-- TEST: -- CTE * rewrite
-- This is just sugar so all we have to do is verify that we
-- did the rewrite correctly
-- + some_cte (a, b, c) AS (
-- +   SELECT 1 AS a, 'b' AS b, 3.0 AS c
-- + )
-- + {with_select_stmt}: _select_: { a: integer notnull, b: text notnull, c: real notnull }
-- - error:
with some_cte(*) as (select 1 a, 'b' b, 3.0 c)
  select * from some_cte;

-- TEST: -- CTE * rewrite but some columns were anonymous
-- + error: % all columns in the select must have a name
-- + {with_select_stmt}: err
-- +1 error:
with some_cte(*) as (select 1)
  select * from some_cte;

-- we never actully make this table, we just use its shape
create temp table foo_data (
  c1 text not null, c2 integer, c3 real, c4 real, c5 real, c6 real, c7 real, c8 real, c9 real, c10 real
);

-- make a cursor on it
cursor nully_cursor like foo_data;

-- TEST: use the "null fill" feature of value cursors to rewrite this monster into valid full row fetch
-- + FETCH nully_cursor(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10) FROM VALUES ('x', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
-- + {fetch_values_stmt}: ok
-- +10 {insert_list}
-- +9 {null}: null
-- - error:
fetch nully_cursor(c1) from values ('x');

-- TEST: the one and only non-null column is missing, that's an error
-- + error: % required column missing in FETCH statement 'c1'
-- +1 error:
-- + {fetch_values_stmt}: err
fetch nully_cursor(c2) from values ('x');

-- make a small cursor and load it up, it has only 2 of the columns
cursor c1c7 like select 'x' c1, nullable(3.2) c7;
fetch c1c7 from values ('x', 3.2);

-- TEST: rewrite to use the columns of small cursor
-- + UPDATE CURSOR nully_cursor(c1, c7) FROM VALUES (c1c7.c1, c1c7.c7);
-- + {update_cursor_stmt}: ok
-- - error:
update cursor nully_cursor(like c1c7) from values (c1c7.c1, c1c7.c7);

-- TEST: full rewrite to use the columns of small cursor
-- + UPDATE CURSOR nully_cursor(c1, c7) FROM VALUES (c1c7.c1, c1c7.c7);
-- + {update_cursor_stmt}: ok
-- - error:
update cursor nully_cursor(like c1c7) from cursor c1c7;

-- TEST: try to update cursor from a bogus symbol
-- + error: % name not found 'not_a_symbol'
-- + {update_cursor_stmt}: err
-- +1 error:
update cursor nully_cursor(like c1c7) from cursor not_a_symbol;

-- TEST: rewrite to use the columns of small cursor
-- note that c7 did not get null and it's out of order, that confirms it came form the LIKE expression
-- + FETCH nully_cursor(c1, c7, c2, c3, c4, c5, c6, c8, c9, c10) FROM VALUES (c1c7.c1, c1c7.c7, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
-- + {fetch_values_stmt}: ok
-- - error:
fetch nully_cursor(like c1c7) from values (c1c7.c1, c1c7.c7);

-- TEST: full rewrite get the values from the cursor, same as above
-- + FETCH nully_cursor(c1, c7, c2, c3, c4, c5, c6, c8, c9, c10) FROM VALUES (c1c7.c1, c1c7.c7, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
-- + {fetch_values_stmt}: ok
-- - error:
fetch nully_cursor(like c1c7) from cursor c1c7;

-- TEST: fetch cursor form bogus cursor
-- + error: % name not found 'not_a_symbol'
-- + {fetch_values_stmt}: err
-- +1 error:
fetch nully_cursor(like c1c7) from cursor not_a_symbol;

-- TEST: fetch using like form -- bogus symbol
-- + error: % must be a cursor, proc, table, or view 'not_a_symbol'
-- + {fetch_values_stmt}: err
-- +1 error:
fetch nully_cursor(like not_a_symbol) from values (1, 2);

-- make a cursor with some of the bar columns
cursor id_name_cursor like select 1 id, 'x' name;

-- TEST: rewrite the columns of an insert from a cursor source
-- + INSERT INTO bar(id, name)
-- +   VALUES (1, 'x');
-- + {insert_stmt}: ok
-- - error:
insert into bar(like id_name_cursor) values (1, 'x');

-- TEST: insert using the like form, bogus symbol
-- + error: % must be a cursor, proc, table, or view 'not_a_symbol'
-- + {insert_stmt}: err
-- +1 error:
insert into bar(like not_a_symbol) values (1, 'x');

-- TEST: fetch using from a cursor using the like form
-- this is sugar, again we just verify the rewrite
-- we got a subset of the nully_cursor columns as desired.
-- + FETCH c1c7(c1, c7) FROM VALUES (nully_cursor.c1, nully_cursor.c7);
-- + {fetch_values_stmt}: ok
-- - error:
fetch c1c7 from cursor nully_cursor(like c1c7);

-- TEST: fetch from cursor using the like form, bogus symbol
-- + error: % must be a cursor, proc, table, or view 'not_a_symbol'
-- + {fetch_values_stmt}: err
-- +1 error:
fetch c1c7 from cursor nully_cursor(like not_a_symbol);

-- TEST: try to declare a procedure that uses out union
-- + DECLARE PROC out_union_user (x INT) OUT UNION (id INT, x TEXT);
-- + {declare_proc_stmt}: out_union_user: { id: integer, x: text } uses_out_union
-- - error:
declare proc out_union_user(x integer) out union (id integer, x text);

-- TEST: make a cursor for an externally defined out union func
-- + {declare_cursor}: out_union_cursor: out_union_user: { id: integer, x: text } variable uses_out_union
-- - error:
cursor out_union_cursor for call out_union_user(2);

-- a table with one sensitive column
create table sens_table(t text @sensitive);

-- TEST: introduce a declaration for the proc we are about to create, it has a sensitive result.
-- + {declare_proc_stmt}: sens_result_proc: { t: text sensitive } dml_proc
-- - error:
declare proc sens_result_proc () (t text @sensitive);

-- TEST: this is compatible with the above declaration, it won't be if SENSITIVE is not preserved.
-- + {create_proc_stmt}: sens_result_proc: { t: text sensitive } dml_proc
-- - error:
[[autotest=(dummy_test)]]
proc sens_result_proc()
begin
  select * from sens_table;
end;

-- TEST: simple proc decl
declare proc incompatible_result_proc () (t text);

-- TEST: this is compatible with the above declaration, it won't be if SENSITIVE is not preserved.
-- + Incompatible declarations found
-- + error: in declare_proc_stmt : DECLARE PROC incompatible_result_proc () (t TEXT)
-- + error: in create_proc_stmt : DECLARE PROC incompatible_result_proc () (t INT!)
-- + The above must be identical.
-- + error: % procedure declarations/definitions do not match 'incompatible_result_proc'
-- + {create_proc_stmt}: err
[[autotest=(dummy_test)]]
proc incompatible_result_proc ()
begin
  select 1 t;
end;

-- TEST: use collate in an expression
-- + {orderby_item}
-- + {collate}: name: text
-- + {name name}: name: text
-- + {name nocase}
-- - error:
select * from bar
order by name collate nocase;

-- TEST: verify collate cannot be used in a loose expression
-- + error: % COLLATE may only appear in the context of a SQL statement
-- + {collate}: err
-- +1 error:
set a_string := 'x' collate nocase;

-- TEST: Verify error propogation through collate
-- + error: % string operand not allowed in 'NOT'
-- + {collate}: err
-- +1 error:
select (not 'x') collate nocase;

-- TEST: verify that duplicate table with different "IF NOT EXISTS" is still ok
-- + {create_table_stmt}: foo: { id: integer notnull primary_key autoinc }
-- + {table_flags_attrs}
-- + {int 2}
-- - error:
create table if not exists foo(
  id integer PRIMARY KEY AUTOINCREMENT
);

-- TEST: verify that duplicate view with different "IF NOT EXISTS" is still ok
-- + {create_view_stmt}: MyView: { f1: integer notnull, f2: integer notnull, f3: integer notnull } alias
-- + {int 2}
-- - error:
create view if not exists MyView as select 1 as f1, 2 as f2, 3 as f3;

-- TEST: verify that duplicate trigger  with different "IF NOT EXISTS" is still ok
-- + {create_trigger_stmt}: ok alias
-- + {int 2}
-- - error:
create trigger if not exists trigger2
  after insert on bar
begin
  delete from bar where rate > new.id;
end;

-- TEST: verify that duplicate index  with different "IF NOT EXISTS" is still ok
-- + {create_index_stmt}: ok alias
-- + {int 2}
-- - error:
create index if not exists index_1 on foo(id);

-- TEST: verify blob literal semantic type
-- + {select_stmt}: _select_: { _anon: blob notnull }
-- + {blob x'FAB1'}: blob notnull
-- - error:
select x'FAB1';

-- TEST: blob literals are good in SQL only
-- + error: % blob literals may only appear in the context of a SQL statement
-- + {assign}: err
-- + {blob x'12abcdef'}: err
-- +1 error:
proc blob_literal_out(out b blob)
begin
  set b := x'12abcdef';
end;

-- TEST: test nullif with one param
-- + error: % function got incorrect number of arguments 'nullif'
-- + {select_stmt}: err
-- + {call}: err
-- + {name nullif}: err
-- +1 error:
select nullif(id) from bar;

-- TEST: test nullif with non null integer column table
-- + {select_stmt}: _select_: { n: integer }
-- + {call}: integer
-- + {name nullif}: integer
-- + {name id}: id: integer notnull
-- - error:
select nullif(id, 1) as n from bar;

-- TEST: kind preserved and matches
-- + {select_stmt}: _select_: { p: real<dollars> variable was_set }
-- + {call}: real<dollars> variable
-- - error:
select nullif(price_d, price_d) as p;

-- TEST: kind preserved and doesn't match -> error
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {select_stmt}: err
-- +1 error:
select nullif(price_d, price_e);

-- TEST: test nullif with incompatble type
-- + error: % required 'TEXT' not compatible with found 'INT' context 'NULLIF'
-- + {select_stmt}: err
-- +1 error:
select id, nullif(name, 1) from bar;

-- TEST: nullif may not appear outside of a SQL statement
-- + error: % function may not appear in this context 'nullif'
-- + {assign}: err
-- + {call}: err
set a_string := nullif('x', 1);

-- TEST: test nullif with sensitive value
-- + {select_stmt}: _select_: { n: text sensitive }
-- + {call}: text sensitive
-- + {name nullif}: text sensitive
-- + {name name}: name: text sensitive
-- - error:
select nullif(name, 'a') as n from with_sensitive;

-- TEST: declare a select function with name match SQLite function.
-- + error: % select function does not require a declaration, it is a CQL built-in 'nullif'
-- + {declare_select_func_stmt}: err
-- +1 error:
declare select function nullif(value INT, defaultValue int!) int;

-- TEST: test upper with sensitive value
-- + {select_stmt}: _select_: { _anon: text sensitive }
-- + {call}: text sensitive
-- + {name upper}: text sensitive
-- + {name name}: name: text sensitive
-- - error:
select upper(name) from with_sensitive;

-- TEST: test upper with incompatible param type
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'upper'
-- + {select_stmt}: err
-- + {call}: err
-- + {name upper}
-- +1 error:
select upper(id) from bar;

-- TEST: test upper with incompatible param count
-- + error: % too many arguments in function 'upper'
-- + {select_stmt}: err
-- + {call}: err
-- + {name upper}
-- +1 error:
select upper(name, 1) from bar;

-- TEST: upper rewritten to sql context
-- + SET a_string := ( SELECT upper('x') IF NOTHING THEN THROW );
-- + {call}: text notnull
-- - error:
set a_string := upper('x');

-- TEST: test char with sensitive value
-- + {select_stmt}: _select_: { c: text sensitive }
-- + {call}: text sensitive
-- + {name char}: text sensitive
-- + {name id}: id: integer
-- + {name info}: info: integer sensitive
-- - error:
select char(id, info) as c from with_sensitive;

-- TEST: test char with incompatible param type
-- + error: % argument 1 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' in 'char'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select char(name) from bar;

-- TEST: test char with incompatible param count
-- + error: % too few arguments in function 'char'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select char() from bar;

-- TEST: char rewritten to sql context
-- + SET a_string := ( SELECT char(1) IF NOTHING THEN THROW );
-- + {assign}: a_string: text variable was_set
-- - error:
set a_string := char(1);

-- TEST: test abs with sensitive value
-- + {select_stmt}: _select_: { _anon: integer sensitive }
-- + {call}: integer sensitive
-- + {name abs}: integer sensitive
-- + {name info}: info: integer sensitive
-- - error:
select abs(info) from with_sensitive;

-- TEST: abs should preserve kind
-- + {assign}: price_d: real<dollars> variable
-- + {call}: real<dollars>
-- - error:
set price_d := (select abs(price_d));

-- TEST: test abs with incompatible param count
-- + error: % too few arguments in function 'abs'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select abs() from bar;

-- TEST: test abs with non numeric param
-- + error: % argument 1 'text' is an invalid type; valid types are: 'integer' 'long' 'real' in 'abs'
-- + {select_stmt}: err
-- + {call}: err
-- + {name abs}
-- +1 error:
select abs('Horty');

-- TEST: test abs with null param
-- + error: % argument 1 is a NULL literal; useless in 'abs'
-- + {call}: err
-- +1 error:
select abs(null);

-- TEST: instr rewritten to sql context
-- + SET an_int := ( SELECT instr("x", "y") IF NOTHING THEN THROW );
-- + {assign}: an_int: integer variable was_set
-- + {call}: integer notnull
-- - error:
set an_int := instr("x", "y");

-- TEST: test instr with incompatible param count
-- + error: % too few arguments in function 'instr'
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
select instr();

-- TEST: test instr with sensitive value
-- + {select_stmt}: _select_: { x: integer sensitive }
-- + {call}: integer sensitive
-- + {name name}: name: text sensitive
-- - error:
select instr(name, 'a') as x from with_sensitive;

-- TEST: test instr with all param not null
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {call}: integer notnull
-- +2 {strlit 'a'}: text notnull
-- - error:
select instr('a', 'a');

-- TEST: test instr with all param not null
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'instr'
-- + {select_stmt}: err
-- + {call}: err
-- + {name instr}
-- +1 error:
select instr(1, 'a');

-- TEST: refer to non-existent table in an fk
-- + error: % foreign key refers to non-existent table 'this_table_does_not_exist'
-- + {create_table_stmt}: err
-- +1 error:
-- the @delete is necessary so that there will be table flags
create table bogus_reference_in_fk(
  col1 text,
  col2 int,
  foreign key(col2) references this_table_does_not_exist(col1) on update cascade on delete cascade
) @delete(1);

-- TEST: try to call an undeclared proc while in strict mode
-- + error: % calls to undeclared procedures are forbidden; declaration missing or typo 'some_external_thing'
-- +1 error:
call some_external_thing();

-- TEST: let this be usable
-- + {declare_proc_no_check_stmt}: ok
-- - error:
DECLARE PROC some_external_thing NO CHECK;

-- TEST: same call in non stict mode -> fine
-- - error:
call some_external_thing('x', 5.0);

-- TEST: unchecked procs cannot be used in expressions (unless re-declared with
-- FUNCTION or SELECT FUNCTION)
-- + error: % procedure of an unknown type used in an expression 'some_external_thing'
-- + {call}: err
-- +1 error:
let result_of_some_external_thing := some_external_thing('x', 5.0);

-- TEST: re-declare an unchecked proc with FUNCTION
-- + {declare_func_stmt}: integer
-- + {param}: t: text variable in
-- + {param}: r: real variable in
-- + {type_int}: integer
-- - error:
func some_external_thing(t text, r real) int;

-- TEST: works fine after re-declaring
-- + {let_stmt}: result_of_some_external_thing: integer variable
-- + {call}: integer
-- - error:
let result_of_some_external_thing := some_external_thing('x', 5.0);

-- a proc with a return type for use
declare proc _stuff() (id integer, name text);

-- TEST: type list base case, simple replacement
-- checking the rewrite (that's all that matters here)
-- + DECLARE PROC _stuff1 () (id INT, name TEXT);
-- - error:
declare proc _stuff1() (like _stuff);

-- TEST: type list insert in the middle of some other args, and dedupe
-- checking the rewrite (that's all that matters here)
-- + DECLARE PROC _stuff2 () (h1 INT, id INT, name TEXT, t1 INT);
-- - error:
declare proc _stuff2() ( h1 integer, like _stuff1, like _stuff, t1 integer);

-- TEST: type list insert in the middle of some other args, and dedupe
-- checking the rewrite (that's all that matters here)
-- + DECLARE PROC _stuff3 () (h2 INT, h1 INT, id INT, name TEXT, t1 INT, t2 INT);
-- - error:
declare proc _stuff3() ( h2 integer, like _stuff2, t2 integer);

-- TEST: try to make a name list from a bogus type
-- + error: % must be a cursor, proc, table, or view 'invalid_type_name'
-- + {declare_proc_stmt}: err
-- +1 error:
declare proc _stuff4() (like invalid_type_name);

-- TEST: rewrite with formal name, formals all duplicated with no qualifier
-- + DECLARE PROC _stuff5 () (id INT, name TEXT);
-- - error:
declare proc _stuff5() (like _stuff1, like _stuff1);

-- TEST: rewrite with formal name for each shape
-- + DECLARE PROC _stuff6 () (x_id INT, x_name TEXT, y_id INT, y_name TEXT);
-- - error:
declare proc _stuff6() (x like _stuff1, y like _stuff1);

-- TEST: access shape args using dot notation
-- + {dot}: x_id: integer variable in
proc using_like_shape(x like _stuff1)
begin
  call printf("%s\n", x.id);
end;

-- TEST: access invald shape args using dot notation
-- + error: % field not found in shape 'xyzzy'
-- +1 error:
proc using_like_shape_bad_name(x like _stuff1)
begin
  call printf("%s\n", x.xyzzy);
end;

-- TEST: try to pass some of my args along
-- + PROC arg_shape_forwarder (args_arg1 INT, args_arg2 TEXT, extra_args_id INT, extra_args_name TEXT)
-- + CALL proc2(args.arg1, args.arg2);
-- - error:
proc arg_shape_forwarder(args like proc2 arguments, extra_args like _stuff1)
begin
  call proc2(from args);
end;

-- create a table in the future
-- - error:
create table from_the_future(
  col1 text primary key
) @create(5);

-- TEST: trying to reference the future in an FK is an error
-- + error: % referenced table was created in a later version so it cannot be used in a foreign key 'from_the_future'
-- + {create_table_stmt}: err
-- +1 error:
create table in_the_past(
  col1 text,
  foreign key (col1) references from_the_future(col1)
) @create(4);

-- TEST: ok to reference in the same version
-- + {create_table_stmt}: in_the_future: { col1: text foreign_key } @create(5)
-- - error:
create table in_the_future(
  col1 text,
  foreign key (col1) references from_the_future(col1)
) @create(5);

-- Set up a proc we could call
-- - error:
declare proc basic_source() out union (id integer, name text);

-- TEST: this proc should be OUT not OUT UNION
-- + {create_proc_stmt}: C: basic_wrapper_out: { id: integer, name: text } variable dml_proc shape_storage uses_out
-- - {create_proc_stmt}: % uses_out_union
-- - error:
proc basic_wrapper_out()
begin
  cursor C for call basic_source();
  fetch C;
  out C;
end;

-- TEST: this proc should be OUT not OUT UNION
-- + {create_proc_stmt}: C: basic_wrapper_out_union: { id: integer, name: text } variable dml_proc shape_storage uses_out_union
-- - {create_proc_stmt}: % uses_out %uses_out_union
-- - {create_proc_stmt}: % uses_out_union %uses_out
-- - error:
proc basic_wrapper_out_union()
begin
  cursor C for call basic_source();
  fetch C;
  out union C;
end;

-- TEST: simple self reference
-- + {create_table_stmt}: self_ref1: { id: integer notnull primary_key, id2: integer foreign_key }
-- - error:
create table self_ref1(
 id integer primary key,
 id2 integer references self_ref1(id)
);

-- TEST: simple self reference with constraint notation
-- + {create_table_stmt}: self_ref2: { id: integer notnull primary_key, id2: integer foreign_key }
-- - error:
create table self_ref2(
 id integer primary key,
 id2 integer,
 foreign key (id2) references self_ref2(id)
);

-- TEST: refer to a column in myself -- column does not exist
-- + error: % name not found 'idx'
-- + {create_table_stmt}: err
-- +1 error:
create table self_ref3(
 id integer primary key,
 id2 integer references self_ref3(idx)
);

-- TEST: refer to a column in myself -- column does not exist -- via constraint
-- + error: % name not found 'idx'
-- + {create_table_stmt}: err
-- +1 error:
create table self_ref4(
 id integer primary key,
 id2 integer,
 foreign key (id2) references self_ref4(idx)
);

-- TEST: refer to a column in myself -- column not a key -- via constraint
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'self_ref5'
-- + {create_table_stmt}: err
-- +1 error:
create table self_ref5(
 id integer primary key,
 id2 integer,
 foreign key (id2) references self_ref5(id2)
);

-- TEST: refer to a table id that isn't a part of a PK/UK via the attribute
-- + error: % columns referenced in the foreign key statement should match exactly a unique key in the parent table 'self_ref2'
-- + {create_table_stmt}: err
-- +1 error:
create table fk_to_non_key(
 id integer references self_ref2(id2)
);

-- TEST: make sure we can parse the dummy test params that include null
-- + {name self_ref1}: ok
-- + {misc_attr_value_list}: ok
-- + {int 1}: ok
-- + {null}: ok
-- + {misc_attr_value_list}: ok
-- + {int 2}: ok
-- + {create_proc_stmt}: self_ref_proc_table: { id: integer notnull, id2: integer } dml_proc
-- - error:
[[autotest=((dummy_test, (self_ref1, (id, id2), (1, null), (2, 1))))]]
proc self_ref_proc_table()
begin
  select * from self_ref1;
end;

-- TEST: test ok_scan_table attribution
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name ok_table_scan}
-- + {name foo}: ok
-- - error:
[[ok_table_scan=foo]]
proc ok_table_scan()
begin
  select * from foo;
end;

-- TEST: test list of value for ok_scan_table attribution
-- + error: % ok_table_scan attribute must be a name
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {name cql}
-- + {name ok_table_scan}
-- + {name foo}: ok
-- + {int 1}: err
-- +1 error:
[[ok_table_scan=(foo, 1)]]
proc ok_table_scan_value()
begin
  select * from foo;
end;

-- TEST: bogus table name in ok_scan_table attribution
-- + error: % table name in ok_table_scan does not exist 'bogus'
-- + {misc_attrs}: err
-- + {name bogus}: err
-- + {name foo}
-- +1 error:
[[ok_table_scan=bogus]]
[[attr]]
proc ok_table_scan_bogus()
begin
  select * from foo;
end;

-- TEST: bogus integer in ok_scan_table attribution
-- + error: % ok_table_scan attribute must be a name
-- + {misc_attrs}: err
-- + {int 1}: err
-- +1 error:
[[ok_table_scan=1]]
proc ok_table_scan_value_int()
begin
  select * from foo;
end;

-- TEST: ok_scan_table attribution not on a create proc statement
-- + error: % ok_table_scan attribute can only be used in a create procedure statement
-- + {misc_attrs}: err
-- + {select_stmt}: err
-- +1 error:
[[ok_table_scan=foo]]
select * from foo;

-- TEST: no_scan_table attribution is not on create table node
-- + error: % no_table_scan attribute may only be added to a create table statement
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {select_stmt}: err
-- +1 error:
[[no_table_scan]]
select * from foo;

-- TEST: no_scan_table attribution on create table node
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- - error:
[[no_table_scan]]
create table no_table_scan(id text);

-- TEST: no_scan_table attribution with a value
-- + error: % a value should not be assigned to no_table_scan attribute
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {int 1}: err
-- + {select_stmt}: err
-- +1 error:
[[no_table_scan=1]]
select * from foo;

-- TEST: test select with values clause
-- + {select_stmt}: values: { column1: integer notnull }
-- + {select_core_list}: values: { column1: integer notnull }
-- + {select_core}: values: { column1: integer notnull }
-- + {values}: values: { column1: integer notnull }
-- + {int 1}: integer notnull
-- - error:
values (1);

-- TEST: test select with values clause (multi row values)
-- + {select_stmt}: values: { column1: integer notnull }
-- + {values}: values: { column1: integer notnull }
-- + {int 1}: integer notnull
-- + {int 5}: integer notnull
-- - error:
values (1), (5);

-- TEST: test sensitive value carry on in values clause
-- + {select_stmt}: values: { column1: integer sensitive }
-- + {values}: values: { column1: integer sensitive }
-- + {name _sens}: _sens: integer variable sensitive
-- - error:
values (1), (_sens);

-- TEST: number of column values not identical in values clause
-- + error: % number of columns values for each row should be identical in VALUES clause
-- + {select_stmt}: err
-- + {values}: err
-- + {dbl 4.5}: err
-- +1 error:
values (1), (3, 4.5);

-- TEST: incompatible types in values clause
-- + error: % required 'TEXT' not compatible with found 'INT' context 'VALUES clause'
-- + {select_stmt}: err
-- + {values}: err
-- + {int 1}: err
-- +1 error:
values ("ok"), (1);

-- TEST: test values clause compounded in insert stmt with dummy_seed
-- + error: % @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row
-- + {insert_stmt}: err
-- +1 error:
insert into foo (id) values (1) union values (2) @dummy_seed(1);

-- TEST: test values from a with statement, and seed, this not a supported form
-- + error: % @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row
-- + {insert_stmt}: err
-- +1 error:
insert into foo with T(x) as (values (1), (2), (3)) select * from T @dummy_seed(1);

-- TEST: test values from a with statement, no seed, this is fine.
-- + {insert_stmt}: ok
-- + {with_select_stmt}: _select_: { x: integer notnull }
insert into foo with T(x) as (values (1), (2), (3)) select * from T;

-- TEST: test values from simple select statement, and seed, this not a supported form
-- + error: % @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row
-- + {insert_stmt}: err
-- +1 error:
insert into foo select 1 @dummy_seed(1);

-- TEST: test multi row values in values clause with dummy_seed
-- + error: % @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row
-- + {insert_stmt}: err
-- +1 error:
insert into foo (id) values (1), (2) @dummy_seed(1);

-- TEST: test invalid expr in values clause
-- + error: % name not found 'bogus'
-- + {insert_stmt}: err
-- + {name bogus}: err
-- +1 error:
insert into foo values (bogus) @dummy_seed(1);

-- TEST: test null type expr in values clause with dummy_seed
-- + {insert_stmt}: ok
-- + {columns_values}: ok
-- + {null}: null
-- - error:
insert into foo values (null) @dummy_seed(1);

-- TEST: test incompatible type in values clause with dummy_seed
-- + error: % required 'INT' not compatible with found 'TEXT' context 'id'
-- + {insert_stmt}: err
-- + {strlit 'k'}: err
-- +1 error:
insert into foo values ("k") @dummy_seed(1);

-- TEST: test invalid expr in values clause
-- + error: % name not found 'l'
-- + {select_stmt}: err
-- + {values}: err
-- + {name l}: err
-- +1 error:
values (l);

-- TEST: test insert statement with compound select
-- + {insert_stmt}: ok
-- + {select_stmt}: UNION ALL: { column1: integer notnull }
-- + {select_core}: values: { column1: integer notnull }
-- + {select_core}: _select_: { column1: integer notnull }
-- - error:
insert into foo values (1) union all select 2 column1;

-- TEST: test multi row values in values clause with dummy_seed
-- + error: % @dummy_seed @dummy_nullables @dummy_defaults many only be used with a single VALUES row
-- + {insert_stmt}: err
-- +1 error:
insert into foo (id) values (1), (2) @dummy_seed(1);

-- TEST: number of column in second row is not correct in values clause
-- + error: % number of columns values for each row should be identical in VALUES clause
-- + {select_stmt}: err
-- + {values}: err
-- + {int 10}: err
-- +1 error:
values (1, 2), (10);

-- TEST: test invalid value in second row in values clause
-- + error: % name not found 'bogus'
-- + {select_stmt}: err
-- + {values}: err
-- + {strlit 'ok'}: text notnull
-- + {name bogus}: err
-- +1 error:
values ("ok"), (bogus);

-- TEST: basic table to test columns in wrong order in the insert statement
create table values_table(
  id integer PRIMARY KEY AUTOINCREMENT,
  name text
);

-- TEST: test columns in wrong order in insert statement.
-- + {insert_stmt}: ok
-- + {select_stmt}: values: { column1: text notnull, column2: null }
insert into values_table(name, id) values ("ok", null);

-- TEST: enforce strict without rowid
-- + @ENFORCE_STRICT WITHOUT ROWID;
-- + {enforce_strict_stmt}: ok
-- + {int 7}
-- - error:
@enforce_strict without rowid;

-- TEST: without rowid failed validation in strict mode
-- + error: % WITHOUT ROWID tables are forbidden if strict without rowid mode is enabled 'table_with_invalid_without_rowid_mode'
-- + {create_table_stmt}: err
-- +1 error:
create table table_with_invalid_without_rowid_mode(
  id integer primary key
) without rowid;

-- TEST: enforcement normal without rowid
-- + @ENFORCE_NORMAL WITHOUT ROWID;
-- + {enforce_normal_stmt}: ok
-- + {int 7}
@enforce_normal without rowid;

-- TEST: without rowid succeed validation in normal mode
-- + {create_table_stmt}: table_with_valid_without_rowid_mode: { id: integer notnull primary_key }
-- - error:
create table table_with_valid_without_rowid_mode(
  id integer primary key
) without rowid;

-- TEST: negating 9223372036854775808L requires first representing the positive value
-- this value does not fit in 64 bits signed.  As a consequence the numeric representation
-- of integers cannot just be an int64_t.  To avoid all these problems and more we
-- simply hold the string value of the integer as the need for math is very limited, nearly zero
-- anyway due to lack of constant folding and whatnot.
-- the text in the comment has the original string with the L
-- the positive version of the integer does not and there is
-- no kidding around negation going on here.
-- + SELECT -9223372036854775808L AS x;
-- + {create_proc_stmt}: min_int_64_test: { x: longint notnull } dml_proc
-- + {uminus}: longint notnull
-- + {longint 9223372036854775808}: longint notnull
CREATE PROC min_int_64_test ()
BEGIN
  SELECT -9223372036854775808L AS x;
END;

-- TEST: complex floating point and integer literals
-- first verify round trip through the AST
-- + SELECT
-- +    2147483647 AS a,
-- +    2147483648L AS b,
-- +    3.4e11 AS c,
-- +    .001e+5 AS d,
-- +    .4e-9 AS e;
-- + {int 2147483647}: integer notnull
-- + {longint 2147483648}: longint notnull
-- + {dbl 3.4e11}: real notnull
-- + {dbl .001e+5}: real notnull
-- + {dbl .4e-9}: real notnull
proc exotic_literals()
begin
  select 2147483647 a, 2147483648 b,  3.4e11 c, .001e+5 d, .4e-9 e;
end;

-- TEST: hex literal processing
-- + SELECT 0x13aF AS a, 0x234L AS b, 0x123456789L AS c;
-- + {int 0x13aF}: integer notnull
-- + {longint 0x234}: longint notnull
-- + {longint 0x123456789}: longint notnull
proc hex_literals()
begin
  select 0x13aF a, 0x234L b,  0x123456789 c;
end;

-- a type shape we will use for making args and cursors
declare proc shape() (x int!, y text not null);

-- just one column of the type, we'll use this to call with a slice of the cursor
declare proc small_shape() (y text not null);

-- some procedure we can call
declare proc shape_consumer(like shape);

-- TEST: try to call shape_consumer from a suitable cursor
-- This is strictly a rewrite so all we have to do here is make sure that we are calling the proc correctly
-- + CALL shape_consumer(C.x, C.y);
-- - error:
proc shape_all_columns()
begin
   cursor C like shape;
   fetch C from values (1, 'x');
   call shape_consumer(from C);
end;

-- TEST: try to call shape_consumer from not a cursor...
-- This is strictly a rewrite so all we have to do here is make sure that we are calling the proc correctly
-- + error: % name not found 'not_a_cursor'
-- + {create_proc_stmt}: err
-- + {call_stmt}: err
-- +1 error:
proc shape_thing_bogus_cursor()
begin
   call shape_consumer(from not_a_cursor);
end;

-- TEST: try to call shape_consumer using a statement cursor.  This is bogus...
-- + {create_proc_stmt}: err
-- + {call_stmt}: err
-- +2 error:
proc shape_some_columns_statement_cursor()
begin
   cursor C for select 1 x, 'y' y;
   call shape_consumer(from C);
end;

declare proc shape_y_only(like small_shape);

-- TEST: try to call shape_y_only using the LIKE form
-- This is strictly a rewrite so all we have to do here is make sure that we are calling the proc correctly
-- + CALL shape_y_only(C.y);
-- - error:
proc shape_some_columns()
begin
   cursor C like shape;
   fetch C(x, y) from values (1, 'x');
   call shape_y_only(from C like small_shape);
end;

-- TEST: try to call shape_y_only using the LIKE form with bogus like name
-- + error: % must be a cursor, proc, table, or view 'not_a_real_shape'
-- +1 error:
proc shape_some_columns_bogus_name()
begin
   cursor C like shape;
   fetch C(x, y) from values (1, 'x');
   call shape_y_only(from C like not_a_real_shape);
end;

declare proc lotsa_ints(a int!, b int!, c int!, d int!);

-- TEST: try inserting arguments into the middle of the arg list
-- + CALL lotsa_ints(C.x, C.y, 1, 2);
-- + CALL lotsa_ints(1, C.x, C.y, 2);
-- + CALL lotsa_ints(1, 2, C.x, C.y);
-- + CALL lotsa_ints(C.x, C.y, C.x, C.y);
-- - error:
proc shape_args_middle()
begin
   cursor C like select 1 x, 2 y;
   fetch C from values (1, 2);
   call lotsa_ints(from C, 1, 2);
   call lotsa_ints(1, from C, 2);
   call lotsa_ints(1, 2, from C);
   call lotsa_ints(from C, from C);
end;

-- TEST: try a variety of standard arg replacements
-- Just rewrites to verify
-- +  CALL lotsa_ints(x, y, 1, 2);
-- +  CALL lotsa_ints(1, x, y, 2);
-- +  CALL lotsa_ints(1, 2, x, y);
-- +  CALL lotsa_ints(x, y, x, y);
-- - error:
proc arg_rewrite_simple(x int!, y int!)
begin
   call lotsa_ints(from arguments, 1, 2);
   call lotsa_ints(1, from arguments, 2);
   call lotsa_ints(1, 2, from arguments);
   call lotsa_ints(from arguments, from arguments);
end;

-- TEST: try from arguments with no arguments
-- + error: % FROM ARGUMENTS used in a procedure with no arguments 'arg_rewrite_no_args'
-- +1 error:
proc arg_rewrite_no_args()
begin
   call lotsa_ints(from arguments, 1, 2);
end;

-- TEST: try to use from arguments outside of any procedure
-- + error: % FROM ARGUMENTS construct is only valid inside a procedure
-- +1 error:
call lotsa_ints(from arguments, 1, 2);

-- TEST: try a variety of standard arg replacements with type constraint
-- Just rewrites to verify
-- +  CALL lotsa_ints(y, 1, 2, 3);
-- +  CALL lotsa_ints(1, y, 2, 3);
-- +  CALL lotsa_ints(1, 2, y, 3);
-- +  CALL lotsa_ints(1, 2, 3, y);
-- +  CALL lotsa_ints(y, y, y, y);
-- - error:
proc arg_rewrite_with_like(x int!, y int!)
begin
   call lotsa_ints(from arguments like small_shape, 1, 2, 3);
   call lotsa_ints(1, from arguments like small_shape, 2, 3);
   call lotsa_ints(1, 2, from arguments like small_shape, 3);
   call lotsa_ints(1, 2, 3, from arguments like small_shape);
   call lotsa_ints(from arguments like small_shape,
                   from arguments like small_shape,
                   from arguments like small_shape,
                   from arguments like small_shape);
end;

-- TEST: try a variety of standard arg replacements with type constraint
--       this version matches the arg with a trailing underscore
-- Just rewrites to verify
-- +  CALL lotsa_ints(y_, 1, 2, 3);
-- +  CALL lotsa_ints(1, y_, 2, 3);
-- +  CALL lotsa_ints(1, 2, y_, 3);
-- +  CALL lotsa_ints(1, 2, 3, y_);
-- +  CALL lotsa_ints(y_, y_, y_, y_);
-- - error:
proc arg_rewrite_with_like_with_underscore(x int!, y_ int!)
begin
   call lotsa_ints(from arguments like small_shape, 1, 2, 3);
   call lotsa_ints(1, from arguments like small_shape, 2, 3);
   call lotsa_ints(1, 2, from arguments like small_shape, 3);
   call lotsa_ints(1, 2, 3, from arguments like small_shape);
   call lotsa_ints(from arguments like small_shape,
                   from arguments like small_shape,
                   from arguments like small_shape,
                   from arguments like small_shape);
end;

-- TEST: try a variety of standard arg replacements with type constraint
--       this version matches the arg with a trailing underscore
--       this version also writes more than one column
-- Just rewrites to verify
-- +  CALL lotsa_ints(x_, y_, 1, 2);
-- +  CALL lotsa_ints(1, x_, y_, 2);
-- +  CALL lotsa_ints(1, 2, x_, y_);
-- +  CALL lotsa_ints(x_, y_, x_, y_);
-- - error:
proc arg_rewrite_with_like_many_cols_with_underscore(x_ int!, y_ int!)
begin
   call lotsa_ints(from arguments like shape, 1, 2);
   call lotsa_ints(1, from arguments like shape, 2);
   call lotsa_ints(1, 2, from arguments like shape);
   call lotsa_ints(from arguments like shape, from arguments like shape);
end;

-- TEST: try to do from arguments with a type but there is no matching arg
-- + error: % expanding FROM ARGUMENTS, there is no argument matching 'id'
-- + error: % additional info: calling 'lotsa_ints' argument #4 intended for parameter 'd' has the problem
-- + {call_stmt}: err
-- +2 error:
proc call_with_missing_type(x integer)
begin
  -- the table foo has a column 'id' but we have no such arg
  call lotsa_ints(1, 2, 3, from arguments like foo);
end;

-- TEST: try to do from arguments with a type but there is no such type
-- + error: % must be a cursor, proc, table, or view 'no_such_type_dude'
-- + {call_stmt}: err
-- + {arg_list}: err
-- +1 error:
proc call_from_arguments_bogus_type(x integer)
begin
  -- the table foo has a column 'id' but we have no such arg
  call lotsa_ints(1, 2, 3, from arguments like no_such_type_dude);
end;

-- this procedure ends with an out arg, can be called as a function
declare proc funclike(like shape, out z int!);

-- TEST: use argument expansion in a function call context
-- This is strictly a rewrite
-- + PROC arg_caller (x_ INT!, y_ TEXT!, OUT z INT!)
-- + SET z := funclike(x_, y_);
-- - error:
proc arg_caller(like shape, out z int!)
begin
   set z := funclike(from arguments like shape);
end;

-- TEST: use argument expansion in a function call context
-- + error: % must be a cursor, proc, table, or view 'not_a_shape'
-- + {call}: err
-- + {arg_list}: err
-- from arguments not replaced because the rewrite failed
-- + {from_shape}
-- + {name not_a_shape}: err
-- +1 error:
proc arg_caller_bogus_shape(like shape, out z int!)
begin
   set z := funclike(from arguments like not_a_shape);
end;

-- TEST: @proc rewrites
-- + SET p := 'savepoint_proc_stuff';
-- + SAVEPOINT savepoint_proc_stuff;
-- + ROLLBACK TO savepoint_proc_stuff;
-- + RELEASE savepoint_proc_stuff;
-- - error:
proc savepoint_proc_stuff()
begin
  declare p text;
  set p := @proc;
  savepoint @proc;
  rollback transaction to savepoint @proc;
  release savepoint @proc;
end;

-- TEST: call cql_cursor_diff_col with non variable arguments
-- + error: % CQL0205: not a cursor '1'
-- + error: % additional info: calling 'cql_cursor_diff_col' argument #1 intended for parameter 'l' has the problem
-- + {assign}: err
-- + {call}: err
-- +2 error:
set a_string := cql_cursor_diff_col(1, "bogus");

-- TEST: call cql_cursor_diff_col with invalid variable arguments
-- + error: % not a cursor 'an_int'
-- + error: % additional info: calling 'cql_cursor_diff_col' argument #1 intended for parameter 'l' has the problem
-- + {assign}: err
-- + {call}: err
-- +2 error:
set a_string := cql_cursor_diff_col(an_int, an_int2);

-- TEST: call cql_cursor_diff_col with cursor with fetch value and same shape
-- + error: % cursor was not used with 'fetch [cursor]' 'c1'
-- + error: % additional info: calling 'cql_cursor_diff_col' argument #1 intended for parameter 'l' has the problem
-- + {create_proc_stmt}: err
-- + {assign}: err
-- + {call}: err
-- + {name c1}: err
-- +2 error:
proc cql_cursor_diff_col_without_cursor_arg()
begin
  declare x int!;
  declare y text not null;
  cursor c1 for select 1 x, 'y' y;
  cursor c2 for select 1 x, 'y' y;
  fetch c1 into x, y; -- tricky, fetching but not with storage
  fetch c2;
  set a_string := cql_cursor_diff_col(c1, c2);
end;

-- TEST: try to use a cursor without fetching it
-- neither storage type has been specified by the time
-- we get to the if statement.  The error indicates the
-- most probable mistake.
-- + error: % cursor was not used with 'fetch [cursor]' 'C'
-- + {create_proc_stmt}: err
-- + {declare_cursor}: C: _select_: { x: integer notnull } variable dml_proc
-- + {if_stmt}: err
-- +  {name C}: err
-- +1 error:
proc cql_cursor_unfetched()
begin
  cursor C for select 1 x;
  if C then end if;
end;

-- TEST: call cql_cursor_diff_col with incompatible cursor types
-- + error: % in cql_cursor_diff_col, all columns must be an exact type match (expected integer notnull; found text notnull) 'x'
-- + {create_proc_stmt}: err
-- + {assign}: err
-- + {call}: err
-- the expected type does not get error marking
-- - {name c1}: err
-- + {name c2}: err
-- +1 error:
proc cql_cursor_diff_col_wrong_cursor_type()
begin
  cursor c1 for select 1 x;
  cursor c2 for select '1' x;
  fetch c1;
  fetch c2;
  set a_string := cql_cursor_diff_col(c1, c2);
end;

-- TEST: call cql_cursor_diff_col with invalid column count arguments
-- + error: % in cql_cursor_diff_col, all must have the same column count
-- + error: % additional difference diagnostic info:
-- + this item has 2 columns
-- + this item has 1 columns
-- + only in 1st: z text notnull
-- + {create_proc_stmt}: err
-- + {assign}: err
-- + {call}: err
proc cql_cursor_diff_col_with_wrong_col_count_arg()
begin
  cursor c1 for select 1 x, 'z' z;
  cursor c2 for select 1 x;
  fetch c1;
  fetch c2;
  set a_string := cql_cursor_diff_col(c1, c2);
end;

-- TEST: call cql_cursor_diff_col with valid cursor param but different column name
-- + error: % in cql_cursor_diff_col, all column names must be identical so they have unambiguous names; error in column 1: 'x' vs. 'z'
-- + {create_proc_stmt}: err
-- + {assign}: err
-- + {call}: err
-- diagnostics also present
-- +4 error:
proc cql_cursor_diff_col_compatible_cursor_with_diff_col_name()
begin
  cursor c1 for select 1 x, 'y' y;
  cursor c2 for select 1 z, 'v' v;
  fetch c1;
  fetch c2;
  set a_string := cql_cursor_diff_col(c1, c2);
end;

-- TEST: call cql_cursor_diff_col with cursor with fetch value and same shape
-- + SET a_string := cql_cursor_diff_col(c1, c2);
-- + {create_proc_stmt}: ok dml_proc
-- + {assign}: a_string: text variable
-- - error:
proc cql_cursor_diff_col_with_shape_storage()
begin
  cursor c1 for select 1 x, 'y' y;
  cursor c2 for select 1 x, 'y' y;
  fetch c1;
  fetch c2;
  set a_string := cql_cursor_diff_col(c1, c2);
end;

-- TEST: call cql_cursor_diff_col from another func
-- + CALL printf(cql_cursor_diff_col(c1, c2));
-- + {create_proc_stmt}: ok dml_proc
-- + {call_stmt}: ok
-- - error:
proc print_call_cql_cursor_diff_col()
begin
  cursor c1 for select 1 x, 'y' y;
  cursor c2 for select 1 x, 'v' y;
  fetch c1;
  fetch c2;
  call printf(cql_cursor_diff_col(c1, c2));
end;

-- TEST: call cql_cursor_diff_val from another func
-- + CALL printf(cql_cursor_diff_val(c1, c2));
-- + {create_proc_stmt}: ok dml_proc
-- + {call_stmt}: ok
-- - error:
proc print_call_cql_cursor_diff_val()
begin
  cursor c1 for select nullable(1) x, 'y' y;
  cursor c2 for select nullable(1) x, 'v' y;
  fetch c1;
  fetch c2;
  call printf(cql_cursor_diff_val(c1, c2));
end;

-- TEST: simple trim call (two args)
-- + {call}: text notnull
-- + {name trim}: text notnull
-- - sensitive
-- - error:
set a_string := (select trim("x", "y"));

-- TEST: simple trim call (one arg)
-- + {call}: text notnull
-- + {name trim}: text notnull
-- - sensitive
-- - error:
set a_string := (select trim("x"));

declare kind_string text<surname>;

-- TEST: substr preserves kind
-- + {select_stmt}: _anon: text<surname>
-- + {name kind_string}: kind_string: text<surname> variable
-- - error:
set kind_string := (select substr(kind_string, 2, 3));

-- TEST: replace preserves kind
-- + {select_stmt}: _anon: text<surname>
-- + {name kind_string}: kind_string: text<surname> variable
-- - error:
set kind_string := (select replace(kind_string, 'b', 'c'));

-- TEST: verify that kind is preserved
-- + {select_stmt}: _anon: text<surname>
-- + {name kind_string}: kind_string: text<surname> variable
-- - error:
set kind_string := (select trim(kind_string));

-- TEST: verify that kind is preserved
-- + {select_stmt}: _anon: text<surname>
-- + {name kind_string}: kind_string: text<surname> variable
-- - error:
set kind_string := (select upper(kind_string));

-- TEST: verify that kind is preserved
-- + {select_stmt}: _anon: text<surname>
-- + {name kind_string}: kind_string: text<surname> variable
-- - error:
set kind_string := (select lower(kind_string));

-- TEST: simple ltrim call
-- + {call}: text notnull
-- + {name ltrim}: text notnull
-- - sensitive
-- - error:
set a_string := (select ltrim("x", "y"));

-- TEST: simple rtrim call
-- + {call}: text notnull
-- + {name rtrim}: text notnull
-- - sensitive
-- - error:
set a_string := (select rtrim("x", "y"));

-- TEST: trim failure: no args
-- + error: % too few arguments in function 'trim'
-- + {call}: err
-- +1 error:
set a_string := (select trim());

-- TEST: trim failure: three args
-- + error: % too many arguments in function 'trim'
-- + {call}: err
-- +1 error:
set a_string := (select trim('x','y','z'));

-- TEST: trim failure: arg 1 is not a string
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'trim'
-- + {call}: err
-- +1 error:
set a_string := (select trim(1,"x"));

-- TEST: trim failure: arg 2 is not a string
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'trim'
-- + {call}: err
-- +1 error:
set a_string := (select trim("x", 1));

-- TEST: trim rewritten to SQL context
-- + SET a_string := ( SELECT trim("x", "y") IF NOTHING THEN THROW );
-- + {call}: text notnull
-- - error:
set a_string := trim("x", "y");

-- TEST: trim must preserve sensitivity
-- + {call}: text sensitive
-- + {name trim}: text sensitive
-- - error:
set sens_text := (select trim(name) from with_sensitive);

-- TEST: trim must preserve sensitivity (2nd arg too, 1st arg not null)
-- + {select_stmt}: result: text notnull sensitive
-- + {call}: text notnull sensitive
-- + {name trim}: text notnull sensitive
-- - error:
set sens_text := (select trim("xyz", name) result from with_sensitive);

-- TEST: call cql_cursor_format on a auto cursor
-- + CURSOR c1 FOR
-- +  SELECT
-- +     TRUE AS a,
-- +     1 AS b,
-- +     99L AS c,
-- +     'x' AS d,
-- +     nullable(1.1) AS e,
-- +     CAST('y' AS BLOB) AS f;
-- + FETCH c1;
-- cursor format is a normal call with dynamic cursor (used to be complex rewrite)
-- + SET a_string := cql_cursor_format(c1);
-- + {create_proc_stmt}: ok dml_proc
-- - error:
proc print_call_cql_cursor_format()
begin
  cursor c1 for select TRUE a, 1 b, 99L c, 'x' d, nullable(1.1) e, cast('y' as blob) f;
  fetch c1;
  set a_string := c1:format;
end;

-- TEST: call cql_cursor_format in select context
-- + error: % user function may not appear in the context of a SQL statement 'cql_cursor_format'
-- + {create_proc_stmt}: err
-- + {select_stmt}: err
-- + {call}: err
-- +1 error:
proc select_cql_cursor_format()
begin
  cursor c1 for select 1 as a;
  fetch c1;
  select c1:format as p;
end;

-- TEST: call cql_cursor_format on a not auto cursor
-- + error: % cursor was not used with 'fetch [cursor]' 'c'
-- + error: % additional info: calling 'cql_cursor_format' argument #1 intended for parameter 'C' has the problem
-- + {create_proc_stmt}: err
-- + {call}: err
-- + {name c}: err
-- +2 error:
proc print_call_cql_not_fetch_cursor_format()
begin
  cursor c for select 1;
  declare x int!;
  fetch C into x; -- tricky, fetching but not with storage
  set a_string := cql_cursor_format(c);
end;

-- TEST: assigning an int64 to an int is not ok
-- + error: % lossy conversion from type 'LONG'
-- + {assign}: err
-- +1 error:
set an_int := 1L;

-- TEST: assigning a real to an int is not ok
-- + error: % lossy conversion from type 'REAL'
-- + {assign}: err
-- +1 error:
set an_int := 1.0;

-- TEST: assigning a real to a long int is not ok
-- + error: % lossy conversion from type 'REAL'
-- + {assign}: err
-- +1 error:
set ll := 1.0;

-- TEST: length failure: no args
-- + error: % too few arguments in function 'length'
-- + {call}: err
-- +1 error:
set an_int := (select length());

-- TEST: length failure: no args
-- + error: % too few arguments in function 'octet_length'
-- + {call}: err
-- +1 error:
set an_int := (select octet_length());

-- TEST: length failure: arg is not a string
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'length'
-- + {call}: err
-- +1 error:
set an_int := (select length(1));

-- TEST: length rewritten to SQL
-- + SET an_int := ( SELECT length("x") IF NOTHING THEN THROW );
-- + {assign}: an_int: integer variable was_set
-- - error:
set an_int := length("x");

-- TEST: length must preserve sensitivity
-- + {call}: integer sensitive
-- + {name length}: integer sensitive
-- - error:
set _sens := (select length(name) from with_sensitive);

-- TEST: unicode failure: no args
-- + error: % too few arguments in function 'unicode'
-- + {call}: err
-- +1 error:
set an_int := (select unicode());

-- TEST: unicode failure: arg is not a string
-- + error: % 'integer' is an invalid type; valid types are: 'text' in 'unicode'
-- + {call}: err
-- +1 error:
set an_int := (select unicode(1));

-- TEST: unicode rewritten
-- + SET an_int := ( SELECT unicode("x") IF NOTHING THEN THROW );
-- + {assign}: an_int: integer variable was_set
-- - error
set an_int := unicode("x");

-- TEST: length must preserve nullability
-- + {assign}: an_int: integer variable
-- + {select_stmt}: _anon: integer notnull
-- + {call}: integer notnull
-- - error:
set an_int := (select length("x"));

-- TEST: unicode must preserve sensitivity
-- + {call}: integer sensitive
-- + {name unicode}: integer sensitive
-- - error:
set _sens := (select unicode(name) from with_sensitive);

-- TEST: box a cursor (success path)
-- + {name C}: C: _select_: { id: integer notnull, name: text, rate: longint } variable dml_proc
-- + {set_from_cursor}: C: _select_: { id: integer notnull, name: text, rate: longint } variable dml_proc boxed
-- - error:
proc cursor_box(out B object<bar cursor>)
begin
  cursor C for select * from bar;
  set B from cursor C;
end;

-- TEST: bad box arg as a param
-- + error: % expression must be of type object<T cursor> where T is a valid shape name 'OUT b BLOB<foo>'
-- +1 error:
proc bogus_param_for_box(out b blob<foo>)
begin
  cursor C for select * From bar;
  set b from cursor C;
end;

-- TEST: unbox a cursor (success path)
-- + {declare_cursor}: C: bar: { id: integer notnull, name: text, rate: longint } variable boxed
-- + {name C}: C: bar: { id: integer notnull, name: text, rate: longint } variable boxed
-- + {name box}: box: object<bar CURSOR> variable in
-- - error:
proc cursor_unbox(box object<bar cursor>)
begin
  cursor C for box;
end;

-- TEST: unbox from an object that has no type spec
-- + error: % expression must be of type object<T cursor> where T is a valid shape name 'box'
-- +1 error:
proc cursor_unbox_untyped(box object)
begin
  cursor C for box;
end;

-- TEST: unbox from an object that is not marked CURSOR
-- + error: % variable must be of type object<T CURSOR> or object<T SET> where T is a valid shape name 'box'
-- +1 error:
proc cursor_unbox_not_cursor(box object<bar>)
begin
  cursor C for box;
end;

-- TEST: unbox from an object that has a type spec that isn't a valid shape
-- + error: % must be a cursor, proc, table, or view 'not_a_type'
-- +1 error:
proc cursor_unbox_not_a_type(box object<not_a_type cursor>)
begin
  cursor C for box;
end;

-- TEST: unbox and attempt to redeclare the same cursor
-- + error: % duplicate variable name in the same scope 'C'
-- +1 error:
proc cursor_unbox_duplicate(box object<bar cursor>)
begin
  cursor C for box;
  cursor C for box;
end;

-- TEST: unbox from a variable that does not exist
-- + error: % name not found 'box'
-- +1 error:
proc cursor_unbox_not_exists()
begin
  cursor C for box;
end;

-- TEST: try to box a value cursor
-- + error: % cursor did not originate from a SQLite statement, it only has values 'C'
-- +1 error:
proc cursor_box_value(out box object<bar cursor>)
begin
  cursor C like bar;
  set box from cursor C;
end;

-- TEST: try to box but the type isn't a shape
-- + error: % must be a cursor, proc, table, or view 'barf'
-- +1 error:
proc cursor_box_not_a_shape(out box object<barf cursor>)
begin
  cursor C for select * from bar;
  set box from cursor C;
end;

-- TEST: try to box but the type doesn't match
-- + error: % in the cursor and the variable type, all must have the same column count
-- diagnostics also present
-- +4 error:
proc cursor_box_wrong_shape(out box object<foo cursor>)
begin
  cursor C for select * from bar;
  set box from cursor C;
end;

-- TEST: try to box but the source isnt a cursor
-- + error: % name not found 'XYZZY'
-- +1 error:
proc cursor_box_not_a_cursor(out box object<foo cursor>)
begin
  set box from cursor XYZZY;
end;

-- TEST: try to box but the source isnt a cursor
-- + error: % variable not found 'box'
-- +1 error:
proc cursor_box_var_not_found()
begin
  cursor C for select * from bar;
  set box from cursor C;
end;

-- TEST: test cql_get_blob_size cql builtin function
-- + {assign}: an_long: longint variable
-- + {name cql_get_blob_size}: longint
-- - error:
set an_long := cql_get_blob_size(blob_var);

-- TEST: test cql_get_blob_size with too many arguments
-- + error: % too many arguments in function 'cql_get_blob_size'
-- + {assign}: err
-- +1 error:
set an_long := cql_get_blob_size(blob_var, 0);

-- TEST: test cql_get_blob_size with invalid argument type
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'blob' in 'cql_get_blob_size'
-- + {assign}: err
-- + {call}: err
-- + {name cql_get_blob_size}
-- +1 error:
set an_long := cql_get_blob_size(an_int);

-- TEST: test cql_get_blob_size used in SQL context
-- + error: % function may not appear in this context 'cql_get_blob_size'
-- + {assign}: err
-- + {call}: err
-- + {name cql_get_blob_size}
-- +1 error:
set an_long := (select cql_get_blob_size(an_int));

declare proc some_proc(id integer, t text, t1 text not null, b blob, out x int!);

-- TEST: make a cursor using the arguments of a procedure as the shape
-- + CURSOR Q LIKE some_proc ARGUMENTS;
-- + {declare_cursor_like_name}: Q: some_proc[arguments]: { id: integer in, t: text in, t1: text notnull in, b: blob in, x: integer notnull in } variable shape_storage value_cursor
-- - error:
cursor Q like some_proc arguments;

-- TEST: make a procedure using a declared shape (rewrite test)
-- + PROC some_proc_proxy (id INT, t TEXT, t1 TEXT!, b BLOB, OUT x INT!)
-- - error:
proc some_proc_proxy(like some_proc arguments)
begin
   call some_proc(from arguments);
end;

declare proc some_proc2(inout id integer, t text, t1 text not null, b blob, out x int!);

-- TEST: make a procedure using a declared shape (rewrite test)
-- + PROC some_proc2_proxy (INOUT id INT, t TEXT, t1 TEXT!, b BLOB, OUT x INT!)
-- - error:
proc some_proc2_proxy(like some_proc2 arguments)
begin
   call some_proc(from arguments);
end;

-- TEST: there is no some_proc3 -- error
-- + PROC some_proc3_proxy (LIKE some_proc3 ARGUMENTS)
-- + error: % name not found 'some_proc3'
-- +1 error:
proc some_proc3_proxy(like some_proc3 arguments)
begin
   call some_proc(from arguments);
end;

-- TEST: there is no some_proc3 -- error
-- + error: % LIKE ... ARGUMENTS used on a procedure with no arguments 'proc1'
-- +1 error:
proc some_proc4_proxy(like proc1 arguments)
begin
end;

-- TEST: object arguments are supported
-- + {declare_cursor_like_name}: cursor_with_object: obj_proc[arguments]: { an_obj: object in } variable shape_storage value_cursor
-- + {shape_def}: obj_proc[arguments]: { an_obj: object in }
-- - error:
cursor cursor_with_object like obj_proc arguments;

-- TEST: try to make a proc that emits a cursor with an object in it
-- + {create_proc_stmt}: cursor_with_object: try_to_emit_object: { an_obj: object } variable shape_storage uses_out value_cursor
-- + {name try_to_emit_object}: cursor_with_object: try_to_emit_object: { an_obj: object } variable shape_storage uses_out value_cursor
-- + {stmt_list}: ok
-- + {out_stmt}: cursor_with_object: obj_proc[arguments]: { an_obj: object in } variable shape_storage value_cursor
-- + {name cursor_with_object}: cursor_with_object: obj_proc[arguments]: { an_obj: object in } variable shape_storage value_cursor
-- - error:
proc try_to_emit_object()
begin
  out cursor_with_object;
end;

-- TEST: test rewrite for [FETCH [c] USING ... ] grammar
-- + FETCH C(id, name, rate) FROM VALUES (1, NULL, 99);
-- + {create_proc_stmt}: ok
-- - error:
proc test_fetch_using()
begin
  cursor C like bar;
  fetch C using 1 id, NULL as name, 99 rate;
end;

-- TEST: test rewrite for [FETCH [c] USING ... ] grammar with dummy_seed
-- + FETCH C(id, name, rate) FROM VALUES (1, printf('name_%d', _seed_), _seed_) @DUMMY_SEED(9) @DUMMY_DEFAULTS @DUMMY_NULLABLES;
-- + {create_proc_stmt}: ok
-- - error:
proc test_fetch_using_with_dummy_seed()
begin
  cursor C like bar;
  fetch C using 1 id @dummy_seed(9) @dummy_defaults @dummy_nullables;
end;

-- TEST: try to return object from a select function
-- + error: % select function may not return type OBJECT 'returns_object_is_bogus'
-- + {declare_select_func_stmt}: err
-- +1 error:
declare select function returns_object_is_bogus() object;

-- TEST: simple check expression -> valid case
-- + {create_table_stmt}: with_check: { id: integer, lo: integer has_check, hi: integer }
-- + {col_attrs_check}: ok
-- + {le}: bool
-- + {name lo}: lo: integer
-- + {name hi}: hi: integer
-- - error:
create table with_check
(
  id integer,
  lo integer check (lo <= hi),
  hi integer
);

-- TEST: simple check expression -> bogus identifier
-- + error: % name not found 'hip'
-- + {create_table_stmt}: err
-- + {col_attrs_check}: err
-- + {le}: err
-- +1 error:
create table with_check_bogus_column
(
  id integer,
  lo integer check (lo <= hip),
  hi integer
);

-- TEST: simple collate, no problem
-- + {create_table_stmt}: with_collate: { id: integer, t: text has_collate }
-- + {col_attrs_collate}: ok
-- - error:
create table with_collate
(
  id integer,
  t text collate garbonzo
);

-- TEST: simple collate, bogus column type
-- + error: % collate applied to a non-text column 'i'
-- + {create_table_stmt}: err
-- + {col_attrs_collate}: err
-- +1 error:
create table with_collate
(
  id integer,
  i real collate garbonzo
);

-- TEST: make sure all constraints come after all columns
-- + error: % column definitions may not come after constraints 'id'
-- + {create_table_stmt}: err
-- +1 error:
create table bad_order(
 id integer,
 primary key (id),
 t text
);

-- TEST: test rewrite for [INSERT name USING ... ] grammar
-- + INSERT INTO foo(id) VALUES (1);
-- + {create_proc_stmt}: ok dml_proc
-- - error:
proc test_insert_using()
begin
  insert into foo using 1 id;
end;

-- TEST: test rewrite for [INSERT name USING ... ] grammar with dummy_seed
-- + INSERT INTO bar(id, name, rate) VALUES (1, printf('name_%d', _seed_), _seed_) @DUMMY_SEED(9) @DUMMY_DEFAULTS @DUMMY_NULLABLES
-- + {create_proc_stmt}: ok dml_proc
-- - error:
proc test_insert_using_with_dummy_seed()
begin
  insert into bar using 1 id @dummy_seed(9) @dummy_defaults @dummy_nullables;
end;

-- TEST: test rewrite for [INSERT name USING ... ] grammar printed
-- note: because the proc is a duplicate it won't be further analyzed
-- which means that we get to see the printout of the proc before
-- it is rewritten so this is a test for printing the "before" SQL
-- not a semantic test of the rewrite.  gen_sql code is exercised here.
-- + INSERT INTO foo USING 1 AS bogus;
-- + error: % duplicate stored proc name 'test_insert_using'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_insert_using()
begin
  insert into foo using 1 bogus;
end;

-- TEST: test rewrite for IIF func
-- + SELECT CASE
-- + WHEN an_int IS NULL THEN 3
-- + ELSE 2
-- + END;
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- - error:
select iif(an_int is null, 3, 2);

-- TEST: test rewrite for IIF func with invalid argument count
-- + error: % function got incorrect number of arguments 'iif'
-- + {select_stmt}: err
-- +1 error:
select iif(an_int is null, 2, 3, 4);

-- TEST: exercise iif analysis with a bad first argument
-- + {select_stmt}: err
-- + {name not_found}: err
-- +1 error:
select iif(not_found, 2, 3);

-- TEST: exercise iif analysis with a bad second argument
-- + {select_stmt}: err
-- + {name not_found}: err
-- +1 error:
select iif(1, not_found, 3);

-- TEST: exercise iif analysis with a bad third argument
-- + {select_stmt}: err
-- + {name not_found}: err
-- +1 error:
select iif(1, 2, not_found);

-- TEST: test rewrite for IIF func with non-numeric first argument
-- + error: % required 'BOOL' not compatible with found 'TEXT' context 'iif'
-- + {select_stmt}: err
-- +1 error:
select iif('x', 2, 3);

-- TEST: test rewrite for IIF func with incompatible types
-- + required 'INT' not compatible with found 'BLOB' context 'iif'
-- + {select_stmt}: err
-- +1 error:
select iif(an_int is null, 2, x'23');

-- TEST: test rewrite for IIF func out of sql context
-- + SET an_int := CASE
-- + WHEN an_int IS NULL THEN CASE
-- + WHEN 4 THEN 5
-- + ELSE 6
-- + END
-- + ELSE 2
-- + END;
-- + {assign}: an_int: integer variable
-- - error:
set an_int := iif(an_int is null, iif(4, 5, 6), 2);

-- TEST: test rewrite for [UPDATE cursor USING ... ] grammar
-- + UPDATE CURSOR small_cursor(x) FROM VALUES (2);
-- + {create_proc_stmt}: ok dml_proc
-- - error:
proc test_update_cursor_using()
begin
  update cursor small_cursor using 2 x;
end;

-- TEST: basic use of proc savepoint rollback return and commit return
-- + {create_proc_stmt}: ok dml_proc
-- + {name proc_savepoint_basic}: ok dml_proc
-- + {proc_savepoint_stmt}: ok
-- + {rollback_return_stmt}: ok
-- + {commit_return_stmt}: ok
proc proc_savepoint_basic()
begin
  proc savepoint
  begin
     if 1 then
       rollback return;
     else
       commit return;
     end if;
  end;
end;

-- TEST: proc savepoint with an error, the outer statement should be marked error
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {proc_savepoint_stmt}: err
proc proc_savepoint_error_in_stmt_list()
begin
  proc savepoint
  begin
     set X := not 'x';
  end;
end;

-- TEST: proc savepoint invalid outside of a proc
-- + error: % should be in a procedure and at the top level
-- + {proc_savepoint_stmt}: err
-- +1 error:
proc savepoint begin end;

-- TEST: proc savepoint invalid outside of a proc
-- + error: % should be in a procedure and at the top level
-- + {proc_savepoint_stmt}: err
-- +1 error:
proc savepoint_nested()
begin
   if 1 then
     proc savepoint begin end;
   end if;
end;

-- TEST: rollback return invalid outside of proc savepoint
-- + error: % statement must appear inside of a PROC SAVEPOINT block
-- + {rollback_return_stmt}: err
-- +1 error:
proc rollback_return_invalid()
begin
   if 1 then
     rollback return;
   end if;
end;

-- TEST: commit return invalid outside of proc savepoint
-- + error: % statement must appear inside of a PROC SAVEPOINT block
-- + {commit_return_stmt}: err
-- +1 error:
proc commit_return_invalid()
begin
   if 1 then
     commit return;
   end if;
end;

-- TEST: may not use a return statement inside of a savepoint block
-- + error: % use COMMIT RETURN or ROLLBACK RETURN in within a proc savepoint block
-- + {create_proc_stmt}: err
-- + {proc_savepoint_stmt}: err
-- + {return_stmt}: err
-- +1 error:
proc regular_return_invalid()
begin
   proc savepoint
   begin
     return;
   end;
end;

-- TEST: create an integer enum
-- + {declare_enum_stmt}: integer_things: integer
-- + {name pen}: integer = 1
-- + {name paper}: integer = 7
-- + {name pencil}: integer = 8
enum integer_things integer (
  pen,
  paper = 7,
  pencil
);

declare proc test_shape() (x integer_things);

-- TEST: ensure that the type kind is preserved on cursor read
-- + {name z}: z: integer<integer_things> notnull variable
-- - error:
proc enum_users()
begin
   cursor C like test_shape;
   fetch C using integer_things.pen x;
   let z := C.x;
end;

-- TEST: declare a proc with an enum argument and output column
-- + {declare_proc_stmt}: enum_users_out: { x: integer<integer_things> notnull } uses_out
-- - error:
declare proc enum_users_out(i integer_things) out (x integer_things);

-- TEST: ensure that a proc defined with an enum argument and enum output column
-- matches its previous declaration correctly
-- + {create_proc_stmt}: C: enum_users_out: { x: integer<integer_things> notnull } variable shape_storage uses_out value_cursor
-- - error:
proc enum_users_out(i integer_things)
begin
  cursor C like test_shape;
  fetch C using i x;
  out C;
end;

-- TEST: ensure that the type kind is preserved from an arg bundle
-- + PROC enum_in_bundle (b_x INT<integer_things>!)
-- proof that the cursor fields had the right type when extracted
-- + {name u}: u: integer<integer_things> notnull variable
-- proof that the b_x arg has the right type
-- + {name v}: v: integer<integer_things> notnull variable
-- rewrite includes the KIND
-- - error:
proc enum_in_bundle(b like test_shape)
begin
  let u := b.x;
  let v := b_x;  -- the param normal name
end;

-- TEST: verify typed names preserve kind
-- verify the rewrite include the enum type
-- + DECLARE PROC shape_result_test () (x INT<integer_things>!);
declare proc shape_result_test() (like test_shape);

-- TEST: create an integer enum exact copy is OK!
-- + {declare_enum_stmt}: integer_things: integer
-- + {name pen}: integer = 1
-- + {name paper}: integer = 7
-- + {name pencil}: integer = 8
enum integer_things integer (
  pen,
  paper = 7,
  pencil
);

-- TEST: create an real enum
-- + {declare_enum_stmt}: real_things: real
-- + {name pen}: real = 1.000000e+00
-- + {name paper}: real = 7.000000e+00
-- + {name pencil}: real = 8.000000e+00
enum real_things real (
  pen,
  paper = 7,
  pencil
);

-- TEST: x is declared with correct type and kind (real and <real_things>
-- + {declare_vars_type}: real<real_things> notnull
-- + {name rt}: rt: real<real_things> notnull variable
-- - error:
declare rt real_things;

-- TEST: ok to assign a pen to a x because it's a real_thing
-- + {assign}: rt: real<real_things> notnull variable
-- + {name rt}: rt: real<real_things> notnull variable
-- + {dbl 1.000000e+00}: real<real_things> notnull
set rt := real_things.pen;

-- TEST: not ok to assign integer_things.pen because it's the wrong kind
-- + error: % expressions of different kinds can't be mixed: 'real_things' vs. 'integer_things'
-- + {assign}: err
-- + {name rt}: rt: real<real_things> notnull variable
-- + {int 1}: integer<integer_things> notnull
-- +1 error:
set rt := integer_things.pen;

-- TEST: try to use an enum value, this is a rewrite
-- + SELECT 8.000000e+00;
select real_things.pencil;

-- TEST: try to use an enum value, invalid name
-- + error: % enum does not contain 'nope'
-- + {select_stmt}: err
-- + {dot}: err
-- +1 error:
select real_things.nope;

-- TEST: create a bool enum (it all becomes true/false)
-- + {declare_enum_stmt}: bool_things: bool
-- + {name pen}: bool = 1
-- + {name paper}: bool = 1
-- + {name pencil}: bool = 0
enum bool_things bool (
  pen,
  paper = 7,
  pencil
);

-- TEST: create a long integer enum
-- +  {declare_enum_stmt}: long_things: longint
-- + {name pen}: longint = 1
-- + {name paper}: longint = -7
-- + {name pencil}: longint = -6
enum long_things long_int (
  pen,
  paper = -7,
  pencil
);

-- TEST: duplicate enum name
-- + error: % enum definitions do not match 'long_things'
-- + {declare_enum_stmt}: err
-- there will be three reports, 1 each for the two versions and one overall error
-- +3 error:
enum long_things integer (
  foo
);

-- TEST: duplicate enum member name
-- + error: % duplicate enum member 'two'
-- + {declare_enum_stmt}: err
-- +1 error:
enum duplicated_things integer (
  two,
  two
);

-- TEST: invalid enum member
-- + error: % evaluation failed 'boo'
-- + {declare_enum_stmt}: err
-- +1 error:
enum invalid_things integer (
  boo = 1/0
);

-- TEST: refer to the enum from within itself
-- + ENUM sizes REAL (
-- + big = 100,
-- + medium = 1.000000e+02 / 2
-- + small = 5.000000e+01 / 2
-- + tiny = 2.500000e+01 / 2
-- + {name big}: real = 1.000000e+02
-- + {name medium}: real = 5.000000e+01
-- + {name small}: real = 2.500000e+01
-- + {name tiny}: real = 1.250000e+01
-- - error:
enum sizes real (
  big = 100,
  medium = big/2,
  small = medium/2,
  tiny = small/2
);

-- TEST: reference other enums in this enum
-- + ENUM misc REAL (
-- +   one = 1.000000e+02 - 2.500000e+01,
-- +   two = 7.500000e+01 - 1.250000e+01
-- + );
-- + {name one}: real = 7.500000e+01
-- + {name two}: real = 6.250000e+01
-- - error:
enum misc real (
  one = sizes.big - sizes.small,
  two = one - sizes.tiny
);

-- TEST: enum declarations must be top level
-- + error: % declared enums must be top level 'bogus_inside_proc'
-- + {create_proc_stmt}: err
-- + {declare_enum_stmt}: err
-- +1 error:
proc enum_in_proc_bogus()
begin
  enum bogus_inside_proc integer (foo);
end;

create table SalesInfo(
  month integer,
  amount real
);

-- TEST: sum is not allowed in a window range
-- + error: % function may not appear in this context 'sum'
-- +1 error:
SELECT month, amount, AVG(amount) OVER
  (ORDER BY month ROWS BETWEEN 1 PRECEDING AND sum(month) FOLLOWING)
SalesMovingAverage FROM SalesInfo;

-- TEST: sum is not allowed in a window range
-- + error: % function may not appear in this context 'sum'
-- +1 error:
SELECT month, amount, AVG(amount) OVER
  (PARTITION BY sum(month) ROWS BETWEEN 1 PRECEDING AND 3 FOLLOWING)
SalesMovingAverage FROM SalesInfo;

-- TEST: sum is not allowed in a window range
-- + error: % function may not appear in this context 'sum'
-- +1 error:
SELECT month, amount, AVG(amount) OVER
  (ORDER BY month ROWS BETWEEN sum(month) PRECEDING AND 1 FOLLOWING)
SalesMovingAverage FROM SalesInfo;

-- TEST: sum is not allowed in a filter expression
-- + error: % function may not appear in this context 'sum'
-- +1 error:
SELECT month, amount, AVG(amount) FILTER(WHERE sum(month) = 1) OVER
  (ORDER BY month ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING EXCLUDE NO OTHERS)
SalesMovingAverage FROM SalesInfo;

create table AB(
  a integer,
  b text
);

create table CD(
  c integer,
  d text
);

create table BA(
  b integer,
  a text
);

declare proc use_c() (c integer);

-- TEST: arg bundle with a specific column
-- + INSERT INTO AB(a) VALUES (a2.c);
-- - error:
proc arg_bundle_1(a1 like AB, a2 like CD)
begin
  insert into AB(a) from a2(c);
end;

-- TEST: arg bundle with a specific column using LIKE
-- + INSERT INTO AB(a) VALUES (a2.c);
-- - error:
proc arg_bundle_2(a1 like AB, a2 like CD)
begin
  insert into AB(a) from a2(like use_c);
end;

-- TEST: arg bundle one column, in order
-- + INSERT INTO AB(a) VALUES (a2.c);
-- - error:
proc arg_bundle_3(a1 like AB, a2 like CD)
begin
  insert into AB(a) from a2;
end;

-- TEST: arg bundle all columns
-- + INSERT INTO AB(a, b) VALUES (a1.a, a1.b);
-- - error:
proc arg_bundle_4(a1 like AB, a2 like CD)
begin
  insert into AB from a1;
end;

-- TEST: arg bundle reverse order using LIKE (arg mismatch)
-- + INSERT INTO AB(a, b) VALUES (a1.b, a1.a);
-- + required 'INT' not compatible with found 'TEXT' context 'a'
-- +1 error:
proc arg_bundle_5(a1 like AB, a2 like CD)
begin
  insert into AB from a1(like BA);
end;

-- TEST: arg bundle reverse order using LIKE both reversed
-- + INSERT INTO AB(b, a) VALUES (a1.b, a1.a);
-- - error:
proc arg_bundle_6(a1 like AB, a2 like CD)
begin
  insert into AB(like BA) from a1(like BA);
end;

-- TEST: arg bundle non-name matching columns (this is ok, all in order)
-- + INSERT INTO AB(a, b) VALUES (a2.c, a2.d);
-- - error:
proc arg_bundle_7(a1 like AB, a2 like CD)
begin
  insert into AB from a2;
end;

-- TEST: arg bundle out of order, no autoexpand (types mismatch)
-- + INSERT INTO AB(b, a) VALUES (a1.a, a1.b);
-- + error: % required 'TEXT' not compatible with found 'INT' context 'b'
-- +1 error:
proc arg_bundle_8(a1 like AB, a2 like CD)
begin
  insert into AB(b,a) from a1;
end;

-- TEST: arg bundle out of order, no autoexpand, loading from alternate names (types mismatch)
-- + INSERT INTO AB(b, a) VALUES (a2.c, a2.d);
-- + error: % required 'TEXT' not compatible with found 'INT' context 'b'
-- +1 error:
proc arg_bundle_9(a1 like AB, a2 like CD)
begin
  insert into AB(b,a) from a2;
end;

-- TEST: arg bundle into cursor in order but field names different
-- + FETCH C(a, b) FROM VALUES (a2.c, a2.d);
-- - error:
proc arg_bundle_10(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  fetch C from a2;
end;

-- TEST: arg bundle into cursor in order field names same
-- + FETCH C(a, b) FROM VALUES (a1.a, a1.b);
-- - error:
proc arg_bundle_11(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  fetch C from a1;
end;

-- TEST: arg bundle into cursor in order, but not all fields
-- + FETCH C(a, b) FROM VALUES (a1.a, NULL);
-- - error:
proc arg_bundle_12(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  fetch C(a) from a1;
end;

-- TEST: arg bundle update cursor, all fields, autoexpand
-- + UPDATE CURSOR C(a, b) FROM VALUES (a1.a, a1.b);
-- - error:
proc arg_bundle_13(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  update cursor C from a1;
end;

-- TEST: arg bundle update cursor, one field, name doesn't match
-- + UPDATE CURSOR C(a) FROM VALUES (a2.c);
-- - error:
proc arg_bundle_14(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  update cursor C(a) from a2;
end;

-- TEST: arg bundle update cursor, all fields, names don't match
-- + UPDATE CURSOR C(a, b) FROM VALUES (a2.c, a2.d);
-- - error:
proc arg_bundle_15(a1 like AB, a2 like CD)
begin
  cursor C like AB;
  update cursor C from a2;
end;

-- TEST: arg bundle update cursor, all fields, names don't match
-- + UPDATE CURSOR C(a, b) FROM VALUES (a2.c, a2.d);
-- - error:
proc arg_bundle_16(a1 like AB, a2 like CD)
begin
  cursor C like a1;
  update cursor C from a2;
end;

-- TEST: a simple virtual table form
-- + {create_virtual_table_stmt}: basic_virtual: { id: integer, t: text } virtual @recreate
-- the exact module name encodes this list so keeping the whole tree shape here
-- misc attributes are tested elsewhere so there's no need to go crazy on arg varieties here
-- +  | {module_info}
-- +  | | {name module_name}
-- +  | | {misc_attr_value_list}
-- +  |   | {name this}
-- +  |   | {misc_attr_value_list}
-- +  |     | {name that}
-- +  |     | {misc_attr_value_list}
-- +  |       | {name the_other}
create virtual table basic_virtual using module_name(this, that, the_other) as (
  id integer,
  t text
);

-- TEST: virtual table error case
-- + error: % duplicate column name 'id'
-- + {create_virtual_table_stmt}: err
-- + {create_table_stmt}: err
-- +1 error:
create virtual table broken_virtual_table using module_name as (
  id integer,
  id integer
);

-- TEST: no indices on virtual tables
-- + error: % cannot add an index to a virtual table 'basic_virtual'
-- + {create_index_stmt}: err
-- +1 error:
create index some_index on basic_virtual(id);

-- TEST: no triggers on virtual tables
-- + error: % cannot add a trigger to a virtual table 'basic_virtual'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger no_triggers_on_virtual
  before delete on basic_virtual
begin
  delete from bar where rate > id;
end;

-- TEST: no alters on virtual tables
-- + error: % cannot use ALTER TABLE on a virtual table 'basic_virtual'
-- + {alter_table_add_column_stmt}: err
-- +1 error:
alter table basic_virtual add column xname text;

-- TEST: must specify appropriate delete attribute
-- + error: % when deleting a virtual table you must specify @delete(nn, cql:module_must_not_be_deleted_see_docs_for_CQL0392) as a reminder not to delete the module for this virtual table 'deleting_virtual'
-- + {create_virtual_table_stmt}: err
-- +1 error:
create virtual table deleting_virtual using module_name(this, that, the_other) as (
  id integer,
  t text
) @delete(1);

-- TEST: using module attribute in an invalid location
-- + error: % built-in migration procedure not valid in this context 'cql:module_must_not_be_deleted_see_docs_for_CQL0392'
-- + {create_table_stmt}: err
-- +1 error:
create table any_table_at_all(
  id integer,
  t text
) @create(1, cql:module_must_not_be_deleted_see_docs_for_CQL0392);

-- TEST: must specify appropriate delete attribute, done correctly
-- + {create_virtual_table_stmt}: deleting_virtual_correctly: { id: integer, t: text } deleted virtual @delete(1)
-- - error:
create virtual table deleting_virtual_correctly using module_name(this, that, the_other) as (
  id integer,
  t text
) @delete(1, cql:module_must_not_be_deleted_see_docs_for_CQL0392);

-- TEST: emit an enum
-- + {emit_enums_stmt}: ok
-- - error:
@emit_enums ints;

-- TEST: emit an enum (failed case)
-- + error: % enum not found 'bogus_enum_name'
-- + {emit_enums_stmt}: err
-- +1 error:
@emit_enums bogus_enum_name;

-- TEST: try a check expression
-- + CHECK (v > 5)
-- + {create_table_stmt}: with_check_expr: { v: integer }
-- + {check_def}: ok
-- + {gt}: bool
-- + {name v}: v: integer
-- + {int 5}: integer notnull
-- - error:
create table with_check_expr(
  v integer,
  check (v > 5)
);

-- TEST: can't use random in a constraint expression
-- + error: % function may not appear in this context 'random'
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_random(
  v integer,
  check (v > random())
);

-- TEST: can't use changes in a constraint expression
-- + error: % function may not appear in this context 'changes'
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_changes(
  v integer,
  check (v > changes())
);

-- TEST: can't use UDF in a constraint expression
-- + error: % User function cannot appear in a constraint expression  'SqlUserFunc'
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_udf(
  v integer,
  check (v > SqlUserFunc(1))
);

-- TEST: random takes no args
-- + error: % function got incorrect number of arguments 'random'
-- + {select_stmt}: err
-- +1 error:
select random(5);

-- TEST: random success case
-- + {select_stmt}: _select_: { _anon: longint notnull }
-- + {name random}: longint notnull
-- - error:
select random();

-- TEST: sqlite_offset takes exactly one argument successfully
-- + {select_stmt}: _select_: { _anon: longint }
-- + {name sqlite_offset}: longint
-- - error:
select sqlite_offset(true);

-- TEST: sqlite_offset is only allowed in SQL
-- + error: % function may not appear in this context 'sqlite_offset'
-- + {call}: err
-- +1 error:
sqlite_offset(1);

-- TEST: sqlite_offset doesn't work on NULL
-- + error: % argument 1 is a NULL literal; useless in 'sqlite_offset'
-- + {call}: err
-- +1 error:
select sqlite_offset(null);

-- TEST: likely takes exactly one argument successfully
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {name likely}: bool notnull
-- - error:
select likely(true);

-- TEST: the return type of likely is the type of its argument
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {name likely}: integer notnull
-- - error:
select likely(42);

-- TEST: the return type of unlikely is the type of its argument
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {name unlikely}: integer notnull
-- - error:
select unlikely(42);

-- TEST: likely fails with incorrect number of arguments
-- + error: % too few arguments in function 'likely'
-- + {select_stmt}: err
-- +1 error:
select likely();

-- TEST: likely fails with null arg
-- + error: % argument 1 is a NULL literal; useless in 'likely'
-- + {select_stmt}: err
-- +1 error:
select likely(null);

-- TEST: normal use of likelihood
-- + {select_stmt}: _select_: { _anon: text notnull }
-- - error:
select likelihood('x', 0.2);

-- TEST: likelihood bogus second arg
-- + error: % argument 2 is a NULL literal; useless in 'likelihood'
-- + {select_stmt}: err
-- +1 error:
select likelihood('x', NULL);

-- TEST: invalid context
-- + error: % function may not appear in this context 'likelihood'
-- + {expr_stmt}: err
-- +1 error:
likelihood('x', 1.2);

-- TEST: likely fails when used outside a SQL statement
-- + error: % function may not appear in this context 'likely'
-- + {let_stmt}: err
-- +1 error:
let test := likely(true);

-- TEST: can't use nested select in a constraint expression
-- + error: % Nested select expressions may not appear inside of a constraint expression
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_select(
  v integer,
  check (v > (select 5))
);

-- TEST: can't use 'now' in strftime in a constraint expression
-- + error: % function may not appear in this context 'strftime'
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_strftime(
  t text
  check (t > strftime('%s', 'now'))
);

-- TEST: can't use 'now' in time in a constraint expression
-- + error: % function may not appear in this context 'date'
-- + {create_table_stmt}: err
-- +1 error:
create table with_check_expr_date(
  t text
  check (t > date('now'))
);

-- TEST: check expression error
-- + error: % name not found 'q'
-- + {create_table_stmt}: err
-- + {check_def}: err
-- +1 error:
create table with_bogus_check_expr(
  v integer,
  check (q > 5)
);

-- TEST: declare type definition
-- + {declare_named_type}: text sensitive
-- + {name my_type}: text sensitive
-- + {sensitive_attr}: text sensitive
-- + {type_text}: text
-- - error:
type my_type text @sensitive;

-- TEST: can't add sensitive again
-- + error: % an attribute was specified twice '@sensitive'
-- +1 error:
declare redundant_sensitive my_type @sensitive;

-- TEST: ok to add not null, it's not there already
-- verify the rewrite and also the type info
-- + DECLARE adding_notnull TEXT @SENSITIVE!;
-- + {declare_vars_type}: text notnull sensitive
-- + {name_list}: adding_notnull: text notnull variable init_required sensitive
-- - error:
declare adding_notnull my_type not null;

-- TEST: verify the check in the context of func create
-- + error: % an attribute was specified twice '@sensitive'
-- + {declare_func_stmt}: err
-- +1 error:
func adding_attr_to_func_redundant() create my_type @sensitive;


-- TEST: just verify this is correct
-- + {declare_named_type}: text notnull
-- + {name text_nn}: text notnull
-- - error:
type text_nn text not null;

-- TEST: short form to declare a type
-- + {declare_named_type}: text notnull
-- + {name type_short_form}: text notnull
-- - error:
type type_short_form text not null;

-- TEST: try to add not null more than once, force the error inside of sensitive ast
-- + error: % an attribute was specified twice 'not null'
-- + {declare_vars_type}: err
-- +1 error:
declare nn_var_redundant text_nn not null @sensitive;

-- TEST: ok to add @sensitive
-- + {declare_vars_type}: text notnull sensitive
-- + {name_list}: nn_var_sens: text notnull variable init_required sensitive
-- - error:
declare nn_var_sens text_nn @sensitive;

-- TEST: declare type using another declared type
-- + TYPE my_type_1 TEXT @SENSITIVE;
-- - error:
type my_type_1 my_type;

-- TEST: declare type using another declared type
-- + TYPE my_type_2 TEXT @SENSITIVE;
-- - error:
type my_type_2 my_type_1;

-- TEST: declare type using another declared type
-- + error: % unknown type 'bogus_type'
-- + {declare_named_type}: err
-- +1 error:
type my_type bogus_type;

-- TEST: duplicate declare type definition
-- + error: % conflicting type declaration 'my_type'
-- + {declare_named_type}: err
-- extra error line for the two conflicting types
-- +3 error:
type my_type integer;

-- TEST: use declared type in variable declaration
-- + DECLARE my_var TEXT @SENSITIVE;
-- + {declare_vars_type}: text sensitive
-- - error:
declare my_var my_type;

-- TEST: use bogus declared type in variable declaration
-- + error: % unknown type 'bogus_type'
-- + {declare_vars_type}: err
-- + {name bogus_type}: err
-- +1 error:
declare my_var bogus_type;

-- TEST: create local named type with same name. the local type have priority
-- + TYPE my_type INT;
-- + DECLARE my_var INT;
-- + {create_proc_stmt}: ok
proc named_type ()
begin
  type my_type integer;
  declare my_var my_type;
end;

-- TEST: declare a sensitive and not null type
-- + TYPE my_type_sens_not TEXT! @SENSITIVE;
-- - error:
type my_type_sens_not text not null @sensitive;

-- used in the following test
-- + {declare_proc_stmt}: ok
-- + {name x}: x: text variable in sensitive
-- - error:
declare proc some_proc_with_an_arg_of_a_named_type(x my_type);

-- TEST: redeclaring a proc that uses a named type works as expected
-- + {declare_proc_stmt}: ok
-- + {name x}: x: text variable in sensitive
-- - error:
declare proc some_proc_with_an_arg_of_a_named_type(x my_type);

-- used in the following tests
-- + {name some_group_var1}: some_group_var1: text variable sensitive
-- + {name some_group_var2}: some_group_var2: text variable sensitive
-- - error:
group some_group_with_a_var_of_a_named_type
begin
  declare some_group_var1 my_type;
  declare some_group_var2 text @sensitive;
end;

-- TEST: redeclaring a group that uses a named type worked as expected; note
-- that the statement list is *not* analyzed in this case
-- + {declare_group_stmt}: ok
-- + {name my_type}
-- + {type_text}
-- - {name some_group_var1}: some_group_var1: text variable sensitive
-- - {name some_group_var2}: some_group_var2: text variable sensitive
-- - error:
group some_group_with_a_var_of_a_named_type
begin
  declare some_group_var1 my_type;
  declare some_group_var2 text @sensitive;
end;

-- TEST: redeclaring a group with named types replaced by that which they alias
-- (and vice versa) also works
-- + {declare_group_stmt}: ok
-- + {type_text}
-- + {name my_type}
-- - {name some_group_var1}: some_group_var1: text variable sensitive
-- - {name some_group_var2}: some_group_var2: text variable sensitive
-- - error:
group some_group_with_a_var_of_a_named_type
begin
  declare some_group_var1 text @sensitive;
  declare some_group_var2 my_type;
end;

-- TEST: redeclaring a group with a bogus named type does not work
-- + Incompatible declarations found
-- +2 error: % GROUP some_group_with_a_var_of_a_named_type
-- + The above must be identical.
-- + error: % variable definitions do not match in group 'some_group_with_a_var_of_a_named_type'
-- +3 error:
group some_group_with_a_var_of_a_named_type
begin
  declare some_group_var1 some_bogus_named_type;
  declare some_group_var2 text @sensitive;
end;

-- TEST: declared type in column definition
-- + id TEXT @SENSITIVE!
-- + {create_table_stmt}: t: { id: text notnull sensitive }
-- + {col_def}: id: text notnull sensitive
-- + {col_def_type_attrs}: ok
-- + {name id}
-- + {type_text}: text
-- + {sensitive_attr}: ok
-- + {col_attrs_not_null}
-- - error:
create table t(id my_type_sens_not);

-- TEST: declared type in column definition with error
-- + error: % unknown type 'bogus_type'
-- + {create_table_stmt}: err
-- + {col_def}: err
-- + {col_def_type_attrs}: err
-- + {name bogus_type}
-- +1 error:
create table t(id bogus_type);

-- TEST: declared type in cast expr
-- + SELECT CAST(1 AS TEXT);
-- + {select_stmt}: _select_: { _anon: text notnull }
-- - error:
select cast(1 as my_type);

-- TEST: declared type in cast expr with error
-- + SELECT CAST(1 AS bogus_type);
-- + error: % unknown type 'bogus_type'
-- + {name bogus_type}: err
-- +1 error:
select cast(1 as bogus_type);

-- TEST: declared type in param
-- + PROC decl_type (label TEXT @SENSITIVE)
-- + {create_proc_stmt}: ok
-- - error:
proc decl_type(label my_type)
begin
end;

-- TEST: declared type in param with error
-- + error: % unknown type 'bogus_type'
-- + {create_proc_stmt}: err
-- + {name bogus_type}: err
-- +1 error:
proc decl_type_err(label bogus_type)
begin
end;

-- TEST: declared type in function
-- + FUNC decl_type_func (arg1 INT) TEXT @SENSITIVE;
-- + {declare_func_stmt}: text sensitive
-- - error:
func decl_type_func (arg1 integer) my_type;

-- TEST: declared type in function with err
-- + FUNC decl_type_func_err (arg1 INT) bogus_type;
-- + error: % unknown type 'bogus_type'
-- + {declare_func_stmt}: err
-- + {name bogus_type}: err
-- +1 error:
func decl_type_func_err (arg1 integer) bogus_type;

create table to_copy(
  f1 integer,
  f2 int!,
  f3 int! @sensitive,
  f4 integer @sensitive
);

-- TEST: ensure all attributes correctly copied
-- + CREATE TABLE the_copy(
-- + f1 INT,
-- + f2 INT!,
-- + f3 INT @SENSITIVE!,
-- + f4 INT @SENSITIVE
-- - error:
create table the_copy(
   like to_copy
);

-- TEST: ensure proc arguments are rewritten correctly
-- + PROC uses_complex_table_attrs (f1_ INT, f2_ INT!, f3_ INT! @SENSITIVE, f4_ INT @SENSITIVE)
-- - error:
proc uses_complex_table_attrs(like to_copy)
begin
end;

-- TEST: ensure proc arguments are rewritten correctly
-- + DECLARE PROC uses_complex_table_attrs (f1_ INT, f2_ INT!, f3_ INT! @SENSITIVE, f4_ INT @SENSITIVE)
-- - error:
declare proc uses_complex_table_attrs(like to_copy);

-- TEST: ensure func arguments are rewritten correctly
-- + FUNC function_uses_complex_table_attrs (f1_ INT, f2_ INT!, f3_ INT! @SENSITIVE, f4_ INT @SENSITIVE) INT;
-- - error:
func function_uses_complex_table_attrs(like to_copy) integer;

-- TEST: ensure cursor includes not-null and sensitive
-- + {declare_cursor_like_name}: complex_attr_cursor: to_copy: { f1: integer, f2: integer notnull, f3: integer notnull sensitive, f4: integer sensitive } variable shape_storage value_cursor
-- - error:
cursor complex_attr_cursor like to_copy;

-- TEST: make a function that creates sensitive
-- + {declare_func_stmt}: object create_func sensitive
-- + {create_data_type}: object create_func sensitive
-- + {sensitive_attr}: object sensitive
-- + {type_object}: object
-- - error:
func maybe_create_func_sensitive() create object @sensitive;

-- TEST: make a function that creates blob
-- + {declare_func_stmt}: blob notnull create_func
-- + {create_data_type}: blob notnull create_func
-- + {notnull}: blob notnull
-- + {type_blob}: blob
-- - error:
func maybe_create_func_blob() create blob not null;

-- TEST: make a function that creates text
-- + {declare_func_stmt}: text create_func
-- + {create_data_type}: text create_func
-- + {type_text}: text
-- - error:
func maybe_create_func_text() create text;

-- TEST: make a function that creates int
-- + error: % Return data type in a create function declaration can only be Text, Blob or Object
-- + {declare_func_stmt}: err
-- + {create_data_type}: err
-- +1 error:
func maybe_create_func_int() create int;

-- TEST: make a function that creates bool
-- + error: % Return data type in a create function declaration can only be Text, Blob or Object
-- + {declare_func_stmt}: err
-- + {create_data_type}: err
-- +1 error:
func maybe_create_func_bool() create bool;

-- TEST: make a function that creates long
-- + error: % Return data type in a create function declaration can only be Text, Blob or Object
-- + {declare_func_stmt}: err
-- + {create_data_type}: err
-- +1 error:
func maybe_create_func_long() create long not null @sensitive;

-- TEST: type a named for object Foo
-- + {declare_named_type}: object<Foo> notnull sensitive
-- + {sensitive_attr}: object<Foo> notnull sensitive
-- + {notnull}: object<Foo> notnull
-- + {type_object}: object<Foo>
-- + {name Foo}
-- - error:
type type_obj_foo object<Foo> not null @sensitive;

-- TEST: declared function that return create object
-- + FUNC type_func_return_create_obj () CREATE OBJECT<Foo>! @SENSITIVE;
-- + {declare_func_stmt}: object<Foo> notnull create_func sensitive
-- - error:
func type_func_return_create_obj() create type_obj_foo;

-- TEST: declared function that return create bogus object
-- + error: % unknown type 'bogus_type'
-- + {declare_func_stmt}: err
-- + {create_data_type}: err
-- +1 error:
func type_func_return_create_bogus_obj() create bogus_type;

-- TEST: declared function that return object
-- + FUNC type_func_return_obj () OBJECT<Foo>! @SENSITIVE;
-- + {declare_func_stmt}: object<Foo> notnull sensitive
-- - error:
func type_func_return_obj() type_obj_foo;

-- TEST: declare type as enum name
-- + TYPE my_enum_type INT<ints>!;
-- + {declare_named_type}: integer<ints> notnull
-- + {notnull}: integer<ints> notnull
-- - error:
type my_enum_type ints;

-- TEST: used a named type's name to declare an enum
-- + error: % conflicting type declaration 'my_type'
-- + {declare_enum_stmt}: err
-- additional errors for the two conflicting lines
-- +3 error:
enum my_type integer (
 negative_one = -1,
 postive_one = 1
);

-- TEST: make x coordinate for use later, validate that it has a kind
-- + {type_int}: integer<x_coord>
-- - error:
declare x1, x2, x3 integer<x_coord>;

-- TEST: make x coordinate for use later, validate that it has a kind
-- + {type_int}: integer<y_coord>
-- - error:
declare y1, y2, y3 integer<y_coord>;

-- TEST: try to assign an x to a y
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- +1 error:
set x1 := y1;

-- TEST: try to assign an x to a y
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- +1 error:
set x1 := y1;

-- TEST: try to add and x and a y
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {add}: err
-- + {name x1}: x1: integer<x_coord> variable
-- + {name y1}: err
-- +1 error:
set x1 := x1 + y1;

-- TEST: this is ok, it's still an x
-- + {mul}: integer<x_coord>
-- - error:
set x1 := x1 * 2;

-- TEST: this is ok, it's still an x
-- + {add}: integer<x_coord>
-- - error:
set x1 := x1 + x2;

declare bb bool;

-- TEST: this is ok, comparison of same types (equality)
-- + {eq}: bool
-- - error:
set bb := x1 = x2;

-- TEST: this is ok, comparison of same types (inequality)
-- + {lt}: bool
-- - error:
set bb := x1 < x2;

-- TEST: comparison of two incompatible types (equality)
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {eq}: err
-- +1 error:
set bb := x1 = y1;

-- TEST: comparison of two incompatible types (inequality)
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {lt}: err
-- +1 error:
set bb := x1 < y1;

-- TEST: make an alias for an integer with kind (x)
-- + {declare_named_type}: integer<x_coord>
-- + {name _x}: integer<x_coord>
-- + {type_int}: integer<x_coord>
-- + {name x_coord}
-- - error:
type _x integer<x_coord>;

-- TEST: make an alias for an integer with kind (y)
-- + {name y_coord}
-- - error:
type _y integer<y_coord>;

-- TEST: type an integer with the alias
-- + DECLARE x4 INT<x_coord>;
-- + {declare_vars_type}: integer<x_coord>
-- + {name_list}: x4: integer<x_coord> variable
-- + {name x4}: x4: integer<x_coord> variable
-- + {type_int}: integer<x_coord>
-- + {name x_coord}
-- - error:
declare x4 _x;

-- TEST: use the named type version, should be the same
-- + {assign}: x1: integer<x_coord> variable
-- + {name x1}: x1: integer<x_coord> variable
-- + {name x4}: x4: integer<x_coord> variable
-- - error:
set x1 := x4;

-- TEST: make a table that has mixed kinds
-- + {create_table_stmt}: xy: { x: integer<x_coord>, y: integer<y_coord> }
-- + {col_def}: x: integer<x_coord>
-- + {col_def}: y: integer<y_coord>
create table xy(
  x _x,
  y _y
);

-- TEST: valid insert the kinds match
-- + {insert_stmt}: ok
-- + {name xy}: xy: { x: integer<x_coord>, y: integer<y_coord> }
-- - error:
insert into xy using x1 x, y1 y;

-- TEST: invalid insert the kinds don't match (y1 is not an xcoord)
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {insert_stmt}: err
-- +1 error:
insert into xy using y1 x, x1 y;

-- TEST: insert into the table with matching coordinates
-- + {insert_stmt}: ok
-- + {name xy}: xy: { x: integer<x_coord>, y: integer<y_coord> }
insert into xy select xy.x, xy.y from xy where xy.x = 1;

-- TEST: insert into the table with coordinates reversed (error)
-- + error: % expressions of different kinds can't be mixed: 'y_coord' vs. 'x_coord'
-- + {insert_stmt}: err
-- +1 error:
insert into xy select xy.y, xy.x from xy where xy.x = 1;

-- TEST: compound select with matching object kinds (use as to make the names match)
-- +  {select_stmt}: UNION ALL: { x: integer<x_coord>, y: integer<y_coord> }
-- - error:
select x1 as x, y1 as y
union all
select x2 as x, y2 as y;

-- TEST: compound select with not matching object kinds (as makes the name match)
-- but the kind is wrong so you still get an error (!)
-- + error: % expressions of different kinds can't be mixed: 'y_coord' vs. 'x_coord'
-- + {select_stmt}: err
-- +1 error:
select x1 as x, y1 as y
union all
select y2 as x, x2 as y;

-- TEST: insert into xy with values, kinds are ok
-- + {insert_stmt}: ok
-- - error:
insert into xy values (x1, y1), (x2, y2);

-- TEST: insert into xy with values, kinds are ok
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {insert_stmt}: err
-- +1 error:
insert into xy values
  (x1, y1),
  (y2, x2),
  (x3, y3);

-- TEST: cursor should have the correct shape including kinds
-- + {declare_cursor_like_name}: xy_curs: xy: { x: integer<x_coord>, y: integer<y_coord> } variable shape_storage value_cursor
cursor xy_curs like xy;

-- TEST: fetch cursor, ok, kinds match
-- + {fetch_values_stmt}: ok
-- + {name xy_curs}: xy_curs: xy: { x: integer<x_coord>, y: integer<y_coord> } variable shape_storage value_cursor
-- - error:
fetch xy_curs from values (x1, y1);

-- TEST: fetch cursor but kinds do not match
-- + error: % expressions of different kinds can't be mixed: 'y_coord' vs. 'x_coord'
-- +1 error:
fetch xy_curs from values (y1, x1);

-- some variables of a different type
-- - error:
declare v1, v2, v3 integer<v>;

-- TEST: when with matching variable kinds this is ok, it's x1 or x1
-- + {assign}: x1: integer<x_coord> variable
-- + {name x1}: x1: integer<x_coord> variable
-- + {case_expr}: integer<x_coord>
-- - error:
set x1 := case when 1 then x1 else x1 end;

-- TEST: when with non-matching variable x and y mixed
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {case_expr}: err
-- +1 error:
set x1 := case when 1 then x1 else y1 end;

-- TEST: case expressions match (x and x), this is ok
-- + {assign}: v1: integer<v> variable
-- + {name v1}: v1: integer<v> variable
-- - error:
set v1 := case x1 when x2 then v1 else v2 end;

-- TEST: invalid mixing of x and y in the when expression
-- note extra line breaks to ensure any reported errors are on different lines for help with diagnosis
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {case_expr}: err
-- +1 error:
set v1 := case x1
               when x2
               then v1
               when y1
               then v2
               else v3
               end;

-- TEST: need a bool for the subsequent stuff
-- - error:
declare b0 bool;

-- TEST: in expression has valid kinds, no problem here
-- + {assign}: b0: bool variable
-- + {in_pred}: bool
-- + {name x1}: x1: integer<x_coord> variable
-- + {expr_list}: x1: integer<x_coord> variable
-- + {expr_list}: x2: integer<x_coord> variable
-- + {expr_list}: x3: integer<x_coord> variable
-- - error:
set b0 := x1 in (x1, x2, x3);

-- TEST: in expression has mixed kinds
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {in_pred}: err
-- +1 error:
set b0 := x1 in (x1, y2, x3);

-- TEST: in expression using select
-- + {assign}: b0: bool variable
-- + {in_pred}: bool
-- + {select_stmt}: x2: integer<x_coord> variable
set b0 := (select x1 in (select x2));

-- TEST: in expression using select, but select result is the wrong kind
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {in_pred}: err
-- + {select_stmt}: err
-- + {select_core_list}: _select_: { y1: integer<y_coord> variable }
-- +1 error:
set b0 := (select x1 in (select y1));

-- TEST: between with kinds, all matching
-- + {assign}: b0: bool variable
-- + {between_rewrite}: bool
-- - error:
set b0 := x1 between x2 and x3;

-- TEST: left between operand is of the wrong kind
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {between}: err
-- +1 error:
set b0 := x1 between y2 and 12;

-- TEST: right between operand is of the wrong kind
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {between}: err
-- +1 error:
set b0 := x1 between 34 and y3;

-- TEST: left and right could be used but they don't match each other
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {between}: err
-- +1 error:
set b0 := 56 between x2 and y3;

-- TEST: negation preserves the kind, kind ok so this works
-- +  {assign}: x1: integer<x_coord> variable
-- +  | {name x1}: x1: integer<x_coord> variable
-- +  | {uminus}: integer<x_coord>
set x1 := -x2;

-- TEST: negation preserves the kind, hence we get an error
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {uminus}: err
-- +1 error:
set x1 := -y1;

-- TEST: coalesce compatible kinds (should preserve kind)
-- + {assign}: x1: integer<x_coord> variable
-- + {call}: integer<x_coord>
-- - error:
set x1 := coalesce(x1, x2, x3);

-- TEST: coalesce incompatible kinds (should preserve kind)
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {call}: err
-- +1 error:
set x1 := coalesce(x1, y2, x3);

-- TEST: cast ok direct conversion
-- + {assign}: x1: integer<x_coord> variable
-- + {name x1}: x1: integer<x_coord> variable
-- + {cast_expr}: integer<x_coord>
-- - error:
set x1 := cast(y1 as integer<x_coord>);

-- TEST: cast ok direct conversion (using type name) (check for rewrite too)
-- + SET x1 := CAST(y1 AS INT<x_coord>);
-- + {assign}: x1: integer<x_coord> variable
-- + {name x1}: x1: integer<x_coord> variable
-- + {cast_expr}: integer<x_coord>
-- - error:
set x1 := cast(y1 as _x);

-- TEST: cast ok, strip kind explicitly
-- + {assign}: x1: integer<x_coord> variable
-- + {name x1}: x1: integer<x_coord> variable
-- + {cast_expr}: integer
-- + {name y1}: y1: integer<y_coord> variable
-- - error:
set x1 := cast(y1 as integer);

-- TEST: cast bad, kinds don't match now
-- + error: % expressions of different kinds can't be mixed: 'x_coord' vs. 'y_coord'
-- + {assign}: err
-- + {name x1}: x1: integer<x_coord> variable
-- +1 error:
set x1 := cast(x1 as integer<y_coord>);

-- TEST: ensure that ifnull parses properly after else, it's not "else if"
-- + SELECT CASE
-- + WHEN 1 THEN 2
-- + ELSE ifnull(x, y)
-- + END;
-- + {call}: integer
-- + {name ifnull}
-- - error:
select case when 1 then 2 else ifnull(x, y) end;

-- TEST: hidden ignored on non-virtual tables
-- + {create_table_stmt}: hidden_ignored_on_normal_tables: { x: integer notnull, y: integer }
-- - error:
create table hidden_ignored_on_normal_tables(
  x integer hidden not null,
  y integer
);

-- TEST: hidden applied on virtual tables
-- + {create_table_stmt}: virtual_with_hidden: { x: integer notnull hidden_col, y: integer } virtual @recreate
-- - error:
create virtual table virtual_with_hidden using module_name as (
  x integer hidden not null,
  y integer
);

-- TEST: hidden applied on virtual tables
-- + error: % HIDDEN column attribute must be the first attribute if present
-- +1 error:
create virtual table virtual_with_hidden_wrong using module_name as (
  x int! hidden,
  y integer
);

-- TEST: save the current state
-- + {enforce_push_stmt}: ok
-- - error:
@enforce_push;

-- force this on so we can verify that it is turned off
@enforce_strict foreign key on update;

-- get to a known state
-- + {enforce_reset_stmt}: ok
-- - error:
@enforce_reset;

-- TEST: fk enforcement should be off
-- + {create_table_stmt}: fk_strict_err_0: { id: integer foreign_key }
-- - error:
create table fk_strict_err_0 (
  id integer REFERENCES foo(id)
);

-- TEST: save the current state again
-- + {enforce_push_stmt}: ok
-- - error:
@enforce_push;

@enforce_strict foreign key on update;

-- TEST: enforcement should be on
-- + error: % strict FK validation requires that some ON UPDATE option be selected for every foreign key
-- +1 error:
create table fk_strict_err_1 (
  id integer REFERENCES foo(id)
);

-- TEST: restore the previous state
-- + {enforce_pop_stmt}: ok
-- - error:
@enforce_pop;

-- TEST: enforcement should be off
-- + {create_table_stmt}: fk_strict_err_2: { id: integer foreign_key }
-- - error:
create table fk_strict_err_2 (
  id integer REFERENCES foo(id)
);

-- TEST: restore the state before our first push
-- + {enforce_pop_stmt}: ok
-- - error:
@enforce_pop;

-- TEST: pop too many enforcement options off the stack
-- + error: % @enforce_pop used but there is nothing to pop
-- + {enforce_pop_stmt}: err
-- +1 error:
@enforce_pop;

-- TEST: verify strict mode
-- + {enforce_strict_stmt}: ok
-- - error:
@enforce_strict transaction;

-- TEST: transactions disallowed in strict mode
-- + error: % transaction operations disallowed while STRICT TRANSACTION enforcement is on.
-- +1 error:
-- + {begin_trans_stmt}: err
begin transaction;

-- TEST: verify back to normal mode
-- + {enforce_normal_stmt}: ok
-- - error:
@enforce_normal transaction;

-- TEST: transactions ok again
-- + {begin_trans_stmt}: ok
-- - error:
begin transaction;

-- TEST: strict if nothing then
-- + {enforce_strict_stmt}: ok
-- - error:
@enforce_strict select if nothing;

-- TEST: normal select is disallowed
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- + {assign}: err
-- + {select_stmt}: err
-- +1 error:
set price_d := (select id from foo);


-- TEST: nested select in SQL (e.g. correlated subquery) is ok even in strict select if nothing then mode
-- + SELECT ( SELECT 1 );
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- - error:
select (select 1);

-- TEST: select if nothing then is allowed
-- - error:
set price_d := (select 1 if nothing then -1);

-- TEST: select if nothing or null then is allowed
-- - error:
set price_d := (select 1 if nothing or null then -1);

-- TEST: select nothing or null null is redundant
-- + error: % SELECT ... IF NOTHING OR NULL THEN NULL is redundant; use SELECT ... IF NOTHING THEN NULL instead
-- + {assign}: err
-- + {select_if_nothing_or_null_expr}: err
-- +1 error:
set price_d := (select 1 if nothing or null then null);

-- TEST: select nothing or null some_nullable is okay
-- + {select_if_nothing_or_null_expr}: integer
-- - error:
set price_d := (select 1 if nothing or null then (select null or 1));

-- TEST: nested select is not allowed either
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- + {assign}: err
-- + {select_stmt}: err
-- +1 error:
set price_d := (select 1 if nothing then (select id from foo));

-- TEST: nested select is ok if it has no from clause
-- - error:
set price_d := (select 1 if nothing then (select 1));

-- TEST: explicit if nothing then throw is ok
-- + {select_if_nothing_throw_expr}: id: integer notnull
-- - error:
set price_d := (select id from foo if nothing then throw);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - count
-- - error:
let val_count := (select count(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - total
-- - error:
let val_total := (select total(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - avg
-- - error:
let val_avg := (select avg(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - sum
-- - error:
let val_sum := (select sum(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - group_concat
-- - error:
let val_group_concat := (select group_concat(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - max
-- - error:
let val_max := (select max(1) from foo where 0);

--- TEST: IF NOTHING requirement not enforced for built-in aggregate function - min
-- - error:
let val_min := (select min(1) from foo where 0);

--- TEST: IF NOTHING requirement is enforced for multi-argument scalar function max
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_max := (select max(1, 2, 3) from foo where 0);

--- TEST: IF NOTHING requirement is enforced for multi-argument scalar function min
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_min := (select min(1, 2, 3) from foo where 0);

--- TEST: IF NOTHING requirement is enforced for built-in aggregate functions when GROUP BY is used - min
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_min := (select min(1) from foo where 0 group by id);

--- TEST: IF NOTHING requirement is enforced for built-in aggregate functions when GROUP BY is used - sum
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_sum := (select sum(1) from foo where 0 group by id);

--- TEST: IF NOTHING requirement is enforced for built-in aggregate functions when a LIMIT less than one is used (and expression within LIMIT is evaluated)
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_avg := (select avg(id) col from foo limit 1 - 1);

--- TEST: IF NOTHING requirement is enforced for built-in aggregate functions when a  LIMIT using a variable (and expression within LIMIT is evaluated)
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
proc val_avg_proc(lim integer)
begin
  let val_avg := (select avg(id) col from foo limit lim);
end;

--- TEST: No IF NOTHING requirement is imposed for built-in aggregate functions when a  LIMIT is 1 or bigger (and expression within LIMIT is evaluated)
-- - error:
set val_avg := (select avg(id) col from foo limit (2 + 4 * 10));

--- TEST: IF NOTHING requirement is enforced for built-in aggregate functions when OFFSET is used
-- + error: % strict select if nothing requires that all (select ...) expressions include 'if nothing'
-- +1 error:
set val_avg := (select avg(id) col from foo limit (2 + 4 * 10) offset 1);

-- TEST: normal if nothing then
-- + {enforce_normal_stmt}: ok
-- - error:
@enforce_normal select if nothing;

-- TEST: simple select with else
-- + {assign}: price_d: real<dollars> variable
-- + {select_if_nothing_expr}: real notnull
-- + {select_stmt}: _anon: integer notnull
-- + {dbl 2.0}: real notnull
-- - error:
set price_d := (select 1 if nothing then 2.0);

-- TEST: simple select with else (upgrade from the left)
-- + {assign}: price_d: real<dollars> variable
-- + {select_if_nothing_expr}: real notnull
-- + {select_stmt}: _anon: real notnull
-- + {int 4}: integer notnull
-- - error:
set price_d := (select 3.0 if nothing then 4);

-- TEST: simple select with else (upgrade from the left)
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {assign}: err
-- + {select_if_nothing_expr}: err
-- + {select_stmt}: _anon: real notnull
-- + {name price_e}: price_e: real<euros> variable
-- +1 error:
set price_d := (select 3.0 if nothing then price_e);

-- TEST: simple select with else (upgrade from the left)
-- + error: % expressions of different kinds can't be mixed: 'dollars' vs. 'euros'
-- + {assign}: err
-- + {select_if_nothing_expr}: err
-- + {select_stmt}: price_d: real<dollars> variable
-- + {name price_e}: err
-- +1 error:
set my_real := (select price_d if nothing then price_e);

-- TEST: simple select with else (upgrade from the left)
-- + error: % required 'TEXT' not compatible with found 'REAL' context 'IF NOTHING OR NULL'
-- + {assign}: err
-- + {select_if_nothing_or_null_expr}: err
-- + {select_stmt}: _anon: text notnull
-- + {name price_e}: price_e: real<euros> variable
-- +1 error:
set price_d := (select "x" if nothing or null then price_e);

-- TEST: simple select with else (upgrade from the left)
-- + error: % right operand cannot be an object in 'IF NOTHING OR NULL'
-- + {assign}: err
-- + {select_if_nothing_or_null_expr}: err
-- + {select_stmt}: _anon: text notnull
-- + {name obj_var}: obj_var: object variable
-- +1 error:
set price_d := (select "x" if nothing or null then obj_var);

-- - error:
declare real_nn real!;

-- TEST: if nothing or null then gets not null result if right side is not null
-- +  {assign}: real_nn: real notnull variable
-- + {select_if_nothing_or_null_expr}: real notnull
-- + {select_stmt}: my_real: real variable
-- + {dbl 1.0}: real notnull
-- - error:
set real_nn := (select my_real if nothing or null then 1.0);

-- TEST: if nothing then does NOT get not null result if only right side is not null
-- + error: % cannot assign/copy possibly null expression to not null target 'real_nn'
-- + {assign}: err
-- +1 error:
set real_nn := (select my_real if nothing then 1.0);

-- TEST: error inside the operator should prop out
-- + error: % string operand not allowed in 'NOT'
-- + {assign}: err
-- + {select_if_nothing_expr}: err
-- +1 error:
set real_nn := (select not 'x' if nothing then 1.0);

-- TEST: error inside of any other DML
-- + error: % (SELECT ... IF NOTHING) construct is for use in top level expressions, not inside of other DML
-- + {select_stmt}: err
-- +1 error:
select (select 0 if nothing then -1);

-- TEST: error inside of any other DML
-- + error: % (SELECT ... IF NOTHING) construct is for use in top level expressions, not inside of other DML
-- + {delete_stmt}: err
-- +1 error:
delete from foo where id = (select 33 if nothing then 0);

-- TEST: nested select with count will be not null because count must return a row
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- - error:
select (select count(*) from foo where 0);

-- TEST: nested select with select * is not examined for not nullness, but no crashes or anything
-- +  {select_stmt}: _select_: { x: integer }
-- - error:
select (select * from (select 1 x) T);

-- TEST: sum can return null, that's not a special case (sum(id) is weird but whatever)
-- + {select_stmt}: _select_: { _anon: integer }
-- - error:
select (select sum(id) from foo where 0);

-- TEST: any non aggregate with a where clause might be null
-- + {select_stmt}: _select_: { _anon: integer }
-- - error:
select (select 1+3 where 0);

-- TEST: with form is not simple, it doesn't get the treatment
-- + {select_stmt}: _select_: { x: integer }
-- - error:
select (with y(*) as (select 1 x) select * from y);

-- TEST: compound form is not simple, it doesn't get the treatment
-- + {select_stmt}: _select_: { x: integer }
-- - error:
select (select 1 union all select 2) as x;

@enforce_strict insert select;

-- TEST: ok to insert with a simple select
-- + {insert_stmt}: ok
-- - error:
insert into foo(id)
  select 1;

-- TEST: top level compound select not ok
-- + error: % due to a memory leak bug in old SQLite versions,
-- + {insert_stmt}: err
-- +1 error:
insert into foo(id)
  select 1 union all select 1;

-- TEST: top level join not ok
-- + error: % due to a memory leak bug in old SQLite versions,
-- + {insert_stmt}: err
-- +1 error:
insert into foo(id)
  select 1 from
    (select 1) as T1 inner join (select 2) as T2;

-- TEST: WITH inside the insert is ok too if it has no join
-- + {insert_stmt}: ok
-- - error:
insert into foo(id)
  with cte(id) as ( select 1)
    select * from cte;

-- TEST: values are ok
-- + {insert_stmt}: ok
-- - error:
insert into foo(id)
  values (1), (2), (3);

@enforce_normal insert select;

@enforce_strict table function;

-- TEST: TVF in inner join is ok
-- + {select_stmt}: _select_: { id: integer notnull, foo: text }
-- - error:
select * from foo inner join tvf(1);

-- TEST: TVF on right of left join is an error
-- + error: % table valued function used in a left/right/cross context; this would hit a SQLite bug.  Wrap it in a CTE instead.
-- + {select_stmt}: err
-- +1 error:
select * from foo left join tvf(1);

-- TEST: TVF on left of right join is an error
-- note SQLite doesn't support right join yet so this won't ever run
-- + error: % table valued function used in a left/right/cross context; this would hit a SQLite bug.  Wrap it in a CTE instead.
-- + {select_stmt}: err
-- +1 error:
select * from tvf(1) right join foo;

-- TEST: non TVF cross join is ok
-- + {select_stmt}: _select_: { id: integer notnull, id: integer notnull }
-- - error:
select * from foo T1 cross join foo T2;

@enforce_normal table function;

-- TEST: LET stmt, int
-- + {let_stmt}: int_var: integer notnull variable
-- + {name int_var}: int_var: integer notnull variable
-- - error:
LET int_var := 1;

-- TEST: LET stmt, long
-- + {let_stmt}: long_var: longint notnull variable
-- + {name long_var}: long_var: longint notnull variable
-- - error:
LET long_var := 1L;

-- TEST: LET stmt, real with kind
-- + {let_stmt}: price_dd: real<dollars> variable
-- + {name price_dd}: price_dd: real<dollars> variable
-- - error:
LET price_dd := price_d;

-- TEST: LET stmt, bool
-- + {let_stmt}: bool_var: bool notnull variable
-- + {name bool_var}: bool_var: bool notnull variable
-- - error:
LET bool_var := 1=1;

-- TEST: LET stmt, bool
-- + {let_stmt}: pen_var: real<real_things> notnull variable
-- + {name pen_var}: pen_var: real<real_things> notnull variable
-- - error:
LET pen_var := real_things.pen;

-- TEST: create function -> extra bits should be stripped
-- - {let_stmt}: created_obj: object notnull variable create_func
-- - {name created_obj}: created_obj: object notnull variable create_func
-- + {let_stmt}: created_obj: object notnull variable
-- + {name created_obj}: created_obj: object notnull variable
-- + {call}: object notnull create_func
-- - error:
LET created_obj := creater_func();

-- TEST: LET stmt, NULL (null has no type), this makes a null alias
-- + {let_stmt}: null_alias: null variable
-- - error:
LET null_alias := NULL;

-- TEST: the null alias is rewritten away
-- verify rewrite
-- + LET rewritten_null := price_d IS NULL;
-- - error:
let rewritten_null := price_d is null_alias;

-- TEST: no reassignment of a null alias, it's moot
-- + error: % variable of type NULL cannot be assigned 'null_alias'
-- + {assign}: err
-- + {name null_alias}: err
-- +1 error:
null_alias := null;

-- TEST: LET error cases: bad expression
-- + error: % string operand not allowed in 'NOT'
-- + {let_stmt}: err
-- +1 error:
LET bad_result := NOT 'x';

-- TEST: LET error cases: duplicate variable
-- + error: % duplicate variable name in the same scope 'created_obj'
-- + {let_stmt}: err
-- +1 error:
LET created_obj := 1;

-- a not null variable for the switch tests
LET z := 1;

-- TEST: switch statement with bogus expression
-- + error: % string operand not allowed in 'NOT'
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch not 'x'
  when 1 then nothing
end;

-- TEST: switch statement with bogus switch expression
-- + error: % case expression must be a not-null integral type
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch 1.5
  when 1 then nothing
end;

-- TEST: switch statement with when expression of the wrong type
-- + error: % type of a WHEN expression is bigger than the type of the SWITCH expression
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch z
  when 1L then nothing
end;

-- TEST: switch statement with not constant when expression
-- + error: % WHEN expression cannot be evaluated to a constant
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch z
  when 1+x then nothing
end;

-- TEST: switch statement with bogus when expression
-- + error: % string operand not allowed in 'NOT'
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch z
  when not "x" then nothing
end;

-- TEST: switch statement with bogus statement list
-- + error: % string operand not allowed in 'NOT'
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- + {stmt_list}: err
-- +1 error:
switch z
  when 1 then
    if not "x" then end if;
end;

-- TEST: switch statement with no actual code in it
-- + error: % switch statement did not have any actual statements in it
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- + {switch_case}: err
-- +1 error:
switch z
  when 1 then nothing -- no cases with statements
  when 2 then nothing -- no cases with statements
end;

let thing := integer_things.pen;

-- TEST: switch statement combining ALL VALUES and ELSE is a joke
-- + error: % switch ... ALL VALUES is useless with an ELSE clause
-- + {switch_stmt}: err
-- + {int 1}
-- + {switch_body}
-- - {expr_list}: err
-- 2 {expr_list}: ok
-- +1 error:
switch thing all values
  when
    integer_things.pen,
    integer_things.pencil then
    set x := 10;
  when integer_things.paper then
    set x := 20;
  else
    set x := 30;
end;

-- TEST: switch statement with duplicate values
-- + error: % WHEN clauses contain duplicate values '2'
-- + {switch_stmt}: err
-- + {int 1}
-- +1 error:
switch z
  when 1, 2 then
    set x := 10;
  when 2 then
    set x := 20;
  else
    set x := 30;
end;

-- TEST: switch statement with nullable switch expr
-- + error: % case expression must be a not-null integral type
-- + {switch_stmt}: err
-- + {int 0}
-- + {switch_body}
-- +1 error:
switch x
  when 1 then nothing
end;

-- TEST: switch statement that actually works, 3 cases, 3 expressions
-- + {switch_stmt}: ok
-- +2 {expr_list}: ok
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {int 3}: integer notnull
-- no stmt list for "nothing"
-- +2 {stmt_list}: ok
-- - error:
switch z
  when 1, 2 then
    set y := 1;
  when 3 then nothing
  else
    set y := 2;
end;

-- we need this for the "all values" test, it's just a sample enum
enum three_things integer (
  zip = 0, -- an alias
  zero = 0,
  one = 1,
  two = 2,
  _count = 3
);

-- TEST: switch with all values test: all good here
-- + {switch_stmt}: ok
-- +1 {expr_list}: ok
-- - error:
switch three_things.zero all values
  when three_things.zero, three_things.one, three_things.two then set x := 1;
end;

-- TEST: all values used but the expression isn't an enum
-- + error: % SWITCH ... ALL VALUES is used but the switch expression is not an enum type
-- + {switch_stmt}: err
-- +1 error:
switch 1 all values
  when three_things.one, three_things.two then set x := 1;
end;

-- TEST: switch with all values test: three_things.zero is missing
-- + error: % a value exists in the enum that is not present in the switch 'zero'
-- + {switch_stmt}: err
-- +1 error:
switch three_things.zero all values
  when three_things.one, three_things.two then set x := 1;
end;

-- TEST: switch with all values test: three_things.one is missing
-- + error: % a value exists in the enum that is not present in the switch 'one'
-- + {switch_stmt}: err
-- +1 error:
switch three_things.zero all values
  when three_things.zero, three_things.two then set x := 1;
end;

-- TEST: switch with all values test: three_things.two is missing
-- + error: % a value exists in the enum that is not present in the switch 'two'
-- + {switch_stmt}: err
-- +1 error:
switch three_things.zero all values
  when three_things.zero, three_things.one then set x := 1;
end;

-- TEST: switch with all values test: -1 is extra
-- + error: % a value exists in the switch that is not present in the enum '-1'
-- + {switch_stmt}: err
-- +1 error:
switch three_things.zero all values
  when -1, three_things.zero, three_things.one, three_things.two then set x := 1;
end;

-- TEST: switch with all values test: 5 is extra
-- + error: % a value exists in the switch that is not present in the enum '5'
-- + {switch_stmt}: err
-- +1 error:
switch three_things.zero all values
  when three_things.zero, three_things.one, three_things.two, 5 then set x := 1;
end;

-- TEST: checking if something is NULL with '=' is an error
-- + error: % Comparing against NULL always yields NULL; use IS and IS NOT instead
-- + {eq}: err
-- +1 error:
select (1 = NULL);

-- TEST: checking if something is not null with '<>' is an error
-- + error: % Comparing against NULL always yields NULL; use IS and IS NOT instead
-- + {ne}: err
-- +1 error:
select (1 <> NULL);

-- TEST: a select expression with a null type is an error
-- + error: % SELECT expression is equivalent to NULL
-- + {select_expr}: err
-- +1 error:
select (1 + (SELECT NULL));

-- used in the next suite of tests
declare proc out2_proc(x integer, out y int!, out z int!);

-- TEST: try to do declare out on a non-existent procedure
-- + error: % DECLARE OUT requires that the procedure be already declared 'not_defined'
-- + {declare_out_call_stmt}: err
-- +1 error:
declare out call not_defined();

-- TEST: try to call a proc with no out args
-- + error: % DECLARE OUT CALL used on a procedure with no missing OUT arguments 'decl1'
-- + {declare_out_call_stmt}: err
-- +1 error:
declare out call decl1(1);

-- TEST: try to call a proc but the args have errors
-- + error: % string operand not allowed in 'NOT'
-- + error: % additional info: calling 'out2_proc' argument #1 intended for parameter 'x' has the problem
-- + {declare_out_call_stmt}: err
-- +2 error:
proc decl_test_err()
begin
  declare out call out2_proc(not 'x', u, v);
end;

-- TEST: try to call a proc but the proc had errors
-- + error: % procedure had errors, can't call 'decl_test_err'
-- + {declare_out_call_stmt}: err
-- +1 error:
declare out call decl_test_err(1, 2, 3);

-- TEST: try to call a proc but an OUT arg is aliased by an IN arg
-- + error: % OUT or INOUT argument cannot be used again in same call 'u'
-- + {declare_out_call_stmt}: err
-- + {call_stmt}: err
-- +1 error:
declare out call out2_proc(u, u, v);

-- TEST: try to call a proc but an OUT arg is aliased by another OUT arg
-- + error: % OUT or INOUT argument cannot be used again in same call 'u'
-- + {declare_out_call_stmt}: err
-- + {call_stmt}: err
-- +1 error:
declare out call out2_proc(1, u, u);

-- TEST: non-variable out arg in declare out
-- + error: % expected a variable name for OUT or INOUT argument 'y'
-- + {declare_out_call_stmt}: err
-- +1 error:
proc out_decl_test_2(x integer)
begin
  declare out call out2_proc(x, 1+3, v);
end;

-- we need a deleted table for the next test
CREATE TABLE this_table_is_deleted(
  id INT
) @DELETE(1);

-- TEST: it's ok to have an index refer to a deleted table if the index is deleted
-- the index now refers to a stub column, that's ok because we're only generating
-- a drop for this index
-- + CREATE INDEX deleted_index ON this_table_is_deleted (xyx) @DELETE(1);
-- + error: % object is an orphan because its table is deleted. Remove rather than @delete 'deleted_index'
-- + {create_index_stmt}: err
-- +1 error:
CREATE INDEX deleted_index ON this_table_is_deleted (xyx) @DELETE(1);

-- TEST: it's ok to have a trigger be based on a deleted table if the trigger is also deleted
-- + CREATE TRIGGER trigger_deleted
-- + BEFORE DELETE ON this_table_is_deleted
-- + BEGIN
-- + SELECT 1;
-- + END @DELETE(1);
-- + error: % object is an orphan because its table is deleted. Remove rather than @delete 'trigger_deleted'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger trigger_deleted
  before delete on this_table_is_deleted
begin
  select 1;
end @DELETE(1);

-- TEST: standard usage of declare out
-- + {declare_out_call_stmt}: ok
-- + {call_stmt}: ok
-- + {name u}: u: integer notnull variable implicit
-- + {name v}: v: integer notnull variable implicit
-- - error:
proc out_decl_test_3(x integer)
begin
  declare out call out2_proc(x, u, v);
end;

-- + {declare_out_call_stmt}: ok
-- + {call_stmt}: ok
-- +1 {name u}: u: integer notnull variable implicit
-- +1 {name v}: v: integer notnull variable implicit
-- +2 {name u}: u: integer notnull variable
-- +2 {name v}: v: integer notnull variable
-- - error:
proc out_decl_test_4(x integer)
begin
  declare out call out2_proc(x, u, v);
  declare out call out2_proc(x, u, v);
end;

-- TEST: try the select using form
-- we only need to verify the rewrite, all else is normal processing
-- + INSERT INTO with_kind(id, cost, value)
-- +   SELECT 1 AS id, 3.5 AS cost, 4.8 AS value;
-- + {insert_stmt}: ok
-- - error:
insert into with_kind using
  select 1 id, 3.5 cost, 4.8 value;

-- TEST: try the select using form -- anonymous columns not allowed in this form
-- + error: % all columns in the select must have a name
-- + {insert_stmt}: err
-- +1 error:
insert into with_kind using
  select 1, 3.5 cost, 4.8 value;

-- TEST: try the select using form -- errors in the select must prop up
-- + error: % string operand not allowed in 'NOT'
-- + {insert_stmt}: err
-- +1 error:
insert into with_kind using
  select not 'x', 3.5 cost, 4.8 value;

-- TEST: try the select using form (and with clause)
-- we only need to verify the rewrite, all else is normal processing
-- + INSERT INTO with_kind(id, cost, value)
-- + WITH
-- +   goo (x) AS (
-- +     SELECT 1
-- +   )
-- +   SELECT goo.x AS id, 3.5 AS cost, 4.8 AS value
-- +   FROM goo;
-- + {insert_stmt}: ok
-- - error:
insert into with_kind using
   with goo(x) as (select 1)
   select goo.x id, 3.5 cost, 4.8 value from goo;

-- TEST: use built-in migration
-- + {create_table_stmt}: moving_to_recreate: { id: integer } @create(1)
-- + {dot}: ok
-- + {name cql}
-- + {name from_recreate}
-- - error:
create table moving_to_recreate (
 id integer
) @create(1, cql:from_recreate);

-- TEST: try to use some bogus migrator
-- + error: % unknown built-in migration procedure 'cql:fxom_recreate'
-- + {create_table_stmt}: err
-- + {dot}: err
-- +1 error:
create table bogus_builtin_migrator (
 id integer
) @create(1, cql:fxom_recreate);

-- TEST: try to use valid migrator in a column entry instead of the table entry
-- + error: % built-in migration procedure not valid in this context 'cql:from_recreate'
-- + {create_table_stmt}: err
-- + {dot}: err
-- +1 error:
create table bogus_builtin_migrator_placement (
 id integer,
 id2 integer @create(2, cql:from_recreate)
) @create(1);

-- TEST: test sensitive flag on out param in declare proc using transaction
-- + {declare_proc_stmt}: ok dml_proc
-- + {param}: code_: text notnull variable init_required out sensitive
-- - error:
DECLARE PROC proc_as_func(IN transport_key_ TEXT, OUT code_ TEXT! @sensitive) USING TRANSACTION;

-- TEST: test sensitive flag on pr variable for LET stmt
-- + {let_stmt}: pr: text notnull variable sensitive
-- + {name pr}: pr: text notnull variable sensitive
-- + {call}: text notnull sensitive
-- - error:
LET pr := proc_as_func("t");

-- TEST: helper variable
DECLARE pr2 text;

-- TEST: test sensitive flag on pr variable for SET stmt
-- + error: % cannot assign/copy sensitive expression to non-sensitive target 'pr2'
-- + {assign}: err
-- + {call}: text notnull sensitive
-- +1 error:
SET pr2 := proc_as_func("t");

-- TEST: test create table with not null column on conflict clause abort
-- + {create_table_stmt}: conflict_clause_t: { id: integer notnull }
-- + {col_attrs_not_null}: ok
-- + {int 2}
-- - error:
create table conflict_clause_t(id int! on conflict fail);

-- TEST: test create table with pk column on conflict clause rollback
-- + {create_table_stmt}: conflict_clause_pk: { id: integer notnull partial_pk }
-- + {indexed_columns_conflict_clause}
-- + {int 0}
-- - error:
create table conflict_clause_pk(
  id int!,
  constraint pk1 primary key (id) on conflict rollback
);

create table foo(id integer);

-- TEST: Variables can be improved to NOT NULL via a conditional, but only
-- within the body of the THEN.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: x5: integer variable
-- - error:
proc conditionals_improve_nullable_variables()
begin
  declare a int;
  declare b int;
  declare c int;

  let x0 := a;
  if a is not null then
    let x1 := a;
  else
    let x2 := a;
    if a is not null then
      let x3 := a;
    else
      let x4 := a;
    end if;
  end if;
  let x5 := a;
end;

-- TEST: Conditionals only improve along the spine of ANDs.
-- + {declare_cursor}: c0: _select_: { a0: text notnull variable, b0: text variable, c0: text variable }
-- + {declare_cursor}: c1: _select_: { a1: text notnull variable, b1: text variable, c1: text notnull variable } variable dml_proc
-- + {declare_cursor}: c2: _select_: { a2: text notnull variable, b2: text notnull variable, c2: text notnull variable } variable dml_proc
-- - error:
proc conditionals_only_improve_through_ands()
begin
  declare a text;
  declare b text;
  declare c text;

  if a is not null and (b is not null or c is not null) then
    cursor c0 for select a as a0, b as b0, c as c0;
    if (b is not null or a like "hello") and c is not null then
      cursor c1 for select a as a1, b as b1, c as c1;
      if b is not null then
        cursor c2 for select a as a2, b as b2, c as c2;
      end if;
    end if;
  end if;
end;

-- TEST: Nullability improvements for locals cease at corresponding SETs to
-- nullables.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer notnull variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer notnull variable
-- + {let_stmt}: x5: integer variable
-- + {let_stmt}: y5: integer variable
-- + {let_stmt}: x6: integer variable
-- + {let_stmt}: y6: integer variable
-- - error:
proc local_improvements_persist_until_set_to_a_nullable()
begin
  declare a int;
  declare b int;
  let x0 := a;
  let y0 := b;
  if a is not null and b is not null then
    let x1 := a;
    let y1 := b;
    set b := null;
    let x2 := a;
    let y2 := b;
    if b is not null then
      let x3 := a;
      let y3 := b;
      set a := null;
      let x4 := a;
      let y4 := b;
      set b := null;
    end if;
    let x5 := a;
    let y5 := b;
  end if;
  let x6 := a;
  let y6 := b;
end;

-- TEST: SET can improve a type if set to something known to be not null.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- - error:
proc set_can_improve_a_type_if_set_to_something_not_null()
begin
  declare a int;
  let x0 := a;
  set a := 42;
  let x1 := a;
  set a := null;
  let x2 := a;
end;

-- TEST: `x1` should be nullable because `set a := 42` may not have happened.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_added_by_set_do_not_persist_outside_the_statement_list()
begin
  declare a int;
  if 0 then
    set a := 42;
    let x0 := a;
  end if;
  let x1 := a;
end;

-- TEST: `x1` should be nullable because `set a := null` may have happened.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_removed_by_set_do_persist_outside_the_statement_list()
begin
  declare a int;
  if a is not null then
    let x0 := a;
    if 1 then
      set a := null;
    end if;
  end if;
  let x1 := a;
end;

-- TEST: Improvements work in CASE expressions.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: y1: integer variable
-- - error:
proc improvements_work_in_case_expressions()
begin
  declare a int;
  declare b int;

  -- `a` is nonnull when the condition is true
  let x0 :=
    case
      when a is not null then a + a
      else 42
    end;

  -- `b` is nonnull in the last two branches when previous conditions are false
  let y0 :=
    case
      when b is null then 42
      when 0 then b + b
      else b + b
    end;

  -- nullable as the improvements are no longer in effect
  let x1 := a;
  let y1 := b;
end;

-- TEST: Improvements do not work in CASE expressions that match on an
-- expression.
-- + {let_stmt}: x: integer variable
-- - error:
proc improvements_do_not_work_in_case_expressions_with_matching()
begin
  declare a int;
  let x :=
    case false                      -- match the first false expression
      when a is not null then a + a -- actually used when `a` IS null
      else 42
    end;
end;

-- TEST: Improvements work in IIF expressions.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: y1: integer variable
-- - error:
proc improvements_work_in_iif_expressions()
begin
  declare a int;
  declare b int;

  -- `a` is nonnull when the condition is true
  let x0 := iif(a is not null, a + a, 42);

  -- `b` is nonnull when the condition is false
  let y0 := iif(b is null, 42, b + b);

  -- nullable as the improvements are no longer in effect
  let x1 := a;
  let y1 := b;
end;

-- TEST: Used in the following test.
-- - error:
proc sets_out(out a int, out b int)
begin
end;

-- TEST: Nullability improvements for locals persist until used as an OUT arg.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer variable
-- - error:
proc local_improvements_persist_until_used_as_out_arg()
begin
  declare a int;
  declare b int;
  declare x int;
  if a is not null and b is not null then
    let x0 := a;
    let y0 := b;
    call sets_out(x, b);
    let x1 := a;
    let y1 := b;
    call sets_out(a, x);
    let x2 := a;
    let y2 := b;
  end if;
  if a is not null and b is not null then
    let x3 := a;
    let y3 := b;
    call sets_out(a, b);
    let x4 := a;
    let y4 := b;
  end if;
end;

-- Used in the following tests.
-- - error:
create table tnull (xn int, yn int);

-- TEST: Nullability improvements for locals cease at corresponding FETCH INTOs.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer variable
-- - error:
proc local_improvements_persist_until_fetch_into()
begin
  declare a int;
  declare b int;
  declare x int;
  cursor c for select * from tnull;
  if a is not null and b is not null then
    let x0 := a;
    let y0 := b;
    fetch c into x, b;
    let x1 := a;
    let y1 := b;
    fetch c into a, x;
    let x2 := a;
    let y2 := b;
  end if;
  if a is not null and b is not null then
    let x3 := a;
    let y3 := b;
    fetch c into a, b;
    let x4 := a;
    let y4 := b;
  end if;
end;

-- We need this for our following tests.
-- - error:
cursor c_global like tnull;

-- TEST: Improvements work for auto cursors.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- - error:
proc improvements_work_for_auto_cursors()
begin
  cursor c for select * from tnull;
  fetch c;
  let x0 := c.xn;
  let y0 := c.yn;
  if c.xn is not null and c.yn is not null then
    let x1 := c.xn;
    let y1 := c.yn;
    fetch c;
    let x2 := c.xn;
    let y2 := c.yn;
  end if;
end;

-- TEST: Improvements work for local auto cursors that do not shadow a global
-- cursor. This test exercises our code that checks whether or not a dot that
-- has been found should be tracked as a global. There is no global cursor named
-- `c0`, so it must be local and can be improved.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- - error:
proc improvements_work_for_local_auto_cursors_that_do_not_shadow_a_global()
begin
  cursor c_local like tnull;
  fetch c_local from values (0, 0);
  let x0 := c_local.xn;
  let y0 := c_local.yn;
  if c_local.xn is not null and c_local.yn is not null then
    let x1 := c_local.xn;
    let y1 := c_local.yn;
    fetch c_local from values (0, 0);
    let x2 := c_local.xn;
    let y2 := c_local.yn;
  end if;
end;

-- TEST: Improvements work for local auto cursors that shadow a global cursor
-- (in this case, `c_global`). This test exercises our code that checks whether
-- or not a dot that has been found should be tracked as a global. There is a
-- global cursor named `c_global`, but it's not the same one as the one in the
-- nearest enclosing scope that we want to improve here, so we can do the
-- improvement.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- - error:
proc improvements_work_for_auto_cursors_that_shadow_a_global()
begin
  cursor c_global like select nullable(1) as xn, nullable(2) as yn;
  fetch c_global from values (0, 0);
  let x0 := c_global.xn;
  let y0 := c_global.yn;
  if c_global.xn is not null and c_global.yn is not null then
    let x1 := c_global.xn;
    let y1 := c_global.yn;
    fetch c_global from values (0, 0);
    let x2 := c_global.xn;
    let y2 := c_global.yn;
  end if;
end;

-- TEST: Improvements work for global auto cursors.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer variable
-- - error:
proc improvements_work_for_global_auto_cursors()
begin
  fetch c_global from values (0, 0);
  let x0 := c_global.xn;
  let y0 := c_global.yn;
  if c_global.xn is not null and c_global.yn is not null then
    -- improved due to true condition
    let x1 := c_global.xn;
    let y1 := c_global.yn;
    fetch c_global from values (0, 0);
    -- un-improved due to fetch
    let x2 := c_global.xn;
    let y2 := c_global.yn;
    if c_global.xn is null or c_global.yn is null return;
    -- improved due to false condition
    let x3 := c_global.xn;
    let y3 := c_global.yn;
    call proc1();
    -- un-improved due to procedure call
    let x4 := c_global.xn;
    let y4 := c_global.yn;
  end if;
end;

-- TEST: Improvements work on IN arguments.
-- + {let_stmt}: x: integer notnull variable
-- - error:
proc improvements_work_for_in_args(a int)
begin
  if a is not null then
    let x := a;
  end if;
end;

-- Used in the following test.
-- - error:
proc requires_notnull_out(OUT a INT!)
begin
end;

-- TEST: Improvements do NOT work for OUT arguments.
-- + error: % proc out parameter: arg must be an exact type match (even nullability) (expected integer notnull; found integer) 'a'
-- + error: % additional info: calling 'requires_notnull_out' argument #1 intended for parameter 'a' has the problem
-- + {call_stmt}: err
-- +2 error:
proc improvements_do_not_work_for_out()
begin
  declare a int;
  if a is not null then
    call requires_notnull_out(a);
  end if;
end;

-- Used in the following test.
-- - error:
proc requires_notnull_inout(INOUT a INT!)
begin
end;

-- TEST: Improvements do NOT work for INOUT arguments.
-- + error: % cannot assign/copy possibly null expression to not null target 'a'
-- + error: % additional info: calling 'requires_notnull_inout' argument #1 intended for parameter 'a' has the problem
-- + {call_stmt}: err
-- +2 error:
proc improvements_do_not_work_for_inout()
begin
  declare a int;
  if a is not null then
    call requires_notnull_inout(a);
  end if;
end;

-- TEST: Improvements work in SQL.
-- + {create_proc_stmt}: improvements_work_in_sql: { b: integer notnull } dml_proc
-- - error:
proc improvements_work_in_sql()
begin
  declare a int;
  if a is not null then
    select (1 + a) as b;
  end if;
end;

-- TEST: Improvements are not applied if an id or dot is not the entirety of the
-- expression left of IF NOT NULL.
-- + {let_stmt}: b: integer variable
-- - error:
proc improvements_are_not_applied_if_not_an_id_or_dot()
begin
  declare a int;
  if a + 1 is not null then
    let b := a;
  end if;
end;

-- Used in the following test.
-- - error:
declare some_global int;

-- Used in the following test.
-- - error:
proc requires_not_nulls(a int!, b int!, c int!)
begin
end;

-- Used in the following test.
-- - error:
proc returns_int_not_null(out a int!)
begin
end;

-- TEST: Improvements work for globals.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer notnull variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: x5: integer notnull variable
-- + {let_stmt}: x6: integer variable
-- + {let_stmt}: x7: integer notnull variable
-- + {let_stmt}: x8: integer variable
-- + {let_stmt}: x9: integer notnull variable
-- + {let_stmt}: x10: integer notnull variable
-- + {let_stmt}: x11: integer variable
-- + {let_stmt}: x12: integer notnull variable
-- + {let_stmt}: x13: integer variable
-- - error:
proc improvements_work_for_globals()
begin
  if some_global is not null then
    -- `some_global` is improved here.
    let x0 := some_global;
    -- Both uses are improved here because we have yet to encounter a call to a
    -- stored procedure.
    let x1 := iif(0, some_global, some_global);
    -- It's still improved after calling an external function (which cannot
    -- mutate a global).
    call some_external_thing();
    let x2 := some_global;
    -- The same is true for built-in functions.
    select round(4.2) as a;
    let x3 := some_global;
    -- After calling a stored procedure, it's no longer improved.
    call proc1();
    let x4 := some_global;
    -- Re-improve the global.
    if some_global is null return;
    let x5 := some_global;
    -- This type checks because it remains improved until after the call.
    call requires_not_nulls(some_global, some_global, some_global);
    -- Now, however, it is un-improved due to the call.
    let x6 := some_global;
    -- Re-improve the global.
    if some_global is null return;
    let x7 := some_global;
    -- Here, the result is nullable because calls in previous subexpressions
    -- un-improve, as well.
    let x8 := returns_int_not_null() + some_global;
    -- Re-improve the global.
    if some_global is null return;
    let x9 := some_global;
    -- In contrast, here the result is nonnull despite the call in a previous
    -- subexpression due to branch-independent analysis.
    let x10 := iif(0, returns_int_not_null(), some_global);
    -- Fetching from a procedure will also invalidate the improvement.
    cursor c fetch from call out_cursor_proc();
    let x11 := some_global;
    -- Re-improve the global.
    if some_global is null return;
    let x12 := some_global;
  end if;

  -- Finally, `some_global` is nullable as the scope in which it was improved
  -- has ended.
  let x13 := some_global;
end;

-- TEST: Improvements work on columns resulting from a select *.
-- + {create_proc_stmt}: improvements_work_for_select_star: { xn: integer, yn: integer notnull } dml_proc
-- - error:
proc improvements_work_for_select_star()
begin
  select * from tnull where yn is not null;
end;

-- Used in the following tests.
-- - error:
create table another_table_with_nullables (xn integer, zn integer);

-- TEST: Improvements work on columns resulting from a SELECT table.*.
-- + {create_proc_stmt}: improvements_work_for_select_table_star: { xn: integer notnull, yn: integer notnull, xn0: integer, zn: integer notnull } dml_proc
-- - error:
proc improvements_work_for_select_table_star()
begin
  select
    tnull.*,
    another_table_with_nullables.xn as xn0,
    another_table_with_nullables.zn
  from tnull
  inner join another_table_with_nullables
  on tnull.xn = another_table_with_nullables.xn
  where tnull.xn is not null and yn is not null and zn is not null;
end;

-- TEST: Improvements work for select expressions.
-- + {create_proc_stmt}: improvements_work_for_select_expressions: { xn: integer notnull, yn: integer notnull } dml_proc
-- - error:
proc improvements_work_for_select_expressions()
begin
  select xn, yn from tnull where xn is not null and yn is not null;
end;

-- TEST: Improvements correctly handle nested selects.
-- + {create_proc_stmt}: improvements_correctly_handle_nested_selects: { xn: integer notnull, yn: integer, yn0: integer, yn1: integer notnull } dml_proc
-- - error:
proc improvements_correctly_handle_nested_selects()
begin
  select
    (select xn),
    (select yn from tnull),
    (select yn from tnull where yn is not null) as yn0,
    (select yn) as yn1
  from tnull
  where xn is not null and yn is not null;
end;

-- TEST: We actually want `yn` to be improved in the result even though `xn is
-- not null` because `yn` is an alias for `xn + xn` and `xn is not null`. `yn0`
-- should not be improved even though it is an alias for `yn` because that is a
-- different `yn` from the one we're improving (it's actually `tnull.yn`).
-- + {create_proc_stmt}: improvements_apply_in_select_exprs: { yn: integer notnull, yn0: integer } dml_proc
-- - error:
proc improvements_apply_in_select_exprs()
begin
  select xn + xn as yn, yn as yn0 from tnull where xn is not null;
end;

-- TEST: We do not improve a result column merely because a variable with the
-- same name is improved in an enclosing scope.
-- + {create_proc_stmt}: local_variable_improvements_do_not_affect_result_columns: { xn: integer, yn: integer } dml_proc
-- - error:
proc local_variable_improvements_do_not_affect_result_columns()
begin
  declare xn int;
  if xn is null return;
  select * from tnull;
end;

-- TEST: Improvements work on the result of joins.
-- + {create_proc_stmt}: improvements_work_on_join_results: { xn0: integer notnull } dml_proc
-- - error:
proc improvements_work_on_join_results()
begin
  select tnull.xn as xn0
  from tnull
  inner join another_table_with_nullables
  on tnull.xn = another_table_with_nullables.xn
  where tnull.xn is not null;
end;

-- TEST: Improvements do not work for ON clauses.
-- + {create_proc_stmt}: improvements_do_not_work_for_on_clauses: { xn0: integer } dml_proc
-- - error:
proc improvements_do_not_work_for_on_clauses()
begin
  select tnull.xn as xn0
  from tnull
  inner join another_table_with_nullables
  on tnull.xn = another_table_with_nullables.xn
  and tnull.xn is not null;
end;

-- TEST: We do not want `SEM_TYPE_INFERRED_NOTNULL` flags to be copied via LIKE.
-- Copying the flag would incorrectly imply an inferred NOT NULL status. We also
-- ensure here that there is no aliasing of struct pointers between `c` and `d`.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: y2: integer variable
-- - error:
proc notnull_inferred_does_not_get_copied_via_declare_cursor_like_cursor()
begin
  cursor c like tnull;
  fetch c from values (1, 2);
  if c.xn is not null and c.yn is not null then
    let x0 := c.xn;
    let y0 := c.yn;
    cursor d like c;
    let x1 := c.xn;
    let y1 := c.yn;
    let x2 := d.xn;
    let y2 := d.yn;
  end if;
end;

-- TEST: Ensure that `c.a is not null` does not result in an improvement that
-- shows up in the params of `improvements_work_for_in_args` via unintentional
-- aliasing.
-- + {declare_cursor_like_name}: c: improvements_work_for_in_args[arguments]: { a: integer in } variable shape_storage value_cursor
-- + {let_stmt}: x0: integer notnull variable
-- + {declare_cursor_like_name}: d: improvements_work_for_in_args[arguments]: { a: integer in } variable shape_storage value_cursor
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {declare_cursor_like_name}: e: improvements_work_for_in_args[arguments]: { a: integer in } variable shape_storage value_cursor
-- - error:
proc notnull_inferred_does_not_get_copied_via_declare_cursor_like_proc()
begin
  cursor c like improvements_work_for_in_args arguments;
  fetch c from values (0);
  if c.a is not null then
    let x0 := c.a;
    cursor d like improvements_work_for_in_args arguments;
    fetch d from values (0);
    let x1 := c.a;
    let x2 := d.a;
    cursor e like improvements_work_for_in_args arguments;
  end if;
end;

-- Used in the following test.
-- - error:
proc returns_nullable_int()
begin
  cursor c like select nullable(0) as a;
  out c;
end;

-- TEST: Verify that `returns_nullable_int` does not get improved when we
-- improve `args like returns_nullable_int` (which would indicate aliasing).
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc notnull_inferred_does_not_get_copied_via_arguments_like_proc(args like returns_nullable_int)
begin
  if args.a is not null then
    let x0 := args.a;
    cursor c fetch from call returns_nullable_int();
    let x1 := c.a;
  end if;
end;

-- TEST: Verify that rewrites for nullability work correctly within CTEs and do
-- not get applied twice.
-- + {create_proc_stmt}: improvements_work_within_ctes: { b: integer notnull } dml_proc
-- +1 {name cql_inferred_notnull}: a: integer notnull variable
-- - error:
proc improvements_work_within_ctes()
begin
  declare a int;
  if a is not null then
    with recursive some_cte(b) as (select a)
    select b from some_cte;
  end if;
end;

-- TEST: A commit return guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_commit_return_guards(a int)
begin
  proc savepoint
  begin
    if 1 then
      if a is null commit return;
      let x0 := a;
    end if;
    let x1 := a;
  end;
end;

-- TEST: A continue guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_continue_guards(a int)
begin
  while 1
  begin
    if a is null continue;
    let x0 := a;
  end;
  let x1 := a;
end;

-- TEST: A leave guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_leave_guards(a int)
begin
  while 1
  begin
    if a is null leave;
    let x0 := a;
  end;
  let x1 := a;
end;

-- TEST: A return guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_return_guards(a int)
begin
  if 1 then
    if a is null return;
    let x0 := a;
  end if;
  let x1 := a;
end;

-- TEST: A rollback return guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_rollback_return_guards(a int)
begin
  proc savepoint
  begin
    if 1 then
      if a is null rollback return;
      let x0 := a;
    end if;
    let x1 := a;
  end;
end;

-- TEST: A throw guard can improve nullability.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_throw_guards(a int)
begin
  proc savepoint
  begin
    if 1 then
      if a is null throw;
      let x0 := a;
    end if;
    let x1 := a;
  end;
end;

-- TEST: Guard improvements work for cursor fields.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc guard_improvements_work_for_cursor_fields()
begin
  cursor c for select nullable(1) a;
  fetch c;
  if 1 then
    if c.a is null return;
    let x0 := c.a;
  end if;
  let x1 := c.a;
end;

-- TEST: OR allows guards to introduce multiple improvements.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: z0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: z1: integer variable
-- - error:
proc multiple_improvements_are_possible_via_one_guard(a int, b int, c int)
begin
  if 1 then
    if a is null or b is null or c is null return;
    let x0 := a;
    let y0 := b;
    let z0 := c;
  end if;
  let x1 := a;
  let y1 := b;
  let z1 := c;
end;

-- TEST: Checks not along the outermost spine of ORs result in no improvement.
-- + {let_stmt}: x: integer variable
-- + {let_stmt}: y: integer variable
-- + {let_stmt}: z: integer variable
-- - error:
proc guard_improvements_only_work_for_outermost_ors(a int, b int, c int)
begin
  if a is null and (b is null or c is null) return;
  let x := a;
  let y := b;
  let z := c;
end;

-- TEST: Not explicitly using IS NULL results in no improvement.
proc guard_improvements_only_work_for_is_null(a int)
begin
  if not a return;
  let x := a;
end;

-- TEST: Bad conditions in guards are handled as in if statements.
-- + error: % name not found 'some_undefined_variable'
-- + {if_stmt}: err
-- +1 error:
proc guard_improvements_handle_semantic_issues_like_if()
begin
  if some_undefined_variable is null return;
end;

-- TEST: Improvements work for IFs that follow the guard pattern.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: z0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: z1: integer variable
-- - error:
proc improvements_work_for_guard_pattern_ifs()
begin
  declare a int;
  declare b int;
  declare c int;
  if 1 then
    if a is null or b is null or c is null then
      return;
    end if;
    let x0 := a;
    let y0 := b;
    let z0 := c;
  end if;
  let x1 := a;
  let y1 := b;
  let z1 := c;
end;

-- TEST: Improvements work for IFs that follow the guard pattern when statements
-- are present before the control statement.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: z0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: z1: integer variable
-- - error:
proc improvements_work_for_guard_pattern_ifs_with_preceding_statements()
begin
  declare a int;
  declare b int;
  declare c int;
  if 1 then
    if a is null or b is null or c is null then
      call printf("Hello, world!\n");
      return;
    end if;
    let x0 := a;
    let y0 := b;
    let z0 := c;
  end if;
  let x1 := a;
  let y1 := b;
  let z1 := c;
end;

-- TEST: Improvements work for IFs that follow the guard pattern even if they
-- set the variable that's going to be improved after END IF to NULL.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- - error:
proc improvements_work_for_guard_pattern_ifs_that_set_the_id_to_null()
begin
  declare a int;
  if 1 then
    if a is null then
      set a := null;
      return;
    end if;
    let x0 := a;
  end if;
  let x1 := a;
end;

-- TEST: Improvements do not work for IFs that would be following the guard
-- pattern if not for the presence of ELSE.
-- + {let_stmt}: x: integer variable
-- - error:
proc improvements_do_not_work_for_guard_like_ifs_with_else()
begin
  declare a int;
  if a is null then
    return;
  else
    -- We could set `a` to null here, hence we can't improve it after END IF.
  end if;
  let x := a; -- nullable
end;

-- TEST: Improvements do not work for IFs that would be following the guard
-- pattern if not for the presence of ELSE IF.
-- + {let_stmt}: x: integer variable
-- - error:
proc improvements_do_not_work_for_guard_like_ifs_with_else_if()
begin
  declare a int;
  if a is null then
    return;
  else if 1 then
    -- We could set `a` to null here, hence we can't improve it after END IF.
  end if;
  let x := a; -- nullable
end;

-- TEST: Improvements do not work for IS NULL checks after the first branch.
-- + {let_stmt}: x: integer variable
-- - error:
proc improvements_do_not_work_for_is_null_checks_in_else_ifs()
begin
  declare a int;
  if 0 then
    return;
  else if a is null then
    return;
  end if;
  let x := a; -- nullable
end;

-- TEST: Later branches are improved via the assumption that earlier branches
-- must not have been taken.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer variable
-- + {let_stmt}: z0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer variable
-- + {let_stmt}: z1: integer variable
-- + {let_stmt}: x2: integer notnull variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: z2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: z3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer variable
-- + {let_stmt}: z4: integer variable
proc false_conditions_of_earlier_branches_improve_later_branches()
begin
  declare a int;
  declare b int;
  declare c int;

  if a is null then
    let x0 := a;
    let y0 := b;
    let z0 := c;
  else if 0 then
    -- `a` is improved here
    let x1 := a;
    let y1 := b;
    let z1 := c;
  else if b is null or c is null then
    -- `a` is still improved here
    let x2 := a;
    let y2 := b;
    let z2 := c;
  else
    -- `a`, `b`, and `c` are improved here
    let x3 := a;
    let y3 := b;
    let z3 := c;
  end if;

  let x4 := a;
  let y4 := b;
  let z4 := c;
end;

-- TEST: Un-improvements in one branch do not negatively affect later branches.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: x5: integer notnull variable
-- + {let_stmt}: x6: integer variable
-- - error:
proc unimprovements_do_not_negatively_affect_later_branches()
begin
  declare a int;

  -- nullable
  let x0 := a;

  if a is null return;

  -- nonnull due to the guard
  let x1 := a;

  if 0 then
    set a := null;
    -- nullable due to the set
    let x2 := a;
  else if 0 then
    -- nonnull due to the guard despite the set in an earlier branch
    let x3 := a;
    set a := null;
    -- nullable due to the set
    let x4 := a;
  else
  -- nonnull due to the guard despite the sets in earlier branches
    let x5 := a;
  end if;

  -- nullable because at least one branch had a hazard
  let x6 := a;
end;

-- TEST: Un-improvements in one branch do not negatively affect other branches
-- even if the un-improvements occurred within a nested branch.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: z0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: z1: integer variable
-- + {let_stmt}: x2: integer notnull variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: z2: integer variable
-- + {let_stmt}: x3: integer notnull variable
-- + {let_stmt}: y3: integer notnull variable
-- + {let_stmt}: z3: integer notnull variable
-- + {let_stmt}: x4: integer notnull variable
-- + {let_stmt}: y4: integer notnull variable
-- + {let_stmt}: z4: integer notnull variable
-- + {let_stmt}: x5: integer variable
-- + {let_stmt}: y5: integer variable
-- + {let_stmt}: z5: integer variable
-- + {let_stmt}: x6: integer variable
-- + {let_stmt}: y6: integer variable
-- + {let_stmt}: z6: integer notnull variable
-- + {let_stmt}: x7: integer notnull variable
-- + {let_stmt}: y7: integer notnull variable
-- + {let_stmt}: z7: integer notnull variable
-- + {let_stmt}: x8: integer variable
-- + {let_stmt}: y8: integer variable
-- + {let_stmt}: z8: integer notnull variable
-- + {let_stmt}: x9: integer notnull variable
-- + {let_stmt}: y9: integer notnull variable
-- + {let_stmt}: z9: integer notnull variable
-- + {let_stmt}: x10: integer variable
-- + {let_stmt}: y10: integer variable
-- + {let_stmt}: z10: integer notnull variable
-- - error:
proc nested_unimprovements_do_not_negatively_affect_later_branches()
begin
  declare a int;
  declare b int;
  declare c int;

  if a is null or b is null or c is null return;

  let x0 := a; -- nonnull due to guard
  let y0 := b; -- nonnull due to guard
  let z0 := c; -- nonnull due to guard

  if 0 then
    if 0 then
      set a := null;
      if 0 then
        set b := null;
      else
        set a := 42;
        set c := null;
        let x1 := a; -- nonnull due to set improvement
        let y1 := b; -- nonnull due to guard despite previous set
        let z1 := c; -- nullable due to previous set
        set a := null;
        if a is null then
          set a := null;
        else if c is null then
          set b := null;
          let x2 := a; -- nonnull due to improvement from false condition
          let y2 := b; -- nullable due to previous set
          let z2 := c; -- nullable due to previous set
        else if 0 then
          let x3 := a; -- nonnull due to improvement from false condition
          let y3 := b; -- nonnull due to guard despite previous set
          let z3 := c; -- nonnull due to improvement from false condition
          set b := null;
          set c := null;
        else
          let x4 := a; -- nonnull due to improvement from false condition
          let y4 := b; -- nonnull due to guard despite previous set
          let z4 := c; -- nonnull due to improvement from false condition
        end if;
        let x5 := a; -- nullable due to set in previous branch
        let y5 := b; -- nullable due to set in previous branch
        let z5 := c; -- nullable due to previous set in this statement list
        set a := 42; -- won't affect nullability below because it may not occur
        set b := 42; -- won't affect nullability below because it may not occur
        set c := 42; -- won't affect nullability below because it may not occur
      end if;
      let x6 := a; -- nullable due to previous set in this statement list
      let y6 := b; -- nullable due to previous set in previous branch
      let z6 := c; -- nonnull due to all previous branches being neutral
    else
      let x7 := a; -- nonnull due to guard despite previous set
      let y7 := b; -- nonnull due to guard despite previous set
      let z7 := c; -- nonnull due to guard despite previous set
    end if;
    let x8 := a; -- nullable due to previous set in previous branch
    let y8 := b; -- nullable due to previous set in previous branch
    let z8 := c; -- nonnull due to all previous branches being neutral
  else
    let x9 := a; -- nonnull due to guard despite previous set
    let y9 := b; -- nonnull due to guard despite previous set
    let z9 := c; -- nonnull due to guard despite previous set
  end if;

  let x10 := a; -- nullable due to previous set in previous branch
  let y10 := b; -- nullable due to previous set in previous branch
  let z10 := c; -- nonnull due to all previous branches being neutral
end;

-- TEST: Reverting improvements and un-improvements restores the original state.
-- In particular, an un-improvement within a contingent nullability context is
-- only re-improved if it was originally improved when said contingent context
-- was entered.
-- + {let_stmt}: x0: integer variable
-- + {let_stmt}: y0: integer notnull variable
-- + {let_stmt}: z0: integer notnull variable
-- + {let_stmt}: w0: integer variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: y1: integer notnull variable
-- + {let_stmt}: z1: integer notnull variable
-- + {let_stmt}: w1: integer variable
-- + {let_stmt}: x2: integer notnull variable
-- + {let_stmt}: y2: integer variable
-- + {let_stmt}: z2: integer variable
-- + {let_stmt}: w2: integer notnull variable
-- + {let_stmt}: x3: integer variable
-- + {let_stmt}: y3: integer variable
-- + {let_stmt}: z3: integer variable
-- + {let_stmt}: w3: integer variable
-- + {let_stmt}: x4: integer variable
-- + {let_stmt}: y4: integer notnull variable
-- + {let_stmt}: z4: integer notnull variable
-- + {let_stmt}: w4: integer variable
-- + {let_stmt}: x5: integer variable
-- + {let_stmt}: y5: integer variable
-- + {let_stmt}: z5: integer variable
-- + {let_stmt}: w5: integer variable
-- - error:
proc reverting_improvements_and_unimprovements_restores_original_state()
begin
  declare a int;
  declare b int;
  declare c int;
  declare d int;

  if b is null return;
  set c := 42;

  let x0 := a; -- nullable
  let y0 := b; -- nonnull due to guard
  let z0 := c; -- nonnull due to set
  let w0 := d; -- nullable

  if 0 then
    if a is not null then
      let x1 := a; -- nonnull due to true condition
      let y1 := b; -- nonnull due to guard
      let z1 := c; -- nonnull due to set
      let w1 := d; -- nullable
      set b := null; -- un-improve `b`
      set c := null; -- un-improve `c`
      if c is not null then -- re-improve c
        let dummy := 0;
        -- un-improve `c` at the end of the statement list
      end if;
      set d := 42; -- improve `d`
      let x2 := a; -- nonnull due to true condition
      let y2 := b; -- nullable due to set
      let z2 := c; -- nullable due to most recent then block ending
      let w2 := d; -- nonnull due to set
      -- un-improve `a` at the end of the statement list
      -- un-improve `d` at the end of the statement list
    end if;
    let x3 := a; -- nullable again because then branch is over
    let y3 := b; -- nullable due to set
    let z3 := c; -- nullable due to innermost then branch ending
    let w3 := d; -- nullable due to previous statement list ending
    set a := null; -- does not un-improve `a` as it is already not improved
  else
    let x4 := a; -- not re-improved as it began nullable for previous branch
                 -- (before the improvement for the condition was set)
    let y4 := b; -- re-improved as it began nonnull for previous branch
    let z4 := c; -- re-improved as it began nonnull for previous branch
    let w4 := d; -- not re-improved as it began nullable for previous branch
  end if;

  let x5 := a; -- nullable as then branch in which it was improved is over
  let y5 := b; -- nullable because of set
  let z5 := c; -- nullable because of set
  let w5 := d; -- nullable as statement list in which it was improved is over
end;

-- TEST: Un-improving and re-improving the nullability of a variable within the
-- same branch does not prevent it from remaining improved.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer notnull variable
-- + {let_stmt}: x2: integer variable
-- - error:
proc unimproving_and_reimproving_is_neutral()
begin
  declare a int;

  set a := 42;

  -- nonnull
  let x0 := a;

  if 0 then
    -- multiple sets to NULL have no additional effect
    set a := null;
    set a := null;
    set a := 100;
  else if 0 then
    -- multiple re-improvements can still be neutral
    set a := null;
    set a := 100;
    set a := null;
    set a := 100;
  else
    set a := 100;
  end if;

  -- nonnull
  let x1 := a;

  if 0 then
    set a := 100;
  else if 0 then
    -- this branch is not neutral
    set a := null;
  else
    set a := 100;
  end if;

  -- nullable
  let x2 := a;
end;

-- TEST: If all branches improve the same variable, it is improved after the IF
-- so long as there is an ELSE branch.
-- + {let_stmt}: x0: integer notnull variable
-- + {let_stmt}: x1: integer variable
-- + {let_stmt}: x2: integer variable
-- + {let_stmt}: x3: integer variable
-- - error:
proc all_branches_improving_including_else_results_in_an_improvement()
begin
  declare a int;

  if 0 then
    set a := 42;
  else if 0 then
    set a := null;
    -- nested all-branch improvements propagate upwards
    if 0 then
      set a := 42;
    else
      set a := null;
      set a := 42;
    end if;
  else if 0 then
    set a := 42;
  else
    set a := null;
    set a := null;
    set a := 42;
  end if;

  -- nonnull
  let x0 := a;

  set a := null;

  -- nullable
  let x1 := a;

  -- no else
  if 0 then
    set a := 42;
  end if;

  -- nullable
  let x2 := a;

  -- no else
  if 0 then
    set a := 42;
  else if 0 then
    set a := 42;
  end if;

  -- nullable
  let x3 := a;
end;

-- Used in the following tests.
declare proc requires_int_notnull(a int!);

-- TEST: Improvements that are unset within a loop affect all preceding
-- statements within the loop.
-- + error: % cannot assign/copy possibly null expression to not null target 'a'
-- + error: % additional info: calling 'requires_int_notnull' argument #1 intended for parameter 'a' has the problem
-- + {create_proc_stmt}: err
-- + {name x0}: x0: integer notnull variable
-- + {name y0}: y0: integer notnull variable
-- + {call_stmt}: err
-- + {name x1}: x1: integer variable
-- + {name y1}: y1: integer variable
-- + {name x2}: x2: integer notnull variable
-- + {name y2}: y2: integer variable
-- + {name x3}: x3: integer variable
-- + {name y3}: y3: integer variable
-- + {name x4}: x4: integer notnull variable
-- + {name y4}: y4: integer notnull variable
-- + {name x5}: x5: integer variable
-- + {name y5}: y5: integer notnull variable
-- + {name x6}: x6: integer variable
-- + {name y6}: y6: integer notnull variable
-- +2 error:
proc unimprovements_in_loops_affect_earlier_statements()
begin
  declare a int;
  declare b int;

  set a := 1;
  set b := 1;

  let x0 := a; -- nonnull
  let y0 := b; -- nonnull

  while 0
  begin
    call requires_int_notnull(a); -- correctly flagged as an error
    let x1 := a; -- nullable
    let y1 := b; -- nullable
    set a := null; -- makes x1 nullable
    while 0
    begin
      set a := 1; -- makes x2 nonnull
      set b := null; -- makes y1 nullable
      let x2 := a; -- notnull
      let y2 := b; -- nullable
    end;
  end;

  let x3 := a; -- nullable
  let y3 := b; -- nullable

  set a := 1;
  set b := 1;

  let x4 := a; -- nonnull
  let y4 := b; -- nonnull

  cursor foo for select 1 bar;
  loop fetch foo
  begin
    let x5 := a; -- nullable
    let y5 := b; -- nonnull
    set a := null;
  end;

  let x6 := a; -- nullable
  let y6 := b; -- nonnull
end;

-- TEST: It is not safe to consider a statement list within a loop neutral with
-- respect to some existing improvement if an unset to that improvement occurred
-- anywhere within the loop due to the possible presence of a CONTINUE or LEAVE
-- statement. Since only branch groups can pair up unsets and sets to discover
-- neutrality at the moment, we do the bulk of the test within an IF.
-- + {name x0}: x0: integer notnull variable
-- + {name y0}: y0: integer notnull variable
-- + {name x1}: x1: integer notnull variable
-- + {name y1}: y1: integer variable
-- + {name x2}: x2: integer variable
-- + {name y2}: y2: integer variable
-- + {name x3}: x3: integer notnull variable
-- + {name y3}: y3: integer notnull variable
-- + {name x4}: x4: integer variable
-- + {name y4}: y4: integer notnull variable
-- + {name z}: z: integer notnull variable
-- - error:
proc loops_keep_all_unsets_and_ignore_all_sets()
begin
  declare a int;
  declare b int;

  set a := 1;
  set b := 1;

  while 0
  begin
    set a := 1; -- re-set this so it's not unset due to reanalysis
    set b := 1; -- re-set this so it's not unset due to reanalysis
    let x0 := a; -- nonnull
    let y0 := b; -- nonnull
    -- use an if/else to make sure we're safe in the presence of effect merging
    if 0 then
      set a := null; -- makes x2 nullable, but not x1 as the IF is neutral
      if 0 then
        leave;
      end if;
      set a := 1; -- does not make the whole loop neutral with respect to a
      while 0
      begin
        if 0 then
          set b := null; -- makes y1 nullable despite no leave/continue
          set b := 1;
        else
          set b := 1;
        end if;
      end;
    else
      set a := 1;
      set b := 1;
    end if;
    let x1 := a; -- nonnull due to the merged effects being neutral
    let y1 := b; -- unfortunately nullable because of our conservative analysis
  end;

  let x2 := a; -- nullable despite the neutral IF as required for safety
  let y2 := b; -- nullable

  set a := 1;
  set b := 1;

  let x3 := a; -- nonnull
  let y3 := b; -- nonnull

  cursor foo for select 1 bar;
  loop fetch foo
  begin
    if 0 then
      set a := null;
      if 0 then
        leave;
      end if;
      set a := 1;
    else
      set b := 1;
    end if;
  end;

  let x4 := a; -- nullable
  let y4 := b; -- nonnull

  declare c int;

  set c := 1;

  -- note the different behavior from LOOP and WHILE here
  proc savepoint
  begin
    if 0 then
      set c := null; -- if this were a WHILE, it would make z nullable
      if 0 then
        rollback return; -- safely ignored
      end if;
      set c := 1;
    else
      -- do nothing; neutral
    end if;
  end;

  let z := c; -- safely considered nonnull despite the set to null
end;

-- TEST: Unimprovements anywhere in a TRY negatively affect all statements after
-- the TRY.
-- + {name x0}: x0: integer notnull variable
-- + {name x1}: x1: integer variable
-- + {name x2}: x2: integer variable
-- - error:
proc try_keeps_all_unsets_and_ignores_all_sets()
begin
  declare a int;

  set a := 1;

  try
    -- use an if/else to make sure we're safe in the presence of effect merging
    if 0 then
      set a := null;
      if 0 then
        throw; -- makes x1 and x2 nullable
      end if;
      set a := 1;
      -- neutral
    else
      -- do nothing; neutral
    end if;
    let x0 := a; -- safely considered nonnull
  catch
    let x1 := a; -- nullable
    set a := 1; -- does not allow for improving x2 (at least for now)
  end;

  let x2 := a; -- nullable
end;

-- TEST: Improvements made within a PROC SAVEPOINT statement persist.
-- + {name x}: x: integer notnull variable
-- - error:
proc proc_savepoint_improvements_persist()
begin
  declare a int;

  proc savepoint
  begin
    set a := 1;
    rollback return;
  end;

  let x := a; -- nonnull
end;

-- TEST: Branches of a SWITCH are analyzed independently with respect to improvements.
-- + {name x0}: x0: integer notnull variable
-- + {name x1}: x1: integer notnull variable
-- + {name x2}: x2: integer variable
-- - error:
proc switch_branches_are_independent_for_improvements()
begin
  declare a int;

  set a := 1;

  switch 0
  when 1 then
    set a := null;
  when 2 then
    let x0 := a; -- nonnull despite previous set
    set a := null;
  else
    let x1 := a; -- nonnull despite previous set
  end;

  let x2 := a; -- nullable
end;

-- TEST: If all branches of a SWITCH make the same improvement, it persists
-- after the SWITCH, but only if an ELSE or ALL VALUES is present.
-- + {name x}: x: integer notnull variable
-- + {name y}: y: integer notnull variable
-- + {name z}: z: integer variable
-- - error:
proc switch_improvements_can_persist()
begin
  declare a int;
  declare b int;
  declare c int;

  -- has an ELSE
  switch 0
  when 1 then
    set a := 1;
  when 2 then
    set a := 1;
  else
    set a := 1;
  end;

  -- has ALL VALUES
  switch three_things.zero all values
  when three_things.zero then
    set b := 1;
  when three_things.one then
    set b := 1;
  when three_things.two then
    set b := 1;
  end;

  -- has neither
  switch 0
  when 1 then
    set c := 1;
  when 2 then
    set c := 1;
  end;

  let x := a; -- nonnull
  let y := b; -- nonnull
  let z := c; -- nullable
end;

-- TEST: An empty branch in an IF prevents the IF from persisting any
-- improvements.
-- + {name x0}: x0: integer variable
-- + {name x1}: x1: integer variable
-- + {name x2}: x2: integer variable
-- - error:
proc empty_branches_prevent_persisting_improvements()
begin
  declare a int;

  if 0 then
    -- empty
  else if 0 then
    set a := 1;
  else
    set a := 1;
  end if;

  let x0 := a;

  if 0 then
    set a := 1;
  else if 0 then
    -- empty
  else
    set a := 1;
  end if;

  let x1 := a;

  if 0 then
    set a := 1;
  else if 0 then
    set a := 1;
  else
    -- empty
  end if;

  let x2 := a;
end;

-- TEST: Improvements take control statements into account in order to allow
-- additional improvements to persist.
-- + {name x0}: x0: integer notnull variable
-- + {name x1}: x1: integer notnull variable
-- + {name x2}: x2: integer variable
-- + {name x3}: x3: integer variable
-- - error:
proc improvements_account_for_control_statements()
begin
  declare a int;

  -- basic case
  if 0 then
    set a := 1;
  else
    throw;
  end if;

  let x0 := a; -- nonnull

  set a := null;

  -- complex case
  while 0
  begin
    if 0 then
      if 0 then
        set a := null;
        set a := 1;
      else if 0 then
        throw;
      else if 0 then
        return;
      else
        set a := 1;
      end if;
    else if 0 then
      leave;
    else if 0 then
      if 0 then
        continue;
      else
        set a := null;
        set a := null;
        set a := 1;
      end if;
    else
      set a := null;
      continue;
    end if;

    let x1 := a; -- nonnull as all non-improving paths jump beyond the loop
  end;

  let x2 := a; -- nullable as the loop may have never run

  -- we-could-do-better-here case
  if 0 then
    if 0 then
      throw; -- jumps
    else
      return; -- also jumps
    end if;
    -- this context is not yet considered to always jump, but it does
  else
    set a := 1;
  end if;

  let x3 := a; -- nullable for now, but this may change in the future
end;

-- TEST: Improvements work for WHILE conditions.
-- + {name x0}: x0: integer variable
-- + {name y0}: y0: integer notnull variable
-- + {name x1}: x1: integer notnull variable
-- + {name y1}: y1: integer variable
-- + {name z1}: z1: integer notnull variable
-- + {name x2}: x2: integer variable
-- + {name y2}: y2: integer variable
-- + {name z2}: z2: integer variable
-- - error:
proc improvements_work_for_while_conditions()
begin
  declare a int;
  declare b int;
  declare c int;

  if b is null return;

  let x0 := a; -- nullable
  let y0 := b; -- nonnull due to negative check
  let z0 := b; -- nullable

  while a is not null and c is not null
  begin
    let x1 := a; -- nonnull due to loop condition
    let y1 := b; -- nullable due to set later in loop
    let z1 := c; -- nonnull despite set later in loop due to loop condition
    set b := null;
    set c := null;
  end;

  let x2 := a; -- nullable due to end of loop
  let y2 := b; -- nullable due to set within loop
  let z2 := c; -- nullable due to end of loop
end;

-- Used in the following test.
declare proc requires_inout_text_notnull(inout t text not null);

-- Used in the following test.
declare proc requires_inout_blob_notnull(inout t blob not null);

-- Used in the following test.
declare proc requires_inout_object_notnull(inout t object not null);

-- TEST: Variables of a nonnull reference type must be initialized before use,
-- both when used within expressions and when passed as INOUT arguments.
-- + {create_proc_stmt}: err
-- + {name a}: a: text notnull variable init_required
-- + {name b}: b: blob notnull variable init_required
-- + {name c}: c: object notnull variable init_required
-- +3 {let_stmt}: err
-- +3 {call_stmt}: err
-- +2 error: % variable possibly used before initialization 'a'
-- +2 error: % variable possibly used before initialization 'b'
-- +2 error: % variable possibly used before initialization 'c'
proc initialization_is_required_for_nonnull_reference_types()
begin
  declare a text not null;
  declare b blob not null;
  declare c object not null;

  -- expression case
  let dummy := a;
  let dummy := b;
  let dummy := c;

  -- INOUT arg case
  call requires_inout_text_notnull(a);
  call requires_inout_blob_notnull(b);
  call requires_inout_object_notnull(c);
end;

-- TEST: Variables of a nullable reference type need not be initialized before
-- use.
-- + {name a}: a: text variable
-- + {name b}: b: blob variable
-- + {name c}: c: object variable
-- + {name x}: x: text variable
-- + {name y}: y: blob variable
-- + {name z}: z: object variable
-- - error:
proc initialization_is_not_required_for_nullable_reference_types()
begin
  declare a text;
  declare b blob;
  declare c object;

  let x := a;
  let y := b;
  let z := c;
end;

-- TEST: Variables of a non-reference type need not be initialized before use.
-- + {name a}: a: bool notnull variable
-- + {name b}: b: integer notnull variable
-- + {name c}: c: longint notnull variable
-- + {name x}: x: bool notnull variable
-- + {name y}: y: integer notnull variable
-- + {name z}: z: longint notnull variable
-- - error:
proc initialization_is_not_required_for_non_reference_types()
begin
  declare a bool not null;
  declare b int!;
  declare c long not null;

  let x := a;
  let y := b;
  let z := c;
end;

-- TEST: A SET statement initializes a variable.
-- + {name a}: a: text notnull variable init_required
-- + {name x}: x: text notnull variable
-- - error;
proc set_can_initialize()
begin
  declare a text not null;
  set a := "text";
  let x := a;
end;

-- TEST: make a multi-part string literal
-- +  LET z := "abc\n123\r\n\x02lmnop''";
proc string_chain()
begin
  let z := "abc\n"
     "123\r\n\x02"
     "lmnop''";
end;

-- Used in the following test.
declare proc requires_out_text_notnull(out t text not null);

-- TEST: Passing a variable as an OUT argument (but not an INOUT argument)
-- initializes it.
-- + {name a}: a: text notnull variable init_required
-- + {name x}: x: text notnull variable
-- - error;
proc out_arg_uses_can_initialize()
begin
  declare a text not null;
  call requires_out_text_notnull(a);
  let x := a;
end;

-- TEST: Fetching into a variable initializes it.
-- + {name a}: a: text notnull variable init_required
-- + {name x}: x: text notnull variable
-- - error:
proc fetch_into_initializes()
begin
  declare a text not null;
  cursor foo for select "text" bar;
  fetch foo into a;
  let x := a;
end;

-- TEST: Initialization of OUT args is required before the end of the procedure.
-- + error: % nonnull reference OUT parameter possibly not always initialized 'a'
-- + {create_proc_stmt}: err
-- + {param}: a: text notnull variable init_required out
-- +1 error:
proc nonnull_reference_out_args_require_initialization(out a text not null)
begin
end;

-- TEST: Initialization of OUT args directly in the proc statement list works.
-- + {param}: a: text notnull variable init_required out
-- - error:
proc out_arg_initialization_directly_in_proc_works(out a text not null)
begin
  set a := "text";
end;

-- TEST: Initialization must be complete before all returns.
-- + error: % nonnull reference OUT parameter possibly not always initialized 'a'
-- + {create_proc_stmt}: err
-- + {param}: a: text notnull variable init_required out
-- +1 error:
proc out_args_must_be_initialized_before_return(out a text not null)
begin
  if 0 then
    return;
  end if;
  set a := "text";
end;

-- TEST: Initialization of OUT args can be done within IF and SWITCH branches.
-- + {name a}: a: text notnull variable init_required
-- - error:
proc out_args_can_be_initialized_in_branches(out a text not null)
begin
  if 0 then
    set a := "text";
  else if 0 then
    set a := "text";
  else
    if 0 then
      if 0 then
        set a := "text";
      else
        if 0 then
          set a := "text";
        else
          switch 0
          when 0 then
            set a := "text";
          when 1 then
            if 0 then
              set a := "text";
            else
              set a := "text";
            end if;
          else
            set a := "text";
          end;
        end if;
      end if;
    else
      set a := "text";
    end if;
  end if;
end;

-- TEST: Initialization of OUT args can be done within IF and SWITCH branches,
-- but all cases must be covered.
-- + error: % nonnull reference OUT parameter possibly not always initialized 'a'
-- + {create_proc_stmt}: err
-- + {name a}: a: text notnull variable init_required
-- +1 error:
proc out_arg_initialization_in_branches_must_cover_all_cases(out a text not null)
begin
  if 0 then
    set a := "text";
  else if 0 then
    set a := "text";
  else
    if 0 then
      if 0 then
        set a := "text";
      else
        if 0 then
          set a := "text";
        else
          switch 0
          when 0 then
            set a := "text";
          when 1 then
            if 0 then
              -- this case has not been covered
            else
              set a := "text";
            end if;
          else
            set a := "text";
          end;
        end if;
      end if;
    else
      set a := "text";
    end if;
  end if;
end;

-- TEST: Forwarding procs handle initialization improvements correctly.
-- + {create_proc_stmt}: ok
-- + {param}: t: text notnull variable init_required out
-- - error:
proc forwarding_procs_handle_initialization(like requires_out_text_notnull arguments)
begin
  call requires_out_text_notnull(from arguments);
end;

-- TEST: Forwarding procs using named bundles handle initialization improvements
-- correctly.
-- + {create_proc_stmt}: ok
-- + {param}: bundle_t: text notnull variable init_required out
-- - error:
proc forwarding_procs_handle_initialization_named(bundle like requires_out_text_notnull arguments)
begin
  call requires_out_text_notnull(from bundle);
end;

-- TEST: TRY blocks can be treated as the top level of a proc for the purposes
-- of initialization, if annotated.
-- + {create_proc_stmt}: ok dml_proc
-- + {assign}: a: text notnull variable init_required out
-- - error:
proc try_blocks_can_successfully_verify_initialization(out a text not null, out rc int!)
begin
  set rc := 0;
  [[try_is_proc_body]]
  @attribute(some_other_attribute)
  try
    -- we're okay because it's initialized in the TRY...
    set a := "text";
  catch
    set rc := 1;
  end;
  -- ...even though it's not always initialized in the proc
end;

-- TEST: try_is_proc_body catches parameter initialization errors in the TRY.
-- + error: % nonnull reference OUT parameter possibly not always initialized 'a'
-- + {create_proc_stmt}: err
-- + {stmt_and_attr}: err
-- + {trycatch_stmt}: err
-- +1 error:
proc try_blocks_can_fail_to_verify_initialization(out a text not null, out rc int!)
begin
  set rc := 0;
  @attribute(some_other_attribute)
  [[try_is_proc_body]]
  try
    -- `a` is not initialized soon enough so we get an error...
  catch
    set rc := 1;
  end;
  -- ...even though it's always initialized in the proc
  set a := "text";
end;

-- TEST: try_is_proc_body may only appear once.
-- + error: % [[try_is_proc_body]] cannot be used more than once per procedure
-- + {create_proc_stmt}: err
-- + {stmt_and_attr}: err
-- + {trycatch_stmt}: err
-- +1 error:
proc try_is_proc_body_may_only_appear_once()
begin
  [[try_is_proc_body]]
  try
  catch
  end;
  [[try_is_proc_body]]
  try
  catch
  end;
end;

-- TEST: try_is_proc_body accepts no values.
-- + error: % [[try_is_proc_body]] accepts no values
-- + {create_proc_stmt}: err
-- + {stmt_and_attr}: err
-- + {trycatch_stmt}: err
-- +1 error:
proc try_is_proc_body_accepts_no_values()
begin
  [[try_is_proc_body=(foo)]]
  try
  catch
  end;
end;

-- TEST: Improvements can be set for names using the dot syntax even when the
-- scopes of the names shadow a global variable.
-- + {name x_}: x_: integer notnull variable
-- + {dot}: X_id: integer inferred_notnull variable in
-- + {name y_}: y_: integer notnull variable
-- + {dot}: Y.id: integer inferred_notnull variable
-- - error:
proc improvements_work_for_dots_that_shadow_globals(X like some_proc arguments)
begin
  cursor Y for select nullable(1) id;
  fetch Y;
  if X.id is not null and Y.id is not null then
    let x_ := X.id;
    let y_ := Y.id;
  end if;
end;

-- Used in the following test.
declare proc requires_out_text_notnull_and_int(out a text not null, b int);

-- Used in the following test.
declare proc requires_text_notnull(a text not null);

-- TEST: Improvements set on one form of a name from an argument bundle affect
-- the other form.
-- + {create_proc_stmt}: ok
-- + {dot}: b0_a: text notnull variable out
-- + {name b0_a}: b0_a: text notnull variable out
-- + {dot}: b1_a: text notnull variable out
-- + {name b1_a}: b1_a: text notnull variable out
-- + {dot}: b0_b: integer inferred_notnull variable in
-- + {name b0_b}: b0_b: integer inferred_notnull variable in
-- + {dot}: b1_b: integer inferred_notnull variable in
-- + {name b1_b}: b1_b: integer inferred_notnull variable in
-- - error:
proc dot_form_and_underscore_form_are_equivalent(
  b0 like requires_out_text_notnull_and_int arguments,
  b1 like requires_out_text_notnull_and_int arguments)
begin
  -- Either form works for initialization.
  call requires_out_text_notnull_and_int(from b0); -- rewrites to dot form
  set b1_a := "text";
  call requires_text_notnull(b0.a);
  call requires_text_notnull(b0_a);
  call requires_text_notnull(b1.a);
  call requires_text_notnull(b1_a);

  -- Either form works for nullability.
  if b0.b is not null and b1_b is not null then
    call requires_int_notnull(b0.b);
    call requires_int_notnull(b0_b);
    call requires_int_notnull(b1.b);
    call requires_int_notnull(b1_b);
  end if;
end;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- NOT is weaker than +, parens stay even though this is a special case
-- the parens could be elided becuse it's on the right of the +
-- + SELECT 1 + (NOT 2 IS NULL);
select 1 + not 2 is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- NOT is weaker than +, parens stay even though this is a special case
--  the parens could be elided becuse it's on the right of the +
-- + SELECT (NOT 1) + (NOT 2 IS NULL);
select (not 1) + not 2 is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- IS is weaker than + , parens must stay
-- + SELECT NOT 1 + (2 IS NULL);
select not 1 + (2 is null);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- plus is stronger than IS
-- + SELECT NOT 1 + 2 IS NULL;
select not 1 + 2 is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- NOT is weaker than IS, parens must stay
-- + SELECT 1 + (NOT 2) IS NULL;
select 1 + (not 2) is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- NOT is weaker than IS, parens must stay
-- + SELECT 1 IS NOT NULL AND 2 + (NOT 3) IS NULL;
select 1 is not null and 2 + (not 3) is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--  NOT is weaker than +, parens stay even though this is a special case
--  the parens could be elided becuse it's on the right of the +
-- + SELECT 1 IS NOT NULL AND 2 + (NOT 3 IS NULL)
select 1 is not null and 2 + not 3 is null;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than between, no parens needed
-- + SELECT NOT 0 BETWEEN -1 AND 2;
select not 0 between -1 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than between, must keep parens
-- + SELECT (NOT 0) BETWEEN -1 AND 2;
select (not 0) between -1 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than between, no parens needed
-- + SELECT NOT 0 BETWEEN -1 AND 2;
select not (0 between -1 and 2);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is weaker than =, don't need parens
-- + SELECT 1 = 2 BETWEEN 2 AND 2;
select 1=2 between 2 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is the same as =, but it binds left to right, keep the parens
-- + SELECT 1 = (2 BETWEEN 2 AND 2);
select 1=(2 between 2 and 2);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is the same as =, but it binds left to right
-- + SELECT 1 = 2 BETWEEN 2 AND 2;
select (1=2) between 2 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is the same as =, but it binds left to right
-- + SELECT 0 BETWEEN -2 AND -1 = 4;
select 0 between -2 and -1 = 4;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is the same as =, but it binds left to right (no parens needed)
-- + SELECT 0 BETWEEN -2 AND -1 = 4;
select (0 between -2 and -1) = 4;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- between is the same as =, but it binds left to right
-- + SELECT 0 BETWEEN -2 AND (-1 = 4);
select 0 between -2 and (-1 = 4);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens need to be added in the natural order (and its left associative)
-- + SELECT 0 BETWEEN 0 AND 3 BETWEEN 2 AND 3;
select 0 between 0 and 3 between 2 and 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed here, this is left associative, the parens are redundant
-- + SELECT 0 BETWEEN 0 AND 3 BETWEEN 2 AND 3;
select (0 between 0 and 3) between 2 and 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- must keep the parens on the right arg, between is left associative
-- + SELECT 0 BETWEEN 0 AND (3 BETWEEN 2 AND 3);
select 0 between 0 and (3 between 2 and 3);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed for the left arg of the between range
-- + SELECT 0 BETWEEN 1 BETWEEN 3 AND 4 AND (3 BETWEEN 2 AND 3);
select 0 between (1 between 3 and 4) and (3 between 2 and 3);


-- TEST: order of operations, verifying gen_sql agrees with tree parse
---- TILDE is stronger than CONCAT
-- + SELECT ~1 || 2;
-- - error:
select ~ 1||2;  --> -22

-- TEST: order of operations, verifying gen_sql agrees with tree parse
---- TILDE is stronger than CONCAT
-- + SELECT ~1 || 2;
-- - error:
select (~ 1)||2; --> -22

-- TEST: order of operations, verifying gen_sql agrees with tree parse
---- TILDE is stronger than CONCAT , parens must stay
-- + SELECT ~(1 || 2);
-- + error: % string operand not allowed in '~'
-- +1 error:
select ~ (1||2); --> -13

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- NEGATION is stronger than CONCAT, no parens generated
-- SELECT -0 || 1;
-- - error:
select -0||1;  --> 01

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- NEGATION is stronger than CONCAT, parens can be removed
-- SELECT -0 || 1;
-- - error:
select (-0)||1; --> 01

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- NEGATION is stronger than CONCAT, parens must stay
-- + SELECT -(0 || 1);
-- + error: % string operand not allowed in '-'
-- +1 error:
select -(0||1); --> -1

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- COLLATE is stronger than CONCAT, parens must stay
-- + SELECT 'x' || 'y' COLLATE foo;
select 'x' || 'y'  collate foo;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- COLLATE is stronger than CONCAT, parens must stay
-- + SELECT 'x' || 'y' COLLATE foo;
select 'x' ||  ('y' collate foo);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
--- COLLATE is stronger than CONCAT, parens must stay
-- + SELECT ('x' || 'y') COLLATE foo;
select ('x' || 'y') collate foo;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than not between, no parens needed
-- + SELECT NOT 0 NOT BETWEEN -1 AND 2;
select not 0 not between -1 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than not between, must keep parens
-- + SELECT (NOT 0) NOT BETWEEN -1 AND 2;
select (not 0 ) not between -1 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not is weaker than not between, no parens needed
-- + SELECT NOT 0 NOT BETWEEN -1 AND 2;
select not (0  not between -1 and 2);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is weaker than =, don't need parens
-- + SELECT 1 = 2 NOT BETWEEN 2 AND 2;
select 1=2 not between 2 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is the same as =, but it binds left to right, keep the parens
-- + SELECT 1 = (2 NOT BETWEEN 2 AND 2);
select 1=(2 not between 2 and 2);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is the same as =, but it binds left to right
-- + SELECT 1 = 2 NOT BETWEEN 2 AND 2;
select (1=2) not between 2 and 2;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is the same as =, but it binds left to right
-- + SELECT 0 NOT BETWEEN -2 AND -1 = 4;
select 0 not between -2 and -1 = 4;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is the same as =, but it binds left to right (no parens needed)
-- + SELECT 0 NOT BETWEEN -2 AND -1 = 4;
select (0 not between -2 and -1) = 4;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- not between is the same as =, but it binds left to right
-- + SELECT 0 NOT BETWEEN -2 AND (-1 = 4);
select 0 not between -2 and (-1 = 4);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens need to be added in the natural order (and its left associative)
-- + SELECT 0 NOT BETWEEN 0 AND 3 NOT BETWEEN 2 AND 3;
select 0 not between 0 and 3 not between 2 and 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed here, this is left associative, the parens are redundant
-- + SELECT 0 NOT BETWEEN 0 AND 3 NOT BETWEEN 2 AND 3;
select (0 not between 0 and 3) not between 2 and 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- must keep the parens on the right arg, not between is left associative
-- + SELECT 0 NOT BETWEEN 0 AND (3 NOT BETWEEN 2 AND 3);
select 0 not between 0 and (3 not between 2 and 3);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed for the left arg of the not between range
-- + SELECT 0 NOT BETWEEN 1 NOT BETWEEN 3 AND 4 AND (3 NOT BETWEEN 2 AND 3);
select 0 not between (1 not between 3 and 4) and (3 not between 2 and 3);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed becasuse NOT like is the same strength as = and left to right
-- + SELECT 'x' NOT LIKE 'y' = 1;
-- - error:
select 'x' not like 'y' = 1;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens are needed becasuse NOT like is the same strength as = and left to right
-- + SELECT 'x' NOT LIKE 'y' = 1;
-- - error:
select ('x' not like 'y') = 1;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- parens must stay for the for the right arg because that's not the normal order
-- this doesn't make sense semantically but it should still parse correctly
-- hence the error but still good tree shape
-- + SELECT 'x' NOT LIKE ('y' = 1);
-- + error: % required 'TEXT' not compatible with found 'INT' context '='
select 'x' not like ('y' = 1);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- conversion to IS NULL requires parens
-- + SELECT (nullable(5) IS NULL) + 3;
-- - error:
select nullable(5) isnull + 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens needed left to right works
-- + SELECT 5 IS NULL IS NULL;
-- + error: % Cannot use IS NULL or IS NOT NULL on a value of a NOT NULL type '5'
-- +1 error:
select 5 isnull isnull;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- conversion to IS NOT NULL requires parens
-- + SELECT (nullable(5) IS NOT NULL) + 3;
-- - error:
select nullable(5) notnull + 3;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens needed left to right works
-- + SELECT 5 IS NOT NULL IS NULL;
-- + error: % Cannot use IS NULL or IS NOT NULL on a value of a NOT NULL type '5'
-- +1 error:
select 5 notnull isnull;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens added
-- + SELECT NOT 1 IS TRUE;
-- - error:
select NOT 1 is true;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- IS TRUE is stronger than NOT, parens can be removed
-- - error:
-- + SELECT NOT 1 IS TRUE;
select NOT (1 is true);

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- IS TRUE is stronger than NOT, parens must stay
-- - error:
-- + SELECT (NOT 1) IS TRUE;
select (NOT 1) is true;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- no parens added
-- + SELECT 1 < 5 IS TRUE;
-- - error:
select 1 < 5 is true;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- IS TRUE is weaker than <, the parens can be removed
-- - error:
-- + SELECT 1 < 5 IS TRUE;
select (1 < 5) is true;

-- TEST: order of operations, verifying gen_sql agrees with tree parse
-- IS TRUE is weaker than <, the parens must stay
-- + SELECT 1 < (5 IS TRUE);
-- - error:
select 1 < (5 is true);

-- TEST: is true doesn't work on non numerics
-- + error: % string operand not allowed in 'IS TRUE'
-- + {assign}: err
-- + {is_true}: err
-- +1 error:
SET fal := 'x' is true;

-- TEST: is false should fail on bogus args
-- + error: % string operand not allowed in 'NOT'
-- + {assign}: err
-- + {is_false}: err
SET fal := ( not 'x') is false;

-- TEST: printf must be called with at least one argument
-- + error: % function got incorrect number of arguments 'printf'
-- + {select_expr}: err
-- +1 error:
select printf();

-- TEST: format must be called with at least one argument
-- + error: % function got incorrect number of arguments 'format'
-- + {select_expr}: err
-- +1 error:
select format();

-- TEST: printf requires a string literal for its first argument
-- + error: % first argument must be a string literal 'printf'
-- + {select_expr}: err
-- +1 error:
select printf(a_string);

-- TEST: format requires a string literal for its first argument
-- + error: % first argument must be a string literal 'format'
-- + {select_expr}: err
-- +1 error:
select format(a_string);

-- TEST: printf disallows excess arguments
-- + error: % more arguments provided than expected by format string 'printf'
-- + {select_expr}: err
-- +1 error:
select printf("%d %f", 0, 0.0, "str");

-- TEST: format disallows excess arguments
-- + error: % more arguments provided than expected by format string 'format'
-- + {select_expr}: err
-- +1 error:
select format("%d %f", 0, 0.0, "str");

-- TEST: printf disallows insufficient arguments
-- + error: % fewer arguments provided than expected by format string 'printf'
-- + {select_expr}: err
-- +1 error:
select printf("%d %f %s", 0, 0.0);

-- TEST: printf works with no substitutions
-- + {select_expr}: text notnull
-- - error:
select printf('Hello!\n');

-- TEST: printf understands '%%' requires no arguments
-- + {select_expr}: text notnull
-- - error:
select printf("Hello %% there %%!\n");

-- TEST: format understands '%%' requires no arguments
-- + {select_expr}: text notnull
-- - error:
select format("Hello %% there %%!\n");

-- TEST: printf disallows arguments of the wrong type
-- + error: % required 'TEXT' not compatible with found 'INT' context 'printf'
-- + {select_expr}: err
-- +1 error:
select printf("%s %s", "hello", 42);

-- TEST: format disallows arguments of the wrong type
-- + error: % required 'TEXT' not compatible with found 'INT' context 'format'
-- + {select_expr}: err
-- +1 error:
select format("%s %s", "hello", 42);

-- TEST: printf disallows loss of precision
-- + error: % lossy conversion from type 'LONG' in 0L
-- + {select_expr}: err
-- +1 error:
select printf("%d", 0L);

-- TEST: printf allows null arguments
-- + {select_expr}: text notnull
-- - error:
select printf("%s %d", null, null);

-- TEST: printf allows all sensible type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%d %i %u %f %e %E %g %G %x %X %o %s", 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, "str");

-- TEST: printf does not allow %c
-- + error: % type specifier not allowed in CQL 'c'
-- + {select_expr}: err
-- +1 error:
select printf("%c", "x");

-- TEST: printf does not allow %p
-- + error: % type specifier not allowed in CQL 'p'
-- + {select_expr}: err
-- +1 error:
select printf("%p", 0x123456789L);

-- TEST: printf does not allow %n
-- + error: % type specifier not allowed in CQL 'n'
-- + {select_expr}: err
-- +1 error:
select printf("%n", 0x123456789L);

-- TEST: printf does not allow %q
-- + error: % type specifier not allowed in CQL 'q'
-- + {select_expr}: err
-- +1 error:
select printf("%q", "hello");

-- TEST: printf does not allow %Q
-- + error: % type specifier not allowed in CQL 'Q'
-- + {select_expr}: err
-- +1 error:
select printf("%Q", "hello");

-- TEST: printf does not allow %w
-- + error: % type specifier not allowed in CQL 'w'
-- + {select_expr}: err
-- +1 error:
select printf("%w", "hello");

-- TEST: printf allows 'll' with all integer type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%lld %lli %llu %llx %llX %llo", 0L, 0L, 0L, 0L, 0L, 0L);

-- TEST: printf disallows the use of the 'l'
-- + error: % 'l' length specifier has no effect; consider 'll' instead
-- + {select_expr}: err
-- +1 error:
select printf("%ld", 0L);

-- TEST: printf disallows use of 'll' with non-integer type specifiers
-- + error: % type specifier cannot be combined with length specifier 's'
-- + {select_expr}: err
-- +1 error:
select printf("%lls", "hello");

-- TEST: printf allows numeric widths for all type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%12d %12i %12u %12f %12e %12E %12g %12G %12x %12X %12o %12s", 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, "str");

-- TEST: printf allows use of the '*' width and verifies that an integer
-- argument is provided for the width
-- + {select_expr}: text notnull
-- - error:
select printf("%*s %*f", 10, "hello", 20, 3.14);

-- TEST: printf disallows following a numeric width with '*'
-- + error: % unrecognized type specifier '*'
-- + {select_expr}: err
-- +1 error:
select printf("%10*s", 10, "hello");

-- TEST: printf disallows following '*' with a numeric width
-- + error: % unrecognized type specifier '1'
-- + {select_expr}: err
-- +1 error:
select printf("%*10s", 10, "hello");

-- TEST: printf disallows incomplete substitutions containing '*'
-- + error: % incomplete substitution in format string
-- + {select_expr}: err
-- +1 error:
select printf("%*", 10);

-- TEST: printf allows a precision to be specified for all type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%.12d %.12i %.12u %.12f %.12e %.12E %.12g %.12G %.12x %.12X %.12o %.12s", 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, "str");

-- TEST: printf allows a width and precision to be specified together for all type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%9.12d %9.12i %9.12u %9.12f %9.12e %9.12E %9.12g %9.12G %9.12x %9.12X %9.12o %9.12s", 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, "str");

-- TEST: printf allows '-' to be used with all type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%-16d %-16i %-16u %-16f %-16e %-16E %-16g %-16G %-16x %-16X %-16o %-16s", 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, "str");

-- TEST: printf requires that '-' be used with a width
-- + error: % width required when using flag in substitution '-'
-- + {select_expr}: err
-- +1 error:
select printf("%-s", "hello");

-- TEST: printf disallows the same flag appearing twice
-- + error: % duplicate flag in substitution '-'
-- + {select_expr}: err
-- +1 error:
select printf("%--10s", "hello");

-- TEST: printf allows '+' for signed numeric type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%+d %+i", 42, -100);

-- TEST: printf disallows '+' for other type specifiers
-- + error: % type specifier combined with inappropriate flags 'u'
-- + {select_expr}: err
-- +1 error:
select printf("%+u", 42);

-- TEST: printf allows the space flag for signed numeric type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("% d % i", 42, -100);

-- TEST: printf disallows the space flag for other type specifiers
-- + error: % type specifier combined with inappropriate flags 'u'
-- + {select_expr}: err
-- +1 error:
select printf("% u", 42);

-- TEST: printf disallows the '+' and space flags being used together
-- + error: % cannot combine '+' flag with space flag
-- + {select_expr}: err
-- +1 error:
select printf("%+ u", 42);

-- TEST: printf disallows combining a length specifier and the '!' flag
-- + error: % length specifier cannot be combined with '!' flag
-- + {select_expr}: err
-- +1 error:
select printf("%!lld", 0);

-- TEST: printf allows the '0' flag with numeric type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%09d", 42);

-- TEST: printf disallows the '0' flag with non-numeric type specifiers
-- + error: % type specifier combined with inappropriate flags 's'
-- + {select_expr}: err
-- +1 error:
select printf("%09s", "hello");

-- TEST: printf requires that '0' be used with a width
-- + error: % width required when using flag in substitution '0'
-- + {select_expr}: err
-- +1 error:
select printf("%0d", 42);

-- TEST: printf allows the '#' flag with the appropriate type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%#g %#G %#o %#x %#X", 0.0, 0.0, 00, 0x0, 0x0);

-- TEST: printf disallows the '#' flag with other type specifiers
-- + error: % type specifier combined with inappropriate flags 's'
-- + {select_expr}: err
-- +1 error:
select printf("%#s", "hello");

-- TEST: printf allows the ',' flag with signed integer type specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%,d %,i", 0, 0);

-- TEST: printf disallows the ',' flag with other type specifiers
-- + error: % type specifier combined with inappropriate flags 'u'
-- + {select_expr}: err
-- +1 error:
select printf("%,u", 0);

-- TEST: printf allows the '!' flag with floating point and string type
-- specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%!f %!e %!E %!g %!G %!s", 0.0, 0.0, 0.0, 0.0, 0.0, "str");

-- TEST: printf disallows the '!' flag with other type specifiers
-- + error: % type specifier combined with inappropriate flags 'd'
-- + {select_expr}: err
-- +1 error:
select printf("%!d", 0);

-- TEST: printf allows all valid combinations of flags for signed integer type
-- specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%-+0,10d %, 0-7lli", 0, 0);

-- TEST: printf allows all valid combinations of flags for the unsigned integer
-- type specifier
-- + {select_expr}: text notnull
-- - error:
select printf("%0-7llu %-042u", 0, 0);

-- TEST: printf allows all valid combinations of flags for floating point type
-- specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%-0#!8f %!#-016e %0!#-12E %!0#-24g %-0!#100G", 0.0, 0.0, 0.0, 0.0, 0.0);

-- TEST: printf allows all valid combinations of flags for hex and octal type
-- specifiers
-- + {select_expr}: text notnull
-- - error:
select printf("%#0-32o %-#016x %0-#24X", 00, 0x0, 0x0);

-- TEST: printf allows all valid combinations of flags for the string specifier
-- + {select_expr}: text notnull
-- - error:
select printf("%-!8s %!-16s", "hello", "world");

-- TEST: printf even allows this
-- + {select_expr}: text notnull
-- - error:
select printf("%%s%%%-#123.0194llX%%%.241o.%!.32s% -0,14.234llds%#-!1.000E", 0x0, 00, "str", 0, 0.0);

-- TEST: substr uses zero based indices
-- + error: % substr uses 1 based indices, the 2nd argument of substr may not be zero
-- + {select_stmt}: err
-- + {call}: err
-- + {int 0}: err
-- +1 error:
select substr("123", 0, 2);

-- TEST: cannot use IS NULL on a nonnull type
-- + error: % Cannot use IS NULL or IS NOT NULL on a value of a NOT NULL type 'not_null_object'
-- +1 error:
let not_null_object_is_null := not_null_object is null;

-- TEST: cannot use IS NOT NULL on a nonnull type
-- + error: % Cannot use IS NULL or IS NOT NULL on a value of a NOT NULL type 'not_null_object'
-- +1 error:
let not_null_object_is_not_null := not_null_object is not null;

-- used in the following test
proc proc_inout_text(inout a text)
begin
end;

-- TEST: proc-as-func requires a trailing OUT parameter
-- + error: % procedure without trailing OUT parameter used as function 'proc_inout_text'
-- + {let_stmt}: err
-- + {call}: err
-- +1 error:
let dummy_proc_inout_text := proc_inout_text();

-- TEST: okay if used via a call statement
-- + {call_stmt}: ok
-- - error:
call proc_inout_text(a_string);

-- used in the following test
proc proc_inout_text_out_text(inout a text, out b text)
begin
  set b := null;
end;

-- TEST: proc-as-func disallows INOUT parameters
-- + error: % procedure with INOUT parameter used as function 'proc_inout_text_out_text'
-- + {let_stmt}: err
-- + {call}: err
-- +1 error:
let dummy_inout_text := proc_inout_text_out_text(a_string);

-- TEST: okay if used via a call statement
-- + {call_stmt}: ok
-- - error:
call proc_inout_text_out_text(a_string, a_string2);

-- used in the following test
proc proc_out_text_out_text(out a text, out b text)
begin
  set a := null;
  set b := null;
end;

-- TEST: proc-as-func disallows non-trailing OUT parameters
-- + error: % procedure with non-trailing OUT parameter used as function 'proc_out_text_out_text'
-- + {let_stmt}: err
-- + {call}: err
-- +1 error:
let dummy_proc_out := proc_out_text_out_text(a_string);

-- TEST: okay if used via a call statement
-- + {call_stmt}: ok
-- - error:
call proc_out_text_out_text(a_string, a_string2);

-- used in the following test
proc proc_out_text(out a text)
begin
  set a := null;
end;

-- TEST: okay with no parameters before the trailing out parameter
-- + {let_stmt}: proc_out_text_result: text variable
-- + {call}: text
-- - error:
let proc_out_text_result := proc_out_text();

-- used in the following test
proc proc_in_text_in_text_out_text(a text, b text, out c text)
begin
  set c := null;
end;

-- TEST: okay in a typical case
-- + {let_stmt}: proc_in_text_in_text_out_text_result: text variable
-- + {call}: text
-- - error:
let proc_in_text_in_text_out_text_result := proc_in_text_in_text_out_text("a", "b");

-- TEST: declare some constants we can use later
-- + {declare_const_stmt}: ok
-- + | {name foo}
-- + | {const_values}
-- + | {const_value}: bool = 0 notnull
-- + | | {name const_v}: bool = 0 notnull
-- + | | {bool 0}: bool = 0 notnull
-- + | {const_values}
-- + | {const_value}: real = 3.500000e+00 notnull
-- + | | {name const_w}: real = 3.500000e+00 notnull
-- + | | {dbl 3.5}: real = 3.500000e+00 notnull
-- + | {const_values}
-- + | {const_value}: longint = 1 notnull
-- + | | {name const_x}: longint = 1 notnull
-- + | | {longint 1}: longint = 1 notnull
-- + | {const_values}
-- + | {const_value}: integer = 5 notnull
-- + | | {name const_y}: integer = 5 notnull
-- + | | {add}: integer = 5 notnull
-- + |   | {int 2}: integer notnull
-- + |   | {int 3}: integer notnull
-- + | {const_values}
-- + | {const_value}: text notnull
-- + | {name const_z}: text notnull
-- + | {strlit 'hello, world
-- - error:
const group foo (
  const_v = false,
  const_w = 3.5,
  const_x = 1L,
  const_y = 2+3,
  const_z = "hello, world\n"
);

-- TEST: try to use the constants
-- + {let_stmt}: v: bool notnull variable
-- +  | {bool 0}: bool notnull
-- + {let_stmt}: w: real notnull variable
-- +  | {name w}: w: real notnull variable
-- +  | {dbl 3.500000e+00}: real notnull
-- + {let_stmt}: x: longint notnull variable
-- +  | {name x}: x: longint notnull variable
-- +  | {longint 1}: longint notnull
-- + {let_stmt}: y: integer notnull variable
-- +  | {name y}: y: integer notnull variable
-- +  | {int 5}: integer notnull
-- + {let_stmt}: z: text notnull variable
-- +  | {strlit 'hello, world
-- - error:
proc use_global_constants()
begin
  let v := const_v;
  let w := const_w;
  let x := const_x;
  let y := const_y;
  let z := const_z;
end;

-- TEST:  bad type form
-- + error: % string operand not allowed in 'NOT'
-- + {declare_const_stmt}: err
-- +1 error:
const group err1 (
  const_err1 = NOT 'x'
);

-- TEST: bad evaluation
-- + error: % global constants must be either constant numeric expressions or string literals 'const_err2 = 1 / 0'
-- + {declare_const_stmt}: err
-- +1 error:
const group err2 (
  const_err2 = 1 / 0
);

-- TEST: not a string literal
-- + error: % global constants must be either constant numeric expressions or string literals 'const_err3 = printf("bar")'
-- + {declare_const_stmt}: err
-- +1 error:
const group err3 (
  const_err3 = printf("bar")
);

-- TEST: duplicate constant
-- + error: % duplicate constant name 'const_v'
-- + {declare_const_stmt}: err
-- +1 error:
const group err4 (
  const_v = false
);

-- TEST: duplicate constant group that's different
-- + error: % CONST GROUP foo
-- + error: % CONST GROUP foo
-- + error: % const definitions do not match 'foo'
-- + {declare_const_stmt}: err
-- +3 error:
const group foo (
  const_v = false
);

-- TEST: existing constant group that's a duplciate
-- this is ok
-- + {declare_const_stmt}: ok alias
-- - error:
const group foo (
  const_v = false,
  const_w = 3.5,
  const_x = 1L,
  const_y = 2+3,
  const_z = "hello, world\n"
);

-- TEST: nested constants not allowed
-- + error: % declared constants must be top level 'err5'
-- + {declare_const_stmt}: err
-- +1 error:
proc try_to_nest_constants()
begin
  const group err5 (
   err5 = 1
  );
end;

-- TEST: emit constants for a valid name
-- + {emit_constants_stmt}: ok
-- - error:
@emit_constants foo;

-- TEST: try to emit constants for a bogus name
-- + error: % constant group not found 'not_found'
-- + {emit_constants_stmt}: err
-- +1 error:
@emit_constants not_found;

-- TEST: verify that we can identify a well shaped conditional fragment
-- + {create_proc_stmt}: conditional_frag: { id: integer notnull } dml_proc
-- - error:
[[shared_fragment]]
proc conditional_frag(bb int!)
begin
  if bb == 1 then
    with source(*) like foo
    select * from source;
  else if bb == 2 then
    with source2(*) like foo
    select * from source2 where x != bb;
  else
    with source(*) like foo
    select * from source where x = bb;
  end if;
end;

-- TEST: verify that we can use parameters in a conditional
-- + {create_proc_stmt}: conditional_user: { id: integer notnull } dml_proc
-- + {call_stmt}: conditional_frag: { id: integer notnull } dml_proc
-- + {name conditional_frag}: conditional_frag: { id: integer notnull } dml_proc
-- - error:
proc conditional_user(xx int!)
begin
  with D(*) AS (call conditional_frag(1) using foo as source, foo as source2)
  select * from D;
end;

-- TEST: base fragment that uses possible_conflict, this will later cause conflicts
-- no issues with just this
-- - error:
[[shared_fragment]]
proc fragtest_0_0()
begin
 with
   source(*) like (select 1 x),
   possible_conflict(*) as (select * from source)
 select * from possible_conflict;
end;

-- TEST: base fragment that uses inner frag 0, this will later cause conflicts
-- no issues with just this
-- - error:
[[shared_fragment]]
proc fragtest_0_1()
begin
 with
   source(*) like (select 1 x),
   (call fragtest_0_0() using source as source)
 select * from fragtest_0_0;
end;

-- TEST: base fragment that uses inner frag 1, this will later cause conflicts
-- no issues with just this
-- - error:
[[shared_fragment]]
proc fragtest_0_2()
begin
 with
   source(*) like (select 1 x),
   (call fragtest_0_1() using source as source)
 select * from fragtest_0_1;
end;

-- TEST: try to use fragtest_0_2 with 'possible_conflict' as the source -> error
-- this is going to fail because possible_conflict is already used deep inside this function
-- + error: % this use of the named shared fragment is not legal because of a name conflict 'fragtest_0_2'
-- + Procedure 'fragtest_0_0' has a different CTE that is also named 'possible_conflict'
-- + The above originated from CALL fragtest_0_0 USING possible_conflict AS source
-- + The above originated from CALL fragtest_0_1 USING possible_conflict AS source
-- + The above originated from CALL fragtest_0_2 USING possible_conflict AS source
-- +1 error:
with possible_conflict(*) as (select 1 x)
  select * from (call fragtest_0_2() using possible_conflict as source);

-- TEST: using the same fragment with a different name is fine, even if the name matches the formal name
-- + {with_select_stmt}: _select_: { x: integer notnull }
-- - error:
with source(*) as (select 1 x)
  select * from (call fragtest_0_2() using source as source);

-- TEST: a base fragment that is perfectly legal
-- - error:
[[shared_fragment]]
proc fragtest_1_0()
begin
 with
   source(*) like (select 1 x),
   possible_conflict(*) as (select * from source)
 select * from possible_conflict;
end;

-- TEST: this shared fragment includes a call that conflicts, we don't even have to use it
-- we already know it's wrong
-- + error: % this use of the named shared fragment is not legal because of a name conflict 'fragtest_1_0'
-- + Procedure 'fragtest_1_0' has a different CTE that is also named 'possible_conflict'
-- + The above originated from CALL fragtest_1_0 USING possible_conflict AS source
-- +1 error:
[[shared_fragment]]
proc fragtest_1_1()
begin
 with
   possible_conflict(*) as (select 1 x),
   (call fragtest_1_0() using possible_conflict as source)
 select * from fragtest_1_0;
end;

-- TEST: here 'possible_conflict' won't conflict because it is entirely local
-- setting this up the select ahead
-- - error:
[[shared_fragment]]
proc fragtest_2_0()
begin
 with
   possible_conflict(*) as (select 1 x)
 select * from possible_conflict;
end;

-- TEST: we're going to use a fragment with possible_conflict but it's entirely local
-- that will not cause any issues
-- +  {create_proc_stmt}: fragtest_2_1: { x: integer notnull } dml_proc
-- - error:
[[shared_fragment]]
proc fragtest_2_1()
begin
 with
   source(*) like (select 1 x),
   (call fragtest_2_0())
 select source.x from source join fragtest_2_0;
end;

-- TEST: now we create a nested call chain, this will bring in fragtest2_0 but
-- it will not do so in a way that creates a conflict.  possible_conflict will
-- stop in fragtest_2_1 and that one is not ambiguous with the one in fragtest2_0
-- + {with_select_stmt}: _select_: { x: integer notnull }
-- - error:
with possible_conflict(*) as (select 1 x)
  select * from (call fragtest_2_1() using possible_conflict as source);

-- TEST: use fragtest2_0 in such a way that the formal parameter name would conflict
-- but it doesn't count as a conflict because it's just the formal name
-- + {with_select_stmt}: _select_: { x: integer notnull }
-- - error:
[[shared_fragment]]
proc frag_not_really_a_conflict()
begin
 with
   possible_conflict(*) like (select 1 x)
 select * from (call fragtest_1_0() using possible_conflict as source);
end;

-- TEST: test doc comments being rewritten as attributes
-- + [[doc_comment="/** This is a doc comment */"]]
-- + PROC doc_comment_proc ()
-- - error:
/** This is a doc comment */
proc doc_comment_proc()
begin
end;

-- TEST: semantic check of good eponymous virtual table
-- + CREATE VIRTUAL TABLE @EPONYMOUS epon USING epon
-- + {create_virtual_table_stmt}: epon: { id: integer sensitive, t: text } virtual @recreate
-- - error
create virtual table @eponymous epon using epon
as (
  id integer @sensitive,
  t text
);

-- TEST: semantic check of eponymous virtual table that doesn't have matching module name
-- + error: % virtual table 'epony' claims to be eponymous but its module name 'epono' differs from its table name
-- + {create_virtual_table_stmt}: err
-- +1 error:
create virtual table @eponymous epony using epono
as (
  id integer @sensitive,
  t text
);

create table simple_shape(
  id integer,
  t text
);

create table simple_shape2(
  id integer,
  t text,
  u text
);

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT simple_shape2.id, simple_shape2.t, simple_shape2.u
-- - error:
select @columns(simple_shape2) from simple_shape2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT simple_shape2.id, simple_shape2.t, simple_shape2.u
-- - error:
select @columns(distinct simple_shape2, simple_shape2) from simple_shape2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT simple_shape2.id, simple_shape2.t
-- - error:
select @columns(distinct simple_shape2 like simple_shape) from simple_shape2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT id, t
-- - t, u
-- - error:
select @columns(like simple_shape) from simple_shape2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT T1.id, T1.t
-- - T1.u
-- - error:
select @columns(distinct like simple_shape) from simple_shape2 T1 join simple_shape2 T2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT T1.id, T1.t, T1.u
-- - error:
select @columns(distinct T1) from simple_shape2 T1 join simple_shape2 T2;

-- TEST: this is just a rewrite, validating correct column choice
-- + SELECT T1.id, T1.t, T1.u
-- - error:
select @columns(distinct T1, T2) from simple_shape2 T1 join simple_shape2 T2;

-- TEST: attempt to extract a bogus table from the join
-- + error: % table not found 'not_correct'
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(not_correct) from simple_shape;

-- TEST: attempt to extract a bogus column shape
-- + error: % must be a cursor, proc, table, or view 'this_is_not_a_shape'
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(simple_shape like this_is_not_a_shape) from simple_shape;

-- TEST: attempt to extract a bogus column shape with no table qualification
-- + error: % must be a cursor, proc, table, or view 'this_is_not_a_shape'
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(like this_is_not_a_shape) from simple_shape;

-- TEST: these columns don't exist, but the shapes are valid...
-- errors during expansion, the columns node stays in the tree
-- + SELECT @COLUMNS(LIKE with_kind)
-- + error: % name not found 'cost'
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(like with_kind) from simple_shape;

-- TEST: these columns don't exist, but the shapes are valid...
-- expansion failed so the COLUMNS node is not replaced
-- + SELECT @COLUMNS(simple_shape LIKE with_kind)
-- + error: % name not found 'simple_shape.cost'
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(simple_shape like with_kind) from simple_shape;

-- TEST: can't use the columns construct if there is no from clause
-- + error: % select *, T.*, or @columns(...) cannot be used with no FROM clause
-- + {select_stmt}: err
-- + {select_expr_list_con}: err
-- +1 error:
select @columns(like foo);

-- TEST: ensure that consecutive column rewrites link up properly
-- + SELECT
-- +   1 AS y,
-- +   T.id,
-- +   T.t,
-- +   T.u,
-- +   1 AS x
-- - error:
select 1 y, @columns(distinct T.id), @columns(T.t, T.u), 1 x from simple_shape2 T;

-- some simple shapes to match
create table two_col_v1(x integer, r real);
create table two_col_v2(x integer, t real);
create table two_col_v3(x integer, r text);

-- TEST: v3 has r text but v1 requires r real
-- + error: % required 'REAL' not compatible with found 'TEXT' context 'two_col_v3.r'
-- + {select_stmt}: err
-- + {column_calculation}: err
-- +1 error:
select @COLUMNS(two_col_v3 like two_col_v1) from two_col_v3;

-- TEST: v3 has r text but v2 requires t real
-- + error: % name not found 'two_col_v3.t'
-- + {select_stmt}: err
-- + {column_calculation}: err
-- +1 error:
select @COLUMNS(two_col_v3 like two_col_v2) from two_col_v3;

-- TEST: v3 has r text but v1 requires r real
-- + error: % required 'REAL' not compatible with found 'TEXT' context 'two_col_v3.r'
-- + {select_stmt}: err
-- + {column_calculation}: err
-- +1 error:
select @COLUMNS(like two_col_v1) from two_col_v3;

-- TEST: v3 has r text but v2 requires t real
-- + error: % name not found 't'
-- + {select_stmt}: err
-- + {column_calculation}: err
-- +1 error:
select @COLUMNS(like two_col_v2) from two_col_v3;

declare proc arg_shape(xyzzy integer);

-- TEST: verify that proc args are also valid shapes
-- + SELECT xyzzy
-- - error:
select @columns(like arg_shape arguments) from (select 1 xyzzy);

-- TEST: create a shared fragment with no from clause
-- + {create_proc_stmt}: inline_math: { result: integer } dml_proc
-- - error:
[[shared_fragment]]
proc inline_math(x_ integer, y_ integer)
begin
  select x_ + y_ result;
end;

-- TEST: invoke a shared fragment as an expression
-- + {create_proc_stmt}: do_inline_math: { result: integer } dml_proc
-- + {name inline_math}: integer inline_call
-- - error:
proc do_inline_math()
begin
  with N(i) as (
    select 1 i
    union all
    select i + 1 i from N
    limit 20
  )
  select inline_math(i, i+3) result from N;
end;

-- TEST: the fragment is ok on its own
-- but you can't use this fragment as an inline function
[[shared_fragment]]
proc inline_math_bad(x integer, y integer)
begin
  select x + y sum from (select 1 z);
end;

-- TEST: try to use a bogus fragment as an inline function
-- + error: % a shared fragment used like a function must be a simple SELECT with no FROM clause 'inline_math_bad'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad()
begin
  select inline_math_bad(1,2) bad;
end;

-- TEST: the fragment is ok on its own
-- it has a compound query so you can't use it in an expression
[[shared_fragment]]
proc inline_math_bad2()
begin
  select 1 x
  union all
  select 2 x;
end;

-- TEST: try to use a bogus fragment as an inline function
-- + error: % a shared fragment used like a function must be a simple SELECT with no FROM clause 'inline_math_bad2'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad2()
begin
  select inline_math_bad2() bad;
end;

-- TEST: the fragment has an error, can't use it
[[shared_fragment]]
proc inline_math_bad3()
begin
  select not 'x' y;
end;

-- TEST: try to use a bogus fragment as an inline function
-- + error: % procedure had errors, can't call 'inline_math_bad3'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad3()
begin
  select inline_math_bad3() bad;
end;

-- TEST: the fragment is ok on its own
-- it can't be used as an expression because it selects 2 values
[[shared_fragment]]
proc inline_math_bad4()
begin
  select 1 x, 2 y;
end;

-- TEST: try to use a bogus fragment as an inline function
-- + error: % nested select expression must return exactly one column 'inline_math_bad4'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad4()
begin
  select inline_math_bad4() bad;
end;

-- TEST: invoke a shared fragment as an expression
-- + error: % too few arguments provided to procedure 'inline_math'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad5()
begin
  select 1 where inline_math(2); -- wrong number of args
end;

[[shared_fragment]]
proc inline_frag(x integer)
begin
  select 1 x;
end;

-- TEST: invoke a shared fragment as an expression, try to use distinct
-- + error: % procedure as function call is not compatible with DISTINCT or filter clauses 'inline_frag'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad6()
begin
  select 1 where inline_frag(distinct 2);
end;

[[shared_fragment]]
declare proc declared_shared_fragment() (x integer);

-- TEST: try declare a fragment and use it without doing create proc
-- + error: % [[shared_fragment]] may only be placed on a CREATE PROC statement 'declared_shared_fragment'
-- + {create_proc_stmt}: err
-- + {shared_cte}: err
-- +1 error:
proc uses_declared_shared_fragment()
begin
  with
  x(*) as (call declared_shared_fragment())
  select * from x;
end;

-- TEST: invoke a shared fragment as an expression, try to use filter clause
-- + error: % procedure as function call is not compatible with DISTINCT or filter clauses 'inline_frag'
-- + {create_proc_stmt}: err
-- + {call}: err
-- +1 error:
proc do_inline_math_bad7()
begin
  select 1 where inline_frag(2) filter (where 1);
end;

[[shared_fragment]]
proc no_args_frag()
begin
  select 1 x, 2 y, 3.0 z;
end;

[[shared_fragment]]
proc nested_expression_fragment(x int!, y int!)
begin
  select (
    with
      (call no_args_frag())
    select f.x from no_args_frag f
  ) val;
end;

-- TEST: Using an expression fragment with nested fragment.
-- + {create_proc_stmt}: use_nested_expression_fragment: { val: integer } dml_proc
-- - error:
proc use_nested_expression_fragment()
begin
  select nested_expression_fragment(1, 2) val;
end;

[[shared_fragment]]
proc nested_expression_fragment_with_args1(x int!, y int!)
begin
  select (
    with
      (call a_shared_frag(*))
    select f.x from a_shared_frag f
  ) val;
end;


-- TEST: Using an expression fragment that contains a fragment with args fails
-- + error: % a shared fragment used like a function cannot nest fragments that use arguments 'nested_expression_fragment_with_args1'
-- +1 error:
proc use_nested_expression_fragment_with_args1()
begin
  select nested_expression_fragment_with_args1(1, 2) val;
end;

[[shared_fragment]]
proc nested_expression_fragment_with_args2(x int!, y int!)
begin
  select (
    select f.x from  (call a_shared_frag(*)) f
  ) val;
end;


-- TEST: Using an expression fragment that contains a fragment in a FROM clause with args fails
-- + error: % a shared fragment used like a function cannot nest fragments that use arguments 'nested_expression_fragment_with_args2'
-- +1 error:
proc use_nested_expression_fragment_with_args2()
begin
  select nested_expression_fragment_with_args2(1, 2) val;
end;

create table Shape_xy (x int, y int);
create table Shape_uv (u text, v text);
create table Shape_uvxy (like Shape_xy, like Shape_uv);

-- TEST: expand various insert_list forms using the FROM syntax
-- these are all rewrites so we verify that the rewrite was correct
-- these four forms are exhaustive
-- + INSERT INTO Shape_xy(x, y)
-- +   VALUES (C.x, C.y);
-- + INSERT INTO Shape_xy(x, y)
-- +   VALUES
-- +  (1, 2),
-- +  (3, 4),
-- +  (C.x, C.y);
-- + FETCH R(x, y, u, v) FROM VALUES (C.x, C.y, D.u, D.v);
-- + UPDATE CURSOR R(x, y, u, v) FROM VALUES (C.x, C.y, D.u, D.v);
-- + cte1 (l, m, n, o) AS (
-- +   VALUES (C.x, C.y, D.u, D.v)
-- + )
-- + cte2 (l, m, n, o) AS (
-- +  VALUES
-- +   (1, 2, '3', '4'),
-- +   (C.x, C.y, D.u, D.v)
-- + )
-- - error:
proc ShapeTrix()
begin
  cursor C for select Shape_xy.*, 1 u, 2 v from Shape_xy;
  fetch C;
  insert into Shape_xy values (from C like Shape_xy);
  insert into Shape_xy values (1,2), (3,4), (from C like Shape_xy);

  cursor D for select * from Shape_uv;
  fetch D;

  cursor R like Shape_uvxy;
  fetch R from values (from C like Shape_xy, from D);

  update cursor  R from values (from C like Shape_xy, from D);

  cursor S for
    with cte1(l,m,n,o) as (values (from C like Shape_xy, from D))
     select * from cte1;
  fetch S;

  cursor T for
    with cte2(l,m,n,o) as (values (1,2,'3','4'), (from C like Shape_xy, from D))
     select * from cte2;
  fetch S;
end;

-- TEST: bogus shape name in insert
-- + error: % name not found 'not_a_cursor'
-- +1 error:
proc ShapeTrixError1()
begin
  insert into Shape_xy values (from not_a_cursor like Shape_xy);
end;

-- TEST: bogus shape name in fetch cursor
-- + error: % name not found 'not_a_cursor'
-- +1 error:
proc ShapeTrixError2()
begin
  cursor R like Shape_uvxy;
  fetch R from values (from not_a_cursor);
end;

-- TEST: bogus shape name in update cursor
-- + error: % name not found 'not_a_cursor'
-- +1 error:
proc ShapeTrixError3()
begin
  cursor R like Shape_uvxy;
  fetch R() from values () @dummy_seed(1);
  update cursor R from values (from not_a_cursor);
end;

-- TEST: bogus shape name in values (fail later in the list)
-- + error: % name not found 'not_a_cursor'
-- +1 error:
proc ShapeTrixError4()
begin
  insert into Shape_xy values (1,2), (from not_a_cursor like Shape_xy);
end;

-- TEST: disallow use of sign in SQL
-- + @ENFORCE_STRICT SIGN FUNCTION;
-- + {enforce_strict_stmt}: ok
-- + {int 12}
-- - error:
@enforce_strict sign function;

-- TEST: sign cannot be used in SQL after `@enforce_strict sign function`
-- + error: % function may not be used in SQL because it is not supported on old versions of SQLite 'sign'
-- + {select_stmt}: err
-- +1 error:
select sign(-1);

-- TEST: sign still works outside of SQL
-- + {let_stmt}: sign_of_some_value: integer notnull variable
-- - error:
let sign_of_some_value := sign(-42);

-- TEST: allow use of sign in SQL once again
-- + @ENFORCE_NORMAL SIGN FUNCTION;
-- + {enforce_normal_stmt}: ok
-- + {int 12}
-- - error:
@enforce_normal sign function;

-- TEST: sign can be used in SQL normally
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- - error:
select sign(-1);

-- TEST: simple backing table
-- + {create_table_stmt}: simple_backing_table: { k: blob notnull primary_key, v: blob notnull } backing
-- - error:
[[backing_table]]
create table simple_backing_table(
  k blob primary key,
  v blob not null
);

-- TEST: simple backing table with no pk
-- + error: % table is not suitable for use as backing storage: it does not have a primary key 'simple_backing_table_missing_pk'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table simple_backing_table_missing_pk(
  k blob not null,
  v blob not null
);

-- TEST: simple backing table with only pk
-- + error: % table is not suitable for use as backing storage: it has only primary key columns 'simple_backing_table_only_pk'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table simple_backing_table_only_pk(
  k blob not null,
  v blob not null,
  primary key (k,v)
);

-- TEST: simple backing table loose pk with expression (error)
-- + error: % table is not suitable for use as backing storage: it has an expression in its primary key 'length(k)'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table simple_backing_table_expr_key(
  k blob,
  v blob,
  constraint pk1 primary key (length(k))
);

-- TEST: simple backing table with versions and pk external
-- + {create_table_stmt}: simple_backing_table_with_versions: { k: blob notnull partial_pk, v: blob notnull } deleted backing @create(1) @delete(22)
-- - error:
[[backing_table]]
create table simple_backing_table_with_versions(
  k blob not null,
  v blob not null,
  constraint pk_1 primary key (k)
) @create(1) @delete(22);

-- TEST: simple backed table
-- + {create_table_stmt}: simple_backed_table: { id: integer notnull primary_key, name: text<cool_text> notnull } backed
-- - error:
[[backed_by=simple_backing_table]]
create table simple_backed_table(
  id integer primary key,
  name text<cool_text> not null
);

[[backed_by=simple_backing_table]]
CREATE TABLE backed (
 status_id int primary key,
 global_connection_state long
);

ENUM an_enum INT (
  ONE = 1,
  TWO = 2
);

-- TEST: ensure that we do not lose type kind on the folded constant
-- + {create_proc_stmt}: use_enum_and_backing: { x: integer<an_enum> notnull } dml_proc
-- - error:
PROC use_enum_and_backing()
BEGIN
  SELECT an_enum.ONE AS x FROM backed;
END;

-- TEST: backed tables may not appear in a procedure
-- + error: % table is not suitable for use as backed storage: backed table must appear outside of any procedure 'backed_error'
-- + {create_table_stmt}: err
-- +1 error:
proc backed_decl()
begin
  [[backed_by=simple_backing_table]]
  create table backed_error (
   status_id int primary key,
   global_connection_state long
  );
end;

-- TEST: can't put triggers on backed tables
-- + error: % backed storage tables may not be used in indexes/triggers/drop 'simple_backed_table'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger bogus_backed_trigger
  before delete on simple_backed_table
begin
  delete from bar where rate > id;
end;

-- TEST: can't drop backed tables
-- + error: % backed storage tables may not be used in indexes/triggers/drop 'simple_backed_table'
-- + {drop_table_stmt}: err
-- +1 error:
drop table simple_backed_table;

-- TEST: can't put an index on backed tables
-- + error: % backed storage tables may not be used in indexes/triggers/drop 'simple_backed_table'
-- + {create_index_stmt}: err
-- +1 error:
create index oh_no_you_dont on simple_backed_table(id);

-- TEST: no primary key
-- + error: % table is not suitable for use as backed storage: it does not have a primary key 'no_pk_backed_table'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table no_pk_backed_table(
  id integer,
  name text not null
);

-- TEST: only primary key
-- + error: % table is not suitable for use as backed storage: it has only primary key columns 'only_pk_backed_table'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table only_pk_backed_table(
  id integer primary key
);

-- TEST: simple backed table loose pk
-- + {create_table_stmt}: simple_backed_table_2: { id: integer notnull partial_pk, name: text notnull } backed
-- - error:
[[backed_by=simple_backing_table]]
create table simple_backed_table_2(
  id integer,
  name text not null,
  constraint pk1 primary key (id)
);

-- TEST: simple backed table loose pk with expression (error)
-- + error: % table is not suitable for use as backed storage: it has an expression in its primary key 'id / 2'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table simple_backed_table_expr_key(
  id integer,
  name text not null,
  constraint pk1 primary key (id/2)
);

-- TEST: simple backed table with versions
-- + error: % table is not suitable for use as backed storage: it is declared using schema directives (@create or @delete 'simple_backed_table_with_versions'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table simple_backed_table_with_versions(
  id integer primary key,
  name text not null
) @create(2) @delete(12);

-- TEST: non blob columns are not valid in backing storage during stage 1
-- + error: % table is not suitable for use as backing storage: column 'id' has a column that is not a blob in 'has_non_blob_columns'
-- + {create_table_stmt}: err
-- +1 error
[[backing_table]]
create table has_non_blob_columns(
  id integer primary key,
  v blob not null
);

-- TEST: virtual tables cannot be backing storage
-- + error: % table is not suitable for use as backing storage: it is a virtual table 'virtual_backing_illegal'
-- + {create_virtual_table_stmt}: err
-- +1 error:
[[backing_table]]
create virtual table virtual_backing_illegal using module_name(args) as (
  id integer,
  t text
);

-- TEST: temp tables cannot be backing storage
-- + error: % table is not suitable for use as backing storage: it is redundantly marked TEMP 'temp_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create temp table temp_backing(
  id integer,
  t text
);

-- TEST: without rowid tables cannot be backing storage
-- + error: % table is not suitable for use as backing storage: it is redundantly marked WITHOUT ROWID 'norowid_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table norowid_backing(
  k blob,
  v blob
) without rowid;

-- TEST: tables with constraints cannot be backing storage
-- + error: % table is not suitable for use as backing storage: it has at least one invalid constraint 'constraint_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table constraint_backing(
  k blob primary key,
  v blob,
 CONSTRAINT ak1 UNIQUE (v)
);

-- TEST: table with column with primary key can be backing store
-- + {create_table_stmt}: pk_col_backing: { k: blob notnull primary_key, v: blob } backing
-- - error:
[[backing_table]]
create table pk_col_backing(
  k blob primary key,
  v blob
);

-- TEST: table with column with foreign key cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'id' has a foreign key in 'fk_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table fk_col_backing(
  id integer references foo(id),
  t text
);

-- TEST: table with column with unique key cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'id' has a unique key in 'uk_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table uk_col_backing(
  id integer unique,
  t text
);

-- TEST: table with hidden column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'v' is a hidden column in 'hidden_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table hidden_col_backing(
  k blob primary key,
  v blob hidden not null
);

-- TEST: table with autoinc column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'id' specifies auto increment in 'autoinc_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table autoinc_col_backing(
  id integer primary key autoincrement,
  v blob not null
);

-- TEST: table with conflict clause is ok for backing store
-- + {create_table_stmt}: conflict_clause_col_backing: { k: blob notnull primary_key, v: blob notnull } backing
-- - error:
[[backing_table]]
create table conflict_clause_col_backing(
  k blob primary key on conflict abort,
  v blob not null
);

-- TEST: table with check constraint on column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'id' has a check expression in 'check_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table check_col_backing(
  k blob primary key,
  id integer check(id = 5)
);

-- TEST: table with collate on column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 't' specifies collation order in 'collate_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table collate_col_backing(
  k blob primary key,
  t text collate nocase
);

-- TEST: table with default value on column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'id' has a default value in 'default_value_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table default_value_col_backing(
  id integer default 5,
  v blob not null
);

-- TEST: table with deleted column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'v' has delete attribute in 'deleted_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table deleted_col_backing(
  k blob primary key,
  v blob @delete(11)
);

-- TEST: table with create column cannot be backing store
-- + error: % table is not suitable for use as backing storage: column 'v' has create attribute in 'created_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table created_col_backing(
  k blob primary key,
  v blob @create(11)
);

-- TEST: table with @recreate is ok, it's really only interesting for in-memory tables
-- + {create_table_stmt}: recreate_backing: { k: blob notnull primary_key, v: blob notnull } backing @recreate
-- - error
[[backing_table]]
create table recreate_backing(
  k blob primary key,
  v blob not null
) @recreate;

-- TEST: table with @recreate is not valid
-- + error: % table is not suitable for use as backing storage: it does not have exactly two blob columns 'one_col_backing'
-- + {create_table_stmt}: err
-- +1 error:
[[backing_table]]
create table one_col_backing(
  k blob primary key
);

-- TEST: simple backed table with versions
-- + error: % table is not suitable for use as backed storage: it is declared using schema directives (@create or @delete 'simple_backed_table_versions'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table simple_backed_table_versions(
  id integer primary key,
  name text not null
) @create(2) @delete(12);

-- TEST: virtual tables cannot be backed storage
-- + error: % table is not suitable for use as backed storage: it is a virtual table 'virtual_backed_illegal'
-- + {create_virtual_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create virtual table virtual_backed_illegal using module_name(args) as (
  id integer,
  t text
);

-- TEST: temp tables cannot be backed storage
-- + error: % table is not suitable for use as backed storage: it is redundantly marked TEMP 'temp_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create temp table temp_backed(
  id integer,
  t text
);

-- TEST: table is backed by a table that does not exist
-- + error: % table is not suitable for use as backed storage: backing table does not exist 'not_exists_table'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=not_exists_table]]
create table backed_by_not_exists(
  id integer,
  t text
);

-- TEST: table is backed by a table that is not backing storage
-- + error: % table is not suitable for use as backed storage: table exists but is not a valid backing table 'foo'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=foo]]
create table backed_by_non_backing(
  id integer,
  t text
);

-- TEST: without rowid tables cannot be backed storage
-- + error: % table is not suitable for use as backed storage: it is redundantly marked WITHOUT ROWID 'norowid_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table norowid_backed(
  id integer,
  t text
) without rowid;

-- TEST: tables with constraints cannot be backed storage
-- + error: % table is not suitable for use as backed storage: it has at least one invalid constraint 'constraint_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table constraint_backed(
  id integer,
  t text,
 CONSTRAINT ak1 UNIQUE (id)
);

-- TEST: table with column with primary key can be backed store
-- + {create_table_stmt}: pk_col_backed: { id: integer notnull primary_key, t: text } backed
-- - error:
[[backed_by=simple_backing_table]]
create table pk_col_backed(
  id integer primary key,
  t text
);

-- TEST: table with column with foreign key cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 'id' has a foreign key in 'fk_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table fk_col_backed(
  id integer references foo(id),
  t text
);

-- TEST: table with column with unique key cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 'id' has a unique key in 'uk_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table uk_col_backed(
  id integer unique,
  t text
);

-- TEST: table with hidden column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 'id' is a hidden column in 'hidden_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table hidden_col_backed(
  id integer hidden,
  t text
);

-- TEST: table with autoinc column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 'id' specifies auto increment in 'autoinc_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table autoinc_col_backed(
  id integer primary key autoincrement,
  t text
);

-- TEST: table with autoinc column cannot be backed store
-- + {create_table_stmt}: conflict_clause_col_backed: { id: integer notnull primary_key, t: text } backed
-- - error:
[[backed_by=simple_backing_table]]
create table conflict_clause_col_backed(
  id integer primary key on conflict abort,
  t text
);

-- TEST: table with check constraint on column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 'id' has a check expression in 'check_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table check_col_backed(
  id integer check(id = 5),
  t text
);

-- TEST: table with collate on column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 't' specifies collation order in 'collate_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table collate_col_backed(
  id integer,
  t text collate nocase
);

-- TEST: table with default value on column -- ok for backed store
-- + {create_table_stmt}: default_value_col_backed: { id: integer notnull primary_key, x: integer notnull has_default, t: text } backed
-- - error:
[[backed_by=simple_backing_table]]
create table default_value_col_backed(
  id integer primary key,
  x int! default 7,
  t text
);

-- TEST: table with deleted column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 't' has delete attribute in 'deleted_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table deleted_col_backed(
  id integer,
  t text @delete(7)
);

-- TEST: table with create column cannot be backed store
-- + error: % table is not suitable for use as backed storage: column 't' has create attribute in 'created_col_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table created_col_backed(
  id integer,
  t text @create(7)
);

-- TEST: table with non matching @recreate is not valid
-- + error: % table is not suitable for use as backed storage: @recreate attribute doesn't match the backing table 'recreate_backed'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=simple_backing_table]]
create table recreate_backed(
  id integer primary key,
  t text
) @recreate;

-- TEST: table with non matching @recreate is not valid
-- + error: % table is not suitable for use as backed storage: @recreate group doesn't match the backing table 'recreate_backed_wrong_group'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=recreate_backing]]
create table recreate_backed_wrong_group(
  id integer primary key,
  t text
) @recreate(wrong_group_name);

-- TEST: simple json backing table for later test
-- - error:
[[backing_table]]
[[json]]
create table json_backing(
  k blob primary key,
  v blob
);

-- TEST: json backed tables may not hold blobs
-- + error: % table is not suitable for use as backed storage: column 'x' is a blob column, but blobs cannot appear in tables backed by JSON in 'backed_with_blobs'
-- + {create_table_stmt}: err
-- +1 error:
[[backed_by=json_backing]]
create table backed_with_blobs(
  pk int primary key,
  x blob
);

[[blob_storage]]
create table structured_storage(
  id int!,
  name text not null
);

-- TEST: verify basic analysis of structure storage, correct case
-- + {name C}: C: _select_: { id: integer notnull, name: text notnull } variable dml_proc shape_storage serialize
-- + {name a_blob}: a_blob: blob<structured_storage> notnull variable init_required was_set
-- + {name D}: D: _select_: { id: integer notnull, name: text notnull } variable shape_storage value_cursor serialize
-- + {name a_blob}: a_blob: blob<structured_storage> notnull variable was_set
-- - error:
proc blob_serialization_test()
begin
  cursor C for select 1 id, 'foo' name;
  fetch C;

  declare a_blob blob<structured_storage>!;
  C:to_blob(a_blob);

  cursor D like C;
  D:from_blob(a_blob);
end;

-- TEST: verify basic analysis of structure storage, correct case
-- + error: % cursor not declared with 'LIKE table_name', blob type can't be inferred 'C'
-- + {let_stmt}: err
-- + {call}: err
-- +1 error:
proc cannot_infer_blob_type()
begin
  cursor C for select 1 id, 'foo' name;
  fetch C;
  let a_blob := C:to_blob;
end;

-- TEST: ok to store the blob if blob and type specified and they match
-- + {name C}: C: _select_: { id: integer notnull, name: text notnull } variable dml_proc shape_storage serialize
-- + {name a_blob}: a_blob: blob<structured_storage> notnull variable init_required was_set
-- + {call_stmt}: ok dml_proc
-- + {name cql_cursor_to_blob}: ok dml_proc
-- - error:
proc use_direct_blob_forms()
begin
  cursor C for select 1 id, 'foo' name;
  fetch C;

  declare a_blob blob<structured_storage>!;
  C:to_blob(a_blob);
end;

-- TEST: blob type not specified, this cannot do this store
-- + CALL cql_cursor_to_blob(C, a_blob);
-- + error: % blob variable must have a type-kind for type safety 'a_blob'
-- + {call_stmt}: err
-- +1 error:
proc use_direct_to_blob_badly()
begin
  cursor C for select 1 id, 'foo' name;
  fetch C;

  declare a_blob blob!;
  C:to_blob(a_blob);
end;

-- TEST: blob type not specified, this cannot do this store
-- + CALL cql_cursor_from_blob(C, a_blob);
-- + error: % blob variable must have a type-kind for type safety 'a_blob'
-- + {call_stmt}: err
-- +1 error:
proc use_direct_from_blob_badly()
begin
  cursor C like select 1 id, 'foo' name;

  let a_blob := (select 'x' ~blob~);
  C:from_blob(a_blob);
end;

[[backed_by=simple_backing_table]]
create table basic_table(
  id integer primary key,
  name text<cool_text>
);

[[backed_by=simple_backing_table]]
create table basic_table2(
  id integer primary key,
  name text
);

-- TEST: correct call to blob_get_type
-- + {name cql_blob_get_type}: longint sensitive
-- - error:
proc blob_get_type()
begin
  declare x blob @sensitive;
  let z := (select cql_blob_get_type(basic_table2, x));
end;

-- TEST: incorrect call to blob_get_type, not even a name
-- + error: % argument 1 must be a table name that is a backed table 'cql_blob_get_type'
-- + {select_stmt}: err
-- +1 error:
proc blob_get_type_not_a_table()
begin
  declare x blob @sensitive;
  let z := (select cql_blob_get_type(1, x));
end;

-- TEST: incorrect call to blob_get_type, invalid table name
-- + error: % table/view not defined 'not_a_table_name'
-- + {select_stmt}: err
-- +1 error:
proc blob_get_type_not_a_table_name()
begin
  declare x blob @sensitive;
  let z := (select cql_blob_get_type(not_a_table_name, x));
end;

-- TEST: incorrect call to blob_get_type, table is not backed/backing
-- + error: % the indicated table is not declared for backed or backing storage 'foo'
-- + {select_stmt}: err
-- +1 error:
proc blob_get_type_not_a_backed_table_name()
begin
  declare x blob @sensitive;
  let z := (select cql_blob_get_type(foo, x));
end;

-- TEST: blob get type wrong argument count
-- + error: % function got incorrect number of arguments 'cql_blob_get_type'
-- + {call}: err
-- +1 error:
proc blob_get_type_wrong_arg_count()
begin
  declare x blob;
  let z := (select cql_blob_get_type());
end;

-- TEST: blob get type wrong argument type
-- + error: % required 'BLOB' not compatible with found 'INT' context 'cql_blob_get_type arg2'
-- + {call}: err
-- +1 error:
proc blob_get_type_wrong_arg_type()
begin
  let z := (select cql_blob_get_type(basic_table2, 1));
end;

-- TEST: blob get type arg expression has errors
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- +1 error:
proc blob_get_type_bad_expr()
begin
  let z := (select cql_blob_get_type(basic_table2, not "x"));
end;

-- TEST: blob get type called outside of SQL context
-- + error: % function may not appear in this context 'cql_blob_get_type'
-- + {call}: err
-- +1 error:
proc blob_get_type_context_wrong()
begin
  declare x blob;
  let z :=  cql_blob_get_type(x);
end;

-- TEST: correct call to blob_get
-- + {call}: integer notnull
-- + {name cql_blob_get}: integer notnull
-- - error:
proc blob_get()
begin
  declare x blob;
  let z := (select cql_blob_get(x, basic_table.id));
end;

-- TEST: blob get table not using a table.column as the 2nd arg
-- + error: % argument must be table.column where table is a backed table
-- + {call}: err
-- +1 error:
proc blob_get_not_dot_operator()
begin
  declare x blob;
  let z := (select cql_blob_get(x, 1 + 2));
end;

-- TEST: blob get table doesn't exist
-- + error: % table/view not defined 'table_not_exists'
-- + {call}: err
-- +1 error:
proc blob_get_table_wrong()
begin
  declare x blob;
  let z := (select cql_blob_get(x, table_not_exists.id));
end;

-- TEST: blob get column doesn't exist
-- + error: % the indicated column is not present in the named backed storage 'basic_table.col_not_exists'
-- + {call}: err
-- +1 error:
proc blob_get_column_wrong()
begin
  declare x blob;
  let z := (select cql_blob_get(x, basic_table.col_not_exists));
end;

-- TEST: blob get wrong argument count
-- + error: % function got incorrect number of arguments 'cql_blob_get'
-- + {call}: err
-- +1 error:
proc blob_get_column_wrong_arg_count()
begin
  declare x blob;
  let z := (select cql_blob_get(x));
end;

-- TEST: blob get called outside of SQL context
-- + error: % function may not appear in this context 'cql_blob_get'
-- + {call}: err
-- +1 error:
proc blob_get_column_context_wrong()
begin
  declare x blob;
  let z :=  cql_blob_get(x);
end;

-- TEST: blob get wrong argument type
-- + error: % required 'INT' not compatible with found 'BLOB' context 'cql_blob_get arg1'
-- + {call}: err
-- +1 error:
proc blob_get_column_wrong_arg_type()
begin
  let z := (select cql_blob_get(1, basic_table.id));
end;

-- TEST: blob get arg expression has errors
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- +1 error:
proc blob_get_column_bad_expr()
begin
  let z := (select cql_blob_get(not "x", basic_table.id));
end;

-- TEST: blob get table expression is not a backing table
-- + error: % the indicated table is not declared for backed storage 'simple_backing_table'
-- + {call}: err
-- +1 error:
proc blob_get_not_backed_table()
begin
  declare x blob;
  let z := (select cql_blob_get(x, simple_backing_table.k));
end;

-- TEST: correct call to cql_blob_update
-- + {call}: blob notnull
-- + {name cql_blob_update}: blob notnull
-- - error:
proc blob_update()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, basic_table.id));
end;

-- TEST: correct cql_blob_update arg 1 is not a valid expr
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- +1 error:
proc blob_update_bogus_arg1()
begin
  let z := (select cql_blob_update(not 'x', 1, basic_table.id));
end;

-- TEST: cql blob update mixed tables
-- + error: % the indicated table is not consistently used through all of cql_blob_update 'basic_table2'
-- + {call}: err
-- +1 error:
proc blob_update_different_tables()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, basic_table.id, 2, basic_table2.id));
end;

-- TEST: cql_blob_update first arg not a table
-- + error: % required 'BLOB' not compatible with found 'INT' context 'cql_blob_update arg1'
-- + {call}: err
-- +1 error:
proc blob_update_arg_one_error()
begin
  declare not_a_blob integer;
  let z := (select cql_blob_update(not_a_blob, 1, basic_table.id));
end;

-- TEST: blob update not using a table.column as the 3nd arg
-- + error: % argument must be table.column where table is a backed table
-- + {call}: err
-- +1 error:
proc blob_update_not_dot_operator()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, 1 + 2));
end;

-- TEST: blob update not using a table.column in a later arg
-- + error: % argument must be table.column where table is a backed table
-- + {call}: err
-- +1 error:
proc blob_update_not_dot_operator_later_arg()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, basic_table.id, 2, 1 + 2));
end;

-- TEST: blob update table doesn't exist
-- + error: % table/view not defined 'table_not_exists'
-- + {call}: err
-- +1 error:
proc blob_update_table_wrong()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, table_not_exists.id));
end;

-- TEST: blob update table doesn't exist
-- + error: % table/view not defined 'table_not_exists'
-- + {call}: err
-- +1 error:
proc blob_update_table_wrong_later_arg()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, basic_table.id, 2, table_not_exists.id));
end;

-- TEST: blob update column doesn't exist
-- + error: % the indicated column is not present in the named backed storage 'basic_table.col_not_exists'
-- + {call}: err
-- +1 error:
proc blob_update_column_wrong()
begin
  declare b blob;
  let z := (select cql_blob_update(b, 1, basic_table.col_not_exists));
end;

-- TEST: blob update wrong argument count
-- + error: % function got incorrect number of arguments 'cql_blob_update'
-- + {call}: err
-- +1 error:
proc blob_update_column_wrong_arg_count()
begin
  declare b blob;
  let z := (select cql_blob_update(b));
end;

-- TEST: blob update called outside of SQL context
-- + error: % function may not appear in this context 'cql_blob_update'
-- + {call}: err
-- +1 error:
proc blob_update_column_context_wrong()
begin
  declare b blob;
  let z :=  cql_blob_update(x);
end;

-- TEST: blob update wrong argument type
-- + error: % required 'TEXT' not compatible with found 'INT' context 'cql_blob_update value'
-- + {call}: err
-- +1 error:
proc blob_update_column_wrong_arg_type()
begin
  declare b blob;
  let z := (select cql_blob_update(b, "x", basic_table.id));
end;

-- TEST: blob update arg expression has errors
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- +1 error:
proc blob_update_column_bad_expr()
begin
  declare b blob;
  let z := (select cql_blob_update(b, not "x", basic_table.id));
end;

-- TEST: blob update table expression is not a backing table
-- + error: % the indicated table is not declared for backed storage 'simple_backing_table'
-- + {call}: err
-- +1 error:
proc blob_update_not_backed_table()
begin
  declare b blob;
  let z := (select cql_blob_update(b, x, simple_backing_table.k));
end;

-- TEST: table with lots of default values
-- + {create_table_stmt}: bt_default: { pk1: integer notnull has_default partial_pk, pk2: integer notnull has_default partial_pk, x: integer has_default, y: integer has_default } backed
-- - error
[[backed_by=simple_backing_table]]
create table bt_default(
  pk1 integer default 2222,
  pk2 integer default 99,
  x int default 1111,
  y int default 42,
  constraint pk primary key (pk1, pk2)
);

-- TEST: generate defaults for pk2 and y but pk1 and x
-- + WITH
-- + _vals (pk1, x) AS (
-- +   VALUES (1, 2)
-- + )
-- + INSERT INTO simple_backing_table(k, v)
-- + SELECT cql_blob_create
-- + FROM _vals AS V;
-- these match in the middle of the line
-- * cql_blob_create(bt_default, V.pk1, bt_default.pk1, 99, bt_default.pk2),
-- * cql_blob_create(bt_default, V.x, bt_default.x, 42, bt_default.y)
-- default values for specified columns should be absent
-- - 1111,
-- - 2222,
insert into bt_default(pk1,x) values (1, 2);

--  TEST: insert into backing table in upsert form
-- verify rewrite
-- + WITH
-- + _vals (id, name) AS (
-- +  VALUES (1, 'foo')
-- + )
-- + INSERT INTO simple_backing_table(k, v)
-- + SELECT cql_blob_create(basic_table, V.id, basic_table.id), cql_blob_create(basic_table, V.name, basic_table.name)
-- + FROM _vals AS V
-- + ON CONFLICT (k)
-- + DO NOTHING;
-- + {with_upsert_stmt}: ok
-- - error:
INSERT INTO basic_table(id, name) values (1, 'foo')
  ON CONFLICT(id) DO NOTHING;

-- TEST: upsert form, with update
-- verify the rewrite
-- + INSERT INTO simple_backing_table(k, v)
-- + SELECT cql_blob_create(basic_table, V.id, basic_table.id), cql_blob_create(basic_table, V.name, basic_table.name)
-- +  FROM _vals AS V
-- + ON CONFLICT (k)
-- + DO UPDATE
-- + SET k = cql_blob_update(k, cql_blob_get(k, basic_table.id) + 1, basic_table.id)
-- + {shared_cte}: _basic_table: { rowid: longint notnull, id: integer notnull, name: text<cool_text> } dml_proc
-- + {update_stmt}: simple_backing_table: { k: blob notnull primary_key, v: blob notnull } backing
-- - error:
INSERT INTO basic_table
  SELECT id + 3, name FROM basic_table WHERE id < 100
  on conflict(id)
  do UPDATE SET id = id + 1 WHERE id < 100;

-- TEST: upsert form, bogus table
-- + error: % table in insert statement does not exist 'bogus_table_not_present'
-- + {upsert_stmt}: err
-- +1 error:
INSERT INTO bogus_table_not_present VALUES (1,2) on conflict(id) do nothing;

-- TEST: upsert form, update and with clause
-- verify the rewrite
-- + WITH
-- + basic_table (rowid, id, name) AS (CALL _basic_table()),
-- + a_useless_cte (x, y) AS (
-- +  SELECT 1, 2
-- + ),
-- + _vals (id, name) AS (
-- +   SELECT id + 3, name
-- +   FROM basic_table
-- +   WHERE id < 123
-- + )
-- + INSERT INTO simple_backing_table(k, v)
-- + SELECT cql_blob_create(basic_table, V.id, basic_table.id), cql_blob_create(basic_table, V.name, basic_table.name)
-- + FROM _vals AS V
-- + ON CONFLICT (k)
-- + DO UPDATE
-- + SET k = cql_blob_update(k, cql_blob_get(k, basic_table.id) + 1, basic_table.id)
-- + WHERE cql_blob_get(k, basic_table.id) < 456;
-- + {shared_cte}: _basic_table: { rowid: longint notnull, id: integer notnull, name: text<cool_text> } dml_proc
-- + {update_stmt}: simple_backing_table: { k: blob notnull primary_key, v: blob notnull } backing
-- - error:
with a_useless_cte(x, y) as (select 1 ,2)
insert into basic_table select id + 3, name from basic_table where id < 123
on conflict(id)
do update set id = id + 1 where id < 456;

-- TEST: correct call to cql_blob_create
-- + {call}: blob notnull
-- + {name cql_blob_create}: blob notnull
-- - error:
proc blob_create()
begin
  let z := (select cql_blob_create(basic_table, 1, basic_table.id));
end;

-- TEST: cql_blob_create arg 1 is not even a string
-- + error: % argument 1 must be a table name that is a backed table 'cql_blob_create'
-- + {call}: err
-- +1 error:
proc blob_create_not_a_string()
begin
  let z := (select cql_blob_create(1, 1, basic_table.id));
end;

-- TEST: cql blob create mixed tables
-- + error: % the indicated table is not consistently used through all of cql_blob_create 'basic_table2'
-- + {call}: err
-- +1 error:
proc blob_create_different_tables()
begin
  let z := (select cql_blob_create(basic_table, 1, basic_table.id, 2, basic_table2.id));
end;

-- TEST: cql_blob_create first arg not a table
-- + error: % table/view not defined 'not_a_table'
-- + {call}: err
-- +1 error:
proc blob_create_arg_one_error()
begin
  let z := (select cql_blob_create(not_a_table, 1, basic_table.id));
end;

-- TEST: blob create not using a table.column as the 3nd arg
-- + error: % argument must be table.column where table is a backed table
-- + {call}: err
-- +1 error:
proc blob_create_not_dot_operator()
begin
  let z := (select cql_blob_create(basic_table, 1, 1 + 2));
end;

-- TEST: blob create table doesn't exist
-- + error: % table/view not defined 'table_not_exists'
-- + {call}: err
-- +1 error:
proc blob_create_table_wrong()
begin
  let z := (select cql_blob_create(basic_table, 1, table_not_exists.id));
end;

-- TEST: blob create column doesn't exist
-- + error: % the indicated column is not present in the named backed storage 'basic_table.col_not_exists'
-- + {call}: err
-- +1 error:
proc blob_create_column_wrong()
begin
  declare x blob;
  let z := (select cql_blob_create(basic_table, 1, basic_table.col_not_exists));
end;

-- TEST: blob create wrong argument count
-- + error: % function got incorrect number of arguments 'cql_blob_create'
-- + {call}: err
-- +1 error:
proc blob_create_column_wrong_arg_count()
begin
  declare x blob;
  let z := (select cql_blob_create());
end;

-- TEST: blob create called outside of SQL context
-- + error: % function may not appear in this context 'cql_blob_create'
-- + {call}: err
-- +1 error:
proc blob_create_column_context_wrong()
begin
  declare x blob;
  let z :=  cql_blob_create(x);
end;

-- TEST: blob create wrong argument type
-- + error: % required 'TEXT' not compatible with found 'INT' context 'cql_blob_create'
-- + {call}: err
-- +1 error:
proc blob_create_column_wrong_arg_type()
begin
  let z := (select cql_blob_create(basic_table, "x", basic_table.id));
end;

-- TEST: blob create arg expression has errors
-- + error: % string operand not allowed in 'NOT'
-- + {call}: err
-- +1 error:
proc blob_create_column_bad_expr()
begin
  let z := (select cql_blob_create(basic_table, not "x", basic_table.id));
end;

-- TEST: blob create table expression is not a backing table
-- + error: % the indicated table is not declared for backed storage 'simple_backing_table'
-- + {call}: err
-- +1 error:
proc blob_create_not_backed_table()
begin
  let z := (select cql_blob_create(simple_backing_table, x, simple_backing_table.k));
end;

-- TEST: verify type check on columns
-- + error: % in the cursor and the blob type, all columns must be an exact type match (expected integer notnull; found text notnull) 'name'
-- +1 error:
proc blob_serialization_test_type_mismatch()
begin
  cursor C for select 1 id, 5 name;
  fetch C;
  declare B blob<structured_storage>!;
  C:to_blob(B);
end;

-- TEST: verify blob type is a table
-- + error: % blob type is not a valid table 'not_a_table'
-- +1 error:
proc blob_serialization_test_type_not_a_table()
begin
  cursor C for select 1 id, 'name' name;
  fetch C;
  declare B blob<not_a_table>!;
  C:to_blob(B);
end;

-- TEST: verify blob type is not a view (better error for this case)
-- + error: % blob type is a view, not a table 'MyView'
-- +1 error:
proc blob_serialization_test_type_is_a_view()
begin
  cursor C for select 1 id, 'name' name;
  fetch C;

  declare B blob<MyView>!;

  C:to_blob(B);
end;

-- TEST: verify blob type has a type kind
-- + error: % blob variable must have a type-kind for type safety 'B'
-- +1 error:
proc blob_serialization_test_type_has_no_kind()
begin
  cursor C for select 1 id, 'name' name;
  fetch C;

  declare B blob!;
  C:to_blob(B);
end;

-- TEST: verify blob fetch from cursor; cursor has storage
-- + error: % cursor was not used with 'fetch [cursor]' 'C'
-- + error: % additional info: calling 'cql_cursor_to_blob' argument #1 intended for parameter 'C' has the problem
-- +2 error:
proc blob_serialization_test_no_storage()
begin
  cursor C for select 1 id, 5 name;

  declare B blob<structured_storage>;
  C:to_blob(B);
end;


-- TEST: verify blob fetch from cursor; valid cursor
-- + error: % name not found 'not_a_cursor'
-- +1 error:
proc blob_serialization_test_valid_cursor()
begin
  cursor C for select 1 id, 5 name;

  declare B blob<structured_storage>;

  set B from cursor not_a_cursor;
end;

-- TEST: blob storage types must use cql:blob_storage
-- + error: % the indicated table is not marked with [[blob_storage]] 'foo'
-- + {call_stmt}: err
-- +1 error:
proc blob_serialization_not_storage_table()
begin
  declare b blob<foo>;
  cursor C like foo;
  C:from_blob(b);
end;

-- TEST: can't put triggers on structured storage
-- + error: % the indicated table may only be used for blob storage 'structured_storage'
-- + {create_trigger_stmt}: err
-- +1 error:
create trigger storage_trigger
  before delete on structured_storage
begin
  delete from bar where rate > id;
end;

-- TEST: can't drop structured storage
-- + error: % the indicated table may only be used for blob storage 'structured_storage'
-- + {drop_table_stmt}: err
-- +1 error:
drop table structured_storage;

-- TEST: can't delete from structured storage
-- + error: % the indicated table may only be used for blob storage 'structured_storage'
-- + {delete_stmt}: err
-- +1 error:
delete from structured_storage where 1;

-- TEST: can't put an index on structured storage
-- + error: % the indicated table may only be used for blob storage 'structured_storage'
-- + {create_index_stmt}: err
-- +1 error:
create index oh_no_you_dont on structured_storage(id);

-- TEST: virtual tables cannot be blob storage
-- + error: % table is not suitable for use as blob storage: it is a virtual table 'virtual_blob_storage_illegal'
-- + {create_virtual_table_stmt}: err
-- +1 error:
[[blob_storage]]
create virtual table virtual_blob_storage_illegal using module_name(args) as (
  id integer,
  t text
);

-- TEST: temp tables cannot be blob storage
-- + error: % table is not suitable for use as blob storage: it is redundantly marked TEMP 'temp_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create temp table temp_blob_storage(
  id integer,
  t text
);

-- TEST: without rowid tables cannot be blob storage
-- + error: % table is not suitable for use as blob storage: it is redundantly marked WITHOUT ROWID 'norowid_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table norowid_blob_storage(
  id integer,
  t text
) without rowid;

-- TEST: tables with constraints cannot be blob storage
-- + error: % table is not suitable for use as blob storage: it has at least one constraint 'constraint_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table constraint_blob_storage(
  id integer,
  t text,
 CONSTRAINT ak1 UNIQUE (id)
);

-- TEST: table with column with primary key cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' has a primary key in 'pk_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table pk_col_blob_storage(
  id integer primary key,
  t text
);

-- TEST: table with column with foreign key cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' has a foreign key in 'fk_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table fk_col_blob_storage(
  id integer references foo(id),
  t text
);

-- TEST: table with column with unique key cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' has a unique key in 'uk_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table uk_col_blob_storage(
  id integer unique,
  t text
);

-- TEST: table with hidden column cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' is a hidden column in 'hidden_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table hidden_col_blob_storage(
  id integer hidden,
  t text
);

-- TEST: table with check constraint on column cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' has a check expression in 'check_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table check_col_blob_storage(
  id integer check(id = 5),
  t text
);

-- TEST: table with collate on column cannot be blob
-- + error: % table is not suitable for use as blob storage: column 't' specifies collation order in 'collate_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table collate_col_blob_storage(
  id integer,
  t text collate nocase
);

-- TEST: table with default value on column cannot be blob
-- + error: % table is not suitable for use as blob storage: column 'id' has a default value in 'default_value_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table default_value_col_blob_storage(
  id integer default 5,
  t text
);

-- TEST: table with deleted column cannot be blob
-- + error: % table is not suitable for use as blob storage: column 't' has been deleted in 'deleted_col_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table deleted_col_blob_storage(
  id integer,
  t text @delete(7)
);

-- TEST: table with @recreate is not valid
-- + error: % table is not suitable for use as blob storage: it is declared using @recreate 'recreate_blob_storage'
-- + {create_table_stmt}: err
-- +1 error:
[[blob_storage]]
create table recreate_blob_storage(
  id integer,
  t text
) @recreate;

-- TEST: structured storage cannot appear inside a FROM clause
-- + error: % the indicated table may only be used for blob storage 'structured_storage'
-- + {select_stmt}: err
-- + {select_from_etc}: err
-- + {table_or_subquery_list}: err
-- + {table_or_subquery}: err
-- +1 error:
select * from structured_storage;

-- TEST: enable strict has-row check enforcement for the following tests
-- + @ENFORCE_STRICT CURSOR HAS ROW
-- + {enforce_strict_stmt}: ok
-- - error:
@enforce_strict cursor has row;

-- used in the following tests
create table has_row_check_table (a text not null, b text);

-- used in the following tests
[[blob_storage]]
create table has_row_check_blob (a text not null, b text);

-- TEST: accessing an auto cursor field of a nonnull reference type is not
-- possible before verifying that the cursor has a row
-- + error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c.a'
-- + {create_proc_stmt}: err
-- + {let_stmt}: err
-- + {let_stmt}: y: text variable
-- +1 error:
proc has_row_check_required_before_using_nonnull_reference_field()
begin
  cursor c for select * from has_row_check_table;
  fetch c;
  -- Illegal due to `c.a` having type `TEXT NOT NULL`.
  let x := c.a;
  -- Legal.
  let y := c.b;
end;

-- TEST: both positive and negative checks work for the has-row case, as with
-- nullability
-- + {create_proc_stmt}: err
-- +2 {let_stmt}: err
-- + {let_stmt}: x1: text notnull variable
-- + {let_stmt}: x3: text notnull variable
-- +2 error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c.a'
-- +2 error:
proc has_row_checks_can_be_positive_or_negative()
begin
  cursor c for select * from has_row_check_table;
  fetch c;
  -- Illegal.
  let x0 := c.a;
  if c then
    -- Legal due to a positive check.
    let x1 := c.a;
  end if;
  -- Illegal.
  let x2 := c.a;
  if not c then
    let dummy := "hello";
    return;
  end if;
  -- Legal due to a negative check.
  let x3 := c.a;
end;

-- TEST: the fetch values form does not require a check because it cannot fail
-- + error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c3.a'
-- + {create_proc_stmt}: err
-- + {let_stmt}: x0: text notnull variable
-- + {let_stmt}: x1: text notnull variable
-- + {let_stmt}: x2: text notnull variable
-- + {let_stmt}: err
-- +1 error:
proc fetch_values_requires_no_has_row_check(like has_row_check_table)
begin
  cursor c0 like has_row_check_table;
  fetch c0 from values ("text", null);
  -- Legal due to the fetch values form.
  let x0 := c0.a;

  cursor c1 like has_row_check_table;
  fetch c1 from arguments;
  -- Legal due to the fetch values form.
  let x1 := c1.a;

  declare b blob<has_row_check_blob>;
  cursor c2 like has_row_check_blob;
  c2:from_blob(b);
  -- Legal due to the from blob we just did
  let x2 := c2.a;

  cursor c3 for select * from has_row_check_table;
  fetch c3;
  -- Illegal.
  let x3 := c3.a;
end;

-- TEST: re-fetching a cursor requires another has-row check
-- + error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c.a'
-- + {create_proc_stmt}: err
-- + {let_stmt}: x0: text notnull variable
-- + {let_stmt}: err
-- + {let_stmt}: x2: text notnull variable
-- +1 error:
proc fetching_again_requires_another_check()
begin
  cursor c for select * from has_row_check_table;
  fetch c;
  if not c return;
  -- Legal due to a negative check.
  let x0 := c.a;
  fetch c;
  -- Illegal due to a re-fetch.
  let x1 := c.a;
  if c then
    -- Legal again due to a positive check.
    let x2 := c.a;
  end if;
end;

-- TEST: the loop form does not require a has-row check because the loop only
-- executes when the cursor has a row
-- + error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c.a'
-- + {create_proc_stmt}: err
-- + {let_stmt}: x0: text notnull variable
-- + {let_stmt}: err
-- +1 error:
proc fetching_with_loop_requires_no_check()
begin
  cursor c for select * from has_row_check_table;
  loop fetch c
  begin
    -- Legal due to the loop only running if we have a row.
    let x0 := c.a;
  end;
  -- Illegal due to being outside of the loop.
  let x1 := c.a;
end;

-- TEST: fetching a cursor within a loop unimproves it earlier in the loop
-- unless the cursor was improved by the loop condition
-- + error: % field of a nonnull reference type accessed before verifying that the cursor has a row 'c0.a'
-- + {create_proc_stmt}: err
-- +1 {let_stmt}: err
-- + {let_stmt}: x1: text notnull variable
-- +1 error:
proc refetching_within_loop_may_unimprove_cursor_earlier_in_loop()
begin
  cursor c0 for select * from has_row_check_table;
  cursor c1 for select * from has_row_check_table;
  fetch c0;
  if not c0 return;
  loop fetch c1
  begin
    -- illegal due to the fetch later in the loop
    let x0 := c0.a;
    -- legal despite the fetch later in the loop due to the loop condition
    let x1 := c1.a;
    fetch c0;
    fetch c1;
  end;
end;

-- TEST: disable strict has-row check enforcement
-- + @ENFORCE_NORMAL CURSOR HAS ROW
-- + {enforce_normal_stmt}: ok
-- - error:
@enforce_normal cursor has row;

-- TEST: an ok var group
-- + {declare_group_stmt}: ok
-- + {declare_vars_type}: integer
-- + {declare_cursor_like_name}: var_group_var2: foo: { id: integer notnull primary_key autoinc } variable shape_storage value_cursor
-- + {declare_cursor_like_select}: var_group_var3: _select_: { x: integer notnull, y: text notnull } variable shape_storage value_cursor
-- - error:
group var_group
begin
  declare var_group_var1 integer;
  cursor var_group_var2 like foo;
  cursor var_group_var3 like select 1 x, "2" y;
end;

-- TEST: duplicate var group is ok
-- + {declare_group_stmt}: ok alias
-- - error:
group var_group
begin
  declare var_group_var1 integer;
  cursor var_group_var2 like foo;
  cursor var_group_var3 like select 1 x, "2" y;
end;

-- TEST: non-duplicate var group = error
-- + error: % variable definitions do not match in group 'var_group'
-- + {declare_group_stmt}: err
-- additional error lines (for the difference report)
-- +3 error:
group var_group
begin
  declare var_group_var1 integer;
end;

-- TEST: variable group must be top level
-- + error: % group declared variables must be top level 'var_group'
-- + {create_proc_stmt}: err
-- + {declare_group_stmt}: err
-- +1 error:
proc proc_contains_var_group()
begin
  group var_group
  begin
    declare var_group_var1 integer;
  end;
end;

-- TEST: variable group may contain errors
-- + error: % duplicate variable name in the same scope 'var_group_var_dup'
-- + {declare_group_stmt}: err
-- +1 error:
group var_group_error
begin
  declare var_group_var_dup integer;
  declare var_group_var_dup integer;
end;

-- TEST: ok to emit
-- + {emit_group_stmt}: ok
-- - error:
@emit_group var_group;

-- TEST: not ok to emit
-- + error: % group not found 'not_a_var_group'
-- + {emit_group_stmt}: err
-- +1 error:
@emit_group not_a_var_group;

create table unsub_test_table(id integer primary key);

create table unsub_test_table_deleted(id integer) @delete(2);

create table unsub_test_table_late_create(id integer) @create(7);

-- TEST: unsub on non physical tables makes no sense
-- + error: % unsubscribe does not make sense on non-physical tables 'structured_storage'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(structured_storage);

-- TEST: unsub directive invalid table
-- + error: % the table/view named in an @unsub directive does not exist 'not_a_table'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(not_a_table);

-- TEST: table is visible
-- + {select_stmt}: _select_: { id: integer notnull }
-- - error:
select * from unsub_test_table;

-- TEST: successful unsub
-- + {schema_unsub_stmt}: ok
-- + unsub_test_table
-- - error:
@unsub(unsub_test_table);

-- TEST: table is not visible
-- + error: % table/view not defined (hidden by @unsub) 'unsub_test_table'
-- + {select_stmt}: err
-- +1 error:
select * from unsub_test_table;

-- TEST: duplicate unsub
-- + error: % table/view is already unsubscribed 'unsub_test_table'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(unsub_test_table);

-- TEST: table order doesn't matter, you can unsub regardless of when it was created
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(unsub_test_table_late_create);

-- TEST: already deleted table
-- + error: % table/view is already deleted 'unsub_test_table_deleted'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(unsub_test_table_deleted);

-- TEST: can't add a dependency on an unsubscribed table
-- + error: % foreign key refers to non-existent table (hidden by @unsub) 'unsub_test_table'
-- + {create_table_stmt}: err
-- +1 error
create table sub_test_dependency(
  id integer references unsub_test_table(id)
);

-- create a dependency chain
create table unsub_test_table2(id integer primary key);
create table sub_test_dependency2(id integer references unsub_test_table2(id));

-- TEST: can't do this, unsub_test_table still refers to this table
-- + error: % @unsub is invalid because the table/view is still used by 'sub_test_dependency2'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub (unsub_test_table2);

-- TEST: ok to remove the leaf table
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(sub_test_dependency2);

-- TEST: now ok to remove the other table
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(unsub_test_table2);

-- TEST: setup unsub test case for table in use by a view
-- - error:
create table used_by_a_view(
  id integer
);

-- TEST: setup unsub test case for table in use by a view
-- - error:
create view uses_a_table as select * from used_by_a_view;

-- TEST: setup unsub test case for table in use by a deleted view
-- - error:
create table used_by_a_deleted_view(
  id integer
);

-- TEST: setup unsub test case for table in use by a deleted view
-- - error:
create view uses_a_table_but_deleted as select * from used_by_a_deleted_view @delete(2);

-- TEST: can't delete this table, a view still uses it
-- + error: % @unsub is invalid because the table/view is still used by 'uses_a_table'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(used_by_a_view);

-- TEST: ok to delete this table, a view still uses it, but it's deleted
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(used_by_a_deleted_view);

-- TEST: setup unsub test case for table in use by triggers
create table unrelated(
  id integer
);

-- TEST: setup unsub test case for table in use by a trigger
-- - error:
create table used_by_a_trigger(
  id integer
);

-- TEST: setup unsub test case for table in use by a trigger
-- - error:
create trigger trigger_uses_a_table
  before delete on unrelated
begin
  delete from used_by_a_trigger;
end;

-- TEST: setup unsub test case for table in use by a deleted trigger
-- - error:
create table used_by_a_deleted_trigger(
  id integer
);

-- TEST: setup unsub test case for table in use by a deleted trigger
-- - error:
create trigger trigger_uses_a_table_but_deleted
  before delete on unrelated
begin
  delete from used_by_a_deleted_trigger;
end @delete(5);

-- TEST: can't delete this table, a trigger still uses it
-- + error: % @unsub is invalid because the table/view is still used by 'trigger_uses_a_table'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(used_by_a_trigger);

-- TEST: ok to delete this table, a trigger still uses it, but it's deleted
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(used_by_a_deleted_trigger);


-- TEST: this is just setup stuff
-- - error:
create table unsub_with_views_test_table(id integer);
-- - error:
create view unsub_with_views_v1 as select * from unsub_with_views_test_table;
-- - error:
create view unsub_with_views_v2 as select * from unsub_with_views_v1;
-- - error:
create view unsub_with_views_v3 as select * from unsub_with_views_v1;
-- - error:
create view unsub_with_views_v4 as select * from unsub_with_views_test_table;
-- - error:
create view unsub_with_views_v5 as select * from unsub_with_views_v4;

-- - error:
create trigger unsub_with_views_annoying_trigger
  before delete on unsub_with_views_test_table
begin
  delete from unsub_with_views_test_table where (select id from unsub_with_views_v3);
end;

-- TEST: v2 can be removed, nothing depends on it
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(unsub_with_views_v2);

-- TEST: v1 can't be removed because v3 depends on it
-- + error: % @unsub is invalid because the table/view is still used by 'unsub_with_views_v3'
-- +1 error:
@unsub(unsub_with_views_v1);

-- TEST: can't unsub v3 because of annoying trigger
-- + error: % @unsub is invalid because the table/view is still used by 'unsub_with_views_annoying_trigger'
-- + {schema_unsub_stmt}: err
-- +1 error:
@unsub(unsub_with_views_v3);

-- TEST: v5 can be removed, nothing depends on it
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(unsub_with_views_v5);

-- TEST: v4 can be removed, nothing depends on it but v5 which is gone already
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(unsub_with_views_v4);

declare proc any_args_at_all no check;

-- TEST: check locals rewrite
-- verify the rewrites
-- + CALL any_args_at_all(LOCALS.x, LOCALS.y);
-- + CALL any_args_at_all(LOCALS.x, LOCALS.y, LOCALS.z);
-- + CALL any_args_at_all(LOCALS.x, LOCALS.y, LOCALS.z, LOCALS.u);
-- verify that type and kind flow correctly
-- + {let_stmt}: z: integer<x> notnull variable
-- + {let_stmt}: u: integer<x> notnull variable
proc use_locals_expansion(x integer<x> not null, y integer<y>)
begin
  call any_args_at_all(from locals);
  let z := locals.x;
  call any_args_at_all(from locals);
  let u := locals.z;
  call any_args_at_all(from locals);
end;

-- TEST: bogus scoped local
-- + error: % expanding FROM LOCALS, there is no local matching 'xyzzy'
-- + {call_stmt}: err
-- +1 error:
proc bogus_local_usage()
begin
  call any_args_at_all(locals.xyzzy);
end;

-- TEST: there are no locals
-- + error: % expanding FROM LOCALS, there is no local matching 'xyzzy'
-- + {let_stmt}: err
-- +1 error:
let no_chance_of_this_working := locals.xyzzy;

-- TEST: try to use locals scope with no locals
-- + error: % name not found 'locals'
-- + {call_stmt}: err
-- +1 error:
call any_args_at_all(from locals);

-- TEST: locals work with nullability improvements
-- + {create_proc_stmt}: ok
-- +4 {call_stmt}: ok
-- - error:
proc locals_work_with_nullability_improvements(a_ int)
begin
  declare b int;
  declare c_ int;

  if a_ is null or b is null or locals.c is null return;

  call requires_not_nulls(a_, b, c_);
  call requires_not_nulls(from locals like requires_not_nulls arguments);
  call requires_not_nulls(from locals);
  call requires_not_nulls(*);
end;

-- setup for the resub test
-- - error:
create table parent_subs_table (
  id integer primary key
) @create(9) @delete(25);

-- setup for the resub test
create table child_subs_table (
  id integer primary key references parent_subs_table(id)
) @create(9) @delete(25);

-- for self referencing
create table self_ref_table(
  id integer primary key,
  id2 integer references self_ref_table(id)
) @create(10);

-- TEST: ok to unsub to a table that refers to itself
-- + {schema_unsub_stmt}: ok
-- - error:
@unsub(self_ref_table);

-- TEST: this generates an error and creates an unresolved arg list
-- + error: % name not found 'does_not_exist'
-- + {declare_proc_stmt}: err
-- + {like}: err
-- +1 error:
declare proc broken_thing(LIKE does_not_exist arguments);

-- TEST: attempting to use a proc with errors for the arg list has to fail
-- + error: % name not found (proc had errors, cannot be used) 'broken_thing'
-- + {declare_proc_stmt}: err
-- + {typed_name}: err
-- + {like}: err
-- +1 error:
declare proc uses_broken_thing() (LIKE broken_thing arguments);

-- TEST: declare an external function that accepts a cursor
-- + {declare_func_stmt}: integer
-- + {name external_cursor_func}: integer
-- + {params}: ok
-- + {param}: x: cursor variable in
-- + {param_detail}: x: cursor variable in
-- + {name x}: x: cursor variable in
-- + {type_cursor}: cursor
func external_cursor_func(x cursor) integer;

-- TEST: try to call a function with a cursor argument
-- + {let_stmt}: result: integer variable
-- + {name result}: result: integer variable
-- + {name external_cursor_func}
-- + {arg_list}: ok
-- + {name shape_storage}: shape_storage: _select_: { one: integer notnull, two: integer notnull } variable dml_proc shape_storage
let result := external_cursor_func(shape_storage);

-- TEST: bogus arg to cursor func
-- + error: % not a cursor '1'
-- + error: % additional info: calling 'external_cursor_func' argument #1 intended for parameter 'x' has the problem
-- +  {assign}: err
-- +  | {call}: err
-- +2 error:
set result := external_cursor_func(1);
DECLARE PROC uses_broken_thing() (LIKE broken_thing ARGUMENTS);

-- TEST: attempting to define interface with the same name as proc
-- + {declare_interface_stmt}: err
INTERFACE proc4 (id INT);

-- TEST: attempting to define interface
-- + {declare_interface_stmt}: interface1: { id: integer }
-- - error:
INTERFACE interface1 (id INT);

-- TEST: attempting to redefine interface with the same signature
-- + {declare_interface_stmt}: interface1: { id: integer }
-- - error:
INTERFACE interface1 (id INT);

-- TEST: attempting to redefine column with the same name
-- + error: % duplicate column name 'id'
-- + {declare_interface_stmt}: err
-- +1 error:
INTERFACE interface1 (id INT, id TEXT);

-- TEST: attempting to redefine interface with different signature
-- + error: % INTERFACE interface1 (id INT)
-- + error: % INTERFACE interface1 (id INT, name TEXT)
-- + The above must be identical.
-- + error: % interface declarations do not match 'interface1'
-- + {declare_interface_stmt}: err
-- +3 error:
INTERFACE interface1 (id INT, name TEXT);

-- TEST: attempting to define interface with two columns
-- + {declare_interface_stmt}: interface2: { id: integer, name: text }
-- - error:
INTERFACE interface2 (id INT, name TEXT);

-- TEST: this procedure uses interface for its args
-- verify that the args are rewritten correctly
-- + PROC interface_source (id_ INT, name_ TEXT)
-- + {create_proc_stmt}: ok
-- - error:
proc interface_source(like interface2)
begin
end;

-- TEST: this procedure correctly implements interface
-- + PROC test_interface1_implementation_correct (id_ INT, name_ TEXT)
-- + {create_proc_stmt}: test_interface1_implementation_correct: { id: integer, name: text } dml_proc
-- - error:
[[implements=interface1]]
proc test_interface1_implementation_correct(id_ INT, name_ TEXT)
begin
  select id_ id, name_ name;
end;

-- TEST: this procedure returns NOT NULL id column instead of NULLABLE
-- + PROC test_interface1_implementation_wrong_nullability (id_ INT!)
-- + error: % actual column types need to be the same as interface column types (expected integer; found integer notnull) 'id'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface1]]
proc test_interface1_implementation_wrong_nullability(id_ INT not null)
begin
  select id_ id, "5" col2;
end;

-- TEST: this procedure returns TEXT NOT NULL id column instead of INT NOT NULL
-- + PROC test_interface1_implementation_wrong_type (id_ TEXT!)
-- + error: % actual column types need to be the same as interface column types (expected integer; found text notnull) 'id'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface1]]
proc test_interface1_implementation_wrong_type(id_ TEXT not null)
begin
  select id_ id, "5" col2;
end;

-- TEST: this procedure returns id column as second column instead of first, this is ok
-- + PROC test_interface1_implementation_wrong_order (id_ INT, name_ TEXT)
-- + {create_proc_stmt}: test_interface1_implementation_wrong_order: { name: text, id: integer } dml_proc
-- - error:
[[implements=interface1]]
proc test_interface1_implementation_wrong_order(id_ INT, name_ TEXT)
begin
  select name_ name, id_ id;
end;

-- TEST: first returned column has incorrect name
-- + PROC test_interface1_implementation_wrong_name (id_ INT, name_ TEXT)
-- + error: % procedure 'test_interface1_implementation_wrong_name' is missing column 'id' of interface 'interface1'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface1]]
proc test_interface1_implementation_wrong_name(id_ INT, name_ TEXT)
begin
  select id_ id2, name_ name;
end;

-- TEST: procedure does not return all columns from the interface
-- + PROC test_interface1_missing_column (id_ INT, name_ TEXT)
-- + error: % procedure 'test_interface1_missing_column' is missing column 'name' of interface 'interface2'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface2]]
proc test_interface1_missing_column(id_ INT, name_ TEXT)
begin
  select id_ id;
end;

-- TEST: implementing interface that's not defined
-- + PROC test_interface1_missing_interface (id_ INT, name_ TEXT)
-- + error: % interface not found 'missing_interface'
-- + {name missing_interface}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=missing_interface]]
proc test_interface1_missing_interface(id_ INT, name_ TEXT)
begin
  select id_ id, name_ name;
end;

-- TEST: redefining interface as proc (declare)
-- + DECLARE PROC interface1 (id_ INT, name_ TEXT)
-- + error: % proc name conflicts with interface name 'interface1'
-- + {declare_proc_stmt}: err
-- +1 error:
declare proc interface1(id_ INT, name_ TEXT);

-- TEST: redefining interface as proc (create)
-- + PROC interface1 (id_ INT, name_ TEXT)
-- + error: % proc name conflicts with interface name 'interface1'
-- + {create_proc_stmt}: err
-- + {name interface1}: err
-- +1 error:
proc interface1(id_ INT, name_ TEXT)
begin
  select id_ id2, name_ name;
end;

-- interfaces for multi-interface test cases
declare interface interface_foo1 (id int!, name text not null);
declare interface interface_foo2 (id2 int!, name text not null);

-- TEST: two interfaces, one not supported
-- + error: % procedure 'interface_proc1' is missing column 'id2' of interface 'interface_foo2'
-- + {misc_attrs}: err
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface_foo1]]
[[implements=interface_foo2]]
proc interface_proc1()
begin
   select 1 id, "2" name;
end;

-- TEST: two interfaces, both supported
-- + create_proc_stmt}: interface_proc2: { id: integer notnull, name: text notnull, id2: integer
-- - error:
[[implements=interface_foo1]]
[[implements=interface_foo2]]
proc interface_proc2()
begin
   select 1 id, "2" name, 3 id2;
end;

INTERFACE interface_base (foo OBJECT<interface1>);
INTERFACE interface_base_bad (foo OBJECT<also_not_an_interface>);

-- TEST interface implemented is a subtype of the base, `interface2` is ok
-- + {stmt_and_attr}: ok
-- + {create_proc_stmt}: C: interface_proc_subtype: { foo: object<interface2> } variable shape_storage uses_out value_cursor
-- - error:
[[implements=interface_base]]
proc interface_proc_subtype()
begin
   cursor C like (foo object<interface2>);
   fetch C from values(null);
   out C;
end;

-- TEST interface implemented is not a subtype of the base
-- + error: % actual column types need to be the same as interface column types (expected integer; found integer notnull) 'id'
-- + error: % required column interface_base :: 'foo OBJECT<interface1>' actual column procedure interface_proc_subtype_with_error :: 'foo OBJECT<interface_foo1>'
-- + {create_proc_stmt}: err
-- +2 error:
[[implements=interface_base]]
proc interface_proc_subtype_with_error()
begin
   -- this interface does not match
   cursor C like (foo object<interface_foo1>);
   fetch C from values(null);
   out C;
end;

-- TEST type kind doesn't match and not an interface
-- + error: % interface not found 'garbonzo'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface_base]]
proc interface_proc_non_interface_kind_with_error()
begin
   -- this interface does not match because it isn't an interface type
   cursor C like  (foo object<garbonzo>);
   fetch C from values(null);
   out C;
end;

-- TEST type kind doesn't match -- empty actual
-- + error: % required column interface_base :: 'foo OBJECT<interface1>' actual column procedure interface_proc_no_kind_with_error :: 'foo OBJECT'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface_base]]
proc interface_proc_no_kind_with_error()
begin
   -- this interface does not match because it has no type kind
   cursor C like  (foo object);
   fetch C from values(null);
   out C;
end;

-- TEST type kind doesn't match -- base is not an interface
-- + error: % interface not found 'also_not_an_interface'
-- + {create_proc_stmt}: err
-- +1 error:
[[implements=interface_base_bad]]
proc interface_proc_bad_base_interface_with_error()
begin
   -- this interface does not match the required type has a kind that is not an interface
   cursor C like  (foo object<interface2>);
   fetch C from values(null);
   out C;
end;

-- TEST: declare unchecked functions (allows variadic params and uses the cheaper calling convention)
-- external native functions get regular C strings arguments not string references just like
-- unchecked procs.  This is so procs like printf have a chance to be called.
-- + {declare_func_no_check_stmt}: text
-- + {name no_check_func}: text
-- + {func_params_return}
-- + {type_text}: text
-- - error:
func no_check_func no check text;

-- TEST: call with various args
-- + {expr_stmt}: text
-- + {call}: text
-- + {name no_check_func}
-- + {int 1}: integer notnull
-- + {int 2}: integer notnull
-- + {int 3}: integer notnull
-- - error:
no_check_func(1,2,3);

-- TEST: call with various different args
-- + {expr_stmt}: text
-- + {call}: text
-- + {name no_check_func}
-- + {strlit 'a'}: text notnull
-- + {int 1}: integer notnull
-- - error:
no_check_func("a", 1);

-- TEST: call with no args
-- + {expr_stmt}: text
-- + {call}: text
-- + {name no_check_func}
-- - {arg_list}: ok
-- - error:
no_check_func();

-- TEST: args are validated but not against a prototype
-- + error: % string operand not allowed in 'NOT'
-- + {expr_stmt}: err
-- + {call}: err
-- + {arg_list}: err
-- + {not}: err
-- +1 error:
no_check_func(1, not "x");


-- TEST: declare unchecked select functions (allows variadic UDF params)
-- + {declare_select_func_no_check_stmt}: text select_func
-- + {name no_check_select_fun}: text
-- + {func_params_return}
-- + {type_text}: text
-- - error:
declare select function no_check_select_fun no check text;

-- TEST: redeclare unchecked select function
-- - error:
declare select function no_check_select_fun no check text;

-- TEST: redeclare unchecked select function as checked fails
-- + error: % function cannot be both a normal function and an unchecked function 'no_check_select_fun'
declare select function no_check_select_fun() text;

-- TEST: calling unchecked function
-- + {select_expr}: text
-- + {call}: text
-- + {name no_check_select_fun}
-- + {call_arg_list}
-- + {call_filter_clause}
-- + {arg_list}: ok
-- + {int 0}: integer notnull
-- + {arg_list}
-- + {strlit 'hello'}: text notnull
-- - error:
select no_check_select_fun(0, "hello");

-- TEST: calling unchecked select function with invalid argument fails
-- + error: in star : CQL0051: argument can only be used in count(*) '*'
-- +1 error:
select no_check_select_fun(*);

-- TEST: declaring unchecked table valued select function
-- + {declare_select_func_no_check_stmt}: _select_: { t: text, i: integer } select_func
-- + {name no_check_select_table_valued_fun}: _select_: { t: text, i: integer }
-- + {func_params_return}
-- + {typed_names}: _select_: { t: text, i: integer }
-- + {typed_name}: t: text
-- + {name t}
-- + {type_text}: t: text
-- + {typed_names}
-- + {typed_name}: i: integer
-- + {name i}
-- + {type_int}: i: integer
-- - error:
declare select function no_check_select_table_valued_fun no check (t text, i int);

-- TEST: calling unchecked table valued select function
-- + {select_from_etc}: TABLE { no_check_select_table_valued_fun: _select_ } table_valued_function
-- + {table_or_subquery_list}: TABLE { no_check_select_table_valued_fun: _select_ } table_valued_function
-- + {table_or_subquery}: TABLE { no_check_select_table_valued_fun: _select_ } table_valued_function
-- + {table_function}: TABLE { no_check_select_table_valued_fun: _select_ } table_valued_function
-- + {name no_check_select_table_valued_fun}: TABLE { no_check_select_table_valued_fun: _select_ } table_valued_function
-- + {arg_list}: ok
-- + {int 0}: integer notnull
-- + {arg_list}
-- + {strlit 'hello'}: text notnull
-- - error:
select t, i from no_check_select_table_valued_fun(0, "hello");

-- TEST: calling unchecked table valued function with invalid argument fails
-- + error: in star : CQL0051: argument can only be used in count(*) '*'
-- +1 error:
select t, i from no_check_select_table_valued_fun(*);

-- TEST: redefining interface as proc (declare ... no check)
-- + {declare_proc_no_check_stmt}: err
declare procedure interface1 no check;

-- TEST: redefining func as interface
-- + {declare_interface_stmt}: err
INTERFACE maybe_create_func_text (id INT, name TEXT);

-- TEST: try to declare a interface inside a proc
-- + error: % declared interface must be top level 'foo'
-- +1 error:
proc nested_interface_wrapper()
begin
  declare interface foo(LIKE interface1);
end;

proc test_parent(x_ int!)
begin
  select x_ x, 1 y, nullable(1) u, 1 v;
end;

proc test_child(x_ int!)
begin
  select x_ x, 1 z, 1 u, nullable(1) v;
end;

-- TEST: Verify that the rewrite is successful including arg pass through
-- + PROC test_parent_child ()
-- + BEGIN
-- +   DECLARE __result__0 BOOL!;
-- +   CURSOR __key__0 LIKE test_child(x);
-- +   LET __partition__0 := cql_partition_create();
-- +   CURSOR __child_cursor__0 FOR
-- +     CALL test_child(1);
-- +   LOOP FETCH __child_cursor__0
-- +   BEGIN
-- +     FETCH __key__0(x) FROM VALUES (__child_cursor__0.x);
-- +     SET __result__0 := cql_partition_cursor(__partition__0, __key__0, __child_cursor__0);
-- +   END;
-- +   CURSOR __out_cursor__0 LIKE (x INT!, y INT!,%my_child OBJECT<test_child SET>!);
-- +   CURSOR __parent__0 FOR
-- +     CALL test_parent(2);
-- +   LOOP FETCH __parent__0
-- +   BEGIN
-- +     FETCH __key__0(x) FROM VALUES (__parent__0.x);
-- +     FETCH __out_cursor__0(x, y,%my_child) FROM VALUES (__parent__0.x, __parent__0.y,%cql_extract_partition(__partition__0, __key__0));
-- +     OUT UNION __out_cursor__0;
-- +   END;
-- + END;
-- + {create_proc_stmt}: % test_parent_child: { x: integer notnull, y: integer notnull,%my_child: object<test_child SET> notnull } variable dml_proc shape_storage uses_out_union value_cursor
-- - error:
proc test_parent_child()
begin
  out union
   call test_parent(2) join call test_child(1) using (x) as my_child;
end;

-- TEST: same rewrite with default column name
-- + {create_proc_stmt}: % test_parent_child2: { x: integer notnull, y: integer notnull,%child1: object<test_child SET> notnull } variable dml_proc shape_storage uses_out_union value_cursor
proc test_parent_child2()
begin
  out union
   call test_parent(2) join call test_child(1) using (x);
end;

-- TEST: invalid parent -- not a proc
-- + error: % name not found 'does_not_exist'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_parent1()
begin
  out union
   call does_not_exist(2) join call test_child(1) using (x);
end;

-- TEST: invalid parent -- no result set
-- + error: % proc has no result 'decl1'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_parent2()
begin
  out union
   call decl1(2) join call test_child(1) using (x);
end;

-- TEST: invalid parent -- proc had errors
-- + error: % name not found (proc had errors, cannot be used) 'invalid_identity'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_parent3()
begin
  out union
   call invalid_identity(2) join call test_child(1) using (x);
end;

-- TEST: invalid child -- not a proc
-- + error: % name not found 'does_not_exist'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_child()
begin
  out union
   call test_parent(2) join call does_not_exist(1) using (x);
end;

-- TEST: poarent child, bogus join column
-- + error: % name not found (in parent) 'z'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_join_parent()
begin
  out union
   call test_parent(2) join call test_child(1) using (z);
end;

-- TEST: poarent child, bogus join column
-- + error: % name not found (in child) 'y'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_join_child()
begin
  out union
   call test_parent(2) join call test_child(1) using (y);
end;

-- TEST: poarent child, bogus join column
-- + error: % cannot assign/copy possibly null expression to not null target (parent result is nullable) 'u'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_join_parent_nullable()
begin
  out union
   call test_parent(2) join call test_child(1) using (u);
end;

-- TEST: poarent child, bogus join column
-- + error: % cannot assign/copy possibly null expression to not null target (child result is nullable) 'v'
-- + {create_proc_stmt}: err
-- +1 error:
proc test_parent_child_invalid_join_child_nullable()
begin
  out union
   call test_parent(2) join call test_child(1) using (v);
end;

-- TEST: verify that type kinds that require particular shapes are getting them
-- + error: % must be a cursor, proc, table, or view 'goo'
-- + error: % object<T SET> has a T that is not a procedure with a result set 'C SET'
-- + {declare_vars_type}: object<C CURSOR>
-- + {declare_vars_type}: object<test_parent_child SET>
-- +2 error:
proc test_object_types()
begin
  cursor C like (id integer);
  declare u object<goo cursor>;
  declare w object<C cursor>;
  declare x object<C set>;
  declare y object<test_parent_child set>;
end;

-- TEST: verify semantic types of cql_compressed (ok)
-- + {let_stmt}: compressed_string: text notnull variable
-- - error:
let compressed_string := cql_compressed("foo foo");

-- TEST: verify cql_compressed fails in sql context
-- + error: % function may not appear in this context 'cql_compressed'
-- + {assign}: err
-- +1 error
set compressed_string := (select cql_compressed('hello hello'));

-- TEST: verify semantic types of cql_compressed (too many args)
-- + error: % function got incorrect number of arguments 'cql_compressed'
-- + {assign}: err
-- +1 error:
set compressed_string := cql_compressed("foo foo", 1);

-- TEST: verify semantic types of cql_compressed (not a string)
-- + error: % first argument must be a string literal 'cql_compressed'
-- + {assign}: err
-- +1 error:
set compressed_string := cql_compressed(1);

-- - error:
create table dummy_table_for_backed_test(id integer);

-- TEST: extract columns from backed table
-- ensure kind "cool_text" is preserved
-- + {declare_cursor}: backed_cursor: _select_: { id: integer notnull, name: text<cool_text> notnull } variable dml_proc
-- + {cte_table}: simple_backed_table: { rowid: longint notnull, id: integer notnull, name: text<cool_text> notnull }
cursor backed_cursor for select * from simple_backed_table;

-- TEST: inserting using simple_backed should work even if it isn't the target
-- verify rewrite only
-- + simple_backed_table (rowid, id, name) AS (CALL _simple_backed_table())
-- + {with_insert_stmt}: ok
-- - error:
insert into dummy_table_for_backed_test select id from simple_backed_table;

-- TEST: deleting using simple_backed should work even if it isn't the target
-- verify successful rewrite only
-- + simple_backed_table (rowid, id, name) AS (CALL _simple_backed_table())
-- + {with_delete_stmt}: ok
-- - error:
delete from dummy_table_for_backed_test where id in (select id from simple_backed_table);

-- TEST: updatingg using simple_backed should work even if it isn't the target
-- verify successful rewrite only
-- + simple_backed_table (rowid, id, name) AS (CALL _simple_backed_table())
-- + {with_update_stmt}: dummy_table_for_backed_test: { id: integer }
-- - error:
update dummy_table_for_backed_test set id = id + 1 where id in (select id from simple_backed_table);

create table update_from_target(
  id integer primary key,
  name text
);

create table update_test_1(
  id integer primary key,
  name text
);

create table update_test_2(
  id integer primary key,
  name text
);

-- TEST: update with from clause
-- + {update_stmt}: update_from_target: { id: integer notnull primary_key, name: text }
-- - error:
update update_from_target
set name = update_test_2.name from update_test_1
  inner join update_test_2 on update_test_1.id = update_test_2.id
  where update_test_1.name = 'x' and update_from_target.id = update_test_1.id;

-- TEST: update with from clause
-- + error: % table/view not defined 'table_does_not_exist'
-- + {update_stmt}: err
-- +1 error:
update update_from_target set name = update_test_2.name from table_does_not_exist;

-- TEST: update backed table with from clause -- not supported
-- + error: % FROM clause not supported when updating backed table 'simple_backed_table'
-- + {update_stmt}: err
-- +1 error:
update simple_backed_table set id = 5 from update_test_1;

@ENFORCE_STRICT UPDATE FROM;

-- TEST: update with from clause
-- + error: % strict UPDATE ... FROM validation requires that the UPDATE statement not include a FROM clause
-- + {update_stmt}: err
-- +1 error:
UPDATE update_from_target SET name = update_test_2.name FROM update_test_1;

@ENFORCE_NORMAL UPDATE FROM;

-- TEST: update with from shape sugar
-- Validate first update statement codegen
-- + {update_set}
-- + {update_list}: ok
-- + {update_entry}: id: integer notnull
-- + {name id}: id: integer notnull
-- + {dot}: id_: integer notnull variable in
-- + {name ARGUMENTS}
-- + {name id}
-- + {update_list}
-- + {update_entry}: name: text
-- + {name name}: name: text
-- + {dot}: name_: text variable in
-- + {name ARGUMENTS}
-- + {name name}
-- Validate second update statement codegen
-- + {update_set}
-- + {update_list}: ok
-- + {update_entry}: id: integer notnull
-- + {name id}: id: integer notnull
-- + {dot}: C.id: integer notnull variable primary_key
-- + {name C}
-- + {name id}
-- + {update_list}
-- + {update_entry}: name: text
-- + {name name}: name: text
-- + {dot}: C.name: text variable
-- + {name C}
-- + {name name}
-- - error:
proc test_update_from_shape(like update_test_1)
begin
  -- Update statement from arguments
  update update_test_1
  set (like update_test_1) = (from arguments)
  where id = locals.id
  order by update_test_1.id
  limit 1;

  -- Update statement from a cursor
  cursor C like update_test_1;
  fetch C from values (1, "foo");
  update update_test_1
  set (like update_test_1) = (from C)
  where id = locals.id
  order by update_test_1.id
  limit 1;
end;

-- Test table for next test.
create table update_stmt_table(
  id integer primary key,
  name text,
  a text,
  b text,
  c text,
  x integer,
  y integer,
  z integer
);

-- TEST: update from an insert list
-- + {update_list}: ok
-- + {update_entry}: name: text
-- + {name name}: name: text
-- + {dot}: name_: text variable in
-- + {name locals}
-- + {name name}
-- + {update_list}
-- + {update_entry}: a: text
-- + {name a}: a: text
-- + {dot}: cur.a: text variable
-- + {name cur}
-- + {name a}
-- + {update_list}
-- + {update_entry}: b: text
-- + {name b}: b: text
-- + {dot}: cur.b: text variable
-- + {name cur}
-- + {name b}
-- + {update_list}
-- + {update_entry}: c: text
-- + {name c}: c: text
-- + {dot}: cur.c: text variable
-- + {name cur}
-- + {name c}
-- + {update_list}
-- + {update_entry}: x: integer
-- + {name x}: x: integer
-- + {int 1}: integer notnull
-- + {update_list}
-- + {update_entry}: y: integer
-- + {name y}: y: integer
-- + {int 2}: integer notnull
-- + {update_list}
-- + {update_entry}: z: integer
-- + {name z}: z: integer
-- + {int 3}: integer notnull
-- - error:
proc test_update_from_insert_list(like update_stmt_table(id, name))
begin
  cursor cur like update_stmt_table(a, b, c);
  fetch cur from values ("a", "b", "c");

  update update_stmt_table
    set (like update_stmt_table(-id)) = (locals.name, from cur, 1, 2, 3)
    where id = locals.id
    order by update_stmt_table.id
    limit 1;
end;

-- Test table for next test.
create table aux_table(
  id integer primary key,
  x integer,
  y integer,
  z integer
);

-- TEST: Update with a shape and a FROM clause
-- + {update_list}: ok
-- + {update_entry}: name: text
-- + {name name}: name: text
-- + {dot}: updates_name: text variable in
-- + {name updates}
-- + {name name}
-- + {update_list}
-- + {update_entry}: a: text
-- + {name a}: a: text
-- + {dot}: updates_a: text variable in
-- + {name updates}
-- + {name a}
-- + {update_list}
-- + {update_entry}: b: text
-- + {name b}: b: text
-- + {dot}: updates_b: text variable in
-- + {name updates}
-- + {name b}
-- + {update_list}
-- + {update_entry}: c: text
-- + {name c}: c: text
-- + {dot}: updates_c: text variable in
-- + {name updates}
-- + {name c}
-- + {update_list}
-- + {update_entry}: x: integer
-- + {name x}: x: integer
-- + {dot}: x: integer
-- + {name aux_table}
-- + {name x}
-- + {update_list}
-- + {update_entry}: y: integer
-- + {name y}: y: integer
-- + {dot}: y: integer
-- + {name aux_table}
-- + {name y}
-- + {update_list}
-- + {update_entry}: z: integer
-- + {name z}: z: integer
-- + {dot}: z: integer
-- + {name aux_table}
-- + {name z}
-- - error:
proc test_update_with_shape_and_from_clause(id integer, updates like update_stmt_table(name, a, b, c))
begin
  update update_stmt_table
  set (like update_stmt_table(-id)) = (from updates, aux_table.x, aux_table.y, aux_table.z)
  from aux_table
  where aux_table.id = update_stmt_table.id and update_stmt_table.id = locals.id;
end;

-- TEST: update from_shape sugar error handling, type mismatch
-- + error: % required 'TEXT' not compatible with found 'INT' context 'name'
-- + error: % additional info: in update table 'update_test_1' the column with the problem is 'name'
-- + {update_stmt}: err
-- + {update_list}: err
-- + {update_entry}: err
-- + {dot}: err
-- + {name ARGUMENTS}
-- + {name id}
-- +2 error:
proc test_update_from_shape_errors0(like update_test_1)
begin
  -- Swapped ordering of columns lead to incompatible types.
  update update_test_1
  set (name, id) = (from arguments);
end;

-- TEST: update from_shape sugar error handling, FROM invalid
-- + error: % name not found 'cursor_not_exist'
-- + {update_stmt}: err
-- + {insert_list}: err
-- + {name cursor_not_exist}: err
-- +1 error:
proc test_update_from_shape_errors1(like update_test_1)
begin
  -- Use of non existent shape in values
  update update_test_1 set (id, name) = (from cursor_not_exist);
end;

-- TEST: update from_shape sugar error handling invalid like shape
-- + error: % must be a cursor, proc, table, or view 'cursor_not_exist'
-- + {update_stmt}: err
-- + {columns_values}: err
-- + {shape_def}: err
-- + {name cursor_not_exist}: err
-- +1 error:
proc test_update_from_shape_errors2(like update_test_1)
begin
  -- Use of non existent shape in column spec
  update update_test_1 set (like cursor_not_exist) = (from arguments);
end;

-- TEST: update from_shape sugar error handling, missing count
-- + SET (id, name) = (ARGUMENTS.id);
-- + error: % count of columns differs from count of values
-- + {update_stmt}: err
-- +1 error:
proc test_update_from_shape_errors3(id int!)
begin
   -- Count of columns differ from count of values
  update update_test_1 set (id, name) = (from arguments);
end;

-- TEST: cql:alias_of attribution on declare_func_stmt
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name alias_of}
-- + {name some_native_func}: ok
-- + {declare_func_stmt}: integer notnull
-- - error:
[[alias_of=some_native_func]]
func an_alias_func(x int!) int!;

-- TEST: cql:alias_of attribution on declare proc stmt
-- + {stmt_and_attr}: ok
-- + {misc_attrs}: ok
-- + {name cql}
-- + {name alias_of}
-- + {name some_native_func}: ok
-- + {declare_proc_stmt}: ok
-- - error:
[[alias_of=some_native_func]]
declare proc an_alias_proc(x int!);

-- TEST: cql:alias_of attribution on invalid statement
-- + error: % alias_of attribute may only be added to a declare function or declare proc statement
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {declare_select_func_stmt}: err
-- +1 error:
[[alias_of=barfoo]]
declare select function foobaz(x int!) int!;

-- TEST: cql:alias_of attribution invalid value
-- + error: % alias_of attribute must be a non-empty string argument
-- + {stmt_and_attr}: err
-- + {misc_attrs}: err
-- + {declare_func_stmt}: err
-- +1 error:
[[alias_of]]
func an_alias_func_bad(x int!) int!;

-- setup for invalid child test, private proc
-- this ok so far
[[private]]
proc invalid_child_proc()
begin
   select 1 x, 2 y;
end;

-- setup for invalid child test, suppressed result set
-- this ok so far
[[suppress_result_set]]
proc invalid_child_proc_2()
begin
   select 1 x, 2 y;
end;

-- TEST: cannot use the above proc as a result set because it's private
-- + error: % object<T SET> has a T that is not a public procedure with a result set 'invalid_child_proc SET'
-- +1 error:
proc use_invalid_result_set()
begin
  declare x object<invalid_child_proc set>;
end;

-- TEST: cannot use the above proc as a result set because it's private
-- + error: % object<T SET> has a T that is not a public procedure with a result set 'invalid_child_proc_2 SET'
-- +1 error:
proc use_invalid_result_set2()
begin
  declare x object<invalid_child_proc_2 set>;
end;

func rev_apply_bool(x bool) int!;
func rev_apply_int(x int) int!;
func rev_apply_long(x long) int!;
func rev_apply_real(x real) int!;
func rev_apply_text(x text) int!;
func rev_apply_blob(x blob) int!;
func rev_apply_object(x object) int!;
-- function rev_apply_cursor(x cursor) int!;

@op bool : call rev_apply as rev_apply_bool;
@op int : call rev_apply as rev_apply_int;
@op long : call rev_apply as rev_apply_long;
@op real : call rev_apply as rev_apply_real;
@op text : call rev_apply as rev_apply_text;
@op blob : call rev_apply as rev_apply_blob;
@op object : call rev_apply as rev_apply_object;

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_bool(true);
-- - error:
set int_result := true:rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_int(5);
-- - error:
set int_result := 5:rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_long(5L);
-- - error:
set int_result := 5L:rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_real(3.5);
-- - error:
set int_result := 3.5:rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_text("foo");
-- - error:
set int_result := "foo":rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_blob(blob_var);
-- - error:
set int_result := blob_var:rev_apply();

-- TEST: use the reverse apply with : to get polymorphism
-- validate rewrite only
-- + SET int_result := rev_apply_object(obj_var);
-- - error:
set int_result := obj_var:rev_apply();

-- make the cursor valid to use (this never runs so it's fine)
fetch my_cursor;

-- -- TEST: use the reverse apply with : to get polymorphism
-- -- validate rewrite only
-- -- + SET int_result := rev_apply_cursor(my_cursor);
-- -- - error:
-- set int_result := my_cursor:rev_apply();

-- TEST: path of invalid identifier has a slightly different error route
-- + error: % name not found 'invalid_id_bogus'
-- + {assign}: err
-- + {name invalid_id_bogus}: err
-- ONE error not TWO!
-- +1 error:
set int_result := invalid_id_bogus:rev_apply();

declare lbs real<pounds> not null;

func some_polymorphic_function_real_pounds(x real<pounds>, y real) int!;
@op real<pounds> : call myfunc as some_polymorphic_function_real_pounds;

-- TEST: using the type kind we append "real_pounds" not just "real"
-- + LET poly_result_1 := some_polymorphic_function_real_pounds(lbs, 1);
let poly_result_1 := lbs:myfunc(1);

proc get_result()
begin
   select 1 x, 2 y;
end;

-- note that we have to lose the type kind object<get_result SET>
-- we don't have any way to flow it into a declaration.
-- so we have to use a generic object to capture the argument.
-- this is of dubious usefulness.  But again these internal types
-- are not intended to be used in this way anyway.
func get_result_set_count(result object) int!;
@op object<get_result SET> : call count as get_result_set_count;

-- TEST: this is a not very clever use of : but it showcases space issue
-- note that we added an underscore so we get _SET
-- + LET poly_result_2 := get_result_set_count(get_result());
-- - error:
let poly_result_2 := get_result():count();

-- some things we will use in the tests
func expr_func_a(x integer) integer;
declare procedure expr_proc_b(x integer);

-- TEST: top level function calls are ok, any expression is ok
-- result is discarded
-- + expr_func_a(1);
-- + {expr_stmt}: integer
-- + {call}: integer
-- + {name expr_func_a}
-- - error:
expr_func_a(1);

-- TEST: we should be able to call a proc at the top level (with rewrites)
-- verify the rewrite
-- + CALL expr_proc_b(1);
-- + {call_stmt}: ok
-- - error:
expr_proc_b(1);


-- TEST: the * notation needs additional rewrites to convert from ast_star
-- verify the correct rewrite
-- + CALL expr_proc_b(LOCALS.x);
-- + call_stmt}: ok
-- - ast_star
-- - error:
proc local_expando_rewrite()
begin
  let x := 1;
  expr_proc_b(*);
end;

-- TEST: one error, not two, even though rewrite attemnt
-- rewrite did not succeed
-- + not_found_variable:foo();
-- + error: % name not found 'not_found_variable'
-- + {expr_stmt}: err
-- + {reverse_apply}
-- exactly one error
-- +1 error:
not_found_variable:foo();

-- TEST: top level rewrite with various : operators
-- reverse apply has to go first
-- + CALL expr_proc_b(expr_func_a(expr_func_a(1)));
-- + {call_stmt}: ok
-- - error:
1:expr_func_a():expr_func_a():expr_proc_b();

-- TEST: helper proc for the real test
-- + call printf(" %d", x);
-- - error:
proc dump_int(x integer, out result integer)
begin
  set result := x;
  printf(" %d", x);
end;

@op int : call dump as dump_int;

-- TEST: this dump call is NOT rewritten to a proc call
-- it can't be because it uses the proc as func pattern
-- + dump_int(1);
-- + CALL dump_int(LOCALS.x, LOCALS.result);
-- - error:
proc main()
begin
  let x := 2;
  declare result integer;
  1:dump();
  dump_int(*);
end;

-- TEST: try to expand a top level proc using a bogus FROM
-- + dump_int(FROM this_name_does_not_exist);
-- + error: % name not found 'this_name_does_not_exist'
-- +1 error
dump_int(from this_name_does_not_exist);

-- TEST: rewrite top level := into a SET
-- + SET int_result := 701;
-- + {assign}: int_result: integer variable was_set
-- - error:
int_result := 701;

-- TEST: try to do an assignment that isn't an identifier
-- + error: % left operand of assignment operator must be a name ':='
-- +1 error:
1 := 7;

-- TEST: use := in a place other than the simplest
-- + error: % operator found in an invalid position ':='
-- + {expr_assign}: err
-- +1 error:
int_result := int_result := 2;

let op_assign := 5;

-- TEST: rewrite +=
-- + SET op_assign := op_assign + 7;
-- - error:
op_assign += 7;

-- TEST: rewrite -=
-- + SET op_assign := op_assign - 3;
-- - error:
op_assign -= 3;

-- TEST: rewrite *=
-- + SET op_assign := op_assign * 100;
-- - error:
op_assign *= 100;

-- TEST: rewrite /=
-- + SET op_assign := op_assign / 10;
-- - error:
op_assign /= 10;

-- TEST: rewrite %=
-- + SET op_assign := op_assign % 8;
-- - error:
op_assign %= 8;

-- TEST: rewrite %=
-- + SET op_assign := op_assign & 7;
-- - error:
op_assign &= 7;

-- TEST: rewrite %=
-- + SET op_assign := op_assign | 22;
-- - error:
op_assign |= 22;

-- TEST: rewrite %=
-- + SET op_assign := op_assign << 8;
-- - error:
op_assign <<= 8;

-- TEST: rewrite %=
-- + SET op_assign := op_assign >> 11;
-- - error:
op_assign >>= 11;

-- TEST: += (they are the same) on not an identifier
-- + error: % left operand of assignment operator must be a name ':='
-- + {expr_stmt}: err
-- + {expr_assign}: err
-- +1 error:
1 += 7;

func get_from_object_foo(array object<foo>, index text) text not null;
func set_in_object_foo( array object<foo>, index text, value text) text not null;

@op object<foo> : array get as get_from_object_foo;
@op object<foo> : array set as set_in_object_foo;

-- TEST: emulate array behavior with function rewrites
-- we just have to verify the rewrites
-- + LET z := get_from_object_foo(x, 'index');
-- + set_in_object_foo(x, 'index1', 'value');
-- + set_in_object_foo(x, 'index2', get_from_object_foo(x, 'value2'));
-- we do it with the SET form and the expression statement form even though
-- they map to the same thing
proc array_test()
begin
  declare x object<foo>;
  let z := x['index'];
  x['index1'] := 'value';
  SET x['index2'] := x['value2'];
end;

-- TEST: left of array does not have a type kind
-- it has to have an object kind
-- + error: % operation is only available for types with a declared type kind like object<something> '[]'
-- + {expr_stmt}: err
-- + {array}: err
-- +1 error
1['x'];

-- TEST: left of array does not have a type kind (in set context)
-- it has to have an object kind
-- + error: % operation is only available for types with a declared type kind like object<something> '[]'
-- + {expr_stmt}: err
-- + {array}: err
-- +1 error
1['x'] := 'x';

-- TEST: left of array has a semantic error
-- it has to have an object kind
-- + error: % string operand not allowed in 'NOT'
-- + {expr_stmt}: err
-- + {array}: err
-- +1 error
(not 'x')[5];

func get_object_dot_one_id(x object<dot_one>) integer;
func get_from_object_dot_two no check integer;

@op object<dot_one> : get id as get_object_dot_one_id;
@op object<dot_two> : get all as get_from_object_dot_two;

-- TEST: rewrite dot operations (not set case)
-- +  LET z := get_object_dot_one_id(q);
-- +  SET z := get_from_object_dot_two(u, 'id');
-- +  SET z := get_from_object_dot_two(u, 'id2');
-- - error:
proc dot_test()
begin
  declare q object<dot_one>;
  declare u object<dot_two>;

  let z := q.id;
  set z := u.id;
  set z := u.id2;
end;

-- TEST: try to use a . op but no helper functions
-- + error: % name not found 'q.id'
-- + {dot}: err
-- +1 error:
proc dot_fail_no_funcs()
begin
  declare q object<dot_three>;

  let z := q.id;
end;

-- TEST: try to use a . op but no helper functions
-- + error: % name not found 'q.id'
-- + {dot}: err
-- +1 error:
proc dot_fail_no_kind()
begin
  declare q object;

  let z := q.id;
end;

func make_dot_one() create object<dot_one>;
@op object<dot_one> : get id as get_object_dot_one_id;

-- TEST: try to use a . op but no helper functions (computed version)
-- one successful rewrite
-- + LET u := get_object_dot_one_id(make_dot_one());
-- + error: % function not builtin and not declared 'object<dot_one>:get:id2'
-- + {call}: err
-- +1 error:
proc dot_fail_no_missing_helper_computed()
begin
  declare q object;

  let u := make_dot_one().id;
  let v := make_dot_one().id2;
end;

-- TEST: bogus attempt -- no kind
-- + error: % operation is only available for types with a declared type kind like object<something> '.'
-- + {expr_stmt}: err
-- + {dot}: err
-- +1 error
(1+1).foo;

-- TEST: bogus attempt -- error expression
-- + error: % string operand not allowed in 'NOT'
-- + {expr_stmt}: err
-- + {dot}: err
-- +1 error
(not 'x').foo;

-- both options for getting/setting tested here
declare proc set_in_object_dot_storage no check;
declare proc set_object_dot_storage_id(self object<dot_storage>, value int);
func get_object_dot_storage_id(self object<dot_storage>) integer;
func get_from_object_dot_storage no check integer;

declare storage object<dot_storage>;
@op object<dot_storage> : array get as get_from_object_dot_storage;
@op object<dot_storage> : array set as set_in_object_dot_storage;
@op object<dot_storage> : get id as get_object_dot_storage_id;
@op object<dot_storage> : get all as get_from_object_dot_storage;
@op object<dot_storage> : set all as set_in_object_dot_storage;

-- TEST: array case (control for set case)
-- + CALL set_in_object_dot_storage(storage, 'id2', get_from_object_dot_storage(storage, 'id') + get_from_object_dot_storage(storage, 'id2'));
-- - error:
storage.id2 := storage['id'] + storage['id2'];

-- TEST: set operator
-- rewrite only!
-- + CALL set_in_object_dot_storage(storage, 'id2', get_object_dot_storage_id(storage) + get_from_object_dot_storage(storage, 'id2'));
-- - error:
storage.id2 := storage.id + storage.id2;

-- TEST: exotic expressions
-- complex rewrite with all node types
-- + CALL set_in_object_dot_storage(storage, ( SELECT 'id'
-- - error:
storage[(select 'id' union all select 'id' limit 1)] += 1;

-- TEST: friends don't let friends put = at the top level
-- + error: % a top level equality is almost certainly an error. ':=' is assignment, not '='
-- + {expr_stmt}: err
-- +1 error:
x = 5;

declare proc a_target_proc(x integer, y integer);

-- TEST: catch cases where * is in a bad place in the arg list
-- + error: % argument can only be used in count(*) '*'
-- + error: % additional info: calling 'a_target_proc' argument #2 intended for parameter 'y' has the problem
-- +2 error:
proc abuse_star1(like a_target_proc arguments)
begin
  a_target_proc(1, *, 1);
end;

-- TEST: catch cases where * is in a bad place in the arg list
-- + error: % when '*' appears in an expression list there can be nothing else in the list
-- +1 error:
proc abuse_star2(like a_target_proc arguments)
begin
  call a_target_proc(*, 1);
end;


declare proc another_target_proc(x integer, y integer, out result integer);

-- TEST: catch cases where * is in a bad place in the arg list
-- + error: % when '*' appears in an expression list there can be nothing else in the list
-- +1 error:
proc abuse_star3(like a_target_proc arguments)
begin
  another_target_proc(*, 1);
end;

func create_event() create object<event> not null;
declare proc get_object_event_invitees(event_ object<event>, out value object<event_invitees> not null);
declare proc event_invitees_get(invitees object<event_invitees>, field text not null, out value text not null);

@op object<event> : get invitees as get_object_event_invitees;
@op object<event_invitees> : get all as event_invitees_get;

-- TEST: when calling proc as func the kind of the out parameter should be preserved
-- it didn't used to be which caused the get chain below to break
-- + {let_stmt}: event: object<event> notnull variable
-- + {let_stmt}: x: object<event_invitees> notnull variable
-- + {let_stmt}: y: text notnull variable
-- + {call}: object<event_invitees> notnull
-- - {call}: object notnull
-- - error:
proc proc_as_func_preserves_kind()
BEGIN
  let event := create_event();
  let x := event.invitees;
  let y := event.invitees.firstName;
END;

-- we make a table and a shape
create table larger_table (a int, b int, c int, d int);
interface smaller_interface(a int, b int);

-- TEST: rewrite with specified like columns
-- this is pulling out the smaller interface but not a, so just b.
-- this is interesting because it's a nested rewrite
-- + SELECT larger_table.b
-- - larger_table.a
-- - larger_table.c
-- - larger_table.d
select @columns(larger_table like smaller_interface(-a)) from larger_table;

-- TEST: rewrite with specified like columns
-- this is pulling out the smaller interface but not a, so just b.
-- this is interesting because it's a nested rewrite
-- + SELECT larger_table.a
-- - larger_table.b
-- - larger_table.c
-- - larger_table.d
select @columns(larger_table like smaller_interface(a)) from larger_table;

-- TEST: rewrite with specified like columns
-- this is pulling out the smaller interface but not a, so just b.
-- this is interesting because it's a nested rewrite
-- + SELECT larger_table.a, larger_table.b
-- - larger_table.c
-- - larger_table.d
select @columns(larger_table like smaller_interface) from larger_table;

-- TEST: valid duplicate type
-- + {declare_named_type}: integer notnull
-- -error:
type an_integer_type integer!;

-- TEST: valid duplicate type
-- + {declare_named_type}: integer notnull
-- note that even though ! syntax was used for the former the AST is the same
-- so there is no error here
-- -error:
type an_integer_type int!;

-- TEST: select functions cannot have out arguments -- inout form
-- + error: % select functions cannot have out parameters 'inout_param'
-- + {declare_select_func_stmt}: err
-- +1 error:
declare select func select_func_with_out_arg1(inout inout_param int!) int;

-- TEST: select functions cannot have out arguments -- out form
-- + error: % select functions cannot have out parameters 'out_param'
-- + {declare_select_func_stmt}: err
-- +1 error:
declare select func select_func_with_out_arg2(out out_param int!) int;

-- TEST: create a table with a weird name and a weird column
-- verify that echoing is re-emitting the escaped text
-- + CREATE TABLE `xyz``abc`(
-- + x INT!,
-- + `a b` INT!
-- + {create_table_stmt}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- + {name `xyz``abc`}
-- + {col_def}: x: integer notnull
-- + {col_def}: `a b`: integer notnull unique_key qid
-- + {name `a b`}
-- - error:
create table `xyz``abc`
(
 x int!,
 `a b` int! unique
);

-- TEST: make a cursor on an exotic name and fetch from it
-- verify that echoing is re-emitting the escaped text
-- + CURSOR C FOR
-- +   SELECT `xyz``abc`.x, `xyz``abc`.`a b`
-- + FROM `xyz``abc`;
-- + CALL printf("%d %d", C.x, C.`a b`);
-- + {declare_cursor}: C: _select_: { x: integer notnull, `a b`: integer notnull qid } variable dml_proc
-- + {fetch_stmt}: C: _select_: { x: integer notnull, `a b`: integer notnull qid } variable dml_proc shape_storage
-- + {dot}: C.x: integer notnull variable
-- + {dot}: C.X_aX20b: integer notnull variable qid
-- - error:
proc qid_t1()
begin
  cursor C for select * from `xyz``abc`;
  loop fetch C
  begin
    call printf("%d %d", C.x, C.`a b`);
  end;
end;

-- TEST: Test several expansions
-- verify that echoing is re-emitting the escaped text
-- + CURSOR D FOR
-- +   SELECT `xyz``abc`.x, `xyz``abc`.`a b`
-- + FROM `xyz``abc`;
-- + CALL printf("%d %d", D.x, D.`a b`);
-- + {declare_cursor}: D: _select_: { x: integer notnull, `a b`: integer notnull qid } variable dml_proc
-- + {select_stmt}: _select_: { x: integer notnull, `a b`: integer notnull qid }
-- - error:
proc qid_t2()
begin
  cursor D for select `xyz``abc`.* from `xyz``abc`;
  loop fetch D
  begin
    call printf("%d %d", D.x, D.`a b`);
  end;
end;

-- TEST: Test select expression with specified exact columns
-- verify that echoing is re-emitting the escaped text
-- + LET x := ( SELECT `xyz``abc`.`a b`
-- + FROM `xyz``abc` );
-- + {let_stmt}: x: integer notnull variable
-- + {select_stmt}: `a b`: integer notnull qid
-- + {dot}: `a b`: integer notnull qid
-- + {name `xyz``abc`}
-- + {name `a b`}
-- + {select_from_etc}: TABLE { `xyz``abc`: `xyz``abc` }
-- - error:
proc qid_t3()
begin
  let x := (select `xyz``abc`.`a b` from `xyz``abc`);
end;

-- TEST: cursor forms with exotic columns
-- verify that echoing is re-emitting the escaped text
-- + CURSOR Q LIKE `xyz``abc`(-`a b`);
-- + CURSOR R LIKE `xyz``abc`;
-- + FETCH R(x, `a b`) FROM VALUES (1, 2);
-- + CALL printf("%d %d\n", R.x, R.`a b`);
-- + FETCH R(x, `a b`) FROM VALUES (3, 4);
-- + {declare_cursor_like_name}: Q: _select_: { x: integer notnull } variable shape_storage value_cursor
-- + {declare_cursor_like_name}: R: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } variable shape_storage value_cursor
proc qid_t4()
begin
  cursor Q like `xyz``abc`(-`a b`);
  cursor R like `xyz``abc`;
  fetch R from values (1, 2);
  printf("%d %d\n", R.x, R.`a b`);
  fetch R using  3 x, 4 `a b`;
end;

-- TEST: error message specifies unencoded name
-- + error: % name not found '`a b`'
-- +1 error:
let error_test_for_qid := `a b`;

-- TEST: make a view, use the form that doesn't require escaping
-- verify that echoing is re-emitting the escaped text
-- + CREATE VIEW `view` AS
-- + SELECT 1 AS x;
-- + {create_view_stmt}: view: { x: integer notnull }
-- +  {name `view`}
create view `view` as select 1 x;

-- TEST: create an index with unusual names
-- verify that echoing is re-emitting the escaped text
-- + CREATE INDEX `abc def` ON `xyz``abc` (`a b` ASC);
-- + {name `abc def`}
-- + {name `xyz``abc`}
-- + {name `a b`}: `a b`: integer notnull qid
-- - error:
create index `abc def` on `xyz``abc` (`a b` asc);

-- TEST: use a reference attribute with quoted names
-- verify that echoing is re-emitting the escaped text
-- + x INT! REFERENCES `xyz``abc` (`a b`)
-- + {create_table_stmt}: qid_ref_1: { x: integer notnull foreign_key }
-- + {name `a b`}: `a b`: integer notnull qid
-- - error:
create table qid_ref_1 (
  x int! references `xyz``abc`(`a b`)
);

-- TEST: use a reference attribute with quoted names
-- verify that echoing is re-emitting the escaped text
-- + CONSTRAINT `c1` FOREIGN KEY (`uu uu`) REFERENCES `xyz``abc` (`a b`)
-- +  {name `c1`}
-- + {name `uu uu`}: `uu uu`: integer notnull qid
-- + {name `a b`}: `a b`: integer notnull qid
-- - error:
create table qid_ref_2 (
  `uu uu` int!,
  constraint `c1` foreign key ( `uu uu` ) references `xyz``abc`(`a b`)
);

-- TEST: use a primary key attribute with quoted names
-- verify that echoing is re-emitting the escaped text
-- + CONSTRAINT `c1` PRIMARY KEY (`uu uu`)
-- + {create_table_stmt}: qid_ref_3: { `uu uu`: integer notnull partial_pk qid }
-- + {name `c1`}
-- + {name `uu uu`}: `uu uu`: integer notnull qid
-- - error:
create table qid_ref_3 (
  `uu uu` int!,
  constraint `c1` primary key ( `uu uu` )
);

-- TEST: use a primary key attribute with quoted names
-- verify that echoing is re-emitting the escaped text
-- + CONSTRAINT `c1` UNIQUE (`uu uu`)
-- + {create_table_stmt}: qid_ref_4: { `uu uu`: integer notnull qid }
-- + {name `c1`}
-- + {name `uu uu`}: `uu uu`: integer notnull qid
-- - error:
create table qid_ref_4 (
  `uu uu` int!,
  constraint `c1` unique ( `uu uu` )
);

-- TEST: an update statement with quoted strings
-- verify that echoing is re-emitting the escaped text
-- + UPDATE `xyz``abc`
-- + SET `a b` = 5;
-- + {update_stmt}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- + {name `a b`}: `a b`: integer notnull qid
-- - error:
update `xyz``abc` set `a b` = 5;

-- TEST: insert statement vanilla with quoted names
-- verify that echoing is re-emitting the escaped text
-- + INSERT INTO `xyz``abc`(x, `a b`)
-- +   VALUES (1, 5);
-- + {name `xyz``abc`}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- - error:
insert into `xyz``abc` values (1, 5);

-- TEST: insert statement using syntaxwith quoted names
-- verify that echoing is re-emitting the escaped text
-- + INSERT INTO `xyz``abc`(`a b`, x) VALUES (1, 2);
-- + {name `xyz``abc`}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- - error:
insert into `xyz``abc` using 1 `a b`, 2 x;

-- TEST: insert statement dummy seed using form
-- verify that echoing is re-emitting the escaped text
-- + INSERT INTO `xyz``abc`(x, `a b`) VALUES (2, _seed_) @DUMMY_SEED(500);
-- + {name `xyz``abc`}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- - error:
insert into `xyz``abc` using 2 x @dummy_seed(500);

-- TEST: insert statement dummy seed values form
-- verify that echoing is re-emitting the escaped text
-- + INSERT INTO `xyz``abc`(x, `a b`) VALUES (2, _seed_) @DUMMY_SEED(500);
-- + {name `xyz``abc`}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- - error:
insert into `xyz``abc`(x) values (2) @dummy_seed(500);

-- TEST: create a cursor and expand it using the from form
-- verify that echoing is re-emitting the escaped text
-- + CURSOR C FOR
-- +   SELECT `xyz``abc`.x, `xyz``abc`.`a b`
-- + FROM `xyz``abc`;
-- + INSERT INTO `xyz``abc`(x, `a b`)
-- +   VALUES (C.x, C.`a b`);
-- + {name `xyz``abc`}: `xyz``abc`: { x: integer notnull, `a b`: integer notnull unique_key qid } qid
-- + {name `a b`}
-- - error:
proc quoted_from_forms()
begin
  cursor C for select * from `xyz``abc`;
  fetch C;
  insert into `xyz``abc`(like `xyz``abc`) values (from C);
end;

-- TEST: drop a table with quoted named
-- the echo is all that matters
-- + DROP TABLE `xyz``abc`;
drop table `xyz``abc`;

-- TEST: drop an index
-- the echo is all that matters
-- + DROP INDEX `abc`;
drop index `abc`;

-- TEST: drop a trigger
-- the echo is all that matters
-- + DROP TRIGGER `abc def`;
drop trigger `abc def`;

-- TEST: drop a view
-- the echo is all that matters
-- + DROP VIEW `vvv v`;
drop view `vvv v`;

-- TEST: alter table
-- the echo is all that matters
-- + ALTER TABLE `xyz``abc` ADD COLUMN `a b` INT;
alter table `xyz``abc` add column `a b` int;

-- TEST: this construct forces exotic names into the reality of locals
-- verify that echoing is re-emitting the escaped text
-- + PROC args_defined_by_exotics (x_ INT!, `a b_` INT!)
-- + SET `a b_` := 1;
-- + SET `a b_` := `a b_` + 1;
-- + LET `u v` := 5;
-- + SET `u v` := 6;
-- + {param}: `a b_`: integer notnull variable in was_set
-- + {assign}: `a b_`: integer notnull variable in was_set
-- + {name `a b_`}: `a b_`: integer notnull variable in was_set
-- + {add}: integer notnull
-- + {name `a b_`}: `a b_`: integer notnull variable in was_set
-- + {let_stmt}: `u v`: integer notnull variable was_set
-- + {name `u v`}: `u v`: integer notnull variable was_set
-- + {assign}: `u v`: integer notnull variable was_set
-- - error:
proc args_defined_by_exotics(like `xyz``abc`)
begin
  `a b_` := 1;
  `a b_` += 1;
  LET `u v` := 5;
  SET `u v` := 6;
end;

-- TEST: boxed cursor constructs and unusual box object
-- verify that echoing is re-emitting the escaped text
-- + CURSOR C FOR
-- +  SELECT 1 AS x;
-- + DECLARE `box obj` OBJECT<C CURSOR>;
-- + SET `box obj` FROM CURSOR C;
-- + {name `box obj`}: `box obj`: object<C CURSOR> variable
-- + {set_from_cursor}: C: _select_: { x: integer notnull } variable dml_proc boxed
-- - error:
proc cursor_boxing_with_qid()
begin
  cursor C for select 1 x;
  declare `box obj` object<C cursor>;
  set `box obj` from cursor C;
end;

-- TEST: create a new table using a nested shape with quoted names
-- verify that echoing is re-emitting the escaped text
-- + CREATE TABLE reuse_exotic_columns(
-- + x INT!,
-- + `a b` INT!
-- + {create_table_stmt}: reuse_exotic_columns: { x: integer notnull, `a b`: integer notnull qid }
-- - error:
create table reuse_exotic_columns (
  LIKE `xyz``abc`
);

-- TEST: shape name expansion with quid in the columns
-- verifying the echo is correct (this is actually sufficient)
-- + PROC qid_shape_args (AAA_x INT!, `AAA_a b` INT!, BBB_x INT!, `BBB_a b` INT!, x_ INT!, `a b_` INT!)
-- + {create_proc_stmt}: ok
-- + {name AAA_x}: AAA_x: integer notnull variable in
-- + {name `AAA_a b`}: `AAA_a b`: integer notnull variable in
-- + {name BBB_x}: BBB_x: integer notnull variable in
-- + {name `BBB_a b`}: `BBB_a b`: integer notnull variable in
-- + {name x_}: x_: integer notnull variable in
-- + {name `a b_`}: `a b_`: integer notnull variable in
-- - error:
proc qid_shape_args(AAA like `xyz``abc`, BBB like `xyz``abc`, like `xyz``abc`)
begin
end;

create table qnamed_table(
 `x y` int,
 `a b` int
);

-- TEST: verifies that the QID goes all the way up to the proc result shape
-- this is necessary so that the generated DECLARE PROC will be correct
-- + {create_proc_stmt}: presult_1: { `x y`: integer qid, `a b`: integer qid } dml_proc
-- - error:
proc presult_1()
begin
  select T2.* from qnamed_table T1 join qnamed_table T2;
end;

-- TEST: verifies that the QID goes all the way up to the proc result shape
-- this is necessary so that the generated DECLARE PROC will be correct
-- + {create_proc_stmt}: presult_2: { `x y`: integer qid } dml_proc
-- - error:
proc presult_2()
begin
  select T1.`x y` from qnamed_table T1 join qnamed_table T2;
end;

-- TEST: verifies that the QID goes all the way up to the proc result shape
-- this is necessary so that the generated DECLARE PROC will be correct
-- + {create_proc_stmt}: presult_3: { `x y`: integer notnull qid } dml_proc
-- - error:
proc presult_3()
begin
 select 1 `x y`;
end;

-- TEST: verifies that the QID goes all the way up to the proc result shape
-- this is necessary so that the generated DECLARE PROC will be correct
-- + {create_proc_stmt}: presult_4: { `x y`: integer qid, `a b`: integer qid } dml_proc
-- - error:
proc presult_4()
begin
  select * from (select * from qnamed_table);
end;

-- TEST: verifies that the QID goes all the way up to the proc result shape
-- this is necessary so that the generated DECLARE PROC will be correct
-- +  {create_proc_stmt}: presult_5: { `x y`: integer qid, `a b`: integer qid } dml_proc
-- - error:
proc presult_5()
begin
  select T1.* from (select * from qnamed_table) T1;
end;

-- TEST: the IN expression can have an empty match list
-- + LET in_pred_empty := 1 IN ();
-- + {let_stmt}: in_pred_empty: bool notnull variable
-- + {in_pred}: bool notnull
-- - {expr_list}
-- - error;
let in_pred_empty := 1 in ();

-- TEST: verifies identifier creation based resolution
-- + DECLARE foobar2 REAL;
-- + {declare_vars_type}: real
-- + {name foobar2}: foobar2: real variable
declare @ID("foo", "bar", "2") @id("real");


-- TEST: enable nullability analysis on logical expressions.
-- + {enforce_strict_stmt}: ok
-- - error:
@enforce_strict and or not null check;

-- TEST: non null improvements with logical operators
-- + {let_stmt}: inferred_not_null1: bool notnull variable
-- + {let_stmt}: inferred_not_null2: bool notnull variable
-- + {let_stmt}: inferred_not_null3: bool notnull variable
-- + {let_stmt}: should_be_nullable: integer variable
-- + {let_stmt}: should_be_nullable2: bool variable
-- - error:
proc nullability_improvement_with_logical_operators() begin
  let nullable1 := nullable(1);
  let nullable2 := nullable(2);
  let nullable3 := nullable(3);

  -- nullable1 is inferred not null when there is an not null AND check.
  let inferred_not_null1 := nullable1 is not null and nullable1 > 0;

  -- nullable1 is inferred not null when there is a null OR check.
  let inferred_not_null2 := nullable1 is null or nullable1 <= 0;

  -- null improvements should stack
  let inferred_not_null3 := nullable1 is not null and
    nullable2 is not null and
    nullable3 is not null and
    (nullable1 + nullable2 + nullable3) > 3;

  -- null improvements are gone in other statements.
  let should_be_nullable := nullable1;

  -- null improvements can lose effect in outer expression.
  let should_be_nullable2 := (nullable1 is not null and nullable1 > 3) or nullable1 < 0;
end;

-- TEST: cursor improvement with logical operators
-- + {declare_cursor}: c: _select_: { a: text notnull, b: text } variable dml_proc
-- - error:
proc cursor_nullability_improvement_with_logical_operators() begin
  cursor c for select * from has_row_check_table;
  fetch c;

  -- Nullability improvement with AND.
  let x := c and c.a == "hi";

  -- Negative nullability improvement with OR.
  let y := not c or c.a == "";
end;

-- TEST: disable nullability analysis on logical expressions.
-- + {enforce_normal_stmt}: ok
-- - error:
@enforce_normal and or not null check;

-- TEST: declare constant variables
-- + {const_stmt}: a_constant_variable: integer notnull variable constant
-- + | {name a_constant_variable}: a_constant_variable: integer notnull variable constant
-- - error:
const a_constant_variable := 1;

-- TEST: constant variables cannot be changed
-- + error: % cannot re-assign value to constant variable 'cant_change'
-- + error: % cannot re-assign value to constant variable 'cant_change'
-- + error: % additional info: calling 'using_rc' argument #1 intended for parameter 'result_code' has the problem
-- + error: % cannot re-assign value to constant variable 'cant_change'
-- + {const_stmt}: cant_change: integer notnull variable was_set constant
-- + {assign}: err
-- + {call_stmt}: err
-- + {fetch_stmt}: err
-- +4 error:
proc try_modifying_constant_variables()
begin
  const cant_change := 1;

  -- set assignment not allowed
  set cant_change := 2;

  -- assignment to out arg not allowed
  call using_rc(cant_change);

  -- fetch into variable not allowed
  cursor my_cursor for select 1 as one;
  fetch fetch_cursor into cant_change;
end;

-- TEST: empty join scope is not a block for the select list
-- + {select_stmt}: _select_: { a_col: integer notnull }
-- + {orderby_item}
-- + {name a_col}: a_col: integer notnull
-- - error:
select 1 a_col order by a_col;

-- TEST: empty join scope looking for rowid (this will fail)
-- + error: % name not found 'foo.rowid'
-- + {select_stmt}: err
-- +1 error:
select 1 a_col order by foo.rowid;

-- TEST: blocked access to tables
-- + error: % name not found 'foo.rowid'
-- + {select_stmt}: err
-- +1 error:
select * from foo limit foo.rowid;

-- TEST: basic extraction operator
-- + {jex1}: text
-- - error:
select '{ "x" : 1}' -> '$.x' as X;

-- TEST: basic extraction operator: non SQL context
-- + error: % operator may only appear in the context of a SQL statement '->'
-- + {jex1}: err
-- +1 error:
'{ "x" : 1}' -> '$.x';

-- TEST: basic extraction operator: invalid expression
-- + error: % string operand not allowed in 'NOT'
-- + {jex1}: err
(not 'x') -> '$.x';

-- TEST: basic extraction operator, invalid right type
-- + error: % right operand must be json text path or integer '->'
-- + {jex1}: err
-- +1 error:
select '{ "x" : 1}' -> 1.5 as X;

-- TEST: basic extraction operator, invalid left type
-- + error: % left operand must be json text or json blob
-- + {jex1}: err
-- +1 error:
select 1 -> '$.x' as X;

-- TEST: extended extraction operator
-- + {jex2}: int
-- - error:
select '{ "x" : 1}' ->> ~int~ '$.x' as X;

-- TEST: extended extraction operator: non SQL context
-- + error: % operator may only appear in the context of a SQL statement '->>'
-- + {jex2}: err
-- +1 error:
'{ "x" : 1}' ->> ~int~ '$.x';

-- TEST: extended extraction operator: invalid expression
-- + error: % string operand not allowed in 'NOT'
-- + {jex2}: err
(not 'x') ->> ~int~ '$.x';

-- TEST: extended extraction operator: invalid type
-- + error: % unknown type 'not_a_type'
-- + {jex2}: err
-- +1 error:
select 'x' ->> ~not_a_type~ '$.x' as X;

-- TEST: extended extraction operator, invalid right type
-- + error: % right operand must be json text path or integer '->>'
-- + {jex2}: err
-- +1 error:
select '{ "x" : 1}' ->> ~int~ 1.5 as X;

-- TEST: extended extraction operator, invalid left type
-- + error: % left operand must be json text or json blob
-- + {jex2}: err
-- +1 error:
select 1 ->> ~int~ '$.x' as X;

-- TEST: json normalization basic case
-- + {call}: text notnull
-- + {name json}: text notnull
-- - error:
select json('[1]');

-- TEST: json wrong number of args
-- + error: % too few arguments in function 'json'
-- + {call}: err
-- +1 error:
select json();

-- TEST: json function in non SQL-context
-- verify rewrite
-- + SET a_string := ( SELECT json('[1]') IF NOTHING THEN THROW );
-- - error:
a_string := json('[1]');

-- TEST: json function in non SQL-context
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json'
-- + {call}: err
-- +1 error:
select json(1);

-- TEST: jsonb normalization basic case
-- + {call}: blob notnull
-- + {name jsonb}: blob notnull
-- - error:
select jsonb('[1]');

-- TEST: jsonb wrong number of args
-- + error: % too few arguments in function 'jsonb'
-- + {call}: err
-- +1 error:
select jsonb();

-- TEST: json function in non SQL-context
-- verify rewrite
-- + SET blob_var := ( SELECT jsonb('[1]') IF NOTHING THEN THROW );
-- - error:
blob_var := jsonb('[1]');

-- TEST: json function in non SQL-context
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'jsonb'
-- + {call}: err
-- +1 error:
select jsonb(1);

-- TEST: json function for JSON array creation
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_array}: text
-- - error:
select json_array(1,2);

-- TEST: json function for JSON array creation empty args
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_array}: text
-- - error:
select json_array();

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET a_string := ( SELECT json_array() IF NOTHING THEN THROW );
-- - error:
a_string := json_array();

-- TEST: no blobs allowed
-- + error: % argument 2 'blob' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' 'text' in 'json_array'
-- + {call}: err
-- +1 error:
select json_array(1, blob_var, 3);

-- TEST: json function for JSON array creation
-- + {select_stmt}: _select_: { _anon: blob }
-- + {call}: blob
-- + {name jsonb_array}: blob
-- - error:
select jsonb_array(1,2);

-- TEST: json function for JSON array_length
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {call}: integer notnull
-- + {name json_array_length}: integer notnull
-- - error:
select json_array_length('');

-- TEST: json function for JSON array_length with 2 args
-- + {select_stmt}: _select_: { _anon: integer }
-- + {call}: integer
-- - {call}: integer notnull
-- + {name json_array_length}: integer
-- - error:
select json_array_length('', '$.x');

-- TEST: json function for JSON array_length with too many args
-- + error: % too many arguments in function 'json_array_length'
-- + {call}: err
-- +1 error:
select json_array_length('', '$.x', '');

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET an_int := ( SELECT json_array_length('x') IF NOTHING THEN THROW );
-- - error:
an_int := json_array_length('x');

-- TEST: json function for JSON array_length with wrong arg type
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_array_length'
-- + {call}: err
-- +1 error:
select json_array_length(1);

-- TEST: json function for JSON array_length with wrong arg type
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'json_array_length'
-- + {call}: err
-- +1 error:
select json_array_length('x', 1);

-- TEST: json function for JSON error_position with 1 args
-- + {select_stmt}: _select_: { _anon: integer notnull }
-- + {call}: integer notnull
-- + {name json_error_position}: integer notnull
-- - error:
select json_error_position('');

-- TEST: json function for JSON error_position with too many args
-- + error: % too many arguments in function 'json_error_position'
-- + {call}: err
-- +1 error:
select json_error_position('', '');

-- TEST: json function for JSON error_position with wrong arg type
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_error_position'
-- + {call}: err
-- +1 error:
select json_error_position(1);

-- TEST: json function outside of SQL
-- + SET an_int := ( SELECT json_error_position('x') IF NOTHING THEN THROW );
-- - error:
an_int := json_error_position('x');

-- TEST: json function for JSON extraction
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_extract}: text
-- - error:
select json_extract('{"x":0}', '$.x');

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET a_string := ( SELECT json_extract('{"x":0}', '$.x') IF NOTHING THEN THROW );
-- - error:
a_string := json_extract('{"x":0}', '$.x');

-- TEST: only json types allowed
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_extract'
-- + {call}: err
-- +1 error:
select json_extract(1, '1');

-- TEST: only text paths allowed
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'json_extract'
-- + {call}: err
-- +1 error:
select json_extract('[]', 1);

-- TEST: json function for JSON extraction wrong arg count
-- + error: % too few arguments in function 'json_extract'
-- + {call}: err
-- +1 error:
select json_extract();

-- TEST: json function for JSON extraction wrong arg count
-- + error: % too few arguments in function 'jsonb_extract'
-- + {call}: err
-- +1 error:
select jsonb_extract();

-- TEST: json function for JSON extraction wrong arg count
-- + error: % too few arguments in function 'json_remove'
-- + {call}: err
-- +1 error:
select json_remove();

-- TEST: json function for JSON extraction wrong arg count
-- + error: % too few arguments in function 'jsonb_remove'
-- + {call}: err
-- +1 error:
select jsonb_remove();

-- TEST: json function for JSON insert
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_insert}: text notnull
-- - error:
select json_insert('{"x":0}', '$.x', 1, '$.y', 2);

-- TEST: json function for JSON insert nullable value
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_insert}: text
-- - error:
select json_insert(nullable('{"x":0}'), '$.x', 1, '$.y', 2);

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET a_string := ( SELECT json_insert('{"x":0}', '$.x', 2) IF NOTHING THEN THROW );
-- - error:
a_string := json_insert('{"x":0}', '$.x', 2);

-- TEST: only json types allowed
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_insert'
-- + {call}: err
-- +1 error:
select json_insert(1, '$.x', 2);

-- TEST: only json types allowed
-- + error: % starting at argument 2, arguments must come in groups of 2 in 'json_insert'
-- + {call}: err
-- +1 error:
select json_insert(1, '$.x', 2, 3);

-- TEST: no blob types allowed
-- + error: % argument 3 'blob' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' 'text' in 'json_insert'
-- + {call}: err
-- +1 error:
select json_insert('{"x":0}', '$.x', blob_var);

-- TEST: only text paths allowed
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'json_insert'
-- + {call}: err
-- +1 error:
select json_insert('[]', 1, 1);

-- TEST: json function for JSON insert wrong arg count
-- + error: % too few arguments in function 'json_insert'
-- + {call}: err
-- +1 error:
select json_insert();

-- TEST: json function for JSON insert wrong arg count
-- + error: % too few arguments in function 'jsonb_insert'
-- + {call}: err
-- +1 error:
select jsonb_insert();

-- TEST: json function for JSON replace wrong arg count
-- + error: % too few arguments in function 'json_replace'
-- + {call}: err
-- +1 error:
select json_replace();

-- TEST: json function for JSON insert wrong arg count
-- + error: % too few arguments in function 'jsonb_replace'
-- + {call}: err
-- +1 error:
select jsonb_replace();

-- TEST: json function for JSON set wrong arg count
-- + error: % too few arguments in function 'json_set'
-- + {call}: err
-- +1 error:
select json_set();

-- TEST: json function for JSON sst wrong arg count
-- + error: % too few arguments in function 'jsonb_set'
-- + {call}: err
-- +1 error:
select jsonb_set();

-- TEST: json function for JSON object
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_object}: text notnull
-- - error:
select json_object('x', 1, 'y', 2);

-- TEST: json function for JSON object, no args
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_object}: text notnull
-- - error:
select json_object();

-- TEST: json function for JSON object nullable value
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text
-- + {name json_object}: text
-- - error:
select json_object(nullable('x'), 1, 'y', 2);

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET a_string := ( SELECT json_object('x', 1, 'y', 2) IF NOTHING THEN THROW );
-- - error:
a_string := json_object('x', 1, 'y', 2);

-- TEST: no blob types allowed
-- + error: % argument 2 'blob' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' 'text' in 'json_object'
-- + {call}: err
-- +1 error:
select json_object('x', blob_var);

-- TEST: only text paths allowed
-- + {name json_object}: text notnull
-- - error:
select json_object('1', null);

-- TEST: json function for JSON object wrong arg count
-- + error: % starting at argument 1, arguments must come in groups of 2 in 'json_object'
-- + {call}: err
-- +1 error:
select json_object(1);

-- TEST: json function for JSON object wrong arg count
-- + error: % starting at argument 1, arguments must come in groups of 2 in 'jsonb_object'
-- + {call}: err
-- +1 error:
select jsonb_object(1);

-- TEST: json function for JSON object
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_patch}: text notnull
-- - error:
select json_patch('{ "name" : "John" }', '{ "age" : 22 }');

-- TEST: json function for JSON object nullable value
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_patch}: text
-- - error:
select json_patch(nullable('{ "name" : "John" }'), '{ "age" : 22 }');

-- TEST: json function outside of SQL
-- verify rewrite
-- + SET a_string := ( SELECT json_patch('{ "name" : "John" }', '{ "age" : 22 }') IF NOTHING THEN THROW );
-- - error:
a_string := json_patch('{ "name" : "John" }', '{ "age" : 22 }');

-- TEST: no blob types allowed
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_patch'
-- + {call}: err
-- +1 error:
select json_patch(1, blob_var);

-- TEST: json function for JSON patch wrong arg count
-- + error: % too few arguments in function 'json_patch'
-- + {call}: err
-- +1 error:
select json_patch('x');

-- TEST: json function for JSON patch wrong arg count
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'jsonb_patch'
-- + {call}: err
-- +1 error:
select jsonb_patch(1);

-- TEST: json normalization basic case with pretty
-- + {call}: text notnull
-- + {name json_pretty}: text notnull
-- - error:
select json_pretty('[1]');

-- TEST: json normalization basic case with pretty, wrong arg types
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'json_pretty'
-- + {call}: err
-- +1 error:
select json_pretty('[1]', 5);

-- TEST: json function for JSON json_type
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_type}: text notnull
-- - error:
select json_type('[]');

-- TEST: json function for JSON array_length with 2 args
-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- - {call}: text notnull
-- + {name json_type}: text
-- - error:
select json_type('[]', '$.x');

-- TEST: json function for json_valid()
-- + {select_stmt}: _select_: { _anon: bool notnull }
-- + {call}: bool notnull
-- + {name json_valid}: bool notnull
-- - error:
select json_valid('{ "name" : "John" }', 6);

-- TEST: json function for json_valid()
-- + {select_stmt}: _select_: { _anon: bool }
-- + {call}: bool
-- + {name json_valid}: bool
-- - error:
select json_valid('{ "name" : "John" }', nullable(6));

-- TEST: json_valid wrong arg count
-- + error: % too few arguments in function 'json_valid'
-- + {call}: err
-- +1 error:
select json_valid();

-- TEST: json_valid invalid arg 1
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'json_valid'
-- + {call}: err
-- +1 error:
select json_valid(1, 1);

-- TEST: json_valid invalid arg 2
-- + error: % argument 2 'text' is an invalid type; valid types are: 'bool' 'integer' 'long' 'real' in 'json_valid'
-- + {call}: err
-- +1 error:
select json_valid('[]', '2');

-- TEST: json function outside of SQL
-- + SET bb := ( SELECT json_valid('[]', 6) IF NOTHING THEN THROW );
-- - error:
bb := json_valid('[]', 6);

-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {call}: text notnull
-- + {name json_quote}: text notnull
-- - error:
select json_quote(1);

-- + {select_stmt}: _select_: { _anon: text }
-- + {call}: text
-- + {name json_quote}: text
-- - error:
select json_quote(nullable(1));

-- TEST: json_quote wrong arg count
-- + error: % too few arguments in function 'json_quote'
-- + {call}: err
-- +1 error:
select json_quote();

-- TEST: json_quote wrong arg count
-- verify rewrite
-- + SET a_string := ( SELECT json_quote(1) IF NOTHING THEN THROW );
-- - error:
a_string := json_quote(1);

-- TEST: json_group_array
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name json_group_array}: text notnull
-- - error:
select json_group_array(foo.id) from foo;

-- TEST: json_group_array with wrong args
-- + error: % too few arguments in function 'json_group_array'
-- + {call}: err
-- +1 error:
select json_group_array() from foo;

-- TEST: json_group_array in non aggregate context
-- + error: % aggregates only make sense if there is a FROM clause 'json_group_array'
-- + {call}: err
-- +1 error:
select json_group_array();

-- TEST: jsonb_group_array in non aggregate context
-- + error: % aggregates only make sense if there is a FROM clause 'jsonb_group_array'
-- + {call}: err
-- +1 error:
select jsonb_group_array();

-- TEST: json_group_object
-- + {select_stmt}: _select_: { _anon: text notnull }
-- + {name json_group_object}: text notnull
-- - error:
select json_group_object(foo.id, foo.id) from foo;

-- TEST: json_group_object with wrong args
-- + error: % too few arguments in function 'json_group_object'
-- + {call}: err
-- +1 error:
select json_group_object() from foo;

-- TEST: json_group_object in non aggregate context
-- + error: % aggregates only make sense if there is a FROM clause 'json_group_object'
-- + {call}: err
-- +1 error:
select json_group_object();

-- TEST: jsonb_group_object in non aggregate context
-- + error: % aggregates only make sense if there is a FROM clause 'jsonb_group_object'
-- + {call}: err
-- +1 error:
select jsonb_group_object();

func new_builder() create object<list_builder>;
func builder_int(arg1 object<list_builder>, arg2 int!) object<list_builder>;
func builder_int_int(arg1 object<list_builder>, arg2 int!, arg3 int!) object<list_builder>;
func builder_real(arg1 object<list_builder>, arg2 real!) object<list_builder>;
func builder_to_list(arg1 object<list_builder>) create object<list>;

@op object<list_builder> : call to_list as builder_to_list;
@op object<list_builder> : functor all as builder;

-- TEST: multiple rewrites based on the builder pattern above
-- verify rewrite only
-- + LET list_result := builder_to_list(builder_int_int(builder_real(builder_int(new_builder(), 5), 7.0), 1, 2));
let list_result := new_builder():(5):(7.0):(1,2):to_list;

var wrong_object object<wrong>;
-- TEST: we do not rewrite if the object type is incorrect
-- +  function not builtin and not declared 'object<wrong>:functor:all_int'
set list_result := wrong_object:(5);

-- TEST: no kind specified in the left arg
-- + error: % left argument must have a type kind
-- + reverse_apply_poly_args}: err
-- +1 error:
let r := 1:();

-- TEST: poly args with invalid arg list
-- + error: % string operand not allowed in 'NOT'
-- + reverse_apply_poly_args}: err
-- + {arg_list}: err
-- +1 error:
let r := new_builder():(not 'x');

-- TEST: order of operations binary ~
-- verify rewrite, stronger than *
-- + 1 * CAST(2 AS REAL);
1 * 2 ~real~;

-- TEST: order of operations unary ~ -- still high
-- verify rewrite
-- + ~1 + 2;
~1+2;

-- TEST: order of oprations equal to '->'
-- verify rewrite
-- ~ type ~ is weaker than <
-- + SELECT CAST('x' -> 'y' AS INT) AS U;
select 'x' -> 'y' ~int~ as U;

-- TEST: order of oprations same as isnull
-- verify rewrite (stronger than IS etc.)
-- + 1 IS CAST(3 AS INT);
1 IS 3 ~int~;

-- TEST: bogus type in op statement
-- + error: % must be a cursor, proc, table, or view 'not_a_proc_at_all'
-- + {op_stmt}: err
-- +1 error:
@op object<not_a_proc_at_all set> : call foo as foofoo;

-- TEST: use array access where none is defined
-- + error: % function not builtin and not declared 'object<list>:array:get'
-- + {call}: err
-- +1 error:
let uu  := list_result[5];

func do_arrow(x integer, y integer) integer;
func do_text_arrow(x integer, y text) integer;
func do_int_foo_arrow(x integer, y integer) integer;

@op int<foo> : arrow all as do_arrow;
@op int<foo> : arrow text as do_text_arrow;
@op int<foo> : arrow int<foo> as do_int_foo_arrow;
var my_foo int<foo>;

-- TEST: override the -> operator for int<foo>
-- verify rewrite
-- + LET arrow_result := do_arrow(my_foo, 2);
let arrow_result := my_foo -> 2;

-- TEST: override the -> operator for int<foo> for text
-- verify rewrite
-- + SET arrow_result := do_text_arrow(my_foo, '2');
set arrow_result := my_foo -> '2';

-- TEST: override the -> operator for int<foo> and arg int<foo>
-- verify rewrite
-- + SET arrow_result := do_int_foo_arrow(my_foo, my_foo);
set arrow_result := my_foo -> my_foo;

var my_bar text<bar>;

-- TEST: rewrite doesn't happen
-- verify rewrite (lack of rewrite actually)
-- + LET arrow_result_2 := ( SELECT my_bar -> 'x' );
let arrow_result_2 := (select my_bar -> 'x');

@op object<storage> : lshift int as write_int;
func write_int(store object<storage>, val int!) object<storage>;

@op object<storage> : rshift int as read_int;
func read_int(store object<storage>, out val int!) object<storage>;

var store object<storage>;

-- TEST: try << overload to "store"
-- verify rewrite
-- + write_int(store, 5);
-- - error:
store << 5;

-- TEST: try >> overlaod to "read"
-- verify rewrite
-- + read_int(store, int_var);
-- - error:
store >> int_var;

@op object<foo> : concat int as concat_func;
func concat_func(store object<foo>, x int!) object<foo>;

-- TEST: try || overload to concat_func
-- verify rewrite
-- + LET concat_result := concat_func(foo_obj, 5);
-- - error
let concat_result := foo_obj || 5;

-- TEST:  use CURSOR instead of a normal type
-- verify echo
-- + @OP cursor : call foo AS cursor_foo;
-- + {op_stmt}: ok
-- + {name CURSOR}
-- - error:
@op cursor : call foo as cursor_foo;

func cursor_foo(x CURSOR) int;
func cursor_bar(x CURSOR) int;
func cursor_foo_poly_int(x CURSOR, y int) int;

cursor CPipe for select 1 x, 2 y;
fetch CPipe;

-- TEST: use function notation with no declaration
-- verify rewrite
-- + cursor_foo(CPipe);
CPipe:foo;

@op cursor : call bar as cursor_bar;

-- TEST: use function method on a cursor
-- verify rewerite
-- + cursor_bar(CPipe);
CPipe:bar;

@op cursor : functor all as cursor_foo_poly;

-- TEST: use function method on a cursor with arg overloading
-- verify rewerite
-- + cursor_foo_poly_int(CPipe, 1);
CPipe:(1);

@op null: call dump as dump_null;
declare proc dump_null(x integer);

-- TEST: rwwrite call on null
-- verify rewrite
-- + dump_null(NULL);
-- -error:
null:dump();

-- TEST: concat various things
-- + LET concat_func_result := ( SELECT concat(1, 2, "x") IF NOTHING THEN THROW );
-- + {let_stmt}: concat_func_result: text notnull variable was_set
-- - error:
let concat_func_result := concat(1, 2, "x");

-- TEST: concat various things with separator
-- + SET concat_func_result := ( SELECT concat_ws(' ', 1, 2, "x") IF NOTHING THEN THROW );
-- + {assign}: concat_func_result: text notnull variable was_set
-- - error:
set concat_func_result := concat_ws(' ', 1, 2, "x");

-- TEST: concat various things with separator, maybe null
-- + LET concat_func_result2 := ( SELECT concat_ws(a_string, 1, 2, "x") IF NOTHING THEN THROW );
-- + {let_stmt}: concat_func_result2: text variable
-- - error:
let concat_func_result2 := concat_ws(a_string, 1, 2, "x");

-- TEST: concat_ws with too few args
-- + error: % too few arguments in function 'concat_ws'
-- + {assign}: err
-- +1 error:
set concat_func_result2 := concat_ws(a_string);

-- TEST: concat_ws with too few args
-- + error: % too few arguments in function 'concat'
-- + {assign}: err
-- +1 error:
set concat_func_result2 := concat();

-- TEST: concat with too few args
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'concat_ws'
-- + {assign}: err
-- +1 error:
set concat_func_result2 := concat_ws(7, 'x');

-- TEST: concat with NULL arg
-- + error: % argument 3 is a NULL literal; useless in 'concat_ws'
-- + {assign}: err
-- +1 error:
set concat_func_result2 := concat_ws(' ', 2, NULL, 4);

-- TEST: concat with NULL arg
-- + error: % argument 3 is a NULL literal; useless in 'concat'
-- + {assign}: err
-- +1 error:
set concat_func_result2 := concat(' ', 2, NULL, 4);

-- TEST: like full form with escape string
-- + {name like}: bool notnull
-- - error:
let like_func := like('a', 'b', 'c');

-- TEST: glob full form with escape string
-- + {name glob}: bool notnull
-- - error:
let glob_func := glob('a', 'b');

-- TEST: bogus arg in matcher
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'like'
-- + {assign}: err
-- +1 error:
set like_func := like(0, 'b', 'c');

-- TEST: bogus arg in matcher
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'like'
-- + {assign}: err
-- +1 error:
set like_func := like('a', 0, 'c');

-- TEST: bogus arg in matcher
-- + error: % argument 3 'integer' is an invalid type; valid types are: 'text' in 'like'
-- + {assign}: err
-- +1 error:
set like_func := like('a', 'b', 0);

-- TEST: bogus arg in matcher
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'glob'
-- + {assign}: err
-- +1 error:
set glob_func := glob(0, 'b');

-- TEST: bogus arg in matcher
-- + error: % argument 2 'integer' is an invalid type; valid types are: 'text' in 'glob'
-- + {assign}: err
-- +1 error:
set glob_func := glob('a', 0);

-- TEST: bogus arg in matcher
-- + error: % too few arguments in function 'like'
-- + {assign}: err
-- +1 error:
set like_func := like();

-- TEST: bogus arg in matcher
-- + error: % too few arguments in function 'glob'
-- + {assign}: err
-- +1 error:
set glob_func := glob();

-- TEST: sqlite version normal call
-- + LET sql_vers := ( SELECT sqlite_version() );
-- + {let_stmt}: sql_vers: text notnull variable
-- - error:
let sql_vers := (select sqlite_version());

-- TEST: sqlite version normal call
-- + error: % too many arguments in function 'sqlite_version'
-- + {call}: err
-- +1 error:
set sql_vers := (select sqlite_version(1));

-- TEST: sqlite compile option normal call
-- + LET sql_option := ( SELECT sqlite_compileoption_get(1) IF NOTHING THEN THROW );
-- + let_stmt}: sql_option: text variable
-- - error:
let sql_option := sqlite_compileoption_get(1);

-- TEST: sqlite compile option no args
-- + error: % too few arguments in function 'sqlite_compileoption_get'
-- + {assign}: err
-- +1 error:
set sql_option := sqlite_compileoption_get();

-- TEST: sqlite compile option used normal call
-- + LET sql_bool_option := ( SELECT sqlite_compileoption_used("foo") IF NOTHING THEN THROW );
-- + {let_stmt}: sql_bool_option: bool notnull variable
-- - error:
let sql_bool_option := "foo":sqlite_compileoption_used;

-- TEST: sqlite compile option used no args
-- + error: % too few arguments in function 'sqlite_compileoption_used'
-- + {assign}: err
-- +1 error:
set sql_bool_option := sqlite_compileoption_used();

-- TEST: sqlite version normal call
-- + LET t_changes := ( SELECT total_changes() );
-- + {let_stmt}: t_changes: longint notnull variable
-- - error:
let t_changes := (select total_changes());

-- TEST: sqlite version normal call
-- + error: % too many arguments in function 'total_changes'
-- + {call}: err
-- +1 error:
set t_changes := (select total_changes(1));

-- TEST: sqlite version normal call
-- + LET sql_src := ( SELECT sqlite_source_id() );
-- + {let_stmt}: sql_src: text notnull variable
-- - error:
let sql_src := (select sqlite_source_id());

-- TEST: sqlite version normal call
-- + error: % too many arguments in function 'sqlite_source_id'
-- + {call}: err
-- +1 error:
set sql_src := (select sqlite_source_id(1));

-- TEST: normal call to hex
-- + LET hex_str := ( SELECT hex("123") IF NOTHING THEN THROW );
-- + {let_stmt}: hex_str: text notnull variable was_set
-- - error:
let hex_str := hex("123");

-- TEST: hex call with bad arg
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' 'blob' in 'hex'
-- +1 error:
set hex_str := hex(1);

-- TEST: hex call with nullable arg
-- this forces use to validate the nullable transitions
-- + SET hex_str := ifnull_throw(( SELECT hex(nullable("123")) IF NOTHING THEN THROW ));
-- + {select_if_nothing_throw_expr}: _anon: text
-- - error:
set hex_str := "123":nullable:hex:ifnull_throw;

-- TEST: normal call to soundex
-- + LET soundex_str := ( SELECT soundex(nullable("123")) IF NOTHING THEN THROW );
-- + {let_stmt}: soundex_str: text notnull variable
-- - error:
let soundex_str := "123":nullable:soundex;

-- TEST: soundex call with bad arg
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'soundex'
-- +1 error:
set soundex_str := soundex(1);

-- TEST: normal call to unhex
-- + LET unhex_blob := ( SELECT unhex("1234") IF NOTHING THEN THROW );
-- + {let_stmt}: unhex_blob: blob notnull variable was_set
-- - error:
let unhex_blob := unhex("1234");

-- TEST: normal call to unhex
-- + SET unhex_blob := ( SELECT unhex("1234-56", "-") IF NOTHING THEN THROW );
-- + {assign}: unhex_blob: blob notnull variable was_set
-- - error:
set unhex_blob := unhex("1234-56", "-");

-- TEST: unhex call with bad arg
-- + error: % argument 1 'integer' is an invalid type; valid types are: 'text' in 'unhex'
-- +1 error:
set unhex_blob := unhex(1);

-- TEST: unhex call with nullable arg
-- this forces use to validate the nullable transitions
-- + SET unhex_blob := ifnull_throw(( SELECT unhex(nullable("1234")) IF NOTHING THEN THROW ));
-- + {select_if_nothing_throw_expr}: _anon: blob
-- - error:
set unhex_blob := "1234":nullable:unhex:ifnull_throw;

-- TEST: normal call to quote
-- + LET quote_str := ( SELECT quote("123") IF NOTHING THEN THROW );
-- + {let_stmt}: quote_str: text notnull variable was_set
-- - error:
let quote_str := quote("123");

-- TEST: quote call with bad arg
-- + error: % too few arguments in function 'quote'
-- +1 error:
set quote_str := quote();

-- TEST: quote call with nullable arg
-- this forces use to validate the nullable transitions
-- + SET quote_str := ifnull_throw(( SELECT quote(nullable("123")) IF NOTHING THEN THROW ));
-- + {select_if_nothing_throw_expr}: _anon: text
-- - error:
set quote_str := "123":nullable:quote:ifnull_throw;

-- TEST: zero blob success
-- + {let_stmt}: zero_blob: blob notnull variable
-- - error:
let zero_blob := (select zeroblob(1));

-- TEST: zero blob rewritten to sql context
-- + SET zero_blob := ( SELECT zeroblob(1) IF NOTHING THEN THROW );
-- + {assign}: zero_blob: blob notnull variable was_set
-- - error:
set zero_blob := zeroblob(1);

-- TEST: zero blob invalid args
-- + error: % too few arguments in function 'zeroblob'
-- + {assign}: err
-- +1 error:
set zero_blob := (select zeroblob());

-- TEST: random blob success
-- + {let_stmt}: random_blob: blob notnull variable
-- - error:
let random_blob := (select randomblob(1));

-- TEST: typeof normal usage
-- + {let_stmt}: type_string: text notnull variable
-- - error:
let type_string := (select typeof('foo'));

-- TEST: typeof error usage
-- + error: % argument 1 is a NULL literal; useless in 'typeof'
-- + {assign}: err
-- +1 error:
set type_string := (select typeof(null));

-- TEST: typeof error usage
-- + error: % function may not appear in this context 'typeof'
-- + {assign}: err
-- +1 error:
set type_string := typeof(null);

-- TEST: try to  load extension, good args
-- + {let_stmt}: loaded: bool variable was_set
-- + {call}: bool
-- - error:
let loaded := (select load_extension('foo', 'bar'));

-- TEST: try to  load extension, good args
-- + {assign}: loaded: bool variable was_set
-- + {call}: bool
-- - error:
set loaded := (select load_extension('foo'));

-- TEST: try to load extension, no args
-- + error: % too few arguments in function 'load_extension'
-- + {call}: err
-- +1 error:
set loaded := (select load_extension());

-- TEST: try to load extension, wrong context
-- + error: % function may not appear in this context 'load_extension'
-- + {call}: err
-- +1 error:
set loaded := load_extension('foo');

-- TEST: ifdef with an error in the interior statement list
-- + error: % string operand not allowed in 'NOT'
-- + {ifndef_stmt}: err
-- + | {is_true}
-- +1 error:
@ifndef foo
  let bogus_assignment_ifndef := not 'x';
@endif


@macro(stmt_list) macro_one!(x! expr)
begin
   let @tmp(x) := x!;
   let @tmp(y) := @tmp(x) + @tmp(x);
end;

@macro(stmt_list) macro_two!(x! expr)
begin
   let @tmp(x) := x!;
   macro_one!(@tmp(x));
end;

func expensive(x int) int!;

-- TEST: we are testing the expansion of macro_two
-- we can't readily validate that the @tmp(x) has
-- the same number when we expand `macro_one` but if
-- it doesn't there will be a compile error, we
-- can catch that.
-- The number might change if other @tmp is added above here.
-- But no errors.
-- + LET tmp_%x := expensive(100);
-- + LET tmp_%x := tmp_%x;
-- + LET tmp_%y := tmp_%x + tmp_%x;
-- + LET tmp_%x := expensive(200);
-- + LET tmp_%x := tmp_%x;
-- + LET tmp_%y := tmp_%x + tmp_%x;
-- + {create_proc_stmt}: ok
-- - error:
proc use_nested_macros_with_at_tmp()
begin
   macro_two!(expensive(100));
   macro_two!(expensive(200));
end;

create table insert_returning_test(
  ix int,
  iy int
);

-- TEST: insert returning normal case -- no with clause
-- + {create_proc_stmt}: insert_returning1: { xy: integer, ix: integer, iy: integer } dml_proc
-- + {insert_returning_stmt}: _select_: { xy: integer, ix: integer, iy: integer }
-- - error:
proc insert_returning1 ()
begin
  insert into insert_returning_test
    values (1, 2)
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: insert returning normal case -- and with clause
-- + {create_proc_stmt}: insert_returning2: { xy: integer, ix: integer, iy: integer } dml_proc
-- + {insert_returning_stmt}: _select_: { xy: integer, ix: integer, iy: integer }
-- - error:
proc insert_returning2 ()
begin
  with
    base as (
      select *
        from insert_returning_test
        where x = 7
    )
  insert into insert_returning_test
    select ix + 10, iy + 10
      from base
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: insert returning error case, bogus insert
-- + error: % table in insert statement does not exist 'insert_returning_yeah_no'
-- + {create_proc_stmt}: err
-- + {insert_returning_stmt}: err
-- +1 error:
proc insert_returning_invalid_insert ()
begin
  insert into insert_returning_yeah_no
    values (1, 2)
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: insert returning error case, bogus with ... insert
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {insert_returning_stmt}: err
-- +1 error:
proc insert_returning_invalid_with_insert ()
begin
  with foo as (select not 'x')
  insert into insert_returning_test
    values (1, 2)
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: insert returning error case, bogus select list
-- + error: % name not found 'nope'
-- + {create_proc_stmt}: err
-- + {insert_returning_stmt}: err
-- + {select_expr_list}: err
-- +1 error:
proc insert_returning_invalid_return ()
begin
  insert into insert_returning_test
    values (1, 2)
    returning nope;
end;

-- TEST: insert returning in a cursor
-- The procedure did not get the type of the cursor! That only happens if the insert is "loose"
-- + {create_proc_stmt}: ok dml_proc
-- + {declare_cursor}: C: _select_: { xy: integer, ix: integer, iy: integer } variable dml_proc
-- - error:
proc insert_returning_cursor()
begin
  declare C cursor for insert into insert_returning_test(ix,iy) values (1,2)
  returning ix+iy xy, ix, iy;
  loop fetch C
  begin
    printf("%d %d %d", C.ix, C.iy, C.xy);
  end;
end;
-- TEST: insert statement without returns doesn't produce a result
-- + error: % statement requires a RETURNING clause to be used as a source of rows
-- + declare_cursor}: err
-- +1 error:
proc insert_returning_cursor_bogus()
begin
  declare C cursor for insert into insert_returning_test(ix,iy) values (1,2);
end;

[[backing_table]]
[[json]]
create table jb_insert (
  k blob primary key,
  v blob
);

[[backed_by=jb_insert]]
create table jbacked(
  id int primary key,
  name text,
  age int
);

-- TEST: rewrite backed table returning
-- verify the rewrite only
-- + WITH
-- +   _vals (id, name, age) AS (
-- +     VALUES
-- +       (1, 'x', 10),
-- +       (2, 'y', 15)
-- +   )
-- + INSERT INTO jb_insert(k, v)
-- +   SELECT cql_blob_create(jbacked, V.id, jbacked.id),
-- = cql_blob_create(jbacked, V.name, jbacked.name, V.age, jbacked.age)
-- +     FROM _vals AS V
-- +   RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- - error:
proc insert_into_backed_returning()
begin
  insert into jbacked values (1, 'x', 10), (2, 'y', 15)
  returning id, name, age;
end;

-- TEST: delete from backed with returning
-- First verify the rewrite (it's backed)
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked())
-- + DELETE FROM jb_insert WHERE rowid IN (SELECT rowid
-- +   FROM jbacked
-- +   WHERE id = 5)
-- +   RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: delete_from_backed_returning: { id: integer notnull, name: text, age: integer } dml_proc
-- + {delete_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc delete_from_backed_returning()
begin
  delete from jbacked where id = 5
  returning id, name, age;
end;

-- TEST: delete from backed with returning and CTE
-- verify rewrite first (it's backed)
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked()),
-- +   a_cte (x) AS (
-- +     SELECT 1 AS x
-- +   )
-- + DELETE FROM jb_insert WHERE rowid IN (SELECT rowid
-- +   FROM jbacked
-- +   WHERE id IN (SELECT a_cte.x
-- +   FROM a_cte))
-- +   RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: with_delete_from_backed_returning: { id: integer notnull, name: text, age: integer } dml_proc
-- + {delete_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc with_delete_from_backed_returning()
begin
  with a_cte as (select 1 x)
  delete from jbacked where id in (select * from a_cte)
  returning id, name, age;
end;

-- TEST: delete returning is ok in a cursor and that doesn't make the proc have a result set
-- first verify rewrite (it's backed)
-- + CURSOR C FOR
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked())
-- +   DELETE FROM jb_insert WHERE rowid IN (SELECT rowid
-- +   FROM jbacked
-- +   WHERE id = 5)
-- + {create_proc_stmt}: ok
-- + {declare_cursor}: C: _select_: { id: integer notnull, name: text, age: integer } variable dml_proc
-- + {delete_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc delete_returning_cursor()
begin
  cursor C for
    delete from jbacked where id = 5
    returning id, name, age;
end;

-- TEST: this is an incorrect form, this delete isn't a row source
-- + error: % statement requires a RETURNING clause to be used as a source of rows
-- +1 error:
-- + declare_cursor}: err
proc bogus_delete_cursor()
begin
  cursor C for
    delete from jbacked;
end;

-- TEST: delete returning error case, bogus with ... delete
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {delete_returning_stmt}: err
-- +1 error:
proc delete_returning_invalid_with_delete ()
begin
  with foo as (select not 'x')
  delete from insert_returning_test
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: delete returning error case, bogus select list
-- + error: % name not found 'nope'
-- + {create_proc_stmt}: err
-- + {delete_returning_stmt}: err
-- + {select_expr_list}: err
-- +1 error:
proc delete_returning_invalid_return ()
begin
  delete from insert_returning_test
    returning nope;
end;

-- TEST: update from backed with returning
-- First verify the rewrite (it's backed)
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked())
-- + UPDATE jb_insert
-- +   SET k = cql_blob_update(k, 7, jbacked.id)
-- +   WHERE rowid IN (SELECT rowid
-- +     FROM jbacked
-- +     WHERE id = 5)
-- +   RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: update_from_backed_returning: { id: integer notnull, name: text, age: integer } dml_proc
-- + {update_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc update_from_backed_returning()
begin
  update jbacked set id = 7 where id = 5
  returning id, name, age;
end;

-- TEST: update from backed with returning and CTE
-- verify rewrite first (it's backed)
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked()),
-- +   a_cte (x) AS (
-- +     SELECT 1 AS x
-- +   )
-- + UPDATE jb_insert
-- +   SET k = cql_blob_update(k, 7, jbacked.id)
-- +   WHERE rowid IN (SELECT rowid
-- +    FROM jbacked
-- +     WHERE id = 5)
-- +   RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: with_update_from_backed_returning: { id: integer notnull, name: text, age: integer } dml_proc
-- + {update_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc with_update_from_backed_returning()
begin
  with a_cte as (select 1 x)
  update jbacked set id = 7 where id = 5
  returning id, name, age;
end;

-- TEST: update returning is ok in a cursor and that doesn't make the proc have a result set
-- first verify rewrite (it's backed)
-- + CURSOR C FOR
-- + WITH
-- +   jbacked (rowid, id, name, age) AS (CALL _jbacked())
-- + UPDATE jb_insert
-- +   SET k = cql_blob_update(k, 7, jbacked.id)
-- +   WHERE rowid IN (SELECT rowid
-- +     FROM jbacked
-- +     WHERE id = 5)
-- +     RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: ok
-- + {declare_cursor}: C: _select_: { id: integer notnull, name: text, age: integer } variable dml_proc
-- + {update_returning_stmt}: _select_: { id: integer notnull, name: text, age: integer }
-- - error:
proc update_returning_cursor()
begin
  cursor C for
    update jbacked set id = 7 where id = 5
    returning id, name, age;
end;

-- TEST: this is an incorrect form, this update isn't a row source
-- + error: % statement requires a RETURNING clause to be used as a source of rows
-- +1 error:
-- + declare_cursor}: err
proc bogus_update_cursor()
begin
  cursor C for
    update insert_returning_test set ix = 7 where ix = 5;
end;

-- TEST: update returning error case, bogus with ... update
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {update_returning_stmt}: err
-- +1 error:
proc update_returning_invalid_with_update ()
begin
  with foo as (select not 'x')
  update insert_returning_test set ix = 7 where ix = 5
    RETURNING ix + iy AS xy, ix, iy;
end;

-- TEST: update returning error case, bogus select list
-- + error: % name not found 'nope'
-- + {create_proc_stmt}: err
-- + {update_returning_stmt}: err
-- + {select_expr_list}: err
-- +1 error:
proc update_returning_invalid_return ()
begin
  update insert_returning_test set ix = 7 where ix = 5
    returning nope;
end;

-- TEST: verify that the returning star is expanded correctly
-- this has to happen early, the normal star expansion doesn't
-- work here.  Behind the scenes the columns form is used and
-- it might be good to use that universally... moving the rewrite
-- further up the chain so that not all code gen has to deal with it.
-- but that is for a later time.
--
-- this is the essential rewrite
-- + RETURNING cql_blob_get(k, jbacked.id), cql_blob_get(v, jbacked.name), cql_blob_get(v, jbacked.age);
-- + {create_proc_stmt}: ok dml_proc
-- + {declare_cursor}: C: _select_: { id: integer notnull, name: text, age: integer } variable dml_proc
-- - error:
PROC expand_returning_star()
BEGIN
  cursor C for
  insert into jbacked(id, name) values (1,'foo') returning *;
END;

-- stress test for backing tables with funky names
-- verify correct parse and echo of qid names
-- + [[backing_table]]
-- + [[jsonb]]
-- + CREATE TABLE `a backing table`(
-- +   `the key` BLOB PRIMARY KEY,
-- +   `the value` BLOB
-- + );
-- - error:
[[backing_table]]
[[jsonb]]
create table `a backing table`(`the key` blob primary key, `the value` blob);

-- stress test for backed tables with funky names
-- verify correct parse and echo of qid names
-- + [[backed_by=`a backing table`]]
-- + CREATE TABLE `a table`(
-- +   `col 1` INT PRIMARY KEY,
-- +   `col 2` INT
-- + );
-- - error:
[[backed_by=`a backing table`]]
create table `a table`( `col 1` int primary key, `col 2` int);

-- TEST: upsert into a backed table with weird names... All the pains.
-- first verify the rewrite, this is complex with all the weird names
-- and many clauses.  We found many bugs when we first added this test,
-- do not delete it lightly.
-- + WITH
-- +   _vals (`col 1`, `col 2`) AS (
-- +     VALUES (1, 2)
-- +   )
-- + INSERT INTO `a backing table`(`the key`, `the value`)
-- + SELECT cql_blob_create(`a table`, V.`col 1`, `a table`.`col 1`), cql_blob_create(`a table`, V.`col 2`, `a table`.`col 2`)
-- +   FROM _vals AS V
-- + ON CONFLICT (`the key`)
-- + WHERE cql_blob_get(`the value`, `a table`.`col 2`) = 1
-- + DO UPDATE
-- +   SET `the key` = cql_blob_update(`the key`, ifnull(cql_blob_get(`the value`, `a table`.`col 2`), 0), `a table`.`col 1`)
-- +   RETURNING cql_blob_get(`the key`, `a table`.`col 1`), cql_blob_get(`the value`, `a table`.`col 2`);
-- + {create_proc_stmt}: upsert_into_backed_returning: { `col 1`: integer notnull qid, `col 2`: integer qid } dml_proc
-- + {upsert_returning_stmt}: _select_: { `col 1`: integer notnull qid, `col 2`: integer qid }
-- + {update_stmt}: `a backing table`: { `the key`: blob notnull primary_key qid, `the value`: blob qid } backing qid
-- + {select_expr_list}: _select_: { `col 1`: integer notnull qid, `col 2`: integer qid }
-- - error:
proc upsert_into_backed_returning()
begin
  insert into `a table`
    values (1, 2)
  on conflict (`col 1`)
  where `col 2` = 1 do update
    set `col 1` = `col 2`:ifnull(0)
    returning `col 1`, `col 2`;
end;

-- TEST: cursor form of update returning this should not affect the procedure
-- first verify the rewrite, this is quite tricky and found many bugs
-- + CURSOR C FOR
-- +   WITH
-- +     _vals (`col 1`, `col 2`) AS (
-- +       VALUES (1, 2)
-- +     )
-- +   INSERT INTO `a backing table`(`the key`, `the value`)
-- +     SELECT cql_blob_create(`a table`, V.`col 1`, `a table`.`col 1`), cql_blob_create(`a table`, V.`col 2`, `a table`.`col 2`)
-- +       FROM _vals AS V
-- +   ON CONFLICT (`the key`)
-- +   WHERE cql_blob_get(`the value`, `a table`.`col 2`) = 1
-- +   DO UPDATE
-- +     SET `the key` = cql_blob_update(`the key`, ifnull(cql_blob_get(`the value`, `a table`.`col 2`), 0), `a table`.`col 1`)
-- +     RETURNING cql_blob_get(`the key`, `a table`.`col 1`), cql_blob_get(`the value`, `a table`.`col 2`);
-- now essential AST shape
-- + {create_proc_stmt}: ok dml_proc
-- + {declare_cursor}: C: _select_: { `col 1`: integer notnull qid, `col 2`: integer qid } variable dml_proc
-- + {upsert_returning_stmt}: _select_: { `col 1`: integer notnull qid, `col 2`: integer qid }
-- + {name `a backing table`}: `a backing table`: { `the key`: blob notnull primary_key qid, `the value`: blob qid } backing qid
-- + {conflict_target}: `a backing table`: { `the key`: blob notnull qid, `the value`: blob qid }
-- - error:
proc upsert_into_backed_cursor()
begin
  cursor C for
  insert into `a table`
    values (1, 2)
  on conflict (`col 1`)
  where `col 2` = 1 do update
    set `col 1` = `col 2`:ifnull(0)
    returning `col 1`, `col 2`;
end;

-- TEST: apply with clause
-- verify the rewrite, that's really all of it
-- + CURSOR C FOR
-- +   WITH
-- +     a_cte (x) AS (
-- +       VALUES
-- +         (1),
-- +         (2),
-- +         (3)
-- +     )
-- +   INSERT INTO `a backing table`(`the key`, `the value`)
-- +     SELECT cql_blob_create(`a table`, V.`col 1`, `a table`.`col 1`), cql_blob_create(`a table`, V.`col 2`, `a table`.`col 2`)
-- +       FROM _vals AS V
-- +   ON CONFLICT (`the key`)
-- +   WHERE cql_blob_get(`the value`, `a table`.`col 2`) IN (SELECT a_cte.x
-- +     FROM a_cte)
-- +   DO UPDATE
-- +     SET `the key` = cql_blob_update(`the key`, ifnull(cql_blob_get(`the value`, `a table`.`col 2`), 0), `a table`.`col 1`)
-- +     RETURNING cql_blob_get(`the key`, `a table`.`col 1`), cql_blob_get(`the value`, `a table`.`col 2`);
-- - backed(
-- - error:
proc with_upsert_returning()
begin
  cursor C for
  with a_cte(x) as (values (1), (2), (3))
  insert into `a table`
    values (1, 2)
  on conflict (`col 1`)
  where `col 2` in (select * from a_cte) do update
    set `col 1` = `col 2`:ifnull(0)
    returning `col 1`, `col 2`;
end;

-- TEST: bogus CTE
-- + error: % string operand not allowed in 'NOT'
-- + {create_proc_stmt}: err
-- + {upsert_returning_stmt}: err
-- +1 error:
proc with_upsert_returning_error_cte()
begin
  cursor C  for
  with a_cte(x) as (values (not 'x'))
  insert into `a table`
    values (1, 2)
  on conflict do nothing
  returning `col 1`, `col 2`;
end;

-- TEST: bogus returning clause
-- + error: % name not found 'nope'
-- + {create_proc_stmt}: err
-- + {upsert_returning_stmt}: err
-- +1 error:
proc with_upsert_returning_error_in_returning()
begin
  cursor C  for
  insert into `a table`
    values (1, 2)
  on conflict do nothing
  returning nope;
end;

-- TEST: anonymous columns in the return
-- + error: % identifier is ambiguous '_anon'
-- + error: % additional info: more than one anonymous column in a result, likely all columsn need a name
-- +2 error:
-- + {create_proc_stmt}: err
proc anon_columns()
begin
  select * from (select 1, 2) as T;
end;

-- TEST: we can still force a failure in the exists logic, just not in the select list
-- the select list is rewritten to 1 regardless of what you put there
-- + error: % table/view not defined 'no_such_table'
-- + {create_proc_stmt}: err
-- +1 error:
proc select_exists_failure()
begin
  let b := (select exists(select not 'x' from no_such_table));
end;


proc make_jsonb_backed_schema()
begin
  [[backing_table]]
  [[jsonb]]
  create table backtab(
    kk blob primary key,
    vv blob
  );
end;

[[backed_by=`a backing table`]]
create table a_table(
  col1 int primary key,
  col2 int
);

[[backed_by=`a backing table`]]
create table b_table(
  col1 int primary key,
  col2 int
);

[[backed_by=`a backing table`]]
create table c_table(
  col1 int primary key,
  col2 int
);

-- TEST: verify that all the implied backed tables are considered
-- the point of this test is to verify that all three backing table references
-- were added to the CTE list (there were bugs here)
-- + WITH
-- + a_table (rowid, col1, col2) AS (CALL _a_table()),
-- + b_table (rowid, col1, col2) AS (CALL _b_table()),
-- + c_table (rowid, col1, col2) AS (CALL _c_table()),
-- + _vals (col1, col2) AS (
-- + INSERT INTO `a backing table`(`the key`, `the value`)
-- +3 (CALL %table())
proc backed_table_implied_refs ()
begin
  cursor c for
    insert into a_table(col1, col2)
      values
        (1, 1),
        (5, 25)
    on conflict (col1)
    do update
      set `col2` = 1000
      where excluded.`col1` not in (
      select col1 from a_table
      union
      select col1 from b_table
      union
      select col1 from c_table)
      returning *;
end;

-- TEST: for loop ok
-- + for_stmt}: ok
-- + {le}: bool notnull
-- + {int 5}: integer
-- + {for_info}
-- + {assign}: i: integer notnull variable was_set
-- -error:
proc for_loop_ok()
begin
  let i := 0;
  for i <= 5; i += 1;
  begin
  end;
end;

-- TEST: for loop bad expression
-- + error: % string operand not allowed in 'NOT'
-- +1 error:
-- + {for_stmt}: err
proc for_loop_bad_expr()
begin
  let i := 0;
  for i <= not 'x'; i += 1;
  begin
  end;
end;

-- TEST: for loop bad update stmts
-- + error: % duplicate variable name in the same scope 'i'
-- +1 error:
-- + {for_stmt}: err
proc for_loop_bad_update()
begin
  let i := 0;
  for i <= 5; let i := 0;
  begin
  end;
end;

-- TEST: for loop bad stmt block
-- + error: % duplicate variable name in the same scope 'i'
-- +1 error:
-- + {for_stmt}: err
proc for_loop_bad_block()
begin
  let i := 0;
  for i <= 5; i += 1;
  begin
    let i := not 'x';
  end;
end;

-- TEST: for loop, update statements are evaluated second
-- + error: % variable not found 'not_visible'
-- +1 error:
-- + {for_stmt}: err
proc for_loop_update_second()
begin
  let i := 0;
  for i <= 5; let not_visible := 1;
  begin
    not_visible := 5;
  end;
end;

const group some_constants (
  bazzle = 5
);

enum HarmonyTint integer (
  orange
);

-- TEST: declare an enum that uses constant names outside of itself
-- + ENUM GoalTint INT (
-- +   boo = 1,
-- +   coo = 5,
-- +   doo = 1 + 5,
-- +   foo = 6
-- + );
-- + {declare_enum_stmt}: GoalTint: integer<GoalTint> notnull
-- - error:
enum GoalTint integer (
  boo = HarmonyTint.orange,
  coo = bazzle,
  doo = HarmonyTint.orange + bazzle,
  foo = doo
);

-- TEST: an invalid constant
-- + error: % enum does not contain 'garbonzo'
-- + error: % evaluation failed 'stew'
-- + {declare_enum_stmt}: err
-- +2 error:
enum ErroneousEnum integer (
  stew = HarmonyTint.garbonzo
);

CREATE TABLE map_xy(
  map_y long PRIMARY KEY,
	map_x long!
);

[[shared_fragment]]
proc frag_xy(x_ long!, y_ long!)
begin
  select x_ x, y_ y;
end;

-- TEST: do not allow the arguments of a call to a shared CTE to reference an outer CTE
-- + error: % table/view not defined 'mapping'
-- + error: % additional info: calling 'frag_xy' argument #1 intended for parameter 'x_' has the problem
-- + {create_proc_stmt}: err
-- +2 error:
[[shared_fragment]]
proc mapped_xy(y_ long!)
begin
  with mapping as (
    select map_x from map_xy where map_y = y_
  )
	select * from (call frag_xy((select x from mapping), y_));
end;
