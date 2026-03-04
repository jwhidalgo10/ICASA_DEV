"! <p class="shorttext synchronized">Presentador ALV de auditoría de Business Partners</p>
"! Transforma issues de validación en filas ALV con semáforo visual, filtra por tipo de BP y severidad.
"! Construye tabla UI con columnas partner/tipo/campo/valores/icono de estado (verde/amarillo/rojo).
"! Configura SALV con optimización automática de columnas, oculta campos técnicos y muestra fila "OK" si no hay issues.
CLASS zcl_bp_alv_presenter DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Fila UI del ALV de auditoría</p>
    " Combina datos de BP, campo validado, valores original/propuesto e indicador visual de estado.
    TYPES: BEGIN OF ty_ui_row,
             partner        TYPE bu_partner,
             bp_type        TYPE char10,
             field_name     TYPE char30,
             current_value  TYPE char100,
             proposed_value TYPE char100,
             status_icon    TYPE icon_d,
             status_tech    TYPE char1,
           END OF ty_ui_row.

    TYPES tt_ui_row TYPE STANDARD TABLE OF ty_ui_row WITH EMPTY KEY.

    "! <p class="shorttext synchronized">Muestra ALV con issues filtrados</p>
    "! Aplica filtros por tipo de BP y solo errores, construye filas UI con semáforo, configura SALV y despliega.
    "! @parameter it_alv_summary | Resumen de BPs procesados (partner/tipo/status/contadores)
    "! @parameter it_issues | Issues detectados durante validación (partner/campo/valores/severidad)
    "! @parameter iv_bp_type | Filtro de tipo de BP: ALL/PER/ORG (default ALL)
    "! @parameter iv_err_only | abap_true para mostrar solo registros con errores (default abap_false)
    "! @raising cx_salv_msg | Error en configuración de SALV
    "! @raising cx_salv_not_found | Columna no encontrada en metadata SALV
    CLASS-METHODS display
      IMPORTING it_alv_summary TYPE zif_bp_processor=>tt_alv
                it_issues      TYPE zif_bp_processor=>tt_issue
                iv_bp_type     TYPE char3     DEFAULT 'ALL'
                iv_err_only    TYPE abap_bool DEFAULT abap_false
      RAISING   cx_salv_msg
                cx_salv_not_found.

  PRIVATE SECTION.
    "! <p class="shorttext synchronized">Construye filas UI desde issues y resumen ALV</p>
    "! Itera BPs ordenados por partner, crea fila por issue detectado o fila "OK" si no hay issues.
    "! @parameter it_alv_summary | Resumen de BPs filtrados (ya aplicados filtros de tipo/errores)
    "! @parameter it_issues | Issues completos (se filtran por partner en runtime)
    "! @parameter rt_ui_rows | Tabla UI con semáforo y valores para despliegue SALV
    CLASS-METHODS build_ui_rows
      IMPORTING it_alv_summary    TYPE zif_bp_processor=>tt_alv
                it_issues         TYPE zif_bp_processor=>tt_issue
      RETURNING VALUE(rt_ui_rows) TYPE tt_ui_row.

    "! <p class="shorttext synchronized">Mapea severidad de issue a estado de semáforo</p>
    "! Convierte E/W/otros a R/Y/G para lógica de icono y filtrado.
    "! @parameter iv_severity | Severidad del issue (E=Error, W=Warning, otros)
    "! @parameter rv_status | Estado técnico (R=Rojo, Y=Amarillo, G=Verde)
    CLASS-METHODS map_severity_to_status
      IMPORTING iv_severity      TYPE string
      RETURNING VALUE(rv_status) TYPE char1.

    "! <p class="shorttext synchronized">Obtiene icono de semáforo según estado</p>
    "! Retorna constante de icono ABAP (icon_red_light/icon_yellow_light/icon_green_light).
    "! @parameter iv_status | Estado técnico (R/Y/G)
    "! @parameter rv_icon | Icono de semáforo para columna STATUS_ICON
    CLASS-METHODS get_status_icon
      IMPORTING iv_status      TYPE char1
      RETURNING VALUE(rv_icon) TYPE icon_d.

    "! <p class="shorttext synchronized">Configura columnas del SALV</p>
    "! Optimiza anchos automáticamente, establece textos largos/medios/cortos, oculta STATUS_TECH.
    "! @parameter io_columns | Objeto de columnas SALV a configurar
    "! @raising cx_salv_not_found | Columna no encontrada en metadata
    CLASS-METHODS configure_salv_columns
      IMPORTING io_columns TYPE REF TO cl_salv_columns_table
      RAISING   cx_salv_not_found.

    "! <p class="shorttext synchronized">Establece propiedades de una columna individual</p>
    "! Aplica textos descriptivos en 3 longitudes (largo/medio/corto) para adaptación responsive.
    "! @parameter io_columns | Objeto de columnas SALV
    "! @parameter iv_columnname | Nombre técnico de la columna
    "! @parameter iv_long_text | Texto largo (display completo)
    "! @parameter iv_medium_text | Texto medio (opcional, display reducido)
    "! @parameter iv_short_text | Texto corto (opcional, display mínimo)
    "! @raising cx_salv_not_found | Columna no encontrada
    CLASS-METHODS set_column_properties
      IMPORTING io_columns     TYPE REF TO cl_salv_columns_table
                iv_columnname  TYPE lvc_fname
                iv_long_text   TYPE scrtext_l
                iv_medium_text TYPE scrtext_m OPTIONAL
                iv_short_text  TYPE scrtext_s OPTIONAL
      RAISING   cx_salv_not_found.
ENDCLASS.



CLASS zcl_bp_alv_presenter IMPLEMENTATION.
  METHOD display.
    DATA lt_ui_rows     TYPE tt_ui_row.
    DATA lt_alv_summary TYPE zif_bp_processor=>tt_alv.
    DATA lo_salv        TYPE REF TO cl_salv_table.

    " Aplicar filtros ANTES de construir filas
    lt_alv_summary = it_alv_summary.

    IF iv_bp_type <> 'ALL'.
      lt_alv_summary = VALUE #( FOR <alv> IN lt_alv_summary
                                WHERE ( bp_type = iv_bp_type )
                                ( <alv> ) ).
    ENDIF.

    " Aplicar filtro de solo errores
    IF iv_err_only = abap_true.
      DELETE lt_alv_summary WHERE status <> 'R' AND errors <= 0.
    ENDIF.

    " Construir filas solo con BPs filtrados
    lt_ui_rows = build_ui_rows( it_alv_summary = lt_alv_summary
                                it_issues      = it_issues ).
    IF lt_ui_rows IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                                CHANGING  t_table      = lt_ui_rows ).

        configure_salv_columns( lo_salv->get_columns( ) ).

        lo_salv->get_functions( )->set_all( abap_true ).
        lo_salv->get_display_settings( )->set_list_header( 'Auditoría de Business Partners' )."#EC NOTEXT
        lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).

        lo_salv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_salv).
        RAISE EXCEPTION lx_salv.
    ENDTRY.
  ENDMETHOD.

  METHOD build_ui_rows.
    DATA lt_partner_issues TYPE zif_bp_processor=>tt_issue.
    DATA lt_alv_sorted     TYPE zif_bp_processor=>tt_alv.

    " Ordenar el ALV summary por partner para mantener consistencia
    lt_alv_sorted = it_alv_summary.
    SORT lt_alv_sorted BY partner ASCENDING.

    " Iterar sobre TODOS los BPs del resumen ordenados
    LOOP AT lt_alv_sorted ASSIGNING FIELD-SYMBOL(<alv_entry>).

      " Buscar issues de este partner
      CLEAR lt_partner_issues.
      LOOP AT it_issues ASSIGNING FIELD-SYMBOL(<issue>)
           WHERE partner = <alv_entry>-partner.
        APPEND <issue> TO lt_partner_issues.
      ENDLOOP.

      " Si tiene issues, crear filas detalladas
      IF lt_partner_issues IS NOT INITIAL.
        LOOP AT lt_partner_issues ASSIGNING <issue>.
          DATA(lv_status) = map_severity_to_status( <issue>-severity ).

          APPEND VALUE #( partner        = <issue>-partner
                          bp_type        = <alv_entry>-bp_type
                          field_name     = <issue>-field_name
                          current_value  = <issue>-original_value
                          proposed_value = <issue>-proposed_value
                          status_tech    = lv_status
                          status_icon    = get_status_icon( lv_status ) )
                 TO rt_ui_rows.
        ENDLOOP.
      ELSE.
        " Si NO tiene issues, mostrar fila "OK"
        APPEND VALUE #( partner        = <alv_entry>-partner
                        bp_type        = <alv_entry>-bp_type
                        field_name     = 'VALIDACIÓN'
                        current_value  = 'Sin problemas'
                        proposed_value = ''
                        status_tech    = 'G'
                        status_icon    = get_status_icon( 'G' ) )
               TO rt_ui_rows.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD map_severity_to_status.
    rv_status = SWITCH #( iv_severity
                          WHEN 'E' THEN 'R'
                          WHEN 'W' THEN 'Y'
                          ELSE          'G' ).
  ENDMETHOD.

  METHOD get_status_icon.
    rv_icon = SWITCH icon_d( iv_status
                             WHEN 'R' THEN icon_red_light
                             WHEN 'Y' THEN icon_yellow_light
                             ELSE          icon_green_light ).
  ENDMETHOD.

METHOD configure_salv_columns.
  io_columns->set_optimize( abap_true ).

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'PARTNER'
                         iv_long_text   = 'Business Partner'        "#EC NOTEXT
                         iv_medium_text = 'BP'                      "#EC NOTEXT
                         iv_short_text  = 'BP' ).                   "#EC NOTEXT

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'BP_TYPE'
                         iv_long_text   = 'Tipo de BP'              "#EC NOTEXT
                         iv_medium_text = 'Tipo'                    "#EC NOTEXT
                         iv_short_text  = 'Tipo' ).                 "#EC NOTEXT

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'FIELD_NAME'
                         iv_long_text   = 'Campo'                   "#EC NOTEXT
                         iv_medium_text = 'Campo'                   "#EC NOTEXT
                         iv_short_text  = 'Campo' ).                "#EC NOTEXT

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'CURRENT_VALUE'
                         iv_long_text   = 'Valor Actual'            "#EC NOTEXT
                         iv_medium_text = 'Actual'                  "#EC NOTEXT
                         iv_short_text  = 'Actual' ).               "#EC NOTEXT

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'PROPOSED_VALUE'
                         iv_long_text   = 'Valor Corregido'         "#EC NOTEXT
                         iv_medium_text = 'Corregido'               "#EC NOTEXT
                         iv_short_text  = 'Correg.' ).              "#EC NOTEXT

  set_column_properties( io_columns     = io_columns
                         iv_columnname  = 'STATUS_ICON'
                         iv_long_text   = 'Estado'                  "#EC NOTEXT
                         iv_medium_text = 'Estado'                  "#EC NOTEXT
                         iv_short_text  = 'Est.' ).                 "#EC NOTEXT

  TRY.
      DATA(lo_column) = io_columns->get_column( 'STATUS_TECH' ). "#EC NOTEXT
      lo_column->set_technical( abap_true ).
    CATCH cx_salv_not_found.
  ENDTRY.
ENDMETHOD.


  METHOD set_column_properties.
    DATA(lo_column) = io_columns->get_column( iv_columnname ).

    lo_column->set_long_text( iv_long_text ).

    IF iv_medium_text IS NOT INITIAL.
      lo_column->set_medium_text( iv_medium_text ).
    ENDIF.

    IF iv_short_text IS NOT INITIAL.
      lo_column->set_short_text( iv_short_text ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
