"! <p class="shorttext synchronized">Procesador central de validación de Business Partners</p>
"! Orquesta la lectura, validación, aplicación de cambios y logging de BPs.
"! Procesa todos los BPs del rango seleccionado, valida según tipo (ORG/PER), aplica correcciones si no es simulación.
"! Genera resumen ALV agrupado por BP con contadores de errores/warnings y log de auditoría completo.
CLASS zcl_bp_processor DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_processor.

  PRIVATE SECTION.
    "! <p class="shorttext synchronized">Calcula resumen estadístico de procesamiento</p>
    "! Cuenta total de BPs procesados y agrupa resultados de actualización por tipo (S/E/W).
    "! @parameter it_update_results | Resultados de actualización de campos
    "! @parameter it_bp | BPs procesados en esta ejecución
    "! @parameter rs_summary | Resumen con totales de BP/éxitos/errores/warnings
    METHODS calculate_summary
      IMPORTING it_update_results TYPE zif_bp_persistence=>tt_update_result
                it_bp             TYPE zif_bp_validator=>tt_bp
      RETURNING VALUE(rs_summary) TYPE zif_bp_audit_logger=>ty_log_summary.
ENDCLASS.


CLASS zcl_bp_processor IMPLEMENTATION.
  METHOD zif_bp_processor~process.
    TYPES: BEGIN OF ty_issue_group,
             partner TYPE string,
             issues  TYPE zif_bp_processor=>tt_issue,
           END OF ty_issue_group.
    TYPES tt_issue_group TYPE HASHED TABLE OF ty_issue_group WITH UNIQUE KEY partner.

    DATA lt_bp             TYPE zif_bp_validator=>tt_bp.
    DATA lt_all_issues     TYPE zif_bp_processor=>tt_issue.
    DATA lt_issue_group    TYPE tt_issue_group.
    DATA lt_alv            TYPE zif_bp_processor=>tt_alv.
    DATA lt_update_results TYPE zif_bp_persistence=>tt_update_result.
    DATA lo_audit_logger   TYPE REF TO zif_bp_audit_logger.
    DATA lv_log_id         TYPE sysuuid_x16.

    " 1. Initialize audit logger
    lo_audit_logger = NEW zcl_bp_audit_logger( ).
    lv_log_id = lo_audit_logger->start_log( is_sel = is_sel ).

    " 2. Read data
    lt_bp = zcl_bp_reader=>read_data( is_sel ).

    IF lt_bp IS INITIAL.
      CLEAR: rt_alv,
             rt_issues.
      RETURN.
    ENDIF.

    " 3. Validate
    DATA(lo_validator) = NEW zcl_bp_validator( ).

    LOOP AT lt_bp ASSIGNING FIELD-SYMBOL(<ls_bp>).
      DATA(ls_bp_val) = CORRESPONDING zif_bp_validator=>ty_bp( <ls_bp> ).
      DATA(lt_bp_issues) = lo_validator->zif_bp_validator~validate( is_bp = ls_bp_val ).
      APPEND LINES OF lt_bp_issues TO lt_all_issues.
    ENDLOOP.

    " 4. Apply updates if not simulation
    IF is_sel-is_simulation = abap_false.
      DATA(lo_updater) = NEW zcl_bp_table_updater( ).
      lt_update_results = lo_updater->zif_bp_persistence~apply_changes( is_sel    = is_sel
                                                                        it_issues = lt_all_issues ).

      " 5. Log update results
      lo_audit_logger->log_bp_results( iv_log_id         = lv_log_id
                                       it_update_results = lt_update_results ).

      " Merge update results into issues
      LOOP AT lt_update_results ASSIGNING FIELD-SYMBOL(<ls_update>).
        IF <ls_update>-result = 'E'.
          APPEND VALUE #( partner        = <ls_update>-partner
                          field_name     = <ls_update>-field_name
                          severity       = 'E'
                          message        = <ls_update>-message
                          original_value = <ls_update>-old_value
                          proposed_value = <ls_update>-new_value )
                 TO lt_all_issues.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 6. Calculate and finalize audit log
    DATA(ls_summary) = calculate_summary( it_update_results = lt_update_results
                                          it_bp             = lt_bp ).

    lo_audit_logger->finalize_log( iv_log_id  = lv_log_id
                                   is_summary = ls_summary ).

    IF lt_all_issues IS INITIAL.
      CLEAR: rt_alv,
             rt_issues.
      RETURN.
    ENDIF.

    " 7. Group and build ALV (existing logic)
    LOOP AT lt_all_issues ASSIGNING FIELD-SYMBOL(<ls_issue>).
      ASSIGN lt_issue_group[ partner = <ls_issue>-partner ]
             TO FIELD-SYMBOL(<ls_group>).
      IF sy-subrc = 0.
        APPEND <ls_issue> TO <ls_group>-issues.
      ELSE.
        DATA(ls_new_group) = VALUE ty_issue_group( partner = <ls_issue>-partner
                                                   issues  = VALUE #( ( <ls_issue> ) ) ).
        INSERT ls_new_group INTO TABLE lt_issue_group.
      ENDIF.
    ENDLOOP.

    " Build ALV summary
    LOOP AT lt_bp ASSIGNING <ls_bp>.
      ASSIGN lt_issue_group[ partner = <ls_bp>-partner ] TO <ls_group>.
      DATA(lt_issues_bp) = VALUE zif_bp_processor=>tt_issue( ).
      IF <ls_group> IS ASSIGNED.
        lt_issues_bp = <ls_group>-issues.
      ENDIF.

      DATA(lv_status) = 'G'.
      DATA(lv_errors) = 0.
      DATA(lv_warnings) = 0.

      LOOP AT lt_issues_bp ASSIGNING FIELD-SYMBOL(<ls_iss>).
        IF <ls_iss>-severity = 'E'.
          lv_status = 'R'.
          lv_errors += 1.
        ELSEIF <ls_iss>-severity = 'W' AND lv_status <> 'R'.
          lv_status = 'Y'.
          lv_warnings += 1.
        ENDIF.
      ENDLOOP.

      APPEND VALUE #( partner  = <ls_bp>-partner
                      bp_type  = <ls_bp>-bp_type
                      status   = lv_status
                      errors   = lv_errors
                      warnings = lv_warnings )
             TO lt_alv.
    ENDLOOP.

    rt_alv = lt_alv.
    rt_issues = lt_all_issues.
  ENDMETHOD.

  METHOD calculate_summary.
    DATA lt_partners TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    CLEAR rs_summary.

    " Total unique BPs processed
    lt_partners = VALUE #( FOR <bp> IN it_bp
                           ( <bp>-partner ) ).
    rs_summary-total_bp = lines( lt_partners ).

    " Count by result status
    LOOP AT it_update_results ASSIGNING FIELD-SYMBOL(<result>).
      CASE <result>-result.
        WHEN 'S'.
          rs_summary-total_success += 1.
        WHEN 'E'.
          rs_summary-total_errors += 1.
        WHEN 'W'.
          rs_summary-total_warnings += 1.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
