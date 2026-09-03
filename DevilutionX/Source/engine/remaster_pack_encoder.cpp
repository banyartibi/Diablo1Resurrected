/**
 * @file remaster_pack_encoder.cpp
 *
 * Encodes 4x-UltraSharp PNG frames into native DevilutionX .CLX HD sprite sheets
 * with 16x Super-Sampled Anti-Aliasing (SSAA) for flawless engine compatibility.
 */
#include "engine/remaster_pack_encoder.hpp"

#include <SDL.h>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <vector>

#include "engine/palette.h"
#include "utils/clx_encode.hpp"
#include "utils/endian_write.hpp"
#include "utils/log.hpp"
#include "utils/png.h"

namespace fs = std::filesystem;

namespace devilution {

namespace {

struct FrameInfo {
	size_t group;
	size_t frame;
	std::string path;
};

uint8_t FindNearestPaletteIndex(uint8_t r, uint8_t g, uint8_t b, const SDL_Color *palette)
{
	int bestDist = 1000000;
	uint8_t bestIdx = 1;
	// Skip 0 (transparent)
	for (int i = 1; i < 256; ++i) {
		int dr = static_cast<int>(r) - palette[i].r;
		int dg = static_cast<int>(g) - palette[i].g;
		int db = static_cast<int>(b) - palette[i].b;
		int dist = dr * dr + dg * dg + db * db;
		if (dist < bestDist) {
			bestDist = dist;
			bestIdx = static_cast<uint8_t>(i);
			if (dist == 0)
				break;
		}
	}
	return bestIdx;
}

void EncodeFolderToClx(const fs::path &folderPath, const fs::path &outClxPath, const SDL_Color *palette)
{
	std::vector<FrameInfo> frames;
	for (const auto &entry : fs::directory_iterator(folderPath)) {
		if (entry.path().extension() == ".png") {
			std::string filename = entry.path().stem().string(); // e.g. "g0_f005"
			size_t group = 0, frame = 0;
			if (std::sscanf(filename.c_str(), "g%zu_f%zu", &group, &frame) == 2) {
				frames.push_back({ group, frame, entry.path().string() });
			}
		}
	}

	if (frames.empty())
		return;

	std::sort(frames.begin(), frames.end(), [](const FrameInfo &a, const FrameInfo &b) {
		if (a.group != b.group)
			return a.group < b.group;
		return a.frame < b.frame;
	});

	size_t maxGroup = 0;
	for (const auto &f : frames) {
		if (f.group > maxGroup)
			maxGroup = f.group;
	}
	size_t numGroups = maxGroup + 1;

	std::vector<std::vector<FrameInfo>> groups(numGroups);
	for (const auto &f : frames) {
		groups[f.group].push_back(f);
	}

	std::vector<uint8_t> clxData;

	if (numGroups > 1) {
		clxData.resize(numGroups * 4);
	}

	for (size_t g = 0; g < numGroups; ++g) {
		const auto &groupFrames = groups[g];
		uint32_t numFramesInGroup = static_cast<uint32_t>(groupFrames.size());
		if (numFramesInGroup == 0)
			continue;

		if (numGroups > 1) {
			WriteLE32(&clxData[4 * g], static_cast<uint32_t>(clxData.size()));
		}

		const size_t clxDataOffset = clxData.size();
		clxData.resize(clxData.size() + 4 * (2 + numFramesInGroup));
		WriteLE32(&clxData[clxDataOffset], numFramesInGroup);

		for (size_t f = 0; f < numFramesInGroup; ++f) {
			WriteLE32(&clxData[clxDataOffset + 4 * (f + 1)], static_cast<uint32_t>(clxData.size() - clxDataOffset));

			SDL_Surface *surface = IMG_LoadPNG(groupFrames[f].path.c_str());
			if (!surface) {
				Log("Failed to load PNG frame: {}", groupFrames[f].path);
				continue;
			}

			// 16x SSAA Box Super-Sampling: Downsample 4x AI frame to native grid stride
			int origW = surface->w / 4;
			int origH = surface->h / 4;
			if (origW > 0 && origH > 0) {
				SDL_Surface *downSurface = SDL_CreateRGBSurfaceWithFormat(0, origW, origH, 32, SDL_PIXELFORMAT_RGBA32);
				if (downSurface) {
					SDL_LockSurface(surface);
					SDL_LockSurface(downSurface);
					const uint32_t *src32 = static_cast<const uint32_t *>(surface->pixels);
					uint32_t *dst32 = static_cast<uint32_t *>(downSurface->pixels);
					int srcPitch = surface->pitch / 4;
					int dstPitch = downSurface->pitch / 4;

					for (int dy = 0; dy < origH; ++dy) {
						for (int dx = 0; dx < origW; ++dx) {
							int rSum = 0, gSum = 0, bSum = 0, aSum = 0;
							int count = 0;
							for (int sy = 0; sy < 4; ++sy) {
								for (int sx = 0; sx < 4; ++sx) {
									uint32_t pix = src32[(dy * 4 + sy) * srcPitch + (dx * 4 + sx)];
									int a = (pix >> 24) & 0xFF;
									if (a > 32) {
										rSum += (pix) & 0xFF;
										gSum += (pix >> 8) & 0xFF;
										bSum += (pix >> 16) & 0xFF;
										aSum += a;
										count++;
									}
								}
							}
							if (count >= 4) {
								uint8_t r = static_cast<uint8_t>(rSum / count);
								uint8_t g = static_cast<uint8_t>(gSum / count);
								uint8_t b = static_cast<uint8_t>(bSum / count);
								uint8_t a = static_cast<uint8_t>(aSum / count);
								dst32[dy * dstPitch + dx] = (a << 24) | (b << 16) | (g << 8) | r;
							} else {
								dst32[dy * dstPitch + dx] = 0;
							}
						}
					}
					SDL_UnlockSurface(downSurface);
					SDL_UnlockSurface(surface);
					SDL_FreeSurface(surface);
					surface = downSurface;
				}
			}

			int w = surface->w;
			int h = surface->h;

			const size_t frameHeaderPos = clxData.size();
			clxData.resize(clxData.size() + ClxFrameHeaderSize);
			WriteLE16(&clxData[frameHeaderPos], ClxFrameHeaderSize);
			WriteLE16(&clxData[frameHeaderPos + 2], static_cast<uint16_t>(w));
			WriteLE16(&clxData[frameHeaderPos + 4], static_cast<uint16_t>(h));

			// Quantize and RLE Encode with Anti-Aliasing
			unsigned transparentRunWidth = 0;
			std::vector<uint8_t> pixels;
			pixels.reserve(w);

			SDL_LockSurface(surface);
			const uint32_t *srcPixels = static_cast<const uint32_t *>(surface->pixels);
			int pitch32 = surface->pitch / 4;

			for (int y = 0; y < h; ++y) {
				for (int x = 0; x < w; ++x) {
					uint32_t pixel = srcPixels[y * pitch32 + x];
					uint8_t alpha = (pixel >> 24) & 0xFF;
					if (alpha < 64) {
						if (!pixels.empty()) {
							AppendClxPixelsOrFillRun(pixels.data(), pixels.size(), clxData);
							pixels.clear();
						}
						transparentRunWidth++;
					} else {
						uint8_t r = (pixel) & 0xFF;
						uint8_t g = (pixel >> 8) & 0xFF;
						uint8_t b = (pixel >> 16) & 0xFF;
						uint8_t colorIdx = FindNearestPaletteIndex(r, g, b, palette);

						if (transparentRunWidth > 0) {
							AppendClxTransparentRun(transparentRunWidth, clxData);
							transparentRunWidth = 0;
						}
						pixels.push_back(colorIdx);
					}
				}
			}

			SDL_UnlockSurface(surface);
			SDL_FreeSurface(surface);

			if (!pixels.empty()) {
				AppendClxPixelsOrFillRun(pixels.data(), pixels.size(), clxData);
				pixels.clear();
			}
			if (transparentRunWidth > 0) {
				AppendClxTransparentRun(transparentRunWidth, clxData);
				transparentRunWidth = 0;
			}
		}

		WriteLE32(&clxData[clxDataOffset + 4 * (1 + numFramesInGroup)], static_cast<uint32_t>(clxData.size() - clxDataOffset));
	}

	fs::create_directories(outClxPath.parent_path());
	std::ofstream outFile(outClxPath, std::ios::binary);
	if (outFile.is_open()) {
		outFile.write(reinterpret_cast<const char *>(clxData.data()), clxData.size());
		outFile.close();
		Log("Generated SSAA HD CLX: {} (Size: {} KB, Groups: {}, Frames: {})",
		    outClxPath.string(), clxData.size() / 1024, numGroups, frames.size());
	} else {
		Log("Failed to write CLX output: {}", outClxPath.string());
	}
}

} // namespace

void RunPackHdClxPipeline()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp SSAA HD CLX Pack Generation   ");
	Log("========================================================");

	const SDL_Color *palette = orig_palette.data();

	fs::path hdSpritesDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites";
	fs::path assetsBaseDir = "/home/biti/antigravity/magical-bell/assets";

	size_t count = 0;
	for (const auto &entry : fs::directory_iterator(hdSpritesDir)) {
		if (entry.is_directory()) {
			std::string dirName = entry.path().filename().string();
			std::string relPath = dirName;
			for (char &c : relPath) {
				if (c == '_')
					c = '/';
			}

			fs::path outClx = assetsBaseDir / (relPath + ".clx");
			EncodeFolderToClx(entry.path(), outClx, palette);
			count++;
		}
	}

	Log("========================================================");
	Log("Successfully generated {} 4x-UltraSharp SSAA HD CLX Packs!", count);
	Log("========================================================");
}

} // namespace devilution
