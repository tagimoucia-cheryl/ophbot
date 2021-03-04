# Steve Harris
# 2020-06-13
# Quick exploration of staffing and workload

# setwd("//uclcmddprafss21/Home/sharris9/Documents/code/data-2.0")

library(tidyverse)
library(lubridate)
library(readxl)

library(janitor)

library(data.table)
library(cowplot)


dt_staff <- readxl::read_excel('data/raw/Nursing Staffing Levels Chart.xlsx', sheet='staffing-levels')
setDT(dt_staff)
setnames(dt_staff, '0', 'N')
setnames(dt_staff, 'Change In Nursing Staff', 'delta')
setnames(dt_staff, 'Time', 'ts')

head(dt_staff)
tail(dt_staff)

dt_staff <- dt_staff[4:nrow(dt_staff)-2]

# Lots of different times but clustered around shift times
tabyl(as.ITime(dt_staff$ts))
?ITime
dt_staff[, time := as.ITime(ts)]
dt_staff[, date := lubridate::date(ts)]
str(dt_staff)

# Inspection suggest the peaks at handover can be dropped by taking the max
# between 0830 and 1959 and 2030 and 0759
ggplot(dt_staff, aes(x=as.POSIXct(time), y=N)) + 
  geom_step() +
  scale_x_datetime(date_labels ="%H", date_minor_breaks = "1 hour")

# check you have sensible numbers if you start at 0830
dtp <- dt_staff[hour(ts)==8 & minute(ts) >=30]
ggplot(dtp, aes(x=ts, y=N)) + 
  geom_step()
# check you have sensible numbers if you start at 2030
dtp <- dt_staff[hour(ts)==20 & minute(ts) >=30]
ggplot(dtp, aes(x=ts, y=N)) + 
  geom_step()

# now drop the shift changeover periods
dt_staff <-  dt_staff[!(
  (hour(ts)==8 & minute(ts) <30) |
  (hour(ts)==20 & minute(ts) <30)
), .(N=min(N)), by=.(ts)]

# now collapse down to 2 shifts per day
dt_staff[, time:=NULL]
dt_staff[, date := lubridate::date(ts)]
dt_staff[hour(ts)>=8 & hour(ts)< 20, time := date + hm("08:00")]
dt_staff[hour(ts)<8 | hour(ts)>= 20, time := date + hm("20:00")]

# finally select the lowest number of staff per shift
dt_staff <- dt_staff[, .(N=min(N)),by=time]


ggplot(dt_staff, aes(x=time, y=N)) + 
  geom_step() +
  coord_cartesian(xlim=c(ymd_hms("2020-03-01 08:00:00"), ymd_hms("2020-04-30 08:00:00"))) +
  theme_cowplot()

# save
dt_staff[, date:=date(time)]
dt_staff[, shift := ifelse(hour(ts)==8,'day','night')]
setnames(dt_staff, 'time', 'ts')
dt_staff <- dt_staff[order(ts)]
write_csv(dt_staff, 'data/staff.csv')


# Let's inspect the CCMDS stuff
dt_ccmds <- readxl::read_excel(('data/raw/CC CCMDS.XLSX'))
dt_ccmds  
setDT(dt_ccmds)
str(dt_ccmds)
dt_ccmds[, organ_support_total := sum(Basic_Respiratory,Advanced_Respiratory,
                       Basic_Cardio, Advanced_Cardio,
                       Renal,
                       Neurological,
                       Gastrointestinal,
                       Dermatological,
                       Liver), by=.(PAT_MRN_ID,StartDateTime)]


dt_ccmds <- dt_ccmds[,.(PAT_MRN_ID, StartDateTime, 
                        LevelOfCare_0, LevelOfCare_1, LevelOfCare_2, LevelOfCare_3,
                        Basic_Respiratory, Advanced_Respiratory, Renal, organ_support_total)]
head(dt_ccmds)


dt_ccmds <- dt_ccmds[,.(N_ccmds = .N, 
            L0=sum(LevelOfCare_0),
            L1=sum(LevelOfCare_1),
            L2=sum(LevelOfCare_2),
            L3=sum(LevelOfCare_3),
            Oplus=sum(Basic_Respiratory),
            Vent=sum(Advanced_Respiratory),
            Renal=sum(Renal)
                        ),by=StartDateTime]
dt_ccmds[, date := ymd(StartDateTime)]
dt_ccmds
write_csv(dt_ccmds, 'data/ccmds.csv')

# Now merge
dt <- dt_ccmds[dt_staff, on="date"]
setnames(dt, "N", "Nurses")
dt[, N_gpics := 1*L3 + 0.5*L2]
dt <- dt[date >= ymd("2020-02-01")]

# Simple description
dtp <- melt.data.table(dt,
                id.vars = c("date", "ts", "shift"),
                measure.vars = c("Nurses", "Vent", "Oplus", "Renal"),
                variable.name = 'variable',
                value.name = 'count')
dtp
ggplot(dtp[shift=='day'], aes(ts, y=count, colour=variable)) +
  geom_step() +
  ggtitle("Counts of nursing, \nventilated patients, Oplus patients (CPAP etc), \nand RRT over time") +
  theme_cowplot()
ggsave('figures/nurses_and_workload.jpg')

# As ratio
dt[, nurses_per_vent := Nurses / Vent]
dt

dtp <- melt.data.table(dt,
                       id.vars = c("date", "ts", "shift"),
                       measure.vars = c("nurses_per_vent"),
                       variable.name = 'variable',
                       value.name = 'count')
dtp[order(variable,date,shift)]
ggplot(dtp, aes(ts, y=count, colour=shift)) +
  geom_step() +
  ggtitle("Ratio of (all) nurses to (all) ventilated patients") +
  ylab("Ratio") +
  theme_cowplot()
ggsave('figures/nurses_per_vent.jpg')
