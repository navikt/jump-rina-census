<#
.SYNOPSIS
    Collects most of the OS and RINA SW version numbers in a single-
    or multi-server RINA 2020.

.DESCRIPTION
    Assumes the environment variable EESSI_HOME to point to the path
    of the REST component installation, e.g. "D:\EESSI".
    Assumes your Apache HTTPD runs on the same server. 
    NB PostgreSQL version is only the client version if you run PG
    on a different server.
    Many other assumptions...
    NB I don't know PowerShell. No time was spent on robustness.

.NOTES
    File Name      : Census2.ps1
    Author         : torsten.kirschner at nav.no
    Prerequisite   : PowerShell 5.1
    Copyright 2024 - NAV
    License        : This work is licensed under the MIT License.

.COAUTHORS
    thomas.kristoffersen at nav.no - The brain in this here operation.

.CREDITS
    Martin.Strelec at socpoist.sk - Provided insights on RINA SW.
    djordje.nizetic at regos.hr - Provided insights on RINA SW.
#>

param (
    [string]$eessi_home = $env:EESSI_HOME
)

# HolodeckB2B
function Get-HolodeckVersion {
    # Construct the path to the version file
    $versionFilePath = Join-Path $script:eessi_home "HolodeckB2B\ver"

    # Check if the version file exists
    if (Test-Path $versionFilePath) {
        # Read the content of the version file
        $HolodeckB2BVersion = (Get-Content $versionFilePath -Raw).Trim()

        # Create a custom object with the desired properties
        $holodeckObject = [PSCustomObject]@{
            DisplayName    = "HolodeckB2B"
            DisplayVersion = $HolodeckB2BVersion
            Note    = $null  # You can modify this based on your requirements
        }

        # Output the custom object
        return $holodeckObject
    }
    else {
        Write-Host "Version file not found: $versionFilePath"
    }
}

# Apache HTTPD
function Get-ApacheVersion {

    # Specify the URL of your Apache server
    $apacheUrl = "http://localhost/portal_new/favicon.ico"

    # Make an HTTP request to the root URL and inspect the response headers
    try {
        $response = Invoke-WebRequest -Uri $apacheUrl -Method Head
        $serverVersion = $response.Headers['Server']
        #Write-Host "Apache HTTPD Version: $serverVersion"
        $versionMatch = $serverVersion -match 'Apache/(\d+\.\d+\.\d+)'
        $apacheVersion = if ($versionMatch) { $matches[1] } else { $null }

        # Create a custom object with the desired properties
        $newApp = [PSCustomObject]@{
             DisplayName = "Apache HTTPD"
             DisplayVersion = $apacheVersion
             Note = $null  # or you can set it to $null or any default value
        }
        $newApp | Format-Table -AutoSize
        # Add the new entry to the installedApps variable
        return $newApp

    } catch {
        Write-Host "Error fetching Apache HTTPD version: $_"
    }

}

# LogStash
function Get-LogstashVersion {
    # Construct the path to the Logstash executable
    $logstashExecutable = Join-Path $script:eessi_home "Logstash\bin\logstash.bat"

    try {
        # Run the Logstash command to get the version information
        $logstashOutput = & $logstashExecutable --version 2>&1

        # Extract the version using Select-String and a regular expression
        $logstashVersion = $logstashOutput | Select-String -Pattern 'logstash (\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }

        # Create a custom object with the desired properties
        $newApp = [PSCustomObject]@{
             DisplayName = "logstash"
             DisplayVersion = $logstashVersion
             Note = $null  # or you can set it to $null or any default value
        }
        $newApp | Format-Table -AutoSize
        # Add the new entry to the installedApps variable
        return $newApp

    } catch {
        Write-Host "Error getting Logstash version: $_"
    }
}

# ElasticSearch
function Get-ElasticsearchVersion {
    # Specify the path to your logstash.conf file
    $logstashConfigPath = Join-Path $script:eessi_home "Logstash\config\logstash.conf"

    # Read the logstash.conf file
    $logstashConfig = Get-Content -Path $logstashConfigPath -Raw

    # Use regular expression to extract the Elasticsearch URL
    $match = $logstashConfig -match 'hosts\s*=>\s*\["([^"]+)"\]'
    $elasticsearchUrl = if ($match) { $matches[1] } else { $null }

    # If a match is found, proceed to query Elasticsearch
    if ($elasticsearchUrl) {
        try {
            # Construct the URL for the root endpoint
            $rootUrl = "http://$elasticsearchUrl/"

            # Make the HTTP request to get Elasticsearch version
            $versionInfo = Invoke-RestMethod -Uri $rootUrl -Method Get
            # Create a custom object with the desired properties
            $newApp = [PSCustomObject]@{
                DisplayName = $versionInfo.name
                DisplayVersion = $versionInfo.version.number
                Note = $null  # or you can set it to $null or any default value
            }
            $newApp | Format-Table -AutoSize
            # Add the new entry to the installedApps variable
            return $newApp
        } catch {
            Write-Host "Error querying Elasticsearch version: $_"
        }
    } else {
        Write-Host "Elasticsearch URL not found in the Logstash configuration file."
    }
}

# Check if $eessi_home is still empty, and if so, prompt the user for input
if (-not $eessi_home) {
    $eessi_home = Read-Host "Enter EESSI_HOME path"
}

# Now you can use $eessi_home in your script
Write-Host "EESSI_HOME path: $eessi_home"

$systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem


Get-ComputerInfo | Select-Object WindowsProductName, @{Name='Note'; Expression={
        $numberOfCores = $systemInfo.NumberOfLogicalProcessors
        $totalRAMBytes = $systemInfo.TotalPhysicalMemory
        $totalRAMGB = [math]::round($totalRAMBytes / 1GB, 2)
        "#cores: $numberOfCores RAM: ${totalRAMGB}GB"
    }} | Format-Table -AutoSize

# Get a list of all installed apps
$installedApps = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Select-Object DisplayName, DisplayVersion, @{Name='Note'; Expression={''}}

$installedApps += Get-ApacheVersion
$installedApps += Get-LogstashVersion
$installedApps += Get-ElasticsearchVersion 
$installedApps += Get-HolodeckVersion 

# Filter for rows containing "JDK" or "PostgreSQL"
$filteredApps = $installedApps | Where-Object { $_.DisplayName -match 'Apache|logstash|elasticsearch|JDK|PostgreSQL|7-Zip|Tomcat|Holodeck' }

# Display the filtered result
$filteredApps | Format-Table -AutoSize
