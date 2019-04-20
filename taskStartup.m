function taskStartup(task)
!echo on
% check task.Diary for output
%!set
% !dir \\vgridfs\F_Drive
% !net use
%
% % MATLAB ghostscript won't work if cwd name is UNC
!net use F: /delete
!net use F: \\vgridfs\F_Drive /P:Y
!dir \\vgridfs\f_drive\IHM\BEOPEST
!dir F:\

!cd F:\IHM\BEOPEST
% !powershell -command """$PWD"""

% !tasklist /v
% !for /F %a in ('hostname') do set hn=%a
% !perl -e "foreach (keys(%ENV)) {print $_,q( ),$ENV{$_},qq(\n)}"
% setdbprefs('DataReturnFormat','numeric')
