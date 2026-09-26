class_name MapCamera
## Camera pitch per map (maps 4.2, the Alpha 11 classics and maps 4.3 classic), in degrees above the horizon: from 58 (bird's-eye, Daniele Alpha 18: "a bit
## more from the top") up to the lowest angle at which the smallest node tap target reaches 44 pt (Apple's
## guideline) on a landscape phone (844 x 390 pt) with no badge overflowing or colliding. From the phone-fit
## probe (tests/phone_fit.tscn) - rerun it and regenerate this table after a map pack changes. On maps 4.2
## every map already reaches 45-66 pt at 58 degrees; the Alpha 11 classics A-01..A-04 56-88 pt.
const PITCH := {
	"A-01": 58.0,
	"A-02": 58.0,
	"A-03": 58.0,
	"A-04": 58.0,
	"B-01": 58.0,
	"B-02": 58.0,
	"B-03": 58.0,
	"B-04": 58.0,
	"B-05": 58.0,
	"C-01": 58.0,
	"C-02": 58.0,
	"C-03": 58.0,
	"C-04": 58.0,
	"C-05": 58.0,
	"D-01": 58.0,
	"D-02": 58.0,
	"D-03": 58.0,
	"S-01": 58.0,
	"S-02": 58.0,
	"S-03": 58.0,
	"S-04": 58.0,
	"S-05": 58.0,
	"T-01": 58.0,
	"T-02": 58.0,
	"M-01": 58.0,
	"M-02": 58.0,
	"M-03": 58.0,
	"M-04": 58.0,
	"M-05": 58.0,
	"M-06": 58.0,
	"M-07": 58.0,
	"M-08": 58.0,
	"M-09": 58.0,
	"M-10": 58.0,
	"M-11": 58.0,
	"M-12": 58.0,
	"M-13": 58.0,
	"M-14": 58.0,
	"M-15": 58.0,
	"M-16": 58.0,
	"M-17": 58.0,
	"M-18": 58.0,
	"M-19": 58.0,
	"M-20": 58.0,
}


static func pitch_for(code: String) -> float:
	return PITCH.get(code, Rules.CAM_PITCH)
