#!/bin/sh

set -ex

# find better way to handle this arg count check
#[ ! $# -eq 6 ] && echo 'missing args' && exit 1
use_strategy=0
while getopts ":n:c:d:b:s" opt; do
    case $opt in
        n)
            [[ -z "$OPTARG" ]] && exit 1
            num_nodes="$OPTARG"
            ;;
        c)
            [[ -z "$OPTARG" ]] && exit 1
            creation_cmd="$OPTARG"
            ;;
        b)
            [[ -z "$OPTARG" ]] && exit 1
            bw_dist="$OPTARG"
            ;;
        s)
            use_strategy=1
            ;;
        d)
            [[ -z "$OPTARG" ]] && exit 1
            results_dir="$OPTARG"
            mkdir -p "$results_dir"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
        --)
            break
            ;;
    esac
done
shift $((OPTIND-1))

yes | iptb init -n $num_nodes --type docker >/dev/null
iptb start

iptb connect 0 1
iptb connect 0 2

results_prefix="$results_dir/"
num_bws=$(wc -w <<< $bw_dist)
if [[ $num_bws -eq 1 ]]; then
    # iptb set upload $bw_dist "[0-$((num_nodes-1))]"
    ./set_rates.sh -i -n0 -u$bw_dist
    for ((k=1; k < num_nodes; k++)); do
        ./set_rates.sh -n$k -u$bw_dist
    done
    results_prefix+="$bw_dist"$(printf "_$bw_dist%.0s" $(eval echo {1..$((num_nodes-1))}))
elif [[ $num_bws > 1 ]]; then
    k=0
    for bw in $bw_dist; do
        if [[ "$k" -eq 0 ]]; then
            [[ "$bw" != "-1" ]] && ./set_rates.sh -i -n$k -u$bw
        fi
        [[ "$bw" != "-1" ]] && ./set_rates.sh -n$k -u$bw
        ((++k))
    done
    results_prefix+="$(echo $bw_dist | sed 's/ /_/g')-"
fi

if [[ $use_strategy -eq 1 ]]; then
    iptb for-each ipfs config --json -- Experimental.BitswapStrategyEnabled true
    iptb for-each ipfs config --json -- Experimental.BitswapStrategy '"Identity"'
fi

# store node ids
for ((i=0; i < num_nodes; i++)); do
    nodeIds[$i]=$(iptb run $i ipfs id | jq .ID | sed 's/"//g')
done

# each node uploads a file
for ((i=0; i < num_nodes; i++)); do
    iptb run $i sh -c "$creation_cmd >file"
    # store cids of uploaded files
    cids[$i]=$(iptb run $i ipfs add -q ./file | tr -d '\r')
done

ledger_file="${results_prefix}ledgers_0"
[[ -f "$ledger_file" ]] && rm "$ledger_file"
touch "$ledger_file"
stop=0
until [[ "$stop" == 1 ]]; do
    # once termination signal is received, finish current iteration of outer loop then stop the loop
    trap "stop=1" SIGTERM
    for ((j=0; j < num_nodes; j++)); do
        [[ $j == 0 ]] && continue
        iptb run 0 -n ipfs bitswap ledger ${nodeIds[j]} >> "$ledger_file" || true
    done
done &
pid_inf=($!)

pids=()
dl_times0_tmp=$(mktemp)
touch "$dl_times0_tmp"
for ((i=1; i < num_nodes; i++)); do
    { out1=$(iptb run 0 -n ipfs get "${cids[$i]}");
    out2=$(echo "$out1" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev >> "$dl_times0_tmp");
    echo "out2: $out2";} &
    pids+=($!)
done

dl_times_tmp=$(mktemp)
touch "$dl_times_tmp"
for ((i=1; i < num_nodes; i++)); do
    { out=$(iptb run $i -n ipfs get "${cids[0]}");
    echo "$out" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev >> "$dl_times_tmp"; } &
    pids+=($!)
done

# wait for `ipfs get` loops to finish
wait "${pids[@]}"
# stop the infinite ledger loop
kill -TERM $pid_inf
wait $pid_inf

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
    echo -n "$i," >> "${results_prefix}aggregate"
    #iptb run $i sh -c "ipfs id --format='<id>,'" >> "${results_prefix}aggregate"
    iptb run "$i" sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' | tr '\n' ',' >> "${results_prefix}aggregate"
    if [[ "$i" -eq 0 ]]; then
        IFS=','
        echo "\"${dl_times0[*]}\"" >> "${results_prefix}aggregate"
        continue
    fi
    echo ${dl_times[$((i-1))]} >> "${results_prefix}aggregate"
 done

iptb kill
