
# Pre-writing wrangle
mdt[, news2_y := news2_pulse(mdt$y)]
mdt[, news2_yhat := news2_pulse(mdt$yhat)]

# Write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))

emapR::udsConnect()
DBI::dbWriteTable(ctn, name=target_table_path, value=mdt, overwrite=TRUE)
emapR::udsDisconnect()

rlang::inform('--- closing database connection')