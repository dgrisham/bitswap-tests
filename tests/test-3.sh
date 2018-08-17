#!/bin/sh

# topology: fully connected
# all users upload unique file, all other users download each file
# result: aggregate stats; TODO

connect() {
    for ((i=0; i < num_nodes; i++)); do
        for ((j=i+1; j < num_nodes; j++)); do
            iptb connect $i $j
        done
    done
}

add() {
    declare -Ag cids
    # each node uploads a file
    for ((i=0; i < num_nodes; i++)); do
        for ((j=0; j < num_nodes; j++)); do
            [[ $i == $j ]] && continue
            iptb run $i sh -c "$creation_cmd >file"
            cids[$j,$i]=$(iptb run $i ipfs add -q ./file | tr -d '\r')
        done
    done
}

request() {
    pid_infs=()
    for ((i=0; i < num_nodes; i++)); do
        ledger_file="${results_prefix}ledgers_$i"
        [[ -f "$ledger_file" ]] && rm "$ledger_file"
        touch "$ledger_file"
        echo 'id,debt_ratio,exchanges,bytes_sent,bytes_received' > "$ledger_file"
        stop=0
        until [[ "$stop" == 1 ]]; do
            # once termination signal is received, finish current iteration of outer loop then stop the loop
            trap "stop=1" SIGTERM
            for ((j=0; j < num_nodes; j++)); do
                [[ $j == $i ]] && continue
                # iptb run 0 -n ipfs bitswap ledger ${nodeIds[j]} >> "$ledger_file" || true
                ledger="$(iptb run $i -n ipfs bitswap ledger ${nodeIds[j]})"
                # echo "$ledger" >> "${results_prefix}ledgers_$i"
                echo "$ledger" | awk '{print $NF}' | sed '1s/>//' | paste -sd ',' | tr -d '\r'|  sed 's/,$//' >> "$ledger_file"
            done
        done &
        pid_infs+=($!)
    done

    pid_gets=()
    dl_times_tmp=$(mktemp)
    touch "$dl_times_tmp"
    for ((i=0; i < num_nodes; i++)); do
        for ((j=0; j < num_nodes; j++)); do
            [[ $j == $i ]] && continue
            { out=$(iptb run $i -n ipfs get "${cids[$i,$j]}");
              flock "$dl_times_tmp" sh -c "echo -n \"$i,$j\": >> $dl_times_tmp ; echo \"$out\" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev >> $dl_times_tmp";
            } &
            pid_gets+=($!)
        done
    done

    # wait for `ipfs get` loops to finish
    wait "${pid_gets[@]}"
    # stop the infinite ledger loops
    kill -TERM "${pid_infs[@]}"
    wait "${pid_infs[@]}"
}

gather_results() {
    re='([[:digit:]]+),([[:digit:]]+):([[:alnum:]]+)'
    declare -A dl_times
    while IFS= read -r line _; do
        if [[ $line =~ $re ]]; then
            dl_times["${BASH_REMATCH[1]}","${BASH_REMATCH[2]}"]="${BASH_REMATCH[3]}"
        else
            echo "error: dl_times_tmp line has wrong format: $line"
        fi
    done <"$dl_times_tmp"

    # get header for bitswap stats
    echo -n "peer," > "${results_prefix}aggregate"
    iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:| \[)' | tr ' ' '_' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
    echo 'dl_time(s)' >> "${results_prefix}aggregate"

    # gather stats for each node
    for ((i=0; i < num_nodes; i++)); do
        echo -n "$(iptb get id $i)," >> "${results_prefix}aggregate"
        #iptb run $i sh -c "ipfs id --format='<id>,'" >> "${results_prefix}aggregate"
        iptb run "$i" sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
        for ((j=0; j < num_nodes; j++)); do
            [[ $j == $i ]] && continue
            delim=','
            if (( $j == $((num_nodes-1)) || ( $j == $((num_nodes-2)) && $i == $((num_nodes-1)) ) )); then
                delim='\n'
            fi
            echo -ne "${dl_times[$i,$j]}$delim" >> "${results_prefix}aggregate"
        done
    done
}
