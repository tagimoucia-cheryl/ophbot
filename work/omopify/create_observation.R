# Steve Harris
# created 2021-01-25

# collapse down observations into a daily cadence?
# then set this up to appear like an OMOP observation table

# ****
# TODO
# ****


# *************
# Running notes
# *************

# Libraries
library(lubridate)
library(data.table)
library(emapR) # see setup.R for installation
library(assertthat)

# *************
# Configuration
# *************
rlang::inform('--- Starting to build OBSERVATION table')

DEBUG <- FALSE
if (DEBUG) rlang::warn('!!! debug mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: uds.icu_audit.observations
target_schema <- 'icu_audit'
target_table <- 'emapr_observation'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()


# Load visit_observation
# ==============
query <- "
SELECT 
   ob.hospital_visit_id       visit_occurrence_id
  ,ip.core_demographic_id     person_id
  ,ob.observation_datetime
  ,ob.unit
  ,ob.value_as_real
  ,ob.value_as_text
  ,ot.name
  ,ot.displayname
FROM star_a.visit_observation ob
LEFT JOIN icu_audit.emapr_visit_observation_type ot
  ON ob.visit_observation_type_id = ot.visit_observation_type
RIGHT JOIN icu_audit.emapr_inpatient_filter ip ON ob.hospital_visit_id = ip.hospital_visit_id
WHERE ot.name IN
  (
   'PULSE OXIMETRY'
  )
;
"
# expect around 1.6m value just for spo2!
rlang::warn('--- slow query')
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
wdt <- data.table::copy(dt)

# if you want to use the extract function then you need to emulate connecting to OMOP
# ideally rewrite emapR to handle arbitrary table names
# Now build index on location_string
target_table_string <- paste('icu_audit', 'emapr_visit_occurrence', sep=".")
create_view_statement <- paste(
  "CREATE VIEW icu_audit.visit_occurrence AS SELECT * FROM", target_table_string, ";"
)
DBI::dbExecute(ctn, 'DROP VIEW IF EXISTS icu_audit.visit_occurrence;')
DBI::dbExecute(ctn, create_view_statement)

query <- "
CREATE VIEW icu_audit.observation AS
SELECT 
   ob.visit_observation_id       observation_id
  ,ob.observation_datetime
  ,ob.visit_observation_type_id  observation_concept_id
  ,ob.value_as_real              value_as_number
  ,ob.value_as_text              value_as_string
  ,ob.hospital_visit_id          visit_occurrence_id
  ,ob.unit                       unit_source_value
  ,ot.name
FROM star_a.visit_observation ob
LEFT JOIN icu_audit.emapr_visit_observation_type ot
  ON ob.visit_observation_type_id = ot.visit_observation_type
WHERE ot.name = 'PULSE OXIMETRY'
"
DBI::dbExecute(ctn, 'DROP VIEW IF EXISTS icu_audit.observation;')
DBI::dbExecute(ctn, query)

# 2021-01-26t00:12:50 resume: now you have observation and vo then you should be able to use emapR::extract
wdt <- emapR::extract(
  ctn,
  'icu_audit',
  concept_ids = c(2273987897),
  concept_short_names = c('spo2'),
  cadence = 24
)
stop()
# error b/c line 116 concatenates a data.table and a string

tables <- data.table(table = c('observation', 'measurement'),
                     path = '')
tables
if (is.null(NULL)) tables <- c(tables, 'visit_occurrence')
tables
emapR::extract
stop()

# structure as per OMOP
# wdt <- wdt[,.(
#    visit_detail_id = NA_integer_
#   ,person_id
#   ,visit_detail_concept_id = NA_integer_
#   ,visit_detail_start_date =  lubridate::date(visit_detail_start_datetime)
#   ,visit_detail_start_datetime 
#   ,visit_detail_end_date =  lubridate::date(visit_detail_end_datetime)
#   ,visit_detail_end_datetime 
#   ,visit_detail_type_concept_id = 44818518 # derived from EHR
#   ,provider_id = NA_integer_
#   ,care_site_id = NA_integer_ # should be location_id but create duplicate rows
#   ,visit_detail_source_value = ward
#   ,visit_detail_source_concept_id = NA_integer_
#   ,admitting_source_value = NA_character_ 
#   ,admitting_source_concept_id = NA_integer_
#   ,discharge_to_source_value = NA_character_
#   ,discharge_to_source_concept_id = NA_integer_
#   ,preceding_visit_detail_id = NA_integer_
#   ,visit_occurrence_id
#   ,ward_lag1
#   ,ward_lead1
# ) ]
# setkey(wdt, person_id, visit_occurrence_id, visit_detail_start_datetime)
# wdt[, visit_detail_id := .I]
# wdt

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


