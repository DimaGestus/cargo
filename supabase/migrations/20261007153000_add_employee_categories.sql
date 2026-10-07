begin;
alter table public.workspace_members add column if not exists employee_category text not null default 'transport' check (employee_category in ('sales','transport'));
alter table public.workspace_invites add column if not exists employee_category text not null default 'transport' check (employee_category in ('sales','transport'));
create or replace function private.handle_new_invited_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare invite_row record;
begin
 update public.workspace_invites
 set status='accepted',accepted_by=new.id,accepted_at=now()
 where lower(email)=lower(new.email) and status='pending'
 returning workspace_id,role,invited_by,employee_category into invite_row;
 if found then
  insert into public.workspace_members(workspace_id,user_id,role,invited_by,employee_category)
  values(invite_row.workspace_id,new.id,invite_row.role,invite_row.invited_by,invite_row.employee_category)
  on conflict(workspace_id,user_id) do nothing;
 end if;
 return new;
end;
$$;
commit;