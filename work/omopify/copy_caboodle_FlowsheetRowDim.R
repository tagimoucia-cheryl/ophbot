# Steve Harris
# created 2021-01-21

# Copy flowsheetrowdim into emap to help map and manage the unlabelled flowsheets

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
rlang::inform('--- Coping Caboodle.dbo.FlowsheetRowDim to EMAP UDS')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Output: 
target_schema <- 'icu_audit'
target_table <- 'emapr_caboodle_flowsheetrowdim'
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
 SELECT * FROM [CABOODLE_REPORT].[dbo].[FlowsheetRowDim] fsdim
"
fsdt <- DBI::dbGetQuery(con_caboodle, query)
DBI::dbDisconnect(con_caboodle)
setDT(fsdt)

nrow(fsdt)
# convert column names to lower for postgres
names(fsdt)
setnames(fsdt, names(fsdt), stringr::str_to_lower(names(fsdt)))
names(fsdt)

dplyr::glimpse(fsdt) 



# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=fsdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')


