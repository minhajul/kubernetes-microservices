## Kubernetes Microservices Architecture

A cloud-native application stack featuring **Laravel** (Backend), **Next.js** (Frontend), and **Kubernetes**, complete
with a full observability suite (Loki, Grafana, Fluent Bit).

### Project Structure

```text
kubernetes-microservices/
├── Makefile                       # Command Center (Build & Deploy automation)
├── README.md                      # Readme docs
├── apps/                          # Source Code
│   ├── auth-service/              # Laravel API (Authentication & Users)
│   ├── backend-service/           # Laravel API (Business Logic)
│   └── frontend/                  # Next.js (Client Side Rendering)
│
└── infrastructure/                # Infrastructure as Code
    ├── k8s/                       # Kubernetes Manifests
    │   └── apps/                  # Application Deployments (Auth, Frontend, MySQL)
    │
    └── observability/             # Logging Stack Configuration
        ├── loki-values.yaml       # Log Aggregation (configured for local filesystem)
        ├── fluentbit-values.yaml  # Log Collector (DaemonSet)
        └── grafana-values.yaml    # Visualization Dashboard
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

### Observability (Logs)

We use **Fluent Bit** to scrape container logs and send them to **Loki**.

1. Run `make grafana-open`.
2. Copy the password displayed in the terminal.
3. Open [http://localhost:3000](https://www.google.com/search?q=http://localhost:3000) and login.
4. Navigate to **Explore** (Compass Icon) -\> Select **Loki**.
5. Run query: `{job="fluent-bit"}` to see all logs.

### Troubleshooting

**1. "Pending" Pods**

* **Symptom:** Pods stay in yellow "Pending" state forever.
* **Fix:** Docker Desktop -\> Settings -\> Resources. Increase Memory to at least **4GB**.

**2. "ImagePullBackOff"**

* **Symptom:** Kubernetes cannot find `auth-service:latest`.
* **Fix:** Ensure you ran `make build` and that your deployment YAML has `imagePullPolicy: IfNotPresent`.

**3. Helm Errors ("No such file")**

* **Fix:** Ensure you are running `make` from the root `kubernetes-microservices/` directory, not inside a subdirectory.

### Cleanup

* **Stop Apps:** `make clean` (Deletes apps, keeps DB/Logs).
* **Stop Everything:** `make nuke` (Deletes Apps, DB, Logs, and Monitoring stack).
