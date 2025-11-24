#!/bin/bash

# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -o errexit -o nounset

S=$(cd $(dirname "$0"); pwd)

source $S/../common/test_helpers.sh || exit 1

while [ "${1:-}" != "" ]; do
  if [ "$1" == "--non_interactive" ]; then
    # shellcheck disable=SC2034
    NON_INTERACTIVE=1
    shift 1
  else
    echo "Usage: test.sh"
    echo "  --non_interactive"
    exit 1
  fi
done

pushd $S >/dev/null

echo "running demo"
set +e

# we have to filter out Nothing to be done because on
# MAC_OS the target 'all' gets `all' quotes hence
# spurious diff.  We just filter that line out to
# make the output canonical
bash ./demo.sh | grep -v "Nothing to be done" >$S/test.out
cat $S/test.out

on_diff_exit $S/test.out

echo "test passed"
