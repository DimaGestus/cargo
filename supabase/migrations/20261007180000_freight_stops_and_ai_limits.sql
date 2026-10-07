alter table public.transport_requests
 add column if not exists loading_stops jsonb not null default '[]'::jsonb,
 add column if not exists delivery_stops jsonb not null default '[]'::jsonb,
 add column if not exists transport_group text check(transport_group in ('Europe','Export'));

create table if not exists public.freight_ai_usage(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id),created_at timestamptz not null default now());
alter table public.freight_ai_usage enable row level security;
create index if not exists freight_ai_usage_user_time_idx on public.freight_ai_usage(user_id,created_at);
create or replace function public.claim_freight_ai_analysis(p_user_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
 if (select count(*) from public.freight_ai_usage where user_id=p_user_id and created_at>now()-interval '1 minute')>=3
 or (select count(*) from public.freight_ai_usage where user_id=p_user_id and created_at>now()-interval '24 hours')>=50 then return false; end if;
 insert into public.freight_ai_usage(user_id) values(p_user_id);
 return true;
end;
$$;
revoke all on function public.claim_freight_ai_analysis(uuid) from public,anon,authenticated;
grant execute on function public.claim_freight_ai_analysis(uuid) to service_role;
