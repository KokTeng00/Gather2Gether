import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { handleEmbedRequest } from './handler.js'

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY'),
}
let model: InstanceType<typeof Supabase.ai.Session> | undefined

Deno.serve((request) => handleEmbedRequest(request, env, async (input: string) => {
  model ??= new Supabase.ai.Session('gte-small')
  return await model.run(input, { mean_pool: true, normalize: true })
}))
