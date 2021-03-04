# 2021-01-23 adapted from make_covid
# build NIV data for Ronan

# TODO rebuild as an inpatient admissions view with ICU and NIV as 'attributes'
source('omopify/create_niv_filter.R')
source('omopify/create_care_site.R')
source('omopify/create_person.R')
source('omopify/create_visit_occurrence.R')
source('omopify/create_visit_detail.R')
source('omopify/create_caboodle_covid.R')

# build reporting data
source('report/make_icu_admissions_table.R')
