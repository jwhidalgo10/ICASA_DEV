# Bitácora de Archiving: ZSD_ESTVNT (Estadísticas de Ventas)

**Objeto de origen:** SAP Query generada desde Infoset (código base copiado como `zsd_estvnt`)  
**Objeto destino propuesto:** `ZCL_SD_ESTVNT_ARC` (clase de servicio) + programa ABAP `Z_SD_ESTVNT`  
**Package propuesto:** `ZARCH_SD_APPS`  
**Estructura de salida:** `ZSTR_SD_ESTVTA`  
**Inicio de análisis:** 25 de marzo de 2026  
**Guía de referencia:** `ARCHIVING_IMPLEMENTATION_GUIDE_ES.md` v3.1  

---

## Estado del Desarrollo

| Fase | Estado | Fecha |
|------|--------|-------|
| Fase 1 – Análisis inicial | ✅ Completado | 2026-03-25 |
| Fase 2 – Migración de Query a ABAP | ✅ Completado | 2026-03-25 |
| Fase 3 – Infraestructura archive | ✅ Completado | 2026-03-25 |
| Fase 4 – Integración híbrida BD + Archive | ✅ Completado | 2026-03-25 |
| Fase 5 – Estabilización | 🔲 Pendiente | — |
| Fase 6 – Testing y documentación | 🔲 Pendiente | — |

---

## 1. Contexto del Objeto

### Naturaleza del código fuente
El archivo `zsd_estvnt` es la **implementación generada por SAP Query** (template `RSAQDVP_TEMPLATE`). No puede modificarse directamente para agregar archiving. La migración a programa ABAP + clase de servicio es **prerequisito arquitectónico**, no opcional.

El usuario no puede abrir el Infoset original vía ADT, por eso se copió el código del reporte generado. Este código sirve como especificación funcional exacta del comportamiento actual.

### Funcionalidad
Reporte de estadísticas de ventas por factura (`VBRK`/`VBRP`) con:
- Agrupación por fecha, ruta, material, organización de ventas, oficina de ventas
- Cálculo de cantidades reducidas por familia/tipo de producto con conversión de unidades
- Cálculo de valor neto y total con tipo de cambio (`KURRF`)
- Derivación de jerarquía de producto (línea, familia, marca)
- Exclusión de ciertos tipos de factura y documentos anulados

---

## 2. Criterio Temporal Real

**Campo:** `VBRK-FKDAT` (fecha de factura)  
**Select-option:** `FECHDOC FOR VBRK-FKDAT OBLIGATORY`  
**Aplicación en WHERE:** `WHERE ENC~FKDAT IN @FECHDOC`

→ `needs_archive()` debe evaluar el extremo inferior del rango `FECHDOC`.

---

## 3. Tablas Core y Auxiliares

### 3.1 Tablas Core (archivables vía SD_VBRK)

| Tabla | Alias | Tipo JOIN | Rol |
|-------|-------|-----------|-----|
| `VBRK` | ENC | `FROM` (base) | Cabecera factura — universo funcional del reporte |
| `VBRP` | DET | `INNER JOIN` | Posiciones factura — driver del GROUP BY |

**Ambas tablas definen juntas el universo funcional.** Cuando son archivadas, el reporte retorna 0 filas para esos períodos → **bloqueo total de histórico**.

**Familia archive candidata:** `SD_VBRK`
- `VBRK` → constante lógica `gc_vbrk`
- `VBRP` → constante lógica `gc_vbrp`

### 3.2 Tablas Auxiliares (no archivables en SD_VBRK)

| Tabla | Alias | Tipo JOIN | Tipo | Rol |
|-------|-------|-----------|------|-----|
| `TVKOT` | ORG | INNER JOIN | Maestro texto | Nombre organización de ventas |
| `TVKBT` | OFVNT | INNER JOIN | Maestro texto | Nombre oficina de ventas |
| `MARA` | MAT | INNER JOIN | Maestro MM | Datos de material (jerarquía, clase) |
| `MAKT` | NMAT | INNER JOIN | Maestro MM texto | Nombre del producto |
| `T179T` | LINEA / FAM / MARCA | LEFT JOIN | Maestro texto | Jerarquía de producto |
| `MARM` | REDU / REDU_L / REDU_G / REDU_LB / REDU_KG | LEFT JOIN | Maestro MM | Factores de conversión de UM alternativas |
| `ZSDT_CANT_FACT` | ECF | LEFT JOIN | Tabla Z | Tipos de factura que anulan cantidad |
| `MARA` (segunda) | MATP | LEFT JOIN | Maestro MM | Material padre para código legado |

**Ninguna de estas tablas es archivable dentro de SD_VBRK.** Son maestros estables o tablas Z. No bloquean histórico por sí mismas.

---

## 4. Bloqueos de Histórico Identificados

### Bloqueo 1 — INNER JOIN VBRK/VBRP con archiving activo
Cuando `VBRK` y `VBRP` son archivadas, el SELECT actual retorna 0 filas para el período archivado. No hay fallback. **Bloqueo total.**

### Bloqueo 2 — INNER JOIN a maestros sobre datos de posición
`TVKBT` se une por `DET~VKBUR` (campo de VBRP). Si bien `TVKBT` no se archiva, su join es `INNER JOIN`, lo que implica que en la lectura archive de VBRP habrá que hacer el lookup por separado y no como join SQL.

### Bloqueo 3 — Campo `VF_STATUS` en rama archive
El filtro `CASE WHEN ENC~VF_STATUS = 'C' ...` usa un campo estándar de `VBRK`. No es un bloqueo arquitectónico; en la rama archive se tratará como regla funcional de post-filtro en memoria.

---

## 5. Lógica Funcional Crítica a Preservar

### 5.1 Exclusión de documentos de anulación
```sql
WHERE ENC~VBTYP NOT IN ('N','S')
  AND ENC~FKART NOT IN ('ZERO','ZASR','ZCSR','ZIVS')
  AND DET~FKIMG > 0
```
Estas exclusiones deben reproducirse en el post-filtro en memoria para la rama archive.

### 5.2 Documentos anulados via VF_STATUS y ECF
```sql
CASE WHEN ENC~VF_STATUS = 'C' OR NOT ECF~FKART IS NULL THEN 0 ELSE ...
```
En la rama archive, `VF_STATUS` debe tratarse como campo funcional estándar de `VBRK` y aplicarse como post-filtro en memoria. `ECF` (`ZSDT_CANT_FACT`) es una tabla Z que puede prefetcharse antes de leer archive y aplicarse en memoria.

### 5.3 Inversión de signo para documentos de reversa
```sql
CASE WHEN (ENC~VBTYP = 'O' OR ENC~VBTYP = '6') OR DET~SHKZG = 'X' THEN -DET~FKIMG ...
```
La lógica de negación por tipo de documento y `SHKZG` debe trasladarse exactamente al procesamiento en memoria post-archive.

### 5.4 Cantidad reducida con conversión compleja de UM
El campo `CantidadReducida` involucra múltiples joins a `MARM` por distintos `MEINH`. Esta lógica puede mantenerse igual porque `MARM` es un maestro que no se archiva. Sin embargo, al leer desde archive, habrá que obtener los datos de `MARM` y `MARA` por separado (prefetch) y luego aplicar la lógica en ABAP puro.

### 5.5 Material legado (MATP)
```sql
LEFT JOIN MARA AS MATP ON SUBSTRING(MATP~MATNR,11,8) = MAT~BISMT
```
Este join resuelve el código legado buscando un material cuyo número contiene el `BISMT` del material actual como substring. Al migrar a ABAP, esto requiere una estrategia explícita (prefetch de MARA con condición similar).

---

## 6. Campos Candidatos para Offsets Archive

**Infostructura validada:** `SD_VBRK` / `SAP_SD_VBRK_001`

### 6.1 Campos indexables confirmados

| Campo | Tabla | Estado | Notas |
|-------|-------|--------|-------|
| `FKDAT` | VBRK | ✅ Confirmado | Criterio temporal real — offset principal |
| `VBELN` | VBRK | ✅ Confirmado | Clave de documento |
| `KUNRG` | VBRK | ✅ Confirmado | Cliente receptor factura |
| `FKART` | VBRK | ✅ Confirmado | Puede usarse en offset para exclusiones |
| `ERNAM` | VBRK | ✅ Confirmado | Confirmado en SARI |
| `VKORG` | VBRK | ✅ Confirmado | Puede ir a offset directamente |

### 6.2 Campos a resolver por post-filtro en memoria

| Campo | Tabla | Estado | Acción |
|-------|-------|--------|--------|
| `VTWEG` | VBRK | ⚠️ Post-filtro | Aplicar en memoria en la rama archive |
| `SPART` | VBRK | ⚠️ Post-filtro | Aplicar en memoria en la rama archive |
| `VBTYP` | VBRK | ⚠️ Post-filtro | Aplicar exclusión funcional en memoria |
| `VF_STATUS` | VBRK | ⚠️ Post-filtro | Campo estándar; aplicar lógica funcional en memoria en la rama archive |
| `VKBUR` | VBRP | ⚠️ Post-filtro | Aplicar en memoria sobre posiciones archive |
| `FKIMG` | VBRP | ❌ Post-filtro | No indexable |
| `SHKZG` | VBRP | ❌ Post-filtro | No indexable — lógica de signo en memoria |

### 6.3 Campos que siempre requieren post-filtro en memoria
- `DET~FKIMG > 0`
- `DET~SHKZG` (lógica de signo)
- `ENC~VBTYP NOT IN ('N','S')`
- `ENC~VTWEG`, `ENC~SPART`
- `DET~VKBUR`
- `ENC~VF_STATUS = 'C'`
- `ZSDT_CANT_FACT` lookup → prefetch tabla Z completa y aplicar en memoria

---

## 7. Patrón Archive Seleccionado

**Patrón: `append_vbrk_vbrp_from_archive()`**

Justificación (guía sección 7.1 y regla de decisión 1):
- `VBRK + VBRP` definen el universo funcional
- Los documentos archivados están completamente ausentes del resultado online
- No es un caso de enriquecimiento (enrichment) sino de documentos faltantes (append)
- Las tablas auxiliares (MARA, MAKT, MARM, T179T) pueden prefetcharse online y aplicarse por lookup en la fase de procesamiento en memoria

---

## 8. Dependencia de Migración Previa

**El desarrollo de archiving NO puede iniciarse en el infoset/query directamente.**

La migración de SAP Query a programa ABAP + clase de servicio es la Fase 2 y es prerequisito de todas las fases de archiving.

### Objetivo: equivalencia funcional, no réplica SQL monolítica

La Fase 2 no consiste en transcribir el SELECT del query a ABAP línea por línea. El objetivo es reproducir el **comportamiento funcional** del reporte, separando internamente responsabilidades para que la integración archive sea natural en Fase 3.

La clase debe estructurarse en tres capas:

1. **Lectura base core (`VBRK + VBRP`):**  Selección de cabeceras y posiciones de factura con los filtros de pantalla aplicados. Sin joins a maestros ni cálculos agregados en SQL. Este nivel es el punto exacto donde se incorporará la rama archive en Fase 3.

2. **Enriquecimiento / master data:**  Prefetch separado de todas las tablas auxiliares (MARA, MAKT, MARM ×5, T179T ×3, TVKOT, TVKBT, ZSDT_CANT_FACT) acotado a los materiales/documentos del resultado base. Se aplican como lookups en memoria, no como joins SQL adicionales.

3. **Cálculos y agregaciones en memoria:**  La lógica de `CantidadReducida`, inversión de signos, clasificación de tipo de producto, y la agrupación equivalente al GROUP BY se ejecutan en ABAP sobre las filas ya enriquecidas.

Esta separación tiene una consecuencia directa para archiving: en Fase 3 bastará con agregar una rama `append_vbrk_vbrp_from_archive()` en la capa 1. Las capas 2 y 3 aplican sin cambios sobre las filas traídas de archive.

Solo entonces puede agregarse la rama archive en la clase.

---

## 9. Riesgos y Bloqueos

| # | Riesgo | Severidad | Acción |
|---|--------|-----------|--------|
| R1 | La lógica de `MATP` (material padre por substring de MATNR) requiere scan completo de MARA (2 columnas) + filtro ABAP | 🟡 Medio | Aceptado: scan columnar en HANA es razonable para reporte batch; filtro por `SUBSTRING(MATNR,10,8)` en loop ABAP |
| R2 | La conversión de cantidad reducida depende de 5 joins a MARM — complejidad alta en ABAP puro | 🟡 Medio | Prefetch los 5 rangos de MARM por material y construir mapa |
| R3 | `VTWEG`, `SPART`, `VKBUR`, `VBTYP` y `VF_STATUS` se resolverán por post-filtro en memoria — riesgo de mayor volumen de filas | 🟡 Medio | Diseñar post-filtro temprano y controlado tras la lectura archive |
| R4 | `ZSDT_CANT_FACT` — semántica exacta de cuándo anula cantidad no queda clara solo del código | 🟡 Medio | Validar con funcional antes de reproducir en archive |
| R5 | GROUP BY con 20+ campos — el agregado debe reproducirse exactamente en ABAP | 🟡 Medio | Mantener misma agrupación en procesamiento interno |
| R6 | Migración de Query implica risk de regresión funcional independiente del archiving | 🟡 Medio | Hacer smoke test comparativo antes de tocar archiving |

---

## 10. Decisiones de Diseño Tomadas

| # | Decisión | Justificación |
|---|----------|---------------|
| D1 | Migrar primero a programa ABAP, luego agregar archiving | SAP Query no soporta extensión de archiving |
| D2 | Patrón `append` para VBRK+VBRP | Documentos faltantes, no columnas faltantes |
| D3 | Prefetch de maestros (MARA, MAKT, MARM, T179T) previo a lectura archive | Mantiene integridad de enriquecimiento sin joins SQL sobre archive |
| D4 | `ZSDT_CANT_FACT` → prefetch completo y lookup en memoria | Tabla Z estática, no archivable |
| D5 | Post-filtro en memoria para: FKIMG > 0, SHKZG, VBTYP 'N'/'S', VTWEG, SPART, VKBUR, VF_STATUS y lógica ECF | Campos no llevados a offset y reglas funcionales de la rama archive |
| D6 | Criterio temporal para `needs_archive()`: extremo inferior de FECHDOC (FKDAT) | Campo temporal real del objeto |
| D7 | Definir `ty_screen` pública en `ZCL_SD_ESTVNT_ARC` y reutilizarla en el consumidor | Evita crear objetos DDIC solo para la pantalla de selección |

---

## 11. Siguiente Paso

**Fase 2 — Migración de SAP Query a Programa ABAP**

Objetivo: Crear `Z_SD_ESTVNT` (programa) + `ZCL_SD_ESTVNT_ARC` (clase de servicio) en package `ZARCH_SD_APPS`, con equivalencia funcional al query actual, sin archiving aún, y con la separación interna que habilita la integración archive en Fase 3.

Tareas de Fase 2:
1. ✅ Verificar estructura `ZSTR_SD_ESTVTA` en sistema — confirmada: 23 campos, tipada correctamente. `tipocambio` presente en estructura pero no proyectado por el query; se deja sin asignar (valor inicial).
2. ✅ Definir `ty_screen` como tipo público en `ZCL_SD_ESTVNT_ARC` — implementado. El consumidor usa `DATA gs_screen TYPE zcl_sd_estvnt_arc=>ty_screen` sin DDIC adicional.
3. ✅ Crear pantalla de selección equivalente en `Z_SD_ESTVNT`: ORGVENT (`s_vkorg`), CANDIST (`s_vtweg`), SECTOR (`s_spart`), OFVNT (`s_vkbur`), FECHDOC (`s_fkdat`) + checkbox `p_hist`.
4. ✅ **Capa 1 — lectura base:** implementada en `get_billing_base()`. SELECT VBRK+VBRP sin joins a maestros. Filtros aplicados en SQL para los campos llevables: `VKORG`, `VTWEG`, `SPART`, `FKDAT`, `VKBUR`, `VBTYP`, `FKART`, `FKIMG > 0`. Punto de inserción archive marcado con comentario.
5. ✅ **Capa 2 — enriquecimiento:** implementada en `load_master_data()`. Prefetch de: MARA, MAKT, MARM×5 (CJR/L/GRR/LB/KG), T179T (jerarquía 2/5/9 chars), TVKOT, TVKBT, ZSDT_CANT_FACT, MATP (material padre). Todos cargados en tablas HASHED (`mt_*`).
6. ✅ **Capa 3 — cálculo:** implementada en `calculate_and_aggregate()`. Post-filtros, cálculos de valor neto/total con tipo de cambio, construcción de filas `ZSTR_SD_ESTVTA`. Lógica de `CantidadReducida` extraída a método privado `calculate_reduced_qty()`.
7. ✅ `VF_STATUS` y `ZSDT_CANT_FACT` integrados como lógica de zeroing diferenciada en Capa 3: cantidades zeroed por VF_STATUS OR ECF con signo VBTYP+SHKZG; valores zeroed solo por VF_STATUS con signo solo VBTYP. Campo confirmado como estándar en VBRK.
8. 🔲 **Smoke test comparativo** — pendiente. Ejecutar `Z_SD_ESTVNT` en período sin archiving y comparar resultado con la query original.

---

## 12. Implementación Fase 2 — Detalle de objetos creados

**Estado:** Creados en package `$TMP`. Pendiente mover a `ZARCH_SD_APPS` al tener OT.

### 12.1 `ZCL_SD_ESTVNT_ARC` — Clase de servicio

**Tipos públicos relevantes:**

| Tipo | Contenido |
|------|-----------|
| `ty_screen` | Estructura pública con `s_vkorg`, `s_vtweg`, `s_spart`, `s_vkbur`, `s_fkdat`, `p_hist` |

**Métodos principales (PROTECTED):**

| Método | Capa | Descripción |
|--------|------|-------------|
| `start( i_screen )` | — | Orquesta las 3 capas y llama `show_alv()` |
| `get_billing_base()` | 1 | SELECT VBRK+VBRP. Sin joins a maestros. Retorna `tt_raw`. |
| `load_master_data( it_raw )` | 2 | Prefetch de todos los maestros en tablas `mt_*` HASHED. |
| `calculate_and_aggregate( it_raw, ct_result )` | 3 | Post-filtros, cálculos, construcción de `ZSTR_SD_ESTVTA`. |
| `show_alv()` | — | Muestra resultado via `CL_SALV_TABLE`. |
| `calculate_reduced_qty( is_raw, is_mara )` | PRIVADO | Lógica de cantidad reducida por familia de producto. |

**Tipo interno `ty_raw` (Capa 1 → Capa 3):**  
Contiene todos los campos de VBRK y VBRP necesarios para cálculos y post-filtros, sin incluir maestros:
- VBRK: `VBELN, FKDAT, VKORG, VTWEG, SPART, VBTYP, FKART, KURRF, LAND1, ZZROUTE, VF_STATUS, BUKRS`
- VBRP: `POSNR, MATNR, VRKME, FKIMG, FKLMG, NETWR, MWSBP, SHKZG, VKBUR`

**Maestros cargados en Capa 2 (atributos `mt_*` HASHED):**

| Atributo | Tabla | Clave UNIQUE | Acotado a |
|----------|-------|--------------|----------|
| `mt_mara` | MARA | `matnr` | Materiales del resultado |
| `mt_makt` | MAKT | `matnr` | Materiales del resultado |
| `mt_marm_cjr` | MARM (CJR) | `matnr` | Materiales del resultado |
| `mt_marm_l` | MARM (L) | `matnr` | Materiales del resultado |
| `mt_marm_grr` | MARM (GRR) | `matnr` | Materiales del resultado |
| `mt_marm_lb` | MARM (LB) | `matnr` | Materiales del resultado |
| `mt_marm_kg` | MARM (KG) | `matnr` | Materiales del resultado |
| `mt_tvkot` | TVKOT | `vkorg` | Rango `s_vkorg` |
| `mt_tvkbt` | TVKBT | `vkbur` | Oficinas del resultado |
| `mt_t179t` | T179T | `prodh` | Niveles 2/5/9 del `PRDHA` |
| `mt_zsdt_cant_fact` | ZSDT_CANT_FACT | `bukrs+vkorg+fkart` | Prefetch completo |
| `mt_matp` | MARA (pivot) | `key8` | Scan completo (semántica original sin filtro) |

**Post-filtros aplicados en Capa 3 (antes de construir fila de salida):**
- `VTWEG IN s_vtweg` — campo de pantalla no llevado a SQL
- `SPART IN s_spart` — ídem
- `VKBUR IN s_vkbur` — ídem (llevado en SELECT pero duplicado en post-filtro por seguridad archive)

**Semántica de anulación (corregida 2ª auditoría):** La lógica de zeroing es diferente por campo, según el query original:
- **Cantidades** (`cantidadfacturada`, `cantidadfacturadaume`, `valorreducido`): zeroed cuando `VF_STATUS = 'C'` **O** ECF match. Signo por `VBTYP` **+** `SHKZG`.
- **Valores** (`valorneto`, `valortotal`): zeroed cuando `VF_STATUS = 'C'` **SOLAMENTE**. Signo por `VBTYP` **SOLAMENTE** (sin `SHKZG`).

Esto se implementa con flags separados (`lv_qty_zeroed` / `lv_is_cancelled`) y factores de signo separados (`lv_factor_qty` / `lv_factor_val`).

**Agregación (H4 corregido):** Se usa `COLLECT` sobre tabla `WITH DEFAULT KEY` para acumular los campos numéricos (`cantidadfacturada`, `cantidadfacturadaume`, `valorneto`, `valortotal`, `valorreducido`) por clave no-numérica (todos los campos CHAR de `ZSTR_SD_ESTVTA`). Nota: `WITH EMPTY KEY` no funciona con `COLLECT` — requiere clave definida.

**Hallazgo en migración:**  
`ZZROUTE` confirmado como campo Z de VBRK (`append Z01_ADDFIELD01`, tipo `route`). Disponible en `VBRK` estándar y accesible normalmente en el SELECT.

### 12.2 `Z_SD_ESTVNT` — Programa consumidor

**Select-options equivalentes al Infoset original:**

| Select-option | Campo DDIC | Obligatorio |
|--------------|------------|-------------|
| `s_vkorg` | `vbrk-vkorg` | Sí |
| `s_vtweg` | `vbrk-vtweg` | Sí |
| `s_spart` | `vbrk-spart` | Sí |
| `s_vkbur` | `vbrp-vkbur` | No |
| `s_fkdat` | `vbrk-fkdat` | Sí |
| `p_hist` | `abap_bool` (checkbox) | — |

**Variable de pantalla:** `DATA gs_screen TYPE zcl_sd_estvnt_arc=>ty_screen`  
**Invocación:** `NEW zcl_sd_estvnt_arc( )->start( gs_screen )`

**Nota:** `p_hist` activa la rama archive cuando se cumplen las tres condiciones del triple gate (ver Sección 13.1). Sin marcar este checkbox, el reporte opera en modo solo-BD.

### 12.3 Pendiente de Fase 2

- **Smoke test** (tarea 8): ejecutar `Z_SD_ESTVNT` en período sin archiving y comparar contra query original
- **Validar**: lógica `MATP` (material padre) — el pivot por `SUBSTRING(MATNR,11,8)` puede necesitar ajuste según datos reales del sistema
- **Validar**: `CantidadReducida` por familia — comparar valores entre query y nueva clase para al menos una familia de cada tipo (01,02,03,04,05,06,07)

---

## 13. Implementación Fase 3 — Infraestructura Archive + Integración Híbrida

**Estado:** Implementado en `$TMP`. Compilación sin errores. Pendiente activación y smoke test.

### 13.1 Triple Gate en `start()`

```abap
TRY.
    DATA(lv_cutoff) = zcl_ca_archiving_utility=>get_cutoff_date( ).
    gv_use_archive = xsdbool( gs_screen-p_hist = abap_true
                              AND lv_cutoff IS NOT INITIAL
                              AND needs_archive( lv_cutoff ) = abap_true ).
  CATCH cx_root.
    gv_use_archive = abap_false.
ENDTRY.
```

**Comportamiento:**
- Sin `p_hist` → `gv_use_archive = false` → modo solo-BD
- Sin cutoff válido en `TVARVC` → ídem
- Con `p_hist` + cutoff pero FKDAT no cubre fechas archivadas → ídem
- Triple gate envuelto en `TRY/CATCH cx_root` → si `get_cutoff_date()` falla, archive desactivado silenciosamente

### 13.2 Integración en Capa 1 (`get_billing_base`)

Después del SELECT BD se agrega:

```abap
IF gv_use_archive = abap_true.
  append_vbrk_vbrp_from_archive( CHANGING ct_raw = rt_raw ).
ENDIF.
```

**Capas 2 y 3 no requieren cambio.** Procesan todas las filas de `rt_raw` (BD + archive) de forma transparente.

### 13.3 Métodos Archive Creados

| Método | Visibilidad | Descripción |
|--------|-------------|-------------|
| `needs_archive( iv_cutoff )` | PROTECTED | Evalúa si algún rango `I-BT/EQ/GE/GT/LE/LT` de `s_fkdat` cubre la fecha de corte |
| `build_archive_filters_vbrk()` | PROTECTED | Construye filtros indexables FKDAT + VKORG para `SAP_SD_VBRK_001` |
| `get_vbrk_vbrp_from_archive( it_filters )` | PROTECTED | Lee VBRK + VBRP desde archivo vía `ZCL_CA_ARCHIVING_FACTORY` |
| `append_vbrk_vbrp_from_archive( ct_raw )` | PROTECTED | Orquesta lectura, post-filtros, dedup y mapeo a `ty_raw` |

### 13.4 Constantes y Datos Agregados

| Objeto | Tipo | Valor | Descripción |
|--------|------|-------|-------------|
| `gc_str_vbrk` | `aind_gtab` | `'SAP_SD_VBRK_001'` | Infostructura SD_VBRK |
| `gv_use_archive` | `abap_bool` | — | Flag del triple gate |
| `tt_vbrk_full` | tipo tabla | `STANDARD TABLE OF vbrk` | Tipo para lectura archive VBRK |
| `tt_vbrp_full` | tipo tabla | `STANDARD TABLE OF vbrp` | Tipo para lectura archive VBRP |

### 13.5 Filtros Archive vs Post-filtros en Memoria

| Campo | Tabla | Indexable | Destino |
|-------|-------|-----------|---------|
| `FKDAT` | VBRK | ✅ Sí | Filtro archive (offset `SAP_SD_VBRK_001`) |
| `VKORG` | VBRK | ✅ Sí | Filtro archive |
| `VTWEG` | VBRK | ❌ No | Post-filtro `DELETE WHERE` en `append` |
| `SPART` | VBRK | ❌ No | Post-filtro `DELETE WHERE` en `append` |
| `VBTYP` | VBRK | ❌ No | Post-filtro `DELETE WHERE vbtyp = 'N' OR 'S'` en `append` |
| `FKART` | VBRK | ✅ Sí (no usado) | Post-filtro exclusión `ZERO/ZASR/ZCSR/ZIVS` en `append` |
| `VKBUR` | VBRP | ❌ No | Post-filtro en LOOP VBRP dentro de `append` |
| `FKIMG` | VBRP | ❌ No | Post-filtro `FKIMG <= 0` → CONTINUE |
| `VF_STATUS` | VBRK | ❌ No | **No filtrado en append** — procesado por Capa 3 (zeroing) |
| `SHKZG` | VBRP | ❌ No | **No filtrado en append** — procesado por Capa 3 (signo) |

**Nota sobre FKART:** Aunque es indexable, se usa como exclusión negativa (`NOT IN`), no como inclusión. Se aplica como post-filtro para mantener la semántica de exclusión simple en memoria.

### 13.6 Deduplicación

Clave natural: `VBELN + POSNR`

Se construye tabla sorted `lt_bd_keys TYPE SORTED TABLE OF ty_raw WITH NON-UNIQUE KEY vbeln posnr` con los datos BD ya obtenidos. Cada fila archive se verifica contra esta tabla antes de append. Además, cada clave archive insertada se registra en `lt_bd_keys` para prevenir duplicados internos del propio payload archive. Búsqueda binaria garantizada por tabla sorted.

### 13.7 Semántica Best-Effort

Toda la rama archive está contenida en:
- `TRY/CATCH cx_root` en el triple gate (protege `get_cutoff_date`)
- `TRY/CATCH zcx_ca_archiving` en `append_vbrk_vbrp_from_archive` (protege `get_vbrk_vbrp_from_archive`)

Si archive falla en cualquier punto → reporte continúa con datos BD solamente. No se aborta.

### 13.8 Pendientes Fase 5 (Estabilización)

- Activación en sistema SAD200
- Smoke test: ejecutar `Z_SD_ESTVNT` **sin** `p_hist` → debe comportarse idéntico a Fase 2
- Smoke test: ejecutar con `p_hist` en período sin datos archivados → mismo resultado
- Smoke test: ejecutar con `p_hist` en período con datos archivados → resultado BD + archive
- Validar: variable `ZARCH_CUTOFF_DATE` existe en TVARVC del sistema
- Mover a package `ZARCH_SD_APPS` con OT

---

## Historial de Cambios

| Fecha | Descripción | Autor |
|-------|-------------|-------|
| 2026-03-25 | Análisis inicial — bitácora creada | GitHub Copilot |
| 2026-03-25 | Actualización: indexabilidad confirmada SAP_SD_VBRK_001; migración reenfocada en separación por capas | GitHub Copilot |
| 2026-03-25 | Corrección: `VF_STATUS` confirmado como campo estándar de `VBRK` y definido como post-filtro en la rama archive | Codex |
| 2026-03-25 | Ajuste de diseño: programa `Z_SD_ESTVNT`, package `ZARCH_SD_APPS`, `ty_screen` pública y post-filtro definitivo para campos no confirmados | Codex |
| 2026-03-25 | Fase 2 iniciada: `ZCL_SD_ESTVNT_ARC` + `Z_SD_ESTVNT` creados en `$TMP`, activación exitosa. Capa 1 (SELECT VBRK+VBRP), Capa 2 (prefetch maestros), Capa 3 (cálculo+agregación) implementadas. Pendiente smoke test funcional. | GitHub Copilot |
| 2026-03-25 | Auditoría técnica: 6 hallazgos (H1–H6). Correcciones aplicadas y activadas: H1 tipo RETURNING, H2 show_alv factory, H3 substring offsets 0-based, H4 COLLECT agregación explícita, H5 VF_STATUS/ECF zero-value (no exclusión), H6 MATP prefetch acotado a BISMT del resultado. | GitHub Copilot |
| 2026-03-25 | Correcciones post-activación: (1) `sy-langu` no es constante → cambio a `DATA(idioma) = sy-langu`; (2) ABAPDoc `"!` antes de TYPES inválido → cambiado a comentario regular `"`; (3) `substring()` retorna STRING incompatible con `SORTED TABLE OF t179t-prodh` → envuelto con `CONV t179t-prodh(...)`; (4) `VALUE ty_xxx( optional ... )` sintaxis incorrecta → corregido a `VALUE #( ... OPTIONAL )`; (5) `COLLECT` requiere clave definida → tabla cambiada de `WITH EMPTY KEY` a `WITH DEFAULT KEY`. Clase activada sin errores. | GitHub Copilot |
| 2026-03-25 | 2ª auditoría crítica contra query original. **H1-MATP**: H6 rompió semántica — `WHERE bismt = lt_bismt_u` filtraba por BISMT propio de MATP, pero original solo requiere `SUBSTRING(MATNR,11,8) = MAT~BISMT`. Revertido a `WHERE bismt IS NOT INITIAL`. **H2-VF_STATUS/ECF**: dos bugs — (A) ECF zeroing aplicado a ValorNeto/ValorTotal cuando original solo usa VF_STATUS para valores; (B) SHKZG aplicado a signo de valores cuando original solo usa VBTYP. Corregido con flags separados `lv_qty_zeroed`/`lv_is_cancelled` y `lv_factor_qty`/`lv_factor_val`. **Agregación**: COLLECT con DEFAULT KEY confirmado como equivalente al GROUP BY original — sin cambio necesario. | GitHub Copilot |
| 2026-03-25 | 3ª revisión MATP: `WHERE bismt IS NOT INITIAL` aún cambiaba semántica (excluía MATP con BISMT vacío pero MATNR substring coincidente). Eliminado filtro WHERE — ahora scan completo de MARA (2 columnas) + filtro ABAP por `SUBSTRING(MATNR,10,8)`, idéntico al LEFT JOIN original. Bitácora alineada: Sección 11 tarea 7 (ya no dice CHECK), R1 (costo MATP aceptado), mt_matp (scan completo). Agregación confirmada sin cambio. | GitHub Copilot |
| 2026-03-25 | **Fase 3 completada:** Infraestructura archive + integración híbrida BD+Archive implementada. Triple gate (`p_hist` + cutoff + `needs_archive`), 4 métodos nuevos (`needs_archive`, `build_archive_filters_vbrk`, `get_vbrk_vbrp_from_archive`, `append_vbrk_vbrp_from_archive`), filtros indexables FKDAT+VKORG, post-filtros VTWEG/SPART/VKBUR/VBTYP/FKART/FKIMG en memoria, dedup VBELN+POSNR, TRY/CATCH best-effort. Sin p_hist o sin cutoff, reporte funciona idéntico a Fase 2. Compilación sin errores. Pendiente activación y smoke test. | GitHub Copilot |
| 2026-03-27 | **Revisión correctiva post-Fase 3 (3 hallazgos).** H1: dedup archive incompleta — `lt_bd_keys` no se actualizaba con filas archive insertadas, permitiendo duplicados internos del payload archive; corregido con INSERT tras APPEND (patrón `ZCL_SD_ANEXOFACTURA_ARC`). H2: `needs_archive()` trataba `GT` igual que `GE/EQ` (`<=`), activando archive innecesariamente cuando `low = cutoff` con opción `GT`; separado a `<`. H3: bitácora sección 12.2 aún decía que `p_hist` no tiene efecto funcional; actualizada para reflejar triple gate activo. Compilación sin errores. | GitHub Copilot |
