module PFB

using REPL.TerminalMenus

function targets(dir::String, dirs::Bool=true)
    options = readdir(dir, join=true)
    if dirs
        options = filter(isdir, options)
    else
        options = filter(options) do opt
            _, ext = splitext(opt)
            ext == ".csv"
        end
    end
    menu = MultiSelectMenu(options)
    return options, request("Select targets:", menu)
end

include("CovPlots.jl")
include("Execs.jl")

end # module
