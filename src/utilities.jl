
####### UTILS #######

"""
    Target(macro_case, stage)

Where converted files go: the Macro case folder, and the stage number (as a string) of a
multi-stage case, or `nothing` for a single-stage one. Files that differ between stages carry
the stage number in their name or folder.
"""
struct Target
    macro_case::String
    stage::Union{Nothing, String}
end

is_multistage(t::Target) = t.stage !== nothing

"Path of an asset file, relative to the Macro case."
asset_file(t::Target, name::AbstractString) =
    is_multistage(t) ? "assets/assets_$(t.stage)/$name.json" : "assets/$name.json"

"Path of a system file, relative to the Macro case; multi-stage files carry the stage number."
system_file(t::Target, base::AbstractString, ext::AbstractString) =
    is_multistage(t) ? "system/$(base)_$(t.stage).$ext" : "system/$base.$ext"

"Absolute path of a file given relative to the Macro case."
case_path(t::Target, relative::AbstractString) = joinpath(t.macro_case, relative)

"""
    load_genx_case(genx_case_path, inputs_path = genx_case_path)

Load a GenX case's settings, and the inputs in `inputs_path` (a stage folder of a multi-stage
case). Parameter scaling is switched off so every value is in MW, MWh, \$ and tonnes.
"""
function load_genx_case(genx_case_path::AbstractString, inputs_path::AbstractString = genx_case_path)
    setup = GenX.configure_settings(
        GenX.get_settings_path(genx_case_path, "genx_settings.yml"),
        GenX.get_settings_path(genx_case_path, "output_settings.yml"))
    setup["ParameterScale"] = 0
    inputs = GenX.load_inputs(setup, inputs_path)
    return setup, inputs
end

"""
    check_supported(inputs, setup; warn = true)

Stop on GenX features the converter cannot represent in Macro, so a conversion fails before
writing anything. With `warn`, also warn about what the Macro case leaves out or represents
differently (see [`unsupported_warnings`](@ref)), so a converted case is never silently
different.
"""
function check_supported(inputs::Dict, setup::Dict; warn::Bool = true)
    # Macro has only a mass cap on a CO2 node (CO2CapConstraint); GenX's CO2Cap 2 and 3 are
    # rate-based caps with no Macro equivalent.
    if !(setup["CO2Cap"] in (0, 1))
        error("CO2Cap = $(setup["CO2Cap"]) is a rate-based CO2 cap, which Macro does not " *
              "support. Only mass-based caps (CO2Cap = 1) or no cap (CO2Cap = 0) can be converted.")
    end
    # With time domain reduction, Macro derives the subperiod weights from the period map, which
    # gives GenX's weights. Without one, Macro weights every subperiod equally.
    if setup["TimeDomainReduction"] != 1 && !allequal(inputs["Weights"])
        error("The subperiods in Demand_data.csv have different Sub_Weights, but without time " *
              "domain reduction there is no period map to carry them to Macro, which would " *
              "weight every subperiod equally.")
    end
    if inputs["L"] > 0 && setup["Trans_Loss_Segments"] >= 2
        error("Trans_Loss_Segments = $(setup["Trans_Loss_Segments"]) models quadratic line " *
              "losses, which Macro does not support; Macro takes a fixed loss percentage " *
              "(Trans_Loss_Segments = 1) or lossless lines (0).")
    end
    gen = inputs["RESOURCES"]
    multi_fuel = get(inputs, "MULTI_FUELS", Int[])
    if !isempty(multi_fuel)
        error("Multi-fuel resources cannot be converted: $(resource_names(inputs, multi_fuel)).")
    end
    # A thermal plant needs a fuel with a Macro commodity and a single CO2 node to emit to;
    # thermal_fuel and co2_sink stop otherwise.
    for y in inputs["THERM_ALL"]
        thermal_fuel(gen[y])
        co2_sink(inputs, gen[y].zone)
    end
    # GenX gives a biomass plant with CO2 capture negative emissions. In Macro that would be a
    # negative flow on the plant's CO2 edge, which edges do not allow, so the plant could not run.
    beccs = filter(y -> GenX.biomass(gen[y]) + GenX.co2_capture_fraction(gen[y]) > 1,
        ccs_thermal(inputs))
    if !isempty(beccs)
        error("Plants with negative CO2 emissions (Biomass plus CO2_Capture_Fraction above 1) " *
              "cannot be converted: $(resource_names(inputs, beccs)). A Macro CO2 edge cannot " *
              "carry a negative flow.")
    end

    if warn
        for message in unsupported_warnings(inputs, setup)
            @warn message
        end
    end
    return nothing
end

"""
    unsupported_warnings(inputs, setup)

Messages about the GenX settings, resources and features that the Macro case leaves out or
represents differently.
"""
function unsupported_warnings(inputs::Dict, setup::Dict)
    gen = inputs["RESOURCES"]
    messages = String[]

    policies = filter(k -> get(setup, k, 0) != 0, ["MinCapReq", "MaxCapReq",
        "EnergyShareRequirement", "CapacityReserveMargin", "OperationalReserves",
        "HydrogenMinimumProduction", "HourlyMatchingRequirement", "DC_OPF",
        "DiscreteInvestments"])
    isempty(policies) || push!(messages, "These active GenX settings are not converted, so " *
                                         "the Macro case leaves them out: $(join(policies, ", ")).")
    resources = filter(k -> !isempty(get(inputs, k, Int[])),
        ["VRE_STOR", "FLEX", "ELECTROLYZER", "ALLAM_CYCLE_LOX"])
    isempty(resources) || push!(messages, "These GenX resource types are not converted, so " *
                                          "the Macro case leaves them out: $(join(resources, ", ")).")

    # Only thermal plants get a fuel edge, so a converted resource of any other type loses its
    # fuel use, and with it its CO2 emissions and capture.
    unconverted = union(Int[], (inputs[k] for k in resources)...)
    burns_fuel = filter(y -> GenX.heat_rate_mmbtu_per_mwh(gen[y]) > 0,
        setdiff(get(inputs, "HAS_FUEL", Int[]), inputs["THERM_ALL"], unconverted))
    isempty(burns_fuel) || push!(messages, "Only thermal plants burn fuel in the Macro case, " *
                                           "so these resources lose their fuel use, CO2 " *
                                           "emissions and CO2 capture: " *
                                           "$(resource_names(inputs, burns_fuel)).")

    features = String[]
    isempty(get(inputs, "THERM_COMMIT_PWFU", Int[])) ||
        push!(features, "piecewise fuel usage (plants use Heat_Rate_MMBTU_per_MWh instead)")
    any(y -> get(gen[y], :maint, 0) == 1, inputs["THERM_ALL"]) && push!(features, "maintenance")
    isempty(get(inputs, "RETROFIT_OPTIONS", Int[])) ||
        push!(features, "retrofits (retrofit options become independent new plants)")
    isempty(features) || push!(messages, "These GenX thermal features are not converted: " *
                                         "$(join(features, ", ")).")

    # Macro applies the steady-state capture rate to start-up fuel too.
    startup = filter(y -> GenX.co2_capture_fraction_startup(gen[y]) !=
                          GenX.co2_capture_fraction(gen[y]), ccs_thermal(inputs))
    isempty(startup) || push!(messages, "CO2_Capture_Fraction_Startup differs from " *
                                        "CO2_Capture_Fraction, but Macro applies one capture " *
                                        "rate, so start-up emissions differ from GenX for: " *
                                        "$(resource_names(inputs, startup)).")
    return messages
end

"""
    warn_unsupported(loaded)

Warn about what the Macro case leaves out, once per message across the loaded stages. In a
multi-stage case, a message that only some stages give names them.
"""
function warn_unsupported(loaded)
    messages = String[]
    stages = Dict{String, Vector{Any}}()
    for s in loaded, message in unsupported_warnings(s.inputs, s.setup)
        haskey(stages, message) || push!(messages, message)
        push!(get!(stages, message, Any[]), s.stage)
    end
    for message in messages
        st = stages[message]
        if length(st) < length(loaded)
            message *= " In stage$(length(st) == 1 ? "" : "s") $(join(st, ", "))."
        end
        @warn message
    end
    return nothing
end

"""
    log_fuel_commodities(loaded)

Log once which Macro commodity each GenX fuel of the loaded stages was matched to. Fuels are
matched by name, so this shows a name that matched the wrong commodity.
"""
function log_fuel_commodities(loaded)
    fuels = sort(setdiff(union((s.inputs["fuels"] for s in loaded)...), ["None"]))
    isempty(fuels) && return nothing
    matched = ["$f -> $(something(fuel_commodity(f), "no commodity"))" for f in fuels]
    @info "GenX fuels matched to Macro commodities: $(join(matched, ", "))."
    return nothing
end

"Names of the resources `ids`, comma-separated."
resource_names(inputs::Dict, ids) = join((inputs["RESOURCES"][y].resource for y in ids), ", ")

"""
    thermal_fuel(r)

Macro commodity of thermal plant `r`'s fuel. Stops when the fuel has none.
"""
function thermal_fuel(r)
    commodity = fuel_commodity(r.fuel)
    commodity === nothing &&
        error("$(r.resource) uses fuel '$(r.fuel)', which has no Macro commodity in the " *
              "converter; only natural gas, coal and uranium are supported.")
    return commodity
end

"""
    fuel_commodity(fuel)

Macro commodity for a GenX fuel name, matched case-insensitively: natural gas (a name
containing `gas` or `_NG`), coal, or uranium (a name containing `uranium` or `nuclear`).
Returns `nothing` for any other fuel.
"""
function fuel_commodity(fuel::AbstractString)
    f = lowercase(fuel)
    if occursin("gas", f) || occursin("_ng", f) || f == "ng"
        return "NaturalGas"
    elseif occursin("coal", f)
        return "Coal"
    elseif occursin("uranium", f) || occursin("nuclear", f)
        return "Uranium"
    end
    return nothing
end

"""
    zone_region(inputs, z)

Name used for zone `z` in node and line ids: the `region` of the zone's resources, or `z<z>`
for a zone that has none.
"""
function zone_region(inputs::Dict, z::Integer)
    gen = inputs["RESOURCES"]
    y = findfirst(r -> r.zone == z, gen)
    return y === nothing ? "z$z" : gen[y].region
end

"Id of the CO2 node for emissions outside every CO2 cap."
const UNCAPPED_CO2_SINK = "co2_sink"

"Id of the node that receives CO2 captured by CCS plants."
const CO2_CAPTURED_SINK = "co2_captured_sink"

"""
    co2_sink(inputs, zone)

Id of the CO2 node that a resource in `zone` emits to: the node of the zone's CO2 cap, or the
uncapped sink when the case has no cap or the zone is outside every cap. A zone in more than
one cap cannot be represented, since each plant has a single CO2 edge.
"""
function co2_sink(inputs::Dict, zone::Integer)
    haskey(inputs, "dfCO2CapZones") || return UNCAPPED_CO2_SINK
    caps = findall(==(1), inputs["dfCO2CapZones"][zone, :])
    isempty(caps) && return UNCAPPED_CO2_SINK
    length(caps) == 1 || error("Zone $zone belongs to CO2 caps $caps; a plant's emissions " *
                               "can only go to one CO2 node in Macro.")
    return "co2_sink_$(caps[1])"
end

"Thermal resources with carbon capture."
ccs_thermal(inputs::Dict) = intersect(inputs["THERM_ALL"], inputs["CCS"])

"""
    availability!(df, r, pmax, t, base)

Availability entry for resource `r`: the single value when `pmax` is constant, otherwise a
reference to column `r.resource` of system file `base`, whose data is added to `df`.
"""
function availability!(df::DataFrame, r, pmax::AbstractVector, t::Target, base::AbstractString)
    length(unique(pmax)) == 1 && return unique(pmax)
    df[!, Symbol(r.resource)] = pmax
    return Dict("timeseries" => Dict("path" => system_file(t, base, "csv"),
        "header" => r.resource))
end

"""
    capacity_constraints!(constraints, min_cap, max_cap)

Switch on Macro's Min/MaxCapacityConstraint where GenX sets a limit, i.e. a positive value.
"""
function capacity_constraints!(constraints::AbstractDict, min_cap, max_cap)
    min_cap > 0 && (constraints["MinCapacityConstraint"] = true)
    max_cap > 0 && (constraints["MaxCapacityConstraint"] = true)
    return constraints
end

"""
    multistage_fields(r, t; min_retired = nothing)

Investment data a multi-stage Macro case needs for resource `r`: cost of capital, capital
recovery period, lifetime and, when given, the minimum capacity to retire. Taken from the
multi-stage inputs GenX loads with the resource, so GenX's defaults apply. Empty for a
single-stage case.
"""
function multistage_fields(r, t::Target; min_retired = nothing)
    is_multistage(t) || return Dict{String, Any}()
    fields = Dict{String, Any}(
        "wacc" => GenX.tech_wacc(r),
        "capital_recovery_period" => GenX.capital_recovery_period(r),
        "lifetime" => GenX.lifetime(r))
    min_retired === nothing || (fields["min_retired_capacity"] = min_retired)
    return fields
end

"Write `data` to `path` as pretty-printed JSON."
function write_json(path::AbstractString, data)
    open(path, "w") do io
        JSON3.pretty(io, data)
    end
    return nothing
end

"""
    write_asset_json(path, assets)

Write an asset file, or skip it when it has no instances, since Macro needs no file for an
asset type the system does not contain. A file left at `path` by an earlier conversion is
removed, so Macro cannot pick up a stale list of assets.
"""
function write_asset_json(path::AbstractString, assets::Dict)
    if all(isempty(a["instance_data"]) for a in values(assets))
        if isfile(path)
            rm(path)
            @info "Removed $path: the GenX case has no assets of this type"
        end
        return nothing
    end
    write_json(path, assets)
    return nothing
end

"Write `df` to `path` as CSV, unless it is empty."
function write_timeseries_csv(path::AbstractString, df::DataFrame)
    isempty(df) || CSV.write(path, df)
    return nothing
end

"""
    make_macro_dir(macro_case, stages)

Create the Macro case folders and write `system_data.json`. `stages` lists the stage numbers
of a multi-stage case, or is `[nothing]` for a single-stage one. `macro_settings.json` is only
written when missing, so local edits to it survive a new conversion.
"""
function make_macro_dir(macro_case::AbstractString, stages::AbstractVector)
    for folder in ("system", "assets", "settings")
        mkpath(joinpath(macro_case, folder))
    end

    function system_data(stage)
        t = Target(macro_case, stage)
        return Dict(
            "commodities" => Dict("path" => "system/commodities.json"),
            # Macro requires a locations entry even when the case defines no locations; it
            # only warns that the file is missing.
            "locations" => Dict("path" => is_multistage(t) ? "locations.json" : "locations"),
            "settings" => Dict("path" => "settings/macro_settings.json"),
            "assets" => Dict("path" => dirname(asset_file(t, "x"))),
            "time_data" => Dict("path" => system_file(t, "time_data", "json")),
            "nodes" => Dict("path" => system_file(t, "nodes", "json")))
    end

    if stages == [nothing]
        write_json(joinpath(macro_case, "system_data.json"), system_data(nothing))
    else
        write_json(joinpath(macro_case, "system_data.json"), Dict(
            "case" => [system_data(s) for s in stages],
            "settings" => Dict("path" => "settings/case_settings.json")))
    end

    macro_settings = joinpath(macro_case, "settings", "macro_settings.json")
    isfile(macro_settings) ||
        write_json(macro_settings, Dict("ConstraintScaling" => false, "OutputLayout" => "wide"))
    return nothing
end

"""
    make_case_settings_json(multistage_settings, settings, macro_case)

Write Macro's `case_settings.json` from the GenX multi-stage settings and `genx_settings.yml`
settings, so period lengths, the discount rate, foresight and parameter scaling match the GenX
run. The multi-stage settings are those GenX reads, with its defaults and the old `WACC` name
for the discount rate accepted.
"""
function make_case_settings_json(ms::Dict, settings::Dict, macro_case::AbstractString)
    case_settings = Dict(
        "PeriodLengths" => ms["StageLengths"],
        "DiscountRate" => ms["DiscountRate"],
        "ExpansionHorizon" => ms["Myopic"] == 1 ? "Myopic" : "PerfectForesight",
        "SolutionAlgorithm" => "Monolithic",
        "ParameterScaling" => settings["ParameterScale"] == 1)

    write_json(joinpath(macro_case, "settings", "case_settings.json"), case_settings)
    return nothing
end

"""
    stage_folders(genx_case, multistage_settings)

Stage numbers and input folders of a multi-stage case: `inputs/inputs_p1` to
`inputs/inputs_p<NumStages>`, the stages GenX runs. Stops when one of them is missing or when
`StageLengths` does not give one length per stage.
"""
function stage_folders(genx_case::AbstractString, ms::Dict)
    n = ms["NumStages"]
    length(ms["StageLengths"]) == n ||
        error("multi_stage_settings.yml sets NumStages = $n but gives " *
              "$(length(ms["StageLengths"])) StageLengths; give one length per stage.")
    inputs_dir = joinpath(genx_case, "inputs")
    folders = [joinpath(inputs_dir, "inputs_p$p") for p in 1:n]
    absent = filter(!isdir, folders)
    isempty(absent) || error("NumStages = $n, but these stage folders do not exist: " *
                             "$(join(absent, ", ")).")
    unused = filter(readdir(inputs_dir)) do d
        m = match(r"^inputs_p(\d+)$", d)
        m !== nothing && parse(Int, m[1]) > n
    end
    isempty(unused) || @info "Not converting $(join(unused, ", ")): NumStages = $n, and GenX " *
                             "skips them too."
    return [(string(p), folders[p]) for p in 1:n]
end
