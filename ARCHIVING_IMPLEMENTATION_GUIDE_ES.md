# 📘 Guía de Implementación de Archiving en ABAP

**Versión:** 2.1  
**Última actualización:** 18 de marzo de 2026  
**Basada en:** Experiencia de implementación de ZCL_MM_FLETFACT_SERVICE, ZCL_PM_FACTORDENSERVICIO_ARC, y Z_TEST_VBFA_ARCHIVE

**Changelog:**
- **v2.1 (18-mar-2026):** Documentación de limitación arquitectural VBFA - solo disponible en SD_VBAK (no en RV_LIKP/SD_VBRK)
- **v2.0 (17-mar-2026):** Guía completa basada en implementaciones de producción  

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

## 🎨 Tipos Explícitos vs Genéricos en Archiving

### ⚠️ Problema Crítico con Tipos Genéricos

**Escenario:** Métodos de enriquecimiento con parámetros `TYPE STANDARD TABLE` (genérico) causan errores de compilación al intentar acceder campos.

```abap
" ❌ INCORRECTO: Tipo genérico en firma de método
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE STANDARD TABLE.  "← Tipo genérico

" Al implementar:
METHOD enrich_vbrk_from_archive.
  " ❌ Error: "Tipo indicado no tiene componente con nombre 'VBELN'"
  IF line_exists( ct_interna1[ vbeln = <fs_vbrk_arch>-vbeln ] ).
    CONTINUE.
  ENDIF.
  
  " ❌ Error: "Objeto de datos no tiene componente NAME1"
  <fs_interna1_new>-name1 = ls_kna1-name1.
ENDMETHOD.
```

**Causa raíz:** ABAP no puede resolver nombres de campos para tablas genéricas en tiempo de compilación.

### ✅ Solución: Tipos Explícitos en PRIVATE SECTION

**Estrategia:** Extraer estructuras de datos de `get_data()` a nivel de clase y usar en firmas de métodos.

#### Paso 1: Definir Tipos en PRIVATE SECTION

```abap
PRIVATE SECTION.
  " ▼ Tipos para tablas de trabajo (extraídos de get_data)
  
  " Estructura de tabla interna #1 (VBRK - facturas)
  " Incluye todos los campos del SELECT de VBRK + campos de JOINs
  TYPES: BEGIN OF ty_interna1,
           vbeln TYPE vbrk-vbeln,
           fkart TYPE vbrk-fkart,
           fktyp TYPE vbrk-fktyp,
           vbtyp TYPE vbrk-vbtyp,
           waerk TYPE vbrk-waerk,
           vkorg TYPE vbrk-vkorg,
           knumv TYPE vbrk-knumv,
           fkdat TYPE vbrk-fkdat,
           ...
           name1 TYPE kna1-name1,  "← Campo de JOIN con KNA1
         END OF ty_interna1.
  " Tipo de tabla para ty_interna1
  TYPES tt_interna1 TYPE STANDARD TABLE OF ty_interna1 WITH DEFAULT KEY.

  " Estructura de tabla interna #2 (VBRP + campos relacionados)
  " Incluye campos de VBRP, VBRK (knumv, waerk), VIAUFKS (objnr)
  TYPES: BEGIN OF ty_interna2,
           vbeln     TYPE vbrp-vbeln,
           posnr     TYPE vbrp-posnr,
           fkimg     TYPE vbrp-fkimg,
           matnr     TYPE vbrp-matnr,
           netwr     TYPE vbrp-netwr,
           ...
           knumv     TYPE vbrk-knumv,   "← Campo de VBRK (JOIN)
           waerk     TYPE vbrk-waerk,   "← Campo de VBRK (JOIN)
           objnr     TYPE viaufks-objnr, "← Campo de VIAUFKS (JOIN)
         END OF ty_interna2.
  TYPES tt_interna2 TYPE STANDARD TABLE OF ty_interna2 WITH DEFAULT KEY.
```

**Principios de diseño:**
- ✅ **Usar `TYPE tabla-campo`** para compatibilidad exacta con columnas DB
- ✅ **Incluir campos de JOINs** en la estructura (no solo tabla principal)
- ✅ **Documentar origen** de cada campo (comentario línea)
- ✅ **Crear tabla type** (`tt_*`) para cada estructura

#### Paso 2: Usar Tipos Explícitos en Firmas de Métodos

```abap
PRIVATE SECTION.
  " ▼ Métodos de enriquecimiento desde archive
  
  "! Enriquecer lt_interna1 (VBRK) desde archive
  "! Lee VBRK+VBRP archivado, combina con BD (sin duplicados)
  "! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out)
  METHODS enrich_vbrk_from_archive
    CHANGING ct_interna1 TYPE tt_interna1.  "← Tipo explícito

  "! Enriquecer lt_datosinterna2 (VBRP) desde archive
  "! @parameter ct_interna1      | Tabla VBRK (para lookup knumv/waerk)
  "! @parameter ct_datosinterna2 | Tabla VBRP a enriquecer (in/out)
  METHODS enrich_vbrp_from_archive
    CHANGING ct_interna1      TYPE tt_interna1    "← Tipo explícito
             ct_datosinterna2 TYPE tt_interna2.   "← Tipo explícito
```

**Beneficios inmediatos:**
- ✅ Validación de tipos en compilación
- ✅ Acceso directo a campos (sin `ASSIGN COMPONENT`)
- ✅ Autocompletado en IDE
- ✅ Errores detectados temprano (no en runtime)

#### Paso 3: Declarar Variables Explícitamente en get_data()

```abap
METHOD get_data.
  " ▼ NUEVAS PRÁCTICAS: Declaraciones explícitas de tablas de trabajo
  " Antes: @DATA(lt_interna1) - tipo inferido (genérico)
  " Ahora: DATA lt_interna1 TYPE tt_interna1 - tipo explícito
  " Beneficio: Permite pasar estas tablas a métodos con parámetros tipificados
  
  DATA lt_interna1       TYPE tt_interna1.
  DATA lt_datosinterna2  TYPE tt_interna2.
  
  " SELECT con mapeo por nombre (más robusto que por posición)
  SELECT vbrk~vbeln, vbrk~fkart, ..., kna1~name1
    INTO CORRESPONDING FIELDS OF TABLE @lt_interna1
    FROM vbrk
      INNER JOIN kna1 ON kna1~kunnr = vbrk~kunrg
    WHERE ...
  
  " Enriquecimiento condicional con tipos explícitos
  IF me->gv_use_archive = abap_true.
    enrich_vbrk_from_archive( CHANGING ct_interna1 = lt_interna1 ).
  ENDIF.
ENDMETHOD.
```

**Por qué usar `INTO CORRESPONDING FIELDS OF TABLE`:**
- ✅ Mapeo por **nombre de campo** (no por posición en SELECT)
- ✅ Más robusto ante cambios en orden de campos SELECT
- ✅ Claramente indica mapeo dinámico vs estático

#### Paso 4: Implementación Limpia con Tipos Explícitos

```abap
METHOD enrich_vbrk_from_archive.
  DATA lt_vbrk_arch TYPE STANDARD TABLE OF vbrk.
  DATA lt_kna1_lookup TYPE STANDARD TABLE OF kna1.

  " Construir filtros y leer desde archivo
  DATA(lt_filters_vbrk) = build_archive_filters_vbrk( ... ).
  get_vbrk_vbrp_from_archive_arc( EXPORTING it_filters_vbrk = lt_filters_vbrk
                                  IMPORTING et_vbrk = lt_vbrk_arch ... ).

  " Prefetch KNA1 para NAME1
  SELECT kunnr, name1 FROM kna1
    FOR ALL ENTRIES IN @lt_vbrk_arch
    WHERE kunnr = @lt_vbrk_arch-kunrg
    INTO TABLE @lt_kna1_lookup.
  SORT lt_kna1_lookup BY kunnr.

  " ✅ Enriquecimiento con acceso directo a campos
  LOOP AT lt_vbrk_arch ASSIGNING FIELD-SYMBOL(<fs_vbrk_arch>).
    " ✅ line_exists con tipo explícito - compila sin errores
    IF line_exists( ct_interna1[ vbeln = <fs_vbrk_arch>-vbeln ] ).
      CONTINUE.
    ENDIF.

    APPEND INITIAL LINE TO ct_interna1 ASSIGNING FIELD-SYMBOL(<fs_interna1_new>).
    MOVE-CORRESPONDING <fs_vbrk_arch> TO <fs_interna1_new>.

    READ TABLE lt_kna1_lookup INTO DATA(ls_kna1)
         WITH KEY kunnr = <fs_vbrk_arch>-kunrg BINARY SEARCH.
    IF sy-subrc = 0.
      " ✅ Acceso directo a campo - compila sin errores
      <fs_interna1_new>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.
ENDMETHOD.
```

### 📊 Comparación: Genérico vs Explícito

| Aspecto | Tipo Genérico (`STANDARD TABLE`) | Tipo Explícito (`tt_interna1`) |
|---------|-----------------------------------|----------------------------------|
| **Compilación** | ❌ Errores en acceso a campos | ✅ Validación completa |
| **Performance** | ⚠️ Casting dinámico en runtime | ✅ Acceso directo optimizado |
| **Mantenibilidad** | ❌ Errores detectados tarde | ✅ Errores en compilación |
| **IDE Support** | ❌ Sin autocompletado | ✅ Autocompletado completo |
| **Testabilidad** | ⚠️ Difícil crear tipos de prueba | ✅ Tipos reutilizables |
| **Documentación** | ❌ Estructura implícita | ✅ Estructura autodocumentada |

### 🎯 Cuándo Usar Cada Tipo

| Escenario | Tipo Recomendado | Justificación |
|-----------|------------------|---------------|
| **Parámetros de métodos que acceden campos** | `TYPE tt_interna1` | Validación compilación |
| **Variables locales simples** | `DATA(var)` inferido | Menos verbose |
| **Tablas compartidas entre métodos** | `TYPE tt_*` explícito | Garantiza compatibilidad |
| **Factory/Framework outputs** | `TYPE STANDARD TABLE` genérico | Framework retorna dinámico |
| **Tablas temporales de 1 uso** | `DATA(lt_temp)` inferido | Scope local limitado |

### ⚠️ Errores Comunes y Soluciones

#### Error 1: Tipos Genéricos Incorrectos

```abap
" ❌ INCORRECTO: Tipo genérico sin referencia a tabla
TYPES: BEGIN OF ty_interna1,
         vbeln TYPE vbeln,    "← Puede no coincidir con conversiones
         name1 TYPE char35,   "← Longitud puede variar
       END OF ty_interna1.

" ✅ CORRECTO: Referencias exactas a tablas DB
TYPES: BEGIN OF ty_interna1,
         vbeln TYPE vbrk-vbeln,   "← Exacto al tipo columna
         name1 TYPE kna1-name1,   "← De tabla relacionada
       END OF ty_interna1.
```

#### Error 2: Campos de Sistema Incorrectos

```abap
" ❌ INCORRECTO: Tipos de sistema no existen
zuonr TYPE zuonr,   "← Tipo no existe en sistema
mwsbk TYPE mwsbk,   "← Tipo no existe en sistema

" ✅ CORRECTO: Usar tipo base o referencia tabla
zuonr TYPE vbrk-zuonr,  "← O TYPE dzuonr (tipo base)
mwsbk TYPE vbrk-mwsbk,  "← O TYPE wrbtr (tipo base)
```

#### Error 3: Intentar Leer VBFA desde Objetos Incorrectos

```abap
" ❌ INCORRECTO: Intentar crear constantes custom para RV_LIKP o SD_VBRK
" NO funciona porque VBFA no existe físicamente en esos archivos

" ✅ CORRECTO: Usar gc_vbfa (internamente usa SD_VBAK)
lo_factory->get_instance( 
  iv_object = zcl_ca_archiving_factory=>gc_vbfa
  it_filter_options = lt_filters ).

lo_factory->get_data( 
  EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
  IMPORTING et_data = lt_vbfa ).
" → lt_vbfa contiene datos ✅

" Post-filtrar por documento destino si se necesita
DELETE lt_vbfa WHERE vbeln NOT IN lr_vbeln_destino.  " Ej: entregas o facturas
DELETE lt_vbfa WHERE vbtyp_n NOT IN lr_vbtyp_n.      " Ej: tipo 'J' (entregas)
```

**Causa raíz:** VBFA se archiva SOLO con documento de origen (VBAK) para evitar duplicación. La constante `gc_vbfa` está configurada internamente para leer desde SD_VBAK. Ver sección "Limitaciones Conocidas" en capítulo "Patrón de Lectura de Archivo".

### 📝 Convenciones de Documentación

**Comentarios estándar para TYPES (NO ABAPDoc):**

```abap
" ✅ CORRECTO: Comentarios estándar (") para TYPES en PRIVATE SECTION
PRIVATE SECTION.
  " Estructura de tabla interna #1 (VBRK - facturas)
  " Incluye todos los campos del SELECT de VBRK + NAME1 de KNA1
  " Usado en get_data() y en enrich_vbrk_from_archive()
  TYPES: BEGIN OF ty_interna1,
           ...
         END OF ty_interna1.

" ❌ INCORRECTO: ABAPDoc ("!) solo para métodos/atributos/constantes
"! Estructura de tabla interna #1  "← Error de compilación
TYPES: BEGIN OF ty_interna1,
```

**ABAPDoc completo para métodos:**

```abap
"! Enriquecer lt_interna1 (VBRK) desde archive
"! Lee VBRK+VBRP archivado, combina con BD (sin duplicados), enriquece con KNA1.
"! Almacena lt_vbrp_arch en atributo de instancia para uso posterior.
"! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out)
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE tt_interna1.
```

### 📦 Plantilla Reutilizable

**Para futuros desarrollos de archiving:**

```abap
" ═══════════════════════════════════════════════════════════════
" PASO 1: Definir tipos en PRIVATE SECTION
" ═══════════════════════════════════════════════════════════════
PRIVATE SECTION.
  " Estructura principal de datos (incluir campos de JOINs)
  TYPES: BEGIN OF ty_main_data,
           " Campos de tabla principal
           campo1 TYPE tabla1-campo1,
           campo2 TYPE tabla1-campo2,
           " Campos de tablas relacionadas (JOINs)
           campo3 TYPE tabla2-campo3,
           campo4 TYPE tabla3-campo4,
         END OF ty_main_data.
  TYPES tt_main_data TYPE STANDARD TABLE OF ty_main_data WITH DEFAULT KEY.

" ═══════════════════════════════════════════════════════════════
" PASO 2: Usar en firmas de métodos
" ═══════════════════════════════════════════════════════════════
PRIVATE SECTION.
  "! Enriquecer datos desde archivo
  "! @parameter ct_data | Tabla a enriquecer (in/out)
  METHODS enrich_from_archive
    CHANGING ct_data TYPE tt_main_data.

" ═══════════════════════════════════════════════════════════════
" PASO 3: Declarar en método principal
" ═══════════════════════════════════════════════════════════════
METHOD get_data.
  DATA lt_data TYPE tt_main_data.
  
  SELECT campo1, campo2, campo3, campo4
    INTO CORRESPONDING FIELDS OF TABLE @lt_data
    FROM tabla1
      LEFT OUTER JOIN tabla2 ON ...
      LEFT OUTER JOIN tabla3 ON ...
    WHERE ...
  
  IF gv_use_archive = abap_true.
    enrich_from_archive( CHANGING ct_data = lt_data ).
  ENDIF.
ENDMETHOD.

" ═══════════════════════════════════════════════════════════════
" PASO 4: Implementar con acceso directo a campos
" ═══════════════════════════════════════════════════════════════
METHOD enrich_from_archive.
  DATA lt_arch TYPE STANDARD TABLE OF tabla1.
  
  " Construir filtros y leer archivo
  DATA(lt_filters) = build_archive_filters( ... ).
  get_data_from_archive( EXPORTING it_filters = lt_filters
                         IMPORTING et_data = lt_arch ).
  
  " Enriquecer sin workarounds dinámicos
  LOOP AT lt_arch ASSIGNING FIELD-SYMBOL(<fs_arch>).
    IF line_exists( ct_data[ campo1 = <fs_arch>-campo1 ] ).
      CONTINUE.  "← Acceso directo, sin ASSIGN COMPONENT
    ENDIF.
    
    APPEND INITIAL LINE TO ct_data ASSIGNING FIELD-SYMBOL(<fs_new>).
    MOVE-CORRESPONDING <fs_arch> TO <fs_new>.
    <fs_new>-campo3 = valor_calculado.  "← Acceso directo
  ENDLOOP.
ENDMETHOD.
```

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

### 🏭 Entendiendo el Framework Factory

#### Arquitectura del Factory Pattern

```
┌─────────────────────────────────────────────────────────────┐
│ ZCL_CA_ARCHIVING_FACTORY (Singleton)                        │
│  - Instanciación centralizada                               │
│  - Gestión de objetos de archivo                            │
│  - Constantes gc_vbak, gc_vbap, gc_vbrk, gc_konv            │
└─────────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ ZCL_CA_ARCHIVING_CTRL (Controller)                          │
│  - Generación de offsets desde filtros                      │
│  - Lectura de datos desde archivos físicos                  │
│  - Extracción y parseo de estructuras                       │
└─────────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ ZCL_CA_ARCHIVING_QUERY_CTRL (Query Controller)              │
│  - Construcción de filtros desde rangos ABAP                │
│  - Validación de campos indexables                          │
│  - Gestión de infoestructuras                               │
└─────────────────────────────────────────────────────────────┘
```

#### 🔑 Constantes de Objetos de Archivo

**Ubicación:** `ZCL_CA_ARCHIVING_FACTORY` (constantes públicas)

| Constante | Valor | Objeto Archive | Tabla(s) Principal(es) | Estado |
|-----------|-------|----------------|------------------------|--------|
| `gc_vbak` | 'SD_VBAK' | Pedido ventas | VBAK (header) | ✅ Funcional |
| `gc_vbap` | 'SD_VBAP' | Posiciones pedido | VBAP (items) | ✅ Funcional |
| `gc_vbrk` | 'SD_VBRK' | Factura ventas | VBRK (header) + VBRP (items) | ✅ Funcional |
| `gc_vbrp` | 'SD_VBRP' | Posiciones factura | VBRP (items) | ✅ Funcional |
| `gc_vbrk_konv` | 'SD_VBRK_KONV' | Pricing facturas | KONV (vía VBRK) | ✅ Funcional |
| `gc_konv` | 'SD_KONV' | Condiciones pricing | KONV (directo) | ✅ Funcional |
| `gc_vbfa` | 'SD_VBFA' | Flujo documentos | VBFA (desde SD_VBAK) | ✅ Funcional* |

**⚠️ Notas importantes:**
- `gc_vbrk` retorna **VBRK Y VBRP** juntos (lectura jerárquica)
- **\* Limitación VBFA:** `gc_vbfa` internamente lee desde SD_VBAK. VBFA no existe físicamente en archivos RV_LIKP ni SD_VBRK (diseño SAP). Ver sección "Limitaciones Conocidas" más abajo.

---

### ⚠️ Limitaciones Conocidas de Objetos de Archivo

#### Restricción Arquitectural: VBFA (Flujo de Documentos)

**📌 Hallazgo Crítico (Marzo 2026):**  
La tabla `VBFA` (flujo de documentos SD) **solo existe físicamente en archivos de SD_VBAK**, NO en RV_LIKP (entregas) ni SD_VBRK (facturas).

**✅ Constante funcional (única disponible):**
- `gc_vbfa = 'SD_VBFA'` → ✅ Lee VBFA desde SD_VBAK exitosamente

**📝 Nota de diseño:**
La constante `gc_vbfa` internamente usa el objeto SD_VBAK (pedidos) para extraer VBFA. No intente crear constantes para leer VBFA desde RV_LIKP (entregas) o SD_VBRK (facturas) - no funcionará por diseño SAP.

**🔍 Evidencia de Debugging (QA - Marzo 2026):**

Debugging de lectura VBFA desde diferentes objetos:
```abap
" ✅ Constante gc_vbfa (lee desde SD_VBAK) - EXITOSO
lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbfa
                          it_filter_options = lt_filters ).
lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
                      IMPORTING et_data = lt_vbfa ).
" → lt_vbfa tiene registros ✅ (internamente usa SD_VBAK/SAP_DRB_VBAK_02)
```

**Traza de debugging confirmó:**
1. ✅ Filtros construidos correctamente
2. ✅ Archivo de archivo encontrado
3. ✅ Offsets generados exitosamente
4. ✅ `ARCHIVE_READ_OBJECT` abre archivo sin error
5. ❌ `ARCHIVE_GET_TABLE` retorna vacío para VBFA (sin excepción)

**🧠 Causa Raíz (Diseño Arquitecural SAP):**

VBFA **no se archiva** con entregas (RV_LIKP) ni facturas (SD_VBRK) porque:

1. **VBAK es el "documento raíz"** en el flujo SD:
   ```
   VBAK (Pedido) → LIKP (Entrega) → VBRK (Factura)
   ```

2. **VBFA registra el flujo COMPLETO** desde origen:
   ```
   VBFA contiene:
   - VBAK → LIKP (pedido → entrega)
   - LIKP → VBRK (entrega → factura)
   - VBAK → VBRK (pedido → factura)
   ```

3. **SAP evita duplicación** de VBFA:
   - Si archivara VBFA con LIKP **Y** con VBRK, cada relación estaría **duplicada**
   - Estrategia SAP: VBFA se archiva solo con **documento de origen** (VBAK)
   - Esto reduce espacio y evita inconsistencias

4. **SARA muestra VBFA en todos los catálogos:**
   - Catálogo de RV_LIKP **incluye** definición de campos de VBFA
   - Catálogo de SD_VBRK **incluye** definición de campos de VBFA
   - PERO: Campo en catálogo ≠ tabla en archivo físico
   - Solo SD_VBAK contiene VBFA **físicamente** en los archivos

**✅ Patrón Correcto para Leer VBFA:**

```abap
METHOD get_vbfa_from_archive.
  " ═══════════════════════════════════════════════════════════════
  " ✅ Usar gc_vbfa (internamente lee desde SD_VBAK)
  " ═══════════════════════════════════════════════════════════════
  DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
  DATA lt_vbfa_arch TYPE STANDARD TABLE OF vbfa.
  
  lo_factory = NEW zcl_ca_archiving_factory( ).
  
  " Construir filtros usando campos indexables de SAP_DRB_VBAK_02
  DATA(lt_filters) = build_archive_filters_vbfa( 
    ir_vbeln = lr_vbeln_origen  " ⚠️ VBELN del documento ORIGEN (pedido)
  ).
  
  lo_factory->get_instance( 
    iv_object         = zcl_ca_archiving_factory=>gc_vbfa
    it_filter_options = lt_filters ).
  
  lo_factory->get_data( 
    EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
    IMPORTING et_data   = lt_vbfa_arch ).
  
  " ═══════════════════════════════════════════════════════════════
  " Post-filtrado: Filtrar por documento destino si es necesario
  " ═══════════════════════════════════════════════════════════════
  " ⚠️ Campos NO indexables: VBELV, VBTYP_V, VBTYP_N, POSNV, POSNN
  " Requieren filtrado en memoria después de extraer desde archivo
  
  IF ir_vbeln_destino IS NOT INITIAL.
    DELETE lt_vbfa_arch WHERE vbeln NOT IN ir_vbeln_destino.
  ENDIF.
  
  IF ir_vbtyp_n IS NOT INITIAL.
    DELETE lt_vbfa_arch WHERE vbtyp_n NOT IN ir_vbtyp_n.  " Tipo doc destino
  ENDIF.
  
  rt_vbfa = lt_vbfa_arch.
ENDMETHOD.
```

**⚠️ Importante:**

```abap
" ⚠️ No intente crear variantes de gc_vbfa para otros objetos
" gc_vbfa ya está configurado internamente para usar SD_VBAK
" Cualquier intento de leer desde RV_LIKP o SD_VBRK no funcionará

" ✅ Solo gc_vbfa funciona (internamente usa SD_VBAK)
lo_factory->get_instance( 
  iv_object = zcl_ca_archiving_factory=>gc_vbfa  " ← NO FUNCIONA
  it_filter_options = lt_filters ).

lo_factory->get_data( 
  EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
  IMPORTING et_data = lt_vbfa_arch ).
" → lt_vbfa_arch estará VACÍO (no se levanta error)
```

**📖 Referencia: Programa de Test Corregido**

Ver programa `Z_TEST_VBFA_ARCHIVE` en el workspace para implementación completa:
- Configurado exclusivamente para SD_VBAK
- Incluye post-filtrado para campos no indexables
- Documentación técnica en header del programa

**📝 Campos Indexables de VBFA (SAP_DRB_VBAK_02):**

Solo disponible para filtrado en archivo:
- `VBELN` (documento origen - del pedido VBAK) ✅

Requieren post-filtrado en memoria:
- `VBELV` (documento precedente) ❌ No indexable
- `VBTYP_V` (tipo documento precedente) ❌ No indexable
- `VBTYP_N` (tipo documento subsecuente) ❌ No indexable
- `POSNV` (posición precedente) ❌ No indexable
- `POSNN` (posición subsecuente) ❌ No indexable

**🎯 Recomendaciones:**

1. **Siempre usar `gc_vbfa`** para leer VBFA desde archivos
2. **NO crear variantes** como gc_vbfa_likp o gc_vbfa_vbrk (no funcionarán)
3. Filtrar por **VBELN del pedido origen** (único campo indexable)
4. Implementar **post-filtrado** para VBELV, VBTYP_V, VBTYP_N en memoria
5. Si necesitas VBFA de entregas/facturas: leer desde VBAK y filtrar por documento destino

**⚠️ Nota:** Esta limitación es **diseño estándar SAP**, no un bug del framework.

---

#### Uso del Patrón Factory - Paso a Paso

**Estructura de llamadas estándar:**

```abap
METHOD get_<tabla>_from_archive.
  " ═══════════════════════════════════════════════════════════════
  " PASO 1: Instanciar factory (singleton)
  " ═══════════════════════════════════════════════════════════════
  DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
  lo_factory = NEW zcl_ca_archiving_factory( ).

  " ═══════════════════════════════════════════════════════════════
  " PASO 2: Construir filtros (solo campos indexables)
  " ═══════════════════════════════════════════════════════════════
  DATA(lt_filters) = build_archive_filters_<tabla>( 
    ir_campo1 = lr_campo1
    ir_campo2 = lr_campo2 ).

  " ═══════════════════════════════════════════════════════════════
  " PASO 3: get_instance() - Genera offsets desde filtros
  " ═══════════════════════════════════════════════════════════════
  " ¿Qué hace internamente?
  " 1. Validar que iv_object existe (gc_vbak, gc_vbap, etc.)
  " 2. Construir SQL dinámico contra infoestructura (GENTAB)
  " 3. Ejecutar query → genera lista de OFFSETS (posiciones en archivo)
  " 4. Retornar controller con offsets precalculados
  
  lo_factory->get_instance( 
    iv_object         = zcl_ca_archiving_factory=>gc_vbap
    it_filter_options = lt_filters ).

  " ═══════════════════════════════════════════════════════════════
  " PASO 4: get_data() - Extrae datos desde offsets
  " ═══════════════════════════════════════════════════════════════
  " ¿Qué hace internamente?
  " 1. Usa offsets precalculados de get_instance()
  " 2. Lee archivos físicos desde disco/storage
  " 3. Parsea estructuras binarias
  " 4. Retorna tabla TIPADA según iv_object
  
  DATA lt_vbap_arch TYPE STANDARD TABLE OF vbap.
  lo_factory->get_data( 
    EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbap
    IMPORTING et_data   = lt_vbap_arch ).  "← VBAP tipado directamente
ENDMETHOD.
```

#### 🔍 Cómo Funciona get_instance() Internamente

**Cadena de llamadas:**

```
get_instance(iv_object, it_filters)
  └─> ZCL_CA_ARCHIVING_CTRL->get_archiving_keys(it_filters)
        └─> Construye SELECT dinámico desde it_filters
        └─> Valida campos contra GENTAB (infoestructura)
        └─> Ejecuta query: SELECT FROM <infoestructura> WHERE ...
        └─> Retorna tabla de OFFSETS (posiciones físicas en archivo)
```

**Pseudo-código interno:**

```abap
METHOD get_archiving_keys.
  " 1. Construir lista dinámica de campos desde infoestructura
  LOOP AT it_filters INTO ls_filter.
    " Validar: ¿campo existe en GENTAB-TABNAME?
    IF campo_no_en_infoestructura( ls_filter-field_name ).
      " ❌ Campo no indexable → ignorado
      CONTINUE.
    ENDIF.
    
    " ✅ Campo indexable → agregar a WHERE clause
    APPEND ls_filter TO lt_where_clause.
  ENDLOOP.
  
  " 2. Ejecutar SELECT contra infoestructura
  SELECT archiv_key, offset_ref
    FROM (gv_infoestructura_table)  " ej: SAP_DRB_VBAK_02
    WHERE (lt_where_clause)
    INTO TABLE rt_offsets.
  
  " 3. Retornar offsets (identificadores únicos de registros archivados)
  RETURN rt_offsets.
ENDMETHOD.
```

**🚨 RESTRICCIÓN CRÍTICA:**  
Solo campos que **existen en GENTAB** (tabla de infoestructura) pueden generar offsets.  
Campos que existen solo en el **catálogo** (tabla original) **NO FUNCIONAN** para filtrado.

#### 🔍 Cómo Funciona get_data() Internamente

**Pseudo-código interno:**

```abap
METHOD get_data.
  " 1. Obtener offsets de instancia actual
  DATA(lt_offsets) = me->mt_archive_keys.  " Precalculados en get_instance()
  
  " 2. Leer archivos físicos usando offsets
  LOOP AT lt_offsets INTO ls_offset.
    " Abrir archivo en posición específica
    OPEN DATASET lv_archive_file FOR INPUT AT POSITION ls_offset-offset_ref.
    
    " Parsear estructura según iv_object
    CASE iv_object.
      WHEN gc_vbap.
        READ DATASET INTO ls_vbap.  " Parseo binario → VBAP
        APPEND ls_vbap TO et_data.
      WHEN gc_vbrk.
        READ DATASET INTO ls_vbrk.  " Parseo binario → VBRK
        READ DATASET INTO lt_vbrp.  " Lectura jerárquica → VBRP
        APPEND ls_vbrk TO et_data.
    ENDCASE.
  ENDLOOP.
  
  " 3. Retornar tabla tipada
  RETURN et_data.  " STANDARD TABLE OF vbap/vbrk/etc.
ENDMETHOD.
```

**Ventaja:** `et_data` retorna tabla **DIRECTAMENTE TIPADA** según `iv_object`. No hay "tabla genérica" que requiera ASSIGN CASTING.

#### ❌ Anti-Patrón: ASSIGN CASTING Innecesario

**Error común al no entender el factory:**

```abap
" ❌ INCORRECTO: Intentar separar tabla genérica con ASSIGN CASTING
DATA lt_archive_data TYPE TABLE OF REF TO data.
lo_factory->get_data( ... IMPORTING et_data = lt_archive_data ).

LOOP AT lt_archive_data ASSIGNING <ls_archive>.
  ASSIGN <ls_archive>->* TO <ls_vbrk> CASTING TYPE vbrk.
  APPEND <ls_vbrk> TO lt_vbrk_arch.
  
  ASSIGN <ls_archive>->* TO <ls_vbrp> CASTING TYPE vbrp.
  APPEND <ls_vbrp> TO lt_vbrp_arch.
ENDLOOP.
```

**Por qué es innecesario:**
- Factory **YA retorna tabla tipada** según `iv_object`
- Para leer VBRK + VBRP: hacer **dos llamadas separadas**
- No hay procesamiento "genérico" que requiera ASSIGN CASTING

#### ✅ Patrón Correcto: Lecturas Separadas

**Para leer múltiples tablas del mismo objeto de archivo:**

```abap
" ✅ CORRECTO: Dos lecturas separadas para VBRK y VBRP
METHOD get_vbrk_vbrp_from_archive_arc.
  DATA lo_factory TYPE REF TO zcl_ca_archiving_factory.
  DATA lt_vbrk_arch TYPE STANDARD TABLE OF vbrk.
  DATA lt_vbrp_arch TYPE STANDARD TABLE OF vbrp.
  
  lo_factory = NEW zcl_ca_archiving_factory( ).
  
  " ═══════════════════════════════════════════════════════════════
  " Lectura 1: VBRK (headers)
  " ═══════════════════════════════════════════════════════════════
  lo_factory->get_instance( iv_object = gc_vbrk
                            it_filter_options = it_filters_vbrk ).
  lo_factory->get_data( EXPORTING iv_object = gc_vbrk
                        IMPORTING et_data = lt_vbrk_arch ).
  
  " ═══════════════════════════════════════════════════════════════
  " Lectura 2: VBRP (items)
  " ═══════════════════════════════════════════════════════════════
  lo_factory->get_instance( iv_object = gc_vbrp
                            it_filter_options = it_filters_vbrp ).
  lo_factory->get_data( EXPORTING iv_object = gc_vbrp
                        IMPORTING et_data = lt_vbrp_arch ).
  
  " Retornar ambas tablas tipadas
  et_vbrk = lt_vbrk_arch.
  et_vbrp = lt_vbrp_arch.
ENDMETHOD.
```

**Alternativa para objetos jerárquicos (SD_VBRK incluye VBRP):**

```abap
" ✅ CORRECTO: Usar gc_vbrk que retorna jerárquico
lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbrk
                          it_filter_options = lt_filters ).

" Solo leer VBRK (VBRP viene incluido en estructura jerárquica)
lo_factory->get_data( EXPORTING iv_object = gc_vbrk
                      IMPORTING et_data = lt_vbrk_with_items ).

" ⚠️ Nota: et_data puede contener nested tables
" Necesitas extraer VBRP desde estructura jerárquica si se requiere tabla plana
```

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

## 🔄 Refactorización: De Inline a Métodos Encapsulados

### Problema: Código Inline Excesivo en get_data()

**Síntoma común:**  
Método `get_data()` crece a 800-1,000+ líneas con lógica de archiving mezclada.

```abap
" ❌ ANTI-PATRÓN: Todo inline en get_data()
METHOD get_data.
  " SELECT base (50 líneas)
  SELECT ... INTO TABLE @lt_interna1 ...
  
  " ❌ Bloque archivo VBRK inline (47 líneas)
  IF gv_use_archive = abap_true.
    DATA lt_vbrk_arch TYPE STANDARD TABLE OF vbrk.
    DATA lt_vbrp_arch TYPE STANDARD TABLE OF vbrp.
    DATA lt_kna1_lookup TYPE STANDARD TABLE OF kna1.
    
    DATA(lt_filters_vbrk) = build_archive_filters_vbrk( ... ).
    get_vbrk_vbrp_from_archive_arc( ... ).
    
    SELECT kunnr, name1 FROM kna1
      FOR ALL ENTRIES IN @lt_vbrk_arch
      WHERE kunnr = @lt_vbrk_arch-kunrg
      INTO TABLE @lt_kna1_lookup.
    SORT lt_kna1_lookup BY kunnr.
    
    LOOP AT lt_vbrk_arch ASSIGNING FIELD-SYMBOL(<fs_vbrk_arch>).
      IF line_exists( lt_interna1[ vbeln = <fs_vbrk_arch>-vbeln ] ).
        CONTINUE.
      ENDIF.
      APPEND INITIAL LINE TO lt_interna1 ASSIGNING FIELD-SYMBOL(<fs_new>).
      MOVE-CORRESPONDING <fs_vbrk_arch> TO <fs_new>.
      READ TABLE lt_kna1_lookup...
      <fs_new>-name1 = ls_kna1-name1.
    ENDLOOP.
    
    gt_vbrp_arch_backup = lt_vbrp_arch.
  ENDIF.
  
  " ❌ Bloque archivo VBRP inline (58 líneas)
  IF gv_use_archive = abap_true.
    DATA lt_viaufks_lookup TYPE STANDARD TABLE OF viaufks.
    IF gt_vbrp_arch_backup IS INITIAL. RETURN. ENDIF.
    
    SELECT aufnr, objnr FROM viaufks
      FOR ALL ENTRIES IN @gt_vbrp_arch_backup
      WHERE aufnr = @gt_vbrp_arch_backup-aufnr ...
    
    LOOP AT gt_vbrp_arch_backup...
      " 40+ líneas de lógica de enriquecimiento
    ENDLOOP.
  ENDIF.
  
  " Más lógica inline... (600+ líneas adicionales)
ENDMETHOD.
```

**Problemas:**
- ❌ Método gigante (1,000+ líneas) difícil de entender
- ❌ Lógica de archiving mezclada con lógica de negocio
- ❌ Difícil de testear (demasiadas responsabilidades)
- ❌ Duplicación de patrones (SELECT FOR ALL ENTRIES + lookup)

### ✅ Solución: Extraer a Métodos Privados Encapsulados

**Estrategia de refactorización:**

#### Paso 1: Identificar Bloques Cohesivos

Buscar en `get_data()`:
- Bloques `IF gv_use_archive = abap_true` de 20+ líneas
- Patrones repetitivos (prefetch + lookup + enrichment)
- Lógica que opera sobre tabla específica (VBRK, VBRP, etc.)

#### Paso 2: Crear Métodos Privados con Tipos Explícitos

```abap
PRIVATE SECTION.
  "! Enriquecer lt_interna1 (VBRK) desde archive
  "! Lee VBRK+VBRP archivado, combina con BD (sin duplicados), enriquece con KNA1.
  "! Almacena lt_vbrp_arch en atributo para uso posterior.
  "! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out)
  METHODS enrich_vbrk_from_archive
    CHANGING ct_interna1 TYPE tt_interna1.

  "! Enriquecer lt_datosinterna2 (VBRP) desde archive
  "! Usa gt_vbrp_arch_backup almacenado previamente, verifica no-duplicados.
  "! @parameter ct_interna1      | Tabla VBRK (para lookup knumv/waerk)
  "! @parameter ct_datosinterna2 | Tabla VBRP a enriquecer (in/out)
  METHODS enrich_vbrp_from_archive
    CHANGING ct_interna1      TYPE tt_interna1
             ct_datosinterna2 TYPE tt_interna2.
```

#### Paso 3: Simplificar get_data() con Métodos Encapsulados

```abap
" ✅ REFACTORIZADO: get_data() limpio y legible
METHOD get_data.
  " Declaraciones explícitas con tipos
  DATA lt_interna1       TYPE tt_interna1.
  DATA lt_datosinterna2  TYPE tt_interna2.

  " SELECT base (50 líneas)
  SELECT vbrk~vbeln, vbrk~fkart, ..., kna1~name1
    INTO CORRESPONDING FIELDS OF TABLE @lt_interna1
    FROM vbrk
      INNER JOIN zpmt_cl_fact ON vbrk~fkart = zpmt_cl_fact~fkart
      LEFT JOIN kna1 ON kna1~kunnr = vbrk~kunrg
    WHERE vbeln IN @gs_screen-s_vbeln
      AND fkdat IN @gs_screen-s_fkdat
      AND NOT EXISTS ( SELECT vbeln FROM vbrk AS v2 WHERE v2~sfakn = vbrk~vbeln ).

  " ✅ Enriquecimiento VBRK encapsulado (3 líneas en lugar de 47)
  IF me->gv_use_archive = abap_true.
    enrich_vbrk_from_archive( CHANGING ct_interna1 = lt_interna1 ).
  ENDIF.

  " SELECT VBRP (40 líneas)
  SELECT vbrk~vbeln, vbrp~posnr, ..., viaufks~objnr
    INTO CORRESPONDING FIELDS OF TABLE @lt_datosinterna2
    FROM vbrp
      INNER JOIN vbrk ON vbrk~vbeln = vbrp~vbeln
      INNER JOIN viaufks ON viaufks~aufnr = vbrp~aufnr
    FOR ALL ENTRIES IN @lt_interna1
    WHERE vbrp~vbeln = @lt_interna1-vbeln ...

  " ✅ Enriquecimiento VBRP encapsulado (4 líneas en lugar de 58)
  IF me->gv_use_archive = abap_true.
    enrich_vbrp_from_archive( CHANGING ct_interna1      = lt_interna1
                                       ct_datosinterna2 = lt_datosinterna2 ).
  ENDIF.

  " Resto de lógica de negocio...
ENDMETHOD.
```

**Beneficios:**
- ✅ get_data() reducido de 800 → 300 líneas (~63% reducción)
- ✅ Responsabilidades claras y separadas
- ✅ Código más testeable (métodos privados con tipos explícitos)
- ✅ Patrones reutilizables (prefetch + lookup encapsulado)

#### Paso 4: Implementar Métodos Encapsulados

**Patrón estándar: Prefetch + Deduplicación + Enrichment**

```abap
METHOD enrich_vbrk_from_archive.
  " ═══════════════════════════════════════════════════════════════
  " 1. Declaraciones locales
  " ═══════════════════════════════════════════════════════════════
  DATA lt_vbrk_arch TYPE STANDARD TABLE OF vbrk.
  DATA lt_vbrp_arch TYPE STANDARD TABLE OF vbrp.
  DATA lt_kna1_lookup TYPE STANDARD TABLE OF kna1.

  " ═══════════════════════════════════════════════════════════════
  " 2. Construir filtros y leer desde archivo
  " ═══════════════════════════════════════════════════════════════
  DATA(lt_filters_vbrk) = build_archive_filters_vbrk(
    ir_vbeln = gs_screen-s_vbeln
    ir_fkdat = gs_screen-s_fkdat
    ir_kunrg = gs_screen-s_kunrg ).

  get_vbrk_vbrp_from_archive_arc(
    EXPORTING it_filters_vbrk = lt_filters_vbrk
              it_filters_vbrp = VALUE #( )
    IMPORTING et_vbrk = lt_vbrk_arch
              et_vbrp = lt_vbrp_arch ).

  IF lt_vbrk_arch IS INITIAL.
    RETURN.  "← Guard: sin datos archivo, nada que hacer
  ENDIF.

  " ═══════════════════════════════════════════════════════════════
  " 3. Prefetch: obtener NAME1 desde KNA1 (evitar SELECT en loop)
  " ═══════════════════════════════════════════════════════════════
  SELECT kunnr, name1
    FROM kna1
    FOR ALL ENTRIES IN @lt_vbrk_arch
    WHERE kunnr = @lt_vbrk_arch-kunrg
    INTO TABLE @lt_kna1_lookup.
  SORT lt_kna1_lookup BY kunnr.

  " ═══════════════════════════════════════════════════════════════
  " 4. Enriquecer y deduplicar (solo agregar si no existe en BD)
  " ═══════════════════════════════════════════════════════════════
  LOOP AT lt_vbrk_arch ASSIGNING FIELD-SYMBOL(<fs_vbrk_arch>).
    " Verificar que no exista ya en BD
    IF line_exists( ct_interna1[ vbeln = <fs_vbrk_arch>-vbeln ] ).
      CONTINUE.  "← Ya existe en BD, skip
    ENDIF.

    " Agregar desde archivo
    APPEND INITIAL LINE TO ct_interna1 ASSIGNING FIELD-SYMBOL(<fs_interna1_new>).
    MOVE-CORRESPONDING <fs_vbrk_arch> TO <fs_interna1_new>.

    " Enriquecer con NAME1 desde lookup
    READ TABLE lt_kna1_lookup INTO DATA(ls_kna1)
         WITH KEY kunnr = <fs_vbrk_arch>-kunrg BINARY SEARCH.
    IF sy-subrc = 0.
      <fs_interna1_new>-name1 = ls_kna1-name1.
    ENDIF.
  ENDLOOP.

  " ═══════════════════════════════════════════════════════════════
  " 5. Almacenar VBRP para uso posterior (backup temporal)
  " ═══════════════════════════════════════════════════════════════
  gt_vbrp_arch_backup = lt_vbrp_arch.
ENDMETHOD.
```

**Patrón estándar: Usar Backup + Lookup Cruzado**

```abap
METHOD enrich_vbrp_from_archive.
  " ═══════════════════════════════════════════════════════════════
  " 1. Guard: Verificar que haya datos de VBRP archive disponibles
  " ═══════════════════════════════════════════════════════════════
  IF gt_vbrp_arch_backup IS INITIAL.
    RETURN.  "← Sin backup, nada que hacer
  ENDIF.

  " ═══════════════════════════════════════════════════════════════
  " 2. Prefetch: obtener objnr desde VIAUFKS
  " ═══════════════════════════════════════════════════════════════
  DATA lt_viaufks_lookup TYPE STANDARD TABLE OF viaufks.
  SELECT aufnr, auart, equnr, tplnr, objnr
    FROM viaufks
    FOR ALL ENTRIES IN @gt_vbrp_arch_backup
    WHERE aufnr  = @gt_vbrp_arch_backup-aufnr
      AND auart IN @gs_screen-s_aufart
      AND equnr IN @gs_screen-s_equnr
      AND tplnr IN @gs_screen-s_tplnr
    INTO TABLE @lt_viaufks_lookup.
  SORT lt_viaufks_lookup BY aufnr.

  " ═══════════════════════════════════════════════════════════════
  " 3. Enriquecer VBRP con lookups cruzados (VBRK + VIAUFKS)
  " ═══════════════════════════════════════════════════════════════
  LOOP AT gt_vbrp_arch_backup ASSIGNING FIELD-SYMBOL(<fs_vbrp_arch>).
    " Verificar que no exista ya en BD
    IF line_exists( ct_datosinterna2[ vbeln = <fs_vbrp_arch>-vbeln
                                      posnr = <fs_vbrp_arch>-posnr ] ).
      CONTINUE.  "← Ya existe en BD, skip
    ENDIF.

    " Lookup 1: Obtener knumv, waerk desde ct_interna1 (VBRK)
    ASSIGN ct_interna1[ vbeln = <fs_vbrp_arch>-vbeln ]
      TO FIELD-SYMBOL(<fs_interna1_vbrp>).
    IF sy-subrc <> 0.
      CONTINUE.  "← VBRK no existe, skip esta posición
    ENDIF.

    " Lookup 2: Obtener objnr desde VIAUFKS
    READ TABLE lt_viaufks_lookup INTO DATA(ls_viaufks)
         WITH KEY aufnr = <fs_vbrp_arch>-aufnr BINARY SEARCH.
    IF sy-subrc <> 0.
      CONTINUE.  "← VIAUFKS no existe, skip
    ENDIF.

    " Agregar posición enriquecida
    APPEND INITIAL LINE TO ct_datosinterna2 ASSIGNING FIELD-SYMBOL(<fs_new>).
    MOVE-CORRESPONDING <fs_vbrp_arch> TO <fs_new>.
    <fs_new>-knumv = <fs_interna1_vbrp>-knumv.  "← Del VBRK
    <fs_new>-waerk = <fs_interna1_vbrp>-waerk.  "← Del VBRK
    <fs_new>-objnr = ls_viaufks-objnr.          "← Del VIAUFKS
  ENDLOOP.
ENDMETHOD.
```

### 📊 Métricas de Refactorización

| Métrica | Antes (Inline) | Después (Encapsulado) | Mejora |
|---------|----------------|------------------------|--------|
| **Líneas get_data()** | ~800 líneas | ~300 líneas | ✅ -63% |
| **Bloques IF anidados** | 3-4 niveles | 1-2 niveles | ✅ -50% |
| **SELECTs en get_data()** | 7-10 SELECTs | 3-5 SELECTs | ✅ -40% |
| **Testabilidad** | Baja (método gigante) | Alta (métodos pequeños) | ✅ |
| **Complejidad ciclomática** | 40-50 | 15-20 | ✅ -60% |
| **Mantenibilidad** | Difícil | Fácil | ✅ |

### 🎯 Checklist de Refactorización

**Para cada bloque de archiving en get_data():**

- [ ] **¿Bloque tiene >20 líneas?** → Candidato a extracto
- [ ] **¿Lógica opera sobre tabla específica?** → Buen límite de responsabilidad
- [ ] **¿Tiene patrón prefetch + lookup?** → Encapsular juntos
- [ ] **¿Requiere datos de método anterior?** → Usar atributo de instancia (backup)
- [ ] **¿Varios bloques similares?** → Extraer patrón común

**Al extraer método:**

- [ ] Nombre descriptivo: `enrich_<tabla>_from_archive`
- [ ] Comentario ABAPDoc completo
- [ ] Parámetros con tipos explícitos (`TYPE tt_*`)
- [ ] Guard al inicio (`CHECK ... IS INITIAL. RETURN.`)
- [ ] TRY-CATCH para archiving (best-effort)
- [ ] Comentarios seccionales con `" ═══...`

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

### Limitación Arquitectural: VBFA Solo en SD_VBAK (Marzo 2026)

**Descubrimiento QA:** Durante testing de soporte multi-objeto para VBFA (flujo de documentos SD), se descubrió que **VBFA solo existe físicamente en archivos de SD_VBAK**, NO en RV_LIKP ni SD_VBRK.

**Hallazgo debugging:**
```abap
" ✅ gc_vbfa (usa SD_VBAK internamente) - Funciona correctamente
lo_factory->get_instance( iv_object = zcl_ca_archiving_factory=>gc_vbfa
                          it_filter_options = lt_filters ).
lo_factory->get_data( EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
                      IMPORTING et_data = lt_vbfa ).
" → lt_vbfa retorna registros ✅ (lee desde SD_VBAK/SAP_DRB_VBAK_02)
```

**Traza de debugging confirmó:**
- ✅ Filtros construidos correctamente
- ✅ Archivo encontrado y abierto (ARCHIVE_READ_OBJECT)
- ✅ Offsets generados exitosamente
- ❌ ARCHIVE_GET_TABLE retorna vacío para VBFA (sin excepción ni error)

**Causa raíz (diseño arquitectural SAP):**

SAP archiva VBFA **solo con el documento de origen** (VBAK = pedidos) para evitar duplicación:

```
Flujo SD típico:
┌────────┐        ┌────────┐        ┌────────┐
│ VBAK   │   →    │ LIKP   │   →    │ VBRK   │
│(Pedido)│        │(Entrega)│       │(Factura)│
└────────┘        └────────┘        └────────┘

Tabla VBFA registra TODAS las relaciones:
- VBAK → LIKP (pedido → entrega)
- LIKP → VBRK (entrega → factura)  
- VBAK → VBRK (pedido → factura)

Estrategia de archiving SAP:
┌────────┐
│SD_VBAK │ ← VBFA archivada AQUÍ (documento raíz)
└────────┘
┌────────┐
│RV_LIKP │ ← VBFA NO archivada (evita duplicar VBAK→LIKP)
└────────┘
┌────────┐
│SD_VBRK │ ← VBFA NO archivada (evita duplicar LIKP→VBRK)
└────────┘
```

**Por qué SARA muestra VBFA en todos los objetos:**
- Catálogo de RV_LIKP **incluye definición de campos** de VBFA
- Catálogo de SD_VBRK **incluye definición de campos** de VBFA
- Esto es para **metadata/estructura**, no significa que la tabla esté físicamente en el archivo

**Lección aprendida:**

> **Campo en catálogo (SARA) ≠ Tabla en archivo físico**
>
> El catálogo muestra qué campos **pueden** extraerse si la tabla existe en el archivo.  
> No garantiza que la tabla esté **físicamente almacenada** en ese objeto de archiving.

**Patrón correcto para leer VBFA:**

```abap
" ✅ CORRECTO: Usar gc_vbfa (internamente usa SD_VBAK)
METHOD get_vbfa_from_archive.
  " Paso 1: Leer VBFA desde SD_VBAK (único objeto que lo contiene)
  DATA(lo_factory) = NEW zcl_ca_archiving_factory( ).
  lo_factory->get_instance( 
    iv_object = zcl_ca_archiving_factory=>gc_vbfa
    it_filter_options = lt_filters ).
  
  lo_factory->get_data( 
    EXPORTING iv_object = zcl_ca_archiving_factory=>gc_vbfa
    IMPORTING et_data = lt_vbfa_arch ).
  
  " Paso 2: Post-filtrar por documento destino si se necesita
  " (ej: filtrar entregas LIKP o facturas VBRK desde VBFA completo)
  IF lr_vbeln_destino IS NOT INITIAL.
    DELETE lt_vbfa_arch WHERE vbeln NOT IN lr_vbeln_destino.
  ENDIF.
  
  IF lr_vbtyp_n IS NOT INITIAL.
    DELETE lt_vbfa_arch WHERE vbtyp_n NOT IN lr_vbtyp_n.
  ENDIF.
  
  RETURN lt_vbfa_arch.
ENDMETHOD.
```

**Campos indexables de VBFA (SAP_DRB_VBAK_02):**
- ✅ `VBELN` (documento origen del pedido) → único campo indexable
- ❌ `VBELV` (documento precedente) → requiere post-filtrado
- ❌ `VBTYP_V` (tipo doc precedente) → requiere post-filtrado
- ❌ `VBTYP_N` (tipo doc subsecuente) → requiere post-filtrado
- ❌ `POSNV`, `POSNN` (posiciones) → requieren post-filtrado

**Referencia:** Ver programa `Z_TEST_VBFA_ARCHIVE` para implementación completa con documentación.

**✅ Implementación en factory:**
- `gc_vbfa` (SD_VBFA) → ✅ Única constante disponible, lee desde SD_VBAK internamente
- No crear constantes adicionales - gc_vbfa es suficiente y ya está configurado correctamente

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

## � Documentación ABAPDoc para Archiving

### 🎯 Importancia de ABAPDoc en Archiving

**Por qué es crítico:**
- **Arquitectura compleja:** Archiving agrega múltiples capas (BD + Archive + prefetch + enrichment)
- **Lógica no obvia:** Decisiones de diseño (guards, best-effort, deduplicación) deben documentarse
- **Mantenimiento futuro:** Otros desarrolladores necesitan entender el flujo completo
- **Testing:** Documentación clara facilita escribir casos de prueba

### ✅ Patrón ABAPDoc para Métodos de Archiving

#### Estructura Estándar de ABAPDoc

```abap
"! <Título corto: qué hace el método>
"! <Descripción detallada: cómo lo hace, estrategia, consideraciones>
"! <Decisiones de diseño importantes>
"! @parameter <param_name> | <Descripción del parámetro>
"! @raising <exception_name> | <Cuándo se lanza>
```

#### Plantilla para Métodos PROTECTED (Lógica de Gating)

```abap
"! Determinar si es necesario leer desde archiving
"! Lógica: Si el rango de fechas incluye facturas anteriores al cutoff, se requiere archiving.
"! Esta decisión es determinística y testeable sin dependencias externas.
"! @parameter iv_cutoff | Fecha límite (e.g. fecha más antigua en BD activa)
"! @parameter ir_fkdat  | Rango de fechas de facturación solicitado por usuario
"! @parameter rv_needs  | abap_true si requiere archiving, abap_false si solo BD
METHODS needs_archive
  IMPORTING iv_cutoff       TYPE sy-datum
            ir_fkdat        TYPE bkk_r_budat
  RETURNING VALUE(rv_needs) TYPE abap_bool.
```

#### Plantilla para build_archive_filters_*()

```abap
"! Construir filtros para lectura de VBRK archivado
"! Usa campos indexables (VBELN, FKDAT, KUNRG) para generar offsets eficientes.
"! Usa infoestructura SAP_DRB_VBAK_02 (estándar SAP para ventas/facturación).
"! CRÍTICO: Solo campos en GENTAB pueden generar offsets. Campos solo-catálogo
"! deben filtrarse en memoria después de lectura (ej: BUKRS, ZUONR, XBLNR).
"! @parameter ir_vbeln   | Rango de números de factura (opcional)
"! @parameter ir_fkdat   | Rango de fechas de facturación (opcional)
"! @parameter ir_kunrg   | Rango de clientes pagadores (opcional)
"! @parameter rt_filters | Tabla de filtros para ZCL_CA_ARCHIVING_FACTORY
METHODS build_archive_filters_vbrk
  IMPORTING ir_vbeln          TYPE ANY TABLE OPTIONAL
            ir_fkdat          TYPE ANY TABLE OPTIONAL
            ir_kunrg          TYPE ANY TABLE OPTIONAL
  RETURNING VALUE(rt_filters) TYPE ztt_ca_archiving.
```

**Elementos clave documentados:**
- ✅ Qué campos son indexables vs solo-catálogo
- ✅ Qué infoestructura se usa
- ✅ Estrategia de filtrado (campos indexables → post-filtro)

#### Plantilla para get_*_from_archive()

```abap
"! Leer VBRK y VBRP desde archiving en una sola llamada
"! Estrategia: Usa objeto SD_VBRK que incluye VBRP automáticamente (estructura jerárquica).
"! Esta es una lectura optimizada: 1 sola llamada a archiving retorna ambas tablas.
"! Factory pattern: get_instance() genera offsets → get_data() extrae datos.
"! @parameter it_filters_vbrk | Filtros para VBRK (campos indexables)
"! @parameter it_filters_vbrp | Filtros para VBRP (actualmente no usado, VBRP viene con VBRK)
"! @parameter et_vbrk         | Tabla VBRK archivado (STANDARD TABLE OF vbrk)
"! @parameter et_vbrp         | Tabla VBRP archivado (STANDARD TABLE OF vbrp)
"! @raising   zcx_ca_archiving | Error de lectura en archiving (archivo corrupto, permisos, etc.)
METHODS get_vbrk_vbrp_from_archive_arc
  IMPORTING it_filters_vbrk TYPE ztt_ca_archiving
            it_filters_vbrp TYPE ztt_ca_archiving
  EXPORTING et_vbrk         TYPE STANDARD TABLE
            et_vbrp         TYPE STANDARD TABLE
  RAISING   zcx_ca_archiving.
```

**Elementos clave documentados:**
- ✅ Estrategia (lectura jerárquica vs separada)
- ✅ Patrón usado (factory)
- ✅ Qué retorna (tipos de tablas)
- ✅ Excepciones posibles

#### Plantilla para enrich_*_from_archive()

```abap
"! Enriquecer lt_interna1 (VBRK) desde archive
"! Lee VBRK+VBRP archivado, combina con BD (sin duplicados), enriquece con KNA1.
"! Almacena lt_vbrp_arch en atributo de instancia para uso posterior.
"! Estrategia: SELECT FOR ALL ENTRIES (prefetch) + READ TABLE BINARY SEARCH (O(log n)).
"! Best-effort: Si archiving falla, continua con datos de BD (TRY-CATCH interno).
"! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out, tipo tt_interna1)
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE tt_interna1.

"! Enriquecer lt_datosinterna2 (VBRP) desde archive
"! Lee VBRP archivado almacenado previamente (gt_vbrp_arch_backup), verifica no-duplicados.
"! Requiere que enrich_vbrk_from_archive() haya sido llamado primero (llena backup).
"! Realiza lookups cruzados: ct_interna1 (VBRK) para knumv/waerk + VIAUFKS para objnr.
"! @parameter ct_interna1      | Tabla VBRK (para lookup knumv/waerk, tipo tt_interna1)
"! @parameter ct_datosinterna2 | Tabla VBRP a enriquecer (in/out, tipo tt_interna2)
METHODS enrich_vbrp_from_archive
  CHANGING ct_interna1      TYPE tt_interna1
           ct_datosinterna2 TYPE tt_interna2.
```

**Elementos clave documentados:**
- ✅ Qué datos enriquece (campos específicos)
- ✅ De dónde vienen  los datos (archivo + lookups)
- ✅ Dependencias entre métodos (orden de llamada)
- ✅ Estrategia de performance (prefetch)
- ✅ Manejo de errores (best-effort)

### ❌ Errores Comunes de Documentación

#### Error 1: ABAPDoc en Lugares Incorrectos

```abap
" ❌ INCORRECTO: ABAPDoc ("!) en TYPES (PRIVATE SECTION)
"! Estructura de tabla interna #1
TYPES: BEGIN OF ty_interna1,  "← Error compilación

" ✅ CORRECTO: Comentarios estándar (") para TYPES
" Estructura de tabla interna #1 (VBRK - facturas)
" Incluye todos los campos del SELECT de VBRK + NAME1 de KNA1
TYPES: BEGIN OF ty_interna1,
```

#### Error 2: Documentación Insuficiente

```abap
" ❌ INCORRECTO: Solo título, sin detalles
"! Enriquecer VBRK
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE tt_interna1.

" ✅ CORRECTO: Título + estrategia + consideraciones
"! Enriquecer lt_interna1 (VBRK) desde archive
"! Lee VBRK+VBRP archivado, combina con BD (sin duplicados), enriquece con KNA1.
"! Almacena lt_vbrp_arch en atributo para uso posterior en enrich_vbrp_from_archive().
"! Best-effort: Si archiving falla, continua con datos de BD.
"! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out)
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE tt_interna1.
```

#### Error 3: No Documentar Decisiones Críticas

```abap
" ❌ INCORRECTO: No explica por qué solo ciertos campos
METHODS build_archive_filters_konv
  IMPORTING ir_vbeln TYPE rsdsselopt_t OPTIONAL
  RETURNING VALUE(rt_filters) TYPE ztt_ca_archiving.

" ✅ CORRECTO: Explica restricción de campos indexables
"! Construir filtros para KONV archivado vía SD_VBRK
"! CRÍTICO: Solo usa campos indexables (VBELN) para generar offsets.
"! KNUMV/KPOSN/KSCHL NO son indexables → filtrado en memoria después.
"! Patrón: Filtrar por VBELN (indexable) → leer datos completos → post-filtrar KNUMV/KSCHL.
"! @parameter ir_vbeln   | Rango de números de factura (opcional)
"! @parameter rt_filters | Tabla de filtros para ZCL_CA_ARCHIVING_FACTORY
METHODS build_archive_filters_konv
  IMPORTING ir_vbeln TYPE rsdsselopt_t OPTIONAL
  RETURNING VALUE(rt_filters) TYPE ztt_ca_archiving.
```

### 📋 Checklist de Documentación ABAPDoc

**Para cada método de archiving:**

- [ ] **Título claro:** ¿Qué hace el método en 1 línea?
- [ ] **Estrategia:** ¿Cómo lo hace? (prefetch, lookup, enrichment)
- [ ] **Decisiones críticas:** ¿Por qué así? (campos indexables, best-effort, etc.)
- [ ] **Dependencias:** ¿Requiere que otro método haya ejecutado antes?
- [ ] **Performance:** ¿Qué optimizaciones usa? (FOR ALL ENTRIES, BINARY SEARCH)
- [ ] **Manejo errores:** ¿Qué pasa si falla? (TRY-CATCH, continúa, aborta)
- [ ] **@parameter:** Cada parámetro documentado con tipo y propósito
- [ ] **@raising:** Excepciones posibles documentadas

### 🎨 Convenciones de Comentarios por Sección

#### En Definición de Clase (CLASS ... DEFINITION)

```abap
PUBLIC SECTION.
  "! Método orquestador principal
  "! @parameter is_screen | Parámetros de selección del usuario
  "! @parameter rt_data   | Datos procesados listos para display
  METHODS start
    IMPORTING is_screen      TYPE ty_screen
    RETURNING VALUE(rt_data) TYPE tt_result.

PROTECTED SECTION.
  "! Determinar si es necesario leer desde archiving
  "! @parameter iv_cutoff | Fecha cutoff (límite BD activa)
  "! @parameter rv_needs  | abap_true si requiere archive
  METHODS needs_archive
    IMPORTING iv_cutoff       TYPE sy-datum
    RETURNING VALUE(rv_needs) TYPE abap_bool.

PRIVATE SECTION.
  " Comentarios estándar (") para TYPES, atributos non-public
  " Estructura de tabla interna #1 (VBRK - facturas)
  TYPES: BEGIN OF ty_interna1,
           ...
         END OF ty_interna1.

  " Flag para control de lectura desde archiving
  " abap_true = BD + Archive, abap_false = solo BD
  DATA gv_use_archive TYPE abap_bool.

  "! ABAPDoc para métodos privados también
  "! Enriquecer VBRK desde archive
  "! @parameter ct_interna1 | Tabla VBRK a enriquecer
  METHODS enrich_vbrk_from_archive
    CHANGING ct_interna1 TYPE tt_interna1.
```

#### En Implementación (CLASS ... IMPLEMENTATION)

```abap
METHOD enrich_vbrk_from_archive.
  " ═══════════════════════════════════════════════════════════════
  " Comentarios seccionales para bloques lógicos
  " ═══════════════════════════════════════════════════════════════
  DATA lt_vbrk_arch TYPE STANDARD TABLE OF vbrk.

  " ═══════════════════════════════════════════════════════════════
  " 1. Construir filtros y leer desde archivo
  " ═══════════════════════════════════════════════════════════════
  DATA(lt_filters) = build_archive_filters_vbrk( ... ).

  " ═══════════════════════════════════════════════════════════════
  " 2. Prefetch: obtener NAME1 desde KNA1 (evitar SELECT en loop)
  " ═══════════════════════════════════════════════════════════════
  SELECT kunnr, name1 FROM kna1 ...

  " Comentarios inline para lógica específica
  LOOP AT lt_vbrk_arch ASSIGNING FIELD-SYMBOL(<fs_vbrk_arch>).
    " Verificar que no exista ya en BD
    IF line_exists( ct_interna1[ vbeln = <fs_vbrk_arch>-vbeln ] ).
      CONTINUE.  "← Ya existe en BD, skip
    ENDIF.
    ...
  ENDLOOP.
ENDMETHOD.
```

---

## �📋 Checklist de Migración

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

### Fase 2B: Tipificación de Parámetros (Best Practice)

> **⚠️ Nueva fase:** Aprendizaje de ZCL_PM_FACTORDENSERVICIO_ARC

- [ ] **Identificar métodos con parámetros de tabla:**
  - [ ] Listar métodos get_*_from_archive() con EXPORTING tablas
  - [ ] Listar métodos enrich_*_from_archive() con CHANGING tablas
- [ ] **Definir tipos explícitos en PRIVATE SECTION:**
  - [ ] `ty_interna1` / `tt_interna1` para primera tabla (e.g. VBRK enriquecido)
  - [ ] `ty_interna2` / `tt_interna2` para segunda tabla (e.g. VBRP enriquecido)
  - [ ] Documentar con comentarios estándar ("") qué campos incluye cada tipo
- [ ] **Actualizar firmas de métodos:**
  - [ ] Reemplazar `TYPE STANDARD TABLE` → `TYPE tt_interna1`
  - [ ] Documentar en ABAPDoc origen de campos (VBRK + NAME1 de KNA1)
- [ ] **Declarar variables con tipos explícitos:**
  - [ ] `DATA lt_interna1 TYPE tt_interna1` en lugar de `DATA lt_vbrk TYPE STANDARD TABLE`
  - [ ] Usar tipos explícitos en LOOPs (`LOOP AT lt_interna1 ASSIGNING FIELD-SYMBOL(<fs>)`)
- [ ] **Verificar compilación:** 0 errores antes de Fase 3

**Ventajas:**
- ✅ Compilación permite field accesses (evita errores "unknown component")
- ✅ Code completion funciona en loops y asignaciones
- ✅ Mantiene type safety en toda la cadena de llamadas
- ✅ Documentación implícita (tipo describe estructura)

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

### Fase 6A: Refactorización y Calidad

> **⚠️ Nueva fase:** Code quality best practices

- [ ] **Revisión de complejidad:**
  - [ ] ¿get_data() > 500 líneas? → Considerar extracción
  - [ ] ¿Lógica de archivo inline > 100 líneas por tabla? → Extraer a métodos
- [ ] **Refactorización de archiving:**
  - [ ] Extraer `build_archive_filters_*()` (1 método por tabla)
  - [ ] Extraer `get_*_from_archive()` (lecturas de archivo limpias)
  - [ ] Extraer `enrich_*_from_archive()` (enriquecimiento archiving best-effort)
  - [ ] Encapsular deduplicación, post-filtros, lookups
- [ ] **Comentarios seccionales:**
  - [ ] Agregar separadores `" ═══...═══` entre bloques lógicos
  - [ ] Etiquetar secciones ("1. Prefetch", "2. Loop principal", "3. Post-filtro")
  - [ ] Documentar decisiones (por qué así, no de otra forma)
- [ ] **Validar métricas:**
  - [ ] Método más largo < 300 líneas
  - [ ] Responsabilidad única: cada método hace una cosa
  - [ ] Nombres descriptivos: verbo + sustantivo (e.g., `enrich_vbrk_from_archive`)
  - [ ] Sin comentarios obvios ("Loop over table" → eliminar)

**Antes:**
```abap
METHOD get_data.
  " 800 líneas ...
  " Inline archiving VBRK (100 líneas)
  " Inline archiving VBRP (150 líneas)
  " Inline archiving KONV (80 líneas)
  ...
ENDMETHOD.
```

**Después:**
```abap
METHOD get_data.
  " 300 líneas ...
  IF gv_use_archive = abap_true.
    enrich_vbrk_from_archive( CHANGING ct_interna1 = lt_interna1 ).
    enrich_vbrp_from_archive( CHANGING ct_interna2 = lt_interna2 ).
    enrich_pricing_konv_archive( CHANGING ct_interna2 = lt_interna2 ).
  ENDIF.
ENDMETHOD.
```

### Fase 6B: Documentación ABAPDoc

> **⚠️ Nueva fase:** Systematic method documentation

- [ ] **ABAPDoc para métodos PUBLIC:**
  - [ ] start() - Orquestador principal, parámetros de entrada/salida
  - [ ] Documentar @parameter para cada parámetro
  - [ ] Documentar @raising para excepciones
- [ ] **ABAPDoc para métodos PROTECTED:**
  - [ ] needs_archive() - Decisión de gating, lógica determinística
  - [ ] determine_transport_parameters() - Mapeo de flags
  - [ ] build_datetime_range() - Construcción de rangos temporales
  - [ ] build_archive_filters_*() - Filtros indexables, qué infostructure usa
- [ ] **ABAPDoc para métodos PRIVATE:**
  - [ ] get_*_from_archive() - Estrategia (jerárquico vs separado), factory pattern
  - [ ] enrich_*_from_archive() - Qué enriquece, origen datos, best-effort
  - [ ] Documentar dependencias (ej: enrich_vbrp requiere enrich_vbrk primero)
- [ ] **Comentarios estándar para TYPES:**
  - [ ] ty_interna1 / tt_interna1 - Qué tabla base, qué campos agregados
  - [ ] ty_interna2 / tt_interna2 - Qué tabla base, qué campos agregados
  - [ ] NO usar ABAPDoc ("!") en TYPES (compilation error)
- [ ] **Checklist de calidad de documentación:**
  - [ ] Cada método tiene título claro (1 línea: qué hace)
  - [ ] Estrategia documentada (cómo lo hace)
  - [ ] Decisiones críticas explicadas (por qué así)
  - [ ] Campos indexables vs catálogo identificados (en build_filters)
  - [ ] Performance hints (prefetch, FOR ALL ENTRIES, BINARY SEARCH)
  - [ ] Manejo de errores explicado (TRY-CATCH, best-effort, continúa)

**Ejemplo ABAPDoc:**
```abap
"! Enriquecer lt_interna1 (VBRK) desde archive
"! Lee VBRK+VBRP archivado, combina con BD (sin duplicados), enriquece con KNA1.
"! Almacena lt_vbrp_arch en atributo para uso posterior en enrich_vbrp_from_archive().
"! Best-effort: Si archiving falla, continua con datos de BD.
"! @parameter ct_interna1 | Tabla VBRK a enriquecer (in/out, tipo tt_interna1)
METHODS enrich_vbrk_from_archive
  CHANGING ct_interna1 TYPE tt_interna1.
```

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
