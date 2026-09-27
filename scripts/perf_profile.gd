class_name PerfProfile
extends RefCounted
## STUB (Alpha 21 OPT-MESH, ahead of OPT-RENDER's GRAPHICS setting). hd() is the one question
## Cosmetics.kit_path() asks to pick the light or HD kit: until opt-render's AUTO / FULL / LOW RES
## switch merges and replaces this file, hd() answers with just AUTO's rule - HD on desktop, light
## on a phone screen or a desktop run forcing the phone profile (MapPool.phone, set once by main.gd
## at startup from the real screen size or --mobile). Replace this whole file, not call sites: every
## caller only ever asks PerfProfile.hd().


static func hd() -> bool:
	return not MapPool.phone
