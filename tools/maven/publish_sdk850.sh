#!/usr/bin/env bash
# Publica o .aar do fabricante no repositório Maven (padrão: ../../maven-repo).
# Uso: tools/maven/publish_sdk850.sh [-Psdk850PublishUrl=https://repo.interno/releases]
set -euo pipefail
cd "$(dirname "$0")"
./gradlew --no-daemon publish "$@"
