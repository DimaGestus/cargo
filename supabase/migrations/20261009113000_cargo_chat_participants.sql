begin;
create table public.request_chat_participants(
 request_id bigint not null references public.transport_requests(id) on delete cascade,
 peer_id uuid not null references auth.users(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 added_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 primary key(request_id,peer_id,user_id)
);
alter table public.request_chat_participants enable row level security;
alter table public.transport_messages add column chat_peer_id uuid references auth.users(id);
update public.transport_messages m set chat_peer_id=case when m.sender_id=r.created_by then m.recipient_id else m.sender_id end from public.transport_requests r where r.id=m.request_id;
create function public.can_access_cargo_chat(p_request_id bigint,p_workspace_id uuid,p_peer_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.transport_requests r
 join public.workspace_members me on me.workspace_id=r.workspace_id and me.user_id=auth.uid()
 join public.workspace_members peer on peer.workspace_id=r.workspace_id and peer.user_id=p_peer_id
 where r.id=p_request_id and r.workspace_id=p_workspace_id and p_peer_id<>r.created_by
 and (auth.uid() in(r.created_by,p_peer_id) or exists(select 1 from public.request_chat_participants cp where cp.request_id=r.id and cp.peer_id=p_peer_id and cp.user_id=auth.uid())));
$$;
create function public.prepare_cargo_chat_message() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_id uuid;
begin
 select r.created_by into owner_id from public.transport_requests r where r.id=new.request_id and r.workspace_id=new.workspace_id;
 if new.chat_peer_id is null then new.chat_peer_id=case when new.sender_id=owner_id then new.recipient_id else new.sender_id end;end if;
 if new.recipient_id is distinct from (case when new.sender_id=owner_id then new.chat_peer_id else owner_id end) then raise exception 'Invalid chat recipient';end if;
 return new;
end;$$;
create trigger prepare_cargo_chat_message before insert on public.transport_messages for each row execute function public.prepare_cargo_chat_message();
alter policy "Conversation participants can read request messages" on public.transport_messages using(public.can_access_cargo_chat(request_id,workspace_id,chat_peer_id));
alter policy "Workspace members can send direct request messages" on public.transport_messages with check(sender_id=auth.uid() and sender_id<>recipient_id and public.can_access_cargo_chat(request_id,workspace_id,chat_peer_id));
create function public.cargo_chat_people(p_request_id bigint,p_peer_id uuid default null)
returns table(user_id uuid,display_name text,peer_id uuid,is_participant boolean,can_add boolean)
language sql stable security definer set search_path='' as $$
 select m.user_id,coalesce(nullif(u.raw_user_meta_data->>'full_name',''),u.email),coalesce(p_peer_id,m.user_id),
 (m.user_id=r.created_by or m.user_id=p_peer_id or exists(select 1 from public.request_chat_participants cp where cp.request_id=r.id and cp.peer_id=p_peer_id and cp.user_id=m.user_id)),
 (r.created_by=auth.uid() and me.employee_category='sales')
 from public.transport_requests r
 join public.workspace_members me on me.workspace_id=r.workspace_id and me.user_id=auth.uid()
 join public.workspace_members m on m.workspace_id=r.workspace_id
 join auth.users u on u.id=m.user_id
 where r.id=p_request_id and (
 (r.created_by=auth.uid() and (m.employee_category='transport' or m.user_id=r.created_by))
 or (p_peer_id is not null and public.can_access_cargo_chat(r.id,r.workspace_id,p_peer_id) and
 (m.user_id in(r.created_by,p_peer_id) or exists(select 1 from public.request_chat_participants cp where cp.request_id=r.id and cp.peer_id=p_peer_id and cp.user_id=m.user_id)))
 or (p_peer_id is null and (m.user_id=auth.uid() or exists(select 1 from public.request_chat_participants cp where cp.request_id=r.id and cp.peer_id=m.user_id and cp.user_id=auth.uid()))))
 order by 2;
$$;
create function public.add_cargo_chat_participant(p_request_id bigint,p_peer_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.transport_requests r
 join public.workspace_members me on me.workspace_id=r.workspace_id and me.user_id=auth.uid() and me.employee_category='sales'
 join public.workspace_members target on target.workspace_id=r.workspace_id and target.user_id=p_user_id and target.employee_category='transport'
 join public.workspace_members peer on peer.workspace_id=r.workspace_id and peer.user_id=p_peer_id
 where r.id=p_request_id and r.created_by=auth.uid() and p_peer_id<>r.created_by and p_user_id not in(r.created_by,p_peer_id))
 then raise exception 'Only the Sales cargo owner can add Transport colleagues to this chat';end if;
 insert into public.request_chat_participants(request_id,peer_id,user_id,added_by) values(p_request_id,p_peer_id,p_user_id,auth.uid()) on conflict do nothing;
end;$$;
revoke all on function public.can_access_cargo_chat(bigint,uuid,uuid),public.cargo_chat_people(bigint,uuid),public.add_cargo_chat_participant(bigint,uuid,uuid) from public,anon;
grant execute on function public.can_access_cargo_chat(bigint,uuid,uuid),public.cargo_chat_people(bigint,uuid),public.add_cargo_chat_participant(bigint,uuid,uuid) to authenticated;
revoke all on function public.prepare_cargo_chat_message() from public,anon,authenticated;
commit;