@EndUserText.label : 'BP Audit Log - Items'
@AbapCatalog.enhancementCategory : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zbp_audit_itm {
  key client     : abap.clnt not null;
  key log_id     : sysuuid_x16 not null;
  key partner    : bu_partner not null;
  key field_name : abap.char(30) not null;
  old_value      : abap.char(100);
  new_value      : abap.char(100);
  status         : abap.char(1);
  message        : abap.char(255);
  created_at     : abap.dec(15,0);

}
