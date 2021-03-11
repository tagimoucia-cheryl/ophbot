# Steve Harris
# 2020-06-22
# Let's assume that CSNs identify an encounter episode; so now use this to extract other hospital level information

# Load libraries
library(tidyverse)
library(lubridate) # not part of tidyverse
library(RPostgres)
# YMMV but I use data.table much more than tidyverse; Apologies if this confuses
library(data.table)
library(assertthat)

ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")

# Re-run the code to generate an up-to-date view of bed moves
source('wrangle/create_bed_moves.R')
query <- "SELECT * FROM icu_audit.bed_moves"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt)

# Current inpatients
tdt <- dt[critcare == TRUE & department == "UCH T03 INTENSIVE CARE"]
# tdt <- dt[is.na(discharge) & critcare == TRUE & department == "UCH T03 INTENSIVE CARE"]
tdt[order(bed)]

# Load demographics
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
	  (SELECT DISTINCT csn FROM icu_audit.bed_moves) icu
		ON e.encounter = icu.csn
	WHERE 
		pf.fact_type IN (4, 11, 60) 
		AND 
		pf.valid_until IS NULL AND pf.stored_until IS NULL
		AND 
		pp.valid_until IS NULL AND pp.stored_until IS NULL
"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt,10)

tdt <- dt[short_name=='L_NAME',.(encounter,name_last=value_as_string)][tdt, on=c('encounter==csn')][order(bed)]
tdt <- dt[short_name=='F_NAME',.(encounter,name_first=value_as_string)][tdt, on=c('encounter==encounter')][order(bed)]
tdt <- dt[short_name=='SEX',.(encounter,sex=property_name)][tdt, on=c('encounter==encounter')][order(bed)]
tdt <- dt[short_name=='DOB',.(encounter,dob=value_as_datetime)][tdt, on=c('encounter==encounter')][order(bed)]
tdt <- dt[short_name=='DEATH_TIME',.(encounter,dod=value_as_datetime)][tdt, on=c('encounter==encounter')][order(bed)]
tdt <- dt[short_name=='DEATH_INDICATOR',.(encounter,dead=property_name=='BOOLEAN_TRUE')][tdt, on=c('encounter==encounter')][order(bed)]
tdt

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
	  (SELECT DISTINCT csn FROM icu_audit.bed_moves) icu
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

tdt <- dt[short_name=='ARRIVAL_TIME',.(encounter,admission_hosp=value_as_datetime)][tdt, on=c('encounter==encounter')][order(bed)]
tdt <- dt[short_name=='DISCHARGE_TIME',.(encounter,discharge_hosp=value_as_datetime)][tdt, on=c('encounter==encounter')][order(bed)]

tdt[, now := now()]
fwrite(tdt, file="data/secure/critical_care_now.csv")

# Better: write this back to the icu_audit schema (rather than saving locally)
table_path <- DBI::Id(schema="icu_audit", table="now")
DBI::dbWriteTable(ctn, name=table_path, value=tdt, overwrite=TRUE)
