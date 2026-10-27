// Hala TV subtitle server — Cloudflare Worker
// Secrets: SUBDL_KEY (subdl.com, free), ANTHROPIC_KEY, optional GOOGLE_KEY + GOOGLE_CX (Programmable Search)
const CORS={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*'};
const txt=(b)=>new Response(b,{headers:{...CORS,'Content-Type':'text/plain; charset=utf-8'}});
const json=(o)=>new Response(JSON.stringify(o),{headers:{...CORS,'Content-Type':'application/json'}});
const err=(s,m)=>new Response(m,{status:s,headers:CORS});
const UA={'User-Agent':'Mozilla/5.0 (Linux; Android 10) Chrome/120 Safari/537.36'};

async function unzip(b){
  const dv=new DataView(b.buffer,b.byteOffset,b.byteLength);let e=b.length-22;
  while(e>=0&&dv.getUint32(e,true)!=0x06054b50)e--;if(e<0)throw 0;
  let n=dv.getUint16(e+10,true),p=dv.getUint32(e+16,true);
  while(n--){const mt=dv.getUint16(p+10,true),cs=dv.getUint32(p+20,true),nl=dv.getUint16(p+28,true),xl=dv.getUint16(p+30,true),cl=dv.getUint16(p+32,true),lo=dv.getUint32(p+42,true),nm=new TextDecoder().decode(b.subarray(p+46,p+46+nl));p+=46+nl+xl+cl;
    if(/\.srt$/i.test(nm)){const st=lo+30+dv.getUint16(lo+26,true)+dv.getUint16(lo+28,true),d=b.subarray(st,st+cs);
      return mt==0?d:new Uint8Array(await new Response(new Blob([d]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer())}}
  throw 0;
}
function decode(u,lang){try{return new TextDecoder('utf-8',{fatal:true}).decode(u)}catch(e){return new TextDecoder(lang=='ar'?'windows-1256':'windows-1252').decode(u)}}
async function fetchSrt(url,lang){
  const r=await fetch(url,{headers:UA,redirect:'follow'});if(!r.ok)throw 0;
  let by=new Uint8Array(await r.arrayBuffer());if(by[0]==0x50&&by[1]==0x4b)by=await unzip(by);
  return decode(by,lang);
}
async function subdl(env,q,lang,se,ep){
  if(!env.SUBDL_KEY)return[];
  const u=`https://api.subdl.com/api/v1/subtitles?api_key=${env.SUBDL_KEY}&film_name=${encodeURIComponent(q)}&languages=${lang.toUpperCase()}&subs_per_page=10`+(se?`&type=tv&season_number=${se}&episode_number=${ep}`:'');
  const j=await (await fetch(u)).json().catch(()=>({}));
  return (j.subtitles||[]).map(s=>({id:'https://dl.subdl.com'+s.url,name:s.release_name||s.name||'—'}));
}
async function google(env,q,lang){
  if(!env.GOOGLE_KEY||!env.GOOGLE_CX)return[];
  const u=`https://www.googleapis.com/customsearch/v1?key=${env.GOOGLE_KEY}&cx=${env.GOOGLE_CX}&q=${encodeURIComponent(q+' '+(lang=='ar'?'arabic':'english')+' subtitle srt')}`;
  const j=await (await fetch(u)).json().catch(()=>({}));
  return (j.items||[]).filter(i=>/\.(srt|zip)(\?|$)/i.test(i.link)).map(i=>({id:i.link,name:i.title}));
}
async function find(env,q,lang,se,ep){
  let a=await subdl(env,q,lang,se,ep);if(!a.length)a=await google(env,q,lang);return a;
}
const parse=s=>s.replace(/\r/g,'').replace(/^\uFEFF/,'').trim().split(/\n\s*\n/).map(b=>{const l=b.split('\n'),i=l.findIndex(x=>x.includes('-->'));return i<0?null:{t:l[i],x:l.slice(i+1).join('\n').replace(/<[^>]+>/g,'')}}).filter(Boolean);
async function tr(env,arr){
  for(let k=0;k<3;k++){
    const r=await fetch('https://api.anthropic.com/v1/messages',{method:'POST',headers:{'x-api-key':env.ANTHROPIC_KEY,'anthropic-version':'2023-06-01','content-type':'application/json'},
      body:JSON.stringify({model:'claude-haiku-5-5',max_tokens:8000,system:'Translate movie subtitle lines to natural, simple Arabic. Input is a JSON array of strings. Return ONLY a JSON array of the same length, same order, no commentary. Keep names, music symbols and line breaks.',messages:[{role:'user',content:JSON.stringify(arr)}]})});
    try{const j=await r.json(),o=JSON.parse(j.content[0].text.replace(/```json|```/g,'').trim());if(Array.isArray(o)&&o.length==arr.length)return o}catch(e){}
  }
  return arr;
}
async function aiTranslate(env,srt){
  const c=parse(srt),B=50,jobs=[];for(let i=0;i<c.length;i+=B)jobs.push(c.slice(i,i+B));
  const out=new Array(jobs.length);let next=0;
  await Promise.all(Array.from({length:6},async()=>{while(next<jobs.length){const k=next++;out[k]=await tr(env,jobs[k].map(x=>x.x))}}));
  const flat=out.flat();return c.map((x,i)=>`${i+1}\n${x.t}\n${flat[i]}\n`).join('\n');
}
export default{async fetch(req,env){
  if(req.method=='OPTIONS')return new Response(null,{headers:CORS});
  const u=new URL(req.url),g=k=>u.searchParams.get(k)||'',lang=g('lang')||'ar';
  try{
    if(u.pathname=='/find')return json({items:await find(env,g('q'),lang,g('se'),g('ep'))});
    if(u.pathname=='/get'||u.pathname=='/fetch')return txt(await fetchSrt(g('id')||g('url'),lang));
    if(u.pathname=='/ai'){
      if(!env.ANTHROPIC_KEY)return err(500,'no key');
      let en=req.method=='POST'?await req.text():'';
      if(!en){const a=await find(env,g('q'),'en',g('se'),g('ep'));if(!a.length)return err(404,'no english sub');en=await fetchSrt(a[0].id,'en')}
      return txt(await aiTranslate(env,en));
    }
    return err(404,'?');
  }catch(e){return err(502,'fail')}
}};
