# Variables
OBSERVABILITY_NS := monitoring

.PHONY: build deploy-infra deploy-apps clean

# 1. Build Docker Images Locally
build:
	@echo "Building Auth Service..."
	docker build -t auth-service:latest ./apps/auth-service
	@echo "Building Frontend..."
	docker build --build-arg NEXT_PUBLIC_API_URL="http://auth-service:8000" -t frontend:latest ./apps/frontend

# 2. Deploy Observability (Loki, FluentBit, Grafana) via Helm
deploy-infra:
	@echo "Deploying Observability Stack..."
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo update

	# Install Loki
	helm upgrade --install loki grafana/loki \
		--namespace $(OBSERVABILITY_NS) --create-namespace \
		-f infrastructure/k8s/observability/loki-values.yaml

	# Install Fluent Bit
	helm upgrade --install fluent-bit fluent/fluent-bit \
		--namespace $(OBSERVABILITY_NS) \
		-f infrastructure/k8s/observability/fluentbit-values.yaml

	# Install Grafana
	helm upgrade --install grafana grafana/grafana \
		--namespace $(OBSERVABILITY_NS) \
		-f infrastructure/k8s/observability/grafana-values.yaml

# 3. Deploy Your Apps (and MySQL)
deploy-apps:
	@echo "Deploying Applications..."
	kubectl apply -f infrastructure/k8s/apps/
	# Force restart to pick up new image builds if tags didn't change
	kubectl rollout restart deployment auth-service frontend

# 4. Master Command
start: build deploy-infra deploy-apps
	@echo "Done! Frontend should be available at http://localhost"

# 5. Access Grafana
grafana-open:
	@echo "Getting Grafana Password..."
	@kubectl get secret --namespace $(OBSERVABILITY_NS) grafana -o jsonpath="{.data.admin-password}" | base64 --decode
	@echo "\nOpening Port Forward..."
	kubectl port-forward svc/grafana -n $(OBSERVABILITY_NS) 3000:80

clean:
	kubectl delete -f infrastructure/k8s/apps/
	helm uninstall loki -n $(OBSERVABILITY_NS)
	helm uninstall fluent-bit -n $(OBSERVABILITY_NS)
	helm uninstall grafana -n $(OBSERVABILITY_NS)