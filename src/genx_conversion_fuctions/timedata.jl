"""
    make_timedata_json(inputs, setup, commodities, genx_inputs_path, t)

Write the time data for `commodities`. With time domain reduction, also copy GenX's period
map from the TDR folder of `genx_inputs_path` (the case, or the stage folder of a multi-stage
case), which must already exist since the inputs were read from the clustered data.
"""
function make_timedata_json(inputs::Dict, setup::Dict, commodities,
        genx_inputs_path::AbstractString, t::Target)
    time_data = Dict{String, Any}(
        "HoursPerSubperiod" => Dict{AbstractString, Int64}(c => inputs["H"] for c in commodities),
        "HoursPerTimeStep" => Dict{AbstractString, Int64}(c => 1 for c in commodities),
        "NumberOfSubperiods" => inputs["REP_PERIOD"])

    if setup["TimeDomainReduction"] == 1
        period_map = system_file(t, "Period_map", "csv")
        source = joinpath(genx_inputs_path, setup["TimeDomainReductionFolder"], "Period_map.csv")
        isfile(source) || error("TimeDomainReduction is on but $source does not exist. " *
                                "Run GenX's time domain reduction before converting.")
        cp(source, case_path(t, period_map); force = true)
        # The weights can sum to e.g. 8760.000000000002; Macro requires a whole number.
        time_data["TotalHoursModeled"] = round(Int, sum(inputs["Weights"]))
        time_data["SubPeriodMap"] = Dict("path" => period_map)
    end

    write_json(case_path(t, system_file(t, "time_data", "json")), time_data)
    return time_data
end
