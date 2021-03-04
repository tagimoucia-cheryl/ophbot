-- 2021-01-09
-- V simple view that produces the foreign keys need to define patients who have ever been in critical care

SELECT DISTINCT
	 p.core_demographic_id
  ,mrn.mrn_id
  ,mrn_to_live.mrn_id AS mrn_id_alt
	,mrn.mrn
	,mrn.nhs_number
	,vd.hospital_visit_id 
	,vo.encounter
FROM star_a.location_visit vd 

LEFT JOIN star_a.location loc ON vd.location_id = loc.location_id
LEFT JOIN icu_audit.emapr_location_attribute locatt ON loc.location_string = locatt.location_string

-- get hospital_visit id
LEFT JOIN star_a.hospital_visit vo ON vd.hospital_visit_id = vo.hospital_visit_id
-- get core_demographic id
LEFT JOIN star_a.core_demographic p ON vo.mrn_id = p.mrn_id

-- get current MRN
LEFT JOIN star_a.mrn_to_live ON p.mrn_id = mrn_to_live.mrn_id
LEFT JOIN star_a.mrn ON mrn_to_live.live_mrn_id = mrn.mrn_id

-- where ever seen in a critical care bed
WHERE 
	--loc.ward IN  ('T03', 'T07CV', 'P03CV', 'SINQ', 'MINQ', 'WSCC')
	locatt.attribute_name = 'critical_care' AND locatt.value_as_integer = 1
	-- in theory should now join against rolling date to confirm attribute was valid for that bed visit
	-- but this is prob not necessary for critical care

;
