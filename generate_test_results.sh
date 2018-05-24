#!/bin/sh

./template.sh -n 3 -c 'echo "hola, mundo"' -o results/holamundo
./template.sh -n 3 -c 'head -c 1000000 /dev/urandom' -o results/medium_random
