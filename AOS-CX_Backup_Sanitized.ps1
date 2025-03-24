# Load the Functions
. "\\<placeholder>\\Functions\\CredentialFunction.ps1"
. "\\<placeholder>\\Functions\\EmailFunctions.ps1"
. "\\<placeholder>\\Functions\\LogWriteFunctions.ps1"

# Define paths to Config Files
$SMTPConfigPath = "\\<placeholder>\\Config\\smtpconfig.xml"
$SwitchBackupConfigPath = "\\<placeholder>\\Config\\switchbackup-accountconfig.xml"

# Set the Key Path
$KeyPath = "\\<placeholder>\\Storage\\encryption.key"

# Define API version
$apiVersion = "v10.13"  # Update this if the API version changes

# Get the script name without extension
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Set the script name for the email alert function
$global:CallingScriptName = $ScriptName

# Create a log file path
$global:logDirectory = Join-Path -Path "\\<placeholder>\\Logs" -ChildPath $ScriptName
$global:LogFile = Join-Path -Path $global:logDirectory -ChildPath "${ScriptName}.log"

# Ensure log directory exists
if (-not (Test-Path -Path $global:logDirectory)) {
    New-Item -ItemType Directory -Path $global:logDirectory | Out-Null
}

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Starting Switch Backup Script"
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 0: Setting Functions, Config Files, and Parameters - Start"

# Initialize counters for success and failure
$totalSuccess = 0
$totalFailed = 0

# Create a collection to log detailed results
$switchResults = @()

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 1: Loading Credentials and Directories - Start"

# Load credentials
LogWrite -ScriptName $ScriptName -Message "[INFO] - Loading credentials from $SwitchBackupConfigPath"
$SwitchBackupData = Get-DecryptedSwitchBackupCredential -ConfigPath $SwitchBackupConfigPath -KeyPath $KeyPath

# Extract components
$SwitchBackupCredentials = $SwitchBackupData.Credential
$AltSwitchBackupCredentials = $SwitchBackupData.AltCredential
$csvPath = $SwitchBackupData.Input
$outputFolder = $SwitchBackupData.Output

# Ensure output folder exists
if (-not (Test-Path -Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Ignore SSL certificate validation
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { return $true }
    LogWrite -ScriptName $ScriptName -Message "[INFO] - SSL certificate validation bypass set using callback"
    } catch {
    LogWrite -ScriptName $ScriptName -Message "[ERROR] - Failed to set SSL certificate validation bypass: $_"
    throw
}

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 2: Importing Switch List - Start"

# Import the list of switches
try {
    LogWrite -ScriptName $ScriptName -Message "[INFO] - Importing switch list from $csvPath"
    $switches = Import-Csv -Path $csvPath
} catch {
    LogWrite -ScriptName $ScriptName -Message "[ERROR] - Failed to load switch list from $csvPath - $_"
    throw
}

# Functions for API interaction
function Login-SwitchAPI {
    param (
        [string]$BaseUrl,
        [PSCredential]$Credential,
        [PSCredential]$AltCredential,
        [string]$ApiVersion
    )

    try {
        # Attempt login with the primary credential
        $loginUrl = "$BaseUrl/rest/$ApiVersion/login"
        $loginBody = @{
            username = $Credential.Username
            password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
            )
        }
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Body $loginBody -ContentType "application/x-www-form-urlencoded" -WebSession $session
        LogWrite -ScriptName $ScriptName -Message "[INFO] - Login successful with primary credential (Radius)"
        return $session
    } catch {
        LogWrite -ScriptName $ScriptName -Message "[WARNING] - Login failed with primary credential (Radius)"

        # Attempt login with the alternate credential
        try {
            $loginBody = @{
                username = $AltCredential.Username
                password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AltCredential.Password)
                )
            }
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Body $loginBody -ContentType "application/x-www-form-urlencoded" -WebSession $session
            LogWrite -ScriptName $ScriptName -Message "[INFO] - Login successful with alternate credential (Local)"
            return $session
        } catch {
            LogWrite -ScriptName $ScriptName -Message "[WARNING] - Login failed with alternate credential (Local)"
            throw 
        }
    }
}

function Fetch-RunningConfig {
    param (
        [string]$BaseUrl,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$ApiVersion
    )

    try {
        $configEndpoint = "$BaseUrl/rest/$ApiVersion/configs/running-config"
        $response = Invoke-RestMethod -Uri $configEndpoint -Method Get -WebSession $Session -Headers @{
            "Accept" = "text/plain"
        }
        return $response
    } catch {
        LogWrite -ScriptName $ScriptName -Message "[ERROR] - Failed to fetch running config: $_"
        throw
    }
}

function Logout-SwitchAPI {
    param (
        [string]$BaseUrl,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$ApiVersion
    )

    try {
        $logoutUrl = "$BaseUrl/rest/$ApiVersion/logout"
        Invoke-RestMethod -Uri $logoutUrl -Method Post -WebSession $Session -Headers @{
            "Accept" = "*/*"
        }
    } catch {
        LogWrite -ScriptName $ScriptName -Message "[ERROR] - Logout failed: $_"
        throw
    }
}

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 3: Processing Switches - Start"

# Loop through each switch
foreach ($switch in $switches) {
    $hostname = $switch.Hostname
    $ipAddress = $switch.'IP Addresses'
    $baseUrl = "https://$ipAddress"

    # Generate timestamp for the filename
    $timestamp = (Get-Date -Format "yyyyMMddHHmmss")
    $outputFilePath = Join-Path -Path $outputFolder -ChildPath "${timestamp}_${hostname}.txt"

    LogWrite -ScriptName $ScriptName -Message "[INFO] - Processing switch: $hostname ($ipAddress)"

    # Initialize result status for the current switch
    $switchResult = @{
        Hostname = $hostname
        IPAddress = $ipAddress
        Status = "Unknown"
    }

    try {
        # Step 1: Login
        $session = Login-SwitchAPI -BaseUrl $baseUrl -Credential $SwitchBackupCredentials -AltCredential $AltSwitchBackupCredentials -ApiVersion $apiVersion

        # Step 2: Fetch Running Config
        $config = Fetch-RunningConfig -BaseUrl $baseUrl -Session $session -ApiVersion $apiVersion
        $config | Out-File -FilePath $outputFilePath -Encoding UTF8
        LogWrite -ScriptName $ScriptName -Message "[INFO] - Running config saved for $hostname"
        $switchResult.Status = "Success"
        $totalSuccess++

        # Step 3: Logout
        Logout-SwitchAPI -BaseUrl $baseUrl -Session $session -ApiVersion $apiVersion
        LogWrite -ScriptName $ScriptName -Message "[INFO] - Logout successful for $hostname"
        LogWrite -ScriptName $ScriptName -Message ("#" * 50)
    } catch {
        # Log the error
        LogWrite -ScriptName $ScriptName -Message "[ERROR] - Processing failed for $hostname - $_"
        LogWrite -ScriptName $ScriptName -Message ("#" * 50)
        $switchResult.Status = "Failed"
        $totalFailed++
    }

    # Add the switch result to the results collection
    $switchResults += $switchResult
}

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 4: Compile Summary - Start"

# Compile Summary
$successDetails = $switchResults | Where-Object { $_.Status -eq "Success" } | ForEach-Object {
    "Hostname: $($_.Hostname), IP: $($_.IPAddress)"
}
$successDetailsString = $successDetails -join "`n"

$failedDetails = $switchResults | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
    "Hostname: $($_.Hostname), IP: $($_.IPAddress)"
}
$failedDetailsString = $failedDetails -join "`n"

$summaryMessage = @"
Switch Backup Script Summary

Total Switches Processed: $($totalSuccess + $totalFailed)
Total Success: $totalSuccess
Total Failed: $totalFailed

Successful Switches:
$successDetailsString

Failed Switches:
$failedDetailsString
"@

# Log the summary
LogWrite -ScriptName $ScriptName -Message "[INFO] - Summary: $summaryMessage"

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 5: Send Summary Email - Start"

# Send Summary Email
try {
    Send-SuccessEmailAlert -SuccessMessage $summaryMessage -CallingScriptName $CallingScriptName -SMTPConfigPath $SMTPConfigPath -KeyPath $KeyPath
    LogWrite -ScriptName $ScriptName -Message "[INFO] - Summary email sent successfully"
} catch {
    LogWrite -ScriptName $ScriptName -Message "[ERROR] - Failed to send summary email: $_"
}

# Log the Status
LogWrite -ScriptName $ScriptName -Message "[INFO] - Phase 6: Stopping Switch Backup Script - Start"
# Final Script Completion Log
if ($totalFailed -eq 0) {
    LogWrite -ScriptName $ScriptName -Message "[INFO] - Switch Backup Script Completed Successfully"
    LogWrite -ScriptName $ScriptName -Message ("#" * 50)
} else {
    LogWrite -ScriptName $ScriptName -Message "[ERROR] - Switch Backup Script Completed with Errors"
    LogWrite -ScriptName $ScriptName -Message ("#" * 50)
}