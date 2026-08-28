#!/usr/bin/env bash
set -euo pipefail

for required in curl jq terraform; do
  command -v "$required" >/dev/null || {
    printf 'Missing required command: %s\n' "$required" >&2
    exit 1
  }
done

: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN before running.}"

terraform_dir="${TERRAFORM_DIR:-infrastructure/terraform}"
project_ref="$(terraform -chdir="$terraform_dir" output -raw supabase_project_ref)"
project_url="https://${project_ref}.supabase.co"
edge_api_url="${EDGE_API_URL:-https://gather2gether.pages.dev/api/v1}"

health_response="$(
  curl --silent --show-error --fail-with-body "${edge_api_url}/health"
)"
if [[ "$(printf '%s' "$health_response" | jq -r '.status')" != "ok" ]]; then
  printf 'Cloudflare edge API health check failed.\n' >&2
  exit 1
fi

key_response="$(
  curl --silent --show-error --fail-with-body \
    "https://api.supabase.com/v1/projects/${project_ref}/api-keys" \
    --header "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}"
)"
publishable_key="$(printf '%s' "$key_response" | jq -r '.[] | select(.type == "publishable") | .api_key' | head -1)"
service_key="$(printf '%s' "$key_response" | jq -r '.[] | select(.name == "service_role") | .api_key' | head -1)"

if [[ -z "$publishable_key" || -z "$service_key" ]]; then
  printf 'Could not resolve Supabase test keys.\n' >&2
  exit 1
fi

run_id="$(date +%s)"
password="SmokeTest-${run_id}-A9"
organizer_email="codex-organizer-${run_id}@example.com"
attendee_email="codex-attendee-${run_id}@example.com"
organizer_id=""
attendee_id=""

cleanup() {
  for user_id in "$attendee_id" "$organizer_id"; do
    if [[ -n "$user_id" ]]; then
      curl --silent --show-error \
        --request DELETE \
        "${project_url}/auth/v1/admin/users/${user_id}" \
        --header "apikey: ${service_key}" \
        --header "Authorization: Bearer ${service_key}" >/dev/null || true
    fi
  done
}
trap cleanup EXIT

create_user() {
  local email="$1"
  local name="$2"
  local body
  body="$(jq -n \
    --arg email "$email" \
    --arg password "$password" \
    --arg name "$name" \
    '{email:$email,password:$password,email_confirm:true,user_metadata:{display_name:$name}}')"

  curl --silent --show-error --fail-with-body \
    --request POST \
    "${project_url}/auth/v1/admin/users" \
    --header "apikey: ${service_key}" \
    --header "Authorization: Bearer ${service_key}" \
    --header "Content-Type: application/json" \
    --data "$body"
}

sign_in() {
  local email="$1"
  local body
  body="$(jq -n --arg email "$email" --arg password "$password" \
    '{email:$email,password:$password}')"

  curl --silent --show-error --fail-with-body \
    --request POST \
    "${project_url}/auth/v1/token?grant_type=password" \
    --header "apikey: ${publishable_key}" \
    --header "Content-Type: application/json" \
    --data "$body" | jq -r '.access_token'
}

organizer_response="$(create_user "$organizer_email" 'Smoke Organizer')"
attendee_response="$(create_user "$attendee_email" 'Smoke Attendee')"
organizer_id="$(printf '%s' "$organizer_response" | jq -r '.id')"
attendee_id="$(printf '%s' "$attendee_response" | jq -r '.id')"
organizer_token="$(sign_in "$organizer_email")"
attendee_token="$(sign_in "$attendee_email")"

event_body="$(jq -n \
  --arg title "Smoke Event ${run_id}" \
  '{title:$title,description:"Temporary end-to-end verification event.",category:"Running",venue_name:"Test Park",address:"Test address",latitude:52.52,longitude:13.405,start_at:"2099-01-01T18:00:00Z",end_at:"2099-01-01T20:00:00Z",max_participants:2}')"
event_id="$(
  curl --silent --show-error --fail-with-body \
    --request POST \
    "${edge_api_url}/events" \
    --header "Authorization: Bearer ${organizer_token}" \
    --header "Content-Type: application/json" \
    --data "$event_body" | jq -r '.id'
)"

nearby_response="$(
  curl --silent --show-error --fail-with-body \
    --get "${edge_api_url}/events/nearby" \
    --header "Authorization: Bearer ${attendee_token}" \
    --data-urlencode 'latitude=52.52' \
    --data-urlencode 'longitude=13.405' \
    --data-urlencode 'radius_km=10'
)"

if [[ "$(printf '%s' "$nearby_response" | jq -r --arg id "$event_id" 'any(.data[]; .id == $id)')" != "true" ]]; then
  printf 'Nearby event query did not return the created event.\n' >&2
  exit 1
fi

assistant_response="$(
  curl --silent --show-error --fail-with-body \
    --max-time 25 \
    --request POST \
    "${edge_api_url}/assistant/chat" \
    --header "Authorization: Bearer ${attendee_token}" \
    --header "Content-Type: application/json" \
    --data '{"message":"Are there any running events near me?","latitude":52.52,"longitude":13.405,"radius_km":10}'
)"

if [[ -z "$(printf '%s' "$assistant_response" | jq -r '.message.content // empty')" ]]; then
  printf 'Assistant did not return an answer.\n' >&2
  exit 1
fi
if [[ "$(printf '%s' "$assistant_response" | jq -r --arg id "$event_id" 'any(.event_matches[]; .id == $id)')" != "true" ]]; then
  printf 'Assistant did not receive the indexed nearby event match.\n' >&2
  exit 1
fi

assistant_history="$(
  curl --silent --show-error --fail-with-body \
    "${edge_api_url}/assistant/history" \
    --header "Authorization: Bearer ${attendee_token}"
)"
if [[ "$(printf '%s' "$assistant_history" | jq -r '.data | length')" -lt 2 ]]; then
  printf 'Assistant history was not persisted.\n' >&2
  exit 1
fi

curl --silent --show-error --fail-with-body \
  --request DELETE \
  "${edge_api_url}/assistant/history" \
  --header "Authorization: Bearer ${attendee_token}" >/dev/null

set_rsvp() {
  local status="$1"
  local body
  body="$(jq -n --arg status "$status" \
    '{status:$status}')"
  curl --silent --show-error --fail-with-body \
    --request PUT \
    "${edge_api_url}/events/${event_id}/rsvp" \
    --header "Authorization: Bearer ${attendee_token}" \
    --header "Content-Type: application/json" \
    --data "$body" >/dev/null
}

set_rsvp tentative
set_rsvp joined

details_response="$(
  curl --silent --show-error --fail-with-body \
    "${edge_api_url}/events/${event_id}" \
    --header "Authorization: Bearer ${attendee_token}"
)"

if [[ "$(printf '%s' "$details_response" | jq -r '.data.joined_count')" != "2" ]]; then
  printf 'RSVP capacity count was not updated atomically.\n' >&2
  exit 1
fi

curl --silent --show-error --fail-with-body \
  --request POST \
  "${edge_api_url}/events/${event_id}/report" \
  --header "Authorization: Bearer ${attendee_token}" \
  --header "Content-Type: application/json" \
  --data '{"reason":"other"}' >/dev/null

anonymous_status="$(
  curl --silent --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${project_url}/rest/v1/profiles?select=id" \
    --header "apikey: ${publishable_key}"
)"
if [[ "$anonymous_status" == "200" ]]; then
  printf 'Anonymous profile access was unexpectedly allowed.\n' >&2
  exit 1
fi

printf 'Smoke test passed: Cloudflare compute, private model Worker, Supabase auth/database, indexed assistant search/history, create, nearby, report, RSVP capacity, and RLS.\n'
