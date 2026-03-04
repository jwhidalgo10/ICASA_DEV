"! <p class="shorttext synchronized">Interfaz para persistencia de cambios en Business Partners</p>
"! Gestiona la aplicación de correcciones a la tabla de BPs (zbp_but000_sim).
"! Soporta modo simulación y transaccionalidad por BP (commit/rollback individual).
INTERFACE zif_bp_persistence
  PUBLIC.

  TYPES: BEGIN OF ty_update_result,
           partner    TYPE bu_partner,
           field_name TYPE char30,
           result     TYPE char1,     " S=Success, E=Error, W=Warning
           message    TYPE string,
           old_value  TYPE char100,
           new_value  TYPE char100,
         END OF ty_update_result.

  TYPES: tt_update_result TYPE STANDARD TABLE OF ty_update_result WITH EMPTY KEY.

  "! <p class="shorttext synchronized">Aplica correcciones a la base de datos</p>
  "! Ejecuta UPDATE en zbp_but000_sim con valores corregidos de it_issues.
  "! Si is_simulation = abap_true, retorna vacío sin aplicar cambios.
  "! Manejo transaccional: COMMIT si éxito, ROLLBACK si error en cualquier campo del BP.
  "!
  "! @parameter is_sel | Criterios de selección (include flag is_simulation)
  "! @parameter it_issues | Issues con proposed_value a aplicar (NIT, DPI, EMAIL, PHONE)
  "! @parameter rt_results | Resultado por campo actualizado: status S/E/W, mensaje, old/new value
  METHODS apply_changes
    IMPORTING
      is_sel            TYPE zif_bp_processor=>ty_sel
      it_issues         TYPE zif_bp_processor=>tt_issue
    RETURNING
      VALUE(rt_results) TYPE tt_update_result.

ENDINTERFACE.
