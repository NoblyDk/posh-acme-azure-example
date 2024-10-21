param (
    [string] $CertificateNames,
    [string] $KeyVaultResourceId,
    [string] $AcmeDirectory
)
$CertificateNames
$KeyVaultResourceId
$AcmeDirectory
Write-Host "Split certificate names by comma or semi-colon"
$currentServerName = ((Get-PAServer).Name)
$currentServerName
Write-Host "For wildcard certificates, Posh-ACME replaces * with ! in the directory name"
$CertificateNamesLocal = $CertificateNames.Replace('*', '!')
$CertificateNamesLocal

Write-Host "Set working directory"
$workingDirectory = Join-Path $(Get-Location) -ChildPath "pa"
$workingDirectory

Write-Host "Set Posh-ACME working directory"
$env:POSHACME_HOME = $workingDirectory
Import-Module -Name Posh-ACME -Force

Write-Host "Resolve the details of the certificate"
#$currentServerName = ((Get-PAServer).location) -split "/" | Where-Object -FilterScript { $_ } | Select-Object -Skip 1 -First 1
#$currentServerName
$currentAccountName = (Get-PAAccount).id
$currentAccountName

Write-Host "Determine paths to resources"
$orderDirectoryPath = Join-Path -Path $workingDirectory -ChildPath $AcmeDirectory | Join-Path -ChildPath $currentAccountName | Join-Path -ChildPath $CertificateNamesLocal
$orderDirectoryPath
$orderDataPath = Join-Path -Path $orderDirectoryPath -ChildPath "order.json"
$orderDataPath
$pfxFilePath = Join-Path -Path $orderDirectoryPath -ChildPath "fullchain.pfx"
$pfxFilePath

Write-Host "If we have a order and certificate available"
if ((Test-Path -Path $orderDirectoryPath) -and (Test-Path -Path $orderDataPath) -and (Test-Path -Path $pfxFilePath)) {

    $pfxPass = (Get-PAOrder $CertificateNames).PfxPass
    $securePfxPass = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    Write-Host "Load PFX"
    $certificate = Get-PfxCertificate $pfxFilePath -Password $securePfxPass
    $certificate
    
    Write-Host "Get the current certificate from key vault (if any)"
    $azureKeyVaultCertificateName = $CertificateNamesLocal.Replace(".", "-").Replace("!", "wildcard")
    $keyVaultResource = Get-AzResource -ResourceId $KeyVaultResourceId
    $keyVaultResource
    $azureKeyVaultCertificate = Get-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -ErrorAction SilentlyContinue
    
    $azureKeyVaultCertificate.Thumbprint
    $certificate.Thumbprint
    
    Write-Host "If we have a different certificate, import it"
    If (-not $azureKeyVaultCertificate -or $azureKeyVaultCertificate.Thumbprint -ne $certificate.Thumbprint) {
        Import-AzKeyVaultCertificate -VaultName $keyVaultResource.Name -Name $azureKeyVaultCertificateName -FilePath $pfxFilePath -Password $securePfxPass | Out-Null    
    }
    else {
        Write-Output "Resource Path(s) not valid."
        exit 1
    }
} 
else {
    Write-Output "No order or certificate was found."
    exit 1
}
