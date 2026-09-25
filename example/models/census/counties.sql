SELECT NAME AS county, geom FROM st_read('data/counties.shp') WHERE STATEFP = '35'
