-- A privileged role must also have completed MFA in the current session.
create or replace function public._is_moderator()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and coalesce(auth.jwt()->'app_metadata'->>'role','') in ('moderator','admin')
    and coalesce(auth.jwt()->>'aal','aal1')='aal2';
$$;
revoke all on function public._is_moderator() from public,anon,authenticated;
