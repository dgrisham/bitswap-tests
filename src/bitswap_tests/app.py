#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import subprocess
import argparse


def app():
    args = cli()
    n = args.num_nodes
    strategies = args.strategies
    upload_rates = args.upload_rates
    dpr = args.dpr

    # create and start iptb nodes
    subprocess.run(
        f"iptb auto --type dockeripfs --count {n} --force >/dev/null".split(" ")
    )
    subprocess.run(["iptb", "start", "--wait"])

    # modify ipfs configs to use/configure strategies
    strats_stdin = ""
    for i in range(n):
        if strategies is not None:
            strats_stdin += f'{i} -- ipfs config --json -- Experimental.BitswapStrategy "{strategies[i]}"\n'
        strats_stdin += (
            f"{i} -- ipfs config --json -- Experimental.BitswapRRQRoundBurst {dpr[i]}\n"
        )
    try:
        print(f"strats_stdin: {strats_stdin}")
        subprocess.run(["iptb", "run"], input=strats_stdin.encode(), check=True)
    except subprocess.CalledProcessError as e:
        print(
            f"error setting strategies and/or round bursts: {e.output}", file=sys.stderr
        )
        return 1

    # TODO: everything below this line has yet to be tested (or ran at all)
    if upload_rates is not None:
        ifnum = 0
        set_rate_bin = "../../deprecated/bin/set_rate.sh"
        try:
            subprocess.run(f"{set_rate_bin} -i {n}".split(" "), check=True)
        except subprocess.CalledProcessError as e:
            print(f"error initializing IFBs: {e.output}", file=sys.stderr)
        for i, u in enumerate(upload_rates):
            if u != -1:
                try:
                    subprocess.run(
                        f"{set_rate_bin} -n {i} -f {ifnum} -u {u}".split(" "),
                        check=True,
                    )
                except subprocess.CalledProcessError as e:
                    print(f"error initializing IFBs: {e.output}", file=sys.stderr)
                    return 1
                ifnum += 1

    for i in range(n):
        idCmd = ["iptb", "attr", "get", f"{i}", "container"]
        try:
            idCmdResult = subprocess.check_output(idCmd)
        except subprocess.CalledProcessError as e:
            print(f"error getting container ID: {e.output}", file=sys.stderr)
            return 1
        try:
            containerID = idCmdResult.decode().strip()
        except bytes.UnicodeError as e:
            print(f"error decoding command output: {e.output}", file=sys.stderr)

        logCmd = [
            "docker",
            "exec",
            "--detach",
            containerID,
            "script",
            "-c",
            "trap exit SIGTERM; ipfs log tail | grep DebtRatio",
            "ipfs_log",
        ]
        try:
            subprocess.run(logCmd, check=True)
        except subprocess.CalledProcessError as e:
            print(f"error starting log workers: {e.output}", file=sys.stderr)
            return 1

    # success!
    return 0


def cli():
    cli = argparse.ArgumentParser()
    # fmt: off
    cli.add_argument(
        "-t",
        "--test",
        type=int,
        help="which test to run",
        required=True,
    )
    cli.add_argument(
        "-n",
        "--num-nodes",
        type=int,
        help="number of nodes to spin up for the test",
        required=True,
    )
    # TODO: need to reasses this arg, seems like something specific tests could
    # specify/handle
    cli.add_argument(
        "--fsize",
        type=int,
        help="size of the files to upload in bytes",
        required=True,
    )
    cli.add_argument(
        "-u",
        "--upload-rates",
        nargs="*",
        type=int,
        help="sequence of upload rates to set for nodes (TODO: units)",
        required=False,
    )
    cli.add_argument(
        "--dpr",
        nargs="*",
        type=int,
        help="sequence of data-per-round values to set for nodes (TODO: explain)",
        required=True,
    )
    cli.add_argument(
        "-s",
        "--strategies",
        nargs="*",
        type=str,
        help="sequence of strategies to set for nodes (TODO: explain)",
        required=False,
    )
    # fmt: on

    args = cli.parse_args()
    n = args.num_nodes
    if len(args.dpr) != n:
        print(f"{len(args.dpr)} DPR values passed, should be {n}", file=sys.stderr)
        exit(1)
    if args.strategies is not None and len(args.strategies) != n:
        print(
            f"{len(args.strategies)} strategies passed, should be {n}", file=sys.stderr
        )
        exit(1)
    if args.upload_rates is not None and len(args.upload_rates) != n:
        print(
            f"{len(args.upload_rates)} upload rates passed, should be {n}",
            file=sys.stderr,
        )
        exit(1)

    return args


if __name__ == "__main__":
    app()
