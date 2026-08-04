# Atom Cam 2 Nerves 道具鎖小包

この小包は、`nerves_system_atomcam2` が使用する構築済み MIPS32R2 ソフトウェア浮動小数点道具鎖を定義する。

Ingenic T31 には、DSP ASE 命令を含まない純粋な MIPS32 Release 2 コンパイラーが必要である。アプリケーション開発者は、システム依存を通じて公開済み道具鎖成果物を自動的に利用する。

## 構築入力

コンパイラーは公式 Nerves 道具鎖リポジトリを元にする。

- リポジトリ: `https://github.com/nerves-project/toolchains.git`
- リビジョン: `fa8f8ba3fd3927b2b4fcc23f3d71918e53fec5ba`
- 基礎小包: `nerves_toolchain_mipsel_nerves_linux_musl`
- 独自命令体系: `mips32r2`
- バイト順: リトルエンディアン
- ABI: MIPS o32
- 浮動小数点: ソフトウェア
- DSP ASE: 無効

正確な上流原本と小包名は `UPSTREAM` に記録する。独自 Crosstool-NG 設定は `defconfig` に記録する。

これらのファイルを、公開道具鎖成果物の検査値入力とする。

## コンパイラーの再現

変更済みの開発用作業場所に依存せず、清潔な一時複製を作る。

```sh
atomcam2_root="$(git rev-parse --show-toplevel)"
build_root="$(mktemp -d)"
toolchains_root="$build_root/toolchains"
package="nerves_toolchain_mipsel_nerves_linux_musl"
revision="$(
  sed -n 's/^revision=//p' "$atomcam2_root/toolchain/UPSTREAM"
)"

git clone \
  https://github.com/nerves-project/toolchains.git \
  "$toolchains_root"

git -C "$toolchains_root" checkout --detach "$revision"

cp \
  "$atomcam2_root/toolchain/defconfig" \
  "$toolchains_root/configs/$package/defconfig"

(
  cd "$toolchains_root"

  make

  bash \
    "$package/build.sh" \
    "$toolchains_root/o/$package"
)
```

生成されるコンパイラーディレクトリは次である。

```text
o/nerves_toolchain_mipsel_nerves_linux_musl/x-tools/mipsel-nerves-linux-musl
```

使用前に、GCC の既定値が `mips32r2` とソフトウェア浮動小数点であり、二つの DSP 命令集合選択肢がいずれも無効であることを確認する。
