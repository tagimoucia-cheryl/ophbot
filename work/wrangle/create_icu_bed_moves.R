# Steve Harris
# 2020-07-04
# Works with ops_b

# *************
# Running notes
# *************

# 2020-07-21 create ICU bed moves from ops_b; note that it should be trivial to generalise this for any ward
# 2020-07-21 this is not accurate as of 'now' so go back to using 'star'

# Libraries
library(lubridate)
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************

# debug <- TRUE
debug <- FALSE
ops <- FALSE

if (debug) rlang::inform('!!! debug mode ON')

# Script extracts all bed movements for patients moving through a particular ward
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
rlang::inform('!!! using star NOT ops')
input_schema <- 'star'
input_table <- 'bed_moves'
cols <- NULL

# Output
target_schema <- 'icu_audit'
target_table <- 'emapR_visit_detail_tower_icu'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Period of interest
period_min <- ymd_hms('2020-02-01 00:00:00')
period_max <- now()

# List the departments or wards that you wish to extract data for
wards_of_interest <- c(
  "UCH T03 INTENSIVE CARE"
  # ,
  # "UCH P03 CV",
  # "UCH T07 HDRU",
  # "WMS W01 CRITICAL CARE"
)


rlang::inform(paste('--- extracting bed moves for', paste(wards_of_interest, collapse=' | ')))

# Beds and Rooms that are non-census (i.e. patient doesn't actually occupy a bed)
# Hand crafted: needs verification
non_census <- c(
  "PATIENT OFFSITE",
  "HOLDING BAY",
  "POOL ROOM",
  "NONE",
  "WAIT",
  "THR",
  "ENDO",
  "ARRIVED",
  "DISCHARGE",
  "READY",
  "HOME",
  "VIRTUAL"
)

rlang::inform(paste('--- labelling as non-census', paste(non_census, collapse=' | ')))

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load bed moves
# ==============
rlang::warn('--- slow query; be patient')
rdt <- emapR::select_from(ctn, input_schema, input_table, cols = cols, limit=10)
setkey(rdt, mrn, admission)

# make a copy of the data so you can debug without having to re-run the query
wdt <- data.table::copy(rdt)
wdt <- wdt[admission > period_min & admission < period_max]

# define the discharge / end of observation for each mrn,csn; store
tdt[order(person_id,visit_occurrence_id), census_moves_i := seq_len(.N), by=.(person_id,visit_occurrence_id)]
tdt[, census_moves_N := .N, by=.(person_id,visit_occurrence_id)]

# census bed moves
csn_bm <- tdt

# Set-up census variable
setkey(wdt, visit_detail_id)
wdt[, critcare := department %in% wards_of_interest]
wdt[, census := TRUE]
wdt[bedisincensus == 'N' | is.na(bed) | (room %in% non_census) | (bed %in% non_census), census := FALSE]

# First find all MRNs that have been to a critical care area
mrn_csn <- unique(wdt[critcare == TRUE][,.(person_id,visit_occurrence_id)])
# Now use that list to filter *all* bed moves involving those patients
tdt <- wdt[mrn_csn, on=c("person_id", "visit_occurrence_id")][order(person_id,visit_occurrence_id)]

# Now collapse by department to appropriately define department level moves
rlang::inform('--- creating department level admission and discharge information')
udt <- emapR::collapse_over(tdt[census == TRUE],
                              col='department',
                              in_time='visit_start_datetime',
                              out_time='visit_end_datetime',
                              order_vars=c('person_id','visit_occurrence_id'),
                              group='visit_occurrence_id',
                              time_jump_window=dhours(8) # Arbitrary but join stays where less than 8 hours
)

# Now label up separate critical care stays
vdt <- unique(udt[critcare == TRUE, .(person_id,visit_occurrence_id,department,department_i)])
vdt[order(person_id,visit_occurrence_id,department_i), critcare_i := seq_len(.N), by=.(person_id,visit_occurrence_id)]
vdt <- vdt[,.(person_id,visit_occurrence_id,critcare_i,department_i)][udt, on=c("person_id", "visit_occurrence_id", "department_i")]

# Now join back on to tdt
tdt <- vdt[tdt, on=.NATURAL]

# Now join on CSN dates etc
tdt <- csn_bm[tdt, on=.NATURAL]

# setnames(tdt, 'admission', 'bed_admission')
# setnames(tdt, 'discharge', 'bed_discharge')

# number bed moves
tdt[order(person_id,visit_start_datetime), bed_i := seq_len(.N), by=.(person_id)]
setkey(tdt,visit_start_datetime)

# Write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing back to database', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')

