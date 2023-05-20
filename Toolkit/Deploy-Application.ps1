<#
.SYNOPSIS

PSApppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION

- The script is provided as a template to perform an install or uninstall of an application(s).
- The script either performs an "Install" deployment type or an "Uninstall" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

PSApppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2023 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

.PARAMETER DeploymentType

The type of deployment to perform. Default is: Install.

.PARAMETER DeployMode

Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.

.PARAMETER AllowRebootPassThru

Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode

Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging

Disables logging to file for the script. Default is: $false.

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"

.EXAMPLE

Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"

.INPUTS

None

You cannot pipe objects to this script.

.OUTPUTS

None

This script does not generate any output.

.NOTES

Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
- 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
- 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1

.LINK

https://psappdeploytoolkit.com
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $true,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)
Set-Location (split-path -parent $MyInvocation.MyCommand.Definition)

Try {
    ## Set the script execution policy for this process
    Try {
        Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
    }
    Catch {
    }

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
    [String]$appVendor = ''
    [String]$appName = ''
    [String]$appVersion = ''
    [String]$appArch = ''
    [String]$appLang = 'RU'
    [String]$appRevision = '01'
    [String]$appScriptVersion = '1.0.0'
    [String]$appScriptDate = 'XX/XX/2023'
    [String]$appScriptAuthor = '<familia_i>'
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [String]$installName = ''
    [String]$installTitle = ''
    ##*===============================================
    ## Variables: TASS Speciefic
    [datetime]$TASSScriptStartTime = (Get-Date).AddSeconds(-5)
    [bool]$TASS_IsChoco = $false # set $true to enable logic to use local TASS Choco repository
    [bool]$TASS_SCCMAppUpdateAutomation = $false # automatically determine app name and vendor by unc path
    [bool]$TASS_IsInnoSetup = $false # https://jrsoftware.org/ishelp/index.php?topic=setupcmdline

    if ($TASS_SCCMAppUpdateAutomation) {
        [String]$appVendor = Split-Path -Leaf -Path (Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Definition))
        [String]$appName = Split-Path -Leaf -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Definition)
    }
    # Install or update Choco from Internet and config local repo
    if ($TASS_IsChoco) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        [String]$TASSChocoRepo = "\\msk-sccm-ss02\pkg\Chocolatey_Repo" # path to choco local repo
        Start-Process -Wait -NoNewWindow -FilePath "choco" -ArgumentList "sources add -n `"TASS`" -s `"$TASSChocoRepo`" -log-file=$("$env:ProgramData\logs\software"+"\ChocoConfig.log") -y -f" -PassThru -Verbose
        Start-Process -Wait -NoNewWindow -FilePath "choco" -ArgumentList "upgrade chocolatey -s=`"TASS`" -log-file=$("$env:ProgramData\logs\software"+"\ChocoUpgrade.log") -y" -PassThru -Verbose
        [Array]$TASSLocalRepoInfo = $(try {((choco find -s="TASS" $appName -r) -split "`n" | Select-Object -Last 1).split("|")} catch {""})
        [String]$TASSChocoAppName = $TASSLocalRepoInfo[0] # proper app name for choco (use choco search to find out)
        [String]$TASSChocoAppVersion = $TASSLocalRepoInfo[1] # proper app name for choco (use choco search to find out)
        [String]$appVersion = $TASSChocoAppVersion
        [String]$TASSChocoPackageParams = ""
    }


    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [Int32]$mainExitCode = 0

    ## Variables: Script
    [String]$deployAppScriptFriendlyName = 'Deploy Application'
    [Version]$deployAppScriptVersion = [Version]'3.9.3'
    [String]$deployAppScriptDate = '02/05/2023'
    [Hashtable]$deployAppScriptParameters = $PsBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    }
    Else {
        $InvocationInfo = $MyInvocation
    }
    [String]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) {
            . $moduleAppDeployToolkitMain -DisableLogging
        }
        Else {
            . $moduleAppDeployToolkitMain
        }
    }
    Catch {
        If ($mainExitCode -eq 0) {
            [Int32]$mainExitCode = 60008
        }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $mainExitCode; Exit
        }
        Else {
            Exit $mainExitCode
        }
    }

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Installation'

        ## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
        Show-InstallationWelcome -CheckDiskSpace -Silent

        ## Show Progress Message (with the default message)
        # Show-InstallationProgress

        ## <Perform Pre-Installation tasks here>
        if ($TASS_IsInnoSetup) {
            $InnoSetupParameters = "/VERYSILENT /NORESTART /NOCANCEL /SUPPRESSMSGBOXES /SP- /CLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /LOG=$configToolkitLogDir\$($logName.Replace(".log","_InnoSetup.log"))"
        }

        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'

        ## Handle Zero-Config MSI Installations
        If ($useDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) {
                $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ }
            }
        }

        ## <Perform Installation tasks here>
        if ($TASS_IsChoco) {
            Execute-Process -Path "choco" -Parameters ("upgrade $TASSChocoAppName "+$(if ($TASSChocoPackageParams){"--params `"$TASSChocoPackageParams`" "})+"-force -s=TASS -log-file=`"$($configToolkitLogDir+ "\$($TASSChocoAppName.replace(" ","_"))`_chocoInstall.log")`" -y") -PassThru -Verbose -CreateNoWindow
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Installation'

        ## <Perform Post-Installation tasks here>

        ## Display a message at the end of the install
        # If (-not $useDefaultMsi) {
        #    Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait
        # }
    }
    ElseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Uninstallation'

        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        Show-InstallationWelcome -Silent -CloseApps $appName

        ## Show Progress Message (with the default message)
        # Show-InstallationProgress

        ## <Perform Pre-Uninstallation tasks here>
        if ($TASS_IsInnoSetup) {
            $InnoSetupParameters = "/VERYSILENT /NORESTART /NOCANCEL /SUPPRESSMSGBOXES /SP- /CLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /LOG=$configToolkitLogDir\$($logName.Replace(".log","_InnoSetup.log"))"
        }


        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Uninstallation'

        ## Handle Zero-Config MSI Uninstallations
        If ($useDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Execute-MSI @ExecuteDefaultMSISplat
        }

        ## <Perform Uninstallation tasks here>
        if ($TASS_IsChoco) {
            Execute-Process -Path "choco" -Parameters "uninstall $TASSChocoAppName -s=TASS -log-file=$($configToolkitLogDir+ "\$($TASSChocoAppName.replace(" ","_"))`_chocoUninstall.log") -y" -PassThru -Verbose -CreateNoWindow
        }



        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Uninstallation'

        ## <Perform Post-Uninstallation tasks here>


    }
    ElseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [String]$installPhase = 'Pre-Repair'

        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        # Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60

        ## Show Progress Message (with the default message)
        # Show-InstallationProgress

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [String]$installPhase = 'Repair'

        ## Handle Zero-Config MSI Repairs
        If ($useDefaultMsi) {
            [Hashtable]$ExecuteDefaultMSISplat = @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) {
                $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile)
            }
            Execute-MSI @ExecuteDefaultMSISplat
        }
        ## <Perform Repair tasks here>

        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [String]$installPhase = 'Post-Repair'

        ## <Perform Post-Repair tasks here>


    }

    ##*===============================================
	##* TASS Speciefic Add-on - Post actions
	##*===============================================

	## Pull  last 25 Application Event Log entries that contains $appName in the message
    if ($eventlog = (Get-EventLog -LogName Application -Newest 25 -Source msiinstaller | Where-Object {$_.Message -like "*$($appName.replace(" ","*"))*"})) {
        Write-Log -Message "Последние 25 записей из Application EventLog:"
        $eventlog.message | ForEach-Object { Write-Log $_ }
    }

    # Invoke SCCM HW Inv Schedule to update App Inventory
    # Invoke-SCCMTask -ScheduleID HardwareInventory -Verbose

    # Pull logs to SCCM Share if it's available
    $LogFileShare = "\\msk-sccm-ss02\logs\PSADT"

    if (Test-Connection -ComputerName "msk-sccm-ss02.corp.tass.ru" -Count 4 -ErrorAction SilentlyContinue) {
        $LogsFileShareFolder = $LogFileShare+"\$env:COMPUTERNAME"

        New-Folder -Path $LogFileShare -Verbose
        
        Write-Log -Message "Копирование логов в папку $LogsFileShareFolder`:"
		$CopyLogs = (Get-ChildItem $configToolkitLogDir | Where-Object LastWriteTime -ge $TASSScriptStartTime).FullName
        if ($CopyLogs) {
            $CopyLogs | ForEach-Object {Copy-File -Path $_ -Destination $LogsFileShareFolder -Recurse -Verbose}
        }
    }


    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [Int32]$mainExitCode = 60001
    [String]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}