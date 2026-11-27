# `01_preparacion_abt.sas` — Preparación de datos

Construye la ABT (tabla analítica a nivel persona), define el `TARGET`, particiona y limpia los datos.
Todas las tablas permanentes se guardan en la librería **`t2`** (`<ruta>/preparacion_proyecto`).

## 0. Configuración

| Elemento | Descripción |
|---|---|
| `%let ruta, f_obs, f_des, ruta_resultados` | Rutas de los CSV y de la carpeta de resultados. |
| `%let otorgante = nobancario` | Otorgante del equipo; se usa para filtrar créditos de 2018. |
| `%let corte_obs = 30DEC2017` | Fecha de corte de la ventana de observación. |
| `%let semilla = 12345` | Reproducibilidad de la partición. |
| `options dlcreatedir; libname t2 ...` | Crea la carpeta si no existe y asigna la librería `t2`. |
| `ods graphics on; title; footnote;` | Habilita gráficos y limpia títulos. |

## Macros definidas

| Macro | Parámetros | Qué hace |
|---|---|---|
| `%verificar_archivos` | — | Comprueba con `fileexist` que existan ambos CSV; si no, escribe `ERROR` y detiene con `%abort cancel`. |
| `%exigir(verdad, mensaje)` | condición, texto | **Aserción**: si la condición es falsa, escribe `ERROR: mensaje` y aborta. Se usa para validar la ABT, la partición y la limpieza. |
| `%resumen(tabla, salida)` | tabla de entrada, tabla de salida | Ordena por `particion` y corre `PROC MEANS` (n, nmiss, mean, std, median) sobre `&entradas.`; guarda el resumen con ODS en `salida`. |
| `%exportar(tabla)` | nombre de tabla en `t2` | `PROC EXPORT` a CSV en `&ruta_resultados.` (se llama para `abt_modeler`, `diagnostico_predictores`, `resumen_imputacion`, `resumen_estandarizacion`). |

## 1. Lectura de los CSV

`DATA step` con `INFILE ... dsd firstobs=2 truncover lrecl=32767` (no `PROC IMPORT`) porque `historico` debe quedar como **texto**
(contiene `X` y `U`). Se genera `t2.creditos_obs` y `t2.creditos_des` con el mismo esquema:

- Fechas leídas con `ddmmyy10.` y mostradas con `date9.`.
- `historico = compress(historico, '0D'x)` quita el retorno de carro (`\r`) de los CSV con fin de línea Windows.
- `otorgante = lowcase(strip(otorgante))` normaliza el texto.

**Control de lectura:** `PROC SQL` con `UNION ALL` cuenta créditos, personas distintas y fechas de apertura faltantes por base.

## 2. Parte A — Variables explicativas (base de observación 2017)

### Ejercicio 1 → `t2.parte_a_credito` (nivel crédito)

| Variable | Definición |
|---|---|
| `tiempo_en_libros` | Número de meses con movimiento reportado = longitud de `historico`. |
| `antiguedad` | Meses entre `fecha_apertura` y `min(fecha_cierre, fecha_corte)` (`intck('month',…)`). Missing si apertura es faltante, posterior al corte, o si cierre < apertura. |
| `credito` (limpieza) | El valor centinela `404040404` se convierte en missing. |
| `pct_utilizacion` | `saldo / credito * 100` si `credito > 0` y `saldo >= 0`. |
| `imor` | Índice de morosidad (CNBV): `saldo_vencido / saldo * 100` si `saldo > 0` y `saldo_vencido >= 0`. |
| `peor_6/12/18/24_meses` | Peor modo de pago (máximo) entre las primeras 6/12/18/24 posiciones de `historico`. Sólo cuentan los caracteres `1,2,3,4,5,6,7,9`; `0`, `X` y `U` se ignoran. |

El cálculo del peor MOP es un lazo `do i = 1 to 24` que acumula `w = max(w, valor)` y guarda `w` al llegar a 6, 12, 18 y 24.

### Ejercicio 2 → `t2.abt_parte_a` (nivel persona)

`PROC SORT` por `id` y `PROC MEANS ... output ... min= p5= p25= median= p75= p95= max= mean= mode= std= / autoname`.
Son **10 estadísticos × 8 variables = 80 variables** por persona (más `id`). Un `PROC SQL` verifica el número de personas y de columnas.

## 3. Parte B — Variable objetivo (base de desempeño 2018)

| Ejercicio | Tabla | Qué hace |
|---|---|---|
| 3 | `t2.cred_sel` | `PROC FREQ` de otorgantes y selección de los créditos cuyo otorgante (sin espacios/`_`/`-`) es `&otorgante.` y con `id` no missing. |
| 4 | `t2.cred_sel_mop` | Calcula `peor_mop_12` por crédito (máximo MOP en las primeras 12 posiciones de `historico`) y muestra su distribución. |
| 5 | `t2.target_sel` | Por persona: `target = 1` si `max(peor_mop_12) >= 4`; `0` si tiene al menos un valor válido y ninguno ≥ 4; missing si no tiene información. |
| 6 | `t2.abt_risk` | `INNER JOIN` de `abt_parte_a` con `target_sel` (sólo `target in (0,1)`). Es la ABT con 80 predictores + `target`. Reporta personas y tasa de `target`. |

Después se arma la macrovariable `&vars` (columnas numéricas de `ABT_RISK` excepto `ID` y `TARGET`, leídas de `dictionary.columns`) y `&nv`.

## 4. Partición entrenamiento / validación

1. Valida con `%exigir` que la ABT no esté vacía, que haya un solo registro por `id` y ≥ 10 eventos y ≥ 10 no-eventos.
2. `PROC SURVEYSELECT method=srs samprate=0.70 seed=&semilla outall; strata target;` → muestreo **estratificado por TARGET** (70 % entrenamiento).
3. `work.entrena` (`particion=1`) y `work.valida` (`particion=0`).

## 5. Limpieza (siempre ajustando con entrenamiento y aplicando a validación)

| Paso | Qué hace | Salida |
|---|---|---|
| **Limpieza 1** — diagnóstico | `PROC MEANS n nmiss std` en entrenamiento. Descarta predictores con **> 50 % de faltantes** o **desviación estándar = 0**. | `t2.diagnostico_predictores` (variable, n, nmiss, pct_missing, conservar, motivo); macrovariable `&entradas` |
| **Limpieza 2** — imputación | `PROC STDIZE reponly method=median` en entrenamiento (guarda medianas con `outstat`) y se aplican esas mismas medianas a validación con `method=in(...)`. | `t2.medianas_train`, `t2.resumen_imputacion` |
| **Limpieza 3** — estandarización | `PROC STDIZE method=std` (z-score) en entrenamiento; parámetros reutilizados en validación. | `t2.parametros_z`, `t2.resumen_estandarizacion` |

Ajustar los parámetros sólo con entrenamiento evita **fuga de información** (*data leakage*) hacia validación.

## 6. Salida final

`t2.abt_modeler` = `id`, `target`, `particion` + predictores conservados, imputados y estandarizados.
Se validan con `%exigir`: una fila por `id` y **cero faltantes** en los predictores finales. Finalmente `%exportar` genera los CSV
`abt_modeler.csv`, `diagnostico_predictores.csv`, `resumen_imputacion.csv` y `resumen_estandarizacion.csv`.
