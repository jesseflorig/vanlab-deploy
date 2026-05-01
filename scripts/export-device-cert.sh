#!/usr/bin/env bash
# Exports the management laptop device cert from the cluster to a local .p12 bundle.
# Requires: kubectl (authenticated), openssl
# Output: ~/fleet1-laptop-cert.p12

set -euo pipefail

SECRET_NAME="laptop-client-cert-tls"
NAMESPACE="cert-manager"
CERT_FILE="$(mktemp)"
KEY_FILE="$(mktemp)"
OUTPUT="$HOME/fleet1-laptop-cert.p12"

trap 'rm -f "$CERT_FILE" "$KEY_FILE"' EXIT

echo "Fetching device cert from $NAMESPACE/$SECRET_NAME..."
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_FILE"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.tls\.key}' | base64 -d > "$KEY_FILE"

echo "Exporting to $OUTPUT (you will be prompted for a passphrase)..."
openssl pkcs12 -export \
  -in "$CERT_FILE" \
  -inkey "$KEY_FILE" \
  -out "$OUTPUT" \
  -name "fleet1-management-laptop"

echo "Done. Import $OUTPUT into your keychain or browser."
