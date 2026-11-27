/* EJERCICIO 2: comparar ABT limpia, PCA y clusterizacion de variables. */
%let carpeta = /ruta/a/tu/carpeta/Proyecto;
%let meta_pca = 0.80;
libname t2 "&carpeta.";

%macro comprobar;
    %if not %sysfunc(exist(t2.abt_modeler)) %then %do;
        %put ERROR: No se encontro T2.ABT_MODELER. Ejecuta primero el programa de preparacion.;
        %abort cancel;
    %end;
%mend;
%comprobar;

proc sql noprint;
    select name into :predictores separated by ' '
    from dictionary.columns
    where libname='T2' and memname='ABT_MODELER' and type='num'
          and upcase(name) not in ('ID','TARGET','PARTICION')
    order by varnum;
quit;
%let n_limpia = %sysfunc(countw(%superq(predictores)));

/* Ambos metodos se ajustan con las mismas personas de entrenamiento. */
ods output Eigenvalues=t2.ej2_varianza_pca;
proc princomp data=t2.abt_modeler(where=(particion=1)) outstat=t2.ej2_parametros_pca;
    var &predictores.;
run;
ods output close;

%let k=0;
data _null_;
    set t2.ej2_varianza_pca;
    if cumulative >= &meta_pca. then do;
        call symputx('k', number, 'G');
        call symputx('varianza_pca', cumulative, 'G');
        stop;
    end;
run;

%macro comparar;
    %if &k. EQ 0 %then %do;
        %put ERROR: No se pudo determinar el numero de componentes PCA.;
        %abort cancel;
    %end;

    /* Aplicar a ambas particiones la transformacion ajustada en entrenamiento. */
    proc score data=t2.abt_modeler score=t2.ej2_parametros_pca
               out=work.ej2_puntuaciones_pca type=score;
        var &predictores.;
    run;
    data t2.ej2_abt_pca;
        set work.ej2_puntuaciones_pca;
        keep id target particion Prin1-Prin&k.;
    run;

    /* Mismo presupuesto de entradas que PCA. Elegir menor razon de R-cuadrado. */
    ods output RSquare=t2.ej2_clusters;
    proc varclus data=t2.abt_modeler(where=(particion=1))
                 maxclusters=&k. short;
        var &predictores.;
    run;
    ods output close;

    /* ODS puede presentar el grupo solo en la primera fila del bloque. */
    data work.ej2_membresia;
        length grupo $32;
        retain grupo;
        set t2.ej2_clusters;
        if not missing(cluster) then grupo=strip(vvalue(cluster));
        if not missing(grupo) and not missing(variable);
        ratio_faltante=missing(rsquareratio);
    run;

    /* Admitir exclusivamente nombres de predictores reales de ABT_MODELER. */
    proc sql;
        create table work.ej2_orden_clusters as
        select a.grupo, b.name as variable, a.rsquareratio, a.ratio_faltante
        from work.ej2_membresia a inner join dictionary.columns b
          on upcase(strip(a.variable))=upcase(b.name)
        where b.libname='T2' and b.memname='ABT_MODELER' and b.type='num'
              and upcase(b.name) not in ('ID','TARGET','PARTICION');
    quit;
    proc sort data=work.ej2_orden_clusters;
        by grupo ratio_faltante rsquareratio variable;
    run;

    /* Los valores perdidos se ordenan al final y se usa el menor valor valido. */
    data t2.ej2_representantes;
        set work.ej2_orden_clusters;
        by grupo;
        if first.grupo;
        keep grupo variable rsquareratio;
        rename grupo=cluster;
    run;

    %local representantes n_cluster;
    proc sql noprint;
        select variable into :representantes separated by ' '
        from t2.ej2_representantes;
        select count(*) into :n_cluster trimmed from t2.ej2_representantes;
    quit;
    %if &n_cluster. NE &k. %then %do;
        title "Diagnostico de representantes de VARCLUS";
        proc print data=t2.ej2_representantes noobs; run;
        title;
        %put ERROR: Se esperaban &k. grupos validos y se obtuvieron &n_cluster..;
        %abort cancel;
    %end;

    data t2.ej2_abt_clusters;
        set t2.abt_modeler;
        keep id target particion &representantes.;
    run;

    %score_log(t2.abt_modeler, &predictores., Limpia);
    %score_log(t2.ej2_abt_pca, Prin1-Prin&k., PCA);
    %score_log(t2.ej2_abt_clusters, &representantes., Clusters);
%mend;

%macro score_log(tabla, variables, metodo);
    proc logistic data=&tabla.(where=(particion=1)) outmodel=work.ej2_log_&metodo.;
        model target(event='1') = &variables.;
    run;

    proc logistic inmodel=work.ej2_log_&metodo.;
        score data=&tabla.(where=(particion=0))
              out=work.ej2_score_&metodo.(keep=id target P_1);
    run;

    data work.ej2_score_&metodo.;
        length modelo $8;
        set work.ej2_score_&metodo.;
        modelo="&metodo.";
        p=P_1;
        keep modelo id target p;
    run;
%mend;

%comparar;

%macro roc_ks(entrada, salida, puntos);

proc sql;

        create table work._dist as

        select modelo, p, sum(target=1) as ev, sum(target=0) as ne

        from &entrada.

        group by modelo, p

        order by modelo, p desc;

        create table work._tot as

        select modelo, sum(ev) as ev_tot, sum(ne) as ne_tot

        from work._dist group by modelo order by modelo;

quit;

data &puntos.;

        merge work._dist work._tot; by modelo;

        retain cev cne auc tpr_ant fpr_ant ks;

        if first.modelo then do; cev=0; cne=0; auc=0; tpr_ant=0; fpr_ant=0; ks=0; end;

        cev = cev + ev;  cne = cne + ne;

        tpr = cev / ev_tot;  fpr = cne / ne_tot;

        auc = auc + (fpr - fpr_ant) * (tpr + tpr_ant) / 2;

        ks  = max(ks, abs(tpr - fpr));

        tpr_ant = tpr;  fpr_ant = fpr;

run;

data &salida.;

        set &puntos.; by modelo;

        if last.modelo;

        keep modelo auc ks;

run;

%mend;


data work.ej2_scores;
    set work.ej2_score_Limpia work.ej2_score_PCA work.ej2_score_Clusters;
run;

%macro comprobar_scores;
    proc sql noprint;
        select count(*) into :n_valid trimmed
        from t2.abt_modeler where particion=0;
        create table work.ej2_control as
        select modelo, count(*) as n, count(distinct id) as ids,
               sum(missing(p) or p<0 or p>1) as invalidos
        from work.ej2_scores group by modelo;
        select count(*) into :metodos_validos trimmed from work.ej2_control
        where n=&n_valid. and ids=&n_valid. and invalidos=0;
    quit;
    %if &metodos_validos. NE 3 %then %do;
        %put ERROR: Las tres regresiones deben puntuar a toda la validacion.;
        %abort cancel;
    %end;
%mend;
%comprobar_scores;

%roc_ks(work.ej2_scores, work.ej2_metricas, work.ej2_roc);

proc sql;
    create table t2.ej2_comparacion as
    select a.modelo as metodo,
           case when a.modelo='Limpia' then &n_limpia. else &k. end as entradas,
           count(*) as casos_validacion,
           mean((a.p>=0.5) ne a.target) as misc_valid format=percent8.2,
           b.auc format=8.4, b.ks format=8.4
    from work.ej2_scores a inner join work.ej2_metricas b on a.modelo=b.modelo
    group by a.modelo, b.auc, b.ks
    order by b.auc desc, b.ks desc;
quit;

title "PCA - Componentes hasta alcanzar el 80%";
proc print data=t2.ej2_varianza_pca noobs;
    where Number <= &k.;
    var Number Proportion Cumulative;
    format Proportion Cumulative percent8.2;
run;

title "Clusterizacion - Variable representante por grupo";
proc print data=t2.ej2_representantes noobs;
run;

title "Comparacion en validacion - Misma regresion y misma particion";
proc print data=t2.ej2_comparacion noobs;
run;
title;

%macro exportar(tabla);
    proc export data=t2.&tabla. outfile="&carpeta./&tabla..csv"
                dbms=csv replace;
    run;
%mend;
%exportar(ej2_abt_pca);
%exportar(ej2_abt_clusters);
%exportar(ej2_comparacion);
%exportar(ej2_representantes);
