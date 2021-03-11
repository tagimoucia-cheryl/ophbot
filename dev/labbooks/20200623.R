# Steve Harris
# 2020-06-23
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

query <- "SELECT * FROM icu_audit.now"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt)

# Current inpatients
tdt <- dt[is.na(discharge) & critcare == TRUE & department == "UCH T03 INTENSIVE CARE"]
tdt[order(bed)]

# query to find vital signs for ICU patients
query <- "
SELECT 
	e.encounter,
	pf.patient_fact_id,
	pf.fact_type,
	att.short_name,
	pp.patient_property_id,
		pp.property_type,
	pp.value_as_datetime,
	pp.value_as_integer,
	pp.value_as_link,
	pp.value_as_real,
	pp.value_as_string,
	pp.value_as_attribute,
	att_prop.short_name
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
		pf.fact_type = 44
		AND 
		pf.valid_until IS NULL AND pf.stored_until IS NULL
		AND 
		pp.valid_until IS NULL AND pp.stored_until IS NULL
"

dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt,10)

tdt <- dt[1:1e5]
janitor::tabyl(tdt[short_name == 'VIT_OBS_ID']$value_as_string)

tdt

tdt_real <- data.table::dcast(dt[,.(encounter, patient_fact_id, short_name, value_as_datetime, value_as_real)]
                  , encounter + patient_fact_id ~ short_name,
                  value.var = list("value_as_datetime", "value_as_real"))[
                    ,.(encounter,
                       patient_fact_id,
                       ts = value_as_datetime_VIT_OBS_TIME,
                       val_real = value_as_real_VIT_NUM_VALUE)
                  ]
tdt_string <- data.table::dcast(dt[,.(encounter, patient_fact_id, short_name, value_as_datetime, value_as_string)]
                              , encounter + patient_fact_id ~ short_name,
                              value.var = list("value_as_datetime", "value_as_string"))[
                                ,.(encounter,
                                   patient_fact_id,
                                   ts = value_as_datetime_VIT_OBS_TIME,
                                   concept = value_as_string_VIT_OBS_ID,
                                   unit = value_as_string_VIT_UNIT,
                                   val_string = value_as_string_VIT_STR_VALUE)
                                ]
tdt_string

setkey(tdt_string, "encounter", "patient_fact_id", "ts")
setkey(tdt_real, "encounter", "patient_fact_id", "ts")

tdt <- tdt_string[tdt_real]
tdt[, now := now()]

audit_dict <- readr::read_tsv('data/audit_master.txt')
setDT(audit_dict)
audit_dict

caboodle_keys1 <- audit_dict[!is.na(epic_id), .(name_short, concept = paste0('caboodle$', epic_id))]
caboodle_keys2 <- audit_dict[!is.na(id_caboodle), .(name_short, concept = paste0('caboodle$', id_caboodle))]
epic_keys <- audit_dict[!is.na(epic_id), .(name_short, concept = paste0('EPIC$', epic_id))]
concept_keys <- data.table::rbindlist(list(caboodle_keys1,caboodle_keys2,epic_keys))
concept_keys
tdt <- concept_keys[tdt, on="concept"]


tdt <- tdt[,.(
  encounter, patient_fact_id,
  ts, concept,
  name_short,
  val_string,
  val_real,
  unit,
  now
)]
tdt

fwrite(tdt, file="data/secure/critical_care_vitals.csv")

# Better: write this back to the icu_audit schema (rather than saving locally)
table_path <- DBI::Id(schema="icu_audit", table="now_vitals")
DBI::dbWriteTable(ctn, name=table_path, value=tdt, overwrite=TRUE)

tdt[order(-ts)]
stop()

# convert long to wide
# first create an EAV spine
# dtu <- tdt[short_name == 'VIT_OBS_ID' | short_name == 'VIT_OBS_TIME']
dtu <- tdt[short_name == 'VIT_OBS_TIME',.(encounter,patient_fact_id,ts=value_as_datetime)]
dtu <- tdt[short_name == 'VIT_OBS_ID',.(encounter,patient_fact_id,value_as_string)][dtu, on=c("encounter", "patient_fact_id")]
dtu <- dtu[,.(encounter,ts,patient_fact_id,attribute=value_as_string)]
dtu

lab_o2_delivery <- "caboodle$3040109305"
lab_rass <- "caboodle$3040104644"

setkey(dtu, "encounter", "patient_fact_id")


# eav for numerics
dtv <- tdt[short_name == 'VIT_NUM_VALUE',.(encounter,patient_fact_id,value_as_real)]
setkey(dtv, "encounter", "patient_fact_id")

dtv[dtu][attribute==lab_rass]


# eav for numeric plus units
dtv <- tdt[short_name == 'VIT_NUM_VALUE' | short_name == 'VIT_UNIT',.(encounter,patient_fact_id,value_as_real,value_as_string)]
setkey(dtv, "encounter", "patient_fact_id")
dtv


dtv <- dtu[tdt[!is.na(value_as_string) & length(value_as_string) > 0
  ,.(encounter,patient_fact_id,value_as_string)]][attribute == lab_o2_delivery][1:30]

dtv
dtv[, foo := length(value_as_string),
    by=.(encounter,ts,patient_fact_id,attribute)]

dtv


# dcast.data.table(dtu[1:4], encounter + value_as_datetime ~ short_name, value.var = c('value_as_string') )



dtu[!is.na(value_as_datetime)][1:30]



# 
# query <- "SELECT * FROM icu_audit.now"
# dt <- DBI::dbGetQuery(ctn, query)
# setDT(dt)
# head(dt,10)
# 
# query <- "SELECT * FROM icu_audit.now_vitals"
# dtv <- DBI::dbGetQuery(ctn, query)
# setDT(dtv)
# head(dtv,10)
# 



# tdt <- data.table::copy(dt[1:1e5])
tdt




vitals <- c('hrate', 'rrate', 'spo2', 'bp', 'fio2', 'o2_flow_rate', 'o2_delivery_device', 'temperature')
vitals <- tdt[name_short %in% vitals]
vitals[, now := now()]
fwrite(vitals, file="data/secure/critical_care_vitals.csv")


# Better: write this back to the icu_audit schema (rather than saving locally)
table_path <- DBI::Id(schema="icu_audit", table="now_vitals")
DBI::dbWriteTable(ctn, name=table_path, value=tdt, overwrite=TRUE)

stop()

library(stringr)

# just checking the naming
tdt <- fread(file="data/secure/critical_care_vitals.csv")
tdt[, source := str_extract(concept, "^.*?(?=\\$)")]

tdt[, .N, by = .(name_short)]

View(tdt[, .N, by = .(name_short, concept)])
View(tdt[, .(min=min(ts), max=max(ts)), by=.(concept,source)])

hrate <- tdt[name_short == 'hrate']
min(hrate$ts); max(hrate$ts)
rrate <- tdt[name_short == 'rrate']
min(rrate$ts); max(rrate$ts)
tail(rrate)

vitals <- c('hrate', 'rrate', 'spo2', 'bp', 'fio2', 'o2_flow_rate', 'o2_delivery_device', 'temperature')
vitals <- tdt[name_short %in% vitals]
vitals
