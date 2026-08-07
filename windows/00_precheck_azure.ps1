<#
=====================================================================
 GCU3 Bootstrap - Azure 事前チェック (00) v1.02  ★新規
 目的: Azure Windows VM で WSL2 を動かす前に「Nested Virtualization 可否」を判定
 背景: Azure VMでWSL2を動かすには Nested Virtualization が必須。
       Bシリーズは非対応。v3世代以上(Dsv3/Ev3/Fsv2/v4/v5系)が必要。
 実行: 通常権限 PowerShell（Azure VM内で実行）
 出力: 判定結果と推奨（続行可否）
=====================================================================
#>
[CmdletBinding()] param()
$ErrorActionPreference = "Continue"
function Step($m){Write-Host "==> $m" -ForegroundColor Cyan}
function Ok($m){Write-Host "[OK] $m" -ForegroundColor Green}
function Warn($m){Write-Host "[WARN] $m" -ForegroundColor Yellow}
function Ng($m){Write-Host "[NG] $m" -ForegroundColor Red}

Step "Azure IMDS からVM情報を取得"
$imds = "http://169.254.169.254/metadata/instance/compute"
$hdr  = @{ Metadata = "true" }
$vmSize = $null; $isAzure = $false
try {
  $vmSize   = Invoke-RestMethod -Headers $hdr -Method GET "$imds/vmSize?api-version=2021-02-01&format=text" -TimeoutSec 3
  $location = Invoke-RestMethod -Headers $hdr -Method GET "$imds/location?api-version=2021-02-01&format=text" -TimeoutSec 3
  $sku      = Invoke-RestMethod -Headers $hdr -Method GET "$imds/securityProfile/securityType?api-version=2021-11-01&format=text" -TimeoutSec 3 -ErrorAction SilentlyContinue
  $isAzure  = $true
  Ok "Azure VM 検出: vmSize=$vmSize / location=$location / securityType=$sku"
} catch {
  Warn "IMDS応答なし。Azure VM でない可能性（ローカルWindowsならこのチェックは不要）。"
}

if (-not $isAzure) {
  Warn "Azure VM ではないためチェック終了。ローカルは 01_install_wsl2.ps1 へ。"
  return
}

# --- Nested Virtualization 可否判定 ---
Step "Nested Virtualization 可否を判定 (vmSize=$vmSize)"
$ok = $true; $reasons = @()

# Bシリーズは非対応
if ($vmSize -match "^Standard_B") {
  $ok = $false; $reasons += "Bシリーズ(バースト)は Nested Virtualization 非対応"
}

# v1/v2世代の一部は非対応の可能性（v3以上を推奨）
# 代表的にNested対応: Dv3/Dsv3, Ev3/Esv3, Fsv2, および v4/v5系
$nestedOkPattern = "v3|v4|v5|Fsv2|Dsv3|Esv3|Dv3|Ev3"
if ($vmSize -notmatch $nestedOkPattern) {
  $ok = $false; $reasons += "v3世代以上(例: Dsv3/Ev3/Fsv2/v4/v5)を推奨（現状: $vmSize）"
}

# Trusted Launch は v5系以外では Nested 非対応の場合がある（警告）
if ($sku -and $sku -match "TrustedLaunch") {
  if ($vmSize -notmatch "v5") {
    Warn "securityType=TrustedLaunch かつ 非v5系: Nested非対応の可能性。標準セキュリティ or v5系を検討。"
  } else {
    Ok "v5系 + TrustedLaunch: Nested対応の想定"
  }
}

Write-Host ""
if ($ok) {
  Ok "判定: WSL2(Nested) 実行可能な見込み → 01_install_wsl2.ps1 に進んでください。"
} else {
  Ng "判定: このVMサイズでは WSL2(Nested) が動作しない可能性が高い。"
  foreach ($r in $reasons) { Write-Host "     - $r" -ForegroundColor Red }
  Write-Host ""
  Warn "対策(いずれか):"
  Write-Host "  (A) VMサイズを v3世代以上(非B系)へ変更（停止→サイズ変更→起動）"
  Write-Host "  (B) WSL2を使わず『Ubuntu VMを直接』構成にし、linux/ を --target native で実行"
  Write-Host "      例) ./linux/00_bootstrap.sh --profile azure-vm --target native"
}

Write-Host ""
Step "参考: 目的別の推奨"
Write-Host "  - CI/Build用途        → Ubuntu VM 直接 (--target native) が簡潔で推奨"
Write-Host "  - 開発者PC環境の再現   → Windows VM + WSL2 (v3以上/非B系/標準セキュリティ)"
Ok "00_precheck_azure.ps1 完了"
