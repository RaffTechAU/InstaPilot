Clear-Host

function Write-HostCenter { param($Message) Write-Host; Write-Host ("{0}{1}" -f (' ' * (([Math]::Max(0, $Host.UI.RawUI.BufferSize.Width / 2) - [Math]::Floor($Message.Length / 2)))), $Message) -f Green; Write-Host }

function ClearScreen {
    nircmd sendkey shift down
    nircmd sendkey f10 down
    nircmd sendkey shift up
    nircmd sendkey f10 up
    Start-Sleep 1
    taskkill /im cmd.exe /f
    nircmd win hide stitle "Microsoft account"
}

function RemoveGPO {
    # Remove logon script GPO
    Write-HostCenter 'Deleting logon script...'

    takeown /f "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" /a
    cmd /C 'icacls "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" /grant EVERYONE:F /q /c'
    Set-Content "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" -Value '' -Encoding Unicode -Force -Verbose
    
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
}

Start-Sleep 5

Write-HostCenter 'Clearing screen...'
Clear-Host
ClearScreen

## Resyncing the time
Write-HostCenter 'Resyncing the time...'
net start w32time
w32tm /resync /force

## Load NuGet
if (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue) { Write-Host "NuGet is already installed!" }
else { Install-PackageProvider NuGet -Confirm:$false -Force }

## Load modules
Write-HostCenter 'Loading dependencies...'
$Modules = @(
    @{ Name = "WindowsAutoPilotIntune"; Version = '5.0' }
    @{ Name = "PSWindowsUpdate"; Version = '2.2.0.3' }
)
foreach ($Module in $Modules) {

    if ((Get-Module -ListAvailable -Name $Module.Name).Version -like $Module.Version) {
        Write-Host "$($Module.Name) is already installed. Importing..."
        Import-Module $Module.Name
    } 
    else {
        Write-Host "$($Module.Name) not found! Installing and importing..."
        Install-Module $Module.Name -RequiredVersion $Module.Version -Confirm:$false -Force | Import-Module
    }
}

## For good measure :)
ClearScreen

## Install driver pack
if (-not(Test-Path C:\Windows\Temp\DriversFinished.txt)) {
    Write-HostCenter 'Installing the correct device drivers...'
    $Device = Get-ComputerInfo -Property CsModel,OSName
    $Link = (Invoke-WebRequest '10.8.45.1/tools/Drivers.csv' -UseBasicParsing -Verbose).Content | ConvertFrom-CSV | 
    Where-Object { ($_.Model -eq $Device.CsModel) -and ($_.OS -eq $Device.OSName.split(" ")[2]) } | Select-Object -ExpandProperty Link
    if ($Link) {
        Start-BitsTransfer -Source $Link -Destination 'C:\Windows\Temp\Drivers.msi' -Verbose
        Start-Process msiexec.exe -ArgumentList "/i C:\Windows\Temp\Drivers.msi /passive /norestart" -Wait
        while (((get-process) -like "*msiexec*").count -ge 2) { start-sleep 3 }
        New-Item C:\Windows\Temp\DriversFinished.txt
    } else { Write-Host "Can't find drivers!" -f Red}
}

Start-sleep 2

## Run a full system update
if (!(test-path C:\Windows\Logs\SkipUpdate.txt) -and !(test-path C:\Windows\Logs\DoUpdate.txt)) {
    Add-Type -AssemblyName PresentationCore,PresentationFramework
    $ButtonType = [System.Windows.MessageBoxButton]::YesNo
    $MessageboxTitle = "Update?"
    $Messageboxbody = "Run a full system update?"
    $MessageIcon = [System.Windows.MessageBoxImage]::Information
    $Result = [System.Windows.MessageBox]::Show($Messageboxbody,$MessageboxTitle,$ButtonType,$messageicon)
    if ($Result -eq 'Yes') { New-Item -Path C:\Windows\Logs -Name DoUpdate.txt -ItemType File }
    if ($Result -eq "No") { New-Item -Path C:\Windows\Logs -Name SkipUpdate.txt -ItemType File }
}
if (test-path C:\Windows\Logs\DoUpdate.txt) {
    Write-HostCenter 'Running a full system update...'

    do { $Error.Clear(); Install-WindowsUpdate -AcceptAll -AutoReboot } until ( $Error.Count -eq 0)
}

Start-Sleep 2

if (Test-Path C:\Windows\Logs\hybrid.txt) {
    Write-HostCenter 'Device is hybrid. Waiting for tenant...'

    for ($i = 1; $i -le 30; $i++ ) {
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot" | Where-Object {$_.CloudAssignedTenantDomain -ne ""}) {
            $Error.Clear()

            ClearScreen

            ##Create notification to inform operator AP policy has applied
            Add-Type -AssemblyName PresentationCore,PresentationFramework
            $ButtonType = [System.Windows.MessageBoxButton]::Ok
            $MessageboxTitle = "Success!"
            $Messageboxbody = "Autopilot policies have successfully been detected. Press OK to proceed to sign in."
            $MessageIcon = [System.Windows.MessageBoxImage]::Information
            [System.Windows.MessageBox]::Show($Messageboxbody,$MessageboxTitle,$ButtonType,$messageicon)
        
            Write-HostCenter "Refreshing OOBE..."
            RemoveGPO
            taskkill /im wwahost.exe /f
            exit
        }
        else {
            Write-Progress -Activity "Waiting for tenant" -PercentComplete ($i/0.3)
            Start-Sleep -Seconds 10
            Write-HostCenter "CloudAssignedTenantDomain registry key is not populated! [$i/30]" -F Yellow -B Black
            Write-Host
        }
    }
    Write-HostCenter "AP Policy still not present after 5 mins, attempting reboot to try again."
    Start-Sleep 3
    Restart-Computer -Force
}

## Connect Graph services
Connect-MSGraph

## Build provisioning GUI
Write-HostCenter 'Building provisioning GUI...'

[void] [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Pared IT'
$form.Size = New-Object System.Drawing.Size(200,150)
$form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'Fixed3D'
$Form.ControlBox = $false
$Form.MaximizeBox = $false
$form.TopMost = $true

$okButton = New-Object System.Windows.Forms.Button
$okButton.Location = New-Object System.Drawing.Point(20,70)
$okButton.Size = New-Object System.Drawing.Size(50,25)
$okButton.Anchor = 'left'
$okButton.Text = 'OK'
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $okButton
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(115,70)
$cancelButton.Size = New-Object System.Drawing.Size(50,25)
$cancelButton.Anchor = 'right'
$cancelButton.Text = 'Cancel'
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(22,5)
$label.Size = New-Object System.Drawing.Size(280,20)
$label.Text = "Autopilot profile:"
$label.Anchor = 'top'
$form.Controls.Add($label)

$List = New-Object system.Windows.Forms.ComboBox
$List.text = ""
$List.Location = New-Object System.Drawing.Point(20,30)
$List.width = 142
$List.Anchor = 'top'

## Gets list of all AP profiles and adds them to the drop down
$Profiles = Get-AutopilotProfile -Verbose
[array]::Reverse($Profiles)
foreach ($Profile in $Profiles) { [void] $List.Items.Add("$($Profile.displayName)") }

## Gets the current profile assigned to the device (if any) and makes it the default selection
$serial = (Get-ComputerInfo -Property BiosSeralNumber -Verbose | Select-Object -ExpandProperty BiosSeralNumber)
$CurrentProfile = (Get-AutopilotDevice -serial $serial -Verbose -expand |
Select-Object -ExpandProperty deploymentProfile -ErrorAction Ignore | 
Select-Object -ExpandProperty displayName -ErrorAction Ignore)
if ($CurrentProfile) { $List.SelectedItem = $CurrentProfile }
else { $List.SelectedIndex = 0 }
$form.Controls.Add($List)

$result = $form.ShowDialog()

## Run provisioning scripts
## ------------------------

Write-HostCenter 'Processing provisioning request...'

if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit }

## Find GroupTag
$SelectedProfile = Get-AutopilotProfile -Verbose | Where-Object displayName -like $List.SelectedItem
$SelectedGroup = Get-AutopilotProfileAssignments -id $SelectedProfile.id -Verbose
$GroupTag = (Get-AADGroup -groupId $SelectedGroup -Verbose | Select-Object -ExpandProperty membershipRule).split(':')[1].trim(')','"')
if (!($GroupTag)) { do { $GroupTag = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Please manually input a GroupTag", #Description
    "No GroupTag found for this profile!" #Title
) } until ($GroupTag) }

if ("$($SelectedProfile.'@odata.type')" -like "#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile") { 
    $Method = 'Hybrid' } else { $Method = 'Azure' 
}

## If the chosen profile doesn't match the existing grouptag
if (($NULL -ne $CurrentProfile) -and ("$($List.SelectedItem)" -ne "$CurrentProfile")) {
    
    Write-HostCenter "Changing groupTag to '$GroupTag'..."

    ## Sets the groupTag
    $DeviceID = (Get-AutopilotDevice -serial $serial -Verbose | Select-Object -ExpandProperty id)
    if ($DeviceID) { Set-AutopilotDevice -id $DeviceID -groupTag $GroupTag -Verbose }

    Get-Job | Wait-Job

    ## Repeatedly checks the chosen profile assigned the Autopilot assigned profile until they match
    do {
        $CurrentProfile = (Get-AutopilotDevice -Serial $serial -Expand -Verbose |
        Select-Object -ExpandProperty deploymentProfile -ErrorAction Ignore | 
        Select-Object -ExpandProperty displayName -ErrorAction Ignore)

        Write-Progress -Activity "Assigning '$($List.SelectedItem)' profile..." -Status "Current profile: $CurrentProfile"
        start-sleep 30
    } until ("$CurrentProfile" -like "$($List.SelectedItem)")
}

## Dump variables
Write-HostCenter "Importing device with GroupTag '$GroupTag'..."

## Run Commands
Install-Script Get-WindowsAutopilotInfo -RequiredVersion 3.5 -Confirm:$false -Force -Verbose
Get-WindowsAutopilotInfo.ps1 -GroupTag "$GroupTag" -online

if ($Method -eq 'Hybrid') {
    New-Item -Path C:\Windows\Logs -Name hybrid.txt -ItemType File
    Restart-Computer -Force
} else {
    ClearScreen

    Add-Type -AssemblyName PresentationCore,PresentationFramework
    $ButtonType = [System.Windows.MessageBoxButton]::Ok
    $MessageboxTitle = "Success!"
    $Messageboxbody = "The device has been imported successfully. Press OK to proceed to Autopilot." 
    $MessageIcon = [System.Windows.MessageBoxImage]::Information
    [System.Windows.MessageBox]::Show($Messageboxbody,$MessageboxTitle,$ButtonType,$messageicon)
    
    Write-HostCenter "Refreshing OOBE..."
    
    RemoveGPO
    taskkill /im wwahost.exe /f
    exit
}