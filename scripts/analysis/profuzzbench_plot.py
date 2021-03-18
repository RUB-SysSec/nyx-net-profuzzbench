#!/usr/bin/env python3

import argparse
import matplotlib.pyplot as plt
import pandas as pd
import statistics

CUT = True
LOG = False


def main(csv_file, put, runs, cut_off, step, out_file):
    #Read the results
    df = pd.read_csv(csv_file)

    #Calculate the mean of code coverage
    #Store in a list first for efficiency
    mean_list = []

    fuzzers = df.fuzzer.unique()
    for subject in [put]:
        # for fuzzer in ['aflnet', 'aflnwe']:
        for fuzzer in fuzzers:
            for cov_type in ['b_abs', 'b_per', 'l_abs', 'l_per']:
                #get subject & fuzzer & cov_type-specific dataframe
                df1 = df[(df['subject'] == subject) & (df['fuzzer'] == fuzzer)
                         & (df['cov_type'] == cov_type)]

                mean_list.append((subject, fuzzer, cov_type, 0, 0.0))
                agg_f = statistics.median if '_abs' in cov_type else statistics.mean
                for time in range(1, cut_off + 1, step):
                    cov = []
                    for run in range(1, runs + 1, 1):
                        #get run-specific data frame
                        df2 = df1[df1['run'] == run]

                        if CUT:
                            #get the starting time for this run
                            start = df2.iloc[0, 0]

                            #get all rows given a cutoff time
                            df2 = df2[df2['time'] <= start + time * 60]

                        #update total coverage and #runs
                        cov.append(df2.iloc[-1, 5])

                    #add a new row
                    mean_list.append(
                        (subject, fuzzer, cov_type, time, agg_f(cov)))

    #Convert the list to a dataframe
    mean_df = pd.DataFrame(
        mean_list, columns=['subject', 'fuzzer', 'cov_type', 'time', 'cov'])

    fig, axes = plt.subplots(2, 2, figsize=(20, 10))
    fig.suptitle("Code coverage analysis")

    for key, grp in mean_df.groupby(['fuzzer', 'cov_type']):
        if key[1] == 'b_abs':
            axes[0, 0].plot(grp['time'], grp['cov'], label=key[0])
            #axes[0, 0].set_title('Edge coverage over time (#edges)')
            axes[0, 0].set_xlabel('Time (in min)')
            axes[0, 0].set_ylabel('#edges')
            if LOG:
                axes[0, 0].set_yscale('log')
        if key[1] == 'b_per':
            axes[1, 0].plot(grp['time'], grp['cov'], label=key[0])
            #axes[1, 0].set_title('Edge coverage over time (%)')
            axes[1, 0].set_ylim([0, 100])
            axes[1, 0].set_xlabel('Time (in min)')
            axes[1, 0].set_ylabel('Edge coverage (%)')
        if key[1] == 'l_abs':
            axes[0, 1].plot(grp['time'], grp['cov'], label=key[0])
            #axes[0, 1].set_title('Line coverage over time (#lines)')
            axes[0, 1].set_xlabel('Time (in min)')
            axes[0, 1].set_ylabel('#lines')
            if LOG:
                axes[0, 1].set_yscale('log')
        if key[1] == 'l_per':
            axes[1, 1].plot(grp['time'], grp['cov'], label=key[0])
            #axes[1, 1].set_title('Line coverage over time (%)')
            axes[1, 1].set_ylim([0, 100])
            axes[1, 1].set_xlabel('Time (in min)')
            axes[1, 1].set_ylabel('Line coverage (%)')

    for i, ax in enumerate(fig.axes):
        # ax.legend(('AFLNet', 'AFLNwe'), loc='upper left')
        # ax.legend(fuzzers, loc='upper left')
        ax.legend(loc='upper left')
        ax.grid()

    #Save to file
    plt.savefig(out_file)


# Parse the input arguments
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-i',
                        '--csv_file',
                        type=str,
                        required=True,
                        help="Full path to results.csv")
    parser.add_argument('-p',
                        '--put',
                        type=str,
                        required=True,
                        help="Name of the subject program")
    parser.add_argument('-r',
                        '--runs',
                        type=int,
                        required=True,
                        help="Number of runs in the experiment")
    parser.add_argument('-c',
                        '--cut_off',
                        type=int,
                        required=True,
                        help="Cut-off time in minutes")
    parser.add_argument('-s',
                        '--step',
                        type=int,
                        required=True,
                        help="Time step in minutes")
    parser.add_argument('-o',
                        '--out_file',
                        type=str,
                        required=True,
                        help="Output file")
    args = parser.parse_args()
    main(args.csv_file, args.put, args.runs, args.cut_off, args.step,
         args.out_file)
