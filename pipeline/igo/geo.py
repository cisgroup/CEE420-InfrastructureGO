"""Coordinates, in one place.

The town's layer is in New Jersey state plane feet on NAD83(2011). A phone reports WGS 84. The two datums differ by
about 0.9 m in Princeton, and a plain reprojection drops that shift without a word, because the default operation
between them is the empty one. The town's own Longitude and Latitude columns do carry the shift. This module takes
the layer's feet to WGS 84 with the standard static operation EPSG:1515, NAD83 to WGS 84 (5), which reproduces the
town's own columns to about a centimetre, and it takes WGS 84 to metres with a projection and nothing else, so that
an inlet and a phone's fix are always compared in the same system.
"""

from functools import lru_cache

import numpy as np
from pyproj import Transformer
from pyproj.crs import CoordinateOperation

from igo import METRIC_CRS, NATIVE_CRS, WGS84

NAD83_2011_GEOGRAPHIC = "EPSG:6318"
DATUM_OPERATION = 1515          # NAD83 to WGS 84 (5), strictly between NAD83 and ITRF96 at 1997.0
ITRF2014_GEOGRAPHIC = "EPSG:9000"


@lru_cache(maxsize=None)
def _unproject():
    return Transformer.from_crs(NATIVE_CRS, NAD83_2011_GEOGRAPHIC, always_xy=True)


@lru_cache(maxsize=None)
def _shift():
    return Transformer.from_pipeline(CoordinateOperation.from_epsg(DATUM_OPERATION).to_proj4())


@lru_cache(maxsize=None)
def _project():
    return Transformer.from_crs(WGS84, METRIC_CRS, always_xy=True)


def datum_operation_name():
    """The name of the datum operation as the EPSG registry spells it, for the provenance of derived files."""
    return f"EPSG:{DATUM_OPERATION} {CoordinateOperation.from_epsg(DATUM_OPERATION).name}"


def nad83_geographic(x_ft, y_ft):
    """Longitude and latitude on NAD83(2011) for positions in the layer's feet, the projection undone and no more."""
    return _unproject().transform(np.asarray(x_ft, dtype=float), np.asarray(y_ft, dtype=float))


def native_to_wgs84(x_ft, y_ft):
    """WGS 84 longitude and latitude for positions in the layer's feet, with the datum shift applied."""
    lon, lat = nad83_geographic(x_ft, y_ft)
    lat_out, lon_out = _shift().transform(lat, lon)          # the registry's operation takes latitude first
    return lon_out, lat_out


def metres(lon, lat):
    """Easting and northing in metres for WGS 84 positions, for inlets and phone fixes alike."""
    return _project().transform(np.asarray(lon, dtype=float), np.asarray(lat, dtype=float))


def lonlat(east, north):
    """WGS 84 longitude and latitude for positions in metres, the way back from `metres`."""
    return _project().transform(np.asarray(east, dtype=float), np.asarray(north, dtype=float), direction="INVERSE")


def offset_m(lon_a, lat_a, lon_b, lat_b):
    """The distance in metres between paired WGS 84 positions that lie close together."""
    ea, na = metres(lon_a, lat_a)
    eb, nb = metres(lon_b, lat_b)
    return np.hypot(ea - eb, na - nb)


def itrf2014(lon_nad83, lat_nad83, epoch):
    """NAD83(2011) positions in ITRF2014 at a decimal year, the frame a satellite fix is in on that day."""
    t = Transformer.from_crs(NAD83_2011_GEOGRAPHIC, ITRF2014_GEOGRAPHIC, always_xy=True)
    lon, lat, _, _ = t.transform(lon_nad83, lat_nad83, np.zeros_like(lon_nad83), np.full_like(lon_nad83, float(epoch)))
    return lon, lat
