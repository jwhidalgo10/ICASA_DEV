*&---------------------------------------------------------------------*
*& Report ZBP_AUDIT_LOG_REPORT
*&---------------------------------------------------------------------*
*& BP Audit Log Viewer
*&---------------------------------------------------------------------*
REPORT zbp_audit_log_report.

" -----------------------------------------------------------------------
" Type Definitions
" -----------------------------------------------------------------------
TYPES: BEGIN OF ty_row,
         log_id         TYPE zbp_audit_hdr-log_id,
         execution_date TYPE zbp_audit_hdr-execution_date,
         execution_time TYPE zbp_audit_hdr-execution_time,
         username       TYPE zbp_audit_hdr-username,
         is_simulation  TYPE zbp_audit_hdr-is_simulation,
         total_bp       TYPE zbp_audit_hdr-total_bp,
         total_errors   TYPE zbp_audit_hdr-total_errors,
         total_success  TYPE zbp_audit_hdr-total_success,
         total_warnings TYPE zbp_audit_hdr-total_warnings,
         partner        TYPE zbp_audit_itm-partner,
         field_name     TYPE zbp_audit_itm-field_name,
         old_value      TYPE zbp_audit_itm-old_value,
         new_value      TYPE zbp_audit_itm-new_value,
         status         TYPE zbp_audit_itm-status,
         message        TYPE zbp_audit_itm-message,
         created_at     TYPE zbp_audit_itm-created_at,
       END OF ty_row,
       tt_row TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.

" -----------------------------------------------------------------------
" Data Declarations
" -----------------------------------------------------------------------
DATA gt_data TYPE tt_row.
DATA go_alv  TYPE REF TO cl_salv_table.
TABLES : zbp_audit_hdr, zbp_audit_itm.
" -----------------------------------------------------------------------
" Selection Screen
" -----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-t01.
  SELECT-OPTIONS s_date FOR zbp_audit_hdr-execution_date OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-t02.
  PARAMETERS p_user TYPE syuname DEFAULT sy-uname.
  SELECT-OPTIONS: s_partne FOR zbp_audit_itm-partner,
                  s_status FOR zbp_audit_itm-status.
  PARAMETERS p_sim AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.



" -----------------------------------------------------------------------
" Selection Screen Texts
" -----------------------------------------------------------------------
INITIALIZATION.
  " TEXT-t01 = 'Date Range (Required)'.
  " TEXT-t02 = 'Optional Filters'.

  " -----------------------------------------------------------------------
  " Main Processing
  " -----------------------------------------------------------------------
START-OF-SELECTION.
  PERFORM get_audit_data.
  PERFORM display_alv.

  " -----------------------------------------------------------------------
  " Get Audit Data
  " -----------------------------------------------------------------------
FORM get_audit_data.
  SELECT h~log_id,
         h~execution_date,
         h~execution_time,
         h~username,
         h~is_simulation,
         h~total_bp,
         h~total_errors,
         h~total_success,
         h~total_warnings,
         i~partner,
         i~field_name,
         i~old_value,
         i~new_value,
         i~status,
         i~message,
         i~created_at
    FROM zbp_audit_hdr AS h
           INNER JOIN
             zbp_audit_itm AS i ON i~log_id = h~log_id
    WHERE h~execution_date IN @s_date
      AND ( @p_sim  = @abap_false OR h~is_simulation = 'X' )
      AND ( @p_sim  IS INITIAL OR h~is_simulation = @p_sim )
      AND i~partner IN @s_partne
      AND i~status  IN @s_status
    ORDER BY h~execution_date DESCENDING,
             h~execution_time DESCENDING,
             h~log_id,
             i~partner,
             i~field_name
    INTO CORRESPONDING FIELDS OF TABLE @gt_data.

  IF gt_data IS INITIAL.
    MESSAGE 'No audit log entries found for the selected criteria' TYPE 'I'. "#EC NOTEXT


    LEAVE LIST-PROCESSING.
  ENDIF.
ENDFORM.

" -----------------------------------------------------------------------
" Display ALV
" -----------------------------------------------------------------------
FORM display_alv.
  DATA lx_msg TYPE REF TO cx_salv_msg.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = go_alv
                              CHANGING  t_table      = gt_data ).

      " Enable all standard functions
      go_alv->get_functions( )->set_all( abap_true ).

      " Optimize column width
      go_alv->get_columns( )->set_optimize( abap_true ).

      " Set column texts
      PERFORM set_column_texts.

      " Display
      go_alv->display( ).

    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg TYPE 'I' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

" -----------------------------------------------------------------------
" Set Column Texts
" -----------------------------------------------------------------------
" -----------------------------------------------------------------------
" Set Column Texts
" -----------------------------------------------------------------------
FORM set_column_texts.
  DATA lo_columns TYPE REF TO cl_salv_columns_table.
  DATA lo_column  TYPE REF TO cl_salv_column_table.

  lo_columns = go_alv->get_columns( ).

  TRY.
      lo_column ?= lo_columns->get_column( 'LOG_ID' ).
      lo_column->set_short_text( 'Log ID' ).                    "#EC NOTEXT
      lo_column->set_medium_text( 'Log ID' ).                   "#EC NOTEXT
      lo_column->set_long_text( 'Log Identifier' ).             "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'EXECUTION_DATE' ).
      lo_column->set_short_text( 'Date' ).                      "#EC NOTEXT
      lo_column->set_medium_text( 'Exec. Date' ).               "#EC NOTEXT
      lo_column->set_long_text( 'Execution Date' ).             "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'EXECUTION_TIME' ).
      lo_column->set_short_text( 'Time' ).                      "#EC NOTEXT
      lo_column->set_medium_text( 'Exec. Time' ).               "#EC NOTEXT
      lo_column->set_long_text( 'Execution Time' ).             "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'USERNAME' ).
      lo_column->set_short_text( 'User' ).                      "#EC NOTEXT
      lo_column->set_medium_text( 'Username' ).                 "#EC NOTEXT
      lo_column->set_long_text( 'User Name' ).                  "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'IS_SIMULATION' ).
      lo_column->set_short_text( 'Sim' ).                       "#EC NOTEXT
      lo_column->set_medium_text( 'Simulation' ).               "#EC NOTEXT
      lo_column->set_long_text( 'Is Simulation' ).              "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'TOTAL_BP' ).
      lo_column->set_short_text( 'Tot BP' ).                    "#EC NOTEXT
      lo_column->set_medium_text( 'Total BP' ).                 "#EC NOTEXT
      lo_column->set_long_text( 'Total Business Partners' ).    "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'TOTAL_ERRORS' ).
      lo_column->set_short_text( 'Errors' ).                    "#EC NOTEXT
      lo_column->set_medium_text( 'Total Errors' ).             "#EC NOTEXT
      lo_column->set_long_text( 'Total Errors' ).               "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'TOTAL_SUCCESS' ).
      lo_column->set_short_text( 'Success' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'Total Success' ).            "#EC NOTEXT
      lo_column->set_long_text( 'Total Successful' ).           "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'TOTAL_WARNINGS' ).
      lo_column->set_short_text( 'Warnings' ).                  "#EC NOTEXT
      lo_column->set_medium_text( 'Total Warn.' ).              "#EC NOTEXT
      lo_column->set_long_text( 'Total Warnings' ).             "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'PARTNER' ).
      lo_column->set_short_text( 'Partner' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'BP Number' ).                "#EC NOTEXT
      lo_column->set_long_text( 'Business Partner' ).           "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'FIELD_NAME' ).
      lo_column->set_short_text( 'Field' ).                     "#EC NOTEXT
      lo_column->set_medium_text( 'Field Name' ).               "#EC NOTEXT
      lo_column->set_long_text( 'Field Name' ).                 "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'OLD_VALUE' ).
      lo_column->set_short_text( 'Old Val' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'Old Value' ).                "#EC NOTEXT
      lo_column->set_long_text( 'Old Value' ).                  "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'NEW_VALUE' ).
      lo_column->set_short_text( 'New Val' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'New Value' ).                "#EC NOTEXT
      lo_column->set_long_text( 'New Value' ).                  "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'STATUS' ).
      lo_column->set_short_text( 'Stat' ).                      "#EC NOTEXT
      lo_column->set_medium_text( 'Status' ).                   "#EC NOTEXT
      lo_column->set_long_text( 'Status' ).                     "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'MESSAGE' ).
      lo_column->set_short_text( 'Message' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'Message' ).                  "#EC NOTEXT
      lo_column->set_long_text( 'Message Text' ).               "#EC NOTEXT

      lo_column ?= lo_columns->get_column( 'CREATED_AT' ).
      lo_column->set_short_text( 'Created' ).                   "#EC NOTEXT
      lo_column->set_medium_text( 'Created At' ).               "#EC NOTEXT
      lo_column->set_long_text( 'Creation Timestamp' ).         "#EC NOTEXT

    CATCH cx_salv_not_found.
      " Column not found - ignore
  ENDTRY.
ENDFORM.
