# Metrics Server

Kubernetes Metrics Server deployed via the [metrics-server](https://github.com/kubernetes-sigs/metrics-server) Helm chart. It collects resource usage (CPU and memory) from kubelets and exposes them through the Kubernetes Metrics API.

Required for `kubectl top nodes`, `kubectl top pods` and Horizontal Pod Autoscaler (HPA) to work.
