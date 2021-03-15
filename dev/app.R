# Steve Harris
# created 2021-03-06

# Demo script that predicts next vital sign

# ****
# TODO
# ****


# *************
# Running notes
# *************

# Libraries
# CRAN
library(tidyverse)
library(strex)
library(lubridate)
library(rms)
library(Hmisc)
library(lme4)
library(broom.mixed)
library(collections)
library(checkmate)
library(data.table)
# Github
library(emapR) # see setup.R for installation

# *************
# Configuration
# *************
rlang::inform('--- Demo script that predicts next vital sign')
llabel <- 'Pulse'
wwindow <- -72

debug <- FALSE
if (debug) rlang::inform('!!! debug mode ON')

# Input: uds.star.bed_moves (custom helper view)
input_schema <- 'star_test'

# Output: 
target_schema <- 'icu_audit'
target_table <- 'vitals_tower_predictor'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# Wards of interest
wards <- c(
   'T01'
  ,'T01ECU'
  ,'T03'
  ,'T06C'
  ,'T06G'
  ,'T06H'
  ,'T07'
  ,'T07CV'
  ,'T08N'
  ,'T08S'
  ,'T09N'
  ,'T09S'
  ,'T10O'
  ,'T10S'
  ,'T11D'
  ,'T11E'
  ,'T11N'
  ,'T11S'
  ,'T12N'
  ,'T12S'
  ,'T13N'
  ,'T13S'
  ,'T14N'
  ,'T14S'
  ,'T16N'
  ,'T16S'
  ,'TYAAC'
  ,'HS15'
)

# set up vitals labels
vitals_dict <- dict()
vitals_dict$set('10', 'SpO2')
vitals_dict$set('5', 'BP')
vitals_dict$set('6', 'Temp')
vitals_dict$set('8', 'Pulse')
vitals_dict$set('9', 'Resp')
vitals_dict$set('28315', 'NEWS - SpO2 scale 1')
vitals_dict$set('28316', 'NEWS - SpO2 scale 2')
vitals_dict$set('3040109304', 'Room Air or Oxygen')
vitals_dict$set('6466', 'Level of consciousness')
vitals_dict$as_list()
vitals_dict$keys()

# Grab user name and password. I store my 'secrets' in an environment file that
# remains out of version control (.Renviron). You can see an example in
# 'example-config-files'. The .Renviron should be at the root of your project or
# in your 'home'.
emapR::udsConnect()

# Load recent vitals
# ==================
query <- readr::read_file('app/query_recent_inpatient_vitals.sql')
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
names(dt)
dtobs <- data.table::copy(dt)

# Load current inpatient filter
# =============================
query <- readr::read_file('app/query_current_inpatients.sql')
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
names(dt)
dtpts <- data.table::copy(dt)
dtpts[, c('ward', 'room', 'bed') := data.table::tstrsplit(location_string, split='\\^')]

# Extract numeric position of ward and bed
regexp <- "[[:digit:]]+"
dtpts[, wardi := as.numeric( str_extract(ward, regexp))]
dtpts[, bedi := as.numeric( str_nth_number(bed, n=2))]

# Note that hospital_visit_id is NOT unique
# perhaps exists in more than one place b/c of temporary locations
tdt <- dtpts
uniqueN(dtpts$hospital_visit_id) == nrow(dtpts)
# Let's first filter out key locations in the tower
tdt <- dtpts[ward %in% wards]
assertthat::assert_that(uniqueN(tdt$hospital_visit_id) == nrow(tdt))
dtpts <- tdt

# Inner join obs on location
# ==========================
wdt <- dtpts[dtobs, on='hospital_visit_id', nomatch=0]
wdt <- wdt[,.( visit_observation_id 
                ,observation_datetime
                ,unit
                ,value_as_real
                ,value_as_text
                ,id_in_application
                ,ward
                ,room
                ,bed
                ,wardi
                ,bedi
                ,mrn
                )]

# Now start working with this smaller table to clean
# Label up the observations
for (k in vitals_dict$keys()) {
  wdt[id_in_application == k, label := vitals_dict$get(k)]
}


# TODO factor out all these as functions
# Extract systolic and from text diastolic 
tdt <- wdt[label == 'BP']
tdt <- tdt[, c('SBP', 'DBP') := data.table::tstrsplit(value_as_text, split='\\/')]
cols <- setdiff(names(tdt), c('SBP', 'DBP'))

dtsbp <- tdt[, value_as_real := SBP]
dtsbp <- dtsbp[,cols,with=FALSE]
dtsbp[, label := 'SBP']

dtdbp <- tdt[, value_as_real := DBP]
dtdbp <- dtdbp[,cols,with=FALSE]
dtdbp[, label := 'DBP']

wdt <- wdt[label != 'BP']
wdt <- rbindlist(list(wdt, dtsbp, dtdbp))
rm(dtsbp, dtdbp)

# Indicator variable for supplemental oxygen
wdt[label == 'Room Air or Oxygen',
    value_as_real := ifelse(value_as_text == 'Supplemental Oxygen', 1, 0)]

# Fahrenheit to Celsius
wdt[, value_as_real := as.numeric(value_as_real)]
wdt[label=='Temp', value_as_real := ((value_as_real - 32) * 5 / 9)]

# Thinking about recency
# time difference
wdt[, tt := -1 * as.numeric(
    difftime(lubridate::now(), observation_datetime, units = 'hours'))]

# Drop unneeded cols
wdt[,id_in_application := NULL]
wdt[,value_as_text := NULL]
wdt[,unit := NULL]

# Drop missing locations
wdt <- wdt[!is.na(wardi) & !is.na(bedi)]

# rename
setnames(wdt, 'value_as_real', 'y')

# Plotting proof of principle
# tdt <- wdt[ward=='T07CV' & bedi == 47 & label == 'Pulse']
# ggplot(tdt, aes(x=tt, y=value_as_real)) + geom_point() 

model_vars <- c('tt', 'y', 'mrn')
nonmodel_vars <- setdiff(names(wdt), model_vars)
timeconstant_vars <- c('mrn', 'ward', 'room', 'wardi', 'bed', 'bedi', 'label' )

# Modelling proof of principle
# https://m-clark.github.io/R-models/
wdt[,.N,by=label]
tdt <- wdt[label == llabel & tt >= wwindow]

# model
mmix <- lmer(y ~ tt + (1+rcs(tt, 3)|mrn), data=tdt)

# Use augment to rapidly build in sample predictions
rdt <- augment(mmix)
setnames(rdt,'.fitted', 'yhat')
sdt <- tibble(tdt[,nonmodel_vars,with=FALSE])
sdt <- bind_cols(sdt,rdt)
sdt <- sdt %>% select(c(nonmodel_vars, model_vars, yhat))
setDT(sdt)

# build predictions out of sample (i.e for the last x hours)
new_data <- data.table(expand.grid(tt=wwindow:0, mrn=unique(sdt$mrn), label=llabel, new_data=TRUE))
pdt <- data.table(yhat=predict(mmix, new_data))
pdt <- bind_cols(pdt,new_data)
udt <- unique(sdt[,timeconstant_vars, with=FALSE])
udt <- udt[pdt, on=c('mrn==mrn', 'label==label')]
tdt <- rbindlist(list(sdt,udt),fill=TRUE)
tdt[is.na(new_data), new_data := FALSE]
tdt[new_data==TRUE, observation_datetime := now() + dhours(tt) ]

# Thinking about recency # variable ordering
# tdt[order(-observation_datetime), ti := seq_len(.N), by=.(mrn, label) ]
# flag vitals that have not been measured for some time
setorder(tdt,mrn,label,-tt) # for the side effect of sorting
tdt[new_data==FALSE, ti := seq_len(.N), by=.(mrn,label)]
tdt[new_data==FALSE, tlast := -1 * max(tt), by=.(mrn,label)]
tdt[new_data==TRUE, tlast := NA]
Hmisc::describe(tdt$tlast)

# inspect
# focus on who have not had a measurement in the last 8 hours
choose_mrn <- unique(tdt[new_data==FALSE & tlast > 8,.(mrn)])
gdt <- choose_mrn[tdt, on='mrn',nomatch=0]
ggplot(gdt, aes(x=tt, group=mrn)) +
  geom_point(aes(y=y), colour='blue', size=0.1) +
  geom_line(data=gdt[new_data==TRUE], aes(y=yhat, colour=new_data)) +
  geom_line(data=gdt[new_data==FALSE], aes(y=yhat, colour=new_data)) +
  facet_wrap(~mrn) +
  # coord_cartesian(xlim=c(-24,0)) +
  ylab(llabel) +
  xlab('Time from now (Hours)') +
  theme_minimal()

tdt
#foo <- data.table(x=sample(1:200,10))

news2_pulse <- function(x) {
  "convert from pulse (real) to news score"
  assertNumeric(x)
  r <- data.table(x=x, y=0L)
  r[, y := ifelse(x <= 50 | x >= 91, 1L, y )]
  r[, y := ifelse(x >= 111, 2L, y )]
  r[, y := ifelse(x <= 40 | x >= 131, 3L, y )]
  return(r$y)
}

tdt[, news2_y := news2_pulse(tdt$y)]
tdt[, news2_yhat := news2_pulse(tdt$yhat)]
tdt


# TODO NEXT
# reduce time frame to 72h 
# function to convert to NEWS categories
# label predictions and actual values
# return to database
# set up as ofelia job
# build superset dashboard
# dashboard features: tower wide view and individual



# Better: write this back to the icu_audit schema (rather than saving locally)
rlang::inform(paste('--- writing:', target_table, 'back to schema:', target_schema))
DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)
rlang::inform('--- closing database connection')
rlang::inform('--- script completed')

