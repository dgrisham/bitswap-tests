#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import argparse
import json
import traceback

import pandas as pd
import matplotlib.pyplot as plt

from collections import OrderedDict
from os.path import splitext
from math import floor, ceil, log10
from matplotlib import rcParams
from pandas.io.json import json_normalize

plt.style.use('ggplot')
rcParams.update({'figure.autolayout': True})
rcParams['axes.titlepad'] = 4


def main(argv):
    cli = argparse.ArgumentParser()
    rangeArgs = cli.add_mutually_exclusive_group()
    rangeArgs.add_argument(
        '-p',
        '--prange',
        nargs=2,
        type=float,
        help="specify lower and upper time range as percentages of total time",
    )
    rangeArgs.add_argument(
        '-t',
        '--trange',
        nargs=2,
        type=float,
        help="specify lower and upper time range as literal time values",
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
    cli.add_argument(
        'infile',
        metavar='<results_file>',
        type=str,
        help="json results file to load and plot",
    )
    args = cli.parse_args(argv)

    try:
        results = load(args.infile)
    except Exception as e:
        print(prependErr("loading results file", e), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

    results['ledgers'].index = results['ledgers'].index.map(
        lambda idx: (idx[0], idx[1], idx[2].total_seconds()))
    time = results['ledgers'].index.levels[2]
    if args.prange is not None:
        ti = floor(args.prange[0] * len(time))
        tf = ceil(args.prange[1] * len(time)) - 1
    elif args.trange is not None:
        ti, tf = args.trange
    else:
        ti, tf = 0, len(time) - 1
    trange = time[[ti, tf]]

    plotCfg = getPlotConfig(results['ledgers'], trange, results['params'],
                            args.kind)
    try:
        if args.save:
            plot(results['ledgers'], trange, plotCfg,
                 f'{splitext(args.infile)[0]}-{args.kind}')
        else:
            plot(results['ledgers'], trange, plotCfg)
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
        2.  `dl_times`: Each peers' downloaded times for the blocks they
            downloaded.
        3.  `ledgers`: The Bitswap ledger update ledgers for each peer.
    Input:
        -   `fname` :: str: Path to json file to load.
    Returns:
        A dictionary containing the above dataframes.
    """

    with open(fname, 'r') as jfile:
        jdata = json.load(jfile)

    # load results into separate dataframes
    params = pd.DataFrame.from_records(
        jdata, exclude=['uploads', 'dl_times', 'history'], index='id')

    uploads = pd.concat([
        json_normalize(data=pdata, record_path='uploads', meta='id')
        for pdata in jdata
    ]).set_index('id')

    dl_times = pd.concat([
        json_normalize(data=pdata, record_path='dl_times', meta='id')
        for pdata in jdata
    ]).set_index(['id', 'block'])

    ledgers = pd.concat([
        json_normalize(data=pdata, record_path='history', meta='id')
        for pdata in jdata
    ])

    # use relative times for debt ratio update timestamps
    ledgers['time'] = ledgers['time'].apply(pd.to_datetime)
    t0 = ledgers['time'].min()
    ledgers['time'] = ledgers['time'].apply(lambda t: t - t0)
    ledgers = ledgers.set_index(['id', 'peer', 'time'])

    return {
        'params': params,
        'uploads': uploads,
        'dl_times': dl_times,
        'ledgers': ledgers
    }


def getPlotConfig(ledgers, trange, params, kind):
    """
    Get all of the configuration values needed by plot().

    Inputs:
        -   `ledgers :: pd.DataFrame`
        -   `trange :: (pd.Datetime, pd.Datetime)`: Time range to plot
        -   `params :: dict`: Node parameters as loaded in load().
        -   `kind :: str`: Which type of plot to configure for. Possible
            values:
            -   'all': Plot every peerwise time series of debt ratio values on
                one plot. This will produce one plot with a line for each pair
                of peers.
            -   'pairs': Make one time-series plot for each pair of peers i, j.
                Each plot will contain two lines: one for user i's view of peer
                j, and one for j's view of i.
        Note: Two users are considered 'peers' if at least one of them has a
        ledger history stored for the other.

    Returns:
        `cfg :: dict`: Dictionary containing the following keys/values:
            -   `title :: str`: The plot title.
            -   `num_axes :: int`: The number of sub-plots to make.
            -   `pairs :: int`: The number of pairs of peers there are to
                plot. One for every pair of peers that have a history
                together.
            -   `cycleLen :: int`: The length of the color cycle for
                matplotlib.
            -   `colors :: [str]`: List of the colors to use in the color
                cycle.
            -   `colorMap :: dict{(str, str): (str, str)}`: Dictionary that
                maps from an ordered pair of peers to their corresponding
                pair of plot colors.
    """

    tmin, tmax = trange
    colorPairs = [
        ('magenta', 'black'),
        ('green', 'orange'),
        ('blue', 'red')
    ]
    colorMap = {}
    colors = []
    # figure out how many peers have a history in this data range, and assign
    # colors to each pair
    pairs = 0
    for user in ledgers.index.levels[0]:
        u = ledgers.loc[user]
        for peer in u.index.levels[0]:
            if user == peer:
                continue
            p = u.loc[peer]
            if len(p[(tmin <= p.index) & (p.index <= tmax)]) > 0:
                if (user, peer) not in colorMap:
                    colors.append(colorPairs[pairs][0])
                    colorMap[user, peer] = colorPairs[pairs]
                    colorMap[peer, user] = colorPairs[pairs][::-1]
                    pairs += 1
                else:
                    colors.append(colorMap[peer, user][1])

    if kind == 'all':
        # only make a single plot axis
        n = 1
        # the color cycle length is equal to the number of pairs of peers
        # (order matters)
        cycleLen = pairs * 2
    elif kind == 'pairs':
        # one plot axis for every peer
        n = pairs // 2
        # the color cycle length is equal to the number of pairs of peers
        # (order doesn't matter)
        cycleLen = pairs

    return {
        'title': mkTitle(params),
        'num_axes': n,
        'pairs': pairs,
        'cycleLen': cycleLen,
        'colors': colors,
        'colorMap': colorMap,
    }


def mkTitle(params):
    paramTitles = OrderedDict()
    paramTitles['strategy'] = 'RF'
    paramTitles['upload_bandwidth'] = 'BW'
    paramTitles['round_burst'] = 'RB'

    pts = []
    for p, t in paramTitles.items():
        vals = params[p]
        if vals.nunique() == 1:
            pts.append(f"{t}: {vals[0].title()}")
        else:
            pts.append(f"{t}s: {', '.join(vals).title()}")

    return f"Debt Ratio vs. Time -- {', '.join(pts)}"


def plot(ledgers, trange, cfg, outfilePrefix=None):
    """
    Plots debt ratios (stored in `ledgers`) from trange[0] to' trange[1].
    The history time series is plotted as a curve where the y-axis is the
    debt ratio value. Two concentric circles are plotted at trange[1] for
    each pair of peers i, j, where the inner circle's radius represents the
    amount of data j has sent to i and the outer radius represents the
    amount of data i has sent to j.

    Inputs:
        -   `ledgers :: pd.DataFrame`
        -   `trange :: (pd.Datetime, pd.Datetime)`: Time range to plot
        -   `cfg :: dict`: Plot config. See getPlotConfig().
        -   `outfilePrefix :: str`: basename of the file to save to (if any)
    """

    try:
        fig, axes = mkAxes(cfg['num_axes'], cfg['cycleLen'], cfg['title'],
                           cfg['colors'])
    except Exception as e:
        raise prependErr("error configuring plot axes", e)
    try:
        figLog, axesLog = mkAxes(cfg['num_axes'], cfg['cycleLen'],
                                 cfg['title'], cfg['colors'], log=True)
    except Exception as e:
        raise prependErr("error configuring semi-log plot axes", e)

    drstats = {
        'min': ledgers['value'].min(),
        'max': ledgers['value'].max(),
        'mean': ledgers['value'].mean(),
    }
    plotTRange(ledgers, trange, axes, axesLog, 'curve', drstats=drstats)
    plotTRange(ledgers, trange, axes, axesLog, 'dot', colorMap=cfg['colorMap'])
    try:
        cfgAxes(axes)
    except Exception as e:
        raise prependErr("configuring axis post-plot", e)
    try:
        cfgAxes(axesLog, log=True, ymax=drstats['max'])
    except Exception as e:
        raise prependErr("configuring semi-log axis post-plot", e)

    if outfilePrefix is not None:
        fig.set_tight_layout(False)
        pdfOut = f'{outfilePrefix}.pdf'
        fig.savefig(pdfOut, bbox_inches='tight')

        figLog.set_tight_layout(False)
        pdfOutLog = f'{outfilePrefix}-semilog.pdf'
        figLog.savefig(pdfOutLog, bbox_inches='tight')


def plotTRange(ledgers, trange, axes, axesLog, kind, **kwargs):
    """
    Inputs:
        -   `ledgers :: pd.DataFrame`
        -   `trange :: (pd.Datetime, pd.Datetime)`: Time range to plot
        -   `axes :: [matplotlib.axes]`
        -   `axesLog :: [matplotlib.axes]`
        -   `kind :: str`: Which plot to make. Possible values:
            -   'curve': Plot the time series curve from trange[0] to
                trange[1].
            -   'dot': Plot the dot at trange[1].
        -   `kwargs :: dict`: Keyword arguments for wrapped plot functions.
    """

    tmin, tmax = trange
    # k is the index of the axis we should be plotting on
    k = 0
    for i, user in enumerate(ledgers.index.levels[0]):
        u = ledgers.loc[user]
        ax = axes[k]
        axLog = axesLog[k]
        for j, peer in enumerate(u.index.levels[0]):
            if user == peer:
                continue
            pall = u.loc[peer]
            p = pall[(tmin <= pall.index) & (pall.index <= tmax)]

            if kind == 'curve':
                if len(p) == 0:
                    warn(f"no data for peers {i} ({user}) and {j} ({peer}) in "
                         f"[{tmin}, {tmax}]")
                    continue
                plotCurve(p, trange, i, j, ax, axLog, **kwargs)
            elif kind == 'dot':
                if len(p) == 0:
                    continue
                # abusing kwargs
                kwargs['extend'] = plotDot(p, user, peer, ax, axLog, **kwargs)

    if kind == 'dot':
        extendAxis(ax, kwargs['extend'])
        extendAxis(axLog, kwargs['extend'], log=True)


def plotCurve(p, trange, i, j, ax, axLog, drstats):
    factor = 0.25
    xmin, xmax = trange
    ymin, ymax = drstats['min'] - factor * \
        drstats['mean'], drstats['max'] + factor*drstats['mean']
    p.plot(y='value', xlim=(xmin, xmax), ylim=(ymin, ymax), ax=ax,
           label=f"Debt ratio of {j} wrt {i}")
    p.plot(y='value', xlim=(xmin, xmax), logy=True, ax=axLog,
           label=f"Debt ratio of {j} wrt {i}")


def plotDot(p, user, peer, ax, axLog, colorMap, extend=0):
    inner = p.iloc[[-1]]
    t, d = inner.index[0], inner.iloc[0]['value']
    recv = inner['recv'].item()
    sent = inner['sent'].item()
    ri = recv / 10 ** int(log10(recv)) if recv > 0 else 0
    ro = sent / 10 ** int(log10(sent)) if sent > 0 else 0

    # TODO: figure out how to nicely scale the marker size
    msize = 3
    cInner, cOuter = colorMap[user, peer]
    ax.plot(t, d, color=cOuter, marker='o', markersize=(ri+ro)*msize,
            markeredgecolor='black')
    ax.plot(t, d, color=cInner, marker='o', markersize=ri*msize,
            markeredgecolor='black')
    axLog.plot(t, d, color=cOuter, marker='o', markersize=(ri+ro)*msize,
               markeredgecolor='black')
    axLog.plot(t, d, color=cInner, marker='o', markersize=ri*msize,
               markeredgecolor='black')

    return max(extend, (ri+ro)*msize/2)


def extendAxis(ax, amt, log=False):
    xright = ax.get_xlim()[1]
    ax.set_xlim(right=xright+amt)
    ybottom = ax.get_ylim()[0]
    if not log:
        # TODO: need a better way to do this
        ax.set_ylim(bottom=ybottom-amt*50000)


def mkAxes(n, cycleLen, plotTitle, colors, log=False):
    """
    Create and configure `n` axes for a given debt ratio plot.

    Inputs:
        -   `n :: int`: Number of sub-plots to create.
        -   `plotTitle :: str`: Title of this plot.
        -   `log :: bool`: Whether the y-axis will be logarithmic.

    Returns:
        `[matplotlib.axes]`: List containing the `n` axes.
    """

    fig, axes = plt.subplots(n)
    if n == 1:
        axes = [axes]

    for i, ax in enumerate(axes):
        ax.set_prop_cycle('color', colors[2*i: 2*i + cycleLen])

        if n > 1:
            # if there are multiple plots in this figure, give each one a
            # unique subtitle
            title = f"User {i}"
            axArgs = {'fontsize': 'medium',
                      'bbox': {'boxstyle': 'round',
                               'facecolor': ax.get_facecolor(),
                               'edgecolor': '#000000',
                               'linewidth': 1,
                               },
                      }
            ax.set_title(title, **axArgs)

        ylabel = "Debt Ratio"
        titleArgs = {'fontsize': 'large',
                     'x': (ax.get_position().xmin+ax.get_position().xmax) / 2,
                     'y': 1.02,
                     'ha': 'center',
                     'bbox': {'boxstyle': 'round',
                              'facecolor': ax.get_facecolor(),
                              'edgecolor': '#000000',
                              'linewidth': 1,
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


def cfgAxes(axes, log=False, **kwargs):
    """
    Configure axes settings that must be set after plotting (e.g. because
    the pandas plotting function overwrites them).
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
            ax.set_ylim(top=kwargs['ymax']*1.5)
            if len(axes) > 1:
                yticks = ax.get_yticks()
                ax.set_yticks([yticks[i]
                               for i in range(len(yticks)) if i % 2 == 0])


def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)


def prependErr(msg, e):
    return type(e)(f"error {msg}: {e}").with_traceback(sys.exc_info()[2])


if __name__ == '__main__':
    main(sys.argv[1:])
