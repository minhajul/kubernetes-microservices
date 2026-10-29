## Kubernetes Microservices Architecture

A cloud-native application stack featuring **Laravel** (Backend), **Next.js** (Frontend), and **Kubernetes**, complete
with a full observability suite (Prometheus, Alertmanager, Loki on RustFS object storage, Fluent Bit, Grafana).

### Project Structure

```text
kubernetes-microservices/
├── Makefile                       # Command Center (Build & Deploy automation)
├── README.md                      # Readme docs
├── .github/workflows/ci.yml       # CI: tests, lint, image builds (pushed to GHCR from main)
├── apps/                          # Source Code
│   ├── auth-service/              # Laravel API (Authentication & Users)
│   ├── backend-service/           # Laravel API (Business Logic)
│   └── frontend/                  # Next.js (Client Side Rendering)
│
└── infrastructure/                # Infrastructure as Code
    ├── ansible/
    │   └── deploy-system-apps.yml # Same observability install as `make deploy-infra`
    └── k8s/                       # Kubernetes Manifests
        ├── apps/                  # Deployments (Auth, Frontend, MySQL), scaling-*.yaml, security-*.yaml
        ├── optional/vpa/          # Recommendation-only VPA (`make deploy-vpa`)
        ├── vault/                 # Vault and Vault Secrets Operator values, setup.sh

        └── observability/         # Helm values for the monitoring stack
            ├── kube-prometheus-stack-values.yaml # Prometheus, Alertmanager, alert rules
            ├── metrics-server-values.yaml        # `kubectl top` and HPA metrics
            ├── rustfs-values.yaml     # S3-compatible object storage for Loki
            ├── loki-values.yaml       # Log Aggregation (chunks stored in RustFS)
            ├── fluentbit-values.yaml  # Log Collector (DaemonSet)
            └── grafana-values.yaml    # Datasources and dashboards
````

### Prerequisites

Ensure you have the following tools installed globally:

1. **Docker Desktop** (Enable Kubernetes in Settings).
2. **Helm** (Kubernetes Package Manager).
    * *Mac:* `brew install helm`
3. **Make** (Build automation tool).

### Quick Start

We use a `Makefile` to automate the complex sequence of building Docker images, installing Helm charts, and applying
Kubernetes manifests.

#### 1\. Start the Environment

Run this single command to build and deploy everything:

```bash
make start
```

#### 2\. Access the Applications

| Service      | URL / Access Method                             | Description                                              |
|:-------------|:------------------------------------------------|:---------------------------------------------------------|
| **Frontend** | [http://localhost](http://localhost)            | Next.js App (Exposed via LoadBalancer)                   |
| **Auth API** | `kubectl port-forward svc/auth-service 8000:80` | Internal API. Forward port to access at `localhost:8000` |
| **Grafana**  | `make grafana-open`                             | Monitoring Dashboard. (User: `admin`)                    |
| **Prometheus** | `make prometheus-open`                        | Metrics and alert rules at `localhost:9090`              |
| **Alertmanager** | `make alertmanager-open`                    | Firing alerts at `localhost:9093`                        |
| **RustFS**   | `make rustfs-open`                              | Object storage console at `localhost:9001` (prints keys) |
| **Vault**    | `make vault-open`                               | Secrets UI at `localhost:8200` (prints the root token)   |

### Daily Development Workflow

Since the code runs inside containers, you cannot simply "refresh" the browser to see backend changes. Follow these
steps:

#### 1\. Making Code Changes (PHP/JS)

After editing files in `apps/auth-service` or `apps/frontend`:

```bash
# Rebuild images and restart pods
make deploy-apps
```

*Tip: If changes are not reflecting, force a clean build:*

```bash
docker build --no-cache -t auth-service:latest ./apps/auth-service
kubectl rollout restart deployment auth-service
```

#### 2\. Database Migrations

The database runs inside the cluster. To migrate the schema:

```bash
# Execute artisan command inside the running pod
kubectl exec -it deploy/auth-service -- php artisan migrate
```

#### 3\. Creating New Controllers

Generate the file inside the container, then copy it out to your host machine:

```bash
# 1. Generate inside pod
kubectl exec deploy/auth-service -- php artisan make:controller TeamController

# 2. Copy to local project folder
kubectl cp $(kubectl get pods -l app=auth-service -o jsonpath="{.items[0].metadata.name}"):/var/www/app/Http/Controllers/TeamController.php ./apps/auth-service/app/Http/Controllers/TeamController.php
```

#### 4\. Debugging 404 Errors (New Routes)

If you add a route but get a 404, the container is likely using a cached route list.

```bash
kubectl exec deploy/auth-service -- php artisan route:clear
kubectl exec deploy/auth-service -- composer dump-autoload
```

### Observability

`make deploy-infra` installs the stack below with Helm. The Ansible playbook
`infrastructure/ansible/deploy-system-apps.yml` installs the same charts, versions and values. Everything goes into the
`monitoring` namespace, except metrics-server, which goes into `kube-system`. The values files are in
`infrastructure/k8s/observability/`.

| Component                                                                         | Helm chart (version)                       | Purpose                                         |
|:----------------------------------------------------------------------------------|:-------------------------------------------|:------------------------------------------------|
| Prometheus, Alertmanager, Prometheus Operator, kube-state-metrics, node-exporter | `prometheus-community/kube-prometheus-stack` (92.14.1) | Metrics, alert rules, alert routing |
| RustFS                                                                            | `rustfs/rustfs` (1.0.4)                    | S3-compatible object storage for Loki           |
| Loki                                                                              | `grafana/loki` (7.5.0)                     | Log storage (single binary, chunks in RustFS)   |
| Fluent Bit                                                                        | `fluent/fluent-bit` (0.58.3)               | Ships every container's logs to Loki            |
| Grafana                                                                           | `grafana/grafana` (10.5.15)                | Dashboards for Prometheus, Loki, Alertmanager   |
| metrics-server                                                                    | `metrics-server/metrics-server` (3.14.0)   | `kubectl top` and HorizontalPodAutoscalers      |

The stack is sized for a single-node laptop cluster. Prometheus scrapes every 30s and keeps 2 days of data, capped at
1 GB. That data is on an `emptyDir`, so it resets when the Prometheus pod restarts. Prometheus requests 256 MiB of
memory (limit 1 GiB), and the other kube-prometheus-stack pods and metrics-server request 64 MiB or less each. Loki's
memcached caches are disabled, because the chunks cache alone would request about 9.6 GiB.

#### Dashboards

Run `make grafana-open`, which prints the `admin` password, log in at [http://localhost:3000](http://localhost:3000), and
open **Dashboards → Kubernetes**:

* **Cluster Overview**: node CPU, memory and disk usage, node pressure conditions, pod phases, restarts, CPU and memory
  per namespace, and firing alerts.
* **App Pods: CPU and Memory**: CPU and memory per pod and as a fraction of the container's limits, restarts,
  available vs. desired replicas (which follow the HPA), and a requests/limits table. Pick the namespace at the top
  (default: `default`).
* **App Logs: auth-service and frontend**: log volume and error lines per app, and a log panel for each app with a
  regex search box.

The dashboards are inline JSON in `grafana-values.yaml`. To change one, edit it in Grafana, export it as JSON and paste
it back there. Prefer that over `gnetId:` dashboards from grafana.com. The chart downloads those in an init container
that exits on the first failed download, so Grafana itself would not start without internet access.

Container CPU and memory come from the kubelet's `/metrics/resource` endpoint (`metrics_path="/metrics/resource"`).
Some local clusters, such as OrbStack, expose no `container_*` series on `/metrics/cadvisor`.

#### Logs

Open the **App Logs** dashboard, or go to **Explore** → **Loki**. Fluent Bit labels every stream with `namespace`,
`app` (the pod's `app` label), `pod`, `container`, `stream` (stdout/stderr) and `job="fluent-bit"`. Each log line is
the container's own output:

```logql
{namespace="default", app="auth-service"} |= "ERROR"
```

`{job="fluent-bit"}` still returns every log line.

#### Log storage (RustFS)

Loki keeps its chunks and ruler data in [RustFS](https://github.com/rustfs/rustfs), an S3-compatible object store. RustFS
runs as one pod with one 5 GiB PVC (`rustfs-data`) from the official chart in standalone mode. Loki reaches it at
`http://rustfs-svc.monitoring.svc.cluster.local:9000` over plain HTTP with path-style addressing. The web console is
on port 9001: `make rustfs-open` prints the keys and forwards it to `localhost:9001`.

* **Credentials**: both RustFS and Loki read the root keys from the Secret `monitoring/rustfs-credentials`
  (`RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`). `make deploy-infra` and the playbook create it before installing RustFS.
  The first time, they generate random keys. After that, they keep the existing Secret, unless you pass both
  variables, which overwrite it:

  ```bash
  make deploy-infra RUSTFS_ACCESS_KEY=... RUSTFS_SECRET_KEY=...
  ```

  If you change the keys, restart RustFS and Loki so they read the new ones:
  `kubectl rollout restart -n monitoring deploy/rustfs statefulset/loki`. Loki receives the keys as environment
  variables, and `-config.expand-env=true` fills them into its config. So they never appear in a ConfigMap or in
  `helm get values`.
* **Buckets**: Loki doesn't create its buckets. A Helm pre-install/pre-upgrade hook Job in the Loki release
  (`loki-create-buckets`, `extraObjects` in `loki-values.yaml`) creates `loki-chunks` and `loki-ruler` with the AWS
  CLI if they're missing. It runs before Loki's pods are created or updated, and Helm waits for it. RustFS is
  installed with `--wait` just before it.
* **Older filesystem logs**: Loki now has a single schema period on S3. On a cluster that already ran the old
  filesystem-backed Loki, logs from before the switch stay on Loki's PVC but are no longer queried.

`make clean` uninstalls RustFS but keeps the `rustfs-data` PVC (the chart marks it `helm.sh/resource-policy: keep`) and
the credentials Secret, so a later `make deploy-infra` finds the same logs. To start from empty storage:

```bash
kubectl delete -n monitoring pvc/rustfs-data secret/rustfs-credentials
```

#### Alerting

The alert rules are under `additionalPrometheusRulesMap` in `kube-prometheus-stack-values.yaml`. They run alongside
the chart's default rules. Defaults for control-plane components that local clusters don't expose (etcd, scheduler,
controller-manager, kube-proxy) are turned off.

| Alert                           | Fires when                                                                   | Severity |
|:--------------------------------|:-----------------------------------------------------------------------------|:---------|
| `PodCrashLooping`               | A container has been in CrashLoopBackOff for 5 minutes                       | warning  |
| `DeploymentReplicasUnavailable` | A Deployment has had unavailable replicas for 10 minutes                     | warning  |
| `ContainerCPUNearLimit`         | A container has used over 90% of its CPU limit for 15 minutes                | warning  |
| `ContainerMemoryNearLimit`      | A container has used over 90% of its memory limit for 5 minutes              | warning  |
| `NodeDiskPressure`              | A node has reported DiskPressure for 5 minutes                               | critical |
| `LokiDown`, `FluentBitDown`     | Prometheus has been unable to scrape Loki or a Fluent Bit pod for 5 minutes, or the target is gone | critical |

Firing alerts show on the Cluster Overview dashboard, under Grafana's **Alerting → Alert groups** (choose the
Alertmanager datasource), and at `make alertmanager-open`. Alertmanager has only a `null` receiver, so it doesn't send
alerts anywhere.

**Sending alerts to Slack or email.** Keep the webhook URL and the SMTP password in a Secret, not in the values file:

```bash
kubectl create secret generic alertmanager-notifiers -n monitoring \
  --from-literal=slack-webhook-url='https://hooks.slack.com/services/...' \
  --from-literal=smtp-password='...'
```

Then merge this into the `alertmanager:` block of `kube-prometheus-stack-values.yaml` and run `make deploy-infra`.
Alertmanager mounts each listed Secret at `/etc/alertmanager/secrets/<name>/`. Here warnings go to Slack, and critical
alerts go to Slack and email:

```yaml
alertmanager:
  config:
    route:
      receiver: "null"
      routes:
        - receiver: "null"
          matchers:
            - alertname = "Watchdog"
        - receiver: slack
          matchers:
            - severity =~ "warning|critical"
          continue: true
        - receiver: email
          matchers:
            - severity = "critical"
    receivers:
      - name: "null"
      - name: slack
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/alertmanager-notifiers/slack-webhook-url
            channel: "#alerts"
            send_resolved: true
      - name: email
        email_configs:
          - to: oncall@example.com
            from: alertmanager@example.com
            smarthost: smtp.example.com:587
            auth_username: alertmanager@example.com
            auth_password_file: /etc/alertmanager/secrets/alertmanager-notifiers/smtp-password
            send_resolved: true
  alertmanagerSpec:
    secrets:
      - alertmanager-notifiers
```

#### metrics-server

The HPAs and `kubectl top` need the metrics API (`v1beta1.metrics.k8s.io`). Docker Desktop, kind and OrbStack don't
ship it. k3d, Rancher Desktop and minikube's addon do. `make deploy-metrics-server` runs as part of
`make deploy-infra`, and the playbook does the same. It installs metrics-server only if the metrics API is missing or
was installed by this same release, so it never fights a metrics-server the cluster already has.

metrics-server runs with `--kubelet-insecure-tls`, because local kubelets serve their metrics with a self-signed
certificate. Without the flag every scrape fails and `kubectl top` keeps saying `metrics not available yet`. Don't carry
the flag over to a real cluster. There, give kubelets serving certificates signed by the cluster CA
(`serverTLSBootstrap: true`, then approve their CSRs) and drop it. To check it works:

```bash
kubectl top pods
```

#### Monitoring the apps

Prometheus selects ServiceMonitors, PodMonitors and PrometheusRules from every namespace, not only from its own Helm
release. auth-service and frontend don't expose `/metrics` yet. Once they do, add a ServiceMonitor for each app's
Service, and Prometheus picks it up.

#### Upgrading the charts

Chart versions are pinned twice: the `*_VERSION` variables in the `Makefile` and the `*_version` vars in
`deploy-system-apps.yml`. Change both together. Helm installs CRDs but never upgrades them. Before you bump
kube-prometheus-stack across a major version, apply the new prometheus-operator CRDs as its upgrade notes describe.
The `grafana/grafana` chart is frozen at 10.5.15. It is now maintained in
[grafana-community/helm-charts](https://github.com/grafana-community/helm-charts).

The `monitoring` namespace is labelled Pod Security `enforce=privileged` (`warn`/`audit=restricted`), because
node-exporter and Fluent Bit need host access. The warnings `make deploy-infra` prints for them are expected.

### Scaling and Security

Besides the three Deployments, `infrastructure/k8s/apps/` holds:

* `scaling-*.yaml`: HPAs (auth-service 2–4 pods, frontend 1–3, both at 70% CPU), PodDisruptionBudgets, and a
  ResourceQuota and LimitRange for the `default` namespace.
* `security-*.yaml`: NetworkPolicies, Pod Security labels (`enforce=restricted`) and one ServiceAccount per app.

Things to know:

* **The HPAs own the replica count.** The Deployments no longer set `replicas`, so the first `make deploy-apps` over an
  older deploy briefly drops auth-service to 1 pod until its HPA scales it back to 2.
* **The `default` namespace has a quota** (requests 2 CPU / 3Gi, limits 8 CPU / 6Gi, 20 pods). Anything else you deploy
  there counts against it. The LimitRange gives containers that set no `resources` a default.
* **Draining a single-node cluster stalls.** Once one auth-service pod is evicted it has nowhere to go, so the PDB
  blocks the second eviction. Use `kubectl drain --disable-eviction`, or delete the PDB first.
* **NetworkPolicies** deny ingress by default. frontend (3000) and auth-service (8000) accept traffic from anywhere,
  MySQL (3306) only from auth-service, and the `monitoring` namespace may scrape the apps. The app pods can only reach
  DNS, plus auth-service → MySQL. They only take effect if the cluster's network plugin enforces NetworkPolicy. To
  check after `make deploy-apps` (a timeout means enforced, `open` means not):

  ```bash
  kubectl run np-test --rm -i --restart=Never --image=busybox:1.36 --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"np-test","image":"busybox:1.36","command":["nc","-zv","-w","3","mysql","3306"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
  ```

* **Secrets** never live in the manifests. They come from Vault; see "Secrets (Vault)" below.

* **Pod Security** is enforced at `restricted` in `default`, so every pod there must run as non-root with all
  capabilities dropped, no privilege escalation and a seccomp profile. A plain `kubectl run` debug pod is rejected; give
  it a `securityContext` like the command above, or run it in another namespace.

* **VPA (optional):** `make deploy-vpa` installs the VPA recommender and recommendation-only VPAs for the three apps,
  and `make clean-vpa` removes them. See `infrastructure/k8s/optional/vpa/README.md`.

### Secrets (Vault)

The app secrets live in HashiCorp Vault, in the `vault` namespace (Pod Security `restricted`). The Vault Secrets
Operator copies them into the Kubernetes Secrets the Deployments read, and checks Vault for changes every minute.

| Vault path                    | Kubernetes Secret  | Used by                                   |
|:------------------------------|:-------------------|:------------------------------------------|
| `secret/auth-service/app`     | `auth-service-app` | auth-service (`APP_KEY`)                  |
| `secret/mysql/app-user`       | `mysql-app-user`   | MySQL creates it; auth-service logs in as it (`app_db` only) |
| `secret/mysql/root`           | `mysql-root`       | MySQL                                     |

Each app logs in to Vault with its own ServiceAccount, and its Vault policy only lets it read its own paths. For
example, auth-service can't read the MySQL root password.

`make start` runs `make deploy-vault` and `make vault-setup`. On its first run `vault-setup` initializes Vault and saves
its unseal key and root token to `.vault/init.json` (git-ignored). **Keep that file**: without it a sealed Vault can't
be opened. Every run then unseals Vault, applies its auth config and policies, and seeds the three secrets with random
values if they don't exist yet. It never overwrites them.

* **After a cluster or Vault restart** Vault comes back sealed. The apps keep running on their existing Secrets, but
  changes in Vault don't sync until you run `make vault-unseal`.
* **To view or change a secret**, open the UI with `make vault-open` (it prints the root token) at
  [http://localhost:8200](http://localhost:8200). A new `APP_KEY` or `mysql/app-user` value restarts auth-service
  within about a minute. To read the synced value from Kubernetes:

  ```bash
  kubectl get secret mysql-app-user -o jsonpath='{.data.password}' | base64 --decode
  ```

* **MySQL reads its credentials only when it initializes an empty data directory.** After changing a MySQL password in
  Vault, also run `ALTER USER` in MySQL, or start the database from scratch (this deletes its data):

  ```bash
  kubectl delete deployment mysql && kubectl delete pvc mysql-data && make deploy-apps
  ```

* **If `.vault/init.json` is lost**, the only way back is a new Vault. Run `helm uninstall vault -n vault`, then
  `kubectl delete pvc data-vault-0 -n vault`, then `make deploy-vault vault-setup`. The new Vault re-seeds from the
  Kubernetes Secrets that still exist, so the apps keep their values.

This setup is for a local cluster only. It uses one unseal key, keeps the root token in a local file, turns TLS off
inside the cluster, and turns mlock off (Pod Security `restricted` drops the `IPC_LOCK` capability it needs).

### Troubleshooting

**1. "Pending" Pods**

* **Symptom:** Pods stay in the yellow "Pending" state forever.
* **Fix:** Docker Desktop -\> Settings -\> Resources. Increase Memory to at least **4GB**.

**2. "ImagePullBackOff"**

* **Symptom:** Kubernetes cannot find `auth-service:latest`.
* **Fix:** Ensure you ran `make build` and that your deployment YAML has `imagePullPolicy: IfNotPresent`.

**3. Helm Errors ("No such file")**

* **Fix:** Ensure you are running `make` from the root `kubernetes-microservices/` directory, not inside a subdirectory.

### Cleanup

* **Stop Everything:** `make clean` (Deletes the apps and uninstalls the monitoring stack, metrics-server, Vault and the
  Vault Secrets Operator. Also deletes MySQL's `mysql-data` PVC, which wipes the database. Keeps Vault's data PVC
  `data-vault-0` and `.vault/init.json`, so the app secrets survive and a fresh MySQL gets the same credentials. Also
  keeps the RustFS data PVC and its credentials Secret; see "Log storage (RustFS)").
* **Full Prune:** `make prune` (Runs `make clean`, then prunes all unused Docker images, containers, volumes and networks).
