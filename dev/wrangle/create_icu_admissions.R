# Steve Harris
# created 2021-01-03 
# derived from create_icu_admissions

# Create one row per patient (starting with the location_visit table) and
# filtering where the patients have been to an ICU
# then set this up to appear like an OMOP visit_occurrence table

# ****
# TODO
# ****
# - [ ] TODO rebuild to look like OMOP


# *************
# Running notes
# *************

# Libraries

library(lubridate)
library(magrittr)
library(purrr)
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Starting to build ICU admissions table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Script collapses all patients assuming that they are unique based on ...
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_test'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapR_admissions'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load bed moves
# ==============
query <- "
SELECT * FROM flow.census_cc
;
"

# - [ ] TODO make this compatible w emapR::select_from by working out how to specify query
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
rdt <- data.table::copy(dt)

# now make unique by ICU admissions
wdt <- rdt[!is.na(cc_census)]
# tdt <- rdt[mrn=='91134732'][order(ts,-event)]

# focus the columns
wdt <- wdt[,.(
   mrn
  ,encounter
  ,hospital_visit_id
)]

# 2021-01-09t13:09:22 RESUME
stop()

# check for duplicate hospital numbers
wdt[, mrn_N := .N, by=.(firstname,lastname,date_of_birth,sex)]
assertthat::assert_that(nrow(wdt[mrn_N>1]) == 0, msg = 'duplicate MRNs by first/lastname/DoB/Sex')
wdt[, mrn_N := NULL]
wdt[, age_at_death := as.numeric(difftime(date_of_death, date_of_birth, units = 'days'))/365.25]
wdt[order(-date_of_death)]

wdt

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')

