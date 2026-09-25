select
  county,
  count(*) as plumes,
  count(facility_id) as matched,
  round(sum(kg_h)) as kg_h
from matches
group by all
order by plumes desc
