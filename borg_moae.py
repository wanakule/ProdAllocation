import os
import borg as bg
import monthly_pam


def main():
    pam = monthly_pam.prodalloc(0)

    n_Seeds = 25  # Number of random seeds (Borg MOEA)
    n_dvars = 48  # Number of decision variables
    n_objs = 4	  # Number of objectives
    n_constrs = 0  # Number of constraints
    # Number of total simulations to run per random seed. Each simulation may be a monte carlo.
    n_func_evals = 1500
    runtime_freq = 50  # Interval at which to print runtime details for each random seed
    dvar_range = {
        'CWUP': [[0, 120]] * 24,
        'SCH': [[0, 30]] * 24
    }
    # Borg epsilon values for each objective
    epsilon_list = [10000, 10, 0.01, 0.01]

    # fix variable bounds upto current month
    budget_target = pam.ampl.getParameter('budget_target')
    bud_fix = pam.ampl.getParameter('bud_fix')
    if pam.MO_OFFSET > 0:
        for i in range(pam.MO_OFFSET):
            temp = budget_target['CWUP', i+1]
            dvar_range['CWUP'][i] = [temp, temp]
            temp = budget_target['BUDSCH', i+1] - bud_fix[i+1]
            dvar_range['SCH'][i] = [temp, temp]
    dvar_range = dvar_range['CWUP'] + dvar_range['SCH']

    '''
    Short run test
    '''
    borg = bg.Borg(n_dvars, n_objs, n_constrs, pam.solve,
                   bounds=dvar_range,
                   epsilons=epsilon_list)

    for solution in borg.solve({'maxEvaluations': 100}):
        solution.display()

    pam.ampl.close()
    '''
    End short run test
    '''

    # Where to save seed and runtime files
    # Specify location of output files for different seeds
    d_out = os.path.join(os.getcwd(), 'Output')
    d_set = os.path.join(d_out, 'sets')

    # Loop through seeds, calling borg.solve (serial) or borg.solveMPI (parallel) each time
    for j in range(n_Seeds):
        # Instantiate borg class, then set bounds, epsilon values, and file output locations
        borg = bg.Borg(n_dvars, n_objs, n_constrs, pam.solve)
        borg.setBounds(*dvar_range)  # Set decision variable bounds
        borg.setEpsilons(*epsilon_list)  # Set epsilon values
        # Runtime file path for each seed:
        f_runtime = os.path.join(d_out, f'seed_{j:04d}.runtime')

        # Run serial Borg
        result = borg.solve({
            "maxEvaluations": n_func_evals,
            "runtimeformat": 'borg',
            "frequency": runtime_freq,
            "runtimefile": f_runtime
        })

        if result:
            # This particular seed is now finished being run in parallel. The result will only be returned from
            # one node in case running Master-Slave Borg.
            result.display()

            # Create/write objective values and decision variable values to files in folder "sets", 1 file per seed.
            f = open(os.path.join(d_set, f'prodalloc_{j:02d}.set'), 'w')
            f.write('#Borg Optimization Results\n')
            f.write(
                f'#First {n_dvars} are the decision variables, last {n_objs} are the objective values\n')
            for solution in result:
                line = ''
                for i in range(len(solution.getVariables())):
                    line = line + (str(solution.getVariables()[i])) + ' '

                for i in range(len(solution.getObjectives())):
                    line = line + (str(solution.getObjectives()[i])) + ' '

                f.write(line[0:-1]+'\n')
            f.write("#")
            f.close()

            # Create/write only objective values to files in folder "sets", 1 file per seed. Purpose is so that
            # the file can be processed in MOEAFramework, where performance metrics may be evaluated across seeds.
            f = open(os.path.join(
                d_set, f'prodalloc_no_vars {j+1:04d}.set'), 'w')
            for solution in result:
                line = ''
                for i in range(len(solution.getObjectives())):
                    line += (str(solution.getObjectives()[i])) + ' '

                f.write(line[0:-1]+'\n')
            f.write("#")
            f.close()

            print(f"Seed {j} complete.")

    pam.ampl.close()


if __name__ == '__main__':
    main()
