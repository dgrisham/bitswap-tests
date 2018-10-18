#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os.path

import matplotlib.pyplot as plt

from math import log10
from collections import OrderedDict
from matplotlib import rcParams

plt.style.use("ggplot")
rcParams.update({"figure.autolayout": True})
rcParams["axes.titlepad"] = 4
rcParams["axes.xmargin"] = 0.1
rcParams["axes.ymargin"] = 0.1


def plot(ledgers, trange, cfg):
    """
    Plots debt ratios (stored in `ledgers`) from trange[0] to' trange[1].
    The history time series is plotted as a curve where the y-axis is the
    debt ratio value. Two concentric circles are plotted at trange[1] for
    each pair of peers i, j, where the inner circle's radius represents the
    amount of data j has sent to i and the outer radius represents the
    amount of data i has sent to j.

    Inputs:
        -   ledgers (pd.DataFrame)
        -   trange ((pd.Datetime, pd.Datetime)): Time range to plot
        -   cfg (dict): Plot config. See getPlotConfig().
    """

    try:
        fig, axes = mkAxes(
            cfg["num_axes"], cfg["cycleLen"], cfg["title"], cfg["colors"]
        )
    except Exception as e:
        raise prependErr("error configuring plot axes", e)
    try:
        figLog, axesLog = mkAxes(
            cfg["num_axes"], cfg["cycleLen"], cfg["title"], cfg["colors"], log=True
        )
    except Exception as e:
        raise prependErr("error configuring semi-log plot axes", e)

    drstats = {
        "min": ledgers["value"].min(),
        "max": ledgers["value"].max(),
        "mean": ledgers["value"].mean(),
    }
    plotTRange(ledgers, trange, axes, axesLog, "curve", stats=drstats)
    sent_max = ledgers["sent"].xs(trange[1], level=2).max().round()
    plotTRange(
        ledgers,
        trange,
        axes,
        axesLog,
        "dot",
        colorMap=cfg["colorMap"],
        sent_max=sent_max,
    )
    try:
        cfgAxes(axes)
    except Exception as e:
        raise prependErr("configuring axis post-plot", e)
    try:
        cfgAxes(axesLog, log=True, ymax=drstats["max"])
    except Exception as e:
        raise prependErr("configuring semi-log axis post-plot", e)

    if cfg["fbasename"] is not None:
        fig.set_tight_layout(False)
        outfile = os.path.join(cfg["fdir"], f"{cfg['fbasename']}{cfg['fext']}")
        fig.savefig(outfile, bbox_inches="tight")
        print(f"saved linear plot to {outfile}")

        figLog.set_tight_layout(False)
        outfileLog = os.path.join(
            cfg["fdir"], f"{cfg['fbasename']}-semilog{cfg['fext']}"
        )
        figLog.savefig(outfileLog, bbox_inches="tight")
        print(f"saved log plot to {outfileLog}")


def plotTRange(ledgers, trange, axes, axesLog, kind, **kwargs):
    """
    Inputs:
        -   ledgers (pd.DataFrame)
        -   trange ((pd.Datetime, pd.Datetime)): Time range to plot
        -   axes ([matplotlib.axes])
        -   axesLog ([matplotlib.axes])
        -   kind (str): Which plot to make. Possible values:
            -   'curve': Plot the time series curve from trange[0] to
                trange[1].
            -   'dot': Plot the dot at trange[1].
        -   kwargs (dict): Keyword arguments for wrapped plot functions.
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

            if kind == "curve":
                if len(p) == 0:
                    warn(
                        f"no data for peers {i} ({user}) and {j} ({peer}) in "
                        f"[{tmin}, {tmax}]"
                    )
                    continue
                plotCurve(p, trange, i, j, ax, axLog, **kwargs)
            elif kind == "dot":
                if len(p) == 0:
                    continue
                plotDot(p, user, peer, ax, axLog, **kwargs)
        k = (k + 1) % len(axes)


def plotCurve(p, trange, i, j, ax, axLog, stats):
    """
    Plot history as a curve from trange[0] to trange[1].
    """
    factor = 0.25
    xmin, xmax = trange
    ymin, ymax = (
        stats["min"] - factor * stats["mean"],
        stats["max"] + factor * stats["mean"],
    )
    p.plot(
        y="value",
        xlim=(xmin, xmax),
        ylim=(ymin, ymax),
        ax=ax,
        label=f"Debt ratio of {j} wrt {i}",
    )
    p.plot(
        y="value",
        xlim=(xmin, xmax),
        logy=True,
        ax=axLog,
        label=f"Debt ratio of {j} wrt {i}",
    )
    return {"xmin": xmin, "xmax": xmax, "ymin": ymin, "ymax": ymax}


def plotDot(p, user, peer, ax, axLog, colorMap, sent_max):
    """
    For a given user, peer pair, plot two concentric circles at the last time
    user updated their ledger for peer. The inner circle's radius corresponds
    to the amount of data user had sent peer at that time, and the difference
    between the outer and inner radii corresponds to the amount of data peer
    had sent peer at that time. colorMap is a map from (user, peer) pairs to
    (color, color), where the first color is that of the inner circle and the
    second is that of the outer circle.
    """

    inner = p.iloc[[-1]]
    t, d = inner.index[0], inner.iloc[0]["value"]
    recv = inner["recv"].item()
    sent = inner["sent"].item()
    # TODO: figure out how to nicely scale the marker size
    msize = 10
    ri = msize * recv / 10 ** int(log10(sent_max)) if sent_max > 0 else 0
    ro = ri + msize * sent / 10 ** int(log10(sent_max)) if sent_max > 0 else 0

    cInner, cOuter = colorMap[user, peer]
    ax.plot(t, d, color=cOuter, marker="o", markersize=ro, markeredgecolor="black")
    ax.plot(t, d, color=cInner, marker="o", markersize=ri, markeredgecolor="black")
    axLog.plot(t, d, color=cOuter, marker="o", markersize=ro, markeredgecolor="black")
    axLog.plot(t, d, color=cInner, marker="o", markersize=ri, markeredgecolor="black")


def mkAxes(n, cycleLen, plotTitle, colors, log=False):
    """
    Create and configure `n` axes for a given debt ratio plot.

    Inputs:
        -   n (int): Number of sub-plots to create.
        -   plotTitle (str): Title of this plot.
        -   log (bool): Whether the y-axis will be logarithmic.

    Returns:
        [matplotlib.axes]: List containing the `n` axes.
    """

    fig, axes = plt.subplots(n)
    if n == 1:
        axes = [axes]

    for i, ax in enumerate(axes):
        ax.set_prop_cycle("color", colors[2 * i : 2 * i + cycleLen])

        if n > 1:
            # if there are multiple plots in this figure, give each one a
            # unique subtitle
            title = f"User {i}"
            axArgs = {
                "fontsize": "medium",
                "bbox": {
                    "boxstyle": "round",
                    "facecolor": ax.get_facecolor(),
                    "edgecolor": "#000000",
                    "linewidth": 1,
                },
            }
            ax.set_title(title, **axArgs)

        ylabel = "Debt Ratio"
        titleArgs = {
            "fontsize": "large",
            "x": (ax.get_position().xmin + ax.get_position().xmax) / 2,
            "y": 1.02,
            "ha": "center",
            "bbox": {
                "boxstyle": "round",
                "facecolor": ax.get_facecolor(),
                "edgecolor": "#000000",
                "linewidth": 1,
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
        ax.legend(prop={"size": "medium"})
        if i != len(axes) - 1:
            ax.set_xlabel("")
            plt.setp(ax.get_xticklabels(), visible=False)
        else:
            ax.set_xlabel("time (seconds)")
        if log:
            ax.set_yscale("symlog")
            ax.set_ylim(top=kwargs["ymax"] * 1.5)
            if len(axes) > 1:
                yticks = ax.get_yticks()
                ax.set_yticks([yticks[i] for i in range(len(yticks)) if i % 2 == 0])
        ax.autoscale(tight=False)


def mkPlotConfig(ledgers, trange, params, kind, **kwargs):
    """
    Get all of the configuration values needed by plot().

    Inputs:
        -   ledgers (pd.DataFrame)
        -   trange ((pd.Datetime, pd.Datetime)): Time range to plot
        -   params (dict): Node parameters as loaded in load().
        -   kind (str): Which type of plot to configure for. Possible
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
        cfg (dict): Dictionary containing the following keys/values:
            -   title (str): The plot title.
            -   fbasename (str): Basename of the file to save the plot to (if any).
                This value should be None if the plot should not be saved.
            -   fext (str): Extension to use when saving the plot. Only used if
                fbasename field is not None.
            -   fdir (str): Directory to save the plot to.
            -   num_axes (int): The number of sub-plots to make.
            -   pairs (int): The number of pairs of peers there are to plot. One for
                every pair of peers that have a history together.
            -   cycleLen (int): The length of the color cycle for matplotlib.
            -   colors ([str]): List of the colors to use in the color cycle.
            -   colorMap (dict{(str, str): (str, str)}): Dictionary that maps an
                ordered pair of peers to their corresponding pair of plot colors.
    """

    paramTitles = OrderedDict()
    paramTitles["strategy"] = "RF"
    paramTitles["upload_bandwidth"] = "BW"
    paramTitles["round_burst"] = "RB"
    pts = []
    for p, t in paramTitles.items():
        vals = params[p]
        if vals.nunique() == 1:
            pts.append(f"{t}: {vals[0].title()}")
        else:
            pts.append(f"{t}s: [{', '.join(vals).title()}]")
    title = f"Debt Ratio vs. Time -- {', '.join(pts)}"
    fbasename = (
        f"{'-'.join(pts)}".replace(", ", "_")
        .replace(": ", "-")
        .translate({ord(c): None for c in "[]"})
        .lower()
    )

    tmin, tmax = trange
    colorPairs = [("magenta", "black"), ("green", "orange"), ("blue", "red")]
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

    if kind == "all":
        # only make a single plot axis
        n = 1
        # the color cycle length is equal to the number of pairs of peers
        # (order matters)
        cycleLen = pairs * 2
    elif kind == "pairs":
        # one plot axis for every user
        n = pairs
        # the color cycle length is equal to the number of pairs of peers
        # (order doesn't matter)
        cycleLen = pairs

    return {
        "title": title,
        "fbasename": fbasename,
        "fext": ".pdf",
        "num_axes": n,
        "pairs": pairs,
        "cycleLen": cycleLen,
        "colors": colors,
        "colorMap": colorMap,
        **kwargs,
    }


def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)


def prependErr(msg, e):
    return type(e)(f"error {msg}: {e}").with_traceback(sys.exc_info()[2])
