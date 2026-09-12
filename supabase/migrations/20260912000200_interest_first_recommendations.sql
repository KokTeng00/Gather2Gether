-- Useful from the first visit: explicit interests stay local, while at most
-- twelve recent distinct items refine them. No new activity log is collected.
alter table public.recommendation_preferences
  add column history_reset_at timestamptz not null default '-infinity';

create function public._recommendation_interest_match(
  p_interests text[], p_category text, p_document tsvector
)
returns text language sql immutable set search_path = '' as $$
  select interest
  from pg_catalog.unnest(p_interests) interest
  where lower(interest) = lower(p_category)
    or p_document @@ pg_catalog.websearch_to_tsquery('english',
      case lower(interest)
        when 'sports' then 'sport OR badminton OR running OR padel OR cycling'
        when 'outdoors' then 'outdoor OR hiking OR walking OR trail OR cycling'
        when 'coffee' then 'coffee OR cafe'
        when 'games' then '"board games" OR tabletop OR chess'
        when 'languages' then '"language exchange" OR "language practice"'
        when 'photography' then 'photography OR camera OR "photo walk"'
        when 'technology' then 'technology OR startup OR coding OR programming'
        when 'arts' then 'art OR painting OR drawing OR museum OR music'
        when 'wellness' then 'wellness OR yoga OR meditation OR running'
        when 'volunteering' then 'volunteer OR volunteering OR cleanup OR charity'
        else interest
      end)
  order by (lower(interest) = lower(p_category)) desc, interest
  limit 1;
$$;

create function public._recommendation_history(p_surface text)
returns table (
  content_id uuid, signal_type text, weight double precision,
  occurred_at timestamptz, category text, creator_id uuid,
  embedding extensions.vector(384), summary text
)
language sql stable security definer set search_path = '' as $$
  with owner as materialized (
    select auth.uid() id, greatest(
      pg_catalog.now() - interval '30 days',
      coalesce(p.history_reset_at, '-infinity'::timestamptz)
    ) since
    from (select auth.uid() id) u
    left join public.recommendation_preferences p on p.user_id = u.id
    where u.id is not null and coalesce(p.enabled, true)
  ), actions as (
    select s.content_id, s.signal_type, s.last_occurred_at occurred_at,
      case s.signal_type when 'joined' then 8.0 when 'tentative' then 4.0
        when 'comment' then 7.0 when 'like' then 4.0 else 1.0 end strength
    from public.recommendation_signals s join owner o on s.user_id = o.id
    where s.content_kind = p_surface and s.last_occurred_at > o.since
    union all
    select s.event_id, 'saved', s.created_at, 6.0
    from public.event_saves s join owner o on s.user_id = o.id
    where p_surface = 'event' and s.created_at > o.since
    union all
    select r.event_id, 'attended', r.updated_at, 10.0
    from public.event_rsvps r join owner o on r.user_id = o.id
    where p_surface = 'event' and r.status = 'attended' and r.updated_at > o.since
  ), visible as (
    select a.*, e.category, e.organizer_id creator_id, e.embedding,
      e.title || ' | ' || left(e.description, 240) summary
    from actions a join public.events e on e.id = a.content_id
    where p_surface = 'event' and e.visibility = 'public'
      and e.status in ('published', 'completed')
      -- Poor feedback must not become a positive attendance preference.
      and not exists (select 1 from public.event_feedback f
        where f.event_id = e.id and f.user_id = auth.uid() and f.rating <= 2)
    union all
    select a.*, p.category, p.author_id, p.embedding,
      p.title || ' | ' || left(p.body, 240)
    from actions a join public.forum_posts p on p.id = a.content_id
    where p_surface = 'forum_post' and p.status in ('active', 'locked')
  ), distinct_items as (
    select distinct on (v.content_id) v.*,
      (v.strength * exp(-extract(epoch from (now() - v.occurred_at)) / 1209600.0))::double precision weight
    from visible v
    where not exists (select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = v.creator_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = v.creator_id))
      and not exists (select 1 from public.hidden_recommendation_content h
        where h.user_id = auth.uid() and h.content_kind = p_surface and h.content_id = v.content_id)
      and not exists (select 1 from public.recommendation_preferences p
        where p.user_id = auth.uid() and v.category = any(p.hidden_categories))
    order by v.content_id, (v.signal_type <> 'view') desc,
      weight desc, v.occurred_at desc, v.signal_type
  )
  select d.content_id, d.signal_type, d.weight, d.occurred_at,
    d.category, d.creator_id, d.embedding, d.summary
  from distinct_items d
  order by (d.signal_type <> 'view') desc, d.occurred_at desc, d.content_id
  limit 12;
$$;

create function public._rank_event_recommendations(
  p_latitude double precision, p_longitude double precision,
  p_radius_km double precision, p_filters jsonb default '{}'
)
returns table (id uuid, distance_meters double precision, score double precision, reason text)
language sql stable security definer set search_path = '' as $$
  with owner as materialized (
    select p.id, coalesce(r.enabled, true) enabled,
      case when coalesce(r.enabled, true) then p.interests else '{}'::text[] end interests,
      coalesce(r.hidden_categories, '{}'::text[]) hidden_categories,
      extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography origin,
      nullif(trim(p_filters->>'interest'), '') search_text,
      (p_filters->>'query_embedding')::extensions.vector(384) query_embedding,
      coalesce((p_filters->>'timezone_offset_minutes')::integer, 0) offset_minutes
    from public.profiles p left join public.recommendation_preferences r on r.user_id = p.id
    where p.id = auth.uid() and p_latitude between -90 and 90
      and p_longitude between -180 and 180 and p_radius_km between 1 and 100
  ), history as materialized (
    select * from public._recommendation_history('event')
  ), categories as (
    select lower(h.category) category, sum(h.weight) / greatest(8.0, (select sum(weight) from history)) affinity
    from history h group by lower(h.category)
  ), creators as (
    select h.creator_id, sum(h.weight) / greatest(8.0, (select sum(weight) from history)) affinity
    from history h group by h.creator_id
  ), eligible as materialized (
    select e.*, o.enabled, o.search_text, o.query_embedding,
      extensions.st_distance(e.location, o.origin) distance_meters,
      public._recommendation_interest_match(o.interests, e.category, e.search_document) matched_interest,
      coalesce(c.affinity, 0.0) category_affinity,
      coalesce(a.affinity, 0.0) creator_affinity,
      coalesce((select max(greatest(0.0, 1 - (e.embedding operator(extensions.<=>) h.embedding))
        * least(1.0, h.weight / 8.0)) from history h where h.embedding is not null), 0.0) semantic_affinity,
      r.status rsvp_status,
      exists(select 1 from public.profile_follows f
        where f.follower_id = o.id and f.followed_id = e.organizer_id) follows_creator
    from public.events e cross join owner o
    left join categories c on c.category = lower(e.category)
    left join creators a on a.creator_id = e.organizer_id
    left join public.event_rsvps r on r.event_id = e.id and r.user_id = o.id
    where e.status = 'published' and e.visibility = 'public' and e.start_at > now()
      and extensions.st_dwithin(e.location, o.origin, p_radius_km * 1000)
      and (nullif(p_filters->>'start_from', '') is null or e.start_at >= (p_filters->>'start_from')::timestamptz)
      and (nullif(p_filters->>'start_before', '') is null or e.start_at < (p_filters->>'start_before')::timestamptz)
      and (nullif(p_filters->>'category', '') is null or e.category = p_filters->>'category')
      and (not coalesce((p_filters->>'spots_only')::boolean, false) or public._event_places(e.id) < e.max_participants)
      and (not coalesce((p_filters->>'following_only')::boolean, false) or exists (
        select 1 from public.profile_follows f where f.follower_id = o.id and f.followed_id = e.organizer_id))
      and (not coalesce((p_filters->>'beginner_friendly_only')::boolean, false) or e.beginner_friendly)
      and (not coalesce((p_filters->>'wheelchair_accessible_only')::boolean, false) or e.wheelchair_accessible)
      and (coalesce(p_filters->>'event_setting', 'any') = 'any' or e.event_setting = p_filters->>'event_setting')
      and (nullif(p_filters->>'event_language', '') is null or lower(e.event_language) = lower(p_filters->>'event_language'))
      and (coalesce(p_filters->>'age_guidance', 'any') = 'any' or e.age_guidance = p_filters->>'age_guidance')
      and (coalesce(p_filters->>'time_filter', 'any') = 'any' or case p_filters->>'time_filter'
        when 'morning' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 5
          and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) < 12
        when 'afternoon' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 12
          and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) < 17
        when 'evening' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 17
        else false end)
      and (o.search_text is null or (o.query_embedding is not null and e.embedding is not null)
        or e.search_document @@ websearch_to_tsquery('english', o.search_text)
        or strpos(lower(e.title || ' ' || e.category || ' ' || e.description), lower(o.search_text)) > 0)
      and not (e.category = any(o.hidden_categories))
      and not exists (select 1 from public.hidden_recommendation_content h
        where h.user_id = o.id and h.content_kind = 'event' and h.content_id = e.id)
      and not exists (select 1 from public.blocks b
        where (b.blocker_id = o.id and b.blocked_id = e.organizer_id)
          or (b.blocked_id = o.id and b.blocker_id = e.organizer_id))
  ), candidates as materialized (
    select e.* from eligible e
    -- Include interest matches before limiting; nearby unrelated items cannot
    -- crowd a new member's selected topics out of the candidate pool.
    order by case when not e.enabled and e.search_text is null then e.start_at end,
      case when e.search_text is not null then
      (case when e.search_document @@ websearch_to_tsquery('english', e.search_text) then 1.0 else 0.0 end
       + coalesce(1 - (e.embedding operator(extensions.<=>) e.query_embedding), 0))
      else (case when e.matched_interest is not null then 4.0 else 0.0 end
       + 3.0 * e.category_affinity + 1.5 * e.semantic_affinity
       + 1.0 / (1.0 + e.distance_meters / 5000.0)) end desc,
      e.start_at, e.id
    limit 500
  ), scored as (
    select c.id, c.distance_meters, c.start_at,
      case when c.search_text is not null then
        (case when c.search_document @@ websearch_to_tsquery('english', c.search_text) then 1.0 else 0.0 end
          + coalesce(1 - (c.embedding operator(extensions.<=>) c.query_embedding), 0))
      else
        (case when c.matched_interest is not null then 4.0 else 0.0 end)
        + 3.0 * c.category_affinity + 0.5 * c.creator_affinity
        + c.semantic_affinity * 1.5
        + case when c.enabled and c.follows_creator then 0.75 else 0.0 end
        + 1.0 / (1.0 + c.distance_meters / 5000.0)
        + 1.0 / (1.0 + extract(epoch from (c.start_at - now())) / 604800.0)
        - case when c.enabled and (c.rsvp_status in ('joined', 'attended') or c.organizer_id = auth.uid()) then 4.0 else 0.0 end
        - case when c.enabled and public._event_places(c.id) >= c.max_participants then 1.0 else 0.0 end
      end::double precision score,
      case when c.search_text is not null then 'Matches your search'
        when not c.enabled then 'Near your chosen area'
        when c.matched_interest is not null then 'Matches your interest in ' || c.matched_interest
        when c.category_affinity >= 0.4 then 'Based on your recent event choices'
        when c.follows_creator then 'From an organizer you follow'
        else 'Upcoming near you' end reason,
      c.enabled, c.search_text
    from candidates c
  )
  select s.id, s.distance_meters, s.score, s.reason from scored s
  order by case when s.enabled or s.search_text is not null then s.score end desc,
    s.start_at, s.distance_meters, s.id
  limit 100;
$$;

revoke all on function public._recommendation_interest_match(text[], text, tsvector) from public, anon, authenticated;
revoke all on function public._recommendation_history(text) from public, anon, authenticated;
revoke all on function public._rank_event_recommendations(double precision, double precision, double precision, jsonb) from public, anon, authenticated;

-- Keep the existing RPC contract for older clients while using the same scorer
-- as filtered discovery. Array ordinality preserves the scorer's exact order.
create or replace function public.recommend_personalized_events(
  p_latitude double precision, p_longitude double precision,
  p_radius_km double precision default 10
)
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text, description text,
  category text, venue_name text, address text, latitude double precision,
  longitude double precision, start_at timestamptz, end_at timestamptz,
  max_participants integer, joined_count bigint, tentative_count bigint,
  distance_meters double precision, user_rsvp_status text
)
language sql stable security definer set search_path = '' as $$
  select e.id, e.organizer_id, p.display_name, e.title, e.description,
    e.category, e.venue_name, e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry), e.start_at, e.end_at,
    e.max_participants, public._event_places(e.id)::bigint,
    (select count(*) from public.event_rsvps r where r.event_id = e.id and r.status = 'tentative'),
    ranked.distance_meters,
    (select r.status from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
  from public._rank_event_recommendations(p_latitude, p_longitude, p_radius_km) with ordinality ranked
  join public.events e on e.id = ranked.id
  join public.profiles p on p.id = e.organizer_id
  order by ranked.ordinality;
$$;

create or replace function public.discover_event_plans(
  p_latitude double precision, p_longitude double precision,
  p_radius_km double precision, p_filters jsonb
)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_latitude is null or p_longitude is null or p_radius_km is null
    or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
    or p_radius_km not between 1 and 100
    or (p_filters->>'start_before')::timestamptz <= (p_filters->>'start_from')::timestamptz
    or coalesce((p_filters->>'timezone_offset_minutes')::integer, 0) not between -840 and 840
    or char_length(p_filters->>'interest') > 240 then
    raise exception using errcode = '22023', message = 'invalid_parameter';
  end if;
  return query
  select public.get_event_plan(r.id, false) || jsonb_build_object(
    'distance_meters', r.distance_meters, 'recommendation_reason', r.reason
  )
  from public._rank_event_recommendations(p_latitude, p_longitude, p_radius_km, p_filters)
    with ordinality r
  order by r.ordinality limit 60;
end;
$$;

create or replace function public.recommend_personalized_forum_posts(
  p_limit integer default 30, p_before timestamptz default null
)
returns table (
  id uuid, author_id uuid, author_name text, author_username text, category text,
  title text, body text, status text, created_at timestamptz, last_activity_at timestamptz,
  comment_count bigint, viewer_is_author boolean, has_image boolean, place_name text, place_address text
)
language sql stable security definer set search_path = '' as $$
  with owner as materialized (
    select p.id, coalesce(r.enabled, true) enabled,
      case when coalesce(r.enabled, true) then p.interests else '{}'::text[] end interests,
      coalesce(r.hidden_categories, '{}'::text[]) hidden_categories
    from public.profiles p left join public.recommendation_preferences r on r.user_id = p.id
    where p.id = auth.uid()
  ), history as materialized (
    select * from public._recommendation_history('forum_post')
  ), candidates as materialized (
    select p.*, o.enabled,
      public._recommendation_interest_match(o.interests, p.category, p.search_document) matched_interest,
      coalesce((select max(greatest(0.0, 1 - (p.embedding operator(extensions.<=>) h.embedding))
        * least(1.0, h.weight / 8.0)) from history h where h.embedding is not null), 0.0) semantic_affinity,
      coalesce((select sum(h.weight) from history h where h.creator_id = p.author_id), 0.0)
        / greatest(8.0, (select sum(weight) from history)) author_affinity
    from public.forum_posts p cross join owner o
    where p.status in ('active', 'locked') and (p_before is null or p.last_activity_at < p_before)
      and not (p.category = any(o.hidden_categories))
      and not exists(select 1 from public.hidden_recommendation_content h
        where h.user_id = o.id and h.content_kind = 'forum_post' and h.content_id = p.id)
      and not exists(select 1 from public.blocks b
        where (b.blocker_id = o.id and b.blocked_id = p.author_id)
          or (b.blocked_id = o.id and b.blocker_id = p.author_id))
    order by (public._recommendation_interest_match(o.interests, p.category, p.search_document) is not null) desc,
      semantic_affinity desc, author_affinity desc, p.last_activity_at desc, p.id
    limit 500
  ), scored as (
    select c.*,
      case when c.matched_interest is not null then 4.0 else 0.0 end
      -- Forum categories describe the type of conversation, not its topic;
      -- semantic evidence is more useful than liking every "General" post.
      + c.semantic_affinity * 3.0
      + c.author_affinity * 0.5
      + 1.0 / (1.0 + greatest(0.0, extract(epoch from (now() - c.last_activity_at)) / 604800.0))
      - case when c.enabled and c.author_id = auth.uid() then 2.0 else 0.0 end score
    from candidates c
  )
  select c.id, c.author_id, p.display_name, p.username, c.category, c.title, c.body,
    c.status, c.created_at, c.last_activity_at,
    (select count(*) from public.forum_comments f where f.post_id = c.id and f.status = 'active'
      and not exists(select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = f.author_id)
          or (b.blocked_id = auth.uid() and b.blocker_id = f.author_id))),
    c.author_id = auth.uid(), c.image_key is not null, c.place_name, c.place_address
  from scored c join public.profiles p on p.id = c.author_id
  order by case when c.enabled then c.score end desc, c.last_activity_at desc, c.id
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.get_ai_recommendation_state(p_surface text, p_candidate_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  preference_query text;
  history_key text;
  profile_key text;
  candidate_key text;
  computed_cache_key text;
  cached_ranked_ids uuid[];
  strong_count integer;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_surface is null or p_surface not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'invalid_recommendation_surface';
  end if;
  if p_candidate_ids is null or cardinality(p_candidate_ids) not between 2 and 24
    or (select count(distinct id) from unnest(p_candidate_ids) id) <> cardinality(p_candidate_ids) then
    raise exception using errcode = '22023', message = 'invalid_recommendation_candidates';
  end if;

  -- One deliberate choice is enough. Passive views alone never trigger a
  -- model call. Interests are used only inside PostgreSQL, not in this query.
  select count(*) filter (where h.signal_type <> 'view'),
    string_agg('Action: ' || h.signal_type || ' | Category: ' || h.category || ' | ' || h.summary,
      E'\n' order by h.occurred_at desc, h.content_id),
    string_agg(h.content_id::text || ':' || h.signal_type || ':' || h.occurred_at::text || ':' || h.summary,
      '|' order by h.content_id)
  into strong_count, preference_query, history_key
  from public._recommendation_history(p_surface) h
  where h.signal_type <> 'view';

  if strong_count = 0 then
    return jsonb_build_object('eligible', false, 'preference_query', null, 'cache_key', null, 'ranked_ids', null);
  end if;
  select p.interests::text || coalesce(r.hidden_categories::text, '')
    || coalesce(r.history_reset_at::text, '') into profile_key
  from public.profiles p left join public.recommendation_preferences r on r.user_id = p.id
  where p.id = auth.uid();
  if p_surface = 'event' then
    select string_agg(e.id::text || ':' || e.updated_at::text, '|' order by ids.ordinality)
    into candidate_key from unnest(p_candidate_ids) with ordinality ids(id, ordinality)
    join public.events e on e.id = ids.id;
  else
    select string_agg(p.id::text || ':' || p.updated_at::text, '|' order by ids.ordinality)
    into candidate_key from unnest(p_candidate_ids) with ordinality ids(id, ordinality)
    join public.forum_posts p on p.id = ids.id;
  end if;
  computed_cache_key := md5('interest-first-v1|' || p_surface || '|' || history_key || '|'
    || profile_key || '|' || coalesce(candidate_key, '') || '|' || array_to_string(p_candidate_ids, ','));
  select c.ranked_ids into cached_ranked_ids from public.ai_recommendation_cache c
  where c.user_id = auth.uid() and c.surface = p_surface
    and c.cache_key = computed_cache_key and c.expires_at > now();
  return jsonb_build_object('eligible', true, 'preference_query', left(preference_query, 4000),
    'cache_key', computed_cache_key, 'ranked_ids', cached_ranked_ids);
end;
$$;

create or replace function public.reset_recommendation_controls()
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.hidden_recommendation_content where user_id = auth.uid();
  delete from public.recommendation_signals where user_id = auth.uid();
  delete from public.ai_recommendation_cache where user_id = auth.uid();
  -- Preserve actual saves and attendance records, but stop using their old
  -- activity for personalization after a reset.
  insert into public.recommendation_preferences(user_id, enabled, hidden_categories, history_reset_at)
  values(auth.uid(), true, '{}', now())
  on conflict(user_id) do update set enabled = true, hidden_categories = '{}', history_reset_at = now();
  return true;
end;
$$;

comment on function public._recommendation_history(text) is
  'At most twelve distinct visible items from the last thirty days; one strongest action per item, no repeat-view amplification.';
comment on function public.get_ai_recommendation_state(text, uuid[]) is
  'Optional reranking after one deliberate choice; declared interests remain in PostgreSQL and are never sent to the provider.';
