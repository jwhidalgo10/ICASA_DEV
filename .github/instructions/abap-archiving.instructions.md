---
applyTo: "**/*.abap,**/*.txt,**/ARCHIVING_*.md"
---

Para tareas de archiving ABAP:

- usa `ARCHIVING_IMPLEMENTATION_GUIDE_ES.md` como guía normativa principal
- si existe una bitácora `ARCHIVING_<OBJETO>.md`, úsala como contexto vivo del desarrollo
- si no existe, créala
- identifica el criterio temporal real del objeto
- identifica tablas core y auxiliares
- si las tablas archivadas son core del flujo, prefiere lectura coherente por familia
- si una tabla archivada es auxiliar, usa patrón de enriquecimiento solo si la fila base sigue siendo válida
- valida objeto físico, familia e infostructura en `ZCL_CA_ARCHIVING_FACTORY` o en la implementación real del sistema antes de asumir el diseño
- valida campos indexables antes de construir filtros
- usa offsets por indexables y post-filtro en memoria cuando sea necesario
- usa `TRY/CATCH` con semántica best-effort salvo que el resultado quede inválido por definición
- no propongas refactor grande si no afecta el soporte de archiving
