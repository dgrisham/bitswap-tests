#!/bin/bash

set -x

while getopts "t::n:f:d:b:r:s:" opt; do
    case $opt in
        t)
            [[ -z "$OPTARG" ]] && exit 1
            test_num="$OPTARG"
            ;;
        n)
            [[ -z "$OPTARG" ]] && exit 1
            num_nodes="$OPTARG"
            ;;
        f)
            [[ -z "$OPTARG" ]] && exit 1
            file_cmd="$OPTARG"
            ;;
        b)
            [[ -z "$OPTARG" ]] && exit 1
            bw_dist="$OPTARG"
            ;;
        r)
            [[ -z "$OPTARG" ]] && exit 1
            echo "setting round bursts to: $OPTARG"
            round_bursts="$OPTARG"
            ;;
        s)
            [[ -z "$OPTARG" ]] && exit 1
            strategy="$OPTARG"
            ;;
        d)
            [[ -z "$OPTARG" ]] && exit 1
            results_dir="$OPTARG"
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

source "tests/test-$test_num.sh"

persistent() {
    until $@; do :; done
}

yes | iptb auto --type dockeripfs --count $num_nodes >/dev/null
iptb start --wait
persistent iptb connect

results_prefix="results/$test_num/$results_dir/"
mkdir -p "$results_prefix"
rm -f "${results_prefix}/*"

if [[ ! -z "$strategy" ]]; then
    iptb run -- ipfs config --json -- Experimental.BitswapStrategyEnabled true
    iptb run -- ipfs config --json -- Experimental.BitswapStrategy "\"$strategy\""
    results_prefix+="${strategy,,}-"

    num_rbs=$(wc -w <<< $round_bursts)
    if [[ $num_rbs -eq 1 ]]; then
        iptb run -- ipfs config --json -- Experimental.BitswapRRQRoundBurst $round_bursts
        results_prefix+="rb_$round_bursts-"
    elif [[ $num_rbs -eq $num_nodes ]]; then
        k=0
        for rb in $round_bursts; do
            iptb run $k -- ipfs config --json -- Experimental.BitswapRRQRoundBurst $rb
            ((++k))
        done
        results_prefix+="rb_$(echo $round_bursts | sed 's/ /_/g')-"
    else
        echo "error: specified $num_rbs round lengths. should be 1 or $num_nodes"
        exit 1
    fi
fi

num_bws=$(wc -w <<< $bw_dist)
if [[ $num_bws -eq 1 ]]; then
    scripts/set_rates.sh -i -n0 -u$bw_dist
    for ((k=1; k < num_nodes; k++)); do
        scripts/set_rates.sh -n$k -u$bw_dist
    done
    results_prefix+="$bw_dist"$(printf "_$bw_dist%.0s" $(eval echo {1..$((num_nodes-1))}))
elif [[ $num_bws > 1 ]]; then
    k=0
    for bw in $bw_dist; do
        if [[ "$k" -eq 0 ]]; then
            [[ "$bw" != "-1" ]] && scripts/set_rates.sh -i -n$k -u$bw
        fi
        [[ "$bw" != "-1" ]] && scripts/set_rates.sh -n$k -u$bw
        ((++k))
    done
    results_prefix+="$(echo $bw_dist | sed 's/ /_/g')-"
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
    ledger_file="${results_prefix}ledgers_$i"
    cat "$ledger_file" |
    jq '{event: .event|ltrimstr("Bitswap.DebtRatioUpdatedOn"),peer:.peer,time:.time,sent:.sent,recv:.recv,value:.value}' |
    jq -s '{"'"${nodeIds[$i]}"'":[.[]]}' | sponge "${results_prefix}ledgers_$i"
done

jq -s '.' ${results_prefix}ledgers_* > "${results_prefix}ledgers"
rm -f ${results_prefix}ledgers_*
