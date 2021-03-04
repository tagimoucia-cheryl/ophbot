# build covid data

source('omopify/create_cc_filter.R')
source('omopify/create_care_site.R')
source('omopify/create_person.R')
source('omopify/create_visit_occurrence.R')
source('omopify/create_visit_detail.R')
source('omopify/create_caboodle_covid.R')

# build reporting data
source('report/make_icu_admissions_table.R')
