# Steve Harris
# 2020-07-03

# Convert a long table built from star to HIC style time series data
# see if we can wrangle our data into a format that looks close enough to CCHIC to use those tools

# NOTE: the naming of variables is often deliberately following the naming that Ed uses in inspectEHR

# Libraries
library(lubridate)
library(data.table)
# Note the order here is important; for now, we want the guidEHR process function to mask the inspectEHR one
library(inspectEHR)   # 1.

# devtools::reload(pkgload::inst('guidEHR'))
library(guidEHR)      # 2. see setup.R for installation

# TODO: Move these over to your package (and then deliberately overwrite
# inspectEHR::extract with guidEHR::extract)
# source('utils/utils.R')
# source('utils/extract.R')

# *************
# Configuration
# *************

debug <- TRUE

# Explain what the script does here ...

# Input: 3 tables (see select_star_from function below)
# visit_occurrence (to define time alignment)
# observations
# concepts

# Output: uds.icu_audit.obs
target_schema <- 'icu_audit'
target_table <- 'obs_coalesced'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# arg to switch to choose which visits to work with
visit_occurrence_ids <- NULL

# cadence for resulting table
cadence <-  1

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


# Prepare the data so you can use inspectEHR
# this means renaming things to match and restructuring to follow the omop standard


# Prepare the data for extraction
# ===============================
# Identify the concepts you want
# Specify the 'coalesce' function(s)

concepts <- select_star_from(ctn, target_schema, 'concepts')
unique(concepts[order(short_name)]$short_name)
concept_short_names <- c('hrate',
                         'rrate',
                         'spo2',
                         'bp',
                         'fio2',
                         'temperature',
                         'map_nibp',
                         'rass'
                         )
concepts <- concepts[short_name %in% concept_short_names]
concepts[, concept_source_name := NULL]
concepts <- unique(concepts)
concept_ids <- concepts$concept_id
assertthat::assert_that(all(!is.na(concept_ids)))

# functions to extract
func_list <- alist(min, median, max)
func_list <- sapply(func_list, as.character)

# Now expand up for each function
coalesce_rows <- rep(func_list, length(concept_ids))
concept_ids <- rep(concepts$concept_id, each=length(func_list))
concept_short_names <- rep(concepts$short_name, each=length(func_list))

# unique(obs[person_id == '03036594']$visit_occurrence_id) # two hospital admissions, three critcare admissions
# if (debug) visit_occurrence_ids <- '1019241303_13'

source('utils/extract.R')
res <- extract(ctn,
               target_schema,
               visit_occurrence_ids = NULL,
               concept_names = concept_ids,
               rename = concept_short_names,
               coalesce_rows = coalesce_rows,
               cadence = 4
               )

res

DBI::dbWriteTable(ctn, name=target_table_path, value=res, overwrite=TRUE)

DBI::dbDisconnect(ctn)









