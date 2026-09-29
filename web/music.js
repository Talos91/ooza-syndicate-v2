// Ooze Syndicate 2.0 - the soundtrack on the web (music.gd drives it through JavaScriptBridge; 0.22.4, 🎵 Music).
// Two <audio> elements, each through a MediaElementSource -> GainNode -> a master GainNode, in the SAME AudioContext
// Godot's audio (the SFX) makes and unlocks on the first tap: the browser streams and decodes the tracks off the main
// thread (no per-frame Godot mixing, no whole-track PCM in memory), and the gains do volume / crossfade / duck / mute
// (iOS ignores <audio>.volume). Loaded in the page head, before the engine, so the AudioContext constructor can be
// wrapped to catch Godot's context. Every failure (no WebAudio, a 404, autoplay refused, offline) is silence, never
// an error. The tracks: music/<name>.ogg (desktop, stereo 44.1 kHz) or music_phone/<name>.ogg (mono 22 kHz) beside
// index.html, fetched per track on demand (tools/copy_music.py --web; BUILD-LOG sec10).
(function () {
  "use strict";
  var AC = window.AudioContext || window.webkitAudioContext;
  var M = window.OozeMusic = {
    ctx: null, master: null, els: [null, null], gains: [null, null], wanted: [false, false], failed: [false, false],
    hidden: false
  };
  // 0.23.0 (Daniele: sound effects silent on his phone while the music played): the music has its OWN AudioContext,
  // made on the first tap (a user gesture - iOS / Android allow it then) and resumed on every tap; it no longer shares
  // Godot's context, so the <audio> elements can never interfere with the game's effects.
  function build() {                             // the elements and gains, once, in Godot's context
    if (M.master) return true;
    try {
      if (!M.ctx) { if (!AC) return false; M.ctx = new AC(); }   // our own context (see above)
      M.master = M.ctx.createGain();
      M.master.gain.value = 0;
      M.master.connect(M.ctx.destination);
      for (var i = 0; i < 2; i++) {
        var a = new Audio();
        a.preload = "auto";
        a.setAttribute("playsinline", "");
        (function (k) {
          a.addEventListener("error", function () { if (M.wanted[k]) M.failed[k] = true; });
        })(i);
        var g = M.ctx.createGain();
        g.gain.value = 0;
        M.ctx.createMediaElementSource(a).connect(g);
        g.connect(M.master);
        M.els[i] = a;
        M.gains[i] = g;
      }
      return true;
    } catch (e) {
      M.master = null;
      return false;
    }
  }

  function kick(i) {                             // (re)start a wanted element; a refused autoplay waits for a tap
    var a = M.els[i];
    if (!a || !M.wanted[i] || M.hidden) return;
    try {
      var p = a.play();
      if (p && p.catch) p.catch(function () {});
    } catch (e) {}
  }

  function unlock() {                            // every tap: resume the context, retry what autoplay refused
    build();                                     // the first tap makes our context and elements (a user gesture)
    try { if (M.ctx && M.ctx.state !== "running" && !M.hidden) M.ctx.resume(); } catch (e) {}
    for (var i = 0; i < 2; i++) if (M.wanted[i] && M.els[i] && M.els[i].paused) kick(i);
  }
  ["pointerdown", "touchend", "keydown", "click"].forEach(function (ev) {
    window.addEventListener(ev, unlock, { capture: true, passive: true });
  });
  document.addEventListener("visibilitychange", function () {   // a hidden tab (phone locked, app switched): quiet
    M.hidden = document.hidden;
    for (var i = 0; i < 2; i++) {
      if (!M.els[i] || !M.wanted[i]) continue;
      if (M.hidden) M.els[i].pause(); else kick(i);
    }
  });

  // ---- what music.gd calls (JavaScriptBridge.get_interface("OozeMusic")) ----
  M.available = function () { return !!AC; };
  M.start = function (i, url) {                  // element i plays url from the start (its gain is set by the caller)
    if (!build()) return false;
    var a = M.els[i];
    M.wanted[i] = true;
    M.failed[i] = false;
    try { a.src = url; a.currentTime = 0; } catch (e) { M.failed[i] = true; return false; }
    kick(i);
    return true;
  };
  M.stop = function (i) {                        // element i silent and its buffer freed
    var a = M.els[i];
    M.wanted[i] = false;
    if (!a) return;
    try { a.pause(); a.removeAttribute("src"); a.load(); } catch (e) {}
  };
  M.gain = function (i, v) { if (M.gains[i]) M.gains[i].gain.value = v; };
  M.level = function (v) { if (M.master) M.master.gain.value = v; };
  M.playing = function (i) {                     // wanted and not finished (a pending start counts as playing)
    var a = M.els[i];
    return !!a && M.wanted[i] && !M.failed[i] && !a.ended;
  };
  M.ended = function (i) {                       // played to its end (not failed, not stopped)
    var a = M.els[i];
    return !!a && M.wanted[i] && !M.failed[i] && a.ended;
  };
  M.pos = function (i) { var a = M.els[i]; return a ? a.currentTime || 0 : 0; };
  M.len = function (i) {                         // -1 until the metadata is in
    var a = M.els[i];
    return a && isFinite(a.duration) && a.duration > 0 ? a.duration : -1;
  };
})();
