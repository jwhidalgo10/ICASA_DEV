# 📘 Guía de Implementación de Archiving en ABAP

**Versión:** 1.0  
**Última actualización:** 11 de marzo de 2026  
**Basada en:** Experiencia de implementación de ZCL_MM_FLETFACT_SERVICE  

---

## 🎯 Propósito y Alcance

### Qué Cubre Esta Guía
Esta guía proporciona un **patrón de implementación reusable** para incorporar soporte de archiving SAP en soluciones ABAP existentes. Documenta estrategias probadas, patrones técnicos y lecciones críticas aprendidas en implementaciones reales.

### Escenarios Aplicables
- ✅ Migración de SAP Query/Infoset a programa ABAP + clase de servicio
- ✅ Reportes ABAP existentes que requieren capacidad de lectura de archivo histórico
- ✅ Clases de servicio en transición de solo BD a híbrido BD + Archive
- ✅ Rediseño de acceso a datos para soportar consulta de datos históricos
- ✅ Optimización de performance en código legacy con muchos SELECTs

### Qué NO Cubre Esta Guía
- ❌ Configuración de archiving (objetos de archivo, políticas de retención, setup SARA)
- ❌ Tuning de performance de ejecuciones de archiving
- ❌ Desarrollo de objetos de archiving custom
- ❌ Requerimientos legales/cumplimiento normativo para archiving de datos

---

## 🚦 Cuándo Migrar desde SAP Query

### Indicadores de que SAP Query Ya No Es Suficiente

#### Limitaciones Técnicas
1. **Sin soporte de archiving en infosets**
   - SAP Query no maneja LEFT OUTER JOINs adecuadamente para datos archivados
   - No permite implementar lectura condicional de archivo
   - Sin control sobre lógica de gating (cuándo consultar archivo)

2. **Problemas de performance**
   - Patrones SELECT SINGLE en loop (complejidad O(n²))
   - No permite implementar estrategias de prefetch
   - Control limitado sobre orden de joins

3. **Cálculos complejos**
   - Transformaciones multi-paso (prorrateo, redondeo, enriquecimiento)
   - Lógica condicional basada en reglas de negocio
   - Necesidad de mapeos reversos determinísticos

4. **Testabilidad**
   - No se puede hacer unit testing de lógica SAP Query
   - Difícil validar casos borde
   - Sin testing de regresión automatizado

#### Drivers de Negocio
- **Requerimientos regulatorios:** Necesidad de reportar datos >2-3 años
- **Auditoría:** Probar corrección de cálculos para períodos históricos
- **Degradación de performance:** Tiempo de ejecución aumenta a medida que envejece la BD
- **Carga de mantenimiento:** Infosets complejos se vuelven inmantenibles

### Plantilla de Justificación de Migración

**Enfoque recomendado para comunicación con stakeholders:**

```
Estado actual: SAP Query [QUERY_NAME] con infoset [INFOSET_NAME]
Problema: No se puede acceder a datos archivados de períodos anteriores a [CUTOFF_DATE]
Impacto: Falta [X]% de datos históricos, reportes incompletos
Solución propuesta: Migrar a programa ABAP + clase de servicio con soporte de archiving
Esfuerzo: [X] días desarrollo + [Y] días testing
Beneficio: Reporteo histórico completo + mejor performance + testabilidad
```

---

## 🏗️ Arquitectura Objetivo Recomendada

### Patrón de 3 Capas

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

### Convenciones de Nombres (Patrón Probado)

#### Métodos Públicos
- `start(is_screen) → rt_data` — Método orquestador (punto de entrada)
- `get_data(...) → rt_data` — SELECT base desde BD con LEFT OUTER JOINs

#### Métodos Protegidos (para testabilidad)
- `build_datetime_range(...)` — Convertir período a rango de timestamp
- `determine_transport_parameters(...)` — Mapear flags de negocio a parámetros técnicos
- `needs_archive(iv_cutoff, iv_pperiodo) → rv_needs` — Lógica de gating temporal

#### Métodos Privados (pipeline de procesamiento)
- `process_initial_calculation(...)` — Primera pasada de transformación
- `distribute_by_trip(...)` — Lógica de distribución/prorrateo
- `round_by_order(...)` — Lógica de redondeo/agregación
- `enrich_pricing_data(iv_use_archive, CHANGING ct_data)` — Prefetch BD + fallback a archivo

#### Métodos Privados (infraestructura de archiving)
- `enrich_vbap_from_archive(CHANGING ct_data)` — Completar campos faltantes de BD (best-effort)
- `fill_pricing_from_archive(it_unique_keys, CHANGING ct_pricing)` — Mapeo reverso para estructuras complejas
- `build_archive_filters_*(ir_vbeln, ...) → rt_filters` — Construcción de filtros
- `get_*_from_archive(it_filters) → et_*` — Lectura de archivo

### Estrategia de Visibilidad de Métodos
- **PUBLIC:** Solo orquestador y punto de entrada principal
- **PROTECTED:** Métodos necesarios para unit testing (lógica determinística, sin dependencias DB/archivo)
- **PRIVATE:** Todos los detalles de implementación

**Lección aprendida:** Mover 3-5 métodos clave de PRIVATE a PROTECTED permite unit testing efectivo sin exponer APIs internas.

---

## 🔁 Patrón General de Diseño de Archiving

### Mecanismo de Triple Gating

**Nunca consultar archivo incondicionalmente.** Usar triple gating:

```abap
METHOD start.
  DATA lv_cutoff TYPE sy-datum.
  DATA lv_use_archive TYPE abap_bool.

  " 1. Obtener fecha de cutoff desde framework de archiving
  lv_cutoff = zcl_ca_archiving_utility=>get_cutoff_date( ).

  " 2. Triple gate: flag usuario AND cutoff válido AND período necesita archivo
  lv_use_archive = xsdbool( is_screen-p_hist = abap_true AND
                            lv_cutoff IS NOT INITIAL AND
                            needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true ).

  " 3. Ejecutar SELECT base (siempre desde BD)
  rt_data = get_data(...).

  " 4. Enriquecer condicionalmente desde archivo
  IF lv_use_archive = abap_true.
    enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
  ENDIF.

  " 5. Continuar procesamiento...
  process_initial_calculation(...).
  enrich_pricing_data( EXPORTING iv_use_archive = lv_use_archive
                       CHANGING  ct_data = rt_data ).
ENDMETHOD.
```

### Lógica de needs_archive() — Criterio Temporal

**Regla:** Se necesita archivo si **primer día del período <= fecha cutoff**

```abap
METHOD needs_archive.
  DATA lv_dinicio TYPE sy-datum.
  
  " Convertir YYYYMM a YYYYMM01
  CONCATENATE iv_pperiodo '01' INTO lv_dinicio.
  
  " Comparar: si inicio período <= cutoff → necesita archivo
  rv_needs = xsdbool( lv_dinicio <= iv_cutoff ).
ENDMETHOD.
```

**Justificación:** Evita heurísticas arbitrarias. El cutoff es el límite autoritativo establecido por las ejecuciones de archiving.

### Estrategia Híbrida BD + Archive

#### Patrón 1: Enrich (Completado Best-Effort)
**Cuándo:** SELECT base trae filas con algunos campos iniciales (datos archivados)  
**Objetivo:** Llenar campos faltantes sin cambiar cantidad de filas  
**Manejo de errores:** TRY-CATCH, continuar si falla archivo

```abap
METHOD enrich_vbap_from_archive.
  " 1. Identificar filas con ARKTX/NETWR iniciales
  " 2. Construir rangos para claves únicas (VBELN, MATNR)
  " 3. Leer VBAP desde archivo
  " 4. Merge: llenar solo si inicial (no sobrescribir)
  " 5. TRY-CATCH: falla de archivo no es crítica
ENDMETHOD.
```

#### Patrón 2: Fill (Mapeo Reverso Complejo)
**Cuándo:** Prefetch desde BD pierde algunas claves (documentos históricos)  
**Objetivo:** Completar entradas faltantes via lookup reverso  
**Manejo de errores:** TRY-CATCH, continuar si falla archivo  
**Característica clave:** Respeta semántica "first occurrence wins"

```abap
METHOD fill_pricing_from_archive.
  " Solo se llama si iv_use_archive = abap_true
  " Paso 1: Detectar claves faltantes (no hay ZPB2/ZR05 en ct_pricing)
  " Paso 2: Construir rangos lr_vbeln_miss, lr_matnr_miss
  " Paso 3: Leer VBAP → construir mapa determinístico (vbeln+posnr→matnr)
  " Paso 4: Leer VBAK → construir mapa determinístico (knumv→vbeln)
  " Paso 5: Leer KONV (filtrar por VBELN indexable)
  " Paso 6: Post-filtrar KONV en memoria (KNUMV/KPOSN/KSCHL)
  " Paso 7: Mapeo reverso → INSERT en ct_pricing (hashed, first wins)
ENDMETHOD.
```

### Árbol de Decisión: Cuándo Usar Cada Patrón

```
¿SELECT base retorna filas con campos faltantes?
├─ SÍ → Usar patrón "enrich" (completar filas existentes)
└─ NO → ¿Prefetch pierde algunas claves?
    ├─ SÍ → Usar patrón "fill" (agregar entradas faltantes)
    └─ NO → No se necesita archivo para este método
```

---

## 🗂️ Estrategia de Acceso a Datos

### Analizar SELECTs Existentes

**Checklist para cada SELECT en código legacy:**

1. ✅ **Identificar tablas clave:** ¿Qué tablas se leen?
2. ✅ **Verificar estado de archiving:** ¿Alguna de estas tablas está archivada? (usar SARI, código de transacción)
3. ✅ **Analizar JOINs:** ¿INNER vs LEFT OUTER? ¿Datos archivados pueden romper joins?
4. ✅ **Identificar campos indexables:** ¿Qué campos están en infoestructura vs solo catálogo?
5. ✅ **Evaluar criticidad de negocio:** ¿Reporte puede funcionar con datos parciales o debe ser completo?

### INNER JOIN vs LEFT OUTER JOIN

#### Cuándo Cambiar INNER → LEFT OUTER

**Regla:** Si la **tabla derecha** (la que se hace join) puede ser archivada Y campos de esa tabla se usan para enriquecimiento (no filtrado), cambiar a LEFT OUTER JOIN.

**Ejemplo de implementación:**
```abap
" Antes (INNER JOIN):
SELECT ... FROM ztmt_serfletr01 AS h
  INNER JOIN vbap AS pv ON ...  " ← VBAP archivada → 0 filas si está archivada

" Después (LEFT OUTER JOIN):
SELECT ... FROM ztmt_serfletr01 AS h
  LEFT OUTER JOIN vbap AS pv ON ...  " ← Query tiene éxito aunque VBAP esté archivada
```

**Cuándo mantener INNER JOIN:**
- Tabla derecha **nunca es archivada** (ej: datos maestros como BUT000, T001)
- Campos de tabla derecha son **obligatorios para lógica de negocio** (no se puede proceder sin ellos)

#### Patrón para Consultas Tolerantes a Archivo

```abap
" Paso 1: SELECT base con LEFT OUTER JOIN en tablas archivables
SELECT @iv_tipotrans,
       h~tor_id,          " Siempre desde BD (header)
       pv~vbeln,          " Puede ser inicial (archivado)
       pv~netwr,          " Puede ser inicial (archivado)
       ...
  FROM ztmt_serfletr01 AS h
  INNER JOIN ztmt_serfletr02 AS p ON ...     " ← No archivada
  INNER JOIN but000 AS c ON ...              " ← Datos maestros
  LEFT OUTER JOIN vbap AS pv ON ...          " ← ARCHIVADA
  WHERE ...
  INTO TABLE @rt_data.

" Paso 2: Condicionalmente completar campos archivados
IF lv_use_archive = abap_true.
  enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
ENDIF.
```

### Estrategia de Prefetch para Performance

**Problema:** SELECT SINGLE en loop → complejidad O(n²)

**Solución:** Prefetch + hashed lookup → O(n)

```abap
METHOD enrich_pricing_data.
  DATA lt_unique_keys TYPE tt_pricing_keys.
  DATA lt_pricing_temp TYPE STANDARD TABLE OF ty_pricing.
  DATA lt_pricing TYPE tt_pricing. " ← HASHED TABLE

  " Paso 1: Extraer (vbeln, matnr) únicos desde ct_data
  lt_unique_keys = VALUE #( FOR <wa> IN ct_data
                            ( vbeln = <wa>-numeropedido
                              matnr = <wa>-materialfactura ) ).
  SORT lt_unique_keys BY vbeln matnr.
  DELETE ADJACENT DUPLICATES FROM lt_unique_keys.

  " Paso 2: SELECT único con FOR ALL ENTRIES
  CHECK lt_unique_keys IS NOT INITIAL.
  SELECT vbeln, matnr, kschl, kbetr
    FROM prcd_elements
    FOR ALL ENTRIES IN @lt_unique_keys
    WHERE vbeln = @lt_unique_keys-vbeln
      AND matnr = @lt_unique_keys-matnr
      AND kschl IN ('ZPB2', 'ZR05')
    INTO TABLE @lt_pricing_temp.

  " Paso 3: Poblar tabla hashed (first occurrence wins)
  LOOP AT lt_pricing_temp ASSIGNING FIELD-SYMBOL(<fs_temp>).
    INSERT VALUE ty_pricing( vbeln = <fs_temp>-vbeln
                             matnr = <fs_temp>-matnr
                             kschl = <fs_temp>-kschl
                             kbetr = <fs_temp>-kbetr )
           INTO TABLE lt_pricing. " ← Hashed INSERT (no duplicates)
  ENDLOOP.

  " Paso 4: Loop con READ TABLE (lookup O(1))
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

### Acceso Coherente a Archivo para Tablas Relacionadas

**Anti-patrón:** Mezclar fuentes BD y archivo para tablas del mismo documento de negocio

**Lección aprendida de la implementación:**
- ❌ **Incorrecto:** Leer VBAK desde BD, VBAP desde archivo, KONV desde BD → estado de documento inconsistente
- ✅ **Correcto:** Leer VBAK + VBAP + KONV todo desde archivo (snapshot histórico coherente)

**Ejemplo (pricing histórico):**
```abap
" Todas las tablas del mismo documento archivado
lt_vbap = get_vbap_from_archive( lt_filters_vbap ).  " ← Archivado
lt_vbak = get_vbak_from_archive( lt_filters_vbak ).  " ← Archivado
lt_konv = get_konv_from_archive( lt_filters_konv ).  " ← Archivado

" Construir mapas reversos desde datos archivados
LOOP AT lt_vbap INTO ls_vbap.
  INSERT VALUE #( vbeln = ls_vbap-vbeln
                  posnr = ls_vbap-posnr
                  matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr.
ENDLOOP.
```

---

## 📦 Patrón de Lectura de Archivo

### Uso del Patrón Factory

```abap
DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
DATA lt_vbap_arch TYPE STANDARD TABLE OF vbap.
DATA lt_filters TYPE ztt_ca_archiving.

" Paso 1: Construir filtros (ver siguiente sección)
lt_filters = build_archive_filters_vbap( ir_vbeln = lr_vbeln
                                         ir_matnr = lr_matnr ).

" Paso 2: Instanciar factory
lo_factory = NEW zcl_ca_archiving_factory( ).

" Paso 3: Obtener instancia con filtros
lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbap
                          it_filter_options = lt_filters ).

" Paso 4: Extraer datos
lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbap
                      IMPORTING et_data = lt_vbap_arch ).
```

### Patrón de Construcción de Filtros

**Patrón estándar para todas las lecturas de archivo:**

```abap
METHOD build_archive_filters_vbap.
  DATA lr_vbeln TYPE /iwbep/t_cod_select_options.
  DATA lr_matnr TYPE /iwbep/t_cod_select_options.

  " Convertir rangos ABAP a formato archiving
  IF ir_vbeln IS NOT INITIAL.
    MOVE-CORRESPONDING ir_vbeln TO lr_vbeln.
  ENDIF.

  IF ir_matnr IS NOT INITIAL.
    MOVE-CORRESPONDING ir_matnr TO lr_matnr.
  ENDIF.

  " Instanciar query controller
  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).

  " Agregar filtros (solo si están poblados)
  IF lr_vbeln IS NOT INITIAL.
    lo_query->add_filter_from_range( iv_name = 'VBELN'
                                     ir_values = lr_vbeln ).
  ENDIF.

  IF lr_matnr IS NOT INITIAL.
    lo_query->add_filter_from_range( iv_name = 'MATNR'
                                     ir_values = lr_matnr ).
  ENDIF.

  " Aplicar a infoestructura
  lo_query->apply_filters_to_str( iv_archiving_str = gc_str_vbap ).

  " Retornar filtros construidos
  rt_filters = lo_query->gt_filter_options.
ENDMETHOD.
```

### Patrón de Manejo de Excepciones

**Todas las lecturas de archivo deben tener TRY-CATCH (best-effort):**

```abap
METHOD enrich_vbap_from_archive.
  TRY.
      DATA(lt_filters) = build_archive_filters_vbap(...).
      DATA(lt_vbap) = get_vbap_from_archive( lt_filters ).
      
      " Lógica de merge aquí...
      
    CATCH zcx_ca_archiving INTO DATA(lx_arch).
      " Loguear o ignorar: falla de archivo no aborta cálculo principal
      " Lectura de archivo es best-effort, no path crítico
  ENDTRY.
ENDMETHOD.
```

**Justificación:** La infraestructura de archivo puede fallar (corrupción de archivo, problemas de permisos, problemas de red). El cálculo principal debe continuar con datos parciales.

---

## ⚡ Lecciones Técnicas Importantes Aprendidas

### Descubrimiento Crítico: Generación de Offsets y Campos Indexables

#### Cómo Funciona Internamente la Lectura de Archivo

**Cadena de llamadas:**
```
get_instance(iv_object, it_filters)
  └─> get_archiving_keys(it_filters)
      └─> get_data_keys(it_filters)
          └─> fill_where_clause(it_filters)
              └─> SELECT FROM (infostructure_table) WHERE ...
```

**Insight clave de ZCL_CA_ARCHIVING_CTRL→get_data_keys():**

```abap
METHOD get_data_keys.
  " Construir lista dinámica de campos desde campos de infoestructura
  lv_fields = 'ARCHIVEKEY, ARCHIVEOFS, field1, field2, ...'.

  " Construir cláusula WHERE dinámica desde filtros
  lv_where = fill_where_clause( it_filters, iv_archindex, iv_table_name ).

  " Ejecutar query en GENTAB (ej: SAP_DRB_VBAK_02)
  SELECT (lv_fields)
    FROM (is_struct-gentab)    " ← NOMBRE DE TABLA DINÁMICO (infoestructura!)
    WHERE (lv_where)
    APPENDING CORRESPONDING FIELDS OF TABLE @<lt_keys>.
ENDMETHOD.
```

**🚨 RESTRICCIÓN CRÍTICA:**  
Solo los campos que **existen en GENTAB** (tabla de infoestructura) pueden generar offsets.  
Los campos que existen solo en el **catálogo** (tabla original) **NO FUNCIONAN** para filtrado.

#### Verificación: Transacción SARI

**Cómo verificar qué campos son indexables:**

1. Ejecutar transacción **SARI** (Archive Information System)
2. Seleccionar objeto de archiving (ej: SD_VBAK)
3. Seleccionar infoestructura (ej: SAP_DRB_VBAK_02)
4. Revisar listas de campos:
   - **Panel izquierdo** ("Campos de estructura info"): Campos en GENTAB → ✅ **INDEXABLES**
   - **Panel derecho** ("Catálogo"): Campos solo en tabla original → ❌ **NO INDEXABLES**

**Ejemplo para SD_VBAK / SAP_DRB_VBAK_02:**
- ✅ **INDEXABLES:** VBELN, POSNR, MATNR (en infoestructura)
- ❌ **NO INDEXABLES:** KNUMV, KPOSN, KSCHL (solo catálogo, no en infoestructura)

#### Por Qué los Filtros de KONV No Generan Offsets

**Escenario problema:**
```abap
" ❌ INCORRECTO: Filtrar por campos solo-catálogo
lo_query->add_filter_from_range( iv_name = 'KNUMV' ir_values = lr_knumv ).
lo_query->add_filter_from_range( iv_name = 'KSCHL' ir_values = lr_kschl ).
```

**Qué ocurre internamente:**
```sql
-- SELECT FROM SAP_DRB_VBAK_02 
-- WHERE KNUMV = ... AND KSCHL = ...  
-- ← CAMPOS NO ENCONTRADOS EN TABLA → 0 offsets generados
```

**Causa raíz:** KNUMV, KPOSN, KSCHL son **campos de catálogo** (existen en estructura de tabla KONV) pero **NO son campos de infoestructura** (no están en GENTAB SAP_DRB_VBAK_02).

#### Patrón Correcto de 2 Pasos para Campos No Indexables

**Estrategia:** Filtrar por campos indexables → leer datos completos → post-filtrar en memoria

```abap
METHOD get_konv_from_archive.
  " Paso 1: Filtrar SOLO por campos indexables (VBELN está en infoestructura)
  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).
  lo_query->add_filter_from_range( iv_name = 'VBELN'
                                   ir_values = lr_vbeln ).
  lo_query->apply_filters_to_str( gc_str_konv ).

  " Paso 2: Leer KONV completo para esos VBELNs
  DATA(lo_factory) = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_konv
                            it_filter_options = lo_query->gt_filter_options ).
  lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_konv
                        IMPORTING et_data = et_konv ).
ENDMETHOD.

METHOD fill_pricing_from_archive.
  " Paso 3: Post-filtrar en memoria por campos no indexables
  DATA(lt_konv) = get_konv_from_archive( lr_vbeln ).
  
  " Filtrar por KNUMV, KPOSN, KSCHL en memoria
  LOOP AT lt_konv INTO DATA(ls_konv)
    WHERE knumv IN lr_knumv
      AND kposn IN lr_kposn
      AND kschl IN lr_kschl.
    " Procesar registro filtrado...
  ENDLOOP.
ENDMETHOD.
```

### Mapeo Reverso Determinístico

**Problema:** Datos de archivo frecuentemente requieren lookups reversos (KONV → VBELN → MATNR)

**Anti-patrón:** Lookups ad-hoc con READ TABLE en loops anidados → O(n³)

**Solución:** Construir mapas intermedios hasheados una vez → O(n)

```abap
" Paso 3: Construir mapa determinístico (VBELN + POSNR → MATNR)
DATA lt_position_to_matnr TYPE tt_position_to_matnr. " ← HASHED
LOOP AT lt_vbap INTO DATA(ls_vbap).
  INSERT VALUE #( vbeln = ls_vbap-vbeln
                  posnr = ls_vbap-posnr
                  matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr. " ← Hashed insert O(1)
ENDLOOP.

" Paso 4: Construir mapa determinístico (KNUMV → VBELN)
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

**Mejor práctica de definición de tipos:**
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

