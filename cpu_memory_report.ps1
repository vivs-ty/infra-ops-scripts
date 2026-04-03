$logtime = Get-Date -Format yyyyMMddhhmm
$ReportOutput = "C:\Scripts\Test\Logs\cpu_memory_report_$logtime.html"
$ServerList = Get-Content -Path "C:\Scripts\Test\ServerList.txt"

$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse; font-family: Verdana; font-size: 10pt;}
TH    {border-width: 1px; padding: 6px; border-style: solid; border-color: black; background-color: #6495ED; color: white;}
TD    {border-width: 1px; padding: 6px; border-style: solid; border-color: black;}
.warn {background-color: #FFD700;}
.crit {background-color: #FF6347; color: white;}
.ok   {background-color: #90EE90;}
</style>
"@

$TableHeader = @"
<table>
  <tr>
    <th>Server</th>
    <th>CPU Usage (%)</th>
    <th>Total RAM (GB)</th>
    <th>Used RAM (GB)</th>
    <th>Free RAM (GB)</th>
    <th>RAM Usage (%)</th>
    <th>Status</th>
  </tr>
"@

$TableRows = ""

foreach ($ServerName in $ServerList)
{
    $ServerName = $ServerName.ToUpper()
    $Reachable = Test-Path "\\$ServerName\c$\" -ErrorAction SilentlyContinue

    if ($Reachable -eq $true)
    {
        Write-Host "*******------ Connected to $ServerName ------*******"

        try
        {
            $Data = Invoke-Command -ComputerName $ServerName -ErrorAction Stop -ScriptBlock {

                # CPU usage — average load over 2 samples
                $CpuLoad = (Get-WmiObject -Class Win32_Processor |
                    Measure-Object -Property LoadPercentage -Average).Average

                # Memory
                $OS = Get-WmiObject -Class Win32_OperatingSystem
                $TotalRAM = [Math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
                $FreeRAM  = [Math]::Round($OS.FreePhysicalMemory / 1MB, 2)
                $UsedRAM  = [Math]::Round($TotalRAM - $FreeRAM, 2)
                $RamPct   = [Math]::Round(($UsedRAM / $TotalRAM) * 100, 1)

                [PSCustomObject]@{
                    CPU     = $CpuLoad
                    TotalGB = $TotalRAM
                    UsedGB  = $UsedRAM
                    FreeGB  = $FreeRAM
                    RamPct  = $RamPct
                }
            }

            # Determine status class
            $Status = "OK"
            $CssClass = "ok"
            if ($Data.CPU -ge 90 -or $Data.RamPct -ge 90) {
                $Status   = "CRITICAL"
                $CssClass = "crit"
            } elseif ($Data.CPU -ge 75 -or $Data.RamPct -ge 75) {
                $Status   = "WARNING"
                $CssClass = "warn"
            }

            Write-Host "  CPU: $($Data.CPU)%  RAM: $($Data.RamPct)%  [$Status]"

            $TableRows += @"
  <tr class='$CssClass'>
    <td>$ServerName</td>
    <td>$($Data.CPU)</td>
    <td>$($Data.TotalGB)</td>
    <td>$($Data.UsedGB)</td>
    <td>$($Data.FreeGB)</td>
    <td>$($Data.RamPct)</td>
    <td>$Status</td>
  </tr>
"@
        }
        catch
        {
            Write-Host "  ERROR collecting data from $ServerName : $_"
            $TableRows += @"
  <tr class='warn'>
    <td>$ServerName</td>
    <td colspan='6'>ERROR: Could not retrieve data — $_</td>
  </tr>
"@
        }
    }
    else
    {
        Write-Host "*******------ Unable to Connect $ServerName ------*******"
        $TableRows += @"
  <tr class='crit'>
    <td>$ServerName</td>
    <td colspan='6'>UNREACHABLE</td>
  </tr>
"@
    }
}

$FinalHtml = $TableHeader + $TableRows + "</table>"

ConvertTo-Html -Head $Header -Body $FinalHtml | Out-File $ReportOutput -Encoding utf8

Write-Host ""
Write-Host "Report saved to: $ReportOutput"

# Send email report
$Subject  = "CPU & Memory Report | $logtime"
$Smtp     = "smtp.hosting.local"
$To       = "Email <viveshrokzz@yahoo.com>"
$From     = "Resource Monitor <noreply@vivesh.net>"
$Body     = Get-Content -Path $ReportOutput | Out-String
Send-MailMessage -SmtpServer $Smtp -To $To -From $From -Subject $Subject -BodyAsHtml $Body
