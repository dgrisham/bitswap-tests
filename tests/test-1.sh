#!/bin/sh

# topology: user 0 connected to users 1 through n
# all users upload unique files, user 0 downloads 1 through n's files while
# 1 through n download 0's
# result: aggregate stats; time series of user 0's ledgers

body() {
    # connect nodes
    until iptb connect 0 "[1,$((num_nodes-1))]"; do :; done

    declare -a cids
    declare -ag uploads
    for ((i=0; i < num_nodes; i++)); do
        iptb run $i -- sh -c "$file_cmd >file"
        # store cids of uploaded files
        cids[$i]=$(iptb run $i -- sh -c "ipfs add -q file && rm file" | tail -n2)
        if [[ -z "${uploads[i]}" ]]; then
            uploads[$i]='{"cid":"'"${cids[i]}"'"}'
        else
            uploads[$i]+=',{"cid":"'"${cids[i]}"'"}'
        fi
    done

    getCmds=""
    for ((i=1; i < num_nodes; i++)); do
        getCmds+="0 -- ipfs get ${cids[i]}\n"
    done
    getCmds+="[1,$((num_nodes-1))] -- ipfs get ${cids[0]}"

    # echo -e "$getCmds" | iptb run |
    #    perl -p -e 's/node\[(\d)\].*?$/\1/' |
    #    sed -e '/^$/d' |
    #    grep -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
    #    sed 'N;N;s/\n/,/g' > "${results_prefix}aggregate"

    # Request files, gather stats
    declare -Ag dl_times
    while IFS=$'\n' read -r key; do
        read -r val
        if [[ -z ${dl_times[$key]} ]]; then
            dl_times[$key]=$val
        else
            dl_times[$key]+=",$val"
        fi
    done <<< $(echo -e "$getCmds" | iptb run |
               perl -p -e 's/node\[(\d)\].*?$/\1/' |
               sed -e '/^$/d' |
               grep -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
               sed -r 'N;N;s/([0-9]+)\n([A-Za-z0-9]+)\n([0-9ms]+)/\1\n{"block":"\2","time":"\3"}/'
    )
}
