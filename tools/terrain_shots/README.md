# terrain-backdrop-shots (THROWAWAY debug branch, NOT for release)

Debug user args added in `scripts/world_layer.gd` (all off by default; without them the game is unchanged):
- `--floor-tex=<abs png>` an assembled floor image on the arena floor (lab5 shader path); `--floor-tex-m=<metres>` (default 64 = 4 x 16 m tiles); `--floor-gain=<x>` (default 1)
- `--backdrop=<abs png|jpg>` an image as the world backdrop (`--backdrop=lab` = current LAB-SIDE B with a non-lab floor)
- `--floor-r14` with `--floor=lab|factory` = the R14 floors_v2 tiles instead of the lab5 tile

`assemble_floors.py` builds the 64 m blocks from the director's tiles; `shoot.sh` shoots R-01 STRAIT at 6 s (1280x720, `--mobile` = 740x340);
`shoot_all.sh` = every shot of 2026-11-10; `contact_sheets.py` = the three sheets. Output on Drive: `References/Art direction 2026-11 - syndicate uniforms/generated/terrain-backdrop-shots-2026-11-10/`.
