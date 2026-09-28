/* TEST ONLY (tests/ are not exported): simulate an iPhone home-screen app in a desktop browser pane - the iOS UA,
   navigator.standalone, portrait screen numbers (the pane's size), safe-area insets (59 / 21 landscape) and iOS's
   innerHeight short by 59 px in landscape. Use: export Web, copy web/*.js and this file into build/web, copy index.html
   with <script src="ios_sim.js"></script> before viewport-fix.js, serve on localhost, open portrait, resize landscape. */
(()=>{
 const d = n => Object.getOwnPropertyDescriptor(window, n) || Object.getOwnPropertyDescriptor(Window.prototype, n);
 const rw = d('innerWidth').get, rh = d('innerHeight').get;
 Object.defineProperty(navigator, 'userAgent', {get: () => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'});
 Object.defineProperty(navigator, 'standalone', {get: () => true});
 Object.defineProperty(screen, 'width', {get: () => Math.min(rw.call(window), rh.call(window))});
 Object.defineProperty(screen, 'height', {get: () => Math.max(rw.call(window), rh.call(window))});
 const land = () => rw.call(window) > rh.call(window);
 Object.defineProperty(window, 'innerWidth', {configurable: true, get: () => rw.call(window)});
 Object.defineProperty(window, 'innerHeight', {configurable: true, get: () => rh.call(window) - (land() ? 59 : 0)});
 const css = document.createElement('style');
 css.textContent = ':root{}';
 document.head.appendChild(css);
 window.__iosSimInsets = () => land() ? [59, 0, 59, 21] : [0, 59, 0, 34];
 addEventListener('DOMContentLoaded', () => { if (window.OozeViewport) OozeViewport.safe = window.__iosSimInsets; });
})();
