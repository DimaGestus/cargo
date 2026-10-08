begin;
create table if not exists public.removed_team_members (
 workspace_id uuid not null, user_id uuid not null,
 member_data jsonb not null, removed_at timestamptz not null default now(),
 primary key(workspace_id,user_id)
);
alter table public.removed_team_members enable row level security;
revoke all on public.removed_team_members from anon,authenticated;
create or replace function public.admin_team_members(p_workspace_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from public.workspace_members where workspace_id=p_workspace_id and user_id=auth.uid() and role in ('owner','admin')) then raise exception 'Administrator access required'; end if;
 return jsonb_build_object(
 'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'name',coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),split_part(u.email,'@',1)),'role',m.role,'category',m.employee_category) order by u.email) from public.workspace_members m join auth.users u on u.id=m.user_id where m.workspace_id=p_workspace_id),'[]'::jsonb),
 'removed',coalesce((select jsonb_agg(jsonb_build_object('user_id',a.user_id,'email',u.email,'name',coalesce(nullif(u.raw_user_meta_data->>'full_name',''),split_part(u.email,'@',1)),'category',a.member_data->>'employee_category','removed_at',a.removed_at) order by u.email) from public.removed_team_members a join auth.users u on u.id=a.user_id where a.workspace_id=p_workspace_id),'[]'::jsonb),
 'invites',coalesce((select jsonb_agg(jsonb_build_object('email',i.email,'category',i.employee_category) order by i.email) from public.workspace_invites i where i.workspace_id=p_workspace_id and i.status='pending'),'[]'::jsonb)
 );
end; $$;
create or replace function public.admin_manage_colleague(p_workspace_id uuid,p_user_id uuid,p_action text,p_category text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare member_row public.workspace_members; archived jsonb;
begin
 if not exists(select 1 from public.workspace_members where workspace_id=p_workspace_id and user_id=auth.uid() and role in ('owner','admin')) then raise exception 'Administrator access required'; end if;
 if p_user_id=auth.uid() then raise exception 'You cannot change your own access'; end if;
 if p_action='restore' then
  select member_data into archived from public.removed_team_members where workspace_id=p_workspace_id and user_id=p_user_id for update;
  if archived is null then raise exception 'Removed colleague not found'; end if;
  if archived->>'role' in ('owner','admin') then raise exception 'Administrator accounts are protected'; end if;
  insert into public.workspace_members select (jsonb_populate_record(null::public.workspace_members,archived)).*;
  delete from public.removed_team_members where workspace_id=p_workspace_id and user_id=p_user_id;
 else
  select * into member_row from public.workspace_members where workspace_id=p_workspace_id and user_id=p_user_id for update;
  if not found then raise exception 'Colleague not found'; end if;
  if member_row.role in ('owner','admin') then raise exception 'Administrator accounts are protected'; end if;
  if p_action='remove' then
   insert into public.removed_team_members(workspace_id,user_id,member_data) values(p_workspace_id,p_user_id,to_jsonb(member_row))
   on conflict(workspace_id,user_id) do update set member_data=excluded.member_data,removed_at=now();
   delete from public.workspace_members where workspace_id=p_workspace_id and user_id=p_user_id;
  elsif p_action='category' then
   if p_category not in ('sales','transport') or p_category is null then raise exception 'Choose Sales or Transport'; end if;
   update public.workspace_members set employee_category=p_category where workspace_id=p_workspace_id and user_id=p_user_id;
  else raise exception 'Unknown action'; end if;
 end if;
end; $$;
revoke all on function public.admin_team_members(uuid) from public,anon;
revoke all on function public.admin_manage_colleague(uuid,uuid,text,text) from public,anon;
grant execute on function public.admin_team_members(uuid) to authenticated;
grant execute on function public.admin_manage_colleague(uuid,uuid,text,text) to authenticated;
commit;