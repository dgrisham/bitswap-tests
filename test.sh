#!/bin/bash

# set -ex

usage="\
./test.sh [-h] -t TEST_NUM -n NUM_NODES -f FILE_CMD
          -b [UPLOAD_BANDWIDTH [UPLOAD_BANDWIDTH ...]]
          -r [ROUND_BURST [ROUND_BURST ...]] -s [STRATEGY [STRATEGY ...]]
          [-d RESULTS_DIR]"

while getopts "t::n:f:d:b:r:s:h" opt; do
    case $opt in
        t)
            test_num="$OPTARG"
            ;;
        n)
            num_nodes="$OPTARG"
            ;;
        f)
            file_cmd="$OPTARG"
            ;;
        b)
            IFS=' ' read -r -a bw_dist <<< "$OPTARG"
            ;;
        r)
            IFS=' ' read -r -a round_bursts <<< "$OPTARG"
            ;;
        s)
            IFS=' ' read -r -a strategies <<< "${OPTARG}"
            ;;
        d)
            results_dir="$OPTARG"
            ;;
        h)
            echo "$usage"
            exit 0
            ;;
        *)
            echo "$usage" >&2
            exit 1
            ;;
        --)
            break
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -z "$test_num" || -z "$num_nodes" || -z "$file_cmd" ]]; then
    echo "missing required arguments" >&2
    echo "$usage" >&2
    exit 1
fi

# post-process args

if ((${#strategies[@]} > 0)); then
    if ((${#strategies[@]} == 1)); then
        s=${strategies[0]}
        strategies=($(for ((i=0; i < $num_nodes; i++)); do echo "$s"; done))
    elif ((${#strategies[@]} != num_nodes)); then
        echo "error: specified ${#strategies[@]} strategies. should be 0, 1 or $num_nodes" >&2
        exit 1
    fi
    if ((${#round_bursts[@]} == 1)); then
        rb=${round_bursts[0]}
        round_bursts=($(for ((i=0; i < $num_nodes; i++)); do echo $rb; done))
    elif ((${#round_bursts[@]} != num_nodes)); then
        echo "error: specified ${#round_bursts[@]} round lengths. should be 1 or $num_nodes" >&2
        exit 1
    fi
fi


if ((${#bw_dist[@]} > 0)); then
    if ((${#bw_dist[@]} == 1)); then
        bw=${bw_dist[0]}
        bw_dist=($(for ((i=0; i < $num_nodes; i++)); do echo $bw; done))
    elif ((${#bw_dist[@]} != num_nodes)); then
        echo "error: specified ${#bw_dist[@]} upload bandwidth values. should be 0, 1 or $num_nodes" >&2
        exit 1
    fi
fi

source "tests/test-$test_num.sh"

yes | iptb auto --type dockeripfs --count $num_nodes >/dev/null
iptb start --wait

results_prefix="$results_dir/"
mkdir -p "$results_prefix"

if [[ -v strategies[@] ]]; then
    iptb run -- ipfs config --json -- Experimental.BitswapStrategyEnabled true
    k=0
    for s in ${strategies[@]}; do
        echo "$k"' -- ipfs config --json -- Experimental.BitswapStrategy \"'"$s"'\"'
        ((k++))
    done | iptb run >/dev/null
    results_prefix+="${strategies[0]}-"
    # NOTE: replace above with this second version if supporting heterogeneous strategies
    # results_prefix+="$(echo ${strategies[i]} | sed 's/ /_/g')-"

    if [[ -v round_bursts[@] ]]; then
        k=0
        for rb in ${round_bursts[@]}; do
            echo "$k -- ipfs config --json -- Experimental.BitswapRRQRoundBurst $rb"
            ((k++))
        done | iptb run >/dev/null
        results_prefix+="rb_$(echo ${round_bursts[@]} | sed 's/ /_/g')-"
    fi
fi

if [[ -v bw_dist[@] ]]; then
    i=0
    ifnum=0
    for bw in ${bw_dist[@]}; do
        if (( bw != -1 )); then
            if ((ifnum == 0)); then
                bin/set_rate.sh -i$num_nodes -n$i -f$ifnum -u$bw
            else
                bin/set_rate.sh -n$i -f$ifnum -u$bw
            fi
            ((ifnum++))
        fi
        ((i++))
    done
    results_prefix+="bw_$(echo ${bw_dist[@]} | sed 's/ /_/g')-"
fi

for ((i=0; i< num_nodes; i++)); do
    nodeIds[$i]="$(iptb attr get $i id)"
done

# background processes to gather log files
for ((i=0; i< num_nodes; i++)); do
    docker exec --detach $(iptb attr get $i container) script -c 'trap "exit" SIGTERM; ipfs log tail | grep DebtRatio' ipfs_log
done

# run test body
body

# grab debt ratio update events from logs
for ((i=0; i < num_nodes; i++)); do
    docker exec $(iptb attr get $i container) pkill -TERM script
    docker cp $(iptb attr get $i container):ipfs_log "${results_prefix}ledgers_$i"
done

# kill nodes
iptb stop

# Format logs
# -----------

for ((i=0; i < num_nodes; i++)); do
    declare -A jq_args
    jq_args="--arg id ${nodeIds[i]}"
    jq_str='{id: $id'
    if [[ -v strategies[@] ]]; then
        jq_args+=" --arg s ${strategies[i]}"
        jq_str+=', strategy: $s'
    fi
    if [[ -v round_bursts[@] ]]; then
        jq_args+=" --arg rb ${round_bursts[i]}"
        jq_str+=',round_burst: $rb'
    fi
    if [[ -v bw_dist[@] ]]; then
        jq_args+=" --arg bw ${bw_dist[i]}"
        jq_str+=',upload_bandwidth: $bw'
    fi
    if [[ -v uploads[@] ]]; then
        jq_args+=" --argjson uploads [${uploads[$i]}]"
        jq_str+=',uploads: $uploads'
    fi
    if [[ -v dl_times[@] ]]; then
        jq_args+=" --argjson dl_times [${dl_times[$i]}]"
        jq_str+=',dl_times: $dl_times'
    fi
    jq_str+=',history:.}'

    ledger_file="${results_prefix}ledgers_$i"
    cat "$ledger_file" |
    jq '{event: .event|ltrimstr("Bitswap.DebtRatioUpdatedOn"),peer:.peer,time:.time,sent:.sent,recv:.recv,value:.value}' |
    jq -s $jq_args "$jq_str" |
    sponge "${results_prefix}ledgers_$i"
done

outfile="${results_prefix%?}.json"
rm -f $outfile
jq -s '.' ${results_prefix}ledgers_* > $outfile
rm -f ${results_prefix}ledgers_*

echo "Saved results to: $outfile"
