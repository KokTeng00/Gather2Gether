const MAX_BODY_BYTES = 32 * 1024;
const MAX_MEDIA_BYTES = 5 * 1024 * 1024;
const MAX_PLACE_RESPONSE_BYTES = 128 * 1024;
const ASSISTANT_HISTORY_LIMIT = 24;
const RECOMMENDATION_RERANK_LIMIT = 24;
// Keep declared interests and practical suitability stronger than the optional
// semantic reranker, particularly when only one deliberate choice is available.
const RECOMMENDATION_AI_WEIGHT = 0.4;
const COMMUNITY_FEED_LIMIT = 30;
const COMMUNITY_RECOMMENDATION_BLOCK = 3;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REPORT_REASONS = new Set([
  'spam',
  'unsafe_behaviour',
  'inappropriate_content',
  'misleading',
  'other',
]);
const FORUM_REPORT_REASONS = new Set([
  'spam',
  'harassment',
  'unsafe_behaviour',
  'personal_information',
  'inappropriate_content',
  'other',
]);
const FORUM_CATEGORIES = new Set([
  'General',
  'Looking for group',
  'Local tips',
  'Event ideas',
  'Safety',
]);
const RSVP_STATUSES = new Set(['joined', 'tentative', 'cancelled']);
const EVENT_PLAN_FILTERS = new Set(['going', 'tentative', 'hosting', 'drafts', 'past', 'saved']);
const PROFILE_EVENT_FILTERS = new Set(['hosting', 'past']);
const EVENT_DATE_FILTERS = new Set(['any', 'today', 'tomorrow', 'weekend']);
const EVENT_TIME_FILTERS = new Set(['any', 'morning', 'afternoon', 'evening']);
const EVENT_SETTINGS = new Set(['unspecified', 'indoor', 'outdoor', 'mixed']);
const EVENT_AGE_GUIDANCE = new Set(['all_ages', 'families', 'teens', 'adults']);
const EVENT_SETTING_FILTERS = new Set(['any', 'indoor', 'outdoor', 'mixed']);
const EVENT_AGE_FILTERS = new Set(['any', ...EVENT_AGE_GUIDANCE]);
const EVENT_STATUSES = new Set(['draft', 'published']);
const EVENT_VISIBILITIES = new Set(['public', 'unlisted', 'followers', 'following', 'selected']);
const EVENT_REPEAT_INTERVALS = new Set(['none', 'weekly', 'monthly']);
const PUSH_PLATFORMS = new Set(['android', 'ios']);
const SERIES_SCOPES = new Set(['this', 'future', 'all']);
const ATTENDANCE_STATUSES = new Set(['joined', 'attended', 'no_show']);
const MODERATION_STATUSES = new Set(['open', 'reviewing', 'resolved', 'dismissed', 'all']);
const MODERATION_ACTIONS = new Set(['reviewing', 'resolved', 'dismissed', 'hidden']);
const MODERATION_REPORT_KINDS = new Set([
  'event',
  'forum_post',
  'forum_comment',
  'discussion',
]);
const ACCESSIBILITY_PREFERENCES = new Set([
  'wheelchair_accessible',
  'beginner_friendly',
  'quiet_space',
  'step_free_access',
  'accessible_toilet',
  'hearing_support',
]);
const EVENT_CATEGORIES = new Set([
  'Badminton',
  'Running',
  'Padel',
  'Hiking',
  'Coffee',
  'Board Games',
  'Language Exchange',
  'Photography',
  'Startup',
  'Cycling',
  'Other',
]);

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export async function onRequest(context) {
  const startedAt = Date.now();
  const response = await handleApiRequest(
    context.request,
    context.env,
    (task) => context.waitUntil(task),
  );
  const url = new URL(context.request.url);
  console.log(JSON.stringify({
    event: 'request_complete',
    method: context.request.method,
    path: url.pathname,
    status: response.status,
    duration_ms: Date.now() - startedAt,
    request_id: response.headers.get('X-Request-Id'),
  }));
  return response;
}

export async function handleApiRequest(request, env, defer = null) {
  const requestId = crypto.randomUUID();
  const cors = {};

  try {
    if (request.headers.get('Origin')) {
      throw new ApiError(403, 'browser_not_supported', 'Browser access is not supported.');
    }
    if (request.method === 'OPTIONS') {
      throw new ApiError(405, 'method_not_allowed', 'Method is not allowed.');
    }

    const url = new URL(request.url);
    const segments = routeSegments(url.pathname);

    if (request.method === 'GET' && segments.length === 1 && segments[0] === 'health') {
      return jsonResponse(
        {status: 'ok', service: 'gather2gether-edge-api', version: 2},
        200,
        requestId,
        cors,
      );
    }

    assertEnvironment(env);
    const identity = await authenticate(request, env);

    if (segments.join('/') === 'onboarding' && request.method === 'POST') {
      const input = validateOnboarding(await jsonBody(request));
      const completed = await supabaseRpc(
        env,
        identity.authorization,
        'complete_onboarding',
        input,
      );
      return jsonResponse({completed: completed === true}, 200, requestId, cors);
    }

    if (segments.join('/') === 'notification-preferences') {
      if (request.method === 'GET') {
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_notification_preferences',
          {},
        );
        if (!Array.isArray(rows) || rows.length !== 1) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid notification preferences.');
        }
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }
      if (request.method === 'PUT') {
        const input = validateNotificationPreferences(await jsonBody(request));
        await supabaseRpc(
          env,
          identity.authorization,
          'update_notification_preferences',
          input,
        );
        return jsonResponse({updated: true}, 200, requestId, cors);
      }
    }

    if (segments.join('/') === 'recommendations/preferences') {
      if (request.method === 'GET') {
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_recommendation_preferences',
          {},
        );
        if (!Array.isArray(rows) || rows.length !== 1) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid recommendation preferences.');
        }
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }
      if (request.method === 'PUT') {
        const input = validateRecommendationPreferences(await jsonBody(request));
        await supabaseRpc(
          env,
          identity.authorization,
          'update_recommendation_preferences',
          input,
        );
        return jsonResponse({updated: true}, 200, requestId, cors);
      }
      if (request.method === 'DELETE') {
        await supabaseRpc(
          env,
          identity.authorization,
          'reset_recommendation_controls',
          {},
        );
        return jsonResponse({reset: true}, 200, requestId, cors);
      }
    }

    if (segments.join('/') === 'recommendations/hide' && request.method === 'POST') {
      const body = await jsonBody(request);
      exactKeys(body, ['content_kind', 'content_id']);
      const kind = stringParameter(body.content_kind, 'content_kind', 5, 20);
      if (kind !== 'event' && kind !== 'forum_post') {
        throw new ApiError(400, 'recommendation_validation', 'Recommendation target is invalid.');
      }
      await supabaseRpc(
        env,
        identity.authorization,
        'hide_recommendation',
        {
          p_content_kind: kind,
          p_content_id: uuidParameter(body.content_id, 'content_id'),
        },
      );
      return jsonResponse({hidden: true}, 200, requestId, cors);
    }

    if (segments.join('/') === 'reports/mine' && request.method === 'GET') {
      const reports = await supabaseRpc(
        env,
        identity.authorization,
        'list_my_reports',
        {},
      );
      if (!Array.isArray(reports)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid report data.');
      }
      return jsonResponse({data: reports}, 200, requestId, cors);
    }

    if (segments.join('/') === 'account/export' && request.method === 'GET') {
      const data = await supabaseRpc(
        env,
        identity.authorization,
        'export_own_data',
        {},
      );
      if (!data || Array.isArray(data) || typeof data !== 'object') {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid export data.');
      }
      return jsonResponse({data}, 200, requestId, cors);
    }

    if (segments.join('/') === 'moderation/status' && request.method === 'GET') {
      const moderator = await supabaseRpc(
        env,
        identity.authorization,
        'get_moderation_status',
        {},
      );
      return jsonResponse({moderator: moderator === true}, 200, requestId, cors);
    }

    if (segments.join('/') === 'moderation/overview' && request.method === 'GET') {
      const data = await supabaseRpc(
        env,
        identity.authorization,
        'moderation_overview',
        {},
      );
      if (!data || Array.isArray(data) || typeof data !== 'object') {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid moderation data.');
      }
      return jsonResponse({data}, 200, requestId, cors);
    }

    if (segments.join('/') === 'moderation/reports' && request.method === 'GET') {
      const status = url.searchParams.get('status') ?? 'open';
      if (!MODERATION_STATUSES.has(status)) {
        throw new ApiError(400, 'moderation_status_validation', 'Moderation status is invalid.');
      }
      const reports = await supabaseRpc(
        env,
        identity.authorization,
        'list_moderation_reports',
        {p_status: status},
      );
      if (!Array.isArray(reports)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid moderation reports.');
      }
      return jsonResponse({data: reports}, 200, requestId, cors);
    }

    if (segments.join('/') === 'moderation/action' && request.method === 'POST') {
      const body = await jsonBody(request);
      exactKeys(body, ['report_kind', 'report_id', 'action', 'note']);
      const reportKind = stringParameter(body.report_kind, 'report_kind', 5, 20);
      const action = stringParameter(body.action, 'action', 6, 20);
      if (!MODERATION_REPORT_KINDS.has(reportKind) || !MODERATION_ACTIONS.has(action)) {
        throw new ApiError(400, 'moderation_action_validation', 'Moderation action is invalid.');
      }
      await supabaseRpc(
        env,
        identity.authorization,
        'moderate_report',
        {
          p_report_kind: reportKind,
          p_report_id: uuidParameter(body.report_id, 'report_id'),
          p_action: action,
          p_note: optionalStringWithDefault(body.note, 'note', 1000),
        },
      );
      return jsonResponse({updated: true}, 200, requestId, cors);
    }

    if (segments.join('/') === 'moderation/triage' && request.method === 'POST') {
      const reports = await supabaseRpc(
        env,
        identity.authorization,
        'list_moderation_reports',
        {p_status: 'open'},
      );
      if (!Array.isArray(reports) || reports.length === 0) {
        throw new ApiError(409, 'triage_unavailable', 'There are no open reports to triage.');
      }
      await claimAssistantTool(env, identity.authorization, 'moderation_triage');
      const result = await callAssistantTool(env, 'moderation-triage', {
        reports: reports.slice(0, 50).map((report) => ({
          report_id: report.report_id,
          kind: report.report_kind,
          reason: report.reason,
          title: report.target_title,
          excerpt: report.excerpt,
        })),
      });
      if (!validModerationTriage(result, reports)) {
        throw new ApiError(502, 'invalid_model_response', 'The assistant returned invalid moderation priorities.');
      }
      return jsonResponse({data: result.priorities}, 200, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'notifications') {
      await supabaseRpc(
        env,
        identity.authorization,
        'process_due_event_reconfirmations',
        {},
      );
      const notifications = await supabaseRpc(
        env,
        identity.authorization,
        'list_member_notifications',
        {},
      );
      if (!Array.isArray(notifications)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid notification data.');
      }
      return jsonResponse({data: notifications}, 200, requestId, cors);
    }

    if (request.method === 'PUT' && segments.join('/') === 'notifications/read-all') {
      await supabaseRpc(
        env,
        identity.authorization,
        'mark_all_member_notifications_read',
        {},
      );
      return jsonResponse({read: true}, 200, requestId, cors);
    }

    if (
      (request.method === 'PUT' || request.method === 'DELETE') &&
      segments.join('/') === 'push/devices'
    ) {
      const body = await jsonBody(request);
      if (request.method === 'PUT') {
        exactKeys(body, ['token', 'platform', 'locale']);
        const token = stringParameter(body.token, 'token', 20, 4096);
        const platform = stringParameter(body.platform, 'platform', 2, 12);
        if (!PUSH_PLATFORMS.has(platform)) {
          throw new ApiError(400, 'push_device_validation', 'Notification device details are invalid.');
        }
        const locale = stringParameter(body.locale, 'locale', 2, 35);
        const id = await supabaseRpc(
          env,
          identity.authorization,
          'register_push_device',
          {p_token: token, p_platform: platform, p_locale: locale},
        );
        if (typeof id !== 'string' || !UUID_PATTERN.test(id)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid device identifier.');
        }
        return jsonResponse({registered: true}, 200, requestId, cors);
      }
      if (request.method === 'DELETE') {
        exactKeys(body, ['token']);
        const token = stringParameter(body.token, 'token', 20, 4096);
        const removed = await supabaseRpc(
          env,
          identity.authorization,
          'unregister_push_device',
          {p_token: token},
        );
        return jsonResponse({removed: removed === true}, 200, requestId, cors);
      }
    }

    if (request.method === 'GET' && segments.join('/') === 'blocks') {
      const profiles = await supabaseRpc(
        env,
        identity.authorization,
        'list_blocked_profiles',
        {},
      );
      if (!Array.isArray(profiles)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid blocked-profile data.');
      }
      return jsonResponse({data: profiles}, 200, requestId, cors);
    }

    if (request.method === 'DELETE' && segments.join('/') === 'account') {
      assertMediaEnvironment(env);
      const body = await jsonBody(request);
      exactKeys(body, ['confirmation']);
      if (body.confirmation !== 'DELETE') {
        throw new ApiError(400, 'account_deletion_confirmation', 'Type DELETE to confirm account deletion.');
      }
      const deletedMedia = await supabaseRpc(
        env,
        identity.authorization,
        'delete_own_account',
        {p_confirmation: body.confirmation},
      );
      if (!deletedMedia || Array.isArray(deletedMedia) || typeof deletedMedia !== 'object') {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid account-deletion data.');
      }
      const keys = [
        deletedMedia.avatar_image_key,
        ...(Array.isArray(deletedMedia.forum_image_keys)
          ? deletedMedia.forum_image_keys
          : []),
        ...(Array.isArray(deletedMedia.event_image_keys) ? deletedMedia.event_image_keys : []),
        `staging/events/${identity.userId}/current.jpg`,
        `staging/forum/${identity.userId}/current.jpg`,
      ].filter((key) =>
        key === `staging/forum/${identity.userId}/current.jpg` ||
        isOwnedMediaKey(key, 'avatars', identity.userId) ||
        isOwnedMediaKey(key, 'posts', identity.userId) ||
        isOwnedMediaKey(key, 'events', identity.userId) || key === `staging/events/${identity.userId}/current.jpg`
      );
      await Promise.all([...new Set(keys)].map((key) =>
        deleteMediaObject(env.USER_MEDIA, key)
      ));
      return jsonResponse({deleted: true}, 200, requestId, cors);
    }

    if (segments.join('/') === 'event-searches') {
      if (request.method === 'GET') {
        const searches = await supabaseRpc(
          env,
          identity.authorization,
          url.searchParams.get('planning') === '1' ? 'list_saved_event_search_plans' : 'list_saved_event_searches',
          {},
        );
        if (!Array.isArray(searches)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid saved search data.');
        }
        return jsonResponse({data: searches}, 200, requestId, cors);
      }
      if (request.method === 'POST') {
        const body = await jsonBody(request);
        if (body.planning !== undefined) {
          const {planning, ...fields} = body;
          const context = validateSearchContext(planning, fields.date_filter);
          const input = validateSavedEventSearch({...fields, date_filter: fields.date_filter === 'custom' ? 'any' : fields.date_filter});
          const id = await supabaseRpc(env, identity.authorization, 'save_event_search_plan', {p_search_id: null, p_input: input, p_context: context});
          return jsonResponse({id}, 201, requestId, cors);
        }
        const input = validateSavedEventSearch(body);
        const id = await supabaseRpc(
          env,
          identity.authorization,
          'create_saved_event_search',
          input,
        );
        if (typeof id !== 'string' || !UUID_PATTERN.test(id)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid saved search identifier.');
        }
        return jsonResponse({id}, 201, requestId, cors);
      }
    }

    if (
      (request.method === 'PUT' || request.method === 'DELETE') &&
      segments.length === 2 &&
      segments[0] === 'event-searches'
    ) {
      const searchId = uuidParameter(segments[1], 'search_id');
      if (request.method === 'PUT') {
        const body = await jsonBody(request);
        if (body.planning !== undefined) {
          const {planning, ...fields} = body;
          const context = validateSearchContext(planning, fields.date_filter);
          const input = validateSavedEventSearch({...fields, date_filter: fields.date_filter === 'custom' ? 'any' : fields.date_filter});
          await supabaseRpc(env, identity.authorization, 'save_event_search_plan', {p_search_id: searchId, p_input: input, p_context: context});
          return jsonResponse({updated: true}, 200, requestId, cors);
        }
        const input = validateSavedEventSearch(body);
        const updated = await supabaseRpc(
          env,
          identity.authorization,
          'update_saved_event_search',
          {p_search_id: searchId, ...input},
        );
        return jsonResponse({updated: updated === true}, 200, requestId, cors);
      }
      const deleted = await supabaseRpc(
        env,
        identity.authorization,
        'delete_saved_event_search',
        {p_search_id: searchId},
      );
      return jsonResponse({deleted: deleted === true}, 200, requestId, cors);
    }

    if (
      request.method === 'PUT' && segments.length === 3 &&
      segments[0] === 'notifications' && segments[2] === 'read'
    ) {
      const notificationId = uuidParameter(segments[1], 'notification_id');
      const read = await supabaseRpc(
        env,
        identity.authorization,
        'mark_member_notification_read',
        {p_notification_id: notificationId},
      );
      return jsonResponse({read: read === true}, 200, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'places/autocomplete') {
      assertPlaceEnvironment(env);
      const text = stringParameter(url.searchParams.get('text'), 'text', 3, 160);
      const latitude = nullableQueryNumberParameter(
        url.searchParams.get('latitude'),
        'latitude',
        -90,
        90,
      );
      const longitude = nullableQueryNumberParameter(
        url.searchParams.get('longitude'),
        'longitude',
        -180,
        180,
      );
      if ((latitude === null) !== (longitude === null)) {
        throw new ApiError(400, 'invalid_parameter', 'Location bias is invalid.');
      }
      const language = languageParameter(url.searchParams.get('language'));
      const places = await geoapifyAutocomplete(env, {
        text,
        latitude,
        longitude,
        language,
      });
      return jsonResponse({data: places}, 200, requestId, cors);
    }

    if (segments.join('/') === 'profile/avatar') {
      assertMediaEnvironment(env);

      if (request.method === 'GET') {
        const imageKey = await supabaseRpc(
          env,
          identity.authorization,
          'get_own_profile_avatar_image_key',
          {},
        );
        if (imageKey === null) {
          throw new ApiError(404, 'profile_avatar_not_found', 'Profile photo was not found.');
        }
        if (!isOwnedMediaKey(imageKey, 'avatars', identity.userId)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid media reference.');
        }
        const object = await getMediaObject(env.USER_MEDIA, imageKey);
        if (object === null) {
          throw new ApiError(404, 'profile_avatar_not_found', 'Profile photo was not found.');
        }
        return mediaResponse(object, requestId, cors);
      }

      if (request.method === 'POST') {
        const imageKey = `avatars/${identity.userId}/${crypto.randomUUID()}.jpg`;
        await putUploadedJpeg(env.USER_MEDIA, imageKey, request, {
          owner: identity.userId,
          purpose: 'profile-avatar',
        });

        let oldImageKey;
        try {
          oldImageKey = await supabaseRpc(
            env,
            identity.authorization,
            'set_profile_avatar',
            {p_image_key: imageKey},
          );
          if (
            oldImageKey !== null &&
            !isOwnedMediaKey(oldImageKey, 'avatars', identity.userId)
          ) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid media reference.');
          }
        } catch (error) {
          if (isDefiniteClientRejection(error)) {
            await deleteMediaObject(env.USER_MEDIA, imageKey);
          }
          throw error;
        }
        if (oldImageKey !== null && oldImageKey !== imageKey) {
          await deleteMediaObject(env.USER_MEDIA, oldImageKey);
        }
        return jsonResponse({updated: true}, 200, requestId, cors);
      }

      if (request.method === 'DELETE') {
        const oldImageKey = await supabaseRpc(
          env,
          identity.authorization,
          'set_profile_avatar',
          {p_image_key: null},
        );
        if (
          oldImageKey !== null &&
          !isOwnedMediaKey(oldImageKey, 'avatars', identity.userId)
        ) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid media reference.');
        }
        if (oldImageKey !== null) {
          await deleteMediaObject(env.USER_MEDIA, oldImageKey);
        }
        return jsonResponse({deleted: oldImageKey !== null}, 200, requestId, cors);
      }
    }

    if (segments.length >= 2 && segments[0] === 'profiles') {
      const profileId = segments[1] === 'me'
        ? identity.userId
        : uuidParameter(segments[1], 'profile_id');

      if (request.method === 'GET' && segments.length === 3 &&
          (segments[2] === 'followers' || segments[2] === 'following')) {
        const query = optionalSearchParameter(url.searchParams.get('query'), 'query', 80);
        const canSearch = profileId.toLowerCase() === identity.userId.toLowerCase();
        if (query !== null && !canSearch) {
          throw new ApiError(403, 'connection_search_owner_only', 'Only the account owner can search this list.');
        }
        let cursor = null;
        const rawCursor = url.searchParams.get('cursor');
        if (rawCursor !== null) {
          try {
            if (rawCursor.length > 200) throw new Error('cursor length');
            cursor = JSON.parse(rawCursor);
            if (!cursor || typeof cursor.id !== 'string' || !UUID_PATTERN.test(cursor.id) ||
                typeof cursor.created_at !== 'string' || cursor.created_at.length > 40 ||
                !Number.isFinite(Date.parse(cursor.created_at))) throw new Error('cursor shape');
          } catch (_) {
            throw new ApiError(400, 'invalid_cursor', 'This list position is invalid. Refresh the list.');
          }
        }
        const rows = await supabaseRpc(env, identity.authorization, 'list_profile_connections', {
          p_profile_id: profileId,
          p_kind: segments[2],
          p_query: query,
          // Preserve database timestamp precision for stable pagination.
          p_before_created_at: cursor?.created_at ?? null,
          p_before_id: cursor?.id ?? null,
          p_limit: 31,
        });
        if (!Array.isArray(rows) || rows.length > 31) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid member list.');
        }
        const data = rows.slice(0, 30);
        const last = data.at(-1);
        return jsonResponse({
          data,
          can_search: canSearch,
          next_cursor: rows.length > 30
            ? JSON.stringify({created_at: last.followed_at, id: last.id})
            : null,
        }, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 2) {
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_public_profile',
          {p_profile_id: profileId},
        );
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'profile_not_found', 'Profile was not found.');
        }
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 3 && segments[2] === 'events') {
        const filter = url.searchParams.get('filter') ?? 'hosting';
        if (!PROFILE_EVENT_FILTERS.has(filter)) {
          throw new ApiError(
            400,
            'invalid_profile_event_filter',
            'Profile event filter is invalid.',
          );
        }
        const events = await supabaseRpc(
          env,
          identity.authorization,
          'list_profile_events',
          {p_profile_id: profileId, p_filter: filter},
        );
        if (!Array.isArray(events)) {
          throw new ApiError(
            502,
            'invalid_backend_response',
            'The database returned invalid profile event data.',
          );
        }
        return jsonResponse({data: events}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 3 && segments[2] === 'avatar') {
        assertMediaEnvironment(env);
        const imageKey = await supabaseRpc(
          env,
          identity.authorization,
          'get_public_profile_avatar_image_key',
          {p_profile_id: profileId},
        );
        if (imageKey === null) {
          throw new ApiError(404, 'profile_avatar_not_found', 'Profile photo was not found.');
        }
        if (!isOwnedMediaKey(imageKey, 'avatars', profileId)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid media reference.');
        }
        const object = await getMediaObject(env.USER_MEDIA, imageKey);
        if (object === null) {
          throw new ApiError(404, 'profile_avatar_not_found', 'Profile photo was not found.');
        }
        return mediaResponse(object, requestId, cors);
      }

      if (
        (request.method === 'PUT' || request.method === 'DELETE') &&
        segments.length === 3 &&
        segments[2] === 'follow'
      ) {
        const following = request.method === 'PUT';
        await supabaseRpc(
          env,
          identity.authorization,
          'set_profile_follow',
          {p_profile_id: profileId, p_following: following},
        );
        return jsonResponse({following}, 200, requestId, cors);
      }

      if (
        (request.method === 'PUT' || request.method === 'DELETE') &&
        segments.length === 3 &&
        segments[2] === 'block'
      ) {
        const blocked = request.method === 'PUT';
        const saved = await supabaseRpc(
          env,
          identity.authorization,
          'set_profile_block',
          {p_profile_id: profileId, p_blocked: blocked},
        );
        return jsonResponse({blocked: saved === true}, 200, requestId, cors);
      }
    }

    if (request.method === 'GET' && segments.join('/') === 'assistant/history') {
      const messages = await supabaseRpc(
        env,
        identity.authorization,
        'list_assistant_messages',
        {p_limit: 50},
      );
      if (!Array.isArray(messages)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid assistant history.');
      }
      return jsonResponse({data: messages}, 200, requestId, cors);
    }

    if (request.method === 'DELETE' && segments.join('/') === 'assistant/history') {
      await supabaseRpc(
        env,
        identity.authorization,
        'clear_assistant_history',
        {},
      );
      return jsonResponse({cleared: true}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'assistant/chat') {
      const input = validateAssistantChat(await jsonBody(request));
      const userMessageId = await supabaseRpc(
        env,
        identity.authorization,
        'begin_assistant_turn',
        {p_message: input.message},
      );
      if (!Number.isInteger(userMessageId) || userMessageId < 1) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid message identifier.');
      }

      try {
        const search = assistantEventSearch(input.message);
        const eventPromise = search.shouldSearch && input.latitude !== null
          ? supabaseRpc(
            env,
            identity.authorization,
            'search_nearby_events',
            {
              p_latitude: input.latitude,
              p_longitude: input.longitude,
              p_radius_km: input.radiusKm,
              p_query: search.query,
              p_limit: 8,
            },
          )
          : Promise.resolve([]);
        const [history, eventMatches] = await Promise.all([
          supabaseRpc(
            env,
            identity.authorization,
            'list_assistant_messages',
            {p_limit: ASSISTANT_HISTORY_LIMIT},
          ),
          eventPromise,
        ]);
        if (!Array.isArray(history) || !Array.isArray(eventMatches)) {
          throw new ApiError(502, 'invalid_backend_response', 'The assistant received invalid context.');
        }

        const answer = await openRouterChat({
          env,
          history,
          eventMatches,
          eventSearchRequested: search.shouldSearch,
          locationAvailable: input.latitude !== null,
        });
        const assistantMessageId = await supabaseRpc(
          env,
          identity.authorization,
          'finish_assistant_turn',
          {p_user_message_id: userMessageId, p_message: answer},
        );
        if (!Number.isInteger(assistantMessageId) || assistantMessageId < 1) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid message identifier.');
        }
        return jsonResponse(
          {
            message: {
              id: assistantMessageId,
              role: 'assistant',
              content: answer,
              created_at: new Date().toISOString(),
            },
            event_matches: eventMatches,
          },
          200,
          requestId,
          cors,
        );
      } catch (error) {
        try {
          await supabaseRpc(
            env,
            identity.authorization,
            'discard_assistant_turn',
            {p_user_message_id: userMessageId},
          );
        } catch (_) {
          // The original safe error is more useful than cleanup failure details.
        }
        throw error;
      }
    }

    if (request.method === 'POST' && segments.join('/') === 'assistant/event-draft') {
      const input = validateAssistantEventDraft(await jsonBody(request));
      await claimAssistantTool(env, identity.authorization, 'event_draft');
      const draft = await callAssistantTool(env, 'event-draft', input);
      if (!validAssistantEventDraft(draft)) {
        throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid event draft.');
      }
      return jsonResponse({draft}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'assistant/event-filters') {
      const body = await jsonBody(request);
      exactKeys(body, ['query', 'locale']);
      const input = {
        query: stringParameter(body.query, 'query', 3, 500),
        locale: stringParameter(body.locale, 'locale', 2, 35),
      };
      await claimAssistantTool(env, identity.authorization, 'natural_filters');
      const filters = await callAssistantTool(env, 'event-filters', input);
      if (!validNaturalEventFilters(filters)) {
        throw new ApiError(502, 'invalid_model_response', 'The assistant returned invalid event filters.');
      }
      return jsonResponse({filters}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'assistant/event-quality') {
      const event = validateEventQualityInput(await jsonBody(request));
      await claimAssistantTool(env, identity.authorization, 'event_quality');
      const quality = await callAssistantTool(env, 'event-quality', {event});
      if (!validEventQuality(quality)) {
        throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid event review.');
      }
      return jsonResponse({quality}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'forum/media') {
      assertMediaEnvironment(env);
      const token = crypto.randomUUID();
      const imageKey = `staging/forum/${identity.userId}/current.jpg`;
      await putUploadedJpeg(env.USER_MEDIA, imageKey, request, {
        owner: identity.userId,
        purpose: 'forum-staging',
        token,
      });
      return jsonResponse({token}, 201, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'forum/posts/mine') {
      const posts = await supabaseRpc(
        env,
        identity.authorization,
        'list_own_forum_posts',
        {p_limit: 30, p_before: null},
      );
      if (!Array.isArray(posts)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid forum data.');
      }
      return jsonResponse({data: posts}, 200, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'forum/posts') {
      const scope = url.searchParams.get('scope');
      if (scope !== null && scope !== 'mine') {
        throw new ApiError(400, 'invalid_parameter', 'scope is invalid.');
      }
      const interest = optionalSearchParameter(url.searchParams.get('interest'), 'interest', 240);
      if (scope === 'mine' && interest !== null) {
        throw new ApiError(400, 'invalid_parameter', 'interest is unavailable for your own posts.');
      }
      const embedding = interest === null
        ? null
        : await generateEmbedding(env, identity.authorization, interest);
      const isDefaultFeed = scope === null && embedding === null;
      let recommendationPreferences = {enabled: true, hidden_categories: []};
      let hiddenPostIds = new Set();
      if (scope === null) {
        const [preferenceRows, hiddenIds] = await Promise.all([
          supabaseRpc(
            env,
            identity.authorization,
            'get_recommendation_preferences',
            {},
          ),
          supabaseRpc(
            env,
            identity.authorization,
            'list_hidden_recommendation_ids',
            {p_content_kind: 'forum_post'},
          ),
        ]);
        if (!Array.isArray(preferenceRows) || preferenceRows.length !== 1 ||
          !Array.isArray(hiddenIds)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid recommendation controls.');
        }
        recommendationPreferences = preferenceRows[0];
        hiddenPostIds = new Set(hiddenIds);
      }
      const recommendationsEnabled = recommendationPreferences?.enabled !== false;
      const [posts, latestPosts] = await Promise.all([
        supabaseRpc(
          env,
          identity.authorization,
          scope === 'mine'
            ? 'list_own_forum_posts'
            : embedding === null
              ? recommendationsEnabled
                ? 'recommend_personalized_forum_posts'
                : 'list_forum_posts'
              : 'recommend_forum_posts_v2',
          embedding === null
            ? {p_limit: 30, p_before: null}
            : {
                p_query_embedding: embedding,
                p_query: interest,
                p_limit: 30,
              },
        ),
        isDefaultFeed && recommendationsEnabled
          ? supabaseRpc(
              env,
              identity.authorization,
              'list_forum_posts',
              {p_limit: 30, p_before: null},
            )
          : Promise.resolve(null),
      ]);
      if (!Array.isArray(posts)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid forum data.');
      }
      if (latestPosts !== null && !Array.isArray(latestPosts)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid latest forum data.');
      }
      const hiddenCategories = new Set(
        Array.isArray(recommendationPreferences?.hidden_categories)
          ? recommendationPreferences.hidden_categories.filter((value) => typeof value === 'string')
          : [],
      );
      const visiblePosts = posts.filter((post) =>
        typeof post?.id === 'string' && !hiddenPostIds.has(post.id) &&
        (typeof post?.category !== 'string' || !hiddenCategories.has(post.category))
      );
      const visibleLatestPosts = Array.isArray(latestPosts)
        ? latestPosts.filter((post) =>
            typeof post?.id === 'string' && !hiddenPostIds.has(post.id) &&
            (typeof post?.category !== 'string' || !hiddenCategories.has(post.category))
          )
        : latestPosts;
      const personalizedPosts = isDefaultFeed
        ? !recommendationsEnabled
          ? visiblePosts
          : await rerankRecommendations({
            env,
            authorization: identity.authorization,
            surface: 'forum_post',
            candidates: visiblePosts,
            defer,
          })
        : visiblePosts;
      const rankedPosts = isDefaultFeed && recommendationsEnabled
        ? interleaveCommunityFeed(personalizedPosts, visibleLatestPosts)
        : personalizedPosts;
      const data = url.searchParams.get('planning') === '1'
        ? await enrichForumPolls(env, identity.authorization, rankedPosts) : rankedPosts;
      return jsonResponse({data}, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'forum/posts') {
      const input = validateCreateForumPost(await jsonBody(request));
      let imageKey = null;
      if (input.imageToken !== null) {
        assertMediaEnvironment(env);
        const stagingKey = `staging/forum/${identity.userId}/current.jpg`;
        const staged = await getMediaObject(env.USER_MEDIA, stagingKey);
        if (
          staged === null ||
          staged.customMetadata?.owner !== identity.userId ||
          staged.customMetadata?.purpose !== 'forum-staging' ||
          staged.customMetadata?.token !== input.imageToken ||
          !Number.isInteger(staged.size) ||
          staged.size < 4 ||
          staged.size > MAX_MEDIA_BYTES
        ) {
          throw new ApiError(400, 'invalid_image_token', 'The selected image is unavailable. Upload it again.');
        }
        imageKey = `posts/${identity.userId}/${crypto.randomUUID()}.jpg`;
        await putMediaObject(env.USER_MEDIA, imageKey, staged.body, {
          owner: identity.userId,
          purpose: 'forum-post',
        }, staged.size);
        // Keep the single bounded staging object. Deleting it here could erase a
        // newer draft that concurrently overwrote current.jpg after this GET.
      }

      try {
        const postId = await supabaseRpc(
          env,
          identity.authorization,
          input.pollOptions === null ? 'create_forum_post' : 'create_forum_post_with_poll',
          {
            ...(input.pollOptions === null ? {} : {p_options: input.pollOptions}),
            p_title: input.title,
            p_body: input.body,
            p_category: input.category,
            p_image_key: imageKey,
            p_place_name: input.placeName,
            p_place_address: input.placeAddress,
          },
        );
        if (typeof postId !== 'string' || !UUID_PATTERN.test(postId)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid post identifier.');
        }
        defer?.(
          indexCreatedContent({
            env,
            authorization: identity.authorization,
            rpc: 'set_forum_post_embedding',
            idField: 'p_post_id',
            id: postId,
            input: semanticDocument({
              Title: input.title,
              Topic: input.category,
              Place: input.placeName,
              Address: input.placeAddress,
              Description: input.body,
            }),
          }),
        );
        return jsonResponse({id: postId}, 201, requestId, cors);
      } catch (error) {
        // A 5xx/fetch failure is commit-ambiguous: keep the final object because
        // PostgreSQL may have committed the row before the response was lost.
        if (imageKey !== null && isDefiniteClientRejection(error)) {
          await deleteMediaObject(env.USER_MEDIA, imageKey);
        }
        throw error;
      }
    }

    if (segments.length >= 3 && segments[0] === 'forum' && segments[1] === 'posts') {
      const postId = uuidParameter(segments[2], 'post_id');

      if (request.method === 'GET' && segments.length === 4 && segments[3] === 'poll') {
        const data = await supabaseRpc(env, identity.authorization, 'get_forum_poll', {p_post_id: postId});
        return jsonResponse({data}, 200, requestId, cors);
      }
      if (request.method === 'PUT' && segments.length === 5 && segments[3] === 'poll') {
        const body = await jsonBody(request);
        exactKeys(body, ['available']);
        if (typeof body.available !== 'boolean') throw new ApiError(400, 'poll_validation', 'Choose your availability.');
        const data = await supabaseRpc(env, identity.authorization, 'set_forum_poll_vote', {
          p_post_id: postId, p_option_id: uuidParameter(segments[4], 'option_id'), p_available: body.available,
        });
        return jsonResponse({data}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 3) {
        const [rows, likeState] = await Promise.all([
          supabaseRpc(
            env,
            identity.authorization,
            'get_forum_post',
            {p_post_id: postId},
          ),
          supabaseRpc(
            env,
            identity.authorization,
            'get_forum_post_like_state',
            {p_post_id: postId},
          ),
        ]);
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'forum_post_not_found', 'Discussion was not found.');
        }
        if (!likeState || typeof likeState !== 'object' || Array.isArray(likeState)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid like data.');
        }
        deferRecommendationView(
          defer,
          env,
          identity.authorization,
          'forum_post',
          postId,
        );
        return jsonResponse(
          {data: {...rows[0], ...likeState, ...(url.searchParams.get('planning') === '1'
            ? {poll: await supabaseRpc(env, identity.authorization, 'get_forum_poll', {p_post_id: postId})} : {})}},
          200,
          requestId,
          cors,
        );
      }

      if (request.method === 'PUT' && segments.length === 4 && segments[3] === 'like') {
        const body = await jsonBody(request);
        exactKeys(body, ['liked']);
        if (typeof body.liked !== 'boolean') {
          throw new ApiError(400, 'invalid_parameter', 'liked must be a boolean.');
        }
        const state = await supabaseRpc(
          env,
          identity.authorization,
          'set_forum_post_like',
          {p_post_id: postId, p_liked: body.liked},
        );
        if (!state || typeof state !== 'object' || Array.isArray(state)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid like data.');
        }
        return jsonResponse({data: state}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 4 && segments[3] === 'media') {
        assertMediaEnvironment(env);
        const imageKey = await supabaseRpc(
          env,
          identity.authorization,
          'get_forum_post_image_key',
          {p_post_id: postId},
        );
        if (imageKey === null) {
          throw new ApiError(404, 'forum_media_not_found', 'Discussion image was not found.');
        }
        if (!isMediaKey(imageKey, 'posts')) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid media reference.');
        }
        const object = await getMediaObject(env.USER_MEDIA, imageKey);
        if (object === null) {
          throw new ApiError(404, 'forum_media_not_found', 'Discussion image was not found.');
        }
        return mediaResponse(object, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 4 && segments[3] === 'comments') {
        const comments = await supabaseRpc(
          env,
          identity.authorization,
          'get_forum_comments',
          {p_post_id: postId, p_limit: 100},
        );
        if (!Array.isArray(comments)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid comment data.');
        }
        return jsonResponse({data: comments}, 200, requestId, cors);
      }

      if (request.method === 'POST' && segments.length === 4 && segments[3] === 'comments') {
        const body = await jsonBody(request);
        exactKeys(body, ['body']);
        const commentBody = stringParameter(body.body, 'body', 1, 1200);
        const commentId = await supabaseRpc(
          env,
          identity.authorization,
          'create_forum_comment',
          {p_post_id: postId, p_body: commentBody},
        );
        if (typeof commentId !== 'string' || !UUID_PATTERN.test(commentId)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid comment identifier.');
        }
        return jsonResponse({id: commentId}, 201, requestId, cors);
      }

      if (request.method === 'POST' && segments.length === 4 && segments[3] === 'report') {
        const reason = validateForumReport(await jsonBody(request));
        await supabaseRpc(
          env,
          identity.authorization,
          'report_forum_post',
          {p_post_id: postId, p_reason: reason},
        );
        return jsonResponse({submitted: true}, 201, requestId, cors);
      }
    }

    if (
      request.method === 'POST' &&
      segments.length === 4 &&
      segments[0] === 'forum' &&
      segments[1] === 'comments' &&
      segments[3] === 'report'
    ) {
      const commentId = uuidParameter(segments[2], 'comment_id');
      const reason = validateForumReport(await jsonBody(request));
      await supabaseRpc(
        env,
        identity.authorization,
        'report_forum_comment',
        {p_comment_id: commentId, p_reason: reason},
      );
      return jsonResponse({submitted: true}, 201, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'events/mine') {
      const filter = url.searchParams.get('filter') ?? 'going';
      if (!EVENT_PLAN_FILTERS.has(filter)) {
        throw new ApiError(400, 'invalid_event_filter', 'Event plan filter is invalid.');
      }
      const events = await supabaseRpc(
        env,
        identity.authorization,
        'list_my_events_v2',
        {p_filter: filter},
      );
      if (!Array.isArray(events)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid event data.');
      }
      const data = url.searchParams.get('planning') === '1'
        ? await enrichEventPlans(env, identity.authorization, events) : events;
      return jsonResponse({data}, 200, requestId, cors);
    }

    if (request.method === 'GET' && segments.join('/') === 'events/nearby') {
      const latitude = numberParameter(url.searchParams.get('latitude'), 'latitude', -90, 90);
      const longitude = numberParameter(url.searchParams.get('longitude'), 'longitude', -180, 180);
      const radiusKm = numberParameter(url.searchParams.get('radius_km'), 'radius_km', 1, 100);
      const interest = optionalSearchParameter(url.searchParams.get('interest'), 'interest', 240);
      const category = optionalSearchParameter(url.searchParams.get('category'), 'category', 60);
      const startFrom = optionalQueryDateParameter(url.searchParams.get('start_from'), 'start_from');
      const startBefore = optionalQueryDateParameter(url.searchParams.get('start_before'), 'start_before');
      if (startFrom !== null && startBefore !== null && startBefore <= startFrom) {
        throw new ApiError(400, 'invalid_parameter', 'Event date range is invalid.');
      }
      const timeFilter = enumQueryParameter(
        url.searchParams.get('time_filter'),
        'time_filter',
        EVENT_TIME_FILTERS,
        'any',
      );
      const spotsOnly = booleanQueryParameter(url.searchParams.get('spots_only'), 'spots_only');
      const followingOnly = booleanQueryParameter(
        url.searchParams.get('following_only'),
        'following_only',
      );
      const beginnerFriendlyOnly = booleanQueryParameter(
        url.searchParams.get('beginner_friendly_only'),
        'beginner_friendly_only',
      );
      const wheelchairAccessibleOnly = booleanQueryParameter(
        url.searchParams.get('wheelchair_accessible_only'),
        'wheelchair_accessible_only',
      );
      const eventSetting = enumQueryParameter(
        url.searchParams.get('event_setting'),
        'event_setting',
        EVENT_SETTING_FILTERS,
        'any',
      );
      const eventLanguage = optionalSearchParameter(
        url.searchParams.get('event_language'),
        'event_language',
        80,
      );
      const ageGuidance = enumQueryParameter(
        url.searchParams.get('age_guidance'),
        'age_guidance',
        EVENT_AGE_FILTERS,
        'any',
      );
      const timezoneOffsetMinutes = integerParameter(
        url.searchParams.get('timezone_offset_minutes') ?? 0,
        'timezone_offset_minutes',
        -840,
        840,
      );
      const [recommendationRows, hiddenRecommendationIds] = await Promise.all([
        supabaseRpc(
          env,
          identity.authorization,
          'get_recommendation_preferences',
          {},
        ),
        supabaseRpc(
          env,
          identity.authorization,
          'list_hidden_recommendation_ids',
          {p_content_kind: 'event'},
        ),
      ]);
      if (
        !Array.isArray(recommendationRows) || recommendationRows.length !== 1 ||
        !Array.isArray(hiddenRecommendationIds)
      ) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid recommendation controls.');
      }
      const recommendationPreferences = recommendationRows[0];
      const recommendationsEnabled = recommendationPreferences?.enabled !== false;
      const hiddenCategories = new Set(
        Array.isArray(recommendationPreferences?.hidden_categories)
          ? recommendationPreferences.hidden_categories.filter((value) => typeof value === 'string')
          : [],
      );
      const hiddenIds = new Set(hiddenRecommendationIds);
      const hasDiscoveryFilters = startFrom !== null || startBefore !== null ||
        category !== null || timeFilter !== 'any' || spotsOnly || followingOnly ||
        beginnerFriendlyOnly || wheelchairAccessibleOnly || eventSetting !== 'any' ||
        eventLanguage !== null || ageGuidance !== 'any';
      // Keep the indexed hybrid RPC for unconstrained text searches. Default
      // recommendations and filtered discovery share the interest-first scorer.
      if (url.searchParams.get('planning') === '1' && (interest === null || hasDiscoveryFilters)) {
        const queryEmbedding = interest === null ? null : await generateEmbedding(env, identity.authorization, interest);
        const data = await supabaseRpc(env, identity.authorization, 'discover_event_plans', {
          p_latitude: latitude, p_longitude: longitude, p_radius_km: radiusKm,
          p_filters: {interest, category, query_embedding: queryEmbedding, start_from: startFrom?.toISOString() ?? null,
            start_before: startBefore?.toISOString() ?? null, time_filter: timeFilter,
            spots_only: spotsOnly, following_only: followingOnly,
            beginner_friendly_only: beginnerFriendlyOnly, wheelchair_accessible_only: wheelchairAccessibleOnly,
            event_setting: eventSetting, event_language: eventLanguage, age_guidance: ageGuidance,
            timezone_offset_minutes: timezoneOffsetMinutes},
        });
        if (!Array.isArray(data)) throw new ApiError(502, 'invalid_backend_response', 'Events are unavailable.');
        const visible = data.filter(event => !hiddenIds.has(event.id) && !hiddenCategories.has(event.category));
        const ranked = interest === null && recommendationsEnabled
          ? await rerankRecommendations({env, authorization: identity.authorization, surface: 'event', candidates: visible, defer})
          : visible;
        return jsonResponse({data: ranked.map(event => ({...event,
          recommendation_reason: recommendationReason(event, interest, recommendationsEnabled)}))}, 200, requestId, cors);
      }
      const embedding = interest === null || followingOnly
        ? null
        : await generateEmbedding(env, identity.authorization, interest);
      const events = followingOnly
        ? await supabaseRpc(
            env,
            identity.authorization,
            'list_followed_nearby_events',
            {
              p_latitude: latitude,
              p_longitude: longitude,
              p_radius_km: radiusKm,
              p_query: interest,
            },
          )
        : await supabaseRpc(
          env,
          identity.authorization,
          embedding === null
            ? recommendationsEnabled
              ? 'recommend_personalized_events'
              : 'nearby_events'
            : 'recommend_nearby_events_v2',
          embedding === null
            ? {
                p_latitude: latitude,
                p_longitude: longitude,
                p_radius_km: radiusKm,
              }
            : {
                p_latitude: latitude,
                p_longitude: longitude,
                p_radius_km: radiusKm,
                p_query_embedding: embedding,
                p_query: interest,
                p_limit: 30,
              },
        );
      if (!Array.isArray(events)) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid event data.');
      }
      const followedIds = new Set(
        followingOnly ? events.map((event) => event?.organizer_id) : [],
      );
      const hasDetailFilters = beginnerFriendlyOnly ||
        wheelchairAccessibleOnly || eventSetting !== 'any' ||
        eventLanguage !== null || ageGuidance !== 'any';
      let allowedEventIds = null;
      if (hasDetailFilters && events.length > 0) {
        const matchingIds = await supabaseRpc(
          env,
          identity.authorization,
          'filter_event_ids_by_details',
          {
            p_event_ids: events
              .map((event) => event?.id)
              .filter((id) => typeof id === 'string' && UUID_PATTERN.test(id)),
            p_beginner_friendly_only: beginnerFriendlyOnly,
            p_wheelchair_accessible_only: wheelchairAccessibleOnly,
            p_event_setting: eventSetting,
            p_event_language: eventLanguage,
            p_age_guidance: ageGuidance,
          },
        );
        if (!Array.isArray(matchingIds) || matchingIds.some((id) =>
          typeof id !== 'string' || !UUID_PATTERN.test(id)
        )) {
          throw new ApiError(
            502,
            'invalid_backend_response',
            'The database returned invalid filtered event data.',
          );
        }
        allowedEventIds = new Set(matchingIds);
      }
      const filteredEvents = filterDiscoveredEvents(events, {
        category,
        startFrom,
        startBefore,
        timeFilter,
        spotsOnly,
        followingOnly,
        followedIds,
        timezoneOffsetMinutes,
        allowedEventIds,
      }).filter((event) =>
        typeof event?.id === 'string' && !hiddenIds.has(event.id) &&
        (typeof event?.category !== 'string' || !hiddenCategories.has(event.category))
      );
      const rankedEvents = interest === null && recommendationsEnabled
        ? await rerankRecommendations({
            env,
            authorization: identity.authorization,
            surface: 'event',
            candidates: filteredEvents,
            defer,
        })
        : filteredEvents;
      const plannedEvents = url.searchParams.get('planning') === '1'
        ? await enrichEventPlans(env, identity.authorization, rankedEvents) : rankedEvents;
      return jsonResponse({
        data: plannedEvents.map((event) => ({
          ...event,
          recommendation_reason: recommendationReason(event, interest, recommendationsEnabled),
        })),
      }, 200, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'events/media') {
      assertMediaEnvironment(env);
      const token = crypto.randomUUID();
      await putUploadedJpeg(env.USER_MEDIA, `staging/events/${identity.userId}/current.jpg`, request, {
        owner: identity.userId, purpose: 'event-staging', token,
      });
      return jsonResponse({token}, 201, requestId, cors);
    }

    if (request.method === 'POST' && segments.join('/') === 'events') {
      const body = await jsonBody(request);
      if (body.planning !== undefined) {
        const {planning, ...eventBody} = body;
        const input = validateCreateEvent(eventBody);
        const ids = await saveEventPlan(env, identity, input, planning, null, 'this');
        for (const id of input.p_visibility === 'public' ? ids : []) {
          defer?.(indexCreatedContent({env, authorization: identity.authorization,
            rpc: 'set_event_embedding', idField: 'p_event_id', id,
            input: semanticDocument({Title: input.p_title, Category: input.p_category,
              Venue: input.p_venue_name, Address: input.p_address, Description: input.p_description})}));
        }
        return jsonResponse({id: ids[0], ids}, 201, requestId, cors);
      }
      const input = validateCreateEvent(body);
      if (input.p_visibility === 'selected') throw new ApiError(400, 'audience_validation', 'Enter usernames in the audience options.');
      const eventIds = await supabaseRpc(
        env,
        identity.authorization,
        'create_event_v3',
        input,
      );
      if (
        !Array.isArray(eventIds) || eventIds.length === 0 || eventIds.length > 12 ||
        eventIds.some((eventId) => typeof eventId !== 'string' || !UUID_PATTERN.test(eventId))
      ) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid event identifiers.');
      }
      if (input.p_status === 'published' && input.p_visibility === 'public') {
        for (const eventId of eventIds) {
          defer?.(
            indexCreatedContent({
              env,
              authorization: identity.authorization,
              rpc: 'set_event_embedding',
              idField: 'p_event_id',
              id: eventId,
              input: semanticDocument({
                Title: input.p_title,
                Category: input.p_category,
                Venue: input.p_venue_name,
                Address: input.p_address,
                Description: input.p_description,
              }),
            }),
          );
        }
      }
      return jsonResponse({id: eventIds[0], ids: eventIds}, 201, requestId, cors);
    }

    if (segments.length >= 2 && segments[0] === 'events') {
      const eventId = uuidParameter(segments[1], 'event_id');

      if (request.method === 'GET' && segments.length === 3 && segments[2] === 'conflicts') {
        const data = await supabaseRpc(env, identity.authorization, 'list_event_conflicts', {p_event_id: eventId});
        if (!Array.isArray(data)) throw new ApiError(502, 'invalid_backend_response', 'Your plans are unavailable.');
        return jsonResponse({data}, 200, requestId, cors);
      }
      if (request.method === 'GET' && segments.length === 3 && segments[2] === 'meeting-image') {
        assertMediaEnvironment(env);
        const key = await supabaseRpc(env, identity.authorization, 'get_event_meeting_image_key', {p_event_id: eventId});
        if (!isMediaKey(key, 'events')) throw new ApiError(404, 'image_not_found', 'Photo is unavailable.');
        const object = await getMediaObject(env.USER_MEDIA, key);
        if (!object) throw new ApiError(404, 'image_not_found', 'Photo is unavailable.');
        return mediaResponse(object, requestId, cors);
      }
      if (request.method === 'GET' && segments.length === 2 && url.searchParams.get('planning') === '1') {
        await supabaseRpc(env, identity.authorization, 'process_due_event_reconfirmations', {});
        const data = await supabaseRpc(env, identity.authorization, 'get_event_plan', {
          p_event_id: eventId, p_via_invite: url.searchParams.get('invite') === '1',
        });
        if (!data || typeof data !== 'object' || Array.isArray(data)) throw new ApiError(404, 'event_not_found', 'Event was not found.');
        deferRecommendationView(defer, env, identity.authorization, 'event', eventId);
        return jsonResponse({data}, 200, requestId, cors);
      }
      if (request.method === 'GET' && segments.length === 2) {
        await supabaseRpc(
          env,
          identity.authorization,
          'process_due_event_reconfirmations',
          {},
        );
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_event_details_v3',
          {
            p_event_id: eventId,
            p_via_invite: url.searchParams.get('invite') === '1',
          },
        );
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'event_not_found', 'Event was not found.');
        }
        deferRecommendationView(
          defer,
          env,
          identity.authorization,
          'event',
          eventId,
        );
        return jsonResponse({data: rows[0]}, 200, requestId, cors);
      }

      if (request.method === 'PUT' && segments.length === 2) {
        const body = await jsonBody(request);
        if (body.planning !== undefined) {
          const {planning, ...eventBody} = body;
          const input = validateCreateEvent(eventBody, false);
          await saveEventPlan(env, identity, input, planning, eventId, 'this');
          if (input.p_visibility === 'public') defer?.(indexCreatedContent({env, authorization: identity.authorization,
            rpc: 'set_event_embedding', idField: 'p_event_id', id: eventId,
            input: semanticDocument({Title: input.p_title, Category: input.p_category,
              Venue: input.p_venue_name, Address: input.p_address, Description: input.p_description})}));
          return jsonResponse({updated: true}, 200, requestId, cors);
        }
        const input = validateCreateEvent(body, false);
        if (input.p_visibility === 'selected') throw new ApiError(400, 'audience_validation', 'Enter usernames in the audience options.');
        const {p_repeat_interval: _, p_repeat_count: __, ...eventInput} = input;
        await supabaseRpc(
          env,
          identity.authorization,
          'update_own_event_v3',
          {p_event_id: eventId, ...eventInput},
        );
        if (input.p_visibility === 'public') defer?.(
          indexCreatedContent({
            env,
            authorization: identity.authorization,
            rpc: 'set_event_embedding',
            idField: 'p_event_id',
            id: eventId,
            input: semanticDocument({
              Title: input.p_title,
              Category: input.p_category,
              Venue: input.p_venue_name,
              Address: input.p_address,
              Description: input.p_description,
            }),
          }),
        );
        return jsonResponse({updated: true}, 200, requestId, cors);
      }

      if (
        request.method === 'PUT' && segments.length === 3 &&
        segments[2] === 'series'
      ) {
        const body = await jsonBody(request);
        const scope = stringParameter(body.scope, 'scope', 3, 6);
        if (!SERIES_SCOPES.has(scope)) {
          throw new ApiError(400, 'series_scope_validation', 'Recurring event scope is invalid.');
        }
        const {scope: _, planning, ...eventBody} = body;
        const input = validateCreateEvent(eventBody, false);
        if (planning !== undefined) {
          const ids = await saveEventPlan(env, identity, input, planning, eventId, scope);
          return jsonResponse({updated: true, updated_count: ids.length}, 200, requestId, cors);
        }
        if (input.p_visibility === 'selected') throw new ApiError(400, 'audience_validation', 'Enter usernames in the audience options.');
        const {p_repeat_interval: __, p_repeat_count: ___, ...eventInput} = input;
        const updatedCount = await supabaseRpc(
          env,
          identity.authorization,
          'update_event_series_v1',
          {p_event_id: eventId, p_scope: scope, ...eventInput},
        );
        if (!Number.isInteger(updatedCount) || updatedCount < 1 || updatedCount > 12) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid series result.');
        }
        return jsonResponse({updated: true, updated_count: updatedCount}, 200, requestId, cors);
      }

      if (
        request.method === 'GET' && segments.length === 3 &&
        segments[2] === 'host-dashboard'
      ) {
        const data = await supabaseRpc(
          env,
          identity.authorization,
          'get_event_host_dashboard',
          {p_event_id: eventId},
        );
        if (!data || Array.isArray(data) || typeof data !== 'object') {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid host statistics.');
        }
        return jsonResponse({data}, 200, requestId, cors);
      }

      if (
        request.method === 'GET' && segments.length === 3 &&
        segments[2] === 'host-attendees'
      ) {
        const attendees = await supabaseRpc(
          env,
          identity.authorization,
          url.searchParams.get('planning') === '1' ? 'list_event_host_parties' : 'list_event_host_attendees',
          {p_event_id: eventId},
        );
        if (!Array.isArray(attendees)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid host attendee data.');
        }
        return jsonResponse({data: attendees}, 200, requestId, cors);
      }

      if (
        request.method === 'PUT' && segments.length === 4 &&
        segments[2] === 'attendance'
      ) {
        const profileId = uuidParameter(segments[3], 'profile_id');
        const body = await jsonBody(request);
        exactKeys(body, ['status']);
        const status = stringParameter(body.status, 'status', 6, 10);
        if (!ATTENDANCE_STATUSES.has(status)) {
          throw new ApiError(400, 'attendance_validation', 'Attendance status is invalid.');
        }
        await supabaseRpc(
          env,
          identity.authorization,
          'set_event_attendance',
          {p_event_id: eventId, p_profile_id: profileId, p_status: status},
        );
        return jsonResponse({updated: true, status}, 200, requestId, cors);
      }

      if (
        request.method === 'POST' && segments.length === 3 &&
        segments[2] === 'translation'
      ) {
        const body = await jsonBody(request);
        exactKeys(body, ['target_language']);
        const targetLanguage = stringParameter(
          body.target_language,
          'target_language',
          2,
          60,
        );
        const rows = await supabaseRpc(
          env,
          identity.authorization,
          'get_event_details_v3',
          {p_event_id: eventId, p_via_invite: false},
        );
        if (!Array.isArray(rows) || rows.length === 0) {
          throw new ApiError(404, 'event_not_found', 'Event was not found.');
        }
        const event = rows[0];
        const text = semanticDocument({
          Title: event?.title,
          Description: event?.description,
          WhatToBring: event?.what_to_bring,
        });
        if (text.length < 1) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid event text.');
        }
        await claimAssistantTool(env, identity.authorization, 'translation');
        const translated = await callAssistantTool(env, 'translate', {
          text,
          target_language: targetLanguage,
        });
        if (
          !translated || Array.isArray(translated) ||
          typeof translated.translation !== 'string' ||
          translated.translation.trim().length < 1 ||
          translated.translation.length > 5000
        ) {
          throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid translation.');
        }
        return jsonResponse(
          {translation: translated.translation.trim()},
          200,
          requestId,
          cors,
        );
      }

      if (
        request.method === 'POST' && segments.length === 3 &&
        segments[2] === 'discussion-summary'
      ) {
        const messages = await supabaseRpc(
          env,
          identity.authorization,
          'list_event_discussion',
          {p_event_id: eventId},
        );
        if (!Array.isArray(messages)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid discussion data.');
        }
        const context = messages
          .filter((message) =>
            typeof message?.body === 'string' && message.body.trim().length > 0
          )
          .slice(-50)
          .map((message) =>
            `${typeof message.author_name === 'string' ? message.author_name : 'Member'}: ${message.body}`
              .slice(0, 1200)
          );
        if (context.length < 2) {
          throw new ApiError(409, 'summary_unavailable', 'There are not enough messages to summarize yet.');
        }
        await claimAssistantTool(env, identity.authorization, 'summary');
        const summary = await callAssistantTool(env, 'summarize', {
          messages: context,
        });
        if (!validDiscussionSummary(summary)) {
          throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid summary.');
        }
        return jsonResponse(
          {
            summary: summary.summary.trim(),
            action_items: summary.action_items.map((item) => item.trim()),
          },
          200,
          requestId,
          cors,
        );
      }

      if (
        request.method === 'POST' && segments.length === 3 &&
        segments[2] === 'discussion-changes'
      ) {
        const [lastSeenAt, messages] = await Promise.all([
          supabaseRpc(
            env,
            identity.authorization,
            'get_event_discussion_last_seen',
            {p_event_id: eventId},
          ),
          supabaseRpc(
            env,
            identity.authorization,
            'list_event_discussion',
            {p_event_id: eventId},
          ),
        ]);
        if (!Array.isArray(messages)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid discussion data.');
        }
        const seenTime = typeof lastSeenAt === 'string' ? Date.parse(lastSeenAt) : Number.NaN;
        const changed = messages.filter((message) => {
          const createdAt = typeof message?.created_at === 'string'
            ? Date.parse(message.created_at)
            : Number.NaN;
          return Number.isNaN(seenTime) || (!Number.isNaN(createdAt) && createdAt > seenTime);
        }).slice(-50);
        if (changed.length < 1) {
          throw new ApiError(409, 'summary_unavailable', 'There are no new messages since your last visit.');
        }
        const context = changed.map((message) =>
          `${typeof message.author_name === 'string' ? message.author_name : 'Member'}: ${message.body}`
            .slice(0, 1200)
        );
        await claimAssistantTool(env, identity.authorization, 'discussion_changes');
        const summary = await callAssistantTool(env, 'summarize', {messages: context});
        if (!validDiscussionSummary(summary)) {
          throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid summary.');
        }
        await supabaseRpc(
          env,
          identity.authorization,
          'mark_event_discussion_seen',
          {p_event_id: eventId},
        );
        return jsonResponse({
          summary: summary.summary.trim(),
          action_items: summary.action_items.map((item) => item.trim()),
          message_count: changed.length,
        }, 200, requestId, cors);
      }

      if (request.method === 'PUT' && segments.length === 3 && segments[2] === 'rsvp') {
        const body = await jsonBody(request);
        exactOptionalKeys(body, ['status'], ['guest_count']);
        const guests = body.guest_count === undefined ? null : integerParameter(body.guest_count, 'guest_count', 0, 1);
        if (typeof body.status !== 'string' || !RSVP_STATUSES.has(body.status)) {
          throw new ApiError(400, 'invalid_rsvp_status', 'RSVP status is invalid.');
        }
        const status = await supabaseRpc(
          env,
          identity.authorization,
          guests === null ? 'set_event_rsvp' : 'set_event_rsvp_with_guest',
          {p_event_id: eventId, p_status: body.status, ...(guests === null ? {} : {p_guest_count: guests})},
        );
        return jsonResponse({status}, 200, requestId, cors);
      }

      if (request.method === 'GET' && segments.length === 3 && segments[2] === 'attendees') {
        const attendees = await supabaseRpc(
          env,
          identity.authorization,
          'list_event_attendees_v2',
          {p_event_id: eventId},
        );
        if (!Array.isArray(attendees)) {
          throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid attendee data.');
        }
        return jsonResponse({data: attendees}, 200, requestId, cors);
      }

      if (segments.length === 3 && segments[2] === 'cohosts') {
        if (request.method === 'GET') {
          const cohosts = await supabaseRpc(
            env,
            identity.authorization,
            'list_event_cohosts',
            {p_event_id: eventId},
          );
          if (!Array.isArray(cohosts)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid co-host data.');
          }
          return jsonResponse({data: cohosts}, 200, requestId, cors);
        }
        if (request.method === 'PUT' || request.method === 'DELETE') {
          const body = await jsonBody(request);
          exactKeys(body, ['username']);
          const username = stringParameter(body.username, 'username', 3, 33);
          const profileId = await supabaseRpc(
            env,
            identity.authorization,
            'set_event_cohost',
            {
              p_event_id: eventId,
              p_username: username,
              p_enabled: request.method === 'PUT',
            },
          );
          if (typeof profileId !== 'string' || !UUID_PATTERN.test(profileId)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid co-host identifier.');
          }
          return jsonResponse({profile_id: profileId}, 200, requestId, cors);
        }
      }

      if (
        request.method === 'PUT' && segments.length === 4 &&
        segments[2] === 'attendees' && segments[3] === 'visibility'
      ) {
        const body = await jsonBody(request);
        exactKeys(body, ['visible']);
        if (typeof body.visible !== 'boolean') {
          throw new ApiError(400, 'invalid_parameter', 'Attendee visibility is invalid.');
        }
        const visible = await supabaseRpc(
          env,
          identity.authorization,
          'set_event_attendee_visibility',
          {p_event_id: eventId, p_visible: body.visible},
        );
        return jsonResponse({visible: visible === true}, 200, requestId, cors);
      }

      if (
        request.method === 'PUT' && segments.length === 3 &&
        segments[2] === 'discussion-notifications'
      ) {
        const body = await jsonBody(request);
        exactKeys(body, ['enabled']);
        if (typeof body.enabled !== 'boolean') {
          throw new ApiError(400, 'invalid_parameter', 'Notification preference is invalid.');
        }
        const enabled = await supabaseRpc(
          env,
          identity.authorization,
          'set_event_discussion_notifications',
          {p_event_id: eventId, p_enabled: body.enabled},
        );
        return jsonResponse({enabled: enabled === true}, 200, requestId, cors);
      }

      if (
        request.method === 'POST' && segments.length === 4 &&
        segments[2] === 'reconfirmation' && segments[3] === 'request'
      ) {
        const deadline = await supabaseRpc(
          env,
          identity.authorization,
          'request_event_rsvp_reconfirmation_v2',
          {p_event_id: eventId},
        );
        return jsonResponse({deadline_at: deadline}, 200, requestId, cors);
      }

      if (
        request.method === 'POST' && segments.length === 4 &&
        segments[2] === 'reconfirmation' && segments[3] === 'confirm'
      ) {
        const confirmedAt = await supabaseRpc(
          env,
          identity.authorization,
          'confirm_event_rsvp',
          {p_event_id: eventId},
        );
        return jsonResponse({confirmed_at: confirmedAt}, 200, requestId, cors);
      }

      if (
        (request.method === 'PUT' || request.method === 'DELETE') &&
        segments.length === 3 && segments[2] === 'save'
      ) {
        const saved = request.method === 'PUT';
        await supabaseRpc(
          env,
          identity.authorization,
          'set_event_saved',
          {p_event_id: eventId, p_saved: saved},
        );
        return jsonResponse({saved}, 200, requestId, cors);
      }

      if (segments.length === 3 && segments[2] === 'reminder') {
        if (request.method === 'PUT') {
          const body = await jsonBody(request);
          exactKeys(body, ['remind_at']);
          const remindAt = dateParameter(body.remind_at, 'remind_at');
          const saved = await supabaseRpc(
            env,
            identity.authorization,
            'set_event_reminder',
            {p_event_id: eventId, p_remind_at: remindAt.toISOString()},
          );
          return jsonResponse({remind_at: saved}, 200, requestId, cors);
        }
        if (request.method === 'DELETE') {
          await supabaseRpc(
            env,
            identity.authorization,
            'clear_event_reminder',
            {p_event_id: eventId},
          );
          return jsonResponse({cleared: true}, 200, requestId, cors);
        }
      }

      if (request.method === 'POST' && segments.length === 3 && segments[2] === 'cancel') {
        await supabaseRpc(
          env,
          identity.authorization,
          'cancel_managed_event',
          {p_event_id: eventId},
        );
        return jsonResponse({cancelled: true}, 200, requestId, cors);
      }

      if (segments.length === 3 && segments[2] === 'announcements') {
        if (request.method === 'GET') {
          const announcements = await supabaseRpc(
            env,
            identity.authorization,
            'list_event_announcements',
            {p_event_id: eventId},
          );
          if (!Array.isArray(announcements)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid announcement data.');
          }
          return jsonResponse({data: announcements}, 200, requestId, cors);
        }
        if (request.method === 'POST') {
          const body = await jsonBody(request);
          exactKeys(body, ['body']);
          const announcement = stringParameter(body.body, 'body', 1, 1000);
          const id = await supabaseRpc(
            env,
            identity.authorization,
            'create_event_announcement_v2',
            {p_event_id: eventId, p_body: announcement},
          );
          if (typeof id !== 'string' || !UUID_PATTERN.test(id)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid announcement identifier.');
          }
          return jsonResponse({id}, 201, requestId, cors);
        }
      }

      if (segments.length === 3 && segments[2] === 'discussion') {
        if (request.method === 'GET') {
          const [messages, lastSeenAt] = await Promise.all([
            supabaseRpc(
              env,
              identity.authorization,
              'list_event_discussion',
              {p_event_id: eventId},
            ),
            supabaseRpc(
              env,
              identity.authorization,
              'get_event_discussion_last_seen',
              {p_event_id: eventId},
            ),
          ]);
          if (!Array.isArray(messages)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid discussion data.');
          }
          return jsonResponse({data: messages, last_seen_at: lastSeenAt}, 200, requestId, cors);
        }
        if (request.method === 'POST') {
          const body = await jsonBody(request);
          exactKeys(body, ['body']);
          const message = stringParameter(body.body, 'body', 1, 1200);
          const id = await supabaseRpc(
            env,
            identity.authorization,
            'create_event_discussion_message',
            {p_event_id: eventId, p_body: message},
          );
          if (typeof id !== 'string' || !UUID_PATTERN.test(id)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid discussion identifier.');
          }
          return jsonResponse({id}, 201, requestId, cors);
        }
      }

      if (
        request.method === 'PUT' && segments.length === 4 &&
        segments[2] === 'discussion' && segments[3] === 'seen'
      ) {
        const seenAt = await supabaseRpc(
          env,
          identity.authorization,
          'mark_event_discussion_seen',
          {p_event_id: eventId},
        );
        return jsonResponse({seen_at: seenAt}, 200, requestId, cors);
      }

      if (
        request.method === 'POST' && segments.length === 5 &&
        segments[2] === 'discussion' && segments[4] === 'report'
      ) {
        const messageId = uuidParameter(segments[3], 'message_id');
        const reason = validateForumReport(await jsonBody(request));
        await supabaseRpc(
          env,
          identity.authorization,
          'report_event_discussion_message',
          {p_message_id: messageId, p_reason: reason},
        );
        return jsonResponse({submitted: true}, 201, requestId, cors);
      }

      if (segments.length === 3 && segments[2] === 'feedback') {
        if (request.method === 'GET') {
          const feedback = await supabaseRpc(
            env,
            identity.authorization,
            'list_event_feedback_v2',
            {p_event_id: eventId},
          );
          if (!Array.isArray(feedback)) {
            throw new ApiError(502, 'invalid_backend_response', 'The database returned invalid feedback data.');
          }
          return jsonResponse({data: feedback}, 200, requestId, cors);
        }
        if (request.method === 'POST') {
          const input = validateEventFeedback(await jsonBody(request));
          await supabaseRpc(
            env,
            identity.authorization,
            'submit_event_feedback',
            {p_event_id: eventId, ...input},
          );
          return jsonResponse({submitted: true}, 201, requestId, cors);
        }
      }

      if (request.method === 'POST' && segments.length === 3 && segments[2] === 'report') {
        const body = await jsonBody(request);
        exactKeys(body, ['reason']);
        if (typeof body.reason !== 'string' || !REPORT_REASONS.has(body.reason)) {
          throw new ApiError(400, 'invalid_report_reason', 'Report reason is invalid.');
        }
        await insertReport(env, identity, eventId, body.reason);
        return jsonResponse({submitted: true}, 201, requestId, cors);
      }
    }

    throw new ApiError(404, 'route_not_found', 'API route was not found.');
  } catch (error) {
    const apiError = error instanceof ApiError
      ? error
      : new ApiError(500, 'internal_error', 'The edge API could not process the request.');
    return jsonResponse(
      {error: {code: apiError.code, message: apiError.message}},
      apiError.status,
      requestId,
      cors,
    );
  }
}

function routeSegments(pathname) {
  const prefix = '/api/v1/';
  if (!pathname.startsWith(prefix)) {
    throw new ApiError(404, 'route_not_found', 'API route was not found.');
  }
  return pathname.slice(prefix.length).split('/').filter(Boolean);
}

function assertEnvironment(env) {
  let url;
  try {
    url = new URL(env.SUPABASE_URL);
  } catch (_) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.supabase.co')) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
  if (typeof env.SUPABASE_PUBLISHABLE_KEY !== 'string' || env.SUPABASE_PUBLISHABLE_KEY.length < 20) {
    throw new ApiError(503, 'edge_not_configured', 'The edge API is not configured.');
  }
}

function assertMediaEnvironment(env) {
  const bucket = env.USER_MEDIA;
  if (
    !bucket ||
    typeof bucket.get !== 'function' ||
    typeof bucket.put !== 'function' ||
    typeof bucket.delete !== 'function'
  ) {
    throw new ApiError(503, 'media_not_configured', 'Media storage is not configured.');
  }
}

function assertPlaceEnvironment(env) {
  if (typeof env.GEOAPIFY_API_KEY !== 'string' || env.GEOAPIFY_API_KEY.trim().length < 16) {
    throw new ApiError(503, 'places_not_configured', 'Address suggestions are not configured.');
  }
}

async function geoapifyAutocomplete(env, {
  text,
  latitude,
  longitude,
  language,
}) {
  // Share a deadline across both requests so the optional fallback stays
  // within the mobile client's timeout. No location data is kept globally.
  const signal = AbortSignal.timeout(8000);
  const parameters = {format: 'json', limit: '10'};
  if (language !== null) parameters.lang = language;
  if (latitude !== null && longitude !== null) {
    parameters.bias = `proximity:${longitude},${latitude}`;
  }
  const tokens = placeSearchTokens(text);
  if (tokens.length === 0) return [];
  let candidates = await geoapifyGeocode(env, 'autocomplete', {
    ...parameters, text,
  }, signal);
  const city = explicitPlaceCity(text, candidates);
  const hasFullMatch = candidates.some((place) =>
    normalizeGeoapifyPlace(place) !== null && placeQueryCoverage(tokens, place) === 1,
  );

  if (!hasFullMatch) {
    // Autocomplete can silently drop words from a venue name. Forward
    // geocoding supports a separate name/city query, including venue aliases.
    const expanded = expandVenueQuery(text);
    const name = city === null
      ? expanded
      : expanded.replace(new RegExp(escapePlaceRegex(city), 'iu'), '').replace(/^[\s,]+|[\s,]+$/g, '');
    const search = city !== null && name.length >= 3 && !/\d/.test(text)
      ? {name, city, type: 'amenity'}
      : {text: expanded};
    try {
      const venues = await geoapifyGeocode(env, 'search', {
        ...parameters, ...search,
      }, signal);
      candidates = [...candidates, ...venues];
    } catch (_) {
      // A best-effort venue lookup must not discard usable autocomplete data.
    }
  }

  const preferredCity = city ?? explicitPlaceCity(text, candidates);
  const ranked = candidates
    .map((raw) => ({
      place: normalizeGeoapifyPlace(raw),
      coverage: placeQueryCoverage(tokens, raw),
      confidence: typeof raw?.rank?.confidence === 'number' ? raw.rank.confidence : 0,
      city: typeof raw?.city === 'string' ? normalizePlaceText(raw.city) : null,
    }))
    .filter((item) => item.place !== null &&
      // A city/street-only match is not an exact match for a named venue.
      item.coverage >= 0.6 &&
      (preferredCity === null || item.city === null || item.city === normalizePlaceText(preferredCity)))
    .sort((a, b) => b.coverage - a.coverage || b.confidence - a.confidence);
  const seen = new Set();
  return ranked.filter(({place}) => {
    // Separate Geoapify indexes can give the same venue different place IDs.
    const key = `${normalizePlaceText(place.formatted_address)}:${place.latitude.toFixed(4)},${place.longitude.toFixed(4)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 5).map(({place}) => place);
}

function expandVenueQuery(text) {
  // Expand common German campus-hall abbreviations, without hardcoding any
  // venue, address or coordinates. Other queries pass through unchanged.
  return text
    .replace(/\buni[\s-]*sport[\s-]*halle\b/giu, 'Sporthalle Universität')
    .replace(/\buni[\s-]*halle\b/giu, 'Sporthalle Universität')
    .replace(/\bsport[\s-]+halle\b/giu, 'Sporthalle')
    .replace(/\buni\b/giu, 'Universität');
}

function normalizePlaceText(text) {
  return expandVenueQuery(text).normalize('NFKD').replace(/\p{M}/gu, '')
    .toLowerCase().replace(/ß/g, 'ss').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

function placeSearchTokens(text) {
  const ignored = new Set(['der', 'die', 'das', 'the', 'of', 'at', 'in']);
  return [...new Set(normalizePlaceText(text).split(' ').filter((token) =>
    token.length > 0 && !ignored.has(token),
  ))];
}

function placeQueryCoverage(tokens, place) {
  if (!place || typeof place !== 'object' || tokens.length === 0) return 0;
  const words = placeSearchTokens([
    place.name, place.formatted, place.address_line1, place.address_line2,
  ].filter((value) => typeof value === 'string').join(' '));
  return tokens.filter((token) => words.some((word) =>
    word === token || (token.length >= 3 && word.startsWith(token)),
  )).length / tokens.length;
}

function explicitPlaceCity(text, candidates) {
  const query = ` ${normalizePlaceText(text)} `;
  const cities = new Map();
  for (const candidate of candidates) {
    const city = boundedUpstreamString(candidate?.city, 160);
    if (city !== null && query.includes(` ${normalizePlaceText(city)} `)) {
      cities.set(city, (cities.get(city) ?? 0) + 1);
    }
  }
  return [...cities].sort((a, b) => b[1] - a[1] || b[0].length - a[0].length)[0]?.[0] ?? null;
}

function escapePlaceRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function geoapifyGeocode(env, endpoint, parameters, signal) {
  const upstreamUrl = new URL(`https://api.geoapify.com/v1/geocode/${endpoint}`);
  for (const [key, value] of Object.entries(parameters)) upstreamUrl.searchParams.set(key, value);
  upstreamUrl.searchParams.set('apiKey', env.GEOAPIFY_API_KEY.trim());

  let response;
  try {
    response = await fetch(upstreamUrl, {
      headers: {Accept: 'application/json'},
      signal,
    });
  } catch (_) {
    throw new ApiError(503, 'place_search_unavailable', 'Address suggestions are temporarily unavailable.');
  }
  if (response.status === 429) {
    throw new ApiError(429, 'place_search_busy', 'Address suggestions are busy. Please wait and retry.');
  }
  if (!response.ok) {
    throw new ApiError(503, 'place_search_unavailable', 'Address suggestions are temporarily unavailable.');
  }

  const rawLength = response.headers.get('Content-Length');
  const contentLength = rawLength === null ? null : Number(rawLength);
  if (
    contentLength !== null &&
    (!Number.isFinite(contentLength) || contentLength > MAX_PLACE_RESPONSE_BYTES)
  ) {
    throw new ApiError(502, 'invalid_place_response', 'The address provider returned invalid data.');
  }

  let payloadText;
  try {
    payloadText = await readBoundedResponseText(response, MAX_PLACE_RESPONSE_BYTES);
  } catch (_) {
    throw new ApiError(502, 'invalid_place_response', 'The address provider returned invalid data.');
  }
  let payload;
  try {
    payload = JSON.parse(payloadText);
  } catch (_) {
    throw new ApiError(502, 'invalid_place_response', 'The address provider returned invalid data.');
  }
  const results = payload && !Array.isArray(payload) && typeof payload === 'object'
    ? payload.results
    : null;
  if (!Array.isArray(results)) {
    throw new ApiError(502, 'invalid_place_response', 'The address provider returned invalid data.');
  }

  return results;
}

async function readBoundedResponseText(response, maximumBytes) {
  if (response.body === null) return '';
  const reader = response.body.getReader();
  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maximumBytes) {
        await reader.cancel();
        throw new Error('Response is too large.');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(body);
}

function normalizeGeoapifyPlace(value) {
  if (!value || Array.isArray(value) || typeof value !== 'object') return null;
  const latitude = finiteNumber(value.lat);
  const longitude = finiteNumber(value.lon);
  const formattedAddress = boundedUpstreamString(value.formatted, 300);
  if (
    latitude === null ||
    longitude === null ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180 ||
    formattedAddress === null
  ) {
    return null;
  }

  const timezone = value.timezone && typeof value.timezone === 'object'
    ? boundedUpstreamString(value.timezone.name, 80)
    : null;
  return {
    id: boundedUpstreamString(value.place_id, 240) ?? `${latitude},${longitude}:${formattedAddress}`,
    name: boundedUpstreamString(value.name, 160),
    formatted_address: formattedAddress,
    address_line1: boundedUpstreamString(value.address_line1, 200),
    address_line2: boundedUpstreamString(value.address_line2, 240),
    country_code: boundedUpstreamString(value.country_code, 2)?.toLowerCase() ?? null,
    latitude,
    longitude,
    result_type: boundedUpstreamString(value.result_type, 40),
    timezone,
  };
}

function finiteNumber(value) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function boundedUpstreamString(value, maximum) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maximum ? trimmed : null;
}

async function authenticate(request, env) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (!/^Bearer\s+\S+$/.test(authorization)) {
    throw new ApiError(401, 'authentication_required', 'Sign in is required.');
  }

  let response;
  try {
    response = await fetch(`${trimSlash(env.SUPABASE_URL)}/auth/v1/user`, {
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: authorization,
      },
    });
  } catch (_) {
    throw new ApiError(503, 'authentication_unavailable', 'Authentication is temporarily unavailable.');
  }

  if (!response.ok) {
    throw new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  }
  const user = await response.json();
  if (!user || typeof user.id !== 'string' || !UUID_PATTERN.test(user.id)) {
    throw new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  }
  return {authorization, userId: user.id};
}

async function supabaseRpc(env, authorization, functionName, parameters) {
  let response;
  try {
    response = await fetch(
      `${trimSlash(env.SUPABASE_URL)}/rest/v1/rpc/${functionName}`,
      {
        method: 'POST',
        headers: supabaseHeaders(env, authorization),
        body: JSON.stringify(parameters),
      },
    );
  } catch (_) {
    throw new ApiError(503, 'database_unavailable', 'The database is temporarily unavailable.');
  }
  return parseSupabaseResponse(response);
}

function deferRecommendationView(
  defer,
  env,
  authorization,
  contentKind,
  contentId,
) {
  if (defer === null) return;
  defer(
    supabaseRpc(
      env,
      authorization,
      'record_recommendation_view',
      {p_content_kind: contentKind, p_content_id: contentId},
    ).catch(() => undefined),
  );
}

async function insertReport(env, identity, eventId, reason) {
  let response;
  try {
    response = await fetch(`${trimSlash(env.SUPABASE_URL)}/rest/v1/reports`, {
      method: 'POST',
      headers: {
        ...supabaseHeaders(env, identity.authorization),
        Prefer: 'return=minimal',
      },
      body: JSON.stringify({
        reporter_id: identity.userId,
        event_id: eventId,
        reason,
      }),
    });
  } catch (_) {
    throw new ApiError(503, 'database_unavailable', 'The database is temporarily unavailable.');
  }
  await parseSupabaseResponse(response);
}

async function parseSupabaseResponse(response) {
  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (_) {
      if (response.ok) {
        throw new ApiError(502, 'invalid_backend_response', 'The database returned an invalid response.');
      }
    }
  }
  if (!response.ok) throw mappedSupabaseError(response.status, payload);
  return payload;
}

function mappedSupabaseError(status, payload) {
  const backendMessage = typeof payload?.message === 'string' ? payload.message : '';
  const known = {
    guest_place_unavailable: [409, 'guest_place_unavailable', 'There is not enough room for that change. Existing reservations are unchanged.'],
    guests_not_allowed: [400, 'guests_not_allowed', 'This host has not enabled guests.'],
    guests_already_registered: [409, 'guests_already_registered', 'Guests are already registered. Keep this enabled until they have been removed.'],
    poll_validation: [400, 'poll_validation', 'Check the proposed dates and choose an available option.'],
    poll_closed: [409, 'poll_closed', 'This poll has already been turned into an event. Refresh to see it.'],
    poll_option_unavailable: [409, 'poll_option_unavailable', 'This date is no longer available.'],
    authentication_required: [401, 'authentication_required', 'Sign in is required.'],
    event_validation: [400, 'event_validation', 'Event details are invalid.'],
    audience_validation: [400, 'audience_validation', 'Choose up to 50 valid usernames for this audience.'],
    audience_not_found: [400, 'audience_not_found', 'One or more usernames could not be selected. Check the usernames and try again.'],
    invalid_rsvp_status: [400, 'invalid_rsvp_status', 'RSVP status is invalid.'],
    invalid_event_filter: [400, 'invalid_event_filter', 'Event plan filter is invalid.'],
    invalid_reminder_time: [400, 'invalid_reminder_time', 'Choose a reminder before the event starts.'],
    capacity_below_attendance: [400, 'capacity_below_attendance', 'Capacity cannot be lower than the number already going.'],
    announcement_validation: [400, 'announcement_validation', 'Announcement content is invalid.'],
    announcement_rate_limited: [429, 'announcement_rate_limited', 'Please wait before sending another announcement.'],
    discussion_validation: [400, 'discussion_validation', 'Event message is invalid.'],
    discussion_rate_limited: [429, 'discussion_rate_limited', 'You are sending event messages too quickly.'],
    discussion_unavailable: [403, 'discussion_unavailable', 'Join this event to take part in its discussion.'],
    feedback_validation: [400, 'feedback_validation', 'Feedback is invalid.'],
    feedback_unavailable: [403, 'feedback_unavailable', 'Feedback is not available for this event.'],
    event_unavailable: [409, 'event_unavailable', 'This event is unavailable.'],
    event_started: [409, 'event_started', 'This event has already started.'],
    event_full: [409, 'event_full', 'This event is full.'],
    saved_search_validation: [400, 'saved_search_validation', 'Saved search details are invalid.'],
    saved_search_limit: [409, 'saved_search_limit', 'You can save up to 12 event searches.'],
    saved_search_name_taken: [409, 'saved_search_name_taken', 'An alert with that name already exists.'],
    invalid_event_filters: [400, 'invalid_event_filters', 'Event filters are invalid.'],
    onboarding_validation: [400, 'onboarding_validation', 'Onboarding preferences are invalid.'],
    notification_preferences_validation: [400, 'notification_preferences_validation', 'Notification preferences are invalid.'],
    recommendation_preferences_validation: [400, 'recommendation_preferences_validation', 'Recommendation preferences are invalid.'],
    recommendation_validation: [400, 'recommendation_validation', 'Recommendation target is invalid.'],
    series_scope_validation: [400, 'series_scope_validation', 'Recurring event scope is invalid.'],
    attendance_validation: [400, 'attendance_validation', 'Attendance status is invalid.'],
    attendance_window_closed: [409, 'attendance_window_closed', 'Check-in opens six hours before the event.'],
    attendee_not_found: [404, 'attendee_not_found', 'Attendee was not found.'],
    moderator_required: [403, 'moderator_required', 'Moderator access is required.'],
    moderation_status_validation: [400, 'moderation_status_validation', 'Moderation status is invalid.'],
    moderation_action_validation: [400, 'moderation_action_validation', 'Moderation action is invalid.'],
    report_not_found: [404, 'report_not_found', 'Report was not found.'],
    push_device_validation: [400, 'push_device_validation', 'Notification device details are invalid.'],
    invalid_block_target: [400, 'invalid_block_target', 'This member cannot be blocked.'],
    profile_not_found: [404, 'profile_not_found', 'Profile was not found.'],
    connection_list_validation: [400, 'connection_list_validation', 'Check the member list options and try again.'],
    connection_search_owner_only: [403, 'connection_search_owner_only', 'Only the account owner can search this list.'],
    account_deletion_confirmation: [400, 'account_deletion_confirmation', 'Type DELETE to confirm account deletion.'],
    invalid_cohost: [400, 'invalid_cohost', 'Choose a valid co-host username.'],
    cohost_not_found: [404, 'cohost_not_found', 'No member has that username.'],
    cohost_limit_reached: [409, 'cohost_limit_reached', 'An event can have up to five co-hosts.'],
    reconfirmation_too_late: [409, 'reconfirmation_too_late', 'It is too close to the event to request confirmations.'],
    reconfirmation_unavailable: [409, 'reconfirmation_unavailable', 'This confirmation request is no longer active.'],
    summary_unavailable: [409, 'summary_unavailable', 'There are not enough messages to summarize yet.'],
    forum_validation: [400, 'forum_validation', 'Discussion content is invalid.'],
    forum_rate_limited: [429, 'forum_rate_limited', 'You are posting too quickly. Please wait and try again.'],
    forum_post_unavailable: [404, 'forum_post_not_found', 'Discussion was not found.'],
    forum_comment_unavailable: [404, 'forum_comment_not_found', 'Comment was not found.'],
    forum_post_locked: [409, 'forum_post_locked', 'This discussion is locked.'],
    profile_avatar_validation: [400, 'invalid_media', 'Profile photo is invalid.'],
    assistant_validation: [400, 'assistant_validation', 'Your message is invalid.'],
    assistant_disabled: [403, 'assistant_disabled', 'The assistant is disabled in your settings.'],
    assistant_rate_limited: [429, 'assistant_rate_limited', 'Please wait a moment before sending another message.'],
    invalid_report_reason: [400, 'invalid_report_reason', 'Report reason is invalid.'],
    cannot_report_own_content: [400, 'cannot_report_own_content', 'You cannot report your own content.'],
    permission_denied: [403, 'permission_denied', 'You do not have permission for this action.'],
  };
  const match = known[backendMessage];
  if (match) return new ApiError(...match);
  if (status === 401) return new ApiError(401, 'invalid_session', 'Your session is invalid or expired.');
  if (status === 403) return new ApiError(403, 'permission_denied', 'You do not have permission for this action.');
  return new ApiError(502, 'database_rejected_request', 'The database rejected the request.');
}

async function jsonBody(request) {
  const contentLength = Number(request.headers.get('Content-Length') ?? 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    throw new ApiError(413, 'request_too_large', 'Request body is too large.');
  }
  if (!(request.headers.get('Content-Type') ?? '').toLowerCase().includes('application/json')) {
    throw new ApiError(415, 'json_required', 'Content-Type must be application/json.');
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new ApiError(413, 'request_too_large', 'Request body is too large.');
  }
  try {
    const body = JSON.parse(text);
    if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error();
    return body;
  } catch (_) {
    throw new ApiError(400, 'invalid_json', 'Request body must be a JSON object.');
  }
}

function validateCreateEvent(body, allowRecurrence = true) {
  const requiredFields = [
    'title',
    'description',
    'category',
    'venue_name',
    'address',
    'latitude',
    'longitude',
    'start_at',
    'end_at',
    'max_participants',
  ];
  const optionalFields = [
    'beginner_friendly',
    'wheelchair_accessible',
    'event_setting',
    'event_language',
    'age_guidance',
    'what_to_bring',
    'status',
    'visibility',
    'repeat_interval',
    'repeat_count',
  ];
  exactOptionalKeys(body, requiredFields, optionalFields);

  const title = stringParameter(body.title, 'title', 3, 120);
  const description = stringParameter(body.description, 'description', 1, 2000);
  const category = stringParameter(body.category, 'category', 2, 60);
  const venueName = stringParameter(body.venue_name, 'venue_name', 2, 160);
  const address = stringParameter(body.address, 'address', 3, 300);
  const latitude = numberParameter(body.latitude, 'latitude', -90, 90);
  const longitude = numberParameter(body.longitude, 'longitude', -180, 180);
  const maxParticipants = integerParameter(body.max_participants, 'max_participants', 2, 500);
  const startAt = dateParameter(body.start_at, 'start_at');
  const endAt = dateParameter(body.end_at, 'end_at');
  if (startAt.getTime() <= Date.now() || endAt.getTime() <= startAt.getTime()) {
    throw new ApiError(400, 'event_validation', 'Event times are invalid.');
  }
  const beginnerFriendly = body.beginner_friendly ?? false;
  const wheelchairAccessible = body.wheelchair_accessible ?? false;
  if (typeof beginnerFriendly !== 'boolean' || typeof wheelchairAccessible !== 'boolean') {
    throw new ApiError(400, 'event_validation', 'Event accessibility details are invalid.');
  }
  const eventSetting = body.event_setting ?? 'unspecified';
  const ageGuidance = body.age_guidance ?? 'all_ages';
  if (typeof eventSetting !== 'string' || !EVENT_SETTINGS.has(eventSetting)) {
    throw new ApiError(400, 'event_validation', 'Event setting is invalid.');
  }
  if (typeof ageGuidance !== 'string' || !EVENT_AGE_GUIDANCE.has(ageGuidance)) {
    throw new ApiError(400, 'event_validation', 'Age guidance is invalid.');
  }
  const eventLanguage = optionalStringWithDefault(body.event_language, 'event_language', 80);
  const whatToBring = optionalStringWithDefault(body.what_to_bring, 'what_to_bring', 500);
  const status = body.status ?? 'published';
  const visibility = body.visibility ?? 'public';
  const repeatInterval = body.repeat_interval ?? 'none';
  const repeatCount = body.repeat_count ?? 1;
  if (typeof status !== 'string' || !EVENT_STATUSES.has(status)) {
    throw new ApiError(400, 'event_validation', 'Event status is invalid.');
  }
  if (typeof visibility !== 'string' || !EVENT_VISIBILITIES.has(visibility)) {
    throw new ApiError(400, 'event_validation', 'Event visibility is invalid.');
  }
  if (typeof repeatInterval !== 'string' || !EVENT_REPEAT_INTERVALS.has(repeatInterval)) {
    throw new ApiError(400, 'event_validation', 'Event repeat interval is invalid.');
  }
  if (!Number.isInteger(repeatCount) || repeatCount < 1 || repeatCount > 12) {
    throw new ApiError(400, 'event_validation', 'Event repeat count is invalid.');
  }
  if (
    (repeatInterval === 'none' && repeatCount !== 1) ||
    (repeatInterval !== 'none' && repeatCount < 2) ||
    (status === 'draft' && (repeatInterval !== 'none' || repeatCount !== 1)) ||
    (!allowRecurrence && (repeatInterval !== 'none' || repeatCount !== 1))
  ) {
    throw new ApiError(400, 'event_validation', 'Event recurrence is invalid.');
  }

  return {
    p_title: title,
    p_description: description,
    p_category: category,
    p_venue_name: venueName,
    p_address: address,
    p_latitude: latitude,
    p_longitude: longitude,
    p_start_at: startAt.toISOString(),
    p_end_at: endAt.toISOString(),
    p_max_participants: maxParticipants,
    p_beginner_friendly: beginnerFriendly,
    p_wheelchair_accessible: wheelchairAccessible,
    p_event_setting: eventSetting,
    p_event_language: eventLanguage,
    p_age_guidance: ageGuidance,
    p_what_to_bring: whatToBring,
    p_status: status,
    p_visibility: visibility,
    p_repeat_interval: repeatInterval,
    p_repeat_count: repeatCount,
  };
}

function validateSavedEventSearch(body) {
  exactOptionalKeys(body, [
    'name', 'interest', 'radius_km', 'category', 'date_filter', 'time_filter',
    'timezone_offset_minutes', 'spots_only', 'following_only',
  ], [
    'beginner_friendly_only', 'wheelchair_accessible_only', 'event_setting',
    'event_language', 'age_guidance', 'alerts_enabled',
  ]);
  const name = stringParameter(body.name, 'name', 1, 80);
  const interest = optionalStringWithDefault(body.interest, 'interest', 240);
  const radiusKm = numberParameter(body.radius_km, 'radius_km', 1, 100);
  const category = body.category === null
    ? null
    : stringParameter(body.category, 'category', 2, 60);
  if (typeof body.date_filter !== 'string' || !EVENT_DATE_FILTERS.has(body.date_filter)) {
    throw new ApiError(400, 'saved_search_validation', 'Saved search date is invalid.');
  }
  if (typeof body.time_filter !== 'string' || !EVENT_TIME_FILTERS.has(body.time_filter)) {
    throw new ApiError(400, 'saved_search_validation', 'Saved search time is invalid.');
  }
  const timezoneOffsetMinutes = integerParameter(
    body.timezone_offset_minutes,
    'timezone_offset_minutes',
    -840,
    840,
  );
  if (typeof body.spots_only !== 'boolean' || typeof body.following_only !== 'boolean') {
    throw new ApiError(400, 'saved_search_validation', 'Saved search filters are invalid.');
  }
  const beginnerFriendlyOnly = body.beginner_friendly_only ?? false;
  const wheelchairAccessibleOnly = body.wheelchair_accessible_only ?? false;
  const eventSetting = body.event_setting ?? 'any';
  const eventLanguage = optionalStringWithDefault(
    body.event_language,
    'event_language',
    80,
  );
  const ageGuidance = body.age_guidance ?? 'any';
  const alertsEnabled = body.alerts_enabled ?? true;
  if (
    typeof beginnerFriendlyOnly !== 'boolean' ||
    typeof wheelchairAccessibleOnly !== 'boolean' ||
    typeof eventSetting !== 'string' ||
    !EVENT_SETTING_FILTERS.has(eventSetting) ||
    typeof ageGuidance !== 'string' ||
    !EVENT_AGE_FILTERS.has(ageGuidance) ||
    typeof alertsEnabled !== 'boolean'
  ) {
    throw new ApiError(400, 'saved_search_validation', 'Saved search filters are invalid.');
  }
  return {
    p_name: name,
    p_interest: interest,
    p_radius_km: radiusKm,
    p_category: category,
    p_date_filter: body.date_filter,
    p_time_filter: body.time_filter,
    p_timezone_offset_minutes: timezoneOffsetMinutes,
    p_spots_only: body.spots_only,
    p_following_only: body.following_only,
    p_beginner_friendly_only: beginnerFriendlyOnly,
    p_wheelchair_accessible_only: wheelchairAccessibleOnly,
    p_event_setting: eventSetting,
    p_event_language: eventLanguage,
    p_age_guidance: ageGuidance,
    p_alerts_enabled: alertsEnabled,
  };
}

function validateCreateForumPost(body) {
  exactOptionalKeys(
    body,
    ['title', 'body', 'category'],
    ['image_token', 'place_name', 'place_address', 'poll_options'],
  );
  const title = stringParameter(body.title, 'title', 5, 120);
  const postBody = stringParameter(body.body, 'body', 10, 4000);
  const category = stringParameter(body.category, 'category', 1, 40);
  if (!FORUM_CATEGORIES.has(category)) {
    throw new ApiError(400, 'forum_validation', 'Discussion category is invalid.');
  }
  const imageToken = body.image_token === undefined || body.image_token === null
    ? null
    : uuidParameter(body.image_token, 'image_token');
  const placeName = optionalNullableStringParameter(body, 'place_name', 2, 120);
  const placeAddress = optionalNullableStringParameter(body, 'place_address', 3, 300);
  if ((placeName === null) !== (placeAddress === null)) {
    throw new ApiError(400, 'invalid_parameter', 'Place name and address must be provided together.');
  }
  return {title, body: postBody, category, imageToken, placeName, placeAddress, pollOptions: validatePollOptions(body.poll_options)};
}

function validateEventFeedback(body) {
  exactKeys(body, ['attended', 'rating', 'comment']);
  if (typeof body.attended !== 'boolean') {
    throw new ApiError(400, 'feedback_validation', 'Attendance is invalid.');
  }
  const rating = body.rating === null
    ? null
    : integerParameter(body.rating, 'rating', 1, 5);
  if ((body.attended && rating === null) || (!body.attended && rating !== null)) {
    throw new ApiError(400, 'feedback_validation', 'Rating is invalid.');
  }
  if (typeof body.comment !== 'string' || body.comment.trim().length > 1000) {
    throw new ApiError(400, 'feedback_validation', 'Feedback comment is invalid.');
  }
  return {
    p_attended: body.attended,
    p_rating: rating,
    p_comment: body.comment.trim(),
  };
}

function validateForumReport(body) {
  exactKeys(body, ['reason']);
  if (typeof body.reason !== 'string' || !FORUM_REPORT_REASONS.has(body.reason)) {
    throw new ApiError(400, 'invalid_report_reason', 'Report reason is invalid.');
  }
  return body.reason;
}

function validateAssistantChat(body) {
  exactKeys(body, ['message', 'latitude', 'longitude', 'radius_km']);
  const message = stringParameter(body.message, 'message', 1, 600);
  const latitude = nullableNumberParameter(body.latitude, 'latitude', -90, 90);
  const longitude = nullableNumberParameter(body.longitude, 'longitude', -180, 180);
  if ((latitude === null) !== (longitude === null)) {
    throw new ApiError(400, 'invalid_parameter', 'Location is invalid.');
  }
  const radiusKm = numberParameter(body.radius_km, 'radius_km', 1, 100);
  return {message, latitude, longitude, radiusKm};
}

function validateAssistantEventDraft(body) {
  exactKeys(body, ['prompt', 'locale']);
  return {
    prompt: stringParameter(body.prompt, 'prompt', 10, 1000),
    locale: stringParameter(body.locale, 'locale', 2, 35),
  };
}

function validateOnboarding(body) {
  exactKeys(body, [
    'interests',
    'accessibility_preferences',
    'radius_km',
    'latitude',
    'longitude',
  ]);
  const interests = stringArrayParameter(body.interests, 'interests', 12, 60);
  const accessibility = stringArrayParameter(
    body.accessibility_preferences,
    'accessibility_preferences',
    8,
    40,
  );
  if (accessibility.some((value) => !ACCESSIBILITY_PREFERENCES.has(value))) {
    throw new ApiError(400, 'onboarding_validation', 'Accessibility preferences are invalid.');
  }
  const latitude = nullableNumberParameter(body.latitude, 'latitude', -90, 90);
  const longitude = nullableNumberParameter(body.longitude, 'longitude', -180, 180);
  if ((latitude === null) !== (longitude === null)) {
    throw new ApiError(400, 'onboarding_validation', 'Approximate location is invalid.');
  }
  return {
    p_interests: interests,
    p_accessibility_preferences: accessibility,
    p_radius_km: numberParameter(body.radius_km, 'radius_km', 1, 100),
    p_latitude: latitude,
    p_longitude: longitude,
  };
}

function validateNotificationPreferences(body) {
  exactKeys(body, [
    'push_enabled',
    'reminders_enabled',
    'announcements_enabled',
    'discussion_enabled',
    'recommendations_enabled',
    'quiet_start_minute',
    'quiet_end_minute',
    'timezone_offset_minutes',
  ]);
  for (const key of [
    'push_enabled',
    'reminders_enabled',
    'announcements_enabled',
    'discussion_enabled',
    'recommendations_enabled',
  ]) {
    if (typeof body[key] !== 'boolean') {
      throw new ApiError(400, 'notification_preferences_validation', 'Notification preferences are invalid.');
    }
  }
  const quietStart = body.quiet_start_minute === null
    ? null
    : integerParameter(body.quiet_start_minute, 'quiet_start_minute', 0, 1439);
  const quietEnd = body.quiet_end_minute === null
    ? null
    : integerParameter(body.quiet_end_minute, 'quiet_end_minute', 0, 1439);
  if ((quietStart === null) !== (quietEnd === null)) {
    throw new ApiError(400, 'notification_preferences_validation', 'Quiet hours are invalid.');
  }
  return {
    p_push_enabled: body.push_enabled,
    p_reminders_enabled: body.reminders_enabled,
    p_announcements_enabled: body.announcements_enabled,
    p_discussion_enabled: body.discussion_enabled,
    p_recommendations_enabled: body.recommendations_enabled,
    p_quiet_start_minute: quietStart,
    p_quiet_end_minute: quietEnd,
    p_timezone_offset_minutes: integerParameter(
      body.timezone_offset_minutes,
      'timezone_offset_minutes',
      -840,
      840,
    ),
  };
}

function validateRecommendationPreferences(body) {
  exactKeys(body, ['enabled', 'hidden_categories']);
  if (typeof body.enabled !== 'boolean') {
    throw new ApiError(400, 'recommendation_preferences_validation', 'Recommendation preferences are invalid.');
  }
  return {
    p_enabled: body.enabled,
    p_hidden_categories: stringArrayParameter(
      body.hidden_categories,
      'hidden_categories',
      24,
      60,
    ),
  };
}

function validateEventQualityInput(body) {
  exactKeys(body, [
    'title',
    'description',
    'category',
    'venue_name',
    'address',
    'start_at',
    'end_at',
    'max_participants',
    'what_to_bring',
  ]);
  return {
    title: optionalStringWithDefault(body.title, 'title', 120),
    description: optionalStringWithDefault(body.description, 'description', 2000),
    category: optionalStringWithDefault(body.category, 'category', 60),
    venue_name: optionalStringWithDefault(body.venue_name, 'venue_name', 160),
    address: optionalStringWithDefault(body.address, 'address', 300),
    start_at: optionalStringWithDefault(body.start_at, 'start_at', 40),
    end_at: optionalStringWithDefault(body.end_at, 'end_at', 40),
    max_participants: integerParameter(body.max_participants, 'max_participants', 2, 500),
    what_to_bring: optionalStringWithDefault(body.what_to_bring, 'what_to_bring', 500),
  };
}

function validAssistantEventDraft(draft) {
  if (!draft || Array.isArray(draft) || typeof draft !== 'object') return false;
  const keys = Object.keys(draft).sort();
  const expected = [
    'age_guidance',
    'beginner_friendly',
    'category',
    'description',
    'event_language',
    'event_setting',
    'title',
    'what_to_bring',
  ];
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    typeof draft.title === 'string' && draft.title.trim().length >= 3 &&
    draft.title.length <= 120 && typeof draft.description === 'string' &&
    draft.description.trim().length >= 1 && draft.description.length <= 1200 &&
    EVENT_CATEGORIES.has(draft.category) &&
    typeof draft.beginner_friendly === 'boolean' &&
    EVENT_SETTINGS.has(draft.event_setting) &&
    typeof draft.event_language === 'string' && draft.event_language.length <= 80 &&
    EVENT_AGE_GUIDANCE.has(draft.age_guidance) &&
    typeof draft.what_to_bring === 'string' && draft.what_to_bring.length <= 500;
}

function validDiscussionSummary(summary) {
  if (!summary || Array.isArray(summary) || typeof summary !== 'object') return false;
  const keys = Object.keys(summary).sort();
  return keys.length === 2 && keys[0] === 'action_items' && keys[1] === 'summary' &&
    typeof summary.summary === 'string' && summary.summary.trim().length >= 1 &&
    summary.summary.length <= 2000 && Array.isArray(summary.action_items) &&
    summary.action_items.length <= 8 && summary.action_items.every((item) =>
      typeof item === 'string' && item.trim().length >= 1 && item.length <= 240
    );
}

function validNaturalEventFilters(filters) {
  if (!exactObjectKeys(filters, [
    'interest', 'category', 'date_filter', 'time_filter', 'spots_only',
    'following_only', 'beginner_friendly_only', 'wheelchair_accessible_only',
    'event_setting', 'event_language', 'age_guidance', 'radius_km',
  ])) return false;
  return (filters.interest === null || validStringValue(filters.interest, 1, 240)) &&
    (filters.category === null || EVENT_CATEGORIES.has(filters.category)) &&
    EVENT_DATE_FILTERS.has(filters.date_filter) &&
    EVENT_TIME_FILTERS.has(filters.time_filter) &&
    typeof filters.spots_only === 'boolean' &&
    typeof filters.following_only === 'boolean' &&
    typeof filters.beginner_friendly_only === 'boolean' &&
    typeof filters.wheelchair_accessible_only === 'boolean' &&
    EVENT_SETTING_FILTERS.has(filters.event_setting) &&
    typeof filters.event_language === 'string' && filters.event_language.length <= 80 &&
    EVENT_AGE_FILTERS.has(filters.age_guidance) &&
    (filters.radius_km === null || (
      typeof filters.radius_km === 'number' && Number.isFinite(filters.radius_km) &&
      filters.radius_km >= 1 && filters.radius_km <= 100
    ));
}

function validEventQuality(quality) {
  return exactObjectKeys(quality, ['ready', 'issues']) &&
    typeof quality.ready === 'boolean' && Array.isArray(quality.issues) &&
    quality.issues.length <= 12 && quality.issues.every((issue) =>
      exactObjectKeys(issue, ['field', 'severity', 'message']) &&
      validStringValue(issue.field, 1, 40) &&
      ['info', 'warning', 'error'].includes(issue.severity) &&
      validStringValue(issue.message, 1, 240)
    );
}

function validModerationTriage(result, reports) {
  if (!exactObjectKeys(result, ['priorities']) || !Array.isArray(result.priorities)) {
    return false;
  }
  const allowed = new Set(reports.map((report) => report?.report_id));
  const seen = new Set();
  return result.priorities.length === Math.min(reports.length, 50) &&
    result.priorities.every((item) => {
      const valid = exactObjectKeys(item, ['report_id', 'priority', 'reason']) &&
        typeof item.report_id === 'string' && allowed.has(item.report_id) &&
        !seen.has(item.report_id) && ['high', 'medium', 'low'].includes(item.priority) &&
        validStringValue(item.reason, 1, 240);
      seen.add(item?.report_id);
      return valid;
    });
}

function exactObjectKeys(value, expected) {
  if (!value || Array.isArray(value) || typeof value !== 'object') return false;
  const keys = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return keys.length === wanted.length &&
    keys.every((key, index) => key === wanted[index]);
}

function validStringValue(value, minimum, maximum) {
  return typeof value === 'string' && value.trim().length >= minimum &&
    value.length <= maximum;
}

function exactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw new ApiError(400, 'unexpected_fields', 'Request contains missing or unexpected fields.');
  }
}

function exactOptionalKeys(value, required, optional) {
  const actual = Object.keys(value);
  const allowed = new Set([...required, ...optional]);
  if (
    required.some((key) => !Object.hasOwn(value, key)) ||
    actual.some((key) => !allowed.has(key))
  ) {
    throw new ApiError(400, 'unexpected_fields', 'Request contains missing or unexpected fields.');
  }
}

function optionalNullableStringParameter(value, name, minimum, maximum) {
  if (!Object.hasOwn(value, name) || value[name] === null) return null;
  return stringParameter(value[name], name, minimum, maximum);
}

function optionalSearchParameter(value, name, maximum) {
  if (value === null) return null;
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return trimmed;
}

function optionalStringWithDefault(value, name, maximum) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return trimmed;
}

function stringArrayParameter(value, name, maximumItems, maximumLength) {
  if (!Array.isArray(value) || value.length > maximumItems) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const normalized = value.map((item) =>
    stringParameter(item, name, 1, maximumLength)
  );
  return [...new Set(normalized)];
}

function booleanQueryParameter(value, name) {
  if (value === null || value === '') return false;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
}

function enumQueryParameter(value, name, values, fallback) {
  if (value === null || value === '') return fallback;
  if (!values.has(value)) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return value;
}

function optionalQueryDateParameter(value, name) {
  if (value === null || value.trim() === '') return null;
  return dateParameter(value, name);
}

function stringParameter(value, name, minimum, maximum) {
  if (typeof value !== 'string') {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < minimum || trimmed.length > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return trimmed;
}

function numberParameter(value, name, minimum, maximum) {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function nullableNumberParameter(value, name, minimum, maximum) {
  if (value === null) return null;
  return numberParameter(value, name, minimum, maximum);
}

function nullableQueryNumberParameter(value, name, minimum, maximum) {
  if (value === null || value.trim().length === 0) return null;
  return numberParameter(value, name, minimum, maximum);
}

function languageParameter(value) {
  if (value === null || value.trim().length === 0) return null;
  const normalized = value.trim().toLowerCase();
  if (!/^[a-z]{2}$/.test(normalized)) {
    throw new ApiError(400, 'invalid_parameter', 'language is invalid.');
  }
  return normalized;
}

function integerParameter(value, name, minimum, maximum) {
  const parsed = numberParameter(value, name, minimum, maximum);
  if (!Number.isInteger(parsed)) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function uuidParameter(value, name) {
  if (typeof value !== 'string' || !UUID_PATTERN.test(value)) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return value;
}

function jpegExpectedLength(request) {
  const contentType = (request.headers.get('Content-Type') ?? '')
    .split(';', 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== 'image/jpeg') {
    throw new ApiError(415, 'jpeg_required', 'Media must be a JPEG image.');
  }

  const rawLength = request.headers.get('Content-Length');
  if (rawLength === null) {
    throw new ApiError(411, 'content_length_required', 'Media size is required.');
  }
  const contentLength = Number(rawLength);
  if (!Number.isInteger(contentLength) || contentLength < 1) {
    throw new ApiError(400, 'invalid_media', 'Media is empty or invalid.');
  }
  if (contentLength > MAX_MEDIA_BYTES) {
    throw new ApiError(413, 'media_too_large', 'Media must be 5 MiB or smaller.');
  }
  if (request.body === null) {
    throw new ApiError(400, 'invalid_media', 'Media is empty or invalid.');
  }
  return contentLength;
}

async function putUploadedJpeg(bucket, key, request, customMetadata) {
  const expectedLength = jpegExpectedLength(request);
  const options = {
    httpMetadata: {contentType: 'image/jpeg'},
    customMetadata,
  };

  if (typeof FixedLengthStream === 'function') {
    const fixedLength = new FixedLengthStream(expectedLength);
    const validation = new TransformStream(jpegValidationTransformer(expectedLength));
    const pump = request.body.pipeThrough(validation).pipeTo(fixedLength.writable);
    const put = bucket.put(key, fixedLength.readable, options);
    const [pumpResult, putResult] = await Promise.allSettled([pump, put]);
    if (pumpResult.status === 'rejected' || putResult.status === 'rejected') {
      await deleteMediaObject(bucket, key);
      if (pumpResult.status === 'rejected' && pumpResult.reason instanceof ApiError) {
        throw pumpResult.reason;
      }
      throw new ApiError(503, 'media_unavailable', 'Media storage is temporarily unavailable.');
    }
    return;
  }

  // Node's test runtime does not expose Cloudflare's FixedLengthStream. Keep
  // equivalent actual-byte validation here; production takes the streaming path.
  const bytes = new Uint8Array(await request.arrayBuffer());
  validateJpegBytes(bytes, expectedLength);
  try {
    await bucket.put(key, bytes, options);
  } catch (_) {
    throw new ApiError(503, 'media_unavailable', 'Media storage is temporarily unavailable.');
  }
}

function jpegValidationTransformer(expectedLength) {
  let byteLength = 0;
  const first = [];
  let penultimate = -1;
  let last = -1;

  return {
    transform(chunk, controller) {
      const bytes = chunk instanceof Uint8Array ? chunk : new Uint8Array(chunk);
      byteLength += bytes.byteLength;
      if (byteLength > MAX_MEDIA_BYTES || byteLength > expectedLength) {
        throw new ApiError(413, 'media_too_large', 'Media must be 5 MiB or smaller.');
      }
      for (const byte of bytes) {
        if (first.length < 3) first.push(byte);
        penultimate = last;
        last = byte;
      }
      controller.enqueue(bytes);
    },
    flush() {
      if (
        byteLength !== expectedLength ||
        byteLength < 4 ||
        first[0] !== 0xff ||
        first[1] !== 0xd8 ||
        first[2] !== 0xff ||
        penultimate !== 0xff ||
        last !== 0xd9
      ) {
        throw new ApiError(400, 'invalid_media', 'Media is not a valid JPEG image.');
      }
    },
  };
}

function validateJpegBytes(bytes, expectedLength) {
  if (bytes.byteLength > MAX_MEDIA_BYTES || bytes.byteLength > expectedLength) {
    throw new ApiError(413, 'media_too_large', 'Media must be 5 MiB or smaller.');
  }
  if (
    bytes.byteLength !== expectedLength ||
    bytes.byteLength < 4 ||
    bytes[0] !== 0xff ||
    bytes[1] !== 0xd8 ||
    bytes[2] !== 0xff ||
    bytes.at(-2) !== 0xff ||
    bytes.at(-1) !== 0xd9
  ) {
    throw new ApiError(400, 'invalid_media', 'Media is not a valid JPEG image.');
  }
}

async function putMediaObject(bucket, key, body, customMetadata, knownLength = null) {
  const options = {
    httpMetadata: {contentType: 'image/jpeg'},
    customMetadata,
  };
  try {
    if (
      typeof FixedLengthStream === 'function' &&
      Number.isInteger(knownLength) &&
      knownLength >= 0 &&
      typeof body?.pipeTo === 'function'
    ) {
      const fixedLength = new FixedLengthStream(knownLength);
      const pump = body.pipeTo(fixedLength.writable);
      const put = bucket.put(key, fixedLength.readable, options);
      const [pumpResult, putResult] = await Promise.allSettled([pump, put]);
      if (pumpResult.status === 'rejected' || putResult.status === 'rejected') {
        throw new Error('R2 stream copy failed.');
      }
      return;
    }
    await bucket.put(key, body, options);
  } catch (_) {
    await deleteMediaObject(bucket, key);
    throw new ApiError(503, 'media_unavailable', 'Media storage is temporarily unavailable.');
  }
}

async function getMediaObject(bucket, key) {
  try {
    return await bucket.get(key);
  } catch (_) {
    throw new ApiError(503, 'media_unavailable', 'Media storage is temporarily unavailable.');
  }
}

async function deleteMediaObject(bucket, key) {
  try {
    await bucket.delete(key);
  } catch (_) {
    // Objects are private and inaccessible without a database reference. Staged
    // uploads also have a lifecycle fallback, so cleanup failure is non-fatal.
  }
}

function isDefiniteClientRejection(error) {
  return error instanceof ApiError && error.status >= 400 && error.status < 500;
}

function isMediaKey(value, prefix) {
  return typeof value === 'string' && new RegExp(
    `^${prefix}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.jpg$`,
    'i',
  ).test(value);
}

function isOwnedMediaKey(value, prefix, userId) {
  return isMediaKey(value, prefix) && value.startsWith(`${prefix}/${userId}/`);
}

function dateParameter(value, name) {
  if (typeof value !== 'string') {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new ApiError(400, 'invalid_parameter', `${name} is invalid.`);
  }
  return parsed;
}

function filterDiscoveredEvents(events, filters) {
  const {
    category,
    startFrom,
    startBefore,
    timeFilter,
    spotsOnly,
    followingOnly,
    followedIds,
    timezoneOffsetMinutes,
    allowedEventIds,
  } = filters;
  return events.filter((event) => {
    if (!event || typeof event !== 'object') return false;
    if (allowedEventIds !== null && !allowedEventIds.has(event.id)) return false;
    if (category !== null && event.category !== category) return false;
    if (followingOnly && !followedIds.has(event.organizer_id)) return false;

    let start = null;
    if (startFrom !== null || startBefore !== null || timeFilter !== 'any') {
      start = new Date(event.start_at);
      if (!Number.isFinite(start.getTime())) return false;
      if (startFrom !== null && start < startFrom) return false;
      if (startBefore !== null && start >= startBefore) return false;
    }

    if (spotsOnly) {
      const joined = Number(event.joined_count);
      const capacity = Number(event.max_participants);
      if (!Number.isFinite(joined) || !Number.isFinite(capacity) || joined >= capacity) {
        return false;
      }
    }

    if (timeFilter !== 'any') {
      const localStart = new Date(start.getTime() + timezoneOffsetMinutes * 60_000);
      const hour = localStart.getUTCHours();
      if (timeFilter === 'morning' && (hour < 5 || hour >= 12)) return false;
      if (timeFilter === 'afternoon' && (hour < 12 || hour >= 17)) return false;
      if (timeFilter === 'evening' && (hour < 17 || hour >= 24)) return false;
    }
    return true;
  });
}

function recommendationReason(event, interest, recommendationsEnabled) {
  if (typeof interest === 'string' && interest.trim().length > 0) {
    return `Matches “${interest.trim().slice(0, 80)}”`;
  }
  if (!recommendationsEnabled) return 'Near your chosen area';
  if (typeof event?.recommendation_reason === 'string' &&
      event.recommendation_reason.trim().length > 0 &&
      event.recommendation_reason.length <= 160) {
    return event.recommendation_reason.trim();
  }
  if (typeof event?.category === 'string' && event.category.trim().length > 0) {
    return `Recommended in ${event.category.trim().slice(0, 60)}`;
  }
  return 'Recommended near you';
}

function assistantEventSearch(message) {
  const normalized = message.toLowerCase();
  const categories = [
    ['language exchange', /\b(language exchange|language practice|practice language)\b/],
    ['board games', /\b(board game|board games|tabletop)\b/],
    ['badminton', /\bbadminton\b/],
    ['running', /\b(run|running|jog|jogging)\b/],
    ['padel', /\bpadel\b/],
    ['hiking', /\b(hike|hiking|trail|walking group)\b/],
    ['coffee', /\b(coffee|cafe|café)\b/],
    ['photography', /\b(photo|photos|photography|camera)\b/],
    ['startup', /\b(startup|founder|entrepreneur)\b/],
    ['cycling', /\b(cycle|cycling|bike ride|biking)\b/],
  ];
  const locationIntent = /\b(near me|nearby|around me|close by|in my area|local events?|what(?:'s| is) on)\b/.test(normalized);
  const category = categories.find(([, pattern]) => pattern.test(normalized));
  const unknownType = normalized.match(
    /\b(?:any|find|show me|looking for|are there|is there)\s+([a-z0-9 -]{2,36}?)\s+(?:events?|meetups?|groups?)\b/,
  )?.[1]?.trim();
  return {
    shouldSearch: locationIntent || category !== undefined || unknownType !== undefined,
    query: category?.[0] ?? unknownType ?? null,
  };
}

function interleaveCommunityFeed(recommendedPosts, latestPosts) {
  const output = [];
  const usedIds = new Set();
  let recommendationIndex = 0;
  let latestIndex = 0;

  while (output.length < COMMUNITY_FEED_LIMIT) {
    const lengthBeforeBlock = output.length;
    let recommendationsAdded = 0;
    while (
      recommendationsAdded < COMMUNITY_RECOMMENDATION_BLOCK &&
      recommendationIndex < recommendedPosts.length &&
      output.length < COMMUNITY_FEED_LIMIT
    ) {
      const post = recommendedPosts[recommendationIndex];
      recommendationIndex += 1;
      if (
        !post ||
        typeof post !== 'object' ||
        typeof post.id !== 'string' ||
        usedIds.has(post.id)
      ) {
        continue;
      }
      usedIds.add(post.id);
      output.push(post);
      recommendationsAdded += 1;
    }

    while (
      latestIndex < latestPosts.length &&
      output.length < COMMUNITY_FEED_LIMIT
    ) {
      const post = latestPosts[latestIndex];
      latestIndex += 1;
      if (
        !post ||
        typeof post !== 'object' ||
        typeof post.id !== 'string' ||
        usedIds.has(post.id)
      ) {
        continue;
      }
      usedIds.add(post.id);
      output.push(post);
      break;
    }

    if (output.length === lengthBeforeBlock) break;
  }
  return output;
}

async function rerankRecommendations({
  env,
  authorization,
  surface,
  candidates,
  defer,
}) {
  if (
    !env.ASSISTANT_MODEL ||
    typeof env.ASSISTANT_MODEL.fetch !== 'function' ||
    !Array.isArray(candidates) ||
    candidates.length < 2
  ) {
    return candidates;
  }

  const shortlist = candidates.slice(0, RECOMMENDATION_RERANK_LIMIT);
  if (
    shortlist.length < 2 ||
    shortlist.some((candidate) =>
      !candidate ||
      typeof candidate !== 'object' ||
      typeof candidate.id !== 'string' ||
      !UUID_PATTERN.test(candidate.id)
    ) ||
    new Set(shortlist.map((candidate) => candidate.id)).size !== shortlist.length
  ) {
    return candidates;
  }

  let state;
  try {
    state = await supabaseRpc(
      env,
      authorization,
      'get_ai_recommendation_state',
      {
        p_surface: surface,
        p_candidate_ids: shortlist.map((candidate) => candidate.id),
      },
    );
  } catch (_) {
    return candidates;
  }
  if (
    !state ||
    Array.isArray(state) ||
    typeof state !== 'object' ||
    state.eligible !== true ||
    typeof state.cache_key !== 'string' ||
    !/^[0-9a-f]{32}$/.test(state.cache_key)
  ) {
    return candidates;
  }

  const cached = recommendationOrder(state.ranked_ids, shortlist);
  if (cached !== null) {
    return [...cached, ...candidates.slice(shortlist.length)];
  }
  if (
    typeof state.preference_query !== 'string' ||
    state.preference_query.length < 1 ||
    state.preference_query.length > 4000
  ) {
    return candidates;
  }

  const modelCandidates = shortlist.map((candidate) => ({
    id: candidate.id,
    document: recommendationDocument(surface, candidate),
  }));
  if (modelCandidates.some((candidate) => candidate.document.length < 1)) {
    return candidates;
  }

  let claimed;
  try {
    claimed = await supabaseRpc(
      env,
      authorization,
      'claim_ai_recommendation_rerank',
      {p_surface: surface},
    );
  } catch (_) {
    return candidates;
  }
  if (claimed !== true) return candidates;

  let response;
  try {
    response = await env.ASSISTANT_MODEL.fetch(new Request('https://assistant.internal/rerank', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        surface,
        preference_query: recommendationQuery(surface, state.preference_query),
        candidates: modelCandidates,
      }),
    }));
  } catch (_) {
    return candidates;
  }
  if (!response.ok) return candidates;

  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    return candidates;
  }
  const blended = blendRecommendationRanking(payload?.ranking, shortlist);
  if (blended === null) return candidates;

  if (defer !== null) {
    defer(
      supabaseRpc(
        env,
        authorization,
        'set_ai_recommendation_cache',
        {
          p_surface: surface,
          p_cache_key: state.cache_key,
          p_ranked_ids: blended.map((candidate) => candidate.id),
        },
      ).catch(() => undefined),
    );
  }
  return [...blended, ...candidates.slice(shortlist.length)];
}

function recommendationQuery(surface, preferenceSummary) {
  const purpose = surface === 'event'
    ? 'Rank public events this anonymous user is most likely to join.'
    : 'Rank public community discussions this anonymous user is most likely to value.';
  return [
    purpose,
    'Use the recent anonymous interactions below as preference evidence; stronger actions indicate stronger interest.',
    preferenceSummary,
  ].join('\n').slice(0, 4000);
}

function recommendationDocument(surface, candidate) {
  const fields = surface === 'event'
    ? {
        Type: 'Event',
        Title: candidate.title,
        Category: candidate.category,
        Venue: candidate.venue_name,
        Starts: candidate.start_at,
        Description: candidate.description,
      }
    : {
        Type: 'Community discussion',
        Title: candidate.title,
        Topic: candidate.category,
        Place: candidate.place_name,
        Posted: candidate.created_at,
        Content: candidate.body,
      };
  return Object.entries(fields)
    .filter(([, value]) => typeof value === 'string' && value.trim().length > 0)
    .map(([label, value]) => `${label}: ${value.trim()}`)
    .join('\n')
    .slice(0, 1200);
}

function recommendationOrder(rankedIds, shortlist) {
  if (
    !Array.isArray(rankedIds) ||
    rankedIds.length !== shortlist.length ||
    rankedIds.some((id) => typeof id !== 'string') ||
    new Set(rankedIds).size !== shortlist.length
  ) {
    return null;
  }
  const byId = new Map(shortlist.map((candidate) => [candidate.id, candidate]));
  if (rankedIds.some((id) => !byId.has(id))) return null;
  return rankedIds.map((id) => byId.get(id));
}

function blendRecommendationRanking(ranking, shortlist) {
  if (!Array.isArray(ranking) || ranking.length !== shortlist.length) return null;
  const byId = new Map(shortlist.map((candidate, index) => [candidate.id, {candidate, index}]));
  const seen = new Set();
  const scored = [];
  for (const result of ranking) {
    const match = typeof result?.id === 'string' ? byId.get(result.id) : null;
    if (
      match === null ||
      match === undefined ||
      seen.has(result.id) ||
      typeof result.score !== 'number' ||
      !Number.isFinite(result.score)
    ) {
      return null;
    }
    seen.add(result.id);
    scored.push({...match, aiScore: result.score});
  }

  const minimum = Math.min(...scored.map((item) => item.aiScore));
  const maximum = Math.max(...scored.map((item) => item.aiScore));
  const spread = maximum - minimum;
  // Min-max scaling would otherwise turn nearly identical model scores into
  // a confident preference and erase the useful interest/distance ordering.
  if (spread < 0.05) return shortlist;
  return scored
    .map((item) => {
      const normalizedAi = spread > Number.EPSILON
        ? (item.aiScore - minimum) / spread
        : 0.5;
      const normalizedBase = (shortlist.length - item.index) / shortlist.length;
      return {
        ...item,
        blendedScore:
          normalizedAi * RECOMMENDATION_AI_WEIGHT +
          normalizedBase * (1 - RECOMMENDATION_AI_WEIGHT),
      };
    })
    .sort((left, right) =>
      right.blendedScore - left.blendedScore || left.index - right.index
    )
    .map((item) => item.candidate);
}

async function openRouterChat({
  env,
  history,
  eventMatches,
  eventSearchRequested,
  locationAvailable,
}) {
  if (!env.ASSISTANT_MODEL || typeof env.ASSISTANT_MODEL.fetch !== 'function') {
    throw new ApiError(503, 'assistant_not_configured', 'The assistant is not configured.');
  }
  const messages = history
    .filter((row) => row?.role === 'user' || row?.role === 'assistant')
    .filter((row) => typeof row.content === 'string' && row.content.length <= 4000)
    .slice(-ASSISTANT_HISTORY_LIMIT)
    .map((row) => ({role: row.role, content: row.content}));

  let response;
  try {
    response = await env.ASSISTANT_MODEL.fetch(new Request('https://assistant.internal/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        history: messages,
        event_matches: eventMatches.slice(0, 8),
        event_search_requested: eventSearchRequested,
        location_available: locationAvailable,
      }),
    }));
  } catch (_) {
    throw new ApiError(503, 'assistant_unavailable', 'The assistant is temporarily unavailable.');
  }
  if (!response.ok) {
    const status = response.status === 429 ? 429 : 503;
    const code = response.status === 429 ? 'assistant_busy' : 'assistant_unavailable';
    throw new ApiError(status, code, 'The assistant is temporarily unavailable.');
  }

  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid response.');
  }
  const answer = payload?.answer;
  if (typeof answer !== 'string' || answer.trim().length < 1 || answer.trim().length > 4000) {
    throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid response.');
  }
  return answer.trim();
}

async function claimAssistantTool(env, authorization, tool) {
  const claimed = await supabaseRpc(
    env,
    authorization,
    'claim_ai_tool_use',
    {p_tool: tool},
  );
  if (claimed !== true) {
    throw new ApiError(
      429,
      'assistant_rate_limited',
      'You have reached the hourly limit for this AI helper.',
    );
  }
}

async function callAssistantTool(env, path, input) {
  if (!env.ASSISTANT_MODEL || typeof env.ASSISTANT_MODEL.fetch !== 'function') {
    throw new ApiError(503, 'assistant_not_configured', 'The assistant is not configured.');
  }
  let response;
  try {
    response = await env.ASSISTANT_MODEL.fetch(
      new Request(`https://assistant.internal/${path}`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(input),
      }),
    );
  } catch (_) {
    throw new ApiError(503, 'assistant_unavailable', 'The assistant is temporarily unavailable.');
  }
  if (!response.ok) {
    const status = response.status === 429 ? 429 : 503;
    const code = response.status === 429 ? 'assistant_busy' : 'assistant_unavailable';
    throw new ApiError(status, code, 'The assistant is temporarily unavailable.');
  }
  try {
    const payload = await response.json();
    if (!payload || Array.isArray(payload) || typeof payload !== 'object') {
      throw new Error('invalid response');
    }
    return payload;
  } catch (_) {
    throw new ApiError(502, 'invalid_model_response', 'The assistant returned an invalid response.');
  }
}

function semanticDocument(fields) {
  return Object.entries(fields)
    .filter(([, value]) => typeof value === 'string' && value.trim().length > 0)
    .map(([label, value]) => `${label}: ${value.trim()}`)
    .join('\n')
    .slice(0, 4000);
}

async function generateEmbedding(env, authorization, input) {
  let response;
  try {
    response = await fetch(`${trimSlash(env.SUPABASE_URL)}/functions/v1/embed`, {
      method: 'POST',
      headers: supabaseHeaders(env, authorization),
      body: JSON.stringify({input}),
      signal: AbortSignal.timeout(15000),
    });
  } catch (_) {
    throw new ApiError(503, 'semantic_search_unavailable', 'Interest search is temporarily unavailable.');
  }
  if (!response.ok) {
    throw new ApiError(503, 'semantic_search_unavailable', 'Interest search is temporarily unavailable.');
  }

  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    throw new ApiError(502, 'invalid_backend_response', 'The embedding service returned invalid data.');
  }
  const embedding = payload?.embedding;
  if (
    !Array.isArray(embedding) ||
    embedding.length !== 384 ||
    embedding.some((value) => typeof value !== 'number' || !Number.isFinite(value))
  ) {
    throw new ApiError(502, 'invalid_backend_response', 'The embedding service returned invalid data.');
  }
  return embedding;
}

async function indexCreatedContent({env, authorization, rpc, idField, id, input}) {
  try {
    const embedding = await generateEmbedding(env, authorization, input);
    await supabaseRpc(env, authorization, rpc, {
      [idField]: id,
      p_embedding: embedding,
    });
  } catch (_) {
    // Search indexing is best-effort. Publishing must not fail if inference is
    // briefly unavailable; a later backfill can safely fill the NULL vector.
  }
}

function supabaseHeaders(env, authorization) {
  return {
    apikey: env.SUPABASE_PUBLISHABLE_KEY,
    Authorization: authorization,
    'Content-Type': 'application/json',
  };
}

function trimSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function responseHeaders(requestId, cors) {
  return {
    ...cors,
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Request-Id': requestId,
  };
}

function mediaResponse(object, requestId, cors) {
  const headers = {
    ...cors,
    'Cache-Control': 'private, no-store',
    'Content-Type': 'image/jpeg',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Request-Id': requestId,
  };
  if (Number.isInteger(object.size) && object.size >= 0) {
    headers['Content-Length'] = String(object.size);
  }
  if (typeof object.httpEtag === 'string' && object.httpEtag.length > 0) {
    headers.ETag = object.httpEtag;
  }
  return new Response(object.body, {status: 200, headers});
}

function jsonResponse(payload, status, requestId, cors) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: responseHeaders(requestId, cors),
  });
}

function validatePollOptions(value) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value) || value.length < 2 || value.length > 3) {
    throw new ApiError(400, 'poll_validation', 'Choose two or three possible dates.');
  }
  const seen = new Set();
  return value.map(option => {
    exactKeys(option, ['start_at', 'end_at']);
    const start = dateParameter(option.start_at, 'start_at');
    const end = dateParameter(option.end_at, 'end_at');
    if (start <= new Date() || start.getTime() > Date.now() + 366 * 86400000 || end <= start || end - start > 86400000 || seen.has(start.toISOString())) {
      throw new ApiError(400, 'poll_validation', 'Choose different future dates, each lasting at most one day.');
    }
    seen.add(start.toISOString());
    return {start_at: start.toISOString(), end_at: end.toISOString()};
  });
}

async function saveEventPlan(env, identity, input, planning, eventId, scope) {
  exactOptionalKeys(planning, [], ['meeting_instructions', 'meeting_latitude', 'meeting_longitude',
    'meeting_image_token', 'remove_meeting_image', 'allow_guest', 'invite_preview_enabled',
    'preview_area', 'timezone_offset_minutes', 'poll_post_id', 'poll_option_id', 'audience_usernames']);
  const rawUsernames = planning.audience_usernames ?? [];
  if (!Array.isArray(rawUsernames) || rawUsernames.length > 50 || rawUsernames.some(name =>
    typeof name !== 'string' || !/^@?[a-z0-9_]{3,30}$/i.test(name.trim()))) {
    throw new ApiError(400, 'audience_validation', 'Enter up to 50 valid usernames.');
  }
  const audienceUsernames = [...new Set(rawUsernames.map(name => name.trim().replace(/^@/, '').toLowerCase()))];
  if ((input.p_visibility === 'selected') !== (audienceUsernames.length > 0)) {
    throw new ApiError(400, 'audience_validation', input.p_visibility === 'selected'
      ? 'Enter at least one username.' : 'Usernames are only used with Specific people.');
  }
  if (!['public', 'unlisted'].includes(input.p_visibility) && planning.invite_preview_enabled === true) {
    throw new ApiError(400, 'audience_validation', 'Invite previews are unavailable for a restricted audience.');
  }
  for (const key of ['allow_guest', 'invite_preview_enabled', 'remove_meeting_image']) {
    if (planning[key] !== undefined && typeof planning[key] !== 'boolean') throw new ApiError(400, 'event_validation', 'Event options are invalid.');
  }
  const lat = planning.meeting_latitude == null ? null : numberParameter(planning.meeting_latitude, 'meeting_latitude', -90, 90);
  const lon = planning.meeting_longitude == null ? null : numberParameter(planning.meeting_longitude, 'meeting_longitude', -180, 180);
  if ((lat === null) !== (lon === null)) throw new ApiError(400, 'event_validation', 'Choose a complete meeting point.');
  const postId = planning.poll_post_id == null ? null : uuidParameter(planning.poll_post_id, 'poll_post_id');
  const optionId = planning.poll_option_id == null ? null : uuidParameter(planning.poll_option_id, 'poll_option_id');
  if ((postId === null) !== (optionId === null) || (postId !== null && eventId !== null)) throw new ApiError(400, 'poll_validation', 'Choose a poll date.');
  const details = {
    audience_usernames: audienceUsernames,
    meeting_instructions: optionalStringWithDefault(planning.meeting_instructions, 'meeting_instructions', 500),
    meeting_latitude: lat, meeting_longitude: lon, allow_guest: planning.allow_guest ?? false,
    invite_preview_enabled: planning.invite_preview_enabled ?? false,
    preview_area: optionalStringWithDefault(planning.preview_area, 'preview_area', 120),
    timezone_offset_minutes: integerParameter(planning.timezone_offset_minutes ?? 0, 'timezone_offset_minutes', -840, 840),
    ...(planning.remove_meeting_image ? {meeting_image_key: null} : {}),
  };
  let finalKey = null;
  if (planning.meeting_image_token != null) {
    if (planning.remove_meeting_image) throw new ApiError(400, 'event_validation', 'Choose or remove the photo.');
    const token = uuidParameter(planning.meeting_image_token, 'meeting_image_token');
    assertMediaEnvironment(env);
    const staged = await getMediaObject(env.USER_MEDIA, `staging/events/${identity.userId}/current.jpg`);
    if (!staged || staged.customMetadata?.owner !== identity.userId || staged.customMetadata?.purpose !== 'event-staging' ||
      staged.customMetadata?.token !== token || !Number.isInteger(staged.size) || staged.size < 4 || staged.size > MAX_MEDIA_BYTES) {
      throw new ApiError(400, 'invalid_image_token', 'Choose the meeting photo again.');
    }
    finalKey = `events/${identity.userId}/${crypto.randomUUID()}.jpg`;
    await putMediaObject(env.USER_MEDIA, finalKey, staged.body, {owner: identity.userId, purpose: 'event-meeting'}, staged.size);
    details.meeting_image_key = finalKey;
  }
  try {
    const ids = await supabaseRpc(env, identity.authorization, 'save_event_plan', {
      p_event_id: eventId, p_scope: scope, p_event: input, p_details: details,
      p_poll_post_id: postId, p_poll_option_id: optionId,
    });
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 12 || ids.some(id => typeof id !== 'string' || !UUID_PATTERN.test(id))) {
      throw new ApiError(502, 'invalid_backend_response', 'The event could not be confirmed. Check your plans before retrying.');
    }
    return ids;
  } catch (error) {
    if (finalKey !== null && isDefiniteClientRejection(error)) await deleteMediaObject(env.USER_MEDIA, finalKey);
    throw error;
  }
}

async function enrichEventPlans(env, authorization, events) {
  if (events.length === 0) return events;
  const byId = new Map();
  for (let start = 0; start < events.length; start += 200) {
    const rows = await supabaseRpc(env, authorization, 'get_event_plan_extras', {p_event_ids: events.slice(start, start + 200).map(event => event.id)});
    if (!Array.isArray(rows)) throw new ApiError(502, 'invalid_backend_response', 'Event details are unavailable.');
    for (const row of rows) if (row && typeof row.id === 'string') byId.set(row.id, row);
  }
  return events.filter(event => byId.has(event.id)).map(event => ({...event, ...byId.get(event.id), distance_meters: event.distance_meters}));
}

async function enrichForumPolls(env, authorization, posts) {
  if (posts.length === 0) return posts;
  const ids = await supabaseRpc(env, authorization, 'get_forum_poll_ids', {p_post_ids: posts.map(post => post.id)});
  if (!Array.isArray(ids)) throw new ApiError(502, 'invalid_backend_response', 'Discussions are unavailable.');
  const hasPoll = new Set(ids);
  return posts.map(post => ({...post, has_poll: hasPoll.has(post.id)}));
}

function validateSearchContext(value, dateFilter) {
  exactOptionalKeys(value, [], ['latitude','longitude','area','start_from','start_before']);
  const latitude = value.latitude == null ? null : numberParameter(value.latitude,'latitude',-90,90);
  const longitude = value.longitude == null ? null : numberParameter(value.longitude,'longitude',-180,180);
  if ((latitude === null) !== (longitude === null)) throw new ApiError(400,'saved_search_validation','Choose a search area.');
  const start = value.start_from == null ? null : dateParameter(value.start_from,'start_from');
  const end = value.start_before == null ? null : dateParameter(value.start_before,'start_before');
  if ((start === null) !== (end === null) || (dateFilter === 'custom' && start === null) || (start !== null && (end <= start || dateFilter !== 'custom'))) {
    throw new ApiError(400,'saved_search_validation','Choose a complete date range.');
  }
  return {latitude,longitude,area:optionalStringWithDefault(value.area,'area',160),start_from:start?.toISOString() ?? null,start_before:end?.toISOString() ?? null};
}
