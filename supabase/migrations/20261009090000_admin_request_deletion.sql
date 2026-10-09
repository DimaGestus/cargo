begin;
create or replace function public.can_delete_request(p_workspace_id uuid,p_created_by uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(
 select 1 from public.workspace_members m where m.workspace_id=p_workspace_id and m.user_id=auth.uid()
 and (p_created_by=auth.uid() or m.role in ('owner','admin')));
$$;
revoke all on function public.can_delete_request(uuid,uuid) from public,anon;
grant execute on function public.can_delete_request(uuid,uuid) to authenticated;
create or replace function public.set_own_request_deleted(p_request_id bigint,p_deleted boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
 update public.transport_requests r set deleted_at=case when p_deleted then now() else null end
 where r.id=p_request_id and public.can_delete_request(r.workspace_id,r.created_by);
 if not found then raise exception 'Only the request author or workspace administrator can delete or restore this request'; end if;
end; $$;
create or replace function public.guard_request_deletion()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.deleted_at is distinct from old.deleted_at and
 (not public.can_delete_request(old.workspace_id,old.created_by) or not public.can_delete_request(new.workspace_id,new.created_by)) then
 raise exception 'Only the request author or workspace administrator can delete or restore this request';
 end if;
 return new;
end; $$;
commit;