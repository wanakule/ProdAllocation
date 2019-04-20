import sys
import pandas as pd


def main(AVAIL_PCTILE=25, RES_INIT=15.5, RID=0, f_excel=None):

    scenarios = [
        {'AVAIL_PCTILE': 25, 'RES_INIT': 15.5, 'RID': 0, 'f_excel': None},
        {'AVAIL_PCTILE': 50, 'RES_INIT': 8.0, 'RID': 1, 'f_excel': None},
        {'AVAIL_PCTILE': 75, 'RES_INIT': 4.0, 'RID': 2, 'f_excel': None}
    ]

    for i in range(len(scenarios)):
        for k in scenarios[i].keys():
            setattr(sys.modules[__name__], k, scenarios[i][k])
        build_scenario(**scenarios[i])
        #
        # build_scenario(
        #     scenarios[i]['AVAIL_PCTILE'],
        #     scenarios[i]['RES_INIT'],
        #     scenarios[i]['RID'],
        #     scenarios[i]['f_excel']
        # )


def build_scenario(AVAIL_PCTILE=25, RES_INIT=15.5, RID=0, f_excel=None):
    import pyodbc
    # import sqlalchemy

    if f_excel == None:
        f_excel = 'WY 2019 monthly delivery and supply for budget InitialDraft.xlsx'

    # =======================================
    # Read fixed allocation from spreadsheet
    # f_excel = os.path.join(
    #     d_cur, 'WY 2019 monthly delivery and supply for budget InitialDraft.xlsx')
    sheet_names = ['WY 2019', 'WY 2020',
                   'WY 2021', 'WY 2022', 'WY 2023', 'WY 2024']
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
    bud_fix, ds_fix, swtp_fix = [], [], []
    for i in range(len(sheet_names)):
        df_excel = pd.read_excel(
            f_excel, sheet_names[i], usecols='C:N', nrows=41)
        ch_poc    .extend(list(df_excel.loc[16 + row_offset, :].values))
        reg_lithia.extend(list(df_excel.loc[20 + row_offset, :].values))
        reg_cot   .extend(list(df_excel.loc[26 + row_offset, :].values))
        reg_thic  .extend(list(df_excel.loc[37 + row_offset, :].values))
        crw_prod  .extend(list(df_excel.loc[40 + row_offset, :].values))
        eag_prod.extend(list(df_excel.loc[41 + row_offset, :].values))

        bud_fix .extend(list(df_excel.loc[22 + row_offset, :].values))
        ds_fix  .extend(list(df_excel.loc[36 + row_offset, :].values))
        swtp_fix.extend(list(df_excel.loc[38 + row_offset, :].values))

    idx = [i for i in range(1, len(ch_poc)+1)]
    df = pd.DataFrame(
        [[AVAIL_PCTILE, 0, RID, 'AVAIL_PCTILE'], [RES_INIT, 0, RID, 'RES_INIT']]
    ).append(
        pd.DataFrame([ch_poc,     idx, [RID]*len(idx),
                      ['ch_poc']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([reg_lithia, idx, [RID]*len(idx),
                      ['reg_lithia']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([reg_cot,    idx, [RID]*len(idx),
                      ['reg_cot']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([reg_thic,   idx, [RID]*len(idx),
                      ['reg_thic']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([crw_prod,   idx, [RID]*len(idx),
                      ['crw_prod']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([eag_prod,   idx, [RID]*len(idx),
                      ['eag_prod']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([bud_fix,    idx, [RID]*len(idx),
                      ['bud_fix']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([ds_fix,     idx, [RID]*len(idx),
                      ['ds_fix']*len(idx)]).transpose()
    ).append(
        pd.DataFrame([swtp_fix,   idx, [RID]*len(idx),
                      ['swtp_fix']*len(idx)]).transpose()
    )
    df.columns = ['Value', 'MonthNo', 'ScenarioID', 'ParameterName']

    # Database connection
    dv = '{SQL Server}'
    # dv = '{SQL Server Native Client 11.0}'
    sv = 'vgridfs'
    db = 'ProdAlloc'
    conn = pyodbc.connect(
        f'DRIVER={dv};SERVER={sv};Database={db};Trusted_Connection=Yes')

    # connstr = 'mssql+pyodbc:///?odbc_connect='
    # connstr += f'DRIVER={dv};SERVER={sv};DATABASE={db};Trusted_Connection=Yes'
    # engine = sqlalchemy.create_engine(connstr)
    # df.to_sql('Scenario', engine, if_exists='replace', index=False)

    curs = conn.cursor()
    for index, row in df.iterrows():
        curs.execute("""
        INSERT INTO dbo.Scenario(ScenarioID,ParameterName,MonthNo,[Value])
            VALUES (?, ?, ?, ?)
        """,
                     row['ScenarioID'], row['ParameterName'], row['MonthNo'], row['Value'])
    conn.commit()
    curs.close()
    conn.close()


if __name__ == '__main__':
    main()
