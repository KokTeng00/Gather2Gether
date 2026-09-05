-- Remote notifications use per-device FCM tokens and a durable, service-role
-- outbox. Mobile clients can only register or remove their own current token;
-- tokens and delivery state are never exposed through table APIs.

create table public.push_devices (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique check (char_length(token) between 20 and 4096),
  platform text not null check (platform in ('android', 'ios')),
  locale text not null default '' check (char_length(locale) <= 35),
  enabled boolean not null default true,
  last_seen_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create index push_devices_user_idx
  on public.push_devices (user_id, enabled);

create table public.push_deliveries (
  id bigint generated always as identity primary key,
  notification_id uuid not null
    references public.member_notifications(id) on delete cascade,
  device_id uuid not null references public.push_devices(id) on delete cascade,
  attempts integer not null default 0 check (attempts between 0 and 8),
  available_at timestamptz not null default pg_catalog.now(),
  claimed_at timestamptz,
  delivered_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 500),
  created_at timestamptz not null default pg_catalog.now(),
  unique (notification_id, device_id)
);

create index push_deliveries_ready_idx
  on public.push_deliveries (available_at, id)
  where delivered_at is null;

alter table public.push_devices enable row level security;
alter table public.push_deliveries enable row level security;
revoke all on table public.push_devices from anon, authenticated;
revoke all on table public.push_deliveries from anon, authenticated;
revoke all on sequence public.push_deliveries_id_seq from anon, authenticated;

create function public.register_push_device(
  p_token text,
  p_platform text,
  p_locale text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  registered_device_id uuid;
  normalized_token text := pg_catalog.btrim(p_token);
  normalized_locale text := pg_catalog.btrim(coalesce(p_locale, ''));
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if normalized_token is null
     or char_length(normalized_token) not between 20 and 4096
     or p_platform is null
     or p_platform not in ('android', 'ios')
     or char_length(normalized_locale) > 35 then
    raise exception using errcode = '22023', message = 'push_device_validation';
  end if;

  insert into public.push_devices (
    user_id, token, platform, locale, enabled, last_seen_at
  ) values (
    current_user_id, normalized_token, p_platform, normalized_locale,
    true, pg_catalog.now()
  )
  on conflict (token) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    locale = excluded.locale,
    enabled = true,
    last_seen_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  returning id into registered_device_id;

  -- A refreshed token may move to a different signed-in account on the same
  -- installation. Never let that account inherit the former owner's outbox.
  delete from public.push_deliveries delivery
  using public.member_notifications notification
  where delivery.device_id = registered_device_id
    and notification.id = delivery.notification_id
    and notification.user_id <> current_user_id;

  return registered_device_id;
end;
$$;

create function public.unregister_push_device(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.push_devices d
  where d.user_id = auth.uid() and d.token = pg_catalog.btrim(p_token);
  return found;
end;
$$;

create function public._queue_member_notification_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_deliveries (notification_id, device_id)
  select new.id, d.id
  from public.push_devices d
  where d.user_id = new.user_id and d.enabled
  on conflict do nothing;
  return new;
end;
$$;

create trigger member_notifications_queue_push
after insert on public.member_notifications
for each row execute function public._queue_member_notification_push();

create function public.enqueue_due_push_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  queued integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  insert into public.member_notifications (user_id, event_id, kind, title, body)
  select reminder.user_id, reminder.event_id, 'reminder', 'Event reminder',
    e.title || ' starts ' || pg_catalog.to_char(e.start_at, 'FMDay at HH24:MI') || '.'
  from public.event_reminders reminder
  join public.events e on e.id = reminder.event_id
  where reminder.remind_at <= pg_catalog.now()
    and e.status = 'published'
    and e.start_at > pg_catalog.now()
  on conflict do nothing;
  get diagnostics queued = row_count;
  return queued;
end;
$$;

create function public.claim_push_delivery_batch(p_limit integer default 50)
returns table (
  delivery_id bigint,
  device_token text,
  device_platform text,
  title text,
  body text,
  event_id uuid,
  attempt integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;

  delete from public.push_deliveries d
  where d.delivered_at < pg_catalog.now() - interval '7 days';
  delete from public.push_deliveries d
  using public.member_notifications n, public.push_devices p
  where n.id = d.notification_id and p.id = d.device_id
    and n.user_id <> p.user_id;
  update public.push_deliveries d
  set delivered_at = pg_catalog.now(), claimed_at = null,
    last_error = 'delivery_attempts_exhausted'
  where d.delivered_at is null and d.attempts >= 8
    and d.claimed_at < pg_catalog.now() - interval '5 minutes';

  return query
  with picked as (
    select d.id
    from public.push_deliveries d
    join public.push_devices p on p.id = d.device_id and p.enabled
    join public.member_notifications n
      on n.id = d.notification_id and n.user_id = p.user_id
    where d.delivered_at is null
      and d.available_at <= pg_catalog.now()
      and d.attempts < 8
      and (
        d.claimed_at is null
        or d.claimed_at < pg_catalog.now() - interval '5 minutes'
      )
    order by d.available_at, d.id
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    for update of d skip locked
  ), claimed as (
    update public.push_deliveries d
    set claimed_at = pg_catalog.now(), attempts = d.attempts + 1
    from picked
    where d.id = picked.id
    returning d.id, d.device_id, d.notification_id, d.attempts
  )
  select
    c.id,
    p.token,
    p.platform,
    n.title,
    n.body,
    n.event_id,
    c.attempts
  from claimed c
  join public.push_devices p on p.id = c.device_id
  join public.member_notifications n on n.id = c.notification_id
  order by c.id;
end;
$$;

create function public.complete_push_delivery(p_delivery_id bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  update public.push_deliveries d
  set delivered_at = pg_catalog.now(), claimed_at = null, last_error = null
  where d.id = p_delivery_id and d.delivered_at is null;
  return found;
end;
$$;

create function public.fail_push_delivery(
  p_delivery_id bigint,
  p_error text,
  p_retryable boolean,
  p_disable_device boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  failed_device_id uuid;
  safe_error text := pg_catalog.left(
    coalesce(nullif(pg_catalog.btrim(p_error), ''), 'push_failed'),
    500
  );
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  select d.device_id into failed_device_id
  from public.push_deliveries d
  where d.id = p_delivery_id and d.delivered_at is null
  for update;
  if not found then return false; end if;

  if p_disable_device then
    update public.push_devices d
    set enabled = false, updated_at = pg_catalog.now()
    where d.id = failed_device_id;
    update public.push_deliveries d
    set delivered_at = pg_catalog.now(), claimed_at = null, last_error = safe_error
    where d.device_id = failed_device_id and d.delivered_at is null;
    return true;
  end if;

  update public.push_deliveries d
  set
    claimed_at = null,
    last_error = safe_error,
    delivered_at = case
      when not p_retryable or d.attempts >= 8 then pg_catalog.now()
      else null
    end,
    available_at = case
      when p_retryable and d.attempts < 8 then
        pg_catalog.now() + pg_catalog.make_interval(
          secs => least(
            3600,
            (30 * pg_catalog.power(2, greatest(0, d.attempts - 1)))::integer
          )
        )
      else d.available_at
    end
  where d.id = p_delivery_id;
  return true;
end;
$$;

revoke all on function public.register_push_device(text, text, text) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
revoke all on function public._queue_member_notification_push() from public, anon, authenticated;
revoke all on function public.enqueue_due_push_reminders() from public, anon, authenticated;
revoke all on function public.claim_push_delivery_batch(integer) from public, anon, authenticated;
revoke all on function public.complete_push_delivery(bigint) from public, anon, authenticated;
revoke all on function public.fail_push_delivery(bigint, text, boolean, boolean) from public, anon, authenticated;

grant execute on function public.register_push_device(text, text, text) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;
grant execute on function public.enqueue_due_push_reminders() to service_role;
grant execute on function public.claim_push_delivery_batch(integer) to service_role;
grant execute on function public.complete_push_delivery(bigint) to service_role;
grant execute on function public.fail_push_delivery(bigint, text, boolean, boolean) to service_role;

comment on table public.push_devices is
  'Private per-installation FCM tokens, writable only through owner-scoped functions.';
comment on table public.push_deliveries is
  'At-least-once remote-notification outbox claimed only by the service-role dispatcher.';
