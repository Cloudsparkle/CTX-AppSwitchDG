<#
.SYNOPSIS
  Switch Citrix published applications to different delivery group
.DESCRIPTION
 Based on week number, the script will switch published applications to a different delivery group
.INPUTS
 None
.OUTPUTS
 None
.NOTES
  Version:        1.0
  Author:         Bart Jacobs - @Cloudsparkle
  Creation Date:  17/6/2022
  Purpose/Change: Switch applications to different delivery group
 .EXAMPLE
  None
#>

# Try loading Citrix Powershell modules, exit when failed
If ((Get-PSSnapin "Citrix*" -EA silentlycontinue) -eq $null)
{
  try {Add-PSSnapin Citrix* -ErrorAction Stop }
  catch {Write-error "Error loading Citrix Powershell snapins"; Return }
}

# Select Deleveriy group name prefix
$DGName = "DG-Name_" #replace with own Delivery Group Name

# Select DDC
$DDC = "DDC-Server" # Replace with own DDC

$Currentweeknumber = get-date -UFormat %V
$Serversrebooted = $false
$Appsswitched = $false
do
{
  if ($Appsswitched -eq $false)
  {
    if($Currentweeknumber % 2 -eq 0 )
    {
      $ToBe_DGNumber = 2
      $Current_DGNumber = 1
    }
    else
    {
      $ToBe_DGNumber = 1
      $Current_DGNumber = 2
    }

    $ToBe_DG = $DGName+$ToBe_DGNumber
    $Current_DG = $DGName+$Current_DGNumber

    $ToBe_CTX_DG = Get-BrokerDesktopGroup -AdminAddress $DDC -Name $ToBe_DG | Select UUID, name
    $Current_CTX_DG = Get-BrokerDesktopGroup -AdminAddress $DDC -Name $Current_DG | Select UUID, name

    $BrokerApps = Get-BrokerApplication -AdminAddress $DDC -AssociatedDesktopGroupUUID $Current_CTX_DG.UUID

    Write-host "Setting active DG to $ToBe_DG" -foregroundcolor Green

    foreach ($BrokerApp in $BrokerApps)
    {
      Write-Host "Processing"$brokerapp.Name -ForegroundColor Yellow
      Add-BrokerApplication -AdminAddress $DDC -DesktopGroup $ToBe_CTX_DG.Name -InputObject $BrokerApp
      Remove-BrokerApplication -AdminAddress $DDC -DesktopGroup $Current_CTX_DG.Name -Name $BrokerApp.Name
      $Appsswitched = $true
    }
  }

  if ($Serversrebooted -eq $false)
  {
    Write-Host "Getting all sessions from" ($Current_CTX_DG.Name)"..." -ForegroundColor Yellow
    $ExistingSessions = Get-BrokerSession -MaxRecordCount 10000 -AdminAddress $DDC -DesktopGroupName $Current_CTX_DG.name
    if ($ExistingSessions.count -eq 0)
    {
      Write-Host "No lingering sessions found, rebooting session hosts" -ForegroundColor Yellow
      $Servers = Get-BrokerMachine -DesktopGroupName $Current_CTX_DG.name
      Foreach ($Server in $Servers)
      {
        New-BrokerHostingPowerAction -MachineName $Server.DNSName -Action Restart
      }
      $Serversrebooted = $true
    }
    Else
    {
      Write-Host "Getting all disconnected sessions from" ($Current_CTX_DG.Name)"..." -ForegroundColor Yellow
      $DisconnectedSessions = Get-BrokerSession -MaxRecordCount 10000 -AdminAddress $DDC -DesktopGroupName $Current_CTX_DG.name -SessionState Disconnected
      foreach ($DisconnectedSession in $DisconnectedSessions)
      {
        Write-Host "Logging off disconnected session for user"$DisconnectedSession.UserFullName -ForegroundColor Green
        Stop-BrokerSession $DisconnectedSession
      }

      Write-Host "Getting all Idle sessions from" ($Current_CTX_DG.Name)"..." -ForegroundColor Yellow
      $IdleSessions = (Get-BrokerSession -AdminAddress $DDC -DesktopGroupName $Current_CTX_DG.name -MaxRecordCount 20000 | where idleduration -GT 00:00:00)
      foreach ($IdleSession in $IdleSessions)
      {
        Write-Host "Logging off idle session for user"$IdleSession.UserFullName -ForegroundColor Green
        Stop-BrokerSession $Idlesession
      }
    }
  }

  if (($Serversrebooted -eq $false) -and ($Appsswitched -eq $false))
  {
    Write-Host "Waiting for next run..." -ForegroundColor yellow
    [System.GC]::Collect()
    start-sleep 15
  }
}
until($Serversrebooted -and $Appsswitched)
