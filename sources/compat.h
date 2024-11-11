/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

cql_noexport char *_Nonnull Strdup(const char *_Nonnull s);
cql_noexport int32_t StrCaseCmp(const char *_Nonnull s1, const char *_Nonnull s2);
cql_noexport int32_t StrNCaseCmp(const char *_Nonnull s1, const char *_Nonnull s2, size_t n);
cql_noexport bool_t StrEndsWith(const char *_Nonnull haystack, const char *_Nonnull needle);

// On Windows, the normal versions of some of these function assert on non-ASCII
// characters when using a debug CRT library. These alternative versions allow
// us to avoid "ctype.h" entirely.
cql_noexport bool_t IsAlpha(char c);
cql_noexport bool_t IsDigit(char c);
cql_noexport bool_t IsLower(char c);
cql_noexport bool_t IsUpper(char c);
cql_noexport bool_t IsXDigit(char c);
cql_noexport char ToLower(char c);
cql_noexport char ToUpper(char c);
