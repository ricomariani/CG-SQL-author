/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_UNIT_TESTS)

// stubs to avoid link errors
cql_noexport void run_unit_tests() {}

#else

#include "cql.h"
#include "bytebuf.h"
#include "cg_common.h"
#include "unit_tests.h"
#include "encoders.h"

// This file implement very simple unit tests for functions that are too complicated
// to test directly through invocations of the CQL tool.
//
// This test suite is extremely simple and it does not (purposefully) use common
// test infrastructure such as gtest or gmock. This is just a simple C program
// that calls test functions and asserts their results on every step.

#define TEST_ASSERT assert
#define STR_EQ(s1, s2) strcmp(s1, s2) == 0

cql_noexport void cg_c_init(void);
cql_noexport void cg_c_cleanup(void);
cql_noexport uint32_t cg_statement_pieces(CSTR in, charbuf *output);

static bool test_frag_tricky_case() {
  options.compress = 1;
  CHARBUF_OPEN(tmp);
  cg_c_init();
  // get into a state with a single trailing space
  uint32_t count = cg_statement_pieces("atest btest ", &tmp);
  cg_c_cleanup();
  CHARBUF_CLOSE(tmp);

  // two tokens, no going off the end and making extra tokens!
  return count == 2;
}

static bool test_strdup__empty_string() {
  char* str_copy = Strdup("");
  bool result = STR_EQ(str_copy, "");
  return result;
}

static bool test_strdup__one_character_string() {
  char* str_copy = Strdup("a");
  bool result = STR_EQ(str_copy, "a");
  return result;
}

static bool test_strdup__long_string() {
  char* str_copy = Strdup("abcd");
  bool result = STR_EQ(str_copy, "abcd");
  return result;
}

static bool test_strcasecmp_empty_strings() {
  return StrCaseCmp("", "") == 0;
}

static bool test_strcasecmp_one_char_strings__result_is_less_than() {
  return StrCaseCmp("a", "B") < 0;
}

static bool test_strcasecmp_one_char_strings__result_is_greater_than() {
  return StrCaseCmp("B", "a") > 0;
}

static bool test_strcasecmp_one_char_strings__result_is_equals() {
  return StrCaseCmp("Aab", "aaB") == 0;
}

static bool test_strcasecmp_long_strings__result_is_less_than() {
  return StrCaseCmp("aca", "acD") < 0;
}

static bool test_strcasecmp_long_strings__result_is_greater_than() {
  return StrCaseCmp("bab", "baA") > 0;
}

static bool test_strcasecmp_long_strings__result_is_equals() {
  return StrCaseCmp("Aab", "aaB") == 0;
}

static bool test_strcasecmp_different_length_strings__result_is_less_than() {
  return StrCaseCmp("aab", "AABc") < 0;
}

static bool test_strcasecmp_different_length_strings__result_is_greater_than() {
  return StrCaseCmp("AABc", "aab") > 0;
}

static bool test_strncasecmp__empty_strings__zero_cmp_size__result_is_equals() {
  return StrNCaseCmp("", "", 0) == 0;
}

static bool test_strncasecmp__empty_strings__past_length_cmp_size__result_is_equals() {
  return StrNCaseCmp("", "", 1) == 0;
}

static bool test_strncasecmp__one_char_strings__zero_cmp_size__result_is_equals() {
  return StrNCaseCmp("a", "b", 0) == 0;
}

static bool test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_less_than() {
  return StrNCaseCmp("a", "B", 2) < 0;
}

static bool test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_greater_than() {
  return StrNCaseCmp("B", "a", 2) > 0;
}

static bool test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_equals() {
  return StrNCaseCmp("B", "b", 2) == 0;
}

static bool test_strncasecmp__long_strings__past_length_cmp_size__result_is_less_than() {
  return StrNCaseCmp("aca", "acD", 4) < 0;
}

static bool test_strncasecmp__long_strings__past_length_cmp_size__result_is_greater_than() {
  return StrNCaseCmp("bab", "baA", 4) > 0;
}

static bool test_strncasecmp__long_strings__past_length_cmp_size__result_is_equals() {
  return StrNCaseCmp("Aab", "aaB", 4) == 0;
}

static bool test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_less_than() {
  return StrNCaseCmp("abd", "Aca", 2) < 0;
}

static bool test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_greater_than() {
  return StrNCaseCmp("Bbd", "baa", 2) > 0;
}

static bool test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_equals() {
  return StrNCaseCmp("Aac", "aaB", 2) == 0;
}

static bool test_sha256_example1() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "Foo:x:String");
  bool result = sha256_charbuf(&temp) == -5028419846961717871L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_sha256_example2() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "id:?Int64");
  bool result = sha256_charbuf(&temp) == -9155171551243524439L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_sha256_example3() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "x:String");
  bool result = sha256_charbuf(&temp) == -6620767298254076690L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_sha256_example4() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "fooBar:?Int64");
  bool result = sha256_charbuf(&temp) == -6345014076009057275L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_sha256_example5() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.");
  bool result = sha256_charbuf(&temp) == -8121930428982087348L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_sha256_example6() {
  CHARBUF_OPEN(temp);
  bprintf(&temp, "XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.XXXXXXXXX.123456789");
  bool result = sha256_charbuf(&temp) ==  -4563262961718308998L;
  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_unknown_macro() {
 ast_node *t = new_ast_unknown_macro_arg(NULL, NULL);
 if (t->type != k_ast_unknown_macro_arg) return false;

 t = new_ast_unknown_macro_def(NULL, NULL);
 if (t->type != k_ast_unknown_macro_def) return false;
 return true;
}

cql_noexport char *Dirname(char *in);

static bool test_Dirname() {
   char buf[10];
   char *result;

   result = Dirname(NULL);
   if (strcmp(result, ".")) return false;

   strcpy(buf, "");
   result = Dirname(buf);
   if (strcmp(result, ".")) return false;

   strcpy(buf, "no_dir");
   result = Dirname(buf);
   if (strcmp(result, ".")) return false;

   strcpy(buf, "x\\y.z");
   result = Dirname(buf);
   if (strcmp(result, "x")) return false;

   strcpy(buf, "x/y.z");
   result = Dirname(buf);
   if (strcmp(result, "x")) return false;

   strcpy(buf, "/y.z");
   result = Dirname(buf);
   if (strcmp(result, "/")) return false;

   return true;
}

// We're going to try to convert utf8 that is badly formed in such cases the
// encoder should escape the bad bytes with \u00XX escapes this is imperfect but
// it's the best we can do without rejecting the input entirely and there is no
// meaningful way to map invalid utf8 into valid utf8 we could make these errors
// in the parser but that would be disruptive and in any case the code has to do
// something with bogus buffers... even if we trimmed them upstream there is no
// guarantee that the data is valid utf8 later on all future paths so we have to
// deal with it here.
static bool test_badly_formed_utf8() {
  bool result = true;

  CHARBUF_OPEN(temp);

  // control case -- well formed utf8 passes through unchanged
  cg_encode_json_string_literal(" \xe2\x80\xa2 ", &temp);
  result &= !strcmp(temp.ptr, "\" \xe2\x80\xa2 \"");

  // case 1: isolated continuation byte
  bclear(&temp);
  cg_encode_json_string_literal("\x81", &temp);
  result &= !strcmp(temp.ptr, "\"\\u0081\"");

  // case 2: a valid prefix followed by an extra continuation byte. The January
  // 2026 correction deliberately escapes the entire malformed run.
  bclear(&temp);
  cg_encode_json_string_literal(" \xe2\x80\xa2\xa2 ", &temp);
  result &= !strcmp(temp.ptr, "\" \\u00e2\\u0080\\u00a2\\u00a2 \"");

  // case 3: truncated sequence
  bclear(&temp);
  cg_encode_json_string_literal(" \xe2\x80 ", &temp);
  result &= !strcmp(temp.ptr, "\" \\u00e2\\u0080 \"");

  CHARBUF_CLOSE(temp);

  return result;
}

static void test_json_pretty_utf8() {
  const struct {
    CSTR name;
    CSTR input;
    CSTR expected;
  } cases[] = {
    // Printable text, quoting, and named control escapes must not change.
    { "ASCII and controls", "'\"\\\b\f\n\r\t\a\v'",
      "\"'\\\"\\\\\\b\\f\\n\\r\\t\\u0007\\u000b'\"" },
    // C0 still needs escaping, but DEL is legal raw JSON text. Do not expand
    // the fix into an output-spelling change for otherwise valid ASCII.
    { "ASCII escape boundary", "'\x1f\x7f'", "\"'\\u001f\x7f'\"" },
    // All UTF-8 widths must survive as the original bytes, not Latin-1 escapes.
    { "two-byte UTF-8", "'\xc3\xa9'", "\"'\xc3\xa9'\"" },
    { "three-byte UTF-8", "'\xe2\x80\xa2'", "\"'\xe2\x80\xa2'\"" },
    { "four-byte UTF-8", "'\xf0\x9f\x98\x80'", "\"'\xf0\x9f\x98\x80'\"" },
    // Codepoint boundaries catch validators that accept only common examples.
    { "lowest two-byte codepoint", "'\xc2\x80'", "\"'\xc2\x80'\"" },
    { "lowest three-byte codepoint", "'\xe0\xa0\x80'", "\"'\xe0\xa0\x80'\"" },
    { "lowest four-byte codepoint", "'\xf0\x90\x80\x80'", "\"'\xf0\x90\x80\x80'\"" },
    { "highest Unicode codepoint", "'\xf4\x8f\xbf\xbf'", "\"'\xf4\x8f\xbf\xbf'\"" },
    // The fallback intentionally maps malformed bytes to \u00xx, not to
    // replacement characters or unchecked raw bytes. Preserve ASCII around them.
    { "isolated continuation", "'a\x81z'", "\"'a\\u0081z'\"" },
    { "invalid lead byte", "'\xff'", "\"'\\u00ff'\"" },
    // Preserve the January 2026 rule: an extra continuation invalidates the
    // preceding sequence too, even when that prefix alone would be valid.
    { "extra continuation", "'\xe2\x80\xa2\xa2'",
      "\"'\\u00e2\\u0080\\u00a2\\u00a2'\"" },
    // Each sequence width can be truncated at the terminating zero. These
    // fixtures end there, rather than supplying a quote as an accidental sentinel.
    { "truncated two-byte sequence", "\xc2", "\"\\u00c2\"" },
    { "truncated three-byte sequence", "\xe2\x80", "\"\\u00e2\\u0080\"" },
    { "truncated four-byte sequence", "\xf0\x9f\x98", "\"\\u00f0\\u009f\\u0098\"" },
    // Overlong forms, surrogate codepoints, and values above Unicode's maximum
    // must stay on the malformed-byte path rather than pass as valid UTF-8.
    { "overlong two-byte sequence", "'\xc0\xaf'", "\"'\\u00c0\\u00af'\"" },
    { "overlong three-byte sequence", "'\xe0\x80\xaf'", "\"'\\u00e0\\u0080\\u00af'\"" },
    { "overlong four-byte sequence", "'\xf0\x80\x80\xaf'", "\"'\\u00f0\\u0080\\u0080\\u00af'\"" },
    { "surrogate codepoint", "'\xed\xa0\x80'", "\"'\\u00ed\\u00a0\\u0080'\"" },
    { "above Unicode maximum", "'\xf4\x90\x80\x80'", "\"'\\u00f4\\u0090\\u0080\\u0080'\"" },
    // Consecutive valid sequences must advance by their full widths; following
    // quote/backslash/newline characters must still go through JSON escaping.
    { "mixed UTF-8 and escapes", "'\xc3\xa9\xe2\x80\xa2\xf0\x9f\x98\x80\"\\\n'",
      "\"'\xc3\xa9\xe2\x80\xa2\xf0\x9f\x98\x80\\\"\\\\\\n'\"" },
  };

  CHARBUF_OPEN(encoded);
  for (uint32_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    printf("Checking JSON UTF-8 case: %s\n", cases[i].name);
    // Assertion failure aborts without flushing redirected stdout.
    fflush(stdout);
    bclear(&encoded);
    cg_encode_json_string_literal(cases[i].input, &encoded);
    TEST_ASSERT(!strcmp(encoded.ptr, cases[i].expected));
    bclear(&encoded);
    cg_pretty_quote_plaintext(cases[i].input, &encoded, PRETTY_QUOTE_JSON);
    TEST_ASSERT(!strcmp(encoded.ptr, cases[i].expected));
  }
  CHARBUF_CLOSE(encoded);
}

static void test_identifier_encoding() {
  static const struct {
    CSTR input;
    CSTR encoded;
  } cases[] = {
    { "`XName`", "XName" },
    { "`aXb`", "aXb" },
    { "`X`", "X" },
    { "`X_Name`", "X_X58_Name" },
    { "`X_X58Name`", "X_X58_X5858Name" },
    { "`aX b`", "X_aX58X20b" },
    { "`1field`", "X_1field" },
    { "`a``b`", "X_aX60b" },
    { "`caf\xc3\xa9`", "X_cafXc3Xa9" },
    { "`safe_123`", "safe_123" },
  };
  CHARBUF_OPEN(encoded);
  CHARBUF_OPEN(decoded);
  for (uint32_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    bclear(&encoded);
    bclear(&decoded);
    // The encoder appends into existing output; prefix insertion must preserve it.
    bprintf(&encoded, "prefix:");
    cg_encode_qstr(&encoded, cases[i].input);
    TEST_ASSERT(!strncmp(encoded.ptr, "prefix:", 7));
    TEST_ASSERT(!strcmp(encoded.ptr + 7, cases[i].encoded));
    cg_decode_qstr(&decoded, encoded.ptr + 7);
    TEST_ASSERT(!strcmp(decoded.ptr, cases[i].input));
  }
  CHARBUF_CLOSE(decoded);
  CHARBUF_CLOSE(encoded);
}

static bool test_c_hex_escape_boundaries() {
  bool result = true;
  CHARBUF_OPEN(temp);
  CSTR bytes = "\x01" "f\x02" "9\xa1" "A";

  // Lowercase/uppercase hex letters and digits all extend C's hex escapes.
  // Adjacent literal tokens must stop the scan while preserving the byte values.
  cg_encode_c_string_literal(bytes, &temp);
  result &= !strcmp(temp.ptr, "\"\\x01\" \"f\\x02\" \"9\\xa1\" \"A\"");

  // Do not split before non-hex characters, after named escapes, inside text
  // spelling a literal backslash-x, or after an escape at the end of the string.
  bclear(&temp);
  cg_encode_c_string_literal("\x01" "g\nf\\x01f\x02", &temp);
  result &= !strcmp(temp.ptr, "\"\\x01g\\nf\\\\x01f\\x02\"");

  // The Lua encoder must keep its existing spelling; in particular,
  // Lua cannot concatenate adjacent literals by the C syntax.
  bclear(&temp);
  cg_encode_lua_string_literal(bytes, &temp);
  result &= !strcmp(temp.ptr, "\"\\x01f\\x029\\xa1A\"");

  // Forking the encoders must preserve named escapes and quote/backslash
  // handling, rather than treating these characters as generic byte escapes.
  bclear(&temp);
  cg_encode_lua_string_literal("\"\\\a\b\f\n\r\t\v", &temp);
  result &= !strcmp(temp.ptr, "\"\\\"\\\\\\a\\b\\f\\n\\r\\t\\v\"");
  bclear(&temp);
  cg_encode_c_string_literal("\"\\\a\b\f\n\r\t\v", &temp);
  result &= !strcmp(temp.ptr, "\"\\\"\\\\\\a\\b\\f\\n\\r\\t\\v\"");

  // SQL text is quoted through a separate path and needs the same C boundaries.
  bclear(&temp);
  cg_pretty_quote_plaintext("SELECT '\x01" "f'", &temp, PRETTY_QUOTE_C);
  result &= !strcmp(temp.ptr, "\"SELECT '\\x01\" \"f'\"");
  bclear(&temp);
  cg_pretty_quote_plaintext("SELECT '\x01" "f'", &temp, PRETTY_QUOTE_LUA);
  result &= !strcmp(temp.ptr, "\"SELECT '\\x01f'\"");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_comment_text_encoding() {
  bool result = true;
  CHARBUF_OPEN(temp);

  // Ordinary printable text must be preserved exactly.  Filenames should stay
  // readable, and line-comment punctuation is harmless within a line comment.
  cg_encode_comment_text("safe [] -- // text", &temp);
  result &= !strcmp(temp.ptr, "safe [] -- // text");

  // CR and LF are the security-critical cases: either could terminate the
  // generated line comment and expose the rest of a filename as source code.
  bclear(&temp);
  cg_encode_comment_text("a\nb\rc", &temp);
  result &= !strcmp(temp.ptr, "a\\nb\\rc");

  // A tab does not terminate the comment, but making it visible keeps generated
  // provenance single-line and prevents invisible formatting surprises.
  bclear(&temp);
  cg_encode_comment_text("a\tb", &temp);
  result &= !strcmp(temp.ptr, "a\\tb");

  // Other C0 controls have no familiar spelling, so they use fixed-width hex.
  // This verifies both ends of the encoded C0 range.
  bclear(&temp);
  cg_encode_comment_text("\x01\x1f", &temp);
  result &= !strcmp(temp.ptr, "\\x01\\x1f");

  // DEL sits outside the C0 range but is also non-printing and must be encoded.
  bclear(&temp);
  cg_encode_comment_text("\x7f", &temp);
  result &= !strcmp(temp.ptr, "\\x7f");

  // UTF-8 bytes cannot end a line comment and should remain readable rather
  // than being expanded into byte escapes.
  bclear(&temp);
  cg_encode_comment_text("\xe2\x80\xa2", &temp);
  result &= !strcmp(temp.ptr, "\xe2\x80\xa2");

  // Encoders append to caller-owned buffers.  Verify this helper does not clear
  // content that the caller emitted before the comment text.
  bclear(&temp);
  bprintf(&temp, "prefix:");
  cg_encode_comment_text("value", &temp);
  result &= !strcmp(temp.ptr, "prefix:value");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_comment_marker_scan() {
  CHARBUF_OPEN(temp);

  cg_remove_slash_star_and_star_slash(&temp);
  bool result = temp.used == 1 && !strcmp(temp.ptr, "");

  const char *inputs[] = { "/", "*", "/*", "*/", "/* */", "text/*", "text*/" };
  const char *outputs[] = { "/", "*", "/+", "+/", "/+ +/", "text/+", "text+/" };
  for (uint32_t i = 0; i < sizeof(inputs) / sizeof(inputs[0]); i++) {
    bclear(&temp);
    bprintf(&temp, "%s", inputs[i]);
    uint32_t used = temp.used;
    cg_remove_slash_star_and_star_slash(&temp);
    result &= temp.used == used && !strcmp(temp.ptr, outputs[i]);
  }

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_bytebuf_self_append() {
  bytebuf buffer;
  bytebuf_open(&buffer);

  // Duplicating this seed forces growth while the source aliases the buffer.
  char seed[BYTEBUF_GROWTH_SIZE + 1];
  for (uint32_t i = 0; i < sizeof(seed); i++) {
    seed[i] = (char)(i & 0x7f);
  }
  bytebuf_append(&buffer, seed, sizeof(seed));
  bytebuf_append(&buffer, buffer.ptr, buffer.used);

  bool result =
    buffer.used == 2 * sizeof(seed) &&
    !memcmp(buffer.ptr, seed, sizeof(seed)) &&
    !memcmp(buffer.ptr + sizeof(seed), seed, sizeof(seed));

  bytebuf_append(&buffer, buffer.ptr + 17, 31);
  result &= buffer.used == 2 * sizeof(seed) + 31;
  result &= !memcmp(buffer.ptr + 2 * sizeof(seed), seed + 17, 31);

  bytebuf_close(&buffer);
  return result;
}

cql_noexport void run_unit_tests() {
  // An empty duplicate must still be a valid, NUL-terminated allocation.
  // Callers rely on receiving a string rather than NULL for empty input.
  TEST_ASSERT(test_strdup__empty_string());

  // The smallest non-empty input verifies that Strdup produces the expected
  // byte and terminator without truncation.
  TEST_ASSERT(test_strdup__one_character_string());

  // A multi-byte input verifies that Strdup copies the complete string rather
  // than accidentally handling only the first character.
  TEST_ASSERT(test_strdup__long_string());

  // Two empty strings establish the equality base case without reading beyond
  // either terminator.
  TEST_ASSERT(test_strcasecmp_empty_strings());

  // Case-insensitive ordering must still report a lexical less-than result
  // when the folded characters differ.
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_less_than());

  // Reverse operands verify the corresponding greater-than result and catch
  // implementations that return only equality versus inequality.
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_greater_than());

  // Mixed casing at several positions must compare equal after case folding.
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_equals());

  // A difference after a shared multi-character prefix must determine
  // less-than ordering, not just the first character.
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_less_than());

  // The reverse shared-prefix case verifies greater-than ordering at a later
  // character in the strings.
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_greater_than());

  // The long-string comparison group also verifies equality when every folded
  // character matches through the terminator.
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_equals());

  // When one folded string is a prefix of the other, the shorter string must
  // sort first.
  TEST_ASSERT(test_strcasecmp_different_length_strings__result_is_less_than());

  // Reversing a prefix pair must make the longer string sort after the shorter
  // one.
  TEST_ASSERT(test_strcasecmp_different_length_strings__result_is_greater_than());

  // A zero comparison limit must report equality without inspecting even empty
  // input.
  TEST_ASSERT(test_strncasecmp__empty_strings__zero_cmp_size__result_is_equals());

  // A limit beyond both empty strings verifies that comparison stops safely at
  // their terminators.
  TEST_ASSERT(test_strncasecmp__empty_strings__past_length_cmp_size__result_is_equals());

  // A zero limit must ignore differing non-empty input, matching strncasecmp
  // semantics.
  TEST_ASSERT(test_strncasecmp__one_char_strings__zero_cmp_size__result_is_equals());

  // With a limit beyond one-character inputs, folded lexical less-than must be
  // reported before the terminators are reached.
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_less_than());

  // Reversing the one-character operands verifies greater-than with a limit
  // larger than both strings.
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_greater_than());

  // Equal folded one-character strings must remain equal when the requested
  // limit extends past their terminators.
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_equals());

  // Longer inputs verify less-than at a later character while the limit extends
  // past the complete strings.
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_less_than());

  // The corresponding longer-input reverse case verifies greater-than after a
  // shared prefix.
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_greater_than());

  // Mixed-case longer strings must compare equal and stop at the terminator
  // even when the limit permits another byte.
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_equals());

  // A short comparison limit must return less-than using only the compared
  // prefix and must ignore later characters.
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_less_than());

  // Reversing the compared prefix verifies greater-than without consulting the
  // ignored suffix.
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_greater_than());

  // Equal folded prefixes must report equality even when characters after the
  // limit differ.
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_equals());

  // A statement ending in one trailing space previously risked scanning past
  // the buffer and inventing an extra fragment; exactly two tokens must remain.
  TEST_ASSERT(test_frag_tricky_case());

  // This known hash vector protects the stable schema-signature encoding for a
  // required string field.
  TEST_ASSERT(test_sha256_example1());

  // This vector covers nullable integer type syntax so changes in punctuation
  // or type spelling cannot silently alter stable hashes.
  TEST_ASSERT(test_sha256_example2());

  // A shorter field description verifies hashing without dependence on the
  // preceding examples' lengths or buffer contents.
  TEST_ASSERT(test_sha256_example3());

  // Mixed-case field names and nullable integer syntax provide another stable
  // real-world signature vector.
  TEST_ASSERT(test_sha256_example4());

  // This input crosses a SHA-256 block boundary, protecting multi-block update
  // and finalization behavior.
  TEST_ASSERT(test_sha256_example5());

  // This input exercises final-block padding near the SHA-256 block boundary,
  // where length and padding mistakes commonly occur.
  TEST_ASSERT(test_sha256_example6());

  // Unknown macro arguments and definitions require distinct AST node tags so
  // later parser and semantic phases can distinguish their roles.
  TEST_ASSERT(test_unknown_macro());

  // Dirname must handle NULL, empty and separator-free names plus Windows and
  // Unix separators, including the Unix root special case.
  TEST_ASSERT(test_Dirname());

  // Invalid UTF-8 must be escaped into valid JSON rather than copied as malformed
  // output or read past truncated byte sequences.
  TEST_ASSERT(test_badly_formed_utf8());
  // Both JSON paths must preserve valid codepoints and the established malformed
  // byte policy; syntactically valid JSON alone does not prove string fidelity.
  test_json_pretty_utf8();
  test_identifier_encoding();

  // Generated C must delimit greedy hex escapes without changing CQL/Lua output.
  TEST_ASSERT(test_c_hex_escape_boundaries());

  // Source-controlled provenance text must remain inside generated line
  // comments while preserving printable and UTF-8 content.
  TEST_ASSERT(test_comment_text_encoding());
  TEST_ASSERT(test_comment_marker_scan());
  TEST_ASSERT(test_bytebuf_self_append());
}

#endif
