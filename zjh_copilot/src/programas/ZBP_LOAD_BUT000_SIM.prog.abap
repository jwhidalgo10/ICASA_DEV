*&---------------------------------------------------------------------*
*& Report ZBP_LOAD_BUT000_SIM
*&---------------------------------------------------------------------*
*& Carga ~20 registros de prueba en ZBP_BUT000_SIM y clasifica
*& cada uno ejecutando los valid adores reales.
*&---------------------------------------------------------------------*
REPORT zbp_load_but000_sim.

PARAMETERS: p_del    AS CHECKBOX DEFAULT 'X',
            p_commit AS CHECKBOX DEFAULT 'X'.

CLASS lcl_loader DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_bp_input,
             partner TYPE bu_partner,
             bp_type TYPE char10,
             nit     TYPE char20,
             dpi     TYPE char20,
             email   TYPE char100,
             phone   TYPE char20,
           END OF ty_bp_input,
           tt_bp_input TYPE STANDARD TABLE OF ty_bp_input WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_result,
             partner  TYPE bu_partner,
             category TYPE string, " VALID / WARNING / ERROR
             details  TYPE string,
           END OF ty_result,
           tt_result TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

    METHODS run.

  PRIVATE SECTION.
    DATA mt_data   TYPE tt_bp_input.
    DATA mt_result TYPE tt_result.

    METHODS build_dataset.
    METHODS classify_all.
    METHODS insert_data.
    METHODS print_summary.

    METHODS add
      IMPORTING iv_seq     TYPE i
                iv_bp_type TYPE char10
                iv_nit     TYPE char20
                iv_dpi     TYPE char20
                iv_email   TYPE char100
                iv_phone   TYPE char20.

    METHODS partner_from_seq
      IMPORTING iv_seq            TYPE i
      RETURNING VALUE(rv_partner) TYPE bu_partner.
ENDCLASS.


CLASS lcl_loader IMPLEMENTATION.
  METHOD run.
    build_dataset( ).
    classify_all( ).

    IF p_del = abap_true.
      DELETE FROM zbp_but000_sim. "#EC CI_NOWHERE
      IF sy-subrc = 0.
        " TODO: check spelling: previos (typo) -> previous (ABAP cleaner)
        WRITE / |Registros previos eliminados del mandante { sy-mandt }.|.
      ELSE.
        " TODO: check spelling: previos (typo) -> previous (ABAP cleaner)
        WRITE / |No había registros previos o error al eliminar.|.
      ENDIF.
    ENDIF.

    insert_data( ).
    print_summary( ).
  ENDMETHOD.

  METHOD build_dataset.
    CLEAR mt_data.

    " ========================================================
    " GRUPO 1: Casos completamente válidos (sin issues)
    " ========================================================

    " 01 - Todo válido, persona natural
    add( iv_seq     = 1
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'juan@correo.com'
         iv_phone   = '+50212345678' ).

    " 02 - Todo válido, organización, NIT 9 dígitos
    add( iv_seq     = 2
         iv_bp_type = 'ORG'
         iv_nit     = '123456789-K'
         iv_dpi     = '9876543210123'
         iv_email   = 'empresa@dominio.gt'
         iv_phone   = '+50287654321' ).

    " 03 - Válido, campos opcionales vacíos (email/phone vacíos = no validan)
    add( iv_seq     = 3
         iv_bp_type = 'PER'
         iv_nit     = '99887766-5'
         iv_dpi     = '1111222233334'
         iv_email   = ''
         iv_phone   = '' ).

    " 04 - Válido, solo NIT y DPI
    add( iv_seq     = 4
         iv_bp_type = 'PER'
         iv_nit     = '11223344-0'
         iv_dpi     = '5566778899001'
         iv_email   = 'test@example.org'
         iv_phone   = '+50255667788' ).

    " ========================================================
    " GRUPO 2: Casos normalizables (warnings)
    " ========================================================

    " 05 - NIT sin guión -> normalizable (ej: '123456789' => '12345678-9')
    add( iv_seq     = 5
         iv_bp_type = 'ORG'
         iv_nit     = '123456789'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+50212340000' ).

    " 06 - NIT con puntos -> normalizable (puntos se eliminan)
    add( iv_seq     = 6
         iv_bp_type = 'ORG'
         iv_nit     = '12.345.678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'info@empresa.com'
         iv_phone   = '+50211112222' ).

    " 07 - DPI con guiones -> normalizable (guiones se eliminan)
    add( iv_seq     = 7
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234-5678-90123'
         iv_email   = 'persona@correo.com'
         iv_phone   = '+50233334444' ).

    " 08 - DPI con espacios -> normalizable
    add( iv_seq     = 8
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234 5678 90123'
         iv_email   = 'otro@correo.com'
         iv_phone   = '+50244445555' ).

    " 09 - Email con mayúsculas -> normalizable (se pasa a lower)
    add( iv_seq     = 9
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'USUARIO@CORREO.COM'
         iv_phone   = '+50255556666' ).

    " 10 - Email con espacios -> normalizable (condense elimina espacios)
    add( iv_seq     = 10
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = ' user @ mail.com '
         iv_phone   = '+50266667777' ).

    " 11 - Phone con guiones/espacios -> normalizable (se eliminan)
    add( iv_seq     = 11
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+502 1234-5678' ).

    " 12 - Phone con paréntesis -> normalizable (se eliminan no-dígitos excepto +)
    add( iv_seq     = 12
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+502(1234)5678' ).

    " 13 - NIT con check digit 'k' minúscula -> normalizable a 'K'
    add( iv_seq     = 13
         iv_bp_type = 'ORG'
         iv_nit     = '123456789-k'
         iv_dpi     = '1234567890123'
         iv_email   = 'org@mail.com'
         iv_phone   = '+50277778888' ).

    " ========================================================
    " GRUPO 3: Casos con errores críticos (severity = E)
    " ========================================================

    " 14 - NIT demasiado corto (< 8 dígitos main)
    add( iv_seq     = 14
         iv_bp_type = 'ORG'
         iv_nit     = '1234-5'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+50211111111' ).

    " 15 - NIT con letras en parte principal
    add( iv_seq     = 15
         iv_bp_type = 'ORG'
         iv_nit     = 'ABCDEFGH-1'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+50222222222' ).

    " 16 - DPI con solo 10 dígitos (inválido, necesita 13)
    add( iv_seq     = 16
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890'
         iv_email   = 'user@mail.com'
         iv_phone   = '+50233333333' ).

    " 17 - DPI con letras (no numérico)
    add( iv_seq     = 17
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '12345ABCD0123'
         iv_email   = 'user@mail.com'
         iv_phone   = '+50244444444' ).

    " 18 - Email sin @ (error)
    add( iv_seq     = 18
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'usermailcom'
         iv_phone   = '+50255555555' ).

    " 19 - Email con dominio sin punto (error)
    add( iv_seq     = 19
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@dominio'
         iv_phone   = '+50266666666' ).

    " 20 - Phone sin +502 (error) y solo 7 dígitos
    add( iv_seq     = 20
         iv_bp_type = 'PER'
         iv_nit     = '12345678-9'
         iv_dpi     = '1234567890123'
         iv_email   = 'user@mail.com'
         iv_phone   = '1234567' ).
  ENDMETHOD.

  METHOD add.
    APPEND VALUE ty_bp_input( partner = partner_from_seq( iv_seq )
                              bp_type = iv_bp_type
                              nit     = iv_nit
                              dpi     = iv_dpi
                              email   = iv_email
                              phone   = iv_phone )
           TO mt_data.
  ENDMETHOD.

  METHOD partner_from_seq.
    rv_partner = |{ iv_seq ALIGN = RIGHT PAD = '0' WIDTH = 10 }|.
  ENDMETHOD.

  METHOD classify_all.
    DATA lo_nit_val     TYPE REF TO zcl_bp_nitvalidator.
    DATA lo_dpi_val     TYPE REF TO zcl_bp_dpivalidator.
    DATA lo_contact_val TYPE REF TO zcl_bp_contactvalidator.
    DATA lt_issues      TYPE zif_bp_validator=>tt_issue.
    DATA ls_bp          TYPE zif_bp_validator=>ty_bp.
    DATA lv_category    TYPE string.
    DATA lv_details     TYPE string.
    DATA lv_has_error   TYPE abap_bool.
    DATA lv_has_warning TYPE abap_bool.

    lo_nit_val = NEW #( ).
    lo_dpi_val = NEW #( ).
    lo_contact_val = NEW #( ).

    CLEAR mt_result.

    LOOP AT mt_data INTO DATA(ls_data).
      CLEAR: lt_issues,
             lv_category,
             lv_details,
             lv_has_error,
             lv_has_warning.

      " Map input to validator structure
      ls_bp-partner = ls_data-partner.
      ls_bp-nit     = ls_data-nit.
      ls_bp-dpi     = ls_data-dpi.
      ls_bp-email   = ls_data-email.
      ls_bp-phone   = ls_data-phone.

      " Run all three validators and collect issues
      APPEND LINES OF lo_nit_val->zif_bp_validator~validate( ls_bp ) TO lt_issues.
      APPEND LINES OF lo_dpi_val->zif_bp_validator~validate( ls_bp ) TO lt_issues.
      APPEND LINES OF lo_contact_val->zif_bp_validator~validate( ls_bp ) TO lt_issues.

      " Determine category from real validator output
      lv_has_error   = abap_false.
      lv_has_warning = abap_false.

      LOOP AT lt_issues INTO DATA(ls_issue).
        IF ls_issue-severity = 'E' ##NO_TEXT.
          lv_has_error = abap_true.
        ELSEIF ls_issue-severity = 'W' ##NO_TEXT.
          lv_has_warning = abap_true.
        ENDIF.

        IF lv_details IS NOT INITIAL.
          lv_details = |{ lv_details } ; |.
        ENDIF.
        lv_details = |{ lv_details }[{ ls_issue-severity }] { ls_issue-field_name }: { ls_issue-message }|.
      ENDLOOP.

      IF lv_has_error = abap_true.
        lv_category = 'ERROR' ##NO_TEXT.
      ELSEIF lv_has_warning = abap_true.
        lv_category = 'WARNING' ##NO_TEXT.
      ELSE.
        lv_category = 'VALID' ##NO_TEXT.
      ENDIF.

      IF lv_details IS INITIAL.
        lv_details = 'Sin issues' ##NO_TEXT.
      ENDIF.

      APPEND VALUE ty_result( partner  = ls_data-partner
                              category = lv_category
                              details  = lv_details )
             TO mt_result.
    ENDLOOP.
  ENDMETHOD.

  METHOD insert_data.
    DATA lt_db TYPE STANDARD TABLE OF zbp_but000_sim.

    LOOP AT mt_data INTO DATA(ls_data).
      APPEND VALUE zbp_but000_sim( client  = sy-mandt
                                   partner = ls_data-partner
                                   bp_type = ls_data-bp_type
                                   nit     = ls_data-nit
                                   dpi     = ls_data-dpi
                                   email   = ls_data-email
                                   phone   = ls_data-phone )
             TO lt_db.
    ENDLOOP.

    INSERT zbp_but000_sim FROM TABLE lt_db.

    IF sy-subrc = 0.
      WRITE / |{ lines( lt_db ) } registros insertados correctamente.|.
    ELSE.
      WRITE / |Error al insertar registros (sy-subrc = { sy-subrc }).|.
    ENDIF.

    IF p_commit = abap_true.
      COMMIT WORK AND WAIT.
      WRITE / |COMMIT ejecutado.|. "#EC NOTEXT
    ENDIF.
  ENDMETHOD.

  METHOD print_summary.
    DATA lv_valid   TYPE i VALUE 0.
    DATA lv_warning TYPE i VALUE 0.
    DATA lv_error   TYPE i VALUE 0.

    ULINE.
    WRITE / |===== RESUMEN DE CLASIFICACIÓN =====|.
    ULINE.

    LOOP AT mt_result INTO DATA(ls_res).
      CASE ls_res-category.
        WHEN 'VALID'. lv_valid += 1.
        WHEN 'WARNING'. lv_warning += 1.
        WHEN 'ERROR'. lv_error += 1.
      ENDCASE.
    ENDLOOP.

    WRITE / |Total registros: { lines( mt_result ) }|.
    WRITE / |  Válidos:       { lv_valid }|.
    WRITE / |  Normalizables: { lv_warning }|.
    WRITE / |  Con errores:   { lv_error }|.
    ULINE.

    WRITE / |===== DETALLE POR REGISTRO =====|.
    ULINE.

    LOOP AT mt_result INTO ls_res.
      WRITE / |Partner: { ls_res-partner } \| Categoria: { ls_res-category }|. "#EC NOTEXT
      WRITE / |  { ls_res-details }|.
    ENDLOOP.

    ULINE.
  ENDMETHOD.
ENDCLASS.


START-OF-SELECTION.
  DATA(lo_loader) = NEW lcl_loader( ).
  lo_loader->run( ).
