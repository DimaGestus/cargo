begin;

-- Check both participants without workspace_members' own-row SELECT policy
-- hiding the recipient. auth.uid() must be one of the participants.
create or replace function public.can_access_request_conversation(
  p_request_id bigint, p_workspace_id uuid, p_sender_id uuid, p_recipient_id uuid
) returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null
    and auth.uid() in (p_sender_id, p_recipient_id)
    and exists (
      select 1 from public.transport_requests r
      join public.workspace_members s
        on s.workspace_id = r.workspace_id and s.user_id = p_sender_id
      join public.workspace_members t
        on t.workspace_id = r.workspace_id and t.user_id = p_recipient_id
      where r.id = p_request_id and r.workspace_id = p_workspace_id
        and r.created_by in (p_sender_id, p_recipient_id)
    );
$$;
revoke all on function public.can_access_request_conversation(bigint,uuid,uuid,uuid) from public, anon;
grant execute on function public.can_access_request_conversation(bigint,uuid,uuid,uuid) to authenticated;

alter policy "Workspace members can send direct request messages"
on public.transport_messages
with check (
  sender_id = (select auth.uid()) and recipient_id <> sender_id
  and public.can_access_request_conversation(request_id,workspace_id,sender_id,recipient_id)
);

alter policy "Conversation participants can read request messages"
on public.transport_messages
using (
  public.can_access_request_conversation(request_id,workspace_id,sender_id,recipient_id)
);

commit;
