/* =========================================================================
   PROYECTO FINAL - PREPARACION DE DATOS (SAS Studio)
   Datos de observacion de 2017 y desempeno NO BANCARIO de 2018.
   Ajusta RUTA a la carpeta con los dos CSV. Resultados en preparacion_proyecto.
   Salida para cargar manualmente en CAS: abt_modeler.csv.
   ========================================================================= */

%let ruta = /ruta/a/tu/carpeta/Proyecto;
%let f_obs = &ruta./creditos_obs_1712.csv;
%let f_des = &ruta./creditos_des_1812.csv;
%let ruta_resultados = &ruta./preparacion_proyecto;
%let otorgante = nobancario;
%let corte_obs = 30DEC2017;
%let semilla = 12345;

%macro verificar_archivos;
    %if not %sysfunc(fileexist(&f_obs.)) or not %sysfunc(fileexist(&f_des.)) %then %do;
        %put ERROR: Verifica que los dos CSV esten en &ruta.;
        %abort cancel;
    %end;
%mend;
%verificar_archivos;

options dlcreatedir;
libname t2 "&ruta_resultados.";
ods graphics on;
title; footnote;

/* =========================================================================

   LECTURA DE LOS CSV (misma lectura para las dos bases)

   DATA step y no PROC IMPORT: HISTORICO debe ser texto (trae X y U).

   ========================================================================= */

data t2.creditos_obs;

    infile "&f_obs." dsd firstobs=2 truncover lrecl=32767;

    length id 8 otorgante $10 tipo_credito $11 pagos_realizados 8

           tipo_pago $9 monto_del_pago 8 fecha_apertura fecha_cierre 8

           credito saldo saldo_vencido modo_pago 8 historico $24;

    informat fecha_apertura fecha_cierre ddmmyy10.;

    format   fecha_apertura fecha_cierre date9.;

    input id otorgante $ tipo_credito $ pagos_realizados tipo_pago $

          monto_del_pago fecha_apertura fecha_cierre credito saldo

          saldo_vencido modo_pago historico $;

    historico = compress(historico, '0D'x);   /* quita retorno de carro */

    otorgante = lowcase(strip(otorgante));

run;

data t2.creditos_des;

    infile "&f_des." dsd firstobs=2 truncover lrecl=32767;

    length id 8 otorgante $10 tipo_credito $11 pagos_realizados 8

           tipo_pago $9 monto_del_pago 8 fecha_apertura fecha_cierre 8

           credito saldo saldo_vencido modo_pago 8 historico $24;

    informat fecha_apertura fecha_cierre ddmmyy10.;

    format   fecha_apertura fecha_cierre date9.;

    input id otorgante $ tipo_credito $ pagos_realizados tipo_pago $

          monto_del_pago fecha_apertura fecha_cierre credito saldo

          saldo_vencido modo_pago historico $;

    historico = compress(historico, '0D'x);

    otorgante = lowcase(strip(otorgante));

run;

/* Controles de lectura: revisa que las columnas y fechas se vean bien */

title "Control - creditos y personas por base";

proc sql;

    select 'obs_1712' as base, count(*) as creditos format=comma12.,

           count(distinct id) as personas format=comma12.,

           nmiss(fecha_apertura) as fechas_apertura_missing format=comma12.

    from t2.creditos_obs

    union all

    select 'des_1812', count(*), count(distinct id), nmiss(fecha_apertura)

    from t2.creditos_des;

quit;

title;

/* =========================================================================

   PARTE A  -  EJERCICIO 1: variables por credito (tabla obs)

   ========================================================================= */

data t2.parte_a_credito;

    set t2.creditos_obs;

    length c $1;

    fecha_corte = "&corte_obs."d;

    /* meses con movimiento reportado en el historico */

    tiempo_en_libros = lengthn(strip(historico));

    /* meses entre apertura y cierre (o la fecha de corte) */

    if missing(fecha_apertura) or fecha_apertura > fecha_corte
       or (not missing(fecha_cierre) and fecha_cierre < fecha_apertura)
       then antiguedad = .;

    else antiguedad = intck('month', fecha_apertura,

                            min(coalesce(fecha_cierre, fecha_corte), fecha_corte));

    if credito = 404040404 then credito = .;

    /* porcentaje de utilizacion = saldo / credito */

    if credito > 0 and saldo >= 0 then pct_utilizacion = saldo / credito * 100;

    else pct_utilizacion = .;

    /* IMOR (CNBV) = cartera vencida / cartera total = saldo vencido / saldo */

    if saldo > 0 and saldo_vencido >= 0 then imor = saldo_vencido / saldo * 100;

    else imor = .;

    /* peor modo de pago acumulado en los ultimos 6, 12, 18 y 24 meses */

    peor_6_meses = .; peor_12_meses = .; peor_18_meses = .; peor_24_meses = .;

    w = .;

    do i = 1 to 24;

        if i <= tiempo_en_libros then do;

            c = substr(historico, i, 1);

            if c in ('1','2','3','4','5','6','7','9') then w = max(w, input(c, 1.));

        end;

        if i = 6  then peor_6_meses  = w;

        if i = 12 then peor_12_meses = w;

        if i = 18 then peor_18_meses = w;

        if i = 24 then peor_24_meses = w;

    end;

    keep id tiempo_en_libros antiguedad pct_utilizacion imor

         peor_6_meses peor_12_meses peor_18_meses peor_24_meses;

run;

/* =========================================================================

   PARTE A  -  EJERCICIO 2: estadisticos a nivel persona (8 x 10 = 80 vars)

   ========================================================================= */

proc sort data=t2.parte_a_credito;

    by id;

run;

proc means data=t2.parte_a_credito noprint;

    by id;

    var tiempo_en_libros antiguedad pct_utilizacion imor

        peor_6_meses peor_12_meses peor_18_meses peor_24_meses;

    output out=work.estadisticos

        min= p5= p25= median= p75= p95= max= mean= mode= std= / autoname;

run;

data t2.abt_parte_a;

    set work.estadisticos(drop=_type_ _freq_);

run;

title "Parte A - Control de la tabla a nivel persona";

proc sql;

    select count(*) as personas format=comma12. from t2.abt_parte_a;

    select count(*) as columnas_incluye_id

    from dictionary.columns

    where libname = 'T2' and memname = 'ABT_PARTE_A';

quit;

title;

/* =========================================================================

   PARTE B  -  EJERCICIO 3: seleccionar creditos del otorgante del equipo

   ========================================================================= */

title "Ejercicio 3 - Creditos por otorgante (se selecciona: &otorgante.)";

proc freq data=t2.creditos_des;

    tables otorgante / nocum;

run;

title;

data t2.cred_sel;

    set t2.creditos_des;

    where compress(otorgante, " _-") = "&otorgante." and not missing(id);

run;

proc sql;

    title "Ejercicio 3 - Resultado de la seleccion";

    select count(*) as creditos_seleccionados format=comma12.,

           count(distinct id) as personas format=comma12.

    from t2.cred_sel;

quit;

title;

/* =========================================================================

   PARTE B  -  EJERCICIO 4: peor modo de pago en los ultimos 12 meses

   ========================================================================= */

data t2.cred_sel_mop;

    set t2.cred_sel;

    length c $1;

    peor_mop_12 = .;

    do i = 1 to min(12, lengthn(strip(historico)));

        c = substr(historico, i, 1);

        if c in ('1','2','3','4','5','6','7','9') then

            peor_mop_12 = max(peor_mop_12, input(c, 1.));

    end;

    drop i c;

run;

title "Ejercicio 4 - Distribucion del peor MOP en 12 meses (nivel credito)";

proc freq data=t2.cred_sel_mop;

    tables peor_mop_12 / missing nocum;

run;

title;

/* =========================================================================

   PARTE B  -  EJERCICIO 5: TARGET a nivel persona (solo id y TARGET)

   ========================================================================= */

proc sql;

    create table t2.target_sel as

    select id,

           case when max(peor_mop_12) >= 4 then 1
                when count(peor_mop_12) > 0 then 0
                else . end as target

    from t2.cred_sel_mop

    group by id

    order by id;

quit;

title "Ejercicio 5 - Distribucion de TARGET";

proc freq data=t2.target_sel;

    tables target / missing nocum;

run;

title;

/* =========================================================================

   PARTE B  -  EJERCICIO 6: ABT_RISK = tabla de la Parte A + TARGET

   ========================================================================= */

proc sql;

    create table t2.abt_risk as

    select a.*, t.target

    from t2.abt_parte_a as a

    inner join t2.target_sel as t

        on a.id = t.id

    where t.target in (0,1) and not missing(a.id)
    order by a.id;

quit;

%let abt = t2.abt_risk;

title "Ejercicio 6 - ABT_RISK";

proc sql;

    select count(*) as personas format=comma12.,

           mean(target) as tasa_target format=percent8.2

    from &abt.;

quit;

title;

/* Lista de variables independientes (numericas, sin id ni target) */

proc sql noprint;

    select name into :vars separated by ' '

    from dictionary.columns

    where libname = 'T2' and memname = 'ABT_RISK' and type = 'num'

      and upcase(name) not in ('ID', 'TARGET')

    order by varnum;

quit;

%let nv = %sysfunc(countw(&vars, %str( )));

%put NOTE: Variables independientes: &nv;

/* ===== PARTICION Y LIMPIEZA ===== */
%macro exigir(verdad, mensaje);
    %if not (&verdad.) %then %do;
        %put ERROR: &mensaje.;
        %abort cancel;
    %end;
%mend;

proc sql noprint;
    select count(*), count(distinct id), coalesce(sum(target=1),0), coalesce(sum(target=0),0)
        into :n_abt trimmed, :n_ids trimmed, :n_eventos trimmed, :n_noeventos trimmed
    from t2.abt_risk;
quit;
%exigir(&n_abt. GT 0 and &n_abt. EQ &n_ids., ABT vacia o con IDs invalidos);
%exigir(&n_eventos. GE 10 and &n_noeventos. GE 10, Faltan casos de alguna clase para particionar);

proc sort data=t2.abt_risk out=work.abt_ordenada;
    by target id;
run;

proc surveyselect data=work.abt_ordenada out=work.particion
                  method=srs samprate=0.70 seed=&semilla. outall noprint;
    strata target;
run;

data work.entrena work.valida;
    set work.particion;
    particion = Selected;
    drop Selected SelectionProb SamplingWeight;
    if particion=1 then output work.entrena;
    else output work.valida;
run;

title "Particion final y distribucion de TARGET";
proc freq data=work.particion;
    tables Selected*target / nocol nopercent;
run;
title;

/* ===== LIMPIEZA 1: DIAGNOSTICO Y DESCARTE DE COLUMNAS ===== */
ods exclude all;
ods output Summary=work.diag_inicial;
proc means data=work.entrena n nmiss std stackodsoutput;
    var &vars.;
run;
ods output close;
ods exclude none;

data t2.diagnostico_predictores;
    set work.diag_inicial;
    length motivo $30;
    pct_missing = NMiss / (N + NMiss);
    conservar = (pct_missing <= 0.50 and StdDev > 0);
    if pct_missing > 0.50 then motivo='Mas de 50% de faltantes';
    else if not conservar then motivo='Sin variacion util';
    else motivo='Conservar';
    format pct_missing percent8.2;
run;

title "Limpieza 1 - Faltantes en entrenamiento y decision por predictor";
proc print data=t2.diagnostico_predictores noobs;
    var variable n nmiss pct_missing conservar motivo;
run;

title;

%let entradas=;
proc sql noprint;
    select variable into :entradas separated by ' '
    from t2.diagnostico_predictores where conservar=1;
quit;
%let n_entradas=%sysfunc(countw(%superq(entradas)));
%exigir(&n_entradas. GT 0, No hay predictores aptos para la limpieza);

/* ===== LIMPIEZA 2: IMPUTACION POR MEDIANA ===== */
proc stdize data=work.entrena(keep=id target particion &entradas.)
            out=work.entrena_imp
            reponly method=median outstat=t2.medianas_train;
    var &entradas.;
run;

proc stdize data=work.valida(keep=id target particion &entradas.)
            out=work.valida_imp
            reponly method=in(t2.medianas_train);
    var &entradas.;
run;

/* Verificar faltantes antes y despues por particion. */
%macro resumen(tabla, salida);
    proc sort data=&tabla. out=work.orden_resumen;
        by particion;
    run;
    ods exclude all;
    ods output Summary=&salida.;
    proc means data=work.orden_resumen n nmiss mean std median stackodsoutput;
        by particion;
        var &entradas.;
    run;
    ods output close;
    ods exclude none;
%mend;

data work.antes_imp;
    set work.entrena work.valida;
run;

data work.despues_imp;
    set work.entrena_imp work.valida_imp;
run;

%resumen(work.antes_imp, work.stats_antes);
%resumen(work.despues_imp, work.stats_despues);

proc sql;
    create table t2.resumen_imputacion as
    select a.particion, a.variable, a.nmiss as faltantes_antes,
           b.nmiss as faltantes_despues,
           a.nmiss-b.nmiss as valores_imputados,
           e.median as mediana_entrenamiento
    from work.stats_antes a
    inner join work.stats_despues b
        on a.particion=b.particion and a.variable=b.variable
    inner join work.stats_antes e
        on e.particion=1 and a.variable=e.variable
    order by a.particion desc, a.variable;
quit;

title "Limpieza 2 - Imputacion por mediana de entrenamiento";
proc print data=t2.resumen_imputacion noobs;
    where faltantes_antes > 0 or faltantes_despues > 0;
    format mediana_entrenamiento best12.;
run;
title;

/* ===== LIMPIEZA 3: ESTANDARIZACION Z-SCORE ===== */
proc stdize data=work.entrena_imp out=work.entrena_z
            method=std outstat=t2.parametros_z;
    var &entradas.;
run;

proc stdize data=work.valida_imp out=work.valida_z
            method=in(t2.parametros_z);
    var &entradas.;
run;

data t2.abt_modeler;
    retain id target particion;
    set work.entrena_z work.valida_z;
    keep id target particion &entradas.;
run;

%resumen(t2.abt_modeler, t2.resumen_estandarizacion);

%let n_final=0;
%let ids_final=0;
%let faltantes_final=-1;
proc sql noprint;
    select count(*), count(distinct id)
        into :n_final trimmed, :ids_final trimmed
    from t2.abt_modeler;
    select coalesce(sum(nmiss),-1) into :faltantes_final trimmed
    from t2.resumen_estandarizacion;
quit;
%exigir(&n_final. EQ &n_abt. and &ids_final. EQ &n_abt.,
        La tabla final no conserva una fila por ID);
%exigir(&faltantes_final. EQ 0, Todavia hay faltantes en los predictores finales);

title "Limpieza 3 - Z-score por particion (1 entrenamiento, 0 validacion)";
proc print data=t2.resumen_estandarizacion noobs;
    var particion variable n nmiss mean stddev;
    format mean stddev 10.4;
run;

title "Tabla final para Model Studio - particion y TARGET";
proc freq data=t2.abt_modeler;
    tables particion*target / nocol nopercent;
run;
title;

%macro exportar(tabla);
    proc export data=t2.&tabla. outfile="&ruta_resultados./&tabla..csv"
                dbms=csv replace;
    run;
%mend;
%exportar(abt_modeler);
%exportar(diagnostico_predictores);
%exportar(resumen_imputacion);
%exportar(resumen_estandarizacion);
