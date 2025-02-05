param (
    [string] $AcmeDirectory,
    [string] $AcmeContact,
    [string] $CertificateNames,
    [string] $StorageContainer
)
$Env:AZCOPY_AUTO_LOGIN_TYPE="PSCRED"
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
Install-Module -Name Posh-ACME -Repository PSGallery -force

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

$tokenObj =Get-AzAccessToken -AsSecureString
$azureAccessToken = ConvertFrom-SecureString -SecureString $tokenObj.Token -AsPlainText

# Request certificate
$paPluginArgs = @{
    AZSubscriptionId = $azureContext.Subscription.Id
    AZAccessToken    = $azureAccessToken;
}
New-PACertificate -Domain $CertificateNamesArr -DnsPlugin Azure -PluginArgs $paPluginArgs

# Sync working directory back to storage container
./azcopy.exe sync "$workingDirectory" "$StorageContainer"
