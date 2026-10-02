"""Provider-agnostic LLM inference service.
This package owns the stable service boundary around large language model
serving backends.
vLLM is the first qualified backend, but backend-specific behavior must remain
behind explicit adapters and configuration rather than leaking into consuming
applications.
"""
