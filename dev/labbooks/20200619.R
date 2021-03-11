# Steve Harris
# 2020-06-19
# Let's assume that CSNs identify an encounter episode; so now use this to extract other hospital level information

# Load libraries
library(tidyverse)
library(lubridate) # not part of tidyverse
library(RPostgres)
# YMMV but I use data.table much more than tidyverse; Apologies if this confuses
library(data.table)
library(assertthat)

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

ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")

dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt)

# FIXME
# So we have some CSNs associated with multiple hospital admission and discharge times
# Prepare a table of encounters and hospital arrival and discharge times
tdt <- dt[short_name %in% c('ARRIVAL_TIME', 'DISCH_TIME'),.(patient_property_id, encounter, short_name,value_as_datetime )]
tdt[order(encounter,value_as_datetime), i:=seq_len(.N), by=.(encounter, short_name)]

udt <- unique(tdt[i>1,.(encounter)])[tdt, on="encounter", nomatch=0]
udt <- udt[order(encounter,short_name,value_as_datetime)]
udt[, sd := sd(value_as_datetime), by=.(encounter, short_name)]
udt[sd > 0]


# For now label those with dups, and then drop them / return missing
tdt <- data.table::dcast(tdt,
                         encounter + i ~ short_name,
                         fun=list(min, max),
                         value.var=c('value_as_datetime'))
tdt <- tdt[,.(encounter, i, value_as_datetime_min_ARRIVAL_TIME,value_as_datetime_max_DISCH_TIME)]
setnames(tdt, 'value_as_datetime_min_ARRIVAL_TIME', 'admission_hosp')
setnames(tdt, 'value_as_datetime_max_DISCH_TIME', 'discharge_hosp')

janitor::tabyl(tdt$i)

tdt[,imax:=max(i),by=encounter]
tdt <- tdt[imax==1,.(encounter,admission_hosp,discharge_hosp)]
tdt_hosp_visit <- data.table::copy(tdt)



# Prepare a table of encounters and associated facts about hospital visits
janitor::tabyl(dt$short_name)
short_names <- c("DISCH_DISP", "DISCH_LOCATION", "PATIENT_CLASS")
tdt <- dt[short_name %in% short_names,.(patient_property_id, encounter, short_name,value_as_string )]
tdt[order(encounter), i:=seq_len(.N), by=.(encounter, short_name)]
# Similar problem to the above scenario; so replace with missing to avoid errors
tdt[encounter %in% unique(tdt[i>1,encounter]), value_as_string := NA]
tdt[i>1]
tdt[, i:= NULL]
tdt[, patient_property_id:= NULL]
tdt <- unique(tdt)
# Now you have unique data with missingness and therefore no need to choose an aggregate function

# For now label those with dups, and then drop them / return missing
tdt <- data.table::dcast(tdt,
                         encounter ~ short_name,
                         value.var='value_as_string')

tdt_hosp_facts <- data.table::copy(tdt)
tdt <- merge(tdt_hosp_facts, tdt_hosp_visit, all=TRUE)

# Finally pull in ICU visits and join together so you have a one row per ICU visit table
query <- "SELECT * FROM icu_audit.bed_moves"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
head(dt)

# Capture prev and subsequent departments
dt[order(mrn,admission),department_prev := shift(department,1,type="lag"),by=.(mrn,csn)]
dt[order(mrn,admission),department_next := shift(department,1,type="lead"),by=.(mrn,csn)]
dt <- dt[critcare==TRUE, .(
  mrn,
  csn,
  admission_icu=department_admission,
  discharge_icu=department_discharge,
  department_prev,
  department_next
)]

dt_now <- tdt[dt, on=c("encounter==csn")][is.na(discharge_icu)][order(admission_icu)]
dt_now  
    