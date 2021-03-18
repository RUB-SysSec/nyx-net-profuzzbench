module Execs

using ..PFB: targets

using Printf
using Statistics

using CSV
using DataFrames

# Load runs from execs.csv
function load(path)
    df = DataFrame(CSV.File(path))
    disallowmissing!(df)
    return df
end

# Agggregate execs accross runs with mean
aggexecs(df) = combine(groupby(df, [:subject, :fuzzer]),
                       :execs => mean => :execs_mean,
                       :execs => std => :execs_std)

function multiple(dir::String)
    options, choices = targets(dir, false)
    length(choices) > 0 || return

    df = DataFrame()
    for choice in choices
        target = options[choice]
        append!(df, load(target))
    end

    return df
end

function mktable(dir::String)
    df = multiple(dir)
    df == nothing && return
    agg = aggexecs(df)
    table = DataFrame()
    for gd in groupby(agg, :subject)
        row = Dict{String, Any}("subject" => gd.subject[1])
        mx = -Inf
        mx_f = nothing
        for fuzzer in unique(gd.fuzzer)
            x = @view gd[gd.fuzzer .== fuzzer, :]
            m = x[1, :execs_mean]
            if m >= mx
                mx = m
                mx_f = fuzzer
            end
        end
        for fuzzer in unique(gd.fuzzer)
            x = @view gd[gd.fuzzer .== fuzzer, :]
            m = x[1, :execs_mean]
            s = x[1, :execs_std]
            if fuzzer == mx_f
                row[fuzzer] = @sprintf("\$\\mathbf{%.1f} \\pm %.1f\$", m, s)
            else
                row[fuzzer] = @sprintf("\$%.1f \\pm %.1f\$", m, s)
            end
        end
        if !("aflpp" in keys(row))
            row["aflpp"] = "-"
        end
        push!(table, row, cols=:union)
    end
    select!(table, "subject" => "target", "aflnet", "aflnet-no-state", "aflnwe", "aflpp",
           "nyx", "nyx-balanced", "nyx-aggressive")
    sort!(table, :target)
    for row in eachrow(table)
        println(join(Tuple(row), " & "), " \\\\")
    end
    return table
end

end # module
