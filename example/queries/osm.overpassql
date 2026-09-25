[out:json][timeout:300];
area["ISO3166-2"="US-NM"]->.nm;
(
  nwr["man_made"~"^(petroleum_well|pumping_station|storage_tank|flare|gas_plant|compressor_station)$"](area.nm);
  nwr["industrial"~"^(oil|gas|compressor_station|refinery)$"](area.nm);
);
out center tags;
