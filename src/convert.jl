"""
    convert_genx_case(genx_case, macro_case)

Convert the GenX case in `genx_case` into a Macro case in `macro_case`.

A multi-stage case (`MultiStage: 1`) becomes a multi-period Macro case: one asset folder and one
set of system files per `inputs/inputs_p<n>` stage folder, plus `case_settings.json` built from
the GenX multi-stage settings. Any other case is converted once.

Every stage is loaded and checked before anything is written, so an unsupported feature stops
the conversion without leaving a partial case behind.
"""
function convert_genx_case(genx_case::AbstractString, macro_case::AbstractString)
    settings = GenX.configure_settings(
        GenX.get_settings_path(genx_case, "genx_settings.yml"),
        GenX.get_settings_path(genx_case, "output_settings.yml"))
    multistage = settings["MultiStage"] == 1

    if multistage
        inputs_dir = joinpath(genx_case, "inputs")
        folders = filter(d -> isdir(joinpath(inputs_dir, d)) && occursin(r"^inputs_p\d+$", d),
            readdir(inputs_dir))
        isempty(folders) && error("No inputs_p<n> stage folders found in $inputs_dir.")
        sort!(folders, by = d -> parse(Int, get_stage_number(d)))
        stages = [(get_stage_number(d), joinpath(inputs_dir, d)) for d in folders]
    else
        stages = [(nothing, genx_case)]
    end

    loaded = map(enumerate(stages)) do (i, (stage, path))
        setup, inputs = load_genx_case(genx_case, path)
        check_supported(inputs, setup; warn = i == 1)
        (stage = stage, path = path, setup = setup, inputs = inputs)
    end
    commodities = union((case_commodities(s.inputs) for s in loaded)...)

    make_macro_dir(macro_case, [s.stage for s in loaded])
    make_commodities_json(commodities, macro_case)
    for s in loaded
        t = Target(macro_case, s.stage)
        mkpath(dirname(case_path(t, asset_file(t, "x"))))
        make_timedata_json(s.inputs, s.setup, commodities, s.path, t)
        make_nodes_json_demands_and_fuels(s.inputs, s.setup, t)
        make_thermal_json(s.inputs, s.setup, t)
        make_thermal_ccs_json(s.inputs, s.setup, t)
        make_vre_json(s.inputs, s.setup, t)
        make_storage_json(s.inputs, s.setup, t)
        make_transmission_json(s.inputs, s.setup, t)
        make_mustrun_json(s.inputs, s.setup, t)
        make_hydro_json(s.inputs, s.setup, t)
    end
    multistage && make_case_settings_json(genx_case, macro_case)
    return macro_case
end
