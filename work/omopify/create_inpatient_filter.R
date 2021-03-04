# Steve Harris
# created 2021-01-24

# Create a filter that identifies INPATIENTS

# ****
# TODO
# ****


# *************
# Running notes
# *************

# Libraries
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Starting to build OMOP inpatients table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: 
target_schema <- 'icu_audit'
target_table <- 'emapr_inpatient_filter'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load bed moves
# ==============
# - [ ] TODO rebuild directly from location_visit
query <- readr::read_file('sql/view_inpatient_filter.sql')

# - [ ] TODO make this compatible w emapR::select_from by working out how to specify query
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
names(dt)

# select columns
wdt <- data.table::copy(dt)

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


