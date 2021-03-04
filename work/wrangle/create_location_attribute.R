# 2021-01-22
# exported location from star_a
# then hand edited the CSV
library(data.table)
library(stringr)
library(lubridate)
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Build a table of location attributes')

# Output: uds.icu_audit.location_attribute
input_schema <- 'star_a'
target_schema <- 'icu_audit'
target_table <- 'emapr_location_attribute'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.

# start with your hand edited table
# basic import
wdt <- readr::read_csv('data/location_attribute.csv',
                       col_types = 'iciccT?')
setDT(wdt)
dplyr::glimpse(wdt)

# basic cleaning
wdt[, X7 := NULL]
setnames(wdt, 'location_attribute', 'location_attribute_id')
wdt[, value_as_text := stringr::str_to_lower(value_as_text)]
wdt[, attribute_name := stringr::str_to_lower(attribute_name)]
wdt

# now append new attributes
# unpack the string into ward/room/bed
tdt <- wdt[, tstrsplit(location_string, 
                         split="\\^", 
                         names=c('ward', 'room', 'bed'))
               , by=location_string]

beds <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'bed',
               value_as_text=bed,
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]


rooms <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'room',
               value_as_text=room,
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]


wards <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'ward',
               value_as_text=ward,
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]

# And hand edit T07 and ECU screw-ups
t07 <- wdt[str_detect(location_string, "null\\^T07CV.*"),
    .(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'ward',
               value_as_text='T07CV',
               valid_from=ymd_hms('2020-12-01 00:00:00')
               )]
t07
ecu <- wdt[str_detect(location_string, "null\\^T01ECU.*"),
    .(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'ward',
               value_as_text='T01ECU',
               valid_from=ymd_hms('2020-12-01 00:00:00')
               )]

# drop updated rows
wards <- wards[!t07, on='location_string']
wards <- wards[!ecu, on='location_string']

wards <- rbindlist(list(wards, t07, ecu))
wards


# procedural areas 
# WHEN location_string ~ '.*(SURGERY|THR|PROC|ENDO|TREAT|ANGI).*|.+(?<!CHA)IN?R\^.*' then 'procedure' 
tdt <- unique(wdt[,.(location_string)])
tdt[str_detect(location_string, ".*(SURGERY|THR|PROC|ENDO|TREAT|ANGI).*|.+(?<!CHA)IN?R\\^.*")
  , attribute_name := 'procedure']
janitor::tabyl(tdt$attribute_name)
tdt <- tdt[!is.na(attribute_name)]

procedures <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name,
               value_as_text='TRUE',
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]
procedures


# imaging
# WHEN location_string ~ '.*XR.*|.*MRI.*|.+CT\^.*|.*SCANNER.*' then 'imaging' 
tdt <- unique(wdt[,.(location_string)])
tdt[str_detect(location_string, ".*XR.*|.*MRI.*|.+CT\\^.*|.*SCANNER.*")
  , attribute_name := 'imaging']
janitor::tabyl(tdt$attribute_name)
tdt <- tdt[!is.na(attribute_name)]
tdt

imaging <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name,
               value_as_text='TRUE',
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]


# -- define ED areas
# ,CASE 
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%RESUS%' THEN 'RESUS'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%MAJ%' THEN 'MAJORS'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%UTC%' THEN 'UTC'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%RAT%' THEN 'RAT'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%SDEC%' THEN 'SDEC'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%SAA%' THEN 'SAA' -- specialty assessment area
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%TRIAGE%' THEN 'TRIAGE'
#     WHEN SPLIT_PART(location_string,'^',1) = 'ED' AND location_string LIKE '%PAEDS%' THEN 'PAEDS'
#     END AS ed_zone
tdt <- unique(wdt[,.(location_string)])
tdt[str_detect(location_string, "RESUS|MAJORS|UTC|RAT|SDEC|SAA|TRIAGE|PAEDS")
  , attribute_name := 'ed_zone']
janitor::tabyl(tdt$attribute_name)
tdt <- tdt[!is.na(attribute_name)]
tdt

ed <- tdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name,
               value_as_text='TRUE',
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]


# building
# -- define building / physical site
# ,CASE 
#     -- THP3 includes podium theatres
#     WHEN SPLIT_PART(location_string,'^',1) ~ '^(T0|T1|THP3|ED(?!H))'  THEN 'tower'
#     WHEN SUBSTR(location_string,1,2) IN ('WM', 'WS')  THEN 'WMS'
#     WHEN location_string LIKE '%MCC%' then 'MCC'
#     WHEN location_string LIKE '%NICU%' then 'NICU'
#     WHEN location_string LIKE '%NHNN%' then 'NHNN'
#     WHEN SUBSTR(location_string,1,4) IN ('SINQ', 'MINQ')  THEN 'NHNN'
#     WHEN location_string LIKE 'EDH%' then 'EDH'
#     WHEN location_string LIKE '%OUTSC%' then 'EXTERNAL'
#     END AS building
tdt <- unique(wards[,.(location_string)])
tdt[str_detect(location_string, "^(T0|T1|THP3|ED(?!H))"  ), value_as_text := 'tower']
tower <- tdt[!is.na(value_as_text)]

tdt <- unique(wards[,.(location_string)])
tdt[str_detect(location_string, "^(WM|WS).*"  ), value_as_text := 'wms']
wms <- tdt[!is.na(value_as_text)]
wms

tdt <- unique(wards[,.(location_string)])
tdt[str_detect(location_string, "^(SINQ|MINQ).*"  ), value_as_text := 'nhnn']
tdt[str_detect(location_string, ".*?NHNN.*"  ), value_as_text := 'nhnn']
nhnn <- tdt[!is.na(value_as_text)]
nhnn

tdt <- unique(wards[,.(location_string)])
tdt[str_detect(location_string, ".*?MCC.*"  ), value_as_text := 'mcc']
mcc <- tdt[!is.na(value_as_text)]
mcc

tdt <- unique(wards[,.(location_string)])
tdt[str_detect(location_string, ".*?NICU.*"  ), value_as_text := 'nicu']
nicu <- tdt[!is.na(value_as_text)]
nicu

building <- rbindlist(list(tower, wms, nhnn, mcc, nicu))
building <- building[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'building',
               value_as_text,
               valid_from=ymd_hms('2006-01-01 00:00:00')
               )]
building
janitor::tabyl(building$value_as_text)

# now bind long
wdt <- rbindlist(list(wdt,beds,rooms,wards,procedures,imaging,ed,building))
wdt[!is.na(attribute_name), attribute_source := 'inferred from location_string']
wdt

# now bring in caboodle
cdt <- readr::read_csv('data/caboodle_DepartmentDim.csv')
setDT(cdt)
dplyr::glimpse(cdt)
cdt[, BedEpicId := as.integer(BedEpicId)]
cdt[, IsBed := as.integer(IsBed)]
cdt[, BedInCensus := as.integer(BedInCensus)]
cdt[, IsRoom := as.integer(IsRoom)]

cdt[, DepartmentEpicId := as.integer(DepartmentEpicId)]
cdt[, IsDepartment := as.integer(IsDepartment)]

janitor::tabyl(cdt, DepartmentSpecialty)
janitor::tabyl(cdt, DepartmentLevelOfCareGrouper)

# Manual inspection ...
# Where DepartmentName = DepartmentAbbreviation then I think these are clinics
udt <- cdt[IsBed != 1]
udt <- udt[DepartmentName == DepartmentAbbreviation, .(DepartmentAbbreviation, DepartmentSpecialty, DepartmentCenter)]
udt <- udt[DepartmentAbbreviation != '*Unknown']
udt <- udt[DepartmentAbbreviation != '*Unspecified']
udt <- udt[DepartmentAbbreviation != '*Not Applicable']
udt <- udt[DepartmentAbbreviation != '*Deleted']
udt <- udt[DepartmentCenter != 'Epic Medical Hospital']
udt <- udt[DepartmentCenter != 'Epic Health System']
setkey(udt, DepartmentAbbreviation)
udt[, c('A1', 'A2') := tstrsplit(DepartmentAbbreviation, split=' ', keep=c(1,2)) ]
udt
# View(udt)

# Prepare the location string for matching
tdt <- wdt[, tstrsplit(location_string, 
                         split="\\^", 
                         names=c('ward', 'room', 'bed'))
               , by=location_string]
tdt <- unique(tdt)
tdt
# View(tdt)
vdt <- tdt[udt, on="ward==A2"]
vdt[!is.na(location_string) & room == 'null' & bed == 'null']


specialty <- vdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'department_specialty',
               value_as_text=DepartmentSpecialty,
               valid_from=ymd_hms('2019-04-01 00:00:00'),
               attribute_source='caboodle DepartmentDim'
               )]


center <- vdt[,.(location_attribute_id = NA_integer_,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'department_centre',
               value_as_text=DepartmentCenter,
               valid_from=ymd_hms('2019-04-01 00:00:00'),
               attribute_source='caboodle DepartmentDim'
               )]

wdt <- rbindlist(list(wdt,specialty,center))
wdt[is.na(attribute_name)]

# tidy
wdt[value_as_text=='null', value_as_text := NA]
wdt[str_to_lower(value_as_text)=='true', value_as_integer := 1]
wdt <- wdt[!is.na(attribute_name)]

# now provide a unique index and sort
wdt <- wdt[!is.na(location_string)]
setkey(wdt, location_string, attribute_name, valid_from)
wdt[, location_attribute_id := .I][]
wdt


#View(wdt[, .(value_as_text, iconv(value_as_text, "UTF-8", "UTF-8", sub=""))])
wdt[, value_as_text := iconv(value_as_text, "UTF-8", "UTF-8", sub="")]

# drop dups
wdt <- unique(wdt)

# later modifications and updates
wdt
wdt[str_detect(location_string, '^T08N.*?([0-1]\\d|2[0-3])$')
    & attribute_name == 'niv', valid_from := ymd_hms('2020-12-28 00:00:00')]

# TODO abstract this out into a function
# function to take a range of beds and apply an attribute
max_location_attribute_id <- max(wdt$location_attribute_id)
locations <- unique(wdt[str_detect(location_string, '^T08N.*?([0-1]\\d|2[0-3])$'), .(location_string)])
new_attributes <- locations[,.(
               location_attribute_id = .I + max_location_attribute_id,
               location_string,
               attribute_code = NA_integer_,
               attribute_name = 'niv',
               value_as_text='TRUE',
               value_as_integer=1,
               valid_from=ymd_hms('2020-12-28 00:00:00'),
               attribute_source='Ronan Astin via email 2021-01-23'
               )]
new_attributes
wdt <- rbindlist(list(new_attributes,wdt), use.names = TRUE)
setkey(wdt, location_string, attribute_name, valid_from)
wdt

# 2021-01-25 see below; don't use
# merge on current location_id index
# location <- emapR::select_from(ctn, input_schema, 'location')
# wdt <- location[wdt, on='location_string']
# setcolorder(wdt, c('location_attribute_id', 'location_id', 'location_string'))


# Now write table back to UDS
emapR::udsConnect()
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=wdt, overwrite=TRUE)


# Now build index on location_string
target_table_string <- paste(target_schema, target_table, sep=".")
create_index_statement <- paste(
  "CREATE INDEX location_string ON", target_table_string, "(location_string);"
)

# 2021-01-25 don't use location_id as an index; risks confusion between schemas
# send query to build index
# DBI::dbExecute(ctn, create_index_statement)
# Now build index on location_id
# create_index_statement <- paste(
#   "CREATE INDEX location_id ON", target_table_string, "(location_id);"
# )

# send query to build index
DBI::dbExecute(ctn, create_index_statement)

DBI::dbDisconnect(ctn)
