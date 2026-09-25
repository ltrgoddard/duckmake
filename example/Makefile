export START ?= 2024-01-01

include ../duckmake.mk

data/counties.shp:
	mkdir -p data && curl -sSfo data/counties.zip https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_20m.zip
	cd data && unzip -oq counties.zip && for f in cb_2023_us_county_20m.*; do mv $$f counties.$${f##*.}; done && rm counties.zip
