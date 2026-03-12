# 🔍 Auditoría de Equivalencia Funcional BD + Archive
## ZCL_SD_ANEXOFACTURA_ARC

**Fecha:** 11 de marzo de 2026  
**Auditor:** GitHub Copilot (Claude Sonnet 4.5)  
**Referencia:** ARCHIVING_IMPLEMENTATION_GUIDE_ES.md  

---

## 📋 Resumen Ejecutivo

### Veredicto Final
**❌ La rama archive NO reproduce la lógica funcional del online**

### Nivel de Riesgo
🔴 **ALTO** - Riesgo de traer de más (facturas anuladas) y diferencias de semántica JOIN

### Cantidad de Desvíos Funcionales Detectados
- **Críticos:** 2
- **Advertencias:** 1
- **OK:** 7 filtros equivalentes

---

## 🎯 Comparación de Filtros Online vs Archive

### ✅ Filtros Equivalentes (Correctamente Empujados a Archive)

| Campo | Online (L225-231) | Archive (build_archive_filters_vbrk) | Estado |
|-------|-------------------|-------------------------------------|---------|
| **VKORG** | `WHERE vbrk~vkorg IN @gs_screen-s_vkorg` | `add_filter_from_range('VKORG', lr_vkorg)` L689 | ✅ OK |
| **VTWEG** | `WHERE vbrk~vtweg IN @gs_screen-s_vtweg` | `add_filter_from_range('VTWEG', lr_vtweg)` L694 | ✅ OK |
| **SPART** | `WHERE vbrk~spart IN @gs_screen-s_spart` | `add_filter_from_range('SPART', lr_spart)` L699 | ✅ OK |
| **FKART** | `WHERE vbrk~fkart IN @gs_screen-s_fkart` | `add_filter_from_range('FKART', lr_fkart)` L704 | ✅ OK |
| **FKDAT** | `WHERE vbrk~fkdat IN @gs_screen-s_fkdat` | `add_filter_from_range('FKDAT', lr_fkdat)` L684 | ✅ OK |
| **KUNAG** | `WHERE vbrk~kunag IN @gs_screen-s_kunag` | `add_filter_from_range('KUNAG', lr_kunag)` L714 | ✅ OK |
| **VBELN** | `WHERE vbrk~vbeln IN @gs_screen-s_vbeln` | `add_filter_from_range('VBELN', lr_vbeln)` L709 | ✅ OK |

**Análisis:** Los 7 filtros principales de selección están correctamente mapeados y se empujan al motor de archiving vía `ZCL_CA_ARCHIVING_QUERY_CTRL`. Estos campos son indexables en el catálogo `SAP_SD_VBRK_001`.

---

## 🔴 Desvíos Funcionales Críticos

### DESVÍO #1: Filtro FKSTO Faltante (Facturas Anuladas)

#### Descripción del Riesgo
**Online (L232):**
```abap
WHERE vbrk~fksto = @abap_false.  " ← Excluye facturas anuladas
```

**Archive (build_archive_filters_vbrk L664-719):**
```abap
" ❌ FKSTO no se empuja a filtros de archive
" ❌ No hay post-filtro en memoria en append_detail_from_archive
```

#### Impacto Funcional
- **Riesgo:** Traer de más (sobrepoblación)
- **Registros afectados:** Todas las facturas con `FKSTO = 'X'` (facturas anuladas) del período archivado
- **Semántica rota:** El online NUNCA retorna facturas anuladas, el archive SÍ puede retornarlas
- **Impacto en usuario:** Reportes con facturas que no deberían aparecer

#### Verificación de Indexabilidad
Según guía (sección "Descubrimiento Crítico: Generación de Offsets y Campos Indexables"):
- **Verificar en SARI:** Transacción SARI > SD_VBRK > SAP_SD_VBRK_001
- **Campo FKSTO:** 
  - Si está en GENTAB (panel izquierdo) → empujable a filtro archive
  - Si está solo en catálogo (panel derecho) → requiere post-filtro en memoria

#### Corrección Requerida

**Opción 1: Si FKSTO es indexable (está en GENTAB)**
```abap
METHOD build_archive_filters_vbrk.
  " ... código existente ...
  
  " 🔧 AGREGAR: Filtro FKSTO
  DATA lr_fksto TYPE /iwbep/t_cod_select_options.
  lr_fksto = VALUE #( ( sign = 'I' option = 'EQ' low = abap_false ) ).
  
  lo_query->add_filter_from_range( iv_name   = 'FKSTO'
                                   ir_values = lr_fksto ).
  
  " ... continuar con apply_filters_to_str ...
ENDMETHOD.
```

**Opción 2: Si FKSTO NO es indexable (solo catálogo) - PATRÓN RECOMENDADO**
```abap
METHOD append_detail_from_archive.
  " ... lectura de archivo existente (L788-798) ...
  
  " 🔧 AGREGAR: Post-filtro en memoria (DESPUÉS de lectura, ANTES de loop L821)
  " Eliminar facturas anuladas del resultado de archive
  DELETE lt_vbrk_arch WHERE fksto = abap_true.
  DELETE lt_vbrp_arch WHERE vbeln NOT IN lt_vbrk_arch.  " Huérfanos
  
  " ... continuar con lógica de merge existente ...
ENDMETHOD.
```

#### Prioridad
🔴 **CRÍTICA** - Implementar inmediatamente

---

### DESVÍO #2: Semántica INNER JOIN con KNA1 No Se Respeta

#### Descripción del Riesgo
**Online (L223-224):**
```abap
INNER JOIN kna1 ON kna1~kunnr = vbrk~kunag  " ← Solo facturas con cliente válido
```

**Archive (append_detail_from_archive L808-814, L840-848):**
```abap
" Best-effort lookup a KNA1 desde BD
SELECT kunnr, name1 FROM kna1
  FOR ALL ENTRIES IN @lt_kunnr
  WHERE kunnr = @lt_kunnr-table_line.

" ❌ Si cliente no existe en KNA1 → registro igual se agrega con NAME1 inicial
DATA(lv_name1) = VALUE kna1-name1( ).  " ← Vacío por defecto
ASSIGN lt_kna1_hash[ kunnr = <ls_vbrk>-kunag ] TO FIELD-SYMBOL(<ls_kna1>).
IF sy-subrc = 0.
  lv_name1 = <ls_kna1>-name1.
ENDIF.
" ← Continúa APPEND VALUE ty_detail(...) aunque lv_name1 esté vacío
```

#### Impacto Funcional
- **Riesgo:** Traer de más (sobrepoblación)
- **Registros afectados:** Facturas históricas donde `VBRK-KUNAG` ya no existe en `KNA1` (datos maestros borrados/archivados)
- **Semántica rota:** 
  - Online: INNER JOIN → 0 filas si cliente no existe
  - Archive: Lookup best-effort → 1 fila con NAME1 vacío
- **Impacto en usuario:** Facturas sin nombre de cliente en el ALV

#### Patrón Correcto Según Guía
Sección "INNER JOIN vs LEFT OUTER JOIN":
> **Regla:** Si la tabla derecha puede ser archivada Y campos de esa tabla se usan para **enriquecimiento** (no filtrado), considerar cambiar a LEFT OUTER JOIN.

**Análisis:**
- `KNA1` no es archivable (datos maestros)
- `NAME1` se usa para enriquecimiento (display ALV), NO para filtrado crítico
- **Decisión:** El patrón archive actual (lookup best-effort) es **aceptable pero inconsistente**

#### Corrección Requerida (Alinear con Semántica Online)

**Si se requiere equivalencia EXACTA con online:**
```abap
METHOD append_detail_from_archive.
  " ... lectura de archivo existente (L788-798) ...
  " ... lookup a KNA1 existente (L808-814) ...
  
  " 🔧 AGREGAR: Filtrar solo registros con cliente válido (simular INNER JOIN)
  LOOP AT lt_vbrp_arch ASSIGNING FIELD-SYMBOL(<ls_vbrp>).
    ASSIGN lt_vbrk_hash[ vbeln = <ls_vbrp>-vbeln ] TO FIELD-SYMBOL(<ls_vbrk>).
    CHECK sy-subrc = 0.
    
    " 🔧 NUEVA LÓGICA: Solo agregamos si cliente existe en KNA1
    READ TABLE lt_kna1_hash TRANSPORTING NO FIELDS
      WITH KEY kunnr = <ls_vbrk>-kunag.
    CHECK sy-subrc = 0.  " ← Simula INNER JOIN
    
    " ... resto del APPEND VALUE ty_detail existente ...
  ENDLOOP.
ENDMETHOD.
```

**Alternativa (documentar diferencia, no corregir):**
Si el negocio acepta que archive retorne facturas con NAME1 vacío (best-effort), documentar explícitamente:
```abap
"! <p class="shorttext synchronized">Hook: Complementa ct_detail desde Archiving SD_VBRK</p>
"! <p>⚠️ DIFERENCIA SEMÁNTICA: Online usa INNER JOIN con KNA1 (excluye si cliente no existe).
"! Archive usa lookup best-effort (incluye facturas con NAME1 vacío si cliente archivado/borrado).
"! Esta diferencia es INTENCIONAL para maximizar datos históricos recuperables.</p>
```

#### Prioridad
🟡 **MEDIA** - Decisión de negocio requerida (equivalencia exacta vs best-effort)

---

## ⚠️ Advertencias (No Críticas)

### ADVERTENCIA #1: Sin Validación de Pushdown de Filtros

#### Descripción
El código actual asume que todos los filtros enviados al motor de archiving se aplican correctamente. No hay validación programática de que los filtros fueron empujados exitosamente a la infoestructura.

#### Riesgo
Si algún campo (ej: un futuro cambio) pasa a ser solo-catálogo (no indexable), el filtro fallará silenciosamente y se traerán MÁS datos de los esperados.

#### Patrón Recomendado Según Guía
Sección "Patrón Correcto de 2 Pasos para Campos No Indexables":
```abap
METHOD append_detail_from_archive.
  " Paso 1: Lectura con filtros indexables
  lt_filters = build_archive_filters_vbrk( ).
  get_vbrk_vbrp_from_archive( EXPORTING it_filters = lt_filters
                              IMPORTING et_vbrk = lt_vbrk_arch
                                        et_vbrp = lt_vbrp_arch ).
  
  " 🔧 MEJORA: Paso 2: Post-filtro defensivo en memoria (safety net)
  " Solo para campos críticos que DEBEN filtrarse
  DELETE lt_vbrk_arch WHERE fksto = abap_true.  " ← Garantizar exclusión anuladas
  
  " Si gs_screen tiene filtros poblados, aplicarlos en memoria también
  IF gs_screen-s_vkorg IS NOT INITIAL.
    DELETE lt_vbrk_arch WHERE vkorg NOT IN gs_screen-s_vkorg.
  ENDIF.
  " ... (repetir para otros campos críticos) ...
ENDMETHOD.
```

**Beneficio:** Defensa en profundidad ante cambios en infoestructura de archiving

#### Prioridad
🔵 **BAJA** - Mejora recomendada, no urgente

---

## 🔄 Análisis de Consistencia BD + Archive

### Triple Gating: ✅ CORRECTO
Implementado en `get_data()` L188-191:
```abap
lv_use_archive = xsdbool(     gs_screen-p_hist = abap_true
                          AND lv_cutoff IS NOT INITIAL
                          AND needs_archive( iv_cutoff = lv_cutoff ) = abap_true ).
```

**Evaluación:** Cumple con patrón de guía (sección "Mecanismo de Triple Gating")

---

### Deduplicación BD + Archive: ✅ CORRECTO
Implementado en `append_detail_from_archive()` L819-832:
```abap
" 8. Preparar set de claves existentes para evitar duplicados
lt_existing_keys = ct_detail.

" 9. Recorrer VBRP de archivo y construir los detalles, evitando duplicados
LOOP AT lt_vbrp_arch ASSIGNING FIELD-SYMBOL(<ls_vbrp>).
  IF line_exists( lt_existing_keys[ vbeln = <ls_vbrp>-vbeln
                                    posnr = <ls_vbrp>-posnr ] ).
    CONTINUE.  " ← Evita duplicados
  ENDIF.
  " ... APPEND ...
  INSERT VALUE ty_detail( vbeln = ... posnr = ... ) INTO TABLE lt_existing_keys.
ENDLOOP.
```

**Evaluación:** Correcto, respeta semántica "BD wins, archive completa"

---

### Manejo de Excepciones: ✅ CORRECTO
Implementado en `append_detail_from_archive()` L788-798:
```abap
TRY.
    get_vbrk_vbrp_from_archive( EXPORTING it_filters = lt_filters
                                IMPORTING et_vbrk = lt_vbrk_arch
                                          et_vbrp = lt_vbrp_arch ).
  CATCH zcx_ca_archiving.
    RETURN.  " ← Best-effort: falla de archivo no aborta
ENDTRY.
```

**Evaluación:** Cumple con patrón de guía (sección "Patrón de Manejo de Excepciones")

---

## 📊 Tabla Consolidada de Hallazgos

| ID | Tipo | Severidad | Descripción | Líneas Afectadas | Prioridad |
|----|------|-----------|-------------|-----------------|-----------|
| **DEV-1** | ❌ Filtro Faltante | 🔴 CRÍTICA | FKSTO no se filtra en archive → trae facturas anuladas | L664-719, L764-881 | P0 |
| **DEV-2** | ❌ Semántica JOIN | 🟡 MEDIA | INNER JOIN KNA1 no se respeta → trae facturas sin cliente | L808-814, L840-848 | P1 |
| **ADV-1** | ⚠️ Robustez | 🔵 BAJA | Sin validación de pushdown exitoso de filtros | L764-881 | P2 |

---

## 🎯 Plan de Acción Recomendado

### Fase 1: Correcciones Críticas (Sprint Actual)
1. **DEV-1:** Implementar post-filtro FKSTO = abap_false en `append_detail_from_archive()`
   - Verificar indexabilidad en SARI
   - Si no indexable → DELETE en memoria (patrón 2 pasos)
   - Si indexable → agregar a `build_archive_filters_vbrk()`
   - **Esfuerzo:** 2-4 horas (incluyendo testing)

### Fase 2: Decisiones de Negocio (Próximo Sprint)
2. **DEV-2:** Definir estrategia para KNA1 INNER JOIN
   - Opción A: Simular INNER JOIN (equivalencia exacta)
   - Opción B: Documentar diferencia (best-effort)
   - **Esfuerzo:** 1 hora (decisión) + 2-4 horas (implementación si se elige Opción A)

### Fase 3: Mejoras de Robustez (Backlog)
3. **ADV-1:** Agregar post-filtros defensivos en memoria
   - **Esfuerzo:** 4-6 horas

---

## 📝 Testing Requerido Post-Corrección

### Caso de Prueba 1: Facturas Anuladas
```gherkin
DADO un período con facturas archivadas (algunas anuladas FKSTO='X')
CUANDO ejecuto reporte con p_hist = 'X'
ENTONCES:
  - Online: 0 facturas anuladas
  - Archive: 0 facturas anuladas  ← DEBE SER IGUAL
```

### Caso de Prueba 2: Clientes Inexistentes
```gherkin
DADO una factura archivada donde KUNAG ya no existe en KNA1
CUANDO ejecuto reporte con p_hist = 'X'
ENTONCES:
  - Online: 0 filas
  - Archive: [definir comportamiento esperado según decisión de negocio]
```

### Caso de Prueba 3: Merge BD + Archive
```gherkin
DADO facturas en ambos BD (2024) y archive (2022-2023)
CUANDO ejecuto reporte con FKDAT 01.01.2022-31.12.2024
ENTONCES:
  - Sin duplicados VBELN+POSNR
  - Facturas anuladas excluidas en ambas fuentes
  - Totales consistentes con ejecución solo-BD (para facturas BD)
```

---

## 📚 Referencias

1. **ARCHIVING_IMPLEMENTATION_GUIDE_ES.md**
   - Sección: "Mecanismo de Triple Gating" → L150-191
   - Sección: "INNER JOIN vs LEFT OUTER JOIN" → L350-450
   - Sección: "Patrón Correcto de 2 Pasos para Campos No Indexables" → L600-750

2. **Clase Auditada:** `ZCL_SD_ANEXOFACTURA_ARC`
   - WHERE online: L225-232
   - build_archive_filters_vbrk: L664-719
   - append_detail_from_archive: L764-881

3. **Transacción SARI:** Verificar campos indexables en SAP_SD_VBRK_001

---

## ✅ Conclusión Final

**La rama archive NO reproduce fielmente la lógica funcional del online debido a:**

1. ❌ **Omisión del filtro FKSTO** (facturas anuladas no se excluyen)
2. ❌ **Diferencia semántica en KNA1** (INNER JOIN vs lookup best-effort)

**Nivel de riesgo para producción:** 🔴 ALTO  
**Acción requerida:** Implementar correcciones críticas antes de release

**Firmado:**  
GitHub Copilot (Claude Sonnet 4.5)  
11 de marzo de 2026
