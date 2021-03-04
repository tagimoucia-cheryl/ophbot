# Steve Harris
# 2021-01-25
# Make a table of ward level admissions (i.e. start from visit_detail)
# then hang off that table certain 'hospital visit' level attributes

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
rlang::inform('--- Build a table of ward admissions then push to superset')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

input_schema <- 'icu_audit'

# Output: uds.icu_audit.emapr_niv_admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_ward_admissions'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load emap data at the visit detail and visit occurrence level
# ==========================================================
# dtvd <- emapR::select_from(ctn, input_schema, 'emapr_visit_detail_niv' )

dtvo <- emapR::select_from(ctn, input_schema, 'emapr_visit_occurrence' )
dtvd <- emapR::select_from(ctn, input_schema, 'emapr_visit_detail' )
dtp <- emapR::select_from(ctn, input_schema, 'emapr_person' )
covid <- emapR::select_from(ctn, input_schema, 'emapr_caboodle_covid' )
icu <- emapR::select_from(ctn, input_schema, 'emapr_cc_filter' )
niv <- emapR::select_from(ctn, input_schema, 'emapr_niv_filter' )

# merge covid onto visit_occurrence
str(covid)
str(dtvo)
# FIXME csn in COVID is character ?why
dtvo[, csn := as.integer(csn)]
dtvo <- covid[,.(csn,covid01)][dtvo, on='csn']
dtvo[is.na(covid01), covid01 := FALSE]

janitor::tabyl(dtvo, covid01)

# start wtih visit occurrence
wdt <- dtvo[,.(visit_occurrence_id, person_id, discharge_disposition, visit_start_datetime, visit_end_datetime, covid01 )]

# merge on person
tdt <- dtp[,.(person_id, gender_source_value, birth_datetime, death_datetime, person_source_value)]
setkey(wdt, person_id)
setkey(tdt, person_id)
wdt <- tdt[wdt]
wdt

# merge on niv
tdt <- niv[,.(visit_occurrence_id = hospital_visit_id, niv = TRUE)]
setkey(wdt, visit_occurrence_id)
setkey(tdt, visit_occurrence_id)
wdt <- tdt[wdt]
wdt[is.na(niv), niv := FALSE]
wdt
janitor::tabyl(wdt$niv)

# merge on icu
tdt <- icu[,.(visit_occurrence_id = hospital_visit_id, critical_care = TRUE)]
setkey(wdt, visit_occurrence_id)
setkey(tdt, visit_occurrence_id)
wdt <- tdt[wdt]
wdt[is.na(critical_care), critical_care := FALSE]
wdt
janitor::tabyl(wdt$critical_care)


wdt[, age_at_hosp_start := (visit_start_datetime - birth_datetime)/dyears(1)]
wdt[, hosp_los := (visit_end_datetime - visit_start_datetime)/ddays(1)]
# death
janitor::tabyl(wdt, discharge_disposition)
wdt[!is.na(death_datetime)]
wdt[, hosp_death := FALSE]

wdt[!is.na(death_datetime), hosp_death := ifelse
    ((death_datetime - visit_end_datetime)/ddays(1) < 3
      &
     (death_datetime >= visit_start_datetime)
      , TRUE, hosp_death)]
janitor::tabyl(wdt, hosp_death)


# now merge this on to ward level visit_detail
tdt <- dtvd[,.(visit_detail_source_value, 
               visit_detail_start_datetime,
               visit_detail_end_datetime,
               visit_occurrence_id)]
wdt <- wdt[tdt, on='visit_occurrence_id']

# Better: write this back to the icu_audit schema (rather than saving locally)
wdt

rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
# rlang::inform('--- closing database connection')
# rlang::inform('--- script completed')


