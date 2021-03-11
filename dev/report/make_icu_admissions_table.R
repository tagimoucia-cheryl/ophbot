# Steve Harris
# 2021-01-12
# Make a table of ICU admissions

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
rlang::inform('--- Build a table of ICU admissions then push to superset')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'icu_audit'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_icu_admissions'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load emap data at the visit detail and visit occurrence level
# =============================================================
dtvd <- emapR::select_from(ctn, input_schema, 'emapr_visit_detail' )
dtvo <- emapR::select_from(ctn, input_schema, 'emapr_visit_occurrence' )
dtp <- emapR::select_from(ctn, input_schema, 'emapr_person' )
covid <- emapR::select_from(ctn, input_schema, 'emapr_caboodle_covid' )

# prep critical care version of visit detail
dtvd
dtvd[,.N,by=visit_detail_source_value][order(-N)][1:30]
critical_care_wards <- c('T03', 'T03CV', 'P03CV', 'WSCC', 'MINQ', 'SINQ')
dtvd[visit_detail_source_value %in% critical_care_wards,
     .N,by=visit_detail_source_value][order(-N)]
dtvd[, critical_care := FALSE]
dtvd[visit_detail_source_value %in% critical_care_wards,
     critical_care := TRUE]


# visit detail
wdt <- dtvd[critical_care == TRUE,
            .(visit_occurrence_id,
               visit_detail_source_value,
               cc_start_datetime = visit_detail_start_datetime,
               cc_end_datetime = visit_detail_end_datetime,
               admitting_source_value = ward_lag1)]
wdt <- unique(wdt)
wdt <- wdt[!is.na(cc_start_datetime)]
wdt

# merge covid onto visit_occurrence
str(covid)
str(dtvo)
# FIXME csn in COVID is character ?why
dtvo[, csn := as.integer(csn)]
dtvo <- covid[,.(csn,covid01)][dtvo, on='csn']
dtvo[is.na(covid01), covid01 := FALSE]

janitor::tabyl(dtvo, covid01)

# merge on visit_occurrence
tdt <- dtvo[,.(visit_occurrence_id, person_id, discharge_disposition, visit_start_datetime, visit_end_datetime, covid01 )]
setkey(wdt, visit_occurrence_id)
setkey(tdt, visit_occurrence_id)
wdt <- tdt[wdt]

# merge on person
tdt <- dtp[,.(person_id, gender_source_value, birth_datetime, death_datetime, person_source_value)]
setkey(wdt, person_id)
setkey(tdt, person_id)
wdt <- tdt[wdt]
wdt

# FIXME hack to drop COVID before March 2020!
wdt[cc_start_datetime <= ymd('2020-03-01'), covid01 := FALSE]
# simple calcs
wdt[, age_at_cc_start := (cc_start_datetime - birth_datetime)/dyears(1)]
wdt[, icu_los := (cc_end_datetime - cc_start_datetime)/ddays(1)]
# death
janitor::tabyl(wdt, discharge_disposition)
wdt[!is.na(death_datetime)]
wdt[, icu_death := FALSE]
wdt[!is.na(death_datetime), icu_death := ifelse((death_datetime - cc_end_datetime)/ddays(1) < 3, TRUE, icu_death)]
janitor::tabyl(wdt, icu_death)
wdt[, hosp_death := FALSE]
wdt[!is.na(death_datetime), hosp_death := ifelse((death_datetime - visit_end_datetime)/ddays(1) < 3, TRUE, hosp_death)]
janitor::tabyl(wdt, hosp_death)

# Likely external transfer
wdt[, external_transfer := FALSE]
wdt[is.na(admitting_source_value), external_transfer := TRUE]
janitor::tabyl(wdt, external_transfer)

# Better: write this back to the icu_audit schema (rather than saving locally)

rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
# rlang::inform('--- closing database connection')
# rlang::inform('--- script completed')


