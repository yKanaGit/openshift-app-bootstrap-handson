#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v oc >/dev/null 2>&1; then
  echo "ERROR: oc CLI が見つかりません。oc をインストールしてから再実行してください。" >&2
  exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "ERROR: oc login が必要です。OpenShift cluster にログインしてから再実行してください。" >&2
  exit 1
fi

wait_for_namespace() {
  local namespace="$1"
  local timeout_seconds="$2"
  local elapsed_seconds=0

  echo "Waiting for namespace/${namespace} ..."
  until oc get namespace "${namespace}" >/dev/null 2>&1; do
    if (( elapsed_seconds >= timeout_seconds )); then
      echo "ERROR: namespace/${namespace} の作成待ちがタイムアウトしました。" >&2
      exit 1
    fi
    sleep 10
    elapsed_seconds=$((elapsed_seconds + 10))
  done
}

wait_for_deployment() {
  local namespace="$1"
  local deployment="$2"
  local timeout_seconds="$3"
  local elapsed_seconds=0

  echo "Waiting for deployment/${deployment} in namespace/${namespace} ..."
  until oc get deployment "${deployment}" -n "${namespace}" >/dev/null 2>&1; do
    if (( elapsed_seconds >= timeout_seconds )); then
      echo "ERROR: deployment/${deployment} の作成待ちがタイムアウトしました。" >&2
      exit 1
    fi
    sleep 10
    elapsed_seconds=$((elapsed_seconds + 10))
  done

  oc wait deployment/"${deployment}" \
    -n "${namespace}" \
    --for=condition=Available \
    --timeout="${timeout_seconds}s"
}

wait_for_crd() {
  local crd="$1"
  local timeout_seconds="$2"
  local elapsed_seconds=0

  echo "Waiting for crd/${crd} ..."
  until oc get crd "${crd}" >/dev/null 2>&1; do
    if (( elapsed_seconds >= timeout_seconds )); then
      echo "ERROR: crd/${crd} の作成待ちがタイムアウトしました。" >&2
      exit 1
    fi
    sleep 10
    elapsed_seconds=$((elapsed_seconds + 10))
  done

  oc wait crd/"${crd}" --for=condition=Established --timeout="${timeout_seconds}s"
}

echo "Applying OpenShift GitOps Operator manifest ..."
oc apply -f "${SCRIPT_DIR}/bootstrap/openshift-gitops-operator.yaml"

wait_for_namespace "openshift-gitops" 600
wait_for_crd "applicationsets.argoproj.io" 600

wait_for_deployment "openshift-gitops" "openshift-gitops-server" 600
wait_for_deployment "openshift-gitops" "openshift-gitops-repo-server" 600
wait_for_deployment "openshift-gitops" "openshift-gitops-redis" 600
wait_for_deployment "openshift-gitops" "openshift-gitops-applicationset-controller" 600

echo "Applying ApplicationSet manifest ..."
oc apply -f "${SCRIPT_DIR}/bootstrap/applicationset.yaml"

cat <<'EOF'

Setup completed.

確認コマンド:
  oc get applications -n openshift-gitops
  oc get applicationsets -n openshift-gitops
  oc get pods -n shipper-dev
  oc get route -n shipper-dev

Route URL 確認:
  oc get route shipper-onboarding-api -n shipper-dev -o jsonpath='https://{.spec.host}{"\n"}'

private repo の場合:
  bootstrap/repo-creds.example.yaml をコピーして値を編集し、手動で oc apply してください。
EOF
