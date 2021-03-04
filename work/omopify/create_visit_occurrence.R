# Steve Harris
# created 2021-01-24

# Create one row per hospital visit (for inpatients only)
# then set this up to appear like an OMOP visit_occurrence table

# ****
# TODO
# ****
# TODO abstract out schema references


# *************
# Running notes
# *************

# Libraries
library(lubridate)
library(data.table)
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Starting to build VISIT_OCCURRENCE table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Script collapses all patients assuming that they are unique based on ...
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_visit_occurrence'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load bed moves
# ==============
query <- "
SELECT 
   vo.hospital_visit_id       visit_occurrence_id
  ,ip.core_demographic_id     person_id
  ,vo.patient_class           visit_source_value
  ,vo.admission_time          visit_start_datetime
  ,vo.discharge_time          visit_end_datetime
  ,vo.encounter               csn
  ,vo.discharge_destination   discharge_to_source_value
  ,vo.arrival_method
  ,vo.discharge_disposition
  ,vo.presentation_time
FROM star_a.hospital_visit vo
RIGHT JOIN icu_audit.emapr_inpatient_filter ip ON vo.hospital_visit_id = ip.hospital_visit_id
;
"

# - [ ] TODO make this compatible w emapR::select_from by working out how to specify query
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
wdt <- data.table::copy(dt)
wdt

# admission/discharge dt tidying
wdt[, visit_start_date := lubridate::date(visit_start_datetime)]
wdt[, visit_end_date := lubridate::date(visit_end_datetime)]

# visit
# https://athena.ohdsi.org/search-terms/terms?vocabulary=Visit&page=1&pageSize=15&query=
janitor::tabyl(wdt$visit_source_value)
wdt[, visit_concept_id := NA] 
wdt[, visit_concept_id := ifelse(visit_source_value == 'INPATIENT', 9201, visit_concept_id)] 
wdt[, visit_concept_id := ifelse(visit_source_value == 'OUTPATIENT', 9202, visit_concept_id)] 

# visit type
# https://athena.ohdsi.org/search-terms/terms?vocabulary=Visit+Type&page=1&pageSize=15&query=
wdt[, visit_type_concept_id := 44818518] # visit derived from ehr record

# discharge to
# https://athena.ohdsi.org/search-terms/terms?vocabulary=CMS+Place+of+Service&page=1&pageSize=15&query=
janitor::tabyl(wdt$discharge_to_source_value)
wdt[, discharge_to_concept_id := NA]
wdt[, discharge_to_concept_id := ifelse(discharge_to_source_value == 'Patient Died', NA, discharge_to_concept_id)]
janitor::tabyl(wdt$discharge_to_concept_id)

# preceding_visit_occurrence_id
wdt[order(person_id,visit_start_datetime),
    preceding_visit_occurrence_id := shift(visit_occurrence_id, type='lag', n=1),
    by=person_id]
wdt[,preceding_visit_occurrence_id :=
    ifelse(preceding_visit_occurrence_id == 0, NULL,
           preceding_visit_occurrence_id)]
wdt[,.(visit_occurrence_id, preceding_visit_occurrence_id)]

# Order of vars
setcolorder(wdt, c( 'visit_occurrence_id'
                   ,'person_id'
                   ,'visit_concept_id'
                   ,'visit_start_date'
                   ,'visit_start_datetime'
                   ,'visit_end_date'
                   ,'visit_end_datetime'
                   ,'visit_type_concept_id'
                   ,'visit_source_value'
                   ,'discharge_to_source_value'
                   # add on columns; not part of the definition
                   ))

chk <- nrow(wdt) - uniqueN(wdt)
if (chk) rlang::warn(paste('---', chk, 'duplicate rows found and removed'))
wdt <- unique(wdt)

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


