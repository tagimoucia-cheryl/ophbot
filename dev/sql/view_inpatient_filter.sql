-- 2021-01-24
-- V simple view that produces the foreign keys need to define inpatients

SELECT DISTINCT
	
	 p.core_demographic_id
  ,mrn.mrn_id
  ,mrn_to_live.mrn_id AS mrn_id_alt
	,mrn.mrn
	,mrn.nhs_number
	,vo.hospital_visit_id 
	,vo.encounter

FROM star_a.hospital_visit vo 
-- get core_demographic id
LEFT JOIN star_a.core_demographic p ON vo.mrn_id = p.mrn_id
-- get current MRN
LEFT JOIN star_a.mrn_to_live ON p.mrn_id = mrn_to_live.mrn_id
LEFT JOIN star_a.mrn ON mrn_to_live.live_mrn_id = mrn.mrn_id

-- where inpatient
WHERE vo.patient_class = 'INPATIENT'
;
