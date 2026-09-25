const $=id=>document.getElementById(id);
let revision=null,lastGood=0,latest=null;
const obs=new URLSearchParams(location.search).get('obs')==='1';
function scale(){const s=Math.min(innerWidth/1920,innerHeight/1080);$('stage').style.transform=`scale(${s})`;}
function render(s){
  latest=s;$('stage').hidden=s.mode==='hidden'||(!s.pages.length&&['reference','body'].includes(s.mode));
  if(revision===s.revision)return;revision=s.revision;
  const date=new Date((s.date||s.today)+'T12:00:00');
  $('day').textContent=date.toLocaleDateString('ja-JP',{year:'numeric',month:'long',day:'numeric',weekday:'short'});
  $('reference').textContent=['prayer','lords_prayer'].includes(s.mode)?'祈り':s.reference;
  $('title').textContent=s.mode==='prayer'?'祈り':s.reference;
  $('titleCaption').hidden=s.mode==='prayer';
  $('titleView').classList.toggle('prayer-title',s.mode==='prayer');
  $('prayerView').hidden=s.mode!=='lords_prayer';
  $('titleView').hidden=!['reference','prayer'].includes(s.mode);$('bodyView').hidden=!['body','extra'].includes(s.mode);
  const pages=s.mode==='extra'?s.extraSelected.pages:s.pages;
  const page=s.mode==='extra'?s.extraPage:s.page;
  document.querySelector('#bodyView small').hidden=s.mode==='extra'&&!pages[page]?.copyright;
  if(s.mode==='extra')$('reference').textContent=s.extraSelected.title;
  if(pages.length){const p=pages[page];$('verse').textContent=p.label+(p.part?' （'+p.part+'）':'');$('text').textContent=p.text;$('page').textContent=`${page+1} / ${pages.length}`;
    $('text').style.fontSize='52px';
    if(['body','extra'].includes(s.mode)){let size=52;while($('text').scrollHeight>$('text').clientHeight+1&&size>34){size-=2;$('text').style.fontSize=size+'px';}}
  }
  if(s.mode==='lords_prayer'){
    const text=$('prayerText');
    let size=64;
    text.style.fontSize=size+'px';
    while((text.scrollHeight>text.clientHeight||text.scrollWidth>text.clientWidth)&&size>24){
      size-=0.5;text.style.fontSize=size+'px';
    }
  }
  scale();
}
async function poll(){try{const r=await fetch('/api/state'+(obs?'?obs=1':''),{signal:AbortSignal.timeout(2000)});if(!r.ok)throw new Error();const s=await r.json();lastGood=Date.now();render(s);}catch(e){}setTimeout(poll,350);}
setInterval(()=>{if(Date.now()-lastGood>3000)$('stage').hidden=true;},500);
addEventListener('resize',scale);scale();poll();
