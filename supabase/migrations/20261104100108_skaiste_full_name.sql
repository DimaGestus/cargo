-- Update only the requested account, preserving all other user metadata.
update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
  || jsonb_build_object('full_name', 'Skaiste Pyragaite')
where lower(email) = 'skaiste@gestus.lt';
