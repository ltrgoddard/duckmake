-- great-circle distance in metres
CREATE MACRO metres(lat1, lon1, lat2, lon2) AS
  2 * 6371000 * asin(sqrt(sin(radians(lat2 - lat1) / 2) ^ 2
    + cos(radians(lat1)) * cos(radians(lat2)) * sin(radians(lon2 - lon1) / 2) ^ 2));
