#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# exit when any command fails
set -e

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..

rm -rf $O
mkdir -p $O

if [ "${JAVA_HOME}" == "" ] ;
then
  echo "JAVA_HOME must be set to your JDK dir"
  echo  "e.g. JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-10.0.1.jdk/Contents/Home"
  echo  "e.g. JAVA_HOME=/lib/jvm/java-16-openjdk-amd64/"
  echo  "e.g. JAVA_HOME=/lib/jvm/java-1.19.0-openjdk-amd64/"
  exit 1
fi

echo "java located at: ${JAVA_HOME}"

CC="cc -g"

if [ "$(uname)" == "Linux" ];
then
  # linux path variation and -fPIC for .so output
  CC="${CC} -I $O -I $R -I${JAVA_HOME}/include -I${JAVA_HOME}/include/linux -fPIC"
  SUFFIX=so
else
  # assuming clang elsewhere (e.g. Mac)
  CC="${CC} -I $O -I $R -I${JAVA_HOME}/include -I${JAVA_HOME}/include/darwin"
  SUFFIX=jnilib
fi

if [ "${SQLITE_PATH}" != "" ] ;
then
  echo building sqlite amalgam
  CC="${CC} -I${SQLITE_PATH}"
  SQLITE_LINK=sqlite3-all.o
  ${CC} -c -o $O/sqlite3-all.o ${SQLITE_PATH}/sqlite3-all.c
else
  SQLITE_LINK=-lsqlite3
fi

echo "building cql"
(cd $O/../.. ; make)
CQL=$R/out/cql

echo "making directories"

mkdir -p $O/sample

echo generating stored procs
cp Sample.sql $O
pushd $O >/dev/null
${CQL} --in Sample.sql --cg Sample.h Sample.c
${CQL} --in Sample.sql --rt json_schema --cg Sample.json
../cqljava.py Sample.json --package sample --class SampleJNI >sample/SampleJNI.java
../cqljava.py Sample.json --emit_c --package sample --class SampleJNI --jni_header sample_SampleJNI.h --cql_header Sample.h >sample_SampleJNI.c
popd >/dev/null

echo "regenerating JNI .h file"
javac -h $O -d $O com/acme/cgsql/CQLResultSet.java
javac -h $O -d $O com/acme/cgsql/CQLDb.java
javac -h $O -d $O out/sample/SampleJNI.java

echo "adding license headers to generated files"

cat <<EOF >$O/__tmp1
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

EOF

cat $O/__tmp1 $O/com_acme_cgsql_CQLResultSet.h >$O/__tmp2
mv $O/__tmp2 $O/com_acme_cgsql_CQLResultSet.h

cat $O/__tmp1 $O/com_acme_cgsql_CQLDb.h >$O/__tmp2
mv $O/__tmp2 $O/com_acme_cgsql_CQLDb.h

cat $O/__tmp1 $O/sample_SampleJNI.h >$O/__tmp2
mv $O/__tmp2 $O/sample_SampleJNI.h

rm $O/__tmp1

echo "compiling native code"
pushd $O >/dev/null
${CC} -c ../std_jni/com_acme_cgsql_CQLResultSet.c
${CC} -c ../std_jni/com_acme_cgsql_CQLDb.c
${CC} -c sample_SampleJNI.c
${CC} -c Sample.c

${CC} -o libSampleJNI.${SUFFIX} -shared sample_SampleJNI.o Sample.o $R/cqlrt.c ${SQLITE_LINK}
${CC} -o libCQLResultSet.${SUFFIX} -shared com_acme_cgsql_CQLResultSet.o $R/cqlrt.c ${SQLITE_LINK}
${CC} -o libCQLDb.${SUFFIX} -shared com_acme_cgsql_CQLDb.o $R/cqlrt.c ${SQLITE_LINK}

popd >/dev/null

echo making .class files
javac -d $O \
  MyJava.java \
  com/acme/cgsql/CQLDb.java \
  com/acme/cgsql/CQLResultSet.java \
  com/acme/cgsql/CQLViewModel.java \
  com/acme/cgsql/CQLEncodedString.java \
  $O/sample/SampleJNI.java

echo "executing"
(
  cd $O 
  java -Djava.library.path=. \
    MyJava \
    sample/SampleJNI \
    CQLViewModel \
    com/acme/cgsql/CQLResultSet \
    com/acme/cgsql/CQLDb
)

echo "run clean.sh to remove build artifacts"
echo "done"
