alter table public.transport_requests add column if not exists edited_at timestamptz;
create or replace function public.mark_freight_request_edited()
returns trigger language plpgsql set search_path = public as $$
begin
  if (to_jsonb(new) - array['edited_at','updated_at','status','price_eur','price_comment'])
     is distinct from (to_jsonb(old) - array['edited_at','updated_at','status','price_eur','price_comment']) then
    new.edited_at := now();
  else
    new.edited_at := old.edited_at;
  end if;
  return new;
end;
$$;
create trigger mark_freight_request_edited before update on public.transport_requests
for each row execute function public.mark_freight_request_edited();