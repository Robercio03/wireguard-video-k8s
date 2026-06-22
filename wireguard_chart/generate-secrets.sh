#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-wireguard}"
OUTPUT_DIR="./wg-keys"

KUBECTL="microk8s kubectl"

NODES=("control-plane" "worker-1" "worker-2")

echo "=============================================="
echo "  WireGuard Key Generator — MicroK8s"
echo "  Namespace: ${NAMESPACE}"
echo "=============================================="
echo ""

if ! command -v wg &>/dev/null; then
  echo "❌ ERROR: 'wg' no está instalado."
  echo "   Ejecuta: sudo apt-get install -y wireguard-tools"
  exit 1
fi

if ! microk8s kubectl version --client &>/dev/null 2>&1; then
  echo "❌ ERROR: 'microk8s kubectl' no funciona."
  echo "   Asegúrate de estar en el nodo control-plane."
  exit 1
fi

if ! $KUBECTL get namespace "$NAMESPACE" &>/dev/null 2>&1; then
  echo "📦 Creando namespace '${NAMESPACE}'..."
  $KUBECTL create namespace "$NAMESPACE"
else
  echo "✅ Namespace '${NAMESPACE}' ya existe."
fi

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

echo ""
echo "🔑 Generando keypairs..."
echo ""

declare -A PUBLIC_KEYS

for NODE in "${NODES[@]}"; do
  PRIVATE_KEY_FILE="$OUTPUT_DIR/${NODE}.private"
  PUBLIC_KEY_FILE="$OUTPUT_DIR/${NODE}.public"
  SECRET_NAME="wg-key-${NODE}"

  wg genkey | tee "$PRIVATE_KEY_FILE" | wg pubkey > "$PUBLIC_KEY_FILE"
  chmod 600 "$PRIVATE_KEY_FILE"
  chmod 644 "$PUBLIC_KEY_FILE"

  PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
  PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
  PUBLIC_KEYS[$NODE]="$PUBLIC_KEY"

  echo "   Nodo: $NODE"
  echo "   Pública: $PUBLIC_KEY"

  if $KUBECTL get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null 2>&1; then
    echo "   ⚠️  Secret '$SECRET_NAME' ya existe, actualizando..."
    $KUBECTL create secret generic "$SECRET_NAME" \
      --from-literal=privateKey="$PRIVATE_KEY" \
      --namespace="$NAMESPACE" \
      --dry-run=client -o yaml | $KUBECTL apply -f -
  else
    $KUBECTL create secret generic "$SECRET_NAME" \
      --from-literal=privateKey="$PRIVATE_KEY" \
      --namespace="$NAMESPACE"
    echo "   ✅ Secret '$SECRET_NAME' creado."
  fi
  echo ""
done

echo "🔍 Verificando Secrets creados:"
$KUBECTL get secrets -n "$NAMESPACE" | grep wg-key || true
echo ""

echo "=============================================="
echo ""
echo "✅ Pasar claves públicas al values.yaml:"
echo ""
echo "publicKeys:"
for NODE in "${NODES[@]}"; do
  printf "  %-20s \"%s\"\n" "${NODE}:" "${PUBLIC_KEYS[$NODE]}"
done
echo ""
echo "=============================================="
echo ""
echo "Próximo paso:"
echo "  1. Pega el bloque publicKeys en values.yaml"
echo "  2. Ajusta los hostnames de los nodos en values.yaml:"
echo "     microk8s kubectl get nodes"
echo "  3. Instala el chart:"
echo "     helm install wireguard ./wireguard-chart --namespace ${NAMESPACE}"
echo "=============================================="
