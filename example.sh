#!/bin/sh

set -ex

yes | iptb init -n 3 --type docker >/dev/null
iptb start

iptb connect 0 1
iptb connect 0 2
iptb connect 1 2

# make a file with some text (TODO: better way to do this?)
iptb run 0 sh -c 'echo "hola, mundo" > file'
# add file to ipfs, save cid
cid=$(iptb run 0 ipfs add -q file)
# get the file from other two nodes

for i in {1..2}; do
    iptb run $i ipfs cat $cid
done

iptb for-each ipfs bitswap stat > results

iptb kill
