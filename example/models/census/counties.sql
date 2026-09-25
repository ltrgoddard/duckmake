SELECT fips, county, geom FROM st_read('data/counties.shp') JOIN census.fips ON fips = GEOID
