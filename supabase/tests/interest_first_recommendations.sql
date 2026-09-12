-- Deterministic ranking scenarios with zero history and one deliberate choice.
-- These verify relevance invariants, not measured real-world recommendation lift.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id, email, raw_user_meta_data) values
  ('92000000-0000-4000-8000-000000000001', 'rec-host@example.test', '{"display_name":"Host"}'),
  ('92000000-0000-4000-8000-000000000002', 'rec-photo@example.test', '{"display_name":"Photo member"}'),
  ('92000000-0000-4000-8000-000000000003', 'rec-games@example.test', '{"display_name":"Games member"}'),
  ('92000000-0000-4000-8000-000000000004', 'rec-new@example.test', '{"display_name":"New member"}');

update public.profiles set interests = array['Photography']
where id = '92000000-0000-4000-8000-000000000002';
update public.profiles set interests = array['Games']
where id = '92000000-0000-4000-8000-000000000003';

insert into public.events(id, organizer_id, title, description, category, venue_name, address,
  location, start_at, end_at, max_participants, beginner_friendly, wheelchair_accessible)
select ('92100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '92000000-0000-4000-8000-000000000001', title, description, category, 'Community centre', 'Test address',
  extensions.st_setsrid(extensions.st_makepoint(13.405, 52.52), 4326)::extensions.geography,
  now() + days * interval '1 day', now() + days * interval '1 day' + interval '2 hours', 12, true, accessible
from (values
  (1, 'Photo walk', 'Learn to use your camera outdoors.', 'Photography', 5, true),
  (2, 'Coffee meetup', 'Chat over coffee with neighbours.', 'Coffee', 1, true),
  (3, 'Tabletop afternoon', 'Play board games and chess together.', 'Board Games', 4, true),
  (4, 'Cycling by the river', 'An easy bicycle ride.', 'Cycling', 3, true),
  (5, 'Upstairs camera workshop', 'Indoor photography practice.', 'Photography', 2, false)
) fixture(n, title, description, category, days, accessible);

insert into public.forum_posts(id, author_id, category, title, body, last_activity_at) values
  ('92200000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
   'General', 'Camera practice this weekend', 'Who wants to go on a photography walk?', now() - interval '2 days'),
  ('92200000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001',
   'General', 'Anyone for board games?', 'We can play chess or other tabletop games.', now() - interval '1 day'),
  ('92200000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000001',
   'General', 'A coffee catch-up', 'Lets meet at the local cafe tomorrow.', now());

select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000002', true);
do $$
declare item jsonb;
begin
  if exists(select 1 from public._recommendation_history('event')) then raise exception 'Fixture has history'; end if;
  select * into item from public.discover_event_plans(52.52, 13.405, 10,
    '{"wheelchair_accessible_only":true}') limit 1;
  if item->>'id' <> '92100000-0000-4000-8000-000000000001'
    or item->>'recommendation_reason' <> 'Matches your interest in Photography' then
    raise exception 'First-visit photography recommendation failed: %', item;
  end if;
  if exists(select 1 from public.discover_event_plans(52.52, 13.405, 10,
    '{"wheelchair_accessible_only":true}') e where e->>'id' = '92100000-0000-4000-8000-000000000005') then
    raise exception 'Interest match overrode accessibility';
  end if;
  if (select id from public.recommend_personalized_forum_posts() limit 1)
    <> '92200000-0000-4000-8000-000000000001' then raise exception 'Discussion ignored interests'; end if;
  if (public.get_ai_recommendation_state('event', array[
    '92100000-0000-4000-8000-000000000001'::uuid, '92100000-0000-4000-8000-000000000002'::uuid
  ])->>'eligible')::boolean then raise exception 'No-history feed required a model'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000003', true);
do $$
begin
  if (select id from public.recommend_personalized_events(52.52,13.405,10) limit 1)
    <> '92100000-0000-4000-8000-000000000003' then raise exception 'Games did not map to Board Games'; end if;
  if (select id from public.recommend_personalized_forum_posts() limit 1)
    <> '92200000-0000-4000-8000-000000000002' then raise exception 'New members received the same discussion feed'; end if;
  if public._recommendation_interest_match(array['Arts'], 'Other', to_tsvector('english', 'Cartography discussion')) is not null then
    raise exception 'Substring produced a false interest match';
  end if;
  if public._recommendation_interest_match(array['Sports'], 'Cycling', to_tsvector('english', 'Cycling')) <> 'Sports' then
    raise exception 'Broad Sports interest was not mapped';
  end if;
end;
$$;

-- A single save is enough to change both local ranking and model eligibility.
select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000004', true);
insert into public.event_saves(event_id, user_id) values
  ('92100000-0000-4000-8000-000000000004', auth.uid());
do $$
declare state jsonb;
begin
  if (select id from public.recommend_personalized_events(52.52,13.405,10) limit 1)
    <> '92100000-0000-4000-8000-000000000004' then raise exception 'Single save did not affect ranking'; end if;
  state := public.get_ai_recommendation_state('event', array[
    '92100000-0000-4000-8000-000000000001'::uuid, '92100000-0000-4000-8000-000000000004'::uuid]);
  if (state->>'eligible')::boolean is not true or state->>'preference_query' not like '%Action: saved%' then
    raise exception 'Single deliberate choice not eligible';
  end if;
  perform set_config('test.recommendation_cache_key', state->>'cache_key', true);
end;
$$;
update public.profiles set interests = array['Photography'] where id = auth.uid();
do $$
declare state jsonb;
begin
  state := public.get_ai_recommendation_state('event', array[
    '92100000-0000-4000-8000-000000000001'::uuid, '92100000-0000-4000-8000-000000000004'::uuid]);
  if state->>'cache_key' = current_setting('test.recommendation_cache_key') then raise exception 'Interest edit reused stale AI ordering'; end if;
  if state->>'preference_query' like '%Photography%' or state->>'preference_query' like '%92000000%' then
    raise exception 'Profile interests or identity left the database';
  end if;
end;
$$;

-- A reset clears learned preferences without deleting actual saved plans.
select public.reset_recommendation_controls();
do $$
begin
  if exists(select 1 from public._recommendation_history('event')) then raise exception 'Reset resurrected save history'; end if;
  if not exists(select 1 from public.event_saves where user_id = auth.uid()) then raise exception 'Reset deleted saved events'; end if;
end;
$$;

-- Filters are enforced before the candidate cap even in a busy area.
insert into public.events(organizer_id, title, description, category, venue_name, address,
  location, start_at, end_at, max_participants, wheelchair_accessible)
select '92000000-0000-4000-8000-000000000001', 'Nearby coffee ' || n, 'Meet neighbours over coffee.',
  'Coffee', 'Cafe', 'Test address', extensions.st_setsrid(extensions.st_makepoint(13.405,52.52),4326)::extensions.geography,
  now() + interval '1 day', now() + interval '1 day 2 hours', 12, true
from generate_series(1, 505) n;
do $$
begin
  if (select e->>'id' from public.discover_event_plans(52.52,13.405,10,
    jsonb_build_object('start_from',now()+interval '3 days','wheelchair_accessible_only',true)) e limit 1)
    <> '92100000-0000-4000-8000-000000000001' then raise exception 'Filtered ranking lost stated interests'; end if;
  if (select e->>'id' from public.discover_event_plans(52.52,13.405,10,
    '{"wheelchair_accessible_only":true}') e limit 1)
    <> '92100000-0000-4000-8000-000000000001' then raise exception 'Unrelated candidates crowded out first-visit match'; end if;
end;
$$;

select public.hide_recommendation('event', '92100000-0000-4000-8000-000000000001');
do $$
begin
  if exists(select 1 from public.recommend_personalized_events(52.52,13.405,10)
    where id = '92100000-0000-4000-8000-000000000001') then raise exception 'Hidden item returned by direct RPC'; end if;
end;
$$;
select public.update_recommendation_preferences(false, '{}');
do $$
begin
  if exists(select 1 from public._recommendation_history('event')) then raise exception 'Opt-out kept using history'; end if;
  if (select e->>'category' from public.discover_event_plans(52.52,13.405,10,'{}') e limit 1) <> 'Coffee' then
    raise exception 'Opt-out retained interest ranking';
  end if;
end;
$$;

-- Repeat views are deduplicated per item at scoring time; only twelve recent
-- distinct items are used, and passive views never trigger the paid model.
select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000002', true);
insert into public.recommendation_signals(user_id, content_kind, content_id, signal_type, occurrence_count, last_occurred_at)
select auth.uid(), 'event', e.id, 'view', 1000, now() - interval '1 hour'
from public.events e where e.title like 'Nearby coffee %' order by e.id limit 20;
do $$
begin
  if (select count(*) from public._recommendation_history('event')) <> 12 then raise exception 'History not bounded to twelve items'; end if;
  if (select max(weight) from public._recommendation_history('event')) > 1.0 then raise exception 'Repeat views amplified preference'; end if;
  if (select e->>'id' from public.discover_event_plans(52.52,13.405,10,
    '{"wheelchair_accessible_only":true}') e limit 1) <> '92100000-0000-4000-8000-000000000001' then
    raise exception 'Passive browsing overwhelmed declared interests';
  end if;
  if (public.get_ai_recommendation_state('event', array[
    '92100000-0000-4000-8000-000000000001'::uuid, '92100000-0000-4000-8000-000000000004'::uuid
  ])->>'eligible')::boolean then raise exception 'Views alone enabled reranking'; end if;
end;
$$;
update public.recommendation_signals set last_occurred_at = now() - interval '31 days' where user_id = auth.uid();
do $$
begin
  if exists(select 1 from public._recommendation_history('event')) then raise exception 'Old browsing still affects rank'; end if;
  if has_function_privilege('authenticated', 'public._recommendation_history(text)', 'execute')
    or has_function_privilege('anon', 'public.discover_event_plans(double precision,double precision,double precision,jsonb)', 'execute') then
    raise exception 'Private recommendation evidence was exposed';
  end if;
end;
$$;

-- Similar content in a different category can be useful after one attendance;
-- a centroid or category-only recommender would miss this case.
select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000003', true);
update public.profiles set interests = '{}' where id = auth.uid();
update public.events set embedding = ('[1,' || repeat('0,',382) || '0]')::extensions.vector
where id = '92100000-0000-4000-8000-000000000001';
insert into public.events(id,organizer_id,title,description,category,venue_name,address,
  location,start_at,end_at,max_participants,status,embedding)
values ('92100000-0000-4000-8000-000000000006','92000000-0000-4000-8000-000000000001',
  'Previous creative meetup','A finished creative meetup.','Other','Community centre','Test address',
  extensions.st_setsrid(extensions.st_makepoint(13.405,52.52),4326)::extensions.geography,
  now()-interval '2 days',now()-interval '1 day',12,'completed',
  ('[1,' || repeat('0,',382) || '0]')::extensions.vector);
insert into public.event_rsvps(event_id,user_id,status) values
  ('92100000-0000-4000-8000-000000000006',auth.uid(),'attended');
do $$
begin
  if (select id from public.recommend_personalized_events(52.52,13.405,10) limit 1)
    <> '92100000-0000-4000-8000-000000000001' then raise exception 'One attendance did not transfer semantic preference'; end if;
end;
$$;
insert into public.event_feedback(event_id,user_id,rating,attended) values
  ('92100000-0000-4000-8000-000000000006',auth.uid(),1,true);
do $$
begin
  if exists(select 1 from public._recommendation_history('event')) then raise exception 'Poorly rated attendance became positive evidence'; end if;
end;
$$;
rollback;
