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

.PHONY: build build-push deploy-infra deploy-metrics-server deploy-apps clean grafana-open prometheus-open alertmanager-open

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

# 3. Deploy Observability (metrics-server, Prometheus, Loki, FluentBit, Grafana) via Helm
deploy-infra: deploy-metrics-server
	@echo "Deploying Observability Stack..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo update

	# Namespace: node-exporter and Fluent Bit need host access, so don't enforce baseline
	kubectl create namespace $(OBSERVABILITY_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(OBSERVABILITY_NS) --overwrite \
		pod-security.kubernetes.io/enforce=privileged \
		pod-security.kubernetes.io/warn=restricted \
		pod-security.kubernetes.io/audit=restricted

	# Install Prometheus, Alertmanager, kube-state-metrics and node-exporter
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--version $(KUBE_PROMETHEUS_STACK_VERSION) \
		--namespace $(OBSERVABILITY_NS) \
		-f $(OBSERVABILITY_VALUES)/kube-prometheus-stack-values.yaml

	# Install Loki
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

# 4. Deploy Your Apps (and MySQL)
deploy-apps:
	@echo "Deploying Applications..."
	kubectl apply -f infrastructure/k8s/apps/
	# Force restart to pick up new image builds if tags didn't change
	kubectl rollout restart deployment auth-service frontend

# 5. Master Command
start: build deploy-infra deploy-apps
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

clean:
	@echo "Stopping and deleting Kubernetes resources..."
	kubectl delete -f infrastructure/k8s/apps/ || true
	helm uninstall loki -n $(OBSERVABILITY_NS) || true
	helm uninstall fluent-bit -n $(OBSERVABILITY_NS) || true
	helm uninstall grafana -n $(OBSERVABILITY_NS) || true
	helm uninstall kube-prometheus-stack -n $(OBSERVABILITY_NS) || true
	helm uninstall metrics-server -n kube-system || true
	@echo "Removing Docker images..."
	docker rmi auth-service:latest frontend:latest || true
	@echo "Cleanup complete!"

# 8. Full Prune (Images, Containers, Volumes, Networks)
prune: clean
	@echo "Pruning unused Docker resources..."
	docker system prune -af --volumes
	@echo "All clean!"