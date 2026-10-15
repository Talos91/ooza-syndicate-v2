/* Ooze Syndicate 2.0 - compact native room chat (Alpha 11 chat-ui.js): reading never opens the keyboard; composing is explicit. Messages carry the sender's player id ("pid", which marks your own) and the host-assigned seat label ("who"), rendered as text. The game draws its own CHAT button (lobby, under PAUSE) and calls OozeChat.show(); the DOM toggle stays hidden. */
(()=>{
 let last='',local='',pending='',unread=0,seen=0,panel,log,input,status,form,write;
 const mine=m=>m.pid!==undefined?String(m.pid)===local:m.seat===local;   // "You" by player id: seats repack when someone leaves
 const style=document.createElement('style');style.textContent=`
 #ooze-chat-toggle{position:fixed;z-index:650;right:max(10px,env(safe-area-inset-right));bottom:max(78px,env(safe-area-inset-bottom));min-width:80px;min-height:44px;background:#071e2bea;color:#8cffff;border:1px solid #1ee4ed;font:700 16px system-ui;touch-action:manipulation}
 #ooze-chat{position:fixed;z-index:1250;right:max(8px,env(safe-area-inset-right));top:max(8px,env(safe-area-inset-top));width:min(350px,94vw);height:190px;max-height:calc(100dvh - 16px);box-sizing:border-box;background:#04121bf2;color:#edffff;border:1px solid #16dbe8;display:flex;flex-direction:column;font:14px system-ui;touch-action:auto}
 #ooze-chat header{display:flex;align-items:center;justify-content:space-between;padding:2px 8px;font-weight:bold;gap:8px}
 #ooze-chat button{min-height:44px;padding:6px 12px;background:#16dbe8;color:#001820;border:0;font:700 14px system-ui;touch-action:manipulation}
 #ooze-chat-log{overflow-y:auto;overscroll-behavior:contain;touch-action:pan-y;flex:1;padding:0 8px;min-height:0}
 #ooze-chat-log p{margin:5px 0;white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.3}
 #ooze-chat-log strong{color:#70e9ef;font-size:12px;margin-right:6px}
 #ooze-chat form{display:flex;gap:5px;padding:5px}#ooze-chat form[hidden]{display:none}
 #ooze-chat input{min-width:0;flex:1;font:16px system-ui;padding:7px;background:#0d2632;color:white;border:1px solid #648b9d;user-select:text;-webkit-user-select:text;touch-action:auto}
 #ooze-chat-status{font-size:11px;padding:3px 8px;color:#bed0d5}
 #ooze-chat.composing #ooze-chat-status{display:none}#ooze-chat header,#ooze-chat form{flex-shrink:0}#ooze-chat .chat-actions{display:flex;justify-content:space-between;gap:8px;padding:3px 8px}
 @media(pointer:coarse) and (orientation:landscape){#ooze-chat{width:min(320px,44vw);height:min(170px,46dvh)}#ooze-chat.composing{height:min(205px,70dvh);top:4px}}
 `;document.head.appendChild(style);
 const toggle=document.createElement('button');toggle.id='ooze-chat-toggle';toggle.textContent='Chat';toggle.hidden=true;toggle.setAttribute('aria-expanded','false');
 function close(){input?.blur();panel?.remove();panel=null;toggle.setAttribute('aria-expanded','false');document.getElementById('canvas')?.focus()}
 function render(){if(!log||!panel)return;const bottom=log.scrollHeight-log.scrollTop-log.clientHeight<48;log.replaceChildren();for(const m of JSON.parse(last||'[]')){const row=document.createElement('p'),name=document.createElement('strong'),body=document.createElement('span');name.textContent=(mine(m)?'You':String(m.who))+':';body.textContent=String(m.text);row.append(name,body);log.append(row)}if(bottom)log.scrollTop=log.scrollHeight;unread=0;toggle.textContent='Chat'}
 function compose(){form.hidden=false;write.hidden=true;panel.classList.add('composing');input.focus()}
 function open(){if(panel){close();return}panel=document.createElement('section');panel.id='ooze-chat';panel.setAttribute('aria-label','Compact room chat');toggle.setAttribute('aria-expanded','true');
 const head=document.createElement('header');head.textContent='CHAT';const exit=document.createElement('button');exit.type='button';exit.textContent='CLOSE ×';exit.setAttribute('aria-label','Close chat and return to match');exit.onclick=close;head.append(exit);
 log=document.createElement('div');log.id='ooze-chat-log';log.setAttribute('role','log');
 form=document.createElement('form');form.hidden=true;input=document.createElement('input');input.type='text';input.maxLength=256;input.placeholder='Message everyone';input.setAttribute('aria-label','Chat message');input.autocomplete='off';
 const send=document.createElement('button');send.type='submit';send.textContent='Send';status=document.createElement('div');status.id='ooze-chat-status';status.textContent='Match continues. Scroll for earlier messages.';
 const actions=document.createElement('div');actions.className='chat-actions';write=document.createElement('button');write.type='button';write.textContent='Write message';write.onclick=compose;actions.append(write);
 form.onsubmit=e=>{e.preventDefault();const text=input.value.trim();if(text){pending=text;input.value='';input.blur();form.hidden=true;write.hidden=false;panel.classList.remove('composing');status.textContent='Sent for delivery. Match continues.';document.getElementById('canvas')?.focus()}};
 form.append(input,send);panel.append(head,log,actions,form,status);panel.addEventListener('keydown',e=>{e.stopPropagation();if(e.key==='Escape')close()});document.body.append(panel);render();log.scrollTop=log.scrollHeight}
 toggle.onclick=open;
 window.OozeChat={sync(active,history,me){if(!toggle.isConnected)document.body.append(toggle);toggle.hidden=true;local=String(me);if(!active){close();last='';seen=0;unread=0;pending='';toggle.textContent='Chat';return}if(history!==last){const entries=JSON.parse(history);const latest=entries.length?Number(entries.at(-1).id):0;if(!panel)unread+=entries.filter(m=>Number(m.id)>seen&&!mine(m)).length;seen=latest;last=history;toggle.textContent=unread?'Chat ('+unread+')':'Chat';render()}},takeMessage(){const value=pending;pending='';return value},show(){if(!panel)open()},unread(){return unread},error(message){if(status&&panel)status.textContent=message}};
})();
