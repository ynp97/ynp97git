import * as pdfjsLib from '/vendor/pdf.min.mjs';
pdfjsLib.GlobalWorkerOptions.workerSrc = '/vendor/pdf.worker.min.mjs';
const $ = id => document.getElementById(id);
let pdf, pageNumber = 1, mappings = [], state, key = '', renderTask, generation = 0;

function status(message) { $('status').textContent = message; }
function normalized(s) { return s.normalize('NFKC').replace(/\s+/g, ''); }
function save() { if(key) localStorage.setItem(key, JSON.stringify(mappings)); }
async function getState() {
  const response = await fetch('/api/state', {cache:'no-store'});
  if(!response.ok) throw new Error('聖書ボードに接続できません');
  state = await response.json();
}
async function send(body) {
  const response = await fetch('/api/action', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const data = await response.json();
  if(!response.ok) throw new Error(data.error || '聖書ボードを切り替えられません');
  state = data;
  status(`OBS：${data.mode === 'body' ? data.pages[data.page]?.label : data.mode === 'reference' ? '箇所名' : '非表示'}`);
}
async function applyMapping() {
  const target = mappings[pageNumber-1];
  if(target === 'keep') return;
  if(target === 'reference') return send({action:'mode',mode:'reference'});
  if(target === 'hidden') return send({action:'mode',mode:'hidden'});
  if(Number.isInteger(target) && state.pages[target]) return send({action:'page',page:target});
}
function choices() {
  const select = $('mapping');
  select.replaceChildren(new Option('前ページの表示を保つ','keep'),new Option('箇所名','reference'),new Option('非表示','hidden'));
  for(const [i,p] of state.pages.entries()) select.add(new Option(p.label+(p.part?` (${p.part})`:''),String(i)));
  select.value = String(mappings[pageNumber-1] ?? 'keep');
}
async function showPage(apply=true) {
  if(!pdf) return;
  const myGeneration = ++generation;
  $('counter').textContent = `${pageNumber} / ${pdf.numPages}`;
  $('prev').disabled = pageNumber <= 1; $('next').disabled = pageNumber >= pdf.numPages;
  choices();
  if(renderTask) { renderTask.cancel(); try { await renderTask.promise; } catch (_) {} }
  const page = await pdf.getPage(pageNumber);
  if(myGeneration !== generation) return;
  const canvas = $('page'), context = canvas.getContext('2d');
  // 窓の幅と高さの両方に収まる大きさで描く（スクロールしないで1ページ全体が見える）
  const sheet = document.querySelector('.sheet'), base = page.getViewport({scale:1});
  const fit = Math.min((sheet.clientWidth-12)/base.width, (sheet.clientHeight-12)/base.height);
  const viewport = page.getViewport({scale:Math.max(.2,fit)*Math.min(devicePixelRatio,2)});
  canvas.width = Math.floor(viewport.width); canvas.height = Math.floor(viewport.height);
  canvas.style.width = `${viewport.width/Math.min(devicePixelRatio,2)}px`;
  renderTask = page.render({canvasContext:context,viewport});
  await renderTask.promise;
  if(apply && myGeneration === generation) await applyMapping();
}
async function go(delta) {
  const next = Math.max(1,Math.min(pdf.numPages,pageNumber+delta));
  if(next === pageNumber) return;
  pageNumber = next;
  try { await showPage(); } catch(e) { status(e.message); }
}
async function suggestMappings() {
  const suggested = [];
  const labels = state.pages.map(p=>normalized(p.label));
  for(let i=1;i<=pdf.numPages;i++) {
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    const text = normalized(content.items.map(item=>item.str).join(' '));
    // A repeated range in the page header is excluded; the first actual verse is a suggestion.
    const matches = [...text.matchAll(/(\d+):(\d+)(?!\d|[-–—〜~]\d)/g)];
    const found = matches.map(m=>labels.findIndex(label=>label.endsWith(`${m[1]}:${m[2]}`))).find(index=>index>=0);
    suggested.push(i===1 ? 'reference' : found === undefined ? 'keep' : found);
  }
  return suggested;
}
async function openPdf(data,identity,name) {
  try {
    status('PDFを読み込み中…');
    await getState();
    const dateToken = name.match(/(?:^|\D)(20\d{6})(?:\D|$)/)?.[1] || identity.match(/(?:^|\D)(20\d{6})(?:\D|$)/)?.[1];
    if(dateToken) {
      const date = `${dateToken.slice(0,4)}-${dateToken.slice(4,6)}-${dateToken.slice(6,8)}`;
      if(state.date !== date) await send({action:'prepare',date});
    }
    pdf = await pdfjsLib.getDocument({data}).promise;
    key = 'soten-reader:'+identity+':'+state.date;
    const saved = localStorage.getItem(key);
    mappings = saved ? JSON.parse(saved) : await suggestMappings();
    if(mappings.length !== pdf.numPages) mappings = await suggestMappings();
    pageNumber = 1; $('filename').textContent = name;
    await showPage();
  } catch(e) { status(e.message); }
}
$('pdfFile').onchange = async event => {
  const file = event.target.files[0];
  if(file) await openPdf(new Uint8Array(await file.arrayBuffer()),`${file.name}:${file.size}:${file.lastModified}`,file.name);
};
let resizeTimer; window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>showPage(false).catch(e=>status(e.message)),150);});
$('prev').onclick=()=>go(-1); $('next').onclick=()=>go(1);
$('nextVerse').onclick=async()=>{try{await send({action:'next'});}catch(e){status(e.message);}};
$('mapping').onchange=async()=>{
  const value=$('mapping').value;
  mappings[pageNumber-1] = /^\d+$/.test(value)?Number(value):value;
  save(); try{await applyMapping();}catch(e){status(e.message);}
};
document.addEventListener('keydown',event=>{
  if(['INPUT','SELECT'].includes(event.target.tagName)||event.altKey||event.ctrlKey||event.metaKey) return;
  if(event.key==='ArrowRight'||event.key==='PageDown'){event.preventDefault();go(1);}
  if(event.key==='ArrowLeft'||event.key==='PageUp'){event.preventDefault();go(-1);}
});
async function openFromUrl(url, identity, name) {
  const response = await fetch(url, {cache:'no-store'});
  if(!response.ok) throw new Error('PDFを読み込めません');
  await openPdf(new Uint8Array(await response.arrayBuffer()), identity, name);
}
async function openToday() {
  if(new URLSearchParams(location.search).has('sample'))
    return openFromUrl('/sample.pdf','sample-20260928','20260928の原稿（試作）');
  const response = await fetch('/api/today-pdf', {cache:'no-store'});
  const info = response.ok ? (await response.json()).pdf : null;
  if(!info) return status('今日のPDFが見つかりません。「PDFを選ぶ」から開いてください');
  await openFromUrl('/today.pdf', `${info.name}:${info.size}:${info.mtime}`, info.name);
}
openToday().catch(e=>status(e.message));

function tick() {
  const now = new Date(), p = n => String(n).padStart(2,'0');
  $('clock').innerHTML = `${p(now.getHours())}:${p(now.getMinutes())}<small>:${p(now.getSeconds())}</small>`;
  setTimeout(tick, 1000 - now.getMilliseconds());
}
tick();
