# Steve Harris
# 2021-01-11
# Validate EMAP data against Caboodle


# TODO
# rebuild against Tim's view

# *************
# Running notes
# *************


# Libraries
library(lubridate)
library(data.table)
# devtools::reload(pkgload::inst('emapR'))
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Validating ICU admissions table')

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')
caboodle_join <- TRUE # Join with Kit's ICU admissions table
if (caboodle_join) rlang::inform('!!! will join with caboodle ICU admissions for verification')

# Script collapes all the bed movements into a department admit/discharge view
# the example below is for critical care areas but it can be adapted

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'icu_audit'

# Output: uds.icu_audit.admissions
target_schema <- 'icu_audit'
target_table <- 'emapr_validate_icu_admissions'
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

# Load from caboodle
query <- "
SELECT  
	 icu.IcuStayRegistryKey
	,icu.PatientDurableKey
	,icu.EncounterKey
	,icu.IcuStayStartInstant
	,icu.IcuStayEndInstant
	,icu.AgeAtIcuStayStart
	,e.EncounterEpicCsn
	,p.PrimaryMRN
	,p.BirthDate
FROM
CABOODLE_REPORT.dbo.IcuStayRegistryDataMart AS icu
JOIN
CABOODLE_REPORT.dbo.EncounterFact AS e
ON icu.EncounterKey = e.EncounterKey
LEFT JOIN 
CABOODLE_REPORT.dbo.PatientDim AS p
ON icu.PatientDurableKey = p.DurableKey
"

# Load caboodle data at the ICU visit level
# =========================================
# cab_icu <- DBI::dbReadTable(con_caboodle, 'IcuStayRegistryDataMart')
# setDT(cab_icu)
# names(cab_icu)
# cab_icu[,.(EncounterKey, DepartmentKey, IcuStayStartInstant, IcuStayEndInstant)]
cab_icu <- DBI::dbGetQuery(con_caboodle, query)
setDT(cab_icu)
cab_icu <- cab_icu[!is.na(IcuStayStartInstant)]
setkey(cab_icu, EncounterEpicCsn, IcuStayStartInstant)
cab_icu <- unique(cab_icu)
summary(cab_icu$AgeAtIcuStayStart)
cab_icu <- cab_icu[AgeAtIcuStayStart > 10]
cab_icu[, icu_i := NULL]
cab_icu[, icu_i := seq_len(.N), by=.(EncounterEpicCsn)]
cab_icu[, icu_n := .N, by=.(EncounterEpicCsn)]
cab_icu[icu_n > 1]


# Load emap data at the visit detail and visit occurrence level
# =============================================================
dtvd <- emapR::select_from(ctn, input_schema, 'emapr_visit_detail' )
dtvo <- emapR::select_from(ctn, input_schema, 'emapr_visit_occurrence' )
str(dtvd)
wdt <- dtvo[,.(visit_occurrence_id, csn)][dtvd, on='visit_occurrence_id']
wdt <- wdt[!is.na(cc_start_datetime)]
wdt <- unique(wdt[,.(visit_occurrence_id,csn,visit_detail_source_value,cc_start_datetime,cc_end_datetime)])
# FIXME csn's are not all Epic formatted etc. and some are character
wdt[, csn := as.integer(csn)]
wdt

# drop where Epic started before EMAP
cab_icu <- cab_icu[IcuStayStartInstant > min(wdt$cc_start_datetime)]
cab_icu

# Now join 
cab_icu[, ts_roll := IcuStayStartInstant]
wdt[, ts_roll := cc_start_datetime]
setkey(cab_icu, EncounterEpicCsn, ts_roll)
setkey(wdt, csn, ts_roll)

# join emap onto caboodle (there are more caboodle rows than emap rows)
res <- wdt[cab_icu, roll='nearest']

res[, nomatch := FALSE]
res[is.na(visit_occurrence_id), nomatch := TRUE]
janitor::tabyl(res, nomatch)
# Not making much difference wrt epoch
janitor::tabyl(res[IcuStayStartInstant > ymd('2020-01-01')], nomatch)

res[, start_diff := (IcuStayStartInstant - cc_start_datetime) / dhours(1)]
res[, end_diff := (IcuStayEndInstant - cc_end_datetime) / dhours(1)]
summary(res$start_diff)
summary(res$end_diff)

res[order(-IcuStayStartInstant)]
View(res)


# Better: write this back to the icu_audit schema (rather than saving locally)

# rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
# DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)
# DBI::dbDisconnect(ctn)
# rlang::inform('--- closing database connection')
# rlang::inform('--- script completed')


