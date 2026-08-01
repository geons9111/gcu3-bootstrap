# VS Code × GitHub × Docker 連携ガイド MECE確認表（v1.1）

> released `gcu3-bootstrap` に対し、連携ガイド(v1.0)をMECEで確認し、是正した記録。
> 判定日: 2026-07-27 / Osaka

---

## 1. 分解軸（ME：相互排他）

| 軸 | 範囲 | 主担当ファイル |
|---|---|---|
| A. VS Code連携 | 拡張/接続/テンプレ/Dev Container | 22_setup_vscode.sh, vscode/*, devcontainer/* |
| B. GitHub連携 | gh導入/SSH鍵/認証/登録 | 20_setup_github_cli.sh |
| C. Docker管理 | 状態/疎通/compose/prune | 21_docker_manage.sh |
| D. 横断 | 統括/Proxy/Security/配置/README | 00_integration.sh, docs/* |

> ME検証：install(bootstrap)とmanage(integration)、gh手順(20に一本化)で**重複なし**。

---

## 2. 網羅性（CE：漏れなし）と是正結果

| # | 確認項目 | v1.0 | 判定 | 是正(v1.1) |
|---|---|---|---|---|
| A1 | 拡張一括導入 | あり | ✅ | 維持 |
| A2 | .vscode/.devcontainer配置 | あり | ✅ | 維持 |
| A3 | ローカルWSL=Remote-WSL | あり | ✅ | 維持 |
| A4 | **Azure VM=Remote-SSH経路** | なし | ⚠️漏れ | **追加**（22 --mode ssh / ガイド§3.2） |
| B1 | gh導入 | あり | ✅ | 維持 |
| B2 | SSH鍵/known_hosts/認証 | あり | ✅ | 維持 |
| B3 | **gh手順の重複(統括/別ガイド)** | 重複 | ⚠️ME違反 | **20に一本化**（統括は呼出のみ） |
| B4 | **gh Proxy環境手順** | 断片 | ⚠️漏れ | **§4.2追加**＋20でProxy検出 |
| B5 | GHES対応 | あり | ✅ | `--host`引数で明示化 |
| C1 | Docker管理(status等) | あり | ✅ | 維持 |
| C2 | install重複回避 | 暗黙 | ⚠️ | **明記**（03=install/21=manage） |
| D1 | 統括スクリプト | あり | ✅ | target連携を追加 |
| D2 | Proxy焼込み禁止(devcontainer) | あり | ✅ | 維持 |
| D3 | Security(Phase1固定) | あり | ✅ | 維持 |
| D4 | **配置場所(bootstrap内)** | なし | ⚠️漏れ | **§0で明記**（integration/配下） |
| D5 | **READMEとの関連付け** | なし | ⚠️漏れ | **§11に追記文**提示 |

---

## 3. 是正サマリ（4点）

| 是正 | 内容 | 反映先 |
|---|---|---|
| ① 配置/README | `gcu3-bootstrap/integration/` 配下と明記、README §9/§16追記文を提供 | ガイド§0/§11 |
| ② Azure native | Remote-SSH経路を追加（22 `--mode ssh`、auto判定） | 22_setup_vscode.sh, ガイド§3.2 |
| ③ gh一本化 | 統括はgh手順を持たず 20 を呼ぶだけ（重複排除） | 00_integration.sh, 20_ |
| ④ gh Proxy | Proxy事前exportを明記＋20でProxy検出表示 | 20_, ガイド§4.2 |

---

## 4. 最終MECE判定

| 観点 | 判定 |
|---|---|
| ME（重複なし） | ✅ install/manage・gh一本化で解消 |
| CE（漏れなし） | ✅ Azure経路/配置/README/Proxyを補完 |
| bootstrap整合 | ✅ integration/配下・README参照で連結 |

**結論：v1.1でMECE成立。released bootstrap にそのまま組込み可能。**
