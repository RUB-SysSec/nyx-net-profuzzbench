module CovPlots

using ..PFB: targets

using Base.Threads
using Printf, Statistics

using CSV
using DataFrames
using HypothesisTests
using StatsPlots


function __init__()
    theme(:ggplot2)
    gr(size=(600, 400) .* 1.2)
end

const UNITKEYS = [:time, :fuzzer, :run]
const VALUECOLS = [:l_per, :l_abs, :b_per, :b_abs]

PALETTE = palette(:seaborn_colorblind)
COLORMAP = Dict("aflnet" => PALETTE.colors.colors[1],
                "aflnet-no-state" => PALETTE.colors.colors[2],
                "aflnwe" => PALETTE.colors.colors[3],
                "aflpp" => PALETTE.colors.colors[8],
                "nyx" => PALETTE.colors.colors[5],
                "nyx-newspec" => PALETTE.colors.colors[6],
                "nyx-balanced" => PALETTE.colors.colors[7],
                "nyx-aggressive" => PALETTE.colors.colors[4])

struct TargetData
    df::DataFrame
    agg::DataFrame
    runslastcov::DataFrame
    target::String
end

"Parse CSV with runs for different fuzzers on a single target"
function getruns(csvpath::String, cutoff::UInt)::Union{TargetData, Nothing}
    df = DataFrame(CSV.File(csvpath))
    println("$csvpath: retrieved $(nrow(df)) rows")
    nrow(df) > 0 || return

    target = unique(df.subject)[1]

    # transform time to relative to the first per run
    udf = unstack(df, UNITKEYS, :cov_type, :cov, allowduplicates=true)
    disallowmissing!(udf)
    fuzzerruns = groupby(udf, [:fuzzer, :run])
    # time from seconds to minutes since first in fuzzer run
    transform!(fuzzerruns, :time => (t -> (t .- minimum(t)) .÷ 60) => :time)

    # fill missing values at all times (i.e. 0 to cutoff)
    filled = DataFrame()
    for gd in fuzzerruns
        fullrun = DataFrame(time=0:cutoff, fuzzer=gd[1, :fuzzer], run=gd[1, :run])
        # pick highest values for the same fuzzer / run / time
        gd = combine(groupby(gd, UNITKEYS), VALUECOLS .=> maximum .=> VALUECOLS)
        # join with full times
        append!(filled, leftjoin(fullrun, gd, on=UNITKEYS))
    end
    sort!(filled, [:fuzzer, :run, :time])
    # forward-fill values
    for col in VALUECOLS
        filled[!, col] = accumulate((n0,n1) -> ismissing(n1) ? n0 : n1,
                                    filled[:, col],
                                    init=zero(eltype(filled[:, col])))
    end
    disallowmissing!(filled)
    TargetData(filled, aggruns(filled), getlatestcov(filled), target)
end

"Aggregate across runs"
aggruns(data::TargetData)::DataFrame = aggruns(data.df)
aggruns(df::DataFrame)::DataFrame =
    combine(groupby(df, [:fuzzer, :time]),
            VALUECOLS .=> repeat([mean, median], 2) .=> VALUECOLS)

"Get latest coverage (`b_abs`) for each run of each fuzzer"
getlatestcov(data::TargetData) = getlatestcov(data.df)
getlatestcov(df::DataFrame) =
    combine(groupby(df, [:fuzzer, :run]), :b_abs => last => :cov)

"Create coverage plot"
function makeplot(data::TargetData, layout::Symbol=:pfb)::Plots.Plot
    fuzzers = unique(data.agg.fuzzer)
    cs = [COLORMAP[f] for f in fuzzers]
    timeformatter(x) = @sprintf("%2.0fh", x ÷ 60)
    if layout == :branches
        p1 = @df data.agg plot(:time, :b_abs, group=:fuzzer, title=data.target, color_palette=cs,
                               legend=:bottomright, linewidth=2, yguide="branches",
                               xformatter=timeformatter)
        get(f) = @view data.runslastcov[data.runslastcov.fuzzer .== f, :]
        tickrotation = 20
        p2 = @df get(fuzzers[1]) boxplot(:fuzzer, :cov, xrotation=tickrotation, xtickfontsize=6,
                                         label=nothing, color=COLORMAP[fuzzers[1]])
        for f in fuzzers[2:end]
            @df get(f) boxplot!(:fuzzer, :cov, xrotation=tickrotation,
                                label=nothing, color=COLORMAP[f])
        end
        @df data.runslastcov dotplot!(:fuzzer, :cov, marker=(:black, stroke(0)), label=nothing)
        return plot(p1, p2)
    elseif layout == :pfb
        yticks = [0:20:100;]
        percformatter = y -> @sprintf("%2.1f%%", y)
        p1 = @df data.agg plot(:time, :b_abs, group=:fuzzer, title=data.target, color_palette=cs,
                               legend=:bottomright, yguide="branches", xformatter=timeformatter)
        p2 = @df data.agg plot(:time, :b_per, group=:fuzzer, title=data.target, color_palette=cs,
                               legend=:best, yformatter=percformatter, xformatter=timeformatter)
        p3 = @df data.agg plot(:time, :l_abs, group=:fuzzer, title=data.target, color_palette=cs,
                               legend=:bottomright, yguide="lines", xformatter=timeformatter)
        p4 = @df data.agg plot(:time, :l_per, group=:fuzzer, title=data.target, color_palette=cs,
                               legend=:best, yformatter=percformatter, xformatter=timeformatter)
        return plot(p1, p2, p3, p4, layout=(2, 2))
    else
        error("Unexpected layout $layout")
    end
end

"Process multiple targets selectable from a menu, given tha parent directory"
function multiple(dir::String, cutoff::UInt;
        layout=:pfb, seldirs=false, latex=false, nyxsumm=true, signconf=0.05)
    options, choices = targets(dir, seldirs)
    length(choices) > 0 || return

    # iterators are not thread safe
    selected = options[collect(choices)]

    outpath_suffix = layout == :branches ? "br" : "all"

    # collect aggregated runs for selected targets
    dfs = Dict()
    sizehint!(dfs, length(selected))
    @threads for targetdir in selected
        if seldirs
            csvpath = joinpath(targetdir, "results.csv")
            outpath = joinpath(dirname(csvpath), "coverage_$outpath_suffix.pdf")
        else
            csvpath = targetdir
            base, _ = splitext(targetdir)
            outpath = base*"_$outpath_suffix.pdf"
        end
        runs = getruns(csvpath, cutoff)
        if runs != nothing
            dfs[csvpath] = (runs, outpath, significance(runs, signconf))
        end
    end

    # the plotting library is not thread safe
    summ = DataFrame()
    for (csvpath, (runs, outpath, sign)) in dfs
        if layout != nothing
            p = makeplot(runs, layout)
            savefig(p, outpath)
        end
        if nyxsumm
            append!(summ, sign[startswith.(sign.vs, "nyx"), :])
        else
            append!(summ, sign)
        end
    end
    sort!(summ, :target)
    io = IOBuffer()
    show(io, MIME("text/"*(latex ? "latex" : "plain")), summ;
         eltypes=false, show_row_number=false, summary=false)
    println(String(take!(io)))
    return summ
end

"Compute and return pairwise Mann-Whitney-U test on final median branch coverage"
function significance(data::TargetData, conf::Real)::DataFrame
    fuzzers = ["aflnet", "aflnet-no-state", "aflnwe", "aflpp",
               "nyx", "nyx-newspec", "nyx-balanced", "nyx-aggressive"]
    tab = DataFrame("target" => String[],
                    "vs" => String[],
                    "aflnet" => Union{String, Missing}[],
                    "aflnet-no-state" => Union{String, Missing}[],
                    "aflnwe" => Union{String, Missing}[],
                    "aflpp" => Union{String, Missing}[],
                    "nyx" => Union{String, Missing}[],
                    "nyx-newspec" => Union{String, Missing}[],
                    "nyx-balanced" => Union{String, Missing}[],
                    "nyx-aggressive" => Union{String, Missing}[])
    for fuzz_i in fuzzers
        d = Dict{String, Union{String, Missing}}("vs" => fuzz_i, "target" => data.target)
        for f in fuzzers
            d[f] = missing
        end
        for fuzz_j in fuzzers
            (fuzz_i == fuzz_j) && continue
            runs_i = @view data.runslastcov[data.runslastcov.fuzzer .== fuzz_i, :cov]
            runs_j = @view data.runslastcov[data.runslastcov.fuzzer .== fuzz_j, :cov]
            (length(runs_i) == 0 || length(runs_j) == 0) && continue
            test = MannWhitneyUTest(runs_i, runs_j)
            ρ = pvalue(test)
            d[fuzz_j] = @sprintf("%8.1f %c", test.median, ρ < conf ? "✓" : "x")
        end
        push!(tab, d)
    end
    return tab
end

function loadall(dir::String; fixaflnwe=false)
    options, choices = targets(dir, false)
    length(choices) > 0 || return
    selected = options[collect(choices)]
    df = DataFrame()
    for targetfile in selected
        runs = getruns(targetfile, UInt(1440))
        if runs != nothing
            insertcols!(runs.df, 1, :target => runs.target)
            append!(df, runs.df)
        end
    end
    select!(df, :target, :fuzzer, :run, :time, :b_abs => :cov)
    !fixaflnwe && return df
    df_cp = DataFrame()
    old_val = 0
    for r in eachrow(df)
        if r.fuzzer == "aflnwe" && r.target == "forked-daapd"
            if r.cov < old_val
                r.cov = old_val
            else
                old_val = r.cov
            end
        end
        push!(df_cp, r)
    end
    return df_cp
end

function mktable(df::DataFrame; noseeds=false)
    if noseeds
        baseline_fuzz = "aflnet-no-state"
        other_fuzzs = ["nyx-aggressive"]
        table = DataFrame("target"=>[],
                          baseline_fuzz=>[],
                          # "nyx-aggressive Δ"=>[],
                          "nyx-aggressive %"=>[])
    else
        baseline_fuzz = "aflnet"
        other_fuzzs = ["aflnet-no-state", "aflnwe", "aflpp", "nyx", "nyx-balanced", "nyx-aggressive"]
        table = DataFrame("target"=>[],
                          baseline_fuzz=>[],
                          # "aflnet-no-state Δ"=>[],
                          "aflnet-no-state %"=>[],
                          # "aflnwe Δ"=>[],
                          "aflnwe %"=>[],
                          # "aflpp Δ"=>[],
                          "aflpp %"=>[],
                          # "nyx Δ"=>[],
                          "nyx %"=>[],
                          # "nyx-balanced Δ"=>[],
                          "nyx-balanced %"=>[],
                          # "nyx-aggressive Δ"=>[],
                          "nyx-aggressive %"=>[])
    end
    for gd in groupby(df, :target)
        baseline = @view gd[gd.fuzzer .== baseline_fuzz, :]
        baseline_last = combine(groupby(baseline, :run), :cov => last => :last_cov)
        row = Dict()
        row["target"] = gd.target[1]
        baseline_med = median(baseline_last.last_cov)
        @show row[baseline_fuzz] = "\$$baseline_med\$"
        for fuzz in other_fuzzs
            fuzz == baseline_fuzz && continue
            if !any(gd.fuzzer .== fuzz)
                # row["$fuzz Δ"] = "n/a"
                row["$fuzz %"] = "n/a"
                continue
            end
            fuzz_data = @view gd[gd.fuzzer .== fuzz, :]
            fuzz_last = combine(groupby(fuzz_data, :run), :cov => last => :last_cov)
            test = MannWhitneyUTest(fuzz_last.last_cov, baseline_last.last_cov)
            perc = (median(fuzz_last.last_cov) - baseline_med) / (baseline_med / 100)
            if pvalue(test) < 0.05
                # row["$fuzz Δ"] = @sprintf("\$\\mathbf{%+.1f}\$", test.median)
                row["$fuzz %"] = @sprintf("\$\\mathbf{%+.1f\\%%}\$", perc)
            else
                # row["$fuzz Δ"] = @sprintf("\$%+.1f\$", test.median)
                row["$fuzz %"] = @sprintf("\$%+.1f\\%%\$", perc)
            end
        end
        push!(table, row, cols=:subset)
    end
    sort!(table, :target)
    for row in eachrow(table)
        println(join(Tuple(row), " & "), "\\\\")
    end
    return table
end

function timetocov(df::DataFrame)
    baseline_fuzz = "aflnet"
    # other_fuzzs = ["aflnet-no-state", "aflnwe", "aflpp", "nyx", "nyx-balanced", "nyx-aggressive"]
    other_fuzzs = ["nyx", "nyx-balanced", "nyx-aggressive"]
    table = DataFrame("target"=>[], "nyx"=>[], "nyx-balanced"=>[], "nyx-aggressive"=>[])
    for gd in groupby(df, :target)
        baseline = @view gd[gd.fuzzer .== baseline_fuzz, :]
        baseline_meds = combine(groupby(baseline, :time), :cov => median => :med_cov)
        baseline_med = last(baseline_meds.med_cov)
        baseline_med_time = first(baseline_meds[baseline_meds.med_cov .>= baseline_med, :time])
        row = Dict{String, Any}("target" => gd.target[1])
        for fuzz in other_fuzzs
            # for each run, find time to baseline median last cov
            fuzz_data = @view gd[gd.fuzzer .== fuzz, :]
            fuzz_meds = combine(groupby(fuzz_data, :time), :cov => median => :med_cov)
            ttcov = fuzz_meds[fuzz_meds.med_cov .>= baseline_med, :time]
            if length(ttcov) > 0
                ttcov = ttcov[1]
                # perc = (ttcov - baseline_med_time) / (baseline_med_time / 100)
                # perc = (baseline_med_time - ttcov) / (baseline_med_time / 100)
                # row[fuzz] = @sprintf("%.2f%%", perc)
                row[fuzz] = "$ttcov $baseline_med_time"
            else
                row[fuzz] = "-"
            end
        end
        push!(table, row, cols=:union)
    end
    sort!(table, "target")
    return table
end

getfuzzname(f) =
    if f == "nyx"
        "nyxnet-none"
    elseif f == "nyx-aggressive"
        "nyxnet-aggressive"
    elseif f == "nyx-balanced"
        "nyxnet-balanced"
    else
        f
    end

LINE_TYPES = Dict(
                  "aflnet" => :dot,
                  "nyx" => :dash,
                  "nyx-balanced" => :dashdot,
                  "nyx-aggressive" => :solid,
                  "aflnet-no-state" => :dash,
                  "aflnwe" => :dot,
                  "aflpp" => :dashdot,
                 )

function mkplotpaper(df::DataFrame, extra_target::String, first_target::String="kamailio";
        alltargets=false, allfuzz=false, noseeds=false, fixaflnwe=false)
    @assert extra_target != first_target
    selected_fuzzers = allfuzz ?
        ["aflnet", "aflnet-no-state", "aflnwe", "aflpp", "nyx", "nyx-balanced", "nyx-aggressive"] :
        ["aflnet", "nyx", "nyx-balanced", "nyx-aggressive"]
    ps = []
    timeformatter(x) = @sprintf("%2.0fh", x ÷ 60)
    sort!(df, :target)
    df[!, :time] = df.time .+ 1
    agg = combine(groupby(df, [:target, :fuzzer, :time]), :cov => median => :med_cov)
    if fixaflnwe
        agg_cp = DataFrame()
        old_val = 0
        for r in eachrow(agg)
            if r.fuzzer == "aflnwe" && r.target == "forked-daapd"
                if r.med_cov < old_val
                    r.med_cov = old_val
                else
                    old_val = r.med_cov
                end
            end
            push!(agg_cp, r)
        end
        agg = agg_cp
    end
    extra_plot = nothing
    extra_plot_2 = nothing
    first_p = nothing
    pic_size = (400, 400) .* 0.8
    idx_multiplot = 1
    for gd in groupby(agg, :target)
        target = gd.target[1]
        gd = filter(:fuzzer => f -> f in selected_fuzzers, gd; view=false)
        fuzzers = unique(gd.fuzzer)
        cs = [COLORMAP[f] for f in fuzzers]
        label_fuzzers = permutedims([getfuzzname(f) for f in fuzzers])
        line_types = permutedims([LINE_TYPES[f] for f in fuzzers])
        if target == extra_target
            mkextra(leg) = @df gd plot(:time, :med_cov, group=:fuzzer, title=target, color_palette=cs,
                                    line=line_types,
                                    legend=leg ? :bottomright : false,
                                    label=label_fuzzers,
                                    yguide="Branches",
                                    xformatter=timeformatter,
                                    xticks=0:240:1440,
                                    linewidth=alltargets ? 2 : 1,
                                    size=pic_size,
                                   )
            extra_plot = mkextra(true)
            extra_plot_2 = mkextra(false)
        else
            yguide = target == first_target ? "Branches" : ""
            legend = (!alltargets && idx_multiplot == 12) ? :bottomright : false
            p = @df gd plot(:time, :med_cov, group=:fuzzer, title=target, color_palette=cs,
                            line=line_types,
                            legend=legend,
                            label=label_fuzzers,
                            yguide=yguide,
                            xticks=0:240:1440,
                            xformatter=timeformatter,
                            linewidth=2,
                           )
            if target == first_target
                first_p = p
            else
                push!(ps, p)
            end
            idx_multiplot += 1
        end
    end
    pic_size_scaled = pic_size .* 0.8
    if noseeds
        grid_l = [2, 6]
        ps = [first_p ps... extra_plot]
    else
        grid_l = alltargets ? [2, 7] : [2, 6]
        ps = alltargets ? [extra_plot first_p ps... extra_plot_2] : [first_p ps...]
    end
    ps = plot(
              ps...,
              layout=Tuple(grid_l),
              size=pic_size_scaled.*reverse(grid_l),
             )
    return ps, extra_plot
end

end # module
