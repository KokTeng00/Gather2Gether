-- Semantic discovery and public social connections.
-- gte-small produces 384-dimensional embeddings. Cosine distance is used by
-- both recommendation RPCs, so the HNSW operator classes must match it.

create extension if not exists vector with schema extensions;

alter table public.events
  add column embedding extensions.vector(384);

alter table public.forum_posts
  add column embedding extensions.vector(384),
  add column search_document tsvector generated always as (
    setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(category, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(body, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(place_name, '')), 'C')
  ) stored;

create index events_embedding_hnsw
  on public.events using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

create index forum_posts_embedding_hnsw
  on public.forum_posts using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

create index forum_posts_search_document_gin
  on public.forum_posts using gin (search_document);

create table public.profile_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (follower_id, followed_id),
  constraint profile_follows_not_self check (follower_id <> followed_id)
);

create index profile_follows_followed_idx
  on public.profile_follows (followed_id, created_at desc, follower_id);

create index profile_follows_follower_idx
  on public.profile_follows (follower_id, created_at desc, followed_id);

alter table public.profile_follows enable row level security;

create policy profile_follows_read_authenticated
on public.profile_follows for select to authenticated
using (
  auth.uid() is not null
  and not exists (
    select 1
    from public.blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id in (follower_id, followed_id))
       or (b.blocked_id = auth.uid() and b.blocker_id in (follower_id, followed_id))
  )
);

create policy profile_follows_create_own
on public.profile_follows for insert to authenticated
with check (
  follower_id = auth.uid()
  and followed_id <> auth.uid()
  and not exists (
    select 1
    from public.blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = followed_id)
       or (b.blocker_id = followed_id and b.blocked_id = auth.uid())
  )
);

create policy profile_follows_delete_own
on public.profile_follows for delete to authenticated
using (follower_id = auth.uid());

revoke all on public.profile_follows from public, anon, authenticated;

create function public.set_event_embedding(
  p_event_id uuid,
  p_embedding extensions.vector(384)
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  update public.events e
  set embedding = p_embedding
  where e.id = p_event_id
    and e.organizer_id = current_user_id;

  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return true;
end;
$$;

create function public.set_forum_post_embedding(
  p_post_id uuid,
  p_embedding extensions.vector(384)
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  update public.forum_posts p
  set embedding = p_embedding
  where p.id = p_post_id
    and p.author_id = current_user_id;

  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return true;
end;
$$;

create function public.recommend_nearby_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision,
  p_query_embedding extensions.vector(384),
  p_limit integer default 30
)
returns table (
  id uuid,
  organizer_id uuid,
  organizer_name text,
  title text,
  description text,
  category text,
  venue_name text,
  address text,
  latitude double precision,
  longitude double precision,
  start_at timestamptz,
  end_at timestamptz,
  max_participants integer,
  joined_count bigint,
  tentative_count bigint,
  distance_meters double precision,
  user_rsvp_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with origin as (
    select extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography as point
  )
  select
    e.id,
    e.organizer_id,
    profile.display_name,
    e.title,
    e.description,
    e.category,
    e.venue_name,
    e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at,
    e.end_at,
    e.max_participants,
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'joined'
    ),
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'tentative'
    ),
    extensions.st_distance(e.location, origin.point),
    (
      select r.status
      from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
    )
  from public.events e
  join public.profiles profile on profile.id = e.organizer_id
  cross join origin
  where auth.uid() is not null
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and e.embedding is not null
    and e.status = 'published'
    and e.visibility = 'public'
    and e.start_at > pg_catalog.now()
    and extensions.st_dwithin(
      e.location,
      origin.point,
      least(greatest(p_radius_km, 1), 100) * 1000
    )
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
        or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
    )
  order by
    e.embedding operator(extensions.<=>) p_query_embedding,
    e.location operator(extensions.<->) origin.point,
    e.start_at
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.recommend_forum_posts(
  p_query_embedding extensions.vector(384),
  p_limit integer default 30
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
    and p.embedding is not null
    and p.status in ('active', 'locked')
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
        or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
    )
  order by
    p.embedding operator(extensions.<=>) p_query_embedding,
    p.last_activity_at desc,
    p.id
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.set_profile_follow(
  p_profile_id uuid,
  p_following boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_profile_id = current_user_id then
    raise exception using errcode = '22023', message = 'cannot_follow_self';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  if p_following then
    insert into public.profile_follows (follower_id, followed_id)
    values (current_user_id, p_profile_id)
    on conflict do nothing;
  else
    delete from public.profile_follows f
    where f.follower_id = current_user_id
      and f.followed_id = p_profile_id;
  end if;
  return p_following;
end;
$$;

create function public.get_public_profile(p_profile_id uuid)
returns table (
  id uuid,
  display_name text,
  username text,
  bio text,
  city text,
  has_avatar boolean,
  avatar_version timestamptz,
  followers_count bigint,
  following_count bigint,
  viewer_is_following boolean,
  viewer_is_self boolean
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
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.username,
    p.bio,
    p.city,
    p.avatar_image_key is not null,
    p.updated_at,
    (select pg_catalog.count(*) from public.profile_follows f where f.followed_id = p.id),
    (select pg_catalog.count(*) from public.profile_follows f where f.follower_id = p.id),
    exists (
      select 1
      from public.profile_follows f
      where f.follower_id = current_user_id and f.followed_id = p.id
    ),
    p.id = current_user_id
  from public.profiles p
  where p.id = p_profile_id;
end;
$$;

create function public.get_public_profile_avatar_image_key(p_profile_id uuid)
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
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  select p.avatar_image_key into image_key
  from public.profiles p
  where p.id = p_profile_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;
  return image_key;
end;
$$;

drop function public.get_own_profile_stats();

create function public.get_own_profile_stats()
returns table (
  posts_count bigint,
  hosted_count bigint,
  going_count bigint,
  followers_count bigint,
  following_count bigint
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
    ),
    (
      select pg_catalog.count(*)
      from public.profile_follows f
      where f.followed_id = current_user_id
    ),
    (
      select pg_catalog.count(*)
      from public.profile_follows f
      where f.follower_id = current_user_id
    );
end;
$$;

revoke all on function public.set_event_embedding(uuid, extensions.vector) from public, anon;
revoke all on function public.set_forum_post_embedding(uuid, extensions.vector) from public, anon;
revoke all on function public.recommend_nearby_events(
  double precision, double precision, double precision, extensions.vector, integer
) from public, anon;
revoke all on function public.recommend_forum_posts(extensions.vector, integer) from public, anon;
revoke all on function public.set_profile_follow(uuid, boolean) from public, anon;
revoke all on function public.get_public_profile(uuid) from public, anon;
revoke all on function public.get_public_profile_avatar_image_key(uuid) from public, anon;
revoke all on function public.get_own_profile_stats() from public, anon;

grant execute on function public.set_event_embedding(uuid, extensions.vector) to authenticated;
grant execute on function public.set_forum_post_embedding(uuid, extensions.vector) to authenticated;
grant execute on function public.recommend_nearby_events(
  double precision, double precision, double precision, extensions.vector, integer
) to authenticated;
grant execute on function public.recommend_forum_posts(extensions.vector, integer) to authenticated;
grant execute on function public.set_profile_follow(uuid, boolean) to authenticated;
grant execute on function public.get_public_profile(uuid) to authenticated;
grant execute on function public.get_public_profile_avatar_image_key(uuid) to authenticated;
grant execute on function public.get_own_profile_stats() to authenticated;

comment on column public.events.embedding is
  'gte-small 384-dimensional embedding for cosine semantic discovery.';
comment on column public.forum_posts.embedding is
  'gte-small 384-dimensional embedding for cosine semantic discovery.';
comment on table public.profile_follows is
  'Public follow graph. Mutations use authenticated RPCs and respect blocks.';
