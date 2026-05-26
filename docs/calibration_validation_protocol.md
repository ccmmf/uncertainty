# Calibration and Validation Data Collection Protocol

Author: David LeBauer

Status: Protocol and schema are working drafts. As a draft, this document and schema should be updated as needed.

**Purpose**

Protocol for spreadsheet-based curation of published and / or archived datasets for crop model calibration and validation.

This document describes a protocol that data curators can use to compile target observations as well as context required for running a model. It uses a file-based workflow centered on a curation workbook, dataset README notes, and later conversion to structured flat files for model configuration and evaluation. It is based on the BETYdb data entry docs, but does not assume a web based UI, API, or PostgreSQL database.

## 1. Scope and status

This protocol describes how to curate published or archived datasets into the current calibration/validation workbook.

The immediate goal is to capture what the source actually reports in a way that is:

- traceable  
- reviewable  
- practical and usable for curation  
- flexible enough to support schema refinement

This is a working protocol, not a finalized publication. Some fields and conventions will change as more datasets are curated.

Dataset-specific discussions and decisions should be tracked in the relevant GitHub issue. This document will capture general decisions.

## 2. Purpose and guiding principles

**Required:** Capture first, estimate later.

- Record what is reported by the source.  
- Do not silently fill unsupported values during curation.  
- Leave gap-filling of management practices, soil properties, initial conditions, biomass pools, and similar model-facing quantities to a separate downstream pipeline.

**Recommended:** Prefer raw data over summary data.

- If replicate- or plot-level data are available, curate those.  
- If only summary data are available, capture the summaries clearly as summaries.  
- If both raw and summary data are retained, collect raw data, optionally use summaries for QC.

**Recommended:** Prefer archived and citable sources.

Source priority should normally be:

1. Archived data at the level of replication  
2. Supplementary tables and appendices  
3. Publication tables  
4. Publication text  
5. Data extracted from figures  
6. Other non-archived sources only when necessary and documented

**Required:** Make uncertainty explicit.

- Use date ranges rather than fake exact dates.  
- Flag approximate, derived, and missing values.  
- Document unresolved ambiguities in the GitHub issue; summarize in dataset README.

**Required:** Keep curation separate from later harmonization.

- During curation, store reported values in reported units.  
- Capture statistics as published.  
- Do not overwrite reported values with converted values.  
- Programmatic unit conversion and statistic conversion happen later, so assumptions can be explicit in code.

**Required:** Use stable text-based keys.

- Use human-readable text identifiers such as `dataset_id`, `citation_id`, `site_id`, `treatment_id`, and `method_id`.  
- Do not rely on numeric or arcane database IDs.

**Recommended:** Treat the spreadsheet as the main curation interface.

- Use the workbook for first-pass structured capture.  
- Use README notes and GitHub issues for dataset-specific instructions.  
- Promote recurring patterns into schema changes only after they appear across multiple datasets.  
- Export to CSV under version control after initial review and revision.

## 3. Deliverables and workflow stages

The usual workflow is:

1. Assemble the source packet including papers and data.  
2. Confirm the dataset is in scope for calibration or validation.  
3. Add the paper and any archived data to the project Zotero folders.  
4. Populate the workbook tabs.  
5. Document assumptions, unavoidable transformations, and unresolved issues in the dataset README.  
6. Run basic QA. [TODO: define]  
7. Hand off for later conversion, harmonization, and gap-filling.

**Required:** Keep project-level source organization simple.

- Maintain project-specific Zotero folders for `to enter` and `entered`.  
- Make sure the curated dataset can be traced back to a stable paper, archive, supplement, or figure source.  
- TODO: put CSVs under version control  
- TODO: annotate PDFs in Zotero?

**Do not:** Optimize early curation around the final downstream file layout.

The first priority is accurate capture and documentation.

**Do not:** Collect all data or stray from targets.

## 4. Source handling

### 4.1 Required source tracking

For every curated dataset, record:

- the primary paper citation  
- DOI when available  
- archived dataset DOI or accession when available  
- supplementary files used  
- companion papers used for methods or timing context  
- any non-DOI sources used, and why  
- terms of use or license if known

### 4.2 Source roles

Use archived data files and source tables as the primary source for observations whenever possible.

Use paper text, methods, captions, and related papers mainly for:

- site metadata  
- treatment interpretation  
- method descriptions  
- timing context  
- management context  
- design interpretation

### 4.3 Source traceability

**Required:** Every curated row must be traceable to a source.

At minimum, each row or group of rows should link back to:

- a citation or source ID  
- a table, figure, worksheet, or file  
- notes sufficient for a second curator to retrace the value

**Recommended:** When extracting from figures, record figure number or panel.

## 5. Using the curation workbook

The workbook separates several important concepts. Treat these tabs as the core curation surface:

- `citations`  
- `sites`  
- `treatments`  
- `methods`  
- `observations`  
- `managements`  
- `variables`  
- `crops`  
- coverage or planning tabs

### 5.1 General workbook rules

**Required:** Use text keys consistently across tabs. Text should be easy for human to map to the source, i.e. site and treatment appear in text.

Examples:

- `dataset_id`: short dataset identifier for the curated source packet  
- `citation_id`: stable local text key in `authorYYYYabc` style  
- `site_id`: stable site key for the real experimental location  
- `treatment_id`: stable treatment or system key  
- `method_id`: stable method key  
- `replicate_id`: text identifier for plot, block, core, chamber, or replicate

**Recommended:** Keep keys source-facing where possible.

- Reuse source labels or system IDs when they are stable and interpretable.  
- Avoid opaque internal codes when a clearer text key is available.

**Do not:** Collapse multiple concepts into one key.

- A site key should not encode the treatment.  
- A treatment key should not be the only place where factor structure is documented.  
- A replicate identifier should not be hidden in notes if it can be represented explicitly. TODO: explain with examples such as `block_a_plot_3` vs buried notes

## 6. Core data model

### 6.1 Citations

A citation identifies the source of the data or metadata.

**Required:** Capture enough information to identify and retrieve the source again.

Minimum:

- `citation_id`  
- full citation text or bibliographic reference  
- `doi` when available

**Recommended:** A stable local text key such as `authorYYYYabc` can be used as `citation_id`, where `abc` is based on the first letters of the first three informative words in the title.

TODO: decide whether `citation_id` should be the canonical local key, whether DOI should serve as the primary key when available, or whether this is purely a schema decision and should be omitted from protocol text.

### 6.2 Sites

A site is the experimental location.

**Required:** Represent sites separately from treatments.

Minimum:

- `site_id`  
- recognizable site name  
- citation linkage

When available, also capture:

- latitude and longitude  
- country, state, nearest city  
- greenhouse or controlled-environment status  
- soil context  
- elevation

**Recommended:** Record location precision honestly.

If exact coordinates are not reported, use the best recoverable coordinates and explain the basis in notes.

**Do not:** Create separate sites for each plot if all observations come from the same experimental location.

Plot- or block-level spatial definitions for remote sensing or spatial analysis may be useful later, but they are out of scope for the current curation protocol.

### 6.3 Treatments

A treatment is the experimental condition, management combination, or system contrast associated with an observation.

**Required:** Represent treatments as categorical conditions with names that are recognizable from source.

Minimum:

- `treatment_id`  
- treatment name or source label  
- treatment definition  
- control status if identifiable

**Recommended:** Keep continuous quantities out of the treatment name unless the source itself uses them as the treatment label.

The treatment definition is where the curator explains the intended contrast. Quantified operations should also appear in the management events table when they can be recovered.

**Do not:** Use treatments to represent information that belongs in another field such as site, cultivar, replicate, or date.

### 6.4 Methods

A method describes how an observation was measured or derived by the source.

**Required:** Give each distinct method a stable `method_id`.

Method records should capture:

- `method_id`  
- short name  
- description  
- relevant citation

**Recommended:** Record method distinctions that materially affect interpretation, such as:

- dry vs wet basis  
- concentration vs stock  
- depth interval  
- flux chamber vs inferred annual total  
- elemental analysis vs sensor estimate

### 6.5 Observations

An observation row is the core data unit for calibration or validation.

**Required:** Use long format by default.

One row should represent one `dataset/source × site × treatment × replicate or summary unit × time window × variable`.

Each observation should identify:

- `dataset_id`  
- `citation_id`  
- `site_id`  
- `treatment_id`  
- `replicate_id` or summary unit  
- `variable`  
- `value`  
- `reported_units`  
- `method_id`  
- `min_date`  
- `max_date`  
- observation level  
- statistic fields if applicable  
- notes and flags

The current workbook still uses some older column names such as `trait`, `mean`, `start_date`, and `end_date`. Use those fields pragmatically if needed during current work, but the preferred schema direction is:

- `trait` -> `variable`  
- `mean` -> `value`  
- `start_date` / `end_date` -> `min_date` / `max_date`

### 6.6 Management events

Management should be represented as time-specific events.

**Required:** Keep one row per event.

Management events are distinct from treatments:

- the treatment identifies the experimental condition  
- the event records what happened, when, and with what reported amount or attributes

Because management details vary across event types, use:

- a small required core shared by all events  
- optional stable columns for common event details  
- `attributes_json` for recurring details that are not yet stable enough for first-class columns

## 7. Experimental design guidance

<!--
[TODO: separate minimum requirements for MVP, i.e. focus on simple cases, from how to capture more complex designs].

TODO: subsections are still somewhat verbose and may need consolidation.
-->

### 7.1 What to capture

The calibration / validation data collection template is adequate for single-factor comparisons and repeated observations. It may not be sufficient for complex designs; when encountered these designs should be documented clearly and used to inform later schema changes.

**Required:** For every dataset, document the experimental design in either:

- a dedicated design tab, or  
- a required README section

At minimum, record:

- `design_type`  
- experimental unit TODO: clarify difference between experimental unit, replicate unit, and plot structure  
- replicate unit  
- blocking or plot structure if present  
- factors and levels 
- whether reported observations are cell means, pooled summaries, main effects, or interaction-specific values.

**Recommended:** If the spreadsheet can not capture a design, include the design metadata in the README immediately rather than leaving it implicit.

### 7.2 Is the current schema good enough?

For simple datasets, mostly yes.

For more complex designs, not by itself. The current curation structure needs additional metadata for:

- block and plot hierarchy  
- repeated measures on the same unit TODO: consider whether `plot_id`, `entity_id`, or another grouping field is needed  
- factorial main effects including pooled summaries across factors  
- explicit unit of replication
- TODO: Add experiment_id (currently 'site_id' is overloaded, experiment ID should be explicit)

### 7.3 Treatment comparisons

For datasets used for explicit treatment-contrast calibration or validation, add a `treatment_pairs` table.

This table is required when the task depends on named treatment comparisons. It is not required for every curated dataset.

Minimum fields:

- `pair_id`  
- `treatment_id_1`  
- `treatment_id_2`  
- `comparison_factor`  
- `comparison_label`  
- `notes`

By convention, `treatment_id_1` is the baseline treatment.

Treatment-level control flags may still be stored when obvious from the paper, but pair ordering is authoritative for comparison tasks.

### 7.4 Main effects and aggregated factorial summaries

Published main effects are sometimes the only values available from a factorial study. These can be used with careful construction of model runs. But this is complex and lower prioirty.

**Required:** If only main effects or other aggregated summaries are available:

- capture them only when the cell-level treatment combinations are unavailable  
- mark them as aggregated summaries  
- document which factors were collapsed  
- record what the source actually reported

**Suggestion:** Add fields such as:

- `reported_effect_scope`  
- `aggregated_over_factors`

Examples of `reported_effect_scope`:

- `treatment_mean`  
- `aggregated_mean`

Use `aggregated_over_factors` only for `aggregated_mean` rows. This should list the factor or factors that were collapsed by the published result.

**Do not:** Use a main-effect row as if it were a normal treatment-combination row for later treatment-level comparison without documenting the aggregation.

## 8. Observations

### 8.1 What to include

Target variables will vary by project. 

For the MAGiC project, these are described in [MAGiC Validation data needs](https://docs.google.com/document/d/1so_UjeJROBtLycVOA5JcLp0a4xpSKxYlbXUJLwdLSLE/edit?tab=t.0#heading=h.rkqco27whmzt)

- soil organic carbon concentration  
- soil organic carbon stock, with depth  
- bulk density  
- N2O flux  
- CH4 flux  
- soil inorganic nitrogen  
- initial biomass or carbon pool information when directly reported

**Required:** Focus curation on the variables directly needed for the task being supported.

- **Do not** curate every measurement reported by default.  
- **Do** start from the calibration/validation question, then capture the observations, methods, dates, treatments, and management context needed to support that question.

**Recommended:** Record additional potentially useful data in notes when they are not yet in scope for structured entry.

Examples:

- lower-priority response variables  
- supporting measurements that may become useful later  
- variables mentioned in the paper

Lower-priority variables can still be worth capturing if they provide strong context or future utility.

### 8.2 Raw vs summary data

**Recommended:** Curate raw replicate-level data over summaries when available.

If only summaries are available, capture:

- the summary value  
- statistic type  
- statistic value  
- sample size  
- what the summary represents

**Do not:** Duplicate the same information as both raw and summary unless there is a specific reason to preserve both. When both are available, they can be used for qc, and this should be recorded.

### 8.3 Replicates and plot identity

**Required:** Represent replicate identity explicitly whenever available.

Use text identifiers such as:

- `plot_1`  
- `block_a_plot_3`

### 8.4 Figure-derived observations

If an observation is extracted from a figure, record:

- figure source (citation + number + panel)  
- tool used for extraction    
- additional notes or context

### 8.5 Table-derived observations

If an observation is extracted from a table, record:

- the table number  
- additional notes or context

## 9. Management event rules

### 9.1 What counts as a management event

Capture management events as far as recoverable from the source.

Typical event types include:

- planting  
- harvest or termination  
- irrigation  
- fertilization or amendment addition  
- tillage

The top-level `event_type` should stay PEcAn-aligned where practical. Event-specific details can then be captured in optional columns and `attributes_json`.

### 9.2 What to and not to infer about events

Papers reporting the results of experimental trials often do not provide all information required. This is often because the focus of the experiment is on a particular factor rather than reporting all information required to simulate the experiment.

**Do** infer:

- the fact that an event occurred if high certainty (e.g. crops were planted; there was a harvest event if yields are reported)

**Do not** infer information that is uncertain, including:

- event dates  
- unreported fertilization rates  
- management histories implied only by local practice guidelines  
- any other management attributes

If these are needed downstream, they will be added through a separate gap-filling pipeline.

Relative timing statements such as "before planting" or "after harvest" may still be captured without inventing dates. See Section 10.2.

### 9.3 Relationship between treatments and management events

**Required:** The treatment will be defined in the treatments table; differences between treatments will be encoded in both the treatment-pairs and managements tables.

- The `treatments.definition` fields explains the intended contrast.  
- The management events table records the specific events that define each treatment; treatment differences are reflected in the different event timelines associated with each treatment.
- The `treatment-pairs` table encodes specific treatment comparisons that test the effect of agronomic management practices (e.g. fallow vs. cover-crop; tilled vs zero-tilled; etc)

The MAGiC project focus is:

- cover crop systems
- compost and manure (non-crop carbon) additions  
- fertilizer regimes  
- tillage contrasts  
- irrigation contrasts
- crop rotations and land use change (e.g. row crop --> orchard)
- [and others]

## 10. Date, uncertainty, and missingness handling

### 10.1 Dates

Use `min_date` and `max_date`.

**Required:** For exact dates, set both fields to the same ISO date:

- `YYYY-MM-DD`

**Required:** For approximate timing, bound the interval *only if stated*.

Examples:

- month only  
- season only  
- day-of-year window

If only a month/season is known, use the first and last day of that month/season and explain the basis in notes.

If no reliable date window can be recovered, leave the date fields blank and explain why.

### 10.2 Relative timing

Use relative timing only when the source gives timing relative to another event but does not report an actual date or bounded interval.

Recommended fields:

- `relative_timing`  
- `relative_timing_days`

Examples of `relative_timing`:

- `before_planting`  
- `after_harvest`  
- `at_planting`  
- `at_harvest`

`relative_timing_days` is optional and should be used only when the source reports a numeric offset such as "14 days before planting".

When `relative_timing` is used:

- leave `min_date` and `max_date` blank unless the source also reports an actual date window  
- explain the source basis in notes

## 11. Transformations, units, and statistics

### 11.1 Units

**Required:** Store values in published units during curation.

Also store:

- the reported unit  
- any basis needed to interpret the unit  
  - wet/dry basis  
  - units encode e.g area vs mass vs volume basis, stock vs concentration, etc.

**Do not:** Convert a reported value to a normalized unit during curation.

Programmatic conversion to canonical units happens later.

### 11.2 Manual transformations

If a transformation is unavoidable during curation, document:

- the original value  
- the original unit  
- the formula used  
- the rationale  
- where the transformed value is stored

**Recommended:** Keep manual transformations rare. Script if possible. Record in spreadsheet if not.

### 11.3 Statistics

**Do not** Collect statistical summaries when the underlying plot (or experimental unit of replication) level data are available. Statistical summaries may be collected to use for QC.  

**Required:** Capture statistics as reported.

Examples:

- `SE`  
- `SD`  
- `MSE`  
- `CI`  
- `LSD`  
- `HSD`  
- `MSD`  
- `P`

Priority:

[`SE`, `SD`, `MSE`, `CI`] > [`LSD`, `HSD`, `MSD`] > [`P`, `F`]

Capture:

- `statname`  
- `stat`  
- `n`

and explain anything unusual in notes.

**Do not:** Convert published statistics to standardized variance estimates during curation unless the original reported statistic remains preserved and the conversion is fully documented.

The default workflow is to convert later in code or harmonization. See [`PEcAn.utils::transformstats`](https://github.com/PecanProject/pecan/blob/e31dc122f99f53fd55bf72363d83fcabe19e6afd/base/utils/R/transformstats.R).

## 12. QA expectations

Each curated dataset should include at least the following checks.

### 12.1 Source QA

- every row traces to a citation or source ID  
- table, figure, worksheet, or file provenance is documented

### 12.2 Structural QA

- keys match across tabs  
- sites, treatments, methods, and citations referenced by observations actually exist  
- event rows point to valid site and treatment keys

<!-- TODO: consider enforcing with spreadsheet rules where practical; or automate checks. -->

### 12.3 Observation QA

- expected row counts by source table or figure are reasonable  
- raw and summary rows are clearly distinguished  
- depth intervals and units are consistent with the source  
- Recorded values are not overly precise. Three significant figures are typically sufficient.  
- Date windows are plausible and not silently over-precise.

### 12.4 Summary reconstruction QA

When raw data and published summaries overlap, reconstruct a subset of the reported summaries and confirm agreement within expected rounding error.

### 12.5 Documentation QA

- the README matches the current workbook  
- assumptions and unresolved ambiguities are current  
- flag meanings are defined

## 13. Required documentation per curated dataset

Each curated dataset should include a README or equivalent data-entry report containing:

- dataset name and scope  
- primary sources  
- worksheets or other notes collected during curation  
- terms of use and/or license. If not known, state.  
- method notes  
- experimental design summary  
- replicate and plot conventions  
- missingness and flag definitions  
- unresolved ambiguities  
- items deferred to the gap-filling pipeline

README notes should describe the current dataset state only. Avoid stale copied boilerplate.

## 14. Escalation and ambiguity handling

If anything materially affects interpretation:

- stop  
- document the ambiguity  
- ask on Slack or GitHub issue associated w/ dataset

Examples:

- unclear treatment mapping  
- uncertain site identity  
- ambiguous time window  
- pooled main effect reported without enough design context  
- management details that may change the modeled interpretation

**Do not:** Resolve major schema or interpretation ambiguity silently.

## 15. Proposed management events table schema

### 15.1 Required core columns

These are the minimum columns recommended for routine curation.

| column | status | description |
| :---- | :---- | :---- |
| `site_id` | required | Stable site key |
| `treatment_id` | required | Stable treatment or system key |
| `event_type` | required | PEcAn-aligned event type such as `planting`, `harvest`, `irrigation`, `fertilization`, `tillage` |
| `min_date` | required when recoverable | Earliest plausible event date |
| `max_date` | required when recoverable | Latest plausible event date |
| `source_id` | required | Citation or source key |
| `notes` | recommended | Human-readable event notes |
| `relative_timing` | optional | Relative timing category when date is described relative to another event |
| `relative_timing_days` | optional | Numeric day offset associated with `relative_timing` when reported |
| `attributes_json` | optional | Additional structured event metadata not yet promoted to columns |

TODO: decide whether `relative_timing` and `relative_timing_days` should remain first-class columns or move into `attributes_json`.

### 15.2 Optional stable columns for routine curation

These columns are worth using when the source reports them directly.

| column | applies to | notes |
| :---- | :---- | :---- |
| `crop_code` | planting | Stable crop identifier when available |
| `crop_display` | planting | Human-readable crop name |
| `reported_amount` | irrigation, fertilization, harvest, amendment | Store the amount as reported |
| `reported_units` | irrigation, fertilization, harvest, amendment | Store the original reported units |
| `method` | irrigation | For example `soil`, `canopy`, `flood` when reported |
| `depth_m` | tillage | Reported tillage depth |
| `intensity_category` | tillage | For example `zero`, `reduced`, `conventional` |
| `frac_above_removed_0to1` | harvest | Only when directly reported or directly recoverable |
| `reported_material` | fertilization or amendment | For example compost, manure, urea, ammonium sulfate |

### 15.3 PEcAn-aligned reference fields for later conversion

The current PEcAn `events.json` schema includes fields such as:

- `leaf_c_kg_m2`  
- `wood_c_kg_m2`  
- `fine_root_c_kg_m2`  
- `coarse_root_c_kg_m2`  
- `frac_below_removed_0to1`  
- `frac_above_to_litter_0to1`  
- `frac_below_to_litter_0to1`  
- `amount_mm`  
- `immed_evap_frac_0to1`  
- `org_c_kg_m2`  
- `org_n_kg_m2`  
- `nh4_n_kg_m2`  
- `no3_n_kg_m2`  
- `tillage_eff_0to1`

These should be treated as optional conversion targets, not routine curation requirements.

**Required:** Leave these blank during curation if the paper does not report them.

### 15.4 Why not require all PEcAn fields now?

Because many literature sources do not report the model-facing attributes needed for direct `events.json` population.

The curation schema should therefore:

- preserve reported event information faithfully  
- make later conversion straightforward  
- avoid forcing curators to invent missing model inputs

## 16. Suggested schema changes

The following changes would improve the current curation schema. This section is exploratory and may evolve as more datasets are curated.

### 16.1 Observation schema

- rename `mean` to `value`  
- rename `trait` to `variable`  
- add `reported_units`  
- add `observation_level`  
- add `dataset_id`  
- replace `rep` with `replicate_id`  
- add `block_id` and `plot_id` if needed separately from replicate id  
- use `min_date` and `max_date` consistently  
- add `reported_effect_scope` with clearly defined values such as `treatment_mean` and `aggregated_mean`  
- add `aggregated_over_factors` for aggregated summaries

### 16.2 Experimental design metadata

Add one of the following:

- a dedicated design tab, or  
- a required structured README section

Recommended fields:

- `design_type`  
- `experimental_unit`  
- `replicate_unit`  
- `control_definition`  
- factor names and levels  
- `treatment_pairs` for explicit contrast tasks

### 16.3 Management schema

The current management sheet pattern using generic columns such as `mgmttype`, `level`, `units`, and `estimated` is useful for quick capture but should evolve toward:

- required event core columns  
- optional stable event columns  
- `attributes_json` for overflow

This will better support later conversion to PEcAn-compatible events.

## 17. Future workflow expansion

This protocol can later be reorganized into a fuller BETYdb-style step-by-step workflow, but the current version is intended to be usable now.

- Import / integrate figure extraction, unit conversion, statistic conversion, site guidance, treatment guidance, management concepts, and QA material as reusable references.  
- Add a top-level pointer directing curators from the legacy BETYdb workflow docs to this spreadsheet-first protocol.  
- Over time, separate reusable curation principles from BETYdb-specific implementation details.

## 18. Open questions and likely future extensions

The following questions should be revisited after several real datasets have been curated:

- whether to add a dedicated design tab instead of relying on README notes  
- how to represent repeated measures on the same experimental unit  
- how best to encode pooled main effects and interaction summaries in downstream conversion  
- whether to add explicit source-location fields such as `source_table`, `source_figure`, and `source_panel`  
- whether to maintain both reported-unit variables and normalized downstream variable names in the same workbook  
- which recurring `attributes_json` keys should be promoted to first-class columns

Until then, prefer simple, explicit capture over premature schema complexity.  
