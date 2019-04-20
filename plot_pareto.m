function plot_pareto(i_seeds)
load('.\Output\runtime.mat','Spam');
% i_seeds = 1:1;
n_sel = length(i_seeds);
temp = cell(n_sel,1);
for i=1:n_sel
    temp{i,1} = [Spam(i_seeds(i)).objs, ones(size(Spam(i_seeds(i)).objs,1),1)*i_seeds(i)];
end
temp = cell2mat(temp);

% set color order
colorder = repmat([...
         0         0         0;
         0    0.4470    0.7410;
    0.8500    0.3250    0.0980;
    0.9290    0.6940    0.1250;
    0.4940    0.1840    0.5560;
    0.4660    0.6740    0.1880;
    0.3010    0.7450    0.9330;
    0.5000    0.5000    0.5000;
    0.6350    0.0780    0.1840;
],ceil(n_sel/9),1);
colorder = colorder(1:n_sel,:);
sel_seeds = ismember(temp(:,end),i_seeds);
figure;
h = gscatter(temp(sel_seeds,3),temp(sel_seeds,4),temp(sel_seeds,end),...
    colorder,'o',3,'on','Under','Cost');
for i=1:length(h), set(h(i),'MarkerFaceColor',colorder(i,:)); end
grid on
% Plot of comparison multiobject from different output frequency
figure;
hold on
for i=1:n_sel
    % use last one as the optimum solution
    temp = Spam(i_seeds(i)).objs(end,:);
    temp(:,4) = temp(:,4)*1e-3;
    plot(1:4,temp(:,1:4),'marker','o','color',colorder(i,:));
end
hold off
xlim([0.5 4.5])
xticks(1:4); xticklabels({'Diff','Over','Under','Cost'});
grid on
end