# Steve Harris
# created 2021-01-24

rlang::warn('!!! Needs to be refactored so that visit detail works as per functional area')
# TODO: perhaps drop down to ward level moves?
# TODO: then add on functional level movements using location_attribute?

# Create one row per ICU admission (starting with the location_visit table) and
# - [ ] NOTE this is achieved with the pre-canned view cc_filter
# filtering where the patients have been to an ICU
# then set this up to appear like an OMOP visit_detail table

# ****
# TODO
# ****
# - [ ] TODO edge case of  MRN 41017935 inpatient->ct->fits->resus->returns to ward
#       need to fix the non-census move to ED before returning to the ward
#       ?just define ED as a non-census area so moves in and out don't count
# - [ ] TODO fix ghosts; perhaps just truncate a bed stay if you can't find death or hospital discharge to use
# - [ ] TODO abstract out the schema references


# *************
# Running notes
# *************
# 2021-01-25 rebuilt at the ward level

# Libraries
library(lubridate)
library(data.table)
library(emapR) # see setup.R for installation
library(assertthat)

# *************
# Configuration
# *************
rlang::inform('--- Starting to build VISIT_DETAIL table')

DEBUG <- FALSE
if (DEBUG) rlang::warn('!!! debug mode ON')
HAND_CORRECT <- TRUE
if (HAND_CORRECT) rlang::warn('!!! hand correction mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_a'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_visit_detail'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()


# Load bed moves
# ==============
# - [ ] TODO rebuild directly from location_visit
# 2021-01-25 note this might not scale; already slow to load
query <- "
SELECT 
   vd.hospital_visit_id       visit_occurrence_id
  ,ip.core_demographic_id     person_id
  ,vd.admission_time          
  ,vd.discharge_time          
  ,loc.location_string
FROM star_a.location_visit vd
LEFT JOIN star_a.location loc ON vd.location_id = loc.location_id
RIGHT JOIN icu_audit.emapr_inpatient_filter ip ON vd.hospital_visit_id = ip.hospital_visit_id
;
"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
wdt <- data.table::copy(dt)

# FIXME 2021-01-25 patients in the inpatient filter that appear to have no visit detail info
chk <- nrow(wdt[is.na(visit_occurrence_id)])
if (chk) rlang::warn(paste('---', chk, 'inpatients found without visit detail data'))
wdt <- wdt[!is.na(visit_occurrence_id)]

# Collapse to ward level moves
# Bring in ward info from location_attribute
ldt <- emapR::select_from(ctn, target_schema, 'emapr_location_attribute')
wards <- unique(ldt[attribute_name == 'ward', .(location_string, ward = value_as_text)])
wdt <- wards[wdt, on='location_string']
assert_that(nrow(wdt[is.na(location_string)]) == 0)

rlang::warn('-- slow operations even in memory')
# create a ward move level counter
setkey(wdt, visit_occurrence_id, admission_time, discharge_time)
wdt[, ward_i := rleid(ward), by=visit_occurrence_id ]
wdt[, visit_detail_start_datetime := min(admission_time), by=.(visit_occurrence_id, ward_i)]
wdt[, visit_detail_end_datetime := max(discharge_time), by=.(visit_occurrence_id, ward_i)]

# now drop all within ward moves by taking unique of the subset of ward level columns
wdt <- unique(wdt[, .(person_id, visit_occurrence_id, ward, visit_detail_start_datetime, visit_detail_end_datetime)])
wdt

# checks
assert_that( nrow(wdt[is.na(visit_detail_start_datetime)]) == 0)

# clean
# derive lead and lag wards
setkey(wdt, visit_occurrence_id, visit_detail_start_datetime)
wdt[, ward_lag1 := shift(ward, type='lag', n=1), by=.(visit_occurrence_id)]
wdt[, ward_lead1 := shift(ward, type='lead', n=1), by=.(visit_occurrence_id)]

# choice:
# (a) don't collapse to ward level moves else you'll lose the original
# location_visit_id key but now store ward as the visit_detail unit accepting
# that you have duplicate rows? (b) drop the original key; trust you can recover
# through visit_occurrence go with (b) for now
names(wdt)
wdt <- wdt[,.(
   visit_detail_id = NA_integer_
  ,person_id
  ,visit_detail_concept_id = NA_integer_
  ,visit_detail_start_date =  lubridate::date(visit_detail_start_datetime)
  ,visit_detail_start_datetime 
  ,visit_detail_end_date =  lubridate::date(visit_detail_end_datetime)
  ,visit_detail_end_datetime 
  ,visit_detail_type_concept_id = 44818518 # derived from EHR
  ,provider_id = NA_integer_
  ,care_site_id = NA_integer_ # should be location_id but create duplicate rows
  ,visit_detail_source_value = ward
  ,visit_detail_source_concept_id = NA_integer_
  ,admitting_source_value = NA_character_ 
  ,admitting_source_concept_id = NA_integer_
  ,discharge_to_source_value = NA_character_
  ,discharge_to_source_concept_id = NA_integer_
  ,preceding_visit_detail_id = NA_integer_
  ,visit_occurrence_id
  ,ward_lag1
  ,ward_lead1
) ]
setkey(wdt, person_id, visit_occurrence_id, visit_detail_start_datetime)
wdt[, visit_detail_id := .I]
wdt

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


