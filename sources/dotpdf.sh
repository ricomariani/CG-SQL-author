#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

./out/cql --dot <"$1" >"out/$1.dot" || exit 1
dot "out/$1.dot" -Tpdf -o "out/$1.pdf" || exit 1
echo "Created out/$1.dot and made out/$1.pdf with it."
open "out/$1.pdf"
