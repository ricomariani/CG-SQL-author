#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

O="out"
T="test"
CQL_FILE="$O/generated_upgrade_test.cql"
SCHEMA_FILE="$O/generated_upgrade_test_schema.sql"
TEST_PREFIX="test"
CQL="./$O/cql"
ERROR_TRACE=0

DIR="$( dirname -- "$0"; )"

cd "${DIR}/.." || exit

# shellcheck disable=SC1091
source common/test_helpers.sh || exit 1

while [ "$1" != "" ]
do
  if [ "$1" == "--coverage" ]
  then
     MAKE_COVERAGE_ARGS="COVERAGE=1"
     shift 1
  else
     echo "Usage: upgrade_test.sh  [--coverage]"
     exit 1
  fi
done

set_exclusive() {
  if [ $1 -eq 4 ]; then
    exclusive="--schema_exclusive"
  else
    exclusive=""
  fi
}

# Delete databases (if they exist).
rm -f $O/*.db

# Delete upgraders if they exist
rm -f $O/generated_upgrader*
rm -f $O/upgrade?

echo "compiling the shared schema validator to C"

cp upgrade/upgrade_validate.sql "$O/upgrade_validate.sql"

 # set ERROR_TRACE to get verbose tracing in the upgrader
if [ "${ERROR_TRACE}" != "0" ]
then
   cat upgrade/errortrace.inc "$O/upgrade_validate.sql" >"$O/x"
   mv "$O/x" "$O/upgrade_validate.sql"
fi

if ! ${CQL} --in $O/upgrade_validate.sql --cg $O/upgrade_validate.h $O/upgrade_validate.c; then
  echo failed compiling upgrade validator
  echo ${CQL} --in upgrade/upgrade_validate.sql --cg $O/upgrade_validate.h $O/upgrade_validate.c
  exit 1;
fi

echo "creating the upgrade to v[n] schema upgraders"

for i in {0..4}
do
  set_exclusive $i

  if ! ${CQL} ${exclusive} --in "upgrade/SchemaPersistentV$i.sql" --rt schema_upgrade --cg "$O/generated_upgrader$i.sql" --global_proc "$TEST_PREFIX"; then
    echo ${CQL} --in "upgrade/SchemaPersistentV$i.sql" --rt schema_upgrade --cg "$O/generated_upgrader$i.sql" --global_proc "$TEST_PREFIX"
    echo "failed generating upgrade to version $i CQL"
    exit 1
  fi

  # set ERROR_TRACE to get verbose tracing in the upgrader
  if [ "${ERROR_TRACE}" != "0" ]
  then
    cat upgrade/errortrace.inc "$O/generated_upgrader$i.sql" >"$O/x"
    mv "$O/x" "$O/generated_upgrader$i.sql"
  fi

  if ! ${CQL} --in "$O/generated_upgrader$i.sql" --compress --cg "$O/generated_upgrade$i.h" "$O/generated_upgrade$i.c"; then
    echo ${CQL} --in "$O/generated_upgrader$i.sql" --compress --cg "$O/generated_upgrade$i.h" "$O/generated_upgrade$i.c"
    echo "failed C from the upgrader $i"
    exit 1
  fi
done

# compile the upgraders above to executables upgrade0-4

if ! make ${MAKE_COVERAGE_ARGS} upgrade_test; then
  echo make ${MAKE_COVERAGE_ARGS} upgrade_test
  echo failed compiling upgraders
fi

# now do the basic validation, can we create a schema of version n?
for i in {0..4}
do
  echo "testing upgrade to v$i from scratch"
  if ! "$O/upgrade$i" "$O/test_$i.db" > "$O/upgrade_schema_v$i.out"; then
    echo "$O/upgrade$i" "$O/test_$i.db" ">" "$O/upgrade_schema_v$i.out"
    echo "failed generating schema from scratch"
    echo "see log file above for details"
    exit 1
  fi

  on_diff_exit "upgrade_schema_v$i.out"
done

# now we'll try various previous schema combos with the current upgrader to make sure the work

for i in {1..4}
do
  (( j=i-1 ))
  echo "Verifying previous schema $j vs. final schema $i is ok"

  # Generate schema file with previous schema
  cat "upgrade/SchemaPersistentV$i.sql" > "$SCHEMA_FILE"
  echo "@previous_schema;" >> "$SCHEMA_FILE"
  cat "upgrade/SchemaPersistentV$j.sql" >> "$SCHEMA_FILE"

  set_exclusive $i

  # Generate upgrade CQL.
  # shellcheck disable=SC2086
  if ! ${CQL} ${exclusive} --in "${SCHEMA_FILE}" --cg "${CQL_FILE}" --rt schema_upgrade --global_proc "${TEST_PREFIX}"; then
    echo "Failed to generate upgrade CQL."
    echo "${CQL} ${exclusive}" --in "${SCHEMA_FILE}" --cg "${CQL_FILE}" --rt schema_upgrade --global_proc "${TEST_PREFIX}"
    exit 1
  fi

  # set ERROR_TRACE to get verbose tracing in the upgrader
  if [ "${ERROR_TRACE}" != "0" ]
  then
    cat upgrade/errortrace.inc "${CQL_FILE}" >"$O/x"
    mv "$O/x" "${CQL_FILE}"
  fi

  if ! diff "$O/generated_upgrader$i.sql" "${CQL_FILE}" ; then
    echo diff "$O/generated_upgrader$i.sql" "${CQL_FILE}"
    echo "The upgrader from $j to $i was different than with no previous schema specified $i!"
    exit 1
  fi
done

for i in {0..4}
do
  for j in {0..4}
  do
    if [ $j -le $i ]; then

      echo "Upgrade from nothing to v$j, then to v$i -- must match direct update to v$i"

      rm -f "$O/test.db"
      if ! $O/upgrade$j "$O/test.db" > $O/partial.out; then
        echo $O/upgrade$j "$O/test.db > $O/partial.out"
        echo "initial step to version $j" failed
      fi

      if ! diff "$O/upgrade_schema_v$j.out" "$O/partial.out";  then
        echo diff "$O/upgrade_schema_v$j.out" "$O/partial.out"
        echo going from nothing to $j was different when the upgrader was run again!
        exit 1
      fi

      if ! $O/upgrade$i "$O/test.db" > $O/final.out; then
        echo $O/upgrade$i "$O/test.db > $O/final.out"
        echo "initial step to version $i" failed
      fi

      if ! diff "$O/upgrade_schema_v$i.out" "$O/final.out";  then
        echo diff "$O/upgrade_schema_v$i.out" "$O/final.out"
        echo going from $j to $i was different than going directly to $i
        exit 1
      fi
    fi
  done
done

# ----- END UPGRADE TESTING -----

# ----- BEGIN DOWNGRADE TESTING -----

echo "Testing downgrade"

# Run the downgrade test binary on the test db which now has the v3 format
# the upgrader needed was already built and the downgrade test hardness was already linked
if ! (./$O/downgrade_test "$O/test.db"); then
  echo "Downgrade test failed."
  echo "./$O/downgrade_test $O/test.db"
  exit 1
fi

# ----- END DOWNGRADE TESTING -----
