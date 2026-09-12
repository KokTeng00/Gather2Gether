import assert from 'node:assert/strict';
import test, {afterEach} from 'node:test';
import {handleApiRequest} from '../functions/api/v1/[[path]].js';
import {onRequest} from '../functions/[[path]].js';
const originalFetch = globalThis.fetch;
afterEach(() => {globalThis.fetch = originalFetch;});
const userId='11111111-1111-4111-8111-111111111111';
const eventId='22222222-2222-4222-8222-222222222222';
const optionId='33333333-3333-4333-8333-333333333333';
const env={SUPABASE_URL:'https://project.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_test_key_long_enough'};
const future=days=>new Date(Date.now()+days*86400000).toISOString();
const event=()=>({title:'A walk by the river',description:'A relaxed walk.',category:'Hiking',venue_name:'River park',address:'Private entrance',latitude:49.48,longitude:8.47,start_at:future(7),end_at:future(7.1),max_participants:4,
  planning:{meeting_instructions:'Meet beside the café.',meeting_latitude:49.481,meeting_longitude:8.471,allow_guest:true,invite_preview_enabled:true,preview_area:'Mannheim'}});
const request=(path,method='GET',body)=>new Request(`https://app.test/api/v1/${path}`,{method,headers:{Authorization:'Bearer member-token','Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
function mockRpc(handler) { globalThis.fetch=async(url,options)=>String(url).endsWith('/auth/v1/user')?Response.json({id:userId}):handler(String(url).split('/').at(-1),JSON.parse(options.body)); }

test('event and planning details are saved in one authenticated transaction',async()=>{
  let captured;
  mockRpc((name,args)=>{assert.equal(name,'save_event_plan');captured=args;return Response.json([eventId]);});
  const response=await handleApiRequest(request('events','POST',event()),env);
  assert.equal(response.status,201);
  assert.equal(captured.p_event_id,null);
  assert.equal(captured.p_event.p_title,'A walk by the river');
  assert.equal(captured.p_details.allow_guest,true);
  assert.equal(captured.p_details.meeting_instructions,'Meet beside the café.');
  assert.equal('organizer_id' in captured,false);
});

test('incomplete meeting coordinates and invalid guest choices cannot reach the database',async()=>{
  mockRpc(()=>{throw new Error('must not write');});
  const body=event();delete body.planning.meeting_longitude;
  assert.equal((await handleApiRequest(request('events','POST',body),env)).status,400);
  assert.equal((await handleApiRequest(request(`events/${eventId}/rsvp`,'PUT',{status:'joined',guest_count:2}),env)).status,400);
});

test('guest reservation and conflict reads use user-scoped RPCs',async()=>{
  const calls=[];mockRpc((name,args)=>{calls.push({name,args});return Response.json(name==='list_event_conflicts'?[]:'waitlisted');});
  const result=await handleApiRequest(request(`events/${eventId}/rsvp`,'PUT',{status:'joined',guest_count:1}),env);
  assert.equal((await result.json()).status,'waitlisted');
  assert.deepEqual(calls[0],{name:'set_event_rsvp_with_guest',args:{p_event_id:eventId,p_status:'joined',p_guest_count:1}});
  assert.equal((await handleApiRequest(request(`events/${eventId}/conflicts`),env)).status,200);
  assert.equal(calls[1].name,'list_event_conflicts');
});

test('poll dates reject duplicates, past dates and incomplete options',async()=>{
  mockRpc(()=>{throw new Error('must not write');});
  const option={start_at:future(7),end_at:future(7.1)};
  for(const options of [[option],[option,option],[option,{start_at:future(-2),end_at:future(-1)}]]){
    const response=await handleApiRequest(request('forum/posts','POST',{title:'A walk together',body:'Which date would work for you?',category:'Event ideas',poll_options:options}),env);
    assert.equal(response.status,400);
  }
});

test('creating a poll and voting preserve separate RSVP state',async()=>{
  const calls=[];mockRpc((name,args)=>{calls.push({name,args});return Response.json(name==='create_forum_post_with_poll'?eventId:{post_id:eventId,options:[]});});
  const response=await handleApiRequest(request('forum/posts','POST',{title:'A walk together',body:'Which date would work for you?',category:'Event ideas',poll_options:[{start_at:future(7),end_at:future(7.1)},{start_at:future(8),end_at:future(8.1)}]}),env);
  assert.equal(response.status,201);assert.equal(calls[0].name,'create_forum_post_with_poll');
  await handleApiRequest(request(`forum/posts/${eventId}/poll/${optionId}`,'PUT',{available:true}),env);
  assert.equal(calls[1].name,'set_forum_poll_vote');
  assert.equal(calls.some(call=>call.name.includes('rsvp')),false);
});

test('custom date discovery forwards constraints before candidate retrieval',async()=>{
  let filters;
  mockRpc((name,args)=>{
    if(name==='get_recommendation_preferences') return Response.json([{enabled:false,hidden_categories:[]}]);
    if(name==='list_hidden_recommendation_ids')return Response.json([]);
    assert.equal(name,'discover_event_plans');filters=args.p_filters;return Response.json([]);
  });
  const start=future(10),end=future(11);
  const query=new URLSearchParams({planning:'1',latitude:'49.48',longitude:'8.47',radius_km:'25',start_from:start,start_before:end});
  const response=await handleApiRequest(request(`events/nearby?${query}`),env);
  assert.equal(response.status,200);assert.equal(filters.start_from,start);assert.equal(filters.start_before,end);
});

test('public invitation is escaped, uses only the preview RPC and never caches opt-in data',async()=>{
  globalThis.fetch=async(url,options)=>{
    assert.match(String(url),/get_event_invite_preview$/);
    assert.equal(options.headers.Authorization,undefined);
    return Response.json({title:'<script>alert(1)</script>',description:'A nice walk & coffee.',start_at:future(2),area:'Mannheim',timezone_offset_minutes:120,address:'DO NOT RENDER',meeting_instructions:'PRIVATE'});
  };
  const response=await onRequest({request:new Request(`https://app.test/invite/${eventId}`),env});
  const html=await response.text();
  assert.match(html,/&lt;script&gt;/);assert.equal(html.includes('<script>'),false);
  assert.equal(html.includes('DO NOT RENDER'),false);assert.equal(html.includes('PRIVATE'),false);
  assert.match(html,/Mannheim/);assert.equal(response.headers.get('Cache-Control'),'no-store');
});

test('private or unavailable invitation keeps a usable app handoff',async()=>{
  for(const reply of [null,{title:'malformed'}]){
    globalThis.fetch=async()=>Response.json(reply);
    const response=await onRequest({request:new Request(`https://app.test/invite/${eventId}`),env});
    assert.equal(response.status,200);const html=await response.text();
    assert.match(html,/keeping event details in the app/);assert.match(html,/gather2gether:\/\/event\//);
  }
});
