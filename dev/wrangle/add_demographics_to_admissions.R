# Steve Harris
# 2020-07-02

# Load libraries
library(lubridate) # not part of tidyverse
library(data.table)

# *************
# Configuration
# *************

debug <- FALSE
check_caboodle <- TRUE # join against reported caboodle info

# Script joins on hospital and visit level facts from EMAP to the existing list of ICU admissions
# and then (optionally) runs checks and cross compares against caboodle

# Input: icu_admissions: 1 row per admission
input_table <- 'uds.icu_audit.icu_admissions'

# Output: uds.icu_audit.icu_admissions_pid
target_schema <- 'icu_audit'
target_table <- 'icu_admissions_pid'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)
target_table_path_check_caboodle <- DBI::Id(schema=target_schema, table=paste0(target_table, '_check'))


# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")


# Load bed moves
# ==============
query <- paste("SELECT * FROM", input_table)
rdt <- DBI::dbGetQuery(ctn, query)
setDT(rdt)
setkey(rdt,mrn,csn)

wdt <- data.table::copy(rdt)

# Load demographics (from star)
# =================
query <- "
SELECT 
	e.encounter,
	pf.fact_type,
	att.short_name,
	pp.patient_property_id,
	pp.value_as_datetime,
	pp.value_as_integer,
	pp.value_as_link,
	pp.value_as_real,
	pp.value_as_string,
	pp.value_as_attribute,
	att_prop.short_name property_name
	FROM star.patient_property pp
	JOIN star.patient_fact pf
	ON pp.fact = pf.patient_fact_id
	JOIN star.encounter e 
	ON pf.encounter = e.encounter_id 
	LEFT JOIN star.attribute att
	ON pp.property_type = att.attribute_id
	LEFT JOIN star.attribute att_prop
	ON pp.value_as_attribute = att_prop.attribute_id
	JOIN 
	  (SELECT DISTINCT csn FROM icu_audit.icu_admissions) icu
		ON e.encounter = icu.csn
	WHERE 
		pf.fact_type IN (4, 11, 60) 
		AND 
		pf.valid_until IS NULL AND pf.stored_until IS NULL
		AND 
		pp.valid_until IS NULL AND pp.stored_until IS NULL
"

rlang::warn('--- slow(ish) query; be patient')
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)

tdt <- data.table::copy(wdt)
tdt <- dt[short_name=='L_NAME',.(encounter,name_last=value_as_string)][tdt, on=c('encounter==csn')]
tdt <- dt[short_name=='F_NAME',.(encounter,name_first=value_as_string)][tdt, on=c('encounter==encounter')]
tdt <- dt[short_name=='SEX',.(encounter,sex=property_name)][tdt, on=c('encounter==encounter')]
tdt <- dt[short_name=='DOB',.(encounter,dob=value_as_datetime)][tdt, on=c('encounter==encounter')]
tdt <- dt[short_name=='DEATH_TIME',.(encounter,dod=value_as_datetime)][tdt, on=c('encounter==encounter')]
tdt <- dt[short_name=='DEATH_INDICATOR',.(encounter,dead=property_name=='BOOLEAN_TRUE')][tdt, on=c('encounter==encounter')]

# Now try and join on hospital visit details
query <- "
SELECT 
	e.encounter,
	pf.encounter AS encounter_id,
	pf.parent_fact,
	att.short_name,
	pp.patient_property_id,
	pp.value_as_datetime,
	pp.value_as_integer,
	pp.value_as_link,
	pp.value_as_real,
	pp.value_as_string
	FROM star.patient_property pp
	JOIN star.patient_fact pf
	ON pp.fact = pf.patient_fact_id
	JOIN star.encounter e 
	ON pf.encounter = e.encounter_id 
	LEFT JOIN star.attribute att
	ON pp.property_type = att.attribute_id
	JOIN 
	  (SELECT DISTINCT csn FROM icu_audit.icu_admissions) icu
		ON e.encounter = icu.csn
	WHERE 
		pf.fact_type = 5 
		AND 
		pf.valid_until IS NULL AND pf.stored_until IS NULL
		AND 
		pp.valid_until IS NULL AND pp.stored_until IS NULL
"

dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt)

# Drop the derived hospital admission and discharge times calculated via the bed moves
# Use the reported values stored here instead
tdt[, hospital_admission := NULL]
tdt[, hospital_discharge := NULL]
tdt <- dt[short_name=='ARRIVAL_TIME',.(encounter,hospital_admission=value_as_datetime)][tdt, on=c('encounter==encounter')]
tdt <- dt[short_name=='DISCH_TIME',.(encounter,hospital_discharge=value_as_datetime)][tdt, on=c('encounter==encounter')]
tdt

# divide by duration so can store in sql as numeric
tdt[, hosp_los := difftime(hospital_discharge, hospital_admission, units="days") / ddays(1) ]
tdt[, icu_los := difftime(icu_discharge, icu_admission, units="days") / ddays(1) ]
tdt
setnames(tdt, 'encounter', 'csn')

# Better: write this back to the icu_audit schema (rather than saving locally)
DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)

if (check_caboodle) {
  query <- "SELECT * FROM uds.icu_audit.patient_encounter"
  caboodle_icu <- DBI::dbGetQuery(ctn, query)
  setDT(caboodle_icu)
  caboodle_icu[, pat_enc_csn_id := as.character(pat_enc_csn_id)]
  setnames(caboodle_icu, 'pat_enc_csn_id', 'csn')  
  setnames(caboodle_icu, 'pat_mrn_id', 'mrn')  
  udt <- caboodle_icu[tdt, on=c('mrn', 'csn')]
  udt
  colnames(udt)
  vdt <- udt[,.(
    mrn,
    csn,
    pat_name,
    name_last,
    name_first,
    name_last_ok = stringr::str_extract(pat_name, "^.*?(?=,)") == name_last,
    # FIXME: R mangles the dates on import; ignore for now
    # birth_date,
    # dob,
    sex,
    sex_emap = i.sex,
    sex_ok = toupper(sex) == i.sex,
    inpatient_admission_dttm,
    hospital_admission,
    hospital_admission_ok = abs(difftime(hospital_admission, inpatient_admission_dttm, units="hours") / dhours(1)) < 1,
    inpatient_discharge_dttm,
    hospital_discharge,
    hospital_discharge_ok = abs(difftime(hospital_discharge, inpatient_discharge_dttm, units="hours") / dhours(1)) < 1,
    discharge_status,
    dead,
    dead_ok = dead == stringr::str_detect(discharge_status, 'Died'),
    death_date,
    dod,
    dod_ok = abs(difftime(dod, as.Date(death_date), units="hours") / ddays(1)) < 1
  )]
  DBI::dbWriteTable(ctn, name=target_table_path_check_caboodle, value=vdt, overwrite=TRUE)
  
}

DBI::dbDisconnect(ctn)
