-- Group is derived from every route country, never from a manual override.
create or replace function public.cargo_route_group(loading_country text, delivery_country text, loading_stops jsonb, delivery_stops jsonb)
returns text language sql immutable security invoker set search_path = '' as $$
 select case when exists (
  select 1 from (
   select loading_country as country union all select delivery_country
   union all select s->>'country' from pg_catalog.jsonb_array_elements(case when pg_catalog.jsonb_typeof(loading_stops)='array' then loading_stops else '[]'::jsonb end) s
   union all select s->>'country' from pg_catalog.jsonb_array_elements(case when pg_catalog.jsonb_typeof(delivery_stops)='array' then delivery_stops else '[]'::jsonb end) s
  ) countries where upper(btrim(country)) in ('LT','LV','EE','PL')
 ) then 'Export' else 'Europe' end;
$$;
create or replace function public.enforce_cargo_route_group()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 new.transport_group := public.cargo_route_group(new.loading_country,new.delivery_country,new.loading_stops,new.delivery_stops);
 return new;
end;
$$;
-- Run after the existing edit marker so a group-only normalization does not
-- label unchanged freight details as edited.
create trigger zz_enforce_cargo_route_group
before insert or update of loading_country,delivery_country,loading_stops,delivery_stops,transport_group
on public.transport_requests for each row execute function public.enforce_cargo_route_group();
-- Set the existing value to invoke normalization without changing edit markers.
update public.transport_requests set transport_group=transport_group
where transport_group is distinct from public.cargo_route_group(loading_country,delivery_country,loading_stops,delivery_stops);
