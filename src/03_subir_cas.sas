libname prep "/export/viya/ruta/a/tu/carpeta/Proyecto;";

cas;

proc casutil;
    load data=prep.ej2_abt_pca
         outcaslib="CASUSER"
         casout="ej2_abt_pca"
         promote;
quit;