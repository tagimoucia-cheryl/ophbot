# Steve Harris
# 2020-07-06

# TODO: Update to take advantage of the following Visit_Occurrence_source is the
# fact id for the hospital visit in the star.patient_fact table, which you can
# join to the star.encounter table to get the CSN.

library(lubridate)
library(data.table)
library(guidEHR)
# guidEHR::hello()

rlang::inform('--- Script starting')

debug <- FALSE
if (debug) {
  rlang::inform('--- Debugging mode ON')
  mrn_list <- c(
    '41559546',
    '40397859',
    '91027785',
    '21203433'
  )
  mrn_list <- paste(mrn_list, collapse="', '")
  mrn_list <- paste0("'", mrn_list ,"'", collapse=" ")
  mrn_list
  where_clause_vo <- paste("WHERE p.person_source_value IN (", mrn_list, ")")
  where_clause_star <- paste("AND mrn.mrn IN (", mrn_list, ")")
  
} else {
  where_clause_vo <- ''
  where_clause_star <- ''
}
print(where_clause_vo)
print(where_clause_star)


ctn <- DBI::dbConnect(RPostgres::Postgres(),
                      host = Sys.getenv("UDS_HOST"),
                      port = 5432,
                      user = Sys.getenv("UDS_USER"),
                      password = Sys.getenv("UDS_PWD"),
                      dbname = "uds")


rlang::inform('--- Database connection opened')

# Output
target_schema <- 'icu_audit'
target_table <- 'visit_occurrence_csn'
target_table_path <- DBI::Id(schema=target_schema, table=target_table)

# emap_ops : visit_occurrence and person to get MRN and hospital visit details
query_vo <- "
SELECT 
  vo.visit_occurrence_id,
  vo.visit_start_datetime,
  vo.visit_end_datetime,
  p.person_id,
  p.person_source_value mrn
FROM ops_b.visit_occurrence vo
LEFT JOIN ops_b.person p
  ON p.person_id = vo.person_id
"
query_vo <- paste(query_vo, where_clause_vo, collapse="\n")
query_vo

rlang::inform('--- loading visit_occurrence from ops')

rdt <- setDT(DBI::dbGetQuery(ctn, query_vo ))
rdt <- rdt[order(mrn, visit_start_datetime),
    .(mrn,visit_start_datetime, visit_end_datetime, visit_occurrence_id)]
rdt

# TODO: visit_occurrence is NOT time zone aware
# see the following two queries: the latter gives 12pm without timezone (i.e. UTC)
# SELECT * FROM star.patient_property pp WHERE pp.patient_property_id = 149967663 
# SELECT * FROM ops_b.visit_occurrence vo WHERE vo.visit_occurrence_id = 210840332 


# emap_star : to get csn and info associated with that
# fact_type 5 = hospital visit details
query_star <- "
SELECT 
  	mrn.mrn,
  	e.encounter,
  	att.short_name,
  	pp.patient_property_id,
  	pp.value_as_datetime
	FROM star.patient_property pp
	JOIN 
		(SELECT patient_fact_id, encounter, fact_type FROM star.patient_fact
			WHERE stored_until IS NULL AND valid_until IS NULL
			-- and collect all hospital visit level info
			AND fact_type = 5) pf
		ON pp.fact = pf.patient_fact_id
	JOIN 
		(SELECT encounter, encounter_id FROM star.encounter) e 
		ON pf.encounter = e.encounter_id 
	JOIN (SELECT attribute_id, short_name FROM star.attribute
				WHERE valid_until IS NULL) att
		ON pp.property_type = att.attribute_id
  	LEFT JOIN 
	  	(SELECT encounter, mrn FROM star.mrn_encounter
		  WHERE stored_until IS NULL AND valid_until IS NULL) me
  		ON e.encounter_id = me.encounter
  	LEFT JOIN 
		(SELECT mrn, mrn_id FROM star.mrn) mrn 
  		ON me.mrn = mrn.mrn_id
	WHERE 
  		pp.valid_until IS NULL AND pp.stored_until IS NULL
		AND
		  pp.property_type IN (7, 8)
	  
"
query_star <- paste(query_star, where_clause_star, collapse = "\n")
query_star

rlang::inform('--- loading csn data from star.encounter')

sdt <- setDT(DBI::dbGetQuery(ctn, query_star ))

if (anyDuplicated(sdt[,.(mrn,encounter,short_name,value_as_datetime)])) {
  rlang::warn('!!! FIXME: duplicates in star query; forcing unique for now')
  sdt <- unique(sdt[,.(mrn,encounter,short_name,value_as_datetime)])
  # now pick this first value (arbitrary!) after ordering
  sdt <- sdt[order(mrn,encounter,short_name,value_as_datetime),
             .SD[1],
             by=.(mrn,encounter,short_name)]
}

sdt <- data.table::dcast(
  sdt, mrn + encounter ~ short_name, value.var = 'value_as_datetime')
setnames(sdt, 'ARRIVAL_TIME', 'visit_start_datetime')
setnames(sdt, 'DISCH_TIME', 'visit_end_datetime')
sdt <- sdt[order(mrn, visit_start_datetime), 
           .(mrn, visit_start_datetime,visit_end_datetime, encounter)]


rlang::inform('--- synchronising time zones')

# CONVERT TO UTC timezone before joining
sdt[, visit_start_datetime := with_tz(visit_start_datetime, 'UTC')]
sdt[, visit_end_datetime := with_tz(visit_end_datetime, 'UTC')]
sdt

# assertthat::assert_that(nrow(rdt) == nrow(sdt))
# str(rdt)
# str(sdt)

# Now force both into the same tz (UTC) before joining else join fails even though times match
sdt[, visit_start_datetime := force_tz(visit_start_datetime, 'UTC')]
sdt[, visit_end_datetime := force_tz(visit_end_datetime, 'UTC')]
sdt
rdt[, visit_start_datetime := force_tz(visit_start_datetime, 'UTC')]
rdt[, visit_end_datetime := force_tz(visit_end_datetime, 'UTC')]
rdt

rlang::inform('--- joining to produce csn to visit_occurrence lookup')

tdt <- sdt[rdt, on=.NATURAL]
tdt

if (uniqueN(tdt[is.na(encounter)])) {
  n <- uniqueN(tdt[is.na(encounter),visit_occurrence_id])
  rlang::warn(paste(
    '!!! Unable to find encounters for',
    n, 'of',
    uniqueN(tdt$visit_occurrence_id), 'unique visits'))
}

# single assertion that checks that visit_occurrence (rdt) has now lost rows
# assertthat::assert_that(nrow(rdt) == nrow(tdt))
# assertthat::assert_that(nrow(sdt) == nrow(tdt))

rlang::inform('--- writing lookup table out to icu_audit')

DBI::dbWriteTable(ctn, name=target_table_path, value=tdt, overwrite=TRUE)
DBI::dbDisconnect(ctn)

rlang::inform('--- closing database connection')
rlang::inform('--- script complete')