#!/bin/sh

set -ex

yes | iptb init -n 3 --type docker >/dev/null
iptb start

iptb connect 0 1
iptb connect 0 2
iptb connect 1 2

# make a file with some text (TODO: way to do this without subshell?)
iptb run 0 sh -c 'echo "hola, mundo" > file'
# add file to ipfs, save cid
cid=$(iptb run 0 ipfs add -q file | tr -d '\r')

# get the file from other two nodes
for i in {1..2}; do
    iptb run $i ipfs cat "$cid"
done

# get header for bitswap stats
echo -n "id," > results
iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:)' | tr ' ' '_' | paste -sd ',' >> results

# gather stats for each node
for i in {0..2}; do
    iptb run $i sh -c "ipfs id --format='<id>,'" >> results
    iptb run $i sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' >> results
done

# the following commented command should be able to grab bitswap stats and do
# the relevant string manipulation, all on the docker image. but it's gross
#iptb for-each sh -c "ipfs id --format='<id>,' && ipfs bitswap stat | grep ':\|\[' | sed 's/.*\?: //' | sed 's/.*\?\[\(.*\?\)\]/\1/' | paste -sd ',' -" > results

iptb kill
