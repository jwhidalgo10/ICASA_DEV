"! <p class="shorttext synchronized">Actualizador de tablas de Business Partners</p>
"! Aplica correcciones validadas a la tabla zbp_but000_sim con control transaccional por BP.
"! Agrupa issues por partner, actualiza campos (NIT/DPI/EMAIL/PHONE), ejecuta COMMIT/ROLLBACK según resultado.
"! Retorna log detallado de actualizaciones con estado S/E/W, valores antiguos y nuevos por campo.
CLASS zcl_bp_table_updater DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_persistence.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_bp_issues,
             partner TYPE bu_partner,
             issues  TYPE zif_bp_processor=>tt_issue,
           END OF ty_bp_issues.

    TYPES tt_bp_issues TYPE HASHED TABLE OF ty_bp_issues WITH UNIQUE KEY partner.

    "! <p class="shorttext synchronized">Agrupa issues por Business Partner</p>
    "! Organiza los issues de validación en tabla hash indexada por partner.
    "! @parameter it_issues  | Issues detectados durante validación
    "! @parameter rt_grouped | Issues agrupados por partner con campos a corregir
    METHODS group_issues_by_partner
      IMPORTING it_issues         TYPE zif_bp_processor=>tt_issue
      RETURNING VALUE(rt_grouped) TYPE tt_bp_issues.

    "! <p class="shorttext synchronized">Aplica cambios para un Business Partner</p>
    "! Verifica existencia del BP, actualiza campos individuales, controla estado de cambios y errores.
    "! @parameter is_bp_issues   | Issues agrupados de un BP específico
    "! @parameter ev_has_changes | abap_true si al menos un campo fue actualizado
    "! @parameter ev_has_error   | abap_true si ocurrió error en alguna actualización
    "! @parameter rt_results     | Resultados de actualización por campo (S/E/W)
    METHODS apply_partner_changes
      IMPORTING is_bp_issues      TYPE ty_bp_issues
      EXPORTING ev_has_changes    TYPE abap_bool
                ev_has_error      TYPE abap_bool
      RETURNING VALUE(rt_results) TYPE zif_bp_persistence=>tt_update_result.

    "! <p class="shorttext synchronized">Construye y ejecuta sentencias UPDATE por campo</p>
    "! Extrae valores propuestos de issues, aplica actualizaciones individuales por campo, genera log de resultados.
    "! @parameter iv_partner     | Business Partner ID
    "! @parameter it_issues      | Issues con valores propuestos para actualizar
    "! @parameter ev_has_changes | abap_true si al menos un campo fue modificado
    "! @parameter et_results     | Log de resultados por campo actualizado
    METHODS build_update_statement
      IMPORTING iv_partner     TYPE bu_partner
                it_issues      TYPE zif_bp_processor=>tt_issue
      EXPORTING ev_has_changes TYPE abap_bool
                et_results     TYPE zif_bp_persistence=>tt_update_result.

    "! <p class="shorttext synchronized">Actualiza un campo individual en zbp_but000_sim</p>
    "! Ejecuta UPDATE específico por tipo de campo (NIT/DPI/EMAIL/PHONE).
    "! @parameter iv_partner   | Business Partner ID
    "! @parameter iv_field     | Nombre del campo a actualizar
    "! @parameter iv_new_value | Nuevo valor a aplicar
    "! @parameter rv_success   | abap_true si la actualización fue exitosa
    METHODS apply_field_update
      IMPORTING iv_partner        TYPE bu_partner
                iv_field          TYPE char30
                iv_new_value      TYPE string
      RETURNING VALUE(rv_success) TYPE abap_bool.
ENDCLASS.


CLASS zcl_bp_table_updater IMPLEMENTATION.
  METHOD zif_bp_persistence~apply_changes.
    DATA lt_bp_issues   TYPE tt_bp_issues.
    DATA lv_has_error   TYPE abap_bool.
    DATA lv_has_changes TYPE abap_bool.

    CLEAR rt_results.

    " Validation
    IF is_sel-is_simulation = abap_true.
      RETURN.
    ENDIF.

    IF it_issues IS INITIAL.
      RETURN.
    ENDIF.

    lt_bp_issues = group_issues_by_partner( it_issues ).

    LOOP AT lt_bp_issues ASSIGNING FIELD-SYMBOL(<ls_bp_issues>).
      CLEAR: lv_has_error,
             lv_has_changes.

      " Apply changes for this BP
      DATA(lt_bp_results) = apply_partner_changes( EXPORTING is_bp_issues   = <ls_bp_issues>
                                                   IMPORTING ev_has_changes = lv_has_changes
                                                             ev_has_error   = lv_has_error ).

      " Transaction control per BP
      IF lv_has_error = abap_true.
        ROLLBACK WORK.
        " Update all results for this BP to reflect rollback
        LOOP AT lt_bp_results ASSIGNING FIELD-SYMBOL(<ls_result>).
          IF <ls_result>-result <> 'E'.
            <ls_result>-result  = 'E'.
            <ls_result>-message = 'Cambios revertidos por error en BP'. "#EC NOTEXT
          ENDIF.
        ENDLOOP.
      ELSEIF lv_has_changes = abap_true.
        COMMIT WORK AND WAIT.
        " Mark successful changes
        LOOP AT lt_bp_results ASSIGNING <ls_result>
             WHERE result = 'S'.
          <ls_result>-message = 'Actualizado correctamente' ##NO_TEXT.
        ENDLOOP.
      ENDIF.

      APPEND LINES OF lt_bp_results TO rt_results.
    ENDLOOP.
  ENDMETHOD.

  METHOD group_issues_by_partner.
    DATA ls_grouped TYPE ty_bp_issues.

    CLEAR rt_grouped.

    LOOP AT it_issues ASSIGNING FIELD-SYMBOL(<ls_issue>)
         WHERE proposed_value IS NOT INITIAL.

      ASSIGN rt_grouped[ partner = <ls_issue>-partner ] TO FIELD-SYMBOL(<ls_group>).

      IF sy-subrc = 0.
        APPEND <ls_issue> TO <ls_group>-issues.
      ELSE.
        ls_grouped = VALUE #( partner = <ls_issue>-partner
                              issues  = VALUE #( ( <ls_issue> ) ) ).
        INSERT ls_grouped INTO TABLE rt_grouped.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD apply_partner_changes.
    DATA lv_partner       TYPE bu_partner.
    DATA lt_field_results TYPE zif_bp_persistence=>tt_update_result.

    CLEAR: rt_results,
           ev_has_changes,
           ev_has_error.

    lv_partner = is_bp_issues-partner.

    " Verify BP exists
    SELECT partner FROM zbp_but000_sim
      WHERE partner = @lv_partner
      INTO TABLE @DATA(lt_bp_check).

    IF NOT line_exists( lt_bp_check[ 1 ] ).
      APPEND VALUE #( partner    = lv_partner
                      field_name = 'EXISTENCE'                      ##NO_TEXT
                      result     = 'E'                              ##NO_TEXT
                      message    = 'Business Partner no existe' )  ##NO_TEXT
             TO rt_results.
      ev_has_error = abap_true.
      RETURN.
    ENDIF.

    " Build and execute updates
    build_update_statement( EXPORTING iv_partner     = lv_partner
                                      it_issues      = is_bp_issues-issues
                            IMPORTING ev_has_changes = ev_has_changes
                                      et_results     = lt_field_results ).

    " Check for errors in field updates
    " TODO: variable is assigned but never used (ABAP cleaner)
    LOOP AT lt_field_results ASSIGNING FIELD-SYMBOL(<ls_result>)
         WHERE result = 'E' ##NO_TEXT.
      ev_has_error = abap_true.
      EXIT.
    ENDLOOP.

    rt_results = lt_field_results.
  ENDMETHOD.

  METHOD build_update_statement.
    DATA lv_nit           TYPE string.
    DATA lv_dpi           TYPE string.
    DATA lv_email         TYPE string.
    DATA lv_phone         TYPE string.
    DATA lv_field_updated TYPE abap_bool.

    CLEAR: ev_has_changes,
           et_results.

    " Extract proposed values by field
    LOOP AT it_issues ASSIGNING FIELD-SYMBOL(<ls_issue>)
         WHERE proposed_value IS NOT INITIAL.

      IF <ls_issue>-proposed_value = <ls_issue>-original_value.
        CONTINUE.
      ENDIF.

      CASE <ls_issue>-field_name.
        WHEN 'NIT' ##NO_TEXT.
          lv_nit = <ls_issue>-proposed_value.
        WHEN 'DPI' ##NO_TEXT.
          lv_dpi = <ls_issue>-proposed_value.
        WHEN 'EMAIL' ##NO_TEXT.
          lv_email = <ls_issue>-proposed_value.
        WHEN 'PHONE' ##NO_TEXT.
          lv_phone = <ls_issue>-proposed_value.
      ENDCASE.
    ENDLOOP.

    " Apply field updates individually
    IF lv_nit IS NOT INITIAL.
      DATA(lv_nit_old) = VALUE string( ).
      ASSIGN it_issues[ field_name = 'NIT' ] TO FIELD-SYMBOL(<ls_nit_issue>) ##NO_TEXT.
      IF sy-subrc = 0.
        lv_nit_old = <ls_nit_issue>-original_value.
      ENDIF.

      lv_field_updated = apply_field_update( iv_partner   = iv_partner
                                             iv_field     = 'NIT'           ##NO_TEXT
                                             iv_new_value = lv_nit ).
      APPEND VALUE #( partner    = iv_partner
                      field_name = 'NIT'                                    ##NO_TEXT
                      result     = COND #( WHEN lv_field_updated = abap_true
                                           THEN 'S'                         ##NO_TEXT
                                           ELSE 'E' )                       ##NO_TEXT
                      message    = COND #( WHEN lv_field_updated = abap_false
                                           THEN 'Error al actualizar NIT'   ##NO_TEXT
                                           ELSE '' )
                      old_value  = lv_nit_old
                      new_value  = lv_nit )
             TO et_results.
      IF lv_field_updated = abap_true.
        ev_has_changes = abap_true.
      ENDIF.
    ENDIF.

    IF lv_dpi IS NOT INITIAL.
      DATA(lv_dpi_old) = VALUE string( ).
      ASSIGN it_issues[ field_name = 'DPI' ] TO FIELD-SYMBOL(<ls_dpi_issue>) ##NO_TEXT.
      IF sy-subrc = 0.
        lv_dpi_old = <ls_dpi_issue>-original_value.
      ENDIF.

      lv_field_updated = apply_field_update( iv_partner   = iv_partner
                                             iv_field     = 'DPI'           ##NO_TEXT
                                             iv_new_value = lv_dpi ).
      APPEND VALUE #( partner    = iv_partner
                      field_name = 'DPI'                                    ##NO_TEXT
                      result     = COND #( WHEN lv_field_updated = abap_true
                                           THEN 'S'                         ##NO_TEXT
                                           ELSE 'E' )                       ##NO_TEXT
                      message    = COND #( WHEN lv_field_updated = abap_false
                                           THEN 'Error al actualizar DPI'   ##NO_TEXT
                                           ELSE '' )
                      old_value  = lv_dpi_old
                      new_value  = lv_dpi )
             TO et_results.
      IF lv_field_updated = abap_true.
        ev_has_changes = abap_true.
      ENDIF.
    ENDIF.

    IF lv_email IS NOT INITIAL.
      DATA(lv_email_old) = VALUE string( ).
      ASSIGN it_issues[ field_name = 'EMAIL' ] TO FIELD-SYMBOL(<ls_email_issue>) ##NO_TEXT.
      IF sy-subrc = 0.
        lv_email_old = <ls_email_issue>-original_value.
      ENDIF.

      lv_field_updated = apply_field_update( iv_partner   = iv_partner
                                             iv_field     = 'EMAIL'         ##NO_TEXT
                                             iv_new_value = lv_email ).
      APPEND VALUE #( partner    = iv_partner
                      field_name = 'EMAIL'                                  ##NO_TEXT
                      result     = COND #( WHEN lv_field_updated = abap_true
                                           THEN 'S'                         ##NO_TEXT
                                           ELSE 'E' )                       ##NO_TEXT
                      message    = COND #( WHEN lv_field_updated = abap_false
                                           THEN 'Error al actualizar EMAIL' ##NO_TEXT
                                           ELSE '' )
                      old_value  = lv_email_old
                      new_value  = lv_email )
             TO et_results.
      IF lv_field_updated = abap_true.
        ev_has_changes = abap_true.
      ENDIF.
    ENDIF.

    IF lv_phone IS NOT INITIAL.
      DATA(lv_phone_old) = VALUE string( ).
      ASSIGN it_issues[ field_name = 'PHONE' ] TO FIELD-SYMBOL(<ls_phone_issue>) ##NO_TEXT.
      IF sy-subrc = 0.
        lv_phone_old = <ls_phone_issue>-original_value.
      ENDIF.

      lv_field_updated = apply_field_update( iv_partner   = iv_partner
                                             iv_field     = 'PHONE'         ##NO_TEXT
                                             iv_new_value = lv_phone ).
      APPEND VALUE #( partner    = iv_partner
                      field_name = 'PHONE'                                  ##NO_TEXT
                      result     = COND #( WHEN lv_field_updated = abap_true
                                           THEN 'S'                         ##NO_TEXT
                                           ELSE 'E' )                       ##NO_TEXT
                      message    = COND #( WHEN lv_field_updated = abap_false
                                           THEN 'Error al actualizar PHONE' ##NO_TEXT
                                           ELSE '' )
                      old_value  = lv_phone_old
                      new_value  = lv_phone )
             TO et_results.
      IF lv_field_updated = abap_true.
        ev_has_changes = abap_true.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD apply_field_update.
    rv_success = abap_false.

    TRY.
        CASE iv_field.
          WHEN 'NIT' ##NO_TEXT.
            UPDATE zbp_but000_sim
              SET nit = @iv_new_value
              WHERE partner = @iv_partner.

          WHEN 'DPI' ##NO_TEXT.
            UPDATE zbp_but000_sim
              SET dpi = @iv_new_value
              WHERE partner = @iv_partner.

          WHEN 'EMAIL' ##NO_TEXT.
            UPDATE zbp_but000_sim
              SET email = @iv_new_value
              WHERE partner = @iv_partner.

          WHEN 'PHONE' ##NO_TEXT.
            UPDATE zbp_but000_sim
              SET phone = @iv_new_value
              WHERE partner = @iv_partner.

        ENDCASE.

        IF sy-subrc = 0 AND sy-dbcnt > 0.
          rv_success = abap_true.
        ENDIF.

      CATCH cx_root.
        rv_success = abap_false.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
