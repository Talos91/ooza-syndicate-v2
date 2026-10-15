/* Ooze Syndicate 2.0 - phone fullscreen gate as native DOM (Alpha 16). Replaces the in-game gate:
   Daniele's Android kept showing "go fullscreen" although the phone was already fullscreen, and the
   prompt could not be left. Here the button calls requestFullscreen inside the real tap (browsers only
   grant it to a user gesture), "already fullscreen" also counts a page that covers the whole screen
   (installed app, immersive browsers), and CLOSE / "continue in the browser" dismiss it for the tab. */
(()=>{
 const ua = navigator.userAgent;
 const ios = /iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(ua));
 const mobile = ios || /Android/i.test(ua);
 const KEY = 'ooze20-windowed';
 let skipped = false, panel = null, note = null;
 try { skipped = sessionStorage.getItem(KEY) === '1'; } catch (e) {}
 function isFull() {
  if (document.fullscreenElement || document.webkitFullscreenElement) return true;
  for (const m of ['fullscreen', 'standalone', 'minimal-ui']) if (matchMedia('(display-mode: ' + m + ')').matches) return true;
  if (navigator.standalone === true) return true;
  const w = Math.max(innerWidth, innerHeight), h = Math.min(innerWidth, innerHeight);
  const sw = Math.max(screen.width, screen.height), sh = Math.min(screen.width, screen.height);
  return w >= sw - 4 && h >= sh - 4;            // the page already covers the screen
 }
 function skip() { skipped = true; try { sessionStorage.setItem(KEY, '1'); } catch (e) {} update(); }
 // 0.22.3: one request path for every caller - the gate's button, any tap on the page while the document is not
 // fullscreen (Daniele: "the game doesn't open anymore in full screen ... often shows the navbar"), and the game's
 // FULLSCREEN buttons (main menu, PAUSE > SETTINGS) through OozeGate.request(). Chrome on Android only grants
 // requestFullscreen inside a user gesture (a tap's pointerup / click, or the ~5 s of transient activation after
 // it), and drops fullscreen on a Back gesture, a rotation, or the notification shade - after which the next tap
 // brings it back. The landscape lock runs after the request settles, in its own try/catch: a refused lock never
 // aborts the fullscreen request. Requests are throttled (one per 1.5 s) so a tap + the button's click, or the
 // engine's own handling of the same tap, never queue two.
 let lastReq = 0;
 function request() {
  skipped = false; try { sessionStorage.removeItem(KEY); } catch (e) {}
  const el = document.documentElement, req = el.requestFullscreen || el.webkitRequestFullscreen;
  if (!req) return null;
  const now = Date.now();
  if (now - lastReq < 1500) return null;
  lastReq = now;
  const lock = () => { try { screen.orientation.lock('landscape').then(() => { locked = true; }, () => {}); } catch (e) {} };
  try {
   const p = req.call(el, {navigationUI: 'hide'});
   if (p && p.then) return p.then(() => { lock(); update(); });
   lock(); return Promise.resolve();
  } catch (e) { return Promise.reject(e); }
 }
 function go() {                          // the gate's PLAY FULLSCREEN button
  const el = document.documentElement;
  if (!(el.requestFullscreen || el.webkitRequestFullscreen)) { note.textContent = 'This browser has no fullscreen - use Continue below.'; return; }
  const p = request();
  if (p) p.catch(() => { note.textContent = 'The browser refused fullscreen - use Continue below.'; });
 }
 function reallyFull() { return !!(document.fullscreenElement || document.webkitFullscreenElement); }
 function onTap() {                       // any tap while the document is not fullscreen (Android; iPhone has no API)
  if (ios || !mobile || skipped || reallyFull()) return;
  const p = request();
  if (p) p.catch(() => {});
 }
 function build() {
  const style = document.createElement('style');
  style.textContent = `#ooze-gate{position:fixed;inset:0;z-index:1400;background:#031017f2;display:grid;place-items:center;padding:12px;box-sizing:border-box;color:#e5fcff;font:18px system-ui;text-align:center;touch-action:manipulation}#ooze-gate[hidden]{display:none}#ooze-gate section{max-width:560px}#ooze-gate h2{font:800 26px system-ui;margin:6px 0 12px;letter-spacing:1px}#ooze-gate button{min-height:52px;font:700 20px system-ui;padding:12px 26px;margin:8px;color:#001720;background:#19dce8;border:0;touch-action:manipulation}#ooze-gate .x{position:fixed;top:max(8px,env(safe-area-inset-top));right:max(8px,env(safe-area-inset-right));background:#0d2632;color:#e5fcff;border:1px solid #19dce8;min-height:44px;padding:6px 14px;font-size:16px}#ooze-gate a{display:inline-block;margin-top:14px;color:#8fb3c0;font-size:15px;padding:8px}#ooze-gate p{line-height:1.4;margin:6px}`;
  document.head.appendChild(style);
  panel = document.createElement('div'); panel.id = 'ooze-gate'; panel.hidden = true;
  const box = document.createElement('section');
  const h = document.createElement('h2'); h.textContent = 'OOZE SYNDICATE PLAYS FULLSCREEN';
  box.append(h);
  if (ios) {
   const p = document.createElement('p'); p.textContent = 'On iPhone and iPad: Safari → Share → Add to Home Screen, then open the new icon with the phone sideways.';
   box.append(p);
  } else {
   const b = document.createElement('button'); b.type = 'button'; b.textContent = 'PLAY FULLSCREEN'; b.onclick = go;
   const p = document.createElement('p'); p.textContent = 'Turn your phone sideways.';
   box.append(b, p);
  }
  note = document.createElement('p'); note.style.color = '#ffd15c';
  const a = document.createElement('a'); a.href = '#'; a.textContent = 'continue in the browser window';
  a.onclick = e => { e.preventDefault(); skip(); };
  const x = document.createElement('button'); x.type = 'button'; x.className = 'x'; x.textContent = 'CLOSE ×'; x.onclick = skip;
  box.append(note, a); panel.append(box, x); document.body.append(panel);
 }
 // LANDSCAPE (Daniele, 2026-09-28: "force the game open in landscape" until there is a store app). The installed app's
 // manifest already asks for landscape and fullscreen locks it (go() above); here: lock whenever the browser allows it
 // (installed app / fullscreen), and in portrait cover the game with "turn your phone sideways" - the only way on iPhone,
 // where Safari never locks. It sits above the fullscreen gate and goes away the moment the phone is turned.
 let rot = null;
 let locked = false;                     // lock once per fullscreen / installed-app session (a lock can trigger a resize)
 function tryLock() {
  if (locked || !(isFull() || matchMedia('(display-mode: standalone)').matches)) return;
  try {
   if (screen.orientation && screen.orientation.lock)
    screen.orientation.lock('landscape').then(() => { locked = true; }, () => { locked = true; });   // refused: don't retry
  } catch (e) { locked = true; }
 }
 for (const ev of ['fullscreenchange', 'webkitfullscreenchange']) addEventListener(ev, () => { locked = false; });
 function portrait() { return innerHeight > innerWidth * 1.05; }
 function buildRot() {
  const st = document.createElement('style');
  st.textContent = `#ooze-rotate{position:fixed;inset:0;z-index:1500;background:#02030a;display:grid;place-items:center;color:#c9f7fb;font:700 20px system-ui;text-align:center;touch-action:none}#ooze-rotate[hidden]{display:none}#ooze-rotate .ph{width:74px;height:124px;border:5px solid #19dce8;border-radius:14px;margin:0 auto 26px;box-shadow:0 0 18px #19dce8;animation:oozerot 2.2s ease-in-out infinite;position:relative}#ooze-rotate .ph:after{content:'';position:absolute;left:50%;bottom:8px;width:16px;height:4px;margin-left:-8px;border-radius:2px;background:#19dce8}@keyframes oozerot{0%,20%{transform:rotate(0)}55%,80%{transform:rotate(-90deg)}100%{transform:rotate(0)}}#ooze-rotate p{margin:6px 16px;letter-spacing:1px}#ooze-rotate small{display:block;margin-top:10px;font:500 15px system-ui;color:#7fa9b4}`;
  document.head.appendChild(st);
  rot = document.createElement('div'); rot.id = 'ooze-rotate'; rot.hidden = true;
  rot.innerHTML = '<div><div class="ph"></div><p>TURN YOUR PHONE SIDEWAYS</p><small>Ooze Syndicate plays in landscape</small></div>';
  document.body.append(rot);
 }
 function update() {
  if (!mobile) return;
  if (!panel) { if (!document.body) return; build(); }
  if (!rot) buildRot();
  const up = portrait();
  rot.hidden = !up;
  panel.hidden = up || skipped || isFull();
  if (!up && !locked) tryLock();
 }
 for (const ev of ['fullscreenchange', 'webkitfullscreenchange', 'resize', 'orientationchange']) addEventListener(ev, update);
 document.addEventListener('DOMContentLoaded', update);
 setInterval(update, 1000);
 document.addEventListener('pointerdown', tryLock, {passive: true});   // a tap is the gesture some browsers want for the lock
 // the re-entry tap: pointerup (a touch's activation event; pointerdown is not one for touch) and click, captured before
 // the engine's canvas handlers - they preventDefault but never stop propagation
 for (const ev of ['pointerup', 'click']) document.addEventListener(ev, onTap, {capture: true, passive: true});
 window.OozeGate = {update, isFull, portrait, request, reallyFull};
})();
