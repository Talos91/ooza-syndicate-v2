// AUDIO DIAG (branch audio-diag, 2026-09-29): Daniele's Android phone plays the music (music.js) but no sound effects,
// and desktop Chrome / its phone emulation cannot reproduce it. This file only WATCHES, for SETTINGS > TEST SOUND and its
// AUDIO readout (scripts/audio_diag.gd): loaded in the page head before music.js and index.js, it wraps the
// AudioContext constructor so every context the page makes is remembered (the real instance is returned, instanceof
// still works), counts AudioBufferSourceNode.start calls (Godot's sample playback starts one per effect), keeps each
// context's state changes and the last audio error. It never resumes, suspends or connects anything - except inside
// runTest(), the TEST's two raw beeps (one on Godot's own context, one on a fresh context made for the test).
// Godot's context = the first one made that is not music.js's (window.OozeMusic.ctx); test contexts are not counted.
(function () {
  var D = window.OozeAudioDiag = { contexts: [], history: [], starts: 0, startsGodot: 0, err: "", test: {} };
  function note(e, where) {
    try { D.err = (where + ": " + (e && e.name ? e.name + " " : "") + String(e && e.message || e || "")).slice(0, 100); } catch (x) {}
  }
  D.godot = function () {
    var m = window.OozeMusic && window.OozeMusic.ctx;
    for (var i = 0; i < D.contexts.length; i++) if (D.contexts[i] !== m) return D.contexts[i];
    return null;
  };
  function ms(v) { return (typeof v === "number" && isFinite(v)) ? Math.round(v * 1000) : -1; }
  D.state = function () {
    var g = D.godot(), m = window.OozeMusic && window.OozeMusic.ctx;
    return { n: D.contexts.length, state: g ? g.state : "none", rate: g ? g.sampleRate : 0,
      base_ms: g ? ms(g.baseLatency) : -1, out_ms: g ? ms(g.outputLatency) : -1,
      time: g ? Math.round(g.currentTime * 10) / 10 : -1, history: D.history.join(" ").slice(-60),
      music: m ? m.state : "none", starts: D.starts, starts_godot: D.startsGodot, err: D.err, test: D.test,
      android: /Android/i.test(navigator.userAgent), visible: document.visibilityState || "" };
  };
  var Orig = window.AudioContext || window.webkitAudioContext;
  if (!Orig) { D.err = "no AudioContext"; D.runTest = function () { return false; }; return; }
  // --- the passive capture
  function Wrapped(opts) {
    var c = arguments.length ? new Orig(opts) : new Orig();
    try {
      var i = D.contexts.length;
      D.contexts.push(c);
      D.history.push(i + ":" + c.state);
      c.addEventListener("statechange", function () {
        D.history.push(i + ":" + c.state);
        if (D.history.length > 12) D.history.shift();
      });
    } catch (e) { note(e, "capture"); }
    return c;
  }
  Wrapped.prototype = Orig.prototype;
  try { Object.setPrototypeOf(Wrapped, Orig); } catch (e) {}
  if (window.AudioContext) window.AudioContext = Wrapped;
  if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
  try {                                             // count the sample starts (a pass-through)
    var S = window.AudioBufferSourceNode && window.AudioBufferSourceNode.prototype, s0 = S && S.start;
    if (s0) S.start = function () {
      try { D.starts++; if (this.context === D.godot()) D.startsGodot++; } catch (e) {}
      try { return s0.apply(this, arguments); } catch (e) { note(e, "start"); throw e; }
    };
  } catch (e) {}
  try {                                             // a refused resume() (autoplay policy) is remembered
    var P = Orig.prototype, r0 = P.resume;
    if (r0) P.resume = function () {
      var p = r0.apply(this, arguments);
      try { if (p && p.catch) p.catch(function (e) { note(e, "resume"); }); } catch (e) {}
      return p;
    };
  } catch (e) {}
  window.addEventListener("error", function (ev) {
    var msg = String(ev && ev.message || "");
    if (/audio|sample|sound|decode/i.test(msg)) note(msg, "page");
  });
  window.addEventListener("unhandledrejection", function (ev) {
    var r = ev && ev.reason, msg = String(r && (r.name + " " + r.message) || r || "");
    if (/audio|sample|sound|decode|NotAllowed/i.test(msg)) note(msg, "promise");
  });
  // --- the TEST (SETTINGS > TEST SOUND): Godot plays its effect itself at 0; here beep B on Godot's context after gapMs
  // (not resumed: its state as it is), beep C on a context made now, inside the tap, after 2 x gapMs (resumed if needed).
  function beep(c, dur, hz, gain, mayResume) {
    if (!c) return "no context";
    try {
      var st = c.state;
      if (mayResume && st !== "running") c.resume();
      var o = c.createOscillator(), g = c.createGain(), t0 = c.currentTime + 0.02, t1 = t0 + dur;
      o.frequency.value = hz;
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(gain, t0 + 0.02);
      g.gain.setValueAtTime(gain, Math.max(t0 + 0.03, t1 - 0.04));
      g.gain.exponentialRampToValueAtTime(0.0001, t1);
      o.connect(g); g.connect(c.destination);
      o.onended = function () { try { o.disconnect(); g.disconnect(); } catch (e) {} };
      o.start(t0); o.stop(t1 + 0.02);
      return "started " + st;
    } catch (e) { note(e, "beep"); return "error " + (e && e.name || e); }
  }
  D.runTest = function (gapMs, beepMs, hz, gain) {
    var t = D.test = { godot: "", fresh: "", fresh_made: "", runs: (D.test.runs || 0) + 1 };
    var fresh = null;
    try { fresh = new Orig(); t.fresh_made = fresh.state; } catch (e) { t.fresh = "error " + (e && e.name || e); note(e, "test"); }
    setTimeout(function () { t.godot = beep(D.godot(), beepMs / 1000, hz, gain, false); }, gapMs);
    setTimeout(function () {
      if (!fresh) return;
      t.fresh = beep(fresh, beepMs / 1000, hz, gain, true);
      setTimeout(function () { try { t.fresh_after = fresh.state; fresh.close(); } catch (e) {} }, beepMs + 400);
    }, gapMs * 2);
    return true;
  };
})();
