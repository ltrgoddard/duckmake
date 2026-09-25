export RADIUS ?= 250

include ../duckmake.mk

data/counties.shp:
	mkdir -p data && curl -sSfo data/counties.zip https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_20m.zip
	cd data && unzip -oq counties.zip && for f in cb_2023_us_county_20m.*; do mv $$f counties.$${f##*.}; done && rm counties.zip

# the api returns 1,000 plumes per page, one JSON object per line
data/plumes.json:
	mkdir -p data && o=0 && while curl -sSf '$(CARBONMAPPER)&offset='$$o > $@.page && grep -q plume_id $@.page; \
	  do cat $@.page && echo && o=$$((o + 1000)); done > $@ && rm $@.page

# public overpass servers are often busy, so try each in turn. a remark means a partial result
data/osm.json: queries/osm.overpassql
	mkdir -p data && for h in overpass.kumi.systems overpass-api.de; do \
	  curl -sSf --retry 2 --retry-all-errors -A duckmake-example --data-urlencode data@$< -o $@ https://$$h/api/interpreter \
	  && ! grep -q '"remark"' $@ && break; rm -f $@; done; test -s $@

CARBONMAPPER = https://api.carbonmapper.org/api/v1/catalog/plumes/annotated?limit=1000&bbox=-109.05&bbox=31.33&bbox=-103.0&bbox=37.0
