#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys

import matplotlib.pyplot as plt

from matplotlib import rcParams
from math import log10

plt.style.use("ggplot")
rcParams.update({"figure.autolayout": True})
rcParams["axes.titlepad"] = 4


def plot(ledgers, trange, cfg, outfilePrefix=None):
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
        -   outfilePrefix (str): basename of the file to save to (if any)
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
    plotTRange(ledgers, trange, axes, axesLog, "curve", drstats=drstats)
    plotTRange(ledgers, trange, axes, axesLog, "dot", colorMap=cfg["colorMap"])
    try:
        cfgAxes(axes)
    except Exception as e:
        raise prependErr("configuring axis post-plot", e)
    try:
        cfgAxes(axesLog, log=True, ymax=drstats["max"])
    except Exception as e:
        raise prependErr("configuring semi-log axis post-plot", e)

    if outfilePrefix is not None:
        fig.set_tight_layout(False)
        pdfOut = f"{outfilePrefix}.pdf"
        fig.savefig(pdfOut, bbox_inches="tight")

        figLog.set_tight_layout(False)
        pdfOutLog = f"{outfilePrefix}-semilog.pdf"
        figLog.savefig(pdfOutLog, bbox_inches="tight")


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
                # abusing kwargs
                kwargs["extend"] = plotDot(p, user, peer, ax, axLog, **kwargs)

    if kind == "dot":
        extendAxis(ax, kwargs["extend"])
        extendAxis(axLog, kwargs["extend"], log=True)


def plotCurve(p, trange, i, j, ax, axLog, drstats):
    """
    Plot history as a curve from trange[0] to trange[1].
    """
    factor = 0.25
    xmin, xmax = trange
    ymin, ymax = (
        drstats["min"] - factor * drstats["mean"],
        drstats["max"] + factor * drstats["mean"],
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


def plotDot(p, user, peer, ax, axLog, colorMap, extend=0):
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
    ri = recv / 10 ** int(log10(recv)) if recv > 0 else 0
    ro = sent / 10 ** int(log10(sent)) if sent > 0 else 0

    # TODO: figure out how to nicely scale the marker size
    msize = 3
    cInner, cOuter = colorMap[user, peer]
    ax.plot(
        t,
        d,
        color=cOuter,
        marker="o",
        markersize=(ri + ro) * msize,
        markeredgecolor="black",
    )
    ax.plot(
        t, d, color=cInner, marker="o", markersize=ri * msize, markeredgecolor="black"
    )
    axLog.plot(
        t,
        d,
        color=cOuter,
        marker="o",
        markersize=(ri + ro) * msize,
        markeredgecolor="black",
    )
    axLog.plot(
        t, d, color=cInner, marker="o", markersize=ri * msize, markeredgecolor="black"
    )

    return max(extend, (ri + ro) * msize / 2)


def extendAxis(ax, amt, log=False):
    xright = ax.get_xlim()[1]
    ax.set_xlim(right=xright + amt)
    ybottom = ax.get_ylim()[0]
    if not log:
        # TODO: need a better way to do this
        ax.set_ylim(bottom=ybottom - amt * 50000)


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


def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)


def prependErr(msg, e):
    return type(e)(f"error {msg}: {e}").with_traceback(sys.exc_info()[2])
