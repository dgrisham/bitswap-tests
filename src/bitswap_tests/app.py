#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import subprocess
import argparse


def app():
    args = cli()
    n = args.num_nodes
    strategies = args.strategies
    dpr = strategies.dpr
    subprocess.run(
        f"yes | iptb auto --type dockeripfs --count {n} >/dev/null".split(" ")
    )
    subprocess.run(["iptb", "start", "--wait"])

    strats_stdin = ""
    for i in range(n):
        strats_stdin += (
            f'{n} -- ipfs config --json -- Experimental.BitswapStrategy "{strategies[n]}"'
            + f"{n} -- ipfs config --json -- Experimental.BitswapRRQRoundBurst {dpr[n]}"
        )
    try:
        subprocess.run(
            ["iptb", "run", ">/dev/null"],
            input=strats_stdin.encode(),
            stdin=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"error setting strategies and/or round bursts: {e.output}", file=sys.stderr
        )


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
    if args.upload_rates != n:
        print(f"{len(args.upload_rates)} passed, should be {n}", file=sys.stderr)
        exit(1)
    if args.dpr != n:
        print(f"{len(args.dpr)} passed, should be {n}", file=sys.stderr)
        exit(1)
    if args.strategies != n:
        print(f"{len(args.strategies)} passed, should be {n}", file=sys.stderr)
        exit(1)

    return args


if __name__ == "__main__":
    app()
