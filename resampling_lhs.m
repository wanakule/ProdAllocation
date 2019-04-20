function [id_min,tuples]=resampling_lhs(tuples0,nsamples,noplot)
% [~,~,tuples0]=lhs(1000);
if nargin<1 || isempty(tuples0), [~,~,tuples0]=lhs(1000); end
if nargin<2, nsamples=334; end
if nargin<3, noplot = true; end

[vars,pctiles,tuples]=lhs(nsamples,1);
popu_pct = [pctiles(tuples0(:,1),1),pctiles(tuples0(:,2),2)];
samp_pct = [pctiles(tuples(:,1),1),pctiles(tuples(:,2),2)];
match_pct = NaN(size(samp_pct));
id_min = NaN(nsamples,1);
for i=1:length(samp_pct)
    dist = arrayfun(@(y) sqrt(sum((samp_pct(i,:)-popu_pct(y,:)).^2)),1:length(popu_pct));
    id_min(i) = find(dist==min(dist),1);
    % fprintf('Replace %d with %d(%d)\n',samp_id(i),popu_id(id_min),id_min);
    tuples(i,:) = tuples0(id_min(i),:);
    match_pct(i,:) = popu_pct(id_min(i),:);
end

if noplot, return; end
[~,a] = create2x1Axes('Compare Population and Sample Histograms');
subplot(a(1));
histogram(vars(:,1),25,'Normalization','cdf');
temp = [vars(tuples0(:,1),1),pctiles(tuples0(:,1),1)/100.];
[~,idx] = sort(temp(:,2));
hold on
plot(temp(idx,1),temp(idx,2),'-or');
plot(vars(tuples(:,1),1),pctiles(tuples(:,1),1)/100,'og','MarkerSize',3);
hold off;
grid on;
xlabel('Demand, mgd');
title('Demand Random Variable');

subplot(a(2));
histogram(vars(:,2),'Normalization','cdf');
temp = [vars(tuples0(:,2),2),pctiles(tuples0(:,2),2)/100.];
[~,idx] = sort(temp(:,2));
hold on
plot(temp(idx,1),temp(idx,2),'-or');
plot(vars(tuples(:,2),2),pctiles(tuples(:,2),2)/100,'og','MarkerSize',3);
hold off;
grid on;
xlabel('Flow, cfs');
title('TBC Flow Random Variable');

% resampling space
[~,a] = create2x1Axes('Compare Population and Sample Space');
a(1).Position = [0.07 0.5350 0.90 0.3850];
a(2).Position = [0.07 0.0750 0.90 0.3850];
subplot(a(1));
plot(popu_pct(:,1),popu_pct(:,2),'.');
hold on
plot(samp_pct(:,1),samp_pct(:,2),'sr','MarkerSize',3);
% find the closest points
plot(match_pct(:,1),match_pct(:,2),'og','MarkerSize',3);
hold off
xlabel('Demand Percentile');
ylabel('TBC Flow Percentile');
grid on;

% compare population and sample space
popsize = 20000;
v = lhsdesign(popsize,2)*100;
v(:,1) = interp1(pctiles(:,1),vars(:,1),v(:,1),'nearest','extrap');
v(:,2) = interp1(pctiles(:,2),vars(:,2),v(:,2),'nearest','extrap');
subplot(a(2));
plot(v(:,1),v(:,2),'.','MarkerSize',5);
hold on
plot(vars(tuples(:,1),1),vars(tuples(:,2),2),'or','MarkerSize',3,'MarkerFaceColor','r');
hold off
xlabel('Demand, mgd');
ylabel('TBC Flow, cfs');
grid on;


