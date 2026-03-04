"! <p class="shorttext synchronized">Interfaz para validación de Business Partners</p>
"! Define el contrato de validación para campos de BPs: NIT, DPI, email, teléfono.
"! Retorna issues con severidad E/W y propuestas de corrección normalizadas.
INTERFACE zif_bp_validator
  PUBLIC.

  " Estructura de datos de Business Partner a validar
  TYPES: BEGIN OF ty_bp,
           partner TYPE string, " Business Partner ID
           bp_type TYPE string, " PER=Persona, ORG=Organización
           nit     TYPE string, " NIT (solo para ORG)
           dpi     TYPE string, " DPI (solo para PER)
           email   TYPE string, " Correo electrónico
           phone   TYPE string, " Número telefónico
         END OF ty_bp.
  TYPES: tt_bp TYPE STANDARD TABLE OF ty_bp WITH EMPTY KEY.

  " Estructura de issue detectado en validación
  TYPES: BEGIN OF ty_issue,
           partner        TYPE string, " BP afectado
           field_name     TYPE string, " Campo con problema (NIT, DPI, EMAIL, PHONE)
           severity       TYPE string, " E=Error, W=Warning
           message        TYPE string, " Descripción del problema
           original_value TYPE string, " Valor actual del campo
           proposed_value TYPE string, " Valor normalizado/corregido propuesto
         END OF ty_issue.


  TYPES: tt_issue TYPE STANDARD TABLE OF ty_issue WITH EMPTY KEY.

  "! <p class="shorttext synchronized">Valida campos de un Business Partner</p>
  "! Ejecuta validaciones según bp_type: NIT (ORG), DPI (PER), contacto (ambos).
  "! Normaliza formatos: NIT sin guiones, DPI con guiones válidos, email lowercase, teléfono estandarizado.
  "!
  "! @parameter is_bp | Business Partner a validar (partner, bp_type, campos a validar)
  "! @parameter rt_issues | Issues detectados: campo, severidad E/W, mensaje, valor original/propuesto
  METHODS validate
    IMPORTING
      is_bp              TYPE ty_bp
    RETURNING
      VALUE(rt_issues) TYPE tt_issue.

ENDINTERFACE.
