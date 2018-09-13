#!/bin/bash

set -ex

num_nodes=2

persistent() {
    until $@; do :; done
}

while getopts "f:" opt; do
    case $opt in
        f)
            [[ -z "$OPTARG" ]] && echo "Invalid file creation command." && exit 1
            file_cmd="$OPTARG"
            ;;
    esac
done
shift $((OPTIND-1))

yes | iptb auto --type dockeripfs --count $num_nodes
iptb start --wait
persistent iptb connect

for ((i=0; i< num_nodes; i++)); do
    docker exec --detach $(iptb attr get $i container) sh -c "ipfs log tail >ipfs_log"
done

declare -Ag cids
# each node uploads a file
for ((i=0; i < num_nodes; i++)); do
    for ((j=0; j < num_nodes; j++)); do
        [[ $i == $j ]] && continue
        iptb run $i -- sh -c "$file_cmd >file_for_$j"
        cids[$j,$i]=$(iptb run $i -- ipfs add -q "file_for_$j" | tail -n2)
    done
done

for ((i=0; i < num_nodes; i++)); do
    for ((j=0; j < num_nodes; j++)); do
        [[ $j == $i ]] && continue
        echo "$i -- ipfs get ${cids[$i,$j]}"
    done
done | iptb run

for ((i=0; i < num_nodes; i++)); do
    docker cp $(iptb attr get $i container):ipfs_log logs_$i
    sed -i '/DebtRatio/!d' logs_$i
done

iptb stop
