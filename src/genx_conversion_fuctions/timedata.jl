"""
    make_timedata_json(inputs, setup, commodities, genx_inputs_path, t)

Write the time data for `commodities`. With time domain reduction, also copy GenX's period
map from the TDR folder of `genx_inputs_path` (the case, or the stage folder of a multi-stage
case), which must already exist since the inputs were read from the clustered data.
"""
function make_timedata_json(inputs::Dict, setup::Dict, commodities,
        genx_inputs_path::AbstractString, t::Target)
    # Macro scales the subperiod weights to sum to TotalHoursModeled, as GenX's Sub_Weights do.
    # The weights can sum to e.g. 8760.000000000002; Macro requires a whole number.
    time_data = Dict{String, Any}(
        "HoursPerSubperiod" => Dict{AbstractString, Int64}(c => inputs["H"] for c in commodities),
        "HoursPerTimeStep" => Dict{AbstractString, Int64}(c => 1 for c in commodities),
        "NumberOfSubperiods" => inputs["REP_PERIOD"],
        "TotalHoursModeled" => round(Int, sum(inputs["Weights"])))

    if setup["TimeDomainReduction"] == 1
        period_map = system_file(t, "Period_map", "csv")
        cp(period_map_source(setup, genx_inputs_path), case_path(t, period_map); force = true)
        time_data["SubPeriodMap"] = Dict("path" => period_map)
    end

    write_json(case_path(t, system_file(t, "time_data", "json")), time_data)
    return time_data
end

"""
    period_map_source(setup, genx_inputs_path)

GenX's period map in the time domain reduction folder of `genx_inputs_path`. Stops when it
does not exist.
"""
function period_map_source(setup::Dict, genx_inputs_path::AbstractString)
    source = joinpath(genx_inputs_path, setup["TimeDomainReductionFolder"], "Period_map.csv")
    isfile(source) || error("TimeDomainReduction is on but $source does not exist. " *
                            "Run GenX's time domain reduction before converting.")
    return source
end
