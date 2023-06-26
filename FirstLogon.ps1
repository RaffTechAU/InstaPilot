## Clean script files
Remove-Item C:\Windows\Temp\*.ps1 -Force -Verbose
Remove-Item C:\Windows\System32\nircmd* -Force -Verbose -ErrorAction SilentlyContinue

## Get device model and CPU from system
$Model = Get-ComputerInfo -Property CsModel | Select-Object -ExpandProperty CsModel
$CPU = Get-WMIObject win32_Processor | select-object name | Select-Object -ExpandProperty name

## Choose appropriate prefix from model
if (!(Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) { exit 0 }
elseif (($Model -eq "Surface Book 3") -and ($CPU -like "*i7*")) { $Prefix = "SB3X"}
elseif ($Model -eq "Surface Book 3" ) { $Prefix = "SB3" }
elseif (($Model -eq "Surface Laptop Studio") -and ($CPU -like "*i7*")) { $Prefix = "SLSX"}
elseif ($Model -eq "Surface Laptop Studio") { $Prefix = "SLS" }
elseif ($Model -eq "Surface Pro 8") { $Prefix = "SP8" }
elseif (($Model -eq "Surface Pro 8") -and ($CPU -like "*i7*")) { $Prefix = "SP8X" }
elseif ($Model -eq "Surface Pro 7+") { $Prefix = "SP7P" }
elseif ($Model -eq "Surface Pro 7") { $Prefix = "SP7" }
else { exit 0 }

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null

do { $Asset = [int] [Microsoft.VisualBasic.Interaction]::InputBox(
    "Please input the 'Asset Number' (e.g. 123456):", #Description
    "Pared CSG IT" #Title
) } until ($Asset)

do { $Contract = [int] [Microsoft.VisualBasic.Interaction]::InputBox(
    "Please input the 'Contract Number' (e.g. 12):", #Description
    "Pared CSG IT" #Title
) } until ($Contract)

## Wait for internet
while (!(test-connection fast.com -Count 1 -Quiet)) {
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")     
    #Adjust delay here
    $delay = 10

    $Counter_Form = New-Object System.Windows.Forms.Form

    #Form size options
    $Counter_Form.width = 500
    $Counter_Form.height = 30
    $Counter_Form.ControlBox = $False
    $Counter_Form.FormBorderStyle = 'Fixed3D'
    $Counter_Form.StartPosition = "CenterScreen"
    $Font = New-Object System.Drawing.Font("Calibri",16)
    $Counter_Form.Font = $Font

    #Places form on top of everything else
    $Counter_Form.TopMost = $true

    $Counter_Label = New-Object System.Windows.Forms.Label
    $Counter_Label2 = New-Object System.Windows.Forms.Label

    #Labels size and position
    $Counter_Label.AutoSize = $true
    $Counter_Label.Location = New-Object System.Drawing.Point(5,5)
    $Counter_Label2.AutoSize = $true
    $Counter_Label2.Location = New-Object System.Drawing.Point(5,5)

    $Counter_Form.Controls.Add($Counter_Label)
    $Counter_Form.Controls.Add($Counter_Label2)

    while ($delay -ge 0)
    {
        $Counter_Form.Show()
        
        #Timer label's text
        $Counter_Label.Text = "Conntection test failed. Retrying in $($delay) seconds..."
        start-sleep 1
        $delay -= 1
    }
    $Counter_Form.Close()
    Start-Sleep 1
}

## E.g. SB3-123456-12
$NewName = "$Prefix-$Asset-$Contract"
Write-host "New name is: $NewName" -b Green
#Remove-Computer -ComputerName $NewName -force
#Remove-ADComputer -Identity $NewName
Rename-Computer -NewName $NewName

if ($error.count -ne 0) {
    Add-Type -AssemblyName PresentationCore,PresentationFramework
    $ButtonType = [System.Windows.MessageBoxButton]::Ok
    $MessageboxTitle = "The computer may not have been renamed!"
    $Messageboxbody = $error[0]
    $MessageIcon = [System.Windows.MessageBoxImage]::Information
    [System.Windows.MessageBox]::Show($Messageboxbody,$MessageboxTitle,$ButtonType,$messageicon)
}
Restart-Computer -Force