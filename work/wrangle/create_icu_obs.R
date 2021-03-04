# Steve Harris
# 2020-07-02

# Directly query 'star' and produce a table of observations; the example below
# uses pf.fact_type = 44 -- Vital sign fact type but you can choose as you wish from star.attributes
# then label these using the current concept mappings
# and finally join on the visit detail
stop('!!! Use ops.observation directly')

# Libraries
library(lubridate)
library(data.table)
library(guidEHR) # see setup.R for installation


# TODO: Move these over to your package
source('utils/utils.R')


# *************
# Configuration
# *************

debug <- FALSE
make_omop_observation <- TRUE     # write out an OMOP CDM compatible table


# Input: uds.star via query to extract vital signs
# pf.fact_type = 44 -- Vital sign fact type
# TODO: should be easy to extend to other measures
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
	  (SELECT DISTINCT csn FROM icu_audit.icu_admissions) icu
		ON e.encounter = icu.csn
	WHERE 
		pf.fact_type = 44 
		AND 
		pf.valid_until IS NULL AND pf.stored_until IS NULL
		AND 
		pp.valid_until IS NULL AND pp.stored_until IS NULL
"


# Output: uds.icu_audit.obs
target_schema <- 'icu_audit'
target_table <- 'observation'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)
target_table_obs <- 'observation'
target_table_path_obs <- DBI::Id(schema=target_schema, table=target_table_obs)

# Period of interest
period_min <- ymd_hms('2020-02-01 00:00:00')
period_max <- now()

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


# Load concepts as prepared in create_concept_mappings.R
concepts <- select_star_from(ctn, target_schema , 'concepts')

# Load and select key columns from bed_moves
vd <- select_star_from(ctn, target_schema , 'bed_moves')
vd <- vd[,.(mrn, csn, bed_i, bed_admission, bed_discharge)]

# Load patient properties as per query
# ====================================

rlang::warn('--- slow query (about 1 minute); be patient')
rdt <- DBI::dbGetQuery(ctn, query)
setDT(rdt)

wdt <- data.table::copy(rdt)



if (debug) wdt <- wdt[1:1e5]
# janitor::tabyl(wdt[short_name == 'VIT_OBS_ID']$value_as_string)

tdt_real <- data.table::dcast(wdt[,.(encounter, patient_fact_id, short_name, value_as_datetime, value_as_real)]
                  , encounter + patient_fact_id ~ short_name,
                  value.var = list("value_as_datetime", "value_as_real"))[
                    ,.(encounter,
                       patient_fact_id,
                       ts = value_as_datetime_VIT_OBS_TIME,
                       val_real = value_as_real_VIT_NUM_VALUE)
                  ]
tdt_string <- data.table::dcast(wdt[,.(encounter, patient_fact_id, short_name, value_as_datetime, value_as_string)]
                              , encounter + patient_fact_id ~ short_name,
                              value.var = list("value_as_datetime", "value_as_string"))[
                                ,.(encounter,
                                   patient_fact_id,
                                   ts = value_as_datetime_VIT_OBS_TIME,
                                   concept = value_as_string_VIT_OBS_ID,
                                   unit = value_as_string_VIT_UNIT,
                                   val_string = value_as_string_VIT_STR_VALUE)
                                ]

tdt_string <- tdt_string[ts > period_min & ts < period_max]
tdt_real <- tdt_real[ts > period_min & ts < period_max]

setkey(tdt_string, "encounter", "patient_fact_id", "ts")
setkey(tdt_real, "encounter", "patient_fact_id", "ts")

tdt <- tdt_string[tdt_real]



tdt <- tdt[,.(
  encounter, patient_fact_id,
  ts, concept,
  name_short,
  val_string,
  val_real,
  unit
)]

# Now perform rolling join for bed_moves (vd)
tdt[, ts_roll := ts]
vdt <- data.table::copy(vd)
vdt[, ts_roll := bed_admission]
setnames(vdt, 'csn', 'encounter')
vdt <- vdt[,.(mrn,encounter,bed_i,ts_roll)]


tdt <- vdt[tdt, on=c('encounter', 'ts_roll'), roll = +Inf]
tdt[, ts_roll := NULL]

tdt <- tdt[order(-ts)]
tdt

if (make_omop_observation) {
  
  # Prepare a local version of the observation table
  obs <- tdt[,.(
    observation_id = patient_fact_id,
    concept_source_name = concept,
    observation_datetime = ts,
    unit_concept_id = NA,
    unit_source_value = unit,
    value_as_datetime = NA,
    value_as_concept_id = NA,
    value_as_number = val_real,
    value_as_string = val_string,
    person_id = mrn,
    visit_detail_id = paste0(encounter, '_', bed_i),
    visit_occurrence_id = encounter
  )]
  obs[, visit_occurrence_id := as.integer(visit_occurrence_id)]
  # convert to POSIXct
  obs[, observation_datetime := lubridate::ymd_hms(observation_datetime)]
  str(obs)
  
  obs <- concepts[,.(concept_id,concept_source_name)][obs, on="concept_source_name"]
  setnames(obs, 'concept_id', 'observation_concept_id')
  
  DBI::dbWriteTable(ctn, name=target_table_path_obs, value=obs, overwrite=TRUE)

} else {
  
  # Better: write this back to the icu_audit schema (rather than saving locally)
  tdt
  DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)
}


DBI::dbDisconnect(ctn)

