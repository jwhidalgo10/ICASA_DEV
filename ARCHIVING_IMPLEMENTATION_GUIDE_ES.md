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
│  - Selection screen (bloques, checkbox p_hist)          │
│  - Mapeo de parámetros a ty_screen                      │
│  - Instanciación de servicio                            │
│  - Display ALV/SALV                                     │
└─────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│  SERVICE CLASS (ZCL_*_SERVICE)                          │
│  - start() orquestador                                  │
│  - get_data() SELECT base (lectura BD)                  │
│  - process_*() métodos de transformación                │
│  - enrich_*() métodos de enriquecimiento (prefetch BD)  │
│  - enrich_*_from_archive() hooks archivo (best-effort)  │
│  - fill_*_from_archive() lectura archivo (fallback)     │
└─────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│  ARCHIVING FRAMEWORK (ZCL_CA_ARCHIVING_*)               │
│  - Factory (instanciación de objetos)                   │
│  - Controller (generación de offsets)                   │
│  - Query Controller (construcción de filtros)           │
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

### Árboldecisión: Cuándo Usar Cada Patrón

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

**Regla:** Si la **tabla derecha** (la que se hace join) puede ser archivada Y campos de esa tabla se usan para enriquecimiento (no filtrado), considerar cambiar a LEFT OUTER JOIN.

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
  DATA lt_pricing TYPE  tt_pricing. " ← HASHED TABLE

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
           INTO TABLE lt_pricing. " ← INSERT hasheado (sin duplicados)
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
         INTO TABLE lt_position_to_matnr. " ← Insert hasheado O(1)
ENDLOOP.

" Paso 4: Construir mapa determinístico (KNUMV → VBELN)
DATA lt_knumv_to_vbeln TYPE tt_knumv_to_vbeln. " ← HASHED
LOOP AT lt_vbak INTO DATA(ls_vbak).
  INSERT VALUE #( knumv = ls_vbak-knumv
                  vbeln = ls_vbak-vbeln )
         INTO TABLE lt_knumv_to_vbeln. " ← Insert hasheado O(1)
ENDLOOP.

" Paso 7: Mapeo reverso KONV → pricing
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
         INTO TABLE ct_pricing. " ← HASHED, duplicado ignorado
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

## 🚀 Lineamientos de Performance

### Optimización de SELECT

#### Anti-patrón: SELECT SINGLE en Loop
```abap
" ❌ INCORRECTO: Complejidad O(n²)
LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs>).
  SELECT SINGLE kbetr FROM prcd_elements
    WHERE vbeln = <fs>-numeropedido
      AND matnr = <fs>-materialfactura
      AND kschl = 'ZPB2'
    INTO <fs>-valorfleteo.
ENDLOOP.
```

#### Patrón: Prefetch + Hashed Lookup
```abap
" ✅ CORRECTO: Complejidad O(n)
" Paso 1: Extraer claves únicas
DATA(lt_keys) = VALUE tt_pricing_keys(
  FOR <wa> IN ct_data ( vbeln = <wa>-numeropedido
                        matnr = <wa>-materialfactura ) ).
SORT lt_keys. DELETE ADJACENT DUPLICATES FROM lt_keys.

" Paso 2: SELECT único con FAE
CHECK lt_keys IS NOT INITIAL.
SELECT vbeln, matnr, kschl, kbetr
  FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
    AND matnr = @lt_keys-matnr
    AND kschl = 'ZPB2'
  INTO TABLE @DATA(lt_pricing_temp).

" Paso 3: Poblar tabla hashed
DATA lt_pricing TYPE tt_pricing. " HASHED TABLE
LOOP AT lt_pricing_temp INTO DATA(ls_temp).
  INSERT VALUE #( vbeln = ls_temp-vbeln ... ) INTO TABLE lt_pricing.
ENDLOOP.

" Paso 4: Loop con lookup O(1)
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

### Guards de Lectura de Archivo

**Nunca leer archivo incondicionalmente:**

```abap
" ✅ Guard 1: Activación por usuario
CHECK is_screen-p_hist = abap_true.

" ✅ Guard 2: Validez de cutoff
DATA(lv_cutoff) = zcl_ca_archiving_utility=>get_cutoff_date( ).
CHECK lv_cutoff IS NOT INITIAL.

" ✅ Guard 3: Criterio temporal
DATA(lv_needs) = needs_archive( lv_cutoff, is_screen-pperiodo ).
CHECK lv_needs = abap_true.

" ✅ Guard 4: Detección de claves faltantes
DATA(lt_missing) = detect_missing_keys( ct_data ).
CHECK lt_missing IS NOT INITIAL.

" Solo si TODOS los guards pasan → leer archivo
```

### Protección FOR ALL ENTRIES

**Siempre proteger FOR ALL ENTRIES:**

```abap
" ❌ INCORRECTO: lt_keys vacía causa lectura de tabla completa
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.

" ✅ CORRECTO: Guard antes del SELECT
CHECK lt_keys IS NOT INITIAL.
SELECT vbeln, matnr, kschl, kbetr
  FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

### Uso de Tablas Hashed

**Cuándo usar HASHED vs SORTED vs STANDARD:**

- **HASHED:** Lookup por clave completa (READ TABLE WITH KEY), sin duplicados, O(1)
- **SORTED:** Lookup por clave parcial, BINARY SEARCH, O(log n)
- **STANDARD:** Acceso secuencial, LOOP, O(n)

**Ejemplo:**
```abap
TYPES tt_pricing TYPE HASHED TABLE OF ty_pricing
      WITH UNIQUE KEY vbeln matnr kschl.

" Lookup O(1) por clave completa
READ TABLE lt_pricing INTO ls_pricing
  WITH KEY vbeln = '123'
           matnr = 'MAT1'
           kschl = 'ZPB2'.
```

---

## 🧪 Estrategia de Testing

### Enfoque de Testing en 3 Niveles

```
┌────────────────────────────────────────────────────────────┐
│  NIVEL 1: ABAP Unit Tests                                  │
│  Alcance: Métodos determinísticos (sin DB, sin archivo)    │
│  Ejemplos:                                                  │
│  - Lógica needs_archive()                                  │
│  - Conversión build_datetime_range()                       │
│  - Mapeo determine_transport_parameters()                  │
│  Herramientas: cl_abap_unit_assert, test helper subclass   │
│  Meta de cobertura: 80%+ para métodos determinísticos      │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  NIVEL 2: Pruebas de Integración Técnicas                  │
│  Alcance: Patrones de lectura de archivo (con archivo real)│
│  Ejemplos:                                                  │
│  - build_archive_filters_*() + get_*_from_archive()        │
│  - Generación de offsets para VBELNs específicos           │
│  - Lógica de post-filtrado en memoria                      │
│  Herramientas: Programas Z_TEST_*, validación manual       │
│  Meta de cobertura: Todos los objetos de archivo usados    │
└────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────┐
│  NIVEL 3: Validación de Negocio End-to-End                 │
│  Alcance: Ejecución completa del reporte (BD + archivo)    │
│  Ejemplos:                                                  │
│  - Ejecutar reporte para período [X] con p_hist = X        │
│  - Validar fórmulas de cálculo                             │
│  - Comparar vs SAP Query original (si es migración)        │
│  Herramientas: Ejecución manual, UAT                       │
│  Meta de cobertura: Escenarios de negocio clave            │
└────────────────────────────────────────────────────────────┘
```

### Qué Testear con Unit Tests

#### ✅ Candidatos de Alto Valor para Unit Test
- **Lógica de gating:** Árbol de decisión needs_archive()
- **Conversiones temporales:** Período → fecha → rangos de timestamp
- **Mapeo de parámetros:** Flags de negocio → parámetros técnicos
- **Cálculos determinísticos:** Fórmulas de prorrateo, lógica de redondeo (sin dependencias DB)

#### ❌ Bajo Valor / Difícil de Unit Testear
- SELECTs de base de datos (usar pruebas de integración)
- Lectura de archivo (usar pruebas técnicas)
- Enriquecimiento complejo con lookups anidados (usar pruebas de integración)
- Métodos con dependencias DB inevitables

### Patrón Test Helper (para Métodos Protegidos)

```abap
" Include de test (.testclasses.abap)
CLASS lcl_test_helper DEFINITION INHERITING FROM zcl_mm_fletfact_service
  FOR TESTING CREATE PUBLIC.

  PUBLIC SECTION.
    " Wrappers públicos para métodos PROTECTED
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

**Por qué este patrón:**
- No se puede acceder a métodos PROTECTED desde clase de test directamente
- La herencia permite acceso via wrappers públicos
- Sin contaminación del API PUBLIC de la clase de producción

### Patrón de Prueba de Integración (Programas Z_TEST_*)

**Propósito:** Validar lectura de archivo con datos reales

**Estructura:**
```abap
REPORT z_test_sd_vbak_pricing_arch.

PARAMETERS: p_vbeln TYPE vbeln OBLIGATORY.

START-OF-SELECTION.
  " 1. Construir filtros
  DATA(lr_vbeln) = VALUE /iwbep/t_cod_select_options(
    ( sign = 'I' option = 'EQ' low = p_vbeln ) ).

  DATA(lo_query) = NEW zcl_ca_archiving_query_ctrl( ).
  lo_query->add_filter_from_range( iv_name = 'VBELN'
                                   ir_values = lr_vbeln ).
  lo_query->apply_filters_to_str( 'SAP_DRB_VBAK_02' ).

  " 2. Leer VBAK
  DATA(lo_factory) = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbak
                            it_filter_options = lo_query->gt_filter_options ).
  lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbak
                        IMPORTING et_data = DATA(lt_vbak) ).

  " 3. Display results
  cl_demo_output=>display( lt_vbak ).
```

**Checklist de validación:**
- ✅ ¿Filtros generados correctamente?
- ✅ ¿Offsets recuperados?
- ✅ ¿Datos extraídos coinciden con expectativas?
- ✅ ¿Lógica de post-filtro funciona?

---

## 📋 Checklist de Migración

### Fase 1: Análisis y Planeación

- [ ] **Identificar alcance:** ¿Qué reporte/query necesita archiving?
- [ ] **Verificar estado de archiving:** ¿Qué tablas están archivadas? (SARI, TAANA)
- [ ] **Analizar SELECTs:** Documentar todos los accesos a tablas en código existente
- [ ] **Identificar infoestructuras:** ¿Qué infoestructuras cubren estas tablas?
- [ ] **Mapear campos indexables:** Para cada tabla, listar campos en infoestructura vs catálogo
- [ ] **Definir estrategia de cutoff:** ¿Qué fecha de cutoff se usará?
- [ ] **Estimar complejidad:** ¿Cuántas tablas? ¿Cuántos joins? ¿Mapeos reversos complejos?
- [ ] **Obtener aprobación de stakeholders:** Estimación de esfuerzo, timeline, alcance de testing

### Fase 2: Diseño de Arquitectura

- [ ] **Crear clase de servicio:** Zcl_*_SERVICE con secciones PUBLIC/PROTECTED/PRIVATE
- [ ] **Definir ty_screen:** Estructura de parámetros (pperiodo, rdfpro/ter/exp, p_hist)
- [ ] **Definir tt_result:** Estructura de salida (replicar campos de infoset + calculados)
- [ ] **Planear descomposición de métodos:**
  - [ ] start() orquestador
  - [ ] get_data() SELECT base
  - [ ] process_*() pipeline de transformación
  - [ ] enrich_*() métodos de prefetch BD
  - [ ] enrich_*_from_archive() hooks de archivo (best-effort)
  - [ ] fill_*_from_archive() fallback a archivo (mapeo complejo)
- [ ] **Documentar lógica de gating:** Pseudo-código para triple gate (p_hist + cutoff + needs_archive)

### Fase 3: Implementación Base (Solo BD)

- [ ] **Migrar SELECT base:** Convertir query de infoset a método get_data()
- [ ] **Cambiar INNER → LEFT OUTER JOIN:** Para tablas archivables
- [ ] **Implementar transformaciones:** Portar lógica de cálculo a métodos process_*()
- [ ] **Implementar prefetch BD:** Portar lógica de enriquecimiento a métodos enrich_*() (sin archivo aún)
- [ ] **Crear reporte:** Selection screen + mapeo de parámetros + display ALV
- [ ] **Testear modo solo-BD:** Validar que resultados coincidan con query original para datos recientes

### Fase 4: Infraestructura de Archivo

- [ ] **Crear métodos protegidos:**
  - [ ] build_datetime_range()
  - [ ] determine_transport_parameters()
  - [ ] needs_archive()
- [ ] **Crear constructores de filtros de archivo:**
  - [ ] build_archive_filters_vbap()
  - [ ] build_archive_filters_vbak()
  - [ ] build_archive_filters_konv() (si se necesita)
- [ ] **Crear lectores de archivo:**
  - [ ] get_vbap_from_archive()
  - [ ] get_vbak_from_archive()
  - [ ] get_konv_from_archive() (si se necesita)
- [ ] **Agregar constantes:**
  - [ ] gc_str_vbap = 'SAP_DRB_VBAK_02'
  - [ ] gc_str_vbak = 'SAP_DRB_VBAK_02'

### Fase 5: Integración de Archivo

- [ ] **Implementar gating en start():**
  - [ ] Obtener cutoff: zcl_ca_archiving_utility=>get_cutoff_date()
  - [ ] Triple gate: p_hist + cutoff + needs_archive()
  - [ ] Llamadas condicionales a enrich_*_from_archive()
- [ ] **Implementar enrich_*_from_archive():**
  - [ ] Detectar filas con campos iniciales
  - [ ] Construir rangos para claves únicas
  - [ ] Llamar get_*_from_archive()
  - [ ] Merge: llenar solo si inicial (no sobrescribir)
  - [ ] TRY-CATCH: best-effort, continuar si falla
- [ ] **Implementar fill_*_from_archive() (si se necesita):**
  - [ ] Detectar claves faltantes en resultado de prefetch
  - [ ] Construir rangos para claves faltantes
  - [ ] Leer datos de archivo (coherente: todo desde archivo)
  - [ ] Construir mapas reversos determinísticos (tablas HASHED)
  - [ ] Mapeo reverso + INSERT (first occurrence wins)
  - [ ] TRY-CATCH: best-effort

### Fase 6: Testing

- [ ] **Unit tests:**
  - [ ] Casos borde de needs_archive() (antes/en/después de cutoff)
  - [ ] Límites de mes build_datetime_range()
  - [ ] Mapeo de flags determine_transport_parameters()
- [ ] **Pruebas de integración (programas Z_TEST_*):**
  - [ ] Lectura de archivo: VBAP, VBAK, KONV
  - [ ] Construcción de filtros: solo campos indexables
  - [ ] Generación de offsets: validar conteos
  - [ ] Lógica de post-filtro: campos de catálogo
- [ ] **Validación end-to-end:**
  - [ ] Ejecutar reporte para período reciente (solo BD): p_hist = ' '
  - [ ] Ejecutar reporte para período histórico (BD + archivo): p_hist = 'X'
  - [ ] Comparar resultados vs query original (si es migración)
  - [ ] Validar fórmulas: spot checks manuales
  - [ ] Benchmark de performance: ¿runtime aceptable?

### Fase 7: Documentación y Despliegue

- [ ] **Actualizar documentación técnica:**
  - [ ] Firmas de métodos y propósitos
  - [ ] Diagrama de lógica de gating
  - [ ] Flujo de lectura de archivo
  - [ ] Limitaciones conocidas
- [ ] **Crear guía de usuario:**
  - [ ] Cuándo activar checkbox p_hist
  - [ ] Comportamiento esperado para datos históricos vs recientes
  - [ ] Consideraciones de performance
- [ ] **Transportar:**
  - [ ] Clase de servicio
  - [ ] Reporte
  - [ ] Unit tests
  - [ ] Pruebas de integración
  - [ ] Documentación
- [ ] **Validación post-despliegue:**
  - [ ] Smoke tests en QA
  - [ ] UAT (User Acceptance Testing)
  - [ ] Monitoreo de performance

---

## ⚠️ Errores Comunes

### 1. Filtrar por Campos No Indexables

**Problema:** Usar campos solo-catálogo en filtros de archivo genera 0 offsets

**Ejemplo:**
```abap
" ❌ INCORRECTO: KNUMV no está en infoestructura
lo_query->add_filter_from_range( iv_name = 'KNUMV' ... ).
" → SELECT FROM SAP_DRB_VBAK_02 WHERE KNUMV = ... → Campo no encontrado
```

**Solución:** Filtrar por campos indexables solo, post-filtrar en memoria
```abap
" ✅ CORRECTO: VBELN en infoestructura
lo_query->add_filter_from_range( iv_name = 'VBELN' ... ).
" → SELECT FROM SAP_DRB_VBAK_02 WHERE VBELN = ... → Offsets generados

" Post-filtrar en memoria
LOOP AT lt_konv INTO ls_konv WHERE knumv IN lr_knumv.
```

**Cómo evitar:** Siempre verificar SARI antes de construir filtros

### 2. Mezclar Fuentes BD y Archivo Inconsistentemente

**Problema:** Leer tablas relacionadas desde fuentes diferentes rompe coherencia de documento

**Ejemplo:**
```abap
" ❌ INCORRECTO: Fuentes inconsistentes para tablas relacionadas
SELECT * FROM vbak INTO TABLE lt_vbak WHERE ...  " ← Desde BD
DATA(lt_vbap) = get_vbap_from_archive( ... ).    " ← Desde archivo
DATA(lt_konv) = get_konv_from_archive( ... ).    " ← Desde archivo
" → VBAK muestra estado actual, VBAP/KONV muestran histórico → desajuste
```

**Solución:** Leer todas las tablas relacionadas desde la misma fuente (snapshot coherente)
```abap
" ✅ CORRECTO: Todo desde archivo para documentos históricos
DATA(lt_vbak) = get_vbak_from_archive( ... ).    " ← Archivo
DATA(lt_vbap) = get_vbap_from_archive( ... ).    " ← Archivo
DATA(lt_konv) = get_konv_from_archive( ... ).    " ← Archivo
```

### 3. Leer Archivo Sin Gating

**Problema:** Lecturas incondicionales de archivo ralentizan cada ejecución

**Ejemplo:**
```abap
" ❌ INCORRECTO: Siempre lee archivo
DATA(lt_vbap) = get_vbap_from_archive( ... ).
```

**Solución:** Triple gating antes de acceder archivo
```abap
" ✅ CORRECTO: Lectura condicional de archivo
IF is_screen-p_hist = abap_true AND
   lv_cutoff IS NOT INITIAL AND
   needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true.
  DATA(lt_vbap) = get_vbap_from_archive( ... ).
ENDIF.
```

### 4. SELECT SINGLE en Loop (No Usar Prefetch)

**Problema:** Complejidad O(n²) degrada performance

**Ejemplo:**
```abap
" ❌ INCORRECTO: n round-trips a base de datos
LOOP AT ct_data ASSIGNING <fs>.
  SELECT SINGLE kbetr FROM prcd_elements WHERE ... INTO <fs>-price.
ENDLOOP.
```

**Solución:** Prefetch + hashed lookup (O(n))
```abap
" ✅ CORRECTO: 1 round-trip a base de datos
" Extraer claves únicas → SELECT FAE → tabla hashed → loop con READ TABLE
```

### 5. No Proteger FOR ALL ENTRIES

**Problema:** Tabla driver vacía causa lectura de tabla completa

**Ejemplo:**
```abap
" ❌ INCORRECTO: Si lt_keys está inicial, lee tabla entera
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

**Solución:** Siempre proteger con guard
```abap
" ✅ CORRECTO: Guard previene lectura de tabla completa
CHECK lt_keys IS NOT INITIAL.
SELECT * FROM prcd_elements
  FOR ALL ENTRIES IN @lt_keys
  WHERE vbeln = @lt_keys-vbeln
  INTO TABLE @lt_pricing.
```

### 6. Sobrescribir Resultados de Prefetch con Archivo

**Problema:** Datos de archivo sobrescriben datos más recientes de BD

**Ejemplo:**
```abap
" ❌ INCORRECTO: Archivo sobrescribe prefetch BD
LOOP AT lt_pricing_archive INTO ls_pricing.
  ct_pricing[ vbeln = ls_pricing-vbeln ] = ls_pricing. " ← Sobrescribe!
ENDLOOP.
```

**Solución:** INSERT en tabla hashed (first occurrence wins)
```abap
" ✅ CORRECTO: INSERT hasheado ignora duplicados
LOOP AT lt_pricing_archive INTO ls_pricing.
  INSERT ls_pricing INTO TABLE ct_pricing. " ← Hashed, sin sobrescribir
ENDLOOP.
```

### 7. No Manejar Excepciones de Archivo

**Problema:** Falla de infraestructura de archivo aborta cálculo completo

**Ejemplo:**
```abap
" ❌ INCORRECTO: Excepción se propaga, cálculo aborta
DATA(lt_vbap) = get_vbap_from_archive( ... ). " ← Lanza zcx_ca_archiving
```

**Solución:** TRY-CATCH, tratar archivo como best-effort
```abap
" ✅ CORRECTO: Falla de archivo no es crítica
TRY.
    DATA(lt_vbap) = get_vbap_from_archive( ... ).
  CATCH zcx_ca_archiving.
    " Loguear o ignorar: continuar con datos parciales
ENDTRY.
```

### 8. Cambiar INNER JOIN Sin Manejar Nulls

**Problema:** LEFT OUTER JOIN trae campos null, cálculos fallan

**Ejemplo:**
```abap
" Cambiado a LEFT OUTER JOIN
SELECT ... LEFT OUTER JOIN vbap AS pv ON ...

" ❌ INCORRECTO: Cálculo falla si pv~netwr es null
<fs>-total = <fs>-quantity * pv~netwr. " ← Propagación de null
```

**Solución:** Enriquecimiento condicional desde archivo
```abap
" Obtener datos con LEFT JOIN (puede tener nulls)
rt_data = get_data( ... ).

" Condicionalmente completar desde archivo
IF lv_use_archive = abap_true.
  enrich_vbap_from_archive( CHANGING ct_data = rt_data ).
ENDIF.

" Proteger cálculos
IF <fs>-netwr IS NOT INITIAL.
  <fs>-total = <fs>-quantity * <fs>-netwr.
ENDIF.
```

---

## 🎯 Reglas de Decisión Reusables

### Regla 1: Cuándo Cambiar INNER → LEFT OUTER JOIN

**SI** tabla es archivable **Y** campos son para enriquecimiento (no filtrado obligatorio)  
**ENTONCES** considerar cambiar INNER JOIN a LEFT OUTER JOIN

**Ejemplo:**
- VBAP archivable, NETWR/ARKTX para display → LEFT OUTER JOIN ✅
- BUT000 datos maestros, KUNNR para filtrado → INNER JOIN ✅

### Regla 2: Cuándo Extraer Método de Archivo

**SI** lógica de archivo >  50 líneas **O** necesita mapeo reverso  
**ENTONCES** extraer a método privado dedicado (fill_*_from_archive)

**Ejemplo:**
- Completado simple de campos (ARKTX, NETWR) → inline en enrich_*_from_archive ✅
- Mapeo complejo de pricing (VBAK→VBAP→KONV) → extraer a fill_pricing_from_archive ✅

### Regla 3: Cuándo Usar Mapas Determinísticos

**SI** se requiere lookup reverso (A→B, B→C, necesito A→C)  
**ENTONCES** construir mapas intermedios hasheados (uno por relación)

**Ejemplo:**
- KONV (tiene KNUMV+KPOSN) → necesito (VBELN+MATNR)
- Construir: mapa KNUMV→VBELN (desde VBAK) + mapa (VBELN+POSNR)→MATNR (desde VBAP)

### Regla 4: Cuándo Mover Métodos a PROTECTED

**SI** método es determinístico (sin DB, sin archivo) **Y** valioso para unit test  
**ENTONCES** mover de PRIVATE a PROTECTED

**Ejemplo:**
- needs_archive() → determinístico, testeable → PROTECTED ✅
- get_vbap_from_archive() → dependencia archivo, prueba integración → PRIVATE ✅

### Regla 5: Cuándo Usar Enrich vs Fill

**SI** SELECT base retorna filas con algunos campos iniciales  
**ENTONCES** usar enrich_*_from_archive (completar filas existentes)

**SI** prefetch pierde algunas claves completamente  
**ENTONCES** usar fill_*_from_archive (agregar entradas faltantes)

### Regla 6: Cuándo Lectura de Archivo Es Best-Effort

**SI** cálculo principal puede proceder con datos parciales  
**ENTONCES** TRY-CATCH lecturas archivo, continuar en excepción

**SI** datos de archivo son obligatorios para corrección  
**ENTONCES** propagar excepción, abortar cálculo

**Ejemplo:**
- Campo display ARKTX faltante → best-effort (mostrar en blanco) ✅
- NETWR para total de factura → obligatorio (abortar si falta) ⚠️

### Regla 7: Cuándo Optimizar con Prefetch

**SI** SELECT SINGLE en loop **Y** claves únicas < 1000  
**ENTONCES** prefetch con FOR ALL ENTRIES + hashed lookup

**SI** claves únicas > 10,000  
**ENTONCES** considerar chunking o SELECT basado en rangos

### Regla 8: Cuándo Escribir Unit Tests

**SI** método es determinístico (sin dependencias) **Y** crítico para negocio  
**ENTONCES** escribir ABAP Unit tests

**SI** método tiene dependencias DB/archivo  
**ENTONCES** escribir pruebas de integración (programas Z_TEST_*)

**Ejemplo:**
- needs_archive() → unit test ✅
- get_vbap_from_archive() → prueba integración ✅

### Regla 9: Cuándo Post-Filtrar en Memoria

**SI** campo de filtro NO está en infoestructura (solo catálogo)  
**ENTONCES** filtrar por campo indexable → post-filtrar en memoria

**Cómo verificar:** Transacción SARI → lista de campos de infoestructura

### Regla 10: Cuándo Priorizar Soporte de Archivo

**SI** fecha cutoff < 18 meses atrás **Y** usuarios necesitan datos históricos  
**ENTONCES** soporte de archiving es prioridad ALTA

**SI** fecha cutoff > 5 años atrás **Y** consultas históricas raras  
**ENTONCES** soporte de archiving es prioridad BAJA (puede no justificar esfuerzo)

---

## 📚 Referencia Rápida: Patrones de Código

### Patrón de Gating
```abap
DATA lv_cutoff TYPE sy-datum.
DATA lv_use_archive TYPE abap_bool.

lv_cutoff = zcl_ca_archiving_utility=>get_cutoff_date( ).
lv_use_archive = xsdbool( is_screen-p_hist = abap_true AND
                          lv_cutoff IS NOT INITIAL AND
                          needs_archive(lv_cutoff, is_screen-pperiodo) = abap_true ).

IF lv_use_archive = abap_true.
  " Lógica de archivo aquí
ENDIF.
```

### Patrón de Construcción de Filtros
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

### Patrón de Lectura de Archivo
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

### Patrón Prefetch + Hashed Lookup
```abap
" Extraer claves únicas
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

" Poblar tabla hashed
DATA lt_pricing TYPE tt_pricing.
LOOP AT lt_temp INTO DATA(ls_temp).
  INSERT VALUE #( vbeln = ls_temp-vbeln ... ) INTO TABLE lt_pricing.
ENDLOOP.

" Loop con lookup O(1)
LOOP AT ct_data ASSIGNING FIELD-SYMBOL(<fs>).
  READ TABLE lt_pricing INTO DATA(ls_pricing)
    WITH KEY vbeln = <fs>-vbeln matnr = <fs>-matnr kschl = 'ZPB2'.
  IF sy-subrc = 0.
    <fs>-price = ls_pricing-kbetr.
  ENDIF.
ENDLOOP.
```

### Patrón de Mapeo Reverso Determinístico
```abap
" Construir mapa 1: KNUMV → VBELN
DATA lt_knumv_to_vbeln TYPE tt_knumv_to_vbeln. " HASHED
LOOP AT lt_vbak INTO DATA(ls_vbak).
  INSERT VALUE #( knumv = ls_vbak-knumv vbeln = ls_vbak-vbeln )
         INTO TABLE lt_knumv_to_vbeln.
ENDLOOP.

" Construir mapa 2: (VBELN, POSNR) → MATNR
DATA lt_position_to_matnr TYPE tt_position_to_matnr. " HASHED
LOOP AT lt_vbap INTO DATA(ls_vbap).
  INSERT VALUE #( vbeln = ls_vbap-vbeln posnr = ls_vbap-posnr matnr = ls_vbap-matnr )
         INTO TABLE lt_position_to_matnr.
ENDLOOP.

" Lookup reverso
LOOP AT lt_konv INTO DATA(ls_konv).
  READ TABLE lt_knumv_to_vbeln INTO DATA(ls_map1)
    WITH KEY knumv = ls_konv-knumv.
  CHECK sy-subrc = 0.

  READ TABLE lt_position_to_matnr INTO DATA(ls_map2)
    WITH KEY vbeln = ls_map1-vbeln posnr = ls_konv-kposn.
  CHECK sy-subrc = 0.

  " Usar: ls_map1-vbeln, ls_map2-matnr, ls_konv-kbetr
ENDLOOP.
```

---

## 📝 Cómo Usar Esta Guía en Desarrollos Futuros

### Escenario 1: Nuevo reporte necesita datos históricos
1. Ir a **Cuándo Migrar desde SAP Query** → evaluar necesidad
2. Seguir **Checklist de Migración Fase 1-2** → planear arquitectura
3. Usar **Patrones de Código** → implementar gating + lectura archivo
4. Aplicar **Reglas de Decisión 1-10** → tomar decisiones de diseño
5. Revisar **Errores Comunes** → evitar errores conocidos

### Escenario 2: Clase existente necesita soporte de archivo
1. Ir a **Estrategia de Acceso a Datos** → analizar SELECTs
2. Aplicar **Regla de Decisión 1** → determinar cambios INNER vs LEFT JOIN
3. Seguir **Patrón General de Diseño de Archiving** → agregar triple gating
4. Usar **Patrón de Lectura de Archivo** → implementar métodos filter + read
5. Seguir **Estrategia de Testing** → validar con enfoque de 3 niveles

### Escenario 3: Problema de performance en código legacy
1. Ir a **Lineamientos de Performance** → identificar cuello de botella
2. Aplicar **Patrón de Prefetch** → eliminar SELECT SINGLE en loop
3. Usar **Patrón Hashed Lookup** → optimizar lookups
4. Agregar **Guards** → proteger FAE, evitar lecturas innecesarias de archivo

### Escenario 4: Lectura de archivo retorna 0 offsets
1. Ir a **Lecciones Técnicas Importantes** → entender generación de offsets
2. Ejecutar **SARI** → verificar que campo está en infoestructura
3. Aplicar **Patrón de 2 pasos** → filtrar por indexable + post-filtrar
4. Revisar **Error Común #1** → evitar filtros solo-catálogo

---

**Versión del Documento:** 1.0  
**Mantenimiento:** Actualizar con nuevos patrones a medida que se completen implementaciones adicionales  
**Feedback:** Documentar lecciones aprendidas de cada nueva implementación de archiving
