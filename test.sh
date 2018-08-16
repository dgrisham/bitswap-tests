#!/bin/sh

set -ex

# find better way to handle this arg count check
#[ ! $# -eq 6 ] && echo 'missing args' && exit 1
use_strategy=0
while getopts "t::n:c:d:b:r:s" opt; do
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

# source the specified test
source "./test-$test_num.sh"

yes | iptb init -n $num_nodes --type docker >/dev/null
iptb start

if [[ $use_strategy -eq 1 ]]; then
    iptb for-each ipfs config --json -- Experimental.BitswapStrategyEnabled true
    iptb for-each ipfs config --json -- Experimental.BitswapStrategy '"Identity"'
    num_rbs=$(wc -w <<< $round_bursts)
    if [[ $num_rbs -eq 1 ]]; then
        iptb for-each ipfs config --json -- Experimental.BitswapRRQRoundBurst $round_bursts
    elif [[ $num_rbs -eq $num_nodes ]]; then
        k=0
        for rb in $round_bursts; do
            iptb run $k ipfs config --json -- Experimental.BitswapRRQRoundBurst $rb
            ((++k))
        done
    else
        echo "error: must specify an appropriate number of round lengths with -r"
    fi
fi

results_prefix="$results_dir/"
num_bws=$(wc -w <<< $bw_dist)
if [[ $num_bws -eq 1 ]]; then
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

for ((i=0; i < num_nodes; i++)); do
    nodeIds[$i]=$(iptb get id $i)
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
