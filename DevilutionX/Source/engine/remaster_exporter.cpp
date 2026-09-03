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

#include "engine/assets.hpp"
#include "engine/clx_sprite.hpp"
#include "engine/dx.h"
#include "engine/load_cel.hpp"
#include "engine/load_cl2.hpp"
#include "engine/palette.h"
#include "engine/render/clx_render.hpp"
#include "engine/surface.hpp"
#include "utils/log.hpp"
#include "utils/png.h"

namespace fs = std::filesystem;

namespace devilution {

namespace {

void ExportAndUpscaleCl2(const std::string &assetPath, uint16_t widthHint = 128)
{
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

	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
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

	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
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
	ExportPlayerClass("sorcerer", 's');
	ExportPlayerClass("monk", 'm');
	ExportPlayerClass("barbarian", 'a');
	ExportPlayerClass("bard", 'b');

	// 2. ALL TRISTRAM TOWN RESIDENTS
	Log("--- Remastering Town Residents ---");
	ExportAndUpscaleCl2("towners\\cain\\cain", 96);
	ExportAndUpscaleCl2("towners\\blacksm\\blacksm", 96);
	ExportAndUpscaleCl2("towners\\witch\\witch", 96);
	ExportAndUpscaleCl2("towners\\healer\\healer", 96);
	ExportAndUpscaleCl2("towners\\pegboy\\pegboy", 96);
	ExportAndUpscaleCl2("towners\\tavern\\tavern", 96);
	ExportAndUpscaleCl2("towners\\barmaid\\barmaid", 96);
	ExportAndUpscaleCl2("towners\\drunk\\drunk", 96);
	ExportAndUpscaleCl2("towners\\twnf\\twnf", 96);

	// 3. ALL ICONIC BOSSES & MONSTERS
	Log("--- Remastering Bosses & Monsters ---");
	ExportMonsterFamily("fatc\\fatc", 128);       // The Butcher
	ExportMonsterFamily("sking\\sking", 160);     // Skeleton King (Leoric)
	ExportMonsterFamily("diablo\\diablo", 160);   // Diablo
	ExportMonsterFamily("zombie\\zombie", 128);   // Zombies
	ExportMonsterFamily("skelaxe\\sklax", 128);   // Skeleton Axe
	ExportMonsterFamily("falsword\\fall", 128);   // Fallen Sword
	ExportMonsterFamily("falspear\\phall", 128);  // Fallen Spear
	ExportMonsterFamily("skelbow\\sklbw", 128);   // Skeleton Bow
	ExportMonsterFamily("scav\\scav", 128);       // Scavengers
	ExportMonsterFamily("goatlord\\goat", 128);   // Goat Men
	ExportMonsterFamily("succ\\succ", 128);       // Succubus
	ExportMonsterFamily("knight\\kngt", 128);     // Black Knights
	ExportMonsterFamily("gargoyle\\garg", 128);   // Gargoyles
	ExportMonsterFamily("mage\\mage", 128);       // Mages
	ExportMonsterFamily("viper\\viper", 128);     // Vipers
	ExportMonsterFamily("golem\\golem", 128);     // Golems
	ExportMonsterFamily("bat\\bat", 128);         // Bats
	ExportMonsterFamily("spit\\spit", 128);       // Spitting Terrors
	ExportMonsterFamily("worm\\worm", 128);       // Lava Worms
	ExportMonsterFamily("magma\\magma", 128);     // Magma Demons
	ExportMonsterFamily("overlord\\over", 128);   // Overlords
	ExportMonsterFamily("unravel\\unrav", 128);   // Unravelers

	// 4. INVENTORY ITEMS, WEAPONS & SPELLS
	Log("--- Remastering Inventory Icons & Spells ---");
	ExportAndUpscaleCel("data\\inv\\objcurs", 56);
	ExportAndUpscaleCel("data\\inv\\spelli2", 56);

	Log("========================================================");
	Log("   4x-UltraSharp Full AI Remastering Completed!         ");
	Log("========================================================");
}

} // namespace devilution
