-- Transactional smoke coverage for the event lifecycle migration.
-- Run against a disposable/local Supabase database; all rows are rolled back.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('10000000-0000-4000-8000-000000000001', 'host@example.test', '{"display_name":"Host"}'),
  ('10000000-0000-4000-8000-000000000002', 'going@example.test', '{"display_name":"Going"}'),
  ('10000000-0000-4000-8000-000000000003', 'waiting@example.test', '{"display_name":"Waiting"}');

insert into public.events (
  id, organizer_id, title, description, category, venue_name, address,
  location, start_at, end_at, max_participants
) values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'Lifecycle test', 'A disposable event.', 'Running', 'Test Park',
  'Test entrance',
  extensions.st_setsrid(extensions.st_makepoint(13.405, 52.52), 4326)::extensions.geography,
  pg_catalog.now() + interval '1 day',
  pg_catalog.now() + interval '1 day 1 hour',
  2
);

insert into public.event_rsvps (event_id, user_id, status) values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'joined'
);

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true
);
select public.set_event_rsvp(
  '20000000-0000-4000-8000-000000000001', 'joined'
);

do $$
begin
  if (select count(*) from public.list_profile_events(
    '10000000-0000-4000-8000-000000000001', 'hosting'
  )) <> 1 then
    raise exception 'upcoming hosted event was not visible on the profile';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true
);
select public.set_event_rsvp(
  '20000000-0000-4000-8000-000000000001', 'joined'
);

do $$
begin
  if (
    select r.status from public.event_rsvps r
    where r.event_id = '20000000-0000-4000-8000-000000000001'
      and r.user_id = '10000000-0000-4000-8000-000000000003'
  ) <> 'waitlisted' then
    raise exception 'full event did not create a waitlist entry';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true
);
select public.set_event_saved(
  '20000000-0000-4000-8000-000000000001', true
);
select public.set_event_reminder(
  '20000000-0000-4000-8000-000000000001',
  pg_catalog.now() + interval '1 hour'
);
select public.set_event_rsvp(
  '20000000-0000-4000-8000-000000000001', 'cancelled'
);

do $$
begin
  if (
    select r.status from public.event_rsvps r
    where r.event_id = '20000000-0000-4000-8000-000000000001'
      and r.user_id = '10000000-0000-4000-8000-000000000003'
  ) <> 'joined' then
    raise exception 'oldest waitlist member was not promoted';
  end if;
  if not exists (
    select 1 from public.member_notifications n
    where n.user_id = '10000000-0000-4000-8000-000000000003'
      and n.kind = 'waitlist_promoted'
  ) then
    raise exception 'waitlist promotion notification was not created';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true
);
select public.create_event_announcement(
  '20000000-0000-4000-8000-000000000001', 'Bring a light jacket.'
);

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true
);
select public.create_event_discussion_message(
  '20000000-0000-4000-8000-000000000001', 'Is the route beginner friendly?'
);

update public.events set
  start_at = pg_catalog.now() - interval '2 hours',
  end_at = pg_catalog.now() - interval '1 hour',
  status = 'completed'
where id = '20000000-0000-4000-8000-000000000001';

select public.submit_event_feedback(
  '20000000-0000-4000-8000-000000000001', true, 5, 'Welcoming group.'
);

do $$
begin
  if (select count(*) from public.list_profile_events(
    '10000000-0000-4000-8000-000000000003', 'past'
  )) <> 1 then
    raise exception 'owner could not see their private past activity';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true
);

do $$
begin
  if (select count(*) from public.list_profile_events(
    '10000000-0000-4000-8000-000000000003', 'past'
  )) <> 0 then
    raise exception 'private past activity was disclosed to another member';
  end if;
end;
$$;

set local role authenticated;
update public.profiles
set show_past_events_public = true
where id = '10000000-0000-4000-8000-000000000003';
reset role;

do $$
begin
  if (select count(*) from public.list_profile_events(
    '10000000-0000-4000-8000-000000000003', 'past'
  )) <> 1 then
    raise exception 'opted-in confirmed attendance was not publicly visible';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true
);

do $$
begin
  if (select count(*) from public.list_event_feedback(
    '20000000-0000-4000-8000-000000000001'
  )) <> 1 then
    raise exception 'host could not read anonymized event feedback';
  end if;
  if (select count(*) from public.list_my_events('past')) <> 1 then
    raise exception 'completed hosted event did not appear in Past plans';
  end if;
end;
$$;

rollback;
