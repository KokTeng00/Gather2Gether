-- Prefer identity-provider names when creating a profile for a social user.
-- Existing profiles are intentionally left unchanged.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  inferred_name text;
begin
  inferred_name := left(
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(trim(split_part(coalesce(new.email, ''), '@', 1)), ''),
      'Member'
    ),
    80
  );

  insert into public.profiles (id, display_name)
  values (new.id, inferred_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Creates an application profile using email or trusted identity-provider display metadata.';
