/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#define CQL_OBJC_MIN_COMPILE
#include "cqlrt_cf/cqlrt_cf.h"

// This is a compile-only portability probe for the CoreFoundation runtime
// header.  CQL_OBJC_MIN_COMPILE replaces Apple framework types with minimal
// stand-ins, allowing non-macOS CI to verify that both always-on macros are
// declared, accept a normal C expression, and remain syntactically valid under
// NDEBUG.  It does not replace a full macOS CoreFoundation build or runtime test.
void cqlrt_cf_contract_test(cql_bool condition) {
  cql_contract(condition);
  cql_invariant(condition);
}
