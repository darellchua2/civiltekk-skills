"""Resource resolver package (Phase 1 Track B, #23).

Resolves placeholder keys emitted by the agent into concrete, local assets
before rendering. All resolvers are non-fatal and independently pluggable.

Public API::

    from resolvers import resolve_slide_data_list, load_config
"""

from .pipeline import load_config, resolve_slide, resolve_slide_data_list

__all__ = ["resolve_slide_data_list", "resolve_slide", "load_config"]
