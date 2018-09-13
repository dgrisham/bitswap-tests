#!/bin/bash

set -ex

test_num=3
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

# source the specified test
source "tests/test-$test_num.sh"

persistent() {
    until $@; do :; done
}

yes | iptb auto --type dockeripfs --count $num_nodes >/dev/null
iptb start --wait
persistent iptb connect

results_prefix="results/$test_num/$results_dir/"
mkdir -p "$results_prefix"

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
            iptb run $k ipfs config --json -- Experimental.BitswapRRQRoundBurst $rb
            ((++k))
        done
        results_prefix+="rb_$(echo $round_bursts | sed 's/ /_/g')-"
    else
        echo "$round_bursts"
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

# start capturing logs

for ((i=0; i< num_nodes; i++)); do
    docker exec --detach $(iptb attr get $i container) sh -c "ipfs log tail >ipfs_log"
done

### CONNECT NODES ###

persistent iptb connect

### ADD FILES ###

declare -A cids
# each node uploads a file
for ((i=0; i < num_nodes; i++)); do
    for ((j=0; j < num_nodes; j++)); do
        [[ $i == $j ]] && continue
        iptb run $i -- sh -c "$file_cmd >file"
        cids[$j,$i]=$(iptb run $i -- sh -c "ipfs add -q file && rm file" | tail -n2)
    done
done

### REQUEST FILES, GATHER STATS ###

for ((i=0; i < num_nodes; i++)); do
    for ((j=0; j < num_nodes; j++)); do
        [[ $j == $i ]] && continue
        echo "$i -- ipfs get ${cids[$i,$j]}"
    done
done | iptb run |
       perl -p -e 's/node\[(\d)\].*?$/\1/' |
       sed -e '/^$/d' |
       grep --color=no -oP '((^\d)|(Qm.*?)|([0-9ms]+))$' |
       sed 'N;N;s/\n/,/g' > "${results_prefix}aggregate"

for ((i=0; i < num_nodes; i++)); do
    docker cp $(iptb attr get $i container):ipfs_log "${results_prefix}ledgers_$i"
done

# kill nodes
iptb stop
