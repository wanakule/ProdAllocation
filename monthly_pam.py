import sys
import os
import math
import time
import pandas as pd
from contextlib import contextmanager
from amplpy import AMPL, DataFrame


class prodalloc:
    MO_OFFSET = 0
    ampl = []

    def __init__(self, cur_month):
        # =======================================
        # instantiate AMPL class and set AMPL options
        MO_OFFSET = cur_month  # count by water year, October = 1
        ampl = AMPL()

        # set options
        ampl.setOption('presolve', False)
        ampl.setOption('solver', 'gurobi_ampl')
        # ampl.setOption('solver', 'cbc')
        ampl.setOption('gurobi_options',
                       'iisfind=1 iismethod=1 lpmethod=4 mipgap=1e-6 warmstart=1')
        # ampl.setOption('reset_initial_guesses', True)
        ampl.setOption('solver_msg', True)

        # =======================================
        # read AMPL model and data files
        d_cur = os.getcwd()
        f_model = os.path.join(d_cur, 'model.amp')
        f_data = os.path.join(d_cur, 'data.amp')
        ampl.read(f_model)
        ampl.read(f_data)

        # =======================================
        # fix BUD and Desal
        timesteps = ampl.getSet('timesteps').getValues().toList()
        ds_prod = ampl.getVariable('ds_prod')
        ds_fix = ampl.getParameter('ds_fix')
        for i in timesteps:
            ds_prod[i].fix(ds_fix[i])

        gw_prod = ampl.getVariable('gw_prod')
        bud_fix = ampl.getParameter('bud_fix')
        for i in timesteps:
            gw_prod['BUD', i].fix(bud_fix[i])
        res_vol = ampl.getVariable('res_vol')
        res_vol[0].fix(ampl.getParameter('res_init').getValues().toList()[0])

        self.ampl = ampl

    def solve(self, *borg_vars):
        # debug
        print(('%7.2f' * 12 + f'\n')*4 % borg_vars)

        # =======================================
        # set borg variables to fix
        ampl = self.ampl
        timesteps = ampl.getSet('timesteps').getValues().toList()
        gw_prod = ampl.getVariable('gw_prod')

        j = 0
        for i in timesteps:
            gw_prod['CWUP', i].fix(borg_vars[j])
            j += 1

        for i in timesteps:
            gw_prod['SCH', i].fix(borg_vars[j])
            j += 1

        '''
        to_swtp = ampl.getVariable('to_swtp')
        for i in range(len(to_swtp)):
            to_swtp[i].fix(borg_vars[j])
            j += 1

        to_res = ampl.getVariable('to_res')
        for i in range(len(to_res)):
            to_res[i].fix(borg_vars[j])
            j += 1

        res_eff = ampl.getVariable('res_eff')
        for i in range(len(res_eff)):
            res_eff[i].fix(borg_vars[j])
            j += 1
        '''

        # run simulation
        with open('nul', 'w') as f:
            with stdout_redirected(f):
                ampl.solve()
        # ampl.solve()

        # check infeasibility
        if (ampl.getObjective('mip_obj').result() == 'infeasible'):
            ampl.eval('commands infeas_gurobi.amp;')

            # Return objective values
            ampl.display('gw_prod')
            # ampl.display('gw_prod_under')
            # ampl.display('gw_prod_over')

            # ampl.display('prodcost_avg')
            # ampl.display('gw_prod_under')
            # ampl.display('gw_prod_over')

        # evaluate borg objective functions
        ampl.eval(
            "let borg_obj['prodcost_avg'] := 1e-3*sum {j in (gw_sources union nongw union {'Reservoir'})} prodcost_avg[j,1];")
        ampl.eval(
            "let borg_obj['budget_diff'] := sum {j in budget_set} total_budget_diff[j];")
        ampl.eval(
            "let borg_obj['gw_prod_under'] := sum {j in gw_sources, k in timesteps} gw_prod_under[j,k];")
        ampl.eval(
            "let borg_obj['gw_prod_over'] := sum {j in gw_sources, k in timesteps} gw_prod_over[j,k];")
        borg_obj = ampl.getParameter('borg_obj').getValues().toDict()

        print(pd.DataFrame.from_dict(borg_obj, orient='index'))
        return [borg_obj['budget_diff'], borg_obj['gw_prod_over'], borg_obj['gw_prod_under'], borg_obj['prodcost_avg']]


@contextmanager
def stdout_redirected(new_stdout):
    save_stdout = sys.stdout
    sys.stdout = new_stdout
    try:
        yield None
    finally:
        sys.stdout = save_stdout
