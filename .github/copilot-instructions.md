Para desarrollos de archiving ABAP en este repositorio:

- usa `ARCHIVING_IMPLEMENTATION_GUIDE_ES.md` como guía normativa principal
- antes de continuar un desarrollo, busca una bitácora `ARCHIVING_<OBJETO>.md`
- si existe, léela primero
- si no existe, créala al iniciar el trabajo
- identifica el criterio temporal real desde el código
- distingue tablas core y auxiliares
- valida familia archive, objeto físico, infostructura e indexabilidad antes de proponer filtros
- usa cambios mínimos y por fases
- usa `append`, `enrich` y `fill` con la semántica correcta
- usa post-filtro en memoria cuando un campo requerido no sea indexable
- reporta primero hallazgos funcionales o riesgos de histórico antes que mejoras de estilo
- no inventes comportamiento no visible en el código
- no propongas rediseño grande salvo que se pida explícitamente
