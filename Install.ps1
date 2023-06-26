## Create centre text function
function Write-HostCenter { param($Message) Write-Host; Write-Host ("{0}{1}" -f (' ' * (([Math]::Max(0, $Host.UI.RawUI.BufferSize.Width / 2) - [Math]::Floor($Message.Length / 2)))), $Message) -f Magenta; Write-Host }

# Create logon script GPO
Write-HostCenter 'Creating GPO for logon script...'
New-Item -Path "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" -Force
Set-Content "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" -Value '
[Logon]
0CmdLine="%windir%\System32\cmd.exe"
0Parameters="/c "start powershell -ep bypass -command "do { $ping = test-netconnection 10.8.45.1 } until ($ping.PingSucceeded); iwr -useb 10.8.45.1/provision.ps1 | iex""
' -Encoding Unicode -Force -Verbose
 
$MachineGpExtensions = '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}'
$UserGpExtensions = '{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B66650-4972-11D1-A7CA-0000F87571E3}'
$contents = Get-Content "C:\Windows\System32\GroupPolicy\gpt.ini" -ErrorAction SilentlyContinue
$newVersion = 65537 # 0x00010001
 
$versionMatchInfo = $contents | Select-String -Pattern 'Version=(.+)'
if ($versionMatchInfo.Matches.Groups -and $versionMatchInfo.Matches.Groups[1].Success) {
    $newVersion += [int]::Parse($versionMatchInfo.Matches.Groups[1].Value)
}

(
    "[General]",
    "gPCMachineExtensionNames=[$MachineGpExtensions]",
    "Version=$newVersion",
    "gPCUserExtensionNames=[$UserGpExtensions]"
) | Out-File -FilePath "C:\Windows\System32\GroupPolicy\gpt.ini" -Encoding ascii

gpupdate /wait:10
Start-Sleep 2

## Set time
Write-HostCenter 'Setting the time server...'
net start w32time
w32tm /config /manualpeerlist:"10.90.196.11" /update
w32tm /resync /force

## Create directory to store temporary dependencies
New-Item 'C:\Windows\Temp\Pared' -ItemType Directory -Force

## Import Cyberhound certificate
Write-HostCenter 'Importing the Cyberhound certificate...'
Invoke-WebRequest 'http://10.8.45.1/tools/cacert.cer' -OutFile 'C:\Windows\Temp\Pared\cacert.cer' -Verbose
Import-Certificate -FilePath 'C:\Windows\Temp\Pared\cacert.cer' -CertStoreLocation Cert:\LocalMachine\Root -Verbose

## Download NirCMD for WindowsStyle hijacking
Write-HostCenter 'Downloading NirCMD for WindowStyle hijack...'
Invoke-WebRequest 'https://www.nirsoft.net/utils/nircmd-x64.zip' -OutFile 'C:\Windows\Temp\Pared\nircmd-x64.zip' -Verbose
Expand-Archive 'C:\Windows\Temp\Pared\nircmd-x64.zip' -DestinationPath 'C:\Windows\System32' -Force -Verbose

## Load dependencies and enroll into SEMM
<#
Write-HostCenter 'Downloading Surface UEFI Manager...'

Invoke-WebRequest 'http://10.8.45.1/tools/SurfaceUEFI_Manager_v2.97.139.0_x64.msi' -OutFile 'C:\Windows\Temp\Pared\SEMM.msi' -Verbose
Start-Process msiexec.exe -ArgumentList "/i C:\Windows\Temp\Pared\SEMM.msi /passive /norestart" -Wait
while (((get-process) -like "*msiexec*").count -ge 2) { start-sleep 3 }

Start-Sleep 3

Write-HostCenter "Downloading Pared's SEMM configuration..."
Invoke-WebRequest 'http://10.8.45.1/tools/ParedSEMM2023.zip' -OutFile 'C:\Windows\Temp\Pared\ParedSEMM2023.zip' -Verbose
Expand-Archive 'C:\Windows\Temp\Pared\ParedSEMM2023.zip' -DestinationPath 'C:\Windows\Temp\Pared' -Force -Verbose
powershell.exe -ep bypass 'C:\Windows\Temp\Pared\ParedUEFIConfig.ps1'
#>
## Clean temp
Remove-Item "C:\Windows\Temp\Pared" -Force -Recurse -Verbose

start-sleep 5