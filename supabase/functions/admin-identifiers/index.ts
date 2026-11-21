import { createClient } from "npm:@supabase/supabase-js@2.95.0";
function allowedOrigins(): Set<string> {
  const configured=Deno.env.get("HUELLIK_ALLOWED_ORIGINS");
  return new Set(configured?configured.split(",").map(v=>v.trim()).filter(Boolean):["https://huellik-web.vercel.app","http://localhost:3000","http://127.0.0.1:3000"]);
}
function reply(body:Record<string,unknown>,status:number,origin:string|null):Response{
  const headers:Record<string,string>={"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","Vary":"Origin","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS"};
  if(origin&&allowedOrigins().has(origin))headers["Access-Control-Allow-Origin"]=origin;
  return new Response(JSON.stringify(body),{status,headers});
}
function key():string{
  const raw=Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if(raw){const parsed=JSON.parse(raw);if(typeof parsed.default==="string"&&parsed.default)return parsed.default;}
  return Deno.env.get("SUPABASE_ANON_KEY")??Deno.env.get("SUPABASE_PUBLISHABLE_KEY")??"";
}
Deno.serve(async(req:Request)=>{
  const origin=req.headers.get("origin");
  if(origin&&!allowedOrigins().has(origin))return reply({error:"Origin not allowed"},403,null);
  if(req.method==="OPTIONS")return new Response("ok",{status:204,headers:{"Vary":"Origin","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS",...(origin&&allowedOrigins().has(origin)?{"Access-Control-Allow-Origin":origin}:{})}});
  if(req.method!=="POST")return reply({error:"Method not allowed"},405,origin);
  const authorization=req.headers.get("authorization")??"",token=authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if(!token)return reply({error:"Authentication required"},401,origin);
  let body:unknown;try{body=await req.json();}catch{return reply({error:"Invalid JSON body"},400,origin);}
  if(!body||typeof body!=="object"||Array.isArray(body))return reply({error:"Invalid request"},400,origin);
  const input=body as Record<string,unknown>,action=input.action;
  if(typeof action!=="string")return reply({error:"Action is required"},400,origin);
  const url=Deno.env.get("SUPABASE_URL"),publishable=key();
  if(!url||!publishable)return reply({error:"Server configuration error"},500,origin);
  const client=createClient(url,publishable,{global:{headers:{Authorization:authorization}},auth:{autoRefreshToken:false,persistSession:false,detectSessionInUrl:false}});
  const {data:userData,error:userError}=await client.auth.getUser(token);
  if(userError||!userData.user)return reply({error:"Invalid or expired session"},401,origin);
  let data,error;
  if(action==="audit"){
    const id=input.identifier_id===undefined||input.identifier_id===null?null:input.identifier_id;
    const limit=input.limit===undefined?50:input.limit,offset=input.offset===undefined?0:input.offset;
    if((id!==null&&(typeof id!=="string"||!/^[0-9a-f-]{36}$/i.test(id)))||typeof limit!=="number"||!Number.isInteger(limit)||limit<1||limit>100||typeof offset!=="number"||!Number.isInteger(offset)||offset<0||offset>100000)
      return reply({error:"Invalid audit filters"},400,origin);
    ({data,error}=await client.rpc("huellik_admin_identifier_audit_v1",{p_identifier_id:id,p_limit:limit,p_offset:offset}));
  }else{
    const allowed=["activate","mark_lost","mark_found","disable","replace"];
    const identifierId=input.identifier_id, replacementId=input.replacement_identifier_id??null, reason=input.reason;
    if(!allowed.includes(action)||typeof identifierId!=="string"||!/^[0-9a-f-]{36}$/i.test(identifierId)||
      (replacementId!==null&&(typeof replacementId!=="string"||!/^[0-9a-f-]{36}$/i.test(replacementId)))||
      typeof reason!=="string"||reason.trim().length<8||reason.trim().length>300)
      return reply({error:"Invalid identifier action"},400,origin);
    ({data,error}=await client.rpc("huellik_admin_identifier_action_v1",{p_action:action,p_identifier_id:identifierId,p_replacement_identifier_id:replacementId,p_reason:reason.trim()}));
  }
  if(error){
    if(error.code==="42501"||/not authorized|permission denied/i.test(error.message))return reply({error:"Administrator access required"},403,origin);
    if(error.code==="P0002")return reply({error:"Identifier not found"},404,origin);
    if(["22023","23514"].includes(error.code))return reply({error:error.message},400,origin);
    console.error("Admin identifier request failed:",error.code??"unknown");
    return reply({error:"Unable to process identifier request"},500,origin);
  }
  return reply({data},200,origin);
});
