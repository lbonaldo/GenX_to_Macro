# What the converter rejects, warns about, or has to work around.

@testset "Rate-based CO2 cap stops before writing" begin
    case = example_case("6_three_zones_w_multistage")  # shipped with CO2Cap = 2
    out = joinpath(mktempdir(), "macro")
    @test_throws r"rate-based CO2 cap" redirect_stdout(devnull) do
        convert_genx_case(case, out)
    end
    @test !isdir(out)
end

@testset "Fuel without a Macro commodity stops before writing" begin
    case = example_case("1_three_zones")
    existing = convert_case(case)  # a Macro case converted before the fuel changes
    before = snapshot(existing)

    thermal = read_csv(joinpath(case, "resources", "Thermal.csv"))
    fuels_path = joinpath(case, "system", "Fuels_data.csv")
    fuels = read_csv(fuels_path)
    fuels.hydrogen = fuels[!, thermal.Fuel[1]]
    CSV.write(fuels_path, fuels)
    set_resource_values!(case, "Thermal.csv", 1, "Fuel" => "hydrogen")

    message = Regex("$(thermal.Resource[1]) uses fuel 'hydrogen'")
    fresh = joinpath(mktempdir(), "macro")
    @test_throws message convert_quietly(case, fresh)
    @test !isdir(fresh)
    @test_throws message convert_quietly(case, existing)
    @test snapshot(existing) == before
end

@testset "Zone in two CO2 caps stops before writing" begin
    case = example_case("1_three_zones"; CO2Cap = 1)
    path = joinpath(case, "policies", "CO2_cap.csv")
    write(path, replace(read(path, String), "MA,z1,1,0,0," => "MA,z1,1,1,0,"))
    fresh = joinpath(mktempdir(), "macro")
    @test_throws r"Zone 1 belongs to CO2 caps \[1, 2\]" convert_quietly(case, fresh)
    @test !isdir(fresh)
end

@testset "Biomass plant with carbon capture stops before writing" begin
    case = example_case("3_three_zones_w_co2_capture")
    set_resource_values!(case, "Thermal.csv", 1, "Biomass" => 1)
    out = joinpath(mktempdir(), "macro")
    @test_throws r"negative CO2 emissions.*MA_natural_gas_combined_cycle" redirect_stdout(devnull) do
        convert_genx_case(case, out)
    end
    @test !isdir(out)
end

@testset "Non-thermal resource that burns fuel and captures CO2" begin
    case = example_case("1_three_zones")
    set_resource_values!(case, "Vre.csv", 1, "Fuel" => "MA_NG",
        "Heat_Rate_MMBTU_per_MWh" => 1.0, "CO2_Capture_Fraction" => 0.5)
    setup, inputs = load_quietly(case)
    solar = findfirst(r -> r.resource == "MA_solar_pv", inputs["RESOURCES"])
    @test solar in inputs["CCS"]  # GenX's CCS set is not limited to thermal plants
    @test_logs (:warn, r"lose their fuel use, CO2 emissions and CO2 capture: MA_solar_pv") match_mode = :any check_supported(inputs, setup)
end

@testset "Thermal features that are not converted" begin
    setup, inputs = load_quietly(example_case("5_three_zones_w_piecewise_fuel"))
    @test_logs (:warn, r"piecewise fuel usage") match_mode = :any check_supported(inputs, setup)

    # Example 9's retrofit options burn ammonia, which stops the conversion, so check the
    # warning itself.
    setup, inputs = load_quietly(example_case("9_three_zones_w_retrofit"; CO2Cap = 1))
    @test any(contains("retrofits"), G2M.unsupported_warnings(inputs, setup))

    setup, inputs = load_quietly(example_case("1_three_zones"; MinCapReq = 0))
    @test_logs check_supported(inputs, setup)  # no features in use, no warning
    inputs["RESOURCES"][first(inputs["THERM_ALL"])].maint = 1
    @test_logs (:warn, r"thermal features are not converted: maintenance") check_supported(inputs, setup)
end

@testset "Example 12: zones without plants, parallel lines, coal and nuclear fuels" begin
    case = example_case("12_IEEE_9_bus_DC_OPF_expansion")
    out = @test_logs (:warn, r"DC_OPF, DiscreteInvestments") match_mode = :any convert_case(case)
    setup, inputs = load_quietly(case)

    @test issubset(["NaturalGas", "Uranium", "Coal"], read_json(out, "system/commodities.json")[:commodities])
    elec = only(g for g in node_groups(out) if g[:type] == "Electricity")
    ids = [n[:id] for n in elec[:instance_data]]
    @test length(ids) == inputs["Z"]
    @test any(startswith(id, "elec_z") for id in ids)  # zones with no plants get a fallback name

    lines = [l[:id] for l in instances(out, "assets/transmission.json", :transmission)]
    @test length(lines) == inputs["L"]
    @test allunique(lines)
    @test any(occursin("_line", id) for id in lines)  # parallel lines carry their number
    @test load_in_macro(out) isa MacroEnergy.Case
end
