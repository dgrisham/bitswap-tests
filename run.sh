#!/bin/sh

set -ex

./test.sh -t 2 -n 3 -s "identity" -r 10000 -f 'head -c 10000000 /dev/urandom' -d 'test-run'
# ./test.sh -t 2 -n 3 -s "Identity" -b 5000 -r 10000 -f 'head -c 10000000 /dev/urandom' -d 'test-run'
