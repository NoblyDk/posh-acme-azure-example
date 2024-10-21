param (
    [string] $AcmeDirectory,
    [string] $AcmeContact,
    [string] $CertificateNames,
    [string] $StorageContainer,
    [string] $AZCOPY_SPA_APPLICATION_ID,
    [string] $AZCOPY_SPA_CLIENT_SECRET,
    [string] $AZCOPY_TENANT_ID
)
$env:AZCOPY_AUTO_LOGIN_TYPE="SPN"
$env:AZCOPY_SPA_APPLICATION_ID=$AZCOPY_SPA_APPLICATION_ID
$env:AZCOPY_SPA_CLIENT_SECRET=$AZCOPY_SPA_CLIENT_SECRET
$env:AZCOPY_TENANT_ID=$AZCOPY_TENANT_ID
# Supress progress messages. Azure DevOps doesn't format them correctly (used by New-PACertificate)
$global:ProgressPreference = 'SilentlyContinue'

# Split certificate names by comma or semi-colin
$CertificateNamesArr = $CertificateNames.Replace(',',';') -split ';' | ForEach-Object -Process { $_.Trim() }

# Create working directory
$workingDirectory = Join-Path -Path "." -ChildPath "pa"
if (Test-Path $workingDirectory) {
	Remove-Item $workingDirectory -Recurse
}
New-Item -Path $workingDirectory -ItemType Directory | Out-Null

# Sync contents of storage container to working directory
./azcopy.exe sync "$StorageContainer" "$workingDirectory"

# Set Posh-ACME working directory
$env:POSHACME_HOME = $workingDirectory
Import-Module Posh-ACME -Force

# Configure Posh-ACME server
Set-PAServer -DirectoryUrl $AcmeDirectory

# Configure Posh-ACME account
$account = Get-PAAccount
if (-not $account) {
    # New account
    $account = New-PAAccount -Contact $AcmeContact -AcceptTOS
}
elseif ($account.contact -ne "mailto:$AcmeContact") {
    # Update account contact
    Set-PAAccount -ID $account.id -Contact $AcmeContact
}

# Acquire access token for Azure (as we want to leverage the existing connection)
$azureContext = Get-AzContext
$currentAzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
$currentAzureProfileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($currentAzureProfile);
$azureAccessToken = $currentAzureProfileClient.AcquireAccessToken($azureContext.Tenant.Id).AccessToken;

# Request certificate
$paPluginArgs = @{
    AZSubscriptionId = $azureContext.Subscription.Id
    AZAccessToken    = $azureAccessToken;
}
New-PACertificate -Domain $CertificateNamesArr -DnsPlugin Azure -PluginArgs $paPluginArgs

# Sync working directory back to storage container
./azcopy.exe sync "$workingDirectory" "$StorageContainer"
