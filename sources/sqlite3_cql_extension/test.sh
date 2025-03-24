#!/bin/bash

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
bash ./demo.sh > $S/test.out
cat $S/test.out

on_diff_exit $S/test.out

echo "test passed"
