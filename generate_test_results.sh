#!/bin/sh

./template.sh -n 3 -c 'echo "hola, mundo"' -o results/holamundo
./template.sh -n 3 -c 'head -c 1000000000 /dev/urandom' -o results/random-medium
./template.sh -n 3 -c 'head -c 10000000000 /dev/urandom' -o results/random-large

./template.sh -n 3 -c 'echo "hola, mundo"' -o results/rrq/holamundo
./template.sh -n 3 -c 'head -c 1000000000 /dev/urandom' -o results/rrq/random-medium
./template.sh -n 3 -c 'head -c 10000000000 /dev/urandom' -o results/rrq/random-large
