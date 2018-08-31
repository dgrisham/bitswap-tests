#!/bin/bash

set -ex

while getopts "t::n:c:d:b:r:s:" opt; do
    case $opt in
        t)
            [[ -z "$OPTARG" ]] && exit 1
            test_num="$OPTARG"
            ;;
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
        r)
            [[ -z "$OPTARG" ]] && exit 1
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

# source the specified test
source "tests/test-$test_num.sh"

yes | iptb init -n $num_nodes --type docker >/dev/null
iptb start

results_prefix="results/$test_num/$results_dir/"
mkdir -p "$results_prefix"

if [[ ! -z "$strategy" ]]; then
    iptb for-each ipfs config --json -- Experimental.BitswapStrategyEnabled true
    iptb for-each ipfs config --json -- Experimental.BitswapStrategy "\"$strategy\""
    results_prefix+="${strategy,,}-"

    num_rbs=$(wc -w <<< $round_bursts)
    if [[ $num_rbs -eq 1 ]]; then
        iptb for-each ipfs config --json -- Experimental.BitswapRRQRoundBurst $round_bursts
        results_prefix+="rb_$round_bursts-"
    elif [[ $num_rbs -eq $num_nodes ]]; then
        k=0
        for rb in $round_bursts; do
            iptb run $k ipfs config --json -- Experimental.BitswapRRQRoundBurst $rb
            ((++k))
        done
        results_prefix+="rb_$(echo $round_bursts | sed 's/ /_/g')-"
    else
        echo "error: must specify an appropriate number of round lengths with -r"
    fi
fi

num_bws=$(wc -w <<< $bw_dist)
if [[ $num_bws -eq 1 ]]; then
    scripts/set_rates.sh -i -n0 -u$bw_dist
    for ((k=1; k < num_nodes; k++)); do
        scripts/set_rates.sh -n$k -u$bw_dist
    done
    results_prefix+="bw_$bw_dist"$(printf "_$bw_dist%.0s" $(eval echo {1..$((num_nodes-1))}))
elif [[ $num_bws > 1 ]]; then
    k=0
    for bw in $bw_dist; do
        if [[ "$k" -eq 0 ]]; then
            [[ "$bw" != "-1" ]] && scripts/set_rates.sh -i -n$k -u$bw
        fi
        [[ "$bw" != "-1" ]] && scripts/set_rates.sh -n$k -u$bw
        ((++k))
    done
    results_prefix+="bw_$(echo $bw_dist | sed 's/ /_/g')-"
fi

# save node ids for later use
declare -a nodeIds
for ((i=0; i < num_nodes; i++)); do
    nodeIds[$i]="$(iptb get id $i)"
done

### CONNECT NODES ###

connect

### ADD FILES ###

add

### REQUEST FILES ###

request

### GATHER RESULTS ###

gather_results

# kill nodes
iptb kill
