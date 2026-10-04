$ErrorActionPreference='Stop'
$Root='D:\AppServ\www\osm-phc'
$Python=Join-Path $Root '.venv\Scripts\python.exe'
$Log='D:\AppServ\private\osm-phc\appointment-onboarding-snapshot.log'
if(-not (Test-Path $Python)){ throw 'Missing OSM-PHC Python runtime' }
$env:OSM_USE_MYSQL='1'
$env:OSM_LOCAL_ADMIN_ONLY='1'
$env:OSM_ENCRYPTION_KEY_FILE='D:\AppServ\private\osm-phc-keys\encryption.key'
$env:PYTHONPATH=$Root
Set-Location $Root
$stamp=(Get-Date).ToString('s')
try{
  $output=& $Python -m backend.appointment_notice_phase33 --snapshot 2>&1
  $code=$LASTEXITCODE
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value ("[$stamp] exit=$code "+(($output -join ' ') -replace '\r?\n',' '))
  exit $code
}catch{
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value ("[$stamp] runner_error="+$_.Exception.GetType().Name)
  exit 2
}