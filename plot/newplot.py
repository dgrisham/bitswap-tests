#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import argparse
import json
import traceback
import warnings

import pandas as pd
import matplotlib.pyplot as plt

from math import floor, ceil
from pandas.io.json import json_normalize

plt.style.use('ggplot')

"""
TODO:

"""

def main(argv):
    cli = argparse.ArgumentParser()
    cli.add_argument(
        'infile',
        metavar='<results_file>',
        type=str,
        help='json results file to load and plot',
    )
    cli.add_argument(
        '--no-plot',
        action='store_true',
        default=False,
        help='if passed, do not show plots',
    )
    cli.add_argument(
        '-k',
        '--kind',
        type=str,
        choices=['all', 'pairs'],
        default='all',
        help='which kind of plot to make',
    )
    args = cli.parse_args(argv)

    try:
        results = load(args.infile)
    except Exception as e:
        print(prependErr("loading results file", e), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

    try:
        plot(results['ledgers']['value'], kind=args.kind, prange=(0,1))
        if not args.no_plot:
            plt.show()
            plt.clf()
            plt.close()
    except Exception as e:
        print(prependErr("plotting results", e), file=sys.stderr)
        traceback.print_exc()

    return results

def load(fname):
    """
    Load json results file into 3 dataframes:
        1.  `uploads`: Set of blocks uploaded by each peer.
        2.  `dl_times`: Each peers' downloaded times for the blocks they downloaded.
        3.  `ledgers`: The Bitswap ledger update ledgers for each peer.
    Input:
        -   `fname` :: str: Path to json file to load.
    Returns: A dictionary containing the above dataframes.
    """

    with open(fname, 'r') as jfile:
        jdata = json.load(jfile)

    # load results into separate dataframes
    params = pd.DataFrame.from_records(jdata, exclude=['uploads', 'dl_times', 'history'], index='id')
    uploads  = pd.concat([json_normalize(data=pdata, record_path='uploads',  meta='id') for pdata in jdata]).set_index('id')
    dl_times = pd.concat([json_normalize(data=pdata, record_path='dl_times', meta='id') for pdata in jdata]).set_index(['id', 'block'])
    ledgers  = pd.concat([json_normalize(data=pdata, record_path='history',  meta='id') for pdata in jdata])

    # use relative times for debt ratio update timestamps
    ledgers['time'] = ledgers['time'].apply(pd.to_datetime)
    t0 = ledgers['time'].min()
    ledgers['time'] = ledgers['time'].apply(lambda t: t - t0)
    ledgers = ledgers.set_index(['id', 'peer', 'time'])

    return {'params': params, 'uploads': uploads, 'dl_times': dl_times, 'ledgers': ledgers}

def plot(dratios, kind='all', trange=None, prange=None):
    """
    Inputs:
        -   `ls :: pd.DataFrame`
        -   `kind :: str`: Which plotting function to use. Supports 'all' or 'pairs'.
        -   `trange :: (pd.Datetime, pd.Datetime)`
        -   `prange :: (float, float)`
    """

    if kind == 'all':
        plotAll(dratios, trange, prange)
    elif kind == 'pairs':
        plotPairs(dratios, trange, prange)

def plotAll(dratios, trange=None, prange=None):
    dratios.index = dratios.index.map(lambda idx: (idx[0], idx[1], idx[2].total_seconds()))
    time = dratios.index.levels[2]
    if trange is not None:
        ti, tf = trange
    elif prange is not None:
        ti = floor(prange[0] * len(time))
        tf = ceil(prange[1] * len(time)) - 1
    else:
        ti, tf = 0, len(time) - 1
    tmin, tmax = time[[ti, tf]]

    drmin  = dratios.min()
    drmax  = dratios.max()
    drmean = dratios.mean()

    num_peers = len(dratios.index.levels[0]) * (len(dratios.index.levels[1]) - 1)
    try:
        ax = makeAxes(1, num_peers, "Testing")
    except Exception as e:
        raise prependErr("error configuring plot axes", e)

    try:
        axLog = makeAxes(1, num_peers, "Testing", log=True)
    except Exception as e:
        raise prependErr("error configuring semi-log plot axes", e)


    for i, user in enumerate(dratios.index.levels[0]):
        u = dratios.loc[user]
        for j, peer in enumerate(u.index.levels[0]):
            if user == peer:
                continue
            pall = u.loc[peer]
            p = pall[(tmin <= pall.index) & (pall.index <= tmax)]
            if len(p) == 0:
                warn(f"no data for peers {i} ({user}) and {j} ({peer}) in time range [{tmin}, {tmax}]")
                continue
            factor = 0.25
            p.plot(xlim=(tmin, tmax), ylim=(drmin - factor*drmean, drmax + factor*drmean), ax=ax, label=f"Debt ratio of {j} wrt {i}")
            # p.plot(x=p.loc[tmax], y='value', ax=ax, style='bx', label='point')
            p.plot(xlim=(tmin, tmax), logy=True, ax=axLog, label=f"Debt ratio of {j} wrt {i}")
            axLog.set_ylim(top=drmax*1.5)

    try:
        cfgAxes([ax])
    except Exception as e:
        raise prependErr("post-plot axis config", e)
    try:
        cfgAxes([axLog], log=True)
    except Exception as e:
        raise prependErr("post-plot semi-log axis config", e)

def plotPairs(dratios, trange=None, prange=None):
    """
    -   Plots debt ratios (stored in `ls`, aka ledgers) from either:
        -   trange[0] to trange[1], or
        -   prange[0] * tf to prange[1] * tf, where tf is the last time that
            the ledgers were updated
    -   At the final plotted time, dot is shown where inner color is peer whose
        debt ratio it is, outer/border color is peer whose judgement it is.
    Inputs:
        -   `ls :: pd.DataFrame`
        -   `trange :: (pd.Datetime, pd.Datetime)`
        -   `prange :: (float, float)`
    """

    dratios.index = dratios.index.map(lambda idx: (idx[0], idx[1], idx[2].total_seconds()))
    time = dratios.index.levels[2]
    if trange is not None:
        ti, tf = trange
    elif prange is not None:
        ti = floor(prange[0] * len(time))
        tf = ceil(prange[1] * len(time)) - 1
    else:
        ti, tf = 0, len(time) - 1
    tmin, tmax = time[[ti, tf]]

    drmin  = dratios.min()
    drmax  = dratios.max()
    drmean = dratios.mean()

    n = len(dratios.index.levels[0])
    num_pairs = n * (len(dratios.index.levels[1]) - 1) // 2
    try:
        axes = makeAxes(n, num_pairs, "Testing")
    except Exception as e:
        raise prependErr("configuring plot axes", e)
    try:
        axesLog = makeAxes(n, num_pairs, "Testing", log=True)
    except Exception as e:
        raise prependErr("configuring semi-log plot axes", e)

    for i, user in enumerate(dratios.index.levels[0]):
        u = dratios.loc[user]
        for j, peer in enumerate(u.index.levels[0]):
            if user == peer:
                continue
            pall = u.loc[peer]
            p = pall[(tmin <= pall.index) & (pall.index <= tmax)]
            if len(p) == 0:
                warn(f"no data for peers {i} ({user}) and {j} ({peer}) in time range [{tmin}, {tmax}]")
                continue
            factor = 0.25
            p.plot(xlim=(tmin, tmax), ylim=(drmin - factor * drmean, drmax + factor * drmean), ax=axes[i], label=f"Debt ratio of {j} wrt {i}")
            if p[p > 0].count() == 0:
                warn(f"all debt ratios are 0 for peers {i} ({user}) and {j} ({peer}) in time range [{tmin}, {tmax}]. skipping semi-log plot")
                continue
            p.plot(xlim=(tmin, tmax), logy=True, ax=axesLog[i], label=f"Debt ratio of {j} wrt {i}")
            axesLog[i].set_ylim(top=drmax*1.5)

    try:
        cfgAxes(axes)
    except Exception as e:
        raise prependErr("configuring axes post-plot", e)
    try:
        cfgAxes(axesLog, log=True)
    except Exception as e:
        raise prependErr("configuring semi-log axes post-plot", e)

def makeAxes(n, cycle_len, plotTitle, log=False):
    """
    Create and configure `n` axes for a given debt ratio plot.
    Inputs:
        -   `n :: int`: Number of sub-plots to create.
        -   `plotTitle :: str`: Title of this plot.
        -   `log :: bool`: Whether the y-axis will be logarithmic.
    Returns:
        -   `[Axes]`: List containing the `n` axes.
    """

    fig, axes = plt.subplots(n)
    if n == 1:
        axList = [axes]
    else:
        axList = axes

    colors = ['black', 'magenta', 'blue', 'red', 'orange', 'green']
    for i, ax in enumerate(axList):
        ax.set_prop_cycle('color', colors[2*i : 2*i + cycle_len])

        title = f"User {i}'s Debt Ratios"
        ylabel = "Debt Ratio"
        if log:
            ax.set_title(f"{title} (Semi-Log)")
            ax.set_ylabel(f"log({ylabel})")
        else:
            ax.set_title(title)
            ax.set_ylabel(ylabel)

    fig.suptitle(plotTitle)
    fig.tight_layout()

    return axes

def cfgAxes(axes, log=False):
    for i, ax in enumerate(axes):
        ax.legend(prop={'size': 'large'})
        if i != len(axes) - 1:
            ax.set_xlabel('')
            plt.setp(ax.get_xticklabels(), visible=False)
        else:
            ax.set_xlabel("time (seconds)")
        if log:
            ax.set_yscale('symlog')

def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)

def prependErr(msg, e):
    return type(e)(f"error {msg}: {e}").with_traceback(sys.exc_info()[2])

if __name__ == '__main__':
    r = main(sys.argv[1:])
    ls = r['ledgers']
    p0, p1, p2 = ls.index.levels[0]