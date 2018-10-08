#!/bin/sh

set -ex

init=0
while getopts ":i:n:u:d:" opt; do
    case $opt in
        i)
            [[ -z "$OPTARG" ]] && exit 1
            num_interfaces="$OPTARG"
            ;;
        n)
            [[ -z "$OPTARG" ]] && exit 1
            num="$((OPTARG+1))"
            ;;
        f)
            [[ -z "$OPTARG" ]] && exit 1
            ifnum="$OPTARG"
            ;;
        u)
            [[ -z "$OPTARG" ]] && exit 1
            ext_up="${OPTARG}kbit"
            ;;
        d)
            [[ -z "$OPTARG" ]] && exit 1
            ext_down="${OPTARG}kbit"
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

## Paths and definitions
ext=$(ip link | grep -oP 'veth.*?@' | sed 's/@//' | sed "${num}q;d")
[[ -z "$ext" ]] && exit 1
ext_ingress="ifb$ifnum"    # Use a unique ifb per rate limiter!
            # Set these as per your provider's settings, at 90% to start with
# ext_down=800kbit      # Max theoretical: for this example, up is 1024kbit
# ext_up=7100kbit   # Max theoretical: for this example, down is 8192kbit
q=1514                  # HTB Quantum = 1500bytes IP + 14 bytes ethernet.
            # Higher bandwidths may require a higher htb quantum. MEASURE.
            # Some ADSL devices might require a stab setting.

quantum=300     # fq_codel quantum 300 gives a boost to interactive flows
            # At higher bandwidths (50Mbit+) don't bother

if [[ -n "$num_interfaces" ]]; then
    [[ ! -z $(lsmod | grep ifb) ]] && sudo modprobe -r ifb
    sudo modprobe ifb numifbs="$num_interfaces"
    sudo modprobe sch_fq_codel
    sudo modprobe act_mirred
fi

# ethtool -K $ext tso off gso off gro off # Also turn of gro on ALL interfaces
                                        # e.g ethtool -K eth1 gro off if you have eth1
                    # some devices you may need to run these
                    # commands independently

# Clear old queuing disciplines (qdisc) on the interfaces
tc qdisc del dev $ext root || true
tc qdisc del dev $ext ingress || true
tc qdisc del dev $ext_ingress root || true
tc qdisc del dev $ext_ingress ingress || true

#########
# INGRESS
#########

if [[ ! -z "$ext_up" ]]; then

    # Create ingress on external interface
    tc qdisc add dev $ext handle ffff: ingress

    sudo ifconfig $ext_ingress up # if the interace is not up bad things happen

    # Forward all ingress traffic to the IFB device
    tc filter add dev $ext parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $ext_ingress

    # Create an EGRESS filter on the IFB device
    tc qdisc add dev $ext_ingress root handle 1: htb default 11

    # Add root class HTB with rate limiting
    tc class add dev $ext_ingress parent 1: classid 1:1 htb rate $ext_up
    tc class add dev $ext_ingress parent 1:1 classid 1:11 htb rate $ext_up prio 0 quantum $q

    # Add FQ_CODEL qdisc with ECN support (if you want ecn)
    tc qdisc add dev $ext_ingress parent 1:11 fq_codel quantum $quantum ecn
fi

#########
# EGRESS
#########

if [[ ! -z "$ext_down" ]]; then

    # Add FQ_CODEL to EGRESS on external interface
    tc qdisc add dev $ext root handle 1: htb default 11

    # Add root class HTB with rate limiting
    tc class add dev $ext parent 1: classid 1:1 htb rate $ext_down
    tc class add dev $ext parent 1:1 classid 1:11 htb rate $ext_down prio 0 quantum $q

    # Note: You can apply a packet limit here and on ingress if you are memory constrained - e.g
    # for low bandwidths and machines with < 64MB of ram, limit 1000 is good, otherwise no point

    # Add FQ_CODEL qdisc without ECN support - on egress it's generally better to just drop the packet
    # but feel free to enable it if you want.

    tc qdisc add dev $ext parent 1:11 fq_codel quantum $quantum noecn
fi
