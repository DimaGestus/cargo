create policy "Workspace members can send self test messages"
on public.transport_messages for insert to authenticated
with check (
 sender_id = (select auth.uid()) and recipient_id = (select auth.uid())
 and exists (
  select 1 from public.transport_requests r
  join public.workspace_members m on m.workspace_id = r.workspace_id
  where r.id = transport_messages.request_id
    and r.workspace_id = transport_messages.workspace_id
    and m.user_id = (select auth.uid()) and r.created_by = (select auth.uid())
 )
);