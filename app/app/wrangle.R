# Join patients onto obs and prep data

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

# Keep only necessary data for modelling
# wdt[,.N,by=label]
mdt <- wdt[label == llabel & tt >= wwindow]