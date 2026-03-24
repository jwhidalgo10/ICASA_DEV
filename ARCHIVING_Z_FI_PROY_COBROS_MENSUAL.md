# Bitácora de Archiving — Z_FI_PROY_COBROS_MENSUAL_ARC

**Inicio:** 2026-03-24
**Sistema:** SAD200
**Responsable:** (asignar)
**Estado actual:** 🔴 NO LISTO — bloqueantes identificados en auditoría inicial

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

Proyección mensual de cobros de deudores (partidas abiertas FI). El programa tiene dos modos de operación:

| Parámetro | Modo | Fuente |
|---|---|---|
| `p_ejec = 'X'` | Ejecución en vivo | `BSID` via `BAPI_AR_ACC_GETOPENITEMS` |
| `p_hist = 'X'` | Histórico | `ZFIT_PRO_COB_POS` (snapshot Z) |

---

## 3. Arquitectura del mecanismo "archiving" actual

> **Clasificación:** Snapshot en tabla Z — **NO es archiving SAP estándar (SARA)**

### Tablas Z propias del mecanismo
| Tabla | Rol |
|---|---|
| `ZFIT_PRO_COB_CAB` | Cabecera del snapshot (nivel, fecha, sociedad, comentario) |
| `ZFIT_PRO_COB_POS` | Posiciones del snapshot (copia de `t_print[]` en el momento de grabar) |

### Objetos de soporte
| Objeto | Uso |
|---|---|
| `ZPROYCOBRO` | Número de objeto para `NUMBER_GET_NEXT` — numerador de niveles |
| `ZSH_FI_PRO_COB_MEN` | Match code para `p_rango` (selección de snapshot) |

### Flujo de guardado
1. El usuario ejecuta en modo `p_ejec`
2. Visualiza el ALV con partidas calculadas
3. Presiona `&SAVE` → `user_command` → `FORM pop_up`
4. `pop_up` llama `NUMBER_GET_NEXT` para obtener `nrlevel`
5. Se graba `ZFIT_PRO_COB_CAB` (cabecera) y luego `ZFIT_PRO_COB_POS` (posiciones) via `COMMIT WORK` por fila
6. El campo `it_print-histo = 'X'` marca la fila como guardada en pantalla

### Flujo de lectura histórica
1. El usuario selecciona `p_hist` e ingresa `p_rango` (nivel del snapshot)
2. `get_data_history` lee `ZFIT_PRO_COB_POS` por `nrlevel`
3. Los datos se mueven a `t_print` directamente
4. `it_print` NO se procesa (correcto)

---

## 4. Criterio temporal real

| Campo | Descripción | Uso |
|---|---|---|
| `s_bldat` | Fecha de documento (`BLDAT`) | Criterio principal de corte temporal |
| `s_budat` | Fecha de contabilización (`BUDAT`) | Filtro secundario en `get_data_bsid` |

> **Referencia guía §4.2:** Criterio temporal real identificado como `s_bldat` (fecha de documento),
> validado en `AT SELECTION-SCREEN ON s_bldat` (include `_001`, línea ~540).
> La fecha se usa como cutoff para calcular `ven_date`, `ven_days` y la distribución en tramos de vencimiento.

---

## 5. Tablas: core vs auxiliares

### Tablas core (definen el universo funcional del reporte)

| Tabla | Descripción | Archivable en SAP |
|---|---|---|
| `BSID` | Índice secundario de deudores (partidas abiertas) | ✅ `FI_DOCUMNT` |
| `BSEG` | Posiciones de documento contable | ✅ `FI_DOCUMNT` |
| `BKPF` | Cabeceras de documento contable | ✅ `FI_DOCUMNT` |
| `BSAD` | Deudores compensados (via `BAPIACITEM`) | ✅ `FI_DOCUMNT` |

> Acceso vía BAPI: `BAPI_AR_ACC_GETOPENITEMS` (el BAPI resuelve el join `BSID/BSEG/BKPF` internamente).

### Tablas auxiliares (enriquecimiento)

| Tabla | Descripción | Archivable |
|---|---|---|
| `KNA1` | Maestro de clientes | No (maestro) |
| `VBRK` | Cabecera de factura SD | ✅ `SD_VBRK` |
| `VBRP` | Posición de factura SD | ✅ `SD_VBRK` |
| `VBPA` | Partners del documento SD | ✅ `SD_VBAK`? |
| `VBFA` | Flujo de documentos SD | ✅ |
| `VBKD` | Datos comerciales del pedido | ✅ `SD_VBAK` |
| `AVIK` | Aviso de pago (cabecera) | No (generalmente) |
| `AVIP` | Aviso de pago (posición) | No |
| `ADRC` | Direcciones | No |
| `J_1BBRANCH` | Lugar comercial (Brasil) | No |
| `PA0002` | Infotipo HR — datos personales | No (HR) |
| `KNVP` | Partners de cliente | No |
| `T001W`, `T188T`, `TVTWT` | Textos maestros | No |
| `T003T` | Textos clase de documento | No |

---

## 6. Familia archive candidata (SAP estándar)

### Para tablas core (BSID/BSEG/BKPF)

| Atributo | Valor candidato |
|---|---|
| Objeto físico | `FI_DOCUMNT` |
| Infostructura | Por confirmar en SARI / `ZCL_CA_ARCHIVING_FACTORY` |
| Campos indexables típicos | `BUKRS`, `BELNR`, `GJAHR`, `BLDAT`, `BUDAT` |

> ⚠️ **NOTA CRÍTICA:** El programa usa `BAPI_AR_ACC_GETOPENITEMS` para leer `BSID/BSEG/BKPF`. Este BAPI **no tiene una contraparte directa de archive**. Replicar su funcionalidad desde `FI_DOCUMNT` requeriría reconstruir la lógica de partidas abiertas/compensadas desde los datos archivados, lo cual es significativamente complejo.

### Para tablas auxiliares SD (VBRK/VBRP)

| Atributo | Valor candidato |
|---|---|
| Objeto físico | `SD_VBRK` |
| Familia lógica | `VBRK + VBRP` |
| Infostructura | Confirmar en sistema (ej: `SAP_SD_VBRK_001`) |
| Campos indexables típicos | `VBELN`, `FKDAT`, `KUNRG`, `BUKRS` |

---

## 7. Análisis de bloqueos para archiving SAP estándar

### Bloqueo principal: BAPI sin contraparte de archive

El flujo de datos vivos depende de `BAPI_AR_ACC_GETOPENITEMS`, que internamente:
- lee `BSID/BSAD`
- aplica lógica de partidas abiertas/compensadas
- maneja monedas, índices secundarios, clasificaciones

**No existe** un equivalente BAPI para leer partidas FI archivadas con la misma semántica. Opciones:
1. Leer `FI_DOCUMNT` directamente via infostructura — solo partidas compensadas o filtros simples
2. Reconstruir la lógica de partidas abiertas desde datos crudos archivados — alta complejidad
3. Mantener el snapshot Z como mecanismo de histórico — ya implementado, solución pragmática

### Bloqueo secundario: tablas SD auxiliares
`VBRK/VBRP` se leen dentro del flujo de enriquecimiento. Si están archivadas, se puede usar `SD_VBRK` con patrón `enrich`. Esto es independiente y más factible.

---

## 8. Decisión arquitectónica requerida (PENDIENTE de usuario)

Existen dos caminos posibles:

### Opción A — Fortalecer el snapshot Z actual
- Arreglar bloquantes del audit (C1, C2, C3, A1, A2, M1)
- Agregar validaciones faltantes
- Documentar explícitamente que es snapshot, no archive SAP
- Agregar enriquecimiento desde `SD_VBRK` si VBRK/VBRP están archivadas

### Opción B — Agregar lectura desde `FI_DOCUMNT`
- Requiere análisis profundo de cómo leer partidas abiertas desde archive
- Requiere validar infostructura en sistema
- Requiere reconstruir lógica de `BAPI_AR_ACC_GETOPENITEMS`
- Alta complejidad, riesgo significativo

> **Recomendación preliminar:** Opción A. El snapshot Z es funcionalmente correcto para el caso de uso (recuperar proyecciones históricas). Opción B solo si el requerimiento es leer partidas nuevas del pasado que nunca se snapshotearon.

---

## 9. Plan de fases propuesto (Opción A)

### Fase 1 — Corrección de bloqueantes (OBLIGATORIA antes de go-live)
- [ ] **C2:** Eliminar todos los `BREAK` activos (≥7 instancias en `_002`)
- [ ] **C3:** Refactorizar `FORM pop_up` con un único `COMMIT WORK` + `ROLLBACK WORK` ante error
- [ ] **C1 + A2:** Agregar validación de `p_rango` en `AT SELECTION-SCREEN`
- [ ] **A1:** Descomentar `PERFORM authority_check`
- [ ] **M1:** Corregir lógica de `saldo` en `FORM normal` (condición duplicada)

### Fase 2 — Estabilización de performance (recomendada)
- [ ] **A3:** Eliminar `SELECT SINGLE koart` en loop — pre-cargar desde `BSEG`
- [ ] **A4:** Eliminar `SELECT SINGLE bktxt` en loop — agregar a `SELECT BKPF`
- [ ] **A5:** Eliminar `SELECT SINGLE ltext` en loop — pre-cargar `T003T`
- [ ] **M4:** Mover `SELECT` de `ZFIT_PRO_COB_CAB` fuera de `TOP_OF_PAGE`

### Fase 3 — Completitud del snapshot (mejora funcional)
- [ ] **M2:** Verificar scope de `lt_j_1bbranch` entre forms
- [ ] **M3:** Grabar parámetros de selección completos en `ZFIT_PRO_COB_CAB`

### Fase 4 — Enriquecimiento desde SD archive (opcional, si VBRK archivado)
- [ ] Validar en `ZCL_CA_ARCHIVING_FACTORY`: existencia de `gc_vbrk`, `gc_vbrp`
- [ ] Validar infostructura `SD_VBRK` e indexabilidad de campos usados
- [ ] Agregar `enrich_vbrk_from_archive()` en `get_data_bsid`
- [ ] Agregar `enrich_vbrp_from_archive()` en `get_data_bsid`
- [ ] Post-filtro en memoria para campos no indexables

---

## 10. Hallazgos de auditoría (2026-03-24)

| ID | Severidad | Hallazgo | Estado |
|---|---|---|---|
| C1 | 🔴 | Sin validación `p_rango` en `get_data_history` | 🔲 Pendiente |
| C2 | 🔴 | `BREAK` activos en producción (≥7) | 🔲 Pendiente |
| C3 | 🔴 | `COMMIT WORK` sin `ROLLBACK` en `pop_up` | 🔲 Pendiente |
| A1 | 🟠 | `authority_check` comentado | 🔲 Pendiente |
| A2 | 🟠 | Sin validación `AT SELECTION-SCREEN ON p_rango` | 🔲 Pendiente |
| A3 | 🟠 | `SELECT SINGLE koart` en loop (`BSEG`) | 🔲 Pendiente |
| A4 | 🟠 | `SELECT SINGLE bktxt` en loop (`BKPF`) | 🔲 Pendiente |
| A5 | 🟠 | `SELECT SINGLE ltext` en loop (`T003T`) | 🔲 Pendiente |
| M1 | 🟡 | Lógica `saldo` incorrecta en `FORM normal` (condición duplicada) | 🔲 Pendiente |
| M2 | 🟡 | Scope de `lt_j_1bbranch` entre forms — verificar | 🔲 Pendiente |
| M3 | 🟡 | Snapshot no graba parámetros de selección completos | 🔲 Pendiente |
| M4 | 🟡 | `SELECT` en `TOP_OF_PAGE` por página ALV | 🔲 Pendiente |
| I1 | 🔵 | Bitácora faltante → creada 2026-03-24 | ✅ Resuelto |
| I2 | 🔵 | Mecanismo es snapshot Z, no archive SAP — documentado | ✅ Documentado |
| I3 | 🔵 | Acoplamiento `authority_check`/`get_global_data` | 🔲 Nota |

---

## 11. Registro de cambios

| Fecha | Autor | Descripción |
|---|---|---|
| 2026-03-24 | Auditoría inicial | Creación de bitácora. Análisis de includes `_001` y `_002`. Auditoría completa. Identificación de bloquantes. |
