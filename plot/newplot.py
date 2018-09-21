#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import argparse
import json

import pandas as pd
import matplotlib.pyplot as plt

from pandas.io.json import json_normalize

plt.style.use('ggplot')

"""
TODO:

"""

def main(argv):
    cli = argparse.ArgumentParser()
    cli.add_argument(
        'infile',
        metavar='f',
        type=str,
        help='Results file to read.',
    )
    args = cli.parse_args(argv)

    try:
        results = load(args.infile)
    except Exception as e:
        print(prependErr("error loading results file", e), file=sys.stderr)
        sys.exit(1)

    try:
        plot(results['ledgers'])
    except Exception as e:
        print(prependErr("error plotting results", e), file=sys.stderr)

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
    uploads  = pd.concat([json_normalize(data=pdata, record_path='uploads',  meta='id') for pdata in jdata]).set_index('id')
    dl_times = pd.concat([json_normalize(data=pdata, record_path='dl_times', meta='id') for pdata in jdata]).set_index(['id', 'block'])
    ledgers  = pd.concat([json_normalize(data=pdata, record_path='history',  meta='id') for pdata in jdata])

    # use relative times for debt ratio update timestamps
    ledgers['time'] = ledgers['time'].apply(pd.to_datetime)
    t0 = ledgers['time'].min()
    ledgers['time'] = ledgers['time'].apply(lambda t: t - t0)
    ledgers = ledgers.set_index(['id', 'peer', 'time'])

    return {'uploads': uploads, 'dl_times': dl_times, 'ledgers': ledgers}

def plot(ls, trange=None, prange=None):
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

    time = ls.index.levels[1]
    if trange is not None:
        tmin, tmax = trange
    elif prange is not None:
        tmin, tmax = prange * max(time)
    else:
        tmin = min(time)
        tmax = max(time)

    drmin  = ls['value'].min()
    drmax  = ls['value'].max()
    drmean = ls['value'].mean()

    n = len(ls.index.levels[0])

    try:
        axes = makeAxes(3, "Testing")
        1/0
    except Exception as e:
        raise prependErr("error configuring plot axes", e)

    try:
        axesLog = makeAxes(3, "Testing", log=True)
    except Exception as e:
        raise prependErr("error configuring semi-log plot axes", e)

    for i, user in enumerate(ls.index.levels[0]):
        u = ls.loc[user]
        for j, peer in enumerate(u.index.levels[0]):
            if user == peer:
                continue
            p = u.loc[peer]
            factor = 0.25
            p.plot(y='value', xlim=(tmin, tmax), ylim=(drmin - factor * drmean, drmax + factor * drmean), ax=axes[i], label=f"Debt ratio of {j} wrt {i}")
            p.plot(y='value', xlim=(tmin, tmax), ylim=(drmin * 0.5, drmax * 1.5), logy=True, ax=axesLog[i], label=f"Debt ratio of {j} wrt {i}")
            axes[i].legend(prop={'size': 'large'})
            axesLog[i].legend(prop={'size': 'large'})

    plt.show()
    plt.clf()
    plt.close()

def makeAxes(n, plotTitle, log=False):
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
    colors = ['black', 'magenta', 'blue', 'red', 'orange', 'green']
    for i, ax in enumerate(axes):
        ax.set_prop_cycle('color', colors[2*i : 2*i + 2])

        title = f"User {i}'s Debt Ratios"
        ylabel = "Debt Ratio"
        if log:
            ax.set_title(f"{title} (Semi-Log)")
            ax.set_ylabel(f"log({ylabel})")
            ax.set_xscale('symlog')
            ax.set_yscale('symlog')
        else:
            ax.set_title(title)
            ax.set_ylabel(ylabel)

        if i != len(axes):
            ax.set_xlabel('')
            plt.setp(ax.get_xticklabels(), visible=False)

    fig.suptitle(plotTitle)
    fig.tight_layout()

    return axes

def prependErr(msg, e):
    return type(e)(f"{msg}: {e}").with_traceback(sys.exc_info()[2])

if __name__ == '__main__':
    r = main(sys.argv[1:])
    l = r['ledgers']
    p0, p1, p2 = l.index.levels[0]
