/* Ooze Syndicate 2.0 - pick up a new build by itself (Alpha 16). Godot's PWA service worker serves the
   cached game first, and a new build's worker waits until every tab of the game is closed - so phones
   and installed apps kept showing an old alpha. This asks for the new worker on every load and, once
   it is installed, tells it to take over ('update' is handled by Godot's own worker: skipWaiting,
   claim, reload the page). */
(()=>{
 if (!('serviceWorker' in navigator)) return;
 let kicked = false;
 const kick = w => { if (w && !kicked) { kicked = true; w.postMessage('update'); } };
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
  reg.update().catch(() => {});
 }
 addEventListener('load', () => navigator.serviceWorker.getRegistration().then(watch).catch(() => {}));
 setInterval(() => navigator.serviceWorker.getRegistration().then(r => r && r.update()).catch(() => {}), 10 * 60 * 1000);
})();
