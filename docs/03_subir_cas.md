# `03_subir_cas.sas` — Carga a CAS

Script corto para llevar la tabla `ej2_abt_pca` (ABT reducida con componentes principales) a la memoria de **SAS Viya / CAS**,
de donde se puede usar en Model Studio o en otros procedimientos CAS.

| Sentencia | Función |
|---|---|
| `libname prep "<ruta>/preparacion_proyecto";` | Apunta a la carpeta con las tablas permanentes generadas por los scripts 01 y 02. |
| `cas;` | Inicia una sesión CAS. |
| `proc casutil; load data=prep.ej2_abt_pca outcaslib="CASUSER" casout="ej2_abt_pca" promote;` | Carga la tabla en la caslib `CASUSER` y la **promueve** (queda a nivel global de la sesión/caslib en lugar de sólo en la sesión). |

> Si `ej2_abt_pca` ya está promovida en CASUSER, `promote` marcará error; elimínala antes con `proc casutil; droptable casdata="ej2_abt_pca" incaslib="CASUSER"; quit;`.
