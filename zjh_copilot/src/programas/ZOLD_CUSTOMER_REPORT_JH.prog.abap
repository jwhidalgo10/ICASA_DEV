*&---------------------------------------------------------------------*
*& Report zold_customer_report_jh
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zold_customer_report_jh.

" Clase modelo para manejar los datos de clientes
CLASS zcl_customer_model DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_customer,
             kunnr TYPE kna1-kunnr,
             name1 TYPE kna1-name1,
             ort01 TYPE kna1-ort01,
           END OF ty_customer.

    TYPES: tt_customer TYPE TABLE OF ty_customer WITH EMPTY KEY.

    METHODS: get_customers IMPORTING iv_kunnr            TYPE kna1-kunnr OPTIONAL
                           RETURNING VALUE(rt_customers) TYPE tt_customer.
ENDCLASS.

CLASS zcl_customer_model IMPLEMENTATION.
  METHOD get_customers.
    SELECT kunnr, name1, ort01
      FROM kna1
      WHERE kunnr = @iv_kunnr OR @iv_kunnr IS INITIAL
      INTO TABLE @rt_customers.
  ENDMETHOD.
ENDCLASS.

" Clase vista para mostrar los datos en ALV
CLASS zcl_customer_view DEFINITION.
  PUBLIC SECTION.
    METHODS: display_customers IMPORTING it_customers TYPE zcl_customer_model=>tt_customer
                               RAISING   cx_salv_msg.
ENDCLASS.

CLASS zcl_customer_view IMPLEMENTATION.
  METHOD display_customers.
    DATA lo_alv TYPE REF TO cl_salv_table.
    DATA lt_table TYPE zcl_customer_model=>tt_customer.
    lt_table = it_customers.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_table ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

" Clase controlador para coordinar modelo y vista
CLASS zcl_customer_controller DEFINITION.
  PUBLIC SECTION.
    METHODS: run RAISING cx_salv_msg.
ENDCLASS.

CLASS zcl_customer_controller IMPLEMENTATION.
  METHOD run.
    DATA lo_model TYPE REF TO zcl_customer_model.
    DATA lo_view TYPE REF TO zcl_customer_view.
    DATA lt_customers TYPE zcl_customer_model=>tt_customer.

    lo_model = NEW zcl_customer_model( ).
    lo_view = NEW zcl_customer_view( ).

    " Obtener datos del modelo
    lt_customers = lo_model->get_customers( ).

    " Mostrar datos en la vista
    lo_view->display_customers( lt_customers ).
  ENDMETHOD.
ENDCLASS.

" Programa principal

START-OF-SELECTION.
  DATA(lo_controller) = NEW zcl_customer_controller( ).
  TRY.
    lo_controller->run( ).
  CATCH cx_salv_msg INTO DATA(lo_exception).
    MESSAGE lo_exception->get_text( ) TYPE 'E'.
  ENDTRY.
