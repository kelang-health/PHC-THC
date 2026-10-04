$ErrorActionPreference='Stop'
$Root='D:\AppServ\www\osm-phc'
$Python=Join-Path $Root '.venv\Scripts\python.exe'
$Log='D:\AppServ\private\osm-phc\appointment-notice-preflight.log'
if(-not (Test-Path $Python)){ throw 'Missing OSM-PHC Python runtime' }
$now=Get-Date
$minutes=($now.Hour*60)+$now.Minute
# Only useful before the 17:30 Auto D-1 run. Skip stale catch-up starts.
if($minutes -lt 930 -or $minutes -gt 1040){
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value ("["+$now.ToString('s')+"] skipped_outside_window")
  exit 0
}
$env:OSM_USE_MYSQL='1'
$env:OSM_LOCAL_ADMIN_ONLY='1'
$env:OSM_ENCRYPTION_KEY_FILE='D:\AppServ\private\osm-phc-keys\encryption.key'
$env:PYTHONPATH=$Root
Set-Location $Root
$stamp=$now.ToString('s')
try{
  $output=& $Python -m backend.appointment_notice_phase32 --preflight 2>&1
  $code=$LASTEXITCODE
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value ("[$stamp] exit=$code "+(($output -join ' ') -replace '\r?\n',' '))
  exit $code
}catch{
  Add-Content -LiteralPath $Log -Encoding UTF8 -Value ("[$stamp] runner_error="+$_.Exception.GetType().Name)
  exit 2
}