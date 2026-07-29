# スタートガイド

このガイドでは、ソースコードからファームウェアを作成し、MicroSD カードへ
インストールして SSH 接続を確認します。

## 準備

次のものが必要です。

- Atom Cam 2 と MicroSD カード
- Elixir、Mix、Nerves、fwup を利用できる開発環境
- 2.4 GHz Wi-Fi の SSID とパスフレーズ
- `~/.ssh` にある SSH 公開鍵

リリース済みの system と専用ツールチェーンはビルド時に取得されるため、通常の
アプリ開発で system やツールチェーンを自分でビルドする必要はありません。

> 初回インストールでは選択した MicroSD カードを消去します。fwup が表示する
> デバイス名を必ず確認してください。

## 1. ビルドしてインストールする

リポジトリのルートからサンプルアプリへ移動し、ターゲットと Wi-Fi を設定します。

```sh
cd examples/atomcam2_nerves_app

export MIX_TARGET=atomcam2
export MIX_ENV=prod
export NERVES_WIFI_SSID="your-ssid"
export NERVES_WIFI_PASSPHRASE="your-passphrase"

mix setup
mix firmware.burn
```

fwup の案内に従って MicroSD カードを選択します。書き込みが完了したらカメラの
電源を切り、カードを挿入してから電源を入れてください。

ビルド時には通常 `~/.ssh/*.pub` の公開鍵が追加されます。使用する鍵を明示する
場合は、`mix firmware.burn` の前に設定します。

```sh
export ATOMCAM2_AUTHORIZED_KEYS="$HOME/.ssh/id_ed25519.pub"
```

ビルド済みファームウェアを再度書き込む場合は `mix burn` を実行します。

## 2. Nerves の起動を確認する

起動と Wi-Fi 接続を待ち、ホスト側から確認します。

```sh
ping nerves.local
ssh nerves@nerves.local
```

SSH 接続するとターゲット上の IEx が開きます。ここまで成功すれば、Nerves の
基本機能は動作しています。カメラ互換機能と NAS 転送はまだ無効です。

## 3. Atom モバイルアプリで確認する

この手順には、標準 Atom アプリとペアリング済みのカメラが必要です。ターゲットの
IEx で、初回準備と手動起動を実行します。

```elixir
cmd("atomcam2-vendor-camera precheck")
cmd("atomcam2-vendor-camera prepare")
cmd("atomcam2-vendor-camera start")
cmd("atomcam2-vendor-camera status")
```

`result=running` と表示されたら、モバイルアプリでライブ映像と録画再生を確認します。
停止するには次を実行します。

```elixir
cmd("atomcam2-vendor-camera stop")
```

停止後にもう一度起動する場合は、先に Atom Cam 2 を再起動してください。自動起動と
NAS 転送の設定は[サンプルアプリの README](../examples/atomcam2_nerves_app/README.md)
を参照してください。

## リモート更新

最初の v0.3.0 以降のファームウェアは MicroSD カードからインストールする必要が
あります。以後はホスト側から更新できます。

カメラランタイムが動作中の場合は、ターゲットの IEx で停止して接続を終了します。

```elixir
cmd("atomcam2-vendor-camera stop")
exit()
```

ホスト側でビルドとアップロードを実行します。

```sh
mix firmware
mix upload nerves.local
```

アップロードしたファームウェアは非アクティブスロットへ書き込まれ、検証後に
再起動します。起動後のヘルスチェックに合格するまでは、以前のスロットが
ロールバック先として残ります。転送が中断された場合は再起動せず、現在の
ファームウェアを継続して使用します。
