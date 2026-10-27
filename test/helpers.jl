# Shared test helpers. The test cases are GenX's own example systems, copied out of the
# installed GenX package so each test can change settings without touching the originals.

const EXAMPLES = joinpath(pkgdir(GenX), "example_systems")

"""
    example_case(name; settings...)

Copy GenX example `name` to a temporary folder and return its path. Time domain reduction is
switched off, since the clustered data is not shipped with GenX; `settings` override further
top-level keys of `genx_settings.yml`.
"""
function example_case(name::AbstractString; settings...)
    case = joinpath(mktempdir(), name)
    cp(joinpath(EXAMPLES, name), case)
    chmod(case, 0o755; recursive = true)  # installed package files are read-only
    set_setting!(case, "genx_settings.yml", "TimeDomainReduction", 0)
    for (key, value) in settings
        set_setting!(case, "genx_settings.yml", string(key), value)
    end
    return case
end

"Set top-level `key` of settings file `file` in `case`, adding it if missing."
function set_setting!(case::AbstractString, file::AbstractString, key::AbstractString, value)
    path = joinpath(case, "settings", file)
    lines = readlines(path)
    i = findfirst(l -> startswith(l, "$key:"), lines)
    if i === nothing
        push!(lines, "$key: $value")
    else
        lines[i] = "$key: $value"
    end
    write(path, join(lines, "\n") * "\n")
    return nothing
end

"""
    set_resource_values!(case, file, row, values...)

Set columns of row `row` in resource file `file` of `case`, given as `column => value` pairs. A
missing column is added, with `"None"` (for text) or zero in the other rows.
"""
function set_resource_values!(case::AbstractString, file::AbstractString, row::Integer,
        values::Pair...)
    path = joinpath(case, "resources", file)
    df = CSV.read(path, DataFrame)
    for (column, value) in values
        if !hasproperty(df, column)
            df[!, column] = fill(value isa AbstractString ? "None" : zero(value), nrow(df))
        end
        df[row, column] = value
    end
    CSV.write(path, df)
    return nothing
end

"Convert a case into a fresh temporary folder, hiding GenX's console output; return the folder."
function convert_case(case::AbstractString)
    out = joinpath(mktempdir(), "macro")
    redirect_stdout(devnull) do
        convert_genx_case(case, out)
    end
    return out
end

"""
    load_in_macro(macro_case)

Load a converted case in Macro without solving it, so every asset is built from its JSON: a
wrong key, commodity or node id fails here even when the mapping tests pass.
"""
load_in_macro(macro_case::AbstractString) =
    redirect_stdout(devnull) do
        with_logger(NullLogger()) do
            MacroEnergy.load_case(macro_case)
        end
    end

"Load a GenX case's inputs quietly, as the converter does."
load_quietly(case, inputs_path = case) =
    redirect_stdout(devnull) do
        load_genx_case(case, inputs_path)
    end

read_json(path::AbstractString) = JSON3.read(read(path, String))
read_json(dir::AbstractString, relative::AbstractString) = read_json(joinpath(dir, relative))
instances(dir, relative, key) = read_json(dir, relative)[key][:instance_data]
node_groups(dir, relative = "system/nodes.json") = read_json(dir, relative)[:nodes]
read_csv(path) = CSV.read(path, DataFrame)
