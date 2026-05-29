# Data Entry Report: White/Salinas Cover Crop + Compost Dataset

**Dataset:** White KE, Brennan EB, Cavigelli MA (2020). Soil carbon and nitrogen data during
eight years of cover crop and compost treatments in organic vegetable production.
*Data in Brief* 33, 106481. https://doi.org/10.1016/j.dib.2020.106481

**Entered by:** AritraDey-Dev  
**Entry date:** 2026-04-10  
**Related issue:** ccmmf/organization#221

---

## Files Created

| File | Status | Source |
|------|--------|--------|
| `citation.csv` | Complete | Paper metadata |
| `site.csv` | Complete | Paper text (coordinates from 36°37'N, 121°32'W) |
| `treatments.csv` | Complete | Paper Table 1 / methods |
| `management_events.csv` | Partial — Year 1 complete, Years 2-8 need expansion | Paper methods (seasonal description) |
| `observations_soc.csv` | Structure complete, values need filling | USDA Ag Data Commons download required |

---

## Data Entry Method

### Site and Treatment Metadata
Extracted directly from paper text and methods section. All 5 treatment systems
are fully documented in the paper. No ambiguity.

### Management Events
The paper describes management as seasonal windows (e.g., "cover crops planted
in fall, incorporated in late winter/early spring"). **No exact calendar dates
are provided for any event in any year.**

Approach taken:
- Assigned approximate DOY based on typical Salinas Valley vegetable production calendar
- Flagged all events with `exact_date_known = FALSE`
- Used the following DOY estimates:
  - Cover crop planting: DOY 288 (mid-October)
  - Spader tillage / cover crop incorporation: DOY 46 (mid-February)
  - Compost application (spring, before lettuce): DOY 121 (May 1)
  - Lettuce transplanting: DOY 135 (May 15)
  - Lettuce harvest: DOY 182 (July 1)
  - Broccoli transplanting: DOY 196 (July 15)
  - Broccoli harvest: DOY 274 (October 1)
  - Compost application (fall, before cover crop): DOY 278 (October 5)
  - Subsoiling: DOY 283 (October 10)

Year 1 (2003 planting → 2004 vegetables) is fully expanded in `management_events.csv`.
Years 2-8 follow the identical cycle; quadrennial systems (sys1, sys2) omit
cover crop planting in years 2, 3, 4, 6, 7, 8 and add it back in year 5.

### SOC Observations
The paper reports annual SOC stock measurements (0–30 cm, Mg ha⁻¹) for Years 0–8
across 5 treatments × 4 replicates = 20 plot-years per year × 9 time points = **180 block-level
SOC rows** (each variable). POXC (labile C) measured at Years 0, 6, 8 only.
Bulk density measured at Years 3 and 7 only.

**Data source — Zotero supplemental** (per @dlebauer's pointer to
https://www.zotero.org/groups/5606810/ccmmf/items/U8UG83C5): the block-level values
were pulled from White et al. 2020 *Data in Brief* Supplemental Tables.xlsx
(Zotero storage `5CB4ZEF8`, Tables 1–4). The original Zotero copy includes:

- 180 block-level SOC stock + concentration rows (`FILLED_ZOTERO_XLSX`)
- 180 block-level Total N stock + concentration rows
- 180 nitrate-N rows (new variable `nitrate_N_mg_kg`)
- POXC, C/N inputs, and yields

These are now in the active MAGiC cal/val workbook
(`White_Salinas_2020_filled.xlsx`) under the `observations` tab with
`observation_level=replicate, n=1`.

The USDA Ag Data Commons archive (doi:10.15482/USDA.ADC/1503927) remains the
canonical long-term source for Years 0–1 block-level SOC, which are still pooled
treatment_mean rows in the workbook pending an AgDC pull.

---

## Challenges and Assumptions

### 1. No exact event dates
**Challenge:** The paper provides only seasonal windows (fall, spring, summer) for all
management events. No day-month-year dates are given for any planting, harvest, tillage,
or compost event in any year.

**Assumption:** DOY estimates assigned based on Salinas Valley vegetable production norms
(see table above). These could be off by ±2-4 weeks.

**Schema suggestion:** Add a `date_precision` field with values like
`exact | month | season | year | inferred` to formally capture this uncertainty.

### 2. Fertilization: not applicable (organic system)
**Challenge:** Issue #215 lists fertilization date and N rate as required management fields.
This is an organic system — no synthetic fertilizer was applied.

**Assumption:** Compost is treated as the organic amendment / N source. Compost N content
(15 g N/kg, applied at 7.6 Mg ha⁻¹) is recorded in `management_events.csv` as
`event_type = compost_application`.

**Schema suggestion:** The current schema conflates compost with fertilization. Need either:
- A dedicated `organic_amendment` event type with `C_rate` and `N_rate` fields, or
- A `fertilization` event type that accepts `form = organic` with `material_type` subfield.

### 3. Harvest component not specified
**Challenge:** The paper does not specify what fraction of broccoli or lettuce biomass was
removed vs. left in field. Issue #215 requires harvest component (grain/fruit/straw/wood/leaf).

**Assumption:** For lettuce: harvested component = head (leaves); stover left in field.
For broccoli: harvested component = head (floret); stover left in field.
These are standard commercial practices for these crops but not stated explicitly.

**Flag:** `exact_date_known = FALSE` used as proxy; a separate `biomass_removal_known` flag
would be more precise.

### 4. Quadrennial cover crop schedule
**Challenge:** The paper says cover crops are planted every 4th winter in sys1 and sys2.

**Confirmed from companion paper (PMC7004306):** Quadrennial cover crop planted in
**Years 4 and 8** (fall 2006 and fall 2010), not Years 1 and 5 as initially assumed.
Year 0 pre-study (fall 2003) all systems received legume-rye; the 4-year cycle then
counts from there, making next quadrennial = fall 2006 = Year 4 of the veg seasons.

### 5. GHG flux measurements absent
**Challenge:** Issue #215 lists GHG flux as a validation target. This dataset contains
no N₂O, CH₄, or CO₂ measurements — explicitly noted as a limitation in the paper.

**Impact:** This dataset can only validate SOC dynamics, not GHG fluxes. It remains
valuable for soil carbon calibration.

### 6. Pre-study 2003 management
**Challenge:** Pre-study establishment in 2003 included a one-time compost application
at 22 Mg ha⁻¹ (wet weight) — much higher than the subsequent annual rate and applied
to ALL systems. This affects Year 0 baseline SOC.

**Assumption:** Included as `study_year = 0`, `treatment_id = all_systems` with a note.
The template schema does not currently have a mechanism for pre-treatment establishment events.

**Schema suggestion:** Add an `is_establishment` boolean or `phase = establishment | treatment`
field to distinguish pre-study conditioning from the treatment period.

---

## Suggested Schema Changes

Based on this ingestion, the following additions to the template would improve usability:

1. **`date_precision` field** in management_events — `exact | month | season | inferred`
2. **`organic_amendment` event type** separate from `fertilization`, with `C_Mg_ha` and `N_Mg_ha` subfields
3. **`harvest_component_known` boolean** in harvest events
4. **`is_establishment` flag** for pre-study management events
5. **`study_year` alongside `calendar_year`** — many papers report Year 0-8 without clear calendar year mapping
6. **`replicate_id` or `block`** column in observations — needed for proper mixed-effects model validation

---

## What Is Needed to Complete This Entry

- [ ] Fill `observations_soc.csv` Years 2-8 block-level SOC values — see instructions below
- [x] Expand `management_events.csv` for Years 2-8 — complete
- [x] Confirm quadrennial cover crop years — confirmed as Years 4 and 8 from companion paper
- [x] Harvest component — confirmed as standard practice: lettuce=head, broccoli=floret; stover left in field. No biomass amounts reported in paper.
- [x] Extend `observations_soc.csv` rows for all Years 0-8, all 5 treatments, all 4 blocks — complete (180 rows; values need filling)

## How to Fill the Remaining SOC Values

The block-level per-year SOC values are in **one of two places**:

**Option A — PLoS ONE Supplementary Table S1** (treatment means + SE only):
1. Go to https://doi.org/10.1371/journal.pone.0228677
2. Download the Supporting Information file (S1 Table)
3. Match by system number + year → fill `SOC_stock_Mg_ha` and `total_N_stock_Mg_ha` at the treatment-mean level

**Option B — USDA Ag Data Commons (block-level, preferred)**:
1. Access the canonical archive at doi:10.15482/USDA.ADC/1503927
2. Pull block-level SOC + bulk density values
3. Match by system + block + year for full per-replicate resolution

Once filled, set `fill_status` to `FILLED_S1_TABLE` (Option A) or `FILLED_AG_DATA_COMMONS` (Option B).

> Note: an earlier draft listed `github.com/swood-ecology/socs` as a third option.
> That repo is analysis code (the
> `data-analysis.Rmd` SOC-stock formula `pom.stock = (POM C * blkden * 30)/10`),
> not a separate data archive — the underlying observations all live in Ag Data
> Commons (doi above). The repo is useful as a reference if we write our own
> parse script, but should not be cited as a data source.
