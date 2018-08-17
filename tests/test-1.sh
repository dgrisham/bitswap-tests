#!/bin/sh

connect() {
    for ((i=0; i < num_nodes; i++)); do
        for ((j=i+1; j < num_nodes; j++)); do
            iptb connect $i $j
        done
    done
}

add() {
    iptb run 0 sh -c "$creation_cmd >file"
    cid=$(iptb run 0 ipfs add -q ./file | tr -d '\r')
}

request() {
    dl_times[0]='LOCAL'
    # have each of the other nodes request the file
    for ((i=1; i < num_nodes; i++)); do
        # collect ledger data while downloading file
        ledger_file="${results_prefix}ledgers_$i"
        [[ -f "$ledger_file" ]] && rm "$ledger_file"
        echo 'id,debt_ratio,exchanges,bytes_sent,bytes_received' > "$ledger_file"
        stop=0
        while [ $stop -eq 0 ]; do
            # once termination signal is received, finish current iteration of outer loop then stop the loop
            trap "stop=1" SIGTERM
            for ((j=0; j < num_nodes; j++)); do
                [[ $i == $j ]] && continue
                ledger="$(iptb run $i -n ipfs bitswap ledger ${nodeIds[j]})"
                # echo "$ledger" >> "${results_prefix}ledgers_$i"
                echo "$ledger" | awk '{print $NF}' | sed '1s/>//' | paste -sd ',' | tr -d '\r'|  sed 's/,$//' >> "${results_prefix}ledgers_$i"
            done
        done &

        out=$(iptb run $i ipfs get "$cid")
        kill -TERM %1
        dl_times[$i]=$(echo "$out" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev)
        # things get messy if we start the next iteration before the backgrounded loop finishes
        wait %1
    done
}

gather_results() {
    # get header for bitswap stats
    echo -n "peer," > "${results_prefix}aggregate"
    iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:| \[)' | tr ' ' '_' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
    echo 'dl_time' >> "${results_prefix}aggregate"

    # gather stats for each node
    for ((i=0; i < num_nodes; i++)); do
        echo -n "$(iptb get id $i)," >> "${results_prefix}aggregate"
        #iptb run $i sh -c "ipfs id --format='<id>,'" >> "${results_prefix}aggregate"
        iptb run $i sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
        echo ${dl_times[$i]} >> "${results_prefix}aggregate"
    done
}
