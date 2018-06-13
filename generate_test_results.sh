#!/bin/sh

./template.sh -n 3 -c 'echo "hola, mundo"' -d results/holamundo
./template.sh -n 3 -c 'head -c 100000000 /dev/urandom' -d results/random-small
./template.sh -n 3 -c 'head -c 1000000000 /dev/urandom' -d results/random-medium
./template.sh -n 3 -c 'head -c 10000000000 /dev/urandom' -d results/random-large

./template.sh -n 3 -s -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
./template.sh -n 3 -s -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
./template.sh -n 3 -s -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
