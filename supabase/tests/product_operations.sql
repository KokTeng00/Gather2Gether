-- Transactional coverage for onboarding, member controls, host operations,
-- recurring edits, exports, and role-gated moderation.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('50000000-0000-4000-8000-000000000001', 'operations-host@example.test', '{"display_name":"Host"}'),
  ('50000000-0000-4000-8000-000000000002', 'operations-member@example.test', '{"display_name":"Member"}'),
  ('50000000-0000-4000-8000-000000000003', 'operations-moderator@example.test', '{"display_name":"Moderator"}');

select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000002', true
);
select public.complete_onboarding(
  array['Outdoors', 'Coffee'], array['beginner_friendly'],
  25, 52.5201, 13.4051
);
select public.update_notification_preferences(
  false, true, true, true, true, 1320, 420, 60
);
select public.update_recommendation_preferences(
  false, array['Running']
);
select public.hide_recommendation(
  'event', '59999999-9999-4999-8999-999999999999'
);

do $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = '50000000-0000-4000-8000-000000000002'
      and p.onboarding_completed_at is not null
      and p.interests = array['Coffee', 'Outdoors']
      and p.approximate_latitude = 52.52
  ) then
    raise exception 'onboarding preferences were not normalized and saved';
  end if;
  if (select enabled from public.get_recommendation_preferences()) then
    raise exception 'recommendation opt-out was not saved';
  end if;
end;
$$;

select public.register_push_device(
  'operations-test-fcm-token-with-enough-entropy', 'android', 'en-GB'
);
insert into public.member_notifications (user_id, kind, title, body) values (
  '50000000-0000-4000-8000-000000000002',
  'reminder', 'Preference test', 'This must not enter the push outbox.'
);

do $$
begin
  if exists (
    select 1 from public.push_deliveries d
    join public.member_notifications n on n.id = d.notification_id
    where n.title = 'Preference test'
  ) then
    raise exception 'disabled push preference still queued a delivery';
  end if;
end;
$$;

select public.update_notification_preferences(
  true, true, true, true, true,
  (
    pg_catalog.date_part('hour', pg_catalog.now())::integer * 60
    + pg_catalog.date_part('minute', pg_catalog.now())::integer
  ),
  (
    pg_catalog.date_part('hour', pg_catalog.now())::integer * 60
    + pg_catalog.date_part('minute', pg_catalog.now())::integer + 60
  ) % 1440,
  0
);
insert into public.member_notifications (user_id, kind, title, body) values (
  '50000000-0000-4000-8000-000000000002',
  'reminder', 'Quiet-hour test', 'This must remain queued for later delivery.'
);

do $$
begin
  if not public._push_notification_category_allowed(
    '50000000-0000-4000-8000-000000000002', 'reminder'
  ) or public._push_notification_allowed(
    '50000000-0000-4000-8000-000000000002', 'reminder', pg_catalog.now()
  ) then
    raise exception 'quiet hours did not defer an otherwise enabled category';
  end if;
  if not exists (
    select 1 from public.push_deliveries d
    join public.member_notifications n on n.id = d.notification_id
    where n.title = 'Quiet-hour test' and d.delivered_at is null
  ) then
    raise exception 'quiet-hour delivery was discarded instead of queued';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true
);
select public.create_event_v3(
  'Operations walk', 'A practical recurring walk.', 'Hiking', 'Test Park',
  'Test entrance', 52.52, 13.405,
  pg_catalog.now() + interval '1 hour',
  pg_catalog.now() + interval '2 hours',
  8, true, false, 'outdoor', 'English', 'all_ages', 'Water',
  'published', 'public', 'weekly', 2
) as event_ids \gset
select set_config(
  'test.first_event_id', (:'event_ids'::uuid[])[1]::text, true
);

select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000002', true
);
select public.set_event_rsvp(
  current_setting('test.first_event_id')::uuid, 'joined'
);
select public.set_event_saved(
  current_setting('test.first_event_id')::uuid, true
);

select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true
);
select public.set_event_attendance(
  current_setting('test.first_event_id')::uuid,
  '50000000-0000-4000-8000-000000000002',
  'attended'
);

do $$
begin
  if (
    select (public.get_event_host_dashboard(
      current_setting('test.first_event_id')::uuid
    ) ->> 'attended')::integer
  ) <> 1 then
    raise exception 'host dashboard did not include check-in';
  end if;
end;
$$;

select public.update_event_series_v1(
  current_setting('test.first_event_id')::uuid, 'future',
  'Updated operations walk', 'Updated details.', 'Hiking', 'New Park',
  'New entrance', 52.52, 13.405,
  pg_catalog.now() + interval '1 day',
  pg_catalog.now() + interval '1 day 1 hour',
  10, true, false, 'outdoor', 'English', 'all_ages', 'Water',
  'published', 'public'
);

do $$
begin
  if (
    select pg_catalog.count(*) from public.events e
    where e.series_id = (
      select anchor.series_id from public.events anchor
      where anchor.id = current_setting('test.first_event_id')::uuid
    ) and e.title = 'Updated operations walk'
  ) <> 2 then
    raise exception 'future series edit did not update both occurrences';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000002', true
);
insert into public.reports (reporter_id, event_id, reason) values (
  '50000000-0000-4000-8000-000000000002',
  current_setting('test.first_event_id')::uuid,
  'misleading'
) returning id as report_id \gset
select set_config('test.report_id', :'report_id', true);

do $$
begin
  if public.export_own_data() -> 'profile' ->> 'display_name' <> 'Member' then
    raise exception 'data export omitted the member profile';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"moderator"}}',
  true
);
select set_config(
  'request.jwt.claim.sub', '50000000-0000-4000-8000-000000000003', true
);

do $$
begin
  if not public.get_moderation_status() then
    raise exception 'moderator app metadata was not recognized';
  end if;
  if (select pg_catalog.count(*) from public.list_moderation_reports('open')) < 1 then
    raise exception 'moderation queue omitted an open event report';
  end if;
end;
$$;

select public.moderate_report('event', :'report_id'::uuid, 'hidden', 'Reviewed in test');

do $$
begin
  if not exists (
    select 1 from public.moderation_actions a
    where a.report_id = current_setting('test.report_id')::uuid
      and a.action = 'hidden'
  ) then
    raise exception 'moderation audit record was not created';
  end if;
  if (
    select e.status from public.events e
    where e.id = current_setting('test.first_event_id')::uuid
  ) <> 'cancelled' then
    raise exception 'hidden event was not cancelled';
  end if;
  if not exists (
    select 1 from public.member_notifications n
    where n.user_id = '50000000-0000-4000-8000-000000000002'
      and n.event_id = current_setting('test.first_event_id')::uuid
      and n.kind = 'event_cancelled'
  ) then
    raise exception 'event removal did not notify an affected member';
  end if;
end;
$$;

rollback;
