drop policy "Workspace members can read request messages" on public.transport_messages;

create policy "Workspace members can read request messages"
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
  )
);
