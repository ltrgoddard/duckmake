-- county names and codes, read directly from the Census Bureau
SELECT STATEFP || COUNTYFP AS fips, COUNTYNAME AS county
FROM read_csv('https://www2.census.gov/geo/docs/reference/codes2020/national_county2020.txt')
WHERE STATE = 'NM'
