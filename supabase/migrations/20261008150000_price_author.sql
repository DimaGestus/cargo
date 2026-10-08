begin;
alter table public.transport_requests add column if not exists price_entered_by uuid;
alter table public.transport_requests add column if not exists price_entered_name text;
create or replace function public.track_freight_price_author()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.price_eur is not null and (new.price_eur is distinct from old.price_eur or new.price_entered_by is distinct from old.price_entered_by) then
  if auth.uid() is not null then
   new.price_entered_by := auth.uid();
   select coalesce(nullif(raw_user_meta_data->>'full_name',''),nullif(raw_user_meta_data->>'name',''),split_part(email,'@',1)) into new.price_entered_name from auth.users where id=auth.uid();
  end if;
 else
  new.price_entered_by := old.price_entered_by;
  new.price_entered_name := old.price_entered_name;
 end if;
 return new;
end; $$;
create trigger track_freight_price_author before update on public.transport_requests for each row execute function public.track_freight_price_author();
create or replace function public.mark_freight_request_edited()
returns trigger language plpgsql set search_path = public as $$
begin
 if (to_jsonb(new) - array['edited_at','updated_at','status','price_eur','price_comment','price_entered_by','price_entered_name'])
 is distinct from (to_jsonb(old) - array['edited_at','updated_at','status','price_eur','price_comment','price_entered_by','price_entered_name']) then new.edited_at := now(); else new.edited_at := old.edited_at; end if;
 return new;
end; $$;
commit;