<#
.SYNOPSIS
	Toast Notification Extension script file, must be dot-sourced by the AppDeployToolkitExtension.ps1 script.
.DESCRIPTION
	Replaces all the windows and dialogs with Toast Notifications with a lot of visual and functional improvements.
.NOTES
	Author:  Leonardo Franco Maragna
	Version: 1.1
	Date:    2023/03/28
#>
[CmdletBinding()]
Param (
)

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VariableDeclaration

## Variables: Extension Info
$ToastNotificationExtName = "ToastNotificationExtension"
$ToastNotificationExtScriptFriendlyName = "Toast Notification Extension"
$ToastNotificationExtScriptVersion = "1.1"
$ToastNotificationExtScriptDate = "2023/03/28"
$ToastNotificationExtSubfolder = "PSADT.ToastNotification"
$ToastNotificationExtConfigFileName = "ToastNotificationConfig.xml"

## Variables: Toast Notification Script Dependency Files
[IO.FileInfo]$dirToastNotificationExtFiles = Join-Path -Path $scriptRoot -ChildPath $ToastNotificationExtSubfolder
[IO.FileInfo]$dirToastNotificationExtSupportFiles = Join-Path -Path $dirSupportFiles -ChildPath $ToastNotificationExtSubfolder
[IO.FileInfo]$ToastNotificationConfigFile = Join-Path -Path $dirToastNotificationExtFiles -ChildPath $ToastNotificationExtConfigFileName
if (-not $ToastNotificationConfigFile.Exists) { throw "$($ToastNotificationExtScriptFriendlyName) XML configuration file [$ToastNotificationConfigFile] not found." }

## Variables: Required Support Files
[IO.FileInfo]$envPoshWinRTLibraryPath = (Get-ChildItem -Path $dirToastNotificationExtSupportFiles -Recurse -Include "*PoshWinRT*.dll").FullName | Select-Object -First 1
[IO.FileInfo]$envUser32LibraryPath = Join-Path -Path $envSystem32Directory -ChildPath "user32.dll"

## Variables: RegEx Patterns
#  WildCards used to detect processes
$ProcessObjectsWildCardRegExPattern = "[\*\?\[\]]"
#  Regex used to detect filtered apps by path or title
$ProcessObjectsTitlePathRegExPattern = "(?<=(title:|path:)).+"

## Variables: Translate Buttons
[scriptblock]$TranslateButton = {
	Param (
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		$Parameter
	)

	switch ($Parameter) {
		"OK" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 800 -DisableFunctionLogging).Replace("&", "") }
		"Cancel" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 801 -DisableFunctionLogging).Replace("&", "") }
		"Abort" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 802 -DisableFunctionLogging).Replace("&", "") }
		"Retry" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 803 -DisableFunctionLogging).Replace("&", "") }
		"Ignore" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 804 -DisableFunctionLogging).Replace("&", "") }
		"Yes" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 805 -DisableFunctionLogging).Replace("&", "") }
		"No" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 806 -DisableFunctionLogging).Replace("&", "") }
		"Close" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 807 -DisableFunctionLogging).Replace("&", "") }
		"Help" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 808 -DisableFunctionLogging).Replace("&", "") }
		"TryAgain" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 809 -DisableFunctionLogging).Replace("&", "") }
		"Continue" { [string](Get-StringFromFile -Path $envUser32LibraryPath -StringID 810 -DisableFunctionLogging).Replace("&", "") }
		default { $Parameter }
	}
}

## Variables: Resolve Parameters. For backward compatibility
if (-not (Test-Path "variable:ResolveParameters")) {
	[scriptblock]$ResolveParameters = {
		Param (
			[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
			[ValidateNotNullOrEmpty()]$Parameter
		)

		switch -regex ($Parameter.Value.GetType().Name) {
			"^(SwitchParameter|Boolean)$" { "-$($Parameter.Key):`$$($Parameter.Value.ToString().ToLower())" }
			"^((u){0,1}int(\d)+|single|decimal|double)$" { "-$($Parameter.Key):$($Parameter.Value)" }
			default { "-$($Parameter.Key):`'$($Parameter.Value)`'" }
		}
	}
}

## Import variables from XML configuration file
[Xml.XmlDocument]$xmlToastNotificationConfigFile = Get-Content -LiteralPath $ToastNotificationConfigFile -Encoding UTF8
[Xml.XmlElement]$xmlToastNotificationConfig = $xmlToastNotificationConfigFile.ToastNotification_Config

#  Get Config File Details
[Xml.XmlElement]$configToastNotificationConfigDetails = $xmlToastNotificationConfig.Config_File

#  Check compatibility version
$configToastNotificationConfigVersion = [string]$configToastNotificationConfigDetails.Config_Version
#$configToastNotificationConfigDate = [string]$configToastNotificationConfigDetails.Config_Date

try {
	if ([version]$ToastNotificationExtScriptVersion -ne [version]$configToastNotificationConfigVersion) {
		Write-Log -Message "The $($ToastNotificationExtScriptFriendlyName) version [$([version]$ToastNotificationExtScriptVersion)] is not the same as the $($ToastNotificationExtConfigFileName) version [$([version]$configToastNotificationConfigVersion)]. Problems may occurs." -Severity 2 -Source $ToastNotificationExtName
	}
}
catch {}

#  Get Toast Notification General Options
[Xml.XmlElement]$xmlToastNotificationOptions = $xmlToastNotificationConfig.ToastNotification_Options
$configToastNotificationGeneralOptions = [PSCustomObject]@{
	WorkingDirectory                                  = [string](Invoke-Expression -Command 'try { if (([IO.Path]::IsPathRooted($xmlToastNotificationOptions.WorkingDirectory)) -and (Test-Path -Path $xmlToastNotificationOptions.WorkingDirectory -IsValid)) { [string]($xmlToastNotificationOptions.WorkingDirectory).Trim() } else { $dirAppDeployTemp } } catch { $dirAppDeployTemp }') -replace "&|@", ""
	TaggingVariable                                   = [string](Remove-InvalidFileNameChars -Name (Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.TaggingVariable))) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.TaggingVariable) } else { $installName } } catch { $installName }')) -replace "&| |@|\.", ""
	ProtocolName                                      = [string](Remove-InvalidFileNameChars -Name (Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.ProtocolName))) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.ProtocolName) } else { "psadttoastnotification" } } catch { "psadttoastnotification" }')) -replace "&| |@|\.", ""
	SubscribeToEvents                                 = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.SubscribeToEvents)) } catch { $true }'
	ShowToastNotificationAsyncTimeout                 = Invoke-Expression -Command 'try { if ([int32]::Parse([string]($xmlToastNotificationOptions.ShowToastNotificationAsyncTimeout)) -gt 5) { [int32]::Parse([string]($xmlToastNotificationOptions.ShowToastNotificationAsyncTimeout)) } else { 5 } } catch { 5 }'

	LimitTimeoutToInstallationUI                      = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.LimitTimeoutToInstallationUI)) } catch { $true }'

	CriticalProcesses_NeverKill                       = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.CriticalProcesses_NeverKill))) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.CriticalProcesses_NeverKill) -split "," } else { @() } } catch { @() }'
	CriticalProcesses_NeverBlock                      = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.CriticalProcesses_NeverBlock))) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.CriticalProcesses_NeverBlock) -split "," } else { @() } } catch { @() }'

	InstallationWelcome_AlwaysParseMuiCacheAppName    = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.InstallationWelcome_AlwaysParseMuiCacheAppName)) } catch { $false }'

	WelcomePrompt_MaxRunningProcessesRows             = Invoke-Expression -Command 'try { if ([int32]::Parse([string]($xmlToastNotificationOptions.WelcomePrompt_MaxRunningProcessesRows)) -in @(1..5)) { [int32]::Parse([string]($xmlToastNotificationOptions.WelcomePrompt_MaxRunningProcessesRows)) } else { 5 } } catch { 5 }'
	WelcomePrompt_ShowCloseMessageIfCustomMessage     = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.WelcomePrompt_ShowCloseMessageIfCustomMessage)) } catch { $true }'
	WelcomePrompt_ReplaceContinueButtonDeploymentType = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.WelcomePrompt_ReplaceContinueButtonDeploymentType)) } catch { $true }'

	BlockExecution_TemplateFileName                   = [string](Remove-InvalidFileNameChars -Name (Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.BlockExecution_TemplateFileName))) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationOptions.BlockExecution_TemplateFileName) } else { "BlockExecutionToastNotificationTemplate.xml" } } catch { "BlockExecutionToastNotificationTemplate.xml" }')) -replace "&| |@", ""

	InstallationProgress_ShowIndeterminateProgressBar = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.InstallationProgress_ShowIndeterminateProgressBar)) } catch { $true }'
	#InstallationProgress_ChangeStylePerLine           = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.InstallationProgress_ChangeStylePerLine)) } catch { $false }'

	InstallationRestartPrompt_ShowIcon                = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationOptions.InstallationRestartPrompt_ShowIcon)) } catch { $false }'
}

$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "ResourceFolder" -Value (Join-Path -Path $configToastNotificationGeneralOptions.WorkingDirectory -ChildPath $configToastNotificationGeneralOptions.ProtocolName | Join-Path -ChildPath $configToastNotificationGeneralOptions.TaggingVariable)

#  Defines and invokes the scriptblock that contains changes to the button logic
[scriptblock]$SetSubscribeToEventsProperties = {
	if ($configToastNotificationGeneralOptions.SubscribeToEvents) {
		$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "ActivationType" -Value "foreground" -Force
		$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "ArgumentsPrefix" -Value "" -Force
	}
	else {
		$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "ActivationType" -Value "protocol" -Force
		$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "ArgumentsPrefix" -Value ('{0}:' -f ( <#0#> $configToastNotificationGeneralOptions.ProtocolName)) -Force
	}
}
Invoke-Command -ScriptBlock $SetSubscribeToEventsProperties -NoNewScope

#  Defines and invokes the scriptblock that sets the icons size used in notifications
[scriptblock]$SetIconSizeProperties = {
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_PreSpacing" -Value 9 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_TargetSize" -Value 16 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_TargetStacking" -Value "top" -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_TargetRemoveMargin" -Value $false -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_PostSpacing" -Value 16 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_BlockSize" -Value 270 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Small_BlockSizeCollapsed" -Value 300 -Force

	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_PreSpacing" -Value 0 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_TargetSize" -Value 32 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_TargetStacking" -Value "center" -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_TargetRemoveMargin" -Value $false -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_PostSpacing" -Value 8 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_BlockSize" -Value 270 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Large_BlockSizeCollapsed" -Value 288 -Force

	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_PreSpacing" -Value $null -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_TargetSize" -Value 48 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_TargetStacking" -Value "center" -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_TargetRemoveMargin" -Value $false -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_PostSpacing" -Value 0 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_BlockSize" -Value 270 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_ExtraLarge_BlockSizeCollapsed" -Value 274 -Force

	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_PreSpacing" -Value $null -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_TargetSize" -Value 256 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_TargetStacking" -Value "center" -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_TargetRemoveMargin" -Value $false -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_PostSpacing" -Value 0 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_BlockSize" -Value 1008 -Force
	$configToastNotificationGeneralOptions | Add-Member -MemberType NoteProperty -Name "IconSize_Biggest_BlockSizeCollapsed" -Value 1032 -Force
}
Invoke-Command -ScriptBlock $SetIconSizeProperties -NoNewScope

#  Get Toast Notification AppId Options
[Xml.XmlElement]$xmlToastNotificationAppId = $xmlToastNotificationConfig.AppId_Options
$configToastNotificationAppId = [PSCustomObject]@{
	AppId                 = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.AppId)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.AppId)) } else { "PSADT.ToastNotification" } } catch { "PSADT.ToastNotification" }'
	DisplayName           = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.DisplayName)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.DisplayName)) } else { "PSADT Toast Notification" } } catch { "PSADT Toast Notification" }'
	IconUri               = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.IconUri)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.IconUri)) } else { "%SystemRoot%\ImmersiveControlPanel\images\logo.png" } } catch { "%SystemRoot%\ImmersiveControlPanel\images\logo.png" }'
	IconBackgroundColor   = Invoke-Expression -Command 'try { [int32]::Parse([string]($xmlToastNotificationAppId.IconBackgroundColor)) } catch { 0 }'
	LaunchUri             = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.LaunchUri)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationAppId.LaunchUri)) } else { [string]::Empty } } catch { [string]::Empty }'
	ShowInSettings        = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationAppId.ShowInSettings)) } catch { $false }'
	AllowContentAboveLock = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationAppId.AllowContentAboveLock)) } catch { $false }'
	ShowInActionCenter    = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationAppId.ShowInActionCenter)) } catch { $false }'
}

#  Get Toast Notification Scripts Options
[Xml.XmlElement]$xmlToastNotificationScripts = $xmlToastNotificationConfig.Scripts_Options
$configToastNotificationScripts = [PSCustomObject]@{
	ScriptsEnabledOrder = [array]($xmlToastNotificationScripts.ScriptsEnabledOrder -split ",")
	CommandVBS          = $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationScripts.CommandVBS)
	CommandCMD          = $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationScripts.CommandCMD)
	ScriptVBS           = [string]$xmlToastNotificationScripts.ScriptVBS
	ScriptCMD           = [string]$xmlToastNotificationScripts.ScriptCMD
}

#  Get Toast Notification visual style options for each supported function
$SupportedFunctions = @("WelcomePrompt", "BalloonTip", "DialogBox", "InstallationRestartPrompt", "InstallationPrompt", "InstallationProgress", "BlockExecution")

foreach ($supportedFunction in $SupportedFunctions) {
	$null = Set-Variable -Name "configToastNotification$($supportedFunction)Options" -Force -Value (
		[PSCustomObject]@{
			UpdateInterval                      = Invoke-Expression -Command 'try { if ([int32]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".UpdateInterval)) -in @(1..10)) { [int32]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".UpdateInterval)) } else { 3 } } catch { 3 }'
			ShowAttributionText                 = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ShowAttributionText)) } catch { $true }'

			ImageHeroShow                       = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageHeroShow)) } catch { $false }'
			ImageHeroFileName                   = Remove-InvalidFileNameChars -Name (Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageHeroFileName)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageHeroFileName)) } else { [string]::Empty } } catch { [string]::Empty }')
			ImageAppLogoOverrideShow            = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageAppLogoOverrideShow)) } catch { $false }'
			ImageAppLogoOverrideFileName        = Remove-InvalidFileNameChars -Name (Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageAppLogoOverrideFileName)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageAppLogoOverrideFileName)) } else { [string]::Empty } } catch { [string]::Empty }')
			ImageAppLogoOverrideCircularCrop    = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ImageAppLogoOverrideCircularCrop)) } catch { $true }'

			ShowApplicationsIcons               = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ShowApplicationsIcons)) } catch { $true }'
			ApplicationsIconsSize               = Invoke-Expression -Command 'try { if ($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationConfig."$($supportedFunction)_Options".ApplicationsIconsSize) -in @("Small", "Large", "ExtraLarge", "Biggest")) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationConfig."$($supportedFunction)_Options".ApplicationsIconsSize) } else { "ExtraLarge" } } catch { "ExtraLarge" }'
			CollapseApplicationsIcons           = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".CollapseApplicationsIcons)) } catch { $false }'
			ShowExtendedApplicationsInformation = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ShowExtendedApplicationsInformation)) } catch { $true }'
			ShowDialogIconAsAppLogoOverride     = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".ShowDialogIconAsAppLogoOverride)) } catch { $true }'
			DialogsIconsSize                    = Invoke-Expression -Command 'try { if ($ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationConfig."$($supportedFunction)_Options".DialogsIconsSize) -in @("Small", "Large", "ExtraLarge", "Biggest")) { $ExecutionContext.InvokeCommand.ExpandString($xmlToastNotificationConfig."$($supportedFunction)_Options".DialogsIconsSize) } else { "Large" } } catch { "Large" }'
			CollapseDialogsIcons                = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".CollapseDialogsIcons)) } catch { $true }'

			AudioSource                         = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".AudioSource)))) { $ExecutionContext.InvokeCommand.ExpandString([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".AudioSource)) } else { "ms-winsoundevent:Notification.Looping.Alarm2" } } catch { "ms-winsoundevent:Notification.Looping.Alarm2" }'
			AudioLoop                           = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".AudioLoop)) } catch { $false }'
			AudioSilent                         = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlToastNotificationConfig."$($supportedFunction)_Options".AudioSilent)) } catch { $true }'
		}
	)
}

#  Define ScriptBlock for Loading Message UI Language Options (default for English if no localization found)
[scriptblock]$xmlLoadLocalizedUIToastNotificationMessages = {
	[Xml.XmlElement]$xmlUIToastNotificationMessages = $xmlToastNotificationConfig.$xmlUIMessageLanguage
	$configUIToastNotificationMessages = [PSCustomObject]@{
		AttributionTextAutoContinue               = [string]$xmlUIToastNotificationMessages.AttributionTextAutoContinue
		RemainingTimeHours                        = [string]$xmlUIToastNotificationMessages.RemainingTimeHours
		RemainingTimeHour                         = [string]$xmlUIToastNotificationMessages.RemainingTimeHour
		RemainingTimeMinutes                      = [string]$xmlUIToastNotificationMessages.RemainingTimeMinutes
		RemainingTimeMinute                       = [string]$xmlUIToastNotificationMessages.RemainingTimeMinute
		DeploymentTypeInstall                     = [string]$xmlUIToastNotificationMessages.DeploymentTypeInstall
		DeploymentTypeUninstall                   = [string]$xmlUIToastNotificationMessages.DeploymentTypeUninstall
		DeploymentTypeRepair                      = [string]$xmlUIToastNotificationMessages.DeploymentTypeRepair

		WelcomePrompt_WelcomeMessage              = [string]$xmlUIToastNotificationMessages.WelcomePrompt_WelcomeMessage
		WelcomePrompt_CloseMessageSingular        = [string]$xmlUIToastNotificationMessages.WelcomePrompt_CloseMessageSingular
		WelcomePrompt_CloseMessagePlural          = [string]$xmlUIToastNotificationMessages.WelcomePrompt_CloseMessagePlural
		WelcomePrompt_AttributionTextAutoDeferral = [string]$xmlUIToastNotificationMessages.WelcomePrompt_AttributionTextAutoDeferral
		WelcomePrompt_ProgressBarTitleSingular    = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ProgressBarTitleSingular
		WelcomePrompt_ProgressBarTitlePlural      = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ProgressBarTitlePlural
		WelcomePrompt_ProgressBarStatus           = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ProgressBarStatus
		WelcomePrompt_MoreApplicationsMessage     = [string]$xmlUIToastNotificationMessages.WelcomePrompt_MoreApplicationsMessage
		WelcomePrompt_RemainingDeferrals          = [string]$xmlUIToastNotificationMessages.WelcomePrompt_RemainingDeferrals
		WelcomePrompt_DeferMessage                = [string]$xmlUIToastNotificationMessages.WelcomePrompt_DeferMessage
		WelcomePrompt_DeferMessageDeadline        = [string]$xmlUIToastNotificationMessages.WelcomePrompt_DeferMessageDeadline
		WelcomePrompt_DeferMessageDeadlineWarning = [string]$xmlUIToastNotificationMessages.WelcomePrompt_DeferMessageDeadlineWarning
		WelcomePrompt_ButtonCloseSingular         = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ButtonCloseSingular
		WelcomePrompt_ButtonClosePlural           = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ButtonClosePlural
		WelcomePrompt_ButtonContinue              = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ButtonContinue
		WelcomePrompt_ButtonDefer                 = [string]$xmlUIToastNotificationMessages.WelcomePrompt_ButtonDefer

		BlockExecution_CloseMessage               = [string]$xmlUIToastNotificationMessages.BlockExecution_CloseMessage
		BlockExecution_BlockMessageSingular       = [string]$xmlUIToastNotificationMessages.BlockExecution_BlockMessageSingular
		BlockExecution_BlockMessagePlural         = [string]$xmlUIToastNotificationMessages.BlockExecution_BlockMessagePlural
		BlockExecution_MoreApplicationsMessage    = [string]$xmlUIToastNotificationMessages.BlockExecution_MoreApplicationsMessage

		RestartPrompt_RestartMessage              = [string]$xmlUIToastNotificationMessages.RestartPrompt_RestartMessage
		RestartPrompt_AttributionText             = [string]$xmlUIToastNotificationMessages.RestartPrompt_AttributionText
		RestartPrompt_ProgressBarTitle            = [string]$xmlUIToastNotificationMessages.RestartPrompt_ProgressBarTitle
		RestartPrompt_ProgressBarStatus           = [string]$xmlUIToastNotificationMessages.RestartPrompt_ProgressBarStatus
		RestartPrompt_AutoRestartMessage          = [string]$xmlUIToastNotificationMessages.RestartPrompt_AutoRestartMessage
		RestartPrompt_SaveMessage                 = [string]$xmlUIToastNotificationMessages.RestartPrompt_SaveMessage
		RestartPrompt_ButtonRestartLater          = [string]$xmlUIToastNotificationMessages.RestartPrompt_ButtonRestartLater
		RestartPrompt_ButtonRestartNow            = [string]$xmlUIToastNotificationMessages.RestartPrompt_ButtonRestartNow

		InstallationPrompt_AttributionTextDismiss = [string]$xmlUIToastNotificationMessages.InstallationPrompt_AttributionTextDismiss
	}
}

#  Defines the original functions to be renamed
$FunctionsToRename = @()
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-WelcomePromptOriginal";	Value = $(${Function:Show-WelcomePrompt}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-BalloonTipOriginal";	Value = $(${Function:Show-BalloonTip}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-DialogBoxOriginal"; Value = $(${Function:Show-DialogBox}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-InstallationRestartPromptOriginal"; Value = $(${Function:Show-InstallationRestartPrompt}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-InstallationPromptOriginal"; Value = $(${Function:Show-InstallationPrompt}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Show-InstallationProgressOriginal"; Value = $(${Function:Show-InstallationProgress}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }
$FunctionsToRename += [PSCustomObject]@{ Scope = "Script"; Name = "Close-InstallationProgressOriginal"; Value = $(${Function:Close-InstallationProgress}.ToString() -replace "http(s){0,1}:\/\/psappdeploytoolkit\.com", "") }

## Reusable ScriptBlocks called by functions
#  Creates an empty Dictionary Data
[scriptblock]$ToastNotificationNewDictionaryData = {
	return [PSCustomObject]@{
		attributionText             = ""
		progressValue               = ""
		progressValueStringOverride = ""
		progressTitle               = ""
		progressStatus              = ""
	}
}

#  Updates the remaining time data
[scriptblock]$ToastNotificationGetRemainingTime = {
	Param (
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[timespan]$RemainingTime
	)

	$RemainingHours = $RemainingTime.Days * 24 + $RemainingTime.Hours
	$RemainingMinutes = $RemainingTime.Minutes
	$TotalRemainingMinutes = $RemainingHours * 60 + $RemainingMinutes
	#if ($null -eq $initialremainingMinutes) { [int]$initialremainingMinutes = ($countdownTime.Subtract($startTime)).TotalMinutes }

	$RemainingTimeLabel = [string]::Empty
	if ($RemainingHours -gt 1) { $RemainingTimeLabel += "$($RemainingHours) $($configUIToastNotificationMessages.RemainingTimeHours) " }
	elseif ($RemainingHours -eq 1) { $RemainingTimeLabel += "$($RemainingHours) $($configUIToastNotificationMessages.RemainingTimeHour) " }
	if ($RemainingMinutes -eq 1) { $RemainingTimeLabel += "$($RemainingMinutes) $($configUIToastNotificationMessages.RemainingTimeMinute)" }
	else { $RemainingTimeLabel += "$($RemainingMinutes) $($configUIToastNotificationMessages.RemainingTimeMinutes)" }

	return [PSCustomObject]@{
		RemainingTimeLabel    = $RemainingTimeLabel
		RemainingHours        = $RemainingHours
		RemainingMinutes      = $RemainingMinutes
		TotalRemainingMinutes = $TotalRemainingMinutes
	}
}

#  Fallbacks to original function if any problem occur
[scriptblock]$ToastNotificationFallbackToOriginalFunction = {
	if ($ToastNotificationGroup -in ("WelcomePrompt", "DialogBox", "InstallationRestartPrompt", "InstallationPrompt")) {
		## Clear any previous displayed Toast Notification
		Clear-ToastNotificationHistory -Group $ToastNotificationGroup

		## Remove user environment result variable
		Remove-ToastNotificationResult -ResultVariable $ResultVariable -IncludeOriginalPID $true

		if ($Result -notin $AllowedResults) {
			Write-Log -Message "A problem occured with the Toast Notification or function result [$Result] not allowed. Falling back to original function..." -Severity 3 -Source ${CmdletName}

			switch ($ToastNotificationGroup) {
				"WelcomePrompt" {
					#  Get the parameters passed to the function for invoking the function asynchronously
					[hashtable]$welcomePromptParameters = $PSBoundParameters

					#  Modify ProcessDescriptions parameter to suit the original function parameter.
					if ($welcomePromptParameters.ContainsKey("ProcessDescriptions")) {
						$welcomePromptParameters.Remove("ProcessDescriptions")
						[string]$runningProcessDescriptions = ($processDescriptions.ProcessDescription | Sort-Object -Unique) -join ", "
						$welcomePromptParameters.Add("ProcessDescriptions", $runningProcessDescriptions)
					}

					$Result = Show-WelcomePromptOriginal @welcomePromptParameters
				}
				"DialogBox" { $Result = Show-DialogBoxOriginal @PSBoundParameters }
				"InstallationRestartPrompt" { $Result = Show-InstallationRestartPromptOriginal @PSBoundParameters }
				"InstallationPrompt" { $Result = Show-InstallationPromptOriginal @PSBoundParameters }
			}
		}
	}
	elseif ($ToastNotificationGroup -in ("BalloonTip", "InstallationProgress", "BlockExecution")) {
		if ($ToastNotificationVisible -ne $true -and -not $OriginalFunctionTriggered) {
			## Clear any previous displayed Toast Notification
			Clear-ToastNotificationHistory -Group $ToastNotificationGroup

			Write-Log -Message "A problem occured with the Toast Notification or it's not visible. Falling back to original function..." -Severity 3 -Source ${CmdletName}

			switch ($ToastNotificationGroup) {
				"BalloonTip" { Show-BalloonTipOriginal @PSBoundParameters }
				"InstallationProgress" { Show-InstallationProgressOriginal @PSBoundParameters }
				"BlockExecution" {
					try {
						#  Create a mutex and specify a name without acquiring a lock on the mutex
						[boolean]$showBlockedAppDialogMutexLocked = $false
						[string]$showBlockedAppDialogMutexName = "Global\PSADT_ShowBlockedAppDialog_Message"
						[Threading.Mutex]$showBlockedAppDialogMutex = New-Object -TypeName "System.Threading.Mutex" -ArgumentList ($false, $showBlockedAppDialogMutexName)
						#  Attempt to acquire an exclusive lock on the mutex, attempt will fail after 1 millisecond if unable to acquire exclusive lock
						if ((Test-IsMutexAvailable -MutexName $showBlockedAppDialogMutexName -MutexWaitTimeInMilliseconds 1) -and ($showBlockedAppDialogMutex.WaitOne(1))) {
							[boolean]$showBlockedAppDialogMutexLocked = $true
							Show-InstallationPrompt -Title $installTitle -Message $configBlockExecutionMessage -Icon "Warning" -ButtonRightText "OK"
						}
						else {
							#  If attempt to acquire an exclusive lock on the mutex failed, then exit script as another blocked app dialog window is already open
							Write-Log -Message "Unable to acquire an exclusive lock on mutex [$showBlockedAppDialogMutexName] because another blocked application dialog window is already open. Exiting script..." -Severity 2 -Source ${CmdletName}
						}
					}
					catch {
						Write-Log -Message "There was an error in displaying the Installation Prompt.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						[Environment]::Exit(60005)
					}
					finally {
						if ($showBlockedAppDialogMutexLocked) { $null = $showBlockedAppDialogMutex.ReleaseMutex() }
						if ($showBlockedAppDialogMutex) { $showBlockedAppDialogMutex.Close() }
					}
				}
			}
		}
		$OriginalFunctionTriggered = $true
	}
}

#  Shows the Toast Notification
[scriptblock]$ToastNotificationShowScriptBlock = {
	[scriptblock]$InvokesToastNotificationAsUser = {
		## Constructs the Toast Notification template
		try {
			#  Constructs the Toast Notification template
			Invoke-Command -ScriptBlock $DefineToastNotificationTemplate -NoNewScope

			#  Logs the template for debugging
		($scriptSeparator, $XMLTemplate, $scriptSeparator) | ForEach-Object { Write-Log -Message $_ -Source ${CmdletName} -DebugMessage }

			#  Sets the initial Notification Data if exists
			if ($SetToastNotificationInitialNotificationData) {
				Invoke-Command -ScriptBlock $SetToastNotificationInitialNotificationData -NoNewScope
			}
		}
		catch {
			Write-Log -Message "Unable to create Toast Notification template...`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

			$XMLTemplate = $null
		}

		## Invokes Toast Notification As User
		try {
			if ([string]::IsNullOrWhiteSpace($XMLTemplate)) {
				$Result = $null
			}
			else {
				#  Sets the parameters used by the invokation function and calls it
				$ToastNotificationShowParameters = @{
					InvokedMethod             = "Show"
					ResultVariable            = $ResultVariable
					Group                     = $ToastNotificationGroup
					AllowedResults            = $AllowedResults
					DismissedResults          = @("ApplicationHidden", "Click", "TimedOut", "UserCanceled")
					ToastNotificationTemplate = $XMLTemplate
					UpdateInterval            = $configFunctionOptions.UpdateInterval
					DictionaryData            = $InitialDictionaryData
				}

				$Result = Invoke-ToastNotificationAsUser @ToastNotificationShowParameters
			}
		}
		catch {
			Write-Log -Message "An error ocurred when trying to invoke Toast Notification as user.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

			$Result = $null
		}
	}

	## Constructs the Toast Notification and invokes it as user
	Invoke-Command -ScriptBlock $InvokesToastNotificationAsUser -NoNewScope

	if ($Result -eq "RetryWithProtocol") {
		#  Retry with protocol insted of event subscription
		Invoke-Command -ScriptBlock $InvokesToastNotificationAsUser -NoNewScope
	}

	if ([string]::IsNullOrWhiteSpace($Result)) {
		#  Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope
	}
	elseif ($Result -match "^\d+$") {
		$Result = $null

		$ToastNotificationVisible = $true

		if ($UpdateToastNotificationData) {
			$LastRemainingTimeLabel = ""
			Invoke-Command -ScriptBlock $UpdateToastNotificationData -NoNewScope
		}
	}
}

#  ScriptBlock that loops until the Toast Notification gives a result
[scriptblock]$ToastNotificationLoopUntilResult = {
	do {
		## Checks if the Toast Notification is visible
		$ToastNotificationVisible = Test-ToastNotificationVisible -Group $ToastNotificationGroup

		## Get Toast Notification result from environment variable
		$Result = Get-ToastNotificationResult -AllowedResults $AllowedResults -ResultVariable $ResultVariable

		Write-Log -Message "Toast Notification result before switch [$Result]." -Severity 2 -Source ${CmdletName} -DebugMessage

		switch ($Result) {
			#  Expected button clicked
			{ $_ -in $AllowedResults } {
				$ToastNotificationVisible = $false

				if ($ToastNotificationGroup -eq "InstallationRestartPrompt") {
					if ($_ -eq "RestartLater") {
						Write-Log -Message "Toast Notification result [$_], the user has choosen to restart later..." -Source ${CmdletName}
					}
					elseif ($_ -eq "RestartNow") {
						Write-Log -Message "Toast Notification result [$_], the user has choosen to restart now..." -Source ${CmdletName}
						break
					}
				}
				elseif ($ToastNotificationGroup -eq "InstallationPrompt") {
					if ($_ -ne "Timeout") {
						Write-Log -Message "Toast Notification result [$($ExecutionContext.InvokeCommand.ExpandString('$button{0}Text' -f $_))], exiting function..." -Source ${CmdletName}
					}
					break
				}
				else {
					Write-Log -Message "Toast Notification action [$_], continuing the script execution..." -Source ${CmdletName}
					break
				}
			}

			"ApplicationHidden" { Write-Log -Message "Toast Notification action [$_], the Toast Notification has been hidden by the application." -Severity 2 -Source ${CmdletName} }
			"Click" { Write-Log -Message "Toast Notification action [$_], the user has clicked the Toast Notification body." -Severity 2 -Source ${CmdletName} }
			"TimedOut" { Write-Log -Message "Toast Notification action [$_], the Toast Notification has timed out." -Severity 2 -Source ${CmdletName} }
			"UserCanceled" {
				Write-Log -Message "Toast Notification action [$_], the user has closed the Toast Notification." -Severity 2 -Source ${CmdletName}

				if ($ToastNotificationGroup -eq "WelcomePrompt") {
					if (-not $persistPrompt) {
						Write-Log -Message "Try using '-PersistPrompt' to avoid this behaviour, exiting function with 'Timeout'." -Severity 2 -Source ${CmdletName}
						$Result = "Timeout"
						break
					}
				}
			}

			#  Update Toast Notification remaining time data
			{ $ToastNotificationVisible } {
				if ($ToastNotificationGroup -eq "WelcomePrompt") {
					#  Dynamically update the Toast Notification running applications list
					if ($configInstallationWelcomePromptDynamicRunningProcessEvaluation) {
						Invoke-Command -ScriptBlock $ReevaluateRunningProcesses -NoNewScope
					}
				}

				#  Update Toast Notification remaining time data
				Invoke-Command -ScriptBlock $UpdateToastNotificationData -NoNewScope
			}

			# Re-construct and re-show the Toast Notification
			{ -not [string]::IsNullOrWhiteSpace($_) -or -not $ToastNotificationVisible } {
				if ($ToastNotificationGroup -eq "WelcomePrompt") {
					if ($persistPrompt -or $_ -in ("ApplicationHidden", "Click", "TimedOut")) {
						Write-Log -Message "The Toast Notification has been closed, it will be shown again." -Severity 2 -Source ${CmdletName}
						Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
					}
				}
				elseif ($ToastNotificationGroup -eq "InstallationRestartPrompt") {
					Write-Log -Message "The Toast Notification has been closed, it will be shown again in [$configInstallationRestartPersistInterval] seconds." -Severity 2 -Source ${CmdletName}

					# Wait the default time for reshowing the restart prompt
					Start-Sleep -Seconds $configInstallationRestartPersistInterval

					Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
				}
				elseif ($ToastNotificationGroup -eq "InstallationPrompt") {
					if ($deployAppScriptFriendlyName) {
						Write-Log -Message "The Toast Notification has been closed, it will be shown again." -Severity 2 -Source ${CmdletName}
						Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
					}
				}
				else {
					Write-Log -Message "The Toast Notification has been closed, it will be shown again." -Severity 2 -Source ${CmdletName}
					Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
				}

				break
			}

			#  Wait a few seconds before reevaluate result
			{ [string]::IsNullOrWhiteSpace($_) } {
				Start-Sleep -Seconds $configFunctionOptions.UpdateInterval
			}
		}
	}
	while ($ToastNotificationVisible)
}
#endregion

#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

#region Function New-DynamicFunction
Function New-DynamicFunction {
	<#
	.SYNOPSIS
		Defines a new function with the given name, scope and content given.
	.DESCRIPTION
		Defines a new function with the given name, scope and content given.
	.PARAMETER Name
		Function name.
	.PARAMETER Scope
		Scope where the function will be created.
	.PARAMETER Value
		Logic of the function.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to create new function. Default: $false.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		New-DynamicFunction -Name 'Exit-ScriptOriginal' -Scope 'Script' -Value ${Function:Exit-Script}
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[ValidateSet("Global", "Local", "Script")]
		[string]$Scope,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[string]$Value,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		try {
			$null = New-Item -Path function: -Name "$($Scope):$($Name)" -Value $Value -Force

			if ($?) {
				Write-Log -Message "Successfully created function [$Name] in scope [$Scope]." -Source ${CmdletName} -DebugMessage
			}
		}
		catch {
			Write-Log -Message "Failed when trying to create new function [$Name] in scope [$Scope].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				throw "Failed when trying to create new function [$Name] in scope [$Scope]: $($_.Exception.Message)"
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Rename Original Functions
#  Called now, before functions subsitution
$FunctionsToRename | ForEach-Object { New-DynamicFunction -Name $_.Name -Scope $_.Scope -Value $_.Value }
#endregion


#region Function Get-RunningProcesses
Function Get-RunningProcesses {
	<#
	.SYNOPSIS
		Gets the processes that are running from a custom list of process objects and also adds a property called ProcessDescription.
	.DESCRIPTION
		Gets the processes that are running from a custom list of process objects and also adds a property called ProcessDescription.
	.PARAMETER ProcessObjects
		Custom object containing the process objects to search for. If not supplied, the function just returns $null. ProcessObjects alias for backward compatibility.
	.PARAMETER DisableFunctionLogging
		Disables function logging. DisableLogging alias for backward compatibility.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		[PSCustomObject[]]
		Returns an array of objects with the running processes and their description, path and company.
	.EXAMPLE
		Get-RunningProcesses -ProcessObjects $ProcessObjects
	.NOTES
		This is an internal script function and should typically not be called directly.
		Added support to wildcards, title and path searching.
		Modified to display more properties used by notifications.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[Alias("ProcessObjects")]
		[PSCustomObject[]]$SearchObjects,
		[Parameter(Mandatory = $false)]
		[Alias("DisableLogging")]
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		if ($SearchObjects -and $SearchObjects[0].ProcessName) {
			if (-not($DisableFunctionLogging)) { Write-Log -Message "Checking for running applications: [$($SearchObjects.ProcessName -join ', ')]" -Source ${CmdletName} }

			## Prepare a filter for Where-Object
			[scriptblock]$whereObjectFilter = {
				foreach ($SearchObject in $SearchObjects) {
					if ($SearchObject.ProcessName -match "(?<=title:).+") {
						## Logic to use when the 'title:...' is used
						if ([string]::IsNullOrWhiteSpace($_.MainWindowTitle)) { continue }

						[string]$MainWindowTitleSearched = $null
						$ExecutionContext.InvokeCommand.ExpandString($SearchObject.ProcessName) | Select-String -Pattern $ProcessObjectsTitlePathRegExPattern -AllMatches | ForEach-Object { if ([string]::IsNullOrWhiteSpace($MainWindowTitleSearched)) { $MainWindowTitleSearched = $_.matches.value } }

						if ([string]::IsNullOrWhiteSpace($MainWindowTitleSearched)) { continue }
						elseif ($_.MainWindowTitle -like $MainWindowTitleSearched) {
							#  Use the internal process description if not null or empty
							if (-not [string]::IsNullOrWhiteSpace($_.Description)) { $processDescription = $_.Description }
							#  Fall back on the process name if no description is provided by the process
							else { $processDescription = $_.ProcessName }

							if ([IO.Path]::GetFileNameWithoutExtension($_.ProcessName) -in $configToastNotificationGeneralOptions.CriticalProcesses_NeverKill) {
								Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] but it is tagged as critical and its termination could compromise system stability, it will be skipped." -Severity 2 -Source ${CmdletName}
							}
							else {
								if (-not($DisableFunctionLogging)) { Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] and will be added to the close app collection." -Source ${CmdletName} }

								#  Adds the new detected process if not already in the list
								if ($_.ProcessName -notin $SearchObjects.ProcessName) {
									$Script:ProcessObjects += [PSCustomObject]@{
										ProcessName        = $_.ProcessName
										ProcessDescription = $processDescription
									}
								}

								Add-Member -InputObject $_ -MemberType NoteProperty -Name "ProcessDescription" -Value $processDescription -Force -PassThru -ErrorAction SilentlyContinue
								return $true
							}
						}
					}
					elseif ($SearchObject.ProcessName -match "(?<=path:).+") {
						## Logic to use when the 'path:...' is used
						if ([string]::IsNullOrWhiteSpace($_.Path)) { continue }

						[string]$PathSearched = $null
						$ExecutionContext.InvokeCommand.ExpandString($SearchObject.ProcessName) | Select-String -Pattern $ProcessObjectsTitlePathRegExPattern -AllMatches | ForEach-Object { if ([string]::IsNullOrWhiteSpace($PathSearched)) { $PathSearched = $_.matches.value } }

						if ([string]::IsNullOrWhiteSpace($PathSearched)) { continue }
						elseif ($_.Path -like $PathSearched) {
							#  Use the internal process description if not null or empty
							if (-not [string]::IsNullOrWhiteSpace($_.Description)) { $processDescription = $_.Description }
							#  Fall back on the process name if no description is provided by the process
							else { $processDescription = $_.ProcessName }

							if ([IO.Path]::GetFileNameWithoutExtension($_.ProcessName) -in $configToastNotificationGeneralOptions.CriticalProcesses_NeverKill) {
								Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] but it is tagged as critical and its termination could compromise system stability, it will be skipped." -Severity 2 -Source ${CmdletName}
							}
							else {
								if (-not($DisableFunctionLogging)) { Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] and will be added to the close app collection." -Source ${CmdletName} }

								#  Adds the new detected process if not already in the list
								if ($_.ProcessName -notin $SearchObjects.ProcessName) {
									$Script:ProcessObjects += [PSCustomObject]@{
										ProcessName        = $_.ProcessName
										ProcessDescription = $processDescription
									}
								}

								Add-Member -InputObject $_ -MemberType NoteProperty -Name "ProcessDescription" -Value $processDescription -Force -PassThru -ErrorAction SilentlyContinue
								return $true
							}
						}
					}
					elseif ($_.ProcessName -eq $SearchObject.ProcessName) {
						## Logic to use when exact match

						#  The description of the process provided as a Parameter to the function, e.g. -ProcessName "winword=Microsoft Office Word".
						if ($SearchObject.ProcessDescription) { $processDescription = $SearchObject.ProcessDescription }
						#  Use the internal process description if not null or empty
						elseif (-not [string]::IsNullOrWhiteSpace($_.Description)) { $processDescription = $_.Description }
						#  Fall back on the process name if no description is provided by the process or as a parameter to the function
						else { $processDescription = $_.ProcessName }

						Add-Member -InputObject $_ -MemberType NoteProperty -Name "ProcessDescription" -Value $processDescription -Force -PassThru -ErrorAction SilentlyContinue
						return $true
					}
					elseif ($_.ProcessName -like $SearchObject.ProcessName) {
						## Logic to use when matched with wildcards

						#  The description of the process provided as a Parameter to the function, e.g. -ProcessName "winword=Microsoft Office Word".
						if ($SearchObject.ProcessDescription) { $processDescription = $SearchObject.ProcessDescription }
						#  Use the internal process description if not null or empty
						elseif (-not [string]::IsNullOrWhiteSpace($_.Description)) { $processDescription = $_.Description }
						#  Fall back on the process name if no description is provided by the process or as a parameter to the function
						else { $processDescription = $_.ProcessName }

						if ([IO.Path]::GetFileNameWithoutExtension($_.ProcessName) -in $configToastNotificationGeneralOptions.CriticalProcesses_NeverKill) {
							Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] but it is tagged as critical and its termination could compromise system stability, it will be skipped." -Severity 2 -Source ${CmdletName}
						}
						else {
							if (-not($DisableFunctionLogging)) { Write-Log -Message "The process [$([IO.Path]::GetFileNameWithoutExtension($_.ProcessName))] corresponding to application [$($processDescription)] matchs the pattern [$($SearchObject.ProcessName)] and will be added to the close app collection." -Source ${CmdletName} }

							#  Adds the new detected process if not already in the list
							if ($_.ProcessName -notin $SearchObjects.ProcessName) {
								$Script:ProcessObjects += [PSCustomObject]@{
									ProcessName        = $_.ProcessName
									ProcessDescription = $processDescription
								}
							}

							Add-Member -InputObject $_ -MemberType NoteProperty -Name "ProcessDescription" -Value $processDescription -Force -PassThru -ErrorAction SilentlyContinue
							return $true
						}
					}
				}
				return $false
			}

			## Get all running processes. Match against the process names to search for to find running processes.
			[System.Diagnostics.Process[]]$runningProcesses = Get-Process | Where-Object -FilterScript $whereObjectFilter | Sort-Object ProcessName

			if ($runningProcesses) {
				## Select the process with visible windows or full path if they are repeated
				$groupedProcesses = $runningProcesses | Group-Object -Property ProcessName | Where-Object { $_.Count -gt 1 } | Sort-Object Name
				foreach ($groupedProcess in $groupedProcesses) {
					#  Remove repeated processes
					$runningProcesses = $runningProcesses | Where-Object { $_.ProcessName -ne $groupedProcess.Name }

					#  Select the process
					$selectedProcess = $groupedProcess.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) } | Select-Object -First 1
					if ($null -eq $selectedProcess) { $selectedProcess = $groupedProcess.Group | Sort-Object Path -Descending | Select-Object -First 1 }

					#  Add selected process from grouped
					$runningProcesses += $selectedProcess
				}

				if (-not($DisableFunctionLogging)) { Write-Log -Message "The following processes are running: [$($runningProcesses.ProcessName -join ', ')]." -Source ${CmdletName} }
				return $runningProcesses
			}
			else {
				if (-not($DisableFunctionLogging)) { Write-Log -Message "Specified applications are not running." -Source ${CmdletName} }
				return $null
			}
		}
		else {
			return $null
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-InstallationWelcome
Function Show-InstallationWelcome {
	<#
	.SYNOPSIS
		Show a welcome dialog prompting the user with information about the installation and actions to be performed before the installation can begin.
	.DESCRIPTION
		The following prompts can be included in the welcome dialog:
		 a) Close the specified running applications, or optionally close the applications without showing a prompt (using the -Silent switch).
		 b) Defer the installation a certain number of times, for a certain number of days or until a deadline is reached.
		 c) Countdown until applications are automatically closed.
		 d) Prevent users from launching the specified applications while the installation is in progress.
		Notes:
		 The process descriptions are retrieved from WMI, with a fall back on the process name if no description is available. Alternatively, you can specify the description yourself with a '=' symbol - see examples.
		 The dialog box will timeout after the timeout specified in the XML configuration file (default 1 hour and 55 minutes) to prevent SCCM installations from timing out and returning a failure code to SCCM. When the dialog times out, the script will exit and return a 1618 code (SCCM fast retry code).
	.PARAMETER CloseApps
		Name of the process to stop (do not include the .exe). Specify multiple processes separated by a comma. Specify custom descriptions like this: "winword=Microsoft Office Word,excel=Microsoft Office Excel"
	.PARAMETER Silent
		Stop processes without prompting the user.
	.PARAMETER CloseAppsCountdown
		Option to provide a countdown in seconds until the specified applications are automatically closed. This only takes effect if deferral is not allowed or has expired.
	.PARAMETER ForceCloseAppsCountdown
		Option to provide a countdown in seconds until the specified applications are automatically closed regardless of whether deferral is allowed.
	.PARAMETER PromptToSave
		Specify whether to prompt to save working documents when the user chooses to close applications by selecting the "Close Programs" button. Option does not work in SYSTEM context unless toolkit launched with "psexec.exe -s -i" to run it as an interactive process under the SYSTEM account.
	.PARAMETER PersistPrompt
		Specify whether to make the Show-InstallationWelcome prompt persist in the center of the screen every couple of seconds, specified in the AppDeployToolkitConfig.xml. The user will have no option but to respond to the prompt. This only takes effect if deferral is not allowed or has expired.
	.PARAMETER BlockExecution
		Option to prevent the user from launching processes/applications, specified in -CloseApps, during the installation.
	.PARAMETER AllowDefer
		Enables an optional defer button to allow the user to defer the installation.
	.PARAMETER AllowDeferCloseApps
		Enables an optional defer button to allow the user to defer the installation only if there are running applications that need to be closed. This parameter automatically enables -AllowDefer
	.PARAMETER DeferTimes
		Specify the number of times the installation can be deferred.
	.PARAMETER DeferDays
		Specify the number of days since first run that the installation can be deferred. This is converted to a deadline.
	.PARAMETER DeferDeadline
		Specify the deadline date until which the installation can be deferred.
		Specify the date in the local culture if the script is intended for that same culture.
		If the script is intended to run on EN-US machines, specify the date in the format: "08/25/2013" or "08-25-2013" or "08-25-2013 18:00:00"
		If the script is intended for multiple cultures, specify the date in the universal sortable date/time format: "2013-08-22 11:51:52Z"
		The deadline date will be displayed to the user in the format of their culture.
	.PARAMETER CheckDiskSpace
		Specify whether to check if there is enough disk space for the installation to proceed.
		If this parameter is specified without the RequiredDiskSpace parameter, the required disk space is calculated automatically based on the size of the script source and associated files.
	.PARAMETER RequiredDiskSpace
		Specify required disk space in MB, used in combination with CheckDiskSpace.
	.PARAMETER MinimizeWindows
		Specifies whether to minimize other windows when displaying prompt. Default: $true.
	.PARAMETER TopMost
		Specifies whether the windows is the topmost window. Default: $true.
	.PARAMETER ForceCountdown
		Specify a countdown to display before automatically proceeding with the installation when a deferral is enabled.
	.PARAMETER CustomText
		Specify whether to display a custom message specified in the XML file. Custom message must be populated for each language section in the XML.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'iexplore,winword,excel'
		Prompt the user to close Internet Explorer, Word and Excel.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'winword,excel' -Silent
		Close Word and Excel without prompting the user.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'winword,excel' -BlockExecution
		Close Word and Excel and prevent the user from launching the applications while the installation is in progress.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'winword=Microsoft Office Word,excel=Microsoft Office Excel' -CloseAppsCountdown 600
		Prompt the user to close Word and Excel, with customized descriptions for the applications and automatically close the applications after 10 minutes.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'winword,msaccess,excel' -PersistPrompt
		Prompt the user to close Word, MSAccess and Excel.
		By using the PersistPrompt switch, the dialog will return to the center of the screen every couple of seconds, specified in the AppDeployToolkitConfig.xml, so the user cannot ignore it by dragging it aside.
	.EXAMPLE
		Show-InstallationWelcome -AllowDefer -DeferDeadline '25/08/2013'
		Allow the user to defer the installation until the deadline is reached.
	.EXAMPLE
		Show-InstallationWelcome -CloseApps 'winword,excel' -BlockExecution -AllowDefer -DeferTimes 10 -DeferDeadline '25/08/2013' -CloseAppsCountdown 600
		Close Word and Excel and prevent the user from launching the applications while the installation is in progress.
		Allow the user to defer the installation a maximum of 10 times or until the deadline is reached, whichever happens first.
		When deferral expires, prompt the user to close the applications and automatically close them after 10 minutes.
	.NOTES
		Modified to use new Get-RunningProcesses returned object.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding(DefaultParametersetName = "None")]

	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$CloseApps,
		[switch]$Silent,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$CloseAppsCountdown = 0,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$ForceCloseAppsCountdown = 0,
		[switch]$PromptToSave,
		[switch]$PersistPrompt,
		[switch]$BlockExecution,
		[switch]$AllowDefer,
		[switch]$AllowDeferCloseApps,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$DeferTimes = 0,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$DeferDays = 0,
		[Parameter(Mandatory = $false)]
		[string]$DeferDeadline = "",
		[Parameter(ParameterSetName = "CheckDiskSpaceParameterSet", Mandatory = $true)]
		[ValidateScript({ $_.IsPresent -eq ($true -or $false) })]
		[switch]$CheckDiskSpace,
		[Parameter(ParameterSetName = "CheckDiskSpaceParameterSet", Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$RequiredDiskSpace = 0,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$MinimizeWindows = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$TopMost = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$ForceCountdown = 0,
		[switch]$CustomText
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## If running in NonInteractive mode, force the processes to close silently
		if ($deployModeNonInteractive) {
			$Silent = $true
		}

		## If using Zero-Config MSI Deployment, append any executables found in the MSI to the CloseApps list
		if ($useDefaultMsi) {
			$CloseApps = "$CloseApps,$defaultMsiExecutablesList"
		}

		## Check disk space requirements if specified
		if ($CheckDiskSpace) {
			Write-Log -Message "Evaluating disk space requirements." -Source ${CmdletName}
			[Double]$freeDiskSpace = Get-FreeDiskSpace
			if ($RequiredDiskSpace -eq 0) {
				try {
					#  Determine the size of the Files folder
					$fso = New-Object -ComObject "Scripting.FileSystemObject" -ErrorAction Stop
					$RequiredDiskSpace = [Math]::Round((($fso.GetFolder($scriptParentPath).Size) / 1MB))
				}
				catch {
					Write-Log -Message "Failed to calculate disk space requirement from source files.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				}
				finally {
					try {
						$null = [Runtime.Interopservices.Marshal]::ReleaseComObject($fso)
					}
					catch {}
				}
			}
			if ($freeDiskSpace -lt $RequiredDiskSpace) {
				Write-Log -Message "Failed to meet minimum disk space requirement. Space Required [$RequiredDiskSpace MB], Space Available [$freeDiskSpace MB]." -Severity 3 -Source ${CmdletName}
				if (-not $Silent) {
					Show-InstallationPrompt -Message ($configDiskSpaceMessage -f $installTitle, $RequiredDiskSpace, ($freeDiskSpace)) -ButtonRightText "OK" -Icon Error
				}
				Exit-Script -ExitCode $configInstallationUIExitCode
			}
			else {
				Write-Log -Message "Successfully passed minimum disk space requirement check." -Source ${CmdletName}
			}
		}

		## Create a Process object with custom descriptions where they are provided (split on an '=' sign)
		if ($CloseApps) {
			$Script:ProcessObjects = @()
			#  Split multiple processes on a comma skipping empty ones
			[array]$CloseAppsArray = $CloseApps.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
			#  Split multiple processes on equal sign, then create custom object with process name and description
			foreach ($AppToClose in $CloseAppsArray) {
				if ($AppToClose -match $ProcessObjectsTitlePathRegExPattern) {
					$Script:ProcessObjects += [PSCustomObject]@{
						ProcessName        = $AppToClose
						ProcessDescription = $null
					}
				}
				elseif ($AppToClose.Contains("=")) {
					[array]$ProcessSplit = $AppToClose.Split("=")

					#  Trim any space
					$ProcessSplit[0] = ($ProcessSplit[0]).Trim()
					if ($null -ne $ProcessSplit[1]) {
						$ProcessSplit[1] = ($ProcessSplit[1..$($ProcessSplit.Count - 1)] -join "=").Trim()
					}

					if ($ProcessSplit[0] -match $ProcessObjectsWildCardRegExPattern) {
						$Script:ProcessObjects += [PSCustomObject]@{
							ProcessName        = $ProcessSplit[0]
							ProcessDescription = $ProcessSplit[1]
						}
					}
					else {
						$ProcessSplit[0] = [IO.Path]::GetFileNameWithoutExtension($ProcessSplit[0])
						if ($ProcessSplit[0] -notin $configToastNotificationGeneralOptions.CriticalProcesses_NeverKill) {
							if ($configToastNotificationGeneralOptions.InstallationWelcome_AlwaysParseMuiCacheAppName) {
								$ProcessInfo = Get-ApplicationMuiCache -ProcessName $ProcessSplit[0]
								$Script:ProcessObjects += [PSCustomObject]@{
									ProcessName        = $ProcessInfo.ProcessName
									ProcessDescription = Invoke-Expression -Command 'try { if (-not [string]::IsNullOrWhiteSpace($ProcessInfo.FriendlyAppName)) { $ProcessInfo.FriendlyAppName } else { $ProcessSplit[1] } } catch { $ProcessSplit[1] }'
								}
							}
							else {
								$Script:ProcessObjects += [PSCustomObject]@{
									ProcessName        = $ProcessSplit[0]
									ProcessDescription = $ProcessSplit[1]
								}
							}
						}
						else {
							$ProcessInfo = Get-ApplicationMuiCache -ProcessName $ProcessSplit[0]
							Write-Log -Message "The process [$($ProcessInfo.ProcessName)] with given description [$($ProcessSplit[1])] corresponding to application [$($ProcessInfo.FriendlyAppName)] is tagged as critical and its termination could compromise system stability, it will be skipped." -Severity 2 -Source ${CmdletName}
						}
					}
				}
				elseif ($AppToClose -match $ProcessObjectsWildCardRegExPattern) {
					$Script:ProcessObjects += [PSCustomObject]@{
						ProcessName        = $AppToClose
						ProcessDescription = $null
					}
				}
				elseif ([IO.Path]::GetFileNameWithoutExtension($AppToClose) -in $configToastNotificationGeneralOptions.CriticalProcesses_NeverKill) {
					$ProcessInfo = Get-ApplicationMuiCache -ProcessName $AppToClose
					Write-Log -Message "The process [$($ProcessInfo.ProcessName)] corresponding to application [$($ProcessInfo.FriendlyAppName)] is tagged as critical and its termination could compromise system stability, it will be skipped." -Severity 2 -Source ${CmdletName}
				}
				else {
					$ProcessInfo = Get-ApplicationMuiCache -ProcessName $AppToClose
					$Script:ProcessObjects += [PSCustomObject]@{
						ProcessName        = $ProcessInfo.ProcessName
						ProcessDescription = $ProcessInfo.FriendlyAppName
					}
				}
			}
		}

		## Check Deferral history and calculate remaining deferrals
		if (($allowDefer) -or ($AllowDeferCloseApps)) {
			#  Set $allowDefer to true if $AllowDeferCloseApps is true
			$allowDefer = $true

			#  Get the deferral history from the registry
			$deferHistory = Get-DeferHistory
			$deferHistoryTimes = $deferHistory | Select-Object -ExpandProperty "DeferTimesRemaining" -ErrorAction SilentlyContinue
			$deferHistoryDeadline = $deferHistory | Select-Object -ExpandProperty "DeferDeadline" -ErrorAction SilentlyContinue

			#  Reset Switches
			$checkDeferDays = $false
			$checkDeferDeadline = $false
			if ($DeferDays -ne 0) {
				$checkDeferDays = $true
			}
			if ($DeferDeadline) {
				$checkDeferDeadline = $true
			}
			if ($DeferTimes -ne 0) {
				if ($deferHistoryTimes -ge 0) {
					Write-Log -Message "Defer history shows [$($deferHistory.DeferTimesRemaining)] deferrals remaining." -Source ${CmdletName}
					$DeferTimes = $deferHistory.DeferTimesRemaining - 1
				}
				else {
					Write-Log -Message "The user has [$deferTimes] deferrals remaining." -Source ${CmdletName}
					$DeferTimes = $DeferTimes - 1
				}
				if ($DeferTimes -lt 0) {
					Write-Log -Message "Deferral has expired." -Source ${CmdletName}
					$AllowDefer = $false
				}
			}
			else {
				if (Test-Path -LiteralPath "variable:deferTimes") {
					Remove-Variable -Name "deferTimes"
				}
				$DeferTimes = $null
			}
			if ($checkDeferDays -and $allowDefer) {
				if ($deferHistoryDeadline) {
					Write-Log -Message "Defer history shows a deadline date of [$deferHistoryDeadline]." -Source ${CmdletName}
					[String]$deferDeadlineUniversal = Get-UniversalDate -DateTime $deferHistoryDeadline
				}
				else {
					[String]$deferDeadlineUniversal = Get-UniversalDate -DateTime (Get-Date -Date ((Get-Date).AddDays($deferDays)) -Format ($culture).DateTimeFormat.UniversalDateTimePattern).ToString()
				}
				Write-Log -Message "The user has until [$deferDeadlineUniversal] before deferral expires." -Source ${CmdletName}
				if ((Get-UniversalDate) -gt $deferDeadlineUniversal) {
					Write-Log -Message "Deferral has expired." -Source ${CmdletName}
					$AllowDefer = $false
				}
			}
			if ($checkDeferDeadline -and $allowDefer) {
				#  Validate Date
				try {
					[String]$deferDeadlineUniversal = Get-UniversalDate -DateTime $deferDeadline -ErrorAction Stop
				}
				catch {
					Write-Log -Message "Date is not in the correct format for the current culture. Type the date in the current locale format, such as 20/08/2014 (Europe) or 08/20/2014 (United States). If the script is intended for multiple cultures, specify the date in the universal sortable date/time format, e.g. '2013-08-22 11:51:52Z'.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					throw "Date is not in the correct format for the current culture. Type the date in the current locale format, such as 20/08/2014 (Europe) or 08/20/2014 (United States). If the script is intended for multiple cultures, specify the date in the universal sortable date/time format, e.g. '2013-08-22 11:51:52Z': $($_.Exception.Message)"
				}
				Write-Log -Message "The user has until [$deferDeadlineUniversal] remaining." -Source ${CmdletName}
				if ((Get-UniversalDate) -gt $deferDeadlineUniversal) {
					Write-Log -Message "Deferral has expired." -Source ${CmdletName}
					$AllowDefer = $false
				}
			}
		}
		if (($deferTimes -lt 0) -and (-not $deferDeadlineUniversal)) {
			$AllowDefer = $false
		}

		## Prompt the user to close running applications and optionally defer if enabled
		if (-not ($deployModeSilent) -and (-not ($silent))) {
			if ($forceCloseAppsCountdown -gt 0) {
				#  Keep the same variable for countdown to simplify the code:
				$closeAppsCountdown = $forceCloseAppsCountdown
				#  Change this variable to a boolean now to switch the countdown on even with deferral
				[boolean]$forceCloseAppsCountdown = $true
			}
			elseif ($forceCountdown -gt 0) {
				#  Keep the same variable for countdown to simplify the code:
				$closeAppsCountdown = $forceCountdown
				#  Change this variable to a boolean now to switch the countdown on
				[boolean]$forceCountdown = $true
			}
			Set-Variable -Name "closeAppsCountdownGlobal" -Value $closeAppsCountdown -Scope Script

			while ((Get-RunningProcesses -ProcessObjects $ProcessObjects -OutVariable "runningProcesses") -or (($promptResult -ne "Defer") -and ($promptResult -ne "Close"))) {
				#  Check if we need to prompt the user to defer, to defer and close apps, or not to prompt them at all
				if ($allowDefer) {
					#  If there is deferral and closing apps is allowed but there are no apps to be closed, break the while loop
					if ($AllowDeferCloseApps -and (-not $runningProcesses)) {
						break
					}
					#  Otherwise, as long as the user has not selected to close the apps or the processes are still running and the user has not selected to continue, prompt user to close running processes with deferral
					elseif (($promptResult -ne "Close") -or (($runningProcesses) -and ($promptResult -ne "Continue"))) {
						[string]$promptResult = Show-WelcomePrompt -ProcessDescriptions $runningProcesses -CloseAppsCountdown $closeAppsCountdownGlobal -ForceCloseAppsCountdown $forceCloseAppsCountdown -ForceCountdown $forceCountdown -PersistPrompt $PersistPrompt -AllowDefer -DeferTimes $deferTimes -DeferDeadline $deferDeadlineUniversal -MinimizeWindows $MinimizeWindows -CustomText:$CustomText -TopMost $TopMost
					}
				}
				#  If there is no deferral and processes are running, prompt the user to close running processes with no deferral option
				elseif (($runningProcesses) -or ($forceCountdown)) {
					[string]$promptResult = Show-WelcomePrompt -ProcessDescriptions $runningProcesses -CloseAppsCountdown $closeAppsCountdownGlobal -ForceCloseAppsCountdown $forceCloseAppsCountdown -ForceCountdown $forceCountdown -PersistPrompt $PersistPrompt -MinimizeWindows $minimizeWindows -CustomText:$CustomText -TopMost $TopMost
				}
				#  If there is no deferral and no processes running, break the while loop
				else {
					break
				}

				#  If the user has clicked OK, wait a few seconds for the process to terminate before evaluating the running processes again
				if ($promptResult -eq "Continue") {
					Write-Log -Message "The user selected to continue..." -Source ${CmdletName}
					Start-Sleep -Seconds 2

					#  Break the while loop if there are no processes to close and the user has clicked OK to continue
					if (-not $runningProcesses) {
						break
					}
				}
				#  Force the applications to close
				elseif ($promptResult -eq "Close") {
					Write-Log -Message "The user selected to force the application(s) to close..." -Source ${CmdletName}
					if (($PromptToSave) -and ($SessionZero -and (-not $IsProcessUserInteractive))) {
						Write-Log -Message "Specified [-PromptToSave] option will not be available, because current process is running in session zero and is not interactive." -Severity 2 -Source ${CmdletName}
					}
					#  Update the process list right before closing, in case it changed
					$runningProcesses = Get-RunningProcesses -ProcessObjects ($ProcessObjects | Where-Object { $_.ProcessName -notmatch $ProcessObjectsWildCardRegExPattern } | Where-Object { $_.ProcessName -notmatch $ProcessObjectsTitlePathRegExPattern })

					#  Close running processes
					foreach ($runningProcess in $runningProcesses) {
						[psobject[]]$AllOpenWindowsForRunningProcess = Get-WindowTitle -GetAllWindowTitles -DisableFunctionLogging | Where-Object { $_.ParentProcess -eq $runningProcess.ProcessName }
						#  If the PromptToSave parameter was specified and the process has a window open, then prompt the user to save work if there is work to be saved when closing window
						if (($PromptToSave) -and (-not ($SessionZero -and (-not $IsProcessUserInteractive))) -and ($AllOpenWindowsForRunningProcess) -and ($runningProcess.MainWindowHandle -ne [IntPtr]::Zero)) {
							[timespan]$PromptToSaveTimeout = New-TimeSpan -Seconds $configInstallationPromptToSave
							[Diagnostics.StopWatch]$PromptToSaveStopWatch = [Diagnostics.StopWatch]::StartNew()
							$PromptToSaveStopWatch.Reset()
							foreach ($OpenWindow in $AllOpenWindowsForRunningProcess) {
								try {
									Write-Log -Message "Stopping process [$($runningProcess.ProcessName)] with window title [$($OpenWindow.WindowTitle)] and prompt to save if there is work to be saved (timeout in [$configInstallationPromptToSave] seconds)..." -Source ${CmdletName}
									[boolean]$IsBringWindowToFrontSuccess = [PSADT.UiAutomation]::BringWindowToFront($OpenWindow.WindowHandle)
									[boolean]$IsCloseWindowCallSuccess = $runningProcess.CloseMainWindow()
									if (-not $IsCloseWindowCallSuccess) {
										Write-Log -Message "Failed to call the CloseMainWindow() method on process [$($runningProcess.ProcessName)] with window title [$($OpenWindow.WindowTitle)] because the main window may be disabled due to a modal dialog being shown." -Severity 3 -Source ${CmdletName}
									}
									else {
										$PromptToSaveStopWatch.Start()
										do {
											[boolean]$IsWindowOpen = [boolean](Get-WindowTitle -GetAllWindowTitles -DisableFunctionLogging | Where-Object { $_.WindowHandle -eq $OpenWindow.WindowHandle })
											if (-not $IsWindowOpen) { break }
											Start-Sleep -Seconds 3
										} while (($IsWindowOpen) -and ($PromptToSaveStopWatch.Elapsed -lt $PromptToSaveTimeout))
										$PromptToSaveStopWatch.Reset()
										if ($IsWindowOpen) {
											Write-Log -Message "Exceeded the [$configInstallationPromptToSave] seconds timeout value for the user to save work associated with process [$($runningProcess.ProcessName)] with window title [$($OpenWindow.WindowTitle)]." -Severity 2 -Source ${CmdletName}
										}
										else {
											Write-Log -Message "Window [$($OpenWindow.WindowTitle)] for process [$($runningProcess.ProcessName)] was successfully closed." -Source ${CmdletName}
										}
									}
								}
								catch {
									Write-Log -Message "Failed to close window [$($OpenWindow.WindowTitle)] for process [$($runningProcess.ProcessName)].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
									continue
								}
								finally {
									$runningProcess.Refresh()
								}
							}
						}
						else {
							Write-Log -Message "Stopping process $($runningProcess.ProcessName)..." -Source ${CmdletName}
							Stop-Process -Name $runningProcess.ProcessName -Force -ErrorAction SilentlyContinue
						}
					}

					if ($runningProcesses = Get-RunningProcesses -ProcessObjects ($ProcessObjects | Where-Object { $_.ProcessName -notmatch $ProcessObjectsWildCardRegExPattern } | Where-Object { $_.ProcessName -notmatch $ProcessObjectsTitlePathRegExPattern }) -DisableLogging) {
						#  Apps are still running, give them 2s to close. If they are still running, the Welcome Window will be displayed again
						Write-Log -Message "Sleeping for 2 seconds because the processes are still not closed..." -Source ${CmdletName}
						Start-Sleep -Seconds 2
					}
				}
				#  Stop the script (if not actioned before the timeout value)
				elseif ($promptResult -eq "Timeout") {
					Write-Log -Message "Installation not actioned before the timeout value." -Source ${CmdletName}
					$BlockExecution = $false

					if (($deferTimes -ge 0) -or ($deferDeadlineUniversal)) {
						Set-DeferHistory -DeferTimesRemaining $DeferTimes -DeferDeadline $deferDeadlineUniversal
					}
					## Dispose the welcome prompt timer here because if we dispose it within the Show-WelcomePrompt function we risk resetting the timer and missing the specified timeout period
					if ($script:welcomeTimer) {
						try {
							$script:welcomeTimer.Dispose()
							$script:welcomeTimer = $null
						}
						catch { }
					}

					#  Restore minimized windows
					$null = $shellApp.UndoMinimizeAll()

					Exit-Script -ExitCode $configInstallationUIExitCode
				}
				#  Stop the script (user chose to defer)
				elseif ($promptResult -eq "Defer") {
					Write-Log -Message "Installation deferred by the user." -Source ${CmdletName}
					$BlockExecution = $false

					Set-DeferHistory -DeferTimesRemaining $DeferTimes -DeferDeadline $deferDeadlineUniversal

					#  Restore minimized windows
					$null = $shellApp.UndoMinimizeAll()

					Exit-Script -ExitCode $configInstallationDeferExitCode
				}
			}
		}

		## Force the processes to close silently, without prompting the user
		if (($Silent -or $deployModeSilent) -and $CloseApps) {
			[array]$runningProcesses = $null
			[array]$runningProcesses = Get-RunningProcesses -ProcessObjects ($ProcessObjects | Where-Object { $_.ProcessName -notmatch $ProcessObjectsWildCardRegExPattern } | Where-Object { $_.ProcessName -notmatch $ProcessObjectsTitlePathRegExPattern })
			if ($runningProcesses) {
				Write-Log -Message "Force closing application(s) [$(($runningProcesses.ProcessDescription | Sort-Object -Unique) -join ', ')] without prompting user." -Source ${CmdletName}
				$runningProcesses.ProcessName | ForEach-Object -Process { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
				Start-Sleep -Seconds 2
			}
		}

		## Force nsd.exe to stop if Notes is one of the required applications to close
		if (($ProcessObjects | Select-Object -ExpandProperty "ProcessName") -contains "notes") {
			## Get the path where Notes is installed
			[String]$notesPath = Get-Item -LiteralPath $regKeyLotusNotes -ErrorAction SilentlyContinue | Get-ItemProperty | Select-Object -ExpandProperty "Path"

			## Ensure we aren't running as a Local System Account and Notes install directory was found
			if ((-not $IsLocalSystemAccount) -and ($notesPath)) {
				#  Get a list of all the executables in the Notes folder
				[string[]]$notesPathExes = Get-ChildItem -LiteralPath $notesPath -Filter "*.exe" -Recurse | Select-Object -ExpandProperty "BaseName" | Sort-Object
				## Check for running Notes executables and run NSD if any are found
				$notesPathExes | ForEach-Object {
					if ((Get-Process | Select-Object -ExpandProperty "Name") -contains $_) {
						[String]$notesNSDExecutable = Join-Path -Path $notesPath -ChildPath "NSD.exe"
						try {
							if (Test-Path -LiteralPath $notesNSDExecutable -PathType Leaf -ErrorAction Stop) {
								Write-Log -Message "Executing [$notesNSDExecutable] with the -kill argument..." -Source ${CmdletName}
								[Diagnostics.Process]$notesNSDProcess = Start-Process -FilePath $notesNSDExecutable -ArgumentList "-kill" -WindowStyle "Hidden" -PassThru -ErrorAction SilentlyContinue

								if (-not $notesNSDProcess.WaitForExit(10000)) {
									Write-Log -Message "[$notesNSDExecutable] did not end in a timely manner. Force terminate process." -Source ${CmdletName}
									Stop-Process -Name "NSD" -Force -ErrorAction SilentlyContinue
								}
							}
						}
						catch {
							Write-Log -Message "Failed to launch [$notesNSDExecutable].`r`n$(Resolve-Error)" -Source ${CmdletName}
						}

						Write-Log -Message "[$notesNSDExecutable] returned exit code [$($notesNSDProcess.ExitCode)]." -Source ${CmdletName}

						#  Force NSD process to stop in case the previous command was not successful
						Stop-Process -Name "NSD" -Force -ErrorAction SilentlyContinue
					}
				}
			}

			#  Strip all Notes processes from the process list except notes.exe, because the other notes processes (e.g. notes2.exe) may be invoked by the Notes installation, so we don't want to block their execution.
			if ($notesPathExes) {
				[Array]$processesIgnoringNotesExceptions = Compare-Object -ReferenceObject ($ProcessObjects | Select-Object -ExpandProperty "ProcessName" | Sort-Object) -DifferenceObject $notesPathExes -IncludeEqual | Where-Object { ($_.SideIndicator -eq "<=") -or ($_.InputObject -eq "notes") } | Select-Object -ExpandProperty "InputObject"
				[Array]$ProcessObjects = $ProcessObjects | Where-Object { $processesIgnoringNotesExceptions -contains $_.ProcessName }
			}
		}

		## If block execution switch is true, call the function to block execution of these processes
		if ($BlockExecution) {
			#  Make this variable globally available so we can check whether we need to call Unblock-AppExecution
			Set-Variable -Name "BlockExecution" -Value $BlockExecution -Scope Script
			Write-Log -Message "[-BlockExecution] parameter specified." -Source ${CmdletName}

			#  Skip critical processes before blocking
			$ProcessObjects | Where-Object {
				$_.ProcessName -in $configToastNotificationGeneralOptions.CriticalProcesses_NeverBlock
			} | ForEach-Object {
				Write-Log -Message "The process [$($_.ProcessName)] with description [$($_.ProcessDescription)] is tagged as critical and the system stability could be compromised if blocked, it will be skipped." -Severity 2 -Source ${CmdletName}
			}

			$ProcessesToBlock = $ProcessObjects | Where-Object { $_.ProcessName -notin $configToastNotificationGeneralOptions.CriticalProcesses_NeverBlock } | Where-Object { $_.ProcessName -notmatch $ProcessObjectsWildCardRegExPattern } | Where-Object { $_.ProcessName -notmatch $ProcessObjectsTitlePathRegExPattern } | Sort-Object -Property ProcessName -Unique
			Block-AppExecution -ProcessObjects $ProcessesToBlock
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-WelcomePrompt
Function Show-WelcomePrompt {
	<#
	.SYNOPSIS
		Called by Show-InstallationWelcome to prompt the user to optionally do the following:
		 1) Close the specified running applications.
		 2) Provide an option to defer the installation.
		 3) Show a countdown before applications are automatically closed.
	.DESCRIPTION
		The user is presented with a Windows Forms dialog box to close the applications themselves and continue or to have the script close the applications for them.
		If the -AllowDefer option is set to true, an optional "Defer" button will be shown to the user. If they select this option, the script will exit and return a 1618 code (SCCM fast retry code).
		The dialog box will timeout after the timeout specified in the XML configuration file (default 1 hour and 55 minutes) to prevent SCCM installations from timing out and returning a failure code to SCCM. When the dialog times out, the script will exit and return a 1618 code (SCCM fast retry code).
	.PARAMETER ProcessDescriptions
		The descriptive names of the applications that are running and need to be closed.
	.PARAMETER CloseAppsCountdown
		Specify the countdown time in seconds before running applications are automatically closed when deferral is not allowed or expired.
	.PARAMETER ForceCloseAppsCountdown
		Specify whether to show the countdown regardless of whether deferral is allowed.
	.PARAMETER PersistPrompt
		Specify whether to make the prompt persist in the center of the screen every couple of seconds, specified in the AppDeployToolkitConfig.xml.
	.PARAMETER AllowDefer
		Specify whether to provide an option to defer the installation.
	.PARAMETER DeferTimes
		Specify the number of times the user is allowed to defer.
	.PARAMETER DeferDeadline
		Specify the deadline date before the user is allowed to defer.
	.PARAMETER MinimizeWindows
		Specifies whether to minimize other windows when displaying prompt. Default: $true.
	.PARAMETER TopMost
		Specifies whether the windows is the topmost window. Default: $true.
	.PARAMETER ForceCountdown
		Specify a countdown to display before automatically proceeding with the installation when a deferral is enabled.
	.PARAMETER CustomText
		Specify whether to display a custom message specified in the XML file. Custom message must be populated for each language section in the XML.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Returns the user's selection.
	.EXAMPLE
		Show-WelcomePrompt -ProcessDescriptions 'Lotus Notes, Microsoft Word' -CloseAppsCountdown 600 -AllowDefer -DeferTimes 10
	.NOTES
		This is an internal script function and should typically not be called directly. It is used by the Show-InstallationWelcome prompt to display a custom prompt.
		Modified to display a Toast Notification instead of a Windows Form, falls back to the original function if any error occurs.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[PSCustomObject]$ProcessDescriptions,
		[Parameter(Mandatory = $false)]
		[int32]$CloseAppsCountdown,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ForceCloseAppsCountdown,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$PersistPrompt = $false,
		[switch]$AllowDefer,
		[Parameter(Mandatory = $false)]
		[string]$DeferTimes,
		[Parameter(Mandatory = $false)]
		[string]$DeferDeadline,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$MinimizeWindows = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$TopMost = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$ForceCountdown = 0,
		[switch]$CustomText
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "WelcomePrompt"
		$AllowedResults = @("Defer", "Close", "Continue", "Timeout")
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Initial variables definition
		[datetime]$StartTime = Get-Date
		[boolean]$showCloseApps = $false

		## Check if the timeout exceeds the maximum allowed
		if ($CloseAppsCountdown -and ($CloseAppsCountdown -gt $configInstallationUITimeout)) {
			Write-Log -Message "The close applications countdown time [$CloseAppsCountdown] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 3 -Source ${CmdletName}

			if ($configToastNotificationGeneralOptions.LimitTimeoutToInstallationUI) {
				Write-Log -Message "Using the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 2 -Source ${CmdletName}
				$CloseAppsCountdown = $configInstallationUITimeout
			}
			else {
				throw "The close applications countdown time [$CloseAppsCountdown] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]."
			}
		}

		## Initial form layout: Close Applications / Allow Deferral
		if ($processDescriptions) {
			[string]$runningProcessDescriptions = ($processDescriptions.ProcessDescription) -join ", "
			Write-Log -Message "Prompting the user to close application(s) [$runningProcessDescriptions]..." -Source ${CmdletName}
			$showCloseApps = $true
		}
		if (($allowDefer) -and (($deferTimes -ge 0) -or ($deferDeadline))) {
			Write-Log -Message "The user has the option to defer." -Source ${CmdletName}
			$showDefer = $true
			if ($deferDeadline) {
				#  Remove the Z from universal sortable date time format, otherwise it could be converted to a different time zone
				$deferDeadline = $deferDeadline -replace "Z", ""
				#  Convert the deadline date to a string
				[string]$deferDeadline = (Get-Date -Date $deferDeadline).ToString()
			}
		}

		## If deferral is not being shown and 'close apps countdown' was specified, enable that feature.
		if (-not $showDefer) {
			if ($closeAppsCountdown -gt 0) {
				Write-Log -Message "Close applications countdown has [$closeAppsCountdown] seconds remaining." -Source ${CmdletName}
				$showCountdown = $true
			}
		}

		## If 'force close apps countdown' was specified, enable that feature.
		if ($forceCloseAppsCountdown -eq $true) {
			Write-Log -Message "Close applications countdown has [$closeAppsCountdown] seconds remaining." -Source ${CmdletName}
			$showCountdown = $true
		}

		## If 'force countdown' was specified, enable that feature.
		if ($forceCountdown -eq $true) {
			Write-Log -Message "Countdown has [$closeAppsCountdown] seconds remaining." -Source ${CmdletName}
			$showCountdown = $true
		}

		## If no contdown was specified, use configuration timeout
		if (-not $showCountdown -and $CloseAppsCountdown -eq 0) {
			$CloseAppsCountdown = $configInstallationUITimeout
		}

		## Toast Notification variable standarization
		$Timeout = $CloseAppsCountdown


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			$XMLTemplate += '<toast activationType="{0}" launch="{1}{2}?Click" scenario="alarm">' -f ( <#0#> $configToastNotificationGeneralOptions.ActivationType), ( <#1#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#2#> $ResultVariable)
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
				[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
				[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
				if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
					Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
					$AppLogoOverrideImageDestinationPath.Refresh()
				}
				if ($AppLogoOverrideImageDestinationPath.Exists) {
					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title and message section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($installTitle))

			$WelcomeMessage = $null
			$CloseMessage = $null
			if ($CustomText -and $configWelcomePromptCustomMessage) {
				#  Show custom text if defined
				$WelcomeMessage = $configWelcomePromptCustomMessage
			}
			else {
				$WelcomeMessage = $configUIToastNotificationMessages.WelcomePrompt_WelcomeMessage -f ( <#0#> $deploymentTypeName.ToLower())
			}
			if ($configToastNotificationGeneralOptions.WelcomePrompt_ShowCloseMessageIfCustomMessage -and $ProcessDescriptions) {
				if ($ProcessDescriptions.Count -gt 1) {
					$CloseMessage = $configUIToastNotificationMessages.WelcomePrompt_CloseMessagePlural -f ( <#0#> $ProcessDescriptions.Count)
				}
				else {
					$CloseMessage = $configUIToastNotificationMessages.WelcomePrompt_CloseMessageSingular
				}
			}
			else {
				$CloseMessage = $null
			}
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape("$($WelcomeMessage) $($CloseMessage)"))

			#  Progress bar section, added only if there is an application countdown
			if ($showCountdown) {
				$XMLTemplate += '<progress title="{progressTitle}" value="{progressValue}" valueStringOverride="{progressValueStringOverride}" status="{progressStatus}"/>'
			}
			elseif ($configFunctionOptions.ShowAttributionText) {
				$XMLTemplate += '<text placement="attribution">{attributionText}</text>'
			}

			#  Application icon and details section
			if ($ProcessDescriptions) {
				#  If deferral is enabled use the last group to show its information
				if ($showDefer -and $configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows -eq 5) { $configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows = 4 }

				#  Divide processes according the max running rows
				if ($ProcessDescriptions.Count -gt $configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows) {
					$ShownProcesses = $ProcessDescriptions | Select-Object -First ($configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows - 1)
					$MoreProcesses = $ProcessDescriptions | Select-Object -Last ($ProcessDescriptions.Count - ($configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows - 1))
				}
				else {
					$ShownProcesses = $ProcessDescriptions
					$MoreProcesses = $null
				}

				foreach ($Process in $ShownProcesses) {
					#  Individual Applicaton icon and details group
					$XMLTemplate += '<group>'

					#  Show Applications Icons
					if ($configFunctionOptions.ShowApplicationsIcons) {
						#  Extract individual application icon from process file
						[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($Process.ProcessName).png"
						if (([IO.FileInfo]$Process.Path).Exists -and -not $IconPath.Exists) {
							$IconPath = Get-IconFromFile -Path $Process.Path -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
						}
						#  Use default no application icon if can´t get process icon
						if ($null -eq $IconPath -or -not $IconPath.Exists) {
							[IO.FileInfo]$NoIconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_noicon.png"
							if (-not $NoIconPath.Exists) {
								$NoIconPath = Get-IconFromFile -SystemIcon Application -SavePath $NoIconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
							}
							$IconPath = $NoIconPath
						}

						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing")
						}
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetStacking")
						$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetRemoveMargin").ToString().ToLower())
						$XMLTemplate += '</subgroup>'
						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing")
						}

						#  Collapse Applications Icons
						if ($configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSizeCollapsed")
						}
						else {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSize")
						}
					}
					else {
						$XMLTemplate += '<subgroup hint-textStacking="center">'
					}

					#  Show Process Description
					$XMLTemplate += '<text hint-style="Base" hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($Process.ProcessDescription))

					#  Show Extended Applications Information
					if ($configFunctionOptions.ShowExtendedApplicationsInformation) {
						if ($Process.MainWindowTitle.Length -gt 0 -and $Process.MainWindowTitle -ne $Process.ProcessDescription) {
							$XMLTemplate += '<text hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($Process.MainWindowTitle))
						}
						else {
							$XMLTemplate += '<text hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape("$($Process.ProcessName).exe"))
						}
						if ($Process.Company.Length -gt 0) {
							$XMLTemplate += '<text hint-style="CaptionSubtle">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($Process.Company))
						}
					}

					$XMLTemplate += '</subgroup>'
					$XMLTemplate += '</group>'
				}

				if ($MoreProcesses) {
					#  More applicatons icon and details group
					$XMLTemplate += '<group>'

					#  Show Applications Icons
					if ($configFunctionOptions.ShowApplicationsIcons) {
						#  Use default more application icon
						[IO.FileInfo]$MoreIconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_moreicon.png"
						if (-not $MoreIconPath.Exists) {
							$MoreIconPath = Get-IconFromFile -SystemIcon MultipleWindows -SavePath $MoreIconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
						}
						$IconPath = $MoreIconPath

						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing")
						}
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetStacking")
						$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetRemoveMargin").ToString().ToLower())
						$XMLTemplate += '</subgroup>'
						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing")
						}

						#  Collapse Applications Icons
						if ($configFunctionOptions.CollapseApplicationsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSizeCollapsed")
						}
						else {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSize")
						}
					}
					else {
						$XMLTemplate += '<subgroup hint-textStacking="center">'
					}

					#  Get more application text
					$MoreProcessesCount = [string]::Empty
					if ($configToastNotificationGeneralOptions.WelcomePrompt_MaxRunningProcessesRows -gt 1) {
						$MoreProcessesCount = "+ $($configUIToastNotificationMessages.WelcomePrompt_MoreApplicationsMessage)"
					}
					else {
						$MoreProcessesCount = $configUIToastNotificationMessages.WelcomePrompt_MoreApplicationsMessage
					}
					$MoreProcessesCount = $MoreProcessesCount -f $MoreProcesses.Count
					$MoreProcessesDescriptions = $MoreProcesses.ProcessDescription -join ", "
					$MoreProcessesProcessNames = ($MoreProcesses.ProcessName | ForEach-Object { "$($_).exe" }).ToLower() -join ", "

					$XMLTemplate += '<text hint-style="Base" hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($MoreProcessesCount))
					$XMLTemplate += '<text hint-wrap="true" hint-maxLines="4">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($MoreProcessesDescriptions.Substring(0, $(if ($MoreProcessesDescriptions.Length -gt 256) { 256 } else { $MoreProcessesDescriptions.Length }))))

					#  Show Extended Applications Information
					if ($configFunctionOptions.ShowExtendedApplicationsInformation) {
						$XMLTemplate += '<text hint-style="CaptionSubtle" hint-wrap="true" hint-maxLines="4">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($MoreProcessesProcessNames.Substring(0, $(if ($MoreProcessesProcessNames.Length -gt 256) { 256 } else { $MoreProcessesProcessNames.Length }))))
					}

					$XMLTemplate += '</subgroup>'
					$XMLTemplate += '</group>'
				}
			}

			#  Deferral section
			if ($showDefer) {
				$XMLTemplate += '<group>'
				$XMLTemplate += '<subgroup hint-textStacking="center">'
				$XMLTemplate += '<text hint-style="Base">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_DeferMessage -f ( <#0#> $deploymentTypeName.ToLower())))
				if ($deferDeadline) {
					$XMLTemplate += '<text hint-style="Caption">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_DeferMessageDeadline) -f ( <#0#> [Security.SecurityElement]::Escape($deferDeadline)))
					$XMLTemplate += '<text hint-style="CaptionSubtle">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_DeferMessageDeadlineWarning) -f ( <#0#> $deploymentTypeName.ToLower()))
				}
				$XMLTemplate += '<text hint-style="CaptionSubtle">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_RemainingDeferrals) -f ( <#0#> "$([int32]$deferTimes + 1)"))
				$XMLTemplate += '</subgroup>'
				$XMLTemplate += '</group>'
			}

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Action buttons section
			$XMLTemplate += '<actions>'
			if ($showDefer) {
				$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Defer"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_ButtonDefer)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
			}
			if ($showCloseApps) {
				$ButtonClose = $null
				if ($ProcessDescriptions.Count -gt 1) { $ButtonClose = $configUIToastNotificationMessages.WelcomePrompt_ButtonClosePlural }
				else { $ButtonClose = $configUIToastNotificationMessages.WelcomePrompt_ButtonCloseSingular }

				$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Close"/>' -f ( <#0#> [Security.SecurityElement]::Escape($ButtonClose)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
			}
			else {
				#  Replace Continue button with deployment type
				if ($configToastNotificationGeneralOptions.WelcomePrompt_ReplaceContinueButtonDeploymentType) {
					$ContinueButton = switch ($deploymentType) {
						"Install" { $configUIToastNotificationMessages.DeploymentTypeInstall }
						"Uninstall" { $configUIToastNotificationMessages.DeploymentTypeUninstall }
						"Repair" { $configUIToastNotificationMessages.DeploymentTypeRepair }
						default { $configUIToastNotificationMessages.WelcomePrompt_ButtonContinue }
					}
					$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Continue"/>' -f ( <#0#> [Security.SecurityElement]::Escape($ContinueButton)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
				}
				else {
					$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Continue"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_ButtonContinue)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
				}
			}
			$XMLTemplate += '</actions>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}

		## Sets the Toast Notification initial Notification Data
		[scriptblock]$SetToastNotificationInitialNotificationData = {
			#  Initial Notification Data
			$InitialDictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			if ($showCountdown) {
				$InitialDictionaryData.progressValue = "indeterminate"
				$InitialDictionaryData.progressValueStringOverride = " "
				$InitialDictionaryData.progressStatus = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_ProgressBarStatus)

				if ($ProcessDescriptions.Count -gt 1) {
					$InitialDictionaryData.progressTitle = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_ProgressBarTitlePlural)
				}
				else {
					$InitialDictionaryData.progressTitle = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_ProgressBarTitleSingular)
				}
			}
			elseif ($configFunctionOptions.ShowAttributionText) {
				$InitialDictionaryData.attributionText = " "
			}
		}

		## Update Toast Notification if necessary
		[scriptblock]$UpdateToastNotificationData = {
			#  Get the time information
			[datetime]$CurrentTime = Get-Date
			[datetime]$CountdownTime = $StartTime.AddSeconds($Timeout)

			#  If the countdown is complete, close the application(s) or continue
			if ($CountdownTime -le $CurrentTime) {
				if ($showCountdown) {
					if ($forceCountdown -eq $true) {
						$Result = "Continue"
						Write-Log -Message "Toast Notification result [$Result], countdown timer has elapsed. Force continue." -Severity 2 -Source ${CmdletName}
					}
					else {
						$Result = "Close"
						Write-Log -Message "Toast Notification result [$Result], close application(s) countdown timer has elapsed. Force closing application(s)." -Severity 2 -Source ${CmdletName}
					}
				}
				else {
					$Result = "Timeout"
					Write-Log -Message "Toast Notification result [$Result], exiting function." -Severity 2 -Source ${CmdletName}
				}
			}
			else {
				#  Update the remaining time data
				[timespan]$RemainingTime = $CountdownTime.Subtract($CurrentTime)
				Set-Variable -Name "closeAppsCountdownGlobal" -Value $RemainingTime.TotalSeconds -Scope Script

				$RemainingTimeData = Invoke-Command -ScriptBlock $ToastNotificationGetRemainingTime -ArgumentList $RemainingTime

				#  Update Toast Notification if new label is different
				if ($LastRemainingTimeLabel -ne $RemainingTimeData.RemainingTimeLabel) {
					$DictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

					if ($showCountdown) {
						if ($null -eq $InitialRemainingMinutes) { [int]$InitialRemainingMinutes = ($CountdownTime.Subtract($StartTime)).TotalMinutes }

						$DictionaryData.progressValue = (($InitialRemainingMinutes - $RemainingTimeData.TotalRemainingMinutes) / $InitialRemainingMinutes)
						$DictionaryData.progressValueStringOverride = [Security.SecurityElement]::Escape($RemainingTimeData.RemainingTimeLabel)
					}
					elseif ($configFunctionOptions.ShowAttributionText) {
						if ($showDefer) {
							$DictionaryData.attributionText = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.WelcomePrompt_AttributionTextAutoDeferral -f ( <#0#> $deploymentTypeName.ToLower()), ( <#1#> $RemainingTimeData.RemainingTimeLabel))
						}
						else {
							$DictionaryData.attributionText = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.AttributionTextAutoContinue -f ( <#0#> $RemainingTimeData.RemainingTimeLabel))
						}
					}

					$ToastNotificationUpdateParameters = @{
						InvokedMethod  = "Update"
						Group          = $ToastNotificationGroup
						DictionaryData = $DictionaryData
					}

					$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
				}
				$LastRemainingTimeLabel = $RemainingTimeData.RemainingTimeLabel
			}
		}

		## Re-Enumerate running processes
		[scriptblock]$ReevaluateRunningProcesses = {
			#  Get running processes
			$dynamicRunningProcesses = Get-RunningProcesses -ProcessObjects $ProcessObjects -DisableLogging
			[string]$dynamicRunningProcessDescriptions = ($dynamicRunningProcesses.ProcessDescription) -join ", "

			if ($null -eq $dynamicRunningProcesses) { $showCloseApps = $false } else { $showCloseApps = $true }

			#  If CloseApps processes were running when the Toast Notification was shown, and they are subsequently detected to be closed while the Toast Notification is showing, then close the Toast Notification. The deferral and CloseApps conditions will be re-evaluated.
			if ($ProcessDescriptions) { if ($null -eq $dynamicRunningProcesses) { Write-Log -Message "Previously detected running processes are no longer running." -Source ${CmdletName} } }
			#  If CloseApps processes were not running when the Toast Notification was shown, and they are subsequently detected to be running while the Toast Notification is showing, then close the Toast Notification for relaunch. The deferral and CloseApps conditions will be re-evaluated.
			elseif ($dynamicRunningProcesses) { Write-Log -Message "New running processes detected. Updating the Toast Notification to prompt to close the running applications." -Source ${CmdletName} }

			#  Update the Toast Notification if the running processes have changed
			if ($dynamicRunningProcessDescriptions -ne $runningProcessDescriptions) {
				if (-not $showDefer -and -not $showCloseApps) {
					#  If no defer options and no running processes, continue
					$Result = "Continue"
					Clear-ToastNotificationHistory -Group $ToastNotificationGroup
				}
				else {
					#  Update the ProcessDescriptions and runningProcessDescriptions variables to create the new Toast Notification
					$ProcessDescriptions = $dynamicRunningProcesses
					$runningProcessDescriptions = $dynamicRunningProcessDescriptions
					if ($dynamicRunningProcesses) { Write-Log -Message "The running processes have changed. Updating the apps to close: [$runningProcessDescriptions]..." -Source ${CmdletName} }

					#  Update the Toast Notification with the processes to close
					Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
				}
			}
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Minimize all other windows
			if ($minimizeWindows) { $null = $shellApp.MinimizeAll() }

			## Test if the Toast Notification can be shown
			$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension -CheckProtocol

			if ($ToastNotificationExtensionTestResult) {
				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope

				#  Loops until Toast Notification result
				if ($ToastNotificationVisible) {
					Invoke-Command -ScriptBlock $ToastNotificationLoopUntilResult -NoNewScope
				}
			}
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope

		Write-Log -Message "Exiting function [${CmdletName}] with result [$Result]." -Severity 2 -Source ${CmdletName} -DebugMessage

		return $Result
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-BalloonTip
Function Show-BalloonTip {
	<#
	.SYNOPSIS
		Displays a balloon tip notification in the system tray.
	.DESCRIPTION
		Displays a balloon tip notification in the system tray.
	.PARAMETER BalloonTipText
		Text of the balloon tip.
	.PARAMETER BalloonTipTitle
		Title of the balloon tip.
	.PARAMETER BalloonTipIcon
		Icon to be used. Options: 'Error', 'Info', 'None', 'Warning'. Default is: Info.
	.PARAMETER BalloonTipTime
		Time in milliseconds to display the balloon tip. Default: 10000.
	.PARAMETER NoWait
		Create the balloontip asynchronously. Default: $false
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Show-BalloonTip -BalloonTipText 'Installation Started' -BalloonTipTitle 'Application Name'
	.EXAMPLE
		Show-BalloonTip -BalloonTipIcon 'Info' -BalloonTipText 'Installation Started' -BalloonTipTitle 'Application Name' -BalloonTipTime 1000
	.NOTES
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$BalloonTipText,
		[Parameter(Mandatory = $false, Position = 1)]
		[ValidateNotNullorEmpty()]
		[string]$BalloonTipTitle = $installTitle,
		[Parameter(Mandatory = $false, Position = 2)]
		[ValidateSet("Error", "Info", "None", "Warning")]
		[Windows.Forms.ToolTipIcon]$BalloonTipIcon = "Info",
		[Parameter(Mandatory = $false, Position = 3)]
		[ValidateNotNullorEmpty()]
		[int32]$BalloonTipTime = 10000,
		[Parameter(Mandatory = $false, Position = 4)]
		[switch]$NoWait
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "BalloonTip"
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Bypass if in silent mode
		if ($deployModeSilent) {
			Write-Log -Message "Bypassing function [${CmdletName}], because DeployMode [$deployMode]. Text: $BalloonTipText" -Severity 2 -Source ${CmdletName}
			return
		}
		else {
			Write-Log -Message "Executing function [${CmdletName}]. Text: $BalloonTipText" -Severity 2 -Source ${CmdletName}
		}


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			if ($BalloonTipTime -gt 10000) {
				$XMLTemplate += '<toast duration="long">'
			}
			else {
				$XMLTemplate += '<toast duration="short">'
			}
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow) {
				if ($configFunctionOptions.ShowDialogIconAsAppLogoOverride) {
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($BalloonTipIcon.ToString()).png"
					if (-not $AppLogoOverrideImageDestinationPath.Exists) {
						$AppLogoOverrideImageDestinationPath = Get-IconFromFile -SystemIcon $BalloonTipIcon.ToString() -SavePath $AppLogoOverrideImageDestinationPath -TargetSize $configToastNotificationGeneralOptions."IconSize_Biggest_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
					[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName

					if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
						Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
						$AppLogoOverrideImageDestinationPath.Refresh()
					}

					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
				}

				if ($AppLogoOverrideImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title and message section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($BalloonTipTitle))

			if (-not $configFunctionOptions.ShowDialogIconAsAppLogoOverride -or -not $configFunctionOptions.ImageAppLogoOverrideShow) {
				#  Balloon Tip icon and message section
				$XMLTemplate += '<group>'

				#  Extract dialog icon from Windows library
				[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($BalloonTipIcon.ToString()).png"
				if (-not $IconPath.Exists) {
					$IconPath = Get-IconFromFile -SystemIcon $BalloonTipIcon.ToString() -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
				}

				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
				}
				$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetStacking")
				$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetRemoveMargin").ToString().ToLower())
				$XMLTemplate += '</subgroup>'
				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
				}

				#  Collapse Dialogs Icons
				if ($configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
				}
				else {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
				}

				$XMLTemplate += '<text hint-style="Base" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($BalloonTipText))
				$XMLTemplate += '</subgroup>'
				$XMLTemplate += '</group>'
			}
			else {
				$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($BalloonTipText))
			}

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Test if the Toast Notification can be shown
			$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension

			if ($ToastNotificationExtensionTestResult) {
				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
			}
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-DialogBox
Function Show-DialogBox {
	<#
	.SYNOPSIS
		Display a custom dialog box with optional title, buttons, icon and timeout.
		Show-InstallationPrompt is recommended over this function as it provides more customization and uses consistent branding with the other UI components.
	.DESCRIPTION
		Display a custom dialog box with optional title, buttons, icon and timeout. The default button is "OK", the default Icon is "None", and the default Timeout is none.
	.PARAMETER Text
		Text in the message dialog box
	.PARAMETER Title
		Title of the message dialog box
	.PARAMETER Buttons
		Buttons to be included on the dialog box. Options: OK, OKCancel, AbortRetryIgnore, YesNoCancel, YesNo, RetryCancel, CancelTryAgainContinue. Default: OK.
	.PARAMETER DefaultButton
		The Default button that is selected. Options: First, Second, Third. Default: First.
	.PARAMETER Icon
		Icon to display on the dialog box. Options: None, Stop, Question, Exclamation, Information. Default: None.
	.PARAMETER Timeout
		Timeout period in seconds before automatically closing the dialog box with the return message "Timeout". Default: UI timeout value set in the config XML file.
	.PARAMETER TopMost
		Specifies whether the message box is a system modal message box and appears in a topmost window. Default: $true.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Returns the text of the button that was clicked.
	.EXAMPLE
		Show-DialogBox -Title 'Installed Complete' -Text 'Installation has completed. Please click OK and restart your computer.' -Icon 'Information'
	.EXAMPLE
		Show-DialogBox -Title 'Installation Notice' -Text 'Installation will take approximately 30 minutes. Do you wish to proceed?' -Buttons 'OKCancel' -DefaultButton 'Second' -Icon 'Exclamation' -Timeout 600 -Topmost $false
	.NOTES
		Modified to display a Toast Notification instead of a Dialog Box, falls back to the original function if any error occurs.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, Position = 0, HelpMessage = "Enter a message for the dialog box")]
		[ValidateNotNullorEmpty()]
		[string]$Text,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Title = $installTitle,
		[Parameter(Mandatory = $false)]
		[ValidateSet("OK", "OKCancel", "AbortRetryIgnore", "YesNoCancel", "YesNo", "RetryCancel", "CancelTryAgainContinue")]
		[string]$Buttons = "OK",
		[Parameter(Mandatory = $false)]
		[ValidateSet("First", "Second", "Third")]
		[string]$DefaultButton = "First",
		[Parameter(Mandatory = $false)]
		[ValidateSet("Exclamation", "Information", "None", "Stop", "Question")]
		[string]$Icon = "None",
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Timeout = $configInstallationUITimeout,
		[Parameter(Mandatory = $false)]
		[boolean]$TopMost = $true
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "DialogBox"
		$AllowedResults = @("Ok", "Cancel", "Abort", "Retry", "Ignore", "Yes", "No", "TryAgain", "Continue", "Timeout")
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Bypass if in non-interactive mode
		if ($deployModeNonInteractive) {
			Write-Log -Message "Bypassing function [${CmdletName}], because DeployMode [$deployMode]. Text: $Text" -Severity 2 -Source ${CmdletName}
			return
		}
		else {
			Write-Log -Message "Executing function [${CmdletName}]. Text: $Text" -Severity 2 -Source ${CmdletName}
		}

		## Reset times
		[datetime]$StartTime = Get-Date

		## Check if the timeout exceeds the maximum allowed
		if ($Timeout -gt $configInstallationUITimeout) {
			Write-Log -Message "The timeout time [$Timeout] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 3 -Source ${CmdletName}

			if ($configToastNotificationGeneralOptions.LimitTimeoutToInstallationUI) {
				Write-Log -Message "Using the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 2 -Source ${CmdletName}
				$Timeout = $configInstallationUITimeout
			}
			else {
				throw "The timeout time [$Timeout] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]."
			}
		}


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			$XMLTemplate += '<toast activationType="{0}" launch="{1}{2}?Click" scenario="alarm">' -f ( <#0#> $configToastNotificationGeneralOptions.ActivationType), ( <#1#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#2#> $ResultVariable)
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow) {
				if ($configFunctionOptions.ShowDialogIconAsAppLogoOverride -and $Icon -ne "None") {
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
					if (-not $AppLogoOverrideImageDestinationPath.Exists) {
						$AppLogoOverrideImageDestinationPath = Get-IconFromFile -SystemIcon $Icon -SavePath $AppLogoOverrideImageDestinationPath -TargetSize $configToastNotificationGeneralOptions."IconSize_Biggest_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
					[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName

					if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
						Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
						$AppLogoOverrideImageDestinationPath.Refresh()
					}

					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
				}

				if ($AppLogoOverrideImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Tittle section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($Title))

			if ($configFunctionOptions.ShowAttributionText) {
				$XMLTemplate += '<text placement="attribution">{attributionText}</text>'
			}

			#  Dialog Box icon and message section
			$XMLTemplate += '<group>'

			if ($Icon -ne "None") {
				if (-not $configFunctionOptions.ShowDialogIconAsAppLogoOverride -or -not $configFunctionOptions.ImageAppLogoOverrideShow) {
					#  Extract dialog box icon from Windows library
					[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
					if (-not $IconPath.Exists) {
						$IconPath = Get-IconFromFile -SystemIcon $Icon -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}

					if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
					}
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetStacking")
					$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetRemoveMargin").ToString().ToLower())
					$XMLTemplate += '</subgroup>'
					if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
					}

					#  Collapse Dialogs Icons
					if ($configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
					}
					else {
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
					}
				}
				else {
					$XMLTemplate += '<subgroup hint-textStacking="center">'
				}
			}
			else {
				$XMLTemplate += '<subgroup hint-textStacking="center">'
			}

			[array]$SplittedMessage = $Text -split '`r`n'

			if ($SplittedMessage.Count -gt 5) {
				$XMLTemplate += '<text hint-style="Caption" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($SplittedMessage))
			}
			else {
				$XMLTemplate += '<text hint-style="Base" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($SplittedMessage))
			}
			$XMLTemplate += '</subgroup>'
			$XMLTemplate += '</group>'

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Action buttons section
			$XMLTemplate += '<actions>'

			switch -regex ($Buttons) {
				"OK" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?OK"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "OK"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Abort" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Abort"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Abort"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Retry" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Retry"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Retry"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Ignore" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Ignore"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Ignore"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Yes" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Yes"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Yes"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"(?!\w*Ig)No(?<!re\w*)" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?No"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "No"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Cancel" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Cancel"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Cancel"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"TryAgain" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?TryAgain"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "TryAgain"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
				"Continue" { $XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Continue"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList "Continue"))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable) }
			}

			$XMLTemplate += '</actions>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}

		## Sets the Toast Notification initial Notification Data
		[scriptblock]$SetToastNotificationInitialNotificationData = {
			#  Initial Notification Data
			$InitialDictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			if ($configFunctionOptions.ShowAttributionText) {
				$InitialDictionaryData.attributionText = " "
			}
		}

		## Update Toast Notification if necessary
		[scriptblock]$UpdateToastNotificationData = {
			#  Get the time information
			[datetime]$CurrentTime = Get-Date
			[datetime]$CountdownTime = $StartTime.AddSeconds($Timeout)

			#  If the countdown is complete, close the application(s) or continue
			if ($CountdownTime -le $CurrentTime) {
				$Result = "Timeout"
				Write-Log -Message "Toast Notification result [$Result], exiting function." -Severity 2 -Source ${CmdletName}
			}
			else {
				#  Update the remaining time data
				[timespan]$RemainingTime = $CountdownTime.Subtract($CurrentTime)

				$RemainingTimeData = Invoke-Command -ScriptBlock $ToastNotificationGetRemainingTime -ArgumentList $RemainingTime

				#  Update Toast Notification if new label is different
				if ($LastRemainingTimeLabel -ne $RemainingTimeData.RemainingTimeLabel) {
					$DictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

					if ($configFunctionOptions.ShowAttributionText) {
						$DictionaryData.attributionText = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.AttributionTextAutoContinue -f ( <#0#> $RemainingTimeData.RemainingTimeLabel))
					}

					$ToastNotificationUpdateParameters = @{
						InvokedMethod  = "Update"
						Group          = $ToastNotificationGroup
						DictionaryData = $DictionaryData
					}

					$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
				}
				$LastRemainingTimeLabel = $RemainingTimeData.RemainingTimeLabel
			}
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Test if the Toast Notification can be shown
			$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension -CheckProtocol

			if ($ToastNotificationExtensionTestResult) {
				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope

				#  Loops until Toast Notification result
				if ($ToastNotificationVisible) {
					Invoke-Command -ScriptBlock $ToastNotificationLoopUntilResult -NoNewScope
				}
			}
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope

		Write-Log -Message "Exiting function [${CmdletName}] with result [$Result]." -Severity 2 -Source ${CmdletName} -DebugMessage

		return $Result
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-InstallationRestartPrompt
Function Show-InstallationRestartPrompt {
	<#
	.SYNOPSIS
		Displays a restart prompt with a countdown to a forced restart.
	.DESCRIPTION
		Displays a restart prompt with a countdown to a forced restart.
	.PARAMETER CountdownSeconds
		Specifies the number of seconds to countdown before the system restart. Default: 60
	.PARAMETER CountdownNoHideSeconds
		Specifies the number of seconds to display the restart prompt without allowing the window to be hidden. Default: 30
	.PARAMETER NoSilentRestart
		Specifies whether the restart should be triggered when Deploy mode is silent or very silent. Default: $true
	.PARAMETER NoCountdown
		Specifies not to show a countdown.
		The UI will restore/reposition itself persistently based on the interval value specified in the config file.
	.PARAMETER SilentCountdownSeconds
		Specifies number of seconds to countdown for the restart when the toolkit is running in silent mode and NoSilentRestart is $false. Default: 5
	.PARAMETER TopMost
		Specifies whether the windows is the topmost window. Default: $true.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Show-InstallationRestartPrompt -Countdownseconds 600 -CountdownNoHideSeconds 60
	.EXAMPLE
		Show-InstallationRestartPrompt -NoCountdown
	.EXAMPLE
		Show-InstallationRestartPrompt -Countdownseconds 300 -NoSilentRestart $false -SilentCountdownSeconds 10
	.NOTES
		Be mindful of the countdown you specify for the reboot as code directly after this function might NOT be able to execute - that includes logging.
		Modified to display a Toast Notification instead of a Windows Form, falls back to the original function if any error occurs.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$CountdownSeconds = 60,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$CountdownNoHideSeconds = 30,
		[Parameter(Mandatory = $false)]
		[bool]$NoSilentRestart = $true,
		[Parameter(Mandatory = $false)]
		[switch]$NoCountdown = $false,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$SilentCountdownSeconds = 5,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$TopMost = $true
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "InstallationRestartPrompt"
		$AllowedResults = @("RestartLater", "RestartNow")
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Restart Computer ScriptBlock
		[scriptblock]$RestartComputer = {
			Write-Log -Message "Forcefully restarting the computer..." -Severity 2 -Source ${CmdletName}
			Start-Process -FilePath "shutdown.exe" -ArgumentList "/r /f /t $($SilentCountdownSeconds)" -WindowStyle Hidden -ErrorAction SilentlyContinue
			[Environment]::Exit(0)
		}

		## If in non-interactive mode
		if ($deployModeSilent) {
			if ($NoSilentRestart -eq $false) {
				Write-Log -Message "Triggering restart silently, because the deploy mode is set to [$deployMode] and [NoSilentRestart] is disabled. Timeout is set to [$SilentCountdownSeconds] seconds." -Source ${CmdletName}
				Invoke-Command -ScriptBlock $RestartComputer -NoNewScope
			}
			else {
				Write-Log -Message "Skipping restart, because the deploy mode is set to [$deployMode] and [NoSilentRestart] is enabled." -Source ${CmdletName}
			}
			return
		}

		## Check if we are already displaying a restart prompt
		try {
			if (Test-ToastNotificationVisible -Group $ToastNotificationGroup) {
				Write-Log -Message "${CmdletName} was invoked, but an existing restart prompt was detected. Cancelling restart prompt." -Severity 2 -Source ${CmdletName}
				return
			}
		}
		catch {}

		## If the script has been dot-source invoked by the deploy app script, display the restart prompt asynchronously
		if ($deployAppScriptFriendlyName) {
			if ($NoCountdown) {
				Write-Log -Message "Invoking ${CmdletName} asynchronously with no countdown..." -Source ${CmdletName}
			}
			else {
				Write-Log -Message "Invoking ${CmdletName} asynchronously with a [$countDownSeconds] seconds countdown..." -Source ${CmdletName}
			}

			## Initialize the Toast Notification Extension
			try { $null = Test-ToastNotificationExtension } catch {}

			## Get the parameters passed to the function for invoking the function asynchronously
			[hashtable]$installRestartPromptParameters = $PSBoundParameters
			#  Remove Silent reboot parameters from the list that is being forwarded to the main script for asynchronous function execution. This is only for Interactive mode so we dont need silent mode reboot parameters.
			$installRestartPromptParameters.Remove("NoSilentRestart")
			$installRestartPromptParameters.Remove("SilentCountdownSeconds")
			#  Prepare a list of parameters of this function as a string
			[string]$installRestartPromptParameters = ($installRestartPromptParameters.GetEnumerator() | ForEach-Object { & $ResolveParameters $_ }) -join " "

			## Start another powershell instance silently with function parameters from this function
			Start-Process -FilePath "$($PSHome)\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -Command &{& `'$scriptPath`' -ReferredInstallTitle `'$installTitle`' -ReferredInstallName `'$installName`' -ReferredLogName `'$logName`' -ShowInstallationRestartPrompt $installRestartPromptParameters -AsyncToolkitLaunch}" -WindowStyle Hidden -ErrorAction SilentlyContinue
			return
		}

		## Initial variables definition
		[datetime]$StartTime = Get-Date

		## Toast Notification variable standarization
		$Timeout = $CountdownSeconds


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			$XMLTemplate += '<toast duration="long">'
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			if ($configToastNotificationGeneralOptions.InstallationRestartPrompt_ShowIcon) { $Icon = "Warning" } else { $Icon = "None" }

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow) {
				if ($configFunctionOptions.ShowDialogIconAsAppLogoOverride -and $Icon -ne "None") {
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
					if (-not $AppLogoOverrideImageDestinationPath.Exists) {
						$AppLogoOverrideImageDestinationPath = Get-IconFromFile -SystemIcon $Icon -SavePath $AppLogoOverrideImageDestinationPath -TargetSize $configToastNotificationGeneralOptions."IconSize_Biggest_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
					[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName

					if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
						Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
						$AppLogoOverrideImageDestinationPath.Refresh()
					}

					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
				}

				if ($AppLogoOverrideImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title and message section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($installTitle))
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_RestartMessage))

			#  Progress bar section, added only if there is an application countdown
			if (-not $NoCountdown) {
				$XMLTemplate += '<progress title="{progressTitle}" value="{progressValue}" valueStringOverride="{progressValueStringOverride}" status="{progressStatus}"/>'
			}
			$XMLTemplate += '<text placement="attribution">{attributionText}</text>'

			$XMLTemplate += '<group>'

			if ($Icon -ne "None") {
				if (-not $configFunctionOptions.ShowDialogIconAsAppLogoOverride -or -not $configFunctionOptions.ImageAppLogoOverrideShow) {
					#  Extract dialog icon from Windows library
					[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
					if (-not $IconPath.Exists) {
						$IconPath = Get-IconFromFile -SystemIcon $Icon -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}

					if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
					}
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetStacking")
					$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetRemoveMargin").ToString().ToLower())
					$XMLTemplate += '</subgroup>'
					if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
					}

					#  Collapse Dialogs Icons
					if ($configFunctionOptions.CollapseDialogsIcons) {
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
					}
					else {
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
					}
				}
				else {
					$XMLTemplate += '<subgroup hint-textStacking="center">'
				}
			}
			else {
				$XMLTemplate += '<subgroup hint-textStacking="center">'
			}

			$XMLTemplate += '<text hint-style="Base" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_AutoRestartMessage))
			$XMLTemplate += '<text hint-style="CaptionSubtle" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_SaveMessage))
			$XMLTemplate += '</subgroup>'
			$XMLTemplate += '</group>'

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Action buttons section
			$XMLTemplate += '<actions>'
			$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?RestartNow"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_ButtonRestartNow)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
			$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?RestartLater"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_ButtonRestartLater)), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
			$XMLTemplate += '</actions>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}

		## Sets the Toast Notification initial Notification Data
		[scriptblock]$SetToastNotificationInitialNotificationData = {
			#  Initial Notification Data
			$InitialDictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			$InitialDictionaryData.attributionText = " "

			if (-not $NoCountdown) {
				$InitialDictionaryData.progressValue = "indeterminate"
				$InitialDictionaryData.progressValueStringOverride = " "
				$InitialDictionaryData.progressTitle = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_ProgressBarTitle)
				$InitialDictionaryData.progressStatus = [Security.SecurityElement]::Escape($configUIToastNotificationMessages.RestartPrompt_ProgressBarStatus)
			}
		}

		## Update Toast Notification if necessary
		[scriptblock]$UpdateToastNotificationData = {
			#  Get the time information
			[datetime]$CurrentTime = Get-Date
			[datetime]$CountdownTime = $StartTime.AddSeconds($Timeout)

			#  If the countdown is complete, close the application(s) or continue
			if ($CountdownTime -le $CurrentTime) {
				$Result = "RestartNow"
				Write-Log -Message "Toast Notification result [$Result], countdown timer has elapsed." -Severity 2 -Source ${CmdletName}
			}
			else {
				#  Update the remaining time data
				[timespan]$RemainingTime = $CountdownTime.Subtract($CurrentTime)

				$RemainingTimeData = Invoke-Command -ScriptBlock $ToastNotificationGetRemainingTime -ArgumentList $RemainingTime

				$DictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

				if ($configFunctionOptions.ShowAttributionText -and $NoCountdown) {
					$AttributionText = $configUIToastNotificationMessages.RestartPrompt_AttributionText -f ( <#0#> $RemainingTimeData.RemainingTimeLabel)
				}
				else {
					$AttributionText = $null
				}

				$DictionaryData.attributionText = [Security.SecurityElement]::Escape("$($AttributionText)$(" "*(Get-Random -Minimum 1 -Maximum 6))")


				if (-not $NoCountdown) {
					if ($null -eq $InitialRemainingMinutes) { [int]$InitialRemainingMinutes = ($CountdownTime.Subtract($StartTime)).TotalMinutes }

					$DictionaryData.progressValue = (($InitialRemainingMinutes - $RemainingTimeData.TotalRemainingMinutes) / $InitialRemainingMinutes)
					$DictionaryData.progressValueStringOverride = [Security.SecurityElement]::Escape($RemainingTimeData.RemainingTimeLabel)
				}

				$ToastNotificationUpdateParameters = @{
					InvokedMethod  = "Update"
					Group          = $ToastNotificationGroup
					DictionaryData = $DictionaryData
				}

				$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
			}
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Test if the Toast Notification can be shown
			$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension -CheckProtocol

			if ($ToastNotificationExtensionTestResult) {
				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope

				#  Loops until Toast Notification result
				if ($ToastNotificationVisible) {
					Invoke-Command -ScriptBlock $ToastNotificationLoopUntilResult -NoNewScope
				}
			}
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope

		## If this point is reached, force restart the computer
		Invoke-Command -ScriptBlock $RestartComputer -NoNewScope
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-InstallationPrompt
Function Show-InstallationPrompt {
	<#
	.SYNOPSIS
		Displays a custom installation prompt with the toolkit branding and optional buttons.
	.DESCRIPTION
		Any combination of Left, Middle or Right buttons can be displayed. The return value of the button clicked by the user is the button text specified.
	.PARAMETER Title
		Title of the prompt. Default: the application installation name.
	.PARAMETER Message
		Message text to be included in the prompt
	.PARAMETER MessageAlignment
		Alignment of the message text. Options: Left, Center, Right. Default: Center.
	.PARAMETER ButtonLeftText
		Show a button on the left of the prompt with the specified text
	.PARAMETER ButtonRightText
		Show a button on the right of the prompt with the specified text
	.PARAMETER ButtonMiddleText
		Show a button in the middle of the prompt with the specified text
	.PARAMETER Icon
		Show a system icon in the prompt. Options: Application, Asterisk, Error, Exclamation, Hand, Information, None, Question, Shield, Warning, WinLogo. Default: None.
	.PARAMETER NoWait
		Specifies whether to show the prompt asynchronously (i.e. allow the script to continue without waiting for a response). Default: $false.
	.PARAMETER PersistPrompt
		Specify whether to make the prompt persist in the center of the screen every couple of seconds, specified in the AppDeployToolkitConfig.xml. The user will have no option but to respond to the prompt - resistance is futile!
	.PARAMETER MinimizeWindows
		Specifies whether to minimize other windows when displaying prompt. Default: $false.
	.PARAMETER Timeout
		Specifies the time period in seconds after which the prompt should timeout. Default: UI timeout value set in the config XML file.
	.PARAMETER ExitOnTimeout
		Specifies whether to exit the script if the UI times out. Default: $true.
	.PARAMETER TopMost
		Specifies whether the progress window should be topmost. Default: $true.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Returns the text of the button that was clicked.
	.EXAMPLE
		Show-InstallationPrompt -Message 'Do you want to proceed with the installation?' -ButtonRightText 'Yes' -ButtonLeftText 'No'
	.EXAMPLE
		Show-InstallationPrompt -Title 'Funny Prompt' -Message 'How are you feeling today?' -ButtonRightText 'Good' -ButtonLeftText 'Bad' -ButtonMiddleText 'Indifferent'
	.EXAMPLE
		Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install, or remove it completely for unattended installations.' -Icon Information -NoWait
	.NOTES
		Modified to display a Toast Notification instead of a Windows Form, falls back to the original function if any error occurs.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Title = $installTitle,
		[Parameter(Mandatory = $false)]
		[string]$Message = "",
		[Parameter(Mandatory = $false)]
		[ValidateSet("Left", "Center", "Right")]
		[string]$MessageAlignment = "Center",
		[Parameter(Mandatory = $false)]
		[string]$ButtonRightText = "",
		[Parameter(Mandatory = $false)]
		[string]$ButtonLeftText = "",
		[Parameter(Mandatory = $false)]
		[string]$ButtonMiddleText = "",
		[Parameter(Mandatory = $false)]
		[ValidateSet("Application", "Asterisk", "Error", "Exclamation", "Hand", "Information", "None", "Question", "Shield", "Warning", "WinLogo")]
		[string]$Icon = "None",
		[switch]$NoWait,
		[switch]$PersistPrompt,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$MinimizeWindows = $false,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$Timeout = $configInstallationUITimeout,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ExitOnTimeout = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$TopMost = $true
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "InstallationPrompt"
		$AllowedResults = @("Left", "Middle", "Right", "Timeout")
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Bypass if in silent mode
		if ($deployModeSilent) {
			Write-Log -Message "Bypassing function [${CmdletName}], because DeployMode [$deployMode]. Message: $Message" -Severity 2 -Source ${CmdletName}
			return
		}
		else {
			Write-Log -Message "Executing function [${CmdletName}]. Message: $Message" -Severity 2 -Source ${CmdletName}
		}

		## Check if the timeout exceeds the maximum allowed
		if ($Timeout -gt $configInstallationUITimeout) {
			Write-Log -Message "The timeout time [$Timeout] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 3 -Source ${CmdletName}

			if ($configToastNotificationGeneralOptions.LimitTimeoutToInstallationUI) {
				Write-Log -Message "Using the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]." -Severity 2 -Source ${CmdletName}
				$Timeout = $configInstallationUITimeout
			}
			else {
				throw "The timeout time [$Timeout] cannot be longer than the timeout specified in the XML configuration for installation UI dialogs to timeout [$configInstallationUITimeout]."
			}
		}

		## If the NoWait parameter is specified, launch a new PowerShell session to show the prompt asynchronously
		if ($NoWait) {
			Write-Log -Message "Invoking ${CmdletName} asynchronously..." -Source ${CmdletName}

			## Get parameters for calling function asynchronously
			[hashtable]$installPromptParameters = $PSBoundParameters
			#  Remove the NoWait parameter so that the script is run synchronously in the new PowerShell session. This also prevents the function to loop indefinitely.
			$installPromptParameters.Remove("NoWait")
			#  Format the parameters as a string
			[String]$installPromptParameters = ($installPromptParameters.GetEnumerator() | ForEach-Object { & $ResolveParameters $_ }) -join " "

			## Initialize the Toast Notification Extension
			try { $null = Test-ToastNotificationExtension } catch {}

			## Start another powershell instance silently with function parameters from this function
			Start-Process -FilePath "$($PSHome)\powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -Command &{& `'$scriptPath`' -ReferredInstallTitle `'$Title`' -ReferredInstallName `'$installName`' -ReferredLogName `'$logName`' -ShowInstallationPrompt $installPromptParameters -AsyncToolkitLaunch}" -WindowStyle 'Hidden' -ErrorAction SilentlyContinue
			return
		}

		## Initial variables definition
		[datetime]$StartTime = Get-Date


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			if ($deployAppScriptFriendlyName) {
				$XMLTemplate += '<toast activationType="{0}" launch="{1}{2}?Click" scenario="alarm">' -f ( <#0#> $configToastNotificationGeneralOptions.ActivationType), ( <#1#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#2#> $ResultVariable)
			}
			else {
				$XMLTemplate += '<toast duration="long">'
			}
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow) {
				if ($configFunctionOptions.ShowDialogIconAsAppLogoOverride -and $Icon -ne "None") {
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
					if (-not $AppLogoOverrideImageDestinationPath.Exists) {
						$AppLogoOverrideImageDestinationPath = Get-IconFromFile -SystemIcon $Icon -SavePath $AppLogoOverrideImageDestinationPath -TargetSize $configToastNotificationGeneralOptions."IconSize_Biggest_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
					[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName

					if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
						Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
						$AppLogoOverrideImageDestinationPath.Refresh()
					}

					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
				}

				if ($AppLogoOverrideImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($Title))

			$XMLTemplate += '<text placement="attribution">{attributionText}</text>'

			#  Message section
			if ($Message) {
				#  Installation icon and message section
				$XMLTemplate += '<group>'

				if ($Icon -ne "None") {
					if (-not $configFunctionOptions.ShowDialogIconAsAppLogoOverride -or -not $configFunctionOptions.ImageAppLogoOverrideShow) {
						#  Extract dialog icon from Windows library
						[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_$($Icon).png"
						if (-not $IconPath.Exists) {
							$IconPath = Get-IconFromFile -SystemIcon $Icon -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
						}

						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
						}
						$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetStacking")
						$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetRemoveMargin").ToString().ToLower())
						$XMLTemplate += '</subgroup>'
						if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
						}

						#  Collapse Dialogs Icons
						if ($configFunctionOptions.CollapseDialogsIcons) {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
						}
						else {
							$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
						}
					}
					else {
						$XMLTemplate += '<subgroup hint-textStacking="center">'
					}
				}
				else {
					$XMLTemplate += '<subgroup hint-textStacking="center">'
				}

				[array]$SplittedMessage = $Message -split '`r`n'

				$XMLTemplate += '<text hint-wrap="true" hint-align="{0}">{1}</text>' -f ( <#0#> ($MessageAlignment).ToLower()), ( <#1#> [Security.SecurityElement]::Escape($SplittedMessage))
				$XMLTemplate += '</subgroup>'
				$XMLTemplate += '</group>'
			}

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Action buttons section
			if ($buttonLeftText -or $buttonMiddleText -or $buttonRightText) {
				$XMLTemplate += '<actions>'
				if ($deployAppScriptFriendlyName) {
					if ($buttonLeftText) {
						$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Left"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonLeftText))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
					}
					if ($buttonMiddleText) {
						$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Middle"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonMiddleText))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
					}
					if ($buttonRightText) {
						$XMLTemplate += '<action content="{0}" activationType="{1}" arguments="{2}{3}?Right"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonRightText))), ( <#1#> $configToastNotificationGeneralOptions.ActivationType), ( <#2#> $configToastNotificationGeneralOptions.ArgumentsPrefix), ( <#3#> $ResultVariable)
					}
				}
				else {
					if ($buttonLeftText) {
						$XMLTemplate += '<action content="{0}" arguments="Left"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonLeftText)))
					}
					if ($buttonMiddleText) {
						$XMLTemplate += '<action content="{0}" arguments="Middle"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonMiddleText)))
					}
					if ($buttonRightText) {
						$XMLTemplate += '<action content="{0}" arguments="Right"/>' -f ( <#0#> [Security.SecurityElement]::Escape((Invoke-Command -ScriptBlock $TranslateButton -ArgumentList $buttonRightText)))
					}
				}
				$XMLTemplate += '</actions>'
			}

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}

		## Sets the Toast Notification initial Notification Data
		[scriptblock]$SetToastNotificationInitialNotificationData = {
			#  Initial Notification Data
			$InitialDictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			$InitialDictionaryData.attributionText = " "
		}

		## Update Toast Notification if necessary
		[scriptblock]$UpdateToastNotificationData = {
			#  Get the time information
			[datetime]$CurrentTime = Get-Date
			[datetime]$CountdownTime = $StartTime.AddSeconds($Timeout)

			#  If the countdown is complete, close the application(s) or continue
			if ($CountdownTime -le $CurrentTime) {
				$Result = "Timeout"
				Write-Log -Message "Toast Notification result [$Result], exiting function." -Severity 2 -Source ${CmdletName}
			}
			else {
				#  Update the remaining time data
				[timespan]$RemainingTime = $CountdownTime.Subtract($CurrentTime)

				$RemainingTimeData = Invoke-Command -ScriptBlock $ToastNotificationGetRemainingTime -ArgumentList $RemainingTime

				$DictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

				if ($configFunctionOptions.ShowAttributionText) {
					if ($deployAppScriptFriendlyName) {
						$AttributionText = $configUIToastNotificationMessages.AttributionTextAutoContinue -f ( <#0#> $RemainingTimeData.RemainingTimeLabel)
					}
					else {
						$AttributionText = $configUIToastNotificationMessages.InstallationPrompt_AttributionTextDismiss
					}
				}
				else {
					$AttributionText = " "
				}

				if ($deployAppScriptFriendlyName) {
					#  Update Toast Notification if new label is different
					if ($LastRemainingTimeLabel -ne $RemainingTimeData.RemainingTimeLabel) {
						$DictionaryData.attributionText = [Security.SecurityElement]::Escape($AttributionText)

						$ToastNotificationUpdateParameters = @{
							InvokedMethod  = "Update"
							Group          = $ToastNotificationGroup
							DictionaryData = $DictionaryData
						}

						$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
					}
					$LastRemainingTimeLabel = $RemainingTimeData.RemainingTimeLabel
				}
				else {
					$DictionaryData.attributionText = [Security.SecurityElement]::Escape("$($AttributionText)$(" "*(Get-Random -Minimum 1 -Maximum 6))")

					$ToastNotificationUpdateParameters = @{
						InvokedMethod  = "Update"
						Group          = $ToastNotificationGroup
						DictionaryData = $DictionaryData
					}

					$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
				}
			}
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Test if the Toast Notification can be shown
			if ($deployAppScriptFriendlyName) {
				$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension -CheckProtocol
			}
			else {
				$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension
			}

			if ($ToastNotificationExtensionTestResult) {
				#  Minimize all other windows
				if ($minimizeWindows) { $null = $shellApp.MinimizeAll() }

				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope

				#  Loops until Toast Notification result
				if ($ToastNotificationVisible) {
					Invoke-Command -ScriptBlock $ToastNotificationLoopUntilResult -NoNewScope
				}
			}
		}

		#  Restore minimized windows
		$null = $shellApp.UndoMinimizeAll()

		if ($deployAppScriptFriendlyName) {
			## Fallback to original function
			Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope

			switch ($Result) {
				"Left" { $Result = $buttonLeftText }
				"Middle" { $Result = $buttonMiddleText }
				"Right" { $Result = $buttonRightText }
			}

			if ($Result -ne "Timeout") {
				Write-Log -Message "Exiting function [${CmdletName}] with result [$Result]." -Severity 2 -Source ${CmdletName} -DebugMessage

				return $Result
			}
			else {
				if ($ExitOnTimeout) {
					Write-Log -Message "Function [${CmdletName}] timed out, exit script with exit code [$configInstallationUIExitCode]." -Severity 2 -Source ${CmdletName}
					Exit-Script -ExitCode $configInstallationUIExitCode
				}
				else {
					Write-Log -Message "Function [${CmdletName}] timed out but `$ExitOnTimeout set to `$false. Continue..." -Severity 2 -Source ${CmdletName}
				}
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-InstallationProgress
Function Show-InstallationProgress {
	<#
	.SYNOPSIS
		Displays a progress dialog in a separate thread with an updateable custom message.
	.DESCRIPTION
		Create a WPF window in a separate thread to display a marquee style progress ellipse with a custom message that can be updated.
		The status message supports line breaks.
		The first time this function is called in a script, it will display a balloon tip notification to indicate that the installation has started (provided balloon tips are enabled in the configuration).
	.PARAMETER StatusMessage
		The status message to be displayed. The default status message is taken from the XML configuration file.
	.PARAMETER WindowLocation
		The location of the progress window. Default: center of the screen.
	.PARAMETER TopMost
		Specifies whether the progress window should be topmost. Default: $true.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Show-InstallationProgress
		Uses the default status message from the XML configuration file.
	.EXAMPLE
		Show-InstallationProgress -StatusMessage 'Installation in Progress...'
	.EXAMPLE
		Show-InstallationProgress -StatusMessage "Installation in Progress...`r`nThe installation may take 20 minutes to complete."
	.EXAMPLE
		Show-InstallationProgress -StatusMessage 'Installation in Progress...' -WindowLocation 'BottomRight' -TopMost $false
	.NOTES
		Modified to display a Toast Notification instead of a Windows Form, falls back to the original function if any error occurs.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$StatusMessage = $configProgressMessageInstall,
		[Parameter(Mandatory = $false)]
		[ValidateSet("Default", "BottomRight", "TopCenter")]
		[string]$WindowLocation = "Default",
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$TopMost = $true
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "InstallationProgress"
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	}
	Process {
		## Bypass if in silent mode
		if ($deployModeSilent) {
			Write-Log -Message "Bypassing function [${CmdletName}], because DeployMode [$deployMode]. Status message: $StatusMessage" -Severity 2 -Source ${CmdletName}
			return
		}
		else {
			Write-Log -Message "Executing function [${CmdletName}]. Status message: $StatusMessage" -Severity 2 -Source ${CmdletName}
			New-Variable -Name "InstallationProgressFunctionCalled" -Value $true -Scope Global -Force
		}

		## If the default progress message hasn't been overridden and the deployment type is uninstall, use the default uninstallation message
		if ($StatusMessage -eq $configProgressMessageInstall) {
			if ($deploymentType -eq "Uninstall") {
				$StatusMessage = $configProgressMessageUninstall
			}
			elseif ($deploymentType -eq "Repair") {
				$StatusMessage = $configProgressMessageRepair
			}
		}
		else {
			$ShowMessageGroup = $true
		}

		$deploymentTypeProgressMessage = switch ($deploymentType) {
			"Install" { $configProgressMessageInstall }
			"Uninstall" { $configProgressMessageUninstall }
			"Repair" { $configProgressMessageRepair }
			default { $configProgressMessageInstall }
		}


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			$XMLTemplate += '<toast duration="long">'
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
				[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
				[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
				if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
					Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
					$AppLogoOverrideImageDestinationPath.Refresh()
				}
				if ($AppLogoOverrideImageDestinationPath.Exists) {
					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title and message section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($installTitle))

			if ($configToastNotificationGeneralOptions.InstallationProgress_ShowIndeterminateProgressBar) {
				$XMLTemplate += '<progress value="indeterminate" valueStringOverride="" status=""/>'
			}

			$XMLTemplate += '<text placement="attribution">{attributionText}</text>'

			if ($ShowMessageGroup) {
				<#
				#  Split the status message in multiple lines and assign style if defined
				$StatusMessageLines = @()
				($StatusMessage -split '`r`n') | ForEach-Object { $StatusMessageLines += [PSCustomObject]@{StatusMessageLine = $_; StatusMessageStyle = "caption" } }

 				if ($configToastNotificationGeneralOptions.InstallationProgress_ChangeStylePerLine -and $StatusMessageLines.Count -gt 1) {
					for ($i = 0; $i -lt $StatusMessageLines.Count; $i++) {
						if ($i -eq 0) { $StatusMessageLines[$i].StatusMessageStyle = "base" }
						elseif ($i -eq 1) { $StatusMessageLines[$i].StatusMessageStyle = "caption" }
						else { $StatusMessageLines[$i].StatusMessageStyle = "captionSubtle" }
					}
				}
				#>

				#  Add group showing the message(s)
				$XMLTemplate += '<group>'
				$XMLTemplate += '<subgroup hint-textStacking="center">'
				<#
				$StatusMessageLines | ForEach-Object {
					$XMLTemplate += '<text hint-wrap="true" hint-style="{0}">{1}</text>' -f ( $_.StatusMessageStyle), ( [Security.SecurityElement]::Escape($_.StatusMessageLine))
				}
				#>
				if (($StatusMessage -split '`r`n').Count -gt 5) {
					$XMLTemplate += '<text hint-style="Caption" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($StatusMessage))
				}
				else {
					$XMLTemplate += '<text hint-style="Base" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($StatusMessage))
				}
				$XMLTemplate += '</subgroup>'
				$XMLTemplate += '</group>'
			}

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}

		## Sets the Toast Notification initial Notification Data
		[scriptblock]$SetToastNotificationInitialNotificationData = {
			#  Initial Notification Data
			$InitialDictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			if ($configFunctionOptions.ShowAttributionText -or $ShowMessageGroup) {
				$AttributionText = $deploymentTypeProgressMessage
			}
			else {
				$AttributionText = " "
			}

			$InitialDictionaryData.attributionText = [Security.SecurityElement]::Escape($AttributionText)
		}

		## Update Toast Notification if necessary
		[scriptblock]$UpdateToastNotificationData = {
			$DictionaryData = Invoke-Command -ScriptBlock $ToastNotificationNewDictionaryData

			$DictionaryData.attributionText = [Security.SecurityElement]::Escape($AttributionText)

			$ToastNotificationUpdateParameters = @{
				InvokedMethod  = "BackgroundKeep"
				Group          = $ToastNotificationGroup
				UpdateInterval = $configFunctionOptions.UpdateInterval
				DictionaryData = $DictionaryData
			}

			$null = Invoke-ToastNotificationAsUser @ToastNotificationUpdateParameters
		}
		#endregion


		## Create Working Directory temp folder to use
		$ResourceFolderCreated = New-ToastNotificationResourceFolder -ResourceFolder $ResourceFolder

		if ($ResourceFolderCreated) {
			## Test if the Toast Notification can be shown
			$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension

			if ($ToastNotificationExtensionTestResult) {
				#  Create and show the Toast Notification
				Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
			}
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Close-InstallationProgress
Function Close-InstallationProgress {
	<#
	.SYNOPSIS
		Wraps the original function but unregisters any event before.
	.DESCRIPTION
		Closes any dialog or notification created by Show-InstallationProgress.
		This function is called by the Exit-Script function to close a running instance of the progress dialog if found.
	.PARAMETER WaitingTime
		How many seconds to wait, at most, for the InstallationProgress window to be initialized, before the function returns, without closing anything. Range: 1 - 60  Default: 5
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Close-InstallationProgress
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateRange(1, 60)]
		[int]$WaitingTime = 2
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		if (-not $Global:InstallationProgressFunctionCalled) {
			Write-Log -Message "Bypassing function [${CmdletName}], no call to Show-InstallationProgress function registered." -Source ${CmdletName} -DebugMessage
			return
		}

		## Clear any previous displayed Toast Notification
		Clear-ToastNotificationHistory -Group "InstallationProgress"

		## Call original function
		Close-InstallationProgressOriginal @PSBoundParameters
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-BlockExecutionToastNotificationTemplate
Function New-BlockExecutionToastNotificationTemplate {
	<#
	.SYNOPSIS
		Create a new template with the data of the blocked processes
	.DESCRIPTION
		Create a new template with the data of the blocked processes
	.PARAMETER ProcessObjects
		An object passed by the parent function.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Show-WelcomePrompt -ProcessObjects $ProcessObjects
	.NOTES
		This is an internal script function and should typically not be called directly.
		It is used by the Block-AppExecution function.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[PSCustomObject[]]$ProcessObjects
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "BlockExecution"
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$blockExecutionTempPath = Join-Path -Path $dirAppDeployTemp -ChildPath "BlockExecution"
		$ResourceFolder = $blockExecutionTempPath
	}
	Process {
		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			$XMLTemplate = @()
			$XMLTemplate += '<toast duration="long">'
			$XMLTemplate += '<visual baseUri="file://{0}\">' -f ( <#0#> [Security.SecurityElement]::Escape($ResourceFolder))
			$XMLTemplate += '<binding template="ToastGeneric">'

			#  Hero image section
			if ($configFunctionOptions.ImageHeroShow -and -not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageHeroFileName)) {
				[IO.FileInfo]$HeroImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageHeroFileName
				[IO.FileInfo]$HeroImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageHeroFileName
				if ($HeroImageSourcePath.Exists -and -not $HeroImageDestinationPath.Exists) {
					Copy-File -Path $HeroImageSourcePath -Destination $HeroImageDestinationPath
					$HeroImageDestinationPath.Refresh()
				}
				if ($HeroImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="hero" src="{0}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($HeroImageDestinationPath.Name))
				}
			}

			#  AppLogoOverride image section
			if ($configFunctionOptions.ImageAppLogoOverrideShow) {
				if ($configFunctionOptions.ShowDialogIconAsAppLogoOverride) {
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_Lock.png"
					if (-not $AppLogoOverrideImageDestinationPath.Exists) {
						$AppLogoOverrideImageDestinationPath = Get-IconFromFile -SystemIcon Lock -SavePath $AppLogoOverrideImageDestinationPath -TargetSize $configToastNotificationGeneralOptions."IconSize_Biggest_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($configFunctionOptions.ImageAppLogoOverrideFileName)) {
					[IO.FileInfo]$AppLogoOverrideImageSourcePath = Join-Path -Path $dirToastNotificationExtSupportFiles -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName
					[IO.FileInfo]$AppLogoOverrideImageDestinationPath = Join-Path -Path $ResourceFolder -ChildPath $configFunctionOptions.ImageAppLogoOverrideFileName

					if ($AppLogoOverrideImageSourcePath.Exists -and -not $AppLogoOverrideImageDestinationPath.Exists) {
						Copy-File -Path $AppLogoOverrideImageSourcePath -Destination $AppLogoOverrideImageDestinationPath
						$AppLogoOverrideImageDestinationPath.Refresh()
					}

					if ($configFunctionOptions.ImageAppLogoOverrideCircularCrop) { $ImageCrop = ' hint-crop="circle"' }
				}

				if ($AppLogoOverrideImageDestinationPath.Exists) {
					$XMLTemplate += '<image placement="appLogoOverride" src="{0}"{1}/>' -f ( <#0#> [Security.SecurityElement]::Escape($AppLogoOverrideImageDestinationPath.Name)), ( <#1#> $ImageCrop)
				}
			}

			#  Title and message section
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($installTitle))
			$XMLTemplate += '<text>{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.BlockExecution_CloseMessage -f ( <#0#> $deploymentTypeName.ToLower())))

			#  Comment for future use, populated by Show-BlockExecutionToastNotification function
			$XMLTemplate += '<!-- blocked_process -->'

			$XMLTemplate += '<group>'

			if (-not $configFunctionOptions.ShowDialogIconAsAppLogoOverride -or -not $configFunctionOptions.ImageAppLogoOverrideShow) {
				#  Extract dialog icon from Windows library
				[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_Lock.png"
				if (-not $IconPath.Exists) {
					$IconPath = Get-IconFromFile -SystemIcon Lock -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
				}

				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
				}
				$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetStacking")
				$XMLTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetRemoveMargin").ToString().ToLower())
				$XMLTemplate += '</subgroup>'
				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
				}

				#  Collapse Dialogs Icons
				if ($configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
				}
				else {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
				}
			}
			else {
				$XMLTemplate += '<subgroup hint-textStacking="center">'
			}

			if ($ProcessObjects.Count -gt 1) {
				$BlockMessage = $configUIToastNotificationMessages.BlockExecution_BlockMessagePlural -f ( <#0#> $ProcessObjects.Count), ( <#0#> $deploymentTypeName.ToLower())
			}
			else {
				$BlockMessage = $configUIToastNotificationMessages.BlockExecution_BlockMessageSingular -f ( <#0#> $deploymentTypeName.ToLower())
			}

			$XMLTemplate += '<text hint-style="Caption" hint-wrap="true" hint-align="left">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($BlockMessage))
			$XMLTemplate += '</subgroup>'
			$XMLTemplate += '</group>'

			#  Blocked applications section
			if ($ProcessObjects.Count -gt 1) {
				$XMLTemplate += '<group>'
				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PreSpacing")
				}
				$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_TargetSize")
				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_PostSpacing")
				}
				if ($configFunctionOptions.CollapseDialogsIcons) {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSizeCollapsed")
				}
				else {
					$XMLTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.DialogsIconsSize)_BlockSize")
				}

				for ($i = 0; $i -lt $ProcessObjects.Count; $i++) {
					if ($i -lt 10) {
						if ([string]::IsNullOrWhiteSpace($ProcessObjects[$i].ProcessDescription)) {
							$ProcessMessage = "$($ProcessObjects[$i].ProcessName).exe"
						}
						else {
							$ProcessMessage = "$($ProcessObjects[$i].ProcessDescription) - ( $($ProcessObjects[$i].ProcessName).exe )"
						}
						$XMLTemplate += '<text hint-style="CaptionSubtle" hint-wrap="false" hint-align="left">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($ProcessMessage))
					}
					else {
						$RemainingProcesses = $ProcessObjects.Count - 1 - $i
						$XMLTemplate += '<text hint-style="CaptionSubtle" hint-wrap="false" hint-align="left">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($configUIToastNotificationMessages.BlockExecution_MoreApplicationsMessage -f ( <#0#> $RemainingProcesses)))
						break
					}
				}

				$XMLTemplate += '</subgroup>'
				$XMLTemplate += '</group>'
			}

			$XMLTemplate += '</binding>'
			$XMLTemplate += '</visual>'

			#  Audio section
			$XMLTemplate += '<audio src="{0}" loop="{1}" silent="{2}"/>' -f ( <#0#> [Security.SecurityElement]::Escape($configFunctionOptions.AudioSource)), ( <#1#> ($configFunctionOptions.AudioLoop).ToString().ToLower()), ( <#2#> ($configFunctionOptions.AudioSilent).ToString().ToLower())

			$XMLTemplate += '</toast>'
		}
		#endregion


		## Construct and save Toast Notification template
		try {
			#  Construct Toast Notification template
			Invoke-Command -ScriptBlock $DefineToastNotificationTemplate -NoNewScope

			#  Save template for debugging
			($scriptSeparator, $XMLTemplate, $scriptSeparator) | ForEach-Object { Write-Log -Message $_ -Source ${CmdletName} -DebugMessage }

			#  Export the Toast Notification template to file
			$XMLTemplatePath = Join-Path -Path $ResourceFolder -ChildPath $configToastNotificationGeneralOptions.BlockExecution_TemplateFileName

			$XMLTemplate | Out-File -FilePath $XMLTemplatePath -Force -ErrorAction Stop
		}
		catch {
			Write-Log -Message "Failed to export the Toast Notification template file [$XMLTemplatePath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Show-BlockExecutionToastNotification
Function Show-BlockExecutionToastNotification {
	<#
	.SYNOPSIS
		Shows a notification informing of the applications that are blocked.
	.DESCRIPTION
		Shows a notification informing of the applications that are blocked.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.NOTES
		This is an internal script function and should typically not be called directly.
		It is used when the -ShowBlockedAppDialog parameter is specified in the script, calleb by a blocked process.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Define function variables
		$ToastNotificationGroup = "BlockExecution"
		$configFunctionOptions = Get-Variable -Name "configToastNotification$($ToastNotificationGroup)Options" -ValueOnly
		$ResultVariable = "$($ToastNotificationGroup)_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		$ResourceFolder = $scriptRoot
	}
	Process {
		## Check if previously generated Toast Notification template exists
		[IO.FileInfo]$XMLTemplatePath = Join-Path -Path $ResourceFolder -ChildPath $configToastNotificationGeneralOptions.BlockExecution_TemplateFileName

		if (-not $XMLTemplatePath.Exists) {
			Write-Log -Message "Unable to locate Toast Notification template. Falling back to original function...`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

			#  Fallback to original function
			Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope
			return
		}


		#region Function reusable ScriptBlocks
		## Defines the Toast Notification template
		[scriptblock]$DefineToastNotificationTemplate = {
			try {
				#  Trying to parse the ToastNotification template as XML
				$XMLTemplate = Get-Content -Path $XMLTemplatePath -Raw

				if ($? -and $XMLTemplate.Length -eq 0) {
					Write-Log -Message "The Toast Notification template is empty." -Severity 2 -Source ${CmdletName}

					$XMLTemplate = $null
				}
				elseif (-not [string]::IsNullOrWhiteSpace($ReferredInstallName)) {
					#  Parse process template
					Invoke-Command -ScriptBlock $ConstructProcessTemplate -NoNewScope
				}
			}
			catch {
				Write-Log -Message "Unable to read Toast Notification template.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

				$XMLTemplate = $null
			}
		}

		## Complete the Toast Notification template with the blocked process information
		[scriptblock]$ConstructProcessTemplate = {
			#  Individual Applicaton icon and details group
			$ProcessTemplate = @()
			$ProcessTemplate += '<group>'

			#  Show Applications Icons
			if ($configFunctionOptions.ShowApplicationsIcons) {
				#  Extract individual application icon from process file
				[IO.FileInfo]$IconPath = Join-Path -Path $ResourceFolder -ChildPath "$([IO.Path]::GetFileNameWithoutExtension($ReferredInstallName)).png"
				if (([IO.FileInfo]$ReferredInstallName).Exists -and -not $IconPath.Exists) {
					$IconPath = Get-IconFromFile -Path $ReferredInstallName -SavePath $IconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
				}

				#  Use default no application icon if can´t get process icon
				if ($null -eq $IconPath -or -not $IconPath.Exists) {
					[IO.FileInfo]$NoIconPath = Join-Path -Path $ResourceFolder -ChildPath "$($ToastNotificationGroup)_noicon.png"
					if (-not $NoIconPath.Exists) {
						$NoIconPath = Get-IconFromFile -SystemIcon Application -SavePath $NoIconPath -TargetSize $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize" -DisableFunctionLogging -ErrorAction SilentlyContinue
					}
					$IconPath = $NoIconPath
				}

				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
					$ProcessTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PreSpacing")
				}
				$ProcessTemplate += '<subgroup hint-weight="{0}" hint-textStacking="{1}">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetSize"), ( <#1#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetStacking")
				$ProcessTemplate += '<image src="{0}" hint-removeMargin="{1}" hint-align="stretch"/>' -f ( <#0#> [Security.SecurityElement]::Escape($IconPath.Name)), ( <#1#> ($configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_TargetRemoveMargin").ToString().ToLower())
				$ProcessTemplate += '</subgroup>'
				if ($null -ne $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing" -and -not $configFunctionOptions.CollapseApplicationsIcons) {
					$ProcessTemplate += '<subgroup hint-weight="{0}"/>' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_PostSpacing")
				}

				#  Collapse Applications Icons
				if ($configFunctionOptions.CollapseApplicationsIcons) {
					$ProcessTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSizeCollapsed")
				}
				else {
					$ProcessTemplate += '<subgroup hint-weight="{0}" hint-textStacking="center">' -f ( <#0#> $configToastNotificationGeneralOptions."IconSize_$($configFunctionOptions.ApplicationsIconsSize)_BlockSize")
				}
			}
			else {
				$ProcessTemplate += '<subgroup hint-textStacking="center">'
			}

			#  Get information from blocked file trying to be executed
			$FileVersionInfo = Get-FileVersionInfo -Path $ReferredInstallName

			#  Show Process Description
			if ([string]::IsNullOrWhiteSpace($FileVersionInfo.FileDescription)) {
				$ProcessTemplate += '<text hint-style="Base" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape([IO.Path]::GetFileName($ReferredInstallName)))
			}
			else {
				$ProcessTemplate += '<text hint-style="Base" hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($FileVersionInfo.FileDescription))
				$ProcessTemplate += '<text hint-wrap="false">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape([IO.Path]::GetFileName($ReferredInstallName)))
			}

			#  Show Extended Applications Information
			if ($configFunctionOptions.ShowExtendedApplicationsInformation) {
				if (-not [string]::IsNullOrWhiteSpace($FileVersionInfo.CompanyName)) {
					$ProcessTemplate += '<text hint-style="CaptionSubtle" hint-wrap="true">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape($FileVersionInfo.CompanyName))
				}
				else {
					$ProcessTemplate += '<text hint-style="CaptionSubtle" hint-wrap="true" hint-maxLines="2">{0}</text>' -f ( <#0#> [Security.SecurityElement]::Escape([IO.Path]::GetDirectoryName($ReferredInstallName)))
				}
			}

			$ProcessTemplate += '</subgroup>'
			$ProcessTemplate += '</group>'

			#  Add current blocked application details
			$XMLTemplate = $XMLTemplate -replace "<!-- blocked_process -->", ($ProcessTemplate -join "")
		}
		#endregion


		## Test if the Toast Notification can be shown
		$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension

		if ($ToastNotificationExtensionTestResult) {
			#  Clear Installation Progress Toast Notification since cannot show both at the same time
			Clear-ToastNotificationHistory -Group "InstallationProgress"

			#  Create and show the Toast Notification
			Invoke-Command -ScriptBlock $ToastNotificationShowScriptBlock -NoNewScope
		}

		## Fallback to original function
		Invoke-Command -ScriptBlock $ToastNotificationFallbackToOriginalFunction -NoNewScope

		## Wait for 25 seconds and dismiss Block Execution Toast Notification if visible
		Start-Sleep -Seconds 25
		Clear-ToastNotificationHistory -Group $ToastNotificationGroup
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Block-AppExecution
Function Block-AppExecution {
	<#
	.SYNOPSIS
		Block the execution of an application(s)
	.DESCRIPTION
		This function is called when you pass the -BlockExecution parameter to the Stop-RunningApplications function. It does the following:
		1. Makes a copy of this script in a temporary directory on the local machine.
		2. Checks for an existing scheduled task from previous failed installation attempt where apps were blocked and if found, calls the Unblock-AppExecution function to restore the original IFEO registry keys.
		   This is to prevent the function from overriding the backup of the original IFEO options.
		3. Creates a scheduled task to restore the IFEO registry key values in case the script is terminated uncleanly by calling the local temporary copy of this script with the parameter -CleanupBlockedApps.
		4. Modifies the "Image File Execution Options" registry key for the specified process(s) to call this script with the parameter -ShowBlockedAppDialog.
		5. When the script is called with those parameters, it will display a custom message to the user to indicate that execution of the application has been blocked while the installation is in progress.
		   The text of this message can be customized in the XML configuration file.
	.PARAMETER ProcessName
		Name of the process or processes separated by commas
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Block-AppExecution -ProcessName ('winword','excel')
	.NOTES
		This is an internal script function and should typically not be called directly.
		It is used when the -BlockExecution parameter is specified with the Show-InstallationWelcome function to block applications.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		## Specify process names separated by commas
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[PSCustomObject[]]$ProcessObjects
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Bypass if no Admin rights
		if (-not $IsAdmin) {
			Write-Log -Message "Bypassing function [${CmdletName}], administrator rights are needed." -Severity 2 -Source ${CmdletName}
			return
		}

		## Block execution folder
		[IO.FileInfo]$blockExecutionTempPath = Join-Path -Path $dirAppDeployTemp -ChildPath "BlockExecution"

		$schTaskRenameBlockedAppsExists = $false

		## Delete this file if it exists as it can cause failures (it is a bug from an older version of the toolkit)
		if (Test-Path -LiteralPath "$configToolkitTempPath\PSAppDeployToolkit" -PathType Leaf -ErrorAction SilentlyContinue) {
			$null = Remove-Item -LiteralPath "$configToolkitTempPath\PSAppDeployToolkit" -Force -ErrorAction SilentlyContinue
		}

		if (Test-Path -Path $blockExecutionTempPath -PathType Container) {
			Remove-Folder -Path $blockExecutionTempPath
		}
		try {
			New-Folder -Path $blockExecutionTempPath -ContinueOnError $false
		}
		catch {
			return
		}

		Copy-Item -Path "$scriptRoot\*.*" -Destination $blockExecutionTempPath -Exclude "thumbs.db" -Force -Recurse -ErrorAction SilentlyContinue

		## Build the debugger block value script
		[string[]]$debuggerBlockScript = "strCommand = `"$($PSHome)\powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `" & chr(34) & `"$blockExecutionTempPath\$scriptFileName`" & chr(34) & `" -ShowBlockedAppDialog -AsyncToolkitLaunch -ReferredInstallTitle `" & chr(34) & `"$installTitle`" & chr(34) & `" -ReferredInstallName `" & chr(34) & WScript.Arguments(0) & chr(34) & `" -ReferredLogName `" & chr(34) & `"$logName`" & chr(34)"
		$debuggerBlockScript += 'set oWShell = CreateObject("WScript.Shell")'
		$debuggerBlockScript += 'oWShell.Run strCommand, 0, false'
		$debuggerBlockScript | Out-File -FilePath "$blockExecutionTempPath\AppDeployToolkit_BlockAppExecutionMessage.vbs" -Force -Encoding default -ErrorAction SilentlyContinue
		$debuggerBlockValue = "$envWinDir\System32\wscript.exe `"$blockExecutionTempPath\AppDeployToolkit_BlockAppExecutionMessage.vbs`""

		## Set contents to be readable for all users (BUILTIN\USERS)
		try {
			$Users = ConvertTo-NTAccountOrSID -SID "S-1-5-32-545"
			Set-ItemPermission -Path $blockExecutionTempPath -User $Users -Permission Read -Inheritance "ObjectInherit", "ContainerInherit"
		}
		catch {
			Write-Log -Message "Failed to set Read permissions on path [$blockExecutionTempPath]. The function might not be able to work correctly." -Severity 2 -Source ${CmdletName}
		}

		## Remove illegal characters from the scheduled task arguments string
		[char[]]$invalidScheduledTaskChars = '$', '!', '''', '"', '(', ')', ';', '\', '`', '*', '?', '{', '}', '[', ']', '<', '>', '|', '&', '%', '#', '~', '@', ' '
		[string]$SchInstallName = $installName
		foreach ($invalidChar in $invalidScheduledTaskChars) { $SchInstallName = $SchInstallName -replace [regex]::Escape($invalidChar), "" }
		$schTaskUnblockAppsCommand = "-ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File `"$blockExecutionTempPath\$scriptFileName`" -CleanupBlockedApps -ReferredInstallName `"$SchInstallName`" -ReferredInstallTitle `"$installTitle`" -ReferredLogName `"$logName`" -AsyncToolkitLaunch"
		$schTaskBlockedAppsName = $SchInstallName + "_BlockedApps"
		$schTaskRenameBlockedAppsName = "Restore_Image_File_Execution_Options_PSADTbackup"

		## Specify the scheduled task configuration
		$schTaskBlockedAppsParams = @{
			TaskName    = $schTaskBlockedAppsName
			Principal   = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -RunLevel Highest #NT AUTHORITY\SYSTEM
			Action      = New-ScheduledTaskAction -Execute "$($PSHome)\powershell.exe" -Argument $schTaskUnblockAppsCommand
			Description = "Scheduled task to run on startup to clean up blocked applications in case the installation is interrupted."
			Settings    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun
			Trigger     = New-ScheduledTaskTrigger -AtStartup
			Force       = $true
		}

		## Create a scheduled task to run on startup to call this script and clean up blocked applications in case the installation is interrupted, e.g. user shuts down during installation"
		Write-Log -Message "Creating scheduled task to cleanup blocked applications in case the installation is interrupted." -Source ${CmdletName}
		try {
			$null = Register-ScheduledTask @schTaskBlockedAppsParams
			if ($?) {
				Write-Log -Message "Successfully registered cleanup blocked applications scheduled task [$schTaskBlockedAppsName]." -Source ${CmdletName}
			}
		}
		catch {
			Write-Log -Message "Failed to register cleanup blocked applications scheduled task [$schTaskBlockedAppsName].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			return
		}

		[string[]]$blockProcessName = $ProcessObjects.ProcessName
		## Append .exe to match registry keys
		[string[]]$blockProcessName = $blockProcessName | ForEach-Object { $_ + ".exe" } -ErrorAction SilentlyContinue

		## Enumerate each process and set the debugger value to block application execution
		foreach ($blockProcess in $blockProcessName) {
			Write-Log -Message "Setting the Image File Execution Option registry key to block execution of [$blockProcess]." -Source ${CmdletName}

			$regKeyAppExecutionProcess = Join-Path -Path $regKeyAppExecution -ChildPath $blockProcess

			if (Test-Path -Path $regKeyAppExecutionProcess) {
				## Backing up existing Image File Execution Options
				if (-not (Test-Path -Path "$($regKeyAppExecutionProcess)_PSADTbackup" -ErrorAction SilentlyContinue)) {
					$null = Rename-Item -Path $regKeyAppExecutionProcess -NewName "$($blockProcess)_PSADTbackup" -Force
				}

				if (Test-Path -Path "$($regKeyAppExecutionProcess)_PSADTbackup" -ErrorAction SilentlyContinue) {
					#  Recreate the existing key but volatile
					New-RegistryKeyVolatile -Key $regKeyAppExecutionProcess -DeleteIfExist -DisableFunctionLogging

					#  Create a scheduled task to run on startup to rename and restore original Image File Execution Options
					if (-not $schTaskRenameBlockedAppsExists) {
						try {
							$schTaskRenameBlockedAppsCommand = "Get-Item -Path `"$(Join-Path -Path $regKeyAppExecution -ChildPath `"*`" -ErrorAction Stop)_PSADTbackup`" -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -Path (`$_.PSPath).Replace(`"_PSADTbackup`", `"`") -ErrorAction SilentlyContinue; Rename-Item -Path `$_.PSPath -NewName (Split-Path `$_.PSPath -Leaf).Replace(`"_PSADTbackup`", `"`") -ErrorAction SilentlyContinue }; Unregister-ScheduledTask -TaskName `"$schTaskRenameBlockedAppsName`" -Confirm:`$false"
							$schTaskRenameBlockedAppsParams = @{
								TaskName    = $schTaskRenameBlockedAppsName
								Principal   = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -RunLevel Highest #NT AUTHORITY\SYSTEM
								Action      = New-ScheduledTaskAction -Execute "$($PSHome)\powershell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($schTaskRenameBlockedAppsCommand)))"
								Description = "Scheduled task to run on startup to rename backed up blocked application Image File Execution Options."
								Trigger     = New-ScheduledTaskTrigger -AtStartup
								Force       = $true
							}

							$null = Register-ScheduledTask @schTaskRenameBlockedAppsParams

							if ($?) {
								Write-Log -Message "Successfully registered rename blocked applications IFEO scheduled task [$schTaskRenameBlockedAppsName]." -Source ${CmdletName} -DebugMessage
								$schTaskRenameBlockedAppsExists = $true
							}
						}
						catch {
							Write-Log -Message "Failed to register rename blocked applications IFEO scheduled task [$schTaskRenameBlockedAppsName].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						}
					}
				}
			}
			else {
				New-RegistryKeyVolatile -Key $regKeyAppExecutionProcess -DeleteIfExist -DisableFunctionLogging
			}

			Set-RegistryKey -Key $regKeyAppExecutionProcess -Name "Debugger" -Value $debuggerBlockValue -ContinueOnError $true
		}

		## Create Toast Notification template with blocked applications
		New-BlockExecutionToastNotificationTemplate -ProcessObjects $ProcessObjects
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Unblock-AppExecution
Function Unblock-AppExecution {
	<#
	.SYNOPSIS
		Unblocks the execution of applications performed by the Block-AppExecution function and deletes temporary files if succeeded
	.DESCRIPTION
		This function is called by the Exit-Script function or when the script itself is called with the parameters -CleanupBlockedApps
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Unblock-AppExecution
	.NOTES
		This is an internal script function and should typically not be called directly.
		It is used when the -BlockExecution parameter is specified with the Show-InstallationWelcome function to undo the actions performed by Block-AppExecution.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Bypass if no Admin rights
		if (-not $IsAdmin) {
			Write-Log -Message "Bypassing function [${CmdletName}], administrator rights are needed." -Source ${CmdletName}
			return
		}

		## ScriptBlock that get the blocked processes
		[scriptblock]$GetBlockedProcesses = {
			[psobject[]]$unblockProcesses = $null
			[psobject[]]$unblockProcesses = Get-ChildItem -Path $regKeyAppExecution -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty -Path $_.PSPath -Name "Debugger" -ErrorAction SilentlyContinue | Where-Object { $_.Debugger -like "*AppDeployToolkit_BlockAppExecutionMessage*" } }
		}

		## Remove Debugger values to unblock processes
		Invoke-Command -ScriptBlock $GetBlockedProcesses -NoNewScope
		foreach ($unblockProcess in $unblockProcesses) {
			Write-Log -Message "Removing the Image File Execution Options registry key to unblock execution of [$($unblockProcess.PSChildName)]." -Source ${CmdletName}
			$unblockProcess | Remove-ItemProperty -Name "Debugger" -Force -ErrorAction SilentlyContinue
		}

		## Deletes the scheduled task and temporary files if no blocked processes remain
		Invoke-Command -ScriptBlock $GetBlockedProcesses -NoNewScope

		#  Scheduled Task names
		[char[]]$invalidScheduledTaskChars = '$', '!', '''', '"', '(', ')', ';', '\', '`', '*', '?', '{', '}', '[', ']', '<', '>', '|', '&', '%', '#', '~', '@', ' '
		[string]$SchInstallName = $installName
		foreach ($invalidChar in $invalidScheduledTaskChars) { $SchInstallName = $SchInstallName -replace [regex]::Escape($invalidChar), "" }
		$schTaskBlockedAppsName = $SchInstallName + "_BlockedApps"
		$schTaskRenameBlockedAppsName = "Restore_Image_File_Execution_Options_PSADTbackup"

		if ($null -eq $unblockProcesses) {
			#  If block execution variable is $true, set it to $false
			if ($BlockExecution) {
				#  Make this variable globally available so we can check whether we need to call Unblock-AppExecution
				Set-Variable -Name "BlockExecution" -Value $false -Scope Script
			}

			#  Remove BlockAppExecution Schedule Task XML file
			[IO.FileInfo]$xmlSchTaskFilePath = "$dirAppDeployTemp\SchTaskUnBlockApps.xml"
			if ($xmlSchTaskFilePath.Exists) {
				Remove-Item -Path $xmlSchTaskFilePath
			}

			#  Remove BlockAppExection Temporary directory
			[IO.FileInfo]$blockExecutionTempPath = Join-Path -Path $dirAppDeployTemp -ChildPath "BlockExecution"
			if (Test-Path -LiteralPath $blockExecutionTempPath -PathType Container) {
				Remove-Folder -Path $blockExecutionTempPath
			}

			#  Get scheduled tasks
			try {
				$ScheduledTasks = Get-SchedulerTask -ContinueOnError $true
			}
			catch {
				Write-Log -Message "Error retrieving scheduled tasks.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}

			#  Remove the unblock scheduled task if it exists
			try {
				if ($ScheduledTasks | ForEach-Object { if ($_.TaskName -eq "\$schTaskBlockedAppsName") { $_.TaskName } }) {
					Write-Log -Message "Deleting Scheduled Task [$schTaskBlockedAppsName]." -Source ${CmdletName}
					Unregister-ScheduledTask -TaskName $schTaskBlockedAppsName -Confirm:$false
				}
			}
			catch {
				Write-Log -Message "Error deleting [$schTaskBlockedAppsName] Scheduled Task.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}

			#  Remove the restore scheduled task if it exists
			try {
				if ($ScheduledTasks | ForEach-Object { if ($_.TaskName -eq "\$schTaskRenameBlockedAppsName") { $_.TaskName } }) {
					Start-ScheduledTask -TaskName $schTaskRenameBlockedAppsName
					Write-Log -Message "Deleting Scheduled Task [$schTaskRenameBlockedAppsName]." -Source ${CmdletName}
					Unregister-ScheduledTask -TaskName $schTaskRenameBlockedAppsName -Confirm:$false
				}
			}
			catch {
				Write-Log -Message "Error deleting [$schTaskRenameBlockedAppsName] Scheduled Task.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}
		}
		else {
			Write-Log -Message "The following processes [$(($unblockProcesses.PSPath | Split-Path -Leaf -ErrorAction SilentlyContinue) -join ", ")] remain blocked, the scheduled task will retry hourly." -Severity 3 -Source ${CmdletName}

			$Triggers = @(
				$(New-ScheduledTaskTrigger -AtStartup),
				$(New-ScheduledTaskTrigger -AtLogOn),
				$(New-ScheduledTaskTrigger -Once -At 0am -RepetitionInterval (New-TimeSpan -Hours 1))
			)
			$null = Set-ScheduledTask -TaskName $schTaskBlockedAppsName -Trigger $Triggers -ErrorAction SilentlyContinue
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-ToastNotificationParameters
Function New-ToastNotificationParameters {
	<#
	.SYNOPSIS
		Constructs the variables array used by the user invokation function.
	.DESCRIPTION
		Constructs the variables array used by the user invokation function.
	.PARAMETER ResultVariable
		Result variable of the user environment where the result of the actions will be written.
	.PARAMETER Group
		Group variable used to identify different instances.
	.PARAMETER UpdateInterval
		Update interval in seconds.
	.PARAMETER DictionaryData
		Hashtable with notification data.
	.PARAMETER PoshWinRTLibraryPath
		Path to the PshWinRT Library.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ResultVariable,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Group,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$UpdateInterval,
		[Parameter(Mandatory = $false)]
		[PSCustomObject]$DictionaryData,
		[Parameter(Mandatory = $false)]
		[IO.FileInfo]$PoshWinRTLibraryPath
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Parameters used by Toast Notification invoked scriptblocks
		#  Toast Notification general variables
		$Parameters = @(
			"`$AppUserModelId = `"$($configToastNotificationAppId.AppId)`"",
			"`$Tag = `"$($configToastNotificationGeneralOptions.TaggingVariable)`""
		)

		#  Aditional general variables
		if ($Group -in ("WelcomePrompt", "DialogBox", "InstallationRestartPrompt", "InstallationPrompt")) {
			$Parameters += "[bool]`$SubscribeToEvents = [boolean]::Parse(`"$($configToastNotificationGeneralOptions.SubscribeToEvents)`")"
		}
		if ($PoshWinRTLibraryPath) {
			$Parameters += @(
				"`$PSVersionMajor = `$PSVersionTable.PSVersion.Major",
				"[IO.FileInfo]`$PoshWinRTLibraryPath = `"$($PoshWinRTLibraryPath)`""
			)
		}

		#  Toast Notification function specific variables
		if ($Group) {
			$Parameters += "`$Group = `"$($Group)`""
		}
		if ($ResultVariable) {
			$Parameters += "`$ResultVariable = `"$($ResultVariable)`""
		}
		if ($UpdateInterval) {
			$Parameters += "`$UpdateInterval = $($UpdateInterval)"
		}

		#  Toast Notification update data variables
		if ($DictionaryData) {
			$Parameters += @(
				"`$DictionaryDataRegexPattern = `"(?<type>[\S]+) (?<property>[\S]+)=(?<value>.+)`"",
				"`$DictionaryData = `"$(($DictionaryData | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Definition) -join "_item-separator_")`""
			)
		}

		return ($Parameters -join ";")
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Invoke-ToastNotificationAsUser
Function Invoke-ToastNotificationAsUser {
	<#
	.SYNOPSIS
		Shows and Updates the Toast Notification as active user.
	.DESCRIPTION
		Shows and Updates the Toast Notification as active user.
	.PARAMETER ResultVariable
		Result variable of the user environment where the result of the actions will be written.
	.PARAMETER Group
		Group variable used to identify different instances.
	.PARAMETER ToastNotificationTemplate
		Toast Notification template as an array.
	.PARAMETER AllowedResults
		Allowed Toast Notification action results.
	.PARAMETER DismissedResults
		Results considered dismissed by the user.
	.PARAMETER UpdateInterval
		Update interval in seconds.
	.PARAMETER DictionaryData
		Hashtable with notification data.
	.PARAMETER InvokedMethod
		Different invoke method types.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Can be the Process Id of the invoked method or any result in the arrays.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ResultVariable,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Group,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[array]$ToastNotificationTemplate,
		[Parameter(Mandatory = $false)]
		[array]$AllowedResults,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[array]$DismissedResults,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int32]$UpdateInterval,
		[Parameter(Mandatory = $false)]
		[PSCustomObject]$DictionaryData,
		[ValidateSet("Show", "Update", "BackgroundKeep")]
		[string]$InvokedMethod
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Reusable ScriptBlocks bodies invoked as active user
		[scriptblock]$InvokedToastNotificationShowBody = {
			Function Set-ResultVariable {
				<#
				.SYNOPSIS
					Sets a result value given as parameter to the result variable.
				.DESCRIPTION
					Sets a result value given as parameter to the result variable.
					Used by all Toast Notification functions that require a result.
				.PARAMETER ResultValue
					Value assigned to the environment Result Variable.
				.INPUTS
					None
					You cannot pipe objects to this function.
				.OUTPUTS
					None
					This function does not generate any output.
				.EXAMPLE
					Test-ToastNotificationVisible -Group 'DialogBox'
				.NOTES
					This is an internal script function and should typically not be called directly.
					Author: Leonardo Franco Maragna
					Part of Toast Notification Extension
				.LINK
					https://github.com/LFM8787/PSADT.ToastNotification
				#>
				[CmdletBinding()]
				Param (
					[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
					[string]$ResultValue
				)

				[Environment]::SetEnvironmentVariable($ResultVariable, $ResultValue, "User")
			}
			Function Test-ToastNotificationVisible {
				<#
				.SYNOPSIS
					Determines if the previously raised notification is visible.
				.DESCRIPTION
					Determines if the previously raised notification is visible.
					Used by all Toast Notification functions that raise a notification.
				.PARAMETER AppUserModelId
					Identifier of the application that raises the notification.
				.PARAMETER Group
					Group variable used to identify different instances.
				.PARAMETER Tag
					Tag variable used to identify different instances.
				.INPUTS
					None
					You cannot pipe objects to this function.
				.OUTPUTS
					System.Boolean
					Returns $true if the Toast Notification is visible.
				.EXAMPLE
					Test-ToastNotificationVisible -Group 'DialogBox'
				.NOTES
					This is an internal script function and should typically not be called directly.
					Author: Leonardo Franco Maragna
					Part of Toast Notification Extension
				.LINK
					https://github.com/LFM8787/PSADT.ToastNotification
				#>
				[CmdletBinding()]
				Param (
					[Parameter(Mandatory = $false)]
					[ValidateNotNullorEmpty()]
					[string]$Group
				)

				## Prepare a filter for Where-Object
				[scriptblock]$whereObjectFilter = {
					if (($Group -and $Tag)) { if (($_.Group -eq $Group) -and ($_.Tag -eq $Tag)) { return $true } }
					elseif ($Group) { if ($_.Group -eq $Group) { return $true } }
					elseif ($Tag) { if ($_.Tag -eq $Tag) { return $true } }
					return $false
				}

				## Trying to determinate if the Toast Notification is visible
				try {
					$ToastNotificationVisible = [Windows.UI.Notifications.ToastNotificationManager]::History.GetHistory($AppUserModelId) | Where-Object -FilterScript $whereObjectFilter

					if ($ToastNotificationVisible) {
						return $true
					}
					else {
						return $false
					}
				}
				catch {
					return $false
				}
			}
			Function Register-WrappedToastNotificationEvent {
				<#
				.SYNOPSIS
					Register a WinRT event by wrapping it in a compatible object.
				.DESCRIPTION
					Register a WinRT event by wrapping it in a compatible object.
					Used by all Toast Notification functions that require a result.
				.PARAMETER Target
					Toast Notification object to which events will be wrapped.
				.PARAMETER EventName
					Triggering event.
				.INPUTS
					None
					You cannot pipe objects to this function.
				.OUTPUTS
					None
					This function does not generate any output.
				.EXAMPLE
					Register-WrappedToastNotificationEvent -Target $ToastNotificationObject -EventName 'Activated'
				.NOTES
					This is an internal script function and should typically not be called directly.
					Author: Leonardo Franco Maragna
					Part of Toast Notification Extension
				.LINK
					https://github.com/LFM8787/PSADT.ToastNotification
				#>
				[CmdletBinding()]
				Param (
					[Parameter(Mandatory = $true)]
					[Windows.UI.Notifications.ToastNotification]$Target,
					[Parameter(Mandatory = $true)]
					[ValidateSet("Activated", "Dismissed", "Failed")]
					[string]$EventName
				)

				## Wrap WinRT Event based in the event name
				switch ($EventName) {
					"Activated" { $EventType = "System.Object" }
					"Dismissed" { $EventType = "Windows.UI.Notifications.ToastDismissedEventArgs" }
					"Failed" { $EventType = "Windows.UI.Notifications.ToastFailedEventArgs" }
				}

				$EventWrapper = New-Object "PoshWinRT.EventWrapper[Windows.UI.Notifications.ToastNotification,$($EventType)]"
				$EventWrapper.Register($Target, $EventName)
			}
			Function Register-ToastNotificationEvents {
				<#
				.SYNOPSIS
					Registers the events triggered by the notification.
				.DESCRIPTION
					Registers the events triggered by the notification.
					Used by all Toast Notification functions that require a result.
				.PARAMETER ToastNotificationObject
					Toast Notification object to which events will be registered.
				.PARAMETER ResultVariable
					Result variable of the user environment where the result of the actions will be written.
				.INPUTS
					None
					You cannot pipe objects to this function.
				.OUTPUTS
					System.String
					Returns a string with the esception if any error occur.
				.EXAMPLE
					Register-ToastNotificationEvents -ToastNotificationObject $ToastNotificationObject -ResultVariable 'DialogBox_1234_Result'
				.NOTES
					This is an internal script function and should typically not be called directly.
					Author: Leonardo Franco Maragna
					Part of Toast Notification Extension
				.LINK
					https://github.com/LFM8787/PSADT.ToastNotification
				#>
				[CmdletBinding()]
				Param (
					[Parameter(Mandatory = $true)]
					[Windows.UI.Notifications.ToastNotification]$ToastNotificationObject,
					[Parameter(Mandatory = $true)]
					[ValidateNotNullorEmpty()]
					[string]$ResultVariable
				)

				## Wrap WinRT event using PoshWinRt.dll
				try {
					if ([int]$PSVersionMajor -lt 7) {
						$EventActivated = [PSCustomObject]@{ InputObject = Register-WrappedToastNotificationEvent -Target $ToastNotificationObject -EventName "Activated"; EventName = "FireEvent" }
						$EventDismissed = [PSCustomObject]@{ InputObject = Register-WrappedToastNotificationEvent -Target $ToastNotificationObject -EventName "Dismissed"; EventName = "FireEvent" }
						$EventFailed = [PSCustomObject]@{ InputObject = Register-WrappedToastNotificationEvent -Target $ToastNotificationObject -EventName "Failed"; EventName = "FireEvent" }
					}
					else {
						$EventActivated = [PSCustomObject]@{ InputObject = $ToastNotificationObject; EventName = "Activated" }
						$EventDismissed = [PSCustomObject]@{ InputObject = $ToastNotificationObject; EventName = "Dismissed" }
						$EventFailed = [PSCustomObject]@{ InputObject = $ToastNotificationObject; EventName = "Failed" }
					}
				}
				catch {
					return "3:Register-ToastNotificationEvents,Unable to wrap Toast Notification WinRT Events: $($_.Exception.Message)"
				}

				## Trying to register the (wrapped) events
				try {
					#  Saves the result as user environment variable in the registry
					$null = Register-ObjectEvent -SourceIdentifier "$($ResultVariable)_Activated" -InputObject $EventActivated.InputObject -MessageData $ResultVariable -EventName $EventActivated.EventName -Action {
						$ResultVariable = $Event.MessageData

						$ResultValue = [string]($Event.SourceArgs[1].Result.Arguments).Replace("$($ResultVariable)?", "")

						[Environment]::SetEnvironmentVariable($ResultVariable, $ResultValue, "User")
					}
					$null = Register-ObjectEvent -SourceIdentifier "$($ResultVariable)_Dismissed" -InputObject $EventDismissed.InputObject -MessageData $ResultVariable -EventName $EventDismissed.EventName -Action {
						$ResultVariable = $Event.MessageData

						[string]$ResultValue = $Event.SourceArgs[1].Result.Reason

						[Environment]::SetEnvironmentVariable($ResultVariable, $ResultValue, "User")
					}
					$null = Register-ObjectEvent -SourceIdentifier "$($ResultVariable)_Failed" -InputObject $EventFailed.InputObject -MessageData $ResultVariable -EventName $EventFailed.EventName -Action {
						$ResultVariable = $Event.MessageData

						[string]$ResultValue = $Event.SourceArgs[1].Result.ErrorCode

						[Environment]::SetEnvironmentVariable($ResultVariable, $ResultValue, "User")
					}
				}
				catch {
					return "3:Register-ToastNotificationEvents,Unable to register Toast Notification Events: $($_.Exception.Message)"
				}

				## Verify if the Events were registered
				$EventJobs = Get-Job | Where-Object { $_.Name -like "$($ResultVariable)_*" }

				if (-not $EventJobs) {
					return "3:Register-ToastNotificationEvents,No registered Toast Notification Events found."
				}
			}

			## Trying to load required library
			if ($SubscribeToEvents) {
				if ([int]$PSVersionMajor -lt 7) {
					if ($null -ne $PoshWinRTLibraryPath) {
						try {
							$null = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($PoshWinRTLibraryPath))
						}
						catch {
							Set-ResultVariable "3:[Assembly]::Load(),Unable to load required library to subscribe to Toast Notification Events in Powershell versions below 7: $($_.Exception.Message)"
							return
						}
					}
					else {
						Set-ResultVariable "3:[Assembly]::Load(),To subscribe to Toast Notification Events in Powershell versions below 7, the required PoshWinRT.dll library must be located under [..\SupportFiles\PSADT.ToastNotification\] directory."
						return
					}
				}
			}

			## Trying to parse the Toast Notification template as XML
			try {
				$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
				$XMLObject = [Windows.Data.Xml.Dom.XmlDocument]::New()
				$XMLObject.LoadXml($XMLTemplate)
			}
			catch {
				Set-ResultVariable "3:[XmlDocument]::New().LoadXml(),$($_.Exception.Message)"
				return
			}

			## New Toast Notification object
			try {
				$null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
				$ToastNotificationObject = [Windows.UI.Notifications.ToastNotification]::New($XMLObject)
				$ToastNotificationObject.Tag = $Tag
				$ToastNotificationObject.Group = $Group
			}
			catch {
				Set-ResultVariable "3:[ToastNotification]::New(),$($_.Exception.Message)"
				return
			}

			## Initial Notification Data
			try {
				$Dictionary = [System.Collections.Generic.Dictionary[String, String]]::New()

				if (-not [string]::IsNullOrWhiteSpace($DictionaryData)) {
					$DictionaryData -split "_item-separator_" | ForEach-Object {
						if ($_ -match $DictionaryDataRegexPattern) {
							if ($Matches["type"] -in ("double", "float", "single")) { $Value = "$($Matches["value"])" -replace ",", "." } else { $Value = "$($Matches["value"])" }
							$Dictionary.Add("$($Matches["property"])", $Value)
						}
					}
				}

				$null = [Windows.UI.Notifications.NotificationData, Windows.UI.Notifications, ContentType = WindowsRuntime]
				$ToastNotificationObject.Data = [Windows.UI.Notifications.NotificationData]::New($Dictionary)
				$ToastNotificationObject.Data.SequenceNumber = 1
			}
			catch {
				Set-ResultVariable "3:[NotificationData]::New(),$($_.Exception.Message)"
				return
			}

			## Register Toast Notification Events
			if ($SubscribeToEvents) {
				$RegisterToastNotificationEventsResult = Register-ToastNotificationEvents -ToastNotificationObject $ToastNotificationObject -ResultVariable $ResultVariable

				if ($RegisterToastNotificationEventsResult -like "3:*") {
					Set-ResultVariable $RegisterToastNotificationEventsResult
					return
				}
			}

			## Show Toast Notification
			try {
				$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
				$null = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppUserModelId).Show($ToastNotificationObject)

				if ($? -and (Test-ToastNotificationVisible -Group $Group)) {
					Set-ResultVariable "$([System.Diagnostics.Process]::GetCurrentProcess().Id)"

					do {
						Start-Sleep -Milliseconds ($UpdateInterval * 1000 / 2)
					}
					while (Test-ToastNotificationVisible -Group $Group)
				}
			}
			catch {
				Set-ResultVariable "3:[ToastNotificationManager]::CreateToastNotifier().Show(),$($_.Exception.Message)"
				return
			}
		}

		[scriptblock]$InvokedToastNotificationUpdateBody = {
			## Update Notification Data
			try {
				$Dictionary = [System.Collections.Generic.Dictionary[String, String]]::New()

				$DictionaryData -split "_item-separator_" | ForEach-Object {
					if ($_ -match $DictionaryDataRegexPattern) {
						if ($Matches["type"] -in ("double", "float", "single")) { $Value = "$($Matches["value"])" -replace ",", "." } else { $Value = "$($Matches["value"])" }
						$Dictionary.Add("$($Matches["property"])", $Value)
					}
				}

				$null = [Windows.UI.Notifications.NotificationData, Windows.UI.Notifications, ContentType = WindowsRuntime]
				$NotificationData = [Windows.UI.Notifications.NotificationData]::New($Dictionary)
				$NotificationData.SequenceNumber = 2
			}
			catch {
				return "3:[NotificationData]::New(),$($_.Exception.Message)"
			}

			## Update Toast Notification object
			try {
				$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
				$NotificationUpdateResult = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppUserModelId).Update($NotificationData, $Tag, $Group)

				switch ($NotificationUpdateResult) {
					"Succeeded" { return "1:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)" }
					"NotificationNotFound" { return "2:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)" }
					"Failed" { return "3:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)" }
					Default { throw "The Toast Notification Update Result [$NotificationUpdateResult] is unexpected." }
				}
			}
			catch {
				return "3:[ToastNotificationManager]::CreateToastNotifier().Update(),$($_.Exception.Message)"
			}
		}

		[scriptblock]$InvokedToastNotificationBackgroundKeepBody = {
			Function Test-ToastNotificationVisible {
				<#
				.SYNOPSIS
					Determines if the previously raised notification is visible.
				.DESCRIPTION
					Determines if the previously raised notification is visible.
					Used by all Toast Notification functions that raise a notification.
				.PARAMETER AppUserModelId
					Identifier of the application that raises the notification.
				.PARAMETER Group
					Group variable used to identify different instances.
				.PARAMETER Tag
					Tag variable used to identify different instances.
				.INPUTS
					None
					You cannot pipe objects to this function.
				.OUTPUTS
					System.Boolean
					Returns $true if the Toast Notification is visible.
				.EXAMPLE
					Test-ToastNotificationVisible -Group 'DialogBox'
				.NOTES
					This is an internal script function and should typically not be called directly.
					Author: Leonardo Franco Maragna
					Part of Toast Notification Extension
				.LINK
					https://github.com/LFM8787/PSADT.ToastNotification
				#>
				[CmdletBinding()]
				Param (
					[Parameter(Mandatory = $false)]
					[ValidateNotNullorEmpty()]
					[string]$Group
				)

				## Prepare a filter for Where-Object
				[scriptblock]$whereObjectFilter = {
					if (($Group -and $Tag)) { if (($_.Group -eq $Group) -and ($_.Tag -eq $Tag)) { return $true } }
					elseif ($Group) { if ($_.Group -eq $Group) { return $true } }
					elseif ($Tag) { if ($_.Tag -eq $Tag) { return $true } }
					return $false
				}

				## Trying to determinate if the Toast Notification is visible
				try {
					$ToastNotificationVisible = [Windows.UI.Notifications.ToastNotificationManager]::History.GetHistory($AppUserModelId) | Where-Object -FilterScript $whereObjectFilter

					if ($ToastNotificationVisible) {
						return $true
					}
					else {
						return $false
					}
				}
				catch {
					return $false
				}
			}

			## Load required assemblies
			$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
			$null = [Windows.UI.Notifications.NotificationData, Windows.UI.Notifications, ContentType = WindowsRuntime]

			do {
				## Update Notification Data
				try {
					$Dictionary = [System.Collections.Generic.Dictionary[String, String]]::New()

					$DictionaryData -split "_item-separator_" | ForEach-Object {
						if ($_ -match $DictionaryDataRegexPattern) {
							$Dictionary.Add("$($Matches["property"])", "$($Matches["value"])$(" "*(Get-Random -Minimum 1 -Maximum 6))")
						}
					}

					$NotificationData = [Windows.UI.Notifications.NotificationData]::New($Dictionary)
					$NotificationData.SequenceNumber = 2
				}
				catch {
					$Return = "3:[NotificationData]::New(),$($_.Exception.Message)"; break
				}

				#  Update Toast Notification object
				try {
					$NotificationUpdateResult = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppUserModelId).Update($NotificationData, $Tag, $Group)

					switch ($NotificationUpdateResult) {
						"Succeeded" { $Return = "1:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)" }
						"NotificationNotFound" { $Return = "2:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)"; break }
						"Failed" { $Return = "3:[ToastNotificationManager]::CreateToastNotifier().Update(),$($NotificationUpdateResult)"; break }
						Default { throw "The Toast Notification Update Result [$NotificationUpdateResult] is unexpected." }
					}
				}
				catch {
					$Return = "3:[ToastNotificationManager]::CreateToastNotifier().Update(),$($_.Exception.Message)"; break
				}

				#  Wait a few seconds before reupdate
				Start-Sleep -Seconds $UpdateInterval
			}
			while (Test-ToastNotificationVisible -Group $Group)

			return $Return
		}

		## Shows and Updates the Toast Notification as active user
		if ($InvokedMethod -eq "Show") {
			#  Reset function result variable and remove any logged user environment result variable
			$Return = $null
			Remove-ToastNotificationResult -ResultVariable $ResultVariable -IncludeOriginalPID $true

			#  Clear any previous displayed Toast Notification
			Clear-ToastNotificationHistory -Group $Group

			#  Copy required file to subscribe to events
			if ($Group -in ("WelcomePrompt", "DialogBox", "InstallationRestartPrompt", "InstallationPrompt") -and $configToastNotificationGeneralOptions.SubscribeToEvents) {
				if ([int]$envPSVersionMajor -lt 7) {
					if ($null -ne $envPoshWinRTLibraryPath) {
						$PoshWinRTLibrarySourcePath = $envPoshWinRTLibraryPath
						$PoshWinRTLibraryDestinationPath = Join-Path -Path $ResourceFolder -ChildPath (Split-Path -Path $PoshWinRTLibrarySourcePath -Leaf)

						try {
							Copy-File -Path $PoshWinRTLibrarySourcePath -Destination $PoshWinRTLibraryDestinationPath -ContinueOnError $false
						}
						catch {
							$configToastNotificationGeneralOptions.SubscribeToEvents = $false
							Write-Log -Message "Unable to load required library to subscribe to Toast Notification Events in Powershell versions below 7.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
							return "RetryWithProtocol"
						}
					}
					else {
						Write-Log -Message "To subscribe to Toast Notification Events in Powershell versions below 7, the required PoshWinRT.dll library must be located under [..\SupportFiles\PSADT.ToastNotification\] directory." -Severity 2 -Source ${CmdletName}
						$configToastNotificationGeneralOptions.SubscribeToEvents = $false
						return "RetryWithProtocol"
					}
				}

				$PoshWinRTParameter = @{
					PoshWinRTLibraryPath = $PoshWinRTLibraryDestinationPath
				}
			}

			#  Creates the ScriptBlock with parameters
			$InvokedToastNotificationParameters = New-ToastNotificationParameters -ResultVariable $ResultVariable -Group $Group -UpdateInterval $UpdateInterval -DictionaryData $DictionaryData @PoshWinRTParameter
			$InvokedToastNotification = [scriptblock]::Create(((('[string]$XMLTemplate = ''{0}''' -f ($ToastNotificationTemplate -join "")), $InvokedToastNotificationParameters, $InvokedToastNotificationShowBody.ToString()) -join ";"))

			try {
				#  Invokes Toast Notification ScriptBlock as Active user
				$null = Invoke-ProcessAsActiveUser -ScriptBlock $InvokedToastNotification -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging

				#  Loops until get the Process Id as result
				for ($i = 1; $i -le $configToastNotificationGeneralOptions.ShowToastNotificationAsyncTimeout; $i++) {
					Start-Sleep -Seconds 1

					$InvokedToastNotificationResult = Get-ToastNotificationResult -ResultVariable $ResultVariable -GetInvokedPID

					if ($InvokedToastNotificationResult -match "^\d+$") {
						#  Received the Process Id
						$Return = $InvokedToastNotificationResult
						break
					}
					elseif (-not [string]::IsNullOrWhiteSpace($InvokedToastNotificationResult)) {
						#  Received something different to the Process Id
						if (($AllowedResults -and $InvokedToastNotificationResult -in $AllowedResults) -or ($InvokedToastNotificationResult -in $DismissedResults)) {
							#  Catch fast user interaction before Result loop

							#  Clear any previous displayed Toast Notification
							Clear-ToastNotificationHistory -Group $Group

							$Return = $InvokedToastNotificationResult
							break
						}
						elseif ($InvokedToastNotificationResult -match "(?<Severity>\d):(?<Method>[\S]+),(?<Description>.+)") {
							#  Received a expected formatted string
							$ReturnSeverity = $Matches["Severity"]
							$ReturnMethod = $Matches["Method"]
							$ReturnDescription = $Matches["Description"]


							if ($ReturnSeverity -eq 1) {
								#  Received a expected formatted information string
								Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName} -DebugMessage
							}
							elseif ($ReturnSeverity -eq 2) {
								#  Received a expected formatted warning string
								Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName} -DebugMessage
							}
							elseif ($ReturnSeverity -eq 3) {
								#  Received a expected formatted error string
								Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName}

								if ($ReturnMethod -in ("Register-ToastNotificationEvents", "[Assembly]::Load()")) {
									#  If Subscription failed, try with Protocol
									if ($configToastNotificationGeneralOptions.SubscribeToEvents) {
										$configToastNotificationGeneralOptions.SubscribeToEvents = $false

										#  Test if the Toast Notification can be shown
										$ToastNotificationExtensionTestResult = Test-ToastNotificationExtension -CheckProtocol

										if ($ToastNotificationExtensionTestResult) {
											Invoke-Command -ScriptBlock $SetSubscribeToEventsProperties -NoNewScope
											$Return = "RetryWithProtocol"
										}
									}
									break
								}
							}
						}

						#  Received an unexpected output from the invokation
						throw "Unexpected result [$InvokedToastNotificationResult] given by the Toast Notification."
					}
					else {
						Write-Log -message "Trying to obtain the invoked PID running as user, try $($i) of $($configToastNotificationGeneralOptions.ShowToastNotificationAsyncTimeout)..." -Severity 2 -Source ${CmdletName} -DebugMessage
					}

					if ($i -eq $configToastNotificationGeneralOptions.ShowToastNotificationAsyncTimeout) {
						throw "No invoked PID received in [$i] seconds."
					}
				}
			}
			catch {
				Write-Log -Message "Unable to show Toast Notification.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}

			return $Return
		}
		elseif ($InvokedMethod -eq "Update") {
			#  Creates the ScriptBlock with parameters
			$InvokedToastNotificationParameters = New-ToastNotificationParameters -Group $Group -DictionaryData $DictionaryData
			$InvokedToastNotification = [scriptblock]::Create((($InvokedToastNotificationParameters, $InvokedToastNotificationUpdateBody.ToString()) -join ";"))

			try {
				#  Invokes Toast Notification ScriptBlock as Active user
				[string]$InvokedToastNotificationResult = Invoke-ProcessAsActiveUser -ScriptBlock $InvokedToastNotification -CaptureOutput -Wait -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging

				if ($InvokedToastNotificationResult -match "(?<Severity>\d):(?<Method>[\S]+),(?<Description>.+)") {
					#  Received a expected formatted string
					$ReturnSeverity = $Matches["Severity"]
					$ReturnMethod = $Matches["Method"]
					$ReturnDescription = $Matches["Description"]

					if ($ReturnSeverity -eq 1) {
						#  Received a expected formatted information string
						Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName} -DebugMessage
					}
					elseif ($ReturnSeverity -eq 2) {
						#  Received a expected formatted warning string
						Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName} -DebugMessage
					}
					elseif ($ReturnSeverity -eq 3) {
						#  Received a expected formatted error string
						Write-Log -Message "$($ReturnMethod): $($ReturnDescription)" -Severity $ReturnSeverity -Source ${CmdletName}
					}
				}
			}
			catch {
				Write-Log -Message "Unable to update Toast Notification.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}
		}
		elseif ($InvokedMethod -eq "BackgroundKeep") {
			#  Creates the ScriptBlock with parameters
			$InvokedToastNotificationParameters = New-ToastNotificationParameters -Group $Group -DictionaryData $DictionaryData -UpdateInterval $UpdateInterval
			$InvokedToastNotification = [scriptblock]::Create((($InvokedToastNotificationParameters, $InvokedToastNotificationBackgroundKeepBody.ToString()) -join ";"))

			try {
				#  Invokes Toast Notification ScriptBlock as Active user
				Invoke-ProcessAsActiveUser -ScriptBlock $InvokedToastNotification -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging
			}
			catch {
				Write-Log -Message "Unable to keep Toast Notification updated in background.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-ToastNotificationResourceFolder
Function New-ToastNotificationResourceFolder {
	<#
	.SYNOPSIS
		Creates a folder where the icons and library will be located.
	.DESCRIPTION
		Creates a folder where the icons and library will be located.
	.PARAMETER ResourceFolder
		Base directory where the icons and library will be located.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the folder could be created.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$ResourceFolder = $configToastNotificationGeneralOptions.ResourceFolder
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		$Result = $false

		## Create Working Directory temp folder to use
		if (-not (Test-Path -Path $ResourceFolder -PathType Container)) {
			try {
				New-Folder -Path $ResourceFolder -ContinueOnError $false
				if ($IsAdmin) {
					$null = Remove-FolderAfterReboot -Path (Split-Path -Path $ResourceFolder -Parent) -ContinueOnError $true -DisableFunctionLogging
				}
			}
			catch {
				Write-Log -Message "Unable to create Toast Notification resource folder [$ResourceFolder].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

				return $Result
			}
		}

		if (Test-Path -Path $ResourceFolder -PathType Container) {
			$Result = $true

			## Set contents to be readable for all users (BUILTIN\USERS)
			if ($IsAdmin) {
				try {
					$Users = ConvertTo-NTAccountOrSID -SID "S-1-5-32-545"
					$null = Set-ItemPermission -Path $ResourceFolder -User $Users -Permission Read -Inheritance "ObjectInherit", "ContainerInherit"
				}
				catch {
					Write-Log -Message "Failed to set Read permissions on path [$ResourceFolder]. The images and icons might not be shown correctly." -Severity 2 -Source ${CmdletName}
				}
			}
		}

		return $Result
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-ToastNotificationAppId
Function New-ToastNotificationAppId {
	<#
	.SYNOPSIS
		Registers the application identifier in registry.
	.DESCRIPTION
		Registers the application identifier in registry.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER DisplayName
		Name that is displayed in the notifications.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.PARAMETER IconUri
		Path of the icon showed in the application identifier.
	.PARAMETER IconBackgroundColor
		Icon background color.
	.PARAMETER LaunchUri
		URI launched when clicked the notification.
	.PARAMETER ShowInSettings
		Determines if notifications should be shown in Settings.
	.PARAMETER AllowContentAboveLock
		Determines if notifications should show its content on lock screen.
	.PARAMETER ShowInActionCenter
		Determines if notifications should be displayed in the Action Center.
	.PARAMETER RegistrySubTree
		Registry subtree to use to register the application identifier.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$DisplayName = $configToastNotificationAppId.DisplayName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId,
		[Parameter(Mandatory = $false)]
		[string]$IconUri = $configToastNotificationAppId.IconUri,
		[Parameter(Mandatory = $false)]
		[string]$IconBackgroundColor = $configToastNotificationAppId.IconBackgroundColor,
		[Parameter(Mandatory = $false)]
		[string]$LaunchUri = $configToastNotificationAppId.LaunchUri,
		[Parameter(Mandatory = $false)]
		[bool]$ShowInSettings = $configToastNotificationAppId.ShowInSettings,
		[Parameter(Mandatory = $false)]
		[bool]$AllowContentAboveLock = $configToastNotificationAppId.AllowContentAboveLock,
		[Parameter(Mandatory = $false)]
		[bool]$ShowInActionCenter = $configToastNotificationAppId.ShowInActionCenter,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Try to register the application identifier options
		try {
			$NotificationsRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$($AppUserModelId)"
			New-RegistryKeyVolatile -Key $NotificationsRegistryPath -DeleteIfExist -DisableFunctionLogging

			$null = New-ItemProperty -LiteralPath $NotificationsRegistryPath -Name "AllowContentAboveLock" -Value ([int]$AllowContentAboveLock) -PropertyType DWord -Force
			$null = New-ItemProperty -LiteralPath $NotificationsRegistryPath -Name "Enabled" -Value ([int]$true) -PropertyType DWord -Force
			$null = New-ItemProperty -LiteralPath $NotificationsRegistryPath -Name "ShowInActionCenter" -Value ([int]$ShowInActionCenter) -PropertyType DWord -Force
		}
		catch {
			Write-Log -Message "Failed to register application identifier [$NotificationsRegistryPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			throw "Failed to register application identifier [$NotificationsRegistryPath]: $($_.Exception.Message)"
		}

		try {
			$AppIdRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\AppUserModelId\$($AppUserModelId)"
			New-RegistryKeyVolatile -Key $AppIdRegistryPath -DeleteIfExist -DisableFunctionLogging

			$null = New-ItemProperty -LiteralPath $AppIdRegistryPath -Name "DisplayName" -Value $DisplayName -PropertyType ExpandString -Force
			$null = New-ItemProperty -LiteralPath $AppIdRegistryPath -Name "ShowInSettings" -Value ([int]$ShowInSettings) -PropertyType DWord -Force

			if ($IconUri) { $null = New-ItemProperty -LiteralPath $AppIdRegistryPath -Name "IconUri" -Value $IconUri -PropertyType ExpandString -Force }
			if ($IconBackgroundColor) { $null = New-ItemProperty -LiteralPath $AppIdRegistryPath -Name "IconBackgroundColor" -Value $IconBackgroundColor -PropertyType String -Force }
			#if ($LaunchUri) { $null = New-ItemProperty -LiteralPath $AppIdRegistryPath -Name "LaunchUri" -Value $LaunchUri -PropertyType String -Force }
		}
		catch {
			Write-Log -Message "Failed to register application identifier [$AppIdRegistryPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			throw "Failed to register application identifier [$AppIdRegistryPath]: $($_.Exception.Message)"
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-ToastNotificationProtocol
Function New-ToastNotificationProtocol {
	<#
	.SYNOPSIS
		Registers the protocol in registry.
	.DESCRIPTION
		Registers the protocol in registry.
		Used by all Toast Notification functions that require a result.
	.PARAMETER ProtocolName
		Protocol name used to generate the result.
	.PARAMETER WorkingDirectory
		Base directory where the script, icons and results will be located.
	.PARAMETER FileType
		Different file types according the script order to be compared.
	.PARAMETER RegistrySubTree
		Registry subtree to use to register the protocol.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		New-ToastNotificationProtocol -ProtocolName 'psadttoastnotification' -FileType 'cmd' -RegistrySubTree 'HKEY_CURRENT_USER'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ProtocolName = $configToastNotificationGeneralOptions.ProtocolName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$WorkingDirectory = $configToastNotificationGeneralOptions.WorkingDirectory,
		[Parameter(Mandatory = $true)]
		[ValidateSet("vbs", "cmd")]
		[string]$FileType,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Creates a new protocol command file and get the hash of that file
		$ProtocolCommandFileHash = New-ToastNotificationProtocolCommandFile -ProtocolName $ProtocolName -WorkingDirectory $WorkingDirectory -FileType $FileType

		if ([string]::IsNullOrWhiteSpace($ProtocolCommandFileHash) -or -not $ProtocolCommandFileHash -is [System.String]) {
			Write-Log -Message "Protocol [$ProtocolName] command file hash is invalid." -Severity 3 -Source ${CmdletName}
			throw "Protocol [$ProtocolName] command file hash is invalid."
		}
		else {
			switch ($FileType) {
				"vbs" { $ProtocolCommand = $configToastNotificationScripts.CommandVBS }
				"cmd" { $ProtocolCommand = $configToastNotificationScripts.CommandCMD }
			}

			if ([string]::IsNullOrWhiteSpace($ProtocolCommand)) {
				Write-Log -Message "Script command is empty for file type [$FileType]." -Severity 3 -Source ${CmdletName}
				throw "Script command is empty for file type [$FileType]."
			}
			else {
				try {
					$ProtocolRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\$($ProtocolName)"

					if (Test-Path -Path $ProtocolRegistryPath) { Remove-RegistryKey -Key $ProtocolRegistryPath -Recurse }

					New-RegistryKeyVolatile -Key $ProtocolRegistryPath -DeleteIfExist -DisableFunctionLogging
					New-RegistryKeyVolatile -Key "$($ProtocolRegistryPath)\shell\open\command" -DeleteIfExist -DisableFunctionLogging

					$null = New-ItemProperty -LiteralPath $ProtocolRegistryPath -Name "URL Protocol" -Value "" -PropertyType String -Force
					$null = New-ItemProperty -LiteralPath "$($ProtocolRegistryPath)\shell\open\command" -Name "(Default)" -Value $ProtocolCommand -PropertyType String -Force
					$null = New-ItemProperty -LiteralPath "$($ProtocolRegistryPath)\shell\open\command" -Name "hash" -Value $ProtocolCommandFileHash -PropertyType String -Force
				}
				catch {
					Write-Log -Message "Failed to register protocol [$ProtocolRegistryPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					throw "Failed to register protocol [$ProtocolRegistryPath]: $($_.Exception.Message)"
				}
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-ToastNotificationProtocolCommandFile
Function New-ToastNotificationProtocolCommandFile {
	<#
	.SYNOPSIS
		Creates a new file with the script used by the protocol.
	.DESCRIPTION
		Creates a new file with the script used by the protocol.
		Used by all Toast Notification functions that require a result.
	.PARAMETER ProtocolName
		Protocol name used to generate the result.
	.PARAMETER WorkingDirectory
		Base directory where the script, icons and results will be located.
	.PARAMETER FileType
		Different file types according the script order to be compared.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Returns the Protocol command file hash.
	.EXAMPLE
		New-ToastNotificationProtocolCommandFile -ProtocolName 'psadttoastnotification' -FileType 'cmd'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ProtocolName = $configToastNotificationGeneralOptions.ProtocolName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$WorkingDirectory = $configToastNotificationGeneralOptions.WorkingDirectory,
		[Parameter(Mandatory = $true)]
		[ValidateSet("vbs", "cmd")]
		[string]$FileType
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		$ProtocolCommandFileName = "$($ProtocolName).$($FileType)"
		[IO.FileInfo]$ProtocolCommandFilePath = Join-Path -Path $WorkingDirectory -ChildPath $ProtocolName | Join-Path -ChildPath $ProtocolCommandFileName

		## Trying to create protocol command file
		try {
			if ($ProtocolCommandFilePath.Exists) { $null = Remove-Item -Path $ProtocolCommandFilePath -Force -ErrorAction SilentlyContinue }
			$null = New-Item -Path $ProtocolCommandFilePath -ItemType File -Force
		}
		catch {
			Write-Log -Message "Failed to create protocol command file [$ProtocolCommandFilePath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			throw "Failed to create protocol command file [$ProtocolCommandFilePath]: $($_.Exception.Message)"
		}

		## Set protocol command file execution permission for all users (BUILTIN\USERS)
		if ($IsAdmin) {
			try {
				$Users = ConvertTo-NTAccountOrSID -SID "S-1-5-32-545"
				$null = Set-ItemPermission -Path $ProtocolCommandFilePath -User $Users -Permission ReadAndExecute -Inheritance "ObjectInherit", "ContainerInherit"
			}
			catch {
				Write-Log -Message "Failed to set ReadAndExecute permissions on protocol command file [$ProtocolCommandFilePath]." -Severity 2 -Source ${CmdletName}
			}
		}

		switch ($FileType) {
			"vbs" { $ScriptContent = $configToastNotificationScripts.ScriptVBS -split '`r`n' }
			"cmd" { $ScriptContent = $configToastNotificationScripts.ScriptCMD -split '`r`n' }
		}

		if ([string]::IsNullOrWhiteSpace($ScriptContent)) {
			Write-Log -Message "Script content is empty for file type [$FileType]." -Severity 3 -Source ${CmdletName}
			throw "Script content is empty for file type [$FileType]."
		}
		else {
			try {
				$ScriptContent | ForEach-Object { Out-File -InputObject "$($_)$([Environment]::NewLine)" -LiteralPath $ProtocolCommandFilePath -Append -Encoding oem -Force -ErrorAction Stop }

				$ProtocolCommandFileHash = (Get-FileHash -Path $ProtocolCommandFilePath).Hash

				#  If the protocol command file is created, return the hash of the file
				return $ProtocolCommandFileHash
			}
			catch {
				Write-Log -Message "Failed to create protocol command file [$ProtocolCommandFilePath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				throw "Failed to create protocol command file [$ProtocolCommandFilePath]: $($_.Exception.Message)"
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Remove-ToastNotificationAppId
Function Remove-ToastNotificationAppId {
	<#
	.SYNOPSIS
		Removes an application identifier from the registry.
	.DESCRIPTION
		Removes an application identifier from the registry.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.PARAMETER RegistrySubTree
		Registry subtree to determine if the application identifier will be removed from system or user context.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Remove-ToastNotificationAppId -AppUserModelId 'psadttoastnotification' -RegistrySubTree 'HKEY_CURRENT_USER'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		$NotificationsRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$($AppUserModelId)"
		if (Test-Path -Path $NotificationsRegistryPath -ErrorAction SilentlyContinue) { Remove-RegistryKey -Key $NotificationsRegistryPath -Recurse }

		$AppIdRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\AppUserModelId\$($AppUserModelId)"
		if (Test-Path -Path $AppIdRegistryPath -ErrorAction SilentlyContinue) { Remove-RegistryKey -Key $AppIdRegistryPath -Recurse }
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Remove-ToastNotificationProtocol
Function Remove-ToastNotificationProtocol {
	<#
	.SYNOPSIS
		Removes a protocol from the registry.
	.DESCRIPTION
		Removes a protocol from the registry.
		Used by all Toast Notification functions that require a result.
	.PARAMETER ProtocolName
		Protocol name used to generate the result.
	.PARAMETER RegistrySubTree
		Registry subtree to determine if the protocol will be removed from system or user context.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Remove-ToastNotificationProtocol -ProtocolName 'psadttoastnotification' -RegistrySubTree 'HKEY_CURRENT_USER'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ProtocolName = $configToastNotificationGeneralOptions.ProtocolName,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		$ProtocolRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\$($ProtocolName)"
		if (Test-Path -Path $ProtocolRegistryPath) { Remove-RegistryKey -Key $ProtocolRegistryPath -Recurse }
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Compare-ToastNotificationAppId
Function Compare-ToastNotificationAppId {
	<#
	.SYNOPSIS
		Compares and verifies the application identifier data in the registry.
	.DESCRIPTION
		Compares and verifies the application identifier data in the registry.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER DisplayName
		Name that is displayed in the notifications.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.PARAMETER IconUri
		Path of the icon showed in the application identifier.
	.PARAMETER IconBackgroundColor
		Icon background color.
	.PARAMETER LaunchUri
		URI launched when clicked the notification.
	.PARAMETER ShowInSettings
		Determines if notifications should be shown in Settings.
	.PARAMETER AllowContentAboveLock
		Determines if notifications should show its content on lock screen.
	.PARAMETER ShowInActionCenter
		Determines if notifications should be displayed in the Action Center.
	.PARAMETER RegistrySubTree
		Registry subtree to use to register the application identifier.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the application identifier is correct in the registry.
	.EXAMPLE
		Compare-ToastNotificationAppId -DisplayName 'IT software' -RegistrySubTree 'HKEY_CURRENT_USER'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$DisplayName = $configToastNotificationAppId.DisplayName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId,
		[Parameter(Mandatory = $false)]
		[string]$IconUri = $configToastNotificationAppId.IconUri,
		[Parameter(Mandatory = $false)]
		[string]$IconBackgroundColor = $configToastNotificationAppId.IconBackgroundColor,
		[Parameter(Mandatory = $false)]
		[string]$LaunchUri = $configToastNotificationAppId.LaunchUri,
		[Parameter(Mandatory = $false)]
		[bool]$ShowInSettings = $configToastNotificationAppId.ShowInSettings,
		[Parameter(Mandatory = $false)]
		[bool]$AllowContentAboveLock = $configToastNotificationAppId.AllowContentAboveLock,
		[Parameter(Mandatory = $false)]
		[bool]$ShowInActionCenter = $configToastNotificationAppId.ShowInActionCenter,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Check if Toast Notification AppId is Enabled and registered
		$NotificationsRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$($AppUserModelId)"
		$AppIdRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\AppUserModelId\$($AppUserModelId)"

		try {
			$NotificationsRegistryPathProperties = Get-ItemProperty -Path $NotificationsRegistryPath -ErrorAction SilentlyContinue
			$AppIdRegistryPathProperties = Get-ItemProperty -Path $AppIdRegistryPath -ErrorAction SilentlyContinue

			if ($null -eq $NotificationsRegistryPathProperties -or $null -eq $AppIdRegistryPathProperties) {
				Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] does not exists in [$($RegistrySubTree)]." -Severity 2 -Source ${CmdletName} -DebugMessage
				return $false
			}

			if ($NotificationsRegistryPathProperties.Enabled -eq 1) {
				if ([System.Convert]::ToBoolean([int32]($NotificationsRegistryPathProperties.AllowContentAboveLock)) -ne $AllowContentAboveLock) {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] AllowContentAboveLock property should be [$AllowContentAboveLock]." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}
				if ([System.Convert]::ToBoolean([int32]($NotificationsRegistryPathProperties.ShowInActionCenter)) -ne $ShowInActionCenter) {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] ShowInActionCenter property should be [$ShowInActionCenter]." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}

				if ($null -eq $AppIdRegistryPathProperties.DisplayName) {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] DisplayName property is empty." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}
				elseif ($AppIdRegistryPathProperties.DisplayName -ne $DisplayName -and $DisplayName -ne "PSADT Toast Notification") {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] DisplayName property should be [$DisplayName]." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}

				if ($AppIdRegistryPathProperties.IconUri -ne [Environment]::ExpandEnvironmentVariables($IconUri)) {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] IconUri property should be [$IconUri]." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}

				if ($AppIdRegistryPathProperties.IconBackgroundColor -ne $IconBackgroundColor) {
					Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] IconBackgroundColor property should be [$IconBackgroundColor]." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}

				#if ($AppIdRegistryPathProperties.LaunchUri -ne $LaunchUri) {
				#	Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] LaunchUri property should be [$LaunchUri]." -Severity 3 -Source ${CmdletName} -DebugMessage
				#	return $false
				#}

				Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] is Enabled and registered." -Severity 2 -Source ${CmdletName} -DebugMessage
				return $true
			}
			else {
				Write-Log -Message "The Toast Notification AppId [$($AppUserModelId)] is not Enabled or not properly registered." -Severity 3 -Source ${CmdletName} -DebugMessage
				return $false
			}
		}
		catch {
			Write-Log -Message "The Toast Notification AppId [$AppUserModelId] test failed.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Compare-ToastNotificationProtocol
Function Compare-ToastNotificationProtocol {
	<#
	.SYNOPSIS
		Compares and verifies the correct operation of the protocol.
	.DESCRIPTION
		Compares and verifies the correct operation of the protocol.
		Used by all Toast Notification functions that require a result.
	.PARAMETER ProtocolName
		Protocol name used to generate the result.
	.PARAMETER TaggingVariable
		Tag variable used to identify different instances.
	.PARAMETER WorkingDirectory
		Base directory where the script, icons and results will be located.
	.PARAMETER FileType
		Different file types according the script order to be compared.
	.PARAMETER RegistrySubTree
		Registry subtree to determine if the protocol will be registered in system or user context.
	.PARAMETER OnlyCheckExistance
		If specified, only checks if the protocols exists in registry.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the Protocol is correctly registered.
	.EXAMPLE
		Compare-ToastNotificationProtocol -FileType 'cmd' -RegistrySubTree 'HKEY_CURRENT_USER' -OnlyCheckExistance
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$ProtocolName = $configToastNotificationGeneralOptions.ProtocolName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$TaggingVariable = $configToastNotificationGeneralOptions.TaggingVariable,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$WorkingDirectory = $configToastNotificationGeneralOptions.WorkingDirectory,
		[Parameter(Mandatory = $true)]
		[ValidateSet("vbs", "cmd")]
		[string]$FileType,
		[Parameter(Mandatory = $true)]
		[ValidateSet("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER")]
		[string]$RegistrySubTree,
		[switch]$OnlyCheckExistance
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Switch between different supported file types
		switch ($FileType) {
			"vbs" { $ProtocolCommand = $configToastNotificationScripts.CommandVBS }
			"cmd" { $ProtocolCommand = $configToastNotificationScripts.CommandCMD }
		}

		## Check if Toast Notification protocol exists
		$ProtocolRegistryPath = "Registry::$RegistrySubTree\SOFTWARE\Classes\$($ProtocolName)"
		$ProtocolRegistryItem = Get-Item -Path $ProtocolRegistryPath -ErrorAction SilentlyContinue

		if ($OnlyCheckExistance) {
			if (Test-Path -Path $ProtocolRegistryPath -ErrorAction SilentlyContinue) {
				Write-Log -Message "The Toast Notification protocol [$($ProtocolName)] exists in [$($ProtocolRegistryPath)]." -Severity 2 -Source ${CmdletName} -DebugMessage
				return $true
			}
			else {
				Write-Log -Message "The Toast Notification protocol [$($ProtocolName)] does not exists in [$($ProtocolRegistryPath)]." -Severity 2 -Source ${CmdletName} -DebugMessage
				return $false
			}
		}

		## Check if Toast Notification protocol contains 'URL Protocol' property
		if ($ProtocolRegistryItem.Property -notcontains "URL Protocol") {
			Write-Log -Message "The Toast Notification protocol [$($ProtocolName)] does not contain 'URL Protocol' property." -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}

		## Check if Toast Notification protocol open command is correct
		$ProtocolRegistryCommand = Get-ItemPropertyValue -Path "Registry::$($RegistrySubTree)\SOFTWARE\Classes\$($ProtocolName)\shell\open\command" -Name "(default)"

		if ($ProtocolRegistryCommand -ne $ProtocolCommand) {
			Write-Log -Message "The Toast Notification protocol command [$($ProtocolRegistryCommand)] is not correct." -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}

		## Check if Toast Notification protocol command hash is correct
		$ProtocolRegistryHash = Get-ItemPropertyValue -Path "Registry::$($RegistrySubTree)\SOFTWARE\Classes\$($ProtocolName)\shell\open\command" -Name "hash"

		$ProtocolCommandFileName = "$($ProtocolName).$($FileType)"
		[IO.FileInfo]$ProtocolCommandFilePath = Join-Path -Path $WorkingDirectory -ChildPath $ProtocolName | Join-Path -ChildPath $ProtocolCommandFileName
		if ($ProtocolCommandFilePath.Exists) {
			$ProtocolCommandFileHash = (Get-FileHash -Path $ProtocolCommandFilePath).Hash
		}
		else {
			Write-Log -Message "The Toast Notification protocol command script file [$($ProtocolCommandFilePath)] does not exist." -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}

		if ($ProtocolRegistryHash -ne $ProtocolCommandFileHash) {
			Write-Log -Message "The Toast Notification protocol command script file hash does not match the expected hash in registry." -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}

		## Check if Toast Notification protocol command gives the expected result
		$ProtocolResultVariable = "Testing_$([System.Diagnostics.Process]::GetCurrentProcess().Id)_Result"
		#  Clean any previuos result
		Remove-ToastNotificationResult -ResultVariable $ProtocolResultVariable -IncludeOriginalPID $true

		#  Test Toast Notification protocol
		try {
			$ProtocolTesting = '{0}:{1}?Testing' -f ( <#0#> $ProtocolName), ( <#1#> $ProtocolResultVariable)

			## Creates the ScriptBlock with parameters
			$ProtocolTestParameters = "`$ProtocolTesting = '$ProtocolTesting'"

			[scriptblock]$ProtocolTestBody = {
				Start-Process $ProtocolTesting -PassThru -Wait -WindowStyle Hidden
			}

			$ProtocolTestScriptBlock = [scriptblock]::Create((($ProtocolTestParameters, $ProtocolTestBody.ToString()) -join ";"))

			## Invokes ScriptBlock as Active user
			$null = Invoke-ProcessAsActiveUser -ScriptBlock $ProtocolTestScriptBlock -Wait -ExitOnProcessFailure $false -DisableFunctionLogging

			if ($?) {
				$Result = Get-ToastNotificationResult -ResultVariable $ProtocolResultVariable -TestingProtocol
				if ($Result -eq "Testing") {
					Write-Log -Message "The Toast Notification protocol [$ProtocolName] test was successful." -Severity 2 -Source ${CmdletName} -DebugMessage
					return $true
				}
				else {
					Write-Log -Message "The Toast Notification protocol [$ProtocolName] test did not get any result." -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}
			}
		}
		catch {
			Write-Log -Message "The Toast Notification protocol [$ProtocolName] test failed.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Test-ToastNotificationAppId
Function Test-ToastNotificationAppId {
	<#
	.SYNOPSIS
		Unregister and register again the AppId properties in registry.
	.DESCRIPTION
		Unregister and register again the AppId properties in registry.
		Used by all Toast Notification functions that require a result.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the Application Identifier Test is OK.
	.EXAMPLE
		Test-ToastNotificationAppId
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Unregister and register again the AppId properties in registry
		$Result = $false

		if ($IsAdmin) {
			$HKCUAppIdTest = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
			if ($HKCUAppIdTest -eq $true) {
				$Result = $true
			}
			else {
				Remove-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
				$HKLMAppIdTest = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_LOCAL_MACHINE"
				if ($HKLMAppIdTest -eq $true) {
					$Result = $true
				}
				else {
					Remove-ToastNotificationAppId -RegistrySubTree "HKEY_LOCAL_MACHINE"
					New-ToastNotificationAppId -RegistrySubTree "HKEY_LOCAL_MACHINE"
					$Result = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_LOCAL_MACHINE"
				}
			}
		}
		else {
			$HKCUAppIdTest = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
			if ($HKCUAppIdTest -eq $true) {
				$Result = $true
			}
			else {
				$HKLMAppIdTest = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_LOCAL_MACHINE"
				if ($HKLMAppIdTest -eq $true) {
					$Result = $true
				}
				else {
					Remove-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
					New-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
					$Result = Compare-ToastNotificationAppId -RegistrySubTree "HKEY_CURRENT_USER"
				}
			}
		}

		return $Result
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Test-ToastNotificationProtocol
Function Test-ToastNotificationProtocol {
	<#
	.SYNOPSIS
		Unregister and register again the protocol properties in registry.
	.DESCRIPTION
		Unregister and register again the protocol properties in registry.
		Used by all Toast Notification functions that require a result.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the Protocol Test is correct.
	.EXAMPLE
		Test-ToastNotificationProtocol
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Unregister and register again the protocol properties in registry
		$Result = $false

		foreach ($ScriptEnabledFileType in $configToastNotificationScripts.ScriptsEnabledOrder) {
			if ($IsAdmin) {
				if (Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_CURRENT_USER" -OnlyCheckExistance) {
					Remove-ToastNotificationProtocol -RegistrySubTree "HKEY_CURRENT_USER"
				}
				if (Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_LOCAL_MACHINE" -OnlyCheckExistance) {
					Remove-ToastNotificationProtocol -RegistrySubTree "HKEY_LOCAL_MACHINE"
				}
				New-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_LOCAL_MACHINE"
				$HKLMProtocolTest = Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_LOCAL_MACHINE"
				if ($HKLMProtocolTest -eq $true) {
					$Result = $true
					break
				}
				else {
					Remove-ToastNotificationProtocol -RegistrySubTree "HKEY_LOCAL_MACHINE"
				}
			}
			else {
				if (Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_CURRENT_USER" -OnlyCheckExistance) {
					Remove-ToastNotificationProtocol -RegistrySubTree "HKEY_CURRENT_USER"
				}
				if (Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_LOCAL_MACHINE" -OnlyCheckExistance) {
					$HKLMProtocolTest = Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_LOCAL_MACHINE"
					if ($HKLMProtocolTest -eq $true) {
						$Result = $true
						break
					}
				}
				else {
					New-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_CURRENT_USER"
					$HKCUProtocolTest = Compare-ToastNotificationProtocol -FileType $ScriptEnabledFileType -RegistrySubTree "HKEY_CURRENT_USER"
					if ($HKCUProtocolTest -eq $true) {
						$Result = $true
						break
					}
					else {
						Remove-ToastNotificationProtocol -RegistrySubTree "HKEY_CURRENT_USER"
					}
				}
			}
		}

		return $Result
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Test-ToastNotificationVisible
Function Test-ToastNotificationVisible {
	<#
	.SYNOPSIS
		Determines if the previously raised notification is visible.
	.DESCRIPTION
		Determines if the previously raised notification is visible.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.PARAMETER Group
		Group variable used to identify different instances.
	.PARAMETER Tag
		Tag variable used to identify different instances.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the Toast Notification is visible.
	.EXAMPLE
		Test-ToastNotificationVisible -Group 'DialogBox'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Group,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Tag = $configToastNotificationGeneralOptions.TaggingVariable
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		$Return = $false

		## Prepare a filter for Where-Object
		[scriptblock]$whereObjectFilter = {
			if (($Group -and $Tag)) { if (($_.Group -eq $Group) -and ($_.Tag -eq $Tag)) { return $true } }
			elseif ($Group) { if ($_.Group -eq $Group) { return $true } }
			elseif ($Tag) { if ($_.Tag -eq $Tag) { return $true } }
			return $false
		}

		## Trying to determinate if the Toast Notification is visible
		try {
			$ToastNotificationVisible = [Windows.UI.Notifications.ToastNotificationManager]::History.GetHistory($AppUserModelId) | Where-Object -FilterScript $whereObjectFilter | Select-Object *

			if ($ToastNotificationVisible) { $Return = $true }
		}
		catch {
			Write-Log -Message "The Toast Notification visible test failed.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
		}

		Write-Log -Message "The Toast Notification visible test result is [$($Return.ToString().ToUpper())]." -Source ${CmdletName} -DebugMessage
		return $Return
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Test-ToastNotificationAvailability
Function Test-ToastNotificationAvailability {
	<#
	.SYNOPSIS
		Determines whether the application identifier can raise notifications.
	.DESCRIPTION
		Determines whether the application identifier can raise notifications.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Return $true if the Toast Notification can be raised.
	.EXAMPLE
		Test-ToastNotificationAvailability -AppUserModelId 'PSADT.ToastNotification'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Creates the ScriptBlock with parameters
		$TestCurrentUserAvailabilityParameters = "`$AppUserModelId = '$AppUserModelId'"

		[scriptblock]$TestCurrentUserAvailabilityBody = {
			try {
				## Load required WinRT assemblies
				$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]

				$ToastNotificationManager = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppUserModelId)

				if ($ToastNotificationManager.Setting.value__ -is [int]) {
					return $ToastNotificationManager.Setting.value__
				}
				else {
					return "null"
				}
			}
			catch {
				return $_.Exception.Message
			}
		}

		$TestCurrentUserAvailabilityScriptBlock = [scriptblock]::Create((($TestCurrentUserAvailabilityParameters, $TestCurrentUserAvailabilityBody.ToString()) -join ";"))

		## Trying to get if the AppId is able to display a Toast Notification
		try {
			## Invokes ScriptBlock as Active user
			[string]$InvokationResult = Invoke-ProcessAsActiveUser -ScriptBlock $TestCurrentUserAvailabilityScriptBlock -CaptureOutput -Wait -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging

			## Analyze the returned invokation result
			if ([string]::IsNullOrWhiteSpace($InvokationResult)) {
				throw "The invokation process did not returned any useful data."
			}
			else {
				Write-Log -Message "The invokation process returned [$InvokationResult]" -Severity 2 -Source ${CmdletName} -DebugMessage

				## Formats the invokation result since it may contains additional empty lines
				$FormattedResult = ($InvokationResult.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries) -join "").Trim()

				[int]$SettingValue = $null

				if ([int32]::TryParse($FormattedResult, [ref]$SettingValue)) {
					Write-Log -Message "The Toast Notification availability test result is: [$($SettingValue)]" -Source ${CmdletName} -DebugMessage

					switch ($SettingValue) {
						0 {
							Write-Log -Message "All notifications raised by this app can be displayed." -Source ${CmdletName} -DebugMessage
							return $true
						}
						1 {
							Write-Log -Message "The user has disabled notifications for this app." -Severity 3 -Source ${CmdletName} -DebugMessage
							return $false
						}
						2 {
							Write-Log -Message "The user or administrator has disabled all notifications for this user on this computer." -Severity 3 -Source ${CmdletName} -DebugMessage
							return $false
						}
						3 {
							Write-Log -Message "An administrator has disabled all notifications on this computer through group policy. The group policy setting overrides the user's setting." -Severity 3 -Source ${CmdletName} -DebugMessage
							return $false
						}
						4 {
							Write-Log -Message "This app has not declared itself toast capable in its package.appxmanifest file. This setting is found on the manifest's Application UI page, under the Notification section. For an app to send toast, the Toast Capable option must be set to 'Yes'." -Severity 3 -Source ${CmdletName} -DebugMessage
							return $false
						}
						default {
							Write-Log -Message "The result given is not expected, by default the test will fail." -Severity 2 -Source ${CmdletName} -DebugMessage
							return $false
						}
					}
				}
				elseif ($FormattedResult -eq "null") {
					Write-Log -Message "The Toast Notification availability test result is null. Expected if this is the first notification raised by the AppId" -Severity 2 -Source ${CmdletName} -DebugMessage
					return $true
				}
				else {
					Write-Log -Message "The Toast Notification availability test failed: $FormattedResult" -Severity 3 -Source ${CmdletName} -DebugMessage
					return $false
				}
			}
		}
		catch {
			Write-Log -Message "The Toast Notification availability test failed.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName} -DebugMessage
			return $false
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Test-ToastNotificationExtension
Function Test-ToastNotificationExtension {
	<#
	.SYNOPSIS
		Performs several tests to determine if notifications can be displayed.
	.DESCRIPTION
		Performs several tests to determine if notifications can be displayed.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER CheckProtocol
		If specified, also performs protocol result tests.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.Boolean
		Returns $true if the Extension can be used.
	.EXAMPLE
		Test-ToastNotificationExtension -CheckProtocol
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[switch]$CheckProtocol
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Test if the Toast Notification Protocol can create the necessary tag file
		if ($CheckProtocol -and -not $configToastNotificationGeneralOptions.SubscribeToEvents) {
			if ($Global:ToastNotificationProtocolTestResult -ne $true) { New-Variable -Name "ToastNotificationProtocolTestResult" -Value (Test-ToastNotificationProtocol) -Scope Global -Force }
			if ($Global:ToastNotificationProtocolTestResult -ne $true) { Write-Log -Message "The Toast Notification protocol [$($configToastNotificationGeneralOptions.ProtocolName)] test result was unsuccessful." -Severity 2 -Source ${CmdletName} }
		}

		## Test if Toast Notification AppId is Enabled
		if ($Global:ToastNotificationAppIdTestResult -ne $true) { New-Variable -Name "ToastNotificationAppIdTestResult" -Value (Test-ToastNotificationAppId) -Scope Global -Force }
		if ($Global:ToastNotificationAppIdTestResult -ne $true) { Write-Log -Message "The Toast Notification AppId [$($configToastNotificationAppId.AppId)] test result was unsuccessful." -Severity 2 -Source ${CmdletName} }

		## Test if Toast Notification AppId is able to show notifications
		if ($Global:ToastNotificationAvailabilityTestResult -ne $true) { New-Variable -Name "ToastNotificationAvailabilityTestResult" -Value (Test-ToastNotificationAvailability) -Scope Global -Force }
		if ($Global:ToastNotificationAvailabilityTestResult -ne $true) { Write-Log -Message "The Toast Notification AppId [$($configToastNotificationAppId.AppId)] availability test result was unsuccessful." -Severity 2 -Source ${CmdletName} }

		if ($Global:ToastNotificationProtocolTestResult -eq $false -or $Global:ToastNotificationAppIdTestResult -eq $false -or $Global:ToastNotificationAvailabilityTestResult -eq $false) {
			return $false
		}
		else {
			return $true
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Get-ToastNotificationResult
Function Get-ToastNotificationResult {
	<#
	.SYNOPSIS
		Obtains the result of the execution and/or test of the protocol.
	.DESCRIPTION
		Obtains the result of the execution and/or test of the protocol.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER AllowedResults
		Allowed Toast Notification action results.
	.PARAMETER ResultVariable
		Result variable of the user environment where the result of the actions will be written.
	.PARAMETER GetInvokedPID
		If specified, returns the invoked Process Id as result.
	.PARAMETER TestingProtocol
		If specified, only finds protocol test result.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		System.String
		Returns not null string if any result is found in Resource folder.
	.EXAMPLE
		Get-ToastNotificationResult -AllowedResults ('Yes', 'No', 'Cancel')
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[array]$AllowedResults,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[string]$ResultVariable,
		[switch]$GetInvokedPID,
		[switch]$TestingProtocol
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Creates the ScriptBlock with parameters
		$GetResultVariableParameters = "`$ResultVariable = '$ResultVariable'"

		[scriptblock]$GetResultVariableBody = {
			## Regex used to match the Result Variables
			try {
				$Return = [Environment]::GetEnvironmentVariable($ResultVariable, "User")
				return $Return
			}
			catch {
				return $null
			}
		}

		$GetResultVariableScriptBlock = [scriptblock]::Create((($GetResultVariableParameters, $GetResultVariableBody.ToString()) -join ";"))

		## Trying to get the Toast Notification result
		try {
			## Invokes ScriptBlock as Active user
			[string]$InvokationResult = Invoke-ProcessAsActiveUser -ScriptBlock $GetResultVariableScriptBlock -CaptureOutput -Wait -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging

			## Analyze the returned invokation result
			$Result = $null

			Write-Log -Message "The invokation process returned [$InvokationResult]" -Severity 2 -Source ${CmdletName} -DebugMessage

			## Formats the invokation result since it may contains additional empty lines
			$FormattedResult = ($InvokationResult.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries) -join "").Trim()

			switch ($FormattedResult) {
				"Testing" {
					if ($TestingProtocol) {
						#  Returning 'Testing'
						$Result = $_
					}
				}
				default {
					if (-not [string]::IsNullOrWhiteSpace($_)) {
						if ($AllowedResults) {
							if (($_ -in $AllowedResults) -or ($_ -in ("ApplicationHidden", "Click", "TimedOut", "UserCanceled"))) {
								#  Returning the matching Allowed Result or user interaction
								$Result = $_
							}
						}
						elseif ($GetInvokedPID -and $_ -match "^\d+$") {
							#  Returning the invokation Process Id
							$Result = $_
						}
						else {
							#  Returning the not null result found
							$Result = $_
						}
					}
				}
			}

			if ($null -eq $Result) {
				Write-Log -Message "Returning null value since no match was possible with function parameters." -Severity 2 -Source ${CmdletName} -DebugMessage
			}
			else {
				Write-Log -Message "Returning result [$Result]" -Severity 2 -Source ${CmdletName} -DebugMessage
			}

			return $Result
		}
		catch {
			Write-Log -Message "Failed to get the Toast Notification result.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName} -DebugMessage
			return $null
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Remove-ToastNotificationResult
Function Remove-ToastNotificationResult {
	<#
	.SYNOPSIS
		Removes any previous result environment variable.
	.DESCRIPTION
		Removes any previous result environment variable.
		Used by all Toast Notification functions that require a result.
	.PARAMETER ResultVariable
		Environment Variable to remove.
	.PARAMETER IncludeOriginalPID
		Include the calling Process Id to the filter.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Remove-ToastNotificationResult -ResourceFolder 'C:\path_defined_in_xml'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[string]$ResultVariable,
		[bool]$IncludeOriginalPID = $false
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
	}
	Process {
		## Creates the ScriptBlock with parameters
		$RemoveResultVariablesParameters = "`$OriginalPID = $([System.Diagnostics.Process]::GetCurrentProcess().Id); `$IncludeOriginalPID = [boolean]::Parse(`'$IncludeOriginalPID`'); `$ResultVariable = `'$ResultVariable`';"

		[scriptblock]$RemoveResultVariablesBody = {
			## Regex used to match the Result Variables
			$ResultVariableRegexPattern = "[\S]+_(?<ProcessId>\d+)_Result"

			## Running processes
			$RunningProcesses = Get-Process

			$EnvironmentVariables = [Environment]::GetEnvironmentVariables("User")
			$EnvironmentVariables.Keys | ForEach-Object {
				if ($_ -match $ResultVariableRegexPattern) {
					if ($RunningProcesses.Id -notcontains $Matches["ProcessId"]) {
						#  Removes all environment variables corresponding to not running processes
						[Environment]::SetEnvironmentVariable($_, $null , "User")
					}
					elseif ($IncludeOriginalPID -and $Matches["ProcessId"] -eq $OriginalPID) {
						#  Removes the environment variable corresponding to the calling process
						[Environment]::SetEnvironmentVariable($_, $null , "User")
					}
					elseif ($_ -eq $ResultVariable) {
						#  Removes the environment variable corresponding to the result variable
						[Environment]::SetEnvironmentVariable($_, $null , "User")
					}
				}
			}
		}

		$RemoveResultVariablesScriptBlock = [scriptblock]::Create((($RemoveResultVariablesParameters, $RemoveResultVariablesBody.ToString()) -join ";"))

		## Invokes ScriptBlock as Active user
		$null = Invoke-ProcessAsActiveUser -ScriptBlock $RemoveResultVariablesScriptBlock -FallbackToOriginalFunctionOnError $false -ExitOnProcessFailure $false -DisableFunctionLogging
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Clear-ToastNotificationHistory
Function Clear-ToastNotificationHistory {
	<#
	.SYNOPSIS
		Clear previously shown notifications from history.
	.DESCRIPTION
		Clear previously shown notifications from history.
		Used by all Toast Notification functions that raise a notification.
	.PARAMETER AppUserModelId
		Identifier of the application that raises the notification.
	.PARAMETER Group
		Specific group of notifications to clear.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Clear-ToastNotificationHistory -Group 'DialogBox'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of Toast Notification Extension
	.LINK
		https://github.com/LFM8787/PSADT.ToastNotification
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AppUserModelId = $configToastNotificationAppId.AppId,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Group
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Load required assemblies
		$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
	}
	Process {
		try {
			if ($Group) {
				$null = [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($Group, $AppUserModelId)
			}
			else {
				$null = [Windows.UI.Notifications.ToastNotificationManager]::History.Clear($AppUserModelId)
			}
		}
		catch {}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion

#endregion
##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================
#region ScriptBody

if ($scriptParentPath) {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $ToastNotificationExtName
}
else {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $ToastNotificationExtName
}

## Append localized UI messages from Toast Notification config XML
$xmlLoadLocalizedUIMessages = [scriptblock]::Create($xmlLoadLocalizedUIMessages.ToString() + ";" + $xmlLoadLocalizedUIToastNotificationMessages.ToString())

## If the ShowBlockedAppDialog Parameter is specified, only call that function.
if ($showBlockedAppDialog) {
	## Set the install phase to asynchronous if the script was not dot sourced, i.e. called with parameters
	if ($AsyncToolkitLaunch) {
		$installPhase = "Asynchronous"
	}

	## Disable logging
	if (-not $configToolkitLogDebugMessage) { . $DisableScriptLogging }

	## Dot source ScriptBlock to get a list of all users logged on to the system (both local and RDP users), and discover session details for account executing script
	. $GetLoggedOnUserDetails

	## Dot source ScriptBlock to create temporary directory of logged on user
	. $GetLoggedOnUserTempPath

	## Dot source ScriptBlock to load localized UI messages from config XML
	. $xmlLoadLocalizedUIMessages

	## Dot source ScriptBlock to get system DPI scale factor
	. $GetDisplayScaleFactor

	## Revert script logging to original setting
	. $RevertScriptLogging

	## Log the block execution attempt
	if ($RunAsActiveUser) { $ActiveUser = $RunAsActiveUser.NTAccount }
	elseif ($CurrentConsoleUserSession) { $ActiveUser = $CurrentConsoleUserSession.NTAccount }
	elseif ($CurrentLoggedOnUserSession) { $ActiveUser = $CurrentLoggedOnUserSession.NTAccount }
	else { $ActiveUser = $null }

	Write-Log -Message "[$appDeployMainScriptFriendlyName] called with switch [-ShowBlockedAppDialog]." -Source $ToastNotificationExtName
	if ($ActiveUser) {
		Write-Log -Message "The user [$ActiveUser] tried to execute the blocked application [$ReferredInstallName] which is currently blocked by [$ReferredInstallTitle]." -Severity 2 -Source $ToastNotificationExtName
	}
	else {
		Write-Log -Message "An user tried to execute the blocked application [$ReferredInstallName] which is currently blocked by [$ReferredInstallTitle]." -Severity 2 -Source $ToastNotificationExtName
	}

	## Disable logging
	if (-not $configToolkitLogDebugMessage) { . $DisableScriptLogging }

	## Showing Block Application Toast Notification template previously generated
	Show-BlockExecutionToastNotification
	[Environment]::Exit(0)
}

## Delete any previously created Resource directory temp folder
if ((Test-Path -Path $configToastNotificationGeneralOptions.ResourceFolder -PathType Container) -and -not $AsyncToolkitLaunch) {
	Remove-Folder -Path $configToastNotificationGeneralOptions.ResourceFolder
}

#endregion
##*===============================================
##* END SCRIPT BODY
##*===============================================