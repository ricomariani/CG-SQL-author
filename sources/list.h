/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// super simple linked list handlers

#pragma once

// no need to free this list anymore minipool will do it for
// you automatically at the end of a CQL run.
// @see minipool
typedef struct list_item {
  struct ast_node *_Nonnull ast;
  struct list_item *_Nullable next;
} list_item;

cql_noexport void add_item_to_list(CqlState* _Nonnull CS, list_item *_Nonnull*_Nonnull head, struct ast_node *_Nonnull ast);
cql_noexport void reverse_list(list_item *_Nonnull*_Nonnull head);
