alter table public.transport_messages
  add column recipient_id uuid references auth.users(id) on delete cascade;

update public.transport_messages
set recipient_id = sender_id
where recipient_id is null;

alter table public.transport_messages
  alter column recipient_id set not null;

drop policy "Workspace members can read request messages" on public.transport_messages;
drop policy "Workspace members can send request messages" on public.transport_messages;

create policy "Conversation participants can read request messages"
on public.transport_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.transport_requests r
    join public.workspace_members m on m.workspace_id = r.workspace_id
    where r.id = transport_messages.request_id
      and r.workspace_id = transport_messages.workspace_id
      and m.user_id = (select auth.uid())
      and (
        (m.user_id = r.created_by and (transport_messages.sender_id = r.created_by or transport_messages.recipient_id = r.created_by))
        or
        (m.user_id <> r.created_by and (
          (transport_messages.sender_id = m.user_id and transport_messages.recipient_id = r.created_by)
          or (transport_messages.recipient_id = m.user_id and transport_messages.sender_id = r.created_by)
        ))
      )
  )
);

create policy "Workspace members can send direct request messages"
on public.transport_messages
for insert
to authenticated
with check (
  sender_id = (select auth.uid())
  and recipient_id <> sender_id
  and exists (
    select 1
    from public.transport_requests r
    join public.workspace_members sender_member
      on sender_member.workspace_id = r.workspace_id
     and sender_member.user_id = (select auth.uid())
    join public.workspace_members recipient_member
      on recipient_member.workspace_id = r.workspace_id
     and recipient_member.user_id = transport_messages.recipient_id
    where r.id = transport_messages.request_id
      and r.workspace_id = transport_messages.workspace_id
      and (r.created_by = sender_id or r.created_by = recipient_id)
  )
);
