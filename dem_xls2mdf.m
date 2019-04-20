conn = database('ProdAlloc','','',...
'com.microsoft.sqlserver.jdbc.SQLServerDriver',...
'jdbc:sqlserver://vgridfs:1433;TimeOut=600;Database=prodalloc;integratedSecurity=true;');
setdbprefs('DataReturnFormat','table');
colname = {'RealizationID','MonthYear','WPDA','Demand'};

d_cur = fileparts(mfilename('fullpath'));
f_dem = fullfile(d_cur,'WY 2019 monthly delivery and supply for budget InitialDraft.xlsx');
sheets = {'WY 2019','WY 2020','WY 2021','WY 2022','WY 2023','WY 2024'};
for i=sheets
    [dem,wpda] = xlsread(f_dem,char(i),'$b2:$n8');
    [~,monyr] = xlsread(f_dem,char(i),'$c1:$n1');
    
    t_dem = table(...
        zeros(numel(dem),1),...
        reshape(repmat(monyr,size(dem,1),1),numel(dem),1),...
        repmat(wpda,size(dem,2),1),...
        reshape(dem,numel(dem),1),...
        'VariableNames',colname);
    t_dem.WPDA = cellfun(@(y) y(1:3),t_dem.WPDA,'UniformOutput',false);

    fastinsert(conn,'Demand',colname,t_dem);
end
close(conn);
