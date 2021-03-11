library(lubridate) # not part of tidyverse
library(RPostgres)
library(data.table)

ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")

sql_query <- "
SELECT 
	 vd.hospital_visit_id 
	,mrn.mrn
	,mrn.nhs_number
	,p.firstname
	,p.lastname
	,p.home_postcode
	,p.alive
	,p.date_of_birth
	,p.date_of_death
	,p.sex
	,vo.encounter
	,vo.patient_class
	,vo.admission_time
	,vo.discharge_time
	,vo.arrival_method
	,vo.discharge_destination
	,vo.discharge_disposition
	,vo.presentation_time
	,vo.mrn_id
FROM star_test.location_visit vd 
LEFT JOIN flow.location loc ON vd.location_id = loc.location_id 
LEFT JOIN star_test.hospital_visit vo ON vd.hospital_visit_id = vo.hospital_visit_id
LEFT JOIN star_test.core_demographic p ON vo.mrn_id = p.mrn_id
LEFT JOIN star_test.mrn ON p.mrn_id = mrn.mrn_id
WHERE loc.critical_care = true
"

dt <- DBI::dbGetQuery(ctn, sql_query)
setDT(dt)
rdt <- data.table::copy(dt)
View(dt)

# unique patients to critical care
dt_pts <- unique(dt[,.(mrn,nhs_number,firstname,lastname,home_postcode,date_of_birth,date_of_death,sex)])
# 2021-01-03 RESUME: write this back to flow