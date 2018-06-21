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
    parsed = re.match(freg, fname)

    if parsed is None:
        print("Bad filename format.")
        sys.exit(1)
    elif parsed.group('dist') is not None:
        dist = [int(b) for b in parsed.group('dist').split('_')]
    elif parsed.group('hom_bw') is not None:
        dist = [int(parsed.group('hom_bw'))] * int(parsed.group('hom_num'))

    data = pd.read_csv(infile, index_col=0)
    dl_times = {}
    treg = r'(?:(?P<m>\d+)m)?(?P<s>\d+)s'
    for peer, row in data.iterrows():
        ptime = re.match(treg, row['dl_time'])
        if ptime is not None:
            seconds = int(ptime.group('m')) * 60 + int(ptime.group('s'))
            dl_times[peer] = seconds

    return dl_times, data
    #results = pd.read_csv(fname, index_col=False)
    #results = results.set_index('peer')
    #return results

if __name__ == '__main__':
    #main(sys.argv[1:])
    dl_times, data = main(sys.argv[1:])
