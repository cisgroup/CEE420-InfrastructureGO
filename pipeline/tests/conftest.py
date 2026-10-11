"""What several test files share. The pinned layer is read and derived once per session."""

import pytest

from igo import inlets, zones


@pytest.fixture(scope="session")
def layers():
    """The raw inlet layer, the boundary and the provenance, as read from the pinned file."""
    return inlets.read_layers()


@pytest.fixture(scope="session")
def play_zones():
    return zones.read_zones()


@pytest.fixture(scope="session")
def derived(layers, play_zones):
    raw, boundary, provenance = layers
    return inlets.derive(raw, boundary, play_zones, provenance)
