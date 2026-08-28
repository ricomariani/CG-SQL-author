/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#define CQL_OBJC_MIN_COMPILE
#include "cqlrt_cf/cqlrt_cf.h"

void cqlrt_cf_contract_test(cql_bool condition) {
  cql_contract(condition);
  cql_invariant(condition);
}
