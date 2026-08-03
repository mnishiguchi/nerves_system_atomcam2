# atomcam2-boot-announce

起動アナウンス用のスピーカー再生ツール `atomcam2-aoplay`(ビルド済み
バイナリ + ソース)と音声データを rootfs に載せる Buildroot パッケージ。
再生スクリプトは `rootfs_overlay/usr/bin/atomcam2-boot-announce` で、
Elixir アプリの `Atomcam2NervesApp.BootAnnounce`(Task)が起動時に一度
呼び出す。iCamera_app を使用しない(native 専業)前提で、audio 系
カーネルモジュールが未ロードならスクリプト自身が insmod する。

## 収録物

- `atomcam2-aoplay` — libimp `IMP_AO` で raw PCM を再生するツール
  (→ `/usr/bin/atomcam2-aoplay`)
- `boot-announce.raw` — 「起動しました。」signed 16-bit LE / 8000 Hz /
  mono raw PCM(→ `/usr/share/atomcam2/boot-announce.raw`)
- `aoplay.c` — 上記バイナリのソース

## なぜビルド済みバイナリをコミットするか

`aoplay` は実機の `/atom/system/lib/libimp.so`(uClibc 0.9.33.2 / GCC 4.7.2
ビルド)を動的リンクするため、Buildroot のツールチェーン(musl)では
ビルドできない。Ingenic 純正の MIPS uClibc ツールチェーンと T31 SDK 1.1.1
ヘッダが必要で、どちらもリポジトリには含めていない。

## ビルド手順

1. ツールチェーン: Ingenic GCC 4.7.2 / uClibc 0.9.33.2
   (`mips-linux-uclibc-gnu-gcc`)。
2. SDK ヘッダ: GitHub `cgrrty/Ingenic-SDK-T31-1.1.1-20200508` の `include/imp/`
   一式(エンコーダ以外は新旧互換だが、1.1.1 完全一致版を使うこと)。
3. リンク用に実機の `/atom/system/lib/{libimp.so,libalog.so}` を手元へコピー。

```sh
mips-linux-uclibc-gnu-gcc -O2 -march=mips32r2 \
  -I<sdk-include> \
  -Wl,--dynamic-linker=/atom/lib/ld-uClibc.so.0 \
  aoplay.c -L<device-libs> -limp -lalog -lpthread -lm -lrt \
  -o atomcam2-aoplay
```

`--dynamic-linker` の明示が必須(Nerves ルートには `/lib/ld-uClibc.so.0` が
無いため)。実行時は `LD_LIBRARY_PATH=/atom/system/lib:/atom/lib` を与える。

## 実行条件

- `audio.ko` と `speaker_ctl.ko` がロード済みであること
  (`atomcam2-boot-announce` 経由なら未ロード時に自動 insmod される)
- 音声デバイスが未使用であること(`iCamera_app` 稼働中は IMPAudio の
  ロックを握るため再生できない。atomcam_tools issue #23 参照。
  iCamera_app 不使用の native 運用では常に満たされる)
- 使い方: `atomcam2-aoplay <file.raw> [gain 0-4] [rate] [volume]`
  (既定: gain 1 / 8000 Hz / volume 60、100 = 0dB)
- 短い音声が冒頭で切れる場合は teardown 前の `IMP_AO_FlushChnBuf`
  (排出完了待ち)が入っているか確認する(aoplay.c は対応済み)

## 起動アナウンス音声の差し替え・無効化

signed 16-bit LE / 8000 Hz / mono の raw PCM を用意し、この
`boot-announce.raw` を置き換えてリビルドする。SD カードの `atomcam2.env`
で `ATOMCAM2_BOOT_ANNOUNCE_SOUND` を上書きすればリビルドなしでも
差し替えられる(無効化は `ATOMCAM2_BOOT_ANNOUNCE=disabled`)。
