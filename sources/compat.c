/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"
#include "compat.h"
#include "minipool.h"

// duplicate a string into the string pool, these live until the end of the run
cql_noexport char *_Nonnull Strdup(CSTR _Nonnull s) {
  uint32_t length = (uint32_t)(strlen(s) + 1);
  void *result = minipool_alloc(str_pool, length);
  Invariant(result);
  return (char *)memcpy(result, s, length);
}

// Portable case-insensitive string comparison
cql_noexport int32_t StrCaseCmp(
  CSTR _Nonnull s1,
  CSTR _Nonnull s2)
{
  CSTR p1 = s1;
  CSTR p2 = s2;
  int32_t result;
  if (p1 == p2)
    return 0;

  while ((result = ToLower(*p1) - ToLower(*p2++)) == 0)
    if (*p1++ == '\0')
      break;

  return result;
}

// Portable case-insensitive string comparison with length
cql_noexport int32_t StrNCaseCmp(
  CSTR _Nonnull s1,
  CSTR _Nonnull s2, 
  size_t n)
{
  CSTR p1 = s1;
  CSTR p2 = s2;
  int32_t result = 0;

  for (; n != 0; --n) {
    if ((result = ToLower(*p1) - ToLower(*p2++)) != 0) {
        return result;
    }
    if (*p1++ == '\0')
        return 0;
  }

  return result;
}

// Portable case-insensitive string comparison at end
cql_noexport bool_t StrEndsWith(
  CSTR _Nonnull haystack,
  CSTR _Nonnull needle)
{
  size_t haystack_len = strlen(haystack);
  size_t needle_len = strlen(needle);

  return (haystack_len >= needle_len) &&
         (!StrNCaseCmp(haystack + haystack_len - needle_len, needle, needle_len));
}

// Portable versions of the character classification functions They are
// PascalCased to avoid conflict with the standard C library functions if they
// exist.

cql_noexport bool_t IsLower(char c) {
  return c >= 'a' && c <= 'z';
}

cql_noexport bool_t IsUpper(char c) {
  return c >= 'A' && c <= 'Z';
}

cql_noexport bool_t IsAlpha(char c) {
  return IsLower(c) || IsUpper(c);
}

cql_noexport bool_t IsDigit(char c) {
  return c >= '0' && c <= '9';
}

cql_noexport bool_t IsXDigit(char c) {
  return IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

cql_noexport char ToLower(char c) {
  return IsUpper(c) ? c + ('a' - 'A') : c;
}

cql_noexport char ToUpper(char c) {
  return IsLower(c) ? c - ('a' - 'A') : c;
}
