@EndUserText.label : 'BP Audit Log - Header'
@AbapCatalog.enhancementCategory : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #ALLOWED
define table zbp_audit_hdr {
  key client     : abap.clnt not null;
  key log_id     : sysuuid_x16 not null;
  execution_date : abap.dats;
  execution_time : abap.tims;
  username       : syuname;
  is_simulation  : abap.char(1);
  total_bp       : abap.int4;
  total_errors   : abap.int4;
  total_success  : abap.int4;
  total_warnings : abap.int4;
  created_at     : abap.dec(15,0);

}
