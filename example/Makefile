export RADIUS ?= 250

DUCKMAKE = main
include .duckmake/$(DUCKMAKE)/duckmake.mk
.duckmake/%/duckmake.mk:
	curl -sSfL --create-dirs -o $@ https://raw.githubusercontent.com/ltrgoddard/duckmake/$*/duckmake.mk

curl = curl -sSf --retry 3 --retry-all-errors --create-dirs -A duckmake-example -o $@

data/cb_2023_us_county_20m.zip:
	$(curl) https://www2.census.gov/geo/tiger/GENZ2023/shp/$(@F)

data/cb_2023_us_county_20m.shp: data/cb_2023_us_county_20m.zip
	unzip -oqDDd data $<

data/plumes.json:
	$(curl) 'https://api.carbonmapper.org/api/v1/catalog/plumes/annotated?limit=10000&bbox=-109.05&bbox=31.33&bbox=-103&bbox=37'

data/osm.json: queries/osm.overpassql
	$(curl) --data-urlencode data@$< https://overpass.kumi.systems/api/interpreter
