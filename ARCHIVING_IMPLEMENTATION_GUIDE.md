# 📘 ABAP Archiving Implementation Guide

**Version:** 1.0  
**Last Updated:** March 11, 2026  
**Author:** Based on ZCL_MM_FLETFACT_SERVICE implementation experience  

---

## 🎯 Purpose & Scope

### What This Guide Covers
This guide provides a **reusable implementation pattern** for incorporating SAP archiving support into existing ABAP solutions. It documents proven strategies, technical patterns, and critical lessons learned from real-world implementations.

### Applicable Scenarios
- ✅ Migration from SAP Query/Infoset to ABAP program + service class
- ✅ Existing ABAP reports that need archive reading capability
- ✅ Service classes transitioning from BD-only to hybrid BD + Archive
- ✅ Data access redesign to support historical data retrieval
- ✅ Performance optimization of SELECT-heavy legacy code

### What This Guide Does NOT Cover
- ❌ Archive configuration (archiving objects, retention policies, SARA setup)
- ❌ Performance tuning of archiving runs themselves
- ❌ Custom archiving object development
- ❌ Legal/compliance requirements for data archiving

---

## 🚦 When to Move Away from SAP Query

### Indicators That SAP Query Is No Longer Sufficient

#### Technical Limitations
1. **No archiving support in infosets**
   - SAP Query does not handle LEFT OUTER JOINs gracefully for archived data
   - Cannot implement conditional archive reading
   - No control over gating logic (when to consult archive)

2. **Performance issues**
   - SELECT SINGLE in loop patterns (O(n²) complexity)
   - Cannot implement prefetch strategies
   - Limited control over join order

3. **Complex calculation requirements**
   - Multi-step transformations (prorrateo, rounding, enrichment)
   - Conditional logic based on business rules
   - Need for deterministic reverse mappings

4. **Testability**
   - Cannot unit test SAP Query logic
   - Difficult to validate edge cases
   - No automated regression testing

#### Business Drivers
- **Regulatory requirements:** Need to report on data >2-3 years old
- **Audit trails:** Must prove calculation correctness for historical periods
- **Performance degradation:** Query runtime increases as BD data ages
- **Maintenance burden:** Complex infosets become unmaintainable

### Migration Justification Template

**Recommended approach for stakeholder communication:**

```
Current state: SAP Query [QUERY_NAME] with infoset [INFOSET_NAME]
Problem: Cannot access archived data for periods before [CUTOFF_DATE]
Impact: Missing [X]% of historical data, reports incomplete
Proposed solution: Migrate to ABAP program + service class with archiving support
Effort: [X] days development + [Y] days testing
Benefit: Complete historical reporting + improved performance + testability
```

---

## 🏗️ Recommended Target Architecture

### 3-Layer Pattern

```
┌─────────────────────────────────────────────────────────┐
│  REPORT (Z*_R_*)                                        │
│  - Selection screen (blocks, p_hist checkbox)           │
│  - Parameter mapping to ty_screen                       │
│  - Service instantiation                                │
│  - ALV/SALV display                                     │
└─────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│  SERVICE CLASS (ZCL_*_SERVICE)                          │
│  - start() orchestrator                                 │
│  - get_data() base SELECT (BD read)                     │
│  - process_*() transformation methods                   │
│  - enrich_*() enrichment methods (BD prefetch)          │
│  - enrich_*_from_archive() archive hooks (best-effort)  │
│  - fill_*_from_archive() archive retrieval (fallback)   │
└─────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│  ARCHIVING FRAMEWORK (ZCL_CA_ARCHIVING_*)               │
│  - Factory (object instantiation)                       │
│  - Controller (offset generation)                       │
│  - Query Controller (filter construction)               │
└─────────────────────────────────────────────────────────┘
```

### Naming Conventions (Proven Pattern)

#### Public Methods
- `start(is_screen) → rt_data` — Orchestrator method (entry point)
- `get_data(...) → rt_data` — Base SELECT from BD with LEFT OUTER JOINs

#### Protected Methods (for testability)
- `build_datetime_range(...)` — Convert period to timestamp range
- `determine_transport_parameters(...)` — Map business flags to technical params
- `needs_archive(iv_cutoff, iv_pperiodo) → rv_needs` — Temporal gating logic

#### Private Methods (processing pipeline)
- `process_initial_calculation(...)` — First transformation pass
- `distribute_by_trip(...)` — Distribution/proration logic
- `round_by_order(...)` — Rounding/aggregation logic
- `enrich_pricing_data(iv_use_archive, CHANGING ct_data)` — BD prefetch + archive fallback

#### Private Methods (archiving infrastructure)
- `enrich_vbap_from_archive(CHANGING ct_data)` — Complete missing BD fields (best-effort)
- `fill_pricing_from_archive(it_unique_keys, CHANGING ct_pricing)` — Reverse mapping for complex structures
- `build_archive_filters_*(ir_vbeln, ...) → rt_filters` — Filter construction
- `get_*_from_archive(it_filters) → et_*` — Archive reading

### Method Visibility Strategy
- **PUBLIC:** Only orchestrator and main entry point
- **PROTECTED:** Methods needed for unit testing (deterministic logic, no DB/archive dependencies)
- **PRIVATE:** All implementation details

**Lesson learned:** Moving 3-5 key methods from PRIVATE to PROTECTED enables effective unit testing without exposing internal APIs.

---

## 🔁 General Archiving Design Pattern

### Triple Gating Mechanism

**Never consult archive unconditionally.** Use triple gate:

```abap
METHOD start.
  DATA lv_cutoff TYPE sy-datum.
  DATA lv_use_archive TYPE abap_bool.

  " 1. Get cutoff date from archiving framework
  lv_cutoff = zcl_ca_archiving_utility=>get_cutoff_date( ).

  " 2. Triple gate: user flag AND cutoff valid AND period needs archive
  lv_use_archive = xsdbool( is_screen-p_hist = abap_true AND
                            lv_cutoff IS NOT INITIAL AND
                            needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true ).

  " 3. Execute base SELECT (always from BD)
  rt_data = get_data(...).

  " 4. Conditionally enrich from archive
  IF lv_use_archive = abap_true.
    enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
  ENDIF.

  " 5. Continue processing...
  process_initial_calculation(...).
  enrich_pricing_data( EXPORTING iv_use_archive = lv_use_archive
                       CHANGING  ct_data = rt_data ).
ENDMETHOD.
```

### needs_archive() Logic — Temporal Criterion

**Rule:** Archive is needed if **first day of period <= cutoff date**

```abap
METHOD needs_archive.
  DATA lv_dinicio TYPE sy-datum.
  
  " Convert YYYYMM to YYYYMM01
  CONCATENATE iv_pperiodo '01' INTO lv_dinicio.
  
  " Compare: if period start <= cutoff → needs archive
  rv_needs = xsdbool( lv_dinicio <= iv_cutoff ).
ENDMETHOD.
```

**Rationale:** Avoids arbitrary heuristics. Cutoff is the authoritative boundary set by archiving runs.

### Hybrid BD + Archive Strategy

#### Pattern 1: Enrich (Best-Effort Completion)
**When:** Base SELECT brings rows with some fields initial (archived data)  
**Goal:** Fill missing fields without changing row count  
**Error handling:** TRY-CATCH, continue if archive fails

```abap
METHOD enrich_vbap_from_archive.
  " 1. Identify rows with initial ARKTX/NETWR
  " 2. Build ranges for unique keys (VBELN, MATNR)
  " 3. Read VBAP from archive
  " 4. Merge: fill only if initial (no overwrite)
  " 5. TRY-CATCH: archive failure is non-critical
ENDMETHOD.
```

#### Pattern 2: Fill (Complex Reverse Mapping)
**When:** Prefetch from BD misses some keys (historical documents)  
**Goal:** Complete missing entries via reverse lookup  
**Error handling:** TRY-CATCH, continue if archive fails  
**Key characteristic:** Respects "first occurrence wins" semantic

```abap
METHOD fill_pricing_from_archive.
  " Only called if iv_use_archive = abap_true
  " Paso 1: Detect missing keys (no ZPB2/ZR05 in ct_pricing)
  " Paso 2: Build ranges lr_vbeln_miss, lr_matnr_miss
  " Paso 3: Read VBAP → build deterministic map (vbeln+posnr→matnr)
  " Paso 4: Read VBAK → build deterministic map (knumv→vbeln)
  " Paso 5: Read KONV (filter by VBELN indexable)
  " Paso 6: Post-filter KONV in memory (KNUMV/KPOSN/KSCHL)
  " Paso 7: Reverse map → INSERT into ct_pricing (hashed, first wins)
ENDMETHOD.
```

### Decision Tree: When to Use Each Pattern

```
Does base SELECT return rows with missing fields?
├─ YES → Use "enrich" pattern (complete existing rows)
└─ NO → Does prefetch miss some keys?
    ├─ YES → Use "fill" pattern (add missing entries)
    └─ NO → Archive not needed for this method
```

---

## 🗂️ Data Access Strategy

### Analyzing Existing SELECTs

**Checklist for each SELECT in legacy code:**

1. ✅ **Identify key tables:** Which tables are read?
2. ✅ **Check archiving status:** Are any of these tables archived? (use SARI, transaction code)
3. ✅ **Analyze JOINs:** INNER vs LEFT OUTER? Can archived data break joins?
4. ✅ **Identify indexable fields:** Which fields are in infostructure vs catalog only?
5. ✅ **Assess business criticality:** Can report work with partial data or must it be complete?

### INNER JOIN vs LEFT OUTER JOIN

#### When to Change INNER → LEFT OUTER

**Rule:** If **right table** (the one being joined) can be archived AND fields from that table are used for enrichment (not filtering), change to LEFT OUTER JOIN.

**Example from implementation:**
```abap
" Before (INNER JOIN):
SELECT ... FROM ztmt_serfletr01 AS h
  INNER JOIN vbap AS pv ON ...  " ← VBAP archived → 0 rows if archived

" After (LEFT OUTER JOIN):
SELECT ... FROM ztmt_serfletr01 AS h
  LEFT OUTER JOIN vbap AS pv ON ...  " ← Query succeeds even if VBAP archived
```

**When to keep INNER JOIN:**
- Right table is **never archived** (e.g., master data like BUT000, T001)
- Right table fields are **mandatory for business logic** (cannot proceed without them)

#### Pattern for Archive-Tolerant Queries

```abap
" Step 1: Base SELECT with LEFT OUTER JOIN on archivable tables
SELECT @iv_tipotrans,
       h~tor_id,          " Always from BD (header)
       pv~vbeln,          " May be initial (archived)
       pv~netwr,          " May be initial (archived)
       ...
  FROM ztmt_serfletr01 AS h
  INNER JOIN ztmt_serfletr02 AS p ON ...     " ← Not archived
  INNER JOIN but000 AS c ON ...              " ← Master data
  LEFT OUTER JOIN vbap AS pv ON ...          " ← ARCHIVED
  WHERE ...
  INTO TABLE @rt_data.

" Step 2: Conditionally complete archived fields
IF lv_use_archive = abap_true.
  enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
ENDIF.
```

### Prefetch Strategy for Performance

**Problem:** SELECT SINGLE in loop → O(n²) complexity

**Solution:** Prefetch + hashed lookup → O(n)

```abap
METHOD enrich_pricing_data.
  DATA lt_unique_keys TYPE tt_pricing_keys.
  DATA lt_pricing_temp TYPE STANDARD TABLE OF ty_pricing.
  DATA lt_pricing TYPE tt_pricing. " ← HASHED TABLE

  " Step 1: Extract unique (vbeln, matnr) from ct_data
  lt_unique_keys = VALUE #( FOR <wa> IN ct_data
                            ( vbeln = <wa>-numeropedido
                              matnr = <wa>-materialfactura ) ).
  SORT lt_unique_keys BY vbeln matnr.
  DELETE ADJACENT DUPLICATES FROM lt_unique_keys.

  " Step 2: Single SELECT with FOR ALL ENTRIES
  CHECK lt_unique_keys IS NOT INITIAL.
  SELECT vbeln, matnr, kschl, kbetr
    FROM prcd_elements
    FOR ALL ENTRIES IN @lt_unique_keys
    WHERE vbeln = @lt_unique_keys-vbeln
      AND matnr = @lt_unique_keys-matnr
      AND kschl IN ('ZPB2', 'ZR05')
    INTO TABLE @lt_pricing_temp.

  " Step 3: Populate hashed table (first occurrence wins)
  LOOP AT lt_pricing_temp ASSIGNING FIELD-SYMBOL(<fs_temp>).
    INSERT VALUE ty_pricing( vbeln = <fs_temp>-vbeln
                             matnr = <fs_temp>-matnr
                             kschl = <fs_temp>-kschl
                             kbetr = <fs_temp>-kbetr )
           INTO TABLE lt_pricing. " ← Hashed INSERT (no duplicates)
  ENDLOOP.

  " Step 4: Loop with READ TABLE (O(1) lookup)
  LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs_data>).
    READ TABLE lt_pricing INTO DATA(ls_zpb2)
      WITH KEY vbeln = <fs_data>-numeropedido
               matnr = <fs_data>-materialfactura
               kschl = 'ZPB2'.
    IF sy-subrc = 0.
      <fs_data>-valorfleteo = ls_zpb2-kbetr.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

### Coherent Archive Access for Related Tables

**Anti-pattern:** Mix BD and archive sources for tables from the same business document

**Lesson learned from implementation:**
- ❌ **Wrong:** Read VBAK from BD, VBAP from archive, KONV from BD → inconsistent document state
- ✅ **Correct:** Read VBAK + VBAP + KONV all from archive (coherent historical snapshot)

**Example (pricing historical):**
```abap
" All tables from same archived document
lt_vbap = get_vbap_from_archive( lt_filters_vbap ).  " ← Archived
lt_vbak = get_vbak_from_archive( lt_filters_vbak ).  " ← Archived
lt_konv = get_konv_from_archive( lt_filters_konv ).  " ← Archived

" Build reverse maps from archived data
LOOP AT lt_vbap INTO ls_vbap.
  INSERT VALUE #( vbeln = ls_vbap-vbeln
                  posnr = ls_vbap-posnr
                  matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr.
ENDLOOP.
```

---

## 📦 Archive Retrieval Pattern

### Factory Pattern Usage

```abap
DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
DATA lt_vbap_arch TYPE STANDARD TABLE OF vbap.
DATA lt_filters TYPE ztt_ca_archiving.

" Step 1: Build filters (see next section)
lt_filters = build_archive_filters_vbap( ir_vbeln = lr_vbeln
                                         ir_matnr = lr_matnr ).

" Step 2: Instantiate factory
lo_factory = NEW zcl_ca_archiving_factory( ).

" Step 3: Get instance with filters
lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbap
                          it_filter_options = lt_filters ).

" Step 4: Extract data
lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbap
                      IMPORTING et_data = lt_vbap_arch ).
```

### Filter Construction Pattern

**Standard pattern for all archive reads:**

```abap
METHOD build_archive_filters_vbap.
  DATA lr_vbeln TYPE /iwbep/t_cod_select_options.
  DATA lr_matnr TYPE /iwbep/t_cod_select_options.

  " Convert ABAP ranges to archiving format
  IF ir_vbeln IS NOT INITIAL.
    MOVE-CORRESPONDING ir_vbeln TO lr_vbeln.
  ENDIF.

  IF ir_matnr IS NOT INITIAL.
    MOVE-CORRESPONDING ir_matnr TO lr_matnr.
  ENDIF.

  " Instantiate query controller
  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).

  " Add filters (only if populated)
  IF lr_vbeln IS NOT INITIAL.
    lo_query->add_filter_from_range( iv_name = 'VBELN'
                                     ir_values = lr_vbeln ).
  ENDIF.

  IF lr_matnr IS NOT INITIAL.
    lo_query->add_filter_from_range( iv_name = 'MATNR'
                                     ir_values = lr_matnr ).
  ENDIF.

  " Apply to infostructure
  lo_query->apply_filters_to_str( iv_archiving_str = gc_str_vbap ).

  " Return constructed filters
  rt_filters = lo_query->gt_filter_options.
ENDMETHOD.
```

### Exception Handling Pattern

**All archive reads must be TRY-CATCH (best-effort):**

```abap
METHOD enrich_vbap_from_archive.
  TRY.
      DATA(lt_filters) = build_archive_filters_vbap(...).
      DATA(lt_vbap) = get_vbap_from_archive( lt_filters ).
      
      " Merge logic here...
      
    CATCH zcx_ca_archiving INTO DATA(lx_arch).
      " Log or ignore: archive failure does not abort main calculation
      " Archive read is best-effort, not critical path
  ENDTRY.
ENDMETHOD.
```

**Rationale:** Archive infrastructure may fail (file corruption, permission issues, network problems). Main calculation should continue with partial data.

---

## ⚡ Important Technical Lessons Learned

### Critical Discovery: Offset Generation & Indexable Fields

#### How Archive Reading Works Internally

**Chain of calls:**
```
get_instance(iv_object, it_filters)
  └─> get_archiving_keys(it_filters)
      └─> get_data_keys(it_filters)
          └─> fill_where_clause(it_filters)
              └─> SELECT FROM (infostructure_table) WHERE ...
```

**Key insight from ZCL_CA_ARCHIVING_CTRL→get_data_keys():**

```abap
METHOD get_data_keys.
  " Build dynamic field list from infostructure fields
  lv_fields = 'ARCHIVEKEY, ARCHIVEOFS, field1, field2, ...'.

  " Build dynamic WHERE clause from filters
  lv_where = fill_where_clause( it_filters, iv_archindex, iv_table_name ).

  " Execute query on GENTAB (e.g., SAP_DRB_VBAK_02)
  SELECT (lv_fields)
    FROM (is_struct-gentab)    " ← DYNAMIC TABLE NAME (infostructure!)
    WHERE (lv_where)
    APPENDING CORRESPONDING FIELDS OF TABLE @<lt_keys>.
ENDMETHOD.
```

**🚨 CRITICAL CONSTRAINT:**  
Only fields that **exist in GENTAB** (infostructure table) can generate offsets.  
Fields that exist only in the **catalog** (original table) **DO NOT WORK** for filtering.

#### Verification: SARI Transaction

**How to check which fields are indexable:**

1. Run transaction **SARI** (Archive Information System)
2. Select archiving object (e.g., SD_VBAK)
3. Select infostructure (e.g., SAP_DRB_VBAK_02)
4. Check field lists:
   - **Left panel** ("Campos de estructura info"): Fields in GENTAB → ✅ **INDEXABLE**
   - **Right panel** ("Catálogo"): Fields in original table only → ❌ **NOT INDEXABLE**

**Example for SD_VBAK / SAP_DRB_VBAK_02:**
- ✅ **INDEXABLE:** VBELN, POSNR, MATNR (in infostructure)
- ❌ **NOT INDEXABLE:** KNUMV, KPOSN, KSCHL (catalog only, not in infostructure)

#### Why KONV Filters Don't Generate Offsets

**Problem scenario:**
```abap
" ❌ WRONG: Filtering by catalog-only fields
lo_query->add_filter_from_range( iv_name = 'KNUMV' ir_values = lr_knumv ).
lo_query->add_filter_from_range( iv_name = 'KSCHL' ir_values = lr_kschl ).
```

**What happens internally:**
```sql
-- SELECT FROM SAP_DRB_VBAK_02 
-- WHERE KNUMV = ... AND KSCHL = ...  
-- ← FIELDS NOT FOUND IN TABLE → 0 offsets generated
```

**Root cause:** KNUMV, KPOSN, KSCHL are **catalog fields** (exist in KONV table structure) but are **NOT infostructure fields** (not in SAP_DRB_VBAK_02 GENTAB).

#### Correct 2-Step Pattern for Non-Indexable Fields

**Strategy:** Filter by indexable fields → read full data → post-filter in memory

```abap
METHOD get_konv_from_archive.
  " Step 1: Filter ONLY by indexable fields (VBELN is in infostructure)
  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).
  lo_query->add_filter_from_range( iv_name = 'VBELN'
                                   ir_values = lr_vbeln ).
  lo_query->apply_filters_to_str( gc_str_konv ).

  " Step 2: Read full KONV for those VBELNs
  DATA(lo_factory) = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_konv
                            it_filter_options = lo_query->gt_filter_options ).
  lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_konv
                        IMPORTING et_data = et_konv ).
ENDMETHOD.

METHOD fill_pricing_from_archive.
  " Step 3: Post-filter in memory by non-indexable fields
  DATA(lt_konv) = get_konv_from_archive( lr_vbeln ).
  
  " Filter by KNUMV, KPOSN, KSCHL in memory
  LOOP AT lt_konv INTO DATA(ls_konv)
    WHERE knumv IN lr_knumv
      AND kposn IN lr_kposn
      AND kschl IN lr_kschl.
    " Process filtered record...
  ENDLOOP.
ENDMETHOD.
```

### Deterministic Reverse Mapping

**Problem:** Archive data often requires reverse lookups (KONV → VBELN → MATNR)

**Anti-pattern:** Ad-hoc lookups with READ TABLE in nested loops → O(n³)

**Solution:** Build hashed intermediate maps once → O(n)

```abap
" Paso 3: Build deterministic map (VBELN + POSNR → MATNR)
DATA lt_position_to_matnr TYPE tt_position_to_matnr. " ← HASHED
LOOP AT lt_vbap INTO DATA(ls_vbap).
  INSERT VALUE #( vbeln = ls_vbap-vbeln
                  posnr = ls_vbap-posnr
                  matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr. " ← Hashed insert O(1)
ENDLOOP.

" Paso 4: Build deterministic map (KNUMV → VBELN)
DATA lt_knumv_to_vbeln TYPE tt_knumv_to_vbeln. " ← HASHED
LOOP AT lt_vbak INTO DATA(ls_vbak).
  INSERT VALUE #( knumv = ls_vbak-knumv
                  vbeln = ls_vbak-vbeln )
         INTO TABLE lt_knumv_to_vbeln. " ← Hashed insert O(1)
ENDLOOP.

" Paso 7: Reverse map KONV → pricing
LOOP AT lt_konv_filtered ASSIGNING FIELD-SYMBOL(<fs_konv>).
  " Lookup 1: KNUMV → VBELN (O(1))
  READ TABLE lt_knumv_to_vbeln INTO DATA(ls_knumv_map)
    WITH KEY knumv = <fs_konv>-knumv.
  CHECK sy-subrc = 0.

  " Lookup 2: (VBELN, POSNR) → MATNR (O(1))
  READ TABLE lt_position_to_matnr INTO DATA(ls_position_map)
    WITH KEY vbeln = ls_knumv_map-vbeln
             posnr = <fs_konv>-kposn.
  CHECK sy-subrc = 0.

  " Lookup 3: Insert pricing (hashed, first wins)
  INSERT VALUE ty_pricing( vbeln = ls_knumv_map-vbeln
                           matnr = ls_position_map-matnr
                           kschl = <fs_konv>-kschl
                           kbetr = <fs_konv>-kbetr )
         INTO TABLE ct_pricing. " ← HASHED, duplicate ignored
ENDLOOP.
```

**Type definition best practice:**
```abap
TYPES: BEGIN OF ty_knumv_to_vbeln,
         knumv TYPE knumv,
         vbeln TYPE vbeln,
       END OF ty_knumv_to_vbeln.
TYPES tt_knumv_to_vbeln TYPE HASHED TABLE OF ty_knumv_to_vbeln
      WITH UNIQUE KEY knumv.

TYPES: BEGIN OF ty_position_to_matnr,
         vbeln TYPE vbeln,
         posnr TYPE posnr,
         matnr TYPE matnr,
       END OF ty_position_to_matnr.
TYPES tt_position_to_matnr TYPE HASHED TABLE OF ty_position_to_matnr
      WITH UNIQUE KEY vbeln posnr.
```

---

## 🚀 Performance Guidelines

### SELECT Optimization

#### Anti-pattern: SELECT SINGLE in Loop
```abap
" ❌ WRONG: O(n²) complexity
LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs>).
  SELECT SINGLE kbetr FROM prcd_elements
    WHERE vbeln = <fs>-numeropedido
      AND matnr = <fs>-materialfactura
      AND kschl = 'ZPB2'
    INTO <fs>-valorfleteo.
ENDLOOP.
```

#### Pattern: Prefetch + Hashed Lookup
```abap
" ✅ CORRECT: O(n) complexity
" Step 1: Extract unique keys
DATA(lt_keys) = VALUE tt_pricing_keys(
  FOR <wa> IN ct_data ( vbeln = <wa>-numeropedido
                        matnr = <wa>-materialfactura ) ).
SORT lt_keys. DELETE ADJACENT DUPLICATES FROM lt_keys.

" Step 2: Single SELECT with FAE
CHECK lt_keys IS NOT INITIAL.
SELECT vbeln, matnr, kschl, kbetr
  FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
    AND matnr = @lt_keys-matnr
    AND kschl = 'ZPB2'
  INTO TABLE @DATA(lt_pricing_temp).

" Step 3: Populate hashed table
DATA lt_pricing TYPE tt_pricing. " HASHED TABLE
LOOP AT lt_pricing_temp INTO DATA(ls_temp).
  INSERT VALUE #( vbeln = ls_temp-vbeln ... ) INTO TABLE lt_pricing.
ENDLOOP.

" Step 4: Loop with O(1) lookup
LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs>).
  READ TABLE lt_pricing INTO DATA(ls_pricing)
    WITH KEY vbeln = <fs>-numeropedido
             matnr = <fs>-materialfactura
             kschl = 'ZPB2'.
  IF sy-subrc = 0.
    <fs>-valorfleteo = ls_pricing-kbetr.
  ENDIF.
ENDLOOP.
```

### Archive Reading Guards

**Never read archive unconditionally:**

```abap
" ✅ Guard 1: User activation
CHECK is_screen-p_hist = abap_true.

" ✅ Guard 2: Cutoff validity
DATA(lv_cutoff) = zcl_ca_archiving_utility=>get_cutoff_date( ).
CHECK lv_cutoff IS NOT INITIAL.

" ✅ Guard 3: Temporal criterion
DATA(lv_needs) = needs_archive( lv_cutoff, is_screen-pperiodo ).
CHECK lv_needs = abap_true.

" ✅ Guard 4: Missing keys detection
DATA(lt_missing) = detect_missing_keys( ct_data ).
CHECK lt_missing IS NOT INITIAL.

" Only if ALL guards pass → read archive
```

### FOR ALL ENTRIES Protection

**Always guard FOR ALL ENTRIES:**

```abap
" ❌ WRONG: Empty lt_keys causes full table read
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.

" ✅ CORRECT: Guard before SELECT
CHECK lt_keys IS NOT INITIAL.
SELECT vbeln, matnr, kschl, kbetr
  FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

### Hashed Table Usage

**When to use HASHED vs SORTED vs STANDARD:**

- **HASHED:** Lookup by full key (READ TABLE WITH KEY), no duplicates, O(1)
- **SORTED:** Lookup by partial key, BINARY SEARCH, O(log n)
- **STANDARD:** Sequential access, LOOP, O(n)

**Example:**
```abap
TYPES tt_pricing TYPE HASHED TABLE OF ty_pricing
      WITH UNIQUE KEY vbeln matnr kschl.

" O(1) lookup by full key
READ TABLE lt_pricing INTO ls_pricing
  WITH KEY vbeln = '123'
           matnr = 'MAT1'
           kschl = 'ZPB2'.
```

---

## 🧪 Test Strategy

### 3-Tier Test Approach

```
┌────────────────────────────────────────────────────────────┐
│  TIER 1: ABAP Unit Tests                                   │
│  Scope: Deterministic methods (no DB, no archive)          │
│  Examples:                                                  │
│  - needs_archive() logic                                   │
│  - build_datetime_range() conversion                       │
│  - determine_transport_parameters() mapping                │
│  Tools: cl_abap_unit_assert, test helper subclass          │
│  Coverage target: 80%+ for deterministic methods           │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  TIER 2: Technical Integration Tests                       │
│  Scope: Archive retrieval patterns (with real archive)     │
│  Examples:                                                  │
│  - build_archive_filters_*() + get_*_from_archive()        │
│  - Offset generation for specific VBELNs                   │
│  - Post-filter memory logic                                │
│  Tools: Z_TEST_* programs, manual validation               │
│  Coverage target: All archive objects used                 │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  TIER 3: End-to-End Business Validation                    │
│  Scope: Full report execution (BD + archive)               │
│  Examples:                                                  │
│  - Run report for period [X] with p_hist = X               │
│  - Validate calculation formulas                           │
│  - Compare vs original SAP Query (if migrating)            │
│  Tools: Manual execution, user acceptance testing          │
│  Coverage target: Key business scenarios                   │
└────────────────────────────────────────────────────────────┘
```

### What to Unit Test

#### ✅ High-Value Unit Test Candidates
- **Gating logic:** needs_archive() decision tree
- **Temporal conversions:** Period → date → timestamp ranges
- **Parameter mapping:** Business flags → technical parameters
- **Deterministic calculations:** Proration formulas, rounding logic (if no DB dependencies)

#### ❌ Low-Value / Difficult to Unit Test
- Database SELECTs (use integration tests)
- Archive reading (use technical tests)
- Complex enrichment with nested lookups (use integration tests)
- Methods with unavoidable DB dependencies

### Test Helper Pattern (for Protected Methods)

```abap
" Test include (.testclasses.abap)
CLASS lcl_test_helper DEFINITION INHERITING FROM zcl_mm_fletfact_service
  FOR TESTING CREATE PUBLIC.

  PUBLIC SECTION.
    " Wrapper públicos para métodos PROTECTED
    METHODS test_needs_archive
      IMPORTING iv_cutoff TYPE sy-datum
                iv_pperiodo TYPE spmon
      RETURNING VALUE(rv_needs) TYPE abap_bool.

    METHODS test_build_datetime_range
      IMPORTING iv_pperiodo TYPE spmon
      EXPORTING ev_dinicio TYPE sy-datum
                ev_dfin TYPE sy-datum
                er_datetime TYPE tr_datetime.
ENDCLASS.

CLASS lcl_test_helper IMPLEMENTATION.
  METHOD test_needs_archive.
    rv_needs = needs_archive( iv_cutoff = iv_cutoff
                              iv_pperiodo = iv_pperiodo ).
  ENDMETHOD.

  METHOD test_build_datetime_range.
    build_datetime_range( EXPORTING iv_pperiodo = iv_pperiodo
                          IMPORTING ev_dinicio = ev_dinicio
                                    ev_dfin = ev_dfin
                                    er_datetime = er_datetime ).
  ENDMETHOD.
ENDCLASS.
```

**Why this pattern:**
- Cannot access PROTECTED methods from test class directly
- Inheritance allows access via public wrappers
- No contamination of production class PUBLIC API

### Integration Test Pattern (Z_TEST_* Programs)

**Purpose:** Validate archive retrieval with real data

**Structure:**
```abap
REPORT z_test_sd_vbak_pricing_arch.

PARAMETERS: p_vbeln TYPE vbeln OBLIGATORY.

START-OF-SELECTION.
  " 1. Build filters
  DATA(lr_vbeln) = VALUE /iwbep/t_cod_select_options(
    ( sign = 'I' option = 'EQ' low = p_vbeln ) ).

  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).
  lo_query->add_filter_from_range( iv_name = 'VBELN'
                                   ir_values = lr_vbeln ).
  lo_query->apply_filters_to_str( 'SAP_DRB_VBAK_02' ).

  " 2. Read VBAK
  DATA(lo_factory) = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbak
                            it_filter_options = lo_query->gt_filter_options ).
  lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbak
                        IMPORTING et_data = DATA(lt_vbak) ).

  " 3. Display results
  cl_demo_output=>display( lt_vbak ).
```

**Validation checklist:**
- ✅ Filters generated correctly?
- ✅ Offsets retrieved?
- ✅ Data extracted matches expectations?
- ✅ Post-filter logic works?

---

## 📋 Migration Checklist

### Phase 1: Analysis & Planning

- [ ] **Identify scope:** Which report/query needs archiving?
- [ ] **Check archiving status:** Which tables are archived? (SARI, TAANA)
- [ ] **Analyze SELECTs:** Document all table accesses in existing code
- [ ] **Identify infostructures:** Which infostructures cover these tables?
- [ ] **Map indexable fields:** For each table, list fields in infostructure vs catalog
- [ ] **Define cutoff strategy:** What cutoff date will be used?
- [ ] **Estimate complexity:** How many tables? How many joins? Complex reverse mappings?
- [ ] **Get stakeholder approval:** Effort estimation, timeline, testing scope

### Phase 2: Architecture Design

- [ ] **Create service class:** ZCL_*_SERVICE with PUBLIC/PROTECTED/PRIVATE sections
- [ ] **Define ty_screen:** Parameter structure (pperiodo, rdfpro/ter/exp, p_hist)
- [ ] **Define tt_result:** Output structure (replicate infoset fields + calculated)
- [ ] **Plan method decomposition:**
  - [ ] start() orchestrator
  - [ ] get_data() base SELECT
  - [ ] process_*() transformation pipeline
  - [ ] enrich_*() BD prefetch methods
  - [ ] enrich_*_from_archive() archive hooks (best-effort)
  - [ ] fill_*_from_archive() archive fallback (complex mapping)
- [ ] **Document gating logic:** Pseudo-code for triple gate (p_hist + cutoff + needs_archive)

### Phase 3: Base Implementation (BD Only)

- [ ] **Migrate base SELECT:** Convert infoset query to get_data() method
- [ ] **Change INNER → LEFT OUTER JOIN:** For archivable tables
- [ ] **Implement transformations:** Port calculation logic to process_*() methods
- [ ] **Implement BD prefetch:** Port enrichment logic to enrich_*() methods (no archive yet)
- [ ] **Create report:** Selection screen + parameter mapping + ALV display
- [ ] **Test BD-only mode:** Validate results match original query for recent data

### Phase 4: Archive Infrastructure

- [ ] **Create protected methods:**
  - [ ] build_datetime_range()
  - [ ] determine_transport_parameters()
  - [ ] needs_archive()
- [ ] **Create archive filter builders:**
  - [ ] build_archive_filters_vbap()
  - [ ] build_archive_filters_vbak()
  - [ ] build_archive_filters_konv() (if needed)
- [ ] **Create archive readers:**
  - [ ] get_vbap_from_archive()
  - [ ] get_vbak_from_archive()
  - [ ] get_konv_from_archive() (if needed)
- [ ] **Add constants:**
  - [ ] gc_str_vbap = 'SAP_DRB_VBAK_02'
  - [ ] gc_str_vbak = 'SAP_DRB_VBAK_02'

### Phase 5: Archive Integration

- [ ] **Implement gating in start():**
  - [ ] Get cutoff: zcl_ca_archiving_utility=>get_cutoff_date()
  - [ ] Triple gate: p_hist + cutoff + needs_archive()
  - [ ] Conditional enrich_*_from_archive() calls
- [ ] **Implement enrich_*_from_archive():**
  - [ ] Detect rows with initial fields
  - [ ] Build ranges for unique keys
  - [ ] Call get_*_from_archive()
  - [ ] Merge: fill only if initial (no overwrite)
  - [ ] TRY-CATCH: best-effort, continue if fails
- [ ] **Implement fill_*_from_archive() (if needed):**
  - [ ] Detect missing keys in prefetch result
  - [ ] Build ranges for missing keys
  - [ ] Read archive data (coherent: all from archive)
  - [ ] Build deterministic reverse maps (HASHED tables)
  - [ ] Reverse map + INSERT (first occurrence wins)
  - [ ] TRY-CATCH: best-effort

### Phase 6: Testing

- [ ] **Unit tests:**
  - [ ] needs_archive() edge cases (before/at/after cutoff)
  - [ ] build_datetime_range() month boundaries
  - [ ] determine_transport_parameters() flag mapping
- [ ] **Integration tests (Z_TEST_* programs):**
  - [ ] Archive retrieval: VBAP, VBAK, KONV
  - [ ] Filter construction: indexable fields only
  - [ ] Offset generation: validate counts
  - [ ] Post-filter logic: catalog fields
- [ ] **End-to-end validation:**
  - [ ] Run report for recent period (BD only): p_hist = ' '
  - [ ] Run report for historical period (BD + archive): p_hist = 'X'
  - [ ] Compare results vs original query (if migrating)
  - [ ] Validate formulas: manual spot checks
  - [ ] Performance benchmark: runtime acceptable?

### Phase 7: Documentation & Deployment

- [ ] **Update technical documentation:**
  - [ ] Method signatures and purposes
  - [ ] Gating logic diagram
  - [ ] Archive retrieval flow
  - [ ] Known limitations
- [ ] **Create user guide:**
  - [ ] When to activate p_hist checkbox
  - [ ] Expected behavior for historical vs recent data
  - [ ] Performance considerations
- [ ] **Transport:**
  - [ ] Service class
  - [ ] Report
  - [ ] Unit tests
  - [ ] Integration tests
  - [ ] Documentation
- [ ] **Post-deployment validation:**
  - [ ] Smoke tests in QA
  - [ ] User acceptance testing
  - [ ] Performance monitoring

---

## ⚠️ Common Pitfalls

### 1. Filtering by Non-Indexable Fields

**Problem:** Using catalog-only fields in archive filters generates 0 offsets

**Example:**
```abap
" ❌ WRONG: KNUMV not in infostructure
lo_query->add_filter_from_range( iv_name = 'KNUMV' ... ).
" → SELECT FROM SAP_DRB_VBAK_02 WHERE KNUMV = ... → Field not found
```

**Solution:** Filter by indexable fields only, post-filter in memory
```abap
" ✅ CORRECT: VBELN in infostructure
lo_query->add_filter_from_range( iv_name = 'VBELN' ... ).
" → SELECT FROM SAP_DRB_VBAK_02 WHERE VBELN = ... → Offsets generated

" Post-filter in memory
LOOP AT lt_konv INTO ls_konv WHERE knumv IN lr_knumv.
```

**How to avoid:** Always check SARI before building filters

### 2. Mixing BD and Archive Sources Inconsistently

**Problem:** Reading related tables from different sources breaks document coherence

**Example:**
```abap
" ❌ WRONG: Inconsistent sources for related tables
SELECT * FROM vbak INTO TABLE lt_vbak WHERE ...  " ← From BD
DATA(lt_vbap) = get_vbap_from_archive( ... ).    " ← From archive
DATA(lt_konv) = get_konv_from_archive( ... ).    " ← From archive
" → VBAK shows current state, VBAP/KONV show historical → mismatch
```

**Solution:** Read all related tables from same source (coherent snapshot)
```abap
" ✅ CORRECT: All from archive for historical documents
DATA(lt_vbak) = get_vbak_from_archive( ... ).    " ← Archive
DATA(lt_vbap) = get_vbap_from_archive( ... ).    " ← Archive
DATA(lt_konv) = get_konv_from_archive( ... ).    " ← Archive
```

### 3. Reading Archive Without Gating

**Problem:** Unconditional archive reads slow down every execution

**Example:**
```abap
" ❌ WRONG: Always reads archive
DATA(lt_vbap) = get_vbap_from_archive( ... ).
```

**Solution:** Triple gating before archive access
```abap
" ✅ CORRECT: Conditional archive read
IF is_screen-p_hist = abap_true AND
   lv_cutoff IS NOT INITIAL AND
   needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true.
  DATA(lt_vbap) = get_vbap_from_archive( ... ).
ENDIF.
```

### 4. SELECT SINGLE in Loop (Not Using Prefetch)

**Problem:** O(n²) complexity degrades performance

**Example:**
```abap
" ❌ WRONG: n database round-trips
LOOP AT ct_data ASSIGNING <fs>.
  SELECT SINGLE kbetr FROM prcd_elements WHERE ... INTO <fs>-price.
ENDLOOP.
```

**Solution:** Prefetch + hashed lookup (O(n))
```abap
" ✅ CORRECT: 1 database round-trip
" Extract unique keys → SELECT FAE → hashed table → loop with READ TABLE
```

### 5. Not Protecting FOR ALL ENTRIES

**Problem:** Empty driver table causes full table read

**Example:**
```abap
" ❌ WRONG: If lt_keys is initial, reads entire table
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

**Solution:** Always guard FAE
```abap
" ✅ CORRECT: Guard prevents full table read
CHECK lt_keys IS NOT INITIAL.
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

### 6. Overwriting Prefetch Results with Archive

**Problem:** Archive data overwrites more recent BD data

**Example:**
```abap
" ❌ WRONG: Archive overwrites BD prefetch
LOOP AT lt_pricing_archive INTO ls_pricing.
  ct_pricing[ vbeln = ls_pricing-vbeln ] = ls_pricing. " ← Overwrites!
ENDLOOP.
```

**Solution:** INSERT into hashed table (first occurrence wins)
```abap
" ✅ CORRECT: Hashed INSERT ignores duplicates
LOOP AT lt_pricing_archive INTO ls_pricing.
  INSERT ls_pricing INTO TABLE ct_pricing. " ← Hashed, no overwrite
ENDLOOP.
```

### 7. Not Handling Archive Exceptions

**Problem:** Archive infrastructure failure aborts entire calculation

**Example:**
```abap
" ❌ WRONG: Exception propagates, calculation aborts
DATA(lt_vbap) = get_vbap_from_archive( ... ). " ← Raises zcx_ca_archiving
```

**Solution:** TRY-CATCH, treat archive as best-effort
```abap
" ✅ CORRECT: Archive failure is non-critical
TRY.
    DATA(lt_vbap) = get_vbap_from_archive( ... ).
  CATCH zcx_ca_archiving.
    " Log or ignore: continue with partial data
ENDTRY.
```

### 8. Changing INNER JOIN Without Handling Nulls

**Problem:** LEFT OUTER JOIN brings null fields, calculations break

**Example:**
```abap
" Changed to LEFT OUTER JOIN
SELECT ... LEFT OUTER JOIN vbap AS pv ON ...

" ❌ WRONG: Calculation fails if pv~netwr is null
<fs>-total = <fs>-quantity * pv~netwr. " ← Null propagation
```

**Solution:** Conditional enrichment from archive
```abap
" Get data with LEFT JOIN (may have nulls)
rt_data = get_data( ... ).

" Conditionally complete from archive
IF lv_use_archive = abap_true.
  enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
ENDIF.

" Guard calculations
IF <fs>-netwr IS NOT INITIAL.
  <fs>-total = <fs>-quantity * <fs>-netwr.
ENDIF.
```

---

## 🎯 Reusable Decision Rules

### Rule 1: When to Change INNER → LEFT OUTER JOIN

**IF** table is archivable **AND** fields are for enrichment (not mandatory filtering)  
**THEN** change INNER JOIN to LEFT OUTER JOIN

**Example:**
- VBAP archivable, NETWR/ARKTX for display → LEFT OUTER JOIN ✅
- BUT000 master data, KUNNR for filtering → INNER JOIN ✅

### Rule 2: When to Extract Archive Method

**IF** archive logic > 50 lines **OR** needs reverse mapping  
**THEN** extract to dedicated private method (fill_*_from_archive)

**Example:**
- Simple field completion (ARKTX, NETWR) → inline in enrich_*_from_archive ✅
- Complex pricing mapping (VBAK→VBAP→KONV) → extract to fill_pricing_from_archive ✅

### Rule 3: When to Use Deterministic Maps

**IF** reverse lookup required (A→B, B→C, need A→C)  
**THEN** build intermediate hashed maps (one per relationship)

**Example:**
- KONV (has KNUMV+KPOSN) → need (VBELN+MATNR)
- Build: KNUMV→VBELN map (from VBAK) + (VBELN+POSNR)→MATNR map (from VBAP)

### Rule 4: When to Move Methods to PROTECTED

**IF** method is deterministic (no DB, no archive) **AND** valuable for unit tests  
**THEN** move from PRIVATE to PROTECTED

**Example:**
- needs_archive() → deterministic, testable → PROTECTED ✅
- get_vbap_from_archive() → archive dependency, integration test → PRIVATE ✅

### Rule 5: When to Use Enrich vs Fill

**IF** base SELECT returns rows with some fields initial  
**THEN** enrich_*_from_archive (complete existing rows)

**IF** prefetch misses some keys entirely  
**THEN** fill_*_from_archive (add missing entries)

### Rule 6: When Archive Read Is Best-Effort

**IF** main calculation can proceed with partial data  
**THEN** TRY-CATCH archive reads, continue on exception

**IF** archive data is mandatory for correctness  
**THEN** propagate exception, abort calculation

**Example:**
- ARKTX display field missing → best-effort (show blank) ✅
- NETWR for invoice total → mandatory (abort if missing) ⚠️

### Rule 7: When to Optimize with Prefetch

**IF** SELECT SINGLE in loop **AND** unique keys < 1000  
**THEN** prefetch with FOR ALL ENTRIES + hashed lookup

**IF** unique keys > 10,000  
**THEN** consider chunking or range-based SELECT

### Rule 8: When to Write Unit Tests

**IF** method is deterministic (no dependencies) **AND** business-critical  
**THEN** write ABAP Unit tests

**IF** method has DB/archive dependencies  
**THEN** write integration tests (Z_TEST_* programs)

**Example:**
- needs_archive() → unit test ✅
- get_vbap_from_archive() → integration test ✅

### Rule 9: When to Post-Filter in Memory

**IF** filter field is NOT in infostructure (catalog only)  
**THEN** filter by indexable field → post-filter in memory

**How to check:** SARI transaction → infostructure field list

### Rule 10: When to Prioritize Archive Support

**IF** cutoff date < 18 months ago **AND** users need historical data  
**THEN** archiving support is HIGH priority

**IF** cutoff date > 5 years ago **AND** historical queries rare  
**THEN** archiving support is LOW priority (may not justify effort)

---

## 📚 Quick Reference: Code Patterns

### Gating Pattern
```abap
DATA lv_cutoff TYPE sy-datum.
DATA lv_use_archive TYPE abap_bool.

lv_cutoff = zcl_ca_archiving_utility=>get_cutoff_date( ).
lv_use_archive = xsdbool( is_screen-p_hist = abap_true AND
                          lv_cutoff IS NOT INITIAL AND
                          needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true ).

IF lv_use_archive = abap_true.
  " Archive logic here
ENDIF.
```

### Filter Construction Pattern
```abap
METHOD build_archive_filters_vbap.
  DATA lr_vbeln TYPE /iwbep/t_cod_select_options.
  DATA lr_matnr TYPE /iwbep/t_cod_select_options.

  IF ir_vbeln IS NOT INITIAL.
    MOVE-CORRESPONDING ir_vbeln TO lr_vbeln.
  ENDIF.

  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).

  IF lr_vbeln IS NOT INITIAL.
    lo_query->add_filter_from_range( iv_name = 'VBELN' ir_values = lr_vbeln ).
  ENDIF.

  lo_query->apply_filters_to_str( iv_archiving_str = gc_str_vbap ).
  rt_filters = lo_query->gt_filter_options.
ENDMETHOD.
```

### Archive Reading Pattern
```abap
METHOD get_vbap_from_archive.
  DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
  DATA lt_vbap_arch TYPE STANDARD TABLE OF vbap.

  CHECK it_filters IS NOT INITIAL.

  lo_factory = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbap
                            it_filter_options = it_filters ).
  lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbap
                        IMPORTING et_data = lt_vbap_arch ).

  et_vbap = lt_vbap_arch.
ENDMETHOD.
```

### Prefetch + Hashed Lookup Pattern
```abap
" Extract unique keys
DATA(lt_keys) = VALUE tt_pricing_keys(
  FOR <wa> IN ct_data ( vbeln = <wa>-vbeln matnr = <wa>-matnr ) ).
SORT lt_keys. DELETE ADJACENT DUPLICATES FROM lt_keys.

" Prefetch
CHECK lt_keys IS NOT INITIAL.
SELECT vbeln, matnr, kschl, kbetr
  FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
    AND matnr = @lt_keys-matnr
    AND kschl IN ('ZPB2', 'ZR05')
  INTO TABLE @DATA(lt_temp).

" Populate hashed table
DATA lt_pricing TYPE tt_pricing.
LOOP AT lt_temp INTO DATA(ls_temp).
  INSERT VALUE #( vbeln = ls_temp-vbeln ... ) INTO TABLE lt_pricing.
ENDLOOP.

" Loop with O(1) lookup
LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs>).
  READ TABLE lt_pricing INTO DATA(ls_pricing)
    WITH KEY vbeln = <fs>-vbeln matnr = <fs>-matnr kschl = 'ZPB2'.
  IF sy-subrc = 0.
    <fs>-price = ls_pricing-kbetr.
  ENDIF.
ENDLOOP.
```

### Deterministic Reverse Mapping Pattern
```abap
" Build map 1: KNUMV → VBELN
DATA lt_knumv_to_vbeln TYPE tt_knumv_to_vbeln. " HASHED
LOOP AT lt_vbak INTO DATA(ls_vbak).
  INSERT VALUE #( knumv = ls_vbak-knumv vbeln = ls_vbak-vbeln )
         INTO TABLE lt_knumv_to_vbeln.
ENDLOOP.

" Build map 2: (VBELN, POSNR) → MATNR
DATA lt_position_to_matnr TYPE tt_position_to_matnr. " HASHED
LOOP AT lt_vbap INTO DATA(ls_vbap).
  INSERT VALUE #( vbeln = ls_vbap-vbeln posnr = ls_vbap-posnr matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr.
ENDLOOP.

" Reverse lookup
LOOP AT lt_konv INTO DATA(ls_konv).
  READ TABLE lt_knumv_to_vbeln INTO DATA(ls_map1)
    WITH KEY knumv = ls_konv-knumv.
  CHECK sy-subrc = 0.

  READ TABLE lt_position_to_matnr INTO DATA(ls_map2)
    WITH KEY vbeln = ls_map1-vbeln posnr = ls_konv-kposn.
  CHECK sy-subrc = 0.

  " Use: ls_map1-vbeln, ls_map2-matnr, ls_konv-kbetr
ENDLOOP.
```

---

## 📝 Summary

### Guide Structure

This guide covers:
1. ✅ **Purpose & Scope** — When and why to use this guide
2. ✅ **SAP Query Migration** — Indicators and justification
3. ✅ **Target Architecture** — 3-layer pattern, naming conventions
4. ✅ **Archiving Design** — Triple gating, hybrid BD+Archive strategy
5. ✅ **Data Access Strategy** — JOIN analysis, prefetch optimization
6. ✅ **Archive Retrieval** — Factory pattern, filter construction
7. ✅ **Technical Lessons** — Indexable fields, offset generation, coherent reads
8. ✅ **Performance** — Prefetch, guards, hashed lookups
9. ✅ **Test Strategy** — 3-tier approach (unit, integration, e2e)
10. ✅ **Migration Checklist** — Step-by-step implementation plan
11. ✅ **Common Pitfalls** — 8 frequent mistakes and solutions
12. ✅ **Decision Rules** — 10 reusable rules for quick decisions
13. ✅ **Code Patterns** — Copy-paste templates

### Key Lessons Documented

#### From Current Implementation (ZCL_MM_FLETFACT_SERVICE)
- **Gating mechanism:** Triple gate (p_hist + cutoff + needs_archive)
- **LEFT OUTER JOIN:** Enable archive tolerance in base SELECT
- **Prefetch optimization:** Eliminate SELECT SINGLE in loop (O(n²) → O(n))
- **Deterministic reverse mapping:** Intermediate hashed maps for KONV→VBELN→MATNR
- **Coherent archive reading:** All related tables from same source (VBAK+VBAP+KONV)
- **Best-effort pattern:** TRY-CATCH for archive reads, continue on failure

#### Critical Technical Discovery
- **Offset generation constraint:** Only infostructure fields (GENTAB) generate offsets
- **Catalog-only fields:** Must be post-filtered in memory (e.g., KNUMV, KSCHL)
- **SARI verification:** Always check field list before building filters
- **2-step pattern:** Filter by indexable → read full → post-filter

### How to Use This Guide in Future Developments

#### Scenario 1: New report needs historical data
1. Go to **When to Move Away from SAP Query** → assess need
2. Follow **Migration Checklist Phase 1-2** → plan architecture
3. Use **Code Patterns** → implement gating + archive reading
4. Apply **Decision Rules 1-10** → make design choices
5. Check **Common Pitfalls** → avoid known mistakes

#### Scenario 2: Existing class needs archive support
1. Go to **Data Access Strategy** → analyze SELECTs
2. Apply **Decision Rule 1** → determine INNER vs LEFT JOIN changes
3. Follow **General Archiving Design Pattern** → add triple gating
4. Use **Archive Retrieval Pattern** → implement filter + read methods
5. Follow **Test Strategy** → validate with 3-tier approach

#### Scenario 3: Performance issue in legacy code
1. Go to **Performance Guidelines** → identify bottleneck
2. Apply **Prefetch Pattern** → eliminate SELECT SINGLE in loop
3. Use **Hashed Lookup Pattern** → optimize lookups
4. Add **Guards** → protect FAE, avoid unnecessary archive reads

#### Scenario 4: Archive read returns 0 offsets
1. Go to **Important Technical Lessons** → understand offset generation
2. Run **SARI** → verify field is in infostructure
3. Apply **2-step pattern** → filter by indexable + post-filter
4. Check **Common Pitfall #1** → avoid catalog-only filters

---

**Document Version:** 1.0  
**Maintenance:** Update with new patterns as additional implementations are completed  
**Feedback:** Document lessons learned from each new archiving implementation

