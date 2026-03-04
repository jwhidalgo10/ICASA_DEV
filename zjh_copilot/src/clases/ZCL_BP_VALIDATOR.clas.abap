"! <p class="shorttext synchronized">Coordinador de validaciones de Business Partners</p>
"! Orquesta la validación según tipo de BP: NIT para ORG, DPI para PER, contacto para ambos.
"! Delega a validadores especializados (NIT/DPI/contacto) y consolida issues detectados.
"! Implementa patrón Singleton por tipo de validador para reutilización de instancias.
CLASS zcl_bp_validator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bp_validator.

  PRIVATE SECTION.
    DATA mo_nit_validator     TYPE REF TO zcl_bp_nitvalidator.
    DATA mo_dpi_validator     TYPE REF TO zcl_bp_dpivalidator.
    DATA mo_contact_validator TYPE REF TO zcl_bp_contactvalidator.

    "! <p class="shorttext synchronized">Obtiene instancia singleton del validador de NIT</p>
    "! Crea la instancia solo en primera llamada, reutiliza en siguientes.
    "! @parameter ro_validator | Instancia del validador de NIT
    METHODS get_nit_validator
      RETURNING VALUE(ro_validator) TYPE REF TO zcl_bp_nitvalidator.

    "! <p class="shorttext synchronized">Obtiene instancia singleton del validador de DPI</p>
    "! Crea la instancia solo en primera llamada, reutiliza en siguientes.
    "! @parameter ro_validator | Instancia del validador de DPI
    METHODS get_dpi_validator
      RETURNING VALUE(ro_validator) TYPE REF TO zcl_bp_dpivalidator.

    "! <p class="shorttext synchronized">Obtiene instancia singleton del validador de contacto</p>
    "! Crea la instancia solo en primera llamada, reutiliza en siguientes.
    "! @parameter ro_validator | Instancia del validador de email/teléfono
    METHODS get_contact_validator
      RETURNING VALUE(ro_validator) TYPE REF TO zcl_bp_contactvalidator.
ENDCLASS.


CLASS zcl_bp_validator IMPLEMENTATION.
  METHOD zif_bp_validator~validate.
    rt_issues = VALUE zif_bp_validator=>tt_issue( ).

    " Validate NIT or DPI based on bp_type
    IF is_bp-bp_type = 'ORG'.
      APPEND LINES OF me->get_nit_validator( )->zif_bp_validator~validate( is_bp = is_bp ) TO rt_issues.
    ELSEIF is_bp-bp_type = 'PER'.
      APPEND LINES OF me->get_dpi_validator( )->zif_bp_validator~validate( is_bp = is_bp ) TO rt_issues.
    ENDIF.

    " Always validate contact info for ORG and PER
    IF is_bp-bp_type = 'ORG' OR is_bp-bp_type = 'PER'.
      APPEND LINES OF me->get_contact_validator( )->zif_bp_validator~validate( is_bp = is_bp ) TO rt_issues.
    ENDIF.
    " No validation for unknown type
  ENDMETHOD.

  METHOD get_nit_validator.
    IF mo_nit_validator IS INITIAL.
      mo_nit_validator = NEW #( ).
    ENDIF.
    ro_validator = mo_nit_validator.
  ENDMETHOD.

  METHOD get_dpi_validator.
    IF mo_dpi_validator IS INITIAL.
      mo_dpi_validator = NEW #( ).
    ENDIF.
    ro_validator = mo_dpi_validator.
  ENDMETHOD.

  METHOD get_contact_validator.
    IF mo_contact_validator IS INITIAL.
      mo_contact_validator = NEW #( ).
    ENDIF.
    ro_validator = mo_contact_validator.
  ENDMETHOD.
ENDCLASS.
