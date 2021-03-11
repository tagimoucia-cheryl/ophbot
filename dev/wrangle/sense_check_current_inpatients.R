# Steve Harris
# 2020-07-06
# Sense check by pulling up existing inpatients (as of the time the script was last run)

# *************
# Configuration
# *************
rlang::inform('--- Script starting')
rlang::inform('--- Loading inpatients as of the time the icu_audit tables were last built')

# Input: uds.icu_audit ... multiple tables starting from icu_admissions
input_admissions <- 'uds.icu_audit.icu_admissions'
input_observations <- 'uds.icu_audit.observations'
rlang::inform(paste('--- input table:', input_table))

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'

library(lubridate)
library(data.table)

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



# Load bed moves
# ==============
query <- paste("SELECT * FROM", input_admissions)
rlang::inform(paste('--- loading data from', target_schema, input_admissions))
wdt <- DBI::dbGetQuery(ctn, query)
setDT(wdt)

wdt <- wdt[is.na(icu_discharge)][order(department,icu_admission)]
wdt

DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')
