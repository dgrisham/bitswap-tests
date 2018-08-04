#!/bin/sh

# topology: fully connected
# user 0 uploads file, users 1 through n download consecutively (not at the same time)
# results: aggregate stats; time series of ledgers for users 1 through N

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

for ((i=0; i < num_nodes; i++)); do
    for ((j=i+1; j < num_nodes; j++)); do
        iptb connect $i $j
    done
done

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

iptb run 0 sh -c "$creation_cmd >file"
# add file to ipfs, save cid
cid=$(iptb run 0 ipfs add -q ./file | tr -d '\r')

for ((i=0; i < num_nodes; i++)); do
    nodeIds[$i]=$(iptb get id $i)
done

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

iptb kill
