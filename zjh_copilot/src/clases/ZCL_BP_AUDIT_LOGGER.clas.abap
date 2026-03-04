"! <p class="shorttext synchronized">Logger de auditoría de Business Partners</p>
"! Registra en tablas zbp_audit_hdr/zbp_audit_itm el proceso completo de validación/actualización.
"! Genera log con UUID único, guarda cabecera (fecha/usuario/modo), detalle por campo actualizado y resumen final.
"! Maneja errores de escritura sin interrumpir el proceso principal (modo fail-safe).
CLASS zcl_bp_audit_logger DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_audit_logger.

  PRIVATE SECTION.
    "! <p class="shorttext synchronized">Inserta cabecera del log en zbp_audit_hdr</p>
    "! Crea registro inicial con UUID, fecha/hora ejecución, usuario y modo (simulación/real).
    "! @parameter iv_log_id | UUID único del log generado
    "! @parameter is_sel | Criterios de selección con modo simulación
    METHODS insert_header
      IMPORTING iv_log_id TYPE sysuuid_x16
                is_sel    TYPE zif_bp_processor=>ty_sel.

    "! <p class="shorttext synchronized">Inserta detalle de actualizaciones en zbp_audit_itm</p>
    "! Registra cada campo actualizado con partner/campo/valores/status/timestamp.
    "! @parameter iv_log_id | UUID del log (FK a zbp_audit_hdr)
    "! @parameter it_update_results | Resultados de actualización por campo
    METHODS insert_items
      IMPORTING iv_log_id         TYPE sysuuid_x16
                it_update_results TYPE zif_bp_persistence=>tt_update_result.

    "! <p class="shorttext synchronized">Actualiza resumen estadístico en zbp_audit_hdr</p>
    "! Completa cabecera con totales de BPs procesados, éxitos, errores y warnings.
    "! @parameter iv_log_id | UUID del log a actualizar
    "! @parameter is_summary | Resumen con contadores finales
    METHODS update_header_summary
      IMPORTING iv_log_id  TYPE sysuuid_x16
                is_summary TYPE zif_bp_audit_logger=>ty_log_summary.

    "! <p class="shorttext synchronized">Obtiene timestamp actual del sistema</p>
    "! Genera marca de tiempo precisa para created_at de registros de log.
    "! @parameter rv_timestamp | Timestamp en formato TIMESTAMPL
    METHODS get_timestamp
      RETURNING VALUE(rv_timestamp) TYPE timestampl.

    "! <p class="shorttext synchronized">Genera UUID único para el log</p>
    "! Usa cl_system_uuid con fallback a timestamp si falla generación.
    "! @parameter rv_guid | UUID en formato SYSUUID_X16
    METHODS generate_guid
      RETURNING VALUE(rv_guid) TYPE sysuuid_x16.
ENDCLASS.


CLASS zcl_bp_audit_logger IMPLEMENTATION.
  METHOD zif_bp_audit_logger~start_log.
    rv_log_id = generate_guid( ).
    insert_header( iv_log_id = rv_log_id
                   is_sel    = is_sel ).
  ENDMETHOD.

  METHOD zif_bp_audit_logger~log_bp_results.
    IF it_update_results IS INITIAL.
      RETURN.
    ENDIF.
    insert_items( iv_log_id         = iv_log_id
                  it_update_results = it_update_results ).
  ENDMETHOD.

  METHOD zif_bp_audit_logger~finalize_log.
    update_header_summary( iv_log_id  = iv_log_id
                           is_summary = is_summary ).
  ENDMETHOD.

  METHOD insert_header.
    DATA ls_header TYPE zbp_audit_hdr.

    ls_header-log_id         = iv_log_id.
    ls_header-execution_date = sy-datum.
    ls_header-execution_time = sy-uzeit.
    ls_header-username       = sy-uname.
    ls_header-is_simulation  = is_sel-is_simulation.
    ls_header-created_at     = get_timestamp( ).

    INSERT zbp_audit_hdr FROM ls_header.
    IF sy-subrc <> 0.
      " Log insert error but do not interrupt main process
      MESSAGE 'Error al insertar cabecera de log' TYPE 'I' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD insert_items.
    DATA lt_items     TYPE TABLE OF zbp_audit_itm.
    DATA lv_timestamp TYPE timestampl.

    lv_timestamp = get_timestamp( ).

    lt_items = VALUE #( FOR <result> IN it_update_results
                        ( log_id     = iv_log_id
                          partner    = <result>-partner
                          field_name = <result>-field_name
                          old_value  = <result>-old_value
                          new_value  = <result>-new_value
                          status     = <result>-result
                          message    = <result>-message
                          created_at = lv_timestamp ) ).

    IF lt_items IS NOT INITIAL.
      INSERT zbp_audit_itm FROM TABLE lt_items.
      IF sy-subrc <> 0.
        MESSAGE 'Error al insertar detalle de log' TYPE 'I' DISPLAY LIKE 'E'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD update_header_summary.
    UPDATE zbp_audit_hdr
      SET total_bp       = @is_summary-total_bp,
          total_errors   = @is_summary-total_errors,
          total_success  = @is_summary-total_success,
          total_warnings = @is_summary-total_warnings
      WHERE log_id = @iv_log_id.

    IF sy-subrc <> 0.
      MESSAGE 'Error al actualizar resumen de log' TYPE 'I' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD get_timestamp.
    GET TIME STAMP FIELD rv_timestamp.
  ENDMETHOD.

  METHOD generate_guid.
    TRY.
        rv_guid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        " Fallback: generate GUID based on timestamp and system info
        DATA lv_timestamp TYPE timestampl.
        GET TIME STAMP FIELD lv_timestamp.
        rv_guid = lv_timestamp.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
