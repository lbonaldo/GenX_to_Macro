# Multi-stage conversion of GenX example 6. Shipped with a rate-based CO2 cap, which Macro
# cannot represent, so it is converted here with the mass cap its inputs also define.

@testset "Example 6: multi-stage" begin
    case = example_case("6_three_zones_w_multistage"; CO2Cap = 1)
    ms = GenX.configure_settings_multistage(GenX.get_settings_path(case, "multi_stage_settings.yml"))
    nstages = length(ms["StageLengths"])

    # Pre-existing files: a custom macro_settings.json is kept, a stale asset file removed.
    out = joinpath(mktempdir(), "macro")
    mkpath(joinpath(out, "settings")); mkpath(joinpath(out, "assets", "assets_1"))
    write(joinpath(out, "settings", "macro_settings.json"), """{"ConstraintScaling": true}""")
    write(joinpath(out, "assets", "assets_1", "hydro.json"), "{}")
    redirect_stdout(devnull) do
        convert_genx_case(case, out)
    end
    @test read_json(out, "settings/macro_settings.json")[:ConstraintScaling] == true
    @test !isfile(joinpath(out, "assets", "assets_1", "hydro.json"))

    case_settings = read_json(out, "settings/case_settings.json")
    @test case_settings[:PeriodLengths] == ms["StageLengths"]
    @test case_settings[:DiscountRate] == ms["DiscountRate"]
    @test case_settings[:ExpansionHorizon] == (ms["Myopic"] == 1 ? "Myopic" : "PerfectForesight")

    system_data = read_json(out, "system_data.json")
    @test length(system_data[:case]) == nstages
    @test [s[:assets][:path] for s in system_data[:case]] == ["assets/assets_$p" for p in 1:nstages]
    @test all(haskey(s, :locations) for s in system_data[:case])
    @test length(load_in_macro(out).systems) == nstages

    for p in 1:nstages
        setup, inputs = load_quietly(case, joinpath(case, "inputs", "inputs_p$p"))
        resource(id) = inputs["RESOURCES"][findfirst(g -> g.resource == id, inputs["RESOURCES"])]

        # Lines: total capped at Line_Max_Flow_Possible_MW, each stage's addition at
        # Line_Max_Reinforcement_MW, and the line's own recovery period.
        for (l, line) in enumerate(instances(out, "assets/assets_$p/transmission.json", :transmission))
            edge = line[:edges][:transmission_edge]
            @test edge[:max_capacity] ≈ inputs["pLine_Max_Flow_Possible_MW"][l]
            @test edge[:max_new_capacity] ≈ inputs["pMax_Line_Reinforcement"][l]
            @test edge[:capital_recovery_period] == inputs["Capital_Recovery_Period_Trans"][l]
            @test edge[:constraints][:MaxNewCapacityConstraint]
        end

        # Multi-stage investment data, taken from GenX's loaded inputs.
        for v in instances(out, "assets/assets_$p/vre.json", :VRE)
            r, edge = resource(v[:id]), v[:edges][:edge]
            @test edge[:variable_om_cost] ≈ GenX.var_om_cost_per_mwh(r)
            @test edge[:capital_recovery_period] == GenX.capital_recovery_period(r)
            @test edge[:lifetime] == GenX.lifetime(r)
            @test edge[:min_retired_capacity] ≈ GenX.min_retired_cap_mw(r)
        end
        for s in instances(out, "assets/assets_$p/storage.json", :elec_stor)
            r = resource(s[:id])
            @test s[:storage][:annualized_investment_cost] ≈ r.inv_cost_per_mwhyr
            @test s[:storage][:min_retired_capacity] ≈ GenX.min_retired_energy_cap_mw(r)
            @test s[:edges][:charge_edge][:min_retired_capacity] ≈ GenX.min_retired_charge_cap_mw(r)
        end
        for t in instances(out, "assets/assets_$p/thermal.json", :ThermalPower)
            edge = t[:edges][:elec_edge]
            @test edge[:min_capacity] >= 0
            @test edge[:capital_recovery_period] == GenX.capital_recovery_period(resource(t[:id]))
        end
    end
end

@testset "Example 6: stages follow NumStages" begin
    case = example_case("6_three_zones_w_multistage"; CO2Cap = 1)
    set_setting!(case, "multi_stage_settings.yml", "NumStages", 2)
    set_setting!(case, "multi_stage_settings.yml", "StageLengths", "[10, 10]")
    out = joinpath(mktempdir(), "macro")
    @test_logs (:info, r"Not converting inputs_p3") match_mode = :any convert_quietly(case, out)
    @test length(read_json(out, "system_data.json")[:case]) == 2
    @test read_json(out, "settings/case_settings.json")[:PeriodLengths] == [10, 10]
    @test length(load_in_macro(out).systems) == 2

    # A missing stage, or StageLengths that do not match NumStages, stop before writing.
    fresh = joinpath(mktempdir(), "macro")
    set_setting!(case, "multi_stage_settings.yml", "NumStages", 3)
    @test_throws r"NumStages = 3 but gives 2 StageLengths" convert_quietly(case, fresh)
    set_setting!(case, "multi_stage_settings.yml", "StageLengths", "[10, 10, 10]")
    rm(joinpath(case, "inputs", "inputs_p3"); recursive = true)
    @test_throws r"stage folders do not exist: .*inputs_p3" convert_quietly(case, fresh)
    @test !isdir(fresh)
end

@testset "Example 6: a warning that only a later stage gives" begin
    case = example_case("6_three_zones_w_multistage"; CO2Cap = 1)
    set_resource_values!(joinpath(case, "inputs", "inputs_p2"), "Thermal.csv", 1, "Maint" => 1)
    logs, _ = Test.collect_test_logs() do
        convert_quietly(case, joinpath(mktempdir(), "macro"))
    end
    warnings = [string(l.message) for l in logs if l.level == Logging.Warn]
    @test count(==("These GenX thermal features are not converted: maintenance. In stage 2."),
        warnings) == 1
    @test allunique(warnings)
end
