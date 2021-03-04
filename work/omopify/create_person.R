# Steve Harris
# created 2021-01-24

# Create one row per patient then set this up to appear like an OMOP patients table

# ****
# TODO
# ****
# TODO abstract out the schema references so you can swap from a/b/test etc.


# *************
# Running notes
# *************

# Libraries
library(lubridate)
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Starting to build PERSON table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Script collapses all patients assuming that they are unique based on ...
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_person'
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
   p.core_demographic_id      person_id
	,ip.mrn                     person_source_value
	,ip.nhs_number
	,p.firstname
	,p.lastname
	,p.home_postcode
	,p.alive
	,p.date_of_birth::timestamp birth_datetime
	,p.date_of_death::timestamp death_datetime
	,p.sex                      gender_source_value
FROM star_a.core_demographic p
RIGHT JOIN icu_audit.emapr_inpatient_filter ip ON p.core_demographic_id = ip.core_demographic_id
;
"

# - [ ] TODO make this compatible w emapR::select_from by working out how to specify query
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
wdt <- data.table::copy(dt)

# gender 
# https://athena.ohdsi.org/search-terms/terms?vocabulary=Gender&page=1&pageSize=15&query=gender
wdt[, gender_concept_id := NA]
wdt[, gender_concept_id := ifelse(gender_source_value == 'F', 8632, gender_concept_id)]
wdt[, gender_concept_id := ifelse(gender_source_value == 'M', 8507, gender_concept_id)]
wdt[, gender_concept_id := ifelse(gender_source_value == 'U', 8551, gender_concept_id)]
with(wdt, table(gender_concept_id, gender_source_value))

# DoB tidying
wdt[, year_of_birth := lubridate::year(birth_datetime)]
wdt[, month_of_birth := lubridate::month(birth_datetime)]
wdt[, day_of_birth := lubridate::day(birth_datetime)]

str(wdt)

# Order of vars
setcolorder(wdt, c( 'person_id'
                   ,'gender_concept_id'
                   ,'year_of_birth'
                   ,'month_of_birth'
                   ,'day_of_birth'
                   ,'birth_datetime'
                   ,'death_datetime'
                   ,'person_source_value'
                   ,'gender_source_value'
                   # add on columns; not part of the definition
                   ,'nhs_number'
                   ,'firstname'
                   ,'lastname'
                   ,'home_postcode'
                   ))
wdt <- unique(wdt)

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


