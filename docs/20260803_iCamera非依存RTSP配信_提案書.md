# 2026-08-03 iCamera_app 非依存 RTSP 配信 提案書

ベンダーアプリ `iCamera_app` を使わずに RTSP 配信を実現するための、
実行可能な実装提案。方式 B(ネイティブ実装)の具体化であり、8/2 以降の
実機調査で判明した事実を反映して経路と手順を確定させたもの。

関連: [カメラ参照機能スクラッチ実装 提案書](20260802_カメラ参照機能スクラッチ実装_提案書.md)
(全体構想)、
[ネイティブカメラ実装 技術相談](20260803_ネイティブカメラ実装_技術相談.md)
(初期化停止の切り分け)

## なぜ iCamera_app を外すか

現行の RTSP は `iCamera_app`(ブラックボックス)のエンコード出力を
LD_PRELOAD フックで横取りしている。この依存が次の制約を生む。

- モバイルアプリの HD/SD 切り替えでエンコーダチャンネルが競合し、フレーム
  供給が止まる。繰り返すとパイプライン全体が停止し**自動復旧しない**
- 解像度・fps・ビットレート・チャンネルを一切制御できない
- `iCamera_app` は RSS 18MB を消費し、87MB 機のメモリを圧迫する

映像パイプラインを自前で持てば、いずれも根本解決する。

## 鍵となる着眼点: 配信半分は再利用できる

「iCamera_app を外す」= パイプライン全体の作り直し、ではない。現行構成は
2 段に分かれる。

```text
[前段] iCamera_app → libvideo-hook.so → /dev/videoN   ← ここだけ置き換える
[後段] /dev/videoN(v4l2loopback)→ v4l2rtspserver → RTSP   ← そのまま再利用
```

**後段(v4l2loopback + v4l2rtspserver)は実機で動作実績があり、そのまま使える。**
必要なのは前段、すなわち **libimp を自前で駆動して `/dev/videoN` にエンコード
済みフレームを書き込むネイティブプロセス**を作ることだけ。これにより開発
範囲が大幅に狭まる。

## 提案アーキテクチャ

```text
Nerves（musl / soft-float）
  ├── CameraNative GenServer（監督・死活監視・自動再起動）
  │     socket / 状態ファイル（ABI 非依存のバイト列でやり取り）
  ▼
atomcam2-camera（uClibc / hard-float、実機の libimp.so を動的リンク）
  ├── IMP_System_Init → ISP → sensor → framesource → encoder（libimp 経由）
  └── エンコード済み H.264/H.265 を /dev/video0 へ write()
        │
        ▼
  /dev/video0（v4l2loopback、既存）→ v4l2rtspserver（既存）→ RTSP :8554
```

- **前段の置き換え**: `atomcam2-camera` が libimp を駆動し、フレームを
  loopback へ書く。書き込み先とフォーマットは現行フックと同一のため、
  後段は無改修
- **ABI の分離**: musl/soft-float の Nerves と hard-float の libimp は
  **別プロセス**にすれば同居できる(プロセス境界で ABI は消える)。
  やり取りは loopback(バイト列)と状態ファイルのみ
- **監督**: `CameraNative` GenServer が起動・ヘルス監視・自動再起動を担う。
  停止を検知して**自前で再起動できる**(ベンダーアプリと違い再開に
  リブートが不要になる見込み)。既存の心拍監視(`RtspServer`)の仕組みも
  そのまま活きる

## 実機で確認済みの前提(すべて揃っている)

| 部品 | 実機での所在 | 状態 |
| --- | --- | --- |
| センサー | `sensor_gc2053_t31.ko`(GC2053、I2C `0x37`) | 確認済み |
| ISP | `tx_isp_t31.ko` | 確認済み |
| エンコーダ | `avpu.ko` | 確認済み |
| libimp | `/atom/system/lib/libimp.so`(1.1.1) + `libalog` / `libsysutils` | 確認済み |
| uClibc ランタイム | `/atom/lib/`(0.9.33.2、`ld-uClibc.so.0` 一式) | 確認済み |
| ISP チューニング | `/atom/system/etc/sensor/gc2053-t31*.bin` | 確認済み |
| デバイスノード | `/dev/tx-isp`、`/dev/isp-m0`、`/dev/avpu`、`/dev/framechan0-2` | **iCamera_app なしで、モジュール insmod だけで生成されることを確認済み** |
| 後段 | v4l2loopback + v4l2rtspserver | 実機で配信実績あり |

**iCamera_app を止めた状態でカメラモジュールを手動ロードし、デバイスノードが
生成されることは検証済み**。ハードウェア面の成立性は確認できている。

## 現在の障害と、その解決策(調査で判明)

自前プログラム(Ingenic 公式サンプル)は `IMP_System_Init` 付近で停止する。
調査で原因を 2 段階に絞り込んだ。

1. **float ABI 不一致 → 解決済み**。Nerves の musl は soft-float、libimp は
   hard-float で同居できず `Bus error` になっていた。hard-float の
   ツールチェーンでビルドして解消
2. **libimp と実機環境のビルド系統不一致 → 未解決の本命**。リンクした
   ingenic-lib の libimp は **glibc / GCC 5.4.0** だったが、実機の libimp は
   **uClibc / GCC 4.7.2**。Ingenic SDK は OEM ごとに libimp・tx-isp・
   センサドライバが改変され、SDK 番号(1.1.1)が同じでも互換とは限らない

**解決策(セカンドオピニオンとも一致)**: **実機の `/atom/system/lib/libimp.so`
を、実機の uClibc ランタイムに合わせてそのまま使う。** これにより実機の
tx-isp モジュールとの整合性が保証される。動作しない場合でも「SDK の違い」を
原因候補から外せる。

## 段階計画

### フェーズ 1: PoC(実機の libimp.so で 1 ストリーム取得)

1. **uClibc ツールチェーンを用意**(Bootlin の mips32el uclibc、hard-float)。
   ただし実機は uClibc **0.9.33.2** の古い版で、Bootlin は uClibc-ng。
   SONAME/動的リンカのパスが食い違う場合は、**実機の `/atom/lib` の uClibc
   ランタイムを sysroot として使う**(chroot 実行または `--sysroot` 指定)
2. 実機の `libimp.so` / `libalog.so` / `libsysutils.so` を動的リンクして、
   最小のエンコーダ(`IMP_System_Init` → sensor → framesource → encoder →
   1 本の H.264)をビルド
3. カメラモジュールを手動ロードし、ベンダーアプリ停止状態で実行。
   **`IMP_System_Init` を通過してフレームが取れることを確認**
   (デバッグは `fprintf(stderr,...)` + `fflush` で停止位置を追う。stdout は
   フルバッファリングされるため使わない)
4. 画質(チューニングデータ適用)・CPU・メモリを実測

### フェーズ 2: loopback へ接続

- エンコード済みフレームを `/dev/video0` へ書き込む(現行フックと同じ流儀)。
  後段(v4l2rtspserver)は無改修で RTSP 配信に載る

### フェーズ 3: Buildroot パッケージ化と監督

- `package/atomcam2-camera`(uClibc ビルド、実機 libimp を実行時に参照)
- `CameraNative` GenServer(起動・ヘルス監視・自動再起動)
- ベンダーモード(現行)とネイティブモードの排他切り替え(ISP は同時に
  1 利用者のみ)。`/data` の設定で選択
- precheck・文書・ADR 追記

## 再利用するもの / 新規に作るもの

| 区分 | 内容 |
| --- | --- |
| 再利用 | v4l2loopback、v4l2rtspserver、`atomcam2-video-loopback`(起動時ロード)、`RtspServer` の心拍監視、ベンダー資産の chroot マウント機構 |
| 新規 | `atomcam2-camera`(libimp 駆動プロセス)、`CameraNative` GenServer、uClibc ビルドの仕組み |

## 失うもの(明示)

ネイティブモード動作中は **Atom モバイルアプリ・クラウド連携が使えない**
(ISP を専有するため)。両立が必要な利用者はベンダーモードを選ぶ。連続録画・
NAS 転送はネイティブ側でも実装可能。

## リスクと検証項目

| リスク | 内容 | 対応 |
| --- | --- | --- |
| uClibc 版差 | 実機 0.9.33.2 と Bootlin uClibc-ng の SONAME 不一致 | 実機 `/atom/lib` を sysroot に。最悪 chroot 実行 |
| libimp と .ko の整合 | 実機 libimp と実機 tx-isp なら整合するはず | フェーズ 1 で確認。これでも駄目なら別要因に切り分け |
| ベンダー独自の前処理 | `ver-comp` 等が ISP 初期化に必要な可能性 | `ver-comp` の open/ioctl/`/proc` アクセスを観察し、必要な初期化を再現 |
| メモリ | ネイティブプロセスの実フットプリント | フェーズ 1 で実測。`iCamera_app`(18MB)より小さい見込み |
| 音声 | 本カーネルは ALSA 非搭載 | libimp の AI API は ALSA 非依存の可能性。まず映像のみ |
| ライセンス | ベンダー .ko / libimp / チューニングデータ | **再配布せず**、実機 `/atom` から実行時に読む(現行ベンダーモードと同じ整理) |

## 位置づけ

[RTSP 実装方針 技術相談](20260803_RTSP実装方針_技術相談.md)の評価では、
本方式は「研究テーマ」(成功すれば価値大だが成否・工数が読めない)。本提案は
その研究を進めるための**具体的な次の一手**を確定させたもの。成功すれば、
現行のフック方式(方式 A)を置き換え、ブラックボックス依存・チャンネル競合・
18MB のメモリ消費をすべて解消できる。

## 関連文書

- [カメラ参照機能スクラッチ実装 提案書](20260802_カメラ参照機能スクラッチ実装_提案書.md) —
  方式 B の全体構想と部品調査
- [ネイティブカメラ実装 技術相談](20260803_ネイティブカメラ実装_技術相談.md) —
  `IMP_System_Init` 停止の詳細な切り分けと助言
- [RTSP 配信 提案書](20260802_RTSP配信_提案書.md) — 再利用する後段(v4l2loopback
  + v4l2rtspserver)の設計
- [平常時メモリ削減 提案書](20260803_平常時メモリ削減_提案書.md) — 本方式が
  実現する 18MB 削減の位置づけ
