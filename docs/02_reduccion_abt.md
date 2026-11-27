# `02_reduccion_abt.sas` — Reducción de dimensión y comparación de modelos

Compara tres conjuntos de entradas para una **regresión logística** que predice `TARGET`:

| Método | Entradas |
|---|---|
| **Limpia** | Todos los predictores de `abt_modeler` (`&n_limpia`). |
| **PCA** | Los primeros *k* componentes principales (*k* = menor número que alcanza ≥ 80 % de varianza acumulada). |
| **Clusters** | *k* variables representantes, una por cada cluster de `PROC VARCLUS` (mismo presupuesto *k* que PCA). |

Todos los ajustes usan **sólo entrenamiento** (`particion=1`) y se evalúan en **validación** (`particion=0`).

## Configuración

`%let carpeta` (ruta de `t2`), `%let meta_pca = 0.80`, `libname t2 "&carpeta."`.

## Macros

| Macro | Parámetros | Qué hace |
|---|---|---|
| `%comprobar` | — | Verifica que exista `t2.abt_modeler`; si no, aborta pidiendo ejecutar primero el script 01. |
| `%comparar` | — | Orquesta la comparación: puntúa con PCA, hace VARCLUS, elige representantes, construye las tres ABT y llama a `%score_log` para cada método. |
| `%score_log(tabla, variables, metodo)` | tabla de entrada, lista de variables, etiqueta | Ajusta `PROC LOGISTIC` (`target(event='1')`) en entrenamiento (`outmodel`), puntúa validación con `inmodel` + `score` y deja `work.ej2_score_<metodo>` con `modelo`, `id`, `target`, `p` (= `P_1`). |
| `%roc_ks(entrada, salida, puntos)` | tabla de scores, tabla de métricas, tabla de puntos ROC | Calcula **AUC** (regla del trapecio sobre la curva ROC) y **KS** (`max |TPR − FPR|`) por modelo, sin depender de `PROC LOGISTIC` para ello. |
| `%comprobar_scores` | — | Valida que cada uno de los 3 métodos puntúe a **toda** la validación, con IDs únicos y probabilidades en [0,1]. |
| `%exportar(tabla)` | tabla de `t2` | Exporta a CSV en `&carpeta.`. |

> Nota: `%score_log` se define **después** de `%comparar` pero antes de invocarla, por lo que funciona (SAS resuelve las llamadas anidadas al ejecutar).

## Flujo

1. **Variables de entrada limpias** — `&predictores` = columnas numéricas de `ABT_MODELER` excepto `ID`, `TARGET`, `PARTICION`; `&n_limpia` = cuántas son.
2. **PCA** — `PROC PRINCOMP` en entrenamiento (`outstat=t2.ej2_parametros_pca`, valores propios en `t2.ej2_varianza_pca`).
   Un `DATA _NULL_` busca el primer componente con `cumulative >= &meta_pca` y guarda `&k` y `&varianza_pca`.
3. **Puntuación PCA** — `PROC SCORE type=score` aplica la rotación (ajustada en entrenamiento) a ambas particiones → `t2.ej2_abt_pca` (`id, target, particion, Prin1–Prin&k`).
4. **Clusterización de variables** — `PROC VARCLUS maxclusters=&k` en entrenamiento → `t2.ej2_clusters` (R-cuadrado).
5. **Representantes** — Se ordena cada grupo por `1-R²` ratio (`rsquareratio`, menor es mejor; los faltantes van al final) y se toma la primera variable de cada grupo → `t2.ej2_representantes`.
   Se exige que haya exactamente `&k` grupos válidos. Resultado: `t2.ej2_abt_clusters`.
6. **Tres regresiones logísticas** con `%score_log` para `Limpia`, `PCA` y `Clusters`.
7. **Métricas** — `%roc_ks` → `t2.ej2_comparacion` con: método, número de entradas, casos de validación, **tasa de mala clasificación** (corte 0.5), **AUC** y **KS**, ordenado por AUC y KS.
8. **Reportes** — Imprime componentes hasta el 80 %, representantes por cluster y la tabla comparativa.
9. **Exporta** `ej2_abt_pca.csv`, `ej2_abt_clusters.csv`, `ej2_comparacion.csv`, `ej2_representantes.csv`.

## Tablas generadas

| Tabla (`t2.`) | Contenido |
|---|---|
| `ej2_varianza_pca` | Valores propios, proporción y acumulado de varianza. |
| `ej2_parametros_pca` | Estadísticos y cargas para puntuar. |
| `ej2_abt_pca` | ABT reducida con componentes principales. |
| `ej2_clusters` | Salida de R-cuadrado de VARCLUS. |
| `ej2_representantes` | Una variable por cluster. |
| `ej2_abt_clusters` | ABT reducida con variables representantes. |
| `ej2_comparacion` | Comparación final (MISC, AUC, KS). |
