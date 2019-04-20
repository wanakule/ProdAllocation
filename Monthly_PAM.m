classdef Monthly_PAM
	properties
        MO_OFFSET
        ampl
    end
	methods
        function obj=Monthly_PAM(cur_month)
            % =======================================
            % instantiate AMPL class and set AMPL options
            obj.MO_OFFSET = cur_month;  % count by water year, October = 1
            obj.ampl = AMPL;

            % set options
            obj.ampl.setIntOption('solver_msg', 0);
            obj.ampl.setBoolOption('presolve', false);
            obj.ampl.setOption('solver', 'gurobi_ampl');
%             obj.ampl.setOption('solver', 'cbc');
%             obj.ampl.setOption('gurobi_options',...
%                            'iisfind=1 iismethod=1 lpmethod=4 mipgap=1e-6 warmstart=1');
            obj.ampl.setBoolOption('solver_msg', false);

            % =======================================
            % read AMPL model and data files
            f_model = fullfile(pwd, 'model.amp');
            f_data = fullfile(pwd, 'data.amp');
            obj.ampl.read(f_model);
            obj.ampl.read(f_data);

            % =======================================
            % fix BUD and Desal
            timesteps = cell2mat(obj.ampl.getSet('timesteps').getValues().getColumn('timesteps'));
            ds_prod = obj.ampl.getVariable('ds_prod');
            ds_fix = obj.ampl.getParameter('ds_fix');
            for i=timesteps'
                temp = ds_prod.get(i);
                temp.fix(ds_fix(i));
            end

            gw_prod = obj.ampl.getVariable('gw_prod');
            bud_fix = obj.ampl.getParameter('bud_fix');
            for i=timesteps'
                temp = gw_prod.get('BUD',i);
                temp.fix(bud_fix(i))
            end
            res_vol = obj.ampl.getVariable('res_vol');
            temp = res_vol.get(0);
            temp.fix(cell2mat(obj.ampl.getParameter('res_init').getValues().getColumn('res_init')));
        end
    end
        
    methods
        function [borg_obj] = solve(obj,borg_vars)
            % debug
            % fprintf(repmat([repmat('%7.2f',1,12) '\n'],1,4),borg_vars);

            % =======================================
            % set borg variables to fix
            temp = obj.ampl.getSet('timesteps');
            timesteps = cell2mat(temp.getValues().getColumn('timesteps'));
            gw_prod = obj.ampl.getVariable('gw_prod');

            j = 1;
            for i=timesteps'
                temp = gw_prod.get('CWUP', i);
                temp.fix(borg_vars(j));
                j = j+1;
            end

            for i=timesteps'
                temp = gw_prod.get('SCH', i);
                temp.fix(borg_vars(j));
                j = j+1;
            end

            %{
            to_swtp = obj.ampl.getVariable('to_swtp')
            for i=timesteps'
                to_swtp[i].fix(borg_vars[j])
                j += 1
            end

            to_res = obj.ampl.getVariable('to_res')
            for i=timesteps'
                to_res[i].fix(borg_vars[j])
                j += 1
            end

            res_eff = obj.ampl.getVariable('res_eff')
            for i=timesteps'
                res_eff[i].fix(borg_vars[j])
                j += 1
            end
            %}

            % run simulation
%             obj.ampl.solve();
            obj.ampl.eval('solve >null;');

            % check infeasibility
            if (strcmp(obj.ampl.getObjective('mip_obj').result(),'infeasible'))
                obj.ampl.setBoolOption('solver_msg', true);
                obj.ampl.setOption('solver', 'gurobi_ampl');
                obj.ampl.setOption('gurobi_options',...
                    'iisfind=1 iismethod=1 lpmethod=4 mipgap=1e-6 warmstart=1');
                obj.ampl.solve();
                obj.ampl.eval('commands infeas_gurobi.amp;')

                % Return objective values
                obj.ampl.display('gw_prod')
                % obj.ampl.display('gw_prod_under')
                % obj.ampl.display('gw_prod_over')

                % obj.ampl.display('prodcost_avg')
                % obj.ampl.display('gw_prod_under')
                % obj.ampl.display('gw_prod_over')
                exit;
            end

            % evaluate borg objective functions
            obj.ampl.eval(...
                "let borg_obj['prodcost_avg'] := 1e-3*sum {j in (gw_sources union nongw union {'Reservoir'})} prodcost_avg[j,1];");
            obj.ampl.eval(...
                "let borg_obj['budget_diff'] := sum {j in budget_set} total_budget_diff[j];");
            obj.ampl.eval(...
                "let borg_obj['gw_prod_under'] := sum {j in gw_sources, k in timesteps} gw_prod_under[j,k];");
            obj.ampl.eval(...
                "let borg_obj['gw_prod_over'] := sum {j in gw_sources, k in timesteps} gw_prod_over[j,k];");
            borg_obj = cell2mat(obj.ampl.getParameter('borg_obj').getValues().getColumn('borg_obj'));

%             obj.ampl.display('borg_obj');
        end
	end
end


