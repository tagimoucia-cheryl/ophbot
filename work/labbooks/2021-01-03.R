# Proof of connection to the UDS
# Load libraries
.libPaths()

install.packages(c('RPostgres', 'DBI', 'lubridate', 'janitor', 'ggplot2', 'data.table'))
install.packages(c('remotes', 'plotly'))


#library(tidyverse)
library(lubridate) # not part of tidyverse
library(ggplot2)
library(plotly)

library(RPostgres)
# YMMV but I use data.table much more than tidyverse; Apologies if this confuses
library(data.table)
#library(assertthat)

ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")
# slowish b/c runs against the view you've built
query <- "SELECT * FROM flow.census_cc"
dt <- DBI::dbGetQuery(ctn, query)
setDT(dt)
rdt <- data.table::copy(dt)

# warning reloading
dt <- rdt
head(dt)

# renaming for convenience
setnames(dt, 'hospital_visit_id', 'id_vo') # idvo = id visit_occurrence
setnames(dt, 'location_visit_id', 'id_vd') # idvo = id visit_occurrence
dt

# enumerate patients/visits/critical care admissions
tdt <- dt[!is.na(cc_census),.(id_vd,mrn,id_vo,encounter,ward,ts,event,cc_census)]

# critical care visits
tdt <- tdt[order(id_vd)]
tdt[, cc_i := rleid(tdt$id_vd)][]
tdt[,.(id_vd,cc_i)][dt]
tdt[order(id_vd)][1:10]


# patients
tdt <- tdt[order(mrn,ts)]
tdt[, mrn_i:= rleid(tdt$mrn)][]

# cast back to one row per bed visit so you can enumerate patient/visit events
tdt <- data.table::dcast(tdt, id_vd + cc_i + mrn + id_vo + encounter ~ event, value.var = "ts")
tdt


# patients
tdt <- tdt[order(mrn,bed_in)]
tdt[, mrn_i:= rleid(tdt$mrn)][]

# hospital visits
tdt <- tdt[order(id_vo,bed_in)]
tdt[, vo_i := rleidv(tdt$id_vo)][]

# count critical care visits within a hospital admission
tdt[, cc_N := .N, by=id_vo][]

# and now save back to main data.table

#dt <- tdt[,.(id_vd,mrn,id_vo,encounter,mrn_i,vo_i,cc_i,cc_N)][dt,on=.NATURAL]
res <- tdt[,.(id_vd,mrn_i,vo_i,cc_i,cc_N)][dt,on='id_vd']
View(res)

# prepare 5 admissions
tdt <- dt[cc_N > 1]
tdt[,
    .(id_vd,mrn,id_vo,encounter,ward,ts,event,cc_census,mrn_i,vo_i,cc_i,cc_N)
    ][order(mrn_i,vo_i,ts)]

tdt <- tdt[cc_i %in% sample(dt[!is.na(cc_i)]$cc_i,10)]
gg <- ggplot(tdt[!is.na(cc_census)][order(ts)], aes(x=ts,y=mrn, group=cc_i)) + geom_path() + theme_minimal()
gg
plotly::ggplotly(gg)

