SELECT fips, county, geom FROM st_read('data/cb_2023_us_county_20m.shp') JOIN census.fips ON fips = GEOID
