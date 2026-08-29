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

  // case 2: overlong sequence
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

static bool test_bytebuf_self_append() {
  bytebuf buffer;
  bytebuf_open(&buffer);

  // Use more than one growth quantum so duplicating the buffer must replace
  // its allocation while the append source still refers to the old contents.
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

  bytebuf_close(&buffer);
  return result;
}

static void test_vbprintf_alias(charbuf *buffer, const char *format, ...) {
  va_list args;
  va_start(args, format);
  vbprintf(buffer, format, args);
  va_end(args);
}

static bool test_charbuf_format_aliases() {
  bool result = true;
  CHARBUF_OPEN(temp);

  // Force heap storage and growth so a %s argument into the destination would
  // become dangling if formatting released the old allocation too early.
  for (uint32_t i = 0; i < CHARBUF_INTERNAL_SIZE + 1; i++) {
    bputc(&temp, 'a');
  }
  bprintf(&temp, "%s", temp.ptr);
  result &= temp.used == 2 * (CHARBUF_INTERNAL_SIZE + 1) + 1;
  for (uint32_t i = 0; i < 2 * (CHARBUF_INTERNAL_SIZE + 1); i++) {
    result &= temp.ptr[i] == 'a';
  }

  // The format string itself may also reside in the destination buffer.
  bclear(&temp);
  bprintf(&temp, "literal");
  test_vbprintf_alias(&temp, temp.ptr);
  result &= !strcmp(temp.ptr, "literalliteral");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_c_control_before_hex_digit() {
  CHARBUF_OPEN(temp);

  // A C \x escape consumes every following hex digit; the encoded bytes must
  // remain 0x01 and 'f', rather than being compiled as the single byte 0x1f.
  cg_encode_c_string_literal("\x01" "f", &temp);
  bool result = !strcmp(temp.ptr, "\"\\001f\"");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_json_utf8_portability() {
  bool result = true;
  CHARBUF_OPEN(temp);

  // Invalid high bytes must be escaped even when plain char is unsigned.
  cg_encode_char_as_json_string_literal((char)0x81, &temp);
  result &= !strcmp(temp.ptr, "\\u0081");

  // Pretty JSON quoting must preserve a complete UTF-8 sequence, rather than
  // converting each byte into a different Latin-1 Unicode code point.
  bclear(&temp);
  cg_pretty_quote_plaintext("'\xe2\x80\xa2'", &temp, PRETTY_QUOTE_JSON);
  result &= !strcmp(temp.ptr, "\"'\xe2\x80\xa2'\"");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_empty_comment_marker_scan() {
  bool result = true;
  CHARBUF_OPEN(temp);

  // Empty and one-byte buffers contain no two-byte marker and must not make
  // the unsigned scan bound wrap around.
  cg_remove_slash_star_and_star_slash(&temp);
  result &= !strcmp(temp.ptr, "");
  bputc(&temp, '/');
  cg_remove_slash_star_and_star_slash(&temp);
  result &= !strcmp(temp.ptr, "/");

  // Keep the existing marker rewriting behavior covered at the same boundary.
  bclear(&temp);
  bprintf(&temp, "/* */");
  cg_remove_slash_star_and_star_slash(&temp);
  result &= !strcmp(temp.ptr, "/+ +/");

  CHARBUF_CLOSE(temp);
  return result;
}

static bool test_replacing_scanner_input_closes_previous_file() {
  FILE *first = tmpfile();
  FILE *second = tmpfile();
  Contract(first);
  Contract(second);

  cql_set_input_file(first);
  cql_set_input_file(second);
  return true;
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

  // Source-controlled provenance text must remain inside generated line
  // comments while preserving printable and UTF-8 content.
  TEST_ASSERT(test_comment_text_encoding());

  // Appending bytes already owned by a byte buffer must survive capacity
  // growth and reproduce the original bytes exactly.
  TEST_ASSERT(test_bytebuf_self_append());

  // Formatting must permit both the format and string arguments to refer to
  // the destination without overlap or lifetime violations.
  TEST_ASSERT(test_charbuf_format_aliases());

  // C control-byte escapes must not absorb a following hexadecimal digit.
  TEST_ASSERT(test_c_control_before_hex_digit());

  // JSON encoding must be independent of char signedness and preserve UTF-8
  // through the pretty-quoting path.
  TEST_ASSERT(test_json_utf8_portability());

  // Comment-marker removal must safely accept buffers shorter than a marker.
  TEST_ASSERT(test_empty_comment_marker_scan());

  // Replacing scanner input must close the previously owned stream so repeated
  // in-process compiler runs do not leak one descriptor per source file.
  TEST_ASSERT(test_replacing_scanner_input_closes_previous_file());
}

#endif
