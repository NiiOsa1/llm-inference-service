"""Provider-agnostic LLM inference service.

The package owns the stable service boundary around large language model
serving backends.

vLLM is the first qualified backend, but backend-specific behavior remains
behind explicit adapters and configuration rather than leaking into
applications that consume the service.
"""
