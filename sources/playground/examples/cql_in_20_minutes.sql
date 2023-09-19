-- CHAPTER 0 — Preamble

-- Single line comments start with two dashes

/* C style comments also work
 *
 * C pre-processor features like #include and #define are generally available
 * CQL is typically run through the C pre-processor before it is compile.
 */

-- The SQL file can be pre-processed with the C pre-processor
-- E.g. It can be used to include another .sql file (which provides utility functions and macros)
#include "./cql_in_20_minutes.utils.sql"

create procedure chapter_1 ()
begin
  _("## CHAPTER 1 — Primitive Datatypes and Operators\n");

  _("### You have numbers, strings, and booleans\n");
  EXAMPLE(3,    "-- An integer");
  EXAMPLE(3L,   "-- A long integer");
  EXAMPLE(3.5,  "-- A real literal");
  EXAMPLE(0x10, "-- 16 in hex");
  _("");


  _("### Math is what you would expect\n");
  EXAMPLE(1 + 1);  
  EXAMPLE(8 - 1);
  EXAMPLE(10 * 2);
  EXAMPLE(35.0 / 5);
  _("");


  _("### Modulo operation, same as C and SQLite\n");
  EXAMPLE(7 % 3);
  EXAMPLE(-7 % 3);
  EXAMPLE(7 % -3);
  EXAMPLE(-7 % 3);
  _("");


  _("### Bitwise operators bind left to right like in SQLite\n");
  EXAMPLE(2 | 4 & 1,   "-- (Expected LTR: 0, RTL/Standard: 2)");
  EXAMPLE(2 | (4 & 1), "-- (Standard Evaluation)");
  EXAMPLE((2 | 4) & 1, "-- (Left-to-Right Evaluation)");
  _("");


  _("### Enforce precedence with parentheses\n");
  EXAMPLE(1 + 3 * 2);
  EXAMPLE((1 + 3) * 2);
  _("");


  _("### Use true and false for bools, nullable bool is possible\n");

  EXAMPLE(true,  "-- how to true");
  EXAMPLE(false, "-- how to false");
  EXAMPLE(null,  "-- null means \"unknown\" in CQL like SQLite");
  _("");


  _("### Negate with not\n");
  EXAMPLE(not true);
  EXAMPLE(not false);
  EXAMPLE(not null, "-- not unknown is unknown");
  _("");


  _("### Logical Operators\n");
  let x := 1;
  EXAMPLE(1 and 0);
  EXAMPLE(0 or 1);
  EXAMPLE(0 and x, "-- x not evaluated");
  EXAMPLE(1 or x,  "-- x not evaluated");
  _("");


  _("### Remember null is \"unknown\"\n");
  EXAMPLE(null or false);
  EXAMPLE(null or true);
  EXAMPLE(null and false);
  EXAMPLE(null and true);
  _("");


  _("### Non-zero values are truthy\n");
  EXAMPLE(0);
  EXAMPLE(4);
  EXAMPLE(-6);
  EXAMPLE(0 and 2);
  EXAMPLE(-5 or 0);
  _("");


  _("### Equality is == or =\n");
  EXAMPLE(1 == 1);
  EXAMPLE(1 = 1, "-- = and == are the same thing");
  EXAMPLE(2 == 1);
  _("");


  _("### IS lets you compare against null\n");
  EXAMPLE(1 IS 1);
  EXAMPLE(2 IS 1);
  EXAMPLE(null IS 1);
  EXAMPLE(null IS null, "-- Unknown is Unknown? Yes it is!");
  EXAMPLE("x" IS "x");
  _("");


  _("### x IS NOT y is the same as NOT (x IS y)\n");
  EXAMPLE(1 IS NOT 1);
  EXAMPLE(2 IS NOT 1);
  EXAMPLE(null IS NOT 1);
  EXAMPLE(null IS NOT null);
  EXAMPLE("x" IS NOT "x");
  _("");


  DECLARE _null bool; SET _null := NULL; -- CQL0373: comparing against NULL always yields NULL; use IS and IS NOT instead
  _("### Inequality is != or <>\n");
  EXAMPLE(1 != 1);
  EXAMPLE(2 <> 1);
  EXAMPLE(_null != 1);
  EXAMPLE(_null <> _null);
  _("");


  _("### More comparisons\n");
  EXAMPLE(1 < 10);
  EXAMPLE(1 > 10);
  EXAMPLE(2 <= 2);
  EXAMPLE(2 >= 2);
  EXAMPLE(10 < null);
  _("");


  _("### To test if a value is in a range\n");
  EXAMPLE(1 < 2 and 2 < 3);
  EXAMPLE(2 < 3 and 3 < 2);
  _("");


  _("### BETWEEN makes this look nicer\n");
  EXAMPLE(2 between 1 and 3);
  EXAMPLE(3 between 2 and 2);
  _("");


  _("### Strings are created with \"x\" or 'x'\n");
  EXAMPLE("This\nis a string.",            "-- can have C style escapes; no embedded nulls");
  EXAMPLE("\"Th\\x69s\\nis a string.\"",   "-- even hex literals");
  EXAMPLE('This\nisn''t a C style string', "-- use '' to escape single quote ONLY");
END;

create procedure chapter_2 ()
begin
  _("## CHAPTER 2 — Simple Variables\n");

  _("### Variables are declared with DECLARE\n");
  declare x integer not null;
  set X := 123;
  EXAMPLE(X, "-- Keywords and identifiers are not case sensitive"); 
  EXAMPLE(x, "-- x is the same as X");
  _("");


  _("### All variables begin with a null value if allowed, else a zero value\n");
  declare y integer not null;
  if y == 0 then
    EXAMPLE(y, "-- Yes, this will run.");
  end if;
  _("");


  _("### A nullable variable (i.e. not marked with not null) is initialized to null\n");
  declare z real;
  if z is null then
    EXAMPLE(z, "-- Yes, this will run.");
  end if;
  _("");


  _("### The various types\n");
  declare a_real real;       EXAMPLE(a_real, '-- null real');
  declare an_int integer;    EXAMPLE(an_int, '-- null integer');
  declare a_long long;       EXAMPLE(a_long, '-- null long');
  declare a_string text;     EXAMPLE(a_string, "-- string is null, EXAMPLE() is not good enough");
  -- declare an_object object;  EXAMPLE(an_object, "-- object is null, EXAMPLE() is not good enough");
  declare a_blob blob;       EXAMPLE(a_blob, "-- blob is null, EXAMPLE() is not good enough");
  _("");


  _("### There are some typical SQL synonyms\n");
  declare an_int_bis int;             EXAMPLE(an_int_bis);
  declare a_long_bis_1 long integer;  EXAMPLE(a_long_bis_1);
  declare a_long_bis_2 long int;      EXAMPLE(a_long_bis_2);
  declare a_long_bis_3 long_int;      EXAMPLE(a_long_bis_3);
  _("");


  _("### The basic types can be tagged to make them less miscible\n");
  declare m real<meters>;
  declare kg real<kilos>;
  -- set m := kg; --Uncomment to witness the following error:
  -- error: in str : CQL0070: expressions of different kinds cannot be mixed: `meters` vs. `kilos`
  _("");


  _("### Object variables can also be tagged so that they are not mixed-up easily\n");
  declare dict object<dict> not null;
  declare list object<list> not null;
  -- @TODO: Create create_dict create_list
  -- set dict := create_dict();  -- an external function that creates a dict
  -- set dict := create_list();  -- error
  -- set list := create_list();  -- ok
  -- set list := dict;           -- error
  _("");


  _("### Implied type initialization\n");
  let int_not_null    := 1;
  let long_not_null   := 1L;
  let text_not_null   := "x";
  EXAMPLE(int_not_null,  "-- integer NOT NULL");
  EXAMPLE(long_not_null, "-- long NOT NULL");
  EXAMPLE(text_not_null, "-- text NOT NULL");


  let _int_not_null := 123;
  declare _int_null integer;

  let bool_IS_1 := _int_not_null IS _int_not_null;
  let bool_IS_2 := _int_not_null IS _int_null;
  EXAMPLE(bool_IS_1, "-- `IS` never returns `NULL`");
  EXAMPLE(bool_IS_2, "-- `IS` never returns `NULL`");

  let bool_EQ_1 := _int_not_null =  _int_not_null; --, `=` returns `NULL` if either side is `NULL`
  let bool_EQ_2 := _int_not_null =  _int_null;     --, `=` returns `NULL` if either side is `NULL`
  EXAMPLE(bool_EQ_1, "-- (NOT NULL = NOT NULL) -> NOT NULL");
  EXAMPLE(bool_EQ_2, "-- (NOT NULL = NULL) -> NULL");

  -- The psuedo function "nullable" converts the type of its arg to the nullable
  -- version of the same thing.

  let n_i := nullable(1);   -- nullable integer variable initialized to 1
  let l_i := nullable(1L);  -- nullable long variable initialized to 1
END;

create procedure chapter_3 ()
begin
  _("## CHAPTER 3 — Control Flow\n");


  _("### IF statement\n");
  let some_var := 5;
  if some_var > 10 then
    _("some_var is totally bigger than 10.");
  else if some_var < 10 then -- else if block is optional
    _("some_var is smaller than 10.");
  else -- else block is optional
    _("some_var is indeed 10.");
  end if;
  _("");


  _("### WHILE loops iterate as usual\n");
  declare i integer not null;
  set i := 0;
  while i < 5
  begin
    _("i %d", i);
    set i := i + 1;
  end;
  _("");


  _("### Use LEAVE to end a loop early\n");
  declare j integer not null;
  set j := 0;
  while j < 500
  begin
    if j >= 5 then
      -- we are not going to get anywhere near 500
      leave;
    end if;

    _("j %d", j);
    set j := j + 1;
  end;
  _("");


  _("### Use CONTINUE to go back to the loop test\n");
  declare k integer not null;
  set k := 0;
  while k < 42
  begin
     set k := k + 1;
     if k % 2 then
       -- Note: we to do this after "k" is incremented!
       -- to avoid an infinite loop
       continue;
     end if;

     -- odd numbers will not be printed because of continue above
     _("k %d", k);
  end;
END;

create procedure chapter_4 ()
begin
  _("## CHAPTER 4 — Complex Expression Forms");

  _('Case is an expression, so it is more like the C "?:" operator than a switch statement. It is like "?:" on steroids.');

  _("### Case statement\n");
  let a := 1;
  call printf(
    case a              -- a switch expression is optional
      when 1 then "one" -- one or more cases
      when 2 then "two"
      else "other"      -- else is optional
    end
  );
  _("");


  _("### Case with no common expression is a series of independent tests\n");
  let b := 2;
  let c := 3;
  call printf(
    case
      when b == 3 then "b = one"   -- booleans could be completely unrelated
      when c == 3 then "c = two"   -- first match wins
      else "other"
    end
  );
  _("");


  -- If nothing matches the cases, the result is null.
  -- The following expression yields null because 7 is not 1.
  -- @TODO: BUG
  -- call printf("3) (case 7 when 1 then \"one\" end) --> %s\n", (case 7 when 1 then "one" end));
  -- _("");


  _("### Case is just an expression, so it can nest\n");
  let d := 4;
  let e := 5;
  let f := 6;
  call printf((
    case d
      when 4 THEN
        case e
          when 5 THEN "d:4 e:5"
          else "d:4 e:other"
      end
    else
      case
        when f = 6 THEN "d:other f:6"
        else "d:other f:other"
      end
    end
  ));
  _("");


  _("### IN is used to test for membership\n");
  EXAMPLE(5 IN (1, 2, 3, 4, 5));
  EXAMPLE(7 IN (1, 2));
  EXAMPLE(null in (1, 2, 3));
  EXAMPLE(null in (1, null, 3));
  EXAMPLE(7 NOT IN (1, 2));
  EXAMPLE(null not in (null, 3));
  _("");
END;

create procedure chapter_5 ()
begin
  _("## CHAPTER 5 — Working with and \"getting rid of\" nulls\n");
  _("Null can be annoying, you might need a not null value.\n");

  declare _null integer;
  set _null := null;


  _("### In most operations null is radioactive:\n");
  EXAMPLE(null + 1);
  EXAMPLE(null * 1);
  EXAMPLE(_null == _null);
  _("");


  _("### IS and IS NOT always return 0 or 1:\n");
  EXAMPLE(null IS 1);
  EXAMPLE(1 IS NOT _null);
  _("");


  _("### COALESCE returns the first non null arg, or the last arg if all were null.\n");
  _("If the last arg is not null, you get a non null result for sure.");
  _("The following is never null, but it's false if either x or y is null");
  EXAMPLE(COALESCE(1==_null, false));
  -- COALESCE(x==y, false) -> thought excercise: how is this different than x IS y?
  _("");


  _("### IFNULL is coalesce with 2 args only (COALESCE is more general)\n");
  EXAMPLE(IFNULL(_null, -1), "-- use -1 if x is null");
  _("");


  _("### The reverse, NULLIF, converts a sentinel value to unknown, more exotic\n");
  -- EXAMPLE(NULLIF(_null, -1), "if _null is -1 then use null"); -- error: in call : CQL0080: function may not appear in this context 'NULLIF'
  _("");


  _("### The else part of a case can get rid of nulls\n");
  EXAMPLE(case when 1 == 2 then 1 else 0 end, "    -- true if y = z and neither is null");
  EXAMPLE(case when 2 == 2 then 1 else 0 end, "    -- true if y = z and neither is null");
  EXAMPLE(case when 2 == _null then 1 else 0 end, "-- true if y = z and neither is null");
  _("");


  _("### `case` can be used to give you a default value after various tests\n");
  EXAMPLE((case when _null > 0 then "pos" when _null < 0 then "neg" else "other" end), "-- never null, \"other\" is returned if _null is null");
  _("");


  _('### You can "throw" out of the current procedure (see exceptions below)');
  begin try
    let y := ifnull_throw(_null);
  end try;
  begin catch
    call printf("CATCH: _null is null\n");
  end catch;
  _("");


  _("### Conditions improves type to \"not null\" by the control flow analysis\n");
  _('Many common check patterns are recognized.');
  if _null is not null then
    -- _null is known to be not null in this context
  end if;
  _("");
END;


create procedure chapter_6 ()
begin
  _("## CHAPTER 6 — Tables, Views, Indices, Triggers\n");

  _("Most forms of data definition language DDL are supported.");
  _("\"Loose\" DDL (outside of any procedure) simply declares");
  _("schema, it does not actually create it; the schema is assumed to");
  _("exist as you specified.");

  _("");

  _("CQL can take a series of schema declarations (DDL) and");
  _("automatically create a procedure that will materialize");
  _("that schema and even upgrade previous versions of the schema.");
  _("This system is discussed in Chapter 10 of The Guide.");

  _("### Create Tables\n");
  create table T1(
    id integer primary key,
    t text,
    r real
  );

  create table T2(
    id integer primary key references T1(id),
    l long,
    b blob
  );

  _("### Create Views\n");
  create view V1 as select * from T1;

  _("### Create Triggers\n");
  create trigger if not exists trigger1
    before delete on T1
  begin
    delete from T2 where id = old.id;
  end;

  _("### Create Indexes\n");
  create index I1 on T1(t);
  create index I2 on T1(r);

  _("### The various drop forms are supported\n");
  drop index I1;
  drop index I2;
  drop view V1;
  drop table T2;
  drop table T1;

  _("A complete discussion of DDL is out of scope, refer to sqlite.org");
END;

create procedure chapter_7 ()
begin
  _("## CHAPTER 7 — Selecting Data\n");

  _("### CQL is a two-headed language\n");
  EXAMPLE(1+1, "-- this is evaluated in generated C code");
  EXAMPLE(select 1+1, "-- this expresion goes to SQLite; SQLite does the addition");
  _("");


  _("CQL tries to do most things the same as SQLite in the C context");
  _("but some things are exceedingly hard to emulate correctly.");
  _("Even simple looking things such as:\n");
  EXAMPLE(select cast("1.23" as real));
  ERROR(cast("1.23" as real), "-- not safe to emulate SQLite");
  _("");


  _("In general, numeric/text conversions have to happen in SQLite context");
  _("because the specific library that does the conversion could be and usually");
  _("is different than the one CQL would use. It would not do to give different answers");
  _("in one context or another so those conversions are simply not supported.");
  _("");


  _("Loose concatenation is not supported because of the implied conversions:");
  _("(Loose means: not in the context of a SQL statement)\n");
  EXAMPLE(select cast("100"||1.23 as real));  --> 1001.23 (a number)
  ERROR(cast("100"||1.23 as real), "-- concat not supported in loose expr");
  _("");


  _("### Use IF NOTHING forms to handle no rows or null\n");
  create table T1(id integer primary key, t text, r real);
  insert into T1 values (1, "foo", 3.14);
  declare _null integer;

  EXAMPLE(select r from T1 where id = 1);
  EXAMPLE(select r from T1 where id = 2 if nothing -1);
  EXAMPLE(select _null from T1 where id = 1 if nothing -1);
  EXAMPLE(select _null from T1 where id = 1 if nothing or null -1);
  _("");
  ERROR(select r from T1 where id = 2, "-- This throws an exception");
  ERROR(select r from T1 where id = 2 if nothing throw, "-- Merely makes it explicit");
  _("");
END;

create procedure chapter_8 ()
begin
  _("## CHAPTER 8 — Procedures, Results, Exceptions\n");

  _("TODO");
END;

create procedure chapter_9 ()
begin
  _("## CHAPTER 9 — Statement Cursors\n");

  _("TODO");
END;

create procedure chapter_10 ()
begin
  _("## CHAPTER 10 — Value Cursors, Out, and Out Union\n");

  _("TODO");
END;

create procedure chapter_11  ()
begin
  _("## CHAPTER 11 — Named Types and Enumerations\n");

  _("TODO");
END;

create procedure chapter_12 ()
begin
  _("## CHAPTER 12 — Shapes and Their Uses\n");

  _("TODO");
END;

create procedure chapter_13 ()
begin
  _("## CHAPTER 13 — INSERT USING and FETCH USING\n");

  _("TODO");
END;

create proc entrypoint ()
begin
  _("# CQL IN 20 MINUTES");
  _("");

  call chapter_1();

  _("\n\n___\n");

  call chapter_2();

  _("\n\n___\n");

  call chapter_3();

  _("\n\n___\n");

  call chapter_4();

  _("\n\n___\n");

  call chapter_5();

  _("\n\n___\n");

  call chapter_6();

  _("\n\n___\n");

  call chapter_7();

  -- _("\n\n___\n");

  -- call chapter_8();

  -- _("\n\n___\n");

  -- call chapter_9();

  -- _("\n\n___\n");

  -- call chapter_10();

  -- _("\n\n___\n");

  -- call chapter_11();

  -- _("\n\n___\n");

  -- call chapter_12();

  -- _("\n\n___\n");
  
  -- call chapter_13();

  _("If you've read this far you know more than most now.  :)");
END;
