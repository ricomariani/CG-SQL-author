%option noyywrap nodefault yylineno case-insensitive never-interactive

%x at_inc
%x skipping
%x skipping_c_comment
%x ifdef
%x ifndef

%{

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// In case there is any doubt, 'cql.l' is included in the license as well as
// the code flex generates from it.

#include "cql.y.h"
#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include <cql.h>
#include <charbuf.h>
#include <encoders.h>
#include <symtab.h>

void yyerror(const char *s, ...);
void line_directive(const char *);
char *Strdup(const char *);
static CSTR last_doc_comment = NULL;


cql_noexport int32_t resolve_macro_name(const char *);
static bool_t cql_already_processed_file(CSTR);
static void cql_record_processed_file(CSTR);

#ifndef CQL_AMALGAM
// already in the headers in the amalgam
int fileno(FILE *);
#endif

// the lexer has unused functions and implicit conversions, not easily removed

#ifndef _MSC_VER
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wconversion"
#endif

#pragma clang diagnostic ignored "-Wmisleading-indentation"

cql_noexport CSTR get_last_doc_comment() {
  CSTR result = last_doc_comment;
  last_doc_comment = NULL;
  return result;
}

static bool cql_builtins_processing = false;
static bool cql_delete_main_buffer = false;
static YY_BUFFER_STATE cql_main_buffer;

cql_noexport void cql_setup_for_builtins() {
  // stash a buffer for the main input, note that we might already have a buffer
  // in the amalgam case, if we do then use that.
  if (YY_CURRENT_BUFFER) {
    cql_main_buffer = YY_CURRENT_BUFFER;
    cql_delete_main_buffer = false;
  }
  else {
    // if we don't already have a buffer make one using yyin or stdin
    cql_main_buffer = yy_create_buffer(yyin ? yyin : stdin, YY_BUF_SIZE);
    cql_delete_main_buffer = true;
  }

  // add the builtin declares before we process the real input
  yy_scan_string(cql_builtin_text());
  cql_builtins_processing = true;
}

#define MAX_INCLUDES 10

typedef struct {
  YY_BUFFER_STATE buf;
  int32_t line_saved;
  char *filename_saved;
} cql_include_state;

static cql_include_state cql_includes[MAX_INCLUDES];
static int cql_include_index = 0;

typedef struct cql_ifdef_state_t {
  bool_t process_else;
  bool_t processing;
  struct cql_ifdef_state_t *prev;
} cql_ifdef_state_t;

static cql_ifdef_state_t *cql_ifdef_state;

static symtab *processed_files;

cql_noexport void cql_reset_open_includes() {
  cql_include_index = 0;
  memset(cql_includes, 0, sizeof(cql_includes));
  if (processed_files) { 
    symtab_delete(processed_files);
    processed_files = NULL;
  }
}

cql_noexport void cql_cleanup_open_includes() {
  while (cql_ifdef_state) {
     cql_ifdef_state_t *prev = cql_ifdef_state->prev;
     free(cql_ifdef_state);
     cql_ifdef_state = prev;
  }

  for (int32_t i = 0; i < cql_include_index; i++) {
     cql_include_state *inc = &cql_includes[i];
     yy_delete_buffer(inc->buf);
  }
  cql_reset_open_includes();
}

static void cql_setup_for_include(CSTR str) {
  if (!processed_files) {
    processed_files = symtab_new();
  }

  if (cql_include_index >= MAX_INCLUDES) {
    cql_error("%s:%d includes nested too deeply.\n", current_file, yylineno);
    cql_cleanup_and_exit(4);
  }

  cql_include_state *inc = &cql_includes[cql_include_index];

  inc->buf = YY_CURRENT_BUFFER;
  inc->line_saved = yylineno;
  inc->filename_saved = current_file;
  cql_include_index++;

  CHARBUF_OPEN(name);
  CHARBUF_OPEN(path);
  char resolved_path[PATH_MAX];  // PATH_MAX is defined in limits.h

  cg_decode_c_string_literal(str, &name);

  yyin = NULL;

  CSTR opened_name = name.ptr;

  // Call realpath to resolve the pathname
  char *abspath = realpath(name.ptr, resolved_path);
  if (abspath) {
    if (cql_already_processed_file(abspath)) {
      yy_switch_to_buffer(yy_scan_string(""));
      goto done;
    }
    yyin = fopen(abspath, "r");
  }

  if (!yyin) {
     for (int i = 0; i < options.include_paths_count; i++) {
        bclear(&path);
        bprintf(&path, "%s/%s", options.include_paths[i], name.ptr);
        abspath = realpath(path.ptr, resolved_path);
        if (abspath) {
          if (cql_already_processed_file(abspath)) {
            yy_switch_to_buffer(yy_scan_string(""));
            goto done;
          }

          yyin = fopen(path.ptr, "r");
          if (yyin) {
            opened_name = path.ptr;
            break;
          }
        }
     }
  }

  if (!yyin) {
     cql_error("%s:%d unable to open %s\n", current_file, yylineno, str);
     cql_cleanup_and_exit(1);
  }

  cql_record_processed_file(abspath);
  yy_switch_to_buffer(yy_create_buffer(yyin, YY_BUF_SIZE));

done:

  yylineno = 1;
  current_file = Strdup(opened_name);
  
  CHARBUF_CLOSE(path);
  CHARBUF_CLOSE(name);
}

static void cql_finish_stream() {
  // when we read the end of the temporary buffer we switch to the main buffer
  cql_builtins_processing = false;
  yy_delete_buffer(YY_CURRENT_BUFFER);
  yy_switch_to_buffer(cql_main_buffer);
}

static void cql_record_processed_file(CSTR str) {
  Contract(processed_files);
  symtab_add(processed_files, Strdup(str), NULL);
}

static bool_t cql_already_processed_file(CSTR str) {
  Contract(processed_files);
  return !!symtab_find(processed_files, str);
}

%}

stop [^A-Z_0-9]
sp [ \t]+
hex [0-9A-F]
d [0-9]

id [_A-Z][A-Z0-9_]*
qid `(``|[^`\n])*`
cstrlit \"(\\.|[^\\"\n])*\"
strlit '(''|[^']|\n)*'
reallit ({d}+"."{d}*|"."{d}+)(E("+"|"-")?{d}+)?

%%

@IFDEF                           { BEGIN(ifdef); }
<ifdef>{sp}*
<ifdef>{id}                      { 
                                   cql_ifdef_state_t *new_state = _new(cql_ifdef_state_t);
                                   new_state->prev = cql_ifdef_state;
                                   new_state->processing = cql_is_defined(yytext); 
                                   new_state->process_else = !new_state->processing;
                                   cql_ifdef_state = new_state;

                                   if (cql_ifdef_state->processing) {
                                     BEGIN(INITIAL);
                                   }
                                   else {
                                     BEGIN(skipping);
                                   }
                                 }

@IFNDEF                          { BEGIN(ifndef); }
<ifndef>{sp}*
<ifndef>{id}                     { 
                                   cql_ifdef_state_t *new_state = _new(cql_ifdef_state_t);
                                   new_state->prev = cql_ifdef_state;
                                   new_state->processing = !cql_is_defined(yytext); 
                                   new_state->process_else = !new_state->processing;
                                   cql_ifdef_state = new_state;

                                   if (cql_ifdef_state->processing) {
                                     BEGIN(INITIAL);
                                   }
                                   else {
                                     BEGIN(skipping);
                                   }
                                 }

@ELSE                            {
                                   if (cql_ifdef_state) {
                                     cql_ifdef_state->processing = false;
                                     BEGIN(skipping);
                                   }
                                 }

@ENDIF                           {
                                   if (cql_ifdef_state) {
                                     cql_ifdef_state_t *prev = cql_ifdef_state->prev;
                                     free(cql_ifdef_state);
                                     cql_ifdef_state = prev;
                                     // it is not possible to go from processing to not processing
                                     // so there is never a transition here
                                   }
                                 }

<skipping>@IFDEF                 {
                                   cql_ifdef_state_t *new_state = _new(cql_ifdef_state_t);
                                   new_state->prev = cql_ifdef_state;
                                   new_state->processing = false;
                                   new_state->process_else = false;
                                   cql_ifdef_state = new_state;
                                 }
                                   
<skipping>@ELSE                  {
                                   if (cql_ifdef_state->process_else) {
                                     cql_ifdef_state->processing = true;
                                     BEGIN(INITIAL);
                                   }
                                 }

<skipping>@ENDIF                 {
                                   cql_ifdef_state_t *prev = cql_ifdef_state->prev;
                                   free(cql_ifdef_state);
                                   cql_ifdef_state = prev;
                                   if (!cql_ifdef_state || cql_ifdef_state->processing) {
                                     BEGIN(INITIAL);
                                   }
                                 }

<skipping>"/*"                   { BEGIN(skipping_c_comment); }
<skipping_c_comment>.
<skipping_c_comment>[\n]
<skipping_c_comment>"*/"         { BEGIN(skipping); }

<skipping>--.*\n
<skipping>{qid}
<skipping>{strlit}
<skipping>{cstrlit}
<skipping>.
<skipping>[\n]

@INCLUDE                         {
                                   BEGIN(at_inc);
                                   return BEGIN_INCLUDE;
                                 }
<at_inc>{sp}*
<at_inc>{cstrlit}                {
                                   cql_setup_for_include(yytext);
                                   BEGIN(INITIAL);
                                 }

@@BEGIN_INCLUDE@@                { return BEGIN_INCLUDE; }
@@END_INCLUDE@@                  { return END_INCLUDE; }
@ATTRIBUTE                       { return AT_ATTRIBUTE; }
@BEGIN_SCHEMA_REGION             { return AT_BEGIN_SCHEMA_REGION; }
@BLOB_CREATE_KEY                 { return AT_BLOB_CREATE_KEY ; }
@BLOB_CREATE_VAL                 { return AT_BLOB_CREATE_VAL; }
@BLOB_GET_KEY                    { return AT_BLOB_GET_KEY ; }
@BLOB_GET_KEY_TYPE               { return AT_BLOB_GET_KEY_TYPE ; }
@BLOB_GET_VAL                    { return AT_BLOB_GET_VAL ; }
@BLOB_GET_VAL_TYPE               { return AT_BLOB_GET_VAL_TYPE ; }
@BLOB_UPDATE_KEY                 { return AT_BLOB_UPDATE_KEY; }
@BLOB_UPDATE_VAL                 { return AT_BLOB_UPDATE_VAL; }
@COLUMNS                         { return AT_COLUMNS; }
@CREATE                          { return AT_CREATE; }
@DECLARE_DEPLOYABLE_REGION       { return AT_DECLARE_DEPLOYABLE_REGION; }
@DECLARE_SCHEMA_REGION           { return AT_DECLARE_SCHEMA_REGION; }
@DELETE                          { return AT_DELETE; }
@DUMMY_DEFAULTS                  { return AT_DUMMY_DEFAULTS; }
@DUMMY_NULLABLES                 { return AT_DUMMY_NULLABLES; }
@DUMMY_SEED                      { return AT_DUMMY_SEED; }
@ECHO                            { return AT_ECHO; }
@EMIT_CONSTANTS                  { return AT_EMIT_CONSTANTS; }
@EMIT_ENUMS                      { return AT_EMIT_ENUMS; }
@EMIT_GROUP                      { return AT_EMIT_GROUP; }
@END_SCHEMA_REGION               { return AT_END_SCHEMA_REGION; }
@ENFORCE_NORMAL                  { return AT_ENFORCE_NORMAL; }
@ENFORCE_POP                     { return AT_ENFORCE_POP; }
@ENFORCE_PUSH                    { return AT_ENFORCE_PUSH; }
@ENFORCE_RESET                   { return AT_ENFORCE_RESET; }
@ENFORCE_STRICT                  { return AT_ENFORCE_STRICT; }
@EPONYMOUS                       { return AT_EPONYMOUS; }
@FILE                            { return AT_FILE; }
@ID                              { return AT_ID; }
@KEEP_TABLE_NAME_IN_ALIASES      { return AT_KEEP_TABLE_NAME_IN_ALIASES; }
@LINE                            { return AT_LINE; }
@MACRO_FILE                      { return AT_MACRO_FILE; }
@MACRO_LINE                      { return AT_MACRO_LINE; }
@MACRO                           { return AT_MACRO; }
@PREVIOUS_SCHEMA                 { return AT_PREVIOUS_SCHEMA; }
@PROC                            { return AT_PROC; }
@RC                              { return AT_RC; }
@RECREATE                        { return AT_RECREATE; }
@SCHEMA_AD_HOC_MIGRATION         { return AT_SCHEMA_AD_HOC_MIGRATION; }
@SCHEMA_UPGRADE_SCRIPT           { return AT_SCHEMA_UPGRADE_SCRIPT; }
@SCHEMA_UPGRADE_VERSION          { return AT_SCHEMA_UPGRADE_VERSION; }
@SENSITIVE                       { return AT_SENSITIVE; }
@TEXT                            { return AT_TEXT; }
@UNSUB                           { return AT_UNSUB; }
ABORT                            { return ABORT; }
ACTION                           { return ACTION; }
ADD                              { return ADD; }
AFTER                            { return AFTER; }
ALL                              { return ALL; }
ALTER                            { return ALTER; }
AND                              { return AND; }
ARGUMENTS                        { return ARGUMENTS; }
AS                               { return AS; }
ASC                              { return ASC; }
AUTOINCREMENT                    { return AUTOINCREMENT; }
BEFORE                           { return BEFORE; }
BEGIN                            { return BEGIN_; }
BETWEEN                          { return BETWEEN; }
BLOB                             { return BLOB; }
BOOL                             { return BOOL_; }
BY                               { return BY; }
CALL                             { return CALL; }
CASCADE                          { return CASCADE; }
CASE                             { return CASE; }
CAST                             { return CAST; }
CATCH                            { return CATCH; }
CHECK                            { return CHECK; }
CLOSE                            { return CLOSE; }
COLLATE                          { return COLLATE; }
COLUMN                           { return COLUMN; }
COMMIT                           { return COMMIT; }
CONST                            { return CONST; }
CONSTRAINT                       { return CONSTRAINT; }
CONTEXT{sp}COLUMN/{stop}         { return CONTEXT_COLUMN; }
CONTEXT{sp}TYPE/{stop}           { return CONTEXT_TYPE; }
CONTINUE                         { return CONTINUE; }
CREATE                           { return CREATE; }
CROSS                            { return CROSS; }
CTE_TABLES                       { return CTE_TABLES; }
CURRENT{sp}ROW/{stop}            { return CURRENT_ROW; }
CURSOR                           { return CURSOR; }
CURSOR{sp}HAS{sp}ROW/{stop}      { return CURSOR_HAS_ROW; }
DECLARE                          { return DECLARE; }
DEFAULT                          { return DEFAULT; }
DEFERRABLE                       { return DEFERRABLE; }
DEFERRED                         { return DEFERRED; }
DELETE                           { return DELETE; }
DESC                             { return DESC; }
DISTINCT                         { return DISTINCT; }
DISTINCTROW                      { return DISTINCTROW; }
DO                               { return DO; }
DROP                             { return DROP; }
ELSE                             { return ELSE; }
ELSE{sp}IF/{stop}                { return ELSE_IF; }
ENCODE                           { return ENCODE; }
END                              { return END; }
ENUM                             { return ENUM; }
EXCEPT                           { return EXCEPT; }
EXCLUDE{sp}CURRENT{sp}ROW/{stop} { return EXCLUDE_CURRENT_ROW; }
EXCLUDE{sp}GROUP/{stop}          { return EXCLUDE_GROUP; }
EXCLUDE{sp}NO{sp}OTHERS/{stop}   { return EXCLUDE_NO_OTHERS; }
EXCLUDE{sp}TIES/{stop}           { return EXCLUDE_TIES; }
EXCLUSIVE                        { return EXCLUSIVE; }
EXISTS                           { return EXISTS; }
EXPLAIN                          { return EXPLAIN; }
EXPR                             { return EXPR; }
FAIL                             { return FAIL; }
FALSE                            { return FALSE_; }
FETCH                            { return FETCH; }
FILTER                           { return FILTER; }
FIRST                            { return FIRST; }
FOLLOWING                        { return FOLLOWING; }
FOR                              { return FOR; }
FOREIGN                          { return FOREIGN; }
FOR{sp}EACH{sp}ROW/{stop}        { return FOR_EACH_ROW; }
FROM                             { return FROM; }
FROM{sp}BLOB/{stop}              { return FROM_BLOB; }
FUNC                             { return FUNC; }
FUNCTION                         { return FUNCTION; }
GLOB                             { return GLOB; }
GROUP                            { return GROUP; }
GROUPS                           { return GROUPS; }
HAVING                           { return HAVING; }
HIDDEN                           { return HIDDEN; }
IF                               { return IF; }
IGNORE                           { return IGNORE; }
IMMEDIATE                        { return IMMEDIATE; }
IN                               { return IN; }
INDEX                            { return INDEX; }
INITIALLY                        { return INITIALLY; }
INNER                            { return INNER; }
INOUT                            { return INOUT; }
INSERT                           { return INSERT; }
INSTEAD                          { return INSTEAD; }
INT                              { return INT_; }
INTEGER                          { return INTEGER; }
INTERFACE                        { return INTERFACE; }
INTERSECT                        { return INTERSECT; }
INTO                             { return INTO; }
IS                               { return IS; }
ISNULL                           { return ISNULL; }
IS{sp}FALSE/{stop}               { return IS_FALSE; }
IS{sp}NOT/{stop}                 { return IS_NOT; }
IS{sp}NOT{sp}FALSE/{stop}        { return IS_NOT_FALSE; }
IS{sp}NOT{sp}TRUE/{stop}         { return IS_NOT_TRUE; }
IS{sp}TRUE/{stop}                { return IS_TRUE; }
JOIN                             { return JOIN; }
KEY                              { return KEY; }
LAST                             { return LAST; }
LEAVE                            { return LEAVE; }
LEFT                             { return LEFT; }
LET                              { return LET; }
LIKE                             { return LIKE; }
LIMIT                            { return LIMIT; }
LONG                             { return LONG_; }
LONG_INT                         { return LONG_INT; }
LONG_INTEGER                     { return LONG_INTEGER; }
LOOP                             { return LOOP; }
MATCH                            { return MATCH; }
NO                               { return NO; }
NOT                              { return NOT; }
NOTHING                          { return NOTHING; }
NOTNULL                          { return NOTNULL; }
NOT{sp}BETWEEN/{stop}            { return NOT_BETWEEN; }
NOT{sp}DEFERRABLE/{stop}         { return NOT_DEFERRABLE; }
NOT{sp}GLOB/{stop}               { return NOT_GLOB; }
NOT{sp}IN/{stop}                 { return NOT_IN; }
NOT{sp}LIKE/{stop}               { return NOT_LIKE; }
NOT{sp}MATCH/{stop}              { return NOT_MATCH; }
NOT{sp}REGEXP/{stop}             { return NOT_REGEXP; }
NULL                             { return NULL_; }
NULLS                            { return NULLS; }
OBJECT                           { return OBJECT; }
OF                               { return OF; }
OFFSET                           { return OFFSET; }
ON                               { return ON; }
ON{sp}CONFLICT/{stop}            { return ON_CONFLICT; }
OR                               { return OR; }
ORDER                            { return ORDER; }
OUT                              { return OUT; }
OUTER                            { return OUTER; }
OVER                             { return OVER; }
PARTITION                        { return PARTITION; }
PRECEDING                        { return PRECEDING; }
PRIMARY                          { return PRIMARY; }
PRIVATE                          { return PRIVATE; }
PROC                             { return PROC; }
PROCEDURE                        { return PROCEDURE; }
QUERY_PARTS                      { return QUERY_PARTS; }
QUERY{sp}PLAN/{stop}             { return QUERY_PLAN; }
RAISE                            { return RAISE; }
RANGE                            { return RANGE; }
REAL                             { return REAL; }
RECURSIVE                        { return RECURSIVE; }
REFERENCES                       { return REFERENCES; }
REGEXP                           { return REGEXP; }
RELEASE                          { return RELEASE; }
RENAME                           { return RENAME; }
REPLACE                          { return REPLACE; }
RESTRICT                         { return RESTRICT; }
RETURN                           { return RETURN; }
RIGHT                            { return RIGHT; }
ROLLBACK                         { return ROLLBACK; }
ROWID                            { return ROWID; }
ROWS                             { return ROWS; }
SAVEPOINT                        { return SAVEPOINT; }
SELECT                           { return SELECT; }
SELECT_CORE                      { return SELECT_CORE; }
SELECT_EXPR                      { return SELECT_EXPR; }
SET                              { return SET; }
SIGN{sp}FUNCTION/{stop}          { return SIGN_FUNCTION; }
STATEMENT                        { return STATEMENT; }
STMT_LIST                        { return STMT_LIST; }
SWITCH                           { return SWITCH; }
TABLE                            { return TABLE; }
TEMP                             { return TEMP; }
TEXT                             { return TEXT; }
THEN                             { return THEN; }
THROW                            { return THROW; }
TO                               { return TO; }
TRANSACTION                      { return TRANSACTION; }
TRIGGER                          { return TRIGGER; }
TRUE                             { return TRUE_; }
TRY                              { return TRY; }
TYPE                             { return TYPE; }
TYPE_CHECK                       { return TYPE_CHECK; }
UNBOUNDED                        { return UNBOUNDED; }
UNION                            { return UNION; }
UNION{sp}ALL/{stop}              { return UNION_ALL; }
UNIQUE                           { return UNIQUE; }
UPDATE                           { return UPDATE; }
UPSERT                           { return UPSERT; }
USING                            { return USING; }
VALUES                           { return VALUES; }
VAR                              { return VAR; }
VIEW                             { return VIEW; }
VIRTUAL                          { return VIRTUAL; }
WHEN                             { return WHEN; }
WHERE                            { return WHERE; }
WHILE                            { return WHILE; }
WINDOW                           { return WINDOW; }
WITH                             { return WITH; }
WITHOUT                          { return WITHOUT; }

"->"                             { return JEX1; }
"->>"                            { return JEX2; }
"!="                             { return NE_; }
"%="                             { return MOD_EQ; }
"&="                             { return AND_EQ; }
"*="                             { return MUL_EQ; }
"+="                             { return ADD_EQ; }
"-="                             { return SUB_EQ; }
"/="                             { return DIV_EQ; }
":="                             { return ASSIGN; }
"<<"                             { return LS; }
"<<="                            { return LS_EQ; }
"<="                             { return LE; }
"<>"                             { return NE; }
"=="                             { return EQEQ; }
">="                             { return GE; }
">>"                             { return RS; }
">>="                            { return RS_EQ; }
"|="                             { return OR_EQ; }
"||"                             { return CONCAT; }

0x{hex}+                         { char *s = Strdup(yytext);
                                   yylval.sval = s;
                                   errno = 0;
                                   return (strtoll(s+2, NULL, 16) <= 0x7fffffff  && errno == 0) ? INTLIT: LONGLIT; }

0x{hex}+L                        { char *s = Strdup(yytext);
                                   s[strlen(s)-1] = 0; /* remove the L */
                                   yylval.sval = s;
                                   return LONGLIT; }

{d}+                             { char *s = Strdup(yytext);
                                   yylval.sval = s;
                                   errno = 0;
                                   return (strtoll(s, NULL, 10) <= 0x7fffffff  && errno == 0) ? INTLIT: LONGLIT; }

{d}+L                            { char *s = Strdup(yytext);
                                   s[strlen(s)-1] = 0; /* remove the L */
                                   yylval.sval = s;
                                   return LONGLIT; }

{reallit}                        { yylval.sval = Strdup(yytext); return REALLIT; }
{qid}                            { yylval.sval = Strdup(yytext); return QID; }
{cstrlit}                        { yylval.sval = Strdup(yytext); return CSTRLIT; }
{strlit}                         { yylval.sval = Strdup(yytext); return STRLIT; }
X'({hex}{hex})*'                 { yylval.sval = Strdup(yytext); return BLOBLIT; }

[-+&~|^/%*(),.;!<>:=]            { return yytext[0]; }
\[                               { return yytext[0]; }
\]                               { return yytext[0]; }
\{                               { return yytext[0]; }
\}                               { return yytext[0]; }
{id}                             { yylval.sval = Strdup(yytext); return ID; }
{id}!                            { int32_t result = resolve_macro_name(yytext);
                                   if (result == EOF) {
                                     REJECT;
                                   }
                                   else {
                                     yylval.sval = Strdup(yytext);
                                   }
                                   return result;
                                 }

[ \t\r\n]                        ;
\-\-.*                           ;

.                                { yyerror("Unexpected %s\n", yytext); }

^#\ {d}+\ \"[^"]*\".*            { line_directive(yytext); }
^\ *#line\ {d}+\ \"[^"]*\".*     { line_directive(yytext); }

"/*"                             { // sqlite supports C style comments... ignore those
                                   CHARBUF_OPEN(tmp);
                                   int c1 = 0, c2 = input();
                                   bool_t save_comment = false;
                                   if (c2 == '!' || c2 == '*') {
                                     save_comment = true;
                                     bputc(&tmp, '/');
                                     bputc(&tmp, '*');
                                   }
                                   for (;;) {
                                     if (c2 == EOF) break;
                                     if (save_comment) {
                                       bputc(&tmp, c2);
                                     }
                                     if (c1 == '*' && c2 == '/') break;
                                     c1 = c2;
                                     c2 = input();
                                   }
                                   if (save_comment) {
                                     CHARBUF_OPEN(strlit);
                                     cg_encode_c_string_literal(tmp.ptr, &strlit);
                                     last_doc_comment = Strdup(strlit.ptr);
                                     CHARBUF_CLOSE(strlit);
                                   }
                                   CHARBUF_CLOSE(tmp);
                                 }

<<EOF>>                          {
                                   if (cql_builtins_processing)  {
                                     cql_finish_stream();
                                   }
                                   else if (!cql_include_index) {
                                     if (cql_delete_main_buffer) {
                                        yy_delete_buffer(YY_CURRENT_BUFFER);
                                        cql_delete_main_buffer = false;
                                     }
                                     yyterminate();
                                   }
                                   else {
                                     yy_delete_buffer(YY_CURRENT_BUFFER);
                                     cql_include_state *inc = &cql_includes[--cql_include_index];
                                     yy_switch_to_buffer(inc->buf);
                                     yylineno = inc->line_saved;
                                     current_file = inc->filename_saved;
                                     return END_INCLUDE;
                                   }
                                 }

