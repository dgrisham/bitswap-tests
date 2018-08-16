#!/bin/sh

# ./template3.sh -n 3 -s -b "100 100 100" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "100 100 150" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "100 100 200" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "100 150 100" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "100 200 100" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium

# ./template3.sh -n 3 -s -b "1000 1000 1000" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "1000 1000 1500" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "1000 1000 2000" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "1000 1500 1000" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
# ./template3.sh -n 3 -s -b "1000 2000 1000" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium

./template3.sh -n 3 -s -b "1000 1500 2000" -c 'head -c 1000000000 /dev/urandom' -d results-3/rrq/random-medium
./template3.sh -n 3 -s -b "1000 1500 2000" -c 'head -c 100000000 /dev/urandom' -d results-3/rrq/random-small
./template3.sh -n 3 -s -b "1400 1500 1600" -c 'head -c 100000000 /dev/urandom' -d results-3/rrq/random-small
./template3.sh -n 3 -s -b "10000 15000 20000" -c 'head -c 10000000000 /dev/urandom' -d results-3/rrq/random-large

# ./template.sh -n 3 -s -b "100 100 100" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "100 100 150" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "100 100 200" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "100 150 100" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "100 200 100" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

# ./template.sh -n 3 -s -b "1000 1000 1000" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "1000 1000 1500" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "1000 1000 2000" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "1000 1500 1000" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
# ./template.sh -n 3 -s -b "1000 2000 1000" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

#./template.sh -n 3 -c 'echo "hola, mundo"' -d results/prq/holamundo
#./template.sh -n 3 -c 'head -c 100000000 /dev/urandom' -d results/prq/random-small
#./template.sh -n 3 -c 'head -c 1000000000 /dev/urandom' -d results/prq/random-medium
#./template.sh -n 3 -c 'head -c 10000000000 /dev/urandom' -d results/prq/random-large

#./template.sh -n 3 -s -c 'echo "hola, mundo"' -d results/rrq/holamundo
#./template.sh -n 3 -s -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

#./template.sh -n 3 -s -b 10 -c 'echo "hola, mundo"' -d results/rrq/holamundo
#./template.sh -n 3 -s -b 10 -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b 10 -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b 10 -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

#./template.sh -n 3 -s -b "10 20 10" -c 'echo "hola, mundo"' -d results/rrq/holamundo
#./template.sh -n 3 -s -b "10 20 10" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 20 10" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 20 10" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

#./template.sh -n 3 -s -b "10 10 20" -c 'echo "hola, mundo"' -d results/rrq/holamundo
#./template.sh -n 3 -s -b "10 10 20" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 10 20" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 10 20" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large

#./template.sh -n 3 -s -b "10 20 20" -c 'echo "hola, mundo"' -d results/rrq/holamundo
#./template.sh -n 3 -s -b "10 20 20" -c 'head -c 100000000 /dev/urandom' -d results/rrq/random-small
#./template.sh -n 3 -s -b "10 20 20" -c 'head -c 1000000000 /dev/urandom' -d results/rrq/random-medium
#./template.sh -n 3 -s -b "10 20 20" -c 'head -c 10000000000 /dev/urandom' -d results/rrq/random-large
