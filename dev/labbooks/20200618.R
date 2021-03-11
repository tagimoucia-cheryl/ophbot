# Steve Harris
# 2020-06-16
# See if you can build a basic data mart
# Working out if CSN ties things together properly

# setwd("//uclcmddprafss21/Home/sharris9/Documents/code/data-2.0")

library(tidyverse)
library(lubridate)
library(readxl)

library(janitor)

library(data.table)
library(cowplot)

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


# We have 2 databases
# 'star'  : live (within minutes), complete, with the history of all information but in a 'star' schema so harder to use
# 'ops'   : based on the OMOP schema, and up-to-date within 12-24 hours; patient centric, easier to use

# A series of pre-built views are available on 'star' that make it easier to use
# - bed_moves: patient movements from bed to bed within the bed
# - demographics: direct patient identifiers including vital status and date of death
# - flowsheets: derived from both flowsheet via caboodle and via HL7 where the interfaces have been built (e.g. vital signs) 
# - labs: derived from the HL7 stream from HSL

# We have copies of the queries that create these views stores in snippets/SQL
# You can load these as follows if you wish e.g.
# query <- read_file("snippets/SQL/bed_moves.sql")


# Load bed moves
# ==============
query <- "SELECT * FROM icu_audit.bed_moves"
rdt <- DBI::dbGetQuery(ctn, query)
setDT(rdt)
wdt <- data.table::copy(rdt)
head(wdt)

tdt <- wdt[,.N,by=.(mrn,csn)][order(-N)][1:30]
tdt[,mrnN := .N,by=mrn]
tdt[order(-mrnN)]

query <- "SELECT * FROM icu_audit.bed_moves WHERE mrn = '21142068' "
pdt <- setDT(DBI::dbGetQuery(ctn, query))
pdt


query <- "SELECT * FROM covid_staging.locations"
locations <- setDT(DBI::dbGetQuery(ctn, query))
locations

locations[, hl7_location := paste(`EpicDepartmentMpiId(InterfaceId)`, `RoomExternalId(InterfaceId)`, `BedLabel(InterfaceId)`,
                                  sep = '^')]
locations[, hl7_location := stringr::str_replace_all(hl7_location, "\\^NA", "^null")]

locations
# Better: write this back to the icu_audit schema (rather than saving locally)
table_path <- DBI::Id(schema="icu_audit", table="locations")
DBI::dbWriteTable(ctn, name=table_path, value=locations, overwrite=TRUE)

pdt
tabyl(locations$departmentrecordstatusname)
tdt <- unique(locations[is.na(bedrecordstate) & 
                   is.na(departmentrecordstatusname) &
                   bedisincensus == 'Y'
                 ])[pdt, on='hl7_location', nomatch=0][!is.na(mrn)]
View(tdt)
