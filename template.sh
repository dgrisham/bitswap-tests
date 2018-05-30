#!/bin/sh

# find better way to handle this arg count check
#[ ! $# -eq 6 ] && echo 'missing args' && exit 1
while getopts ":n:c:o:i" opt; do
    case $opt in
        n)
            [[ -z "$OPTARG" ]] && exit 1
            num_nodes="$OPTARG"
            ;;
        c)
            [[ -z "$OPTARG" ]] && exit 1
            creation_cmd="$OPTARG"
            ;;
        o)
            [[ -z "$OPTARG" ]] && exit 1
            results="$OPTARG"
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
    
iptb run 0 sh -c "$creation_cmd >file"
# add file to ipfs, save cid
cid=$(iptb run 0 ipfs add -q ./file | tr -d '\r')

dl_times[0]='LOCAL'
# have each of the other nodes request the file
for ((i=1; i < num_nodes; i++)); do
    out=$(iptb run $i ipfs get "$cid")
    # save the file download time for this node
    dl_times[$i]=$(echo "$out" | tail -n1 | rev | cut -d' ' -f1 | cut -c 2- | rev)
done

# get header for bitswap stats
echo -n "id," > $results
iptb run 0 sh -c "ipfs bitswap stat" | grep -oP '(?<=\t).*(?=:)' | tr ' ' '_' | paste -sd ',' | tr '\n' ',' >> $results
echo 'dl_time' >> $results

# gather stats for each node
for ((i=0; i < num_nodes; i++)); do
    iptb run $i sh -c "ipfs id --format='<id>,'" >> $results
    iptb run $i sh -c "ipfs bitswap stat" | grep -oP '(?<=: |\[)[0-9A-Za-z /]+(?=]|)' | paste -sd ',' | tr '\n' ',' >> $results
    echo ${dl_times[$i]} >> $results
done

# the following commented command should be able to grab bitswap stats and do
# the relevant string manipulation, all on the docker image. but it's gross
#iptb for-each sh -c "ipfs id --format='<id>,' && ipfs bitswap stat | grep ':\|\[' | sed 's/.*\?: //' | sed 's/.*\?\[\(.*\?\)\]/\1/' | paste -sd ',' -" > $results

iptb kill
