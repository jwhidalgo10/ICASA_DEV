@EndUserText.label : 'Tabla Z BUT000 Simulacion'
@AbapCatalog.enhancementCategory : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #ALLOWED
define table zbp_but000_sim {
  key client  : abap.clnt not null;
  key partner : bu_partner not null;
  bp_type     : char10;
  nit         : char20;
  dpi         : char20;
  email       : char100;
  phone       : char20;

}
