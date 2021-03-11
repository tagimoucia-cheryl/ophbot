# Steve Harris
# created 2021-01-03 
# derived from create_icu_admissions

# Create one row per patient (starting with the location_visit table) and
# filtering where the patients have been to an ICU
# then set this up to appear like an OMOP patients table

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
rlang::inform('--- Starting to build ICU patients table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Script collapses all patients assuming that they are unique based on ...
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_test'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapR_patients'
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
	 vd.hospital_visit_id 
	,mrn.mrn
	,mrn.nhs_number
	,p.firstname
	,p.lastname
	,p.home_postcode
	,p.alive
	,p.date_of_birth
	,p.date_of_death
	,p.sex
	,vo.encounter
	,vo.patient_class
	,vo.admission_time
	,vo.discharge_time
	,vo.arrival_method
	,vo.discharge_destination
	,vo.discharge_destination
	,vo.presentation_time
	,vo.mrn_id
FROM star_test.location_visit vd 
LEFT JOIN flow.location loc ON vd.location_id = loc.location_id 
LEFT JOIN star_test.hospital_visit vo ON vd.hospital_visit_id = vo.hospital_visit_id
LEFT JOIN star_test.core_demographic p ON vo.mrn_id = p.mrn_id
LEFT JOIN star_test.mrn_to_live ON p.mrn_id = mrn_to_live.mrn_id
LEFT JOIN star_test.mrn ON mrn_to_live.live_mrn_id = mrn.mrn_id
WHERE loc.critical_care = true
;
"

# - [ ] TODO make this compatible w emapR::select_from by working out how to specify query
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
rdt <- data.table::copy(dt)
wdt <- unique(dt[,.(mrn,nhs_number,firstname,lastname,home_postcode,date_of_birth,date_of_death,sex)])
# check for duplicate hospital numbers
wdt[, mrn_N := .N, by=.(firstname,lastname,date_of_birth,sex)]
assertthat::assert_that(nrow(wdt[mrn_N>1]) == 0, msg = 'duplicate MRNs by first/lastname/DoB/Sex')
wdt[, mrn_N := NULL]
wdt[, age_at_death := as.numeric(difftime(date_of_death, date_of_birth, units = 'days'))/365.25]
wdt[order(-date_of_death)]

# - [ ] TODO abstract this messy section out; add error checking for each variable
# extract postcodes
pcodes <- unique(wdt$home_postcode)
llen <- length(pcodes)
i <- 1; sstep <- 100; results <- list()
while (i < llen) {
  sstart <- i
  sstop <- i + sstep - 1
  if (sstop > llen) sstop <- llen
  these_pcodes <- PostcodesioR::bulk_postcode_lookup(list(postcodes=pcodes[sstart:sstop]))
  # print(these_pcodes)
  results <- append(results, these_pcodes) 
  i <- i + sstep
}


bulk_list <- lapply(results, "[[", 2)
bulk_list[[1]]
postcodes <-
  bulk_list %>% 
  keep(function(x) !is.null(x$quality)) %>% 
  keep(function(x) x$quality == 1) %>% 
  map_dfr(function(x) list(
    'postcode'=x$postcode, 
    'longitude'=x$longitude, 
    'latitude'=x$latitude, 
    'lsoa'=x$lsoa, 
    'gss_district'=x$codes$admin_district,
    'gss_county'=x$codes$admin_county
    ))


setDT(postcodes)
postcodes

# 2021-01-08 found a lookup for postcode to ISO-3166:2
# see https://github.com/academe/UK-Postcodes.git
# note it's a bit out of date
iso_lookup <- read.csv('data/county_iso3166_2_gb.csv', stringsAsFactors = FALSE)
setDT(iso_lookup)
iso_lookup <- iso_lookup[
  !is.na(iso_code) & nchar(iso_code)>0,.(
      name,
      iso_code,
      gss_code,
      uk_region_gss_code)]
iso_lookup

# counties
# check first with devon
# iso_lookup[gss_code=='E10000008']
# postcodes[gss_county=='E10000008']

postcodes <- iso_lookup[,.(name_county=name,
                           iso_code_county=iso_code,
                           gss_county=gss_code
                           )][
                         postcodes, on='gss_county']
postcodes


# district
# check first with enfield
# iso_lookup[gss_code=='E09000010']
# postcodes[gss_district=='E09000010']

postcodes <- iso_lookup[,.(name_district=name,
                           iso_code_district=iso_code,
                           gss_district=gss_code
                           )][
                         postcodes, on='gss_district']
postcodes
postcodes[, iso_code := NULL]
postcodes[, iso_code := iso_code_county]
postcodes[, iso_code := ifelse(is.na(iso_code_county) & !is.na(iso_code_district), iso_code_district, iso_code)]
-- warn

chk <- nrow(postcodes[is.na(iso_code)])
if (chk) rlang::inform(paste('!!! missing', chk, 'iso_codes'))
postcodes <- postcodes[,.(postcode,longitude,latitude,lsoa,iso_code,name_district,name_county)]
postcodes[is.na(iso_code)]

# - [ ] TODO download the full table from the docker image and load here
# save to avoid hitting the PostcodesIO too often
saveRDS(postcodes,file='data/pcode_df.rds')

wdt <- postcodes[wdt,on="postcode==home_postcode"]
wdt

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


