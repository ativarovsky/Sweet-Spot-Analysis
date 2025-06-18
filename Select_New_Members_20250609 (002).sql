
--CONNECT DB-PROD-DWH
	use datalake;

--TODAY AND FUTURE ELIGIBLE FQ MEMBERS
	drop table if exists #today_and_future_elig_fq_members;
	select mh.memb_keyid, mh.company_id, mh.hpcode, mc.MEMB_MPI_NO --, min(mh.opfromdt) as min_from_dt, max(mh.opthrudt) as max_thru_dt, count(*) as cnt
	into #today_and_future_elig_fq_members
	from 
		ezcap.memb_hphists mh with(nolock)
		inner join ezcap.memb_company mc with(nolock)
		on mh.memb_keyid = mc.MEMB_KEYID
	where 
		mh.company_id in ('ALTAMED','ALTAOC','ALTACHLA')	--FQ ONLY, EXCLUDE PACE, ALTANET, AND OMNICARE
		AND
		(
		cast(getdate() as date) between isnull(mh.opfromdt,cast(getdate() as date)) and isnull(mh.opthrudt,cast(getdate() as date)) --eligible today
		OR
		cast(getdate() as date) < isnull(mh.opfromdt,cast(getdate() as date)) --eligible in future
		)
		AND
		isnull(mh.opfromdt,cast(getdate() as date)) <> isnull(mh.opthrudt,cast(getdate() as date)) --EXCLUDE CASES OF INVALID ELIGIBILITY LOAD (OPFROMDT = OPTHRUDT)
		AND
		mh.LOADDATE between '2024-06-01' and '2024-06-30'	--ELIGIBILITY LOADED THIS MONTH
	group by  mh.memb_keyid, mh.company_id, mh.hpcode, mc.MEMB_MPI_NO;
	--379823

select count(*) 
from #today_and_future_elig_fq_members

--DETERMINE UNIQUE LIST OF ABOVE PATIENTS FROM DWH
	drop table if exists #UNIQ_DWH_IDS;
	SELECT DAP.ALLPATIENTID, DAP.CurrentPatientSID 
	INTO #UNIQ_DWH_IDS
	FROM 
		ALTAMED_DWH.DBO.DIMALLPATIENT DAP WITH(NOLOCK)
		INNER JOIN #today_and_future_elig_fq_members tafefm
		ON DAP.AllPatientID = CAST(tafefm.MEMB_MPI_NO AS VARCHAR(36))
	GROUP BY DAP.ALLPATIENTID, DAP.CurrentPatientSID;

--DETERMINE UNIQUE LIST OF ABOVE PATIENTS SEEN BY DWH PRIOR TO THIS MONTH REGARDLESS OF SOURCE SYSTEM
	drop table if exists #MEMBERS_SEEN_IN_SYSTEM_PRIOR_TO_CURRENT_MONTH_LOAD;
	SELECT DISTINCT UDI.* 
	INTO #MEMBERS_SEEN_IN_SYSTEM_PRIOR_TO_CURRENT_MONTH_LOAD
	FROM 
		#UNIQ_DWH_IDS UDI
		INNER JOIN ALTAMED_DWH.DBO.DIMALLPATIENT DAP WITH(NOLOCK)
		ON UDI.CurrentPatientSID = DAP.CurrentPatientSID
	WHERE DAP.ETL_CreateDate < '2024-06-01';	--SEEN BY DWH PRIOR TO CURRENT MONTH

-- select count(*) from #MEMBERS_SEEN_IN_SYSTEM_PRIOR_TO_CURRENT_MONTH_LOAD

--NET NEW PATIENTS LOADED THIS MONTH AND NEVER SEEN BEFORE BY DWH/ALTAMED SYSTEM(S) IN PRIOR MONTHS
	drop table if exists #net_new_members_jun_2024;
	SELECT tafefm.* 
	into #net_new_members_jun_2024
	FROM 
		#today_and_future_elig_fq_members tafefm
		LEFT JOIN #MEMBERS_SEEN_IN_SYSTEM_PRIOR_TO_CURRENT_MONTH_LOAD msisptcml
		ON tafefm.MEMB_MPI_NO = msisptcml.AllPatientID
	WHERE msisptcml.AllPatientID IS NULL;
	--2272

select count(*) 
from #net_new_members_jun_2024