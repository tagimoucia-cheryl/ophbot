# Steve Harris
# 2020-07-04
# Query from ops_b.measurement; seems to be close to full as of 2020-07-04

rlang::inform('--- Script starting')
stop('\n!!! Use ops.measurement directly')

# Libraries
library(lubridate)
library(data.table)
library(guidEHR) # see setup.R for installation


# TODO: Move these over to your package
# source('utils/utils.R')

# *************
# Configuration
# *************

debug <- FALSE
if (debug)  rlang::inform('--- Debugging mode ON')

# Input: uds.ops_b.measurement
ops_schema <- 'ops_b'
measurement_table <- 'measurement'
measurement_in_path <- DBI::Id(schema=ops_schema, table=measurement_table)

# Output: uds.icu_audit.obs
icu_schema <- 'icu_audit'
measurement_out_path <- DBI::Id(schema=target_schema, table=target_table_obs)

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

rlang::inform('--- connecting to database')
rlang::inform('--- loading concepts')

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

