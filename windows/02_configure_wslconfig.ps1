<#
=====================================================================
 GCU3 Bootstrap - Windows (02) v1.01
 目的: %USERPROFILE%\.wslconfig を生成（リソース/ネットワーク）
 反映(レビュー):
   - 既定では固定値を強制しない。物理スペックに対して警告
   - Yocto用の大容量プロファイル(-Profile yocto)を用意
 実行: 通常権限 PowerShell（管理者不要）
 反映手順: wsl --shutdown 後に再起動
=====================================================================
#>
[CmdletBinding()]
param(
  [ValidateSet("light","yocto","custom")]
  [string]$Profile = "light",
  [string]$Memory,           # 例: 8GB / 24GB（custom時に使用）
  [int]$Processors,          # 例: 4 / 8
  [string]$Swap,             # 例: 4GB / 16GB
  [switch]$MirroredNetworking = $false
)
$ErrorActionPreference = "Stop"
function Step($m){Write-Host "==> $m" -ForegroundColor Cyan}
function Ok($m){Write-Host "[OK] $m" -ForegroundColor Green}
function Warn($m){Write-Host "[WARN] $m" -ForegroundColor Yellow}

# 物理スペック取得
$cs = Get-CimInstance Win32_ComputerSystem
$totalGB = [math]::Round($cs.TotalPhysicalMemory/1GB)
$logical = $cs.NumberOfLogicalProcessors
Write-Host ("Host: RAM=${totalGB}GB / LogicalCPU=${logical}")

# プロファイル既定
switch ($Profile) {
  "light" { $Memory = $Memory ?? "8GB";  $Processors = if($Processors){$Processors}else{4}; $Swap = $Swap ?? "4GB" }
  "yocto" { $Memory = $Memory ?? "24GB"; $Processors = if($Processors){$Processors}else{8}; $Swap = $Swap ?? "16GB" }
  "custom"{ if(-not($Memory -and $Processors -and $Swap)){ throw "custom は -Memory -Processors -Swap を指定してください" } }
}

# スペック警告
$memNum = [int]($Memory -replace 'GB','')
if ($memNum -gt $totalGB) { Warn "指定Memory=${Memory} が物理RAM=${totalGB}GB を超えています（見直し推奨）" }
if ($Processors -gt $logical) { Warn "指定Processors=${Processors} が論理CPU=${logical} を超えています（見直し推奨）" }
if ($Profile -eq "yocto" -and $totalGB -lt 24) { Warn "Yocto用途に対しRAMが不足気味（推奨32GB級）" }

$path = Join-Path $env:USERPROFILE ".wslconfig"
$net = if ($MirroredNetworking) { "networkingMode=mirrored" } else { "# networkingMode=mirrored  # 必要時に有効化" }

$content = @"
# =====================================================================
# WSL2 global config (GCU3 bootstrap 02 / profile=$Profile)
# 反映: PowerShell で  wsl --shutdown  後に WSL 再起動
# =====================================================================
[wsl2]
memory=$Memory
processors=$Processors
swap=$Swap
localhostForwarding=true
$net

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@

if (Test-Path $path) {
  $bak = "$path.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
  Copy-Item $path $bak -Force
  Ok "既存 .wslconfig をバックアップ: $bak"
}
Set-Content -Path $path -Value $content -Encoding UTF8
Ok ".wslconfig を書き込み (profile=$Profile / mem=$Memory / cpu=$Processors / swap=$Swap)"

Write-Host ""
Write-Host "適用: wsl --shutdown → Ubuntu 再起動" -ForegroundColor Yellow
Ok "02_configure_wslconfig.ps1 完了"
