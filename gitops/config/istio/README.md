# Istio

Service mesh and ingress gateway deployed via the [istio](https://istio-release.storage.googleapis.com/charts) Helm chart.

## How It Works

Istio provides traffic management, observability and security for services in the cluster. All external traffic enters through the `istio-ingressgateway` LoadBalancer service.

```
Internet → LoadBalancer → Istio IngressGateway → VirtualService → Service → Pod
```

## No Vault Secret Required

Istio does not require any secrets to operate.

## Exposing an Application

To expose an application externally, create a `Gateway` and `VirtualService` in the application's namespace:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: myapp
  namespace: myapp
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: myapp-tls
      hosts:
        - myapp.example.com
    - port:
        number: 80
        name: http
        protocol: HTTP
      tls:
        httpsRedirect: true
      hosts:
        - myapp.example.com
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: myapp
  namespace: myapp
spec:
  hosts:
    - myapp.example.com
  gateways:
    - myapp
  http:
    - route:
        - destination:
            host: myapp
            port:
              number: 8080
```

The `external-dns.alpha.kubernetes.io/hostname` annotation on the Gateway triggers ExternalDNS to create the DNS record automatically.

For TLS certificate provisioning, see the [cert-manager README](../cert-manager/README.md).

## Using nip.io without a Custom Domain

If you don't have a custom domain, you can use [nip.io](https://nip.io) with the load balancer public IP to get a resolvable hostname for free:

```bash
# Get the load balancer public IP
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[1].ip}'
```

Then use the IP in the Gateway hostname:

```yaml
hosts:
  - myapp.<load-balancer-ip>.nip.io
```

Combine with the `letsencrypt-http01` ClusterIssuer from cert-manager to also get a valid TLS certificate.

## Using nip.io without a Custom Domain

If you don't have a custom domain, you can use [nip.io](https://nip.io) with the load balancer public IP to get a resolvable hostname for free:

```bash
# Get the load balancer public IP
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[1].ip}'
```

Then use the IP in the Gateway hostname:

```yaml
hosts:
  - myapp.<load-balancer-ip>.nip.io
```

Combine with the `letsencrypt-http01` ClusterIssuer from cert-manager to also get a valid TLS certificate.
