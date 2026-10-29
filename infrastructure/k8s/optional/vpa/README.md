## Vertical Pod Autoscaler (optional)

`vpa.yaml` adds a VerticalPodAutoscaler for `auth-service`, `frontend` and `mysql`, all with
`updateMode: "Off"`. VPA only recommends requests here and never evicts or resizes a pod,
because the HPAs in `../../apps/scaling-hpa.yaml` already scale auth-service and frontend
on CPU. Use the recommendations to tune the `resources` blocks in `../../apps/*-deployment.yaml`.

These manifests live outside `infrastructure/k8s/apps/`, so `make deploy-apps` keeps working on
clusters without the VPA CRDs.

### 1. Install the VPA recommender

`make deploy-vpa` does steps 1 and 2, and `make clean-vpa` removes both.

VPA needs metrics-server (installed with the observability stack). Recommendation-only mode
needs just the recommender and the CRDs, so turn off the updater and the admission webhook.
The chart's PDB for the single recommender pod would block node drains, so turn that off too:

```bash
helm upgrade --install vpa vertical-pod-autoscaler \
  --repo https://kubernetes.github.io/autoscaler \
  --version 0.15.0 \
  --namespace kube-system \
  --set updater.enabled=false \
  --set admissionController.enabled=false \
  --set recommender.replicas=1 \
  --set recommender.podDisruptionBudget.enabled=false
```

Alternatively, use `hack/vpa-up.sh` from [kubernetes/autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler).
It installs all three components.

### 2. Apply the VPA objects

```bash
kubectl apply -f infrastructure/k8s/optional/vpa/
```

Apply them to the namespace that holds the apps.

### 3. Read the recommendations

The recommender needs a few minutes of metrics before it fills in `status.recommendation`:

```bash
kubectl describe vpa auth-service frontend mysql
```

`Target` is the suggested request. `Lower Bound` and `Upper Bound` show the range it considers safe.

### Remove

```bash
kubectl delete -f infrastructure/k8s/optional/vpa/
helm uninstall vpa --namespace kube-system
```
