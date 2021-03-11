# Steve Harris
# created 2021-01-011

# Use Tim's Caboodle script to get COVID status by CSN

# ****
# TODO
# ****
# - [ ] TODO need some timestamps of _when_ the patient was positive


# *************
# Running notes
# *************

# Libraries
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Starting to build CABOODLE_COVID table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Output: 
target_schema <- 'icu_audit'
target_table <- 'emapr_caboodle_covid'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

con_caboodle <- DBI::dbConnect(
  odbc::odbc(),
  Driver = "ODBC Driver 17 for SQL Server",
  Server = Sys.getenv("CABOODLE_HOST"),
  Database = "CABOODLE_REPORT",
  UID = Sys.getenv("CABOODLE_USER"),
  PWD = Sys.getenv("CABOODLE_PWD"),
  Port = 1433
)
# Load COVID data
# ==============
# query <- readr::read_file('sql/caboodle_covid.sql')
query <- "
 SELECT
       encounter_csn as csn
      ,Primary_MRN as mrn
      ,covid_status                   -- COVID status according to the data mart
      ,Infectious_YesNo                -- Is the patient considerd to be infectious
      ,Infection_Status
      ,Infection_Status_Start_Dttm
      ,Infection_Status_End_Dttm
   FROM [CABOODLE_REPORT].[WIP].[COVDM_Dataset] covdm
"
covid <- DBI::dbGetQuery(con_caboodle, query)
setDT(covid)
covid <- unique(covid)
covid
janitor::tabyl(unique(covid), Infection_Status, covid_status)

covid[, covid01 := FALSE]
covid[covid_status == 'Positive', covid01 := TRUE]
covid[Infection_Status == 'COVID-19', covid01 := TRUE]
janitor::tabyl(covid, covid01)

wdt <- unique(covid[,.(mrn, csn, covid01)])
wdt <- wdt[covid01==TRUE]
nrow(wdt)

# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


