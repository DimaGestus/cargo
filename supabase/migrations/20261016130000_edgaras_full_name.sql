-- Update only the requested account, preserving all other user metadata.
update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
  || jsonb_build_object('full_name', 'Edgaras Sabaliauskas')
where lower(email) = 'edgaras@gestus.lt';
