#.\Submit-ProdAlloc.ps1 -nfe 200 -freq 50 -nreal '[1,2]' -slist @(7..7)
param
(
	[int[]] $slist=@(2..7),	# Available KT id as AMTLAB code
	[string] $nreal='100',	# number realization or partial list of realizations of the current seqid
	[int] $sample_id=7,		# LHS ID (from Sample Table)
	[int] $nseed=5,		# Number of random seed = number solution sets
	[int] $moffset=0,		# Offset to the first month of Water Year
	[int] $nfe=5000,		# Number of function evaluations per borg call
	[int] $freq=250,		# Interval to printout runtime information
	[switch] $utest,	# Use MATLAB parallel toolbox, else unit test mode
	[switch] $ml_noexit
)

$sb0 = {
    param($server,$nreal,$nseed,$moffset,$nfe,$freq,$utest,$ml_noexit,$d_cur,$sid)

    if ($utest) { $use_partool = 'false' }
    else { $use_partool = 'true' }
    if ($ml_noexit) { $noexit = '' }
    else { $noexit = 'exit;' }

    $mlcmd = "borg_moea_fn({0},{1},{2},{3},{4},{5},[],{6})" -f `
        $nreal,$nseed,$moffset,$nfe,$freq,$use_partool,$sid
    $title = "`$host.ui.RawUI.WindowTitle='borg_moea_fn $nreal $nseed'"
    #$mlcmd = "C:\MATLAB\R2019a\bin\matlab.exe -automation -sd '$d_cur' -r '$mlcmd; $noexit'"
    #$pscmd = "C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe -NoExit -Command"
    $mlcmd = "matlab.exe -nosplash -sd '$d_cur' -r '$mlcmd; $noexit'"
    $pscmd = "C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe -NoExit -Command"

# RDP file template
$rdp = @"
screen mode id:i:1
desktopwidth:i:1920
desktopheight:i:1200
session bpp:i:32
winposstr:s:0,1,1,1,1200,800
compression:i:1
keyboardhook:i:2
audiocapturemode:i:0
videoplaybackmode:i:1
connection type:i:2
displayconnectionbar:i:1
disable wallpaper:i:1
allow font smoothing:i:0
allow desktop composition:i:0
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
full address:s:$server
audiomode:i:0
redirectprinters:i:1
redirectcomports:i:0
redirectsmartcards:i:1
redirectclipboard:i:1
redirectposdevices:i:0
redirectdirectx:i:1
autoreconnection enabled:i:1
authentication level:i:0
prompt for credentials:i:0
negotiate security layer:i:1
remoteapplicationmode:i:0
alternate shell:s:$pscmd "$mlcmd"
shell working directory:s:$d_cur
gatewayhostname:s:
gatewayusagemethod:i:4
gatewaycredentialssource:i:4
gatewayprofileusagemethod:i:0
promptcredentialonce:i:1
use redirection server name:i:0
username:s:$env:USERDOMAIN\$env:USERNAME
drivestoredirect:s:
"@

    $f_rdp = "C:\windows\temp\$server.rdp"
    Set-Content $f_rdp -Value $rdp
    sleep -Seconds 1
    $f_rdp
	
    # spawn mstsc process and get system process
    C:\Windows\System32\mstsc.exe "$f_rdp" -v:$server

    sleep -Seconds 15
    Remove-Item -Path $f_rdp -Force
    $f_rdp
}

# Start script
cd F:\ProdAllocation
$ml_bin = 'C:\MATLAB\R2019a\bin'
$ps_bin = 'C:\Windows\System32\WindowsPowershell\v1.0'
$sid = '['+[string]::join(',',($slist |%{$_.ToString()}))+']'

$sb1 = {
    param($cred,$ml_bin,$ps_bin)
    New-PSDrive 'F' 'FileSystem' '\\vgridfs\f_drive' -Persist -Credential $cred
    $path = [System.Environment]::GetEnvironmentVariable("Path","User")
    if ($path.Split(';') -inotcontains $ml_bin) {
        [System.Environment]::SetEnvironmentVariable("Path","$ml_bin;"+$path,"User")
    }
    if ($path.Split(';') -inotcontains $ps_bin) {
        [System.Environment]::SetEnvironmentVariable("Path","$ps_bin;"+$path,"User")
    }
    #sqllocaldb create v11.0 -s
}

#$cred = Get-Credential
$slist |%{
    $s = $_.ToString('KUHNTUCKER0')
    Invoke-Command -ComputerName $s -ScriptBlock $sb1 -ArgumentList $cred,$ml_bin,$ps_bin
    sleep -Seconds 1
    $f_rdp = Invoke-Command -ComputerName . -ScriptBlock $sb0 `
        -ArgumentList $s,$nreal,$nseed,$moffset,$nfe,$freq,$utest,$ml_noexit,$PWD,$sid
    # C:\Windows\System32\mstsc $f_rdp /v:$s
}


# Monitoring CPU usage to make sure Borg/ProdAlloc is running
$sb2 = {
    param($s,$cred)
    $temp = $true
    $CookedValue = 100
    while (($CookedValue -gt 90) -and ($temp.Length -gt 0)) {
        sleep -Seconds 3
        $CookedValue = Invoke-Command -ComputerName "$s.vgrid.net" -ScriptBlock {
            (Get-Counter '\Processor(_total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 `
            ).CounterSamples.CookedValue `
            } -Credential $cred -Authentication Credssp
            
        $temp = Invoke-Command -ComputerName "$s.vgrid.net" -ScriptBlock {
            gwmi -Class win32_process -Filter "commandline like '%parallelserver%'" `
            } -Credential $cred -Authentication Credssp |%{$_}
    }
    Out-Host -InputObject ('Detecting {0} RDP session is idle, will logoff' -f $s)
    Invoke-Command -ComputerName $s -ScriptBlock {
        $tss = ((quser | ? { $_ -imatch $env:USERNAME }) -split ' +')[2]
        if ($tss) { logoff $tss }
	    }
}

$jb = @()
$slist |%{
    $s = $_.ToString('KUHNTUCKER0')
    $jb += Invoke-Command -ComputerName . -ScriptBlock $sb2 -ArgumentList $s,$cred -AsJob
}

Wait-Job $jb
$slist |%{
    $s = $_.ToString('KUHNTUCKER0')
    Get-TSSession -ComputerName $s -UserName $cred.UserName.Split('\')[1] |
    Stop-TSSession -ComputerName $s -Force
}
Remove-Job $jb
