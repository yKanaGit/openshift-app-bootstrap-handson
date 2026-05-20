# OpenShift App Bootstrap Handson

このリポジトリは、OpenShift GitOps / Argo CD ApplicationSet と Kustomize を使って、通常の OpenShift コンテナアプリをブートストラップ配備するためのハンズオン用リポジトリです。

題材は汎用的な `workload` です。初期状態ではすぐ動作確認できるように public image の `quay.io/openshift/origin-hello-openshift:latest` を配備します。PostgreSQL、Tekton CI/CD、OpenShift AI、GPU Operator、NFD、LLM Serving、VLM Serving、OpenWebUI 関連の manifest は含めていません。

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
  +--> Deployment / Service / Route / ConfigMap
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
oc get pods -n workload-dev
oc get route -n workload-dev
```

Route URL は次のコマンドで確認できます。

```bash
oc get route workload -n workload-dev -o jsonpath='https://{.spec.host}{"\n"}'
```

取得した URL にアクセスすると、初期 image の hello-openshift アプリに到達できます。

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

## image tag の差し替え

dev/prod の image は overlay ごとに変更します。

```yaml
images:
  - name: quay.io/openshift/origin-hello-openshift
    newTag: latest
```

tag だけ変える場合は `newTag` を更新します。image registry も変える場合は、`newName` を追加します。

```yaml
images:
  - name: quay.io/openshift/origin-hello-openshift
    newName: quay.io/example/workload
    newTag: v1.0.0
```

## 実アプリのイメージに差し替える

実アプリの container image が用意できたら、`apps/workload/overlays/dev/kustomization.yaml` と `apps/workload/overlays/prod/kustomization.yaml` の `images` を変更します。

例:

```yaml
images:
  - name: quay.io/openshift/origin-hello-openshift
    newName: quay.io/<org>/<app-image>
    newTag: <tag>
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
