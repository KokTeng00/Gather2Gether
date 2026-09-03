-- Transactional coverage for practical discovery and event-management tools.
-- Run against a disposable/local Supabase database after all migrations.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('30000000-0000-4000-8000-000000000001', 'tools-host@example.test', '{"display_name":"Host"}'),
  ('30000000-0000-4000-8000-000000000002', 'tools-one@example.test', '{"display_name":"One"}'),
  ('30000000-0000-4000-8000-000000000003', 'tools-two@example.test', '{"display_name":"Two"}'),
  ('30000000-0000-4000-8000-000000000004', 'tools-three@example.test', '{"display_name":"Three"}');

update public.profiles set
  approximate_latitude = 52.52,
  approximate_longitude = 13.405
where id in (
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000004'
);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000002', true
);
select public.set_profile_follow(
  '30000000-0000-4000-8000-000000000001', true
);
select public.create_saved_event_search(
  'Nearby running', 'running', 10, 'Running', 'any', 'any', 0, false, false
);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000001', true
);
select public.create_event_v2(
  'Practical tools run', 'A friendly run.', 'Running', 'Test Park',
  'Test entrance', 52.52, 13.405,
  pg_catalog.now() + interval '5 days',
  pg_catalog.now() + interval '5 days 1 hour',
  6, true, true, 'outdoor', 'English', 'all_ages', 'Water'
) as event_id \gset
select set_config('test.event_id', :'event_id', true);

do $$
begin
  if not exists (
    select 1 from public.member_notifications n
    where n.user_id = '30000000-0000-4000-8000-000000000002'
      and n.event_id = current_setting('test.event_id')::uuid
      and n.kind = 'followed_host_event'
  ) then
    raise exception 'followed-host event alert was not created';
  end if;
  if not exists (
    select 1 from public.member_notifications n
    where n.user_id = '30000000-0000-4000-8000-000000000002'
      and n.event_id = current_setting('test.event_id')::uuid
      and n.kind = 'saved_search_match'
  ) then
    raise exception 'saved-search event alert was not created';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000002', true
);
select public.set_event_rsvp(:'event_id'::uuid, 'joined');
select public.set_event_attendee_visibility(:'event_id'::uuid, false);
select public.set_event_discussion_notifications(:'event_id'::uuid, false);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000003', true
);
select public.set_event_rsvp(:'event_id'::uuid, 'joined');
select public.set_event_attendee_visibility(:'event_id'::uuid, true);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000004', true
);
select public.set_event_rsvp(:'event_id'::uuid, 'joined');
select public.set_event_attendee_visibility(:'event_id'::uuid, false);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000002', true
);
do $$
begin
  if (
    select pg_catalog.count(*)
    from public.list_event_attendees(current_setting('test.event_id')::uuid)
  ) <> 3 then
    raise exception 'privacy-aware attendee list returned the wrong members';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000001', true
);
select public.create_event_discussion_message(
  :'event_id'::uuid, 'The route is confirmed.'
);
select public.request_event_rsvp_reconfirmation(:'event_id'::uuid);

select set_config(
  'request.jwt.claim.sub', '30000000-0000-4000-8000-000000000002', true
);
select public.confirm_event_rsvp(:'event_id'::uuid);

update public.events set reconfirmation_deadline_at = pg_catalog.now() - interval '1 minute'
where id = :'event_id'::uuid;
select public.process_due_event_reconfirmations();

do $$
begin
  if exists (
    select 1 from public.member_notifications n
    where n.user_id = '30000000-0000-4000-8000-000000000002'
      and n.event_id = current_setting('test.event_id')::uuid
      and n.kind = 'discussion_reply'
  ) then
    raise exception 'muted attendee received a discussion notification';
  end if;
  if (
    select r.status from public.event_rsvps r
    where r.event_id = current_setting('test.event_id')::uuid
      and r.user_id = '30000000-0000-4000-8000-000000000002'
  ) <> 'joined' then
    raise exception 'reconfirmed attendee lost their place';
  end if;
  if exists (
    select 1 from public.event_rsvps r
    where r.event_id = current_setting('test.event_id')::uuid
      and r.user_id in (
        '30000000-0000-4000-8000-000000000003',
        '30000000-0000-4000-8000-000000000004'
      )
      and r.status = 'joined'
  ) then
    raise exception 'unconfirmed attendee kept a reserved place';
  end if;
end;
$$;

rollback;
