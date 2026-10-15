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
      try { if (D.meas && this.context === D.godot()) D.tapSource(this); } catch (e) { note(e, "tap"); }
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
  // 0.23.3 measurement: which stage of Godot's effect chain is silent on a phone (buffer data / after the source / at the output)
  D.edges = [];
  D.destNodes = [];
  try {
    var N = window.AudioNode && window.AudioNode.prototype, c0 = N && N.connect;
    if (c0) N.connect = function (dest) {
      try {
        if (D.edges.length < 600) D.edges.push([this, dest]);
        if (window.AudioDestinationNode && dest instanceof AudioDestinationNode && D.destNodes.indexOf(this) < 0) D.destNodes.push(this);
      } catch (e) {}
      return c0.apply(this, arguments);
    };
  } catch (e) {}
  function peakOf(an) {
    var b = new Float32Array(an.fftSize); an.getFloatTimeDomainData(b);
    var p = 0; for (var i = 0; i < b.length; i++) { var v = Math.abs(b[i]); if (v > p) p = v; } return p;
  }
  function pathGains(src) {                         // the gain values along the first path from the source to the destination
    var out = [], cur = src, k = 0;
    while (cur && k < 12) {
      var nxt = null;
      for (var i = 0; i < D.edges.length; i++) if (D.edges[i][0] === cur) { nxt = D.edges[i][1]; break; }
      if (!nxt || !(nxt instanceof AudioNode)) break;
      if (window.GainNode && nxt instanceof GainNode) out.push(nxt.gain.value.toFixed(3));
      if (window.AudioDestinationNode && nxt instanceof AudioDestinationNode) { out.push("OUT"); break; }
      cur = nxt; k++;
    }
    return out.join(">");
  }
  D.tapSource = function (s) {
    var m = D.meas; if (!m || m.src_tapped) return;
    m.src_tapped = true;
    try { s.connect(m.a_src); } catch (e) {}
    try {
      var b = s.buffer, p = 0;
      if (b) { m.buf_ch = b.numberOfChannels; m.buf_rate = b.sampleRate; m.buf_len = b.length;
        for (var c = 0; c < b.numberOfChannels; c++) { var d = b.getChannelData(c); for (var i = 0; i < d.length; i += 4) { var v = Math.abs(d[i]); if (v > p) p = v; } } }
      m.buf_peak = p;
    } catch (e) { m.buf_peak = -1; }
    setTimeout(function () { try { m.path = pathGains(s); } catch (e) {} }, 30);
  };
  function kind(n) {
    var k = (n && n.constructor && n.constructor.name) || "?";
    return k.replace("AudioWorkletNode", "Worklet").replace("GainNode", "Gain").replace("ChannelMergerNode", "Merger");
  }
  function levels(an) {                              // [peak, mean] of one analyser read (mean = the steady offset)
    var b = new Float32Array(an.fftSize); an.getFloatTimeDomainData(b);
    var p = 0, s = 0; for (var i = 0; i < b.length; i++) { var v = b[i]; s += v; if (Math.abs(v) > p) p = Math.abs(v); }
    return [p, s / b.length];
  }
  D.arm = function () {                              // called right before the game effect of a TEST plays
    var c = D.godot(); if (!c) return false;
    var m = D.meas = { a_src: c.createAnalyser(), src_peak: 0, buf_peak: -2, buf_ch: 0, buf_rate: 0, buf_len: 0, path: "",
      feeds: [], ch: c.destination.channelCount + "/" + c.destination.maxChannelCount };
    m.a_src.fftSize = 2048;
    D.destNodes.forEach(function (n) {               // every node feeding the speakers, each on its own meter
      try {
        if (n.context !== c) return;
        var a = c.createAnalyser(); a.fftSize = 2048; n.connect(a);
        m.feeds.push({ n: n, a: a, k: kind(n), pre: 0, pre_dc: 0, peak: 0, dc: 0, ch: n.channelCount });
      } catch (e) {}
    });
    var t0 = Date.now();
    (function poll() {
      if (D.meas !== m) return;
      var early = Date.now() - t0 < 40;              // the first reads come before the effect starts: the baseline
      try {
        m.src_peak = Math.max(m.src_peak, peakOf(m.a_src));
        m.feeds.forEach(function (f) {
          var l = levels(f.a);
          if (early) { f.pre = Math.max(f.pre, l[0]); f.pre_dc = l[1]; }
          f.peak = Math.max(f.peak, l[0]); f.dc = l[1];
        });
      } catch (e) {}
      if (Date.now() - t0 < 700) { setTimeout(poll, 15); return; }
      var fs = m.feeds.map(function (f) {
        return f.k + " " + f.pre.toFixed(2) + ">" + f.peak.toFixed(2) + " dc" + f.dc.toFixed(2) + " c" + f.ch;
      }).join(" | ");
      D.test.meas = "data " + m.buf_peak.toFixed(2) + " (" + m.buf_ch + "ch " + m.buf_rate + ")  src " + m.src_peak.toFixed(2) +
        "  out " + m.ch + ": " + fs + "  path " + (m.path || "?");
      try { m.a_src.disconnect(); m.feeds.forEach(function (f) { try { f.n.disconnect(f.a); } catch (e) {} }); } catch (e) {}
      D.meas = null;
    })();
    return true;
  };
  D.runTest = function (gapMs, beepMs, hz, gain) {
    var t = D.test = { godot: "", fresh: "", fresh_made: "", meas: D.test.meas_pending || "", runs: (D.test.runs || 0) + 1 };
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
