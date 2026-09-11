#pragma once

#include "engine/clx_sprite.hpp"
#include "engine/surface.hpp"
#include "spelldat.h"

namespace devilution {

void InitSpellBook();
void FreeSpellBook();
void CheckSBook();
void DrawSpellBook(const Surface &out);
SpellID GetSpellFromSpellPage(size_t page, size_t entry);
SpellType GetSBookTrans(SpellID ii, bool townok);

} // namespace devilution
