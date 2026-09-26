class_name NameGenerator
## Generates playful, original bot names like "CuLuoi_42" or "SoiNinja".

const FIRST := [
	"Cao", "Gau", "Meo", "Soi", "Cu", "Rua", "Ho", "Khi", "Vit", "Ga", "Heo", "Tho",
	"Chuot", "Nai", "Ca", "Oc", "Bao", "Ech", "Doi", "Cop", "Sau", "Te", "Nhim",
]
const SECOND := [
	"Luoi", "Nhanh", "Ngao", "Lieu", "Li", "Xin", "Beo", "Ninja", "Buon", "Gian",
	"Kho", "Tron", "Lac", "Du", "Hien", "Dien", "Mu", "Sieu", "Bi", "Lanh",
]


static func generate(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for attempt in 30:
		var n: String = FIRST[rng.randi() % FIRST.size()] + SECOND[rng.randi() % SECOND.size()]
		if rng.randf() < 0.6:
			n += "_" + str(rng.randi_range(1, 99))
		if not used.has(n):
			used[n] = true
			return n
	return "Bot_%d" % rng.randi_range(100, 999)
