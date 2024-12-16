%{

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <stdio.h>

int yywrap(void) {
  // no further input
  return 1;
}

int yylex(void);

int main(int argc, char **argv) {
  while (yylex()) ;
}

void put_quoted(const char *s) {
  printf("\"%s\"", s);
}

%}

%%

%prec[ ]UMINUS[ ]                     { /* gobble */ }
%prec[ ]BETWEEN[ ]                    { /* gobble */ }
[ ][ ]*$                              { /* gobble */ }

ABORT                                 { put_quoted("ABORT"); }
ACTION                                { put_quoted("ACTION"); }
ADD                                   { put_quoted("ADD"); }
AFTER                                 { put_quoted("AFTER"); }
ALL                                   { put_quoted("ALL"); }
ALTER                                 { put_quoted("ALTER"); }
AND                                   { put_quoted("AND"); }
ARGUMENTS                             { put_quoted("ARGUMENTS"); }
AS                                    { put_quoted("AS"); }
ASC                                   { put_quoted("ASC"); }
AT_ATTRIBUTE                          { put_quoted("@ATTRIBUTE"); }
AT_BEGIN_SCHEMA_REGION                { put_quoted("@BEGIN_SCHEMA_REGION"); }
AT_COLUMNS                            { put_quoted("@COLUMNS"); }
AT_CREATE                             { put_quoted("@CREATE"); }
AT_DECLARE_DEPLOYABLE_REGION          { put_quoted("@DECLARE_DEPLOYABLE_REGION"); }
AT_DECLARE_SCHEMA_REGION              { put_quoted("@DECLARE_SCHEMA_REGION"); }
AT_DELETE                             { put_quoted("@DELETE"); }
AT_DUMMY_DEFAULTS                     { put_quoted("@DUMMY_DEFAULTS"); }
AT_DUMMY_NULLABLES                    { put_quoted("@DUMMY_NULLABLES"); }
AT_DUMMY_SEED                         { put_quoted("@DUMMY_SEED"); }
AT_ECHO                               { put_quoted("@ECHO"); }
AT_ELSE                               { put_quoted("@ELSE"); }
AT_EMIT_CONSTANTS                     { put_quoted("@EMIT_CONSTANTS"); }
AT_EMIT_ENUMS                         { put_quoted("@EMIT_ENUMS"); }
AT_EMIT_GROUP                         { put_quoted("@EMIT_GROUP"); }
AT_ENDIF                              { put_quoted("@ENDIF"); }
AT_END_SCHEMA_REGION                  { put_quoted("@END_SCHEMA_REGION"); }
AT_ENFORCE_NORMAL                     { put_quoted("@ENFORCE_NORMAL"); }
AT_ENFORCE_POP                        { put_quoted("@ENFORCE_POP"); }
AT_ENFORCE_PUSH                       { put_quoted("@ENFORCE_PUSH"); }
AT_ENFORCE_RESET                      { put_quoted("@ENFORCE_RESET"); }
AT_ENFORCE_STRICT                     { put_quoted("@ENFORCE_STRICT"); }
AT_EPONYMOUS                          { put_quoted("@EPONYMOUS"); }
AT_FILE                               { put_quoted("@FILE"); }
AT_ID                                 { put_quoted("@ID"); }
AT_IFDEF                              { put_quoted("@IFDEF"); }
AT_IFNDEF                             { put_quoted("@IFNDEF"); }
AT_KEEP_TABLE_NAME_IN_ALIASES         { put_quoted("@KEEP_TABLE_NAME_IN_ALIASES"); }
AT_LINE                               { put_quoted("@LINE"); }
AT_MACRO                              { put_quoted("@MACRO"); }
AT_MACRO_FILE                         { put_quoted("@MACRO_FILE"); }
AT_MACRO_LINE                         { put_quoted("@MACRO_LINE"); }
AT_OP                                 { put_quoted("@OP"); }
AT_PREVIOUS_SCHEMA                    { put_quoted("@PREVIOUS_SCHEMA"); }
AT_PROC                               { put_quoted("@PROC"); }
AT_RC                                 { put_quoted("@RC"); }
AT_RECREATE                           { put_quoted("@RECREATE"); }
AT_SCHEMA_AD_HOC_MIGRATION            { put_quoted("@SCHEMA_AD_HOC_MIGRATION"); }
AT_SCHEMA_UPGRADE_SCRIPT              { put_quoted("@SCHEMA_UPGRADE_SCRIPT"); }
AT_SCHEMA_UPGRADE_VERSION             { put_quoted("@SCHEMA_UPGRADE_VERSION"); }
AT_SENSITIVE                          { put_quoted("@SENSITIVE"); }
AT_TEXT                               { put_quoted("@TEXT"); }
AT_TMP                                { put_quoted("@TMP"); }
AT_UNSUB                              { put_quoted("@UNSUB"); }
AUTOINCREMENT                         { put_quoted("AUTOINCREMENT"); }
BEFORE                                { put_quoted("BEFORE"); }
BEGIN_                                { put_quoted("BEGIN"); }
BEGIN_INCLUDE                         { put_quoted("@INCLUDE quoted-filename"); }
BETWEEN                               { put_quoted("BETWEEN"); }
BLOB                                  { put_quoted("BLOB"); }
BLOBLIT                               { put_quoted("sql-blob-literal"); }
BOOL_                                 { put_quoted("BOOL"); }
BY                                    { put_quoted("BY"); }
CALL                                  { put_quoted("CALL"); }
CASCADE                               { put_quoted("CASCADE"); }
CASE                                  { put_quoted("CASE"); }
CAST                                  { put_quoted("CAST"); }
CATCH                                 { put_quoted("CATCH"); }
CHECK                                 { put_quoted("CHECK"); }
CLOSE                                 { put_quoted("CLOSE"); }
COLLATE                               { put_quoted("COLLATE"); }
COLUMN                                { put_quoted("COLUMN"); }
COLUMNS                               { put_quoted("COLUMNS"); }
COMMIT                                { put_quoted("COMMIT"); }
CONST                                 { put_quoted("CONST"); }
CONSTRAINT                            { put_quoted("CONSTRAINT"); }
CONTEXT_COLUMN                        { put_quoted("CONTEXT COLUMN"); }
CONTEXT_TYPE                          { put_quoted("CONTEXT TYPE"); }
CONTINUE                              { put_quoted("CONTINUE"); }
CREATE                                { put_quoted("CREATE"); }
CROSS                                 { put_quoted("CROSS"); }
CSTRLIT                               { put_quoted("c-string-literal"); }
CTE_TABLES                            { put_quoted("CTE_TABLES"); }
CTE_TABLES_MACRO                      { put_quoted("ID!"); }
CURRENT_ROW                           { put_quoted("CURRENT ROW"); }
CURSOR                                { put_quoted("CURSOR"); }
CURSOR_HAS_ROW                        { put_quoted("CURSOR HAS ROW"); }
DECLARE                               { put_quoted("DECLARE"); }
DEFAULT                               { put_quoted("DEFAULT"); }
DEFERRABLE                            { put_quoted("DEFERRABLE"); }
DEFERRED                              { put_quoted("DEFERRED"); }
DELETE                                { put_quoted("DELETE"); }
DESC                                  { put_quoted("DESC"); }
DISTINCT                              { put_quoted("DISTINCT"); }
DISTINCTROW                           { put_quoted("DISTINCTROW"); }
DO                                    { put_quoted("DO"); }
DROP                                  { put_quoted("DROP"); }
ELSE                                  { put_quoted("ELSE"); }
ELSE_IF                               { put_quoted("ELSE IF"); }
ENCODE                                { put_quoted("ENCODE"); }
END                                   { put_quoted("END"); }
END_INCLUDE                           { put_quoted("end of included file"); }
ENUM                                  { put_quoted("ENUM"); }
EXCEPT                                { put_quoted("EXCEPT"); }
EXCLUDE_CURRENT_ROW                   { put_quoted("EXCLUDE CURRENT ROW"); }
EXCLUDE_GROUP                         { put_quoted("EXCLUDE GROUP"); }
EXCLUDE_NO_OTHERS                     { put_quoted("EXCLUDE NO OTHERS"); }
EXCLUDE_TIES                          { put_quoted("EXCLUDE TIES"); }
EXCLUSIVE                             { put_quoted("EXCLUSIVE"); }
EXISTS                                { put_quoted("EXISTS"); }
EXPLAIN                               { put_quoted("EXPLAIN"); }
EXPR                                  { put_quoted("EXPR"); }
EXPR_MACRO                            { put_quoted("ID!"); }
FAIL                                  { put_quoted("FAIL"); }
FALSE_                                { put_quoted("FALSE"); }
FCOUNT                                { put_quoted("FCOUNT"); }
FETCH                                 { put_quoted("FETCH"); }
FILTER                                { put_quoted("FILTER"); }
FIRST                                 { put_quoted("FIRST"); }
FOLLOWING                             { put_quoted("FOLLOWING"); }
FOR                                   { put_quoted("FOR"); }
FOREIGN                               { put_quoted("FOREIGN"); }
FOR_EACH_ROW                          { put_quoted("FOR EACH ROW"); }
FROM                                  { put_quoted("FROM"); }
FROM_BLOB                             { put_quoted("FROM BLOB"); }
FUNC                                  { put_quoted("FUNC"); }
FUNCTION                              { put_quoted("FUNCTION"); }
GLOB                                  { put_quoted("GLOB"); }
GROUP                                 { put_quoted("GROUP"); }
GROUPS                                { put_quoted("GROUPS"); }
HAVING                                { put_quoted("HAVING"); }
HIDDEN                                { put_quoted("HIDDEN"); }
ID                                    { put_quoted("ID"); }
IF                                    { put_quoted("IF"); }
IGNORE                                { put_quoted("IGNORE"); }
IMMEDIATE                             { put_quoted("IMMEDIATE"); }
IN                                    { put_quoted("IN"); }
INDEX                                 { put_quoted("INDEX"); }
INITIALLY                             { put_quoted("INITIALLY"); }
INNER                                 { put_quoted("INNER"); }
INOUT                                 { put_quoted("INOUT"); }
INSERT                                { put_quoted("INSERT"); }
INSTEAD                               { put_quoted("INSTEAD"); }
INTEGER                               { put_quoted("INTEGER"); }
INTERFACE                             { put_quoted("INTERFACE"); }
INTERSECT                             { put_quoted("INTERSECT"); }
INTLIT                                { put_quoted("integer-literal"); }
INTO                                  { put_quoted("INTO"); }
INT_                                  { put_quoted("INT"); }
IS                                    { put_quoted("IS"); }
ISNULL                                { put_quoted("ISNULL"); }
IS_FALSE                              { put_quoted("IS FALSE"); }
IS_NOT                                { put_quoted("IS NOT"); }
IS_NOT_FALSE                          { put_quoted("IS NOT FALSE"); }
IS_NOT_TRUE                           { put_quoted("IS NOT TRUE"); }
IS_TRUE                               { put_quoted("IS TRUE"); }
JOIN                                  { put_quoted("JOIN"); }
KEY                                   { put_quoted("KEY"); }
LAST                                  { put_quoted("LAST"); }
LEAVE                                 { put_quoted("LEAVE"); }
LEFT                                  { put_quoted("LEFT"); }
LET                                   { put_quoted("LET"); }
LIKE                                  { put_quoted("LIKE"); }
LIMIT                                 { put_quoted("LIMIT"); }
LONGLIT                               { put_quoted("long-literal"); }
LONG_                                 { put_quoted("LONG"); }
LONG_INT                              { put_quoted("LONG_INT"); }
LONG_INTEGER                          { put_quoted("LONG_INTEGER"); }
LOOP                                  { put_quoted("LOOP"); }
MATCH                                 { put_quoted("MATCH"); }
NO                                    { put_quoted("NO"); }
NOT                                   { put_quoted("NOT"); }
NOTHING                               { put_quoted("NOTHING"); }
NOTNULL                               { put_quoted("NOTNULL"); }
NOT_BETWEEN                           { put_quoted("NOT BETWEEN"); }
NOT_DEFERRABLE                        { put_quoted("NOT DEFERRABLE"); }
NOT_GLOB                              { put_quoted("NOT GLOB"); }
NOT_IN                                { put_quoted("NOT IN"); }
NOT_LIKE                              { put_quoted("NOT LIKE"); }
NOT_MATCH                             { put_quoted("NOT MATCH"); }
NOT_REGEXP                            { put_quoted("NOT REGEXP"); }
NULLS                                 { put_quoted("NULLS"); }
NULL_                                 { put_quoted("NULL"); }
OBJECT                                { put_quoted("OBJECT"); }
OF                                    { put_quoted("OF"); }
OFFSET                                { put_quoted("OFFSET"); }
ON                                    { put_quoted("ON"); }
ON_CONFLICT                           { put_quoted("ON CONFLICT"); }
OPEN                                  { put_quoted("OPEN"); }
OR                                    { put_quoted("OR"); }
ORDER                                 { put_quoted("ORDER"); }
OUT                                   { put_quoted("OUT"); }
OUTER                                 { put_quoted("OUTER"); }
OVER                                  { put_quoted("OVER"); }
PARTITION                             { put_quoted("PARTITION"); }
PRECEDING                             { put_quoted("PRECEDING"); }
PRIMARY                               { put_quoted("PRIMARY"); }
PRIVATE                               { put_quoted("PRIVATE"); }
PROC                                  { put_quoted("PROC"); }
PROCEDURE                             { put_quoted("PROCEDURE"); }
QID                                   { put_quoted("`quoted identifier`"); }
QUERY_PARTS                           { put_quoted("QUERY_PARTS"); }
QUERY_PARTS_MACRO                     { put_quoted("ID!"); }
QUERY_PLAN                            { put_quoted("QUERY PLAN"); }
RAISE                                 { put_quoted("RAISE"); }
RANGE                                 { put_quoted("RANGE"); }
REAL                                  { put_quoted("REAL"); }
REALLIT                               { put_quoted("real-literal"); }
RECURSIVE                             { put_quoted("RECURSIVE"); }
REFERENCES                            { put_quoted("REFERENCES"); }
REGEXP                                { put_quoted("REGEXP"); }
RELEASE                               { put_quoted("RELEASE"); }
RENAME                                { put_quoted("RENAME"); }
REPLACE                               { put_quoted("REPLACE"); }
RESTRICT                              { put_quoted("RESTRICT"); }
RETURN                                { put_quoted("RETURN"); }
RIGHT                                 { put_quoted("RIGHT"); }
ROLLBACK                              { put_quoted("ROLLBACK"); }
ROWID                                 { put_quoted("ROWID"); }
ROWS                                  { put_quoted("ROWS"); }
SAVEPOINT                             { put_quoted("SAVEPOINT"); }
SELECT                                { put_quoted("SELECT"); }
SELECT_CORE                           { put_quoted("SELECT_CORE"); }
SELECT_CORE_MACRO                     { put_quoted("ID!"); }
SELECT_EXPR                           { put_quoted("SELECT_EXPR"); }
SELECT_EXPR_MACRO                     { put_quoted("ID!"); }
SELECT_LIST_MACRO                     { put_quoted("ID!"); }
SET                                   { put_quoted("SET"); }
SIGN_FUNCTION                         { put_quoted("SIGN FUNCTION"); }
STATEMENT                             { put_quoted("STATEMENT"); }
STMT_LIST                             { put_quoted("STMT_LIST"); }
STMT_LIST_MACRO                       { put_quoted("ID!"); }
STRLIT                                { put_quoted("sql-string-literal"); }
SWITCH                                { put_quoted("SWITCH"); }
TABLE                                 { put_quoted("TABLE"); }
TEMP                                  { put_quoted("TEMP"); }
TEXT                                  { put_quoted("TEXT"); }
THEN                                  { put_quoted("THEN"); }
THROW                                 { put_quoted("THROW"); }
TO                                    { put_quoted("TO"); }
TRANSACTION                           { put_quoted("TRANSACTION"); }
TRIGGER                               { put_quoted("TRIGGER"); }
TRUE_                                 { put_quoted("TRUE"); }
TRY                                   { put_quoted("TRY"); }
TYPE                                  { put_quoted("TYPE"); }
TYPE_CHECK                            { put_quoted("TYPE_CHECK"); }
UMINUS                                { put_quoted("UMINUS"); }
UNBOUNDED                             { put_quoted("UNBOUNDED"); }
UNION                                 { put_quoted("UNION"); }
UNION_ALL                             { put_quoted("UNION ALL"); }
UNIQUE                                { put_quoted("UNIQUE"); }
UPDATE                                { put_quoted("UPDATE"); }
UPSERT                                { put_quoted("UPSERT"); }
USING                                 { put_quoted("USING"); }
VALUES                                { put_quoted("VALUES"); }
VAR                                   { put_quoted("VAR"); }
VIEW                                  { put_quoted("VIEW"); }
VIRTUAL                               { put_quoted("VIRTUAL"); }
WHEN                                  { put_quoted("WHEN"); }
WHERE                                 { put_quoted("WHERE"); }
WHILE                                 { put_quoted("WHILE"); }
WINDOW                                { put_quoted("WINDOW"); }
WITH                                  { put_quoted("WITH"); }
WITHOUT                               { put_quoted("WITHOUT"); }

  /* two character operators */

ADD_EQ                                { put_quoted("+="); }
AND_EQ                                { put_quoted("&="); }
ASSIGN                                { put_quoted(":="); }
CONCAT                                { put_quoted("||"); }
DIV_EQ                                { put_quoted("/="); }
EQEQ                                  { put_quoted("=="); }
GE                                    { put_quoted(">="); }
JEX1                                  { put_quoted("->"); }
JEX2                                  { put_quoted("->>"); }
LE                                    { put_quoted("<="); }
LS                                    { put_quoted("<<"); }
LS_EQ                                 { put_quoted("<<="); }
MOD_EQ                                { put_quoted("%="); }
MUL_EQ                                { put_quoted("*="); }
NE                                    { put_quoted("<>"); }
NE_                                   { put_quoted("!="); }
OR_EQ                                 { put_quoted("|="); }
RS                                    { put_quoted(">>"); }
RS_EQ                                 { put_quoted(">>="); }
SUB_EQ                                { put_quoted("-="); }

  /*  passthrough normalized grammar rule operator */

::=                                   { printf("::="); }

  /* simple single quote and passthrough */

.                                     { putc(*yytext, stdout); }
'.'                                   { printf("'%c'", yytext[1]); }

[a-zA-Z_][a-zA-Z_0-9]*                { printf("%s", yytext); }

