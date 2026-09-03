-- Hybrid semantic + lexical discovery across every useful public text field.
-- HNSW supplies fast conceptual candidates while GIN supplies exact title,
-- topic, venue, description/body, place, and address matches. Reciprocal rank
-- fusion avoids relying on incomparable cosine-distance and ts_rank scales.

drop index if exists public.events_search_document_gin;
alter table public.events drop column search_document;
alter table public.events
  add column search_document tsvector generated always as (
    setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(category, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(venue_name, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(description, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(address, '')), 'C')
  ) stored;
create index events_search_document_gin
  on public.events using gin (search_document);

drop index if exists public.forum_posts_search_document_gin;
alter table public.forum_posts drop column search_document;
alter table public.forum_posts
  add column search_document tsvector generated always as (
    setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(category, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(body, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(place_name, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(place_address, '')), 'C')
  ) stored;
create index forum_posts_search_document_gin
  on public.forum_posts using gin (search_document);

create function public.recommend_nearby_events_v2(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision,
  p_query_embedding extensions.vector(384),
  p_query text,
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
  with input as materialized (
    select
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude),
        4326
      )::extensions.geography as origin,
      websearch_to_tsquery(
        'english'::regconfig,
        btrim(left(coalesce(p_query, ''), 240))
      ) as query,
      least(greatest(p_limit * 5, 50), 250) as candidate_limit
  ),
  semantic_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.semantic_distance, ranked.id
      ) as semantic_rank,
      ranked.semantic_distance
    from (
      select
        e.id,
        e.embedding operator(extensions.<=>) p_query_embedding as semantic_distance
      from public.events e
      cross join input
      where auth.uid() is not null
        and p_latitude between -90 and 90
        and p_longitude between -180 and 180
        and e.embedding is not null
        and e.status = 'published'
        and e.visibility = 'public'
        and e.start_at > pg_catalog.now()
        and extensions.st_dwithin(
          e.location,
          input.origin,
          least(greatest(p_radius_km, 1), 100) * 1000
        )
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
            or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
        )
      order by e.embedding operator(extensions.<=>) p_query_embedding
      limit (select candidate_limit from input)
    ) ranked
  ),
  keyword_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.keyword_rank desc, ranked.id
      ) as keyword_position,
      ranked.keyword_rank
    from (
      select
        e.id,
        pg_catalog.ts_rank_cd(e.search_document, input.query, 32) as keyword_rank
      from public.events e
      cross join input
      where auth.uid() is not null
        and p_latitude between -90 and 90
        and p_longitude between -180 and 180
        and e.status = 'published'
        and e.visibility = 'public'
        and e.start_at > pg_catalog.now()
        and e.search_document @@ input.query
        and extensions.st_dwithin(
          e.location,
          input.origin,
          least(greatest(p_radius_km, 1), 100) * 1000
        )
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
            or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
        )
      order by keyword_rank desc, e.id
      limit (select candidate_limit from input)
    ) ranked
  ),
  candidate_ids as materialized (
    select id from semantic_candidates
    union
    select id from keyword_candidates
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
    extensions.st_distance(e.location, input.origin),
    (
      select r.status
      from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
    )
  from candidate_ids candidate
  join public.events e on e.id = candidate.id
  join public.profiles profile on profile.id = e.organizer_id
  cross join input
  left join semantic_candidates semantic on semantic.id = e.id
  left join keyword_candidates keyword on keyword.id = e.id
  order by
    coalesce(1.0 / (60.0 + semantic.semantic_rank), 0.0) +
      coalesce(1.0 / (60.0 + keyword.keyword_position), 0.0) desc,
    coalesce(semantic.semantic_distance, 2.0),
    extensions.st_distance(e.location, input.origin),
    e.start_at,
    e.id
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.recommend_forum_posts_v2(
  p_query_embedding extensions.vector(384),
  p_query text,
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
  with input as materialized (
    select
      websearch_to_tsquery(
        'english'::regconfig,
        btrim(left(coalesce(p_query, ''), 240))
      ) as query,
      least(greatest(p_limit * 5, 50), 250) as candidate_limit
  ),
  semantic_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.semantic_distance, ranked.id
      ) as semantic_rank,
      ranked.semantic_distance
    from (
      select
        p.id,
        p.embedding operator(extensions.<=>) p_query_embedding as semantic_distance
      from public.forum_posts p
      where auth.uid() is not null
        and p.embedding is not null
        and p.status in ('active', 'locked')
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
            or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
        )
      order by p.embedding operator(extensions.<=>) p_query_embedding
      limit (select candidate_limit from input)
    ) ranked
  ),
  keyword_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.keyword_rank desc, ranked.id
      ) as keyword_position,
      ranked.keyword_rank
    from (
      select
        p.id,
        pg_catalog.ts_rank_cd(p.search_document, input.query, 32) as keyword_rank
      from public.forum_posts p
      cross join input
      where auth.uid() is not null
        and p.status in ('active', 'locked')
        and p.search_document @@ input.query
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
            or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
        )
      order by keyword_rank desc, p.id
      limit (select candidate_limit from input)
    ) ranked
  ),
  candidate_ids as materialized (
    select id from semantic_candidates
    union
    select id from keyword_candidates
  )
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
            or (cb.blocked_id = auth.uid() and cb.blocker_id = c.author_id)
        )
    ),
    p.author_id = auth.uid(),
    p.image_key is not null,
    p.place_name,
    p.place_address
  from candidate_ids candidate
  join public.forum_posts p on p.id = candidate.id
  join public.profiles profile on profile.id = p.author_id
  left join semantic_candidates semantic on semantic.id = p.id
  left join keyword_candidates keyword on keyword.id = p.id
  order by
    coalesce(1.0 / (60.0 + semantic.semantic_rank), 0.0) +
      coalesce(1.0 / (60.0 + keyword.keyword_position), 0.0) desc,
    coalesce(semantic.semantic_distance, 2.0),
    p.last_activity_at desc,
    p.id
  limit least(greatest(p_limit, 1), 50);
$$;

revoke all on function public.recommend_nearby_events_v2(
  double precision, double precision, double precision, extensions.vector, text, integer
) from public, anon;
revoke all on function public.recommend_forum_posts_v2(
  extensions.vector, text, integer
) from public, anon;

grant execute on function public.recommend_nearby_events_v2(
  double precision, double precision, double precision, extensions.vector, text, integer
) to authenticated;
grant execute on function public.recommend_forum_posts_v2(
  extensions.vector, text, integer
) to authenticated;

comment on function public.recommend_nearby_events_v2(
  double precision, double precision, double precision, extensions.vector, text, integer
) is 'Hybrid HNSW/GIN nearby event search fused with reciprocal rank fusion.';
comment on function public.recommend_forum_posts_v2(
  extensions.vector, text, integer
) is 'Hybrid HNSW/GIN community search fused with reciprocal rank fusion.';
