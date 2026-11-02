$ErrorActionPreference = 'Stop'
$backendDirectory = Split-Path -Parent $PSScriptRoot
$environmentFile = Join-Path $backendDirectory '.env'

if (-not (Test-Path $environmentFile)) {
  throw 'backend/.env est introuvable. Copiez .env.example vers .env, puis configurez MySQL avant de continuer.'
}

$secureKey = Read-Host 'Collez la nouvelle clé secrète sandbox FedaPay (saisie masquée)' -AsSecureString
$keyPointer = [IntPtr]::Zero

try {
  $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  $secretKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
  if ($secretKey -notmatch '^sk_sandbox_.+') {
    throw 'La clé saisie ne ressemble pas à une clé secrète sandbox FedaPay (préfixe sk_sandbox_). Aucune modification effectuée.'
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.AddRange([System.IO.File]::ReadAllLines($environmentFile))
  $settings = @{
    FEDAPAY_ENVIRONMENT = 'sandbox'
    FEDAPAY_SECRET_KEY = $secretKey
  }

  foreach ($setting in $settings.GetEnumerator()) {
    $found = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
      if ($lines[$index] -match ('^\s*' + [regex]::Escape($setting.Key) + '\s*=')) {
        $lines[$index] = "$($setting.Key)=$($setting.Value)"
        $found = $true
        break
      }
    }
    if (-not $found) {
      $lines.Add("$($setting.Key)=$($setting.Value)")
    }
  }

  [System.IO.File]::WriteAllLines(
    $environmentFile,
    $lines,
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Output 'Clé sandbox enregistrée dans backend/.env sans l’afficher. Redémarrez ensuite l’API.'
}
finally {
  if ($keyPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
  }
  if ($secureKey) {
    $secureKey.Dispose()
  }
  $secretKey = $null
}
