#!/bin/sh

./template.sh -n 3 -c 'echo "hola, mundo"' -d results/prq/holamundo
./template.sh -n 3 -c 'head -c 100000000 /dev/urandom' -d results/prq/random-small
./template.sh -n 3 -c 'head -c 1000000000 /dev/urandom' -d results/prq/random-medium
#./template.sh -n 3 -c 'head -c 10000000000 /dev/urandom' -d results/prq/random-large

./template.sh -n 3 -s -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
./template.sh -n 3 -s -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

./template.sh -n 3 -s -b 10 -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -b 10 -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b 10 -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b 10 -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

./template.sh -n 3 -s -b "10 20 10" -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -b "10 20 10" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 20 10" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 20 10" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

./template.sh -n 3 -s -b "10 10 20" -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -b "10 10 20" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 10 20" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 10 20" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

./template.sh -n 3 -s -b "10 20 20" -c 'echo "hola, mundo"' -d results/rrq/holamundo
./template.sh -n 3 -s -b "10 20 20" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 20 20" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 20 20" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
