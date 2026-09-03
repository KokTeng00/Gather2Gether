-- High-accuracy recommendations use a bounded two-stage pipeline:
-- 1. PostgreSQL retrieves candidates with collaborative-style affinities,
--    freshness, popularity, distance, and an embedding taste centroid.
-- 2. The API may rerank the first 24 candidates with a cross-encoder.
--
-- Only an anonymous preference summary and public candidate content leave the
-- database. The short cache keeps model usage bounded and provides a stable UI.

create table public.ai_recommendation_cache (
  user_id uuid not null references public.profiles(id) on delete cascade,
  surface text not null check (surface in ('event', 'forum_post')),
  cache_key text not null check (cache_key ~ '^[0-9a-f]{32}$'),
  ranked_ids uuid[] not null check (
    pg_catalog.cardinality(ranked_ids) between 2 and 24
  ),
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, surface)
);

create index ai_recommendation_cache_expiry_idx
  on public.ai_recommendation_cache (expires_at);

alter table public.ai_recommendation_cache enable row level security;
revoke all on public.ai_recommendation_cache from public, anon, authenticated;

create or replace function public.recommend_personalized_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 10
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
    select extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography as origin
  ),
  weighted_signals as materialized (
    select
      s.content_id,
      s.signal_type,
      (
        case s.signal_type
          when 'joined' then 8.0
          when 'tentative' then 4.0
          else 1.0
        end
        * least(s.occurrence_count, case when s.signal_type = 'view' then 3 else 1 end)
        * pg_catalog.exp(
          -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
            / 2592000.0
        )
      ) as weight,
      case s.signal_type
        when 'joined' then 4
        when 'tentative' then 2
        else 1
      end as semantic_samples
    from public.recommendation_signals s
    where s.user_id = auth.uid()
      and s.content_kind = 'event'
      and s.last_occurred_at > pg_catalog.now() - interval '90 days'
  ),
  category_preferences as materialized (
    select e.category, sum(s.weight) as affinity
    from weighted_signals s
    join public.events e on e.id = s.content_id
    group by e.category
  ),
  organizer_preferences as materialized (
    select e.organizer_id, sum(s.weight) as affinity
    from weighted_signals s
    join public.events e on e.id = s.content_id
    group by e.organizer_id
  ),
  semantic_history as materialized (
    select e.embedding, s.semantic_samples
    from weighted_signals s
    join public.events e on e.id = s.content_id
    where e.embedding is not null
    order by s.weight desc
    limit 16
  ),
  taste as materialized (
    select extensions.avg(h.embedding) as embedding
    from semantic_history h
    cross join lateral pg_catalog.generate_series(1, h.semantic_samples)
  ),
  candidates as materialized (
    select
      e.id,
      e.organizer_id,
      profile.display_name as organizer_name,
      e.title,
      e.description,
      e.category,
      e.venue_name,
      e.address,
      e.embedding,
      extensions.st_y(e.location::extensions.geometry) as latitude,
      extensions.st_x(e.location::extensions.geometry) as longitude,
      e.start_at,
      e.end_at,
      e.max_participants,
      (
        select pg_catalog.count(*)
        from public.event_rsvps r
        where r.event_id = e.id and r.status = 'joined'
      ) as joined_count,
      (
        select pg_catalog.count(*)
        from public.event_rsvps r
        where r.event_id = e.id and r.status = 'tentative'
      ) as tentative_count,
      extensions.st_distance(e.location, input.origin) as distance_meters,
      (
        select r.status
        from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
      ) as user_rsvp_status
    from public.events e
    join public.profiles profile on profile.id = e.organizer_id
    cross join input
    where auth.uid() is not null
      and p_latitude between -90 and 90
      and p_longitude between -180 and 180
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
    order by e.location operator(extensions.<->) input.origin, e.start_at
    limit 500
  )
  select
    c.id,
    c.organizer_id,
    c.organizer_name,
    c.title,
    c.description,
    c.category,
    c.venue_name,
    c.address,
    c.latitude,
    c.longitude,
    c.start_at,
    c.end_at,
    c.max_participants,
    c.joined_count,
    c.tentative_count,
    c.distance_meters,
    c.user_rsvp_status
  from candidates c
  cross join taste
  left join category_preferences category on category.category = c.category
  left join organizer_preferences organizer on organizer.organizer_id = c.organizer_id
  order by
    coalesce(category.affinity, 0.0) * 2.5
      + coalesce(organizer.affinity, 0.0) * 0.6
      + case
          when c.embedding is null or taste.embedding is null then 0.0
          else greatest(
            0.0::double precision,
            1.0 - (c.embedding operator(extensions.<=>) taste.embedding)
          ) * 4.0
        end
      + pg_catalog.ln(1.0 + c.joined_count::double precision) * 0.4
      + 1.0 / (1.0 + c.distance_meters / 10000.0)
      + 1.0 / (
        1.0 + greatest(
          extract(epoch from (c.start_at - pg_catalog.now())) / 1209600.0,
          0.0
        )
      )
      - case c.user_rsvp_status
          when 'joined' then 8.0
          when 'tentative' then 3.0
          else 0.0
        end desc,
    c.distance_meters,
    c.start_at,
    c.id
  limit 100;
$$;

create or replace function public.recommend_personalized_forum_posts(
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
  with weighted_signals as materialized (
    select
      s.content_id,
      s.signal_type,
      (
        case s.signal_type
          when 'comment' then 7.0
          when 'like' then 4.0
          else 1.0
        end
        * least(
          s.occurrence_count,
          case
            when s.signal_type = 'view' then 3
            when s.signal_type = 'comment' then 5
            else 1
          end
        )
        * pg_catalog.exp(
          -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
            / 2592000.0
        )
      ) as weight,
      case s.signal_type
        when 'comment' then 4
        when 'like' then 2
        else 1
      end as semantic_samples
    from public.recommendation_signals s
    where s.user_id = auth.uid()
      and s.content_kind = 'forum_post'
      and s.last_occurred_at > pg_catalog.now() - interval '90 days'
  ),
  category_preferences as materialized (
    select p.category, sum(s.weight) as affinity
    from weighted_signals s
    join public.forum_posts p on p.id = s.content_id
    group by p.category
  ),
  author_preferences as materialized (
    select p.author_id, sum(s.weight) as affinity
    from weighted_signals s
    join public.forum_posts p on p.id = s.content_id
    group by p.author_id
  ),
  semantic_history as materialized (
    select p.embedding, s.semantic_samples
    from weighted_signals s
    join public.forum_posts p on p.id = s.content_id
    where p.embedding is not null
    order by s.weight desc
    limit 16
  ),
  taste as materialized (
    select extensions.avg(h.embedding) as embedding
    from semantic_history h
    cross join lateral pg_catalog.generate_series(1, h.semantic_samples)
  ),
  candidates as materialized (
    select
      p.id,
      p.author_id,
      profile.display_name as author_name,
      profile.username as author_username,
      p.category,
      p.title,
      p.body,
      p.embedding,
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
      ) as comment_count,
      (
        select pg_catalog.count(*)
        from public.forum_post_likes l
        where l.post_id = p.id
      ) as like_count,
      p.author_id = auth.uid() as viewer_is_author,
      p.image_key is not null as has_image,
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
    limit 500
  )
  select
    c.id,
    c.author_id,
    c.author_name,
    c.author_username,
    c.category,
    c.title,
    c.body,
    c.status,
    c.created_at,
    c.last_activity_at,
    c.comment_count,
    c.viewer_is_author,
    c.has_image,
    c.place_name,
    c.place_address
  from candidates c
  cross join taste
  left join category_preferences category on category.category = c.category
  left join author_preferences author on author.author_id = c.author_id
  order by
    coalesce(category.affinity, 0.0) * 2.0
      + coalesce(author.affinity, 0.0) * 0.5
      + case
          when c.embedding is null or taste.embedding is null then 0.0
          else greatest(
            0.0::double precision,
            1.0 - (c.embedding operator(extensions.<=>) taste.embedding)
          ) * 3.5
        end
      + pg_catalog.ln(1.0 + c.like_count::double precision) * 0.8
      + pg_catalog.ln(1.0 + c.comment_count::double precision) * 0.45
      + 1.0 / (
        1.0 + greatest(
          extract(epoch from (pg_catalog.now() - c.last_activity_at))
            / 1209600.0,
          0.0
        )
      )
      - case when c.viewer_is_author then 1.5 else 0.0 end desc,
    c.last_activity_at desc,
    c.id
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.get_ai_recommendation_state(
  p_surface text,
  p_candidate_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  candidate_count integer;
  distinct_candidate_count integer;
  distinct_history_count integer := 0;
  latest_signal timestamptz;
  preference_query text;
  computed_cache_key text;
  cached_ranked_ids uuid[];
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_surface is null or p_surface not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'invalid_recommendation_surface';
  end if;

  candidate_count := pg_catalog.cardinality(p_candidate_ids);
  select pg_catalog.count(distinct candidate_id)::integer
  into distinct_candidate_count
  from pg_catalog.unnest(p_candidate_ids) candidate_id;
  if p_candidate_ids is null
      or candidate_count not between 2 and 24
      or distinct_candidate_count <> candidate_count then
    raise exception using errcode = '22023', message = 'invalid_recommendation_candidates';
  end if;

  select
    pg_catalog.count(distinct s.content_id)::integer,
    max(s.last_occurred_at)
  into distinct_history_count, latest_signal
  from public.recommendation_signals s
  where s.user_id = current_user_id
    and s.content_kind = p_surface
    and s.last_occurred_at > pg_catalog.now() - interval '90 days';

  if distinct_history_count < 2 then
    return pg_catalog.jsonb_build_object(
      'eligible', false,
      'preference_query', null,
      'cache_key', null,
      'ranked_ids', null
    );
  end if;

  if p_surface = 'event' then
    select pg_catalog.string_agg(history.summary, E'\n' order by history.weight desc)
    into preference_query
    from (
      select
        (
          case s.signal_type
            when 'joined' then 8.0
            when 'tentative' then 4.0
            else 1.0
          end
          * pg_catalog.exp(
            -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
              / 2592000.0
          )
        ) as weight,
        pg_catalog.concat(
          'Action: ', s.signal_type,
          ' | Category: ', e.category,
          ' | Event: ', e.title,
          ' | Description: ', pg_catalog.left(e.description, 240)
        ) as summary
      from public.recommendation_signals s
      join public.events e on e.id = s.content_id
      where s.user_id = current_user_id
        and s.content_kind = 'event'
        and s.last_occurred_at > pg_catalog.now() - interval '90 days'
        and e.status = 'published'
        and e.visibility = 'public'
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = current_user_id and b.blocked_id = e.organizer_id)
            or (b.blocker_id = e.organizer_id and b.blocked_id = current_user_id)
        )
      order by weight desc
      limit 16
    ) history;
  else
    select pg_catalog.string_agg(history.summary, E'\n' order by history.weight desc)
    into preference_query
    from (
      select
        (
          case s.signal_type
            when 'comment' then 7.0
            when 'like' then 4.0
            else 1.0
          end
          * pg_catalog.exp(
            -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
              / 2592000.0
          )
        ) as weight,
        pg_catalog.concat(
          'Action: ', s.signal_type,
          ' | Topic: ', p.category,
          ' | Discussion: ', p.title,
          ' | Public post: ', pg_catalog.left(p.body, 240)
        ) as summary
      from public.recommendation_signals s
      join public.forum_posts p on p.id = s.content_id
      where s.user_id = current_user_id
        and s.content_kind = 'forum_post'
        and s.last_occurred_at > pg_catalog.now() - interval '90 days'
        and p.status in ('active', 'locked')
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = current_user_id and b.blocked_id = p.author_id)
            or (b.blocker_id = p.author_id and b.blocked_id = current_user_id)
        )
      order by weight desc
      limit 16
    ) history;
  end if;

  if preference_query is null or pg_catalog.length(preference_query) < 1 then
    return pg_catalog.jsonb_build_object(
      'eligible', false,
      'preference_query', null,
      'cache_key', null,
      'ranked_ids', null
    );
  end if;

  computed_cache_key := pg_catalog.md5(
    p_surface || '|' || latest_signal::text || '|'
      || pg_catalog.array_to_string(p_candidate_ids, ',')
  );

  select cache.ranked_ids
  into cached_ranked_ids
  from public.ai_recommendation_cache cache
  where cache.user_id = current_user_id
    and cache.surface = p_surface
    and cache.cache_key = computed_cache_key
    and cache.expires_at > pg_catalog.now();

  return pg_catalog.jsonb_build_object(
    'eligible', true,
    'preference_query', pg_catalog.left(preference_query, 4000),
    'cache_key', computed_cache_key,
    'ranked_ids', cached_ranked_ids
  );
end;
$$;

create function public.set_ai_recommendation_cache(
  p_surface text,
  p_cache_key text,
  p_ranked_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  ranked_count integer;
  distinct_ranked_count integer;
  visible_count integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_surface is null
      or p_surface not in ('event', 'forum_post')
      or p_cache_key is null
      or p_cache_key !~ '^[0-9a-f]{32}$' then
    raise exception using errcode = '22023', message = 'invalid_recommendation_cache';
  end if;

  ranked_count := pg_catalog.cardinality(p_ranked_ids);
  select pg_catalog.count(distinct ranked_id)::integer
  into distinct_ranked_count
  from pg_catalog.unnest(p_ranked_ids) ranked_id;
  if p_ranked_ids is null
      or ranked_count not between 2 and 24
      or distinct_ranked_count <> ranked_count then
    raise exception using errcode = '22023', message = 'invalid_recommendation_candidates';
  end if;

  if p_surface = 'event' then
    select pg_catalog.count(*)::integer
    into visible_count
    from public.events e
    where e.id = any(p_ranked_ids)
      and e.status = 'published'
      and e.visibility = 'public'
      and e.start_at > pg_catalog.now()
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_id = current_user_id and b.blocked_id = e.organizer_id)
          or (b.blocker_id = e.organizer_id and b.blocked_id = current_user_id)
      );
  else
    select pg_catalog.count(*)::integer
    into visible_count
    from public.forum_posts p
    where p.id = any(p_ranked_ids)
      and p.status in ('active', 'locked')
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_id = current_user_id and b.blocked_id = p.author_id)
          or (b.blocker_id = p.author_id and b.blocked_id = current_user_id)
      );
  end if;

  if visible_count <> ranked_count then
    raise exception using errcode = '22023', message = 'invalid_recommendation_candidates';
  end if;

  insert into public.ai_recommendation_cache (
    user_id,
    surface,
    cache_key,
    ranked_ids,
    expires_at
  ) values (
    current_user_id,
    p_surface,
    p_cache_key,
    p_ranked_ids,
    pg_catalog.now() + interval '30 minutes'
  )
  on conflict (user_id, surface)
  do update set
    cache_key = excluded.cache_key,
    ranked_ids = excluded.ranked_ids,
    expires_at = excluded.expires_at,
    updated_at = pg_catalog.now();

  return true;
end;
$$;

revoke all on function public.get_ai_recommendation_state(text, uuid[])
  from public, anon;
revoke all on function public.set_ai_recommendation_cache(text, text, uuid[])
  from public, anon;

grant execute on function public.get_ai_recommendation_state(text, uuid[])
  to authenticated;
grant execute on function public.set_ai_recommendation_cache(text, text, uuid[])
  to authenticated;

comment on table public.ai_recommendation_cache is
  'Short-lived per-user cross-encoder ordering cache; inaccessible through direct table APIs.';
comment on function public.get_ai_recommendation_state(text, uuid[]) is
  'Builds an anonymous bounded preference summary and returns an exact cached ordering when available.';
comment on function public.set_ai_recommendation_cache(text, text, uuid[]) is
  'Stores a validated visible recommendation ordering for thirty minutes.';
comment on function public.recommend_personalized_events(
  double precision, double precision, double precision
) is 'Retrieves nearby event candidates with recent private engagement, embedding taste, distance, time, and popularity.';
comment on function public.recommend_personalized_forum_posts(
  integer, timestamptz
) is 'Retrieves discussion candidates with recent private engagement, embedding taste, freshness, and popularity.';
