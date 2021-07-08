#!/bin/bash

set -e 
HOST='127.0.0.1'
PORT=2525
USER='apc'
PASSWD='apc'
FILE='file'
NO_TESTS=50
TEST_DIR=_tmp_client
SERVER_DIR=_tmp_server

mkdir -p $SERVER_DIR
mkdir -p $TEST_DIR

for NO in $(eval echo {1..$NO_TESTS})
do
cd $TEST_DIR
FILE_NAME="${FILE}${NO}.txt"
echo "This is a test1" >> $FILE_NAME
date=$(date +%H:%M:%S:%N)
echo "$date -- Tring to put $FILE_NAME" >> logfile.txt
ftp -vp -n $HOST $PORT <<END_SCRIPT
quote USER $USER
quote PASS $PASSWD
put $FILE_NAME
quit
END_SCRIPT

rm $FILE_NAME
cd ..
sleep 0.05
done

FILES_MISSING=$(($NO_TESTS-$(ls -1 $SERVER_DIR/ | wc -l)))
rm -rf $TEST_DIR
rm -rf $SERVER_DIR/*
echo "DONE. Files Missing = $FILES_MISSING/$NO_TESTS"

exit 0