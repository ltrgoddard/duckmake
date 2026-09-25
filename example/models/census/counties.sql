select fips, county, geom
from st_read('data/cb_2023_us_county_20m.shp')
join census.fips on fips = GEOID
