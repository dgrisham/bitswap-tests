#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import re
import pandas as pd

#import matplotlib as mpl
#mpl.use('Agg')
#import matplotlib.pyplot as plt

def main(argv):
    infile = argv[0]
    fname = os.path.basename(infile)
    freg = r'(?:(?P<dist>\d+(?:_\d+)+)|(?:(?P<hom_bw>\d+)x(?P<hom_num>\d+)))-aggregate'
    fmatch = re.match(freg, fname)

    if fmatch is None:
        print("Bad filename format.")
        sys.exit(1)
    elif fmatch.group('dist') is not None:
        resources = [int(b) for b in fmatch.group('dist').split('_')]
    elif fmatch.group('hom_bw') is not None:
        resources = [int(fmatch.group('hom_bw'))] * int(fmatch.group('hom_num'))

    data = pd.read_csv(infile, index_col=0)
    dl_times = {}
    treg = r'(?:(?P<m>\d+)m)?(?P<s>\d+)s'
    for peer, row in data.iterrows():
        ptime = re.match(treg, row['dl_time'])
        if ptime is not None:
            minutes = int(ptime.group('m')) if ptime.group('m') is not None else 0
            dl_times[peer] = minutes * 60 + int(ptime.group('s'))

    ratios = {}
    for peer, time in dl_times.items():
        ratios[peer] = (resources[peer] / sum(resources)) / (time / sum(dl_times.values()))

    return ratios, data
    #results = pd.read_csv(fname, index_col=False)
    #results = results.set_index('peer')
    #return results

if __name__ == '__main__':
    #main(sys.argv[1:])
    ratios, data = main(sys.argv[1:])
