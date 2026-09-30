/* Ooze Syndicate 2.0 - the game fills the real screen on iPhone (Alpha 21). An iPhone 14 Pro home-screen app in
   landscape showed a black band over the bottom ~15 % below the skill dock: Godot sizes its canvas from
   window.innerWidth / innerHeight every frame (canvas_resize_policy 2), and iOS standalone web apps report an
   innerHeight short by the portrait status bar (393 - 59 = 334 CSS px on a 14 Pro) after a rotation - or a
   stale one from the other orientation - while the page itself covers the whole screen (viewport-fit=cover,
   black-translucent status bar). Here, in a standalone / fullscreen page only, innerWidth / innerHeight give
   the real screen size when the reported one falls short of it; the canvas is pinned to the top-left corner
   (a rotation can leave the page scrolled); and OozeViewport.safe() hands the game the safe-area insets
   (notch / Dynamic Island / home indicator, CSS px) so the HUD stays clear of them (main._apply_safe_area).
   A browser tab (toolbars in view) keeps the browser's own numbers. */
(()=>{
 const own = n => Object.getOwnPropertyDescriptor(window, n) || Object.getOwnPropertyDescriptor(Window.prototype, n);
 const dw = own('innerWidth'), dh = own('innerHeight');
 if (!dw || !dh || !dw.get || !dh.get) return;
 const nativeW = () => dw.get.call(window), nativeH = () => dh.get.call(window);
 const ua = navigator.userAgent;
 const ios = /iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(ua));
 function covering() {                      // the page is meant to cover the whole screen
  if (navigator.standalone === true) return true;
  for (const m of ['fullscreen', 'standalone']) if (matchMedia('(display-mode: ' + m + ')').matches) return true;
  return !!(document.fullscreenElement || document.webkitFullscreenElement);
 }
 function size() {
  let w = nativeW(), h = nativeH();
  if (!ios || !covering()) return [w, h];
  const land = matchMedia('(orientation: landscape)').matches;
  const a = screen.width, b = screen.height;  // iOS: always the portrait numbers
  const sw = land ? Math.max(a, b) : Math.min(a, b), sh = land ? Math.min(a, b) : Math.max(a, b);
  // short by up to a quarter (a status bar, a home indicator, the other orientation's leftovers): the screen
  if (w < sw && w >= sw * 0.75) w = sw;
  if (h < sh && h >= sh * 0.75) h = sh;
  return [w, h];
 }
 try {
  Object.defineProperty(window, 'innerWidth', {configurable: true, get: () => size()[0], set: v => {}});
  Object.defineProperty(window, 'innerHeight', {configurable: true, get: () => size()[1], set: v => {}});
 } catch (e) { return; }
 const style = document.createElement('style');
 style.textContent = 'html,body{margin:0;height:100%;overflow:hidden;background:#000}' +
  '#canvas{position:fixed;left:0;top:0}' +
  '#ooze-safe-probe{position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;' +
  'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)}';
 document.head.appendChild(style);
 let probe = null;
 function safe() {                          // [left, top, right, bottom] in CSS px
  if (!probe) {
   if (!document.body) return [0, 0, 0, 0];
   probe = document.createElement('div'); probe.id = 'ooze-safe-probe'; document.body.appendChild(probe);
  }
  const cs = getComputedStyle(probe), px = s => parseFloat(s) || 0;
  return [px(cs.paddingLeft), px(cs.paddingTop), px(cs.paddingRight), px(cs.paddingBottom)];
 }
 function settle() {                        // iOS finishes a rotation (and hides its bars) a little later
  if (covering()) window.scrollTo(0, 0);
  for (const ms of [50, 250, 600, 1200]) setTimeout(() => { if (covering()) window.scrollTo(0, 0); dispatchEvent(new Event('ooze-viewport')); }, ms);
 }
 addEventListener('orientationchange', settle);
 addEventListener('resize', settle);
 addEventListener('pageshow', settle);
 if (window.visualViewport) visualViewport.addEventListener('resize', settle);
 window.OozeViewport = {size, safe, nativeSize: () => [nativeW(), nativeH()], covering};
})();
