-- Enforce owner username changes through one atomic, rate-limited operation.

alter table public.profiles
  add column username_changed_at timestamptz;

create function public.update_own_profile_identity(
  p_display_name text,
  p_username text,
  p_bio text,
  p_city text
)
returns table (
  display_name text,
  username text,
  bio text,
  city text,
  preferred_radius_km double precision,
  approximate_latitude double precision,
  approximate_longitude double precision,
  assistant_enabled boolean,
  avatar_image_key text,
  username_changed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_username text;
  last_username_change timestamptz;
  normalized_display_name text := pg_catalog.btrim(p_display_name);
  normalized_username text := pg_catalog.lower(pg_catalog.btrim(p_username));
  normalized_bio text := pg_catalog.btrim(coalesce(p_bio, ''));
  normalized_city text := nullif(
    pg_catalog.btrim(coalesce(p_city, '')),
    ''
  );
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if normalized_display_name is null
    or pg_catalog.char_length(normalized_display_name) not between 1 and 80
    or normalized_username is null
    or normalized_username !~ '^[a-z0-9_]{3,30}$'
    or pg_catalog.char_length(normalized_bio) > 500
    or (
      normalized_city is not null
      and pg_catalog.char_length(normalized_city) > 120
    ) then
    raise exception using errcode = '22023', message = 'profile_identity_validation';
  end if;

  select p.username, p.username_changed_at
  into current_username, last_username_change
  from public.profiles p
  where p.id = current_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  if normalized_username <> current_username
    and last_username_change is not null
    and pg_catalog.now() < last_username_change + interval '3 months' then
    raise exception using
      errcode = 'P0001',
      message = 'profile_username_cooldown',
      detail = (last_username_change + interval '3 months')::text;
  end if;

  begin
    update public.profiles p
    set
      display_name = normalized_display_name,
      username = normalized_username,
      bio = normalized_bio,
      city = normalized_city,
      username_changed_at = case
        when normalized_username <> current_username then pg_catalog.now()
        else p.username_changed_at
      end
    where p.id = current_user_id;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'profile_username_taken';
  end;

  return query
  select
    p.display_name,
    p.username,
    p.bio,
    p.city,
    p.preferred_radius_km,
    p.approximate_latitude,
    p.approximate_longitude,
    p.assistant_enabled,
    p.avatar_image_key,
    p.username_changed_at,
    p.updated_at
  from public.profiles p
  where p.id = current_user_id;
end;
$$;

-- Authenticated clients may read the cooldown but can only change usernames
-- through the owner-scoped function above.
grant select (username_changed_at) on public.profiles to authenticated;
revoke update (username) on public.profiles from authenticated;

revoke all on function public.update_own_profile_identity(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.update_own_profile_identity(text, text, text, text)
  to authenticated;

comment on column public.profiles.username_changed_at is
  'Timestamp of the latest owner username change; null until the first change.';
comment on function public.update_own_profile_identity(text, text, text, text) is
  'Updates the authenticated owner public identity and limits username changes to once per three calendar months.';
