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
# persistent iptb run -- ipfs log level engine debug
persistent iptb connect

iptb run --longopts detach -- sh -c "ipfs log tail >ipfs_log"

iptb run 0 -- sh -c "$file_cmd >file"
cid=$(iptb run 0 -- ipfs add -q ./file | tail -n2)
# cid=$(iptb run 0 -- ipfs add -q ./file | tail -n2 | tr -d '\r')
iptb run 1 -- ipfs get $cid

for ((i=0; i < num_nodes; i++)); do
    docker cp $(cat $IPTB_ROOT/testbeds/default/$i/dockerid):ipfs_log logs_$i
    sed -i '/DebtRatio/!d' logs_$i
done

iptb stop
