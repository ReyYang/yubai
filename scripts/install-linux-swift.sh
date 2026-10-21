#!/usr/bin/env bash
# 在没有 swift.org 访问权限的 Linux（如云端容器）里安装 Swift 工具链。
# 从 Docker Hub 官方 swift 镜像直接下载层并解压，不需要 docker 守护进程。
# 用法：scripts/install-linux-swift.sh [前缀目录]，默认 /opt/swift-rootfs；
# 完成后 export PATH=<前缀>/usr/bin:$PATH。
set -euo pipefail

tag="${SWIFT_IMAGE_TAG:-6.2-noble}"
prefix="${1:-/opt/swift-rootfs}"

if [ -x "$prefix/usr/bin/swift" ] && "$prefix/usr/bin/swift" --version >/dev/null 2>&1; then
  "$prefix/usr/bin/swift" --version
  exit 0
fi

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

registry=https://registry-1.docker.io/v2/library/swift
token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/swift:pull" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
auth="Authorization: Bearer $token"

index=$(curl -fsSL -H "$auth" \
  -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json' \
  "$registry/manifests/$tag")
digest=$(python3 -c '
import json, sys
for m in json.loads(sys.argv[1])["manifests"]:
    if m["platform"].get("os") == "linux" and m["platform"].get("architecture") == sys.argv[2]:
        print(m["digest"]); break
' "$index" "$arch")

layers=$(curl -fsSL -H "$auth" \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json' \
  "$registry/manifests/$digest" |
  python3 -c 'import json,sys; [print(l["digest"]) for l in json.load(sys.stdin)["layers"]]')

mkdir -p "$prefix"
for layer in $layers; do
  echo "下载并解压 $layer"
  curl -fsSL --retry 5 --retry-delay 30 -H "$auth" "$registry/blobs/$layer" | tar -xz -C "$prefix" --exclude='dev/*'
done

"$prefix/usr/bin/swift" --version
