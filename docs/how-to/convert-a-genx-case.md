# How to convert a GenX case to Macro

This guide turns a GenX case folder, single-stage or multi-stage, into a Macro case folder,
and optionally runs both models.

## Before you start

- The repository's Julia environment is instantiated (`julia --project=. -e 'using Pkg;
  Pkg.instantiate()'`).
- The GenX case runs in GenX. If it uses time domain reduction (`TimeDomainReduction: 1`), the
  clustered data must already exist: run the case in GenX once, or set
  `TimeDomainReduction: 0`.

## Steps

1. Put the GenX case folder somewhere convenient, for example under `genx_cases/`.

2. Convert it, either with the script or from Julia.

   With the script, set the case names at the top of `Multistage_convert.jl`:

   ```julia
   genx_case = "my_genx_case"      # folder under genx_cases/
   output_case = "my_macro_case"   # created under genx_cases/
   run_genx = false                # true to run GenX after converting
   run_macro = false               # true to run Macro after converting
   use_gurobi = false              # true to solve with Gurobi instead of HiGHS
   ```

   Gurobi must be in your global Julia environment
   (`julia -e 'using Pkg; Pkg.add("Gurobi")'`); HiGHS comes with GenX and Macro.

   and run it from the repository root:

   ```bash
   julia --project=. Multistage_convert.jl
   ```

   From Julia, call the converter directly:

   ```julia
   using GenX_to_Macro
   convert_genx_case("genx_cases/my_genx_case", "genx_cases/my_macro_case")
   ```

   The script handles single-stage cases too, despite its name.

3. Read the warnings printed during conversion. Each names a GenX setting or resource type that
   the Macro case leaves out. If the conversion stops with an error instead, see
   [Resolve conversion errors and warnings](resolve-conversion-errors.md).

4. Check the output folder:

   - single-stage: `assets/<type>.json`, `system/*.json` and `system/*.csv`
   - multi-stage: `assets/assets_<n>/` and `system/<file>_<n>` for each stage, plus
     `settings/case_settings.json` with the period lengths, discount rate and foresight taken
     from the GenX settings. As in GenX, the stages are `inputs/inputs_p1` to
     `inputs/inputs_p<NumStages>`; any further stage folder is left out.

5. Run Macro on it, if the script has not already:

   ```julia
   using MacroEnergy
   MacroEnergy.run_case("genx_cases/my_macro_case")  # HiGHS
   ```

   With Gurobi, also pass Gurobi options: Macro's defaults are HiGHS options, which Gurobi
   rejects.

   ```julia
   using MacroEnergy, Gurobi
   MacroEnergy.run_case("genx_cases/my_macro_case"; optimizer = Gurobi.Optimizer,
       optimizer_attributes = ("Method" => 2, "Crossover" => -1))
   ```

   Results go to `results_001/` inside the Macro case, then `results_002/`, and so on.

## Converting again into the same folder

Converting into an existing Macro case updates it in place. Asset and system files are
rewritten, asset files for types the case no longer has are deleted, and `case_settings.json`
is regenerated. `settings/macro_settings.json` is kept if it exists, so edits to it survive.
