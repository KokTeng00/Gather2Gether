-- Transactional coverage for push registration, account switching, and outbox
-- claiming. Run against a disposable/local Supabase database after migrations.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('40000000-0000-4000-8000-000000000001', 'push-one@example.test', '{"display_name":"One"}'),
  ('40000000-0000-4000-8000-000000000002', 'push-two@example.test', '{"display_name":"Two"}');

select set_config(
  'request.jwt.claim.sub', '40000000-0000-4000-8000-000000000001', true
);
select public.register_push_device(
  'test-fcm-device-token-with-enough-entropy', 'android', 'en-GB'
);
insert into public.member_notifications (user_id, kind, title, body) values (
  '40000000-0000-4000-8000-000000000001',
  'event_updated', 'First account update', 'Private first-account content.'
);

do $$
begin
  if (select pg_catalog.count(*) from public.push_deliveries) <> 1 then
    raise exception 'notification was not queued for the registered device';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub', '40000000-0000-4000-8000-000000000002', true
);
select public.register_push_device(
  'test-fcm-device-token-with-enough-entropy', 'android', 'de-DE'
);

do $$
begin
  if exists (
    select 1
    from public.push_deliveries delivery
    join public.member_notifications notification
      on notification.id = delivery.notification_id
    join public.push_devices device on device.id = delivery.device_id
    where notification.user_id <> device.user_id
  ) then
    raise exception 'a reassigned token retained another account''s delivery';
  end if;
end;
$$;

insert into public.member_notifications (user_id, kind, title, body) values (
  '40000000-0000-4000-8000-000000000002',
  'event_updated', 'Second account update', 'Second-account content.'
);

select set_config('request.jwt.claim.role', 'service_role', true);
select delivery_id from public.claim_push_delivery_batch(10) limit 1 \gset
select set_config('test.delivery_id', :'delivery_id', true);
select public.complete_push_delivery(:'delivery_id'::bigint);

do $$
begin
  if not exists (
    select 1 from public.push_deliveries delivery
    where delivery.id = current_setting('test.delivery_id')::bigint
      and delivery.delivered_at is not null
  ) then
    raise exception 'claimed push delivery was not completed';
  end if;
end;
$$;

rollback;
