# Atom Cam 2 向け最小 Nerves アプリ

Atom Cam 2 で Nerves アプリを動かすためのサンプルです。Wi-Fi 接続、mDNS、
SSH、ターゲット上の IEx、永続データ領域、リモートファームウェア更新を
利用できます。

システム全体については
[アーキテクチャ概要](../../docs/architecture.md)、初めてセットアップする場合は
[スタートガイド](../../docs/getting-started.md)も参照してください。

## 必要なもの

- Atom Cam 2
- MicroSD カード
- Elixir、Mix、Nerves、fwup を利用できる開発環境
- 2.4 GHz 帯の Wi-Fi 接続情報
- SSH 公開鍵（通常は `~/.ssh/*.pub`）

> `mix firmware.burn` は選択した MicroSD カードの内容を消去します。
> fwup が表示するデバイス名を必ず確認してから書き込んでください。

## 初回セットアップ

このディレクトリでターゲット、Wi-Fi、必要に応じて SSH 公開鍵を設定します。

```sh
export MIX_TARGET=atomcam2
export MIX_ENV=prod
export NERVES_WIFI_SSID="your-ssid"
export NERVES_WIFI_PASSPHRASE="your-passphrase"

# 使用する鍵を明示したい場合のみ設定
export ATOMCAM2_AUTHORIZED_KEYS="$HOME/.ssh/id_ed25519.pub"
```

依存関係を取得し、ファームウェアをビルドして MicroSD カードへ書き込みます。

```sh
mix setup
mix firmware.burn
```

fwup の案内に従って書き込み先を選択します。完了後は Atom Cam 2 の電源を切り、
MicroSD カードを挿入してから電源を入れてください。

ビルド済みのファームウェアをもう一度書き込む場合は、次のコマンドを使います。

```sh
mix burn
```

## 接続を確認する

起動と Wi-Fi 接続を待ってから、ホスト側で確認します。

```sh
ping nerves.local
ssh nerves@nerves.local
```

SSH 接続するとターゲット上の IEx が開きます。Toolshed は自動的に読み込まれる
ため、`tree`、`top`、`exit` などをすぐに利用できます。

`nerves.local` を名前解決できない場合は、同じネットワークに接続していること、
Wi-Fi の SSID とパスフレーズ、mDNS が利用可能であることを確認してください。

## 有線 LAN(任意)

USB Ethernet アダプタ(実績: Realtek RTL8152、ASIX AX88772 系)を接続すると、
起動時にドライバがロードされ、`eth0` が DHCP で構成されます。有線と無線の両方が
利用できる場合は有線が優先され、ケーブルやアダプタがない場合は Wi-Fi へ
フォールバックします。追加設定は不要です。

ドライバの動作状況は、MicroSD の FAT パーティションに書き込まれる
`atomcam2-eth-driver.env` で確認できます。有線ドライバのロード自体を無効にする
場合は、FAT パーティションの `atomcam2.env` に
`ATOMCAM2_PRE_RUN_ETH_DRIVER=0` を記述してください。

## 永続データ

`/data` はファームウェア更新後も保持される永続領域です。起動時には、アンマウント
状態でファイルシステムを検査し、必要であれば自動修復してから読み書き可能な状態で
マウントします。安全に修復できない場合は、データを初期化せず `/data` を
アンマウントのままにします。

## Atom アプリとの互換機能

標準の Atom モバイルアプリでライブ映像や録画を利用するためのベンダー製カメラ
ランタイムは、初期状態では無効です。この機能を試す前に、Atom Cam 2 が
モバイルアプリとペアリング済みであることを確認してください。

初回だけ `prepare` を実行し、手動で起動します。

```elixir
cmd("atomcam2-vendor-camera precheck")
cmd("atomcam2-vendor-camera prepare")
cmd("atomcam2-vendor-camera start")
cmd("atomcam2-vendor-camera status")
```

`status` に `result=running` と表示されたら、モバイルアプリでライブ映像と録画再生を
確認します。停止するには次を実行します。

```elixir
cmd("atomcam2-vendor-camera stop")
```

カメラ用カーネルモジュールは停止後も読み込まれたままになるため、再度起動する前に
Atom Cam 2 を再起動してください。

### 起動時に自動実行する

手動での起動と停止を確認できた後、次のファイルを作成します。

```text
/data/atomcam2-vendor-camera/auto-start.conf
```

内容は次の 1 行です。

```text
enabled=true
```

次回以降の起動時に、ファームウェア、ネットワーク接続、時刻同期などの準備が
整ってからカメラランタイムを起動します。状態の確認と再チェックは IEx から
実行できます。

```elixir
Atomcam2NervesApp.VendorCamera.status()
Atomcam2NervesApp.VendorCamera.run_now()
```

自動起動を無効にするには、設定を `enabled=false` に変更するかファイルを削除します。
設定を変更しても、すでに動作中のカメラランタイムは停止しません。

## NAS へ録画を転送する

録画を SFTP で NAS へ転送できます。次の設定ファイルが存在しない場合、または
`enabled=false` の場合、転送機能は動作しません。

```text
/data/atomcam2-vendor-camera/nas-export.conf
```

設定例:

```text
enabled=true
host=nas.local
port=22
user=atomcam2
user_dir=/data/atomcam2-vendor-camera/nas-ssh
remote_directory=recordings/atomcam2
poll_interval_seconds=60
retention_days=20
max_spool_bytes=536870912
```

主な設定項目:

- `remote_directory`: NAS 上の保存先。SFTP ユーザーのホームからの相対パス
- `poll_interval_seconds`: 転送確認の間隔。指定できる最小値は 60 秒
- `retention_days`: NAS 上で録画を保持する日数
- `max_spool_bytes`: ローカルに保持する転送済み録画の上限サイズ

`user_dir` には、NAS 用アカウントの秘密鍵と、接続先を登録済みの
`known_hosts` を OTP SSH が期待する構成で配置してください。パスワード認証と
接続先ホスト鍵の自動承認には対応していません。ディレクトリのパーミッションは
`0700`、秘密鍵などのファイルは `0600` にします。

NAS 用アカウントは `remote_directory` だけへアクセスできるよう制限することを
推奨します。転送機能は `retention_days` を過ぎた日付ディレクトリの録画を
NAS から削除します。

転送対象は、録画が完了した `YYYYMMDD/HH/MM.mp4` 形式のファイルだけです。
アップロード中は NAS 上で拡張子 `.uploading` を付け、サイズを確認してから正式な
ファイル名へ変更します。未転送の録画は `max_spool_bytes` を超えても削除されません。
初めて有効にするときは、既存の録画量より大きい `max_spool_bytes` を設定して
ください。

状態の確認と即時実行は IEx から行えます。

```elixir
Atomcam2NervesApp.NasExporter.status()
Atomcam2NervesApp.NasExporter.SFTP.status()
Atomcam2NervesApp.NasExporter.run_now()
```

## リモートファームウェア更新

リモート更新を利用するには、最初に `mix firmware.burn` で v0.3.0 以降の
ファームウェアを MicroSD カードへインストールしておく必要があります。

カメラランタイムが動作中の場合は、先にターゲットへ SSH 接続して停止します。

```sh
ssh nerves@nerves.local
```

```elixir
cmd("atomcam2-vendor-camera stop")
exit()
```

ホスト側で新しいファームウェアをビルドしてアップロードします。

```sh
mix firmware
mix upload nerves.local
```

更新は次の順序で進みます。

1. ファームウェアを `/data` に一時保存して内容を検証する
2. 現在使用していないアプリケーションスロットへ書き込んで検証する
3. 新しいスロットを次回起動候補に設定して再起動する
4. 起動後のヘルスチェックに成功したら新しいファームウェアを確定する

転送が途中で中断された場合は一時ファイルを削除し、再起動しません。新しい
ファームウェアが確定するまでは、以前のスロットがロールバック先として残ります。
リモート更新では、Wi-Fi や SSH の設定、永続データ、保護された制御カーネルは
書き換えません。

自動起動を設定している場合、更新後の準備が整うとカメラランタイムも再び起動します。
