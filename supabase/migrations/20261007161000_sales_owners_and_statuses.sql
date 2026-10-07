begin;
alter table public.transport_requests drop constraint transport_requests_status_check;
alter table public.transport_requests add constraint transport_requests_status_check check(status in ('Waiting for price','Price received','Price sent','Accepted','Declined','No price'));
create or replace function public.list_request_owners(p_workspace_id uuid)
returns table(user_id uuid,display_name text)
language sql stable security definer set search_path = '' as $$
 select m.user_id,coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),split_part(u.email,'@',1),'Team member')
 from public.workspace_members m join auth.users u on u.id=m.user_id
 where m.workspace_id=p_workspace_id
 and exists(select 1 from public.workspace_members caller where caller.workspace_id=p_workspace_id and caller.user_id=auth.uid())
 order by 2;
$$;
revoke all on function public.list_request_owners(uuid) from public,anon;
grant execute on function public.list_request_owners(uuid) to authenticated;
commit;