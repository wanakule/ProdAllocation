classdef merge_Spam
% Spam = merge_SpamXid(1:2:10,4:5);
% Spam = merge_Spam1('KUHNTUCKER4');
    properties
        f_run_specs
    end
    
    methods
        function obj=merge_Spam(fname)
            obj.f_run_specs = fname;
        end

        %% merge all Spam output
        function Spam=by_all(o)
        m = matfile(o.f_run_specs);
        n_Seeds = m.n_Seeds;
        n_iteration = m.n_iteration;
        d_out = m.d_out;
        d_set = m.d_set;
        
        Spam = struct('vars',cell(n_iteration,1),'objs',cell(n_iteration,1),...
            'runtime',cell(n_iteration,1),'grpid',cell(n_iteration,1));

        for j=1:n_iteration
            i_real = floor(double(j-1)/n_Seeds)+1;
            i_seed = mod(j-1,n_Seeds)+1;
            d_seed = fullfile(d_set,sprintf('seed%02d',i_seed));
            fn = fullfile(d_seed, sprintf('Spam_%02d.mat',i_real));
            if exist(fn,'file')~=2, continue; end
            m = matfile(fn);
            Spam(j,1) = m.Spam;    
        end

        f_temp = fullfile(d_out,'Spam.mat');
        save(f_temp,'Spam','-v7.3');
        end

        %% merge Spam by Seed
        function Spam=by_id(o,reals,seeds,use_csv)
        if nargin<2, reals = 1:1; end
        if nargin<3, seeds = 1:1; end
        if nargin<4, use_csv = false; end

        m = matfile(o.f_run_specs);
        n_Seeds = m.n_Seeds;
        n_Reals = m.n_Reals;
        d_set = m.d_set;
        
        temp = iif(length(n_Reals)>1,n_Reals,1:n_Reals);
        i_temp = ~ismember(reals,temp);
        if any(i_temp)
            fprintf('RealizationID: [%s] are not found in the soultion set!\n',num2str(reals(i_temp)));
        end
        temp = 1:n_Seeds;
        i_temp = ~ismember(seeds,temp);
        if any(i_temp)
            fprintf('SeedID: [%s] are not found in the soultion set!\n',num2str(seeds(i_temp)));
        end

        % initialize Spam structure
        n_iteration = n_Reals*n_Seeds;
        Spam = struct('vars',cell(n_iteration,1),'objs',cell(n_iteration,1),...
            'runtime',cell(n_iteration,1),'grpid',cell(n_iteration,1));

        for j=1:n_iteration
            i_real = floor(double(j-1)/n_Seeds)+1;
            i_seed = mod(j-1,n_Seeds)+1;
            if ~ismember(i_real,reals) || ~ismember(i_seed,seeds), continue; end
            d_seed = fullfile(d_set,sprintf('seed%02d',i_seed));

            % user csv
            if use_csv
                Spam(j,1).grpid = [i_real,i_seed,j];

                fn = fullfile(d_seed, sprintf('objs_%02d.csv',i_real));
                if exist(fn,'file')~=2, continue; end
                Spam(k,1).objs = table2array(readtable(fn));

                fn = fullfile(d_seed, sprintf('vars_%02d.csv',i_real));
                Spam(k,1).vars = table2array(readtable(fn));

                fn = fullfile(d_seed, sprintf('runtime_%02d.csv',i_real));
                runtime = readtable(fn);
                Spam(j,1).runtime = struct('fields',runtime.Properties.VariableNames',...
                    'values',table2array(runtime)');
            else
                fn = fullfile(d_seed, sprintf('Spam_%02d.mat',i_real));
                if exist(fn,'file')~=2, continue; end
                m = matfile(fn);
                Spam(j,1) = m.Spam;
            end
            Spam = Spam(cellfun(@(y) ~isempty(y),{Spam.objs}),1);
        end
        end

        %% merge Spam by server
        function Spam=by_server(o,server,use_csv)
        if nargin<2, server = 'KUHNTUCKER5'; end
        if nargin<3, use_csv = false; end
        
        m = matfile(o.f_run_specs);
        n_Seeds = m.n_Seeds;
        iter_subset = m.iter_subset;
        d_out = m.d_out;
        d_set = m.d_set;
        servers = m.servers;
        
        % get subset for the specified server
        iter_subset = iter_subset{strcmpi(server,servers)};

        n_itersub = length(iter_subset);
        Spam = struct('vars',cell(n_itersub,1),'objs',cell(n_itersub,1),...
            'runtime',cell(n_itersub,1),'grpid',cell(n_itersub,1));

        for k=1:length(iter_subset)
            j = iter_subset(k);
            i_real = floor(double(j-1)/n_Seeds)+1;
            i_seed = mod(j-1,n_Seeds)+1;
            d_seed = fullfile(d_set,sprintf('seed%02d',i_seed));

            % user csv
            if use_csv
                Spam(k,1).grpid = [i_real,i_seed,j];

                fn = fullfile(d_seed, sprintf('objs_%02d.csv',i_real));
                if exist(fn,'file')~=2, continue; end
                Spam(k,1).objs = table2array(readtable(fn));

                fn = fullfile(d_seed, sprintf('vars_%02d.csv',i_real));
                Spam(k,1).vars = table2array(readtable(fn));

                fn = fullfile(d_seed, sprintf('runtime_%02d.csv',i_real));
                runtime = readtable(fn);
                Spam(k,1).runtime = struct('fields',runtime.Properties.VariableNames',...
                    'values',table2array(runtime)');
            else
                fn = fullfile(d_seed, sprintf('Spam_%02d.mat',i_real));
                if exist(fn,'file')~=2, continue; end
                m = matfile(fn);
                Spam(k,1) = m.Spam;
            end
        end

        f_temp = fullfile(d_out,[server '.mat']);
        save(f_temp,'Spam','-v7.3');
        end
        
        %% get run_specs
        function run_specs(o,n_Reals,n_Seeds,month_offset,nfe,freq,use_partool,seqid,sid_avail)

        if nargin-1<1 || isempty(n_Reals), n_Reals = 100; end
        if nargin-1<2 || isempty(n_Seeds), n_Seeds = 1; end
        if nargin-1<3 || isempty(month_offset), month_offset = 0; end
        if nargin-1<4 || isempty(nfe), nfe = 5000; end
        if nargin-1<5 || isempty(freq), freq = 250; end
        if nargin-1<6 || isempty(use_partool), use_partool = true; end
        if nargin-1<7, seqid = []; end
        if nargin-1<8 || isempty(sid_avail), sid_avail = 2:7; end
%         % specifications
%         n_Reals = 100;
%         n_Seeds = 5;
%         month_offset = 0;
%         nfe = 5000;
%         freq = 250;
%         use_partool = true;
%         seqid = [];
%         sid_avail = 2:7;

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
        options = {'frequency',freq};
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

        % use MATLAB parallel toolbox
        % Determine subset of realizations to run on available servers
        n_iteration = int32(n_Reals*n_Seeds);
        n_server = length(servers);

        % Setup iteration subset by server
        iter_subset = arrayfun(@(y) y:n_server:n_iteration,1:n_server,'UniformOutput',false);

        % save run specs
        save (o.f_run_specs,'-v7.3',...
            'n_Reals','n_Seeds','month_offset','nfe','freq','use_partool','seqid','sid_avail',...
            'n_dvars','n_objs','n_constrs','epsilon_list','lbound','ubound','options',...
            'd_cur','d_out','d_set','f_runtime','iter_subset','n_iteration','servers');
        end
    
    end
end
