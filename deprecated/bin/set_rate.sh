#!/bin/sh

usage="\
./set_rate.sh [-h] -n NODE_NUM -f INTERFACE_NUM -u EXT_INTERFACE
              [-i NUM_INTERFACES]"

while getopts "n:f:u:i:h" opt; do
    case $opt in
        n)
            node_num="$OPTARG"
            ;;
        f)
            ifnum="$OPTARG"
            ;;
        u)
            ext_up="$OPTARG"
            ;;
        i)
            num_interfaces="$OPTARG"
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

if [[ -z "$node_num" || -z "$ifnum" || -z "$ext_up" ]]; then
    echo "missing required argument(s)" >&2
    echo "$usage" >&2
    exit 1
fi

if [[ -n "$num_interfaces" ]]; then
    [[ ! -z $(lsmod | grep ifb) ]] && sudo modprobe -r ifb
    sudo modprobe ifb numifbs=$num_interfaces
    sudo modprobe sch_fq_codel
    sudo modprobe act_mirred
    exit 0
fi

ext=$(iptb attr get $node_num ifname)
[[ -z "$ext" ]] && exit 1
# each interfaces gets its own rate limiter
ifb="ifb$ifnum"

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
