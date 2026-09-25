const $ = id => document.getElementById(id);
const dockMode = new URLSearchParams(location.search).get('dock') === '1';
if (dockMode) {
  document.documentElement.classList.add('dock');
  document.querySelector('.preview iframe')?.remove();
  $('prepare').textContent = '表示';
}
let state = null, revision = null, busy = false, connected = false;
const modeNames = {reference:'箇所名',body:'本文',hidden:'非表示',prayer:'祈り',lords_prayer:'主の祈り',extra:'説明用のページ'};
function error(message) { $('error').textContent = message; $('error').hidden = !message; }
function render(next) {
  state = next;
  $('connection').textContent = next.obsConnected ? '● OBS 接続中' : 'OBSの表示待ち';
  $('connection').className = 'status ' + (next.obsConnected ? 'online' : 'offline');
  if (revision === next.revision) return;
  revision = next.revision;
  if (!$('date').value) $('date').value = next.date || next.today;
  $('reference').textContent = next.reference || '日付を選んでください';
  $('dateLabel').textContent = next.date ? new Date(next.date+'T12:00:00').toLocaleDateString('ja-JP',{year:'numeric',month:'long',day:'numeric',weekday:'long'}) : '';
  $('modeLabel').textContent = modeNames[next.mode];
  document.querySelectorAll('[data-mode]').forEach(b => {b.setAttribute('aria-pressed',b.dataset.mode===next.mode);b.disabled=!next.pages.length&&['reference','body'].includes(b.dataset.mode);});
  renderExtras(next);
  const pages=next.mode==='extra'?next.extraSelected.pages:next.pages;
  const page=next.mode==='extra'?next.extraPage:next.page;
  $('previous').disabled = !pages.length || page===0;
  $('next').disabled = !pages.length || page===pages.length-1;
  $('pageNumber').textContent = pages.length ? `${page+1} / ${pages.length}` : '—';
  $('pageSelect').replaceChildren(...pages.map((p,i)=>new Option(`${i+1}. ${p.label}${p.part?' ('+p.part+')':''}`,i)));
  for(const e of next.extras||[])$('pageSelect').add(new Option('説明：'+e.title,'extra:'+e.id));
  $('pageSelect').value = page;
  $('pageSelect').disabled = !pages.length&&!next.extras?.length;
  $('warnings').textContent = next.warnings.join('\n'); $('warnings').hidden=!next.warnings.length;
  if(next.startupError) error(next.startupError);
}
async function action(body) {
  if (busy) return;
  busy = true;
  try {
    const response = await fetch('/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(5000)});
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    error('');$('extraError').textContent='';render(data);return true;
  } catch(e) {$('extraError').textContent=e.message;error(e.message || '接続できません。早天配信アプリを開き直してください。');}
  finally {busy=false;}
}
async function poll() {
  try {
    const response = await fetch('/api/state',{signal:AbortSignal.timeout(2500)});
    if(!response.ok) throw new Error();
    connected=true;render(await response.json());
  } catch(e) {connected=false;$('connection').textContent='接続が切れました';$('connection').className='status offline';}
  setTimeout(poll,600);
}
$('prepare').onclick=()=>action({action:'prepare',date:$('date').value});
$('today').onclick=()=>{const d=new Date();$('date').value=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;action({action:'prepare',date:$('date').value});};
document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>action({action:'mode',mode:b.dataset.mode}));
$('previous').onclick=()=>action({action:'previous'});$('next').onclick=()=>action({action:'next'});
$('pageSelect').onchange=()=>{const value=$('pageSelect').value;action(value.startsWith('extra:')?{action:'show_extra',id:value.slice(6)}:{action:'page',page:Number(value)});};
document.addEventListener('keydown',e=>{if($('extrasDialog').open||!connected||busy||e.altKey||e.ctrlKey||e.metaKey||['INPUT','SELECT','TEXTAREA'].includes(e.target.tagName))return;if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();action({action:e.key==='ArrowRight'?'next':'previous'});}});
$('obsUrl').textContent=location.origin+'/display?obs=1';
poll();

function renderExtras(s){
  $('extraList').replaceChildren();
  for(const [i,e] of (s.extras||[]).entries()){
    const row=document.createElement('div');row.className='extra-row';
    const label=document.createElement('span');label.textContent=e.title;row.append(label);
    for(const [caption,body,disabled] of [
      ['表示',{action:'show_extra',id:e.id},false],
      ['↑',{action:'move_extra',id:e.id,direction:'up'},i===0],
      ['↓',{action:'move_extra',id:e.id,direction:'down'},i===s.extras.length-1],
      ['削除',{action:'remove_extra',id:e.id},false]]){
      const b=document.createElement('button');b.textContent=caption;b.disabled=disabled;
      b.onclick=async()=>{if(body.action==='remove_extra'&&!confirm('この追加ページを削除しますか？'))return;if(await action(body)&&body.action==='show_extra')$('extrasDialog').close();};row.append(b);
    }
    $('extraList').append(row);
  }
  if(!s.extras?.length)$('extraList').textContent='追加ページはまだありません。';
}
$('manageExtras').onclick=()=>{if(dockMode)window.open('/?edit=1','_blank');else $('extrasDialog').showModal();};
if(new URLSearchParams(location.search).get('edit')==='1')$('extrasDialog').showModal();
$('closeExtras').onclick=()=>$('extrasDialog').close();
$('addVerse').onclick=async()=>{if(!$('extraReference').value.trim()){$('extraError').textContent='聖書箇所を入力してください。';return;}if(await action({action:'add_extra',reference:$('extraReference').value}))$('extraReference').value='';};
$('addText').onclick=async()=>{if(await action({action:'add_extra',title:$('extraTitle').value,text:$('extraText').value})){$('extraTitle').value='';$('extraText').value='';}};
