#!/bin/sh

# topology: fully connected
# all users upload unique file, all other users download each file
# result: aggregate stats; TODO

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

# establish connection between all node pairs
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
        if [[ $k == 0 ]]; then
            [[ "$bw" != "-1" ]] && ./set_rates.sh -i -n$k -u$bw
        fi
        [[ "$bw" != "-1" ]] && ./set_rates.sh -n$k -u$bw
        ((++k))
    done
    results_prefix+="$(echo $bw_dist | sed 's/ /_/g')-"
fi

if [[ $use_strategy == 1 ]]; then
    iptb for-each ipfs config --json -- Experimental.BitswapStrategyEnabled true
    iptb for-each ipfs config --json -- Experimental.BitswapStrategy '"Identity"'
fi

# store node ids
for ((i=0; i < num_nodes; i++)); do
    nodeIds[$i]=$(iptb get id $i)
done

declare -A cids
# each node uploads a file
for ((i=0; i < num_nodes; i++)); do
    for ((j=0; j < num_nodes; j++)); do
        [[ $i == $j ]] && continue
        iptb run $i sh -c "$creation_cmd >file"
        cids[$j,$i]=$(iptb run $i ipfs add -q ./file | tr -d '\r')
    done
done

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
    done
    pid_gets+=($!)
done

# wait for `ipfs get` loops to finish
wait "${pid_gets[@]}"
# stop the infinite ledger loops
kill -TERM "${pid_infs[@]}"
wait "${pid_infs[@]}"

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

iptb kill
