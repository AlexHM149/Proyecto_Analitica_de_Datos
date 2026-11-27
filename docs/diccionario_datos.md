# Diccionario de datos

## Entrada: `creditos_obs_1712.csv` y `creditos_des_1812.csv`

Una fila por **crédito**; cada persona (`id`) puede tener varios créditos. Ambas bases comparten las mismas 13 columnas y los mismos 19,001 clientes.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | numérico | Identificador de la persona. |
| `otorgante` | texto | `bancario` o `nobancario`. |
| `tipo_credito` | texto | `fijos`, `revolvente`, `hipotecario` o `sin info`. |
| `pagos_realizados` | numérico | Pagos realizados (muchos faltantes). |
| `tipo_pago` | texto | Periodicidad: `mensual`, `quincenal`, `semanal` u `otro`. |
| `monto_del_pago` | numérico | Monto del pago periódico. |
| `fecha_apertura` | fecha (dd/mm/aaaa) | Apertura del crédito. |
| `fecha_cierre` | fecha (dd/mm/aaaa) | Cierre; vacío si sigue abierto. |
| `credito` | numérico | Monto / límite del crédito. El valor `404040404` es un centinela → se trata como faltante. |
| `saldo` | numérico | Saldo actual. |
| `saldo_vencido` | numérico | Saldo vencido. |
| `modo_pago` | numérico | Modo de pago actual (MOP). |
| `historico` | texto (≤ 24) | Una letra por mes. Dígitos `0–9` = modo de pago, `X` = sin información, `U` = sin uso. |

## Códigos de `historico` y su tratamiento

| Carácter | Tratamiento en el código |
|---|---|
| `1, 2, 3, 4, 5, 6, 7, 9` | Se convierten a número y participan en el **máximo** (peor MOP). |
| `0` | Ignorado (no participa). |
| `X`, `U` | Ignorados. |

## Variables por crédito (`t2.parte_a_credito`)

`tiempo_en_libros`, `antiguedad`, `pct_utilizacion`, `imor`, `peor_6_meses`, `peor_12_meses`, `peor_18_meses`, `peor_24_meses` (definiciones en [01_preparacion_abt.md](01_preparacion_abt.md)).

## Variables por persona (`t2.abt_parte_a`, 80 + `id`)

Cada una de las 8 variables anteriores × 10 estadísticos, con nombres autogenerados por `PROC MEANS` (`autoname`):
`_Min`, `_P5`, `_P25`, `_Median`, `_P75`, `_P95`, `_Max`, `_Mean`, `_Mode`, `_StdDev`.
Ej.: `antiguedad_Mean`, `imor_P95`, `peor_12_meses_Max`.

## Tablas finales

| Tabla | Columnas |
|---|---|
| `t2.abt_risk` | `id`, 80 predictores, `target`. |
| `t2.abt_modeler` | `id`, `target`, `particion` (1 = entrenamiento, 0 = validación) + predictores conservados, imputados y en z-score. |
| `t2.ej2_abt_pca` | `id`, `target`, `particion`, `Prin1 … Prin<k>`. |
| `t2.ej2_abt_clusters` | `id`, `target`, `particion` + variables representantes. |

## Variable objetivo

`TARGET = 1` si en la base de **2018**, entre los créditos del otorgante seleccionado, la persona tiene un peor MOP en los primeros 12 meses del histórico **≥ 4**; `0` si tiene información válida y nunca llega a 4.
