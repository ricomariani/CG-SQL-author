/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// super simple linked list handlers

// Provides just enough structure for small AST node collections where order is either
// irrelevant (we later sort deterministically) or reversed via a final pass. Avoids
// pulling in dynamic array logic or realloc churn for tiny counts.

#pragma once

// no need to free this list anymore minipool will do it for
// you automatically at the end of a CQL run.
// @see minipool
typedef struct list_item {
  struct ast_node *ast;       // Borrowed pointer; lifetime managed by AST pool.
  struct list_item *next;     // Singly-linked; only prepend + reverse needed.
} list_item;

cql_noexport void add_item_to_list(list_item **head, struct ast_node *ast);
cql_noexport void reverse_list(list_item **head);
