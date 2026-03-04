*&---------------------------------------------------------------------*
*& Report ZBP_AUDIT_REPORT
*&---------------------------------------------------------------------*
*& Business Partner Audit Report - OO Implementation
*&---------------------------------------------------------------------*
REPORT zbp_audit_report.

TABLES zbp_but000_sim.

" -----------------------------------------------------------------------
" Selection Screen
" -----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS s_partne FOR zbp_but000_sim-partner.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS p_bptype TYPE char3 AS LISTBOX VISIBLE LENGTH 20 DEFAULT 'ALL'. "#EC NOTEXT
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
  PARAMETERS: p_sim TYPE abap_bool AS CHECKBOX DEFAULT abap_true,
              p_err TYPE abap_bool AS CHECKBOX DEFAULT abap_false.
SELECTION-SCREEN END OF BLOCK b3.

" -----------------------------------------------------------------------
" Application Class
" -----------------------------------------------------------------------
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES ty_bp_type TYPE char3.

    CLASS-METHODS run.
    CLASS-METHODS setup_listbox.

    METHODS constructor
      IMPORTING is_sel      TYPE zif_bp_processor=>ty_sel
                iv_bp_type  TYPE ty_bp_type
                iv_err_only TYPE abap_bool.

  PRIVATE SECTION.
    CONSTANTS gc_bp_type_all  TYPE char3 VALUE 'ALL'. "#EC NOTEXT
    CONSTANTS gc_bp_type_per  TYPE char3 VALUE 'PER'. "#EC NOTEXT
    CONSTANTS gc_bp_type_org  TYPE char3 VALUE 'ORG'. "#EC NOTEXT

    CONSTANTS gc_status_green TYPE char1 VALUE 'G'. "#EC NOTEXT
    CONSTANTS gc_status_red   TYPE char1 VALUE 'R'. "#EC NOTEXT

    DATA ms_sel      TYPE zif_bp_processor=>ty_sel.
    DATA mt_alv      TYPE zif_bp_processor=>tt_alv.
    DATA mt_issues   TYPE zif_bp_processor=>tt_issue.
    DATA mv_bp_type  TYPE ty_bp_type.
    DATA mv_err_only TYPE abap_bool.

    METHODS execute.

    METHODS apply_filters
      CHANGING ct_alv TYPE zif_bp_processor=>tt_alv.

    METHODS filter_errors_only
      CHANGING ct_alv TYPE zif_bp_processor=>tt_alv.

    METHODS filter_by_bp_type
      CHANGING ct_alv TYPE zif_bp_processor=>tt_alv.

    METHODS display_results.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA(ls_sel) = VALUE zif_bp_processor=>ty_sel( partner_range = s_partne[]
                                                   is_simulation = p_sim ).

    DATA(lo_app) = NEW lcl_app( is_sel      = ls_sel
                                iv_bp_type  = p_bptype
                                iv_err_only = p_err ).

    lo_app->execute( ).
    lo_app->display_results( ).
  ENDMETHOD.

  METHOD setup_listbox.
    DATA lt_values TYPE vrm_values.

    lt_values = VALUE #( ( key = gc_bp_type_all text = 'Todos' )        "#EC NOTEXT
                         ( key = gc_bp_type_per text = 'Persona' )      "#EC NOTEXT
                         ( key = gc_bp_type_org text = 'Organización' ) ). "#EC NOTEXT

    CALL FUNCTION 'VRM_SET_VALUES'
      EXPORTING id     = 'P_BPTYPE'                              "#EC NOTEXT
                values = lt_values.
  ENDMETHOD.

  METHOD constructor.
    ms_sel      = is_sel.
    mv_bp_type  = iv_bp_type.
    mv_err_only = iv_err_only.
  ENDMETHOD.

  METHOD execute.
    DATA lo_processor TYPE REF TO zif_bp_processor.

    lo_processor = NEW zcl_bp_processor( ).

    lo_processor->process( EXPORTING is_sel    = ms_sel
                           IMPORTING rt_alv    = mt_alv
                                     rt_issues = mt_issues ).
  ENDMETHOD.

  METHOD apply_filters.
    IF mv_bp_type <> gc_bp_type_all.
      filter_by_bp_type( CHANGING ct_alv = ct_alv ).
    ENDIF.

    IF mv_err_only = abap_true.
      filter_errors_only( CHANGING ct_alv = ct_alv ).
    ENDIF.
  ENDMETHOD.

  METHOD filter_errors_only.
    ct_alv = VALUE #( FOR <alv> IN ct_alv
                      WHERE ( errors > 0 OR status = gc_status_red )
                      ( <alv> ) ).
  ENDMETHOD.

  METHOD filter_by_bp_type.
    DATA lt_filtered TYPE zif_bp_processor=>tt_alv.

    LOOP AT ct_alv ASSIGNING FIELD-SYMBOL(<alv>).
      DATA(lv_bp_type_alv) = <alv>-bp_type.
      IF lv_bp_type_alv = mv_bp_type.
        APPEND <alv> TO lt_filtered.
      ENDIF.
    ENDLOOP.

    ct_alv = lt_filtered.
  ENDMETHOD.

  METHOD display_results.
    IF mt_alv IS INITIAL.
      MESSAGE 'No se encontraron registros con los criterios seleccionados' TYPE 'I'. "#EC NOTEXT
      RETURN.
    ENDIF.

    TRY.
        zcl_bp_alv_presenter=>display( it_alv_summary = mt_alv
                                       it_issues      = mt_issues
                                       iv_bp_type     = mv_bp_type    " <- AGREGAR
                                       iv_err_only    = mv_err_only ). " <- AGREGAR
      CATCH cx_salv_msg
            cx_salv_not_found INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

" -----------------------------------------------------------------------
" Initialization
" -----------------------------------------------------------------------
INITIALIZATION.
  " Empty - reserved for future initialization logic

  " -----------------------------------------------------------------------
  " Selection Screen Events
  " -----------------------------------------------------------------------
AT SELECTION-SCREEN OUTPUT.
  lcl_app=>setup_listbox( ).

  " -----------------------------------------------------------------------
  " Main Execution
  " -----------------------------------------------------------------------
START-OF-SELECTION.
  lcl_app=>run( ).
