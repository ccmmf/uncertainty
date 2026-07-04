# Data Entry Report: White/Salinas Cover Crop + Compost Dataset

**Dataset:** White et al. (2020a) — see Citations at the bottom of this document.

**Entered by:** Aritra Dey  
**Entry date:** 2026-04-10  
**Related issue:** [ccmmf/organization#221](https://github.com/ccmmf/organization/issues/221)

---

## Workbook Tabs Populated

All data is ingested into the MAGiC cal/val workbook
([Google Sheets](https://docs.google.com/spreadsheets/d/1pXiZUkNP50WXbmAztoEgUJ6rpQNyewmobCuaFHL8UjQ/edit)),
not local CSV files. The tabs touched by this ingestion:

| Tab | Status | Source |
|------|--------|--------|
| `citations` | Complete | Paper metadata + DOIs for White et al. (2020a, 2020b) and the AgDC archive |
| `sites` | Complete | Paper text (coordinates 36°37′N, 121°32′W) |
| `treatments` | Complete | Paper Table 1 + methods |
| `managements` | Complete (Years 0–8, all 5 systems, season-bound `min_date`/`max_date` per row) | Paper methods |
| `observations` | Years 2–8 block-level rows complete (180 SOC + 180 total N + 180 nitrate-N + POXC/yields); Years 0–1 are still treatment-mean rows pending an Ag Data Commons pull | White et al. (2020a) supplemental tables + (Years 0–1) PLoS ONE S1 |

---

## Data Entry Method

### Site and Treatment Metadata
Extracted directly from paper text and methods section. All 5 treatment systems
are fully documented in the paper. No ambiguity.

### Management Events
The paper describes management as seasonal windows (e.g., "cover crops planted
in fall, incorporated in late winter/early spring"). **No exact calendar dates
are provided for any event in any year.**

Approach taken: record the paper's stated range in `min_date` /
`max_date` rather than inventing point-estimate DOY values from
production-calendar norms. Each managements row carries the
season bounds the paper actually reports (e.g. spring planting →
`min_date=2005-03-01, max_date=2005-05-31`) plus a `notes` field indicating
source (`paper text: spring planting`). Norm-based / monitoring-derived DOY
refinement is deferred to a downstream gap-fill stage rather than baked
into the curated workbook — keeps the date uncertainty in the posterior
instead of pinning to an invented day.

> Note: an earlier draft of this report listed point-estimate DOYs for each
> event type (e.g. DOY 288 for cover crop planting, DOY 121 for spring
> compost). Those values were never propagated into the workbook — the
> managements tab carries season-bound ranges only. Removed here so the
> report doesn't suggest values that aren't in the dataset.

All event rows (Years 0–8, all 5 systems) are in the workbook's
`managements` tab. Treatment-cycle metadata (quadrennial cover crop years,
system-specific rotation) lives alongside the rows in `managements` /
`treatments`, not here.

### SOC Observations
The paper reports annual SOC stock measurements (0–30 cm, Mg ha⁻¹) for Years 0–8
across 5 treatments × 4 replicates = 20 plot-years per year × 9 time points = **180 block-level
SOC rows** (each variable). POXC (labile C) measured at Years 0, 6, 8 only.
Bulk density measured at Years 3 and 7 only.

**Data source.** All block-level values are sourced from the
supplemental tables (Tables 1–4) of White et al. (2020a). Block-level rows
ingested into the MAGiC cal/val workbook
([Google Sheets](https://docs.google.com/spreadsheets/d/1pXiZUkNP50WXbmAztoEgUJ6rpQNyewmobCuaFHL8UjQ/edit))
under the `observations` tab (`observation_level=replicate, n=1`):

- 180 SOC stock + concentration rows
- 180 Total N stock + concentration rows
- 180 nitrate-N rows
- POXC, C/N inputs, and yields

Full citation details (DOI, URL, supplement identifiers) are in the
workbook's `citations` tab.

Years 0–1 block-level SOC remain pooled `treatment_mean` rows in the
workbook; an additional USDA Ag Data Commons pull is needed for full
per-block resolution. The previously circulated DOI did not resolve;
the active AgDC record identifier still needs to be confirmed.

---

## Challenges and Assumptions

### 1. No exact event dates
**Challenge:** The paper provides only seasonal windows (fall, spring, summer)
for all management events. No day-month-year dates are given for any planting,
harvest, tillage, or compost event in any year.

**Approach:** Documented above under *Management Events* — paper's stated
season-bounds go into `min_date` / `max_date`, no point-estimate DOYs are
invented in the workbook.

### 2. Fertilization: not applicable (organic system)
**Challenge:** Issue [#215](https://github.com/ccmmf/organization/issues/215) lists fertilization date and N rate as required management fields.
This is an organic system — no synthetic fertilizer was applied.

**Assumption:** Compost is treated as the organic amendment / N source.
Material type is **urban yard-waste compost** per White et al. (2020b).
Compost N content (15 g N kg⁻¹, applied at 7.6 Mg ha⁻¹) is recorded in the
workbook's `managements` tab as `event_type = compost_application`. The
PLOS ONE paper reports the compost C:N ratio was measured in only 4 of 8
study years and ranged 18–28 (mean 22); per-year compost C:N values are
not captured in the workbook yet — pending a check of the *Data in Brief*
supplement for year-resolved values.

**Schema (resolved):** Per PR #5 review — extend the existing
`fertilization` event with `form: organic` + `material_type` + optional
`C_rate` / `C_N_ratio` fields, rather than introducing a new
`organic_amendment` event_type. Same correctness fix, no schema bump.

### 3. Harvest component and harvest index
**Reported in White et al. (2020b):** romaine lettuce and broccoli harvest
indices are explicitly stated:

> "Vegetable post-harvest residues were estimated based on measured
> harvested shoot biomass and measured harvest indices of 0.26 and 0.24
> for romaine lettuce hearts and broccoli, respectively (Brennan,
> unpublished data). Thus, approximately 74% (1 − 0.26) of total lettuce
> shoot biomass and 76% (1 − 0.24) of total broccoli shoot biomass was
> left in the field as residue."

These values are now in the workbook's `managements` tab harvest rows:

- **Romaine lettuce hearts:** `harvest_index = 0.26`, ~74% residue left
  in field. (Lower than a whole-head value would be — romaine hearts are
  field-trimmed to the heart and outer leaves stay as residue.)
- **Broccoli:** `harvest_index = 0.24`, ~76% residue left in field
  (floret only removed).

Both attributed to *Brennan, unpublished data* per the cited paper.

**Note on Issue [#215](https://github.com/ccmmf/organization/issues/215)
"harvest component required" field:** worth revisiting — when the paper
does not report HI, downstream code can assume a per-crop default and
flag it. We do not need the harvest_component / HI field to block
ingestion. Tracking this as a schema follow-up.

### 4. Quadrennial cover crop schedule
**Challenge:** The paper says cover crops are planted every 4th winter in sys1 and sys2.

**Confirmed from the companion paper (White et al. 2020b):** Quadrennial
cover crop planted in **Years 3 and 7** (fall 2006 and fall 2010), not
Years 1 and 5 as initially assumed. Year 0 pre-study (fall 2003) all
systems received legume-rye; counting from there, the next quadrennial
plantings line up with fall 2006 and fall 2010 (i.e. Years 3 and 7 of
the experimental period).

### 5. GHG flux measurements absent
**Challenge:** Issue [#215](https://github.com/ccmmf/organization/issues/215) lists GHG flux as a validation target. This dataset contains
no N₂O, CH₄, or CO₂ measurements — explicitly noted as a limitation in the paper.

### 6. Pre-study site history and 2003 establishment
**Site history per White et al. (2020b):**
- **1990–1996:** hay production and mixed vegetable / sugar beet trials.
- **1997–2003:** occasional vegetable trials and cover crops with
  **minimal compost or fertilizer inputs** and frequent fallow periods.

This puts the pre-study soil in a relatively low-input baseline state,
not a fully fertilized prior — relevant for Year 0 SOC interpretation
since the baseline C is not a steady-state under the new treatments.

**Challenge:** Pre-study establishment in 2003 included a one-time compost
application at 22 Mg ha⁻¹ (wet weight) — much higher than the subsequent
annual rate and applied to ALL 5 systems. This is materially load-bearing
for the cal/val: the unexpected Year 0 → Year 1 SOC decline reported in
White et al. (2020b) is driven by this pre-treatment compost flush rather
than by the treatments themselves.

**Approach (per PR #5 review):** capture pre-establishment events
explicitly, one row per treatment. This follows the same convention the
workbook already uses for in-treatment events — each `(treatment_id,
event_type, date_range)` gets its own row even when the only differing
field is `treatment_id`. So the 2003 establishment compost expands to 5
identical rows (sys1–sys5) on the `managements` tab. Same pattern for any
prior management we extract from the 1990–2003 site history if/when
those become event-resolved.

A many-to-many normalization (a `managements_treatments` lookup table, or
a `treatment_ids` JSON list on each management row) was considered but
not adopted — duplication-per-treatment is simpler, matches the existing
workbook convention, and remains BETYdb-compatible.

**Schema:** No new flag needed — pre-treatment rows are already
distinguishable as `management.date < treatment.start_date`, so a
downstream query can derive phase from the existing fields without
introducing an `is_establishment` boolean whose meaning is ambiguous to
read later. If multi-year pre-history needs sequencing, negative
`study_year` values are the cleanest convention.

**TODO (workbook):** expand the current single `treatment_id =
all_systems` row for the 2003 compost into 5 per-treatment rows.

---

## Schema Changes Motivated by This Dataset

Schema decisions that arose while ingesting this dataset. Each is annotated
with its current status.

1. ~~`date_precision` field in management_events~~ — **not adopted**. Superseded: `min_date` / `max_date` carry the paper's stated range; `min_date == max_date` ⇒ exact date known, so a separate boolean is redundant.
2. **Organic amendment handling** in `fertilization` — **proposed, awaiting @dlebauer sign-off**. Extend the existing `fertilization` event with `form: organic` + `material_type` + optional `C_rate` / `C_N_ratio`, rather than a new `organic_amendment` event_type. Same correctness fix, no schema bump. Dispatch via `look_up_ca_compost_amendment`.
3. ~~`harvest_component_known` boolean in harvest events~~ — **not adopted**. Superseded: missingness already means unknown; downstream code can assume a per-crop default (e.g. HI from a `PEcAn.data.land::look_up_harvest_index()` lookup) and flag it.
4. ~~`is_establishment` flag for pre-study management events~~ — **not adopted**. Superseded: derivable as `management.date < treatment.start_date`; explicit flag name was ambiguous to read at query time.
5. ~~`study_year` alongside `calendar_year`~~ — **not adopted for this dataset** (Year 0–8 ↔ 2003–2011 is unambiguous from the companion paper). For papers where the calendar year IS missing, a sentinel `0000-MM-DD` date is a cleaner encoding than a parallel `study_year` integer field, since it keeps the partial-date information in the existing `date` column rather than splitting it across two fields.
6. **`replicate_id` / `block`** column in observations — **implemented**. Needed for proper mixed-effects model validation; block is used as the replicate identifier at this site (per the RCBD structure — one plot per treatment per block; `block ≡ replicate ≠ plot`).

---

## Ingestion Decisions and Assumptions

Record of what was ingested, at what resolution, and the decisions made
while doing so. Assumptions here shape how downstream cal/val work should
interpret the workbook rows for this dataset.

**Data ingested:**

- `managements` tab: expanded for Years 0–8 across the 5 observed systems,
  each event carrying `min_date` / `max_date` season bounds only (no
  point-estimate DOYs invented from production norms).
- `observations` tab: Years 2–8 block-level ingested from the *Data in
  Brief* supplemental tables — 180 SOC stock + 180 total N + 180
  nitrate-N rows.
- Harvest indices captured on the harvest managements rows as
  HI = 0.26 (romaine hearts) and HI = 0.24 (broccoli), per White et al.
  (2020b) citing Brennan, unpublished.
- Quadrennial cover crop years fixed at Years 3 and 7 (fall 2006 and
  fall 2010), confirmed from the companion paper.

**Assumptions made:**

- Block ≡ replicate at this site (RCBD, 4 blocks, one plot per treatment
  per block); block number used as the replicate identifier.
- Compost C:N ratio (mean 22, range 18–28) is captured at the source
  level, not per-year — the paper reports only the 4-of-8-year aggregate
  and per-year values are not recoverable from the publication.
- Pre-treatment 2003 establishment compost (22 Mg ha⁻¹ wet weight) is
  materially load-bearing for the Year 0 → Year 1 SOC decline (per
  companion paper: spading + tillage breaking macroaggregates + exposing
  protected SOC) — retained in `managements` and flagged as
  pre-establishment via `management.date < treatment.start_date`, not via
  a separate boolean.

**Open follow-ups (do not block this ingestion):**

- Pull Years 0–1 block-level rows from USDA Ag Data Commons — currently
  treatment-mean rows from PLoS ONE S1 (see *How to Fill the Remaining
  SOC Values* below).
- Expand the single 2003 pre-establishment compost row into per-treatment
  rows (see Challenge #6 and PR #5 review — 5 vs. 8 system reconciliation
  pending @dlebauer's call).
- Add `use_for_calibration` column to `observations` and populate
  `treatment_pairs` (per divine7022's PR #5 review).

## How to Fill the Remaining Years 0–1 SOC Values

The two data sources are **not at the same resolution** — one is a
summary of the other:

- **USDA Ag Data Commons** — *primary data*. All 4 block-level
  measurements per `(system, year)`. The experiment uses a randomized
  complete block design with 4 blocks, and each treatment appears once
  per block, so **block-level = per-replicate resolution at this site**.
  Includes SOC concentration, bulk density, total N, POXC, and yields.
- **PLoS ONE Supplementary Table S1** — *summaries* of the primary data:
  treatment means + standard errors per `(system, year)`, computed across
  the 4 blocks. No information in S1 that is not derivable from the AgDC
  primary data.

**Default ingestion path: always pull from the primary archive when one
exists.** For this dataset that means Ag Data Commons:

1. Open the dataset landing page:
   <https://data.nal.usda.gov/dataset/data-soil-carbon-and-nitrogen-data-during-eight-years-cover-crop-and-compost-treatments-organic-vegetable-production>
   (canonical DOI is in the workbook's `citations` tab)
2. Pull block-level SOC + bulk density + total N values
3. Match by `(system, block, year)` for full per-replicate rows in the
   workbook's `observations` tab

PLoS ONE S1 is a useful cross-check (do our block-means line up with
their reported treatment means?) but should not be used as the primary
fill source if AgDC is reachable.

Once filled, set `fill_status` to `FILLED_AG_DATA_COMMONS`. Use
`FILLED_S1_TABLE` only for treatment-mean rows where block-level data
genuinely is not available (Years 0–1 in the current workbook).

**Protocol note (apply to future ingestions):** when a paper has a
companion data publication or open archive, treat that as the
authoritative source. Tables and supplementary files in the analysis
paper are summary statistics over the same data — useful for
verification, not a substitute for replicate-level ingestion.

> Note: an earlier draft listed `github.com/swood-ecology/socs` as a third
> option. That repo is analysis code, not a separate data archive — the
> underlying observations are White et al. (2020a / b). Useful as a
> reference if we write our own parse script, but should not be cited as a
> data source.

---

## Citations

- **White et al. (2020a)** — White KE, Brennan EB, Cavigelli MA. Soil
  carbon and nitrogen data during eight years of cover crop and compost
  treatments in organic vegetable production. *Data in Brief* 33, 106481.
  <https://doi.org/10.1016/j.dib.2020.106481>
- **White et al. (2020b)** — White KE, Brennan EB, Cavigelli MA. Companion
  PLoS ONE paper reporting the same multi-year cover crop / compost
  experiment (treatment means + SE in Supplementary Table S1).
  <https://doi.org/10.1371/journal.pone.0228677>
- **USDA Ag Data Commons** — long-term archive for block-level SOC and
  bulk density values from the same Salinas experiment. Landing page:
  <https://data.nal.usda.gov/dataset/data-soil-carbon-and-nitrogen-data-during-eight-years-cover-crop-and-compost-treatments-organic-vegetable-production>.
  Canonical DOI recorded in the workbook's `citations` tab (the
  `10.15482/USDA.ADC/1503927` identifier in earlier drafts did not
  resolve — please defer to the citations tab as the source of truth).

Full citation metadata also lives in the workbook's `citations` tab.
