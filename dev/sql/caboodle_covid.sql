         
         /* The first CTE selects the (commonly used) COVID entries from the problem list. The rownum
         bit is there just in case there are multiple Covid related entried in the problem list.
         This query pricks the most recent one. There's also a somewhat arbitrary cutoff that the diagnosis
         needs to be within the last 60 days.
         */
         with pl_covid as (
             SELECT * from
             (
                 select ef.EncounterEpicCsn
                         , dd.Name             as pl_covid_status
                         , def._CreationInstant
                         , ROW_NUMBER() over (partition by EncounterEpicCsn order by def._CreationInstant desc) as rownum
                 from  [CABOODLE_REPORT].[dbo].[DiagnosisEventFact] def
                 join [CABOODLE_REPORT].[dbo].[DiagnosisDim] dd
                 on def.DiagnosisKey = dd.DiagnosisKey
                 left join [CABOODLE_REPORT].[dbo].EncounterFact ef
                     on def.EncounterKey = ef.EncounterKey
                 where DiagnosisEpicId in (1801624, 1801625, 1494811383, 1494811626, 1494811646, 1494816042)
                     --and Status = 'Active'
                     --and DATEDIFF(day,def._CreationInstant,GETDATE()) < 60
             ) t1
             where rownum = 1
         ),
         
         ic_covid as (
             SELECT * from
             (
                 select    pd.PrimaryMrn
                         , EncounterEpicCsn
                         , InfectionName               as ic_covid_status
                         , AddedInstant
                         , ROW_NUMBER() over (partition by PrimaryMrn order by AddedInstant desc) as rownum
                 from [CABOODLE_REPORT].[dbo].[InfectionStatusUclhFactX] inf
                 join [CABOODLE_REPORT].[dbo].[PatientDim] pd
                 on inf.PatientEpicId = pd.PatientEpicId
                 where InfectionTypeId in(67,68)
                     --and DATEDIFF(day,AddedInstant,GETDATE()) < 60 --Needs to be within the last 60 days
             ) t1
             where rownum = 1
         ),
         
final as (
   SELECT
      encounter_csn as csn,
      --Primary_MRN as mrn,
      --ward_name,
      --bed_name,
      --bed_id,
      --covid_status,                   -- COVID status according to the data mart
      --Infectious_YesNo,                -- Is the patient considerd to be infectious
      --Infectious_Period_End_Dttm,
      --pl_covid_status,             -- COVID status according to the problem list
      --ic_covid_status,             -- COVID status according to the Infection Status table
      --case when COVID_Status is null then 'No Infection' else COVID_Status end    as dm_infection_status, -- the original definition
      case when pl_covid_status is not NULL then 'Positive'
         when COVID_Status is null then 'No Infection' 
          else COVID_Status end                                        as infection_status,  -- new and improved
      case when Infectious_YesNo = 'Yes' and Infectious_Period_End_Dttm is NULL
          then 1 else 0 end as currently_infectious
   FROM [CABOODLE_REPORT].[WIP].[COVDM_Dataset] covdm
   left join pl_covid
      on covdm.Encounter_CSN = pl_covid.EncounterEpicCsn
   left join ic_covid
      on covdm.Encounter_CSN = pl_covid.EncounterEpicCsn
   WHERE is_encounter_record = 1
        and bed_status_end_dttm is null
        -- FIXME: check with Tim what the purpose was of this line; appears to just filter
        --AND encounter_csn IN (SELECT value FROM STRING_SPLIT(?, ','))
        and Effective_End_Dttm is null
)

SELECT 
   csn,
   case 
      when infection_status = 'Positive' and currently_infectious = 0 then 'Covid Positive (not infectious)'
      when infection_status = 'Positive' and currently_infectious = 1 then 'Covid Positive (infectious)'
      when infection_status = 'Query' then 'Covid Query'
      else infection_status end as infection_status 
 
FROM final order by csn;
