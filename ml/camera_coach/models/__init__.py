"""Disabled camera-coach model candidates; no runtime provider is enabled."""

from .set_composition_net import (
    CandidateA,
    CandidateB,
    ContractError,
    SETCompositionNetCandidateA,
    SETCompositionNetCandidateB,
    SETCompositionNetInputs,
    SETCompositionNetManifest,
    count_macs,
    count_parameters,
)

__all__ = [
    "CandidateA",
    "CandidateB",
    "ContractError",
    "SETCompositionNetCandidateA",
    "SETCompositionNetCandidateB",
    "SETCompositionNetInputs",
    "SETCompositionNetManifest",
    "count_macs",
    "count_parameters",
]
