$ErrorActionPreference = 'Stop'
$backendDirectory = Split-Path -Parent $PSScriptRoot
$securePassword = $null
$passwordPointer = [IntPtr]::Zero

try {
  $env:CLOUD_MYSQL_HOST = Read-Host 'Hôte public de votre base TiDB'
  $env:CLOUD_MYSQL_DATABASE = Read-Host 'Nom de la base TiDB'
  $env:CLOUD_MYSQL_USER = Read-Host 'Utilisateur TiDB'
  $env:CLOUD_MYSQL_PORT = Read-Host 'Port TiDB (4000 par défaut)'
  if ([string]::IsNullOrWhiteSpace($env:CLOUD_MYSQL_PORT)) {
    $env:CLOUD_MYSQL_PORT = '4000'
  }
  $securePassword = Read-Host 'Mot de passe TiDB (saisie masquée)' -AsSecureString
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  $env:CLOUD_MYSQL_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

  Push-Location $backendDirectory
  try {
    & node .\src\scripts\copy-local-data.js
    if ($LASTEXITCODE -ne 0) {
      throw 'La migration a échoué. Vérifiez la connexion et les journaux locaux.'
    }
  } finally {
    Pop-Location
  }
} finally {
  if ($passwordPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
  }
  if ($securePassword) {
    $securePassword.Dispose()
  }
  foreach ($name in 'CLOUD_MYSQL_HOST', 'CLOUD_MYSQL_DATABASE', 'CLOUD_MYSQL_USER', 'CLOUD_MYSQL_PORT', 'CLOUD_MYSQL_PASSWORD') {
    Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
  }
}
