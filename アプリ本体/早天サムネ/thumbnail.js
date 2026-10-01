const date=document.querySelector('#date'),status=document.querySelector('#status'),passage=document.querySelector('#passage'),preview=document.querySelector('#preview'),canvas=document.querySelector('#canvas'),ctx=canvas.getContext('2d');let filename='',valid=false;
function today(){const p=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Tokyo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());date.value=p;refresh()}
function chosen(){if(!/^\d{4}-\d{2}-\d{2}$/.test(date.value))return null;const [y,m,d]=date.value.split('-').map(Number);const dt=new Date(y,m-1,d);if(dt.getFullYear()!==y||dt.getMonth()!==m-1||dt.getDate()!==d)return null;return{y,m,d,weekday:'日月火水木金土'[dt.getDay()],text:window.PASSAGES[date.value]}}
function titleText(){const x=chosen();return x?.text?`${x.y}・${x.m}・${x.d}（${x.weekday}）${x.text.replaceAll('–','-')} Morning Dew`:''}
function refresh(){valid=false;preview.hidden=true;const x=chosen();passage.textContent=x?.text||'';status.className=x?.text?'':'error';status.textContent=x?.text?`${x.y}年${x.m}月${x.d}日（${x.weekday}）のサムネイルを作成します。`:x?'この日付の聖書箇所は未登録です。月間一覧を追加してください。':'日付を入力してください。';document.querySelector('#make').disabled=!x?.text;document.querySelector('#copy').disabled=!x?.text;document.querySelector('#copyText').textContent=titleText()}
function line(text,y,size,family,max=1160){ctx.font=`${size}px ${family}`;while(ctx.measureText(text).width>max&&size>24){size--;ctx.font=`${size}px ${family}`}ctx.fillText(text,640,y)}
function balancedLine(text,y,size,family,max=1160){
 const parts=text.match(/[0-9A-Za-z:.-]+|[^0-9A-Za-z:.-]+/g)||[];
 const measure=(scale)=>parts.map(t=>{const japanese=/[^0-9A-Za-z:.-]/.test(t);const px=size*(japanese?0.78:1)*scale;ctx.font=`${px}px ${family}`;const m=ctx.measureText(t);return{t,px,w:m.width,asc:m.actualBoundingBoxAscent,desc:m.actualBoundingBoxDescent}});
 let runs=measure(1),width=runs.reduce((n,r)=>n+r.w,0);if(width>max){runs=measure(max/width);width=runs.reduce((n,r)=>n+r.w,0)}
 ctx.font=`${size}px ${family}`;const ref=ctx.measureText('0123456789');const center=y-(ref.actualBoundingBoxAscent-ref.actualBoundingBoxDescent)/2;
 let left=(1280-width)/2;ctx.textAlign='left';for(const r of runs){ctx.font=`${r.px}px ${family}`;ctx.fillText(r.t,left,center+(r.asc-r.desc)/2);left+=r.w}ctx.textAlign='center';
}
async function make(){refresh();const x=chosen(),selectedDate=date.value;if(!x?.text)return;await document.fonts.ready;if(date.value!==selectedDate)return;ctx.fillStyle='#ffaa20';ctx.fillRect(0,0,1280,720);ctx.fillStyle='#000';ctx.textAlign='center';ctx.textBaseline='alphabetic';const serif='"Times New Roman","Hiragino Mincho ProN","YuMincho",serif';balancedLine(`${x.y}・${x.m}・${x.d}（${x.weekday}）`,157,100,serif);line(x.text.replaceAll('–','-').replace(/([一-龯])([0-9])/g,'$1 $2'),282,88,'"Hiragino Mincho ProN","YuMincho",serif');line('Morning Dew',409,100,serif);line('八千代福音キリスト教会',566,50,'"Hiragino Kaku Gothic ProN",sans-serif');line('早天メッセージ',637,50,'"Hiragino Kaku Gothic ProN",sans-serif');filename=`${date.value}_${x.text.replaceAll(':','-').replaceAll('–','-')}_早天サムネ.png`;document.querySelector('#filename').textContent=filename;preview.hidden=false;valid=true;status.textContent='プレビューを確認して、PNG画像を保存してください。'}
document.querySelector('#copy').onclick=async()=>{
 const text=titleText();if(!text)return;
 try{await navigator.clipboard.writeText(text);status.textContent='タイトルをコピーしました。'}
 catch{const field=document.createElement('textarea');field.value=text;field.style.position='fixed';field.style.opacity='0';document.body.append(field);field.select();const ok=document.execCommand('copy');field.remove();status.textContent=ok?'タイトルをコピーしました。':'コピーできませんでした。表示されたタイトルを選択してコピーしてください。'}
};
let studioWindow=null;
document.querySelector('#studio').onclick=()=>{
 if(studioWindow&&!studioWindow.closed){studioWindow.focus();return;}
 studioWindow=window.open('https://www.youtube.com/upload','soutenYouTubeStudio');
 if(!studioWindow)status.textContent='Studioが開かない場合は、このページのポップアップを許可してください。';
};
date.addEventListener('input',refresh);document.querySelector('#today').onclick=today;document.querySelector('#make').onclick=make;document.querySelector('#save').onclick=()=>{if(!valid)return;const a=document.createElement('a');a.download=filename;a.href=canvas.toDataURL('image/png');a.click()};today();
