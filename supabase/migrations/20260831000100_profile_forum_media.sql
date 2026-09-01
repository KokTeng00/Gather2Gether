-- Private R2 media references and richer owner profile/forum contracts.
-- Object bytes remain in R2; PostgreSQL stores only validated private object keys.

alter table public.profiles
  add column username text;

update public.profiles p
set username = 'member_' || pg_catalog.substr(
  pg_catalog.replace(p.id::text, '-', ''),
  1,
  23
);

alter table public.profiles
  alter column username set default (
    'member_' || pg_catalog.substr(
      pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''),
      1,
      23
    )
  ),
  alter column username set not null,
  add constraint profiles_username_format check (
    username ~ '^[a-z0-9_]{3,30}$'
  ),
  add constraint profiles_username_key unique (username),
  add column avatar_image_key text,
  add constraint profiles_avatar_image_key check (
    avatar_image_key is null
    or (
      pg_catalog.char_length(avatar_image_key) <= 96
      and avatar_image_key like 'avatars/' || id::text || '/%'
      and avatar_image_key ~ '^avatars/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$'
    )
  );

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  inferred_name text;
  inferred_username text;
  fallback_username text;
begin
  inferred_name := nullif(
    pg_catalog.left(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')),
      80
    ),
    ''
  );

  if inferred_name is null then
    inferred_name := pg_catalog.left(
      coalesce(pg_catalog.split_part(new.email, '@', 1), 'Member'),
      80
    );
  end if;

  inferred_username := pg_catalog.lower(
    pg_catalog.btrim(
      pg_catalog.regexp_replace(
        coalesce(new.raw_user_meta_data ->> 'username', ''),
        '[^a-zA-Z0-9_]+',
        '_',
        'g'
      ),
      '_'
    )
  );
  inferred_username := pg_catalog.left(inferred_username, 30);
  fallback_username := 'member_' || pg_catalog.substr(
    pg_catalog.replace(new.id::text, '-', ''),
    1,
    23
  );

  if inferred_username !~ '^[a-z0-9_]{3,30}$'
    or exists (
      select 1
      from public.profiles p
      where p.username = inferred_username
    ) then
    inferred_username := fallback_username;
  end if;

  begin
    insert into public.profiles (id, display_name, username)
    values (new.id, inferred_name, inferred_username)
    on conflict (id) do nothing;
  exception when unique_violation then
    -- Two simultaneous sign-ups can request the same metadata username after
    -- the existence check. Retry with the UUID-derived collision-free handle.
    if inferred_username = fallback_username then
      raise;
    end if;
    insert into public.profiles (id, display_name, username)
    values (new.id, inferred_name, fallback_username)
    on conflict (id) do nothing;
  end;

  return new;
end;
$$;

alter table public.forum_posts
  add column image_key text,
  add column place_name text,
  add column place_address text,
  add constraint forum_posts_image_key check (
    image_key is null
    or (
      pg_catalog.char_length(image_key) <= 96
      and image_key like 'posts/' || author_id::text || '/%'
      and image_key ~ '^posts/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$'
    )
  ),
  add constraint forum_posts_place_pair check (
    (place_name is null) = (place_address is null)
  ),
  add constraint forum_posts_place_name_length check (
    place_name is null
    or pg_catalog.char_length(place_name) between 2 and 120
  ),
  add constraint forum_posts_place_address_length check (
    place_address is null
    or pg_catalog.char_length(place_address) between 3 and 300
  );

create index forum_posts_author_activity_idx
  on public.forum_posts (author_id, last_activity_at desc, id);

drop function public.create_forum_post(text, text, text);
drop function public.list_forum_posts(integer, timestamptz);
drop function public.get_forum_post(uuid);

create function public.create_forum_post(
  p_title text,
  p_body text,
  p_category text,
  p_image_key text default null,
  p_place_name text default null,
  p_place_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  new_post_id uuid;
  recent_posts integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('forum-post:' || current_user_id::text, 0)
  );

  select pg_catalog.count(*) into recent_posts
  from public.forum_posts p
  where p.author_id = current_user_id
    and p.created_at > pg_catalog.now() - interval '10 minutes';

  if recent_posts >= 3 then
    raise exception using errcode = 'P0001', message = 'forum_rate_limited';
  end if;

  if pg_catalog.char_length(pg_catalog.btrim(p_title)) not between 5 and 120
    or pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 10 and 4000
    or p_category not in (
      'General',
      'Looking for group',
      'Local tips',
      'Event ideas',
      'Safety'
    )
    or (p_place_name is null) <> (p_place_address is null)
    or (
      p_place_name is not null
      and pg_catalog.char_length(pg_catalog.btrim(p_place_name)) not between 2 and 120
    )
    or (
      p_place_address is not null
      and pg_catalog.char_length(pg_catalog.btrim(p_place_address)) not between 3 and 300
    )
    or (
      p_image_key is not null
      and (
        pg_catalog.char_length(p_image_key) > 96
        or p_image_key not like 'posts/' || current_user_id::text || '/%'
        or p_image_key !~ '^posts/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$'
      )
    ) then
    raise exception using errcode = '22023', message = 'forum_validation';
  end if;

  insert into public.forum_posts (
    author_id,
    title,
    body,
    category,
    image_key,
    place_name,
    place_address
  )
  values (
    current_user_id,
    pg_catalog.btrim(p_title),
    pg_catalog.btrim(p_body),
    p_category,
    p_image_key,
    case when p_place_name is null then null else pg_catalog.btrim(p_place_name) end,
    case when p_place_address is null then null else pg_catalog.btrim(p_place_address) end
  )
  returning id into new_post_id;

  return new_post_id;
end;
$$;

create function public.list_forum_posts(
  p_limit integer default 30,
  p_before timestamptz default null
)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_username text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean,
  has_image boolean,
  place_name text,
  place_address text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.author_id,
    profile.display_name,
    profile.username,
    p.category,
    p.title,
    p.body,
    p.status,
    p.created_at,
    p.last_activity_at,
    (
      select pg_catalog.count(*)
      from public.forum_comments c
      where c.post_id = p.id
        and c.status = 'active'
        and not exists (
          select 1
          from public.blocks cb
          where (cb.blocker_id = auth.uid() and cb.blocked_id = c.author_id)
            or (cb.blocker_id = c.author_id and cb.blocked_id = auth.uid())
        )
    ),
    p.author_id = auth.uid(),
    p.image_key is not null,
    p.place_name,
    p.place_address
  from public.forum_posts p
  join public.profiles profile on profile.id = p.author_id
  where auth.uid() is not null
    and p.status in ('active', 'locked')
    and (p_before is null or p.last_activity_at < p_before)
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
        or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
    )
  order by p.last_activity_at desc, p.id
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.get_forum_post(p_post_id uuid)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_username text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean,
  has_image boolean,
  place_name text,
  place_address text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.author_id,
    profile.display_name,
    profile.username,
    p.category,
    p.title,
    p.body,
    p.status,
    p.created_at,
    p.last_activity_at,
    (
      select pg_catalog.count(*)
      from public.forum_comments c
      where c.post_id = p.id
        and c.status = 'active'
        and not exists (
          select 1
          from public.blocks cb
          where (cb.blocker_id = auth.uid() and cb.blocked_id = c.author_id)
            or (cb.blocker_id = c.author_id and cb.blocked_id = auth.uid())
        )
    ),
    p.author_id = auth.uid(),
    p.image_key is not null,
    p.place_name,
    p.place_address
  from public.forum_posts p
  join public.profiles profile on profile.id = p.author_id
  where auth.uid() is not null
    and p.id = p_post_id
    and p.status in ('active', 'locked')
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
        or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
    );
$$;

create function public.list_own_forum_posts(
  p_limit integer default 30,
  p_before timestamptz default null
)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_username text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean,
  has_image boolean,
  place_name text,
  place_address text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.author_id,
    profile.display_name,
    profile.username,
    p.category,
    p.title,
    p.body,
    p.status,
    p.created_at,
    p.last_activity_at,
    (
      select pg_catalog.count(*)
      from public.forum_comments c
      where c.post_id = p.id
        and c.status = 'active'
        and not exists (
          select 1
          from public.blocks cb
          where (cb.blocker_id = auth.uid() and cb.blocked_id = c.author_id)
            or (cb.blocker_id = c.author_id and cb.blocked_id = auth.uid())
        )
    ),
    true,
    p.image_key is not null,
    p.place_name,
    p.place_address
  from public.forum_posts p
  join public.profiles profile on profile.id = p.author_id
  where auth.uid() is not null
    and p.author_id = auth.uid()
    and p.status in ('active', 'locked')
    and (p_before is null or p.last_activity_at < p_before)
  order by p.last_activity_at desc, p.id
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.get_forum_post_image_key(p_post_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  post_author_id uuid;
  post_image_key text;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select p.author_id, p.image_key
  into post_author_id, post_image_key
  from public.forum_posts p
  where p.id = p_post_id
    and p.status in ('active', 'locked');

  if not found then
    raise exception using errcode = 'P0001', message = 'forum_post_unavailable';
  end if;
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = post_author_id)
      or (b.blocker_id = post_author_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  return post_image_key;
end;
$$;

create function public.get_own_profile_stats()
returns table (
  posts_count bigint,
  hosted_count bigint,
  going_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  return query
  select
    (
      select pg_catalog.count(*)
      from public.forum_posts p
      where p.author_id = current_user_id
        and p.status in ('active', 'locked')
    ),
    (
      select pg_catalog.count(*)
      from public.events e
      where e.organizer_id = current_user_id
        and e.status in ('published', 'completed')
    ),
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      join public.events e on e.id = r.event_id
      where r.user_id = current_user_id
        and r.status in ('joined', 'tentative')
        and e.status = 'published'
        and e.start_at > pg_catalog.now()
    );
end;
$$;

create function public.set_profile_avatar(p_image_key text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  old_image_key text;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_image_key is not null and (
    pg_catalog.char_length(p_image_key) > 96
    or p_image_key not like 'avatars/' || current_user_id::text || '/%'
    or p_image_key !~ '^avatars/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$'
  ) then
    raise exception using errcode = '22023', message = 'profile_avatar_validation';
  end if;

  select p.avatar_image_key into old_image_key
  from public.profiles p
  where p.id = current_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  update public.profiles
  set avatar_image_key = p_image_key
  where id = current_user_id;

  return old_image_key;
end;
$$;

create function public.get_own_profile_avatar_image_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  image_key text;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select p.avatar_image_key into image_key
  from public.profiles p
  where p.id = current_user_id;

  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return image_key;
end;
$$;

-- Keep object-key columns writable only through the owner-scoped functions.
revoke select, update on public.profiles from authenticated;
grant select (
  id,
  display_name,
  bio,
  city,
  approximate_latitude,
  approximate_longitude,
  preferred_radius_km,
  created_at,
  updated_at,
  assistant_enabled,
  username,
  avatar_image_key
) on public.profiles to authenticated;
grant update (
  display_name,
  bio,
  city,
  approximate_latitude,
  approximate_longitude,
  preferred_radius_km,
  assistant_enabled,
  username
) on public.profiles to authenticated;

revoke all on function public.create_forum_post(text, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.list_forum_posts(integer, timestamptz)
  from public, anon, authenticated;
revoke all on function public.get_forum_post(uuid)
  from public, anon, authenticated;
revoke all on function public.list_own_forum_posts(integer, timestamptz)
  from public, anon, authenticated;
revoke all on function public.get_forum_post_image_key(uuid)
  from public, anon, authenticated;
revoke all on function public.get_own_profile_stats()
  from public, anon, authenticated;
revoke all on function public.set_profile_avatar(text)
  from public, anon, authenticated;
revoke all on function public.get_own_profile_avatar_image_key()
  from public, anon, authenticated;

grant execute on function public.create_forum_post(text, text, text, text, text, text)
  to authenticated;
grant execute on function public.list_forum_posts(integer, timestamptz)
  to authenticated;
grant execute on function public.get_forum_post(uuid)
  to authenticated;
grant execute on function public.list_own_forum_posts(integer, timestamptz)
  to authenticated;
grant execute on function public.get_forum_post_image_key(uuid)
  to authenticated;
grant execute on function public.get_own_profile_stats()
  to authenticated;
grant execute on function public.set_profile_avatar(text)
  to authenticated;
grant execute on function public.get_own_profile_avatar_image_key()
  to authenticated;

comment on column public.profiles.username is
  'Unique normalized community username. Defaults to a private UUID-derived member handle.';
comment on column public.profiles.avatar_image_key is
  'Private R2 object key. Owner-readable under profile RLS and changed through an owner-scoped RPC.';
comment on column public.forum_posts.image_key is
  'Private R2 object key. Forum list/detail RPCs expose only has_image.';
comment on function public.get_forum_post_image_key(uuid) is
  'Returns a private forum image key only after authentication and mutual-block checks.';
