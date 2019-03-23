#!/bin/sh

# topology: fully connected
# all users upload unique file, all other users download each file
# result: aggregate stats; ledgers over time

body() {
    # connect nodes
    iptb connect

    # Add files
    declare -A cids
    declare -Ag uploads
    # each node uploads a file
    for ((i=0; i < num_nodes; i++)); do
        for ((j=0; j < num_nodes; j++)); do
            [[ $i == $j ]] && continue
            iptb run $i -- sh -c "$file_cmd >file"
            cids[$j,$i]=$(iptb run $i -- sh -c "ipfs add -q file && rm file" | tail -n2)
            if [[ -z ${uploads[$i]} ]]; then
                uploads[$i]='{"cid":"'"${cids[$j,$i]}"'"}'
            else
                uploads[$i]+=',{"cid":"'"${cids[$j,$i]}"'"}'
            fi
        done
    done

    # Request files, gather stats
    declare -Ag dl_times
    while IFS=$'\n' read -r key; do
        read -r val
        if [[ -z ${dl_times[$key]} ]]; then
            dl_times[$key]=$val
        else
            dl_times[$key]+=",$val"
        fi
    done <<< $(
        for ((i=0; i < num_nodes; i++)); do
            for ((j=0; j < num_nodes; j++)); do
                [[ $j == $i ]] && continue
                echo "$i -- ipfs get ${cids[$i,$j]}"
            done
        done | iptb run |
               perl -p -e 's/node\[(\d)\].*?$/\1/' |
               sed -e '/^$/d' |
               grep -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
               sed -r 'N;N;s/([0-9]+)\n([A-Za-z0-9]+)\n([0-9ms]+)/\1\n{"block":"\2","time":"\3"}/'
    )
}
