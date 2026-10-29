# Variables
OBSERVABILITY_NS := monitoring
OBSERVABILITY_VALUES := infrastructure/k8s/observability
NEXT_PUBLIC_API_URL ?= http://localhost:8000

# Helm chart versions the values files were validated against.
# Keep in sync with the *_version vars in infrastructure/ansible/deploy-system-apps.yml.
KUBE_PROMETHEUS_STACK_VERSION := 92.14.1
LOKI_VERSION := 7.5.0
FLUENT_BIT_VERSION := 0.58.3
GRAFANA_VERSION := 10.5.15
METRICS_SERVER_VERSION := 3.14.0
RUSTFS_VERSION := 1.0.4

# Optional VPA recommender (make deploy-vpa). Not part of deploy-infra or the playbook.
VPA_VERSION := 0.15.0

# Vault and the Vault Secrets Operator (make deploy-vault). Not part of deploy-infra or the playbook.
VAULT_NS := vault
VAULT_VALUES := infrastructure/k8s/vault
VAULT_VERSION := 0.34.1
VAULT_SECRETS_OPERATOR_VERSION := 1.6.2

.PHONY: build build-push deploy-infra deploy-metrics-server deploy-monitoring-namespace deploy-rustfs-secret deploy-vault vault-setup vault-unseal deploy-apps deploy-vpa clean-vpa clean grafana-open prometheus-open alertmanager-open rustfs-open vault-open

# 1. Build Docker Images Locally
build:
	@echo "Building Auth Service..."
	docker build -t auth-service:latest ./apps/auth-service
	@echo "Building Frontend with API URL: $(NEXT_PUBLIC_API_URL)..."
	docker build --build-arg NEXT_PUBLIC_API_URL="$(NEXT_PUBLIC_API_URL)" -t frontend:latest ./apps/frontend

# 2. Build and push to registry (for k8s deployment)
build-push:
	@echo "Building Auth Service..."
	docker build -t auth-service:latest ./apps/auth-service
	@echo "Building Frontend with API URL: $(NEXT_PUBLIC_API_URL)..."
	docker build --build-arg NEXT_PUBLIC_API_URL="$(NEXT_PUBLIC_API_URL)" -t frontend:latest ./apps/frontend
	@echo "Pushing images..."
	docker push auth-service:latest
	docker push frontend:latest

# 3. Deploy Observability (metrics-server, Prometheus, RustFS, Loki, FluentBit, Grafana) via Helm
deploy-infra: deploy-metrics-server deploy-rustfs-secret
	@echo "Deploying Observability Stack..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add rustfs https://charts.rustfs.com
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo update

	# Install Prometheus, Alertmanager, kube-state-metrics and node-exporter
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--version $(KUBE_PROMETHEUS_STACK_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		-f $(OBSERVABILITY_VALUES)/kube-prometheus-stack-values.yaml

	# Install RustFS (Loki's object storage). --wait: Loki's bucket Job needs it up
	helm upgrade --install rustfs rustfs/rustfs \
		--version $(RUSTFS_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		--wait \
		-f $(OBSERVABILITY_VALUES)/rustfs-values.yaml

	# Install Loki (a pre-install hook Job creates its buckets in RustFS first)
	helm upgrade --install loki grafana/loki \
		--version $(LOKI_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		-f $(OBSERVABILITY_VALUES)/loki-values.yaml

	# Install Fluent Bit
	helm upgrade --install fluent-bit fluent/fluent-bit \
		--version $(FLUENT_BIT_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		-f $(OBSERVABILITY_VALUES)/fluentbit-values.yaml

	# Install Grafana
	helm upgrade --install grafana grafana/grafana \
		--version $(GRAFANA_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		-f $(OBSERVABILITY_VALUES)/grafana-values.yaml

# Namespace: node-exporter and Fluent Bit need host access, so don't enforce baseline
deploy-monitoring-namespace:
	kubectl create namespace $(OBSERVABILITY_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(OBSERVABILITY_NS) --overwrite \
		pod-security.kubernetes.io/enforce=privileged \
		pod-security.kubernetes.io/warn=restricted \
		pod-security.kubernetes.io/audit=restricted

# RustFS root credentials, also used by Loki. Pass RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY
# (environment or make variables) to set them. Otherwise an existing Secret is kept, or
# random keys are generated the first time.
deploy-rustfs-secret: deploy-monitoring-namespace
	@if [ -n "$$RUSTFS_ACCESS_KEY$$RUSTFS_SECRET_KEY" ] && { [ -z "$$RUSTFS_ACCESS_KEY" ] || [ -z "$$RUSTFS_SECRET_KEY" ]; }; then \
		echo "Set both RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY, or neither."; exit 1; \
	elif [ -n "$$RUSTFS_ACCESS_KEY" ]; then \
		kubectl create secret generic rustfs-credentials -n $(OBSERVABILITY_NS) \
			--from-literal=RUSTFS_ACCESS_KEY="$$RUSTFS_ACCESS_KEY" \
			--from-literal=RUSTFS_SECRET_KEY="$$RUSTFS_SECRET_KEY" \
			--dry-run=client -o yaml | kubectl apply -f -; \
	elif kubectl get secret rustfs-credentials -n $(OBSERVABILITY_NS) >/dev/null 2>&1; then \
		echo "Keeping the existing rustfs-credentials Secret."; \
	else \
		kubectl create secret generic rustfs-credentials -n $(OBSERVABILITY_NS) \
			--from-literal=RUSTFS_ACCESS_KEY="$$(openssl rand -hex 10)" \
			--from-literal=RUSTFS_SECRET_KEY="$$(openssl rand -hex 20)"; \
	fi

# metrics-server backs `kubectl top` and the HPAs. Some clusters already serve the
# metrics API (k3d, Rancher Desktop, minikube's addon), and a second metrics-server
# would fight over the v1beta1.metrics.k8s.io APIService. So install it only when
# that API is missing or was installed by this same Helm release.
deploy-metrics-server:
	@if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1 && \
		[ "$$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}')" != "metrics-server" ]; then \
		echo "The cluster already serves the metrics API; skipping metrics-server."; \
	else \
		helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ && \
		helm repo update metrics-server && \
		helm upgrade --install metrics-server metrics-server/metrics-server \
			--version $(METRICS_SERVER_VERSION) \
			--namespace kube-system \
			-f $(OBSERVABILITY_VALUES)/metrics-server-values.yaml; \
	fi

# Vault holds the app secrets (Laravel's APP_KEY, the MySQL root password and the app's own
# MySQL user). The Vault Secrets Operator copies them into the Kubernetes Secrets the apps
# read. Both run in the vault namespace, which enforces Pod Security restricted. Vault's
# pod only turns Ready once vault-setup has initialized and unsealed it, so no --wait here.
deploy-vault:
	kubectl create namespace $(VAULT_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(VAULT_NS) --overwrite \
		pod-security.kubernetes.io/enforce=restricted \
		pod-security.kubernetes.io/warn=restricted \
		pod-security.kubernetes.io/audit=restricted
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo update hashicorp
	helm upgrade --install vault hashicorp/vault \
		--version $(VAULT_VERSION) \
		--namespace $(VAULT_NS) \
		-f $(VAULT_VALUES)/vault-values.yaml
	helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
		--version $(VAULT_SECRETS_OPERATOR_VERSION) \
		--namespace $(VAULT_NS) \
		--wait \
		-f $(VAULT_VALUES)/vault-secrets-operator-values.yaml

# Initializes Vault (first run), unseals it, configures its auth and policies, and seeds the
# app secrets once. The unseal key and root token go to .vault/init.json (git-ignored): keep it.
vault-setup:
	$(VAULT_VALUES)/setup.sh

# Vault seals itself whenever its pod restarts, e.g. after the cluster restarts.
vault-unseal:
	$(VAULT_VALUES)/setup.sh unseal

# 4. Deploy Your Apps (and MySQL). Their Secrets come from Vault.
deploy-apps: vault-setup
	@echo "Deploying Applications..."
	kubectl apply -f infrastructure/k8s/apps/
	# Force restart to pick up new image builds if tags didn't change
	kubectl rollout restart deployment auth-service frontend

# Optional: VPA in recommendation-only mode (see infrastructure/k8s/optional/vpa/README.md).
# Only the recommender runs, so VPA never evicts or resizes pods. Its single replica gets
# no PDB, which would otherwise block node drains. Needs metrics-server (make deploy-infra).
deploy-vpa:
	helm repo add autoscaler https://kubernetes.github.io/autoscaler
	helm repo update autoscaler
	helm upgrade --install vpa autoscaler/vertical-pod-autoscaler \
		--version $(VPA_VERSION) \
		--namespace kube-system \
		--set updater.enabled=false \
		--set admissionController.enabled=false \
		--set recommender.replicas=1 \
		--set recommender.podDisruptionBudget.enabled=false \
		--wait
	kubectl apply -f infrastructure/k8s/optional/vpa/

clean-vpa:
	kubectl delete -f infrastructure/k8s/optional/vpa/ --ignore-not-found || true
	helm uninstall vpa -n kube-system || true

# 5. Master Command
start: build deploy-infra deploy-vault deploy-apps
	@echo "Done! Frontend should be available at http://localhost"

# 6. Access Grafana
grafana-open:
	@echo "Getting Grafana Password..."
	@kubectl get secret --namespace $(OBSERVABILITY_NS) grafana -o jsonpath="{.data.admin-password}" | base64 --decode
	@echo "\nOpening Port Forward..."
	kubectl port-forward svc/grafana -n $(OBSERVABILITY_NS) 3000:80

# 7. Access Prometheus and Alertmanager
prometheus-open:
	kubectl port-forward svc/kube-prometheus-stack-prometheus -n $(OBSERVABILITY_NS) 9090:9090

alertmanager-open:
	kubectl port-forward svc/kube-prometheus-stack-alertmanager -n $(OBSERVABILITY_NS) 9093:9093

# RustFS web console at http://localhost:9001
rustfs-open:
	@echo "Access key: $$(kubectl get secret rustfs-credentials -n $(OBSERVABILITY_NS) -o jsonpath='{.data.RUSTFS_ACCESS_KEY}' | base64 --decode)"
	@echo "Secret key: $$(kubectl get secret rustfs-credentials -n $(OBSERVABILITY_NS) -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 --decode)"
	kubectl port-forward svc/rustfs-svc -n $(OBSERVABILITY_NS) 9001:9001

# Vault UI at http://localhost:8200 (sign in with the root token)
vault-open:
	@echo "Root token: $$(sed -n 's/.*"root_token": *"\([^"]*\)".*/\1/p' .vault/init.json)"
	kubectl port-forward svc/vault -n $(VAULT_NS) 8200:8200

clean:
	@echo "Stopping and deleting Kubernetes resources..."
	kubectl delete -f infrastructure/k8s/apps/ || true
	kubectl delete -f infrastructure/k8s/optional/vpa/ --ignore-not-found || true
	helm uninstall vpa -n kube-system || true
	helm uninstall loki -n $(OBSERVABILITY_NS) || true
	helm uninstall fluent-bit -n $(OBSERVABILITY_NS) || true
	helm uninstall grafana -n $(OBSERVABILITY_NS) || true
	helm uninstall kube-prometheus-stack -n $(OBSERVABILITY_NS) || true
	helm uninstall rustfs -n $(OBSERVABILITY_NS) || true
	helm uninstall metrics-server -n kube-system || true
	helm uninstall vault-secrets-operator -n $(VAULT_NS) || true
	helm uninstall vault -n $(VAULT_NS) || true
	@echo "Removing Docker images..."
	docker rmi auth-service:latest frontend:latest || true
	@echo "Cleanup complete!"

# 8. Full Prune (Images, Containers, Volumes, Networks)
prune: clean
	@echo "Pruning unused Docker resources..."
	docker system prune -af --volumes
	@echo "All clean!"