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
 function go() {
  const el = document.documentElement, req = el.requestFullscreen || el.webkitRequestFullscreen;
  if (!req) { note.textContent = 'This browser has no fullscreen - use Continue below.'; return; }
  try {
   const p = req.call(el, {navigationUI: 'hide'});
   const lock = () => { try { screen.orientation.lock('landscape').catch(() => {}); } catch (e) {} };
   if (p && p.then) p.then(lock, () => { note.textContent = 'The browser refused fullscreen - use Continue below.'; }); else lock();
  } catch (e) { note.textContent = 'The browser refused fullscreen - use Continue below.'; }
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
 function update() {
  if (!mobile) return;
  if (!panel) { if (!document.body) return; build(); }
  panel.hidden = skipped || isFull();
 }
 for (const ev of ['fullscreenchange', 'webkitfullscreenchange', 'resize', 'orientationchange']) addEventListener(ev, update);
 document.addEventListener('fullscreenchange', update);
 document.addEventListener('DOMContentLoaded', update);
 setInterval(update, 1000);
 window.OozeGate = {update, isFull};
})();
