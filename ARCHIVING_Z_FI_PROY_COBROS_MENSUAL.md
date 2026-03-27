# Bitácora de Archiving — Z_FI_PROY_COBROS_MENSUAL_ARC

**Inicio:** 2026-03-24
**Sistema:** SAD200
**Responsable:** (asignar)
**Estado actual:** 🟡 PARCIAL — 1 bloqueante (C1-ARC), 2 altos (A1-ARC, A2-ARC), 2 medios (M1-ARC, M3-ARC), 1 arquitectónico (ARQ-ARC). Auditoría final 2026-03-26.
**Alcance archive:** Solo módulo SD (`SD_VBRK` → `VBRK`/`VBRP`). Las tablas FI (`BSID`, `BSEG`, `BKPF`, `BSAD`) permanecen **vigentes en base de datos** — fuera de scope de archiving.

---

## 1. Objeto auditado

| Artefacto | Nombre |
|---|---|
| Programa principal | `Z_FI_PROY_COBROS_MENSUAL_ARC` |
| Include declaraciones | `ZFII_PROY_COBROS_MENS_ARC_001` |
| Include lógica | `ZFII_PROY_COBROS_MENS_ARC_002` |
| Paquete | `ZARCH_MAIN/ZARCH_FI_APPS` |
| Programa base original | `Z_FI_PROY_COBROS_MENSUAL` (clonado a derivado ARC) |

---

## 2. Descripción funcional

Proyección mensual de cobros de deudores (partidas abiertas FI). Dos modos de operación:

| Parámetro | Modo | Fuente |
|---|---|---|
| `p_ejec = 'X'` | Ejecución en vivo | `BSID` via `BAPI_AR_ACC_GETOPENITEMS` |
| `p_hist = 'X'` | Histórico | `ZFIT_PRO_COB_POS` (snapshot Z) |

> **Alcance de archiving:** Las tablas FI permanecen vigentes en BD. El único archive relevante es **`SD_VBRK`** → enriquecimiento de `VBRK`/`VBRP`.

---

## 3. Arquitectura actual

> **Clasificación:** Programa con includes + FORMs. Snapshot en tabla Z. Enriquecimiento SD archive en FORMs inline.

### Tablas Z propias (snapshot)
| Tabla | Rol |
|---|---|
| `ZFIT_PRO_COB_CAB` | Cabecera del snapshot |
| `ZFIT_PRO_COB_POS` | Posiciones del snapshot |

### Flujo de enriquecimiento SD archive
1. `FORM init_cutoff` → determina `gv_cutoff_date` y `gv_use_archive`
2. `FORM collect_vbeln_from_records` → extrae VBELNs de `awkey(10)` donde `awtyp = 'VBRK'`
3. `FORM load_vbrk_hybrid` / `FORM load_vbrp_hybrid` → BD primero, faltantes desde `SD_VBRK` vía `ZCL_CA_ARCHIVING_FACTORY`
4. Resultado en `gt_vbrk_final` / `gt_vbrp_final`
5. Loop principal usa `READ TABLE gt_vbrk_final` en lugar de `SELECT SINGLE FROM vbrk`

> ✅ **Validado:** Clases `ZCL_CA_ARCHIVING_FACTORY`, `ZCL_CA_ARCHIVING_QUERY_CTRL` e infostructura `SAP_SD_VBRK_001` confirmadas en SAD200.

---

## 4. Criterio temporal real

| Campo | Contexto | Descripción |
|---|---|---|
| `s_bldat` | **Lógica FI (BD)** | Fecha de documento — criterio de corte para vencimientos. Siempre vía BAPI. |
| `s_budat` | **Lógica FI (BD)** | Fecha de contabilización — filtro secundario. |
| `gv_cutoff_date` | **Gating SD archive** | Desde `TVARVC`. Activa lectura de `VBRK`/`VBRP` desde `SD_VBRK`. |

> **Separación:** `s_bldat` controla negocio FI. `gv_cutoff_date` controla gating archive SD. Son independientes.

---

## 5. Tablas: core vs auxiliares

### Core (definen universo funcional)

| Tabla | Estado archive |
|---|---|
| `BSID` / `BSEG` / `BKPF` / `BSAD` | 🟢 Vigente en BD — fuera de scope |

> Partidas abiertas no pueden archivarse en `FI_DOCUMNT`. Sin cambios necesarios en capa FI.

### Auxiliares (enriquecimiento)

| Tabla | Archive | Tratamiento |
|---|---|---|
| `VBRK` | ✅ `SD_VBRK` | Híbrido BD + archive |
| `VBRP` | ✅ `SD_VBRK` | Híbrido BD + archive |
| `VBPA` | `SD_VBAK` | Best-effort BD — no recuperable desde `SD_VBRK` |
| `VBFA` / `VBKD` | `SD_VBAK` | Best-effort BD — limitación documentada |
| `KNA1`, `AVIK`, `AVIP`, `ADRC`, `PA0002`, `KNVP`, maestros | No | BD siempre |

---

## 6. Familia archive — SD_VBRK

| Atributo | Valor | Estado |
|---|---|---|
| Objeto físico | `SD_VBRK` | ✅ |
| Familia lógica | `VBRK + VBRP` | ✅ |
| Infostructura | `SAP_SD_VBRK_001` | ✅ |
| Campo indexable principal | `VBELN` | ✅ |
| Campos indexables secundarios | `FKDAT`, `KUNRG` | ✅ |
| Clase lectora | `ZCL_CA_ARCHIVING_FACTORY` | ✅ |
| Clase de query | `ZCL_CA_ARCHIVING_QUERY_CTRL` | ✅ |

---

## 7. Hallazgos de auditoría — Estado actual

### 7.1 Hallazgos activos (pendientes de corrección)

| ID | Sev. | Hallazgo | Ubicación | Corrección mínima |
|---|---|---|---|---|
| **C1-ARC** | 🔴 Bloqueante | **Gating impreciso:** `FORM init_cutoff` usa `s_bldat <= gv_cutoff_date` — la fecha FI del usuario desactiva el archive en ejecuciones normales. **Todo el código híbrido es código muerto en producción.** | `FORM init_cutoff` — `_002` | Cambiar a `gv_use_archive = xsdbool( gv_cutoff_date IS NOT INITIAL )`. Los VBELNs faltantes en BD son el filtro natural. |
| **A1-ARC** | 🟠 Alto | **Bloque DZ bypasea `gt_vbrk_final`:** `FORM preload_dz_caches` (BP4) hace `SELECT FROM vbrk` sin consultar `gt_vbrk_final`. Compensaciones con factura archivada pierden `vtweg`/`vkorg`. | `FORM preload_dz_caches` BP4 — `_002` | Tras el SELECT, completar faltantes con `LOOP/READ TABLE gt_vbrk_final`. |
| **A2-ARC** | 🟠 Alto | **VBPA sin trazabilidad:** Para facturas archivadas, `pernr` queda vacío. Sin contador ni mensaje. Limitación SAP (`VBPA` → `SD_VBAK`). | `FORM load_vbpa_hybrid` + loop DZ — `_002` | Agregar `gv_cnt_vbpa_missing` + mensaje informativo al final de `get_data_bsid`. |
| **M1-ARC** | 🟡 Medio | **`awkey(10)` sin guard:** Si `strlen(awkey) < 10`, dump `CX_SY_RANGE_OUT_OF_BOUNDS` no capturado. | `FORM collect_vbeln_from_records` — `_002` | Agregar `CHECK strlen( <rec_aux>-awkey ) >= 10` antes del offset. |
| **M3-ARC** | 🟡 Medio | **CATCH sin log:** `CATCH zcx_ca_archiving` no emite mensaje — sin trazabilidad en QA. | `FORM load_vbrk_hybrid`, `load_vbrp_hybrid` — `_002` | Agregar `MESSAGE lcx->get_text( ) TYPE 'S' DISPLAY LIKE 'W'`. |
| **ARQ-ARC** | 🟡 Arquitectónico | **Archiving en FORMs inline vs clase de servicio:** La lógica de archive está dispersa en 6+ FORMs con variables globales. Las 3 implementaciones de referencia usan clases de servicio con métodos encapsulados, `needs_archive()` testeable y gestión de estado por instancia. Ver §8 para análisis completo. | `_001` + `_002` (todo el bloque archive) | No bloquea producción. Si se planea evolución futura (nuevas familias, reuso), considerar migración a clase `ZCL_FI_PROY_COBROS_ARC_SRV`. |

### 7.2 Hallazgos resueltos (Fase 1-2 del programa base)

| ID | Hallazgo | Estado |
|---|---|---|
| C1-base | Sin validación `p_rango` | ✅ Resuelto en ARC |
| C2-base | `BREAK` activos en producción (≥7) | ✅ Resuelto en ARC |
| C3-base | `COMMIT WORK` sin `ROLLBACK` | ✅ Resuelto en ARC |
| A1-base | `authority_check` comentado | ✅ Resuelto en ARC |
| A3/A4/A5-base | `SELECT SINGLE` en loops (koart/bktxt/ltext) | ✅ Resuelto en ARC — pre-cargas implementadas |

### 7.3 Hallazgos informativos / bajo riesgo

| ID | Hallazgo | Estado |
|---|---|---|
| I1 | `gt_bkpf_cache` declarado en `_001` pero nunca usado — código muerto | 🔲 Nota |
| I2 | `VBFA`/`VBKD` limitación `SD_VBAK` correctamente documentada | ✅ Correcto |
| I3 | `BKPF`/`BSEG` justificación no-archiving FI correcta | ✅ Correcto |
| I4 | Pre-carga `T003T` en tabla hash implementada correctamente | ✅ Correcto |
| M2-base | Scope `lt_j_1bbranch` entre forms | 🔲 Bajo riesgo |
| M3-base | Snapshot no graba parámetros completos | 🔲 Mejora funcional |
| M4-base | `SELECT` en `TOP_OF_PAGE` | 🔲 Bajo riesgo |

---

## 8. Análisis arquitectónico: FORMs inline vs clase de servicio

### 8.1 Contexto

La guía normativa (`ARCHIVING_IMPLEMENTATION_GUIDE_ES.md` §3, §16) recomienda migrar a **programa ABAP + clase de servicio** cuando se necesita gating temporal controlado, lectura condicional de archive, testabilidad y trazabilidad técnica.

Las 3 implementaciones de referencia validadas en SAD200 siguen ese patrón:

| Clase | Patrón | Métodos archive |
|---|---|---|
| `ZCL_PM_FACTORDENSERVICIO_ARC` | Enrich, triple gate | `needs_archive()`, `build_archive_filters_vbrk()`, `enrich_vbrk_from_archive()`, `enrich_vbrp_from_archive()`, `get_vbrk_vbrp_from_archive_arc()` |
| `ZCL_SD_ANEXOFACTURA_ARC` | Append, triple gate | `needs_archive()`, `build_archive_filters_vbrk()`, `append_detail_from_archive()`, `get_vbrk_vbrp_from_archive()` |
| `ZCL_SD_ESTVNT_ARC` | Layered (capas) | Arquitectura preparada para inyección en Capa 1 |

### 8.2 Comparativa: implementación actual vs patrón de referencia

| Aspecto | Implementación actual (FORMs) | Patrón de referencia (Clase) |
|---|---|---|
| **Encapsulación** | 6+ FORMs dispersos en `_002` (`init_cutoff`, `collect_vbeln`, `load_vbrk_hybrid`, `load_vbrp_hybrid`, `load_vbpa_hybrid`, `preload_dz_caches`). Lógica archive mezclada con lógica FI. | Métodos privados/protegidos. Lógica archive separada de lógica de negocio. |
| **Estado** | Variables globales en `_001` (`gv_cutoff_date`, `gv_use_archive`, `gt_vbrk_final`, `gt_vbrp_final`, `gt_vbeln_all`, `gt_vbeln_arc`). Cualquier FORM puede leer/escribir. | Atributos de instancia. Estado gestionado por el objeto. |
| **Gating** | `IF gv_cutoff_date IS NOT INITIAL AND s_bldat <= gv_cutoff_date` — evaluación inline sin `needs_archive()`. No testeable unitariamente. | `needs_archive( iv_cutoff ir_fkdat )` — método protegido, determinístico, testeable. Triple gate: `p_hist + cutoff + needs_archive()`. |
| **Testabilidad** | No testeable unitariamente. Toda la lógica depende de variables globales y pantalla de selección. | `needs_archive()` testeable con inputs explícitos. Métodos de filtro testeable aislados. |
| **Reuso** | No reutilizable. Si otro programa FI necesita leer SD_VBRK archivado, debe reimplementar los mismos FORMs. | Clase instanciable y reutilizable por cualquier consumidor. |
| **Duplicación de query** | `load_vbrk_hybrid` y `load_vbrp_hybrid` construyen query controller independientemente — código duplicado (mismos filtros, misma infostructura). | `build_archive_filters_vbrk()` centralizado — un solo punto de construcción de filtros, reutilizado por `enrich_vbrk` y `enrich_vbrp`. |
| **Evolución** | Agregar una nueva familia (e.g., `SD_VBAK` para VBFA) requiere más variables globales, más FORMs, más acoplamiento. | Agregar familia = agregar método privado + llamada en el método de orquestación. |

### 8.3 Valoración del hallazgo ARQ-ARC

**Severidad: 🟡 Arquitectónico (no bloqueante)**

El patrón de FORMs **funciona**. La lógica de BD + archive es correcta cuando C1-ARC se corrige. No hay error funcional derivado de usar FORMs vs clase.

**Sin embargo:**
1. **Diverge del estándar del proyecto.** Las 3 implementaciones previamente auditadas y validadas usan clases de servicio. Mantener FORMs inline crea una excepción que dificulta auditorías futuras.
2. **`needs_archive()` no existe.** El gating más robusto (triple gate) no es posible sin un método determinístico. La corrección de C1-ARC simplifica el gating, pero sigue siendo un `IF` inline.
3. **Duplicación.** `load_vbrk_hybrid` y `load_vbrp_hybrid` repiten la construcción de `zcl_ca_archiving_query_ctrl` con los mismos filtros y la misma infostructura.
4. **No testeable.** Imposible ejecutar test unitario sobre el gating o la lógica de mezcla BD+Archive sin ejecutar el programa completo.

**Recomendación:**
- **Corto plazo (Fase actual):** Corregir C1-ARC a M3-ARC con FORMs actuales. No bloquear el transporte por refactor de arquitectura.
- **Mediano plazo:** Si se planea evolución (soporte `SD_VBAK` para VBFA, nuevos consumidores FI que necesiten archive SD), migrar a clase `ZCL_FI_PROY_COBROS_ARC_SRV` con métodos `needs_archive()`, `load_hybrid_sd()`, `get_enriched_records()`.
- **Esfuerzo estimado de migración:** Bajo-medio. Los FORMs ya están separados en bloques lógicos. La migración es esencialmente mover cada FORM a un método y reemplazar variables globales por atributos de instancia.

---

## 9. Plan de correcciones pendientes

### Correcciones requeridas antes de transporte

| Prioridad | ID | Acción |
|---|---|---|
| 🔴 1 | C1-ARC | Corregir `FORM init_cutoff`: `gv_use_archive = xsdbool( gv_cutoff_date IS NOT INITIAL )` |
| 🟠 2 | A1-ARC | En `FORM preload_dz_caches` BP4: completar `gt_vbrk_dz_cache` con faltantes de `gt_vbrk_final` |
| 🟠 3 | A2-ARC | Agregar `gv_cnt_vbpa_missing` + mensaje informativo |
| 🟡 4 | M1-ARC | Guard `CHECK strlen(...) >= 10` en `FORM collect_vbeln_from_records` |
| 🟡 5 | M3-ARC | `MESSAGE` en `CATCH zcx_ca_archiving` de `load_vbrk_hybrid` / `load_vbrp_hybrid` |

### Mejoras recomendadas (no bloquean transporte)

| ID | Acción |
|---|---|
| ARQ-ARC | Evaluar migración a clase de servicio cuando se planee evolución |
| I1 | Eliminar `gt_bkpf_cache` (código muerto) |
| M4-base | Mover SELECT de `ZFIT_PRO_COB_CAB` fuera de `TOP_OF_PAGE` |

---

## 10. Limitaciones conocidas y aceptadas

| Limitación | Impacto | Decisión |
|---|---|---|
| `VBPA` no recuperable desde `SD_VBRK` | Partner vacío para facturas archivadas | Aceptada — agregar contador (A2-ARC) |
| `VBFA`/`VBKD` solo en `SD_VBAK` | `bstkd_e` ausente para facturas archivadas | Aceptada — best-effort BD |
| FI permanece en BD | Sin impacto | N/A — fuera de scope |

---

## 11. Resumen ejecutivo

| Categoría | Cant. | Detalle |
|---|---|---|
| 🔴 Bloqueante | 1 | C1-ARC: gating impide activación de archive en uso real |
| 🟠 Alto | 2 | A1-ARC: bloque DZ bypasea hybrid; A2-ARC: VBPA sin trazabilidad |
| 🟡 Medio | 2 | M1-ARC: awkey sin guard; M3-ARC: CATCH sin log |
| 🟡 Arquitectónico | 1 | ARQ-ARC: FORMs inline vs clase de servicio — diverge del estándar |
| 🔵 Info | 3 | Código muerto, mejoras menores |

**Conclusión final: PARCIAL**

La infraestructura de archiving SD está correctamente diseñada y las clases de soporte validadas. Los patrones de enriquecimiento, mezcla BD+Archive, filtros por indexable y TRY/CATCH son estructuralmente correctos. El bloqueante C1-ARC impide que el archive se active en condiciones reales. Se requieren 5 correcciones antes de producción. La arquitectura basada en FORMs funciona pero diverge del patrón validado del proyecto (clases de servicio); se recomienda evaluar migración en evolución futura.

---

## 12. Registro de cambios

| Fecha | Autor | Descripción |
|---|---|---|
| 2026-03-24 | Auditoría inicial | Creación de bitácora. Hallazgos snapshot Z: C1–C3, A1–A5, M1–M4. |
| 2026-03-25 | Auditoría SD archive | Hallazgos archive: C1-ARC (bloqueante), A1-ARC, A2-ARC, M1-M3-ARC. Anulados C2-ARC, C3-ARC, A1-ARC-old tras validación real de clases. |
| 2026-03-25 | Ajuste de scope | FI fuera de scope confirmado. Solo archive SD aplica. |
| 2026-03-26 | Auditoría final + clean | Validación cruzada código ↔ bitácora ↔ guía. Limpieza de hallazgos anulados y resueltos. Nuevo hallazgo ARQ-ARC (FORMs vs clase de servicio). Bitácora reestructurada a estado actual limpio. |
