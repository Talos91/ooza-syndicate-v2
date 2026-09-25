/* Ooze Syndicate 2.0 - pick up a new build by itself (Alpha 16). Godot's PWA service worker serves the
   cached game first, and a new build's worker waits until every tab of the game is closed - so phones
   and installed apps kept showing an old alpha. This asks for the new worker on every load and, once
   it is installed, tells it to take over ('update' is handled by Godot's own worker: skipWaiting,
   claim, reload the page), unless a match or a room is on: then it waits until the game is back on
   the menu. */
(()=>{
 if (!('serviceWorker' in navigator)) return;
 let kicked = false, pending = null;
 // The game sets window.oozeBusy while a match or an online room is on (Net.set_busy): a reload
 // then would end the match (and close the room for everyone if this is the host), so the new
 // worker waits for the menu.
 const busy = () => { try { return !!window.oozeBusy; } catch (e) { return false; } };
 const kick = w => { if (!w || kicked) return; if (busy()) { pending = w; return; } kicked = true; w.postMessage('update'); };
 setInterval(() => { if (pending && !busy()) kick(pending); }, 5000);
 function watch(reg) {
  if (!reg) return;
  if (reg.waiting && navigator.serviceWorker.controller) kick(reg.waiting);
  reg.addEventListener('updatefound', () => {
   const nw = reg.installing;
   if (!nw) return;
   nw.addEventListener('statechange', () => {
    if (nw.state === 'installed' && navigator.serviceWorker.controller) kick(nw);
   });
  });
  if (reg.installing) reg.installing.addEventListener('statechange', () => { if (reg.waiting && navigator.serviceWorker.controller) kick(reg.waiting); });
  reg.update().catch(() => {});
  let tries = 0;                                  // the new worker may install before we listen
  const poll = setInterval(() => { if (reg.waiting && navigator.serviceWorker.controller) kick(reg.waiting); if (kicked || ++tries > 15) clearInterval(poll); }, 2000);
 }
 addEventListener('load', () => navigator.serviceWorker.getRegistration().then(watch).catch(() => {}));
 setInterval(() => navigator.serviceWorker.getRegistration().then(r => r && r.update()).catch(() => {}), 10 * 60 * 1000);
})();
