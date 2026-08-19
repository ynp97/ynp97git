const $=id=>document.getElementById(id);const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const FRAME={2:'通常枠',1:'プロモ等',0:'別枠レア'};
async function loadStats(){const s=await fetch('/api/stats').then(r=>r.json());$('stats').textContent=`現行スタンダード ${s.kinds||0}種（版は ${s.ready||0} / ${s.total||0}枚 準備済み）${s.errors?`・失敗${s.errors}件`:''}`;
/* 本文中のエネルギー記号（【水】など）が入っていないDBだと、「特性で水エネルギーを
   持ってくる」は正しく0件になる。黙って0件を返すと誤読するので、上に出す。 */
if(!s.icon_texts){const b=document.createElement('div');b.className='banner';
b.innerHTML='カード本文の <b>【水】【炎】</b> などのエネルギー記号が、まだDBに入っていません（取得時に消えていました）。タイプがからむ質問は正しく答えられません。ターミナルで <code>python3 update_cards.py --refresh-all</code> を一度実行してください。';
document.querySelector('main').insertBefore(b,document.querySelector('.ask-panel'))}}
function versionsHtml(c){const v=c.variants||[];if(v.length<2)return '';const rows=v.map(x=>`<li>${esc([x.set_code,x.card_number,x.rarity].filter(Boolean).join(' '))} <span class="frame">${esc(FRAME[x.frame_rank]??'')}</span> <a href="${esc(x.official_url)}" target="_blank" rel="noopener">詳細 ↗</a></li>`).join('');return `<details class="variants"><summary>他 ${v.length-1} 版（別絵・再録・プロモ）</summary><ul>${rows}</ul></details>`}
function cardHtml(c){const abs=(c.abilities||[]).map(x=>`<div class="ability"><span class="tag">特性</span><b>${esc(x.name)}</b> ${esc(x.text)}</div>`).join('');
const at=(c.attacks||[]).map(x=>{const note=x.damage_note?` <span class="status">${esc(x.damage_note)}</span>`:'';return `<div class="attack"><span class="tag">ワザ</span><b>${esc(x.name)}</b> <b>${esc(x.printed_damage)}</b>${note}<br>${esc(x.text)}</div>`}).join('');
return `<article class="card"><img src="${esc(c.image_url)}" alt="" loading="lazy"><div><h3>${esc(c.name)}</h3><div class="meta">${esc([c.category,c.subcategory,c.stage,c.hp&&`HP${c.hp}`,c.set_code,c.card_number].filter(Boolean).join(' / '))}</div><div class="reason">${esc(c.match_reason||'')}</div>${abs}${at}${versionsHtml(c)}<a class="official" href="${esc(c.official_url)}" target="_blank" rel="noopener">公式カード詳細 ↗</a></div></article>`}
const FIELDS=['q','name_q','ability_q','attack_q','attack_energy','category','subcategory','type','stage','ability','hp_min','hp_max','damage_min','damage_certain'];
const panelParams=()=>{const o={};FIELDS.forEach(id=>{const v=$(id)&&$(id).value.trim();if(v)o[id]=v});return o};
async function search(){const p=new URLSearchParams(panelParams());
$('notice').textContent='全カードを走査中…';const d=await fetch('/api/search?'+p).then(r=>r.json());
if(d.error){$('resultTitle').textContent='エラー';$('notice').textContent=d.error;$('results').innerHTML='';return}
$('resultTitle').textContent=`検索結果 ${d.total??0}種`;
const notes=[`同じカードは1件にまとめています（該当する版は${d.prints??0}枚）。`];
if(d.total>d.limit)notes.push(`最初の${d.limit}種を表示しています。条件を追加してください。`);
if($('damage_min').value&&!$('damage_certain').value)notes.push('×・＋のついたワザは「要計算」として残しています。');
$('notice').textContent=notes.join(' ');
$('results').innerHTML=(d.cards||[]).map(c=>cardHtml(c)).join('')||'<div class="empty">条件に合うカードはありません。</div>'}
$('search').addEventListener('click',search);$('q').addEventListener('keydown',e=>{if(e.key==='Enter')search()});loadStats().catch(e=>$('stats').textContent='データ未作成');

/* ---- AIへの質問窓 --------------------------------------------------------
   答えの出どころは常にローカルDB。AIは「質問→検索条件」と「候補の読み分け」
   だけを担当する。AIが候補に無い名前を書いたら ※印つきで見えるようにする。 */
const post=(path,body)=>fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).then(async r=>({ok:r.ok,data:await r.json()}));
async function loadAiConfig(){try{const c=await fetch('/api/ai-config').then(r=>r.json());$('base_url').value=c.base_url||'';$('model').value=c.model||'';$('max_cards').value=c.max_cards??60;$('api_key').placeholder=c.api_key_set?'保存済み（変えるときだけ入力）':'変更するときだけ入力'}catch(e){}}
$('aiSettingsToggle').addEventListener('click',()=>{$('aiSettings').hidden=!$('aiSettings').hidden});
$('saveAi').addEventListener('click',async()=>{$('aiStatus').textContent='保存中…';const{ok,data}=await post('/api/ai-config',{base_url:$('base_url').value.trim(),model:$('model').value.trim(),api_key:$('api_key').value,max_cards:Number($('max_cards').value)||60});$('api_key').value='';$('aiStatus').textContent=ok?'保存しました':(data.error||'保存できません');loadAiConfig()});
$('checkAi').addEventListener('click',async()=>{$('aiStatus').textContent='確認中…';const r=await fetch('/api/ai-models');const d=await r.json();$('aiStatus').textContent=r.ok?`つながりました：${(d.models||[]).join(' / ')||'モデル名なし'}`:`つながりません：${d.error||''}`});

function pickHtml(label,items){if(!items||!items.length)return '';const rows=items.map(x=>`<li><b>${esc(x.name||'')}</b>${x.unverified?' <span class="warn">※候補に無い名前。AIの作り話の疑い</span>':''} — ${esc(x.why||'')}</li>`).join('');return `<div class="picks"><h4>${esc(label)}（${items.length}）</h4><ul>${rows}</ul></div>`}
function answerHtml(d){const j=d.judged||{};const cond=(d.searches||[]).map(s=>{const{該当,...rest}=s;return `<li><code>${esc(JSON.stringify(rest))}</code> → ${該当??'-'}種</li>`}).join('');
const warn=d.invented&&d.invented.length?`<p class="warn">AIが候補に無い名前を挙げました：${esc(d.invented.join('、'))}。ローカルDBで裏が取れていません。</p>`:'';
const trim=d.trimmed?`<p class="warn">候補が${d.candidate_count}種あり、AIに読ませたのは上限${d.max_cards}種までです。条件を足すか上限を上げてください。</p>`:'';
const err=d.error?`<p class="warn">AIにつながりませんでした：${esc(d.error)}<br>下の「AIに貼る文」をコピーして、Claude等へ貼ってください。</p>`:'';
const none=d.no_conditions?'<p class="warn">下の検索欄が空なので候補を集められませんでした。条件（特性の文・カード種別など）を入れてから、もう一度押してください。</p>':'';
const je=d.judge_error?`<p class="warn">候補の読み分けでAIが応答しませんでした：${esc(d.judge_error)}</p>`:'';
return `${err}${none}${je}${d.reading?`<p class="reading">読み取り：${esc(d.reading)}</p>`:''}
${j.answer?`<p class="answer">${esc(j.answer)}</p>`:''}
${pickHtml('該当',j.hits)}${pickHtml('たぶん（要確認）',j.maybe)}
${j.missing?`<p class="warn">漏れの心配：${esc(j.missing)}</p>`:''}${warn}${trim}
${cond?`<details class="cond"><summary>使った検索条件</summary><ul>${cond}</ul></details>`:''}
${d.packet?`<details class="cond"><summary>AIに貼る文（${d.candidate_count??0}種ぶん）</summary><textarea readonly rows="10" id="packetText">${esc(d.packet)}</textarea><div class="actions"><button class="secondary" id="copyPacket">コピー</button></div></details>`:''}`}
function showAnswer(d){$('aiAnswer').hidden=false;$('aiAnswer').innerHTML=answerHtml(d);const b=$('copyPacket');if(b)b.addEventListener('click',()=>{$('packetText').select();document.execCommand('copy');b.textContent='コピーしました'});
$('resultTitle').textContent=`AIが読んだ候補 ${d.cards?d.cards.length:0}種`;
$('notice').textContent='答えの根拠はこの候補の中だけです。最終確認は各カードの公式詳細で。';
$('results').innerHTML=(d.cards||[]).map(c=>cardHtml(c)).join('')||'<div class="empty">条件に合うカードはありません。</div>'}
async function runAsk(packetOnly){const question=$('question').value.trim();if(!question){$('askNotice').textContent='質問を書いてください';return}
$('askNotice').textContent=packetOnly?'DBを走査中…':'AIに問い合わせ中…（ローカルモデルは3分ほどかかることがあります）';
try{const{data}=await post('/api/ask',{question,packet_only:!!packetOnly,params:panelParams()});$('askNotice').textContent='';showAnswer(data)}
catch(e){$('askNotice').textContent='失敗しました：'+e}}
$('ask').addEventListener('click',()=>runAsk(false));$('packet').addEventListener('click',()=>runAsk(true));
$('question').addEventListener('keydown',e=>{if(e.key==='Enter'&&(e.metaKey||e.ctrlKey))runAsk(false)});
loadAiConfig();
