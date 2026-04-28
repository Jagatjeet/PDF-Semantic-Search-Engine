# Issues with Self Hosting

Based on this specific stack (Mistral via Ollama, Qdrant, FastAPI, React), here are the key challenges:

## Inference Performance

Mistral 7B on CPU is extremely slow (you've been hitting timeouts throughout today). Self-hosted requires GPU hardware (Nvidia A10/A100) to be production-viable — hyperscalers abstract this away with pay-per-token pricing.

## Model Lifecycle

You're manually pulling models (`ollama pull mistral`) and handling startup ordering in Docker. Foundry/SageMaker handle model versioning, warm pools, and zero-downtime updates automatically.

## Scaling

Your current setup is single-instance. Horizontal scaling requires you to manage:

- Load balancing across backend replicas
- Shared Qdrant state (Qdrant clustering is complex)
- Stateless embedding workers

Hyperscalers autoscale endpoints with one config change.

## Availability & Ops Burden

No health monitoring, alerting, or automatic restart beyond Docker's restart policy. You need to build/integrate your own observability stack (Prometheus, Grafana, etc.).

## Embedding Model Dependency

`nomic-embed-text` runs locally too. Any change in embedding model requires re-indexing all documents. Managed services version this for you.

## Security

No authentication on your API currently. On a public server you'd need to add auth, TLS termination, secrets management, and network hardening — all handled out of the box on Foundry/SageMaker.

## Hardware Costs at Scale

A GPU instance capable of running Mistral 7B comfortably (~A10G) costs ~$1.50–3/hr. At low query volume, this is often more expensive than per-token pricing on managed APIs.

---

The sweet spot for self-hosting is when you have **high, predictable query volume**, **strict data residency requirements**, or need **offline/air-gapped operation** — otherwise managed platforms win on total cost of ownership.
