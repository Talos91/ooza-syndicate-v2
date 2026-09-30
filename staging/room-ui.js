/* Ooze Syndicate 2.0 - native DOM room-code field (Alpha 11 mobile-ui.js): phone keyboards type, paste and copy the four-character code in the browser, not in the canvas. */
(()=>{
 let result='';
 const style=document.createElement('style');style.textContent=`#ooze-room{position:fixed;inset:0;z-index:1200;background:#031017ed;display:grid;place-items:center;padding:12px;box-sizing:border-box;touch-action:auto;font:20px system-ui;color:#e5fcff}#ooze-room form{width:min(460px,90vw);max-height:90dvh;overflow:auto;padding:20px;background:#081f2b;border:2px solid #13dbea;box-sizing:border-box}#ooze-room input{width:100%;box-sizing:border-box;font:700 32px system-ui;letter-spacing:8px;text-align:center;padding:12px;background:#020c12;color:white;border:2px solid #4e98ad;touch-action:auto;user-select:text;-webkit-user-select:text}#ooze-room button{min-height:48px;font:700 18px system-ui;padding:10px 20px;margin:12px 8px 0 0;color:#001720;background:#19dce8;border:0;touch-action:manipulation}#ooze-room p{font-size:16px;line-height:1.4}#ooze-room-code{position:fixed;z-index:1100;box-sizing:border-box;margin:0;padding:0 12px;background:#020c12;color:#fff;border:2px solid #255363;font-family:system-ui;font-weight:700;letter-spacing:6px;touch-action:manipulation;user-select:text;-webkit-user-select:text;outline:none}#ooze-room-code:focus{border-color:var(--acc,#19dce8)}#ooze-room-code::placeholder{color:#5f7a86;letter-spacing:2px}`;document.head.appendChild(style);
 function show(value,readOnly=false){
  document.getElementById('ooze-room')?.remove();result='';
  const panel=document.createElement('div');panel.id='ooze-room';
  const form=document.createElement('form');const title=document.createElement('h2');title.textContent=readOnly?'Share room code':'Join a room';
  const input=document.createElement('input');input.type='text';input.inputMode='text';input.autocomplete='off';input.autocapitalize='characters';input.spellcheck=false;input.maxLength=4;input.setAttribute('aria-label','Four-character room code');input.value=value;input.readOnly=readOnly;
  input.addEventListener('input',()=>{input.value=input.value.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g,'').slice(0,4)});
  const note=document.createElement('p');note.textContent=readOnly?'Tap Copy, or hold the code to select and copy it.':'Type four letters/numbers, or hold the field and choose Paste.';
  const submit=document.createElement('button');submit.type=readOnly?'button':'submit';submit.textContent=readOnly?'Copy':'Join room';
  if(readOnly)submit.onclick=async()=>{try{await navigator.clipboard.writeText(input.value);submit.textContent='Copied';}catch(e){input.focus();input.select();note.textContent='Hold the selected code and choose Copy.'}};
  const cancel=document.createElement('button');cancel.type='button';cancel.textContent=readOnly?'Close':'Cancel';cancel.onclick=()=>panel.remove();
  form.onsubmit=e=>{e.preventDefault();if(/^[A-HJ-NP-Z2-9]{4}$/.test(input.value)){result=input.value;panel.remove();document.getElementById('canvas')?.focus()}else note.textContent='Enter all four characters from the host.'};
  form.append(title,input,note,submit,cancel);panel.append(form);document.body.append(panel);input.focus();input.select();
 }
 // Alpha 21 ONLINE ROOMS: the code field inline, laid over the page's ROOM CODE frame (placeCode: canvas fractions, like
 // ACCOUNT's name field) - the player taps the DOM input itself, so phones raise their keyboard; Enter hands the code to takeCode().
 function placeCode(fx,fy,fw,fh,v,acc){const c=document.getElementById('canvas');if(!c)return;const b=c.getBoundingClientRect();let el=document.getElementById('ooze-room-code');
  if(!el){el=document.createElement('input');el.id='ooze-room-code';el.type='text';el.inputMode='text';el.enterKeyHint='go';el.autocomplete='off';el.autocapitalize='characters';el.spellcheck=false;el.maxLength=4;el.placeholder='E.G. K7QX';el.setAttribute('aria-label','Four-character room code');el.value=v||'';
   el.addEventListener('input',()=>{el.value=el.value.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g,'').slice(0,4)});
   el.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();if(/^[A-HJ-NP-Z2-9]{4}$/.test(el.value)){result=el.value;el.blur()}}});
   el.addEventListener('pointerdown',e=>e.stopPropagation());document.body.appendChild(el)}
  if(acc)el.style.setProperty('--acc',acc);el.style.left=(b.left+fx*b.width)+'px';el.style.top=(b.top+fy*b.height)+'px';el.style.width=(fw*b.width)+'px';el.style.height=(fh*b.height)+'px';el.style.fontSize=Math.max(16,Math.round(fh*b.height*0.42))+'px'}
 window.OozeRoom={openCode:code=>show(code||''),takeCode:()=>{const code=result;result='';return code},shareCode:code=>show(code,true),closeCode:()=>document.getElementById('ooze-room')?.remove(),
  placeCode:placeCode,codeValue:()=>(document.getElementById('ooze-room-code')?.value||'').trim(),removeCode:()=>document.getElementById('ooze-room-code')?.remove()};
})();
