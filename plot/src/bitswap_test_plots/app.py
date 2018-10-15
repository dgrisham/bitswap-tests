#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import argparse
import json
import traceback

import pandas as pd
import matplotlib.pyplot as plt

from os.path import splitext
from math import floor, ceil
from pandas.io.json import json_normalize

# local imports
from plot import plot, mkPlotConfig, prependErr


def run():
    args = cli()
    try:
        results = load(args.infile)
    except Exception as e:
        print(prependErr("loading results file", e), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

    results["ledgers"].index = results["ledgers"].index.map(
        lambda idx: (idx[0], idx[1], idx[2].total_seconds())
    )
    time = results["ledgers"].index.levels[2]
    if args.prange is not None:
        ti = floor(args.prange[0] * len(time))
        tf = ceil(args.prange[1] * len(time)) - 1
    elif args.trange is not None:
        ti, tf = args.trange
    else:
        ti, tf = 0, len(time) - 1
    trange = time[[ti, tf]]

    plotCfg = mkPlotConfig(results["ledgers"], trange, results["params"], args.kind)
    try:
        if args.save:
            plot(
                results["ledgers"],
                trange,
                plotCfg,
                f"{splitext(args.infile)[0]}-{args.kind}",
            )
        else:
            plot(results["ledgers"], trange, plotCfg)
        if not args.no_show:
            plt.show()
            plt.clf()
            plt.close()
    except Exception as e:
        print(prependErr("plotting results", e), file=sys.stderr)
        traceback.print_exc()

    return results


def cli():
    """
    Parse CLI args.
    """
    parser = argparse.ArgumentParser()
    rangeArgs = parser.add_mutually_exclusive_group(required=True)
    # fmt: off
    rangeArgs.add_argument(
        "-p",
        "--prange",
        nargs=2,
        type=float,
        help="specify lower and upper time range as percentages of total time",
    )
    rangeArgs.add_argument(
        "-t",
        "--trange",
        nargs=2,
        type=float,
        help="specify lower and upper time range as literal time values",
    )
    parser.add_argument(
        "-k",
        "--kind",
        type=str,
        choices=["all", "pairs"],
        default="all",
        help="which kind of plot to make",
    )
    parser.add_argument(
        "--no-show",
        action="store_true",
        default=False,
        help="do not show plots",
    )
    parser.add_argument(
        "-s",
        "--save",
        action="store_true",
        default=False,
        help="save plots as a pdf with the same basename as infile",
    )
    parser.add_argument(
        "infile",
        metavar="<results_file>",
        type=str,
        help="json results file to load and plot",
    )
    # fmt: on
    return parser.parse_args()


def load(fname):
    """
    Load json results file into 3 dataframes:
        1.  uploads: Set of blocks uploaded by each peer.
        2.  dl_times: Each peers' downloaded times for the blocks they
            downloaded.
        3.  ledgers: The Bitswap ledger update ledgers for each peer.
    Input:
        -   fname (str): Path to json file to load.
    Returns:
        A dictionary containing the above dataframes.
    """

    with open(fname, "r") as jfile:
        jdata = json.load(jfile)

    # load results into separate dataframes
    params = pd.DataFrame.from_records(
        jdata, exclude=["uploads", "dl_times", "history"], index="id"
    )

    uploads = pd.concat(
        [
            json_normalize(data=pdata, record_path="uploads", meta="id")
            for pdata in jdata
        ]
    ).set_index("id")

    dl_times = pd.concat(
        [
            json_normalize(data=pdata, record_path="dl_times", meta="id")
            for pdata in jdata
        ]
    ).set_index(["id", "block"])

    ledgers = pd.concat(
        [
            json_normalize(data=pdata, record_path="history", meta="id")
            for pdata in jdata
        ]
    )

    # use relative times for debt ratio update timestamps
    ledgers["time"] = ledgers["time"].apply(pd.to_datetime)
    t0 = ledgers["time"].min()
    ledgers["time"] = ledgers["time"].apply(lambda t: t - t0)
    ledgers = ledgers.set_index(["id", "peer", "time"])

    return {
        "params": params,
        "uploads": uploads,
        "dl_times": dl_times,
        "ledgers": ledgers,
    }


run()
