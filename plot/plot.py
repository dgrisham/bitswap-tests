#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import re
import argparse
import pandas as pd

#import matplotlib as mpl
#mpl.use('Agg')
import matplotlib.pyplot as plt

plt.style.use('ggplot')

def main(argv):
    cli = argparse.ArgumentParser()
    cli.add_argument(
        'infile',
        metavar='f',
        type=str,
        help='Input aggregate results file.',
    )
    cli.add_argument(
        '--no-plot',
        action='store_true',
        default=False,
    )
    args = cli.parse_args(argv)

    try:
        aggregate = loadAggregate(args.infile)
    except Exception as e:
        print(f"error loading aggregate file: {e}")
        sys.exit(1)

    history = loadLedgers(aggregate.index.map(lambda uid: uid[2:8]), args.infile[:-len("aggregate")])
    if not args.no_plot:
        plotNew(history, outfile=args.infile[:-len("-aggregate")])

    return aggregate, history

def loadAggregate(infile):
    fname = os.path.basename(infile)
    freg = r'(?:(?P<strategy>[a-z]+)-)?(?:rb_(?P<burst>\d+(?:_\d+)*)-)?bw_(?P<dist>\d+(?:_\d+)+)-aggregate'
    fmatch = re.match(freg, fname)

    if fmatch is None:
        raise Exception(f"Bad filename format: {fname}")
    resources = [int(b) for b in fmatch.group('dist').split('_')]

    aggregate = pd.read_csv(infile, index_col=0)
    return aggregate

    # dl_times = {}
    # treg = r'(?:(?P<m>\d+)m)?(?P<s>\d+)s'
    # for peer, row in data.iterrows():
    #     ptime = re.match(treg, row['dl_time'])
    #     if ptime is not None:
    #         minutes = int(ptime.group('m')) if ptime.group('m') is not None else 0
    #         dl_times[peer] = minutes * 60 + int(ptime.group('s'))

    # ratios = {}
    # for peer, time in dl_times.items():
    #     ratios[peer] = (resources[peer] / sum(resources)) / (time / sum(dl_times.values()))

    # return ratios, data

def loadLedgers(uids, fprefix):
    ledgers = []
    print(f'{fprefix}')
    if '/1/' in fprefix:
        # TODO: this is a bad way to handle this
        skip0 = True
    for i, uid in enumerate(uids):
        if i == 0 and skip0:
            continue
        ledgers_i = pd.read_csv(f"{fprefix}ledgers_{i}")
        ledgers_i.index = pd.MultiIndex.from_arrays([ledgers_i.index.map(lambda i: i // 2), [uid] * ledgers_i.shape[0], ledgers_i['id']])
        ledgers_i = ledgers_i.drop('id', axis=1)
        ledgers_i.index = ledgers_i.index.map(lambda idx: (idx[0], uids.get_loc(idx[1]), uids.get_loc(idx[2])))
        ledgers.append(ledgers_i)
    return pd.concat(ledgers).sort_index()

def plotNew(history, save=False, show=True, outfile=''):
    dr_min = history['debt_ratio'].min()
    dr_max = history['debt_ratio'].max()
    dr_mean = history['debt_ratio'].mean()
    fig, axes = plt.subplots(3)
    figLog, axesLog = plt.subplots(3)

    axes[0].set_prop_cycle('color', ['black', 'magenta'])
    axes[1].set_prop_cycle('color', ['blue', 'red'])
    axes[2].set_prop_cycle('color', ['orange', 'green'])

    axesLog[0].set_prop_cycle('color', ['black', 'magenta'])
    axesLog[1].set_prop_cycle('color', ['blue', 'red'])
    axesLog[2].set_prop_cycle('color', ['orange', 'green'])

    for (i, j), hij in history.groupby(level=[1, 2]):
        hij.index = hij.index.droplevel([1, 2])
        factor = 0.25
        hij.plot(y='debt_ratio', xlim=(0, hij.index.get_level_values(0).max()), ylim=(dr_min - factor * dr_mean, dr_max + factor * dr_mean), ax=axes[i], label=f"Debt ratio of {j} wrt {i}")
        hij.plot(y='debt_ratio', xlim=(0, hij.index.get_level_values(0).max()), ylim=(dr_min * 0.5, dr_max * 1.5), logy=True, ax=axesLog[i], label=f"Debt ratio of {j} wrt {i}")

        legendFont = 'large'
        axes[i].legend(prop={'size': legendFont})
        axesLog[i].legend(prop={'size': legendFont})

        title = f"User {i}'s Debt Ratios"
        axes[i].set_title(title)
        axesLog[i].set_title(f"{title} (Semi-Log)")

        ylabel = "Debt Ratio"
        axes[i].set_ylabel(ylabel)
        axesLog[i].set_ylabel(f"log({ylabel})")

    pts = outfile.split('-')
    if len(pts) < 7:
        title = outfile
    else:
        title = f"RF: {pts[0].title()}, IR: {pts[1].title()}, Data: {pts[2]}, DPR: [{pts[3].replace('_', ', ')}], UR: [{pts[4].replace('_', ', ')}], {pts[5].replace('_', ' ').title()} ({pts[6].title()})"

    fig.suptitle(title)
    axes[0].set_xlabel('')
    axes[1].set_xlabel('')

    figLog.suptitle(title)
    axesLog[0].set_xlabel('')
    axesLog[1].set_xlabel('')

    fig.tight_layout()
    figLog.tight_layout()

    plt.setp(axes[0].get_xticklabels(), visible=False)
    plt.setp(axes[1].get_xticklabels(), visible=False)
    plt.setp(axesLog[0].get_xticklabels(), visible=False)
    plt.setp(axesLog[1].get_xticklabels(), visible=False)

    if save and outfile:
        plt.savefig(f"plots-new/{outfile}.pdf")
    if show:
        plt.show()

    plt.clf()
    plt.close()

if __name__ == '__main__':
    aggregate, history = main(sys.argv[1:])
