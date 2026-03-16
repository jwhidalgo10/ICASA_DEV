# Manual de Usuario – Transacciones con Archiving

## 1. Objetivo

Este manual explica, de forma simple, cómo probar las transacciones que ya incorporan consulta de información histórica mediante **Archiving**.

El objetivo de las pruebas es:
- validar que la transacción ejecute correctamente,
- revisar los resultados obtenidos,
- y comparar el comportamiento entre la versión original y la versión con soporte histórico, cuando aplique.

---

## 2. Escenarios de integración

En este alcance existen **tres formas** de integración de archiving:

### 2.1 Transacción original con check de histórico
Se mantiene la transacción original y se agrega un **check** para decidir si la consulta debe incluir información histórica.

**Uso esperado:**
- sin marcar el check → lógica original,
- marcando el check → lógica con apoyo de archiving.

---

### 2.2 Nueva transacción con sufijo `_ARC`
Se conserva la transacción original y se crea una **nueva transacción** con sufijo `_ARC`.

**Uso esperado:**
- transacción original → lógica habitual,
- transacción `_ARC` → lógica con histórico integrada.

Esto se usa normalmente cuando ya existe una solución en **programa + clase**, y se prefirió no modificar la clase original para no afectar ajustes futuros o soporte en producción.

---

### 2.3 SAP Query o reporte original transformado
Cuando la solución original era un **SAP Query** o un **reporte sin clase**, se dejó la transacción original sin cambios y se creó una nueva versión con sufijo `_ARC`.

En estos casos, la nueva transacción ya ejecuta una arquitectura nueva en **programa ABAP + clase**, preparada para consultar información activa e histórica.

**Uso esperado:**
- transacción original → comportamiento previo,
- transacción `_ARC` → versión reestructurada con histórico.

---

## 3. Transacciones disponibles

### 3.1 Transacciones con check de histórico

| Transacción | Nombre | Forma de uso |
|---|---|---|
| Z91_10031 | Reporte Anexo Factura Órdenes | Probar la misma transacción con el check desmarcado y luego marcado. |

---

### 3.2 Transacciones con sufijo `_ARC`

| Transacción original | Transacción con histórico | Nombre |
|---|---|---|
| Z01_10297 | Z01_10297_ARC | Diario de facturación con detalle de documentos |
| Z02_10245 | Z02_10245_ARC | Libro de Ventas Guatemala |

---

### 3.3 Transacciones transformadas desde SAP Query u otra solución original

| Transacción original | Transacción nueva | Nombre |
|---|---|---|
| Z00_00100001 | Z00_00100001_ARC | Fletes Facturados de TTACASA |
| Z03_00100005 | Z03_00100005_ARC | Visualizar reporte de trazabilidad de pedidos facturación versus salida de mercancía |

---

## 4. Cómo probar las transacciones

### 4.1 Caso 1: transacción con check de histórico
Para este tipo de transacción se recomienda:

1. Ejecutar la transacción con el **check desmarcado**.
2. Ejecutar nuevamente la transacción con el **check marcado**.
3. Comparar resultados.

**Qué se espera validar:**
- cantidad de registros,
- documentos recuperados,
- diferencias entre la lógica original y la lógica con histórico,
- consistencia general del reporte.

---

### 4.2 Caso 2: transacción original vs transacción `_ARC`
Para este tipo de transacción se recomienda:

1. Ejecutar la **transacción original**.
2. Ejecutar la **transacción con sufijo `_ARC`**.
3. Comparar resultados entre ambas.

**Qué se espera validar:**
- que la transacción `_ARC` ejecute correctamente,
- que la información histórica se recupere cuando corresponda,
- y que la lógica original permanezca sin afectación.

---

### 4.3 Caso 3: transacción transformada desde SAP Query
Para este tipo de transacción se recomienda:

1. Ejecutar la **transacción original**.
2. Ejecutar la **nueva transacción `_ARC`**.
3. Comparar resultados y comportamiento general.

**Importante:**  
Aunque internamente la solución fue reestructurada, desde el punto de vista del usuario funcional el objetivo sigue siendo el mismo: consultar el reporte y validar la información obtenida.

---

## 5. Parámetro de fecha para información histórica

El sistema utiliza la variable de TVARVC:

- `ZARCH_CUTOFF_DATE`

Esta fecha se usa como referencia interna para determinar cuándo una consulta debe apoyarse en información archivada.

**Importante para el usuario:**
- esta variable no forma parte de la operación normal del reporte,
- y no requiere mantenimiento por parte del usuario final.

---

## 6. Qué validar durante las pruebas

Durante la ejecución de las transacciones, se recomienda validar al menos lo siguiente:

- que la transacción ejecute sin error,
- que el resultado mostrado sea consistente con los filtros ingresados,
- que se recuperen los documentos esperados,
- que existan diferencias razonables cuando se consulta con histórico,
- y que la versión original siga funcionando correctamente cuando aplique.

Si se detectan diferencias, conviene registrar:
- transacción probada,
- filtros utilizados,
- resultado observado,
- y evidencia de pantalla.

---

