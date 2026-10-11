"""InfrastructureGO, the data and model pipeline.

Every step of the pipeline is one module of this package with a Makefile target of the same name. The constants
below are the ones more than one module needs.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = 20261012                                  # the course's seed, used wherever chance enters
LAYER = ROOT / "data" / "town" / "princeton_municipal_2026-09-11.gpkg"
SNAPSHOT = "2026-09-11"                          # the day the town's layers were fetched
ZONES = ROOT / "data" / "zones.geojson"
NATIVE_CRS = "EPSG:6527"                         # NAD83(2011) New Jersey in US survey feet, the layer's own system
METRIC_CRS = "EPSG:32618"                        # WGS 84 UTM zone 18N in metres, used for every distance
WGS84 = "EPSG:4326"
OWNER_TYPES = ("Municipality", "County", "State", "Other Municipality", "Private")
PERSON_PATTERN = r"owner_?name|reporter|e-?mail|phone|inspector|creator|editor|operator|contributor|username"
