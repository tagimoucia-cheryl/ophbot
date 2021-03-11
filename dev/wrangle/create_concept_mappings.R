# Steve Harris
# 2020-07-03
# Prepare and manage a local table of concept mappings


# Log
# 2020-07-03: initial version
# 2020-07-06: 
# - updated to use basic OMOP concept structure
# - works from ops

# TODO: switch over to using mapping table from caboodle
# NOTE: note this is destructive and overwrites the existing table

# Prepare metadata 
# Takes Ed's existing OMOP mapping csv and converts to a table in the schema with the correct flow sheet rows

# NOTE: the naming of variables is often deliberately following the naming that Ed uses in inspectEHR

# Libraries
library(data.table)

# *************
# Configuration
# *************
# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")
rlang::inform('--- success: connnectd to UDS')

debug <- FALSE
ops_schema <- 'ops_b'
icu_schema <- 'icu_audit'

extract_unique_concepts_from <- function(concept_column, table, schema, ctn) {
  text_path <- paste(schema, table, sep='.')
  query <- paste('SELECT DISTINCT(', concept_column, ') FROM', text_path)
  dt <- setDT(DBI::dbGetQuery(ctn, query))
  setnames(dt, concept_column, 'concept_id')
  return(dt)
}

d <- data.table(
  table = c('measurement', 'measurement', 'observation', 'observation'),
  column = c('measurement_concept_id', 'unit_concept_id', 'observation_concept_id', 'unit_concept_id')
)
concepts <- vector("list", nrow(d))

for (i in 1:length(concepts)) {
  udt <- extract_unique_concepts_from(d[i]$column, d[i]$table, ops_schema, ctn)
  concepts[[i]] <- udt
  
}
concepts <- rbindlist(concepts, fill=TRUE)

# Write this back to the database so you can do the join there
target_table_path <- DBI::Id(schema=icu_schema, table='concepts_icu')
DBI::dbWriteTable(ctn, name=target_table_path, value=concepts, overwrite=TRUE)

# Join with concepts from ops to get OMOP structure
query_concepts_join2omop <- '
SELECT 
	c.* 
	FROM icu_audit.concepts_icu ci
	LEFT JOIN ops.concept c
		ON ci.concept_id = c.concept_id
'
rlang::inform('--- filtering ops.concepts (OMOP) to just those in use in ops measurement/observation')
concepts <- setDT(DBI::dbGetQuery(ctn,query_concepts_join2omop))
DBI::dbWriteTable(ctn, name=target_table_path, value=concepts, overwrite=TRUE)

# Maintain your own local mapping file that runs from this
first_run <- FALSE
if (first_run) {
  rlang::inform('--- FIRST_RUN=TRUE: rebuilding concept_dict from provided text files')
  audit_dict <- setDT(readr::read_tsv('data/audit_master.txt'))
  colnames(audit_dict)
  d1 <- audit_dict[!is.na(id_omop),.(concept_id=id_omop,
                               name_short,
                               data_type,
                               domain_omop)]
  d1[, target := '']
  d1[tolower(data_type) == 'numeric', target := 'value_as_number']
  d1[tolower(data_type) == 'string', target := 'value_as_string']
  d1[tolower(data_type) == 'categorical', target := 'value_as_string']
  d1 <- d1[!is.na(name_short),.(concept_id, name_short, target)]
  d1
  
  inspectEHR_dict <- setDT(readr::read_csv('data/omop_mapping_ref.csv'))
  colnames(inspectEHR_dict)
  d2 <- inspectEHR_dict[!is.na(concept_id),.(concept_id, name_short=short_name, target)]
  d2 <- d2[!is.na(name_short),.(concept_id, name_short, target)]
  
  cdt <- unique(rbindlist(list(d1,d2)))
  cdt[, concept_id := as.integer(concept_id)]
  concepts <- cdt[concepts, on='concept_id']
  
  file.copy('data/concept_dict.csv', 'data/concept_dict.csv.bak')
  readr::write_csv(concepts, 'data/concept_dict.csv')
} 

cdt <- setDT(readr::read_csv('data/concept_dict.csv'))

target_table_path <- DBI::Id(schema=icu_schema, table='concepts_icu')
DBI::dbWriteTable(ctn, name=target_table_path, value=cdt, overwrite=TRUE)



# RESUME: now append your local short name info
stop()




# Load and update mapping table
# =============================

mdata <- readr::read_csv('data/omop_mapping_ref.csv')
# this is the one from the omop branch of inspectEHR it contains concept_ids,
# the name of the column holding the data; but you need to add the key to look
# up from obs (i.e. flowsheet_type)
setDT(mdata)

# Hand corrections
mdata[short_name == 'hr', short_name := 'hrate']
mdata[short_name == 'rr', short_name := 'rrate']
mdata[short_name == 'temp', short_name := 'temperature']
mdata[short_name == 'vol_tidal', short_name := 'tidal_volume']

concepts <- mdata[concept_keys, on='short_name == name_short']
setnames(concepts, 'concept_audit', 'concept_source_name')
concepts



# Add each item that you which to extract here
# ============================================
# NOTE: add all additional mappings here (hard coded for now)
concepts[!is.na(target)]

DBI::dbWriteTable(ctn, name=target_table_path, value=concepts, overwrite=TRUE)
DBI::dbDisconnect(ctn)
