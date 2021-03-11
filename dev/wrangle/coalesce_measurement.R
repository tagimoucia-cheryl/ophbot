# Steve Harris
# 2020-07-07
# Collapse down measurments for ICU patients into a HIC style structure for analysis

rlang::inform('--- script starting')
# debugging?
debug <- FALSE
if (debug) rlang::inform('--- debug mode ON')

# Libraries
library(lubridate)
library(data.table)
# Note the order here is important; for now, we want the guidEHR process function to mask the inspectEHR one
library(inspectEHR)   # 1.
rlang::inform('--- loading emapR over inspectEHR to take advantage of updated extract function')
# devtools::reload(pkgload::inst('emapR'))
library(emapR)      # 2. see setup.R for installation

# TODO: Move these over to your package (and then deliberately overwrite
# inspectEHR::extract with guidEHR::extract)
# source('utils/extract.R')

# Connect to the UDS using environment vars
udsConnect()

# *************
# Configuration
# *************
icu_schema <- 'icu_audit'
ops_schema <- 'ops_b'
results_table <- 'sh_long24'

# arg to switch to choose which visits to work with
visit_occurrence_ids <- NULL

# cadence for resulting table
cadence <-  24

# measurements and observations
wishlist <- setDT(readr::read_csv('config/wishlist_measurement.csv'))
wishlist <- wishlist[wishlist==1]
assertthat::assert_that(anyDuplicated(wishlist$concept_id) == 0)
assertthat::assert_that(anyDuplicated(wishlist$concept_id) == 0)

# define functions based on domain
rlang::inform('--- reading concept_mappings icu_audit.concept_icu')
concepts <- guidEHR::select_star_from(ctn, icu_schema, table_concepts )
str(concepts)
cdt <- unique(concepts[,.(concept_id, domain_id)][wishlist, on='concept_id', nomatch=0])
cdt[, func := '']
cdt[domain_id=='Measurement', func := 'median']
cdt[domain_id=='Observation', func := 'first']

# define anchor time as ICU admission time
vo <- select_from(ctn, icu_schema, 'icu_admissions', cols=c('visit_occurrence_id', 'icu_admission'))

# Run extract
res <- emapR::extract(
 connection = ctn,
 target_schema = ops_schema,
 visit_occurrence_ids = vo$visit_occurrence_id,
 anchor_times = vo$icu_admission,
 concept_ids = cdt$concept_id,
 concept_short_names  = cdt$name_short,
 coalesce_rows = cdt$func,
 cadence = cadence
 )

# Just data from ICU admission onwards
str(res)
res_icu <- res[diff_time>0]

target_table_path <- DBI::Id(schema=icu_schema, table=results_table)
DBI::dbWriteTable(ctn, name=target_table_path, value=res_icu, overwrite=TRUE)

udsDisconnect()









