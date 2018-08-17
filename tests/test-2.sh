#!/bin/sh

# topology: user 0 connected to users 1 and 2
# all users upload unique files, user 0 downloads 1 and 2's files while
# 1 and 2 download 0's
# result: aggregate stats; time series of user 0's ledgers

connect() {
    iptb connect 0 1
    iptb connect 0 2
}

add() {
    for ((i=0; i < num_nodes; i++)); do
        iptb run $i sh -c "$creation_cmd >file"
        # store cids of uploaded files
        cids[$i]=$(iptb run $i ipfs add -q ./file | tr -d '\r')
    done
}

request() {
    ledger_file="${results_prefix}ledgers_0"
    [[ -f "$ledger_file" ]] && rm "$ledger_file"
    touch "$ledger_file"
    echo 'id,debt_ratio,exchanges,bytes_sent,bytes_received' > "$ledger_file"
    stop=0
    until [[ "$stop" == 1 ]]; do
        # once termination signal is received, finish current iteration of outer loop then stop the loop
        trap "stop=1" SIGTERM
        for ((j=0; j < num_nodes; j++)); do
            [[ $j == 0 ]] && continue
            # iptb run 0 -n ipfs bitswap ledger ${nodeIds[j]} >> "$ledger_file" || true
            ledger="$(iptb run 0 -n ipfs bitswap ledger ${nodeIds[j]})"
            # echo "$ledger" >> "${results_prefix}ledgers_$i"
            echo "$ledger" | awk '{print $NF}' | sed '1s/>//' | paste -sd ',' | tr -d '\r'|  sed 's/,$//' >> "$ledger_file"
        done
    done &
    pid_inf=($!)

    pids=()
    dl_times0_tmp=$(mktemp)
    touch "$dl_times0_tmp"
    for ((i=1; i < num_nodes; i++)); do
        { out=$(iptb run 0 -n ipfs get "${cids[$i]}");
        echo "$out" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev >> "$dl_times0_tmp";
        } &
        pids+=($!)
    done

    dl_times_tmp=$(mktemp)
    touch "$dl_times_tmp"
    for ((i=1; i < num_nodes; i++)); do
        { out=$(iptb run $i -n ipfs get "${cids[0]}");
        echo "$out" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev >> "$dl_times_tmp";
        } &
        pids+=($!)
    done

    # wait for `ipfs get` loops to finish
    wait "${pids[@]}"
    # stop the infinite ledger loop
    kill -TERM $pid_inf
    wait $pid_inf
}

gather_results() {
    readarray -t dl_times0 < "$dl_times0_tmp"
    readarray -t dl_times < "$dl_times_tmp"

    echo "dl_times0: ${dl_times0[*]}"
    echo "dl_times: ${dl_times[*]}"

    # get header for bitswap stats
    echo -n "peer," > "${results_prefix}aggregate"
    iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:| \[)' | tr ' ' '_' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
    echo 'dl_time(s)' >> "${results_prefix}aggregate"

    # gather stats for each node
    for ((i=0; i < num_nodes; i++)); do
        echo -n "$(iptb get id $i)," >> "${results_prefix}aggregate"
        #iptb run $i sh -c "ipfs id --format='<id>,'" >> "${results_prefix}aggregate"
        iptb run "$i" sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
        if [[ "$i" -eq 0 ]]; then
            IFS=','
            echo "\"${dl_times0[*]}\"" >> "${results_prefix}aggregate"
            continue
        fi
        echo ${dl_times[$((i-1))]} >> "${results_prefix}aggregate"
     done
}
