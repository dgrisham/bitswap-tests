#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import argparse
import json
import traceback
import warnings

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as patches

from itertools import islice
from collections import OrderedDict
from os.path import splitext
from math import floor, ceil
from matplotlib import rcParams
from pandas.io.json import json_normalize

plt.style.use('ggplot')
rcParams.update({'figure.autolayout': True})
rcParams['axes.titlepad'] = 4

"""
TODO:
    -   plotDot
"""

def main(argv):
    cli = argparse.ArgumentParser()
    cli.add_argument(
        'infile',
        metavar='<results_file>',
        type=str,
        help="json results file to load and plot",
    )
    cli.add_argument(
        '-k',
        '--kind',
        type=str,
        choices=['all', 'pairs'],
        default='all',
        help="which kind of plot to make",
    )
    cli.add_argument(
        '--no-show',
        action='store_true',
        default=False,
        help="do not show plots",
    )
    cli.add_argument(
        '-s',
        '--save',
        action='store_true',
        default=False,
        help="save plots",
    )
    args = cli.parse_args(argv)

    try:
        results = load(args.infile)
    except Exception as e:
        print(prependErr("loading results file", e), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

    try:
        if args.save:
            plot(results['ledgers']['value'], results['params'], kind=args.kind, prange=(0,1),
                    outfilePrefix=f'{splitext(args.infile)[0]}-{args.kind}')
        else:
            plot(results['ledgers']['value'], results['params'], kind=args.kind, prange=(0,1))
        if not args.no_show:
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

def plot(dratios, params, kind='all', trange=None, prange=None, outfilePrefix=None):
    """
    Purpose
        Plots debt ratios (stored in `ls`, aka ledgers) from either:
        -   trange[0] to trange[1], or
        -   prange[0] * tf to prange[1] * tf, where tf is the last time that
            the ledgers were updated
        Currently supports 2 kinds of plots:
        -   'all': Plot every peerwise time series of debt ratio values on one plot. This
                   will produce one plot with a line for each pair of peers.
        -   'pairs': Make one time-series plot for every pair of peers i j. Each plot will
                     contain two lines: one for user i's view of peer j, and one for j's
                     view of i.
        Note: Two users are considered 'peers' if at least one of them has a ledger history
              stored for the other.
    Inputs:
        -   `ls :: pd.DataFrame`
        -   `kind :: str`: Which plotting function to use.
        -   `trange :: (pd.Datetime, pd.Datetime)`
        -   `prange :: (float, float)`
    """

    colors = ['magenta', 'green', 'black', 'blue', 'orange', 'red']
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

    plotDot = True
    if kind == 'all':
        # only make a single plot axis
        n = 1
        # the color cycle length is equal to the number of pairs of peers (order matters)
        cycle_len = len(dratios.index.levels[0]) * (len(dratios.index.levels[1]) - 1)
    elif kind == 'pairs':
        # one plot axis for every peer
        n = len(dratios.index.levels[0])
        # the color cycle length is equal to the number of pairs of peers (order doesn't
        # matter)
        cycle_len = n * (len(dratios.index.levels[1]) - 1) // 2

    plotTitle = mkTitle(params)
    try:
        fig, axes = mkAxes(n, cycle_len, plotTitle, colors)
    except Exception as e:
        raise prependErr("error configuring plot axes", e)
    try:
        figLog, axesLog = mkAxes(n, cycle_len, plotTitle, colors, log=True)
    except Exception as e:
        raise prependErr("error configuring semi-log plot axes", e)

    drmin  = dratios.min()
    drmax  = dratios.max()
    drmean = dratios.mean()

    extend = 0
    for i, user in enumerate(dratios.index.levels[0]):
        u = dratios.loc[user]
        # k is the index of the axis we should be plotting on, based on which user
        # we're plotting, i, and the total number of plots we want by the end, n
        k = i % n
        ax = axes[k]
        axLog = axesLog[k]
        for j, peer in enumerate(u.index.levels[0]):
            if user == peer:
                continue
            pall = u.loc[peer]
            p = pall[(tmin <= pall.index) & (pall.index <= tmax)]
            if len(p) == 0:
                warn(f"no data for peers {i} ({user}) and {j} ({peer}) [{tmin}, {tmax}]")
                continue
            factor = 0.25
            xmin, xmax = tmin, tmax
            ymin, ymax = drmin - factor*drmean, drmax + factor*drmean
            p.plot(xlim=(xmin, xmax), ylim=(ymin, ymax), ax=ax, label=f"Debt ratio of {j} wrt {i}")
            p.plot(xlim=(xmin, xmax), logy=True, ax=axLog, label=f"Debt ratio of {j} wrt {i}")
            if plotDot:
                    inner = p.iloc[[-1]]
                    t, d = inner.index[0], inner.iloc[0]

                    pjall = dratios.loc[peer].loc[user]
                    dj = pjall[pjall.index <= t].iloc[[-1]].iloc[0]

                    msize = 10
                    ax.plot(t, d, color=colors[2*i+(j if j < i else j-1)], marker='o', markersize=(d+dj)*msize, markeredgecolor='black')
                    ax.plot(t, d, color=colors[(2*j+(i if i < j else i-1))], marker='o', markersize=d*msize, markeredgecolor='black')
                    extend = max(extend, (d+dj)*msize/2)

                    if d > 1:
                        dLog = np.log(d)
                    else:
                        dLog = d

                    axLog.plot(t, dLog, color=colors[2*i+(j if j < i else j-1)], marker='o', markersize=(d+dj)*msize, markeredgecolor='black')
                    axLog.plot(t, dLog, color=colors[(2*j+(i if i < j else i-1))], marker='o', markersize=d*msize, markeredgecolor='black')

        extendAxis(ax, extend)
        extendAxis(axLog, extend, log=True)
        axLog.set_ylim(top=drmax*1.5)

    try:
        cfgAxes(axes)
    except Exception as e:
        raise prependErr("configuring axis post-plot", e)
    try:
        cfgAxes(axesLog, log=True)
    except Exception as e:
        raise prependErr("configuring semi-log axis post-plot", e)

    if outfilePrefix is not None:
        fig.set_tight_layout(False)
        pdfOut = f'{outfilePrefix}.pdf'
        fig.savefig(pdfOut, bbox_inches='tight')

        figLog.set_tight_layout(False)
        pdfOutLog = f'{outfilePrefix}-semilog.pdf'
        figLog.savefig(pdfOutLog, bbox_inches='tight')

def extendAxis(ax, amt, log=False):
    xright = ax.get_xlim()[1]
    ax.set_xlim(right=xright+amt)
    ybottom = ax.get_ylim()[0]
    if not log:
        # TODO: need a better way to do this
        ax.set_ylim(bottom=ybottom-amt*50000)

def mkTitle(params):
    paramTitles = OrderedDict()
    paramTitles['strategy']         = 'RF'
    paramTitles['upload_bandwidth'] = 'BW'
    paramTitles['round_burst']      = 'RB'

    pts = []
    for p, t in paramTitles.items():
        vals = params[p]
        if vals.nunique() == 1:
            pts.append(f"{t}: {vals[0].title()}")
        else:
            pts.append(f"{t}s: {', '.join(vals).title()}")

    return f"Debt Ratio vs. Time -- {', '.join(pts)}"

def mkAxes(n, cycle_len, plotTitle, colors, log=False):
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
        axes = [axes]

    for i, ax in enumerate(axes):
        ax.set_prop_cycle('color', colors[2*i : 2*i + cycle_len])

        if n > 1:
            # if there are multiple plots in this figure, give each one a unique subtitle
            title = f"User {i}"
            axArgs = { 'fontsize' : 'medium',
                       'bbox': { 'boxstyle'  : 'round',
                                 'facecolor' : ax.get_facecolor(),
                                 'edgecolor' : '#000000',
                                 'linewidth' : 1,
                                },
                     }
            ax.set_title(title, **axArgs)

        ylabel = "Debt Ratio"
        titleArgs = { 'fontsize' : 'large',
                      'x'        : (ax.get_position().xmin+ax.get_position().xmax) / 2,
                      'y'        : 1.02,
                      'ha'       : 'center',
                      'bbox': { 'boxstyle' : 'round',
                               'facecolor' : ax.get_facecolor(),
                               'edgecolor' : '#000000',
                               'linewidth' : 1,
                              },
                    }
        if log:
            ax.set_ylabel(f"log({ylabel})")
            fig.suptitle(f"{plotTitle} (Semi-Log)", **titleArgs)
        else:
            ax.set_ylabel(ylabel)
            fig.suptitle(plotTitle, **titleArgs)

    fig.subplots_adjust(hspace=0.5)

    return fig, axes

def cfgAxes(axes, log=False):
    """
    Configure axes settings that must be set after plotting (e.g. because the
    pandas plotting function overwrites them).
    """

    for i, ax in enumerate(axes):
        ax.legend(prop={'size': 'medium'})
        if i != len(axes) - 1:
            ax.set_xlabel('')
            plt.setp(ax.get_xticklabels(), visible=False)
        else:
            ax.set_xlabel("time (seconds)")
        if log:
            ax.set_yscale('symlog')
            if len(axes) > 1:
                yticks = ax.get_yticks()
                ax.set_yticks([yticks[i] for i in range(len(yticks)) if i % 2 == 0])

def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)

def prependErr(msg, e):
    return type(e)(f"error {msg}: {e}").with_traceback(sys.exc_info()[2])

if __name__ == '__main__':
    r = main(sys.argv[1:])
    ls = r['ledgers']
    p0, p1, p2 = ls.index.levels[0]
