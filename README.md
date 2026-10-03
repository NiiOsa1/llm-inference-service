# LLM Inference Service

A production-oriented, provider-agnostic service boundary for serving large language models.

The project separates AI applications from the inference engine that happens to run the model.

## Why This Exists

Applications should not need to know whether an LLM is running through vLLM, another self-hosted inference engine, or a qualified managed provider.

The LLM Inference Service owns that boundary so model serving can evolve without forcing application-domain rewrites.

This separation is especially important for systems requiring reproducible model qualification, observability, security controls, controlled tool use, predictable failure handling, and portable deployment.

## Architecture

    Model Control
         |
         | approved model artifact
         v
    LLM Inference Service
         |
         | provider boundary
         v
        vLLM
         |
         | qualified model API
         v
    AI Applications

The three layers have separate responsibilities.

**Model Control** determines whether a model artifact is permitted to enter the serving environment.

**LLM Inference Service** serves an approved model through a controlled, observable, and reproducible runtime.

**Applications** contain their own business logic, authorization policy, workflows, tools, and user experience.

## Current Backend

The first backend being qualified is:

- vLLM 0.30.0

The version is intentionally pinned to the currently known-good runtime baseline.

Backend upgrades are treated as engineering changes that require compatibility, regression, stability, and performance qualification.

## Provider Independence

vLLM is the first backend. It is not the architecture itself.

    LLM Inference Service
             |
             v
      Provider Interface
             |
             +---- vLLM
             |
             +---- Future self-hosted backend
             |
             +---- Future managed GPU provider

Changing the inference implementation should not require rewriting applications that consume this service.

## Design Principles

- Provider-agnostic service boundary
- Reproducible dependency locking
- Explicit model identity and revision
- Approved-model-only loading
- Private-by-default serving
- Health and readiness checks
- Structured logging
- Metrics and distributed tracing
- Bounded concurrency
- Explicit timeouts
- Backpressure and queue controls
- Deterministic startup and shutdown
- Container-ready deployment
- No application business logic in the inference layer

## Security Boundary

The inference service is not the authority for deciding whether arbitrary model artifacts are trusted.

It consumes models that have passed the appropriate Model Control gate.

The serving process should receive only the permissions needed to:

- read approved model artifacts
- use allocated compute resources
- expose the configured inference endpoint
- emit approved telemetry

It should not receive unrestricted access to application databases, telecom datasets, user files, shell automation, or unrelated infrastructure.

## Repository Safety

This repository is public.

It must never contain:

- model weights
- API keys
- access tokens
- passwords
- private certificates
- signing keys
- proprietary datasets
- telecom or customer data
- private application prompts
- production environment files
- machine-specific secrets

Runtime models, credentials, and deployment secrets are supplied separately through controlled configuration.

## Relationship to Transmission AI

    model-control
         |
         | approves model artifacts
         v
    llm-inference-service
         |
         | controlled LLM inference
         v
    transmission-ai

Transmission AI remains a separate private application and telecom-domain system.

This repository is intentionally reusable outside the telecom domain.

## Development Status

The service is currently establishing its production foundation.

Current qualification work includes:

- reproducible Python and vLLM dependency locking
- qualified vLLM runtime configuration
- model identity and startup validation
- health and readiness behavior
- structured observability
- timeout and cancellation behavior
- queueing and backpressure
- GPU capacity qualification
- context-window qualification
- containerization
- provider abstraction
- security testing
- regression testing

The previously working vLLM environment is retained as a rollback reference while this service is formalized and requalified.

## Non-Goals

This service does not own:

- application business logic
- unrestricted tool execution
- model artifact trust decisions
- conversation persistence
- application authorization policy
- end-user interfaces

Those concerns belong to their respective system boundaries.

## Engineering Philosophy

Reduce feature breadth when necessary, not engineering quality.

The goal is a small service with a permanent architecture that can be hardened, extended, benchmarked, containerized, and deployed without requiring an architectural rewrite.


## Development documentation

- [MSI inference qualification](docs/msi-inference-qualification.md):
  hardware, configuration, benchmark results and known limitations.
- [Developer runbook](docs/msi-development-runbook.md):
  prerequisites, setup, operation and troubleshooting.

The documented profile is validated for local development on the
reference hardware. It is not a production certification.
