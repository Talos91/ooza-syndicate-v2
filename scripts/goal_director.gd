class_name GoalDirector
extends RefCounted
## A generic goal list with an event timeline (TUTORIAL-REWRITE-DESIGN.md §4). STANDALONE: it knows nothing of the Sim,
## the tutorial, the campaign or any UI - only goals, a clock and callables. TutorialDirector (tutorial.gd) sits on top
## of it (a tutorial adds its coach card, reveal stages and rival scripts); a later job may move MissionDirector onto it
## too (its stars, timer and briefing would sit on top the same way). Pure logic, headless-testable.
##
## A goal is a Dictionary:
##   id        String            unique
##   check     Callable(ctx)     -> bool (done) or float (progress 0..1, done at >= 1); called every tick while the goal is
##                               open and its stage is unlocked (optional: a goal can be ticked from outside with complete())
##   stage     int   = 0         the goal is live once `stage_unlocked() >= stage`
##   optional  bool  = false     an optional goal never holds all_done() back
##   assist    Callable(ctx, dt) run every tick while the goal is open and live (a scripted rival line, a top-up ...)
##   follow    Callable(ctx)     -> Array of world points the goal wants lit (cheap: a few samples, no scene lookups)
##   ready     Callable(ctx)     -> bool; a live goal that is not ready is skipped by current() (it cannot be done yet)
##   any other keys are the caller's (a tutorial keeps its hint line and hand provider there)
## Goals are done in ANY order; current() is the first open, live, ready goal in list order.
##
## The timeline: events {at: seconds | when: Callable(ctx) -> bool, do: Callable(ctx), once: bool = true}. `at` compares
## with the clock (tick(dt, now) passes the match clock, else the sum of the dts).
##
## API: add_goal / add_event, tick(dt, now := -1.0), open_goals(), live_goals(), current(), goal(id), goal_done(id),
## complete(id), skip(id), progress(id), done_count(), all_done(), stage_unlocked() / unlock_stage(n), follow_points().
## Signals: goal_completed(id, skipped), all_completed.

signal goal_completed(id: String, skipped: bool)
signal all_completed

var ctx = null                                      # what the callables receive (the layer on top)
var goals: Array = []
var events: Array = []
var time := 0.0                                     # the clock (tick's `now`, or the sum of dts)
var _stage := 0
var _done_all := false


func _init(context = null) -> void:
	ctx = context


# ---------------------------------------------------------------- building
func add_goal(spec: Dictionary) -> Dictionary:
	var g := spec.duplicate()
	g["done"] = false
	g["skipped"] = false
	g["progress"] = 0.0
	g["done_at"] = -1.0
	if not g.has("stage"):
		g["stage"] = 0
	if not g.has("optional"):
		g["optional"] = false
	goals.append(g)
	return g


func add_event(spec: Dictionary) -> void:
	var e := spec.duplicate()
	e["fired"] = false
	if not e.has("once"):
		e["once"] = true
	events.append(e)


# ---------------------------------------------------------------- the frame
func tick(dt: float, now := -1.0) -> void:
	time = now if now >= 0.0 else time + dt
	for e in events:
		if e["fired"] and e["once"]:
			continue
		var due := false
		if e.has("at"):
			due = time >= float(e["at"])
		elif e.has("when"):
			due = bool((e["when"] as Callable).call(ctx))
		if due:
			e["fired"] = true
			if e.has("do"):
				(e["do"] as Callable).call(ctx)
	for g in goals:
		if g["done"] or not is_live(g):
			continue
		if g.has("check"):
			var r = (g["check"] as Callable).call(ctx)
			if r is bool:
				if r:
					_finish(g, false)
					continue
			elif r != null:
				g["progress"] = clampf(float(r), 0.0, 1.0)
				if float(r) >= 1.0:
					_finish(g, false)
					continue
		if g.has("assist"):
			(g["assist"] as Callable).call(ctx, dt)


func _finish(g: Dictionary, skipped: bool) -> void:
	if g["done"]:
		return
	g["done"] = true
	g["skipped"] = skipped
	g["progress"] = 1.0
	g["done_at"] = time
	goal_completed.emit(str(g["id"]), skipped)
	if not _done_all and all_done():
		_done_all = true
		all_completed.emit()


# ---------------------------------------------------------------- queries and control
func goal(id: String) -> Dictionary:
	for g in goals:
		if g["id"] == id:
			return g
	return {}


func goal_done(id: String) -> bool:
	return bool(goal(id).get("done", false))


func progress(id: String) -> float:
	return float(goal(id).get("progress", 0.0))


func complete(id: String) -> void:
	## Tick a goal from outside (a detector the layer runs itself).
	var g := goal(id)
	if not g.is_empty():
		_finish(g, false)


func skip(id: String) -> void:
	## The player skipped it: done for the flow (the next goals open), flagged so the layer can refuse to count it.
	var g := goal(id)
	if not g.is_empty():
		_finish(g, true)


func was_skipped() -> bool:
	for g in goals:
		if g["skipped"]:
			return true
	return false


func stage_unlocked() -> int:
	return _stage


func unlock_stage(n: int) -> bool:
	## true when this opened a new stage.
	if n > _stage:
		_stage = n
		return true
	return false


func is_live(g: Dictionary) -> bool:
	return int(g["stage"]) <= _stage


func open_goals() -> Array:
	return goals.filter(func(g): return not g["done"])


func live_goals() -> Array:
	return goals.filter(func(g): return not g["done"] and is_live(g))


func current() -> Dictionary:
	## The goal to talk about now: the first open, live, ready goal; else the first open live one (its prep hint); else {}.
	var fallback := {}
	for g in goals:
		if g["done"] or not is_live(g):
			continue
		if not g.has("ready") or bool((g["ready"] as Callable).call(ctx)):
			return g
		if fallback.is_empty():
			fallback = g
	return fallback


func done_count() -> int:
	return goals.filter(func(g): return g["done"]).size()


func all_done() -> bool:
	for g in goals:
		if not g["done"] and not g["optional"]:
			return false
	return true


func follow_points() -> Array:
	## What the open, live goals want lit this frame - their own `follow` callables, nothing else.
	var out := []
	for g in goals:
		if g["done"] or not is_live(g) or not g.has("follow"):
			continue
		out.append_array((g["follow"] as Callable).call(ctx))
	return out
