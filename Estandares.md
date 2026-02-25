# Estándares de nomenclatura para desarrollo ABAP ICASA

**Fecha:** 25/02/2026
**Versión:** V. 1.0

Un aspecto fundamental para todo desarrollador es establecer un estilo de programación claro y consistente. Existen numerosos estándares de programación que pueden aplicarse, pero es crucial adoptar uno que tenga en cuenta los siguientes principios:

- **Consistencia:** Utilizar de manera uniforme las mismas convenciones de nomenclatura a lo largo de toda la aplicación. Esto mejora la legibilidad y facilita la comprensión del código.

- **Mnemotecnia:** Facilitar la recordación de los nombres de los objetos de desarrollo. Unos nombres bien pensados permiten al programador identificar rápidamente el propósito de cada elemento.

- **Claridad:** El código debe ser comprensible tanto para el programador original como para cualquier persona que lo modifique en el futuro. Nombres sugerentes y bien estructurados permiten interpretar fácilmente el objetivo y la lógica del desarrollo.

A continuación, se detallan las reglas de notación y nomenclatura que deben ser seguidas durante la fase de implementación de una aplicación en ABAP.

## Nomenclatura para objetos de Workbench

### Programas Z

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| Z_<Módulo>_<Descripción> | Para programas finales de cliente. | Z_SD_REPORTE1 |

### Grupos de Funciones

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| ZGF_<Módulo>_<Descripción> | Para grupos finales de cliente | ZGF_MM_REPORTES |

### Módulo de Funciones

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| ZMF_<Módulo>_<Descripción> | Para funciones finales de cliente | ZMF_MM_REPORTES |

Los parámetros dentro de las funciones deben tener la siguiente convención:

| Pref | Tipo | Param | Tipo | Ejemplo |
| --- | --- | --- | --- | --- |
| I | Importing | T_ | Tabla interna | It_data |
| E | Exporting | S_ | Estructura | Is_mara<br>Es_mara |
| C | Changing | V_ | Campo | Iv_kunnr<br>Cv_datum |
|  |  | O_ | Objeto | O_data<br>Io_alv |
|  |  | IF_ | Interface | Eif_validate_data |

### Interfaces

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| ZIF_<Módulo>_<Descripción> | Para interfaces finales de cliente | ZIF_SD_ENVIO_PRECIOS |

### Clases

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| ZCL_<Módulo>_<Descripción> | Para clases finales de cliente | ZCL_SD_UTILITY |

#### Consideraciones

- Crear atributos privados o públicos read-only

- Crear métodos para modificar esos atributos

- Los parámetros deben tener la siguiente convención:

### Nombres para métodos dentro de clases:

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| GET_<Descripción> | Para los métodos de lectura | - GET_PO_BY_KEY |
| CREATE_<Descripción>, ADD_<Descripción>, INSERT_<Descripción>. | Para los métodos de creación se puede usar cualquier nomenclatura que identifique claramente la operación | - CREATE_PO<br>- INSERT_TICKET<br>- ADD_POS |
| UPDATE_<Descripción> | Para los métodos de modificar | - UPDATE_DATE |
| DELETE_<Descripción> | Para los métodos de borrar | - DELETE_ORDER |

### Formularios

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| ZSF_<Módulo>_<Descripción> | Para formularios de SmartForms | ZSF_SD_REPORT1 |
| ZAF_<Módulo>_<Descripción> | Para formularios de AdobeForms | ZAF_SD_REPORT2 |

### Objetos de Diccionario

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| Z<Módulo>T_ <Descripción> | Para tablas | ZPPT_audit |
| Z<Módulo>D_ <Descripción> | Para dominios | ZSDD_date |
| Z<Módulo>E_ <Descripción> | Para elementos de datos | ZMME_date |
| Z<Módulo>MC_ <Correlativo> | Para clase de mensaje | ZPPMC_001 |
| ZSTR_<Módulo>_<Descripción> | Estructuras simples | ZSTR_QM_mara |
| ZTT_<Módulo>_ <Descripción> | Tipo tabla | ZTT_FI_itab |
| ZRG_<Módulo>_ <Descripción> | Tipo rango | ZRG_FI_date |
| ZSH_<Módulo>_ <Descripción> | Ayuda de búsqueda | ZSH_SD_kunnr |

### Paquetes

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| Z<Módulo>_<Descripción> | Para paquetes finales | ZSD_MAIN |

## Nomenclatura para objetos locales de programa

| Nomenclatura | Descripción | Ejemplo |
| --- | --- | --- |
| Variable | lv_<Nombre> | gv_<Nombre> |
| Estructura | ls_<Nombre> | gs_<Nombre> |
| Tabla interna | lt_<Nombre> | gt_<Nombre> |
| Rango | lr_<Nombre> | gr_<Nombre> |
| Clase | lcl_<Nombre> |  |
| Objetos | o_<Nombre> | go_<Nombre> |
| Interfaces | lif_<Nombre> | gif_<Nombre> |
| Instancia de interfaz | if__<Nombre> | gif__<Nombre> |
| Tipo de dato | t__<Nombre> | t__<Nombre> |
| Tipo de tabla | tt_<Nombre> | tt_<Nombre> |
| Select-Options | S_<Nombre> |  |
| Parameters | P_<Nombre> |  |

