# OpenShift App Bootstrap Handson

このリポジトリは、OpenShift GitOps / Argo CD ApplicationSet と Kustomize を使って、通常の OpenShift コンテナアプリをブートストラップ配備するためのハンズオン用リポジトリです。

題材は汎用的な `workload` です。初期状態では `https://github.com/yKanaGit/Sample-app01.git` のコードを OpenShift BuildConfig でコンテナ化し、OpenShift 内部 ImageStream から Deployment に配備します。PostgreSQL、Tekton CI/CD、OpenShift AI、GPU Operator、NFD、LLM Serving、VLM Serving、OpenWebUI 関連の manifest は含めていません。

## アーキテクチャ

```text
GitHub repository
  |
  | bootstrap/applicationset.yaml
  v
OpenShift GitOps / Argo CD
  |
  | ApplicationSet list generator
  +--> Application: workload-dev  -> apps/workload/overlays/dev  -> namespace workload-dev
  |
  +--> Application: workload-prod -> apps/workload/overlays/prod -> namespace workload-prod
       (prod は手動同期を想定)

Kustomize overlay
  |
  +--> ImageStream / BuildConfig / Deployment / Service / Route / ConfigMap

BuildConfig
  |
  +--> GitHub: yKanaGit/Sample-app01 -> Docker build -> ImageStream: workload:latest
                                             |
                                             v
                                       Deployment: workload
```

## ディレクトリ構成

```text
bootstrap/
  openshift-gitops-operator.yaml
  argocd-app-rbac.yaml
  applicationset.yaml
  repo-creds.example.yaml
apps/
  workload/
    base/
    overlays/
      dev/
      prod/
```

## 前提条件

- OpenShift cluster が利用できること
- `cluster-admin`、または Operator / Argo CD を導入できる権限があること
- `oc` CLI が利用できること
- OpenShift GitOps Operator をインストールできること
- このリポジトリを GitHub に push して Argo CD から参照できること

## セットアップ

1. OpenShift にログインします。

```bash
oc login <api-server>
```

2. 必要に応じて `bootstrap/applicationset.yaml` の `repoURL` を自分の GitHub URL に変更します。初期値は次です。

```text
https://github.com/yKanaGit/openshift-app-bootstrap-handson.git
```

3. セットアップスクリプトを実行します。

```bash
chmod +x setup.sh
./setup.sh
```

`setup.sh` は OpenShift GitOps Operator を導入し、`openshift-gitops` namespace の Argo CD 関連 Deployment が利用可能になってから、アプリ配備先 namespace 用の RoleBinding と ApplicationSet を適用します。private repo 用の credentials は自動適用しません。

## 動作確認

```bash
oc get applications -n openshift-gitops
oc get applicationsets -n openshift-gitops
oc get builds -n workload-dev
oc get imagestream workload -n workload-dev
oc get pods -n workload-dev
oc get route -n workload-dev
```

Route URL は次のコマンドで確認できます。

```bash
oc get route workload -n workload-dev -o jsonpath='https://{.spec.host}{"\n"}'
```

取得した URL にアクセスすると、`Sample-app01` からビルドされたアプリに到達できます。

`workload-dev` が `OutOfSync / Missing` のまま Pod が作成されない場合は、Application に automated sync が入っているか確認します。

```bash
oc get application workload-dev -n openshift-gitops -o jsonpath='{.spec.syncPolicy}{"\n"}'
```

空の場合は、最新の `bootstrap/applicationset.yaml` を push したうえで再適用します。

```bash
oc apply -f bootstrap/argocd-app-rbac.yaml
oc apply -f bootstrap/applicationset.yaml
```

`operationState.message` に `cannot create resource "deployments"` や `cannot create resource "routes"` が出る場合も、`bootstrap/argocd-app-rbac.yaml` を適用してください。これは OpenShift GitOps の application-controller に `workload-dev` / `workload-prod` への配備権限を渡すための RoleBinding です。

## dev / prod の違い

| 環境 | Application 名 | namespace | replicas | APP_ENV | LOG_LEVEL | 同期方式 |
| --- | --- | --- | ---: | --- | --- | --- |
| dev | `workload-dev` | `workload-dev` | 1 | `dev` | `debug` | automated sync、prune/selfHeal 有効 |
| prod | `workload-prod` | `workload-prod` | 2 | `prod` | `info` | 手動同期を想定 |

## GitHub アプリの差し替え

このリポジトリは、アプリの GitHub repository を OpenShift 上で直接ビルドする構成です。対象 repository は `apps/workload/base/buildconfig.yaml` の `source.git.uri` で指定します。

```yaml
source:
  type: Git
  git:
    uri: https://github.com/yKanaGit/Sample-app01.git
    ref: main
```

別のデモアプリに差し替える場合は、`uri` と `ref` を変更します。Docker strategy を使っているため、対象 repository の root に `Dockerfile` または `Containerfile` が必要です。

BuildConfig は `workload:latest` という ImageStreamTag に出力し、Deployment はその ImageStreamTag を参照します。

```yaml
output:
  to:
    kind: ImageStreamTag
    name: workload:latest
```

## 外部 image を使う場合

OpenShift 上でビルドせず、外部 registry の image を直接使う場合は、`apps/workload/base/deployment.yaml` の image を registry image に変更し、`imagestream.yaml` と `buildconfig.yaml` を `base/kustomization.yaml` から外します。

例:

```yaml
containers:
  - name: workload
    image: quay.io/<org>/<app-image>:<tag>
```

変更を GitHub に push すると、dev は automated sync により反映されます。prod は本番想定のため、Argo CD UI または CLI で手動同期してください。

## private repo の場合

private repo を Argo CD から参照する場合だけ、`bootstrap/repo-creds.example.yaml` をコピーして username と token を編集し、手動で適用します。サンプルには実トークンを含めていません。

```bash
cp bootstrap/repo-creds.example.yaml bootstrap/repo-creds.yaml
vi bootstrap/repo-creds.yaml
oc apply -f bootstrap/repo-creds.yaml
```

`url` は `https://github.com/yKanaGit` にしているため、この owner 配下の repository に対する repo credentials として使えます。

## Tekton-ArgoCD との違い

- `Tekton-ArgoCD` は GitHub Push から Tekton Pipeline を起動し、manifest update の後に Argo CD sync する CI/CD 構成です。
- このリポジトリは Tekton Pipeline / Task / Trigger を含めず、ApplicationSet から Argo CD Application を生成して OpenShift に配備します。
- このリポジトリの目的は、Argo CD / ApplicationSet / Kustomize だけでアプリ配備を何度でも構築しやすくすることです。

## ローカル確認

OpenShift に適用する前に Kustomize の出力を確認できます。

```bash
kustomize build apps/workload/overlays/dev
kustomize build apps/workload/overlays/prod
```
