# Azure DevOps Repository Backup Script
# This script mirrors all repositories from Azure DevOps to on-premises storage

#region Configuration
$config = @{
    # Azure DevOps Configuration
    Organization = "your-organization"  # Your Azure DevOps organization name
    Project = $null                    # Set to $null for all projects, or specific project name
    PAT = "your-personal-access-token" # Personal Access Token with Code (Read) permission
    
    # Backup Configuration
    BackupRootPath = "D:\Backups\AzureDevOps"  # Root backup directory
    RetentionDays = 30                          # How long to keep old backups
    RestoreRootPath = "D:\Restored_Repos"       # Where to create readable copies
    CreateRestoreCopy = $true                   # Set to $false to skip creating restore copies
    
    # Logging Configuration
    LogPath = "D:\Backup_Logs\AzureDevOps"
    
    # Email Notification (optional)
    EnableEmailAlerts = $false
    SmtpServer = "smtp.yourdomain.com"
    SmtpPort = 587
    EmailFrom = "devops-backup@yourdomain.com"
    EmailTo = @("admin@yourdomain.com")
    EmailUsername = "smtp-user"
    EmailPassword = "smtp-password"
}
#endregion

#region Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
    
    # File output
    Add-Content -Path $script:logFile -Value $logMessage
}

function Get-AzureDevOpsRepositories {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$PAT
    )
    
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
    $headers = @{
        Authorization = "Basic $base64AuthInfo"
    }
    
    try {
        if ($Project) {
            # Get repos for specific project
            $uri = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=7.0"
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            return $response.value
        } else {
            # Get all projects first
            $projectsUri = "https://dev.azure.com/$Organization/_apis/projects?api-version=7.0"
            $projects = Invoke-RestMethod -Uri $projectsUri -Headers $headers -Method Get
            
            $allRepos = @()
            foreach ($proj in $projects.value) {
                $uri = "https://dev.azure.com/$Organization/$($proj.name)/_apis/git/repositories?api-version=7.0"
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                $allRepos += $response.value
            }
            return $allRepos
        }
    }
    catch {
        Write-Log "Failed to retrieve repositories: $_" -Level ERROR
        throw
    }
}

function Backup-Repository {
    param(
        [object]$Repository,
        [string]$BackupPath,
        [string]$PAT
    )
    
    $repoName = $Repository.name
    $projectName = $Repository.project.name
    $cloneUrl = $Repository.remoteUrl
    
    # Create backup directory structure
    $repoBackupPath = Join-Path $BackupPath "$projectName\$repoName"
    $mirrorPath = Join-Path $repoBackupPath "mirror"
    $archivePath = Join-Path $repoBackupPath "archives"
    
    New-Item -ItemType Directory -Path $mirrorPath -Force | Out-Null
    New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
    
    try {
        # Modify clone URL to include PAT for authentication
        # Azure DevOps URL format: https://org@dev.azure.com/org/project/_git/repo
        # Need to convert to: https://PAT@dev.azure.com/org/project/_git/repo
        
        if ($cloneUrl -match "https://(.+)@dev.azure.com/(.+)") {
            # URL already has username, replace it with PAT
            $authenticatedUrl = $cloneUrl -replace "https://(.+)@dev.azure.com", "https://$PAT@dev.azure.com"
        }
        elseif ($cloneUrl -match "https://dev.azure.com/(.+)") {
            # URL doesn't have username, just add PAT
            $authenticatedUrl = $cloneUrl -replace "https://dev.azure.com", "https://$PAT@dev.azure.com"
        }
        else {
            throw "Unexpected clone URL format: $cloneUrl"
        }
        
        if (Test-Path (Join-Path $mirrorPath ".git")) {
            # Repository already exists - update it
            Write-Log "Updating existing mirror: $projectName/$repoName" -Level INFO
            
            Push-Location $mirrorPath
            $updateResult = git remote update --prune 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Git update failed: $updateResult"
            }
            Pop-Location
        }
        else {
            # Clone as mirror
            Write-Log "Creating new mirror: $projectName/$repoName" -Level INFO
            
            $cloneResult = git clone --mirror $authenticatedUrl $mirrorPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Git clone failed: $cloneResult"
            }
        }
        
        # Create compressed archive with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $archiveFile = Join-Path $archivePath "$repoName`_$timestamp.zip"
        
        Write-Log "Creating archive: $archiveFile" -Level INFO
        Compress-Archive -Path $mirrorPath -DestinationPath $archiveFile -Force
        
        # Get the archive file size
        $archiveSize = (Get-Item $archiveFile -ErrorAction SilentlyContinue).Length
        if (-not $archiveSize) { $archiveSize = 0 }
        
        Write-Log "Successfully backed up: $projectName/$repoName (Size: $([math]::Round($archiveSize / 1MB, 2)) MB)" -Level SUCCESS
        
        return @{
            Success = $true
            Repository = "$projectName/$repoName"
            Size = $archiveSize
        }
    }
    catch {
        Write-Log "Failed to backup $projectName/$repoName : $_" -Level ERROR
        return @{
            Success = $false
            Repository = "$projectName/$repoName"
            Error = $_.Exception.Message
        }
    }
}

function Remove-OldBackups {
    param(
        [string]$BackupPath,
        [int]$RetentionDays
    )
    
    Write-Log "Cleaning up backups older than $RetentionDays days" -Level INFO
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    
    Get-ChildItem -Path $BackupPath -Recurse -Filter "*.zip" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Write-Log "Removing old backup: $($_.FullName)" -Level INFO
            Remove-Item $_.FullName -Force
        }
}

function Create-RestoreCopy {
    param(
        [string]$MirrorPath,
        [string]$RestorePath,
        [string]$ProjectName,
        [string]$RepoName
    )
    
    try {
        $restoreDestination = Join-Path $RestorePath "$ProjectName\$RepoName"
        
        # Remove existing restore copy if it exists
        if (Test-Path $restoreDestination) {
            Write-Log "Removing existing restore copy: $restoreDestination" -Level INFO
            Remove-Item -Path $restoreDestination -Recurse -Force
        }
        
        # Create parent directory
        $parentDir = Split-Path $restoreDestination -Parent
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        
        Write-Log "Creating readable copy: $ProjectName/$RepoName" -Level INFO
        
        # Clone from mirror to create a normal working repository
        $cloneResult = git clone $MirrorPath $restoreDestination 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed: $cloneResult"
        }
        
        Write-Log "Successfully created restore copy at: $restoreDestination" -Level SUCCESS
        return $restoreDestination
    }
    catch {
        Write-Log "Failed to create restore copy for $ProjectName/$RepoName : $_" -Level WARNING
        return $null
    }
}

function Send-EmailNotification {
    param(
        [string]$Subject,
        [string]$Body,
        [hashtable]$Config
    )
    
    if (-not $Config.EnableEmailAlerts) { return }
    
    try {
        $securePassword = ConvertTo-SecureString $Config.EmailPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($Config.EmailUsername, $securePassword)
        
        Send-MailMessage -SmtpServer $Config.SmtpServer `
                        -Port $Config.SmtpPort `
                        -UseSsl `
                        -Credential $credential `
                        -From $Config.EmailFrom `
                        -To $Config.EmailTo `
                        -Subject $Subject `
                        -Body $Body `
                        -BodyAsHtml
    }
    catch {
        Write-Log "Failed to send email notification: $_" -Level ERROR
    }
}
#endregion

#region Main Execution
try {
    # Initialize logging
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Path $config.LogPath -Force | Out-Null
    $script:logFile = Join-Path $config.LogPath "backup_$timestamp.log"
    
    Write-Log "========================================" -Level INFO
    Write-Log "Azure DevOps Backup Started" -Level INFO
    Write-Log "========================================" -Level INFO
    
    # Validate Git installation
    $gitVersion = git --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Git is not installed or not in PATH"
    }
    Write-Log "Git version: $gitVersion" -Level INFO
    
    # Create backup directories
    New-Item -ItemType Directory -Path $config.BackupRootPath -Force | Out-Null
    
    $datePath = Join-Path $config.BackupRootPath (Get-Date -Format "yyyy-MM-dd")
    New-Item -ItemType Directory -Path $datePath -Force | Out-Null
    
    # Get all repositories
    Write-Log "Retrieving repository list from Azure DevOps..." -Level INFO
    $repositories = Get-AzureDevOpsRepositories -Organization $config.Organization `
                                                  -Project $config.Project `
                                                  -PAT $config.PAT
    
    Write-Log "Found $($repositories.Count) repositories to backup" -Level INFO
    
    # Backup each repository
    $results = @()
    $successCount = 0
    $failureCount = 0
    $restorePaths = @()
    
    foreach ($repo in $repositories) {
        $result = Backup-Repository -Repository $repo `
                                    -BackupPath $datePath `
                                    -PAT $config.PAT
        $results += $result
        
        if ($result.Success) {
            $successCount++
            
            # Create restore copy if enabled
            if ($config.CreateRestoreCopy) {
                $mirrorPath = Join-Path $datePath "$($repo.project.name)\$($repo.name)\mirror"
                $restorePath = Create-RestoreCopy -MirrorPath $mirrorPath `
                                                   -RestorePath $config.RestoreRootPath `
                                                   -ProjectName $repo.project.name `
                                                   -RepoName $repo.name
                if ($restorePath) {
                    $restorePaths += $restorePath
                }
            }
        } else {
            $failureCount++
        }
    }
    
    # Cleanup old backups
    Remove-OldBackups -BackupPath $config.BackupRootPath -RetentionDays $config.RetentionDays
    
    # Summary
    Write-Log "========================================" -Level INFO
    Write-Log "Backup Summary" -Level INFO
    Write-Log "Total Repositories: $($repositories.Count)" -Level INFO
    Write-Log "Successful: $successCount" -Level SUCCESS
    Write-Log "Failed: $failureCount" -Level $(if ($failureCount -gt 0) { "ERROR" } else { "INFO" })
    
    # Calculate total size safely
    $totalSize = 0
    foreach ($result in $results) {
        if ($result.Success -and $result.ContainsKey('Size') -and $result.Size -gt 0) {
            $totalSize += $result.Size
        }
    }
    
    if ($totalSize -gt 0) {
        Write-Log "Total Backup Size: $([math]::Round($totalSize / 1MB, 2)) MB" -Level INFO
    } else {
        Write-Log "Total Backup Size: 0 MB" -Level INFO
    }
    
    # Show restore paths
    if ($restorePaths.Count -gt 0) {
        Write-Log "" -Level INFO
        Write-Log "Readable copies created at:" -Level INFO
        foreach ($path in $restorePaths) {
            Write-Log "  - $path" -Level INFO
        }
        Write-Log "" -Level INFO
        Write-Log "Opening first restore location in File Explorer..." -Level INFO
        Start-Process explorer.exe -ArgumentList $config.RestoreRootPath
    }
    
    Write-Log "========================================" -Level INFO
    
    # Send email notification
    $emailSubject = "Azure DevOps Backup - $(if ($failureCount -eq 0) { 'SUCCESS' } else { 'COMPLETED WITH ERRORS' })"
    
    # Build email table rows
    $tableRows = ""
    foreach ($r in $results) {
        $status = if ($r.Success) { "<span style='color:green'>SUCCESS</span>" } else { "<span style='color:red'>FAILED</span>" }
        $size = if ($r.Success -and $r.ContainsKey('Size') -and $r.Size -gt 0) { 
            [math]::Round($r.Size / 1MB, 2) 
        } else { 
            "N/A" 
        }
        $tableRows += "<tr><td>$($r.Repository)</td><td>$status</td><td>$size</td></tr>`n"
    }
    
    $emailBody = @"
<h2>Azure DevOps Backup Report</h2>
<p><strong>Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Organization:</strong> $($config.Organization)</p>
<p><strong>Total Repositories:</strong> $($repositories.Count)</p>
<p><strong>Successful Backups:</strong> $successCount</p>
<p><strong>Failed Backups:</strong> $failureCount</p>
<p><strong>Total Size:</strong> $([math]::Round($totalSize / 1MB, 2)) MB</p>

<h3>Details:</h3>
<table border='1' style='border-collapse: collapse;'>
<tr><th>Repository</th><th>Status</th><th>Size (MB)</th></tr>
$tableRows
</table>

<p>Log file: $script:logFile</p>
"@
    
    Send-EmailNotification -Subject $emailSubject -Body $emailBody -Config $config
    
    if ($failureCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "Critical error: $_" -Level ERROR
    Write-Log $_.ScriptStackTrace -Level ERROR
    
    # Send failure notification
    Send-EmailNotification -Subject "Azure DevOps Backup - FAILED" `
                          -Body "Backup failed with error: $_<br><br>Log file: $script:logFile" `
                          -Config $config
    exit 1
}
#endregion
