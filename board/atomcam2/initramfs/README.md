# AtomCam2 initramfs

このディレクトリには、最初の AtomCam2 initramfs の文章部分を置く。

ここで維持する重要な `atomcam_tools` 起動方式は、製造元名のカーネル画像から、FAT パーティション上の `rootfs_hack.squashfs` へ引き渡す処理である。initramfs は小さなシェル環境を含み、SD カードをマウントし、Nerves SquashFS をマウントし、FAT マウントを `/media/mmc` へ移動してから `switch_root` する。

現在の範囲は次のとおりである。

- SD カードの第一パーティションを VFAT としてマウントする。
- `rootfs_hack.squashfs` を見つける。
- 新しいルートファイルシステムとしてマウントする。
- `dev`、`proc`、`sys`、SD カードのマウントを新しいルートへ移す。
- `/sbin/init` へ `switch_root` する。

最初の実装では次を後回しにする。

- exFAT 第二パーティション対応
- 機器上での更新展開
- rootfs の大きさ検証
- 製造元復旧経路

## 必要なカーネル機能

initramfs の引き渡し処理では、次のカーネル機能をモジュールではなく組み込みで必要とする。

- MMC ブロックデバイス対応
- SD カード起動用パーティションに必要な VFAT と NLS 表
- gzip 圧縮された `rootfs_hack.squashfs` 用の zlib 対応 SquashFS
- SquashFS 画像をファイルからマウントするための loop ブロックデバイス
- devtmpfs、procfs、sysfs

## BusyBox 実行環境

initramfs の BusyBox は、独自の純 MIPS32R2 musl 道具鎖で動的連結する。そのため initramfs には、対応する `libc.so` と `/lib/ld-musl-mipsel-sf.so.1` の別名を含める。組み込み initramfs を小さく保つため、BusyBox の小道具は実行形式の複製ではなくシンボリックリンクにする。
