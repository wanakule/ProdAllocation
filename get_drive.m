function d=get_drive(pi)
pa = path_array(pi);
if regexpi(pa{1},'[a-zA-z]\:\\')
    d = pa{1};
elseif regexpi(pa{1},'\\\\\w+')
    d = fullfile(pa{1},pa{2});
else
    error('Input argument must be a full path!');
end

function p=path_array(pi,pa)
if nargin<2, pa = {}; end
p = [];
while isempty(p)
    [po,fo,eo] = fileparts(pi);
    if ~isempty(fo)
        pa = [{[fo eo]}; pa];
        p = path_array(po,pa);
    else
        p = [po; pa];
        break;
    end
end;