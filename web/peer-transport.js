/* Ooze Syndicate 2.0 - PeerJS transport only (copied from Alpha 11's peer-transport.js). The host's
   Godot simulation owns every rule; this only moves strings between browsers. Up to 5 guests. */
(function () {
  let peer = null, host = false, events = [], links = new Map(), epoch = 0;
  const prefix = 'ooze20-';          // 2.0 rooms never collide with Alpha 11's
  function emit(event) { if(event.type==='data' && event.data.startsWith('{"kind":"state"')) { const i=events.findIndex(e=>e.type==='data'&&e.peer===event.peer&&e.data.startsWith('{"kind":"state"')); if(i>=0){events[i]=event;return;} } if (events.length < 256 || event.type !== 'data') events.push(event); }   // only data packets are capped; control events always get through
  function bind(conn, token) {
    if (links.size >= 5 || links.has(conn.peer)) { conn.close(); return; }
    links.set(conn.peer, conn);
    conn.on('open', () => { if (token === epoch) emit({type:'connection', peer:conn.peer}); });
    conn.on('data', data => { if (token !== epoch) return; if (typeof data !== 'string' || data.length > (host ? 4096 : 8*1024*1024)) { conn.close(); return; } emit({type:'data', peer:conn.peer, data}); });
    conn.on('close', () => { if (token !== epoch) return; links.delete(conn.peer); emit({type:'closed',peer:conn.peer}); });
    conn.on('error', () => { if (token === epoch) emit({type:'closed',peer:conn.peer}); });
  }
  window.OozePeer = {
    start(isHost, code, attempt=0) {
      this.close(); host=!!isHost; const token=epoch; let opened=false;
      if (typeof Peer !== 'function') { emit({type:'error',message:'PeerJS did not load. Refresh the page.'}); return; }
      if (!host && !/^[A-HJ-NP-Z2-9]{4}$/.test(code)) { emit({type:'error',message:'Enter the four-character room code.'}); return; }
      let id;
      if (host) { const bytes=crypto.getRandomValues(new Uint8Array(4));const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';id=prefix+Array.from(bytes,b=>alphabet[b%alphabet.length]).join(''); }
      peer=host?new Peer(id,{debug:0}):new Peer({debug:0});
      peer.on('open', id => { if(token!==epoch)return;const first=!opened;opened=true;emit({type:'open',code:host?id.slice(prefix.length):code});if(!host && first)bind(peer.connect(prefix+code,{reliable:true,serialization:'raw'}),token); });
      peer.on('connection', conn => { if(token!==epoch || !host){conn.close();return;}bind(conn,token); });
      peer.on('error', err => { if(token!==epoch)return; if(host && err.type==='unavailable-id' && attempt<5 && !opened){this.start(true,'',attempt+1);return;} if(opened && err.type==='network')return;   /* the room service socket dropped; live data channels survive and 'disconnected' reports it */ emit({type:'error',message:err.type==='peer-unavailable'?'Room not found. Check the code and keep the host online.':'Connection failed ('+err.type+'). Try another network or recreate the room.'}); });
      peer.on('disconnected', () => { if(token===epoch)emit({type:'signalling-lost'}); });
    },
    send(id, data) { const conn=links.get(id); if(!conn || !conn.open)return false; if(data.startsWith('{"kind":"state"') && (conn.bufferSize>0 || (conn.dataChannel && conn.dataChannel.bufferedAmount>65536)))return false;conn.send(data);return true; },
    closePeer(id) { const conn=links.get(id);if(conn)conn.close(); },
    poll() { const result=JSON.stringify(events);events=[];return result; },
    close() { epoch++; for(const conn of links.values())conn.close();links.clear();if(peer)peer.destroy();peer=null;events=[]; }
  };
})();
