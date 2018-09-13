#!/bin/sh

# topology: fully connected
# all users upload unique file, all other users download each file
# result: aggregate stats; ledgers over time

body() {
    # Connect nodes
    persistent iptb connect

    # Add files
    declare -A cids
    # each node uploads a file
    for ((i=0; i < num_nodes; i++)); do
        for ((j=0; j < num_nodes; j++)); do
            [[ $i == $j ]] && continue
            iptb run $i -- sh -c "$file_cmd >file"
            cids[$j,$i]=$(iptb run $i -- sh -c "ipfs add -q file && rm file" | tail -n2)
        done
    done

    # Request files, gather stats
    for ((i=0; i < num_nodes; i++)); do
        for ((j=0; j < num_nodes; j++)); do
            [[ $j == $i ]] && continue
            echo "$i -- ipfs get ${cids[$i,$j]}"
        done
    done | iptb run |
           perl -p -e 's/node\[(\d)\].*?$/\1/' |
           sed -e '/^$/d' |
           grep -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
           sed 'N;N;s/\n/,/g' > "${results_prefix}aggregate"
}
