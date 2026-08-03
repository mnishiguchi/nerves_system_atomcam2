# atomcam2-camera

iCamera_app を置き換えるネイティブカメラデーモン `atomcam2-camd`
(ビルド済みバイナリ + ソース)を rootfs に載せる Buildroot パッケージ。
起動・監視は Elixir の `Atomcam2NervesApp.CameraNative` が行う。

## 動作

- パイプライン: sensor(GC2053) → ISP → FrameSource → OSD → H.264 →
  v4l2loopback(`/dev/video0`)書き出し
- 実行: `atomcam2-camd <frames> <loopback> <sensor> <i2c-addr> [bitrate-kbps]`
  (例: `atomcam2-camd 2000000000 /dev/video0 gc2053 0x37`)。
  第 1 引数はフレーム数上限。終了したら監督側が再起動する
- 実行時制御: **`/tmp/camd.ctl`** に 1 コマンドずつ書く
  (`clock on|off` / `logo on|off` / `bitrate <kbps>` / `qp <min> <max>` /
  `clockpos <x> <y>` / `logopos <x> <y>` / `quit`)。
  /data 非依存にするため `/data/camd.ctl` から移した
- 依存: `/atom/system/lib` の libimp ほか(実行時
  `LD_LIBRARY_PATH=/atom/system/lib:/atom/lib`)、カメラ系カーネル
  モジュール(tx_isp_t31 / sensor_gc2053_t31 / avpu / sinfo)

## なぜビルド済みバイナリをコミットするか

実機の `/atom/system/lib/libimp.so`(uClibc 0.9.33.2 / GCC 4.7.2 ビルド)を
動的リンクするため、Buildroot のツールチェーン(musl)ではビルドできない
(`package/atomcam2-boot-announce/` の aoplay と同じ事情)。

## ビルド手順

1. ツールチェーン: Ingenic GCC 4.7.2 / uClibc 0.9.33.2
   (`mips-linux-uclibc-gnu-gcc`)
2. SDK ヘッダ: `cgrrty/Ingenic-SDK-T31-1.1.1-20200508` の `include/imp/`
   (エンコーダ API は 1.1.1 完全一致が必須。旧ヘッダは ABI 不一致で
   `invalid resolution(0x0)` になる)
3. OSD 用データ: atomcam_tools の ingenic_samples `libimp-samples`
   (`logodata_100x100_bgra.h` / `bgramapinfo.h`)
4. リンク用に実機の `/atom/system/lib/{libimp.so,libalog.so}` をコピー

```sh
mips-linux-uclibc-gnu-gcc -O2 -march=mips32r2 \
  -I<sdk-include> -I<libimp-samples> \
  -Wl,--dynamic-linker=/atom/lib/ld-uClibc.so.0 \
  camd.c -L<device-libs> -limp -lalog -lpthread -lm -lrt \
  -o atomcam2-camd
```

## 実装メモ(ハマりどころ)

- エンコーダは T31 1.1.1 の新 API(`IMP_Encoder_SetDefaultParam`)。
  ストリームは `IMPEncoderPack.offset` + リング折り返しで読む
- ループバックへは `VIDIOC_S_FMT`(H264)+ `STREAMON` 後にフレーム毎
  write。**書き手が S_FMT してから** v4l2rtspserver を起動すること
