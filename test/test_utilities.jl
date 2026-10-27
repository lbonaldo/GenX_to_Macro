# Unit tests of the shared helpers; no GenX case is loaded.

@testset "Paths" begin
    single, stage2 = Target("case", nothing), Target("case", "2")
    @test G2M.asset_file(single, "vre") == "assets/vre.json"
    @test G2M.asset_file(stage2, "vre") == "assets/assets_2/vre.json"
    @test G2M.system_file(single, "demand", "csv") == "system/demand.csv"
    @test G2M.system_file(stage2, "demand", "csv") == "system/demand_2.csv"
    @test get_stage_number("inputs_p12") == "12"
    @test_throws ErrorException get_stage_number("inputs")
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
    inputs = Dict("L" => 1, "MULTI_FUELS" => Int[], "RESOURCES" => [(resource = "gas",)])
    ok = Dict("CO2Cap" => 1, "Trans_Loss_Segments" => 1)
    @test check_supported(inputs, ok; warn = false) === nothing
    for cap in (2, 3)
        @test_throws r"rate-based CO2 cap" check_supported(inputs, merge(ok, Dict("CO2Cap" => cap)); warn = false)
    end
    @test_throws r"quadratic line losses" check_supported(inputs,
        merge(ok, Dict("Trans_Loss_Segments" => 2)); warn = false)
    @test_throws r"Multi-fuel resources cannot be converted: gas" check_supported(
        merge(inputs, Dict("MULTI_FUELS" => [1])), ok; warn = false)
    @test_logs (:warn, r"MinCapReq, DC_OPF") check_supported(inputs,
        merge(ok, Dict("MinCapReq" => 1, "DC_OPF" => 1)))
end
