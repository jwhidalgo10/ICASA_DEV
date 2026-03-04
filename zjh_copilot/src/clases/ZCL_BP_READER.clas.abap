"! <p class="shorttext synchronized">Lector de datos de Business Partners</p>
"! Lee registros de la tabla zbp_but000_sim según rango de partners seleccionado.
"! Extrae campos NIT, DPI, email y phone para validación posterior.
"! Retorna estructura normalizada compatible con zif_bp_validator=>tt_bp.
CLASS zcl_bp_reader DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_sel,
             partner_range TYPE RANGE OF bu_partner,
           END OF ty_sel.

    "! <p class="shorttext synchronized">Lee Business Partners de zbp_but000_sim</p>
    "! Ejecuta SELECT con filtro de rango de partners, mapea campos a estructura de validación.
    "! @parameter is_sel | Criterios de selección (rango de partners)
    "! @parameter rt_bp | Tabla de BPs con campos partner/bp_type/nit/dpi/email/phone
    CLASS-METHODS read_data
      IMPORTING is_sel       TYPE zif_bp_processor=>ty_sel
      RETURNING VALUE(rt_bp) TYPE  zif_bp_validator=>tt_bp.
ENDCLASS.


CLASS zcl_bp_reader IMPLEMENTATION.
  METHOD read_data.
    rt_bp = VALUE zif_bp_validator=>tt_bp( ).

    SELECT partner,
           bp_type,
           nit,
           dpi,
           email,
           phone
      FROM zbp_but000_sim
      WHERE partner IN @is_sel-partner_range
      INTO TABLE @DATA(lt_bp_raw).

    LOOP AT lt_bp_raw ASSIGNING FIELD-SYMBOL(<ls_bp_raw>).
      APPEND VALUE zif_bp_validator=>ty_bp( partner = <ls_bp_raw>-partner
                                            bp_type = <ls_bp_raw>-bp_type
                                            nit     = <ls_bp_raw>-nit
                                            dpi     = <ls_bp_raw>-dpi
                                            email   = <ls_bp_raw>-email
                                            phone   = <ls_bp_raw>-phone )
             TO rt_bp.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
