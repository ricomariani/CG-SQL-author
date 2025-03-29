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
#include "cg_common.h"
#include "unit_tests.h"

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

cql_noexport void run_unit_tests() {
  TEST_ASSERT(test_strdup__empty_string());
  TEST_ASSERT(test_strdup__one_character_string());
  TEST_ASSERT(test_strdup__long_string());
  TEST_ASSERT(test_strcasecmp_empty_strings());
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_less_than());
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_greater_than());
  TEST_ASSERT(test_strcasecmp_one_char_strings__result_is_equals());
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_less_than());
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_greater_than());
  TEST_ASSERT(test_strcasecmp_long_strings__result_is_equals());
  TEST_ASSERT(test_strcasecmp_different_length_strings__result_is_less_than());
  TEST_ASSERT(test_strcasecmp_different_length_strings__result_is_greater_than());
  TEST_ASSERT(test_strncasecmp__empty_strings__zero_cmp_size__result_is_equals());
  TEST_ASSERT(test_strncasecmp__empty_strings__past_length_cmp_size__result_is_equals());
  TEST_ASSERT(test_strncasecmp__one_char_strings__zero_cmp_size__result_is_equals());
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_less_than());
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_greater_than());
  TEST_ASSERT(test_strncasecmp__one_char_strings__past_length_cmp_size__result_is_equals());
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_less_than());
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_greater_than());
  TEST_ASSERT(test_strncasecmp__long_strings__past_length_cmp_size__result_is_equals());
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_less_than());
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_greater_than());
  TEST_ASSERT(test_strncasecmp__long_strings__shorter_than_length_cmp_size__result_is_equals());
  TEST_ASSERT(test_frag_tricky_case());
  TEST_ASSERT(test_sha256_example1());
  TEST_ASSERT(test_sha256_example2());
  TEST_ASSERT(test_sha256_example3());
  TEST_ASSERT(test_sha256_example4());
  TEST_ASSERT(test_sha256_example5());
  TEST_ASSERT(test_sha256_example6());
  TEST_ASSERT(test_unknown_macro());
  TEST_ASSERT(test_Dirname());
}

#endif
