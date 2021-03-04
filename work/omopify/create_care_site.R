# Steve Harris
# created 2021-01-03 

# Create one row per care site 
# then set this up to appear like an OMOP CARE_SITE table

# ****
# TODO
# ****


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
rlang::inform('--- Starting to build CARE_SITE table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: 
target_schema <- 'icu_audit'
target_table <- 'emapr_care_site'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load bed moves
# ==============
# - [ ] TODO rebuild directly from location_visit
dt <- emapR::select_from(ctn, input_schema, 'location')
wdt <- data.table::copy(dt)
names(dt)

# select columns
wdt <- data.table::copy(dt)
wdt <- wdt[,.(
   care_site_id = location_id
  ,care_site_name = location_string
  ,place_of_service_concept_id = NA_integer_
  ,location_id = NA_integer_ # foreign key to location table (physical location)
  ,care_site_source_value = NA_character_
  ,place_of_service_source_value = NA_character_
)]
wdt[, c('ward', 'room', 'bed') := data.table::tstrsplit(care_site_name, split='\\^')]

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


