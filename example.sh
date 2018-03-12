#!/bin/sh

set -ex

num_nodes="$1"
[[ -z "$num_nodes" ]] && num_nodes=3

yes | iptb init -n $num_nodes --type docker >/dev/null
iptb start

for ((i=0; i < num_nodes; i++)); do
    for ((j=i+1; j < num_nodes; j++)); do
        iptb connect $i $j
    done
done

# make a file with some text (TODO: way to do this without subshell?)
iptb run 0 sh -c 'echo "hola, mundo" > file'
# add file to ipfs, save cid
cid=$(iptb run 0 ipfs add -q file | tr -d '\r')

# have each of the other nodes request the file
for ((i=1; i < num_nodes; i++)); do
    iptb run $i ipfs cat "$cid"
done

# get header for bitswap stats
echo -n "id," > results
iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:)' | tr ' ' '_' | paste -sd ',' >> results

# gather stats for each node
for ((i=0; i < num_nodes; i++)); do
    iptb run $i sh -c "ipfs id --format='<id>,'" >> results
    iptb run $i sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' >> results
done

# the following commented command should be able to grab bitswap stats and do
# the relevant string manipulation, all on the docker image. but it's gross
#iptb for-each sh -c "ipfs id --format='<id>,' && ipfs bitswap stat | grep ':\|\[' | sed 's/.*\?: //' | sed 's/.*\?\[\(.*\?\)\]/\1/' | paste -sd ',' -" > results

iptb kill
