# 20260713 最初のネットワーク試験に必要な実行時前提

## 状態

この文書は、system をビルド成果物から起動可能な Nerves 利用者空間へ近づけた変更の
中間確認表です。ping と SSH の最終的な根本原因記録ではありません。

後に確認した阻害要因は次に記載しています。

- [`20260713-atomcam2-toolchain-dsp-ase-investigation.md`](20260713-atomcam2-toolchain-dsp-ase-investigation.md)
- [`20260714-sdio-wifi-driver-bring-up.md`](20260714-sdio-wifi-driver-bring-up.md)
- [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md)

## この段階で導入した変更

- initramfs の実行ファイルに必要な musl loader を追加した
- Wi-Fi device が使用する T31 MMC1 SDIO controller を有効にした
- 生成する root filesystem で gzip 互換の SquashFS 対応を有効にした
- 正常動作する既知の Atom Cam 2 kernel command line を復元した
- hardware の初期準備情報を取得するため、ベンダー system および configuration
  partition を読み取り専用でマウントした
- ベンダーの SDIO 準備と Wi-Fi module 読み込み順序を再利用した
- ネットワーク設定前に工場設定の Wi-Fi MAC address を復元した
- `wlan0` を待つ時間に上限を設けた
- 独自 kernel の作業から利用者空間を分離して試験するため、正常動作する既知の
  ベンダー kernel を一時的な上書きとして維持した

## この段階で確立したこと

これらの変更により試験可能な起動経路を作りましたが、`nerves.local` が存在しないこと
だけでは失敗層を識別できませんでした。

その後の調査で、次を個別に証明しました。

```text
boot and rootfs
-> dynamic userspace
-> Erlang release
-> SDIO and vendor driver
-> VintageNet native monitor
-> wpa_supplicant configuration
-> DHCP, mDNS, and SSH
```

## 維持した試験順序

有効な確認順序は次のとおりです。

1. 稼働中の root filesystem と `/sbin/init` を確認する
2. `/srv/erlang` 配下の Erlang release を確認する
3. SDIO 準備とベンダー module の読み込みを確認する
4. `/sys/class/net/wlan0` または `ip` で `wlan0` を確認する
5. VintageNet 設定を確認する
6. IP address を直接指定し、Wi-Fi 接続と DHCP を確認する
7. `nerves.local` を確認する
8. SSH 公開鍵接続を確認する
