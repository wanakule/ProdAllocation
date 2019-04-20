TRUNCATE TABLE prodalloc.dbo.ppp_sum12
INSERT INTO prodalloc.dbo.ppp_sum12
SELECT LEFT(PointName,3) WF, MonYr, SUM(avgval) WFProd
FROM (
	SELECT OP.PointName
		, FORMAT(TS.TimeSeriesDateTime,'yyyy-MM','en-US') MonYr
		, AVG(TS.TimeSeriesValue) avgval
		---, TS.TimeSeriesDateTime
		---, TS.TimeSeriesValue
	FROM ParameterData PD
	INNER JOIN OROPPoint OP ON OP.PointID=PD.PointID
	INNER JOIN TimeSeries TS ON TS.ParameterDataID=PD.ParameterDataID
	WHERE PD.Description like '%Production Well Water Production' AND 
		(TS.TimeSeriesDateTime BETWEEN '10/1/2017' AND '9/30/2018')
		---AND LEFT(PointName,3)='SCH'
	GROUP BY OP.PointName
		, FORMAT(TS.TimeSeriesDateTime,'yyyy-MM','en-US')
) A
GROUP BY LEFT(PointName,3), MonYr
ORDER BY WF, MonYr

