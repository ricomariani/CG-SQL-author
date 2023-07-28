#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

(echo -n "<!--- @" ; echo "generated -->") >internal.md
for f in ../int*.md
do
  ( cat "$f"; echo ""; echo "" ) >>internal.md
done

pandoc --toc -s -f markdown -t html --metadata title="CQL Internals" internal.md -o internal.html
