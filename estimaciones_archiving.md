# Resumen de estimaciones

| Transacción | Nombre | Objeto técnico | Total horas | Observaciones |
|---|---|---|---:|---|
| Z01_10297 | Diario de Facturación | ZCL_23_SALES_REPORT_CTRL2 | 0 | Ya estaba incluido en listado anterior y listo para pruebas |
| Z01_10287 | Reporte de Fyduca | Z_SD_REPORTE_FYDUCA | 74 | Requiere estrategia híbrida BD + Archive, ajuste de SELECT base, merge/dedupe y pruebas |
| Z01_10314 | Rep Movimientos de envases ligados | ZSD_REPORT_ENVASE_LIGADO | 90 | Principal impacto en bloqueo de histórico por INNER JOIN y coherencia entre familias |
| Z03_02200008 | Reporte de mensajes enviados | ZSD_SEND_SMS_CLIENTE_LOG | 69 | Requiere branch híbrido para VBAK/VBAP, ajuste de framework SD y mejoras de performance |
| Z03_02500014 | Validar pedidos cliente especial | ZSDT_CLI_PED_ESP | 0 | No requiere archiving; corresponde a mantenimiento de tabla Z |

**Total general estimado: 233 horas**

---

# Z01_10297
**Nombre:** Diario de Facturación  
**Objeto técnico:** `ZCL_23_SALES_REPORT_CTRL2`

| Actividad | Horas | Observaciones |
|---|---:|---|
| Validación de estado actual | 0 | Ya estaba incluido en el listado anterior y listo para pruebas |

**Total estimado: 0 horas**

---

# Z01_10287
**Nombre:** Reporte de Fyduca  
**Objeto técnico:** `Z_SD_REPORTE_FYDUCA`

| Actividad | Horas | Observaciones |
|---|---:|---|
| Análisis técnico detallado y diseño fino | 4 | Confirmar flujo real, criterio temporal, dependencias SD y bloqueos por INNER JOIN |
| Inventario técnico de tablas y accesos | 3 | Mapear VBAK, VBAP, VBKD, VBFA, VBRK, VBRP y accesos repetidos |
| Diseño de estrategia híbrida BD + Archive | 5 | Definir gating, familias, merge, dedupe y semántica TRY...CATCH |
| Refactor mínimo del SELECT base | 8 | Evitar dependencia total de INNER JOIN que bloquea histórico |
| Implementar `needs_archive( )` | 2 | Gating real sobre criterio temporal del reporte |
| Implementar builders de filtros archive | 4 | Validar campos indexables y post-filtro si aplica |
| Integración archive familia Facturación | 10 | Soporte VBRK/VBRP con merge y deduplicación |
| Integración archive familia Ventas | 10 | Soporte VBAK/VBKD y posible coherencia con VBAP/VBFA |
| Dedupe y merge BD + Archive | 4 | Control de duplicados por documento y posición |
| Ajustes mínimos de performance | 6 | Sacar SELECT SINGLE de loops y estabilizar FAE/lookups |
| Ajuste de semántica de errores | 3 | TRY...CATCH correcto sin alterar lógica funcional |
| Pruebas técnicas unitarias/integración básicas | 8 | Validar online, histórico, mezcla, fallback y no duplicación |
| Correcciones por hallazgos de prueba | 5 | Ajustes finos posteriores a pruebas |
| Documentación técnica corta | 2 | Documentar puntos tocados y operación |

**Total estimado: 74 horas**

---

# Z01_10314
**Nombre:** Rep Movimientos de envases ligados  
**Objeto técnico:** `ZSD_REPORT_ENVASE_LIGADO`

| Actividad | Horas | Observaciones |
|---|---:|---|
| Revisión técnica detallada y mapeo de accesos SD/LE | 5 | Revisar flujo principal, joins, auxiliares y criterio temporal real |
| Diseño técnico mínimo de solución híbrida BD + Archive | 6 | Definir enfoque sin reescribir programa completo |
| Implementación de gating temporal `needs_archive` | 3 | Respetando semántica del reporte |
| Ajuste del acceso base para evitar bloqueo de histórico por INNER JOIN | 12 | Punto más sensible del desarrollo |
| Integración archive familia ventas / flujo | 11 | Soporte VBAK + VBAP + VBFA con merge y dedupe |
| Integración archive familia entregas | 8 | Soporte LIKP + LIPS orientado a enrich |
| Integración archive familia facturación | 8 | Soporte VBRK + VBRP orientado a fill/lookups |
| Estabilización de tablas internas y deduplicación | 7 | Uso de HASHED/SORTED y claves funcionales |
| Ajustes mínimos de performance en loops y lookups | 6 | Sin rediseño grande |
| Manejo de errores archive con TRY/CATCH | 4 | Best-effort salvo necesidad comprobada |
| Pruebas unitarias/técnicas mínimas | 6 | Cobertura de gating, fallback, merge y errores |
| Pruebas manuales funcionales del reporte | 10 | Validación de saldos, cantidades y consistencia ALV |
| Ajustes finales, documentación breve y transporte | 4 | Cierre técnico |

**Total estimado: 90 horas**

---

# Z03_02200008
**Nombre:** Reporte de mensajes enviados  
**Objeto técnico:** `ZSD_SEND_SMS_CLIENTE_LOG`

| Actividad | Horas | Observaciones |
|---|---:|---|
| Análisis técnico detallado y diseño fino del branch híbrido | 4 | Enfocado en VBAK/VBAP y flujo actual |
| Validar infoestructura y campos indexables reales | 3 | Confirmar filtros viables para archive |
| Implementar `needs_archive( )` | 2 | Criterio temporal alineado a I_FECHA -> VBAK-ERDAT |
| Implementar `build_archive_filters_vbak( )` y `build_archive_filters_vbap( )` | 4 | Con revisión de indexables y post-filtro si aplica |
| Implementar método de familia `get_vbak_vbap_from_archive( )` | 6 | Lectura agrupada usando factory |
| Completar/ajustar capa SD del framework | 8 | Hacer usable gc_vbak/gc_vbap en ZCL_CA_ARCHIVING_DATA_SD |
| Integrar branch híbrido en GET_DATA_SEND | 6 | Sin romper lógica posterior |
| Merge online + archive con deduplicación | 3 | Claves VBELN y VBELN+POSNR |
| TRY/CATCH y semántica de corte segura | 2 | Manejo seguro de falla archive |
| Pruebas unitarias/técnicas mínimas | 6 | Gating, filtros y lectura archive |
| Pruebas integrales online e históricas | 6 | Validación completa de escenarios |
| Eliminar doble lectura de VBAP | 2 | Derivar lt_route desde una sola lectura |
| Reemplazar lookups repetidos por HASHED/SORTED | 4 | Optimización de tablas internas y lookups |
| Evitar borrado fila a fila de lt_vbak | 2 | Mejora puntual de performance |
| Preagrupar conteo de rutas por VBELN | 2 | Evita REDUCE repetido sobre lt_route |
| Deduplicar claves antes de FOR ALL ENTRIES | 2 | Reduce lecturas redundantes |
| Reemplazar SELECT * en tablas Z | 2 | Limitar a campos realmente usados |
| Poner límite al WHILE `gv_token IS INITIAL` | 1 | Evita riesgo de loop infinito |
| Revisar/parametrizar `WAIT UP TO 1 SECONDS` | 1 | Ajuste de estabilidad en envío |
| Pruebas de regresión funcional | 4 | Validar envío y reproceso |
| Documentación técnica corta | 2 | Diseño, cutoff, errores y checklist técnico |

**Total estimado: 69 horas**

---

# Z03_02500014
**Nombre:** Validar pedidos cliente especial  
**Objeto técnico:** `ZSDT_CLI_PED_ESP`

| Actividad | Horas | Observaciones |
|---|---:|---|
| Evaluación de aplicabilidad | 0 | No es un desarrollo; es mantenimiento de tabla Z y no requiere archiving |

**Total estimado: 0 horas**