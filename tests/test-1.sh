#!/bin/sh

# topology: user 0 connected to users 1 through n
# all users upload unique files, user 0 downloads 1 through n's files while
# 1 through n download 0's
# result: aggregate stats; time series of user 0's ledgers

body() {
    # connect nodes
    iptb connect 0 "[1,$((num_nodes-1))]"

    declare -a cids
    for ((i=0; i < num_nodes; i++)); do
        iptb run $i -- sh -c "$file_cmd >file"
        # store cids of uploaded files
        cids[$i]=$(iptb run $i -- sh -c "ipfs add -q file && rm file" | tail -n2)
    done

    getCmds=""
    for ((i=1; i < num_nodes; i++)); do
        getCmds+="0 -- ipfs get ${cids[i]}\n"
    done
    getCmds+="[1,$((num_nodes-1))] -- ipfs get ${cids[0]}"

    echo -e "$getCmds" | iptb run |
       perl -p -e 's/node\[(\d)\].*?$/\1/' |
       sed -e '/^$/d' |
       grep -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
       sed 'N;N;s/\n/,/g' > "${results_prefix}aggregate"
}
