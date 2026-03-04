"! <p class="shorttext synchronized">Interfaz principal del procesador de auditoría de BP</p>
"! Orquesta el flujo completo de validación: lectura de datos, validación, aplicación de cambios y logging.
"! Genera resúmenes para ALV y detalle de issues por BP.
INTERFACE zif_bp_processor
  PUBLIC.

  " Estructura de criterios de selección del reporte
  TYPES: BEGIN OF ty_sel,
           partner_range TYPE RANGE OF bu_partner, " Rango de partners a procesar
           is_simulation TYPE abap_bool,           " abap_true: solo validar, no actualizar
           only_errors   TYPE abap_bool,           " abap_true: filtrar solo BPs con errores
         END OF ty_sel.

  " Estructura de resumen de BP para visualización en ALV
  TYPES: BEGIN OF ty_alv,
           partner  TYPE bu_partner, " Business Partner ID
           bp_type  TYPE c LENGTH 3, " PER=Persona, ORG=Organización
           status   TYPE c LENGTH 1, " G=Green, Y=Yellow, R=Red
           errors   TYPE i,          " Cantidad de errores tipo E
           warnings TYPE i,          " Cantidad de warnings tipo W
         END OF ty_alv.


  TYPES tt_alv   TYPE STANDARD TABLE OF ty_alv WITH EMPTY KEY.
  TYPES tt_issue TYPE STANDARD TABLE OF zif_bp_validator=>ty_issue WITH EMPTY KEY.

  "! <p class="shorttext synchronized">Procesa y valida BP según criterios de selección</p>
  "! Ejecuta lectura → validación → aplicación de cambios (si no es simulación) → logging.
  "! Genera resumen consolidado (rt_alv) y detalle de issues (rt_issues).
  "!
  "! @parameter is_sel    | Criterios de selección (rango BPs, modo simulación, filtro errores)
  "! @parameter rt_alv    | Resumen por BP: status, cantidad de errores/warnings
  "! @parameter rt_issues | Detalle de issues validados: campo, valor actual/propuesto, severidad E/W
  METHODS process
    IMPORTING is_sel    TYPE ty_sel
    EXPORTING rt_alv    TYPE tt_alv
              rt_issues TYPE tt_issue.

ENDINTERFACE.
