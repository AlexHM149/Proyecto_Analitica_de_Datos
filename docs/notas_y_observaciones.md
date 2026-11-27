# Notas, supuestos y puntos a verificar

## Supuestos del código
- `historico` se interpreta con la **posición 1 = mes más reciente** (los "últimos 6/12/18/24 meses" son los primeros caracteres).
- `peor_X_meses` es el máximo acumulado: si el histórico es más corto que X, el valor es el peor de todo el histórico disponible.
- Sólo se evalúa desempeño sobre créditos del otorgante `&otorgante.` en la base 2018; las variables explicativas usan **todos** los créditos de 2017 (bancarios y no bancarios).
- Los puntos de corte de la matriz de clasificación (`misc_valid`) usan probabilidad 0.5; con clases desbalanceadas AUC y KS son más informativos.

## Buenas prácticas ya presentes
- Partición **estratificada** y reproducible (`seed`).
- Imputación, estandarización y PCA/VARCLUS **ajustados sólo con entrenamiento**.
- Aserciones con `%exigir` / `%comprobar*` que detienen el programa si algo no cuadra.
- Mismo modelo (regresión logística) y misma partición para comparar los tres métodos de forma justa.

## Puntos a verificar con el enunciado / mejoras posibles
1. **MOP `9`**: el código lo trata como el valor numérico más alto, por lo que cualquier `9` en 12 meses implica `TARGET = 1` (aparece mucho en los datos). Confirma que ese sea el significado deseado; el `0` y los códigos `96/97` de `modo_pago` no entran en el cálculo.
2. Posible **sesgo temporal**: asegúrate de que ninguna variable de 2017 use información posterior a la fecha de corte.
3. `saldo` tiene muchos faltantes en la base 2017 (≈108 mil) y ninguno en la de 2018; considera documentar la causa.
4. Las rutas contienen el **usuario institucional** (correo). Antes de publicar el repositorio, reemplázalas por una ruta genérica o una macrovariable.
5. Los CSV no se versionan; documenta su fuente en `data/README.md`.
