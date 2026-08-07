<#
=====================================================================
 GCU3 Bootstrap - Windows (01) v1.01
 目的: 前提確認 → WSL更新 → WSL2 + Ubuntu 24.04 導入
 実行: 管理者権限 PowerShell
 反映(レビュー): wsl --version(2.4.10以上目安) / wsl --update / --list --online 確認
=====================================================================
#>
[CmdletBinding()]
param(
  [string]$Distro = "Ubuntu-24.04",
  [switch]$SetWsl2Default = $true
)
$ErrorActionPreference = "Stop"
function Step($m){Write-Host "==> $m" -ForegroundColor Cyan}
function Ok($m){Write-Host "[OK] $m" -ForegroundColor Green}
function Warn($m){Write-Host "[WARN] $m" -ForegroundColor Yellow}

# 管理者チェック
$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "管理者権限の PowerShell で実行してください。"
}

Step "Windows バージョン"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("OS: {0} (Build {1})" -f $os.Caption, $os.BuildNumber)

Step "WSL 機能 / 仮想マシンプラットフォーム 有効化"
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
Ok "Windows機能 有効化"

Step "WSL 本体を更新（Ubuntu24.04 新形式は WSL 2.4.10 以上が必要）"
try { wsl --update } catch { Warn "wsl --update 失敗（後で再実行可）: $_" }

Step "WSL バージョン確認"
try { wsl --version } catch { Warn "wsl --version 取得不可。'wsl --update' 実行後に再確認してください。" }

if ($SetWsl2Default) {
  Step "既定を WSL2 に設定"
  wsl --set-default-version 2
  Ok "WSL2 既定化"
}

Step "オンライン配布一覧（$Distro が含まれるか確認）"
wsl --list --online

Step "$Distro をインストール"
$installed = (wsl --list --quiet) -join "`n"
if ($installed -match [regex]::Escape($Distro)) {
  Warn "$Distro は既にインストール済み。スキップします。"
} else {
  wsl --install -d $Distro
  Ok "$Distro インストール開始"
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " 次の手順" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " 1) 案内に従い Windows を再起動（初回必須）"
Write-Host " 2) スタートメニューから '$Distro' 初回起動 → Linuxユーザー/パスワード設定"
Write-Host " 3) 任意: 02_configure_wslconfig.ps1（リソース/ネットワーク）"
Write-Host " 4) WSL内: linux/07_enable_systemd.sh → wsl --shutdown → 再起動"
Write-Host " 5) WSL内: linux/00_bootstrap.sh --profile office-osaka"
Write-Host ""
Ok "01_install_wsl2.ps1 完了"
