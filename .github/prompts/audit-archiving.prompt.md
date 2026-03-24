---
agent: ask
description: Audita una implementación de archiving ABAP
---

Usa `ARCHIVING_IMPLEMENTATION_GUIDE_ES.md` como norma principal.

Lee:
- la clase o programa a auditar
- la bitácora `ARCHIVING_<OBJETO>.md`
- el consumidor si aplica
- `ZCL_CA_ARCHIVING_FACTORY` si aplica

Valida:
- criterio temporal real
- gating y `needs_archive()`
- tablas core vs auxiliares
- familia archive
- objeto físico, infostructura e indexabilidad
- post-filtro en memoria
- append/enrich/fill
- `TRY/CATCH` y semántica best-effort
- coherencia entre código y bitácora

Entrega:
- hallazgos por severidad
- evidencia con archivo y línea
- impacto
- corrección mínima sugerida
- conclusión final: listo / parcial / no listo
