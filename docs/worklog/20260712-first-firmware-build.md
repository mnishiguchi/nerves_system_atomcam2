# 20260712 最初のファームウェアビルド

## 状態

最小限の `atomcam2` Nerves firmware の最初のビルドに成功しました。この時点では
ビルドだけの到達点であり、実機での ping と SSH は 2026 年 7 月 15 日に検証しました。

ネットワーク到達点の完了については、
[`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md)
を参照してください。

## 目標

- 独自 Nerves system を構築する
- サンプル Nerves application を構築する
- AtomCam2 MIPSEL firmware 成果物を生成する
- 実機試験用に平坦な MicroSD 書き込み内容を準備する

カメラ実行環境とベンダーアプリケーションとの互換性は、この段階の対象外でした。

## 結果

ファームウェアビルドに成功し、メタデータでは次を識別できました。

```text
meta-product=atomcam2_nerves_app
meta-platform=atomcam2
meta-architecture=mipsel
```

最初の成果物は約 19 MB でした。

## この段階で使用したビルドコマンド

```sh
cd examples/atomcam2_nerves_app
direnv allow
mix deps.get
../../scripts/patch-vintage-net-linux-3.10.sh
mix firmware
```

その後、リポジトリの標準手順を次へ統一しました。

```sh
./scripts/build-firmware-log.sh
```

## ビルド成功に必要だった修正

最初のビルド成功には次が必要でした。

- `nerves_runtime`、`nerves_ssh`、`mdns_lite`、`vintage_net`、
  `vintage_net_wifi` への直接依存
- MVP に無関係な Wi-Fi access point 用依存関係の削除
- 保守的な MIPS32 native build flag
- `BR2_PACKAGE_LIBNL=y`
- Linux 3.10 kernel source に対する GNU89 互換 patch
- VintageNet に対する最初の Linux 3.10 互換 patch

最初の VintageNet patch は後に修正しました。`IFA_MAX` を更新せずに `IFA_FLAGS` を
定義すると、native runtime が停止するためです。最終的な修正は 7 月 15 日の
立ち上げ記録に記載しています。

## 到達結果

このビルドにより、リポジトリから完全な Nerves firmware 成果物を生成できることを
証明しました。ただし、次はまだ証明していませんでした。

- Ingenic T31 上の動的な利用者空間との互換性
- 正しい起動内容の選択
- ベンダー Wi-Fi driver の起動
- Wi-Fi 接続
- DHCP、mDNS、SSH

これらの境界は、その後の作業記録で調査しました。
