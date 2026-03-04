"! <p class="shorttext synchronized">Validador de DPI para Business Partners tipo Persona</p>
"! Valida formato y longitud de DPI (13 dígitos), normaliza removiendo guiones y espacios.
"! Retorna issues con severidad E (formato inválido) o W (normalización aplicada/vacío).
CLASS zcl_bp_dpivalidator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_validator.

  PRIVATE SECTION.
    METHODS normalize_digits
      IMPORTING iv_dpi        TYPE string
      RETURNING VALUE(rv_dpi) TYPE string.
ENDCLASS.


CLASS zcl_bp_dpivalidator IMPLEMENTATION.
  METHOD zif_bp_validator~validate.
    DATA lv_dpi_orig TYPE string.
    DATA lv_dpi_norm TYPE string.
    DATA ls_issue    TYPE zif_bp_validator=>ty_issue.

    CLEAR rt_issues.
    lv_dpi_orig = is_bp-dpi.
    lv_dpi_norm = normalize_digits( lv_dpi_orig ).

    " Empty DPI
    IF lv_dpi_norm IS INITIAL.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'DPI'.
      ls_issue-severity       = 'W'.
      ls_issue-message        = 'DPI vacío'.
      ls_issue-original_value = lv_dpi_orig.
      ls_issue-proposed_value = ''.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " Format/length check
    IF strlen( lv_dpi_norm ) <> 13 OR lv_dpi_norm CN '0123456789'.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'DPI'.
      ls_issue-severity       = 'E'.
      ls_issue-message        = 'DPI inválido (13 dígitos)'.
      ls_issue-original_value = lv_dpi_orig.
      ls_issue-proposed_value = lv_dpi_norm.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " Normalization warning
    IF lv_dpi_norm <> lv_dpi_orig.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'DPI'.
      ls_issue-severity       = 'W'.
      ls_issue-message        = 'DPI normalizado'.
      ls_issue-original_value = lv_dpi_orig.
      ls_issue-proposed_value = lv_dpi_norm.
      APPEND ls_issue TO rt_issues.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_digits.
    rv_dpi = iv_dpi.
    rv_dpi = condense( val  = rv_dpi
                       from = ` `
                       to   = `` ).
    REPLACE ALL OCCURRENCES OF '-' IN rv_dpi WITH ''.
  ENDMETHOD.
ENDCLASS.
