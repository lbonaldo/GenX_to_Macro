# How to add a GenX resource type to the converter

This guide adds conversion for a GenX resource type the converter skips today, such as
flexible demand. Every asset type follows the same pattern, so the new one works for both
single-stage and multi-stage cases.

## Before you start

- Know which Macro asset type the GenX resource maps to, and the fields that asset reads.
  Macro's asset definitions are in `src/model/assets/` of the MacroEnergy package.
- You can run the tests: see [Run the tests](run-the-tests.md).

## Steps

1. Create `src/genx_conversion_fuctions/<type>.jl` with one writer. Use an existing writer such
   as `vre.jl` as a template:

   ```julia
   """
       make_flex_json(inputs, setup, t)

   Write the <MacroType> assets: <one line on what they represent>.
   """
   function make_flex_json(inputs::Dict, setup::Dict, t::Target)
       assets = Dict("flex" => Dict(
           "type" => "<MacroType>",
           "global_data" => Dict(#= settings shared by every instance =#),
           "instance_data" => Vector{Dict{AbstractString, Any}}()))

       gen = inputs["RESOURCES"]
       availability = DataFrame()
       for y in inputs["FLEX"]
           r = gen[y]
           edge = Dict{String, Any}(
               "end_vertex" => "elec_" * r.region,
               "availability" => availability!(availability, r, inputs["pP_Max"][y, :], t,
                   "flex_availability"),
               "constraints" => capacity_constraints!(Dict("CapacityConstraint" => true),
                   GenX.min_cap_mw(r), GenX.max_cap_mw(r)),
               # ... the remaining fields, read from GenX's loaded inputs
           )
           merge!(edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))
           push!(assets["flex"]["instance_data"], Dict("id" => r.resource, "edges" => Dict("edge" => edge)))
       end

       write_asset_json(case_path(t, asset_file(t, "flex")), assets)
       write_timeseries_csv(case_path(t, system_file(t, "flex_availability", "csv")), availability)
       return assets
   end
   ```

   Rules the existing writers follow:

   - Build every path with `asset_file` / `system_file` and `case_path`; the `Target` decides
     single-stage or per-stage names.
   - Read optional GenX columns with GenX's accessors (`GenX.max_cap_mw(r)`, …), which apply
     GenX's defaults.
   - Merge `multistage_fields` into each edge or storage component that has capacity; it adds
     nothing for a single-stage case.
   - Write with `write_asset_json`, which skips the file when the case has none of this type.

2. Register the writer in `src/GenX_to_Macro.jl`: add the `include` and the `export`.

3. Call it in `convert_genx_case` in `src/convert.jl`, next to the other `make_*_json` calls.

4. If the resource uses a commodity the converter does not know yet, add it to
   `COMMODITY_ORDER` and `case_commodities` in `commodities.jl`, and create its nodes in
   `nodes.jl`.

5. Remove the resource type from the "not converted" list in `check_supported`
   (`src/utilities.jl`), so the converter stops warning about it.

6. Add a test that converts a GenX example containing the resource and checks the fields
   against the GenX inputs, as in `test/test_single_stage.jl`. Then run the tests.
