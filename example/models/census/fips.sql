-- county names and codes, read directly from the Census Bureau
select
  STATEFP || COUNTYFP as fips,
  COUNTYNAME as county
from read_csv('https://www2.census.gov/geo/docs/reference/codes2020/national_county2020.txt')
where STATE = 'NM'
