"! <p class="shorttext synchronized">Interfaz para registro de auditoría de Business Partners</p>
"! Gestiona el ciclo completo de auditoría: inicio, registro de resultados y finalización.
"! Permite rastrear cambios aplicados a BPs y su resultado (éxito/error/warning).
INTERFACE zif_bp_audit_logger
  PUBLIC.

  TYPES: BEGIN OF ty_log_summary,
           total_bp       TYPE i,
           total_errors   TYPE i,
           total_success  TYPE i,
           total_warnings TYPE i,
         END OF ty_log_summary.

  "! <p class="shorttext synchronized">Inicia un nuevo log de auditoría</p>
  "! Crea registro header con criterios de selección y timestamp inicial.
  "!
  "! @parameter is_sel | Criterios de selección del reporte (rango partners, modo simulación)
  "! @parameter rv_log_id | ID único del log (UUID) para referencias posteriores
  METHODS start_log
    IMPORTING
      is_sel           TYPE zif_bp_processor=>ty_sel
    RETURNING
      VALUE(rv_log_id) TYPE sysuuid_x16.

  "! <p class="shorttext synchronized">Registra resultados de actualización de BPs</p>
  "! Almacena detalle de cada campo actualizado: partner, campo, resultado (S/E/W), valores old/new.
  "! Se ejecuta solo cuando is_simulation = abap_false.
  "!
  "! @parameter iv_log_id | ID del log activo (generado por start_log)
  "! @parameter it_update_results | Tabla con resultados de actualizaciones por campo
  METHODS log_bp_results
    IMPORTING
      iv_log_id         TYPE sysuuid_x16
      it_update_results TYPE zif_bp_persistence=>tt_update_result.

  "! <p class="shorttext synchronized">Finaliza el log con resumen consolidado</p>
  "! Actualiza header con totales: BPs procesados, éxitos, errores, warnings y timestamp final.
  "! Marca el log como completo.
  "!
  "! @parameter iv_log_id | ID del log a finalizar
  "! @parameter is_summary | Estructura con contadores finales (total_bp, total_errors, etc.)
  METHODS finalize_log
    IMPORTING
      iv_log_id  TYPE sysuuid_x16
      is_summary TYPE ty_log_summary.

ENDINTERFACE.
