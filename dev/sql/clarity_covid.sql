/******** Clarity COVID Status
Contains commented out code to get COVID status from Flowsheet rows which would allow us to do it live.
I haven't done the work to turn the flowsheet rows into a binary metric yet
********/
--use CLARITY_REPORT;

WITH hi_care_beds AS (
	SELECT	BED_ID
			,dep.DEPARTMENT_ID
			,dep.DEPARTMENT_NAME
			,CASE WHEN dep.RPT_GRP_NINE = 20 THEN 'ICU' ELSE 'ECU' END AS DEPARTMENT_TYPE
			,rom.ROOM_NAME
			,bed.BED_LABEL
	FROM CLARITY_REPORT.dbo.CLARITY_DEP				dep
	JOIN CLARITY_REPORT.dbo.CLARITY_ROM				rom
	  ON dep.DEPARTMENT_ID = rom.DEPARTMENT_ID
	JOIN CLARITY_REPORT.dbo.CLARITY_BED				bed
	  ON rom.ROOM_ID = bed.ROOM_ID
	WHERE (dep.DEPARTMENT_ID in (1021100002 --wms
								,1020200013 -- SITU
								,2019000008  -- T07 CV surge
								,1020100014 -- t03
								,1020200006 -- MITU
								,2019000001 --p03cv
								,1020100162 -- ECU
								,1020100023 -- t08n
								)
		AND bed_label <> 'WAIT'
		AND BED_ID <> '7188') -- PLEX Room ON MITU
		AND bed.CENSUS_INCLUSN_YN = 'Y'
		AND bed.RECORD_STATE is null
	GROUP BY bed.BED_ID,dep.DEPARTMENT_ID,dep.DEPARTMENT_NAME, dep.RPT_GRP_NINE ,rom.ROOM_NAME ,bed.BED_LABEL
),

recent_hi_care_stays AS (
	SELECT *
	FROM (
		SELECT adt.PAT_ENC_CSN
			  ,enc.PAT_ID
			  ,pt.PAT_NAME
			  ,pt.PAT_MRN_ID
			  ,pt.DEATH_DATE
			  ,ADT_DEPARTMENT_ID
			  ,ADT_DEPARTMENT_NAME
			  ,ADT_BED_ID
			  ,PAT_OUT_DTTM
			  ,ROW_NUMBER()	OVER (PARTITION BY PAT_ENC_CSN ORDER BY IN_DTTM DESC) AS REVERSE_BED_RANK
		FROM CLARITY_REPORT.dbo.V_PAT_ADT_LOCATION_HX			adt
		JOIN CLARITY_REPORT.dbo.PAT_ENC							enc
			ON adt.PAT_ENC_CSN = enc.PAT_ENC_CSN_ID
		JOIN CLARITY_REPORT.dbo.PATIENT							pt
			ON enc.PAT_ID = pt.PAT_ID
		WHERE ADT_DEPARTMENT_ID in (1021100002 --wms
								,1020200013 -- SITU
								,2019000008  -- T07 CV surge
								,1020100014 -- t03
								,1020200006 -- MITU
								,2019000001 --p03cv
								,1020100162 -- ECU
								,1020100023 -- t08n
								)
				AND EVENT_TYPE_C in (1,3)
				AND PAT_NAME not like '%TEST%'
				AND ADT_BED_LABEL_WID not like 'WAIT%'
				AND DATEDIFF(DAY, OUT_DTTM, GETDATE()) <= 2
			) t1
	WHERE REVERSE_BED_RANK = 1
),

filtered_adt AS (
    SELECT EVENT_ID
		  ,EVENT_TYPE_C
		  ,PAT_ENC_CSN
		  ,ADT_DEPARTMENT_ID
		  ,ADT_DEPARTMENT_NAME
		  ,dep.RPT_GRP_NINE			department_type_id
		  ,ADT_BED_ID
		  ,ADT_BED_LABEL_WID
		  ,IN_DTTM
		  ,OUT_DTTM
		  ,PAT_OUT_DTTM
    FROM CLARITY_REPORT.dbo.V_PAT_ADT_LOCATION_HX adt
	JOIN CLARITY_DEP dep
		ON adt.ADT_DEPARTMENT_ID = dep.DEPARTMENT_ID
	WHERE ADT_DEPARTMENT_NAME IS NOT NULL
		AND SPECIALTY not in ('Anaesthetics', 'Diagnostic Imaging - Radiology', 'Gastroenterology - Endoscopy', 'Respiratory - Interventional Bronchoscopy')
		AND EVENT_TYPE_C in (1,3)
		AND ADT_BED_LABEL_WID not like 'WAIT%'
),

ward_moves_grouper AS (
    SELECT	rhcs.PAT_ENC_CSN
			, fadt.ADT_DEPARTMENT_ID
			, fadt.ADT_DEPARTMENT_NAME
			, fadt.department_type_id
			, fadt.IN_DTTM
			, fadt.OUT_DTTM
			, fadt.PAT_OUT_DTTM
			, ROW_NUMBER() over(partition by rhcs.PAT_ENC_CSN ORDER BY fadt.IN_DTTM)
				- ROW_NUMBER() over(partition by rhcs.PAT_ENC_CSN, fadt.ADT_DEPARTMENT_NAME ORDER BY fadt.IN_DTTM) AS grouper
    FROM recent_hi_care_stays rhcs
	LEFT JOIN filtered_adt fadt
		ON rhcs.pat_enc_csn = fadt.pat_enc_csn
    ),

ward_moves AS (
	SELECT *
			, LAG(ADT_DEPARTMENT_ID) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) prev_dept_id
			, LAG(ADT_DEPARTMENT_NAME) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) prev_dept_name
			, LAG(department_type_id) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) prev_dept_type_id
			, LEAD(ADT_DEPARTMENT_ID) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) next_dept_id
			, LEAD(ADT_DEPARTMENT_NAME) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) next_dept_name
			, LEAD(department_type_id) OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM) next_dept_type_id
			, ROW_NUMBER() OVER (PARTITION BY PAT_ENC_CSN ORDER BY UNIT_START_DTTM DESC) AS REVERSE_WARD_RANK
	FROM(
		SELECT	PAT_ENC_CSN
				, min(ADT_DEPARTMENT_ID)													ADT_DEPARTMENT_ID
				, min(ADT_DEPARTMENT_NAME)													ADT_DEPARTMENT_NAME
				, min(department_type_id)													department_type_id
				, min(IN_DTTM)																UNIT_START_DTTM
				, max(OUT_DTTM)																OUT_DTTM
				,CASE WHEN MAX(CASE WHEN PAT_OUT_DTTM IS NULL THEN 1 ELSE 0 END) = 0
					THEN MAX(PAT_OUT_DTTM) ELSE NULL END									PAT_OUT_DTTM
		FROM ward_moves_grouper
		GROUP BY PAT_ENC_CSN, grouper
	) T1
),

recent_hi_care_stay_details AS(
    SELECT	rhcs.PAT_ENC_CSN
			,rhcs.PAT_ID
			,rhcs.PAT_NAME
			,rhcs.PAT_MRN_ID
			,rhcs.DEATH_DATE
			,rhcs.ADT_DEPARTMENT_ID
			,rhcs.ADT_DEPARTMENT_NAME
			,rhcs.ADT_BED_ID			LAST_BED_ID
			,rhcs.PAT_OUT_DTTM
			,wm.ADT_DEPARTMENT_NAME		WM_DEPT_NAME
			, wm.UNIT_START_DTTM
			, wm.PAT_OUT_DTTM			UNIT_PAT_OUT_DTTM
			, prev_dept_name
			, next_dept_name
			, CASE WHEN prev_dept_type_id = 20 --ICUs
				THEN 1 ELSE 0 END AS prev_dept_is_icu
			, CASE WHEN next_dept_type_id = 20 --ICUs
				THEN 1 ELSE 0 END AS next_dept_is_icu
    FROM recent_hi_care_stays rhcs
	JOIN ward_moves wm
		ON rhcs.PAT_ENC_CSN = wm.PAT_ENC_CSN
	WHERE REVERSE_WARD_RANK = 1
),

current_inpts as (
	SELECT *
	FROM recent_hi_care_stay_details
	WHERE PAT_OUT_DTTM IS NULL
),

icu_disch_and_death AS (
	SELECT	ADT_DEPARTMENT_NAME
			, COUNT(PAT_OUT_DTTM)			num_icu_discharges
			, COUNT(DEATH_DATE)				num_icu_deaths
	FROM recent_hi_care_stay_details rhcsd
	WHERE ADT_DEPARTMENT_ID != 1020100011 --AMU
			AND next_dept_is_icu = 0
			AND  PAT_OUT_DTTM >=  dateadd(hour, -16, DATEADD(dd, 0, DATEDIFF(dd, 0, GETDATE()))) -- yesterday_8am
	GROUP BY ADT_DEPARTMENT_NAME
),

non_covid_inf_status AS (
-- This gives one of the multiple possible infections that a patient can have
-- COVID   INFECTION_TYPE_C = 72, ?COVID  INFECTION_TYPE_C = 73
	SELECT
		PAT_ID
		, min(zci.NAME)			AS other_infection_status
	FROM CLARITY_REPORT.dbo.INFECTIONS		inf
	JOIN CLARITY_REPORT.dbo.ZC_INFECTION	zci
		ON inf.INFECTION_TYPE_C = zci.INFECTION_C
	WHERE RESOLVE_UTC_DTTM IS NULL
		AND INFECTION_TYPE_C not in (72,73)
	GROUP BY PAT_ID
),

ic_cov_status AS (
-- It is possible to have both COVID AND ?COVID status simultaneously
-- COVID   INFECTION_TYPE_C = 72, ?COVID  INFECTION_TYPE_C = 73
	SELECT *
	FROM (
		SELECT
			PAT_ID
			, zci.NAME		AS ic_covid_status
			, ONSET_DATE	AS ic_covid_onset_date
			, DENSE_RANK() OVER (partition by PAT_ID ORDER BY ONSET_DATE DESC, INFECTION_TYPE_C ASC) AS rnk
		FROM CLARITY_REPORT.dbo.INFECTIONS inf
		JOIN CLARITY_REPORT.dbo.ZC_INFECTION zci
			ON inf.INFECTION_TYPE_C = zci.INFECTION_C
		WHERE RESOLVE_UTC_DTTM IS NULL
			AND INFECTION_TYPE_C in (72,73) -- COVID +ve INFECTION_TYPE_C = 72, ?COVID INFECTION_TYPE_C = 73
	) t1
	WHERE rnk = 1
),

pl_cov_status AS (
	SELECT
		PAT_ID
		, min(edg.DX_NAME)		AS pl_covid_status -- relies ON the fact that COVID is earlier in the alphabet than ?COVID
		, count(dx_name)		AS count_pl_entries
	FROM CLARITY_REPORT.dbo.PROBLEM_LIST pl
	JOIN CLARITY_REPORT.dbo.CLARITY_EDG edg
		ON pl.DX_ID = edg.DX_ID
	WHERE pl.dx_id in (1801624, 1801625, 1494811383, 1494811626, 1494811646, 1494816042)
		AND RESOLVED_DATE IS NULL
	GROUP BY PAT_ID
),

isolatn_status AS (
	SELECT
		PAT_ID
		, min(zci.NAME) AS ISOLATION_STATUS -- a very dirty hack to ensure that only one isolation status per patient is returned
	FROM CLARITY_REPORT.dbo.HSP_ISOLATION iso
	JOIN CLARITY_REPORT.dbo.ZC_ISOLATION zci
		ON iso.ISOLATION_C = zci.ISOLATION_C
	WHERE ISO_RMVD_TIME IS NULL
	GROUP BY PAT_ID
)

/*
covid_flo AS (
	SELECT
		PAT_ID
		, PAT_ENC_CSN_ID
		, max(CASE WHEN flo_meas_id = '40449' THEN MEAS_VALUE END) AS covid_intubation_date
		, max(CASE WHEN flo_meas_id = '40448' THEN MEAS_VALUE END) AS covid_icu_admission_date
		, max(CASE WHEN flo_meas_id = '40445' THEN MEAS_VALUE END) AS covid_symptom_onset
	FROM
		(SELECT *
		FROM
			(SELECT
				enc.PAT_ID
				,PAT_ENC_CSN_ID
				,rank() over (partition by pat_enc_csn_id, ifm.flo_meas_id ORDER BY recorded_time desc) AS rank
				,FLO_MEAS_NAME
				,DISP_NAME
				,ifm.FLO_MEAS_ID
				,MEAS_VALUE
			FROM CLARITY_REPORT.dbo.PAT_ENC								enc
			JOIN  CLARITY_REPORT.dbo.IP_FLWSHT_REC						ifr
				ON enc.INPATIENT_DATA_ID = ifr.INPATIENT_DATA_ID
			JOIN  CLARITY_REPORT.dbo.IP_FLWSHT_MEAS						ifm
				ON ifr.FSD_ID = ifm.FSD_ID
			JOIN  CLARITY_REPORT.dbo.IP_FLO_GP_DATA						ifgd
				ON ifm.FLO_MEAS_ID = ifgd.FLO_MEAS_ID
			WHERE ifm.FLO_MEAS_ID in ('40449','40448', '40445')
				AND meas_value IS NOT NULL
			) t1
		WHERE rank = 1) t2
	GROUP BY pat_id, PAT_ENC_CSN_ID
),
*/


SELECT	department
		,bay
		,bed
		,mrn
		,csn
		--,covid_symptom_onset
		--,covid_icu_admission_date
		--,covid_intubation_date
		,ic_covid_status
		,pl_covid_status
		,infection_status
		,CASE WHEN infection_status = 'Positive' AND ic_covid_status = 'COVID-19'
				THEN 1 else 0 END											currently_infectious
FROM (
	SELECT
		DEPARTMENT_NAME																	department
		,ROOM_NAME																		bay
		,BED_LABEL																		bed
		,BED_ID
		,icupts.PAT_MRN_ID																mrn
		,icupts.PAT_ENC_CSN																csn
		,ic_covid_status
		,ic_covid_onset_date
		,pl_covid_status
		--,covid_symptom_onset
		--,covid_icu_admission_date
		--,covid_intubation_date
		,CASE WHEN (ic_covid_status = 'COVID-19' OR
					ic_covid_status IS NULL AND pl_covid_status IS NOT NULL)
					THEN 'Positive'
				WHEN ic_covid_status = '?COVID-19' THEN 'Query' END						infection_status
	FROM hi_care_beds
	LEFT JOIN current_inpts icupts
		ON hi_care_beds.BED_ID = icupts.LAST_BED_ID
	LEFT JOIN non_covid_inf_status ncif
		ON icupts.PAT_ID = ncif.PAT_ID
	LEFT JOIN ic_cov_status
		ON icupts.PAT_ID = ic_cov_status.PAT_ID
	LEFT JOIN pl_cov_status
		ON icupts.PAT_ID = pl_cov_status.PAT_ID
	LEFT JOIN isolatn_status
		ON icupts.PAT_ID = isolatn_status.PAT_ID
	--LEFT JOIN covid_flo
		--ON icupts.PAT_ENC_CSN = covid_flo.PAT_ENC_CSN_ID
	) t1
ORDER BY department, bed_id
;
