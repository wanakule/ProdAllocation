function [vars,pctiles,tuples]=lhs(nsample,n_trial,do_eda)

if nargin<2, n_trial = 100; end
if nargin<3, do_eda = false; end

% get demand total by realization
sv = '(localdb)\v11.0;';
dv = 'SQL Server Native Client 11.0;';
% db = 'master;';
db = 'prodalloc';
atdb = 'F:\ProdAllocation\prodalloc.mdf;';
conn = database(['Driver=' dv 'Server=' sv 'AttachDbFilename=' atdb 'Database=' db ...
    ';Trusted_Connection=Yes;']);
% temp = fetch(conn,'SELECT name,filename FROM sysdatabases');
temp = fetch(conn,[...
    'select RealizationID,MonthYear,(COT+NPR+NWH+PAS+PIN+SCH+STP) TotalDemand from (',...
	'select * from Demand where RealizationID>0',...
    ') D pivot (',...
	'max(Demand) for WPDA IN (COT,NPR,NWH,PAS,PIN,SCH,STP)) B ',...
    'order by RealizationID,MonthYear']);

%% plot for EDA
if do_eda
    boxplot(temp.TotalDemand,temp.RealizationID,'PlotStyle','compact');
    grid on;
    set(gca,'Position',[0.010 0.191 0.985 0.734]);
    % set(gcf,'Position',[4 678 3834 420]);

    % variabtion in realizations
    temp_pivot = reshape(temp.TotalDemand,24,1000);
    ens_avgP50 = mean(prctile(temp_pivot,50))
    ens_stdP50 = std(prctile(temp_pivot,50))
    ens_avgP25 = mean(prctile(temp_pivot,25))
    ens_avgP75 = mean(prctile(temp_pivot,75))
    ens_avgIQR = mean(prctile(temp_pivot,75)-prctile(temp_pivot,25))
    ens_stdIQR = std(prctile(temp_pivot,75)-prctile(temp_pivot,25))
    ens_stdP75 = std(prctile(temp_pivot,75))
    ens_stdP90 = std(prctile(temp_pivot,90))
    ens_stdavg = std(mean(temp_pivot))
    ens_stdstd = std(std(temp_pivot))
    % p75 = arrayfun(@(y) prctile(temp.TotalDemand(temp.RealizationID==y),75),1:1000);
    % p90 = arrayfun(@(y) prctile(temp.TotalDemand(temp.RealizationID==y),90),1:1000);
    hold on;
    plot([1 1000 NaN 1 1000]',...
        [ens_avgP50-ens_stdP50 ens_avgP50-ens_stdP50 NaN ...
        ens_avgP50+ens_stdP50 ens_avgP50+ens_stdP50]','-g');
    plot([1 1000 NaN 1 1000]',...
        [ens_avgP25 ens_avgP25 NaN ens_avgP75 ens_avgP75]','-r');
    hold off;
end

demands = fetch(conn,[...
    'select RealizationID,avg(COT+NPR+NWH+PAS+PIN+SCH+STP) AvgDemand,',...
    '  Stdev(COT+NPR+NWH+PAS+PIN+SCH+STP) StdDemand from (',...
	'select * from Demand where RealizationID>0',...
    ') D pivot (',...
	'max(Demand) for WPDA IN (COT,NPR,NWH,PAS,PIN,SCH,STP)) B ',...
    'group by RealizationID ',...
    'order by RealizationID']);
flows = fetch(conn,[...
   'select RealizationID,TBC_flow ',...
   'from FlowRealizationAvg ',...
   'order by RealizationID']);
exec(conn,['exec sp_detach_db ' db]);
close(conn);

vars = [demands.AvgDemand flows.TBC_flow];
if nargin<1, nsample = round(length(vars)*0.334); end
[pctiles,tuples] = sampling(vars,nsample,n_trial);
if do_eda
    fprintf('Mean and Stdev of Demand Realization Average = (%.3f,%.3f)\n',...
        [mean(demands.AvgDemand),std(demands.AvgDemand)]);
    fprintf('Mean and Stdev of TBC Flow Realization Average = (%.3f,%.3f)\n',...
        [mean(flows.TBC_flow),std(flows.TBC_flow)]);
    [~,a] = create2x1Axes('Compare Population and Sample Histograms');
    subplot(a(1));
    histogram(demands.AvgDemand,25,'Normalization','cdf');
    temp = [demands.AvgDemand(tuples(:,1)),pctiles(tuples(:,1),1)/100.];
    [~,idx] = sort(temp(:,2));
    hold on
    plot(temp(idx,1),temp(idx,2),'-or');
    hold off;
    grid on;
    xlabel('Demand, mgd');
    title('Demand Random Variable');
    
    subplot(a(2));
    histogram(flows.TBC_flow,25,'Normalization','cdf');
    temp = [flows.TBC_flow(tuples(:,2)),pctiles(tuples(:,2),2)/100.];
    [~,idx] = sort(temp(:,2));
    hold on
    plot(temp(idx,1),temp(idx,2),'-or');
    hold off;
    grid on;
    xlabel('Flow, cfs');
    title('TBC Flow Random Variable');
end

function [pctiles,sample_tuple]=sampling(vars,nsample,n_trial)
% vars is the random variable matrix of size (nreals,nvars)
% if number of realizations for each variable are not the same, fill the
% rest of vars rows with NaN

pctiles = NaN(size(vars));
[~,ind] = sort(vars);
i_temp = ~isnan(vars);
nreals = sum(i_temp);
nvars = length(nreals);
% compute percentile
for i=1:nvars
    pctiles(ind(i_temp(:,i),i),i) = (((1:nreals(i))-1)/nreals(i)+1/nreals(i)/2)*100;
end

% trial n_trial sampling design
rid = NaN(nsample,nvars,n_trial);
dup = cell(nvars,n_trial);
for j=1:n_trial
    lhs_prob = lhsdesign(nsample,nvars);

    % pick RealizationID with the closest percentile to the lhsdesign prob
    for i=1:nvars
        rid(:,i,j) = interp1(pctiles(i_temp(:,i),i),(1:nreals(i))',...
            lhs_prob(:,i)*100.,'nearest','extrap');
        dup{i,j} = find(rid(:,i,j)==circshift(rid(:,i,j),-1))+1;
    end
end

% find jth trial with min number of duplications
n_dup = arrayfun(@(x) sum(cellfun(@(y) length(y),dup(:,x))),1:n_trial);
j = find(n_dup==min(n_dup),1);
fprintf('Minimun sum number of duplications = %d\n',n_dup(j));

% % Try to reduce ndups
% if min_ndups>0
%     i_dup = squeeze(i_dup(:,j(1)));
%     for i=1:nvars
%         i_rid(i_dup{i},i) = i_rid(i_dup{i},i)+1;
%         i_dup{i} = find(i_rid(:,i)==circshift(i_rid(:,i),-1))+1;
%     end
%     ndups = sum(arrayfun(@(x) length(i_dup{x}),1:nvars));
%     fprintf('Reduced number of duplications to = %d\n',ndups);
% end
sample_tuple = rid(:,:,j);

