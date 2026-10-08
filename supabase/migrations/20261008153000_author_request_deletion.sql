begin;
alter table public.transport_requests add column if not exists deleted_at timestamptz;
create or replace function public.set_own_request_deleted(p_request_id bigint,p_deleted boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
 update public.transport_requests r set deleted_at=case when p_deleted then now() else null end
 where r.id=p_request_id and r.created_by=auth.uid()
 and exists(select 1 from public.workspace_members m where m.workspace_id=r.workspace_id and m.user_id=auth.uid());
 if not found then raise exception 'Only the request author can delete or restore this request'; end if;
end; $$;
revoke all on function public.set_own_request_deleted(bigint,boolean) from public,anon;
grant execute on function public.set_own_request_deleted(bigint,boolean) to authenticated;
commit;