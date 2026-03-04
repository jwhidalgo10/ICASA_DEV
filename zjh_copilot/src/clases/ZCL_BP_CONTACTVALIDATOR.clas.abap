"! <p class="shorttext synchronized">Validador de información de contacto (email y teléfono)</p>
"! Valida formato de email (estructura con @ y dominio válido) y teléfono guatemalteco (+502 + 8 dígitos).
"! Normaliza email a minúsculas sin espacios, teléfono solo con + y dígitos.
"! Retorna issues con severidad E (formato inválido) o W (normalización aplicada).
CLASS zcl_bp_contactvalidator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_validator.

  PRIVATE SECTION.
    "! <p class="shorttext synchronized">Valida formato y estructura del email</p>
    "! Verifica presencia de un @ único, partes local/dominio no vacías, dominio con punto válido.
    "! @parameter iv_partner | Business Partner ID
    "! @parameter iv_email | Email a validar
    "! @parameter rt_issues | Issues detectados (E si formato inválido, W si normalizado)
    METHODS validate_email
      IMPORTING iv_partner       TYPE string
                iv_email         TYPE string
      RETURNING VALUE(rt_issues) TYPE zif_bp_validator=>tt_issue.

    "! <p class="shorttext synchronized">Valida formato de teléfono guatemalteco</p>
    "! Verifica estructura +502 seguido de exactamente 8 dígitos numéricos.
    "! @parameter iv_partner | Business Partner ID
    "! @parameter iv_phone | Teléfono a validar
    "! @parameter rt_issues | Issues detectados (E si formato inválido, W si normalizado)
    METHODS validate_phone
      IMPORTING iv_partner       TYPE string
                iv_phone         TYPE string
      RETURNING VALUE(rt_issues) TYPE zif_bp_validator=>tt_issue.

    "! <p class="shorttext synchronized">Normaliza el email</p>
    "! Convierte a minúsculas y elimina espacios en blanco.
    "! @parameter iv_email | Email original
    "! @parameter rv_email | Email normalizado
    METHODS normalize_email
      IMPORTING iv_email        TYPE string
      RETURNING VALUE(rv_email) TYPE string.

    "! <p class="shorttext synchronized">Normaliza el teléfono</p>
    "! Elimina caracteres no válidos, conserva solo + y dígitos 0-9.
    "! @parameter iv_phone | Teléfono original
    "! @parameter rv_phone | Teléfono normalizado
    METHODS normalize_phone
      IMPORTING iv_phone        TYPE string
      RETURNING VALUE(rv_phone) TYPE string.
ENDCLASS.



CLASS zcl_bp_contactvalidator IMPLEMENTATION.
  METHOD zif_bp_validator~validate.
    rt_issues = validate_email( iv_partner = is_bp-partner
                                iv_email   = is_bp-email ).
    APPEND LINES OF validate_phone( iv_partner = is_bp-partner
                                    iv_phone   = is_bp-phone ) TO rt_issues.
  ENDMETHOD.

  METHOD validate_email.
    DATA lv_at_count TYPE i.
    DATA lv_at_pos   TYPE i.
    DATA lv_local    TYPE string.
    DATA lv_domain   TYPE string.
    DATA lv_dot_pos  TYPE i.
    DATA lv_offset   TYPE i.

    " Si email está vacío, no validar
    IF iv_email IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_orig) = iv_email.
    DATA(lv_norm) = normalize_email( iv_email ).

    " Count @
    lv_at_count = 0.
    DO strlen( lv_norm ) TIMES.
      lv_offset = sy-index - 1.
      IF lv_norm+lv_offset(1) = '@'.
        lv_at_count += 1.
        lv_at_pos = lv_offset.
      ENDIF.
    ENDDO.

    IF lv_at_count <> 1.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'E'
                      message        = 'Email debe contener exactamente un @'
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
      RETURN.
    ENDIF.

    " Extract local and domain parts
    DATA(lv_local_len) = lv_at_pos.
    DATA(lv_domain_start) = lv_at_pos + 1.
    DATA(lv_domain_len) = strlen( lv_norm ) - lv_at_pos - 1.
    lv_local = lv_norm(lv_local_len).
    lv_domain = lv_norm+lv_domain_start(lv_domain_len).

    IF lv_local IS INITIAL.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'E'
                      message        = 'Email: parte local vacía antes de @'
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
      RETURN.
    ENDIF.

    IF lv_domain IS INITIAL.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'E'
                      message        = 'Email: dominio vacío después de @'
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
      RETURN.
    ENDIF.

    " Domain must contain at least one dot
    lv_dot_pos = -1.
    DO strlen( lv_domain ) TIMES.
      lv_offset = sy-index - 1.
      IF lv_domain+lv_offset(1) = '.'.
        lv_dot_pos = lv_offset.
        EXIT.
      ENDIF.
    ENDDO.

    IF lv_dot_pos < 0.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'E'
                      message        = 'Email: dominio debe contener al menos un punto'"#EC NOTEXT
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
      RETURN.
    ENDIF.

    " Domain must not start or end with dot
    lv_domain_len = strlen( lv_domain ).
    DATA(lv_last_pos) = lv_domain_len - 1.
    IF lv_domain+0(1) = '.' OR lv_domain+lv_last_pos(1) = '.'.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'E'
                      message        = 'Email: dominio no debe iniciar ni terminar con punto'"#EC NOTEXT
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
      RETURN.
    ENDIF.

    " Normalization warning
    IF lv_norm <> lv_orig.
      APPEND VALUE #( partner        = iv_partner
                      field_name     = 'EMAIL'
                      severity       = 'W'
                      message        = 'Email normalizado'
                      original_value = lv_orig
                      proposed_value = lv_norm ) TO rt_issues.
    ENDIF.
  ENDMETHOD.

  METHOD validate_phone.
    DATA lv_digit  TYPE string.
    DATA lv_digits TYPE string.
    DATA lv_offset TYPE i.

    DATA(lv_orig) = iv_phone.
    DATA(lv_norm) = normalize_phone( iv_phone ).
    DATA(ls_issue) = VALUE zif_bp_validator=>ty_issue( partner        = iv_partner
                                                       field_name     = 'PHONE'
                                                       original_value = lv_orig
                                                       proposed_value = lv_norm ).

    IF lv_norm IS INITIAL.
      RETURN.
    ENDIF.

    " Must start with +502 and have exactly 12 chars (+502 + 8 digits)
    IF strlen( lv_norm ) <> 12 OR lv_norm(4) <> '+502'.
      ls_issue-severity = 'E'.
      ls_issue-message  = 'Teléfono debe iniciar con +502 y tener 8 dígitos'.
      APPEND ls_issue TO rt_issues.
      RETURN.
    ENDIF.

    " Extract 8 digits after +502
    DATA(lv_start_offset) = 4.
    lv_digits = lv_norm+lv_start_offset(8).

    " Validate digits are numeric
    DO 8 TIMES.
      lv_offset = sy-index - 1.
      lv_digit = lv_digits+lv_offset(1).
      IF lv_digit < '0' OR lv_digit > '9'.
        ls_issue-severity = 'E'.
        ls_issue-message  = 'Teléfono: los 8 dígitos deben ser numéricos'.
        APPEND ls_issue TO rt_issues.
        RETURN.
      ENDIF.
    ENDDO.

    " Normalization warning
    IF lv_norm <> lv_orig.
      ls_issue-severity = 'W'.
      ls_issue-message  = 'Teléfono normalizado'.
      APPEND ls_issue TO rt_issues.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_email.
    rv_email = to_lower( val = iv_email ).

    CONDENSE rv_email NO-GAPS.
  ENDMETHOD.

  METHOD normalize_phone.
    DATA lv_char   TYPE string.
    DATA lv_result TYPE string.
    DATA lv_offset TYPE i.

    rv_phone = condense( iv_phone ).

    IF rv_phone IS INITIAL.
      RETURN.
    ENDIF.

    " Remove all characters except + and digits
    CLEAR lv_result.
    DO strlen( rv_phone ) TIMES.
      lv_offset = sy-index - 1.
      lv_char = rv_phone+lv_offset(1).

      IF lv_char = '+' OR ( lv_char >= '0' AND lv_char <= '9' ).
        CONCATENATE lv_result lv_char INTO lv_result.
      ENDIF.
    ENDDO.

    rv_phone = lv_result.
  ENDMETHOD.
ENDCLASS.
