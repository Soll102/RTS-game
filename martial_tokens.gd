extends RefCounted
## Hallmark component redesign / inherited mineral-jade system / no spatial motion.
## Pre-emit critique: Philosophy 5, Hierarchy 4, Execution 4, Specificity 5, Restraint 5, Variety 4.
const INK=Color("263c32")
const SEAL_INK=Color("1e3026")
const BANNER=Color("354b40")
const EDGE=Color("8d9475")
const TEXT=Color("eee3c5")
const SECONDARY=Color("c8cdb5")
const MARCH=Color("d4d7bd")
const FERRY=Color("aebdad")
const SUPPLY=Color("94ae86")
const CINNABAR=Color("d29b82")
const MORALE=Color("afbf91")
const FACTION={"wei":Color("879b93"),"shu":Color("97a17d"),"wu":Color("b69179")}
const FACTION_LETTER={"wei":"W","shu":"S","wu":"U"}
const TYPE_NAME={"infantry":"INF","archers":"ARC","cavalry":"CAV","siege":"SIE"}
const STROKE=1.25
const HUD_SIZE=Vector2(72,32)
const HUD_SPACING=80.0
const MARCH_PATTERN=Vector2(11,7)
const FERRY_PATTERN=Vector2(18,9)
const SUPPLY_PATTERN=Vector2(2,8)
const CHEVRON_SPACING=30.0
static func route_color(order: String, kind: String, purpose: String) -> Color:
	if purpose=="supply":return SUPPLY
	if kind=="ferry":return FERRY
	return CINNABAR if order in ["retreat","attack","siege"] else MARCH
