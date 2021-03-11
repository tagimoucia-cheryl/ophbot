# Steve Harris
# 2020-07-04
# Add locations information to ops.care_site

# *************
# Configuration
# *************

debug <- FALSE

# Input: uds.ops_b.care_site
input_care_site <- 'uds.ops_b.care_site'
# Input: uds.covid_staging.locations
input_locations <- 'uds.covid_staging.locations'

# Output: uds.icu_audit.bed_moves
target_schema <- 'icu_audit'
target_table <- 'care_site_plus'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

library(janitor)
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

rlang::inform('--- Database connection opened')

# Load care site
# ==============
query <- paste("SELECT * FROM", input_care_site)
wdt <- DBI::dbGetQuery(ctn, query)
setDT(wdt)

# Load locations
# ==============
query <- paste("SELECT * FROM", input_locations)
locations <- DBI::dbGetQuery(ctn, query)
setDT(locations)

# Inspect
locations[,.N,by=`EpicDepartmentMpiId(InterfaceId)`]
locations[,.N,by=`RoomExternalId(InterfaceId)`]
locations[,.N,by=`BedLabel(InterfaceId)`]


# Reconstruct the HL7 location string for a join
locations[,
          care_site_name := paste(
                  `EpicDepartmentMpiId(InterfaceId)`,
                  `RoomExternalId(InterfaceId)`,
                  `BedLabel(InterfaceId)`,
                  sep="^"
          )]

# swap NA for null
locations[,
          care_site_name := stringr::str_replace_all(
                  care_site_name,
                  "\\^NA",
                  "^null" )]

# now check unique
locations[,.N,by=care_site_name][N>1]

tabyl(locations$departmentrecordstatusname)
locations <- locations[!departmentrecordstatusname %in% c('Deleted', 'Deleted and Hidden', 'Hidden')]

tabyl(locations$roomrecordstate)

tabyl(locations$bedrecordstate)
locations <- locations[!bedrecordstate %in% c('Deleted', 'Deleted and Hidden', 'Hidden')]

tabyl(locations$bedisincensus)
# locations[,dups :=.N,by=care_site_name]

uniqueN(locations)
locations <- unique(locations)
locations[,dups :=.N,by=care_site_name]
if (uniqueN(locations) !=   uniqueN(locations[,care_site_name])) {
        warning('!!! forced drop of some locations')
}

locations <- unique(locations[,.(care_site_name,
                                 department=epicdepartmentname,
                                 room=roomname,
                                 bed=`BedLabel(InterfaceId)`,
                                 # drop the following else not unique
                                 bedisincensus,
                                 ispoolbed
)])

# assume everything is in census and not pool then eliminate dups
janitor::tabyl(locations$bedisincensus)
janitor::tabyl(locations$ispoolbed)
locations[,.N,by=care_site_name][N>1]
# Y sorts after N; sort then keep just the head row
locations <- locations[order(-bedisincensus),.SD[1],by=care_site_name]
locations <- locations[order(-ispoolbed),.SD[1],by=care_site_name]

assertthat::assert_that(
        uniqueN(locations) == uniqueN(locations[,care_site_name]),
        msg="locations are not unique"
)

readr::write_csv(locations, 'data/secure/locations.csv')

wdt <- locations[wdt,on="care_site_name"]
wdt

# Better: write this back to the icu_audit schema (rather than saving locally)
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)

rlang::inform('--- Database connection closed')
rlang::inform('--- Script completed successfully')
rlang::inform('--- Script completed successfully')

