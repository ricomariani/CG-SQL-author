/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"

cql_noexport const rtdata *_Nullable find_rtdata(CqlState* _Nonnull CS, CSTR _Nonnull name);
cql_noexport void rt_cleanup(CqlState* _Nonnull CS);
