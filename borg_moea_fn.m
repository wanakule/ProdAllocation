function Spam=borg_moea_fn(n_Reals,n_Seeds,month_offset,n_func_evals,runtime_freq,use_partool,seqid,sid_avail)
%% Function borg_moea_fn
% Main function to run Borg/MOEA for Production Allocation Model (PAM), 
% which is written in AMPL and being solved by GUROBI.
% 
% n_Reals: Number of monte carlo realization
% n_Seeds: Number of random seeds (Borg MOEA)
% month_offset: the number of month offset from the beginning of water year
% n_func_evals: number of function evaluation per borg call
% runtime_freq: interval at which to print runtime details

% use_partool: flag to to parallet toolbox, set to false for debuging
% seqid: list of realization tuple indeces of realization data

if nargin<1 || isempty(n_Reals), n_Reals = 100; end
if nargin<2 || isempty(n_Seeds), n_Seeds = 1; end
if nargin<3 || isempty(month_offset), month_offset = 0; end
if nargin<4 || isempty(n_func_evals), n_func_evals = 5000; end
if nargin<5 || isempty(runtime_freq), runtime_freq = 250; end
if nargin<6 || isempty(use_partool), use_partool = true; end
if nargin<7, seqid = []; end
if nargin<8 || isempty(sid_avail), sid_avail = 2:7; end

% Available servers in the cluster
servers = arrayfun(@(y) sprintf('KUHNTUCKER%d',y),sid_avail','UniformOutput',false);

% Create an instance of PAM and setup problem definition to run 'borg' function
% setup AMPL/MATLAB API
if exist('com.ampl.AMPL',"class") ~= 8, setUp; end

% Instantiate an instance of PAM
pam = Monthly_PAM(month_offset);

% Setup problem specs
n_dvars = 48;   % Number of decision variables (CWUP and SCH production over 24 months)
n_objs = 4;     % Number of objectives
n_constrs = 0;  % Number of constraints

% Variable bounds
dvar_range = struct(...
    'CWUP', repmat([0; 120],1,24),...
    'SCH', repmat([0; 30],1,24) ...
);
% Borg epsilon values for each objective
epsilon_list = [10., .01, 1.5, 2000.];

% fix variable bounds upto current month
budget_target = pam.ampl.getParameter('budget_target');
bud_fix = pam.ampl.getParameter('bud_fix');
if pam.MO_OFFSET > 0
    for i=1:pam.MO_OFFSET
        temp = budget_target('CWUP', i+1);
        dvar_range.CWUP(:,i) = [temp; temp];
        temp = budget_target('BUDSCH', i+1) - bud_fix(i+1);
        dvar_range.SCH(:,i) = [temp; temp];
    end
end
lbound = [dvar_range.CWUP(1,:),dvar_range.SCH(1,:)];
ubound = [dvar_range.CWUP(2,:),dvar_range.SCH(2,:)];

% borg options
options = {'frequency',runtime_freq};
pam.ampl.close();
clear('pam');

% Setup where to save seed/realization and runtime files
% Specify location of output files for different seeds/realizations
d_cur = 'F:\ProdAllocation';
% cur_drive = get_drive(d_cur);
d_out = fullfile(d_cur, 'Output');
d_set = fullfile(d_out, 'sets');
f_runtime = fullfile(d_out, 'runtime.mat');
if isempty(seqid), load(f_runtime,'seqid'); end

% Test if n_Reals is a list of seqid in the existing samples
if length(n_Reals)>1
    if isempty(seqid), load(f_runtime,'seqid'); end
    seqid = seqid(ismember(1:size(seqid,1),n_Reals));
    n_Reals = length(n_Reals);
else
    % localDB data connection specs
    sv = '(localdb)\v11.0;';
    dv = 'SQL Server Native Client 11.0;';
    db = 'master';
    atdb_name = 'prodalloc';
    atdb = 'F:\ProdAllocation\prodalloc.mdf';
    conn = database(['Driver=' dv 'Server=' sv 'Database=' db ';Integrated Security=true;']);
    exec(conn,[...
        'if (not exists(select name from sysdatabases where name=''' atdb_name ''')) ',...
        'exec sp_attach_db ' atdb_name ',''' atdb '''']);
    % temp = fetch(conn,'SELECT name,filename FROM sysdatabases');

    % Latin Hypercube Sampling
    if n_Reals>0 && (exist('seqid','var')~=1 || isempty(seqid) || length(seqid)~=n_Reals)
        % get LHS samples to be resampled
        % set realization data: LHS for Demand & Availabilities (at TBC and Alafia River)
        ls_samples = fetch(conn,...
            ['select Demand_RID,Flows_RID from ' atdb_name '.dbo.LHS_map order by SequenceID'],...
            'DataReturnFormat','numeric');
        seqid = resampling_lhs(ls_samples,n_Reals,true);
        save(f_runtime,'seqid')
    end
    close(conn);
end

if ~use_partool
    unittest(d_out,month_offset,seqid,...
        n_dvars,n_objs,n_constrs,epsilon_list,lbound,ubound);
    return;
end

% use MATLAB parallel toolbox
% Determine subset of realizations to run on available servers
n_iteration = int32(n_Reals*n_Seeds);
server = getenv('computername');
n_server = length(servers);
f_temp = strrep(f_runtime,'runtime.mat',[server '.mat']);

% Setup iteration subset by server
iter_subset = arrayfun(@(y) y:n_server:n_iteration,1:n_server,'UniformOutput',false);
iter_subset = iter_subset{strcmpi(server,servers)};

% Loop through seeds/realizations, calling borg.solve (serial) each time
tic;
% using pararell toolbox
n_itersub = length(iter_subset);
Spam = struct('vars',cell(n_itersub,1),'objs',cell(n_itersub,1),...
    'runtime',cell(n_itersub,1),'grpid',cell(n_itersub,1));
save(f_temp,'Spam','-v7.3');

parpool('local',20);
parfor k=1:length(iter_subset)
    j = iter_subset(k);
    i_real = floor(double(j-1)/n_Seeds)+1;
    i_seed = mod(j-1,n_Seeds)+1;
    opts = [options,{'rngstate',double(i_seed*10)}];
    Spam(k,1) = sub_dce(k,i_real,d_set,month_offset,seqid(i_real),i_seed,...
        n_dvars,n_objs,n_constrs,n_func_evals,epsilon_list,lbound,ubound,opts);
end
delete(gcp);
fprintf('Elapsed Time = %d sec\n',toc);

% if n_Reals>0
%     plot_pareto([1,5,10,15,20,25]);
% end
end

%% function sub_dce
% Use MATLAB distributed computing engine to run each realizations

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

%% Run unit test
function unittest(d_out,month_offset,seqid,...
    n_dvars,n_objs,n_constrs,epsilon_list,lbound,ubound)
% Short run test for debugging
tic;
[vars,objs] = sub_dce(1,d_out,month_offset,seqid(1),1,...
    n_dvars,n_objs,n_constrs,200,epsilon_list,lbound,ubound,{'frequency',100});
disp(objs);
disp(vars);
fprintf('Elapsed Time = %d sec\n',toc);
end
