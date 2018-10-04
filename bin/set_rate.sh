#!/bin/sh

while getopts ":i:n:f:u:d:" opt; do
    case $opt in
        i)
            [[ -z "$OPTARG" ]] && exit 1
            num_interfaces="$OPTARG"
            ;;
        n)
            [[ -z "$OPTARG" ]] && exit 1
            node_num="$OPTARG"
            ;;
        f)
            [[ -z "$OPTARG" ]] && exit 1
            ifnum="$OPTARG"
            ;;
        u)
            [[ -z "$OPTARG" ]] && exit 1
            ext_up="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        --)
            break
            ;;
    esac
done
shift $((OPTIND-1))

ext=$(iptb attr get $node_num ifname)
[[ -z "$ext" ]] && exit 1
# each interfaces gets its own rate limiter
ifb="ifb$ifnum"

if [[ -n "$num_interfaces" ]]; then
    [[ ! -z $(lsmod | grep ifb) ]] && sudo modprobe -r ifb
    sudo modprobe ifb numifbs=$num_interfaces
    sudo modprobe sch_fq_codel
    sudo modprobe act_mirred
fi

# clear old queuing disciplines
tc qdisc del dev $ext root || true
tc qdisc del dev $ext ingress || true
tc qdisc del dev $ifb root || true
tc qdisc del dev $ifb ingress || true

# create ingress on external interface
tc qdisc add dev $ext handle ffff: ingress
sudo ifconfig $ifb up
# forward all ingress traffic to the ifb device
tc filter add dev $ext parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $ifb
# create *egress* filter on the IFB device
tc qdisc add dev $ifb root tbf rate "${ext_up}kbit" burst $ext_up limit 100000
