#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
system_version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
toolchain_version="$(tr -d '[:space:]' < "$repo_root/toolchain/VERSION")"
version="$system_version"
release_tag="v$version"
output_dir="$repo_root/tmp/release/$release_tag"
control_kernel="${ATOMCAM2_KERNEL_IMAGE:-$repo_root/target/atomcam2-control/factory_t31_ZMC6tiIDQN}"
expected_kernel_sha256="b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc"
publish="0"
verify="0"
force="0"

usage() {
  cat <<'USAGE'
Usage:
  release-artifacts.sh [OPTIONS]

Build the Atom Cam 2 custom toolchain and Nerves system release artifacts.

Options:
  --output PATH  Artifact output directory.
  --publish      Create the matching Git tag and GitHub release, then upload
                 the artifacts.
  --verify       Clone the release tag and build the example app with isolated
                 Nerves caches and no local system/toolchain overrides.
  --force        Replace an existing local artifact output directory.
  -h, --help     Show this help.

The custom compiler directory must be available through NERVES_TOOLCHAIN.
ATOMCAM2_KERNEL_IMAGE may override the verified control kernel path.
Publishing requires a clean Git worktree and an authenticated gh command.
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  else
    fail "required command not found: $command_name"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      if [ "$#" -lt 2 ]; then
        fail "--output requires a path"
      else
        output_dir="$2"
        shift 2
      fi
      ;;
    --publish)
      publish="1"
      shift
      ;;
    --verify)
      verify="1"
      shift
      ;;
    --force)
      force="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

require_command git

if [ -z "$system_version" ]; then
  fail "system VERSION is empty"
elif [ -z "$toolchain_version" ]; then
  fail "toolchain VERSION is empty"
elif [ "$system_version" != "$toolchain_version" ]; then
  fail "system and toolchain versions differ: $system_version != $toolchain_version"
fi

reuse_artifacts="0"

if [ -e "$output_dir" ]; then
  if [ "$force" = "1" ]; then
    rm -rf "$output_dir"
  elif [ "$publish" = "1" ] || [ "$verify" = "1" ]; then
    reuse_artifacts="1"
  else
    fail "output directory already exists: $output_dir (pass --force to replace it)"
  fi
fi

if [ "$reuse_artifacts" = "0" ]; then
  require_command elixir
  require_command mix
  require_command sha256sum
  require_command tar

  if [ -z "${NERVES_TOOLCHAIN:-}" ]; then
    fail "NERVES_TOOLCHAIN must point to the validated Atom Cam 2 compiler directory"
  elif [ ! -d "$NERVES_TOOLCHAIN" ]; then
    fail "NERVES_TOOLCHAIN is not a directory: $NERVES_TOOLCHAIN"
  elif [ ! -x "$NERVES_TOOLCHAIN/bin/mipsel-nerves-linux-musl-gcc" ]; then
    fail "compiler not found under NERVES_TOOLCHAIN: $NERVES_TOOLCHAIN"
  fi

  if [ ! -f "$control_kernel" ]; then
    fail "AtomCam2 control kernel not found: $control_kernel"
  fi

  actual_kernel_sha256="$(sha256sum "$control_kernel" | awk '{print $1}')"

  if [ "$actual_kernel_sha256" != "$expected_kernel_sha256" ]; then
    fail "unexpected AtomCam2 control kernel SHA256: $actual_kernel_sha256"
  fi

  mkdir -p "$output_dir"
  "$repo_root/scripts/prepare-toolchain-archive.sh" --force

  host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  host_arch="$(uname -m)"

  if [ "$host_os" = "linux" ]; then
    :
  else
    fail "toolchain artifact packaging is currently supported only on Linux"
  fi

  case "$host_arch" in
    x86_64|aarch64|arm)
      ;;
    *)
      fail "unsupported host architecture: $host_arch"
      ;;
  esac

  toolchain_checksum="$({
    cd "$repo_root/toolchain"

    elixir -e '
      Application.ensure_all_started(:mix)

      modules =
        "mix.exs"
        |> Code.compile_file()
        |> Enum.map(fn {module, _bytecode} -> module end)

      project_module =
        Enum.find(modules, fn module ->
          function_exported?(module, :project, 0) and
            String.ends_with?(Atom.to_string(module), ".MixProject")
        end) ||
          raise "could not find the toolchain Mix project"

      checksum_paths =
        project_module.project()
        |> Keyword.fetch!(:nerves_package)
        |> Keyword.fetch!(:checksum)

      files =
        checksum_paths
        |> Enum.flat_map(fn path ->
          path
          |> Path.wildcard()
          |> Enum.flat_map(fn entry ->
            if File.dir?(entry) do
              Path.wildcard(Path.join(entry, "**"))
            else
              [entry]
            end
          end)
        end)
        |> Enum.filter(&File.regular?/1)
        |> Enum.uniq()

      checksum =
        files
        |> Enum.map(&File.read!/1)
        |> Enum.map(&:crypto.hash(:sha256, &1))
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16()
        |> binary_part(0, 7)

      IO.puts(checksum)
    '
  })"

  toolchain_name="nerves_toolchain_atomcam2-${host_os}_${host_arch}-${version}-${toolchain_checksum}.tar.xz"
  toolchain_path="$output_dir/$toolchain_name"
  toolchain_parent="$(cd -- "$NERVES_TOOLCHAIN/.." && pwd)"
  toolchain_basename="$(basename -- "$NERVES_TOOLCHAIN")"

  if ! tar --version 2>/dev/null | grep -q 'GNU tar'; then
    fail "GNU tar is required to rename the toolchain root in the release archive"
  fi

  tar \
    -C "$toolchain_parent" \
    --transform="s,^${toolchain_basename},nerves_toolchain_atomcam2," \
    -cJf "$toolchain_path" \
    "$toolchain_basename"

  first_entry="$(tar -tJf "$toolchain_path" | sed -n '1p')"
  case "$first_entry" in
    nerves_toolchain_atomcam2/*|nerves_toolchain_atomcam2)
      ;;
    *)
      fail "unexpected toolchain archive root: $first_entry"
      ;;
  esac

  (
    cd "$repo_root"

    export ATOMCAM2_KERNEL_IMAGE="$control_kernel"

    MIX_ENV=prod mix deps.get
    MIX_ENV=prod mix nerves.artifact --path "$output_dir"
  )

  (
    cd "$output_dir"
    sha256sum ./*.tar.gz ./*.tar.xz > SHA256SUMS
  )
fi

system_count="$(find "$output_dir" -maxdepth 1 -type f -name "nerves_system_atomcam2-portable-${version}-*.tar.gz" | wc -l | tr -d '[:space:]')"
toolchain_count="$(find "$output_dir" -maxdepth 1 -type f -name "nerves_toolchain_atomcam2-*-${version}-*.tar.xz" | wc -l | tr -d '[:space:]')"

if [ "$system_count" != "1" ]; then
  fail "expected one system artifact, found $system_count in $output_dir"
elif [ "$toolchain_count" != "1" ]; then
  fail "expected one toolchain artifact, found $toolchain_count in $output_dir"
elif [ ! -s "$output_dir/SHA256SUMS" ]; then
  fail "missing checksum manifest: $output_dir/SHA256SUMS"
fi

echo "Release artifacts created:"
find "$output_dir" -maxdepth 1 -type f -printf '  %f\n' | sort

if [ "$publish" = "1" ]; then
  require_command gh

  if [ -n "$(git -C "$repo_root" status --short)" ]; then
    fail "the Git worktree must be clean before publishing"
  fi

  gh auth status >/dev/null

  if gh release view "$release_tag" --repo mnishiguchi/nerves_system_atomcam2 >/dev/null 2>&1; then
    fail "GitHub release already exists: $release_tag"
  fi

  mapfile -t release_files < <(find "$output_dir" -maxdepth 1 -type f | sort)

  gh release create "$release_tag" \
    "${release_files[@]}" \
    --repo mnishiguchi/nerves_system_atomcam2 \
    --target "$(git -C "$repo_root" rev-parse HEAD)" \
    --title "nerves_system_atomcam2 $version" \
    --generate-notes
fi

if [ "$verify" = "1" ]; then
  require_command mix

  verification_root="$(mktemp -d)"
  trap 'rm -rf "$verification_root"' EXIT

  git clone \
    --branch "$release_tag" \
    --depth 1 \
    https://github.com/mnishiguchi/nerves_system_atomcam2.git \
    "$verification_root/repository"

  verification_app="$verification_root/repository/examples/atomcam2_nerves_app"
  verification_data="$verification_root/xdg"

  (
    cd "$verification_app"
    env \
      -u NERVES_SYSTEM \
      -u NERVES_TOOLCHAIN \
      -u ATOMCAM2_SYSTEM_SOURCE \
      XDG_DATA_HOME="$verification_data" \
      MIX_TARGET=atomcam2 \
      MIX_ENV=prod \
      mix setup

    env \
      -u NERVES_SYSTEM \
      -u NERVES_TOOLCHAIN \
      -u ATOMCAM2_SYSTEM_SOURCE \
      XDG_DATA_HOME="$verification_data" \
      MIX_TARGET=atomcam2 \
      MIX_ENV=prod \
      mix firmware
  )

  firmware="$verification_app/_build/atomcam2_prod/nerves/images/atomcam2_nerves_app.fw"
  payload="$verification_app/_build/atomcam2_prod/nerves/images/atomcam2-sd"

  if [ ! -s "$firmware" ]; then
    fail "clean-checkout firmware was not created: $firmware"
  elif [ ! -d "$payload" ]; then
    fail "clean-checkout SD payload was not created: $payload"
  fi

  verified_output="$output_dir/verified-application"
  rm -rf "$verified_output"
  mkdir -p "$verified_output"
  cp "$firmware" "$verified_output/atomcam2_nerves_app.fw"
  cp -a "$payload" "$verified_output/atomcam2-sd"

  echo "Clean-checkout release verification succeeded."
  echo "Verified firmware: $verified_output/atomcam2_nerves_app.fw"
  echo "Verified payload: $verified_output/atomcam2-sd"
fi
