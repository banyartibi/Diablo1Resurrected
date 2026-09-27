/**
 * @file remaster_exporter.cpp
 *
 * Full Master 4x-UltraSharp AI sprite export and remastering pipeline.
 */
#include "engine/remaster_exporter.hpp"

#include <SDL.h>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

#include "cursor.h"
#include "engine/assets.hpp"
#include "engine/clx_sprite.hpp"
#include "engine/dx.h"
#include "engine/load_cel.hpp"
#include "engine/load_cl2.hpp"
#include "engine/palette.h"
#include "engine/render/clx_render.hpp"
#include "engine/surface.hpp"
#include "misdat.h"
#include "objdat.h"
#include "utils/log.hpp"
#include "utils/png.h"

namespace fs = std::filesystem;

namespace devilution {

namespace {

void ExportAndUpscaleCl2(const std::string &assetPath, uint16_t widthHint = 128)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	if (fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCl2 = assetPath + ".cl2";
	AssetRef ref = FindAsset(fullCl2.c_str());
	if (!ref.ok()) {
		return;
	}

	Log("========================================================");
	Log("Processing Asset: {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCl2ListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	// Get system palette
	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			// Convert to 32-bit RGBA
			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0; // Transparent
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	// Run 4x-UltraSharp on GPU!
	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportAndUpscaleCel(const std::string &assetPath, uint16_t widthHint = 128)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	if (fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCel = assetPath + ".cel";
	AssetRef ref = FindAsset(fullCel.c_str());
	if (!ref.ok()) {
		return;
	}

	Log("========================================================");
	Log("Processing CEL Asset: {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCelListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0;
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled CEL asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportAndUpscaleCelWidths(const std::string &assetPath, const uint16_t *widths)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	if (fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCel = assetPath + ".cel";
	AssetRef ref = FindAsset(fullCel.c_str());
	if (!ref.ok()) {
		return;
	}

	Log("========================================================");
	Log("Processing CEL Asset (Variable Widths): {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCelListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widths));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0;
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled CEL asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportMonsterFamily(const std::string &basePrefix, uint16_t widthHint)
{
	const char *actions[] = { "a", "d", "h", "s", "w", "t" };
	for (const char *act : actions) {
		ExportAndUpscaleCl2("monsters\\" + basePrefix + act, widthHint);
	}
}

void ExportPlayerClass(const char *classDir, char classChar)
{
	const char armors[] = { 'a', 'l', 'm', 'h' };
	const char weapons[] = { 'n', 's', 'a', 'b', 'm', 't', 'u', 'd', 'h' };
	const char *actions[] = { "as", "st", "aw", "wl", "at", "ht", "lm", "fm", "qm", "dt", "bl" };

	for (char a : armors) {
		for (char w : weapons) {
			char prefix[4] = { classChar, a, w, '\0' };
			for (const char *act : actions) {
				std::string path = "plrgfx\\" + std::string(classDir) + "\\" + prefix + "\\" + prefix + act;
				ExportAndUpscaleCl2(path, 128);
			}
		}
	}
}

} // namespace

void RemasterWarriorClass()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp Warrior HD Remastering        ");
	Log("========================================================");
	ExportPlayerClass("warrior", 'w');
}

void RunRemasterAssetPipeline()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp Full Master AI Remastering    ");
	Log("========================================================");

	// 1. ALL PLAYER CLASSES (Warrior, Rogue, Sorcerer, Monk, Barbarian, Bard)
	Log("--- Remastering Player Classes ---");
	ExportPlayerClass("warrior", 'w');
	ExportPlayerClass("rogue", 'r');
	ExportPlayerClass("sorceror", 's'); // Diablo 1 MPQ directory is 'sorceror'
	ExportPlayerClass("monk", 'm');
	ExportPlayerClass("barbarian", 'a');
	ExportPlayerClass("bard", 'b');

	// 2. ALL TRISTRAM TOWN RESIDENTS & ANIMALS
	Log("--- Remastering Town Residents ---");
	ExportAndUpscaleCel("towners\\smith\\smithn", 96);
	ExportAndUpscaleCel("towners\\twnf\\twnfn", 96);
	ExportAndUpscaleCel("towners\\butch\\deadguy", 96);
	ExportAndUpscaleCel("towners\\townwmn1\\witch", 96);
	ExportAndUpscaleCel("towners\\townwmn1\\wmnn", 96);
	ExportAndUpscaleCel("towners\\townboy\\pegkid1", 96);
	ExportAndUpscaleCel("towners\\healer\\healer", 96);
	ExportAndUpscaleCel("towners\\strytell\\strytell", 96);
	ExportAndUpscaleCel("towners\\drunk\\twndrunk", 96);
	ExportAndUpscaleCel("towners\\farmer\\farmrn2", 96);
	ExportAndUpscaleCel("towners\\girl\\girlw1", 96);
	ExportAndUpscaleCel("towners\\girl\\girls1", 96);
	ExportAndUpscaleCel("towners\\farmer\\mfrmrn2", 96);
	ExportAndUpscaleCel("towners\\animals\\cow", 128);

	// 3. ALL 57 MONSTER FAMILIES
	Log("--- Remastering Monster Families ---");
	ExportMonsterFamily("acid\\acid", 128);
	ExportMonsterFamily("antworm\\worm", 192);
	ExportMonsterFamily("bat\\bat", 96);
	ExportMonsterFamily("bigfall\\fallg", 128);
	ExportMonsterFamily("black\\black", 160);
	ExportMonsterFamily("bspidr\\bspidr", 148);
	ExportMonsterFamily("bubba\\bubba", 154);
	ExportMonsterFamily("byclps\\byclps", 180);
	ExportMonsterFamily("clasp\\clasp", 176);
	ExportMonsterFamily("darkmage\\dmage", 128);
	ExportMonsterFamily("demskel\\demskl", 128);
	ExportMonsterFamily("diablo\\diablo", 160);
	ExportMonsterFamily("eye2\\eye2", 140);
	ExportMonsterFamily("eye\\eye", 156);
	ExportMonsterFamily("falspear\\phall", 128);
	ExportMonsterFamily("falsword\\fall", 128);
	ExportMonsterFamily("fat\\fat", 128);
	ExportMonsterFamily("fatc\\fatc", 128);
	ExportMonsterFamily("fireman\\firem", 128);
	ExportMonsterFamily("flesh\\flesh", 164);
	ExportMonsterFamily("fork\\fork", 188);
	ExportMonsterFamily("gargoyle\\gargo", 160);
	ExportMonsterFamily("goatbow\\goatb", 128);
	ExportMonsterFamily("goatlord\\goatl", 160);
	ExportMonsterFamily("goatmace\\goat", 128);
	ExportMonsterFamily("golem\\golem", 96);
	ExportMonsterFamily("gravdg\\gravdg", 124);
	ExportMonsterFamily("hellbat2\\bhelbt", 96);
	ExportMonsterFamily("hellbat\\helbat", 96);
	ExportMonsterFamily("hellbug\\hellbg", 198);
	ExportMonsterFamily("horkd\\horkd", 138);
	ExportMonsterFamily("lich2\\lich2", 136);
	ExportMonsterFamily("lich\\lich", 96);
	ExportMonsterFamily("mage\\mage", 128);
	ExportMonsterFamily("magma\\magma", 128);
	ExportMonsterFamily("mega\\mega", 160);
	ExportMonsterFamily("nkr\\nkr", 226);
	ExportMonsterFamily("rat\\rat", 104);
	ExportMonsterFamily("reaper\\reap", 180);
	ExportMonsterFamily("rhino\\rhino", 160);
	ExportMonsterFamily("scav\\scav", 128);
	ExportMonsterFamily("scorp\\scorp", 64);
	ExportMonsterFamily("skelaxe\\sklax", 128);
	ExportMonsterFamily("skelbow\\sklbw", 128);
	ExportMonsterFamily("skelsd\\sklsr", 128);
	ExportMonsterFamily("sking\\sking", 160);
	ExportMonsterFamily("snake\\snake", 160);
	ExportMonsterFamily("sneak\\sneak", 128);
	ExportMonsterFamily("spawn\\spawn", 164);
	ExportMonsterFamily("spider\\spider", 148);
	ExportMonsterFamily("succ\\scbs", 128);
	ExportMonsterFamily("thin\\thin", 160);
	ExportMonsterFamily("tsneak\\tsneak", 128);
	ExportMonsterFamily("unrav\\unrav", 96);
	ExportMonsterFamily("worm\\worm", 160);
	ExportMonsterFamily("wscorp\\wscorp", 86);
	ExportMonsterFamily("zombie\\zombie", 128);

	// 4. INVENTORY ITEMS, WEAPONS & SPELLS
	Log("--- Remastering Inventory Icons & Spells ---");
	ExportAndUpscaleCelWidths("data\\inv\\objcurs", InvItemWidth1);
	ExportAndUpscaleCelWidths("data\\inv\\objcurs2", InvItemWidth2);
	ExportAndUpscaleCel("data\\spelli2", 37);
	ExportAndUpscaleCel("data\\spelicon", 56);
	ExportAndUpscaleCel("data\\spellbk", 320);
	ExportAndUpscaleCel("data\\spellbkb", 76);

	// 5. INTERACTIVE OBJECTS (Chests, Barrels, Torches, Doors, Shrines, Altars)
	Log("--- Remastering Interactive Objects ---");
	uint16_t objectWidths[65] = {};
	for (const ObjectData &objectData : AllObjects) {
		if (objectData.ofindex >= 0 && objectData.ofindex < 65 && objectData.animWidth > 0) {
			objectWidths[objectData.ofindex] = objectData.animWidth;
		}
	}
	for (int i = 0; i < 65; i++) {
		if (objectWidths[i] > 0) {
			std::string path = "objects\\" + std::string(ObjMasterLoadList[i]);
			ExportAndUpscaleCel(path, objectWidths[i]);
		}
	}

	// 6. MISSILES & PROJECTILES (Spells, Arrows, Fireballs, Lightning, Portals)
	Log("--- Remastering Missiles & Projectiles ---");
	for (size_t mi = 0; MissileSpriteData[mi].animFAmt != 0; mi++) {
		const auto &ms = MissileSpriteData[mi];
		if (ms.name[0] == '\0')
			continue;
		if (ms.animFAmt == 1) {
			std::string path = "missiles\\" + std::string(ms.name);
			ExportAndUpscaleCl2(path, ms.animWidth);
		} else {
			for (size_t i = 1; i <= ms.animFAmt; i++) {
				std::string path = "missiles\\" + std::string(ms.name) + std::to_string(i);
				ExportAndUpscaleCl2(path, ms.animWidth);
			}
		}
	}

	// 7. LEVEL SPECIALS (Doors, Stairs, Traps)
	Log("--- Remastering Level Specials ---");
	ExportAndUpscaleCel("levels\\towndata\\towns", 64);
	ExportAndUpscaleCel("levels\\l1data\\l1s", 64);
	ExportAndUpscaleCel("levels\\l2data\\l2s", 64);
	ExportAndUpscaleCel("nlevels\\l5data\\l5s", 64);

	Log("========================================================");
	Log("   4x-UltraSharp Full AI Remastering Completed!         ");
	Log("========================================================");
}

} // namespace devilution
