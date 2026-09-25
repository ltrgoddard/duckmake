select id
from matches
group by id
having count(*) > 1
