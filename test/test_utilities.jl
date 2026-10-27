# Unit tests of the shared helpers; no GenX case is loaded.

@testset "Paths" begin
    single, stage2 = Target("case", nothing), Target("case", "2")
    @test G2M.asset_file(single, "vre") == "assets/vre.json"
    @test G2M.asset_file(stage2, "vre") == "assets/assets_2/vre.json"
    @test G2M.system_file(single, "demand", "csv") == "system/demand.csv"
    @test G2M.system_file(stage2, "demand", "csv") == "system/demand_2.csv"
end

@testset "Stage folders" begin
    case = mktempdir()
    foreach(p -> mkpath(joinpath(case, "inputs", "inputs_p$p")), 1:3)
    folder(p) = joinpath(case, "inputs", "inputs_p$p")
    # Stages 1 to NumStages, as in GenX; a further stage folder is left out.
    stages = @test_logs (:info, r"Not converting inputs_p3") G2M.stage_folders(case,
        Dict("NumStages" => 2, "StageLengths" => [10, 10]))
    @test stages == [("1", folder(1)), ("2", folder(2))]
    @test_throws r"NumStages = 3 but gives 2 StageLengths" G2M.stage_folders(case,
        Dict("NumStages" => 3, "StageLengths" => [10, 10]))
    @test_throws r"stage folders do not exist: .*inputs_p4" G2M.stage_folders(case,
        Dict("NumStages" => 4, "StageLengths" => [10, 10, 10, 10]))
end

@testset "Fuel commodities" begin
    for (fuel, commodity) in ["MA_NG" => "NaturalGas", "natural_gas" => "NaturalGas",
        "NG" => "NaturalGas", "Coal" => "Coal", "west_north_central_coal" => "Coal",
        "nuclear" => "Uranium", "new_england_uranium" => "Uranium"]
        @test G2M.fuel_commodity(fuel) == commodity
    end
    @test G2M.fuel_commodity("biomass") === nothing
    @test G2M.fuel_commodity("hydrogen") === nothing
end

@testset "CO2 sinks" begin
    caps = Dict("dfCO2CapZones" => [1 1; 0 1; 0 0])
    @test G2M.co2_sink(caps, 2) == "co2_sink_2"
    @test G2M.co2_sink(caps, 3) == G2M.UNCAPPED_CO2_SINK   # zone outside every cap
    @test G2M.co2_sink(Dict(), 1) == G2M.UNCAPPED_CO2_SINK  # case without a cap
    @test_throws ErrorException G2M.co2_sink(caps, 1)       # zone in two caps
end

@testset "Capacity constraints" begin
    @test isempty(G2M.capacity_constraints!(Dict(), 0, -1))  # GenX's "no limit" values
    both = G2M.capacity_constraints!(Dict(), 5, 10)
    @test both["MinCapacityConstraint"] && both["MaxCapacityConstraint"]
end

@testset "Availability" begin
    t, r, df = Target("case", "1"), (resource = "solar",), DataFrame()
    @test G2M.availability!(df, r, [0.5, 0.5], t, "vre_availability") == [0.5]
    @test ncol(df) == 0
    profile = G2M.availability!(df, r, [0.1, 0.2], t, "vre_availability")
    @test profile["timeseries"] == Dict("path" => "system/vre_availability_1.csv",
        "header" => "solar")
    @test df.solar == [0.1, 0.2]
end

@testset "Asset files" begin
    dir = mktempdir()
    path = joinpath(dir, "hydro.json")
    empty_assets = Dict("hydro_res" => Dict("instance_data" => []))
    write(path, "{}")  # a file left by an earlier conversion
    @test_logs (:info, r"Removed") G2M.write_asset_json(path, empty_assets)
    @test !isfile(path)
    G2M.write_asset_json(path, Dict("hydro_res" => Dict("instance_data" => [Dict("id" => "h")])))
    @test isfile(path)
end

@testset "Commodities file" begin
    dir = mktempdir()
    mkpath(joinpath(dir, "system"))
    @test make_commodities_json(Set(["CO2", "Coal", "Electricity"]), dir) ==
          ["Electricity", "Coal", "CO2"]
    @test read_json(dir, "system/commodities.json")[:commodities] == ["Electricity", "Coal", "CO2"]
end

@testset "check_supported" begin
    inputs = Dict("L" => 1, "MULTI_FUELS" => Int[], "RESOURCES" => [(resource = "gas",)],
        "THERM_ALL" => Int[], "CCS" => Int[], "Weights" => [4380.0, 4380.0])
    ok = Dict("CO2Cap" => 1, "Trans_Loss_Segments" => 1, "TimeDomainReduction" => 0)
    @test check_supported(inputs, ok; warn = false) === nothing
    unequal = merge(inputs, Dict("Weights" => [5000.0, 3760.0]))
    @test_throws r"different Sub_Weights" check_supported(unequal, ok; warn = false)
    @test check_supported(unequal, merge(ok, Dict("TimeDomainReduction" => 1)); warn = false) === nothing
    for cap in (2, 3)
        @test_throws r"rate-based CO2 cap" check_supported(inputs, merge(ok, Dict("CO2Cap" => cap)); warn = false)
    end
    @test_throws r"quadratic line losses" check_supported(inputs,
        merge(ok, Dict("Trans_Loss_Segments" => 2)); warn = false)
    @test_throws r"Multi-fuel resources cannot be converted: gas" check_supported(
        merge(inputs, Dict("MULTI_FUELS" => [1])), ok; warn = false)
    @test_logs (:warn, r"MinCapReq, DC_OPF") check_supported(inputs,
        merge(ok, Dict("MinCapReq" => 1, "DC_OPF" => 1)))

    # Across stages, a warning is given once and names the stages only when not all have it.
    stage(n, setup) = (stage = n, inputs = inputs, setup = setup)
    policy = merge(ok, Dict("MinCapReq" => 1))
    @test_logs (:warn, r"MinCapReq\.$") G2M.warn_unsupported([stage(nothing, policy)])
    @test_logs (:warn, r"MinCapReq\.$") G2M.warn_unsupported([stage("1", policy), stage("2", policy)])
    @test_logs (:warn, r"MinCapReq\. In stage 2\.$") G2M.warn_unsupported(
        [stage("1", ok), stage("2", policy), stage("3", ok)])
    @test_logs (:warn, r"MinCapReq\. In stages 2, 3\.$") G2M.warn_unsupported(
        [stage("1", ok), stage("2", policy), stage("3", policy)])
end
