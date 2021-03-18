# Analysis script in Julia

This folder contains a collection of functions to analyze coverage data (and
more) and produce plots and tables for the paper.

# Simple example

Start [Julia](https://julialang.org/) with 4 threads and the package path:

```bash
julia -t 4 --project=PFB.jl
```

Import the package and analyze coverage data for multiple runs from multiple
fuzzers and targets with:

```julia
use PFB
PFB.CovPlots.multiple("/path/to/runs/outdir", UInt(60))
```

The above code will ask you to select CSV files from the given directory. Each
CSV file contains coverage data from multiple runs and multiple fuzzers _on the
same target_. The correct format can be obtained with
`scripts/nyx-eval/convert_coverage.sh`.

The second parameter sets the timeout that was used for the fuzzing runs.

`PFB.CovPlots.multiple` will make a plot for each target it finds and output a
table with Mann-Whitney-U tests result across all combination of fuzzers for
the final coverage. The plots will be stored as PDF in the same directory as
the CSV files.

Optional keyword parameters to `PFB.CovPlots.multiple`:

- `seldirs`: whether multiple selection works on directories instead of files; each directory should contain a `results.csv` file [default: false]
- `latex`: wheter to print statistical difference as LaTeX table or plain text [default: false]
- `layout`: `:pfb` makes plots with branch and line coverage; `:branches` plots only branch coverage [default: `:pfb`]
- `signconf`: confidence value for statistical test [default: 0.05]
- `nyxsumm`: make table Nyx-Net centric [default: true]

# Other functions

- `PFB.CovPlots.getruns(csvpath::String, timeout::UInt)::TargetData`: loads a single CSV file
- `PFB.CovPlots.makeplot(data::TargetData, layout::Symbol=:pfb)`: returns a plot for the loaded CSV data (i.e. from `getruns`)
- `PFB.CovPlots.significance(data::TargetData, conf::Real)::DataFrame`: returns a table with Mann-Whitney U test results
- `PFB.CovPlots.loadall(dir::String)::DataFrame`: loads data for the paper evaluation (used by following functions)
- `PFB.CovPlots.mktable(df::DataFrame)`: outputs the table with coverage data for the paper
- `PFB.CovPlots.timetocov(df::DataFrame)::DataFrame`: returns time to reach same coverage as baseline fuzzer
- `PFB.CovPlots.mkplotpaper`: makes the coverage plot for the paper
- `PFB.Execs.multiple(dir::String)::DataFrame`: processes and loads CSV files that are output of `scripts/nyx-eval/gather_execs.sh`
- `PFB.Execs.mktable(dir::String)`: loads data with the function above and prints a table for the paper
