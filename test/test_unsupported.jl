# What the converter rejects, warns about, or has to work around.

@testset "Rate-based CO2 cap stops before writing" begin
    case = example_case("6_three_zones_w_multistage")  # shipped with CO2Cap = 2
    out = joinpath(mktempdir(), "macro")
    @test_throws r"rate-based CO2 cap" redirect_stdout(devnull) do
        convert_genx_case(case, out)
    end
    @test !isdir(out)
end

@testset "Fuel without a Macro commodity" begin
    case = example_case("1_three_zones")
    setup, inputs = load_quietly(case)
    y = first(inputs["THERM_ALL"])
    inputs["RESOURCES"][y].fuel = "hydrogen"
    inputs["fuel_CO2"]["hydrogen"] = 0.0
    out = mktempdir()
    mkpath(joinpath(out, "assets")); mkpath(joinpath(out, "system"))
    @test_throws r"uses fuel 'hydrogen'" make_thermal_json(inputs, setup, Target(out, nothing))
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
end
