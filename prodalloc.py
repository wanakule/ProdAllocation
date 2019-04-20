import sys
import os
import math
import time
import datetime as dt
import numpy as np
import pandas as pd
from contextlib import contextmanager


def main(RID=0, SID=0, f_excel=None, f_out=None, f_log=None):
    import multiprocessing as mp

    # setup shared namespace
    mgr = mp.Manager()
    ns = mgr.Namespace()

    # pull data from database for AMPL into shared namespace
    (ns.df_demand, ns.wup_12mavg, ns.ppp_sum12, ns.df_scenario, ns.sw_avail,
        ns.df_penfunc, ns.df_relcost) = pull_data()
    kargs = {'shared_ns': ns}
    # kargs = {'shared_ns': None}

    # setup to call run parallel processing - call prodalloc by tuple (RID,SID)
    rid = [0]*6
    sid = [0, 1, 2]*2
    pargs = [(jr, js) for jr in rid for js in sid]
    if f_out != None:
        f_out = f_out[:-4]
        #### output files must be unique to avoid file collision - use set
        pargs = [(jr, js, '%s_%03d_%d.out' % (f_out, jr, js)) for (jr, js) in pargs]

    # p = mp.Pool(min(len(sid), 18))
    # print(list(map(prodalloc_1arg, pargs)))

    procs = [mp.Process(target=prodalloc_1arg, args=(arg, kargs)) for arg in pargs]
    for p in procs: p.start()
    for p in procs: p.join()
        

def test_main(RID=0, SID=0, f_excel=None, f_out=None, f_log=None):
    """
    Test main without multiprocessing
    """
    prodalloc_1arg([RID, SID], {'shared_ns': None})


def prodalloc_1arg(argvs, kargvs):
    stime = time.time()
    prodalloc(*argvs, **kargvs)
    print(f'ProcessID: {os.getpid()}' + (r' ; Elasped Time: %.2f sec' % (time.time() - stime)))


def prodalloc(RID, SID, shared_ns=None, f_out=None, f_log=None):
    from amplpy import AMPL, DataFrame

    if shared_ns == None:
        (df_demand, wup_12mavg, ppp_sum12, df_scenario, sw_avail,
            df_penfunc, df_relcost) = pull_data(RID, SID)

    # =======================================
    # instantiate AMPL class and set AMPL options
    ampl = AMPL()

    # set options
    ampl.setOption('presolve', False)
    ampl.setOption('solver', 'gurobi_ampl')
    # ampl.setOption('solver', 'cbc')
    ampl.setOption('gurobi_options', 'iisfind=1 iismethod=1 lpmethod=4 mipgap=1e-6 warmstart=1')
    ampl.setOption('reset_initial_guesses', True)
    ampl.setOption('solver_msg', True)

    # real model from model file
    d_cur = os.getcwd()
    f_model = os.path.join(d_cur, 'model.amp')
    ampl.read(f_model)

    if shared_ns != None:
        df_demand = shared_ns.df_demand.query(f'RealizationID == {RID}').loc[
            : , ['wpda', 'dates', 'Demand']
        ]
    dates = df_demand.loc[:, ['dates']].values
    df_demand.loc[:, 'dates'] = [pd.to_datetime(d).strftime('%Y-%b') for d in dates]
    df_demand.set_index(keys=['wpda', 'dates'], inplace=True)
    wpda = sorted(list(set([w for (w, m) in df_demand.index])))
    monyr = df_demand.loc[('COT',),].index.values
    nyears = int(len(monyr)/12.0)
    
    # lambda for determine number of days in a month
    dates = dates[0:(12*nyears)]
    f_ndays_mo = lambda aday: (aday + dt.timedelta(days=32)).replace(day=1) - aday
    ndays_mo = map(f_ndays_mo, [pd.to_datetime(d[0]) for d in dates])
    ndays_mo = [i.days for i in ndays_mo]

    # add data to sets -- Demand
    ampl.getParameter('nyears').value = nyears
    ampl.getSet('monyr').setValues(monyr)
    ampl.getSet('wpda').setValues(wpda)
    ampl.getParameter('demand').setValues(DataFrame.fromPandas(df_demand))
    ampl.getParameter('ndays_mo').setValues(ndays_mo)
    
    # index to year number
    yearno = [(i // 12) + 1 for i in range(len(dates))]
    ampl.getParameter('yearno').setValues(np.asarray(yearno))
    monthno = [pd.to_datetime(d[0]).month for d in dates]
    ampl.getParameter('monthno').setValues(np.asarray(monthno))

    # ---------------------------------------
    # WUP and preferred ranges
    if shared_ns != None:
        wup_12mavg = shared_ns.wup_12mavg
    ampl.getParameter('wup_12mavg').setValues(DataFrame.fromPandas(
        wup_12mavg.loc[:,['wup_12mavg']]))
    ampl.getParameter('prod_range_lo').setValues(DataFrame.fromPandas(
        wup_12mavg.loc[:,['prod_range_lo']]))
    ampl.getParameter('prod_range_hi').setValues(DataFrame.fromPandas(
        wup_12mavg.loc[:,['prod_range_hi']]))

    # add ppp_sum12
    if shared_ns != None:
        ppp_sum12 = shared_ns.ppp_sum12
    ppp_sum12.loc[:, 'monyr'] = [i for i in range(1, 12)] * 3
    ppp_sum12.set_index(keys=['WF', 'monyr'], inplace=True)
    ampl.getParameter('ppp_sum12').setValues(DataFrame.fromPandas(ppp_sum12))

    # Relative cost of water per a million gallon
    if shared_ns != None:
        df_relcost = shared_ns.df_relcost
    ampl.getParameter('relcost').setValues(DataFrame.fromPandas(df_relcost))

    # ---------------------------------------
    # Scenario's data
    if shared_ns != None:
        df_scenario = shared_ns.df_scenario.query(f'ScenarioID=={SID}').loc[
            : , ['ParameterName', 'MonthNo', 'Value']
        ]
    AVAIL_PCTILE = df_scenario.query(f"ParameterName == 'AVAIL_PCTILE'")
    AVAIL_PCTILE = AVAIL_PCTILE.loc[AVAIL_PCTILE.index, 'Value'].values[0]
    RES_INIT = df_scenario.query(f"ParameterName == 'RES_INIT'")
    RES_INIT = RES_INIT.loc[RES_INIT.index,'Value'].values[0]
    # Surface Water Availability Data by month repeated for nyears
    ampl.getParameter('avail_pctile').value = AVAIL_PCTILE
    if shared_ns != None:
        sw_avail = shared_ns.sw_avail.query(f'Percentile == {AVAIL_PCTILE}').loc[
            : , ['source', 'monthno', 'value']
        ]
    # sw_avail = temp.copy()
    # if nyears > 1:
    #     for i in range(1, nyears):
    #         sw_avail = sw_avail.append(temp)
    # srcs = sw_avail.loc[:, 'source'].unique()
    # for j in srcs:
    #     sw_avail.loc[sw_avail['source']==j,'monthno'] = [i+1 for i in range(len(monyr))]
    # sw_avail.set_index(keys=['source', 'monthno'], inplace=True)
    # ampl.getParameter('ngw_avail').setValues(DataFrame.fromPandas(sw_avail))
    sw_avail.set_index(keys=['source', 'monthno'], inplace=True)
    ampl.getParameter('ngw_avail').setValues(DataFrame.fromPandas(sw_avail))

    # ---------------------------------------
    # Penalty functions for under utilization
    if shared_ns != None:
        df_penfunc = shared_ns.df_penfunc
    ampl.getParameter('penfunc_x').setValues(
        DataFrame.fromPandas(df_penfunc.loc[:, ['under_limit']]))
    ampl.getParameter('penfunc_r').setValues(
        DataFrame.fromPandas(df_penfunc.loc[:, ['penalty_rate']]))

    '''
    # =======================================
    # Read fixed allocation from spreadsheet
    # f_excel = os.path.join(
    #     d_cur, 'WY 2019 monthly delivery and supply for budget InitialDraft.xlsx')
    sheet_names = ['WY 2019','WY 2020','WY 2021','WY 2022','WY 2023','WY 2024']
    # ch_poc: Central Hills delivery (row 16)
    # reg_lithia: Regional to Lithia (row 20)
    # reg_cot: Regional to City of Tampa (row 26)
    # reg_thic: THIC intertie purchase (row 37)
    # crw_prod: Carrollwood WF production (row 40)
    # eag_prod: Production for Eagle Well (row 41)

    # row index is zero based, minus one header row = -2
    row_offset = -2
    ch_poc, reg_lithia, reg_cot, reg_thic, crw_prod, eag_prod = [], [], [], [], [], []
    # These DV is fixed or receives values from other optimizer
    bud_fix, ds_fix, swtp_fix=[], [], []
    for i in range(nyears):
        df_excel = pd.read_excel(f_excel, sheet_names[i], usecols='C:N', nrows=41)
        ch_poc    .extend(list(df_excel.loc[16 + row_offset, :].values))
        reg_lithia.extend(list(df_excel.loc[20 + row_offset, :].values))
        reg_cot   .extend(list(df_excel.loc[26 + row_offset, :].values))
        reg_thic  .extend(list(df_excel.loc[37 + row_offset, :].values))
        crw_prod  .extend(list(df_excel.loc[40 + row_offset, :].values))
        eag_prod  .extend(list(df_excel.loc[41 + row_offset, :].values))
        
        bud_fix .extend(list(df_excel.loc[22 + row_offset, :].values))
        ds_fix  .extend(list(df_excel.loc[36 + row_offset, :].values))
        swtp_fix.extend(list(df_excel.loc[38 + row_offset, :].values))
    '''
    ch_poc     = df_scenario[df_scenario.ParameterName=='ch_poc'].Value
    reg_lithia = df_scenario[df_scenario.ParameterName=='reg_lithia'].Value
    reg_cot    = df_scenario[df_scenario.ParameterName=='reg_cot'].Value
    reg_thic   = df_scenario[df_scenario.ParameterName=='reg_thic'].Value
    crw_prod   = df_scenario[df_scenario.ParameterName=='crw_prod'].Value
    eag_prod   = df_scenario[df_scenario.ParameterName=='eag_prod'].Value

    ampl.getParameter('ch_poc')    .setValues(np.asarray(ch_poc    , dtype=np.float32))
    ampl.getParameter('reg_lithia').setValues(np.asarray(reg_lithia, dtype=np.float32))
    ampl.getParameter('reg_cot')   .setValues(np.asarray(reg_cot   , dtype=np.float32))
    ampl.getParameter('reg_thic')  .setValues(np.asarray(reg_thic  , dtype=np.float32))
    ampl.getParameter('crw_prod')  .setValues(np.asarray(crw_prod  , dtype=np.float32))
    ampl.getParameter('eag_prod')  .setValues(np.asarray(eag_prod  , dtype=np.float32))

    # overloaded function 'VariableInstance_fix' need float64
    bud_fix  = np.asarray(df_scenario[df_scenario.ParameterName=='bud_fix'].Value, dtype=np.float64)
    ds_fix   = np.asarray(df_scenario[df_scenario.ParameterName=='ds_fix'].Value, dtype=np.float64)
    swtp_fix = np.asarray(df_scenario[df_scenario.ParameterName=='swtp_fix'].Value, dtype=np.float64)
    ampl.getParameter('bud_fix')   .setValues(np.asarray(bud_fix   , dtype=np.float32))
    ampl.getParameter('ds_fix')    .setValues(np.asarray(ds_fix    , dtype=np.float32))
    ampl.getParameter('swtp_fix')  .setValues(np.asarray(swtp_fix  , dtype=np.float32))

    # ---------------------------------------
    # initialize/fix variable values
    ampl.getParameter('res_init').value = RES_INIT
    res_vol = ampl.getVariable('res_vol')
    res_vol[0].fix(RES_INIT)

    gw_prod = ampl.getVariable('gw_prod')
    bud_prod = [gw_prod[j,i] for ((j,i),k) in gw_prod.instances() if j=='BUD']
    for i in range(len(bud_prod)): bud_prod[i].fix(bud_fix[i])

    ds_prod = ampl.getVariable('ds_prod')
    for i in range(ds_prod.numInstances()): ds_prod[i+1].fix(ds_fix[i])
    
    swtp_prod = ampl.getVariable('swtp_prod')
    for i in range(swtp_prod.numInstances()): swtp_prod[i+1].fix(swtp_fix[i])

    # ---------------------------------------
    # dump data
    with open('dump.dat', 'w') as f:
        with stdout_redirected(f):
            ampl.display('wpda,monyr')
            ampl.display('demand')
            ampl.display('nyears')
            ampl.display('ndays_mo,yearno,monthno')
            # ampl.display('years')
            # ampl.display('dem_total')
            ampl.display('ch_poc,reg_lithia,reg_cot,reg_thic,crw_prod,eag_prod,bud_fix,ds_fix')
            ampl.display('wup_12mavg')
            ampl.display('ppp_sum12')
            ampl.display('ngw_avail')
            ampl.display('prod_range_lo,prod_range_hi')
            ampl.display('relcost')
            ampl.display('penfunc_x,penfunc_r')

    # =======================================
    # silence solver
    with open('nul', 'w') as f:
        with stdout_redirected(f):
            ampl.solve()

    if f_out != None:
        with open(f_out, 'w') as f:
            print(r'# *** SOURCE ALLOCATION MODEL ****', file=f)
            print(r'# Monthly Delivery and Supply for Budgeting', file=f)
            print('\n# Objective: {}'.format(ampl.getObjective('mip_obj').value()), file=f)

    if (f_log != None) & (ampl.getObjective('mip_obj').result() == 'solved'):
        with open(f_log, "w") as f:
            print('\n\nDump Variable and Constraint Values', file=f)
            with stdout_redirected(f):
                write_log(ampl)

    if ampl.getObjective('mip_obj').result() == 'infeasible':
        if f_log != None:
            with open(f_log, "w") as f:
                with stdout_redirected(f):  
                    write_iis(ampl)
        else:
            write_iis(ampl)

    # =======================================
    # print output
    # groundwater production
    temp = ampl.getVariable('gw_prod').getValues().toPandas().join(
        ampl.getVariable('gw_under').getValues().toPandas()
    ).join(
        ampl.getVariable('gw_over').getValues().toPandas()
    )
    temp.columns = [i.replace('.val', '') for i in temp.columns]

    # pivoting df by source
    cwup_prod = temp.loc[[i for i in temp.index if i[0] == 'CWUP'],:].assign(index=monyr
        ).set_index('index').rename(
        columns={'gw_prod': 'cwup_prod','gw_under':'cwup_under','gw_over':'cwup_over'})
    bud_prod = temp.loc[[i for i in temp.index if i[0] == 'BUD'],:].assign(index=monyr
        ).set_index('index').rename(
        columns={'gw_prod': 'bud_prod','gw_under':'bud_under','gw_over':'bud_over'})
    sch_prod = temp.loc[[i for i in temp.index if i[0] == 'SCH'],:].assign(index=monyr
        ).set_index('index').rename(
        columns={'gw_prod': 'sch_prod','gw_under':'sch_under','gw_over':'sch_over'})
    temp = cwup_prod.join(sch_prod.join(bud_prod))
    gw_results = temp

    temp_avg = temp.groupby(by=yearno).mean().reset_index()
    temp_avg = temp_avg.loc[:, [i for i in temp_avg.columns[1:temp_avg.shape[1]]]]

    if f_out != None:
        with open(f_out, 'a') as f:
            # print heading
            print('\n\n# Monthly Groudwater Production', file=f)
            for l in range(len(temp)):
                if (l % 12) == 0:
                    print(('\n%10s' % 'Yr-Month') +
                        ('%11s' * len(temp.columns) % tuple(temp.columns)), file=f)
                print(('%10s' % monyr[l]) +
                    ('%11.3f' * len(temp.columns) % tuple(temp.iloc[l,:].values)), file=f)
                if (l + 1) % 12 == 0:
                    print(('%10s' % 'Average') +
                        ('%11.3f' * len(temp_avg.columns) % tuple(temp_avg.iloc[l // 12,:].values)), file=f)
            print(('\n%10s' % 'Total Avg') +
                ('%11.3f' * len(temp_avg.columns) % tuple(temp_avg.mean().values)), file=f)

    # ---------------------------------------
    # SWTP Production
    to_swtp = ampl.getVariable('to_swtp').getValues().toPandas()
    to_res = ampl.getVariable('to_res').getValues().toPandas()
    idx = to_swtp.index
    temp = ampl.getVariable('swtp_prod').getValues().toPandas()
    temp = temp.assign(tbc_swtp=to_swtp.loc[[i for i in idx if i[0] == 'TBC']].values)
    temp = temp.assign(alf_swtp=to_swtp.loc[[i for i in idx if i[0] == 'Alafia']].values)
    temp = temp.join(
        ampl.getVariable('res_eff').getValues().toPandas()
    )
    temp = temp.assign(tbc_res=to_res.loc[[i for i in idx if i[0] == 'TBC']].values)
    temp = temp.assign(alf_res=to_res.loc[[i for i in idx if i[0] == 'Alafia']].values)
    temp = temp.join(
        ampl.getVariable('res_inf').getValues().toPandas()
    ).join(
        ampl.getVariable('res_vol').getValues().toPandas()
    )

    # Add availability columns
    temp = temp.assign(tbc_avail=sw_avail.loc[[('TBC', i) for i in monthno], ['value']].values)
    temp = temp.assign(alf_avail=sw_avail.loc[[('Alafia', i) for i in monthno], ['value']].values)

    # Add SW withdraws
    df1 = ampl.getVariable('sw_withdraw').getValues().toPandas()
    idx = temp.index
    temp = temp.assign(tbc_wthdr=df1.loc[[('TBC', i) for i in idx],:].values)
    temp = temp.assign(alf_wthdr=df1.loc[[('Alafia', i) for i in idx],:].values)
    temp.columns = [i.replace('.val', '') for i in temp.columns]
    sw_results = temp

    # Compute annual average
    temp_avg = temp.groupby(by=yearno).mean().reset_index()
    temp_avg = temp_avg.loc[:, [i for i in temp_avg.columns[1:temp_avg.shape[1]]]]

    if f_out != None:
        with open(f_out, 'a') as f:
            # print heading
            print('\n\n# Monthly Surface Water Production', file=f)
            for l in range(len(temp)):
                if (l % 12) == 0:
                    print(('\n%10s' % 'Yr-Month') +
                        ('%10s' * len(temp.columns) % tuple(temp.columns)), file=f)    
                print(('%10s' % monyr[l]) +
                    ('%10.3f' * len(temp.columns) % tuple(temp.loc[float(l + 1),:])), file=f)
                if ((l + 1) % 12) == 0:
                    print(('%10s' % 'Average') +
                        ('%10.3f' * len(temp_avg.columns) % tuple(temp_avg.loc[l//12,:])), file=f)         
            print(('\n%10s' % 'Total Avg') +
                ('%10.3f' * len(temp_avg.columns) % tuple(temp_avg.mean().values)), file=f)

    # ---------------------------------------
    # print multi objective values
    temp = ampl.getVariable('prodcost_avg').getValues().toPandas()
    idx = [i for i in temp.index]
    temp = temp.assign(prod_avg=temp.loc[:, 'prodcost_avg.val'] * 1e-3 /
        np.asarray([df_relcost.loc[i[0],'relcost'] for i in idx]))

    temp = temp.join(
        ampl.getVariable('uu_penalty').getValues().toPandas()
    ).join(
        ampl.getVariable('uu_avg').getValues().toPandas()
    )
    temp.columns = [i.replace('.val', '') for i in temp.columns]
    temp_avg = temp.groupby([i[0] for i in temp.index]).mean().reset_index()

    if f_out != None:
        with open(f_out, 'a') as f:
            print('\n\n# Annual Production and Under Utilization (Opportunity) Costs', file=f)
            for l in range(len(temp)):
                if (l % nyears) == 0:
                    print(('\n%10s%10s' % ('YearNo', 'Source')) +
                        ('%15s' * len(temp.columns) % tuple(temp.columns)), file=f)
                print(('%10d%10s' % (idx[l][1],idx[l][0])) +
                    ('%15.3f' * len(temp.columns) % tuple(temp.loc[[idx[l]],:].values[0])), file=f)
                if ((l + 1) % nyears) == 0:
                    print(('%10s' % 'Average') + 
                        (('%10s' + '%15.3f' * len(temp.columns)) % tuple(temp_avg.iloc[l // nyears,:])), file=f)

    ampl.close()

    # prepare data for ploting
    if f_out != None:
        df_plotdata = df_demand.groupby(level=1).sum().join(
            df_demand.loc[('COT',), ['Demand']].rename(columns={'Demand': 'COT'})
        ).assign(TBW_Demand=lambda x: x.Demand - x.COT).loc[:, ['TBW_Demand']].join(
            gw_results.join(sw_results.set_index(gw_results.index))
        )
        monyr = [pd.Timestamp(i + '-01') for i in df_plotdata.index]
        df_plotdata = df_plotdata.assign(Dates=monyr).set_index('Dates').sort_index()
        df_plotdata = df_plotdata.assign(ndays_mo=ndays_mo)

        plot_results(SID, AVAIL_PCTILE, df_plotdata, f_out)


def pull_data(RID=None, SID=None):
    """
    Pull data from database for AMPL
    """
    import pyodbc

    # Database connection
    dv = '{SQL Server}'
    sv = 'vgridfs'
    db = 'ProdAlloc'
    conn = pyodbc.connect(
        f'DRIVER={dv};SERVER={sv};Database={db};Trusted_Connection=Yes')

    # =======================================
    # Demand ata by WPDA
    where_clause = ''
    add_column = 'RealizationID,'
    if RID != None:
        where_clause = f"WHERE RealizationID={RID} AND MonthYear<'10/1/2020'"
        add_column = ''
    df_demand = pd.read_sql(f"""
        SELECT {add_column} wpda, MonthYear as dates, Demand
        FROM Demand {where_clause}
        ORDER BY RealizationID, WPDA, MonthYear
    """, conn)

    nmonths = df_demand.dates.size / df_demand.wpda.unique().size
    
    wup_12mavg = pd.read_sql("""
        SELECT source, wup_12mavg, prod_range_lo, prod_range_hi
        FROM wup_12mavg
    """, conn, index_col='source')

    ppp_sum12 = pd.read_sql("""
        SELECT WF, monyr, ppp_sum12
        FROM PPP_Sum12
        WHERE (WF='BUD' OR WF='SCH')
            AND monyr<>'2017-10'
        UNION
        SELECT 'CWUP' AS WF, monyr, sum(ppp_sum12) AS ppp_sum12
        FROM PPP_Sum12
        WHERE WF NOT IN ('BUD','SCH','CRW','EAG')
            AND monyr<>'2017-10'
        GROUP BY monyr
        ORDER BY WF, monyr
    """, conn)

    where_clause = ''
    add_column = 'ScenarioID,'
    if SID != None:
        where_clause = f'WHERE ScenarioID={SID} AND MonthNo<={nmonths}'
        add_column = ''
    df_scenario = pd.read_sql(f"""
        SELECT {add_column} ParameterName, MonthNo, Value
        FROM Scenario {where_clause}
        ORDER BY ScenarioID, ParameterName, MonthNo
    """, conn)

    where_clause = ''
    add_column = 'Percentile,'
    AVAIL_PCTILE = df_scenario.query(f"ParameterName == 'AVAIL_PCTILE'")
    AVAIL_PCTILE = AVAIL_PCTILE.loc[AVAIL_PCTILE.index, 'Value'].values[0]
    if SID != None:
        where_clause = f'WHERE Percentile={AVAIL_PCTILE}'
        add_column = ''
    sw_avail = pd.read_sql(f"""
        SELECT {add_column} source, monthno, value
        FROM SW_Availability {where_clause}
        ORDER BY Percentile, Source, MonthNo
    """, conn)

    df_penfunc = pd.read_sql(f"""
        SELECT source, point, capacity, under_limit, penalty_rate
        FROM UnderUtilizationPenalty
        ORDER BY source, point
    """, conn, index_col=['source','point'])

    df_relcost = pd.read_sql(f"""
        SELECT source, relcost
        FROM RelativeCost
    """, conn, index_col='source')
    
    conn.close()
    return df_demand, wup_12mavg, ppp_sum12, df_scenario, sw_avail, df_penfunc, df_relcost


def plot_results(SID, AVAIL_PCTILE, df_plotdata=None, f_out=None):
    """
    Output visualization
    """
    import matplotlib.pyplot as plt
    import re

    # custom color for line plot
    co = [[0,0.4470,0.7410,1.],
        [0.8500,0.3250,0.0980],
        [0.9290,0.6940,0.1250],
        [0.4940,0.1840,0.5560],
        [0.4660,0.6740,0.1880],
        [0.3010,0.7450,0.9330],
        [0.6350, 0.0780, 0.1840]]
        
    # plot to compare hydrographs
    fig1 = plt.figure(1, figsize=(11, 8.5), dpi=100)
    fig1.clf()
    pagetitle = 'Timeseries of Groundwater and Surface Water Production'
    fig1.suptitle(f'{pagetitle}\nFor RealizationID: {SID}, Availability Percentile: {AVAIL_PCTILE}', fontsize=9)
    fontsize = 7

    # Production 
    fig1.add_subplot(2, 1, 1)
    r = re.compile('.*(prod)')
    df_temp = df_plotdata.loc[:, ['TBW_Demand'] + list(filter(r.match, df_plotdata.columns))]
    ax = df_temp.plot(kind='line', grid=True, fontsize=fontsize, use_index=True, lw=0.75, color=co,
            title='Production', ax=fig1.gca(), legend=None, sharex=False
    )
    ax.set_xlim(df_temp.index[0], df_temp.index[-1])
    ax.title.set_size(fontsize)
    ax.set_xlabel('Date', fontsize=fontsize)
    ax.set_ylabel('Production, mgd', fontsize=fontsize)
    plt.legend(('TBW Demand', 'CWUP', 'SCH', 'BUD', 'SWTP'), fontsize=fontsize, loc=1)

    # Under utilization
    fig1.add_subplot(2, 1, 2)
    df_temp = df_plotdata.loc[:,['tbc_avail','tbc_wthdr','alf_avail','alf_wthdr','res_vol','res_eff','ndays_mo']]
    df_temp = df_temp.assign(
        tbc_under=lambda x: x.tbc_avail - x.tbc_wthdr
    ).assign(
        alf_under=lambda x: x.alf_avail - x.alf_wthdr
    ).assign(
        res_under=pd.DataFrame(
            df_temp.apply(lambda x: max(min(max(x['res_vol'] - 4., 0.)*1e3/365.25,100.)-x['res_eff'],0.),
            axis=1)).iloc[:,0]
    ).loc[:, ['tbc_under', 'alf_under', 'res_under']]
    df_temp = df_plotdata.loc[:, ['cwup_under', 'bud_under', 'sch_under']].join(df_temp)
    ax = df_temp.plot(kind='line', grid=True, fontsize=fontsize, use_index=True, lw=0.75, color=co,
            title='Under-Utilization', ax=fig1.gca(), legend=None, sharex=False
    )
    ax.set_xlim(df_temp.index[0], df_temp.index[-1])
    ax.title.set_size(fontsize)
    ax.set_xlabel('Date', fontsize=fontsize)
    ax.set_ylabel('Utilization, mgd', fontsize=fontsize)
    plt.legend(('CWUP', 'SCH', 'BUD', 'TBC', 'Alafia', 'Reservoir'), fontsize=fontsize, loc=1)

    fig1.tight_layout()
    fig1.subplots_adjust(top=0.90)
    # plt.show()

    f_fig = f_out[:(len(f_out) - 4)]
    fig1.savefig(f"{f_fig}.pdf", dpi=300, orientation='landscape', papertype='letter')
    fig1.savefig(f"{f_fig}.png", dpi=300, orientation='landscape', papertype='letter')

    plt.close()


def write_log(ampl):
    """
    Dump variables and constraints to log file
    """
    
    ampl.eval(r'''
    printf "\nList of variables:\n";
    printf "%25s%12s%12s%12s%12s\n",
        "Variable Name","Slack","LBound","Value","UBound";
    printf {i in {1.._nvars}}: "%25s%12.5f%12.5f%12.5f%12.5f\n",
        _varname[i],_var[i].slack,_var[i].lb,_var[i],_var[i].ub;
    ''')

    ampl.eval(r'''
    printf "\nList of constraints:\n";
    printf "%25s%12s%12s%12s%12s\n",
        "Constraint Name","Slack","LBound","Value","UBound";
    printf {i in {1.._ncons}}: "%25s%12.5f%12.5f%12.5f%12.5f\n",
        _conname[i],_con[i].slack,_con[i].lb,_con[i].body,_con[i].ub;
    ''')


def write_iis(ampl):
    """
    Irreduciable Infeasible Sets to log file and exit
    """

    ampl.eval(r'''
    printf "\nList of variables in the Irriducible Infeasible Subset (IIS):\n";
    printf "%25s%12s%12s%12s%12s%8s\n",
        "Variable Name","Slack","LBound","Value","UBound","IIS";
    printf {i in {1.._nvars}: _var[i].iis_num>0}: "%25s%12.5f%12.5f%12.5f%12.5f%8s\n",
        _varname[i],_var[i].slack,_var[i].lb,_var[i],_var[i].ub,_var[i].iis;
    ''')

    ampl.eval(r'''
    printf "\nList of violated constraints:\n";
    printf "%25s%12s%12s%12s%12s%8s\n",
        "Constraint Name","Slack","LBound","Value","UBound","IIS";
    printf {i in {1.._ncons}: _con[i].iis_num>0}: "%25s%12.5f%12.5f%12.5f%12.5f%8s\n",
        _conname[i],_con[i].slack,_con[i].lb,_con[i].body,_con[i].ub,_con[i].iis;
    ''')
    
    sys.exit()


@contextmanager
def stdout_redirected(new_stdout):
    save_stdout = sys.stdout
    sys.stdout = new_stdout
    try:
        yield None
    finally:
        sys.stdout = save_stdout


def parse_args(argvs):
    import getopt
    from functools import reduce

    # ---------------------------------------
    # default avail_pctile, res_init
    arg_default = {'realization_id': 0, 'scenario_id': 0, 'fname_excel': 'Monthly Allocation.xlsx',
                   'infile': 'prodalloc.csv', 'outfile': None, 'logfile': None}
    prog_args = {'RID': 'realization_id', 'SID': 'scenario_id',
                 'f_excel': 'fname_excel', 'f_out': 'outfile', 'f_log': 'logfile'}
    arg_keys = arg_default.keys()
    longopts = [f'{i}=' for i in arg_keys] + ['help']
    shortopts = reduce(lambda i, j: i + j,
                       [f'{i[0]}:' for i in arg_keys]) + 'h'

    # Help message
    help_args = reduce(lambda i, j:
                       i + f'    --{j}=<"{arg_default[j]}">\n'
                       if isinstance(arg_default[j], str) else
                       i + f'    --{j}=<{arg_default[j]}>\n', arg_keys, '')
    helplines = f"""
{os.path.basename(__file__)}
{help_args}
    """
    try:
        opts, args = getopt.getopt(argvs, shortopts, longopts)
    except getopt.GetoptError:
        print(helplines)
        sys.exit(2)

    # assign values by keyword
    tuple_args = {i: (f'-{i[0]}', f'--{i}') for i in arg_keys}
    options = [opt for opt, argv in opts]
    if len(options) > 0:
        for opt, argv in opts:
            if opt in ('-h', '--help'):
                print(helplines)
                sys.exit()
            else:
                for i in arg_keys:
                    if opt in tuple_args[i]:
                        arg_default[i] = type(arg_default[i])(argv)

    # assign value by position
    if len(args) > 0:
        arg_keys = [i for i in arg_keys if
                    (f'-{i[0]}' not in options) | (f'--{i}' not in options)]
        for i in range(len(args)):
            arg_default[arg_keys[i]] = type(arg_default[arg_keys[i]])(args[i])

    if arg_default['outfile'] != None:
        arg_default['outfile'] = os.path.abspath(
            os.path.realpath(arg_default['outfile']))
    if arg_default['logfile'] != None:
        arg_default['logfile'] = os.path.abspath(
            os.path.realpath(arg_default['logfile']))
    arg_default['fname_excel'] = os.path.abspath(
        os.path.realpath(arg_default['fname_excel']))
    if os.path.islink(arg_default['fname_excel']):
        arg_default['fname_excel'] = os.readlink(arg_default['fname_excel'])

    for k in prog_args.keys():
        prog_args[k] = arg_default[f"{prog_args[k]}"]
        setattr(sys.modules[__name__], k, prog_args[k])

    return prog_args


if __name__ == '__main__':
    stime = time.time() 
    # main(**parse_args(sys.argv[1:]))
    test_main(**parse_args(sys.argv[1:]))
    print(r'Elasped time: %.2f sec' % (time.time()-stime))
