# k8s-infra — couche plateforme du cluster

Repo **infrastructure / plateforme** du projet *journalintime*. Il ne contient **aucune application** : il regroupe les ressources Kubernetes **transverses au cluster** — le **routage externe** (Ingress) et les **add-ons** (metrics-server) — qui ne doivent pas vivre dans les repos applicatifs.

Les deux applications sont déployées depuis leurs propres dépôts, chacune avec son namespace :

| Brique | Repo | Namespace | Service (port) |
|---|---|---|---|
| Frontend Next.js | `frontend-nextjs-graphql` | `frontend` | `frontend-nextjs-graphql` (3000) |
| Backend GraphQL | `backend-jaxrs-liquibase-graphql-api` | `backend` | `backend-jaxrs-liquibase-graphql-api` (8080) |
| Plateforme (ce repo) | `k8s-infra` | `infra` (+ ingress dans `frontend`/`backend`) | — |

## 🔌 Interactions front ↔ back ↔ infra

```
                 Internet
                    │
        ┌───────────┴───────────┐
   journalintime.eu        api.journalintime.eu
        │                        │
   Ingress (ns frontend)    Ingress (ns backend)     ← définis dans CE repo
        │                        │
  svc frontend-...:3000     svc backend-...:8080
   (ns frontend)             (ns backend)
        │                        │
   pods Next.js             pods Tomcat/JAX-RS ──► PostgreSQL
```

- Le **frontend** est servi sur `journalintime.eu`. Rendu côté client, il appelle le **backend** en GraphQL.
  - En cluster, sa ConfigMap (overlay dev) pointe vers le DNS interne `http://backend-jaxrs-liquibase-graphql-api.backend:8080/api/graphql`.
  - Depuis un navigateur réel, l'appel doit viser l'URL publique `https://api.journalintime.eu/api/graphql` (l'endpoint vu par le client doit être joignable de l'extérieur).
- Le **backend** est exposé sur `api.journalintime.eu`, parle à **PostgreSQL** (BDD managée en prod, ou Postgres in-cluster en local) et signe des **JWT**.
- Ce repo ne fait que **router** vers ces services et fournir les briques cluster communes.

## 📁 Structure

```
k8s/base/
  namespace.yaml          # namespace "infra" (ressources transverses à venir)
  ingress-frontend.yaml   # journalintime.eu     -> svc frontend (ns frontend)
  ingress-backend.yaml    # api.journalintime.eu -> svc backend  (ns backend)
  kustomization.yaml
k8s/overlays/
  dev/   prod/            # surcouches Kustomize (référencent la base)
scripts/
  install-metrics-server.sh   # add-on metrics-server (requis par les HPA des apps)
```

> ⚠️ Un ancien fichier `k8s/base/ingress.yaml` (ingress unique dans le namespace `infra`) traîne encore et n'est **plus** référencé par la kustomization — à supprimer : `git rm k8s/base/ingress.yaml`.

## 🧭 Pourquoi un Ingress par namespace ?

Un objet `Ingress` ne peut router **que** vers des `Service` de **son propre namespace**. Comme les services vivent dans `frontend` et `backend`, il faut **deux** Ingress (un dans chaque namespace) plutôt qu'un seul centralisé.

Cela ne retire rien à l'intérêt de ce repo : un **repo** est une frontière d'organisation Git, pas un namespace. `k8s-infra` centralise donc le *stockage* et le cycle de vie de ces manifests (et des add-ons cluster), même si les objets atterrissent dans des namespaces différents. Pour un vrai routage cross-namespace depuis un point unique, l'évolution « propre » serait la **Gateway API** (`Gateway` + `HTTPRoute` + `ReferenceGrant`).

## ✅ Pré-requis

- Un cluster Kubernetes (prod : **DOKS** / DigitalOcean ; local : **kind**).
- Un **contrôleur d'ingress** (ex. ingress-nginx) installé ; les Ingress ici utilisent `ingressClassName: nginx`.
- Les **namespaces `frontend` et `backend` doivent exister avant** d'appliquer ce repo : ils sont créés par les overlays des apps.

## 🚀 Application (ordre important)

```bash
# 1) Les apps d'abord (créent les namespaces + services ciblés par les ingress)
kubectl apply -k ../backend-jaxrs-liquibase-graphql-api/k8s/overlays/dev
kubectl apply -k ../frontend-nextjs-graphql/k8s/overlays/dev

# 2) Puis la plateforme (ingress + namespace infra)
kubectl apply -k k8s/overlays/dev      # ou .../prod

# 3) Add-on metrics-server (une fois) — requis par les HorizontalPodAutoscaler des apps
./scripts/install-metrics-server.sh
```

Validation locale sans cluster :

```bash
kustomize build k8s/overlays/dev
```

## 🌐 DNS / accès

- **Prod** : faire pointer les enregistrements `journalintime.eu` et `api.journalintime.eu` vers l'IP/LoadBalancer du contrôleur d'ingress.
- **Local (kind)** : ajouter à `/etc/hosts` →
  ```
  127.0.0.1 journalintime.eu api.journalintime.eu
  ```
  Un guide complet de déploiement local (cluster kind, ingress-nginx, Postgres in-cluster, pull GHCR, k9s) est fourni dans le dossier `kind-local/` du workspace.

## 📈 Autoscaling (metrics-server)

Les apps définissent des `HorizontalPodAutoscaler` (CPU). Ils nécessitent **metrics-server** dans le cluster, d'où `scripts/install-metrics-server.sh`. Sur kind, ajouter l'argument `--kubelet-insecure-tls` au déploiement metrics-server. Sans lui, les pods tournent mais l'autoscaling reste inactif.

## 🔁 CI/CD

Ce repo ne build pas d'image (pas d'application). Les images sont publiées sur **GHCR** par les pipelines des repos frontend/backend ; ici on ne gère que des manifests YAML. Une validation `kustomize build` en CI suffit pour attraper les erreurs de rendu.
