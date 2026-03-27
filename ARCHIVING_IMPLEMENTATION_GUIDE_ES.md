# Guía de Implementación de Archiving en ABAP

**Versión:** 3.1  
**Última actualización:** 24 de marzo de 2026  
**Basada en implementaciones reales:**
- `ZCL_MM_FLETFACT_SERVICE`
- `ZCL_SD_ANEXOFACTURA_ARC`
- `ZCL_PM_FACTORDENSERVICIO_ARC`
- `ZCL_CA_ARCHIVING_FACTORY`

---

## 1. Propósito y Alcance

Esta guía define un patrón reusable para incorporar soporte de archiving en soluciones ABAP existentes sin reescribir la lógica funcional completa.

Su objetivo es resolver cuatro problemas a la vez:
- acceso a histórico archivado
- mantenimiento del comportamiento funcional actual
- claridad arquitectónica
- control de performance y testing

### Qué cubre
- migración desde SAP Query/Infoset a programa ABAP + clase de servicio
- adaptación de reportes/clases existentes para lectura híbrida `BD + Archive`
- patrones de familia para SD/LE
- gating temporal
- filtros por infostructura y post-filtro en memoria
- uso correcto de `ZCL_CA_ARCHIVING_FACTORY`

### Qué no cubre
- configuración de SARA/SARI
- creación de objetos de archiving custom
- políticas de retención
- tuning de procesos batch de archivado

---

## 2. Principios No Negociables

1. No inventar comportamiento que no exista en el código original.
2. Identificar primero el criterio temporal real del objeto.
3. Identificar primero las tablas ancla online.
4. Distinguir tablas core del documento vs tablas auxiliares.
5. Validar en sistema la infostructura y los campos indexables antes de diseñar filtros archive.
6. Usar `TRY/CATCH` y semántica best-effort salvo que el resultado quede inválido por definición.
7. No hacer refactor grande salvo que sea imprescindible para soportar archiving.

---

## 3. Cuándo Migrar desde SAP Query

La razón principal para migrar desde SAP Query no es simplemente el uso de joins. El problema real es de arquitectura.

### SAP Query deja de ser suficiente cuando se necesita:
- gating temporal controlado
- lectura condicional de archive
- lectura coherente por familia documental
- post-filtros en memoria sobre datos archivados
- semántica clara de mezcla `BD + Archive`
- testabilidad y trazabilidad técnica

### Aclaración importante sobre joins
Resolver un acceso con joins no resuelve por sí mismo:
- cuándo consultar archive
- cómo leer una familia archivada de forma coherente
- cómo completar datos faltantes sin duplicar
- cómo mantener la lógica bajo pruebas

Por eso, cuando el requerimiento es histórico real y mantenible, conviene migrar a programa ABAP + clase.

### Patrón de migración en 3 capas
Al migrar desde SAP Query, estructurar la clase de servicio en tres capas internas:

1. **Capa 1 — Lectura core:** SELECT de las tablas ancla (ej. VBRK+VBRP) con filtros de pantalla, sin joins a maestros ni agregaciones SQL. Este es el punto exacto de inserción del `append_*_from_archive()` en la fase de archiving.
2. **Capa 2 — Prefetch de master data:** Carga separada de tablas auxiliares (textos, conversiones, tablas Z) acotada a las claves del resultado base. Tablas HASHED para lookup O(1).
3. **Capa 3 — Cálculo y agregación:** Toda la lógica funcional (signos, zeroing, conversiones, clasificaciones) se ejecuta en ABAP sobre las filas base ya enriquecidas.

Esta separación tiene una consecuencia directa: al agregar archiving, solo se toca la Capa 1. Las capas 2 y 3 procesan filas BD y archive de forma transparente, sin cambios.

---

## 4. Punto de Partida Obligatorio: Análisis del Objeto

Antes de diseñar archiving, siempre responder estas preguntas:

### 4.1 Qué tablas anclan el flujo online actual
Ejemplos:
- facturación: `VBRK`, `VBRP`
- ventas: `VBAK`, `VBAP`, `VBKD`
- entregas: `LIKP`, `LIPS`
- transporte: `VTTK`, `VTTP`
- viajes/custom: tablas Z que luego enriquecen con SD

### 4.2 Cuál es el criterio temporal real
No asumir `pperiodo`.

Ejemplos reales:
- `ZCL_MM_FLETFACT_SERVICE`: `pperiodo` convertido a rango de `/SCMTMS/DATETIME`
- `ZCL_SD_ANEXOFACTURA_ARC`: `VBRK-FKDAT`
- `ZCL_PM_FACTORDENSERVICIO_ARC`: `VBRK-FKDAT`

### 4.3 Qué bloquea el histórico hoy
- `INNER JOIN` contra tablas archivables
- dependencia obligatoria de tablas online para construir la fila principal
- filtro temporal aplicado solo en la parte online

### 4.4 Si el objeto es candidato a híbrido `BD + Archive`
La respuesta suele ser sí cuando:
- el reporte ya tiene una base online útil
- el histórico falta porque una o más tablas core fueron archivadas
- la lógica de cálculo posterior puede mantenerse si se completa el dataset base

---

## 5. Regla Central: Tabla Core vs Tabla Auxiliar

Esta es la decisión más importante de la guía.

### 5.1 Tabla o familia core
Una tabla es core cuando define el universo funcional del reporte.

Ejemplos:
- `VBRK + VBRP` en reportes de facturación
- `VBAK + VBAP` en reportes de pedidos
- `LIKP + LIPS` en reportes de entregas

### 5.2 Tabla auxiliar o de enriquecimiento
Una tabla es auxiliar cuando la fila principal existe sin ella y solo aporta campos adicionales.

Ejemplos:
- `VBAP` en `ZCL_MM_FLETFACT_SERVICE`, donde el core nace en tablas Z de viaje
- maestros, textos, tablas Z complementarias, HR, PM, pricing auxiliar según el caso

### 5.3 Regla de decisión
- Si la tabla archivada es **core**, resolverla con lectura coherente por familia o con el patrón archive que preserve el universo funcional.
- Si la tabla archivada es **auxiliar**, puede resolverse con un patrón de enriquecimiento sobre la fila base existente.

---

## 6. Selección del Patrón de Acceso

### 6.1 Cuándo usar un patrón de enriquecimiento
Usarlo solo si se cumplen todas estas condiciones:
- la tabla de la izquierda sigue siendo el verdadero ancla funcional
- la fila base existe sin la tabla archivada
- la tabla archivada solo completa campos
- si la tabla archivada falta online, la fila debe seguir viva

En este escenario, una variante válida puede ser `LEFT OUTER JOIN + enrich`.

### 6.2 Cuándo usar lectura por familia
Usar lectura por familia como solución principal cuando:
- la tabla archivada pertenece al core documental
- el reporte necesita reconstruir la familia completa
- el filtro temporal y funcional depende de esa familia
- el objetivo real es recuperar filas faltantes, no solo completar columnas

### 6.3 Casos reales

#### Caso válido de patrón de enriquecimiento
`ZCL_MM_FLETFACT_SERVICE`
- core: `ZTMT_SERFLETR01`, `ZTMT_SERFLETR02`, `ZSDT_PARAMADIC`, `BUT000`
- `VBAP` entra como enriquecimiento
- patrón correcto: join tolerante + `enrich_vbap_from_archive()`

#### Casos donde no aplica
`ZCL_SD_ANEXOFACTURA_ARC`
- core: `VBRK + VBRP`
- patrón correcto: leer BD, luego `append_detail_from_archive()` con familia `SD_VBRK`

`ZCL_PM_FACTORDENSERVICIO_ARC`
- core: `VBRK + VBRP`
- patrón correcto: leer BD, luego `enrich_vbrk_from_archive()` y `enrich_vbrp_from_archive()` usando la misma familia

---

## 7. Patrones Reusables de Integración con Archive

### 7.1 `append_*_from_archive`
Agregar filas faltantes.

Usar cuando:
- faltan documentos completos porque fueron archivados
- el resultado online no contiene esas filas

Ejemplo:
- `append_detail_from_archive` en `ZCL_SD_ANEXOFACTURA_ARC`

### 7.2 `enrich_*_from_archive`
Completar campos faltantes sobre filas ya existentes.

Usar cuando:
- el registro base existe en BD
- una tabla archivada solo aporta columnas adicionales

Ejemplo:
- `enrich_vbap_from_archive` en `ZCL_MM_FLETFACT_SERVICE`

### 7.3 `fill_*_from_archive`
Completar lookups, caches o estructuras auxiliares.

Usar cuando:
- el consumo real es indirecto
- se necesita poblar mapas internos o pricing lookups

Ejemplo típico:
- pricing histórico desde `KONV`

### 7.4 `family read`
Lectura coherente de varias tablas relacionadas del mismo flujo archivado.

Usar cuando:
- más de una tabla del mismo documento debe venir del mismo objeto archive
- la coherencia documental es más importante que leer tablas sueltas

Ejemplos:
- `get_vbrk_vbrp_from_archive_*`
- `get_vbak_vbkd_from_archive_*`
- `get_likp_lips_from_archive_*`
- `get_vttk_vttp_from_archive_*`

---

## 8. Familias de Archiving

Agrupar lecturas relacionadas evita mezclar fuentes arbitrariamente.

### 8.1 Facturación
- familia lógica: `VBRK + VBRP`
- pricing relacionado: `KONV`
- objeto físico típico: `SD_VBRK`
- infostructura típica de facturación: validar en sistema, por ejemplo `SAP_SD_VBRK_001`

### 8.2 Ventas
- familia lógica: `VBAK + VBKD + VBAP`
- pricing relacionado: `KONV`
- objeto físico típico: `SD_VBAK`
- infostructura: validar en sistema, por ejemplo `SAP_DRB_VBAK_01` o `SAP_DRB_VBAK_02`

### 8.3 Entregas
- familia lógica: `LIKP + LIPS`
- objeto físico: validar en factory

### 8.4 Transporte
- familia lógica: `VTTK + VTTP`
- objeto físico típico: `SD_VTTK`

### Regla
No inventar familias ni objetos. Confirmar siempre en:
- SARI
- factory
- implementaciones validadas del sistema

---

## 9. Modelo del Factory: Constante Lógica vs Objeto Físico

`ZCL_CA_ARCHIVING_FACTORY` puede exponer constantes lógicas distintas que internamente resuelven al mismo objeto físico archive.

### Ejemplos reales
- `gc_vbrk` → objeto físico `SD_VBRK`, tabla `VBRK`
- `gc_vbrp` → mismo objeto físico `SD_VBRK`, tabla `VBRP`
- `gc_vbrk_konv` → mismo objeto físico `SD_VBRK`, tabla `KONV`
- `gc_vbak` → objeto físico `SD_VBAK`, tabla `VBAK`
- `gc_vbap` → mismo objeto físico `SD_VBAK`, tabla `VBAP`
- `gc_vbak_konv` → mismo objeto físico `SD_VBAK`, tabla `KONV`

### Consecuencia práctica
Lectura coherente por familia no significa necesariamente “una sola llamada”.
Puede haber varias llamadas lógicas al factory si:
- usan la misma familia física
- comparten offsets coherentes
- no mezclan universos documentales incompatibles

---

## 10. Gating Temporal

La decisión de consultar archive debe derivarse del criterio temporal real del objeto.

### Regla
No forzar `pperiodo` si el código usa otro campo.

### Ejemplos
- si el objeto usa `FKDAT`, `needs_archive()` debe evaluar `FKDAT`
- si el objeto usa un período que luego se transforma a fechas/timestamps, evaluar el rango resultante

### Triple gate
Usar cuando aplique técnicamente:
- flag usuario histórico (`p_hist`)
- cutoff válido
- `needs_archive(...) = abap_true`

### Buenas prácticas para `needs_archive()`
- procesar todas las líneas relevantes del rango
- considerar solo inclusiones
- manejar explícitamente `EQ`, `BT`, `GE`, `GT`, `LE`, `LT`
- si no puede determinarse el mínimo de forma segura, usar una decisión conservadora documentada

### Operadores y comparación correcta con cutoff
- `EQ`, `GE`: activar archive si `low <= cutoff`
- `GT`: activar archive si `low < cutoff` (no `<=`, porque el rango empieza estrictamente después de `low`)
- `BT`: activar archive si `low <= cutoff`
- `LE`, `LT`: activar archive incondicionalmente (el rango siempre puede cubrir fechas archivadas)

---

## 11. Filtros de Archive: Indexables Primero

### Regla principal
Solo construir offsets con campos indexables confirmados en la infostructura.

### Nunca hacer
- asumir que un campo es indexable porque existe en la tabla SAP
- filtrar archive directamente por `KNUMV`, `KPOSN`, `KSCHL` u otros campos no confirmados

### Si un campo no es indexable
Aplicar este patrón:
1. generar offsets con los campos indexables
2. leer los registros archive
3. post-filtrar en memoria

### Casos reales

#### Facturación
En implementaciones sobre `SD_VBRK`, se validó que filtros como `VBELN`, `FKDAT`, `KUNRG` sí pueden servir para offsets, mientras otros como `BUKRS`, `ZUONR`, `XBLNR` deben post-filtrarse según el caso.

#### Pricing
Para `KONV`, el filtro efectivo suele anclarse en el documento principal y luego aplicar filtro en memoria por `KNUMV`, `KPOSN`, `KSCHL`.

---

## 12. Post-Filtro en Memoria

El post-filtro en memoria no es un parche; es parte normal del diseño cuando la infostructura no soporta todos los criterios.

### Usarlo para:
- campos no indexables
- exclusiones funcionales
- coherencia documental posterior
- anulación de documentos

### Zeroing vs exclusión
Al migrar lógica SQL a post-filtro en memoria, distinguir:
- **Exclusión:** la fila completa se descarta (ej. `VBTYP NOT IN ('N','S')`, `FKIMG > 0`). Implementar como `DELETE WHERE` o `CONTINUE`.
- **Zeroing:** la fila permanece, pero uno o más campos se ponen a 0 (ej. `CASE WHEN VF_STATUS = 'C' THEN 0 ELSE valor`). Implementar como flag + asignación condicional.

No confundir ambos: si el query original usa `CASE WHEN ... THEN 0`, la fila sigue existiendo en el GROUP BY y afecta la agrupación. Convertirla en exclusión cambia la semántica del reporte.

### Casos reales
- `FKSTO`, `VTWEG`, `SPART`, `KUNAG` en `ZCL_SD_ANEXOFACTURA_ARC`
- `BUKRS`, `ZUONR`, `XBLNR`, `SFAKN` en `ZCL_PM_FACTORDENSERVICIO_ARC`

---

## 13. Semántica de Error

### Best-effort
Usar por defecto cuando el reporte puede seguir siendo válido con la parte BD.

Patrón:
- `TRY/CATCH`
- `RETURN` local
- no abortar el reporte completo

### Hard fail
Usar solo si:
- el usuario exige completitud estricta
- sin archive no existe resultado válido

### Regla práctica
Si el resultado BD sigue siendo funcional aunque incompleto históricamente, archive debe ser best-effort.

---

## 14. Performance: Solo Estabilizaciones Seguras

El soporte de archiving no justifica una reescritura total.

Aplicar solo mejoras pequeñas y seguras:
- proteger cada `FOR ALL ENTRIES` con `itab IS NOT INITIAL`
- deduplicar claves antes de `FOR ALL ENTRIES`
- reemplazar búsquedas repetidas con tablas `HASHED` o `SORTED`
- evitar `SELECT SINGLE` dentro de loops
- evitar `SELECT` dentro de loops
- evitar borrar sobre la misma itab mientras se la recorre si existe alternativa segura

### Ejemplo válido
`ZCL_MM_FLETFACT_SERVICE` usa prefetch + hashed lookup para pricing y para completar desde archive.

---

## 15. Testing

La validación debe hacerse en tres niveles.

### 15.1 Lógica determinística
Testear:
- `needs_archive()`
- construcción de rangos
- mapeos determinísticos
- post-filtros en memoria

### 15.2 Lectura técnica de archive
Programas `Z_TEST_*` para validar:
- generación de offsets
- lectura de tablas esperadas
- comportamiento con 0 resultados
- deduplicación

### 15.3 Smoke test funcional
Comparar:
- período 100% BD
- período 100% archive
- período mixto
- caso con documentos anulados
- caso con pricing histórico si aplica

---

## 16. Fases Recomendadas de Implementación

### Fase 1: Análisis
- identificar flujo actual
- identificar criterio temporal real
- identificar tablas core y auxiliares
- identificar bloqueos de histórico

### Fase 2: Limpieza mínima pre-archiving
- consolidar accesos duplicados si reducen complejidad
- corregir reglas de exclusión clave
- tipificar estructuras si el método archive lo requiere

### Fase 3: Infraestructura archive
- agregar `p_hist` si aplica
- agregar `needs_archive()`
- agregar gating
- crear métodos `build_archive_filters_*`
- crear métodos `get_*_from_archive`

### Fase 4: Integración híbrida
- mantener BD como fuente primaria
- incorporar archive por familia
- hacer append/enrich/fill según corresponda
- aplicar post-filtro en memoria

### Fase 5: Estabilización
- deduplicación BD vs archive
- deduplicación interna del payload archive (ver nota abajo)
- guards de `FOR ALL ENTRIES`
- lookups hashed/sorted
- comentarios y ABAPDoc

#### Deduplicación en dos niveles
Al hacer `append` de filas archive a un resultado BD, la tabla de claves conocidas debe actualizarse con cada fila archive insertada. Si solo se inicializa con las claves BD, duplicados internos del propio payload archive no se detectan.

Patrón correcto:
1. Inicializar tabla sorted de claves con las filas BD.
2. En el LOOP archive: verificar contra la tabla → si no existe, APPEND + INSERT clave.
3. No usar una tabla de claves estática que solo contenga BD.

### Fase 6: Testing y documentación
- test técnico
- smoke test funcional
- bitácora de decisiones
- ABAPDoc alineado con la implementación

---

## 17. Reglas de Decisión Reusables

### Regla 1
Si la tabla archivada define el universo funcional del reporte, tratarla como core y leerla por familia.

### Regla 2
Si la tabla archivada solo completa columnas y la fila base existe sin ella, considerar un patrón de enriquecimiento.

### Regla 3
El criterio temporal de `needs_archive()` debe reflejar el filtro real del objeto, no un patrón genérico.

### Regla 4
No diseñar filtros archive sin validar indexabilidad real.

### Regla 5
Si varias tablas pertenecen al mismo flujo archivado, agruparlas por familia.

### Regla 6
`append`, `enrich` y `fill` no son sinónimos; usar el verbo correcto según la semántica.

### Regla 7
Si archive falla y BD sigue siendo útil, usar best-effort.

### Regla 8
Si una optimización no cambia el soporte de archiving ni corrige un problema visible, no hacerla en esta fase.

---

## 18. Casos de Referencia

### 18.1 `ZCL_MM_FLETFACT_SERVICE`
Patrón principal:
- core en tablas Z
- `VBAP` como enriquecimiento opcional
- join tolerante + `enrich_vbap_from_archive()`
- criterio temporal: `pperiodo`

### 18.2 `ZCL_SD_ANEXOFACTURA_ARC`
Patrón principal:
- core de facturación `VBRK + VBRP`
- append de detalle desde `SD_VBRK`
- familia adicional de ventas `VBAK + VBKD`
- criterio temporal: `FKDAT`

### 18.3 `ZCL_PM_FACTORDENSERVICIO_ARC`
Patrón principal:
- core de facturación `VBRK + VBRP`
- enrich de cabecera y posiciones desde archive
- pricing `KONV` vía misma familia física `SD_VBRK`
- criterio temporal: `FKDAT`

### 18.4 `ZCL_SD_ESTVNT_ARC`
Patrón principal:
- migración desde SAP Query (Infoset) a programa ABAP + clase de servicio
- arquitectura en 3 capas: lectura core VBRK+VBRP / prefetch maestros / cálculo+agregación
- core de facturación `VBRK + VBRP`, familia `SD_VBRK`
- append de documentos archivados en Capa 1; capas 2 y 3 sin cambios
- criterio temporal: `FKDAT`
- deduplicación en dos niveles (BD + interna archive)
- zeroing diferenciado: cantidades zero por VF_STATUS+ECF, valores zero solo por VF_STATUS

---

## 19. Checklist Operativo

Antes de implementar:
- ya identifiqué tablas core
- ya identifiqué criterio temporal real
- ya validé family/object en factory
- ya validé infostructura y campos indexables

Antes de activar:
- `needs_archive()` probado
- gating funcionando
- semántica `append/enrich/fill` correcta
- `TRY/CATCH` correcto
- sin `SELECT` dentro de loop en la parte nueva

Antes de transportar:
- bitácora actualizada
- ABAPDoc alineado
- smoke test BD/archive ejecutado

---

## 20. Resumen Ejecutivo

La guía no debe enseñar un único patrón de acceso como regla general.

La regla correcta es:
- **familia core** → lectura coherente por familia archive
- **tabla auxiliar** → patrón de enriquecimiento solo si la fila base sigue siendo válida

Ese es el patrón que mejor mantiene:
- corrección funcional
- mantenibilidad
- escalabilidad
- consistencia entre BD y Archive

---

## 21. Anexo Técnico A: Tipos Explícitos vs Genéricos

Este anexo sí es importante porque afecta directamente la implementación ABAP de métodos archive.

### Problema
Firmas genéricas como `TYPE STANDARD TABLE` o `TYPE ANY TABLE` vuelven frágil el contrato del método y complican:
- acceso a componentes
- validación en compilación
- mantenimiento del código
- lectura del flujo archive

### Cuándo sí exigir tipos explícitos
- cuando el método necesita acceder a campos concretos como `VBELN`, `KNUMV`, `FKDAT`, `MATNR`
- cuando el método modifica una tabla interna estructurada del pipeline
- cuando el método pertenece al flujo archive principal

### Recomendación
Definir tipos internos en `PRIVATE SECTION` y usarlos en firmas de métodos como:
- `tt_interna1`
- `tt_interna2`
- `tt_detail`
- tipos hash para lookups

### Cuándo tolerar tipos más genéricos
- en wrappers técnicos muy pequeños
- cuando el método solo reenvía datos al factory sin lógica adicional
- cuando el costo de tipificar no compensa y no se accede a campos

### Regla práctica
Si el método archive hace más que transportar parámetros, tipificarlo explícitamente.

---

## 22. Anexo Técnico B: Funcionamiento Real del Factory

### Modelo mental correcto
El factory no necesariamente tiene relación 1:1 entre:
- constante pública
- objeto físico archive
- tabla interna extraída

### Flujo real
1. el consumidor llama `get_instance( iv_object = gc_* )`
2. el factory resuelve el objeto físico
3. se generan offsets con la infostructura correspondiente
4. se llama `get_table_data( iv_reftab = ... )`
5. el factory llena la tabla global tipada
6. `get_data()` entrega esa tabla al consumidor

### Ejemplos reales
- `gc_vbrk` -> `SD_VBRK` -> `VBRK`
- `gc_vbrp` -> `SD_VBRK` -> `VBRP`
- `gc_vbrk_konv` -> `SD_VBRK` -> `KONV`
- `gc_vbak` -> `SD_VBAK` -> `VBAK`
- `gc_vbap` -> `SD_VBAK` -> `VBAP`
- `gc_vbak_konv` -> `SD_VBAK` -> `KONV`

### Consecuencia importante
Dos llamadas lógicas distintas pueden seguir siendo correctas si mantienen coherencia con la misma familia física.

### Qué documentar siempre
- constante usada por el consumidor
- objeto físico real
- tabla `iv_reftab`
- infostructura usada para offsets

---

## 23. Anexo Técnico C: Limitaciones Conocidas

### 23.1 `VBFA`
No asumir que `VBFA` está disponible desde cualquier familia.

Validar siempre:
- objeto físico real
- tabla disponible en el objeto
- si el factory del sistema ya soporta ese caso

Si no está disponible en la familia esperada:
- no inventar el acceso
- rediseñar el consumo como caso específico

### 23.2 `KONV`
`KONV` casi nunca debe filtrarse por sus propios campos como offset primario.

Patrón correcto:
1. usar el documento ancla para generar offsets
2. leer `KONV` desde la familia física correspondiente
3. filtrar en memoria por `KNUMV`, `KPOSN`, `KSCHL` u otros campos requeridos

### 23.3 Post-filtros obligatorios
Cuando un criterio no es indexable, no intentar forzarlo al archive query.
Aplicarlo en memoria y documentar la decisión.

---

## 24. Anexo Técnico D: Plantillas ABAPDoc

### 24.1 `needs_archive`

```abap
"! Determinar si es necesario leer desde archiving
"! Usa el criterio temporal real del objeto, no un patrón genérico.
"! @parameter iv_cutoff | Fecha de corte de datos online
"! @parameter ir_fecha  | Rango temporal real del objeto
"! @parameter rv_needs  | abap_true si requiere archive
```

### 24.2 `build_archive_filters_*`

```abap
"! Construir filtros para lectura archive
"! Usa solo campos indexables confirmados en la infostructura.
"! Los campos no indexables deben post-filtrarse en memoria.
"! @parameter ir_docno   | Rango de documento
"! @parameter ir_fecha   | Rango de fecha
"! @parameter rt_filters | Filtros para ZCL_CA_ARCHIVING_FACTORY
```

### 24.3 `get_*_from_archive`

```abap
"! Leer datos desde archiving
"! Mantiene semántica best-effort salvo indicación contraria.
"! @parameter it_filters | Filtros ya construidos
"! @parameter et_data    | Datos retornados desde archive
"! @raising zcx_ca_archiving | Error técnico de lectura
```

### 24.4 `append/enrich/fill`

```abap
"! Append desde archive
"! Agrega filas faltantes sin sobrescribir datos ya obtenidos desde BD.

"! Enrich desde archive
"! Completa campos faltantes sobre filas existentes.

"! Fill desde archive
"! Completa estructuras auxiliares o lookups internos.
```

### Regla
ABAPDoc debe describir:
- semántica del método
- criterio temporal si aplica
- familia u objeto archive
- qué se filtra por index
- qué se filtra en memoria

---

## 25. Anexo Técnico E: Patrón de Testing

### 25.1 Métodos determinísticos
Los mejores candidatos para pruebas unitarias o semi-unitarias son:
- `needs_archive()`
- `build_*_range`
- post-filtros en memoria
- mapeos reversos
- deduplicación

### 25.2 Programas `Z_TEST_*`
Usarlos para validar técnicamente:
- generación de offsets
- lectura por familia
- lectura de tablas concretas
- casos con 0 resultados
- mezcla BD + Archive

### 25.3 Casos mínimos de smoke test
- período 100% BD
- período 100% archive
- período mixto
- caso con anulaciones
- caso con pricing histórico si aplica

### Regla práctica
No avanzar al reporte consumidor si la clase `_ARC` no pasó antes por un test técnico de archive.

---

## 26. Anexo Técnico F: Checklist de Migración

### Fase 1
- identifiqué el flujo online
- identifiqué el criterio temporal real
- identifiqué tablas core y auxiliares

### Fase 2
- validé objeto físico archive
- validé factory
- validé infostructura
- validé campos indexables

### Fase 3
- implementé gating
- implementé `needs_archive()`
- implementé `build_archive_filters_*`
- implementé lectura por familia o hook mínimo

### Fase 4
- integré archive sin cambiar la lógica funcional principal
- apliqué post-filtros en memoria
- verifiqué deduplicación

### Fase 5
- documenté bitácora
- alineé comentarios/ABAPDoc
- ejecuté pruebas técnicas y smoke tests

---

## 27. Anexo Técnico G: Errores Comunes

### Error 1
Tratar toda tabla archivada con el mismo patrón de acceso.

Corrección:
- primero decidir si es core o auxiliar

### Error 2
Diseñar `needs_archive()` sobre `pperiodo` cuando el objeto filtra por otra fecha.

Corrección:
- usar el criterio temporal real

### Error 3
Construir filtros con campos no indexables.

Corrección:
- offsets por indexables
- post-filtro en memoria

### Error 4
Mezclar fuentes BD y Archive sin respetar la familia documental.

Corrección:
- agrupar por familia
- documentar objeto físico e infostructura

### Error 5
Leer archive sin `TRY/CATCH`.

Corrección:
- encapsular lectura archive y usar semántica de error explícita

### Error 6
Resolver problemas de archiving con refactor grande innecesario.

Corrección:
- aplicar solo cambios mínimos que afecten soporte histórico

### Error 7
Cerrar un hallazgo en bitácora sin reflejarlo realmente en el código.

Corrección:
- verificar siempre código, comentarios y documentación
