function Spam=restart_missing
d_out = '.\Output';
m = matfile(fullfile(d_out,'run_specs.mat'));
% n_Reals = m.n_Reals;
n_Seeds = m.n_Seeds;
month_offset = m.month_offset;
n_func_evals = m.n_func_evals;
n_objs = m.n_objs;
n_dvars = m.n_dvars;
n_constrs = m.n_constrs;
seqid = m.seqid;
options = m.options;
servers = m.servers;
d_set = m.d_set;
epsilon_list = m.epsilon_list;
f_runtime = m.f_runtime;
iter_subset = m.iter_subset;
lbound = m.lbound;
ubound = m.ubound;

server = getenv('computername');
iter_subset = iter_subset{strcmpi(server,servers)};
f_temp = strrep(f_runtime,'runtime.mat',[server '.mat']);

% determine the missing runs
load(f_temp,'Spam');
k_missing = cellfun(@(y) isempty(y),{Spam.grpid}');

parpool('local',20);
parfor k=1:length(iter_subset)
    if ~k_missing(k), continue; end
    j = iter_subset(k);
    i_real = floor(double(j-1)/n_Seeds)+1;
    i_seed = mod(j-1,n_Seeds)+1;
    opts = [options,{'rngstate',double(i_seed*10)}];
    Spam(k,1) = sub_dce(k,i_real,d_set,month_offset,seqid(i_real),i_seed,...
        n_dvars,n_objs,n_constrs,n_func_evals,epsilon_list,lbound,ubound,opts);
end
delete(gcp);
end

%% function sub_dce
function Spam=sub_dce(k,j,d_set,month_offset,seqid,i_seed,...
    n_dvars,n_objs,n_constrs,n_func_evals,epsilon_list,lbound,ubound,options)
% output folder
d_seed = fullfile(d_set,sprintf('seed%02d',i_seed));
if exist(d_seed,"dir")~=7, mkdir(d_seed); end

if exist('com.ampl.AMPL',"class") ~= 8, setUp; end
pam = update_pamdata(Monthly_PAM(month_offset),seqid);

% % reset ramdom seed
% rng(i_seed); rng

% Instantiate borg class, then set bounds, epsilon values, and file output locations
[vars,objs,runtime] = borg(n_dvars, n_objs, n_constrs, @pam.solve, n_func_evals,...
     epsilon_list, lbound, ubound, options);

if ~isempty(vars)
    % Create/write objective values and decision variable values to files in folder "sets", 1 folder per seed.
    fn = fullfile(d_seed, sprintf('vars_%02d.csv',j));
    writetable(array2table(vars,'VariableNames',[ ...
        arrayfun(@(y) sprintf('CWUP%02d',y),1:24,'UniformOutput',false),...
        arrayfun(@(y) sprintf('SCH%02d',y),1:24,'UniformOutput',false) ...
        ]),fn);

    fn = fullfile(d_seed, sprintf('objs_%02d.csv',j));
    writetable(array2table(objs,'VariableNames',...
        {'Budget_diff','GW_prod_over','GW_prod_under','Prodcost_avg'}),fn);
    fn = fullfile(d_seed, sprintf('runtime_%02d.csv',j));
    writetable(array2table(runtime.values','VariableNames',runtime.fields'),fn);

    fprintf('Seed %d Realization %d complete.\n',i_seed,j);
    fn = fullfile(d_seed, sprintf('Spam_%02d.mat',j));
    Spam = struct('vars',vars,'objs',objs,'runtime',runtime,'grpid',[j,i_seed]);
    save(fn,'Spam');
    
    f_temp = fullfile(fileparts(d_set),sprintf('%s.mat',getenv('computername')));
    m = matfile(f_temp,'Writable',true);
    m.Spam(k,1) = Spam;
end
pam.ampl.close();
clear('pam');
end

%% function update_pamdata
function pam=update_pamdata(pam,seqid)
% Update demand and water availability by realization
sv = '(localdb)\v11.0;';
dv = 'SQL Server Native Client 11.0;';
db = 'master';
atdb_name = 'prodalloc';
atdb = 'F:\ProdAllocation\prodalloc.mdf';
% local database can be very busy if a number of realizations are required
conn = database(['Driver=' dv 'Server=' sv 'Database=' db ';Trusted_Connection=Yes;Timeout=300']);
while ~isempty(conn.Message)
    disp(conn.Message);
    conn = database(['Driver=' dv 'Server=' sv 'Database=' db ';Trusted_Connection=Yes;Timeout=300']);
end
exec(conn,[...
    'if (not exists(select name from sysdatabases where name=''' atdb_name ''')) ',...
    'exec sp_attach_db ' atdb_name ',''' atdb '''']);
% set realization data: LHS for Demand & Availabilities (at TBC and Alafia River)
demands = fetch(conn,[...
    'select format(MonthYear,''yyyy-MMM'') monyr',...
    '    ,COT,NPR,NWH,PAS,PIN,SCH,STP from (',...
    'select * from ' atdb_name '.dbo.Demand dem ',...
    'inner join ' atdb_name '.dbo.LHS_map lhs on dem.RealizationID=lhs.Demand_RID ',...
    '    and SequenceID=',sprintf('%d',seqid),...
    ') D pivot (',...
    'max(Demand) for WPDA IN (COT,NPR,NWH,PAS,PIN,SCH,STP)) B ',...
    'order by MonthYear']);
df = DataFrame(2,'wpda','monyr','demand');
df.setMatrix(table2array(demands(:,2:end))',...
    {'COT','NPR','NWH','PAS','PIN','SCH','STP'},demands.monyr);
pam.ampl.setData(df);

flows = fetch(conn,[...
    'select timesteps,TBC,Alafia from(',...
    'select replace(Source,''_avail'','''') nongw',...
    '    ,row_number() over (partition by Source order by MonthYear) timesteps,Value ',...
    'from ' atdb_name '.dbo.SW_Availability swa ',...
    'inner join ' atdb_name '.dbo.LHS_map lhs on swa.RealizationID=lhs.Demand_RID ',...
    '    and SequenceID=',sprintf('%d',seqid),...
    ') D pivot (',...
    'max(Value) for nongw IN (TBC,Alafia)) B ',...
    'order by timesteps']);
df = DataFrame(2,'nongw','monyr','ngw_avail');
df.setMatrix(table2array(flows(:,2:end))',...
    {'TBC','Alafia'},flows.timesteps);
pam.ampl.setData(df);
exec(conn,['exec sp_detach_db ' db]);
close(conn)
end



