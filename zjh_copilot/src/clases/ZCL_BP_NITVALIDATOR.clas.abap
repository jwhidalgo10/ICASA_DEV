"! <p class="shorttext synchronized">Validador de NIT para Business Partners</p>
"! Implementa reglas de validación y normalización de NITs, incluyendo formato y cálculo de dígito verificador.
CLASS zcl_bp_nitvalidator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_validator.

    "! <p class="shorttext synchronized">Tipo para representar un dígito</p>
    TYPES ty_digit TYPE c LENGTH 1.

  PRIVATE SECTION.
    "! <p class="shorttext synchronized">Normaliza el formato del NIT</p>
    "! Elimina caracteres no válidos y aplica formato estándar con guion.
    "! @parameter iv_nit | NIT original a normalizar
    "! @parameter rv_nit | NIT normalizado o vacío si el formato es inválido
    METHODS normalize_nit
      IMPORTING iv_nit        TYPE string
      RETURNING VALUE(rv_nit) TYPE string.

    "! <p class="shorttext synchronized">Verifica si el formato del NIT es válido</p>
    "! Comprueba longitud, caracteres permitidos y estructura con guion.
    "! @parameter iv_nit | NIT a verificar
    "! @parameter rv_ok  | abap_true si el formato es válido, abap_false en caso contrario
    METHODS is_format_ok
      IMPORTING iv_nit       TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    "! <p class="shorttext synchronized">Calcula el dígito verificador del NIT</p>
    "! Aplica reglas específicas para obtener el dígito de control.
    "! @parameter iv_nit   | NIT base sin dígito verificador
    "! @parameter rv_digit | Dígito calculado o vacío si el cálculo falla
    METHODS calc_check_digit
      IMPORTING iv_nit          TYPE string
      RETURNING VALUE(rv_digit) TYPE ty_digit.

    "! <p class="shorttext synchronized">Verifica si el NIT ya está normalizado</p>
    "! Comprueba si el NIT cumple con el formato estándar.
    "! @parameter iv_nit | NIT a verificar
    "! @parameter rv_ok  | abap_true si ya está normalizado, abap_false en caso contrario
    METHODS is_already_normalized
      IMPORTING iv_nit       TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_bool.

ENDCLASS.


CLASS zcl_bp_nitvalidator IMPLEMENTATION.
  METHOD zif_bp_validator~validate.
    DATA lv_nit_orig TYPE string.
    DATA lv_nit_norm TYPE string.
    DATA ls_issue    TYPE zif_bp_validator=>ty_issue.

    CLEAR rt_issues.
    lv_nit_orig = is_bp-nit.

    " 1. Validar si está vacío ANTES de normalizar
    IF lv_nit_orig IS INITIAL.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'NIT'.
      ls_issue-severity       = 'W'.
      ls_issue-message        = 'NIT vacío'.
      ls_issue-original_value = lv_nit_orig.
      ls_issue-proposed_value = ''.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " 2. Intentar normalizar
    lv_nit_norm = normalize_nit( lv_nit_orig ).

    " 3. Si normalización falla (devuelve vacío) -> formato inválido
    IF lv_nit_norm IS INITIAL.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'NIT'.
      ls_issue-severity       = 'E'.
      ls_issue-message        = 'NIT inválido (formato)'.
      ls_issue-original_value = lv_nit_orig.
      ls_issue-proposed_value = ''.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " 4. Validar formato del normalizado
    IF is_format_ok( lv_nit_norm ) = abap_false.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'NIT'.
      ls_issue-severity       = 'E'.
      ls_issue-message        = 'NIT inválido (formato)'.
      ls_issue-original_value = lv_nit_orig.
      ls_issue-proposed_value = lv_nit_norm.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " 5. Warning si se normalizó
    IF lv_nit_norm <> lv_nit_orig AND is_already_normalized( lv_nit_orig ) = abap_false.
      CLEAR ls_issue.
      ls_issue-partner        = is_bp-partner.
      ls_issue-field_name     = 'NIT'.
      ls_issue-severity       = 'W'.
      ls_issue-message        = 'NIT normalizado'.
      ls_issue-original_value = lv_nit_orig.
      ls_issue-proposed_value = lv_nit_norm.
      APPEND ls_issue TO rt_issues.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_nit.
    DATA lv_clean TYPE string.
    DATA lv_len   TYPE i.
    DATA lv_main  TYPE string.
    DATA lv_chk   TYPE c LENGTH 1.

    lv_clean = iv_nit.

    lv_clean = condense( val  = lv_clean
                         from = ` `
                         to   = `` ).
    REPLACE ALL OCCURRENCES OF '.' IN lv_clean WITH ''.
    REPLACE ALL OCCURRENCES OF ',' IN lv_clean WITH ''.
    REPLACE ALL OCCURRENCES OF '/' IN lv_clean WITH ''.
    REPLACE ALL OCCURRENCES OF '\' IN lv_clean WITH ''.
    REPLACE ALL OCCURRENCES OF '_' IN lv_clean WITH ''.

    IF lv_clean IS INITIAL.
      rv_nit = ''.
      RETURN.
    ENDIF.

    IF is_already_normalized( lv_clean ) = abap_true.
      rv_nit = lv_clean.
      RETURN.
    ENDIF.

    REPLACE ALL OCCURRENCES OF '-' IN lv_clean WITH ''.

    IF lv_clean IS INITIAL.
      rv_nit = ''.
      RETURN.
    ENDIF.

    lv_len = strlen( lv_clean ).

    IF lv_len < 9 OR lv_len > 10.
      rv_nit = ''.
      RETURN.
    ENDIF.

    lv_main = substring( val = lv_clean
                         off = 0
                         len = lv_len - 1 ).
    lv_chk  = substring( val = lv_clean
                         off = lv_len - 1
                         len = 1 ).

    IF strlen( lv_main ) < 8 OR strlen( lv_main ) > 9.
      rv_nit = ''.
      RETURN.
    ENDIF.

    IF lv_main CN '0123456789'.
      rv_nit = ''.
      RETURN.
    ENDIF.

    DATA(lv_chk_upper) = to_upper( lv_chk ).
    IF lv_chk_upper CN '0123456789K'.
      rv_nit = ''.
      RETURN.
    ENDIF.

    rv_nit = |{ lv_main }-{ lv_chk_upper }|.
  ENDMETHOD.

  METHOD is_format_ok.
    DATA lv_main TYPE string.
    DATA lv_chk  TYPE string.
    DATA lv_len  TYPE i.

    rv_ok = abap_false.

    IF iv_nit NS '-'.
      RETURN.
    ENDIF.

    SPLIT iv_nit AT '-' INTO lv_main lv_chk.

    IF lv_chk IS INITIAL OR strlen( lv_chk ) <> 1.
      RETURN.
    ENDIF.

    lv_len = strlen( lv_main ).
    IF lv_len < 8 OR lv_len > 9.
      RETURN.
    ENDIF.

    IF lv_main CN '0123456789'.
      RETURN.
    ENDIF.

    DATA(lv_chk_upper) = to_upper( lv_chk ).
    IF lv_chk_upper CN '0123456789K'.
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.

  METHOD calc_check_digit.
    IF iv_nit IS INITIAL.
      rv_digit = ''.
      RETURN.
    ENDIF.

    IF iv_nit CN '0123456789'.
      rv_digit = ''.
      RETURN.
    ENDIF.

    rv_digit = '0'.
  ENDMETHOD.

  METHOD is_already_normalized.
    DATA lv_main TYPE string.
    DATA lv_chk  TYPE string.
    DATA lv_len  TYPE i.

    rv_ok = abap_false.

    IF iv_nit NS '-'.
      RETURN.
    ENDIF.

    SPLIT iv_nit AT '-' INTO lv_main lv_chk.

    IF lv_chk IS INITIAL OR strlen( lv_chk ) <> 1.
      RETURN.
    ENDIF.

    lv_len = strlen( lv_main ).
    IF lv_len < 8 OR lv_len > 9.
      RETURN.
    ENDIF.

    IF lv_main CN '0123456789'.
      RETURN.
    ENDIF.

    DATA(lv_chk_upper) = to_upper( lv_chk ).
    IF lv_chk_upper CN '0123456789K'.
      RETURN.
    ENDIF.

    IF lv_chk <> lv_chk_upper.
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.
ENDCLASS.
