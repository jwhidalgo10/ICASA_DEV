# Paquete $ZJH_COPILOT

## Descripción General

Este paquete contiene un sistema completo de validación y auditoría de Business Partners desarrollado en ABAP con sintaxis moderna (7.40+). El sistema permite validar, normalizar y corregir datos de Business Partners (NIT, DPI, email, teléfono) con un registro completo de auditoría.

## Arquitectura

El paquete implementa una arquitectura orientada a objetos con separación de responsabilidades:

### Interfaces

- **ZIF_BP_VALIDATOR**: Contrato de validación para campos de BPs
- **ZIF_BP_PROCESSOR**: Interfaz principal del procesador de auditoría
- **ZIF_BP_PERSISTENCE**: Gestiona la persistencia de cambios
- **ZIF_BP_AUDIT_LOGGER**: Maneja el registro de auditoría

### Clases Principales

#### Validadores
- **ZCL_BP_VALIDATOR**: Coordinador de validaciones (Patrón Singleton)
- **ZCL_BP_NITVALIDATOR**: Validador de NIT para organizaciones
- **ZCL_BP_DPIVALIDATOR**: Validador de DPI para personas
- **ZCL_BP_CONTACTVALIDATOR**: Validador de email y teléfono

#### Procesamiento
- **ZCL_BP_PROCESSOR**: Orquestador principal del flujo de validación
- **ZCL_BP_READER**: Lector de datos desde zbp_but000_sim
- **ZCL_BP_TABLE_UPDATER**: Aplicador de correcciones con control transaccional

#### Presentación y Auditoría
- **ZCL_BP_ALV_PRESENTER**: Generador de ALV con semáforo visual
- **ZCL_BP_AUDIT_LOGGER**: Logger de auditoría con UUID único

### Programas

1. **ZBP_AUDIT_REPORT**: Reporte principal de auditoría de BPs (OO)
   - Permite filtrar por tipo de BP (PER/ORG/ALL)
   - Modo simulación o aplicación real de cambios
   - Filtro de solo errores

2. **ZBP_AUDIT_LOG_REPORT**: Visor de logs de auditoría
   - Consulta histórica de ejecuciones
   - Filtros por fecha, usuario, partner, status
   - JOIN entre zbp_audit_hdr y zbp_audit_itm

3. **ZBP_LOAD_BUT000_SIM**: Programa de carga de datos de prueba
   - Genera 20 registros con casos válidos, normalizables y erróneos
   - Clasificación automática mediante validadores reales
   - Útil para testing y demos

4. **ZOLD_CUSTOMER_REPORT_JH**: Reporte ejemplo de clientes (Patrón MVC)

## Características Principales

### Validación Multi-nivel
- **NIT**: Formato con guión, dígito verificador K, normalización de puntos/espacios
- **DPI**: 13 dígitos, eliminación de guiones y espacios
- **Email**: Validación de estructura (@, dominio con punto), normalización a minúsculas
- **Teléfono**: Formato guatemalteco (+502 + 8 dígitos)

### Severidades
- **E (Error)**: Formato inválido que impide normalización
- **W (Warning)**: Normalización aplicada o campo vacío
- **S (Success)**: Campo válido sin cambios

### Control Transaccional
- COMMIT por Business Partner si todos los campos se actualizan correctamente
- ROLLBACK completo de un BP si falla cualquier campo
- Log detallado de cada operación

### Auditoría Completa
- Header log (zbp_audit_hdr): UUID, fecha/hora, usuario, modo, totales
- Detail log (zbp_audit_itm): Campo actualizado, valores old/new, status, mensaje
- Resumen estadístico al finalizar

## Tablas de Base de Datos

- **zbp_but000_sim**: Tabla de simulación de Business Partners
- **zbp_audit_hdr**: Cabecera de logs de auditoría
- **zbp_audit_itm**: Detalle de items de auditoría

## Buenas Prácticas Implementadas

### Sintaxis Moderna ABAP 7.40+
- Uso extensivo de `DATA(...)` y `FIELD-SYMBOL(...)`
- Constructor de valores `VALUE #( ... )`
- Expresiones de tabla `lt_data[ ... ]`
- Operadores lógicos `SWITCH #( ... )` y `COND #( ... )`

### Patrones de Diseño
- **Singleton**: Reutilización de instancias de validadores
- **Strategy**: Diferentes validadores intercambiables
- **Template Method**: Flujo común de procesamiento
- **MVC**: Separación modelo/vista/controlador en reportes

### Nomenclatura Consistente
- `lv_`: Variables locales
- `lt_`: Tablas internas
- `ls_`: Estructuras
- `lo_`: Objetos/instancias de clases

### Documentación
- ABAP Doc completo en todas las clases e interfaces
- Comentarios descriptivos en código complejo
- Texto explicativo en pantallas de selección

## Uso Básico

### 1. Cargar Datos de Prueba
```abap
" Ejecutar ZBP_LOAD_BUT000_SIM
" Marcar: p_del = X, p_commit = X
```

### 2. Ejecutar Auditoría
```abap
" Ejecutar ZBP_AUDIT_REPORT
" Seleccionar rango de partners
" Elegir: Simulación = X (primero para ver issues)
" Revisar ALV con semáforos
```

### 3. Aplicar Correcciones
```abap
" Ejecutar ZBP_AUDIT_REPORT
" Simulación = ' ' (vacío)
" Las correcciones se aplican a la base de datos
```

### 4. Consultar Logs
```abap
" Ejecutar ZBP_AUDIT_LOG_REPORT
" Filtrar por fecha de ejecución
" Ver detalle de cada cambio aplicado
```

## Extensibilidad

El sistema está diseñado para ser fácilmente extensible:

1. **Nuevos Validadores**: Implementar ZIF_BP_VALIDATOR
2. **Nuevos Campos**: Agregar a ty_bp y crear validador específico
3. **Nuevas Reglas**: Modificar validadores existentes sin afectar flujo principal
4. **Nuevos Reportes**: Reutilizar clases de procesamiento y presentación

## Requisitos del Sistema

- SAP NetWeaver 7.40 o superior (por sintaxis moderna)
- Tabla zbp_but000_sim creada
- Tablas de auditoría zbp_audit_hdr y zbp_audit_itm creadas

## Autor

Desarrollado como parte del package $ZJH_COPILOT

## Licencia

Uso interno - ICASA DEV
