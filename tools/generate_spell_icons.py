#!/usr/bin/env python3
"""
Spell Icon Registry and Asset Manager for Diablo 1 Resurrected
Maintains the full list of all 36 base game spells + Hellfire spells,
their IDs, names, categories, and crafted prompt definitions for high-res generation.
"""

import os
import sys

SPELL_REGISTRY = {
    # ID: (Name, Slug, Category, Prompt)
    0: (
        "Attack / Skill", "attack", "Skill",
        "A high resolution dark fantasy RPG skill icon for basic Weapon Attack in the style of Diablo IV and Diablo II Resurrected. A gleaming engraved steel broadsword blade angled diagonally, sharp metallic blade reflecting brilliant edge gleam, runes carved along the fuller, sparks flying against a dark obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    1: (
        "Firebolt", "firebolt", "Fire",
        "A high resolution dark fantasy RPG skill icon for Firebolt in the style of Diablo IV and Diablo II Resurrected. A blazing comet and swirling vortex fireball projectile in deep black void, intensely glowing molten orange and golden yellow flame core, spiraling vortex trail of hellfire, embers, smoke, and fiery sparks flying outwards. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed textures, vibrant magical lighting, no text, borderless art filling the frame."
    ),
    2: (
        "Healing", "healing", "Magic",
        "A high resolution dark fantasy RPG skill icon for Healing spell in the style of Diablo IV and Diablo II Resurrected. A radiant holy glowing white and pale gold sacred cross enclosed within an ornate circular metallic celestial halo ring. Brilliant divine light shining from the center of the cross, ethereal golden and white luminescence radiating against a dark textured obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed textures, vibrant holy lighting, no text, borderless art filling the frame."
    ),
    3: (
        "Lightning", "lightning", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Lightning spell in the style of Diablo IV and Diablo II Resurrected. A violent blinding fork of electric blue-white lightning violently striking downward, crackling electrical plasma arcs, intense azure luminescence and electric sparks discharging against a dark stormy obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed lightning textures and dramatic luminous glow, no text, borderless art filling the frame."
    ),
    4: (
        "Flash", "flash", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Flash spell in the style of Diablo IV and Diablo II Resurrected. A sudden blinding radial blast of azure and white electrical arcane energy erupting outwards, intense circular shockwave of plasma light, electric sparks and disintegrating magical particles against a dark gothic stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    5: (
        "Identify", "identify", "Magic",
        "A high resolution dark fantasy RPG skill icon for Identify spell in the style of Diablo IV and Diablo II Resurrected. An ancient weathered parchment scroll glowing with a mystical all-seeing arcane eye symbol, sapphire blue celestial light rays and ancient glowing revelation runes floating around the manuscript against a dark textured obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    6: (
        "Fire Wall", "fire_wall", "Fire",
        "A high resolution dark fantasy RPG skill icon for Fire Wall spell in the style of Diablo IV and Diablo II Resurrected. A blistering vertical wall of blazing hellfire and roaring flames stretching across the stone floor, towering fire plumes, searing heat distortion, burning embers and thick dark smoke rising against a dark gothic dungeon background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed flame textures, vibrant fiery orange and crimson lighting, no text, borderless art filling the frame."
    ),
    7: (
        "Town Portal", "town_portal", "Magic",
        "A high resolution dark fantasy RPG skill icon for Town Portal spell in the style of Diablo IV and Diablo II Resurrected. A mystical oval interdimensional portal of swirling azure and cyan cosmic energy, rotating blue magical vortex rift emitting ethereal light beams, arcane mist and glowing energy particles into the darkness against a textured dark stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed textures, vibrant blue and cyan arcane lighting, no text, borderless art filling the frame."
    ),
    8: (
        "Stone Curse", "stone_curse", "Magic",
        "A high resolution dark fantasy RPG skill icon for Stone Curse spell in the style of Diablo IV and Diablo II Resurrected. A petrified grey stone face of an agonized screaming human or gargoyle, completely turned into rough cracked granite and weathered stone, petrification cracks, stone dust particles and eerie faint mystic grey energy faintly glowing against a dark textured subterranean stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed cracked rock textures and dramatic moody lighting, no text, borderless art filling the frame."
    ),
    9: (
        "Infravision", "infravision", "Magic",
        "A high resolution dark fantasy RPG skill icon for Infravision in the style of Diablo IV and Diablo II Resurrected. A mystical glowing crimson-red occult all-seeing eye with an elongated black slit pupil, surrounded by pulsating dark blood-red magical energy tendrils, psychic sight haze, and ethereal crimson glow against a dark textured obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed textures, vibrant magical red lighting, no text, borderless art filling the frame."
    ),
    10: (
        "Phasing", "phasing", "Magic",
        "A high resolution dark fantasy RPG skill icon for Phasing spell in the style of Diablo IV and Diablo II Resurrected. A translucent ethereal blue silhouette of a sorcerer phasing out of reality, fading into glowing cosmic vapor, residual cyan energy trails and spatial displacement ripples against a dark gothic stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    11: (
        "Mana Shield", "mana_shield", "Magic",
        "A high resolution dark fantasy RPG skill icon for Mana Shield spell in the style of Diablo IV and Diablo II Resurrected. A shimmering spherical translucent protective energy barrier of deep indigo and cyan arcane magic, geometric celestial protective runes glowing on its surface, faint magical distortion and defensive arcane shield aura guarding against dark shadows against a dark textured stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed crystalline shield textures, vibrant glowing cyan and purple lighting, no text, borderless art filling the frame."
    ),
    12: (
        "Fireball", "fireball", "Fire",
        "A high resolution dark fantasy RPG skill icon for Fireball spell in the style of Diablo IV and Diablo II Resurrected. A massive, explosive blazing demonic fireball sphere hurtling forward, molten magma core glowing white-hot, intense red-orange hellfire flames roaring around it, smoke clouds and blazing embers bursting outward against a dark textured obsidian cavern background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed flame and molten rock textures, vibrant infernal lighting, no text, borderless art filling the frame."
    ),
    13: (
        "Guardian", "guardian", "Fire",
        "A high resolution dark fantasy RPG skill icon for Guardian spell in the style of Diablo IV and Diablo II Resurrected. Three demonic serpent dragon heads made of pure roaring hellfire and molten magma rearing up from a fiery stone fissure, breathing streams of flame, glowing red-hot eyes against a dark gothic dungeon background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    14: (
        "Chain Lightning", "chain_lightning", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Chain Lightning spell in the style of Diablo IV and Diablo II Resurrected. A web of violent, crackling electric blue-white lightning bolts branching and leaping between multiple arcane points, intense electrostatic plasma bursts, vivid azure sparks discharging into the shadowy dark against a dark gothic obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed electrical arcs and intense luminescence, no text, borderless art filling the frame."
    ),
    15: (
        "Flame Wave", "flame_wave", "Fire",
        "A high resolution dark fantasy RPG skill icon for Flame Wave spell in the style of Diablo IV and Diablo II Resurrected. A towering tidal wave wall of roaring hellfire sweeping forward, intense glowing orange flame crest, flying burning embers, smoke, and heat distortion rolling over stone floor against dark gothic background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    16: (
        "Doom Serpents", "doom_serpents", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Doom Serpents spell in the style of Diablo IV and Diablo II Resurrected. Ethereal serpent silhouettes formed of crackling dark blue lightning and storm clouds, twisting viciously in the dark air with glowing electric eyes against dark textured stone. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    17: (
        "Blood Ritual", "blood_ritual", "Magic",
        "A high resolution dark fantasy RPG skill icon for Blood Ritual in the style of Diablo IV and Diablo II Resurrected. An ornate sacrificial blood dagger carved with demonic runes, dark crimson blood dripping from its tip into a glowing pool of red occult energy, dark red necrotic mist rising against dark obsidian stone. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    18: (
        "Nova", "nova", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Nova spell in the style of Diablo IV and Diablo II Resurrected. An expanding circular ring of blinding electric lightning bolts and azure plasma explosions radiating in all directions, intense shockwave of magical electricity against dark gothic dungeon stone floor. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    19: (
        "Invisibility", "invisibility", "Magic",
        "A high resolution dark fantasy RPG skill icon for Invisibility spell in the style of Diablo IV and Diablo II Resurrected. A shadowy hooded rogue figure fading into dark smoke and translucent purple darkness, fading footsteps, subtle distortion of space and soft eerie shadow tendrils against a dark stone wall. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    20: (
        "Inferno", "inferno", "Fire",
        "A high resolution dark fantasy RPG skill icon for Inferno spell in the style of Diablo IV and Diablo II Resurrected. A continuous roaring flamethrower stream of searing orange and yellow hellfire blasting forward from an outstretched gauntleted hand, intense fiery vortex, flying embers and smoke against dark gothic background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    21: (
        "Golem", "golem", "Fire",
        "A high resolution dark fantasy RPG skill icon for Golem summon spell in the style of Diablo IV and Diablo II Resurrected. A massive hulking elemental golem head and shoulders sculpted from cracked ancient stone, hardened clay, and glowing fiery magma veins pulsing between dark rock slabs, burning molten eyes against a dark subterranean cavern background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed heavy rock and magma textures, dramatic lighting, no text, borderless art filling the frame."
    ),
    22: (
        "Rage", "rage", "Magic",
        "A high resolution dark fantasy RPG skill icon for Rage skill in the style of Diablo IV and Diablo II Resurrected. A fierce battle-scarred barbarian warrior face contorted in a savage roar, glowing fiery crimson eyes, bursting red berserker rage veins and glowing blood-red aura aura radiating against dark shadowy background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    23: (
        "Teleport", "teleport", "Magic",
        "A high resolution dark fantasy RPG skill icon for Teleport spell in the style of Diablo IV and Diablo II Resurrected. A mystical deep violet and cosmic blue dimensional rift tearing through reality, geometric arcane space fracture lines, warping ethereal portal distortion, sparkling spatial energy dust against a dark obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed cosmic arcane textures, vibrant purple and blue lighting, no text, borderless art filling the frame."
    ),
    24: (
        "Apocalypse", "apocalypse", "Fire",
        "A high resolution dark fantasy RPG skill icon for Apocalypse spell in the style of Diablo IV and Diablo II Resurrected. Cataclysmic apocalyptic inferno, the stone earth cracking wide open with glowing lava chasms, towering colossal pillars of hellfire and brimstone shooting into the sky, ash and fire rain against dark apocalyptic sky. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    25: (
        "Etherealize", "etherealize", "Magic",
        "A high resolution dark fantasy RPG skill icon for Etherealize spell in the style of Diablo IV and Diablo II Resurrected. A spectral translucent human phantom figure floating in mid-air, ghostly turquoise luminescence, ethereal mist and floating glowing spirit fragments drifting against dark stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    26: (
        "Item Repair", "item_repair", "Skill",
        "A high resolution dark fantasy RPG skill icon for Item Repair warrior skill in the style of Diablo IV and Diablo II Resurrected. A heavy iron blacksmith anvil with a red-hot glowing forged sword blade being struck by an ornate smithing hammer, brilliant orange-gold sparks bursting outward in dark forge atmosphere against dark stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    27: (
        "Staff Recharge", "staff_recharge", "Skill",
        "A high resolution dark fantasy RPG skill icon for Staff Recharge in the style of Diablo IV and Diablo II Resurrected. An ornate weathered wooden sorcerer staff placed diagonally across the frame, its top crystal headpiece bursting with brilliant glowing golden-yellow arcane energy, sharp radiant light rays, magical sparks, and electrical mana recharge embers. Dark textured gothic obsidian stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed wood carving and glowing crystal textures, vibrant magical lighting, no text, borderless art filling the frame."
    ),
    28: (
        "Trap Disarm", "trap_disarm", "Skill",
        "A high resolution dark fantasy RPG skill icon for Trap Disarm rogue skill in the style of Diablo IV and Diablo II Resurrected. Nimble leather-gloved hands holding a delicate bronze lockpick and miniature shear tool, disarming an intricate iron spring trap mechanism with gears, springs and deadly poison needle against dark wooden floor. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    29: (
        "Elemental", "elemental", "Fire",
        "A high resolution dark fantasy RPG skill icon for Elemental spell in the style of Diablo IV and Diablo II Resurrected. A floating fiery spirit elemental face mask sculpted from swirling white-hot flames and molten embers, mystical glowing golden fire eyes, roaring flame tendrils trailing behind against dark obsidian stone. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    30: (
        "Charged Bolt", "charged_bolt", "Lightning",
        "A high resolution dark fantasy RPG skill icon for Charged Bolt spell in the style of Diablo IV and Diablo II Resurrected. Multiple erratic creeping blue and violet electrical sparks skittering along the cracked stone floor, small electric plasma orbs and miniature lightning arcs discharging in zigzag patterns against dark stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    31: (
        "Holy Bolt", "holy_bolt", "Magic",
        "A high resolution dark fantasy RPG skill icon for Holy Bolt spell in the style of Diablo IV and Diablo II Resurrected. A radiant, divine golden-white spear-like projectile of sacred angelic energy flying forward, surrounded by feathery golden light rays, celestial holy runes, and brilliant sunburst luminescence slicing through gothic darkness against a dark textured stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, highly detailed divine holy lighting effects, no text, borderless art filling the frame."
    ),
    32: (
        "Resurrect", "resurrect", "Magic",
        "A high resolution dark fantasy RPG skill icon for Resurrect spell in the style of Diablo IV and Diablo II Resurrected. Reverent glowing open hands reaching upward towards a warm heavenly golden light shaft, a radiant glowing soul rising from darkness with angelic feathery aura and warm healing particles against dark gothic background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    33: (
        "Telekinesis", "telekinesis", "Magic",
        "A high resolution dark fantasy RPG skill icon for Telekinesis spell in the style of Diablo IV and Diablo II Resurrected. An ethereal translucent cyan mystical hand reaching out, surrounded by swirling psionic force rings, floating stone debris and glowing blue telekinetic energy aura lifting objects against dark stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    34: (
        "Heal Other", "heal_other", "Magic",
        "A high resolution dark fantasy RPG skill icon for Heal Other spell in the style of Diablo IV and Diablo II Resurrected. A priest's open benevolent palm bestowing a gentle glowing orb of warm golden divine light, soothing amber energy waves radiating outwards in an aura of restorative grace against dark gothic background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    35: (
        "Blood Star", "blood_star", "Magic",
        "A high resolution dark fantasy RPG skill icon for Blood Star spell in the style of Diablo IV and Diablo II Resurrected. A sinister pulsating dark crimson crystal star spinning in dark void, trailing streams of deep ruby-red blood magic, dark occult energy veins and scarlet sparks radiating outward against dark textured stone background. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    36: (
        "Bone Spirit", "bone_spirit", "Magic",
        "A high resolution dark fantasy RPG skill icon for Bone Spirit spell in the style of Diablo IV and Diablo II Resurrected. A terrifying spectral human skull formed of aged bone and translucent turquoise ghost fire, screaming mouth trailing long wisps of ethereal cyan ectoplasm smoke and ghostly graveyard luminescence against dark black gothic void. Centered square composition, painted digital dark fantasy illustration, gothic atmosphere, no text, borderless art filling the frame."
    ),
    37: ("Mana", "mana", "Magic", "Arcane star wheel restoring mana"),
    38: ("the Magi", "magi", "Magic", "Spiked celestial wheel of the magi"),
    39: ("the Jester", "jester", "Magic", "Sinister bronze jester mask with chaos aura"),
    40: ("Lightning Wall", "lightning_wall", "Lightning", "Towering crackling electrical barrier wall"),
    41: ("Immolation", "immolation", "Fire", "Cataclysmic molten magma firestorm eruption"),
    42: ("Warp", "warp", "Magic", "Spatiotemporal vortex ripping space-time"),
    43: ("Reflect", "reflect", "Magic", "Crystalline arcane mirror shield deflecting spells"),
    44: ("Berserk", "berserk", "Magic", "Demonic horned skull with blazing red berserker rage"),
    45: ("Ring of Fire", "ring_of_fire", "Fire", "Blazing circle of roaring hellfire flames"),
    46: ("Search", "search", "Magic", "Occult arcane eye disc illuminating hidden runes and treasures"),
    47: ("Rune of Fire", "rune_of_fire", "Fire", "Ancient granite runestone trap with blazing fire rune"),
    48: ("Rune of Light", "rune_of_light", "Lightning", "Ancient granite runestone trap with electric lightning rune"),
    49: ("Rune of Nova", "rune_of_nova", "Lightning", "Ancient granite runestone trap with pulsing nova rune"),
    50: ("Rune of Immolation", "rune_of_immolation", "Fire", "Ancient granite runestone trap with molten immolation rune"),
    51: ("Rune of Stone", "rune_of_stone", "Magic", "Ancient granite runestone trap with petrifying stone rune"),
}

def print_status():
    assets_dir = "assets/skills"
    os.makedirs(assets_dir, exist_ok=True)
    
    total = len(SPELL_REGISTRY)
    done = 0
    print(f"{'ID':<4} {'Name':<20} {'Category':<12} {'Status'}")
    print("-" * 50)
    for spell_id, (name, slug, category, _) in sorted(SPELL_REGISTRY.items()):
        path_id = os.path.join(assets_dir, f"{spell_id}.png")
        path_slug = os.path.join(assets_dir, f"{slug}.png")
        is_done = os.path.exists(path_id) or os.path.exists(path_slug)
        if is_done:
            done += 1
            status = "✓ READY"
        else:
            status = "PENDING"
        print(f"{spell_id:<4} {name:<20} {category:<12} {status}")
    print("-" * 50)
    print(f"Total: {done}/{total} high-res icons installed ({done/total*100:.1f}%)")

if __name__ == "__main__":
    print_status()
