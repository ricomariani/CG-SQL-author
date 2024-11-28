CREATE TABLE t(cql TEXT, dummy, sqlite TEXT GENERATED ALWAYS AS (typeof(dummy)) VIRTUAL);
INSERT INTO t(cql, dummy) VALUES
  ("bool", 1),
  ("real", 3.14),
  ("integer", 1234),
  ("long", 1234567890123456789),
  ("text", 'HW'),
  ("blob", (select CAST("blob" as blob))),
  ("object", 123),
  ("null", NULL)
;

-- Example from ./README.md
SELECT hello_world(); -- Expect Result

-- Nullables as null
SELECT comprehensive_test(
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "null"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob"),
  (SELECT t.dummy FROM t WHERE t.cql = "null")
) as out; -- Expect RESULT

-- Nullables as non null
SELECT comprehensive_test(
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob"),
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "bool"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "real"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "integer"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "long"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "text"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob"),
  (SELECT t.dummy FROM t WHERE t.cql = "blob")
) as out; -- Expect RESULT

-- Nullables as null
SELECT
  in__bool__not_null((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__not_null,
  in__bool__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) bool__nullable,
  in__real__not_null((SELECT t.dummy FROM t WHERE t.cql = "real")) real__not_null,
  in__real__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) real__nullable,
  in__integer__not_null((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__not_null,
  in__integer__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) integer__nullable,
  in__long__not_null((SELECT t.dummy FROM t WHERE t.cql = "long")) long__not_null,
  in__long__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) long__nullable,
  in__text__not_null((SELECT t.dummy FROM t WHERE t.cql = "text")) text__not_null,
  in__text__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) text__nullable,
  in__blob__not_null((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__not_null,
  in__blob__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) blob__nullable
; -- Expect RESULT

-- Nullables as non null
SELECT
  in__bool__not_null((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__not_null,
  in__bool__nullable((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__nullable,
  in__real__not_null((SELECT t.dummy FROM t WHERE t.cql = "real")) real__not_null,
  in__real__nullable((SELECT t.dummy FROM t WHERE t.cql = "real")) real__nullable,
  in__integer__not_null((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__not_null,
  in__integer__nullable((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__nullable,
  in__long__not_null((SELECT t.dummy FROM t WHERE t.cql = "long")) long__not_null,
  in__long__nullable((SELECT t.dummy FROM t WHERE t.cql = "long")) long__nullable,
  in__text__not_null((SELECT t.dummy FROM t WHERE t.cql = "text")) text__not_null,
  in__text__nullable((SELECT t.dummy FROM t WHERE t.cql = "text")) text__nullable,
  in__blob__not_null((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__not_null,
  in__blob__nullable((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__nullable
; -- Expect RESULT

-- Nullables as null
SELECT
  inout__bool__not_null((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__not_null,
  inout__bool__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) bool__nullable,
  inout__real__not_null((SELECT t.dummy FROM t WHERE t.cql = "real")) real__not_null,
  inout__real__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) real__nullable,
  inout__integer__not_null((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__not_null,
  inout__integer__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) integer__nullable,
  inout__long__not_null((SELECT t.dummy FROM t WHERE t.cql = "long")) long__not_null,
  inout__long__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) long__nullable,
  inout__text__not_null((SELECT t.dummy FROM t WHERE t.cql = "text")) text__not_null,
  inout__text__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) text__nullable,
  inout__blob__not_null((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__not_null,
  inout__blob__nullable((SELECT t.dummy FROM t WHERE t.cql = "null")) blob__nullable
; -- Expect RESULT

-- Nullables as null
SELECT
  inout__bool__not_null((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__not_null,
  inout__bool__nullable((SELECT t.dummy FROM t WHERE t.cql = "bool")) bool__nullable,
  inout__real__not_null((SELECT t.dummy FROM t WHERE t.cql = "real")) real__not_null,
  inout__real__nullable((SELECT t.dummy FROM t WHERE t.cql = "real")) real__nullable,
  inout__integer__not_null((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__not_null,
  inout__integer__nullable((SELECT t.dummy FROM t WHERE t.cql = "integer")) integer__nullable,
  inout__long__not_null((SELECT t.dummy FROM t WHERE t.cql = "long")) long__not_null,
  inout__long__nullable((SELECT t.dummy FROM t WHERE t.cql = "long")) long__nullable,
  inout__text__not_null((SELECT t.dummy FROM t WHERE t.cql = "text")) text__not_null,
  inout__text__nullable((SELECT t.dummy FROM t WHERE t.cql = "text")) text__nullable,
  inout__blob__not_null((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__not_null,
  inout__blob__nullable((SELECT t.dummy FROM t WHERE t.cql = "blob")) blob__nullable
; -- Expect RESULT

SELECT
  out__bool__not_null() bool__not_null,
  out__bool__nullable() bool__nullable,
  out__real__not_null() real__not_null,
  out__real__nullable() real__nullable,
  out__integer__not_null() integer__not_null,
  out__integer__nullable() integer__nullable,
  out__long__not_null() long__not_null,
  out__long__nullable() long__nullable,
  out__text__not_null() text__not_null,
  out__text__nullable() text__nullable,
  out__blob__not_null() blob__not_null,
  out__blob__nullable() blob__nullable
; -- Expect RESULT

SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect RESULT
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
SELECT result_from_inout(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR


SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__bool__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__bool__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT


SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect RESULT
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__real__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect RESULT
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__real__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT


SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__integer__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__integer__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT


SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__long__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect RESULT
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect RESULT
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect RESULT
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect RESULT
SELECT inout__long__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT


SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect RESULT
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
SELECT inout__text__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect RESULT
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
SELECT inout__text__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT


SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect RESULT
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
SELECT inout__blob__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR

SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect RESULT
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
SELECT inout__blob__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect RESULT

-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
-- SELECT inout__object__not_null(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR
--
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "bool"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "integer"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "long"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "real"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "text"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "blob"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "object"; -- Expect ERROR
-- SELECT inout__object__nullable(t.dummy) output, t.* FROM t WHERE t.cql = "null"; -- Expect ERROR
